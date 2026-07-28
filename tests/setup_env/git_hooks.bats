#!/usr/bin/env bats

load '../helpers/common.bash'

setup() {
  load_setup_env
  # lib/git_hooks.sh isn't wired into setup_env.sh's source chain until a
  # later task — source it explicitly so this file is self-contained.
  # shellcheck disable=SC1091
  source "${REPO_ROOT}/lib/git_hooks.sh"

  export GIT_AUTHOR_NAME="bats" GIT_AUTHOR_EMAIL="bats@example.com"
  export GIT_COMMITTER_NAME="bats" GIT_COMMITTER_EMAIL="bats@example.com"

  export TESTDIR="${BATS_TEST_TMPDIR}"
  export PERSONAL_GITREPOS="${TESTDIR}/personal"
  mkdir -p "${PERSONAL_GITREPOS}"

  # 1. repo-with-target — real repo, Makefile carries install-hooks:
  mkdir -p "${PERSONAL_GITREPOS}/repo-with-target"
  git init -q "${PERSONAL_GITREPOS}/repo-with-target"
  printf 'install-hooks:\n\t@true\n' > "${PERSONAL_GITREPOS}/repo-with-target/Makefile"

  # 4. plain-dir — no .git at all
  mkdir -p "${PERSONAL_GITREPOS}/plain-dir"
}

@test "HOOK_EXPECTED_REPOS is populated after sourcing lib/git_hooks.sh" {
  [ "${#HOOK_EXPECTED_REPOS[@]}" -gt 0 ]
}

@test "_git_hooks_discover excludes plain-dir (no .git at all)" {
  run _git_hooks_discover
  [ "$status" -eq 0 ]
  [[ "$output" != *"plain-dir"* ]]
}
