# Install nala from the Ubuntu archive on every release

- **Date:** 2026-10-04
- **Backlog row closed:** "Volian archive debs install as root with no integrity check" (P2 — bugs and security).

## Problem

`check_and_install_nala` (`lib/helpers.sh`) installs nala only when it is not already `ii`.
On any Ubuntu release other than 26.04 (`RESOLUTE` unset) it first:

- `wget`s `volian-archive-keyring_0.2.0_all.deb` and `volian-archive-nala_0.2.0_all.deb` from
  GitLab upload URLs, with no sha256 pin, no signature check and no `wget` exit check;
- runs `sudo dpkg --install` on both, as root;
- runs `apt update`, then installs nala.

So whoever controls those URLs runs code as root on a fresh non-26.04 provision. The two debs
carry a keyring, an apt `.sources` file and a `preferences.d` pin to volian's `scar-unstable`
channel, and no maintainer scripts. That was checked with `dpkg-deb -c` on 2026-10-03 against
the current URLs, so it describes today's files, not what the URLs serve tomorrow. Found by the
security-review of dotfiles#310.

## Premise checks

- **The bootstrap is unnecessary on Noble.** Launchpad's published sources for the Ubuntu
  primary archive, queried 2026-10-04, list `nala 0.15.1` in `universe`, pocket `Release`, for
  `noble`. For `jammy` it is `0.11.1~bpo22.04.1` in `Backports`. The volian path dates from
  2023-11 (`29113506`, `af315bea`), when Jammy was current. #145 (`a2fd2912`, 2026-06-17) moved
  26.04 to `apt install nala` and kept Noble on volian "unchanged". Its spec
  (`2026-06-17-ubuntu-2604-pr3-design.md`) gives scope as the reason and states no technical
  one.
- **Nothing on the fleet's Linux dev boxes depends on volian.** Measured 2026-10-04:
  `claude` and `workstation` are both on Ubuntu 26.04, carry no `volian*` package and no
  `volian` file in `/etc/apt/sources.list.d`, and `workstation`'s nala 0.16.0 comes from
  `resolute/universe`. That covers those two machines only. Other Ubuntu hosts were not
  checked.
- **Every caller refreshes apt lists first.** `lib/linux_ubuntu.sh:39` runs `apt update`
  before the calls at `:43` and `:51`. `lib/linux_shared.sh:54` does the same before `:55`. The
  call at `lib/linux_ubuntu.sh:1335` ends a function that has already run `apt update` several
  times. The 26.04 path relies on this today, so Noble would too.

## Decision

Delete the volian bootstrap. Every Ubuntu release takes the existing 26.04 path:
`sudo -H DEBIAN_FRONTEND=noninteractive apt install "${APT_CONFFILE_OPTS[@]}" nala -y`.

Rejected: **pin each sha256, `sha256sum -c`, and check `wget`.** That keeps root-installed
third-party debs and a third-party apt source pinned to an unstable channel. It also needs
re-pinning whenever volian republishes, for no benefit over the Ubuntu archive's nala.

This removes the two volian `dpkg --install` calls that dotfiles#310 gave `--force-confmiss`.
Its spec's R5/R11 named three archive-setup debs. After this change there is one,
`packages-microsoft-prod.deb`. That spec shipped and is not edited. This spec governs from
here, and ADR-0040 gets a dated amendment note.

### Changes

- `lib/helpers.sh` `check_and_install_nala`: remove the `if [[ -z ${RESOLUTE} ]]; then … fi`
  block (both `wget`s, both `dpkg --install`, its comments, its `apt update`). The surrounding
  Linux/Ubuntu/not-`ii` guards and the `apt install` line are unchanged.
- `tests/setup_env/install_functions.bats`:
  - delete `check_and_install_nala: volian dpkg --install sees DEBIAN_FRONTEND=noninteractive`;
  - delete `conffile argv: volian dpkg --install restores deleted conffiles (confmiss) on both debs`;
  - replace `check_and_install_nala on NOBLE uses volian wget path` with a NOBLE test. It
    asserts that `apt install` of nala ran and that there were zero `wget` and zero `dpkg
    --install` calls.
  - keep the RESOLUTE test.
- `tests/scripts/dpkg_sudo_frontend.bats`:
  - the confmiss allow-set becomes `packages-microsoft-prod.deb` only;
  - drop the `'lib/helpers.sh|sudo.*dpkg --install'` anchor from the real-tree enumeration
    test. The `'lib/linux_ubuntu.sh|sudo.*dpkg -i'` anchor already keeps the dpkg family
    reached. The fixture tests that cover `--install` stay.
- `CLAUDE.md`: the Shell Scripts conffile bullet says confmiss sits only on
  `packages-microsoft-prod.deb`.
- `docs/adr/0040-…`: add a dated amendment note saying the volian path was removed and
  confmiss is on the Microsoft deb only, with a pointer to this spec. The original text stays.
- `docs/superpowers/README.md`:
  - delete the volian backlog row;
  - narrow the repair-gap row to the Microsoft package only (its guard is `_pwsh_probe_runs`).
- `ai-config/docs/knowledge/dotfiles-apt-upgrade-hazards.md` §2b: one sentence saying the
  volian calls were removed. This is a separate docs-only commit to ai-config, not part of the
  dotfiles PR.

## Testing

TDD: write the new NOBLE test first and watch it fail against the current code (the volian
`wget` runs). Then delete the block, then update the gate and the remaining tests.

Mutation checks:

- re-adding a volian `wget` line turns the NOBLE test red;
- adding `--force-confmiss` to any other dpkg or apt call turns the confmiss allow-set test red;
- deleting the `apt install … nala` line turns both the NOBLE and RESOLUTE tests red.

## Requirements

- **R1.** `[PR1]` `check_and_install_nala` in `lib/helpers.sh` contains no `wget`, no `dpkg --install` and no `volian` text, and installs nala with `sudo -H DEBIAN_FRONTEND=noninteractive apt install "${APT_CONFFILE_OPTS[@]}" nala -y` on every Ubuntu release.
- **R2.** `[PR1]` No tracked file under `lib/`, `scripts/`, `setup_env.sh` or `tests/` contains the text `volian`.
- **R3.** `[PR1]` A bats test with `NOBLE=1` and `RESOLUTE` unset asserts that `check_and_install_nala` runs `apt install` of nala and makes zero `wget` calls and zero `dpkg --install` calls.
- **R4.** `[PR1]` The confmiss allow-set in `tests/scripts/dpkg_sudo_frontend.bats` is exactly `packages-microsoft-prod.deb`, and the whole file passes.
- **R5.** `[PR1]` The real-tree enumeration test in `tests/scripts/dpkg_sudo_frontend.bats` no longer names a `lib/helpers.sh` dpkg site, and still names at least one `dpkg` site.
- **R6.** `[PR1]` `CLAUDE.md` states that `--force-confmiss` appears only at the `packages-microsoft-prod.deb` install.
- **R7.** `[PR1]` `docs/adr/0040-apt-conffile-prompts-answered-unattended.md` carries a dated amendment note naming the volian removal and this spec, and its original Decision text is unchanged.
- **R8.** `[PR1]` `docs/superpowers/README.md` has no volian backlog row, and its repair-gap row names only the Microsoft package and `_pwsh_probe_runs`.
- **V1.** Mutations: re-adding a volian `wget` turns the R3 test red; adding `--force-confmiss` to another dpkg or apt call turns the confmiss test red; deleting the nala `apt install` line turns the NOBLE and RESOLUTE tests red.
- **V2.** `make test` passes, and the changed bats files pass on the Mac Studio (bundle clone, bare env).
- **N1.** No code removes volian packages or sources from machines that already have them.
- **N2.** `_install_ubuntu_powershell` and `packages-microsoft-prod.deb` handling are unchanged.
- **N3.** No new `apt update` call is added.
- **N4.** The 2026-10-03 apt-conffile spec's text is not edited.
