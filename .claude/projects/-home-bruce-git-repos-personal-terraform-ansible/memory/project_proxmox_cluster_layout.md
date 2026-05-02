---
name: Proxmox cluster node layout
description: Which VMs run on which Proxmox nodes, VM IDs, and node status
type: project
originSessionId: afe40797-6af6-4b15-9aea-73e3f52ca23b
---

Proxmox cluster node layout as of 2026-05-02.

**prox-1** — currently offline

**prox-2** — running workloads:

- bind-slave (VM 105)
- docker-server (VM 103)
- downloads (VM 104)
- etch-cli-test (VM 108) — ubuntu-2404-golden clone, test box

**prox-3** — running workloads + templates:

- teleport (VM 100)
- common-1 (VM 101)
- emotive-toolbox-1 (VM 102)
- plex-2 (VM 106)
- test-2604 (VM 107)
- ubuntu-2404-golden template (VM 1001, tag: golden-image)
- ubuntu-2604-golden template (VM 1002, tag: golden-image-2604)

**Why:** Node layout was clarified when importing pre-existing VMs into Terraform state. `plex-3` was an erroneous node name used in earlier config — it does not exist.

**How to apply:** Use these VM IDs and node assignments when running `terraform import` or debugging plan drift. Verify current state with `pvesh get /nodes/<node>/qemu` if VMs have been added or moved.
