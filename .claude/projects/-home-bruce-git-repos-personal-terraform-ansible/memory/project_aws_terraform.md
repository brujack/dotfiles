---
name: AWS Terraform future work
description: User plans to tackle the aws-terraform directory in a future session
type: project
originSessionId: afe40797-6af6-4b15-9aea-73e3f52ca23b
---

AWS Terraform work (`aws-terraform/`) is the next active project as of 2026-04-26.

**Why:** The proxmox and cloudflare Terraform work was explicitly done to establish patterns and
practices (Terratest, Makefile targets, HCP Terraform remote state, pre-push hook integration,
pr-review workflow) that will be applied to `aws-terraform/`.

**Current state of aws-terraform/:**

- Multiple sub-directories: `master/`, `ca-central-1/bruce-s3/`, `ca-central-1/bruce-tfe/`,
  `conecrazy-route53/`, `s3-bucket/`
- Severely outdated: `master/` pins Terraform `= 1.4.6` + AWS provider `~> 4.0`;
  `bruce-s3/` pins Terraform `= 1.1.7` + AWS provider `~> 3.0`
- Uses old Kitchen/InSpec tests (`bruce-tfe/`) — not Terratest
- No Makefile lint/test targets wired into root Makefile or pre-push hook
- No HCP Terraform remote state (uses local S3 tfstate buckets)

**Reference implementations to follow:**

- `cloudflare/` — Makefile, Terratest, HCP Terraform, pre-push hook integration
- `proxmox/terraform/` — Terratest pattern with no-destroy + exact resource set assertions

**How to apply:** Start by auditing what's still active vs. dead infrastructure, then modernize
using the cloudflare/proxmox patterns. Add to root Makefile and pre-push hook as a new component.
