# Cursor Specs

This folder stores durable planning/design specs created for Cursor-driven work in this repository.

## File Naming

Use:

`YYYY-MM-DD-<topic>-plan.md`

Example:

`2026-03-31-dotfiles-improvements-plan.md`

## Recommended Template

Each spec should include at minimum:

- Date
- Status (`Draft`, `Approved`, `Superseded`)
- Scope
- Goals and non-goals
- Phased plan (or implementation sections)
- Validation/verification strategy
- Risks and mitigations

## Guidance

- Prefer one spec per meaningful initiative.
- Keep specs concise, concrete, and executable.
- Update status when direction changes.

## Active Roadmap

Current work items tracked in `docs/superpowers/`:

| Item                 | Spec                                                                      | Plan                                                               | Status |
| -------------------- | ------------------------------------------------------------------------- | ------------------------------------------------------------------ | ------ |
| Workflows extraction | [spec](../../superpowers/specs/2026-04-08-workflows-extraction-design.md) | [plan](../../superpowers/plans/2026-04-08-workflows-extraction.md) | Done   |
| Doctor + dry-run     | [spec](../../superpowers/specs/2026-04-08-doctor-dry-run-design.md)       | [plan](../../superpowers/plans/2026-04-08-doctor-dry-run.md)       | Done   |
| Secrets guardrails   | [spec](../../superpowers/specs/2026-04-08-secrets-guardrails-design.md)   | [plan](../../superpowers/plans/2026-04-08-secrets-guardrails.md)   | Done   |
| CI safety pass       | [spec](../../superpowers/specs/2026-04-08-ci-safety-design.md)            | [plan](../../superpowers/plans/2026-04-08-ci-safety.md)            | Done   |
| Plan hygiene         | [spec](../../superpowers/specs/2026-04-08-plan-hygiene-design.md)         | [plan](../../superpowers/plans/2026-04-08-plan-hygiene.md)         | Done   |

For history, see `2026-03-31-dotfiles-improvements-plan.md` (superseded) and `2026-04-08-dotfiles-next-steps-plan.md` (active, links to above).
