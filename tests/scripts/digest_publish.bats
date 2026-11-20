#!/usr/bin/env bats

# Tests for scripts/digest-publish.sh: publish_digest pushes the committed
# digest to its own branch and opens a PR, refuses anything outside the
# digest's directory, and fails loudly when it cannot publish.
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
  DIR="docs/test-features"
  PATH="${REAL_PATH}" git init -q --bare "${REMOTE}"
  PATH="${REAL_PATH}" git init -q -b master "${WORK}"
  PATH="${REAL_PATH}" git -C "${WORK}" config user.email test@example.com
  PATH="${REAL_PATH}" git -C "${WORK}" config user.name Test
  PATH="${REAL_PATH}" git -C "${WORK}" remote add origin "${REMOTE}"
  mkdir -p "${WORK}/${DIR}"
  printf 'base\n' > "${WORK}/base.md"
  PATH="${REAL_PATH}" git -C "${WORK}" add base.md
  PATH="${REAL_PATH}" git -C "${WORK}" commit -q -m base
  PATH="${REAL_PATH}" git -C "${WORK}" push -q origin master
  printf 'digest\n' > "${WORK}/${DIR}/digest.md"
  PATH="${REAL_PATH}" git -C "${WORK}" add "${DIR}/digest.md"
  PATH="${REAL_PATH}" git -C "${WORK}" commit -q -m "docs: digest"

  source "${REPO_ROOT}/scripts/digest-publish.sh"
}

remote_tip() {
  PATH="${REAL_PATH}" git -C "${REMOTE}" rev-parse --verify -q "refs/heads/$1"
}

@test "publish_digest pushes HEAD to its own branch and opens a PR against master" {
  cd "${WORK}"
  PATH="${REAL_PATH}" run publish_digest digest/test-2026-11-23 "docs: digest 2026-11-23" "${DIR}"
  [ "${status}" -eq 0 ]
  [ "$(remote_tip digest/test-2026-11-23)" = "$(PATH="${REAL_PATH}" git -C "${WORK}" rev-parse HEAD)" ]
  # master on the remote is untouched: the digest reaches it only through the PR.
  [ "$(remote_tip master)" = "$(PATH="${REAL_PATH}" git -C "${WORK}" rev-parse HEAD~1)" ]
  grep -qx -- "gh pr create --repo brujack/dotfiles --base master --head digest/test-2026-11-23 --title docs: digest 2026-11-23 --body Weekly digest committed by the scheduled routine." "${MOCK_CALLS_FILE}"
}

@test "publish_digest works from a detached HEAD, as the cloud sandbox checks out" {
  cd "${WORK}"
  PATH="${REAL_PATH}" git checkout -q --detach
  PATH="${REAL_PATH}" run publish_digest digest/detached "docs: digest" "${DIR}"
  [ "${status}" -eq 0 ]
  [ "$(remote_tip digest/detached)" = "$(PATH="${REAL_PATH}" git -C "${WORK}" rev-parse HEAD)" ]
}

@test "publish_digest works from a base behind origin/master" {
  cd "${WORK}"
  # Someone else advanced master after the sandbox checked out.
  PATH="${REAL_PATH}" git switch -q -c ahead HEAD~1
  printf 'peer\n' > "${WORK}/peer.md"
  PATH="${REAL_PATH}" git add peer.md
  PATH="${REAL_PATH}" git commit -q -m "peer work"
  PATH="${REAL_PATH}" git push -q origin HEAD:master
  PATH="${REAL_PATH}" git switch -q master
  PATH="${REAL_PATH}" run publish_digest digest/stale-base "docs: digest" "${DIR}"
  [ "${status}" -eq 0 ]
  [ -n "$(remote_tip digest/stale-base)" ]
}

@test "publish_digest refuses, pushing nothing, when HEAD carries a change outside the digest dir" {
  cd "${WORK}"
  printf 'stray\n' > "${WORK}/stray.sh"
  PATH="${REAL_PATH}" git add stray.sh
  PATH="${REAL_PATH}" git commit -q -m "unrelated work on the sandbox branch"
  PATH="${REAL_PATH}" run publish_digest digest/scoped "docs: digest" "${DIR}"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"stray.sh is outside ${DIR}"* ]]
  [ -z "$(remote_tip digest/scoped)" ]
  run ! grep -q '^gh ' "${MOCK_CALLS_FILE}"
}

@test "publish_digest refuses a rename into the digest dir, which deletes a file outside it" {
  cd "${WORK}"
  # Rename detection would list only the destination; the source path is a
  # deletion outside the dir that an auto-merged PR would apply to master.
  PATH="${REAL_PATH}" git mv base.md "${DIR}/base.md"
  PATH="${REAL_PATH}" git commit -q -m "move base into the digest dir"
  PATH="${REAL_PATH}" run publish_digest digest/renamed "docs: digest" "${DIR}"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"base.md is outside ${DIR}"* ]]
  [ -z "$(remote_tip digest/renamed)" ]
}

@test "publish_digest refuses a sibling dir that only shares the prefix" {
  cd "${WORK}"
  mkdir -p "${WORK}/${DIR}-evil"
  printf 'x\n' > "${WORK}/${DIR}-evil/x.md"
  PATH="${REAL_PATH}" git add "${DIR}-evil/x.md"
  PATH="${REAL_PATH}" git commit -q -m "sibling"
  PATH="${REAL_PATH}" run publish_digest digest/sibling "docs: digest" "${DIR}"
  [ "${status}" -eq 1 ]
  [ -z "$(remote_tip digest/sibling)" ]
}

@test "publish_digest refuses when HEAD adds nothing to master" {
  cd "${WORK}"
  PATH="${REAL_PATH}" git push -q origin HEAD:master
  PATH="${REAL_PATH}" run publish_digest digest/empty "docs: digest" "${DIR}"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"nothing to publish"* ]]
  [ -z "$(remote_tip digest/empty)" ]
}

@test "publish_digest exits 1 naming the branch, and opens no PR, when the push fails" {
  cd "${WORK}"
  # Fetch still works; only the push is refused, by a pre-receive hook.
  printf '#!/bin/sh\nexit 1\n' > "${REMOTE}/hooks/pre-receive"
  chmod +x "${REMOTE}/hooks/pre-receive"
  PATH="${REAL_PATH}" run publish_digest digest/nopush "docs: digest" "${DIR}"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"push of digest/nopush failed"* ]]
  run ! grep -q '^gh ' "${MOCK_CALLS_FILE}"
}

@test "publish_digest exits 1 when origin master cannot be fetched" {
  cd "${WORK}"
  PATH="${REAL_PATH}" git remote set-url origin "${BATS_TEST_TMPDIR}/missing.git"
  PATH="${REAL_PATH}" run publish_digest digest/nofetch "docs: digest" "${DIR}"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"cannot fetch origin master"* ]]
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
  PATH="${REAL_PATH}" run publish_digest digest/taken "docs: digest" "${DIR}"
  [ "${status}" -eq 1 ]
  [ "$(remote_tip digest/taken)" = "${_before}" ]
}

@test "publish_digest exits 1 saying the branch is pushed when gh pr create fails" {
  cd "${WORK}"
  export MOCK_GH_EXIT=1
  PATH="${REAL_PATH}" run publish_digest digest/noprgh "docs: digest" "${DIR}"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"pushed digest/noprgh but could not open the PR"* ]]
  [ -n "$(remote_tip digest/noprgh)" ]
}

@test "publish_digest exits 1 when gh is not installed" {
  cd "${WORK}"
  export _DIGEST_GH_BIN="${BATS_TEST_TMPDIR}/no-such-gh"
  PATH="${REAL_PATH}" run publish_digest digest/nogh "docs: digest" "${DIR}"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"could not open the PR"* ]]
}

@test "publish_digest exits 2 on a wrong argument count, before any push" {
  cd "${WORK}"
  PATH="${REAL_PATH}" run publish_digest digest/only-two "docs: digest"
  [ "${status}" -eq 2 ]
  [ -z "$(remote_tip digest/only-two)" ]
  run ! grep -q '^gh ' "${MOCK_CALLS_FILE}"
}

@test "load_mocks points _DIGEST_GH_BIN at the recording stub, so no test reaches real gh" {
  unset _DIGEST_GH_BIN
  load_mocks
  [ "${_DIGEST_GH_BIN}" = "${REPO_ROOT}/tests/stubs/gh-stub" ]
}
