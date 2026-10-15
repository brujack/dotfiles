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

- **apt repo dists.** `apt.releases.hashicorp.com` serves `noble`, `resolute` and `jammy`.
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
- **apt update exit status.** A source whose keyring does not match its signer makes `apt update`
  exit 100 ("not signed"); an unreachable host exits 0 with `W:` lines only. Measured by the
  round-2 risk lens in a sandbox, on one wrong-key source and one unreachable one.
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
  deb side effects that had made apt costly.
- **apt with no pin.** Let the repo's latest flow through `-t update`. Rejected: the pin in
  `lib/constants.sh` stays the single authority for what version a box runs ("own the stack"),
  which is what the hold buys. The cost is a "kept back" line for packer and vagrant on every
  `-t update`, and a bump needs check-versions, a PR and a `-t setup`/`-t developer` run per box.

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
3. **Source.** `_write_apt_source_list` writes
   `<_APT_SOURCES_DIR>/hashicorp.list` containing
   `deb [arch=<dpkg --print-architecture> signed-by=<keyring>] https://apt.releases.hashicorp.com <lsb_release -cs> main`.
4. **Refresh.** `sudo -H apt update || :` (base owns the update warning, as in `_install_ubuntu_gui_tools`).
   A failed refresh leaves madison reading the previous lists, which the not-found line names.
5. **Per tool**, packer then vagrant, each attempted regardless of the other:
   - vagrant on a box whose `_LINUX_ARCH` is not `amd64` is skipped with
     `hashicorp: vagrant: no arm64 build; skipped`, and counts as success.
   - **Resolve the deb version.** The candidate is the highest version `apt-cache madison <tool>`
     lists whose upstream part is exactly `<VER>` (matches `^<VER>-`). None found: fail the tool
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
6. Returns 0 when every attempted tool succeeded, else 1 (the existing step contract).

The hold means `-t update`'s apt upgrade keeps both packages back; the pin in `lib/constants.sh` is
the only thing that moves them, by the next `-t setup`/`-t developer` run.

**Key rotation stops OS updates.** `update_apt_packages` (`lib/linux_shared.sh`) runs
`apt update || return 1` before `nala full-upgrade`. Once HashiCorp signs with a key other than
the vendored one, `apt update` exits 100 and `-t update` upgrades no package at all, security
updates included, on every box, until a PR vendors the new key. The key was created 2026-09-09, so
the last rotation is recent. The edge, albert and docker sources carry the same exposure today;
this PR adds a fourth source to it and does not fix the class. Accepted here; the fleet-wide fix
is a P1 backlog row in `docs/superpowers/README.md`.

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
- **Core-packer guard.** On a mac that still has homebrew-core `packer`, `brew bundle` is expected
  to fail on the tap formula, and `install_macos_casks`'s `|| return 1` would then skip
  `Brewfile.gui` and `Brewfile.devtools`. Before the main bundle, `install_macos_casks` checks
  `brew list --formula --full-name` for a bare `packer` line and, when present, prints a warning
  naming `brew uninstall packer` as the one-time fix. It removes nothing (N1). Expected, not
  measured: the Studio is migrated by the uninstall first, so the conflict is never observed there.
- **Tap trust.** Homebrew requires tap trust by default (unless `HOMEBREW_NO_REQUIRE_TAP_TRUST`
  is set), and `install_macos_casks` runs `brew trust` *after* `brew bundle`. A new tap listed only
  in that call is untrusted on the first bundle, the bundle fails, and `|| return 1` skips
  `Brewfile.gui` and `Brewfile.devtools`. So the Brewfile's own `trusted: true` (supported by
  `brew bundle`'s tap entry) is what trusts the tap on first contact. `hashicorp/tap` is also added
  to the two `brew trust` calls that list the macOS taps (`install_macos_casks` in `lib/macos.sh`
  and the update path in `lib/helpers.sh`), so the list stays complete. Unmeasured: whether
  `trusted: true` works on a tap not yet tapped; V2 starts from that state. The Linux
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
  manual steps (`brew uninstall packer consul vault nomad` on each mac before the next bundle;
  unstamped `/usr/local/bin` leftovers by hand).

### 5. Testing

bats in `tests/setup_env/linux_ubuntu.bats`, against existing seams: `_APT_SOURCES_DIR`,
`_APT_KEYRINGS_DIR`, `_APT_KEY_TMP_ROOT`, `_MS_GPG_BIN` (real gpg, so the fingerprint pin is
genuinely exercised), `_DL_STAMP_DIR`, `_DL_BIN_DIR`, and the sudo/apt mocks. A new
`_HASHICORP_KEY_PATH` seam is honoured only when `BATS_TEST_TMPDIR` is non-empty, so a test can feed
a wrong key without touching the vendored one.

Two mock seams do not exist and are added: a new `tests/mocks/apt-cache` whose `madison <pkg>`
prints `MOCK_APT_MADISON_<pkg>` (absent means no versions), and `showhold` support in
`tests/mocks/apt-mark` printing `MOCK_APT_MARK_HOLD`. Without the first, `madison` would read the
host's real apt state.

Cases:

- clean install of both tools: install line carries `packer=1.16.1-1`, `--allow-change-held-packages`,
  `--allow-downgrades` and `APT_CONFFILE_OPTS`, then `apt-mark hold packer`;
- madison lists `1.16.1-2` and `1.16.1-1`: install line carries `packer=1.16.1-2`;
- madison lists no `1.16.1-`: rc 1 and the "not in apt.releases.hashicorp.com" line;
- installed `ii 1.16.1-1` and held: the line `packer: up to date (1.16.1-1, held)` and no install call;
- installed `rc 1.16.1-1` and held: install runs;
- installed at an older version and held: install runs;
- arm64: vagrant skip line, stamped vagrant removed, packer installed;
- a wrong key, with a `hashicorp.list` and keyring pre-seeded: rc 1, both removed, no install call;
- packer install fails: rc 1, packer named, stamped `/usr/local/bin/packer` and its stamp still
  present, vagrant still installed, held and its stamped copy removed;
- stamped `/usr/local/bin/consul`: binary and stamp removed, removal line printed;
- unstamped `/usr/local/bin/packer`: kept, shadow warning printed;
- second run after migration: both `up to date (…, held)` lines and no removal line;
- installed `ii 1.16.1-1`, held, and a stamped `/usr/local/bin/packer` still present: the
  `up to date` line, no install call, and the copy and stamp removed;
- mac: a bare `packer` in `brew list --formula --full-name` prints the uninstall warning; `hashicorp/tap/packer` alone prints nothing;
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
| K4' | risk | MAJOR | Round-1 K4 is wrong: a rotated key makes `apt update` exit 100 and `update_apt_packages` returns before upgrading anything | Accepted (operator, option c): section 2 states it; fleet-wide fix is a P1 backlog row |
| K2' | risk | MINOR | `apt-cache` mock and `apt-mark showhold` support do not exist; wrong-key case cannot show removal without pre-seeded files | Addressed: section 5 names both mocks and the pre-seed |
| G2' / E2' | goal-fit, ergonomics | MINOR | A removal that fails after a good install is never retried; the next run skips as up to date while `/usr/local/bin` shadows `/usr/bin` | Addressed: removal also runs on the already-done branch (R11, R12); new bats case |
| K3' | risk | MINOR | R11 "always removes" contradicts R12 "keeps on install failure" | Addressed: R11 is subject to R12 |
| E3' | ergonomics | MINOR | The not-found line blames release or key when `apt update` failed | Addressed: the line names a failed `apt update` too |

Not raised by a lens and kept: the tap formula declares `conflicts_with "packer"`, so R17's warning
partly repeats brew's own error; it is cheap and fires before the bundle.

**Assumption lines.** All three lenses named the same one: nala 0.16.0 `full-upgrade` keeps a held
package at its version when a newer candidate exists, and exits 0. Unmeasured; V1 as rewritten
settles it. G1' adds a second: `trusted: true` in a Brewfile works on a tap not yet tapped.
Unmeasured; V2 settles it.

## Requirements

- **R1.** `_install_ubuntu_hashicorp` installs exactly packer and vagrant; no code path installs consul, vault or nomad.
- **R2.** `lib/constants.sh` defines no `CONSUL_VER`, `NOMAD_VER`, `VAULT_VER` or `HASHICORP_URL`, and defines `HASHICORP_GPG_FPR="D55C0D1AC78A8D8126CB631CFC9CA96ACA026560"`.
- **R3.** `_install_fetched_binary` has no `--unverified` mode, and no file in `lib/` contains the string `pending HashiCorp apt`.
- **R4.** `keys/hashicorp.asc` is tracked and its primary fingerprint is `HASHICORP_GPG_FPR`.
- **R5.** The keyring is built by `_build_pinned_keyring` from the vendored key with `HASHICORP_GPG_FPR`; a key whose primary fingerprint differs makes the step return 1 with no `hashicorp.list` and no keyring left behind and no `apt-get install` of packer or vagrant.
- **R6.** `hashicorp.list` holds one line: `deb [arch=<dpkg arch> signed-by=<keyring>] https://apt.releases.hashicorp.com <lsb_release -cs> main`.
- **R7.** Each tool is installed as `sudo -H DEBIAN_FRONTEND=noninteractive apt-get install -y "${APT_CONFFILE_OPTS[@]}" --allow-change-held-packages --allow-downgrades <tool>=<deb version>` followed by `sudo apt-mark hold <tool>`, where `<deb version>` is the highest `apt-cache madison` version matching `^<VER>-`; when none matches, the tool fails with a line naming `<VER>`, the repo, a failed `apt update` and `keys/hashicorp.asc`.
- **R8.** A tool whose dpkg status is `ii`, whose upstream version is `<VER>`, and which is held is not reinstalled, and the step prints `<tool>: up to date (<deb version>, held)`.
- **R9.** On a box whose `_LINUX_ARCH` is not `amd64`, vagrant is not installed and the step prints `hashicorp: vagrant: no arm64 build; skipped` without failing.
- **R10.** One tool's install or hold failure names that tool on stderr and returns 1, and the other tool is still attempted.
- **R11.** Subject to R12, for each of consul, vault, nomad, packer and vagrant with a stamp in `_DL_STAMP_DIR`, the step removes `_DL_BIN_DIR/<tool>` and the stamp; with no stamp, an existing `_DL_BIN_DIR/<tool>` is left in place and a warning names it.
- **R12.** A stamped packer or vagrant copy is removed only after that tool's apt install and hold succeeded, or when the tool takes the R8 up-to-date branch, or for vagrant on non-amd64 at its skip; when the install fails, the copy and its stamp remain.
- **R13.** `.config/.zshrc.d/5_general.zsh` contains no completion line for vault, consul or nomad.
- **R14.** `Brewfile` has no consul, nomad or vault entry, has `tap "hashicorp/tap", trusted: true` and `brew "hashicorp/tap/packer"` tagged `# [HAS_DEVTOOLS]`, and has no `brew "packer"` line.
- **R15.** Both macOS `brew trust` calls (`lib/macos.sh`, `lib/helpers.sh`) include `hashicorp/tap`.
- **R16.** `run_check_versions` checks packer (`hashicorp/packer`, `PACKER_VER`) and vagrant (`hashicorp/vagrant`, `VAGRANT_VER`) through `_run_cv_pinned_release`, comparing the pin, not the installed binary, with GitHub latest.
- **R17.** `install_macos_casks` prints a warning naming `brew uninstall packer` before the main `brew bundle` when `brew list --formula --full-name` contains a bare `packer`, and continues.
- **R18.** ADR-0046 carries a dated amendment describing PR B as built, and the README backlog row "HashiCorp tools are installed without a checksum" is gone.
- **V1.** On `claude` and `workstation`, `./setup_env.sh -t developer` then: `command -v packer vagrant` gives `/usr/bin/packer` and `/usr/bin/vagrant`; `apt-mark showhold` lists both; none of `/usr/local/bin/{consul,vault,nomad,packer,vagrant}` exists; a second run prints the two `up to date` lines and no removal line. Hold check, on `claude` only, privileged and run by the operator: `sudo apt-get install --allow-downgrades --allow-change-held-packages packer=1.16.0-1 && sudo apt-mark hold packer`, then `./setup_env.sh -t update` exits 0 and `dpkg-query -W packer` is still `1.16.0-1`; control: `sudo apt-mark unhold packer`, `./setup_env.sh -t update`, and `dpkg-query -W packer` is `1.16.1-1`. Then `-t developer` restores the pin and hold.
- **V2.** On the Studio, after `brew uninstall packer consul vault nomad` and `brew untap hashicorp/tap` (if tapped), with `hashicorp/tap` absent from `~/.homebrew/trust.json` and `HOMEBREW_NO_REQUIRE_TAP_TRUST` unset, `install_macos_casks` completes all three bundles and installs `hashicorp/tap/packer`, and `brew list --formula --full-name` shows `hashicorp/tap/packer` with `packer --version` at or above `PACKER_VER`.
- **V3.** CI green, including `bash-coverage` at or above its floor.
- **N1.** No code uninstalls a Homebrew formula or cask.
- **N2.** No code removes a `/usr/local/bin` file that has no matching stamp in `_DL_STAMP_DIR`.
- **N3.** No vagrant is installed on a non-amd64 Linux box.
- **N4.** No new doctor check (for key expiry, signer mismatch or anything else).
- **N5.** The HashiCorp key is never fetched over the network at install time.
