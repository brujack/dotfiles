# PR Review Gate Implementation Plan

**Goal:** Insert the `pr-review` skill as a mandatory gate into the `finishing-a-development-branch` Option 2 workflow (push and create PR), and add a durable backup rule to `~/.claude/CLAUDE.md`.

**Architecture:** The gate runs after tests pass but before push. HOLD verdicts trigger an automatic fix loop with escalation after two failed fix attempts. WARNING and INFO findings are advisory only.

**Tech Stack:** Claude plugins (superpowers finishing-a-development-branch skill), bash configuration

---

## Task 1: Insert PR Review Gate into finishing-a-development-branch SKILL.md

**Files:**
- Modify: `~/.claude/plugins/cache/claude-plugins-official/superpowers/<version>/skills/finishing-a-development-branch/SKILL.md`

**Steps:**

1. Locate Step 1 "Run test suite" in the skill file
2. After "If tests pass: Continue to Step 3" block, insert a new "Step 2b: PR Review Gate (Option 2 only)" section
3. The section must:
   - Run pr-review skill when user selects Option 2
   - On PASS verdict: proceed to push + PR creation
   - On HOLD verdict: enter fix loop (show findings → fix → test → commit → re-review)
   - After 2 failed fix attempts on same CRITICAL: escalate to user
   - Treat WARNING and INFO as advisory only

**Acceptance Criteria:**
- Step 2b appears after test verification in the skill file
- Step 2b only applies to Option 2
- Code review happens before `git push`

---

## Task 2: Add PR Review Gate section to ~/.claude/CLAUDE.md

**Files:**
- Modify: `~/.claude/CLAUDE.md`

**Steps:**

1. Locate the "Feature Branches" section in CLAUDE.md
2. After the main feature branch instructions, add new subsection "### PR Review Gate"
3. Subsection must state:
   - Run pr-review skill before pushing any feature branch (Option 2)
   - Only push on PASS verdict
   - On HOLD: fix CRITICAL findings → make test → commit → re-run pr-review
   - Repeat until PASS, or escalate after two failed fix attempts
   - WARNING and INFO are advisory

**Acceptance Criteria:**
- "### PR Review Gate" section exists in Feature Branches
- Rule is explicit and matches the skill behavior
- Acts as durable backup surviving plugin updates

---

## Task 3: Update docs/superpowers/README.md plan index

**Files:**
- Modify: `docs/superpowers/README.md`

**Steps:**

1. Add a new row to the All Plans table after the last existing row
2. Row format: `| 2026-04-14 | [pr-review-gate](plans/2026-04-14-pr-review-gate.md) | [spec](specs/2026-04-14-pr-review-gate-design.md) | In Progress |`
3. Update status to Done once all three tasks are complete and PR merges

**Acceptance Criteria:**
- New row appears in All Plans table
- Date and links are correct
- Status is set to Done when PR merges
