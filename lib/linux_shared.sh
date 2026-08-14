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

update_system_packages() {
  sudo -H apt update
  check_and_install_nala
  sudo -H nala full-upgrade -y
  sudo -H nala autoremove -y
  sudo snap refresh
  log_info "Updated snap packages"
}

[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0
