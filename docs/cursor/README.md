# Cursor Specs and Plans

Master status index for Cursor-oriented specs and plans in this repository.

The Claude + Superpowers workflow remains primary; `docs/superpowers/README.md` is the full historical index.
This file is the Cursor-friendly secondary index and should be kept in sync for active/ongoing work.

## Status Key

| Status      | Meaning                          |
| ----------- | -------------------------------- |
| Done        | Implemented and merged to master |
| In Progress | Currently being implemented      |
| Pending     | Not yet started                  |

---

## All Plans

| Date       | Plan                                                                         | Spec                                                                      | Status |
| ---------- | ---------------------------------------------------------------------------- | ------------------------------------------------------------------------- | ------ |
| 2026-03-31 | [dotfiles-improvements-plan](plans/2026-03-31-dotfiles-improvements-plan.md) | [spec](../superpowers/specs/2026-03-31-dotfiles-modularization-design.md) | Done   |
| 2026-04-08 | [dotfiles-next-steps-plan](plans/2026-04-08-dotfiles-next-steps-plan.md)     | [spec index](../superpowers/specs/README.md)                              | Done   |

---

## Backlog

Ideas approved for future cursor-specific specs/plans, in no particular order:

| Feature                                                         | Notes                                                                                                       |
| --------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| Verify state-ledger writes idempotent for setup + recreate_venv | Wired in #166–#168; no idempotency tests exist for these paths                                              |
| Brewfile dedup lint                                             | `scripts/check-brewfile-dedup.sh`, wire into `make lint` (2026-06 retro)                                    |
| Ubuntu upgrade runbook                                          | Pre-flight checklist doc at `docs/knowledge/dotfiles-ubuntu-upgrade.md` (2026-06 retro)                     |
| Per-file coverage floors enforcement                            | Extend `scripts/run-bash-coverage.sh` to emit per-file % and fail on known-floor violations (2026-06 retro) |
| Default pyenv mock in test setup()                              | Set `MOCK_PYENV_WHICH_STDOUT` in `tests/helpers/common.bash` so tests don't run real pip (2026-06 retro)    |

---

## Adding a new entry

When a new Cursor spec or plan is created, add a row to the All Plans table.
Set status to **In Progress** when implementation starts and **Done** when the work merges.
Keep the backlog at the bottom of this file.
