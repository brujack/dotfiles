# git-hooks dry-run summary row Implementation Plan

spec: docs/superpowers/specs/2026-10-24-git-hooks-dry-run-summary-design.md

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `-t update --dry-run` renders `[OK] git-hooks  dry run: install skipped` instead of `[OK] git-hooks  updated`.

**Architecture:** One `git-hooks)` arm in the `case "${_section}"` of `_update_record_end` (`lib/update_summary.sh`), placed after `snap)` and before `*)`. It branches on `_dry_run_active` (`lib/helpers.sh`). The FAIL early return and the SKIP guard above the `case` are unchanged, so rc 1 still renders `[FAIL]`, and `_update_warn` still overwrites the row after an rc-2 sweep.

**Tech Stack:** bash, bats.

## Global Constraints

- No change to `lib/git_hooks.sh` (N3).
- No change to how `git-repos` renders (N1).
- No change to `run_update`'s rc-2→0 ternary (N2).
- Result text is exactly `dry run: install skipped`.

## Verification

- Session-level: `make test` exits 0, run once by the orchestrator after Task 2. Task gates use the single bats file (27 s measured 2026-10-24), not the full suite.
- V1 (orchestrator): before dispatching Task 1, add only the two new tests to a scratch copy of the branch and confirm the dry-run test fails with `result_git-hooks` = `updated` and the non-dry test passes. After Task 1, both pass.
- V2: optional and operator-only. Not run unless asked.

---

### Task 1: git-hooks arm in `_update_record_end`

```yaml-task
id: 1
description: Add a git-hooks arm to _update_record_end that names the skipped install under DRY_RUN, with two tests
role: executor
model: sonnet
tdd: required
requirements: [R1, R2, R3]
acceptance:
  - cmd: 'bats tests/setup_env/update_summary.bats < /dev/null'
    exit_code: 0
  - cmd: 'bats -f "_update_record_end git-hooks" tests/setup_env/update_summary.bats < /dev/null'
    exit_code: 0
    stdout_match: "1\\.\\.2\\n"
  - cmd: make lint
    exit_code: 0
  - cmd: 'git diff --quiet origin/master -- lib/git_hooks.sh lib/workflows.sh'
    exit_code: 0
max_retries: 3
files_touched: [lib/update_summary.sh, tests/setup_env/update_summary.bats]
depends_on: []
```

**Files:** `lib/update_summary.sh`, `tests/setup_env/update_summary.bats`.

**Interfaces:**

- Consumes: `_dry_run_active` (`lib/helpers.sh`; returns 0 when `DRY_RUN` is set to anything except empty, `0`, `false`, `no`).
- Produces: `result_git-hooks` holds `dry run: install skipped` under dry run, `updated` otherwise; `status_git-hooks` is `OK` in both.

- [ ] **Step 1: Write the failing tests.** Add them to `tests/setup_env/update_summary.bats` directly after the test `_update_summary prints a git-hooks row with the literal result production writes, not a fabricated counts string`:

```bash
@test "_update_record_end git-hooks under DRY_RUN records OK and dry run: install skipped" {
  export DRY_RUN=1
  _update_record_end "git-hooks" 0
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_git-hooks")" = "OK" ]
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/result_git-hooks")" = "dry run: install skipped" ]
}

@test "_update_record_end git-hooks without DRY_RUN records updated" {
  # bats inherits the caller's environment; a DRY_RUN exported by the
  # invoking shell would otherwise turn this into a second dry-run case.
  unset DRY_RUN
  _update_record_end "git-hooks" 0
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_git-hooks")" = "OK" ]
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/result_git-hooks")" = "updated" ]
}
```

- [ ] **Step 2: Run** `bats -f "_update_record_end git-hooks" tests/setup_env/update_summary.bats < /dev/null`. Expect the DRY_RUN test to fail (result is `updated`) and the other to pass.

- [ ] **Step 3: Implement.** In `lib/update_summary.sh`, insert this arm between the end of `snap)` (its `;;`) and `*)`:

```bash
    git-hooks)
      # Hook installs go through run_cmd, which only prints under DRY_RUN,
      # so "updated" would claim installs that never ran. The checks did
      # run, so this is OK, not SKIP.
      if _dry_run_active; then
        _result="dry run: install skipped"
      else
        _result="updated"
      fi
      ;;
```

- [ ] **Step 4: Fix the comment that Step 3 makes false.** The test `_update_summary prints a git-hooks row with the literal result production writes, ...` opens with `# _update_record_end has no git-hooks) case arm -- git-hooks falls` / `# through to the generic \`*) _result="updated"\` branch like every other`/`# section without special-cased diffing.` Replace those three lines with:

```bash
  # _update_record_end's git-hooks) arm writes "updated" outside --dry-run
  # (the dry-run text is pinned by the two _update_record_end git-hooks
  # tests below).
```

Leave the rest of that comment and the test body unchanged.

- [ ] **Step 5: Run the acceptance commands** above; all must pass.

- [ ] **Step 6: Commit** both files, message from `caveman:caveman-commit`.

### Task 2: Backlog rows

```yaml-task
id: 2
description: Remove the P2 git-repos/git-hooks dry-run row and add the err_git-hooks note to the no-op row (docs-only, no behavior change)
role: executor
model: haiku
tdd: not-applicable
requirements: [R4, R5]
acceptance:
  - cmd: '! command grep -qF "render \`[OK] … updated\` in the summary table over a dry run that did nothing" docs/superpowers/README.md'
    exit_code: 0
  - cmd: 'command grep -F "| no-op update sections render" docs/superpowers/README.md | command grep -qF "err_git-hooks"'
    exit_code: 0
  - cmd: 'test "$(command grep -cF "| no-op update sections render" docs/superpowers/README.md)" -eq 1'
    exit_code: 0
max_retries: 2
files_touched: [docs/superpowers/README.md]
depends_on: [1]
```

**Files:** `docs/superpowers/README.md` only. Not read by the suite, so no `make test` gate.

- [ ] **Step 1 (R4):** Under `### P2 — bugs and security`, delete the whole table row that begins ``| `git-repos` and `git-hooks` render `[OK] … updated` in the summary table over a dry run that did nothing |``. Delete only that one line.
- [ ] **Step 2 (R5):** Under `### P3 — bugs and security`, find the row beginning `` | no-op update sections render `updated` ``. In its second cell, after the sentence ending `would say \`no changes\`.`, insert this sentence (keep the cell's trailing padding and the closing `|`):

  ``For `git-hooks` the counts already exist: `run_update` tees the sweep into `err_git-hooks`, whose `<N> checked, <M> updated` line an arm can read without touching `lib/git_hooks.sh`.``

  Do not add a new row.

- [ ] **Step 3:** Run the acceptance commands; all must pass.
- [ ] **Step 4:** Commit, message from `caveman:caveman-commit`.

### Orchestrator, after Task 2

- [ ] `make test < /dev/null` exits 0 (run in background; full suite exceeds the Bash cap).
- [ ] Phase 3 via `finishing-a-development-branch`.

## Non-goal check

Reviewer (fresh subagent, 2026-10-24): N1 CLEAR, N2 CLEAR, N3 CLEAR. No plan revision.

- N1: "Task 1 adds only a `git-hooks)` arm to the case statement."
- N2: "No step touches `run_update`."
- N3: "Not in `files_touched`. Task 1's acceptance check also runs `git diff --quiet ... lib/git_hooks.sh`."

Side note from the reviewer, not a non-goal finding: deleting the P2 row leaves `git-repos` untracked. No change: `[OK] git-repos` under `--dry-run` is truthful by the 2026-09-14 spec §2 decision (fetch and `pull --ff-only` run for real), and the P3 row "no-op update sections render `updated`" already names `git-repos` for the non-dry no-op case.
