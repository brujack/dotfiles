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

extract_new_content() {
  local _current="$1"
  local _state_file="$2"
  if [[ -f "${_state_file}" ]]; then
    diff "${_state_file}" <(printf "%s" "${_current}") | grep '^>' | sed 's/^> //'
  else
    printf "%s" "${_current}"
  fi
}

generate_summary() {
  local _platform_diff="$1"
  local _sdk_diff="$2"
  local _combined
  _combined="$(printf "## Platform Release Notes\n%s\n\n## Python SDK\n%s" "${_platform_diff}" "${_sdk_diff}")"
  # Cap at 40000 chars to stay within claude -p prompt limits (first-run changelogs can be huge)
  _combined="${_combined:0:40000}"
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
  # Store only the most recent 20KB of each source; changelogs are reverse-chronological
  # so head -c captures the newest entries and keeps state files small enough to push.
  printf "%s" "${_platform_current}" | head -c 20000 > "${PLATFORM_STATE_FILE}"
  printf "%s" "${_sdk_current}" | head -c 20000 > "${SDK_STATE_FILE}"
  commit_and_push || _rc=$?
  send_ntfy

  printf "Done: %s\n" "${OUTPUT_FILE}"
  return "${_rc}"
}

[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0
main "$@"
