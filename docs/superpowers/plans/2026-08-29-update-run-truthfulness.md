# `-t update` Run Truthfulness Implementation Plan

> **Status: IN PROGRESS**
>
> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `setup_env.sh -t update` exit non-zero when a section fails, with honest section return codes feeding it and the failing section's raw output still on disk.

**Architecture:** Four sequential changes to existing functions plus an ADR, no new source files. `_dotfiles_run_tmpdir_setup` stops deleting its directory so `err_*` survives the run; `_update_summary` returns `$(( _fail > 0 ))` so `_run_or_exit` finally fires; `update_aws_cli`/`update_rust` check every command so the `aws` and `rust` sections can report something other than OK.

**Tech Stack:** bash, bats, `make lint` (bash -n + zsh -n + shellcheck), `make test`.

**Spec:** [2026-08-29-update-run-truthfulness-design.md](../specs/2026-08-29-update-run-truthfulness-design.md) at `b9338ef`.

## Global Constraints

- Tasks are strictly sequential. No `parallel_group` anywhere: Tasks 1-4 touch behaviour that `tests/setup_env/update_summary.bats` and `tests/setup_env/workflows.bats` observe; Task 2 changes a return contract Task 1's tests run under; and Tasks 3 and 4 edit the same file.
- `make test` takes roughly ten minutes in this repo and crosses the Bash tool's 120s auto-background threshold. **Invoke it with an explicit `timeout: 600000`.** A backgrounded acceptance command never wakes the subagent that started it.
- `make test` is `lint check-lock check-requirements-ci test-python` (`Makefile:109`) and is the aggregate gate. Do not substitute `bats tests/` for it.
- `mktemp -d -t <prefix>` is **forbidden** — BSD reads `-t` as a prefix, GNU as a deprecated flag needing `XXXXXX`, and Linux fails with `too few X's in template`. Use the explicit template form the spec gives.
- Every new test that stages a `FAIL` status file uses `run`, never a bare call. Bats runs test bodies under `set -e`, and `_dotfiles_run_tmpdir_setup`'s EXIT trap clobbers bats' own — reproduced in this repo three times as `Executed N-1 instead of expected N` with no test name and no line number (`tests/setup_env/workflows.bats:237`, `:1796`, `:1930`).
- No `--no-verify` on any push. The pre-push hook runs `make test` and is the local gate.
- Work happens in a git worktree, not the main checkout. Concurrent sessions share this repo's index.

## Gate Falsifiability

Every acceptance gate naming a measurable was run against the base tree (`b9338ef`) before
being written into a task. A gate that passes there is not a gate:

| gate | base-tree result |
| --- | --- |
| `! grep -q _rustup_found lib/developer.sh` (T4) | exit 1 — the variable is present |
| `test -f docs/adr/0027-….md` (T5) | exit 1 — the file is absent |
| `grep -q "plans/2026-08-29-update-run-truthfulness.md" …` (T6) | exit 1 — the row still reads `—` |
| `grep -q "2026-08-29-update-run-truthfulness" …` | **exit 0 — rejected as vacuous.** The spec link in the existing row already contains that substring, so the gate would have passed before the task ran. Replaced with the two gates above. |

Each is exit 1 rather than 2/4/127, so they fail because they measured something rather than
because a path or binary is missing.

## Session-Level Verification

Beyond the per-task gates, the whole change is proven by driving the real entry point on a fixture `HOME` and asserting both directions of the process exit:

```bash
t="$(mktemp -d "${TMPDIR:-/tmp}/verify.XXXXXXXX")"
HOME="${t}" ./setup_env.sh -t update --claude-only; echo "rc=$?"
```

Expected: `rc=1` on a run whose summary shows a non-zero failed count, `rc=0` on a run showing `0 failed`. Both directions matter — asserting only the failing one cannot distinguish a working contract from one that always returns 1.

Edge cases that must be exercised: a run whose only non-OK sections are WARN must exit 0 **and** print at least one `[WARN]` row; a run with an unset `_DOTFILES_RUN_TMPDIR` must exit 0 rather than false-1; and the `err_*` files from a failing section must still exist after the process ends.

---

### Task 1: Retain `err_*` past the run

```yaml-task
id: 1
description: Stop _dotfiles_run_tmpdir_setup deleting its directory so a failing section's raw output survives, using a portable mktemp template
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: make lint
    exit_code: 0
  - cmd: bats tests/setup_env/ledger_integration.bats -f "_dotfiles_run_tmpdir_setup"
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - lib/workflows.sh
  - tests/setup_env/ledger_integration.bats
depends_on: []
```

**Files:** `lib/workflows.sh:105-116`, `tests/setup_env/ledger_integration.bats` (new tests near the existing `_dotfiles_run_tmpdir_setup` block at `:290`).

**RED first.** Add to `tests/setup_env/ledger_integration.bats`, whose `setup()` already
calls `load_setup_env` and exports `HOME="${BATS_TEST_TMPDIR}"`.

**The subshell is load-bearing and a bare call is vacuous here.** The EXIT trap fires when the
*shell* exits, not when the function returns — so the existing bare-call tests at `:292` and
`:300` already assert `[ -d "${_DOTFILES_RUN_TMPDIR}" ]` and pass today. Probed before this
plan was dispatched: bare call `ok`, subshell form `not ok`. Only the subshell form is red.

```bash
@test "_dotfiles_run_tmpdir_setup: directory survives the EXIT trap" {
    run bash -c 'set -e
      source "'"${REPO_ROOT}"'/setup_env.sh" >/dev/null 2>&1 || true
      _dotfiles_run_tmpdir_setup
      printf "%s" "${_DOTFILES_RUN_TMPDIR}"'
    [ "$status" -eq 0 ]
    [ -n "$output" ]
    [ -d "$output" ]              # RED today: the trap removed it when bash -c exited
    [ -f "${output}/started_at" ]
    rm -rf "$output"
}

@test "_dotfiles_run_tmpdir_setup: directory name carries the dotfiles-run prefix" {
    unset _DOTFILES_RUN_TMPDIR
    _dotfiles_run_tmpdir_setup
    [[ "$(basename "${_DOTFILES_RUN_TMPDIR}")" == dotfiles-run.* ]]  # RED: name is tmp.XXXXXXXX
}
```

The second test may stay a bare call — it asserts on the name, which the trap does not affect,
and it is not staging a FAIL status.

**GREEN.** In `lib/workflows.sh`, replace lines 106 and 108:

```bash
_dotfiles_run_tmpdir_setup() {
  _DOTFILES_RUN_TMPDIR=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-run.XXXXXXXX")
  export _DOTFILES_RUN_TMPDIR
  trap 'unset _DOTFILES_RUN_TMPDIR' EXIT INT TERM
```

Everything below line 108 is unchanged. The trap stays — only `rm -rf "${_DOTFILES_RUN_TMPDIR}"; ` is removed from it.

**Do not** add pruning in this task. Retention is bounded by the OS reaping `/var/folders` (macOS, ~3 days) and `/tmp` (`systemd-tmpfiles`, ~10 days); a prune is the deferred durable-root work.

**Why no isolation work is needed:** the directory is still `mktemp`, so every test writes to a throwaway path exactly as today. Three tests call this function directly — `tests/setup_env/install_guards.bats:783`, `tests/setup_env/ledger_integration.bats:294` and `:302` — and all three now leave a directory behind that the OS reaps. None of the 372 `_DOTFILES_RUN_TMPDIR` references changes.

**Interfaces:**

- Consumes: nothing from earlier tasks.
- Produces: `_DOTFILES_RUN_TMPDIR` now names a surviving directory matching `dotfiles-run.*`. Task 2's tests may rely on `err_*` and `status_*` files persisting past the call that wrote them.

---

### Task 1b: Harden the run-dir change (re-plan, from Task 1 review)

```yaml-task
id: 7
description: Guard the mktemp assignment, scope TMPDIR in the bats suites so test run dirs are reaped, and fix three test defects found in Task 1 review
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: make lint
    exit_code: 0
  - cmd: bats tests/setup_env/ledger_integration.bats
    exit_code: 0
  - cmd: 'bash -c "test $(find /var/folders -path \"*/T/dotfiles-run.*\" -maxdepth 4 -type d 2>/dev/null | wc -l) -eq 0"'
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - lib/workflows.sh
  - tests/setup_env/ledger_integration.bats
  - tests/setup_env/workflows.bats
  - tests/setup_env/unit.bats
  - tests/setup_env/install_guards.bats
depends_on: [1]
```

**Why this task exists.** Task 1's review found five defects, four of them inherited from
this plan rather than introduced by the implementer. The plan's "no pruning" decision rested
on a wrong population: it counted **3 direct callers** of `_dotfiles_run_tmpdir_setup` and
concluded the OS reaper was sufficient. The population that actually creates directories is
**test invocations reaching any of the six `run_*` callers** — measured at ~318 lines across
six bats files, `run_update` alone accounting for 203. One suite run left **282** directories
in a temp tree at 362M, and `make test` fires on every push via the pre-push hook.

The distinction the plan missed, and which decides the fix: **production** creates one
directory per real `-t update` run, a few per week, where the OS reaper is genuinely
adequate; **tests** create hundreds per suite run. So the fix is test-side scoping, not
production pruning — the original no-pruning decision stands and is correct for the case it
was actually about.

**1 — Guard the assignment (HIGH).** `lib/workflows.sh:106` has no `|| return 1`. The
templated form makes `TMPDIR` load-bearing where bare `mktemp -d` ignored it — measured on
macOS:

```
TMPDIR=/tmp/probe  mktemp -d                              -> /var/folders/.../tmp.K4P129yETg   (ignored)
TMPDIR=/tmp/probe  mktemp -d "${TMPDIR:-/tmp}/x.XXXXXXXX" -> /tmp/probe/x.mLqa55nU             (honoured)
TMPDIR=/nonexistent ... same templated form               -> rc=1, variable empty
```

An empty `_DOTFILES_RUN_TMPDIR` sends every subsequent write to `/started_at` and the run
continues — and per this spec's own Exit contract section an absent tmpdir leaves `_fail=0`,
so the summary reads clean and the ledger records success over a run that did nothing. That
is the precise defect this spec exists to eliminate, reintroduced by its first task.

```bash
_DOTFILES_RUN_TMPDIR=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-run.XXXXXXXX") || return 1
```

Add the error-path test `tdd.md` mandates for this branch. `TMPDIR` alone cannot drive it
hermetically, so introduce a `_OVERRIDE_RUN_TMPDIR_ROOT` seam read only by this function,
defaulting to `${TMPDIR:-/tmp}`, and point it at a nonexistent path in the test.

**2 — Scope `TMPDIR` in every bats suite that reaches a `run_*` caller.** bats sets
`BATS_TEST_TMPDIR` but leaves `TMPDIR` as the system temp dir — verified. At `setup()` scope,
not per test:

```bash
export TMPDIR="${BATS_TEST_TMPDIR}"
```

**Four** files, and the route to that number is the point. The first list named six by
resemblance. The second named six by `grep -cE` over the six `run_*` names — which counts
**test names and comments as invocations**, so `launch_agents.bats` scored 2 on a `@test`
title plus a comment, and `extracted_functions.bats` scored 1 on a title reading
*"(mas is called from run_update)"*. Neither file calls a `run_*` function at all; the
implementer caught it by reading the lines, and it was settled empirically by running just
those two files against a cleaned temp tree — **0 directories created**.

| file | direct calls | real `run_*` invocations |
| --- | --- | --- |
| `workflows.bats` | 3 | 267 |
| `unit.bats` | 0 | 38 |
| `install_guards.bats` | 2 | 5 |
| `ledger_integration.bats` | 12 | 1 |

A text match over a file that discusses the thing it tests will count the discussion. Where
the question is "does this code run", the settling instrument is running it and counting the
side effect, not grepping for the name.

`brewfile_drift.bats`, `update_summary.bats`, `package_capture.bats`, `launch_agents.bats`
and `extracted_functions.bats` all have **zero** invocations — `update_summary.bats` sets `_DOTFILES_RUN_TMPDIR` to
`BATS_TEST_TMPDIR` directly and never calls the setup function at all, which is also why
Task 2's bare `_update_summary` call sites are safe there. Setup scope is the point — a
per-test guard leaves the trap armed for the next test someone adds.

**3 — Convert the prefix test to `run bash -c` form.** `ledger_integration.bats:320` is a
bare call, so the function's EXIT trap clobbers bats' own and a failure reports
`Executed N-1 instead of expected N` with no test name and no line number. It is falsifiable
(rc=1 at RED in isolation) but unattributable. This plan's own Global Constraints name that
symptom as having cost this repo three prior incidents, and then exempted this test from it.

**4 — Drop `|| true` from the test's `source` line.** `ledger_integration.bats:310` reads
`source setup_env.sh >/dev/null 2>&1 || true`. Demonstrated in review: appending a syntax
error to `lib/git_hooks.sh` (sourced after `workflows.sh`) leaves the test reporting `ok`.
Any breakage past `workflows.sh:116` is masked. `setup_env.sh` returns 0 on the sourcing path
by construction, so the guard buys nothing.

**5 — Use `run --separate-stderr`** in the survives-the-EXIT-trap test, or write the path to
a file and read it back. `run` merges stderr into `$output`, and `ensure_state_ledger` has
three reachable `log_warn` paths, any of which prepends a line and false-reds `[ -d "$output" ]`.

**Interfaces:**

- Consumes: Task 1's production change.
- Produces: a guarded assignment and a suite that reaps its own run dirs. Tasks 2-6 inherit both.

---

### Task 1c: Propagate the run-dir failure to the callers (re-plan, from Task 1b review)

```yaml-task
id: 8
description: Make the six run_* callers branch on _dotfiles_run_tmpdir_setup's return value, and correct three stale RED comments in the tests it touches
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: make lint
    exit_code: 0
  - cmd: bats tests/setup_env/ledger_integration.bats
    exit_code: 0
  - cmd: bats tests/setup_env/workflows.bats
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - lib/workflows.sh
  - tests/setup_env/ledger_integration.bats
  - tests/setup_env/workflows.bats
depends_on: [7]
```

**Task 1b's guard returns into a void, and the whole spec turns on closing it.** All six call
sites are bare statements, there is no `set -e` in `lib/workflows.sh` or `setup_env.sh`, so a
non-zero return is discarded and the caller runs on with `_DOTFILES_RUN_TMPDIR` set to the
empty string. 107 write sites in `lib/update_summary.sh` and 28 in `lib/workflows.sh` then
target `/`.

Reproduced end to end against the real functions, with an unreachable override:

```
setup rc=1 var=[]
summary rc=0
0 sections: 0 OK, 0 failed, 0 warnings, 0 skipped
```

`_update_record_end "brew" 1` had recorded a **failure**, and the summary reports `0 failed`
while `_update_summary` returns 0. Task 2's exit contract cannot save this: `_fail` is 0
because no status file was ever written, so `$(( _fail > 0 ))` is 0 and `-t update` exits
clean over a run that did nothing. That is verbatim the defect this spec exists to eliminate,
reachable today.

**The fix.** All six sites — `lib/workflows.sh:120, 225, 261, 286, 293, 331` — become:

```bash
_dotfiles_run_tmpdir_setup || return 1
```

This widens each `run_*` function's contract from "always 0 unless an inner `cd` fails" to
"non-zero when the run directory cannot be created". `_run_or_exit` (`setup_env.sh:76-80`)
already treats any non-zero as fatal, which is the correct outcome: a run that cannot create
its own scratch directory has not run. Per `behavior.md`'s contract-widening rule, enumerate
the call sites before editing — `grep -n '_dotfiles_run_tmpdir_setup' lib/workflows.sh` — and
confirm none of the six is written as `fn && x`, `if fn; then`, or a bare `||`, since each
would read a new non-zero as something other than failure.

**The error-path test is at the caller level, not the function level.** Task 1b already
covers the function returning 1. What is untested is that a caller *stops*. Drive
`run_update` with `_OVERRIDE_RUN_TMPDIR_ROOT` pointed at an unreachable path and assert both
halves: the function returns non-zero, **and** it did not proceed — no summary line, no log
append. Asserting only the return code would pass against a caller that returned 1 after
running every section.

**Three stale comments, in the same files.** `ledger_integration.bats:329` says
`# RED today: mktemp ignores the unreachable root entirely` — false in both halves: `mktemp`
honours the root and fails, which is the point of the guard, and the test is green at HEAD.
`:358` says `# RED: name is tmp.XXXXXXXX`, stale since Task 1. `:343` says the trap "removed
it", describing a trap that unsets a variable and removes nothing. Correct all three; they
are the same defect class as the code they annotate.

**Interfaces:**

- Consumes: Task 1b's `|| return 1` and the `_OVERRIDE_RUN_TMPDIR_ROOT` seam.
- Produces: six `run_*` functions that fail closed. Task 2's exit contract composes with this
  rather than duplicating it — that task governs a run that *completed* with failures, this
  one a run that could not start.

---

### Task 2: Exit contract

```yaml-task
id: 2
description: _update_summary returns non-zero when any section FAILed, migrate the 14 test call sites, and correct _run_or_exit's comment to name both non-zero meanings
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: make lint
    exit_code: 0
  - cmd: bats tests/setup_env/update_summary.bats
    exit_code: 0
  - cmd: bats tests/setup_env/workflows.bats
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - lib/update_summary.sh
  - setup_env.sh
  - tests/setup_env/update_summary.bats
depends_on: [1]
```

**Files:** `lib/update_summary.sh:598` (end of `_update_summary`), `setup_env.sh:75` (comment only), `tests/setup_env/update_summary.bats` (14 call sites).

**RED first.** Add a paired test — the pair is the point, since `[ "$status" -eq 1 ]` alone is satisfied by a function that always returns 1:

```bash
@test "_update_summary returns 1 when a section FAILed" {
  printf "FAIL\n" > "${_DOTFILES_RUN_TMPDIR}/status_claude"
  printf "exit 1\n" > "${_DOTFILES_RUN_TMPDIR}/result_claude"
  run _update_summary
  [ "$status" -eq 1 ]
}

@test "_update_summary returns 0 when every section is OK" {
  printf "OK\n" > "${_DOTFILES_RUN_TMPDIR}/status_claude"
  printf "updated\n" > "${_DOTFILES_RUN_TMPDIR}/result_claude"
  run _update_summary
  [ "$status" -eq 0 ]
}

@test "_update_summary returns 0 when the only non-OK section is WARN" {
  printf "WARN\n" > "${_DOTFILES_RUN_TMPDIR}/status_git-repos"
  printf "one or more repos unreachable\n" > "${_DOTFILES_RUN_TMPDIR}/result_git-repos"
  run _update_summary
  [ "$status" -eq 0 ]
  [[ "$output" == *"[WARN]"* ]]   # a fixture with no WARN row would pass on nothing
}
```

The first fails today (returns 0); the second and third pass today and must keep passing. The WARN test asserts the row is present as well as the exit code — without that assertion a fixture staging no WARN section satisfies it identically.

**GREEN.** `lib/update_summary.sh`, final lines of `_update_summary`:

```bash
  _ledger_write_dotfiles_entry || true
  return $(( _fail > 0 ))
}
```

`_fail` is `local` at `:537` and the function body has no early returns, so it is in scope. An unset `_DOTFILES_RUN_TMPDIR` makes the `[[ ! -f … ]] && continue` at `:546` skip every section, leaving `_fail=0` — the function fails safe rather than false-1.

**Migrate the 14 call sites in `tests/setup_env/update_summary.bats`.** Eleven use `run _update_summary`, three are bare (`:416`, `:427`, `:438`). Only two stage a FAIL today and both already use `run`:

- `:363` `_update_summary prints FAIL section with exit code` — add `[ "$status" -eq 1 ]`.
- `:391` `_update_summary prints totals line` — stages FAIL at `:394`; add `[ "$status" -eq 1 ]`.

Every other `run` site stages only OK/SKIP/WARN and gets `[ "$status" -eq 0 ]` added. The three bare sites stage only OK and are left bare — but add a comment at each saying a FAIL-staging test must use `run`, because a bare call returning 1 aborts under bats' `set -e` before its assertions.

Do **not** loosen any test to stop asserting status. A test that stops checking the return value of the function whose return value is the point of the change is worse than one that goes red.

**Comment correction, `setup_env.sh:75`:**

```bash
# Fail-fast strict runner: exit immediately on the first failed selected step.
# NOTE: run_update returns non-zero for two different situations — it ran every
# section and some recorded FAIL (summary, log line and ledger entry all written),
# or it aborted early on one of its five `cd` guards (lib/workflows.sh:621, :631,
# :641, :661, :663), which record nothing at all. Only the first leaves evidence.
```

Comment only. `_run_or_exit`'s code does not change.

**Interfaces:**

- Consumes: Task 1's surviving `_DOTFILES_RUN_TMPDIR`.
- Produces: `_update_summary` returns `0|1`; `run_update` propagates it; `setup_env.sh -t update` exits 1 on a section failure. Task 3's `aws`/`rust` FAIL statuses now reach the process exit.

---

### Task 3: `update_aws_cli` return-code propagation

```yaml-task
id: 3
description: Check every command in update_aws_cli and remove AWSCLIV2.pkg before returning on installer failure
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: make lint
    exit_code: 0
  - cmd: bats tests/setup_env/developer.bats -f update_aws_cli
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - lib/developer.sh
  - tests/setup_env/developer.bats
depends_on: [2]
```

**Files:** `lib/developer.sh:17-36`, `tests/setup_env/developer.bats`.

**Set `HOME="${BATS_TEST_TMPDIR}"` at `setup()` scope, not per test.** This function's failing
path otherwise runs a real `sudo -H installer` against the operator's machine, and a per-test
guard leaves the trap armed for the next test someone adds (`tdd.md` E2).

**RED first — mutation, both directions.** The negative alone is satisfied by a function that
always returns 1, so the positive control is required, not optional:

```bash
@test "update_aws_cli returns 1 when curl fails" {
  export MACOS=1 HAS_AWS=1; unset LINUX
  mkdir -p "${BATS_TEST_TMPDIR}/bin" "${HOME}/software_downloads/awscli"
  printf '#!/usr/bin/env bash\nexit 1\n' > "${BATS_TEST_TMPDIR}/bin/curl"
  chmod +x "${BATS_TEST_TMPDIR}/bin/curl"
  PATH="${BATS_TEST_TMPDIR}/bin:${PATH}" run update_aws_cli
  [ "$status" -eq 1 ]           # RED today: returns 0, curl's rc is discarded
}

@test "update_aws_cli returns 0 when every command succeeds" {
  export MACOS=1 HAS_AWS=1; unset LINUX
  mkdir -p "${BATS_TEST_TMPDIR}/bin" "${HOME}/software_downloads/awscli"
  for _c in curl installer sudo rm; do
    printf '#!/usr/bin/env bash\nexit 0\n' > "${BATS_TEST_TMPDIR}/bin/${_c}"
    chmod +x "${BATS_TEST_TMPDIR}/bin/${_c}"
  done
  PATH="${BATS_TEST_TMPDIR}/bin:${PATH}" run update_aws_cli
  [ "$status" -eq 0 ]
}

@test "update_aws_cli removes the pkg when the installer fails" {
  export MACOS=1 HAS_AWS=1; unset LINUX
  mkdir -p "${BATS_TEST_TMPDIR}/bin" "${HOME}/software_downloads/awscli"
  printf '#!/usr/bin/env bash\ntouch AWSCLIV2.pkg\n' > "${BATS_TEST_TMPDIR}/bin/curl"
  printf '#!/usr/bin/env bash\nexit 1\n' > "${BATS_TEST_TMPDIR}/bin/sudo"
  chmod +x "${BATS_TEST_TMPDIR}/bin/curl" "${BATS_TEST_TMPDIR}/bin/sudo"
  PATH="${BATS_TEST_TMPDIR}/bin:${PATH}" run update_aws_cli
  [ "$status" -eq 1 ]
  [ ! -f "${HOME}/software_downloads/awscli/AWSCLIV2.pkg" ]
}
```

**GREEN.** Both branches, every command checked. `rm` becomes `rm -f` so an already-absent
pkg is not itself a failure:

```bash
update_aws_cli() {
  if [[ -n ${HAS_AWS} ]] && [[ -n ${MACOS} ]]; then
    log_info "Updating MACOS awscli"
    cd "${HOME}/software_downloads/awscli" || return 1
    curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg" || return 1
    # Cleanup runs regardless of the installer's result: a stale or partial pkg
    # means the next run installs it. tdd.md's cleanup exception.
    if ! sudo -H installer -pkg AWSCLIV2.pkg -target /; then
      rm -f AWSCLIV2.pkg
      return 1
    fi
    rm -f AWSCLIV2.pkg || return 1
    cd "${PERSONAL_GITREPOS}/${DOTFILES}" || return 1
  fi
  if [[ -n ${HAS_AWS} ]] && [[ -n ${LINUX} ]]; then
    log_info "Updating Linux awscli"
    mkdir -p "${HOME}"/software_downloads/awscli || return 1
    cd "${HOME}/software_downloads/awscli" || return 1
    curl "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip" -o "awscliv2.zip" || return 1
    unzip -u -o awscliv2.zip || return 1
    sudo -H "${HOME}"/software_downloads/awscli/aws/install --install-dir /usr/local/aws-cli --bin-dir /usr/local/bin --update || return 1
    cd "${PERSONAL_GITREPOS}/${DOTFILES}" || return 1
  fi
}
```

**Interfaces:**

- Consumes: Task 2's exit contract — this rc reaches the process exit via `_update_record_end "aws"` → `status_aws` → `_fail`.
- Produces: nothing later tasks consume.

---

### Task 4: `update_rust` return-code propagation

```yaml-task
id: 4
description: Check every rustup invocation in update_rust and delete the write-only _rustup_found variable
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: make lint
    exit_code: 0
  - cmd: 'bash -c "! grep -q _rustup_found lib/developer.sh"'
    exit_code: 0
  - cmd: bats tests/setup_env/developer.bats -f update_rust
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - lib/developer.sh
  - tests/setup_env/developer.bats
depends_on: [3]
```

**Files:** `lib/developer.sh:38-56`, `tests/setup_env/developer.bats`.

`_rustup_found` is assigned at `:41`, `:45` and `:50` and read nowhere in the repo — verified
by `grep -rn '_rustup_found' . --include='*.sh' --include='*.bats' --include='*.bash'`, which
returns those three assignments and nothing else. Delete it rather than annotate it; a
suppression would make dead code permanent.

**RED first — the three-way branch needs all three cases**, because the absent-rustup branch
returning 0 and a failing rustup returning 1 are different outcomes that a single test cannot
distinguish:

```bash
@test "update_rust returns 1 when rustup update fails" {
  export UBUNTU=1 HAS_RUST=1
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  printf '#!/usr/bin/env bash\n[ "$1" = update ] && exit 1\nexit 0\n' \
    > "${BATS_TEST_TMPDIR}/bin/rustup"
  chmod +x "${BATS_TEST_TMPDIR}/bin/rustup"
  PATH="${BATS_TEST_TMPDIR}/bin:${PATH}" HOME="${BATS_TEST_TMPDIR}" run update_rust
  [ "$status" -eq 1 ]           # RED today: rustup's rc is discarded
}

@test "update_rust returns 0 when every rustup call succeeds" {
  export UBUNTU=1 HAS_RUST=1
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${BATS_TEST_TMPDIR}/bin/rustup"
  chmod +x "${BATS_TEST_TMPDIR}/bin/rustup"
  PATH="${BATS_TEST_TMPDIR}/bin:${PATH}" HOME="${BATS_TEST_TMPDIR}" run update_rust
  [ "$status" -eq 0 ]
}

@test "update_rust returns 0 and warns when rustup is absent" {
  export UBUNTU=1 HAS_RUST=1
  _clean="$(printf '%s' "${PATH}" | tr ':' '\n' | grep -v "${BATS_TEST_TMPDIR}" | tr '\n' ':')"
  PATH="${_clean}" HOME="${BATS_TEST_TMPDIR}" run update_rust
  [ "$status" -eq 0 ]
  [[ "$output" == *"rustup not found"* ]]
}
```

The third test asserts the warning text as well as the exit code — asserting `status -eq 0`
alone passes on a function that skipped the block entirely for the wrong reason.

**GREEN.** Resolve the binary once, then check each call:

```bash
update_rust() {
  if [[ -n ${UBUNTU} ]] && [[ -n ${HAS_RUST} ]]; then
    log_info "Updating Rust Ubuntu"
    local _rustup
    if [[ -x ${HOME}/.cargo/bin/rustup ]]; then
      _rustup="${HOME}/.cargo/bin/rustup"
    elif command -v rustup >/dev/null 2>&1; then
      _rustup="rustup"
    else
      log_warn "rustup not found; skipping Rust update"
      return 0
    fi
    "${_rustup}" self update || return 1
    "${_rustup}" update || return 1
    "${_rustup}" component add rust-analyzer || return 1
  fi
}
```

The absent-`rustup` branch returns 0 deliberately: a machine without rustup is a skip, not a
failure, matching how the `pip` section treats a missing `uv`.

**Interfaces:**

- Consumes: Task 3's file state (same file, sequential).
- Produces: nothing later tasks consume.

---

### Task 5: ADR-0027 — the update run's exit code

```yaml-task
id: 5
description: Record the decision that -t update derives its exit code from section status, with the accepted brew noise rate and its review trigger (docs-only, no behavior change, so TDD does not apply)
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: test -f docs/adr/0027-update-run-exit-code-from-section-status.md
    exit_code: 0
  - cmd: 'grep -qE "Status:.*Accepted" docs/adr/0027-update-run-exit-code-from-section-status.md'
    exit_code: 0
  - cmd: 'grep -q "0027" docs/adr/README.md'
    exit_code: 0
max_retries: 2
files_touched:
  - docs/adr/0027-update-run-exit-code-from-section-status.md
  - docs/adr/README.md
depends_on: [4]
```

**Files:** new `docs/adr/0027-update-run-exit-code-from-section-status.md`, plus its row in
`docs/adr/README.md`.

This is the same decision class as ADR-0017 (pre-push trigger fail-closed) and ADR-0025 (no
mechanical guard for CI job timeouts): what a gate does on failure, and what was deliberately
not built. Nygard format, matching the sibling files — Context, Decision, Consequences,
Related.

Content it must carry, all of it already measured and in the spec:

- **Context:** `run_update` returned 0 for every path reaching `_update_summary`, so
  `_run_or_exit` never fired for a section failure; the ledger already recorded
  `failure_stage` accurately, so the gap was the process exit rather than the record.
- **Decision:** exit code is `$(( _fail > 0 ))`. Plain 0/1, not a tri-state — widening a
  return contract breaks `fn || handler` callers, which dotfiles#194 already paid for. WARN
  does not fail, because `git-repos`, `legacy-rsync` and `git-hooks` deliberately map partial
  success to rc 0 plus a WARN row.
- **Consequences, stated as accepted rather than discovered:** ~25-32% of recent runs would
  exit 1, because `brew` has failed on 15 of the last 20 FAIL rows spread across 2026-07-07 to
  2026-08-19. Per-window table from the spec. No per-section opt-in list and no WARN
  demotion, since an exit code suppressing the one section actually failing is a gate that
  cannot fail.
- **The review trigger, and the fact that nothing enforces it:** if `brew` is still failing a
  month after this ships, fix `brew` rather than loosen the contract. Nothing schedules that
  check — name it as an open gap, the way ADR-0025 names its own.
- **Related:** the spec, ADR-0017, and the three deferred backlog rows.

The grep gate uses `Status:.*Accepted` rather than a literal, because this repo's ADRs write
`**Status:** Accepted` and a literal `Status: Accepted` cannot match it — a literal gate would
force the file into the directory's only format outlier.

**Interfaces:**

- Consumes: nothing.
- Produces: nothing.

---

### Task 6: Plan index and status banner

```yaml-task
id: 6
description: Mark the plan Done in the index and stamp the plan file (docs-only, no behavior change, so TDD does not apply)
role: executor
model: haiku
tdd: not-applicable
acceptance:
  - cmd: 'grep -q "plans/2026-08-29-update-run-truthfulness.md" docs/superpowers/README.md'
    exit_code: 0
  - cmd: 'grep -q "update-run-truthfulness.md) | \[spec\](specs/2026-08-29-update-run-truthfulness-design.md) | Done" docs/superpowers/README.md'
    exit_code: 0
max_retries: 2
files_touched:
  - docs/superpowers/README.md
depends_on: [5]
```

**Files:** `docs/superpowers/README.md`.

Update the existing All Plans row for `2026-08-29` — currently
`| 2026-08-29 | — | [spec](...) | In Progress |` — to name this plan file and set status
`Done`:

```markdown
| 2026-08-29 | [update-run-truthfulness](plans/2026-08-29-update-run-truthfulness.md) | [spec](specs/2026-08-29-update-run-truthfulness-design.md) | Done |
```

Do not touch the Backlog rows — the three deferred rows stay open.
