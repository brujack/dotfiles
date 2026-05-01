# Plan Hygiene and Status Tracking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Update the two Cursor spec docs to reflect current status, add an active roadmap section to `docs/cursor/specs/README.md`, and create `docs/superpowers/README.md` as a master status index for all superpowers specs and plans.

**Architecture:** Documentation-only changes. No code modified.

**Tech Stack:** Markdown

---

## File Map

| Action | File                                                         |
| ------ | ------------------------------------------------------------ |
| Modify | `docs/cursor/plans/2026-03-31-dotfiles-improvements-plan.md` |
| Modify | `docs/cursor/plans/2026-04-08-dotfiles-next-steps-plan.md`   |
| Modify | `docs/cursor/specs/README.md`                                |
| Create | `docs/superpowers/README.md`                                 |

---

### Task 1: Update `2026-03-31-dotfiles-improvements-plan.md`

**Files:**

- Modify: `docs/cursor/plans/2026-03-31-dotfiles-improvements-plan.md`

- [ ] **Step 1: Read the file**

Read `docs/cursor/plans/2026-03-31-dotfiles-improvements-plan.md` in full.

- [ ] **Step 2: Update the status field**

Change the `**Status:**` line from:

```markdown
**Status:** Partially Completed
```

to:

```markdown
**Status:** Superseded — see `docs/cursor/plans/2026-04-08-dotfiles-next-steps-plan.md`
```

- [ ] **Step 3: Update the Current Status section**

The "Current Status" section currently says:

```markdown
## Current Status

This plan is partially completed. Major modularization and profile/capability migration work has landed.

For the active continuation plan, see:

- `docs/cursor/plans/2026-04-08-dotfiles-next-steps-plan.md`
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

- `docs/cursor/plans/2026-04-08-dotfiles-next-steps-plan.md`
- `docs/superpowers/specs/` and `docs/superpowers/plans/`
```

- [ ] **Step 4: Commit**

```bash
git add docs/cursor/plans/2026-03-31-dotfiles-improvements-plan.md
git commit -m "docs: mark 2026-03-31 improvements plan as superseded with completion summary

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 2: Update `2026-04-08-dotfiles-next-steps-plan.md`

**Files:**

- Modify: `docs/cursor/plans/2026-04-08-dotfiles-next-steps-plan.md`

- [ ] **Step 1: Read the file**

Read `docs/cursor/plans/2026-04-08-dotfiles-next-steps-plan.md` in full.

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

| Step                         | Spec                                                                      | Plan                                                               | Status      |
| ---------------------------- | ------------------------------------------------------------------------- | ------------------------------------------------------------------ | ----------- |
| Step 1: Workflows extraction | [spec](../../superpowers/specs/2026-04-08-workflows-extraction-design.md) | [plan](../../superpowers/plans/2026-04-08-workflows-extraction.md) | Pending     |
| Step 2: Doctor + dry-run     | [spec](../../superpowers/specs/2026-04-08-doctor-dry-run-design.md)       | [plan](../../superpowers/plans/2026-04-08-doctor-dry-run.md)       | Pending     |
| Step 3: Secrets guardrails   | [spec](../../superpowers/specs/2026-04-08-secrets-guardrails-design.md)   | [plan](../../superpowers/plans/2026-04-08-secrets-guardrails.md)   | Done        |
| Step 4: CI safety            | [spec](../../superpowers/specs/2026-04-08-ci-safety-design.md)            | [plan](../../superpowers/plans/2026-04-08-ci-safety.md)            | Pending     |
| Step 5: Plan hygiene         | [spec](../../superpowers/specs/2026-04-08-plan-hygiene-design.md)         | [plan](../../superpowers/plans/2026-04-08-plan-hygiene.md)         | In Progress |
```

Update the `Status` column for each step as work completes.

- [ ] **Step 4: Commit**

```bash
git add docs/cursor/plans/2026-04-08-dotfiles-next-steps-plan.md
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

| Item                 | Spec                                                                      | Plan                                                               | Status  |
| -------------------- | ------------------------------------------------------------------------- | ------------------------------------------------------------------ | ------- |
| Workflows extraction | [spec](../../superpowers/specs/2026-04-08-workflows-extraction-design.md) | [plan](../../superpowers/plans/2026-04-08-workflows-extraction.md) | Pending |
| Doctor + dry-run     | [spec](../../superpowers/specs/2026-04-08-doctor-dry-run-design.md)       | [plan](../../superpowers/plans/2026-04-08-doctor-dry-run.md)       | Pending |
| Secrets guardrails   | [spec](../../superpowers/specs/2026-04-08-secrets-guardrails-design.md)   | [plan](../../superpowers/plans/2026-04-08-secrets-guardrails.md)   | Done    |
| CI safety pass       | [spec](../../superpowers/specs/2026-04-08-ci-safety-design.md)            | [plan](../../superpowers/plans/2026-04-08-ci-safety.md)            | Pending |

For history, see `2026-03-31-dotfiles-improvements-plan.md` (superseded) and `2026-04-08-dotfiles-next-steps-plan.md` (active, links to above).
```

- [ ] **Step 3: Commit**

```bash
git add docs/cursor/specs/README.md
git commit -m "docs: add active roadmap section to docs/cursor/specs/README.md

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 4: Create `docs/superpowers/README.md`

**Files:**

- Create: `docs/superpowers/README.md`

- [ ] **Step 1: Create the file**

Create `docs/superpowers/README.md` with the following content exactly:

```markdown
# Superpowers Specs and Plans

Master status index for all specs and implementation plans in this directory.

## Status Key

| Status      | Meaning                          |
| ----------- | -------------------------------- |
| Done        | Implemented and merged to master |
| In Progress | Currently being implemented      |
| Pending     | Not yet started                  |

---

## All Plans

| Date       | Plan                                                                               | Spec                                                                | Status      |
| ---------- | ---------------------------------------------------------------------------------- | ------------------------------------------------------------------- | ----------- |
| 2026-03-27 | [bats-testing](plans/2026-03-27-bats-testing.md)                                   | [spec](specs/2026-03-27-bats-testing-design.md)                     | Done        |
| 2026-03-27 | [test-coverage-expansion](plans/2026-03-27-test-coverage-expansion.md)             | —                                                                   | Done        |
| 2026-03-28 | [makefile-lint](plans/2026-03-28-makefile-lint.md)                                 | [spec](specs/2026-03-28-makefile-lint-design.md)                    | Done        |
| 2026-03-28 | [powershell-tests](plans/2026-03-28-powershell-tests.md)                           | [spec](specs/2026-03-28-powershell-tests-design.md)                 | Done        |
| 2026-03-28 | [powershell-setup-improvements](plans/2026-03-28-powershell-setup-improvements.md) | [spec](specs/2026-03-28-powershell-setup-improvements-design.md)    | Done        |
| 2026-03-28 | [setup-env-function-extraction](plans/2026-03-28-setup-env-function-extraction.md) | [spec](specs/2026-03-28-setup-env-function-extraction-design.md)    | Done        |
| 2026-03-28 | [test-coverage-remaining](plans/2026-03-28-test-coverage-remaining.md)             | [spec](specs/2026-03-28-test-coverage-remaining-design.md)          | Done        |
| 2026-03-28 | [zshrc-d-test-coverage](plans/2026-03-28-zshrc-d-test-coverage.md)                 | [spec](specs/2026-03-28-zshrc-d-test-coverage-design.md)            | Done        |
| 2026-03-31 | [dotfiles-phase0-bootstrap](plans/2026-03-31-dotfiles-phase0-bootstrap.md)         | [spec](specs/2026-03-31-dotfiles-modularization-design.md)          | Done        |
| 2026-03-31 | [dotfiles-phase1-lib-split](plans/2026-03-31-dotfiles-phase1-lib-split.md)         | [spec](specs/2026-03-31-dotfiles-modularization-design.md)          | Done        |
| 2026-03-31 | [dotfiles-phase2-hardening](plans/2026-03-31-dotfiles-phase2-hardening.md)         | [spec](specs/2026-03-31-dotfiles-modularization-design.md)          | Done        |
| 2026-03-31 | [dotfiles-phase3-profiles](plans/2026-03-31-dotfiles-phase3-profiles.md)           | [spec](specs/2026-03-31-dotfiles-modularization-design.md)          | Done        |
| 2026-03-31 | [dotfiles-phase4-ci](plans/2026-03-31-dotfiles-phase4-ci.md)                       | [spec](specs/2026-03-31-dotfiles-modularization-design.md)          | Done        |
| 2026-03-31 | [dotfiles-phase5-docs](plans/2026-03-31-dotfiles-phase5-docs.md)                   | [spec](specs/2026-03-31-dotfiles-modularization-design.md)          | Done        |
| 2026-04-02 | [brewfile-profile-split](plans/2026-04-02-brewfile-profile-split.md)               | [spec](specs/2026-04-02-brewfile-profile-split-design.md)           | Done        |
| 2026-04-05 | [mas-brewfile-integration](plans/2026-04-05-mas-brewfile-integration.md)           | [spec](specs/2026-04-05-mas-brewfile-integration-design.md)         | Done        |
| 2026-04-07 | [macos-capability-migration](plans/2026-04-07-macos-capability-migration.md)       | [spec](specs/2026-04-05-macos-setup-capability-migration-design.md) | Done        |
| 2026-04-07 | [linux-capability-migration](plans/2026-04-07-linux-capability-migration.md)       | [spec](specs/2026-04-05-linux-setup-capability-migration-design.md) | Done        |
| 2026-04-08 | [secrets-guardrails](plans/2026-04-08-secrets-guardrails.md)                       | [spec](specs/2026-04-08-secrets-guardrails-design.md)               | Done        |
| 2026-04-08 | [workflows-extraction](plans/2026-04-08-workflows-extraction.md)                   | [spec](specs/2026-04-08-workflows-extraction-design.md)             | Pending     |
| 2026-04-08 | [doctor-dry-run](plans/2026-04-08-doctor-dry-run.md)                               | [spec](specs/2026-04-08-doctor-dry-run-design.md)                   | Pending     |
| 2026-04-08 | [ci-safety](plans/2026-04-08-ci-safety.md)                                         | [spec](specs/2026-04-08-ci-safety-design.md)                        | Pending     |
| 2026-04-08 | [plan-hygiene](plans/2026-04-08-plan-hygiene.md)                                   | [spec](specs/2026-04-08-plan-hygiene-design.md)                     | In Progress |
```

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/README.md
git commit -m "docs: add docs/superpowers/README.md master status index

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```
