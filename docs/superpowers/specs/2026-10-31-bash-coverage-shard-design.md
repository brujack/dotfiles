# Shard the traced Linux suite as the single Linux gate, `test`

- **Date:** 2026-10-31
- **Follows:** dotfiles#411 (`test-macos` shard, ADR-0053, `docs/superpowers/specs/2026-10-30-test-macos-shard-design.md`)
- **Backlog rows closed:** "The pre-push hook's `make test` honours make-input env vars" (P2 CI), for `BATS_FILES_FROM` only.

## Problem

After dotfiles#411 the `test-macos` gate finishes in about 9 minutes. The Linux jobs are now the long pole.
On #411's own run (41240902996) `test` took 11m02s and `bash-coverage` 15m57s, and a PR waits for the
slowest required check.

Both Linux jobs run the same 3696 bats tests. `bash-coverage` runs them under the `BASH_ENV`/PS4
tracer and refuses to score a red run (`_check_red_suite`), so it already proves the suite passes on
Linux. The untraced `test` job adds three things:

1. `make test`'s prerequisites on Linux: `lint`, `check-lock`, `check-requirements-ci`, `test-python`
   and `check-claude-md-budget`. `bash-coverage` runs only bats.
2. The `Tool versions` step (locale, `sort`/`comm` resolution).
3. The "test count ≥ 840" floor.

Since #411, macOS shard 1 runs `make test`, so (1) also runs on macOS. It does not run on Linux anywhere
else.

## Measurements

| What                    | Population                                                                               | Result                                                                                                                                        |
| ----------------------- | ---------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| CI job durations        | run 41240902996 (#411), one sample                                                       | `test` 11m02s, `bash-coverage` 15m57s, macOS shards 6m09s / 8m46s / 5m30s, gate 7s                                                            |
| CI coverage             | same run                                                                                 | 91% (the floor)                                                                                                                               |
| Full traced run         | `claude` (48 threads), `origin/master` `056494d8`, scratch copy, `COVERAGE_BATS_JOBS=24` | 223 s, rc 0, 6402 / 7006 = 91%                                                                                                                |
| Three-shard traced runs | same tree, lists from `bats-shard.sh i 3` (32 / 28 / 30 files), each run alone           | 95 s / 91 s / 83 s, all rc 0                                                                                                                  |
| Unique traced lines     | same four runs, `LC_ALL=C sort -u` of each `bash_trace.txt`                              | full 7108; shards 3983 / 3441 / 4317; their union 7108, byte-identical to the full run (`cmp`)                                                |
| Raw trace size          | full run                                                                                 | 445,810,278 bytes for 7108 unique lines                                                                                                       |
| Environment leak        | first shard-1 attempt, list passed via an exported variable                              | red: `not ok 162 run-bash-coverage.sh --print-bats-args with a valid job count is parallel` (the test ran the script, which saw the variable) |

Scoring is a pure function of the unique trace: `_file_coverage_report` reads per-file line sets, and
the denominator is the static heuristic unioned with traced lines. So equal unique traces give equal
figures. The table shows equality on one run on one machine. The 2026-10-17 parallel-coverage spec
measured run-to-run variation from timing-dependent branches (160 more filtered lines under `--jobs`),
and that variation exists in either layout. V1 checks it in CI.

## Alternatives considered

- **Coverage off the PR path.** PRs would run a sharded untraced `test` and coverage would run only on
  master or nightly. It is fastest, but nothing would block a coverage drop at merge, which reverses the
  91% gate's role. Rejected by the operator.
- **Shard by source file.** Each leg traces the whole suite and scores part of the instrumented set. It
  gives no speed-up, because the traced run is the cost.
- **Keep `test` and shard it too.** It doubles Linux runner time for a result `bash-coverage` already
  proves. Rejected by the operator: `bash-coverage` becomes the Linux gate.
- **Four shards.** About 5 minutes, but macOS (~9 minutes) still sets the PR's wall-clock, and each leg
  runs fewer tests at once, which moves the timing-dependent lines further.

## Decision

Three Linux shards (operator, 2026-10-31). Shard 1 also runs `make test`'s prerequisites (operator). The
Linux gate is named `test` (operator, 2026-10-31): it keeps the required-check name, so branch protection
drops only `bash-coverage`. Its shard job is `test-shard`. The untraced `test` job and the single
`bash-coverage` job are both replaced.

## Design

### Makefile

- **`test-prereqs`:** a new phony target whose prerequisites are today's `test` prerequisites (`lint`
  `check-lock` `check-requirements-ci` `test-python` `check-claude-md-budget`). `test` becomes
  `test: test-prereqs test-bats`, so `make test` runs the same steps in the same serial order as today.
  `tests/scripts/docs_inert_premise.bats` gains `test-prereqs` in `ALLOWED_TEST_PREREQS`; it reads no
  tracked `.md`.
- **`bash-coverage`:** with `BATS_FILES_FROM` empty, it behaves as today. With it set, the recipe passes
  the list to the script as an argument, `--files $(BATS_FILES_FROM)`, plus `--trace-only <dir>` when
  `COVERAGE_TRACE_DIR` is set. The variable stays `unexport`ed, so neither the script's environment nor
  any test sees it. The empty and missing list refusals from `test-bats` apply here too.

### `scripts/run-bash-coverage.sh`

Three additions. The existing modes and today's default run are unchanged.

- **`--files <list>`:** the traced run's bats arguments are the listed paths instead of
  `--recursive tests/`. `--print-bats-args --files <list>` prints them. A missing, unreadable or empty
  list, a blank line or a CR in it, and a listed path that does not exist each exit 2 with a message
  naming it.
- **`--trace-only <dir>`:** after the traced bats run, and only when it is green, the script writes
  `<dir>/bash_trace.txt` (the run's trace, `LC_ALL=C sort -u`) and `<dir>/bats_run.log` (the TAP log),
  prints the trace's line count, and exits 0 without scoring. A red run still exits 1 through
  `_check_red_suite`. An empty trace exits 1, as today.
- **`--score <trace>...`:** no bats run. The traces are unioned (`LC_ALL=C sort -u`) and passed to the
  existing scoring loop, which prints the same per-file table, `TOTAL`, `Overall bash coverage: N%` and
  the heuristic-disagreement list as a full run. `--json <path>` works as today. A missing or empty
  trace argument exits 2.

None of the three reads its list or traces from the environment. The measured leak (`not ok 162`) is the
reason.

### CI (`.github/workflows/ci.yml`)

- **`test-shard`:**
  - `strategy.fail-fast: false`, matrix `shard: [1, 2, 3]`, `runs-on: ubuntu-latest`,
    `timeout-minutes: 30`, `permissions: contents: read`.
  - Install steps as in today's `bash-coverage`. The `Tool versions` step moves here from today's `test`.
  - `bash scripts/bats-shard.sh "${{ matrix.shard }}" "${{ strategy.job-total }}" > "shard-${{ matrix.shard }}.files"`
    in a bash step.
  - Shard 1 only: `make test-prereqs`.
  - `make bash-coverage` with step `env:` `BATS_FILES_FROM: shard-${{ matrix.shard }}.files` and
    `COVERAGE_TRACE_DIR: shard-out`. The list is passed on the command line by the Makefile recipe, not
    by the workflow.
  - `bash scripts/ci-suite-report.sh shard-out/bats_run.log --files "shard-${{ matrix.shard }}.files"`.
  - On success only: upload `test-shard-${{ github.run_attempt }}-${{ matrix.shard }}` holding
    `shard-<i>.files` and `shard-out/bash_trace.txt` renamed `shard-<i>.trace`, with
    `if-no-files-found: error`.
  - On failure or cancel: upload `shard-out/bats_run.log` as `test-shard-log-<i>` with
    `overwrite: true`.
- **`test`** (the gate):
  - `runs-on: ubuntu-latest`, `needs: test-shard`, `if: always()`, `timeout-minutes: 10`,
    `permissions: contents: write` (the badge push).
  - Fails unless `needs.test-shard.result` is `success`.
  - Checks out, downloads `test-shard-${{ github.run_attempt }}-*` with `merge-multiple: true`
    into `cov-shards`, runs `bash scripts/ci-shard-gate.sh cov-shards`, then
    `bash scripts/run-bash-coverage.sh --score cov-shards/shard-*.trace`. It enforces the 91% floor with
    today's step and publishes the badge with today's step.
- Today's untraced **`test`** job and the single **`bash-coverage`** job are deleted, and with them the
  ≥ 840 count floor. Per-shard executed = declared plus the gate's coverage check prove more: every file
  ran, and every test in it. The badge keeps its `bash coverage` label and `coverage-data` branch.
- `auto-merge`'s `needs:` drops `bash-coverage` and keeps `test`. Branch protection's required checks drop
  `bash-coverage`; that is a repository setting, changed by the operator at merge (see Rollout).

### `scripts/ci-shard-gate.sh`

It reads `<dir>/shard-*.files` and ignores other files, so the traces sitting in the same directory do
not disturb it. A test pins that.

### Pre-push

Both `make test` calls in `scripts/pre-push` (the in-place run and the clean-checkout run) run as
`env -u BATS_FILES_FROM make ...`. A `pre_push.bats` case exports a one-file `BATS_FILES_FROM` and
asserts the hook's `make test` still names the full file list (stubbed `make`/`bats`).
`BATS_FILES_FROM` is the only Makefile input that narrows the bats set: `BATS_SERIAL_FILES` and
`HAVE_PARALLEL` are assigned with `:=`, which overrides the environment, and `JOBS` changes parallelism,
not the file set. The wider rule (run `make test` with an explicit allowlist of variables) stays a
Backlog row.

### Rollout

Branch protection lists `bash-coverage` as required. Once `ci.yml` no longer has a `bash-coverage` job,
a PR waits forever on a check that never reports. `test` stays required and is now the gate. So the
order is:

1. The operator removes `bash-coverage` from the required checks just before merging this PR.
2. Merge.

The PR body carries the exact `gh api` call. If the PR is reverted, `bash-coverage` returns to the
required list the same way.

### Docs

- **ADR-0054:** single Linux gate, trace merge, and why `test` went. Partly supersedes ADR-0037's job
  list.
- **`CLAUDE.md`:**
  - The CI section's `test` and `bash-coverage` bullets are replaced by `test-shard` and the `test`
    gate.
  - The runner list and the timeouts list are updated (`test-shard` 30, `test` 10; `bash-coverage` removed).
  - `auto-merge`'s `needs:` list is updated.
  - The Coverage > Bash section names `--files`, `--trace-only` and `--score`.
- **`README.md`:** the CI job list.
- **Backlog:** the env-var row is narrowed to the allowlist follow-up. The "re-size the 60-minute
  `bash-coverage` cap" row is closed, because that job no longer exists.

## Testing

TDD, bats. Every success case also asserts a non-empty result.

- **`run-bash-coverage.sh`** (its existing bats file):
  - `--print-bats-args --files <list>` prints exactly the listed paths.
  - Each `--files` error exits 2 with a message naming its input.
  - A `--trace-only` run over a two-file fixture writes a sorted unique trace and a log, and does not
    print `Overall bash coverage`.
  - A red `--trace-only` run exits 1.
  - `--score` over two fixture traces equals `--score` over their concatenation, which proves union
    semantics. A scored fixture yields a specific non-zero `TOTAL`, not just a verdict.
  - `--score` with a missing trace exits 2.
  - An environment-leak case: with `--files` given, a test running the script sees no list-carrying
    variable.
- **Makefile** (`tests/makefile_shard_list.bats`, stubbed `bats`/`bash`):
  - `make test` runs `test-prereqs` before `test-bats`.
  - `make bash-coverage` with `BATS_FILES_FROM` set passes `--files <path>` on the script's command line,
    and the script's environment has no `BATS_FILES_FROM`.
  - Unset, the argv is today's.
- **`ci-shard-gate.sh`:** a directory holding `shard-*.files` and `shard-*.trace` passes on the lists
  alone.
- **CI shape** (new `tests/scripts/ci_bash_coverage_shard.bats`, per-job raw-text parse as in #411):
  - No `bash-coverage` job, `auto-merge` `needs:` lacks it and still lists `test`, and job `test` is the gate (`needs: test-shard`).
  - The shard matrix is `[1, 2, 3]` with `fail-fast: false`.
  - `make test-prereqs` runs only on shard 1.
  - `BATS_FILES_FROM` is set only in step `env:`.
  - The upload is success-only and attempt-scoped.
  - The gate's `if: always()` and `needs` result check, plus the download pattern and `merge-multiple`.
  - The gate is the only job with `contents: write`.
  - `always()` appears exactly twice outside comments, once per gate job.
  - Every `uses:` is SHA-pinned.
  - Existing CI-shape tests that name the untraced `test` job's steps or the `bash-coverage` job are retargeted.
- **Pre-push:** the exported-`BATS_FILES_FROM` case above.

## Requirements

- **R1.** `[PR1]` `make test` runs `test-prereqs` (lint, check-lock, check-requirements-ci, test-python, check-claude-md-budget) then `test-bats`, and `make test-prereqs` runs those five without bats.
- **R2.** `[PR1]` `scripts/run-bash-coverage.sh --files <list>` traces exactly the listed `.bats` paths and exits 2, naming the input, on a missing, unreadable, empty, blank-line, CR-bearing or nonexistent-path list; with no `--files` the bats arguments are unchanged.
- **R3.** `[PR1]` `--trace-only <dir>` writes a `LC_ALL=C sort -u` trace and the bats log after a green run and does not score; a red run exits 1.
- **R4.** `[PR1]` `--score <trace>...` scores the union of the given traces with the existing per-file loop and prints `Overall bash coverage: N%`; the result for several traces equals the result for their concatenation; a missing or empty trace exits 2.
- **R5.** `[PR1]` `make bash-coverage` passes `BATS_FILES_FROM` to the script only as `--files <path>` on the command line (and `--trace-only` when `COVERAGE_TRACE_DIR` is set), never through the script's environment, and behaves as today when it is unset.
- **R6.** `[PR1]` `ci.yml` has a `test-shard` matrix over `[1, 2, 3]` with `fail-fast: false` in which only shard 1 runs `make test-prereqs`, each leg checks executed = declared with `ci-suite-report.sh --files` and uploads its list and trace only on success under `test-shard-<run_attempt>-<i>`; and a `test` gate with `if: always()` that fails unless the shard result is `success`, runs `ci-shard-gate.sh` and `run-bash-coverage.sh --score` over this attempt's artifacts, enforces 91% and publishes the badge.
- **R7.** `[PR1]` `ci.yml` has no `bash-coverage` job and no untraced `test` job, `auto-merge`'s `needs:` lists `test` but not `bash-coverage`, and only the `test` gate job has `contents: write`.
- **R8.** `[PR1]` Both `make test` calls in `scripts/pre-push` run with `BATS_FILES_FROM` removed from the environment, and a test shows an exported value does not narrow the run.
- **R9.** `[PR1]` ADR-0054 exists and is indexed; `CLAUDE.md`, `README.md` and the Backlog are updated as listed under Docs.
- **V1.** On the PR, the gate's merged coverage equals the master figure from the same week, or any delta is named in the PR body by file and line as timing-dependent.
- **V2.** Over the first 5 PR runs after merge, the `test` gate completes before the `test-macos` gate in at least 4.
- **V3.** The operator removes `bash-coverage` from branch protection's required checks at merge, and the PR body records the call used.
- **N1.** No change to the 91% floor or to how a file's covered and coverable lines are counted.
- **N2.** No change to the macOS jobs or to `bats-shard.sh`'s packing.
- **N3.** No new secret, token or self-hosted runner.
- **N4.** No change to what any existing test asserts, except retargeting tests that name the untraced `test` job's steps or the deleted `bash-coverage` job, and adding `test-prereqs` to `ALLOWED_TEST_PREREQS`.
