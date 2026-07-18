#!/usr/bin/env bash
# lib/git_sync.sh — git-native repo sync (fetch/pull/push, never clobbers local work)

# _git_ssh_opts is normally provided by lib/workflows.sh (same sourcing
# chain in setup_env.sh). Define a fallback only when not already present so
# this file remains self-contained when sourced standalone (e.g. by
# tests/setup_env/git_sync.bats, which does not source lib/workflows.sh).
if ! declare -f _git_ssh_opts >/dev/null 2>&1; then
  _git_ssh_opts() {
    printf '%s' "ssh -o BatchMode=yes -o ConnectTimeout=10"
  }
fi

_git_repo_status() {
  local _path="$1"

  if [[ ! -d "${_path}" ]] || ! git -C "${_path}" rev-parse --git-dir >/dev/null 2>&1; then
    printf "missing\n"
    return 0
  fi

  if ! GIT_SSH_COMMAND="$(_git_ssh_opts)" git -C "${_path}" fetch --quiet 2>/dev/null; then
    printf "unreachable\n"
    return 0
  fi

  if ! git -C "${_path}" rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
    printf "no-upstream\n"
    return 0
  fi

  local _dirty=0
  [[ -n "$(git -C "${_path}" status --porcelain 2>/dev/null)" ]] && _dirty=1

  local _counts _ahead _behind
  _counts="$(git -C "${_path}" rev-list --left-right --count 'HEAD...@{u}' 2>/dev/null)"
  _ahead="$(printf '%s' "${_counts}" | awk '{print $1}')"
  _behind="$(printf '%s' "${_counts}" | awk '{print $2}')"

  printf "dirty=%d ahead=%d behind=%d\n" "${_dirty}" "${_ahead:-0}" "${_behind:-0}"
}

_git_sync_one_repo() {
  local _path="$1"
  local _status
  _status="$(_git_repo_status "${_path}")"

  case "${_status}" in
    missing)
      return 0
      ;;
    unreachable)
      log_warn "${_path}: remote unreachable, skipping"
      return 1
      ;;
    no-upstream)
      log_warn "${_path}: no upstream configured, skipping"
      return 1
      ;;
    dirty=*)
      local _dirty _ahead _behind
      _dirty="$(printf '%s' "${_status}" | grep -oE 'dirty=[0-9]+' | cut -d= -f2)"
      _ahead="$(printf '%s' "${_status}" | grep -oE 'ahead=[0-9]+' | cut -d= -f2)"
      _behind="$(printf '%s' "${_status}" | grep -oE 'behind=[0-9]+' | cut -d= -f2)"

      if [[ ${_ahead} -gt 0 && ${_behind} -gt 0 ]]; then
        log_warn "${_path}: diverged (ahead ${_ahead}, behind ${_behind}), skipping — manual rebase/merge required"
        return 1
      fi
      if [[ ${_ahead} -gt 0 ]]; then
        if GIT_SSH_COMMAND="$(_git_ssh_opts)" git -C "${_path}" push --quiet; then
          return 0
        fi
        log_warn "${_path}: push failed"
        return 1
      fi
      if [[ ${_behind} -gt 0 ]]; then
        if [[ ${_dirty} -eq 1 ]]; then
          log_warn "${_path}: dirty tree, behind — skipping pull (unsafe)"
          return 1
        fi
        if GIT_SSH_COMMAND="$(_git_ssh_opts)" git -C "${_path}" pull --ff-only --quiet; then
          return 0
        fi
        log_warn "${_path}: pull failed"
        return 1
      fi
      return 0
      ;;
    *)
      log_warn "${_path}: unexpected status '${_status}'"
      return 1
      ;;
  esac
}

[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0
