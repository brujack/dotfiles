# Linux `test` Shard Implementation Plan

spec: docs/superpowers/specs/2026-10-31-bash-coverage-shard-design.md

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development (the local override) to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the untraced `test` job and the single `bash-coverage` job with a 3-leg `test-shard` traced matrix and an ubuntu `test` gate that unions the shard traces, enforces 91% and publishes the badge.

**Architecture:** `run-bash-coverage.sh` gains `--files`, `--trace-only` and `--score`; each CI leg traces its `bats-shard.sh` list (shard 1 also runs `make test-prereqs`) and uploads list plus deduplicated trace on success; the gate checks list/trace pairing and coverage with `ci-shard-gate.sh --with-traces`, then scores the union.

**Tech Stack:** bash, bats, GNU Make 4.x (Linux) and 3.81 (macOS shard 1 still runs `make test`), GitHub Actions.

## Global Constraints

- The spec is the authority; read its Design, Testing and Requirements before each task.
- No list, trace or directory reaches `run-bash-coverage.sh` through the environment: `BATS_FILES_FROM` and `COVERAGE_TRACE_DIR` are `unexport`ed and passed as arguments (measured leak: `not ok 162`).
- No change to the 91% floor or to how a file's covered/coverable lines are counted (N1); no change to the macOS jobs or `bats-shard.sh` (N2); no new secret, token or self-hosted runner (N3).
- No existing test changes what it asserts except retargeting tests that name the untraced `test` job's steps or the deleted `bash-coverage` job, and adding `test-prereqs` to `ALLOWED_TEST_PREREQS` (N4). Tests that read the literal `^test:` Makefile line (`tests/scripts/makefile_lint_scope.bats` "test still depends on both lint and test-python", `tests/setup_env/requirements_ci.bats` "make test depends on the drift check") must pass unmodified, so the `test:` line keeps naming its five prerequisites.
- `tests/scripts/unit.bats` "main run captures the bats argv before the FIFO exists" asserts exactly two `_out="$(_coverage_bats_args)" || exit 2` captures; keep it at two.
- Every bats/make gate command carries `< /dev/null`; a stdout-capturing `make -C` carries `--no-print-directory`.
- Shell standards per repo CLAUDE.md; every success-path test asserts a non-empty result.

## Verification

- Session: `make test` green (base 3696 plus new tests); `make bash-coverage` unchanged locally with no new variables set.
- CI on the draft PR: three `test-shard` legs green with executed = declared; the `test` gate prints `Overall bash coverage: N%` with N >= 91 and `ci-shard-gate: PASS`; the temporary headroom jobs' diff recorded in the PR body (V1).
- Suite duration on `claude` is under the 600 s Bash cap, so code tasks gate on `make test`.

---

### Task 1: `run-bash-coverage.sh --files` and `--print-output-on-failure`

```yaml-task
id: 1
description: Add --files <list> to run-bash-coverage.sh and pass --print-output-on-failure on every traced run, with tests
role: executor
model: sonnet
tdd: required
requirements: [R2, R3]
acceptance:
  - cmd: bats --jobs 8 tests/scripts/unit.bats < /dev/null
    exit_code: 0
  - cmd: make test < /dev/null
    exit_code: 0
max_retries: 3
files_touched: [scripts/run-bash-coverage.sh, tests/scripts/unit.bats]
depends_on: []
```

**Behaviour:** spec "`scripts/run-bash-coverage.sh`" `--files` bullet and the `--print-output-on-failure` paragraph. `_coverage_bats_args` gains `--print-output-on-failure` always, and the listed paths instead of `--recursive tests/` when `--files` is given (paths are repo-relative lines; resolve against `REPO_ROOT`). `--print-bats-args --files <list>` prints them. Every `--files` input error exits 2 naming its input (missing, unreadable, empty, blank line, CR, nonexistent listed path). Parse arguments so `--files` combines with `--print-bats-args` and with the main run; unknown flags still exit as today. Keep exactly two argv captures. Update the usage text (`-h`).

**Tests (unit.bats):** exact argv for a two-path list (both paths, `--print-output-on-failure`, no `--recursive`); each error case with message; default argv still has `--recursive` and now `--print-output-on-failure`; usage documents `--files`. Show one red against a mutant (e.g. ignore the list) and report it.

### Task 2: `--trace-only` and `--score`

```yaml-task
id: 2
description: Add --trace-only <dir> (log before red check, sorted unique trace on green, no scoring) and --score <trace>... (union then the existing scoring loop) to run-bash-coverage.sh, with tests
role: executor
model: sonnet
tdd: required
requirements: [R3, R4]
acceptance:
  - cmd: bats --jobs 8 tests/scripts/unit.bats < /dev/null
    exit_code: 0
  - cmd: make test < /dev/null
    exit_code: 0
max_retries: 3
files_touched: [scripts/run-bash-coverage.sh, tests/scripts/unit.bats, tests/fixtures/coverage-shard/]
depends_on: [1]
```

**Behaviour:** spec `--trace-only` and `--score` bullets. `--trace-only <dir>`: run the traced bats as today, copy the TAP log to `<dir>/bats_run.log` BEFORE `_check_red_suite`; red exits 1 with the log there; green writes `<dir>/bash_trace.txt` = `LC_ALL=C sort -u` of the trace, prints its line count, exits 0, never scores. `--score <trace>...`: no bats; union with `LC_ALL=C sort -u` into a temp file; run the existing per-file loop unchanged (same table, `TOTAL`, `Overall bash coverage:`, disagreements, `--json`); missing or empty trace argument exits 2. Factor the scoring loop into a function both the main run and `--score` call, so its behaviour is shared, not copied.

**Tests:** traced runs use a fixture `tests/` tree of two tiny `.bats` files (named `*.bats.fixture`, copied into a temp tree; never real `*.bats` under `tests/fixtures`) and a tiny instrumented script, driven so the run takes seconds; red fixture leaves a log containing the failing test's own output; `--score` of two traces equals `--score` of their concatenation AND asserts a specific non-zero `TOTAL`; missing/empty trace exits 2. If driving a real traced run in a fixture tree is infeasible, stop and report a blocker rather than weakening the test. Mutation: move the log copy after the red check; the red test must fail.

### Task 3: `ci-shard-gate.sh --with-traces`

```yaml-task
id: 3
description: Add --with-traces to scripts/ci-shard-gate.sh requiring one non-empty shard-<i>.trace per shard-<i>.files and no orphan trace, with tests
role: executor
model: sonnet
tdd: required
requirements: [R10]
acceptance:
  - cmd: bats --jobs 8 tests/scripts/ci_shard_gate.bats < /dev/null
    exit_code: 0
  - cmd: make test < /dev/null
    exit_code: 0
max_retries: 3
files_touched: [scripts/ci-shard-gate.sh, tests/scripts/ci_shard_gate.bats]
depends_on: []
```

**Behaviour:** spec "`scripts/ci-shard-gate.sh`". Without the flag, unchanged (traces in the directory ignored; add a test). With `--with-traces`, before coverage/disjointness: each `shard-<i>.files` has a non-empty `shard-<i>.trace`, each trace has its list; else exit 1 naming the shard (`pairing:` prefix). Usage errors exit 2.

**Tests:** missing trace, empty trace, orphan trace each fail naming the shard; complete pairing passes with the PASS summary; flagless run over lists plus traces passes. Mutant: skip the empty check → the empty-trace test fails.

### Task 4: Makefile `test-prereqs` and `bash-coverage` argument forwarding

```yaml-task
id: 4
description: Add test-prereqs, keep the test line naming its prerequisites, forward BATS_FILES_FROM and COVERAGE_TRACE_DIR to run-bash-coverage.sh as arguments, unexport both, with tests
role: executor
model: sonnet
tdd: required
requirements: [R1, R5]
acceptance:
  - cmd: bats --jobs 8 tests/makefile_shard_list.bats tests/makefile_parallel_target.bats tests/scripts/docs_inert_premise.bats tests/scripts/makefile_lint_scope.bats tests/setup_env/requirements_ci.bats < /dev/null
    exit_code: 0
  - cmd: make test < /dev/null
    exit_code: 0
max_retries: 3
files_touched: [Makefile, tests/makefile_shard_list.bats, tests/scripts/docs_inert_premise.bats]
depends_on: [1, 2]
```

**Behaviour:** `test-prereqs: lint check-lock check-requirements-ci test-python check-claude-md-budget` (phony). `test:` becomes `test: test-prereqs lint check-lock check-requirements-ci test-python check-claude-md-budget test-bats` so the literal-line tests keep passing; make runs each target once. `bash-coverage`: when `BATS_FILES_FROM` is non-empty, refuse a missing/empty list as `test-bats` does and pass `--files $(BATS_FILES_FROM)`; when `COVERAGE_TRACE_DIR` is non-empty, pass `--trace-only $(COVERAGE_TRACE_DIR)`; both `unexport`ed. Unset: recipe as today. Add `test-prereqs` to `ALLOWED_TEST_PREREQS` (only change in that file).

**Tests (makefile_shard_list.bats, stub `bash`/`bats` on its from-scratch PATH; unset both variables first):** `make -n test` lists the prerequisites before the bats call; `make test-prereqs` runs no bats; `make bash-coverage` with both variables set in the environment passes `--files <path> --trace-only <dir>` on the script's command line and the stub sees neither variable; unset gives today's argv; missing list refused.

### Task 5: pre-push strips make-input variables

```yaml-task
id: 5
description: Run both make test calls in scripts/pre-push under env -u MAKEFLAGS -u MFLAGS -u MAKELEVEL -u BATS_FILES_FROM, with two recorded-environment tests
role: executor
model: sonnet
tdd: required
requirements: [R8]
acceptance:
  - cmd: bats --jobs 8 tests/scripts/pre_push.bats < /dev/null
    exit_code: 0
  - cmd: make test < /dev/null
    exit_code: 0
max_retries: 3
files_touched: [scripts/pre-push, tests/scripts/pre_push.bats]
depends_on: []
```

**Behaviour:** spec "Pre-push". Both `make ... test` calls (in-place and clean-checkout) prefixed `env -u MAKEFLAGS -u MFLAGS -u MAKELEVEL -u BATS_FILES_FROM`. `tests/scripts/pre_push.bats` mocks `make`; extend the mock (or its recording) to capture the presence of those variables, then two cases on a feature ref that runs the suite: exported `BATS_FILES_FROM` absent in the mock's environment; exported `MAKEFLAGS=BATS_FILES_FROM=<list>` absent. Cover the clean-checkout path too if the file already has a case reaching it. Mutant: drop `-u MAKEFLAGS` → the second case fails. Respect the file's rules: master/main refs only in `wiring:` tests.

### Task 6: CI workflow and CI-shape tests

```yaml-task
id: 6
description: Replace the untraced test job and the bash-coverage job with the test-shard matrix and the test gate, and pin the shape in tests
role: executor
model: sonnet
tdd: required
requirements: [R6, R7]
acceptance:
  - cmd: bats --jobs 8 tests/scripts/ci_test_shard.bats tests/scripts/ci_test_macos_shard.bats tests/scripts/ci_test_macos_log.bats tests/scripts/ci_runner_pins.bats tests/setup_env/requirements_ci.bats tests/setup_env/shellcheck_pin.bats < /dev/null
    exit_code: 0
  - cmd: make test < /dev/null
    exit_code: 0
max_retries: 3
files_touched: [.github/workflows/ci.yml, tests/scripts/ci_test_shard.bats, tests/scripts/ci_test_macos_shard.bats, tests/scripts/ci_runner_pins.bats, tests/setup_env/requirements_ci.bats, tests/setup_env/shellcheck_pin.bats]
depends_on: [1, 2, 3, 4]
```

**Behaviour:** spec "CI". `test-shard` (matrix [1,2,3], fail-fast false, ubuntu-latest, 30 min, contents: read): today's `bash-coverage` install steps; `Tool versions` from today's `test`; bash step `bats-shard.sh` -> `shard-<i>.files`; shard 1 `make test-prereqs`; `make bash-coverage` with step env `BATS_FILES_FROM` and `COVERAGE_TRACE_DIR: shard-out`; `ci-suite-report.sh shard-out/bats_run.log --files shard-<i>.files` (no `if:`); success-only upload `test-shard-${{ github.run_attempt }}-<i>` of the list and `shard-out/bash_trace.txt` as `shard-<i>.trace` (stage both into one dir first), `if-no-files-found: error`; failure/cancel upload of the log as `test-shard-log-<i>`, `overwrite: true`. Gate `test` (ubuntu, needs test-shard, `if: always()`, 10 min, contents: write): result check, checkout, download (same pinned download-artifact SHA as `test-macos`) into `cov-shards` with merge-multiple, `ci-shard-gate.sh --with-traces cov-shards`, `run-bash-coverage.sh --score cov-shards/shard-*.trace`, today's floor step and badge step reading that output. Delete the untraced `test` job's old body and the `bash-coverage` job; `auto-merge` needs drops `bash-coverage`.

**Tests:** new `ci_test_shard.bats` per spec CI-shape bullets (per-job raw-text extractor with positive control; the `ci-suite-report.sh` step pinned with no `if:`, log path from `COVERAGE_TRACE_DIR`, same list; only `test` has contents: write; `always()` exactly twice outside comments; SHA pins with a floor). Retarget only what N4 allows: `ci_test_macos_shard.bats`' single-`always()` assertion becomes "exactly twice, in `test-macos` and `test`"; any test naming `bash-coverage` or the old `test` job's steps. `requirements_ci.bats`' per-job uv test must still pass (the shard job installs uv). Each new assertion shown red once against a broken copy via `WORKFLOW_UNDER_TEST`.

### Task 7: Docs and ADR-0054

```yaml-task
id: 7
description: CLAUDE.md CI and Coverage sections, README CI list, ADR-0054 plus index and ADR-0037 status, Backlog rows (docs-only, no behaviour change)
role: executor
model: sonnet
tdd: not-applicable
requirements: [R9]
acceptance:
  - cmd: make check-claude-md-budget < /dev/null
    exit_code: 0
  - cmd: make lint < /dev/null
    exit_code: 0
  - cmd: test -f docs/adr/0054-single-linux-gate-sharded-coverage.md
    exit_code: 0
  - cmd: 'grep -q "0054" docs/adr/README.md'
    exit_code: 0
max_retries: 3
files_touched: [CLAUDE.md, README.md, docs/adr/0054-single-linux-gate-sharded-coverage.md, docs/adr/README.md, docs/adr/0037-macos-suite-gates-merge.md, docs/superpowers/README.md]
depends_on: [6]
```

**Content:** spec "Docs" bullet by bullet, verified against the branch files. CLAUDE.md: replace the `test` and `bash-coverage` CI bullets with `test-shard` and the `test` gate (re-run all jobs, never failed-only; local repro `bash scripts/bats-shard.sh <i> 3 > /tmp/s && make bash-coverage BATS_FILES_FROM=/tmp/s COVERAGE_TRACE_DIR=/tmp/out`); `auto-merge` needs list; runner list; timeouts (`test-shard` 30, `test` 10, `bash-coverage` removed); `needs:` rule naming both `always()` gates; Coverage > Bash names `--files`, `--trace-only`, `--score`, `--with-traces`; the bash-coverage bullet's "installed in BOTH jobs" sentence updated. Stay under the 85000-byte budget. ADR-0054 per spec, including the accepted untraced-Linux gap. Backlog: narrow the env-var row (add `GNUMAKEFLAGS`/`MAKEFILES`), close the 60-minute cap row and the "prints only the names" row. Open-table rows only.

### Orchestrator steps (not dispatched)

- [ ] After Task 7: `make test` once; paste the summary.
- [ ] Phase 3 gate chain through pr-review, then push and open the PR as a DRAFT (`gh pr create --draft`).
- [ ] Headroom proof (V1): add one commit `chore(ci): temporary headroom baseline` with two jobs, `headroom-baseline` (today's single `bash-coverage` traced run on the same SHA, uploading its `sort -u` trace; no badge, contents: read, not in `auto-merge` needs) and `headroom-diff` (needs both; downloads both; prints the union's and the baseline's `TOTAL` and the per-file line diff). Run CI twice (re-run all jobs). Record both runs' figures and diffs in the PR body. If the union is below 91% or loses lines outside known timing-dependent branches: stop; the PR stays draft and a margin-raising PR goes first.
- [ ] `git revert` the temporary commit (or drop it before marking ready), re-run the gate chain's recorded items at the final SHA.
- [ ] Ask the operator to remove `bash-coverage` from required checks (`gh api -X DELETE repos/brujack/dotfiles/branches/master/protection/required_status_checks/contexts -f 'contexts[]=bash-coverage'` or the settings page); after they confirm, `gh pr ready`; watch CI to merge.
- [ ] After merge: rebase or re-run every open PR; post-merge docs and learnings.

## Non-goal check

Reviewer verdicts (2026-10-31): N1, N2, N3 CLEAR. N4 CONFLICT, quoting Task 6: "`ci_test_macos_shard.bats`' single-`always()` assertion becomes \"exactly twice, in `test-macos` and `test`\"" — that assertion names neither the untraced `test` job's steps nor `bash-coverage`, so it fell outside N4's exceptions. Secondary point (Task 1, adding `--print-output-on-failure` to the default argv) checked against the repo: the existing argv tests (`tests/scripts/unit.bats:1089-1107`) assert substrings only, so no existing assertion changes.

Resolution (spec amendment): N4 amended to allow changing that one assertion to "exactly twice, as the `if:` of `test-macos` and of `test`"; the plan text is unchanged.
