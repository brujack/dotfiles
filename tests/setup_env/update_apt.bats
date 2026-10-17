#!/usr/bin/env bats
# run_update's apt section: stale-signer detection on err_apt.

load '../helpers/common.bash'

setup() {
  load_setup_env
  load_mocks
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  : > "${MOCK_CALLS_FILE}"
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${HOME}"
  STALE="${REPO_ROOT}/tests/fixtures/apt/update-stale-rotated-resolute.txt"
  CLEAN="${REPO_ROOT}/tests/fixtures/apt/update-clean-resolute.txt"
}

@test "run_update apt section: stale signer is WARN, package result kept, detail names host and remedy" {
  setup_run_update_linux
  MOCK_APT_STDOUT_FILE="${CLEAN}" run_update
  local _base
  _base="$(cat "${_DOTFILES_RUN_TMPDIR}/result_apt")"
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_apt")" = "OK" ]

  setup_run_update_linux
  MOCK_APT_STDOUT_FILE="${STALE}" run_update
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_apt")" = "WARN" ]
  [[ "$(cat "${_DOTFILES_RUN_TMPDIR}/result_apt")" == "${_base}; signer check failed for download.docker.com"* ]]
  grep -q 'download.docker.com is not updating' "${_DOTFILES_RUN_TMPDIR}/detail_apt"
  grep -q -e '-t developer' "${_DOTFILES_RUN_TMPDIR}/detail_apt"
}

@test "run_update apt section: stale signer does not make run_update fail" {
  setup_run_update_linux
  export MOCK_APT_STDOUT_FILE="${STALE}"
  run run_update
  [ "$status" -eq 0 ]
}

@test "run_update apt section: failed apt keeps FAIL with error tail before the stale line" {
  setup_run_update_linux
  export MOCK_APT_STDOUT_FILE="${STALE}" MOCK_APT_FAIL_SUBCMD=full-upgrade
  run_update || true
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_apt")" = "FAIL" ]
  local _err _stale
  _err="$(grep -n 'nala full-upgrade failed' "${_DOTFILES_RUN_TMPDIR}/detail_apt" | head -1 | cut -d: -f1)"
  _stale="$(grep -n 'is not updating' "${_DOTFILES_RUN_TMPDIR}/detail_apt" | head -1 | cut -d: -f1)"
  [ -n "${_err}" ]
  [ -n "${_stale}" ]
  [ "${_err}" -lt "${_stale}" ]
}

@test "run_update apt section: clean output is OK with no stale line" {
  setup_run_update_linux
  export MOCK_APT_STDOUT_FILE="${CLEAN}"
  run_update
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_apt")" = "OK" ]
  ! { [[ -f "${_DOTFILES_RUN_TMPDIR}/detail_apt" ]] && grep -q 'is not updating' "${_DOTFILES_RUN_TMPDIR}/detail_apt"; }
}

@test "run_update apt section: parser failure is WARN, never clean" {
  setup_run_update_linux
  export MOCK_APT_STDOUT_FILE="${STALE}"
  _apt_stale_signer_hosts() { printf 'signer lists undefined\n' >&2; return 1; }
  run_update
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_apt")" = "WARN" ]
  [[ "$(cat "${_DOTFILES_RUN_TMPDIR}/result_apt")" == *"signer check did not run"* ]]
  grep -q 'signer lists undefined' "${_DOTFILES_RUN_TMPDIR}/detail_apt"
}
