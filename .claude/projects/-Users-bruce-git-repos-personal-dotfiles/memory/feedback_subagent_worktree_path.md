---
name: Subagent worktree path must be explicit
description: When dispatching implementer subagents to a worktree, the working directory must be stated prominently or the subagent will commit to the wrong repo
type: feedback
---

When dispatching implementer subagents via subagent-driven-development, always state the working directory at the **top** of the prompt (not just at the bottom under "Work from:"), and add an explicit warning not to cd to any other directory.

**Why:** During linux-package-update-tracking (2026-04-16), the Task 6 docs implementer committed README.md and docs/superpowers/README.md to `dotfiles/` (the main checkout) instead of `dotfiles-linux-pkg-tracking/` (the worktree). The "Work from:" line was present but buried at the bottom. The spec reviewer also missed it because it only verified file content, not which repo received the commit.

**How to apply:** In every implementer subagent prompt for worktree-based work:

- Add a prominent callout near the top: "**IMPORTANT: All work must happen in `/path/to/worktree/`. Do not cd to any other directory.**"
- Keep the "Work from:" line at the bottom as well (belt and suspenders)
- Consider having the spec reviewer verify the commit is on the correct branch: `git -C <worktree> log --oneline -1`
