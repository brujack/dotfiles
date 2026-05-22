#!/usr/bin/env bash
# lib/linux_shared.sh — Ubuntu Linux install functions (git, zsh, bats, updates)

install_git_linux() {
  log_info "Installing git"
  log_info "Installing git via apt"
  sudo -H add-apt-repository ppa:git-core/ppa -y
  sudo -H apt update
  sudo -H apt dist-upgrade -y
  sudo -H apt install git -y
  log_info "Installed git"
}

install_zsh_linux() {
  log_info "Installing zsh"
  log_info "Installing zsh via apt"
  sudo -H apt update
  sudo -H apt dist-upgrade -y
  sudo -H apt install zsh zsh-doc -y
  log_info "Installed zsh"
}

install_bats() {
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
