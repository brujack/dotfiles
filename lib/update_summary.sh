#!/usr/bin/env bash
# lib/update_summary.sh — update run tracking and summary reporting

# Fixed section order for summary display
readonly _UPDATE_SECTION_ORDER=(
  brew softwareupdate mas claude pip gems
  oh-my-zsh p10k tpm tfenv cheat.sh
)

# _update_diff_lines PRE_FILE POST_FILE
# Outputs lines in POST_FILE that differ from PRE_FILE (new or changed).
_update_diff_lines() {
  local _pre="$1" _post="$2"
  comm -13 <(sort "${_pre}") <(sort "${_post}")
}

# _update_snapshot SECTION COMMAND...
# Runs COMMAND and writes stdout to ${_UPDATE_TMPDIR}/pre_SECTION.
_update_snapshot() {
  local _section="$1"
  shift
  "$@" > "${_UPDATE_TMPDIR}/pre_${_section}" 2>/dev/null || true
}

# _update_git_diff DIR OLD_SHA
# Outputs git log from OLD_SHA to HEAD in DIR (one line per commit).
_update_git_diff() {
  local _dir="$1" _old_sha="$2"
  git -C "${_dir}" log "${_old_sha}..HEAD" --oneline 2>/dev/null
}
