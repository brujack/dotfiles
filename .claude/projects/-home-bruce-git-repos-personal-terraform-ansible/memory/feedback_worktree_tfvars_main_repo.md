---
name: Worktree tfvars — don't overwrite main repo gitignored credentials
description: Copying updated gitignored credential files into the main repo during worktree work breaks the pre-push hook when branches have mismatched variable schemas
type: feedback
originSessionId: b44f6455-165e-4121-9df3-27eb741f264f
---

Never copy a worktree's updated gitignored credential file (e.g. `terraform.tfvars`) into the main repo's working tree until after the PR merges.

**Why:** The pre-push hook runs Terratest against the main repo's working tree (not the worktree branch). If the worktree renames a variable (e.g. `ssh_public_key` → `ssh_public_keys`) and you copy the new-format `terraform.tfvars` into the main repo, it mismatches the main repo's `variables.tf` (which is still on master with the old name). Result: `terraform plan` fails with "No value for required variable" and the push is blocked.

**How to apply:** During a worktree-based workflow, keep the main repo's gitignored credential files in their current (master-compatible) format. Only update them after the PR merges and you've pulled master.
