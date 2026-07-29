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

@test "_git_hooks_digest changes when a single hook file is renamed with identical content (filename folding)" {
  local _repo="${PERSONAL_GITREPOS}/repo-with-target"
  local _hooks_dir="${_repo}/.git/hooks"
  # Deliberately a single file: with two or more files a rename also
  # perturbs sort order, so the digest would change for that reason alone
  # and the test would pass without the filename actually being folded
  # into the hashed material.
  printf '#!/usr/bin/env bash\necho same\n' > "${_hooks_dir}/pre-commit"
  chmod +x "${_hooks_dir}/pre-commit"

  run _git_hooks_digest "${_repo}/"
  local _before="$output"

  mv "${_hooks_dir}/pre-commit" "${_hooks_dir}/pre-push"
  run _git_hooks_digest "${_repo}/"
  local _after="$output"

  [ "${_before}" != "${_after}" ]
}

@test "_git_hooks_digest ignores a broken symlink and a subdirectory in the hooks directory" {
  local _repo="${PERSONAL_GITREPOS}/repo-with-target"
  local _hooks_dir="${_repo}/.git/hooks"
  printf '#!/usr/bin/env bash\necho normal\n' > "${_hooks_dir}/pre-commit"
  chmod +x "${_hooks_dir}/pre-commit"

  run _git_hooks_digest "${_repo}/"
  local _clean_digest="$output"

  ln -s /nonexistent "${_hooks_dir}/broken"
  mkdir -p "${_hooks_dir}/subdir"
  printf 'noise' > "${_hooks_dir}/subdir/noise.txt"

  run _git_hooks_digest "${_repo}/"
  local _with_noise_digest="$output"

  [ "${_clean_digest}" = "${_with_noise_digest}" ]
}

@test "_git_hooks_digest returns the missing-hooks marker for a plain non-git directory (via the non-repo guard)" {
  local _plain="${TESTDIR}/plain-non-git-dir"
  mkdir -p "${_plain}"

  # Guard the guard: if an ancestor git repo exists above this fixture,
  # rev-parse would succeed and this test would exercise the wrong guard
  # (the "! -d hooks dir" guard, already covered by test 11) instead of
  # the "-z hooks path" (not-a-repo-at-all) guard this test targets.
  run git -C "${_plain}" rev-parse --git-dir
  [ "$status" -ne 0 ]

  run _git_hooks_digest "${_plain}/"
  [ "$status" -eq 0 ]
  [ "$output" = "no-hooks-dir" ]
}

@test "_git_hooks_digest follows an absolute --git-path (the worktree shape) via the absolute-path case arm" {
  local _wt_source="${TESTDIR}/abs-path-source"
  mkdir -p "${_wt_source}"
  git init -q "${_wt_source}"
  git -C "${_wt_source}" commit -q --allow-empty -m init
  local _wt="${TESTDIR}/abs-path-worktree"
  git -C "${_wt_source}" worktree add -q -b abs-path-branch "${_wt}"

  # Confirm the premise this test relies on: a worktree's --git-path is
  # absolute (hooks live in the shared common dir, unreachable via a
  # relative join) — this is now the only route to the `/*)` arm, since
  # Major 2's GIT_DIR fix neutralizes the leaked-GIT_DIR route to an
  # absolute path.
  run git -C "${_wt}" rev-parse --git-path hooks
  [[ "$output" == /* ]]

  printf '#!/usr/bin/env bash\necho wt\n' > "${_wt_source}/.git/hooks/pre-commit"
  chmod +x "${_wt_source}/.git/hooks/pre-commit"

  run _git_hooks_digest "${_wt}/"
  [ "$status" -eq 0 ]
  local _wt_digest="$output"
  [[ "${_wt_digest}" =~ ^[0-9a-f]{64}$ ]]

  # Same digest as reading the shared hooks dir directly through the
  # source repo — proving the absolute path was followed correctly
  # rather than mis-joined into a nonexistent relative path (which would
  # have produced "no-hooks-dir", not a matching real digest).
  run _git_hooks_digest "${_wt_source}/"
  [ "$output" = "${_wt_digest}" ]
}

@test "_git_hooks_digest returns a valid non-marker digest for an existing but empty hooks directory" {
  local _repo="${PERSONAL_GITREPOS}/repo-with-target"
  # This is exactly the state after someone clears sample hooks
  # (rm .git/hooks/*.sample) — precisely when auto-install most needs to
  # fire, so it must not be confused with "no hooks directory at all".
  rm -f "${_repo}/.git/hooks"/*

  run _git_hooks_digest "${_repo}/"
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9a-f]{64}$ ]]
  [ "$output" != "no-hooks-dir" ]
}

@test "_git_hooks_check_complete returns 0 and prints nothing for a repo with all three mandated hooks" {
  local _repo="${TESTDIR}/complete-repo"
  mkdir -p "${_repo}"
  git init -q "${_repo}"
  local _hooks_dir="${_repo}/.git/hooks"
  local _hook
  for _hook in pre-commit pre-push commit-msg; do
    printf '#!/usr/bin/env bash\ntrue\n' > "${_hooks_dir}/${_hook}"
    chmod +x "${_hooks_dir}/${_hook}"
  done

  run _git_hooks_check_complete "${_repo}/"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "_git_hooks_check_complete returns 1 and prints commit-msg when only commit-msg is missing" {
  local _repo="${TESTDIR}/missing-commit-msg-repo"
  mkdir -p "${_repo}"
  git init -q "${_repo}"
  local _hooks_dir="${_repo}/.git/hooks"
  printf '#!/usr/bin/env bash\ntrue\n' > "${_hooks_dir}/pre-commit"
  chmod +x "${_hooks_dir}/pre-commit"
  printf '#!/usr/bin/env bash\ntrue\n' > "${_hooks_dir}/pre-push"
  chmod +x "${_hooks_dir}/pre-push"

  run _git_hooks_check_complete "${_repo}/"
  [ "$status" -eq 1 ]
  [[ "$output" == *"commit-msg"* ]]
  [[ "$output" != *"pre-commit"* ]]
  [[ "$output" != *"pre-push"* ]]
}

@test "_git_hooks_check_complete returns 1 and prints both names on exactly one space-separated line when two hooks are missing" {
  local _repo="${TESTDIR}/missing-two-repo"
  mkdir -p "${_repo}"
  git init -q "${_repo}"
  local _hooks_dir="${_repo}/.git/hooks"
  printf '#!/usr/bin/env bash\ntrue\n' > "${_hooks_dir}/pre-commit"
  chmod +x "${_hooks_dir}/pre-commit"

  run _git_hooks_check_complete "${_repo}/"
  [ "$status" -eq 1 ]
  # Exact-shape assertions, not substring matching: printf '%s\n' "${arr[*]}"
  # (one line, space-joined) and printf '%s\n' "${arr[@]}" (one line PER
  # element) both satisfy every *"name"* substring check used elsewhere in
  # this file, so mutating [*] to [@] here survives the whole suite unless
  # something checks the exact line count and exact joined string.
  [ "${#lines[@]}" -eq 1 ]
  [ "$output" = "pre-push commit-msg" ]
}

@test "_git_hooks_check_complete counts a present-but-non-executable hook as missing (the -x guard's false-condition branch)" {
  local _repo="${TESTDIR}/non-exec-repo"
  mkdir -p "${_repo}"
  git init -q "${_repo}"
  local _hooks_dir="${_repo}/.git/hooks"
  printf '#!/usr/bin/env bash\ntrue\n' > "${_hooks_dir}/pre-commit"
  chmod +x "${_hooks_dir}/pre-commit"
  printf '#!/usr/bin/env bash\ntrue\n' > "${_hooks_dir}/pre-push"
  chmod +x "${_hooks_dir}/pre-push"
  printf '#!/usr/bin/env bash\ntrue\n' > "${_hooks_dir}/commit-msg"
  chmod 644 "${_hooks_dir}/commit-msg"

  run _git_hooks_check_complete "${_repo}/"
  [ "$status" -eq 1 ]
  [[ "$output" == *"commit-msg"* ]]
}

@test "_git_hooks_check_complete returns 2 and prints the no-hooks-dir marker when the hooks directory itself is absent" {
  local _repo="${TESTDIR}/no-hooks-dir-repo"
  mkdir -p "${_repo}"
  git init -q "${_repo}"
  rm -rf "${_repo}/.git/hooks"

  run _git_hooks_check_complete "${_repo}/"
  [ "$status" -eq 2 ]
  [ "$output" = "no-hooks-dir" ]
}

@test "_git_hooks_check_complete returns 1 (not 2) and lists all three hooks when the hooks directory exists but is empty" {
  # Distinguishes "hooks directory absent entirely" (rc=2, MAJOR 1's fix)
  # from "hooks directory exists but every hook is missing" (rc=1) --
  # both list the identical hook set, so only the exit code tells them
  # apart. This is precisely the case Task 4 needs to branch on:
  # `make install-hooks` can plausibly fix rc=1 (there's a directory to
  # install into) but cannot fix rc=2 (there is nowhere to install into
  # at all).
  local _repo="${TESTDIR}/empty-hooks-dir-repo"
  mkdir -p "${_repo}"
  git init -q "${_repo}"
  rm -f "${_repo}/.git/hooks"/*

  run _git_hooks_check_complete "${_repo}/"
  [ "$status" -eq 1 ]
  [ "$output" = "pre-commit pre-push commit-msg" ]
}

@test "_git_hooks_check_complete passes when hooks are installed with no scripts/ counterpart at all (the ledger init shape)" {
  local _repo="${TESTDIR}/ledger-shape-repo"
  mkdir -p "${_repo}"
  git init -q "${_repo}"
  local _hooks_dir="${_repo}/.git/hooks"
  local _hook
  for _hook in pre-commit pre-push commit-msg; do
    printf '#!/usr/bin/env bash\ntrue\n' > "${_hooks_dir}/${_hook}"
    chmod +x "${_hooks_dir}/${_hook}"
  done

  # Guard the guard: prove scripts/ genuinely does not exist, so a pass
  # below isn't vacuous — this is exactly the state-ledger shape, where
  # pre-commit arrives via `ledger init` and there is no scripts/pre-commit
  # at all. A source-based check would report a false gap here forever.
  [[ ! -d "${_repo}/scripts" ]]

  run _git_hooks_check_complete "${_repo}/"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "_git_hooks_check_complete honors _git_hooks_dir's return code even when it prints a real, populated path" {
  # Stub _git_hooks_dir to FAIL (return 1) while still printing a path to
  # a real directory that genuinely has all three mandated hooks,
  # executable. This is deliberate: it makes the two possible guard
  # implementations diverge instead of coincidentally agreeing.
  #   - Branch on the return code (correct): the guard fires regardless
  #     of what was printed — status 2, the no-hooks-dir marker.
  #   - Branch on `[[ -z "$_hooks_dir" ]]` (the old, wrong proxy): the
  #     printed path is non-empty, so the guard does NOT fire, the
  #     per-hook loop runs against the real populated directory, finds
  #     every hook executable, and returns 0 with empty output — the
  #     opposite result.
  # A stub that prints nothing (or a nonexistent path) cannot distinguish
  # these two implementations: both the guard and the per-hook loop's
  # fallback report "all missing" either way, which is exactly why the
  # original coincidental-equivalence problem existed in the first place.
  local _fake_hooks_dir="${TESTDIR}/fake-hooks-dir"
  mkdir -p "${_fake_hooks_dir}"
  local _hook
  for _hook in pre-commit pre-push commit-msg; do
    printf '#!/usr/bin/env bash\ntrue\n' > "${_fake_hooks_dir}/${_hook}"
    chmod +x "${_fake_hooks_dir}/${_hook}"
  done

  _git_hooks_dir() {
    printf '%s\n' "${_fake_hooks_dir}"
    return 1
  }

  run _git_hooks_check_complete "${TESTDIR}/irrelevant-repo/"
  [ "$status" -eq 2 ]
  [ "$output" = "no-hooks-dir" ]
}

@test "_git_hooks_gap_repos includes ai-devops (listed, real repo, no Makefile)" {
  run _git_hooks_gap_repos
  [ "$status" -eq 0 ]
  [[ "$output" == *"ai-devops"* ]]
}

@test "_git_hooks_gap_repos excludes repo-unlisted-no-makefile" {
  run _git_hooks_gap_repos
  [ "$status" -eq 0 ]
  [[ "$output" != *"repo-unlisted-no-makefile"* ]]
}

@test "_git_hooks_gap_repos excludes an expected repo that has a Makefile (mutation guard for the Makefile check)" {
  mkdir -p "${PERSONAL_GITREPOS}/math"
  git init -q "${PERSONAL_GITREPOS}/math"
  printf 'install-hooks:\n\t@true\n' > "${PERSONAL_GITREPOS}/math/Makefile"

  run _git_hooks_gap_repos
  [ "$status" -eq 0 ]
  [[ "$output" != *"math"* ]]
  [[ "$output" == *"ai-devops"* ]]
}

@test "_git_hooks_gap_repos excludes an expected-repo name that is a non-git directory (mutation guard for the -d .git check)" {
  mkdir -p "${PERSONAL_GITREPOS}/etch-config"

  run _git_hooks_gap_repos
  [ "$status" -eq 0 ]
  [[ "$output" != *"etch-config"* ]]
}

@test "_git_hooks_gap_repos excludes an expected-repo name that is a linked worktree (mutation guard for the -d vs -e polarity)" {
  # Mirrors _git_hooks_discover's own worktree fixture: a REAL linked
  # worktree, not a synthetic .git-file stand-in. Measured: against a
  # real `git worktree add` under a listed name, `-d .git` correctly
  # excludes it, while `-e .git` (also true for a worktree's .git FILE)
  # would incorrectly admit it -- a genuine behavior difference the
  # rev-parse check does NOT catch, since rev-parse --git-dir genuinely
  # succeeds inside a real worktree.
  local _wt_source="${TESTDIR}/math-source"
  mkdir -p "${_wt_source}"
  git init -q "${_wt_source}"
  git -C "${_wt_source}" commit -q --allow-empty -m init
  git -C "${_wt_source}" worktree add -q -b math-wt-branch "${PERSONAL_GITREPOS}/math"

  run _git_hooks_gap_repos
  [ "$status" -eq 0 ]
  [[ "$output" != *"math"* ]]
}

@test "_git_hooks_gap_repos excludes an expected-repo name that is a partial clone (mutation guard for the rev-parse check)" {
  # .git is a real directory (passes -d .git) but an interrupted/invalid
  # clone — the same shape _git_hooks_discover's partial-clone fixture
  # guards against. -d .git alone is not sufficient evidence of a real
  # repo; this is the spec's own argument, applied to gap_repos too.
  mkdir -p "${PERSONAL_GITREPOS}/terraform_ansible/.git"

  # Guard the guard: if an ancestor git repo exists above this fixture,
  # rev-parse would walk up and succeed, making the exclusion below
  # vacuous.
  run git -C "${PERSONAL_GITREPOS}/terraform_ansible" rev-parse --git-dir
  [ "$status" -ne 0 ]

  run _git_hooks_gap_repos
  [ "$status" -eq 0 ]
  [[ "$output" != *"terraform_ansible"* ]]
}

@test "_git_hooks_gap_repos reports a listed repo entirely absent from disk with a distinct :absent label" {
  # etch-cli is on HOOK_EXPECTED_REPOS but this test's PERSONAL_GITREPOS
  # (built in setup()) never creates a directory for it at all -- the
  # "never cloned" shape. This was previously invisible: [[ -d
  # "${_dir}/.git" ]] fails silently on a directory that doesn't exist,
  # identically to how it fails on a repo that legitimately has no
  # Makefile, with nothing distinguishing "repo missing entirely" from
  # "repo present and fully compliant". It is also invisible to
  # _git_hooks_discover, which has nothing to glob -- this expected-
  # repos list is the only mechanism that can ever catch it.
  run _git_hooks_gap_repos
  [ "$status" -eq 0 ]
  [[ "$output" == *"etch-cli:absent"* ]]
}

@test "_git_hooks_gap_repos distinguishes an absent repo from a no-Makefile repo by label, not just by presence in output" {
  run _git_hooks_gap_repos
  [ "$status" -eq 0 ]
  # ai-devops: real repo, no Makefile -- bare name, unchanged shape.
  [[ "$output" == *"ai-devops"* ]]
  [[ "$output" != *"ai-devops:absent"* ]]
  # etch-cli: no directory at all -- the new distinct label.
  [[ "$output" == *"etch-cli:absent"* ]]
}

@test "_git_hooks_gap_repos prints nothing and returns 0 when HOOK_EXPECTED_REPOS is empty" {
  HOOK_EXPECTED_REPOS=()
  run _git_hooks_gap_repos
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "_git_hooks_discover emits nothing on stderr for a repo with no Makefile" {
  # The `[[ -f Makefile ]]` guard is not a correctness guard — grep exits 2
  # on a missing file, so the repo is excluded either way. Its actual job is
  # keeping grep's "No such file or directory" off stderr during the weekly
  # sweep. Assert that directly, or the guard is only "mutation-visible"
  # because grep's stderr leaks into bats' combined $output.
  local _stderr
  _stderr="$(_git_hooks_discover 2>&1 1>/dev/null)"
  [ -z "${_stderr}" ]
}

# ── Task 4: install_git_hooks_all_repos sweep fixtures ──────────────────────
#
# Deliberately isolated from the shared 9-fixture tree built in setup()
# above: the sweep genuinely invokes `make` (real, not mocked — this file's
# setup() never calls load_mocks) and asserts on real filesystem state
# before/after, so each test below builds its own small PERSONAL_GITREPOS
# tree rather than reusing the Task 1-3 tree's Makefiles, which were never
# written to be run.

# _sweep_build_cp_repo creates REPO_BASE/NAME as a real git repo whose
# install-hooks target really `cp`s three hook files from scripts/ into
# .git/hooks — the real four-of-six-repo shape (repo-structure.md) — and
# writes MARKER_DIR/NAME.ran as its last step. The marker proves the
# recipe genuinely executed; a `make` mock never touches the filesystem
# and would pass an "unchanged ⇒ not updated" assertion for the wrong
# reason (tdd.md section E, mock fidelity).
_sweep_build_cp_repo() {
  local _repo_base="$1" _name="$2" _marker_dir="$3"
  local _repo="${_repo_base}/${_name}"
  mkdir -p "${_repo}/scripts"
  git init -q "${_repo}"
  local _hook
  for _hook in pre-commit pre-push commit-msg; do
    printf '#!/usr/bin/env bash\ntrue\n' > "${_repo}/scripts/${_hook}"
    chmod +x "${_repo}/scripts/${_hook}"
  done
  printf 'install-hooks:\n\tmkdir -p .git/hooks\n\tcp scripts/pre-commit scripts/pre-push scripts/commit-msg .git/hooks/\n\tchmod +x .git/hooks/pre-commit .git/hooks/pre-push .git/hooks/commit-msg\n\ttouch "%s/%s.ran"\n' \
    "${_marker_dir}" "${_name}" > "${_repo}/Makefile"
}

# _sweep_seed_installed pre-installs REPO's hooks by directly cp-ing its own
# scripts/ content into .git/hooks — the "already current" state a
# perfectly up-to-date box is in before the sweep ever runs `make`. Used to
# prove the sweep reports checked-not-updated for a repo whose content
# genuinely does not change across the make call.
_sweep_seed_installed() {
  local _repo="$1"
  mkdir -p "${_repo}/.git/hooks"
  cp "${_repo}/scripts/pre-commit" "${_repo}/scripts/pre-push" "${_repo}/scripts/commit-msg" "${_repo}/.git/hooks/"
  chmod +x "${_repo}/.git/hooks/pre-commit" "${_repo}/.git/hooks/pre-push" "${_repo}/.git/hooks/commit-msg"
}

@test "install_git_hooks_all_repos on a clean tree returns 0 and reports checked equal to the discovered count" {
  local _base="${TESTDIR}/sweep-clean"
  local _markers="${TESTDIR}/sweep-clean-markers"
  mkdir -p "${_base}" "${_markers}"
  _sweep_build_cp_repo "${_base}" "repo-one" "${_markers}"
  _sweep_build_cp_repo "${_base}" "repo-two" "${_markers}"
  _sweep_seed_installed "${_base}/repo-one"
  _sweep_seed_installed "${_base}/repo-two"

  HOOK_EXPECTED_REPOS=()
  PERSONAL_GITREPOS="${_base}" run install_git_hooks_all_repos
  [ "$status" -eq 0 ]
  [[ "$output" == *"2 checked"* ]]
}

# _sweep_build_failing_repo creates a repo whose install-hooks target writes
# its own marker (proving it ran) and then exits 1 — the failure the
# fail-closed loop must survive without stopping the repos discovered
# after it.
_sweep_build_failing_repo() {
  local _repo_base="$1" _name="$2" _marker_dir="$3"
  local _repo="${_repo_base}/${_name}"
  mkdir -p "${_repo}"
  git init -q "${_repo}"
  printf 'install-hooks:\n\ttouch "%s/%s.ran"\n\texit 1\n' \
    "${_marker_dir}" "${_name}" > "${_repo}/Makefile"
}

@test "install_git_hooks_all_repos returns 1 when a repo's make fails, AND every repo discovered after it still ran" {
  # Names are prefixed aaa-/bbb-/ccc- to fix discovery order regardless of
  # locale/glob collation: aaa-failing must be attempted before the other
  # two for this test to prove anything about "after it".
  local _base="${TESTDIR}/sweep-fail"
  local _markers="${TESTDIR}/sweep-fail-markers"
  mkdir -p "${_base}" "${_markers}"
  _sweep_build_failing_repo "${_base}" "aaa-failing" "${_markers}"
  _sweep_build_cp_repo "${_base}" "bbb-ok" "${_markers}"
  _sweep_build_cp_repo "${_base}" "ccc-ok" "${_markers}"

  HOOK_EXPECTED_REPOS=()
  PERSONAL_GITREPOS="${_base}" run install_git_hooks_all_repos
  [ "$status" -eq 1 ]
  [ -f "${_markers}/aaa-failing.ran" ]
  [ -f "${_markers}/bbb-ok.ran" ]
  [ -f "${_markers}/ccc-ok.ran" ]
}

# _sweep_build_loud_repo's recipe line is NOT @-prefixed. Without `-s`, make
# prints the recipe line's own command text ("echo LOUD-RECIPE-MARKER")
# before running it; with `-s` only the command's real stdout
# ("LOUD-RECIPE-MARKER") appears. Only the command-text line distinguishes
# the two — the echoed word itself would appear in the sweep's output
# either way.
_sweep_build_loud_repo() {
  local _repo_base="$1" _name="$2" _marker_dir="$3"
  local _repo="${_repo_base}/${_name}"
  mkdir -p "${_repo}"
  git init -q "${_repo}"
  printf 'install-hooks:\n\techo LOUD-RECIPE-MARKER\n\ttouch "%s/%s.ran"\n' \
    "${_marker_dir}" "${_name}" > "${_repo}/Makefile"
}

@test "install_git_hooks_all_repos invokes make with -s, suppressing the recipe's own command transcript" {
  local _base="${TESTDIR}/sweep-loud"
  local _markers="${TESTDIR}/sweep-loud-markers"
  mkdir -p "${_base}" "${_markers}"
  _sweep_build_loud_repo "${_base}" "loud-repo" "${_markers}"

  HOOK_EXPECTED_REPOS=()
  PERSONAL_GITREPOS="${_base}" run install_git_hooks_all_repos
  [ "$status" -eq 0 ]
  [ -f "${_markers}/loud-repo.ran" ]
  [[ "$output" == *"LOUD-RECIPE-MARKER"* ]]
  [[ "$output" != *"echo LOUD-RECIPE-MARKER"* ]]
}

@test "install_git_hooks_all_repos reports checked-not-updated for a repo whose real cp recipe changes nothing" {
  local _base="${TESTDIR}/sweep-unchanged"
  local _markers="${TESTDIR}/sweep-unchanged-markers"
  mkdir -p "${_base}" "${_markers}"
  _sweep_build_cp_repo "${_base}" "current-repo" "${_markers}"
  # Pre-seed .git/hooks with the SAME bytes the recipe's own cp will write —
  # the "already current" state a perfectly up-to-date box is in. The
  # recipe still genuinely runs (proven by the marker); the point is that
  # its cp is a content no-op.
  _sweep_seed_installed "${_base}/current-repo"

  HOOK_EXPECTED_REPOS=()
  PERSONAL_GITREPOS="${_base}" run install_git_hooks_all_repos
  [ "$status" -eq 0 ]
  [ -f "${_markers}/current-repo.ran" ]
  [[ "$output" == *"0 updated"* ]]
  [[ "$output" != *"current-repo"* ]]
}

# _sweep_build_symlink_repo installs hooks as symlinks into SOURCE_FILE —
# the other two of six real repos' install-hooks shape (`ln -sf`). The
# recipe rewrites SOURCE_FILE's own content as one of its steps, which is a
# deliberate test artifice (plan Task 4: "the ln -sf unchanged branch is
# unfalsifiable by re-running make"): a symlinked hook tracks its source
# continuously, so nothing about re-running `make` alone can ever change
# its digest. This proves the digest mechanism is CAPABLE of seeing a
# symlink-target change; it does not prove the sweep ever observes one in
# production, where nothing mutates the source between the two digest
# reads the sweep takes.
_sweep_build_symlink_repo() {
  local _repo_base="$1" _name="$2" _marker_dir="$3" _source_file="$4"
  local _repo="${_repo_base}/${_name}"
  mkdir -p "${_repo}"
  git init -q "${_repo}"
  printf 'install-hooks:\n\techo mutated > "%s"\n\tmkdir -p .git/hooks\n\tln -sf "%s" .git/hooks/pre-commit\n\tln -sf "%s" .git/hooks/pre-push\n\tln -sf "%s" .git/hooks/commit-msg\n\ttouch "%s/%s.ran"\n' \
    "${_source_file}" "${_source_file}" "${_source_file}" "${_source_file}" "${_marker_dir}" "${_name}" \
    > "${_repo}/Makefile"
}

@test "install_git_hooks_all_repos reports updated for a symlink-install repo when its source is mutated between digests" {
  local _base="${TESTDIR}/sweep-symlink"
  local _markers="${TESTDIR}/sweep-symlink-markers"
  local _source="${TESTDIR}/symlink-hook-source.sh"
  mkdir -p "${_base}" "${_markers}"
  printf '#!/usr/bin/env bash\necho original\n' > "${_source}"
  chmod +x "${_source}"
  _sweep_build_symlink_repo "${_base}" "symlinked-repo" "${_markers}" "${_source}"
  # Pre-install: the symlinks already exist and point at the (as yet
  # unmutated) source, mirroring a box that already ran install-hooks once.
  mkdir -p "${_base}/symlinked-repo/.git/hooks"
  ln -sf "${_source}" "${_base}/symlinked-repo/.git/hooks/pre-commit"
  ln -sf "${_source}" "${_base}/symlinked-repo/.git/hooks/pre-push"
  ln -sf "${_source}" "${_base}/symlinked-repo/.git/hooks/commit-msg"

  HOOK_EXPECTED_REPOS=()
  PERSONAL_GITREPOS="${_base}" run install_git_hooks_all_repos
  [ "$status" -eq 0 ]
  [ -f "${_markers}/symlinked-repo.ran" ]
  [[ "$output" == *"1 updated"* ]]
  [[ "$output" == *"symlinked-repo"* ]]
}

@test "install_git_hooks_all_repos never counts a repo as updated when either digest is digest-error" {
  # commit-msg starts unreadable (mode 000), so the pre-digest is the
  # literal "digest-error" marker. The recipe's own chmod +x repairs it, so
  # the post-digest is a real, DIFFERENT hex digest. Without the explicit
  # "never compare digest-error" guard, a naive "${_pre} != ${_post}"
  # comparison would see two different strings and wrongly count this as
  # updated -- exactly the false-PASS the guard exists to prevent.
  local _base="${TESTDIR}/sweep-digest-error"
  local _markers="${TESTDIR}/sweep-digest-error-markers"
  mkdir -p "${_base}" "${_markers}"
  local _repo="${_base}/broken-repo"
  mkdir -p "${_repo}/.git/hooks"
  git init -q "${_repo}"
  printf '#!/usr/bin/env bash\ntrue\n' > "${_repo}/.git/hooks/pre-commit"
  chmod +x "${_repo}/.git/hooks/pre-commit"
  printf '#!/usr/bin/env bash\ntrue\n' > "${_repo}/.git/hooks/pre-push"
  chmod +x "${_repo}/.git/hooks/pre-push"
  printf 'AAA' > "${_repo}/.git/hooks/commit-msg"
  chmod 000 "${_repo}/.git/hooks/commit-msg"
  printf 'install-hooks:\n\tchmod +x .git/hooks/commit-msg\n\ttouch "%s/broken-repo.ran"\n' \
    "${_markers}" > "${_repo}/Makefile"

  HOOK_EXPECTED_REPOS=()
  PERSONAL_GITREPOS="${_base}" run install_git_hooks_all_repos
  [ "$status" -eq 0 ]
  [ -f "${_markers}/broken-repo.ran" ]
  [[ "$output" == *"0 updated"* ]]
  [[ "$output" != *"broken-repo"* ]]
}

# _sweep_build_partial_repo installs only ONE of the three mandated hooks —
# the state-ledger shape: `make install-hooks` exits 0 (the target ran
# cleanly), but the repo's hooks directory is still incomplete. This is a
# post-condition gap (_git_hooks_check_complete rc=1), not a make failure.
_sweep_build_partial_repo() {
  local _repo_base="$1" _name="$2" _marker_dir="$3"
  local _repo="${_repo_base}/${_name}"
  mkdir -p "${_repo}"
  git init -q "${_repo}"
  printf 'install-hooks:\n\tmkdir -p .git/hooks\n\techo pushonly > .git/hooks/pre-push\n\tchmod +x .git/hooks/pre-push\n\ttouch "%s/%s.ran"\n' \
    "${_marker_dir}" "${_name}" > "${_repo}/Makefile"
}

@test "install_git_hooks_all_repos counts an incomplete-hook-set repo as a gap, not a failure, and warns" {
  local _base="${TESTDIR}/sweep-partial"
  local _markers="${TESTDIR}/sweep-partial-markers"
  mkdir -p "${_base}" "${_markers}"
  _sweep_build_partial_repo "${_base}" "partial-repo" "${_markers}"

  HOOK_EXPECTED_REPOS=()
  PERSONAL_GITREPOS="${_base}" run install_git_hooks_all_repos
  [ "$status" -eq 0 ]
  [ -f "${_markers}/partial-repo.ran" ]
  [[ "$output" == *"1 gaps"* ]]
  [[ "$output" == *"[WARN]"* ]]
  [[ "$output" == *"partial-repo"* ]]
  [[ "$output" == *"pre-commit"* ]]
  [[ "$output" == *"commit-msg"* ]]
}

@test "install_git_hooks_all_repos labels a no-hooks-directory gap (rc=2) distinctly from a missing-hooks gap (rc=1)" {
  # Collapsing rc=1 and rc=2 into one label is the exact failure the
  # tri-state check_complete contract exists to prevent: rc=1 is a gap
  # `make install-hooks` can plausibly fix (there's a directory to install
  # into); rc=2 means there is nowhere to install into at all, so telling
  # the operator to re-run the same command is unactionable advice printed
  # weekly forever.
  local _base="${TESTDIR}/sweep-rc-distinct"
  local _markers="${TESTDIR}/sweep-rc-distinct-markers"
  mkdir -p "${_base}" "${_markers}"

  _sweep_build_partial_repo "${_base}" "partial-hooks-repo" "${_markers}"

  local _no_dir_repo="${_base}/no-hooks-dir-repo"
  mkdir -p "${_no_dir_repo}"
  git init -q "${_no_dir_repo}"
  rm -rf "${_no_dir_repo}/.git/hooks"
  printf 'install-hooks:\n\ttouch "%s/no-hooks-dir-repo.ran"\n' "${_markers}" > "${_no_dir_repo}/Makefile"

  HOOK_EXPECTED_REPOS=()
  PERSONAL_GITREPOS="${_base}" run install_git_hooks_all_repos
  [ "$status" -eq 0 ]
  [ -f "${_markers}/partial-hooks-repo.ran" ]
  [ -f "${_markers}/no-hooks-dir-repo.ran" ]
  [[ "$output" == *"2 gaps"* ]]
  [[ "$output" == *"partial-hooks-repo: missing pre-commit commit-msg"* ]]
  [[ "$output" == *"no-hooks-dir-repo: no hooks directory"* ]]
}

@test "install_git_hooks_all_repos names gap repos from _git_hooks_gap_repos in the summary line, without affecting the return code" {
  local _base="${TESTDIR}/sweep-gap-repos"
  mkdir -p "${_base}"
  # real repo, no Makefile at all — the bare-name gap shape.
  mkdir -p "${_base}/no-makefile-repo"
  git init -q "${_base}/no-makefile-repo"
  # never-cloned — no directory on disk at all for this listed name.

  HOOK_EXPECTED_REPOS=(no-makefile-repo never-cloned-repo)
  PERSONAL_GITREPOS="${_base}" run install_git_hooks_all_repos
  [ "$status" -eq 0 ]
  [[ "$output" == *"0 checked"* ]]
  [[ "$output" == *"2 gaps"* ]]
  [[ "$output" == *"no-makefile-repo: no Makefile"* ]]
  [[ "$output" == *"never-cloned-repo: never cloned"* ]]
}

@test "install_git_hooks_all_repos under DRY_RUN never invokes make and reports the updated count as n/a" {
  local _base="${TESTDIR}/sweep-dry-run"
  local _markers="${TESTDIR}/sweep-dry-run-markers"
  mkdir -p "${_base}" "${_markers}"
  _sweep_build_cp_repo "${_base}" "repo-one" "${_markers}"
  _sweep_build_cp_repo "${_base}" "repo-two" "${_markers}"

  HOOK_EXPECTED_REPOS=()
  DRY_RUN=1 PERSONAL_GITREPOS="${_base}" run install_git_hooks_all_repos
  [ "$status" -eq 0 ]
  # run_cmd only prints under DRY_RUN -- neither recipe's own marker touch
  # ever executes, proving make itself was never really invoked.
  [ ! -f "${_markers}/repo-one.ran" ]
  [ ! -f "${_markers}/repo-two.ran" ]
  [[ "$output" == *"2 checked"* ]]
  [[ "$output" == *"n/a updated"* ]]
  [[ "$output" != *"0 updated"* ]]
}
