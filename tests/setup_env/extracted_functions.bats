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
  touch "${FAKE_DOTFILES_SRC}/.gitignore_global"
  touch "${FAKE_DOTFILES_SRC}/.gitconfig_mac_gitlab"
  touch "${FAKE_DOTFILES_SRC}/.gitconfig_linux_gitlab"
  touch "${FAKE_DOTFILES_SRC}/.vimrc"
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
  mkdir -p "${FAKE_AI_CONFIG_SRC}/.claude/projects"
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

@test "setup_dotfile_symlinks links .gitignore_global" {
  _make_fake_dotfiles
  export MACOS=1
  unset LINUX
  run setup_dotfile_symlinks
  [ "$status" -eq 0 ]
  [[ -L "${FAKE_HOME}/.gitignore_global" ]]
  [[ "$(readlink "${FAKE_HOME}/.gitignore_global")" == "${FAKE_DOTFILES_SRC}/.gitignore_global" ]]
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

@test "setup_dotfile_symlinks symlinks ~/.claude/projects to ai-config projects dir" {
  _make_fake_dotfiles
  export MACOS=1
  unset LINUX
  run setup_dotfile_symlinks
  [ "$status" -eq 0 ]
  [[ -L "${FAKE_HOME}/.claude/projects" ]]
  [[ "$(readlink "${FAKE_HOME}/.claude/projects")" == "${FAKE_AI_CONFIG_SRC}/.claude/projects" ]]
}

@test "setup_dotfile_symlinks handles .claude/projects/ when absent from ai-config" {
  _make_fake_dotfiles
  rm -rf "${FAKE_AI_CONFIG_SRC}/.claude/projects"
  export MACOS=1
  unset LINUX
  run setup_dotfile_symlinks
  [ "$status" -eq 0 ]
}

@test "setup_dotfile_symlinks logs 'Installed Oh My ZSH' when OMZ install succeeds" {
  _make_fake_dotfiles
  export MACOS=1
  unset LINUX
  # MOCK_CURL_SDK_STDOUT: curl mock outputs this when URL matches *githubusercontent.com*
  # bash -c runs the output, creating ~/.oh-my-zsh so the success branch is taken
  export MOCK_CURL_SDK_STDOUT='mkdir -p "${HOME}/.oh-my-zsh"'
  run setup_dotfile_symlinks
  [ "$status" -eq 0 ]
  [[ "$output" == *"Installed Oh My ZSH"* ]]
}

@test "setup_dotfile_symlinks warns when Cursor is not installed" {
  _make_fake_dotfiles
  export MACOS=1
  unset LINUX
  mkdir -p "${FAKE_HOME}/.oh-my-zsh"  # skip OMZ install block
  # Override app_dir_exists — /Applications/Cursor.app exists on dev machine
  app_dir_exists() { return 1; }
  # Minimal PATH: mocks (no cursor) + system /bin; excludes /opt/homebrew/bin where real cursor lives
  local _mocks_dir
  _mocks_dir="$(cd "${BATS_TEST_DIRNAME}/../mocks" && pwd)"
  local _tmp="${BATS_TEST_TMPDIR}/mocks_no_cursor"
  mkdir -p "${_tmp}"
  for f in "${_mocks_dir}/"*; do
    [[ "$(basename "$f")" == "cursor" ]] && continue
    ln -sf "$f" "${_tmp}/$(basename "$f")"
  done
  export PATH="${_tmp}:/usr/bin:/bin"
  run setup_dotfile_symlinks
  [ "$status" -eq 0 ]
  [[ "$output" == *"Cursor is not installed"* ]]
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

# All three drive the ACCOUNT's login shell through
# _OVERRIDE_CURRENT_LOGIN_SHELL rather than exporting ${SHELL}, and that is not
# a style change. Production stopped reading ${SHELL} because it names the
# invoking shell rather than the account, so without this seam these tests fall
# through to dscl/getent and read the developer's REAL login shell: "already
# zsh" passed on this mac for the machine's reason, not the code's, and would
# flip on any box whose account differs -- ubuntu-latest included. Same trap
# the homebrew-prefix and gnubin seams already carry.
@test "setup_zsh_as_default_shell does nothing when the account is already zsh" {
  export _OVERRIDE_CURRENT_LOGIN_SHELL="/bin/zsh"
  run setup_zsh_as_default_shell
  [ "$status" -eq 0 ]
  run grep -q "chsh" "${MOCK_CALLS_FILE}"
  [ "$status" -ne 0 ]
}

@test "setup_zsh_as_default_shell calls chsh when the account is not zsh" {
  export _OVERRIDE_CURRENT_LOGIN_SHELL="/bin/bash"
  run setup_zsh_as_default_shell
  [ "$status" -eq 0 ]
  grep -q "chsh -s /bin/zsh" "${MOCK_CALLS_FILE}"
}

# Now returns non-zero rather than 0. An absent zsh is a provisioning failure,
# and run_setup_user's `|| return 1` (workflows.sh:153) should stop on it --
# the old `status -eq 0` here pinned the swallow that made that line dead.
@test "setup_zsh_as_default_shell fails when the zsh path does not exist" {
  export _OVERRIDE_CURRENT_LOGIN_SHELL="/bin/bash"
  export _OVERRIDE_ZSH_PATH="/nonexistent/zsh"
  run setup_zsh_as_default_shell
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]]
  ! grep -q "chsh" "${MOCK_CALLS_FILE}"
}

# Measured on `claude` 2026-09-12, after a full provision left the login shell
# as /bin/bash while the run reported success:
#
#   $ chsh -s /bin/zsh </dev/null
#   Password: chsh: PAM: Authentication failure          rc=1, shell unchanged
#   $ sudo -n chsh -s /bin/zsh "$USER"                   rc=0, shell changed
#
# chsh is setuid root but authenticates the INVOKING user through PAM, so it
# prompts for a password and fails in every non-interactive actor -- ssh
# 'cmd', cron, a provision run. The old code neither sudo'd nor checked the
# rc, and then logged "Changed default shell to ${ZSH_PATH}" unconditionally,
# so a provision that failed to change the shell reported that it had. That is
# a FAIL rendered as a PASS, and it is why nothing surfaced it for the whole
# provisioning session. run_setup_user's `|| return 1` (workflows.sh:153)
# could not fire either, because the function's last command was log_info.
@test "setup_zsh_as_default_shell fails loudly when chsh cannot change the shell" {
  export _OVERRIDE_CURRENT_LOGIN_SHELL="/bin/bash"
  export MOCK_SUDO_EXIT=1
  export MOCK_CHSH_EXIT=1
  run setup_zsh_as_default_shell
  [ "$status" -ne 0 ]
  [[ "$output" != *"Changed default shell"* ]]
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
  # update_aws_cli now gates the installer on _aws_verify_pkg (AWS's Apple
  # team ID), which reads real pkgutil output -- MOCK_PKGUTIL_EXIT defaults
  # to 1 with no stdout, which would fail verification (and the retry) and
  # this test would never reach the installer it asserts on. Give it a
  # passing read.
  export MOCK_PKGUTIL_EXIT=0
  export MOCK_PKGUTIL_STDOUT="   Status: signed by a developer certificate issued by Apple for distribution
   Notarization: trusted by the Apple notary service
    1. Developer ID Installer: AMZN Mobile LLC (${AWSCLI_APPLE_TEAM_ID})"
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
  # update_aws_cli now gates the install script on _aws_verify_zip, a real
  # gpg signature check against the vendored key. Stubbed here rather than
  # driven through a real throwaway key: this test is about the
  # fetch/unzip/install orchestration, not the verifier itself, which has
  # its own dedicated real-gpg coverage in tests/setup_env/developer.bats.
  _aws_verify_zip() { return 0; }
  run update_aws_cli
  [ "$status" -eq 0 ]
  grep -q "curl.*awscli-exe-linux" "${MOCK_CALLS_FILE}"
  grep -q "unzip" "${MOCK_CALLS_FILE}"
}

@test "update_aws_cli on Linux uses uname -m arch in URL (aarch64)" {
  export LINUX=1
  export HAS_AWS=1
  export MOCK_UNAME_M="aarch64"
  unset MACOS
  mkdir -p "${FAKE_DOTFILES_SRC}"
  # Same verification gate as the sibling Linux test above.
  _aws_verify_zip() { return 0; }
  run update_aws_cli
  [ "$status" -eq 0 ]
  grep -q "curl.*awscli-exe-linux-aarch64" "${MOCK_CALLS_FILE}"
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

@test "update_rust does not call curl for nextest when nextest is installed (brew manages updates)" {
  export UBUNTU=1
  export HAS_RUST=1
  unset MACOS
  local _bin_dir="${BATS_TEST_TMPDIR}/nextest_bin"
  mkdir -p "${_bin_dir}"
  printf '#!/usr/bin/env bash\n' > "${_bin_dir}/cargo-nextest" && chmod +x "${_bin_dir}/cargo-nextest"
  mkdir -p "${FAKE_HOME}/.cargo/bin"
  export PATH="${_bin_dir}:${PATH}"
  run update_rust
  [ "$status" -eq 0 ]
  run grep "curl.*nexte.st" "${MOCK_CALLS_FILE:-/dev/null}"
  [ "$status" -ne 0 ]
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
