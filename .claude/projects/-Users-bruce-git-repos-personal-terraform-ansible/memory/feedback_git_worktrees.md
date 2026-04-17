---
name: Always use git worktrees for feature branches
description: Feature branch work must use git worktrees, not bare git checkout -b
type: feedback
---

Always use `git worktree add` when starting implementation work on a feature branch. Never just `git checkout -b` or `git switch -c`.

**Why:** User explicitly requires worktrees for feature branch isolation (also documented in CLAUDE.md Feature Branches section). Creating a bare branch without a worktree bypasses the isolation the workflow requires.

**How to apply:** Before any implementation work that warrants a feature branch, invoke `superpowers:using-git-worktrees` skill to set up the worktree. Docs-only commits (CLAUDE.md, README, memory files) may go directly to master per the exception in CLAUDE.md.
