#!/usr/bin/env bats
#
# NVIDIA driver state check (docs/superpowers/specs/2026-11-09-nvidia-reboot-check-design.md).
# These cases pin the test seams the check relies on: the systemctl stub's
# ActiveState branch (R10) and load_mocks' _NVIDIA_LIBCUDA default (R8).

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_setup_env
  load_mocks
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  export MOCK_SYSTEMCTL_ACTIVE_STATE_FILE="${BATS_TEST_TMPDIR}/active_states"
  printf 'nvidia-cdi-refresh.path\tfailed\nnvidia-cdi-refresh.service\tactive\n' \
    > "${MOCK_SYSTEMCTL_ACTIVE_STATE_FILE}"
}

@test "systemctl stub: a listed unit prints its ActiveState" {
  run "${_SYSTEMCTL_BIN}" show -P ActiveState nvidia-cdi-refresh.path
  [ "${status}" -eq 0 ]
  [ "${output}" = "failed" ]
  run "${_SYSTEMCTL_BIN}" show -P ActiveState nvidia-cdi-refresh.service
  [ "${output}" = "active" ]
}

@test "systemctl stub: an unlisted unit prints inactive" {
  run "${_SYSTEMCTL_BIN}" show -P ActiveState other.service
  [ "${status}" -eq 0 ]
  [ "${output}" = "inactive" ]
}

@test "systemctl stub: unset state file variable prints inactive" {
  unset MOCK_SYSTEMCTL_ACTIVE_STATE_FILE
  run "${_SYSTEMCTL_BIN}" show -P ActiveState nvidia-cdi-refresh.path
  [ "${status}" -eq 0 ]
  [ "${output}" = "inactive" ]
}

@test "systemctl stub: missing state file prints inactive" {
  export MOCK_SYSTEMCTL_ACTIVE_STATE_FILE="${BATS_TEST_TMPDIR}/absent"
  run "${_SYSTEMCTL_BIN}" show -P ActiveState nvidia-cdi-refresh.path
  [ "${status}" -eq 0 ]
  [ "${output}" = "inactive" ]
}

@test "systemctl stub: MOCK_SYSTEMCTL_SHOW_EXIT sets the ActiveState exit status" {
  export MOCK_SYSTEMCTL_SHOW_EXIT=1
  run "${_SYSTEMCTL_BIN}" show -P ActiveState nvidia-cdi-refresh.path
  [ "${status}" -eq 1 ]
}

@test "systemctl stub: ActiveState calls are logged" {
  : > "${MOCK_CALLS_FILE}"
  run "${_SYSTEMCTL_BIN}" show -P ActiveState nvidia-cdi-refresh.path
  grep -qxF 'systemctl show -P ActiveState nvidia-cdi-refresh.path' "${MOCK_CALLS_FILE}"
}

@test "systemctl stub: other show calls still print the tmp.mount fragment" {
  run "${_SYSTEMCTL_BIN}" show -P FragmentPath tmp.mount
  [ "${status}" -eq 0 ]
  [ "${output}" = "${_TMP_STOCK_UNIT}" ]
}
