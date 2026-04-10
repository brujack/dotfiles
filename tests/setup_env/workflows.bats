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

@test "run_brew_install calls brew update" {
  export MACOS=1
  unset LINUX UBUNTU HAS_GUI HAS_DEVTOOLS
  touch "${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile"
  touch "${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile.gui"
  touch "${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile.devtools"
  run run_brew_install
  grep -q "brew update" "${MOCK_CALLS_FILE}"
}

@test "run_brew_install calls brew bundle" {
  export MACOS=1
  unset LINUX UBUNTU HAS_GUI HAS_DEVTOOLS
  touch "${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile"
  touch "${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile.gui"
  touch "${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile.devtools"
  run run_brew_install
  grep -q "brew bundle" "${MOCK_CALLS_FILE}"
}

@test "run_brew_install calls brew cleanup" {
  export MACOS=1
  unset LINUX UBUNTU HAS_GUI HAS_DEVTOOLS
  touch "${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile"
  touch "${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile.gui"
  touch "${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile.devtools"
  run run_brew_install
  grep -q "brew cleanup" "${MOCK_CALLS_FILE}"
}

@test "run_brew_install calls install_homebrew when brew is missing" {
  export MACOS=1
  unset LINUX UBUNTU HAS_GUI HAS_DEVTOOLS
  touch "${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile"
  touch "${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile.gui"
  touch "${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile.devtools"
  export MOCK_WHICH_MISSING=brew
  run run_brew_install
  grep -q "curl" "${MOCK_CALLS_FILE}"
}
