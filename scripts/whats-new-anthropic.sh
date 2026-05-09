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
