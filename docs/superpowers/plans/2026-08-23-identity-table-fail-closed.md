# Identity Table Fail-Closed Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `setup_env.sh` refuse to provision a machine when `config/profiles.sh` did not load, instead of continuing with `PROFILE=unknown` and zero `HAS_*`.

**Architecture:** `lib/detect_env.sh:23` currently discards the exit status of the `source` that loads the identity table. Three changes: propagate that status and record a `_PROFILES_LOADED` sentinel; have `setup_env.sh:61` read it and abort every workflow except the two read-only reporters; and give `_doctor_check_profile` a third branch on the sentinel so `doctor` does not regress into reporting a stale inherited `PROFILE` as a PASS.

**Tech Stack:** bash 5, bats-core, existing `tests/mocks/` PATH mocks.

**Spec:** [`2026-08-23-profiles-bash-version-guard-design.md`](../specs/2026-08-23-profiles-bash-version-guard-design.md) — four Multi-Lens Review rounds; the bash-version guard it originally proposed was cut and is a backlog row.

## Global Constraints

- Never `env -i` in a test. `env -i` clears `PATH`, so bash resolves via the confstr default and a mac gets `/bin/bash` 3.2.57 — reintroducing the exact class this spec declared out of scope. Clear identity names explicitly instead: `unset "${!HAS_@}" PROFILE STUDIO`.
- Every test keeps a `PATH` that resolves bash 5 **and** reaches `tests/mocks`, and pins the hostname with `MOCK_HOSTNAME_OUTPUT` + `MOCK_UNAME_S`, per `tests/setup_env/profiles.bats:50-53`. Without the mock a `PROFILE` assertion is host-specific and `ubuntu-latest` yields `unknown`.
- Never `chmod 000` the tracked `config/profiles.sh`. Its failing path leaves the file unreadable and `.zprofile` sources it through `config/profiles.zsh`, breaking every subsequent login shell. Copy `lib/detect_env.sh` and `config/profiles.sh` into a fixture tree and break the copy — the relative path `$(dirname "${BASH_SOURCE[0]}")/../config/profiles.sh` resolves against the copy.
- `_PROFILES_LOADED` is never `export`ed. Its safety comes from the unconditional `=0` on entry to `detect_env` plus `detect_env` always running before `run_doctor`, **not** from non-export — an environment-supplied value defeats the read, and T7 pins that.
- Any test that executes `setup_env.sh -t update` must assert `command -v brew` resolves under `tests/mocks` **before** invoking it. `run_update` calls `brew_update` then `sudo -H softwareupdate --install --all` (`lib/workflows.sh:325-334`); a wrong `PATH` makes the test destructive rather than merely wrong. `ssh` is absent from the 66 mocks and `sync_git_repos.sh` does real `git push`/`rsync --delete` later in that workflow.
- `bats -f <filter>` with no match is not uniformly a hard error across bats 1.10.0 (CI) and 1.14.0 (local), so every per-test gate pairs the run with `grep -q '^ok '`.

- **No task's `acceptance:` block runs `make test`.** Measured 2026-08-23 during execution: the Bash tool hard-caps at **600000 ms** and a clean, uncontended `make test` for this repo exceeds it (killed at exit 143 having reached ~1351 of 1466 tests). A subagent therefore *cannot* run the aggregate gate to completion, and an implementer told to do so either backgrounds it and strands itself or reports a timeout as a defect. Tasks carry scoped commands that answer only for their own files; **the orchestrator runs `make test` once after each task**, uncontended, and that single run is the gate. This is the rule `subagent-driven-development` already states for shared-worktree waves, applied here for a different reason — a tool ceiling rather than sibling interference. It does not weaken `writing-plans`' aggregate-gate rule, which exists because a narrow command can pass while the repo's gate fails; that risk is answered by the orchestrator's run.
- **Only one `make test` may run in this worktree at a time.** Two concurrent runs corrupt each other's results — observed as `Executed 1449 instead of expected 1466 tests` and a bare `Terminated: 15`, neither of which is a real defect. Never pipe a gate through `head`/`tail`: the pipeline's exit status is the tail's, which discards the real one (`shell.md`).

## Verification Planning

**Command that proves the whole change works**, from a normal terminal shell in the worktree (so `PROFILE=mac_workstation` is inherited, which is the operator actor):

```bash
F=$(mktemp -d); mkdir -p "$F/lib" "$F/config"
cp lib/detect_env.sh "$F/lib/"; cp config/profiles.sh "$F/config/"; chmod 000 "$F/config/profiles.sh"
bash -c "source '$F/lib/detect_env.sh'; detect_env; echo rc=\$?; echo LOADED=\${_PROFILES_LOADED}"
chmod 644 "$F/config/profiles.sh"; rm -rf "$F"
```

**Expected:** `lib/detect_env.sh: failed to source ... Refusing to continue.` on stderr, `rc=1`, `LOADED=0`. On the pre-change tree this prints `rc=0` with `LOADED=` empty — measured.

**Edge cases that must be exercised:** the operator actor with `PROFILE` inherited (the case where a naive `${PROFILE+x}` check is inert); a table that loads but whose hostname is unmapped (must stay distinguishable from a table that did not load); and `-t doctor` continuing while `-t update` aborts.

**Full-suite gate:** `make test` green, and `make lint` exit 0.

---

## Task 5: Un-hide the failing `run_update` tests (prerequisite, discovered during execution)

```yaml-task
id: 5
description: wrap direct run_update call sites in run so bats' EXIT trap survives and failing tests regain their names
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: 'bats tests/setup_env/workflows.bats 2>&1 | grep -c "bats warning: Executed"'
    exit_code: 1
  - cmd: 'bats tests/setup_env/unit.bats 2>&1 | grep -c "bats warning: Executed"'
    exit_code: 1
  - cmd: 'make lint'
    exit_code: 0
max_retries: 3
files_touched:
  - tests/setup_env/workflows.bats
  - tests/setup_env/unit.bats
depends_on: []
```

`tdd: not-applicable` — this changes no behaviour and adds no test. It makes existing failures
*visible*; the tests and the production code are untouched.

**Why this exists.** `run_update` installs `trap '...' EXIT INT TERM` (`lib/workflows.sh:108`).
bats emits each test's TAP line from **its own** `EXIT` trap (`bats_teardown_trap as-exit-trap`),
so `run_update` clobbers it. Measured with a discriminating fixture:

```
not ok 1 A plain failure reports normally
ok 3 C trap then PASS
# bats warning: Executed 2 instead of expected 3 tests      <- B, trap-then-FAIL, vanished
```

A *passing* test with the trap still reports. A *failing* one emits nothing at all. So on this
machine `make test` is red with **17 failures whose names do not appear** — 174 of 191 executed
in `workflows.bats` alone, measured on unmodified `origin/master`, so this predates and is
independent of every other task in this plan.

**Do not "fix" it by clearing the trap.** `trap - EXIT` before returning removes bats' trap too
and is exactly as fatal — backlog row 7 measured that as probe case D. Chaining onto
`bats_teardown_trap` works but depends on bats internals and is version-fragile (1.14.0 local,
1.10.0 in CI).

**The conversion is NOT mechanical, and the obvious version hides the bug it exists to reveal.**
These tests call `run_update` bare, so bats' `set -e` fails the test the instant it returns
non-zero. `run run_update` captures the status instead and execution continues to the next line.
Wrap without adding an assertion and 17 real failures become passes.

For every site converted, decide which the original meant and make it explicit:

- Relied on `set -e` for success (the common case) → add `[ "$status" -eq 0 ]` immediately after.
- Deliberately exercises a failure path (e.g. *"records FAIL for git-hooks section when
  install_git_hooks_all_repos fails"*) → assert the status the test actually intends, not `0`.
- Already asserts on `$status` → leave the assertion, just wrap the call.

`workflows.bats` already contains **21** sites in the wrapped form; match their local convention
rather than inventing one.

**Census, taken at the base ref rather than HEAD** — backlog row 7 records that the first count
of this population was wrong because it was taken on a dirty tree and swept the counter's own
in-flight edits in as pre-existing debt:

```
origin/master   tests/setup_env/workflows.bats   direct=41   already wrapped=21
origin/master   tests/setup_env/unit.bats        direct=7    already wrapped=0
```

48 sites. Identical at HEAD, so this branch has not moved it.

**The acceptance gate expects failures, and that is deliberate.** Success is that
`bats warning: Executed N instead of expected M` **disappears** — i.e. every declared test now
emits a TAP line. It is emphatically **not** that the suite turns green: the 17 are real
failures and naming them is this task's entire product. Diagnosing them is separate work.
`grep -c` exiting 1 is the "zero matches" case, which is why both gates declare `exit_code: 1`.

**Interfaces:**

- Produces: no symbols. Restores diagnosability of `make test` on any developer machine, and
  unblocks the pre-push gate for every task in this plan.

---

## Task 6: Record the aws and rust update sections (production fix, discovered during execution)

```yaml-task
id: 6
description: wrap update_aws_cli and update_rust in the section-record idiom so their failures are reported instead of discarded
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: 'bats tests/setup_env/workflows.bats 2>&1 | grep -c "bats warning: Executed"'
    exit_code: 1
  - cmd: 'bats tests/setup_env/update_summary.bats'
    exit_code: 0
  - cmd: 'make lint'
    exit_code: 0
max_retries: 3
files_touched:
  - lib/workflows.sh
  - lib/update_summary.sh
  - tests/setup_env/workflows.bats
  - tests/setup_env/update_summary.bats
depends_on: [5]
```

**The production defect.** `run_update` wraps every update step in
`_update_record_start` / `_update_record_end` with a `PIPESTATUS` capture — every step except
two. `lib/workflows.sh:601-602` calls `update_aws_cli` and `update_rust` **bare**, and neither
`aws` nor `rust` appears in `_UPDATE_SECTION_ORDER` (`lib/update_summary.sh:5-8`, 20 sections).
`setup_env.sh` has no `set -e`, so their return values are discarded. **If either fails on a
real machine, `-t update` reports nothing at all** — no section line, no failure, no warning,
and the summary reads clean. That is the same defect class as this whole plan: a return value
dropped at the call site, so a failure becomes invisible.

**How it was found, because the chain explains the nine tests Task 5 could not fix.** Four
independent things line up:

| layer | defect |
| --- | --- |
| production | `update_aws_cli` / `update_rust` unguarded and unrecorded |
| test fixture | bats `HOME` has no `~/software_downloads/awscli`, so `cd … \|\| return 1` returns 1 every run |
| bats | test bodies run under `set -e`, so that non-zero kills the test process |
| trap | `run_update`'s EXIT trap has clobbered bats', so the death emits **no TAP line** |

CI never sees it: `MACOS` is unset there, so the macOS branch never executes.

Measured: with the trap neutralised at source the failure surfaces as
`lib/developer.sh: line 20: cd: …/software_downloads/awscli: No such file or directory`; and
creating that directory before the call turns the test green (`ok 1`). Under `run run_update`
the same call returns 0, because bats disables `set -e` inside `run` — verified with a
two-case fixture (`f() { return 1; }`: bare → `not ok`, under `run` → `ok`).

**Fixing production fixes the tests.** Wrapping the call in the pipeline idiom makes the
pipeline's exit status `tee`'s, so errexit no longer fires and the rc is captured and reported
instead. Do **not** paper over it by creating the fixture directory in the tests — that hides
the production bug this task exists to fix.

**What to do.** Copy the idiom from the `legacy-rsync` section immediately above
(`lib/workflows.sh:580-584`):

```bash
_update_record_start "aws"
update_aws_cli 2>&1 | tee "${_DOTFILES_RUN_TMPDIR}/err_aws"
_update_record_end "aws" "${PIPESTATUS[0]}"

_update_record_start "rust"
update_rust 2>&1 | tee "${_DOTFILES_RUN_TMPDIR}/err_rust"
_update_record_end "rust" "${PIPESTATUS[0]}"
```

**Both halves are mandatory and the second is easy to forget.** `CLAUDE.md` records this
coupling: adding `_update_record_start/end` without adding the name to
`_UPDATE_SECTION_ORDER` means the section is tracked internally and **never printed**, with no
error. Add `aws` and `rust` to that array in `lib/update_summary.sh`.

**Then fix the count assertions, which a `sed` pass will not catch.** Three tests hardcode a
section total and will break: `tests/setup_env/update_summary.bats:404` (`8 OK`), `:461`
(`1 OK`), and `tests/setup_env/workflows.bats:2100` (`8 OK`). `CLAUDE.md` names this trap
explicitly — audit and adjust each by hand against what the run actually produces, rather than
incrementing blindly.

**TDD.** Add a test that a failing `update_aws_cli` is *recorded* — it must fail before the
change (today the failure is unreported) and pass after. That is the discriminating test; the
gate below only proves the nine stopped vanishing.

**Interfaces:**

- Consumes: Task 5's converted call sites.
- Produces: `aws` and `rust` sections in the update summary; `update_aws_cli`/`update_rust`
  failures become reportable rather than silent.

---

## Task 0: Isolate the profile tests from an inherited environment (prerequisite)

```yaml-task
id: 0
description: clear inherited HAS_* and identity variables in the three profiles.bats tests that assert a capability is absent
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: 'bats tests/setup_env/profiles.bats'
    exit_code: 0
  - cmd: 'env -u HAS_AWS -u HAS_DEVTOOLS -u HAS_DOCKER -u HAS_GUI -u HAS_K8S -u HAS_PRINTING -u HAS_RUST -u PROFILE -u STUDIO bats tests/setup_env/profiles.bats'
    exit_code: 0
  - cmd: 'make lint'
    exit_code: 0
max_retries: 3
files_touched:
  - tests/setup_env/profiles.bats
depends_on: []
```

**Files:** `tests/setup_env/profiles.bats` only.

**Why this exists.** Discovered during Task 1's execution, not at plan time. `config/profiles.zsh:46,56,67` `export`s `PROFILE`, seven `HAS_*` and the legacy identity variable into every child of a login shell. `detect_env` only ever *adds* `HAS_*` — it never clears inherited ones — so any test asserting a capability is **absent** reads the login shell's value instead of the code's output. Measured on unmodified `HEAD` in a scratch copy:

```
HAS_* inherited (a dev mac)   not ok 8 HAS_DEVTOOLS is unset for mac_mini
                              not ok 10 HAS_DOCKER is unset for mac_mini
HAS_* cleared (CI's state)    ok 8   ok 10
```

Green in CI because `ubuntu-latest` never sources `.zprofile`; red on every development machine. That is `tdd.md` pitfall A, and the actor-boundary class — a test that cannot fail where it runs, and cannot pass where the operator runs it.

**Three tests carry the vulnerable shape** `[ -z "${HAS_*:-}" ]`: `HAS_DEVTOOLS`, `HAS_DOCKER`, `HAS_SNAP`. **Fix all three, including `HAS_SNAP`.** It currently passes, but only because `HAS_SNAP` is `linux_workstation`-only and nothing exports it on a mac — it is exactly as unisolated as the two that fail, and would fail on the Linux workstation. A test that passes by accident of the host's profile is not isolated.

**The idiom already exists in this file** — `tests/setup_env/profiles.bats:50` and `:385` use `unset \${!HAS_@}` inside their `bash -c` bodies. Follow it; do not invent a new mechanism. Clear the legacy identity variables too (`PROFILE`, `STUDIO`, `LAPTOP`, `RECEPTION`, `RATNA`, `OFFICE`, `HOMES`, `WORKSTATION`, `CRUNCHER`), since the same export path sets one of them per host.

**Verified safe:** `unset "${!HAS_@}" PROFILE STUDIO` under `set -e` with **no** `HAS_*` set — CI's state — exits 0. The quoted empty expansion yields zero words, not one empty word, so it does not trip bats' `set -e`.

**Both acceptance gates are required and they measure opposite environments.** Gate 1 runs with this machine's real inherited environment and fails on master today. Gate 2 runs with it cleared and passes on master today — it is the control proving the fix did not simply make the tests vacuous. A fix that deletes the assertions passes gate 1 and fails nothing; that is why gate 2 exists alongside it.

**Interfaces:**

- Produces: no symbols. Unblocks every other task's aggregate gate.

---

## Task 1: Propagate the source failure and record the sentinel

```yaml-task
id: 1
description: detect_env propagates the failed source of config/profiles.sh and records a _PROFILES_LOADED sentinel
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: 'bash -c ''F=$(mktemp -d); mkdir -p "$F/lib" "$F/config"; cp lib/detect_env.sh "$F/lib/"; cp config/profiles.sh "$F/config/"; chmod 000 "$F/config/profiles.sh"; bash -c "source $F/lib/detect_env.sh; detect_env >/dev/null 2>&1; [ \$? -eq 1 ]"; r=$?; chmod 644 "$F/config/profiles.sh"; rm -rf "$F"; exit $r'''
    exit_code: 0
  - cmd: 'env PATH="$PWD/tests/mocks:$PATH" MOCK_HOSTNAME_OUTPUT=studio MOCK_UNAME_S=Darwin bash -c ''source lib/detect_env.sh; detect_env >/dev/null 2>&1; [ "${_PROFILES_LOADED:-unset}" = 1 ]'''
    exit_code: 0
max_retries: 3
files_touched:
  - lib/detect_env.sh
  - tests/setup_env/unit.bats
depends_on: [0]
```

**Files:** `lib/detect_env.sh` (edit `:23`), `tests/setup_env/unit.bats` (add spec cases T1, T2).

Replace the bare `source` at `:23` with the block from spec §1: `_PROFILES_LOADED=0`, an `if ! source ...; then` that prints to stderr and `return 1`, then `_PROFILES_LOADED=1`. The stderr string must contain `Refusing to continue` — T1 asserts on it, because a bash-3.2 run also yields rc=1 while merely _naming_ the file.

**Add a post-condition before `_PROFILES_LOADED=1`, not just the `source` guard.** A sourced file returns the status of its **last executed command**, and `config/profiles.sh` ends with `declare -A PROFILE_LEGACY=(...)`. A failure confined to an earlier statement therefore leaves `source` returning 0 with the table incomplete. Measured on a fixture whose `PROFILE_MAP` is never declared and whose last statement succeeds:

```
rc=0  LOADED=1  PROFILE=unknown  HAS_DEVTOOLS=[1]
```

`HAS_DEVTOOLS=1` there is **inherited from the login shell** — so `detect_env` reports success, the sentinel claims the table loaded, `PROFILE` is `unknown`, and the capabilities are the parent's. Exactly the state the guard's own message says it refuses to continue into.

```bash
if ! declare -p PROFILE_MAP PROFILE_CAPS PROFILE_LEGACY >/dev/null 2>&1; then
  printf "lib/detect_env.sh: config/profiles.sh sourced but did not define PROFILE_MAP, PROFILE_CAPS and PROFILE_LEGACY -- the identity table is incomplete. Refusing to continue.\n" >&2
  return 1
fi
```

Verified both directions: fails on the incomplete fixture, passes on the real `config/profiles.sh`. This turns the check from *the last statement succeeded* into *the three arrays the caller depends on exist*, and closes the same positional-versus-structural weakness the cut bash-version guard was justified on — in the consumer rather than in `config/profiles.sh`.

Add a comment beside the existing `readonly`-here / `export`-there note at `:44` recording that this is deliberately stricter than `config/profiles.zsh:41`'s warn-and-continue, and why: that file is sourced by `.zprofile` at login, this one is sourced only by a provisioning script.

**T1** — `detect_env` against a fixture-tree `profiles.sh` that is unreadable: assert rc is **exactly 1** (a wrong fixture path makes `detect_env` an unknown command and yields 127), stderr contains `Refusing to continue`, **and `_PROFILES_LOADED` is `0`**.

Capture the sentinel in an rc-preserving form so `$status` still reports `detect_env`'s:

```bash
run bash -c "source '${fixture}/lib/detect_env.sh'
             detect_env; rc=\$?
             printf 'LOADED=%s\\n' \"\${_PROFILES_LOADED:-unset}\"
             exit \$rc"
```

**An earlier revision of this plan forbade that third assertion, and was wrong.** Its reason —
that `${_PROFILES_LOADED:-0}` returns `0` for a never-assigned variable, so the arm cannot tell
"ran and failed" from "never reached" — is true of the arm **in isolation** and false of it in
T1, where rc-exactly-1 and the stderr string already prove the branch executed. It carries no
vacuity here, and it is the **only** thing in this plan that kills the sentinel-ordering mutant.
See Self-Review.

**T2** — `detect_env` normal with `MOCK_HOSTNAME_OUTPUT=studio`: assert `PROFILE` is `mac_workstation`, `STUDIO` is `1`, and `_PROFILES_LOADED` is `1`.

**Both gates were run against this tree and exit 1** (real failure, not usage error): the sentinel is never assigned today, and `detect_env` returns 0 on an unreadable table. The second gate was also confirmed able to pass, by simulating the assignment.

**Interfaces:**

- Produces: `_PROFILES_LOADED` — a non-exported shell variable, `0` on entry to `detect_env`, `1` only after a successful source. Task 3 reads it.
- Produces: `detect_env` returns `1` when the table cannot be loaded, `0` otherwise. Task 2 reads it.

---

## Task 2: setup_env.sh reads detect_env's status

```yaml-task
id: 2
description: setup_env.sh aborts every workflow except doctor and check-versions when detect_env fails
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: 'bats tests/setup_env/unit.bats -f "detect_env failure" 2>&1 | grep -q "^ok "'
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched:
  - setup_env.sh
  - tests/setup_env/unit.bats
depends_on: [1]
```

**Files:** `setup_env.sh` (edit `:61`), `tests/setup_env/unit.bats` (add spec cases T3, T4).

Replace the bare `detect_env` at `:61` with:

```bash
if ! detect_env && [[ -z ${DOCTOR:-} && -z ${CHECK_VERSIONS:-} ]]; then
  exit 1
fi
```

`DOCTOR` and `CHECK_VERSIONS` are readonly globals set by `process_args` (`lib/helpers.sh:641`) at `:59`; their dispatch sites are `:69` and `:70`. `--brew-install` stays out of the carve-out deliberately — it is a flag on `-t setup`, which needs the table.

**T3** — `setup_env.sh -t update` against a fixture tree whose `profiles.sh` is unreadable. Three arms, all required: exit 1, stderr contains `Refusing to continue`, and no workflow marker file exists. Exit 1 alone is **not** discriminating — `setup_env.sh:20` (bash < 5) and `:30` (no brew) both produce it, so a mac resolving 3.2 or a brew-less `PATH` would pass this against unmodified master.

**Before invoking `setup_env.sh`, T3 must assert its mock is live:**

```bash
[[ "$(command -v brew)" == "${REPO_ROOT}/tests/mocks/brew" ]] \
  || { echo "refusing to run: tests/mocks not on PATH" >&2; return 1; }
```

That converts a `PATH`-dependent hazard into a test that refuses to run rather than one that runs `softwareupdate` for real.

**T4** — same fixture, `-t doctor`: assert `run_doctor` is reached (its `=== Checks ===` banner appears).

**Interfaces:**

- Consumes: `detect_env`'s `1`/`0` return from Task 1.
- Produces: no new symbols. Task 3 depends on this only for ordering.

---

## Task 3: doctor branches on the sentinel, and the tests it breaks are repaired

```yaml-task
id: 3
description: _doctor_check_profile distinguishes a table that did not load from an unmapped hostname, and the three existing tests this changes are repaired
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: 'bash -c ''source lib/helpers.sh 2>/dev/null; PROFILE=mac_workstation _PROFILES_LOADED=0 _doctor_check_profile 2>&1 | grep -q "did not load"'''
    exit_code: 0
  - cmd: 'bash -c ''source lib/helpers.sh 2>/dev/null; PROFILE=mac_workstation _PROFILES_LOADED=1 _doctor_check_profile 2>&1 | grep -q "PASS"'''
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched:
  - lib/helpers.sh
  - tests/setup_env/unit.bats
depends_on: [1, 2]
```

**Files:** `lib/helpers.sh` (edit `_doctor_check_profile`, `:397-410`), `tests/setup_env/unit.bats` (add T5, T6, T7; repair tests 118, 119, 120).

Replace the two-branch `if [[ "${PROFILE:-unknown}" == "unknown" ]]` with the three-branch form from spec §3, testing `[[ "${_PROFILES_LOADED:-0}" != 1 ]]` first. **This is mandatory repair of a regression Task 1 introduces, not a courtesy fix** — `detect_env.sh:31` assigns `PROFILE` unconditionally today, so master reports correctly; Task 1's early return skips that assignment and lets a stale inherited `PROFILE` survive.

**Three existing tests change and only one repair is safe.** `load_setup_env()` (`tests/helpers/common.bash:38`) sources `setup_env.sh`, whose guard at `:56` returns before `:61`, so `detect_env` never runs and every doctor call site reads an unset sentinel. Measured on a patched copy: `not ok 118`, `not ok 119`, and `ok 120` passing through the sentinel branch rather than the branch its name describes — re-point 120.

- **Set `_PROFILES_LOADED=1` at function scope in the affected tests.** Correct.
- **Do not call `detect_env`** — it assigns `PROFILE` unconditionally at `:31`, the exact variable 118 and 119 control.
- **Do not export `_PROFILES_LOADED=1` from `load_setup_env`** — that makes the sentinel environment-supplied in the suite meant to guard against an environment-supplied oracle.

**T5** — the regression pin: `PROFILE=mac_workstation` left set, fixture table unreadable, then a
real **`detect_env`** call, then `run_doctor`; fails if doctor reports PASS for PROFILE. Fails
with Task 1 alone, passes only with this change.

**Drive the sentinel through `detect_env`; never inject it.** An injected `_PROFILES_LOADED`
exercises `_doctor_check_profile`'s branch and is invariant under a sentinel-ordering defect in
`detect_env` — which is exactly how the mutant in Self-Review survives everything else. T5 is
this plan's only end-to-end path from a broken table to a doctor verdict. Note the contrast with
the three *existing* tests repaired below, which must **not** call `detect_env` — there the
reason is that `detect_env` assigns `PROFILE` unconditionally and would clobber the fixture those
tests control. Different tests, opposite instructions, both deliberate.

**T6** — `_doctor_check_profile` across all three states (loaded+mapped, loaded+unmapped, not loaded); fails if any two produce the same verdict/message pair.

**T7** — negative control: `_PROFILES_LOADED=1` supplied in the environment with `detect_env` **not** called. Assert a non-empty `[PASS]` line — not merely "no FAIL", which an empty result satisfies. It must PASS, pinning that the environment _can_ defeat the read, so the protection is the unconditional `=0` and not non-export. If T7 ever starts failing, the mechanism changed and Task 1's comment is stale.

**Both discriminating gates were run against this tree and exit 1** — there is no `did not load` branch today.

**Interfaces:**

- Consumes: `_PROFILES_LOADED` from Task 1.
- Produces: no new symbols.

---

## Task 4: Update docs and close the plan

```yaml-task
id: 4
description: Update CLAUDE.md Test Seams and the plan index (docs-only, no behavior change, so TDD does not apply)
role: executor
model: haiku
tdd: not-applicable
acceptance:
  - cmd: 'grep -q "_PROFILES_LOADED" CLAUDE.md'
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 2
files_touched:
  - CLAUDE.md
depends_on: [3]
```

**Files:** `CLAUDE.md` only.

Add a paragraph to the **Test Seams** section recording `_PROFILES_LOADED`: what sets it, that it is never exported, and that its safety is the unconditional `=0` on entry to `detect_env` rather than non-export — with the one-line measurement showing an environment-supplied value defeats the read. Note T7 exists to keep that paragraph honest.

The plan-index row and the backlog row [14] rewrite are handled in Phase 3 by the `docs` skill, not here.

---

## Self-Review

1. **Spec coverage.** §1 → Task 1; §2 → Task 2; §3 + existing-test repair → Task 3; T1-T7 → Tasks 1-3. The cut guard, Groups B and C, and `_OVERRIDE_PROFILES_SH` are out of scope by design.
2. **Placeholders.** None.
3. **Type consistency.** `_PROFILES_LOADED`, `detect_env`, `_doctor_check_profile`, `DOCTOR`, `CHECK_VERSIONS` used identically across tasks.
4. **yaml-task blocks.** Present on all four; `make validate-plan` run before commit.
5. **TDD `files_touched` includes the test file.** Tasks 1-3 all list `tests/setup_env/unit.bats`.
6. **Token budget.** Each block under 2KB.
7. **ADR significance.** No new Phase 3 gate, storage choice, or security guardrail — this is a return-code propagation fix. No ADR task.
8. **`files_touched` matches the prose.** Task 4 is `haiku` and touches exactly one file, satisfying the scope guard.

**Gates proven capable of failing.** Every discriminating gate above was run against this pre-change tree and returned **exit 1**, not a usage error — recorded per task. Tasks 1-3 pair theirs with the aggregate `make test`; no task carries `parallel_group`, so the aggregate gate is correct rather than harmful.

**One wrong implementation each gate would still accept.** Task 1's sentinel gate passes if `_PROFILES_LOADED=1` is set unconditionally rather than only after a successful source — which is why Task 1's _other_ gate (rc 1 on an unreadable table) and T7 both exist. Task 3's `did not load` gate passes if the branch fires unconditionally — which T6's three-state comparison is what catches.
