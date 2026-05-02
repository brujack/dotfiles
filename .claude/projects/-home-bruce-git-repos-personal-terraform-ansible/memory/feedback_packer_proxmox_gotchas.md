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

Go applies build constraints file-wide. Any test that needs the `integration` tag must be in its own file with `//go:build integration` as the first non-blank, non-comment line.

**6. `cross_env_vars.yml` must be passed to Ansible in Packer.**

`users_uid_bruce`/`users_gid_bruce` are only defined in `ansible/environments/cross_env_vars.yml`. Add to `extra_arguments` in the ansible provisioner block:
`"--extra-vars", "@../../ansible/environments/cross_env_vars.yml"`

**7. checkov `--framework packer` is not a valid framework — do not add it.**

checkov dropped the `packer` framework. `proxmox/Makefile` lint target omits it intentionally.
Valid checkov frameworks in this repo: `--framework terraform` only. Do not attempt to add packer
static analysis via checkov — it will fail with "Invalid frameworks specified: packer."

**8. `terraform validate` requires `terraform init` — it is NOT part of `make lint`.**

`terraform validate` downloads and locks providers. It belongs in `make lint-validate`
(which also requires credentials). `make lint` is credential-free static analysis only:
`packer fmt -check`, `terraform fmt -check`, `tflint`, `checkov --framework terraform`.

**9. Token format: split into two fields, username and secret UUID.**

`proxmox_username = "user@realm!tokenid"` and `proxmox_token = "<uuid-secret-only>"`. Do NOT put the full `user@realm!tokenid=secret` string in `proxmox_token`. Token also needs `SDN.Use` permission on `/sdn/zones/localnetwork` (add `PVESDNUser` role) for VM creation with network bridges.

**10. `packer build .` not `packer build <file>`.**

`packer build ubuntu-2404-golden.pkr.hcl` only loads that one file — `variables.pkr.hcl` is ignored, causing "unsupported attribute" errors. Always use `packer build .` to load all `.pkr.hcl` files in the directory.

**11. user-data password must be a real hash, not a placeholder.**

`identity.password` in `http/user-data` must be the actual SHA-512 hash of `ssh_build_password`. Generate with `openssl passwd -6 'YOUR_PASSWORD'`. The placeholder `REPLACE_WITH_HASHED_PASSWORD` is not replaced automatically — it must be set manually.

**12. Sudoers setup must go in `late-commands`, not `user-data.runcmd`.**

`runcmd` runs cloud-init on the installed system's first boot, which races with SSH availability. `late-commands` runs during the installer phase before reboot, guaranteeing the sudoers file exists when Packer SSHs in. Use: `echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' > /target/etc/sudoers.d/ubuntu-packer`.

**13. YAML flow-mapping in runcmd — quote strings containing colons.**

`- echo "ubuntu ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/ubuntu-packer` is parsed as a dict by YAML because `NOPASSWD: ALL` looks like a key-value pair. Wrap the entire string in single quotes: `- 'echo "ubuntu ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ubuntu-packer'`.

**14. Install `acl` package before Ansible runs.**

Ansible's `become` with an unprivileged user requires `setfacl` (from the `acl` package) to set permissions on temp files. Without it: `chmod: invalid mode: 'A+user:bruce:rx:allow'`. Install `acl` in `setup.sh` before the Ansible provisioner step.

**15. Create `/etc/packer` sentinel in setup.sh.**

The `common` role checks for `/etc/packer` to set `common_is_packer_environment`. Without this file, the variable is `false` and packer-skipped tasks (like homebrew install) will run and fail. Add `touch /etc/packer` to `setup.sh`.

**16. Homebrew (`users` role) must skip on packer builds.**

Homebrew refuses to run as root (`Don't run this as root!`). Guard with `not (common_is_packer_environment | default(false))` — use the `default` filter so it works when `common` hasn't run (e.g. molecule tests for the `users` role standalone).

**17. Ubuntu autoinstall default lvm layout leaves root LV at ~50% of disk.**

The default `storage: layout: name: lvm` in `user-data` uses scaled sizing — on a 32 GB disk the root LV ends up at ~15 GB. Add `sizing-policy: all` under the lvm layout to make the root LV occupy 100% of the VG. Without this, cloned VMs have half their disk unusable. Fix for existing VMs: `lvextend -l +100%FREE /dev/ubuntu-vg/ubuntu-lv && resize2fs /dev/mapper/ubuntu--vg-ubuntu--lv`.

**18. cloud-init overwrites `authorized_keys` baked into the golden image.**

`initialization.user_account.keys` in the bpg/proxmox provider writes a cloud-init NoCloud drive that runs on first VM boot and replaces `/home/bruce/.ssh/authorized_keys` with only the keys listed in Terraform. The `users` role bakes 3 keys into the golden image template, but cloud-init silently discards any key not in `ssh_public_keys`. Fix: keep `ssh_public_keys` (list) in `terraform.tfvars` in sync with the `users` role `authorized_keys` template. After applying the Terraform change, Ansible must be re-run on existing VMs — cloud-init won't re-run on a running VM.

**Why:** Cloud-init's user module treats `users:` as authoritative — it overwrites, not appends.

**How to apply:** When adding a key to the `users` role template, also add it to `ssh_public_keys` in `terraform.tfvars`. When provisioning a new golden-image VM, verify `authorized_keys` after first boot.

**How to apply:** Check all of these when adding or modifying anything in `proxmox/`.
