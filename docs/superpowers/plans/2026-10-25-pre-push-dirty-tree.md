# pre-push Dirty-Tree Clean Checkout Implementation Plan

spec: docs/superpowers/specs/2026-10-25-pre-push-dirty-tree-refusal-design.md

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** when the working tree is dirty, `scripts/pre-push` runs the suite in a locked, temporary, detached worktree at the pushed commit instead of in the dirty tree.

**Architecture:** after the wrong-tree refusal, the hook reads `git --no-optional-locks status --porcelain --untracked-files=all` of `REPO_ROOT` (`GIT_*` stripped). Empty: today's `make -C "${REPO_ROOT}" test`. Non-empty or failed read: a subshell creates `mktemp -d "${TMPDIR:-/tmp}/pre-push.XXXXXX"`, adds a locked detached worktree `pre-push-<sha7>` at `tree_head`, runs `make -C` there, and removes it from an `EXIT` trap; the hook's own shell traps INT/TERM so it waits for that cleanup.

**Tech Stack:** bash (hook under `set -e`), bats (`tests/scripts/pre_push.bats`), python3 (new-session helper), git worktree.

## Global Constraints

- Status read: `env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE git -C "${REPO_ROOT}" --no-optional-locks status --porcelain --untracked-files=all`, inside a conditional.
- Temp root: `mktemp -d "${TMPDIR:-/tmp}/pre-push.XXXXXX"`; never a bare `mktemp -d` (BSD ignores `TMPDIR`).
- Worktree: `${_tmp_root}/pre-push-${tree_head:0:7}`, `worktree add --quiet --detach --lock --reason "pre-push pid $$ testing ${tree_head:0:7}"`.
- Cleanup: `worktree remove -f -f "${_tree}"` then `rm -rf "${_tmp_root}"`, from an `EXIT` trap installed only after `_tmp_root` is non-empty; never `git worktree prune`.
- Messages (exact): `pre-push: working tree has <N> uncommitted or untracked path(s); testing committed <sha7> in clean checkout <path>.` / `pre-push: could not read the working-tree status; testing committed <sha7> in clean checkout <path>.` / `pre-push: suite failed against committed <sha7> (clean checkout <path>, now removed); uncommitted changes were not tested.` / `pre-push: could not create a temporary checkout of <sha7>; push refused.`
- N1 never modify `REPO_ROOT`'s tree, index or stash; N2 a dirty tree alone never refuses; N3 inert set, master guard, budget check, wrong-tree refusal and the clean path unchanged.
- `_budget_commit` is not changed.
- New test names start `dirty-tree: `. `setup()` exports `TMPDIR` under `BATS_TEST_TMPDIR`. Paths compared with `git worktree list` or recorded `-C` dirs go through one canonicalising helper (`cd … && pwd -P`).
- No `setsid`: signal cases use `_in_new_session` from `tests/helpers/new_session.bash`.
- `make test` takes about 3 min on `claude`, under the 600 s Bash cap: run it in the foreground with `timeout: 600000`. In agent shells use `command grep` for absence checks.

## Verification Planning

- **Whole change:** `make test` exits 0 on the branch; CI green including `bash-coverage` (gate 91%, CI-only) and `test-macos`.
- **V1 (orchestrator, after Task 3):** in a detached worktree at the branch tip under `mktemp -d /tmp/pre-push.XXXXXX`, the real `make test </dev/null` exits 0 (claude and Studio already measured on master). In a fresh feature worktree, after `make test`, `make bash-coverage`, `make -C powershell test` and the `dod_log.py` record/finalize steps, `git status --porcelain --untracked-files=all` is empty. Record in the PR body.
- **V2 (orchestrator, before merge):** in the feature worktree, add an uncommitted tracked edit, then `printf '%s %s %s %s\n' refs/heads/<branch> "$(git rev-parse HEAD)" refs/heads/<branch> 0000000000000000000000000000000000000000 | bash scripts/pre-push origin <url>`: the dirty line prints, the suite runs in `/tmp/pre-push.*/pre-push-<sha7>` and passes, the edit is still present, `git worktree list` shows no leftover. Never `-c core.hooksPath`. Record in the PR body.
- **Edge cases the tests exercise:** staged-only, untracked, ignored, corrupt index, inert push with dirty tree, worktree push with dirty main checkout, decoy `GIT_DIR`, suite failure, `mktemp` failure, `worktree add` failure, SIGTERM, SIGINT.
- **ai-config knowledge (orchestrator, after Task 3):** message the ai-config session, then update `docs/knowledge/dotfiles-bats-test-infrastructure.md` § `Testing: pre-commit and pre-push hooks` (mechanism, lock, cleanup and its `kill -9` limit, why untracked files count) in an ai-config worktree, direct to master (docs-only). Not a plan task: another repo.

---

### Task 1: Test apparatus for the dirty-tree cases

```yaml-task
id: 1
description: Share the new-session helper, export TMPDIR file-wide, canonicalise paths and anchor existing make assertions to REPO_DIR (test-only refactor, no hook change)
model: sonnet
tdd: not-applicable
requirements: [R7]
acceptance:
  - cmd: make test
    exit_code: 0
  - cmd: '! command grep -n "make -C \.\* test" tests/scripts/pre_push.bats'
    exit_code: 0
  - cmd: 'test "$(command grep -c "^_in_new_session()" tests/helpers/new_session.bash)" = 1'
    exit_code: 0
  - cmd: '! command grep -n "^_in_new_session()" tests/setup_env/update_signals.bats'
    exit_code: 0
max_retries: 3
files_touched: [tests/helpers/new_session.bash, tests/setup_env/update_signals.bats, tests/scripts/pre_push.bats]
depends_on: []
```

**Files:** create `tests/helpers/new_session.bash`; modify `tests/setup_env/update_signals.bats`, `tests/scripts/pre_push.bats`.

- [ ] Move `_in_new_session` (`update_signals.bats:49-67`, comment included) verbatim into `tests/helpers/new_session.bash` (function only, no top-level side effects); in `update_signals.bats` `setup()`, beside the existing `source "${REPO_ROOT}/tests/helpers/common.bash"`, add `source "${REPO_ROOT}/tests/helpers/new_session.bash"`.
- [ ] In `pre_push.bats` `setup()` (which deliberately does not source `common.bash`; keep it that way): `source "${REPO_ROOT}/tests/helpers/new_session.bash"`, and add `export TMPDIR="${BATS_TEST_TMPDIR}/tmp"; mkdir -p "${TMPDIR}"`; add `_canon() { (cd "$1" && pwd -P); }`.
- [ ] Replace every `grep -qE "^make -C .* test$" "${MOCK_CALLS_FILE}"` (currently 32 `make -C` lines; check each) with an exact match on `make -C $(_canon "${REPO_DIR}") test` (the hook's `REPO_ROOT` is `--show-toplevel`, which is canonical). Where a case runs from another worktree, anchor to that worktree's canonical path.
- [ ] `make test`; commit.

**Why not TDD:** no behaviour changes; the gate is that the existing suite stays green with tighter assertions. Base tree fails gates 2-4.

**Interfaces:** Produces `_in_new_session <script>` (prints exit as 128+N on signal), `_canon <dir>`, file-wide `TMPDIR`.

### Task 2: Dirty tree runs the suite in a locked temporary checkout

```yaml-task
id: 2
description: Status read after the wrong-tree check; clean path unchanged; dirty or unreadable runs make in a locked detached worktree at tree_head with path-bearing messages and trap cleanup
model: sonnet
tdd: required
requirements: [R1, R2, R3, R4, R6, R7]
acceptance:
  - cmd: make test
    exit_code: 0
  - cmd: 'test "$(bats --count -f "^dirty-tree: " tests/scripts/pre_push.bats)" = 11'
    exit_code: 0
  - cmd: '! command grep -n "worktree prune" scripts/pre-push'
    exit_code: 0
max_retries: 3
files_touched: [scripts/pre-push, tests/scripts/pre_push.bats]
depends_on: [1]
```

**Files:** `scripts/pre-push` (between the wrong-tree block and `unset GIT_DIR …`/`make`), `tests/scripts/pre_push.bats`.

Write each case RED then GREEN, one at a time, from the spec's Testing table: `clean tree`, `modified tracked file`, `uncommitted edit changes the verdict`, `staged-only change`, `untracked file`, `ignored file` (commit `.gitignore` first), `suite fails in temp checkout` (exit 2, temp `-C` recorded, suite-failed line), `status read fails` (`printf x > .git/index` after committing), `inert push, dirty tree`, `worktree push, dirty main checkout`, `decoy GIT_DIR` (bypass `_run_pre_push`'s unset). Name each `dirty-tree: <case>`.

- [ ] Extend the `make` mock: when `MAKE_MOCK_RECORD_TREE=1`, also append `git -C <-C dir> rev-parse HEAD`, `git -C <dir> status --porcelain`, and `git -C "${REPO_DIR}" worktree list --porcelain` lock lines to `MOCK_CALLS_FILE`.
- [ ] Hook code per spec Design steps 1-3 and Global Constraints; `_git_stripped` and the message helpers as small functions; reads inside conditionals.
- [ ] Every temp-path case asserts the dir is gone afterwards and `git -C "${REPO_DIR}" worktree list --porcelain` names only `$(_canon "${REPO_DIR}")`.
- [ ] `make test`; commit.

**Interfaces:** Consumes Task 1 helpers. Produces the subshell structure Task 3 adds failure handling and traps to.

### Task 3: Failure paths and signal cleanup

```yaml-task
id: 3
description: mktemp or worktree-add failure refuses with the could-not-create line; hook-shell INT/TERM traps make cleanup finish before exit; TERM and INT cases via _in_new_session
model: sonnet
tdd: required
requirements: [R4, R5, R7]
acceptance:
  - cmd: make test
    exit_code: 0
  - cmd: 'test "$(bats --count -f "^dirty-tree: " tests/scripts/pre_push.bats)" = 19'
    exit_code: 0
max_retries: 3
files_touched: [scripts/pre-push, tests/scripts/pre_push.bats]
depends_on: [2]
```

Cases, RED then GREEN each:

- `dirty-tree: mktemp fails` — `TMPDIR` names a nonexistent dir: exit 1, could-not-create line, no `make` line.
- `dirty-tree: worktree add fails` — a `PATH` `git` shim failing only `worktree add` (exec the real git otherwise, resolved before `PATH` changes): exit 1, line printed, no `make`, no `${TMPDIR}/pre-push.*` left.
- `dirty-tree: interrupt (TERM)` / `(INT)` — write a wrapper script that runs the hook with the fixture stdin; run it via `run _in_new_session <wrapper>`; the `make` mock records its `-C` dir and lock state, then `kill -TERM 0` (or `-INT 0`) and `sleep 10`. Assert output `143` (or `130`), the recorded dir was locked, and immediately after return the dir is gone and `worktree list` names only `REPO_DIR`.

- [ ] Hook: `trap 'exit 130' INT; trap 'exit 143' TERM` in the hook's shell inside the dirty/unreadable branch only (after the status read has chosen it, immediately before the subshell), and the same pair inside the subshell; the clean path installs no trap (N3); `|| { _no_checkout; exit 1; }` on `mktemp` and `worktree add`.
- [ ] Prove the TERM case fails with the hook-shell traps removed (record that run in the commit body).
- [ ] `make test`; commit.

### Task 4: Docs and backlog

```yaml-task
id: 4
description: CLAUDE.md pre-push bullet, remove the P2 Backlog row, add the P3 wrong-tree remedy row and the plan index row (docs-only; CLAUDE.md is read by the budget and phrase tests, so the gate is make test)
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: make test
    exit_code: 0
  - cmd: '! command grep -n "tests uncommitted edits along with the pushed commit" docs/superpowers/README.md'
    exit_code: 0
  - cmd: 'command grep -q "clean temporary checkout\|temporary clean checkout" CLAUDE.md'
    exit_code: 0
max_retries: 3
files_touched: [CLAUDE.md, docs/superpowers/README.md]
depends_on: [3]
```

- [ ] `CLAUDE.md`, after the bullet starting "Once the suite would run": one bullet — a dirty tree (tracked or untracked, not ignored) makes the hook test the pushed commit in a locked temporary clean checkout under `${TMPDIR:-/tmp}`; a `kill -9` leftover clears with `git worktree remove -f -f <path>`; `→ dotfiles-bats-test-infrastructure.md § Testing: pre-commit and pre-push hooks`. Keep under the 85,000-byte ceiling (`make check-claude-md-budget`).
- [ ] `docs/superpowers/README.md`: delete the P2 row "`scripts/pre-push` tests uncommitted edits…"; add to `### P3 — bugs and security` (not the closed table): "wrong-tree refusal remedy text is unsafe to paste | refs printed unquoted; a `HEAD` local ref prints a sha source, so `-u` sets no upstream; found by spec 2026-10-25 round 2"; add the plan/spec index row at the top, status "In progress".
- [ ] `make test`; commit.

## Non-goal check

Reviewer: one fresh subagent, `nongoal-check.md`, 2026-10-25. Verdicts: N1 CLEAR, N2 CLEAR, N3 UNCLEAR.

- **N3 — UNCLEAR.** Quote: Task 3: "Hook: `trap 'exit 130' INT; trap 'exit 143' TERM` in the hook's shell before the subshell, and the same pair inside it". Why: traps installed before the clean/dirty branch would also defer a signal on the clean path until `make -C "${REPO_ROOT}" test` exits. Resolution: plan revised. Before: "in the hook's shell before the subshell, and the same pair inside it;". After: "in the hook's shell inside the dirty/unreadable branch only (after the status read has chosen it, immediately before the subshell), and the same pair inside the subshell; the clean path installs no trap (N3);".

## Re-plan log

- 2026-10-25, after Task 2 review: three `dirty-tree:` cases added in Task 2's fix round (untracked directory, quote in `TMPDIR`, exported `GIT_DIR`), so Task 3's count gate moves from 15 to 18. Spec amendment R7 records the change.
- 2026-10-25, after the Task 2 fix re-review: Task 3 also owns `|| :` on the trap's `rm -rf` and its test, so its count gate moves from 18 to 19. Spec amendment R7 (second) records it.
- 2026-10-25, Phase 3 test-quality-review fix cycle 1: canonical `TMPDIR` in `setup()` (macOS `/private/var`) and a case pinning the trap's second remove; `dirty-tree:` count 20. Spec amendment R7 (third) records it.
