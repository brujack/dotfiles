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
  readonly HOOK_EXPECTED_REPOS=()
fi

_git_hooks_discover() {
  local _dir
  for _dir in "${PERSONAL_GITREPOS}"/*/; do
    [[ -d "${_dir}.git" ]] || continue
    git -C "${_dir}" rev-parse --git-dir >/dev/null 2>&1 || continue
    printf '%s\n' "${_dir}"
  done
}

[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0
