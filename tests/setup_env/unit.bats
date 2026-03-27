#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_setup_env
}

@test "quiet_which returns 0 for existing command" {
  run quiet_which bash
  [ "$status" -eq 0 ]
}
