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
  FAKE_AI_CONFIG_SRC="${BATS_TEST_TMPDIR}/ai-config"

  mkdir -p "${FAKE_HOME}"
  export HOME="${FAKE_HOME}"
  export PERSONAL_GITREPOS="${FAKE_PERSONAL_GITREPOS}"
  export DOTFILES="dotfiles"
  export _OVERRIDE_AI_CONFIG_DIR="${FAKE_AI_CONFIG_SRC}"
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
  touch "${FAKE_DOTFILES_SRC}/.warp/settings.toml"
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
  # .cursor/ and .claude/ items sourced from AI_CONFIG_DIR (ai-config repo)
  mkdir -p "${FAKE_AI_CONFIG_SRC}/.cursor/User/snippets"
  mkdir -p "${FAKE_AI_CONFIG_SRC}/.cursor/plugins"
  mkdir -p "${FAKE_AI_CONFIG_SRC}/.cursor/skills-cursor"
  touch "${FAKE_AI_CONFIG_SRC}/.cursor/User/settings.json"
  touch "${FAKE_AI_CONFIG_SRC}/.cursor/User/keybindings.json"
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

@test "clone_or_update_dotfiles returns non-zero when cd to HOME fails" {
  # Set HOME to a path that does not exist so cd fails in the clone branch.
  # PERSONAL_GITREPOS is derived from HOME so it also won't exist → clone branch taken.
  export HOME="${BATS_TEST_TMPDIR}/nonexistent_home"
  export PERSONAL_GITREPOS="${HOME}/git-repos/personal"
  run clone_or_update_dotfiles
  [ "$status" -ne 0 ]
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

@test "setup_dotfile_symlinks links .warp/settings.toml" {
  _make_fake_dotfiles
  export MACOS=1
  unset LINUX
  run setup_dotfile_symlinks
  [ "$status" -eq 0 ]
  [[ -L "${FAKE_HOME}/.warp/settings.toml" ]]
  [[ "$(readlink "${FAKE_HOME}/.warp/settings.toml")" == "${FAKE_DOTFILES_SRC}/.warp/settings.toml" ]]
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

@test "setup_dotfile_symlinks links Cursor User settings on macOS (v2 settings dir)" {
  _make_fake_dotfiles
  # Cursor v2: settings live in Cursor/settings/ subdir
  mkdir -p "${FAKE_HOME}/Library/Application Support/Cursor/settings"
  touch "${FAKE_HOME}/Library/Application Support/Cursor/settings/settings.json"
  touch "${FAKE_HOME}/Library/Application Support/Cursor/settings/keybindings.json"
  export MACOS=1
  unset LINUX
  run setup_dotfile_symlinks
  [ "$status" -eq 0 ]
  [[ -L "${FAKE_HOME}/Library/Application Support/Cursor/User/settings.json" ]]
  [[ -L "${FAKE_HOME}/Library/Application Support/Cursor/User/keybindings.json" ]]
  [[ -L "${FAKE_HOME}/Library/Application Support/Cursor/User/snippets" ]]
}

@test "setup_dotfile_symlinks links Cursor User settings on macOS (v3 User dir)" {
  _make_fake_dotfiles
  # Cursor v3: no settings/ subdir; User dir exists directly
  mkdir -p "${FAKE_HOME}/Library/Application Support/Cursor/User"
  export MACOS=1
  unset LINUX
  run setup_dotfile_symlinks
  [ "$status" -eq 0 ]
  [[ -L "${FAKE_HOME}/Library/Application Support/Cursor/User/settings.json" ]]
  [[ -L "${FAKE_HOME}/Library/Application Support/Cursor/User/keybindings.json" ]]
  [[ -L "${FAKE_HOME}/Library/Application Support/Cursor/User/snippets" ]]
}

@test "setup_dotfile_symlinks links Cursor User settings on Linux" {
  _make_fake_dotfiles
  export LINUX=1
  unset MACOS
  run setup_dotfile_symlinks
  [ "$status" -eq 0 ]
  [[ -L "${FAKE_HOME}/.config/Cursor/User/settings.json" ]]
  [[ -L "${FAKE_HOME}/.config/Cursor/User/keybindings.json" ]]
  [[ -L "${FAKE_HOME}/.config/Cursor/User/snippets" ]]
}

@test "setup_dotfile_symlinks creates ~/.cursor/plugins symlink" {
  _make_fake_dotfiles
  export MACOS=1
  unset LINUX
  run setup_dotfile_symlinks
  [ "$status" -eq 0 ]
  [[ -L "${FAKE_HOME}/.cursor/plugins" ]]
  [[ "$(readlink "${FAKE_HOME}/.cursor/plugins")" == "${FAKE_AI_CONFIG_SRC}/.cursor/plugins" ]]
}

@test "setup_dotfile_symlinks creates ~/.cursor/skills-cursor symlink" {
  _make_fake_dotfiles
  export MACOS=1
  unset LINUX
  run setup_dotfile_symlinks
  [ "$status" -eq 0 ]
  [[ -L "${FAKE_HOME}/.cursor/skills-cursor" ]]
  [[ "$(readlink "${FAKE_HOME}/.cursor/skills-cursor")" == "${FAKE_AI_CONFIG_SRC}/.cursor/skills-cursor" ]]
}

@test "setup_dotfile_symlinks creates ~/.cursor/plugins symlink on Linux" {
  _make_fake_dotfiles
  export LINUX=1
  unset MACOS
  run setup_dotfile_symlinks
  [ "$status" -eq 0 ]
  [[ -L "${FAKE_HOME}/.cursor/plugins" ]]
  [[ "$(readlink "${FAKE_HOME}/.cursor/plugins")" == "${FAKE_AI_CONFIG_SRC}/.cursor/plugins" ]]
}

@test "setup_dotfile_symlinks creates ~/.cursor/skills-cursor symlink on Linux" {
  _make_fake_dotfiles
  export LINUX=1
  unset MACOS
  run setup_dotfile_symlinks
  [ "$status" -eq 0 ]
  [[ -L "${FAKE_HOME}/.cursor/skills-cursor" ]]
  [[ "$(readlink "${FAKE_HOME}/.cursor/skills-cursor")" == "${FAKE_AI_CONFIG_SRC}/.cursor/skills-cursor" ]]
}

@test "setup_dotfile_symlinks does not symlink User/ under ~/.cursor" {
  _make_fake_dotfiles
  export MACOS=1
  unset LINUX
  run setup_dotfile_symlinks
  [ "$status" -eq 0 ]
  [[ ! -L "${FAKE_HOME}/.cursor/User" ]]
}

@test "setup_dotfile_symlinks handles .cursor/ with only User/ present" {
  _make_fake_dotfiles
  rm -rf "${FAKE_AI_CONFIG_SRC}/.cursor/plugins" "${FAKE_AI_CONFIG_SRC}/.cursor/skills-cursor"
  export MACOS=1
  unset LINUX
  run setup_dotfile_symlinks
  [ "$status" -eq 0 ]
  [[ ! -L "${FAKE_HOME}/.cursor/User" ]]
}

@test "setup_dotfile_symlinks handles .claude/projects/ when directory is absent" {
  _make_fake_dotfiles
  rm -rf "${FAKE_DOTFILES_SRC}/.claude/projects"
  export MACOS=1
  unset LINUX
  run setup_dotfile_symlinks
  [ "$status" -eq 0 ]
}

# ── setup_credential_directories ────────────────────────────────────────────

@test "setup_credential_directories creates .aws with chmod 700" {
  run setup_credential_directories
  [ "$status" -eq 0 ]
  [[ -d "${FAKE_HOME}/.aws" ]]
  perms=$(stat -c "%a" "${FAKE_HOME}/.aws" 2>/dev/null || stat -f "%OLp" "${FAKE_HOME}/.aws")
  [ "$perms" = "700" ]
}

@test "setup_credential_directories creates .gcloud_creds with chmod 700" {
  run setup_credential_directories
  [ "$status" -eq 0 ]
  [[ -d "${FAKE_HOME}/.gcloud_creds" ]]
  perms=$(stat -c "%a" "${FAKE_HOME}/.gcloud_creds" 2>/dev/null || stat -f "%OLp" "${FAKE_HOME}/.gcloud_creds")
  [ "$perms" = "700" ]
}

@test "setup_credential_directories creates .azure_creds with chmod 700" {
  run setup_credential_directories
  [ "$status" -eq 0 ]
  [[ -d "${FAKE_HOME}/.azure_creds" ]]
  perms=$(stat -c "%a" "${FAKE_HOME}/.azure_creds" 2>/dev/null || stat -f "%OLp" "${FAKE_HOME}/.azure_creds")
  [ "$perms" = "700" ]
}

# ── setup_zsh_as_default_shell ───────────────────────────────────────────────

@test "setup_zsh_as_default_shell does nothing when shell is already zsh" {
  export SHELL="/bin/zsh"
  run setup_zsh_as_default_shell
  [ "$status" -eq 0 ]
  run grep -q "chsh" "${MOCK_CALLS_FILE}"
  [ "$status" -ne 0 ]
}

@test "setup_zsh_as_default_shell calls chsh when shell is not zsh" {
  export SHELL="/bin/bash"
  run setup_zsh_as_default_shell
  [ "$status" -eq 0 ]
  grep -q "chsh -s /bin/zsh" "${MOCK_CALLS_FILE}"
}

# ── update_system_packages ───────────────────────────────────────────────────

@test "update_system_packages calls apt update on Ubuntu" {
  export UBUNTU=1
  unset MACOS LINUX
  run update_system_packages
  [ "$status" -eq 0 ]
  grep -q "apt update" "${MOCK_CALLS_FILE}"
}

@test "update_system_packages calls nala full-upgrade on Ubuntu Noble" {
  export UBUNTU=1
  unset MACOS LINUX
  run update_system_packages
  [ "$status" -eq 0 ]
  grep -q "nala full-upgrade" "${MOCK_CALLS_FILE}"
}

# ── update_aws_cli ───────────────────────────────────────────────────────────

@test "update_aws_cli on macOS calls curl and installer" {
  export MACOS=1
  export HAS_AWS=1
  unset LINUX
  mkdir -p "${FAKE_HOME}/software_downloads/awscli"
  mkdir -p "${FAKE_DOTFILES_SRC}"
  run update_aws_cli
  [ "$status" -eq 0 ]
  grep -q "curl.*AWSCLIV2.pkg" "${MOCK_CALLS_FILE}"
  grep -q "installer -pkg" "${MOCK_CALLS_FILE}"
}

@test "update_aws_cli on Linux calls curl and install script" {
  export LINUX=1
  export HAS_AWS=1
  unset MACOS
  mkdir -p "${FAKE_DOTFILES_SRC}"
  run update_aws_cli
  [ "$status" -eq 0 ]
  grep -q "curl.*awscli-exe-linux" "${MOCK_CALLS_FILE}"
  grep -q "unzip" "${MOCK_CALLS_FILE}"
}

# ── update_rust ──────────────────────────────────────────────────────────────

@test "update_rust does nothing when not Ubuntu Workstation" {
  export MACOS=1
  unset UBUNTU HAS_RUST
  run update_rust
  [ "$status" -eq 0 ]
  run grep -q "rustup" "${MOCK_CALLS_FILE}"
  [ "$status" -ne 0 ]
}

@test "update_rust calls system rustup when cargo rustup is absent" {
  export UBUNTU=1
  export HAS_RUST=1
  unset MACOS
  # .cargo/bin/rustup does not exist in FAKE_HOME; rustup mock is in PATH
  run update_rust
  [ "$status" -eq 0 ]
  grep -q "rustup self update" "${MOCK_CALLS_FILE}"
}

@test "update_rust calls curl for nextest update when nextest is installed" {
  export UBUNTU=1
  export HAS_RUST=1
  unset MACOS
  local _bin_dir="${BATS_TEST_TMPDIR}/nextest_bin"
  mkdir -p "${_bin_dir}"
  printf '#!/usr/bin/env bash\n' > "${_bin_dir}/cargo-nextest" && chmod +x "${_bin_dir}/cargo-nextest"
  mkdir -p "${FAKE_HOME}/.cargo/bin"
  export PATH="${_bin_dir}:${PATH}"
  run update_rust
  grep -q "curl.*nexte.st" "${MOCK_CALLS_FILE}"
}

@test "update_rust does not call curl for nextest when nextest is absent" {
  export UBUNTU=1
  export HAS_RUST=1
  unset MACOS
  # Strip any dir containing cargo-nextest so the guard sees it as absent
  local _clean_path=""
  IFS=: read -ra _parts <<< "${PATH}"
  for _p in "${_parts[@]}"; do
    [[ -x "${_p}/cargo-nextest" ]] && continue
    [[ -z "${_clean_path}" ]] && _clean_path="${_p}" || _clean_path="${_clean_path}:${_p}"
  done
  export PATH="${_clean_path}"
  run update_rust
  ! grep -q "curl.*nexte.st" "${MOCK_CALLS_FILE}"
}

@test "update_rust prints skip message when rustup is not found" {
  export UBUNTU=1
  export HAS_RUST=1
  unset MACOS
  # Build a PATH that excludes the mocks directory and any directory containing rustup,
  # so both the mock rustup and any real rustup are invisible to command -v.
  local clean_path
  clean_path="$(printf "%s" "${PATH}" | tr ':' '\n' | grep -v "tests/mocks" | while read -r dir; do
    [[ -x "${dir}/rustup" ]] || printf "%s\n" "${dir}"
  done | tr '\n' ':' | sed 's/:$//')"
  run bash -c "
    export PATH='${clean_path}'
    export HOME='${FAKE_HOME}'
    export PERSONAL_GITREPOS='${FAKE_PERSONAL_GITREPOS}'
    export DOTFILES='dotfiles'
    export UBUNTU=1
    export HAS_RUST=1
    unset MACOS
    source '${REPO_ROOT}/setup_env.sh'
    update_rust
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipping"* ]]
}

@test "update_system_packages does not call mas upgrade (mas is called from run_update)" {
  export MACOS=1
  unset UBUNTU
  run update_system_packages
  [ "$status" -eq 0 ]
  ! grep -q "mas upgrade" "${MOCK_CALLS_FILE}"
}
