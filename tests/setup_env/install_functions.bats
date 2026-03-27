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

# ── install_git ──────────────────────────────────────────────────────────────

@test "install_git on macOS skips when git is already in brew list" {
  export MOCK_UNAME_S=Darwin
  export MACOS=1
  export MOCK_BREW_LIST_FORMULA="git"
  run install_git
  [ "$status" -eq 0 ]
  [[ "$output" == *"already installed"* ]]
  ! grep -q "brew install" "${MOCK_CALLS_FILE}"
}

@test "install_git on macOS calls brew install when git is absent" {
  export MOCK_UNAME_S=Darwin
  export MACOS=1
  export MOCK_BREW_LIST_FORMULA=""
  run install_git
  [ "$status" -eq 0 ]
  grep -q "brew install git" "${MOCK_CALLS_FILE}"
}

@test "install_git on Ubuntu calls apt install" {
  export MOCK_UNAME_S=Linux
  export MOCK_AWK_OS_NAME="Ubuntu"
  run install_git
  [ "$status" -eq 0 ]
  grep -q "apt install git" "${MOCK_CALLS_FILE}"
}

@test "install_git on CentOS calls yum install" {
  export MOCK_UNAME_S=Linux
  export MOCK_AWK_OS_NAME="CentOS Linux"
  run install_git
  [ "$status" -eq 0 ]
  grep -q "yum install git" "${MOCK_CALLS_FILE}"
}

@test "install_git on Fedora calls dnf install" {
  export MOCK_UNAME_S=Linux
  export MOCK_AWK_OS_NAME="Fedora"
  run install_git
  [ "$status" -eq 0 ]
  grep -q "dnf install git" "${MOCK_CALLS_FILE}"
}

# ── install_zsh ──────────────────────────────────────────────────────────────

@test "install_zsh on macOS skips when zsh is already in brew list" {
  export MOCK_UNAME_S=Darwin
  export MACOS=1
  export MOCK_BREW_LIST_FORMULA="zsh"
  run install_zsh
  [ "$status" -eq 0 ]
  [[ "$output" == *"already installed"* ]]
  ! grep -q "brew install" "${MOCK_CALLS_FILE}"
}

@test "install_zsh on macOS calls brew install when zsh is absent" {
  export MOCK_UNAME_S=Darwin
  export MACOS=1
  export MOCK_BREW_LIST_FORMULA=""
  run install_zsh
  [ "$status" -eq 0 ]
  grep -q "brew install zsh" "${MOCK_CALLS_FILE}"
}

@test "install_zsh on Ubuntu calls apt install" {
  export MOCK_UNAME_S=Linux
  export MOCK_AWK_OS_NAME="Ubuntu"
  run install_zsh
  [ "$status" -eq 0 ]
  grep -q "apt install zsh" "${MOCK_CALLS_FILE}"
}

@test "install_zsh on CentOS calls yum install" {
  export MOCK_UNAME_S=Linux
  export MOCK_AWK_OS_NAME="CentOS Linux"
  run install_zsh
  [ "$status" -eq 0 ]
  grep -q "yum install zsh" "${MOCK_CALLS_FILE}"
}

@test "install_zsh on Fedora calls dnf install" {
  export MOCK_UNAME_S=Linux
  export MOCK_AWK_OS_NAME="Fedora"
  run install_zsh
  [ "$status" -eq 0 ]
  grep -q "dnf install zsh" "${MOCK_CALLS_FILE}"
}
