#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  SCRIPT="${REPO_ROOT}/scripts/refresh-uv-lock.sh"
  FIXTURE="${BATS_TEST_TMPDIR}/root"
  mkdir -p "${FIXTURE}"
  printf 'version = 1\n' > "${FIXTURE}/uv.lock"
  export REFRESH_UV_LOCK_ROOT="${FIXTURE}"
  export _UV_BIN="${REPO_ROOT}/tests/stubs/uv-refresh-stub"
  export _MAKE_BIN="${REPO_ROOT}/tests/stubs/make-refresh-stub"
  export STUB_MAKE_LOG="${BATS_TEST_TMPDIR}/make.log"
  BODY="${BATS_TEST_TMPDIR}/body.md"
  unset STUB_UV_LINES STUB_UV_EXIT STUB_UV_CHANGE STUB_MAKE_FAIL
}

run_script() {
  run --separate-stderr bash "${SCRIPT}" "${BODY}" < /dev/null
}

@test "unchanged lock prints no changes and writes no body" {
  export STUB_UV_CHANGE=0
  run_script
  [ "${status}" -eq 0 ]
  [ "${lines[-1]}" = "no changes" ]
  [ ! -e "${BODY}" ]
  [ ! -e "${STUB_MAKE_LOG}" ]
}

@test "changed lock writes body with every line and the four review commands" {
  export STUB_UV_CHANGE=1
  export STUB_UV_LINES=$'Updated acme v5.7.0 -> v5.9.0\nAdded cloudpickle v3.1.2\nRemoved greenlet v3.5.5'
  run_script
  [ "${status}" -eq 0 ]
  [ "${lines[-1]}" = "changed" ]
  command grep -qF 'Updated acme v5.7.0 -> v5.9.0' "${BODY}"
  command grep -qF 'Added cloudpickle v3.1.2' "${BODY}"
  command grep -qF 'Removed greenlet v3.5.5' "${BODY}"
  command grep -qF 'gh pr close chore/uv-lock-refresh && gh pr reopen chore/uv-lock-refresh' "${BODY}"
  command grep -qF 'gh pr merge chore/uv-lock-refresh --squash' "${BODY}"
  command grep -qF 'gh workflow run uv-lock-refresh.yml' "${BODY}"
  command grep -qF 'changed 3 package entries' "${BODY}"
}

@test "changed lock with no change lines is refused" {
  export STUB_UV_CHANGE=1
  run_script
  [ "${status}" -eq 1 ]
  [[ "${stderr}" == *"uv printed no change lines"* ]]
  [ ! -e "${BODY}" ]
}

@test "downgrade is refused" {
  export STUB_UV_CHANGE=1
  export STUB_UV_LINES='Updated acme v2.0 -> v1.9'
  run_script
  [ "${status}" -eq 1 ]
  [[ "${stderr}" == *"refusing downgrade: acme"* ]]
  [[ "${stderr}" == *"yanked"* ]]
  [ ! -e "${STUB_MAKE_LOG}" ]
}

@test "comma form downgrade is refused and comma form upgrade passes" {
  export STUB_UV_CHANGE=1
  export STUB_UV_LINES='Updated six v1.15.0, v1.16.0 -> v1.15.0'
  run_script
  [ "${status}" -eq 1 ]
  [[ "${stderr}" == *"refusing downgrade: six"* ]]
  export STUB_UV_LINES='Updated six v1.15.0, v1.16.0 -> v1.16.0'
  run_script
  [ "${status}" -eq 0 ]
  [ "${lines[-1]}" = "changed" ]
}

@test "unparseable Updated line is refused" {
  export STUB_UV_CHANGE=1
  export STUB_UV_LINES='Updated acme sideways'
  run_script
  [ "${status}" -eq 1 ]
  [[ "${stderr}" == *"unparseable: Updated acme sideways"* ]]
}

@test "uv failure exits 1 with its own message" {
  export STUB_UV_EXIT=2
  run_script
  [ "${status}" -eq 1 ]
  [[ "${stderr}" == *"uv lock --upgrade failed"* ]]
}

@test "sync-requirements-ci failure is named" {
  export STUB_UV_CHANGE=1 STUB_UV_LINES='Updated acme v1 -> v2'
  export STUB_MAKE_FAIL=sync-requirements-ci
  run_script
  [ "${status}" -eq 1 ]
  [[ "${stderr}" == *"make sync-requirements-ci failed"* ]]
}

@test "check-lock failure is named" {
  export STUB_UV_CHANGE=1 STUB_UV_LINES='Updated acme v1 -> v2'
  export STUB_MAKE_FAIL=check-lock
  run_script
  [ "${status}" -eq 1 ]
  [[ "${stderr}" == *"make check-lock failed"* ]]
}

@test "check-requirements-ci failure is named" {
  export STUB_UV_CHANGE=1 STUB_UV_LINES='Updated acme v1 -> v2'
  export STUB_MAKE_FAIL=check-requirements-ci
  run_script
  [ "${status}" -eq 1 ]
  [[ "${stderr}" == *"make check-requirements-ci failed"* ]]
}

@test "both checks run with REQUIRE_TOOLS=1 and the sync does not" {
  export STUB_UV_CHANGE=1 STUB_UV_LINES='Updated acme v1 -> v2'
  unset REQUIRE_TOOLS
  run_script
  [ "${status}" -eq 0 ]
  command grep -qx 'sync-requirements-ci REQUIRE_TOOLS=unset' "${STUB_MAKE_LOG}"
  command grep -qx 'check-lock REQUIRE_TOOLS=1' "${STUB_MAKE_LOG}"
  command grep -qx 'check-requirements-ci REQUIRE_TOOLS=1' "${STUB_MAKE_LOG}"
}

@test "stub sentinel stays off stdout and the last line is the result word" {
  export STUB_UV_CHANGE=1 STUB_UV_LINES='Updated acme v1 -> v2'
  run_script
  [ "${status}" -eq 0 ]
  [ "${output}" = "changed" ]
  [[ "${stderr}" == *"STUB-SENTINEL"* ]]
}

@test "missing body-file argument exits 2" {
  run --separate-stderr bash "${SCRIPT}" < /dev/null
  [ "${status}" -eq 2 ]
  [[ "${stderr}" == *"usage"* ]]
}

@test "unreachable root exits 1" {
  export REFRESH_UV_LOCK_ROOT="${BATS_TEST_TMPDIR}/nope"
  run_script
  [ "${status}" -eq 1 ]
  [[ "${stderr}" == *"cannot cd"* ]]
}

@test "missing uv.lock exits 1" {
  rm -f "${FIXTURE}/uv.lock"
  run_script
  [ "${status}" -eq 1 ]
  [[ "${stderr}" == *"cannot read uv.lock"* ]]
}

@test "relative body-file resolves against the caller's cwd" {
  export STUB_UV_CHANGE=1 STUB_UV_LINES='Updated acme v1 -> v2'
  cd "${BATS_TEST_TMPDIR}"
  run --separate-stderr bash "${SCRIPT}" rel-body.md < /dev/null
  [ "${status}" -eq 0 ]
  [ -s "${BATS_TEST_TMPDIR}/rel-body.md" ]
}

@test "no temp dir is left behind" {
  export STUB_UV_CHANGE=1 STUB_UV_LINES='Updated acme v1 -> v2'
  export TMPDIR="${BATS_TEST_TMPDIR}/tmp"
  mkdir -p "${TMPDIR}"
  run_script
  [ "${status}" -eq 0 ]
  [ -z "$(ls -A "${TMPDIR}")" ]
}
