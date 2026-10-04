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
}

@test "nested .dpkg-dist is reported with its path and a diff remedy naming the live file" {
  export LINUX=1
  mkdir -p "${FAKE_ETC}/sub/dir"
  : > "${FAKE_ETC}/sub/dir/foo.conf.dpkg-dist"
  run _doctor_check_conffile_dist
  [ "$status" -eq 0 ]
  [ "$(grep -c '\[WARN\]' <<<"$output")" -eq 1 ]
  [ "$(grep -c '\[PASS\]' <<<"$output")" -eq 0 ]
  [[ "$output" == *"${FAKE_ETC}/sub/dir/foo.conf.dpkg-dist"* ]]
  [[ "$output" == *"diff it against ${FAKE_ETC}/sub/dir/foo.conf,"* ]]
}

@test "nested .ucf-dist is reported" {
  export LINUX=1
  mkdir -p "${FAKE_ETC}/default"
  : > "${FAKE_ETC}/default/grub.ucf-dist"
  run _doctor_check_conffile_dist
  [ "$(grep -c '\[WARN\]' <<<"$output")" -eq 1 ]
  [[ "$output" == *"${FAKE_ETC}/default/grub.ucf-dist"* ]]
  [[ "$output" == *"diff it against ${FAKE_ETC}/default/grub,"* ]]
}

@test "a .dpkg-dist with an old mtime is still reported" {
  export LINUX=1
  : > "${FAKE_ETC}/old.conf.dpkg-dist"
  touch -d 2020-01-01 "${FAKE_ETC}/old.conf.dpkg-dist"
  run _doctor_check_conffile_dist
  [ "$(grep -c '\[WARN\]' <<<"$output")" -eq 1 ]
  [[ "$output" == *"old.conf.dpkg-dist"* ]]
}

@test "multiple files give one WARN each and no PASS" {
  export LINUX=1
  : > "${FAKE_ETC}/a.dpkg-dist"
  : > "${FAKE_ETC}/b.ucf-dist"
  run _doctor_check_conffile_dist
  [ "$(grep -c '\[WARN\]' <<<"$output")" -eq 2 ]
  [ "$(grep -c '\[PASS\]' <<<"$output")" -eq 0 ]
}

@test ".dpkg-new and .ucf-new are not reported" {
  export LINUX=1
  : > "${FAKE_ETC}/x.conf.dpkg-new"
  : > "${FAKE_ETC}/y.conf.ucf-new"
  run _doctor_check_conffile_dist
  [ "$(grep -c '\[WARN\]' <<<"$output")" -eq 0 ]
  [ "$(grep -c '\[PASS\]' <<<"$output")" -eq 1 ]
}

@test "empty root gives exactly one PASS and no WARN" {
  export LINUX=1
  run _doctor_check_conffile_dist
  [ "$status" -eq 0 ]
  [ "$(grep -c '\[PASS\]' <<<"$output")" -eq 1 ]
  [ "$(grep -c '\[WARN\]' <<<"$output")" -eq 0 ]
}

@test "missing root gives exactly one WARN and no PASS" {
  export LINUX=1
  export _OVERRIDE_CONFFILE_DIST_ROOT="${BATS_TEST_TMPDIR}/does-not-exist"
  run _doctor_check_conffile_dist
  [ "$status" -eq 0 ]
  [ "$(grep -c '\[WARN\]' <<<"$output")" -eq 1 ]
  [ "$(grep -c '\[PASS\]' <<<"$output")" -eq 0 ]
  [[ "$output" == *"cannot scan"* ]]
}

@test "LINUX unset produces no output even with a kept copy present" {
  unset LINUX
  : > "${FAKE_ETC}/a.dpkg-dist"
  run _doctor_check_conffile_dist
  [ "$status" -eq 0 ]
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
