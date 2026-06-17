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
  export LINUX=1
  unset MACOS
  export MOCK_AWK_OS_NAME="Ubuntu"
  run install_git
  [ "$status" -eq 0 ]
  grep -q "apt install git" "${MOCK_CALLS_FILE}"
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
  export LINUX=1
  unset MACOS
  export MOCK_AWK_OS_NAME="Ubuntu"
  run install_zsh
  [ "$status" -eq 0 ]
  grep -q "apt install zsh zsh-doc" "${MOCK_CALLS_FILE}"
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
  # The function checks 'dpkg -l nala | grep -q "^ii"' to detect nala.
  # The dpkg mock outputs nothing, so grep -q fails, taking the install branch.
  run check_and_install_nala
  [ "$status" -eq 0 ]
  grep -q "dpkg --install" "${MOCK_CALLS_FILE}"
  grep -q "apt install nala" "${MOCK_CALLS_FILE}"
}

@test "check_and_install_nala skips install when nala is already installed" {
  export MOCK_UNAME_S=Linux
  export MOCK_AWK_OS_NAME="Ubuntu"
  export HOME="${BATS_TEST_TMPDIR}"
  # Simulate nala already installed: make dpkg -l output an 'ii' line.
  export MOCK_DPKG_L_NALA="ii  nala  0.15.0  amd64  Commandline Package Manager"
  run check_and_install_nala
  [ "$status" -eq 0 ]
  ! grep -q "dpkg --install" "${MOCK_CALLS_FILE}"
  ! grep -q "apt install nala" "${MOCK_CALLS_FILE}"
}

@test "check_and_install_nala on RESOLUTE uses apt install, skips volian wget" {
  export MOCK_UNAME_S=Linux
  export MOCK_AWK_OS_NAME="Ubuntu"
  export RESOLUTE=1
  export HOME="${BATS_TEST_TMPDIR}"
  mkdir -p "${BATS_TEST_TMPDIR}/software_downloads"
  run check_and_install_nala
  [ "$status" -eq 0 ]
  run grep -q "apt install nala" "${MOCK_CALLS_FILE}"
  [ "$status" -eq 0 ]
  run grep -q "wget" "${MOCK_CALLS_FILE}"
  [ "$status" -ne 0 ]
}

@test "check_and_install_nala on NOBLE uses volian wget path" {
  export MOCK_UNAME_S=Linux
  export MOCK_AWK_OS_NAME="Ubuntu"
  export NOBLE=1
  unset RESOLUTE
  export HOME="${BATS_TEST_TMPDIR}"
  mkdir -p "${BATS_TEST_TMPDIR}/software_downloads"
  run check_and_install_nala
  [ "$status" -eq 0 ]
  run grep -q "wget" "${MOCK_CALLS_FILE}"
  [ "$status" -eq 0 ]
  run grep -q "dpkg --install" "${MOCK_CALLS_FILE}"
  [ "$status" -eq 0 ]
}

# ── install_homebrew ─────────────────────────────────────────────────────────

@test "install_homebrew skips xcode setup when xcode-select is already installed" {
  export MOCK_UNAME_S=Darwin
  export MOCK_XCODE_SELECT_PRINT_PATH_EXIT=0
  run install_homebrew
  [ "$status" -eq 0 ]
  [[ "$output" == *"Homebrew has been successfully installed"* ]]
  run grep -q "xcode-select --install" "${MOCK_CALLS_FILE}"
  [ "$status" -ne 0 ]
}

@test "install_homebrew installs xcode tools when not present" {
  export MOCK_UNAME_S=Darwin
  export MOCK_XCODE_SELECT_PRINT_PATH_EXIT=1
  export MOCK_XCODE_SELECT_EXIT=0
  export MOCK_XCODEBUILD_EXIT=0
  run install_homebrew
  [ "$status" -eq 0 ]
  grep -q "xcode-select --install" "${MOCK_CALLS_FILE}"
  grep -q "xcodebuild -license accept" "${MOCK_CALLS_FILE}"
}

@test "install_homebrew returns 1 when xcode-select --install fails" {
  export MOCK_UNAME_S=Darwin
  export MOCK_XCODE_SELECT_PRINT_PATH_EXIT=1
  export MOCK_XCODE_SELECT_EXIT=1
  run install_homebrew
  [ "$status" -eq 1 ]
  [[ "$output" == *"Failed to install Xcode Command Line Tools"* ]]
}

@test "install_homebrew returns 1 when brew install script fails" {
  # Use Linux to skip xcode block; test only the brew install failure path
  export MOCK_UNAME_S=Linux
  export MOCK_CURL_STDOUT="exit 1"
  run install_homebrew
  [ "$status" -eq 1 ]
  [[ "$output" == *"Failed to install Homebrew"* ]]
}

# ── install_ruby_tools ───────────────────────────────────────────────────────

@test "install_ruby_tools returns non-zero when cd to ruby-install dir fails" {
  export LINUX=1
  unset MACOS UBUNTU
  local _home="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${_home}/software_downloads"
  export HOME="${_home}"
  export MOCK_TAR_EXIT=1  # tar fails → ruby-install dir not created → cd fails
  run install_ruby_tools
  [ "$status" -ne 0 ]
}

# ── _install_ubuntu_go ────────────────────────────────────────────────────────
# The unsupported-version range guard was removed — always calls tarball install.

@test "_install_ubuntu_go with GO_VER 1.18 does not call add-apt-repository" {
  export UBUNTU=1
  unset MACOS LINUX
  export MOCK_UNAME_S=Linux
  local _home="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${_home}/software_downloads"
  export HOME="${_home}"
  export GO_VER="1.18"
  export PATH="${BATS_TEST_DIRNAME}/../mocks:${PATH}"
  _install_ubuntu_go
  run grep "add-apt-repository" "${MOCK_CALLS_FILE}"
  [ "$status" -ne 0 ]
}

@test "_install_ubuntu_go always calls _install_go_from_tarball" {
  export UBUNTU=1
  unset MACOS LINUX
  export MOCK_UNAME_S=Linux
  local _home="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${_home}/software_downloads"
  export HOME="${_home}"
  export GO_VER="1.18"
  export PATH="${BATS_TEST_DIRNAME}/../mocks:${PATH}"
  _install_ubuntu_go
  grep -q "wget" "${MOCK_CALLS_FILE}"
}

# ── install_terraform_skill ───────────────────────────────────────────────────

@test "install_terraform_skill clones repo when skill dir does not exist" {
  local _home="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${_home}/.cursor/skills"
  export HOME="${_home}"
  run install_terraform_skill
  [ "$status" -eq 0 ]
  grep -q "git clone --depth=1" "${MOCK_CALLS_FILE}"
}

@test "install_terraform_skill runs git pull when .git dir exists" {
  local _home="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${_home}/.cursor/skills/terraform-skill/.git"
  export HOME="${_home}"
  run install_terraform_skill
  [ "$status" -eq 0 ]
  grep -qE "git -C .* pull --ff-only" "${MOCK_CALLS_FILE}"
}

@test "install_terraform_skill warns and skips when path exists without .git" {
  local _home="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${_home}/.cursor/skills/terraform-skill"
  export HOME="${_home}"
  run install_terraform_skill
  [ "$status" -eq 0 ]
  [[ "$output" == *"not a git checkout"* ]]
  ! grep -q "git clone" "${MOCK_CALLS_FILE}"
  ! grep -qE "git -C .* pull" "${MOCK_CALLS_FILE}"
}

@test "install_terraform_skill returns non-zero when git pull fails" {
  local _home="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${_home}/.cursor/skills/terraform-skill/.git"
  export HOME="${_home}"
  export MOCK_GIT_EXIT=1
  run install_terraform_skill
  [ "$status" -ne 0 ]
}

@test "install_terraform_skill returns non-zero when git clone fails" {
  local _home="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${_home}/.cursor/skills"
  export HOME="${_home}"
  export MOCK_GIT_CLONE_EXIT=1
  run install_terraform_skill
  [ "$status" -ne 0 ]
}

# ── recreate_python_venv ──────────────────────────────────────────────────────

@test "recreate_python_venv ansible: calls pyenv virtualenv-delete, create, activate, pip install" {
  export MACOS=1
  unset LINUX
  export HAS_DEVTOOLS=1
  # Point MOCK_PYENV_WHICH_STDOUT to mock python so `pyenv which python` returns
  # the mock binary — this intercepts the `"${_python}" -m pip install` call.
  export MOCK_PYENV_WHICH_STDOUT="${BATS_TEST_DIRNAME}/../mocks/python"
  export PATH="${BATS_TEST_DIRNAME}/../mocks:${PATH}"
  recreate_python_venv "ansible"
  grep -q "virtualenv-delete -f ansible" "${MOCK_CALLS_FILE}"
  grep -q "virtualenv.*ansible" "${MOCK_CALLS_FILE}"
  grep -q "activate ansible" "${MOCK_CALLS_FILE}"
  grep -q "pip install" "${MOCK_CALLS_FILE}"
  grep -q "pyenv rehash" "${MOCK_CALLS_FILE}"
}

@test "recreate_python_venv myenv: calls delete, create, activate — no pip install" {
  export MACOS=1
  unset LINUX
  export HAS_DEVTOOLS=1
  export MOCK_PYENV_WHICH_STDOUT="${BATS_TEST_DIRNAME}/../mocks/python"
  export PATH="${BATS_TEST_DIRNAME}/../mocks:${PATH}"
  recreate_python_venv "myenv"
  grep -q "virtualenv-delete -f myenv" "${MOCK_CALLS_FILE}"
  grep -q "virtualenv.*myenv" "${MOCK_CALLS_FILE}"
  grep -q "activate myenv" "${MOCK_CALLS_FILE}"
  run grep "pip install" "${MOCK_CALLS_FILE}"
  [ "$status" -ne 0 ]
}

@test "recreate_python_venv returns 1 when pyenv not found" {
  export MACOS=1
  unset LINUX
  export HAS_DEVTOOLS=1
  local _saved_path="$PATH"
  export PATH="/usr/bin:/bin"
  local _rc=0
  recreate_python_venv "ansible" || _rc=$?
  export PATH="${_saved_path}"
  [ "${_rc}" -ne 0 ]
}

@test "recreate_python_venv succeeds when virtualenv does not exist (delete returns non-zero)" {
  export MACOS=1
  unset LINUX
  export HAS_DEVTOOLS=1
  export MOCK_PYENV_WHICH_STDOUT="${BATS_TEST_DIRNAME}/../mocks/python"
  export MOCK_PYENV_VIRTUALENV_DELETE_EXIT=1
  export PATH="${BATS_TEST_DIRNAME}/../mocks:${PATH}"
  local _rc=0
  recreate_python_venv "ansible" || _rc=$?
  [ "${_rc}" -eq 0 ]
  grep -q "virtualenv-delete -f ansible" "${MOCK_CALLS_FILE}"
  grep -q "virtualenv.*ansible" "${MOCK_CALLS_FILE}"
}

@test "recreate_python_venv ansible on macOS includes mlx in pip install" {
  export MACOS=1
  unset LINUX
  export HAS_DEVTOOLS=1
  export MOCK_PYENV_WHICH_STDOUT="${BATS_TEST_DIRNAME}/../mocks/python"
  export PATH="${BATS_TEST_DIRNAME}/../mocks:${PATH}"
  recreate_python_venv "ansible"
  grep -q "mlx" "${MOCK_CALLS_FILE}"
}

@test "recreate_python_venv ansible on Linux excludes mlx from pip install" {
  unset MACOS
  export LINUX=1
  export UBUNTU=1
  export HAS_DEVTOOLS=1
  export MOCK_PYENV_WHICH_STDOUT="${BATS_TEST_DIRNAME}/../mocks/python"
  export PATH="${BATS_TEST_DIRNAME}/../mocks:${PATH}"
  local _rc=0
  recreate_python_venv "ansible" || _rc=$?
  [ "${_rc}" -eq 0 ]
  grep -q "pip install" "${MOCK_CALLS_FILE}"
  run grep "mlx" "${MOCK_CALLS_FILE}"
  [ "$status" -ne 0 ]
}
