# pre-push Wrong-Tree Refusal Implementation Plan

spec: docs/superpowers/specs/2026-10-22-pre-push-wrong-tree-refusal-design.md

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `scripts/pre-push` refuses, before `make test`, any push whose refs are not all at the commit of the tree `make` will test.

**Architecture:** The ref loop records each non-deletion line. After the existing three refusals, when `needs_test=1`, the hook reads `HEAD` of `REPO_ROOT` with `GIT_*` stripped, peels every recorded `local_sha`, and refuses on any failure or mismatch with a per-ref remedy. Tests drive the hook with synthetic stdin in fixture repos.

**Tech Stack:** bash (hook, `set -e`), bats (`tests/scripts/pre_push.bats`), git plumbing.

## Global Constraints

- Every git read in the new check sits inside a conditional (`if ! x="$(...)"`); the hook runs under `set -e`.
- `HEAD` read: `env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE git -C "${REPO_ROOT}" rev-parse --verify --quiet 'HEAD^{commit}' 2>/dev/null`.
- Peel: `git rev-parse --verify --quiet "${local_sha}^{commit}" 2>/dev/null`.
- The check runs after the unresolved-range, budget and direct-to-master refusals and before `unset GIT_DIR ...` / `make`.
- N1 no archive/switch/temp checkout; N2 no `REPO_ROOT` override seam; N3 no existing assertion deleted or weakened, an existing case changes only the commit it pushes or its fixture's `HEAD`; N4 no change to ai-config or terraform_ansible hooks; N5 the hook never reads `git worktree list`.
- New test names start `wrong-tree: ` (the acceptance count keys on it).
- `make test` runs about 2 minutes here, under the 600 s Bash cap: run it in the foreground with `timeout: 600000`.

## Verification Planning

- **Whole-change proof (V1):** `make test` exits 0 on the branch.
- **Real-push proof (V2), orchestrator, before merge:** from the feature worktree, `git -c core.hooksPath="$PWD/scripts" push -u origin <branch>` passes the hook; from the main checkout (on master), the same command with `core.hooksPath=<worktree>/scripts` and the branch name prints the refusal and exits non-zero. Both outputs go in the PR body.
- **Edge cases the tests must exercise:** annotated tag at HEAD, tag at a tree, unborn HEAD, decoy `GIT_DIR`, `GIT_WORK_TREE` exported, URL remote, `local_ref` outside `refs/`.
- **V3 (ai-config), orchestrator, after Task 2:** message the ai-config session, then one ai-config PR rewriting git-workflow-043 (core.md line, `docs/knowledge/ai-config-standards-core.md` § git-workflow-043, `docs/knowledge/ai-config-bats-testing-pitfalls.md:104`) to "push from the branch's own worktree; if tests fail only during push, strip `GIT_*` in that repo's hook or Makefile (reproduce with `GIT_DIR=<worktree gitdir> make test`)", amending `.claude/skills/finishing-a-development-branch/SKILL.md`'s push step to push from the branch's worktree, and adding a terraform_ansible Backlog row for its missing `GIT_*` strip on the test path. Merged before or with the dotfiles PR; the dotfiles PR body links it. Not a plan task: it is another repo, outside this plan's `files_touched`.

---

### Task 1: Refuse a push whose refs are not at the tested tree's HEAD

```yaml-task
id: 1
description: Add the R1/R2 check after the existing refusals, a minimal refusal line, ten wrong-tree bats cases, and repoint case 83
role: executor
model: sonnet
tdd: required
requirements: [R1, R2, R3, R5]
acceptance:
  - cmd: '[ "$(grep -c "^@test \"wrong-tree: " tests/scripts/pre_push.bats)" -eq 10 ]'
    exit_code: 0
  - cmd: bats tests/scripts/pre_push.bats
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [scripts/pre-push, tests/scripts/pre_push.bats]
depends_on: []
```

**Files:** `scripts/pre-push`, `tests/scripts/pre_push.bats`.

**Hook change.**

1. Before the `while read` loop, add `pushed_refs=""`. Inside the loop, after the deletion `continue` (`:98`), append `"${local_ref} ${local_sha} ${remote_ref}"$'\n'` to it.
2. After the direct-to-master refusal block and the `[[ "${needs_test}" -eq 0 ]] && exit 0` line, before `unset GIT_DIR ...`: resolve `tree_head` with the Global Constraints read (failure leaves it empty). For each line of `pushed_refs`, peel `local_sha`; when the peel fails or differs from a non-empty `tree_head`, or `tree_head` is empty, collect the ref. If any were collected, print the refusal (first line exactly `pre-push: the suite tests this checkout's working tree, not the pushed commit.`, then per ref `  <local_ref> is at <short sha|unresolved>; this checkout (<REPO_ROOT>) is at <short sha|unresolved>.`) to stderr and `exit 1`. Task 2 adds the remedy lines.

**Tests** (each `@test "wrong-tree: ..."`, using `_commit_file`, `_write_make_mock`, `_run_pre_push`, `MOCK_CALLS_FILE`):

1. mismatch refused: non-inert `a.sh` at sha1, HEAD advanced to sha2; push `refs/heads/feat sha1`; status 1, output has both short SHAs, no `MOCK_CALLS_FILE`.
2. match runs suite: same, push sha2; status 0, make called once.
3. inert-only mismatch: `.md` commits only, push older sha; status 0, no refusal text, no make.
4. tag peeled: `git tag -a v1 -m v1` at HEAD after a non-inert commit; push `refs/tags/v1 <tag object sha>`; status 0, make called.
5. mixed refs refused: non-inert ref at HEAD plus an inert-only ref at an older commit; status 1, output names only the older ref.
6. unpeelable ref: `local_sha` = a tag object pointing at a tree (`git tag -a t -m t "$(git rev-parse HEAD^{tree})"`); status 1, output has `unresolved`, not `expected commit type`, no make.
7. unborn HEAD: in a second fixture, `git checkout --orphan empty` with the index cleared, push a non-inert commit sha of the original branch; status 1, `unresolved` in output, no make.
8. master refusal wins: non-inert ref to `refs/heads/master` at a non-HEAD commit; output has the existing `refusing a direct push to master` text and not `not the pushed commit`.
9. decoy GIT_DIR: create a worktree (`git worktree add`) at the pushed commit, run the hook from `REPO_DIR` (HEAD elsewhere) with `GIT_DIR=<REPO_DIR>/.git/worktrees/<name>` exported in the runner; status 1, no make. Needs a runner variant that keeps the exported variable instead of `unset GIT_DIR ...`.
10. work tree elsewhere: hook cwd `REPO_DIR` (HEAD elsewhere), `GIT_WORK_TREE=<worktree at pushed commit>` exported; status 0, make called with `-C <worktree path>`.

**Existing case 83** (`pre_push.bats:884`): push `feat/x` at `${sha2}` instead of `${sha1}`; leave every assertion unchanged (N3).

**Mutation control (report in the receipt):** replace the comparison with `false` (never refuse) and confirm cases 1, 5, 9 go red; make the `HEAD` read return empty and confirm cases 2, 4, 10 go red; read `HEAD` without `env -u ...`/`-C` and confirm case 9 or 10 goes red. Restore the code after each.

**Interfaces:** Produces `pushed_refs` (newline list of `local_ref local_sha remote_ref`), `tree_head`, and a refusal block Task 2 extends; a runner variant for exported git variables.

---

### Task 2: Print the exact remedy and withhold a URL remote

```yaml-task
id: 2
description: Extend the refusal with the R4 remedy command, the re-add-flags line and the R6 remote-name filter, with two wrong-tree cases
role: executor
model: sonnet
tdd: required
requirements: [R4, R6, R7]
acceptance:
  - cmd: '[ "$(grep -c "^@test \"wrong-tree: " tests/scripts/pre_push.bats)" -eq 12 ]'
    exit_code: 0
  - cmd: bats tests/scripts/pre_push.bats
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [scripts/pre-push, tests/scripts/pre_push.bats]
depends_on: [1]
```

**Files:** `scripts/pre-push`, `tests/scripts/pre_push.bats`.

**Hook change.** For each collected ref: `<ref>`/`<src>` is `local_ref` when it starts with `refs/`, else the full `local_sha`; use it in the per-ref line from Task 1 too. `<remote>` is `$1` only when `git remote` (inside a conditional) lists a line equal to it, else the literal `<remote>`. After the per-ref lines print `Push each ref from a checkout whose HEAD is that commit:`, one `  git push <remote> <src>:<remote_ref>` per ref, then `Re-add any flags the original push used (-u, --force-with-lease).`

**Tests:** extend `_run_pre_push` (or add a variant) so the hook receives positional args (`bash scripts/pre-push "$remote" "$url"`); existing calls keep passing none. 11. remedy is the exact command: fixture runs `git remote add origin <bare repo path>`; mismatch on `refs/heads/feat` with `$1=origin` prints `git push origin refs/heads/feat:refs/heads/feat`; a second run with `local_ref` `HEAD~1` prints the full 40-char sha as source and in the per-ref line. 12. remote URL withheld: `$1=https://token@example.invalid/r.git` (not a configured remote); output contains `<remote>` and not `example.invalid`.

**Mutation control (report in the receipt):** print `$1` unconditionally and confirm case 12 goes red; print `local_ref` unconditionally and confirm case 11's `HEAD~1` arm goes red.

**Interfaces:** Consumes Task 1's `pushed_refs`, collected-refs list and refusal block.

---

## Non-goal check

Run 2026-10-22, one fresh reviewer against N1-N5: 5 CLEAR, 0 CONFLICT, 0 UNCLEAR. No resolution needed.

- N1 CLEAR: `git checkout --orphan` (case 7) and `git worktree add` (case 9) build fixtures only; the hook never switches, archives or lists worktrees.
- N2 CLEAR: cases 9-10 export `GIT_DIR`/`GIT_WORK_TREE` through a runner variant; no `REPO_ROOT` seam is added.
- N3 CLEAR: case 83 changes only the commit it pushes (sha1 to sha2), assertions unchanged; `_run_pre_push` extension keeps existing calls argument-free.
- N4 CLEAR: V3 edits ai-config docs and a skill and adds a terraform_ansible Backlog row; neither hook changes.
- N5 CLEAR: the hook reads `git remote`, never `git worktree list`.
