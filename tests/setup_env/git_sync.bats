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
