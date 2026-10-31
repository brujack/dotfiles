# test-macos Shard Implementation Plan

spec: docs/superpowers/specs/2026-10-30-test-macos-shard-design.md

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development (the local override) to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split the required `test-macos` CI job into a 3-leg macOS matrix (`test-macos-shard`) plus an ubuntu aggregation gate still named `test-macos`, packed by measured CPU seconds.

**Architecture:** `scripts/bats-shard.sh` packs every `.bats` file into N shards from `tests/bats-weights.tsv`. Each CI shard writes its list once (`shard-<i>.files`) and passes it to make through an unexported `BATS_FILES_FROM`; make, `ci-suite-report.sh --files` and `scripts/ci-shard-gate.sh` all read that one file. Shards upload their list only on success, under attempt-scoped names, so the gate's coverage check proves every shard passed.

**Tech Stack:** bash, bats, GNU Make 3.81 and 4.x, GitHub Actions.

## Global Constraints

- The spec is the authority: read its Design, Testing and Requirements sections before each task. Section names below refer to it.
- Make 3.81 compatibility (the macOS runner's `/usr/bin/make`): no `$(file …)`, no `.SHELLSTATUS`; the list is read with `$(shell cat …)`.
- `BATS_FILES_FROM` is `unexport`ed and passed by CI only as step `env:`, never on a make command line.
- `bats-shard.sh` exits 2 with empty stdout on every error; `BATS_SHARD_HANDICAP` defaults to 40.
- No change to `JOBS`, bats flags within a shard, the Linux `test`/`bash-coverage`/`powershell` jobs, branch protection or `auto-merge`'s `needs:` (N2-N4).
- No existing test changes what it asserts except retargeting `test-macos` → `test-macos-shard` in `tests/scripts/ci_test_macos_log.bats` and in `tests/scripts/ci_runner_pins.bats`'s positive control (N5).
- Every new test file sources `tests/helpers/common.bash` or unsets `GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE` itself; any stdout-capturing `make -C` carries `--no-print-directory` (partition rule, `tests/scripts/makefile_lint_scope.bats`).
- Every success-path test also asserts non-empty output.
- Shell standards: `#!/usr/bin/env bash`, no top-level `set -e`, functions `|| return 1`, sourcing guard on the last line, `[[ ]]`, `printf`.

## Verification

- Session-level: `make test` green in the worktree (3621 tests at base plus the new ones), then CI on the PR: three `test-macos-shard` legs and the `test-macos` gate green, each leg's log printing `executed=N declared=N` with N > 0 and the three N summing to the full declared count.
- Edge cases proven by tests, not by CI: a dropped line, an overlap, a missing download directory, a serial-only list, a "re-run failed jobs" attempt (attempt-scoped names, covered by the CI-shape test).
- Suite duration on `claude`: under the 600 s Bash cap, so code tasks gate on `make test`.

---

### Task 1: `bats-shard.sh` and the weights table

```yaml-task
id: 1
description: Add scripts/bats-shard.sh (CPU-weighted LPT packing) and the seeded tests/bats-weights.tsv, with tests
role: executor
model: sonnet
tdd: required
requirements: [R1, R2, R8]
acceptance:
  - cmd: bats tests/scripts/bats_shard.bats
    exit_code: 0
  - cmd: 'bash scripts/bats-shard.sh 1 3 | grep -c . | grep -qvx 0'
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [scripts/bats-shard.sh, tests/bats-weights.tsv, tests/scripts/bats_shard.bats, tests/fixtures/bats-shard/]
depends_on: []
```

**Files:** create `scripts/bats-shard.sh`, `tests/bats-weights.tsv`, `tests/scripts/bats_shard.bats`, fixture trees under `tests/fixtures/bats-shard/`. Fixture `.bats` files must NOT end in `.bats` (they would join the real suite and the real `find`): name them `*.bats.fixture` and have the tests copy them into `${BATS_TEST_TMPDIR}/tests/` as `*.bats` before running the script there (the script runs `find tests` relative to its cwd).

**Weights table:** copy `/tmp/claude-1000/-home-bruce-git-repos-personal-dotfiles/b338f609-49a2-44c9-9d20-31fb95ef48aa/scratchpad/m/weights.tsv` (86 rows, `<path>\t<cpu-seconds>`, `LC_ALL=C` sorted, total 2680.4) and prepend one comment line: `# CPU s (user+sys, children) of bats --jobs 3 <file>, macOS, env -i; Studio @ ab92a62d; reseed: ai-config docs/knowledge/dotfiles-bats-test-infrastructure.md`.

**Behaviour:** spec "Shard selection" steps 1-4 exactly. Weight arithmetic in awk (floats). Dead rows to stderr as `bats-shard: dead row: <path>`. Every error: message on stderr, nothing on stdout, exit 2.

**Tests (spec "Testing", `bats_shard.bats`):** real-tree partition for N in 1..4 (non-empty, disjoint, union == `find tests -name '*.bats' | LC_ALL=C sort`, more than 80 entries); golden fixture with tied weights and tied running totals, exact per-shard output at `BATS_SHARD_HANDICAP=0` and at a non-zero handicap, the two differing; balance-beats-count with `BATS_SHARD_HANDICAP=0` in both arms, both partitions scored with the committed table (expect 894 < 1056 at base; assert only `<`); fallback weight decides a fixture shard; dead row named on stderr, output and exit unchanged; exit 2 + empty stdout for bad args (`0 3`, `4 3`, `x 3`, `1 0`), unreadable table, no live rows, live-row `^@test` sum 0, malformed line, empty tree. Mutation check before commit: swap the heaviest-first sort to lightest-first and confirm the golden test fails; report it.

**Interfaces:** Produces `bash scripts/bats-shard.sh <i> <N>` → one path per line; env `BATS_WEIGHTS`, `BATS_SHARD_HANDICAP`.

### Task 2: Makefile `BATS_FILES_FROM` and `test-bats`

```yaml-task
id: 2
description: Move the bats recipe into test-bats, add unexported BATS_FILES_FROM with filtered, separately guarded serial and parallel passes, with tests
role: executor
model: sonnet
tdd: required
requirements: [R3]
acceptance:
  - cmd: bats tests/makefile_shard_list.bats tests/makefile_parallel_target.bats
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [Makefile, tests/makefile_shard_list.bats, tests/scripts/docs_inert_premise.bats]
depends_on: []
```

**Files:** `Makefile` (bats recipe at the `test:` rule, `BATS_*` variables near `BATS_SERIAL_FILES`), new `tests/makefile_shard_list.bats`. `tests/makefile_parallel_target.bats` must pass unmodified (N5): `make -n test` still prints the `test-bats` recipe as a prerequisite. If it cannot, stop and report a blocker; do not edit it. Add `test-bats` to `ALLOWED_TEST_PREREQS` in `tests/scripts/docs_inert_premise.bats` (re-plan 1, spec amendment N5): it reads no tracked `.md`.

**Behaviour:** spec "Makefile". `test:` keeps its prerequisites and adds `test-bats`; `test-bats` holds the recipe. `BATS_RAN_FILES` = `$(shell cat $(BATS_FILES_FROM))` when set, else `BATS_ALL_FILES`. Refuse (non-zero, message on stderr, before bats) when `BATS_FILES_FROM` is set and `$(wildcard …)` is empty, or when `BATS_RAN_FILES` is empty. Serial pass `$(filter $(BATS_SERIAL_FILES),$(BATS_RAN_FILES))`, parallel pass the `filter-out`, each in its own `ifneq ($(strip …),)`; keep the HAVE_PARALLEL serial fallback and its message. `unexport BATS_FILES_FROM`. Keep the existing comments that still apply.

**Tests (`makefile_shard_list.bats`):** follow `makefile_parallel_target.bats`'s from-scratch `PATH` shim, but stub `bats` to append its argv and `${BATS_FILES_FROM-unset}` to a record file, then run `make --no-print-directory -C "${REPO_ROOT}" test-bats` (never `test`, never real bats). Cases: unset → argv lists `BATS_ALL_FILES`; set in env to a 2-file fixture list → argv is exactly those 2 and the stub saw `unset`; `BATS_SERIAL_FILES=<a listed file>` on the command line → that file only in the serial call, an unlisted serial file not run; serial-only list → no parallel call, exit 0; missing list file and empty list file → non-zero and no stub call. Strip `MAKEFLAGS MFLAGS MAKELEVEL JOBS` as that file does.

**Interfaces:** Produces `BATS_FILES_FROM=<file> make test-bats`, `make test` unchanged when unset.

### Task 3: `ci-suite-report.sh --files`

```yaml-task
id: 3
description: Add the <log> --files <list> mode to scripts/ci-suite-report.sh, with tests
role: executor
model: sonnet
tdd: required
requirements: [R4]
acceptance:
  - cmd: bats tests/scripts/ci_suite_report.bats
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [scripts/ci-suite-report.sh, tests/scripts/ci_suite_report.bats]
depends_on: []
```

**Behaviour:** spec "`scripts/ci-suite-report.sh`". `ci-suite-report.sh <log> --files <listfile>`: declared = `grep -c '^@test'` summed over the listed paths (a listed path that is unreadable is exit 2 naming it); same output line and same zero-declared refusal; the two-argument form is byte-for-byte unchanged in behaviour. Update the usage comment.

**Tests:** passes when executed == declared over a non-empty fixture list; fails one short; fails on an empty list; unreadable listed path exits 2; existing two-argument tests untouched.

### Task 4: `ci-shard-gate.sh`

```yaml-task
id: 4
description: Add scripts/ci-shard-gate.sh (coverage and disjointness over shard-*.files against an independent find), with tests
role: executor
model: sonnet
tdd: required
requirements: [R5]
acceptance:
  - cmd: bats tests/scripts/ci_shard_gate.bats
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [scripts/ci-shard-gate.sh, tests/scripts/ci_shard_gate.bats]
depends_on: [1]
```

**Behaviour:** spec "`scripts/ci-shard-gate.sh`". `ci-shard-gate.sh <dir>` run from the repo root; independent `find tests -name '*.bats' | LC_ALL=C sort`; never calls `bats-shard.sh` or make. Fails on missing `<dir>`, no `shard-*.files`, union != find (prints `coverage:` plus missing and extra paths, so a blank line or extra path fails), any duplicate (prints `disjointness:` plus paths). Use `LC_ALL=C` on every `sort`/`comm`.

**Tests:** spec "Testing", `ci_shard_gate.bats`: correct fixture partition passes; missing file → coverage; overlap → disjointness; missing dir, empty dir, blank line, extra path each fail; drop-one-line from the real 3-shard output → coverage; real-output control: `bash scripts/bats-shard.sh <i> 3 > <dir>/shard-<i>.files` for i in 1..3 → passes.

### Task 5: CI workflow and CI-shape tests

```yaml-task
id: 5
description: Replace the test-macos job with the test-macos-shard matrix plus the ubuntu test-macos gate, and pin its shape in tests
role: executor
model: sonnet
tdd: required
requirements: [R6, R7]
acceptance:
  - cmd: bats tests/scripts/ci_test_macos_shard.bats tests/scripts/ci_test_macos_log.bats tests/scripts/ci_runner_pins.bats
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [.github/workflows/ci.yml, tests/scripts/ci_test_macos_shard.bats, tests/scripts/ci_test_macos_log.bats, tests/scripts/ci_runner_pins.bats]
depends_on: [1, 2, 3, 4]
```

**Behaviour:** spec "CI". Shard job: current `test-macos` steps renamed into `test-macos-shard` with matrix, a `Compute shard list` bash step (`bats-shard.sh ${{ matrix.shard }} ${{ strategy.job-total }} > shard-${{ matrix.shard }}.files`), `Run tests` with step `env: BATS_FILES_FROM`, shard 1 `make test` else `make test-bats` (one step with a shell `if` on `${{ matrix.shard }}`), report via `ci-suite-report.sh /tmp/make-test.log --files shard-<i>.files`, success-only list upload `test-macos-shard-${{ github.run_attempt }}-${{ matrix.shard }}` with `if-no-files-found: error`, log upload `test-macos-make-test-log-${{ matrix.shard }}` unchanged otherwise. Gate job per spec; resolve the `actions/download-artifact` v7 full commit SHA with `gh api repos/actions/download-artifact/git/ref/tags/<tag>` (dereference an annotated tag) and record the tag in a comment. Comments must not contain the string `always()`.

**Tests:** spec "Testing", CI-shape bullets. New `ci_test_macos_shard.bats` with a per-job raw-text extractor (job header to next job header, block bodies included) and its positive control; retarget the two existing files only as N5 allows. Each new assertion must be shown red once: break `ci.yml` locally (e.g. drop `merge-multiple`, add `BATS_FILES_FROM=` to the make line, add a second `always()`), see the matching test fail, restore. Report each.

### Task 6: dotfiles docs and ADR-0053

```yaml-task
id: 6
description: CLAUDE.md CI/Testing updates, ADR-0053 plus index and ADR-0037 status, Backlog rows (docs-only, no behaviour change)
role: executor
model: sonnet
tdd: not-applicable
requirements: [R9, R10]
acceptance:
  - cmd: make check-claude-md-budget
    exit_code: 0
  - cmd: make lint
    exit_code: 0
  - cmd: test -f docs/adr/0053-shard-test-macos-by-cpu-seconds.md
    exit_code: 0
  - cmd: 'grep -q "0053" docs/adr/README.md'
    exit_code: 0
max_retries: 3
files_touched: [CLAUDE.md, docs/adr/0053-shard-test-macos-by-cpu-seconds.md, docs/adr/README.md, docs/adr/0037-macos-suite-gates-merge.md, docs/superpowers/README.md]
depends_on: [5]
```

**Content:** spec "Docs". CLAUDE.md: rewrite the `test-macos` bullet (shard job + gate, authoritative artifact, local repro `BATS_FILES_FROM=<list> make test-bats`, three log artifacts, never `--failed` and why it fails coverage); amend the `needs:` rule for the single `always()`; runner list (`test-macos` on ubuntu-latest, `test-macos-shard` on macos-latest); timeouts (`test-macos-shard` 30, `test-macos` 10); Testing line on `tests/bats-weights.tsv`. Keep CLAUDE.md under the 85000-byte ceiling. ADR-0053 (Context, Decision, Consequences, Related) records the shape, CPU weighting with its measurements and the self-hosted alternative; ADR-0037's status line notes partial supersession. `docs/superpowers/README.md`: rewrite the P1 `test-macos` Backlog row to point at the spec and V1; correct the setup-floor row's claim that the floor explains the shard imbalance (CPU seconds do, per the spec); point the plan index row at this plan file. Backlog rows go in the open Backlog table, not "Closed without shipping".

### Orchestrator steps (not dispatched)

- [ ] After Task 6: `make test` once in the worktree; paste the summary line.
- [ ] ai-config knowledge (R8): message the ai-config session (`ListAgents`, `SendMessage`) first; in an ai-config worktree add a `Shard weights: reseed procedure` section to `docs/knowledge/dotfiles-bats-test-infrastructure.md` with the per-file `/usr/bin/time -p bats --jobs 3` loop (6 concurrent, `env -i`, Studio), the `LC_ALL=C sort` step and the table header format; `make test` there; push to ai-config master (docs-only).
- [ ] Phase 3 via `finishing-a-development-branch`; PR body carries the V1/V2 plan; `gh pr checks --watch` and confirm each shard log's `executed=`/`declared=`.

## Non-goal check

Reviewer verdicts (2026-10-31): N1-N4 CLEAR. N5 UNCLEAR, quoting Task 2's `files_touched` entry for `tests/makefile_parallel_target.bats` and its "only if its `make -n test` expectations need the recipe's new location".

Resolution (plan revision): Task 2 no longer lists that file. Before: "`tests/makefile_parallel_target.bats` only if its `make -n test` expectations need the recipe's new location (its assertions must not change, N5)." After: "`tests/makefile_parallel_target.bats` must pass unmodified (N5): `make -n test` still prints the `test-bats` recipe as a prerequisite. If it cannot, stop and report a blocker; do not edit it."
