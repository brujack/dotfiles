#!/usr/bin/env bats
# Tests for lib/helpers.sh's _doctor_check_brew_links and the load_mocks brew
# defaults it depends on (_BREW_BIN, _BREW_FALLBACK_PATHS).
# Spec: docs/superpowers/specs/2026-10-20-doctor-brew-links-design.md

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_setup_env
  load_mocks
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  HOME="${BATS_TEST_TMPDIR}/home"
  export HOME
  mkdir -p "${HOME}"
}

@test "load_mocks: _BREW_BIN is an executable stub under BATS_TEST_TMPDIR" {
  [[ -x "${_BREW_BIN}" ]]
  [[ "${_BREW_BIN}" == "${BATS_TEST_TMPDIR}"/* ]]
}

@test "load_mocks: the _BREW_BIN stub exits 0, prints nothing, logs argv under BATS_TEST_TMPDIR" {
  run "${_BREW_BIN}" doctor x
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  grep -qx 'doctor x' "${BATS_TEST_TMPDIR}/brew-calls"
}

@test "load_mocks: _BREW_FALLBACK_PATHS names only a missing path under BATS_TEST_TMPDIR" {
  [ "${_BREW_FALLBACK_PATHS}" = "${BATS_TEST_TMPDIR}/no-brew" ]
  [[ ! -e "${_BREW_FALLBACK_PATHS}" ]]
}

@test "load_mocks: _BREW_BIN and _BREW_FALLBACK_PATHS are exported" {
  run bash -c 'printf "%s|%s" "${_BREW_BIN}" "${_BREW_FALLBACK_PATHS}"'
  [ "${status}" -eq 0 ]
  [ -n "${_BREW_BIN}" ]
  [ -n "${_BREW_FALLBACK_PATHS}" ]
  [ "${output}" = "${_BREW_BIN}|${_BREW_FALLBACK_PATHS}" ]
}
