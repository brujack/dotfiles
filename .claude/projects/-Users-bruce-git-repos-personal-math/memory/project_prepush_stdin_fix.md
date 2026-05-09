---
name: pre-push hook stdin deadlock fix
description: Python multiprocessing deadlocks in git pre-push hook when stdin is a live git pipe — fix is make test < /dev/null
type: project
originSessionId: dbf0123f-5acb-467e-b3fa-1e6a4315c531
---

## Finding (PR #47, 2026-05-09)

Python's `multiprocessing.resource_tracker` daemon inherits the pre-push hook's stdin FD. In the git hook environment, git holds the **write end** of the hook's stdin pipe open (waiting for the hook to finish). The resource_tracker blocks on stdin reads waiting for EOF — but EOF never comes because git still holds the write end. Circular deadlock: git waits for hook → hook waits for tests → tests wait for resource_tracker → resource_tracker waits for git's pipe to close.

**Fix:** Redirect stdin from `/dev/null` when running `make test` in the hook:

```bash
make -C "${REPO_ROOT}/${dir}" test < /dev/null
```

**Why:** This ensures all spawned subprocesses (Python multiprocessing workers, resource_tracker) get EOF on stdin immediately, breaking the circular wait.

**How to apply:** Any pre-push hook that runs tests for projects using Python `ProcessPoolExecutor` (or any multiprocessing with the spawn context on macOS) must use `< /dev/null`. This is now documented in `dotfiles/.claude/standards/ci.md`.

Discovered when factorial tests deadlocked for 40+ minutes during push of PR #47 (failure-mode test matrix). The deadlock only occurred in the git hook environment, not when running `make test` directly.
