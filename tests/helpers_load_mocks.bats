#!/usr/bin/env bats
#
# load_mocks used to prepend tests/mocks to PATH before its own chmod/cp calls,
# so those resolved to the logging mocks and appended lines to MOCK_CALLS_FILE,
# which defaults to the shared /tmp/mock_calls. Every test calling load_mocks
# leaked into that one file. The prepend must be load_mocks' last statement.

bats_require_minimum_version 1.5.0

setup() {
  # shellcheck source=tests/helpers/common.bash
  source "${BATS_TEST_DIRNAME}/helpers/common.bash"
}

@test "load_mocks writes no mock log and leaves tests/mocks first on PATH" {
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/calls"
  : > "${MOCK_CALLS_FILE}"
  load_mocks
  if [[ -s ${MOCK_CALLS_FILE} ]]; then
    cat "${MOCK_CALLS_FILE}" >&2
    return 1
  fi
  [ "${PATH%%:*}" = "${REPO_ROOT}/tests/mocks" ]
}
