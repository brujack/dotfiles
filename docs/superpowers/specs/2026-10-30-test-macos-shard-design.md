# Shard `test-macos` across hosted macOS runners

- **Date:** 2026-10-30
- **Backlog row:** "`test-macos` takes 17-29 min on GitHub's 3-vCPU macOS runner, against a 30-min `timeout-minutes`" (P1 — performance)
- **Designed with:** the ansible session (cross-session, 2026-10-30), which priced a self-hosted Studio runner against this approach.

## Problem

`test-macos` runs the whole suite as one job on `macos-latest` (3 vCPU). The last 14 successful
runs (`gh run list --workflow ci.yml`, run 40783669811 through 40998654932) took 17, 20, 20, 20,
21, 22, 22, 24, 25, 25, 26, 26, 27 and 29 min against `timeout-minutes: 30`, so a normal run sits a
minute from its cap. The job is a required check and in `auto-merge`'s `needs:`, so every PR waits
on it. On dotfiles#408 it took six attempts to merge one PR.

## Measurements

| What                                          | Population                                                                                            | Result                                                                                                       |
| --------------------------------------------- | ----------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| Hosted `test-macos` duration                  | 14 successful runs, PR/master, 2026-10-29/30                                                          | 17-29 min                                                                                                    |
| Linux suite under `taskset` (ansible session) | `claude`, fresh clone, one run each                                                                   | 3 CPUs 360 s, 12 CPUs 140 s, 3606 ok                                                                         |
| Studio full suite (this session)              | Studio, macOS 27.2, fresh clone of dotfiles#408's branch, `env -i`, `/usr/bin/make` 3.81, bats 1.14.0 | 3613/3613 in ~5 min                                                                                          |
| Suite composition                             | this tree, `find tests -name '*.bats'`                                                                | 84 files, 3613 `@test`; largest `tests/setup_env/linux_ubuntu.bats` 516 (14%); `tests/setup_env/` holds 2827 |

The suite scales with cores (2.6x for 4x on Linux), and the hosted mac is about 4x slower per core
than 3 Linux cores. Splitting the files across parallel hosted jobs therefore divides wall-clock
roughly by the shard count, plus per-job setup (~1.5 min: checkout, `brew install`, pinned
shellcheck and uv).

## Alternatives considered

- **Self-hosted runner on the Studio** (ansible session's design): ~5 min, but dotfiles is public
  with 2 forks. `pull_request` runs the PR head's workflow, so a fork can retarget `runs-on`.
  Personal-account repos have no runner groups. The only controls are an `all_external_contributors`
  approval policy and an ephemeral VM, plus a non-admin runner user, `pf` egress rules, a
  route job with a PAT, JIT registration and a queue watchdog. It also moves the suite onto
  20 cores, which would hide the starved-runner condition under which dotfiles#408 stalled twice.
  Kept as Phase 2 if this spec misses its target.
- **Split by directory:** `tests/setup_env/` alone is 78% of the tests.
- **Round-robin by sorted index:** balance depends on sort order. Largest-first by test count costs
  the same and balances by construction.

## Decision

Three shards (operator, 2026-10-30). GitHub allows 5 concurrent macOS jobs per account. With
`lint-macos`, one PR uses 4 of them and leaves room for a second PR's `lint-macos`. Estimated
wall-clock is ~8-11 min. The shard count is a single constant, so moving to 4 is one change.

## Design

### Shard selection: `scripts/bats-shard.sh`

`bats-shard.sh <index> <count>` prints, one per line, the `.bats` files shard `<index>` (1-based) of
`<count>` runs.

1. Read `find tests -name '*.bats'`, sorted with `LC_ALL=C sort`. This is the same population as
   the Makefile's `BATS_ALL_FILES`, minus `BATS_SERIAL_FILES`, which is passed in as an environment
   variable (`BATS_SHARD_EXCLUDE`, space-separated) so the script has one input list.
2. Weight each file by its count of lines matching `^@test`.
3. Visit files from heaviest to lightest (ties broken by path, ascending), and assign each to the
   shard with the lowest running weight (ties broken by lowest index). Shard 1 starts with a
   handicap weight `BATS_SHARD_HANDICAP` (default 150), because it also runs lint, the lock
   checks and the Python suite.
4. Exit 2 with a message on: a non-integer or out-of-range argument, `<count>` below 1, or an
   empty file list.

The output is a pure function of the tree, so every caller recomputes the same split.

### Makefile

- A new `BATS_SHARD` variable, empty by default. When set to `i/N`, `BATS_PARALLEL_FILES` becomes
  `$(shell bash scripts/bats-shard.sh i N)` with the serial files excluded. When empty, everything
  is as today.
- The bats recipe moves from `test` into a new `test-bats` target. `test` becomes its current
  prerequisites plus `test-bats`, so `make test` behaves exactly as before.
- `BATS_SERIAL_FILES` (empty today) runs only when `BATS_SHARD` is empty or is `1/N`.
- A new `BATS_RAN_FILES` variable lists exactly the files this invocation runs: the shard's
  `BATS_PARALLEL_FILES`, plus `BATS_SERIAL_FILES` when `BATS_SHARD` is empty or `1/N`.
- The existing empty-list refusal applies to the shard's list too.

### `scripts/ci-suite-report.sh`

Gains `--files <listfile>`. In that mode the declared count is the `^@test` count over the listed
files, not over all of `tests/`, and the executed count must equal it. The existing two-argument
form is unchanged.

### `scripts/ci-shard-gate.sh`

`ci-shard-gate.sh <dir>` reads `<dir>/shard-<i>.files` and `<dir>/shard-<i>.executed` for every
shard present, and fails unless all of these hold:

1. **Coverage:** the union of the file lists equals an independent
   `find tests -name '*.bats' | LC_ALL=C sort`. It is computed in the gate, not by calling
   `bats-shard.sh`.
2. **Disjointness:** no file appears in two lists.
3. **Counts:** the sum of the executed counts equals the `^@test` total over the full list.
4. **Arity:** the number of shards present equals the expected count passed as `--expect <N>`.

Each failure prints which check failed and the offending files or counts.

### CI (`.github/workflows/ci.yml`)

- `test-macos-shard`:
  - `strategy.fail-fast: false`, matrix `shard: [1, 2, 3]`, `runs-on: macos-latest`,
    `timeout-minutes: 30`, `permissions: contents: read`.
  - The install steps are unchanged.
  - Shard 1 runs `make test BATS_SHARD=1/3`; shards 2 and 3 run `make test-bats BATS_SHARD=<i>/3`.
  - Each shard writes `make print-BATS_RAN_FILES` (with its `BATS_SHARD`) to
    `shard-<i>.files`, runs `ci-suite-report.sh --files`, and writes its executed count to
    `shard-<i>.executed`.
  - It uploads both as artifact `test-macos-shard-<i>`, always.
  - On failure or cancel it uploads `test-macos-make-test-log-<i>`.
- `test-macos` (the gate):
  - `runs-on: ubuntu-latest`, `needs: test-macos-shard`, `if: always()`, `timeout-minutes: 10`,
    `permissions: contents: read`.
  - It fails first if `needs.test-macos-shard.result` is anything other than `success`, which
    covers `failure`, `cancelled` and `skipped`.
  - It checks out the repo, downloads the `test-macos-shard-*` artifacts with
    `actions/download-artifact` pinned to a full commit SHA, and runs
    `ci-shard-gate.sh <dir> --expect 3`.
- The job name `test-macos`, branch protection's required checks, and `auto-merge`'s `needs:`
  list are unchanged.

### Docs

- `CLAUDE.md`, CI section:
  - Rewrite the `test-macos` bullet for the shard job plus gate.
  - Amend "Every job in `needs:` is a gate with no advisory tier (no `continue-on-error`, no
    `always()`)" to say there is no `continue-on-error`, and that the only `always()` is the
    `test-macos` aggregation gate, which fails on any shard result other than `success`.
  - The timeout list adds `test-macos-shard` 30 and `test-macos` 10.
- ADR-0053 records the sharded shape and the self-hosted alternative. It partly supersedes
  ADR-0037's single-job decision, and ADR-0037's status line notes that.
- The P1-performance backlog row is rewritten to point at this spec and the V1 measurement.

## Testing

TDD, bats, in `tests/scripts/`:

- `bats_shard.bats`:
  - For N in 1..4 over the real tree, the union of all shards equals the full list and they are
    disjoint.
  - Two runs give identical output.
  - For N = 3 over the real tree, the heaviest shard's weight, handicap excluded, is at most the
    lightest's plus the largest file's weight.
  - `N = 1` returns the full list.
  - `BATS_SHARD_EXCLUDE` removes a named file.
  - Bad arguments and an empty tree (a fixture root) exit 2.
- `ci_shard_gate.bats`, over fixture directories:
  - A correct 3-shard partition passes.
  - A missing file, an overlap, a count mismatch and an arity mismatch each fail, naming the check.
  - **Drop-one-file control:** start from the real 3-shard output, delete one line from one
    shard's list, and expect failure. This pins the coverage check, not the counts check.
- `ci_suite_report.bats` (new or extended): `--files` passes when executed equals declared over
  the list, fails when it is one short, and the two-argument form is unchanged.
- CI-shape tests:
  - The existing `ci_test_macos_log.bats` assertions move to `test-macos-shard`.
  - New assertions: the gate job has `if: always()` and references
    `needs.test-macos-shard.result`; the matrix has `fail-fast: false`; the matrix size equals the
    `N` in every `BATS_SHARD=<i>/N` and in `--expect`.
- `make test` locally stays green. `make test BATS_SHARD=2/3` runs only shard 2's files.

## Requirements

- **R1.** `[PR1]` `scripts/bats-shard.sh <i> <N>` prints shard `i` of `N`, assigning files heaviest-first by `^@test` count to the lightest shard, with shard 1 starting at `BATS_SHARD_HANDICAP` (default 150), and exits 2 on bad arguments or an empty list.
- **R2.** `[PR1]` For every N from 1 to 4, the shards' outputs over the real tree are disjoint and their union equals `find tests -name '*.bats' | LC_ALL=C sort` minus `BATS_SHARD_EXCLUDE`; `BATS_RAN_FILES` adds `BATS_SERIAL_FILES` to shard 1 only, so the shards' `BATS_RAN_FILES` partition the full list.
- **R3.** `[PR1]` With `BATS_SHARD` unset, `make test` runs the same prerequisites and the same bats file list as before this change; with `BATS_SHARD=i/N`, `make test-bats` runs only shard `i`'s files.
- **R4.** `[PR1]` `ci-suite-report.sh --files <list>` compares executed against the `^@test` count over the listed files only; the two-argument form is unchanged.
- **R5.** `[PR1]` `ci-shard-gate.sh` fails, naming the check, on a missing file, an overlapping file, an executed-count mismatch, or a shard-count mismatch, and passes on a correct partition; removing one line from one shard's list makes it fail.
- **R6.** `[PR1]` `ci.yml` runs `test-macos-shard` as a 3-way matrix with `fail-fast: false`, and a job named `test-macos` on `ubuntu-latest` with `needs: test-macos-shard`, `if: always()`, that fails unless `needs.test-macos-shard.result` is `success` and then runs `ci-shard-gate.sh --expect 3`.
- **R7.** `[PR1]` Each shard uploads its file list and executed count as `test-macos-shard-<i>` on every run, and its full log as `test-macos-make-test-log-<i>` on failure or cancel.
- **R8.** `[PR1]` `CLAUDE.md`'s CI section describes the shard job and gate, states the single `always()` exception, and lists both jobs' timeouts.
- **R9.** `[PR1]` ADR-0053 exists, is indexed, and ADR-0037's status notes the partial supersession.
- **V1.** Over the first 10 PR runs after merge, p90 of `test-macos` gate completion minus the run's creation time (queue included) is at most 10 min. Otherwise, open a follow-up to move to 4 shards or to Phase 2 (self-hosted).
- **V2.** A CI run's three shard durations are within 3 min of each other, or `BATS_SHARD_HANDICAP` is re-tuned from them.
- **N1.** No self-hosted runner and no new secret or token.
- **N2.** No change to branch protection's required checks or to `auto-merge`'s `needs:` list.
- **N3.** No change to the Linux `test`, `bash-coverage` or `powershell` jobs.
- **N4.** No change to `JOBS` or to the bats flags within a shard.
