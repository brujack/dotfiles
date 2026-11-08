#!/usr/bin/env bash
# Verify packages-microsoft-prod.deb's debsig origin signature against the
# vendored Microsoft key before `dpkg -i` installs Microsoft's apt signing key
# as root. CI's powershell job calls this; setup_env.sh's own install path calls
# the same lib/linux_ubuntu.sh:_ms_verify_deb directly. The .deb is never
# sha256-pinned: Microsoft rewrites it in place per release, the signature does
# not change meaning.
#
# Usage: verify-ms-deb.sh <deb>
# Exit: 0 verified, 1 not verified (unreadable, unsigned, bad signature,
# unexpected members, gpg or ar missing), 2 usage.

_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly _REPO_ROOT

main() {
  if [[ $# -ne 1 ]]; then
    printf "usage: %s <deb>\n" "$(basename "$0")" >&2
    return 2
  fi
  local _deb="$1"
  # shellcheck source=lib/constants.sh
  source "${_REPO_ROOT}/lib/constants.sh" || return 1
  # shellcheck source=lib/helpers.sh
  source "${_REPO_ROOT}/lib/helpers.sh" || return 1
  # shellcheck source=lib/linux_ubuntu.sh
  source "${_REPO_ROOT}/lib/linux_ubuntu.sh" || return 1

  if [[ ! -f "${_deb}" || ! -r "${_deb}" ]]; then
    log_error "${_deb}: not a readable file"
    return 1
  fi
  _ms_verify_deb "${_deb}" || return 1
  printf "%s: signature verified against the Microsoft key %s\n" "$(basename "${_deb}")" "${MS_GPG_FPR}"
}

main "$@"
