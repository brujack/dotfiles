#!/usr/bin/env bash
# scripts/bootstrap_mac.sh
# Run once on a fresh Mac before setup_env.sh.
# Installs Homebrew and bash 5 — the only two prerequisites for setup_env.sh.

_bootstrap_check_macos() {
  if [[ $(uname -s) != "Darwin" ]]; then
    printf "[ERROR] This script is macOS only.\n" >&2
    return 1
  fi
}

_bootstrap_mac_install_homebrew() {
  if env which brew &>/dev/null; then
    printf "[INFO]  Homebrew already installed.\n"
    return 0
  fi
  printf "[INFO]  Installing Homebrew...\n"
  local _script
  _script=$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh) || return 1
  /bin/bash -c "${_script}"
}

_bootstrap_mac_setup_brew_path() {
  if [[ -f /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
}

_bootstrap_mac_install_bash5() {
  local _ver
  _ver=$("${BASH:-bash}" --version | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  local _major="${_ver%%.*}"
  if [[ "${_major:-0}" -ge 5 ]]; then
    printf "[INFO]  bash 5 already installed (version %s).\n" "${_ver}"
    return 0
  fi
  printf "[INFO]  Installing bash 5...\n"
  brew install bash
}

bootstrap_mac_main() {
  _bootstrap_check_macos || return 1
  _bootstrap_mac_install_homebrew || { printf "[ERROR] Homebrew installation failed.\n" >&2; return 1; }
  _bootstrap_mac_setup_brew_path
  _bootstrap_mac_install_bash5 || { printf "[ERROR] bash 5 installation failed.\n" >&2; return 1; }
  printf "[INFO]  Bootstrap complete. You can now run: ./setup_env.sh -t <type>\n"
}

# Allow sourcing for unit testing without executing
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0

bootstrap_mac_main
exit $?
