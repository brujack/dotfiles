---
name: Packer proxmox plugin gotchas
description: Known pitfalls when working with the hashicorp/proxmox Packer plugin in this repo
type: feedback
originSessionId: 811d8edd-ef3b-42c2-97b7-26a151fdd088
---

Several non-obvious issues discovered during the golden image pipeline build.

**1. Goss plugin doesn't exist as a Packer plugin — use file+shell provisioners instead.**

`github.com/supersoftware/goss` doesn't exist. `packer-provisioner-goss` has a forbidden `packer-` prefix and can't be installed via `required_plugins`. Use `file` provisioner to copy `goss.yaml` + a `shell` provisioner to download the goss binary (`curl -fL`) and run it.

**Why:** Both goss plugin sources are dead ends. The file+shell approach is portable and has no plugin dependency.

**2. Packer proxmox plugin v1.2.3 requires a separate `username` field.**

Add `proxmox_username` as a variable (default `packer@pve!packer`) and wire it to `username` in the `source "proxmox-iso"` block. Without it, the plugin errors on missing required field.

**3. Use `curl -fL` not `curl -sL` for downloads.**

`-s` (silent) suppresses error output AND swallows HTTP errors — a 404 looks like success. `-f` (fail-fast) exits non-zero on HTTP errors.

**4. Ubuntu ISO version changes frequently — verify SHA256SUMS.**

24.04.2 was removed from `SHA256SUMS` before the pipeline was built; 24.04.4 was current. Check the Ubuntu release page before hardcoding an ISO version/checksum.

**5. `//go:build integration` must be at the top of the file, not mid-file.**

Go applies build constraints file-wide. If `TestProxmoxApply` (which destroys real VMs) needs the `integration` tag, it must be in its own file with `//go:build integration` as the first non-blank, non-comment line.

**6. `cross_env_vars.yml` must be passed to Ansible in Packer.**

`users_uid_bruce`/`users_gid_bruce` are only defined in `ansible/environments/cross_env_vars.yml`. Add to `extra_arguments` in the ansible provisioner block:
`"--extra-vars", "@../../ansible/environments/cross_env_vars.yml"`

**How to apply:** Check all of these when adding or modifying anything in `proxmox/packer/`.
