---
name: subagent-plan-file-deletion
description: Subagents may silently delete plan/spec files and README rows when reformatting superpowers README tables — always verify before pushing
type: feedback
---

When an implementer subagent is asked to touch `docs/superpowers/README.md`, it may reformat the table (changing column widths) and in doing so silently drop the In Progress row for the current feature — and delete the corresponding plan/spec files outright.

**Why:** Caught on the dotfiles dual-mode-ci branch. The subagent reformatted the entire README table to shorter column widths and omitted the dual-mode-ci row. The plan and spec files (`docs/superpowers/plans/2026-04-21-*.md` and `docs/superpowers/specs/2026-04-21-*.md`) were also deleted. This was caught during PR review and fixed before merge.

**How to apply:** After any subagent touches `docs/superpowers/README.md`, verify:

1. The current feature's row is still present with correct status
2. The corresponding plan and spec files still exist (or were restored with DONE banners if the feature is complete)
3. Run `git diff master -- docs/superpowers/` and scan for unexpected deletions
