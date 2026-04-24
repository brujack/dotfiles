---
name: Use pr-review skill for math repo PRs
description: The pr-review skill must be invoked via the Skill tool before pushing any branch in the math repo — running the review inline as the main agent is not acceptable
type: feedback
originSessionId: 0cbbbe3c-1f4c-43f3-8471-ae3f51e72d24
---

Always invoke the `pr-review` skill via the `Skill` tool (not `superpowers:pr-review`) before pushing any feature branch in the math repo. Do not run the review phases manually inline.

**Why:** The user explicitly required this. Running the review inline as the main agent bypasses the structured skill workflow and misses the skill's reference files and per-language checklists.

**How to apply:** In `finishing-a-development-branch` Option 2 (push + PR), invoke `Skill tool` with `skill: "pr-review"` and let the skill load and drive the review. Do not duplicate the review phases manually.
