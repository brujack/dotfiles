#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_setup_env
  load_mocks
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  export MOCK_ID_U=1000
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${HOME}/software_downloads"
}

teardown() {
  rm -f "${MOCK_CALLS_FILE:-}"
}

# ── install_git_linux ────────────────────────────────────────────────────────

@test "install_git_linux: CentOS path calls yum install git" {
  export MOCK_AWK_OS_NAME="CentOS Linux"
  run install_git_linux
  [ "$status" -eq 0 ]
  grep -q "yum install git" "${MOCK_CALLS_FILE}"
}

@test "install_git_linux: Fedora path calls dnf install git" {
  export MOCK_AWK_OS_NAME="Fedora"
  run install_git_linux
  [ "$status" -eq 0 ]
  grep -q "dnf install git" "${MOCK_CALLS_FILE}"
}

# ── install_zsh_linux ────────────────────────────────────────────────────────

@test "install_zsh_linux: CentOS path calls yum install zsh" {
  export MOCK_AWK_OS_NAME="CentOS Linux"
  run install_zsh_linux
  [ "$status" -eq 0 ]
  grep -q "yum install zsh" "${MOCK_CALLS_FILE}"
}

@test "install_zsh_linux: Fedora path calls dnf install zsh" {
  export MOCK_AWK_OS_NAME="Fedora"
  run install_zsh_linux
  [ "$status" -eq 0 ]
  grep -q "dnf install zsh" "${MOCK_CALLS_FILE}"
}

# ── update_system_packages — Noble and Fedora paths ─────────────────────────

@test "update_system_packages: UBUNTU+NOBLE calls nala full-upgrade" {
  export UBUNTU=1
  export NOBLE=1
  unset FOCAL JAMMY REDHAT CENTOS FEDORA
  run update_system_packages
  [ "$status" -eq 0 ]
  grep -q "nala full-upgrade" "${MOCK_CALLS_FILE}"
}

@test "update_system_packages: FEDORA calls dnf update" {
  export FEDORA=1
  unset UBUNTU REDHAT CENTOS FOCAL JAMMY NOBLE
  run update_system_packages
  [ "$status" -eq 0 ]
  grep -q "dnf update" "${MOCK_CALLS_FILE}"
}

# ── setup_vim_plugins ────────────────────────────────────────────────────────

@test "setup_vim_plugins: creates .vim/plugged and .vim/autoload directories" {
  run setup_vim_plugins
  [ "$status" -eq 0 ]
  [ -d "${HOME}/.vim/plugged" ]
  [ -d "${HOME}/.vim/autoload" ]
}

@test "setup_vim_plugins: downloads plug.vim when it does not exist" {
  run setup_vim_plugins
  [ "$status" -eq 0 ]
  grep -q "curl.*plug.vim" "${MOCK_CALLS_FILE}"
}

@test "setup_vim_plugins: skips curl when plug.vim already exists" {
  mkdir -p "${HOME}/.vim/autoload"
  touch "${HOME}/.vim/autoload/plug.vim"
  run setup_vim_plugins
  [ "$status" -eq 0 ]
  ! grep -q "curl.*plug.vim" "${MOCK_CALLS_FILE}"
}
