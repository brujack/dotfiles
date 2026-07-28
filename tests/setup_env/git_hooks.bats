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

  # 6. partial-clone — .git is a real but empty/invalid directory (interrupted
  # clone). No ancestor git repository must exist above this fixture, or
  # rev-parse would walk upward and find one — asserted explicitly below.
  mkdir -p "${PERSONAL_GITREPOS}/partial-clone/.git"
  printf 'install-hooks:\n\t@true\n' > "${PERSONAL_GITREPOS}/partial-clone/Makefile"

  # 3. worktree-dir — .git is a regular file (gitdir pointer), not a directory
  mkdir -p "${PERSONAL_GITREPOS}/worktree-dir"
  printf 'gitdir: /somewhere\n' > "${PERSONAL_GITREPOS}/worktree-dir/.git"

  # 2. repo-no-target — real repo, Makefile present but no install-hooks target
  mkdir -p "${PERSONAL_GITREPOS}/repo-no-target"
  git init -q "${PERSONAL_GITREPOS}/repo-no-target"
  printf 'lint:\n\t@true\n' > "${PERSONAL_GITREPOS}/repo-no-target/Makefile"

  # 8. ai-devops — real repo, no Makefile, name IS on HOOK_EXPECTED_REPOS
  mkdir -p "${PERSONAL_GITREPOS}/ai-devops"
  git init -q "${PERSONAL_GITREPOS}/ai-devops"

  # 9. repo-unlisted-no-makefile — real repo, no Makefile, name NOT on the list
  mkdir -p "${PERSONAL_GITREPOS}/repo-unlisted-no-makefile"
  git init -q "${PERSONAL_GITREPOS}/repo-unlisted-no-makefile"
}

@test "HOOK_EXPECTED_REPOS is populated after sourcing lib/git_hooks.sh" {
  [ "${#HOOK_EXPECTED_REPOS[@]}" -gt 0 ]
}

@test "_git_hooks_discover excludes plain-dir (no .git at all)" {
  run _git_hooks_discover
  [ "$status" -eq 0 ]
  [[ "$output" != *"plain-dir"* ]]
}

@test "_git_hooks_discover excludes partial-clone (passes -d .git, fails rev-parse)" {
  # Guard the guard: if this fails, the fixture has an ancestor git repo and
  # the exclusion assertion below would be vacuous.
  run git -C "${PERSONAL_GITREPOS}/partial-clone" rev-parse --git-dir
  [ "$status" -ne 0 ]

  run _git_hooks_discover
  [ "$status" -eq 0 ]
  [[ "$output" != *"partial-clone"* ]]
}

@test "_git_hooks_discover excludes worktree-dir (.git is a file, not a directory)" {
  run _git_hooks_discover
  [ "$status" -eq 0 ]
  [[ "$output" != *"worktree-dir"* ]]
}

@test "_git_hooks_discover excludes repo-no-target (Makefile present, no install-hooks target)" {
  run _git_hooks_discover
  [ "$status" -eq 0 ]
  [[ "$output" != *"repo-no-target"* ]]
}

@test "_git_hooks_discover excludes repo-listed-no-makefile and repo-unlisted-no-makefile" {
  run _git_hooks_discover
  [ "$status" -eq 0 ]
  [[ "$output" != *"ai-devops"* ]]
  [[ "$output" != *"repo-unlisted-no-makefile"* ]]
}
