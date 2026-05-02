---
name: Proxmox cross-node clone requires node_name in clone block
description: bpg/proxmox provider needs clone.node_name set when VM node differs from template node; plan-only tests cannot catch this
type: feedback
originSessionId: cc03853e-5f02-4d42-a98a-82cdde98ffaa
---

When creating a VM on a different node than the template (e.g. VM on prox-2, template on prox-3), the `clone {}` block must include `node_name = "prox-3"`. Without it, the provider looks for the template on the VM's target node and fails at apply time with HTTP 500: "unable to find configuration file for VM 1001 on node 'prox-2'".

**Why:** The `bpg/proxmox` provider does not automatically resolve cross-node clones. The `node_name` in `clone {}` tells it where to find the source template.

**How to apply:** Any time `node_name` on the VM resource differs from `prox-3` (where the golden templates live), add `node_name = "prox-3"` inside the `clone {}` block. Terratest plan-only tests will not catch this — it only surfaces at `terraform apply` time.
