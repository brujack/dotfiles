#!/usr/bin/env bash

CHANGELOG_URL="https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="${_OVERRIDE_DOTFILES_ROOT:-${SCRIPT_DIR}/..}"
FEATURES_DIR="${_OVERRIDE_FEATURES_DIR:-${DOTFILES_ROOT}/docs/claude-code-new-features}"
STATE_FILE="${FEATURES_DIR}/.changelog-state.md"
TODAY="$(date +%Y-%m-%d)"
OUTPUT_FILE="${FEATURES_DIR}/features-${TODAY}.md"

usage() {
  printf "Usage: %s [--dry-run]\n" "$0"
  printf "  --dry-run  Print summary without writing files or committing\n"
}

fetch_changelog() {
  curl -sf "${CHANGELOG_URL}" || { printf "Error: failed to fetch CHANGELOG from GitHub\n" >&2; return 1; }
}

extract_new_content() {
  local _current="$1"
  if [[ -f "${STATE_FILE}" ]]; then
    diff "${STATE_FILE}" <(printf "%s" "${_current}") | grep '^>' | sed 's/^> //'
  else
    printf "%s" "${_current}"
  fi
}

generate_summary() {
  local _content="$1"
  printf "%s" "${_content}" | claude -p \
    "Summarize Claude Code features and changes from this CHANGELOG content for a developer.

Structure your response as:

## New Features
## Improvements
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
    printf "# Claude Code — What's New (%s)\n\n" "${TODAY}"
    printf "%s\n" "${_summary}"
    printf "\n---\n"
    printf "_Source: [anthropics/claude-code CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)_\n"
  } > "${OUTPUT_FILE}" || { printf "Error: failed to write %s\n" "${OUTPUT_FILE}" >&2; return 1; }
}

commit_and_push() {
  cd "${DOTFILES_ROOT}" || return 1
  git add "${OUTPUT_FILE}" "${STATE_FILE}"
  git commit -m "docs: add Claude Code weekly features digest ${TODAY}

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>" || return 1
  git push || { printf "Warning: git push failed — changes are committed locally\n" >&2; }
}

send_ntfy() {
  [[ -z "${NTFY_URL:-}" ]] && return 0
  curl -sf \
    -d "$(head -c 4000 "${OUTPUT_FILE}")" \
    -H "Title: Claude Code — Week of ${TODAY}" \
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
  local _current _new_content _summary

  _current="$(fetch_changelog)" || return 1
  _new_content="$(extract_new_content "${_current}")"

  if [[ -z "${_new_content}" ]]; then
    printf "No new CHANGELOG entries since last run.\n"
    return 0
  fi

  _summary="$(generate_summary "${_new_content}")" || return 1

  if [[ -z "${_summary}" ]]; then
    printf "Error: empty summary generated\n" >&2
    return 1
  fi

  if [[ "${_dry_run}" == "true" ]]; then
    printf "# Claude Code — What's New (%s)\n\n%s\n" "${TODAY}" "${_summary}"
    return 0
  fi

  write_output "${_summary}" || return 1
  printf "%s" "${_current}" > "${STATE_FILE}"
  commit_and_push || _rc=$?
  send_ntfy

  printf "Done: %s\n" "${OUTPUT_FILE}"
  return "${_rc}"
}

[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0
main "$@"
