#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_setup_env
  load_mocks
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  export MOCK_BATS_VER="${BATS_VER}"
}

teardown() {
  rm -f "${MOCK_CALLS_FILE:-}"
  rm -rf "/tmp/bats-core-${BATS_VER}" "/tmp/bats.tar.gz"
}

# ── brew_formula_installed ───────────────────────────────────────────────────

@test "brew_formula_installed returns 0 when formula is listed" {
  export MOCK_BREW_LIST_FORMULA="git wget"
  run brew_formula_installed git
  [ "$status" -eq 0 ]
}

@test "brew_formula_installed returns 1 when formula is not listed" {
  export MOCK_BREW_LIST_FORMULA="wget"
  run brew_formula_installed git
  [ "$status" -eq 1 ]
}

@test "brew_formula_installed uses full-name flag for tap-qualified formulas" {
  export MOCK_BREW_LIST_FORMULA="hashicorp/tap/vault"
  run brew_formula_installed hashicorp/tap/vault
  [ "$status" -eq 0 ]
  grep -q "brew list --formula --full-name" "${MOCK_CALLS_FILE}"
}

# ── brew_cask_installed ──────────────────────────────────────────────────────

@test "brew_cask_installed returns 0 when cask is listed" {
  export MOCK_BREW_LIST_CASK="docker firefox"
  run brew_cask_installed docker
  [ "$status" -eq 0 ]
}

@test "brew_cask_installed returns 1 when cask is not listed" {
  export MOCK_BREW_LIST_CASK="firefox"
  run brew_cask_installed docker
  [ "$status" -eq 1 ]
}

# ── brew_install_formula ─────────────────────────────────────────────────────

@test "brew_install_formula calls brew install when formula is absent" {
  export MOCK_BREW_LIST_FORMULA=""
  run brew_install_formula git
  [ "$status" -eq 0 ]
  grep -q "brew install git" "${MOCK_CALLS_FILE}"
}

@test "brew_install_formula does not call brew install when formula is present" {
  export MOCK_BREW_LIST_FORMULA="git"
  run brew_install_formula git
  [ "$status" -eq 0 ]
  ! grep -q "brew install git" "${MOCK_CALLS_FILE}"
}

# ── brew_tap_if_missing ──────────────────────────────────────────────────────

@test "brew_tap_if_missing calls brew tap when tap is absent" {
  export MOCK_BREW_TAPS=""
  run brew_tap_if_missing hashicorp/tap
  [ "$status" -eq 0 ]
  grep -q "brew tap hashicorp/tap" "${MOCK_CALLS_FILE}"
}

@test "brew_tap_if_missing does not call brew tap when tap is present" {
  export MOCK_BREW_TAPS="hashicorp/tap"
  run brew_tap_if_missing hashicorp/tap
  [ "$status" -eq 0 ]
  # Only one call: the listing call, not a tap add call
  count=$(grep -c "brew tap" "${MOCK_CALLS_FILE}")
  [ "$count" -eq 1 ]
  grep -q "brew tap$" "${MOCK_CALLS_FILE}"
}

# ── install_bats ─────────────────────────────────────────────────────────────

@test "install_bats skips install when bats is already present" {
  unset MOCK_WHICH_MISSING  # which finds bats normally
  export UBUNTU=1
  run install_bats
  [ "$status" -eq 0 ]
  [[ "$output" == *"already installed"* ]]
  ! grep -q "apt-get" "${MOCK_CALLS_FILE}"
}

@test "install_bats on Ubuntu calls apt-get install when bats is absent" {
  export MOCK_WHICH_MISSING=bats
  export UBUNTU=1
  unset REDHAT CENTOS FEDORA
  run install_bats
  [ "$status" -eq 0 ]
  grep -q "apt-get install -y bats" "${MOCK_CALLS_FILE}"
}

@test "install_bats on RHEL downloads bats-core tarball from GitHub" {
  export MOCK_WHICH_MISSING=bats
  export REDHAT=1
  unset UBUNTU CENTOS FEDORA
  run install_bats
  [ "$status" -eq 0 ]
  grep -q "curl.*bats-core.*${BATS_VER}.*tar.gz" "${MOCK_CALLS_FILE}"
}

@test "install_bats returns 1 on unsupported platform" {
  export MOCK_WHICH_MISSING=bats
  unset UBUNTU REDHAT CENTOS FEDORA
  run install_bats
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unsupported platform"* ]]
}

# ── ensure_not_root ──────────────────────────────────────────────────────────

@test "ensure_not_root returns 0 when not root" {
  export MOCK_ID_U=1000
  run ensure_not_root
  [ "$status" -eq 0 ]
}

@test "ensure_not_root returns 1 and prints message when root" {
  export MOCK_ID_U=0
  run ensure_not_root
  [ "$status" -eq 1 ]
  [[ "$output" == *"Homebrew cannot run as root"* ]]
}

# ── brew_tap_installed ───────────────────────────────────────────────────────

@test "brew_tap_installed returns 0 when tap is listed" {
  export MOCK_BREW_TAPS="hashicorp/tap homebrew/cask-versions"
  run brew_tap_installed hashicorp/tap
  [ "$status" -eq 0 ]
}

@test "brew_tap_installed returns 1 when tap is not listed" {
  export MOCK_BREW_TAPS=""
  run brew_tap_installed hashicorp/tap
  [ "$status" -eq 1 ]
}

# ── brew_install_cask ────────────────────────────────────────────────────────

@test "brew_install_cask calls brew install --cask when cask is absent" {
  export MOCK_BREW_LIST_CASK=""
  run brew_install_cask docker
  [ "$status" -eq 0 ]
  grep -q "brew install --cask --force --overwrite docker" "${MOCK_CALLS_FILE}"
}

@test "brew_install_cask does not call brew install when cask is present" {
  export MOCK_BREW_LIST_CASK="docker"
  run brew_install_cask docker
  [ "$status" -eq 0 ]
  ! grep -q "brew install --cask" "${MOCK_CALLS_FILE}"
}

# ── rhel_installed_package ───────────────────────────────────────────────────

@test "rhel_installed_package returns 1 when yum is not available" {
  # command -v is a bash builtin and cannot be intercepted by the which mock.
  # Run in a subprocess without the mocks directory to simulate yum being absent.
  # Source without mocks in PATH so command -v yum fails on macOS
  local clean_path
  clean_path="$(printf "%s" "${PATH}" | tr ':' '\n' | grep -v "tests/mocks" | tr '\n' ':' | sed 's/:$//')"
  run bash -c "
    export PATH='${clean_path}'
    source '${REPO_ROOT}/setup_env.sh'
    rhel_installed_package zsh
  "
  [ "$status" -eq 1 ]
  [[ "$output" == *"yum command not found"* ]]
}

@test "rhel_installed_package returns 0 when yum reports package installed" {
  export MOCK_YUM_LIST_EXIT=0
  run rhel_installed_package zsh
  [ "$status" -eq 0 ]
  grep -q "yum list installed zsh" "${MOCK_CALLS_FILE}"
}

@test "rhel_installed_package returns 1 when yum reports package not installed" {
  export MOCK_YUM_LIST_EXIT=1
  run rhel_installed_package zsh
  [ "$status" -eq 1 ]
  grep -q "yum list installed zsh" "${MOCK_CALLS_FILE}"
}

# ── brew_update ──────────────────────────────────────────────────────────────

@test "brew_update returns 1 when running as root" {
  export MOCK_ID_U=0
  run brew_update
  [ "$status" -eq 1 ]
  [[ "$output" == *"Homebrew cannot run as root"* ]]
}

@test "brew_update calls install_homebrew when brew is absent" {
  export MOCK_ID_U=1000
  export MOCK_XCODE_SELECT_PRINT_PATH_EXIT=0
  # Build a filtered mocks dir without the brew mock
  local tmp_mocks="${BATS_TEST_TMPDIR}/mocks_no_brew"
  mkdir -p "${tmp_mocks}"
  for f in "${REPO_ROOT}/tests/mocks/"*; do
    [[ "$(basename "$f")" == "brew" ]] && continue
    ln -sf "$f" "${tmp_mocks}/$(basename "$f")"
  done
  # Build a PATH that excludes tests/mocks and any directory containing a real brew binary
  local clean_path
  clean_path="$(printf "%s" "${PATH}" | tr ':' '\n' | grep -v "tests/mocks" | tr '\n' ':' | sed 's/:$//')"
  clean_path="$(printf "%s" "${clean_path}" | tr ':' '\n' | while read -r dir; do
    [[ -x "${dir}/brew" ]] || printf "%s\n" "${dir}"
  done | tr '\n' ':' | sed 's/:$//')"
  run bash -c "
    export PATH='${tmp_mocks}:${clean_path}'
    export MOCK_CALLS_FILE='${MOCK_CALLS_FILE}'
    export MOCK_ID_U=1000
    export MOCK_XCODE_SELECT_PRINT_PATH_EXIT=0
    source '${REPO_ROOT}/setup_env.sh'
    brew_update
  "
  # Function exits non-zero (brew stays absent after install_homebrew) — only assert install was reached
  grep -q "curl" "${MOCK_CALLS_FILE}"
}

@test "brew_update returns 1 when brew update fails" {
  export MOCK_ID_U=1000
  export MOCK_BREW_UPDATE_EXIT=1
  run brew_update
  [ "$status" -eq 1 ]
  [[ "$output" == *"Failed to update Homebrew"* ]]
}

@test "brew_update runs full update sequence on success" {
  export MOCK_ID_U=1000
  run brew_update
  [ "$status" -eq 0 ]
  grep -q "brew update" "${MOCK_CALLS_FILE}"
  grep -q "brew upgrade" "${MOCK_CALLS_FILE}"
  grep -q "brew cleanup" "${MOCK_CALLS_FILE}"
  [[ "$output" == *"Homebrew update process completed successfully"* ]]
}

@test "brew_update does not proceed past install_homebrew when install_homebrew fails" {
  # Subshell approach: remove brew from PATH so command -v brew fails, then stub
  # install_homebrew to return 1. With || return 1 in place the function stops before
  # logging "Updating Homebrew"; without it the message appears in output.
  export MOCK_ID_U=1000
  local tmp_mocks="${BATS_TEST_TMPDIR}/mocks_no_brew"
  mkdir -p "${tmp_mocks}"
  for f in "${REPO_ROOT}/tests/mocks/"*; do
    [[ "$(basename "$f")" == "brew" ]] && continue
    ln -sf "$f" "${tmp_mocks}/$(basename "$f")"
  done
  local clean_path
  clean_path="$(printf "%s" "${PATH}" | tr ':' '\n' | grep -v "tests/mocks" | tr '\n' ':' | sed 's/:$//')"
  clean_path="$(printf "%s" "${clean_path}" | tr ':' '\n' | while read -r dir; do
    [[ -x "${dir}/brew" ]] || printf "%s\n" "${dir}"
  done | tr '\n' ':' | sed 's/:$//')"
  run bash -c "
    export PATH='${tmp_mocks}:${clean_path}'
    export MOCK_CALLS_FILE='${MOCK_CALLS_FILE}'
    export MOCK_ID_U=1000
    source '${REPO_ROOT}/setup_env.sh'
    install_homebrew() { return 1; }
    brew_update
  "
  [ "$status" -ne 0 ]
  [[ "$output" != *"Updating Homebrew"* ]]
}

# ── safe_link ─────────────────────────────────────────────────────────────────

@test "safe_link creates symlink when dest does not exist" {
  local src="${BATS_TEST_TMPDIR}/src_file"
  local dest="${BATS_TEST_TMPDIR}/dest_link"
  touch "${src}"
  run safe_link "${src}" "${dest}"
  [ "$status" -eq 0 ]
  [[ -L "${dest}" ]]
}

@test "safe_link is a no-op when dest is already a correct symlink" {
  local src="${BATS_TEST_TMPDIR}/src_file"
  local dest="${BATS_TEST_TMPDIR}/dest_link"
  touch "${src}"
  ln -s "${src}" "${dest}"
  run safe_link "${src}" "${dest}"
  [ "$status" -eq 0 ]
  [[ -L "${dest}" ]]
  [[ "$(readlink "${dest}")" == "${src}" ]]
}

@test "safe_link replaces symlink pointing to wrong target" {
  local src="${BATS_TEST_TMPDIR}/src_file"
  local wrong="${BATS_TEST_TMPDIR}/wrong_target"
  local dest="${BATS_TEST_TMPDIR}/dest_link"
  touch "${src}"
  touch "${wrong}"
  ln -s "${wrong}" "${dest}"
  run safe_link "${src}" "${dest}"
  [ "$status" -eq 0 ]
  [[ -L "${dest}" ]]
  [[ "$(readlink "${dest}")" == "${src}" ]]
}

@test "safe_link backs up existing regular file before linking" {
  local src="${BATS_TEST_TMPDIR}/src_file"
  local dest="${BATS_TEST_TMPDIR}/dest_file"
  touch "${src}"
  touch "${dest}"
  run safe_link "${src}" "${dest}"
  [ "$status" -eq 0 ]
  [[ -L "${dest}" ]]
  [[ -f "${dest}.bak" ]]
}

@test "safe_link output contains Linked message" {
  local src="${BATS_TEST_TMPDIR}/src_file"
  local dest="${BATS_TEST_TMPDIR}/dest_link"
  touch "${src}"
  run safe_link "${src}" "${dest}"
  [ "$status" -eq 0 ]
  [[ "${output}" == *"Linked"* ]]
}

# ── install_macos_casks ───────────────────────────────────────────────────────

@test "install_macos_casks calls brew bundle with main Brewfile" {
  export BREWFILE_LOC="${BATS_TEST_TMPDIR}/brew"
  export PERSONAL_GITREPOS="${BATS_TEST_TMPDIR}/repos"
  export DOTFILES="dotfiles"
  unset HAS_GUI HAS_DEVTOOLS
  run install_macos_casks
  grep -q "brew bundle" "${MOCK_CALLS_FILE}"
}

@test "install_macos_casks calls brew bundle with Brewfile.gui when HAS_GUI is set" {
  export BREWFILE_LOC="${BATS_TEST_TMPDIR}/brew"
  export PERSONAL_GITREPOS="${BATS_TEST_TMPDIR}/repos"
  export DOTFILES="dotfiles"
  export HAS_GUI=1
  unset HAS_DEVTOOLS
  run install_macos_casks
  grep -q "Brewfile\.gui" "${MOCK_CALLS_FILE}"
}

@test "install_macos_casks does not call brew bundle with Brewfile.gui when HAS_GUI is unset" {
  export BREWFILE_LOC="${BATS_TEST_TMPDIR}/brew"
  export PERSONAL_GITREPOS="${BATS_TEST_TMPDIR}/repos"
  export DOTFILES="dotfiles"
  unset HAS_GUI HAS_DEVTOOLS
  run install_macos_casks
  grep -q "brew bundle" "${MOCK_CALLS_FILE}"
  ! grep -q "Brewfile\.gui" "${MOCK_CALLS_FILE}"
}

@test "install_macos_casks calls brew bundle with Brewfile.devtools when HAS_DEVTOOLS is set" {
  export BREWFILE_LOC="${BATS_TEST_TMPDIR}/brew"
  export PERSONAL_GITREPOS="${BATS_TEST_TMPDIR}/repos"
  export DOTFILES="dotfiles"
  unset HAS_GUI
  export HAS_DEVTOOLS=1
  run install_macos_casks
  grep -q "Brewfile\.devtools" "${MOCK_CALLS_FILE}"
}

@test "install_macos_casks does not call brew bundle with Brewfile.devtools when HAS_DEVTOOLS is unset" {
  export BREWFILE_LOC="${BATS_TEST_TMPDIR}/brew"
  export PERSONAL_GITREPOS="${BATS_TEST_TMPDIR}/repos"
  export DOTFILES="dotfiles"
  unset HAS_GUI HAS_DEVTOOLS
  run install_macos_casks
  grep -q "brew bundle" "${MOCK_CALLS_FILE}"
  ! grep -q "Brewfile\.devtools" "${MOCK_CALLS_FILE}"
}

# ── setup_ai_config ──────────────────────────────────────────────────────────

@test "setup_ai_config clones repo when AI_CONFIG_DIR absent" {
  export _OVERRIDE_AI_CONFIG_DIR="${BATS_TEST_TMPDIR}/nonexistent-ai-config"

  run setup_ai_config
  [ "${status}" -eq 0 ]
  grep -q "git clone git@github.com:brujack/ai-config ${BATS_TEST_TMPDIR}/nonexistent-ai-config" "${MOCK_CALLS_FILE}"
}

@test "setup_ai_config skips clone when AI_CONFIG_DIR exists" {
  export _OVERRIDE_AI_CONFIG_DIR="${BATS_TEST_TMPDIR}/ai-config"
  mkdir -p "${_OVERRIDE_AI_CONFIG_DIR}"

  run setup_ai_config
  [ "${status}" -eq 0 ]
  ! grep -q "git clone" "${MOCK_CALLS_FILE}"
}

@test "setup_ai_config returns 1 when clone fails" {
  export MOCK_GIT_CLONE_EXIT=1
  export _OVERRIDE_AI_CONFIG_DIR="${BATS_TEST_TMPDIR}/nonexistent-ai-config"

  local _rc=0
  setup_ai_config || _rc=$?
  [ "${_rc}" -eq 1 ]
}

# ── setup_claude_mcp (AI_CONFIG_DIR seam) ────────────────────────────────────

@test "setup_claude_mcp uses template from AI_CONFIG_DIR" {
  export _OVERRIDE_AI_CONFIG_DIR="${BATS_TEST_TMPDIR}/ai-config"
  export GITHUB_PAT="test-pat-value"
  # Prevent config/local.sh from overriding GITHUB_PAT by pointing PERSONAL_GITREPOS
  # to a temp dir where no config/local.sh exists
  export PERSONAL_GITREPOS="${BATS_TEST_TMPDIR}/git-repos/personal"
  export DOTFILES="dotfiles"
  mkdir -p "${_OVERRIDE_AI_CONFIG_DIR}/.claude"
  printf '{"token": "${GITHUB_PAT}"}\n' > "${_OVERRIDE_AI_CONFIG_DIR}/.claude/mcp.json.template"
  local _home="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${_home}/.claude"
  export HOME="${_home}"

  run setup_claude_mcp
  [ "${status}" -eq 0 ]
  grep -q "test-pat-value" "${_home}/.claude/mcp.json"
}

# ── setup_dotfile_symlinks (AI_CONFIG_DIR seam) ──────────────────────────────

@test "setup_dotfile_symlinks creates .claude symlinks from AI_CONFIG_DIR" {
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  export _OVERRIDE_AI_CONFIG_DIR="${BATS_TEST_TMPDIR}/ai-config"
  mkdir -p "${_OVERRIDE_AI_CONFIG_DIR}/.claude"
  touch "${_OVERRIDE_AI_CONFIG_DIR}/.claude/CLAUDE.md"
  local _home="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${_home}"
  export HOME="${_home}"

  run setup_dotfile_symlinks
  [ "${status}" -eq 0 ]
  [ -L "${_home}/.claude/CLAUDE.md" ]
  [[ "$(readlink "${_home}/.claude/CLAUDE.md")" == "${_OVERRIDE_AI_CONFIG_DIR}/.claude/CLAUDE.md" ]]
}

@test "setup_dotfile_symlinks creates .cursor symlinks from AI_CONFIG_DIR" {
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  export _OVERRIDE_AI_CONFIG_DIR="${BATS_TEST_TMPDIR}/ai-config"
  mkdir -p "${_OVERRIDE_AI_CONFIG_DIR}/.cursor"
  touch "${_OVERRIDE_AI_CONFIG_DIR}/.cursor/testfile"
  local _home="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${_home}"
  export HOME="${_home}"

  run setup_dotfile_symlinks
  [ "${status}" -eq 0 ]
  [ -L "${_home}/.cursor/testfile" ]
  [[ "$(readlink "${_home}/.cursor/testfile")" == "${_OVERRIDE_AI_CONFIG_DIR}/.cursor/testfile" ]]
}
