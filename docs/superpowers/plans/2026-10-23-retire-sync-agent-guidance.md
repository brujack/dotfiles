# Retire sync-agent-guidance Implementation Plan

> **Status: DONE** — merged as dotfiles#367 (6093ef4a), 2026-10-24.

spec: docs/superpowers/specs/2026-10-23-retire-sync-agent-guidance-design.md

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Delete `scripts/sync-agent-guidance.sh`, its tests, its two `make` targets and every live reference to it, closing two Backlog rows.

**Architecture:** Pure deletion plus three wording edits. No behaviour is added, so there is no RED test; the gates prove each reference is gone and that the suite and lint stay green.

**Tech Stack:** bash, GNU make, bats.

## Global Constraints

- No edit to `docs/adr/`, to dated specs or plans other than this plan and its spec, to `docs/knowledge/retrospectives/`, or to the two `tests/scripts/unit.bats` heredoc comments (spec N1).
- No code that deletes the gitignored `.cursor/rules/global-claude-standards.mdc` (spec N2).
- No change to ai-config (spec N3); its one Layout line is a post-merge orchestrator step.
- Fixture Makefile strings in `tests/scripts/docs_inert_premise.bats` that use `check-agent-guidance` as a target name stay unchanged, as does every test in that file.

## Verification

- `make test` (orchestrator, once, after Task 1): passes; plan count is master's minus 17 (master: `1..3386`, so `1..3369`).
- `make check-agent-guidance` exits 2 with `No rule to make target`.
- `git grep -n -e sync-agent-guidance -e check-agent-guidance` hits only N1's dated records, the spec, this plan and the fixture strings in `docs_inert_premise.bats`.
- CI `bash-coverage` at least 91% (sanity check only; the script measured 88%, below the total).

---

### Task 1: Delete the tool and its live references

```yaml-task
id: 1
description: Delete sync-agent-guidance script, tests, make targets and live references (deletion only, no new behaviour, so no RED test)
role: executor
model: sonnet
tdd: not-applicable
requirements: [R1, R2, R3, R4, R5, R6]
acceptance:
  - cmd: 'test ! -e scripts/sync-agent-guidance.sh && test ! -e tests/scripts/sync_agent_guidance.bats'
    exit_code: 0
  - cmd: '! git grep -q -e sync-agent-guidance -e check-agent-guidance -- Makefile README.md CLAUDE.md scripts/sync-requirements-ci.sh'
    exit_code: 0
  - cmd: '! command grep -qE "^\| (sync-agent-guidance with zero standards imports|`check-agent-guidance` cannot pass in a worktree) " docs/superpowers/README.md'
    exit_code: 0
  - cmd: '! command grep -qE "sync-agent-guidance|_OVERRIDE_CLAUDE_MD_PATH|known reader" tests/scripts/docs_inert_premise.bats'
    exit_code: 0
  - cmd: 'make check-agent-guidance'
    exit_code: 2
    stderr_match: 'No rule to make target'
  - cmd: 'make lint'
    exit_code: 0
  - cmd: 'bats tests/scripts/docs_inert_premise.bats tests/scripts/makefile_lint_scope.bats < /dev/null'
    exit_code: 0
max_retries: 3
files_touched: [scripts/sync-agent-guidance.sh, tests/scripts/sync_agent_guidance.bats, Makefile, README.md, CLAUDE.md, scripts/sync-requirements-ci.sh, tests/scripts/docs_inert_premise.bats, docs/superpowers/README.md]
depends_on: []
```

**Steps:**

- [ ] `git rm scripts/sync-agent-guidance.sh tests/scripts/sync_agent_guidance.bats`.
- [ ] `Makefile`: remove `sync-agent-guidance check-agent-guidance` from the `.PHONY` line (keep every other name in order); delete the two `help` printf lines naming them; delete both target blocks (`sync-agent-guidance:` and `check-agent-guidance:` with their recipe lines) and one of the blank lines that separated them, so the file keeps single blank lines between targets.
- [ ] `README.md`: delete the two lines `make sync-agent-guidance  # ...` and `make check-agent-guidance # ...` in the make-targets code block.
- [ ] `CLAUDE.md`: delete the two Testing lines starting `**Sync agent guidance:**` and `**Check agent guidance drift:**`. Touch nothing else.
- [ ] `scripts/sync-requirements-ci.sh`: the header reads ``# `sync` writes them; `check` fails if a committed copy has drifted. Same shape`` / `# as sync-agent-guidance.sh.` Make it the single line ``# `sync` writes them; `check` fails if a committed copy has drifted.``
- [ ] `tests/scripts/docs_inert_premise.bats` lines 35-36: replace the two-line example with `#   - reads done by scripts a test invokes, e.g. a script that falls back to the` / `#     real CLAUDE.md when its override seam is unset`. Line 173: replace the hint with `printf 'A target that reads a tracked .md (CLAUDE.md included) must not be a prerequisite.\n' >&2`. No other change in this file.
- [ ] `docs/superpowers/README.md`: delete the Backlog row starting `| sync-agent-guidance with zero standards imports |` and the row starting ``| `check-agent-guidance` cannot pass in a worktree``. Delete whole lines only.
- [ ] Run the acceptance gates. `make check-agent-guidance` already exits 2 on the base tree (make reports the script's exit 1 as 2); only its `No rule to make target` stderr shows the target is gone. Do not run `make test`; the orchestrator runs it once after this task.
- [ ] Commit with exact paths (`git add` each file; `git rm` already staged the deletions); message via `caveman:caveman-commit`, e.g. `chore: retire sync-agent-guidance`.

**Interfaces:**

- Consumes: nothing.
- Produces: a tree with no `sync-agent-guidance` or `check-agent-guidance` make target.

## Non-goal check

Fresh reviewer, 2026-10-23: 3 CLEAR, 0 CONFLICT, 0 UNCLEAR.

- **N1** CLEAR: Task 1 touches no dated record; its files are `Makefile`, `README.md`, `CLAUDE.md`, `scripts/sync-requirements-ci.sh`, `tests/scripts/docs_inert_premise.bats`, `docs/superpowers/README.md` and the two deleted files. Resolution: none needed.
- **N2** CLEAR: the only deletion is `git rm` of the script and its bats file; nothing deletes `.cursor/rules/global-claude-standards.mdc`. Resolution: none needed.
- **N3** CLEAR: every path is in dotfiles; the ai-config Layout line is a post-merge orchestrator step. Resolution: none needed.
