#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_setup_env
  load_mocks
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  export MOCK_ID_U=1000
}

teardown() {
  rm -f "${MOCK_CALLS_FILE:-}"
}

# ── install_rosetta ──────────────────────────────────────────────────────────

@test "install_rosetta: Intel processor - no Rosetta needed" {
  export MOCK_SW_VERS_PRODUCTVERSION="12.0.0"
  export MOCK_SYSCTL_CPU="Intel(R) Core(TM) i9-9900K CPU"
  run install_rosetta
  [ "$status" -eq 0 ]
  [[ "$output" == *"No need to install Rosetta"* ]]
}

@test "install_rosetta: Apple Silicon, oahd already running" {
  export MOCK_SW_VERS_PRODUCTVERSION="12.0.0"
  export MOCK_SYSCTL_CPU="Apple M1"
  export MOCK_PGREP_EXIT=0
  run install_rosetta
  [ "$status" -eq 0 ]
  [[ "$output" == *"already installed and running"* ]]
}

@test "install_rosetta: Apple Silicon, installs when oahd absent" {
  export MOCK_SW_VERS_PRODUCTVERSION="12.0.0"
  export MOCK_SYSCTL_CPU="Apple M1"
  export MOCK_PGREP_EXIT=1
  export MOCK_PKGUTIL_EXIT=1
  export MOCK_SOFTWAREUPDATE_EXIT=0
  run install_rosetta
  [ "$status" -eq 0 ]
  grep -q "softwareupdate --install-rosetta" "${MOCK_CALLS_FILE}"
}

@test "install_rosetta: Apple Silicon, skips install when Rosetta package already present" {
  export MOCK_SW_VERS_PRODUCTVERSION="12.0.0"
  export MOCK_SYSCTL_CPU="Apple M1"
  export MOCK_PGREP_EXIT=1
  export MOCK_PKGUTIL_EXIT=0
  run install_rosetta
  [ "$status" -eq 0 ]
  ! grep -q "softwareupdate --install-rosetta" "${MOCK_CALLS_FILE}"
}

@test "install_rosetta: softwareupdate fails returns exit 1" {
  export MOCK_SW_VERS_PRODUCTVERSION="12.0.0"
  export MOCK_SYSCTL_CPU="Apple M1"
  export MOCK_PGREP_EXIT=1
  export MOCK_PKGUTIL_EXIT=1
  export MOCK_SOFTWAREUPDATE_EXIT=1
  run install_rosetta
  [ "$status" -eq 1 ]
}

@test "install_rosetta: macOS 10 - no Rosetta needed" {
  export MOCK_SW_VERS_PRODUCTVERSION="10.15.7"
  run install_rosetta
  [ "$status" -eq 0 ]
  [[ "$output" == *"No need to install Rosetta on this version"* ]]
}

# ── install_homebrew ─────────────────────────────────────────────────────────

@test "install_homebrew: xcode already installed, brew install succeeds" {
  export MOCK_UNAME_S=Darwin
  export MOCK_XCODE_SELECT_PRINT_PATH_EXIT=0
  export MOCK_CURL_STDOUT="true"
  run install_homebrew
  [ "$status" -eq 0 ]
  ! grep -q "xcode-select --install" "${MOCK_CALLS_FILE}"
}

@test "install_homebrew: xcode not installed, installs xcode then brew" {
  export MOCK_UNAME_S=Darwin
  export MOCK_XCODE_SELECT_PRINT_PATH_EXIT=1
  export MOCK_XCODE_SELECT_EXIT=0
  export MOCK_XCODEBUILD_EXIT=0
  export MOCK_CURL_STDOUT="true"
  run install_homebrew
  [ "$status" -eq 0 ]
  grep -q "xcode-select --install" "${MOCK_CALLS_FILE}"
}

@test "install_homebrew: curl failure returns exit 1" {
  export MOCK_UNAME_S=Darwin
  export MOCK_XCODE_SELECT_PRINT_PATH_EXIT=0
  export MOCK_CURL_EXIT=1
  run install_homebrew
  [ "$status" -eq 1 ]
}

# ── install_git_macos ────────────────────────────────────────────────────────

@test "install_git_macos: git already in brew list" {
  export MOCK_BREW_LIST_FORMULA="git wget"
  run install_git_macos
  [ "$status" -eq 0 ]
  [[ "$output" == *"already installed"* ]]
}

@test "install_git_macos: brew present, git not installed - installs via brew" {
  export MOCK_BREW_LIST_FORMULA=""
  run install_git_macos
  [ "$status" -eq 0 ]
  grep -q "brew install git" "${MOCK_CALLS_FILE}"
}

# ── install_zsh_macos ────────────────────────────────────────────────────────

@test "install_zsh_macos: zsh already in brew list" {
  export MOCK_BREW_LIST_FORMULA="zsh wget"
  run install_zsh_macos
  [ "$status" -eq 0 ]
  [[ "$output" == *"already installed"* ]]
}

@test "install_zsh_macos: brew present, zsh not installed - installs via brew" {
  export MOCK_BREW_LIST_FORMULA=""
  run install_zsh_macos
  [ "$status" -eq 0 ]
  grep -q "brew install zsh" "${MOCK_CALLS_FILE}"
}

# ── install_macos_casks ──────────────────────────────────────────────────────

@test "install_macos_casks: no GUI, no devtools - runs base Brewfile only" {
  export BREWFILE_LOC="${BATS_TEST_TMPDIR}/brew"
  export PERSONAL_GITREPOS="${BATS_TEST_TMPDIR}/git-repos/personal"
  export DOTFILES="dotfiles"
  mkdir -p "${BREWFILE_LOC}" "${PERSONAL_GITREPOS}/${DOTFILES}"
  touch "${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile.gui"
  touch "${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile.devtools"
  ln -sf "${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile.gui" "${BREWFILE_LOC}/Brewfile"
  unset HAS_GUI HAS_DEVTOOLS
  run install_macos_casks
  [ "$status" -eq 0 ]
}

@test "install_macos_casks: with HAS_GUI set - runs gui Brewfile" {
  export BREWFILE_LOC="${BATS_TEST_TMPDIR}/brew"
  export PERSONAL_GITREPOS="${BATS_TEST_TMPDIR}/git-repos/personal"
  export DOTFILES="dotfiles"
  mkdir -p "${BREWFILE_LOC}" "${PERSONAL_GITREPOS}/${DOTFILES}"
  touch "${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile.gui"
  touch "${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile.devtools"
  ln -sf "${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile.gui" "${BREWFILE_LOC}/Brewfile"
  export HAS_GUI=1
  run install_macos_casks
  [ "$status" -eq 0 ]
}

# ── install_homebrew (xcodebuild license failure) ────────────────────────────

@test "install_homebrew: xcodebuild fails after xcode install - returns 1 with license error" {
  export MOCK_UNAME_S=Darwin
  export MOCK_XCODE_SELECT_PRINT_PATH_EXIT=1
  export MOCK_XCODE_SELECT_EXIT=0
  export MOCK_XCODEBUILD_EXIT=1
  run install_homebrew
  [ "$status" -eq 1 ]
  [[ "$output" == *"Failed to accept Xcode license"* ]]
}

# ── install_git_macos / install_zsh_macos (no-brew error paths) ──────────────

@test "install_git_macos: brew absent after install_homebrew stub - returns error" {
  local _mocks="${BATS_TEST_DIRNAME}/../mocks"
  local _no_brew="${BATS_TEST_TMPDIR}/no-brew-bin"
  mkdir -p "${_no_brew}"
  for _f in "${_mocks}/"*; do
    [[ "$(basename "${_f}")" == "brew" ]] && continue
    cp "${_f}" "${_no_brew}/$(basename "${_f}")"
  done
  local _saved_path="${PATH}"
  export PATH="${_no_brew}:/usr/bin:/bin"
  install_homebrew() { return 0; }
  export -f install_homebrew
  local _rc=0
  local _out
  _out="$(install_git_macos 2>&1)" || _rc=$?
  export PATH="${_saved_path}"
  [ "${_rc}" -eq 1 ]
  [[ "${_out}" == *"Failed to install Homebrew. Cannot install Git."* ]]
}

@test "install_zsh_macos: brew absent after install_homebrew stub - returns error" {
  local _mocks="${BATS_TEST_DIRNAME}/../mocks"
  local _no_brew="${BATS_TEST_TMPDIR}/no-brew-bin"
  mkdir -p "${_no_brew}"
  for _f in "${_mocks}/"*; do
    [[ "$(basename "${_f}")" == "brew" ]] && continue
    cp "${_f}" "${_no_brew}/$(basename "${_f}")"
  done
  local _saved_path="${PATH}"
  export PATH="${_no_brew}:/usr/bin:/bin"
  install_homebrew() { return 0; }
  export -f install_homebrew
  local _rc=0
  local _out
  _out="$(install_zsh_macos 2>&1)" || _rc=$?
  export PATH="${_saved_path}"
  [ "${_rc}" -eq 1 ]
  [[ "${_out}" == *"Failed to install Homebrew. Cannot install zsh."* ]]
}

# ── install_macos_packages (no-brew path) ────────────────────────────────────

@test "install_macos_packages: brew absent, install_homebrew fails - returns 1" {
  export BREWFILE_LOC="${BATS_TEST_TMPDIR}/brew"
  export PERSONAL_GITREPOS="${BATS_TEST_TMPDIR}/git-repos/personal"
  export DOTFILES="dotfiles"
  mkdir -p "${BREWFILE_LOC}" "${PERSONAL_GITREPOS}/${DOTFILES}"
  touch "${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile"
  local _mocks="${BATS_TEST_DIRNAME}/../mocks"
  local _no_brew="${BATS_TEST_TMPDIR}/no-brew-bin"
  mkdir -p "${_no_brew}"
  for _f in "${_mocks}/"*; do
    [[ "$(basename "${_f}")" == "brew" ]] && continue
    cp "${_f}" "${_no_brew}/$(basename "${_f}")"
  done
  local _saved_path="${PATH}"
  export PATH="${_no_brew}:/usr/bin:/bin"
  install_homebrew() { return 1; }
  local _rc=0
  install_macos_packages 2>/dev/null || _rc=$?
  export PATH="${_saved_path}"
  [ "${_rc}" -eq 1 ]
}
