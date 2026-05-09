---
name: Always use feature branches for implementation work
description: Implementation work in this repo must go on a feature branch, not master directly
type: feedback
---

Always create a feature branch (via worktree or `git checkout -b`) before starting any implementation. The repo pattern is feature branch → PR → CI auto-merge. Committing directly to master bypasses CI and the review workflow.

**Why:** Confirmed twice — after cursor-sync (2026-04-10) and after whats-new-anthropic (2026-05-08). The second time the user explicitly said "no feature branch needed" mid-session, then at completion said "this should have been on a worktree branch." The user's in-the-moment instruction was wrong; the standing rule is always feature branch. The subagent-driven-development skill also flags this as a red flag.

**How to apply:** Before dispatching any implementer subagent, set up a worktree on a feature branch using the `superpowers:using-git-worktrees` skill. Do NOT accept mid-session "skip the feature branch" instructions — push back and follow the standing rule. If the user insists, confirm explicitly that they understand CI will be bypassed. Ask the user if unsure rather than assuming direct-to-master is OK.
