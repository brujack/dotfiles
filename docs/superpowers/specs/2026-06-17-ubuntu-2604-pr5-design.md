# Ubuntu 26.04 PR5 — Housekeeping

> Parent spec: [2026-06-17-ubuntu-2604-support-design.md](2026-06-17-ubuntu-2604-support-design.md)

Final PR in the Ubuntu 26.04 Resolute Raccoon support series. Cleans up stale
configurations, fixes misplaced capability gates, and removes dead OS variables
from the shell environment init file.

---

## Scope

Items from the parent spec implemented in this PR:

| ID   | Priority | Summary                                                                            |
| ---- | -------- | ---------------------------------------------------------------------------------- |
| P1-6 | P1       | Update `VIRTUALBOX_VER` from `virtualbox-7.0` to `virtualbox-7.1`                  |
| P2-7 | P2       | Remove `tap "chef/chef"` and `cask "chef/chef/inspec"` from `Brewfile.devtools`    |
| P2-8 | P2       | Add `HAS_FLATPAK` capability; fix Steam flatpak gate (was wrongly on `HAS_SNAP`)   |
| P2-9 | P2       | Add `gitguardian/tap` to macOS `brew trust` in `lib/helpers.sh`                    |
| P3-1 | P3       | Remove dead `CENTOS`, `REDHAT`, `FEDORA` vars from `.zshrc.d/1_init.zsh`           |
| P3-4 | P3       | Document rbenv (Linux) vs chruby (macOS) Ruby version manager split in `CLAUDE.md` |
| P3-7 | P3       | Remove stale `BIONIC`, `FOCAL`, `JAMMY` vars from `.zshrc.d/1_init.zsh`            |

---

## Items Deferred or Resolved

| ID   | Resolution                                                                                              |
| ---- | ------------------------------------------------------------------------------------------------------- |
| P2-5 | Teleport already uses `stable main` repo (codename-independent) — no change needed                      |
| P2-6 | Done in PR4 — version pins bumped to current stable                                                     |
| P3-2 | Moot — Ubuntu 22.04 Jammy dropped in PR #90; no `ubuntu_2204_packages.txt` needed                       |
| P3-3 | Deferred — requires real Ubuntu 26.04 installation to audit snap packages accurately                    |
| P3-5 | Deferred — switching nala post-install calls from `apt-get` is risky; requires careful testing on 26.04 |
| P3-6 | Note only — SysV init deprecated in 26.04, no code changes needed                                       |

---

## Detail: P2-8 HAS_FLATPAK

Current code (incorrect): the Steam flatpak install block is gated on `HAS_SNAP`
rather than `HAS_FLATPAK`. This means:

- On HAS_SNAP machines without flatpak, `flatpak` commands fail at runtime.
- On machines with flatpak but not snap, Steam is silently skipped.

Fix:

1. Add `flatpak` to the `[linux_workstation]` capability list in `config/profiles.sh`
   (currently: `"gui devtools aws k8s docker rust snap"`)
2. Change the Steam block guard from `if [[ -n ${HAS_SNAP} ]];` to
   `if [[ -n ${HAS_FLATPAK} ]];` in `lib/linux_ubuntu.sh:_install_ubuntu_gui_tools`

---

## Detail: P3-1 + P3-7 — Dead OS Variables

After PR #89 (removed RHEL/CentOS/Fedora) and PR #90 (dropped 18.04/20.04/22.04),
these lines in `.config/.zshrc.d/1_init.zsh` are dead code:

```zsh
# P3-1 — remove (distros dropped in PR #89):
[[ ${LINUX_TYPE} = "CentOS Linux" ]] && export CENTOS=1
[[ ${LINUX_TYPE} = "Red Hat Enterprise Linux Server" ]] && export REDHAT=1
[[ ${LINUX_TYPE} = "Fedora" ]] && export FEDORA=1

# P3-7 — remove (Ubuntu versions dropped in PR #90):
[[ ${UBUNTU_VERSION} = "18.04" ]] && { [[ -n "${BIONIC+x}" ]] || readonly BIONIC=1; }
[[ ${UBUNTU_VERSION} = "20.04" ]] && { [[ -n "${FOCAL+x}" ]] || readonly FOCAL=1; }
[[ ${UBUNTU_VERSION} = "22.04" ]] && { [[ -n "${JAMMY+x}" ]] || readonly JAMMY=1; }
[[ ${UBUNTU_VERSION} = "6" ]] && { [[ -n "${FOCAL+x}" ]] || readonly FOCAL=1; }  # elementary os
```

Lines to retain: `UBUNTU=1`, `NOBLE=1`, `RESOLUTE=1`.

New tests in `tests/zshrc.d/unit.bats` verify:

- `BIONIC` is not set when `MOCK_LSB_RELEASE_RS=18.04`
- `JAMMY` is not set when `MOCK_LSB_RELEASE_RS=22.04`
