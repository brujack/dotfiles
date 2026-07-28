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

  # 4. plain-dir — no .git at all. Carries a qualifying Makefile so only the
  # -d .git guard (not the later Makefile-target guard) can exclude it —
  # otherwise its exclusion is over-determined and mutation-invisible.
  mkdir -p "${PERSONAL_GITREPOS}/plain-dir"
  printf 'install-hooks:\n\t@true\n' > "${PERSONAL_GITREPOS}/plain-dir/Makefile"

  # 6. partial-clone — .git is a real but empty/invalid directory (interrupted
  # clone). No ancestor git repository must exist above this fixture, or
  # rev-parse would walk upward and find one — asserted explicitly below.
  mkdir -p "${PERSONAL_GITREPOS}/partial-clone/.git"
  printf 'install-hooks:\n\t@true\n' > "${PERSONAL_GITREPOS}/partial-clone/Makefile"

  # 3. worktree-dir — a REAL linked git worktree, not a synthetic gitdir-file
  # stand-in. A synthetic ".git file pointing nowhere" fails rev-parse for
  # the wrong reason (bad path) rather than the reason production cares
  # about — rev-parse --git-dir genuinely SUCCEEDS inside a real worktree
  # (this is the ai-config-hook-integrity hazard), so only -d .git can
  # exclude it. The worktree inherits its Makefile from the source repo it
  # was created from, giving it a qualifying install-hooks: target too.
  local _wt_source="${TESTDIR}/wt-source"
  mkdir -p "${_wt_source}"
  git init -q "${_wt_source}"
  printf 'install-hooks:\n\t@true\n' > "${_wt_source}/Makefile"
  git -C "${_wt_source}" add Makefile
  git -C "${_wt_source}" commit -q -m init
  git -C "${_wt_source}" worktree add -q "${PERSONAL_GITREPOS}/worktree-dir" -b wt-branch

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

  # 5. repo-failing — real repo, install-hooks target present but exits 1.
  # Discovery only checks for the target's presence, not its exit behaviour
  # (running it is Task 4's job), so this fixture is discovered like any
  # other qualifying repo.
  mkdir -p "${PERSONAL_GITREPOS}/repo-failing"
  git init -q "${PERSONAL_GITREPOS}/repo-failing"
  printf 'install-hooks:\n\t@exit 1\n' > "${PERSONAL_GITREPOS}/repo-failing/Makefile"

  # 7. repo-partial-hooks — real repo, target present, installs pre-push only
  # (the state-ledger shape). Content of the recipe is irrelevant to
  # discovery; only the target's presence is checked here.
  mkdir -p "${PERSONAL_GITREPOS}/repo-partial-hooks"
  git init -q "${PERSONAL_GITREPOS}/repo-partial-hooks"
  printf 'install-hooks:\n\t@true\n' > "${PERSONAL_GITREPOS}/repo-partial-hooks/Makefile"
}

@test "HOOK_EXPECTED_REPOS is populated after sourcing lib/git_hooks.sh" {
  [ "${#HOOK_EXPECTED_REPOS[@]}" -gt 0 ]
}

@test "sourcing lib/git_hooks.sh twice produces empty stderr and leaves HOOK_EXPECTED_REPOS non-empty" {
  local _stderr
  _stderr="$(source "${REPO_ROOT}/lib/git_hooks.sh" 2>&1 1>/dev/null)"
  [ -z "${_stderr}" ]
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

@test "_git_hooks_discover excludes ai-devops (listed, no Makefile) and repo-unlisted-no-makefile" {
  run _git_hooks_discover
  [ "$status" -eq 0 ]
  [[ "$output" != *"ai-devops"* ]]
  [[ "$output" != *"repo-unlisted-no-makefile"* ]]
}

@test "_git_hooks_discover discovers repo-with-target, repo-failing, and repo-partial-hooks" {
  run _git_hooks_discover
  [ "$status" -eq 0 ]
  [[ "$output" == *"repo-with-target"* ]]
  [[ "$output" == *"repo-failing"* ]]
  [[ "$output" == *"repo-partial-hooks"* ]]
}

@test "_git_hooks_discover prints nothing and returns 0 for an empty PERSONAL_GITREPOS" {
  local _empty="${TESTDIR}/empty-personal"
  mkdir -p "${_empty}"
  PERSONAL_GITREPOS="${_empty}" run _git_hooks_discover
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "_git_hooks_discover behaves the same for a single-qualifying-repo tree as a multi-repo tree" {
  local _solo="${TESTDIR}/solo-personal"
  mkdir -p "${_solo}/only-repo"
  git init -q "${_solo}/only-repo"
  printf 'install-hooks:\n\t@true\n' > "${_solo}/only-repo/Makefile"

  PERSONAL_GITREPOS="${_solo}" run _git_hooks_discover
  [ "$status" -eq 0 ]
  [[ "$output" == *"only-repo"* ]]
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq 1 ]
}
