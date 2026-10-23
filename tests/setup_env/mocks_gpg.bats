#!/usr/bin/env bats
# Contract of tests/mocks/gpg's stdin handling. Real gpg reads stdin only for
# --dearmor/--enarmor without a file operand, or with a "-" operand. The mock
# drains stdin in exactly those cases: an unconditional drain blocks forever when
# stdin is an open socket or FIFO whose writer never closes it.

load '../helpers/common.bash'

setup() {
  load_mocks
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  # Resolve the test's own timeout primitive portably (coreutils gtimeout on
  # macOS). tests/mocks has no timeout; if one is ever added this resolution
  # would pick up the mock and a mocked timeout would give a false pass.
  REAL_TIMEOUT="$(command -v timeout || command -v gtimeout)"
  [[ -n "${REAL_TIMEOUT}" ]] || {
    printf 'no timeout/gtimeout on PATH\n' >&2
    return 1
  }
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
  # Explicit return: a caller's `||` turns errexit off inside this function.
  [ "$status" -eq 0 ] || return 1
  # `! cmd` never trips bats' errexit, so test the read explicitly.
  if read -r _line <&8; then
    return 1
  fi
}

@test "stdin: --list-keys with an open FIFO returns without reading" {
  _open_fifo
  run "${REAL_TIMEOUT}" 5 "${GPG_MOCK}" --homedir x --list-keys <&7
  [ "$status" -eq 0 ]
  grep -q -- '^gpg --homedir x --list-keys$' "${MOCK_CALLS_FILE}"
}

@test "stdin: --dearmor consumes a file on stdin" {
  _assert_consumed --dearmor
  grep -q -- '^gpg --dearmor$' "${MOCK_CALLS_FILE}"
}

@test "stdin: --dearmor -o out consumes stdin (-o's argument is not an operand)" {
  _assert_consumed --batch --yes --dearmor -o "${BATS_TEST_TMPDIR}/out"
}

@test "stdin: --dearmor key.asc with an open FIFO returns (file operand)" {
  _open_fifo
  run "${REAL_TIMEOUT}" 5 "${GPG_MOCK}" --dearmor key.asc <&7
  [ "$status" -eq 0 ]
}

@test "stdin: --dearmor -o - consumes stdin (- is -o's argument)" {
  _assert_consumed --dearmor -o -
}

@test "stdin: --dearmor key.asc - consumes stdin (- operand)" {
  _assert_consumed --dearmor key.asc -
}

@test "stdin: --enarmor consumes a file on stdin" {
  _assert_consumed --enarmor
}

@test "stdin: argument-taking options do not create a file operand" {
  local opt
  for opt in -o --output --homedir --status-fd --keyring; do
    _assert_consumed --dearmor "${opt}" x || {
      printf '%s x was read as a file operand\n' "${opt}" >&2
      return 1
    }
  done
}
