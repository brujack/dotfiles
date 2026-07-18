#!/usr/bin/env bats

load '../helpers/common.bash'

setup() {
  load_mocks
  load_setup_env
  # shellcheck disable=SC1091
  source "${REPO_ROOT}/lib/legacy_rsync.sh"
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  export _OVERRIDE_GIT_REPOS_SRC="${BATS_TEST_TMPDIR}/git-repos"
  mkdir -p "${_OVERRIDE_GIT_REPOS_SRC}"
}

@test "_is_legacy_sync_host is true on studio" {
  export MOCK_HOSTNAME_OUTPUT=studio
  run _is_legacy_sync_host
  [ "$status" -eq 0 ]
}

@test "_is_legacy_sync_host is false on any other host" {
  export MOCK_HOSTNAME_OUTPUT=workstation
  run _is_legacy_sync_host
  [ "$status" -eq 1 ]
}

@test "sync_legacy_dirs runs no rsync and returns 0 on non-studio" {
  export MOCK_HOSTNAME_OUTPUT=workstation
  run sync_legacy_dirs
  [ "$status" -eq 0 ]
  run grep -q rsync "${MOCK_CALLS_FILE}"
  [ "$status" -ne 0 ]
}

@test "sync_legacy_dirs pushes to workstation and laptop-1 with --exclude=personal, ratna without" {
  export MOCK_HOSTNAME_OUTPUT=studio
  run sync_legacy_dirs
  [ "$status" -eq 0 ]
  grep -q -- "--exclude=personal.*bruce@workstation" "${MOCK_CALLS_FILE}"
  grep -q -- "--exclude=personal.*bruce@laptop-1" "${MOCK_CALLS_FILE}"
  grep -q "bruce@ratna" "${MOCK_CALLS_FILE}"
  run grep -- "--exclude=personal.*bruce@ratna" "${MOCK_CALLS_FILE}"
  [ "$status" -ne 0 ]
}

@test "sync_legacy_dirs returns 2 when one rsync leg fails, but still attempts all three legs" {
  export MOCK_HOSTNAME_OUTPUT=studio
  export MOCK_RSYNC_EXIT=1
  run sync_legacy_dirs
  [ "$status" -eq 2 ]
  # A failing leg must not short-circuit the remaining legs — assert all
  # three targets were actually attempted, not just that the exit code
  # matches (an early-return-on-first-failure bug would also produce 2).
  run grep -c "bruce@" "${MOCK_CALLS_FILE}"
  [ "$output" -eq 3 ]
}

@test "sync_legacy_dirs returns 0 when all three legs succeed" {
  export MOCK_HOSTNAME_OUTPUT=studio
  export MOCK_RSYNC_EXIT=0
  run sync_legacy_dirs
  [ "$status" -eq 0 ]
}
