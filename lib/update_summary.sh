#!/usr/bin/env bash
# lib/update_summary.sh — update run tracking and summary reporting

# Fixed section order for summary display
readonly _UPDATE_SECTION_ORDER=(
  brew softwareupdate apt snap flatpak mas ai-config claude plugin-node terraform-skill npm pip pip-check pyenv-shims gems
  git-repos legacy-rsync git-hooks aws rust cargo-tools oh-my-zsh zsh-autosuggestions tpm tfenv cheat.sh brew-drift
)

# _update_diff_lines PRE_FILE POST_FILE
# Outputs lines in POST_FILE that differ from PRE_FILE (new or changed).
_update_diff_lines() {
  local _pre="$1" _post="$2"
  comm -13 <(sort "${_pre}") <(sort "${_post}")
}

# The result for a section whose before or after snapshot failed: the update ran,
# but the change list cannot be derived from it.
_UPDATE_NO_CHANGE_LIST="updated; change list unavailable (snapshot failed)"

# _update_capture FILE CMD... -- writes CMD's stdout to FILE. When CMD fails the
# file is removed: `cmd > file || true` creates the file before cmd runs, so a
# failed snapshot used to leave an empty list that diffed as "no changes" (or as
# every package changed).
_update_capture() {
  local _file="$1"
  shift
  "$@" > "${_file}" 2> /dev/null || rm -f "${_file}"
}

# _update_capture_sha FILE DIR -- the HEAD SHA of DIR into FILE; no file when git
# fails or prints nothing.
_update_capture_sha() {
  _update_capture "$1" _update_git -C "$2" rev-parse HEAD
  [[ -s "$1" ]] || rm -f "$1"
}

# _update_apt_list -- "package version" per installed deb.
_update_apt_list() {
  dpkg-query -W -f='${Package} ${Version}\n'
}

# _update_snap_list -- "name version" per installed snap. Fails when `snap list`
# fails, which `snap list | awk` hides behind awk's exit status.
_update_snap_list() {
  local _out
  _out="$(snap list --color=never 2> /dev/null)" || return 1
  printf '%s\n' "${_out}" | awk 'NR>1 {print $1, $2}'
}

# _update_claude_list -- one "Version:" line per installed plugin. Fails when
# `claude plugins list` fails; no plugins installed is an empty list, not a failure.
_update_claude_list() {
  local _out
  _out="$(claude plugins list 2> /dev/null)" || return 1
  printf '%s\n' "${_out}" | { grep 'Version:' || true; } | sed 's/^[[:space:]]*//'
}

# _update_npm_list -- one line per global npm package. `npm list -g` exits
# non-zero on harmless peer-dependency warnings, so success is judged by output:
# a listing with no package line failed.
_update_npm_list() {
  local _pkgs
  _pkgs="$(npm list -g --depth=0 2> /dev/null | grep -v '^/')"
  [[ -n ${_pkgs} ]] || return 1
  printf '%s\n' "${_pkgs}"
}

# _update_gem_list -- `gem list` from the ruby update_gems updates. Fails when
# _ruby_gem_path_prefix (lib/developer.sh) is not loaded, rather than listing
# whatever gem PATH finds and reading "no changes".
_update_gem_list() {
  declare -f _ruby_gem_path_prefix > /dev/null || return 1
  PATH="$(_ruby_gem_path_prefix)${PATH}" gem list
}

# _update_softwareupdate_labels -- pending update labels, one per line. Fails only
# when softwareupdate -l fails; no pending update is an empty, successful list.
_update_softwareupdate_labels() {
  local _out
  _out="$(softwareupdate -l 2> /dev/null)" || return 1
  printf '%s\n' "${_out}" | sed -n 's/^\* Label: //p'
}

# _update_git ARGS... -- git with the four repo-location variables stripped: git -C
# does not override an inherited GIT_DIR, which a hook or worktree parent exports.
# A local copy of workflows.sh's _git_noenv, since this file is sourced on its own.
_update_git() {
  env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE git "$@"
}

# _update_git_diff DIR OLD_SHA
# Outputs git log from OLD_SHA to HEAD in DIR (one line per commit).
_update_git_diff() {
  local _dir="$1" _old_sha="$2"
  _update_git -C "${_dir}" log "${_old_sha}..HEAD" --oneline 2>/dev/null
}

# _update_skip SECTION REASON
# Records a section as skipped with the given reason.
_update_skip() {
  local _section="$1" _reason="$2"
  printf "SKIP\n" > "${_DOTFILES_RUN_TMPDIR}/status_${_section}"
  printf "%s\n" "${_reason}" > "${_DOTFILES_RUN_TMPDIR}/result_${_section}"
}

# _update_status_is_fail SECTION -- true when SECTION already recorded FAIL. The
# _update_ok and _update_warn writers check it so a later call never softens a FAIL.
_update_status_is_fail() {
  [[ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_$1" 2>/dev/null)" == "FAIL" ]]
}

# _update_ok SECTION MESSAGE
# Records a section as passing. Use for advisory check sections (like brew-drift)
# that bypass _update_record_start/_update_record_end. Do NOT call this on sections
# that use _update_record_end — it would silently overwrite the timed result.
_update_ok() {
  local _section="$1" _msg="$2"
  _update_status_is_fail "${_section}" && return 0
  printf "OK\n" > "${_DOTFILES_RUN_TMPDIR}/status_${_section}"
  printf "%s\n" "${_msg}" > "${_DOTFILES_RUN_TMPDIR}/result_${_section}"
}

# _update_warn SECTION MESSAGE
# Records a section as a non-blocking warning. Two lifecycles call this:
# (1) an advisory check section that bypasses _update_record_end entirely,
# same as _update_ok; and (2) a timed section using the rc-2-means-partial-
# success shape -- _update_record_end "SECTION" 0 first (so the section's
# own case-arm result, or the default "updated", is recorded), then this
# call overwrites the status to WARN. brew-drift is shape (1); every other
# caller is shape (2). The call sites are the list, not this comment:
# git grep -n '_update_warn ' lib/
_update_warn() {
  local _section="$1" _msg="$2"
  _update_status_is_fail "${_section}" && return 0
  printf "WARN\n" > "${_DOTFILES_RUN_TMPDIR}/status_${_section}"
  printf "%s\n" "${_msg}" > "${_DOTFILES_RUN_TMPDIR}/result_${_section}"
}

# _update_fail SECTION MESSAGE
# Records a section as a blocking failure. Same lifecycle constraint as
# _update_ok: for advisory check sections only, not timed _update_record_end
# sections. The FAIL status is counted into _fail, which _update_summary passes
# to _ledger_write_run_entry as the run's status — so this is durable, not just
# a line on the terminal.
_update_fail() {
  local _section="$1" _msg="$2"
  printf "FAIL\n" > "${_DOTFILES_RUN_TMPDIR}/status_${_section}"
  printf "%s\n" "${_msg}" > "${_DOTFILES_RUN_TMPDIR}/result_${_section}"
}

# _update_printable_lines -- stdin to stdout, each line cut to printable ASCII.
# The summary prints detail verbatim (printf '%s'), so a raw byte in a tool's
# output would reach the terminal and the update log: a cursor-movement or OSC
# escape, a BEL, or a right-to-left override (U+202E) reordering the line.
# Whole CSI sequences (colour, cursor movement, erase) go first, so they leave no
# "[2K" residue and a line of nothing but them ends up blank; a tab becomes a
# space, so tab-separated words stay apart; the non-ASCII characters our own
# messages use (em dash, box-drawing line and corners, right arrow) become ASCII,
# since our log lines reach err_<section> too; then every byte outside [:print:]
# goes. The C locale makes [:print:] ASCII-only whatever the caller's locale
# (other non-ASCII text is dropped, a cost accepted for one rule everywhere) and
# keeps BSD sed from refusing an invalid UTF-8 byte.
_update_printable_lines() {
  LC_ALL=C sed -e 's|\x1b\[[0-?]*[ -/]*[@-~]||g' \
    -e 's|\xe2\x80\x94|-|g; s|\xe2\x94\x80|-|g; s|\xe2\x86\x92|->|g; s|\xe2\x94\x9c|+|g; s|\xe2\x94\x94|+|g' \
    | LC_ALL=C tr '\t' ' ' | LC_ALL=C tr -cd '[:print:]\n'
}

# _update_printable TEXT -- TEXT cut to printable ASCII, newlines dropped, for a
# value interpolated into one line: apt's fetch host and reason (the reason is a
# mirror's HTTP reason phrase, so a man-in-the-middle on a plain-http source
# controls it), its signer host and reason, and kept-back package names.
_update_printable() {
  printf '%s\n' "$1" | _update_printable_lines | LC_ALL=C tr -d '\n'
}

# _update_write_detail_from_err SECTION LABEL
# Extracts a trimmed tail of err_${SECTION} into detail_${SECTION}. Shared by
# _update_record_end's FAIL path and run_update's WARN call sites (legacy-rsync
# and others) so partial-failure detail captured via `tee` isn't silently
# dropped just because the section didn't hard-fail. Lines are cut to printable
# ASCII before blank ones are dropped, so a line of nothing but escapes cannot
# take a slot in the 10-line window.
_update_write_detail_from_err() {
  local _section="$1" _label="$2"
  local _err_file="${_DOTFILES_RUN_TMPDIR}/err_${_section}"
  if [[ -f "${_err_file}" ]] && [[ -s "${_err_file}" ]]; then
    local _err_tail
    _err_tail=$(_update_printable_lines < "${_err_file}" | grep -v '^[[:space:]]*$' | tail -10)
    if [[ -n "${_err_tail}" ]]; then
      printf "[%s %s]\n%s\n" "${_section}" "${_label}" "${_err_tail}" \
        > "${_DOTFILES_RUN_TMPDIR}/detail_${_section}"
    fi
  fi
}

# _update_write_detail_from_warn SECTION LABEL
# Like _update_write_detail_from_err, but keeps only the [WARN] lines, so a
# section that logs a line per item (git-repos logs one per repo) cannot push the
# warning that explains the WARN out of the window. Capped at 20 lines with a
# count of the rest. With no [WARN] line it falls back to the plain tail, so any
# non-blank output still reaches the detail.
_update_write_detail_from_warn() {
  local _section="$1" _label="$2"
  local _err_file="${_DOTFILES_RUN_TMPDIR}/err_${_section}" _warns _n
  [[ -s "${_err_file}" ]] || return 0
  _warns="$(_update_printable_lines < "${_err_file}" | grep '^\[WARN\]' || true)"
  if [[ -z "${_warns}" ]]; then
    _update_write_detail_from_err "${_section}" "${_label}"
    return 0
  fi
  _n="$(printf '%s\n' "${_warns}" | wc -l | tr -d ' ')"
  {
    printf "[%s %s]\n" "${_section}" "${_label}"
    printf '%s\n' "${_warns}" | head -20
    if [[ ${_n} -gt 20 ]]; then
      printf '... and %d more\n' "$((_n - 20))"
    fi
  } > "${_DOTFILES_RUN_TMPDIR}/detail_${_section}"
}

# _update_record_start SECTION
# Takes pre-snapshot appropriate for the section type. Marks the section STARTED
# first, so one that never reaches _update_record_end or _update_skip still gets a
# row (a FAIL, from _update_summary) instead of none.
_update_record_start() {
  local _section="$1"
  printf "STARTED\n" > "${_DOTFILES_RUN_TMPDIR}/status_${_section}"
  case "${_section}" in
    brew)
      _update_capture "${_DOTFILES_RUN_TMPDIR}/pre_brew_formula" brew list --formula --versions
      _update_capture "${_DOTFILES_RUN_TMPDIR}/pre_brew_cask" brew list --cask --versions
      ;;
    gems)
      _update_capture "${_DOTFILES_RUN_TMPDIR}/pre_gems" _update_gem_list
      ;;
    pip)
      # pip snapshot is captured inside the Python block; nothing to do here
      ;;
    oh-my-zsh)
      _update_capture_sha "${_DOTFILES_RUN_TMPDIR}/pre_oh-my-zsh" "${HOME}/.oh-my-zsh"
      ;;
    tpm)
      _update_capture_sha "${_DOTFILES_RUN_TMPDIR}/pre_tpm" "${HOME}/.tmux/plugins/tpm"
      ;;
    tfenv)
      _update_capture_sha "${_DOTFILES_RUN_TMPDIR}/pre_tfenv" "${HOME}/.tfenv"
      ;;
    zsh-autosuggestions)
      _update_capture_sha "${_DOTFILES_RUN_TMPDIR}/pre_zsh-autosuggestions" "${HOME}/.oh-my-zsh/custom/plugins/zsh-autosuggestions"
      ;;
    softwareupdate)
      _update_capture "${_DOTFILES_RUN_TMPDIR}/pre_softwareupdate" _update_softwareupdate_labels
      ;;
    apt)
      if [[ -n ${UBUNTU:-} ]]; then
        _update_capture "${_DOTFILES_RUN_TMPDIR}/pre_apt" _update_apt_list
      else
        _update_skip "apt" "not applicable"
      fi
      ;;
    snap)
      if [[ -n ${UBUNTU:-} ]]; then
        _update_capture "${_DOTFILES_RUN_TMPDIR}/pre_snap" _update_snap_list
      else
        _update_skip "snap" "not applicable"
      fi
      ;;
    claude)
      _update_capture "${_DOTFILES_RUN_TMPDIR}/pre_claude" _update_claude_list
      ;;
    npm)
      _update_capture "${_DOTFILES_RUN_TMPDIR}/pre_npm" _update_npm_list
      ;;
    legacy-rsync)
      if ! _is_legacy_sync_host; then
        _update_skip "legacy-rsync" "not studio"
      # _dry_run_active: see lib/helpers.sh
      elif _dry_run_active; then
        _update_skip "legacy-rsync" "dry run"
      fi
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
  if [[ -f "${_DOTFILES_RUN_TMPDIR}/status_${_section}" ]]; then
    local _existing_status
    _existing_status=$(cat "${_DOTFILES_RUN_TMPDIR}/status_${_section}")
    if [[ "${_existing_status}" == "SKIP" ]]; then
      return 0
    fi
  fi

  if [[ "${_exit}" -ne 0 ]]; then
    printf "FAIL\n" > "${_DOTFILES_RUN_TMPDIR}/status_${_section}"
    local _fail_result_file="${_DOTFILES_RUN_TMPDIR}/fail_result_${_section}"
    if [[ -f "${_fail_result_file}" ]]; then
      cat "${_fail_result_file}" > "${_DOTFILES_RUN_TMPDIR}/result_${_section}"
    else
      printf "exit %d\n" "${_exit}" > "${_DOTFILES_RUN_TMPDIR}/result_${_section}"
    fi
    _update_write_detail_from_err "${_section}" "error output"
    return
  fi

  case "${_section}" in
    brew)
      local _formula_diff="" _cask_diff="" _formula_count=0 _cask_count=0 _f
      _update_capture "${_DOTFILES_RUN_TMPDIR}/post_brew_formula" brew list --formula --versions
      _update_capture "${_DOTFILES_RUN_TMPDIR}/post_brew_cask" brew list --cask --versions
      for _f in pre_brew_formula post_brew_formula pre_brew_cask post_brew_cask; do
        [[ -f "${_DOTFILES_RUN_TMPDIR}/${_f}" ]] || _result="${_UPDATE_NO_CHANGE_LIST}"
      done
      if [[ -z "${_result}" ]]; then
        _formula_diff=$(_update_diff_lines "${_DOTFILES_RUN_TMPDIR}/pre_brew_formula" "${_DOTFILES_RUN_TMPDIR}/post_brew_formula")
        _formula_count=$(printf '%s' "${_formula_diff}" | grep -c . || true)
        _cask_diff=$(_update_diff_lines "${_DOTFILES_RUN_TMPDIR}/pre_brew_cask" "${_DOTFILES_RUN_TMPDIR}/post_brew_cask")
        _cask_count=$(printf '%s' "${_cask_diff}" | grep -c . || true)
      fi
      if [[ -n "${_result}" ]]; then
        :
      elif [[ ${_formula_count} -gt 0 ]] || [[ ${_cask_count} -gt 0 ]]; then
        if [[ ${_formula_count} -gt 0 ]]; then
          _result="${_formula_count} formulae ($(printf '%s' "${_formula_diff}" | paste -sd', ' -))"
        fi
        if [[ ${_cask_count} -gt 0 ]]; then
          [[ -n "${_result}" ]] && _result="${_result}"$'\n'
          _result="${_result}${_cask_count} cask(s) ($(printf '%s' "${_cask_diff}" | paste -sd', ' -))"
        fi
      else
        _result="no changes"
      fi
      ;;
    mas)
      if [[ -f "${_DOTFILES_RUN_TMPDIR}/err_mas" ]]; then
        local _mas_updated
        _mas_updated=$(grep '^==> Updated ' "${_DOTFILES_RUN_TMPDIR}/err_mas" || true)
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
      [[ -f "${_DOTFILES_RUN_TMPDIR}/pre_gems" ]] \
        && _update_capture "${_DOTFILES_RUN_TMPDIR}/post_gems" _update_gem_list
      if [[ -f "${_DOTFILES_RUN_TMPDIR}/pre_gems" && -f "${_DOTFILES_RUN_TMPDIR}/post_gems" ]]; then
        local _gem_diff
        _gem_diff=$(_update_diff_lines "${_DOTFILES_RUN_TMPDIR}/pre_gems" "${_DOTFILES_RUN_TMPDIR}/post_gems")
        local _gem_count
        _gem_count=$(printf '%s' "${_gem_diff}" | grep -c . || true)
        if [[ ${_gem_count} -gt 0 ]]; then
          _result="${_gem_count} gem(s) ($(printf '%s' "${_gem_diff}" | paste -sd', ' -))"
        else
          _result="no changes"
        fi
      else
        _result="${_UPDATE_NO_CHANGE_LIST}"
      fi
      ;;
    pip)
      if [[ -f "${_DOTFILES_RUN_TMPDIR}/pip_outdated" ]]; then
        local _pip_count
        _pip_count=$(grep -c . "${_DOTFILES_RUN_TMPDIR}/pip_outdated" || true)
        if [[ ${_pip_count} -gt 0 ]]; then
          _result="${_pip_count} package(s) ($(paste -sd', ' - < "${_DOTFILES_RUN_TMPDIR}/pip_outdated"))"
        else
          _result="no changes"
        fi
      else
        _result="updated"
      fi
      ;;
    oh-my-zsh|tpm|tfenv|zsh-autosuggestions)
      if [[ -f "${_DOTFILES_RUN_TMPDIR}/pre_${_section}" ]]; then
        local _old_sha _git_dir
        _old_sha=$(cat "${_DOTFILES_RUN_TMPDIR}/pre_${_section}")
        case "${_section}" in
          oh-my-zsh) _git_dir="${HOME}/.oh-my-zsh" ;;
          tpm) _git_dir="${HOME}/.tmux/plugins/tpm" ;;
          tfenv) _git_dir="${HOME}/.tfenv" ;;
          zsh-autosuggestions) _git_dir="${HOME}/.oh-my-zsh/custom/plugins/zsh-autosuggestions" ;;
        esac
        local _commits _commit_count
        if ! _commits=$(_update_git_diff "${_git_dir}" "${_old_sha}"); then
          _result="${_UPDATE_NO_CHANGE_LIST}"
        else
          _commit_count=$(printf '%s' "${_commits}" | grep -c . || true)
          if [[ ${_commit_count} -gt 0 ]]; then
            _result="${_commit_count} commit(s)"
          else
            _result="no changes"
          fi
        fi
      else
        _result="${_UPDATE_NO_CHANGE_LIST}"
      fi
      ;;
    softwareupdate)
      # Installed = listed before and gone after; pending = whatever is still
      # listed after the install. The pre list alone only says what was
      # available, not what the install did.
      [[ -f "${_DOTFILES_RUN_TMPDIR}/pre_softwareupdate" ]] \
        && _update_capture "${_DOTFILES_RUN_TMPDIR}/post_softwareupdate" _update_softwareupdate_labels
      if [[ -f "${_DOTFILES_RUN_TMPDIR}/pre_softwareupdate" && -f "${_DOTFILES_RUN_TMPDIR}/post_softwareupdate" ]]; then
        local _su_done _su_pending _su_done_n _su_pending_n
        _su_done=$(LC_ALL=C comm -23 <(LC_ALL=C sort "${_DOTFILES_RUN_TMPDIR}/pre_softwareupdate") \
          <(LC_ALL=C sort "${_DOTFILES_RUN_TMPDIR}/post_softwareupdate"))
        _su_pending=$(grep -v '^$' "${_DOTFILES_RUN_TMPDIR}/post_softwareupdate" || true)
        _su_done_n=$(printf '%s' "${_su_done}" | grep -c . || true)
        _su_pending_n=$(printf '%s' "${_su_pending}" | grep -c . || true)
        if [[ ${_su_done_n} -gt 0 ]]; then
          _result="${_su_done_n} update(s) installed ($(printf '%s' "${_su_done}" | paste -sd', ' -))"
        else
          _result="no changes"
        fi
        if [[ ${_su_pending_n} -gt 0 ]]; then
          _result="${_result}; ${_su_pending_n} still pending ($(printf '%s' "${_su_pending}" | paste -sd', ' -))"
        fi
      else
        _result="${_UPDATE_NO_CHANGE_LIST}"
      fi
      ;;
    claude)
      [[ -f "${_DOTFILES_RUN_TMPDIR}/pre_claude" ]] \
        && _update_capture "${_DOTFILES_RUN_TMPDIR}/post_claude" _update_claude_list
      if [[ -f "${_DOTFILES_RUN_TMPDIR}/pre_claude" && -f "${_DOTFILES_RUN_TMPDIR}/post_claude" ]]; then
        local _claude_diff
        _claude_diff=$(_update_diff_lines "${_DOTFILES_RUN_TMPDIR}/pre_claude" "${_DOTFILES_RUN_TMPDIR}/post_claude")
        local _claude_count
        _claude_count=$(printf '%s' "${_claude_diff}" | grep -c . || true)
        if [[ ${_claude_count} -gt 0 ]]; then
          _result="${_claude_count} plugin(s) updated"
        else
          _result="no changes"
        fi
      else
        _result="${_UPDATE_NO_CHANGE_LIST}"
      fi
      ;;
    npm)
      [[ -f "${_DOTFILES_RUN_TMPDIR}/pre_npm" ]] \
        && _update_capture "${_DOTFILES_RUN_TMPDIR}/post_npm" _update_npm_list
      if [[ -f "${_DOTFILES_RUN_TMPDIR}/pre_npm" && -f "${_DOTFILES_RUN_TMPDIR}/post_npm" ]]; then
        local _npm_diff _npm_count
        _npm_diff=$(_update_diff_lines "${_DOTFILES_RUN_TMPDIR}/pre_npm" "${_DOTFILES_RUN_TMPDIR}/post_npm")
        _npm_count=$(printf '%s' "${_npm_diff}" | grep -c . || true)
        if [[ ${_npm_count} -gt 0 ]]; then
          _result="${_npm_count} package(s) ($(printf '%s' "${_npm_diff}" | sed 's/^[├└]── //' | paste -sd', ' -))"
        else
          _result="no changes"
        fi
      else
        _result="${_UPDATE_NO_CHANGE_LIST}"
      fi
      ;;
    apt)
      [[ -f "${_DOTFILES_RUN_TMPDIR}/pre_apt" ]] \
        && _update_capture "${_DOTFILES_RUN_TMPDIR}/post_apt" _update_apt_list
      if [[ -f "${_DOTFILES_RUN_TMPDIR}/pre_apt" && -f "${_DOTFILES_RUN_TMPDIR}/post_apt" ]]; then
        local _apt_diff _apt_count
        _apt_diff=$(_update_diff_lines "${_DOTFILES_RUN_TMPDIR}/pre_apt" "${_DOTFILES_RUN_TMPDIR}/post_apt")
        _apt_count=$(printf '%s' "${_apt_diff}" | grep -c . || true)
        if [[ ${_apt_count} -gt 0 ]]; then
          _result="${_apt_count} package(s) ($(printf '%s' "${_apt_diff}" | paste -sd', ' -))"
        else
          _result="no changes"
        fi
      else
        _result="${_UPDATE_NO_CHANGE_LIST}"
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
      [[ -f "${_DOTFILES_RUN_TMPDIR}/pre_snap" ]] \
        && _update_capture "${_DOTFILES_RUN_TMPDIR}/post_snap" _update_snap_list
      if [[ -f "${_DOTFILES_RUN_TMPDIR}/pre_snap" && -f "${_DOTFILES_RUN_TMPDIR}/post_snap" ]]; then
        local _snap_diff _snap_count
        _snap_diff=$(_update_diff_lines "${_DOTFILES_RUN_TMPDIR}/pre_snap" "${_DOTFILES_RUN_TMPDIR}/post_snap")
        _snap_count=$(printf '%s' "${_snap_diff}" | grep -c . || true)
        if [[ ${_snap_count} -gt 0 ]]; then
          _result="${_snap_count} package(s) ($(printf '%s' "${_snap_diff}" | paste -sd', ' -))"
        else
          _result="no changes"
        fi
      else
        _result="${_UPDATE_NO_CHANGE_LIST}"
      fi
      ;;
    git-hooks)
      # Hook installs go through run_cmd, which only prints under DRY_RUN,
      # so "updated" would claim installs that never ran. The checks did
      # run, so this is OK, not SKIP.
      if _dry_run_active; then
        _result="dry run: install skipped"
      else
        _result="updated"
      fi
      ;;
    *)
      _result="updated"
      ;;
  esac

  printf "OK\n" > "${_DOTFILES_RUN_TMPDIR}/status_${_section}"
  printf "%s\n" "${_result}" > "${_DOTFILES_RUN_TMPDIR}/result_${_section}"
}

# _ledger_write_run_entry RUN_TYPE EXIT_CODE
# Writes a state-ledger CMDB entry for any dotfiles run function.
# RUN_TYPE: update | setup_user | setup | developer | recreate_venv | recreate_ruby
# EXIT_CODE: return code of the run function (0=success).
# No-ops when _DOTFILES_RUN_TMPDIR/started_at absent (not called from a
# run_* function) or when machine-id is absent (ledger not initialized).
_ledger_write_run_entry() {
  local _run_type="${1:?_ledger_write_run_entry: run_type required}"
  local _exit_code="${2:-0}"

  [[ ! -f "${_DOTFILES_RUN_TMPDIR}/started_at" ]] && return 0
  local _machine_id_path="${HOME}/.config/dotfiles/machine-id"
  [[ ! -f "${_machine_id_path}" ]] && return 0

  local _machine_id _started_at _start_epoch _now_epoch _duration _run_id _git_sha
  _machine_id=$(tr -d '[:space:]' < "${_machine_id_path}" 2>/dev/null)
  _started_at=$(cat "${_DOTFILES_RUN_TMPDIR}/started_at" 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)
  _start_epoch=$(cat "${_DOTFILES_RUN_TMPDIR}/start_epoch" 2>/dev/null || printf '0')
  _now_epoch=$(date +%s)
  _duration=$(( _now_epoch - _start_epoch ))
  _run_id=$(cat "${_DOTFILES_RUN_TMPDIR}/run_id" 2>/dev/null || \
    python3 -c "import uuid; print(str(uuid.uuid4()))" 2>/dev/null || printf 'unknown')
  _git_sha=$(cat "${_DOTFILES_RUN_TMPDIR}/git_sha" 2>/dev/null || printf 'unknown')

  local _success="true"
  [[ "${_exit_code}" -ne 0 ]] && _success="false"

  local _hostname _os _distro_version
  _hostname=$(hostname -s 2>/dev/null || printf 'unknown')
  if [[ -n "${MACOS:-}" ]]; then
    _os="macos"
    _distro_version=$(sw_vers -productVersion 2>/dev/null || printf 'unknown')
  elif [[ -n "${UBUNTU:-}" ]]; then
    _os="linux"
    _distro_version=$(lsb_release -rs 2>/dev/null || printf 'unknown')
  else
    _os="unknown"
    _distro_version="unknown"
  fi

  # macOS-only: the machine's `make` major version. `make` (not `gmake`) is
  # deliberate -- this measures what `make` actually resolves to for this
  # process, which is the divergence signal the field exists to catch: a
  # machine can have GNU make 4.x installed via Homebrew while `make` still
  # resolves to Apple's bundled 3.81 if the gnubin PATH prepend isn't in
  # effect. Verified in this session: on a machine with both installed,
  # `make --version | head -1` printed "GNU Make 3.81" while
  # `gmake --version | head -1` printed "GNU Make 4.4.1" -- probing `gmake`
  # would have hidden exactly the drift this field is meant to surface.
  local _make_version_fragment=""
  if [[ -n "${MACOS:-}" ]]; then
    local _make_version_raw _make_version_major
    _make_version_raw=$(make --version 2>/dev/null | head -1)
    _make_version_major=$(printf '%s' "${_make_version_raw}" | grep -oE '[0-9]+' | head -1)
    # Validate with a regex before any numeric comparison. Verified in this
    # session: `x="abc"; [[ "$x" -ge 0 ]]` exits 0 (true) rather than
    # erroring -- bash arithmetic treats a non-numeric, identifier-shaped
    # operand as an unset variable name, which reads as 0. An unvalidated
    # `-ge`/`-lt` on a raw grep match would silently accept garbage as a
    # valid major instead of falling through to "unknown".
    if [[ "${_make_version_major}" =~ ^[0-9]+$ ]] && [[ "${_make_version_major}" -ge 0 ]]; then
      printf -v _make_version_fragment ',\n  "make_version": "%s"' "${_make_version_major}"
    else
      printf -v _make_version_fragment ',\n  "make_version": "unknown"'
    fi
  fi

  # Base JSON — common to all run types (no trailing comma, no closing brace)
  local _base_json
  printf -v _base_json '{
  "schema_version": "1.0",
  "run_id": "%s",
  "tool": "dotfiles",
  "entity_id": "%s",
  "triggered_by": "manual",
  "git_sha": "%s",
  "git_repo": "dotfiles",
  "started_at": "%s",
  "duration_seconds": %d,
  "success": %s,
  "machine_id": "%s",
  "hostname": "%s",
  "os": "%s",
  "distro_version": "%s",
  "run_type": "%s"' \
    "${_run_id}" "${_machine_id}" "${_git_sha}" "${_started_at}" \
    "${_duration}" "${_success}" \
    "${_machine_id}" "${_hostname}" "${_os}" "${_distro_version}" \
    "${_run_type}"
  _base_json+="${_make_version_fragment}"

  if [[ "${_run_type}" == "update" ]]; then
    # update-specific fields: failure_stage, workflows_ran, packages_updated_count
    local _failure_stage="null"
    if [[ "${_exit_code}" -ne 0 ]]; then
      local _s
      for _s in "${_UPDATE_SECTION_ORDER[@]}"; do
        if [[ -f "${_DOTFILES_RUN_TMPDIR}/status_${_s}" ]] && \
           [[ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_${_s}")" == "FAIL" ]]; then
          _failure_stage="\"${_s}\""
          break
        fi
      done
    fi

    local _packages_updated=0
    local _s _result_str _count
    for _s in brew pip gems mas apt snap npm; do
      if [[ -f "${_DOTFILES_RUN_TMPDIR}/result_${_s}" ]]; then
        _result_str=$(cat "${_DOTFILES_RUN_TMPDIR}/result_${_s}")
        if [[ "${_result_str}" != "no changes" && "${_result_str}" != "updated" && \
              "${_result_str}" != *"skipped"* ]]; then
          # brew's result is two lines when formulae and casks both changed; sum each line's count.
          _count=$(printf '%s\n' "${_result_str}" | awk '/^[0-9]+/ { n += $1 } END { print n + 0 }')
          _packages_updated=$(( _packages_updated + ${_count:-0} ))
        fi
      fi
    done

    local _workflows_json="["
    local _first=1 _s _st
    for _s in "${_UPDATE_SECTION_ORDER[@]}"; do
      if [[ -f "${_DOTFILES_RUN_TMPDIR}/status_${_s}" ]]; then
        _st=$(cat "${_DOTFILES_RUN_TMPDIR}/status_${_s}")
        if [[ "${_st}" != "SKIP" ]]; then
          [[ ${_first} -eq 0 ]] && _workflows_json+=","
          _workflows_json+="\"${_s}\""
          _first=0
        fi
      fi
    done
    _workflows_json+="]"

    local _ext_json
    printf -v _ext_json ',
  "failure_stage": %s,
  "workflows_ran": %s,
  "packages_updated_count": %d
}' "${_failure_stage}" "${_workflows_json}" "${_packages_updated}"
    ledger_write_entry "${_base_json}${_ext_json}"
  else
    ledger_write_entry "${_base_json}
}"
  fi
}

# _ledger_write_dotfiles_entry — backward-compat shim for update runs.
# Reads _fail from dynamic scoping (set in _update_summary).
_ledger_write_dotfiles_entry() {
  _ledger_write_run_entry "update" "${_fail:-0}"
}

# _update_summary
# Reads status/result files, prints formatted table, appends to log file.
_update_summary() {
  local _ok=0 _fail=0 _skip=0 _warn=0
  local _output=""
  local _timestamp
  _timestamp=$(date '+%Y-%m-%d %H:%M:%S')

  _output+="=== Update Summary — ${_timestamp} ==="$'\n\n'

  local _section _status _result
  for _section in "${_UPDATE_SECTION_ORDER[@]}"; do
    if [[ ! -f "${_DOTFILES_RUN_TMPDIR}/status_${_section}" ]]; then
      continue
    fi
    _status=$(cat "${_DOTFILES_RUN_TMPDIR}/status_${_section}")
    _result=$(cat "${_DOTFILES_RUN_TMPDIR}/result_${_section}" 2>/dev/null)

    # Anything but the four final statuses is a FAIL, rewritten on disk so the
    # ledger entry's failure_stage (which reads these files) names it too.
    case "${_status}" in
      OK|FAIL|SKIP|WARN) ;;
      *)
        if [[ "${_status}" == "STARTED" ]]; then
          _result="started but did not finish"
        else
          _result="unrecognised status '${_status}'"
        fi
        _status="FAIL"
        printf "FAIL\n" > "${_DOTFILES_RUN_TMPDIR}/status_${_section}"
        printf "%s\n" "${_result}" > "${_DOTFILES_RUN_TMPDIR}/result_${_section}"
        ;;
    esac

    case "${_status}" in
      OK)
        _ok=$(( _ok + 1 ))
        _output+="$(printf "[OK]   %-20s %s" "${_section}" "${_result}")"$'\n'
        ;;
      FAIL)
        _fail=$(( _fail + 1 ))
        _output+="$(printf "[FAIL] %-20s %s" "${_section}" "${_result}")"$'\n'
        ;;
      SKIP)
        _skip=$(( _skip + 1 ))
        _output+="$(printf "[SKIP] %-20s %s" "${_section}" "${_result}")"$'\n'
        ;;
      WARN)
        _warn=$(( _warn + 1 ))
        _output+="$(printf "[WARN] %-20s %s" "${_section}" "${_result}")"$'\n'
        ;;
    esac
  done

  local _total=$(( _ok + _fail + _skip + _warn ))
  _output+=$'\n'"$(printf "%d sections: %d OK, %d failed, %d warnings, %d skipped" "${_total}" "${_ok}" "${_fail}" "${_warn}" "${_skip}")"$'\n'

  # Build detail output (in section order for deterministic output)
  local _detail_output=""
  for _section in "${_UPDATE_SECTION_ORDER[@]}"; do
    if [[ -f "${_DOTFILES_RUN_TMPDIR}/detail_${_section}" ]]; then
      _detail_output+=$'\n'"$(cat "${_DOTFILES_RUN_TMPDIR}/detail_${_section}")"$'\n'
    fi
  done

  # Print to terminal
  printf '%s' "${_output}"
  [[ -n "${_detail_output}" ]] && printf '%s' "${_detail_output}"

  # Append to log file
  local _log="${UPDATE_LOG_PATH:-${HOME}/.dotfiles-update.log}"
  {
    printf "────────────────────────────────────────────────────────\n"
    printf '%s' "${_output}"
    [[ -n "${_detail_output}" ]] && printf '%s' "${_detail_output}"
    :
  } >> "${_log}" 2>/dev/null || log_warn "Could not write to ${_log}"

  printf "Log appended: %s\n" "${_log}"

  _ledger_write_dotfiles_entry || true
  return $(( _fail > 0 ))
}

# _brewfile_extract_cap LINE
# Extracts the capability tag from a Brewfile line (e.g. "# [HAS_DEVTOOLS]" → "HAS_DEVTOOLS").
# Prints nothing if the line has no valid tag.
_brewfile_extract_cap() {
  printf '%s\n' "${1}" | sed 's/.*# \[//;s/\].*//' | grep -E '^[A-Z][A-Z0-9_]+$' || true
}

# _brewfile_parse_section TYPE BREWFILE
# Reads entries of TYPE (brew, cask, tap) from BREWFILE.
# Lines tagged # [HAS_*] are INCLUDED only when that capability is set on this machine.
# Lines with no tag are always included.
_brewfile_parse_section() {
  local _type="${1}" _brewfile="${2}"
  while IFS= read -r _line; do
    local _cap
    _cap=$(_brewfile_extract_cap "${_line}")
    if [[ -n "${_cap}" ]] && [[ -z "${!_cap:-}" ]]; then
      continue
    fi
    case "${_type}" in
      brew) printf '%s\n' "${_line}" | sed 's/^brew "//;s/".*//' ;;
      cask) printf '%s\n' "${_line}" | sed 's/^cask "//;s/".*//' ;;
      tap)  printf '%s\n' "${_line}" | sed 's/^tap "//;s/".*//' ;;
    esac
  done < <(grep "^${_type} \"" "${_brewfile}")
}

# _brewfile_parse_inactive TYPE BREWFILE
# Reads entries of TYPE (brew, cask, tap) from BREWFILE that are tagged with a
# capability that is NOT set on this machine.  Used to suppress "untracked"
# reports for packages that are installed but belong to an inactive profile.
_brewfile_parse_inactive() {
  local _type="${1}" _brewfile="${2}"
  while IFS= read -r _line; do
    local _cap
    _cap=$(_brewfile_extract_cap "${_line}")
    # Only emit entries whose capability tag is explicitly inactive (tag present, var unset)
    if [[ -z "${_cap}" ]] || [[ -n "${!_cap:-}" ]]; then
      continue
    fi
    case "${_type}" in
      brew) printf '%s\n' "${_line}" | sed 's/^brew "//;s/".*//' ;;
      cask) printf '%s\n' "${_line}" | sed 's/^cask "//;s/".*//' ;;
      tap)  printf '%s\n' "${_line}" | sed 's/^tap "//;s/".*//' ;;
    esac
  done < <(grep "^${_type} \"" "${_brewfile}")
}

# _update_check_brewfile_drift
# Compares Brewfile (formulae, casks on macOS, taps) against locally installed
# Homebrew packages. Records OK/WARN/SKIP into the update summary.
# Entries tagged # [HAS_*] in the Brewfile are invisible to drift detection on
# machines where that capability is not set — they are neither "missing" nor
# "untracked", so packages installed for another profile cause no noise.
# Uses _OVERRIDE_BREWFILE_PATH seam for testing.
_update_check_brewfile_drift() {
  local _brewfile="${_OVERRIDE_BREWFILE_PATH:-${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile}"

  if ! quiet_which brew; then
    _update_skip "brew-drift" "brew not available"
    return 0
  fi

  # Brewfile is the macOS manifest -- `brew bundle --file Brewfile` runs only from
  # lib/macos.sh:install_macos_casks, while Linux installs a hand-listed subset via
  # _install_ubuntu_brew_packages. Grading a Linux box against it reported 82 missing
  # formulae on claude (2026-09-12): mac-only GNU tools (bash, coreutils, findutils),
  # chruby where Linux uses rbenv, and an arm64-only cask. A WARN that fires on
  # correct state is one a reader learns to skip, and the next one is the one that
  # mattered. An honest SKIP beats a false WARN; a real Linux manifest is backlogged.
  if [[ -z ${MACOS} ]]; then
    _update_skip "brew-drift" "Brewfile is the macOS manifest; Linux installs via _install_ubuntu_brew_packages"
    return 0
  fi

  if [[ ! -f "${_brewfile}" ]]; then
    _update_skip "brew-drift" "Brewfile not found at ${_brewfile}"
    return 0
  fi

  # Parse Brewfile: active = expected on this machine; inactive = invisible to drift
  _brewfile_parse_section  brew "${_brewfile}" | sort > "${_DOTFILES_RUN_TMPDIR}/drift_bf_formulae"
  _brewfile_parse_inactive brew "${_brewfile}" | sort > "${_DOTFILES_RUN_TMPDIR}/drift_ignore_formulae"
  _brewfile_parse_section  tap  "${_brewfile}" | sort > "${_DOTFILES_RUN_TMPDIR}/drift_bf_taps"
  _brewfile_parse_inactive tap  "${_brewfile}" | sort > "${_DOTFILES_RUN_TMPDIR}/drift_ignore_taps"

  # Get actual installed state, stripping packages that belong to an inactive profile
  # so they are invisible to drift detection on this machine.
  # leaves: top-level installs only (for untracked detection, filters transitive deps)
  # all: every installed formula (for missing detection, avoids false positives)
  brew leaves 2>/dev/null | sort \
    | comm -23 - "${_DOTFILES_RUN_TMPDIR}/drift_ignore_formulae" \
    > "${_DOTFILES_RUN_TMPDIR}/drift_inst_formulae_leaves"
  brew list --formula --full-name 2>/dev/null | sort \
    | comm -23 - "${_DOTFILES_RUN_TMPDIR}/drift_ignore_formulae" \
    > "${_DOTFILES_RUN_TMPDIR}/drift_inst_formulae_all"
  brew tap 2>/dev/null \
    | grep -v -E '^homebrew/(bundle|cask|core|services)$' \
    | sort \
    | comm -23 - "${_DOTFILES_RUN_TMPDIR}/drift_ignore_taps" \
    > "${_DOTFILES_RUN_TMPDIR}/drift_inst_taps"

  # Compute formula and tap drift
  # comm -13: lines only in file2 = installed but not in Brewfile (untracked)
  # comm -23: lines only in file1 = in Brewfile but not installed (missing)
  local _untracked_formulae _missing_formulae _untracked_taps _missing_taps
  _untracked_formulae=$(comm -13 "${_DOTFILES_RUN_TMPDIR}/drift_bf_formulae" \
    "${_DOTFILES_RUN_TMPDIR}/drift_inst_formulae_leaves")
  _missing_formulae=$(comm -23 "${_DOTFILES_RUN_TMPDIR}/drift_bf_formulae" \
    "${_DOTFILES_RUN_TMPDIR}/drift_inst_formulae_all")
  _untracked_taps=$(comm -13 "${_DOTFILES_RUN_TMPDIR}/drift_bf_taps" \
    "${_DOTFILES_RUN_TMPDIR}/drift_inst_taps")
  _missing_taps=$(comm -23 "${_DOTFILES_RUN_TMPDIR}/drift_bf_taps" \
    "${_DOTFILES_RUN_TMPDIR}/drift_inst_taps")

  # Cask drift: macOS only (Linux Homebrew does not support casks)
  local _untracked_casks="" _missing_casks=""
  if [[ -n ${MACOS:-} ]]; then
    _brewfile_parse_section  cask "${_brewfile}" | sort > "${_DOTFILES_RUN_TMPDIR}/drift_bf_casks"
    _brewfile_parse_inactive cask "${_brewfile}" | sort > "${_DOTFILES_RUN_TMPDIR}/drift_ignore_casks"
    brew list --cask 2>/dev/null | sort \
      | comm -23 - "${_DOTFILES_RUN_TMPDIR}/drift_ignore_casks" \
      > "${_DOTFILES_RUN_TMPDIR}/drift_inst_casks"
    _untracked_casks=$(comm -13 "${_DOTFILES_RUN_TMPDIR}/drift_bf_casks" \
      "${_DOTFILES_RUN_TMPDIR}/drift_inst_casks")
    _missing_casks=$(comm -23 "${_DOTFILES_RUN_TMPDIR}/drift_bf_casks" \
      "${_DOTFILES_RUN_TMPDIR}/drift_inst_casks")
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
  local _detail="brew-drift details:"$'\n'
  if [[ -n "${_untracked_formulae}" ]] || [[ -n "${_untracked_casks}" ]] || [[ -n "${_untracked_taps}" ]]; then
    _detail+="  Untracked (installed, not in Brewfile):"$'\n'
    while IFS= read -r _pkg; do
      [[ -z "${_pkg}" ]] && continue
      _detail+="    ${_pkg}"$'\n'
    done <<< "${_untracked_formulae}"
    while IFS= read -r _pkg; do
      [[ -z "${_pkg}" ]] && continue
      _detail+="    cask: ${_pkg}"$'\n'
    done <<< "${_untracked_casks}"
    while IFS= read -r _pkg; do
      [[ -z "${_pkg}" ]] && continue
      _detail+="    tap: ${_pkg}"$'\n'
    done <<< "${_untracked_taps}"
  fi
  if [[ -n "${_missing_formulae}" ]] || [[ -n "${_missing_casks}" ]] || [[ -n "${_missing_taps}" ]]; then
    _detail+="  Missing (in Brewfile, not installed):"$'\n'
    while IFS= read -r _pkg; do
      [[ -z "${_pkg}" ]] && continue
      _detail+="    ${_pkg}"$'\n'
    done <<< "${_missing_formulae}"
    while IFS= read -r _pkg; do
      [[ -z "${_pkg}" ]] && continue
      _detail+="    cask: ${_pkg}"$'\n'
    done <<< "${_missing_casks}"
    while IFS= read -r _pkg; do
      [[ -z "${_pkg}" ]] && continue
      _detail+="    tap: ${_pkg}"$'\n'
    done <<< "${_missing_taps}"
  fi

  printf '%s' "${_detail}" > "${_DOTFILES_RUN_TMPDIR}/detail_brew-drift"
}
