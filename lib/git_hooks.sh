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

# _GIT_HOOKS_MANDATED is the uniform hook set every personal repo must
# carry per repo-structure.md: pre-commit (ggshield secret scan),
# pre-push (the permanent local test gate), and commit-msg (Conventional
# Commits). Immutable AND re-source-safe: readonly guards against
# accidental mutation, and the emptiness check guards against the
# readonly declaration itself aborting a second source of this file in
# the same shell (see the "sourcing lib/git_hooks.sh twice" test) — the
# same pattern the HOOK_EXPECTED_REPOS source block above would need if
# it were readonly.
if [[ -z "${_GIT_HOOKS_MANDATED+x}" ]]; then
  readonly _GIT_HOOKS_MANDATED=(pre-commit pre-push commit-msg)
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
    # Not a correctness guard: grep already exits 2 on a missing file, so
    # `|| continue` would exclude the repo without it. It exists to suppress
    # grep's "No such file or directory" on stderr, which would otherwise
    # print once per Makefile-less repo on every weekly `-t update`.
    [[ -f "${_dir}Makefile" ]] || continue
    grep -q '^install-hooks:' "${_dir}Makefile" || continue
    printf '%s\n' "${_dir}"
  done
}

# _git_hooks_dir resolves REPO_DIR's installed hooks directory. Contract:
# prints the resolved absolute path and returns 0 when the directory
# exists; prints nothing and returns 1 when REPO_DIR is not a git repo at
# all, or its hooks directory does not exist. Shared by _git_hooks_digest
# and _git_hooks_check_complete so the GIT_DIR-leak guard and the
# relative-vs-absolute path handling exist in exactly one place.
_git_hooks_dir() {
  local _repo_dir="$1"
  local _hooks_dir

  # rev-parse --git-path hooks is empty when _repo_dir is not a git repo at
  # all (reachable: callers may pass a listed repo path that is not a git
  # repo at all -- see the plain-non-git-directory test -- this is not a
  # defensive-only branch). An inherited
  # GIT_DIR (or GIT_WORK_TREE/GIT_COMMON_DIR/GIT_INDEX_FILE) overrides -C
  # entirely, silently redirecting this at a different repo's hooks dir —
  # git-workflow.md documents that git exports GIT_DIR into the pre-push
  # hook environment when pushed from a worktree, and this repo's pre-push
  # hook runs `make test`, which sources this file.
  _hooks_dir="$(env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE \
    git -C "${_repo_dir}" rev-parse --git-path hooks 2>/dev/null)"
  if [[ -z "${_hooks_dir}" ]]; then
    return 1
  fi

  # git-path can return a path relative to the repo dir (the common case) —
  # resolve it before testing/reading it.
  case "${_hooks_dir}" in
    /*) : ;;
    *) _hooks_dir="${_repo_dir%/}/${_hooks_dir}" ;;
  esac

  if [[ ! -d "${_hooks_dir}" ]]; then
    return 1
  fi

  printf '%s\n' "${_hooks_dir}"
  return 0
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

  if ! _hooks_dir="$(_git_hooks_dir "${_repo_dir}")"; then
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

# _git_hooks_check_complete asserts each mandated hook exists and is
# executable in REPO_DIR's installed hooks directory — it never looks at
# scripts/. A hook that arrives by a route other than the Makefile (e.g.
# `ledger init` installing an executable .git/hooks/pre-commit with no
# scripts/pre-commit counterpart) must satisfy this check; a source-based
# check would report a false gap on state-ledger every week forever.
#
# Contract is tri-state, not binary:
#   exit 0 -- complete. No stdout output.
#   exit 1 -- incomplete, but the hooks directory exists. Prints the
#             missing hook names, space-separated, on ONE line of
#             stdout. `make install-hooks` can plausibly fix this.
#   exit 2 -- no hooks directory at all (mirrors _git_hooks_digest's
#             own no-hooks-dir marker). Prints the literal string
#             "no-hooks-dir" on stdout -- never a hook-name list.
#             `make install-hooks` cannot fix this: there is nowhere to
#             install into, and this repo's git infrastructure itself
#             is broken, not just its hook set.
# Callers (Task 4's sweep) must branch on the exit code, not merely
# check non-zero -- collapsing 1 and 2 into "incomplete" is exactly the
# bug this tri-state exists to prevent: a repair loop that only knows
# how to re-run install-hooks would retry forever against a repo whose
# hooks directory doesn't exist, and never escalate.
_git_hooks_check_complete() {
  local _repo_dir="$1"
  local _hooks_dir
  local _hook
  local -a _missing=()

  if ! _hooks_dir="$(_git_hooks_dir "${_repo_dir}")"; then
    printf 'no-hooks-dir\n'
    return 2
  fi

  for _hook in "${_GIT_HOOKS_MANDATED[@]}"; do
    [[ -x "${_hooks_dir}/${_hook}" ]] || _missing+=("${_hook}")
  done

  if [[ ${#_missing[@]} -eq 0 ]]; then
    return 0
  fi

  printf '%s\n' "${_missing[*]}"
  return 1
}

# _git_hooks_gap_repos prints bare names of repos on HOOK_EXPECTED_REPOS
# that exist under PERSONAL_GITREPOS as real git repos but carry no
# Makefile at all — the "infrastructure missing" gap condition described
# in the spec's Gaps section. Repos absent from the list are silent
# regardless of their filesystem shape. Always returns 0 (reporting only;
# never affects the sweep's return code).
_git_hooks_gap_repos() {
  local _name
  local _dir

  for _name in "${HOOK_EXPECTED_REPOS[@]}"; do
    _dir="${PERSONAL_GITREPOS}/${_name}"
    # -d not -e: a worktree/submodule .git is a FILE, not a directory --
    # same reason _git_hooks_discover excludes them. A listed name that
    # is only a linked worktree must not be reported as a gap.
    [[ -d "${_dir}/.git" ]] || continue
    # rev-parse, separately: -d .git alone still admits a partial or
    # interrupted clone (a real but empty/invalid .git directory). A
    # partial clone sitting on the expected-repos list is not evidence
    # of a real repo missing a Makefile, so it must not be reported as
    # a gap on the strength of a .git directory alone -- this is the
    # spec's own argument for why _git_hooks_discover needs both checks,
    # applied here too.
    env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE \
      git -C "${_dir}" rev-parse --git-dir >/dev/null 2>&1 || continue
    # Makefile present => discovery already handles this repo; not a gap.
    # (The only &&-guard in this file; the other five all use || continue
    # because their conditions are inverted -- this one isn't.)
    [[ -f "${_dir}/Makefile" ]] && continue
    printf '%s\n' "${_name}"
  done
  return 0
}

[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0
