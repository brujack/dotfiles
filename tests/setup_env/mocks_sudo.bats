#!/usr/bin/env bats
# Contract of tests/mocks/sudo's environment handling. Real sudo resets the
# caller's environment, so `VAR=x sudo cmd` never reaches cmd while
# `sudo VAR=x cmd` does. The mock scrubs DEBIAN_FRONTEND (and only that) so a
# misplaced assignment in production code cannot pass the behavioural tests.

load '../helpers/common.bash'

setup() {
  load_mocks
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  unset DEBIAN_FRONTEND
  # tests/mocks/sh is itself a mock, so name the real shell by absolute path.
  REAL_SH=/bin/sh
}

_probe_frontend='printf "%s" "${DEBIAN_FRONTEND:-<unset>}"'

@test "sudo mock: caller-environment DEBIAN_FRONTEND does not reach the child" {
  DEBIAN_FRONTEND=dialog run sudo "${REAL_SH}" -c "${_probe_frontend}"
  [ "$status" -eq 0 ]
  [ "$output" = "<unset>" ]
}

@test "sudo mock: DEBIAN_FRONTEND given on the sudo command line reaches the child" {
  run sudo DEBIAN_FRONTEND=noninteractive "${REAL_SH}" -c "${_probe_frontend}"
  [ "$status" -eq 0 ]
  [ "$output" = "noninteractive" ]
}

@test "sudo mock: -H before the assignment still delivers it" {
  run sudo -H DEBIAN_FRONTEND=noninteractive "${REAL_SH}" -c "${_probe_frontend}"
  [ "$status" -eq 0 ]
  [ "$output" = "noninteractive" ]
}

@test "sudo mock: command-line DEBIAN_FRONTEND wins over a different caller value" {
  DEBIAN_FRONTEND=dialog run sudo DEBIAN_FRONTEND=noninteractive "${REAL_SH}" -c "${_probe_frontend}"
  [ "$status" -eq 0 ]
  [ "$output" = "noninteractive" ]
}

@test "sudo mock: an unrelated caller variable still reaches the child" {
  FOO=bar run sudo "${REAL_SH}" -c 'printf "%s" "${FOO:-<unset>}"'
  [ "$status" -eq 0 ]
  [ "$output" = "bar" ]
}

@test "sudo mock: the invocation is logged verbatim to MOCK_CALLS_FILE" {
  : > "${MOCK_CALLS_FILE}"
  run sudo -H DEBIAN_FRONTEND=noninteractive "${REAL_SH}" -c 'exit 0'
  [ "$status" -eq 0 ]
  [ "$(cat "${MOCK_CALLS_FILE}")" = "sudo -H DEBIAN_FRONTEND=noninteractive ${REAL_SH} -c exit 0" ]
}
