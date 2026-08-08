#!/usr/bin/env bats
#
# make lint's file list is derived from `git ls-files`, which means it inherits
# git's environment. git exports GIT_DIR into the pre-push hook when the push
# originates from a worktree, and `make lint` runs from that hook via
# `test: lint` — so a leaked GIT_DIR would silently resolve the list against a
# different repository. `ci.md` records the same failure for a parse-time
# HOOKS_DIR assignment, where an `unexport` block eleven lines above did not
# cover it: `unexport` governs recipe subshells, and a `:=` assignment runs in
# make's own process before any recipe exists.
#
# These tests exercise the real Makefile, not a fixture reproducing it. A test
# that greps the Makefile for `env -u` passes whether or not the prefix works,
# and a test that rebuilds the recipe in a temp file passes even after the real
# one is broken.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  DECOY="${BATS_TEST_TMPDIR}/decoy"
  mkdir -p "${DECOY}"
  git -C "${DECOY}" init -q
  printf '#!/usr/bin/env bash\ntrue\n' > "${DECOY}/only_in_decoy.sh"
  git -C "${DECOY}" add -A
  git -C "${DECOY}" -c user.email=t@example.com -c user.name=t commit -qm "decoy"
}

@test "SHELL_FILES resolves against this repo even with GIT_DIR leaked" {
  run env GIT_DIR="${DECOY}/.git" make -C "${REPO_ROOT}" -n lint
  [ "$status" -eq 0 ]
  # A file that exists only here — proves the real repo was read.
  [[ "$output" == *"setup_env.sh"* ]]
  # A file that exists only in the decoy — proves the leak was not followed.
  [[ "$output" != *"only_in_decoy.sh"* ]]
}

@test "SHELL_FILES resolves against this repo even with GIT_INDEX_FILE leaked" {
  run env GIT_INDEX_FILE="${DECOY}/.git/index" make -C "${REPO_ROOT}" -n lint
  [ "$status" -eq 0 ]
  [[ "$output" == *"setup_env.sh"* ]]
  [[ "$output" != *"only_in_decoy.sh"* ]]
}

# Only GIT_DIR and GIT_INDEX_FILE are tested above, and that is deliberate:
# measured 2026-08-08 against this repo, they are the only two of the four
# stripped variables that redirect `git ls-files` at all. Pointed at a decoy
# repo, each reduces the result from 33 tracked .sh files to 1 (the decoy's).
# GIT_WORK_TREE and GIT_COMMON_DIR leave the result unchanged at 33, because
# ls-files reads the index rather than walking the work tree — so a test
# leaking either of them passes whether or not `env -u` is present, which is
# the definition of a test that cannot fail. They stay in the strip list as
# defence against wrapper scripts and IDEs that set them, per shell.md, but
# they are not assertable through this surface and pretending otherwise would
# put two green tests in this file that prove nothing.
#
# The pairing is not a coincidence: shell.md's measured table records that git
# exports exactly GIT_DIR into pre-push and GIT_INDEX_FILE into pre-commit.
# The two variables that can break this Makefile are the two git actually sets.

@test "SHELL_FILES covers the extensionless hooks that gate every commit" {
  run make -C "${REPO_ROOT}" -n lint
  [ "$status" -eq 0 ]
  # These have no extension, so the previous find -name '*.sh' scope missed
  # them entirely — the two scripts that gate every commit and push.
  [[ "$output" == *"scripts/pre-push"* ]]
  [[ "$output" == *"scripts/commit-msg"* ]]
}

@test "SHELL_FILES excludes untracked files" {
  local _scratch="${REPO_ROOT}/zz_untracked_scratch.sh"
  printf '#!/usr/bin/env bash\ntrue\n' > "${_scratch}"
  run make -C "${REPO_ROOT}" -n lint
  rm -f "${_scratch}"
  [ "$status" -eq 0 ]
  # find would have linted this; git ls-files does not. That difference is why
  # the scope moved — an untracked scratch file present locally and absent on
  # CI makes the same commit lint two different sets.
  [[ "$output" != *"zz_untracked_scratch.sh"* ]]
}
