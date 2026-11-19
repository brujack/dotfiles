#!/usr/bin/env bats
# Tests for resolve_pinned_uv, _uv_pinned_version_regex and _uv_pinned_asset
# (lib/helpers.sh). The resolver reads only the pinned path (or the
# PINNED_UV_BIN override), never PATH; stubs are per-test scripts under
# BATS_TEST_TMPDIR and HOME is redirected so nothing touches the real home.

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_setup_env
  export HOME="${BATS_TEST_TMPDIR}"
  unset PINNED_UV_BIN
}

# _make_stub <path> <version-line>: executable script printing the given line.
_make_stub() {
  mkdir -p "$(dirname "${1}")"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "%s"\n' "${2}" > "${1}"
  chmod +x "${1}"
}

@test "resolve_pinned_uv: absent file returns 2 with the remedy" {
  export PINNED_UV_BIN="${BATS_TEST_TMPDIR}/nope/uv"
  run -2 --separate-stderr resolve_pinned_uv
  [[ "${stderr}" == *"pinned uv not found at ${PINNED_UV_BIN}; run make install-pinned-uv"* ]]
  [[ -z "${output}" ]]
}

@test "resolve_pinned_uv: non-executable file returns 1" {
  export PINNED_UV_BIN="${BATS_TEST_TMPDIR}/uv"
  printf '#!/bin/sh\n' > "${PINNED_UV_BIN}"
  chmod -x "${PINNED_UV_BIN}"
  run -1 --separate-stderr resolve_pinned_uv
  [[ "${stderr}" == *"pinned uv at ${PINNED_UV_BIN} is not executable"* ]]
  [[ -z "${output}" ]]
}

@test "resolve_pinned_uv: wrong version returns 1 naming both versions" {
  export PINNED_UV_BIN="${BATS_TEST_TMPDIR}/uv"
  _make_stub "${PINNED_UV_BIN}" "uv 0.13.9"
  run -1 --separate-stderr resolve_pinned_uv
  [[ "${stderr}" == *"pinned uv at ${PINNED_UV_BIN} reports uv 0.13.9, expected uv 0.13.0"* ]]
  [[ -z "${output}" ]]
}

@test "resolve_pinned_uv: rejects uv 0.13.01" {
  export PINNED_UV_BIN="${BATS_TEST_TMPDIR}/uv"
  _make_stub "${PINNED_UV_BIN}" "uv 0.13.01"
  run -1 --separate-stderr resolve_pinned_uv
  [[ "${stderr}" == *"reports uv 0.13.01"* ]]
  [[ -z "${output}" ]]
}

@test "resolve_pinned_uv: empty UV_VER returns 1" {
  export PINNED_UV_BIN="${BATS_TEST_TMPDIR}/uv"
  _make_stub "${PINNED_UV_BIN}" "uv 0.13.0"
  # shellcheck disable=SC2034 # read by resolve_pinned_uv and _uv_pinned_version_regex in lib/helpers.sh
  UV_VER=""
  run -1 --separate-stderr resolve_pinned_uv
  [[ "${stderr}" == *"UV_VER is not set; source lib/constants.sh"* ]]
}

@test "resolve_pinned_uv: matching version prints exactly the path" {
  export PINNED_UV_BIN="${BATS_TEST_TMPDIR}/uv"
  _make_stub "${PINNED_UV_BIN}" "uv 0.13.0 (x86_64-unknown-linux-gnu)"
  run -0 resolve_pinned_uv
  [[ "${output}" == "${PINNED_UV_BIN}" ]]
}

@test "resolve_pinned_uv: default path is under HOME when PINNED_UV_BIN is unset" {
  local _p="${HOME}/.local/share/dotfiles/pinned/uv-0.13.0/uv"
  _make_stub "${_p}" "uv 0.13.0 (x)"
  run -0 resolve_pinned_uv
  [[ "${output}" == "${_p}" ]]
}

@test "resolve_pinned_uv: never consults PATH" {
  local _bin="${BATS_TEST_TMPDIR}/pathbin"
  _make_stub "${_bin}/uv" "uv 0.13.0"
  PATH="${_bin}:${PATH}" run -2 --separate-stderr resolve_pinned_uv
  [[ "${stderr}" == *"not found at ${HOME}/.local/share/dotfiles/pinned/uv-0.13.0/uv"* ]]
}

@test "_uv_pinned_version_regex: prints the anchored escaped pattern" {
  run -0 _uv_pinned_version_regex
  [[ "${output}" == '^uv 0\.13\.0( |$)' ]]
}

@test "_uv_pinned_asset: Linux x86_64" {
  run -0 _uv_pinned_asset Linux x86_64
  [[ "${output}" == "uv-x86_64-unknown-linux-gnu 1468ebd5a5541121837c5a2817b9972ba6090fa6caa3d142620850a47fb75154" ]]
}

@test "_uv_pinned_asset: Darwin arm64" {
  run -0 _uv_pinned_asset Darwin arm64
  [[ "${output}" == "uv-aarch64-apple-darwin a9c1b29002cf3c83f07fa9cd8a887a3be0107d90e23189721221e7257db8e3d6" ]]
}

@test "_uv_pinned_asset: unsupported platforms return 1 with empty stdout" {
  run -1 --separate-stderr _uv_pinned_asset Linux aarch64
  [[ -z "${output}" ]]
  run -1 --separate-stderr _uv_pinned_asset Darwin x86_64
  [[ -z "${output}" ]]
}

@test "_uv_pinned_version_regex: derives the pattern from UV_VER" {
  # shellcheck disable=SC2034 # read by _uv_pinned_version_regex in lib/helpers.sh
  UV_VER="1.2.3"
  run -0 _uv_pinned_version_regex
  [[ "${output}" == '^uv 1\.2\.3( |$)' ]]
}

@test "resolve_pinned_uv: follows UV_VER, accepting its version and rejecting 0.13.0" {
  # shellcheck disable=SC2034 # read by resolve_pinned_uv in lib/helpers.sh
  UV_VER="1.2.3"
  export PINNED_UV_BIN="${BATS_TEST_TMPDIR}/uv"
  _make_stub "${PINNED_UV_BIN}" "uv 1.2.3"
  run -0 resolve_pinned_uv
  _make_stub "${PINNED_UV_BIN}" "uv 0.13.0"
  run -1 --separate-stderr resolve_pinned_uv
  [[ "${stderr}" == *"reports uv 0.13.0, expected uv 1.2.3"* ]]
}

@test "resolve_pinned_uv: a directory at the path is not executable" {
  export PINNED_UV_BIN="${BATS_TEST_TMPDIR}/adir"
  mkdir -p "${PINNED_UV_BIN}"
  run -1 --separate-stderr resolve_pinned_uv
  [[ "${stderr}" == *"pinned uv at ${PINNED_UV_BIN} is not executable"* ]]
}

@test "resolve_pinned_uv: a stub printing nothing reports (no output)" {
  export PINNED_UV_BIN="${BATS_TEST_TMPDIR}/uv"
  printf '#!/usr/bin/env bash\n' > "${PINNED_UV_BIN}"
  chmod +x "${PINNED_UV_BIN}"
  run -1 --separate-stderr resolve_pinned_uv
  [[ "${stderr}" == *"reports (no output), expected uv 0.13.0"* ]]
}

@test "resolve_pinned_uv: right version but non-zero exit is a mismatch" {
  export PINNED_UV_BIN="${BATS_TEST_TMPDIR}/uv"
  printf '#!/usr/bin/env bash\nprintf "uv 0.13.0\\n"\nexit 3\n' > "${PINNED_UV_BIN}"
  chmod +x "${PINNED_UV_BIN}"
  run -1 --separate-stderr resolve_pinned_uv
  [[ "${stderr}" == *"reports uv 0.13.0, expected uv 0.13.0"* ]]
}

@test "resolve_pinned_uv: rejects uv 0.13.0.1" {
  export PINNED_UV_BIN="${BATS_TEST_TMPDIR}/uv"
  _make_stub "${PINNED_UV_BIN}" "uv 0.13.0.1"
  run -1 --separate-stderr resolve_pinned_uv
  [[ "${stderr}" == *"reports uv 0.13.0.1"* ]]
}

@test "resolve_pinned_uv: unset UV_VER returns 1" {
  export PINNED_UV_BIN="${BATS_TEST_TMPDIR}/uv"
  _make_stub "${PINNED_UV_BIN}" "uv 0.13.0"
  unset UV_VER
  run -1 --separate-stderr resolve_pinned_uv
  [[ "${stderr}" == *"UV_VER is not set; source lib/constants.sh"* ]]
}
