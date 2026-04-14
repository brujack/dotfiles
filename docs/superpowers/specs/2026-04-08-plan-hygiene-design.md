# Design: Plan Hygiene and Status Tracking

**Date:** 2026-04-08
**Status:** Approved

## Summary

Update the two Cursor spec docs in `docs/cursor/specs/` to reflect current implementation status, and add an active roadmap section to `docs/cursor/specs/README.md` pointing to the next steps.

## Motivation

The Cursor specs were written as planning documents but were never updated to reflect what got done. `2026-03-31-dotfiles-improvements-plan.md` is marked "Partially Completed" with no link to the follow-on spec. `2026-04-08-dotfiles-next-steps-plan.md` is marked "Draft" but has been superseded by the superpowers specs and plans in `docs/superpowers/`. Future sessions should be able to find the current state in one place without reconstructing history.

## Changes

### Modified: `docs/cursor/specs/2026-03-31-dotfiles-improvements-plan.md`

Update the status header:

```markdown
**Status:** Superseded — see docs/cursor/specs/2026-04-08-dotfiles-next-steps-plan.md
```

Add a completion note at the top of the Current Status section linking to the superpowers specs.

### Modified: `docs/cursor/specs/2026-04-08-dotfiles-next-steps-plan.md`

Update the status header:

```markdown
**Status:** Active — implementation tracked in docs/superpowers/specs/ and docs/superpowers/plans/
```

Add a reference table mapping each step to its superpowers spec and plan file.

### Modified: `docs/cursor/specs/README.md`

Add an "Active Roadmap" section listing current work items with links:

```markdown
## Active Roadmap

| Item                 | Spec                                                                      | Plan                                                               | Status  |
| -------------------- | ------------------------------------------------------------------------- | ------------------------------------------------------------------ | ------- |
| Workflows extraction | [spec](../../superpowers/specs/2026-04-08-workflows-extraction-design.md) | [plan](../../superpowers/plans/2026-04-08-workflows-extraction.md) | Pending |
| Doctor + dry-run     | [spec](../../superpowers/specs/2026-04-08-doctor-dry-run-design.md)       | [plan](../../superpowers/plans/2026-04-08-doctor-dry-run.md)       | Pending |
| Secrets guardrails   | [spec](../../superpowers/specs/2026-04-08-secrets-guardrails-design.md)   | [plan](../../superpowers/plans/2026-04-08-secrets-guardrails.md)   | Pending |
| CI safety pass       | [spec](../../superpowers/specs/2026-04-08-ci-safety-design.md)            | [plan](../../superpowers/plans/2026-04-08-ci-safety.md)            | Pending |
```

## Constraints

- No code changes — this is documentation only.
- All links must be relative and correct.
- Status fields should be kept up to date as work completes.
