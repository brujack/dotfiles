# ADR-0040: apt/dpkg conffile prompts are answered unattended

**Date:** 2026-10-03
**Status:** Accepted.

## Context

Setup and update run apt, nala and dpkg with no usable stdin: `xargs` hands its children
`/dev/null`, and `-t update` tees stdout and stderr. When a package ships a changed conffile,
dpkg asks what to do, reads end-of-file, and fails with `end of file on stdin at conffile
prompt`. The package is left `iU` (unpacked, not configured) and every later apt operation
trips on it. The same failure hit `dpkg -i` of a vendor archive deb whose conffile the operator
had deleted. Measurements are in `ai-config/docs/knowledge/dotfiles-apt-upgrade-hazards.md`
sections 2 and 2b. #280 fixed this for `full-upgrade` only.

## Decision

1. One array, `APT_CONFFILE_OPTS` in `lib/constants.sh`
   (`-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold`), is carried by every
   configuring `sudo apt|apt-get|nala` call. The operator's edited file is kept and dpkg writes
   the package copy beside it as `.dpkg-dist`.
2. `--force-confmiss` is added only at the three archive-setup `dpkg` installs:
   `packages-microsoft-prod.deb` and the two volian debs. Each package carries only vendor apt
   archive configuration (the volian pair: a keyring, a `.sources` file and a `preferences.d`
   pin, no maintainer scripts, checked with `dpkg-deb -c`), so restoring a deleted file is
   always right. Elsewhere confmiss would
   undo a deliberate deletion. It is load-bearing, measured on `claude` with a throwaway
   one-conffile package:

   | step                                                         | rc | state | conffile |
   | ------------------------------------------------------------ | -- | ----- | -------- |
   | `dpkg -i` v1, delete the conffile                            | 0  | `ii`  | absent   |
   | `dpkg -i` v2, no force                                       | 1  | `iU`  | absent   |
   | v2 with confdef+confold+confmiss                             | 0  | `ii`  | restored |
   | from a fresh `iU`: confdef+confold only                      | 0  | `ii`  | absent   |
   | from `ii`, conffile deleted: same-version reinstall, no miss | 0  | `ii`  | absent   |
   | same, plus confmiss                                          | 0  | `ii`  | restored |

3. Rejected: an `apt.conf.d` drop-in (a global, machine-wide policy that dpkg calls outside
   our workflows would inherit, and invisible at the call site); a wrapper function (a second
   place for the policy to drift, and the gate must still read the real call); literal flags at
   each site (the policy would be restated at dozens of sites).
4. Enforcement is the existing dpkg sudo gate, `tests/scripts/dpkg_sudo_frontend.bats`, which
   now rejects a configuring call without both options and any confmiss outside the three debs.
5. A doctor check, `_doctor_check_conffile_dist` (`lib/helpers.sh`), replaces the prompt that
   confold removed. It reports every `*.dpkg-dist` and `*.ucf-dist` under `/etc` on Linux until
   the operator merges and deletes it. It is presence-based, not time-based: dpkg keeps the
   archive's mtime on `.dpkg-dist`, so age says nothing about when it was written (measured:
   `find -newer` against a reference file at epoch 0 versus `-cnewer` at epoch 1 disagree on it).
   Its seam is `_OVERRIDE_CONFFILE_DIST_ROOT`.

## Consequences

- The repair runs only when the caller's install guard lets the call run. `_install_ubuntu_powershell`
  returns early when `_pwsh_probe_runs` succeeds and `check_and_install_nala` installs only when
  nala is not `ii`, so a package already `iU` from an earlier failure, or an archive-setup
  package at `ii` with a deleted keyring/source, is not repaired by this change. Recorded as a
  backlog row (R19); the guards are unchanged.
- `.ucf-dist` copies are now surfaced; `claude` already has `/etc/default/grub.ucf-dist`, so
  the check WARNs there until the operator handles it.
- The scan runs unprivileged, so it skips root-only directories under `/etc`; none holding
  conffiles were found on `claude`.
- `*.dpkg-new` and `*.ucf-new` are not matched: they mean an interrupted install, which needs a
  different remedy.
- The bootstrap script uses the same array (spec amendment to R7), since it sources
  `lib/constants.sh` before installing.

## Related

- Spec: `docs/superpowers/specs/2026-10-03-apt-conffile-noninteractive-design.md`
- Plan: `docs/superpowers/plans/2026-10-03-apt-conffile-noninteractive.md`
- ADR-0039; #280
- `ai-config/docs/knowledge/dotfiles-apt-upgrade-hazards.md`
