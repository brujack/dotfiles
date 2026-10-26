#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  CLEAN_PATH="$(printf "%s" "${PATH}" | tr ':' '\n' | grep -v "tests/mocks" | tr '\n' ':' | sed 's/:$//')"
  REPO_DIR="${BATS_TEST_TMPDIR}/repo"
  MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  MAKE_MOCK_DIR="${BATS_TEST_TMPDIR}/makebin"
  source "${REPO_ROOT}/tests/helpers/new_session.bash"
  export TMPDIR="${BATS_TEST_TMPDIR}/tmp"
  mkdir -p "${REPO_DIR}" "${MAKE_MOCK_DIR}" "${TMPDIR}"
  bash -c "
    export PATH='${CLEAN_PATH}'
    unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE
    git -C '${REPO_DIR}' init --quiet
    git -C '${REPO_DIR}' config user.email 'test@test.com'
    git -C '${REPO_DIR}' config user.name 'Test'
  "
}

# _canon <dir> -- physical (symlink-resolved) path, as git rev-parse prints it.
_canon() { (cd "$1" && pwd -P); }

# _assert_make_ran -- the hook ran make against REPO_DIR's canonical path, as an
# exact whole-line match. Substitution stays off the grep line so
# makefile_lint_scope.bats's grep-led-line exemption applies.
_assert_make_ran() {
  local _dir
  _dir="$(_canon "${REPO_DIR}")"
  grep -qxF "make -C ${_dir} test" "${MOCK_CALLS_FILE}" && return 0
  printf 'expected the suite to run in %s; mock calls:\n' "${_dir}" >&2
  if [[ -f "${MOCK_CALLS_FILE}" ]]; then
    cat "${MOCK_CALLS_FILE}" >&2
  else
    printf '<no mock calls file>\n' >&2
  fi
  return 1
}

teardown() {
  # A test may leave a read-only directory under TMPDIR; bats must still clean up.
  if [[ "${TMPDIR:-}" == "${BATS_TEST_TMPDIR}"/* ]]; then
    chmod -R u+w "${TMPDIR}" 2>/dev/null || :
  fi
  rm -f "${MOCK_CALLS_FILE:-}"
}

# The mock records its arguments. With MAKE_MOCK_RECORD_TREE=1 it also records,
# for its -C directory, the physical path, HEAD, porcelain status (bracketed)
# and the locked/listed worktrees of REPO_DIR as seen while it runs. With
# MAKE_MOCK_REQUIRE_FILE set it exits 1 unless that file in the -C directory
# holds MAKE_MOCK_REQUIRE_CONTENT.
_write_make_mock() {
  local _exit="${1:-0}"
  cat > "${MAKE_MOCK_DIR}/make" <<EOF
#!/usr/bin/env bash
printf "make %s\n" "\$*" >> "${MOCK_CALLS_FILE}"
if [[ "\${MAKE_MOCK_RECORD_TREE:-}" == 1 && "\$1" == -C ]]; then
  _d="\$2"
  printf 'tree_dir %s\n' "\$(cd "\${_d}" && pwd -P)" >> "${MOCK_CALLS_FILE}"
  printf 'tree_head %s\n' "\$(git -C "\${_d}" rev-parse HEAD)" >> "${MOCK_CALLS_FILE}"
  printf 'tree_status [%s]\n' "\$(git -C "\${_d}" status --porcelain)" >> "${MOCK_CALLS_FILE}"
  git -C "${REPO_DIR}" worktree list --porcelain | sed -n 's/^locked /tree_lock /p' >> "${MOCK_CALLS_FILE}"
  git -C "${REPO_DIR}" worktree list --porcelain | sed -n 's/^worktree /tree_listed /p' >> "${MOCK_CALLS_FILE}"
fi
if [[ -n "\${MAKE_MOCK_SIGNAL:-}" ]]; then
  kill -"\${MAKE_MOCK_SIGNAL}" 0
  sleep 10
fi
if [[ -n "\${MAKE_MOCK_UNDELETABLE:-}" && "\$1" == -C ]]; then
  mkdir -p "\$2/ro"
  : > "\$2/ro/x"
  chmod 0555 "\$2/ro"
fi
if [[ -n "\${MAKE_MOCK_REQUIRE_FILE:-}" ]]; then
  [[ "\$(cat "\$2/\${MAKE_MOCK_REQUIRE_FILE}")" == "\${MAKE_MOCK_REQUIRE_CONTENT}" ]] || exit 1
fi
exit ${_exit}
EOF
  chmod +x "${MAKE_MOCK_DIR}/make"
}

_commit_file() {
  local _path="${1}" _content="${2}" _msg="${3}"
  bash -c "
    export PATH='${CLEAN_PATH}'
    unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE
    mkdir -p \"\$(dirname '${REPO_DIR}/${_path}')\"
    printf '%s\n' '${_content}' > '${REPO_DIR}/${_path}'
    git -C '${REPO_DIR}' add '${_path}'
    git -C '${REPO_DIR}' commit --quiet -m '${_msg}'
    git -C '${REPO_DIR}' rev-parse HEAD
  "
}

# These cases push to a FEATURE ref, not master, and that is deliberate. Their
# subject is the inert set -- does this path make the suite run -- not master
# policy. They used refs/heads/master incidentally until the direct-to-master
# guard landed, at which point every one of them would have been answered by
# the refusal instead of by the thing they assert. Do not switch them back.
_run_pre_push() {
  local _stdin="${1}"
  local _path_with_make="${MAKE_MOCK_DIR}:${CLEAN_PATH}"
  printf "%b" "${_stdin}" | bash -c "
    export PATH='${_path_with_make}'
    unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE
    cd '${REPO_DIR}' && bash '${REPO_ROOT}/scripts/pre-push'
  "
}

@test "pre-push skips the test run when only non-triggering files changed" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file "README.md" "v2" "docs: v2")
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 0 ]
  [ ! -f "${MOCK_CALLS_FILE}" ]
}

@test "pre-push runs make test when a .sh file changed" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file "deploy.sh" "echo hi" "feat: add deploy script")
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 0 ]
  _assert_make_ran
}

@test "pre-push runs make test when only scripts/pre-push changed" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file "scripts/pre-push" "# hook" "chore: touch hook")
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 0 ]
  _assert_make_ran
}

@test "pre-push runs make test when only scripts/commit-msg changed" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file "scripts/commit-msg" "# hook" "chore: touch hook")
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 0 ]
  _assert_make_ran
}

@test "pre-push runs make test when only a .zsh file changed" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file ".config/.zshrc.d/2_functions.zsh" "echo hi" "feat: add a zsh function")
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 0 ]
  _assert_make_ran
}

@test "pre-push runs make test when only .shellcheckrc changed" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file ".shellcheckrc" "disable=SC2086" "chore: touch shellcheckrc")
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 0 ]
  _assert_make_ran
}

@test "pre-push runs make test when only .gitignore changed" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file ".gitignore" "*.log" "chore: touch gitignore")
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 0 ]
  _assert_make_ran
}

@test "pre-push triggers on a non-markdown file under docs/, not just .gitignore" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file "docs/.gitignore" "*.log" "chore: nested gitignore")
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 0 ]
  _assert_make_ran
}

@test "pre-push triggers on a root file merely prefixed with .gitignore" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file ".gitignore_global" "*.log" "chore: global ignore")
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 0 ]
  _assert_make_ran
}

@test "pre-push runs make test when only Makefile changed" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file "Makefile" "test:" "chore: touch Makefile")
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 0 ]
  _assert_make_ran
}

@test "pre-push runs make test when only a non-source file under tests/ changed" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file "tests/fixtures/sample.txt" "fixture" "chore: touch tests fixture")
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 0 ]
  _assert_make_ran
}

@test "pre-push triggers when only .zshrc changed" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file ".zshrc" "echo hi" "chore: touch zshrc")
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 0 ]
  _assert_make_ran
}

@test "pre-push skips a top-level path merely prefixed with scripts because it is a markdown file" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file "scripts-old/notes.md" "notes" "docs: notes")
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 0 ]
  [ ! -f "${MOCK_CALLS_FILE}" ]
}

@test "pre-push propagates a make test failure as a non-zero exit" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file "deploy.sh" "echo hi" "feat: add deploy script")
  _write_make_mock 1
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 1 ]
}

@test "pre-push triggers on a new branch push (remote_sha all zeros) by diffing from the root commit" {
  _commit_file "README.md" "v1" "docs: v1" > /dev/null
  local_sha=$(_commit_file "deploy.sh" "echo hi" "feat: add deploy script")
  _write_make_mock 0
  run _run_pre_push "refs/heads/feature ${local_sha} refs/heads/feature 0000000000000000000000000000000000000000\n"
  [ "$status" -eq 0 ]
  _assert_make_ran
}

@test "pre-push skips a branch deletion (local_sha all zeros) without running tests" {
  _write_make_mock 0
  run _run_pre_push "refs/heads/old-feature 0000000000000000000000000000000000000000 refs/heads/old-feature abc123\n"
  [ "$status" -eq 0 ]
  [ ! -f "${MOCK_CALLS_FILE}" ]
}

@test "pre-push processes multiple ref lines in one push without exiting early" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file "deploy.sh" "echo hi" "feat: add deploy script")
  _write_make_mock 0
  run _run_pre_push "refs/heads/old-feature 0000000000000000000000000000000000000000 refs/heads/old-feature abc123\nrefs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 0 ]
  _assert_make_ran
}

_write_make_env_mock() {
  cat > "${MAKE_MOCK_DIR}/make" <<EOF
#!/usr/bin/env bash
printf "make %s\n" "\$*" >> "${MOCK_CALLS_FILE}"
env | grep '^GIT_' >> "${MOCK_CALLS_FILE}" || true
exit 0
EOF
  chmod +x "${MAKE_MOCK_DIR}/make"
}

_run_pre_push_leaked() {
  local _stdin="${1}"
  local _path_with_make="${MAKE_MOCK_DIR}:${CLEAN_PATH}"
  printf "%b" "${_stdin}" | bash -c "
    export PATH='${_path_with_make}'
    export GIT_DIR='${REPO_DIR}/.git'
    export GIT_WORK_TREE='${REPO_DIR}'
    export GIT_COMMON_DIR='${REPO_DIR}/.git'
    export GIT_INDEX_FILE='${REPO_DIR}/.git/index'
    cd '${REPO_DIR}' && bash '${REPO_ROOT}/scripts/pre-push'
  "
}

@test "pre-push clears inherited git repo-location vars before running make test" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file "deploy.sh" "echo hi" "feat: add deploy script")
  _write_make_env_mock
  run _run_pre_push_leaked "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 0 ]
  _assert_make_ran
  run ! grep -qE "^GIT_(DIR|WORK_TREE|COMMON_DIR|INDEX_FILE)=" "${MOCK_CALLS_FILE}"
}

@test "pre-push runs make test when only ubuntu_common_packages.txt changed" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file "ubuntu_common_packages.txt" "curl" "chore: touch ubuntu packages")
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 0 ]
  _assert_make_ran
}

@test "pre-push runs make test when only starship.toml changed" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file "starship.toml" "format = x" "chore: touch starship config")
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 0 ]
  _assert_make_ran
}

@test "pre-push skips when only a docs/adr file changed" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file "docs/adr/0017-x.md" "# ADR" "docs: touch adr")
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 0 ]
  [ ! -f "${MOCK_CALLS_FILE}" ]
}

@test "pre-push runs the suite when only a .github/workflows file changed" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file ".github/workflows/ci.yml" "name: CI" "chore: touch ci workflow")
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 0 ]
  _assert_make_ran
}

@test "pre-push triggers on a mixed diff with one inert and one non-inert path" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  _commit_file "README.md" "v2" "docs: v2" > /dev/null
  local_sha=$(_commit_file "setup_env.sh" "echo hi" "feat: touch setup_env")
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 0 ]
  _assert_make_ran
}

@test "pre-push triggers on a LICENSE outside the repo root" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file "docs/LICENSE" "text" "chore: nested license")
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 0 ]
  _assert_make_ran
}

@test "pre-push triggers on a .github directory outside the repo root" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file "docs/.github/x.yml" "on: push" "chore: nested github dir")
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 0 ]
  _assert_make_ran
}

@test "pre-push triggers on a .github file merely suffixed after .yml" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file ".github/workflows/ci.yml.bak" "backup" "chore: yml backup")
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 0 ]
  _assert_make_ran
}

@test "pre-push runs the suite for a .github workflow using the .yaml spelling" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file ".github/workflows/x.yaml" "on: push" "ci: yaml spelling")
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 0 ]
  _assert_make_ran
}

@test "pre-push triggers on a markdown fixture under tests/" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file "tests/fixtures/expected_output.md" "expected" "test: md fixture")
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 0 ]
  _assert_make_ran
}

@test "pre-push skips when only LICENSE changed" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file "LICENSE" "MIT" "chore: touch license")
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 0 ]
  [ ! -f "${MOCK_CALLS_FILE}" ]
}

@test "pre-push triggers on a file merely prefixed with LICENSE" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file "LICENSE.txt" "MIT" "chore: add license txt")
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 0 ]
  _assert_make_ran
}

@test "pre-push triggers on a .mdx file, not just .md" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file "foo.mdx" "content" "chore: add mdx file")
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 0 ]
  _assert_make_ran
}

@test "pre-push triggers when a shell script exists under docs/" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file "docs/gen.sh" "echo hi" "chore: add docs gen script")
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 0 ]
  _assert_make_ran
}

@test "pre-push triggers when a shell script exists under .github/" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file ".github/scripts/foo.sh" "echo hi" "chore: add github script")
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 0 ]
  _assert_make_ran
}

@test "pre-push triggers on CHANGELOG_gen.sh" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file "CHANGELOG_gen.sh" "echo hi" "chore: add changelog gen script")
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 0 ]
  _assert_make_ran
}

@test "pre-push skips when the diff range contains no changes" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${base_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 0 ]
  [ ! -f "${MOCK_CALLS_FILE}" ]
}

@test "pre-push fails closed and triggers when the diff range cannot be resolved" {
  local_sha=$(_commit_file "README.md" "v1" "docs: v1")
  bogus_sha="deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${bogus_sha}\n"
  [ "$status" -eq 0 ]
  _assert_make_ran
}

# ── default-deny inert predicate (_path_is_inert) ───────────────────────────
# Commit a file whose content is written directly (shebang / large payloads
# cannot go through _commit_file's single-quoted printf).
_commit_raw() {
  local _path="${1}" _src="${2}" _msg="${3}"
  bash -c "
    export PATH='${CLEAN_PATH}'
    unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE
    mkdir -p \"\$(dirname '${REPO_DIR}/${_path}')\"
    cp '${_src}' '${REPO_DIR}/${_path}'
    git -C '${REPO_DIR}' add '${_path}'
    git -C '${REPO_DIR}' commit --quiet -m '${_msg}'
    git -C '${REPO_DIR}' rev-parse HEAD
  "
}

_git_clean() {
  bash -c "
    export PATH='${CLEAN_PATH}'
    unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE
    git -C '${REPO_DIR}' $*
  "
}

_assert_suite_ran() {
  _assert_make_ran
}

@test "pre-push skips a docs markdown file" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file "docs/a.md" "x" "docs: a")
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 0 ]
  [ ! -f "${MOCK_CALLS_FILE}" ]
}

@test "pre-push skips a markdown file under a nested tests/ directory" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file "foo/tests/a.md" "x" "docs: nested")
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 0 ]
  [ ! -f "${MOCK_CALLS_FILE}" ]
}

@test "pre-push runs the suite for a .md whose content starts with a shebang" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  printf '#!/usr/bin/env bash\necho hi\n' > "${BATS_TEST_TMPDIR}/evil"
  local_sha=$(_commit_raw "docs/evil.md" "${BATS_TEST_TMPDIR}/evil" "docs: evil")
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 0 ]
  _assert_suite_ran
}

@test "pre-push runs the suite for a root LICENSE that starts with a shebang" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  printf '#!/usr/bin/env bash\necho hi\n' > "${BATS_TEST_TMPDIR}/lic"
  local_sha=$(_commit_raw "LICENSE" "${BATS_TEST_TMPDIR}/lic" "chore: license")
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 0 ]
  _assert_suite_ran
}

@test "pre-push runs the suite for a LICENSE in a subdirectory" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file "x/LICENSE" "MIT" "chore: sub license")
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 0 ]
  _assert_suite_ran
}

@test "pre-push runs the suite for a double-extension a.md.sh" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file "a.md.sh" "echo hi" "feat: sh")
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 0 ]
  _assert_suite_ran
}

@test "pre-push skips a 300 KB markdown file (larger than the pipe buffer)" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  head -c 300000 /dev/zero | tr '\0' 'a' > "${BATS_TEST_TMPDIR}/big"
  local_sha=$(_commit_raw "docs/big.md" "${BATS_TEST_TMPDIR}/big" "docs: big")
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 0 ]
  [ ! -f "${MOCK_CALLS_FILE}" ]
}

@test "pre-push runs the suite when a shell script is renamed to .md" {
  _commit_file "x.sh" "echo hi" "feat: x" > /dev/null
  base_sha=$(_git_clean "rev-parse HEAD")
  _git_clean "mv x.sh x.md"
  _git_clean "commit --quiet -m 'chore: rename'"
  local_sha=$(_git_clean "rev-parse HEAD")
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 0 ]
  _assert_suite_ran
}

@test "pre-push skips the deletion of a markdown file" {
  _commit_file "docs/old.md" "x" "docs: old" > /dev/null
  base_sha=$(_git_clean "rev-parse HEAD")
  _git_clean "rm --quiet docs/old.md"
  _git_clean "commit --quiet -m 'docs: rm'"
  local_sha=$(_git_clean "rev-parse HEAD")
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 0 ]
  [ ! -f "${MOCK_CALLS_FILE}" ]
}

@test "pre-push runs the suite when a shell script is deleted" {
  _commit_file "x.sh" "echo hi" "feat: x" > /dev/null
  base_sha=$(_git_clean "rev-parse HEAD")
  _git_clean "rm --quiet x.sh"
  _git_clean "commit --quiet -m 'chore: rm'"
  local_sha=$(_git_clean "rev-parse HEAD")
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 0 ]
  _assert_suite_ran
}

# ── direct-to-master guard ──────────────────────────────────────────────────
# The hook refuses a push whose target ref is master when the diff carries a
# path _path_is_inert rejects (ADR-0038). Measured 2026-09-11: five such pushes reached master
# in one session with no CI behind them, because ci.yml is pull_request-only.
# The two allow-cases below are positive controls: without them a passing
# refusal set cannot distinguish "correctly scoped" from "refuses everything".

@test "pre-push refuses a .sh pushed to master and does not run the suite" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file "deploy.sh" "echo hi" "feat: add deploy script")
  _write_make_mock 0
  run _run_pre_push "refs/heads/master ${local_sha} refs/heads/master ${base_sha}\n"
  [ "$status" -ne 0 ]
  [ ! -f "${MOCK_CALLS_FILE}" ]
  [[ "$output" == *"deploy.sh"* ]]
}

@test "pre-push refuses a .bash pushed to master" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file "tests/helpers/legacy_oracle.bash" "x" "test: oracle")
  _write_make_mock 0
  run _run_pre_push "refs/heads/master ${local_sha} refs/heads/master ${base_sha}\n"
  [ "$status" -ne 0 ]
  [ ! -f "${MOCK_CALLS_FILE}" ]
  [[ "$output" == *"legacy_oracle.bash"* ]]
}

@test "pre-push still runs the suite for a .sh pushed to a feature branch" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file "deploy.sh" "echo hi" "feat: add deploy script")
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 0 ]
  _assert_make_ran
}

@test "pre-push still permits a markdown push to master" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file "README.md" "v2" "docs: v2")
  _write_make_mock 0
  run _run_pre_push "refs/heads/master ${local_sha} refs/heads/master ${base_sha}\n"
  [ "$status" -eq 0 ]
  [ ! -f "${MOCK_CALLS_FILE}" ]
}

# ── default-deny master guard and recovery messages ─────────────────────────
# Guard tests push to refs/heads/master. _on_branch sets the checkout the hook
# sees, because a local_ref of HEAD is resolved from it.

ZERO_SHA="0000000000000000000000000000000000000000"

_on_branch() { _git_clean "checkout --quiet -B ${1}"; }

_assert_refused() {
  [ "$status" -eq 1 ]
  [ ! -f "${MOCK_CALLS_FILE}" ]
  [[ "$output" == *"gh pr merge --admin"* ]]
  [[ "$output" != *"--no-verify"* ]]
  # The rule text must name every exclusion, or a refused tests/a.md or
  # shebang .md reads as contradicting it.
  [[ "$output" == *"outside the root tests/"* ]]
  [[ "$output" == *"#!"* ]]
  [[ "$output" == *"symlink"* ]]
}

# Commit one path (content via printf) and push it to master; sets $output.
_master_push_of() {
  local _path="${1}" _content="${2:-x}" _base _sha
  _base=$(_commit_file "README.md" "v1" "docs: v1")
  _sha=$(_commit_file "${_path}" "${_content}" "chore: add path")
  _write_make_mock 0
  run _run_pre_push "refs/heads/master ${_sha} refs/heads/master ${_base}\n"
}

@test "master guard refuses and names tests/mocks/x" {
  _master_push_of "tests/mocks/x" "echo hi"
  _assert_refused
  [[ "$output" == *"tests/mocks/x"* ]]
}

@test "master guard refuses and names a.py" {
  _master_push_of "a.py" "print(1)"
  _assert_refused
  [[ "$output" == *"a.py"* ]]
}

@test "master guard refuses and names .zshrc" {
  _master_push_of ".zshrc" "echo hi"
  _assert_refused
  [[ "$output" == *".zshrc"* ]]
}

@test "master guard refuses and names uv.lock" {
  _master_push_of "uv.lock" "lock"
  _assert_refused
  [[ "$output" == *"uv.lock"* ]]
}

@test "master guard refuses and names a workflow file" {
  _master_push_of ".github/workflows/ci.yml" "name: CI"
  _assert_refused
  [[ "$output" == *".github/workflows/ci.yml"* ]]
}

@test "master guard refuses and names .warp/settings.toml" {
  _master_push_of ".warp/settings.toml" "a = 1"
  _assert_refused
  [[ "$output" == *".warp/settings.toml"* ]]
}

@test "master guard refuses and names renovate.json" {
  _master_push_of "renovate.json" "{}"
  _assert_refused
  [[ "$output" == *"renovate.json"* ]]
}

@test "master guard refuses and names a dotfile txt under docs" {
  _master_push_of "docs/x/.state.txt" "s"
  _assert_refused
  [[ "$output" == *"docs/x/.state.txt"* ]]
}

@test "master guard refuses and names an unknown extension" {
  _master_push_of "foo.unknown" "s"
  _assert_refused
  [[ "$output" == *"foo.unknown"* ]]
}

@test "master guard allows docs/a.md" {
  _master_push_of "docs/a.md" "x"
  [ "$status" -eq 0 ]
  [ ! -f "${MOCK_CALLS_FILE}" ]
}

@test "master guard allows README.md" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file "README.md" "v2" "docs: v2")
  _write_make_mock 0
  run _run_pre_push "refs/heads/master ${local_sha} refs/heads/master ${base_sha}\n"
  [ "$status" -eq 0 ]
  [ ! -f "${MOCK_CALLS_FILE}" ]
}

@test "master guard allows the root LICENSE" {
  _master_push_of "LICENSE" "MIT"
  [ "$status" -eq 0 ]
  [ ! -f "${MOCK_CALLS_FILE}" ]
}

@test "master guard allows a non-ASCII markdown name" {
  _master_push_of "docs/café.md" "x"
  [ "$status" -eq 0 ]
  [ ! -f "${MOCK_CALLS_FILE}" ]
}

@test "master guard allows a 300 KB markdown file" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  head -c 300000 /dev/zero | tr '\0' 'a' > "${BATS_TEST_TMPDIR}/big"
  local_sha=$(_commit_raw "docs/big.md" "${BATS_TEST_TMPDIR}/big" "docs: big")
  _write_make_mock 0
  run _run_pre_push "refs/heads/master ${local_sha} refs/heads/master ${base_sha}\n"
  [ "$status" -eq 0 ]
  [ ! -f "${MOCK_CALLS_FILE}" ]
}

@test "master guard allows foo/tests/a.md" {
  _master_push_of "foo/tests/a.md" "x"
  [ "$status" -eq 0 ]
  [ ! -f "${MOCK_CALLS_FILE}" ]
}

@test "master guard allows deleting docs/old.md" {
  _commit_file "docs/old.md" "x" "docs: old" > /dev/null
  base_sha=$(_git_clean "rev-parse HEAD")
  _git_clean "rm --quiet docs/old.md"
  _git_clean "commit --quiet -m 'docs: rm'"
  local_sha=$(_git_clean "rev-parse HEAD")
  _write_make_mock 0
  run _run_pre_push "refs/heads/master ${local_sha} refs/heads/master ${base_sha}\n"
  [ "$status" -eq 0 ]
  [ ! -f "${MOCK_CALLS_FILE}" ]
}

@test "master guard refuses a shebang .md" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  printf '#!/usr/bin/env bash\necho hi\n' > "${BATS_TEST_TMPDIR}/evil"
  local_sha=$(_commit_raw "docs/evil.md" "${BATS_TEST_TMPDIR}/evil" "docs: evil")
  _write_make_mock 0
  run _run_pre_push "refs/heads/master ${local_sha} refs/heads/master ${base_sha}\n"
  _assert_refused
  [[ "$output" == *"docs/evil.md"* ]]
}

@test "master guard refuses a shebang LICENSE" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  printf '#!/usr/bin/env bash\necho hi\n' > "${BATS_TEST_TMPDIR}/lic"
  local_sha=$(_commit_raw "LICENSE" "${BATS_TEST_TMPDIR}/lic" "chore: license")
  _write_make_mock 0
  run _run_pre_push "refs/heads/master ${local_sha} refs/heads/master ${base_sha}\n"
  _assert_refused
}

@test "master guard refuses tests/a.md" {
  _master_push_of "tests/a.md" "x"
  _assert_refused
  [[ "$output" == *"tests/a.md"* ]]
}

@test "master guard refuses x/LICENSE" {
  _master_push_of "x/LICENSE" "MIT"
  _assert_refused
  [[ "$output" == *"x/LICENSE"* ]]
}

@test "master guard refuses a.md.sh" {
  _master_push_of "a.md.sh" "echo hi"
  _assert_refused
  [[ "$output" == *"a.md.sh"* ]]
}

@test "master guard refuses a path containing a newline" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  bash -c "
    export PATH='${CLEAN_PATH}'
    unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE
    p=\$'a\nb.md'
    printf 'x\n' > '${REPO_DIR}/'\"\${p}\"
    git -C '${REPO_DIR}' add -A
    git -C '${REPO_DIR}' commit --quiet -m 'chore: newline name'
  "
  local_sha=$(_git_clean "rev-parse HEAD")
  _write_make_mock 0
  run _run_pre_push "refs/heads/master ${local_sha} refs/heads/master ${base_sha}\n"
  _assert_refused
}

@test "master guard refuses the deletion of a shell script" {
  _commit_file "x.sh" "echo hi" "feat: x" > /dev/null
  base_sha=$(_git_clean "rev-parse HEAD")
  _git_clean "rm --quiet x.sh"
  _git_clean "commit --quiet -m 'chore: rm'"
  local_sha=$(_git_clean "rev-parse HEAD")
  _write_make_mock 0
  run _run_pre_push "refs/heads/master ${local_sha} refs/heads/master ${base_sha}\n"
  _assert_refused
  [[ "$output" == *"x.sh"* ]]
}

@test "master guard refuses x.sh renamed to x.md and names x.sh" {
  _commit_file "x.sh" "echo hi" "feat: x" > /dev/null
  base_sha=$(_git_clean "rev-parse HEAD")
  _git_clean "mv x.sh x.md"
  _git_clean "commit --quiet -m 'chore: rename'"
  local_sha=$(_git_clean "rev-parse HEAD")
  _write_make_mock 0
  run _run_pre_push "refs/heads/master ${local_sha} refs/heads/master ${base_sha}\n"
  _assert_refused
  [[ "$output" == *"x.sh"* ]]
}

@test "master guard with an unknown remote_sha says fetch and omits the PR recipe" {
  local_sha=$(_commit_file "README.md" "v1" "docs: v1")
  _write_make_mock 0
  run _run_pre_push "refs/heads/master ${local_sha} refs/heads/master deadbeefdeadbeefdeadbeefdeadbeefdeadbeef\n"
  [ "$status" -eq 1 ]
  [ ! -f "${MOCK_CALLS_FILE}" ]
  [[ "$output" == *"git fetch"* ]]
  [[ "$output" == *"refs/heads/master"* ]]
  [[ "$output" != *"gh pr create"* ]]
}

@test "master recipe for local_ref master uses reset --keep, not a push of the current branch" {
  _on_branch feat
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file "deploy.sh" "echo hi" "feat: deploy")
  _write_make_mock 0
  run _run_pre_push "refs/heads/master ${local_sha} refs/heads/master ${base_sha}\n"
  _assert_refused
  [[ "$output" == *"git switch -c <name> master"* ]]
  [[ "$output" == *"git reset --keep origin/master"* ]]
  [[ "$output" != *"git push -u origin feat"* ]]
}

@test "branch recipe for local_ref feat names feat and lacks reset --keep" {
  _on_branch feat
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file "deploy.sh" "echo hi" "feat: deploy")
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat ${local_sha} refs/heads/master ${base_sha}\n"
  _assert_refused
  [[ "$output" == *"git push -u origin feat"* ]]
  [[ "$output" != *"reset --keep"* ]]
}

@test "HEAD on branch feat gives the feat recipe" {
  _on_branch feat
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file "deploy.sh" "echo hi" "feat: deploy")
  _write_make_mock 0
  run _run_pre_push "HEAD ${local_sha} refs/heads/master ${base_sha}\n"
  _assert_refused
  [[ "$output" == *"git push -u origin feat"* ]]
  [[ "$output" != *"reset --keep"* ]]
}

@test "HEAD on master gives the local-master recipe" {
  _on_branch master
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file "deploy.sh" "echo hi" "feat: deploy")
  _write_make_mock 0
  run _run_pre_push "HEAD ${local_sha} refs/heads/master ${base_sha}\n"
  _assert_refused
  [[ "$output" == *"git reset --keep origin/master"* ]]
}

@test "detached HEAD gives git switch -c" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file "deploy.sh" "echo hi" "feat: deploy")
  _git_clean "checkout --quiet --detach"
  _write_make_mock 0
  run _run_pre_push "HEAD ${local_sha} refs/heads/master ${base_sha}\n"
  _assert_refused
  [[ "$output" == *"git switch -c"* ]]
  [[ "$output" != *"reset --keep"* ]]
}

@test "master guard refuses a docs commit stacked on an unpushed code commit" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  _commit_file "deploy.sh" "echo hi" "feat: deploy" > /dev/null
  local_sha=$(_commit_file "docs/a.md" "x" "docs: a")
  _write_make_mock 0
  run _run_pre_push "refs/heads/master ${local_sha} refs/heads/master ${base_sha}\n"
  _assert_refused
  [[ "$output" == *"deploy.sh"* ]]
}

@test "non-inert path on a feature ref runs the suite and exits 0" {
  _master_push_of "deploy.sh" "echo hi" # populates repo; ignore its result
  rm -f "${MOCK_CALLS_FILE}"
  base_sha=$(_git_clean "rev-parse HEAD~1")
  local_sha=$(_git_clean "rev-parse HEAD")
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 0 ]
  _assert_suite_ran
}

@test "live_paths is reset per ref: a branch's non-inert path does not leak into a master ref" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  sha1=$(_commit_file "deploy.sh" "echo hi" "feat: deploy")
  sha2=$(_commit_file "docs/a.md" "x" "docs: a")
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${sha2} refs/heads/feat/x ${base_sha}\nrefs/heads/master ${sha2} refs/heads/master ${sha1}\n"
  [ "$status" -eq 0 ]
  [[ "$output" != *"refusing"* ]]
  _assert_suite_ran
}

@test "first push to an empty master refuses a single commit carrying a.py" {
  local_sha=$(_commit_file "a.py" "print(1)" "feat: first")
  _write_make_mock 0
  run _run_pre_push "refs/heads/master ${local_sha} refs/heads/master ${ZERO_SHA}\n"
  _assert_refused
  [[ "$output" == *"a.py"* ]]
}

@test "first push to an empty master allows a single docs/a.md commit" {
  local_sha=$(_commit_file "docs/a.md" "x" "docs: first")
  _write_make_mock 0
  run _run_pre_push "refs/heads/master ${local_sha} refs/heads/master ${ZERO_SHA}\n"
  [ "$status" -eq 0 ]
  [ ! -f "${MOCK_CALLS_FILE}" ]
}

@test "first push of a single-commit branch carrying a.py runs the suite" {
  local_sha=$(_commit_file "a.py" "print(1)" "feat: first")
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${ZERO_SHA}\n"
  [ "$status" -eq 0 ]
  _assert_suite_ran
}

@test "a tag source is called not a branch, not detached HEAD" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file "deploy.sh" "echo hi" "feat: deploy")
  _write_make_mock 0
  run _run_pre_push "refs/tags/v1 ${local_sha} refs/heads/master ${base_sha}\n"
  _assert_refused
  [[ "$output" == *"not a branch"* ]]
  [[ "$output" != *"detached"* ]]
}

# ── inertness is decided from the pushed tree entry, not the object ─────────
# Commit a single index entry of any mode: _mode _object _path.
_commit_entry() {
  local _mode="${1}" _obj="${2}" _path="${3}"
  bash -c "
    export PATH='${CLEAN_PATH}'
    unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE
    git -C '${REPO_DIR}' update-index --add --cacheinfo '${_mode},${_obj},${_path}'
    git -C '${REPO_DIR}' commit --quiet -m 'chore: entry'
    git -C '${REPO_DIR}' rev-parse HEAD
  "
}

@test "master guard refuses a gitlink named .md whose commit is not in the repo" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_entry 160000 "1111111111111111111111111111111111111111" "docs/sub.md")
  _write_make_mock 0
  run _run_pre_push "refs/heads/master ${local_sha} refs/heads/master ${base_sha}\n"
  _assert_refused
  [[ "$output" == *"docs/sub.md"* ]]
}

@test "master guard refuses a gitlink named .md whose commit IS in the repo" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_entry 160000 "${base_sha}" "docs/sub2.md")
  _write_make_mock 0
  run _run_pre_push "refs/heads/master ${local_sha} refs/heads/master ${base_sha}\n"
  _assert_refused
  [[ "$output" == *"docs/sub2.md"* ]]
}

@test "master guard refuses a symlink named .md" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  blob=$(printf '../scripts/s.sh' | _git_clean "hash-object -w --stdin")
  local_sha=$(_commit_entry 120000 "${blob}" "docs/link.md")
  _write_make_mock 0
  run _run_pre_push "refs/heads/master ${local_sha} refs/heads/master ${base_sha}\n"
  _assert_refused
  [[ "$output" == *"docs/link.md"* ]]
}

@test "master guard allows a markdown name containing glob characters" {
  _master_push_of "docs/[x].md" "x"
  [ "$status" -eq 0 ]
  [ ! -f "${MOCK_CALLS_FILE}" ]
}

@test "master guard allows a markdown name that looks like pathspec magic" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  blob=$(printf 'x' | _git_clean "hash-object -w --stdin")
  local_sha=$(_commit_entry 100644 "${blob}" ":(x).md")
  _write_make_mock 0
  run _run_pre_push "refs/heads/master ${local_sha} refs/heads/master ${base_sha}\n"
  [ "$status" -eq 0 ]
  [ ! -f "${MOCK_CALLS_FILE}" ]
}

@test "master guard refuses a .md whose blob object is missing from the repo" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  printf '#!/usr/bin/env bash\necho hi\n' > "${BATS_TEST_TMPDIR}/evil"
  local_sha=$(_commit_raw "docs/gone.md" "${BATS_TEST_TMPDIR}/evil" "docs: gone")
  blob=$(_git_clean "rev-parse ${local_sha}:docs/gone.md")
  obj="${REPO_DIR}/.git/objects/${blob:0:2}/${blob:2}"
  [ -f "${obj}" ]
  rm -f "${obj}"
  _write_make_mock 0
  run _run_pre_push "refs/heads/master ${local_sha} refs/heads/master ${base_sha}\n"
  _assert_refused
  [[ "$output" == *"docs/gone.md"* ]]
}

@test "master guard allows an executable-mode .md with no shebang" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  blob=$(printf 'plain text' | _git_clean "hash-object -w --stdin")
  local_sha=$(_commit_entry 100755 "${blob}" "docs/exec.md")
  _write_make_mock 0
  run _run_pre_push "refs/heads/master ${local_sha} refs/heads/master ${base_sha}\n"
  [ "$status" -eq 0 ]
  [ ! -f "${MOCK_CALLS_FILE}" ]
}

@test "master guard refuses an ordinary .md when head itself fails" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file "docs/a.md" "x" "docs: a")
  mkdir -p "${BATS_TEST_TMPDIR}/headshim"
  printf '#!/bin/sh\nexit 1\n' > "${BATS_TEST_TMPDIR}/headshim/head"
  chmod +x "${BATS_TEST_TMPDIR}/headshim/head"
  _write_make_mock 0
  # Control: without the shim the same push is allowed, so the refusal below
  # is caused by head failing and not by anything else in the fixture.
  run _run_pre_push "refs/heads/master ${local_sha} refs/heads/master ${base_sha}\n"
  [ "$status" -eq 0 ]
  MAKE_MOCK_DIR="${BATS_TEST_TMPDIR}/headshim:${MAKE_MOCK_DIR}"
  run _run_pre_push "refs/heads/master ${local_sha} refs/heads/master ${base_sha}\n"
  _assert_refused
  [[ "$output" == *"docs/a.md"* ]]
}

# ── the hook reads the PUSHED commit, not HEAD ──────────────────────────────
# "On feat, push local master": HEAD and local_sha differ. _sha must reach
# every read, so each fixture makes HEAD answer differently from local_sha.
_pushed_vs_head() {
  # _pushed_vs_head <pushed: shebang|plain|gone> <head: shebang|plain|absent>
  local _pushed="${1}" _head="${2}" _base _s
  printf '#!/usr/bin/env bash\necho hi\n' > "${BATS_TEST_TMPDIR}/sb"
  printf 'plain text\n' > "${BATS_TEST_TMPDIR}/pl"
  _on_branch master
  _base=$(_commit_file "README.md" "v1" "docs: v1")
  if [[ "${_pushed}" == "plain" ]]; then
    PUSHED_SHA=$(_commit_raw "docs/a.md" "${BATS_TEST_TMPDIR}/pl" "docs: pushed")
  else
    PUSHED_SHA=$(_commit_raw "docs/a.md" "${BATS_TEST_TMPDIR}/sb" "docs: pushed")
  fi
  if [[ "${_pushed}" == "gone" ]]; then
    _s=$(_git_clean "rev-parse ${PUSHED_SHA}:docs/a.md")
    rm -f "${REPO_DIR}/.git/objects/${_s:0:2}/${_s:2}"
  fi
  BASE_SHA="${_base}"
  _git_clean "checkout --quiet -B feat ${_base}"
  case "${_head}" in
    shebang) _commit_raw "docs/a.md" "${BATS_TEST_TMPDIR}/sb" "docs: head" > /dev/null ;;
    plain) _commit_raw "docs/a.md" "${BATS_TEST_TMPDIR}/pl" "docs: head" > /dev/null ;;
  esac
  _write_make_mock 0
  run _run_pre_push "refs/heads/master ${PUSHED_SHA} refs/heads/master ${BASE_SHA}\n"
}

@test "pushed shebang .md is refused when HEAD's copy is plain text" {
  _pushed_vs_head shebang plain
  _assert_refused
  [[ "$output" == *"docs/a.md"* ]]
}

@test "pushed shebang .md is refused when HEAD does not have the path at all" {
  _pushed_vs_head shebang absent
  _assert_refused
  [[ "$output" == *"docs/a.md"* ]]
}

@test "pushed plain .md is allowed when HEAD's copy has a shebang" {
  _pushed_vs_head plain shebang
  [ "$status" -eq 0 ]
  [ ! -f "${MOCK_CALLS_FILE}" ]
}

@test "pushed .md with a missing blob is refused when HEAD's copy is readable" {
  _pushed_vs_head gone plain
  _assert_refused
  [[ "$output" == *"docs/a.md"* ]]
}

# ── CLAUDE.md byte-budget gate (ADR-0047) ───────────────────────────────────
# The hook runs the checker from the PUSHED commit, so these fixtures commit a
# copy of the real checker. The over-ceiling case is refused before the
# inert-path exit, so a CLAUDE.md-only (docs-only) push is covered too.

# _budget_commit <size> [nochecker]: commit CLAUDE.md of exactly <size> bytes
# (with the real checker committed alongside unless told otherwise); prints sha.
_budget_commit() {
  local _size="${1}" _mode="${2:-checker}"
  bash -c "
    export PATH='${CLEAN_PATH}'
    unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE
    # Stage the blob directly: no CLAUDE.md file is written anywhere on disk,
    # so a failed path cannot overwrite the real repo's copy.
    _blob=\"\$(head -c '${_size}' /dev/zero | tr '\\0' 'a' | git -C '${REPO_DIR}' hash-object -w --stdin)\" || exit 1
    git -C '${REPO_DIR}' update-index --add --cacheinfo \"100644,\${_blob},CLAUDE.md\" || exit 1
    if [ '${_mode}' = checker ]; then
      mkdir -p '${REPO_DIR}/scripts'
      cp '${REPO_ROOT}/scripts/claude_md_budget.py' '${REPO_DIR}/scripts/claude_md_budget.py'
      git -C '${REPO_DIR}' add scripts/claude_md_budget.py
    fi
    git -C '${REPO_DIR}' commit --quiet -m 'docs: claude md' >&2 || exit 1
    git -C '${REPO_DIR}' rev-parse HEAD
  "
}

@test "budget gate refuses a CLAUDE.md-only push of 85001 bytes and names the ceiling" {
  base_sha=$(_budget_commit 100)
  local_sha=$(_budget_commit 85001)
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 1 ]
  [ ! -f "${MOCK_CALLS_FILE}" ]
  [[ "$output" == *"ADR-0047"* ]]
  [[ "$output" == *"dotfiles-*.md"* ]]
  # The checker itself refused, not a git step failing first.
  [[ "$output" == *"bytes, ceiling 85000"* ]]
  [[ "$output" == *"Any message from git or the checker is above."* ]]
  [[ "$output" != *"105,0"* ]]
  [[ "$output" == *"refs/heads/feat/x"* ]]
}

@test "budget gate allows a CLAUDE.md of exactly 85000 bytes" {
  base_sha=$(_budget_commit 100)
  local_sha=$(_budget_commit 85000)
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 0 ]
}

@test "budget gate does not refuse a pushed commit that predates the checker" {
  base_sha=$(_budget_commit 100 nochecker)
  local_sha=$(_budget_commit 85001 nochecker)
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 0 ]
  [[ "$output" != *"CLAUDE.md budget check failed"* ]]
}

@test "budget gate runs the committed checker, not the working-tree copy" {
  base_sha=$(_budget_commit 100)
  local_sha=$(_budget_commit 85001)
  printf 'import sys\nsys.exit(0)\n' > "${REPO_DIR}/scripts/claude_md_budget.py"
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ADR-0047"* ]]
  [[ "$output" == *"dotfiles-*.md"* ]]
  # The checker itself refused, not a git step failing first.
  [[ "$output" == *"bytes, ceiling 85000"* ]]
}

@test "budget gate refuses a two-ref push whose first ref is over the ceiling" {
  base_sha=$(_budget_commit 100)
  bad_sha=$(_budget_commit 85001)
  _git_clean "checkout --quiet -B good ${base_sha}"
  good_sha=$(_budget_commit 200)
  _write_make_mock 0
  run _run_pre_push "refs/heads/bad ${bad_sha} refs/heads/bad ${base_sha}\nrefs/heads/good ${good_sha} refs/heads/good ${base_sha}\n"
  [ "$status" -eq 1 ]
  [[ "$output" == *"refs/heads/bad"* ]]
  [[ "$output" != *"refs/heads/good"* ]]
}

@test "budget gate refuses when git show of the checker fails" {
  base_sha=$(_budget_commit 100)
  local_sha=$(_budget_commit 200)
  real_git="$(PATH="${CLEAN_PATH}" command -v git)"
  shim="${BATS_TEST_TMPDIR}/gitshim"
  mkdir -p "${shim}"
  cat > "${shim}/git" <<SHIM
#!/usr/bin/env bash
if [[ "\${1}" == "show" && "\${2}" == *":scripts/claude_md_budget.py" ]]; then
  exit 128
fi
exec "${real_git}" "\$@"
SHIM
  chmod +x "${shim}/git"
  _write_make_mock 0
  export PATH="${shim}:${MAKE_MOCK_DIR}:${CLEAN_PATH}"
  unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE
  cd "${REPO_DIR}"
  run bash -c "printf 'refs/heads/feat/x %s refs/heads/feat/x %s\n' '${local_sha}' '${base_sha}' | bash '${REPO_ROOT}/scripts/pre-push'"
  [ "$status" -eq 1 ]
  [[ "$output" == *"refs/heads/feat/x"* ]]
}

@test "budget gate uses the pushed commit's checker, not HEAD's (stub checker at HEAD)" {
  base_sha=$(_budget_commit 100)
  _git_clean "checkout --quiet -B bad ${base_sha}"
  bad_sha=$(_budget_commit 85001)
  _git_clean "checkout --quiet -B stub ${base_sha}"
  _commit_file "scripts/claude_md_budget.py" "import sys; sys.exit(0)" "chore: stub checker" > /dev/null
  _write_make_mock 0
  run _run_pre_push "refs/heads/bad ${bad_sha} refs/heads/bad ${base_sha}\n"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ADR-0047"* ]]
  [[ "$output" == *"dotfiles-*.md"* ]]
  # The checker itself refused, not a git step failing first.
  [[ "$output" == *"bytes, ceiling 85000"* ]]
}

@test "budget gate detects the pushed commit's checker when HEAD has none" {
  base_sha=$(_budget_commit 100 nochecker)
  _git_clean "checkout --quiet -B bad ${base_sha}"
  bad_sha=$(_budget_commit 85001)
  _git_clean "checkout --quiet -B none ${base_sha}"
  _write_make_mock 0
  run _run_pre_push "refs/heads/bad ${bad_sha} refs/heads/bad ${base_sha}\n"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ADR-0047"* ]]
  [[ "$output" == *"dotfiles-*.md"* ]]
  # The checker itself refused, not a git step failing first.
  [[ "$output" == *"bytes, ceiling 85000"* ]]
}

@test "budget gate refuses when git ls-tree fails on a nonexistent local sha" {
  base_sha=$(_budget_commit 100)
  ghost=1234567890123456789012345678901234567890
  _write_make_mock 0
  run _run_pre_push "refs/heads/ghost ${ghost} refs/heads/ghost ${base_sha}\n"
  [ "$status" -eq 1 ]
  [[ "$output" == *"CLAUDE.md budget check failed"* ]]
}

@test "budget gate names every over-ceiling ref in a multi-ref push" {
  base_sha=$(_budget_commit 100)
  _git_clean "checkout --quiet -B one ${base_sha}"
  one_sha=$(_budget_commit 85001)
  _git_clean "checkout --quiet -B two ${base_sha}"
  two_sha=$(_budget_commit 85002)
  _write_make_mock 0
  run _run_pre_push "refs/heads/one ${one_sha} refs/heads/one ${base_sha}\nrefs/heads/two ${two_sha} refs/heads/two ${base_sha}\n"
  [ "$status" -eq 1 ]
  [[ "$output" == *"refs/heads/one"* ]]
  [[ "$output" == *"refs/heads/two"* ]]
}

# --- wrong-tree refusal: the suite tests REPO_ROOT's working tree, so every
# pushed ref must be at that tree's HEAD or the green run proves nothing about
# what is pushed. ---

# Run the hook from <cwd>. <extra> is shell text run after the GIT_* unset, so
# a case can deliberately export one (as git does for a push from a worktree).
_run_pre_push_at() {
  local _cwd="${1}" _stdin="${2}" _extra="${3:-}" _hook_args="${4:-}"
  local _path_with_make="${MAKE_MOCK_DIR}:${CLEAN_PATH}"
  printf "%b" "${_stdin}" | bash -c "
    export PATH='${_path_with_make}'
    unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE
    ${_extra}
    cd '${_cwd}' && bash '${REPO_ROOT}/scripts/pre-push' ${_hook_args}
  "
}

@test "wrong-tree: a ref behind this checkout's HEAD is refused before the suite" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  sha1=$(_commit_file "a.sh" "echo 1" "feat: a")
  sha2=$(_commit_file "b.sh" "echo 2" "feat: b")
  _write_make_mock 0
  # New branch (remote_sha all zeros): the commonest real wrong-tree push.
  run _run_pre_push "refs/heads/feat ${sha1} refs/heads/feat ${ZERO_SHA}\n"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not the pushed commit"* ]]
  [[ "$output" == *"${sha1:0:7}"* ]]
  [[ "$output" == *"${sha2:0:7}"* ]]
  _repo_canon="$(_canon "${REPO_DIR}")"
  [[ "$output" == *"this checkout (${_repo_canon})"* ]]
  [ ! -f "${MOCK_CALLS_FILE}" ]
}

@test "wrong-tree: a ref at this checkout's HEAD runs the suite" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  _commit_file "a.sh" "echo 1" "feat: a" > /dev/null
  sha2=$(_commit_file "b.sh" "echo 2" "feat: b")
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat ${sha2} refs/heads/feat ${base_sha}\n"
  [ "$status" -eq 0 ]
  [[ "$output" != *"not the pushed commit"* ]]
  [ "$(grep -c "^make " "${MOCK_CALLS_FILE}")" -eq 1 ]
}

@test "wrong-tree: an inert-only push from another commit is not refused" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  sha1=$(_commit_file "docs/a.md" "a" "docs: a")
  _commit_file "docs/b.md" "b" "docs: b" > /dev/null
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat ${sha1} refs/heads/feat ${base_sha}\n"
  [ "$status" -eq 0 ]
  [[ "$output" != *"not the pushed commit"* ]]
  [ ! -f "${MOCK_CALLS_FILE}" ]
}

@test "wrong-tree: an annotated tag at HEAD is peeled and matches" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  _commit_file "a.sh" "echo 1" "feat: a" > /dev/null
  _git_clean "tag -a v1 -m v1"
  tag_sha=$(_git_clean "rev-parse v1")
  _write_make_mock 0
  run _run_pre_push "refs/tags/v1 ${tag_sha} refs/tags/v1 ${base_sha}\n"
  [ "$status" -eq 0 ]
  [[ "$output" != *"not the pushed commit"* ]]
  _assert_suite_ran
}

@test "wrong-tree: a mixed push is refused and names only the stale ref" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  old1=$(_commit_file "docs/a.md" "a" "docs: a")
  old2=$(_commit_file "docs/b.md" "b" "docs: b")
  sha2=$(_commit_file "a.sh" "echo 1" "feat: a")
  _write_make_mock 0
  # Both stale refs precede the HEAD ref, so a refusal that overwrote rather
  # than appended its per-ref lines would name only the last stale one.
  run _run_pre_push "refs/heads/docs1 ${old1} refs/heads/docs1 ${base_sha}\nrefs/heads/docs2 ${old2} refs/heads/docs2 ${base_sha}\nrefs/heads/feat ${sha2} refs/heads/feat ${base_sha}\n"
  [ "$status" -eq 1 ]
  [[ "$output" == *"refs/heads/docs1"* ]]
  [[ "$output" == *"refs/heads/docs2"* ]]
  [[ "$output" != *"refs/heads/feat"* ]]
  [ ! -f "${MOCK_CALLS_FILE}" ]
}

@test "wrong-tree: a tag that peels to no commit is refused as unresolved" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  _commit_file "a.sh" "echo 1" "feat: a" > /dev/null
  _git_clean "tag -a t -m t \"\$(git -C '${REPO_DIR}' rev-parse 'HEAD^{tree}')\""
  tag_sha=$(_git_clean "rev-parse t")
  _write_make_mock 0
  run _run_pre_push "refs/tags/t ${tag_sha} refs/tags/t ${base_sha}\n"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unresolved"* ]]
  [[ "$output" != *"expected commit type"* ]]
  [ ! -f "${MOCK_CALLS_FILE}" ]
}

@test "wrong-tree: an unborn HEAD is refused as unresolved" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  sha1=$(_commit_file "a.sh" "echo 1" "feat: a")
  second="${BATS_TEST_TMPDIR}/repo2"
  bash -c "
    export PATH='${CLEAN_PATH}'
    unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE
    git clone --quiet '${REPO_DIR}' '${second}'
    git -C '${second}' checkout --quiet --orphan empty
    git -C '${second}' rm -rf --quiet --cached .
  "
  _write_make_mock 0
  run _run_pre_push_at "${second}" "refs/heads/feat ${sha1} refs/heads/feat ${base_sha}\n"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unresolved"* ]]
  [ ! -f "${MOCK_CALLS_FILE}" ]
}

@test "wrong-tree: an unborn HEAD and an unpeelable ref are refused, not matched as equal" {
  # Both reads fail here, and two empty values compare equal: only the -z
  # guards keep this fail-closed.
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  _commit_file "a.sh" "echo 1" "feat: a" > /dev/null
  _git_clean "tag -a t -m t \"\$(git -C '${REPO_DIR}' rev-parse 'HEAD^{tree}')\""
  tag_sha=$(_git_clean "rev-parse t")
  second="${BATS_TEST_TMPDIR}/repo2"
  bash -c "
    export PATH='${CLEAN_PATH}'
    unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE
    git clone --quiet '${REPO_DIR}' '${second}'
    git -C '${second}' fetch --quiet origin 'refs/tags/t:refs/tags/t'
    git -C '${second}' checkout --quiet --orphan empty
    git -C '${second}' rm -rf --quiet --cached .
  "
  _write_make_mock 0
  run _run_pre_push_at "${second}" "refs/tags/t ${tag_sha} refs/tags/t ${base_sha}\n"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unresolved"* ]]
  [ ! -f "${MOCK_CALLS_FILE}" ]
}

@test "wrong-tree: the master refusal wins over the wrong-tree refusal" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  sha1=$(_commit_file "a.sh" "echo 1" "feat: a")
  _commit_file "b.sh" "echo 2" "feat: b" > /dev/null
  _write_make_mock 0
  run _run_pre_push "refs/heads/master ${sha1} refs/heads/master ${base_sha}\n"
  [ "$status" -eq 1 ]
  [[ "$output" == *"refusing a direct push to master"* ]]
  [[ "$output" != *"not the pushed commit"* ]]
}

@test "wrong-tree: an exported GIT_DIR naming another worktree cannot fake a match" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  sha1=$(_commit_file "a.sh" "echo 1" "feat: a")
  _commit_file "b.sh" "echo 2" "feat: b" > /dev/null
  wt="${BATS_TEST_TMPDIR}/wt"
  _git_clean "worktree add --quiet --detach '${wt}' ${sha1}"
  _write_make_mock 0
  run _run_pre_push_at "${REPO_DIR}" "refs/heads/feat ${sha1} refs/heads/feat ${base_sha}\n" \
    "export GIT_DIR='${REPO_DIR}/.git/worktrees/wt'"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not the pushed commit"* ]]
  [ ! -f "${MOCK_CALLS_FILE}" ]
}

@test "wrong-tree: an exported GIT_WORK_TREE is the tree tested and is what HEAD is read from" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  sha1=$(_commit_file "a.sh" "echo 1" "feat: a")
  _commit_file "b.sh" "echo 2" "feat: b" > /dev/null
  wt="${BATS_TEST_TMPDIR}/wt"
  _git_clean "worktree add --quiet --detach '${wt}' ${sha1}"
  wt="$(_canon "${wt}")"
  _write_make_mock 0
  run _run_pre_push_at "${REPO_DIR}" "refs/heads/feat ${sha1} refs/heads/feat ${base_sha}\n" \
    "export GIT_WORK_TREE='${wt}'"
  [ "$status" -eq 0 ]
  grep -qxF "make -C ${wt} test" "${MOCK_CALLS_FILE}"
}

@test "wrong-tree: the remedy is the exact push command, with a sha source when the ref is not a refs/ name" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  sha1=$(_commit_file "a.sh" "echo 1" "feat: a")
  _commit_file "b.sh" "echo 2" "feat: b" > /dev/null
  bare="${BATS_TEST_TMPDIR}/origin.git"
  _git_clean "init --quiet --bare '${bare}'"
  _git_clean "remote add origin '${bare}'"
  _write_make_mock 0
  run _run_pre_push_at "${REPO_DIR}" "refs/heads/feat ${sha1} refs/heads/feat ${base_sha}\n" "" "origin"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Push each ref from a checkout whose HEAD is that commit:"* ]]
  [[ "$output" == *"  git push origin refs/heads/feat:refs/heads/feat"* ]]
  [[ "$output" == *"Re-add any flags the original push used (-u, --force-with-lease)."* ]]
  run _run_pre_push_at "${REPO_DIR}" "HEAD~1 ${sha1} refs/heads/feat ${base_sha}\n" "" "origin"
  [ "$status" -eq 1 ]
  [[ "$output" == *"  ${sha1} is at ${sha1:0:7};"* ]]
  [[ "$output" == *"  git push origin ${sha1}:refs/heads/feat"* ]]
  [[ "$output" != *"HEAD~1"* ]]
}

@test "wrong-tree: a URL remote is withheld and the placeholder printed" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  sha1=$(_commit_file "a.sh" "echo 1" "feat: a")
  _commit_file "b.sh" "echo 2" "feat: b" > /dev/null
  bare="${BATS_TEST_TMPDIR}/origin.git"
  _git_clean "init --quiet --bare '${bare}'"
  _git_clean "remote add origin '${bare}'"
  _write_make_mock 0
  run _run_pre_push_at "${REPO_DIR}" "refs/heads/feat ${sha1} refs/heads/feat ${base_sha}\n" "" \
    "'https://token@origin.example.invalid/r.git'"
  [ "$status" -eq 1 ]
  [[ "$output" == *"<remote>"* ]]
  [[ "$output" != *"example.invalid"* ]]
  [[ "$output" != *"token"* ]]
}

# --- dirty tree: the suite runs in a locked, temporary, clean checkout of the
# pushed commit, never in the dirty tree. ---

# Commit README.md and a.sh; sets base_sha and local_sha, installs the make
# mock (exit ${1:-0}) and turns on its tree recording.
_dirty_fixture() {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file "a.sh" "echo 1" "feat: a")
  _write_make_mock "${1:-0}"
  export MAKE_MOCK_RECORD_TREE=1
}

_dirty_push() {
  _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
}

# Edit a committed file in place, uncommitted.
_dirty_edit() {
  printf '%s\n' "$1" > "${REPO_DIR}/a.sh"
}

# The temp root is gone and REPO_DIR is the only registered worktree.
_assert_temp_gone() {
  local _left _listed
  _left="$(find "${TMPDIR}" -mindepth 1 -maxdepth 1 -name 'pre-push.*' | wc -l)"
  [ "${_left}" -eq 0 ]
  _listed="$(git -C "${REPO_DIR}" worktree list --porcelain | sed -n 's/^worktree //p')"
  [ "${_listed}" = "$(_canon "${REPO_DIR}")" ]
}

# The suite ran in the temp checkout of <sha>, recorded at its HEAD, clean.
_assert_ran_in_temp() {
  local _sha="${1}" _tmp _dir
  _tmp="$(_canon "${TMPDIR}")"
  _dir="$(sed -n 's/^tree_dir //p' "${MOCK_CALLS_FILE}")"
  [[ "${_dir}" == "${_tmp}"/pre-push.*/pre-push-"${_sha:0:7}" ]]
  grep -qxF "make -C ${_dir} test" "${MOCK_CALLS_FILE}"
  grep -qxF "tree_head ${_sha}" "${MOCK_CALLS_FILE}"
  grep -qxF "tree_status []" "${MOCK_CALLS_FILE}"
}

# The suite ran in REPO_DIR itself: no temp checkout was recorded.
_assert_ran_in_repo() {
  [ "$(sed -n 's/^tree_dir //p' "${MOCK_CALLS_FILE}")" = "$(_canon "${REPO_DIR}")" ]
}

@test "dirty-tree: clean tree" {
  _dirty_fixture
  run _dirty_push
  [ "$status" -eq 0 ]
  _assert_make_ran
  [[ "$output" != *"uncommitted"* ]]
  [[ "$output" != *"clean checkout"* ]]
  _assert_ran_in_repo
  _assert_temp_gone
}

@test "dirty-tree: modified tracked file" {
  _dirty_fixture
  _dirty_edit "echo 2"
  run _dirty_push
  [ "$status" -eq 0 ]
  [[ "$output" == *"pre-push: working tree has 1 uncommitted or untracked path(s); testing committed ${local_sha:0:7} in clean checkout ${TMPDIR}/pre-push."*"/pre-push-${local_sha:0:7}."* ]]
  _assert_ran_in_temp "${local_sha}"
  grep -qE "^tree_lock pre-push pid [0-9]+ testing ${local_sha:0:7}\$" "${MOCK_CALLS_FILE}"
  [ "$(cat "${REPO_DIR}/a.sh")" = "echo 2" ]
  _assert_temp_gone
}

@test "dirty-tree: uncommitted edit changes the verdict" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file "tests/x.bats" "A" "test: x")
  _write_make_mock 0
  export MAKE_MOCK_RECORD_TREE=1 MAKE_MOCK_REQUIRE_FILE="tests/x.bats" MAKE_MOCK_REQUIRE_CONTENT="A"
  printf 'B\n' > "${REPO_DIR}/tests/x.bats"
  run _dirty_push
  [ "$status" -eq 0 ]
  _assert_ran_in_temp "${local_sha}"
  [ "$(cat "${REPO_DIR}/tests/x.bats")" = "B" ]
  _assert_temp_gone
}

@test "dirty-tree: staged-only change" {
  _dirty_fixture
  _dirty_edit "echo 2"
  _git_clean "add a.sh"
  run _dirty_push
  [ "$status" -eq 0 ]
  _assert_ran_in_temp "${local_sha}"
  _assert_temp_gone
}

@test "dirty-tree: untracked file" {
  _dirty_fixture
  printf 'x\n' > "${REPO_DIR}/new.bats"
  run _dirty_push
  [ "$status" -eq 0 ]
  [[ "$output" == *"working tree has 1 uncommitted or untracked path(s)"* ]]
  _assert_ran_in_temp "${local_sha}"
  _assert_temp_gone
}

@test "dirty-tree: ignored file" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file ".gitignore" "cov/" "chore: ignore cov")
  _write_make_mock 0
  export MAKE_MOCK_RECORD_TREE=1
  mkdir -p "${REPO_DIR}/cov"
  printf 'x\n' > "${REPO_DIR}/cov/x"
  run _dirty_push
  [ "$status" -eq 0 ]
  _assert_make_ran
  [[ "$output" != *"uncommitted"* ]]
  _assert_ran_in_repo
}

@test "dirty-tree: suite fails in temp checkout" {
  _dirty_fixture 2
  _dirty_edit "echo 2"
  run _dirty_push
  [ "$status" -eq 2 ]
  _assert_ran_in_temp "${local_sha}"
  [[ "$output" == *"pre-push: suite failed against committed ${local_sha:0:7} (clean checkout ${TMPDIR}/pre-push."*"/pre-push-${local_sha:0:7}, now removed); uncommitted changes were not tested."* ]]
  _assert_temp_gone
}

@test "dirty-tree: status read fails" {
  _dirty_fixture
  printf 'x' > "${REPO_DIR}/.git/index"
  run _dirty_push
  [ "$status" -eq 0 ]
  [[ "$output" == *"pre-push: could not read the working-tree status; testing committed ${local_sha:0:7} in clean checkout ${TMPDIR}/pre-push."*"/pre-push-${local_sha:0:7}."* ]]
  _assert_ran_in_temp "${local_sha}"
  _assert_temp_gone
}

@test "dirty-tree: inert push dirty tree" {
  base_sha=$(_commit_file "a.sh" "echo 1" "feat: a")
  local_sha=$(_commit_file "docs/a.md" "x" "docs: a")
  _write_make_mock 0
  export MAKE_MOCK_RECORD_TREE=1
  _dirty_edit "echo 2"
  run _dirty_push
  [ "$status" -eq 0 ]
  [ ! -f "${MOCK_CALLS_FILE}" ]
  [[ "$output" != *"uncommitted"* ]]
}

@test "dirty-tree: worktree push dirty main checkout" {
  _dirty_fixture
  wt="${BATS_TEST_TMPDIR}/wt"
  _git_clean "worktree add --quiet --detach '${wt}' ${local_sha}"
  wt="$(_canon "${wt}")"
  _dirty_edit "echo 2"
  run _run_pre_push_at "${wt}" "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 0 ]
  grep -qxF "make -C ${wt} test" "${MOCK_CALLS_FILE}"
  [[ "$output" != *"uncommitted"* ]]
}

@test "dirty-tree: decoy GIT_DIR" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  sha_a=$(_commit_file "a.sh" "echo 1" "feat: a")
  sha_b=$(_commit_file "a.sh" "echo 2" "feat: a2")
  _write_make_mock 0
  export MAKE_MOCK_RECORD_TREE=1
  wt="${BATS_TEST_TMPDIR}/wt"
  _git_clean "worktree add --quiet --detach '${wt}' ${sha_b}"
  wt="$(_canon "${wt}")"
  _git_clean "checkout --quiet --detach ${sha_a}"
  printf 'x\n' > "${REPO_DIR}/junk"
  run _run_pre_push_at "${wt}" "refs/heads/feat/x ${sha_b} refs/heads/feat/x ${sha_a}\n" \
    "export GIT_DIR='${REPO_DIR}/.git'"
  [ "$status" -eq 0 ]
  grep -qxF "make -C ${wt} test" "${MOCK_CALLS_FILE}"
  [[ "$output" != *"uncommitted"* ]]
}

@test "dirty-tree: untracked directory counts each file" {
  _dirty_fixture
  mkdir -p "${REPO_DIR}/newdir"
  printf 'x\n' > "${REPO_DIR}/newdir/one"
  printf 'y\n' > "${REPO_DIR}/newdir/two"
  run _dirty_push
  [ "$status" -eq 0 ]
  [[ "$output" == *"working tree has 2 uncommitted or untracked path(s)"* ]]
  _assert_ran_in_temp "${local_sha}"
  _assert_temp_gone
}

@test "dirty-tree: a single quote in TMPDIR still cleans up" {
  export TMPDIR="${BATS_TEST_TMPDIR}/it's tmp"
  mkdir -p "${TMPDIR}"
  _dirty_fixture
  _dirty_edit "echo 2"
  run _dirty_push
  [ "$status" -eq 0 ]
  _assert_ran_in_temp "${local_sha}"
  _assert_temp_gone
}

@test "dirty-tree: the suite does not inherit an exported GIT_DIR" {
  _dirty_fixture
  _dirty_edit "echo 2"
  _git_clean "add a.sh"
  run _run_pre_push_at "${REPO_DIR}" "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n" \
    "export GIT_DIR='${REPO_DIR}/.git'"
  [ "$status" -eq 0 ]
  _assert_ran_in_temp "${local_sha}"
  _assert_temp_gone
}

_no_checkout_line() {
  printf 'pre-push: could not create a temporary checkout of %s; push refused.' "${local_sha:0:7}"
}

@test "dirty-tree: mktemp fails" {
  _dirty_fixture
  _dirty_edit "echo 2"
  export TMPDIR="${BATS_TEST_TMPDIR}/no-such-dir"
  run _dirty_push
  [ "$status" -eq 1 ]
  [[ "$output" == *"$(_no_checkout_line)"* ]]
  [ ! -f "${MOCK_CALLS_FILE}" ]
}

@test "dirty-tree: worktree add fails" {
  _dirty_fixture
  _dirty_edit "echo 2"
  local _real_git _shim="${BATS_TEST_TMPDIR}/gitshim"
  _real_git="$(PATH="${CLEAN_PATH}" command -v git)"
  mkdir -p "${_shim}"
  cat > "${_shim}/git" <<SHIM
#!/usr/bin/env bash
for _a in "\$@"; do
  if [[ "\${_a}" == worktree ]]; then
    for _b in "\$@"; do [[ "\${_b}" == add ]] && exit 1; done
  fi
done
exec "${_real_git}" "\$@"
SHIM
  chmod +x "${_shim}/git"
  CLEAN_PATH="${_shim}:${CLEAN_PATH}"
  run _dirty_push
  [ "$status" -eq 1 ]
  [[ "$output" == *"$(_no_checkout_line)"* ]]
  [ ! -f "${MOCK_CALLS_FILE}" ]
  [ "$(find "${TMPDIR}" -mindepth 1 -maxdepth 1 -name 'pre-push.*' | wc -l)" -eq 0 ]
}

# _signal_case <TERM|INT> <expected status> -- the make mock signals its own
# process group while the suite runs in the temp checkout.
_signal_case() {
  local _sig="${1}" _want="${2}" _wrapper="${BATS_TEST_TMPDIR}/wrapper.sh"
  _dirty_fixture
  _dirty_edit "echo 2"
  export MAKE_MOCK_SIGNAL="${_sig}"
  # Slow the cleanup's worktree removal so a hook shell that exits without
  # waiting for the subshell's cleanup is caught, not raced.
  local _real_git _shim="${BATS_TEST_TMPDIR}/slowgit"
  _real_git="$(PATH="${CLEAN_PATH}" command -v git)"
  mkdir -p "${_shim}"
  cat > "${_shim}/git" <<SHIM
#!/usr/bin/env bash
for _a in "\$@"; do [[ "\${_a}" == remove ]] && sleep 1; done
exec "${_real_git}" "\$@"
SHIM
  chmod +x "${_shim}/git"
  CLEAN_PATH="${_shim}:${CLEAN_PATH}"
  cat > "${_wrapper}" <<WRAP
#!/usr/bin/env bash
export PATH='${MAKE_MOCK_DIR}:${CLEAN_PATH}'
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE
cd '${REPO_DIR}' || exit 1
exec bash '${REPO_ROOT}/scripts/pre-push' > '${BATS_TEST_TMPDIR}/hook.out' 2>&1 <<< 'refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}'
WRAP
  SECONDS=0
  run _in_new_session "${_wrapper}"
  [ "$output" = "${_want}" ]  # stdout of the hook goes to a file: bats waits on a pipe the cleanup would hold open
  [ "${SECONDS}" -lt 8 ]
  grep -q '^tree_lock ' "${MOCK_CALLS_FILE}"
  grep -q '^tree_listed .*pre-push-' "${MOCK_CALLS_FILE}"
  _assert_temp_gone
}

@test "dirty-tree: interrupt (TERM)" {
  _signal_case TERM 143
}

@test "dirty-tree: interrupt (INT)" {
  _signal_case INT 130
}

@test "dirty-tree: an undeletable temp file does not change the verdict" {
  [[ "${EUID}" -ne 0 ]] || skip "root ignores 0555; case needs a non-root user"
  _dirty_fixture
  _dirty_edit "echo 2"
  export MAKE_MOCK_UNDELETABLE=1
  run _dirty_push
  chmod -R u+w "${TMPDIR}"
  [ "$status" -eq 0 ]
}
