#!/usr/bin/env bash
# lib/git_hooks.sh — discover personal repos carrying an install-hooks target

# HOOK_EXPECTED_REPOS is normally provided by config/hook_repos.sh (same
# sourcing chain as detect_env.sh's config/profiles.sh). Define an empty
# fallback only when that file is not present so this file remains
# self-contained when sourced standalone (e.g. by tests/setup_env/git_hooks.bats),
# following the same technique lib/git_sync.sh uses for _git_ssh_opts.
if [[ -f "$(dirname "${BASH_SOURCE[0]}")/../config/hook_repos.sh" ]]; then
  # shellcheck disable=SC1091
  source "$(dirname "${BASH_SOURCE[0]}")/../config/hook_repos.sh"
else
  HOOK_EXPECTED_REPOS=()
fi

_git_hooks_discover() {
  local _dir
  for _dir in "${PERSONAL_GITREPOS}"/*/; do
    # -d not -e: a worktree/submodule .git is a FILE — skip those (hooks
    # live in the common dir), and stop rev-parse walking up into an
    # ancestor repo.
    [[ -d "${_dir}.git" ]] || continue
    git -C "${_dir}" rev-parse --git-dir >/dev/null 2>&1 || continue
    [[ -f "${_dir}Makefile" ]] || continue
    grep -q '^install-hooks:' "${_dir}Makefile" || continue
    printf '%s\n' "${_dir}"
  done
}

_git_hooks_digest() {
  local _repo_dir="$1"
  local _hooks_dir

  # rev-parse --git-path hooks is empty when _repo_dir is not a git repo at
  # all (defensive; _git_hooks_discover output is always a real repo).
  _hooks_dir="$(git -C "${_repo_dir}" rev-parse --git-path hooks 2>/dev/null)"
  if [[ -z "${_hooks_dir}" ]]; then
    printf 'no-hooks-dir\n'
    return 0
  fi

  # git-path can return a path relative to the repo dir (the common case) —
  # resolve it before testing/reading it.
  case "${_hooks_dir}" in
    /*) : ;;
    *) _hooks_dir="${_repo_dir%/}/${_hooks_dir}" ;;
  esac

  if [[ ! -d "${_hooks_dir}" ]]; then
    printf 'no-hooks-dir\n'
    return 0
  fi

  printf 'no-hooks-dir\n'
  return 0
}

[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0
