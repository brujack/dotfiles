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
}

# The real gpg, resolved with the mocks directory stripped from PATH.
_real_gpg() {
  PATH="$(printf '%s' "${PATH}" | tr ':' '\n' | grep -v 'tests/mocks' | tr '\n' ':' | sed 's/:$//')" command -v gpg
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
  _assert_untouched
}

@test "_install_apt_keyring: armored conversion producing nothing fails on the -s check" {
  export MOCK_CURL_STDOUT="not a real key"
  # The gpg mock exits 0 and writes no -o file: only the non-empty check can fail it.
  export _MS_GPG_BIN="${REPO_ROOT}/tests/mocks/gpg"
  run _install_apt_keyring "${URL}" "${KEYRING}" armored
  [ "$status" -eq 1 ]
  grep -q '^curl ' "${MOCK_CALLS_FILE}"
  grep -q '^gpg ' "${MOCK_CALLS_FILE}"
  _assert_untouched
}

@test "_install_apt_keyring: rename failure leaves the keyring untouched and no .new" {
  export MOCK_CURL_STDOUT="binary-key-bytes"
  export MOCK_MV_FAIL_ARGS=".new"
  run _install_apt_keyring "${URL}" "${KEYRING}" binary
  [ "$status" -eq 1 ]
  grep -q '^mv ' "${MOCK_CALLS_FILE}"
  _assert_untouched
}

@test "_install_apt_keyring: armored success with real gpg replaces the keyring" {
  local _gpg
  _gpg="$(_real_gpg)" || skip "no real gpg"
  export _MS_GPG_BIN="${_gpg}"
  MOCK_CURL_STDOUT="$(cat "${REPO_ROOT}/keys/microsoft.asc")"
  export MOCK_CURL_STDOUT
  run _install_apt_keyring "${URL}" "${KEYRING}" armored
  [ "$status" -eq 0 ]
  grep -q '^curl ' "${MOCK_CALLS_FILE}"
  [ -s "${KEYRING}" ]
  [ "$(cat "${KEYRING}")" != "old" ]
  [ ! -e "${KEYRING}.new" ]
  [ -z "$(ls -A "${_APT_KEY_TMP_ROOT}")" ]
}

@test "_install_apt_keyring: binary success installs the fetched bytes" {
  export MOCK_CURL_STDOUT="binary-key-bytes"
  run _install_apt_keyring "${URL}" "${KEYRING}" binary
  [ "$status" -eq 0 ]
  grep -q '^curl ' "${MOCK_CALLS_FILE}"
  [ "$(cat "${KEYRING}")" = "binary-key-bytes" ]
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
