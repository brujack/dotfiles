#!/usr/bin/env bats
# Coverage for tests/mocks/claude's --json list modes, MOCK_CLAUDE_FAIL_ARGS,
# MOCK_CLAUDE_FAIL_ON_CALL, and MOCK_CLAUDE_EDIT_SETTINGS. These are the seams
# _claude_plugin_manifest/_claude_registered_marketplaces/_claude_installed_user_ids
# and the settings write guard (later tasks) are tested through, so the mock's
# own behavior is pinned here rather than only exercised incidentally.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_mocks
  load_setup_env
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  touch "${MOCK_CALLS_FILE}"
  CLAUDE_MOCK="${REPO_ROOT}/tests/mocks/claude"
  unset MOCK_CLAUDE_PLUGINS_LIST_JSON MOCK_CLAUDE_MARKETPLACE_LIST_JSON \
    MOCK_CLAUDE_PLUGINS_LIST_OUTPUT MOCK_CLAUDE_FAIL_ARGS MOCK_CLAUDE_FAIL_ON_CALL \
    MOCK_CLAUDE_EDIT_SETTINGS MOCK_CLAUDE_EXIT MOCK_CLAUDE_STDOUT
}

@test "claude mock: plugins list --json defaults to []" {
  run "${CLAUDE_MOCK}" plugins list --json
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "claude mock: plugins marketplace list --json defaults to []" {
  run "${CLAUDE_MOCK}" plugins marketplace list --json
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "claude mock: plugins list --json echoes MOCK_CLAUDE_PLUGINS_LIST_JSON when set" {
  export MOCK_CLAUDE_PLUGINS_LIST_JSON='[{"id":"a@m","scope":"user"}]'
  run "${CLAUDE_MOCK}" plugins list --json
  [ "$status" -eq 0 ]
  [ "$output" = '[{"id":"a@m","scope":"user"}]' ]
}

@test "claude mock: plugins marketplace list --json echoes MOCK_CLAUDE_MARKETPLACE_LIST_JSON when set" {
  export MOCK_CLAUDE_MARKETPLACE_LIST_JSON='[{"name":"caveman"}]'
  run "${CLAUDE_MOCK}" plugins marketplace list --json
  [ "$status" -eq 0 ]
  [ "$output" = '[{"name":"caveman"}]' ]
}

@test "claude mock: plugins list (no --json) still prints MOCK_CLAUDE_PLUGINS_LIST_OUTPUT" {
  export MOCK_CLAUDE_PLUGINS_LIST_OUTPUT="superpowers@claude-plugins-official"
  run "${CLAUDE_MOCK}" plugins list
  [ "$status" -eq 0 ]
  [ "$output" = "superpowers@claude-plugins-official" ]
}

@test "claude mock: MOCK_CLAUDE_FAIL_ARGS matching the full argv fails that call" {
  export MOCK_CLAUDE_FAIL_ARGS="marketplace add"
  run "${CLAUDE_MOCK}" plugins marketplace add anthropics/claude-plugins-official
  [ "$status" -eq 1 ]
}

@test "claude mock: MOCK_CLAUDE_FAIL_ARGS does not fail a non-matching call" {
  export MOCK_CLAUDE_FAIL_ARGS="marketplace add"
  run "${CLAUDE_MOCK}" plugins install -s user superpowers@claude-plugins-official
  [ "$status" -eq 0 ]
}

@test "claude mock: MOCK_CLAUDE_FAIL_ON_CALL=2 passes call 1 and fails call 2" {
  export MOCK_CLAUDE_FAIL_ON_CALL=2
  run "${CLAUDE_MOCK}" plugins list --json
  [ "$status" -eq 0 ]
  run "${CLAUDE_MOCK}" plugins list --json
  [ "$status" -eq 1 ]
}

@test "claude mock: MOCK_CLAUDE_FAIL_ON_CALL counter is not advanced by marketplace list --json" {
  export MOCK_CLAUDE_FAIL_ON_CALL=2
  # Two marketplace list calls must not count toward the plugins-list counter --
  # the third call here is the first REAL "plugins list --json" call and must
  # still pass, since only the second such call should fail.
  run "${CLAUDE_MOCK}" plugins marketplace list --json
  [ "$status" -eq 0 ]
  run "${CLAUDE_MOCK}" plugins marketplace list --json
  [ "$status" -eq 0 ]
  run "${CLAUDE_MOCK}" plugins list --json
  [ "$status" -eq 0 ]
}

@test "claude mock: MOCK_CLAUDE_EDIT_SETTINGS=install grows the settings file on plugins install" {
  local _settings="${BATS_TEST_TMPDIR}/settings.json"
  printf '{}' > "${_settings}"
  local _before
  _before="$(wc -c < "${_settings}")"
  export MOCK_CLAUDE_EDIT_SETTINGS=install
  export _OVERRIDE_CLAUDE_SETTINGS="${_settings}"
  run "${CLAUDE_MOCK}" plugins install -s user x@y
  [ "$status" -eq 0 ]
  local _after
  _after="$(wc -c < "${_settings}")"
  [ "$((_after - _before))" -eq 1 ]
}

@test "claude mock: MOCK_CLAUDE_EDIT_SETTINGS=install does not grow the settings file on plugins update" {
  local _settings="${BATS_TEST_TMPDIR}/settings2.json"
  printf '{}' > "${_settings}"
  local _before
  _before="$(wc -c < "${_settings}")"
  export MOCK_CLAUDE_EDIT_SETTINGS=install
  export _OVERRIDE_CLAUDE_SETTINGS="${_settings}"
  run "${CLAUDE_MOCK}" plugins update x@y
  [ "$status" -eq 0 ]
  local _after
  _after="$(wc -c < "${_settings}")"
  [ "${_after}" -eq "${_before}" ]
}

@test "claude mock: every call is logged to MOCK_CALLS_FILE" {
  "${CLAUDE_MOCK}" plugins list --json > /dev/null
  "${CLAUDE_MOCK}" plugins marketplace list --json > /dev/null
  grep -qF "claude plugins list --json" "${MOCK_CALLS_FILE}"
  grep -qF "claude plugins marketplace list --json" "${MOCK_CALLS_FILE}"
}

@test "claude mock: plugin (singular) install still exits 0 by default" {
  run "${CLAUDE_MOCK}" plugin install -s user superpowers@claude-plugins-official
  [ "$status" -eq 0 ]
}

@test "claude mock: -p mode is unaffected by the new plugins/plugin case" {
  run "${CLAUDE_MOCK}" -p "some prompt"
  [ "$status" -eq 0 ]
  [ "$output" = "## New Features
- Mock feature added" ]
}
