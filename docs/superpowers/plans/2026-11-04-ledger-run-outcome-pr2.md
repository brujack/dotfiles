# Ledger Run Outcome PR2 Implementation Plan (state-ledger display)

> **Status: DONE** (state-ledger#37, merged 2026-11-04)

spec: docs/superpowers/specs/2026-11-04-ledger-run-outcome-design.md
scope: PR2

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `ledger history` and `ledger status` show each entry's run type and its status from `outcome`, so a failed dotfiles run is findable at the console. The README documents `outcome` and `recreate_ruby`.

**Repo:** state-ledger (default branch `main`). The plan lives in dotfiles beside its spec. All implementation happens in the worktree `/home/bruce/git-repos/personal/state-ledger-wt-outcome` on branch `feat/display-run-outcome`. Never touch the main checkout: it is the live CMDB, and `ledger write` from any tool runs `git add -A` there.

**Architecture:** Two pure helpers in `scripts/ledger.py`, `_entry_status(entry) -> str` and `_entry_run_type(entry) -> str`, used by `cmd_history` and `cmd_status` in place of the inline `"OK" if entry.get("success") else "FAILED"`.

**Tech Stack:** Python 3 (3.9-compatible, `tests/test_py39_compat.py`), unittest-style tests run by pytest, ruff.

## Global Constraints

- `_validate_entry` is unchanged, and no field becomes required: entries without `outcome` or `run_type` stay valid and display (N1).
- Status rule (R6): `entry["outcome"].upper()` when `outcome` is exactly `"ok"` or `"failed"`; otherwise `"OK"` if `success` is truthy, else `"FAILED"`. Any other `outcome` value (`"partial"`, `5`, `None`, a list) falls back to `success` and never raises.
- Run type: `run_type` when it is a non-empty string, else `-`.
- Output formats (exact):
  - history: `f"{ts[:19]}  {run_type:<13}  {status:<6}  run={run_id[:8]}"`
  - status: `f"{t:12} {eid:40} {started[:19]}  {run_type:<13}  {status}  known_good={kg}"` plus the existing optional `  promoted_at=...`
- No other command's output changes. `cmd_drift` is untouched.

## Verification

- `make test` and `make coverage` (floor 90) exit 0 in the worktree.
- After merge: `ledger history dotfiles/ee76a031-9c5d-4c2f-b763-ef24238e462a | tail -3` on `claude` shows `update` and `OK` or `FAILED` on the newest line, and `ledger status` shows a run type column.
- Edge cases covered by tests: `outcome` `ok`, `failed`, absent, malformed (`"partial"`, `5`); `run_type` present and absent; `success` false with `outcome` `ok` (outcome wins).

### Task 1: Display run type and outcome-derived status

```yaml-task
id: 1
description: Add _entry_status and _entry_run_type and use them in cmd_history and cmd_status
role: executor
model: sonnet
tdd: required
requirements: [R6]
acceptance:
  - cmd: make -C /home/bruce/git-repos/personal/state-ledger-wt-outcome test
    exit_code: 0
  - cmd: make -C /home/bruce/git-repos/personal/state-ledger-wt-outcome coverage
    exit_code: 0
max_retries: 3
files_touched:
  - scripts/ledger.py
  - tests/test_ledger_read.py
depends_on: []
```

**Files:**

- Modify: `scripts/ledger.py` (`cmd_status`, `cmd_history`; new helpers just above `cmd_status`)
- Test: `tests/test_ledger_read.py` (new `TestEntryStatus`, `TestEntryRunType`; new cases in `TestCmdHistory` and `TestCmdStatus`)

**Interfaces:**

- Produces: `_entry_status(entry: dict) -> str` returning `"OK"` or `"FAILED"`; `_entry_run_type(entry: dict) -> str` returning the run type or `"-"`.

- [ ] Write failing unit tests for `_entry_status`: `outcome` `"ok"` with `success` false gives `OK`; `"failed"` with `success` true gives `FAILED`; absent `outcome` follows `success` both ways; `"partial"`, `5` and `None` follow `success`.
- [ ] Write failing unit tests for `_entry_run_type`: `"update"` gives `update`; absent, `""` and a non-string give `-`.
- [ ] Write failing `cmd_history` tests: an entry with `run_type` `"setup"` and `outcome` `"failed"` prints a line containing `setup` and `FAILED`; an entry with neither field prints `-` and the `success`-derived status. Assert the exact line for one case.
- [ ] Write failing `cmd_status` tests: same two cases, asserting the run type and status appear in order before `known_good=`.
- [ ] Run `python3 -m pytest tests/test_ledger_read.py -q` and confirm the new tests fail for the missing helpers.
- [ ] Implement the helpers and wire them in; keep the existing tests green.
- [ ] Run the acceptance gates; commit (`caveman:caveman-commit`).

### Task 2: README documents outcome and recreate_ruby

```yaml-task
id: 2
description: Document the outcome field and add the recreate_ruby run_type row in README.md (docs-only, no behavior change)
role: executor
model: haiku
tdd: not-applicable
requirements: [R7]
acceptance:
  - cmd: 'grep -q "| \`outcome\`" /home/bruce/git-repos/personal/state-ledger-wt-outcome/README.md'
    exit_code: 0
  - cmd: 'grep -q "| \`recreate_ruby\`" /home/bruce/git-repos/personal/state-ledger-wt-outcome/README.md'
    exit_code: 0
max_retries: 2
files_touched:
  - README.md
depends_on: [1]
```

**Files:**

- Modify: `README.md` (the `#### Base fields` area and the `#### \`run_type\` values` table)

- [ ] After the base-fields table, add a `#### Optional fields — dotfiles` table with one row: `outcome` | string | `"ok"` when the run function returned 0, `"failed"` otherwise. Written by dotfiles since dotfiles#426; older entries lack it. `ledger history`/`status` display it, falling back to `success` when absent or unrecognised.
- [ ] The base-fields intro says "All fields are present in every entry"; leave it, since `outcome` is listed separately as optional.
- [ ] Add `| \`recreate_ruby\` | \`run_recreate_ruby()\` | Ruby teardown and rebuild |`after the`recreate_venv` row.
- [ ] Update the `ledger history`/`status` usage examples in README, if they show output lines, to the new formats from Global Constraints.
- [ ] Run the acceptance greps, then `make -C <worktree> lint`; commit.

## Non-goal check

- N1: Task 1 touches no validation code; Task 2 lists `outcome` as optional. Pass.
- N2: Task 2 leaves the `success` row's meaning ("returned exit 0") unchanged. Pass.
- N6: the display maps an unrecognised `outcome` such as `"partial"` to the `success` status; it adds no value. Pass.
- N3 to N5 constrain the dotfiles writer (PR1, merged); this plan touches no dotfiles code. Pass.
