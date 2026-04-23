---
name: Proxmox Golden Image Pipeline
description: Status and key facts about the Packer+Terraform golden image pipeline in proxmox/
type: project
originSessionId: 811d8edd-ef3b-42c2-97b7-26a151fdd088
---

The Proxmox golden image pipeline is complete (PR #44, merged 2026-04-22).

**What was built:**

- `proxmox/packer/ubuntu-2404-golden.pkr.hcl` — Packer `proxmox-iso` source, Ubuntu 24.04 autoinstall, bakes in `common` + `users` Ansible roles via `ansible/playbooks/common-packer.yml`
- `proxmox/terraform/` — `bpg/proxmox` provider (v0.103.0), `proxmox_virtual_environment_vm` resource, clones the golden template by looking it up via `golden-image` tag
- `proxmox/terraform/test/` — Terratest (Go) plan test + integration test gated by `//go:build integration`
- `proxmox/Makefile` — `make build-image`, `make plan`, `make apply`, `make lint` (no creds), `make lint-validate` (requires credentials.pkrvars.hcl)

**Key credential files (gitignored, must be created manually):**

- `proxmox/packer/credentials.pkrvars.hcl` (see `.example` file)
- `proxmox/terraform/terraform.tfvars` (see `.example` file)

**Why:** Home lab VM management — single golden template instead of per-VM installs.

**How to apply:** When working in proxmox/, read `proxmox/CLAUDE.md` for full docs.
