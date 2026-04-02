#!/usr/bin/env bash
# lib/linux.sh — Linux-specific install and update functions

install_bats() {
  if quiet_which bats; then
    printf "bats already installed\\n"
    return 0
  fi

  printf "Installing bats\\n"

  if [[ -n ${UBUNTU} ]]; then
    sudo -H apt-get install -y bats
  elif [[ -n ${REDHAT} ]] || [[ -n ${CENTOS} ]] || [[ -n ${FEDORA} ]]; then
    curl -fsSL "https://github.com/bats-core/bats-core/archive/refs/tags/v${BATS_VER}.tar.gz" \
      -o /tmp/bats.tar.gz
    tar -xzf /tmp/bats.tar.gz -C /tmp
    sudo -H /tmp/bats-core-${BATS_VER}/install.sh /usr/local
    rm -rf /tmp/bats.tar.gz /tmp/bats-core-${BATS_VER}
  else
    printf "Unsupported platform for bats install\\n"
    return 1
  fi
}

update_system_packages() {
  if [[ -n ${UBUNTU} ]]; then
    sudo -H apt update
    if [[ -n ${FOCAL} ]]; then
      sudo -H apt autoremove -y
    elif [[ -n ${JAMMY} ]]; then
      check_and_install_nala
      sudo -H nala full-upgrade -y
      sudo -H nala autoremove -y
    elif [[ -n ${NOBLE} ]]; then
      check_and_install_nala
      sudo -H nala full-upgrade -y
      sudo -H nala autoremove -y
    fi
    sudo snap refresh
    printf "Updated snap packages\n"
  fi
  if [[ -n ${REDHAT} ]] || [[ -n ${FEDORA} ]]; then
    sudo -H dnf update -y
    printf "Updated dnf packages\n"
  fi
  if [[ -n ${CENTOS} ]]; then
    sudo -H yum update -y
    printf "Updated yum packages\n"
  fi
  if [[ -n ${MACOS} ]]; then
    printf "Updating mas packages\n"
    mas upgrade
  fi
}
