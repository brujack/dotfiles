#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  # Use real git (exclude git mock from PATH so `git rev-parse --show-toplevel` works)
  CLEAN_PATH="$(printf "%s" "${PATH}" | tr ':' '\n' | grep -v "tests/mocks" | tr '\n' ':' | sed 's/:$//')"
  REPO_DIR="${BATS_TEST_TMPDIR}/repo"
  MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  mkdir -p "${REPO_DIR}"
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

_write_makefile() {
  local _lint_exit="${1}"
  printf 'lint:\n\t@exit %s\n' "${_lint_exit}" > "${REPO_DIR}/Makefile"
}

_write_ggshield_mock() {
  local _exit="${1:-0}"
  cat > "${BATS_TEST_TMPDIR}/ggshield" <<EOF
#!/usr/bin/env bash
printf "ggshield %s\n" "\$*" >> "${MOCK_CALLS_FILE}"
exit ${_exit}
EOF
  chmod +x "${BATS_TEST_TMPDIR}/ggshield"
}

@test "pre-commit-hook.sh exits 0 when lint passes and ggshield is absent" {
  _write_makefile 0
  run bash -c "export PATH='${CLEAN_PATH}'; cd '${REPO_DIR}' && bash '${REPO_ROOT}/scripts/pre-commit-hook.sh'"
  [ "$status" -eq 0 ]
}

@test "pre-commit-hook.sh exits 1 when lint fails, and never invokes ggshield" {
  _write_makefile 1
  _write_ggshield_mock 0
  local path_with_ggshield="${BATS_TEST_TMPDIR}:${CLEAN_PATH}"
  run bash -c "export PATH='${path_with_ggshield}'; cd '${REPO_DIR}' && bash '${REPO_ROOT}/scripts/pre-commit-hook.sh'"
  [ "$status" -eq 1 ]
  run grep -q "ggshield" "${MOCK_CALLS_FILE}"
  [ "$status" -ne 0 ]
}

@test "pre-commit-hook.sh runs ggshield with pre-commit args when present and lint passes" {
  _write_makefile 0
  _write_ggshield_mock 0
  local path_with_ggshield="${BATS_TEST_TMPDIR}:${CLEAN_PATH}"
  run bash -c "export PATH='${path_with_ggshield}'; cd '${REPO_DIR}' && bash '${REPO_ROOT}/scripts/pre-commit-hook.sh'"
  [ "$status" -eq 0 ]
  grep -q "ggshield secret scan pre-commit" "${MOCK_CALLS_FILE}"
}

@test "pre-commit-hook.sh exits 1 when ggshield fails" {
  _write_makefile 0
  _write_ggshield_mock 1
  local path_with_ggshield="${BATS_TEST_TMPDIR}:${CLEAN_PATH}"
  run bash -c "export PATH='${path_with_ggshield}'; cd '${REPO_DIR}' && bash '${REPO_ROOT}/scripts/pre-commit-hook.sh'"
  [ "$status" -eq 1 ]
}
