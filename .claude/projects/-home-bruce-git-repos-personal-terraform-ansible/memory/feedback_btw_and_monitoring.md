---
name: handle btw side-requests and monitor PRs actively
description: User uses /btw for inline side-requests and expects active CI/PR monitoring without being asked
type: feedback
originSessionId: 1849ac56-b366-4acc-a759-3bf934f8700b
---

Handle "/btw" messages as inline side-requests — they're not interruptions, they're additional work items to fold into the current flow. Don't treat them as a context switch.

When PRs are open, actively monitor CI status without waiting to be asked. The user expects to be told when CI passes/fails and for next steps (rebase, fix, cleanup) to happen automatically.

**Why:** User asked "Are you watching pr33?" — indicating the expectation is proactive monitoring, not reactive.

**How to apply:** After pushing a PR, poll CI status periodically. When all checks pass and auto-merge completes, proceed with cleanup (worktree removal, branch deletion, master pull) without prompting. This applies to EVERY PR — not just the first one in a session. The user has called this out multiple times (PR #33, PR #38, PR #60) — it is a consistent expectation that must not lapse mid-session or between PRs. After merging one PR and starting a new branch, reset and watch the next PR with the same diligence.
