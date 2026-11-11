# Pre-push signal-case bound removal Implementation Plan

spec: docs/superpowers/specs/2026-11-11-pre-push-signal-case-bound-design.md

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the flaky 8 s wall-clock assertion from `_signal_case` and make its comment state what actually catches a hook that does not wait.

**Architecture:** Test-only change in `tests/scripts/pre_push.bats` plus removal of one Backlog row. No production code changes.

**Tech Stack:** bats, bash.

## Global Constraints

- No change to `scripts/pre-push` (N1).
- No `@test` block in `tests/scripts/pre_push.bats` is added or removed, and no helper other than `_signal_case` changes (N2).
- The `make` mock's `sleep 10` after `kill -"${MAKE_MOCK_SIGNAL}" 0` is unchanged (R3).

## Verification

Session-level: both `dirty-tree: interrupt` cases pass; with `trap 'exit 143' TERM` in
`scripts/pre-push` replaced by `: no-trap`, the TERM case fails at `_assert_temp_gone`
(V1, reverted afterwards); `make test` exits 0; CI green with both cases `ok` on the macOS
shard (V2). The orchestrator runs `make test` once after Task 1, since the task's own gates
are scoped.

Base values of the task gates (measured on master `87f37a18`): `not raced` occurs 1 time
in `tests/scripts/pre_push.bats`; `SECONDS` occurs 2 times; the Backlog row is at line 256.
So each absence gate fails on the base tree.

---

### Task 1: Delete the bound, rewrite the shim comment, remove the Backlog row

```yaml-task
id: 1
description: Delete SECONDS=0 and the 8 s bound from _signal_case, rewrite the slow-git-shim comment in place, remove the Backlog row (test-only change removing an assertion; no new behaviour to drive red first, V1 mutation is the control)
role: executor
model: sonnet
tdd: not-applicable
requirements: [R1, R2, R3, R4]
acceptance:
  - cmd: '! grep -q SECONDS tests/scripts/pre_push.bats'
    exit_code: 0
  - cmd: '! grep -q "not raced" tests/scripts/pre_push.bats'
    exit_code: 0
  - cmd: 'awk "/^_signal_case\\(\\)/,/^}/" tests/scripts/pre_push.bats | grep -c "_assert_temp_gone"'
    exit_code: 0
    stdout_match: '^[2-9]$'
  - cmd: 'grep -A1 "kill -\"\\\\\${MAKE_MOCK_SIGNAL}\" 0" tests/scripts/pre_push.bats | grep -q "sleep 10"'
    exit_code: 0
  - cmd: '! grep -q "fails its 8 s wall-clock bound" docs/superpowers/README.md'
    exit_code: 0
  - cmd: 'bats -f "dirty-tree: interrupt" tests/scripts/pre_push.bats'
    exit_code: 0
    stdout_match: 'ok 2 dirty-tree: interrupt \(INT\)'
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched: [tests/scripts/pre_push.bats, docs/superpowers/README.md]
depends_on: []
```

**Files:**

- Modify: `tests/scripts/pre_push.bats`, function `_signal_case`.
- Modify: `docs/superpowers/README.md`, Backlog.

- [ ] **Step 1: Rewrite the comment.** In `_signal_case`, replace the two-line comment

  ```bash
    # Slow the cleanup's worktree removal so a hook shell that exits without
    # waiting for the subshell's cleanup is caught, not raced.
  ```

  with:

  ```bash
    # Slow the cleanup's worktree removal by 1 s so a hook shell that exits
    # without waiting for the subshell's cleanup returns while the temporary
    # checkout still exists; _assert_temp_gone then fails. The check relies on
    # bats reaching _assert_temp_gone within that 1 s, so a miss is a silent
    # pass, never a failure of a correct hook. There is no wall-clock bound:
    # it detected only a slow-but-correct interrupted exit, which no
    # requirement forbids, and it failed correct hooks on loaded macOS runners.
  ```

- [ ] **Step 2: Delete the bound.** Remove the line `  SECONDS=0` before `run _in_new_session "${_wrapper}"` and the line `  [ "${SECONDS}" -lt 8 ]` after the status assertion. Change nothing else in the function.

- [ ] **Step 3: Remove the Backlog row** in `docs/superpowers/README.md` whose first cell begins "`dirty-tree: interrupt (TERM)` fails its 8 s wall-clock bound" (one table line).

- [ ] **Step 4: Run the gates** above, then V1: replace `trap 'exit 143' TERM` in `scripts/pre-push` with `: no-trap`, run `bats -f "dirty-tree: interrupt \(TERM\)" tests/scripts/pre_push.bats`, confirm `not ok` from `_assert_temp_gone`, then `git checkout -- scripts/pre-push` and confirm `git diff --stat scripts/pre-push` is empty. Report the V1 output.

- [ ] **Step 5: Commit** both files with a `test(pre-push):` Conventional Commit message (generate with `caveman:caveman-commit`), with the session trailers.

**Interfaces:**

- Consumes: nothing.
- Produces: nothing other tasks use.

## Non-goal check

- N1 CLEAR — "Step 4 (V1) temporarily edits `scripts/pre-push` ... then reverts it via `git checkout -- scripts/pre-push` and verifies `git diff --stat` is empty." Resolution: none needed; the edit is a verification control outside `files_touched`.
- N2 CLEAR — "Only `_signal_case` internals change (comment rewrite plus deletion of `SECONDS=0` and `[ \"${SECONDS}\" -lt 8 ]`); no `@test` blocks are added or removed." Resolution: none needed.
