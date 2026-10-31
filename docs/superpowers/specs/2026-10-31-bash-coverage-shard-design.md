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

Three additions, plus one change to every traced run: its bats arguments gain
`--print-output-on-failure`, as `make test`'s `BATS_FLAGS` already do. Without it a red traced run
records only test names, and once the untraced `test` job is gone nothing else records what a failing
test saw (the existing Backlog row "`run-bash-coverage.sh` prints only the names of failing tests").
The existing modes are otherwise unchanged.

- **`--files <list>`:** the traced run's bats arguments are the listed paths instead of
  `--recursive tests/`. `--print-bats-args --files <list>` prints them. A missing, unreadable or empty
  list, a blank line or a CR in it, and a listed path that does not exist each exit 2 with a message
  naming it.
- **`--trace-only <dir>`:** after the traced bats run the script first writes `<dir>/bats_run.log`
  (the TAP log), green or red. Only then does `_check_red_suite` run: a red run exits 1 with the log in
  place. On a green run it writes `<dir>/bash_trace.txt` (the run's trace, `LC_ALL=C sort -u`), prints
  the trace's line count, and exits 0 without scoring. An empty trace exits 1, as today.
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
    `overwrite: true`. It exists on a red run because `--trace-only` writes the log before the red
    check.
- **`test`** (the gate):
  - `runs-on: ubuntu-latest`, `needs: test-shard`, `if: always()`, `timeout-minutes: 10`,
    `permissions: contents: write` (the badge push).
  - Fails unless `needs.test-shard.result` is `success`.
  - Checks out, downloads `test-shard-${{ github.run_attempt }}-*` with `merge-multiple: true`
    into `cov-shards`, runs `bash scripts/ci-shard-gate.sh --with-traces cov-shards`, then
    `bash scripts/run-bash-coverage.sh --score cov-shards/shard-*.trace`. It enforces the 91% floor with
    today's step and publishes the badge with today's step.
- Today's untraced **`test`** job and the single **`bash-coverage`** job are deleted, and with them the
  ≥ 840 count floor. Per-shard executed = declared plus the gate's coverage check prove more: every file
  ran, and every test in it. The badge keeps its `bash coverage` label and `coverage-data` branch.
- `auto-merge`'s `needs:` drops `bash-coverage` and keeps `test`. Branch protection's required checks drop
  `bash-coverage`; that is a repository setting, changed by the operator at merge (see Rollout).

### `scripts/ci-shard-gate.sh`

Without a flag it reads `<dir>/shard-*.files` and ignores other files, as today. With `--with-traces` it
also requires, before its coverage and disjointness checks, exactly one non-empty `shard-<i>.trace` for
each `shard-<i>.files` and no trace without a list, and names any shard that breaks this (exit 1).

Without that pairing, a shard whose trace is missing still uploads its list (`if-no-files-found: error`
fires only when no file matches), `--score` never sees the missing trace as an argument, and the gate
fails only because of how many lines that shard happens to contribute. Measured at `3063a29a`: real
32 / 28 / 30 lists plus one empty `shard-1.trace` and no others gave `PASS 90 files across 3 lists`.

### Pre-push

Both `make test` calls in `scripts/pre-push` (the in-place run and the clean-checkout run) run as
`env -u MAKEFLAGS -u MFLAGS -u MAKELEVEL -u BATS_FILES_FROM make ...`. `Makefile:1` re-adds
`--no-print-directory`, so nothing the hook relies on is lost.

`BATS_FILES_FROM` reaches make two ways, and stripping only the variable closes one. Make also reads
assignments and flags from an exported `MAKEFLAGS`. Measured at `3063a29a`:
- `env -u BATS_FILES_FROM MAKEFLAGS="BATS_FILES_FROM=<one-file list>" make -n test-bats` narrows to that
  one file.
- `MAKEFLAGS=e` with `BATS_RAN_FILES` or `BATS_PARALLEL_RAN` exported narrows the same way, because `-e`
  lets the environment beat `:=`.

The realistic trigger is a push run from inside a recipe started as `make BATS_FILES_FROM=x ...`,
since command-line variables ride `MAKEFLAGS`. `JOBS` changes parallelism, not the file set.

`tests/scripts/pre_push.bats` mocks `make` itself, so a test cannot see an expanded file list. Two cases
assert the mock's recorded environment instead:
- `BATS_FILES_FROM` exported: absent from the mock's environment.
- `MAKEFLAGS=BATS_FILES_FROM=<list>` exported: `MAKEFLAGS` absent from the mock's environment.

The wider rule (run `make test` with an explicit allowlist of variables) stays a Backlog row.

### Rollout

Branch protection lists `bash-coverage` as required (live: `test`, `lint-macos`, `powershell`,
`secret-scan`, `test-macos`, `bash-coverage`; `strict: false`). Once `ci.yml` has no `bash-coverage` job,
a PR waits forever on a check that never reports. And this PR's own `auto-merge` runs
`gh pr merge --squash` as soon as its `needs:` are green, which branch protection refuses while
`bash-coverage` is still required. So the order is:

1. The PR is opened as a draft. The headroom proof runs on it (below).
2. After the proof, and before the final CI run, the operator removes `bash-coverage` from the required
   checks with the `gh api` call the PR body carries. Then the PR is marked ready, the final run goes
   green, and `auto-merge` merges it.
3. After merge, every open PR is rebased or re-run. Their old runs carry an untraced `test` that reads
   green, and with `strict: false` a hand merge through the UI would skip the coverage gate.

If the PR is reverted, `bash-coverage` returns to the required list the same way.

### Headroom proof (draft PR, before merge)

CI coverage sits 26 to 34 lines above the floor (6433 / 7031 = 91.49% on run 41240902996), and the
2026-10-17 spec measured up to 160 timing-dependent lines. The one-run equality on `claude` does not
settle the 4-vCPU CI case. So while the PR is a draft, `ci.yml` carries a temporary `test-full-trace`
job: today's single traced run on the same SHA, writing its `sort -u` trace as an artifact. A temporary
gate step compares it with the shard union and prints the line diff by file.

Over three CI runs of the draft, the shard union must score at least 91% each time, and its covered
count must fall within the full job's own run-to-run spread over those same runs. The temporary job and
step are deleted before the PR is marked ready, and the PR body records the three runs' figures.

### Docs

- **ADR-0054:** single Linux gate, trace merge, and why the untraced run went. Partly supersedes
  ADR-0037's job list. It records an accepted gap (operator, 2026-10-31): CI no longer runs the Linux
  bats suite untraced. The tracer runs `set -x` and sets `PS4` and `BASH_XTRACEFD` in every bash, and no
  collision with it exists in `lib/` or `scripts/` today. The pre-push hook still runs the suite
  untraced on `claude` for the operator's and agents' pushes; bot PRs never run pre-push.
- **`CLAUDE.md`:**
  - The CI section's `test` and `bash-coverage` bullets are replaced by `test-shard` and the `test`
    gate.
  - The runner list and the timeouts list are updated (`test-shard` 30, `test` 10; `bash-coverage` removed).
  - `auto-merge`'s `needs:` list is updated.
  - The Coverage > Bash section names `--files`, `--trace-only`, `--score` and `ci-shard-gate.sh --with-traces`.
  - Re-run all jobs, never failed-only, now applies to the Linux gate too.
- **`README.md`:** the CI job list.
- **Backlog:** the env-var row is narrowed to the allowlist follow-up. The "re-size the 60-minute
  `bash-coverage` cap" row is closed, because that job no longer exists. The "prints only the names of
  failing tests" row is closed by `--print-output-on-failure`.

## Testing

TDD, bats. Every success case also asserts a non-empty result.

- **`run-bash-coverage.sh`** (its existing bats file):
  - `--print-bats-args --files <list>` prints exactly the listed paths.
  - Each `--files` error exits 2 with a message naming its input.
  - A `--trace-only` run over a two-file fixture writes a sorted unique trace and a log, and does not
    print `Overall bash coverage`.
  - A red `--trace-only` run exits 1 and leaves `<dir>/bats_run.log` holding the failing test's own
    output (proves both the log-before-check order and `--print-output-on-failure`).
  - `--score` over two fixture traces equals `--score` over their concatenation, which proves union
    semantics. A scored fixture yields a specific non-zero `TOTAL`, not just a verdict.
  - `--score` with a missing trace exits 2.
  - An environment-leak case: with `--files` given, a fixture test that runs the script records that it
    ran (a positive control) and that no list-carrying variable reached it.
- **Makefile** (`tests/makefile_shard_list.bats`, stubbed `bats`/`bash`):
  - `make test` runs `test-prereqs` before `test-bats`.
  - `make bash-coverage` with `BATS_FILES_FROM` set passes `--files <path>` on the script's command line,
    and the script's environment has no `BATS_FILES_FROM`.
  - Unset, the argv is today's.
- **`ci-shard-gate.sh`:** without a flag, a directory holding `shard-*.files` and `shard-*.trace`
  passes on the lists alone. With `--with-traces`: a missing trace, an empty trace and a trace with no
  list each fail naming the shard; a complete pairing passes.
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
- **Pre-push:** the two recorded-environment cases above.

## Requirements

- **R1.** `[PR1]` `make test` runs `test-prereqs` (lint, check-lock, check-requirements-ci, test-python, check-claude-md-budget) then `test-bats`, and `make test-prereqs` runs those five without bats.
- **R2.** `[PR1]` `scripts/run-bash-coverage.sh --files <list>` traces exactly the listed `.bats` paths and exits 2, naming the input, on a missing, unreadable, empty, blank-line, CR-bearing or nonexistent-path list; with no `--files` the bats arguments are unchanged.
- **R3.** `[PR1]` Every traced bats run passes `--print-output-on-failure`; `--trace-only <dir>` writes the bats log before the red-suite check on every run, writes a `LC_ALL=C sort -u` trace only after a green run, never scores, and exits 1 on a red run with the log in place.
- **R4.** `[PR1]` `--score <trace>...` scores the union of the given traces with the existing per-file loop and prints `Overall bash coverage: N%`; the result for several traces equals the result for their concatenation; a missing or empty trace exits 2.
- **R5.** `[PR1]` `make bash-coverage` passes `BATS_FILES_FROM` to the script only as `--files <path>` on the command line (and `--trace-only` when `COVERAGE_TRACE_DIR` is set), never through the script's environment, and behaves as today when it is unset.
- **R6.** `[PR1]` `ci.yml` has a `test-shard` matrix over `[1, 2, 3]` with `fail-fast: false` in which only shard 1 runs `make test-prereqs`, each leg checks executed = declared with `ci-suite-report.sh --files` and uploads its list and trace only on success under `test-shard-<run_attempt>-<i>`; and a `test` gate with `if: always()` that fails unless the shard result is `success`, runs `ci-shard-gate.sh --with-traces` and `run-bash-coverage.sh --score` over this attempt's artifacts, enforces 91% and publishes the badge.
- **R7.** `[PR1]` `ci.yml` has no `bash-coverage` job and no untraced `test` job, `auto-merge`'s `needs:` lists `test` but not `bash-coverage`, and only the `test` gate job has `contents: write`.
- **R8.** `[PR1]` Both `make test` calls in `scripts/pre-push` run with `MAKEFLAGS`, `MFLAGS`, `MAKELEVEL` and `BATS_FILES_FROM` removed from the environment, and tests show neither an exported `BATS_FILES_FROM` nor an exported `MAKEFLAGS` reaches make.
- **R9.** `[PR1]` ADR-0054 exists and is indexed; `CLAUDE.md`, `README.md` and the Backlog are updated as listed under Docs.
- **R10.** `[PR1]` `ci-shard-gate.sh --with-traces <dir>` fails, naming the shard, unless every `shard-<i>.files` has exactly one non-empty `shard-<i>.trace` and no trace lacks a list; without the flag its behaviour is unchanged.
- **V1.** On the draft PR, over three CI runs, the shard union scores at least 91% each time and its covered count falls within the temporary full traced job's own spread over those runs; the PR body records the figures and the per-file line diffs.
- **V2.** Over the first 5 PR runs after merge, the `test` gate completes before the `test-macos` gate in at least 4.
- **V3.** Before the PR's final CI run the operator removes `bash-coverage` from branch protection's required checks (the PR body records the call), and after merge every open PR is rebased or re-run.
- **N1.** No change to the 91% floor or to how a file's covered and coverable lines are counted.
- **N2.** No change to the macOS jobs or to `bats-shard.sh`'s packing.
- **N3.** No new secret, token or self-hosted runner.
- **N4.** No change to what any existing test asserts, except retargeting tests that name the untraced `test` job's steps or the deleted `bash-coverage` job, and adding `test-prereqs` to `ALLOWED_TEST_PREREQS`.

## Multi-Lens Review

Round 1 reviewed at commit: `3063a29a` (Step 7 self-review commit, before Step 8 dispatch)

### Goal-Fit

Finding: No issues. Premises verified on run 41240902996: the Linux job is the PR long pole
(`bash-coverage` ended 21:08:12, the `test-macos` gate 21:01:13); the untraced `test` job's only unique
work is ~44 s of prerequisites; pre-push still runs untraced Linux `make test` on `claude`; projected gate
time 7-8 min against macOS 9. Every new output has a consumer (traces -> `--score` -> floor and badge;
logs -> `ci-suite-report.sh`; lists -> `ci-shard-gate.sh`). The environment-leak test passed with nothing
measured.
Assumption: the three CI shards' merged trace scores at least 91%. CI headroom is 34 lines (6433 / 7031)
against up to 160 timing-dependent lines; confirm with repeated CI runs comparing the union to a full run.
Disposition: Addressed (operator, 2026-10-31): headroom proof on the draft PR (Design, V1); leak test
gains a positive control.

### Ergonomics

Finding: a red shard leaves nothing to read. `--trace-only` copied the log only after a green run, so the
failure upload was empty, and the traced run passes no `--print-output-on-failure`, which `make test` has.
The pre-push test could not work as written, because `pre_push.bats` mocks `make`.
Assumption: same as Goal-Fit (stability of the split on 4-vCPU runners).
Disposition: Addressed, revision presented to the operator 2026-10-31: log written before the red check;
`--print-output-on-failure` on every traced run (closes a Backlog row); pre-push cases assert the mock's
environment.

### Risk

Finding: no green-with-tests-skipped path. Defects: (1) pre-push `env -u BATS_FILES_FROM` misses an
exported `MAKEFLAGS` carrying the assignment or `-e` (measured narrowing); (2) the gate never pairs lists
with traces (real lists plus one empty trace passed `ci-shard-gate.sh`); (3) CI loses its untraced Linux
run, and bot PRs never run pre-push; (4) this PR's own auto-merge is refused while `bash-coverage` is still
required, and `strict: false` lets an old open PR merge by hand without the coverage gate; (5) the
red-run log gap above.
Assumption: the merged trace equals a full CI run's within the 26-line margin; percentages hide tens of
lines, so compare unique traces.
Disposition: Addressed, revision presented to the operator 2026-10-31: (1) strip `MAKEFLAGS`, `MFLAGS`,
`MAKELEVEL`; (2) `ci-shard-gate.sh --with-traces` (R10); (3) accepted and recorded in ADR-0054 (operator,
2026-10-31); (4) required-check removal before the final run, open PRs rebased after merge; (5) as
Ergonomics.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.
