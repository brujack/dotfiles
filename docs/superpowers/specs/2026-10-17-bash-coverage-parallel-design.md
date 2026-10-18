# Bash coverage: run the traced suite in parallel

- **Date:** 2026-10-17
- **Status:** Draft (Phase 1), revised after Step 8 round 2
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
  - Population: GitHub-hosted `ubuntu-latest` runners for this repo. The latest successful run
    (#344) printed `Overall bash coverage: 91%`, which is the floor.
- **M2, parallel vs serial over the full suite.** Measured on `claude` (48 threads, bash 5.3.9)
  at master `1e29afb1`. The real filter pipeline from `run-bash-coverage.sh` ran in both modes,
  with `BASH_ENV=scripts/bash-tracer.sh`.

  | mode                                | time  | not ok | filtered trace lines | unique file:line |
  | ----------------------------------- | ----- | ------ | -------------------- | ---------------- |
  | `bats --jobs 24 --recursive tests/` | 173s  | 0      | 2,113,720            | 6442             |
  | `bats --recursive tests/`           | 1478s | 0      | 2,113,560            | 6442             |
  - `comm -3` of the two unique sets is empty.
  - The parallel run filtered 160 more lines. Timing-dependent branches ran more often, so
    execution differed slightly, but the set of lines covered did not.
  - Population: one machine, one run per mode. V1 repeats the comparison under CI's bash and
    core count.

- **M3, writes cannot tear a prefix.**
  - `strace -e write` of a traced script with a 10,000-byte line, run on bash 5.3.9 (`claude`)
    and bash 5.2.21 (`ubuntu:24.04`, CI's version), shows the same pattern:
    - Every trace line starts a new `write()`, and its first bytes are the `C*COVTRACE:` prefix.
    - Lines longer than 4096 bytes are written as further 4096-byte chunks.
    - The prefix is therefore always inside a write of 4096 bytes or less. A FIFO write of up to
      `PIPE_BUF` (4096 on Linux) is atomic, so no prefix is ever split.
  - Interleaving happens only between the chunks of a long line. Another writer's whole line can
    land between two chunks, so it starts mid-line in the stream. The filter's `grep -oE` is
    unanchored, which is why such a line is still found.
  - A 24-writer FIFO fixture (risk lens, round 1) produced 43,248 lines with 1,112 mid-line
    interleavings, and every prefix was followed by `:N: `.
  - In a full `--jobs 24` run, 112 trace records exceeded 4096 bytes. They named 8 distinct
    `file:line` keys, and all 8 also appear in shorter records. No covered line depends on a long
    record.
- **M4, the runner has GNU parallel.** `ubuntu-latest` preinstalls `parallel 20231122+ds-1`
  (core.md ci-006). The `test` job installs no parallel package, and its log in run 39075591428
  shows `bats --jobs 24`.

## Design

### 1. The Makefile decides; the script obeys

CI already reaches the script through `make bash-coverage` (`ci.yml`), whose recipe is a bare
`@bash scripts/run-bash-coverage.sh`. The `Makefile` already validates `JOBS` at parse time and
computes `HAVE_PARALLEL` from the `^GNU parallel` version string. The coverage run reuses those
instead of re-implementing them.

- **Recipe.** The `bash-coverage` recipe sets `COVERAGE_BATS_JOBS=$(JOBS)` in the script's
  environment when two conditions hold:
  - `HAVE_PARALLEL` is `yes`;
  - `BATS_SERIAL_FILES` is empty.

  Otherwise it runs the script under `env -u COVERAGE_BATS_JOBS`, so a value exported in the
  caller's shell cannot turn a serial run parallel. One file needing serial execution therefore
  sends the whole coverage run serial. That matches `make test`'s treatment of those files without splitting the trace
  into two runs.

- **Script.** One function, `_coverage_bats_args`, turns `COVERAGE_BATS_JOBS` into the bats
  argument list, one argument per line.
  - With `COVERAGE_BATS_JOBS` set: `--jobs`, `<value>`, `--recursive`, `<tests dir>`.
  - Unset or empty: `--recursive`, `<tests dir>`, as today.
  - A value other than a positive integer without a leading zero makes it fail with
    `COVERAGE_BATS_JOBS must be a positive integer, got '<value>'` on stderr. Only a direct
    invocation can reach this, since make has already validated `JOBS`.
- **Call site.** The main run calls `_coverage_bats_args` and checks its exit status **before**
  `mkdir`, `rm` and `mkfifo` touch `coverage/`. An invalid value therefore exits 2 with no FIFO and
  no reader process created. The real `bats` call is built from that function's output, read into
  an array, so the call site cannot drift from what the function returns.
- **Inspection flag.** `--print-bats-args` prints `_coverage_bats_args`' output and the mode line,
  then exits (0, or 2 on an invalid value). It never reaches the main run.
- **Mode line.** Before running bats the script prints one of two lines into the job log:
  - `bats mode: parallel (--jobs <n>)`
  - `bats mode: serial (COVERAGE_BATS_JOBS unset)`
- **Overrides.** `make bash-coverage HAVE_PARALLEL=` forces serial, and
  `make bash-coverage JOBS=6` changes the worker count. `HAVE_PARALLEL= make bash-coverage` does
  nothing, because the `Makefile` reassigns `HAVE_PARALLEL` with `:=`. Only the make-argument form
  is documented.
- **Flag parsing.** The script's positional `--json` parsing and its unknown-option guard are
  untouched. The value travels in the environment, not as a flag.

### 2. Trace extraction

- The filter's extraction stage moves into `_coverage_filter_trace <root>`. It reads stdin and
  writes normalised `path:line` lines for prefixes under `<root>`. The FIFO pipeline calls it with
  `"${REPO_ROOT}"`.
- The root is matched as a **literal** prefix, never interpolated into a regex. `.` in a path
  (`.worktrees`) would otherwise match any character, and `+` would match nothing.
  - The existing `grep -F "COVTRACE:${root}/"` prefilter stays.
  - Extraction takes each `C*COVTRACE:` occurrence followed by `[^:]+:[0-9]+: `.
  - It keeps the occurrence only when its path starts with `<root>/`, compared as a string.
- The separator after the line number is required, and the `: ` is stripped afterwards. M3 shows a prefix cannot be torn, so the separator is defence in
  depth, not a fix for an observed failure.
- **Inspection flag.** `--filter-trace <root>` runs `_coverage_filter_trace` on stdin and exits 0.
  The root is an argument so test fixtures can use a fake root (`/fixture-root`). A test that
  embedded the real repo path in a traced command would put `COVTRACE:<repo>/<file>:N: ` into the
  real trace, and the unanchored extraction would count that line as covered.
- **Usage text.** `-h` lists `--filter-trace`, `--print-bats-args` and `COVERAGE_BATS_JOBS`. The existing test
  `-h documents both inspection flags` is extended to cover them.

### 3. CI

`ci.yml` is unchanged. The job already runs `make bash-coverage` on `ubuntu-latest`, which has GNU
parallel (M4), and the mode line shows which path it took. The 60-minute cap stays. A backlog row
records re-sizing it to about 3x the p90 once three parallel runs exist.

### 4. Documentation

`CLAUDE.md`'s Coverage > Bash section gains a bullet covering:

- how the traced suite is parallelised (`make bash-coverage` passes `COVERAGE_BATS_JOBS` when GNU
  parallel is detected and `BATS_SERIAL_FILES` is empty);
- the two make-argument overrides;
- why `--filter-trace` fixtures must use a fake root.

## Alternatives

- **Detect parallel inside the script.** This was the first draft. It duplicated the `Makefile`'s
  `JOBS` validation and `HAVE_PARALLEL` detection, and needed its own test seam. Round 1 replaced
  it with the recipe.
- **Shard the suite across a CI matrix and merge the traces.** This works without GNU parallel,
  but needs a merge step and per-shard plumbing for the same win.
- **Stop tracing bats' `DEBUG` trap.** That trap is 94% of raw trace volume (one file: 375,859 of
  398,862 lines), and suppressing it means patching bats internals. Tracing cost only 1.25x on that
  file (6.4s plain, 8.0s traced). The serial run is the cost, not the tracing.

## Testing

Tests drive the CLI and make, never `source scripts/run-bash-coverage.sh`, which has no sourcing
guard and launches a full traced suite. **No test reaches the main run.** It writes the fixed
paths `coverage/bash_trace.fifo` and `coverage/bash_trace.txt`, and CI's own traced run owns those
same paths while `tests/scripts/unit.bats` executes. Every case uses an inspection flag that exits
before the main run, or `make -n`.

**Script (`tests/scripts/unit.bats`):**

1. `COVERAGE_BATS_JOBS=6 … --print-bats-args`: prints `--jobs`, `6`, `--recursive`, the tests dir,
   and `bats mode: parallel (--jobs 6)`.
2. `--print-bats-args` with `COVERAGE_BATS_JOBS` explicitly unset (`env -u`), then set empty:
   prints `--recursive`, the tests dir, and `bats mode: serial (COVERAGE_BATS_JOBS unset)`. The
   explicit unset matters, because the variable is inherited from the enclosing coverage run.
3. `--print-bats-args` with `COVERAGE_BATS_JOBS` set to `0`, `07`, `x`, `-1` or `2 3`: exit 2,
   with the message naming the value.
4. `--filter-trace /fixture-root` on a fixture file of two prefixes at nesting depths `+` and `++`:
   two normalised `path:line` lines.
5. `--filter-trace /fixture-root` on
   `COVTRACE:/fixture-root/lib/x.sh:1COVTRACE:/fixture-root/lib/y.sh:5: cmd`: exactly
   `lib/y.sh:5`, with no `lib/x.sh:1`.
6. `--filter-trace /fixture-root` on a prefix under another root
   (`COVTRACE:/usr/lib/bats-core/tracing.bash:19: x`): no output.
7. `--filter-trace /fix.ture-root` on a prefix under `/fixXture-root`: no output, because the root
   is literal. `--filter-trace /fix+root` on a prefix under `/fix+root`: one line.
8. Structural checks on `scripts/run-bash-coverage.sh`:
   - The main run builds its bats argv from `_coverage_bats_args`, before the first `mkfifo`.
   - The FIFO pipeline calls `_coverage_filter_trace "${REPO_ROOT}"`.
   - No other `grep -oE` extraction of `COVTRACE` remains.

Fixtures for cases 4–7 live in files under `tests/fixtures/coverage/` and are fed on stdin, so no
traced test command contains a prefix string.

**Recipe (a `make -n` test in `tests/makefile_*.bats` style):**

9. `make -n --no-print-directory bash-coverage HAVE_PARALLEL=yes JOBS=6 BATS_SERIAL_FILES=` prints
   a command carrying `COVERAGE_BATS_JOBS=6`.
10. The same with `HAVE_PARALLEL=`, and again with `BATS_SERIAL_FILES=tests/x.bats`: the command
    carries `env -u COVERAGE_BATS_JOBS` and no `COVERAGE_BATS_JOBS=`.

The recipe test unsets `MAKEFLAGS MFLAGS MAKELEVEL JOBS` first (CLAUDE.md, Testing), and passes
`--no-print-directory` per call (the stdout partition rule).

Mutation controls:

- Drop the `: ` from the pattern: case 5 emits `lib/x.sh:1`.
- Interpolate the root into a regex: case 7 fails both ways.
- Hard-code `--jobs 24`: case 1 fails.
- Drop the `env -u` arm: case 10 fails.
- Drop the `BATS_SERIAL_FILES` condition: case 10's second half fails.
- Leave the call site on the literal `bats --recursive`: case 8 fails.

## Requirements

- **R1.** The `bash-coverage` recipe runs `scripts/run-bash-coverage.sh` with `COVERAGE_BATS_JOBS=$(JOBS)` in its environment when `HAVE_PARALLEL` is `yes` and `BATS_SERIAL_FILES` is empty, and under `env -u COVERAGE_BATS_JOBS` otherwise.
- **R2.** `_coverage_bats_args` prints `--jobs`, `<value>`, `--recursive`, `<tests dir>` one per line when `COVERAGE_BATS_JOBS` is a positive integer without a leading zero, prints `--recursive`, `<tests dir>` when it is unset or empty, and otherwise fails printing `COVERAGE_BATS_JOBS must be a positive integer, got '<value>'` to stderr; the main run builds its `bats` argv from that output and exits 2 on failure before creating `coverage/`, the FIFO or the reader.
- **R3.** Before running bats the script prints exactly one line, `bats mode: parallel (--jobs <n>)` or `bats mode: serial (COVERAGE_BATS_JOBS unset)`.
- **R4.** Trace extraction is `_coverage_filter_trace <root>`, which takes each `C*COVTRACE:<path>:<n>: ` occurrence (separator required), keeps it only when `<path>` starts with the literal string `<root>/`, and emits the normalised `path:line` without the separator; the FIFO pipeline calls it with `"${REPO_ROOT}"`.
- **R5.** `--filter-trace <root>` applies `_coverage_filter_trace` to stdin, prints its output and exits 0; `--print-bats-args` prints `_coverage_bats_args`' output and the mode line and exits 0, or 2 on an invalid value; neither reaches the main run.
- **R6.** The script's `-h` text lists `--filter-trace <root>`, `--print-bats-args` and `COVERAGE_BATS_JOBS`, and the existing `-h` test asserts all three.
- **R7.** Test cases 1–10 from the Testing section exist and pass, with fixtures for cases 4–7 in files under `tests/fixtures/coverage/` using fake roots.
- **R8.** `CLAUDE.md`'s Coverage > Bash section states how the traced suite is parallelised, the `make bash-coverage HAVE_PARALLEL=` and `JOBS=<n>` overrides, and that `--filter-trace` fixtures use a fake root.
- **V1.** In `ubuntu:24.04` (bash 5.2.21) with `--cpus 4`, run the full traced suite through `make bash-coverage` in both modes (`HAVE_PARALLEL=` for serial), as a non-root user; run each mode twice; record all four times, and confirm all four unique `file:line` sets are identical and the overall figures equal.
- **V2.** The PR's own `bash-coverage` CI job logs `bats mode: parallel (--jobs 24)`, passes the 91% gate, and its duration and figure are recorded in the PR body.
- **V3.** After three parallel CI runs, add their durations to the backlog row for re-sizing the cap.
- **N1.** The 91% floor, the union-with-trace rule and the coverable-line heuristic are unchanged.
- **N2.** `.github/workflows/ci.yml` is not changed by this work.
- **N3.** No bats file is added to `BATS_SERIAL_FILES` or otherwise excluded from the traced run.
- **N4.** No test runs the full traced suite or reaches the script's main run, and no test fixture or traced test command contains a `COVTRACE:` string under the real repo root.
- **N5.** The script's `--json` parsing and unknown-option guard are unchanged.

## Multi-Lens Review

Reviewed at commit: `693dc297` (Step 7 self-review commit, before Step 8 dispatch)

### Goal-Fit

Finding:

1. The `Makefile` already validates `JOBS` and detects GNU parallel, and CI calls
   `make bash-coverage`. The script-side detection, its seam and test cases 1–6 duplicated them.
2. The tests checked the new functions but not the real call sites. With the call sites unchanged,
   all nine would still have passed.
3. Context: CI's latest figure is exactly 91%, so there is no headroom.

Assumption: serial and parallel runs cover the same lines on CI's runner, not only on `claude`.

Disposition: **Addressed (operator, 2026-10-17).** The recipe now decides and the script obeys
(Design §1). A stub bats records the real call site's argv, and a structural test pins the
pipeline (cases 1, 7). V1 now runs both modes on bash 5.2.21 with 4 CPUs.

### Ergonomics

Finding:

1. `HAVE_PARALLEL= make …` is ignored, because the `Makefile` reassigns it with `:=`.
2. `-h` and its test would go stale.
3. `--filter-trace` waits on a terminal.

Assumption: set equality holds where interleaving differs. Measured since: no covered line depends
on a record longer than 4096 bytes (M3).

Disposition: **Addressed (operator, 2026-10-17)** for 1–2: only the make-argument form is
documented, and R6 extends `-h` and its test. **Accepted** for 3: it is cosmetic, on an
inspection-only flag.

### Risk

Finding:

1. **HIGH:** fixture strings containing `COVTRACE:<repo>/<file>:N: ` inside a traced test would be
   extracted as coverage, which fails green.
2. M3's claim that "a prefix can in principle be split" is refuted. bash starts every trace line
   in a fresh write, so the prefix sits in an atomic write.
3. The evidence was one run per mode, on one machine.
4. The coverage run ignored `BATS_SERIAL_FILES`.

Assumption: bash 5.2.21 flushes xtrace once per line. Measured since with `strace` in
`ubuntu:24.04`: it does (M3).

Disposition: **Addressed (operator, 2026-10-17).**

- `--filter-trace` takes the root, fixtures use `/fixture-root`, and N4 forbids the real root.
- M3 was rewritten with both bash versions' `strace` and the long-record count.
- V1 moved to bash 5.2.21 with 4 CPUs.
- The recipe goes serial when `BATS_SERIAL_FILES` is non-empty.

### Round 2 — spec at `0b8ac0db`

All three lenses, told round 1 was history.

| # | Lens | Sev | Finding |
|---|------|-----|---------|
| A | all three | HIGH | The stub-bats tests could not work. `_OVERRIDE_BATS_BIN` feeds only the presence check, and the main run calls the literal `bats`, so cases 1–2 would run the real suite, which contains them. Even with a stub, the main run deletes and recreates the fixed `coverage/bash_trace.fifo`, cutting off CI's own outer traced run. A non-bash stub hangs, because nothing opens the FIFO's write end. |
| B | ergonomics | MED | "Otherwise sets nothing" lets an exported `COVERAGE_BATS_JOBS` through. A scratch Makefile probe printed `got=24` with `HAVE_PARALLEL=`. |
| C | ergonomics | LOW | Validation placed next to the bats call would orphan a FIFO reader. |
| D | risk | MED | Interpolating the root into a regex: `.` over-matched a foreign root (`.worktrees` is live), and `+` matched nothing. |
| E | risk | LOW | Tests inherit `COVERAGE_BATS_JOBS` from the outer run, so an "unset" case must `env -u` it. |
| F | goal-fit, risk | — | Assumption: set equality on CI's runner. One V1 run per mode is thin given timing-dependent branches. |

Disposition: **Addressed (operator, 2026-10-17).**

- A: the main-run tests were dropped. `_coverage_bats_args` feeds both the call site and
  `--print-bats-args`, a structural case pins the call site, and N4 forbids reaching the main run.
- B: the recipe's else arm uses `env -u`.
- C: validation runs before `coverage/` is touched.
- D: the root is matched as a literal prefix.
- E: case 2 uses `env -u`.
- F: V1 now runs each mode twice.

The operator asked for a round 3.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.
