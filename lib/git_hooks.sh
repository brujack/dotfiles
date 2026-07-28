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
    # An inherited GIT_DIR (or GIT_WORK_TREE/GIT_COMMON_DIR/GIT_INDEX_FILE)
    # overrides -C entirely, so rev-parse would report success for ANY
    # _dir as long as the leaked var happens to point at a real repo
    # elsewhere — silently defeating the partial-clone exclusion this
    # guard exists for. git-workflow.md documents that git exports GIT_DIR
    # into the pre-push hook environment when pushed from a worktree, and
    # this repo's pre-push hook runs `make test`, which sources this file.
    env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE \
      git -C "${_dir}" rev-parse --git-dir >/dev/null 2>&1 || continue
    [[ -f "${_dir}Makefile" ]] || continue
    grep -q '^install-hooks:' "${_dir}Makefile" || continue
    printf '%s\n' "${_dir}"
  done
}

# _git_hooks_digest prints a content-based digest of a repo's installed
# hooks directory. Contract: exit 0 with a 64-hex sha256 digest on stdout,
# exit 0 with the literal marker "no-hooks-dir" when the repo has no hooks
# directory, or exit 1 with the literal marker "digest-error" when a hook
# file's content could not be read. Callers (Task 4's sweep) must treat
# exit 1 as "cannot determine" and never compare its output as if it were
# a real digest.
_git_hooks_digest() {
  local _repo_dir="$1"
  local _hooks_dir

  # rev-parse --git-path hooks is empty when _repo_dir is not a git repo at
  # all (defensive; _git_hooks_discover output is always a real repo). See
  # the GIT_DIR comment in _git_hooks_discover above — the same leak would
  # silently redirect this function at a different repo's hooks dir.
  _hooks_dir="$(env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE \
    git -C "${_repo_dir}" rev-parse --git-path hooks 2>/dev/null)"
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

  # Hash inside the single glob loop rather than collecting names into an
  # array and re-sorting: bash pathname expansion already returns entries
  # in the same LC_COLLATE order `sort` would apply (verified identical
  # for the mandated hook names, so the extra pass was a no-op), and the
  # array/printf/sort/while-read round trip re-split any filename
  # containing a newline into bogus names whose shasum call then failed
  # silently. Fold the filename into the hashed material so a rename
  # (same bytes, different name) still changes the digest. -f follows
  # symlinks (stat-based test), so a symlinked hook is included and
  # hashed via its target's content — a broken symlink or a subdirectory
  # is excluded since -f is false for both.
  local _file _name _hash _combined=""
  for _file in "${_hooks_dir}"/*; do
    [[ -f "${_file}" ]] || continue
    _name="$(basename "${_file}")"
    # An unreadable file (e.g. mode 000) makes shasum fail and print
    # nothing on stdout; awk then hands back an empty string, which used
    # to fold into the digest as a bare "name:" and silently succeed —
    # two directories with completely different, both-unreadable content
    # then hashed identically. Validate the shape and fail closed instead.
    _hash="$(shasum -a 256 "${_file}" 2>/dev/null | awk '{print $1}')"
    if [[ ! ${_hash} =~ ^[0-9a-f]{64}$ ]]; then
      printf 'digest-error\n'
      return 1
    fi
    _combined+="${_name}:${_hash}"$'\n'
  done

  printf '%s' "${_combined}" | shasum -a 256 | awk '{print $1}'
  return 0
}

[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0
