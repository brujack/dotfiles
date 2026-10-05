#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

# _install_apt_keyring <url> <keyring> <armored|binary>: fetch to a file, convert
# into <keyring>.new, rename over <keyring>. A failure at any stage must leave the
# existing keyring untouched and no .new or throwaway directory behind.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_setup_env
  load_mocks
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  : > "${MOCK_CALLS_FILE}"
  # Setup scope: the throwaway dir and keyring live under the test tmpdir, so a
  # regression cannot reach the system temp dir or a real /usr/share/keyrings.
  export _APT_KEY_TMP_ROOT="${BATS_TEST_TMPDIR}/apt-key-tmp"
  mkdir -p "${_APT_KEY_TMP_ROOT}"
  KEYRING="${BATS_TEST_TMPDIR}/keyrings/test.gpg"
  mkdir -p "$(dirname "${KEYRING}")"
  printf 'old' > "${KEYRING}"
  URL="https://example.invalid/key"
  # Armored conversion runs unprivileged in the throwaway dir; the stub writes
  # its -o target, which tests/mocks/gpg does not.
  export _APT_KEY_GPG_BIN="${REPO_ROOT}/tests/mocks/gpg-dearmor"
}

# The real gpg, resolved with the mocks directory stripped from PATH.
_real_gpg() {
  PATH="$(printf '%s' "${PATH}" | tr ':' '\n' | grep -v 'tests/mocks' | tr '\n' ':' | sed 's/:$//')" command -v gpg
}

# Positive control for the "root is empty" assertions: the fetch really wrote
# under the throwaway root, so empty afterwards means cleaned, not never used.
_assert_tmp_was_used() {
  local _o
  _o="$(grep '^curl ' "${MOCK_CALLS_FILE}" | head -1 | sed -E 's/.* -o ([^ ]+) .*/\1/')"
  [[ "${_o}" == "${_APT_KEY_TMP_ROOT}/apt-key."* ]]
}

_assert_untouched() {
  [ "$(cat "${KEYRING}")" = "old" ]
  [ ! -e "${KEYRING}.new" ]
  [ -z "$(ls -A "${_APT_KEY_TMP_ROOT}")" ]
}

@test "_install_apt_keyring: fetch failure leaves the keyring untouched" {
  export MOCK_CURL_FAIL_URL="example.invalid"
  run _install_apt_keyring "${URL}" "${KEYRING}" armored
  [ "$status" -eq 1 ]
  grep -q '^curl ' "${MOCK_CALLS_FILE}"
  _assert_tmp_was_used
  _assert_untouched
}

@test "_install_apt_keyring: empty dearmor output fails on the -s check" {
  export MOCK_CURL_STDOUT="not a real key"
  export MOCK_GPG_DEARMOR_EMPTY=1
  run _install_apt_keyring "${URL}" "${KEYRING}" armored
  [ "$status" -eq 1 ]
  grep -q '^curl ' "${MOCK_CALLS_FILE}"
  grep -q '^gpg-dearmor ' "${MOCK_CALLS_FILE}"
  _assert_untouched
}

@test "_install_apt_keyring: conversion that writes then fails leaves the keyring untouched" {
  export MOCK_CURL_STDOUT="not a real key"
  export MOCK_GPG_DEARMOR_EXIT=2
  run _install_apt_keyring "${URL}" "${KEYRING}" armored
  [ "$status" -eq 1 ]
  grep -q '^gpg-dearmor ' "${MOCK_CALLS_FILE}"
  _assert_untouched
}

@test "_install_apt_keyring: a stale .new is removed even when conversion then fails" {
  export MOCK_CURL_STDOUT="not a real key"
  export MOCK_GPG_DEARMOR_EMPTY=1
  printf 'STALE' > "${KEYRING}.new"
  run _install_apt_keyring "${URL}" "${KEYRING}" armored
  [ "$status" -eq 1 ]
  grep -q '^gpg-dearmor ' "${MOCK_CALLS_FILE}"
  _assert_untouched
}

@test "_install_apt_keyring: a stale .new is removed even when the fetch fails" {
  export MOCK_CURL_FAIL_URL="example.invalid"
  printf 'STALE' > "${KEYRING}.new"
  run _install_apt_keyring "${URL}" "${KEYRING}" armored
  [ "$status" -eq 1 ]
  grep -q '^curl ' "${MOCK_CALLS_FILE}"
  _assert_untouched
}

@test "_install_apt_keyring: a stale .new never reaches the keyring on success" {
  export MOCK_CURL_STDOUT="not a real key"
  printf 'STALE' > "${KEYRING}.new"
  run _install_apt_keyring "${URL}" "${KEYRING}" armored
  [ "$status" -eq 0 ]
  [ "$(cat "${KEYRING}")" = "dearmored-test-keyring" ]
  [ ! -e "${KEYRING}.new" ]
}

@test "_install_apt_keyring: rename failure leaves the keyring untouched and no .new" {
  export MOCK_CURL_STDOUT="binary-key-bytes"
  export MOCK_MV_FAIL_ARGS=".new"
  run _install_apt_keyring "${URL}" "${KEYRING}" binary
  [ "$status" -eq 1 ]
  grep -q '^mv ' "${MOCK_CALLS_FILE}"
  _assert_untouched
}

@test "_install_apt_keyring: armored success with real gpg yields a readable binary keyring" {
  export _APT_KEY_GPG_BIN="${_REAL_GPG:-$(_real_gpg)}"
  _APT_KEY_GPG_BIN="${_APT_KEY_GPG_BIN:-/nonexistent/gpg}"
  MOCK_CURL_STDOUT="$(cat "${REPO_ROOT}/keys/microsoft.asc")"
  export MOCK_CURL_STDOUT
  run _install_apt_keyring "${URL}" "${KEYRING}" armored
  [ "$status" -eq 0 ]
  grep -q '^curl ' "${MOCK_CALLS_FILE}"
  [ -s "${KEYRING}" ]
  run ! grep -q 'BEGIN PGP' "${KEYRING}"
  local _home="${BATS_TEST_TMPDIR}/gnupg"
  mkdir -m 700 "${_home}"
  run "${_APT_KEY_GPG_BIN}" --homedir "${_home}" --show-keys --with-colons "${KEYRING}"
  [ "$status" -eq 0 ]
  [[ "${output}" == *"${MS_GPG_FPR}"* ]]
  if [[ "$(uname -s)" == "Darwin" ]]; then
    [ "$(stat -f %Lp "${KEYRING}")" = "644" ]
  else
    [ "$(stat -c %a "${KEYRING}")" = "644" ]
  fi
  [ ! -e "${KEYRING}.new" ]
  [ -z "$(ls -A "${_APT_KEY_TMP_ROOT}")" ]
}

@test "_install_apt_keyring: binary success installs the fetched bytes" {
  export MOCK_CURL_STDOUT="binary-key-bytes"
  run _install_apt_keyring "${URL}" "${KEYRING}" binary
  [ "$status" -eq 0 ]
  grep -q '^curl ' "${MOCK_CALLS_FILE}"
  [ "$(cat "${KEYRING}")" = "binary-key-bytes" ]
  _assert_tmp_was_used
  [ ! -e "${KEYRING}.new" ]
  [ -z "$(ls -A "${_APT_KEY_TMP_ROOT}")" ]
}

@test "_install_apt_keyring: unknown kind is rejected before any fetch" {
  run _install_apt_keyring "${URL}" "${KEYRING}" bogus
  [ "$status" -eq 1 ]
  run ! grep -q '^curl ' "${MOCK_CALLS_FILE}"
  _assert_untouched
}

@test "_install_apt_keyring: missing argument is rejected before any fetch" {
  run _install_apt_keyring "${URL}" "" armored
  [ "$status" -eq 1 ]
  run _install_apt_keyring "${URL}" "${KEYRING}"
  [ "$status" -eq 1 ]
  run ! grep -q '^curl ' "${MOCK_CALLS_FILE}"
  _assert_untouched
}

# _write_apt_source_list <step> <tool> <keyring> <list> <line>: a source signed-by
# a missing or empty keyring would break every later apt update, so it is written
# only when the keyring is a non-empty file.

@test "_write_apt_source_list: a zero-byte keyring writes no list and warns (no keyring)" {
  local _ring="${BATS_TEST_TMPDIR}/keyrings/empty.gpg" _list="${BATS_TEST_TMPDIR}/empty.list"
  : > "${_ring}"
  run _write_apt_source_list step tool "${_ring}" "${_list}" "deb http://example.invalid stable main"
  [ "$status" -eq 1 ]
  [[ "$output" == *"step: tool: source write skipped (no keyring)"* ]]
  [ ! -e "${_list}" ]
}

@test "_write_apt_source_list: a non-empty keyring writes the list" {
  local _list="${BATS_TEST_TMPDIR}/ok.list"
  run _write_apt_source_list step tool "${KEYRING}" "${_list}" "deb http://example.invalid stable main"
  [ "$status" -eq 0 ]
  [ "$(cat "${_list}")" = "deb http://example.invalid stable main" ]
}
