#!/usr/bin/env bats

# The -t update summary must not lose or soften a row: a section that started and
# never finished, a status it does not recognise, and a FAIL overwritten by a later
# WARN or OK each read clean before, and none raised the exit code.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_mocks
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  touch "${MOCK_CALLS_FILE}"
  load_setup_env
  export _DOTFILES_RUN_TMPDIR="${BATS_TEST_TMPDIR}"
  export UPDATE_LOG_PATH="${BATS_TEST_TMPDIR}/update.log"
}

_status() { cat "${_DOTFILES_RUN_TMPDIR}/status_$1"; }

# ── started but never finished ───────────────────────────────────────────────

@test "test_bug_update_summary_integrity: a section that started and never ended is a FAIL row" {
  _update_record_start rust
  run _update_summary
  [ "$status" -eq 1 ]
  [[ "$output" == *"[FAIL] rust"*"started but did not finish"* ]]
  [[ "$output" == *"1 sections: 0 OK, 1 failed"* ]]
  # Rewritten on disk, so the ledger's failure_stage (which reads the files) names it.
  [ "$(_status rust)" = "FAIL" ]
}

@test "test_bug_update_summary_integrity: a started section that ends with 0 is OK" {
  _update_record_start rust
  _update_record_end rust 0
  run _update_summary
  [ "$status" -eq 0 ]
  [[ "$output" == *"[OK]   rust"* ]]
}

@test "test_bug_update_summary_integrity: a started section that is then skipped is SKIP" {
  _update_record_start rust
  _update_skip rust "rustup not found"
  run _update_summary
  [ "$status" -eq 0 ]
  [[ "$output" == *"[SKIP] rust"*"rustup not found"* ]]
}

# ── unrecognised status ──────────────────────────────────────────────────────

@test "test_bug_update_summary_integrity: an unrecognised status is a FAIL row, counted" {
  printf "BOGUS\n" > "${_DOTFILES_RUN_TMPDIR}/status_brew"
  printf "whatever\n" > "${_DOTFILES_RUN_TMPDIR}/result_brew"
  run _update_summary
  [ "$status" -eq 1 ]
  [[ "$output" == *"[FAIL] brew"*"unrecognised status 'BOGUS'"* ]]
  [[ "$output" == *"1 sections: 0 OK, 1 failed"* ]]
  [ "$(_status brew)" = "FAIL" ]
}

@test "test_bug_update_summary_integrity: an empty status file is a FAIL row, counted" {
  : > "${_DOTFILES_RUN_TMPDIR}/status_brew"
  run _update_summary
  [ "$status" -eq 1 ]
  [[ "$output" == *"[FAIL] brew"*"unrecognised status ''"* ]]
}

# ── a FAIL is never downgraded ───────────────────────────────────────────────

@test "test_bug_update_summary_integrity: _update_warn does not downgrade a FAIL" {
  _update_record_end git-repos 1
  _update_warn git-repos "one or more repos unreachable"
  [ "$(_status git-repos)" = "FAIL" ]
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/result_git-repos")" = "exit 1" ]
  run _update_summary
  [ "$status" -eq 1 ]
}

@test "test_bug_update_summary_integrity: _update_ok does not downgrade a FAIL" {
  _update_fail pip-check "dependency conflicts reported"
  _update_ok pip-check "no dependency conflicts"
  [ "$(_status pip-check)" = "FAIL" ]
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/result_pip-check")" = "dependency conflicts reported" ]
}

@test "test_bug_update_summary_integrity: _update_warn still turns an OK into WARN" {
  _update_record_end git-repos 0
  _update_warn git-repos "one or more repos unreachable"
  [ "$(_status git-repos)" = "WARN" ]
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/result_git-repos")" = "one or more repos unreachable" ]
}
