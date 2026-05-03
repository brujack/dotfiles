---
name: pre-push hook runs from main repo in worktrees
description: Pre-push hook navigates to main repo root via git-common-dir, so it tests main not the worktree branch when pushing from a worktree
type: project
---

The pre-push hook runs:

```bash
make -C "$(cd "$(git rev-parse --git-common-dir)/.." && pwd)" test
```

In a linked worktree, `--git-common-dir` returns the shared `.git` of the main repo, so this runs `make test` in the main repo root — testing whatever branch main is on, not the worktree's branch.

**Why:** The hook was designed this way to find the Makefile reliably, but it means worktree pushes don't get local pre-push validation of their own changes.

**How to apply:** When pushing from a worktree, the pre-push hook is not a reliable gate. Verify the worktree tests pass explicitly (`make test` from the worktree directory) before pushing. CI is the real merge gate in this workflow.
