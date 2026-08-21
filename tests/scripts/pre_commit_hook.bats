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

# _hook_env -- run the hook with ggshield resolution driven entirely by the
# seams, never by PATH. PATH cannot express "ggshield is absent" on a dev
# machine: /opt/homebrew/bin is in CLEAN_PATH and holds a real ggshield, so a
# PATH-only test of the absent branch invokes the real binary and asserts
# nothing. Measured 2026-08-21 -- the case this replaces claimed "ggshield is
# absent" while ggshield was present the whole time.
_run_hook() {
  run bash -c "export PATH='${CLEAN_PATH}'; $* cd '${REPO_DIR}' && bash '${REPO_ROOT}/scripts/pre-commit-hook.sh'"
}

# MINIMAL_PATH holds git and make and NOT ggshield, so `command -v ggshield`
# genuinely fails. Verified on this machine: /usr/bin/git and /usr/bin/make
# exist, /bin/bash exists, and ggshield resolves nowhere under it.
#
# Deliberately a minimal real PATH rather than stripping the directory that
# contains ggshield: /opt/homebrew/bin also holds the toolchain, so removing it
# to remove one binary takes git, make and friends with it -- the "delete a
# directory to delete one binary" trap this repo has paid for before.
MINIMAL_PATH="/usr/bin:/bin"

_run_hook_no_ggshield_on_path() {
  run bash -c "export PATH='${MINIMAL_PATH}'; $* cd '${REPO_DIR}' && bash '${REPO_ROOT}/scripts/pre-commit-hook.sh'"
}

@test "hook exits 0 when lint passes and ggshield genuinely cannot be resolved" {
  _write_makefile 0
  _run_hook_no_ggshield_on_path "export GGSHIELD_BIN='' ; export GGSHIELD_FALLBACK_PATHS='${BATS_TEST_TMPDIR}/nowhere';"
  [ "$status" -eq 0 ]
}

@test "hook ANNOUNCES the skip when ggshield cannot be resolved" {
  # The point of the change. A security arm that does not run must say so:
  # silence is indistinguishable from "scanned and found nothing", and a hook
  # inherits whoever invoked git, so the non-interactive actors are exactly the
  # ones nobody is watching.
  _write_makefile 0
  _run_hook_no_ggshield_on_path "export GGSHIELD_BIN='' ; export GGSHIELD_FALLBACK_PATHS='${BATS_TEST_TMPDIR}/nowhere';"
  [ "$status" -eq 0 ]
  [[ "${output}" == *"SECRET SCAN DID NOT RUN"* ]]
}

@test "hook resolves ggshield via GGSHIELD_BIN when it is not on PATH" {
  _write_makefile 0
  _write_ggshield_mock 0
  _run_hook "export GGSHIELD_BIN='${BATS_TEST_TMPDIR}/ggshield';"
  [ "$status" -eq 0 ]
  grep -q "ggshield secret scan pre-commit" "${MOCK_CALLS_FILE}"
}

@test "hook resolves ggshield via an absolute fallback path when not on PATH" {
  # The Linux workstation case: ggshield exists at
  # /home/linuxbrew/.linuxbrew/bin/ggshield but that prefix reaches PATH only
  # through .config/.zshrc.d/6_path.zsh, which INTERACTIVE zsh alone sources.
  # Measured on that box: zsh -i -c resolves it; zsh -l -c, cron, ssh and
  # env -i sh all do not.
  _write_makefile 0
  _write_ggshield_mock 0
  _run_hook_no_ggshield_on_path "export GGSHIELD_BIN='' ; export GGSHIELD_FALLBACK_PATHS='${BATS_TEST_TMPDIR}/ggshield';"
  [ "$status" -eq 0 ]
  grep -q "ggshield secret scan pre-commit" "${MOCK_CALLS_FILE}"
}

@test "hook fails loudly when GGSHIELD_BIN names something non-executable" {
  # An explicit override that does not resolve is an operator error, not an
  # absent tool -- it must not degrade into the announce-and-continue path.
  _write_makefile 0
  _run_hook "export GGSHIELD_BIN='${BATS_TEST_TMPDIR}/no-such-binary';"
  [ "$status" -ne 0 ]
  [[ "${output}" == *"GGSHIELD_BIN"* ]]
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
