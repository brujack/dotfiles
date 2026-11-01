# Setup floor, part 1: two quick wins in the bats setup helpers

- **Approved:** 2026-11-01

## Problem

The P1 backlog row "Per-test setup floor dominates many bats files" measured, serially on the
Studio, about 190 ms of setup per test (`load_setup_env` ~95 ms plus `load_mocks` ~95 ms) and
estimated that `tests/setup_env/linux_ubuntu.bats` spends ~61% of its time in setup.

Re-measured on `claude` (Linux, 2026-11-01, `bash` timing harness sourcing
`tests/helpers/common.bash`, 5 samples each):

| Helper           | Per call | Tests that call it in `setup()` |
| ---------------- | -------- | ------------------------------- |
| `load_mocks`     | 54-64 ms | 2771 of 3752                    |
| `load_setup_env` | 60-78 ms | 2644 of 3752                    |

Population: the per-call figures are from one process on one Linux box, outside bats; the
caller counts are a static scan of every tracked `tests/**/*.bats` `setup()` body.

Two causes are mechanical, not inherent, and both were located with a `PS4` timestamp trace
and an `strace -e execve` count:

1. **`load_mocks` calls its own mocks.** It prepends `tests/mocks` to `PATH` part-way through,
   then runs `chmod +x` five times (generated stubs) and `cp` once (the claude-settings copy).
   Those resolve to the pass-through wrappers `tests/mocks/chmod` and `tests/mocks/cp`. Each
   wrapper is `#!/usr/bin/env bash`, so each call costs `env`, a `PATH` walk (9 failed `execve`
   attempts before `bash`), a bash start and the real binary: 6.4-7.1 ms per call, about 37 ms
   of the 60 ms.
2. **`setup_env.sh` forks `dirname` 14 times.** Each of its 13 `source` lines and the
   `_LOCAL_CFG` assignment runs `$(dirname "${BASH_SOURCE[0]}")`, about 1.1-1.6 ms each.

Cause 1 also breaks isolation. Every `setup()` that was checked calls `load_mocks` before it
sets `MOCK_CALLS_FILE` (`tests/setup_env/linux_ubuntu.bats`, `tests/setup_env/workflows.bats`),
and the wrappers log to `${MOCK_CALLS_FILE:-/tmp/mock_calls}`. So every such test appends six
lines to one shared file outside its tmpdir, from every test, in every run, in parallel. On
`claude` that file was 83,391,304 bytes on 2026-11-01. No test reads those lines: tests read
the per-test `MOCK_CALLS_FILE` they set afterwards.

The row's 61% figure does not carry to Linux. An A/B over the three heaviest files
(`linux_ubuntu.bats`, `workflows.bats`, `install_guards.bats`; 976 tests; `bats --jobs 8`; two
runs per arm in `git archive` copies; all 976 ok in every run) gave:

| Arm        | Wall              | user              | sys               | CPU total |
| ---------- | ----------------- | ----------------- | ----------------- | --------- |
| baseline   | 166.26 / 166.12 s | 269.30 / 267.36 s | 437.19 / 437.49 s | ~706 s    |
| both fixes | 158.66 / 158.26 s | 254.43 / 254.54 s | 381.12 / 379.94 s | ~635 s    |

So setup is ~17% of per-test CPU on Linux (about 120 ms of ~723 ms), and the two fixes save
~10% CPU and ~5% wall on those files. `sys` is 62% of the baseline CPU: the larger cost is
process creation throughout the test bodies, which is part 2 (a separate spec).

## Design

### `load_mocks` prepends `tests/mocks` last

Move `export PATH="${REPO_ROOT}/tests/mocks:${PATH}"` from its current position to the last
statement of `load_mocks`. Everything `load_mocks` runs before it (`cat`, `chmod`, `cp`,
`mkdir`, `printf` into generated stubs and fixtures) then resolves to real binaries.

The environment `load_mocks` leaves behind is unchanged: the same exports, the same files under
`BATS_TEST_TMPDIR`, and `tests/mocks` first on `PATH`. The only observable difference is that
`load_mocks` itself no longer writes to `MOCK_CALLS_FILE` (or its `/tmp/mock_calls` fallback).

### `setup_env.sh` resolves its directory once for the lib block

Before the first `source` line, set `_SETUP_ENV_DIR="$(dirname "${BASH_SOURCE[0]}")"`, use
`"${_SETUP_ENV_DIR}/lib/<name>.sh"` in the 13 `source` lines, and `unset _SETUP_ENV_DIR`
immediately after the last of them, before the sourcing guard. `dirname` keeps its exact
semantics, including `.` for a bare `setup_env.sh`. Fourteen forks become two when the script is executed, and one when it is sourced (every test), since the `_LOCAL_CFG` line runs only after the sourcing guard.

The `_LOCAL_CFG` line keeps its own `$(dirname "${BASH_SOURCE[0]}")`. It sits after the
sourcing guard, so it runs only when the script is executed; moving it above the guard would
set `_LOCAL_CFG` in every sourced shell, which every test is, and that is a behaviour change
this PR does not make.

The unset matters because the value depends on the caller: `load_setup_env` sources
`${REPO_ROOT}/setup_env.sh`, so in tests it is absolute, while `./setup_env.sh` in production
gives `.`. A lib function that reused a leftover `_SETUP_ENV_DIR` would pass every test and
break after a `cd`, the hazard `tests/setup_env/developer.bats` already documents for
`update_aws_cli`'s verifier. Unset, nothing can reuse it.

### Stale comment

`load_mocks`' comment about resolving the real git "before the prepend below" stays true after
the move (the prepend is still below it), but is reworded to say the prepend is the function's
last statement and why.

## Testing

TDD, bats:

- **R1, red on master.** In the file that already tests `tests/helpers/common.bash` (the plan
  names it), with `MOCK_CALLS_FILE` set to an existing empty file before `load_mocks`: the file
  is still empty afterwards (on failure the test prints its contents, so a later stub placed
  after the prepend names the mocked command that logged), and the first `PATH` entry afterwards
  is `${REPO_ROOT}/tests/mocks`. Measured on `88cf9aca` in an archive copy: master writes 6 lines
  (5 `chmod`, 1 `cp`). Measured in round 3: with the prepend moved, the exported environment and
  every generated file under `BATS_TEST_TMPDIR` (excluding the fixture's `.git` internals) are
  identical to master's.
- **R2, red on master.** `tests/setup_env/unit.bats`, structural, not a text count. The guard is
  located by its form, the line matching `&& return 0` (line 57 today), never by the first
  `BASH_SOURCE[0]`-versus-`${0}` comparison: line 4 is a second such comparison, and a parser
  stopping there inspects zero lines and passes vacuously. Above the guard, the test inspects the
  top-level `source` lines, asserts their count equals `git ls-files 'lib/*.sh' | wc -l` (13
  today), and asserts each references `${_SETUP_ENV_DIR}` and none contains `$(dirname`; it also
  asserts `_SETUP_ENV_DIR` is unset after sourcing. Master has 13 lines of the old form, so it is
  red there. A count of the text `dirname` was rejected: a harmless comment or an unrelated later
  use would turn it red with no hint of the cause.
- **R3, a characterization guard, green on master by design.** `tests/setup_env/unit.bats`, in a
  separate process: `run env -u GO_VER bash -c 'cd "${REPO_ROOT}/lib" && source
  ../setup_env.sh && <check>'`, with the relative path built by that `cd`, never by
  `realpath --relative-to` (GNU-only; absent on the macOS shards). The check loops over a
  `lib:marker` table and prints `missing <marker> (lib/<file>)` for each marker not defined:
  - one marker per file in `git ls-files 'lib/*.sh'`, and the test asserts the table has that
    many rows, so a new lib fails until it gets a marker;
  - a function defined in exactly one lib file, public where the file has one (e.g.
    `log_info`, `detect_env`, `install_ubuntu_packages`); a function defined in two libs (e.g.
    `_dry_run_active`, `_git_ssh_opts`) stays defined after its own lib's `source` line is
    deleted, so it can never be a marker;
  - `GO_VER` for `lib/constants.sh`, which defines no function.

  The separate process is load-bearing: `unit.bats`' `setup()` already runs `load_setup_env`,
  so in the test's own shell every marker exists before the test starts, and a same-shell check
  stays green with a lib's `source` line deleted (measured in round 2: same shell green, fresh
  `bash -c` red). Measured in round 3 in an archive copy: master green, refactor green, refactor
  with `lib/git_sync.sh`'s line deleted red. It pins the refactor rather than proving it. The
  child `bash` must be bash 4 or later on the macOS shards; `CLAUDE.md` puts Homebrew bash first
  on the runner's `PATH`, and the PR's first macOS shard run confirms it.
- The full suite stays green.

## Measurement (informational)

The `claude` A/B above is the measurement of record. For macOS, the PR body quotes this PR's own
`test-macos-shard` leg timings beside master's most recent run. No separate Studio run, and no
threshold: neither figure can block the PR, because both fixes stand on their own (fewer forks,
no writes outside the test tmpdir).

## Out of scope

- Mocks themselves (shebangs, the `/tmp/mock_calls` fallback in other mocks), bats structure
  (`setup_file`, caching the sourced env), and any test body: part 2, a separate spec on
  process-spawn cost.
- Deleting the existing `/tmp/mock_calls` on any machine: an operator decision after merge.

## Requirements

- **R1.** `[PR1]` `load_mocks` prepends `${REPO_ROOT}/tests/mocks` to `PATH` as its last statement, so with `MOCK_CALLS_FILE` set to an empty file before the call the file is still empty afterwards, and the first `PATH` entry afterwards is `${REPO_ROOT}/tests/mocks`.
- **R2.** `[PR1]` `setup_env.sh` sets `_SETUP_ENV_DIR` with one `dirname` call, uses it in all 13 lib `source` lines and unsets it before the sourcing guard, while `_LOCAL_CFG` keeps its own `dirname`; a test locates the guard by its `&& return 0` form, asserts the number of top-level `source` lines above it equals the number of tracked `lib/*.sh` files, that each references `${_SETUP_ENV_DIR}` and none contains `$(dirname`, and that `_SETUP_ENV_DIR` is unset after sourcing.
- **R3.** `[PR1]` In a separate process started with `GO_VER` unset, `cd "${REPO_ROOT}/lib" && source ../setup_env.sh` leaves defined one marker per tracked `lib/*.sh` file (a function defined in exactly one lib, or `GO_VER` for `lib/constants.sh`), from a table whose row count the test asserts equals the number of tracked lib files, and a missing marker is reported as `missing <marker> (lib/<file>)`.
- **V1.** The PR body records the `claude` three-file A/B figures from this spec and this PR's `test-macos-shard` leg timings beside master's most recent run, as information only.
- **N1.** No change to any file under `tests/mocks/`.
- **N2.** No change to what any existing test asserts.
- **N3.** No change to bats structure: no `setup_file`, no cached or exported function definitions.

## Multi-Lens Review

Round 1 reviewed at commit: `88cf9aca` (spec as first written, before Step 8 dispatch)

### Goal-Fit

Finding: No issues; worth building. Premise verified: `/tmp/mock_calls` on `claude` held 990,713 `chmod` and 197,957 `cp` lines (ratio 5.005, the 5:1 inside `load_mocks`), about 97% of the file; no test greps a `chmod`/`cp` line that only `load_mocks` writes. V1 was decoration: no threshold, the `claude` arm repeated the spec's A/B, and the Studio hosts no sessions.
Assumption: no genuinely uncertain one; closest was that no test passes only because of `load_mocks`' own log lines, settled by the full suite.
Disposition: Accepted (operator, 2026-11-01); V1 reworked under the Ergonomics item.

### Ergonomics

Finding: `_SETUP_ENV_DIR` would leak into every sourced shell with a caller-dependent value (absolute in tests, `.` in production), inviting a lib to reuse it and break after a `cd`; V1 had no decision rule and its Studio "all tests ok" could block on Studio-local noise.
Assumption: the gain has the same direction on the Studio; refuted or confirmed by a Studio A/B.
Disposition: Addressed (operator, 2026-11-01): `_SETUP_ENV_DIR` unset before the sourcing guard, `_LOCAL_CFG` keeps its own `dirname` (2 forks, not 1); V1 informational, macOS figure taken from the PR's own CI shard timings, no Studio run.

### Risk

Finding: R3 impossible as written (`lib/constants.sh` defines no function) and green on master; R2 had no test, and the `_LOCAL_CFG` path is unreached by a sourced test. Checked clean: lines between the old and new prepend position need no mock; both early `return 1` paths precede the old prepend; no file sets `MOCK_CALLS_FILE` before `load_mocks`.
Assumption: no test reads the shared `/tmp/mock_calls` fallback; settled by the orchestrator: `git grep -n '/tmp/mock_calls' -- tests ':!tests/mocks'` outside the `${MOCK_CALLS_FILE:-/tmp/mock_calls}` writes returned nothing.
Disposition: Addressed (operator, 2026-11-01): R3 uses `GO_VER` for constants and is labelled a characterization guard; R2 gains a static count test (2, red on master's 14) plus an unset check; stale comment reworded.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.

### Round 2 (`95e571d2`)

- **Goal-Fit.** Lens skipped: the dispatch was denied by the auto-mode classifier. Disposition: Accepted (operator, 2026-11-01); round 1 found no issues and the revision did not change goal or scope.
- **Ergonomics.** Finding: R2's exact text count of `dirname` is brittle (a harmless comment or an unrelated later use turns it red with no cause shown). Premise re-verified on a fresh copy: 6 log lines, 14 `dirname`. Disposition: Addressed (operator, 2026-11-01): R2 is now structural.
- **Risk.** Finding: R3 cannot fail in `unit.bats`' own shell, because `setup()` already ran `load_setup_env` (same shell green with a lib line deleted, fresh `bash -c` red); "fourteen forks become two" holds only when executed. Checked clean: nothing reads `_SETUP_ENV_DIR`, `GO_VER` is top-level in `lib/constants.sh`, each other lib defines a top-level function; the orchestrator confirmed no lib runs `$(command -v` at top level. Disposition: Addressed (operator, 2026-11-01): R3 runs in a separate process with `GO_VER` unset; wording corrected.

### Round 3 (`7fd64f90`)

- **Goal-Fit.** Lens skipped: the dispatch was denied by the auto-mode classifier twice (brief reworded between attempts). Disposition: Addressed (operator, 2026-11-01).
- **Ergonomics.** Finding: R3 red names no lib; its marker list does not grow with `lib/`; markers defined in two libs (`_dry_run_active`, `_git_ssh_opts`) give a false green; the relative path must be built portably (`realpath --relative-to` is GNU-only); R1 should print the calls file on failure. Probe in an archive copy: R2 red then green, R3 green, red with `lib/git_sync.sh`'s line deleted. Assumption: the child `bash` on the macOS shards is bash 4 or later. Disposition: Addressed (operator, 2026-11-01): `lib:marker` table with per-marker messages, row count tied to `git ls-files 'lib/*.sh'`, single-definition markers, `cd "${REPO_ROOT}/lib" && source ../setup_env.sh`, R1 prints the file; the bash assumption is confirmed by the PR's first macOS shard run.
- **Risk.** Finding: R2 could pass vacuously, because `setup_env.sh` line 4 is a second `BASH_SOURCE[0]`-versus-`${0}` comparison and a parser stopping there inspects zero lines. Checked clean: bats exports no lib function, nothing sets `BASH_ENV` but the coverage tracer, `GO_VER` is not exported, the relative path resolves from `tests/`. Assumption (`load_mocks` needs no mock override before the moved prepend) settled by the orchestrator: exported environment and every generated file identical, master vs moved, apart from the fixture's `.git` internals; mock log 6 lines vs 0. Disposition: Addressed (operator, 2026-11-01): guard located by `&& return 0`, inspected count asserted equal to the tracked lib count.

