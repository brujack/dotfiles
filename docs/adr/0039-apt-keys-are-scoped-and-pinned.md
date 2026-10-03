# ADR-0039: Third-party apt keys are scoped and pinned, never global

**Date:** 2026-10-03
**Status:** Accepted.

## Context

`lib/linux_ubuntu.sh` installed two third-party apt sources with machine-wide trust. azure-cli
fetched Microsoft's key over plain `http://` into `/etc/apt/trusted.gpg.d/` and added an
`http://` source with no `signed-by`. albert fetched its OBS key over https but also wrote it
into `trusted.gpg.d`, with an `http://` source. A key in `trusted.gpg.d` signs for every
source on the machine, so anyone on the path of the azure key fetch could gain root package
installs on every Linux machine that runs setup. Both machines (`claude`, `workstation`)
carried both global keys when this was measured.

Edge already used a vendored Microsoft key, but its keyring check passed if any `fpr:` line
matched the pin, which includes a subkey's. An attacker can attach a pinned public key to
their own primary as an encrypt-only subkey without the private key, so that check would have
trusted the attacker's primary.

## Decision

1. Every third-party apt source uses a dedicated keyring through `signed-by`. Nothing is
   written to `/etc/apt/trusted.gpg.d/`, and setup deletes the legacy global keys and sources.
2. One builder, `_build_pinned_keyring`, makes those keyrings. It dearmors and verifies in a
   temp directory, accepts exactly one primary key whose own fingerprint equals the pin, and
   stages the install to `<keyring>.new` before `mv`, so a failed build never touches a
   working keyring. It returns 0 installed, 1 for a key that is not the pinned one, 2 when no
   usable key could be read, and 3 for a local failure.
3. A fetched key is pinned by fingerprint in `lib/constants.sh` (`ALBERT_GPG_FPR`), not
   vendored, so an upstream expiry extension is picked up while a key change fails closed.
4. Where a maintained Homebrew formula exists, prefer it to adding an apt repository:
   azure-cli moved to linuxbrew, which removed its apt key entirely.

## Consequences

- A caller decides what each return means for its source. Albert keeps its last verified
  source on 2 and 3 (a network or local failure) and removes it on 1 (a different key).
- On the first run after migration there is no previous albert source to keep.
- `az` now resolves only through linuxbrew, which interactive zsh alone puts on `PATH`.
- `migration-classifier` records this kind of host-provisioning change as code-only; a revert
  needs a re-run of `-t developer` plus `brew uninstall azure-cli` to restore a machine.

## Related

- Spec: `docs/superpowers/specs/2026-10-03-scoped-apt-keys-azure-albert-design.md`
- dotfiles#309
