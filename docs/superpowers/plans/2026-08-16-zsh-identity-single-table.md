# Single Identity Table Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Collapse four drifted hostname→identity tables into one, so bash, zsh, and `.zprofile` answer "which machine is this" from a single source.

**Architecture:** `config/profiles.sh` stays the sole data file and gains wireless-interface keys, `ratna`, and comment rationale; `[server]` is dropped. A new `config/profiles.zsh` holds the zsh-side derivation once and is sourced by both `.zprofile` and `.zshrc.d/1_init.zsh`. `lib/detect_env.sh` derives the legacy variables from the table instead of re-testing hostnames. Read sites that were really Homebrew-prefix tests become prefix tests.

**Tech Stack:** bash 5.x, zsh 5.9+, BATS, GNU make.

## Global Constraints

- **No task's acceptance gate runs `make test`, and that is deliberate.** Measured 2026-08-16 on an uncontended Studio: `make test` is **571s** (`9:31.10 total`, 1367 ok, 0 not ok) against the Bash tool's **600s** hard maximum. Twenty-nine seconds of margin, on a run with nothing else competing — and `USER.md` records suite contention as this box's default condition, since every repo's session shares one CPU. A subagent whose command exceeds the cap has it auto-backgrounded, and a backgrounded command never wakes a subagent, so the task stalls awaiting a notification that does not exist.

  This deviates from `writing-plans`' "use the aggregate gate, never a narrower proxy" rule, which is correct where the aggregate is reachable. It is the same mechanism that skill already carves out for wave members; the trigger there is a shared worktree and here it is wall-clock, but the failure is identical. Tasks therefore gate on their own bats file plus `make lint`, and **the orchestrator runs `make test` after each task in the main thread via `run_in_background`**, which has no cap. That single uncontended run is the real gate, so nothing is weakened — it just runs one level up, where it can complete.

  Measured gate costs, so no task is sized against a guess: `make lint` 15s · `tests/setup_env/profiles.bats` 3s · `tests/zshrc.d/unit.bats` 5s · `tests/scripts/makefile_lint_scope.bats` 22s · `tests/setup_env/unit.bats` 69s.

- `make lint` runs `bash -n` over `SHELL_FILES`, `zsh -n` over `ZSH_FILES`, then shellcheck. It is the pre-commit hook, so a task that leaves it red cannot commit.
- The zsh file list has **two independent call sites**: `Makefile:46` (`ZSH_FILES`) and `.github/workflows/ci.yml:60` (an inline `git ls-files` copy in `lint-macos`). Any change to that set must land in both. Verified 2026-08-16.
- zsh does not word-split unquoted expansions (`SH_WORD_SPLIT` off by default). A capability string must be split with `${=var}` in zsh where bash uses bare `${var}`. Measured on both dev boxes.
- zsh sources bash's `declare -A M=( [k]=v )` correctly, on zsh 5.9 (Linux) and 5.9.2 (macOS). This is why one shared data file works with no generation step.
- `${0:A:h}` in a sourced zsh file resolves through a symlink to the target's directory. Measured cross-directory on both boxes.
- `zsh -n config/profiles.sh` exits 0 today, so that file can join `ZSH_FILES` without a rewrite. Measured 2026-08-16.
- Preserve exactly: `_OVERRIDE_KEYCHAIN_BIN`, `_OVERRIDE_RBENV_BINARY`, `_OVERRIDE_GNUBIN_ARM`, `_OVERRIDE_GNUBIN_INTEL`, and the `[[ -o interactive ]]` guard around the keychain block. Each is load-bearing and documented in `CLAUDE.md` / `shell.md`.
- CI installs `zsh` in the ubuntu `test` and `bash-coverage` jobs, so bats tests that shell out to zsh run in CI. Verified in `ci.yml:18,129`.
- The CI test-count floor is 840 (`ci.yml:35`); current count is 1367. Adding tests only moves it up.

## Verification

**Command that proves the whole change works:**

```bash
make test
bash scripts/run-bash-coverage.sh --list-sources
```

**Expected:** `make test` exits 0 with a test count above 1367 and zero `not ok` lines. The coverage source list still contains `config/profiles.sh` and does not contain `config/profiles.zsh` (zsh is not instrumented by a bash tracer).

**Run it as a background command and read the log, never as a pipeline.** At 571s it exceeds the Bash tool's foreground default, and `shell.md` records that piping a gate into `head`/`tail` discards both the failing lines and the failing status — a green result was once reported to the operator from a command whose `tail -3` had scrolled the `not ok` lines away:

```bash
make test > /tmp/mt.log 2>&1; rc=$?
grep -cE '^ok ' /tmp/mt.log; grep -E '^not ok' /tmp/mt.log
[ "$rc" -eq 0 ]
```

Note that `grep -c` exits 1 on zero matches, so a trailing `grep -c '^not ok'` makes a passing run look failed. That happened while measuring this plan's baseline and cost a false alarm.

**Baseline for comparison, measured on this tree 2026-08-16:** `1367 ok, 0 not ok, rc=0, 9:31.10`.

**The behavioural claim, verified directly** — for every key in `PROFILE_MAP`, bash and zsh must derive the same `PROFILE` and the same `HAS_*` set. Task 5 encodes this as a test; it is also the manual check:

```bash
for hn in $(git show HEAD:config/profiles.sh | sed -n 's/^ *\[\([a-z0-9-]*\)\]=.*/\1/p'); do
  b=$(MOCK_HOSTNAME_OUTPUT="$hn" bash -c 'source lib/detect_env.sh; detect_env; \
        echo "$PROFILE $(set | grep -o "^HAS_[A-Z]*" | sort | tr "\n" " ")"')
  z=$(MOCK_HOSTNAME_OUTPUT="$hn" zsh -c 'source config/profiles.zsh; \
        echo "$PROFILE $(set | grep -o "^HAS_[A-Z]*" | sort | tr "\n" " ")"')
  [[ "$b" == "$z" ]] || echo "DIVERGE $hn: bash=[$b] zsh=[$z]"
done
```

**Expected:** no `DIVERGE` lines. This is the differential the spec's design rests on, and it is the gate that would catch a derivation written correctly for one shell and wrongly for the other.

**Edge cases that must be exercised:** an unmapped hostname (`PROFILE=unknown`, zero capabilities, `run_doctor` reports it); empty `hostname -s` output; a hostname that is a prefix of a real key (`studio-2` must resolve to `unknown`, not to `studio`); and re-sourcing `config/profiles.zsh` in one shell, since a login+interactive shell sources it twice.

**Test isolation requirement, applies to every task below.** The operator's own shell exports `STUDIO=1` (and peers on other machines export their own). Any test asserting on a legacy variable MUST strip them first — `env -u STUDIO -u LAPTOP -u RECEPTION -u OFFICE -u HOMES -u WORKSTATION -u CRUNCHER -u RATNA` — or it reads the caller's environment and false-passes. This was hit live while measuring the spec: a first measurement showed `STUDIO=[1]` for hostname `studio-1`, which is the wrong answer arriving via inheritance.

---

## Task 1: Widen PROFILE_MAP to wireless pairs, add ratna, drop server

```yaml-task
id: 1
description: Add wireless-interface keys and ratna to PROFILE_MAP, drop the retired server profile, and cover every key with a wired/wireless equivalence test
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: bats tests/setup_env/profiles.bats
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched:
  - config/profiles.sh
  - tests/setup_env/profiles.bats
depends_on: []
```

**Baseline (measured 2026-08-16, so the gate is proven falsifiable):** `grep -c 'studio-1\|laptop-1\|ratna-1\|reception-1\|office-1' tests/setup_env/profiles.bats` returns **0**. The gate cannot pass on the pre-change tree because the tests do not exist.

**Files:** `config/profiles.sh`, `tests/setup_env/profiles.bats`

Write the tests first. For each wireless key, assert it resolves to the same `PROFILE` **and** the same `HAS_*` set as its wired twin — not just the same `PROFILE`, since a matching profile string with a divergent capability set is the failure this work exists to prevent.

`PROFILE_MAP` becomes:

```bash
declare -A PROFILE_MAP=(
  [laptop]="personal_laptop"      [laptop-1]="personal_laptop"
  [studio]="mac_workstation"      [studio-1]="mac_workstation"
  [reception]="mac_workstation"   [reception-1]="mac_workstation"
  [ratna]="mac_workstation"       [ratna-1]="mac_workstation"
  [office]="mac_mini"             [office-1]="mac_mini"
  [home-1]="mac_mini"
  [workstation]="linux_workstation"
  [cruncher]="wsl2_workstation"
)
```

Three comments are required in the file, because none is inferable from the data and each was established by asking the operator:

- A `-1` suffix is the machine's **wireless interface** hostname. `workstation` and `cruncher` are wired-only. `home-1` is the exception — there `-1` is part of the machine name, a naming mistake kept because a `home-2` may follow.
- `reception` carries `mac_workstation` rather than `mac_mini` despite being the same hardware class as `office` and `home-1`: it was a full-time dev box at work and still has the toolchain, though the work moved to remote SSH.
- `ratna` carries `mac_workstation` because it was a home dev box for years and is now a server-room terminal that keeps the full toolchain deliberately.

Delete `[server]="devtools aws"` from `PROFILE_CAPS` — it belonged to a retired mac mini and no hostname has mapped to it.

Do **not** collapse `personal_laptop` and `mac_workstation`, which carry identical capability sets. That is a separate decision, recorded in the spec as an observation.

Required test cases beyond the pairs: unmapped hostname → `PROFILE=unknown` with zero `HAS_*`; empty `hostname -s` → `unknown`; `studio-2` → `unknown` (a prefix of a real key must not match it).

**Interfaces:**

- Consumes: nothing.
- Produces: `PROFILE_MAP` with 13 keys and `PROFILE_CAPS` with 5 profiles (`personal_laptop`, `mac_workstation`, `mac_mini`, `linux_workstation`, `wsl2_workstation`). Tasks 2 and 4 read both by sourcing this file.

---

## Task 2: Add config/profiles.zsh, the zsh-side derivation

```yaml-task
id: 2
description: New zsh resolver that sources the shared table and derives PROFILE, HAS_* and the legacy identity variables
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: bats tests/zshrc.d/profiles.bats
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched:
  - config/profiles.zsh
  - tests/zshrc.d/profiles.bats
depends_on: [1]
```

**Baseline:** `ls config/profiles.zsh` returns `No such file or directory` (measured 2026-08-16), so both gates fail on the pre-change tree.

**Files:** `config/profiles.zsh` (new), `tests/zshrc.d/profiles.bats` (new)

The file locates the table relative to itself, so it works when symlinked into `$HOME`:

```zsh
source "${0:A:h}/profiles.sh"
```

Derivation notes that are not optional:

- Split the capability string with `${=PROFILE_CAPS[$PROFILE]}`. A bare `${...}` does not split in zsh and yields one capability named `"gui devtools aws …"`. Measured on both boxes.
- Use `export`, never `readonly`. `.zprofile` and `1_init.zsh` both source this file, so a login+interactive shell runs it twice; `readonly` makes the second run fail. `1_init.zsh` already carries a `${NOBLE+x}` guard for the same reason.
- Set the legacy variables (`LAPTOP`, `STUDIO`, `RECEPTION`, `OFFICE`, `HOMES`, `WORKSTATION`, `CRUNCHER`, `RATNA`) from the resolved hostname, so every existing read site keeps working unchanged.

Tests must cover: each of the 13 keys sets the right legacy variable and `HAS_*` set; an unmapped hostname sets none; sourcing twice in one shell is idempotent and does not error. Follow `tests/zshrc.d/unit.bats`'s existing pattern — do **not** call `load_mocks()` at setup scope, because prepending `tests/mocks/` to the outer `PATH` corrupts `PATH` for zsh subprocesses; inject the `hostname` stub inside each `zsh -c` invocation instead.

**Interfaces:**

- Consumes: `PROFILE_MAP`, `PROFILE_CAPS` from Task 1.
- Produces: `config/profiles.zsh`, sourceable from any zsh context, exporting `PROFILE`, `HAS_<CAP>` and the eight legacy variables. Task 3 sources it; Task 5 diffs it against the bash side.

---

## Task 3: Point .zprofile and 1_init.zsh at the resolver

```yaml-task
id: 3
description: Delete the two zsh hostname tables and source config/profiles.zsh instead
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: bats tests/zshrc.d/unit.bats
    exit_code: 0
  - cmd: zsh -i -c exit
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched:
  - .zprofile
  - .config/.zshrc.d/1_init.zsh
  - tests/zshrc.d/unit.bats
depends_on: [2]
```

**Files:** `.zprofile`, `.config/.zshrc.d/1_init.zsh`, `tests/zshrc.d/unit.bats`

Delete `.zprofile` lines 2–13 (twelve hostname lines, including the duplicate `workstation` at line 13 and the `homes`/`homes-1` spellings that match no machine) and `1_init.zsh` lines 17–25 (nine hostname lines). Both source `config/profiles.zsh` in their place.

`.zprofile` is symlinked at `~/.zprofile`, so it must reach the repo via `${0:A:h}`, not a hardcoded path. `1_init.zsh` is symlinked under `~/.config/.zshrc.d/`, so its relative path to the repo root differs — resolve it the same way and verify, do not assume the two are identical.

Leave `.zprofile:17`'s five-mac guard alone. It reads legacy variables, which are now derived, so it keeps working; converting it to a prefix test is out of scope.

Three regressions to pin, each of which is live on the pre-change tree:

1. Hostname `office` sets `OFFICE` from `1_init.zsh` alone, with no `.zprofile` in the chain. Today `1_init.zsh` never sets it and it survives only by `.zprofile`'s export leaking into child processes.
2. Hostname `home-1` sets `HOMES` from `.zprofile`. Today `.zprofile` matches `homes`/`homes-1` and cannot.
3. Hostname `cruncher` sets `CRUNCHER` from `.zprofile`. Today `.zprofile` reads it at line 21 without ever setting it.

`zsh -i -c exit` is in the gate because `.zshrc.d` changes can crash a re-source in a way `zsh -n` cannot see — a standing rule in `CLAUDE.md`.

**Interfaces:**

- Consumes: `config/profiles.zsh` from Task 2.
- Produces: both zsh entry points deriving identity from the shared table. No new symbols.

---

## Task 4: Derive the legacy variables in detect_env.sh from the table

```yaml-task
id: 4
description: Replace the hostname-testing legacy alias block with derivation from PROFILE_MAP so bash matches zsh
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: bats tests/setup_env/profiles.bats
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched:
  - lib/detect_env.sh
  - tests/setup_env/profiles.bats
depends_on: [1]
```

**Files:** `lib/detect_env.sh`, `tests/setup_env/profiles.bats`

Delete the five-entry legacy alias block (five `readonly` assignments plus their five `shellcheck disable` comments, ten lines) and derive the same variables from the resolved hostname. The bash side currently sets `OFFICE` but not `RATNA`, `WORKSTATION` or `CRUNCHER`; after this task it sets all eight, matching zsh.

Keep `readonly` here — `detect_env` runs once per bash process and the existing tests rely on it. This deliberately differs from Task 2's `export`, because the zsh file is sourced twice per login shell and the bash function is not. State that asymmetry in a comment; a future reader will otherwise "fix" one to match the other.

Tests must assert each legacy variable for its hostname, with the ambient variables stripped via the `env -u` list in the Verification section. Without the strip these tests pass on the operator's machine regardless of what the code does.

**Interfaces:**

- Consumes: `PROFILE_MAP` from Task 1.
- Produces: `detect_env()` setting `PROFILE`, `HAS_*` and all eight legacy variables. Task 5 diffs this against Task 2's output; Task 8 reads `PROFILE`.

---

## Task 5: Cross-shell equivalence test

```yaml-task
id: 5
description: Assert bash and zsh derive identical PROFILE and HAS_* sets for every key in the table
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: bats tests/zshrc.d/cross_shell.bats
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched:
  - tests/zshrc.d/cross_shell.bats
depends_on: [2, 4]
```

**Files:** `tests/zshrc.d/cross_shell.bats` (new)

This is the task that matters. The existing suite's oracle is derived from the same wired-only table it checks, so it agrees by construction — `tests/setup_env/profiles.bats` has 20 tests, all on wired hostnames, and its line-46 test asserts `PROFILE=unknown` for an unrecognised hostname, which `studio-1` satisfies. Two shells reading one table is an oracle produced by a different mechanism than the target, which is the property the suite currently lacks.

Enumerate the keys **from the table itself**, not from a list typed into the test — a hand-typed list reintroduces exactly the drift this plan removes, and a key added to `PROFILE_MAP` without a test would go unnoticed:

```bash
mapfile -t KEYS < <(bash -c 'source "$1"; printf "%s\n" "${!PROFILE_MAP[@]}"' _ "${REPO_ROOT}/config/profiles.sh" | sort)
```

Source the file and read `${!PROFILE_MAP[@]}` — do **not** scrape it with `sed`. A regex over `^ *\[\(...\)\]=` also matches `PROFILE_CAPS`'s entries, so it needs a `head -N` to stop at the boundary, and that N is a magic number that silently truncates or over-reads the moment either array changes size. The first draft of this plan carried exactly that (`head -14`) with the wrong N, because the key count had been reasoned about rather than run. Sourcing has no boundary to guess.

Guard the derived list: assert it is non-empty and that its length equals `${#PROFILE_MAP[@]}` before looping. An empty list makes every assertion in the loop vacuously true, which is indistinguishable from a pass.

For each key, capture `PROFILE` and the sorted `HAS_*` names from bash (`source lib/detect_env.sh; detect_env`) and from zsh (`source config/profiles.zsh`), with the `env -u` strip applied to both, and assert the two strings are equal.

**Mutation guard, required before the task reports green:** temporarily change one wireless key in `PROFILE_MAP` to a different profile, confirm this test goes red, and revert. A test that has never been seen to fail is not yet a test.

**Interfaces:**

- Consumes: `config/profiles.zsh` (Task 2), `detect_env()` (Task 4), `PROFILE_MAP` (Task 1).
- Produces: nothing consumed downstream.

---

## Task 6: Replace the ARM-mac hostname lists with a Homebrew prefix test

```yaml-task
id: 6
description: Collapse 5_general.zsh CHRUBY_LOC and FZF_BASE host lists to a prefix test, deleting the always-true {OFFICE} typo
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: bats tests/zshrc.d/unit.bats
    exit_code: 0
  - cmd: zsh -i -c exit
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched:
  - .config/.zshrc.d/5_general.zsh
  - tests/zshrc.d/unit.bats
depends_on: [3]
```

**Files:** `.config/.zshrc.d/5_general.zsh`, `tests/zshrc.d/unit.bats`

Lines 5–11 and 18 each enumerate hostnames to mean _"an ARM mac"_ — a `RATNA` arm for the Intel prefix, a five-host list for the ARM one, once for `CHRUBY_LOC` and once for `FZF_BASE`. Both become a prefix test with no hostname in it.

Line 18 currently reads `[[ -n {OFFICE} ]]` — no `$`. zsh evaluates the braces as a literal non-empty string, so the branch is **always taken**. Measured on both dev boxes: `brace=ALWAYS-TRUE`. This task deletes the construct rather than adding the missing `$`.

**This is a real behaviour change on three machines and must be stated in the commit message.** `FZF_BASE` is currently exported as `/opt/homebrew/bin/fzf` on `ratna` (x86_64, Homebrew at `/usr/local`) and on both Linux boxes, where the path does not exist. After this task it is unset there and line 21's `[ -f ~/.fzf.zsh ] && source` fallback is what those machines use.

Required tests: on a tree with `/opt/homebrew` present, `CHRUBY_LOC` and `FZF_BASE` take ARM values; with only the Intel prefix present, `CHRUBY_LOC` takes the Intel value and `FZF_BASE` is unset; with neither present, both are unset. Drive prefix presence through the existing `_OVERRIDE_GNUBIN_ARM` / `_OVERRIDE_GNUBIN_INTEL` seams or add an equivalent one — do **not** test the real `/opt/homebrew`, which exists on every provisioned mac and would short-circuit the guard so the test asserts nothing. `CLAUDE.md` records that exact trap for these seams.

**Interfaces:**

- Consumes: nothing new.
- Produces: `CHRUBY_LOC` unchanged in name and meaning. Task 7 edits the same file below these lines.

---

## Task 7: Collapse the seven keychain host arms

```yaml-task
id: 7
description: Reduce the keychain block to a capability test plus one key list, and make its binary path a prefix test
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: bats tests/zshrc.d/unit.bats
    exit_code: 0
  - cmd: zsh -i -c exit
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched:
  - .config/.zshrc.d/5_general.zsh
  - tests/zshrc.d/unit.bats
depends_on: [6]
```

**Files:** `.config/.zshrc.d/5_general.zsh`, `tests/zshrc.d/unit.bats`

Six of the seven mac arms are byte-identical (`id_rsa`, `home`, `github`, `gitlab`, plus commented-out entries). The Linux split is workstation/cruncher with the same four keys versus everything else with `id_rsa` only — which is "a known profile or not", now expressible against the table.

`home-1`'s arm is the sole outlier: `keychain --eval any home` rather than `--eval home`. `any` is not a keychain flag, so it is read as a key name. **Drop it.** If that key turns out to be real, the revert is one line; retaining it would force a per-host carve-out back into a design whose purpose is removing per-host carve-outs. Refuted by `ls ~/.ssh/any*` on `home-1` returning a key.

The binary-path selection at line 191 (`RATNA` → `/usr/local/bin/keychain`, otherwise `/opt/homebrew/bin/keychain`) becomes a prefix test, consistent with Task 6.

**Preserve exactly, both of them:** `_OVERRIDE_KEYCHAIN_BIN` and the `[[ -o interactive ]]` wrapper. `shell.md` records that the absolute paths defeat a `PATH` mock, which is why the seam exists at all. `CLAUDE.md` records that the interactive guard is what stopped `make test` hanging forever on leaked `ssh-agent` processes holding the bats output pipe — 16 agents on the suite's pipe, 161 accumulated. Removing either reintroduces a measured incident.

The two existing tests for that guard are a **pair** and both must still pass: the non-interactive test asserts zero keychain calls, and the interactive test is the control proving production actually reads the seam. The negative test alone stays green under a typo'd seam name.

**Interfaces:**

- Consumes: `HAS_*` from Task 2's resolver.
- Produces: nothing consumed downstream.

---

## Task 8: Doctor check for an unresolved profile

```yaml-task
id: 8
description: run_doctor fails when PROFILE is unknown, so an unmapped hostname stops degrading silently
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: bats tests/setup_env/unit.bats
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched:
  - lib/helpers.sh
  - tests/setup_env/unit.bats
depends_on: [1]
```

**Files:** `lib/helpers.sh`, `tests/setup_env/unit.bats`

`run_doctor` gains a check that `PROFILE != unknown`, following the existing `command -v` pattern. This is the detection that would have surfaced the wireless defect: an unmapped hostname currently produces `PROFILE=unknown` with zero capabilities, which is a well-formed answer that nothing reports.

The failure message must name the hostname and point at `config/profiles.sh`, since the remedy is adding a row there. Follow the file's existing `_DOCTOR_FAIL` / `doctor_warn` conventions — `CLAUDE.md` records that `_DOCTOR_FAIL` and `_DOCTOR_FAILED` are different things and that `log_warn` and `doctor_warn` are not interchangeable.

Tests: a mapped hostname passes; an unmapped hostname fails with a non-zero `run_doctor` exit and a message naming the hostname.

**Interfaces:**

- Consumes: `PROFILE` from Task 4's `detect_env()`.
- Produces: nothing consumed downstream.

---

## Task 9: Add config/profiles.sh to the zsh lint scope, both call sites

```yaml-task
id: 9
description: The shared table is now zsh-consumed, so zsh -n must cover it in the Makefile and in the CI job's independent copy of the file list
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: bats tests/scripts/makefile_lint_scope.bats
    exit_code: 0
  - cmd: 'bash -c ''make print-ZSH_FILES | tr " " "\n" | grep -qx config/profiles.sh'''
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched:
  - Makefile
  - .github/workflows/ci.yml
  - tests/scripts/makefile_lint_scope.bats
depends_on: [2]
```

**Files:** `Makefile`, `.github/workflows/ci.yml`, `tests/scripts/makefile_lint_scope.bats`

`config/profiles.sh` is sourced by zsh from Task 2 onward, so it needs `zsh -n` as well as `bash -n` and shellcheck. It stays in `SHELL_FILES` — one file, both parsers. `zsh -n config/profiles.sh` already exits 0, measured 2026-08-16, so this adds coverage rather than work.

**Both call sites, not one.** `Makefile:46` builds `ZSH_FILES`; `.github/workflows/ci.yml:60` has its own inline `git ls-files '*.zsh' '*.zsh-theme' '.zshrc' '.zprofile'` inside `lint-macos`. Changing only the Makefile leaves CI checking the old set — the fix-one-call-site shape `behavior.md` names, and the reason `tdd.md` pitfall G's make-version fix stayed red through a CI round.

Add a test asserting the two lists agree, so a future divergence is caught mechanically rather than by someone remembering. `tests/scripts/makefile_lint_scope.bats` already derives its domain from `git ls-files` with the four-variable `env -u` strip; follow that pattern.

Keep the existing empty-list guards intact — both sites refuse to report a pass on an empty file list, and that property must survive.

`model: sonnet` is required rather than a choice: `files_touched` includes a `.github/workflows/*` path, which the haiku scope guard rejects.

**Interfaces:**

- Consumes: `config/profiles.zsh` exists (Task 2), establishing that the table is zsh-consumed.
- Produces: `ZSH_FILES` including `config/profiles.sh`.

---

## Task 10: Documentation and index

```yaml-task
id: 10
description: Update CLAUDE.md Profile Model and Adding a New Machine for the wired/wireless rule and record the plan as Done (docs-only, no behavior change)
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: 'grep -q "wireless" CLAUDE.md'
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched:
  - CLAUDE.md
  - docs/superpowers/README.md
  - docs/superpowers/plans/2026-08-16-zsh-identity-single-table.md
depends_on: [3, 4, 5, 6, 7, 8, 9]
```

**Files:** `CLAUDE.md`, `docs/superpowers/README.md`, this plan file

`tdd: not-applicable` because this task changes only prose and index rows; every behavioural change it describes was tested by Tasks 1–9.

`CLAUDE.md` updates:

- **Profile Model** — record that a `-1` suffix is the wireless-interface hostname and that both spellings map to the same profile; note `home-1` as the exception where `-1` is part of the machine name.
- **Adding a New Machine** — the numbered steps must say to add **both** the wired and wireless keys, since the machine will otherwise lose every capability whenever it is on wifi.
- **Testing** — the test count moves off 1367. Take the new figure from the CI run on the merged PR, never from a local run; `CLAUDE.md` already records that local macOS measures one point above CI and that publishing the local number is how the coverage figure went wrong before.
- **Test Seams** — document `config/profiles.zsh` and note the deliberate `export`-versus-`readonly` asymmetry against `detect_env.sh`.

`docs/superpowers/README.md`: set this plan's row to `Done`. Add the `> **Status: DONE**` banner at the top of this plan file.

**Interfaces:**

- Consumes: the completed state of every prior task.
- Produces: nothing.

---

## Self-Review

**Spec coverage.** Every in-scope item maps to a task: table (T1), resolver (T2), zsh consumers (T3), bash derivation (T4), cross-shell equivalence (T5), prefix collapse and the `{OFFICE}` typo (T6), keychain collapse (T7), doctor check (T8), lint scope (T9), docs (T10). Out-of-scope items — `Make()` gmake paths, the gcloud sites, `.zprofile:17` — appear in no task and already carry backlog rows.

**Gate falsifiability.** Each gate was checked against the pre-change tree rather than reasoned about: T1's wireless grep returns 0, T2's file does not exist, T9's `make print-ZSH_FILES` does not contain `config/profiles.sh`. T5 additionally carries an explicit mutation step, because a differential test that has never been seen fail is not yet a differential.

**Gate blindness.** Asked of each task: name a wrong implementation that still passes. For T1–T4 the answer is a derivation correct in one shell and wrong in the other, which is precisely what T5 exists to catch — so T5 is load-bearing rather than decorative, and the plan is weaker than it looks if T5 is skipped or weakened. For T6 the answer is a test run against the real `/opt/homebrew`, which exists on every provisioned mac and makes the guard short-circuit; the task therefore mandates the override seams. For T7 it is the negative-only keychain assertion, which is why the task requires both halves of the existing pair to keep passing.

**Baselines measured under a configuration this plan changes.** None. Every figure cited — 0 wireless tests, 13 table keys, `zsh -n` exit 0, the two zsh-list call sites, CI's zsh availability — was measured against the current tree, and none of them is altered by an earlier task in a way that invalidates a later one.

**Correction, recorded rather than quietly fixed.** That sentence originally read "14 table keys", and the key count was the one figure in the list that had been _counted in reasoning_ rather than run. It is 13. The error reached four places in this plan, including a `head -14` in Task 5's key extraction — a magic number that would have silently over-read into `PROFILE_CAPS` had the arrays been a different size. It was caught by Task 1's spec reviewer counting the table key-by-key, not by any of this plan's own checks, and specifically not by the sentence above claiming everything was measured. A self-review section asserting that every figure was measured is worth exactly as much as the least-measured figure in it, and prose cannot tell you which one that is.

**ADR significance.** No new Phase 3 gate, HOLD-capable check, storage choice, or security guardrail. T8 adds a `run_doctor` check, which is a health probe rather than a merge gate. No ADR required.

**`files_touched` matches the prose.** Checked per task; T9 is the one that needed care, since its body describes editing the Makefile, the CI workflow, and a test, and all three are declared. No task declares `model: haiku`, so the single-file scope guard is not engaged.

**Token budget.** Every task block is under 2KB. No parallel groups are declared — the dependency chain is genuinely sequential and only T1/T9 could overlap, which is not worth the shared-worktree hazards that wave dispatch carries.

**Gate reachability.** Every acceptance command was timed against this tree before being written into a task, not assumed. That check is what caught the aggregate gate: the first draft put `make test` in all ten tasks per `writing-plans`' standing rule, and measurement showed it at 571s against a 600s cap — reachable on paper, unreachable in practice under this box's normal contention. The gates were rewritten before the plan was committed rather than discovered stalling at dispatch. The general form is the rule this plan is itself an instance of: a gate is a claim about what an instrument will report, so run the instrument first.
