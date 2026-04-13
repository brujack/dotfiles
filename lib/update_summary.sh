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

# _update_skip SECTION REASON
# Records a section as skipped with the given reason.
_update_skip() {
  local _section="$1" _reason="$2"
  printf "SKIP\n" > "${_UPDATE_TMPDIR}/status_${_section}"
  printf "%s\n" "${_reason}" > "${_UPDATE_TMPDIR}/result_${_section}"
}

# _update_record_start SECTION
# Takes pre-snapshot appropriate for the section type.
_update_record_start() {
  local _section="$1"
  case "${_section}" in
    brew)
      brew list --formula --versions > "${_UPDATE_TMPDIR}/pre_brew_formula" 2>/dev/null || true
      brew list --cask --versions > "${_UPDATE_TMPDIR}/pre_brew_cask" 2>/dev/null || true
      ;;
    mas)
      mas list > "${_UPDATE_TMPDIR}/pre_mas" 2>/dev/null || true
      ;;
    gems)
      gem list > "${_UPDATE_TMPDIR}/pre_gems" 2>/dev/null || true
      ;;
    pip)
      # pip snapshot is captured inside the Python block; nothing to do here
      ;;
    oh-my-zsh)
      git -C "${HOME}/.oh-my-zsh" rev-parse HEAD > "${_UPDATE_TMPDIR}/pre_oh-my-zsh" 2>/dev/null || true
      ;;
    p10k)
      git -C "${HOME}/.oh-my-zsh/custom/themes/powerlevel10k" rev-parse HEAD > "${_UPDATE_TMPDIR}/pre_p10k" 2>/dev/null || true
      ;;
    tpm)
      git -C "${HOME}/.tmux/plugins/tpm" rev-parse HEAD > "${_UPDATE_TMPDIR}/pre_tpm" 2>/dev/null || true
      ;;
    tfenv)
      git -C "${HOME}/.tfenv" rev-parse HEAD > "${_UPDATE_TMPDIR}/pre_tfenv" 2>/dev/null || true
      ;;
    zsh-autosuggestions)
      git -C "${HOME}/.oh-my-zsh/custom/plugins/zsh-autosuggestions" rev-parse HEAD > "${_UPDATE_TMPDIR}/pre_zsh-autosuggestions" 2>/dev/null || true
      ;;
    softwareupdate)
      softwareupdate -l 2>/dev/null \
        | grep '^\* Label:' \
        | sed 's/^\* Label: //' \
        > "${_UPDATE_TMPDIR}/pre_softwareupdate" || true
      ;;
    claude)
      claude plugins list 2>/dev/null \
        | grep 'Version:' \
        | sed 's/^[[:space:]]*//' \
        > "${_UPDATE_TMPDIR}/pre_claude" || true
      ;;
    # cheat.sh — no pre-snapshot needed
    *) ;;
  esac
}

# _update_record_end SECTION EXIT_CODE
# Takes post-snapshot, diffs against pre, stores result and status.
_update_record_end() {
  local _section="$1" _exit="$2"
  local _result=""

  if [[ "${_exit}" -ne 0 ]]; then
    printf "FAIL\n" > "${_UPDATE_TMPDIR}/status_${_section}"
    printf "exit %d — see output above\n" "${_exit}" > "${_UPDATE_TMPDIR}/result_${_section}"
    return
  fi

  case "${_section}" in
    brew)
      local _formula_diff="" _cask_diff="" _formula_count=0 _cask_count=0
      brew list --formula --versions > "${_UPDATE_TMPDIR}/post_brew_formula" 2>/dev/null || true
      brew list --cask --versions > "${_UPDATE_TMPDIR}/post_brew_cask" 2>/dev/null || true
      if [[ -f "${_UPDATE_TMPDIR}/pre_brew_formula" ]]; then
        _formula_diff=$(_update_diff_lines "${_UPDATE_TMPDIR}/pre_brew_formula" "${_UPDATE_TMPDIR}/post_brew_formula")
        _formula_count=$(printf '%s' "${_formula_diff}" | grep -c . || true)
      fi
      if [[ -f "${_UPDATE_TMPDIR}/pre_brew_cask" ]]; then
        _cask_diff=$(_update_diff_lines "${_UPDATE_TMPDIR}/pre_brew_cask" "${_UPDATE_TMPDIR}/post_brew_cask")
        _cask_count=$(printf '%s' "${_cask_diff}" | grep -c . || true)
      fi
      if [[ ${_formula_count} -gt 0 ]] || [[ ${_cask_count} -gt 0 ]]; then
        if [[ ${_formula_count} -gt 0 ]]; then
          _result="${_formula_count} formulae ($(printf '%s' "${_formula_diff}" | paste -sd', ' -))"
        fi
        if [[ ${_cask_count} -gt 0 ]]; then
          [[ -n "${_result}" ]] && _result="${_result}\n"
          _result="${_result}${_cask_count} cask(s) ($(printf '%s' "${_cask_diff}" | paste -sd', ' -))"
        fi
      else
        _result="no changes"
      fi
      ;;
    mas)
      if [[ -f "${_UPDATE_TMPDIR}/pre_mas" ]]; then
        mas list > "${_UPDATE_TMPDIR}/post_mas" 2>/dev/null || true
        local _mas_diff
        _mas_diff=$(_update_diff_lines "${_UPDATE_TMPDIR}/pre_mas" "${_UPDATE_TMPDIR}/post_mas")
        local _mas_count
        _mas_count=$(printf '%s' "${_mas_diff}" | grep -c . || true)
        if [[ ${_mas_count} -gt 0 ]]; then
          local _mas_names
          _mas_names=$(printf '%s' "${_mas_diff}" | awk '{$1=""; sub(/^ /, ""); sub(/ \([^)]*\)$/, ""); print}' | paste -sd', ' -)
          _result="${_mas_count} app(s) (${_mas_names})"
        else
          _result="no changes"
        fi
      else
        _result="updated"
      fi
      ;;
    gems)
      if [[ -f "${_UPDATE_TMPDIR}/pre_gems" ]]; then
        gem list > "${_UPDATE_TMPDIR}/post_gems" 2>/dev/null || true
        local _gem_diff
        _gem_diff=$(_update_diff_lines "${_UPDATE_TMPDIR}/pre_gems" "${_UPDATE_TMPDIR}/post_gems")
        local _gem_count
        _gem_count=$(printf '%s' "${_gem_diff}" | grep -c . || true)
        if [[ ${_gem_count} -gt 0 ]]; then
          _result="${_gem_count} gem(s) ($(printf '%s' "${_gem_diff}" | paste -sd', ' -))"
        else
          _result="no changes"
        fi
      else
        _result="updated"
      fi
      ;;
    pip)
      if [[ -f "${_UPDATE_TMPDIR}/pip_outdated" ]]; then
        local _pip_count
        _pip_count=$(wc -l < "${_UPDATE_TMPDIR}/pip_outdated" | tr -d ' ')
        if [[ ${_pip_count} -gt 0 ]]; then
          _result="${_pip_count} package(s) ($(paste -sd', ' - < "${_UPDATE_TMPDIR}/pip_outdated"))"
        else
          _result="no changes"
        fi
      else
        _result="updated"
      fi
      ;;
    oh-my-zsh|p10k|tpm|tfenv|zsh-autosuggestions)
      if [[ -f "${_UPDATE_TMPDIR}/pre_${_section}" ]]; then
        local _old_sha _git_dir
        _old_sha=$(cat "${_UPDATE_TMPDIR}/pre_${_section}")
        case "${_section}" in
          oh-my-zsh) _git_dir="${HOME}/.oh-my-zsh" ;;
          p10k) _git_dir="${HOME}/.oh-my-zsh/custom/themes/powerlevel10k" ;;
          tpm) _git_dir="${HOME}/.tmux/plugins/tpm" ;;
          tfenv) _git_dir="${HOME}/.tfenv" ;;
          zsh-autosuggestions) _git_dir="${HOME}/.oh-my-zsh/custom/plugins/zsh-autosuggestions" ;;
        esac
        local _commits
        _commits=$(_update_git_diff "${_git_dir}" "${_old_sha}")
        local _commit_count
        _commit_count=$(printf '%s' "${_commits}" | grep -c . || true)
        if [[ ${_commit_count} -gt 0 ]]; then
          _result="${_commit_count} commit(s)"
        else
          _result="no changes"
        fi
      else
        _result="no changes"
      fi
      ;;
    softwareupdate)
      if [[ -f "${_UPDATE_TMPDIR}/pre_softwareupdate" ]]; then
        local _su_count
        _su_count=$(wc -l < "${_UPDATE_TMPDIR}/pre_softwareupdate" | tr -d ' ')
        if [[ ${_su_count} -gt 0 ]]; then
          _result="${_su_count} update(s) ($(paste -sd', ' - < "${_UPDATE_TMPDIR}/pre_softwareupdate"))"
        else
          _result="no changes"
        fi
      else
        _result="updated"
      fi
      ;;
    claude)
      if [[ -f "${_UPDATE_TMPDIR}/pre_claude" ]]; then
        claude plugins list 2>/dev/null \
          | grep 'Version:' \
          | sed 's/^[[:space:]]*//' \
          > "${_UPDATE_TMPDIR}/post_claude" || true
        local _claude_diff
        _claude_diff=$(_update_diff_lines "${_UPDATE_TMPDIR}/pre_claude" "${_UPDATE_TMPDIR}/post_claude")
        local _claude_count
        _claude_count=$(printf '%s' "${_claude_diff}" | grep -c . || true)
        if [[ ${_claude_count} -gt 0 ]]; then
          _result="${_claude_count} plugin(s) updated"
        else
          _result="no changes"
        fi
      else
        _result="updated"
      fi
      ;;
    *)
      _result="updated"
      ;;
  esac

  printf "OK\n" > "${_UPDATE_TMPDIR}/status_${_section}"
  printf "%s\n" "${_result}" > "${_UPDATE_TMPDIR}/result_${_section}"
}

# _update_summary
# Reads status/result files, prints formatted table, appends to log file.
_update_summary() {
  local _ok=0 _fail=0 _skip=0
  local _output=""
  local _timestamp
  _timestamp=$(date '+%Y-%m-%d %H:%M:%S')

  _output+="=== Update Summary — ${_timestamp} ===\n\n"

  local _section _status _result
  for _section in "${_UPDATE_SECTION_ORDER[@]}"; do
    if [[ ! -f "${_UPDATE_TMPDIR}/status_${_section}" ]]; then
      continue
    fi
    _status=$(cat "${_UPDATE_TMPDIR}/status_${_section}")
    _result=$(cat "${_UPDATE_TMPDIR}/result_${_section}")

    case "${_status}" in
      OK)
        _ok=$(( _ok + 1 ))
        _output+="$(printf "[OK]   %-16s %s" "${_section}" "${_result}")\n"
        ;;
      FAIL)
        _fail=$(( _fail + 1 ))
        _output+="$(printf "[FAIL] %-16s %s" "${_section}" "${_result}")\n"
        ;;
      SKIP)
        _skip=$(( _skip + 1 ))
        _output+="$(printf "[SKIP] %-16s %s" "${_section}" "${_result}")\n"
        ;;
    esac
  done

  local _total=$(( _ok + _fail + _skip ))
  _output+="\n$(printf "%d sections: %d OK, %d failed, %d skipped" "${_total}" "${_ok}" "${_fail}" "${_skip}")\n"

  # Print to terminal
  printf '%b' "${_output}"

  # Append to log file
  local _log="${UPDATE_LOG_PATH:-${HOME}/.dotfiles-update.log}"
  {
    printf "────────────────────────────────────────────────────────\n"
    printf '%b' "${_output}"
  } >> "${_log}" 2>/dev/null || log_warn "Could not write to ${_log}"

  printf "Log appended: %s\n" "${_log}"
}
