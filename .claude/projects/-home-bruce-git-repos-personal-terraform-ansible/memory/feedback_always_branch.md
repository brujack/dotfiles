---
name: always-use-feature-branches
description: Never commit fix/feat/refactor directly to master - always create a feature branch and PR, even for single-file changes
type: feedback
originSessionId: 60371967-5758-4038-8843-f14bd4dfbbe9
---

Never commit implementation work directly to master. Always create a feature branch and PR, even for small single-file fixes like adding a missing handler. The user called this out after a handler fix was committed directly to master.

**Why:** The CLAUDE.md rule exists to ensure CI runs on every change via PR. Committing directly bypasses CI and the review workflow.

**How to apply:** Before any `git commit` for non-docs work, verify you're on a feature branch, not master. If you catch yourself on master, create a branch before committing. The only exception is documentation-only changes (typos, README updates, memory commits).
