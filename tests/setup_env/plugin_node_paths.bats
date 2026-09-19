#!/usr/bin/env bats

# Covers lib/helpers.sh's _plugin_stale_node_paths, repair_plugin_node_paths
# and _doctor_check_plugin_node_paths, and run_update's plugin-node section.
#
# Some Claude Code plugins write process.execPath into their cached
# hooks/hooks.json and .claude-plugin/plugin.json. Under Homebrew that is the
# versioned Cellar path, so `brew upgrade node` deletes it and every hook then
# fails with "/bin/sh: 1: <path>: not found". context-mode does this on Linux
# (upstream mksglu/context-mode#1090) and cannot heal itself, because its MCP
# server starts from the same dead path. Measured 2026-09-19 on claude
# (26.8.2) and workstation (26.4.0, all six cached versions).

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_setup_env
  load_mocks
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${HOME}"
  # Set at setup scope so no test can reach the operator's real plugin cache
  # (tdd.md E2): a repair test that forgot the seam would rewrite it.
  export _OVERRIDE_CLAUDE_PLUGIN_CACHE="${BATS_TEST_TMPDIR}/cache"
  BREW_PREFIX="${BATS_TEST_TMPDIR}/brew"
  STALE_NODE="${BREW_PREFIX}/Cellar/node/1.0.0/bin/node"
  STABLE_NODE="${BREW_PREFIX}/opt/node/bin/node"
}

teardown() {
  rm -f "${MOCK_CALLS_FILE:-}"
}

# Installs node 2.0.0 under a fake brew prefix, with opt/node pointing at it
# the way brew links a keg. The 1.0.0 keg the fixtures pin is never created.
_make_brew_node() {
  mkdir -p "${BREW_PREFIX}/Cellar/node/2.0.0/bin" "${BREW_PREFIX}/opt"
  printf '#!/bin/sh\n' > "${BREW_PREFIX}/Cellar/node/2.0.0/bin/node"
  chmod +x "${BREW_PREFIX}/Cellar/node/2.0.0/bin/node"
  ln -s ../Cellar/node/2.0.0 "${BREW_PREFIX}/opt/node"
}

# Writes a plugin's hooks.json and plugin.json with NODE as the interpreter,
# in the shapes context-mode writes: a quoted path inside a hook command
# string, and a bare path in mcpServers.command.
_make_plugin() {
  local _dir="${_OVERRIDE_CLAUDE_PLUGIN_CACHE}/$1" _node="$2"
  mkdir -p "${_dir}/hooks" "${_dir}/.claude-plugin"
  printf '{"hooks":{"PostToolUse":[{"hooks":[{"type":"command","command":"\\"%s\\" \\"%s/hooks/posttooluse.mjs\\""}]}]}}\n' \
    "${_node}" "${_dir}" > "${_dir}/hooks/hooks.json"
  printf '{"mcpServers":{"ctx":{"command":"%s","args":["%s/start.mjs"]}}}\n' \
    "${_node}" "${_dir}" > "${_dir}/.claude-plugin/plugin.json"
}

# ── _plugin_stale_node_paths ─────────────────────────────────────────────────

@test "_plugin_stale_node_paths names each config file that pins a missing Cellar node" {
  _make_brew_node
  _make_plugin "ctx/ctx/1.0.169" "${STALE_NODE}"

  run _plugin_stale_node_paths
  [ "$status" -eq 0 ]
  [[ "$output" == *"${_OVERRIDE_CLAUDE_PLUGIN_CACHE}/ctx/ctx/1.0.169/hooks/hooks.json"$'\t'"${STALE_NODE}"* ]]
  [[ "$output" == *"${_OVERRIDE_CLAUDE_PLUGIN_CACHE}/ctx/ctx/1.0.169/.claude-plugin/plugin.json"$'\t'"${STALE_NODE}"* ]]
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq 2 ]
}

@test "_plugin_stale_node_paths ignores a pin whose Cellar node still exists" {
  _make_brew_node
  _make_plugin "ctx/ctx/1.0.169" "${BREW_PREFIX}/Cellar/node/2.0.0/bin/node"

  run _plugin_stale_node_paths
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "_plugin_stale_node_paths ignores a bare node interpreter" {
  _make_plugin "ctx/ctx/1.0.169" "node"

  run _plugin_stale_node_paths
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "_plugin_stale_node_paths returns rc 2 when there is no plugin cache" {
  run _plugin_stale_node_paths
  [ "$status" -eq 2 ]
  [ -z "$output" ]
}

@test "_plugin_stale_node_paths returns rc 0 and nothing for an empty plugin cache" {
  mkdir -p "${_OVERRIDE_CLAUDE_PLUGIN_CACHE}"

  run _plugin_stale_node_paths
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "_plugin_stale_node_paths covers every cached version, not only the newest" {
  _make_brew_node
  _make_plugin "ctx/ctx/1.0.162" "${STALE_NODE}"
  _make_plugin "ctx/ctx/1.0.169" "${STALE_NODE}"

  run _plugin_stale_node_paths
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq 4 ]
  [[ "$output" == *"/1.0.162/hooks/hooks.json"* ]]
}

@test "_plugin_stale_node_paths recognises a versioned node@NN formula" {
  local _pinned="${BREW_PREFIX}/Cellar/node@22/22.1.0/bin/node"
  _make_plugin "ctx/ctx/1.0.169" "${_pinned}"

  run _plugin_stale_node_paths
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\t'"${_pinned}"* ]]
}

# ── repair_plugin_node_paths ─────────────────────────────────────────────────

@test "repair_plugin_node_paths repoints a stale pin at the keg's stable opt path" {
  _make_brew_node
  _make_plugin "ctx/ctx/1.0.169" "${STALE_NODE}"
  local _dir="${_OVERRIDE_CLAUDE_PLUGIN_CACHE}/ctx/ctx/1.0.169"

  run repair_plugin_node_paths
  [ "$status" -eq 0 ]
  [[ "$output" == *"repaired ${_dir}/hooks/hooks.json"* ]]
  refute_grep "${STALE_NODE}" "${_dir}/hooks/hooks.json" -F
  refute_grep "${STALE_NODE}" "${_dir}/.claude-plugin/plugin.json" -F
  grep -qF "\\\"${STABLE_NODE}\\\" " "${_dir}/hooks/hooks.json"
  grep -qF "\"command\":\"${STABLE_NODE}\"" "${_dir}/.claude-plugin/plugin.json"
  run _plugin_stale_node_paths
  [ -z "$output" ]
}

@test "repair_plugin_node_paths leaves the file untouched and returns 1 when no opt link exists" {
  # No _make_brew_node: neither the pinned keg nor opt/node exists.
  _make_plugin "ctx/ctx/1.0.169" "${STALE_NODE}"
  local _file="${_OVERRIDE_CLAUDE_PLUGIN_CACHE}/ctx/ctx/1.0.169/hooks/hooks.json"
  local _before
  _before="$(cat "${_file}")"

  run repair_plugin_node_paths
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot repair ${_file}"* ]]
  [[ "$output" == *"${STABLE_NODE} does not exist"* ]]
  [ "$(cat "${_file}")" == "${_before}" ]
}

@test "repair_plugin_node_paths returns 1 for a file it cannot write, and still repairs the others" {
  [ "$(id -u)" -ne 0 ] || skip "root ignores the read-only mode this test relies on"
  _make_brew_node
  _make_plugin "ctx/ctx/1.0.169" "${STALE_NODE}"
  local _dir="${_OVERRIDE_CLAUDE_PLUGIN_CACHE}/ctx/ctx/1.0.169"
  chmod 444 "${_dir}/hooks/hooks.json"

  run repair_plugin_node_paths
  chmod 644 "${_dir}/hooks/hooks.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot repair ${_dir}/hooks/hooks.json: rewrite failed"* ]]
  grep -qF "${STALE_NODE}" "${_dir}/hooks/hooks.json"
  grep -qF "\"command\":\"${STABLE_NODE}\"" "${_dir}/.claude-plugin/plugin.json"
}

@test "repair_plugin_node_paths is a no-op on a second run" {
  _make_brew_node
  _make_plugin "ctx/ctx/1.0.169" "${STALE_NODE}"
  local _file="${_OVERRIDE_CLAUDE_PLUGIN_CACHE}/ctx/ctx/1.0.169/hooks/hooks.json"
  repair_plugin_node_paths >/dev/null
  local _after_first
  _after_first="$(cat "${_file}")"

  run repair_plugin_node_paths
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(cat "${_file}")" == "${_after_first}" ]
}

@test "repair_plugin_node_paths returns 2 when there is no plugin cache" {
  run repair_plugin_node_paths
  [ "$status" -eq 2 ]
  [ -z "$output" ]
}

@test "repair_plugin_node_paths changes only the stale path, keeping a live pin and the rest of the file" {
  _make_brew_node
  local _live="${BREW_PREFIX}/Cellar/node/2.0.0/bin/node"
  local _dir="${_OVERRIDE_CLAUDE_PLUGIN_CACHE}/ctx/ctx/1.0.169"
  mkdir -p "${_dir}/hooks"
  printf '{"a":"%s x","b":"%s y","c":"keep"}\n' "${STALE_NODE}" "${_live}" > "${_dir}/hooks/hooks.json"

  run repair_plugin_node_paths
  [ "$status" -eq 0 ]
  [ "$(cat "${_dir}/hooks/hooks.json")" == "{\"a\":\"${STABLE_NODE} x\",\"b\":\"${_live} y\",\"c\":\"keep\"}" ]
}

@test "repair_plugin_node_paths maps a node@NN pin to that formula's opt link" {
  mkdir -p "${BREW_PREFIX}/Cellar/node@22/22.2.0/bin" "${BREW_PREFIX}/opt"
  printf '#!/bin/sh\n' > "${BREW_PREFIX}/Cellar/node@22/22.2.0/bin/node"
  chmod +x "${BREW_PREFIX}/Cellar/node@22/22.2.0/bin/node"
  ln -s ../Cellar/node@22/22.2.0 "${BREW_PREFIX}/opt/node@22"
  _make_plugin "ctx/ctx/1.0.169" "${BREW_PREFIX}/Cellar/node@22/22.1.0/bin/node"

  run repair_plugin_node_paths
  [ "$status" -eq 0 ]
  grep -qF "\"command\":\"${BREW_PREFIX}/opt/node@22/bin/node\"" \
    "${_OVERRIDE_CLAUDE_PLUGIN_CACHE}/ctx/ctx/1.0.169/.claude-plugin/plugin.json"
}
