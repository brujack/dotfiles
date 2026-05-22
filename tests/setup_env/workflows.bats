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

# ── setup_claude_mcp ─────────────────────────────────────────────────────────

@test "setup_claude_mcp generates mcp.json when GITHUB_PAT is set" {
  export _OVERRIDE_AI_CONFIG_DIR="${BATS_TEST_TMPDIR}/ai-config"
  export GITHUB_PAT="test-token-abc"
  mkdir -p "${_OVERRIDE_AI_CONFIG_DIR}/.claude"
  printf '{"mcpServers":{"github":{"headers":{"Authorization":"Bearer ${GITHUB_PAT}"}}}}\n' \
    > "${_OVERRIDE_AI_CONFIG_DIR}/.claude/mcp.json.template"
  setup_claude_mcp
  [[ -f "${HOME}/.claude/mcp.json" ]]
  grep -q "test-token-abc" "${HOME}/.claude/mcp.json"
  ! grep -q '\${GITHUB_PAT}' "${HOME}/.claude/mcp.json"
}

@test "setup_claude_mcp returns 0 when GITHUB_PAT is unset" {
  export _OVERRIDE_AI_CONFIG_DIR="${BATS_TEST_TMPDIR}/ai-config"
  unset GITHUB_PAT
  mkdir -p "${_OVERRIDE_AI_CONFIG_DIR}/.claude"
  printf '{"mcpServers":{"github":{"headers":{"Authorization":"Bearer ${GITHUB_PAT}"}}}}\n' \
    > "${_OVERRIDE_AI_CONFIG_DIR}/.claude/mcp.json.template"
  local _rc=0
  setup_claude_mcp || _rc=$?
  [ "${_rc}" -eq 0 ]
}

@test "setup_claude_mcp does not create mcp.json when GITHUB_PAT is unset" {
  export _OVERRIDE_AI_CONFIG_DIR="${BATS_TEST_TMPDIR}/ai-config"
  unset GITHUB_PAT
  mkdir -p "${_OVERRIDE_AI_CONFIG_DIR}/.claude"
  printf '{"test":"${GITHUB_PAT}"}\n' \
    > "${_OVERRIDE_AI_CONFIG_DIR}/.claude/mcp.json.template"
  setup_claude_mcp
  [[ ! -f "${HOME}/.claude/mcp.json" ]]
}

@test "setup_claude_mcp removes broken symlink before generating file" {
  export _OVERRIDE_AI_CONFIG_DIR="${BATS_TEST_TMPDIR}/ai-config"
  export GITHUB_PAT="test-token"
  mkdir -p "${_OVERRIDE_AI_CONFIG_DIR}/.claude"
  printf '{"auth":"Bearer ${GITHUB_PAT}"}\n' \
    > "${_OVERRIDE_AI_CONFIG_DIR}/.claude/mcp.json.template"
  mkdir -p "${HOME}/.claude"
  # Create broken symlink (points to non-existent file)
  ln -s "${BATS_TEST_TMPDIR}/nonexistent_target" "${HOME}/.claude/mcp.json"
  setup_claude_mcp
  [[ -f "${HOME}/.claude/mcp.json" ]]
  [[ ! -L "${HOME}/.claude/mcp.json" ]]
}

@test "setup_claude_mcp returns 1 when envsubst fails" {
  export _OVERRIDE_AI_CONFIG_DIR="${BATS_TEST_TMPDIR}/ai-config"
  export GITHUB_PAT="test-token"
  mkdir -p "${_OVERRIDE_AI_CONFIG_DIR}/.claude"
  printf '{"auth":"Bearer ${GITHUB_PAT}"}\n' \
    > "${_OVERRIDE_AI_CONFIG_DIR}/.claude/mcp.json.template"
  envsubst() { return 1; }
  run setup_claude_mcp
  [ "$status" -eq 1 ]
}

# ── run_setup_user — coarse-grained (macOS) ───────────────────────────────────

@test "run_setup_user clones dotfiles repo on macOS when missing" {
  export MACOS=1
  unset LINUX UBUNTU
  rm -rf "${PERSONAL_GITREPOS}/${DOTFILES}"
  run_setup_user
  grep -q "git clone" "${MOCK_CALLS_FILE}"
}

@test "run_setup_user creates HOME/bin on macOS" {
  export MACOS=1
  unset LINUX UBUNTU
  run_setup_user
  [ -d "${HOME}/bin" ]
}

@test "run_setup_user creates HOME/go-work on macOS" {
  export MACOS=1
  unset LINUX UBUNTU
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

@test "run_setup_user calls setup_claude_mcp" {
  export MACOS=1
  unset LINUX UBUNTU
  local _called=0
  setup_claude_mcp() { _called=1; return 0; }
  run_setup_user
  [ "${_called}" -eq 1 ]
}

@test "run_setup_user returns non-zero when setup_claude_mcp fails" {
  export MACOS=1
  unset LINUX UBUNTU
  setup_claude_mcp() { return 1; }
  run run_setup_user
  [ "$status" -ne 0 ]
}

# ── setup_claude_plugins ──────────────────────────────────────────────────────

@test "setup_claude_plugins installs plugin when not listed" {
  export MOCK_CLAUDE_PLUGINS_LIST_OUTPUT=""
  setup_claude_plugins
  grep -q "claude plugins install superpowers@claude-plugins-official" "${MOCK_CALLS_FILE}"
}

@test "setup_claude_plugins skips install when plugin already listed" {
  export MOCK_CLAUDE_PLUGINS_LIST_OUTPUT="superpowers@claude-plugins-official"
  setup_claude_plugins
  ! grep -q "claude plugins install superpowers@claude-plugins-official" "${MOCK_CALLS_FILE}"
}

@test "run_setup_user calls setup_claude_plugins" {
  export MACOS=1
  unset LINUX UBUNTU
  local _called=0
  setup_claude_plugins() { _called=1; return 0; }
  run_setup_user
  [ "${_called}" -eq 1 ]
}

@test "run_setup_user returns non-zero when setup_claude_plugins fails" {
  export MACOS=1
  unset LINUX UBUNTU
  setup_claude_plugins() { return 1; }
  run run_setup_user
  [ "$status" -ne 0 ]
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

# ── install_macos_packages ────────────────────────────────────────────────────

@test "install_macos_packages symlinks Brewfile at BREWFILE_LOC" {
  export MACOS=1
  unset LINUX UBUNTU
  touch "${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile"
  touch "${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile.gui"
  touch "${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile.devtools"
  mkdir -p "${HOME}/scripts"
  touch "${HOME}/scripts/.osx.sh"
  chmod +x "${HOME}/scripts/.osx.sh"
  run install_macos_packages
  [[ -L "${BREWFILE_LOC}/Brewfile" ]]
}

@test "install_macos_packages calls brew update when brew is present" {
  export MACOS=1
  unset LINUX UBUNTU
  touch "${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile"
  touch "${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile.gui"
  touch "${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile.devtools"
  mkdir -p "${HOME}/scripts"
  touch "${HOME}/scripts/.osx.sh"
  chmod +x "${HOME}/scripts/.osx.sh"
  run install_macos_packages
  grep -q "brew update" "${MOCK_CALLS_FILE}"
}

@test "install_macos_packages calls softwareupdate" {
  export MACOS=1
  unset LINUX UBUNTU
  touch "${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile"
  touch "${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile.gui"
  touch "${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile.devtools"
  mkdir -p "${HOME}/scripts"
  touch "${HOME}/scripts/.osx.sh"
  chmod +x "${HOME}/scripts/.osx.sh"
  run install_macos_packages
  grep -q "softwareupdate" "${MOCK_CALLS_FILE}"
}

@test "install_macos_packages returns non-zero when brew_update fails" {
  export MACOS=1
  unset LINUX UBUNTU
  touch "${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile"
  mkdir -p "${HOME}/scripts"
  touch "${HOME}/scripts/.osx.sh"
  chmod +x "${HOME}/scripts/.osx.sh"
  brew_update() { return 1; }
  run install_macos_packages
  [ "$status" -ne 0 ]
}

@test "install_macos_packages does not call softwareupdate when brew_update fails" {
  export MACOS=1
  unset LINUX UBUNTU
  touch "${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile"
  mkdir -p "${HOME}/scripts"
  touch "${HOME}/scripts/.osx.sh"
  chmod +x "${HOME}/scripts/.osx.sh"
  brew_update() { return 1; }
  run install_macos_packages
  ! grep -q "softwareupdate" "${MOCK_CALLS_FILE}"
}

@test "install_macos_packages returns non-zero when install_macos_casks fails" {
  export MACOS=1
  unset LINUX UBUNTU
  touch "${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile"
  mkdir -p "${HOME}/scripts"
  touch "${HOME}/scripts/.osx.sh"
  chmod +x "${HOME}/scripts/.osx.sh"
  install_macos_casks() { return 1; }
  run install_macos_packages
  [ "$status" -ne 0 ]
}

@test "install_macos_packages does not call softwareupdate when install_macos_casks fails" {
  export MACOS=1
  unset LINUX UBUNTU
  touch "${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile"
  mkdir -p "${HOME}/scripts"
  touch "${HOME}/scripts/.osx.sh"
  chmod +x "${HOME}/scripts/.osx.sh"
  install_macos_casks() { return 1; }
  run install_macos_packages
  ! grep -q "softwareupdate" "${MOCK_CALLS_FILE}"
}

# ── install_ubuntu_packages ───────────────────────────────────────────────────

@test "install_ubuntu_packages calls apt update on Ubuntu Noble" {
  unset MACOS
  export LINUX=1
  export UBUNTU=1
  export NOBLE=1
  # Create mock xargs files to prevent xargs errors
  touch ubuntu_common_packages.txt ubuntu_2404_packages.txt
  # Create directory for apt sources
  mkdir -p /etc/apt/sources.list.d /etc/apt/keyrings /etc/apt/trusted.gpg.d 2>/dev/null || true
  run install_ubuntu_packages
  grep -q "apt update" "${MOCK_CALLS_FILE}"
}

@test "install_ubuntu_packages calls nala on Noble" {
  unset MACOS
  export LINUX=1
  export UBUNTU=1
  export NOBLE=1
  # Create mock xargs files to prevent xargs errors
  touch ubuntu_common_packages.txt ubuntu_2404_packages.txt
  # Create directory for apt sources
  mkdir -p /etc/apt/sources.list.d /etc/apt/keyrings /etc/apt/trusted.gpg.d 2>/dev/null || true
  run install_ubuntu_packages
  grep -q "nala" "${MOCK_CALLS_FILE}"
}

@test "install_ubuntu_packages installs snap packages when HAS_SNAP" {
  unset MACOS
  export LINUX=1
  export UBUNTU=1
  export NOBLE=1
  export HAS_SNAP=1
  # Create mock xargs files to prevent xargs errors
  touch ubuntu_common_packages.txt ubuntu_2404_packages.txt ubuntu_workstation_packages.txt ubuntu_workstation_snap_packages.txt
  # Create directory for apt sources
  mkdir -p /etc/apt/sources.list.d /etc/apt/keyrings /etc/apt/trusted.gpg.d 2>/dev/null || true
  run install_ubuntu_packages
  grep -q "snap" "${MOCK_CALLS_FILE}"
}

# ── install_aws_tools ─────────────────────────────────────────────────────────

@test "install_aws_tools calls wget for AWSCLIV2.pkg on macOS with HAS_AWS" {
  export MACOS=1
  export HAS_AWS=1
  unset LINUX
  mkdir -p "${HOME}/software_downloads/awscli"
  install_aws_tools
  grep -q "AWSCLIV2.pkg" "${MOCK_CALLS_FILE}"
}

@test "install_aws_tools calls wget for awscliv2.zip on Linux with HAS_AWS" {
  unset MACOS
  export LINUX=1
  export HAS_AWS=1
  mkdir -p "${HOME}/software_downloads/awscli"
  install_aws_tools
  grep -q "awscliv2.zip" "${MOCK_CALLS_FILE}"
}

@test "install_aws_tools is a no-op when HAS_AWS is unset" {
  export MACOS=1
  unset HAS_AWS LINUX
  install_aws_tools
  ! grep -q "awscli" "${MOCK_CALLS_FILE}"
}

# ── install_ruby_tools ────────────────────────────────────────────────────────

@test "install_ruby_tools downloads ruby-install on Linux when absent" {
  unset MACOS
  export LINUX=1
  export UBUNTU=1
  export NOBLE=1
  install_ruby_tools
  grep -q "ruby-install" "${MOCK_CALLS_FILE}"
}

@test "install_ruby_tools downloads chruby on Linux Focal" {
  unset MACOS
  export LINUX=1
  export UBUNTU=1
  export FOCAL=1
  install_ruby_tools
  grep -q "chruby" "${MOCK_CALLS_FILE}"
}

@test "install_ruby_tools is a no-op on macOS" {
  export MACOS=1
  unset LINUX UBUNTU
  install_ruby_tools
  ! grep -q "ruby-install" "${MOCK_CALLS_FILE}"
}

# ── install_ruby ──────────────────────────────────────────────────────────────

@test "install_ruby calls ruby-install on macOS when ruby absent" {
  export MACOS=1
  unset LINUX UBUNTU
  install_ruby
  grep -q "ruby-install" "${MOCK_CALLS_FILE}"
}

@test "install_ruby calls rbenv on Noble when ruby absent" {
  unset MACOS
  export LINUX=1
  export UBUNTU=1
  export NOBLE=1
  install_ruby
  grep -q "rbenv" "${MOCK_CALLS_FILE}"
}

@test "install_ruby skips when ruby dir already exists" {
  export MACOS=1
  unset LINUX UBUNTU
  mkdir -p "${HOME}/.rubies/ruby-${RUBY_VER}/bin"
  install_ruby
  ! grep -q "ruby-install" "${MOCK_CALLS_FILE}"
}

# ── install_github_cli_linux ──────────────────────────────────────────────────

@test "install_github_cli_linux calls apt install gh on Ubuntu" {
  unset MACOS
  export LINUX=1
  export UBUNTU=1
  export NOBLE=1
  install_github_cli_linux
  grep -q "apt install gh" "${MOCK_CALLS_FILE}"
}

# ── setup_kitchen ─────────────────────────────────────────────────────────────

@test "setup_kitchen calls gem install test-kitchen on macOS" {
  export MACOS=1
  unset LINUX UBUNTU
  export CHRUBY_LOC="${BATS_TEST_TMPDIR}/chruby_stub"
  mkdir -p "${CHRUBY_LOC}/chruby"
  printf "# stub\n" > "${CHRUBY_LOC}/chruby/chruby.sh"
  printf "# stub\n" > "${CHRUBY_LOC}/chruby/auto.sh"
  setup_kitchen
  grep -q "gem install test-kitchen" "${MOCK_CALLS_FILE}"
}

@test "setup_kitchen calls gem install test-kitchen on Linux Jammy" {
  unset MACOS
  export LINUX=1
  export UBUNTU=1
  export JAMMY=1
  export CHRUBY_LOC="${BATS_TEST_TMPDIR}/chruby_stub"
  mkdir -p "${CHRUBY_LOC}/chruby"
  printf "# stub\n" > "${CHRUBY_LOC}/chruby/chruby.sh"
  printf "# stub\n" > "${CHRUBY_LOC}/chruby/auto.sh"
  setup_kitchen
  grep -q "gem install test-kitchen" "${MOCK_CALLS_FILE}"
}

@test "setup_kitchen calls rbenv on Noble" {
  unset MACOS
  export LINUX=1
  export UBUNTU=1
  export NOBLE=1
  setup_kitchen
  grep -q "rbenv" "${MOCK_CALLS_FILE}"
}

# ── setup_ansible ─────────────────────────────────────────────────────────────

@test "setup_ansible calls pyenv install when Python version absent" {
  export MACOS=1
  unset LINUX
  export HAS_DEVTOOLS=1
  setup_ansible
  grep -q "pyenv" "${MOCK_CALLS_FILE}"
}

@test "setup_ansible calls pip install ansible" {
  export MACOS=1
  unset LINUX
  export HAS_DEVTOOLS=1
  setup_ansible
  grep -q "pip install ansible" "${MOCK_CALLS_FILE}"
}

@test "setup_ansible skips pip when HAS_DEVTOOLS is unset" {
  export MACOS=1
  unset LINUX HAS_DEVTOOLS
  setup_ansible
  ! grep -q "pip install ansible" "${MOCK_CALLS_FILE}"
}

# ── clone_personal_repos ──────────────────────────────────────────────────────

@test "clone_personal_repos calls git clone for each absent repo" {
  export MACOS=1
  clone_personal_repos
  grep -q "git clone" "${MOCK_CALLS_FILE}"
}

@test "clone_personal_repos skips git clone when repo already exists" {
  export MACOS=1
  # Pre-create the dotfiles repo dir so its clone is skipped
  mkdir -p "${PERSONAL_GITREPOS}/dotfiles"
  clone_personal_repos
  # dotfiles dir already exists — its clone must not appear in the call log
  ! grep -q "git clone.*dotfiles" "${MOCK_CALLS_FILE}"
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

@test "run_update mas section summary shows updated app name and version" {
  export MACOS=1
  unset LINUX UBUNTU
  export UPDATE_MAS=1
  unset UPDATE_BREW UPDATE_PIP UPDATE_GEMS UPDATE_CLAUDE
  export UPDATE_LOG_PATH="${BATS_TEST_TMPDIR}/update.log"
  export MOCK_MAS_UPGRADE_OUTPUT="==> Updated Windows App (11.3.5)"
  run run_update
  [[ "$output" == *"1 app(s) (Windows App (11.3.5))"* ]]
}

@test "run_update mas section summary shows count for multiple updated apps" {
  export MACOS=1
  unset LINUX UBUNTU
  export UPDATE_MAS=1
  unset UPDATE_BREW UPDATE_PIP UPDATE_GEMS UPDATE_CLAUDE
  export UPDATE_LOG_PATH="${BATS_TEST_TMPDIR}/update.log"
  export MOCK_MAS_UPGRADE_OUTPUT="$(printf '==> Updated App One (1.0)\n==> Updated App Two (2.0)')"
  run run_update
  [[ "$output" == *"2 app(s)"* ]]
}

@test "run_update mas section summary shows no changes when mas upgrade reports no updates" {
  export MACOS=1
  unset LINUX UBUNTU
  export UPDATE_MAS=1
  unset UPDATE_BREW UPDATE_PIP UPDATE_GEMS UPDATE_CLAUDE
  export UPDATE_LOG_PATH="${BATS_TEST_TMPDIR}/update.log"
  export MOCK_MAS_UPGRADE_OUTPUT=""
  run run_update
  [[ "$output" == *"no changes"* ]]
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

@test "run_brew_install returns non-zero when brew_update fails" {
  export MACOS=1
  unset LINUX UBUNTU
  touch "${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile"
  brew_update() { return 1; }
  run run_brew_install
  [ "$status" -ne 0 ]
}

@test "run_brew_install does not call brew cleanup when brew_update fails" {
  export MACOS=1
  unset LINUX UBUNTU
  touch "${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile"
  brew_update() { return 1; }
  run run_brew_install
  ! grep -q "brew cleanup" "${MOCK_CALLS_FILE}"
}

@test "run_brew_install returns non-zero when install_macos_casks fails" {
  export MACOS=1
  unset LINUX UBUNTU
  touch "${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile"
  install_macos_casks() { return 1; }
  run run_brew_install
  [ "$status" -ne 0 ]
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

# ── _fetch_github_latest ─────────────────────────────────────────────────────

@test "_fetch_github_latest extracts version and strips v prefix" {
  export MOCK_CURL_STDOUT='  "tag_name": "v1.23.4",'
  run _fetch_github_latest "some/repo"
  [ "$status" -eq 0 ]
  [ "$output" = "1.23.4" ]
}

@test "_fetch_github_latest returns version unchanged when no v prefix" {
  export MOCK_CURL_STDOUT='  "tag_name": "1.23.4",'
  run _fetch_github_latest "some/repo"
  [ "$status" -eq 0 ]
  [ "$output" = "1.23.4" ]
}

@test "_fetch_github_latest returns empty when curl fails" {
  export MOCK_CURL_EXIT=1
  run _fetch_github_latest "some/repo"
  [ -z "$output" ]
}

@test "_fetch_github_latest adds Authorization header when GITHUB_TOKEN is set" {
  export GITHUB_TOKEN="mytoken"
  export MOCK_CURL_STDOUT='  "tag_name": "v2.0.0",'
  _fetch_github_latest "some/repo"
  grep -q "Authorization: Bearer mytoken" "${MOCK_CALLS_FILE}"
}

@test "_fetch_github_latest omits Authorization header without GITHUB_TOKEN" {
  unset GITHUB_TOKEN
  export MOCK_CURL_STDOUT='  "tag_name": "v1.0.0",'
  _fetch_github_latest "some/repo"
  ! grep -q "Authorization" "${MOCK_CALLS_FILE}"
}

# ── run_check_versions — tool inclusion ───────────────────────────────────────

@test "run_check_versions checks gitleaks version" {
  local _checked_tools="${BATS_TEST_TMPDIR}/checked_tools"
  _check_one_version() {
    printf '%s\n' "$1" >> "${_checked_tools}"
  }
  run_check_versions
  grep -q "gitleaks" "${_checked_tools}"
}

# ── run_update summary integration ────────────────────────────────────────────

@test "run_update calls _update_summary at end" {
  export MACOS=1
  unset LINUX UBUNTU REDHAT FEDORA CENTOS
  export UPDATE_BREW=1
  export UPDATE_LOG_PATH="${BATS_TEST_TMPDIR}/update.log"
  run run_update
  [[ "$output" == *"Update Summary"* ]]
}

@test "run_update records brew section status" {
  export MACOS=1
  unset LINUX UBUNTU REDHAT FEDORA CENTOS
  export UPDATE_BREW=1
  export UPDATE_LOG_PATH="${BATS_TEST_TMPDIR}/update.log"
  run run_update
  [[ "$output" == *"brew"* ]]
}

@test "run_update skips sections when specific flag is set" {
  export MACOS=1
  unset LINUX UBUNTU REDHAT FEDORA CENTOS
  export UPDATE_BREW=1
  export UPDATE_LOG_PATH="${BATS_TEST_TMPDIR}/update.log"
  run run_update
  [[ "$output" == *"[SKIP]"* ]]
}

@test "run_update appends to log file" {
  export MACOS=1
  unset LINUX UBUNTU
  export UPDATE_BREW=1
  export UPDATE_LOG_PATH="${BATS_TEST_TMPDIR}/update.log"
  run_update
  [ -f "${BATS_TEST_TMPDIR}/update.log" ]
  grep -q "Update Summary" "${BATS_TEST_TMPDIR}/update.log"
}

@test "run_update skips softwareupdate on Linux" {
  export LINUX=1
  export UBUNTU=1
  unset MACOS
  export UPDATE_LOG_PATH="${BATS_TEST_TMPDIR}/update.log"
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  run_update
  # softwareupdate must not have been called
  if [[ -f "${MOCK_CALLS_FILE}" ]]; then
    ! grep -q "^softwareupdate" "${MOCK_CALLS_FILE}"
  fi
}

# ── return-code propagation: run_setup_user ───────────────────────────────────

# ── run_update — Linux system packages block ──────────────────────────────

@test "run_update calls dpkg-query on Ubuntu with no flags" {
  unset MACOS
  export LINUX=1
  export UBUNTU=1
  export NOBLE=1
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  export UPDATE_LOG_PATH="${BATS_TEST_TMPDIR}/update.log"
  unset UPDATE_BREW UPDATE_PIP UPDATE_GEMS UPDATE_MAS UPDATE_CLAUDE UPDATE_PKGS
  run_update
  grep -q "dpkg-query" "${MOCK_CALLS_FILE}"
}

@test "run_update Linux packages block skips apt with not applicable on macOS" {
  export MACOS=1
  unset LINUX UBUNTU
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  export UPDATE_LOG_PATH="${BATS_TEST_TMPDIR}/update.log"
  unset UPDATE_BREW UPDATE_PIP UPDATE_GEMS UPDATE_MAS UPDATE_CLAUDE UPDATE_PKGS
  run_update
  grep -q "SKIP" "${_UPDATE_TMPDIR}/status_apt"
  grep -q "not applicable" "${_UPDATE_TMPDIR}/result_apt"
}

@test "run_update Linux packages block skips apt and snap when UPDATE_PKGS not set and not run_all" {
  export MACOS=1
  unset LINUX UBUNTU
  export UPDATE_BREW=1
  unset UPDATE_PIP UPDATE_GEMS UPDATE_MAS UPDATE_CLAUDE UPDATE_PKGS
  export UPDATE_LOG_PATH="${BATS_TEST_TMPDIR}/update.log"
  run_update
  grep -q "SKIP" "${_UPDATE_TMPDIR}/status_apt"
  grep -q "flag not set" "${_UPDATE_TMPDIR}/result_apt"
  grep -q "flag not set" "${_UPDATE_TMPDIR}/result_snap"
}

@test "run_update Linux packages block runs when UPDATE_PKGS is set on Ubuntu" {
  unset MACOS
  export LINUX=1
  export UBUNTU=1
  export NOBLE=1
  export UPDATE_PKGS=1
  unset UPDATE_BREW UPDATE_PIP UPDATE_GEMS UPDATE_MAS UPDATE_CLAUDE
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  export UPDATE_LOG_PATH="${BATS_TEST_TMPDIR}/update.log"
  run_update
  grep -q "dpkg-query" "${MOCK_CALLS_FILE}"
}

@test "run_update does not call update_system_packages from mas block on Linux" {
  unset MACOS
  export LINUX=1
  export UBUNTU=1
  export NOBLE=1
  export UPDATE_MAS=1
  unset UPDATE_BREW UPDATE_PIP UPDATE_GEMS UPDATE_CLAUDE UPDATE_PKGS
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  export UPDATE_LOG_PATH="${BATS_TEST_TMPDIR}/update.log"
  run_update
  # dpkg-query is called by update_system_packages on Ubuntu — must NOT appear
  ! grep -q "dpkg-query" "${MOCK_CALLS_FILE}"
}

# ── return-code propagation: run_setup_user ───────────────────────────────────

@test "run_setup_user returns non-zero when install_rosetta fails" {
  export MACOS=1
  unset LINUX UBUNTU
  install_rosetta() { return 1; }
  run run_setup_user
  [ "$status" -ne 0 ]
}

@test "run_setup_user does not call install_git when install_rosetta fails" {
  export MACOS=1
  unset LINUX UBUNTU
  install_rosetta() { return 1; }
  install_git() { printf "install_git\n" >> "${MOCK_CALLS_FILE}"; return 0; }
  run run_setup_user
  ! grep -q "install_git" "${MOCK_CALLS_FILE}"
}

@test "run_setup_user returns non-zero when clone_or_update_dotfiles fails" {
  export MACOS=1
  unset LINUX UBUNTU
  clone_or_update_dotfiles() { return 1; }
  run run_setup_user
  [ "$status" -ne 0 ]
}

@test "run_setup_user returns non-zero when setup_dotfile_symlinks fails" {
  export MACOS=1
  unset LINUX UBUNTU
  setup_dotfile_symlinks() { return 1; }
  run run_setup_user
  [ "$status" -ne 0 ]
}

@test "run_setup_user returns non-zero when setup_zsh_as_default_shell fails" {
  export MACOS=1
  unset LINUX UBUNTU
  setup_zsh_as_default_shell() { return 1; }
  run run_setup_user
  [ "$status" -ne 0 ]
}

# ── return-code propagation: run_setup_or_developer ───────────────────────────

@test "run_setup_or_developer returns non-zero when install_ubuntu_packages fails" {
  export UBUNTU=1
  export NOBLE=1
  unset MACOS LINUX
  install_ubuntu_packages() { return 1; }
  run run_setup_or_developer
  [ "$status" -ne 0 ]
}

@test "run_setup_or_developer does not call install_aws_tools when install_ubuntu_packages fails" {
  export UBUNTU=1
  export NOBLE=1
  unset MACOS LINUX
  install_ubuntu_packages() { return 1; }
  install_aws_tools() { printf "install_aws_tools\n" >> "${MOCK_CALLS_FILE}"; return 0; }
  run run_setup_or_developer
  ! grep -q "install_aws_tools" "${MOCK_CALLS_FILE}"
}

@test "run_setup_or_developer returns non-zero when install_aws_tools fails" {
  export MACOS=1
  unset LINUX UBUNTU
  install_macos_packages() { return 0; }
  install_aws_tools() { return 1; }
  run run_setup_or_developer
  [ "$status" -ne 0 ]
}

# ── return-code propagation: run_developer_or_ansible ────────────────────────

@test "run_developer_or_ansible returns non-zero when install_ruby_tools fails" {
  unset MACOS LINUX UBUNTU
  install_ruby_tools() { return 1; }
  run run_developer_or_ansible
  [ "$status" -ne 0 ]
}

@test "run_developer_or_ansible does not call install_ruby when install_ruby_tools fails" {
  unset MACOS LINUX UBUNTU
  install_ruby_tools() { return 1; }
  install_ruby() { printf "install_ruby\n" >> "${MOCK_CALLS_FILE}"; return 0; }
  run run_developer_or_ansible
  ! grep -q "install_ruby" "${MOCK_CALLS_FILE}"
}

@test "run_developer_or_ansible returns non-zero when setup_kitchen fails" {
  unset MACOS LINUX UBUNTU
  install_ruby_tools() { return 0; }
  install_ruby()       { return 0; }
  setup_kitchen()      { return 1; }
  run run_developer_or_ansible
  [ "$status" -ne 0 ]
}

@test "run_developer_or_ansible does not call setup_ansible when setup_kitchen fails" {
  unset MACOS LINUX UBUNTU
  install_ruby_tools() { return 0; }
  install_ruby()       { return 0; }
  setup_kitchen()      { return 1; }
  setup_ansible()      { printf "setup_ansible\n" >> "${MOCK_CALLS_FILE}"; return 0; }
  run run_developer_or_ansible
  ! grep -q "setup_ansible" "${MOCK_CALLS_FILE}"
}

# ── process_args --pkgs-only ──────────────────────────────────────────────

@test "process_args --pkgs-only sets UPDATE_PKGS" {
  unset UPDATE_PKGS
  process_args --pkgs-only
  [ -n "${UPDATE_PKGS:-}" ]
}

@test "process_args --pkgs-only twice does not crash" {
  unset UPDATE_PKGS
  process_args --pkgs-only
  local _rc=0
  process_args --pkgs-only || _rc=$?
  [ "${_rc}" -eq 0 ]
}

@test "_any_update_flag returns true when UPDATE_PKGS is set" {
  unset UPDATE_BREW UPDATE_PIP UPDATE_GEMS UPDATE_MAS UPDATE_CLAUDE UPDATE_PKGS
  export UPDATE_PKGS=1
  _any_update_flag
}

@test "_any_update_flag returns false when only UPDATE_PKGS is unset among all flags" {
  unset UPDATE_BREW UPDATE_PIP UPDATE_GEMS UPDATE_MAS UPDATE_CLAUDE UPDATE_PKGS
  local _rc=0
  _any_update_flag || _rc=$?
  [ "${_rc}" -ne 0 ]
}
