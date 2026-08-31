#!/usr/bin/env bats
# Coverage for tests/mocks/curl's -f/HTTP-status simulation and -o content
# writing. See shell.md's PATH-mock-fidelity pitfall: a mock that returns
# success without performing the real operation passes tests asserting on
# return code but fails tests asserting on side effects (files created).
# Before this file, a successful -o call produced a zero-byte target --
# byte-identical to the production defect this branch exists to catch.

load '../helpers/common.bash'

setup() {
  CURL_MOCK="${REPO_ROOT}/tests/mocks/curl"
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
}

@test "curl mock: -fsS with MOCK_CURL_HTTP_STATUS=404 exits non-zero" {
  export MOCK_CURL_HTTP_STATUS=404
  run "${CURL_MOCK}" -fsS -o "${BATS_TEST_TMPDIR}/out1" https://cht.sh/:cht.sh
  [ "$status" -ne 0 ]
}

@test "curl mock: -sS (no f) with MOCK_CURL_HTTP_STATUS=404 exits 0" {
  export MOCK_CURL_HTTP_STATUS=404
  run "${CURL_MOCK}" -sS -o "${BATS_TEST_TMPDIR}/out2" http://x
  [ "$status" -eq 0 ]
}

@test "curl mock: --form (long option) with MOCK_CURL_HTTP_STATUS=404 exits 0" {
  export MOCK_CURL_HTTP_STATUS=404
  run "${CURL_MOCK}" --form x -o "${BATS_TEST_TMPDIR}/out3" http://x
  [ "$status" -eq 0 ]
}

@test "curl mock: -o writes MOCK_CURL_STDOUT content to the target" {
  export MOCK_CURL_STDOUT="body"
  local target="${BATS_TEST_TMPDIR}/out4"
  rm -f "${target}"
  run "${CURL_MOCK}" -o "${target}" http://x
  [ "$status" -eq 0 ]
  [ -s "${target}" ]
}

@test "curl mock: -o on a simulated failure leaves a pre-seeded target unchanged" {
  export MOCK_CURL_HTTP_STATUS=404
  export MOCK_CURL_STDOUT="body"
  local target="${BATS_TEST_TMPDIR}/out5"
  printf 'pre-existing content\n' > "${target}"
  run "${CURL_MOCK}" -fsS -o "${target}" http://x
  [ "$status" -ne 0 ]
  run cat "${target}"
  [ "$output" = "pre-existing content" ]
}

@test "curl mock: MOCK_CURL_EXIT=0 beats MOCK_CURL_HTTP_STATUS=404" {
  export MOCK_CURL_EXIT=0
  export MOCK_CURL_HTTP_STATUS=404
  run "${CURL_MOCK}" -fsS -o "${BATS_TEST_TMPDIR}/out6" http://x
  [ "$status" -eq 0 ]
}

@test "curl mock: both unset behaves as today -- exit 0 and -o target created" {
  local target="${BATS_TEST_TMPDIR}/out7"
  rm -f "${target}"
  run "${CURL_MOCK}" -o "${target}" http://x
  [ "$status" -eq 0 ]
  [ -f "${target}" ]
}
