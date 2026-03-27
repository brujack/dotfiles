#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_setup_env
  load_mocks
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"

  # Fake filesystem layout for extracted function tests
  FAKE_HOME="${BATS_TEST_TMPDIR}/home"
  FAKE_PERSONAL_GITREPOS="${BATS_TEST_TMPDIR}/home/git-repos/personal"
  FAKE_DOTFILES_SRC="${FAKE_PERSONAL_GITREPOS}/dotfiles"

  mkdir -p "${FAKE_HOME}"
  export HOME="${FAKE_HOME}"
  export PERSONAL_GITREPOS="${FAKE_PERSONAL_GITREPOS}"
  export DOTFILES="dotfiles"
}

teardown() {
  rm -f "${MOCK_CALLS_FILE:-}"
}

# Helper: create all source files that setup_dotfile_symlinks will symlink
_make_fake_dotfiles() {
  mkdir -p "${FAKE_DOTFILES_SRC}/.config/.zshrc.d"
  mkdir -p "${FAKE_DOTFILES_SRC}/.config/ccstatusline"
  mkdir -p "${FAKE_DOTFILES_SRC}/.ssh"
  mkdir -p "${FAKE_DOTFILES_SRC}/.claude"
  mkdir -p "${FAKE_DOTFILES_SRC}/.warp/themes"
  mkdir -p "${FAKE_DOTFILES_SRC}/.warp/launch_configurations"
  touch "${FAKE_DOTFILES_SRC}/.gitconfig_mac"
  touch "${FAKE_DOTFILES_SRC}/.gitconfig_linux"
  touch "${FAKE_DOTFILES_SRC}/.gitconfig_mac_gitlab"
  touch "${FAKE_DOTFILES_SRC}/.gitconfig_linux_gitlab"
  touch "${FAKE_DOTFILES_SRC}/.vimrc"
  touch "${FAKE_DOTFILES_SRC}/.p10k.zsh"
  touch "${FAKE_DOTFILES_SRC}/.tmux.conf"
  touch "${FAKE_DOTFILES_SRC}/scripts"
  touch "${FAKE_DOTFILES_SRC}/bruce.zsh-theme"
  touch "${FAKE_DOTFILES_SRC}/profile.ps1"
  touch "${FAKE_DOTFILES_SRC}/bruce.omp.json"
  touch "${FAKE_DOTFILES_SRC}/starship.toml"
  touch "${FAKE_DOTFILES_SRC}/.zshrc"
  touch "${FAKE_DOTFILES_SRC}/.zprofile"
  touch "${FAKE_DOTFILES_SRC}/.ssh/config"
  touch "${FAKE_DOTFILES_SRC}/.ssh/teleport.cfg"
}

# ── clone_or_update_dotfiles ─────────────────────────────────────────────────

@test "clone_or_update_dotfiles clones when dotfiles directory does not exist" {
  run clone_or_update_dotfiles
  [ "$status" -eq 0 ]
  grep -q "git clone" "${MOCK_CALLS_FILE}"
  [[ -d "${FAKE_PERSONAL_GITREPOS}/dotfiles" ]]
}

@test "clone_or_update_dotfiles runs git pull when dotfiles directory exists" {
  mkdir -p "${FAKE_DOTFILES_SRC}"
  run clone_or_update_dotfiles
  [ "$status" -eq 0 ]
  grep -q "git pull" "${MOCK_CALLS_FILE}"
  ! grep -q "git clone" "${MOCK_CALLS_FILE}"
}

# ── setup_dotfile_symlinks ───────────────────────────────────────────────────

@test "setup_dotfile_symlinks links .gitconfig_mac on macOS" {
  _make_fake_dotfiles
  export MACOS=1
  unset LINUX
  run setup_dotfile_symlinks
  [ "$status" -eq 0 ]
  [[ -L "${FAKE_HOME}/.gitconfig" ]]
  [[ "$(readlink "${FAKE_HOME}/.gitconfig")" == "${FAKE_DOTFILES_SRC}/.gitconfig_mac" ]]
}

@test "setup_dotfile_symlinks links .gitconfig_linux on Linux" {
  _make_fake_dotfiles
  export LINUX=1
  unset MACOS
  run setup_dotfile_symlinks
  [ "$status" -eq 0 ]
  [[ -L "${FAKE_HOME}/.gitconfig" ]]
  [[ "$(readlink "${FAKE_HOME}/.gitconfig")" == "${FAKE_DOTFILES_SRC}/.gitconfig_linux" ]]
}

@test "setup_dotfile_symlinks links .vimrc" {
  _make_fake_dotfiles
  export MACOS=1
  unset LINUX
  run setup_dotfile_symlinks
  [ "$status" -eq 0 ]
  [[ -L "${FAKE_HOME}/.vimrc" ]]
}

@test "setup_dotfile_symlinks links .zshrc" {
  _make_fake_dotfiles
  export MACOS=1
  unset LINUX
  run setup_dotfile_symlinks
  [ "$status" -eq 0 ]
  [[ -L "${FAKE_HOME}/.zshrc" ]]
}

@test "setup_dotfile_symlinks links .config/ccstatusline and .zshrc.d" {
  _make_fake_dotfiles
  export MACOS=1
  unset LINUX
  run setup_dotfile_symlinks
  [ "$status" -eq 0 ]
  [[ -L "${FAKE_HOME}/.config/ccstatusline" ]]
  [[ -L "${FAKE_HOME}/.config/.zshrc.d" ]]
}

# ── setup_credential_directories ────────────────────────────────────────────

@test "setup_credential_directories creates .aws with chmod 700" {
  run setup_credential_directories
  [ "$status" -eq 0 ]
  [[ -d "${FAKE_HOME}/.aws" ]]
  perms=$(stat -f "%OLp" "${FAKE_HOME}/.aws" 2>/dev/null || stat -c "%a" "${FAKE_HOME}/.aws")
  [ "$perms" = "700" ]
}

@test "setup_credential_directories creates .gcloud_creds with chmod 700" {
  run setup_credential_directories
  [ "$status" -eq 0 ]
  [[ -d "${FAKE_HOME}/.gcloud_creds" ]]
  perms=$(stat -f "%OLp" "${FAKE_HOME}/.gcloud_creds" 2>/dev/null || stat -c "%a" "${FAKE_HOME}/.gcloud_creds")
  [ "$perms" = "700" ]
}

@test "setup_credential_directories creates .azure_creds with chmod 700" {
  run setup_credential_directories
  [ "$status" -eq 0 ]
  [[ -d "${FAKE_HOME}/.azure_creds" ]]
  perms=$(stat -f "%OLp" "${FAKE_HOME}/.azure_creds" 2>/dev/null || stat -c "%a" "${FAKE_HOME}/.azure_creds")
  [ "$perms" = "700" ]
}

# ── setup_zsh_as_default_shell ───────────────────────────────────────────────

@test "setup_zsh_as_default_shell does nothing when shell is already zsh" {
  export SHELL="/bin/zsh"
  unset REDHAT
  run setup_zsh_as_default_shell
  [ "$status" -eq 0 ]
  ! grep -q "chsh" "${MOCK_CALLS_FILE}"
}

@test "setup_zsh_as_default_shell calls chsh when shell is not zsh" {
  export SHELL="/bin/bash"
  unset REDHAT
  run setup_zsh_as_default_shell
  [ "$status" -eq 0 ]
  grep -q "chsh -s /bin/zsh" "${MOCK_CALLS_FILE}"
}
