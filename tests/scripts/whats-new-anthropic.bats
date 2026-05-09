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

# ── generate_summary ─────────────────────────────────────────────────────────

@test "generate_summary: returns claude output on success" {
  source "${REPO_ROOT}/scripts/whats-new-anthropic.sh"
  result="$(generate_summary "platform diff content" "sdk diff content")"
  [ $? -eq 0 ]
  [[ "${result}" == *"Claude Opus 4.7"* ]]
}

@test "generate_summary: passes both diffs to claude under labelled headers" {
  source "${REPO_ROOT}/scripts/whats-new-anthropic.sh"
  generate_summary "PLATFORM_CONTENT" "SDK_CONTENT"
  grep -q "claude" "${MOCK_CALLS_FILE}"
}

@test "generate_summary: returns 1 when claude fails" {
  source "${REPO_ROOT}/scripts/whats-new-anthropic.sh"
  export MOCK_CLAUDE_EXIT=1
  local _rc=0
  generate_summary "platform" "sdk" || _rc=$?
  [ "${_rc}" -ne 0 ]
}

# ── write_output ─────────────────────────────────────────────────────────────

@test "write_output: creates output file with header and summary" {
  source "${REPO_ROOT}/scripts/whats-new-anthropic.sh"
  local _today
  _today="$(date +%Y-%m-%d)"
  write_output "## Model & API Changes
- Claude Opus 4.7 launched"
  [ -f "${_OVERRIDE_FEATURES_DIR}/features-${_today}.md" ]
  grep -q "Anthropic & Claude API" "${_OVERRIDE_FEATURES_DIR}/features-${_today}.md"
  grep -q "Claude Opus 4.7" "${_OVERRIDE_FEATURES_DIR}/features-${_today}.md"
  grep -q "platform.claude.com" "${_OVERRIDE_FEATURES_DIR}/features-${_today}.md"
}

# ── commit_and_push ──────────────────────────────────────────────────────────

@test "commit_and_push: runs git add, commit, and push" {
  source "${REPO_ROOT}/scripts/whats-new-anthropic.sh"
  commit_and_push
  grep -q "^git add" "${MOCK_CALLS_FILE}"
  grep -q "^git commit" "${MOCK_CALLS_FILE}"
  grep -q "^git push" "${MOCK_CALLS_FILE}"
}

@test "commit_and_push: returns 1 when git commit fails" {
  source "${REPO_ROOT}/scripts/whats-new-anthropic.sh"
  export MOCK_GIT_EXIT=1
  local _rc=0
  commit_and_push || _rc=$?
  [ "${_rc}" -ne 0 ]
}

# ── send_ntfy ────────────────────────────────────────────────────────────────

@test "send_ntfy: sends curl request when NTFY_URL is set" {
  source "${REPO_ROOT}/scripts/whats-new-anthropic.sh"
  local _today
  _today="$(date +%Y-%m-%d)"
  printf "digest content\n" > "${OUTPUT_FILE}"
  export NTFY_URL="http://ntfy.example.com/test"
  send_ntfy
  grep -q "ntfy.example.com" "${MOCK_CALLS_FILE}"
}

@test "send_ntfy: skips when NTFY_URL is not set" {
  source "${REPO_ROOT}/scripts/whats-new-anthropic.sh"
  local _today
  _today="$(date +%Y-%m-%d)"
  printf "digest content\n" > "${OUTPUT_FILE}"
  unset NTFY_URL
  send_ntfy
  ! grep -q "ntfy" "${MOCK_CALLS_FILE}"
}

# ── main (happy path + boundary) ─────────────────────────────────────────────

@test "main: creates output file and updates both state files on happy path" {
  local _today
  _today="$(date +%Y-%m-%d)"

  run env \
    _OVERRIDE_FEATURES_DIR="${_OVERRIDE_FEATURES_DIR}" \
    _OVERRIDE_DOTFILES_ROOT="${_OVERRIDE_DOTFILES_ROOT}" \
    MOCK_CALLS_FILE="${MOCK_CALLS_FILE}" \
    MOCK_CURL_PLATFORM_STDOUT="${MOCK_CURL_PLATFORM_STDOUT}" \
    MOCK_CURL_SDK_STDOUT="${MOCK_CURL_SDK_STDOUT}" \
    MOCK_CLAUDE_STDOUT="${MOCK_CLAUDE_STDOUT}" \
    PATH="${REPO_ROOT}/tests/mocks:${PATH}" \
    bash "${REPO_ROOT}/scripts/whats-new-anthropic.sh"
  [ "$status" -eq 0 ]
  [ -f "${_OVERRIDE_FEATURES_DIR}/features-${_today}.md" ]
  [ -f "${_OVERRIDE_FEATURES_DIR}/.platform-state.txt" ]
  [ -f "${_OVERRIDE_FEATURES_DIR}/.sdk-state.md" ]
  grep -q "^git add" "${MOCK_CALLS_FILE}"
  grep -q "^git commit" "${MOCK_CALLS_FILE}"
}

@test "main: skips when output file already exists (idempotency)" {
  local _today
  _today="$(date +%Y-%m-%d)"
  printf "existing digest\n" > "${_OVERRIDE_FEATURES_DIR}/features-${_today}.md"

  run env \
    _OVERRIDE_FEATURES_DIR="${_OVERRIDE_FEATURES_DIR}" \
    _OVERRIDE_DOTFILES_ROOT="${_OVERRIDE_DOTFILES_ROOT}" \
    MOCK_CALLS_FILE="${MOCK_CALLS_FILE}" \
    PATH="${REPO_ROOT}/tests/mocks:${PATH}" \
    bash "${REPO_ROOT}/scripts/whats-new-anthropic.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already exists"* ]]
  ! grep -q "^curl" "${MOCK_CALLS_FILE}"
}

@test "main: exits 0 with no commit when both diffs are empty" {
  local _today
  _today="$(date +%Y-%m-%d)"
  # Pre-populate state files with same content as mock output
  strip_result="$(printf "%s" "${FAKE_PLATFORM_HTML}" | python3 -c "
import sys, re
content = sys.stdin.read()
text = re.sub(r'<[^>]+>', ' ', content)
text = re.sub(r'\s+', ' ', text).strip()
print(text)
")"
  printf "%s" "${strip_result}" > "${_OVERRIDE_FEATURES_DIR}/.platform-state.txt"
  printf "%s" "${FAKE_SDK_CHANGELOG}" > "${_OVERRIDE_FEATURES_DIR}/.sdk-state.md"

  run env \
    _OVERRIDE_FEATURES_DIR="${_OVERRIDE_FEATURES_DIR}" \
    _OVERRIDE_DOTFILES_ROOT="${_OVERRIDE_DOTFILES_ROOT}" \
    MOCK_CALLS_FILE="${MOCK_CALLS_FILE}" \
    MOCK_CURL_PLATFORM_STDOUT="${MOCK_CURL_PLATFORM_STDOUT}" \
    MOCK_CURL_SDK_STDOUT="${MOCK_CURL_SDK_STDOUT}" \
    MOCK_CLAUDE_STDOUT="${MOCK_CLAUDE_STDOUT}" \
    PATH="${REPO_ROOT}/tests/mocks:${PATH}" \
    bash "${REPO_ROOT}/scripts/whats-new-anthropic.sh"
  [ "$status" -eq 0 ]
  [ ! -f "${_OVERRIDE_FEATURES_DIR}/features-${_today}.md" ]
  ! grep -q "^git commit" "${MOCK_CALLS_FILE}"
}

@test "main: proceeds to summary when only platform diff is non-empty" {
  local _today
  _today="$(date +%Y-%m-%d)"
  # Pre-populate SDK state so SDK diff is empty; platform state absent so platform diff is full
  printf "%s" "${FAKE_SDK_CHANGELOG}" > "${_OVERRIDE_FEATURES_DIR}/.sdk-state.md"

  run env \
    _OVERRIDE_FEATURES_DIR="${_OVERRIDE_FEATURES_DIR}" \
    _OVERRIDE_DOTFILES_ROOT="${_OVERRIDE_DOTFILES_ROOT}" \
    MOCK_CALLS_FILE="${MOCK_CALLS_FILE}" \
    MOCK_CURL_PLATFORM_STDOUT="${MOCK_CURL_PLATFORM_STDOUT}" \
    MOCK_CURL_SDK_STDOUT="${MOCK_CURL_SDK_STDOUT}" \
    MOCK_CLAUDE_STDOUT="${MOCK_CLAUDE_STDOUT}" \
    PATH="${REPO_ROOT}/tests/mocks:${PATH}" \
    bash "${REPO_ROOT}/scripts/whats-new-anthropic.sh"
  [ "$status" -eq 0 ]
  [ -f "${_OVERRIDE_FEATURES_DIR}/features-${_today}.md" ]
}

@test "main: proceeds to summary when only SDK diff is non-empty" {
  local _today
  _today="$(date +%Y-%m-%d)"
  # Pre-populate platform state so platform diff is empty; SDK state absent so SDK diff is full
  strip_result="$(printf "%s" "${FAKE_PLATFORM_HTML}" | python3 -c "
import sys, re
content = sys.stdin.read()
text = re.sub(r'<[^>]+>', ' ', content)
text = re.sub(r'\s+', ' ', text).strip()
print(text)
")"
  printf "%s" "${strip_result}" > "${_OVERRIDE_FEATURES_DIR}/.platform-state.txt"

  run env \
    _OVERRIDE_FEATURES_DIR="${_OVERRIDE_FEATURES_DIR}" \
    _OVERRIDE_DOTFILES_ROOT="${_OVERRIDE_DOTFILES_ROOT}" \
    MOCK_CALLS_FILE="${MOCK_CALLS_FILE}" \
    MOCK_CURL_PLATFORM_STDOUT="${MOCK_CURL_PLATFORM_STDOUT}" \
    MOCK_CURL_SDK_STDOUT="${MOCK_CURL_SDK_STDOUT}" \
    MOCK_CLAUDE_STDOUT="${MOCK_CLAUDE_STDOUT}" \
    PATH="${REPO_ROOT}/tests/mocks:${PATH}" \
    bash "${REPO_ROOT}/scripts/whats-new-anthropic.sh"
  [ "$status" -eq 0 ]
  [ -f "${_OVERRIDE_FEATURES_DIR}/features-${_today}.md" ]
}

@test "main --dry-run: prints summary without creating output file" {
  local _today
  _today="$(date +%Y-%m-%d)"

  run env \
    _OVERRIDE_FEATURES_DIR="${_OVERRIDE_FEATURES_DIR}" \
    _OVERRIDE_DOTFILES_ROOT="${_OVERRIDE_DOTFILES_ROOT}" \
    MOCK_CALLS_FILE="${MOCK_CALLS_FILE}" \
    MOCK_CURL_PLATFORM_STDOUT="${MOCK_CURL_PLATFORM_STDOUT}" \
    MOCK_CURL_SDK_STDOUT="${MOCK_CURL_SDK_STDOUT}" \
    MOCK_CLAUDE_STDOUT="${MOCK_CLAUDE_STDOUT}" \
    PATH="${REPO_ROOT}/tests/mocks:${PATH}" \
    bash "${REPO_ROOT}/scripts/whats-new-anthropic.sh" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Model & API Changes"* ]]
  [ ! -f "${_OVERRIDE_FEATURES_DIR}/features-${_today}.md" ]
  [ ! -f "${_OVERRIDE_FEATURES_DIR}/.platform-state.txt" ]
}

@test "main --dry-run: exits 1 when claude CLI is missing" {
  run env \
    _OVERRIDE_FEATURES_DIR="${_OVERRIDE_FEATURES_DIR}" \
    _OVERRIDE_DOTFILES_ROOT="${_OVERRIDE_DOTFILES_ROOT}" \
    MOCK_CALLS_FILE="${MOCK_CALLS_FILE}" \
    PATH="/usr/bin:/bin" \
    bash "${REPO_ROOT}/scripts/whats-new-anthropic.sh" --dry-run
  [ "$status" -eq 1 ]
  [[ "$output" == *"claude CLI not found"* ]]
}

# ── main (error paths) ───────────────────────────────────────────────────────

@test "main: exits 1 when platform fetch fails" {
  run env \
    _OVERRIDE_FEATURES_DIR="${_OVERRIDE_FEATURES_DIR}" \
    _OVERRIDE_DOTFILES_ROOT="${_OVERRIDE_DOTFILES_ROOT}" \
    MOCK_CALLS_FILE="${MOCK_CALLS_FILE}" \
    MOCK_CURL_EXIT="1" \
    PATH="${REPO_ROOT}/tests/mocks:${PATH}" \
    bash "${REPO_ROOT}/scripts/whats-new-anthropic.sh"
  [ "$status" -eq 1 ]
  [ ! -f "${_OVERRIDE_FEATURES_DIR}/.platform-state.txt" ]
}

@test "main: exits 1 when claude fails, state files not modified" {
  run env \
    _OVERRIDE_FEATURES_DIR="${_OVERRIDE_FEATURES_DIR}" \
    _OVERRIDE_DOTFILES_ROOT="${_OVERRIDE_DOTFILES_ROOT}" \
    MOCK_CALLS_FILE="${MOCK_CALLS_FILE}" \
    MOCK_CURL_PLATFORM_STDOUT="${MOCK_CURL_PLATFORM_STDOUT}" \
    MOCK_CURL_SDK_STDOUT="${MOCK_CURL_SDK_STDOUT}" \
    MOCK_CLAUDE_EXIT="1" \
    PATH="${REPO_ROOT}/tests/mocks:${PATH}" \
    bash "${REPO_ROOT}/scripts/whats-new-anthropic.sh"
  [ "$status" -eq 1 ]
  [ ! -f "${_OVERRIDE_FEATURES_DIR}/.platform-state.txt" ]
  [ ! -f "${_OVERRIDE_FEATURES_DIR}/.sdk-state.md" ]
}

@test "main: non-zero exit when git push fails but output file exists" {
  run env \
    _OVERRIDE_FEATURES_DIR="${_OVERRIDE_FEATURES_DIR}" \
    _OVERRIDE_DOTFILES_ROOT="${_OVERRIDE_DOTFILES_ROOT}" \
    MOCK_CALLS_FILE="${MOCK_CALLS_FILE}" \
    MOCK_CURL_PLATFORM_STDOUT="${MOCK_CURL_PLATFORM_STDOUT}" \
    MOCK_CURL_SDK_STDOUT="${MOCK_CURL_SDK_STDOUT}" \
    MOCK_CLAUDE_STDOUT="${MOCK_CLAUDE_STDOUT}" \
    MOCK_GIT_EXIT="1" \
    PATH="${REPO_ROOT}/tests/mocks:${PATH}" \
    bash "${REPO_ROOT}/scripts/whats-new-anthropic.sh"
  [ "$status" -ne 0 ]
}

@test "main: ntfy notification sent when NTFY_URL is set" {
  run env \
    _OVERRIDE_FEATURES_DIR="${_OVERRIDE_FEATURES_DIR}" \
    _OVERRIDE_DOTFILES_ROOT="${_OVERRIDE_DOTFILES_ROOT}" \
    MOCK_CALLS_FILE="${MOCK_CALLS_FILE}" \
    MOCK_CURL_PLATFORM_STDOUT="${MOCK_CURL_PLATFORM_STDOUT}" \
    MOCK_CURL_SDK_STDOUT="${MOCK_CURL_SDK_STDOUT}" \
    MOCK_CLAUDE_STDOUT="${MOCK_CLAUDE_STDOUT}" \
    NTFY_URL="http://ntfy.example.com/test" \
    PATH="${REPO_ROOT}/tests/mocks:${PATH}" \
    bash "${REPO_ROOT}/scripts/whats-new-anthropic.sh"
  [ "$status" -eq 0 ]
  grep -q "ntfy.example.com" "${MOCK_CALLS_FILE}"
}
