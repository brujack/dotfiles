#!/usr/bin/env bash
# Verify a downloaded GitHub release asset against its sha256 pin in
# lib/constants.sh before anything runs it. CI's secret-scan job calls this on
# the gitleaks tarball; any tool _release_asset_sha knows works.
#
# Usage: verify-release-asset.sh <tool> <amd64|arm64> <file>
# Exit: 0 verified, 1 not verified (pins recorded for another version, digest
# mismatch, unreadable file), 2 usage (wrong arguments, unknown tool or arch).
#
# The pins are refused unless <TOOL>_SHA256_FOR_VER equals <TOOL>_VER: a
# check-versions bump that skipped the refresh would otherwise compare a new
# download against the old version's digest, and report a mismatch that names
# the wrong cause.

_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly _REPO_ROOT

main() {
  if [[ $# -ne 3 ]]; then
    printf "usage: %s <tool> <amd64|arm64> <file>\n" "$(basename "$0")" >&2
    return 2
  fi
  local _tool="$1" _arch="$2" _file="$3"
  local _constants="${_REPO_ROOT}/lib/constants.sh"
  # bats-only seam, as in lib/workflows.sh:_refresh_pins_bin
  if [[ -n "${BATS_TEST_TMPDIR:-}" && -n "${_OVERRIDE_CONSTANTS_PATH:-}" ]]; then
    _constants="${_OVERRIDE_CONSTANTS_PATH}"
  fi
  # shellcheck source=/dev/null # the constants file is a runtime choice
  source "${_constants}" || return 1
  # shellcheck source=lib/helpers.sh
  source "${_REPO_ROOT}/lib/helpers.sh" || return 1
  # shellcheck source=lib/linux_ubuntu.sh
  source "${_REPO_ROOT}/lib/linux_ubuntu.sh" || return 1

  local _pin_line _var _pin _url
  if ! _pin_line="$(_release_asset_sha "${_tool}" "${_arch}")"; then
    printf "%s: no sha256 pin for %s %s\n" "$(basename "$0")" "${_tool}" "${_arch}" >&2
    return 2
  fi
  _var="${_pin_line%% *}"
  _pin="${_pin_line#* }"

  local _up="${_tool^^}"
  local _ver_var="${_up}_VER" _for_var="${_up}_SHA256_FOR_VER"
  if [[ -z "${!_ver_var:-}" || "${!_for_var:-}" != "${!_ver_var}" ]]; then
    printf "%s: %s is %s, not %s %s: run scripts/refresh-sha256-pins.sh %s and commit lib/constants.sh\n" \
      "${_tool}" "${_for_var}" "${!_for_var:-<unset>}" "${_ver_var}" "${!_ver_var:-<unset>}" "${_tool}" >&2
    return 1
  fi

  _url="$(_release_asset_url "${_tool}" "${_arch}")"
  _sha256_check "${_tool}" "${_file}" "${_var}" "${_pin}" "${_url}" "refusing to run it" || return 1
  printf "%s: %s verified against %s\n" "${_tool}" "${_file}" "${_var}"
}

main "$@"
