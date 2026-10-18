#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  CLEAN_PATH="$(printf "%s" "${PATH}" | tr ':' '\n' | grep -v "tests/mocks" | tr '\n' ':' | sed 's/:$//')"
  REPO_DIR="${BATS_TEST_TMPDIR}/repo"
  MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  MAKE_MOCK_DIR="${BATS_TEST_TMPDIR}/makebin"
  mkdir -p "${REPO_DIR}" "${MAKE_MOCK_DIR}"
  bash -c "
    export PATH='${CLEAN_PATH}'
    unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE
    git -C '${REPO_DIR}' init --quiet
    git -C '${REPO_DIR}' config user.email 'test@test.com'
    git -C '${REPO_DIR}' config user.name 'Test'
  "
}

teardown() {
  rm -f "${MOCK_CALLS_FILE:-}"
}

_write_make_mock() {
  local _exit="${1:-0}"
  cat > "${MAKE_MOCK_DIR}/make" <<EOF
#!/usr/bin/env bash
printf "make %s\n" "\$*" >> "${MOCK_CALLS_FILE}"
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
  grep -qE "^make -C .* test$" "${MOCK_CALLS_FILE}"
}

@test "pre-push runs make test when only scripts/pre-push changed" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file "scripts/pre-push" "# hook" "chore: touch hook")
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 0 ]
  grep -qE "^make -C .* test$" "${MOCK_CALLS_FILE}"
}

@test "pre-push runs make test when only scripts/commit-msg changed" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file "scripts/commit-msg" "# hook" "chore: touch hook")
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 0 ]
  grep -qE "^make -C .* test$" "${MOCK_CALLS_FILE}"
}

@test "pre-push runs make test when only a .zsh file changed" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file ".config/.zshrc.d/2_functions.zsh" "echo hi" "feat: add a zsh function")
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 0 ]
  grep -qE "^make -C .* test$" "${MOCK_CALLS_FILE}"
}

@test "pre-push runs make test when only .shellcheckrc changed" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file ".shellcheckrc" "disable=SC2086" "chore: touch shellcheckrc")
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 0 ]
  grep -qE "^make -C .* test$" "${MOCK_CALLS_FILE}"
}

@test "pre-push runs make test when only .gitignore changed" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file ".gitignore" "*.log" "chore: touch gitignore")
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 0 ]
  grep -qE "^make -C .* test$" "${MOCK_CALLS_FILE}"
}

@test "pre-push triggers on a non-markdown file under docs/, not just .gitignore" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file "docs/.gitignore" "*.log" "chore: nested gitignore")
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 0 ]
  grep -qE "^make -C .* test$" "${MOCK_CALLS_FILE}"
}

@test "pre-push triggers on a root file merely prefixed with .gitignore" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file ".gitignore_global" "*.log" "chore: global ignore")
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 0 ]
  grep -qE "^make -C .* test$" "${MOCK_CALLS_FILE}"
}

@test "pre-push runs make test when only Makefile changed" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file "Makefile" "test:" "chore: touch Makefile")
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 0 ]
  grep -qE "^make -C .* test$" "${MOCK_CALLS_FILE}"
}

@test "pre-push runs make test when only a non-source file under tests/ changed" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file "tests/fixtures/sample.txt" "fixture" "chore: touch tests fixture")
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 0 ]
  grep -qE "^make -C .* test$" "${MOCK_CALLS_FILE}"
}

@test "pre-push triggers when only .zshrc changed" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file ".zshrc" "echo hi" "chore: touch zshrc")
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 0 ]
  grep -qE "^make -C .* test$" "${MOCK_CALLS_FILE}"
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
  grep -qE "^make -C .* test$" "${MOCK_CALLS_FILE}"
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
  grep -qE "^make -C .* test$" "${MOCK_CALLS_FILE}"
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
  grep -qE "^make -C .* test$" "${MOCK_CALLS_FILE}"
  run ! grep -qE "^GIT_(DIR|WORK_TREE|COMMON_DIR|INDEX_FILE)=" "${MOCK_CALLS_FILE}"
}

@test "pre-push runs make test when only ubuntu_common_packages.txt changed" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file "ubuntu_common_packages.txt" "curl" "chore: touch ubuntu packages")
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 0 ]
  grep -qE "^make -C .* test$" "${MOCK_CALLS_FILE}"
}

@test "pre-push runs make test when only starship.toml changed" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file "starship.toml" "format = x" "chore: touch starship config")
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 0 ]
  grep -qE "^make -C .* test$" "${MOCK_CALLS_FILE}"
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
  grep -qE "^make -C .* test$" "${MOCK_CALLS_FILE}"
}

@test "pre-push triggers on a mixed diff with one inert and one non-inert path" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  _commit_file "README.md" "v2" "docs: v2" > /dev/null
  local_sha=$(_commit_file "setup_env.sh" "echo hi" "feat: touch setup_env")
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 0 ]
  grep -qE "^make -C .* test$" "${MOCK_CALLS_FILE}"
}

@test "pre-push triggers on a LICENSE outside the repo root" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file "docs/LICENSE" "text" "chore: nested license")
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 0 ]
  grep -qE "^make -C .* test$" "${MOCK_CALLS_FILE}"
}

@test "pre-push triggers on a .github directory outside the repo root" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file "docs/.github/x.yml" "on: push" "chore: nested github dir")
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 0 ]
  grep -qE "^make -C .* test$" "${MOCK_CALLS_FILE}"
}

@test "pre-push triggers on a .github file merely suffixed after .yml" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file ".github/workflows/ci.yml.bak" "backup" "chore: yml backup")
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 0 ]
  grep -qE "^make -C .* test$" "${MOCK_CALLS_FILE}"
}

@test "pre-push runs the suite for a .github workflow using the .yaml spelling" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file ".github/workflows/x.yaml" "on: push" "ci: yaml spelling")
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 0 ]
  grep -qE "^make -C .* test$" "${MOCK_CALLS_FILE}"
}

@test "pre-push triggers on a markdown fixture under tests/" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file "tests/fixtures/expected_output.md" "expected" "test: md fixture")
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 0 ]
  grep -qE "^make -C .* test$" "${MOCK_CALLS_FILE}"
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
  grep -qE "^make -C .* test$" "${MOCK_CALLS_FILE}"
}

@test "pre-push triggers on a .mdx file, not just .md" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file "foo.mdx" "content" "chore: add mdx file")
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 0 ]
  grep -qE "^make -C .* test$" "${MOCK_CALLS_FILE}"
}

@test "pre-push triggers when a shell script exists under docs/" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file "docs/gen.sh" "echo hi" "chore: add docs gen script")
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 0 ]
  grep -qE "^make -C .* test$" "${MOCK_CALLS_FILE}"
}

@test "pre-push triggers when a shell script exists under .github/" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file ".github/scripts/foo.sh" "echo hi" "chore: add github script")
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 0 ]
  grep -qE "^make -C .* test$" "${MOCK_CALLS_FILE}"
}

@test "pre-push triggers on CHANGELOG_gen.sh" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file "CHANGELOG_gen.sh" "echo hi" "chore: add changelog gen script")
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 0 ]
  grep -qE "^make -C .* test$" "${MOCK_CALLS_FILE}"
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
  grep -qE "^make -C .* test$" "${MOCK_CALLS_FILE}"
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
  grep -qE "^make -C .* test$" "${MOCK_CALLS_FILE}"
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
  grep -qE "^make -C .* test$" "${MOCK_CALLS_FILE}"
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
  run _run_pre_push "refs/heads/feat/x ${sha1} refs/heads/feat/x ${base_sha}\nrefs/heads/master ${sha2} refs/heads/master ${sha1}\n"
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
    git -C '${REPO_DIR}' commit --quiet -m 'docs: claude md'
    git -C '${REPO_DIR}' rev-parse HEAD
  "
}

@test "budget gate refuses a CLAUDE.md-only push of 105001 bytes and names the ceiling" {
  base_sha=$(_budget_commit 100)
  local_sha=$(_budget_commit 105001)
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 1 ]
  [ ! -f "${MOCK_CALLS_FILE}" ]
  [[ "$output" == *"105,000 bytes"* ]]
  [[ "$output" == *"refs/heads/feat/x"* ]]
}

@test "budget gate allows a CLAUDE.md of exactly 105000 bytes" {
  base_sha=$(_budget_commit 100)
  local_sha=$(_budget_commit 105000)
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 0 ]
}

@test "budget gate does not refuse a pushed commit that predates the checker" {
  base_sha=$(_budget_commit 100 nochecker)
  local_sha=$(_budget_commit 105001 nochecker)
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 0 ]
  [[ "$output" != *"105,000 bytes"* ]]
}

@test "budget gate runs the committed checker, not the working-tree copy" {
  base_sha=$(_budget_commit 100)
  local_sha=$(_budget_commit 105001)
  printf 'import sys\nsys.exit(0)\n' > "${REPO_DIR}/scripts/claude_md_budget.py"
  _write_make_mock 0
  run _run_pre_push "refs/heads/feat/x ${local_sha} refs/heads/feat/x ${base_sha}\n"
  [ "$status" -eq 1 ]
  [[ "$output" == *"105,000 bytes"* ]]
}

@test "budget gate refuses a two-ref push whose first ref is over the ceiling" {
  base_sha=$(_budget_commit 100)
  bad_sha=$(_budget_commit 105001)
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
  bad_sha=$(_budget_commit 105001)
  _git_clean "checkout --quiet -B stub ${base_sha}"
  _commit_file "scripts/claude_md_budget.py" "import sys; sys.exit(0)" "chore: stub checker" > /dev/null
  _write_make_mock 0
  run _run_pre_push "refs/heads/bad ${bad_sha} refs/heads/bad ${base_sha}\n"
  [ "$status" -eq 1 ]
  [[ "$output" == *"105,000 bytes"* ]]
}

@test "budget gate detects the pushed commit's checker when HEAD has none" {
  base_sha=$(_budget_commit 100 nochecker)
  _git_clean "checkout --quiet -B bad ${base_sha}"
  bad_sha=$(_budget_commit 105001)
  _git_clean "checkout --quiet -B none ${base_sha}"
  _write_make_mock 0
  run _run_pre_push "refs/heads/bad ${bad_sha} refs/heads/bad ${base_sha}\n"
  [ "$status" -eq 1 ]
  [[ "$output" == *"105,000 bytes"* ]]
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
  one_sha=$(_budget_commit 105001)
  _git_clean "checkout --quiet -B two ${base_sha}"
  two_sha=$(_budget_commit 105002)
  _write_make_mock 0
  run _run_pre_push "refs/heads/one ${one_sha} refs/heads/one ${base_sha}\nrefs/heads/two ${two_sha} refs/heads/two ${base_sha}\n"
  [ "$status" -eq 1 ]
  [[ "$output" == *"refs/heads/one"* ]]
  [[ "$output" == *"refs/heads/two"* ]]
}
