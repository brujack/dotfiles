#!/usr/bin/env bash
# lib/linux_shared.sh — Ubuntu Linux install functions (git, zsh, bats, updates)

_apt_pkg_installed() {
  dpkg-query -f '${db:Status-Abbrev}' -W "${1}" 2>/dev/null | grep -q '^ii'
}

install_git_linux() {
  # This guard answers "is git installed", not "is the PPA's newer git installed" —
  # it returns true for the distro package and skips the ppa:git-core/ppa step below.
  # Harmless while this function is unreachable (run_setup_user calls install_git only
  # under [[ -n ${MACOS} ]]). Adding a production Linux caller requires replacing this
  # with a version comparison first.
  if _apt_pkg_installed git; then
    log_info "git already installed"
    return 0
  fi

  log_info "Installing git via apt"
  sudo -H add-apt-repository ppa:git-core/ppa -y \
    || log_warn "PPA add failed — continuing with distro git"
  sudo -H apt update \
    || log_warn "apt update failed — package index may be stale"
  sudo -H apt install git -y \
    || { log_error "Failed to install git"; return 1; }
  log_info "Installed git"
}

install_zsh_linux() {
  if _apt_pkg_installed zsh && _apt_pkg_installed zsh-doc; then
    log_info "zsh already installed"
    return 0
  fi

  log_info "Installing zsh via apt"
  sudo -H apt update \
    || log_warn "apt update failed — package index may be stale"
  sudo -H apt install zsh zsh-doc -y \
    || { log_error "Failed to install zsh"; return 1; }
  log_info "Installed zsh"
}

install_bats_linux() {
  if quiet_which bats; then
    log_info "bats already installed"
    return 0
  fi

  log_info "Installing bats"
  sudo -H apt-get install -y bats
}

update_apt_packages() {
  sudo -H apt update || { log_error "apt update failed"; return 1; }
  check_and_install_nala || { log_error "nala install failed"; return 1; }
  sudo -H nala full-upgrade -y || { log_error "nala full-upgrade failed"; return 1; }
  sudo -H nala autoremove -y || { log_error "nala autoremove failed"; return 1; }
  log_info "Updated apt packages"
}

# Whether this host can refresh snaps. A named function rather than an inline
# `command -v snap`, so a test can override it directly.
#
# Tests must NOT try to hide snap by stripping PATH. On Ubuntu 24.04 — which is
# what ubuntu-latest runs — snap lives in /usr/bin alongside bash, grep, sed,
# awk, mktemp, cp and rm, so removing "the directory containing snap" removes
# the whole toolchain. That passed on macOS, where no /usr/bin/snap exists, and
# failed three tests in CI. Removing a directory to drop one binary is the same
# defect this branch already fixed once for tests/mocks; this seam removes the
# class rather than the instance.
_snap_available() {
  command -v snap > /dev/null 2>&1
}

update_snap_packages() {
  sudo snap refresh || { log_error "snap refresh failed"; return 1; }
  log_info "Updated snap packages"
}

# Wrapper retained so existing callers/tests that invoke the combined
# operation keep working. Runs both halves unconditionally — snap should
# still refresh even when apt fails — and reports failure if either did.
#
# It has NO production caller: run_update calls update_apt_packages and
# update_snap_packages directly so each gets its own summary row. The snap
# gate is duplicated here rather than left to the caller because this
# function's name makes it the obvious entry point for a future caller, and
# an ungated snap refresh on a host without snapd is the permanently-red
# summary row the split was written to remove. Both paths must agree.
update_system_packages() {
  local _rc=0
  update_apt_packages || _rc=1
  if _snap_available; then
    update_snap_packages || _rc=1
  else
    log_info "snap not installed on this host — skipping snap refresh"
  fi
  return "${_rc}"
}

[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0
