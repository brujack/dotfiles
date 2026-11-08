#!/usr/bin/env bats

# Covers lib/helpers.sh's _doctor_check_conffile_dist.
#
# Every case sets or unsets LINUX explicitly: developer shells export it, and
# the check is gated on it. _OVERRIDE_CONFFILE_DIST_ROOT always points at a
# fixture directory, never the real /etc.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_setup_env
  load_mocks
  HOME="${BATS_TEST_TMPDIR}/home"
  export HOME
  mkdir -p "${HOME}"
  FAKE_ETC="${BATS_TEST_TMPDIR}/etc"
  mkdir -p "${FAKE_ETC}"
  export _OVERRIDE_CONFFILE_DIST_ROOT="${FAKE_ETC}"
  _DOCTOR_PASS=0 _DOCTOR_FAIL=0 _DOCTOR_FAILED=0 _DOCTOR_WARN=0
  OUT="${BATS_TEST_TMPDIR}/out"
}

teardown() {
  # Restore mode so bats can remove the fixture even after a failed assertion.
  chmod -R u+rwx "${FAKE_ETC}" 2>/dev/null || true
}

@test "nested .dpkg-dist is reported with its path and a diff remedy naming the live file" {
  export LINUX=1
  mkdir -p "${FAKE_ETC}/sub/dir"
  : > "${FAKE_ETC}/sub/dir/foo.conf.dpkg-dist"
  _doctor_check_conffile_dist > "${OUT}" 2>&1
  output="$(cat "${OUT}")"
  [[ "$output" != *"[FAIL]"* ]]
  [ "${_DOCTOR_FAILED}" -eq 0 ]
  [ "$(grep -c '\[WARN\]' <<<"$output")" -eq 1 ]
  [ "$(grep -c '\[PASS\]' <<<"$output")" -eq 0 ]
  [[ "$output" == *"${FAKE_ETC}/sub/dir/foo.conf.dpkg-dist"* ]]
  [[ "$output" == *"diff it against ${FAKE_ETC}/sub/dir/foo.conf,"* ]]
}

@test "nested .ucf-dist is reported" {
  export LINUX=1
  mkdir -p "${FAKE_ETC}/default"
  : > "${FAKE_ETC}/default/grub.ucf-dist"
  _doctor_check_conffile_dist > "${OUT}" 2>&1
  output="$(cat "${OUT}")"
  [[ "$output" != *"[FAIL]"* ]]
  [ "${_DOCTOR_FAILED}" -eq 0 ]
  [ "$(grep -c '\[WARN\]' <<<"$output")" -eq 1 ]
  [[ "$output" == *"${FAKE_ETC}/default/grub.ucf-dist"* ]]
  [[ "$output" == *"diff it against ${FAKE_ETC}/default/grub,"* ]]
}

@test "a .dpkg-dist with an old mtime is still reported" {
  export LINUX=1
  : > "${FAKE_ETC}/old.conf.dpkg-dist"
  touch -t 202001010000 "${FAKE_ETC}/old.conf.dpkg-dist"
  _doctor_check_conffile_dist > "${OUT}" 2>&1
  output="$(cat "${OUT}")"
  [[ "$output" != *"[FAIL]"* ]]
  [ "${_DOCTOR_FAILED}" -eq 0 ]
  [ "$(grep -c '\[WARN\]' <<<"$output")" -eq 1 ]
  [[ "$output" == *"old.conf.dpkg-dist"* ]]
}

@test "multiple files give one WARN each and no PASS" {
  export LINUX=1
  : > "${FAKE_ETC}/a.dpkg-dist"
  : > "${FAKE_ETC}/b.ucf-dist"
  _doctor_check_conffile_dist > "${OUT}" 2>&1
  output="$(cat "${OUT}")"
  [[ "$output" != *"[FAIL]"* ]]
  [ "${_DOCTOR_FAILED}" -eq 0 ]
  [ "$(grep -c '\[WARN\]' <<<"$output")" -eq 2 ]
  [ "$(grep -c '\[PASS\]' <<<"$output")" -eq 0 ]
}

@test ".dpkg-new and .ucf-new are not reported" {
  export LINUX=1
  : > "${FAKE_ETC}/x.conf.dpkg-new"
  : > "${FAKE_ETC}/y.conf.ucf-new"
  _doctor_check_conffile_dist > "${OUT}" 2>&1
  output="$(cat "${OUT}")"
  [[ "$output" != *"[FAIL]"* ]]
  [ "${_DOCTOR_FAILED}" -eq 0 ]
  [ "$(grep -c '\[WARN\]' <<<"$output")" -eq 0 ]
  [ "$(grep -c '\[PASS\]' <<<"$output")" -eq 1 ]
}

@test "empty root gives exactly one PASS and no WARN" {
  export LINUX=1
  _doctor_check_conffile_dist > "${OUT}" 2>&1
  output="$(cat "${OUT}")"
  [[ "$output" != *"[FAIL]"* ]]
  [ "${_DOCTOR_FAILED}" -eq 0 ]
  [ "$(grep -c '\[PASS\]' <<<"$output")" -eq 1 ]
  [ "$(grep -c '\[WARN\]' <<<"$output")" -eq 0 ]
}

@test "missing root gives exactly one WARN and no PASS" {
  export LINUX=1
  export _OVERRIDE_CONFFILE_DIST_ROOT="${BATS_TEST_TMPDIR}/does-not-exist"
  _doctor_check_conffile_dist > "${OUT}" 2>&1
  output="$(cat "${OUT}")"
  [[ "$output" != *"[FAIL]"* ]]
  [ "${_DOCTOR_FAILED}" -eq 0 ]
  [ "$(grep -c '\[WARN\]' <<<"$output")" -eq 1 ]
  [ "$(grep -c '\[PASS\]' <<<"$output")" -eq 0 ]
  [[ "$output" == *"cannot scan"* ]]
}

@test "LINUX unset produces no output even with a kept copy present" {
  unset LINUX
  : > "${FAKE_ETC}/a.dpkg-dist"
  _doctor_check_conffile_dist > "${OUT}" 2>&1
  output="$(cat "${OUT}")"
  [[ "$output" != *"[FAIL]"* ]]
  [ "${_DOCTOR_FAILED}" -eq 0 ]
  [ -z "$output" ]
}

@test "a WARN never marks the doctor run failed and nothing is removed" {
  export LINUX=1
  : > "${FAKE_ETC}/a.dpkg-dist"
  _doctor_check_conffile_dist >/dev/null
  [ "${_DOCTOR_FAILED}" -eq 0 ]
  [ "${_DOCTOR_FAIL}" -eq 0 ]
  [ "${_DOCTOR_WARN}" -eq 1 ]
  [ -e "${FAKE_ETC}/a.dpkg-dist" ]
}

@test "a name carrying both suffixes loses exactly one" {
  export LINUX=1
  : > "${FAKE_ETC}/x.ucf-dist.dpkg-dist"
  _doctor_check_conffile_dist > "${OUT}" 2>&1
  output="$(cat "${OUT}")"
  [[ "$output" != *"[FAIL]"* ]]
  [ "${_DOCTOR_FAILED}" -eq 0 ]
  [ "$(grep -c '\[WARN\]' <<<"$output")" -eq 1 ]
  [[ "$output" == *"diff it against ${FAKE_ETC}/x.ucf-dist,"* ]]
}

@test "an unreadable root gives exactly one WARN naming the failed scan and no PASS" {
  [ "$(id -u)" -ne 0 ] || skip "root can read mode-000 directories"
  export LINUX=1
  : > "${FAKE_ETC}/x.dpkg-dist"
  chmod 000 "${FAKE_ETC}"
  _doctor_check_conffile_dist > "${OUT}" 2>&1
  chmod 755 "${FAKE_ETC}"
  output="$(cat "${OUT}")"
  [ "$(grep -c '\[WARN\]' <<<"$output")" -eq 1 ]
  [ "$(grep -c '\[PASS\]' <<<"$output")" -eq 0 ]
  [[ "$output" == *"cannot scan"* ]]
  [ "${_DOCTOR_FAILED}" -eq 0 ]
}

# --- dpkg package state (spec 2026-10-03 R19) --------------------------------
# A package left unpacked-not-configured by an earlier conffile failure, and a
# packages-microsoft-prod whose keyring or source was deleted after install, both
# leave apt failing. Neither repaired itself: the install guards skip once pwsh
# runs. _doctor_check_dpkg_state reports both with a remedy and runs nothing.
# _DPKG_QUERY_BIN is the stub load_mocks exports; tests feed it fixtures.

_dpkg_status() { printf '%b' "$1" > "${BATS_TEST_TMPDIR}/dpkg-status"; export STUB_DPKG_STATUS="${BATS_TEST_TMPDIR}/dpkg-status"; }
_dpkg_conffiles() { printf '%b' "$1" > "${BATS_TEST_TMPDIR}/dpkg-conffiles"; export STUB_DPKG_CONFFILES="${BATS_TEST_TMPDIR}/dpkg-conffiles"; }
_real_dpkg_query() { PATH="$(printf '%s' "${PATH}" | tr ':' '\n' | grep -v 'tests/mocks' | tr '\n' ':' | sed 's/:$//')" command -v dpkg-query; }

@test "_dpkg_missing_conffiles prints only the absent, non-obsolete conffiles" {
  export _DPKG_CONFFILE_ROOT="${BATS_TEST_TMPDIR}/root"
  mkdir -p "${_DPKG_CONFFILE_ROOT}/etc/apt/sources.list.d"
  : > "${_DPKG_CONFFILE_ROOT}/etc/apt/sources.list.d/microsoft-prod.list"
  _dpkg_conffiles ' /etc/apt/sources.list.d/microsoft-prod.list 20728d05\n /usr/share/keyrings/microsoft-prod.gpg 9d87c5b1\n /etc/old.conf 1234abcd obsolete\n'
  run _dpkg_missing_conffiles packages-microsoft-prod
  [ "$status" -eq 0 ]
  [ "$output" = "/usr/share/keyrings/microsoft-prod.gpg" ]
}

@test "_dpkg_missing_conffiles prints nothing for a package that is not installed" {
  unset STUB_DPKG_CONFFILES
  run _dpkg_missing_conffiles packages-microsoft-prod
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "_dpkg_missing_conffiles counts a dangling symlink as present" {
  export _DPKG_CONFFILE_ROOT="${BATS_TEST_TMPDIR}/root"
  mkdir -p "${_DPKG_CONFFILE_ROOT}/etc"
  ln -s /nonexistent/target "${_DPKG_CONFFILE_ROOT}/etc/link.conf"
  _dpkg_conffiles ' /etc/link.conf abcd\n'
  run _dpkg_missing_conffiles anything
  [ -z "$output" ]
}

@test "_dpkg_missing_conffiles parses the real dpkg-query Conffiles output" {
  local _real _want
  _real="$(_real_dpkg_query)" || skip "no dpkg-query on this host"
  export _DPKG_QUERY_BIN="${_real}"
  # An empty root makes every real conffile of `dpkg` absent, so the count
  # must equal dpkg's own non-obsolete conffile lines -- and be above zero.
  export _DPKG_CONFFILE_ROOT="${BATS_TEST_TMPDIR}/empty-root"
  mkdir -p "${_DPKG_CONFFILE_ROOT}"
  _want="$("${_real}" -W -f='${Conffiles}\n' dpkg | awk 'NF && $3 != "obsolete"' | wc -l | tr -d ' ')"
  [ "${_want}" -gt 0 ]
  run _dpkg_missing_conffiles dpkg
  [ "$(printf '%s\n' "$output" | grep -c '^/')" -eq "${_want}" ]
}

@test "doctor dpkg: each half-configured status FAILs alone with the configure -a remedy" {
  export LINUX=1
  local _row _abbrev
  for _abbrev in 'iU ' 'iF ' 'iH ' 'iW ' 'it ' 'iiR'; do
    _DOCTOR_PASS=0 _DOCTOR_FAIL=0 _DOCTOR_FAILED=0 _DOCTOR_WARN=0
    _dpkg_status "ii \tfine\n${_abbrev}\tstuck\nrc \tremoved\n"
    _doctor_check_dpkg_state > "${OUT}" 2>&1
    output="$(cat "${OUT}")"
    [ "${_DOCTOR_FAILED}" -eq 1 ] || { printf '[%s] no FAIL\n%s\n' "${_abbrev}" "$output"; return 1; }
    [ "$(grep -c '\[FAIL\]' <<<"$output")" -eq 1 ] || { printf '[%s]\n%s\n' "${_abbrev}" "$output"; return 1; }
    [[ "$output" == *"not fully configured: stuck"* ]] || { printf '[%s]\n%s\n' "${_abbrev}" "$output"; return 1; }
    [[ "$output" != *"fine"* && "$output" != *"removed"* ]]
    [[ "$output" == *"sudo DEBIAN_FRONTEND=noninteractive dpkg --configure -a --force-confdef --force-confold"* ]]
    [[ "$output" != *"setup_env.sh -t developer"* ]]
  done
}

@test "doctor dpkg: every half-configured package is named in one FAIL" {
  export LINUX=1
  _dpkg_status "iU \talpha\nii \tbeta\niF \tgamma\n"
  _doctor_check_dpkg_state > "${OUT}" 2>&1
  output="$(cat "${OUT}")"
  [ "$(grep -c '\[FAIL\]' <<<"$output")" -eq 1 ]
  [[ "$output" == *"not fully configured: alpha gamma"* ]]
}

@test "doctor dpkg: a deleted packages-microsoft-prod conffile FAILs with the setup re-run remedy" {
  export LINUX=1
  export _DPKG_CONFFILE_ROOT="${BATS_TEST_TMPDIR}/root"
  mkdir -p "${_DPKG_CONFFILE_ROOT}"
  _dpkg_status "ii \tpackages-microsoft-prod\n"
  _dpkg_conffiles ' /usr/share/keyrings/microsoft-prod.gpg 9d87c5b1\n'
  _doctor_check_dpkg_state > "${OUT}" 2>&1
  output="$(cat "${OUT}")"
  [ "${_DOCTOR_FAILED}" -eq 1 ]
  [ "$(grep -c '\[FAIL\]' <<<"$output")" -eq 1 ]
  [ "$(grep -c '\[PASS\]' <<<"$output")" -eq 0 ]
  [[ "$output" == *"packages-microsoft-prod"*"/usr/share/keyrings/microsoft-prod.gpg"* ]]
  [[ "$output" == *"./setup_env.sh -t developer"* ]]
  [[ "$output" != *"dpkg --configure -a"* ]]
}

@test "doctor dpkg: clean state gives exactly one PASS and no FAIL" {
  export LINUX=1
  export _DPKG_CONFFILE_ROOT="${BATS_TEST_TMPDIR}/root"
  mkdir -p "${_DPKG_CONFFILE_ROOT}/usr/share/keyrings"
  : > "${_DPKG_CONFFILE_ROOT}/usr/share/keyrings/microsoft-prod.gpg"
  _dpkg_status "ii \tpackages-microsoft-prod\nrc \told\nhi \theld\n"
  _dpkg_conffiles ' /usr/share/keyrings/microsoft-prod.gpg 9d87c5b1\n'
  _doctor_check_dpkg_state > "${OUT}" 2>&1
  output="$(cat "${OUT}")"
  [ "${_DOCTOR_FAILED}" -eq 0 ]
  [ "$(grep -c '\[PASS\]' <<<"$output")" -eq 1 ]
  [ "$(grep -c '\[WARN\]' <<<"$output")" -eq 0 ]
}

@test "doctor dpkg: a dpkg-query failure is one WARN, never a PASS or FAIL" {
  export LINUX=1
  export STUB_DPKG_QUERY_EXIT=2
  _doctor_check_dpkg_state > "${OUT}" 2>&1
  output="$(cat "${OUT}")"
  [ "$(grep -c '\[WARN\]' <<<"$output")" -eq 1 ]
  [ "$(grep -c '\[PASS\]' <<<"$output")" -eq 0 ]
  [ "${_DOCTOR_FAILED}" -eq 0 ]
  [[ "$output" == *"cannot list package states"* ]]
}

@test "doctor dpkg: off Linux the check prints nothing and never calls dpkg-query" {
  unset LINUX
  export STUB_DPKG_ARGV="${BATS_TEST_TMPDIR}/argv"
  _dpkg_status "iU \tstuck\n"
  _doctor_check_dpkg_state > "${OUT}" 2>&1
  [ ! -s "${OUT}" ]
  [ ! -e "${STUB_DPKG_ARGV}" ]
}

@test "doctor dpkg: the status query's format is one the real dpkg-query answers in the parsed shape" {
  local _real _args=() _a
  _real="$(_real_dpkg_query)" || skip "no dpkg-query on this host"
  export LINUX=1
  export STUB_DPKG_ARGV="${BATS_TEST_TMPDIR}/argv"
  _doctor_check_dpkg_state > "${OUT}" 2>&1
  # Replay the status call's exact argv (the first one recorded) against the real binary.
  while IFS= read -r _a; do [[ "${_a}" == -- ]] && break; _args+=("${_a}"); done < "${STUB_DPKG_ARGV}"
  [ "${#_args[@]}" -gt 0 ]
  run "${_real}" "${_args[@]}"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c .)" -gt 0 ]
  ! printf '%s\n' "$output" | grep -vqE '^[uihrp][ncHUFWti][ R]	[^[:space:]]+$'
}

@test "run_doctor calls _doctor_check_dpkg_state" {
  declare -f run_doctor | grep -qE '^[[:space:]]+_doctor_check_dpkg_state;?$'
}
