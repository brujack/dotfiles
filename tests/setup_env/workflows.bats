#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_mocks
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  touch "${MOCK_CALLS_FILE}"
  load_setup_env
  # Minimal env so workflow functions don't crash on missing vars
  export HOME="${BATS_TEST_TMPDIR}"
  export PERSONAL_GITREPOS="${BATS_TEST_TMPDIR}/git-repos/personal"
  export DOTFILES="dotfiles"
  export BREWFILE_LOC="${BATS_TEST_TMPDIR}/brew"
  mkdir -p "${PERSONAL_GITREPOS}/${DOTFILES}"
}

teardown() {
  :
}

# ── run_setup_user — coarse-grained (macOS) ───────────────────────────────────

@test "run_setup_user clones dotfiles repo on macOS when missing" {
  export MACOS=1
  unset LINUX UBUNTU REDHAT FEDORA CENTOS
  rm -rf "${PERSONAL_GITREPOS}/${DOTFILES}"
  run_setup_user
  grep -q "git clone" "${MOCK_CALLS_FILE}"
}

@test "run_setup_user creates HOME/bin on macOS" {
  export MACOS=1
  unset LINUX UBUNTU REDHAT FEDORA CENTOS
  run_setup_user
  [ -d "${HOME}/bin" ]
}

@test "run_setup_user creates HOME/go-work on macOS" {
  export MACOS=1
  unset LINUX UBUNTU REDHAT FEDORA CENTOS
  run_setup_user
  [ -d "${HOME}/go-work" ]
}

# ── run_setup_user — platform branching ───────────────────────────────────────

@test "run_setup_user calls install_rosetta on macOS" {
  export MACOS=1
  unset LINUX UBUNTU
  run_setup_user
  grep -q "rosetta" "${MOCK_CALLS_FILE}"
}

@test "run_setup_user does not call install_rosetta on Linux" {
  unset MACOS
  export LINUX=1
  export UBUNTU=1
  export NOBLE=1
  run_setup_user
  ! grep -q "rosetta" "${MOCK_CALLS_FILE}"
}

@test "run_setup_user calls install_bats on Linux when bats is missing" {
  unset MACOS
  export LINUX=1
  export UBUNTU=1
  export NOBLE=1
  export MOCK_WHICH_MISSING=bats
  run_setup_user
  grep -q "apt-get install -y bats" "${MOCK_CALLS_FILE}"
}

# ── run_setup_or_developer ────────────────────────────────────────────────────

@test "run_setup_or_developer creates credential directories" {
  export MACOS=1
  unset LINUX UBUNTU
  export SETUP=1
  run run_setup_or_developer
  [ -d "${HOME}/.aws" ]
}

@test "run_setup_or_developer calls brew update on macOS" {
  export MACOS=1
  unset LINUX UBUNTU
  export SETUP=1
  run run_setup_or_developer
  grep -q "brew update" "${MOCK_CALLS_FILE}"
}

@test "run_setup_or_developer calls apt-get on Ubuntu" {
  unset MACOS
  export LINUX=1
  export UBUNTU=1
  export NOBLE=1
  export SETUP=1
  run run_setup_or_developer
  grep -q "apt" "${MOCK_CALLS_FILE}"
}

@test "run_setup_or_developer does not call apt-get on macOS" {
  export MACOS=1
  unset LINUX UBUNTU
  export SETUP=1
  run run_setup_or_developer
  ! grep -q "apt-get install" "${MOCK_CALLS_FILE}"
}

# ── run_update — platform branching ───────────────────────────────────────────

@test "run_update calls brew update on macOS" {
  export MACOS=1
  unset LINUX UBUNTU
  unset UPDATE_BREW UPDATE_PIP UPDATE_GEMS UPDATE_MAS UPDATE_CLAUDE
  run_update
  grep -q "brew update" "${MOCK_CALLS_FILE}"
}

@test "run_update calls gem update with no flags" {
  export MACOS=1
  unset LINUX
  unset UPDATE_BREW UPDATE_PIP UPDATE_GEMS UPDATE_MAS UPDATE_CLAUDE
  run_update
  grep -q "gem update" "${MOCK_CALLS_FILE}"
}

@test "run_update calls apt on Ubuntu" {
  unset MACOS
  export LINUX=1
  export UBUNTU=1
  export NOBLE=1
  unset UPDATE_BREW UPDATE_PIP UPDATE_GEMS UPDATE_MAS UPDATE_CLAUDE
  run_update
  grep -q "apt" "${MOCK_CALLS_FILE}"
}

@test "run_update calls mas upgrade on macOS" {
  export MACOS=1
  unset LINUX UBUNTU
  export UPDATE_MAS=1
  unset UPDATE_BREW UPDATE_PIP UPDATE_GEMS UPDATE_CLAUDE
  run_update
  grep -q "mas upgrade" "${MOCK_CALLS_FILE}"
}

# ── run_brew_install ──────────────────────────────────────────────────────────

@test "run_brew_install creates Brewfile symlink at BREWFILE_LOC" {
  export MACOS=1
  unset LINUX UBUNTU HAS_GUI HAS_DEVTOOLS HAS_AWS HAS_K8S HAS_DOCKER HAS_RUST HAS_SNAP HAS_PRINTING
  touch "${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile"
  run run_brew_install
  [[ -L "${BREWFILE_LOC}/Brewfile" ]]
}

@test "run_brew_install returns 1 when install_homebrew fails" {
  export MACOS=1
  unset LINUX UBUNTU HAS_GUI HAS_DEVTOOLS HAS_AWS HAS_K8S HAS_DOCKER HAS_RUST HAS_SNAP HAS_PRINTING
  touch "${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile"
  export MOCK_WHICH_MISSING=brew
  export MOCK_CURL_EXIT=1
  export MOCK_UNAME_S="Darwin"
  run run_brew_install
  [ "$status" -eq 1 ]
}

@test "run_brew_install calls brew but skips install_macos_casks on Linux" {
  export LINUX=1
  unset MACOS
  export UBUNTU=1
  export NOBLE=1
  touch "${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile"
  run run_brew_install
  ! grep -q "brew bundle" "${MOCK_CALLS_FILE}"
}

# ── run_mas_install ───────────────────────────────────────────────────────────

@test "run_mas_install calls mas upgrade on macOS" {
  export MACOS=1
  unset LINUX UBUNTU
  run run_mas_install
  grep -q "mas upgrade" "${MOCK_CALLS_FILE}"
}

@test "run_mas_install is a no-op on Linux" {
  unset MACOS
  export LINUX=1
  export UBUNTU=1
  run run_mas_install
  [ "$status" -eq 0 ]
  ! grep -q "mas" "${MOCK_CALLS_FILE}"
}

@test "run_mas_install fails when mas is not installed" {
  export MACOS=1
  unset LINUX UBUNTU
  export MOCK_WHICH_MISSING=mas
  run run_mas_install
  [ "$status" -eq 1 ]
  [[ "$output" == *"mas not found"* ]]
}

# ── _update_version_pin ───────────────────────────────────────────────────────

setup_constants_copy() {
  # Creates a writable temp copy of lib/constants.sh for update tests
  _CONSTANTS_COPY="${BATS_TEST_TMPDIR}/constants.sh"
  cp "${REPO_ROOT}/lib/constants.sh" "${_CONSTANTS_COPY}"
  export _TEST_CONSTANTS_PATH="${_CONSTANTS_COPY}"
}

@test "_update_version_pin updates GO_VER in constants.sh" {
  setup_constants_copy
  export _OVERRIDE_CONSTANTS_PATH="${_TEST_CONSTANTS_PATH}"
  _update_version_pin "go" "GO_VER" "1.26" "1.27"
  grep -q 'GO_VER="1.27"' "${_TEST_CONSTANTS_PATH}"
}

@test "_update_version_pin does not modify other vars" {
  setup_constants_copy
  export _OVERRIDE_CONSTANTS_PATH="${_TEST_CONSTANTS_PATH}"
  _update_version_pin "go" "GO_VER" "1.26" "1.27"
  grep -q 'PYTHON_VER=' "${_TEST_CONSTANTS_PATH}"
  grep -q "PYTHON_VER=\"${PYTHON_VER}\"" "${_TEST_CONSTANTS_PATH}"
}

@test "_update_version_pin removes .bak file after update" {
  setup_constants_copy
  export _OVERRIDE_CONSTANTS_PATH="${_TEST_CONSTANTS_PATH}"
  _update_version_pin "go" "GO_VER" "1.26" "1.27"
  [[ ! -f "${_TEST_CONSTANTS_PATH}.bak" ]]
}

# ── _update_url_pins ──────────────────────────────────────────────────────────

@test "_update_url_pins updates GO_DOWNLOAD_FILENAME for go" {
  setup_constants_copy
  sed -i.bak 's|^GO_DOWNLOAD_FILENAME=.*|GO_DOWNLOAD_FILENAME="go1.26.1.linux-amd64.tar.gz"|' "${_TEST_CONSTANTS_PATH}"
  rm -f "${_TEST_CONSTANTS_PATH}.bak"
  _update_url_pins "go" "1.26" "1.27" "${_TEST_CONSTANTS_PATH}"
  grep -q 'go1.27' "${_TEST_CONSTANTS_PATH}"
}

@test "_update_url_pins updates GO_DOWNLOAD_URL for go" {
  setup_constants_copy
  sed -i.bak 's|^GO_DOWNLOAD_FILENAME=.*|GO_DOWNLOAD_FILENAME="go1.26.1.linux-amd64.tar.gz"|' "${_TEST_CONSTANTS_PATH}"
  rm -f "${_TEST_CONSTANTS_PATH}.bak"
  _update_url_pins "go" "1.26" "1.27" "${_TEST_CONSTANTS_PATH}"
  ! grep -q 'go1.26.1' "${_TEST_CONSTANTS_PATH}"
  grep -q 'go1.27' "${_TEST_CONSTANTS_PATH}"
}

@test "_update_url_pins updates YQ_URL for yq" {
  setup_constants_copy
  _update_url_pins "yq" "${YQ_VER}" "9.9.9" "${_TEST_CONSTANTS_PATH}"
  grep -q '/v9.9.9/' "${_TEST_CONSTANTS_PATH}"
}

@test "_update_url_pins leaves constants unchanged for vagrant" {
  setup_constants_copy
  cp "${_TEST_CONSTANTS_PATH}" "${BATS_TEST_TMPDIR}/constants_before.sh"
  _update_url_pins "vagrant" "2.4.9" "2.5.0" "${_TEST_CONSTANTS_PATH}"
  diff "${_TEST_CONSTANTS_PATH}" "${BATS_TEST_TMPDIR}/constants_before.sh"
}

@test "_update_url_pins leaves constants unchanged for shellcheck" {
  setup_constants_copy
  cp "${_TEST_CONSTANTS_PATH}" "${BATS_TEST_TMPDIR}/constants_before.sh"
  _update_url_pins "shellcheck" "${SHELLCHECK_VER}" "0.12.0" "${_TEST_CONSTANTS_PATH}"
  diff "${_TEST_CONSTANTS_PATH}" "${BATS_TEST_TMPDIR}/constants_before.sh"
}

# ── _prompt_version_update ────────────────────────────────────────────────────

@test "_prompt_version_update calls _update_version_pin on y reply" {
  setup_constants_copy
  export _OVERRIDE_CONSTANTS_PATH="${_TEST_CONSTANTS_PATH}"
  _prompt_version_update "go" "GO_VER" "1.26" "1.27" <<< "y"
  grep -q 'GO_VER="1.27"' "${_TEST_CONSTANTS_PATH}"
}

@test "_prompt_version_update skips update on n reply" {
  setup_constants_copy
  export _OVERRIDE_CONSTANTS_PATH="${_TEST_CONSTANTS_PATH}"
  _prompt_version_update "go" "GO_VER" "1.26" "1.27" <<< "n"
  grep -q 'GO_VER="1.26"' "${_TEST_CONSTANTS_PATH}"
}

@test "_prompt_version_update skips update on empty reply" {
  setup_constants_copy
  export _OVERRIDE_CONSTANTS_PATH="${_TEST_CONSTANTS_PATH}"
  _prompt_version_update "go" "GO_VER" "1.26" "1.27" <<< ""
  grep -q 'GO_VER="1.26"' "${_TEST_CONSTANTS_PATH}"
}
