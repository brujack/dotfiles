# HashiCorp tools: remove consul, vault and nomad; install packer and vagrant from HashiCorp's signed apt repo (PR B)

Date: 2026-10-15
Status: Draft
Related: ADR-0046 (release asset pins, PR A), `docs/superpowers/specs/2026-10-13-release-asset-sha256-design.md`

## Problem

`_install_ubuntu_hashicorp` (`lib/linux_ubuntu.sh`) installs consul, vault, nomad, packer and
vagrant with `_install_fetched_binary --unverified`: each zip is downloaded from
`releases.hashicorp.com` and installed into `/usr/local/bin` with nothing but TLS behind it. The
`--unverified` mode exists only for these five tools, and its output says "not verified (pending
HashiCorp apt, PR B)". ADR-0046 line 59 and the backlog row "HashiCorp tools are installed without
a checksum" record that PR B would move them to HashiCorp's signed apt repo.

The operator uses only packer and vagrant. consul, vault and nomad are installed on every Linux
developer box and every `HAS_DEVTOOLS` mac for no purpose. That changes PR B's shape: the three
server tools are removed rather than moved, which also removes the reason the apt repo was costly —
their debs create service users, `/etc/<tool>.d` conffiles, `/opt/<tool>` and a systemd unit, and
vault's postinst writes a self-signed TLS key and runs `setcap`. packer and vagrant debs do none of
that (measured below).

Two further defects surfaced while exploring:

- **vagrant on arm64 is broken today.** The loop forces `_arch=amd64` for vagrant, so an arm64 box
  receives an amd64 binary. HashiCorp publishes no arm64 Linux vagrant, in the zips or the apt repo.
- **macOS packer is four years stale.** The Brewfile's `brew "packer"` resolves to homebrew-core,
  which froze at 1.9.4 (the last MPL release). The Studio has 1.9.4 installed; Linux pins 1.16.1.
  `hashicorp/tap/packer` tracks current releases.

## Measurements

Each line names the population the command covered.

- **apt repo dists.** `apt.releases.hashicorp.com` serves at least `noble`, `resolute`, `jammy`,
  `questing`, `plucky` and `bookworm` (the last three found by the round-7 goal-fit lens;
  `questing`'s `InRelease` is still signed with the old key `AA16FCBCA621E701`).
  Measured on the repo's `dists/` index, 2026-10-14. Unlike the noble-fallback repos in ai-config
  memory `dotfiles-ubuntu26-third-party-repo-noble-fallback`, `resolute` is present, so the
  `.list` uses the box's own codename.
- **Pinned versions present.** `packer 1.16.1-1` and `vagrant 2.4.9-1` are in `noble` for amd64,
  and `packer 1.16.1-1` for arm64; vagrant has no arm64 entry. Measured on
  `dists/noble/main/binary-{amd64,arm64}/Packages.gz`, 2026-10-15. Step 8 lenses then read all
  four `{noble,resolute}` x `{amd64,arm64}` indexes: packer 1.16.1-1 is in all four, vagrant
  2.4.9-1 in both amd64 and neither arm64.
- **Revision suffix is not always `-1`.** The noble amd64 index also carries `packer 1.6.1-2`,
  `packer 1.6.2-2` and `vagrant 2.2.10-4`; every recent version is `-1`. Measured by the Step 8
  goal-fit and ergonomics lenses on that one index.
- **Deb contents.** `packer_1.16.1-1_amd64.deb`: `/usr/bin/packer`, a licence file, a
  `conffiles` entry, no maintainer scripts; `Depends: openssl`. `vagrant_2.4.9-1_amd64.deb`:
  `/usr/bin/vagrant` and `/opt/vagrant/**`, no maintainer scripts, no `Depends`. Measured with
  `dpkg-deb -c`/`-I` on the two amd64 debs only; the arm64 packer deb was not opened.
- **Signing key.** `https://apt.releases.hashicorp.com/gpg`: rsa4096, primary fingerprint
  `D55C0D1AC78A8D8126CB631CFC9CA96ACA026560`, created 2026-09-09, expires 2031-09-08, uid
  "HashiCorp Security (HashiCorp Package Signing) <security+packaging@hashicorp.com>". Measured on
  the file as served 2026-10-14.
- **Live state.** On `claude` and `workstation`: all five tools in `/usr/local/bin`, each with a
  stamp in `~/.local/share/dotfiles/installed/` (the `claude` packer stamp is the 1.15.4 zip URL),
  and no HashiCorp dpkg package, apt source or keyring. Measured on those two boxes only (the
  `workstation` reading by the Step 8 risk lens over `ssh`).
- **nala and holds.** `-t update` upgrades with `nala full-upgrade`. nala 0.16.0's
  `nala/nala.py:316-342` collects packages apt's depcache kept back into a separate `held_pkgs`
  table after `cache.upgrade`, i.e. it reports holds rather than overriding them. Read from the
  source on `claude` only. The pins are already the newest versions in the repo, so a live check
  needs a held older version with a newer candidate; V1 does that.
- **apt update exit status.** Depends on whether the source was ever fetched. Never fetched, wrong
  key: rc 100, `E: The repository '…' is not signed.` Fetched once with the right key, then the
  `signed-by=` keyring swapped for another key: rc 0, three warnings ending
  `NO_PUBKEY FC9CA96ACA026560` ("the previous index files will be used"), and `apt-cache madison
  packer` still lists `1.16.1-1`. An unreachable host: rc 0, warnings only. The first case was
  measured by the round-2 risk lens; the fetched case by the round-4 ergonomics lens and again by
  the orchestrator, unprivileged with every `Dir::` path in a sandbox, on `claude` (apt 3.x) and
  `workstation` (apt 3.2.0), both resolute. noble's apt 2.7 is unmeasured. Round 2 measured only
  the never-fetched case and generalised it (K4').
- **Diagnostic prefix depends on the frontend.** On apt 3.2.0, `apt-get update` prefixes
  diagnostics `W:`/`E:`; `apt update` prefixes them `Warning:`/`Error:`, also when output is not a
  terminal. Both write them to stderr; stdout carries only `Hit:`/`Get:`/`Err:` progress, and the
  `Err:` line's `NO_PUBKEY` continuation is on its own indented line without the host. The round-4
  "three `W:` lines" were `apt-get` output. Measured on `claude` (sandbox, update) by the
  orchestrator and all three round-5 lenses, and on `workstation` (install path).
- **macOS.** On the Studio: core `packer` 1.9.4 installed, `vagrant` cask 2.4.9 installed, and
  `consul`, `vault`, `nomad` formulae installed. Measured on the Studio only.

## Alternatives considered

- **Keep the zips, verify each against HashiCorp's signed `SHA256SUMS`.** Every release publishes
  `<tool>_<ver>_SHA256SUMS` and a detached `.sig`, made with HashiCorp's long-standing release key
  (subkey `374EC75B485913604A831CC7C820C6D5CD27AB87`), a different key from the apt key. This would
  keep `/usr/local/bin`, need no apt source, no holds and no migration. Rejected by the operator on
  2026-10-15 in favour of the apt repo, which ADR-0046 and the backlog row had already named as
  PR B's plan: apt verifies index and package with one key through a mechanism every other
  third-party source on these boxes already uses, and removing the three server tools removed the
  deb side effects that had made apt costly. Cost the apt route carries that the zips do not: once
  HashiCorp's signer changes, the source goes stale silently and packer/vagrant stop receiving
  pin bumps until a new key is vendored (section 2, "Key rotation is silent").
- **apt with no pin.** Let the repo's latest flow through `-t update`. Rejected: the pin in
  `lib/constants.sh` stays the single authority for what version a box runs ("own the stack"),
  which is what the hold buys. The cost is a "kept back" line for packer and vagrant on every
  `-t update`, and a bump needs check-versions, a PR and a `-t setup`/`-t developer` run per box.
- **Transient apt source.** Write `hashicorp.list`, `apt update`, install `<tool>=<ver>`, remove
  the `.list`. With no source, `-t update` has no newer candidate, so no hold is needed, and a key
  rotation fails only this step. Raised by the round-3 goal-fit lens. Rejected by the operator on
  2026-10-15: HashiCorp has changed its apt key twice in about four years, both times unplanned
  (`…AA16FCBCA621E701`, then `…FC9CA96ACA026560` on 2026-09-09/10 after a delivery-pipeline
  incident, HCSEC-2026-33). At that rate the persistent source costs little, and section 2's
  rotation check makes the rare event loud. The holds' one open assumption (nala respects them) is
  settled by V1. [The decision was taken while the spec still claimed a rotation stops OS updates;
  round 4 showed that false, which weakens the transient source's case further.]

## Design

### 1. Removals (Linux and macOS)

- `_install_ubuntu_hashicorp` installs packer and vagrant only (section 2).
- `lib/constants.sh` loses `CONSUL_VER`, `NOMAD_VER`, `VAULT_VER` and `HASHICORP_URL`.
- `_install_fetched_binary` loses its `--unverified` mode: the argument parsing, the
  consul/vault/nomad/packer/vagrant allow-list, the URL-only stamp form and the
  "not verified (pending HashiCorp apt, PR B)" line. Every remaining call is the pinned form.
  Tests of the `--unverified` mode are deleted with it.
- `.config/.zshrc.d/5_general.zsh` loses the vault/consul/nomad completion block (the
  `complete -o nospace -C /usr/local/bin/<tool>` lines and their comment).
- `Brewfile` loses `brew "consul"`, `brew "nomad"`, `brew "vault"` and the commented
  `#brew "vault", args: [...]` line.

### 2. Linux: packer and vagrant from the signed apt repo

New constant `HASHICORP_GPG_FPR="D55C0D1AC78A8D8126CB631CFC9CA96ACA026560"` and a vendored key
`keys/hashicorp.asc` (the file as served at `https://apt.releases.hashicorp.com/gpg`). The key path
defaults to `${DOTFILES_REPO_ROOT}/keys/hashicorp.asc`, resolved at source time in
`lib/constants.sh` as a plain assignment, the same rule as `_AWS_KEY_PATH`; no network fetch of the
key happens at install time.

`_install_ubuntu_hashicorp` then:

1. **Migration of the removed tools** (section 3) runs first, on every path.
2. **Keyring.** `_build_pinned_keyring <vendored key> <_APT_KEYRINGS_DIR>/hashicorp-archive-keyring.gpg "${HASHICORP_GPG_FPR}"`.
   rc 1 (not the pinned key) removes the `.list` and keyring and fails the step; rc 2/3 keep the
   last verified keyring and `.list` and fail the step, mirroring `_install_ubuntu_albert`.
3. **Log, then source.** First `_log` is created with `mktemp` under a new
   `_HASHICORP_LOG_TMP_ROOT` seam (default `${TMPDIR:-/tmp}`; its own seam because step 2's
   `_build_pinned_keyring` already makes its temp dir under `_APT_KEY_TMP_ROOT`, and BSD `mktemp`
   with a template ignores `TMPDIR`). If `mktemp` fails, the step prints
   `hashicorp: cannot create a log under <dir> (mktemp failed); packer, vagrant not installed` on
   stderr and returns 1 before writing any source. That deliberately stops earlier than the step-4
   log failures: with no log the step could not decide step 4's removal, so it writes no source.
   Then `_write_apt_source_list` writes
   `<_APT_SOURCES_DIR>/hashicorp.list` containing
   `deb [arch=<dpkg --print-architecture> signed-by=<keyring>] https://apt.releases.hashicorp.com <lsb_release -cs> main`.
4. **Refresh.** `sudo -H apt-get update 2>&1 | tee "${_log}"`, with `tee`'s status taken from
   `${PIPESTATUS[1]}` (`lib/` is bash); `apt-get`'s own status is ignored (base owns the update
   warning, as in `_install_ubuntu_gui_tools`). `apt-get`, not `apt`: its CLI is stable and its
   diagnostics are prefixed `W:`/`E:`, where `apt` 3.x prints `Warning:`/`Error:`
   (Measurements). `2>&1` because the diagnostics are on stderr. `tee` keeps progress on screen,
   so a slow mirror does not look like a hang. Both `grep` verdicts below are computed, then
   `_log` is removed at once (one removal point; traps are banned in `lib/` and nothing reads the
   log later).
   **Log check.** A non-zero `tee` status, an empty `_log` (`apt-get update` always prints at least
   `Reading package lists...`), or a `grep` exit status of 2 or more prints
   `hashicorp: rotation check not run (no log)`; the step still attempts both tools (the `.list`
   is already written) and will return 1. A missing or empty log is never read as "no match".
   **Source failure removal.** When any line of `_log` starts `E:` and contains
   `apt.releases.hashicorp.com`, this source made `apt-get update` fail, and every later
   `apt update` on the box would exit 100 while the `.list` exists (blocking `-t update`'s apt
   section, powershell and nvidia). The step removes `hashicorp.list`, keeps the keyring, prints
   `hashicorp: hashicorp.list removed (apt-get update failed for it: <first such E: line>);
   packer, vagrant not installed`, skips both tools (no not-found lines), and will return 1. In
   `apt-get`, `E:` for a source means that source failed the update; `W:` means apt continued, as
   for a rotated key on a box with previous lists (rc 0) or an unreachable host (rc 0). Measured
   `E:` inputs: wrong key with no lists (`is not signed`, rc 100, twice in a row), lists deleted
   then wrong key (same), a codename the repo does not serve (`does not have a Release file`), and
   unsigned or HTML data on a fetched box (`is no longer signed`, `NOSPLIT`, rc 100). Cost: a box
   behind a proxy that served bad data once waits for the next `-t setup`/`-t developer` to
   recreate the source; the held packages stay installed.
   **Rotation check.** When any `W:` or `E:` line of `_log` contains `apt.releases.hashicorp.com`
   and one of `NO_PUBKEY`, `EXPKEYSIG`, `EXPSIG`, `KEYEXPIRED`, `REVKEYSIG`, `is not signed` or
   `is no longer signed`, the step prints
   `hashicorp: apt.releases.hashicorp.com is not verified by keys/hashicorp.asc (key rotated or
   expired, or the host served unsigned data); re-vendor keys/hashicorp.asc from
   https://apt.releases.hashicorp.com/gpg after verifying it out of band, and if its primary
   fingerprint changed also edit HASHICORP_GPG_FPR in lib/constants.sh` on stderr and will
   return 1. An expiry extension keeps the fingerprint, so only the file changes; a rotation
   changes both, and re-vendoring the file alone would trip step 2's rc 1 on the next run. On a
   box with previous lists (only `W:` lines) the tools are still attempted: apt keeps those lists,
   so the current pins usually still install.
5. **Per tool**, packer then vagrant, each attempted regardless of the other:
   - vagrant on a box whose `_LINUX_ARCH` is not `amd64` is skipped with
     `hashicorp: vagrant: no arm64 build; skipped`. The skip itself counts as success; a failed
     removal of a stamped vagrant at that point (section 3) still fails the step.
   - **Resolve the deb version.** The candidate is the highest version `apt-cache madison <tool>`
     lists whose version field (column 2 of madison's `|`-split output, whitespace trimmed) has
     upstream part exactly `<VER>` (matches `^<VER>-`). Real madison lines start with a padded
     package name, so a match on the raw line never succeeds. None found: fail the tool
     with `hashicorp: <tool>: <VER> not in apt.releases.hashicorp.com; the release may not be
     published yet, apt update may have failed, or the repo key may have rotated (keys/hashicorp.asc)`.
   - **Already done:** `dpkg-query -W -f='${db:Status-Abbrev} ${Version}'` prints `ii ` and a
     version whose upstream part is `<VER>`, **and** `apt-mark showhold` lists the tool. Skip the
     install with `<tool>: up to date (<installed deb version>, held)`, then still run the
     stamp-gated removal below: a run whose removal failed after a good install takes this branch
     next time, and the stale `/usr/local/bin` copy would otherwise shadow `/usr/bin/<tool>`
     forever. A package in `rc` state (removed, conffiles left) is not done.
   - **Otherwise:**
     `sudo -H DEBIAN_FRONTEND=noninteractive apt-get install -y "${APT_CONFFILE_OPTS[@]}" --allow-change-held-packages --allow-downgrades <tool>=<resolved version>`,
     then `sudo apt-mark hold <tool>`. `--allow-change-held-packages` lets a pin bump replace a
     held version; `--allow-downgrades` lets a pin rollback do the same. The first flag applies to
     the whole transaction, so a hold the operator placed on packer's dependency `openssl` would
     also be overridden if that transaction touched it; accepted, since the transaction names only
     the one tool.
   - **Then** remove the tool's stamped `/usr/local/bin` copy (section 3), only after its apt
     install and hold succeeded, or on the already-done branch above.
   - A failure is named `hashicorp: <tool>: <install|hold|remove> failed` on stderr.
6. Returns 0 when every attempted tool succeeded and the rotation check stayed quiet, else 1 (the
   existing step contract).

The hold means `-t update`'s apt upgrade keeps both packages back; the pin in `lib/constants.sh` is
the only thing that moves them, by the next `-t setup`/`-t developer` run.

**Key rotation is silent.** Once HashiCorp signs with a key other than the vendored one, a box that
already fetched the source keeps using its previous index files: `apt update` exits 0 with three
warnings (`Warning:` from `apt`, `W:` from `apt-get`; Measurements). `update_apt_packages`' `apt update || return 1` does not trip, so OS
updates continue; what stops is the HashiCorp source itself, which goes stale. A second trigger is
expiry: the vendored copy expires 2031-09-08, and if HashiCorp extends that key's expiry the
vendored copy goes stale the same way (EXPKEYSIG). Without a check the staleness surfaces only at
the next `PACKER_VER`/`VAGRANT_VER` bump, through the not-found line. The step-4 rotation check
names it on the next `-t setup`/`-t developer` instead: one line on stderr, and `hashicorp` listed
once in the `ubuntu packages: failed:` summary; `-t developer` still exits 0 (CLAUDE.md), and the
same run may print `up to date` lines from the stale lists. `-t update` does not run this step, so
there it stays a scrolled warning. A box that never fetched the source is different: every
`apt update` exits 100 while the `.list` exists, which would block `-t update`'s apt section,
powershell and nvidia; step 4's source failure removal deletes the `.list` in that case, and in
every other case where apt-get reports an `E:` for this source. Every
persistent third-party source on these boxes (12 on `claude`) has the same silent-staleness
exposure, fetched keys included, since nothing re-fetches a key; that class is a P2 backlog row in
`docs/superpowers/README.md`. No stopgap is needed.

### 3. Migration of existing boxes

consul, vault and nomad are handled before the keyring step. packer and vagrant are handled per
tool, after that tool's apt install and hold succeeded or on its already-done branch, so a failed
apt install (repo down, version not yet published, wrong key) never leaves a box with neither the
old binary nor the new one. For each tool, at its point:

- If `${_DL_STAMP_DIR}/<tool>` exists, dotfiles installed `${_DL_BIN_DIR}/<tool>`: remove the
  binary (`sudo rm -f`) and the stamp (`rm -f`), and log `hashicorp: removed <path> (installed by dotfiles)`.
- If there is no stamp but `${_DL_BIN_DIR}/<tool>` exists, it is not ours: leave it and warn. For
  packer and vagrant the warning says it shadows `/usr/bin/<tool>` on PATH and names the remove
  command.
- A failed removal is named and fails the step; the install still runs.
- What the removal destroys on a stamped path: whatever file is there now. A stamp proves dotfiles
  wrote that path; it does not prove the operator has not since replaced the file. That case is
  accepted: replacing a dotfiles-managed binary by hand without deleting its stamp is outside any
  workflow this repo supports.
- On an arm64 box vagrant is never apt-installed (section 2), so a stamped arm64 vagrant (the
  broken amd64 binary) is removed at that point instead, with the skip line.

The second run finds no stamps and removes nothing. A run interrupted between hold and removal
leaves a stamp; the next run takes the already-done branch and removes it there. Brew formulae on macOS are not removed by any
code: `brew bundle` installs and never uninstalls.

### 4. macOS, check-versions, docs

- **Brewfile.** Add `tap "hashicorp/tap", trusted: true` and replace `brew "packer"` with
  `brew "hashicorp/tap/packer"`, both tagged `# [HAS_DEVTOOLS]`. `vagrant` stays a cask. The tag
  selects drift expectations only (CLAUDE.md, Brewfile Capability Tags): every mac, `mac_mini`
  included, taps hashicorp/tap and installs tap packer. macOS packer is unpinned: the tap installs
  its latest, as the vagrant cask already does. `PACKER_VER` governs Linux only.
- **Core-packer guard.** Every mac has homebrew-core `packer` today (the main Brewfile installs
  every entry whatever its tag), and the tap formula declares `conflicts_with "packer"`, so the
  main `brew bundle` is expected to fail. That failure returns through `install_macos_casks`
  (`lib/macos.sh`), `install_macos_packages` and `run_setup_or_developer` (`lib/workflows.sh`), so
  the whole `-t setup`/`-t developer` run aborts: gui and devtools bundles, cargo tools, vim plugins,
  pyenv, the ansible venv and ruby. `run_brew_install` (`--brew-install`) also calls
  `install_macos_casks` and exits non-zero the same way. The guard does not shrink that abort; it
  makes it clear and leaves nothing half-run. A warning before a bundle that still runs would
  scroll away under its output. So, before the main bundle, `install_macos_casks` checks
  `brew list --formula --full-name` for a bare `packer` line and, when present, prints one line,
  `homebrew-core packer conflicts with hashicorp/tap/packer: run 'brew uninstall packer consul
  vault nomad', then re-run`, and returns 1 without running the bundle. It removes nothing (N1).
  `-t update` never calls `install_macos_casks`; there the first signal is the brew-drift WARN
  (untracked `packer consul nomad vault`, missing `hashicorp/tap/packer` and its tap), and the
  CLAUDE.md manual step is the remedy. The bundle failure itself is expected, not measured: the Studio is
  migrated by the uninstall first, so the conflict is never observed there.
- **Tap trust.** Homebrew requires tap trust by default (unless `HOMEBREW_NO_REQUIRE_TAP_TRUST`
  is set), and `install_macos_casks` runs `brew trust` *after* `brew bundle`. A new tap listed only
  in that call is untrusted on the first bundle, the bundle fails, and `|| return 1` skips
  `Brewfile.gui` and `Brewfile.devtools`. So the Brewfile's own `trusted: true` (supported by
  `brew bundle`'s tap entry) is what trusts the tap on first contact. `hashicorp/tap` is also added
  to the two `brew trust` calls that list the macOS taps (`install_macos_casks` in `lib/macos.sh`
  and the update path in `lib/helpers.sh`), so the list stays complete. Homebrew 7.0.9's
  `bundle/installer.rb:81` applies `trusted: true` before anything loads the entries (read by the
  round-3 lenses on the Studio); whether that holds on a tap not yet tapped is unmeasured, and V2
  starts from that state. The Linux
  brew-packages call is unchanged: Linux packer comes from apt.
- **check-versions.** packer and vagrant are checked pin-against-latest, through
  `_run_cv_pinned_release` (the kind/yq/shellcheck route), never installed-binary-against-latest:
  on a mac the tap and the cask track latest, so the installed-binary route would report OK while
  the pin is stale. `_run_cv_pinned_release "packer" "${PACKER_VER}" "hashicorp/packer" "PACKER_VER"`
  is added and vagrant's `_run_cv_check` line is replaced by
  `_run_cv_pinned_release "vagrant" "${VAGRANT_VER}" "hashicorp/vagrant" "VAGRANT_VER"`.
  `--update` for both writes only the `*_VER` line (no digests). Both stay in the token-gated set
  the CLAUDE.md `check-versions` paragraph derives its count from. Known window, both tools:
  GitHub can publish a release before the apt repo carries it; a `--update` in that window writes
  a pin apt cannot install yet, and the next install fails with the section 2 "not in
  apt.releases.hashicorp.com" line. Accepted and documented rather than solved.
- **ADR-0046** gets a dated amendment: PR B moved packer and vagrant to the signed apt repo with
  holds, and consul, vault and nomad were removed, not moved.
- **`docs/superpowers/README.md`**: remove the backlog row "HashiCorp tools are installed without a
  checksum"; reword "check-versions covers under half the pins" to drop the HashiCorp tools.
- **CLAUDE.md**: the release-asset-pins bullet no longer mentions `--unverified`; add the one-time
  manual steps (`brew uninstall packer consul vault nomad` on each mac before the first
  `-t setup`, `-t developer` or `--brew-install` after this merges; unstamped `/usr/local/bin`
  leftovers by hand).

### 5. Testing

bats in `tests/setup_env/linux_ubuntu.bats`, against existing seams: `_APT_SOURCES_DIR`,
`_APT_KEYRINGS_DIR`, `_APT_KEY_TMP_ROOT`, `_MS_GPG_BIN` (real gpg, so the fingerprint pin is
genuinely exercised), `_DL_STAMP_DIR`, `_DL_BIN_DIR`, and the sudo/apt mocks. A new
`_HASHICORP_KEY_PATH` seam is honoured only when `BATS_TEST_TMPDIR` is non-empty, so a test can feed
a wrong key without touching the vendored one.

Mock seams that do not exist and are added:

- a new `tests/mocks/apt-cache` whose `madison <pkg>` prints the file named by
  `MOCK_APT_MADISON_<pkg>` (absent means no versions). Without it, `madison` would read the host's
  real apt state. The fixtures are captured real output, never hand-typed (tdd.md pitfall F):
  `tests/fixtures/apt-cache/madison-packer.txt` and `madison-vagrant.txt`, padding and `| url`
  column included. No box has the source, and none is needed: run `apt-get update` and
  `apt-cache madison` unprivileged with `-o Dir::State`, `Dir::State::Lists`, `Dir::Cache`,
  `Dir::Etc::sourcelist`, `Dir::Etc::sourceparts`, `Dir::Etc::Parts`, `Dir::Etc::TrustedParts`,
  `Dir::Log` pointed into a scratch dir, `Debug::NoLocking=1` and `APT::Sandbox::User=$(id -un)`,
  with a one-line `.list` signed by the dearmored vendored key (two lenses and the orchestrator
  did this in round 4). The no-match case needs no edit (set the pin to an unpublished version);
  only the `-2` case edits a copy of a captured file;
- `update` output in `tests/mocks/apt-get`: `MOCK_APT_GET_UPDATE_OUTPUT` names a file whose `W:`/
  `E:` lines the mock prints to stderr and whose other lines it prints to stdout, for
  `apt-get update`, so an implementation that captures stdout only goes red. Fixtures
  `tests/fixtures/apt/update-hashicorp-rotated.txt` (fetched, then wrong key: rc 0, `W:` lines)
  and `update-hashicorp-never-fetched.txt` (`E: … is not signed`), captured with the sandbox
  recipe using `apt-get … update 2>&1`, the same binary and streams the step runs. A fixture
  captured with `apt` would hold `Warning:` lines and test a different program;
- `showhold` support in `tests/mocks/apt-mark`, printing `MOCK_APT_MARK_HOLD`;
- a flag-aware `tests/mocks/lsb_release`: `-cs` prints `MOCK_LSB_RELEASE_CS`, `-rs` keeps
  `MOCK_LSB_RELEASE_RS`. Today the mock prints `MOCK_LSB_RELEASE_RS` for any arguments, so a `-rs`
  in place of `-cs` passes the suite and writes `26.04` into the `.list`, which makes `apt update`
  exit 100 on a real box. `MOCK_LSB_RELEASE_CS` defaults to `noble`, so the cloudflared `.list`
  (the one other `-cs` caller) never renders an empty codename. Existing callers keep passing.

Existing mocks that differ from the real tool, so the cases below set them to the real shape:
`tests/mocks/dpkg` prints `--print-architecture` only when `MOCK_DPKG_PRINT_ARCH` is set;
`tests/mocks/dpkg-query` prints `MOCK_DPKG_STATUS_<pkg>` verbatim and exits 0 for an unset package,
where real `dpkg-query -W -f='${db:Status-Abbrev} ${Version}'` prints two spaces after the status
(`ii  1.16.1-1`) and exits 1 for a package that is not installed.

Cases:

- clean install of both tools, with `MOCK_DPKG_QUERY_EXIT=1` (not installed): install line carries
  `packer=1.16.1-1`, `--allow-change-held-packages`, `--allow-downgrades` and
  `APT_CONFFILE_OPTS`, then `apt-mark hold packer`;
- `.list` content, with `MOCK_LSB_RELEASE_CS=resolute`, `MOCK_LSB_RELEASE_RS=26.04` and
  `MOCK_DPKG_PRINT_ARCH=armhf`: the whole line equals
  `deb [arch=armhf signed-by=<keyring path>] https://apt.releases.hashicorp.com resolute main`;
- rotation cases, each with both madison fixtures set and installs that succeed, so the rotation
  check is the only possible failure, and asserting the substring
  `is not verified by keys/hashicorp.asc` (the not-found line also names the key file):
  - `update-hashicorp-rotated.txt`: that line on stderr, rc 1, both tools installed, `hashicorp.list`
    still present;
  - `update-hashicorp-never-fetched.txt`: that line, the `hashicorp.list removed` line, rc 1,
    `hashicorp.list` absent, keyring present, no install call and no not-found line;
  - `update-hashicorp-no-release.txt` (a codename the repo does not serve, captured with the same
    recipe): no rotation line, the `hashicorp.list removed` line, rc 1, `hashicorp.list` absent;
  - clean output: no such line and rc 0;
- `_HASHICORP_LOG_TMP_ROOT` pointed at an unwritable directory (with `_APT_KEY_TMP_ROOT` writable,
  so step 2 succeeds): rc 1, the `cannot create a log under` line, no `hashicorp.list` written, no
  `apt-get update` call;
- `SHIM_TEE_FAIL_ARGS` set to the log path (so only the log's `tee` fails and the `.list` write
  succeeds): rc 1 and the `rotation check not run (no log)` line;
- no file is left under `_HASHICORP_LOG_TMP_ROOT` after the step returns, on success and on
  failure;
- the step's refresh is recorded in the mock call log as `apt-get update` (sudo, `-H`), and no
  `apt update` call is recorded by this step, so the refresh command and the fixtures' capture
  command cannot drift apart;
- madison lists `1.16.1-2` and `1.16.1-1`: install line carries `packer=1.16.1-2`;
- madison lists no `1.16.1-`: rc 1 and the "not in apt.releases.hashicorp.com" line;
- installed `ii  1.16.1-1` (two spaces, as dpkg-query prints) and held: the line
  `packer: up to date (1.16.1-1, held)` and no install call;
- installed `rc  1.16.1-1` and held: install runs;
- installed at an older version and held: install runs;
- arm64: vagrant skip line, stamped vagrant removed, packer installed;
- arm64 with the vagrant removal failing: rc 1 and the removal named;
- a wrong key, with a `hashicorp.list` and keyring pre-seeded: rc 1, both removed, no install call;
- packer install fails: rc 1, packer named, stamped `/usr/local/bin/packer` and its stamp still
  present, vagrant still installed, held and its stamped copy removed;
- stamped `/usr/local/bin/consul`: binary and stamp removed, removal line printed;
- unstamped `/usr/local/bin/packer`: kept, shadow warning printed;
- second run after migration: both `up to date (…, held)` lines and no removal line;
- installed `ii  1.16.1-1`, held, and a stamped `/usr/local/bin/packer` still present: the
  `up to date` line, no install call, and the copy and stamp removed;
- mac: a bare `packer` in `brew list --formula --full-name` prints the line naming `brew uninstall packer consul vault nomad`, returns 1, and runs no `brew bundle`; `hashicorp/tap/packer` alone prints nothing and the bundle runs;
- check-versions: `PACKER_VER` behind the mocked GitHub latest reports outdated while the installed `packer --version` equals latest.

`tests/scripts/dpkg_sudo_frontend.bats` must pass over the new install line unchanged.

## Multi-Lens Review

### Round 1 — spec at `0ae607c9`

Three general-purpose lenses (goal-fit, ergonomics, risk), no conversation context. Adversarial
gate not triggered: no comparison design, no judge, concrete acceptance criteria. Every lens
re-verified the premise (stamps on `claude` and `workstation`, the four apt indexes, the key
fingerprint) and found it true. No R-vs-N contradiction found.

| # | Lens | Sev | Finding | Disposition |
|---|------|-----|---------|-------------|
| G1 | goal-fit | MAJOR | Signed-`SHA256SUMS` zip verification is never weighed against apt | Addressed: Alternatives section records it and the operator's choice |
| G2 / E5 | goal-fit, ergonomics | MINOR | `<VER>-1` is hardcoded; the index carries `-2`/`-4` revisions | Addressed: version resolved from `apt-cache madison` matching `^<VER>-` (R7) |
| G3 | goal-fit | MINOR | `dpkg-query ${Version}` reads an `rc` package as installed | Addressed: skip requires `ii` (R8) |
| G4 / E7 / K5 | all three | MINOR | "held: no install call" and "second run: no removal lines" pass on a no-op | Addressed: both assert the `up to date (…, held)` lines |
| E1 | ergonomics | MAJOR | check-versions compares the installed binary, so a mac tracking latest hides a stale pin | Addressed: packer and vagrant move to `_run_cv_pinned_release` (R16) |
| E2 | ergonomics | MAJOR | V2's `packer --version == PACKER_VER` fails once the tap moves past the pin | Addressed: macOS packer declared unpinned; V2 asserts at-or-above |
| E3 | ergonomics | MAJOR | Core packer left on a mac makes `brew bundle` fail and skips the gui/devtools bundles | Addressed: pre-bundle warning naming the uninstall (R17); conflict expected, not measured |
| E4 | ergonomics | MINOR | The hold's cost (kept-back line, per-box bump) is not named | Addressed: Alternatives, "apt with no pin" |
| E6 | ergonomics | MINOR | The release-before-apt window applies to vagrant too | Addressed: section 4 names both tools |
| E8 | ergonomics | MINOR | `[HAS_DEVTOOLS]` reads as gating install; it gates drift only | Addressed: section 4 states every mac gets the tap |
| K1 | risk | MAJOR | Migration deletes packer/vagrant before apt has a replacement | Addressed: removal after that tool's install and hold succeed (R12) |
| K2 | risk | MINOR | A pin rollback aborts without `--allow-downgrades` | Addressed: flag added (R7) |
| K3 | risk | MINOR | `--allow-change-held-packages` is transaction-wide (openssl hold) | Addressed: accepted and stated in section 2 |
| K4 | risk | MINOR | A key rotation fails silently until a bump, then names packer | Addressed: the not-found line names the key file [round 2 K4': wrong — rotation blocks `-t update`] |

**Assumption lines.**

- Goal-fit: HashiCorp keeps publishing new releases to apt promptly. Partly measured: every recent
  version in the index is `-1`; publish lag is unmeasured. Covered by the documented window.
- Ergonomics: `brew bundle` hard-fails with core packer installed. Unmeasured; R17 warns either way.
- Risk: `nala full-upgrade` respects apt holds. Source read on `claude` (`nala/nala.py:316-342`
  reports held packages separately); V1 now checks it on a live hold. [round 2 E1': false — the
  pins have no newer candidate, so that V1 could not fail]

### Round 2 — spec at `0f85ea8f`

Same three lenses, fresh, no conversation context. Adversarial gate not triggered. Two of the
three MAJORs were created by round-1 fixes (V1's hold check, the tap added in R14).

| # | Lens | Sev | Finding | Disposition |
|---|------|-----|---------|-------------|
| E1' / K1' | ergonomics, risk | MAJOR | V1's `-t update` check cannot fail: the pins are already the repo's newest versions, so nala has no candidate held or not | Addressed: V1 holds `packer=1.16.0-1` with an unheld control |
| G1' | goal-fit | MAJOR | `brew trust` runs after `brew bundle`; with trust required by default the new tap is untrusted on first bundle, which fails and skips the gui/devtools bundles | Addressed: `trusted: true` on the Brewfile tap; V2 starts untapped and untrusted |
| K4' | risk | MAJOR | Round-1 K4 is wrong: a rotated key makes `apt update` exit 100 and `update_apt_packages` returns before upgrading anything [round 4 E1''': wrong for any box that fetched the source — rc 0, silent] | Accepted (operator, option c): section 2 states it; fleet-wide fix is a P1 backlog row |
| K2' | risk | MINOR | `apt-cache` mock and `apt-mark showhold` support do not exist; wrong-key case cannot show removal without pre-seeded files | Addressed: section 5 names both mocks and the pre-seed |
| G2' / E2' | goal-fit, ergonomics | MINOR | A removal that fails after a good install is never retried; the next run skips as up to date while `/usr/local/bin` shadows `/usr/bin` | Addressed: removal also runs on the already-done branch (R11, R12); new bats case |
| K3' | risk | MINOR | R11 "always removes" contradicts R12 "keeps on install failure" | Addressed: R11 is subject to R12 |
| E3' | ergonomics | MINOR | The not-found line blames release or key when `apt update` failed | Addressed: the line names a failed `apt update` too |

Not raised by a lens and kept: the tap formula declares `conflicts_with "packer"`, so R17's warning
partly repeats brew's own error; it is cheap and fires before the bundle. [round 3 E1'': wrong —
the bundle aborts the whole setup run; R17 now returns 1 before it]

**Assumption lines.** All three lenses named the same one: nala 0.16.0 `full-upgrade` keeps a held
package at its version when a newer candidate exists, and exits 0. Unmeasured; V1 as rewritten
settles it. G1' adds a second: `trusted: true` in a Brewfile works on a tap not yet tapped.
Unmeasured; V2 settles it.

### Round 3 — spec at `5c36a6f6`

Same three lenses, fresh. Adversarial gate not triggered. Every round-2 fix was re-verified:
`trusted: true` exists in Homebrew 7.0.9 bundle, `packer=1.16.0-1` is in the index, and
`InRelease` verifies with `gpgv` against the pinned key (Good signature, key `D55C…CA026560`).

| # | Lens | Sev | Finding | Disposition |
|---|------|-----|---------|-------------|
| G1'' | goal-fit | MAJOR | A transient apt source removes the holds, the nala assumption and this source's share of K4' | Rejected (operator): recorded under Alternatives with the rotation history |
| E1'' | ergonomics | MAJOR | R17 warns of a certain bundle failure and runs into it; the failure aborts the whole setup/developer run | Addressed: R17 returns 1 before the bundle; section 4 states the blast radius |
| K1'' | risk | MINOR | The madison mock invites a hand-typed fixture that hides a raw-line parser matching nothing on a box | Addressed: captured fixtures; R7 matches column 2 |
| K2'' | risk | MINOR | The `lsb_release` mock ignores flags, so a `-rs` for `-cs` passes the suite | Addressed: flag-aware mock; R6 test sets distinct values |
| G2'' / K3'' / E2'' | all three | MINOR | Rotation class is every persistent third-party source (12 on `claude`), expiry is a second trigger, and no stopgap is given | Addressed: section 2 and the P1 row widened; stopgap in section 2 and CLAUDE.md |
| K4'' | risk | MINOR | R9 says the arm64 skip never fails; section 3 fails the step on a failed removal | Addressed: removal failure counts (R9) |
| K5'' | risk | MINOR | V2 passes vacuously once any earlier run trusted the tap | Addressed: V2 untrusts first and checks `trust.json` |
| E3'' | ergonomics | MINOR | V1 asserts `-t update`'s whole exit code, which any unrelated section FAIL turns red | Addressed: V1 asserts the `apt` summary row |
| K6'' | risk | MINOR | V1's control expects exactly `1.16.1-1`; a newer release fails it falsely | Addressed: control asserts newer than `1.16.0-1` |
| G3'' | goal-fit | MINOR | The zips alternative omits the rotation cost apt carries | Addressed: cost stated in Alternatives |

**Assumption lines.** Goal-fit and risk: nala 0.16.0 `full-upgrade` keeps a held package back when
a newer candidate exists (unmeasured; V1). Risk also: HashiCorp signs `InRelease` with the pinned
primary key (verified with `gpgv`). Ergonomics: `brew bundle` exits non-zero when a formula
conflicts with an installed one (unmeasured; R17 holds either way).

### Round 4 — spec at `2743cb6d`

Same three lenses, fresh. Adversarial gate not triggered. Goal-fit and risk found no MAJOR; every
round-3 change was re-verified against the code.

| # | Lens | Sev | Finding | Disposition |
|---|------|-----|---------|-------------|
| E1''' | ergonomics | MAJOR | K4' is false for a box that fetched the source: a rotated key leaves `apt update` at rc 0 with `W:` lines and old lists, so OS updates continue and the HashiCorp source goes stale silently | Addressed: reproduced by the orchestrator on `claude` and `workstation`; section 2 rewritten, stopgap dropped, backlog row demoted P1 to P2 (operator), step-4 rotation check added (operator) |
| E2''' | ergonomics | MINOR | R17's guard does not shrink the abort, its line names only `packer`, and `-t update`'s first signal is unstated | Addressed: section 4 says so; R17's line names all four formulae and "re-run" |
| G1''' | goal-fit | MINOR | The stopgap lasts only until the next setup run | Moot: stopgap dropped with E1''' |
| G2''' / K3''' | goal-fit, risk | MINOR | No capture route for the madison fixtures is named (goal-fit thought none existed) | Addressed: the unprivileged sandbox recipe is in section 5 |
| K1''' | risk | MINOR | The R6 test never sets `MOCK_DPKG_PRINT_ARCH`, so `arch=` is unchecked | Addressed: whole-line assertion with `armhf` |
| K2''' | risk | MINOR | The dpkg-query mock prints one space and exits 0 for an absent package; real output has two spaces and rc 1 | Addressed: fixtures use the real shape; clean install sets `MOCK_DPKG_QUERY_EXIT=1` |
| K4''' | risk | MINOR | Section 4 omits `run_brew_install` as an R17 caller | Addressed |
| K5''' | risk | MINOR | V2 asserts all three bundles, so an unrelated cask failure turns it red | Addressed: V2 asserts the main bundle and the tap formula |

**Assumption lines.** Goal-fit: nala keeps a held package back (unmeasured; V1). Ergonomics: apt
keeps old lists and exits 0 on a fetched source's signer change (verified on two resolute boxes;
noble unmeasured). Risk: `trusted: true` trusts an untapped tap on first bundle (unmeasured; V2).

### Round 5 — spec at `4301333e`

Same three lenses, fresh. Adversarial gate not triggered. All three found the same MAJOR, created
by the round-4 fix.

| # | Lens | Sev | Finding | Disposition |
|---|------|-----|---------|-------------|
| G1⁗ / E1⁗ / K1⁗ | all three | MAJOR | R19 matches `^W:`/`^E:`, but the step runs `apt update`, which on apt 3.x prints `Warning:`/`Error:`; fixtures captured with `apt-get` would pass while production never fires | Addressed: refresh is `apt-get update 2>&1 \| tee`; fixtures captured with the same command; a test pins the refresh command; reproduced by the orchestrator (`grep -c '^W:'` = 0, three `Warning:`) |
| G2⁗ / E1⁗ | goal-fit, ergonomics | MINOR | The captured stream is unstated; diagnostics are on stderr, so a stdout capture is inert, and the mock cannot tell | Addressed: `2>&1` stated; the mock prints `W:`/`E:` lines to stderr |
| G3⁗ | goal-fit | MINOR | `is not signed` also follows unsigned data from a proxy; the message names only rotation | Addressed: message names both causes |
| E2⁗ | ergonomics | MINOR | "Loud" overstates it: one summary entry, `-t developer` exits 0 | Addressed: section 2 states exactly what is shown |
| E3⁗ | ergonomics | MINOR | Capture-then-print hides progress on a slow mirror | Addressed: `tee` |
| E4⁗ | ergonomics | MINOR | `lib/linux_ubuntu.sh:223`'s "see apt's E:/W: lines above" is stale on apt 3.x | Out of scope: P3 backlog row |

**Assumption lines.** Goal-fit: noble's apt 2.7 prefixes `apt update` warnings `W:` (unverified;
moot with `apt-get`). Ergonomics: apt 3.x prints `Warning:`/`Error:` whatever the output target
(verified on `claude` and `workstation`). Risk: resolute boxes verify with gpgv, not sqv, whose
error text could lack `NO_PUBKEY` (`sqv` not installed on either box; sqv output untested).

### Round 6 — spec at `483bee39`

Same three lenses, fresh. Adversarial gate not triggered. Goal-fit and risk re-ran the real
`apt-get update 2>&1` (risk with all 15 of `claude`'s sources plus HashiCorp): R19's predicate
matches the rotated and never-fetched output, host and token on one line. Both boxes verify with
gpgv (`sqv` not installed).

| # | Lens | Sev | Finding | Disposition |
|---|------|-----|---------|-------------|
| K1⁵ | risk | MAJOR | "rc 100 happens only inside this step" is false: a never-fetched source with a bad key leaves `hashicorp.list` and every later `apt update` exits 100, blocking `-t update`, powershell and nvidia | Addressed: an `E:` match removes the `.list`, keeps the keyring (R20); reproduced (rc 100 twice) |
| K2⁵ | risk | MINOR | Rotation cases pass via the not-found branch; `keys/hashicorp.asc` is in both messages; clean case asserts only absence | Addressed: fixtures make the rotation check the only failure; unique substring; clean case asserts rc 0 |
| G1⁵ / K3⁵ | goal-fit, risk | MINOR | The log's temp dir does not exist; a missing or empty log reads as "no match" | Addressed: `mktemp` under `_APT_KEY_TMP_ROOT` before the source is written; empty log or grep rc ≥ 2 fails the step |
| E1⁵ | ergonomics | MINOR | The message omits `HASHICORP_GPG_FPR`, so a rotation costs two runs and a deleted source | Addressed: message names both and when each applies |
| E2⁵ | ergonomics | MINOR | Section 2 still says `apt update` prints `W:` lines | Addressed |

**Assumption lines.** Goal-fit and ergonomics: apt-get 3.2.0 puts host and `NO_PUBKEY` on one
`W:` line (verified by goal-fit and risk). Risk: expired-key output (`EXPKEYSIG`/`KEYEXPIRED`)
arrives on a `W:` line carrying the host; unverified (no `faketime`, no expired key).

### Round 7 — spec at `80f7118f`

Same three lenses, fresh. Adversarial gate not triggered.

| # | Lens | Sev | Finding | Disposition |
|---|------|-----|---------|-------------|
| G1⁶ / E1⁶ | goal-fit, ergonomics | MAJOR | R20 fires only with a signature token; an unserved codename (`does not have a Release file`) also leaves rc 100 forever | Addressed: R20 removes the `.list` on any `E:` line naming the host |
| K1⁶ / K2⁶ | risk | MAJOR | The mktemp and empty-log tests cannot pass: step 2 shares `_APT_KEY_TMP_ROOT`, and `MOCK_TEE_EXIT` also fails the `.list` write | Addressed: own `_HASHICORP_LOG_TMP_ROOT` seam; `SHIM_TEE_FAIL_ARGS` keyed on the log path |
| K3⁶ | risk | MINOR | "fetched before shows only `W:`" is false (lists deleted; `is no longer signed` and `NOSPLIT` give `E:` rc 100 on a fetched box) | Addressed: premise is "this source failed the update"; `is no longer signed` added to tokens |
| K4⁶ | risk | MINOR | Emptiness misses a truncated log or a sudo failure | Addressed: `tee` status from `PIPESTATUS[1]` |
| K5⁶ | risk | MINOR | "removed when the step returns" has no mechanism; traps are banned | Addressed: removed right after the verdicts |
| E2⁶ | ergonomics | MINOR | The removing run prints two not-found lines blaming wrong causes | Addressed: one removal line, both tools skipped |
| E3⁶ / G3⁶ | ergonomics, goal-fit | MINOR | One "no log" message covers two outcomes, and the two exits differ unexplained | Addressed: mktemp failure has its own line; the difference is stated |
| G4⁶ | goal-fit | MINOR | Dists list incomplete; `questing` still on the old key | Addressed: Measurements lists "at least" six |
| G2⁶ | goal-fit | MINOR | Rotation scaffolding out of proportion; log failure could only warn | Rejected: R20 now reads the log, so a missing log must fail closed |

**Assumption lines.** Goal-fit: apt keeps no `InRelease` for a source whose first fetch failed
(verified, wrong key and 404 codename). Ergonomics: a missing suite prints an `E:` line with the
host and exits 100 on every later update (verified by goal-fit's `zzzfake` run). Risk: an expired
vendored key on a never-fetched box gives the same `E: … is not signed` (unverified).

## Requirements

- **R1.** `_install_ubuntu_hashicorp` installs exactly packer and vagrant; no code path installs consul, vault or nomad.
- **R2.** `lib/constants.sh` defines no `CONSUL_VER`, `NOMAD_VER`, `VAULT_VER` or `HASHICORP_URL`, and defines `HASHICORP_GPG_FPR="D55C0D1AC78A8D8126CB631CFC9CA96ACA026560"`.
- **R3.** `_install_fetched_binary` has no `--unverified` mode, and no file in `lib/` contains the string `pending HashiCorp apt`.
- **R4.** `keys/hashicorp.asc` is tracked and its primary fingerprint is `HASHICORP_GPG_FPR`.
- **R5.** The keyring is built by `_build_pinned_keyring` from the vendored key with `HASHICORP_GPG_FPR`; a key whose primary fingerprint differs makes the step return 1 with no `hashicorp.list` and no keyring left behind and no `apt-get install` of packer or vagrant.
- **R6.** `hashicorp.list` holds one line: `deb [arch=<dpkg arch> signed-by=<keyring>] https://apt.releases.hashicorp.com <lsb_release -cs> main`.
- **R7.** Each tool is installed as `sudo -H DEBIAN_FRONTEND=noninteractive apt-get install -y "${APT_CONFFILE_OPTS[@]}" --allow-change-held-packages --allow-downgrades <tool>=<deb version>` followed by `sudo apt-mark hold <tool>`, where `<deb version>` is the highest version in column 2 of `apt-cache madison <tool>` (the `|`-split version field, trimmed) matching `^<VER>-`; when none matches, the tool fails with a line naming `<VER>`, the repo, a failed `apt update` and `keys/hashicorp.asc`.
- **R8.** A tool whose dpkg status is `ii`, whose upstream version is `<VER>`, and which is held is not reinstalled, and the step prints `<tool>: up to date (<deb version>, held)`.
- **R9.** On a box whose `_LINUX_ARCH` is not `amd64`, vagrant is not installed and the step prints `hashicorp: vagrant: no arm64 build; skipped`; the skip itself does not fail the step, but a failed removal of a stamped vagrant at that point does.
- **R10.** One tool's install or hold failure names that tool on stderr and returns 1, and the other tool is still attempted.
- **R11.** Subject to R12, for each of consul, vault, nomad, packer and vagrant with a stamp in `_DL_STAMP_DIR`, the step removes `_DL_BIN_DIR/<tool>` and the stamp; with no stamp, an existing `_DL_BIN_DIR/<tool>` is left in place and a warning names it.
- **R12.** A stamped packer or vagrant copy is removed only after that tool's apt install and hold succeeded, or when the tool takes the R8 up-to-date branch, or for vagrant on non-amd64 at its skip; when the install fails, the copy and its stamp remain.
- **R13.** `.config/.zshrc.d/5_general.zsh` contains no completion line for vault, consul or nomad.
- **R14.** `Brewfile` has no consul, nomad or vault entry, has `tap "hashicorp/tap", trusted: true` and `brew "hashicorp/tap/packer"` tagged `# [HAS_DEVTOOLS]`, and has no `brew "packer"` line.
- **R15.** Both macOS `brew trust` calls (`lib/macos.sh`, `lib/helpers.sh`) include `hashicorp/tap`.
- **R16.** `run_check_versions` checks packer (`hashicorp/packer`, `PACKER_VER`) and vagrant (`hashicorp/vagrant`, `VAGRANT_VER`) through `_run_cv_pinned_release`, comparing the pin, not the installed binary, with GitHub latest.
- **R17.** When `brew list --formula --full-name` contains a bare `packer`, `install_macos_casks` prints one line naming `brew uninstall packer consul vault nomad` and returns 1 without running any `brew bundle`.
- **R18.** ADR-0046 carries a dated amendment describing PR B as built, and the README backlog row "HashiCorp tools are installed without a checksum" is gone.
- **R19.** The step refreshes with `sudo -H apt-get update 2>&1 | tee` into a log created by `mktemp` under `_HASHICORP_LOG_TMP_ROOT` before the source is written; a `mktemp` failure prints a line naming the directory and returns 1 with no source written; a non-zero `tee` status, an empty log or a `grep` status of 2 or more prints `hashicorp: rotation check not run (no log)` and returns 1; the log is removed once the verdicts are computed; when that log has a `W:` or `E:` line containing `apt.releases.hashicorp.com` and one of `NO_PUBKEY`, `EXPKEYSIG`, `EXPSIG`, `KEYEXPIRED`, `REVKEYSIG`, `is not signed` or `is no longer signed`, the step prints a line containing `is not verified by keys/hashicorp.asc`, both causes (key rotated or expired, host served unsigned data) and `HASHICORP_GPG_FPR` on stderr, attempts both tools unless R20 applies, and returns 1.
- **R20.** When any log line starts `E:` and contains `apt.releases.hashicorp.com`, the step removes `hashicorp.list`, keeps the keyring, prints one line saying so, does not attempt either tool and returns 1; when no such line exists, `hashicorp.list` is left in place.
- **V1.** On `claude` and `workstation`, `./setup_env.sh -t developer` then: `command -v packer vagrant` gives `/usr/bin/packer` and `/usr/bin/vagrant`; `apt-mark showhold` lists both; none of `/usr/local/bin/{consul,vault,nomad,packer,vagrant}` exists; a second run prints the two `up to date` lines and no removal line. Hold check, on `claude` only, privileged and run by the operator: `sudo apt-get install --allow-downgrades --allow-change-held-packages packer=1.16.0-1 && sudo apt-mark hold packer`, then `./setup_env.sh -t update` reports the `apt` section OK in its summary and `dpkg-query -W packer` is still `1.16.0-1`; control: `sudo apt-mark unhold packer`, `./setup_env.sh -t update`, and `dpkg-query -W packer` is newer than `1.16.0-1`. Then `-t developer` restores the pin and hold.
- **V2.** On the Studio, after `brew uninstall packer consul vault nomad`, `brew untap hashicorp/tap` (if tapped) and `brew untrust hashicorp/tap`, and with `! grep -q hashicorp/tap ~/.homebrew/trust.json` and `HOMEBREW_NO_REQUIRE_TAP_TRUST` unset checked immediately before the run, the main `brew bundle` in `install_macos_casks` exits 0 and installs `hashicorp/tap/packer` (the gui and devtools bundles are reported separately, not asserted), and `brew list --formula --full-name` shows `hashicorp/tap/packer` with `packer --version` at or above `PACKER_VER`.
- **V3.** CI green, including `bash-coverage` at or above its floor.
- **N1.** No code uninstalls a Homebrew formula or cask.
- **N2.** No code removes a `/usr/local/bin` file that has no matching stamp in `_DL_STAMP_DIR`.
- **N3.** No vagrant is installed on a non-amd64 Linux box.
- **N4.** No new doctor check (for key expiry, signer mismatch or anything else).
- **N5.** The HashiCorp key is never fetched over the network at install time.
