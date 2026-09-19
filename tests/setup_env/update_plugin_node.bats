#!/usr/bin/env bats

# Covers run_update's plugin-node section (lib/workflows.sh) and its
# _UPDATE_SECTION_ORDER entry (lib/update_summary.sh). The repair itself is
# covered in plugin_node_paths.bats.
#
# `brew upgrade node` deletes the versioned Cellar node that context-mode
# writes into its cached hooks.json/plugin.json on Linux
# (mksglu/context-mode#1090), so the repair has to run in the same command
# that performs the upgrade: under a full update or --brew-only. It also runs
# under --claude-only, because a plugin update extracts a fresh cache.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_mocks
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  touch "${MOCK_CALLS_FILE}"
  load_setup_env
  unset PYENV_ROOT
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
  unset LINUX UBUNTU HAS_AWS HAS_DEVTOOLS
  unset UPDATE_BREW UPDATE_PIP UPDATE_GEMS UPDATE_MAS UPDATE_CLAUDE UPDATE_PKGS
  export _OVERRIDE_PYENV_ROOT="${BATS_TEST_TMPDIR}/pyenv_root"
  # Set at setup scope so no run_update here can rewrite the operator's real
  # plugin cache (tdd.md E2).
  export _OVERRIDE_CLAUDE_PLUGIN_CACHE="${BATS_TEST_TMPDIR}/cache"
  BREW_PREFIX="${BATS_TEST_TMPDIR}/brew"
  STALE_NODE="${BREW_PREFIX}/Cellar/node/1.0.0/bin/node"
  PLUGIN_JSON="${_OVERRIDE_CLAUDE_PLUGIN_CACHE}/ctx/ctx/1.0.169/.claude-plugin/plugin.json"
}

teardown() {
  rm -f "${MOCK_CALLS_FILE:-}"
}

# A plugin.json pinning the missing 1.0.0 keg. WITH_OPT=1 also installs a
# 2.0.0 keg behind opt/node, so the pin is repairable.
_make_stale_plugin() {
  mkdir -p "$(dirname "${PLUGIN_JSON}")"
  printf '{"mcpServers":{"ctx":{"command":"%s"}}}\n' "${STALE_NODE}" > "${PLUGIN_JSON}"
  if [[ ${1:-0} -eq 1 ]]; then
    mkdir -p "${BREW_PREFIX}/Cellar/node/2.0.0/bin" "${BREW_PREFIX}/opt"
    printf '#!/bin/sh\n' > "${BREW_PREFIX}/Cellar/node/2.0.0/bin/node"
    chmod +x "${BREW_PREFIX}/Cellar/node/2.0.0/bin/node"
    ln -s ../Cellar/node/2.0.0 "${BREW_PREFIX}/opt/node"
  fi
}

@test "plugin-node: --brew-only repairs a stale pin and reports OK" {
  _make_stale_plugin 1
  export UPDATE_BREW=1
  run_update
  grep -q '^OK$' "${_DOTFILES_RUN_TMPDIR}/status_plugin-node"
  grep -qF "\"command\":\"${BREW_PREFIX}/opt/node/bin/node\"" "${PLUGIN_JSON}"
}

@test "plugin-node: runs under --claude-only" {
  _make_stale_plugin 1
  export UPDATE_CLAUDE=1
  run_update
  grep -q '^OK$' "${_DOTFILES_RUN_TMPDIR}/status_plugin-node"
  grep -qF "${BREW_PREFIX}/opt/node/bin/node" "${PLUGIN_JSON}"
}

@test "plugin-node: an unrepairable pin WARNs, names the file, and does not FAIL the run" {
  _make_stale_plugin 0
  export UPDATE_BREW=1
  run_update
  grep -q '^WARN$' "${_DOTFILES_RUN_TMPDIR}/status_plugin-node"
  grep -q 'could not be repaired' "${_DOTFILES_RUN_TMPDIR}/result_plugin-node"
  grep -qF "${PLUGIN_JSON}" "${_DOTFILES_RUN_TMPDIR}/detail_plugin-node"
  grep -qF "${STALE_NODE}" "${PLUGIN_JSON}"
}

@test "plugin-node: SKIPs 'no Claude plugin cache' when there is none" {
  export UPDATE_BREW=1
  run_update
  grep -q '^SKIP$' "${_DOTFILES_RUN_TMPDIR}/status_plugin-node"
  grep -q 'no Claude plugin cache' "${_DOTFILES_RUN_TMPDIR}/result_plugin-node"
}

@test "plugin-node: SKIPs 'flag not set' under --gems-only and leaves the pin alone" {
  _make_stale_plugin 1
  export UPDATE_GEMS=1
  run_update
  grep -q '^SKIP$' "${_DOTFILES_RUN_TMPDIR}/status_plugin-node"
  grep -q 'flag not set' "${_DOTFILES_RUN_TMPDIR}/result_plugin-node"
  grep -qF "${STALE_NODE}" "${PLUGIN_JSON}"
}

@test "plugin-node: the printed update summary includes the section" {
  _make_stale_plugin 1
  export UPDATE_BREW=1
  run_update
  run _update_summary
  [[ "$output" == *"plugin-node"* ]]
}

@test "plugin-node: a full update with no flags repairs a stale pin" {
  # The common invocation. The flag tests above cannot see the _run_all arm.
  _make_stale_plugin 1
  run_update
  grep -q '^OK$' "${_DOTFILES_RUN_TMPDIR}/status_plugin-node"
  grep -qF "\"command\":\"${BREW_PREFIX}/opt/node/bin/node\"" "${PLUGIN_JSON}"
}
