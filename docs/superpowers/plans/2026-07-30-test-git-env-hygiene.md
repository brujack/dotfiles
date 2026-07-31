# Strip Inherited Git Repo-Location Vars — Implementation Plan

> **Status: DONE** — merged as dotfiles#191 (`f13f43d`), 2026-07-31.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore the pre-push test gate for worktree pushes by stripping the four git repo-location vars at the one point where they enter this repo's test suite.

**Architecture:** `scripts/pre-push` gains a single `unset`, placed after the hook's own git resolution and before `make test`. Nothing under `lib/`, `tests/helpers/`, or CI changes. One BATS case asserts the hook clears all four vars before invoking `make`.

**Tech Stack:** bash, BATS 1.10.0 (CI) / 1.14.0 (macOS), GNU make.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-29-test-git-env-hygiene-design.md` at `f4b9e3c`.
- The four vars are exactly `GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE` — same list and order as `lib/git_hooks.sh` uses.
- The `unset` goes **after** the hook's `REPO_ROOT` / `merge-base` / `git diff` resolution. Those calls legitimately want the git environment; only `make test` must not see it.
- Do **not** add an `unset` to `tests/helpers/common.bash`, delete the 15 hand-rolled unsets, add a guard test, or add a CI step. All are explicitly out of scope (spec, Decision 3) and belong to a follow-up hygiene spec.
- Do **not** put the strip in the `Makefile` `test:` target — it would swallow the leak injection that both the spec's Problem section and its Testing table use to reproduce the defect.
- `scripts/pre-push` uses `set -e`; any added command must not spuriously exit non-zero.
- Shell standards: `[[ ]]` not `[ ]`, `${VAR}` braces, `printf` not `echo`.

---

## Verification Planning

**Command that proves the whole change works** — a real worktree push with the hook enabled and no `--no-verify`:

```bash
git worktree add /tmp/verify-wt -b verify-probe
cd /tmp/verify-wt && git commit --allow-empty -m "test: probe" && git push origin verify-probe
```

**Expected:** the hook runs `make test`, the suite passes, the push completes. Before this change the same push produces 90 failures and aborts.

**Measured baseline** (spec Testing table, clone + worktree-of-clone, both leak shapes): `90 not ok, exit 2` before; `0 not ok, 1058 pass, exit 0` after. Residual empty.

**Edge cases exercised by the plan:** the hook still resolves its own `REPO_ROOT`/range correctly with the vars set (Task 1's test runs with all four exported); the new case fails when the `unset` is removed (both-branches rule, `tdd.md`).

---

## Task 1: Strip the four vars in `scripts/pre-push`

```yaml-task
id: 1
description: Add the boundary unset to scripts/pre-push and a BATS case asserting make test sees none of the four vars
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: make test
    exit_code: 0
  - cmd: 'bats tests/scripts/pre_push.bats'
    exit_code: 0
  - cmd: 'grep -q "^unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE$" scripts/pre-push'
    exit_code: 0
max_retries: 3
files_touched:
  - scripts/pre-push
  - tests/scripts/pre_push.bats
depends_on: []
```

**Files:** `scripts/pre-push`, `tests/scripts/pre_push.bats`

**Interfaces:**

- Consumes: existing `pre_push.bats` harness — `CLEAN_PATH`, `REPO_DIR`, `MOCK_CALLS_FILE`, `MAKE_MOCK_DIR`, `_commit_file()`, `_write_make_mock()`.
- Produces: `_write_make_env_mock()` and `_run_pre_push_leaked()` helpers in that file. No production interface.

**Why the existing `_run_pre_push` cannot be reused:** it already runs `unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE` inside its own wrapper, which would mask the behaviour under test. The new case needs a runner that deliberately leaks.

### Steps

- [ ] **Write the failing test.** Append to `tests/scripts/pre_push.bats`:

```bash
_write_make_env_mock() {
  cat > "${MAKE_MOCK_DIR}/make" <<EOF
#!/usr/bin/env bash
printf "make %s\n" "\$*" >> "${MOCK_CALLS_FILE}"
env | grep '^GIT_' >> "${MOCK_CALLS_FILE}" || true
exit 0
EOF
  chmod +x "${MAKE_MOCK_DIR}/make"
}

_run_pre_push_leaked() {
  local _stdin="${1}"
  local _path_with_make="${MAKE_MOCK_DIR}:${CLEAN_PATH}"
  printf "%b" "${_stdin}" | bash -c "
    export PATH='${_path_with_make}'
    export GIT_DIR='${REPO_DIR}/.git'
    export GIT_WORK_TREE='${REPO_DIR}'
    export GIT_COMMON_DIR='${REPO_DIR}/.git'
    export GIT_INDEX_FILE='${REPO_DIR}/.git/index'
    cd '${REPO_DIR}' && bash '${REPO_ROOT}/scripts/pre-push'
  "
}

@test "pre-push clears inherited git repo-location vars before running make test" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file "deploy.sh" "echo hi" "feat: add deploy script")
  _write_make_env_mock
  run _run_pre_push_leaked "refs/heads/master ${local_sha} refs/heads/master ${base_sha}\n"
  [ "$status" -eq 0 ]
  grep -qE "^make -C .* test$" "${MOCK_CALLS_FILE}"
  ! grep -qE "^GIT_(DIR|WORK_TREE|COMMON_DIR|INDEX_FILE)=" "${MOCK_CALLS_FILE}"
}
```

- [ ] **Run it and confirm it fails**, and fails for the right reason: `bats tests/scripts/pre_push.bats -f "clears inherited"`. The failure must be the final `! grep` assertion (the four vars reached `make`), not an earlier one. If `make -C .* test` is what fails, the fixture is wrong, not the code.

- [ ] **Implement.** In `scripts/pre-push`, insert between line 29 (`[[ "${needs_test}" -eq 0 ]] && exit 0`) and line 31 (`printf "Running tests locally..."`):

```bash
# Git exports GIT_DIR into this hook's environment when the push originates
# from a worktree (git-workflow.md's measured table). Everything below runs
# `make test`, and any suite building a git fixture inherits the leak --
# including suites that never source tests/helpers/common.bash. Placed after
# the range resolution above, which legitimately wants the git environment.
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE
```

- [ ] **Run the test and confirm it passes.**
- [ ] **Verify both branches** (`tdd.md`): comment out the `unset`, re-run, confirm the case fails; restore it, confirm it passes. A case that passes either way is worthless.
- [ ] **Run `make test`** — 1059 pass, exit 0.
- [ ] **Commit.** Invoke `caveman:caveman-commit` for the message.

---

## Task 2: Update the test-count figures in `CLAUDE.md`

```yaml-task
id: 2
description: Bump the two recorded test-count figures from 1058 to 1059 (docs-only, no behavior change, so TDD does not apply)
role: executor
model: haiku
tdd: not-applicable
acceptance:
  - cmd: make test
    exit_code: 0
  - cmd: '! grep -q "1058 tests" CLAUDE.md'
    exit_code: 0
  - cmd: 'grep -qE "[0-9]+ tests as of 2026-07-30" CLAUDE.md'
    exit_code: 0
max_retries: 3
files_touched:
  - CLAUDE.md
depends_on: [1]
parallel_group: docs
```

**Files:** `CLAUDE.md`

**Interfaces:** none — documentation only.

### Steps

- [ ] **Line 237** — `verifies test count ≥ 840 (regression proxy; 1058 tests as of 2026-07-29)` → `1059 tests as of 2026-07-30`.
- [ ] **Line 289** — `**Overall: 91%** (1058 tests as of 2026-07-29)` → `1059 tests as of 2026-07-30`.
- [ ] Read the live count first — `grep -rh "^@test" tests/ | wc -l` — and write **that** number, rather than assuming 1059. The gate deliberately does not assert a specific figure: it asserts the stale one is gone and a `2026-07-30`-dated one is present, so it stays correct if Task 1's test count differs or another test lands first.
- [ ] Leave the CI floor at **840** and the coverage gate at **90%** — neither changes.
- [ ] **Commit.** Invoke `caveman:caveman-commit`.

---

## Task 3: Mark the spec done and add the plan index row

```yaml-task
id: 3
description: Set the spec status banner to Done and add an All Plans row (docs-only, no behavior change, so TDD does not apply)
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: make test
    exit_code: 0
  - cmd: 'grep -q "test-git-env-hygiene" docs/superpowers/README.md'
    exit_code: 0
  - cmd: 'grep -q "2026-07-30-test-git-env-hygiene.md" docs/superpowers/README.md'
    exit_code: 0
max_retries: 3
files_touched:
  - docs/superpowers/README.md
  - docs/superpowers/specs/2026-07-29-test-git-env-hygiene-design.md
depends_on: [1]
parallel_group: docs
```

**Files:** `docs/superpowers/README.md`, `docs/superpowers/specs/2026-07-29-test-git-env-hygiene-design.md`

**Interfaces:** none — documentation only.

### Steps

- [ ] In the spec, change `Status: Spec` (line 5) to `Status: Done`.
- [ ] Add a `> **Status: DONE**` banner directly under the spec's H1, per `repo-structure.md`.
- [ ] Add one row to the **All Plans** table in `docs/superpowers/README.md`, matching the existing column layout:

```
| 2026-07-30 | [test-git-env-hygiene](plans/2026-07-30-test-git-env-hygiene.md) | [spec](specs/2026-07-29-test-git-env-hygiene-design.md) | Done |
```

- [ ] Do **not** add a backlog row for the hygiene follow-up here — the spec's Out of scope section already names it, and a duplicate backlog row would drift.
- [ ] **Commit.** Invoke `caveman:caveman-commit`.

---

## Notes for the implementer

**Both spec items are already settled — do not re-run them.** Item 1 (plain vs linked-worktree gitdir) was measured on 2026-07-30: identical 90-failure split under both shapes, so the proxy was faithful. Item 2 (`pre_commit_hook.bats` 2 → 0) was refuted and its argument deleted from the spec. The spec's Testing section records the residual as unexplained, not pending.

**No ADR required.** This adds no Phase 3 gate, no HOLD-capable check, no structural pattern, no storage or schema choice — it restores an existing gate's correctness. `repo-structure.md`'s significance list is not triggered.

**If a manual leak reproduction is needed**, run it against a scratch clone plus a worktree _of that clone_, never the live checkout: `git_hooks.bats:846-900` documents that under a leaked `GIT_DIR`/`GIT_COMMON_DIR`, `install_git_hooks_all_repos` writes hooks into the leaked repo.
