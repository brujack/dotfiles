---
name: Always invoke pr-review skill before pushing feature branches
description: pr-review skill must be run before every feature branch push, not just when following the finishing-a-development-branch workflow
type: feedback
originSessionId: afe40797-6af6-4b15-9aea-73e3f52ca23b
---

Always invoke the `pr-review` skill before pushing any feature branch. Do not skip it for small changes or when not following a formal skill workflow.

**Why:** The skill was being skipped when not explicitly prompted by a superpowers workflow, causing PRs to go up without a review gate.

**How to apply:** Before every `git push` on a feature branch, invoke `pr-review`. Only push on PASS. This applies in all repos, all branch sizes, all scenarios.
