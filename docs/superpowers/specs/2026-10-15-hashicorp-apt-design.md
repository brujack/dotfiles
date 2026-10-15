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
  `dists/noble/main/binary-{amd64,arm64}/Packages.gz`, 2026-10-15. The same two versions were
  found in `resolute` amd64 on 2026-10-14; `resolute` arm64 was not read.
- **Deb contents.** `packer_1.16.1-1_amd64.deb`: `/usr/bin/packer`, a licence file, a
  `conffiles` entry, no maintainer scripts; `Depends: openssl`. `vagrant_2.4.9-1_amd64.deb`:
  `/usr/bin/vagrant` and `/opt/vagrant/**`, no maintainer scripts, no `Depends`. Measured with
  `dpkg-deb -c`/`-I` on the two amd64 debs only; the arm64 packer deb was not opened.
- **Signing key.** `https://apt.releases.hashicorp.com/gpg`: rsa4096, primary fingerprint
  `D55C0D1AC78A8D8126CB631CFC9CA96ACA026560`, created 2026-09-09, expires 2031-09-08, uid
  "HashiCorp Security (HashiCorp Package Signing) <security+packaging@hashicorp.com>". Measured on
  the file as served 2026-10-14.
- **Live state.** On `claude`: all five tools in `/usr/local/bin`, no HashiCorp dpkg package, apt
  source or keyring. Measured on `claude` only; `workstation` is assumed to match because both run
  the same step, and V1 verifies it.
- **macOS.** On the Studio: core `packer` 1.9.4 installed, `vagrant` cask 2.4.9 installed, and
  `consul`, `vault`, `nomad` formulae installed. Measured on the Studio only.

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

1. **Migration** (section 3) runs first, on every path.
2. **Keyring.** `_build_pinned_keyring <vendored key> <_APT_KEYRINGS_DIR>/hashicorp-archive-keyring.gpg "${HASHICORP_GPG_FPR}"`.
   rc 1 (not the pinned key) removes the `.list` and keyring and fails the step; rc 2/3 keep the
   last verified keyring and `.list` and fail the step, mirroring `_install_ubuntu_albert`.
3. **Source.** `_write_apt_source_list` writes
   `<_APT_SOURCES_DIR>/hashicorp.list` containing
   `deb [arch=<dpkg --print-architecture> signed-by=<keyring>] https://apt.releases.hashicorp.com <lsb_release -cs> main`.
4. **Refresh.** `sudo -H apt update || :` (base owns the update warning, as in `_install_ubuntu_gui_tools`).
5. **Per tool**, packer then vagrant, each attempted regardless of the other:
   - vagrant on a box whose `_LINUX_ARCH` is not `amd64` is skipped with
     `hashicorp: vagrant: no arm64 build; skipped`, and counts as success.
   - Already done: `dpkg-query -W -f='${Version}'` prints `<VER>-1` **and** `apt-mark showhold`
     lists the tool. Skip with `<tool>: up to date (<VER>-1, held)`.
   - Otherwise:
     `sudo -H DEBIAN_FRONTEND=noninteractive apt-get install -y "${APT_CONFFILE_OPTS[@]}" --allow-change-held-packages <tool>=<VER>-1`,
     then `sudo apt-mark hold <tool>`. `--allow-change-held-packages` is what lets a pin bump
     replace a held older version.
   - A failure is named `hashicorp: <tool>: <install|hold> failed` on stderr.
6. Returns 0 when every attempted tool succeeded, else 1 (the existing step contract).

The hold means `-t update`'s apt upgrade keeps both packages back; the pin in `lib/constants.sh` is
the only thing that moves them, by the next `-t setup`/`-t developer` run.

### 3. Migration of existing boxes

Before the keyring step, for each of consul, vault, nomad, packer and vagrant:

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

The second run finds no stamps and removes nothing. Brew formulae on macOS are not removed by any
code: `brew bundle` installs and never uninstalls.

### 4. macOS, check-versions, docs

- **Brewfile.** Add `tap "hashicorp/tap"` and replace `brew "packer"` with
  `brew "hashicorp/tap/packer"`, both tagged `# [HAS_DEVTOOLS]`. `vagrant` stays a cask.
- **Tap trust.** Add `hashicorp/tap` to the two `brew trust` calls that list the macOS taps
  (`install_macos_casks` in `lib/macos.sh` and the update path in `lib/helpers.sh`). The Linux
  brew-packages call is unchanged: Linux packer comes from apt.
- **check-versions.** Add a packer entry next to vagrant in `run_check_versions`:
  `_run_cv_check "packer" "${PACKER_VER}" "hashicorp/packer" "packer --version" "[0-9]+\.[0-9]+\.[0-9]+" "PACKER_VER"`.
  It is counted in the token-gated set the CLAUDE.md `check-versions` paragraph derives its count
  from. Known window: GitHub can publish a release before the apt repo carries `<ver>-1`; a
  `--update` in that window writes a pin apt cannot install yet, and the next install fails naming
  packer. Accepted and documented rather than solved.
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

Cases:

- clean install of both tools: install line carries `=<VER>-1`, `--allow-change-held-packages` and
  `APT_CONFFILE_OPTS`, then a hold;
- already installed at `<VER>-1` and held: no install call;
- installed at an older version and held: install runs;
- arm64: vagrant skipped with its line, packer installed;
- a wrong key: rc 1, `.list` and keyring absent, no install call;
- packer install fails: rc 1, packer named, vagrant still installed and held;
- stamped `/usr/local/bin/consul`: binary and stamp removed;
- unstamped `/usr/local/bin/packer`: kept, shadow warning printed;
- second run after migration: no removal lines.

`tests/scripts/dpkg_sudo_frontend.bats` must pass over the new install line unchanged.

## Requirements

- **R1.** `_install_ubuntu_hashicorp` installs exactly packer and vagrant; no code path installs consul, vault or nomad.
- **R2.** `lib/constants.sh` defines no `CONSUL_VER`, `NOMAD_VER`, `VAULT_VER` or `HASHICORP_URL`, and defines `HASHICORP_GPG_FPR="D55C0D1AC78A8D8126CB631CFC9CA96ACA026560"`.
- **R3.** `_install_fetched_binary` has no `--unverified` mode, and no file in `lib/` contains the string `pending HashiCorp apt`.
- **R4.** `keys/hashicorp.asc` is tracked and its primary fingerprint is `HASHICORP_GPG_FPR`.
- **R5.** The keyring is built by `_build_pinned_keyring` from the vendored key with `HASHICORP_GPG_FPR`; a key whose primary fingerprint differs makes the step return 1 with no `hashicorp.list` and no keyring left behind and no `apt-get install` of packer or vagrant.
- **R6.** `hashicorp.list` holds one line: `deb [arch=<dpkg arch> signed-by=<keyring>] https://apt.releases.hashicorp.com <lsb_release -cs> main`.
- **R7.** Each tool is installed as `sudo -H DEBIAN_FRONTEND=noninteractive apt-get install -y "${APT_CONFFILE_OPTS[@]}" --allow-change-held-packages <tool>=<VER>-1` followed by `sudo apt-mark hold <tool>`.
- **R8.** A tool already at `<VER>-1` and held is not reinstalled.
- **R9.** On a box whose `_LINUX_ARCH` is not `amd64`, vagrant is not installed and the step prints `hashicorp: vagrant: no arm64 build; skipped` without failing.
- **R10.** One tool's install or hold failure names that tool on stderr and returns 1, and the other tool is still attempted.
- **R11.** For each of consul, vault, nomad, packer and vagrant with a stamp in `_DL_STAMP_DIR`, the step removes `_DL_BIN_DIR/<tool>` and the stamp; with no stamp, an existing `_DL_BIN_DIR/<tool>` is left in place and a warning names it.
- **R12.** `.config/.zshrc.d/5_general.zsh` contains no completion line for vault, consul or nomad.
- **R13.** `Brewfile` has no consul, nomad or vault entry, has `tap "hashicorp/tap"` and `brew "hashicorp/tap/packer"` tagged `# [HAS_DEVTOOLS]`, and has no `brew "packer"` line.
- **R14.** Both macOS `brew trust` calls (`lib/macos.sh`, `lib/helpers.sh`) include `hashicorp/tap`.
- **R15.** `run_check_versions` checks packer against `hashicorp/packer` with `PACKER_VER`.
- **R16.** ADR-0046 carries a dated amendment describing PR B as built, and the README backlog row "HashiCorp tools are installed without a checksum" is gone.
- **V1.** On `claude` and `workstation`, `./setup_env.sh -t developer` then: `command -v packer vagrant` gives `/usr/bin/packer` and `/usr/bin/vagrant`; `apt-mark showhold` lists both; none of `/usr/local/bin/{consul,vault,nomad,packer,vagrant}` exists; a second run prints the two `up to date` lines and no removal line.
- **V2.** On the Studio, after `brew uninstall packer consul vault nomad`, `brew bundle` installs `hashicorp/tap/packer` and `packer --version` reports `PACKER_VER`.
- **V3.** CI green, including `bash-coverage` at or above its floor.
- **N1.** No code uninstalls a Homebrew formula or cask.
- **N2.** No code removes a `/usr/local/bin` file that has no matching stamp in `_DL_STAMP_DIR`.
- **N3.** No vagrant is installed on a non-amd64 Linux box.
- **N4.** No new doctor check (for key expiry or anything else).
- **N5.** The HashiCorp key is never fetched over the network at install time.
