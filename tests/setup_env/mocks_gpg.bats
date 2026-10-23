#!/usr/bin/env bats
# Contract of tests/mocks/gpg's stdin handling. Real gpg reads stdin only for
# --dearmor/--enarmor without a file operand, or with a "-" operand. The mock
# drains stdin in exactly those cases: an unconditional drain blocks forever when
# stdin is an open socket or FIFO whose writer never closes it.

load '../helpers/common.bash'

setup() {
  load_mocks
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  # Absolute paths: the test's own primitives must not resolve through PATH mocks.
  REAL_TIMEOUT=/usr/bin/timeout
  GPG_MOCK="${REPO_ROOT}/tests/mocks/gpg"
  FIFO="${BATS_TEST_TMPDIR}/f"
  DATA="${BATS_TEST_TMPDIR}/data"
  printf 'line1\nline2\nline3\n' > "${DATA}"
}

teardown() {
  exec 7>&- 8<&-
}

_open_fifo() {
  mkfifo "${FIFO}"
  exec 7<> "${FIFO}"
}

# Run the mock with the shared fd 8 as stdin, then report whether fd 8 hit EOF.
_assert_consumed() {
  exec 8< "${DATA}"
  run "${REAL_TIMEOUT}" 5 "${GPG_MOCK}" "$@" <&8
  [ "$status" -eq 0 ]
  # `! cmd` never trips bats' errexit, so test the read explicitly.
  if read -r _line <&8; then
    return 1
  fi
}

@test "stdin: --list-keys with an open FIFO returns without reading" {
  _open_fifo
  run "${REAL_TIMEOUT}" 5 "${GPG_MOCK}" --list-keys <&7
  [ "$status" -eq 0 ]
  grep -q -- '^gpg --list-keys$' "${MOCK_CALLS_FILE}"
}

@test "stdin: --dearmor consumes a file on stdin" {
  _assert_consumed --dearmor
}

@test "stdin: --dearmor -o out consumes stdin (-o's argument is not an operand)" {
  _assert_consumed --dearmor -o "${BATS_TEST_TMPDIR}/out"
}

@test "stdin: --dearmor key.asc with an open FIFO returns (file operand)" {
  _open_fifo
  run "${REAL_TIMEOUT}" 5 "${GPG_MOCK}" --dearmor key.asc <&7
  [ "$status" -eq 0 ]
}

@test "stdin: --dearmor -o - consumes stdin (- is -o's argument)" {
  _assert_consumed --dearmor -o -
}
