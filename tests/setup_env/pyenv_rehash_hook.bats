#!/usr/bin/env bats

# Covers pyenv.d/rehash/dotfiles-register-all-executables.bash (sourced by
# real pyenv-rehash, in isolation via env -i + bash -c, following the
# tests/scripts/bash_tracer.bats pattern) and lib/helpers.sh's
# install_pyenv_rehash_hook (loaded via load_setup_env, called directly like
# install_terraform_skill's tests in install_functions.bats).
#
# See docs/superpowers/specs/2026-09-17-claude-provisioning-gaps-design.md,
# Part 1, for why the hook exists: uutils `sort -u` (Ubuntu 26.04) collates
# py.test and pytest as equal, so pyenv-versions --executables drops one and
# remove_stale_shims deletes the pytest shim. The hook re-registers the same
# globs without sort.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_setup_env
  load_mocks
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  HOME="${BATS_TEST_TMPDIR}/home"
  export HOME
  mkdir -p "${HOME}"
  HOOK_SRC="${REPO_ROOT}/pyenv.d/rehash/dotfiles-register-all-executables.bash"
  # load_setup_env's real detect_env() run has nothing to do with PYENV_ROOT,
  # but this developer session exports a real PYENV_ROOT (pyenv's own shell
  # integration), and install_pyenv_rehash_hook resolves
  # _OVERRIDE_PYENV_ROOT, then PYENV_ROOT, then HOME as its fallback chain.
  # Any installer test that forgets the override seam would otherwise write
  # into the operator's real ~/.pyenv (tdd.md E2).
  unset PYENV_ROOT
}

teardown() {
  rm -f "${MOCK_CALLS_FILE:-}"
}

# Builds a fixture PYENV_ROOT: versions/v/bin/{pytest,py.test,.dot} (the
# collision case plus a dotfile that only dotglob reaches) and
# versions/v/envs/e/bin/x (the venv-shim path), plus an empty versions/w/bin/.
# The empty leaf does NOT exercise nullglob on its own: versions/*/bin/*
# still matches via v/bin/*, so the pattern as a whole is never unmatched
# here — w/bin/ only proves an empty directory contributes nothing of its
# own. See _make_fixture_root_no_envs below for the fixture that actually
# forces nullglob on the second glob (no envs/ directory anywhere).
_make_fixture_root() {
  local _root="$1"
  mkdir -p "${_root}/versions/v/bin" "${_root}/versions/v/envs/e/bin" "${_root}/versions/w/bin"
  : > "${_root}/versions/v/bin/pytest"
  : > "${_root}/versions/v/bin/py.test"
  : > "${_root}/versions/v/bin/.dot"
  : > "${_root}/versions/v/envs/e/bin/x"
  chmod +x "${_root}/versions/v/bin/pytest" "${_root}/versions/v/bin/py.test"
  chmod +x "${_root}/versions/v/bin/.dot" "${_root}/versions/v/envs/e/bin/x"
}

# A populated bin/ with NO envs/ directory anywhere. versions/*/bin/* still
# matches (via v/bin/pytest), but versions/*/envs/*/bin/* matches nothing —
# this is the fixture that actually exercises nullglob on the second glob.
# Mutation-proven (dropping `nullglob` from the hook's `shopt -s` line):
# against _make_fixture_root above, the mutant still registers every shim
# with no literal `*` (v/bin AND v/envs both exist, so neither glob goes
# unmatched); against THIS fixture the mutant registers a literal
# ".../versions/*/envs/*/bin/*" line, which only this fixture can catch.
_make_fixture_root_no_envs() {
  local _root="$1"
  mkdir -p "${_root}/versions/v/bin"
  : > "${_root}/versions/v/bin/pytest"
  chmod +x "${_root}/versions/v/bin/pytest"
}

# ── hook: sourced directly, real caller shape (make_shims defined, then rehash sources hooks) ──

@test "hook registers pytest, py.test, the dotfile and the venv shim; never a literal *" {
  local _root="${BATS_TEST_TMPDIR}/pyenv_root"
  _make_fixture_root "${_root}"
  local _calls="${BATS_TEST_TMPDIR}/shim_calls"

  run env -i PATH="${PATH}" HOME="${HOME}" PYENV_ROOT="${_root}" bash -c "
    make_shims() { printf '%s\n' \"\$@\" >> '${_calls}'; }
    source '${HOOK_SRC}'
  "
  [ "$status" -eq 0 ]
  [ -f "${_calls}" ]

  local _content
  _content="$(cat "${_calls}")"
  [[ "${_content}" == *"${_root}/versions/v/bin/pytest"* ]]
  [[ "${_content}" == *"${_root}/versions/v/bin/py.test"* ]]
  [[ "${_content}" == *"${_root}/versions/v/bin/.dot"* ]]
  [[ "${_content}" == *"${_root}/versions/v/envs/e/bin/x"* ]]
  [[ "${_content}" != *'*'* ]]
}

# T2 fix: the fixture above has a populated bin/ AND envs/ under v/, so
# versions/*/envs/*/bin/* is never unmatched there and this test cannot
# discriminate a missing nullglob. Mutation-proven: dropping `nullglob` from
# the hook's `shopt -s nullglob dotglob` line left the test above green
# (every shim still registered, no literal * — verified in a scratch mktemp
# copy, never the worktree file), while THIS fixture's assertion goes red
# under the identical mutation, because its versions/*/envs/*/bin/* pattern
# has nothing to match.
@test "hook registers no literal * when no envs/ directory exists anywhere" {
  local _root="${BATS_TEST_TMPDIR}/pyenv_root_no_envs"
  _make_fixture_root_no_envs "${_root}"
  local _calls="${BATS_TEST_TMPDIR}/shim_calls_no_envs"

  run env -i PATH="${PATH}" HOME="${HOME}" PYENV_ROOT="${_root}" bash -c "
    make_shims() { printf '%s\n' \"\$@\" >> '${_calls}'; }
    source '${HOOK_SRC}'
  "
  [ "$status" -eq 0 ]
  [ -f "${_calls}" ]

  local _content
  _content="$(cat "${_calls}")"
  [[ "${_content}" == *"${_root}/versions/v/bin/pytest"* ]]
  [[ "${_content}" != *'*'* ]]
}

# RED case: `shopt -p nullglob dotglob` exits 1 when either named option is
# off (verified directly: both off -> rc 1), and pyenv-rehash sources hooks
# under `set -e`. Confirmed failing before the fix: with the `|| true` on
# the capture line removed, this test aborted mid-script (no "SURVIVED"
# line, rc 1) instead of reaching the assertions below. Restored `|| true`
# before committing.
@test "under set -e, with nullglob and dotglob OFF at entry, sourcing survives and restores both OFF" {
  local _root="${BATS_TEST_TMPDIR}/pyenv_root"
  _make_fixture_root "${_root}"

  run env -i PATH="${PATH}" HOME="${HOME}" PYENV_ROOT="${_root}" bash -c "
    set -e
    shopt -u nullglob dotglob
    make_shims() { :; }
    source '${HOOK_SRC}'
    echo SURVIVED
    shopt -q nullglob && echo NULLGLOB_ON || echo NULLGLOB_OFF
    shopt -q dotglob && echo DOTGLOB_ON || echo DOTGLOB_OFF
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"SURVIVED"* ]]
  [[ "$output" == *"NULLGLOB_OFF"* ]]
  [[ "$output" == *"DOTGLOB_OFF"* ]]
}

@test "with nullglob and dotglob ON at entry, sourcing restores both ON" {
  local _root="${BATS_TEST_TMPDIR}/pyenv_root"
  _make_fixture_root "${_root}"

  run env -i PATH="${PATH}" HOME="${HOME}" PYENV_ROOT="${_root}" bash -c "
    set -e
    shopt -s nullglob dotglob
    make_shims() { :; }
    source '${HOOK_SRC}'
    echo SURVIVED
    shopt -q nullglob && echo NULLGLOB_ON || echo NULLGLOB_OFF
    shopt -q dotglob && echo DOTGLOB_ON || echo DOTGLOB_OFF
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"SURVIVED"* ]]
  [[ "$output" == *"NULLGLOB_ON"* ]]
  [[ "$output" == *"DOTGLOB_ON"* ]]
}

# T3 fix: the previous version of this test set no `set -e`, so `source`
# returns the status of its LAST command regardless of what failed partway
# through — deleting the hook's `declare -f make_shims > /dev/null ||
# return 0` guard line left this test green (status 0, "SOURCED_OK"
# printed) even though `make_shims: command not found` fired on the way.
# Mutation-proven in a scratch mktemp copy (never the worktree file): the
# old test body reported rc=0 against that mutant; this body, with `set -e`
# added and the shopt state checked before/after, reports rc=127 and never
# reaches "SOURCED_OK" — the guard is now falsifiable by shell state, not
# just by the calls file (which nothing in this test could ever populate,
# since no make_shims stub is defined).
@test "with make_shims undefined, sourcing returns 0 before touching shell state" {
  local _root="${BATS_TEST_TMPDIR}/pyenv_root"
  _make_fixture_root "${_root}"

  run env -i PATH="${PATH}" HOME="${HOME}" PYENV_ROOT="${_root}" bash -c "
    set -e
    shopt -u nullglob dotglob
    source '${HOOK_SRC}'
    echo SOURCED_OK
    shopt -q nullglob && echo NULLGLOB_ON || echo NULLGLOB_OFF
    shopt -q dotglob && echo DOTGLOB_ON || echo DOTGLOB_OFF
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"SOURCED_OK"* ]]
  [[ "$output" == *"NULLGLOB_OFF"* ]]
  [[ "$output" == *"DOTGLOB_OFF"* ]]
}

# ── installer: install_pyenv_rehash_hook, loaded via load_setup_env ──

@test "install_pyenv_rehash_hook is a no-op when versions/ does not exist" {
  local _root="${BATS_TEST_TMPDIR}/pyenv_root"
  mkdir -p "${_root}"
  export _OVERRIDE_PYENV_ROOT="${_root}"

  run install_pyenv_rehash_hook
  [ "$status" -eq 0 ]
  [ ! -d "${_root}/pyenv.d" ]
}

@test "install_pyenv_rehash_hook copies the hook as a regular file, never a symlink" {
  local _root="${BATS_TEST_TMPDIR}/pyenv_root"
  mkdir -p "${_root}/versions"
  export _OVERRIDE_PYENV_ROOT="${_root}"

  run install_pyenv_rehash_hook
  [ "$status" -eq 0 ]

  local _dst="${_root}/pyenv.d/rehash/dotfiles-register-all-executables.bash"
  [ -f "${_dst}" ]
  [ ! -L "${_dst}" ]
  cmp -s "${REPO_ROOT}/pyenv.d/rehash/dotfiles-register-all-executables.bash" "${_dst}"
}

# T4 fix: tests/mocks/sleep is a no-op stub that logs and exits immediately
# (load_mocks puts tests/mocks/ ahead of PATH), so `sleep 1` here never
# separates the two installs in wall-clock time and a second-resolution
# `stat` mtime comparison could not discriminate the cmp-skip branch either
# way. Mutation-proven in a scratch copy (never the worktree file): deleting
# the `if [[ -f ]] && cmp -s ... return 0` branch left mtimes equal under
# the OLD sleep-based body just as often as the unmutated code did, because
# both installs still land in the same wall-clock second regardless of
# whether a rewrite happened. Pinning an old mtime with `touch -t` instead
# removes the race: the mutant unconditionally re-runs `install`, which
# always sets a current mtime, so `_mtime_before` (pinned to 2020) can never
# equal `_mtime_after` under the mutant, while the unmutated code's early
# `return 0` never touches the file at all and the pinned mtime survives.
@test "install_pyenv_rehash_hook does not rewrite an already-current copy" {
  local _root="${BATS_TEST_TMPDIR}/pyenv_root"
  mkdir -p "${_root}/versions"
  export _OVERRIDE_PYENV_ROOT="${_root}"

  run install_pyenv_rehash_hook
  [ "$status" -eq 0 ]
  local _dst="${_root}/pyenv.d/rehash/dotfiles-register-all-executables.bash"
  [ -f "${_dst}" ]

  touch -t 202001010000 "${_dst}"
  local _mtime_before
  _mtime_before=$(stat -f '%m' "${_dst}" 2>/dev/null || stat -c '%Y' "${_dst}")

  run install_pyenv_rehash_hook
  [ "$status" -eq 0 ]

  local _mtime_after
  _mtime_after=$(stat -f '%m' "${_dst}" 2>/dev/null || stat -c '%Y' "${_dst}")
  [ "${_mtime_before}" = "${_mtime_after}" ]
}

@test "install_pyenv_rehash_hook re-copies a changed destination" {
  local _root="${BATS_TEST_TMPDIR}/pyenv_root"
  mkdir -p "${_root}/versions"
  export _OVERRIDE_PYENV_ROOT="${_root}"

  run install_pyenv_rehash_hook
  [ "$status" -eq 0 ]
  local _dst="${_root}/pyenv.d/rehash/dotfiles-register-all-executables.bash"
  [ -f "${_dst}" ]

  printf 'stale content\n' > "${_dst}"
  # A bare `!` only fails a bats test as the LAST command in the body
  # (SC2314; see refute_grep's doc comment in tests/helpers/common.bash) —
  # `run` + status assertion is required here since more assertions follow.
  run cmp -s "${REPO_ROOT}/pyenv.d/rehash/dotfiles-register-all-executables.bash" "${_dst}"
  [ "$status" -ne 0 ]

  run install_pyenv_rehash_hook
  [ "$status" -eq 0 ]
  cmp -s "${REPO_ROOT}/pyenv.d/rehash/dotfiles-register-all-executables.bash" "${_dst}"
}

# ── installer error paths (T5, review findings P1-P3) ──

# P2: with DOTFILES_REPO_ROOT unset, _src resolves to
# "/pyenv.d/rehash/dotfiles-register-all-executables.bash" (leading slash,
# from the empty expansion), which does not exist. Isolated via env -i,
# sourcing lib/helpers.sh directly rather than through load_setup_env/
# setup_env.sh, because DOTFILES_REPO_ROOT is `readonly` once constants.sh
# has run in this bats process and cannot be unset for a single test.
# Mutation-proven: without the `[[ -f "${_src}" ]] || return 1` guard,
# `install -m 0644 "" "${_dst}"` fails with install's own stderr and a
# non-obvious message rather than a clean rc=1 from the guard — verified
# against the pre-fix function in a scratch copy (never the worktree file).
@test "install_pyenv_rehash_hook fails when the source hook cannot be found" {
  local _root="${BATS_TEST_TMPDIR}/pyenv_root"
  mkdir -p "${_root}/versions"

  run env -i PATH="${PATH}" HOME="${HOME}" _OVERRIDE_PYENV_ROOT="${_root}" bash -c "
    source '${REPO_ROOT}/lib/helpers.sh'
    install_pyenv_rehash_hook
  "
  [ "$status" -eq 1 ]
}

# P3: a directory at the destination path is left untouched and the
# installer fails rather than writing inside it and reporting success.
# Mutation-proven: removing the `[[ -d "${_dst}" ]] && return 1` guard in a
# scratch copy (never the worktree file) made `install -m 0644 src
# .../dotfiles-register-all-executables.bash/` succeed (rc=0), writing a
# file INSIDE the directory rather than replacing it — a hook pyenv would
# never source, reported as a clean install.
@test "install_pyenv_rehash_hook fails when the destination path is a directory" {
  local _root="${BATS_TEST_TMPDIR}/pyenv_root"
  mkdir -p "${_root}/versions"
  local _dst="${_root}/pyenv.d/rehash/dotfiles-register-all-executables.bash"
  mkdir -p "${_dst}"
  export _OVERRIDE_PYENV_ROOT="${_root}"

  run install_pyenv_rehash_hook
  [ "$status" -eq 1 ]
  [ -d "${_dst}" ]
}

# P1: a pre-existing symlink is replaced with a regular file, even when the
# symlink's target holds byte-identical content to the source — the exact
# case where a `cmp -s` guard run before the symlink check would wrongly
# early-return and leave the dangling-link hazard in place. Mutation-proven
# against the pre-fix function (no `[[ -L ]] && rm -f` branch) in a scratch
# copy (never the worktree file): `[[ -f "${_dst}" ]] && cmp -s` follows the
# symlink, sees identical content, and returns 0 without ever replacing it —
# reproduced directly, the symlink survived.
@test "install_pyenv_rehash_hook replaces a pre-existing symlink with a regular file" {
  local _root="${BATS_TEST_TMPDIR}/pyenv_root"
  mkdir -p "${_root}/versions" "${_root}/pyenv.d/rehash"
  local _dst="${_root}/pyenv.d/rehash/dotfiles-register-all-executables.bash"
  local _decoy="${_root}/decoy-hook.bash"
  cp "${REPO_ROOT}/pyenv.d/rehash/dotfiles-register-all-executables.bash" "${_decoy}"
  ln -s "${_decoy}" "${_dst}"
  export _OVERRIDE_PYENV_ROOT="${_root}"

  run install_pyenv_rehash_hook
  [ "$status" -eq 0 ]
  [ -f "${_dst}" ]
  [ ! -L "${_dst}" ]
  cmp -s "${REPO_ROOT}/pyenv.d/rehash/dotfiles-register-all-executables.bash" "${_dst}"
}

# A regular file blocks `mkdir -p .../pyenv.d/rehash` at the pyenv.d
# component, exercising the `mkdir -p ... || return 1` guard.
@test "install_pyenv_rehash_hook fails when pyenv.d/rehash cannot be created" {
  local _root="${BATS_TEST_TMPDIR}/pyenv_root"
  mkdir -p "${_root}/versions"
  : > "${_root}/pyenv.d"
  export _OVERRIDE_PYENV_ROOT="${_root}"

  run install_pyenv_rehash_hook
  [ "$status" -eq 1 ]
}
