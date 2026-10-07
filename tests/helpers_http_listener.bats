#!/usr/bin/env bats
#
# Tests for tests/helpers/http_listener.bash: a one-shot python3 listener that
# records request headers and cannot outlive a test holding bats' fd 3.

bats_require_minimum_version 1.5.0

setup() {
  source "${BATS_TEST_DIRNAME}/helpers/common.bash"
  source "${BATS_TEST_DIRNAME}/helpers/http_listener.bash"
}

teardown() {
  stop_http_listener
}

@test "listener serves one GET to real curl and records the request headers" {
  start_http_listener "${BATS_TEST_TMPDIR}"
  local rc=0 out
  out=$(/usr/bin/env curl -sf -H 'X-Probe: p1' "${HTTP_LISTENER_URL}/x") || rc=$?
  [ "${rc}" -eq 0 ]
  [ "${out}" = '{"tag_name": "v9.9.9"}' ]
  grep -q 'X-Probe: p1' "${HTTP_LISTENER_HEADERS}"
}

@test "listener with no request exits on its own after the deadline" {
  HTTP_LISTENER_DEADLINE=1 start_http_listener "${BATS_TEST_TMPDIR}"
  # Positive control: it was alive right after start.
  kill -0 "${HTTP_LISTENER_PID}"
  local _
  for _ in $(seq 80); do
    kill -0 "${HTTP_LISTENER_PID}" 2>/dev/null || break
    sleep 0.05
  done
  ! kill -0 "${HTTP_LISTENER_PID}" 2>/dev/null
}

@test "listener holds neither bats' fd 3 nor the test's output pipe" {
  [[ -d /proc/self/fd ]] || skip "needs /proc"
  start_http_listener "${BATS_TEST_TMPDIR}"
  [[ -d /proc/${HTTP_LISTENER_PID}/fd ]] || skip "needs /proc"
  # Positive control: $! is python itself, and fd 0 exists to inspect.
  [[ "$(ps -o comm= -p "${HTTP_LISTENER_PID}")" == *python* ]]
  [ -e "/proc/${HTTP_LISTENER_PID}/fd/0" ]
  # python reuses the closed fd 3 for its own listening socket, so fd 3 must
  # be that socket and not the inherited bats descriptor (a pipe or file).
  [[ "$(readlink "/proc/${HTTP_LISTENER_PID}/fd/3")" == socket:* ]]
  [ "$(readlink "/proc/${HTTP_LISTENER_PID}/fd/1")" = "${BATS_TEST_TMPDIR}/listener.log" ]
}
