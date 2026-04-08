# Plan Hygiene and Status Tracking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Update the two Cursor spec docs to reflect current status and add an active roadmap section to `docs/cursor/specs/README.md` that points to the superpowers specs and plans.

**Architecture:** Documentation-only changes. No code modified.

**Tech Stack:** Markdown

---

## File Map

| Action | File |
|---|---|
| Modify | `docs/cursor/specs/2026-03-31-dotfiles-improvements-plan.md` |
| Modify | `docs/cursor/specs/2026-04-08-dotfiles-next-steps-plan.md` |
| Modify | `docs/cursor/specs/README.md` |

---

### Task 1: Update `2026-03-31-dotfiles-improvements-plan.md`

**Files:**
- Modify: `docs/cursor/specs/2026-03-31-dotfiles-improvements-plan.md`

- [ ] **Step 1: Read the file**

Read `docs/cursor/specs/2026-03-31-dotfiles-improvements-plan.md` in full.

- [ ] **Step 2: Update the status field**

Change the `**Status:**` line from:

```markdown
**Status:** Partially Completed
```

to:

```markdown
**Status:** Superseded — see `docs/cursor/specs/2026-04-08-dotfiles-next-steps-plan.md`
```

- [ ] **Step 3: Update the Current Status section**

The "Current Status" section currently says:

```markdown
## Current Status

This plan is partially completed. Major modularization and profile/capability migration work has landed.

For the active continuation plan, see:

- `docs/cursor/specs/2026-04-08-dotfiles-next-steps-plan.md`
```

Update it to:

```markdown
## Current Status

This plan is superseded. All phases were either completed or subsumed into superpowers-tracked work.

**Completed work (as of 2026-04-08):**
- Phase 0: Baseline tests and CI established
- Phase 1: `lib/` modularization complete (`constants`, `helpers`, `detect_env`, `macos`, `linux`, `developer`)
- Phase 2: Idempotency hardening via `safe_link()` and structured logging
- Phase 3: Profile/capability model (`config/profiles.sh`, `HAS_*` vars, `PROFILE` map)
- Phase 4: CI gate active (lint + BATS tests + auto-merge)
- Phase 5: Partially complete — docs updated for profile model, lib architecture documented

**Remaining work is tracked in:**
- `docs/cursor/specs/2026-04-08-dotfiles-next-steps-plan.md`
- `docs/superpowers/specs/` and `docs/superpowers/plans/`
```

- [ ] **Step 4: Commit**

```bash
git add docs/cursor/specs/2026-03-31-dotfiles-improvements-plan.md
git commit -m "docs: mark 2026-03-31 improvements plan as superseded with completion summary

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 2: Update `2026-04-08-dotfiles-next-steps-plan.md`

**Files:**
- Modify: `docs/cursor/specs/2026-04-08-dotfiles-next-steps-plan.md`

- [ ] **Step 1: Read the file**

Read `docs/cursor/specs/2026-04-08-dotfiles-next-steps-plan.md` in full.

- [ ] **Step 2: Update the status field**

Change the `**Status:**` line from:

```markdown
**Status:** Draft
```

to:

```markdown
**Status:** Active — implementation tracked in `docs/superpowers/specs/` and `docs/superpowers/plans/`
```

- [ ] **Step 3: Add reference table after the Goals section**

After the `## Goals` section, add a new section:

```markdown
## Implementation Tracking

Each step from this plan has a corresponding spec and implementation plan in `docs/superpowers/`:

| Step | Spec | Plan | Status |
|---|---|---|---|
| Step 1: Workflows extraction | [spec](../../superpowers/specs/2026-04-08-workflows-extraction-design.md) | [plan](../../superpowers/plans/2026-04-08-workflows-extraction.md) | Pending |
| Step 2: Doctor + dry-run | [spec](../../superpowers/specs/2026-04-08-doctor-dry-run-design.md) | [plan](../../superpowers/plans/2026-04-08-doctor-dry-run.md) | Pending |
| Step 3: Secrets guardrails | [spec](../../superpowers/specs/2026-04-08-secrets-guardrails-design.md) | [plan](../../superpowers/plans/2026-04-08-secrets-guardrails.md) | Pending |
| Step 4: CI safety | [spec](../../superpowers/specs/2026-04-08-ci-safety-design.md) | [plan](../../superpowers/plans/2026-04-08-ci-safety.md) | Pending |
| Step 5: Plan hygiene | [spec](../../superpowers/specs/2026-04-08-plan-hygiene-design.md) | [plan](../../superpowers/plans/2026-04-08-plan-hygiene.md) | In Progress |
```

Update the `Status` column for each step as work completes.

- [ ] **Step 4: Commit**

```bash
git add docs/cursor/specs/2026-04-08-dotfiles-next-steps-plan.md
git commit -m "docs: update next-steps plan status and add superpowers tracking table

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 3: Add active roadmap to `docs/cursor/specs/README.md`

**Files:**
- Modify: `docs/cursor/specs/README.md`

- [ ] **Step 1: Read the file**

Read `docs/cursor/specs/README.md` in full.

- [ ] **Step 2: Add Active Roadmap section**

Append to the end of `docs/cursor/specs/README.md`:

```markdown
## Active Roadmap

Current work items tracked in `docs/superpowers/`:

| Item | Spec | Plan | Status |
|---|---|---|---|
| Workflows extraction | [spec](../../superpowers/specs/2026-04-08-workflows-extraction-design.md) | [plan](../../superpowers/plans/2026-04-08-workflows-extraction.md) | Pending |
| Doctor + dry-run | [spec](../../superpowers/specs/2026-04-08-doctor-dry-run-design.md) | [plan](../../superpowers/plans/2026-04-08-doctor-dry-run.md) | Pending |
| Secrets guardrails | [spec](../../superpowers/specs/2026-04-08-secrets-guardrails-design.md) | [plan](../../superpowers/plans/2026-04-08-secrets-guardrails.md) | Pending |
| CI safety pass | [spec](../../superpowers/specs/2026-04-08-ci-safety-design.md) | [plan](../../superpowers/plans/2026-04-08-ci-safety.md) | Pending |

For history, see `2026-03-31-dotfiles-improvements-plan.md` (superseded) and `2026-04-08-dotfiles-next-steps-plan.md` (active, links to above).
```

- [ ] **Step 3: Commit**

```bash
git add docs/cursor/specs/README.md
git commit -m "docs: add active roadmap section to docs/cursor/specs/README.md

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```
