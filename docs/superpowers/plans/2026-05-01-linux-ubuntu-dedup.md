# linux_ubuntu.sh Deduplication — Implementation Plan

> **Status: DONE** — merged as PR #69

**Date:** 2026-05-01
**Spec:** [linux-ubuntu-dedup-design](../specs/2026-05-01-linux-ubuntu-dedup-design.md)
**Status:** Pending

## Goal

Eliminate copy-paste duplication in `lib/linux_ubuntu.sh` without changing behavior:

1. `_install_ubuntu_powershell` (54 lines → ~18): collapse 4x identical blocks into one
2. `_install_ubuntu_go` (178 lines → ~45): extract tarball helper + arithmetic version removal

All existing tests in `tests/setup_env/linux_ubuntu.bats` must pass unchanged.

## Pre-flight

```bash
make test   # must be green before touching anything
```

## Step 1 — Refactor `_install_ubuntu_powershell`

Replace lines 69–123 in `lib/linux_ubuntu.sh`. The four `if [[ -n ${BIONIC/FOCAL/JAMMY/NOBLE} ]]`
blocks are byte-for-byte identical. Collapse to one unconditional block:

```bash
_install_ubuntu_powershell() {
  printf "Installing powershell Ubuntu\n"
  if [[ ! -f ${HOME}/software_downloads/packages-microsoft-prod.deb ]]; then
    # shellcheck disable=SC2046
    wget -O ${HOME}/software_downloads/packages-microsoft-prod.deb \
      https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb
    sudo -H dpkg -i ${HOME}/software_downloads/packages-microsoft-prod.deb
    sudo apt update
    sudo -H add-apt-repository universe
    sudo -H apt install powershell -y
    if [[ -x $(command -v pwsh) ]]; then
      printf "pwsh is installed\n"
    fi
  fi
}
```

```bash
make test   # must pass
```

Commit:

```
refactor: collapse _install_ubuntu_powershell 4x copy-paste into single block
```

## Step 2 — Extract `_install_go_from_tarball`

Add this private helper immediately before `_install_ubuntu_go` (around line 125):

```bash
_install_go_from_tarball() {
  if [[ ! -f ${HOME}/software_downloads/${GO_DOWNLOAD_FILENAME} ]]; then
    wget -O ${HOME}/software_downloads/${GO_DOWNLOAD_FILENAME} ${GO_DOWNLOAD_URL}
    tar xvf ${HOME}/software_downloads/${GO_DOWNLOAD_FILENAME} -C ${HOME}/software_downloads/
    if [[ -d /usr/local/go ]]; then
      sudo rm -rf /usr/local/go
    fi
    if [[ -d ${HOME}/software_downloads/go ]]; then
      sudo mv ${HOME}/software_downloads/go /usr/local/go
      sudo chmod 755 /usr/local/go
      sudo chown -R root:root /usr/local/go
    fi
    if [[ -d ${HOME}/software_downloads/go ]]; then
      rm -rf ${HOME}/software_downloads/go
    fi
  fi
}
```

No callers yet — just the extracted helper. `make test` must pass unchanged.

## Step 3 — Refactor `_install_ubuntu_go`

Replace the body of `_install_ubuntu_go` (lines 125–302):

```bash
_install_ubuntu_go() {
  printf "Installing Go Ubuntu\n"
  local _minor
  _minor=$(printf '%s' "${GO_VER}" | cut -d. -f2)
  if [[ ${_minor} -lt 16 ]] || [[ ${_minor} -gt 26 ]]; then
    printf "Error: Unsupported Go version %s\n" "${GO_VER}"
    return 1
  fi
  sudo -H apt update
  local _prev_minor=$(( _minor - 1 ))
  local pkgs_to_remove="golang-1.${_prev_minor}-go golang-1.${_prev_minor}-src"
  if [[ -n ${pkgs_to_remove} ]]; then
    sudo -H apt remove ${pkgs_to_remove} -y
  fi
  if [[ ${GO_VER} < "1.21" ]]; then
    sudo add-apt-repository ppa:longsleep/golang-backports -y
    sudo -H apt install "golang-${GO_VER}-go" -y
  else
    _install_go_from_tarball
  fi
  INSTALLED_GO_VER=$(go version | awk '{print $3}' | sed 's/go//g')
  if [[ ${INSTALLED_GO_VER} == "${GO_VER}" ]]; then
    printf "Go %s is installed\n" "${GO_VER}"
  fi
}
```

```bash
make test   # must pass
```

Commit:

```
refactor: eliminate _install_ubuntu_go case duplication via extract method
```

## Verification

```bash
make test
```

All 4 existing `_install_ubuntu_go` tests and 4 existing `_install_ubuntu_powershell`
tests must pass. No new tests required — behavior is unchanged and existing tests
cover the paths exercised by the refactored code.

## Done criteria

- `make test` exits 0
- `_install_ubuntu_powershell`: ≤ 20 lines
- `_install_ubuntu_go` + `_install_go_from_tarball`: ≤ 55 lines combined (vs 178 before)
- Two commits on a feature branch, PR opened, CI passes, auto-merged
