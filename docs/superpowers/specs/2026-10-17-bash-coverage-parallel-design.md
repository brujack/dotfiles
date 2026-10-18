# Bash coverage: run the traced suite in parallel

- **Date:** 2026-10-17
- **Status:** Approved (Phase 1)
- **Approved:** 2026-10-17
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

- **Recipe.** A parse-time conditional (`ifeq`, not a shell `if`, so `make -n` prints only one
  arm) chooses the command.
  - When `HAVE_PARALLEL` is `yes` and `BATS_SERIAL_FILES` is empty, the recipe runs the script
    with `COVERAGE_BATS_JOBS=$(JOBS)` in its environment.
  - Otherwise it runs it under `env -u COVERAGE_BATS_JOBS`, so a value exported in the caller's
    shell cannot turn a serial run parallel. A single file needing serial execution sends the
    whole coverage run serial, which matches `make test`'s treatment of those files without
    splitting the trace into two runs.
- **Argument function.** `_coverage_bats_args` turns `COVERAGE_BATS_JOBS` into the bats argument
  list, one argument per line:
  - set to a valid value: `--jobs`, `<value>`, `--recursive`, `<tests dir>`;
  - unset or empty: `--recursive`, `<tests dir>`, as today.

  A value other than a positive integer without a leading zero makes it return non-zero, with
  `COVERAGE_BATS_JOBS must be a positive integer, got '<value>'` on stderr. Only a direct
  invocation can reach this, since make has already validated `JOBS`.
- **Call site.** The main run captures the list as `_out="$(_coverage_bats_args)" || exit 2`,
  **before** `mkdir`, `rm` and `mkfifo` touch `coverage/`. A process substitution such as
  `mapfile < <(…)` is not used: it discards the function's status, which was measured as `rc=0`
  with an empty argv. The captured lines are read into an array, `bats` is invoked as
  `bats "${_bats_args[@]}"`, and an invalid value exits 2 with no FIFO or reader created.
- **Mode line.** The script prints one line into the job log, built from the array that is
  actually passed to bats, not from the variable:
  - `bats mode: parallel (--jobs <n>)` when the array contains `--jobs`;
  - `bats mode: serial` otherwise.
- **Inspection flag.** `--print-bats-args` prints the same array and mode line, then exits 0, or
  2 on an invalid value. It sits above the unknown-option guard, as that guard's comment requires,
  and never reaches the main run.
- **Overrides.** `make bash-coverage HAVE_PARALLEL=` forces serial, and
  `make bash-coverage JOBS=6` changes the worker count. `HAVE_PARALLEL= make bash-coverage` does
  nothing, because the `Makefile` reassigns `HAVE_PARALLEL` with `:=`. Only the make-argument form
  is documented.
- **Trace filter.** The filter is unchanged. It already matches the root literally
  (`grep -F "COVTRACE:${REPO_ROOT}/"`), and M3 shows a prefix cannot tear under parallel writers.
  Changing it would move the coverage figure, at zero headroom, in a change that is meant only to
  make the run faster.
- **Usage text.** `-h` lists `--print-bats-args` and `COVERAGE_BATS_JOBS`, and the existing `-h`
  test asserts both.

### 2. CI

`ci.yml` is unchanged. The job already runs `make bash-coverage` on `ubuntu-latest`, which has GNU
parallel (M4), and the mode line shows which path it took. The 60-minute cap stays. A backlog row
records re-sizing it to about 3x the p90 once three parallel runs exist.

### 3. Documentation

`CLAUDE.md`'s Coverage > Bash section gains one bullet. It says that `make bash-coverage` passes
`COVERAGE_BATS_JOBS` when GNU parallel is detected and `BATS_SERIAL_FILES` is empty, and that
`make bash-coverage HAVE_PARALLEL=` and `JOBS=<n>` are the overrides.

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
guard and launches a full traced suite. **No test reaches the main run.** The main run writes the
fixed paths `coverage/bash_trace.fifo` and `coverage/bash_trace.txt`, and CI's own traced run owns
those same paths while `tests/scripts/unit.bats` executes.

**Script (`tests/scripts/unit.bats`):**

1. `COVERAGE_BATS_JOBS=6 … --print-bats-args`: prints `--jobs`, `6`, `--recursive`, the tests dir,
   and `bats mode: parallel (--jobs 6)`.
2. `--print-bats-args` under `env -u COVERAGE_BATS_JOBS`, then with it set empty: prints
   `--recursive`, the tests dir, and `bats mode: serial`. The explicit unset matters, because the
   variable is inherited from the enclosing coverage run.
3. `--print-bats-args` with `COVERAGE_BATS_JOBS` set to `0`, `07`, `x`, `-1` or `2 3`: exit 2,
   with the message naming the value.
4. Structural checks on `scripts/run-bash-coverage.sh`:
   - the main run captures `_coverage_bats_args` with `|| exit 2` before the first `mkfifo`;
   - it invokes `bats "${_bats_args[@]}"`;
   - no literal `bats --recursive` call remains.

**Recipe (a `make -n` test in `tests/makefile_*.bats` style):**

5. `make --no-print-directory -C <repo> -n bash-coverage HAVE_PARALLEL=yes JOBS=6 BATS_SERIAL_FILES=`
   prints a command carrying `COVERAGE_BATS_JOBS=6`.
6. The same with `HAVE_PARALLEL=`, and again with `BATS_SERIAL_FILES=tests/x.bats`: the command
   carries `env -u COVERAGE_BATS_JOBS` and no `COVERAGE_BATS_JOBS=`.

The recipe test unsets `MAKEFLAGS MFLAGS MAKELEVEL JOBS` first (CLAUDE.md, Testing). It passes
`--no-print-directory` per call, so it falls in the partition scanner's guarded set.

Mutation controls:

- Hard-code `--jobs 24`: case 1 fails.
- Derive the mode line from the variable instead of the array, and leave the call site on literal
  `bats --recursive`: case 4 fails.
- Capture through `< <(…)` instead of `|| exit 2`: case 4 fails.
- Drop the `env -u` arm: case 6 fails.
- Drop the `BATS_SERIAL_FILES` condition: case 6's second half fails.

## Requirements

- **R1.** The `bash-coverage` recipe uses a parse-time conditional to run `scripts/run-bash-coverage.sh` with `COVERAGE_BATS_JOBS=$(JOBS)` in its environment when `HAVE_PARALLEL` is `yes` and `BATS_SERIAL_FILES` is empty, and under `env -u COVERAGE_BATS_JOBS` otherwise.
- **R2.** `_coverage_bats_args` prints `--jobs`, `<value>`, `--recursive`, `<tests dir>` one per line when `COVERAGE_BATS_JOBS` is a positive integer without a leading zero, prints `--recursive`, `<tests dir>` when it is unset or empty, and otherwise returns non-zero printing `COVERAGE_BATS_JOBS must be a positive integer, got '<value>'` to stderr.
- **R3.** The main run captures `_coverage_bats_args` as `_out="$(_coverage_bats_args)" || exit 2` before creating `coverage/`, the FIFO or the reader, reads it into the array `_bats_args`, and invokes `bats "${_bats_args[@]}"`; no literal `bats --recursive` call remains.
- **R4.** The script prints exactly one mode line derived from `_bats_args`: `bats mode: parallel (--jobs <n>)` when the array contains `--jobs`, otherwise `bats mode: serial`.
- **R5.** `--print-bats-args` prints the `_bats_args` lines and the mode line and exits 0, or 2 on an invalid value, without reaching the main run.
- **R6.** The script's `-h` text lists `--print-bats-args` and `COVERAGE_BATS_JOBS`, and the existing `-h` test asserts both.
- **R7.** Test cases 1–6 from the Testing section exist and pass.
- **R8.** `CLAUDE.md`'s Coverage > Bash section states that `make bash-coverage` passes `COVERAGE_BATS_JOBS` when GNU parallel is detected and `BATS_SERIAL_FILES` is empty, and names the `make bash-coverage HAVE_PARALLEL=` and `JOBS=<n>` overrides.
- **V1.** In `ubuntu:24.04` (bash 5.2.21) with `--cpus 4`, as a non-root user, run `make bash-coverage` twice in each mode (`HAVE_PARALLEL=` for serial); confirm all four runs have 0 `not ok`, identical unique `file:line` sets and equal overall figures, and record the four times.
- **V2.** The PR's own `bash-coverage` CI job logs `bats mode: parallel (--jobs 24)`, passes the 91% gate, and finishes in under 20 minutes (the `test` job's cap); its duration and figure are recorded in the PR body.
- **V3.** After three parallel CI runs, add their durations to the backlog row for re-sizing the cap.
- **N1.** The 91% floor, the union-with-trace rule, the coverable-line heuristic and the trace filter pipeline are unchanged.
- **N2.** `.github/workflows/ci.yml` is not changed by this work.
- **N3.** No bats file is added to `BATS_SERIAL_FILES` or otherwise excluded from the traced run.
- **N4.** No test runs the full traced suite or reaches the script's main run.
- **N5.** The script's `--json` parsing and unknown-option guard are unchanged.

## Addendum: other parallel opportunities (2026-10-17, operator)

After approval the operator asked for the backlog's other parallel items to be pulled into this
work. Two were brought in and one was left out.

**A1. `make lint`'s shellcheck passes run in parallel.**
- **Measured on `claude`:**
  - shellcheck over the 117 `SHELL_FILES` took 27.4s serial and 3.5s with `xargs -n 4 -P 8`.
  - Over the 78 `.bats` files at `--severity=warning`, it took 28.6s serial and 8.6s parallel.
  - All four runs exited 0. The whole `make lint` took 56.6s.
- **Change:** both passes feed their file list to `xargs -n 4 -P $(JOBS)`. The list is unchanged.
  `xargs -P` exists in both GNU and macOS `xargs`, so this does not need GNU parallel.
- **Exit status:** the pass fails when any `shellcheck` invocation fails. The `shellcheck OK` and
  `shellcheck bats OK` lines print only when every invocation passes. GNU `xargs` exits 123 and
  BSD `xargs` exits 1 for a failed child, so the recipe tests for non-zero, never a specific
  code.
- **Unchanged:** the missing-tool guard, the severities, the file lists and the empty-list checks.

**A2. Provision GNU `parallel` on Ubuntu.**
- **Why:** `make test` silently falls back to serial without GNU parallel (717s against 71s,
  measured 2026-09-21). After this work, `make bash-coverage` does too. Nothing provisions the
  tool on Linux: `claude` got it as a Recommends of `bats`, and no repo file names it. macOS
  already has `brew "parallel"` in the `Brewfile`.
- **Change:** `install_bats_linux` installs `parallel` when `parallel --version` does not print a
  `GNU parallel` first line. It uses the same `sudo -H DEBIAN_FRONTEND=noninteractive apt-get
  install "${APT_CONFFILE_OPTS[@]}" -y` form as the `bats` install.
- **A non-GNU `parallel`:** if a `parallel` exists that is not GNU's (moreutils ships one), the
  function warns, naming the conflicting binary, and installs nothing. This is default-deny: it
  never replaces a tool it does not own.
- **Return value:** it returns non-zero when either install fails.

**Left out: `make test-python` runs serially.** CI run 39075591428 logged `Ran 180 tests in
0.228s`, so there is nothing to gain.

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

### Round 3 — spec at `d38d8d9d`

All three lenses, told rounds 1–2 were history.

| # | Lens | Sev | Finding |
|---|------|-----|---------|
| A | goal-fit | HIGH | §2 (the trace-filter rewrite, the separator and `--filter-trace`) fixed no defect. Today's filter already matches the root with `grep -F`, and M3 shows a prefix cannot tear. It changed no decision and does nothing for runtime. |
| B | risk | MED | The required `: ` separator changes what today's filter extracts, at zero headroom, and V1 cannot see it because both modes use the new filter. |
| C | ergonomics | MED | A bare `--filter-trace` would use `/` as the root and report success. |
| D | risk | MED | `mapfile < <(_coverage_bats_args)` discards the function's status (measured `rc=0`, empty argv), so R2's exit 2 could silently vanish. |
| E | goal-fit | LOW | The mode line was derived from the variable, not from the argv bats receives, so a call site that ignored the function would still log "parallel". |

Disposition: **Addressed (operator, 2026-10-17).**

- A, B, C: §2 was cut, and the filter stays untouched (N1).
- D: R3 requires `_out="$(_coverage_bats_args)" || exit 2`, pinned by case 4.
- E: R4 derives the mode line from `_bats_args`, and V2 gains a duration threshold.

The design shrank, so review stops here.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.

## Amendments

- adds R9: `make lint` runs both shellcheck passes over the unchanged `SHELL_FILES` and `BATS_FILES` lists through `xargs -n 4 -P $(JOBS)`, fails lint when any invocation exits non-zero, and prints `shellcheck OK` / `shellcheck bats OK` only when every invocation of that pass passed. — operator pulled the parallel-lint backlog item into this work (Addendum A1)
- adds R10: `install_bats_linux` installs `parallel` with `sudo -H DEBIAN_FRONTEND=noninteractive apt-get install "${APT_CONFFILE_OPTS[@]}" -y parallel` when `parallel --version` does not print a `GNU parallel` first line and no other `parallel` is on PATH, warns naming the binary and installs nothing when a non-GNU `parallel` is on PATH, and returns non-zero when either the bats or the parallel install fails. — operator pulled the provisioning backlog item into this work (Addendum A2)
- adds R11: Tests cover R9 (a failing file in each pass fails `make lint` and suppresses its OK line, under `xargs -P`) and R10 (GNU present: no install; absent: install; non-GNU present: warn, no install; install failure: non-zero) and pass. — tests for the pulled-in items
- adds V4: On `claude`, time `make lint` before and after R9 and record both; both exit 0. — measures the pulled-in speed-up
- adds N6: The shellcheck severities, the `SHELL_FILES` / `BATS_FILES` definitions and the missing-tool guard in `make lint` are unchanged. — bounds the lint change

