---
name: Always run pr-review skill before pushing
description: The pr-review skill must be invoked before every push or PR creation in this repo — it was skipped on the cloudflare-v5-migration and other work
type: feedback
originSessionId: e4ce674c-cc3d-453d-9426-9d6969f1da33
---

Always invoke the `pr-review` skill before pushing a feature branch or creating a PR. This applies to all work in the terraform_ansible repo.

**Why:** The pr-review skill was skipped during the cloudflare-v5-migration PR (#47) and other work. The user flagged this as a required step that must not be omitted.

**How to apply:** In `superpowers:finishing-a-development-branch`, Option 2 (Push and Create PR) requires the pr-review gate. Do not skip it regardless of how mechanical or well-tested the change seems. Run the skill, achieve PASS verdict, then push.
