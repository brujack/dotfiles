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
  # Test isolation (tdd.md pitfall A): _make_print deliberately does NOT
  # strip these (see below) so the leaked-GIT_DIR test can prove the
  # Makefile's own env -u matters. Start every test from a known-clean
  # ambient state so an unrelated leak from whatever invoked bats can't
  # change what a "no GIT_DIR set" test observes.
  unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE
}

# Reads a Makefile-derived variable through the Makefile's own `print-%`
# target. Deliberately does NOT strip GIT_DIR/GIT_WORK_TREE/GIT_COMMON_DIR/
# GIT_INDEX_FILE -- doing so would test the harness's own stripping instead
# of the Makefile's. The Makefile's `ZSH_FILES :=`/`SHELL_FILES :=`
# assignments carry their own `env -u ...` prefix (ci.md: GIT_DIR leaks into
# the pre-push hook from a worktree push) and that prefix is what must be
# proven to work -- see the "survives a leaked GIT_DIR" test below.
# --no-print-directory is load-bearing, not tidiness. GNU Make >= 4.0 emits
# "Entering directory"/"Leaving directory" on stdout whenever -C changes the
# working directory; 3.81 (which Apple still ships) does not. Without the flag
# those two lines are parsed as filenames, so the resolved set gains the same
# junk tokens for EVERY variable -- which makes the disjointness assertion below
# fail while the superset assertion still passes. Measured: 1 line of output
# under make 3.81, 3 lines under gmake 4.4.1, for the identical command.
_make_print() {
  PATH="${CLEAN_PATH}" make --no-print-directory -C "${REPO_ROOT}" "print-${1}"
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
  if [ "${resolved}" != "${expected}" ]; then
    printf 'ZSH_FILES resolved:\n%s\n--- expected:\n%s\n' "${resolved}" "${expected}" >&2
  fi
  [ "${resolved}" = "${expected}" ]
}

@test "every tracked zsh file, independently derived by name OR shebang, is present in ZSH_FILES" {
  run _make_print ZSH_FILES
  [ "${status}" -eq 0 ]
  resolved="$(_sorted_lines_from_space_list "${output}")"

  # Filename arm: broad regex, deliberately NOT the Makefile's own pathspec
  # -- so a wrong/narrow Makefile pathspec (as happened twice already:
  # bruce.zsh-theme, then .zprofile) is caught rather than rubber-stamped by
  # a second copy of the same glob.
  by_name="$(_git_ls_clean | grep -E '\.zsh(-theme)?$|(^|/)\.z[a-z]+$' || true)"

  # Shebang arm: content-derived, orthogonal to any filename rule -- catches
  # a zsh script whose name is not zsh-shaped at all (this repo already
  # carries extensionless hook scripts for bash: scripts/pre-push,
  # scripts/commit-msg). Piped straight from `ls-files -z` into `xargs -0`,
  # never through `$(...)`, because command substitution silently drops the
  # NUL delimiters (shell.md).
  by_shebang="$(_git_ls_clean -z | xargs -0 grep -l '^#!.*[/ ]zsh' 2>/dev/null || true)"

  # Union, not either arm alone: .zshrc has no shebang, so the shebang arm
  # by itself would miss it -- the same lesson in the other direction from
  # the filename arm missing an extensionless script.
  broad="$(printf '%s\n%s\n' "${by_name}" "${by_shebang}" | grep -v '^$' | sort -u)"
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
  if [ -n "${overlap}" ]; then
    printf 'SHELL_FILES/ZSH_FILES overlap:\n%s\n' "${overlap}" >&2
  fi
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

@test "make print-ZSH_FILES survives a leaked GIT_DIR pointed at a decoy repo" {
  decoy="${BATS_TEST_TMPDIR}/decoy"
  mkdir -p "${decoy}"
  PATH="${CLEAN_PATH}" git -C "${decoy}" init --quiet
  PATH="${CLEAN_PATH}" git -C "${decoy}" config user.email "test@test.com"
  PATH="${CLEAN_PATH}" git -C "${decoy}" config user.name "Test"
  printf 'echo hi\n' > "${decoy}/a.zsh"
  PATH="${CLEAN_PATH}" git -C "${decoy}" add a.zsh
  PATH="${CLEAN_PATH}" git -C "${decoy}" commit --quiet -m "decoy"

  # A leaked GIT_DIR is exactly what the Makefile's `env -u GIT_DIR ...`
  # prefix exists to survive (ci.md: git exports GIT_DIR into the pre-push
  # hook when the push originates from a worktree). If that prefix is
  # deleted from the ZSH_FILES assignment, `git ls-files` here resolves
  # against the decoy repo's single a.zsh instead of the real repo's ten --
  # shell.md: `-C` does not override an exported GIT_DIR.
  run env GIT_DIR="${decoy}/.git" PATH="${CLEAN_PATH}" make -C "${REPO_ROOT}" print-ZSH_FILES
  [ "${status}" -eq 0 ]
  resolved="$(_sorted_lines_from_space_list "${output}")"
  expected="$(_git_ls_clean '*.zsh' '*.zsh-theme' '.zshrc' '.zprofile' | sort -u)"
  [ "${resolved}" = "${expected}" ]
}

@test "make -n lint dry-run wires zsh -n to ZSH_FILES, not SHELL_FILES" {
  run env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE \
    bash -c "PATH='${CLEAN_PATH}' make -C '${REPO_ROOT}' -n lint"
  [ "${status}" -eq 0 ]

  count="$(printf '%s\n' "${output}" | grep -c 'zsh  -n')"
  [ "${count}" -eq 1 ]

  # The line immediately before `zsh  -n ...` is the `for` loop it lives
  # inside. It must be fed by ZSH_FILES -- bruce.zsh-theme is a name
  # SHELL_FILES's *.sh/*.bash/hook pathspec can never match -- and must NOT
  # be fed by SHELL_FILES -- lib/constants.sh is a bash file that must not
  # appear in a zsh -n loop.
  for_line="$(printf '%s\n' "${output}" | grep -B1 'zsh  -n' | head -1)"
  [[ "${for_line}" == *"bruce.zsh-theme"* ]]
  [[ "${for_line}" != *"lib/constants.sh"* ]]
}
