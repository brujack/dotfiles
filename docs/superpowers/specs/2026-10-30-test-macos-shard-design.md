# Shard `test-macos` across hosted macOS runners

- **Date:** 2026-10-30
- **Backlog row:** "`test-macos` takes 17-29 min on GitHub's 3-vCPU macOS runner, against a 30-min `timeout-minutes`" (P1 — performance)
- **Designed with:** the ansible session (cross-session, 2026-10-30), which priced a self-hosted Studio runner against this approach.
- **Approved:** 2026-10-31

## Problem

`test-macos` runs the whole suite as one job on `macos-latest` (3 vCPU). The job is a required
check and is in `auto-merge`'s `needs:`, so every PR waits on it. On dotfiles#408 it took six
attempts to merge one PR.

The last 14 successful runs (`gh run list --workflow ci.yml`, run 40783669811 through 40998654932)
took 17, 20, 20, 20, 21, 22, 22, 24, 25, 25, 26, 26, 27 and 29 min. The cap is
`timeout-minutes: 30`. In 11 of them, the `Run tests` step alone took 20-30 min; one finished 12 s
under the cap. Checkout, `brew install`, and the pinned shellcheck and uv install together take
about 20 s.

## Measurements

| What                                              | Population                                                                   | Result                                                    |
| ------------------------------------------------- | ---------------------------------------------------------------------------- | --------------------------------------------------------- |
| Hosted `test-macos` duration                      | 14 successful runs, PR/master, 2026-10-29/30                                 | 17-29 min; setup steps ~20 s                              |
| Studio `make test` by job count (ansible session) | Studio bare metal; coreutils gnubin on `PATH`, rc 2, timing only             | JOBS=3 1415 s, JOBS=16 333 s                              |
| Studio full suite (this session)                  | Studio, macOS 27.2, fresh clone, `env -i`, `/usr/bin/make` 3.81, bats 1.14.0 | 3613/3613, ~5 min, rc 0                                   |
| Per-file serial timing (this session)             | Studio, `faa2f993`, `env -i`, one `bats <file>` at a time, all 86 files rc 0 | 2043 s total, 0.57 s/test mean, 0.30-1.82 s/test per file |
| Shard trial, serial-seconds packing               | Studio, `faa2f993`, `env -i`, each shard `bats --jobs 3`, one after another  | 388 / 458 / 535 s for 975 / 1112 / 1526 tests, all rc 0   |
| Per-file CPU (user+sys, children included)        | Studio, `ab92a62d`, `env -i`, `/usr/bin/time -p bats --jobs 3 <file>`, 6 files concurrent, all 86 rc 0 | 2680 s total, 0.74 s/test mean |
| `make test` prerequisites CPU                     | Studio, `ab92a62d`, `env -i`, `/usr/bin/make lint check-lock check-requirements-ci test-python check-claude-md-budget`, rc 0, shellcheck ran | 38.8 s (34.85 user + 3.96 sys), 14.6 s wall |
| Suite composition                                 | `ab92a62d`, `find tests -name '*.bats'`, `grep -c '^@test'`                  | 86 files, 3621 `@test`                                    |

On bare metal, 3 jobs take 1415 s, inside the hosted runner's 1200-1790 s range. The cost is macOS
process overhead, not virtualization, so splitting the files across parallel hosted jobs divides
wall-clock roughly by the shard count, plus about 20 s of setup each.

Per-test cost varies 6x across files (`tests/scripts/makefile_lint_scope.bats` 1.82 s/test,
`tests/scripts/unit.bats` 0.30 s/test at `faa2f993`), so `@test` count is a poor weight.

Serial wall seconds turned out to be a poor weight too. The trial packed the three shards to
681 / 681 / 681 serial seconds, and they ran in 388 / 458 / 535 s. Serial timing misses the
per-test cost of `bats --jobs` mode, and a shard runs in that mode. A CI shard runs `JOBS=24` on
3 vCPU, so it is CPU-bound and its wall-clock follows its CPU seconds.

CPU seconds measured under `bats --jobs 3` explain the trial. The trial's three shards weigh 815 /
866 / 999 CPU s, in the same order as their wall-clock, and the ratio of wall to CPU varies 12%
across them against 38% for wall to serial seconds. That trial ran unsaturated (3 jobs on 20
cores), so CPU predicts it only partly; on a saturated runner it should predict more.

Packing the 86 files into 3 shards at `ab92a62d`, each shard's CPU seconds:

| Packed by              | CPU seconds per shard |
| ---------------------- | --------------------- |
| `@test` count          | 1056 / 881 / 743      |
| serial wall seconds    | 815 / 866 / 999       |
| CPU seconds            | 893 / 894 / 894       |

So the shards are weighted by CPU seconds. The heaviest file, `tests/setup_env/linux_ubuntu.bats`,
is 529 CPU s. That is below a third of the suite (893 s), so it does not bound three shards. It
would start to bound five (536 s each).

## Alternatives considered

- **Self-hosted runner on the Studio** (the ansible session's design): ~5 min per run, but dotfiles
  is public with 2 forks.
  - `pull_request` runs the PR head's workflow, so a fork can retarget `runs-on`.
  - Personal-account repos have no runner groups. The only controls are an
    `all_external_contributors` approval policy and an ephemeral VM, plus a non-admin runner user,
    `pf` egress rules, a route job with a PAT, JIT registration and a queue watchdog.
  - It also moves the suite onto 20 cores, which would hide the starved-runner condition under
    which dotfiles#408 stalled twice.
  - Kept as Phase 2 if this spec misses its target.
- **Raise `timeout-minutes` alone:** it would have saved 2 of #408's 5 retries, but every PR would
  still wait ~22 min.
- **Split by directory:** `tests/setup_env/` alone is 78% of the tests.
- **Weight by `@test` count:** see the table above. Count-packing leaves the heaviest shard 18%
  above the CPU-packed one (1056 against 894 CPU s).

## Decision

Three shards (operator, 2026-10-30). GitHub allows 5 concurrent macOS jobs per account. With
`lint-macos`, one dotfiles PR uses 4 of them. etch-config's CI also runs on `macos-latest`, so
concurrent PRs, including a Monday Renovate burst, can queue. Estimated wall-clock per shard is
about 1415 s / 3 ≈ 8 min (the JOBS=3 bare-metal figure split three ways) plus ~20 s of setup.

That is a mean, and the gate waits for the slowest of three independent runners, whose speed
varies ±25% run to run. Bootstrapping the 14 measured durations (max of 3 draws, divided by 3)
gives the `Run tests` step p50 8.7 min and p90 9.7 min. Add ~20 s of shard setup, ~30-60 s for the
ubuntu gate job (pickup, checkout, download), and any macOS queue: p90 is about 10.5-11 min before
queueing. Four shards would cut the step to ~6.5 min p90 but use all 5
account macOS slots with `lint-macos`, so any concurrent macOS job, from etch-config or a second
dotfiles PR, would queue. The operator kept 3 shards and set V1 to 12 min, queue included
(2026-10-31), leaving one macOS slot free.

The shard count lives in one place: the matrix list.

## Design

### Weights: `tests/bats-weights.tsv`

A committed table, one line per `.bats` file: `<path>\t<cpu-seconds>`, sorted with
`LC_ALL=C sort`. Each value is the user plus system CPU seconds, children included, of
`bats --jobs 3 <file>` on macOS under `env -i`. Lines starting with `#` are comments; the first
names the commit and host it was measured on.

- Seeded from the `ab92a62d` Studio run above.
- Reseeded by hand, not by a make target. The procedure is a documented command block in
  ai-config `docs/knowledge/dotfiles-bats-test-infrastructure.md`: the per-file `/usr/bin/time -p`
  loop above, run 6 files at a time on the Studio (~8 min), then `LC_ALL=C sort`. Reseed when V2
  fails or when a file's cost changes by a large factor, as `makefile_lint_scope.bats` did in
  dotfiles#410.
- A stale or partial table changes only balance, never correctness. The partition check below does
  not read it.

### Shard selection: `scripts/bats-shard.sh`

`bats-shard.sh <index> <count>` prints, one per line, the `.bats` files shard `<index>` (1-based)
of `<count>` runs. It covers every file, `BATS_SERIAL_FILES` included; the Makefile decides how a
listed file runs.

1. Read `find tests -name '*.bats'`, sorted with `LC_ALL=C sort`. This is the same population as
   the Makefile's `BATS_ALL_FILES`.
2. Weight each file by its value in `tests/bats-weights.tsv` (overridable as `BATS_WEIGHTS`).
   - A **live row** names a file in the list from step 1. A **dead row** names a file that is not
     in it (deleted or renamed). Dead rows are ignored and each is named on stderr; they never
     fail the run.
   - A file with no live row weighs its `^@test` count times the table's CPU seconds per test,
     which is the sum of live-row values divided by the sum of `^@test` over the live-row files.
     A new file needs no table edit.
   - No live rows, a live-row `^@test` sum of zero, or a non-comment line that is not
     `<path>\t<non-negative number>` is an error (step 4).
3. Visit files from heaviest to lightest (ties broken by path, ascending), and assign each to the
   shard with the lowest running weight (ties broken by lowest index). Shard 1 starts with a
   handicap of `BATS_SHARD_HANDICAP` CPU seconds (default 40), because it also runs the `make test`
   prerequisites, measured at 38.8 CPU s above.
4. Compute every shard's list fully, then print only shard `<index>`'s. Print nothing and exit 2,
   with a message on stderr, on: a non-integer or out-of-range argument, `<count>` below 1, an
   unreadable weights file, a table error from step 2, or an empty file list.

`BATS_WEIGHTS` and `BATS_SHARD_HANDICAP` are read from the script's own environment. Make never
calls the script, so nothing has to forward them.

The output is a pure function of the tree, the table and those two variables.

### One list per shard, computed once

Each CI shard runs `bats-shard.sh` once, in a bash step whose exit status fails the step, and
writes `shard-<i>.files`. That single file is what make runs, what `ci-suite-report.sh` counts
against, and what the gate checks. No second computation exists that could disagree with it.

Make still reads the file with `$(shell cat …)`, because GNU Make 3.81 has no working `$(file <…)`
(measured on the Studio's `/usr/bin/make`: it expands to empty). It cannot see `cat`'s exit status,
but both failures close: a failed read gives an empty list, which is refused, and a short read
leaves executed below declared in `ci-suite-report.sh --files`.

### Makefile

- **`BATS_FILES_FROM`:** empty by default. When set, it names a file of `.bats` paths, one per
  line.
  - The bats recipe runs only those paths. The serial pass runs
    `$(filter $(BATS_SERIAL_FILES),$(BATS_RAN_FILES))` and the parallel pass the `filter-out` of
    the same, each wrapped in its own `ifneq ($(strip …),)`. A serial file therefore stays serial
    in whichever shard it lands, runs in that shard only, and a shard holding only serial files
    never calls bats with no file arguments. Today's recipe runs `$(BATS_SERIAL_FILES)` unfiltered
    and the parallel pass unguarded; both change.
  - An unset or empty `BATS_FILES_FROM` leaves everything as today.
  - A set `BATS_FILES_FROM` naming a missing file (`$(wildcard …)` empty) or a file listing no
    paths is refused with a non-zero exit before bats starts. The contents come from
    `$(shell cat …)`, as above.
  - `BATS_FILES_FROM` is unrelated to the existing `BATS_FILES` (the `git ls-files` list `lint`
    reads), which is untouched.
  - It is `unexport`ed. CI passes it as step `env:`, never as a make argument, because a
    command-line variable reaches every nested make through `MAKEFLAGS`. Many bats tests run
    `make`; under a shard they must see the unsharded Makefile, as they do locally.
- **`BATS_RAN_FILES`:** the files an invocation runs. With `BATS_FILES_FROM` it is that file's
  paths; without, `BATS_ALL_FILES`.
- **`test-bats`:** the bats recipe moves from `test` into this new target. `test` becomes its
  current prerequisites plus `test-bats`, so `make test` with no `BATS_FILES_FROM` behaves exactly
  as before.
- **Empty-list refusal:** the existing refusal is extended to `BATS_RAN_FILES`.

### `scripts/ci-suite-report.sh`

Gains a `--files <listfile>` mode: `ci-suite-report.sh <log> --files <listfile>`. The executed
count still comes from `<log>`; the declared count is the `^@test` count over the listed files,
and the executed count must equal it. The existing refusal of a zero declared count applies in both
modes. The existing two-argument form `ci-suite-report.sh <log> <dir>` is unchanged.

### `scripts/ci-shard-gate.sh`

`ci-shard-gate.sh <dir>` reads every `<dir>/shard-*.files`, one path per line. It fails if no such
file exists, and otherwise unless both of these hold:

1. **Coverage:** the union of the file lists equals an independent
   `find tests -name '*.bats' | LC_ALL=C sort`, computed in the gate (never by calling
   `bats-shard.sh` or make). Equality, not containment, so a blank line, an extra path or a path
   split at a space also fails.
2. **Disjointness:** no file appears in two lists.

It prints which check failed and the offending files.

**Coverage proves every shard passed.** A shard uploads its list only after its tests and its
`ci-suite-report.sh --files` check have passed (the step's default `success()` condition). A
failed, cancelled or skipped shard leaves no list for this attempt, so the union misses its files.
The gate's `needs.test-macos-shard.result` check is then a second, independent signal, not the only
one. Whether that result aggregates matrix legs as documented is unverified, and with this design
nothing depends on it alone.

### CI (`.github/workflows/ci.yml`)

- **`test-macos-shard`:**
  - `strategy.fail-fast: false`, matrix `shard: [1, 2, 3]`, `runs-on: macos-latest`,
    `timeout-minutes: 30`, `permissions: contents: read`.
  - The install steps are unchanged.
  - A bash step runs
    `bash scripts/bats-shard.sh ${{ matrix.shard }} ${{ strategy.job-total }} > shard-${{ matrix.shard }}.files`.
    The matrix list is the only place the count is written.
  - The test step sets `BATS_FILES_FROM: shard-${{ matrix.shard }}.files` in its `env:`. Shard 1
    runs `make test`; the others run `make test-bats`.
  - It runs `ci-suite-report.sh <log> --files shard-<i>.files`.
  - On success only, it uploads `shard-<i>.files` as artifact
    `test-macos-shard-${{ github.run_attempt }}-<i>`. The attempt number keeps a re-run from
    colliding with, or being satisfied by, an earlier attempt's list. A "re-run failed jobs"
    attempt therefore fails coverage, which enforces the never-`--failed` rule mechanically.
  - On failure or cancel, it uploads its full log as `test-macos-make-test-log-<i>` with
    `overwrite: true`, as the single job does today.
- **`test-macos`** (the gate):
  - `runs-on: ubuntu-latest`, `needs: test-macos-shard`, `if: always()`, `timeout-minutes: 10`,
    `permissions: contents: read`.
  - It prints `needs.test-macos-shard.result` and fails unless it is `success`, which covers
    `failure`, `cancelled` and `skipped`. Per-shard results are in the run UI; printing them would
    need the jobs API and `actions: read`, for no change to the verdict.
  - It then checks out the repo and downloads the lists with `actions/download-artifact`, pinned
    to a full commit SHA, with `pattern: test-macos-shard-${{ github.run_attempt }}-*`,
    `merge-multiple: true` and `path: shard-lists`. Without `merge-multiple`, each artifact lands
    in its own subdirectory and the gate's glob finds nothing. It then runs
    `ci-shard-gate.sh shard-lists`.
- The job name `test-macos`, branch protection's required checks, and `auto-merge`'s `needs:`
  list are unchanged. `auto-merge`'s own `if:` carries an implicit `success()`, so a red gate skips
  it.

### Docs

- **`CLAUDE.md`, CI section:**
  - Rewrite the `test-macos` bullet for the shard job plus gate.
  - Which files a shard ran: its `test-macos-shard-<attempt>-<i>` artifact is the authority.
    `bash scripts/bats-shard.sh <i> 3` recomputes it from a clean tree at the same SHA; an
    untracked `.bats` file changes the answer.
  - Local repro of a failed shard: recompute its list, then
    `BATS_FILES_FROM=<list> make test-bats`.
  - All three `test-macos-make-test-log-<i>` artifacts are replaced by a re-run, so download them
    first.
  - Re-run all jobs, never `--failed`; a `--failed` attempt fails the gate's coverage check.
- **`CLAUDE.md`, the `needs:` rule:** amend "Every job in `needs:` is a gate with no advisory tier
  (no `continue-on-error`, no `always()`)" to: no `continue-on-error`, and the only `always()` is
  the `test-macos` aggregation gate, which fails on any shard result other than `success`.
- **`CLAUDE.md`, the runner list:** `test-macos` moves to `ubuntu-latest`; `test-macos-shard`
  runs on `macos-latest`.
- **`CLAUDE.md`, timeouts:** the list adds `test-macos-shard` 30 and `test-macos` 10.
- **`CLAUDE.md`, Testing:** a line on `tests/bats-weights.tsv`: what it measures, that it changes
  balance only, and a pointer to the reseed procedure. The table's `#` header also names the
  procedure's location.
- **ai-config `docs/knowledge/dotfiles-bats-test-infrastructure.md`:** the reseed command block
  and the measurements behind CPU weighting.
- **ADR-0053:** records the sharded shape, CPU-seconds weighting and the self-hosted alternative. It
  partly supersedes ADR-0037's single-job decision, and ADR-0037's status line notes that.
- **Backlog:** the P1-performance row is rewritten to point at this spec and at V1.

## Testing

TDD, bats, in `tests/scripts/`. Every case that expects success also asserts a non-empty result.

- **`bats_shard.bats`:**
  - For N in 1..4 over the real tree: the shards' outputs are each non-empty, disjoint, and their
    union equals the full sorted list. The test also asserts the list has more than 80 entries, so
    an empty `find` cannot pass.
  - **Golden fixture:** a fixture tree and table with tied weights and tied running totals, where
    `BATS_SHARD_HANDICAP=0` and a non-zero handicap each give known, different, exact per-shard
    outputs. This pins the heaviest-first order, both tie-breaks and the handicap.
  - **Balance beats count-packing**, non-vacuous: pack N = 3 twice with `BATS_SHARD_HANDICAP=0`,
    once with the committed table and once with a generated table whose values are each file's
    `^@test` count. Score both partitions with the committed CPU table. The first's heaviest shard
    is lighter. Measured: 894 against 1056. Scoring the second in its own units (tests) would pass
    for any packing.
  - A file absent from a fixture table lands in exactly one shard, and its weight is its `^@test`
    count times the live rows' CPU seconds per test (shown by a fixture where that weight decides
    the shard).
  - A dead row is named on stderr, does not change the output, and does not change the exit status.
  - Bad arguments, an unreadable table, a table with no live rows, a malformed line and an empty
    fixture tree each exit 2 with empty stdout.
- **`ci_shard_gate.bats`**, over fixture directories:
  - A correct non-empty 3-shard partition passes.
  - A missing file and an overlap each fail, naming the check.
  - A directory that does not exist, a directory with no `shard-*.files`, a blank line and an
    extra path each fail.
  - **Drop-one-file control:** start from the real 3-shard output, delete one line from one
    shard's list, and expect a failure naming coverage.
  - **Real-output control:** write `bash scripts/bats-shard.sh <i> 3 > shard-<i>.files` for i in
    1..3, the command CI runs, and expect the gate to pass.
- **`ci_suite_report.bats`:**
  - `<log> --files` passes when executed equals declared over a non-empty list, fails one short,
    and fails on an empty list.
  - The two-argument form is unchanged.
- **Makefile** (`makefile_parallel_target.bats` style: a `PATH` shim stubs `bats` and records its
  argv and environment, so no test runs real bats inside `make test`):
  - With `BATS_FILES_FROM` unset, the recorded argv equals today's.
  - With `BATS_FILES_FROM` set in the environment to a fixture list, the argv names exactly the
    listed files, non-empty, and the stub's environment has no `BATS_FILES_FROM`.
  - A listed file that is also in a fixture `BATS_SERIAL_FILES` goes to the serial invocation, and
    an unlisted serial file does not run. A list holding only a serial file makes no parallel
    invocation and exits 0.
  - A missing list file and an empty one each exit non-zero before the stub runs.
- **CI-shape tests**, parsed per job with the job-block `awk` pattern of `ci_runner_pins.bats`,
  never by grepping the whole file. The parser returns each job's raw text, `run: |` block bodies
  included, so a check of what a command line contains sees the command; a positive control shows
  it sees the shard job's `make test` line inside its `run:` body. It also gains the step keys
  these need (`env:`, `with:` children such as `pattern:` and `merge-multiple:`):
  - The existing `ci_test_macos_log.bats` assertions retarget to job `test-macos-shard`, and
    `ci_runner_pins.bats`'s positive control retargets to it (the gate now runs on
    `ubuntu-latest`).
  - `always()` occurs exactly once in `ci.yml` outside comments, as the `if:` of job `test-macos`, which also
    references `needs.test-macos-shard.result`. A positive control shows the parser attributes a
    line to its own job, not a neighbour.
  - The matrix has `fail-fast: false`.
  - The shard job's `bats-shard.sh` call is built from `matrix.shard` and `strategy.job-total`;
    the test asserts the occurrence count before checking the form.
  - `BATS_FILES_FROM` is set under a step's `env:`, and never on a `make` command line (checked
    over the raw job text above, not over parsed keys).
  - New test: every `uses:` line in `test-macos-shard` and `test-macos` is pinned to a 40-hex SHA.
    The retargeted `ci_test_macos_log.bats` pin check passes if either of the shard job's two
    `upload-artifact` steps is pinned, and nothing else covers the gate's `download-artifact`.
  - The list upload has no `if:` and its name contains `github.run_attempt`; the download
    `pattern:` contains `github.run_attempt`, sets `merge-multiple: true`, and its `path:` is the
    directory passed to `ci-shard-gate.sh`.
- `make test` stays green.

## Requirements

- **R1.** `[PR1]` `scripts/bats-shard.sh <i> <N>` prints shard `i` of `N` one path per line over every `.bats` file, assigning files heaviest-first by their CPU seconds in `tests/bats-weights.tsv` (or, with no live row, `^@test` count times the live rows' CPU seconds per test) to the lightest shard, ties by path then lowest index, with shard 1 starting at `BATS_SHARD_HANDICAP` (default 40); dead rows are named on stderr and ignored; it computes all shards before printing and exits 2 with empty stdout on bad arguments, an unreadable or malformed weights file, a table with no live rows or a live-row `^@test` sum of zero, or an empty list.
- **R2.** `[PR1]` For every N from 1 to 4, the shards' outputs over the real tree are non-empty, disjoint and their union equals `find tests -name '*.bats' | LC_ALL=C sort`.
- **R3.** `[PR1]` With `BATS_FILES_FROM` unset, `make test` runs the same prerequisites and the same bats file list as before this change; with it set, `make test-bats` runs exactly the listed files (listed `BATS_SERIAL_FILES` serially, unlisted ones not at all, and no empty bats invocation), refuses a missing or empty list with a non-zero exit, and does not export `BATS_FILES_FROM` to its recipes.
- **R4.** `[PR1]` `ci-suite-report.sh <log> --files <list>` compares the log's executed count against the `^@test` count over the listed files only and refuses a zero declared count; the two-argument form is unchanged.
- **R5.** `[PR1]` `ci-shard-gate.sh <dir>` reads `<dir>/shard-*.files` one path per line; it fails on a missing `<dir>` or no list files, fails naming the check on a file missing from every list, an entry not in the independent `find` or a file in two lists, passes on a correct non-empty partition including one written by `bats-shard.sh` itself, and fails naming coverage when one line is removed from one shard's list.
- **R6.** `[PR1]` `ci.yml` runs `test-macos-shard` as a matrix over `[1, 2, 3]` with `fail-fast: false`, writing `shard-<i>.files` with `bats-shard.sh ${{ matrix.shard }} ${{ strategy.job-total }}` in a bash step and passing it to make as step-`env:` `BATS_FILES_FROM`; and a job named `test-macos` on `ubuntu-latest` with `needs: test-macos-shard` and `if: always()` (the only `always()` in `ci.yml`) that fails unless `needs.test-macos-shard.result` is `success`, downloads this attempt's lists with `merge-multiple: true` into one directory, then runs `ci-shard-gate.sh` on it.
- **R7.** `[PR1]` Each shard runs `ci-suite-report.sh <log> --files shard-<i>.files`, uploads the list as `test-macos-shard-<run_attempt>-<i>` only on success, and uploads its full log as `test-macos-make-test-log-<i>` on failure or cancel.
- **R8.** `[PR1]` `tests/bats-weights.tsv` is committed with one line per `.bats` file holding CPU seconds of `bats --jobs 3 <file>` on macOS, measured at or after dotfiles#410, and the reseed procedure is documented in ai-config `docs/knowledge/dotfiles-bats-test-infrastructure.md`; no make target generates it.
- **R9.** `[PR1]` `CLAUDE.md` describes the shard job and gate, the authoritative per-shard list, the local repro command, the single `always()` exception, both jobs' runners and timeouts, and the weights table.
- **R10.** `[PR1]` ADR-0053 exists, is indexed, and ADR-0037's status notes the partial supersession.
- **V1.** Over the first 10 PR runs after merge, at least one of them in a Monday Renovate window, p90 of `test-macos` gate completion minus the run's creation time (queue included) is at most 12 min. Otherwise, open a follow-up to move to 4 shards or to Phase 2 (self-hosted).
- **V2.** Over at least 5 CI runs, take each shard's median `Run tests` duration divided by its packed weight (shard 1's table weight plus `BATS_SHARD_HANDICAP`). If any shard's ratio is more than 10% from the three-shard mean, re-tune the handicap from shard 1's ratio against the others, or reseed the table by the documented procedure when shards 2 and 3 disagree. Count-packing's spread (1056 against 743) would breach this; a 3-min wall-clock tolerance would not, which is why the ratio is used.
- **N1.** No self-hosted runner and no new secret or token.
- **N2.** No change to branch protection's required checks or to `auto-merge`'s `needs:` list.
- **N3.** No change to the Linux `test`, `bash-coverage` or `powershell` jobs.
- **N4.** No change to `JOBS` or to the bats flags within a shard.
- **N5.** No change to what any existing test asserts, except retargeting the job named in `ci_test_macos_log.bats` and in `ci_runner_pins.bats`'s positive control from `test-macos` to `test-macos-shard`; speed-ups to individual tests are separate changes.

## Round 2 (2026-10-31)

Changes after the operator reviewed round 1:

- **Weight unit:** serial seconds became CPU seconds under `bats --jobs 3`, from the shard trial
  and the CPU measurement above. A considered alternative, `seconds + tests × floor`, fits a free
  parameter to the same overhead that a CPU measurement captures directly, so it was dropped.
- **Reseed:** the weights were measured after dotfiles#410, which changed
  `makefile_lint_scope.bats`'s cost; the `faa2f993` serial table predates it. `make bats-weights`
  was dropped for a documented procedure.
- **Handicap:** 60 → 40, from the measured 38.8 CPU s of the `make test` prerequisites.
- **File-list format:** one path per line, written once per shard by `bats-shard.sh` in a bash
  step and read by make, `ci-suite-report.sh` and the gate alike (`BATS_FILES_FROM`). This replaced
  a `BATS_SHARD` make variable after the round-2 lenses (below).
- **Artifact layout:** attempt-scoped names, success-only upload, `merge-multiple: true` into one
  directory.
- **Fallback weight:** defined over live rows; dead rows reported, not fatal; an empty table exits 2.
- **Balance test:** compares against count-packing, so it cannot pass on any packing.
- **`always()` test:** parsed per job.
- **Counts:** 3621 tests at `ab92a62d`.

## Multi-Lens Review

Round 1 reviewed at commit `faa2f993` (Step 7 self-review commit, before Step 8 dispatch). Round 2
reviewed at `b0a9c67a`; its record follows the round-1 lenses.

### Goal-Fit

Finding: Worth building. The premise was verified from step timings of 11 runs (`Run tests` 20-30
min, one 12 s under its cap). Setup is ~20 s, not ~1.5 min. Raising the timeout alone saves
retries but not the ~22 min wait. The gate's counts check is implied by the per-shard check plus
coverage and disjointness, so it can't change a verdict, and arity adds nothing beyond an empty
shard. Empty-input PASS cases need pins: an empty `--files` list, a shard executing zero tests,
non-zero `.executed` in fixtures. etch-config also uses the 5-slot macOS limit.
Assumption: per-test runtime is uniform enough that count-balancing balances wall-clock.
Disposition: Addressed (operator, 2026-10-30). Measured on the Studio: count-packing gives
872/644/527 s against seconds-packing's 681/681/681 s, so weighting moved to a committed seconds
table. The counts and arity checks were dropped. Empty cases are pinned. etch-config is named in
the Decision.

### Ergonomics

Finding: The CI-shape consistency test passes vacuously on zero `BATS_SHARD` matches. Other PASS
cases pass on empty output. "Single constant" was false: N was hand-written in four places. The
local repro command didn't match CI's shards 2 and 3. The gate's failure didn't name the shard.
There are now three log artifacts to download. File-to-shard mapping moves when files are added.
A matrix doesn't change the re-run-all rule, but each re-run takes 3 macOS slots.
Assumption: wall-clock proportional to `@test` count.
Disposition: Addressed (operator, 2026-10-30). N is derived from `strategy.job-total`, and the test
asserts the occurrence count first. Every success case asserts non-empty. The repro is
`make test-bats BATS_SHARD=i/3`. The gate prints each shard's result. The CLAUDE.md text covers
artifacts, mapping and re-runs. Weighting moved to seconds.

### Risk

Finding: Gate logic fails closed on every attacked path.

- Make 3.81 cannot see `bats-shard.sh`'s exit status. A partial list passes the per-shard check,
  so coverage is load-bearing, and the script must build its whole list before printing.
- Account-wide macOS concurrency (etch-config, Monday Renovate) exposes V1.
- Stale count (86 files, not 84). `grep -c '^@test'` matches bats' count (0 mismatches).

Assumption: `@test` count predicts runtime.
Disposition: Addressed (operator, 2026-10-30). The script computes all shards before printing. The
coverage check is documented as load-bearing. The empty-list refusal is extended to
`BATS_RAN_FILES`. V1 requires a Monday window. Counts are updated. Weighting moved to measured
seconds.

### Round 2 lenses (`b0a9c67a`, 2026-10-31)

- **Goal-Fit.** The CPU-seconds unit is right: the recipe runs `bats --jobs` with no
  `--no-parallelize-within-files`, and a saturated runner overlaps waits. Findings: the serial-packing
  row was mislabelled count-packing data (fixed: 815 / 866 / 999); the round-1 "~28%" was stale
  (fixed: 18%); V2's 3-min tolerance could not fail for any considered packing (fixed: per-shard
  ratio over at least 5 runs); the Decision estimated a mean where the gate waits for the slowest of
  three (fixed: max-of-3 estimate; operator set V1 to 12 min at 3 shards).
- **Ergonomics.** Findings: a real `make test-bats` test would recurse into the suite; `BATS_SHARD`
  as a make argument leaks into every nested make through `MAKEFLAGS`; Make 3.81's `$(shell)` sees
  no make-level variables; handicap and tie-breaks were untested; `ci-suite-report.sh --files` had
  lost its log argument; per-shard results need the jobs API; N5 was false for two retargeted test
  files. Fixed by moving list computation out of make (`BATS_FILES_FROM`, step `env:`, `unexport`),
  a stubbed-`bats` Makefile test, a golden fixture, the `<log> --files <list>` signature, dropping
  the per-shard print, and an N5 exception.
- **Round 3 (`74caceba`, all lenses, one reviewer).** `unexport` plus step `env:` verified on
  Make 4.4.1 and 3.81. Findings fixed: an all-serial shard would call bats with no files, and
  today's unfiltered serial pass would run every serial file in every shard; the `BATS_FILES_FROM`
  absence check could not see `run:` block bodies; the balance test could pass in the wrong
  units; two upload steps let one pinned SHA satisfy the pin test; Make 3.81 has no `$(file <…)`,
  so the list is read with `$(shell cat)` and fails closed by refusal or count; a missing download
  directory was untested; V2 ignored the handicap and could not re-derive per-file weights.
- **Risk.** No unconditional fail-open. Findings: a failed shard's uploaded list would satisfy
  coverage, leaving `needs.result` as the only signal; artifacts persist across attempts; the
  uploaded list came from a different make invocation from the one that ran; per-shard printing
  needs `actions: read`. Fixed by success-only, attempt-scoped uploads and one list per shard read by
  every consumer.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.
