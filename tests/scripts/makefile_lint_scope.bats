#!/usr/bin/env bats
#
# Verifies the Makefile's own ZSH_FILES/SHELL_FILES variables, not a
# re-derivation of the pathspec in the test — see the two `_make_print`
# helper vs. `_git_ls_clean` helper split below and the CLAUDE.md task
# writeup for why the completeness check must use an independently-derived
# regex rather than the same pathspec the Makefile uses.

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  # tests/mocks/git and tests/mocks/make would otherwise shadow the real
  # binaries this suite needs to invoke for real (shell.md PATH-mock
  # shadowing pitfall) -- strip the mocks dir from PATH for every call below.
  CLEAN_PATH="$(printf "%s" "${PATH}" | tr ':' '\n' | grep -v "tests/mocks" | tr '\n' ':' | sed 's/:$//')"
}

# Reads a Makefile-derived variable through the Makefile's own `print-%`
# target, with the git-repo-location env vars stripped (ci.md: a worktree
# push leaks GIT_DIR into hooks, which would otherwise make git resolve
# against the wrong repo for this parse-time assignment).
_make_print() {
  env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE \
    PATH="${CLEAN_PATH}" make -C "${REPO_ROOT}" "print-${1}"
}

_git_ls_clean() {
  env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE \
    PATH="${CLEAN_PATH}" git -C "${REPO_ROOT}" ls-files "$@"
}

_sorted_lines_from_space_list() {
  printf '%s\n' "${1}" | tr ' ' '\n' | sort -u
}

@test "ZSH_FILES equals git ls-files over the zsh pathspecs, as a set" {
  run _make_print ZSH_FILES
  [ "${status}" -eq 0 ]
  resolved="$(_sorted_lines_from_space_list "${output}")"
  expected="$(_git_ls_clean '*.zsh' '*.zsh-theme' '.zshrc' '.zprofile' | sort -u)"
  [ "${resolved}" = "${expected}" ]
}

@test "every tracked zsh-shaped file, independently derived, is present in ZSH_FILES" {
  run _make_print ZSH_FILES
  [ "${status}" -eq 0 ]
  resolved="$(_sorted_lines_from_space_list "${output}")"

  # Deliberately NOT the Makefile's own pathspec -- a broad-net regex over
  # the full tracked set, so a wrong/narrow Makefile pathspec (as happened
  # twice already: bruce.zsh-theme, then .zprofile) is caught rather than
  # rubber-stamped by a second copy of the same glob.
  broad="$(_git_ls_clean | grep -E '\.zsh(-theme)?$|(^|/)\.z[a-z]+$')"
  [ -n "${broad}" ]

  missing=""
  while IFS= read -r f; do
    [ -z "${f}" ] && continue
    printf '%s\n' "${resolved}" | grep -qxF "${f}" || missing="${missing}${f}\n"
  done <<< "${broad}"

  if [ -n "${missing}" ]; then
    printf 'missing from ZSH_FILES:\n%b' "${missing}" >&2
  fi
  [ -z "${missing}" ]
}

@test "SHELL_FILES and ZSH_FILES are disjoint" {
  run _make_print SHELL_FILES
  [ "${status}" -eq 0 ]
  shell_files="$(_sorted_lines_from_space_list "${output}")"

  run _make_print ZSH_FILES
  [ "${status}" -eq 0 ]
  zsh_files="$(_sorted_lines_from_space_list "${output}")"

  overlap="$(comm -12 <(printf '%s\n' "${shell_files}") <(printf '%s\n' "${zsh_files}"))"
  [ -z "${overlap}" ]
}

@test "SHELL_FILES and ZSH_FILES are both non-empty" {
  run _make_print SHELL_FILES
  [ "${status}" -eq 0 ]
  [ -n "${output}" ]

  run _make_print ZSH_FILES
  [ "${status}" -eq 0 ]
  [ -n "${output}" ]
}
