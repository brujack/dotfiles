# Shard `test-macos` across hosted macOS runners

- **Date:** 2026-10-30
- **Backlog row:** "`test-macos` takes 17-29 min on GitHub's 3-vCPU macOS runner, against a 30-min `timeout-minutes`" (P1 — performance)
- **Designed with:** the ansible session (cross-session, 2026-10-30), which priced a self-hosted Studio runner against this approach.

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
| Suite composition                                 | this tree, `find tests -name '*.bats'`                                       | 86 files, 3653 `@test` (3613 at `faa2f993`)               |

On bare metal, 3 jobs take 1415 s, inside the hosted runner's 1200-1790 s range. The cost is macOS
process overhead, not virtualization, so splitting the files across parallel hosted jobs divides
wall-clock roughly by the shard count, plus about 20 s of setup each.

Per-test cost varies 6x across files (`tests/scripts/makefile_lint_scope.bats` 1.82 s/test,
`tests/scripts/unit.bats` 0.30 s/test). Packing the 86 files into 3 shards from the serial timings:

| Packed by        | Seconds per shard |
| ---------------- | ----------------- |
| `@test` count    | 872 / 644 / 527   |
| measured seconds | 681 / 681 / 681   |

So the shards are weighted by measured seconds.

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
- **Weight by `@test` count:** see the table above. Count-packing leaves the slowest shard ~28%
  above the seconds-packed one.

## Decision

Three shards (operator, 2026-10-30). GitHub allows 5 concurrent macOS jobs per account. With
`lint-macos`, one dotfiles PR uses 4 of them. etch-config's CI also runs on `macos-latest`, so
concurrent PRs, including a Monday Renovate burst, can queue. Estimated wall-clock per shard is
about 1415 s / 3 ≈ 8 min (the JOBS=3 bare-metal figure split three ways) plus ~20 s of setup. The shard count lives in one place: the matrix
list.

## Design

### Weights: `tests/bats-weights.tsv`

A committed table, one line per `.bats` file: `<path>\t<seconds>`. It holds serial per-file
seconds measured on macOS.

- Seeded from the Studio run above.
- Regenerated with `make bats-weights`, which times each file serially (`bats <file>`, one at a
  time) and rewrites the table. The run takes ~35 min on the Studio, so it is a manual target,
  never a prerequisite of `test`.
- A stale or partial table changes only balance, never correctness. The partition check below does
  not read it.

### Shard selection: `scripts/bats-shard.sh`

`bats-shard.sh <index> <count>` prints, one per line, the `.bats` files shard `<index>` (1-based)
of `<count>` runs.

1. Read `find tests -name '*.bats'`, sorted with `LC_ALL=C sort`. This is the same population as
   the Makefile's `BATS_ALL_FILES`. Files named in `BATS_SHARD_EXCLUDE` (space-separated; the
   Makefile passes `BATS_SERIAL_FILES`) are removed.
2. Weight each file by its seconds in `tests/bats-weights.tsv` (overridable as `BATS_WEIGHTS`).
   A file missing from the table weighs its `^@test` count times the table's seconds per test,
   so a new file needs no table edit.
3. Visit files from heaviest to lightest (ties broken by path, ascending), and assign each to the
   shard with the lowest running weight (ties broken by lowest index). Shard 1 starts with a
   handicap of `BATS_SHARD_HANDICAP` seconds (default 60), because it also runs lint, the lock
   checks and the Python suite.
4. Compute every shard's list fully, then print only shard `<index>`'s. Print nothing and exit 2,
   with a message on stderr, on: a non-integer or out-of-range argument, `<count>` below 1, an
   unreadable weights file, or an empty file list.

The output is a pure function of the tree and the table, so every caller recomputes the same split.

### Makefile

- **`BATS_SHARD`:** empty by default. When set to `i/N`, `BATS_PARALLEL_FILES` becomes
  `$(shell bash scripts/bats-shard.sh i N)`, with `BATS_SHARD_EXCLUDE` set to `BATS_SERIAL_FILES`.
  When empty, everything is as today.
- **`BATS_RAN_FILES`:** lists exactly the files an invocation runs. That is the shard's
  `BATS_PARALLEL_FILES`, plus `BATS_SERIAL_FILES` when `BATS_SHARD` is empty or `1/N`.
- **`test-bats`:** the bats recipe moves from `test` into this new target. `test` becomes its
  current prerequisites plus `test-bats`, so `make test` with no `BATS_SHARD` behaves exactly as
  before.
- **Empty-list refusal:** the existing refusal is extended to `BATS_RAN_FILES`. GNU Make 3.81 (the
  macOS runner's `/usr/bin/make`) cannot see a `$(shell)` exit status, since `.SHELLSTATUS` needs
  4.2. A failed `bats-shard.sh` therefore reaches make as an empty list, and this refusal turns it
  into a red step.
- **`bats-weights`:** a new target, described above.

### `scripts/ci-suite-report.sh`

Gains `--files <listfile>`. In that mode the declared count is the `^@test` count over the listed
files, and the executed count must equal it. The existing refusal of a zero declared count applies
in both modes. The existing two-argument form is unchanged.

### `scripts/ci-shard-gate.sh`

`ci-shard-gate.sh <dir>` reads every `<dir>/shard-<i>.files` present. It fails unless both of these
hold:

1. **Coverage:** the union of the file lists equals an independent
   `find tests -name '*.bats' | LC_ALL=C sort`, computed in the gate (never by calling
   `bats-shard.sh` or make).
2. **Disjointness:** no file appears in two lists.

It prints which check failed and the offending files.

**Coverage is the load-bearing check.** A shard's own `ci-suite-report.sh --files` proves only
that it ran every test in the list it reported. A partial list, from a `bats-shard.sh` bug or a
truncated `$(shell)`, passes that check. Only the gate's independent `find` sees the missing files.
Executed-count totals and shard arity need no check of their own: the gate runs its checks only
after every shard succeeded, every successful shard has passed its per-list count, and coverage plus
disjointness then imply both.

### CI (`.github/workflows/ci.yml`)

- **`test-macos-shard`:**
  - `strategy.fail-fast: false`, matrix `shard: [1, 2, 3]`, `runs-on: macos-latest`,
    `timeout-minutes: 30`, `permissions: contents: read`.
  - The install steps are unchanged.
  - Each shard sets `BATS_SHARD=${{ matrix.shard }}/${{ strategy.job-total }}`, so the matrix list
    is the only place the count is written. Shard 1 runs `make test`; the others run
    `make test-bats`.
  - Each shard writes `make print-BATS_RAN_FILES` to `shard-<i>.files`, then runs
    `ci-suite-report.sh --files`.
  - It uploads `shard-<i>.files` as artifact `test-macos-shard-<i>` on every run, and on failure or
    cancel `test-macos-make-test-log-<i>`.
- **`test-macos`** (the gate):
  - `runs-on: ubuntu-latest`, `needs: test-macos-shard`, `if: always()`, `timeout-minutes: 10`,
    `permissions: contents: read`.
  - It prints `needs.test-macos-shard.result` and each shard's job result (from the matrix job
    list).
  - It fails if the aggregate result is anything other than `success`, which covers `failure`,
    `cancelled` and `skipped`.
  - It then checks out the repo, downloads the `test-macos-shard-*` artifacts with
    `actions/download-artifact` pinned to a full commit SHA, and runs `ci-shard-gate.sh`.
- The job name `test-macos`, branch protection's required checks, and `auto-merge`'s `needs:`
  list are unchanged.

### Docs

- **`CLAUDE.md`, CI section:**
  - Rewrite the `test-macos` bullet for the shard job plus gate.
  - Local repro of a shard is `make test-bats BATS_SHARD=<i>/3`.
  - Which shard runs a file is recomputed at each SHA (`bash scripts/bats-shard.sh <i> 3`), so
    find it at the failing commit.
  - All three `test-macos-make-test-log-<i>` artifacts are replaced by a re-run, so download them
    first.
  - Re-run all jobs, never `--failed` (ai-config `finishing-a-development-branch`).
- **`CLAUDE.md`, the `needs:` rule:** amend "Every job in `needs:` is a gate with no advisory tier
  (no `continue-on-error`, no `always()`)" to: no `continue-on-error`, and the only `always()` is
  the `test-macos` aggregation gate, which fails on any shard result other than `success`.
- **`CLAUDE.md`, timeouts:** the list adds `test-macos-shard` 30 and `test-macos` 10.
- **`CLAUDE.md`, Testing:** a line on `tests/bats-weights.tsv` and `make bats-weights`.
- **ADR-0053:** records the sharded shape, seconds weighting and the self-hosted alternative. It
  partly supersedes ADR-0037's single-job decision, and ADR-0037's status line notes that.
- **Backlog:** the P1-performance row is rewritten to point at this spec and at V1.

## Testing

TDD, bats, in `tests/scripts/`. Every case that expects success also asserts a non-empty result.

- **`bats_shard.bats`:**
  - For N in 1..4 over the real tree: the shards' outputs are each non-empty, disjoint, and their
    union equals the full sorted list. The test also asserts the list has more than 80 entries, so
    an empty `find` cannot pass.
  - Two runs give identical, non-empty output.
  - For N = 3 with the committed table, the heaviest shard's weight, handicap excluded, is at most
    the lightest's plus the largest single file's weight.
  - A file absent from a fixture weights table still lands in exactly one shard.
  - `BATS_SHARD_EXCLUDE` removes a named file that is present without it.
  - Bad arguments, an unreadable weights file and an empty fixture tree each exit 2 with empty
    stdout.
- **`ci_shard_gate.bats`**, over fixture directories:
  - A correct non-empty 3-shard partition passes.
  - A missing file and an overlap each fail, naming the check.
  - **Drop-one-file control:** start from the real 3-shard output, delete one line from one
    shard's list, and expect a failure naming coverage.
- **`ci_suite_report.bats`:**
  - `--files` passes when executed equals declared over a non-empty list, fails one short, and
    fails on an empty list.
  - The two-argument form is unchanged.
- **CI-shape tests:**
  - The existing `ci_test_macos_log.bats` assertions move to `test-macos-shard`.
  - New assertions:
    - The gate job has `if: always()` and references `needs.test-macos-shard.result`.
    - The matrix has `fail-fast: false`.
    - `BATS_SHARD` occurs in the shard job and is built from `matrix.shard` and
      `strategy.job-total`. The test asserts the occurrence count before checking the form.
- **Makefile:**
  - `make test` stays green.
  - `make test-bats BATS_SHARD=2/3` executes a non-zero number of tests, all from shard 2's list.
  - `make print-BATS_RAN_FILES BATS_SHARD=1/3` includes `BATS_SERIAL_FILES` when it is set to a
    fixture value.

## Requirements

- **R1.** `[PR1]` `scripts/bats-shard.sh <i> <N>` prints shard `i` of `N`, assigning files heaviest-first by their seconds in `tests/bats-weights.tsv` (or `^@test` count times the table's seconds per test when absent) to the lightest shard, with shard 1 starting at `BATS_SHARD_HANDICAP` (default 60); it computes all shards before printing and exits 2 with empty stdout on bad arguments, an unreadable weights file or an empty list.
- **R2.** `[PR1]` For every N from 1 to 4, the shards' outputs over the real tree are non-empty, disjoint and their union equals `find tests -name '*.bats' | LC_ALL=C sort` minus `BATS_SHARD_EXCLUDE`; `BATS_RAN_FILES` adds `BATS_SERIAL_FILES` to shard 1 only.
- **R3.** `[PR1]` With `BATS_SHARD` unset, `make test` runs the same prerequisites and the same bats file list as before this change; with `BATS_SHARD=i/N`, `make test-bats` runs only shard `i`'s files, and an empty `BATS_RAN_FILES` is refused with a non-zero exit.
- **R4.** `[PR1]` `ci-suite-report.sh --files <list>` compares executed against the `^@test` count over the listed files only and refuses a zero declared count; the two-argument form is unchanged.
- **R5.** `[PR1]` `ci-shard-gate.sh` fails, naming the check, on a file missing from every shard list or a file in two lists, passes on a correct non-empty partition, and fails naming coverage when one line is removed from one shard's list.
- **R6.** `[PR1]` `ci.yml` runs `test-macos-shard` as a matrix over `[1, 2, 3]` with `fail-fast: false` and `BATS_SHARD=${{ matrix.shard }}/${{ strategy.job-total }}`, and a job named `test-macos` on `ubuntu-latest` with `needs: test-macos-shard` and `if: always()` that prints each shard's result, fails unless `needs.test-macos-shard.result` is `success`, then runs `ci-shard-gate.sh`.
- **R7.** `[PR1]` Each shard uploads its file list as `test-macos-shard-<i>` on every run, and its full log as `test-macos-make-test-log-<i>` on failure or cancel.
- **R8.** `[PR1]` `tests/bats-weights.tsv` is committed with one line per `.bats` file, and `make bats-weights` regenerates it without being a prerequisite of `test`.
- **R9.** `[PR1]` `CLAUDE.md` describes the shard job and gate, the local repro command, the single `always()` exception, both jobs' timeouts, and the weights table.
- **R10.** `[PR1]` ADR-0053 exists, is indexed, and ADR-0037's status notes the partial supersession.
- **V1.** Over the first 10 PR runs after merge, at least one of them in a Monday Renovate window, p90 of `test-macos` gate completion minus the run's creation time (queue included) is at most 10 min. Otherwise, open a follow-up to move to 4 shards or to Phase 2 (self-hosted).
- **V2.** In a CI run, the three shards' `Run tests` step durations are within 3 min of each other, or `BATS_SHARD_HANDICAP` and the weights table are re-tuned from them.
- **N1.** No self-hosted runner and no new secret or token.
- **N2.** No change to branch protection's required checks or to `auto-merge`'s `needs:` list.
- **N3.** No change to the Linux `test`, `bash-coverage` or `powershell` jobs.
- **N4.** No change to `JOBS` or to the bats flags within a shard.
- **N5.** No change to what any existing test asserts; speed-ups to individual tests are separate changes.

## Multi-Lens Review

Reviewed at commit: `faa2f993` (Step 7 self-review commit, before Step 8 dispatch)

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

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.
