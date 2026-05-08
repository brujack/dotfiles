---
name: auto-merge gate integrity
description: Key learnings from PR #45 — gh pr checks GraphQL limitation and self-exclusion bug in polling gate
type: project
originSessionId: 786c8544-fee1-40a8-8d1d-cfd1bac5920f
---

Auto-merge gate integrity shipped in PR #45 (2026-05-06). Two non-obvious issues hit in CI:

**1. `gh pr checks --json` is unusable with GITHUB_TOKEN**
`gh pr checks --json name,state` uses a GraphQL query that internally fetches `checkSuite.workflowRun` on every check run, regardless of which fields you specify. This field is inaccessible to GITHUB_TOKEN even with `checks: read` declared in workflow permissions. Error: `GraphQL: Resource not accessible by integration (node.statusCheckRollup...checkSuite.workflowRun)`.

Fix: use the REST API directly — `gh api repos/{owner}/{repo}/commits/{sha}/check-runs`. This uses `status` (in_progress/queued/completed) and `conclusion` (success/failure/skipped/...) fields and works with default GITHUB_TOKEN + `checks: read`. Get the SHA first via `gh api repos/{owner}/{repo}/pulls/{pr} --jq '.head.sha'`. Use `GITHUB_REPOSITORY` env var (auto-set in Actions) for the owner/repo.

**2. Polling gate must exclude self-checks from non-terminal detection**
A gate script that polls `gh pr checks` to wait for other workflows must exclude the running job (e.g. `auto-merge`) and its siblings from the non-terminal check — not just from the final pass/fail evaluation. If the gate doesn't exclude itself, it sees itself as in_progress forever and always times out.

Fix: build the `excluded_json` list before the polling loop and apply it to BOTH the non-terminal filter AND the final pass/fail filter.

**Why:** Both bugs cause the gate to always fail (never merge) rather than silently passing.
**How to apply:** Any future CI gate script using `gh pr checks` should switch to the REST check-runs API, and any polling loop must exclude the currently-running workflow from the non-terminal check.
