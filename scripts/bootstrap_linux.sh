#!/usr/bin/env bash
# scripts/bootstrap_linux.sh
# Run once on a fresh Linux machine before setup_env.sh.
# Installs Homebrew prerequisites and Homebrew.

_bootstrap_check_linux() {
  if [[ $(uname -s) != "Linux" ]]; then
    printf "[ERROR] This script is Linux only.\n" >&2
    return 1
  fi
}

_bootstrap_linux_detect_distro() {
  local _osrel="${_BOOTSTRAP_OS_RELEASE:-/etc/os-release}"
  _DISTRO_FAMILY="unknown"

  if [[ -f "${_osrel}" ]]; then
    local ID="" ID_LIKE=""
    # shellcheck disable=SC1090 # path is variable — os-release or test fixture
    . "${_osrel}"
  fi

  if [[ "${ID:-}" == "ubuntu" ]] || [[ "${ID_LIKE:-}" == *"ubuntu"* ]]; then
    _DISTRO_FAMILY="ubuntu"
  elif [[ "${ID:-}" == "centos" ]] || [[ "${ID:-}" == "rhel" ]] || [[ "${ID_LIKE:-}" == *"rhel"* ]]; then
    _DISTRO_FAMILY="rhel"
  elif [[ "${ID:-}" == "fedora" ]] || [[ "${ID_LIKE:-}" == *"fedora"* ]]; then
    _DISTRO_FAMILY="fedora"
  fi
}

_bootstrap_linux_install_prereqs() {
  case "${_DISTRO_FAMILY}" in
    ubuntu)
      printf "[INFO]  Installing Homebrew prerequisites (Ubuntu)...\n"
      sudo apt-get update || return 1
      sudo apt-get install -y build-essential curl file git procps || return 1
      ;;
    fedora)
      printf "[INFO]  Installing Homebrew prerequisites (Fedora)...\n"
      sudo dnf groupinstall -y "Development Tools" || return 1
      sudo dnf install -y curl file git procps-ng || return 1
      ;;
    rhel)
      printf "[INFO]  Installing Homebrew prerequisites (RHEL/CentOS)...\n"
      sudo yum groupinstall -y "Development Tools" || return 1
      sudo yum install -y curl file git procps-ng || return 1
      ;;
    *)
      printf "[WARN]  Unknown distro. Ensure Homebrew prerequisites are installed: build tools, curl, file, git, procps.\n"
      ;;
  esac
}

_bootstrap_linux_install_homebrew() {
  if env which brew &>/dev/null; then
    printf "[INFO]  Homebrew already installed.\n"
    return 0
  fi
  printf "[INFO]  Installing Homebrew...\n"
  local _install_script
  _install_script=$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh) || return 1
  /bin/bash -c "${_install_script}"
}

_bootstrap_linux_setup_brew_path() {
  if [[ -x /home/linuxbrew/.linuxbrew/bin/brew ]]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
  fi
}

bootstrap_linux_main() {
  _bootstrap_check_linux || return 1
  _bootstrap_linux_detect_distro
  _bootstrap_linux_install_prereqs || { printf "[ERROR] Prerequisite installation failed.\n" >&2; return 1; }
  _bootstrap_linux_install_homebrew || { printf "[ERROR] Homebrew installation failed.\n" >&2; return 1; }
  _bootstrap_linux_setup_brew_path
  printf "[INFO]  Bootstrap complete. You can now run: ./setup_env.sh -t <type>\n"
}

# Allow sourcing for unit testing without executing
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0

bootstrap_linux_main
exit $?
