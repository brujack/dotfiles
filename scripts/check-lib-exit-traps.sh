#!/usr/bin/env bash
# Ratchets every `trap ... EXIT` declared in lib/*.sh against a reasoned
# allowlist embedded below.
#
# Why an allowlist and not an inference: after Task 1 on this branch deleted
# `trap 'unset _DOTFILES_RUN_TMPDIR' EXIT INT TERM` from
# `_dotfiles_run_tmpdir_setup` (it silently replaced bats' own EXIT trap,
# breaking failure reporting at 41 test sites -- see
# tests/setup_env/run_tmpdir_traps.bats), the only textual difference
# between that regression and lib/developer.sh's legitimate
# subshell-scoped trap is indentation: both read `trap '...' EXIT` inside a
# function. Deciding subshell containment from text needs a real bash
# parser this repo does not have, and approximating it by brace/indent
# position was proposed and withdrawn during planning for exactly that
# reason -- an approximation is worse than no inference, because it reads
# as safety while quietly missing the next non-subshell trap. So: enumerate
# every EXIT trap, compare the per-file count against an allowlist a human
# maintains, and let a new one fail until it is added with a reason. This
# script deliberately does NOT parse subshells, braces, or indentation --
# tests/scripts/check_lib_exit_traps.bats pins that a trap inside a ( )
# subshell is still counted, so a later "improvement" that starts inferring
# containment fails that test rather than silently re-arming the class.
#
# Scope is `git ls-files 'lib/*.sh'` from the repo root, stripped of a
# leaked GIT_DIR the same way scripts/list-shell-files.sh is (ci.md: git -C
# does not override an exported GIT_DIR, and scripts/pre-push runs
# `make test`, so a push from a worktree would otherwise resolve scope
# against the wrong repository).
#
# _OVERRIDE_LIB_TRAP_SCOPE points scope at an alternate root instead, so the
# bats suite can drive every verdict against a fixture without ever
# mutating real lib/. The override root's own lib/ subdirectory is globbed
# the same way `git ls-files 'lib/*.sh'` would list the real one, which is
# what lets a fixture file named lib/developer.sh land on the real allowlist
# key below without a second seam for the allowlist itself.

set -o pipefail

# Keyed on relative path ("lib/<file>.sh") plus the expected trap count --
# never on line numbers, which move on every edit unrelated to the trap
# itself. A file with no entry here is expected to carry zero EXIT traps.
declare -A _LIB_TRAP_ALLOWLIST=(
  ["lib/developer.sh"]="1"
)
declare -A _LIB_TRAP_ALLOWLIST_REASON=(
  ["lib/developer.sh"]="subshell-scoped gpg homedir cleanup, see the header comment above _aws_verify_zip"
)

# Resolves the directory scope is computed relative to: the override root
# under test, or the real repo root.
_lib_trap_base_dir() {
  if [[ -n "${_OVERRIDE_LIB_TRAP_SCOPE:-}" ]]; then
    printf '%s\n' "${_OVERRIDE_LIB_TRAP_SCOPE}"
    return 0
  fi
  env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE \
    git rev-parse --show-toplevel 2>/dev/null
}

# Emits "lib/<file>.sh"-style relative paths, one per line, sorted. Under
# the override seam this is a plain glob (the fixture need not be a git
# repo at all); in the real repo it is the tracked set, exactly like
# scripts/list-shell-files.sh's BATS_FILES derivation.
_lib_trap_scope() {
  local _base="$1"
  if [[ -n "${_OVERRIDE_LIB_TRAP_SCOPE:-}" ]]; then
    local _f
    for _f in "${_base}"/lib/*.sh; do
      [[ -e "${_f}" ]] || continue
      printf 'lib/%s\n' "$(basename "${_f}")"
    done | sort
    return 0
  fi
  (cd "${_base}" 2>/dev/null && env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE \
     git ls-files 'lib/*.sh') | sort
}

# Counts `trap` statements that fire on exit, excluding prose ABOUT one.
#
# Two stages, because one regex cannot do both jobs. Stage one drops
# whole-line comments -- that is what keeps lib/developer.sh's own header
# ("... with an EXIT trap -- NOT ...") out of the count. Stage two matches
# `trap` as a word anywhere on the surviving line, NOT anchored to line
# start: `[[ -n "${d}" ]] && trap 'x' EXIT` and `if ...; then trap 'x'
# EXIT; fi` are both real installs, and an earlier revision of this script
# missed both. Its header asserted "a real statement always starts the
# line with the word `trap`", which is true of today's lib/ and false in
# general -- a limitation stated as a fact, which stops the next reader
# checking.
#
# `0` is matched as well as `EXIT` because signal 0 IS EXIT in POSIX and
# bash -- verified: `trap 'echo X' 0` fires at exit. Without it the exact
# regression this ratchet exists to prevent, written `trap '...' 0 2 15`,
# passes with no allowlist edit. The `[[:space:]]0([[:space:]]|$)` form
# requires 0 to be a standalone token so `trap 'echo 0' INT` does not
# match; verified against both, on BSD and GNU grep.
#
# Known and accepted: a trailing comment containing the words trap and
# EXIT after real code counts, and `trap - EXIT` (which CLEARS a trap)
# counts as one. Both are loud -- they make the gate fire and a human
# resolves it via the allowlist. That is the right direction for a
# ratchet; a miss is silent, a false match is not.
_lib_trap_count() {
  local _file="$1" _n
  _n=$(grep -vE '^[[:space:]]*#' "${_file}" 2>/dev/null \
    | grep -cE '(^|[^[:alnum:]_])trap[[:space:]]+.*(\bEXIT\b|[[:space:]]0([[:space:]]|$))')
  printf '%s\n' "${_n:-0}"
}

main() {
  local _base
  _base="$(_lib_trap_base_dir)"
  if [[ -z "${_base}" ]]; then
    printf 'check-lib-exit-traps: could not resolve a scope base directory\n' >&2
    return 2
  fi

  local _files
  _files="$(_lib_trap_scope "${_base}")"
  if [[ -z "${_files}" ]]; then
    printf 'check-lib-exit-traps: derived scope is EMPTY -- refusing to report a pass having scanned nothing.\n' >&2
    return 2
  fi

  local _failed=0 _rel _count _expected _reason _scanned=0
  while IFS= read -r _rel; do
    [[ -n "${_rel}" ]] || continue
    _scanned=$((_scanned + 1))
    _count="$(_lib_trap_count "${_base}/${_rel}")"
    _expected="${_LIB_TRAP_ALLOWLIST[${_rel}]:-0}"
    if [[ "${_count}" != "${_expected}" ]]; then
      _reason="${_LIB_TRAP_ALLOWLIST_REASON[${_rel}]:-<no allowlist entry>}"
      printf 'check-lib-exit-traps: %s %s (expected %s, allowlist: %s)\n' \
        "${_rel}" "${_count}" "${_expected}" "${_reason}" >&2
      _failed=1
    fi
  done <<< "${_files}"

  if [[ "${_failed}" -eq 0 ]]; then
    printf 'check-lib-exit-traps: OK (%s files, allowlist honored)\n' "${_scanned}"
  fi
  return "${_failed}"
}

[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0
main "$@"
