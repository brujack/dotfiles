#!/usr/bin/env bats
# run_update's apt section: stale-signer, fetch-failure and kept-back detection.

load '../helpers/common.bash'
bats_require_minimum_version 1.5.0

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
  local _rc=0
  run_update || _rc=$?
  [ "${_rc}" -eq 1 ]
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
  local _rc=0
  run_update || _rc=$?
  [ "${_rc}" -eq 1 ]
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

# ── Cluster D: fetch failures and kept-back packages (2026-10-27 audit #4) ────
# Fixtures are real captures; see tests/fixtures/apt/README.md.

@test "_apt_fetch_failed_hosts: unreachable source names the host and apt's reason" {
  run _apt_fetch_failed_hosts < "${REPO_ROOT}/tests/fixtures/apt/update-unreachable-host-resolute.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "nonexistent.invalid"$'\t'"Could not resolve 'nonexistent.invalid'" ]
}

@test "_apt_fetch_failed_hosts: a signer failure's fetch line is left to the signer check" {
  run _apt_fetch_failed_hosts < "${STALE}"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "_apt_fetch_failed_hosts: apt 2.x W: prefix is read; unprefixed, non-fetch and clean lines are not" {
  local _in
  _in=$'W: Failed to fetch http://user@Mirror.Example:8080/ubuntu/dists/noble/InRelease  Could not connect\n'
  _in+=$'Failed to fetch http://unprefixed.example/x  not apt\n'
  _in+=$'W: http://legacy.example/ubuntu/dists/noble/InRelease: Key is stored in legacy trusted.gpg keyring (/etc/apt/trusted.gpg), see the DEPRECATION section in apt-key(8) for details.\n'
  run _apt_fetch_failed_hosts <<< "${_in}"
  [ "$status" -eq 0 ]
  [ "$output" = "mirror.example"$'\t'"Could not connect" ]
  run _apt_fetch_failed_hosts < "${CLEAN}"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "_apt_not_upgraded: held package is reported kept, with apt's count" {
  run _apt_not_upgraded < "${REPO_ROOT}/tests/fixtures/apt/simulate-held-resolute.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "kept"$'\t'"liblzma5"$'\n'"not-upgraded"$'\t'"1" ]
}

@test "_apt_not_upgraded: phased packages are reported phased, not kept" {
  run _apt_not_upgraded < "${REPO_ROOT}/tests/fixtures/apt/simulate-phased-resolute.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "phased"$'\t'"gir1.2-adw-1"$'\n'"phased"$'\t'"libadwaita-1-0"$'\n'"not-upgraded"$'\t'"2" ]
}

@test "_apt_not_upgraded: clean run prints only a zero count" {
  run _apt_not_upgraded < "${REPO_ROOT}/tests/fixtures/apt/simulate-clean-resolute.txt"
  [ "$status" -eq 0 ]
  [ "$output" = "not-upgraded"$'\t'"0" ]
}

@test "_apt_not_upgraded: a kept-back list wrapped over two lines yields every name" {
  local _in
  _in=$'The following packages have been kept back:\n  aa bb\n  cc\n'
  _in+=$'The following packages will be upgraded:\n  dd\n'
  _in+=$'1 upgraded, 0 newly installed, 0 to remove and 3 not upgraded.\n'
  run _apt_not_upgraded <<< "${_in}"
  [ "$status" -eq 0 ]
  [ "$output" = "kept"$'\t'"aa"$'\n'"kept"$'\t'"bb"$'\n'"kept"$'\t'"cc"$'\n'"not-upgraded"$'\t'"3" ]
}

@test "_apt_not_upgraded: CRLF output parses the same as LF" {
  local _in
  _in=$'The following packages have been kept back:\r\n  aa\r\n0 upgraded, 0 newly installed, 0 to remove and 1 not upgraded.\r\n'
  run _apt_not_upgraded <<< "${_in}"
  [ "$status" -eq 0 ]
  [ "$output" = "kept"$'\t'"aa"$'\n'"not-upgraded"$'\t'"1" ]
}

@test "_apt_not_upgraded: no summary line fails, so a format change never reads clean" {
  run _apt_not_upgraded <<< $'The following packages have been kept back:\n  aa\n'
  [ "$status" -eq 1 ]
  run _apt_not_upgraded < /dev/null
  [ "$status" -eq 1 ]
}

@test "run_update apt section: unreachable source is WARN, detail names host and reason" {
  setup_run_update_linux
  MOCK_APT_STDOUT_FILE="${CLEAN}" run_update
  local _base
  _base="$(cat "${_DOTFILES_RUN_TMPDIR}/result_apt")"

  setup_run_update_linux
  local _rc=0
  MOCK_APT_STDOUT_FILE="${REPO_ROOT}/tests/fixtures/apt/update-unreachable-host-resolute.txt" run_update || _rc=$?
  [ "${_rc}" -eq 0 ]
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_apt")" = "WARN" ]
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/result_apt")" = "${_base}; could not fetch nonexistent.invalid — see detail" ]
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/detail_apt")" = "nonexistent.invalid is not updating: fetch failed (Could not resolve 'nonexistent.invalid'); apt kept its previous package list for this source" ]
}

@test "run_update apt section: held package is WARN naming it, and run_update still exits 0" {
  setup_run_update_linux
  MOCK_APT_STDOUT_FILE="${CLEAN}" run_update
  local _base
  _base="$(cat "${_DOTFILES_RUN_TMPDIR}/result_apt")"

  setup_run_update_linux
  export MOCK_APT_STDOUT_FILE="${CLEAN}"
  export MOCK_APT_GET_FULL_UPGRADE_OUTPUT="${REPO_ROOT}/tests/fixtures/apt/simulate-held-resolute.txt"
  local _rc=0
  run_update || _rc=$?
  [ "${_rc}" -eq 0 ]
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_apt")" = "WARN" ]
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/result_apt")" = "${_base}; 1 package(s) kept back: liblzma5 — see detail" ]
  grep -qx 'liblzma5 was kept back: it is held (apt-mark showhold) or its dependencies cannot be met; apt full-upgrade, run as root, says why' "${_DOTFILES_RUN_TMPDIR}/detail_apt"
}

@test "run_update apt section: the kept-back check asks apt in the C locale, as a simulation" {
  setup_run_update_linux
  export MOCK_APT_STDOUT_FILE="${CLEAN}" LC_ALL=C.UTF-8
  run_update
  grep -qx 'apt-get -s full-upgrade' "${MOCK_CALLS_FILE}"
  grep -qx 'apt-get-env LC_ALL=C' "${MOCK_CALLS_FILE}"
}

@test "run_update apt section: phased-only upgrades stay OK" {
  setup_run_update_linux
  export MOCK_APT_STDOUT_FILE="${CLEAN}"
  export MOCK_APT_GET_FULL_UPGRADE_OUTPUT="${REPO_ROOT}/tests/fixtures/apt/simulate-phased-resolute.txt"
  run_update
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_apt")" = "OK" ]
  [[ ! -f "${_DOTFILES_RUN_TMPDIR}/detail_apt" ]]
}

@test "run_update apt section: kept back with phasing names both, warns on the kept one only" {
  setup_run_update_linux
  local _in="${BATS_TEST_TMPDIR}/sim.txt"
  printf '%s\n' 'The following upgrades have been deferred due to phasing:' '  p1' \
    'The following packages have been kept back:' '  k1' \
    '0 upgraded, 0 newly installed, 0 to remove and 2 not upgraded.' > "${_in}"
  export MOCK_APT_STDOUT_FILE="${CLEAN}" MOCK_APT_GET_FULL_UPGRADE_OUTPUT="${_in}"
  run_update
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_apt")" = "WARN" ]
  [[ "$(cat "${_DOTFILES_RUN_TMPDIR}/result_apt")" == *"; 1 package(s) kept back: k1 — see detail" ]]
  grep -q '^k1 was kept back' "${_DOTFILES_RUN_TMPDIR}/detail_apt"
  grep -qx 'phased (Ubuntu staged rollout, installs on its own): p1' "${_DOTFILES_RUN_TMPDIR}/detail_apt"
}

@test "run_update apt section: a not-upgraded count apt did not name still warns" {
  setup_run_update_linux
  local _in="${BATS_TEST_TMPDIR}/sim.txt"
  printf '%s\n' '0 upgraded, 0 newly installed, 0 to remove and 2 not upgraded.' > "${_in}"
  export MOCK_APT_STDOUT_FILE="${CLEAN}" MOCK_APT_GET_FULL_UPGRADE_OUTPUT="${_in}"
  run_update
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_apt")" = "WARN" ]
  [[ "$(cat "${_DOTFILES_RUN_TMPDIR}/result_apt")" == *"; 2 package(s) kept back — see detail" ]]
  grep -qx '2 package(s) not upgraded that apt-get -s full-upgrade did not name; apt list --upgradable lists them' "${_DOTFILES_RUN_TMPDIR}/detail_apt"
}

@test "run_update apt section: a failed simulation is WARN, never clean" {
  setup_run_update_linux
  export MOCK_APT_STDOUT_FILE="${CLEAN}" MOCK_APT_GET_FULL_UPGRADE_EXIT=100
  run_update
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_apt")" = "WARN" ]
  [[ "$(cat "${_DOTFILES_RUN_TMPDIR}/result_apt")" == *"; kept-back check did not run — see detail" ]]
  grep -q 'apt-get -s full-upgrade' "${_DOTFILES_RUN_TMPDIR}/detail_apt"
}

@test "run_update apt section: simulation output with no summary is WARN, never clean" {
  setup_run_update_linux
  local _in="${BATS_TEST_TMPDIR}/sim.txt"
  printf '%s\n' 'Reading package lists...' > "${_in}"
  export MOCK_APT_STDOUT_FILE="${CLEAN}" MOCK_APT_GET_FULL_UPGRADE_OUTPUT="${_in}"
  run_update
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_apt")" = "WARN" ]
  [[ "$(cat "${_DOTFILES_RUN_TMPDIR}/result_apt")" == *"; kept-back check did not run — see detail" ]]
}

@test "run_update apt section: a failed apt keeps FAIL and runs no simulation" {
  setup_run_update_linux
  export MOCK_APT_STDOUT_FILE="${REPO_ROOT}/tests/fixtures/apt/update-unreachable-host-resolute.txt"
  export MOCK_APT_FAIL_SUBCMD=full-upgrade
  export MOCK_APT_GET_FULL_UPGRADE_OUTPUT="${REPO_ROOT}/tests/fixtures/apt/simulate-held-resolute.txt"
  local _rc=0
  run_update || _rc=$?
  [ "${_rc}" -eq 1 ]
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_apt")" = "FAIL" ]
  run ! grep -q '^apt-get -s full-upgrade' "${MOCK_CALLS_FILE}"
  grep -q 'nonexistent.invalid is not updating' "${_DOTFILES_RUN_TMPDIR}/detail_apt"
}

@test "run_update apt section: signer, fetch and kept-back warnings all reach the row" {
  setup_run_update_linux
  local _both="${BATS_TEST_TMPDIR}/both.txt"
  cat "${STALE}" "${REPO_ROOT}/tests/fixtures/apt/update-unreachable-host-resolute.txt" > "${_both}"
  export MOCK_APT_STDOUT_FILE="${_both}"
  export MOCK_APT_GET_FULL_UPGRADE_OUTPUT="${REPO_ROOT}/tests/fixtures/apt/simulate-held-resolute.txt"
  run_update
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_apt")" = "WARN" ]
  [[ "$(cat "${_DOTFILES_RUN_TMPDIR}/result_apt")" == *"; signer check failed for download.docker.com — see detail; could not fetch nonexistent.invalid — see detail; 1 package(s) kept back: liblzma5 — see detail" ]]
  [ "$(wc -l < "${_DOTFILES_RUN_TMPDIR}/detail_apt")" -eq 3 ]
  [[ "$(sed -n 1p "${_DOTFILES_RUN_TMPDIR}/detail_apt")" == "download.docker.com is not updating: signature"* ]]
  [[ "$(sed -n 2p "${_DOTFILES_RUN_TMPDIR}/detail_apt")" == "nonexistent.invalid is not updating: fetch failed"* ]]
  [[ "$(sed -n 3p "${_DOTFILES_RUN_TMPDIR}/detail_apt")" == "liblzma5 was kept back"* ]]
}

@test "run_update apt section: SKIP runs neither the fetch scan nor the simulation" {
  setup_run_update_linux
  unset UBUNTU
  export MOCK_APT_STDOUT_FILE="${REPO_ROOT}/tests/fixtures/apt/update-unreachable-host-resolute.txt"
  export MOCK_APT_GET_FULL_UPGRADE_OUTPUT="${REPO_ROOT}/tests/fixtures/apt/simulate-held-resolute.txt"
  run_update
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_apt")" = "SKIP" ]
  [[ ! -f "${_DOTFILES_RUN_TMPDIR}/detail_apt" ]]
  run ! grep -q '^apt-get -s full-upgrade' "${MOCK_CALLS_FILE}"
}
