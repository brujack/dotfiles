---
name: Keep task list current throughout implementation
description: Mark tasks completed via TaskUpdate immediately after finishing each one — do not let the task list fall out of sync with actual progress
type: feedback
originSessionId: 0cbbbe3c-1f4c-43f3-8471-ae3f51e72d24
---

Use TaskUpdate to mark each task `completed` as soon as it finishes. Do not batch updates at the end or leave the task list in a stale state reflecting old progress.

**Why:** The task list fell out of sync during the factorial implementation — Task 4 remained "in_progress" and all subsequent tasks stayed "pending" despite the entire project being complete and merged.

**How to apply:** After each subagent returns DONE and passes spec+quality review, immediately call TaskUpdate to mark that task completed before dispatching the next one.
