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

@test "_git_hooks_digest returns 0 and prints a stable marker for a repo with no hooks directory" {
  local _repo="${TESTDIR}/no-hooks-repo"
  mkdir -p "${_repo}"
  git init -q "${_repo}"
  rm -rf "${_repo}/.git/hooks"

  run _git_hooks_digest "${_repo}/"
  [ "$status" -eq 0 ]
  [ "$output" = "no-hooks-dir" ]

  run _git_hooks_digest "${_repo}/"
  [ "$status" -eq 0 ]
  [ "$output" = "no-hooks-dir" ]
}

@test "_git_hooks_digest returns identical, non-marker digests across two calls with no change" {
  local _repo="${PERSONAL_GITREPOS}/repo-with-target"
  local _hooks_dir="${_repo}/.git/hooks"
  printf '#!/usr/bin/env bash\necho one\n' > "${_hooks_dir}/pre-commit"
  chmod +x "${_hooks_dir}/pre-commit"

  run _git_hooks_digest "${_repo}/"
  [ "$status" -eq 0 ]
  local _first="$output"
  [ "${_first}" != "no-hooks-dir" ]
  [[ "${_first}" =~ ^[0-9a-f]{64}$ ]]

  run _git_hooks_digest "${_repo}/"
  [ "$status" -eq 0 ]
  [ "$output" = "${_first}" ]
}

@test "_git_hooks_digest changes when a hook's content is mutated (load-bearing)" {
  local _repo="${PERSONAL_GITREPOS}/repo-with-target"
  local _hooks_dir="${_repo}/.git/hooks"
  printf '#!/usr/bin/env bash\necho one\n' > "${_hooks_dir}/pre-commit"
  chmod +x "${_hooks_dir}/pre-commit"

  run _git_hooks_digest "${_repo}/"
  local _before="$output"

  printf '#!/usr/bin/env bash\necho two\n' > "${_hooks_dir}/pre-commit"
  run _git_hooks_digest "${_repo}/"
  local _after="$output"

  [ "${_before}" != "${_after}" ]
}

@test "_git_hooks_digest changes when a hook file is added" {
  local _repo="${PERSONAL_GITREPOS}/repo-with-target"
  local _hooks_dir="${_repo}/.git/hooks"
  printf '#!/usr/bin/env bash\necho one\n' > "${_hooks_dir}/pre-commit"
  chmod +x "${_hooks_dir}/pre-commit"

  run _git_hooks_digest "${_repo}/"
  local _before="$output"

  printf '#!/usr/bin/env bash\necho commit-msg\n' > "${_hooks_dir}/commit-msg"
  chmod +x "${_hooks_dir}/commit-msg"
  run _git_hooks_digest "${_repo}/"
  local _after="$output"

  [ "${_before}" != "${_after}" ]
}

@test "_git_hooks_digest changes when a hook file is removed" {
  local _repo="${PERSONAL_GITREPOS}/repo-with-target"
  local _hooks_dir="${_repo}/.git/hooks"
  printf '#!/usr/bin/env bash\necho one\n' > "${_hooks_dir}/pre-commit"
  chmod +x "${_hooks_dir}/pre-commit"
  printf '#!/usr/bin/env bash\necho push\n' > "${_hooks_dir}/pre-push"
  chmod +x "${_hooks_dir}/pre-push"

  run _git_hooks_digest "${_repo}/"
  local _before="$output"

  rm -f "${_hooks_dir}/pre-push"
  run _git_hooks_digest "${_repo}/"
  local _after="$output"

  [ "${_before}" != "${_after}" ]
}

@test "_git_hooks_digest of a symlinked hook reflects its target's content, not the link path" {
  local _repo="${PERSONAL_GITREPOS}/repo-with-target"
  local _hooks_dir="${_repo}/.git/hooks"
  local _source="${TESTDIR}/hook-source.sh"
  printf '#!/usr/bin/env bash\necho symlinked\n' > "${_source}"
  ln -sf "${_source}" "${_hooks_dir}/pre-commit"

  run _git_hooks_digest "${_repo}/"
  local _linked_digest="$output"

  # Mutate the symlink TARGET (never the link itself). A content-based
  # digest must change; a path/metadata-based digest would not.
  printf '#!/usr/bin/env bash\necho mutated\n' > "${_source}"
  run _git_hooks_digest "${_repo}/"
  local _after_target_mutate="$output"
  [ "${_linked_digest}" != "${_after_target_mutate}" ]

  # Restore the target, then replace the symlink with a REGULAR file
  # holding the ORIGINAL bytes. The digest must equal the original
  # symlinked digest, proving the hash is over the target's bytes, not
  # over "is this a symlink" or the link's own path string.
  printf '#!/usr/bin/env bash\necho symlinked\n' > "${_source}"
  rm -f "${_hooks_dir}/pre-commit"
  printf '#!/usr/bin/env bash\necho symlinked\n' > "${_hooks_dir}/pre-commit"
  chmod +x "${_hooks_dir}/pre-commit"
  run _git_hooks_digest "${_repo}/"
  local _regular_digest="$output"

  [ "${_linked_digest}" = "${_regular_digest}" ]
}

@test "_git_hooks_digest is unchanged when a real cp rewrites a hook with identical content" {
  local _repo="${PERSONAL_GITREPOS}/repo-with-target"
  local _hooks_dir="${_repo}/.git/hooks"
  local _source="${TESTDIR}/identical-hook.sh"
  printf '#!/usr/bin/env bash\necho identical\n' > "${_source}"
  cp "${_source}" "${_hooks_dir}/pre-commit"
  chmod +x "${_hooks_dir}/pre-commit"

  run _git_hooks_digest "${_repo}/"
  local _before="$output"

  local _mtime_before
  _mtime_before=$(stat -f '%m' "${_hooks_dir}/pre-commit" 2>/dev/null || stat -c '%Y' "${_hooks_dir}/pre-commit")
  sleep 1
  cp "${_source}" "${_hooks_dir}/pre-commit"
  local _mtime_after
  _mtime_after=$(stat -f '%m' "${_hooks_dir}/pre-commit" 2>/dev/null || stat -c '%Y' "${_hooks_dir}/pre-commit")

  # Guard the guard: prove cp genuinely rewrote mtime, so a pass below isn't
  # vacuous because nothing actually changed on disk.
  [ "${_mtime_before}" != "${_mtime_after}" ]

  run _git_hooks_digest "${_repo}/"
  local _after="$output"

  [ "${_before}" = "${_after}" ]
}

@test "_git_hooks_digest fails closed with a non-hex marker when a hook file is unreadable" {
  local _repo="${PERSONAL_GITREPOS}/repo-with-target"
  local _hooks_dir="${_repo}/.git/hooks"
  printf 'AAA' > "${_hooks_dir}/pre-commit"
  chmod 000 "${_hooks_dir}/pre-commit"

  run _git_hooks_digest "${_repo}/"
  local _status_a="$status"
  local _output_a="$output"
  chmod 755 "${_hooks_dir}/pre-commit"

  [ "${_status_a}" -eq 1 ]
  [[ ! "${_output_a}" =~ ^[0-9a-f]{64}$ ]]
}

@test "_git_hooks_digest never fabricates a valid-looking digest collision across two different unreadable hook sets" {
  local _repo="${PERSONAL_GITREPOS}/repo-with-target"
  local _hooks_dir="${_repo}/.git/hooks"

  printf 'AAA' > "${_hooks_dir}/pre-commit"
  printf 'BBB' > "${_hooks_dir}/pre-push"
  chmod 000 "${_hooks_dir}/pre-commit" "${_hooks_dir}/pre-push"
  run _git_hooks_digest "${_repo}/"
  local _status_a="$status"
  local _output_a="$output"
  chmod 755 "${_hooks_dir}/pre-commit" "${_hooks_dir}/pre-push"

  printf 'ZZZ' > "${_hooks_dir}/pre-commit"
  printf 'QQQ' > "${_hooks_dir}/pre-push"
  chmod 000 "${_hooks_dir}/pre-commit" "${_hooks_dir}/pre-push"
  run _git_hooks_digest "${_repo}/"
  local _status_b="$status"
  local _output_b="$output"
  chmod 755 "${_hooks_dir}/pre-commit" "${_hooks_dir}/pre-push"

  # The bug this guards: unreadable content used to hash to an empty
  # string for both sets, producing a genuine, identical, valid-looking
  # sha256 digest for completely different content (measured: both
  # digested to 7d67336...). Post-fix, neither call may succeed with a
  # real digest at all — fail-closed status 1 plus a non-hex marker means
  # no caller can ever mistake these two calls as "content equal", which
  # is the property that actually matters. A shared literal error marker
  # across two independent failures is fine; a shared VALID digest across
  # two different real contents is the bug.
  [ "${_status_a}" -eq 1 ]
  [ "${_status_b}" -eq 1 ]
  [[ ! "${_output_a}" =~ ^[0-9a-f]{64}$ ]]
  [[ ! "${_output_b}" =~ ^[0-9a-f]{64}$ ]]
}

@test "_git_hooks_digest ignores a leaked GIT_DIR and always reads the repo named by its own argument" {
  local _repo_a="${TESTDIR}/git-dir-leak-a"
  local _repo_b="${TESTDIR}/git-dir-leak-b"
  mkdir -p "${_repo_a}" "${_repo_b}"
  git init -q "${_repo_a}"
  git init -q "${_repo_b}"
  printf '#!/usr/bin/env bash\necho a\n' > "${_repo_a}/.git/hooks/pre-commit"
  chmod +x "${_repo_a}/.git/hooks/pre-commit"
  printf '#!/usr/bin/env bash\necho b\n' > "${_repo_b}/.git/hooks/pre-commit"
  chmod +x "${_repo_b}/.git/hooks/pre-commit"

  run _git_hooks_digest "${_repo_a}/"
  local _expected_a="$output"
  run _git_hooks_digest "${_repo_b}/"
  local _expected_b="$output"

  # Guard the guard: if A and B happen to collide, the assertions below
  # would pass even with the bug present.
  [ "${_expected_a}" != "${_expected_b}" ]

  # This simulates the documented pre-push/worktree GIT_DIR leak
  # (git-workflow.md): a caller in this process has GIT_DIR exported
  # pointing at repo B's .git while asking to digest repo A. Without the
  # fix, -C is silently overridden and this returns repo B's digest.
  GIT_DIR="${_repo_b}/.git" run _git_hooks_digest "${_repo_a}/"
  [ "$status" -eq 0 ]
  [ "$output" = "${_expected_a}" ]
}

@test "_git_hooks_discover ignores a leaked GIT_DIR and still excludes partial-clone" {
  local _leak_source="${TESTDIR}/leak-source"
  mkdir -p "${_leak_source}"
  git init -q "${_leak_source}"

  # Without the fix, an exported GIT_DIR pointing at a real repo makes
  # `git -C partial-clone rev-parse --git-dir` succeed regardless of
  # partial-clone's own (broken) .git — silently defeating the exclusion
  # this guard exists for (measured: exit 128 normally, exit 0 leaked).
  GIT_DIR="${_leak_source}/.git" run _git_hooks_discover
  [ "$status" -eq 0 ]
  [[ "$output" != *"partial-clone"* ]]
}
