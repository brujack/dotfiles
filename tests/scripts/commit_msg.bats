#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  MSG_FILE="${BATS_TEST_TMPDIR}/COMMIT_EDITMSG"
}

@test "commit-msg accepts a valid feat message" {
  printf "feat: add brew.bundle action\n" > "${MSG_FILE}"
  run bash "${REPO_ROOT}/scripts/commit-msg" "${MSG_FILE}"
  [ "$status" -eq 0 ]
}

@test "commit-msg accepts a valid message with a scope" {
  printf "fix(parser): handle empty manifest\n" > "${MSG_FILE}"
  run bash "${REPO_ROOT}/scripts/commit-msg" "${MSG_FILE}"
  [ "$status" -eq 0 ]
}

@test "commit-msg accepts a breaking-change marker" {
  printf "feat!: drop support for legacy config\n" > "${MSG_FILE}"
  run bash "${REPO_ROOT}/scripts/commit-msg" "${MSG_FILE}"
  [ "$status" -eq 0 ]
}

@test "commit-msg bypasses a Merge commit message" {
  printf "Merge branch 'feature/x' into master\n" > "${MSG_FILE}"
  run bash "${REPO_ROOT}/scripts/commit-msg" "${MSG_FILE}"
  [ "$status" -eq 0 ]
}

@test "commit-msg bypasses a Revert commit message" {
  printf 'Revert "feat: add brew.bundle action"\n' > "${MSG_FILE}"
  run bash "${REPO_ROOT}/scripts/commit-msg" "${MSG_FILE}"
  [ "$status" -eq 0 ]
}

@test "commit-msg bypasses a fixup! commit message" {
  printf "fixup! feat: add brew.bundle action\n" > "${MSG_FILE}"
  run bash "${REPO_ROOT}/scripts/commit-msg" "${MSG_FILE}"
  [ "$status" -eq 0 ]
}

@test "commit-msg bypasses a squash! commit message" {
  printf "squash! feat: add brew.bundle action\n" > "${MSG_FILE}"
  run bash "${REPO_ROOT}/scripts/commit-msg" "${MSG_FILE}"
  [ "$status" -eq 0 ]
}

@test "commit-msg allows an empty message (git rejects separately)" {
  printf "" > "${MSG_FILE}"
  run bash "${REPO_ROOT}/scripts/commit-msg" "${MSG_FILE}"
  [ "$status" -eq 0 ]
}

@test "commit-msg rejects a message with no type prefix" {
  printf "added brew.bundle action\n" > "${MSG_FILE}"
  run bash "${REPO_ROOT}/scripts/commit-msg" "${MSG_FILE}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not follow Conventional Commits format"* ]]
  [[ "$output" == *"Got: added brew.bundle action"* ]]
}

@test "commit-msg rejects an unrecognized type" {
  printf "wip: half-done thing\n" > "${MSG_FILE}"
  run bash "${REPO_ROOT}/scripts/commit-msg" "${MSG_FILE}"
  [ "$status" -eq 1 ]
}

@test "commit-msg rejects a type with no description" {
  printf "feat:\n" > "${MSG_FILE}"
  run bash "${REPO_ROOT}/scripts/commit-msg" "${MSG_FILE}"
  [ "$status" -eq 1 ]
}
