---
name: Thorough post-merge branch cleanup
description: After PR merges, clean up ALL stale branches (local and remote), not just the current one
type: feedback
originSessionId: 1849ac56-b366-4acc-a759-3bf934f8700b
---

After a PR merges, clean up ALL stale branches — not just the one from the current PR. The full cleanup checklist:

1. **Remote branches:** `git fetch --prune && git branch -r | grep -v master` — delete any that have merged PRs
2. **Local branches (squash-merged):** `git branch | grep -v master` — for each, check `gh pr list --head <branch> --state merged` — if a merged PR exists, delete with `git branch -D` (squash-merges aren't detected by `git branch --merged`)
3. **Local branches (regular merged):** `git branch --merged master | grep -v master` — delete with `git branch -d`

**Why:** User found 6 stale remote branches and 3 stale local branches accumulated across sessions. The per-PR cleanup was only deleting the current branch, leaving older ones behind. Squash-merged branches require `gh pr list` to detect since `git branch --merged` doesn't see them.

**How to apply:** Run this full cleanup after every PR merge, not just for the current branch. Also run it at session start and session end as a sweep.
