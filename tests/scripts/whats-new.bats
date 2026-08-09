#!/usr/bin/env bats

# Tests for scripts/whats-new-claude-code.sh

FAKE_CHANGELOG="## [1.0.1] - 2026-05-08
### Added
- New feature X

## [1.0.0] - 2026-05-01
### Added
- Initial release"

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_mocks

  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  touch "${MOCK_CALLS_FILE}"

  export MOCK_CURL_STDOUT="${FAKE_CHANGELOG}"
  export MOCK_CLAUDE_STDOUT="## New Features
- Added new feature X"

  export _OVERRIDE_FEATURES_DIR="${BATS_TEST_TMPDIR}/features"
  export _OVERRIDE_DOTFILES_ROOT="${BATS_TEST_TMPDIR}"
  mkdir -p "${_OVERRIDE_FEATURES_DIR}"
}

teardown() {
  true
}

# ── extract_new_content ──────────────────────────────────────────────────────

@test "extract_new_content: returns full content when no state file exists" {
  source "${REPO_ROOT}/scripts/whats-new-claude-code.sh"
  STATE_FILE="${BATS_TEST_TMPDIR}/.state.md"

  run extract_new_content "line1
line2"
  [ "$status" -eq 0 ]
  [[ "$output" == *"line1"* ]]
  [[ "$output" == *"line2"* ]]
}

@test "extract_new_content: returns empty when state file matches current" {
  source "${REPO_ROOT}/scripts/whats-new-claude-code.sh"
  STATE_FILE="${BATS_TEST_TMPDIR}/.state.md"
  printf "line1\nline2" > "${STATE_FILE}"

  run extract_new_content "line1
line2"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "extract_new_content: returns only added lines when state file differs" {
  source "${REPO_ROOT}/scripts/whats-new-claude-code.sh"
  STATE_FILE="${BATS_TEST_TMPDIR}/.state.md"
  # Mirrors real CHANGELOG usage: existing content at bottom, new entry prepended at top
  printf "existing content" > "${STATE_FILE}"

  run extract_new_content "new entry
existing content"
  [ "$status" -eq 0 ]
  [[ "$output" == *"new entry"* ]]
  [[ "$output" != *"existing content"* ]]
}

# ── main --dry-run ───────────────────────────────────────────────────────────

@test "main --dry-run: prints summary without creating output file" {
  local _today
  _today="$(date +%Y-%m-%d)"

  run env \
    _OVERRIDE_FEATURES_DIR="${_OVERRIDE_FEATURES_DIR}" \
    _OVERRIDE_DOTFILES_ROOT="${_OVERRIDE_DOTFILES_ROOT}" \
    MOCK_CALLS_FILE="${MOCK_CALLS_FILE}" \
    MOCK_CURL_STDOUT="${MOCK_CURL_STDOUT}" \
    MOCK_CLAUDE_STDOUT="${MOCK_CLAUDE_STDOUT}" \
    PATH="${REPO_ROOT}/tests/mocks:${PATH}" \
    bash "${REPO_ROOT}/scripts/whats-new-claude-code.sh" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"New Features"* ]]
  [ ! -f "${_OVERRIDE_FEATURES_DIR}/features-${_today}.md" ]
}

@test "main --dry-run: exits 1 when claude CLI is missing" {
  run env \
    _OVERRIDE_FEATURES_DIR="${_OVERRIDE_FEATURES_DIR}" \
    _OVERRIDE_DOTFILES_ROOT="${_OVERRIDE_DOTFILES_ROOT}" \
    MOCK_CALLS_FILE="${MOCK_CALLS_FILE}" \
    MOCK_CURL_STDOUT="${MOCK_CURL_STDOUT}" \
    PATH="/usr/bin:/bin" \
    bash "${REPO_ROOT}/scripts/whats-new-claude-code.sh" --dry-run
  [ "$status" -eq 1 ]
  [[ "$output" == *"claude CLI not found"* ]]
}

@test "main --dry-run: exits 1 when curl fails" {
  run env \
    _OVERRIDE_FEATURES_DIR="${_OVERRIDE_FEATURES_DIR}" \
    _OVERRIDE_DOTFILES_ROOT="${_OVERRIDE_DOTFILES_ROOT}" \
    MOCK_CALLS_FILE="${MOCK_CALLS_FILE}" \
    MOCK_CURL_EXIT="1" \
    PATH="${REPO_ROOT}/tests/mocks:${PATH}" \
    bash "${REPO_ROOT}/scripts/whats-new-claude-code.sh" --dry-run
  [ "$status" -eq 1 ]
  [[ "$output" == *"Error"* ]]
}

# ── main (normal mode) ───────────────────────────────────────────────────────

@test "main: skips when output file already exists" {
  local _today
  _today="$(date +%Y-%m-%d)"
  printf "existing content\n" > "${_OVERRIDE_FEATURES_DIR}/features-${_today}.md"

  run env \
    _OVERRIDE_FEATURES_DIR="${_OVERRIDE_FEATURES_DIR}" \
    _OVERRIDE_DOTFILES_ROOT="${_OVERRIDE_DOTFILES_ROOT}" \
    MOCK_CALLS_FILE="${MOCK_CALLS_FILE}" \
    PATH="${REPO_ROOT}/tests/mocks:${PATH}" \
    bash "${REPO_ROOT}/scripts/whats-new-claude-code.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already exists"* ]]
  ! grep -q "^curl" "${MOCK_CALLS_FILE}"
}

@test "main: creates output file on happy path" {
  local _today
  _today="$(date +%Y-%m-%d)"

  run env \
    _OVERRIDE_FEATURES_DIR="${_OVERRIDE_FEATURES_DIR}" \
    _OVERRIDE_DOTFILES_ROOT="${_OVERRIDE_DOTFILES_ROOT}" \
    MOCK_CALLS_FILE="${MOCK_CALLS_FILE}" \
    MOCK_CURL_STDOUT="${MOCK_CURL_STDOUT}" \
    MOCK_CLAUDE_STDOUT="${MOCK_CLAUDE_STDOUT}" \
    PATH="${REPO_ROOT}/tests/mocks:${PATH}" \
    bash "${REPO_ROOT}/scripts/whats-new-claude-code.sh"
  [ "$status" -eq 0 ]
  [ -f "${_OVERRIDE_FEATURES_DIR}/features-${_today}.md" ]
  grep -q "New Features" "${_OVERRIDE_FEATURES_DIR}/features-${_today}.md"
}

@test "main: commits output file and state file to git" {
  run env \
    _OVERRIDE_FEATURES_DIR="${_OVERRIDE_FEATURES_DIR}" \
    _OVERRIDE_DOTFILES_ROOT="${_OVERRIDE_DOTFILES_ROOT}" \
    MOCK_CALLS_FILE="${MOCK_CALLS_FILE}" \
    MOCK_CURL_STDOUT="${MOCK_CURL_STDOUT}" \
    MOCK_CLAUDE_STDOUT="${MOCK_CLAUDE_STDOUT}" \
    PATH="${REPO_ROOT}/tests/mocks:${PATH}" \
    bash "${REPO_ROOT}/scripts/whats-new-claude-code.sh"
  [ "$status" -eq 0 ]
  grep -q "^git add" "${MOCK_CALLS_FILE}"
  grep -q "^git commit" "${MOCK_CALLS_FILE}"
}

@test "main: sends ntfy notification when NTFY_URL is set" {
  run env \
    _OVERRIDE_FEATURES_DIR="${_OVERRIDE_FEATURES_DIR}" \
    _OVERRIDE_DOTFILES_ROOT="${_OVERRIDE_DOTFILES_ROOT}" \
    MOCK_CALLS_FILE="${MOCK_CALLS_FILE}" \
    MOCK_CURL_STDOUT="${MOCK_CURL_STDOUT}" \
    MOCK_CLAUDE_STDOUT="${MOCK_CLAUDE_STDOUT}" \
    NTFY_URL="http://ntfy.example.com/test" \
    PATH="${REPO_ROOT}/tests/mocks:${PATH}" \
    bash "${REPO_ROOT}/scripts/whats-new-claude-code.sh"
  [ "$status" -eq 0 ]
  grep -q "ntfy.example.com" "${MOCK_CALLS_FILE}"
}

@test "main: skips ntfy when NTFY_URL is not set" {
  run env \
    _OVERRIDE_FEATURES_DIR="${_OVERRIDE_FEATURES_DIR}" \
    _OVERRIDE_DOTFILES_ROOT="${_OVERRIDE_DOTFILES_ROOT}" \
    MOCK_CALLS_FILE="${MOCK_CALLS_FILE}" \
    MOCK_CURL_STDOUT="${MOCK_CURL_STDOUT}" \
    MOCK_CLAUDE_STDOUT="${MOCK_CLAUDE_STDOUT}" \
    PATH="${REPO_ROOT}/tests/mocks:${PATH}" \
    bash "${REPO_ROOT}/scripts/whats-new-claude-code.sh"
  [ "$status" -eq 0 ]
  local _curl_calls
  _curl_calls="$(grep -c "^curl" "${MOCK_CALLS_FILE}" || true)"
  [ "${_curl_calls}" -eq 1 ]
}

@test "send_ntfy: warns but continues when curl fails" {
  source "${REPO_ROOT}/scripts/whats-new-claude-code.sh"
  printf "digest content\n" > "${OUTPUT_FILE}"
  export NTFY_URL="http://ntfy.example.com/test"
  export MOCK_CURL_EXIT=1
  run send_ntfy
  [ "$status" -eq 0 ]
  [[ "$output" == *"Warning: ntfy notification failed"* ]]
}

# ── usage / arg parsing ──────────────────────────────────────────────────────

@test "main -h: prints usage and returns 0" {
  run bash "${REPO_ROOT}/scripts/whats-new-claude-code.sh" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"--dry-run"* ]]
}

@test "main: unknown option prints error and usage, returns 1" {
  run bash "${REPO_ROOT}/scripts/whats-new-claude-code.sh" --bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown option: --bogus"* ]]
  [[ "$output" == *"Usage:"* ]]
}

# ── generate_summary ─────────────────────────────────────────────────────────

@test "generate_summary: returns 1 when claude fails" {
  source "${REPO_ROOT}/scripts/whats-new-claude-code.sh"
  export MOCK_CLAUDE_EXIT=1
  local _rc=0
  generate_summary "some new changelog content" || _rc=$?
  [ "${_rc}" -ne 0 ]
}

# ── commit_and_push ──────────────────────────────────────────────────────────

@test "commit_and_push: returns 1 when cd to dotfiles root fails" {
  source "${REPO_ROOT}/scripts/whats-new-claude-code.sh"
  DOTFILES_ROOT="${BATS_TEST_TMPDIR}/does-not-exist"
  local _rc=0
  commit_and_push || _rc=$?
  [ "${_rc}" -ne 0 ]
}

@test "commit_and_push: returns 1 when git commit fails" {
  source "${REPO_ROOT}/scripts/whats-new-claude-code.sh"
  export MOCK_GIT_EXIT=1
  local _rc=0
  commit_and_push || _rc=$?
  [ "${_rc}" -ne 0 ]
}

@test "commit_and_push: warns but returns 0 when git push fails after a successful commit" {
  source "${REPO_ROOT}/scripts/whats-new-claude-code.sh"

  # Real git, not the mock: tests/mocks/git can't fail push-only while
  # leaving add/commit successful (MOCK_GIT_EXIT applies to every git
  # invocation alike). A real repo with no remote lets `git commit` succeed
  # for real and `git push` fail for real ("No configured push destination").
  local _real_path
  _real_path="$(printf "%s" "${PATH}" | tr ':' '\n' | grep -v "tests/mocks" | tr '\n' ':' | sed 's/:$//')"

  DOTFILES_ROOT="${BATS_TEST_TMPDIR}/realrepo"
  mkdir -p "${DOTFILES_ROOT}"
  OUTPUT_FILE="${DOTFILES_ROOT}/features.md"
  STATE_FILE="${DOTFILES_ROOT}/.changelog-state.md"
  printf "digest\n" > "${OUTPUT_FILE}"
  printf "state\n" > "${STATE_FILE}"

  PATH="${_real_path}" git -C "${DOTFILES_ROOT}" init -q
  PATH="${_real_path}" git -C "${DOTFILES_ROOT}" config user.email "test@example.com"
  PATH="${_real_path}" git -C "${DOTFILES_ROOT}" config user.name "Test"

  local _rc=0
  PATH="${_real_path}" commit_and_push || _rc=$?
  [ "${_rc}" -eq 0 ]
  PATH="${_real_path}" git -C "${DOTFILES_ROOT}" log -1 --format=%s | grep -q "Claude Code weekly features digest"
}

# ── main: empty new content ──────────────────────────────────────────────────

@test "main: skips summary when no new changelog entries since last run" {
  printf "%s" "${MOCK_CURL_STDOUT}" > "${_OVERRIDE_FEATURES_DIR}/.changelog-state.md"

  run env \
    _OVERRIDE_FEATURES_DIR="${_OVERRIDE_FEATURES_DIR}" \
    _OVERRIDE_DOTFILES_ROOT="${_OVERRIDE_DOTFILES_ROOT}" \
    MOCK_CALLS_FILE="${MOCK_CALLS_FILE}" \
    MOCK_CURL_STDOUT="${MOCK_CURL_STDOUT}" \
    PATH="${REPO_ROOT}/tests/mocks:${PATH}" \
    bash "${REPO_ROOT}/scripts/whats-new-claude-code.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No new CHANGELOG entries since last run."* ]]
  refute_grep "^git commit" "${MOCK_CALLS_FILE}"
}
