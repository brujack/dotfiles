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
    unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
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
    unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
    mkdir -p \"\$(dirname '${REPO_DIR}/${_path}')\"
    printf '%s\n' '${_content}' > '${REPO_DIR}/${_path}'
    git -C '${REPO_DIR}' add '${_path}'
    git -C '${REPO_DIR}' commit --quiet -m '${_msg}'
    git -C '${REPO_DIR}' rev-parse HEAD
  "
}

_run_pre_push() {
  local _stdin="${1}"
  local _path_with_make="${MAKE_MOCK_DIR}:${CLEAN_PATH}"
  printf "%b" "${_stdin}" | bash -c "
    export PATH='${_path_with_make}'
    unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
    cd '${REPO_DIR}' && bash '${REPO_ROOT}/scripts/pre-push'
  "
}

@test "pre-push skips the test run when only non-triggering files changed" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file "README.md" "v2" "docs: v2")
  _write_make_mock 0
  run _run_pre_push "refs/heads/master ${local_sha} refs/heads/master ${base_sha}\n"
  [ "$status" -eq 0 ]
  [ ! -f "${MOCK_CALLS_FILE}" ]
}

@test "pre-push runs make test when a .sh file changed" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file "deploy.sh" "echo hi" "feat: add deploy script")
  _write_make_mock 0
  run _run_pre_push "refs/heads/master ${local_sha} refs/heads/master ${base_sha}\n"
  [ "$status" -eq 0 ]
  grep -qE "^make -C .* test$" "${MOCK_CALLS_FILE}"
}

@test "pre-push runs make test when only scripts/pre-push changed" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file "scripts/pre-push" "# hook" "chore: touch hook")
  _write_make_mock 0
  run _run_pre_push "refs/heads/master ${local_sha} refs/heads/master ${base_sha}\n"
  [ "$status" -eq 0 ]
  grep -qE "^make -C .* test$" "${MOCK_CALLS_FILE}"
}

@test "pre-push runs make test when only scripts/commit-msg changed" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file "scripts/commit-msg" "# hook" "chore: touch hook")
  _write_make_mock 0
  run _run_pre_push "refs/heads/master ${local_sha} refs/heads/master ${base_sha}\n"
  [ "$status" -eq 0 ]
  grep -qE "^make -C .* test$" "${MOCK_CALLS_FILE}"
}

@test "pre-push runs make test when only a .zsh file changed" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file ".config/.zshrc.d/2_functions.zsh" "echo hi" "feat: add a zsh function")
  _write_make_mock 0
  run _run_pre_push "refs/heads/master ${local_sha} refs/heads/master ${base_sha}\n"
  [ "$status" -eq 0 ]
  grep -qE "^make -C .* test$" "${MOCK_CALLS_FILE}"
}

@test "pre-push runs make test when only .shellcheckrc changed" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file ".shellcheckrc" "disable=SC2086" "chore: touch shellcheckrc")
  _write_make_mock 0
  run _run_pre_push "refs/heads/master ${local_sha} refs/heads/master ${base_sha}\n"
  [ "$status" -eq 0 ]
  grep -qE "^make -C .* test$" "${MOCK_CALLS_FILE}"
}

@test "pre-push runs make test when only .gitignore changed" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file ".gitignore" "*.log" "chore: touch gitignore")
  _write_make_mock 0
  run _run_pre_push "refs/heads/master ${local_sha} refs/heads/master ${base_sha}\n"
  [ "$status" -eq 0 ]
  grep -qE "^make -C .* test$" "${MOCK_CALLS_FILE}"
}

@test "pre-push triggers on a non-markdown file under docs/, not just .gitignore" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file "docs/.gitignore" "*.log" "chore: nested gitignore")
  _write_make_mock 0
  run _run_pre_push "refs/heads/master ${local_sha} refs/heads/master ${base_sha}\n"
  [ "$status" -eq 0 ]
  grep -qE "^make -C .* test$" "${MOCK_CALLS_FILE}"
}

@test "pre-push triggers on a root file merely prefixed with .gitignore" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file ".gitignore_global" "*.log" "chore: global ignore")
  _write_make_mock 0
  run _run_pre_push "refs/heads/master ${local_sha} refs/heads/master ${base_sha}\n"
  [ "$status" -eq 0 ]
  grep -qE "^make -C .* test$" "${MOCK_CALLS_FILE}"
}

@test "pre-push runs make test when only Makefile changed" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file "Makefile" "test:" "chore: touch Makefile")
  _write_make_mock 0
  run _run_pre_push "refs/heads/master ${local_sha} refs/heads/master ${base_sha}\n"
  [ "$status" -eq 0 ]
  grep -qE "^make -C .* test$" "${MOCK_CALLS_FILE}"
}

@test "pre-push runs make test when only a non-source file under tests/ changed" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file "tests/fixtures/sample.txt" "fixture" "chore: touch tests fixture")
  _write_make_mock 0
  run _run_pre_push "refs/heads/master ${local_sha} refs/heads/master ${base_sha}\n"
  [ "$status" -eq 0 ]
  grep -qE "^make -C .* test$" "${MOCK_CALLS_FILE}"
}

@test "pre-push triggers when only .zshrc changed" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file ".zshrc" "echo hi" "chore: touch zshrc")
  _write_make_mock 0
  run _run_pre_push "refs/heads/master ${local_sha} refs/heads/master ${base_sha}\n"
  [ "$status" -eq 0 ]
  grep -qE "^make -C .* test$" "${MOCK_CALLS_FILE}"
}

@test "pre-push skips a top-level path merely prefixed with scripts because it is a markdown file" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file "scripts-old/notes.md" "notes" "docs: notes")
  _write_make_mock 0
  run _run_pre_push "refs/heads/master ${local_sha} refs/heads/master ${base_sha}\n"
  [ "$status" -eq 0 ]
  [ ! -f "${MOCK_CALLS_FILE}" ]
}

@test "pre-push propagates a make test failure as a non-zero exit" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file "deploy.sh" "echo hi" "feat: add deploy script")
  _write_make_mock 1
  run _run_pre_push "refs/heads/master ${local_sha} refs/heads/master ${base_sha}\n"
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
  run _run_pre_push "refs/heads/old-feature 0000000000000000000000000000000000000000 refs/heads/old-feature abc123\nrefs/heads/master ${local_sha} refs/heads/master ${base_sha}\n"
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
  run _run_pre_push_leaked "refs/heads/master ${local_sha} refs/heads/master ${base_sha}\n"
  [ "$status" -eq 0 ]
  grep -qE "^make -C .* test$" "${MOCK_CALLS_FILE}"
  run ! grep -qE "^GIT_(DIR|WORK_TREE|COMMON_DIR|INDEX_FILE)=" "${MOCK_CALLS_FILE}"
}

@test "pre-push runs make test when only ubuntu_common_packages.txt changed" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file "ubuntu_common_packages.txt" "curl" "chore: touch ubuntu packages")
  _write_make_mock 0
  run _run_pre_push "refs/heads/master ${local_sha} refs/heads/master ${base_sha}\n"
  [ "$status" -eq 0 ]
  grep -qE "^make -C .* test$" "${MOCK_CALLS_FILE}"
}

@test "pre-push runs make test when only starship.toml changed" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file "starship.toml" "format = x" "chore: touch starship config")
  _write_make_mock 0
  run _run_pre_push "refs/heads/master ${local_sha} refs/heads/master ${base_sha}\n"
  [ "$status" -eq 0 ]
  grep -qE "^make -C .* test$" "${MOCK_CALLS_FILE}"
}

@test "pre-push skips when only a docs/adr file changed" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file "docs/adr/0017-x.md" "# ADR" "docs: touch adr")
  _write_make_mock 0
  run _run_pre_push "refs/heads/master ${local_sha} refs/heads/master ${base_sha}\n"
  [ "$status" -eq 0 ]
  [ ! -f "${MOCK_CALLS_FILE}" ]
}

@test "pre-push skips when only a .github/workflows file changed" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file ".github/workflows/ci.yml" "name: CI" "chore: touch ci workflow")
  _write_make_mock 0
  run _run_pre_push "refs/heads/master ${local_sha} refs/heads/master ${base_sha}\n"
  [ "$status" -eq 0 ]
  [ ! -f "${MOCK_CALLS_FILE}" ]
}

@test "pre-push triggers on a mixed diff with one inert and one non-inert path" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  _commit_file "README.md" "v2" "docs: v2" > /dev/null
  local_sha=$(_commit_file "setup_env.sh" "echo hi" "feat: touch setup_env")
  _write_make_mock 0
  run _run_pre_push "refs/heads/master ${local_sha} refs/heads/master ${base_sha}\n"
  [ "$status" -eq 0 ]
  grep -qE "^make -C .* test$" "${MOCK_CALLS_FILE}"
}

@test "pre-push skips when only LICENSE changed" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file "LICENSE" "MIT" "chore: touch license")
  _write_make_mock 0
  run _run_pre_push "refs/heads/master ${local_sha} refs/heads/master ${base_sha}\n"
  [ "$status" -eq 0 ]
  [ ! -f "${MOCK_CALLS_FILE}" ]
}

@test "pre-push triggers on a file merely prefixed with LICENSE" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file "LICENSE.txt" "MIT" "chore: add license txt")
  _write_make_mock 0
  run _run_pre_push "refs/heads/master ${local_sha} refs/heads/master ${base_sha}\n"
  [ "$status" -eq 0 ]
  grep -qE "^make -C .* test$" "${MOCK_CALLS_FILE}"
}

@test "pre-push triggers on a .mdx file, not just .md" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file "foo.mdx" "content" "chore: add mdx file")
  _write_make_mock 0
  run _run_pre_push "refs/heads/master ${local_sha} refs/heads/master ${base_sha}\n"
  [ "$status" -eq 0 ]
  grep -qE "^make -C .* test$" "${MOCK_CALLS_FILE}"
}

@test "pre-push triggers when a shell script exists under docs/" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file "docs/gen.sh" "echo hi" "chore: add docs gen script")
  _write_make_mock 0
  run _run_pre_push "refs/heads/master ${local_sha} refs/heads/master ${base_sha}\n"
  [ "$status" -eq 0 ]
  grep -qE "^make -C .* test$" "${MOCK_CALLS_FILE}"
}

@test "pre-push triggers when a shell script exists under .github/" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file ".github/scripts/foo.sh" "echo hi" "chore: add github script")
  _write_make_mock 0
  run _run_pre_push "refs/heads/master ${local_sha} refs/heads/master ${base_sha}\n"
  [ "$status" -eq 0 ]
  grep -qE "^make -C .* test$" "${MOCK_CALLS_FILE}"
}

@test "pre-push triggers on CHANGELOG_gen.sh" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  local_sha=$(_commit_file "CHANGELOG_gen.sh" "echo hi" "chore: add changelog gen script")
  _write_make_mock 0
  run _run_pre_push "refs/heads/master ${local_sha} refs/heads/master ${base_sha}\n"
  [ "$status" -eq 0 ]
  grep -qE "^make -C .* test$" "${MOCK_CALLS_FILE}"
}

@test "pre-push skips when the diff range contains no changes" {
  base_sha=$(_commit_file "README.md" "v1" "docs: v1")
  _write_make_mock 0
  run _run_pre_push "refs/heads/master ${base_sha} refs/heads/master ${base_sha}\n"
  [ "$status" -eq 0 ]
  [ ! -f "${MOCK_CALLS_FILE}" ]
}

@test "pre-push fails closed and triggers when the diff range cannot be resolved" {
  local_sha=$(_commit_file "README.md" "v1" "docs: v1")
  bogus_sha="deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
  _write_make_mock 0
  run _run_pre_push "refs/heads/master ${local_sha} refs/heads/master ${bogus_sha}\n"
  [ "$status" -eq 0 ]
  grep -qE "^make -C .* test$" "${MOCK_CALLS_FILE}"
}
