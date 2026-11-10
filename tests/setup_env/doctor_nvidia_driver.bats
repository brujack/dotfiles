#!/usr/bin/env bats

# Covers lib/helpers.sh's _doctor_check_nvidia_driver.
#
# _nvidia_driver_state is stubbed with a function printing fixed lines, so no
# test reads the real /proc, dkms or systemd. The check runs in the current
# shell so the _DOCTOR_* counters are observable.

REMEDY='    sudo systemctl reset-failed nvidia-cdi-refresh.path nvidia-cdi-refresh.service && sudo systemctl start nvidia-cdi-refresh.path'

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_setup_env
  load_mocks
  _DOCTOR_PASS=0 _DOCTOR_FAIL=0 _DOCTOR_FAILED=0 _DOCTOR_WARN=0
  OUT="${BATS_TEST_TMPDIR}/out"
}

# Stub the state function with the given printf format and arguments.
stub_state() {
  _STUB_STATE="$(printf "$@")"
  _nvidia_driver_state() { printf '%s' "${_STUB_STATE}"; }
}

run_check() {
  _doctor_check_nvidia_driver > "${OUT}" 2>&1
  output="$(cat "${OUT}")"
}

# Strip colour codes so assertions pin the text, not the escape sequences.
plain() {
  sed $'s/\033\\[[0-9;]*m//g' <<<"${output}"
}

@test "empty state: no header, no output, zero counters" {
  stub_state ''
  run_check
  [ -z "${output}" ]
  [ "${_DOCTOR_PASS}" -eq 0 ]
  [ "${_DOCTOR_FAIL}" -eq 0 ]
  [ "${_DOCTOR_WARN}" -eq 0 ]
  [ "${_DOCTOR_FAILED}" -eq 0 ]
}

@test "mismatch: one FAIL naming both versions, no systemctl remedy" {
  stub_state 'mismatch 580.65.06 580.82.07\n'
  run_check
  [ "$(plain)" = "$(printf '\nNVIDIA driver:\n  [FAIL] nvidia module: loaded 580.65.06 but userspace 580.82.07 installed; nvidia-smi, GPU containers and the CDI refresh fail until a reboot; reboot to fix')" ]
  [ "${_DOCTOR_FAIL}" -eq 1 ]
  [ "${_DOCTOR_PASS}" -eq 0 ]
  [ "${_DOCTOR_WARN}" -eq 0 ]
  [[ "${output}" != *systemctl* ]]
  [ "${_DOCTOR_FAILED}" -eq 1 ]
}

@test "not-loaded: exact WARN text, no systemctl remedy" {
  stub_state 'not-loaded 580.82.07\n'
  run_check
  [ "$(plain)" = "$(printf '\nNVIDIA driver:\n  [WARN] nvidia module not loaded (userspace 580.82.07 installed): reboot if the driver was just installed, otherwise check dkms status')" ]
  [ "${_DOCTOR_WARN}" -eq 1 ]
  [ "${_DOCTOR_FAIL}" -eq 0 ]
  [ "${_DOCTOR_PASS}" -eq 0 ]
  [[ "${output}" != *systemctl* ]]
}

@test "ok alone: long PASS" {
  stub_state 'ok 580.82.07\n'
  run_check
  [ "$(plain)" = "$(printf '\nNVIDIA driver:\n  [PASS] nvidia module 580.82.07 matches userspace; CDI refresh not failed')" ]
  [ "${_DOCTOR_PASS}" -eq 1 ]
  [ "${_DOCTOR_FAIL}" -eq 0 ]
  [ "${_DOCTOR_WARN}" -eq 0 ]
}

@test "ok plus one cdi-failed: FAIL, remedy, short PASS" {
  stub_state 'ok 580.82.07\ncdi-failed nvidia-cdi-refresh.service\n'
  run_check
  [ "$(plain)" = "$(printf '\nNVIDIA driver:\n  [FAIL] nvidia-cdi-refresh.service: unit failed\n%s\n  [PASS] nvidia module 580.82.07 matches userspace' "${REMEDY}")" ]
  [ "${_DOCTOR_FAIL}" -eq 1 ]
  [ "${_DOCTOR_FAILED}" -eq 1 ]
  [ "${_DOCTOR_PASS}" -eq 1 ]
  [ "${_DOCTOR_WARN}" -eq 0 ]
}

@test "two cdi-failed lines print the remedy exactly once" {
  stub_state 'ok 580.82.07\ncdi-failed nvidia-cdi-refresh.path\ncdi-failed nvidia-cdi-refresh.service\n'
  run_check
  [ "$(grep -c 'sudo systemctl reset-failed' <<<"${output}")" -eq 1 ]
  [ "$(grep -c '\[FAIL\]' <<<"${output}")" -eq 2 ]
  [[ "${output}" == *"${REMEDY}"* ]]
  [ "${_DOCTOR_FAIL}" -eq 2 ]
  [ "${_DOCTOR_FAILED}" -eq 1 ]
}

@test "ok plus cdi-unknown: WARN and short PASS" {
  stub_state 'ok 580.82.07\ncdi-unknown nvidia-cdi-refresh.path\n'
  run_check
  [ "$(plain)" = "$(printf '\nNVIDIA driver:\n  [WARN] nvidia-cdi-refresh.path: cannot read state\n  [PASS] nvidia module 580.82.07 matches userspace')" ]
  [ "${_DOCTOR_WARN}" -eq 1 ]
  [ "${_DOCTOR_PASS}" -eq 1 ]
  [ "${_DOCTOR_FAIL}" -eq 0 ]
  [[ "${output}" != *systemctl* ]]
}

@test "run_doctor calls _doctor_check_nvidia_driver on the line after _doctor_check_flatpak_gl" {
  run grep -A1 '^  _doctor_check_flatpak_gl$' "${REPO_ROOT}/lib/helpers.sh"
  [ "${lines[1]}" = "  _doctor_check_nvidia_driver" ]
}
