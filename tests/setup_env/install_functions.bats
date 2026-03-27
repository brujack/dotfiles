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

# macOS tests require both MOCK_UNAME_S=Darwin (for the uname -s branch) and
# MACOS=1 (for the inner [[ -n ${MACOS} ]] guard that calls brew_install_formula).
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

# macOS tests require both MOCK_UNAME_S=Darwin (for the uname -s branch) and
# MACOS=1 (for the inner [[ -n ${MACOS} ]] guard that calls brew_install_formula).
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
  grep -q "apt install zsh zsh-doc" "${MOCK_CALLS_FILE}"
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

# ── install_rosetta ──────────────────────────────────────────────────────────

@test "install_rosetta does nothing on macOS older than 11" {
  export MOCK_SW_VERS_PRODUCTVERSION="10.15.7"
  run install_rosetta
  [ "$status" -eq 0 ]
  [[ "$output" == *"No need to install Rosetta"* ]]
  ! grep -q "softwareupdate" "${MOCK_CALLS_FILE}"
}

@test "install_rosetta skips when processor is Intel" {
  export MOCK_SW_VERS_PRODUCTVERSION="12.0.0"
  export MOCK_SYSCTL_CPU="Intel(R) Core(TM) i9-9880H CPU @ 2.30GHz"
  run install_rosetta
  [ "$status" -eq 0 ]
  [[ "$output" == *"No need to install Rosetta"* ]]
  ! grep -q "softwareupdate" "${MOCK_CALLS_FILE}"
}

@test "install_rosetta skips when oahd process is already running" {
  export MOCK_SW_VERS_PRODUCTVERSION="12.0.0"
  export MOCK_SYSCTL_CPU="Apple M1"
  export MOCK_PGREP_EXIT=0
  run install_rosetta
  [ "$status" -eq 0 ]
  [[ "$output" == *"already installed"* ]]
  ! grep -q "softwareupdate --install-rosetta" "${MOCK_CALLS_FILE}"
}

@test "install_rosetta installs Rosetta on Apple Silicon when oahd is absent" {
  export MOCK_SW_VERS_PRODUCTVERSION="12.0.0"
  export MOCK_SYSCTL_CPU="Apple M1"
  export MOCK_PGREP_EXIT=1
  export MOCK_SOFTWAREUPDATE_EXIT=0
  run install_rosetta
  [ "$status" -eq 0 ]
  grep -q "softwareupdate --install-rosetta" "${MOCK_CALLS_FILE}"
  [[ "$output" == *"successfully installed"* ]]
}

@test "install_rosetta returns 1 when softwareupdate fails" {
  export MOCK_SW_VERS_PRODUCTVERSION="12.0.0"
  export MOCK_SYSCTL_CPU="Apple M1"
  export MOCK_PGREP_EXIT=1
  export MOCK_SOFTWAREUPDATE_EXIT=1
  run install_rosetta
  [ "$status" -eq 1 ]
  [[ "$output" == *"installation failed"* ]]
}

# ── check_and_install_nala ───────────────────────────────────────────────────

@test "check_and_install_nala does nothing on non-Linux" {
  export MOCK_UNAME_S=Darwin
  run check_and_install_nala
  [ "$status" -eq 0 ]
  ! grep -q "dpkg" "${MOCK_CALLS_FILE}"
}

@test "check_and_install_nala does nothing on non-Ubuntu Linux" {
  export MOCK_UNAME_S=Linux
  export MOCK_AWK_OS_NAME="Fedora"
  run check_and_install_nala
  [ "$status" -eq 0 ]
  ! grep -q "dpkg" "${MOCK_CALLS_FILE}"
}

@test "check_and_install_nala installs nala via dpkg and apt on Ubuntu when absent" {
  export MOCK_UNAME_S=Linux
  export MOCK_AWK_OS_NAME="Ubuntu"
  export HOME="${BATS_TEST_TMPDIR}"
  mkdir -p "${BATS_TEST_TMPDIR}/software_downloads"
  # nala mock is in tests/mocks/ so command -v nala would succeed by default.
  # Build a tmp mocks dir without the nala mock so command -v nala fails,
  # causing check_and_install_nala to take the install branch.
  mocks_dir="${REPO_ROOT}/tests/mocks"
  tmp_mocks="${BATS_TEST_TMPDIR}/mocks_no_nala"
  mkdir -p "${tmp_mocks}"
  for f in "${mocks_dir}"/*; do
    [[ "$(basename "$f")" == "nala" ]] && continue
    ln -sf "$f" "${tmp_mocks}/$(basename "$f")"
  done
  # Replace load_mocks PATH entry: swap the real mocks dir for our filtered copy.
  # load_mocks prepended tests/mocks/ at the start of PATH, so we remove that prefix
  # and prepend the filtered copy instead.
  export PATH="${tmp_mocks}:${PATH#${mocks_dir}:}"
  run check_and_install_nala
  [ "$status" -eq 0 ]
  grep -q "dpkg --install" "${MOCK_CALLS_FILE}"
  grep -q "apt install nala" "${MOCK_CALLS_FILE}"
}
