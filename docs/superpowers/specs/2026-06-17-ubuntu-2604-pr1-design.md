# PR1: Ubuntu 26.04 Resolute Raccoon — Detection and Package Files

## Context

Ubuntu 26.04 LTS ("Resolute Raccoon", codename `resolute`) shipped April 23, 2026. This is
the first of five PRs to add full 26.04 support. PR1 covers the detection layer and package
files — the foundation every other PR depends on.

Prior art: `lib/linux_ubuntu.sh` used an `if/elif` branch per Ubuntu LTS version until
PR #90 dropped 18.04/20.04/22.04 support and collapsed it to Noble-only. This PR restores
the pattern with NOBLE + RESOLUTE.

## Research

Package availability on Ubuntu 26.04 verified against `packages.ubuntu.com/resolute`:

- `silversearcher-ag` — present in Noble, **absent from Resolute** (move to 2404 list)
- All other packages in `ubuntu_common_packages.txt` confirmed available on Resolute
- `linux-generic-hwe-26.04` confirmed available as the Resolute HWE metapackage
- `packages.microsoft.com/ubuntu/26.04/prod` published day 1 (PowerShell not blocked)
- `download.docker.com/linux/ubuntu resolute` live day 1 (Docker not blocked)

## Scope

Items from backlog spec `2026-06-17-ubuntu-2604-support-design.md`:

- **P0-1** `detect_env.sh`: add `RESOLUTE=1` for 26.04
- **P0-2** `linux_ubuntu.sh`: branch HWE package install by version
- **P0-3** `ubuntu_2604_packages.txt`: new file
- **P0-4** `_install_ubuntu_base_packages`: version branch for package file selection
- **P2-1** `.zshrc.d/1_init.zsh`: add `RESOLUTE` export to shell detection

## Design

### Detection

**`lib/detect_env.sh`** — add after existing Noble check:

```bash
[[ ${UBUNTU_VERSION} = "24.04" ]] && readonly NOBLE=1
[[ ${UBUNTU_VERSION} = "26.04" ]] && readonly RESOLUTE=1
```

**`.config/.zshrc.d/1_init.zsh`** — add after existing Noble line, matching guard pattern:

```bash
[[ ${UBUNTU_VERSION} = "24.04" ]] && { [[ -n "${NOBLE+x}" ]] || readonly NOBLE=1; }
[[ ${UBUNTU_VERSION} = "26.04" ]] && { [[ -n "${RESOLUTE+x}" ]] || readonly RESOLUTE=1; }
```

`detect_env.sh` is setup context; `1_init.zsh` is interactive shell context. Both must stay in sync.

### Package Files

**`ubuntu_common_packages.txt`** — remove `silversearcher-ag` (dropped from Ubuntu 26.04 repos).

**`ubuntu_2404_packages.txt`** — add `silversearcher-ag` (keep available for Noble installs):

```
libbz2-dev
libgmp-dev
libffi-dev
libmpfr-dev
libreadline-dev
libssl-dev
libsqlite3-dev
liblzma-dev
linux-generic-hwe-24.04
neovim
silversearcher-ag
tree
```

**`ubuntu_2604_packages.txt`** — new file (clone of 2404 without `silversearcher-ag`, HWE updated):

```
libbz2-dev
libgmp-dev
libffi-dev
libmpfr-dev
libreadline-dev
libssl-dev
libsqlite3-dev
liblzma-dev
linux-generic-hwe-26.04
neovim
tree
```

### `_install_ubuntu_base_packages` Branch Logic

Replace flat Noble-only install with restored if/elif pattern:

```bash
_install_ubuntu_base_packages() {
  sudo -H apt update
  if [[ -n ${NOBLE} ]]; then
    printf "Installing hwe, common, and 24.04 packages\\n"
    sudo -H apt install --install-recommends linux-generic-hwe-24.04 -y
    check_and_install_nala
    xargs -a ./ubuntu_common_packages.txt sudo apt-get install -y
    xargs -a ./ubuntu_2404_packages.txt sudo apt-get install -y
  elif [[ -n ${RESOLUTE} ]]; then
    printf "Installing hwe, common, and 26.04 packages\\n"
    sudo -H apt install --install-recommends linux-generic-hwe-26.04 -y
    check_and_install_nala
    xargs -a ./ubuntu_common_packages.txt sudo apt-get install -y
    xargs -a ./ubuntu_2604_packages.txt sudo apt-get install -y
  else
    log_error "Unsupported Ubuntu version: ${UBUNTU_VERSION:-unknown}"
    return 1
  fi

  if [[ -n ${HAS_SNAP} ]]; then
    printf "Installing workstation packages\\n"
    xargs -a ./ubuntu_workstation_packages.txt sudo apt install -y
    printf "Installing workstation snap packages\\n"
    xargs -a ./ubuntu_workstation_snap_packages.txt sudo snap install
  fi
}
```

`check_and_install_nala` is inside each branch deliberately: when P1-1 (nala volian fix) lands,
the Resolute branch gets `apt install nala` directly while Noble keeps the volian path, with no
cross-contamination.

`HAS_SNAP` block stays outside — identical for both versions.

The `else` branch uses `log_error` + `return 1` to fail loudly on unsupported Ubuntu versions
rather than silently running Noble packages on an incompatible system.

### Tests

File: `tests/setup_env/linux_ubuntu.bats`

Existing tests at lines 20, 27, 34 of `linux_ubuntu.bats` run without any version var —
`load_setup_env` on macOS sets neither `NOBLE` nor `RESOLUTE`. With the new else-branch, all
three currently pass vacuously but will return 1 after this change. All three need
`export NOBLE=1` added to their test body.

1. **NOBLE hwe (regression guard)** — add `export NOBLE=1`; assert `linux-generic-hwe-24.04`
   install called, `ubuntu_2404_packages.txt` loaded via xargs; `[ "$status" -eq 0 ]`
2. **NOBLE HAS_SNAP (regression guard)** — add `export NOBLE=1`; existing snap assertion unchanged
3. **NOBLE no HAS_SNAP (regression guard)** — add `export NOBLE=1`; existing no-snap assertion unchanged
4. **RESOLUTE branch** — new test: `export RESOLUTE=1 NOBLE=` (explicitly unset Noble); assert
   `linux-generic-hwe-26.04` install called, `ubuntu_2604_packages.txt` loaded via xargs;
   `[ "$status" -eq 0 ]`
5. **Unsupported version** — new test: neither `NOBLE` nor `RESOLUTE` set; assert `[ "$status" -ne 0 ]`
   and output contains "Unsupported Ubuntu version"

All tests use PATH-injected mocks for `apt`, `apt-get`, `xargs`. Mock calls file asserted after
function returns.

## Files Changed

| File                                | Change                                                          |
| ----------------------------------- | --------------------------------------------------------------- |
| `lib/detect_env.sh`                 | +1 line: `RESOLUTE=1` for 26.04                                 |
| `.config/.zshrc.d/1_init.zsh`       | +1 line: `RESOLUTE` export with guard                           |
| `ubuntu_common_packages.txt`        | remove `silversearcher-ag`                                      |
| `ubuntu_2404_packages.txt`          | add `silversearcher-ag`                                         |
| `ubuntu_2604_packages.txt`          | new file                                                        |
| `lib/linux_ubuntu.sh`               | restore if/elif in `_install_ubuntu_base_packages` (~+12 lines) |
| `tests/setup_env/linux_ubuntu.bats` | 2 new tests + update existing Noble test                        |

## Acceptance Criteria

- `detect_env.sh` sets `RESOLUTE=1` when `UBUNTU_VERSION=26.04`
- `1_init.zsh` sets `RESOLUTE=1` when `UBUNTU_VERSION=26.04`
- Fresh Noble setup: installs `linux-generic-hwe-24.04`, loads `ubuntu_2404_packages.txt`
- Fresh Resolute setup: installs `linux-generic-hwe-26.04`, loads `ubuntu_2604_packages.txt`
- Unsupported version: `_install_ubuntu_base_packages` returns non-zero, logs error
- `make test` passes with ≥729 tests, coverage stays ≥90%
