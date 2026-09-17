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
}

teardown() {
  rm -f "${MOCK_CALLS_FILE:-}"
}

# Builds a fixture PYENV_ROOT: versions/v/bin/{pytest,py.test,.dot} (the
# collision case plus a dotfile that only dotglob reaches), versions/v/envs/e/bin/x
# (the venv-shim path), and an empty versions/w/bin/ (the nullglob case —
# must contribute nothing, not a literal `*`).
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

@test "with make_shims undefined, sourcing returns 0 and registers nothing" {
  local _root="${BATS_TEST_TMPDIR}/pyenv_root"
  _make_fixture_root "${_root}"
  local _calls="${BATS_TEST_TMPDIR}/shim_calls_undef"

  run env -i PATH="${PATH}" HOME="${HOME}" PYENV_ROOT="${_root}" bash -c "
    source '${HOOK_SRC}'
    echo SOURCED_OK
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"SOURCED_OK"* ]]
  [ ! -f "${_calls}" ]
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

@test "install_pyenv_rehash_hook does not rewrite an already-current copy" {
  local _root="${BATS_TEST_TMPDIR}/pyenv_root"
  mkdir -p "${_root}/versions"
  export _OVERRIDE_PYENV_ROOT="${_root}"

  run install_pyenv_rehash_hook
  [ "$status" -eq 0 ]
  local _dst="${_root}/pyenv.d/rehash/dotfiles-register-all-executables.bash"
  [ -f "${_dst}" ]

  local _mtime_before
  _mtime_before=$(stat -f '%m' "${_dst}" 2>/dev/null || stat -c '%Y' "${_dst}")
  sleep 1

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
