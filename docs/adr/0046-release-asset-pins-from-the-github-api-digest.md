# ADR-0046: Release asset pins come from the GitHub API digest

**Date:** 2026-10-14
**Status:** Accepted

## Context

`_install_fetched_binary` downloaded kind and yq over TLS alone and installed them. A changed,
truncated or substituted asset, or a redirect to another host, installed without notice.
shellcheck already carried sha256 values for CI, but nothing recorded which version they
belonged to.

GitHub's releases API reports a `digest` (`sha256:<hex>`) for each asset, so a pin can be read
without downloading the asset.

## Decision

- Pins are `<TOOL>_SHA256_AMD64`, `<TOOL>_SHA256_ARM64` and `<TOOL>_SHA256_FOR_VER` in
  `lib/constants.sh` for kind, yq and shellcheck. `_FOR_VER` names the version the digests
  belong to. The installer refuses a pin that is missing, malformed or whose `_FOR_VER` differs
  from `*_VER`, before any download, and verifies the download before extracting it.
- `scripts/refresh-sha256-pins.sh` writes the pins from the API digest. It does not download.
  With no tool named it refreshes only stale tools. It refuses a changed digest at an unchanged
  version unless `--accept-changed` is passed, refuses a symlinked target and a malformed
  constants file, and writes atomically. A hand bump is: edit `*_VER`, run the script, commit
  both. A committed-constants test fails until the pins match.
- Stamps for pinned tools hold `<url> <sha256>`, so a changed pin reinstalls.
- `_install_fetched_binary --unverified` stays for consul, vault, nomad, packer and vagrant,
  and is refused for any other name. It is removed when those tools move to HashiCorp's signed
  apt repository with version holds (PR B).
- `check-versions` compares the pin, not the installed binary, with GitHub's latest for kind,
  yq and shellcheck. `--update` for kind and yq runs the refresher; shellcheck prints a
  hand-bump instruction because three `ci.yml` sites also carry its version and hashes.
- telepresence, cf-terraforming and standalone docker-compose are no longer installed.

### Trust model

The pins come from the API digest at the time the refresher ran. They protect later installs
against a changed, truncated or substituted download and against a redirect to another host,
and the refresher will not re-pin a changed asset at an unchanged version without
`--accept-changed`. They are not independent provenance: a release compromised before the
refresher ran is pinned as is. Verification downloads each pinned asset and hashes it, a
derivation independent of the API digest, which catches a wrong digest or a mis-mapped asset,
not a compromised release.

### Rejected

- Checksum files published beside the assets: they are not published for every tool, formats
  differ, and they are served from the same release as the asset.
- Downloading in the refresher and hashing locally: it costs bandwidth for each tool and
  arch, and the API already states the digest.

## Consequences

- A bump costs one script run and an extra committed diff.
- The pin is only as trustworthy as the release at refresh time (see Trust model).
- Linux boxes other than claude and workstation keep the retired binaries until they are
  removed by hand: `sudo rm /usr/local/bin/<tool>` and `rm ~/.local/share/dotfiles/installed/<tool>`.
- The HashiCorp tools remained TLS-only until PR B (see Amendment 2026-10-16).

## Amendment 2026-10-16: HashiCorp tools move to apt (PR B)

PR B retires `--unverified`. packer and vagrant now install from HashiCorp's signed apt
repository, through a source file kept outside `/etc/apt` that only the install step's own
`apt-get` commands read, so no other apt run can see it, upgrade from it, or need it held.
The signing key is vendored and pinned by fingerprint. consul, vault and nomad were removed, not
moved; their stamped copies are deleted by the install step. On macOS packer comes from
`hashicorp/tap`, and vagrant stays a cask. `check-versions` now compares the packer and vagrant
pins with GitHub's latest release, and `--update` writes only `*_VER`.

## Related

- Spec: `docs/superpowers/specs/2026-10-13-release-asset-sha256-design.md`
- ADR-0041 (stage, rename and stamp), ADR-0043 (executed-installer pins are report-only)
