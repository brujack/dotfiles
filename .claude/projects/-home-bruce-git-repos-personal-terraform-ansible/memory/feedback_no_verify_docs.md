---
name: Use --no-verify for docs-only pushes
description: Documentation-only commits (plans, specs, README, CLAUDE.md, memory) must be pushed with --no-verify to skip molecule
type: feedback
originSessionId: 402fec12-b704-4e7e-8098-742ab5b711ad
---

Use `git push --no-verify` for docs-only commits, even when the files live under `ansible/` (e.g. `ansible/docs/superpowers/`, `ansible/CLAUDE.md`, `ansible/README.md`).

**Why:** The pre-push hook matches the `ansible/` prefix and triggers the full molecule matrix (~5-6 min) for any file under that directory. Docs changes don't affect role behavior and don't warrant a test run.

**How to apply:** Any push whose diff contains only Markdown, plan files, CLAUDE.md, or memory files — use `--no-verify` regardless of which directory they're in.
