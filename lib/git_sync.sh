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

[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0
