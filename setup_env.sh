#!/usr/bin/env bash

# Prerequisite check — runs only when executed directly (not sourced by tests)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  _OS="$(uname -s)"
  _BASH_MAJOR="${BASH_VERSINFO[0]:-0}"
  _REQUIRES_BREW_PREREQ=1

  # Allow workflows that can run before Homebrew exists.
  local_prev=""
  for _arg in "$@"; do
    if [[ "${local_prev}" == "-t" ]] && [[ "${_arg}" == "doctor" || "${_arg}" == "check-versions" ]]; then
      _REQUIRES_BREW_PREREQ=0
      break
    fi
    [[ "${_arg}" == "--brew-install" ]] && { _REQUIRES_BREW_PREREQ=0; break; }
    local_prev="${_arg}"
  done

  if [[ "${_BASH_MAJOR}" -lt 5 ]]; then
    printf "[ERROR] bash 5+ required (running bash %s).\n" "${BASH_VERSION}" >&2
    if [[ "${_OS}" == "Darwin" ]]; then
      printf "        On macOS, run first: ./scripts/bootstrap_mac.sh\n" >&2
    elif [[ "${_OS}" == "Linux" ]]; then
      printf "        On Linux, run first: ./scripts/bootstrap_linux.sh\n" >&2
    fi
    exit 1
  fi
  # Use env which (not command -v) so BATS mocks/tests can shadow PATH which.
  if [[ ${_REQUIRES_BREW_PREREQ} -eq 1 ]] && ! env which brew &>/dev/null; then
    printf "[ERROR] Homebrew not found.\n" >&2
    if [[ "${_OS}" == "Darwin" ]]; then
      printf "        On macOS, run first: ./scripts/bootstrap_mac.sh\n" >&2
    elif [[ "${_OS}" == "Linux" ]]; then
      printf "        On Linux, run first: ./scripts/bootstrap_linux.sh\n" >&2
    fi
    exit 1
  fi
  unset _OS _REQUIRES_BREW_PREREQ local_prev
fi

source "$(dirname "${BASH_SOURCE[0]}")/lib/constants.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/helpers.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/detect_env.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/macos.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/linux_shared.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/linux_ubuntu.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/linux_rhel.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/developer.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/update_summary.sh"
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

# Fail-fast strict runner: exit immediately on the first failed selected step.
_run_or_exit() {
  "$@"
  local _ec=$?
  [[ ${_ec} -eq 0 ]] || exit "${_ec}"
}

[[ -n ${SETUP_BREW:-} ]] && _run_or_exit run_brew_install
[[ -n ${SETUP_MAS:-} ]]  && _run_or_exit run_mas_install
[[ -n ${SETUP_BREW:-} || -n ${SETUP_MAS:-} ]] && exit 0

[[ -n ${SETUP_USER:-} || -n ${SETUP:-} ]] && _run_or_exit run_setup_user
[[ -n ${SETUP:-} || -n ${DEVELOPER:-} ]] && _run_or_exit run_setup_or_developer
[[ -n ${DEVELOPER:-} || -n ${ANSIBLE:-} ]] && _run_or_exit run_developer_or_ansible
[[ -n ${UPDATE:-} ]] && _run_or_exit run_update

exit 0
