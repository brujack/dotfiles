---
name: verify-hooks-installed
description: Always verify pre-push hook is installed at session start before any pushes
type: feedback
originSessionId: 6a19bade-637f-444e-a960-9df032c46c4d
---

At the start of any session in this repo, check that the pre-push hook is installed before doing any work that will end in a push.

**Why:** The hook gates local test runs before GitHub CI. In the April 2026 coverage session, `.git/hooks/pre-push` was missing for the entire session — tests only ran on GitHub CI, not locally first. The user explicitly requires local gating.

**How to apply:** At session start, run:

```bash
ls .git/hooks/pre-push .git/hooks/pre-commit
```

If either is missing, run `make install-hooks` immediately before proceeding.
