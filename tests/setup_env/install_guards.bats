#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_setup_env
  load_mocks
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  export MOCK_WHICH_MISSING=bats
}

teardown() {
  rm -f "${MOCK_CALLS_FILE:-}"
}

@test "install_bats on Ubuntu calls apt-get install" {
  export UBUNTU=1
  unset REDHAT CENTOS FEDORA
  run install_bats
  [ "$status" -eq 0 ]
  grep -q "apt-get install -y bats" "${MOCK_CALLS_FILE}"
}
