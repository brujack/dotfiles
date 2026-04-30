#!/usr/bin/env bash
# lib/update_summary.sh — update run tracking and summary reporting

# Fixed section order for summary display
readonly _UPDATE_SECTION_ORDER=(
  brew softwareupdate apt snap dnf yum mas claude pip gems
  oh-my-zsh p10k tpm tfenv cheat.sh brew-drift
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

# _update_ok SECTION MESSAGE
# Records a section as passing. Use for advisory check sections (like brew-drift)
# that bypass _update_record_start/_update_record_end. Do NOT call this on sections
# that use _update_record_end — it would silently overwrite the timed result.
_update_ok() {
  local _section="$1" _msg="$2"
  printf "OK\n" > "${_UPDATE_TMPDIR}/status_${_section}"
  printf "%s\n" "${_msg}" > "${_UPDATE_TMPDIR}/result_${_section}"
}

# _update_warn SECTION MESSAGE
# Records a section as a non-blocking warning. Same lifecycle constraint as
# _update_ok: for advisory check sections only, not timed _update_record_end sections.
_update_warn() {
  local _section="$1" _msg="$2"
  printf "WARN\n" > "${_UPDATE_TMPDIR}/status_${_section}"
  printf "%s\n" "${_msg}" > "${_UPDATE_TMPDIR}/result_${_section}"
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
    apt)
      if [[ -n ${UBUNTU:-} ]]; then
        dpkg-query -W -f='${Package} ${Version}\n' > "${_UPDATE_TMPDIR}/pre_apt" 2>/dev/null || true
      else
        _update_skip "apt" "not applicable"
      fi
      ;;
    snap)
      if [[ -n ${UBUNTU:-} ]]; then
        snap list --color=never 2>/dev/null \
          | awk 'NR>1 {print $1, $2}' \
          > "${_UPDATE_TMPDIR}/pre_snap" || true
      else
        _update_skip "snap" "not applicable"
      fi
      ;;
    dnf)
      if [[ -n ${REDHAT:-} ]] || [[ -n ${FEDORA:-} ]]; then
        rpm -qa --qf '%{NAME} %{VERSION}-%{RELEASE}\n' > "${_UPDATE_TMPDIR}/pre_dnf" 2>/dev/null || true
      else
        _update_skip "dnf" "not applicable"
      fi
      ;;
    yum)
      if [[ -n ${CENTOS:-} ]]; then
        rpm -qa --qf '%{NAME} %{VERSION}-%{RELEASE}\n' > "${_UPDATE_TMPDIR}/pre_yum" 2>/dev/null || true
      else
        _update_skip "yum" "not applicable"
      fi
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

  # If _update_record_start already wrote a SKIP (e.g. wrong distro), leave it untouched
  if [[ -f "${_UPDATE_TMPDIR}/status_${_section}" ]]; then
    local _existing_status
    _existing_status=$(cat "${_UPDATE_TMPDIR}/status_${_section}")
    if [[ "${_existing_status}" == "SKIP" ]]; then
      return 0
    fi
  fi

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
      if [[ -f "${_UPDATE_TMPDIR}/mas_upgrade_output" ]]; then
        local _mas_updated
        _mas_updated=$(grep '^==> Updated ' "${_UPDATE_TMPDIR}/mas_upgrade_output" || true)
        local _mas_count
        _mas_count=$(printf '%s' "${_mas_updated}" | grep -c . || true)
        if [[ ${_mas_count} -gt 0 ]]; then
          local _mas_names
          _mas_names=$(printf '%s' "${_mas_updated}" | sed 's/^==> Updated //' | paste -sd', ' -)
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
        _pip_count=$(grep -c . "${_UPDATE_TMPDIR}/pip_outdated" || true)
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
    apt)
      dpkg-query -W -f='${Package} ${Version}\n' > "${_UPDATE_TMPDIR}/post_apt" 2>/dev/null || true
      if [[ -f "${_UPDATE_TMPDIR}/pre_apt" ]]; then
        local _apt_diff _apt_count
        _apt_diff=$(_update_diff_lines "${_UPDATE_TMPDIR}/pre_apt" "${_UPDATE_TMPDIR}/post_apt")
        _apt_count=$(printf '%s' "${_apt_diff}" | grep -c . || true)
        if [[ ${_apt_count} -gt 0 ]]; then
          _result="${_apt_count} package(s) ($(printf '%s' "${_apt_diff}" | paste -sd', ' -))"
        else
          _result="no changes"
        fi
      else
        _result="updated"
      fi
      # Check for reboot-required flag written by apt when a kernel or core lib is updated
      local _reboot_flag="${_REBOOT_REQUIRED_PATH:-/var/run/reboot-required}"
      if [[ -f "${_reboot_flag}" ]]; then
        local _reboot_pkgs_file="${_REBOOT_REQUIRED_PKGS_PATH:-/var/run/reboot-required.pkgs}"
        if [[ -f "${_reboot_pkgs_file}" ]]; then
          local _reboot_pkgs
          _reboot_pkgs=$(sort -u "${_reboot_pkgs_file}" | paste -sd', ' -)
          _result="${_result} — reboot required (${_reboot_pkgs})"
        else
          _result="${_result} — reboot required"
        fi
      fi
      ;;
    snap)
      snap list --color=never 2>/dev/null \
        | awk 'NR>1 {print $1, $2}' \
        > "${_UPDATE_TMPDIR}/post_snap" || true
      if [[ -f "${_UPDATE_TMPDIR}/pre_snap" ]]; then
        local _snap_diff _snap_count
        _snap_diff=$(_update_diff_lines "${_UPDATE_TMPDIR}/pre_snap" "${_UPDATE_TMPDIR}/post_snap")
        _snap_count=$(printf '%s' "${_snap_diff}" | grep -c . || true)
        if [[ ${_snap_count} -gt 0 ]]; then
          _result="${_snap_count} package(s) ($(printf '%s' "${_snap_diff}" | paste -sd', ' -))"
        else
          _result="no changes"
        fi
      else
        _result="updated"
      fi
      ;;
    dnf|yum)
      rpm -qa --qf '%{NAME} %{VERSION}-%{RELEASE}\n' > "${_UPDATE_TMPDIR}/post_${_section}" 2>/dev/null || true
      if [[ -f "${_UPDATE_TMPDIR}/pre_${_section}" ]]; then
        local _rpm_diff _rpm_count
        _rpm_diff=$(_update_diff_lines "${_UPDATE_TMPDIR}/pre_${_section}" "${_UPDATE_TMPDIR}/post_${_section}")
        _rpm_count=$(printf '%s' "${_rpm_diff}" | grep -c . || true)
        if [[ ${_rpm_count} -gt 0 ]]; then
          _result="${_rpm_count} package(s) ($(printf '%s' "${_rpm_diff}" | paste -sd', ' -))"
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
  local _ok=0 _fail=0 _skip=0 _warn=0
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
      WARN)
        _warn=$(( _warn + 1 ))
        _output+="$(printf "[WARN] %-16s %s" "${_section}" "${_result}")\n"
        ;;
    esac
  done

  local _total=$(( _ok + _fail + _skip + _warn ))
  _output+="\n$(printf "%d sections: %d OK, %d failed, %d warnings, %d skipped" "${_total}" "${_ok}" "${_fail}" "${_warn}" "${_skip}")\n"

  # Build detail output (in section order for deterministic output)
  local _detail_output=""
  for _section in "${_UPDATE_SECTION_ORDER[@]}"; do
    if [[ -f "${_UPDATE_TMPDIR}/detail_${_section}" ]]; then
      _detail_output+="\n$(cat "${_UPDATE_TMPDIR}/detail_${_section}")\n"
    fi
  done

  # Print to terminal
  printf '%b' "${_output}"
  [[ -n "${_detail_output}" ]] && printf '%b' "${_detail_output}"

  # Append to log file
  local _log="${UPDATE_LOG_PATH:-${HOME}/.dotfiles-update.log}"
  {
    printf "────────────────────────────────────────────────────────\n"
    printf '%b' "${_output}"
    [[ -n "${_detail_output}" ]] && printf '%b' "${_detail_output}"
    :
  } >> "${_log}" 2>/dev/null || log_warn "Could not write to ${_log}"

  printf "Log appended: %s\n" "${_log}"
}

# _update_check_brewfile_drift
# Compares Brewfile (formulae, casks on macOS, taps) against locally installed
# Homebrew packages. Records OK/WARN/SKIP into the update summary.
# Uses _OVERRIDE_BREWFILE_PATH seam for testing.
_update_check_brewfile_drift() {
  if [[ -z ${MACOS:-} ]]; then
    _update_skip "brew-drift" "not applicable on Linux"
    return 0
  fi

  local _brewfile="${_OVERRIDE_BREWFILE_PATH:-${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile}"

  if ! quiet_which brew; then
    _update_skip "brew-drift" "brew not available"
    return 0
  fi

  if [[ ! -f "${_brewfile}" ]]; then
    _update_skip "brew-drift" "Brewfile not found at ${_brewfile}"
    return 0
  fi

  # Parse Brewfile into sorted temp files
  grep '^brew "' "${_brewfile}" | sed 's/^brew "//;s/".*//' | sort \
    > "${_UPDATE_TMPDIR}/drift_bf_formulae"
  grep '^tap "' "${_brewfile}" | sed 's/^tap "//;s/".*//' | sort \
    > "${_UPDATE_TMPDIR}/drift_bf_taps"

  # Get actual installed state — two sets:
  # leaves: top-level installs only (for untracked detection, filters transitive deps)
  # all: every installed formula (for missing detection, avoids false positives)
  brew leaves 2>/dev/null | sort > "${_UPDATE_TMPDIR}/drift_inst_formulae_leaves"
  brew list --formula --full-name 2>/dev/null | sort > "${_UPDATE_TMPDIR}/drift_inst_formulae_all"
  brew tap 2>/dev/null \
    | grep -v -E '^homebrew/(bundle|cask|core|services)$' \
    | sort > "${_UPDATE_TMPDIR}/drift_inst_taps"

  # Compute formula and tap drift
  # comm -13: lines only in file2 = installed but not in Brewfile (untracked)
  # comm -23: lines only in file1 = in Brewfile but not installed (missing)
  local _untracked_formulae _missing_formulae _untracked_taps _missing_taps
  _untracked_formulae=$(comm -13 "${_UPDATE_TMPDIR}/drift_bf_formulae" \
    "${_UPDATE_TMPDIR}/drift_inst_formulae_leaves")
  _missing_formulae=$(comm -23 "${_UPDATE_TMPDIR}/drift_bf_formulae" \
    "${_UPDATE_TMPDIR}/drift_inst_formulae_all")
  _untracked_taps=$(comm -13 "${_UPDATE_TMPDIR}/drift_bf_taps" \
    "${_UPDATE_TMPDIR}/drift_inst_taps")
  _missing_taps=$(comm -23 "${_UPDATE_TMPDIR}/drift_bf_taps" \
    "${_UPDATE_TMPDIR}/drift_inst_taps")

  # Cask drift: macOS only (Linux Homebrew does not support casks)
  local _untracked_casks="" _missing_casks=""
  if [[ -n ${MACOS:-} ]]; then
    grep '^cask "' "${_brewfile}" | sed 's/^cask "//;s/".*//' | sort \
      > "${_UPDATE_TMPDIR}/drift_bf_casks"
    brew list --cask 2>/dev/null | sort > "${_UPDATE_TMPDIR}/drift_inst_casks"
    _untracked_casks=$(comm -13 "${_UPDATE_TMPDIR}/drift_bf_casks" \
      "${_UPDATE_TMPDIR}/drift_inst_casks")
    _missing_casks=$(comm -23 "${_UPDATE_TMPDIR}/drift_bf_casks" \
      "${_UPDATE_TMPDIR}/drift_inst_casks")
  fi

  # Check for any drift
  local _has_drift=0
  [[ -n "${_untracked_formulae}" ]] && _has_drift=1
  [[ -n "${_missing_formulae}" ]]   && _has_drift=1
  [[ -n "${_untracked_taps}" ]]     && _has_drift=1
  [[ -n "${_missing_taps}" ]]       && _has_drift=1
  [[ -n "${_untracked_casks}" ]]    && _has_drift=1
  [[ -n "${_missing_casks}" ]]      && _has_drift=1

  if [[ "${_has_drift}" -eq 0 ]]; then
    local _clean_msg="formulae clean"
    [[ -n ${MACOS:-} ]] && _clean_msg="${_clean_msg}, casks clean"
    _clean_msg="${_clean_msg}, taps clean"
    _update_ok "brew-drift" "${_clean_msg}"
    return 0
  fi

  # Build summary string from non-zero drift counts
  local _untracked_f_count _missing_f_count _untracked_t_count _missing_t_count
  _untracked_f_count=$(printf '%s\n' "${_untracked_formulae}" | grep -c . || true)
  _missing_f_count=$(printf '%s\n' "${_missing_formulae}" | grep -c . || true)
  _untracked_t_count=$(printf '%s\n' "${_untracked_taps}" | grep -c . || true)
  _missing_t_count=$(printf '%s\n' "${_missing_taps}" | grep -c . || true)

  local _summary=""
  [[ "${_untracked_f_count}" -gt 0 ]] && _summary+="${_untracked_f_count} untracked formulae, "
  [[ "${_missing_f_count}" -gt 0 ]]   && _summary+="${_missing_f_count} missing formulae, "
  if [[ -n ${MACOS:-} ]]; then
    local _untracked_c_count _missing_c_count
    _untracked_c_count=$(printf '%s\n' "${_untracked_casks}" | grep -c . || true)
    _missing_c_count=$(printf '%s\n' "${_missing_casks}" | grep -c . || true)
    [[ "${_untracked_c_count}" -gt 0 ]] && _summary+="${_untracked_c_count} untracked casks, "
    [[ "${_missing_c_count}" -gt 0 ]]   && _summary+="${_missing_c_count} missing casks, "
  fi
  [[ "${_untracked_t_count}" -gt 0 ]] && _summary+="${_untracked_t_count} untracked taps, "
  [[ "${_missing_t_count}" -gt 0 ]]   && _summary+="${_missing_t_count} missing taps, "
  _summary="${_summary%, }"

  _update_warn "brew-drift" "${_summary}"

  # Write detail file
  local _detail="brew-drift details:\n"
  if [[ -n "${_untracked_formulae}" ]] || [[ -n "${_untracked_casks}" ]] || [[ -n "${_untracked_taps}" ]]; then
    _detail+="  Untracked (installed, not in Brewfile):\n"
    while IFS= read -r _pkg; do
      [[ -z "${_pkg}" ]] && continue
      _detail+="    ${_pkg}\n"
    done <<< "${_untracked_formulae}"
    while IFS= read -r _pkg; do
      [[ -z "${_pkg}" ]] && continue
      _detail+="    cask: ${_pkg}\n"
    done <<< "${_untracked_casks}"
    while IFS= read -r _pkg; do
      [[ -z "${_pkg}" ]] && continue
      _detail+="    tap: ${_pkg}\n"
    done <<< "${_untracked_taps}"
  fi
  if [[ -n "${_missing_formulae}" ]] || [[ -n "${_missing_casks}" ]] || [[ -n "${_missing_taps}" ]]; then
    _detail+="  Missing (in Brewfile, not installed):\n"
    while IFS= read -r _pkg; do
      [[ -z "${_pkg}" ]] && continue
      _detail+="    ${_pkg}\n"
    done <<< "${_missing_formulae}"
    while IFS= read -r _pkg; do
      [[ -z "${_pkg}" ]] && continue
      _detail+="    cask: ${_pkg}\n"
    done <<< "${_missing_casks}"
    while IFS= read -r _pkg; do
      [[ -z "${_pkg}" ]] && continue
      _detail+="    tap: ${_pkg}\n"
    done <<< "${_missing_taps}"
  fi

  printf '%b' "${_detail}" > "${_UPDATE_TMPDIR}/detail_brew-drift"
}
