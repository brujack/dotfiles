#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_mocks
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  touch "${MOCK_CALLS_FILE}"
  load_setup_env
  export _UPDATE_TMPDIR="${BATS_TEST_TMPDIR}"
  export UPDATE_LOG_PATH="${BATS_TEST_TMPDIR}/update.log"
}

teardown() {
  :
}

# ── _update_diff_lines ────────────────────────────────────────────────────────

@test "_update_diff_lines returns changed lines between pre and post" {
  printf "git 2.44.0\nwget 1.21.3\ncurl 8.6.0\n" > "${BATS_TEST_TMPDIR}/pre"
  printf "git 2.45.0\nwget 1.21.3\ncurl 8.7.1\n" > "${BATS_TEST_TMPDIR}/post"
  run _update_diff_lines "${BATS_TEST_TMPDIR}/pre" "${BATS_TEST_TMPDIR}/post"
  [ "$status" -eq 0 ]
  [[ "$output" == *"git 2.45.0"* ]]
  [[ "$output" == *"curl 8.7.1"* ]]
  [[ "$output" != *"wget"* ]]
}

@test "_update_diff_lines returns empty when no changes" {
  printf "git 2.44.0\nwget 1.21.3\n" > "${BATS_TEST_TMPDIR}/pre"
  printf "git 2.44.0\nwget 1.21.3\n" > "${BATS_TEST_TMPDIR}/post"
  run _update_diff_lines "${BATS_TEST_TMPDIR}/pre" "${BATS_TEST_TMPDIR}/post"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "_update_diff_lines returns new lines added in post" {
  printf "git 2.44.0\n" > "${BATS_TEST_TMPDIR}/pre"
  printf "git 2.44.0\nnode 20.12.0\n" > "${BATS_TEST_TMPDIR}/post"
  run _update_diff_lines "${BATS_TEST_TMPDIR}/pre" "${BATS_TEST_TMPDIR}/post"
  [ "$status" -eq 0 ]
  [[ "$output" == *"node 20.12.0"* ]]
}

# ── _update_snapshot ──────────────────────────────────────────────────────────

@test "_update_snapshot writes command stdout to pre_SECTION file" {
  _update_snapshot "testcmd" printf "hello world\n"
  [ -f "${_UPDATE_TMPDIR}/pre_testcmd" ]
  grep -q "hello world" "${_UPDATE_TMPDIR}/pre_testcmd"
}

@test "_update_snapshot overwrites existing snapshot file" {
  printf "old\n" > "${_UPDATE_TMPDIR}/pre_testcmd"
  _update_snapshot "testcmd" printf "new\n"
  grep -q "new" "${_UPDATE_TMPDIR}/pre_testcmd"
  ! grep -q "old" "${_UPDATE_TMPDIR}/pre_testcmd"
}

# ── _update_git_diff ──────────────────────────────────────────────────────────

@test "_update_git_diff returns commit log between old SHA and HEAD" {
  local _repo="${BATS_TEST_TMPDIR}/gitrepo"
  mkdir -p "${_repo}"
  local clean_path
  clean_path="$(printf "%s" "${PATH}" | tr ':' '\n' | grep -v "tests/mocks" | tr '\n' ':' | sed 's/:$//')"
  bash -c "
    export PATH='${clean_path}'
    git -C '${_repo}' init --quiet
    git -C '${_repo}' config user.email 'test@test.com'
    git -C '${_repo}' config user.name 'Test'
    printf 'a\n' > '${_repo}/file.txt'
    git -C '${_repo}' add .
    git -C '${_repo}' commit --quiet -m 'first commit'
    printf 'b\n' > '${_repo}/file.txt'
    git -C '${_repo}' add .
    git -C '${_repo}' commit --quiet -m 'second commit'
  "
  local _old_sha
  _old_sha=$(bash -c "export PATH='${clean_path}'; git -C '${_repo}' log --format='%H' | tail -1")
  run bash -c "export PATH='${clean_path}'; source '${REPO_ROOT}/lib/update_summary.sh'; _update_git_diff '${_repo}' '${_old_sha}'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"second commit"* ]]
  [[ "$output" != *"first commit"* ]]
}

@test "_update_git_diff returns empty when no new commits" {
  local _repo="${BATS_TEST_TMPDIR}/gitrepo2"
  mkdir -p "${_repo}"
  local clean_path
  clean_path="$(printf "%s" "${PATH}" | tr ':' '\n' | grep -v "tests/mocks" | tr '\n' ':' | sed 's/:$//')"
  bash -c "
    export PATH='${clean_path}'
    git -C '${_repo}' init --quiet
    git -C '${_repo}' config user.email 'test@test.com'
    git -C '${_repo}' config user.name 'Test'
    printf 'a\n' > '${_repo}/file.txt'
    git -C '${_repo}' add .
    git -C '${_repo}' commit --quiet -m 'first commit'
  "
  local _sha
  _sha=$(bash -c "export PATH='${clean_path}'; git -C '${_repo}' rev-parse HEAD")
  run bash -c "export PATH='${clean_path}'; source '${REPO_ROOT}/lib/update_summary.sh'; _update_git_diff '${_repo}' '${_sha}'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
