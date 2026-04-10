#!/usr/bin/env bash

# Prerequisite check — runs only when executed directly (not sourced by tests)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  _OS="$(uname -s)"
  _BASH_MAJOR="${BASH_VERSINFO[0]:-0}"
  if [[ "${_BASH_MAJOR}" -lt 5 ]]; then
    printf "[ERROR] bash 5+ required (running bash %s).\n" "${BASH_VERSION}" >&2
    if [[ "${_OS}" == "Darwin" ]]; then
      printf "        On macOS, run first: ./scripts/bootstrap_mac.sh\n" >&2
    elif [[ "${_OS}" == "Linux" ]]; then
      printf "        On Linux, run first: ./scripts/bootstrap_linux.sh\n" >&2
    fi
    exit 1
  fi
  if ! which brew &>/dev/null; then
    printf "[ERROR] Homebrew not found.\n" >&2
    if [[ "${_OS}" == "Darwin" ]]; then
      printf "        On macOS, run first: ./scripts/bootstrap_mac.sh\n" >&2
    elif [[ "${_OS}" == "Linux" ]]; then
      printf "        On Linux, run first: ./scripts/bootstrap_linux.sh\n" >&2
    fi
    exit 1
  fi
  unset _OS
fi

source "$(dirname "${BASH_SOURCE[0]}")/lib/constants.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/helpers.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/detect_env.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/macos.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/linux.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/developer.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/workflows.sh"

# Allow sourcing for unit testing without executing the main script body
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0

[[ $# -eq 0 ]] && usage
process_args "$@"

detect_env

# Machine-local overrides (git-ignored, sourced if present)
_LOCAL_CFG="$(dirname "${BASH_SOURCE[0]}")/config/local.sh"
# shellcheck disable=SC1090 # path is variable by design — machine-local file
[[ -f "${_LOCAL_CFG}" ]] && source "${_LOCAL_CFG}"
unset _LOCAL_CFG

[[ -n ${DOCTOR:-} ]] && { run_doctor; exit $?; }
[[ -n ${CHECK_VERSIONS:-} ]] && { run_check_versions; exit $?; }

[[ -n ${SETUP_USER:-} ]] || [[ -n ${SETUP:-} ]] && run_setup_user
[[ -n ${SETUP:-} ]] || [[ -n ${DEVELOPER:-} ]] && run_setup_or_developer
[[ -n ${DEVELOPER:-} ]] || [[ -n ${ANSIBLE:-} ]] && run_developer_or_ansible
[[ -n ${UPDATE:-} ]] && run_update

/usr/bin/env zsh "${HOME}/.zshrc"
exit 0
