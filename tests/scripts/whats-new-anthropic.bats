#!/usr/bin/env bats

# Tests for scripts/whats-new-anthropic.sh

FAKE_PLATFORM_HTML="<html><body><h1>Release notes</h1><p>May 2026 Claude Opus 4.7 launched.</p></body></html>"
FAKE_PLATFORM_TEXT="Release notes May 2026 Claude Opus 4.7 launched."

FAKE_SDK_CHANGELOG="## 0.100.0 (2026-05-06)
### Features
* api: add Managed Agents support"

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_mocks

  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  touch "${MOCK_CALLS_FILE}"

  export MOCK_CURL_PLATFORM_STDOUT="${FAKE_PLATFORM_HTML}"
  export MOCK_CURL_SDK_STDOUT="${FAKE_SDK_CHANGELOG}"
  export MOCK_CLAUDE_STDOUT="## Model & API Changes
- Claude Opus 4.7 launched"

  export _OVERRIDE_FEATURES_DIR="${BATS_TEST_TMPDIR}/features"
  export _OVERRIDE_DOTFILES_ROOT="${BATS_TEST_TMPDIR}"
  mkdir -p "${_OVERRIDE_FEATURES_DIR}"
}

teardown() {
  true
}

# ── strip_html ───────────────────────────────────────────────────────────────

@test "strip_html: removes HTML tags and collapses whitespace" {
  source "${REPO_ROOT}/scripts/whats-new-anthropic.sh"
  result="$(printf "%s" "${FAKE_PLATFORM_HTML}" | strip_html)"
  [[ "${result}" != *"<html>"* ]]
  [[ "${result}" == *"Release notes"* ]]
  [[ "${result}" == *"Claude Opus 4.7 launched"* ]]
}

# ── fetch_platform_notes ─────────────────────────────────────────────────────

@test "fetch_platform_notes: fetches and strips HTML from platform page" {
  source "${REPO_ROOT}/scripts/whats-new-anthropic.sh"
  result="$(fetch_platform_notes)"
  [ $? -eq 0 ]
  [[ "${result}" == *"Claude Opus 4.7 launched"* ]]
  [[ "${result}" != *"<html>"* ]]
  grep -q "platform.claude.com" "${MOCK_CALLS_FILE}"
}

@test "fetch_platform_notes: returns 1 when curl fails" {
  source "${REPO_ROOT}/scripts/whats-new-anthropic.sh"
  export MOCK_CURL_EXIT=1
  local _rc=0
  fetch_platform_notes || _rc=$?
  [ "${_rc}" -ne 0 ]
}

# ── fetch_sdk_changelog ──────────────────────────────────────────────────────

@test "fetch_sdk_changelog: fetches raw markdown from GitHub" {
  source "${REPO_ROOT}/scripts/whats-new-anthropic.sh"
  result="$(fetch_sdk_changelog)"
  [ $? -eq 0 ]
  [[ "${result}" == *"Managed Agents"* ]]
  grep -q "githubusercontent.com" "${MOCK_CALLS_FILE}"
}

@test "fetch_sdk_changelog: returns 1 when curl fails" {
  source "${REPO_ROOT}/scripts/whats-new-anthropic.sh"
  export MOCK_CURL_EXIT=1
  local _rc=0
  fetch_sdk_changelog || _rc=$?
  [ "${_rc}" -ne 0 ]
}

# ── extract_new_content ──────────────────────────────────────────────────────

@test "extract_new_content: returns full content when state file does not exist" {
  source "${REPO_ROOT}/scripts/whats-new-anthropic.sh"
  _state="${BATS_TEST_TMPDIR}/.missing-state"
  run extract_new_content "line1
line2" "${_state}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"line1"* ]]
  [[ "$output" == *"line2"* ]]
}

@test "extract_new_content: returns empty when state file matches current content" {
  source "${REPO_ROOT}/scripts/whats-new-anthropic.sh"
  _state="${BATS_TEST_TMPDIR}/.state-match"
  printf "line1\nline2" > "${_state}"
  run extract_new_content "line1
line2" "${_state}"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "extract_new_content: returns only new lines when content prepended" {
  source "${REPO_ROOT}/scripts/whats-new-anthropic.sh"
  _state="${BATS_TEST_TMPDIR}/.state-old"
  printf "existing content" > "${_state}"
  run extract_new_content "new entry
existing content" "${_state}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"new entry"* ]]
  [[ "$output" != *"existing content"* ]]
}
