#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_setup_env
  load_mocks
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  export MOCK_ID_U=1000
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${HOME}/software_downloads"
}

teardown() {
  rm -f "${MOCK_CALLS_FILE:-}"
}

# ── update_system_packages — Noble path ─────────────────────────────────────

@test "update_system_packages: UBUNTU+NOBLE calls nala full-upgrade" {
  export UBUNTU=1
  export NOBLE=1
  unset FOCAL JAMMY
  run update_system_packages
  [ "$status" -eq 0 ]
  grep -q "nala full-upgrade" "${MOCK_CALLS_FILE}"
}
