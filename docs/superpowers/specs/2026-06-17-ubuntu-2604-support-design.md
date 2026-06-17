# Ubuntu 26.04 "Resolute Raccoon" Support

## Context

Ubuntu 26.04 LTS ("Resolute Raccoon") shipped April 23, 2026. This dotfiles repo was built against
Noble (24.04). This document tracks every known gap, ordered by severity. Each item maps to one of
five proposed PRs.

Key facts confirmed via web research (2026-06-17):

- Codename: `resolute` (`VERSION_CODENAME=resolute` in `/etc/os-release`)
- Kernel: Linux 7.0
- Python: 3.13 (stdlib `crypt` module removed)
- Docker: 29 (containerd image store default; cgroup v2 mandatory)
- cgroup v1: **fully removed** — systemd 259 dropped it; no fallback
- X11 GNOME session: **removed** — Wayland-only (XWayland present for app compat)
- PowerShell: `packages.microsoft.com/ubuntu/26.04/prod` published day 1 ✓
- Docker repo: `download.docker.com/linux/ubuntu resolute` published day 1 ✓
- HWE package: `linux-generic-hwe-26.04` exists

---

## Backlog

### P0 — Breaks fresh 26.04 setup today

| ID   | File(s)                                             | Issue                                                                                                                   | Fix                                                                              |
| ---- | --------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------- |
| P0-1 | `lib/detect_env.sh:16`                              | `NOBLE=1` only fires for `"24.04"` — 26.04 gets no version var, every Noble-gated block skips silently                  | Add `[[ ${UBUNTU_VERSION} = "26.04" ]] && readonly RESOLUTE=1`                   |
| P0-2 | `lib/linux_ubuntu.sh:22`                            | `linux-generic-hwe-24.04` hardcoded — package absent on 26.04, base install fails                                       | Branch on `RESOLUTE` → `linux-generic-hwe-26.04`                                 |
| P0-3 | _(missing)_                                         | No `ubuntu_2604_packages.txt` — `_install_ubuntu_base_packages()` loads 2404 file on 26.04                              | Create file; clone `ubuntu_2404_packages.txt`, swap HWE package name             |
| P0-4 | `lib/linux_ubuntu.sh:_install_ubuntu_base_packages` | No version branch — loads 2404 packages unconditionally                                                                 | Add `RESOLUTE` branch selecting `ubuntu_2604_packages.txt`                       |
| P0-5 | `lib/linux_ubuntu.sh:_install_ubuntu_docker`        | No `/etc/docker/daemon.json` written — cgroup v1 gone in kernel 7.0/systemd 259; Docker 29 may default wrong on upgrade | Write `{"exec-opts":["native.cgroupdriver=systemd"]}` idempotently after install |
| P0-6 | `lib/developer.sh:setup_ansible`                    | Python 3.13 removes `crypt` stdlib — ansible/pip packages that import `crypt` fail on load                              | Audit pip packages; add `passlib` to ansible venv install list                   |

---

### P1 — High probability of failure or corrupt state

| ID   | File(s)                           | Issue                                                                                                                                            | Fix                                                                                             |
| ---- | --------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------- |
| P1-1 | `lib/helpers.sh:199`              | Nala install via hard-coded volian archive `.deb` URL — 2022-era bootstrap; nala likely in official 26.04 repos                                  | Version branch: use `apt install nala` directly on 26.04                                        |
| P1-2 | `lib/linux_ubuntu.sh:477`         | `python -m pip install glances` — PEP 668 externally-managed error on 26.04                                                                      | Replace with `pipx install glances` or install inside pyenv venv                                |
| P1-3 | `ubuntu_common_packages.txt`      | `ruby-full` installs system Ruby 3.4+ alongside rbenv — shadows rbenv Ruby until `rbenv global` explicitly set                                   | Remove `ruby-full`; rely on rbenv exclusively                                                   |
| P1-4 | `lib/developer.sh:125`            | `rbenv install ${RUBY_VER}` with `RUBY_VER="4.0.5"` — Ruby 4 may not have a `ruby-build` definition; no guard                                    | Add `rbenv install --list                                                                       | grep -q "^ ${RUBY_VER}$"` check; log skip with instructions if missing |
| P1-5 | `lib/linux_ubuntu.sh:97`          | `ppa:longsleep/golang-backports` — dead code (Go ≥1.21 uses tarball), but branch still live if `GO_VER` minor ≤20; longsleep PPA slow on new LTS | Remove PPA path entirely; tarball only                                                          |
| P1-6 | `lib/constants.sh:VIRTUALBOX_VER` | `virtualbox-7.0` — kernel 7.0 DKMS module compat unverified; VirtualBox notoriously slow on new kernels                                          | Verify VirtualBox 7.1/7.2 + kernel 7.0; pin to supported version or add post-install smoke test |

---

### P2 — Silently wrong or incomplete

| ID   | File(s)                                           | Issue                                                                                                                                    | Fix                                                                            |
| ---- | ------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| P2-1 | `.config/.zshrc.d/1_init.zsh:14-15`               | Shell sets `BIONIC=1` (EOL 2023), no `RESOLUTE` — shell env diverged from `detect_env.sh`                                                | Add `[[ ${UBUNTU_VERSION} = "26.04" ]] && export RESOLUTE=1`; prune `BIONIC`   |
| P2-2 | `lib/developer.sh:30`                             | AWS CLI Linux: `awscli-exe-linux-x86_64.zip` hardcoded — ARM64 machines get wrong binary                                                 | Branch on `$(uname -m)`: `x86_64` vs `aarch64`                                 |
| P2-3 | `lib/constants.sh:GO_DOWNLOAD_FILENAME`           | `go1.26.1.linux-amd64.tar.gz` hardcoded — ARM64 gets wrong binary                                                                        | Derive at runtime: `go${GO_VER}.1.linux-$(dpkg --print-architecture).tar.gz`   |
| P2-4 | `ubuntu_common_packages.txt`                      | `xinetd` — removed from Ubuntu universe in 26.04; `ruby-full` — conflicts with rbenv (see P1-3); `python3-pip` — PEP 668 misleads users  | Remove `xinetd`, `ruby-full`; annotate `python3-pip`                           |
| P2-5 | `lib/linux_ubuntu.sh:_install_ubuntu_cloud_tools` | Teleport install — if URL uses codename needs `resolute` support; unverified                                                             | Verify Teleport publishes `resolute` repo; add graceful fallback               |
| P2-6 | `lib/constants.sh`                                | Stale version pins: `CONSUL_VER=1.16.0`, `VAULT_VER=1.14.1`, `NOMAD_VER=1.6.1`, `PACKER_VER=1.15.1`                                      | Bump all to current stable before 26.04 PR                                     |
| P2-7 | `Brewfile.devtools`                               | `tap "chef/chef"` (line 2) and `cask "chef/chef/inspec"` (line 14) — missed in PR #140                                                   | Remove both lines                                                              |
| P2-8 | `config/profiles.sh` + `lib/linux_ubuntu.sh`      | Flatpak code exists (`flatpak remote-add flathub`) but no `HAS_FLATPAK` capability — untracked, silently installs on all `HAS_GUI` Linux | Add `flatpak` to `linux_workstation` capability; gate install on `HAS_FLATPAK` |
| P2-9 | `lib/linux_ubuntu.sh:388`                         | `gitguardian/tap` in Linux `brew trust` but absent from `lib/helpers.sh` macOS brew trust — inconsistency                                | Add `gitguardian/tap` to `helpers.sh` brew trust list                          |

---

### P3 — Low risk / cleanup

| ID   | File(s)                                 | Issue                                                                                                   |
| ---- | --------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| P3-1 | `.config/.zshrc.d/1_init.zsh`           | Dead OS branches: `CENTOS`, `REDHAT`, `FEDORA` vars set, nothing uses them                              |
| P3-2 | _(missing)_                             | No `ubuntu_2204_packages.txt` — Jammy never got a per-version file                                      |
| P3-3 | `ubuntu_workstation_snap_packages.txt`  | List unaudited for 26.04 — some snaps may have moved to apt or Flatpak                                  |
| P3-4 | `CLAUDE.md`                             | rbenv (Linux) vs chruby (macOS) split undocumented                                                      |
| P3-5 | `lib/helpers.sh:check_and_install_nala` | Installs nala then continues using `apt-get`/`apt` — if nala is the goal, switch subsequent calls       |
| P3-6 | _(note)_                                | SysV init scripts deprecated in 26.04, **removed in 26.10** — no action now but flag for next LTS cycle |
| P3-7 | `.config/.zshrc.d/1_init.zsh`           | `BIONIC`, `FOCAL`, `JAMMY` version vars set in zshrc but not in `detect_env.sh` — split model           |

---

## Proposed PR Batching

```
PR1 (detection + packages) → PR2 (docker/python) → PR3 (packages/ruby/Go)
                                                   → PR4 (ARM64)
                                                   → PR5 (housekeeping)
```

| PR  | Title                                                                  | Items                                                 | Depends on |
| --- | ---------------------------------------------------------------------- | ----------------------------------------------------- | ---------- |
| PR1 | `feat(ubuntu): add 26.04 Resolute Raccoon detection and package files` | P0-1, P0-2, P0-3, P0-4, P2-1                          | —          |
| PR2 | `fix(docker): cgroup v2 daemon config + Python 3.13 crypt migration`   | P0-5, P0-6, P1-2                                      | PR1        |
| PR3 | `fix(packages): nala, ruby, Go PPA cleanup`                            | P1-1, P1-3, P1-4, P1-5, P2-4                          | PR1        |
| PR4 | `fix(arch): ARM64 support for Go and AWS CLI`                          | P2-2, P2-3                                            | PR1        |
| PR5 | `chore: housekeeping — version bumps, chef, flatpak, stale vars`       | P1-6, P2-5, P2-6, P2-7, P2-8, P2-9, P3-1 through P3-7 | PR1        |

---

## Breaking changes that affect this repo (notes only)

- **cgroup v1 removed**: Docker 29 works correctly with cgroup v2. `daemon.json` fix in P0-5 handles this.
- **X11 GNOME session removed**: XWayland present; GUI apps work. Snap packages with direct X11 deps may need audit (P3-3).
- **Python 3.13 `crypt` removed**: Handled in P0-6. Also: `walinuxagent` (Azure) affected — not a concern for this repo.
- **sudo-rs default**: New Rust sudo with asterisk password feedback. No impact on setup scripts.
- **SysV init deprecated**: No SysV scripts in this repo. Note for 26.10 cycle.
- **Docker `pids.limit = 0` now means 1**: No containers defined in this repo. Not applicable.
