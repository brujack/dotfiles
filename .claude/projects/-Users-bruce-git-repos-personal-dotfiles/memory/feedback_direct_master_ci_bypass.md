---
name: Direct master commits bypass CI — new CI checks may be untested
description: New CI steps added via direct master commits are never exercised until the next PR; always verify new CI steps work on Linux before merging to master
type: feedback
---

When a new CI step is added to `.github/workflows/ci.yml` via a direct master commit (docs, memory, chore), CI never runs on that commit — the workflow triggers on `pull_request` only. The new step may have bugs that are silently invisible until the next PR exposes them.

**Why:** Discovered when `sync-agent-guidance.sh` was added to master with `claude_path = root / ".claude" / "claude.md"` (lowercase). Works on macOS (case-insensitive HFS+), fails on Linux CI where the file is actually `.claude/CLAUDE.md` (uppercase). The bug was silent in master, only surfaced when PR #58 was the first PR after the script was added.

**How to apply:** When adding any new CI step via a direct master commit, immediately open a scratch PR (or check the logic manually on Linux) to verify the step actually passes in CI before the next real PR reveals the bug.
