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
  _apt_stale_signer_hosts() { log_error 'signer lists undefined'; return 1; }
  run_update
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_apt")" = "WARN" ]
  [[ "$(cat "${_DOTFILES_RUN_TMPDIR}/result_apt")" == *"signer check did not run"* ]]
  grep -q 'signer lists undefined' "${_DOTFILES_RUN_TMPDIR}/detail_apt"
  ! command grep -q $'\x1b' "${_DOTFILES_RUN_TMPDIR}/detail_apt"
}

@test "run_update apt section: two stale hosts are named in order, one detail line each" {
  setup_run_update_linux
  local _both="${BATS_TEST_TMPDIR}/both.txt"
  cat "${STALE}" "${REPO_ROOT}/tests/fixtures/apt/update-hashicorp-stale-rotated.txt" > "${_both}"
  MOCK_APT_STDOUT_FILE="${_both}" run_update
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_apt")" = "WARN" ]
  [[ "$(cat "${_DOTFILES_RUN_TMPDIR}/result_apt")" == *"; signer check failed for download.docker.com, apt.releases.hashicorp.com — see detail" ]]
  [ "$(wc -l < "${_DOTFILES_RUN_TMPDIR}/detail_apt")" -eq 2 ]
  [[ "$(sed -n 1p "${_DOTFILES_RUN_TMPDIR}/detail_apt")" == "download.docker.com is not updating"* ]]
  [[ "$(sed -n 2p "${_DOTFILES_RUN_TMPDIR}/detail_apt")" == "apt.releases.hashicorp.com is not updating"* ]]
}

@test "run_update apt section: detail line has the exact pinned format" {
  setup_run_update_linux
  MOCK_APT_STDOUT_FILE="${STALE}" run_update
  local _want
  _want="download.docker.com is not updating: signature check failed (NO_PUBKEY): signer rotated or expired, or a proxy served unsigned data; $(_apt_signer_remedy download.docker.com)"
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/detail_apt")" = "${_want}" ]
}

@test "run_update apt section: parser failure on a failed apt keeps FAIL, appends message without ANSI" {
  setup_run_update_linux
  export MOCK_APT_STDOUT_FILE="${STALE}" MOCK_APT_FAIL_SUBCMD=full-upgrade
  _apt_stale_signer_hosts() { log_error "boom"; return 1; }
  run_update || true
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_apt")" = "FAIL" ]
  local _err _boom
  _err="$(grep -n 'nala full-upgrade failed' "${_DOTFILES_RUN_TMPDIR}/detail_apt" | head -1 | cut -d: -f1)"
  _boom="$(grep -n 'boom' "${_DOTFILES_RUN_TMPDIR}/detail_apt" | head -1 | cut -d: -f1)"
  [ -n "${_err}" ]
  [ -n "${_boom}" ]
  [ "${_err}" -lt "${_boom}" ]
  ! command grep -q $'\x1b' "${_DOTFILES_RUN_TMPDIR}/detail_apt"
}

@test "run_update apt section: SKIP stays SKIP even when the parser would fail" {
  setup_run_update_linux
  unset UBUNTU
  export MOCK_APT_STDOUT_FILE="${STALE}"
  _apt_stale_signer_hosts() { log_error "boom"; return 1; }
  run_update
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_apt")" = "SKIP" ]
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/result_apt")" = "not applicable" ]
  [[ ! -f "${_DOTFILES_RUN_TMPDIR}/detail_apt" ]]
}
