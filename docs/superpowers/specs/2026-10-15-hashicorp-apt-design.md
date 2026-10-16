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
- **apt update exit status.** Depends on whether the source was ever fetched. Never fetched, wrong
  key: rc 100, `E: The repository '…' is not signed.` Fetched once with the right key, then the
  `signed-by=` keyring swapped for another key: rc 0, three warnings ending
  `NO_PUBKEY FC9CA96ACA026560` ("the previous index files will be used"), and `apt-cache madison
packer` still lists `1.16.1-1`. An unreachable host: rc 0, warnings only. The first case was
  measured by the round-2 risk lens; the fetched case by the round-4 ergonomics lens and again by
  the orchestrator, unprivileged with every `Dir::` path in a sandbox, on `claude` (apt 3.x) and
  `workstation` (apt 3.2.0), both resolute. noble's apt 2.7 is unmeasured. Round 2 measured only
  the never-fetched case and generalised it (K4').
- **Single-source refresh.** `apt-get update -o Dir::Etc::sourcelist=<one .list> -o
  Dir::Etc::sourceparts=- -o APT::Get::List-Cleanup=0` refreshes only that source and its rc is
  that source's: fetched then rotated rc 0, never fetched with a wrong key rc 100, unserved
  codename rc 100, clean rc 0 (round-8 goal-fit lens). Without `List-Cleanup=0` the same call
  deleted every other source's lists: a Microsoft source's 3 list files went to 0, and stayed at 3
  with the flag (orchestrator, sandbox on `claude`). On a fetched source, a mirror sync in progress
  and a publisher clock ahead of the box each give an `E:` line naming the host and rc 100
  (round-8 risk lens, local signed repo). An empty codename gives
  `E: Malformed entry 1 in list file … (Component)`, rc 100. A held apt lock (`apt-daily`) gives
  `E: Could not get lock /var/lib/apt/lists/lock…`, rc 100, at once (round-9 ergonomics lens).
  Against a sandbox copy of `claude`'s 15 sources, the single-source refresh shrank `pkgcache.bin`
  from 60 MB to 3.7 MB, the next madison rebuilt it, madison still listed `packer 1.16.1-1`,
  `apt-get -s install packer=1.16.1-1` resolved `openssl` from Ubuntu, and no other source's lists
  were lost (round-9 risk lens). All on apt 3.2.0; noble's apt 2.7 unmeasured.
- **Lists of a removed source.** A full `apt-get update` with the default `APT::Get::List-Cleanup`
  deletes the list files of every source not in the configured set. Measured three times on
  apt 3.2.0: the round-8 Microsoft test (3 files to 0), the round-10 goal-fit lens (two pre-seeded
  `apt.releases.hashicorp.com_*` files to 0 under an empty source list) and the round-10
  ergonomics lens (two local repos, 2 files to 0; kept with `List-Cleanup=0`). The cleanup is
  skipped when any source in that update fails: with two `apt.releases.hashicorp.com_*` files
  pre-seeded and only an unreachable source configured, the update gave rc 0 and both files
  stayed (round-11 risk lens). Over such stale lists, a refresh with a swapped keyring and
  `--error-on=any` gave rc 100 with `W: … NO_PUBKEY FC9CA96ACA026560` and
  `E: Failed to fetch https://apt.releases.hashicorp.com/… NO_PUBKEY …`, and no `is not signed`
  (round-11 risk and goal-fit lenses).
- **Ubuntu sources location.** On `claude`, `/etc/apt/sources.list` has no active line
  (`grep -vc '^\s*\(#\|$\)'` gives 0); the Ubuntu sources are in
  `/etc/apt/sources.list.d/ubuntu.sources`. A simulated install using only the HashiCorp source
  and the real dpkg status resolved `Inst packer (1.16.1-1 …)` and `Inst vagrant (2.4.9-1 …)`,
  rc 0 (round-11 goal-fit lens, sandbox). `workstation` has the same layout (round-12 risk lens,
  over ssh). With the full default sourceparts and `-o Dir::Etc::sourcelist=<file>` after the
  verb, a simulated install resolved both tools; without the `-o`,
  `E: Unable to locate package packer` (round-12 risk lens).
- **Two lines for one repo.** A `sources.list.d` entry and the step's file for the same
  repo and suite with different `signed-by=` files: `E: Conflicting values set for option
  Signed-By regarding source https://apt.releases.hashicorp.com/ resolute: … != …` and
  `E: The list of sources could not be read.`, rc 100. With no `signed-by` on one of them: only
  `W: Target … configured multiple times`, rc 0. Round-12 risk lens, sandbox, apt 3.2.0.
- **Who reads what.** strace of a sandboxed single-source update: the source file is opened only
  by the main `apt-get` process (root in production); the keyring is opened by the
  `methods/gpgv` child, the privilege-dropped one. Round-12 risk lens.
- **Fetch failures under `--error-on=any`.** A never-fetched source on an unresolvable host gives
  rc 0 and only `W: Failed to fetch … Could not resolve` and `W: Some index files failed to
  download` by default; with `--error-on=any`, rc 100 and the same lines as `E:`. Round-10 risk
  lens, sandbox, apt 3.2.0. noble's apt 2.7 carries the option per its changelog; unmeasured.
- **Version glob.** `apt-get -s install 'vagrant=2.4.9-*'` selects `2.4.9-1`;
  `'vagrant=2.2.10-*'` selects `2.2.10-4`; `'vagrant=9.9.9-*'` gives
  `E: Version '9.9.9-*' for 'vagrant' was not found`. Round-10 goal-fit lens, sandbox, apt 3.2.0.
- **apt lock type.** apt takes `lists/lock` with `fcntl`. A `flock(1)` holder does not block it
  (rc 0); an `fcntl.lockf` holder does (rc 100, `E: Could not get lock …`). Round-10 risk lens,
  sandbox without `Debug::NoLocking`.
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
  keep `/usr/local/bin` and need no apt source or migration. Rejected by the operator on 2026-10-15
  in favour of the apt repo, which ADR-0046 and the backlog row had already named as PR B's plan:
  apt verifies index and package with one key through a mechanism every other third-party source
  on these boxes already uses, and removing the three server tools removed the deb side effects
  that had made apt costly. Cost the apt route carries that the zips do not: when HashiCorp's
  signer changes, installs fail until a new key is vendored (section 2, "Key rotation").
- **Persistent apt source with holds.** Keep `hashicorp.list` installed between runs and
  `apt-mark hold` both packages so `-t update` cannot move them past the pin. This was the design
  through round 9. Superseded by the operator on 2026-10-16 after round 9: from round 4 on, every
  addition (the never-fetched source removal and its `_APT_LISTS_DIR` seam, the holds and the V1
  hold check, the openssl caveat, the kept-back line) existed only because the `.list` persisted,
  and each round found a new gap in that set (round 9: a held apt lock removed a good `.list`; a
  codename HashiCorp stops serving kept rc 100 forever). The persistent source bought nothing
  between runs: the holds froze the version, and each setup run rewrote the `.list`. This
  reverses the operator's round-3 rejection of the transient source, which rested on a rotation
  stopping OS updates; round 4 showed that false.
- **apt with no pin.** Let the repo's latest flow in. Rejected: the pin in `lib/constants.sh` stays
  the single authority for what version a box runs ("own the stack"). With the transient source
  this costs nothing extra: `-t update` has no HashiCorp source, so it offers no newer candidate.

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

### 2. Linux: packer and vagrant from a transient apt source

New constant `HASHICORP_GPG_FPR="D55C0D1AC78A8D8126CB631CFC9CA96ACA026560"` and a vendored key
`keys/hashicorp.asc` (the file as served at `https://apt.releases.hashicorp.com/gpg`). The key path
defaults to `${DOTFILES_REPO_ROOT}/keys/hashicorp.asc`, resolved at source time in
`lib/constants.sh` as a plain assignment, the same rule as `_AWS_KEY_PATH`; no network fetch of the
key happens at install time.

The source is visible to apt only in this step's own two commands, which name it with
`-o Dir::Etc::sourcelist=`. `-t update` and every other apt user never see it, so no hold is needed: with no HashiCorp source, nala has no newer candidate for packer or
vagrant. `_install_ubuntu_hashicorp` then:

1. **Migration of the removed tools** (section 3) runs first, on every path.
2. **Decide what to install, without apt.** For each tool, packer then vagrant:
   - vagrant on a box whose `_LINUX_ARCH` is not `amd64` is skipped with
     `hashicorp: vagrant: no arm64 build; skipped`. The skip itself counts as success; a failed
     removal of a stamped vagrant at that point (section 3) still fails the step. The skip and its
     removal run whatever later steps do: they need no apt. `_LINUX_ARCH` (from `uname -m`,
     `lib/constants.sh`) decides the skip; `dpkg --print-architecture` decides the source line's
     `arch=`. They are two strings for one fact on a real box, and tests set both.
   - **Already done:** `dpkg-query -W -f='${db:Status-Abbrev} ${Version}' <tool> 2>/dev/null`
     prints `ii ` and a version whose upstream part is `<VER>` (matches `^<VER>-`). Print
     `<tool>: up to date (<installed deb version>)`, then run the stamp-gated removal (section 3):
     a run whose removal failed after a good install takes this branch next time, and the stale
     `/usr/local/bin` copy would otherwise shadow `/usr/bin/<tool>` forever. A package in `rc`
     state (removed, conffiles left) is not done. stderr is discarded because real dpkg-query
     prints `dpkg-query: no packages found matching <tool>` and exits 1 for a package that is not
     installed; that is the normal first-install state, not an error, and rc 1 means "not done".
   - Otherwise the tool joins the install set.
3. **Nothing to install.** When the install set is empty, steps 4 to 7 do not run: no keyring
   build, no source file, no network. A second run on a migrated box therefore touches no apt
   state.
4. **Keyring.** `_build_pinned_keyring <vendored key> <_APT_KEYRINGS_DIR>/hashicorp-archive-keyring.gpg "${HASHICORP_GPG_FPR}"`,
   with `_APT_KEYRINGS_DIR` defaulting to `/usr/share/keyrings`. That is the path HashiCorp's own
   install instructions use, so a hand-written `/etc/apt/sources.list.d` entry that follows them
   names the same `signed-by=` file as this step's source line. Two lines for one repo with
   different `signed-by=` files make apt refuse the whole source list
   (`E: Conflicting values set for option Signed-By …`, rc 100; Measurements); with the same file
   apt only warns that the target is configured twice (expected, not measured).
   Sharing that path means the step overwrites a keyring the operator placed there by hand,
   always with the fingerprint-pinned key, and that rc 1 below deletes it. rc 1 means the vendored
   key in this repo is not the pinned one, a repo defect R4's test catches before merge; accepted.
   rc 1 (not the pinned key) removes the keyring and fails the step; rc 2/3 keep the last verified
   keyring and fail the step, mirroring `_install_ubuntu_albert`. Either way nothing is installed.
   The keyring persists between runs; with no source referencing it, apt never reads it.
5. **Source file, outside apt's configured set.** The source line goes in
   `<_HASHICORP_SOURCE_DIR>/hashicorp.list` (new seam, default `/var/lib/dotfiles`, honoured only
   when `BATS_TEST_TMPDIR` is non-empty, like `_HASHICORP_KEY_PATH`: root apt trusts what that
   file says, and a line can carry `[trusted=yes]`, so production never takes its location from
   the environment), never in
   `/etc/apt/sources.list` or `/etc/apt/sources.list.d`. apt reads it only when a command names it
   with `-o Dir::Etc::sourcelist=`, which only steps 6 and 7 do. So no other apt run (base,
   `k8s_tools`, `-t update`'s nala, `apt-daily`, an `apt` typed by hand) can ever fetch it or
   upgrade from it, and the file needs no removal: a stale copy is inert, and every install run
   rewrites it in full before the refresh. If `dpkg --print-architecture` or
   `lsb_release -cs` prints nothing, the step prints
   `hashicorp: cannot determine <arch|codename>; source not written` and returns 1: an empty field
   makes a malformed line (`E: Malformed entry 1 in list file … (Component)`, rc 100). Otherwise
   the step runs `sudo install -d -m 0755 <_HASHICORP_SOURCE_DIR>` and writes, through
   `sudo tee`, the one line
   `deb [arch=<dpkg --print-architecture> signed-by=<keyring>] https://apt.releases.hashicorp.com <lsb_release -cs> main`.
   If either fails, any partial file is removed and the step returns 1. The root apt process
   reads the source file; only the keyring is read by apt's unprivileged `_apt` child (`gpgv`),
   and `_build_pinned_keyring` already installs it 0644 (Measurements).
6. **Refresh this source only.** The step first prints
   `hashicorp: refreshing apt.releases.hashicorp.com`, since the call below is silent until it
   returns (an unreachable host took 38 s in a sandbox). Then
   ```
   local _out _rc
   _out=$(sudo -H apt-get update --error-on=any \
          -o Dir::Etc::sourcelist=<_HASHICORP_SOURCE_DIR>/hashicorp.list \
          -o Dir::Etc::sourceparts=- -o APT::Get::List-Cleanup=0 2>&1)
   _rc=$?
   ```
   Only this source is fetched, so `_rc` is this source's verdict. `APT::Get::List-Cleanup=0` is
   load-bearing: without it a single-source update deletes every other source's lists.
   `--error-on=any` is load-bearing too: without it an unreachable host, a 5xx or a proxy failure
   exits 0 with only `W:` lines, and the step would go on to report a missing version instead of
   a failed fetch (Measurements). `apt-get`, not `apt`: its CLI is stable and its diagnostics are
   prefixed `W:`/`E:`. `2>&1` because the diagnostics are on stderr. `_out` is printed after the
   call; one ~2 MB index needs no live progress.
   Usually the refresh is a first fetch: the full `apt update`s that run earlier in
   `install_ubuntu_packages` (base, and `k8s_tools` immediately before this step) do not name this
   source, so the default `List-Cleanup` deletes its lists. apt skips that cleanup whenever any
   source in the full update fails, so this source's lists from the previous install run can
   survive (Measurements). Both cases behave the same under `--error-on=any`: a rotated or expired
   key exits 100.
   - **Refresh failed** (`_rc` non-zero): print
     `hashicorp: apt-get update failed for apt.releases.hashicorp.com (rc <N>): <first E: line of _out, else its last line>; <install set> not installed (installed copies, if any, untouched)`,
     followed by exactly one next action:
     - when the rotation hint below fires: `; see the next line`;
     - when that line contains `does not have a Release file`: `; the repo does not serve
       <codename> yet, or returned 404: wait for HashiCorp to publish it, then re-run
       ./setup_env.sh -t developer` (apt's text is the same for both causes);
     - otherwise: `; re-run ./setup_env.sh -t developer`.
     No tool in the install set is attempted, and the step will return 1. Every cause lands here:
     a held apt lock, a sudo failure, an unreachable or failing host, a wrong or rotated key, a
     mirror sync in progress, an unserved codename.
   - **Rotation hint**: when any `W:` or `E:` line of `_out` contains `apt.releases.hashicorp.com`
     and one of `NO_PUBKEY`, `EXPKEYSIG`, `EXPSIG`, `KEYEXPIRED`, `REVKEYSIG`, `is not signed` or
     `is no longer signed`, the step also prints
     `hashicorp: apt.releases.hashicorp.com is not verified by keys/hashicorp.asc (key rotated or
     expired, or the host served unsigned data); re-vendor keys/hashicorp.asc from
     https://apt.releases.hashicorp.com/gpg after verifying it out of band, and if its primary
     fingerprint changed also edit HASHICORP_GPG_FPR in lib/constants.sh` on stderr, and the step
     will return 1. An expiry extension keeps the fingerprint, so only the file changes; a rotation
     changes both, and re-vendoring the file alone would trip step 4's rc 1 on the next run.
7. **Install each tool in the install set**, each attempted regardless of the other:
   - The step prints `hashicorp: installing <tool> <VER>` and runs
     `sudo -H DEBIAN_FRONTEND=noninteractive apt-get install -y "${APT_CONFFILE_OPTS[@]}" -o Dir::Etc::sourcelist=<_HASHICORP_SOURCE_DIR>/hashicorp.list --allow-downgrades "<tool>=<VER>-*"`.
     The `-o` replaces `/etc/apt/sources.list` with this file for one command and keeps the
     default `sourceparts`, so `sources.list.d` (where `ubuntu.sources` lives on resolute and
     noble) stays in scope. A box whose Ubuntu sources are still in `/etc/apt/sources.list` loses
     them for this command only; packer's one dependency, `openssl`, is installed on every box
     (`ubuntu_common_packages.txt`, and `ca-certificates` depends on it), so the install still
     resolves. apt resolves the version glob to the highest matching revision, so a `-2` or `-4`
     revision needs no parsing here (Measurements). `--allow-downgrades` lets a pin rollback
     install an older version.
   - stdout streams to the terminal (packer is 34 MB and vagrant 90 MB); only stderr is captured:
     `{ _err=$(sudo -H … 2>&1 1>&3 3>&-); _irc=$?; } 3>&1`, then `_err` is printed to stderr.
   - A failed install prints `hashicorp: <tool>: install failed`, followed by
     `(<VER> not in apt.releases.hashicorp.com yet; check-versions can pin a release before apt
     publishes it, so wait and re-run ./setup_env.sh -t developer)` when `_err` contains
     `Version '<VER>-*' for '<tool>' was not found`; by
     `(apt.releases.hashicorp.com lists no <tool> for <arch>, or its lists were deleted between
     refresh and install, e.g. by apt-daily; re-run ./setup_env.sh -t developer)` when `_err`
     contains `Unable to locate package <tool>`; and by
     `(another source for apt.releases.hashicorp.com in /etc/apt/sources.list.d names a different
     signed-by keyring; point it at <keyring> or remove it)` when `_err` contains
     `Conflicting values set for option Signed-By`.
   - **Then** remove the tool's stamped `/usr/local/bin` copy (section 3), only after its apt
     install succeeded. A failed removal prints `hashicorp: <tool>: remove failed`.
8. **The source file stays.** No step removes `<_HASHICORP_SOURCE_DIR>/hashicorp.list`: nothing
   reads it except steps 6 and 7, and step 5 overwrites it on every install run. Removing it
   would only add a failure mode (a failed `sudo rm` failing a good install) and test obligations.
9. Returns 0 when every tool succeeded or was up to date and no rotation hint printed, else 1 (the
   existing step contract).

A pin bump moves a box at its next `-t setup`/`-t developer` run; `-t update` never does, because
no source apt is configured with carries packer or vagrant.

**Costs of the per-run source.** `apt-cache policy packer` shows only `/var/lib/dpkg/status`
between runs, so the installed version's origin is not visible there. No install run can count on
old lists (step 6): when the refresh fails, the install waits for a run where it succeeds. Nothing
reports a Linux box that sits below a bumped pin (N4 forbids a doctor check); the check-versions
`--update` line names the run that moves it (section 4). The step owns three paths: `/var/lib/dotfiles/hashicorp.list`, the
`/var/lib/dotfiles` directory it creates, and `/usr/share/keyrings/hashicorp-archive-keyring.gpg`.

**Key rotation.** A rotation or expiry of HashiCorp's signer is seen only by a run that has
something to install: a pin bump or a new box. On a first fetch the refresh exits 100 with
`E: … is not signed` (preceded by a `W: … NO_PUBKEY` line); over stale lists it exits 100 with
`E: Failed to fetch https://apt.releases.hashicorp.com/… NO_PUBKEY …` and no `is not signed`
(Measurements). Either way the step prints the refresh-failed line and the rotation hint,
installs nothing and returns 1. Nothing outside this step is affected: no
other apt run sees the source. The vendored key expires 2031-09-08. The fleet-wide P2 backlog row
on stale third-party keys no longer counts this source.

### 3. Migration of existing boxes

consul, vault and nomad are handled before step 2. packer and vagrant are handled per tool, after
that tool's apt install succeeded or on its already-done branch, so a failed apt install (repo
down, version not yet published, wrong key, lock) never leaves a box with neither the old binary
nor the new one. For each tool, at its point:

- If `${_DL_STAMP_DIR}/<tool>` exists, dotfiles installed `${_DL_BIN_DIR}/<tool>`: remove the
  binary (`sudo rm -f`) and the stamp (`rm -f`), and log
  `hashicorp: removed <path> (installed by dotfiles)`.
- If there is no stamp but `${_DL_BIN_DIR}/<tool>` exists, it is not ours: leave it and warn. For
  packer and vagrant the warning says it shadows `/usr/bin/<tool>` on PATH and names the remove
  command.
- A failed removal is named and fails the step; the install still runs.
- What the removal destroys on a stamped path: whatever file is there now. A stamp proves dotfiles
  wrote that path; it does not prove the operator has not since replaced the file. That case is
  accepted: replacing a dotfiles-managed binary by hand without deleting its stamp is outside any
  workflow this repo supports.
- On an arm64 box vagrant is never apt-installed (section 2), so a stamped arm64 vagrant (the
  broken amd64 binary) is removed at its skip instead. The skip needs no apt, so it runs whatever
  the refresh does.

The second run finds no stamps and removes nothing. A run interrupted between install and removal
leaves a stamp; the next run takes the already-done branch and removes it there. Brew formulae on
macOS are not removed by any code: `brew bundle` installs and never uninstalls.

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
  the whole `-t setup`/`-t developer` run aborts: gui and devtools bundles, cargo tools, vim
  plugins, pyenv, the ansible venv and ruby. `run_brew_install` (`--brew-install`) also calls
  `install_macos_casks` and exits non-zero the same way. The guard does not shrink that abort; it
  makes it clear and leaves nothing half-run. A warning before a bundle that still runs would
  scroll away under its output. So, before the main bundle, `install_macos_casks` checks
  `brew list --formula --full-name` for a bare `packer` line and, when present, prints one line,
  `homebrew-core packer conflicts with hashicorp/tap/packer: run 'brew uninstall packer consul
  vault nomad', then re-run`, and returns 1 without running the bundle. It removes nothing (N1).
  `-t update` never calls `install_macos_casks`; there the first signal is the brew-drift WARN
  (untracked `packer consul nomad vault`, missing `hashicorp/tap/packer` and its tap), and the
  CLAUDE.md manual step is the remedy. The bundle failure itself is expected, not measured: the
  Studio is migrated by the uninstall first, so the conflict is never observed there.
- **Tap trust.** Homebrew requires tap trust by default (unless `HOMEBREW_NO_REQUIRE_TAP_TRUST`
  is set), and `install_macos_casks` runs `brew trust` _after_ `brew bundle`. A new tap listed only
  in that call is untrusted on the first bundle, the bundle fails, and `|| return 1` skips
  `Brewfile.gui` and `Brewfile.devtools`. So the Brewfile's own `trusted: true` (supported by
  `brew bundle`'s tap entry) is what trusts the tap on first contact. `hashicorp/tap` is also added
  to the two `brew trust` calls that list the macOS taps (`install_macos_casks` in `lib/macos.sh`
  and the update path in `lib/helpers.sh`), so the list stays complete. Homebrew 7.0.9's
  `bundle/installer.rb:81` applies `trusted: true` before anything loads the entries (read by the
  round-3 lenses on the Studio); whether that holds on a tap not yet tapped is unmeasured, and V2
  starts from that state. The Linux brew-packages call is unchanged: Linux packer comes from apt.
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
  apt.releases.hashicorp.com yet" hint. Accepted and documented rather than solved. `--update`
  for either tool goes through a new `packer|vagrant)` arm of `_prompt_version_update`, not
  `_update_release_pin` (whose refresher, `scripts/refresh-sha256-pins.sh`, accepts only kind, yq
  and shellcheck) and not the fallthrough `_update_version_pin` (whose `sed` exits 0 when it
  matches nothing). The arm refuses a latest that is not `X.Y.Z` (as `_update_release_pin` does),
  since a two-part pin such as `1.16` would match no apt version and every box would report it
  as not yet published. It then edits only the `*_VER` line of `_release_pin_constants_path`, reads it
  back with `grep -Fqx`, returns 1 with a read-back failure line when the line is not there, and
  otherwise prints the usual `Updated <VAR> → <version>` line, then `<tool>: commit lib/constants.sh and merge the PR, then run ./setup_env.sh -t
  developer on each Linux box to install <version>` followed by `  if it reports <version> not in
  apt.releases.hashicorp.com yet, wait for HashiCorp to publish it and re-run`.
- **ADR-0046** gets a dated amendment: PR B moved packer and vagrant to HashiCorp's signed apt
  repo through a source file outside `/etc/apt` that only the install step's own commands read,
  and consul, vault and nomad were
  removed, not moved.
- **`docs/superpowers/README.md`**: remove the backlog row "HashiCorp tools are installed without a
  checksum"; reword "check-versions covers under half the pins" to drop the HashiCorp tools.
- **CLAUDE.md**: the release-asset-pins bullet no longer mentions `--unverified`; add the one-time
  manual steps (`brew uninstall packer consul vault nomad` on each mac before the first
  `-t setup`, `-t developer` or `--brew-install` after this merges; unstamped `/usr/local/bin`
  leftovers by hand). The `check-versions` entry-point paragraph adds packer to its token-gated
  list and says packer and vagrant compare their pin, not the installed binary, with GitHub
  latest, and that `--update` for them writes only `*_VER`, reads it back and prints the
  next-step line. Test Seams gains `_HASHICORP_KEY_PATH`, `_HASHICORP_SOURCE_DIR` (both
  `BATS_TEST_TMPDIR`-gated, both defaulted by `load_mocks`) and the `MOCK_APT_GET_SOURCELIST_COPY`,
  `MOCK_APT_GET_UPDATE_OUTPUT`, `MOCK_APT_GET_INSTALL_OUTPUT` and `MOCK_LSB_RELEASE_CS` knobs.

### 5. Testing

bats in `tests/setup_env/linux_ubuntu.bats`, against existing seams: `_APT_KEYRINGS_DIR`,
`_APT_KEY_TMP_ROOT`, `_MS_GPG_BIN` (real gpg, so the fingerprint pin is genuinely exercised),
`_DL_STAMP_DIR`, `_DL_BIN_DIR`, and the sudo/apt mocks. Two new seams:

- `_HASHICORP_KEY_PATH`, honoured only when `BATS_TEST_TMPDIR` is non-empty, so a test can feed a
  wrong key without touching the vendored one;
- `_HASHICORP_SOURCE_DIR` (default `/var/lib/dotfiles`), also honoured only when
  `BATS_TEST_TMPDIR` is non-empty.

`load_mocks` (`tests/helpers/common.bash`) exports `_HASHICORP_SOURCE_DIR` and `_APT_KEYRINGS_DIR`
to directories under `BATS_TEST_TMPDIR` by default. `tests/mocks/sudo` execs the real `install`
and `tee`, and `tests/setup_env/workflows.bats` runs the real `install_ubuntu_packages` in four
tests that set neither seam (tdd.md E2). Today those tests stop at step 4 only because the gpg
mock emits nothing; the default makes the isolation deliberate.

`linux_ubuntu.bats` also runs on the `test-macos` runner, where `uname -m` is `arm64`, so
`_LINUX_ARCH` is `arm64` there. Every case that expects vagrant to install, the dispatcher test
included, sets `_LINUX_ARCH=amd64` and `MOCK_DPKG_PRINT_ARCH=amd64` explicitly, before any env
helper runs (the dispatcher's `_k8s_env` derives `KIND_URL_EXPECTED` from `_LINUX_ARCH`); the
arm64 cases set `_LINUX_ARCH=arm64`. No case inherits `_LINUX_ARCH`.

Command-line assertions on the install use `argv_probe_stub_path` and `grep -xF` over the
bracketed argv, the pattern the existing conffile-argv tests use: the mock call log strips the
`-o Dpkg::Options::=…` pairs, and a regex `packer=1.16.1-*` reads `-*` as "zero or more dashes", so
it would pass an implementation that dropped the glob.

Mock seams that do not exist and are added:

- `update` in `tests/mocks/apt-get`, in this order, so a case can combine them:
  1. when `MOCK_APT_GET_SOURCELIST_COPY` is set, copy the file named by the
     `-o Dir::Etc::sourcelist=` argument there, so a test can read the source file the step
     removes before returning;
  2. when `MOCK_APT_GET_UPDATE_OUTPUT` names a file, print its `W:`/`E:` lines to stderr and its
     other lines to stdout (an implementation that captures stdout only goes red); unset, print
     `Reading package lists...` to stdout;
  3. only then apply the existing `MOCK_APT_FAIL_SUBCMD=update` exit 100. Today the mock's fail
     loop exits before printing anything, so without this order the never-fetched case cannot see
     its fixture.
- `install` in the same mock: when `MOCK_APT_GET_INSTALL_OUTPUT` names a file, print it (`E:` lines
  to stderr, the rest to stdout) before the existing fail handling, so the version-not-found case
  can show apt's line and a stdout-capturing implementation goes red.
- fixtures, each captured with the sandbox recipe below and the step's own single-source
  `apt-get update --error-on=any … 2>&1` (a capture with `apt` holds `Warning:` lines and tests a
  different program; a capture over the full source set holds other hosts' lines):
  - `tests/fixtures/apt/update-hashicorp-never-fetched.txt`: no lists, keyring built from a key
    that is not HashiCorp's (`W: … NO_PUBKEY` then `E: … is not signed`);
  - `update-hashicorp-stale-rotated.txt`: one clean fetch with the right key, then the keyring
    swapped for another key and the refresh run again over the surviving lists
    (`E: Failed to fetch https://apt.releases.hashicorp.com/… NO_PUBKEY …`, no `is not signed`).
    This is the only fixture whose sole rotation token is `NO_PUBKEY`, so dropping that token from
    the hint list goes red;
  - `update-hashicorp-no-release.txt`: a codename the repo does not serve;
  - `update-hashicorp-lock.txt`: `E: Could not get lock …`, captured without
    `Debug::NoLocking=1` and with the sandbox's `lists/lock` held by an fcntl lock (`python3 -c`
    with `fcntl.lockf`): apt locks with `fcntl`, and an `flock(1)` holder does not conflict with
    it;
  - `tests/fixtures/apt/install-version-not-found.txt`, captured with
    `apt-get -s install 'vagrant=9.9.9-*'` in the sandbox.
- Sandbox recipe: run `apt-get` unprivileged with `-o Dir::State`, `Dir::State::Lists`,
  `Dir::Cache`, `Dir::Etc::sourcelist`, `Dir::Etc::sourceparts`, `Dir::Etc::Parts`,
  `Dir::Etc::TrustedParts`, `Dir::Log` pointed into a scratch dir, `Debug::NoLocking=1` (except
  for the lock fixture) and `APT::Sandbox::User=$(id -un)`, with a one-line source file signed by
  the dearmored vendored key, or by another key where a fixture above says so.
- a flag-aware `tests/mocks/lsb_release`: `-cs` prints `${MOCK_LSB_RELEASE_CS-noble}` (unset gives
  `noble`, set-but-empty gives empty, so the empty-codename case is reachable), `-rs` keeps
  `MOCK_LSB_RELEASE_RS`. Today the mock prints `MOCK_LSB_RELEASE_RS` for any arguments, so a `-rs`
  in place of `-cs` passes the suite and writes `26.04` into the source line. The default keeps
  the cloudflared `.list` (the one other `-cs` caller) from rendering an empty codename.

Existing mocks that differ from the real tool, so the cases below set them to the real shape:
`tests/mocks/dpkg` prints `--print-architecture` only when `MOCK_DPKG_PRINT_ARCH` is set;
`tests/mocks/dpkg-query` prints `MOCK_DPKG_STATUS_<pkg>` verbatim, where real
`dpkg-query -W -f='${db:Status-Abbrev} ${Version}'` prints two spaces after the status
(`ii  1.16.1-1`) and exits 1 for a package that is not installed; a not-installed case sets
`MOCK_DPKG_QUERY_EXIT=1` when both tools are absent, and leaves the absent tool's variable unset
(empty output, which the step reads as not done) when only one is.

Cases:

- clean install of both tools, `MOCK_DPKG_QUERY_EXIT=1`: the argv probe shows `install`, `-y`,
  the `APT_CONFFILE_OPTS` tokens, `-o`, `Dir::Etc::sourcelist=<source dir>/hashicorp.list`,
  `--allow-downgrades` and the literal `packer=1.16.1-*` (likewise `vagrant=2.4.9-*`); no
  `apt-mark` call is recorded; with `MOCK_APT_GET_UPDATE_OUTPUT` and `MOCK_APT_GET_INSTALL_OUTPUT`
  set to files holding a marker stdout line, `$output` has `hashicorp: refreshing` before the
  refresh marker and `hashicorp: installing packer 1.16.1` before the install marker;
- source line, with `MOCK_LSB_RELEASE_CS=resolute`, `MOCK_LSB_RELEASE_RS=26.04` and
  `MOCK_DPKG_PRINT_ARCH=armhf`: the copy the apt-get mock saved during the refresh equals
  `deb [arch=armhf signed-by=<keyring path>] https://apt.releases.hashicorp.com resolute main`, and
  nothing was written under `_APT_SOURCES_DIR`;
- every case below has installs that succeed unless it says otherwise, so the branch named is the
  only possible failure; rotation assertions use the substring
  `is not verified by keys/hashicorp.asc`:
  - never-fetched fixture, `MOCK_APT_FAIL_SUBCMD=update`: rotation hint, the refresh-failed line
    ending `; see the next line` and not containing `re-run`, step rc 1, keyring present, no
    install call;
  - stale-rotated fixture, `MOCK_APT_FAIL_SUBCMD=update`: the same, which pins `NO_PUBKEY` in the
    token list;
  - no-release fixture, `MOCK_APT_FAIL_SUBCMD=update`, `MOCK_LSB_RELEASE_CS=resolute`: no rotation
    hint, the refresh-failed line with `does not serve resolute yet: wait for HashiCorp to publish
    it`;
  - lock fixture, `MOCK_APT_FAIL_SUBCMD=update`: the refresh-failed line naming
    `Could not get lock` and ending `; re-run ./setup_env.sh -t developer`, no rotation hint, no
    install call;
  - unset fixture, rc 0: no rotation hint or refresh-failed line, step rc 0;
- install-version-not-found fixture with `MOCK_APT_FAIL_SUBCMD=install` and `VAGRANT_VER=9.9.9`
  exported (the step reads the pin by indirect expansion and `lib/constants.sh` assigns it
  plainly, so the export reaches it): rc 1, `hashicorp: vagrant: install failed` and the
  `not in apt.releases.hashicorp.com yet` hint;
- install output, under `run --separate-stderr`: with `MOCK_APT_GET_INSTALL_OUTPUT` holding a
  stdout line and an `E:` line, the stdout line is in `$output` and the `E:` line in `$stderr`.
  This catches the likely wrong copy of step 6 (both streams into one variable, which would put
  the `E:` line on stdout); it cannot tell streaming from capture-then-print, and does not try;
- install stderr `Unable to locate package vagrant`: the `lists no vagrant for <arch>` hint;
  `Conflicting values set for option Signed-By`: the hint naming `/etc/apt/sources.list.d`;
- stale source file: `<source dir>/hashicorp.list` pre-seeded with a `noble` line,
  `MOCK_LSB_RELEASE_CS=resolute`: the copy the apt-get mock saved during the refresh is the
  `resolute` line;
- `sudo install -d` fails (`SHIM_DIR` `install` failing on the source dir): rc 1, no source file,
  no `apt-get update` call; `tee` fails (`SHIM_TEE_FAIL_ARGS` on the source path): rc 1, no
  source file, no `apt-get update` call;
- both tools installed `ii  1.16.1-1` / `ii  2.4.9-1`: the two `up to date` lines, no `apt-get
  update` or `apt-get install` call, no keyring built, no `hashicorp: refreshing` line, and no
  source file ever written (a `SHIM_DIR` `tee` records every path it writes);
- arm64 with a stamped vagrant and the never-fetched fixture: the vagrant skip line, the stamped
  vagrant and its stamp removed, packer not installed;
- `MOCK_LSB_RELEASE_CS=""`: the `cannot determine codename` line, rc 1, no source file, no
  `apt-get update` call; the same with `MOCK_DPKG_PRINT_ARCH` set to empty;
- the refresh argv (argv probe) carries `--error-on=any`,
  `-o Dir::Etc::sourcelist=<source dir>/hashicorp.list`, `-o Dir::Etc::sourceparts=-` and
  `-o APT::Get::List-Cleanup=0`;
- the step's refresh is recorded in the mock call log as `apt-get update` (sudo, `-H`), and no
  `apt update` call is recorded by this step, so the refresh command and the fixtures' capture
  command cannot drift apart;
- installed `ii  1.16.1-1`: the line `packer: up to date (1.16.1-1)` and no install call;
- installed `rc  1.16.1-1`: install runs;
- installed at an older version: install runs;
- arm64: vagrant skip line, stamped vagrant removed, packer installed;
- arm64 with the vagrant removal failing: rc 1 and the removal named;
- a wrong key, with a keyring pre-seeded: rc 1, keyring removed, no source file, no install call;
- packer install fails: rc 1, packer named, stamped `/usr/local/bin/packer` and its stamp still
  present, vagrant still installed and its stamped copy removed;
- stamped `/usr/local/bin/consul`: binary and stamp removed, removal line printed;
- unstamped `/usr/local/bin/packer`: kept, shadow warning printed;
- second run after migration: both `up to date` lines and no removal line;
- installed `ii  1.16.1-1` and a stamped `/usr/local/bin/packer` still present: the `up to date`
  line, no install call, and the copy and stamp removed;
- mac: a bare `packer` in `brew list --formula --full-name` prints the line naming
  `brew uninstall packer consul vault nomad`, returns 1, and runs no `brew bundle`;
  `hashicorp/tap/packer` alone prints nothing and the bundle runs;
- check-versions: `PACKER_VER` behind the mocked GitHub latest reports outdated while the
  installed `packer --version` equals latest; `--update` for packer, with
  `_OVERRIDE_CONSTANTS_PATH` on a copy, writes the new `PACKER_VER`, reads it back, and prints the
  next-step line naming `./setup_env.sh -t developer`; a copy with no `PACKER_VER` line prints a
  read-back failure, no next-step line, and returns 1.

**The dispatcher test changes too.**
`tests/setup_env/linux_ubuntu.bats`'s "install_ubuntu_packages: a clean run reaches every step,
and a second run re-fetches nothing" today asserts a `releases.hashicorp.com` wget and an
`up to date (stamp` line for all five HashiCorp tools, through `_hc_env` and the
`*releases.hashicorp.com*` arm of its wget shim. Under this design it goes red (with no
`MOCK_DPKG_PRINT_ARCH`, step 5 refuses to write the source). It must keep running the real
hashicorp step, never a stub: it sets `_LINUX_ARCH=amd64` and `MOCK_DPKG_PRINT_ARCH=amd64` before
`_k8s_env` and the other env helpers, sets `MOCK_DPKG_QUERY_EXIT=1` on the first run and `ii`
statuses on the second, and points `_HASHICORP_KEY_PATH` at the vendored key. Its first run asserts
`apt-get install` calls carrying `packer=1.16.1-*` and `vagrant=2.4.9-*`; its second asserts both
`up to date (` lines and no `apt-get update` call carrying
`Dir::Etc::sourcelist=<source dir>/hashicorp.list` (other steps, `cloud_tools` and opentofu, issue
their own `apt-get update` on every run, so an unfiltered "no update" assertion cannot pass).
`_hc_env` and the `releases.hashicorp.com` shim arm are deleted.

`tests/scripts/dpkg_sudo_frontend.bats` must pass over the new install line unchanged (verb
`install` before the `-o`, `APT_CONFFILE_OPTS` quoted after the verb).

## Multi-Lens Review

### Round 1 — spec at `0ae607c9`

Three general-purpose lenses (goal-fit, ergonomics, risk), no conversation context. Adversarial
gate not triggered: no comparison design, no judge, concrete acceptance criteria. Every lens
re-verified the premise (stamps on `claude` and `workstation`, the four apt indexes, the key
fingerprint) and found it true. No R-vs-N contradiction found.

| #            | Lens                 | Sev   | Finding                                                                                  | Disposition                                                                                         |
| ------------ | -------------------- | ----- | ---------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| G1           | goal-fit             | MAJOR | Signed-`SHA256SUMS` zip verification is never weighed against apt                        | Addressed: Alternatives section records it and the operator's choice                                |
| G2 / E5      | goal-fit, ergonomics | MINOR | `<VER>-1` is hardcoded; the index carries `-2`/`-4` revisions                            | Addressed: version resolved from `apt-cache madison` matching `^<VER>-` (R7)                        |
| G3           | goal-fit             | MINOR | `dpkg-query ${Version}` reads an `rc` package as installed                               | Addressed: skip requires `ii` (R8)                                                                  |
| G4 / E7 / K5 | all three            | MINOR | "held: no install call" and "second run: no removal lines" pass on a no-op               | Addressed: both assert the `up to date (…, held)` lines                                             |
| E1           | ergonomics           | MAJOR | check-versions compares the installed binary, so a mac tracking latest hides a stale pin | Addressed: packer and vagrant move to `_run_cv_pinned_release` (R16)                                |
| E2           | ergonomics           | MAJOR | V2's `packer --version == PACKER_VER` fails once the tap moves past the pin              | Addressed: macOS packer declared unpinned; V2 asserts at-or-above                                   |
| E3           | ergonomics           | MAJOR | Core packer left on a mac makes `brew bundle` fail and skips the gui/devtools bundles    | Addressed: pre-bundle warning naming the uninstall (R17); conflict expected, not measured           |
| E4           | ergonomics           | MINOR | The hold's cost (kept-back line, per-box bump) is not named                              | Addressed: Alternatives, "apt with no pin"                                                          |
| E6           | ergonomics           | MINOR | The release-before-apt window applies to vagrant too                                     | Addressed: section 4 names both tools                                                               |
| E8           | ergonomics           | MINOR | `[HAS_DEVTOOLS]` reads as gating install; it gates drift only                            | Addressed: section 4 states every mac gets the tap                                                  |
| K1           | risk                 | MAJOR | Migration deletes packer/vagrant before apt has a replacement                            | Addressed: removal after that tool's install and hold succeed (R12)                                 |
| K2           | risk                 | MINOR | A pin rollback aborts without `--allow-downgrades`                                       | Addressed: flag added (R7)                                                                          |
| K3           | risk                 | MINOR | `--allow-change-held-packages` is transaction-wide (openssl hold)                        | Addressed: accepted and stated in section 2                                                         |
| K4           | risk                 | MINOR | A key rotation fails silently until a bump, then names packer                            | Addressed: the not-found line names the key file [round 2 K4': wrong — rotation blocks `-t update`] |

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

| #         | Lens                 | Sev   | Finding                                                                                                                                                                                              | Disposition                                                                            |
| --------- | -------------------- | ----- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| E1' / K1' | ergonomics, risk     | MAJOR | V1's `-t update` check cannot fail: the pins are already the repo's newest versions, so nala has no candidate held or not                                                                            | Addressed: V1 holds `packer=1.16.0-1` with an unheld control                           |
| G1'       | goal-fit             | MAJOR | `brew trust` runs after `brew bundle`; with trust required by default the new tap is untrusted on first bundle, which fails and skips the gui/devtools bundles                                       | Addressed: `trusted: true` on the Brewfile tap; V2 starts untapped and untrusted       |
| K4'       | risk                 | MAJOR | Round-1 K4 is wrong: a rotated key makes `apt update` exit 100 and `update_apt_packages` returns before upgrading anything [round 4 E1''': wrong for any box that fetched the source — rc 0, silent] | Accepted (operator, option c): section 2 states it; fleet-wide fix is a P1 backlog row |
| K2'       | risk                 | MINOR | `apt-cache` mock and `apt-mark showhold` support do not exist; wrong-key case cannot show removal without pre-seeded files                                                                           | Addressed: section 5 names both mocks and the pre-seed                                 |
| G2' / E2' | goal-fit, ergonomics | MINOR | A removal that fails after a good install is never retried; the next run skips as up to date while `/usr/local/bin` shadows `/usr/bin`                                                               | Addressed: removal also runs on the already-done branch (R11, R12); new bats case      |
| K3'       | risk                 | MINOR | R11 "always removes" contradicts R12 "keeps on install failure"                                                                                                                                      | Addressed: R11 is subject to R12                                                       |
| E3'       | ergonomics           | MINOR | The not-found line blames release or key when `apt update` failed                                                                                                                                    | Addressed: the line names a failed `apt update` too                                    |

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

| #                  | Lens       | Sev   | Finding                                                                                                                     | Disposition                                                                     |
| ------------------ | ---------- | ----- | --------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| G1''               | goal-fit   | MAJOR | A transient apt source removes the holds, the nala assumption and this source's share of K4'                                | Rejected (operator): recorded under Alternatives with the rotation history      |
| E1''               | ergonomics | MAJOR | R17 warns of a certain bundle failure and runs into it; the failure aborts the whole setup/developer run                    | Addressed: R17 returns 1 before the bundle; section 4 states the blast radius   |
| K1''               | risk       | MINOR | The madison mock invites a hand-typed fixture that hides a raw-line parser matching nothing on a box                        | Addressed: captured fixtures; R7 matches column 2                               |
| K2''               | risk       | MINOR | The `lsb_release` mock ignores flags, so a `-rs` for `-cs` passes the suite                                                 | Addressed: flag-aware mock; R6 test sets distinct values                        |
| G2'' / K3'' / E2'' | all three  | MINOR | Rotation class is every persistent third-party source (12 on `claude`), expiry is a second trigger, and no stopgap is given | Addressed: section 2 and the P1 row widened; stopgap in section 2 and CLAUDE.md |
| K4''               | risk       | MINOR | R9 says the arm64 skip never fails; section 3 fails the step on a failed removal                                            | Addressed: removal failure counts (R9)                                          |
| K5''               | risk       | MINOR | V2 passes vacuously once any earlier run trusted the tap                                                                    | Addressed: V2 untrusts first and checks `trust.json`                            |
| E3''               | ergonomics | MINOR | V1 asserts `-t update`'s whole exit code, which any unrelated section FAIL turns red                                        | Addressed: V1 asserts the `apt` summary row                                     |
| K6''               | risk       | MINOR | V1's control expects exactly `1.16.1-1`; a newer release fails it falsely                                                   | Addressed: control asserts newer than `1.16.0-1`                                |
| G3''               | goal-fit   | MINOR | The zips alternative omits the rotation cost apt carries                                                                    | Addressed: cost stated in Alternatives                                          |

**Assumption lines.** Goal-fit and risk: nala 0.16.0 `full-upgrade` keeps a held package back when
a newer candidate exists (unmeasured; V1). Risk also: HashiCorp signs `InRelease` with the pinned
primary key (verified with `gpgv`). Ergonomics: `brew bundle` exits non-zero when a formula
conflicts with an installed one (unmeasured; R17 holds either way).

### Round 4 — spec at `2743cb6d`

Same three lenses, fresh. Adversarial gate not triggered. Goal-fit and risk found no MAJOR; every
round-3 change was re-verified against the code.

| #             | Lens           | Sev   | Finding                                                                                                                                                                                      | Disposition                                                                                                                                                                                    |
| ------------- | -------------- | ----- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| E1'''         | ergonomics     | MAJOR | K4' is false for a box that fetched the source: a rotated key leaves `apt update` at rc 0 with `W:` lines and old lists, so OS updates continue and the HashiCorp source goes stale silently | Addressed: reproduced by the orchestrator on `claude` and `workstation`; section 2 rewritten, stopgap dropped, backlog row demoted P1 to P2 (operator), step-4 rotation check added (operator) |
| E2'''         | ergonomics     | MINOR | R17's guard does not shrink the abort, its line names only `packer`, and `-t update`'s first signal is unstated                                                                              | Addressed: section 4 says so; R17's line names all four formulae and "re-run"                                                                                                                  |
| G1'''         | goal-fit       | MINOR | The stopgap lasts only until the next setup run                                                                                                                                              | Moot: stopgap dropped with E1'''                                                                                                                                                               |
| G2''' / K3''' | goal-fit, risk | MINOR | No capture route for the madison fixtures is named (goal-fit thought none existed)                                                                                                           | Addressed: the unprivileged sandbox recipe is in section 5                                                                                                                                     |
| K1'''         | risk           | MINOR | The R6 test never sets `MOCK_DPKG_PRINT_ARCH`, so `arch=` is unchecked                                                                                                                       | Addressed: whole-line assertion with `armhf`                                                                                                                                                   |
| K2'''         | risk           | MINOR | The dpkg-query mock prints one space and exits 0 for an absent package; real output has two spaces and rc 1                                                                                  | Addressed: fixtures use the real shape; clean install sets `MOCK_DPKG_QUERY_EXIT=1`                                                                                                            |
| K4'''         | risk           | MINOR | Section 4 omits `run_brew_install` as an R17 caller                                                                                                                                          | Addressed                                                                                                                                                                                      |
| K5'''         | risk           | MINOR | V2 asserts all three bundles, so an unrelated cask failure turns it red                                                                                                                      | Addressed: V2 asserts the main bundle and the tap formula                                                                                                                                      |

**Assumption lines.** Goal-fit: nala keeps a held package back (unmeasured; V1). Ergonomics: apt
keeps old lists and exits 0 on a fetched source's signer change (verified on two resolute boxes;
noble unmeasured). Risk: `trusted: true` trusts an untapped tap on first bundle (unmeasured; V2).

### Round 5 — spec at `4301333e`

Same three lenses, fresh. Adversarial gate not triggered. All three found the same MAJOR, created
by the round-4 fix.

| #               | Lens                 | Sev   | Finding                                                                                                                                                                        | Disposition                                                                                                                                                                                          |
| --------------- | -------------------- | ----- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| G1⁗ / E1⁗ / K1⁗ | all three            | MAJOR | R19 matches `^W:`/`^E:`, but the step runs `apt update`, which on apt 3.x prints `Warning:`/`Error:`; fixtures captured with `apt-get` would pass while production never fires | Addressed: refresh is `apt-get update 2>&1 \| tee`; fixtures captured with the same command; a test pins the refresh command; reproduced by the orchestrator (`grep -c '^W:'` = 0, three `Warning:`) |
| G2⁗ / E1⁗       | goal-fit, ergonomics | MINOR | The captured stream is unstated; diagnostics are on stderr, so a stdout capture is inert, and the mock cannot tell                                                             | Addressed: `2>&1` stated; the mock prints `W:`/`E:` lines to stderr                                                                                                                                  |
| G3⁗             | goal-fit             | MINOR | `is not signed` also follows unsigned data from a proxy; the message names only rotation                                                                                       | Addressed: message names both causes                                                                                                                                                                 |
| E2⁗             | ergonomics           | MINOR | "Loud" overstates it: one summary entry, `-t developer` exits 0                                                                                                                | Addressed: section 2 states exactly what is shown                                                                                                                                                    |
| E3⁗             | ergonomics           | MINOR | Capture-then-print hides progress on a slow mirror                                                                                                                             | Addressed: `tee`                                                                                                                                                                                     |
| E4⁗             | ergonomics           | MINOR | `lib/linux_ubuntu.sh:223`'s "see apt's E:/W: lines above" is stale on apt 3.x                                                                                                  | Out of scope: P3 backlog row                                                                                                                                                                         |

**Assumption lines.** Goal-fit: noble's apt 2.7 prefixes `apt update` warnings `W:` (unverified;
moot with `apt-get`). Ergonomics: apt 3.x prints `Warning:`/`Error:` whatever the output target
(verified on `claude` and `workstation`). Risk: resolute boxes verify with gpgv, not sqv, whose
error text could lack `NO_PUBKEY` (`sqv` not installed on either box; sqv output untested).

### Round 6 — spec at `483bee39`

Same three lenses, fresh. Adversarial gate not triggered. Goal-fit and risk re-ran the real
`apt-get update 2>&1` (risk with all 15 of `claude`'s sources plus HashiCorp): R19's predicate
matches the rotated and never-fetched output, host and token on one line. Both boxes verify with
gpgv (`sqv` not installed).

| #         | Lens           | Sev   | Finding                                                                                                                                                                                            | Disposition                                                                                                         |
| --------- | -------------- | ----- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| K1⁵       | risk           | MAJOR | "rc 100 happens only inside this step" is false: a never-fetched source with a bad key leaves `hashicorp.list` and every later `apt update` exits 100, blocking `-t update`, powershell and nvidia | Addressed: an `E:` match removes the `.list`, keeps the keyring (R20); reproduced (rc 100 twice)                    |
| K2⁵       | risk           | MINOR | Rotation cases pass via the not-found branch; `keys/hashicorp.asc` is in both messages; clean case asserts only absence                                                                            | Addressed: fixtures make the rotation check the only failure; unique substring; clean case asserts rc 0             |
| G1⁵ / K3⁵ | goal-fit, risk | MINOR | The log's temp dir does not exist; a missing or empty log reads as "no match"                                                                                                                      | Addressed: `mktemp` under `_APT_KEY_TMP_ROOT` before the source is written; empty log or grep rc ≥ 2 fails the step |
| E1⁵       | ergonomics     | MINOR | The message omits `HASHICORP_GPG_FPR`, so a rotation costs two runs and a deleted source                                                                                                           | Addressed: message names both and when each applies                                                                 |
| E2⁵       | ergonomics     | MINOR | Section 2 still says `apt update` prints `W:` lines                                                                                                                                                | Addressed                                                                                                           |

**Assumption lines.** Goal-fit and ergonomics: apt-get 3.2.0 puts host and `NO_PUBKEY` on one
`W:` line (verified by goal-fit and risk). Risk: expired-key output (`EXPKEYSIG`/`KEYEXPIRED`)
arrives on a `W:` line carrying the host; unverified (no `faketime`, no expired key).

### Round 7 — spec at `80f7118f`

Same three lenses, fresh. Adversarial gate not triggered.

| #         | Lens                 | Sev   | Finding                                                                                                                          | Disposition                                                                                  |
| --------- | -------------------- | ----- | -------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| G1⁶ / E1⁶ | goal-fit, ergonomics | MAJOR | R20 fires only with a signature token; an unserved codename (`does not have a Release file`) also leaves rc 100 forever          | Addressed: R20 removes the `.list` on any `E:` line naming the host                          |
| K1⁶ / K2⁶ | risk                 | MAJOR | The mktemp and empty-log tests cannot pass: step 2 shares `_APT_KEY_TMP_ROOT`, and `MOCK_TEE_EXIT` also fails the `.list` write  | Addressed: own `_HASHICORP_LOG_TMP_ROOT` seam; `SHIM_TEE_FAIL_ARGS` keyed on the log path    |
| K3⁶       | risk                 | MINOR | "fetched before shows only `W:`" is false (lists deleted; `is no longer signed` and `NOSPLIT` give `E:` rc 100 on a fetched box) | Addressed: premise is "this source failed the update"; `is no longer signed` added to tokens |
| K4⁶       | risk                 | MINOR | Emptiness misses a truncated log or a sudo failure                                                                               | Addressed: `tee` status from `PIPESTATUS[1]`                                                 |
| K5⁶       | risk                 | MINOR | "removed when the step returns" has no mechanism; traps are banned                                                               | Addressed: removed right after the verdicts                                                  |
| E2⁶       | ergonomics           | MINOR | The removing run prints two not-found lines blaming wrong causes                                                                 | Addressed: one removal line, both tools skipped                                              |
| E3⁶ / G3⁶ | ergonomics, goal-fit | MINOR | One "no log" message covers two outcomes, and the two exits differ unexplained                                                   | Addressed: mktemp failure has its own line; the difference is stated                         |
| G4⁶       | goal-fit             | MINOR | Dists list incomplete; `questing` still on the old key                                                                           | Addressed: Measurements lists "at least" six                                                 |
| G2⁶       | goal-fit             | MINOR | Rotation scaffolding out of proportion; log failure could only warn                                                              | Rejected: R20 now reads the log, so a missing log must fail closed                           |

**Assumption lines.** Goal-fit: apt keeps no `InRelease` for a source whose first fetch failed
(verified, wrong key and 404 codename). Ergonomics: a missing suite prints an `E:` line with the
host and exits 100 on every later update (verified by goal-fit's `zzzfake` run). Risk: an expired
vendored key on a never-fetched box gives the same `E: … is not signed` (unverified).

### Round 8 — spec at `c051b9d6`

Same three lenses, fresh. Adversarial gate not triggered. Every finding traced to the round-7 log
machinery; the operator adopted the single-source refresh, which removes it.

| #   | Lens       | Sev   | Finding                                                                                                                                          | Disposition                                                                                   |
| --- | ---------- | ----- | ------------------------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------- |
| G1⁷ | goal-fit   | MAJOR | With no log R20 leaves the `.list`, recreating the rc-100 lock; a single-source refresh gives a per-source rc and needs no log                   | Addressed: step 4 rewritten; `List-Cleanup=0` reproduced as load-bearing                      |
| K1⁷ | risk       | MAJOR | The apt-get mock prints nothing, so every case without a fixture hits "no log"; the tee-failure case cannot pin `PIPESTATUS`; `\|\| :` clears it | Moot: no log, `tee` or `PIPESTATUS` remain; mock prints `Reading package lists...` by default |
| K2⁷ | risk       | MAJOR | `E:` on a fetched, healthy source (mirror sync, `not valid yet`) would remove the `.list`                                                        | Addressed: removal needs rc ≠ 0 **and** no `InRelease` (R20)                                  |
| K3⁷ | risk       | MINOR | An empty codename or arch writes a malformed `.list` no rule removes                                                                             | Addressed: refuse empty fields; remove a partial write                                        |
| G2⁷ | goal-fit   | MINOR | R9 and R20 disagree on arm64 stamped vagrant                                                                                                     | Addressed: the skip and its removal run regardless                                            |
| E1⁷ | ergonomics | MINOR | "not installed" is false on a box with held debs                                                                                                 | Addressed: "not checked (installed copies, if any, untouched)"                                |
| E2⁷ | ergonomics | MINOR | An unserved codename loops every run with no remedy                                                                                              | Addressed: hint appended                                                                      |
| K4⁷ | risk       | MINOR | K4⁶ claimed `tee` status catches a sudo failure; it does not                                                                                     | Moot with the log gone                                                                        |

**Assumption lines.** Goal-fit and risk: noble's apt 2.7 behaves the same for single-source rc and
transient `E:` lines (unverified; the fleet is resolute). Ergonomics: an `E:` line for this source
carries the host on its first line (verified for `is not signed` and `does not have a Release
file`).

### Round 9 — spec at `d18f9e91`

Same three lenses, fresh. Adversarial gate not triggered. No lens found a defect in the step-4
single-source mechanism itself; risk re-ran it against a sandbox copy of `claude`'s 15 sources
(Measurements). The operator adopted the transient source, which removes R20, the holds and the
`_APT_LISTS_DIR` seam, and with them findings 2 and 3. Every reference in rounds 1 to 8 (R8's
"held" clause, R12's hold, R20, V1's hold check, `_APT_LISTS_DIR`, `apt-mark showhold`) is frozen
at the round that wrote it.

| #   | Lens       | Sev   | Finding                                                                                                                                                       | Disposition                                                                                                       |
| --- | ---------- | ----- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| G1⁸ | goal-fit   | MAJOR | The round-3 rejection of a transient source rested on "a persistent source costs little"; everything since round 4 exists only because the `.list` persists | Addressed (operator, 2026-10-16): section 2 rewritten as a transient source; holds, R20 and `_APT_LISTS_DIR` gone |
| E1⁸ | ergonomics | MINOR | R20 deletes a good `.list` on a box-local failure (held apt lock, sudo failure) with no `InRelease`                                                          | Moot: the `.list` is always removed; the lock is a refresh-failed case with its own fixture                       |
| K1⁸ | risk       | MINOR | A codename HashiCorp stops serving after a box fetched it keeps rc 100 forever, since `InRelease` stays                                                      | Moot: the `.list` never outlives the step                                                                         |
| K2⁸ | risk       | MINOR | §5 omits the dispatcher test that asserts a `releases.hashicorp.com` wget for all five tools; it goes red                                                    | Addressed: section 5 names it, its settings and replacement assertions, and forbids stubbing the step            |

Not raised: the `lsb_release` default must be `${MOCK_LSB_RELEASE_CS-noble}`, not `:-`, or the
empty-codename case is unreachable (risk, checked clean); now stated in section 5.

**Assumption lines.** Goal-fit: a transient source loses nothing the persistent one gave between
runs (argued, not measured). Ergonomics: `brew uninstall` of a set with one missing formula still
removes the rest (verified on the Studio). Risk: noble's apt 2.7 behaves the same for the
single-source refresh (unverified; the fleet is resolute).

### Round 10 — spec at `c3b66d66`

Same three lenses, fresh. Adversarial gate not triggered. No MAJOR. Risk re-verified the core
assumption in a two-source sandbox: after the single-source refresh, madison and a simulated
install under the full source set see packer and vagrant, and the other source keeps its lists.

| #    | Lens                        | Sev   | Finding                                                                                                                                         | Disposition                                                                                                                     |
| ---- | --------------------------- | ----- | ----------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| K1⁹  | risk                        | MINOR | The suite runs on `test-macos` (arm64); `_LINUX_ARCH` is unset in the amd64 cases, so vagrant is skipped there and the dispatcher and clean-install cases go red | Addressed: every case sets `_LINUX_ARCH` and `MOCK_DPKG_PRINT_ARCH`; section 2 names the two sources of one fact               |
| K2⁹  | risk                        | MINOR | An unreachable host, 5xx or proxy failure exits 0 with `W:` lines, so the step blames an unpublished release or a rotated key                   | Addressed: refresh with `--error-on=any` (measured rc 100, `E: Failed to fetch`)                                                |
| K3⁹  | risk                        | MINOR | A killed setup run leaves `hashicorp.list`; with no holds the next `-t update` upgrades packer and vagrant past the pins                         | Addressed (operator, option b): `update_apt_packages` removes a leftover before its `apt update`, fails closed if it cannot     |
| K4⁹  | risk                        | MINOR | The lock fixture cannot be captured: `flock` does not conflict with apt's `fcntl` lock, and `Debug::NoLocking=1` disables locking              | Addressed: fcntl holder, NoLocking dropped for that capture                                                                     |
| K5⁹  | risk                        | MINOR | The apt-get mock's fail loop exits before printing the fixture, so the never-fetched case cannot pass                                          | Addressed: section 5 fixes the mock's order                                                                                     |
| G1⁹  | goal-fit                    | MINOR | `<tool>=<VER>-*` resolves the revision in apt itself; the madison resolver, its mock, two fixtures and two cases buy nothing                   | Addressed: glob install; apt's not-found line drives the publish-lag hint                                                       |
| G2⁹ / E1⁹ | goal-fit, ergonomics   | MINOR | The "rc 0, old lists present" rotation path cannot happen: earlier steps' full `apt update` deletes this source's lists on every run         | Addressed: section 2 says every install run is a first fetch; rotated fixture and rc-0 branch dropped                           |
| E2⁹  | ergonomics                  | MINOR | check-versions `--update` for packer and vagrant prints no next step, and nothing reports a box below a bumped pin                            | Addressed: kind/yq-style next-step line plus the publish-lag note (R27); the unreported lag is stated as a cost (N4 stands)      |
| E3⁹  | ergonomics                  | MINOR | `dpkg-query` prints `no packages found` on stderr on every first install                                                                       | Addressed: `2>/dev/null`, rc 1 means not done                                                                                   |
| E4⁹  | ergonomics                  | MINOR | The refresh-failed line names no next action                                                                                                    | Addressed: `; re-run ./setup_env.sh -t developer`                                                                               |
| —    | goal-fit, ergonomics        | nit   | V1 still checks `apt-mark showhold`                                                                                                             | Addressed: dropped; R24 covers holds                                                                                            |

Not raised by a lens and added: `load_mocks` defaults `_APT_SOURCES_DIR`, because K3⁹'s removal
puts a real `rm` path into every `run_update` test.

**Assumption lines.** Goal-fit: the single-source refresh plus full-config install resolves
`openssl` from Ubuntu (round-9 measurement, not repeated). Ergonomics: every install run is a first
fetch (verified: `k8s_tools`' full `apt update` at `lib/linux_ubuntu.sh:930` runs immediately
before, and a sandbox showed the deletion). Risk: the same as goal-fit, verified with two sources;
noble's apt 2.7 (`--error-on`, version globs) unmeasured.

### Round 11 — spec at `3559b68c`

Same three lenses, fresh. Adversarial gate not triggered. No MAJOR. The operator adopted goal-fit's
relocation: the source file moves out of `/etc/apt` to `/var/lib/dotfiles/hashicorp.list`, read
only through `-o Dir::Etc::sourcelist=`. That withdraws round 10's K3⁹ disposition (the
`update_apt_packages` removal, then R26) and its `load_mocks` default; the round-10 rows are frozen
as written, and R26 now carries a different requirement.

| #     | Lens                 | Sev   | Finding                                                                                                                                                      | Disposition                                                                                                      |
| ----- | -------------------- | ----- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------- |
| G1¹⁰  | goal-fit             | MINOR | The `.list` in `sources.list.d` is the only reason for R26, its test default and deleting a hand-written `hashicorp.list`; a file outside apt's set removes all three | Addressed (operator, 2026-10-16): source file in `/var/lib/dotfiles`; R26 replaced; N6 forbids `/etc/apt`         |
| G2¹⁰ / E3¹⁰ | goal-fit, ergonomics | MINOR | R26's log line names "interrupted setup run" for any `hashicorp.list`, including a hand-written one                                                    | Moot: R26's removal is gone                                                                                      |
| E4¹⁰  | ergonomics           | MINOR | After a killed run the leftover is read by base, powershell, `:772` and `k8s_tools` before step 8 removes it                                                | Moot: the file is never in apt's configured set                                                                  |
| E1¹⁰  | ergonomics           | MINOR | The install's output capture is unstated; copying step 6's `$(…)` hides ~124 MB of download, and nothing prints before the refresh                        | Addressed: `refreshing` and `installing` lines; stdout streams, stderr captured (R26)                            |
| E2¹⁰  | ergonomics           | MINOR | "re-run" is wrong advice for a rotated key and loops for an unserved codename                                                                               | Addressed: exactly one next action per cause (R20)                                                               |
| K1¹⁰  | risk                 | MINOR | "Every install run is a first fetch" is false: apt skips List-Cleanup when any source fails; stale-list rotation output has only `NO_PUBKEY`, and no fixture isolates it | Addressed: premise reworded; `update-hashicorp-stale-rotated.txt` added                                      |
| K2¹⁰  | risk                 | MINOR | The not-found case cannot match `VAGRANT_VER`; the no-release case asserts `resolute` under the `noble` default                                             | Addressed: `VAGRANT_VER=9.9.9`, `MOCK_LSB_RELEASE_CS=resolute`                                                   |
| K3¹⁰  | risk                 | MINOR | Install-argv assertions cannot use the call log (conffile pairs stripped), and a regex on `-*` cannot fail                                                  | Addressed: `argv_probe_stub_path` with `grep -xF`                                                               |
| K4¹⁰  | risk                 | MINOR | The removal never says `sudo`; a plain `rm` passes in the seam dir and fails on the root-owned file                                                         | Addressed: `sudo rm -f` stated (R22) and asserted                                                               |
| K5¹⁰  | risk                 | MINOR | R27's write route is unspecified; `_update_release_pin`'s refresher rejects these tools and `_update_version_pin` has no read-back                         | Addressed: new `packer\|vagrant)` arm with read-back (R27)                                                       |
| K6¹⁰  | risk                 | MINOR | The dispatcher must set `_LINUX_ARCH` before `_k8s_env`, and "no hashicorp update" must filter on the source path since other steps run `apt-get update`   | Addressed: section 5                                                                                             |
| —     | risk                 | nit   | The never-fetched capture needs a wrong key, not the vendored one                                                                                           | Addressed: fixture list says which key                                                                           |

Not raised by a lens and added: a `_HASHICORP_SOURCE_DIR` seam set at setup scope, because the
sudo mock execs the real `install`, `tee` and `rm` (tdd.md E2).

**Assumption lines.** Goal-fit: apt's `_apt` download user can read a source file under a 0755
root directory outside `/etc/apt` (unmeasured; V1 checks for no unsandboxed notice). Ergonomics:
the implementation streams install stdout (now required, R26). Risk: noble's apt 2.7 behaves like
3.2.0 for `--error-on=any`, version globs and List-Cleanup skipped on failure (unmeasured).

### Round 12 — spec at `01efe313`

Same three lenses, fresh. Adversarial gate not triggered. No MAJOR. Risk measured the round-11
premises (`-o` after the verb, the install's source swap on `claude` and `workstation`, the stderr
capture, the dpkg gate) and they hold. The operator chose to keep the source file (option a).

| #     | Lens                 | Sev   | Finding                                                                                                                                             | Disposition                                                                                              |
| ----- | -------------------- | ----- | --------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| G1¹¹  | goal-fit             | MINOR | Step 8's removal is pure cost: nothing reads the file, yet a failed `sudo rm` fails a good install and carries four test obligations                | Addressed (operator, option a): the file stays and is rewritten each install run (R22 replaced)         |
| K1¹¹  | risk                 | MINOR | A hand-written `sources.list.d` entry with a different `signed-by=` makes apt refuse the source list, failing every install; keyring default unstated | Addressed: keyring at `/usr/share/keyrings`, HashiCorp's documented path (R29); install hint for the conflict |
| E3¹¹  | ergonomics           | MINOR | The keyring's default directory is unstated; two defaults exist in the codebase                                                                    | Addressed with K1¹¹; Costs lists the three owned paths                                                    |
| K2¹¹  | risk                 | MINOR | `_HASHICORP_SOURCE_DIR` is honoured in production, while the file it names is a root trust input                                                    | Addressed: gated on `BATS_TEST_TMPDIR` (R28)                                                             |
| K3¹¹  | risk                 | MINOR | `workflows.bats` runs the real step in four tests that set no seam                                                                                  | Addressed: `load_mocks` defaults (R28)                                                                   |
| K4¹¹  | risk                 | MINOR | R21's failed-write half has no case; the tee mock swallows failures                                                                                | Addressed: `install -d` and `tee` failure cases                                                          |
| K5¹¹  | risk                 | MINOR | "`installing` precedes its install" cannot fail: the mock prints nothing and the call log is a separate file                                        | Addressed: marker output, order asserted in `$output`                                                    |
| G2¹¹ / E2¹¹ | goal-fit, ergonomics, risk | MINOR | The 0755-for-`_apt` rationale and V1's unsandboxed check target a mechanism that cannot occur                                         | Addressed: rationale corrected from strace; V1 clause dropped                                            |
| G3¹¹  | goal-fit             | MINOR | The streaming case cannot tell streaming from capture-then-print                                                                                   | Addressed: case states its bound                                                                         |
| E1¹¹  | ergonomics           | MINOR | Section 4's CLAUDE.md edits miss the check-versions paragraph and the new seams and knobs                                                          | Addressed: section 4 lists them                                                                          |
| E4¹¹  | ergonomics           | MINOR | "does not serve <codename>" also fires on a 404 for a served codename; the R27 arm lacks an X.Y.Z check and its `Updated` line is unstated          | Addressed                                                                                                |
| —     | risk                 | nit   | `Unable to locate package` gets no hint; the rm-fails case contradicts the absent-file rule                                                         | Addressed: hint added; both moot cases removed with step 8                                               |

**Assumption lines.** Goal-fit: the round-11 simulated install holds for a real root run (trusted,
not re-run). Ergonomics: the operator reads diagnostics in the scrollback of a long run. Risk:
noble's apt 2.7 matches 3.2.0 for `-o` after the verb, `--error-on=any`, globs and the Signed-By
conflict (unmeasured).

## Requirements

- **R1.** `_install_ubuntu_hashicorp` installs exactly packer and vagrant; no code path installs consul, vault or nomad.
- **R2.** `lib/constants.sh` defines no `CONSUL_VER`, `NOMAD_VER`, `VAULT_VER` or `HASHICORP_URL`, and defines `HASHICORP_GPG_FPR="D55C0D1AC78A8D8126CB631CFC9CA96ACA026560"`.
- **R3.** `_install_fetched_binary` has no `--unverified` mode, and no file in `lib/` contains the string `pending HashiCorp apt`.
- **R4.** `keys/hashicorp.asc` is tracked and its primary fingerprint is `HASHICORP_GPG_FPR`.
- **R5.** The keyring is built by `_build_pinned_keyring` from the vendored key with `HASHICORP_GPG_FPR`; a key whose primary fingerprint differs makes the step return 1 with no keyring left behind, no `hashicorp.list` written and no `apt-get install` of packer or vagrant.
- **R6.** After step 5, `<_HASHICORP_SOURCE_DIR>/hashicorp.list` (default `/var/lib/dotfiles/hashicorp.list`) holds exactly one line: `deb [arch=<dpkg arch> signed-by=<keyring>] https://apt.releases.hashicorp.com <lsb_release -cs> main`, whatever the file held before.
- **R7.** Each tool in the install set is installed as `sudo -H DEBIAN_FRONTEND=noninteractive apt-get install -y "${APT_CONFFILE_OPTS[@]}" -o Dir::Etc::sourcelist=<_HASHICORP_SOURCE_DIR>/hashicorp.list --allow-downgrades "<tool>=<VER>-*"`; when that fails and its stderr says the version was not found, the failure line names `<VER>`, `apt.releases.hashicorp.com` and re-running `./setup_env.sh -t developer`.
- **R8.** A tool whose `dpkg-query -W -f='${db:Status-Abbrev} ${Version}'` output (stderr discarded) shows status `ii` and upstream version `<VER>` is not reinstalled, and the step prints `<tool>: up to date (<deb version>)`.
- **R9.** On a box whose `_LINUX_ARCH` is not `amd64`, vagrant is not installed and the step prints `hashicorp: vagrant: no arm64 build; skipped`; the skip itself does not fail the step, but a failed removal of a stamped vagrant at that point does, and the skip and its removal run whatever the refresh does.
- **R10.** One tool's install failure names that tool on stderr and returns 1, and the other tool is still attempted.
- **R11.** Subject to R12, for each of consul, vault, nomad, packer and vagrant with a stamp in `_DL_STAMP_DIR`, the step removes `_DL_BIN_DIR/<tool>` and the stamp; with no stamp, an existing `_DL_BIN_DIR/<tool>` is left in place and a warning names it.
- **R12.** A stamped packer or vagrant copy is removed only after that tool's apt install succeeded, or when the tool takes the R8 up-to-date branch, or for vagrant on non-amd64 at its skip; when the install fails or is not attempted, the copy and its stamp remain.
- **R13.** `.config/.zshrc.d/5_general.zsh` contains no completion line for vault, consul or nomad.
- **R14.** `Brewfile` has no consul, nomad or vault entry, has `tap "hashicorp/tap", trusted: true` and `brew "hashicorp/tap/packer"` tagged `# [HAS_DEVTOOLS]`, and has no `brew "packer"` line.
- **R15.** Both macOS `brew trust` calls (`lib/macos.sh`, `lib/helpers.sh`) include `hashicorp/tap`.
- **R16.** `run_check_versions` checks packer (`hashicorp/packer`, `PACKER_VER`) and vagrant (`hashicorp/vagrant`, `VAGRANT_VER`) through `_run_cv_pinned_release`, comparing the pin, not the installed binary, with GitHub latest.
- **R17.** When `brew list --formula --full-name` contains a bare `packer`, `install_macos_casks` prints one line naming `brew uninstall packer consul vault nomad` and returns 1 without running any `brew bundle`.
- **R18.** ADR-0046 carries a dated amendment describing PR B as built, and the README backlog row "HashiCorp tools are installed without a checksum" is gone.
- **R19.** The step refreshes with `sudo -H apt-get update --error-on=any -o Dir::Etc::sourcelist=<_HASHICORP_SOURCE_DIR>/hashicorp.list -o Dir::Etc::sourceparts=- -o APT::Get::List-Cleanup=0 2>&1`, output captured in a variable and exit status kept; when the output has a `W:` or `E:` line containing `apt.releases.hashicorp.com` and one of `NO_PUBKEY`, `EXPKEYSIG`, `EXPSIG`, `KEYEXPIRED`, `REVKEYSIG`, `is not signed` or `is no longer signed`, the step prints a line containing `is not verified by keys/hashicorp.asc`, both causes (key rotated or expired, host served unsigned data) and `HASHICORP_GPG_FPR` on stderr and returns 1.
- **R20.** When the R19 refresh exits non-zero, the step prints one line naming its exit status, the first `E:` line of the output (else its last line) and that installed copies are untouched, ending in exactly one next action: `see the next line` when the R19 rotation line prints, a wait-for-HashiCorp-to-publish-`<codename>` instruction when that `E:` line contains `does not have a Release file`, and `re-run ./setup_env.sh -t developer` otherwise; it attempts no tool in the install set and returns 1.
- **R21.** When `dpkg --print-architecture` or `lsb_release -cs` prints nothing, no source file is written and the step returns 1; a failed write leaves no partial source file.
- **R22.** The step never removes `<_HASHICORP_SOURCE_DIR>/hashicorp.list`; it is rewritten on every install run before the refresh.
- **R23.** When every tool is up to date or skipped, the step builds no keyring, writes no source file and runs no `apt-get update`.
- **R24.** No code runs `apt-mark hold` or passes `--allow-change-held-packages` for packer or vagrant.
- **R25.** The dispatcher test "install_ubuntu_packages: a clean run reaches every step, and a second run re-fetches nothing" runs the real hashicorp step and asserts the packer and vagrant `apt-get install` calls on its first run and both `up to date (` lines on its second.
- **R26.** The step prints `hashicorp: refreshing apt.releases.hashicorp.com` before the R19 refresh and `hashicorp: installing <tool> <VER>` before each install; the install's stdout is not captured.
- **R27.** `check-versions --update` for packer or vagrant refuses a latest that is not `X.Y.Z`, edits only that tool's `*_VER` line, reads it back, returns 1 without a next-step line when the read-back fails, and otherwise prints `Updated <VAR> → <version>` and a line naming `./setup_env.sh -t developer` and the apt publish lag.
- **R28.** `_HASHICORP_SOURCE_DIR` and `_HASHICORP_KEY_PATH` are honoured only when `BATS_TEST_TMPDIR` is non-empty, and `load_mocks` exports `_HASHICORP_SOURCE_DIR` and `_APT_KEYRINGS_DIR` under `BATS_TEST_TMPDIR`.
- **R29.** The keyring is `<_APT_KEYRINGS_DIR>/hashicorp-archive-keyring.gpg` with `_APT_KEYRINGS_DIR` defaulting to `/usr/share/keyrings`.
- **V1.** On `claude` and `workstation`, `./setup_env.sh -t developer` then: `command -v packer vagrant` gives `/usr/bin/packer` and `/usr/bin/vagrant`; `/etc/apt/sources.list.d/hashicorp.list` does not exist; none of `/usr/local/bin/{consul,vault,nomad,packer,vagrant}` exists; a second run prints the two `up to date` lines and no removal line; `./setup_env.sh -t update` then reports the `apt` section OK and `dpkg-query -W packer vagrant` is unchanged.
- **V2.** On the Studio, after `brew uninstall packer consul vault nomad`, `brew untap hashicorp/tap` (if tapped) and `brew untrust hashicorp/tap`, and with `! grep -q hashicorp/tap ~/.homebrew/trust.json` and `HOMEBREW_NO_REQUIRE_TAP_TRUST` unset checked immediately before the run, the main `brew bundle` in `install_macos_casks` exits 0 and installs `hashicorp/tap/packer` (the gui and devtools bundles are reported separately, not asserted), and `brew list --formula --full-name` shows `hashicorp/tap/packer` with `packer --version` at or above `PACKER_VER`.
- **V3.** CI green, including `bash-coverage` at or above its floor.
- **N1.** No code uninstalls a Homebrew formula or cask.
- **N2.** No code removes a `/usr/local/bin` file that has no matching stamp in `_DL_STAMP_DIR`.
- **N3.** No vagrant is installed on a non-amd64 Linux box.
- **N4.** No new doctor check (for key expiry, signer mismatch or anything else).
- **N5.** The HashiCorp key is never fetched over the network at install time.
- **N6.** No code writes a HashiCorp apt source under `/etc/apt`.
