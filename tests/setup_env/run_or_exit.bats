#!/usr/bin/env bats
#
# _run_or_exit (lib/workflows.sh) dispatches one run function and, when a
# mapped run function returns non-zero, records a "failed" ledger entry before
# exiting with that function's own code. Spec:
# docs/superpowers/specs/2026-11-04-ledger-run-outcome-design.md (R4).
#
# Every test shares one fixture -- a fixture HOME with a machine-id, the
# recording ledger mock, and a run directory with started_at -- so the absence
# cases below are controls only beside the positive cases in the same file:
# with no machine-id the writer would no-op and every absence test would pass
# vacuously.

setup() {
  exec < /dev/null
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_mocks
  load_setup_env
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${HOME}/.config/dotfiles"
  printf 'test-machine-uuid\n' > "${HOME}/.config/dotfiles/machine-id"
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  : > "${MOCK_CALLS_FILE}"
  export LEDGER_BIN="${REPO_ROOT}/tests/mocks/ledger"
  unset DRY_RUN _DOTFILES_RUN_TMPDIR
}

# _fake_run_dir: what _dotfiles_run_tmpdir_setup leaves behind, without its
# ensure_state_ledger side effects.
_fake_run_dir() {
  _DOTFILES_RUN_TMPDIR="$(mktemp -d "${BATS_TEST_TMPDIR}/run.XXXXXX")"
  export _DOTFILES_RUN_TMPDIR
  printf '2026-11-04T00:00:00Z\n' > "${_DOTFILES_RUN_TMPDIR}/started_at"
  printf '1762214400\n' > "${_DOTFILES_RUN_TMPDIR}/start_epoch"
  printf 'run-%s\n' "${RANDOM}" > "${_DOTFILES_RUN_TMPDIR}/run_id"
  printf 'deadbeef\n' > "${_DOTFILES_RUN_TMPDIR}/git_sha"
}

# The payload has no trailing newline, so a second call's argv line is glued
# to the first payload's closing brace: count occurrences, not line starts.
_ledger_calls() {
  grep -o 'ledger write' "${MOCK_CALLS_FILE}" | wc -l | tr -d ' '
}

@test "_run_or_exit: a failing mapped run function writes one failed entry and exits with its code" {
  run_setup_user() { _fake_run_dir; return 3; }
  run _run_or_exit run_setup_user
  [ "${status}" -eq 3 ]
  [ "$(_ledger_calls)" -eq 1 ]
  grep -q '"outcome": "failed"' "${MOCK_CALLS_FILE}"
  grep -q '"success": false' "${MOCK_CALLS_FILE}"
  grep -q '"run_type": "setup_user"' "${MOCK_CALLS_FILE}"
}

@test "_run_or_exit: each mapped run function gets its own run type" {
  local _pair _fn _type
  for _pair in run_setup_user:setup_user run_setup_or_developer:setup \
               run_developer_or_ansible:developer run_recreate_venv:recreate_venv \
               run_recreate_ruby:recreate_ruby; do
    _fn="${_pair%%:*}"; _type="${_pair##*:}"
    : > "${MOCK_CALLS_FILE}"
    eval "${_fn}() { _fake_run_dir; return 1; }"
    run _run_or_exit "${_fn}"
    [ "${status}" -eq 1 ]
    [ "$(_ledger_calls)" -eq 1 ]
    grep -q "\"run_type\": \"${_type}\"" "${MOCK_CALLS_FILE}"
  done
}

@test "_run_or_exit: a run function that already wrote its own entry gets no second write" {
  run_setup_user() { _fake_run_dir; _ledger_write_run_entry setup_user 0; return 1; }
  run _run_or_exit run_setup_user
  [ "${status}" -eq 1 ]
  [ "$(_ledger_calls)" -eq 1 ]
}

@test "_run_or_exit: a failure before the run directory exists cannot reuse a previous run's directory" {
  _fake_run_dir
  local _prev="${_DOTFILES_RUN_TMPDIR}"
  _ledger_write_run_entry setup_user 0
  [ "$(_ledger_calls)" -eq 1 ]
  local _before
  _before="$(cat "${MOCK_CALLS_FILE}")"
  run_setup_or_developer() { return 1; }
  run _run_or_exit run_setup_or_developer
  [ "${status}" -eq 1 ]
  [ "$(_ledger_calls)" -eq 1 ]
  [ "$(cat "${MOCK_CALLS_FILE}")" = "${_before}" ]
  [ -f "${_prev}/ledger_written" ]
}

@test "_run_or_exit: run_update and unmapped functions get no dispatcher write" {
  run_update() { _fake_run_dir; return 1; }
  run _run_or_exit run_update
  [ "${status}" -eq 1 ]
  [ "$(_ledger_calls)" -eq 0 ]
  run_brew_install() { _fake_run_dir; return 1; }
  run _run_or_exit run_brew_install
  [ "${status}" -eq 1 ]
  [ "$(_ledger_calls)" -eq 0 ]
}

@test "_run_or_exit: a successful run returns 0 with no dispatcher write" {
  run_setup_user() { _fake_run_dir; return 0; }
  run _run_or_exit run_setup_user
  [ "${status}" -eq 0 ]
  [ "$(_ledger_calls)" -eq 0 ]
}

@test "_run_or_exit: every mapped run function ends with its own ledger write (N2 pin)" {
  # A function that wrote 0 and then failed would keep a success:true entry,
  # because the one-write guard blocks the dispatcher's failed write.
  local _pair _fn _type _last
  for _pair in run_setup_user:setup_user run_setup_or_developer:setup \
               run_developer_or_ansible:developer run_recreate_venv:recreate_venv \
               run_recreate_ruby:recreate_ruby; do
    _fn="${_pair%%:*}"; _type="${_pair##*:}"
    _last="$(declare -f "${_fn}" | tail -2 | head -1 | sed 's/^ *//')"
    [ "${_last}" = "_ledger_write_run_entry \"${_type}\" 0 || true" ]
  done
}
