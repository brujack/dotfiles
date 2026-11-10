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

# --- _nvidia_userspace_version and _nvidia_driver_state (R1-R4, R9) ---

# Seam fixtures: every case sets its own LINUX, GPU presence, module file and link.
seed_driver() {
  export LINUX=1
  export _OVERRIDE_NVIDIA_GPU_PRESENT=0
  export _NVIDIA_MODULE_VERSION_FILE="${BATS_TEST_TMPDIR}/module-version"
  export _NVIDIA_LIBCUDA="${BATS_TEST_TMPDIR}/libcuda.so.1"
  printf '%s\n' "${1:-610.57.04}" > "${_NVIDIA_MODULE_VERSION_FILE}"
  ln -s "${2:-libcuda.so.615.71.09}" "${_NVIDIA_LIBCUDA}"
  : > "${MOCK_CALLS_FILE}"
}

no_systemctl_calls() {
  ! command grep -q '^systemctl' "${MOCK_CALLS_FILE}"
}

@test "_nvidia_userspace_version: prints the suffix of the link target" {
  seed_driver
  run _nvidia_userspace_version
  [ "${status}" -eq 0 ]
  [ "${output}" = "615.71.09" ]
}

@test "_nvidia_userspace_version: missing path returns 1 silently" {
  seed_driver
  rm -f "${_NVIDIA_LIBCUDA}"
  run _nvidia_userspace_version
  [ "${status}" -eq 1 ]
  [ -z "${output}" ]
}

@test "_nvidia_userspace_version: regular file returns 1 silently" {
  seed_driver
  rm -f "${_NVIDIA_LIBCUDA}"
  printf 'x\n' > "${_NVIDIA_LIBCUDA}"
  run _nvidia_userspace_version
  [ "${status}" -eq 1 ]
  [ -z "${output}" ]
}

@test "_nvidia_userspace_version: malformed suffix returns 1 silently" {
  seed_driver 610.57.04 libcuda.so.abc
  run _nvidia_userspace_version
  [ "${status}" -eq 1 ]
  [ -z "${output}" ]
}

@test "_nvidia_userspace_version: target without libcuda.so. prefix returns 1" {
  seed_driver 610.57.04 libfoo.so.615.71.09
  run _nvidia_userspace_version
  [ "${status}" -eq 1 ]
  [ -z "${output}" ]
}

@test "_nvidia_userspace_version: a link target path is reduced to its basename" {
  seed_driver 610.57.04 /usr/lib/x86_64-linux-gnu/libcuda.so.615.71.09
  run _nvidia_userspace_version
  [ "${status}" -eq 0 ]
  [ "${output}" = "615.71.09" ]
}

@test "_nvidia_driver_state: matching versions print exactly ok" {
  seed_driver 615.71.09
  : > "${MOCK_SYSTEMCTL_ACTIVE_STATE_FILE}"
  run _nvidia_driver_state
  [ "${status}" -eq 0 ]
  [ "${output}" = "ok 615.71.09" ]
}

@test "_nvidia_driver_state: mismatch names loaded then installed" {
  seed_driver
  run _nvidia_driver_state
  [ "${status}" -eq 0 ]
  [ "${output}" = "mismatch 610.57.04 615.71.09" ]
}

@test "_nvidia_driver_state: absent module file is not-loaded" {
  seed_driver
  rm -f "${_NVIDIA_MODULE_VERSION_FILE}"
  run _nvidia_driver_state
  [ "${status}" -eq 0 ]
  [ "${output}" = "not-loaded 615.71.09" ]
  no_systemctl_calls
}

@test "_nvidia_driver_state: malformed module file prints nothing" {
  seed_driver
  printf 'garbage\n' > "${_NVIDIA_MODULE_VERSION_FILE}"
  run _nvidia_driver_state
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

@test "_nvidia_driver_state: unreadable module file prints nothing" {
  [[ "$(id -u)" -ne 0 ]] || skip "root reads a mode 000 file"
  seed_driver
  chmod 000 "${_NVIDIA_MODULE_VERSION_FILE}"
  run _nvidia_driver_state
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

@test "_nvidia_driver_state: no libcuda link prints nothing and never probes the GPU" {
  seed_driver
  rm -f "${_NVIDIA_LIBCUDA}"
  _nvidia_gpu_present() { printf 'called\n' >> "${BATS_TEST_TMPDIR}/gpu-probe-calls"; return 0; }
  run _nvidia_driver_state
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ ! -s "${BATS_TEST_TMPDIR}/gpu-probe-calls" ]
}

@test "_nvidia_driver_state: regular file at the link path prints nothing" {
  seed_driver
  rm -f "${_NVIDIA_LIBCUDA}"
  printf 'x\n' > "${_NVIDIA_LIBCUDA}"
  run _nvidia_driver_state
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

@test "_nvidia_driver_state: malformed link suffix prints nothing" {
  seed_driver 610.57.04 libcuda.so.abc
  run _nvidia_driver_state
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

@test "_nvidia_driver_state: no GPU prints nothing" {
  seed_driver
  export _OVERRIDE_NVIDIA_GPU_PRESENT=1
  run _nvidia_driver_state
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

@test "_nvidia_driver_state: LINUX unset prints nothing and never probes the GPU" {
  seed_driver
  unset LINUX
  _nvidia_gpu_present() { printf 'called\n' >> "${BATS_TEST_TMPDIR}/gpu-probe-calls"; return 0; }
  run _nvidia_driver_state
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ ! -s "${BATS_TEST_TMPDIR}/gpu-probe-calls" ]
}

@test "_nvidia_driver_state: ok with path unit failed adds cdi-failed for the path" {
  seed_driver 615.71.09
  printf 'nvidia-cdi-refresh.path\tfailed\n' > "${MOCK_SYSTEMCTL_ACTIVE_STATE_FILE}"
  run _nvidia_driver_state
  [ "${status}" -eq 0 ]
  [ "${output}" = $'ok 615.71.09\ncdi-failed nvidia-cdi-refresh.path' ]
}

@test "_nvidia_driver_state: ok with service unit failed adds cdi-failed for the service" {
  seed_driver 615.71.09
  printf 'nvidia-cdi-refresh.service\tfailed\n' > "${MOCK_SYSTEMCTL_ACTIVE_STATE_FILE}"
  run _nvidia_driver_state
  [ "${output}" = $'ok 615.71.09\ncdi-failed nvidia-cdi-refresh.service' ]
}

@test "_nvidia_driver_state: both units failed print two lines, path first" {
  seed_driver 615.71.09
  printf 'nvidia-cdi-refresh.service\tfailed\nnvidia-cdi-refresh.path\tfailed\n' \
    > "${MOCK_SYSTEMCTL_ACTIVE_STATE_FILE}"
  run _nvidia_driver_state
  [ "${output}" = $'ok 615.71.09\ncdi-failed nvidia-cdi-refresh.path\ncdi-failed nvidia-cdi-refresh.service' ]
}

@test "_nvidia_driver_state: unlisted units print exactly ok" {
  seed_driver 615.71.09
  : > "${MOCK_SYSTEMCTL_ACTIVE_STATE_FILE}"
  run _nvidia_driver_state
  [ "${output}" = "ok 615.71.09" ]
}

@test "_nvidia_driver_state: failing systemctl read is cdi-unknown, never cdi-failed" {
  seed_driver 615.71.09
  printf 'nvidia-cdi-refresh.path\tfailed\nnvidia-cdi-refresh.service\tfailed\n' \
    > "${MOCK_SYSTEMCTL_ACTIVE_STATE_FILE}"
  export MOCK_SYSTEMCTL_SHOW_EXIT=1
  run _nvidia_driver_state
  [ "${status}" -eq 0 ]
  [ "${output}" = $'ok 615.71.09\ncdi-unknown nvidia-cdi-refresh.path\ncdi-unknown nvidia-cdi-refresh.service' ]
}

@test "_nvidia_driver_state: ok reads each unit with one ActiveState call, path first" {
  seed_driver 615.71.09
  run _nvidia_driver_state
  [ "$(grep '^systemctl' "${MOCK_CALLS_FILE}")" = $'systemctl show -P ActiveState nvidia-cdi-refresh.path\nsystemctl show -P ActiveState nvidia-cdi-refresh.service' ]
}

@test "_nvidia_driver_state: 2026-10-11 replay is a mismatch with no systemctl call" {
  seed_driver 610.57.04 libcuda.so.615.71.09
  printf 'nvidia-cdi-refresh.path\tfailed\n' > "${MOCK_SYSTEMCTL_ACTIVE_STATE_FILE}"
  run _nvidia_driver_state
  [ "${status}" -eq 0 ]
  [ "${output}" = "mismatch 610.57.04 615.71.09" ]
  no_systemctl_calls
}
