#!/usr/bin/env bats

# Tests for scripts/digest-publish.sh: publish_digest pushes the committed
# digest to its own branch and opens a PR, and fails loudly when it cannot.
# Real git against a local bare remote (the git mock cannot fail push alone);
# gh is the recording stub behind _DIGEST_GH_BIN, so no test reaches GitHub.

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_mocks
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  : > "${MOCK_CALLS_FILE}"
  export _DIGEST_GH_BIN="${REPO_ROOT}/tests/stubs/gh-stub"

  # Real git only: tests/mocks/git would record instead of pushing.
  REAL_PATH="$(printf '%s' "${PATH}" | tr ':' '\n' | grep -v 'tests/mocks' | tr '\n' ':' | sed 's/:$//')"
  REMOTE="${BATS_TEST_TMPDIR}/remote.git"
  WORK="${BATS_TEST_TMPDIR}/work"
  PATH="${REAL_PATH}" git init -q --bare "${REMOTE}"
  PATH="${REAL_PATH}" git init -q -b master "${WORK}"
  PATH="${REAL_PATH}" git -C "${WORK}" config user.email test@example.com
  PATH="${REAL_PATH}" git -C "${WORK}" config user.name Test
  PATH="${REAL_PATH}" git -C "${WORK}" remote add origin "${REMOTE}"
  printf 'base\n' > "${WORK}/base.md"
  PATH="${REAL_PATH}" git -C "${WORK}" add base.md
  PATH="${REAL_PATH}" git -C "${WORK}" commit -q -m base
  PATH="${REAL_PATH}" git -C "${WORK}" push -q origin master
  printf 'digest\n' > "${WORK}/digest.md"
  PATH="${REAL_PATH}" git -C "${WORK}" add digest.md
  PATH="${REAL_PATH}" git -C "${WORK}" commit -q -m "docs: digest"

  source "${REPO_ROOT}/scripts/digest-publish.sh"
}

remote_tip() {
  PATH="${REAL_PATH}" git -C "${REMOTE}" rev-parse --verify -q "refs/heads/$1"
}

@test "publish_digest pushes HEAD to its own branch and opens a PR against master" {
  cd "${WORK}"
  PATH="${REAL_PATH}" run publish_digest digest/test-2026-11-23 "docs: digest 2026-11-23"
  [ "${status}" -eq 0 ]
  [ "$(remote_tip digest/test-2026-11-23)" = "$(PATH="${REAL_PATH}" git -C "${WORK}" rev-parse HEAD)" ]
  # master on the remote is untouched: the digest reaches it only through the PR.
  [ "$(remote_tip master)" = "$(PATH="${REAL_PATH}" git -C "${WORK}" rev-parse HEAD~1)" ]
  grep -qx -- "gh pr create --base master --head digest/test-2026-11-23 --title docs: digest 2026-11-23 --body Weekly digest committed by the scheduled routine." "${MOCK_CALLS_FILE}"
}

@test "publish_digest works from a detached HEAD, as the cloud sandbox checks out" {
  cd "${WORK}"
  PATH="${REAL_PATH}" git checkout -q --detach
  PATH="${REAL_PATH}" run publish_digest digest/detached "docs: digest"
  [ "${status}" -eq 0 ]
  [ "$(remote_tip digest/detached)" = "$(PATH="${REAL_PATH}" git -C "${WORK}" rev-parse HEAD)" ]
}

@test "publish_digest exits 1 naming the branch, and opens no PR, when the push fails" {
  cd "${WORK}"
  PATH="${REAL_PATH}" git remote set-url origin "${BATS_TEST_TMPDIR}/missing.git"
  PATH="${REAL_PATH}" run publish_digest digest/nopush "docs: digest"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"push of digest/nopush failed"* ]]
  run ! grep -q '^gh ' "${MOCK_CALLS_FILE}"
}

@test "publish_digest refuses to overwrite an existing remote branch with other history" {
  cd "${WORK}"
  # A same-day re-run, or anyone else, already owns digest/taken with a commit
  # that is not an ancestor of HEAD: a plain push is rejected as non-fast-forward.
  PATH="${REAL_PATH}" git switch -q -c side HEAD~1
  printf 'other\n' > "${WORK}/other.md"
  PATH="${REAL_PATH}" git add other.md
  PATH="${REAL_PATH}" git commit -q -m "docs: other digest"
  PATH="${REAL_PATH}" git push -q origin HEAD:refs/heads/digest/taken
  PATH="${REAL_PATH}" git switch -q master
  local _before
  _before="$(remote_tip digest/taken)"
  PATH="${REAL_PATH}" run publish_digest digest/taken "docs: digest"
  [ "${status}" -eq 1 ]
  [ "$(remote_tip digest/taken)" = "${_before}" ]
}

@test "publish_digest exits 1 saying the branch is pushed when gh pr create fails" {
  cd "${WORK}"
  export MOCK_GH_EXIT=1
  PATH="${REAL_PATH}" run publish_digest digest/noprgh "docs: digest"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"pushed digest/noprgh but could not open the PR"* ]]
  [ -n "$(remote_tip digest/noprgh)" ]
}

@test "publish_digest exits 1 when gh is not installed" {
  cd "${WORK}"
  export _DIGEST_GH_BIN="${BATS_TEST_TMPDIR}/no-such-gh"
  PATH="${REAL_PATH}" run publish_digest digest/nogh "docs: digest"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"could not open the PR"* ]]
}

@test "publish_digest exits 2 on a wrong argument count, before any push" {
  cd "${WORK}"
  PATH="${REAL_PATH}" run publish_digest digest/only-one
  [ "${status}" -eq 2 ]
  [ -z "$(remote_tip digest/only-one)" ]
  run ! grep -q '^gh ' "${MOCK_CALLS_FILE}"
}

@test "load_mocks points _DIGEST_GH_BIN at the recording stub, so no test reaches real gh" {
  unset _DIGEST_GH_BIN
  load_mocks
  [ "${_DIGEST_GH_BIN}" = "${REPO_ROOT}/tests/stubs/gh-stub" ]
}
