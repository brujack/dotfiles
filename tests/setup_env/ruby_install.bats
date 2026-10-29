#!/usr/bin/env bats
# Tests for install_ruby_tools (lib/developer.sh). ruby-install is built and
# installed as root, so the release tarball must match RUBY_INSTALL_SHA256
# before anything is extracted. tar, sha256sum and mktemp run for real on a
# fixture tarball; only the fetch and sudo are stubbed, by recording shims,
# never tests/mocks/sudo (it execs real commands).

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_setup_env
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  : > "${MOCK_CALLS_FILE}"
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${HOME}"
  export TMPDIR="${BATS_TEST_TMPDIR}/tmp"
  mkdir -p "${TMPDIR}"
  export LINUX=1
  unset MACOS

  RUBY_INSTALL_VER="9.9.9"
  RUBY_INSTALL_SHA256_FOR_VER="9.9.9"
  _fixture_tarball "ruby-install-${RUBY_INSTALL_VER}"
  RUBY_INSTALL_SHA256="$(sha256sum "${_TARBALL}" | awk '{print $1}')"

  _shim="${BATS_TEST_TMPDIR}/shim"
  mkdir -p "${_shim}"
  # Fetch stub: records argv and copies the fixture to the -o target, or
  # fails when MOCK_FETCH_EXIT is set.
  cat > "${_shim}/curl" << EOF
#!/usr/bin/env bash
printf 'fetch %s\n' "\$*" >> "${MOCK_CALLS_FILE}"
[[ -n "\${MOCK_FETCH_EXIT:-}" ]] && exit "\${MOCK_FETCH_EXIT}"
out=""
while [[ \$# -gt 0 ]]; do
  [[ "\$1" == "-o" ]] && { out="\$2"; shift; }
  shift
done
cp "\${MOCK_FETCH_FILE}" "\${out}"
EOF
  cat > "${_shim}/sudo" << EOF
#!/usr/bin/env bash
printf 'sudo %s\n' "\$*" >> "${MOCK_CALLS_FILE}"
exit "\${MOCK_SUDO_EXIT:-0}"
EOF
  chmod +x "${_shim}/curl" "${_shim}/sudo"
  export PATH="${_shim}:${PATH}"
  export MOCK_FETCH_FILE="${_TARBALL}"
}

# _fixture_tarball TOPDIR -- builds ${_TARBALL}, a .tar.gz holding TOPDIR/Makefile.
_fixture_tarball() {
  local _src="${BATS_TEST_TMPDIR}/src-$1"
  mkdir -p "${_src}/$1"
  printf 'install:\n\t@true\n' > "${_src}/$1/Makefile"
  _TARBALL="${BATS_TEST_TMPDIR}/$1.tar.gz"
  tar -czf "${_TARBALL}" -C "${_src}" "$1"
}

@test "install_ruby_tools: a verified release tarball is extracted and installed" {
  run install_ruby_tools
  [ "$status" -eq 0 ]
  [ -f "${HOME}/software_downloads/ruby-install-9.9.9/Makefile" ]
  # Built in two parts: makefile_lint_scope.bats reads a literal "make -C" in
  # test source as a make invocation it must classify.
  local _want="sudo make"
  _want+=" -C ${HOME}/software_downloads/ruby-install-9.9.9 install"
  command grep -qxF "${_want}" "${MOCK_CALLS_FILE}"
}

@test "install_ruby_tools: fetches the release asset over https only" {
  run install_ruby_tools
  [ "$status" -eq 0 ]
  command grep -qF -- "fetch --proto =https --proto-redir =https -fsSL -o " "${MOCK_CALLS_FILE}"
  command grep -qF "https://github.com/postmodern/ruby-install/releases/download/v9.9.9/ruby-install-9.9.9.tar.gz" "${MOCK_CALLS_FILE}"
}

@test "install_ruby_tools: a tarball that does not match the pin is neither extracted nor installed" {
  RUBY_INSTALL_SHA256="0000000000000000000000000000000000000000000000000000000000000000"
  run install_ruby_tools
  [ "$status" -eq 1 ]
  [[ "$output" == *"ruby-install: sha256 mismatch: RUBY_INSTALL_SHA256 expects 0000"* ]]
  [ ! -e "${HOME}/software_downloads/ruby-install-9.9.9" ]
  run ! command grep -q '^sudo ' "${MOCK_CALLS_FILE}"
}

@test "install_ruby_tools: a malformed pin fails before any download" {
  RUBY_INSTALL_SHA256="not-a-digest"
  run install_ruby_tools
  [ "$status" -eq 1 ]
  [[ "$output" == *"RUBY_INSTALL_SHA256 is not a sha256"* ]]
  run ! command grep -q '^fetch ' "${MOCK_CALLS_FILE}"
}

@test "install_ruby_tools: a pin recorded for another version fails before any download" {
  # shellcheck disable=SC2034 # read by lib/developer.sh:install_ruby_tools, called below
  RUBY_INSTALL_SHA256_FOR_VER="9.9.8"
  run install_ruby_tools
  [ "$status" -eq 1 ]
  [[ "$output" == *"RUBY_INSTALL_SHA256 is for 9.9.8, not 9.9.9"* ]]
  run ! command grep -q '^fetch ' "${MOCK_CALLS_FILE}"
}

@test "install_ruby_tools: a failed download installs nothing" {
  export MOCK_FETCH_EXIT=22
  run install_ruby_tools
  [ "$status" -eq 1 ]
  [[ "$output" == *"ruby-install: download failed"* ]]
  [ ! -e "${HOME}/software_downloads/ruby-install-9.9.9" ]
  run ! command grep -q '^sudo ' "${MOCK_CALLS_FILE}"
}

@test "install_ruby_tools: a verified tarball without the expected top directory installs nothing" {
  _fixture_tarball "something-else"
  export MOCK_FETCH_FILE="${_TARBALL}"
  RUBY_INSTALL_SHA256="$(sha256sum "${_TARBALL}" | awk '{print $1}')"
  run install_ruby_tools
  [ "$status" -eq 1 ]
  [[ "$output" == *"ruby-install: archive has no ruby-install-9.9.9/"* ]]
  [ ! -e "${HOME}/software_downloads/ruby-install-9.9.9" ]
  run ! command grep -q '^sudo ' "${MOCK_CALLS_FILE}"
}

@test "install_ruby_tools: a failing make install returns 1" {
  export MOCK_SUDO_EXIT=2
  run install_ruby_tools
  [ "$status" -eq 1 ]
  [[ "$output" == *"ruby-install: make install failed"* ]]
}

@test "install_ruby_tools: leaves no temporary files behind, on success or failure" {
  run install_ruby_tools
  [ "$status" -eq 0 ]
  # shellcheck disable=SC2034 # read by lib/developer.sh:install_ruby_tools, called below
  RUBY_INSTALL_SHA256="0000000000000000000000000000000000000000000000000000000000000000"
  rm -rf "${HOME}/software_downloads/ruby-install-9.9.9"
  run install_ruby_tools
  [ "$status" -eq 1 ]
  [ -z "$(ls -A "${TMPDIR}")" ]
}

@test "install_ruby_tools: does not change the caller's working directory" {
  cd "${BATS_TEST_TMPDIR}"
  install_ruby_tools
  [ "$PWD" = "${BATS_TEST_TMPDIR}" ]
}

@test "install_ruby_tools: an existing extracted tree skips the download" {
  mkdir -p "${HOME}/software_downloads/ruby-install-9.9.9"
  run install_ruby_tools
  [ "$status" -eq 0 ]
  run ! command grep -q '^fetch ' "${MOCK_CALLS_FILE}"
}

@test "install_ruby_tools: is a no-op on macOS" {
  export MACOS=1
  unset LINUX
  run install_ruby_tools
  [ "$status" -eq 0 ]
  run ! command grep -q . "${MOCK_CALLS_FILE}"
}
