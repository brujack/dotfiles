# Anthropic & Claude API Weekly Digest — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `scripts/whats-new-anthropic.sh` that fetches Anthropic platform release notes (HTML) and the Python SDK CHANGELOG (markdown), diffs each against a stored state file, summarizes new content with `claude -p`, and commits a weekly digest to `docs/anthropic-new-features/` — mirroring the existing Claude Code digest system exactly.

**Architecture:** Two independent state files (`.platform-state.txt`, `.sdk-state.md`) each diffed against their respective fetched source. Both diffs are concatenated and passed to `claude -p` in one call, producing a single combined digest. The `curl` mock is updated with URL-pattern dispatch so tests can inject different content per source.

**Tech Stack:** Bash, BATS, Python 3 (stdlib only for HTML stripping), `claude` CLI, `curl`, `git`

---

## File Map

| Action | Path                                      | Purpose                                                                           |
| ------ | ----------------------------------------- | --------------------------------------------------------------------------------- |
| Modify | `tests/mocks/curl`                        | Add URL-pattern dispatch for `MOCK_CURL_PLATFORM_STDOUT` / `MOCK_CURL_SDK_STDOUT` |
| Create | `docs/anthropic-new-features/README.md`   | Usage and schedule docs                                                           |
| Create | `scripts/whats-new-anthropic.sh`          | Main digest script                                                                |
| Create | `tests/scripts/whats-new-anthropic.bats`  | BATS test suite                                                                   |
| Modify | `CLAUDE.md`                               | Layout table, seam table, mock vars table                                         |
| Create | `.claude/commands/whats-new-anthropic.md` | `/whats-new-anthropic` slash command                                              |

---

## Task 1: Update curl mock for URL-pattern dispatch

**Files:**

- Modify: `tests/mocks/curl`

The mock currently always emits `MOCK_CURL_STDOUT`. The new script makes two curl calls with different URLs. Add URL-pattern dispatch that checks `ORIG_ARGS` (saved before the shift loop) so each URL gets its own mock content.

- [ ] **Step 1: Replace `tests/mocks/curl` with the updated version**

```bash
#!/usr/bin/env bash
ORIG_ARGS="$*"
printf "curl %s\n" "${ORIG_ARGS}" >> "${MOCK_CALLS_FILE:-/tmp/mock_calls}"
# Handle -o <file>: create an empty placeholder file
outfile=""
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "-o" ]]; then
    outfile="$2"
    shift 2
  else
    shift
  fi
done
[[ -n "${outfile}" ]] && touch "${outfile}"
# URL-pattern dispatch for multi-source scripts; falls back to MOCK_CURL_STDOUT
if [[ "${ORIG_ARGS}" == *"platform.claude.com"* ]] && [[ -n "${MOCK_CURL_PLATFORM_STDOUT:-}" ]]; then
  printf "%s\n" "${MOCK_CURL_PLATFORM_STDOUT}"
elif [[ "${ORIG_ARGS}" == *"githubusercontent.com"* ]] && [[ -n "${MOCK_CURL_SDK_STDOUT:-}" ]]; then
  printf "%s\n" "${MOCK_CURL_SDK_STDOUT}"
elif [[ -n "${MOCK_CURL_STDOUT:-}" ]]; then
  printf "%s\n" "${MOCK_CURL_STDOUT}"
fi
exit "${MOCK_CURL_EXIT:-0}"
```

- [ ] **Step 2: Verify existing tests still pass (backward-compatibility check)**

```bash
make test
```

Expected: all tests pass. If any test using `MOCK_CURL_STDOUT` breaks, the dispatch logic is wrong — `MOCK_CURL_STDOUT` must still be the fallback when neither pattern-specific var is set.

- [ ] **Step 3: Commit**

```bash
git add tests/mocks/curl
git commit -m "test: add URL-pattern dispatch to curl mock for multi-source scripts

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 2: Create `docs/anthropic-new-features/` directory with README

**Files:**

- Create: `docs/anthropic-new-features/README.md`

- [ ] **Step 1: Create the README**

```bash
mkdir -p docs/anthropic-new-features
```

Write `docs/anthropic-new-features/README.md`:

````markdown
# Anthropic & Claude API — New Features Digest

Weekly summaries of Anthropic platform and Python SDK changes, generated every Monday at 8am Eastern.

## Files

- `features-YYYY-MM-DD.md` — weekly digest committed each Monday
- `.platform-state.txt` — last-fetched platform release notes (HTML-stripped; do not edit manually)
- `.sdk-state.md` — last-fetched Python SDK CHANGELOG snapshot (do not edit manually)

## Generating a digest

```bash
# Run manually (commits and pushes if changes found):
scripts/whats-new-anthropic.sh

# Preview without writing or committing:
scripts/whats-new-anthropic.sh --dry-run

# On-demand in Claude Code (fetches live):
/whats-new-anthropic
```
````

Set `NTFY_URL` in your environment to also push the digest to your ntfy instance.

## Sources

- [Anthropic Platform release notes](https://platform.claude.com/docs/en/release-notes/api)
- [Python SDK CHANGELOG](https://github.com/anthropics/anthropic-sdk-python/blob/main/CHANGELOG.md)

## Automated schedule

A remote Claude Code routine runs every Monday at 8am Eastern and commits the digest automatically. Manage it at https://claude.ai/code/routines

````

- [ ] **Step 2: Commit**

```bash
git add docs/anthropic-new-features/README.md
git commit -m "docs: add anthropic-new-features directory and README

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
````

---

## Task 3: TDD — `strip_html()`, `fetch_platform_notes()`, `fetch_sdk_changelog()`

**Files:**

- Create: `scripts/whats-new-anthropic.sh` (skeleton + these three functions)
- Create: `tests/scripts/whats-new-anthropic.bats` (initial tests)

- [ ] **Step 1: Create the test file with failing tests for fetch functions**

Write `tests/scripts/whats-new-anthropic.bats`:

```bash
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
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
cd /path/to/dotfiles
bats tests/scripts/whats-new-anthropic.bats
```

Expected: `FAILED` — script doesn't exist yet.

- [ ] **Step 3: Create the script skeleton with fetch functions**

Write `scripts/whats-new-anthropic.sh`:

```bash
#!/usr/bin/env bash

PLATFORM_URL="https://platform.claude.com/docs/en/release-notes/api"
SDK_URL="https://raw.githubusercontent.com/anthropics/anthropic-sdk-python/main/CHANGELOG.md"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="${_OVERRIDE_DOTFILES_ROOT:-${SCRIPT_DIR}/..}"
FEATURES_DIR="${_OVERRIDE_FEATURES_DIR:-${DOTFILES_ROOT}/docs/anthropic-new-features}"
PLATFORM_STATE_FILE="${FEATURES_DIR}/.platform-state.txt"
SDK_STATE_FILE="${FEATURES_DIR}/.sdk-state.md"
TODAY="$(date +%Y-%m-%d)"
OUTPUT_FILE="${FEATURES_DIR}/features-${TODAY}.md"

usage() {
  printf "Usage: %s [--dry-run]\n" "$0"
  printf "  --dry-run  Print summary without writing files or committing\n"
}

strip_html() {
  python3 -c "
import sys, re
content = sys.stdin.read()
text = re.sub(r'<[^>]+>', ' ', content)
text = re.sub(r'\s+', ' ', text).strip()
print(text)
"
}

fetch_platform_notes() {
  local _raw
  _raw="$(curl -sL "${PLATFORM_URL}")" || { printf "Error: failed to fetch platform release notes\n" >&2; return 1; }
  printf "%s" "${_raw}" | strip_html
}

fetch_sdk_changelog() {
  curl -sf "${SDK_URL}" || { printf "Error: failed to fetch Python SDK CHANGELOG\n" >&2; return 1; }
}

[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
bats tests/scripts/whats-new-anthropic.bats
```

Expected: all 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/whats-new-anthropic.sh tests/scripts/whats-new-anthropic.bats
git commit -m "feat: add whats-new-anthropic fetch functions with tests

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 4: TDD — `extract_new_content()`

**Files:**

- Modify: `scripts/whats-new-anthropic.sh`
- Modify: `tests/scripts/whats-new-anthropic.bats`

Unlike the existing script's `extract_new_content` (which closes over a single `STATE_FILE` global), this version takes the state file path as a second argument so it works for both sources.

- [ ] **Step 1: Add failing tests**

Append to `tests/scripts/whats-new-anthropic.bats`:

```bash
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
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
bats tests/scripts/whats-new-anthropic.bats
```

Expected: the three new tests fail — `extract_new_content` not defined.

- [ ] **Step 3: Add `extract_new_content()` to the script** (before the sourcing guard)

```bash
extract_new_content() {
  local _current="$1"
  local _state_file="$2"
  if [[ -f "${_state_file}" ]]; then
    diff "${_state_file}" <(printf "%s" "${_current}") | grep '^>' | sed 's/^> //'
  else
    printf "%s" "${_current}"
  fi
}
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
bats tests/scripts/whats-new-anthropic.bats
```

Expected: all 8 tests pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/whats-new-anthropic.sh tests/scripts/whats-new-anthropic.bats
git commit -m "feat: add extract_new_content with state-file param and tests

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 5: TDD — `generate_summary()`

**Files:**

- Modify: `scripts/whats-new-anthropic.sh`
- Modify: `tests/scripts/whats-new-anthropic.bats`

- [ ] **Step 1: Add failing tests**

Append to `tests/scripts/whats-new-anthropic.bats`:

```bash
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
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
bats tests/scripts/whats-new-anthropic.bats
```

Expected: the three new tests fail — `generate_summary` not defined.

- [ ] **Step 3: Add `generate_summary()` to the script** (before the sourcing guard)

```bash
generate_summary() {
  local _platform_diff="$1"
  local _sdk_diff="$2"
  local _combined
  _combined="$(printf "## Platform Release Notes\n%s\n\n## Python SDK\n%s" "${_platform_diff}" "${_sdk_diff}")"
  printf "%s" "${_combined}" | claude -p \
    "Summarize Anthropic and Claude API updates from this content for a developer.

Structure your response as:

## Model & API Changes
## SDK Changes
## Bug Fixes

Rules:
- One bullet per change, one clear sentence each
- Skip version numbers and dates inside bullets
- Omit any empty sections
- Under 400 words total" || { printf "Error: claude CLI failed to generate summary\n" >&2; return 1; }
}
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
bats tests/scripts/whats-new-anthropic.bats
```

Expected: all 11 tests pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/whats-new-anthropic.sh tests/scripts/whats-new-anthropic.bats
git commit -m "feat: add generate_summary with combined prompt and tests

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 6: TDD — `write_output()`, `commit_and_push()`, `send_ntfy()`

**Files:**

- Modify: `scripts/whats-new-anthropic.sh`
- Modify: `tests/scripts/whats-new-anthropic.bats`

- [ ] **Step 1: Add failing tests**

Append to `tests/scripts/whats-new-anthropic.bats`:

```bash
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
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
bats tests/scripts/whats-new-anthropic.bats
```

Expected: the five new tests fail.

- [ ] **Step 3: Add `write_output()`, `commit_and_push()`, `send_ntfy()` to the script** (before the sourcing guard)

```bash
write_output() {
  local _summary="$1"
  {
    printf "# Anthropic & Claude API — What's New (%s)\n\n" "${TODAY}"
    printf "%s\n" "${_summary}"
    printf "\n---\n"
    printf "_Sources: [Platform release notes](https://platform.claude.com/docs/en/release-notes/api) | [Python SDK CHANGELOG](https://github.com/anthropics/anthropic-sdk-python/blob/main/CHANGELOG.md)_\n"
  } > "${OUTPUT_FILE}" || { printf "Error: failed to write %s\n" "${OUTPUT_FILE}" >&2; return 1; }
}

commit_and_push() {
  cd "${DOTFILES_ROOT}" || return 1
  git add "${OUTPUT_FILE}" "${PLATFORM_STATE_FILE}" "${SDK_STATE_FILE}"
  git commit -m "docs: add Anthropic weekly features digest ${TODAY}

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>" || return 1
  git push || { printf "Warning: git push failed — changes are committed locally\n" >&2; }
}

send_ntfy() {
  [[ -z "${NTFY_URL:-}" ]] && return 0
  curl -sf \
    -d "$(head -c 4000 "${OUTPUT_FILE}")" \
    -H "Title: Anthropic & Claude API — Week of ${TODAY}" \
    -H "Tags: rocket" \
    "${NTFY_URL}" || printf "Warning: ntfy notification failed\n" >&2
}
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
bats tests/scripts/whats-new-anthropic.bats
```

Expected: all 16 tests pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/whats-new-anthropic.sh tests/scripts/whats-new-anthropic.bats
git commit -m "feat: add write_output, commit_and_push, send_ntfy with tests

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 7: TDD — `main()` happy path and boundary cases

**Files:**

- Modify: `scripts/whats-new-anthropic.sh`
- Modify: `tests/scripts/whats-new-anthropic.bats`

- [ ] **Step 1: Add failing tests for main() happy path and boundary cases**

Append to `tests/scripts/whats-new-anthropic.bats`:

```bash
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
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
bats tests/scripts/whats-new-anthropic.bats
```

Expected: the seven new tests fail — `main` not defined.

- [ ] **Step 3: Add `main()` to the script** (replace the bare sourcing guard at the bottom)

```bash
main() {
  local _dry_run="false"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) _dry_run="true"; shift ;;
      -h|--help) usage; return 0 ;;
      *) printf "Unknown option: %s\n" "$1" >&2; usage >&2; return 1 ;;
    esac
  done

  if ! command -v claude &>/dev/null; then
    printf "Error: claude CLI not found — install Claude Code first\n" >&2
    return 1
  fi

  mkdir -p "${FEATURES_DIR}"

  if [[ -f "${OUTPUT_FILE}" ]] && [[ "${_dry_run}" == "false" ]]; then
    printf "Features file for %s already exists. Skipping.\n" "${TODAY}"
    return 0
  fi

  local _rc=0
  local _platform_current _sdk_current _platform_new _sdk_new _summary

  _platform_current="$(fetch_platform_notes)" || return 1
  _sdk_current="$(fetch_sdk_changelog)" || return 1

  _platform_new="$(extract_new_content "${_platform_current}" "${PLATFORM_STATE_FILE}")"
  _sdk_new="$(extract_new_content "${_sdk_current}" "${SDK_STATE_FILE}")"

  if [[ -z "${_platform_new}" ]] && [[ -z "${_sdk_new}" ]]; then
    printf "No new content since last run.\n"
    return 0
  fi

  _summary="$(generate_summary "${_platform_new}" "${_sdk_new}")" || return 1

  if [[ -z "${_summary}" ]]; then
    printf "Error: empty summary generated\n" >&2
    return 1
  fi

  if [[ "${_dry_run}" == "true" ]]; then
    printf "# Anthropic & Claude API — What's New (%s)\n\n%s\n" "${TODAY}" "${_summary}"
    return 0
  fi

  write_output "${_summary}" || return 1
  printf "%s" "${_platform_current}" > "${PLATFORM_STATE_FILE}"
  printf "%s" "${_sdk_current}" > "${SDK_STATE_FILE}"
  commit_and_push || _rc=$?
  send_ntfy

  printf "Done: %s\n" "${OUTPUT_FILE}"
  return "${_rc}"
}

[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0
main "$@"
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
bats tests/scripts/whats-new-anthropic.bats
```

Expected: all 23 tests pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/whats-new-anthropic.sh tests/scripts/whats-new-anthropic.bats
git commit -m "feat: add main() orchestration with tests

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 8: TDD — `main()` error path tests

**Files:**

- Modify: `tests/scripts/whats-new-anthropic.bats`

No new implementation needed — all error handling is already in the functions above. These tests verify the wiring.

- [ ] **Step 1: Add failing error-path tests**

Append to `tests/scripts/whats-new-anthropic.bats`:

```bash
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
```

- [ ] **Step 2: Run tests to confirm they pass without any new implementation**

```bash
bats tests/scripts/whats-new-anthropic.bats
```

Expected: all 27 tests pass. If any fail, the error propagation in `main()` is incorrect — trace the return code chain.

- [ ] **Step 3: Run full test suite to confirm no regressions**

```bash
make test
```

Expected: exits 0.

- [ ] **Step 4: Commit**

```bash
git add tests/scripts/whats-new-anthropic.bats
git commit -m "test: add error-path tests for whats-new-anthropic main()

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 9: Update `CLAUDE.md`

**Files:**

- Modify: `CLAUDE.md`

Three additions:

**A. Layout table** — add `anthropic-new-features/` entry after `claude-code-new-features/`:

Find this block in the Layout section:

```
│   ├── claude-code-new-features/  # Weekly Claude Code feature digests
│   │   ├── README.md         # Usage and schedule docs
│   │   ├── .changelog-state.md   # Last-fetched CHANGELOG snapshot (do not edit)
│   │   └── features-YYYY-MM-DD.md  # Weekly digest committed each Monday
```

Add after it:

```
│   ├── anthropic-new-features/  # Weekly Anthropic & Claude API feature digests
│   │   ├── README.md                # Usage and schedule docs
│   │   ├── .platform-state.txt      # Last-fetched platform notes (HTML-stripped; do not edit)
│   │   ├── .sdk-state.md            # Last-fetched Python SDK CHANGELOG (do not edit)
│   │   └── features-YYYY-MM-DD.md   # Weekly digest committed each Monday
```

**B. Scripts section** — add the new script alongside the existing one:

Find:

```
│   ├── whats-new-claude-code.sh  # Weekly Claude Code features digest (fetch, summarize, commit)
```

Add after it:

```
│   ├── whats-new-anthropic.sh    # Weekly Anthropic & Claude API digest (fetch, summarize, commit)
```

**C. Test Seams table** — update the existing `_OVERRIDE_FEATURES_DIR` and `_OVERRIDE_DOTFILES_ROOT` rows to mention both scripts, then add the two new mock vars.

Find:

```
| `_OVERRIDE_FEATURES_DIR`     | `scripts/whats-new-claude-code.sh` | Redirects output and state files to a temp dir; defaults to `docs/claude-code-new-features/` |
| `_OVERRIDE_DOTFILES_ROOT`    | `scripts/whats-new-claude-code.sh` | Redirects the repo root used for `cd` before git operations; defaults to `SCRIPT_DIR/..`     |
```

Replace with:

```
| `_OVERRIDE_FEATURES_DIR`     | `scripts/whats-new-claude-code.sh`, `scripts/whats-new-anthropic.sh` | Redirects output and state files to a temp dir |
| `_OVERRIDE_DOTFILES_ROOT`    | `scripts/whats-new-claude-code.sh`, `scripts/whats-new-anthropic.sh` | Redirects the repo root used for `cd` before git operations |
```

**D. Mock vars table** — add the two new vars after `MOCK_CURL_STDOUT`. Find:

```
| `MOCK_CURL_STDOUT` | Content printed to stdout by `curl` mock (used for `$(curl ...)` substitution; default: empty) |
```

Add after it:

```
| `MOCK_CURL_PLATFORM_STDOUT` | Content returned by `curl` mock when URL contains `platform.claude.com`; used by `whats-new-anthropic.sh` (default: falls back to `MOCK_CURL_STDOUT`) |
| `MOCK_CURL_SDK_STDOUT` | Content returned by `curl` mock when URL contains `githubusercontent.com`; used by `whats-new-anthropic.sh` (default: falls back to `MOCK_CURL_STDOUT`) |
```

- [ ] **Step 1: Make all four edits to `CLAUDE.md`** (use the Edit tool four times, one per section)

- [ ] **Step 2: Run `make test` to confirm nothing broke**

```bash
make test
```

Expected: exits 0.

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md for whats-new-anthropic script

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 10: Add `/whats-new-anthropic` slash command

**Files:**

- Create: `.claude/commands/whats-new-anthropic.md`

- [ ] **Step 1: Create the slash command file**

Write `.claude/commands/whats-new-anthropic.md`:

````markdown
# /whats-new-anthropic

Fetch and display the latest Anthropic platform and Python SDK changes live.

## Instructions for Claude

1. Use Bash to fetch the current platform release notes:

   ```bash
   curl -sL https://platform.claude.com/docs/en/release-notes/api | python3 -c "
   import sys, re
   content = sys.stdin.read()
   text = re.sub(r'<[^>]+>', ' ', content)
   text = re.sub(r'\s+', ' ', text).strip()
   print(text[:8000])
   "
   ```
````

2. Use Bash to fetch the Python SDK CHANGELOG:

   ```bash
   curl -sf https://raw.githubusercontent.com/anthropics/anthropic-sdk-python/main/CHANGELOG.md | head -200
   ```

3. Extract changes from the last 30 days based on dates in both sources.

4. Present a combined digest structured as:
   - **Model & API Changes** — new models, deprecations, beta announcements
   - **SDK Changes** — new API methods, breaking changes, client improvements
   - **Bug Fixes** — issues resolved

5. One bullet per change, one clear sentence. Skip internal tooling items.

6. Close with links to both sources:
   `[Platform release notes](https://platform.claude.com/docs/en/release-notes/api) | [Python SDK CHANGELOG](https://github.com/anthropics/anthropic-sdk-python/blob/main/CHANGELOG.md)`

## Optional flags

- `--since <date>` — show changes since a specific date (e.g. `--since 2026-01-01`)

````

- [ ] **Step 2: Commit**

```bash
git add .claude/commands/whats-new-anthropic.md
git commit -m "feat: add /whats-new-anthropic slash command

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
````

---

## Task 11: Register Monday routine and update superpowers README

**Files:**

- Modify: `docs/superpowers/README.md`

The remote routine must be registered manually at https://claude.ai/code/routines — it cannot be scripted.

- [ ] **Step 1: Register the routine at claude.ai/code/routines**

Create a new routine:

- **Name**: `whats-new-anthropic`
- **Schedule**: Every Monday at 8am Eastern (`0 8 * * 1` in America/New_York)
- **Command**: `scripts/whats-new-anthropic.sh`
- **Repository**: `dotfiles`

- [ ] **Step 2: Update `docs/superpowers/README.md`** — add the plan row

Find the 2026-05-08 spec-only row:

```
| 2026-05-08 | —                                                                                  | [spec](specs/2026-05-08-whats-new-anthropic-design.md)              | Pending |
```

Replace with:

```
| 2026-05-08 | [whats-new-anthropic](plans/2026-05-08-whats-new-anthropic.md)                     | [spec](specs/2026-05-08-whats-new-anthropic-design.md)              | Done    |
```

- [ ] **Step 3: Run full test suite one final time**

```bash
make test
```

Expected: exits 0.

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/README.md
git commit -m "docs: mark whats-new-anthropic plan done in superpowers README

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```
