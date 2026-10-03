#!/usr/bin/env bats
#
# tests/helpers/common.bash strips the git environment when it is sourced, so a
# fixture's git init/config/commit cannot land in the repo named by a GIT_DIR
# the caller exported. Without this test, deleting that line leaves the suite
# green: the leak only shows when a hook or shell exports GIT_DIR.

bats_require_minimum_version 1.5.0

@test "sourcing the shared helper clears every exported git location variable" {
  run bash -c '
    export GIT_DIR=/nonexistent/decoy/.git GIT_WORK_TREE=/nonexistent/decoy
    export GIT_COMMON_DIR=/nonexistent/decoy/.git GIT_INDEX_FILE=/nonexistent/decoy/.git/index
    source "$1"
    printf "[%s][%s][%s][%s]\n" "${GIT_DIR-unset}" "${GIT_WORK_TREE-unset}" \
      "${GIT_COMMON_DIR-unset}" "${GIT_INDEX_FILE-unset}"
  ' _ "${BATS_TEST_DIRNAME}/helpers/common.bash"
  [ "$status" -eq 0 ]
  [ "$output" = "[unset][unset][unset][unset]" ]
}

@test "a fixture repo built after sourcing the helper leaves a leaked GIT_DIR's repo untouched" {
  local decoy="${BATS_TEST_TMPDIR}/decoy" fixture="${BATS_TEST_TMPDIR}/fixture"
  env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE git init -q "${decoy}"
  run bash -c '
    export GIT_DIR="$2/.git"
    source "$1"
    git init -q "$3" && git -C "$3" config user.name Test &&
      git -C "$3" -c user.email=t@example.com commit -q --allow-empty -m init
  ' _ "${BATS_TEST_DIRNAME}/helpers/common.bash" "${decoy}" "${fixture}"
  [ "$status" -eq 0 ]
  [ "$(env -u GIT_DIR git -C "${fixture}" rev-list --count HEAD)" -eq 1 ]
  [ -z "$(env -u GIT_DIR git -C "${decoy}" config --local --get user.name)" ]
  [ "$(env -u GIT_DIR git -C "${decoy}" rev-list --all --count)" -eq 0 ]
}
