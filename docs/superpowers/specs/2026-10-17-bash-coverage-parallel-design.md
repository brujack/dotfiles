# Bash coverage: run the traced suite in parallel

- **Date:** 2026-10-17
- **Status:** Draft (Phase 1)
- **Trigger:** the `bash-coverage` CI job hit its 25-minute cap twice on PR #343. PR #344 raised
  the cap to 60. The backlog row "bash-coverage runtime grows linearly with the suite because the
  coverage run is serial" holds the measurements behind this spec.

## Problem

`scripts/run-bash-coverage.sh` runs `bats --recursive tests/` with no `--jobs`. The `test` job
runs the same suite with `--jobs 24` (`Makefile`, `JOBS ?= 24`). So the suite's growth reaches the
coverage job and nowhere else. Since July the suite has gone from 1070 tests to 3202, and the
coverage job has grown with it at about 0.3s per test. The cap was sized when the job took 8
minutes. It now takes 14–25 minutes, and the same code varies about 1.5x between runs.

## Measurements

All measurements are from 2026-10-17.

- **M1, CI duration history.** From the `ci.yml` run list (200 runs, 2026-06-24 to 2026-10-17),
  `bash-coverage` and `test` job durations for successful runs:
  - **Coverage job, median per half-month:** 221s in late June, 482s in late August, 1029s in
    early October, 1486s on 2026-10-17.
  - **`test` job median:** 335–426s since late August.
  - **Per run:** the time divided by the run's own `Running N tests` line stays near 0.3s per
    test from July to October (345s/1070, 705s/2109, 709s/2737).
  - **Variance:** the same code took 806s and 1177s on one branch, and 916s against 1486s an
    hour apart (#343, #344).
  - Population: GitHub-hosted `ubuntu-latest` runners for this repo.
- **M2, parallel vs serial over the full suite.** Measured on `claude` (48 threads) at master
  `1e29afb1`. The real filter pipeline from `run-bash-coverage.sh` ran in both modes, with
  `BASH_ENV=scripts/bash-tracer.sh`.

  | mode                                | time  | not ok | filtered trace lines | unique file:line |
  | ----------------------------------- | ----- | ------ | -------------------- | ---------------- |
  | `bats --jobs 24 --recursive tests/` | 173s  | 0      | 2,113,720            | 6442             |
  | `bats --recursive tests/`           | 1478s | 0      | 2,113,560            | 6442             |

  `comm -3` of the two unique sets is empty. Population: one machine, one run per mode. The CI
  speed-up will be smaller, since the runner has 4 vCPUs. The set equality is the claim this spec
  relies on, and it is independent of core count.

- **M3, torn writes.**
  - The parallel run produced 231 raw lines that match the repo path but not
    `^C*COVTRACE:<repo>/<path>:<n>: `. The serial run produced 0.
  - Sampled from a `--jobs 24` run of `tests/setup_env/`, these are continuation chunks of trace
    lines longer than 4096 bytes. One is a multi-line `--hash=sha256:` value, another a `local`
    holding captured output that names repo paths. A FIFO write is atomic only up to `PIPE_BUF`,
    4096 bytes on Linux.
  - Every prefix in the sample was intact, and the unique sets in M2 match. A long line's prefix
    can in principle be split by another writer. The current extraction,
    `grep -oE 'C*COVTRACE:[^:]+:[0-9]+'`, would then read a truncated number (`:12` from `:123`)
    as covered.
- **M4, the runner has GNU parallel.** `ubuntu-latest` preinstalls `parallel 20231122+ds-1`
  (core.md ci-006). The `test` job installs no parallel package and still runs `bats --jobs`.

## Design

### 1. Parallel bats in `run-bash-coverage.sh`

- A function `_coverage_bats_args` prints the bats argv, one argument per line:
  - With GNU parallel available: `--jobs`, `<JOBS>`, `--recursive`, `<tests dir>`.
  - Otherwise: `--recursive`, `<tests dir>`.
- **GNU parallel available** means `"${_COVERAGE_PARALLEL_BIN:-parallel}" --version` prints a
  first line matching `^GNU parallel`. `_COVERAGE_PARALLEL_BIN` is a test seam with the
  production default `parallel`. It exists because removing `parallel` from `PATH` on
  `ubuntu-latest` removes `/usr/bin`, and the rest of the toolchain with it (the
  `_OVERRIDE_BATS_BIN` lesson in `CLAUDE.md`). It selects only the binary the detection runs;
  bats still runs `parallel` from `PATH`. This is the `Makefile`'s `HAVE_PARALLEL` test, kept to the version string
  because moreutils ships an incompatible `parallel`. A set but empty `HAVE_PARALLEL` forces
  serial, as `make test HAVE_PARALLEL=` does.
- **`JOBS`** defaults to 24. Any value other than a positive integer without a leading zero makes
  the run exit 2 before bats starts, with `JOBS must be a positive integer, got '<value>'` on
  stderr. This matches the `Makefile`'s rule.
- **Mode line.** The script prints `bats mode: parallel (--jobs <n>)` or
  `bats mode: serial (<reason>)` before running. The reason is either `GNU parallel not found` or
  `HAVE_PARALLEL set empty`. This line goes into the job log, so a serial fallback in CI is
  visible.
- **Inspection flag.** `--print-bats-args` prints the argv and the mode line, then exits 0 without
  running bats. It sits with the script's existing inspection flags and lets tests cover the mode
  logic without a traced suite.

### 2. Torn-prefix-safe trace extraction

- The filter's extraction stage moves into a function, `_coverage_filter_trace`, which reads
  stdin and writes normalised `path:line` lines.
- The extraction pattern requires the separator that follows the line number:
  `grep -oE 'C*COVTRACE:[^:]+:[0-9]+: '`. The trailing `: ` is stripped afterwards.
- A prefix truncated inside its line number, or before the separator, no longer matches. It is
  dropped instead of being counted under a wrong line. A dropped prefix can only lower coverage.
  The union-with-trace rule cannot be pushed upward by it, because the union reads the same
  filtered output.
- **Inspection flag.** `--filter-trace` runs `_coverage_filter_trace` on stdin, so tests can feed
  it fixtures.

### 3. CI

`ci.yml` is unchanged. The `bash-coverage` job already runs on `ubuntu-latest`, which has GNU
parallel (M4), and the mode line from Design §1 shows which path the job took. The 60-minute cap
stays. A backlog row records re-sizing it to about 3x the p90 once three parallel runs exist.

### 4. Documentation

- In `CLAUDE.md`'s Coverage > Bash section, a bullet states that the traced suite runs with
  `--jobs ${JOBS:-24}` under the same GNU-parallel detection as `make test`, and that
  `HAVE_PARALLEL=` forces serial.
- The bullet also notes that the extraction requires the `: ` separator, because concurrent
  writers can tear trace lines longer than 4096 bytes.

## Alternatives

- **Shard the suite across a CI matrix and merge the traces.** This works without GNU parallel,
  but needs a merge step and per-shard plumbing for the same win.
- **Stop tracing bats' `DEBUG` trap.** That trap is 94% of raw trace volume (one file: 375,859 of
  398,862 lines). Suppressing it means patching bats internals, and tracing cost only 1.25x on that
  file (6.4s plain, 8.0s traced). The serial run is the cost, not the tracing.
- **Lower the per-test cost.** No single test dominates; the cost is flat per test across four
  months (M1).

## Testing

New tests go in `tests/scripts/unit.bats`, next to the existing `run-bash-coverage.sh` inspection
flag tests. They drive the CLI, never `source scripts/run-bash-coverage.sh`, which has no sourcing
guard and launches a full traced suite. Detection is driven only through `_COVERAGE_PARALLEL_BIN`, which points at a stub in a
test-owned directory or at a nonexistent path. No test edits `PATH` or depends on the host's own
`parallel`.

1. A `parallel` stub printing `GNU parallel 20231122` with `JOBS` unset: `--print-bats-args`
   prints `--jobs`, `24`, `--recursive`, the tests dir, and `bats mode: parallel (--jobs 24)`.
2. The same stub with `JOBS=6`: the argv carries `6`.
3. A `parallel` stub printing `parallel from moreutils`: the argv has no `--jobs`, and the mode
   line reads `serial (GNU parallel not found)`.
4. `_COVERAGE_PARALLEL_BIN` set to a nonexistent path: the same output as case 3.
5. A GNU stub with `HAVE_PARALLEL=` set empty: the mode is `serial (HAVE_PARALLEL set empty)`.
6. `JOBS` equal to `0`, `07`, `x`, `-1`, `2 3` or an empty string: exit 2 with the message naming
   the value. Nothing else is printed.
7. `--filter-trace` on an intact fixture of two lines in a repo file, at nesting depths `+` and
   `++` (`COVTRACE:` and `CCOVTRACE:`): two normalised `path:line` lines.
8. `--filter-trace` on a torn fixture, `COVTRACE:<repo>/lib/x.sh:1COVTRACE:<repo>/lib/y.sh:5: cmd`:
   exactly `lib/y.sh:5`, and no `lib/x.sh:1`.
9. `--filter-trace` on a line outside the repo (`COVTRACE:/usr/lib/bats-core/tracing.bash:19: x`):
   no output.

Mutation controls: dropping the `: ` from the pattern makes case 8 emit `lib/x.sh:1`. Dropping the
`^GNU parallel` check makes case 3 report parallel. Hard-coding 24 makes case 2 fail.

## Requirements

- **R1.** `scripts/run-bash-coverage.sh` runs the traced suite as `bats --jobs <JOBS> --recursive <tests dir>` when `"${_COVERAGE_PARALLEL_BIN:-parallel}" --version`'s first line matches `^GNU parallel` and `HAVE_PARALLEL` is not set to an empty string, and as `bats --recursive <tests dir>` otherwise.
- **R2.** `JOBS` defaults to 24; any other value that is not a positive integer without a leading zero exits 2 before bats runs, printing `JOBS must be a positive integer, got '<value>'` to stderr.
- **R3.** Before running bats the script prints exactly one line, `bats mode: parallel (--jobs <n>)`, `bats mode: serial (GNU parallel not found)` or `bats mode: serial (HAVE_PARALLEL set empty)`.
- **R4.** `--print-bats-args` prints the bats argv, one argument per line, followed by the mode line, and exits 0 without running bats.
- **R5.** Trace extraction matches `C*COVTRACE:[^:]+:[0-9]+: ` (separator required) and emits the normalised `path:line` without the separator, so a prefix with no `: ` after its digits is dropped.
- **R6.** `--filter-trace` applies the trace extraction to stdin and prints its output.
- **R7.** `tests/scripts/unit.bats` contains cases 1–9 from the Testing section and they pass.
- **R8.** `CLAUDE.md`'s Coverage > Bash section states the `--jobs ${JOBS:-24}` behaviour, the `HAVE_PARALLEL=` override, and why the separator is required.
- **V1.** On `claude`, run the full traced suite through the new script in both modes (`HAVE_PARALLEL=` for serial) and confirm the two unique `file:line` sets are identical and the overall figure is equal; record both times.
- **V2.** The PR's own `bash-coverage` CI job logs `bats mode: parallel (--jobs 24)`, passes the 91% gate, and its duration is recorded in the PR body.
- **V3.** After three parallel CI runs, add their durations to the backlog row for re-sizing the cap.
- **N1.** The 91% floor, the union-with-trace rule and the coverable-line heuristic are unchanged.
- **N2.** `.github/workflows/ci.yml` is not changed by this work.
- **N3.** No bats file is added to `BATS_SERIAL_FILES` or otherwise excluded from the traced run.
- **N4.** No test runs the full traced suite.
