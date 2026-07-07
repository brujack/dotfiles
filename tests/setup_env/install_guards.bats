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

@test "brew_formula_installed returns 1 when root" {
  export MOCK_ID_U=0
  run brew_formula_installed git
  [ "$status" -eq 1 ]
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

@test "brew_cask_installed returns 1 when root" {
  export MOCK_ID_U=0
  run brew_cask_installed docker
  [ "$status" -eq 1 ]
}

@test "brew_cask_installed uses full-name flag for tap-qualified casks" {
  export MOCK_BREW_LIST_CASK="hashicorp/tap/vault-secrets-operator"
  run brew_cask_installed hashicorp/tap/vault-secrets-operator
  [ "$status" -eq 0 ]
  grep -q "brew list --cask --full-name" "${MOCK_CALLS_FILE}"
}

# ── brew_install_formula ─────────────────────────────────────────────────────

@test "brew_install_formula calls brew install when formula is absent" {
  export MOCK_BREW_LIST_FORMULA=""
  run brew_install_formula git
  [ "$status" -eq 0 ]
  grep -q "brew install git" "${MOCK_CALLS_FILE}"
}

@test "brew_install_formula sets NONINTERACTIVE=1 when installing" {
  export MOCK_BREW_LIST_FORMULA=""
  run brew_install_formula git
  [ "$status" -eq 0 ]
  grep -q "NONINTERACTIVE=1" "${MOCK_CALLS_FILE}"
}

@test "brew_install_formula does not call brew install when formula is present" {
  export MOCK_BREW_LIST_FORMULA="git"
  run brew_install_formula git
  [ "$status" -eq 0 ]
  ! grep -q "brew install git" "${MOCK_CALLS_FILE}"
}

@test "brew_install_formula returns 1 when root" {
  export MOCK_ID_U=0
  run brew_install_formula git
  [ "$status" -eq 1 ]
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

@test "brew_tap_if_missing returns 1 when root" {
  export MOCK_ID_U=0
  run brew_tap_if_missing hashicorp/tap
  [ "$status" -eq 1 ]
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
  run install_bats
  [ "$status" -eq 0 ]
  grep -q "apt-get install -y bats" "${MOCK_CALLS_FILE}"
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

@test "brew_tap_installed returns 1 when root" {
  export MOCK_ID_U=0
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

@test "brew_install_cask sets NONINTERACTIVE=1 when installing" {
  export MOCK_BREW_LIST_CASK=""
  run brew_install_cask docker
  [ "$status" -eq 0 ]
  grep -q "NONINTERACTIVE=1" "${MOCK_CALLS_FILE}"
}

@test "brew_install_cask does not call brew install when cask is present" {
  export MOCK_BREW_LIST_CASK="docker"
  run brew_install_cask docker
  [ "$status" -eq 0 ]
  ! grep -q "brew install --cask" "${MOCK_CALLS_FILE}"
}

@test "brew_install_cask returns 1 when root" {
  export MOCK_ID_U=0
  run brew_install_cask docker
  [ "$status" -eq 1 ]
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

@test "brew_update passes --yes to suppress Homebrew 6.0 confirmation prompt" {
  # Regression: Homebrew 6.0 added a confirmation prompt before upgrading
  # multiple packages; without --yes the update workflow hangs waiting for input.
  export MOCK_ID_U=1000
  run brew_update
  [ "$status" -eq 0 ]
  grep -q "brew upgrade --yes" "${MOCK_CALLS_FILE}"
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

@test "brew_update returns 1 when brew upgrade fails" {
  export MOCK_ID_U=1000
  export MOCK_BREW_UPGRADE_EXIT=1
  run brew_update
  [ "$status" -eq 1 ]
  [[ "$output" == *"Failed to upgrade formulae"* ]]
}

@test "brew_update warns but continues when cask upgrade fails" {
  export MOCK_ID_U=1000
  export MOCK_BREW_UPGRADE_CASK_EXIT=1
  run brew_update
  [ "$status" -eq 0 ]
  [[ "$output" == *"Some casks failed to upgrade"* ]]
  [[ "$output" == *"Homebrew update process completed successfully"* ]]
}

@test "brew_update returns 1 when brew cleanup fails" {
  export MOCK_ID_U=1000
  export MOCK_BREW_CLEANUP_EXIT=1
  run brew_update
  [ "$status" -eq 1 ]
  [[ "$output" == *"Failed to clean up"* ]]
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

@test "setup_ai_config does not clone when AI_CONFIG_DIR exists" {
  export _OVERRIDE_AI_CONFIG_DIR="${BATS_TEST_TMPDIR}/ai-config"
  mkdir -p "${_OVERRIDE_AI_CONFIG_DIR}"

  run setup_ai_config
  [ "${status}" -eq 0 ]
  ! grep -q "git clone" "${MOCK_CALLS_FILE}"
}

@test "setup_ai_config pulls when AI_CONFIG_DIR exists" {
  export _OVERRIDE_AI_CONFIG_DIR="${BATS_TEST_TMPDIR}/ai-config"
  mkdir -p "${_OVERRIDE_AI_CONFIG_DIR}"

  run setup_ai_config
  [ "${status}" -eq 0 ]
  grep -q "git -C ${_OVERRIDE_AI_CONFIG_DIR} pull --rebase --autostash" "${MOCK_CALLS_FILE}"
}

@test "setup_ai_config returns 1 when pull fails" {
  export MOCK_GIT_EXIT=1
  export _OVERRIDE_AI_CONFIG_DIR="${BATS_TEST_TMPDIR}/ai-config"
  mkdir -p "${_OVERRIDE_AI_CONFIG_DIR}"

  local _rc=0
  setup_ai_config || _rc=$?
  [ "${_rc}" -eq 1 ]
}

@test "setup_ai_config returns 1 when clone fails" {
  export MOCK_GIT_CLONE_EXIT=1
  export _OVERRIDE_AI_CONFIG_DIR="${BATS_TEST_TMPDIR}/nonexistent-ai-config"

  local _rc=0
  setup_ai_config || _rc=$?
  [ "${_rc}" -eq 1 ]
}

# ── ensure_state_ledger ──────────────────────────────────────────────────────

@test "ensure_state_ledger clones repo when state-ledger dir absent" {
  export _OVERRIDE_STATE_LEDGER_DIR="${BATS_TEST_TMPDIR}/nonexistent-state-ledger"

  run ensure_state_ledger
  [ "${status}" -eq 0 ]
  grep -q "git clone git@github.com:brujack/state-ledger.git ${BATS_TEST_TMPDIR}/nonexistent-state-ledger" "${MOCK_CALLS_FILE}"
}

@test "ensure_state_ledger does not clone when state-ledger dir exists" {
  export _OVERRIDE_STATE_LEDGER_DIR="${BATS_TEST_TMPDIR}/state-ledger"
  mkdir -p "${_OVERRIDE_STATE_LEDGER_DIR}"

  run ensure_state_ledger
  [ "${status}" -eq 0 ]
  ! grep -q "git clone" "${MOCK_CALLS_FILE}"
}

@test "ensure_state_ledger pulls (--ff-only) when state-ledger dir exists" {
  export _OVERRIDE_STATE_LEDGER_DIR="${BATS_TEST_TMPDIR}/state-ledger"
  mkdir -p "${_OVERRIDE_STATE_LEDGER_DIR}"

  run ensure_state_ledger
  [ "${status}" -eq 0 ]
  grep -q "git -C ${_OVERRIDE_STATE_LEDGER_DIR} pull --ff-only" "${MOCK_CALLS_FILE}"
}

@test "ensure_state_ledger warns and returns 0 when clone fails" {
  export MOCK_GIT_CLONE_EXIT=1
  export _OVERRIDE_STATE_LEDGER_DIR="${BATS_TEST_TMPDIR}/nonexistent-state-ledger"

  run ensure_state_ledger
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"state-ledger clone failed"* ]]
}

@test "ensure_state_ledger warns and returns 0 when pull fails" {
  export MOCK_GIT_EXIT=1
  export _OVERRIDE_STATE_LEDGER_DIR="${BATS_TEST_TMPDIR}/state-ledger"
  mkdir -p "${_OVERRIDE_STATE_LEDGER_DIR}"

  run ensure_state_ledger
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"state-ledger pull failed"* ]]
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

@test "setup_dotfile_symlinks symlinks .claude/projects to ai-config (not via loop)" {
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  export _OVERRIDE_AI_CONFIG_DIR="${BATS_TEST_TMPDIR}/ai-config"
  mkdir -p "${_OVERRIDE_AI_CONFIG_DIR}/.claude/projects"
  local _home="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${_home}"
  export HOME="${_home}"

  run setup_dotfile_symlinks
  [ "${status}" -eq 0 ]
  [[ -L "${_home}/.claude/projects" ]]
  [[ "$(readlink "${_home}/.claude/projects")" == "${_OVERRIDE_AI_CONFIG_DIR}/.claude/projects" ]]
}

# ── setup_dotfile_symlinks: gitconfig symlinks ────────────────────────────────

@test "setup_dotfile_symlinks: MACOS creates .gitconfig symlink" {
  local _home="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${_home}"
  export HOME="${_home}"
  export PERSONAL_GITREPOS="${BATS_TEST_TMPDIR}/git-repos/personal"
  export _OVERRIDE_AI_CONFIG_DIR="${BATS_TEST_TMPDIR}/ai-config"
  mkdir -p "${_OVERRIDE_AI_CONFIG_DIR}/.claude" "${_OVERRIDE_AI_CONFIG_DIR}/.cursor"
  export MACOS=1
  unset LINUX

  run setup_dotfile_symlinks
  [ "${status}" -eq 0 ]
  [ -L "${_home}/.gitconfig" ]
}

@test "setup_dotfile_symlinks: MACOS creates gitlab gitconfig when gitlab dir exists" {
  local _home="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${_home}/git-repos/gitlab"
  export HOME="${_home}"
  export PERSONAL_GITREPOS="${BATS_TEST_TMPDIR}/git-repos/personal"
  export _OVERRIDE_AI_CONFIG_DIR="${BATS_TEST_TMPDIR}/ai-config"
  mkdir -p "${_OVERRIDE_AI_CONFIG_DIR}/.claude" "${_OVERRIDE_AI_CONFIG_DIR}/.cursor"
  export MACOS=1
  unset LINUX

  run setup_dotfile_symlinks
  [ "${status}" -eq 0 ]
  [ -L "${_home}/git-repos/gitlab/.gitconfig" ]
}

@test "setup_dotfile_symlinks: MACOS skips gitlab gitconfig when gitlab dir absent" {
  local _home="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${_home}"
  export HOME="${_home}"
  export PERSONAL_GITREPOS="${BATS_TEST_TMPDIR}/git-repos/personal"
  export _OVERRIDE_AI_CONFIG_DIR="${BATS_TEST_TMPDIR}/ai-config"
  mkdir -p "${_OVERRIDE_AI_CONFIG_DIR}/.claude" "${_OVERRIDE_AI_CONFIG_DIR}/.cursor"
  export MACOS=1
  unset LINUX

  run setup_dotfile_symlinks
  [ "${status}" -eq 0 ]
  [ ! -L "${_home}/git-repos/gitlab/.gitconfig" ]
}

@test "setup_dotfile_symlinks: LINUX creates .gitconfig symlink" {
  local _home="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${_home}"
  export HOME="${_home}"
  export PERSONAL_GITREPOS="${BATS_TEST_TMPDIR}/git-repos/personal"
  export _OVERRIDE_AI_CONFIG_DIR="${BATS_TEST_TMPDIR}/ai-config"
  mkdir -p "${_OVERRIDE_AI_CONFIG_DIR}/.claude" "${_OVERRIDE_AI_CONFIG_DIR}/.cursor"
  export LINUX=1
  unset MACOS

  run setup_dotfile_symlinks
  [ "${status}" -eq 0 ]
  [ -L "${_home}/.gitconfig" ]
}

@test "setup_dotfile_symlinks: LINUX creates gitlab gitconfig with HAS_DEVTOOLS when gitlab dir exists" {
  local _home="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${_home}/git-repos/gitlab"
  export HOME="${_home}"
  export PERSONAL_GITREPOS="${BATS_TEST_TMPDIR}/git-repos/personal"
  export _OVERRIDE_AI_CONFIG_DIR="${BATS_TEST_TMPDIR}/ai-config"
  mkdir -p "${_OVERRIDE_AI_CONFIG_DIR}/.claude" "${_OVERRIDE_AI_CONFIG_DIR}/.cursor"
  export LINUX=1
  export HAS_DEVTOOLS=1
  unset MACOS

  run setup_dotfile_symlinks
  [ "${status}" -eq 0 ]
  [ -L "${_home}/git-repos/gitlab/.gitconfig" ]
}

@test "setup_dotfile_symlinks: LINUX skips gitlab gitconfig without HAS_DEVTOOLS" {
  local _home="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${_home}/git-repos/gitlab"
  export HOME="${_home}"
  export PERSONAL_GITREPOS="${BATS_TEST_TMPDIR}/git-repos/personal"
  export _OVERRIDE_AI_CONFIG_DIR="${BATS_TEST_TMPDIR}/ai-config"
  mkdir -p "${_OVERRIDE_AI_CONFIG_DIR}/.claude" "${_OVERRIDE_AI_CONFIG_DIR}/.cursor"
  export LINUX=1
  unset MACOS HAS_DEVTOOLS

  run setup_dotfile_symlinks
  [ "${status}" -eq 0 ]
  [ ! -L "${_home}/git-repos/gitlab/.gitconfig" ]
}

# ── setup_dotfile_symlinks: oh-my-zsh ────────────────────────────────────────

@test "setup_dotfile_symlinks: skips oh-my-zsh install when already present" {
  local _home="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${_home}/.oh-my-zsh"
  export HOME="${_home}"
  export PERSONAL_GITREPOS="${BATS_TEST_TMPDIR}/git-repos/personal"
  export _OVERRIDE_AI_CONFIG_DIR="${BATS_TEST_TMPDIR}/ai-config"
  mkdir -p "${_OVERRIDE_AI_CONFIG_DIR}/.claude" "${_OVERRIDE_AI_CONFIG_DIR}/.cursor"

  run setup_dotfile_symlinks
  [ "${status}" -eq 0 ]
  ! grep -q "ohmyzsh" "${MOCK_CALLS_FILE:-/dev/null}"
}

@test "setup_dotfile_symlinks: installs oh-my-zsh when not present" {
  local _home="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${_home}"
  export HOME="${_home}"
  export PERSONAL_GITREPOS="${BATS_TEST_TMPDIR}/git-repos/personal"
  export _OVERRIDE_AI_CONFIG_DIR="${BATS_TEST_TMPDIR}/ai-config"
  mkdir -p "${_OVERRIDE_AI_CONFIG_DIR}/.claude" "${_OVERRIDE_AI_CONFIG_DIR}/.cursor"

  run setup_dotfile_symlinks
  [ "${status}" -eq 0 ]
  grep -q "ohmyzsh" "${MOCK_CALLS_FILE}"
}

@test "setup_dotfile_symlinks: installs oh-my-zsh via git clone (not curl)" {
  local _home="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${_home}"
  export HOME="${_home}"
  export PERSONAL_GITREPOS="${BATS_TEST_TMPDIR}/git-repos/personal"
  export _OVERRIDE_AI_CONFIG_DIR="${BATS_TEST_TMPDIR}/ai-config"
  mkdir -p "${_OVERRIDE_AI_CONFIG_DIR}/.claude" "${_OVERRIDE_AI_CONFIG_DIR}/.cursor"
  run setup_dotfile_symlinks
  grep -q "git clone.*ohmyzsh" "${MOCK_CALLS_FILE}"
  run grep "curl.*ohmyzsh" "${MOCK_CALLS_FILE:-/dev/null}"
  [ "$status" -ne 0 ]
}

@test "setup_dotfile_symlinks: creates custom/themes dir after oh-my-zsh clone" {
  local _home="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${_home}"
  export HOME="${_home}"
  export PERSONAL_GITREPOS="${BATS_TEST_TMPDIR}/git-repos/personal"
  export _OVERRIDE_AI_CONFIG_DIR="${BATS_TEST_TMPDIR}/ai-config"
  mkdir -p "${_OVERRIDE_AI_CONFIG_DIR}/.claude" "${_OVERRIDE_AI_CONFIG_DIR}/.cursor"
  run setup_dotfile_symlinks
  [ "${status}" -eq 0 ]
  [ -d "${_home}/.oh-my-zsh/custom/themes" ]
}

# ── setup_dotfile_symlinks: TPM ───────────────────────────────────────────────

@test "setup_dotfile_symlinks: skips TPM when already installed" {
  local _home="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${_home}/.oh-my-zsh" "${_home}/.tmux/plugins/tpm"
  export HOME="${_home}"
  export PERSONAL_GITREPOS="${BATS_TEST_TMPDIR}/git-repos/personal"
  export _OVERRIDE_AI_CONFIG_DIR="${BATS_TEST_TMPDIR}/ai-config"
  mkdir -p "${_OVERRIDE_AI_CONFIG_DIR}/.claude" "${_OVERRIDE_AI_CONFIG_DIR}/.cursor"

  run setup_dotfile_symlinks
  [ "${status}" -eq 0 ]
  ! grep -q "tmux-plugins/tpm" "${MOCK_CALLS_FILE:-/dev/null}"
}

@test "setup_dotfile_symlinks: clones TPM when not present" {
  local _home="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${_home}/.oh-my-zsh"
  export HOME="${_home}"
  export PERSONAL_GITREPOS="${BATS_TEST_TMPDIR}/git-repos/personal"
  export _OVERRIDE_AI_CONFIG_DIR="${BATS_TEST_TMPDIR}/ai-config"
  mkdir -p "${_OVERRIDE_AI_CONFIG_DIR}/.claude" "${_OVERRIDE_AI_CONFIG_DIR}/.cursor"

  run setup_dotfile_symlinks
  [ "${status}" -eq 0 ]
  grep -q "tmux-plugins/tpm" "${MOCK_CALLS_FILE}"
}

# ── setup_dotfile_symlinks: Cursor User settings ─────────────────────────────

@test "setup_dotfile_symlinks: skips User/ in .cursor glob loop" {
  local _home="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${_home}/.oh-my-zsh" "${_home}/.tmux/plugins/tpm"
  export HOME="${_home}"
  export PERSONAL_GITREPOS="${BATS_TEST_TMPDIR}/git-repos/personal"
  export _OVERRIDE_AI_CONFIG_DIR="${BATS_TEST_TMPDIR}/ai-config"
  mkdir -p "${_OVERRIDE_AI_CONFIG_DIR}/.claude" "${_OVERRIDE_AI_CONFIG_DIR}/.cursor/User"
  touch "${_OVERRIDE_AI_CONFIG_DIR}/.cursor/User/settings.json"

  run setup_dotfile_symlinks
  [ "${status}" -eq 0 ]
  [ ! -L "${_home}/.cursor/User" ]
}

@test "setup_dotfile_symlinks: links Cursor User settings when installed on LINUX" {
  local _home="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${_home}/.oh-my-zsh" "${_home}/.tmux/plugins/tpm"
  export HOME="${_home}"
  export PERSONAL_GITREPOS="${BATS_TEST_TMPDIR}/git-repos/personal"
  export _OVERRIDE_AI_CONFIG_DIR="${BATS_TEST_TMPDIR}/ai-config"
  mkdir -p "${_OVERRIDE_AI_CONFIG_DIR}/.claude" \
           "${_OVERRIDE_AI_CONFIG_DIR}/.cursor/User/snippets"
  touch "${_OVERRIDE_AI_CONFIG_DIR}/.cursor/User/settings.json"
  touch "${_OVERRIDE_AI_CONFIG_DIR}/.cursor/User/keybindings.json"
  export LINUX=1
  unset MACOS

  run setup_dotfile_symlinks
  [ "${status}" -eq 0 ]
  [ -L "${_home}/.config/Cursor/User/settings.json" ]
  [ -L "${_home}/.config/Cursor/User/keybindings.json" ]
}

@test "setup_dotfile_symlinks: skips Cursor User symlinks when dotfiles User files missing" {
  local _home="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${_home}/.oh-my-zsh" "${_home}/.tmux/plugins/tpm"
  export HOME="${_home}"
  export PERSONAL_GITREPOS="${BATS_TEST_TMPDIR}/git-repos/personal"
  export _OVERRIDE_AI_CONFIG_DIR="${BATS_TEST_TMPDIR}/ai-config"
  mkdir -p "${_OVERRIDE_AI_CONFIG_DIR}/.claude" "${_OVERRIDE_AI_CONFIG_DIR}/.cursor"
  export LINUX=1
  unset MACOS

  run setup_dotfile_symlinks
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Skipping Cursor symlinks"* ]]
}

# ── setup_credential_directories ─────────────────────────────────────────────

@test "setup_credential_directories: creates .aws .gcloud_creds .azure_creds with mode 700" {
  local _home="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${_home}"
  export HOME="${_home}"

  run setup_credential_directories
  [ "${status}" -eq 0 ]
  [ -d "${_home}/.aws" ]
  [ -d "${_home}/.gcloud_creds" ]
  [ -d "${_home}/.azure_creds" ]
  [[ "$(ls -ld "${_home}/.aws")" == drwx------* ]]
  [[ "$(ls -ld "${_home}/.gcloud_creds")" == drwx------* ]]
  [[ "$(ls -ld "${_home}/.azure_creds")" == drwx------* ]]
}

# ── setup_claude_plugins ──────────────────────────────────────────────────────

@test "setup_claude_plugins: claude not installed → returns 0 with skip message" {
  local _clean_path
  _clean_path="$(printf '%s' "${PATH}" | tr ':' '\n' | grep -v 'tests/mocks' | while read -r _dir; do
    [[ -x "${_dir}/claude" ]] || printf '%s\n' "${_dir}"
  done | tr '\n' ':' | sed 's/:$//')"
  run bash -c "
    export PATH='${_clean_path}'
    export MOCK_CALLS_FILE='${BATS_TEST_TMPDIR}/mock_calls'
    source '${REPO_ROOT}/setup_env.sh'
    setup_claude_plugins
  "
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"skipping plugin setup"* ]]
}

@test "setup_claude_plugins: plugin already installed → no install call" {
  export MOCK_CLAUDE_PLUGINS_LIST_OUTPUT="superpowers@claude-plugins-official"
  run setup_claude_plugins
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"already installed: superpowers@claude-plugins-official"* ]]
  ! grep -q "claude plugins install superpowers@claude-plugins-official" "${MOCK_CALLS_FILE}"
}

@test "setup_claude_plugins: plugin not installed → claude plugins install called" {
  export MOCK_CLAUDE_PLUGINS_LIST_OUTPUT=""
  run setup_claude_plugins
  [ "${status}" -eq 0 ]
  grep -q "claude plugins install superpowers@claude-plugins-official" "${MOCK_CALLS_FILE}"
}

# ── run_setup_user (mid-chain failure propagation) ────────────────────────────

@test "run_setup_user: setup_ai_config fails → returns non-zero, setup_dotfile_symlinks not called" {
  local _home="${BATS_TEST_TMPDIR}/home"
  local _git_repos="${BATS_TEST_TMPDIR}/git-repos/personal"
  mkdir -p "${_home}" "${_git_repos}"
  run bash -c "
    export PATH='${PATH}'
    export HOME='${_home}'
    export PERSONAL_GITREPOS='${_git_repos}'
    export DOTFILES='dotfiles'
    export LINUX=1
    unset MACOS UBUNTU
    export MOCK_CALLS_FILE='${BATS_TEST_TMPDIR}/mock_calls'
    source '${REPO_ROOT}/setup_env.sh'
    clone_or_update_dotfiles() { return 0; }
    setup_ai_config() { return 1; }
    setup_dotfile_symlinks() { printf 'DOTFILES_CALLED\n'; return 0; }
    run_setup_user
  "
  [ "${status}" -ne 0 ]
  ! [[ "${output}" == *"DOTFILES_CALLED"* ]]
}

@test "run_setup_user: setup_claude_mcp fails → returns non-zero, setup_claude_plugins not called" {
  local _home="${BATS_TEST_TMPDIR}/home"
  local _git_repos="${BATS_TEST_TMPDIR}/git-repos/personal"
  mkdir -p "${_home}" "${_git_repos}"
  run bash -c "
    export PATH='${PATH}'
    export HOME='${_home}'
    export PERSONAL_GITREPOS='${_git_repos}'
    export DOTFILES='dotfiles'
    export LINUX=1
    unset MACOS UBUNTU
    export MOCK_CALLS_FILE='${BATS_TEST_TMPDIR}/mock_calls'
    source '${REPO_ROOT}/setup_env.sh'
    install_bats() { return 0; }
    clone_or_update_dotfiles() { return 0; }
    setup_ai_config() { return 0; }
    setup_dotfile_symlinks() { return 0; }
    install_terraform_skill() { return 0; }
    setup_zsh_as_default_shell() { return 0; }
    setup_claude_mcp() { return 1; }
    setup_claude_plugins() { printf 'PLUGINS_CALLED\n'; return 0; }
    run_setup_user
  "
  [ "${status}" -ne 0 ]
  ! [[ "${output}" == *"PLUGINS_CALLED"* ]]
}
