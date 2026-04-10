---
name: Always use feature branches for implementation work
description: Implementation work in this repo must go on a feature branch, not master directly
type: feedback
---

Always create a feature branch (via worktree or `git checkout -b`) before starting any implementation. The repo pattern is feature branch → PR → CI auto-merge. Committing directly to master bypasses CI and the review workflow.

**Why:** User confirmed this after cursor-sync was committed directly to master. The subagent-driven-development skill flags this as a red flag ("never start implementation on main/master without explicit user consent") — follow it.

**How to apply:** Before dispatching any implementer subagent, set up a worktree on a feature branch using the `superpowers:using-git-worktrees` skill. Do not skip this step even for small changes. Ask the user if unsure.
