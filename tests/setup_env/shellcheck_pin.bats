#!/usr/bin/env bats
# NOTE: shellcheck is pinned in two places that must agree: lib/constants.sh's
# SHELLCHECK_VER, which drives what the machines install, and ci.yml's SC_VER,
# which drives what the gate runs. Nothing else forces them equal, and a
# disagreement is invisible until a rule moves between releases and one side
# reports a finding the other does not.
#
# Measured 2026-09-18: workstation ran apt's 0.9.0 while claude (26.04), the
# Studio and CI all ran 0.11.0. 0.9.0 emits SC2154 for bats' `$stderr` where
# 0.11.0 does not, so `make test` failed there and the pre-push hook refused
# every source-touching push from that box.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_setup_env
}

@test "SHELLCHECK_VER matches ci.yml's SC_VER" {
  local _ci_ver
  _ci_ver="$(grep -oE 'SC_VER:[[:space:]]*"[0-9]+\.[0-9]+\.[0-9]+"' \
    "${REPO_ROOT}/.github/workflows/ci.yml" | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
  # A parse that silently returns empty would make this assertion vacuous --
  # "" != "0.11.0" would fail loudly, but "" == "" would not if the constant
  # ever went missing too. Pin both sides as non-empty first.
  [ -n "${_ci_ver}" ]
  [ -n "${SHELLCHECK_VER}" ]
  [ "${SHELLCHECK_VER}" = "${_ci_ver}" ]
}

@test "every ci.yml SC_VER occurrence agrees with the constant" {
  # ci.yml installs shellcheck in more than one job; a bump that edits one and
  # not the other is the same drift one level down.
  local _vers
  _vers="$(grep -oE 'SC_VER:[[:space:]]*"[0-9]+\.[0-9]+\.[0-9]+"' \
    "${REPO_ROOT}/.github/workflows/ci.yml" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | sort -u)"
  [ -n "${_vers}" ]
  [ "$(printf '%s\n' "${_vers}" | wc -l | tr -d ' ')" -eq 1 ]
  [ "${_vers}" = "${SHELLCHECK_VER}" ]
}

@test "shellcheck is not installed from apt" {
  # The apt package is whatever the distro ships, which is the whole defect
  # this pin exists to close. If it comes back to ubuntu_common_packages.txt,
  # a 24.04 box silently reverts to 0.9.0 and its pre-push hook starts failing.
  if grep -qx 'shellcheck' "${REPO_ROOT}/ubuntu_common_packages.txt"; then
    printf 'shellcheck is back in ubuntu_common_packages.txt; the pin is bypassed\n' >&2
    return 1
  fi
}

@test "both pinned shellcheck sha256 values are 64 hex chars" {
  # _install_pinned_release_binary fails closed on a malformed pin, but only at
  # install time on the affected arch. Catch a truncated paste here instead.
  [[ "${SHELLCHECK_SHA256_AMD64}" =~ ^[0-9a-f]{64}$ ]]
  [[ "${SHELLCHECK_SHA256_ARM64}" =~ ^[0-9a-f]{64}$ ]]
  [ "${SHELLCHECK_SHA256_AMD64}" != "${SHELLCHECK_SHA256_ARM64}" ]
}
