#!/usr/bin/env bats

# Covers run_update's claude section (lib/workflows.sh) after Task 6 of
# docs/superpowers/specs/2026-09-19-claude-plugin-provisioning-design.md:
# ai-config is now pulled immediately before the claude section runs (so the
# reconcile below reads the settings.json this run just fetched), and the
# section itself is rewritten around setup_claude_plugins's reconcile,
# re-reading the manifest/installed-id lists, updating every declared id
# actually installed at user scope, and the settings.json write guard.
# _UPDATE_SECTION_ORDER's reordering (lib/update_summary.sh) is covered by a
# dedicated test in update_summary.bats.

setup() {
  # A leaked GIT_DIR/GIT_INDEX_FILE would make the guard-repo tests' `git
  # init`/`add`/`commit` calls operate on the wrong repo -- git -C does not
  # override an inherited GIT_DIR (shell.md). Required at setup scope for
  # any bats setup that creates a fixture repo (git-workflow.md).
  unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_mocks
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  touch "${MOCK_CALLS_FILE}"
  load_setup_env
  unset PYENV_ROOT
  export _OVERRIDE_PYENV_ROOT="${BATS_TEST_TMPDIR}/pyenv"
  # run_update's aws section performs real signature verification when
  # HAS_AWS is set for real by this developer session's own profile
  # (tdd.md E2) -- unset it here so a full run doesn't exercise it.
  unset HAS_AWS
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${HOME}"
  export PERSONAL_GITREPOS="${BATS_TEST_TMPDIR}/git-repos/personal"
  export DOTFILES="dotfiles"
  export BREWFILE_LOC="${BATS_TEST_TMPDIR}/brew-files"
  mkdir -p "${PERSONAL_GITREPOS}/${DOTFILES}"
  # run_update's _dotfiles_run_tmpdir_setup uses TMPDIR, which bats leaves
  # at the system temp dir.
  export TMPDIR="${BATS_TEST_TMPDIR}"
  export UPDATE_LOG_PATH="${BATS_TEST_TMPDIR}/update.log"
  export MACOS=1
  unset LINUX UBUNTU
  unset UPDATE_BREW UPDATE_PIP UPDATE_GEMS UPDATE_MAS UPDATE_CLAUDE UPDATE_PKGS
  # Set at setup scope so no test here can rewrite the operator's real
  # plugin cache (tdd.md E2).
  export _OVERRIDE_CLAUDE_PLUGIN_CACHE="${BATS_TEST_TMPDIR}/cache"
  unset MOCK_CLAUDE_MARKETPLACE_LIST_JSON MOCK_CLAUDE_PLUGINS_LIST_JSON
  unset MOCK_CLAUDE_FAIL_ARGS MOCK_CLAUDE_FAIL_ON_CALL MOCK_CLAUDE_EDIT_SETTINGS
}

teardown() {
  rm -f "${MOCK_CALLS_FILE:-}"
}

# Builds a real git repo tracking settings.json and points
# _OVERRIDE_CLAUDE_SETTINGS at the tracked file directly, then resolves a
# REAL git (never tests/mocks/git, which cannot report clean/dirty) with the
# mocks directory stripped from PATH. Mirrors
# tests/setup_env/claude_plugins.bats' _guard_repo_setup; duplicated here
# because this file's files_touched scope does not include that one.
_claude_guard_repo_setup() {
  local _clean_path _real_git
  _clean_path="$(printf '%s' "${PATH}" | tr ':' '\n' | grep -v 'tests/mocks' | tr '\n' ':' | sed 's/:$//')"
  _real_git="$(PATH="${_clean_path}" command -v git)"
  local _git_shim="${BATS_TEST_TMPDIR}/git-shim"
  mkdir -p "${_git_shim}"
  ln -sf "${_real_git}" "${_git_shim}/git"
  export _CLAUDE_GUARD_GIT="${_git_shim}/git"

  GUARD_REPO="${BATS_TEST_TMPDIR}/guard-repo"
  mkdir -p "${GUARD_REPO}"
  cp "${REPO_ROOT}/tests/fixtures/claude-settings.json" "${GUARD_REPO}/settings.json"
  "${_CLAUDE_GUARD_GIT}" -C "${GUARD_REPO}" init -q
  "${_CLAUDE_GUARD_GIT}" -C "${GUARD_REPO}" -c user.email=t@t -c user.name=T add settings.json
  "${_CLAUDE_GUARD_GIT}" -C "${GUARD_REPO}" -c user.email=t@t -c user.name=T commit -qm init
  export _OVERRIDE_CLAUDE_SETTINGS="${GUARD_REPO}/settings.json"
}

@test "run_update pulls ai-config before reading claude plugin state" {
  setup_ai_config() { printf 'AI_PULL\n' >> "${MOCK_CALLS_FILE}"; return 0; }
  sync_git_repos() { return 0; }
  sync_legacy_dirs() { return 0; }
  install_git_hooks_all_repos() { return 0; }
  export -f setup_ai_config sync_git_repos sync_legacy_dirs install_git_hooks_all_repos
  # Full run: every UPDATE_* flag is unset in setup(), so _run_all=1 -- the
  # only way to exercise the ai-config section at all, since it is gated
  # on _run_all, never on UPDATE_CLAUDE.
  run run_update
  [ "$status" -eq 0 ]
  local _ai_line _claude_line
  _ai_line="$(grep -n '^AI_PULL$' "${MOCK_CALLS_FILE}" | head -1 | cut -d: -f1)"
  _claude_line="$(grep -n '^claude plugins marketplace list --json$' "${MOCK_CALLS_FILE}" | head -1 | cut -d: -f1)"
  [ -n "${_ai_line}" ]
  [ -n "${_claude_line}" ]
  [ "${_ai_line}" -lt "${_claude_line}" ]
}

@test "run_update: claude section updates every declared id installed at user scope, disabled ones included" {
  export UPDATE_CLAUDE=1
  export MOCK_CLAUDE_PLUGINS_LIST_JSON='[{"id":"superpowers@claude-plugins-official","scope":"user"},{"id":"frontend-design@claude-plugins-official","scope":"user"}]'
  run run_update
  [ "$status" -eq 0 ]
  [ "$(grep -c '^claude plugins update ' "${MOCK_CALLS_FILE}")" -eq 2 ]
  grep -q '^claude plugins update frontend-design@claude-plugins-official$' "${MOCK_CALLS_FILE}"
}

@test "run_update: a partial reconcile WARNs the claude section and names it partial" {
  export UPDATE_CLAUDE=1
  export MOCK_CLAUDE_PLUGINS_LIST_JSON='[{"id":"superpowers@claude-plugins-official","scope":"user"}]'
  # Leaves both marketplaces unregistered (default []); the git-source
  # marketplace's URL is https, so this fails only that add call.
  export MOCK_CLAUDE_FAIL_ARGS="marketplace add https"
  run_update
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_claude")" = "WARN" ]
  [[ "$(cat "${_DOTFILES_RUN_TMPDIR}/result_claude")" == *"partial"* ]]
}

@test "run_update: a failed plugin update FAILs the claude section" {
  export UPDATE_CLAUDE=1
  export MOCK_CLAUDE_PLUGINS_LIST_JSON='[{"id":"superpowers@claude-plugins-official","scope":"user"}]'
  export MOCK_CLAUDE_FAIL_ARGS="plugins update superpowers"
  local _rc=0
  run_update || _rc=$?
  [ "${_rc}" -ne 0 ]
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_claude")" = "FAIL" ]
}

@test "run_update: unreadable settings FAILs claude with zero update calls" {
  export UPDATE_CLAUDE=1
  export _OVERRIDE_CLAUDE_SETTINGS="${BATS_TEST_TMPDIR}/does-not-exist.json"
  local _rc=0
  run_update || _rc=$?
  [ "${_rc}" -ne 0 ]
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_claude")" = "FAIL" ]
  [[ "$(cat "${_DOTFILES_RUN_TMPDIR}/result_claude")" == *"unreadable"* ]]
  refute_grep "claude plugins update" "${MOCK_CALLS_FILE}"
}

@test "run_update: a failed re-list of installed plugins FAILs claude with zero update calls" {
  export UPDATE_CLAUDE=1
  export MOCK_CLAUDE_PLUGINS_LIST_JSON='[{"id":"superpowers@claude-plugins-official","scope":"user"}]'
  # setup_claude_plugins's own reconcile makes the first "plugins list
  # --json" call (marketplace list --json does not advance this counter);
  # run_update's own re-read is the second, which this fails.
  export MOCK_CLAUDE_FAIL_ON_CALL=2
  local _rc=0
  run_update || _rc=$?
  [ "${_rc}" -ne 0 ]
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_claude")" = "FAIL" ]
  [[ "$(cat "${_DOTFILES_RUN_TMPDIR}/result_claude")" == *"installed-plugin list failed"* ]]
  refute_grep "claude plugins update" "${MOCK_CALLS_FILE}"
}

@test "run_update: the write guard WARNs when the update run edits settings.json" {
  _claude_guard_repo_setup
  export UPDATE_CLAUDE=1
  export MOCK_CLAUDE_MARKETPLACE_LIST_JSON='[{"name":"claude-plugins-official"},{"name":"caveman"}]'
  export MOCK_CLAUDE_PLUGINS_LIST_JSON='[{"id":"superpowers@claude-plugins-official","scope":"user"}]'
  export MOCK_CLAUDE_EDIT_SETTINGS=update
  run_update
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_claude")" = "WARN" ]
  [[ "$(cat "${_DOTFILES_RUN_TMPDIR}/result_claude")" == *"changed during plugin provisioning"* ]]
}

@test "run_update: a failed update still surfaces the guard warning in the FAILed result" {
  _claude_guard_repo_setup
  export UPDATE_CLAUDE=1
  export MOCK_CLAUDE_MARKETPLACE_LIST_JSON='[{"name":"claude-plugins-official"},{"name":"caveman"}]'
  export MOCK_CLAUDE_PLUGINS_LIST_JSON='[{"id":"superpowers@claude-plugins-official","scope":"user"},{"id":"caveman@caveman","scope":"user"}]'
  export MOCK_CLAUDE_EDIT_SETTINGS=update
  export MOCK_CLAUDE_FAIL_ARGS="plugins update caveman"
  local _rc=0
  run_update || _rc=$?
  [ "${_rc}" -ne 0 ]
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_claude")" = "FAIL" ]
  local _result
  _result="$(cat "${_DOTFILES_RUN_TMPDIR}/result_claude")"
  [[ "${_result}" == *"changed during plugin provisioning"* ]]
  # Two independent messages (the plugin-failure count and the guard
  # warning) are joined with "; " -- a semicolon AND a space. `IFS='; '`
  # would join on only the first character of IFS (shell.md), silently
  # dropping the space; assert on the real two-character separator so that
  # regression is caught rather than only the substrings either side of it.
  [[ "${_result}" == *"(caveman); "*"changed during plugin provisioning"* ]]
}
