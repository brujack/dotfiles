# ADR-0041: Ubuntu installs stage, then rename, and stamp on success

**Date:** 2026-10-05
**Status:** Accepted.

## Context

`install_ubuntu_packages` reported each step's last command's status. Several steps ended on
an `if` with no true branch, so they returned 0 even when every install in them failed, and
nvidia's "skip when docker failed" guard could not fire for a failed docker install.

Downloaded tools (kind, telepresence, the HashiCorp tools, cf-terraforming, docker-compose,
yq, Go) were fetched into `~/software_downloads` and copied into `/usr/local`. `wget -O`
truncates its target before it fails, and the copy still ran, so one failed fetch replaced a
working binary with an empty file. Each tool's skip guard read that download, so any failure
after the download left an artifact that made every later run skip the tool and report
success. Several apt keyrings were written in place with `curl | gpg --dearmor --yes -o`,
which truncates the live keyring when curl fails.

## Decision

- Each step lists its sub-installs, attempts every one, names each failure as
  `<step>: <tool>: <action> failed`, and ends on an explicit status. A failed sub-install
  never stops its siblings.
- Downloaded binaries go through `_install_fetched_binary`. It downloads and extracts in a
  throwaway directory, stages the binary with `sudo install -m 0755` to `<dest>.new`, renames
  it into place, and only then writes a stamp holding the download URL under
  `~/.local/share/dotfiles/installed`. A run is skipped only when the stamp matches the URL
  and the binary is executable. telepresence stamps the versioned https URL that its `latest`
  link resolves to.
- Go uses the same throwaway directory and stamp. The tree is chowned to root before the
  swap, every move checks that its destination is absent, the old tree is restored if the new
  one cannot be moved in, and a damaged `go` or `go.old` is removed rather than kept.
- apt keyrings go through `_install_apt_keyring`: fetch to a file, dearmor unprivileged,
  stage 0644 to `<keyring>.new`, rename. `_write_apt_source_list` writes a source only beside
  a non-empty keyring.
- `apt update` failure is a warning, given once by the base step; the `apt install` after it
  is the check. powershell and nvidia keep treating their own `apt update` as a failure.
- docker returns 3 when `docker-ce`, `docker-ce-cli`, `containerd.io` or `daemon.json` fails
  and 1 otherwise; only 3 skips nvidia.

The stamp, not the download, is the record that an install finished, because only a step
that ran after the install can say so. The rejected alternative, deleting the partial
download on each failure path, had its own failure at every stage it covered.

## Consequences

- The first run after this change re-installs every helper-installed tool once, because no
  stamps exist: about 450 MB plus a Go swap per Linux box.
- `rm` a stamp file to force a re-install; the skip line names it.
- A broken install is reported in `ubuntu packages: failed: ...` and `-t developer` still exits
  0, as before, because `run_setup_or_developer` warns on rc 2.
- The helper-installed tools still have no checksums (backlog row); TLS and the https-only
  resolve are the only integrity check.
- Base's `apt update` warning does not fire for a source whose host does not resolve,
  because `apt-get update` exits 0 there (measured; backlog row).

## Related

- Spec: `docs/superpowers/specs/2026-10-04-ubuntu-step-midstep-failures-design.md`
- Plan: `docs/superpowers/plans/2026-10-04-ubuntu-step-midstep-failures.md`
- dotfiles#313
- ADR-0039 (pinned apt keys), ADR-0040 (unattended conffile prompts)
