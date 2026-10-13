#!/usr/bin/env bats

# Covers lib/helpers.sh's _doctor_check_flatpak_gl.
#
# Every case sets or unsets LINUX explicitly: developer shells export it and
# the check is gated on it. The flatpak mock leads PATH via load_mocks, and the
# loaded-driver version file is a fixture, never the real /sys/module path.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_setup_env
  load_mocks
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  : > "${MOCK_CALLS_FILE}"
  HOME="${BATS_TEST_TMPDIR}/home"
  export HOME
  mkdir -p "${HOME}"
  FIXTURE="${REPO_ROOT}/tests/fixtures/flatpak/runtime-list.tsv"
  export _NVIDIA_MODULE_VERSION_FILE="${BATS_TEST_TMPDIR}/nvidia-version"
  printf '615.71.09\n' > "${_NVIDIA_MODULE_VERSION_FILE}"
  export MOCK_FLATPAK_LIST_RUNTIME="${FIXTURE}"
  export MOCK_FLATPAK_LIST_APP="org.example.App"
  unset MOCK_FLATPAK_FAIL_SUBCMD MOCK_FLATPAK_FAIL_ARGS
  export LINUX=1
  _DOCTOR_PASS=0 _DOCTOR_FAIL=0 _DOCTOR_FAILED=0 _DOCTOR_WARN=0
  OUT="${BATS_TEST_TMPDIR}/out"
}

# Run the check in the current shell so the counters are observable. Bare call:
# under bats' errexit the check must survive _flatpak_has_apps returning non-zero.
run_check() {
  _doctor_check_flatpak_gl > "${OUT}" 2>&1
  output="$(cat "${OUT}")"
}

assert_no_mutating_flatpak_call() {
  [ "$(grep -c -E '^flatpak (update|uninstall|install|pin|repair)' "${MOCK_CALLS_FILE}")" -eq 0 ]
}

assert_silent() {
  [ -z "${output}" ]
  [ "${_DOCTOR_PASS}" -eq 0 ]
  [ "${_DOCTOR_FAIL}" -eq 0 ]
  [ "${_DOCTOR_WARN}" -eq 0 ]
  [ "${_DOCTOR_FAILED}" -eq 0 ]
}

@test "silent when LINUX is unset" {
  unset LINUX
  run_check
  assert_silent
}

@test "silent when flatpak is not available" {
  _flatpak_available() { return 1; }
  run_check
  assert_silent
}

@test "silent when no flatpak apps are installed" {
  export MOCK_FLATPAK_LIST_APP=""
  run_check
  assert_silent
}

@test "silent when the loaded driver version file is absent" {
  rm -f "${_NVIDIA_MODULE_VERSION_FILE}"
  run_check
  assert_silent
}

@test "full fixture: one PASS, no WARN, no FAIL" {
  run_check
  [ "$(grep -c '\[PASS\]' <<<"$output")" -eq 1 ]
  [ "$(grep -c '\[WARN\]' <<<"$output")" -eq 0 ]
  [[ "$output" != *"[FAIL]"* ]]
  [ "${_DOCTOR_PASS}" -eq 1 ]
  [ "${_DOCTOR_WARN}" -eq 0 ]
  [ "${_DOCTOR_FAILED}" -eq 0 ]
  assert_no_mutating_flatpak_call
}

@test "missing GL for the loaded driver: one WARN naming Flathub, then the exact update remedy" {
  grep -v 'GL\.nvidia-615-71-09' "${FIXTURE}" > "${BATS_TEST_TMPDIR}/no-gl.tsv"
  [ "$(grep -c 'GL\.nvidia-615-71-09' "${BATS_TEST_TMPDIR}/no-gl.tsv")" -eq 0 ]
  export MOCK_FLATPAK_LIST_RUNTIME="${BATS_TEST_TMPDIR}/no-gl.tsv"
  run_check
  [ "$(grep -c '\[WARN\]' <<<"$output")" -eq 1 ]
  [ "$(grep -c '\[PASS\]' <<<"$output")" -eq 0 ]
  [[ "$output" == *"Flathub"* ]]
  [ "${_DOCTOR_WARN}" -eq 1 ]
  [ "${_DOCTOR_FAILED}" -eq 0 ]
  [ "$(grep -A1 '\[WARN\]' <<<"$output" | tail -1)" = '    sudo flatpak update -y --noninteractive --system' ]
  assert_no_mutating_flatpak_call
}

@test "stale GL refs: one WARN each with the exact uninstall remedy, none for the loaded version" {
  cp "${FIXTURE}" "${BATS_TEST_TMPDIR}/stale.tsv"
  printf '%s\t%s\t%s\n' 'org.freedesktop.Platform.GL.nvidia-580-159-03' x86_64 1.4 >> "${BATS_TEST_TMPDIR}/stale.tsv"
  printf '%s\t%s\t%s\n' 'org.freedesktop.Platform.GL32.nvidia-580-159-03' x86_64 1.4 >> "${BATS_TEST_TMPDIR}/stale.tsv"
  export MOCK_FLATPAK_LIST_RUNTIME="${BATS_TEST_TMPDIR}/stale.tsv"
  run_check
  [ "$(grep -c '\[WARN\]' <<<"$output")" -eq 2 ]
  [ "$(grep -c '\[PASS\]' <<<"$output")" -eq 0 ]
  [ "${_DOCTOR_WARN}" -eq 2 ]
  [ "${_DOCTOR_FAILED}" -eq 0 ]
  [ "$(grep -A1 '\[WARN\].*GL\.nvidia-580' <<<"$output" | tail -1)" = '    sudo flatpak uninstall -y --noninteractive --system org.freedesktop.Platform.GL.nvidia-580-159-03/x86_64/1.4' ]
  [ "$(grep -A1 '\[WARN\].*GL32\.nvidia-580' <<<"$output" | tail -1)" = '    sudo flatpak uninstall -y --noninteractive --system org.freedesktop.Platform.GL32.nvidia-580-159-03/x86_64/1.4' ]
  [ "$(grep -c 'uninstall.*615' <<<"$output")" -eq 0 ]
  [ "$(grep -c '\[WARN\].*615' <<<"$output")" -eq 0 ]
  assert_no_mutating_flatpak_call
}

@test "missing loaded GL and a stale 580 ref: two WARNs, each followed by its own remedy" {
  grep -v 'GL\.nvidia-615-71-09' "${FIXTURE}" > "${BATS_TEST_TMPDIR}/both.tsv"
  printf '%s\t%s\t%s\n' 'org.freedesktop.Platform.GL.nvidia-580-159-03' x86_64 1.4 >> "${BATS_TEST_TMPDIR}/both.tsv"
  export MOCK_FLATPAK_LIST_RUNTIME="${BATS_TEST_TMPDIR}/both.tsv"
  run_check
  [ "$(grep -c '\[WARN\]' <<<"$output")" -eq 2 ]
  [ "${_DOCTOR_WARN}" -eq 2 ]
  [ "${_DOCTOR_FAILED}" -eq 0 ]
  [ "$(grep -A1 '\[WARN\].*GL\.nvidia-615-71-09' <<<"$output" | tail -1)" = '    sudo flatpak update -y --noninteractive --system' ]
  [ "$(grep -A1 '\[WARN\].*GL\.nvidia-580' <<<"$output" | tail -1)" = '    sudo flatpak uninstall -y --noninteractive --system org.freedesktop.Platform.GL.nvidia-580-159-03/x86_64/1.4' ]
  assert_no_mutating_flatpak_call
}

@test "a GL ref whose version only has the loaded one as a prefix does not satisfy the loaded driver" {
  grep -v 'GL\.nvidia-615-71-09' "${FIXTURE}" > "${BATS_TEST_TMPDIR}/prefix.tsv"
  printf '%s\t%s\t%s\n' 'org.freedesktop.Platform.GL.nvidia-615-71-090' x86_64 1.4 >> "${BATS_TEST_TMPDIR}/prefix.tsv"
  export MOCK_FLATPAK_LIST_RUNTIME="${BATS_TEST_TMPDIR}/prefix.tsv"
  run_check
  [ "$(grep -c '\[PASS\]' <<<"$output")" -eq 0 ]
  [ "$(grep -c '\[WARN\].*GL\.nvidia-615-71-09:' <<<"$output")" -eq 1 ]
  [[ "$output" == *"Flathub"* ]]
}

@test "runtime list failure: one 'cannot list' WARN, no FAIL" {
  export MOCK_FLATPAK_FAIL_ARGS="--runtime"
  run_check
  [ "$(grep -c '\[WARN\]' <<<"$output")" -eq 1 ]
  [[ "$output" == *"cannot list"* ]]
  [[ "$output" != *"[FAIL]"* ]]
  [ "${_DOCTOR_FAILED}" -eq 0 ]
  assert_no_mutating_flatpak_call
}

@test "app list failure: one 'cannot list' WARN, no FAIL" {
  export MOCK_FLATPAK_FAIL_ARGS="--app"
  run_check
  [ "$(grep -c '\[WARN\]' <<<"$output")" -eq 1 ]
  [[ "$output" == *"cannot list"* ]]
  [[ "$output" != *"[FAIL]"* ]]
  [ "${_DOCTOR_FAILED}" -eq 0 ]
  assert_no_mutating_flatpak_call
}

@test "run_doctor calls _doctor_check_flatpak_gl directly after _doctor_check_conffile_dist" {
  body="$(declare -f run_doctor | sed 's/^ *//')"
  after="$(grep -A1 -x '_doctor_check_conffile_dist;' <<<"$body" | tail -1)"
  [ "${after}" = "_doctor_check_flatpak_gl;" ]
}
