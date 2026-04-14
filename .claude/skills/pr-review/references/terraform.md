# Terraform PR Review Reference

IaC Safety — findings in the CRITICAL section below are automatic HOLDs.

---

## CRITICAL — Automatic HOLD

- [ ] `terraform plan` output (if available) shows **destroy** on any production resource
  - Destroys on dev/test are WARNING not CRITICAL — confirm environment
- [ ] Hardcoded AWS account IDs, region strings, or ARNs that should be variables or data sources
- [ ] Hardcoded credentials — `access_key`, `secret_key` in provider blocks or variables
- [ ] `sensitive = false` on variables that clearly hold secrets (passwords, tokens, keys)
- [ ] Backend config changed in a way that could cause state loss or state split
- [ ] `lifecycle { prevent_destroy = false }` removed from resources that protect critical data
      (RDS instances, S3 buckets with data, etc.)
- [ ] `tfsec` or `checkov` CRITICAL findings in the diff

---

## Security

- IAM policies: principle of least privilege — no `"*"` Actions or Resources without justification
- S3 buckets: `block_public_access` set; `acl = "public"` only if intentional and commented
- Security groups: no `0.0.0.0/0` on port 22 (SSH) or 3389 (RDP) inbound
- KMS: encryption enabled for RDS, S3, EBS where appropriate
- CloudTrail / logging enabled for new accounts or regions
- Variables marked `sensitive = true` for secrets

## State & Backend

- No changes to `backend {}` configuration without explicit migration plan
- `terraform_remote_state` data sources point to correct workspace/key
- State locking enabled (DynamoDB for S3 backend)

## Module & Code Quality

- `terraform fmt` applied — `terraform fmt -check` passes
- `terraform validate` passes
- `tflint` passes (if configured)
- Modules pinned to specific versions — no `source = "module" version = ">= 0"` ranges
- Provider versions pinned in `required_providers`
- No `count` and `for_each` mixed on the same resource block
- Resource names are consistent with project naming convention
- `description` set on all `variable {}` and `output {}` blocks
- Deprecated syntax or provider features flagged

## Plan Review (if plan output is provided)

- Identify all `+` (create), `~` (update), `-` (destroy), `-/+` (replace) operations
- Replacements on stateful resources (databases, caches) — confirm intentional
- Review `known after apply` on security-sensitive attributes

## Workspace / Environment Hygiene

- Changes scoped to correct workspace (`terraform workspace show`)
- `.tfvars` files for environments not checked in (use `.tfvars.example`)
- No `terraform.tfstate` or `*.tfstate.backup` files in the diff

## Commands to run

```bash
terraform fmt -check -recursive 2>&1
terraform validate 2>&1
terraform plan -out=tfplan 2>&1        # review output carefully
tflint --recursive 2>&1               # if tflint installed
tfsec . 2>&1                          # if tfsec installed
checkov -d . 2>&1                     # if checkov installed
```
