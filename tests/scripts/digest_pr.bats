#!/usr/bin/env bats

# Tests for scripts/digest-pr.sh, the logic behind .github/workflows/digest-pr.yml.
# The workflow opens the weekly digest PR when a routine pushes digest/<name>-<date>,
# because the routine's cloud session cannot create one. The script re-checks scope
# itself (fail closed) so a digest/* branch carrying anything else opens no PR.
# Real git against a local bare remote; gh is a fake on PATH that records every call
# in ${GH_CALLS}, so no test reaches GitHub. The workflow itself cannot run here.

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  SCRIPT="${REPO_ROOT}/scripts/digest-pr.sh"
  GH_CALLS="${BATS_TEST_TMPDIR}/gh_calls"
  : > "${GH_CALLS}"
  export GH_CALLS
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  cat > "${BATS_TEST_TMPDIR}/bin/gh" <<'GH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${GH_CALLS}"
case "$1 $2" in
  "pr list")
    printf '%s\n' "${FAKE_GH_LIST_COUNT:-0}"
    exit "${FAKE_GH_LIST_EXIT:-0}"
    ;;
  "pr create") exit "${FAKE_GH_CREATE_EXIT:-0}" ;;
esac
exit 99
GH
  chmod +x "${BATS_TEST_TMPDIR}/bin/gh"
  export PATH="${BATS_TEST_TMPDIR}/bin:${PATH}"
  unset FAKE_GH_LIST_COUNT FAKE_GH_LIST_EXIT FAKE_GH_CREATE_EXIT
  export GITHUB_REPOSITORY="brujack/dotfiles"

  REMOTE="${BATS_TEST_TMPDIR}/remote.git"
  WORK="${BATS_TEST_TMPDIR}/work"
  git init -q --bare "${REMOTE}"
  git init -q -b master "${WORK}"
  git -C "${WORK}" config user.email test@example.com
  git -C "${WORK}" config user.name Test
  git -C "${WORK}" remote add origin "${REMOTE}"
  printf 'base\n' > "${WORK}/base.md"
  git -C "${WORK}" add base.md
  git -C "${WORK}" commit -q -m base
  git -C "${WORK}" push -q origin master
  git -C "${WORK}" switch -q -c digest/anthropic-2026-11-23
}

teardown() {
  assert_no_real_root_paths || return 1
}

# commit_file <path>: add one file and commit it on the current branch.
commit_file() {
  mkdir -p "${WORK}/$(dirname "$1")"
  printf 'x\n' > "${WORK}/$1"
  git -C "${WORK}" add "$1"
  git -C "${WORK}" commit -q -m "add $1"
}

head_sha() {
  git -C "${WORK}" rev-parse HEAD
}

# run_digest_pr <branch> [<sha>]: run the script from the checkout, as the workflow does.
# The routine has pushed the branch by then, so HEAD is pushed to origin first
# (digest/* names only: never master) unless a test sets NO_BRANCH_PUSH=1.
run_digest_pr() {
  cd "${WORK}" || return 1
  if [[ -z "${NO_BRANCH_PUSH:-}" && "$1" == digest/* ]]; then
    git -C "${WORK}" push -q -f origin "HEAD:refs/heads/$1" 2>/dev/null || true
  fi
  run bash "${SCRIPT}" "$1" "${2:-$(head_sha)}"
}

@test "digest-pr opens the Anthropic digest PR against master with the workflow's body" {
  commit_file docs/anthropic-new-features/features-2026-11-23.md
  run_digest_pr digest/anthropic-2026-11-23
  [ "${status}" -eq 0 ]
  grep -qF -- "pr create --repo brujack/dotfiles --base master --head digest/anthropic-2026-11-23 --title docs: add Anthropic weekly features digest 2026-11-23 --body " "${GH_CALLS}"
  grep -qF -- "digest-pr workflow" "${GH_CALLS}"
}

@test "digest-pr opens the Claude Code digest PR with its own title" {
  git -C "${WORK}" switch -q -c digest/claude-code-2026-11-23
  commit_file docs/claude-code-new-features/features-2026-11-23.md
  run_digest_pr digest/claude-code-2026-11-23
  [ "${status}" -eq 0 ]
  grep -qF -- "--title docs: add Claude Code weekly features digest 2026-11-23 " "${GH_CALLS}"
}

@test "digest-pr lists only open same-repo PRs for the head branch" {
  commit_file docs/anthropic-new-features/f.md
  run_digest_pr digest/anthropic-2026-11-23
  [ "${status}" -eq 0 ]
  grep -qF -- "pr list --repo brujack/dotfiles --head digest/anthropic-2026-11-23 --state open" "${GH_CALLS}"
  grep -qF -- "isCrossRepository==false" "${GH_CALLS}"
}

@test "digest-pr does nothing, successfully, when an open PR already exists for the branch" {
  commit_file docs/anthropic-new-features/f.md
  export FAKE_GH_LIST_COUNT=1
  run_digest_pr digest/anthropic-2026-11-23
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"already open"* ]]
  run ! grep -q 'pr create' "${GH_CALLS}"
}

@test "digest-pr refuses, opening nothing and calling no gh, when a file lies outside the digest dir" {
  commit_file docs/anthropic-new-features/f.md
  commit_file scripts/evil.sh
  run_digest_pr digest/anthropic-2026-11-23
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"scripts/evil.sh is outside docs/anthropic-new-features"* ]]
  [ ! -s "${GH_CALLS}" ]
}

@test "digest-pr refuses the other digest's directory on a branch named for this one" {
  commit_file docs/claude-code-new-features/f.md
  run_digest_pr digest/anthropic-2026-11-23
  [ "${status}" -eq 1 ]
  [ ! -s "${GH_CALLS}" ]
}

@test "digest-pr refuses a sibling directory that only shares the prefix" {
  commit_file docs/anthropic-new-features-evil/f.md
  run_digest_pr digest/anthropic-2026-11-23
  [ "${status}" -eq 1 ]
  [ ! -s "${GH_CALLS}" ]
}

@test "digest-pr refuses a rename into the digest dir, which deletes a file outside it" {
  mkdir -p "${WORK}/docs/anthropic-new-features"
  git -C "${WORK}" mv base.md docs/anthropic-new-features/base.md
  git -C "${WORK}" commit -q -m "move base into the digest dir"
  run_digest_pr digest/anthropic-2026-11-23
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"base.md is outside"* ]]
  [ ! -s "${GH_CALLS}" ]
}

@test "digest-pr refuses a branch that adds nothing to master" {
  run_digest_pr digest/anthropic-2026-11-23
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"nothing to open a PR for"* ]]
  [ ! -s "${GH_CALLS}" ]
}

@test "digest-pr refuses a branch name that is not digest/(anthropic|claude-code)-YYYY-MM-DD" {
  commit_file docs/anthropic-new-features/f.md
  local _b
  for _b in digest/anthropic-2026-11-23-x digest/other-2026-11-23 feature/x digest/anthropic-2026-1-23 \
    digest/anthropic-2026-11-23/extra "digest/anthropic-2026-11-23 " master ""; do
    run_digest_pr "${_b}"
    [ "${status}" -eq 1 ] || { printf 'accepted %q\n' "${_b}" >&2; return 1; }
  done
  [ ! -s "${GH_CALLS}" ]
}

@test "digest-pr refuses a sha that is not 40 hex digits" {
  commit_file docs/anthropic-new-features/f.md
  run_digest_pr digest/anthropic-2026-11-23 "HEAD"
  [ "${status}" -eq 1 ]
  [ ! -s "${GH_CALLS}" ]
}

@test "digest-pr exits 1 when origin master cannot be fetched" {
  commit_file docs/anthropic-new-features/f.md
  git -C "${WORK}" remote set-url origin "${BATS_TEST_TMPDIR}/missing.git"
  run_digest_pr digest/anthropic-2026-11-23
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"cannot fetch origin master"* ]]
  [ ! -s "${GH_CALLS}" ]
}

@test "digest-pr fails closed, creating nothing, when the PR lookup fails" {
  commit_file docs/anthropic-new-features/f.md
  export FAKE_GH_LIST_EXIT=1
  run_digest_pr digest/anthropic-2026-11-23
  [ "${status}" -eq 1 ]
  run ! grep -q 'pr create' "${GH_CALLS}"
}

@test "digest-pr exits 1 when the PR lookup prints something that is not a count" {
  commit_file docs/anthropic-new-features/f.md
  export FAKE_GH_LIST_COUNT=garbage
  run_digest_pr digest/anthropic-2026-11-23
  [ "${status}" -eq 1 ]
  run ! grep -q 'pr create' "${GH_CALLS}"
}

@test "digest-pr exits 1 when gh cannot create the PR" {
  commit_file docs/anthropic-new-features/f.md
  export FAKE_GH_CREATE_EXIT=1
  run_digest_pr digest/anthropic-2026-11-23
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"could not open the PR"* ]]
}

@test "digest-pr exits 1 when GITHUB_REPOSITORY is unset" {
  commit_file docs/anthropic-new-features/f.md
  unset GITHUB_REPOSITORY
  run_digest_pr digest/anthropic-2026-11-23
  [ "${status}" -eq 1 ]
  [ ! -s "${GH_CALLS}" ]
}

@test "digest-pr exits 2 on a wrong argument count" {
  cd "${WORK}"
  run bash "${SCRIPT}" digest/anthropic-2026-11-23
  [ "${status}" -eq 2 ]
  [ ! -s "${GH_CALLS}" ]
}

@test "digest-pr refuses, creating nothing, when the branch tip moved past the checked sha" {
  commit_file docs/anthropic-new-features/f.md
  local _checked
  _checked="$(head_sha)"
  git -C "${WORK}" push -q -f origin "HEAD:refs/heads/digest/anthropic-2026-11-23"
  commit_file scripts/evil.sh
  git -C "${WORK}" push -q -f origin "HEAD:refs/heads/digest/anthropic-2026-11-23"
  NO_BRANCH_PUSH=1 run_digest_pr digest/anthropic-2026-11-23 "${_checked}"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"tip"*"${_checked}"* ]]
  run ! grep -q 'pr create' "${GH_CALLS}"
}

@test "digest-pr refuses when a decoy ref ending in the branch name points at the checked sha" {
  commit_file docs/anthropic-new-features/f.md
  local _checked
  _checked="$(head_sha)"
  # A ref whose name ends in refs/heads/<branch> sorts before the real one and
  # matches a tail-matching lookup (git ls-remote). Only the exact ref may count.
  git -C "${WORK}" push -q -f origin "HEAD:refs/heads/a/refs/heads/digest/anthropic-2026-11-23"
  commit_file scripts/evil.sh
  git -C "${WORK}" push -q -f origin "HEAD:refs/heads/digest/anthropic-2026-11-23"
  NO_BRANCH_PUSH=1 run_digest_pr digest/anthropic-2026-11-23 "${_checked}"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"tip"*"${_checked}"* ]]
  run ! grep -q 'pr create' "${GH_CALLS}"
}

@test "digest-pr refuses, creating nothing, when the branch is absent from origin" {
  commit_file docs/anthropic-new-features/f.md
  NO_BRANCH_PUSH=1 run_digest_pr digest/anthropic-2026-11-23
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"cannot read the tip of digest/anthropic-2026-11-23"* ]]
  run ! grep -q 'pr create' "${GH_CALLS}"
}

@test "digest-pr fails closed, creating nothing, when the branch tip cannot be fetched" {
  commit_file docs/anthropic-new-features/f.md
  local _real
  _real="$(command -v git)"
  printf '#!/usr/bin/env bash\n[[ "$1" == fetch && "$*" == *refs/heads/digest/* ]] && exit 128\nexec %q "$@"\n' "${_real}" > "${BATS_TEST_TMPDIR}/bin/git"
  chmod +x "${BATS_TEST_TMPDIR}/bin/git"
  run_digest_pr digest/anthropic-2026-11-23
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"cannot read"*"origin"* ]]
  run ! grep -q 'pr create' "${GH_CALLS}"
}
