#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  TRACE_FILE="${BATS_TEST_TMPDIR}/trace.txt"
}

teardown() {
  unset _COV_TRACE_FILE BASH_XTRACEFD PS4
}

@test "bash-tracer.sh returns 0 without side effects when _COV_TRACE_FILE is unset" {
  unset _COV_TRACE_FILE
  ( source "${REPO_ROOT}/scripts/bash-tracer.sh"; [[ -z "${BASH_XTRACEFD:-}" ]] )
  [ "$?" -eq 0 ]
}

@test "bash-tracer.sh sets BASH_XTRACEFD and PS4 when _COV_TRACE_FILE is set to a writable path" {
  export _COV_TRACE_FILE="${TRACE_FILE}"
  ( source "${REPO_ROOT}/scripts/bash-tracer.sh"; [[ "${BASH_XTRACEFD}" == "9" ]] )
  [ "$?" -eq 0 ]
}

@test "bash-tracer.sh writes xtrace output to the trace file for a traced command" {
  export _COV_TRACE_FILE="${TRACE_FILE}"
  bash -c "source '${REPO_ROOT}/scripts/bash-tracer.sh'; true"
  [ -s "${TRACE_FILE}" ]
  grep -q "COVTRACE:" "${TRACE_FILE}"
}

@test "bash-tracer.sh returns 0 without error when _COV_TRACE_FILE points to an unwritable path" {
  export _COV_TRACE_FILE="/nonexistent-dir-for-test/trace.txt"
  run bash -c "source '${REPO_ROOT}/scripts/bash-tracer.sh'; echo ok"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok"* ]]
}
