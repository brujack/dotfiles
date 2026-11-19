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
  [[ "${stderr}" == *"reports uv 0.13.0 (exit 3), expected uv 0.13.0"* ]]
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

# ── installers (install_uv_pinned and its platform workers) ──────────────────
#
# curl is a per-test shim that logs its argv and copies a real uv-shaped
# .tar.gz to the -o target; sha256sum, tar and install stay real. HOME and
# _RELEASE_TMP_ROOT live under BATS_TEST_TMPDIR so nothing touches the real home.

# _install_fixture_setup: builds the archive, sets _UV_PINNED_SHA256 and puts
# the logging curl shim on PATH. Sets _CURL_LOG and _PINNED_DIR.
_install_fixture_setup() {
  local _payload="${BATS_TEST_TMPDIR}/payload/pkg" _tar="${BATS_TEST_TMPDIR}/uv-fixture.tar.gz"
  mkdir -p "${_payload}"
  printf '#!/usr/bin/env bash\nprintf "uv 0.13.0 (test)\\n"\n' > "${_payload}/uv"
  printf '#!/usr/bin/env bash\nprintf "uvx 0.13.0 (test)\\n"\n' > "${_payload}/uvx"
  chmod +x "${_payload}/uv" "${_payload}/uvx"
  (cd "${BATS_TEST_TMPDIR}/payload" && tar -czf "${_tar}" pkg)
  export _UV_PINNED_SHA256
  _UV_PINNED_SHA256="$(sha256sum "${_tar}" | awk '{print $1}')"
  _CURL_LOG="${BATS_TEST_TMPDIR}/curl.log"
  : > "${_CURL_LOG}"
  local _shim="${BATS_TEST_TMPDIR}/curl-shim"
  mkdir -p "${_shim}"
  cat > "${_shim}/curl" << SHIM
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${_CURL_LOG}"
out=""
while [[ \$# -gt 0 ]]; do
  if [[ "\$1" == "-o" ]]; then out="\$2"; shift 2; continue; fi
  shift
done
cp "${_tar}" "\${out}"
SHIM
  chmod +x "${_shim}/curl"
  export PATH="${_shim}:${PATH}"
  export _RELEASE_TMP_ROOT="${BATS_TEST_TMPDIR}/tmp-root"
  mkdir -p "${_RELEASE_TMP_ROOT}"
  _PINNED_DIR="${HOME}/.local/share/dotfiles/pinned/uv-0.13.0"
}

@test "install_uv_pinned: Linux x86_64 installs the versioned pinned uv" {
  _install_fixture_setup
  _OVERRIDE_PLATFORM=Linux _UNAME_M=x86_64 run -0 install_uv_pinned
  [ -x "${_PINNED_DIR}/uv" ]
  run "${_PINNED_DIR}/uv" --version
  [[ "${output}" == "uv 0.13.0 (test)" ]]
  grep -qF "uv-x86_64-unknown-linux-gnu.tar.gz" "${_CURL_LOG}"
  [ ! -e "${_PINNED_DIR}/uvx" ]
}

@test "install_uv_pinned: Darwin arm64 uses the aarch64-apple-darwin asset" {
  _install_fixture_setup
  _OVERRIDE_PLATFORM=Darwin _UNAME_M=arm64 run -0 install_uv_pinned
  [ -x "${_PINNED_DIR}/uv" ]
  grep -qF "uv-aarch64-apple-darwin.tar.gz" "${_CURL_LOG}"
}

@test "install_uv_pinned: Linux aarch64 warns, installs nothing and makes no curl call" {
  _install_fixture_setup
  _OVERRIDE_PLATFORM=Linux _UNAME_M=aarch64 run -0 install_uv_pinned
  [[ "${output}" == *"no pinned uv for Linux aarch64; skipping"* ]]
  [ ! -s "${_CURL_LOG}" ]
  [ ! -e "${_PINNED_DIR}" ]
}

@test "install_uv_pinned: Darwin x86_64 warns, installs nothing and makes no curl call" {
  _install_fixture_setup
  _OVERRIDE_PLATFORM=Darwin _UNAME_M=x86_64 run -0 install_uv_pinned
  [[ "${output}" == *"no pinned uv for Darwin x86_64; skipping"* ]]
  [ ! -s "${_CURL_LOG}" ]
  [ ! -e "${_PINNED_DIR}" ]
}

@test "install_uv_pinned: an unsupported OS warns and returns 0 without a curl call" {
  _install_fixture_setup
  _OVERRIDE_PLATFORM=FreeBSD _UNAME_M=x86_64 run -0 install_uv_pinned
  [[ "${output}" == *"FreeBSD"* ]]
  [ ! -s "${_CURL_LOG}" ]
}

@test "install_uv_pinned: a second run with the pinned version present makes no curl call" {
  _install_fixture_setup
  _OVERRIDE_PLATFORM=Linux _UNAME_M=x86_64 run -0 install_uv_pinned
  : > "${_CURL_LOG}"
  _OVERRIDE_PLATFORM=Linux _UNAME_M=x86_64 run -0 install_uv_pinned
  [[ "${output}" == *"uv 0.13.0 already installed"* ]]
  [ ! -s "${_CURL_LOG}" ]
}

@test "install_uv_pinned: a checksum mismatch returns 1 and installs nothing" {
  _install_fixture_setup
  export _UV_PINNED_SHA256="0000000000000000000000000000000000000000000000000000000000000000"
  _OVERRIDE_PLATFORM=Linux _UNAME_M=x86_64 run -1 install_uv_pinned
  [ ! -e "${_PINNED_DIR}/uv" ]
}

# Both platforms run the shared body; each is driven so a gate or leak in it is
# caught whichever entry point is mutated.
@test "install_uv_pinned: leaves _RELEASE_BIN_DIR unset in the caller's shell on Linux and Darwin" {
  local _pair _os _m
  for _pair in Linux:x86_64 Darwin:arm64; do
    _os="${_pair%%:*}" _m="${_pair##*:}"
    _install_fixture_setup
    unset _RELEASE_BIN_DIR
    rm -rf "${HOME}/.local"
    # shellcheck disable=SC2218 # the real function is sourced by load_setup_env; later tests redefine it as a stub
    _OVERRIDE_PLATFORM="${_os}" _UNAME_M="${_m}" install_uv_pinned
    [[ -z ${_RELEASE_BIN_DIR+x} ]]
    [ -x "${_PINNED_DIR}/uv" ]
  done
}

# ── call sites ───────────────────────────────────────────────────────────────

_stub_misc_steps() {
  _install_ubuntu_shellcheck() { :; }
  _install_ubuntu_tflint() { :; }
  _install_ubuntu_tfsec() { :; }
  _install_ubuntu_tfenv() { :; }
  check_and_install_nala() { :; }
  sudo() { :; }
  _install_ubuntu_uv_pinned() { printf 'UV_PINNED_CALLED\n'; }
}

@test "_install_ubuntu_misc: does not call _install_ubuntu_uv_pinned without HAS_DEVTOOLS" {
  _stub_misc_steps
  unset HAS_DEVTOOLS
  run -0 _install_ubuntu_misc
  [[ "${output}" != *"UV_PINNED_CALLED"* ]]
}

@test "_install_ubuntu_misc: calls _install_ubuntu_uv_pinned with HAS_DEVTOOLS and survives its failure" {
  _stub_misc_steps
  export HAS_DEVTOOLS=1
  _install_fetched_binary() { :; }
  run -0 _install_ubuntu_misc
  [[ "${output}" == *"UV_PINNED_CALLED"* ]]
  _install_ubuntu_uv_pinned() { return 1; }
  run -0 _install_ubuntu_misc
  [[ "${output}" == *"pinned uv install failed; skipping"* ]]
}

@test "run_brew_install: calls install_uv_pinned on macOS with HAS_DEVTOOLS, not without" {
  export MACOS=1
  export BREWFILE_LOC="${BATS_TEST_TMPDIR}/brewfile" PERSONAL_GITREPOS="${BATS_TEST_TMPDIR}" DOTFILES=d
  quiet_which() { return 0; }
  brew_update() { return 0; }
  brew_tap_if_missing() { return 0; }
  install_macos_casks() { return 0; }
  brew() { :; }
  install_uv_pinned() { printf 'UV_PINNED_CALLED\n'; }
  export HAS_DEVTOOLS=1
  run -0 run_brew_install
  [[ "${output}" == *"UV_PINNED_CALLED"* ]]
  unset HAS_DEVTOOLS
  run -0 run_brew_install
  [[ "${output}" != *"UV_PINNED_CALLED"* ]]
  install_uv_pinned() { return 1; }
  export HAS_DEVTOOLS=1
  run -0 run_brew_install
  [[ "${output}" == *"pinned uv install failed; skipping"* ]]
}

@test "install_macos_packages: calls install_uv_pinned with HAS_DEVTOOLS, not without, and survives its failure" {
  export BREWFILE_LOC="${BATS_TEST_TMPDIR}/brewfile" PERSONAL_GITREPOS="${BATS_TEST_TMPDIR}" DOTFILES=d
  mkdir -p "${BATS_TEST_TMPDIR}/fakebin" "${HOME}/scripts"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${BATS_TEST_TMPDIR}/fakebin/brew"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${HOME}/scripts/.osx.sh"
  chmod +x "${BATS_TEST_TMPDIR}/fakebin/brew" "${HOME}/scripts/.osx.sh"
  export PATH="${BATS_TEST_TMPDIR}/fakebin:${PATH}"
  brew_update() { return 0; }
  brew_tap_if_missing() { return 0; }
  install_macos_casks() { return 0; }
  sudo() { :; }
  install_uv_pinned() { printf 'UV_PINNED_CALLED\n'; }
  export HAS_DEVTOOLS=1
  run -0 install_macos_packages
  [[ "${output}" == *"UV_PINNED_CALLED"* ]]
  unset HAS_DEVTOOLS
  run -0 install_macos_packages
  [[ "${output}" != *"UV_PINNED_CALLED"* ]]
  install_uv_pinned() { return 1; }
  export HAS_DEVTOOLS=1
  run -0 install_macos_packages
  [[ "${output}" == *"pinned uv install failed; skipping"* ]]
}

@test "install_uv_pinned: the URL and digest overrides are ignored outside bats on Linux and Darwin" {
  local _row _os _m _asset
  for _row in Linux:x86_64:uv-x86_64-unknown-linux-gnu Darwin:arm64:uv-aarch64-apple-darwin; do
    IFS=: read -r _os _m _asset <<< "${_row}"
    _install_fixture_setup
    export _UV_PINNED_SHA256="${_UV_PINNED_SHA256}" _UV_PINNED_URL="https://example.invalid/evil.tar.gz"
    # Empty BATS_TEST_TMPDIR for the call only; the override digest matches the
    # fixture, so only the in-repo constants digest can refuse it.
    BATS_TEST_TMPDIR='' _OVERRIDE_PLATFORM="${_os}" _UNAME_M="${_m}" run -1 install_uv_pinned
    grep -qF "https://github.com/astral-sh/uv/releases/download/0.13.0/${_asset}.tar.gz" "${_CURL_LOG}"
    run ! grep -qF "evil.tar.gz" "${_CURL_LOG}"
    [ ! -e "${_PINNED_DIR}/uv" ]
  done
}
