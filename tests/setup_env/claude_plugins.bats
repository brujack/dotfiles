#!/usr/bin/env bats
# Coverage for the plugin-manifest reader and the two CLI --json list readers
# (_claude_settings_path, _claude_plugin_manifest, _claude_registered_marketplaces,
# _claude_installed_user_ids). Task 2 of
# docs/superpowers/specs/2026-09-19-claude-plugin-provisioning-design.md.
# Later tasks (the write guard, the setup_claude_plugins reconcile) add more
# tests to this same file.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_mocks
  load_setup_env
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${HOME}"
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  touch "${MOCK_CALLS_FILE}"
  SETTINGS="${BATS_TEST_TMPDIR}/claude-settings.json"
  cp "${REPO_ROOT}/tests/fixtures/claude-settings.json" "${SETTINGS}"
  export _OVERRIDE_CLAUDE_SETTINGS="${SETTINGS}"
  unset MOCK_CLAUDE_PLUGINS_LIST_JSON MOCK_CLAUDE_MARKETPLACE_LIST_JSON MOCK_CLAUDE_FAIL_ARGS
}

# ── _claude_settings_path ───────────────────────────────────────────────────

@test "_claude_settings_path prints the override when set" {
  run _claude_settings_path
  [ "$status" -eq 0 ]
  [ "$output" = "${SETTINGS}" ]
}

@test "_claude_settings_path falls back to HOME/.claude/settings.json when unset" {
  unset _OVERRIDE_CLAUDE_SETTINGS
  run _claude_settings_path
  [ "$status" -eq 0 ]
  [ "$output" = "${HOME}/.claude/settings.json" ]
}

# ── _claude_plugin_manifest: marketplace lines ──────────────────────────────

@test "_claude_plugin_manifest emits a marketplace line for a github source" {
  run _claude_plugin_manifest
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qxF \
    "$(printf 'marketplace\tclaude-plugins-official\tanthropics/claude-plugins-official')"
}

@test "_claude_plugin_manifest emits a marketplace line for a git source, with the URL" {
  run _claude_plugin_manifest
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qxF \
    "$(printf 'marketplace\tcaveman\thttps://github.com/juliusbrussee/caveman.git')"
}

@test "_claude_plugin_manifest emits unsupported for an unknown source type" {
  cat > "${SETTINGS}" <<'JSON'
{"extraKnownMarketplaces":{"weird":{"source":{"source":"url","url":"https://example.com"}}}}
JSON
  run _claude_plugin_manifest
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qxF "$(printf 'unsupported\tweird\turl')"
}

@test "_claude_plugin_manifest emits unsupported for a github entry missing repo" {
  cat > "${SETTINGS}" <<'JSON'
{"extraKnownMarketplaces":{"broken":{"source":{"source":"github"}}}}
JSON
  run _claude_plugin_manifest
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qxF "$(printf 'unsupported\tbroken\tgithub')"
}

# ── _claude_plugin_manifest: plugin lines ───────────────────────────────────

@test "_claude_plugin_manifest emits true for an enabled plugin" {
  run _claude_plugin_manifest
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qxF \
    "$(printf 'plugin\tsuperpowers@claude-plugins-official\ttrue')"
}

@test "_claude_plugin_manifest emits false for a disabled plugin" {
  run _claude_plugin_manifest
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qxF \
    "$(printf 'plugin\tfrontend-design@claude-plugins-official\tfalse')"
}

@test "_claude_plugin_manifest emits false for a non-boolean enabledPlugins value" {
  cat > "${SETTINGS}" <<'JSON'
{"enabledPlugins":{"weird@m":"true"}}
JSON
  run _claude_plugin_manifest
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qxF "$(printf 'plugin\tweird@m\tfalse')"
}

# ── _claude_plugin_manifest: failure and empty-set contracts ────────────────

@test "_claude_plugin_manifest returns 1 with no stdout when the settings file is missing" {
  rm -f "${SETTINGS}"
  run _claude_plugin_manifest
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "_claude_plugin_manifest returns 1 with no stdout when the settings file is not JSON" {
  printf 'not json' > "${SETTINGS}"
  run _claude_plugin_manifest
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "_claude_plugin_manifest returns 1 with no stdout when the settings file is a JSON array" {
  printf '[]' > "${SETTINGS}"
  run _claude_plugin_manifest
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "_claude_plugin_manifest returns 0 with no lines when neither key is present" {
  printf '{}' > "${SETTINGS}"
  run _claude_plugin_manifest
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "_claude_plugin_manifest returns 1 with no stdout when python3 cannot be resolved" {
  local _shim="${BATS_TEST_TMPDIR}/no-python3-shim"
  mkdir -p "${_shim}"
  # The function's own body reaches only bash builtins ([[ -r ]], command -v)
  # before it would need python3, so an otherwise-empty shim directory is
  # sufficient to make python3 unresolvable -- never strip a real PATH
  # directory (e.g. /usr/bin) to hide one binary, since that takes every
  # other binary in it down too (shell.md: "scrubbing PATH to hide a binary
  # also removes every binary that shares its directory").
  PATH="${_shim}" run _claude_plugin_manifest
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

# ── _claude_registered_marketplaces ─────────────────────────────────────────

@test "_claude_registered_marketplaces prints one name per line" {
  export MOCK_CLAUDE_MARKETPLACE_LIST_JSON='[{"name":"claude-plugins-official"},{"name":"caveman"}]'
  run _claude_registered_marketplaces
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'claude-plugins-official\ncaveman')" ]
}

@test "_claude_registered_marketplaces returns 1 when the CLI call fails" {
  export MOCK_CLAUDE_FAIL_ARGS="marketplace list --json"
  run _claude_registered_marketplaces
  [ "$status" -eq 1 ]
}

@test "_claude_registered_marketplaces returns 1 when the CLI output does not parse" {
  export MOCK_CLAUDE_MARKETPLACE_LIST_JSON='not json'
  run _claude_registered_marketplaces
  [ "$status" -eq 1 ]
}

# ── _claude_installed_user_ids ──────────────────────────────────────────────

@test "_claude_installed_user_ids prints only ids installed at user scope" {
  export MOCK_CLAUDE_PLUGINS_LIST_JSON='[{"id":"a@m","scope":"user"},{"id":"b@m","scope":"project"}]'
  run _claude_installed_user_ids
  [ "$status" -eq 0 ]
  [ "$output" = "a@m" ]
}

@test "_claude_installed_user_ids returns 1 when the CLI call fails" {
  export MOCK_CLAUDE_FAIL_ARGS="plugins list --json"
  run _claude_installed_user_ids
  [ "$status" -eq 1 ]
}

@test "_claude_installed_user_ids returns 1 when the CLI output does not parse" {
  export MOCK_CLAUDE_PLUGINS_LIST_JSON='not json'
  run _claude_installed_user_ids
  [ "$status" -eq 1 ]
}
