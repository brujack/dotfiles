#!/usr/bin/env bats

# Covers lib/helpers.sh's _pyenv_ansible_venv_bin, _pyenv_ansible_venv_entries,
# _pyenv_missing_shims and _doctor_check_pyenv_shims.
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
  # integration), and every function under test resolves _OVERRIDE_PYENV_ROOT,
  # then PYENV_ROOT, then HOME as its fallback chain -- any test that
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

# T2: a single-name fixture cannot show a separator, and an implementation
# that `break`s after the first missing entry would pass every test above.
@test "_pyenv_missing_shims prints all missing names when more than one is missing" {
  local _root="${BATS_TEST_TMPDIR}/pyenv_root"
  _make_venv_bin "${_root}"
  : > "${_root}/versions/ansible/bin/pytest"
  : > "${_root}/versions/ansible/bin/black"
  # shims/ stays empty -- neither is shimmed.
  export _OVERRIDE_PYENV_ROOT="${_root}"

  run _pyenv_missing_shims
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  [[ "$output" == *"pytest"* ]]
  [[ "$output" == *"black"* ]]
}

# T3 / P1: a dangling symlink in bin/ must not be dropped by `-e` (which
# follows the link and reports false for a broken one).
@test "_pyenv_missing_shims reports a dangling, unshimmed symlink as missing" {
  local _root="${BATS_TEST_TMPDIR}/pyenv_root"
  _make_venv_bin "${_root}"
  ln -s "${_root}/nonexistent-target" "${_root}/versions/ansible/bin/python"
  export _OVERRIDE_PYENV_ROOT="${_root}"

  run _pyenv_missing_shims
  [ "$status" -eq 0 ]
  [ "$output" = "python" ]
}

# P2: the check must mirror the rehash hook's `shopt -s dotglob`, or a
# dot-prefixed venv entry the hook shims is invisible here.
@test "_pyenv_missing_shims includes a dot-prefixed venv entry, mirroring the rehash hook's dotglob" {
  local _root="${BATS_TEST_TMPDIR}/pyenv_root"
  _make_venv_bin "${_root}"
  : > "${_root}/versions/ansible/bin/.hidden-tool"
  export _OVERRIDE_PYENV_ROOT="${_root}"

  run _pyenv_missing_shims
  [ "$status" -eq 0 ]
  [ "$output" = ".hidden-tool" ]
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

# T1: the real-world shape -- shims/ spans every pyenv version, so |shims|
# is always >= |bin|. This fixture has shims/ carry two MORE entries than
# bin/ (python3.11, pip belong to other pyenv versions), so an
# implementation that mistakenly counted shims/ instead of bin/ reports
# "4 of 4" here, not "2 of 2".
@test "_doctor_check_pyenv_shims passes and reports the count when every entry is shimmed" {
  local _root="${BATS_TEST_TMPDIR}/pyenv_root"
  _make_venv_bin "${_root}"
  : > "${_root}/versions/ansible/bin/pytest"
  : > "${_root}/versions/ansible/bin/py.test"
  : > "${_root}/shims/pytest"
  : > "${_root}/shims/py.test"
  : > "${_root}/shims/python3.11"
  : > "${_root}/shims/pip"
  export _OVERRIDE_PYENV_ROOT="${_root}"

  run _doctor_check_pyenv_shims
  [ "$status" -eq 0 ]
  [[ "$output" == *"Pyenv shims:"* ]]
  [[ "$output" == *"[PASS]"* ]]
  [[ "$output" == *"2 of 2 ansible venv entries shimmed"* ]]
  [[ "$output" != *"4 of 4"* ]]
}

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

# T2, doctor arm: both missing names must appear on the single [FAIL] line
# -- an implementation naming only the first missing entry would pass a
# one-name fixture.
@test "_doctor_check_pyenv_shims names every missing shim on the one FAIL line" {
  local _root="${BATS_TEST_TMPDIR}/pyenv_root"
  _make_venv_bin "${_root}"
  : > "${_root}/versions/ansible/bin/pytest"
  : > "${_root}/versions/ansible/bin/black"
  export _OVERRIDE_PYENV_ROOT="${_root}"

  run _doctor_check_pyenv_shims
  [ "$status" -eq 0 ]
  local _fail_count
  _fail_count="$(printf '%s\n' "$output" | grep -c '\[FAIL\]')"
  [ "${_fail_count}" -eq 1 ]
  [[ "$output" == *"pytest"* ]]
  [[ "$output" == *"black"* ]]
}

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

# T3, doctor arm: a bin/ holding only dangling, unshimmed symlinks is NOT
# empty -- it must FAIL naming them, never WARN "ansible venv bin is empty".
@test "_doctor_check_pyenv_shims does not report an empty bin when it holds only dangling symlinks" {
  local _root="${BATS_TEST_TMPDIR}/pyenv_root"
  _make_venv_bin "${_root}"
  ln -s "${_root}/nonexistent-a" "${_root}/versions/ansible/bin/toola"
  ln -s "${_root}/nonexistent-b" "${_root}/versions/ansible/bin/toolb"
  export _OVERRIDE_PYENV_ROOT="${_root}"

  run _doctor_check_pyenv_shims
  [ "$status" -eq 0 ]
  [[ "$output" != *"ansible venv bin is empty"* ]]
  [[ "$output" == *"[FAIL]"* ]]
  [[ "$output" == *"toola"* ]]
  [[ "$output" == *"toolb"* ]]
}

# T3, doctor arm, mixed: a real shimmed entry alongside a dangling unshimmed
# symlink must count BOTH in the total and FAIL naming the symlink -- not
# silently read as "[PASS] 1 of 1".
@test "_doctor_check_pyenv_shims counts a dangling symlink into the total rather than dropping it" {
  local _root="${BATS_TEST_TMPDIR}/pyenv_root"
  _make_venv_bin "${_root}"
  : > "${_root}/versions/ansible/bin/pytest"
  : > "${_root}/shims/pytest"
  ln -s "${_root}/nonexistent-target" "${_root}/versions/ansible/bin/python"
  export _OVERRIDE_PYENV_ROOT="${_root}"

  run _doctor_check_pyenv_shims
  [ "$status" -eq 0 ]
  [[ "$output" != *"[PASS]"* ]]
  [[ "$output" != *"1 of 1"* ]]
  [[ "$output" == *"[FAIL]"* ]]
  [[ "$output" == *"python"* ]]
}

# P4: an unbounded list is unreadable with a wiped shims/ directory. Six
# missing entries must be capped, with the true count stated up front.
@test "_doctor_check_pyenv_shims caps the missing list and states the true count" {
  local _root="${BATS_TEST_TMPDIR}/pyenv_root"
  _make_venv_bin "${_root}"
  local _n
  for _n in e1 e2 e3 e4 e5 e6; do
    : > "${_root}/versions/ansible/bin/${_n}"
  done
  export _OVERRIDE_PYENV_ROOT="${_root}"

  run _doctor_check_pyenv_shims
  [ "$status" -eq 0 ]
  [[ "$output" == *"[FAIL]"* ]]
  [[ "$output" == *"6 entries"* ]]
  [[ "$output" == *"..."* ]]
  # _missing_count/_suffix are computed independently of the `head -n 5`
  # that does the capping, so the two assertions above hold whether or not
  # the cap itself runs. This pair pins the cap.
  [[ "$output" == *"e5"* ]]   # five names ARE shown
  [[ "$output" != *"e6"* ]]   # the sixth is NOT -- this is the cap
}
