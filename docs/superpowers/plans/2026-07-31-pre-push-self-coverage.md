# pre-push Self-Coverage Implementation Plan

> **Status: DONE** — merged as PR dotfiles#195 (2026-08-01), though not as planned; see the supersession banner below.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Scope note (Phase 3):** `bug-scan` found the same defect class for `.zsh` files —
> `tests/zshrc.d/unit.bats` covers all 7 `.config/.zshrc.d/*.zsh` files with `zsh -n`,
> but none of them triggered the hook. The user approved folding it in, so the shipped
> change also extends the extension group to `\.(sh|bats|zsh)$` and adds two more BATS
> cases (a `.zsh` positive and a `.zshrc` negative pinning the deliberate exclusion).
> **Superseded during Phase 3.** The allowlist this plan implements was abandoned
> before merge. Four missed `make test` dependency classes — each found by a different
> gate, the fourth *after* an exhaustive 392-file enumeration declared the set closed —
> established that the shape was the defect. The shipped hook fails closed instead: the
> suite runs unless every changed path is provably inert. See
> [ADR-0017](../../adr/0017-pre-push-trigger-fail-closed.md) and the spec's
> supersession note.
>
> Consequently this plan's Task 1 acceptance gate (`grep -c ^@test ... -eq 10`) and its
> "three BATS cases" scope no longer describe the merged result: 36 cases in that file,
> 1128 repo-wide. Retained as the record of what was planned, not as a description of
> what shipped.

**Goal:** Make `scripts/pre-push` trigger `make test` when the only changed files are the extensionless hook scripts, so the local gate covers the files that implement it.

**Architecture:** One alternation added to the hook's trigger regex, plus three BATS cases that pin the new behavior and the `^` anchor. No new files, no new functions, no consumer changes.

**Tech Stack:** bash, BATS, GNU grep ERE.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-31-git-hook-detection-gaps-design.md`
- `scripts/pre-push` is installed by `make install-hooks` via `ln -sf` in this repo — the installed hook is a **symlink**, so edits take effect immediately and no reinstall step is required (`ci.md`'s copy-vs-symlink check; verified for this repo).
- `scripts/pre-push` is not instrumented by `scripts/run-bash-coverage.sh`, so this change cannot move the bash coverage figure in either direction.
- Do not touch `lib/git_hooks.sh` or `lib/helpers.sh` — the `core.hooksPath` work was split out of this spec and is a backlog item.

---

## Session-Level Verification

Beyond the per-task gate:

1. `make test` passes with **3 more tests than the pre-change count** (1099 → 1102).
2. `bash -n scripts/pre-push && zsh -n scripts/pre-push` both exit 0 — the hook is sourced by neither, but this repo lints every shell file under both.
3. **The end-to-end check that can actually fail:** on the feature branch, make a scratch commit touching _only_ `scripts/pre-push` (e.g. append a trailing comment), push it, and confirm `Running tests locally (pre-push)...` appears. Then reset the scratch commit. Do **not** claim this verified by the push of the real change — that push also touches `tests/**`, which matches the _old_ regex, so it would run the suite either way and prove nothing.

Edge case that must be exercised: a path containing `scripts/` but not at the start (`docs/scripts/notes.md`) must **not** trigger. Without it, a regex written as `scripts/` instead of `^scripts/` passes every other test.

---

## Task 1: Add `^scripts/` to the pre-push trigger regex

```yaml-task
id: 1
description: Add ^scripts/ to the pre-push trigger regex so edits to the extensionless hook scripts run the suite, with BATS cases pinning both the new matches and the ^ anchor
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: make test
    exit_code: 0
  - cmd: make lint
    exit_code: 0
  - cmd: 'grep -q "\^scripts/" scripts/pre-push'
    exit_code: 0
  - cmd: 'bash -c "test \"$(grep -c ^@test tests/scripts/pre_push.bats)\" -eq 10"'
    exit_code: 0
max_retries: 3
files_touched:
  - scripts/pre-push
  - tests/scripts/pre_push.bats
depends_on: []
```

**Files:**

- `tests/scripts/pre_push.bats` — one helper change, three new cases
- `scripts/pre-push` — one line

**Interfaces:**

- Consumes: nothing from earlier tasks (first and only task).
- Produces: nothing later tasks rely on.

### Steps

- [ ] **Extend `_commit_file` to create parent directories.** The helper at
      `tests/scripts/pre_push.bats:33` writes `> "${REPO_DIR}/${_path}"`, which fails
      for any path with a directory component. All three new cases need one. Change the
      `printf` line inside the `bash -c` block from:

      ```bash
              printf '%s\n' '${_content}' > '${REPO_DIR}/${_path}'
          ```

          to:

          ```bash
              mkdir -p \"\$(dirname '${REPO_DIR}/${_path}')\"
              printf '%s\n' '${_content}' > '${REPO_DIR}/${_path}'
          ```

          This is benign for the existing seven cases — every one of them passes a
          bare filename, where `dirname` yields `${REPO_DIR}` itself and `mkdir -p` is a
          no-op.

- [ ] **Write the three failing tests.** Append to `tests/scripts/pre_push.bats`,
      after the existing `@test` at line 71:

      ```bash
          @test "pre-push runs make test when only scripts/pre-push changed" {
            base_sha=$(_commit_file "README.md" "v1" "docs: v1")
            local_sha=$(_commit_file "scripts/pre-push" "# hook" "chore: touch hook")
            _write_make_mock 0
            run _run_pre_push "refs/heads/master ${local_sha} refs/heads/master ${base_sha}\n"
            [ "$status" -eq 0 ]
            grep -qE "^make -C .* test$" "${MOCK_CALLS_FILE}"
          }

          @test "pre-push runs make test when only scripts/commit-msg changed" {
            base_sha=$(_commit_file "README.md" "v1" "docs: v1")
            local_sha=$(_commit_file "scripts/commit-msg" "# hook" "chore: touch hook")
            _write_make_mock 0
            run _run_pre_push "refs/heads/master ${local_sha} refs/heads/master ${base_sha}\n"
            [ "$status" -eq 0 ]
            grep -qE "^make -C .* test$" "${MOCK_CALLS_FILE}"
          }

          @test "pre-push skips when scripts/ appears mid-path, not at the start" {
            base_sha=$(_commit_file "README.md" "v1" "docs: v1")
            local_sha=$(_commit_file "docs/scripts/notes.md" "notes" "docs: notes")
            _write_make_mock 0
            run _run_pre_push "refs/heads/master ${local_sha} refs/heads/master ${base_sha}\n"
            [ "$status" -eq 0 ]
            [ ! -f "${MOCK_CALLS_FILE}" ]
          }
          ```

          The third case is the anchor guard: it passes both before and after the change,
          and fails only if the alternation is written as `scripts/` without `^`. It is
          deliberately not a `.gitignore` case — the existing test at line 55 already
          covers a plain non-triggering file, so a `.gitignore` case would add no
          discrimination.

- [ ] **Run them and confirm the right two fail for the right reason.**

      ```bash
          bats tests/scripts/pre_push.bats
          ```

          Expected: the two `scripts/…` cases fail on `grep -qE "^make -C .* test$"`
          because `${MOCK_CALLS_FILE}` does not exist — the hook exited 0 at line 29
          without invoking make. The mid-path case must **pass** already. If it fails,
          stop: the harness is wrong, not the hook.

- [ ] **Make the change.** In `scripts/pre-push`, line 24, change:

      ```bash
              if git diff --name-only "${range}" | grep -qE '\.(sh|bats)$|^Makefile$|^tests/'; then
          ```

          to:

          ```bash
              if git diff --name-only "${range}" | grep -qE '\.(sh|bats)$|^Makefile$|^scripts/|^tests/'; then
          ```

          Alternation only. Do not reorder or reformat the existing alternatives.

- [ ] **Run the suite.**

      ```bash
          bats tests/scripts/pre_push.bats && make test
          ```

          Expected: 10 tests in `pre_push.bats`, all passing; `make test` green overall.

- [ ] **Lint.** `make lint` — exits 0.

- [ ] **Commit.** Invoke `caveman:caveman-commit` to generate the message before
      running `git commit`. Subject ≤50 chars, `fix(pre-push):` type.

---

## Notes for Phase 3

- `docs/superpowers/README.md` already carries the All Plans row for this spec; set its
  status to **Done** and add the `> **Status: DONE**` banner to this plan file once the
  PR merges.
- The spec's "Gap 2, and why it left this spec" section and both Multi-Lens Review
  rounds are history, not open work — do not treat them as unimplemented scope.
- CLAUDE.md's Testing section records the test count (1099 as of 2026-07-31) and the
  CI floor assertion (`≥ 840`). Update the count to 1102. The floor does not move.
