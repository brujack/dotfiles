#!/usr/bin/env bats

load '../helpers/common.bash'

setup() {
  load_setup_env
  # lib/git_sync.sh isn't wired into setup_env.sh's source chain until a
  # later task — source it explicitly so this file is self-contained.
  # shellcheck disable=SC1091
  source "${REPO_ROOT}/lib/git_sync.sh"
  export TESTDIR="${BATS_TEST_TMPDIR}"
  export ORIGIN="${TESTDIR}/origin.git"
  export CLONE="${TESTDIR}/clone"
  git init -q --bare "${ORIGIN}"
  git clone -q "${ORIGIN}" "${CLONE}"
  git -C "${CLONE}" commit -q --allow-empty -m init
  git -C "${CLONE}" push -q -u origin HEAD:master
}

@test "_git_repo_status reports missing for a nonexistent path" {
  run _git_repo_status "${TESTDIR}/does-not-exist"
  [ "$status" -eq 0 ]
  [ "$output" = "missing" ]
}

@test "_git_repo_status reports clean dirty=0 ahead=0 behind=0 on a fresh clone" {
  run _git_repo_status "${CLONE}"
  [ "$status" -eq 0 ]
  [ "$output" = "dirty=0 ahead=0 behind=0" ]
}

@test "_git_repo_status reports dirty=1 when there are uncommitted changes" {
  echo "scratch" > "${CLONE}/scratch.txt"
  run _git_repo_status "${CLONE}"
  [ "$output" = "dirty=1 ahead=0 behind=0" ]
}

@test "_git_repo_status reports ahead after a local commit" {
  git -C "${CLONE}" commit -q --allow-empty -m "local work"
  run _git_repo_status "${CLONE}"
  [ "$output" = "dirty=0 ahead=1 behind=0" ]
}

@test "_git_repo_status reports behind after a push from a second clone WITHOUT fetching first" {
  local second="${TESTDIR}/second-clone"
  git clone -q "${ORIGIN}" "${second}"
  git -C "${second}" commit -q --allow-empty -m "from second machine"
  git -C "${second}" push -q
  # ${CLONE} has NOT fetched — this is the exact regression the fetch-first
  # ordering fixes. Must report behind, not clean.
  run _git_repo_status "${CLONE}"
  [ "$output" = "dirty=0 ahead=0 behind=1" ]
}

@test "_git_repo_status reports diverged as ahead>0 and behind>0" {
  local second="${TESTDIR}/second-clone"
  git clone -q "${ORIGIN}" "${second}"
  git -C "${second}" commit -q --allow-empty -m "from second machine"
  git -C "${second}" push -q
  git -C "${CLONE}" commit -q --allow-empty -m "local unpushed work"
  run _git_repo_status "${CLONE}"
  [ "$output" = "dirty=0 ahead=1 behind=1" ]
}

@test "_git_repo_status reports unreachable when the remote is gone" {
  rm -rf "${ORIGIN}"
  run _git_repo_status "${CLONE}"
  [ "$output" = "unreachable" ]
}

@test "_git_repo_status reports no-upstream when there is no tracking branch" {
  local noup="${TESTDIR}/no-upstream-repo"
  mkdir -p "${noup}"
  git -C "${noup}" init -q
  git -C "${noup}" commit -q --allow-empty -m init
  run _git_repo_status "${noup}"
  [ "$output" = "no-upstream" ]
}

@test "_git_sync_one_repo no-ops on a clean repo" {
  run _git_sync_one_repo "${CLONE}"
  [ "$status" -eq 0 ]
  [ "$(git -C "${CLONE}" rev-parse HEAD)" = "$(git -C "${CLONE}" rev-parse '@{u}')" ]
}

@test "_git_sync_one_repo no-ops (returns 0, no push/pull) when dirty but nothing to sync" {
  echo "scratch" > "${CLONE}/scratch.txt"
  local _before
  _before="$(git -C "${CLONE}" rev-parse HEAD)"
  run _git_sync_one_repo "${CLONE}"
  [ "$status" -eq 0 ]
  [ "$(git -C "${CLONE}" rev-parse HEAD)" = "${_before}" ]
  [ -f "${CLONE}/scratch.txt" ]
}

@test "_git_sync_one_repo pushes when ahead and not dirty" {
  git -C "${CLONE}" commit -q --allow-empty -m "local work"
  run _git_sync_one_repo "${CLONE}"
  [ "$status" -eq 0 ]
  [ "$(git -C "${ORIGIN}" rev-parse master)" = "$(git -C "${CLONE}" rev-parse HEAD)" ]
}

@test "_git_sync_one_repo pushes when ahead EVEN IF dirty (push never touches working tree)" {
  git -C "${CLONE}" commit -q --allow-empty -m "local work"
  echo "scratch" > "${CLONE}/scratch.txt"
  run _git_sync_one_repo "${CLONE}"
  [ "$status" -eq 0 ]
  [ "$(git -C "${ORIGIN}" rev-parse master)" = "$(git -C "${CLONE}" rev-parse HEAD)" ]
  [ -f "${CLONE}/scratch.txt" ]
}

@test "_git_sync_one_repo pulls --ff-only when behind and clean" {
  local second="${TESTDIR}/second-clone"
  git clone -q "${ORIGIN}" "${second}"
  git -C "${second}" commit -q --allow-empty -m "from second machine"
  git -C "${second}" push -q
  run _git_sync_one_repo "${CLONE}"
  [ "$status" -eq 0 ]
  [ "$(git -C "${CLONE}" rev-parse HEAD)" = "$(git -C "${ORIGIN}" rev-parse master)" ]
}

@test "_git_sync_one_repo skips (does not pull) when behind and dirty" {
  local second="${TESTDIR}/second-clone"
  git clone -q "${ORIGIN}" "${second}"
  git -C "${second}" commit -q --allow-empty -m "from second machine"
  git -C "${second}" push -q
  echo "scratch" > "${CLONE}/scratch.txt"
  local _before
  _before="$(git -C "${CLONE}" rev-parse HEAD)"
  run _git_sync_one_repo "${CLONE}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"skipping pull"* ]]
  [ "$(git -C "${CLONE}" rev-parse HEAD)" = "${_before}" ]
}

@test "_git_sync_one_repo skips diverged repos without merging" {
  local second="${TESTDIR}/second-clone"
  git clone -q "${ORIGIN}" "${second}"
  git -C "${second}" commit -q --allow-empty -m "from second machine"
  git -C "${second}" push -q
  git -C "${CLONE}" commit -q --allow-empty -m "local unpushed work"
  local _before
  _before="$(git -C "${CLONE}" rev-parse HEAD)"
  run _git_sync_one_repo "${CLONE}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"diverged"* ]]
  [ "$(git -C "${CLONE}" rev-parse HEAD)" = "${_before}" ]
}

@test "_git_sync_one_repo returns 0 and no-ops on missing path" {
  run _git_sync_one_repo "${TESTDIR}/does-not-exist"
  [ "$status" -eq 0 ]
}

@test "_git_sync_one_repo returns 1 and warns on unreachable remote" {
  rm -rf "${ORIGIN}"
  run _git_sync_one_repo "${CLONE}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unreachable"* ]]
}

@test "_git_sync_one_repo returns 1 and warns when push fails" {
  git -C "${CLONE}" commit -q --allow-empty -m "local work"
  # Fetch (read) still works against a read-only bare origin; push (write)
  # does not — this exercises the push-failure branch without the fetch
  # step itself reporting unreachable first.
  chmod -R -w "${ORIGIN}"
  run _git_sync_one_repo "${CLONE}"
  chmod -R +w "${ORIGIN}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"push failed"* ]]
}

@test "_git_sync_one_repo returns 1 and warns when pull fails" {
  local second="${TESTDIR}/second-clone"
  git clone -q "${ORIGIN}" "${second}"
  git -C "${second}" commit -q --allow-empty -m "from second machine"
  git -C "${second}" push -q
  # A stale index.lock forces git pull's merge/checkout step to fail after
  # fetch has already succeeded (fetch doesn't touch the index).
  touch "${CLONE}/.git/index.lock"
  run _git_sync_one_repo "${CLONE}"
  rm -f "${CLONE}/.git/index.lock"
  [ "$status" -eq 1 ]
  [[ "$output" == *"pull failed"* ]]
}

@test "sync_git_repos discovers repos via find -maxdepth 2 -name .git -type d" {
  local base="${TESTDIR}/fake-personal"
  mkdir -p "${base}/repo-a"
  git init -q --bare "${TESTDIR}/repo-a-origin.git"
  git clone -q "${TESTDIR}/repo-a-origin.git" "${base}/repo-a"
  git -C "${base}/repo-a" commit -q --allow-empty -m init
  git -C "${base}/repo-a" push -q -u origin HEAD:master
  export _OVERRIDE_PERSONAL_GITREPOS="${base}"
  export _OVERRIDE_STATE_LEDGER_DIR="${TESTDIR}/no-ledger"
  run sync_git_repos
  [ "$status" -eq 0 ]
  [[ "$output" == *"repo-a"* ]]
}

@test "sync_git_repos excludes git worktrees (gitdir-file .git, not a directory)" {
  local base="${TESTDIR}/fake-personal-wt"
  mkdir -p "${base}"
  git init -q --bare "${TESTDIR}/wt-origin.git"
  git clone -q "${TESTDIR}/wt-origin.git" "${base}/main-repo"
  git -C "${base}/main-repo" commit -q --allow-empty -m init
  git -C "${base}/main-repo" push -q -u origin HEAD:master
  git -C "${base}/main-repo" worktree add -q "${base}/main-repo-wt" -b wt-branch
  export _OVERRIDE_PERSONAL_GITREPOS="${base}"
  export _OVERRIDE_STATE_LEDGER_DIR="${TESTDIR}/no-ledger"
  run sync_git_repos
  [ "$status" -eq 0 ]
  [[ "$output" == *"main-repo"* ]]
  [[ "$output" != *"main-repo-wt"* ]]
}

@test "sync_git_repos returns 2 when a repo is skipped" {
  local base="${TESTDIR}/fake-personal-dirty"
  mkdir -p "${base}"
  git init -q --bare "${TESTDIR}/dirty-origin.git"
  git clone -q "${TESTDIR}/dirty-origin.git" "${base}/dirty-repo"
  git -C "${base}/dirty-repo" commit -q --allow-empty -m init
  git -C "${base}/dirty-repo" push -q -u origin HEAD:master
  local second="${TESTDIR}/dirty-second"
  git clone -q "${TESTDIR}/dirty-origin.git" "${second}"
  git -C "${second}" commit -q --allow-empty -m "from second machine"
  git -C "${second}" push -q
  echo scratch > "${base}/dirty-repo/scratch.txt"
  export _OVERRIDE_PERSONAL_GITREPOS="${base}"
  export _OVERRIDE_STATE_LEDGER_DIR="${TESTDIR}/no-ledger"
  run sync_git_repos
  [ "$status" -eq 2 ]
}

@test "sync_git_repos returns 0 when everything is already clean" {
  local base="${TESTDIR}/fake-personal-clean"
  mkdir -p "${base}"
  git init -q --bare "${TESTDIR}/clean-origin.git"
  git clone -q "${TESTDIR}/clean-origin.git" "${base}/clean-repo"
  git -C "${base}/clean-repo" commit -q --allow-empty -m init
  git -C "${base}/clean-repo" push -q -u origin HEAD:master
  export _OVERRIDE_PERSONAL_GITREPOS="${base}"
  export _OVERRIDE_STATE_LEDGER_DIR="${TESTDIR}/no-ledger"
  run sync_git_repos
  [ "$status" -eq 0 ]
}

@test "sync_git_repos is idempotent: running twice on a clean tree gives identical exit 0 both times" {
  local base="${TESTDIR}/fake-personal-idempotent"
  mkdir -p "${base}"
  git init -q --bare "${TESTDIR}/idem-origin.git"
  git clone -q "${TESTDIR}/idem-origin.git" "${base}/idem-repo"
  git -C "${base}/idem-repo" commit -q --allow-empty -m init
  git -C "${base}/idem-repo" push -q -u origin HEAD:master
  export _OVERRIDE_PERSONAL_GITREPOS="${base}"
  export _OVERRIDE_STATE_LEDGER_DIR="${TESTDIR}/no-ledger"
  run sync_git_repos
  [ "$status" -eq 0 ]
  run sync_git_repos
  [ "$status" -eq 0 ]
}
