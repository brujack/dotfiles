#!/usr/bin/env bats

# Covers lib/helpers.sh's _pyenv_missing_shims and _doctor_check_pyenv_shims.
#
# See docs/superpowers/specs/2026-09-17-claude-provisioning-gaps-design.md,
# Part 2: doctor verifies the OUTCOME (every ansible venv binary has a
# shim), not the mechanism (install_pyenv_rehash_hook, Part 1) -- so it also
# catches a future pyenv upgrade silently retiring that hook, which would
# bring the uutils `sort -u` collation defect back with no signal until a
# gate breaks.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_setup_env
  load_mocks
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  HOME="${BATS_TEST_TMPDIR}/home"
  export HOME
  mkdir -p "${HOME}"
  # This developer session exports a real PYENV_ROOT (pyenv's own shell
  # integration), and both functions under test resolve _OVERRIDE_PYENV_ROOT,
  # then PYENV_ROOT, then HOME as their fallback chain -- any test that
  # forgets the override would otherwise read the operator's real ~/.pyenv
  # (tdd.md E2). Every test below sets _OVERRIDE_PYENV_ROOT explicitly.
  unset PYENV_ROOT
}

teardown() {
  rm -f "${MOCK_CALLS_FILE:-}"
}

_make_venv_bin() {
  local _root="$1"
  mkdir -p "${_root}/versions/ansible/bin" "${_root}/shims"
}

# ── _pyenv_missing_shims ──────────────────────────────────────────────────────

@test "_pyenv_missing_shims returns rc 2 and prints nothing when there is no ansible venv" {
  local _root="${BATS_TEST_TMPDIR}/pyenv_root"
  mkdir -p "${_root}"
  export _OVERRIDE_PYENV_ROOT="${_root}"

  run _pyenv_missing_shims
  [ "$status" -eq 2 ]
  [ -z "$output" ]
}

@test "_pyenv_missing_shims returns rc 0 and prints nothing when the venv bin is complete" {
  local _root="${BATS_TEST_TMPDIR}/pyenv_root"
  _make_venv_bin "${_root}"
  : > "${_root}/versions/ansible/bin/pytest"
  : > "${_root}/shims/pytest"
  export _OVERRIDE_PYENV_ROOT="${_root}"

  run _pyenv_missing_shims
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "_pyenv_missing_shims returns rc 0 and prints nothing when the venv bin is empty" {
  local _root="${BATS_TEST_TMPDIR}/pyenv_root"
  _make_venv_bin "${_root}"
  export _OVERRIDE_PYENV_ROOT="${_root}"

  run _pyenv_missing_shims
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "_pyenv_missing_shims prints exactly the missing names, one per line, names with dots included" {
  local _root="${BATS_TEST_TMPDIR}/pyenv_root"
  _make_venv_bin "${_root}"
  : > "${_root}/versions/ansible/bin/pytest"
  : > "${_root}/versions/ansible/bin/py.test"
  : > "${_root}/shims/py.test"
  export _OVERRIDE_PYENV_ROOT="${_root}"

  run _pyenv_missing_shims
  [ "$status" -eq 0 ]
  [ "$output" = "pytest" ]
}

# ── _doctor_check_pyenv_shims ─────────────────────────────────────────────────

# (d) silence, and no header, when there is no ansible venv at all.
@test "_doctor_check_pyenv_shims prints nothing at all when there is no ansible venv" {
  local _root="${BATS_TEST_TMPDIR}/pyenv_root"
  mkdir -p "${_root}"
  export _OVERRIDE_PYENV_ROOT="${_root}"

  run _doctor_check_pyenv_shims
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# (a) PASS, with the count, when every entry is shimmed.
@test "_doctor_check_pyenv_shims passes and reports the count when every entry is shimmed" {
  local _root="${BATS_TEST_TMPDIR}/pyenv_root"
  _make_venv_bin "${_root}"
  : > "${_root}/versions/ansible/bin/pytest"
  : > "${_root}/versions/ansible/bin/py.test"
  : > "${_root}/shims/pytest"
  : > "${_root}/shims/py.test"
  export _OVERRIDE_PYENV_ROOT="${_root}"

  run _doctor_check_pyenv_shims
  [ "$status" -eq 0 ]
  [[ "$output" == *"Pyenv shims:"* ]]
  [[ "$output" == *"[PASS]"* ]]
  [[ "$output" == *"2 of 2 ansible venv entries shimmed"* ]]
}

# (b) FAIL, naming the missing shim, remedy `pyenv rehash` — the exact
# fixture named in the dispatch: bin has pytest + py.test, shims has only
# py.test.
@test "_doctor_check_pyenv_shims fails and names the missing shim, with the pyenv rehash remedy" {
  local _root="${BATS_TEST_TMPDIR}/pyenv_root"
  _make_venv_bin "${_root}"
  : > "${_root}/versions/ansible/bin/pytest"
  : > "${_root}/versions/ansible/bin/py.test"
  : > "${_root}/shims/py.test"
  export _OVERRIDE_PYENV_ROOT="${_root}"

  run _doctor_check_pyenv_shims
  [ "$status" -eq 0 ]
  [[ "$output" == *"[FAIL]"* ]]
  [[ "$output" == *"pytest"* ]]
  [[ "$output" == *"pyenv rehash"* ]]
  [[ "$output" != *"[PASS]"* ]]
}

# (c) WARN, never a PASS with "0 of 0", when the venv bin exists and is empty.
@test "_doctor_check_pyenv_shims warns rather than passes when the venv bin is empty" {
  local _root="${BATS_TEST_TMPDIR}/pyenv_root"
  _make_venv_bin "${_root}"
  export _OVERRIDE_PYENV_ROOT="${_root}"

  run _doctor_check_pyenv_shims
  [ "$status" -eq 0 ]
  [[ "$output" == *"[WARN]"* ]]
  [[ "$output" == *"ansible venv bin is empty"* ]]
  [[ "$output" != *"[PASS]"* ]]
  [[ "$output" != *"0 of 0"* ]]
}
