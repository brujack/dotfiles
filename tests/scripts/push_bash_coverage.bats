#!/usr/bin/env bats

load '../helpers/common.bash'

# scripts/push-bash-coverage.sh has no _OVERRIDE_* seam: REPO_ROOT is always
# derived from its own BASH_SOURCE, and it unconditionally shells out to the
# REAL sibling "${REPO_ROOT}/scripts/run-bash-coverage.sh --json ...". That
# sibling script is the multi-minute, self-recursive coverage tracer this very
# suite runs under during `make bash-coverage` / `bash scripts/run-bash-coverage.sh`.
# Letting it fire for real from inside an already-running tracer pass would
# `rm`/`mkfifo` the SAME trace FIFO the live run is reading from, then invoke
# `bats --recursive` again — which re-enters this very test file and recurses
# without bound.
#
# The script must still be invoked at its REAL absolute repo path for the
# tracer to attribute any executed line back to it at all (the tracer's PS4
# uses ${BASH_SOURCE} verbatim, and per-file coverage is matched by an exact
# string prefix against that real path — see run-bash-coverage.sh). So the
# fake-REPO_ROOT-copy approach other scripts' tests use is not available here;
# copying the script elsewhere would make every line trace under a path the
# tracer's matcher never credits.
#
# The fix applied here: shadow `bash` itself on PATH for the duration of each
# test. The shim inspects only its first argument (the script path bash was
# asked to run) and intercepts exactly the one call ending in
# "run-bash-coverage.sh", handing it to a safe local stub instead; every other
# invocation (including the outer `bash .../push-bash-coverage.sh` call this
# suite makes) is handed to the real bash. The shim's shebang is the real
# bash's own absolute path, never `#!/usr/bin/env bash` — with the shim
# directory first on PATH, `env bash` would resolve back to this same shim
# and recurse via exec.
setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  SHIM_DIR="${BATS_TEST_TMPDIR}/shim-bin"
  mkdir -p "${SHIM_DIR}"

  REAL_BASH="$(command -v bash)"
  STUB_RUNNER="${SHIM_DIR}/stub-run-bash-coverage.sh"
  MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls.log"
  : > "${MOCK_CALLS_FILE}"
  export MOCK_CALLS_FILE

  COVERAGE_WORKTREE="${REPO_ROOT}/.coverage-data-worktree"
  BADGE_JSON="${REPO_ROOT}/coverage/bash.json"
  BADGE_BACKUP="${BATS_TEST_TMPDIR}/badge_backup.json"
  mkdir -p "$(dirname "${BADGE_JSON}")"
  if [[ -f "${BADGE_JSON}" ]]; then
    cp "${BADGE_JSON}" "${BADGE_BACKUP}"
  fi
  rm -f "${BADGE_JSON}"
  rm -rf "${COVERAGE_WORKTREE}"

  cat > "${SHIM_DIR}/bash" <<EOF
#!${REAL_BASH}
if [[ "\${1:-}" == *run-bash-coverage.sh ]]; then
  shift
  exec "${STUB_RUNNER}" "\$@"
fi
exec "${REAL_BASH}" "\$@"
EOF
  chmod +x "${SHIM_DIR}/bash"

  # Fake run-bash-coverage.sh: writes a shields.io badge JSON to the path
  # given via --json, exactly like the real one's own --json contract, but
  # instantly and without touching the real tracer/FIFO/bats-recursive machinery.
  cat > "${STUB_RUNNER}" <<EOF
#!${REAL_BASH}
_out=""
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    --json) _out="\$2"; shift 2 ;;
    *) shift ;;
  esac
done
if [[ -n "\${_out}" && "\${STUB_SKIP_WRITE:-0}" != "1" ]]; then
  mkdir -p "\$(dirname "\${_out}")"
  printf '%s' "\${STUB_COVERAGE_JSON:-{\"schemaVersion\":1,\"label\":\"bash coverage\",\"message\":\"91%\",\"color\":\"brightgreen\"}}" > "\${_out}"
fi
exit "\${STUB_RUN_COVERAGE_EXIT:-0}"
EOF
  chmod +x "${STUB_RUNNER}"

  # tests/mocks/git is a no-op stub that never creates the directories
  # `git worktree add` is supposed to create, so the script's own `cp` into
  # the worktree would fail before the diff/commit/push branches under test
  # ever ran. This mock performs the minimal real filesystem side effects
  # (mkdir/rm) push-bash-coverage.sh depends on, while still never touching a
  # real remote, never running a real `git worktree add`/push.
  cat > "${SHIM_DIR}/git" <<EOF
#!${REAL_BASH}
printf 'git %s\n' "\$*" >> "\${MOCK_CALLS_FILE:-/tmp/mock_calls}"

# The worktree arms below run a real \`rm -rf\` on a path taken from argv. The
# shim exists to exercise the script misbehaving, so the path it is handed is
# exactly the thing under test and cannot be assumed sane. Refuse any path that
# is not the one worktree this suite is allowed to touch — a test that drives
# the script somewhere unexpected should fail loudly, not delete it.
_shim_guard_path() {
  [[ "\$1" == "${COVERAGE_WORKTREE}" ]] && return 0
  printf 'SHIM REFUSED destructive op on unexpected path: %s\n' "\$1" >&2
  return 1
}

case "\$*" in
  "fetch origin coverage-data"*)
    exit "\${MOCK_GIT_FETCH_EXIT:-0}" ;;
  "worktree add "*)
    if [[ "\${MOCK_GIT_WORKTREE_ADD_EXIT:-0}" -ne 0 ]]; then
      exit "\${MOCK_GIT_WORKTREE_ADD_EXIT}"
    fi
    _shim_guard_path "\$3" && mkdir -p "\$3"
    exit 0 ;;
  "worktree remove --force "*)
    _shim_guard_path "\$4" && rm -rf "\$4" 2>/dev/null
    exit "\${MOCK_GIT_WORKTREE_REMOVE_FORCE_EXIT:-0}" ;;
  "worktree remove "*)
    _shim_guard_path "\$3" && rm -rf "\$3" 2>/dev/null
    exit "\${MOCK_GIT_WORKTREE_REMOVE_EXIT:-0}" ;;
  *"diff --quiet bash.json"*)
    exit "\${MOCK_GIT_DIFF_EXIT:-0}" ;;
  *"add bash.json"*)
    exit 0 ;;
  *"commit -m "*)
    exit "\${MOCK_GIT_COMMIT_EXIT:-0}" ;;
  *"push origin coverage-data"*)
    exit "\${MOCK_GIT_PUSH_EXIT:-0}" ;;
  *)
    exit "\${MOCK_GIT_EXIT:-0}" ;;
esac
EOF
  chmod +x "${SHIM_DIR}/git"

  export PATH="${SHIM_DIR}:${PATH}"
}

teardown() {
  rm -rf "${COVERAGE_WORKTREE}"
  if [[ -f "${BADGE_BACKUP}" ]]; then
    cp "${BADGE_BACKUP}" "${BADGE_JSON}"
  else
    rm -f "${BADGE_JSON}"
  fi
}

@test "push-bash-coverage.sh -h prints usage and exits 0 without any git calls" {
  run bash "${REPO_ROOT}/scripts/push-bash-coverage.sh" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  [ ! -s "${MOCK_CALLS_FILE}" ]
}

@test "push-bash-coverage.sh --help prints the same usage as -h" {
  run bash "${REPO_ROOT}/scripts/push-bash-coverage.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  [ ! -s "${MOCK_CALLS_FILE}" ]
}

@test "push-bash-coverage.sh pushes the badge JSON when it changed" {
  export MOCK_GIT_DIFF_EXIT=1
  run bash "${REPO_ROOT}/scripts/push-bash-coverage.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Coverage: 91%"* ]]
  [[ "$output" == *"Pushed bash.json (91%) to coverage-data branch"* ]]
  grep -q "fetch origin coverage-data" "${MOCK_CALLS_FILE}"
  grep -q "worktree add ${COVERAGE_WORKTREE} coverage-data" "${MOCK_CALLS_FILE}"
  grep -q "add bash.json" "${MOCK_CALLS_FILE}"
  grep -q "commit -m" "${MOCK_CALLS_FILE}"
  grep -q "push origin coverage-data" "${MOCK_CALLS_FILE}"
  [ ! -d "${COVERAGE_WORKTREE}" ]
}

@test "push-bash-coverage.sh skips the push when the badge JSON is unchanged" {
  export MOCK_GIT_DIFF_EXIT=0
  run bash "${REPO_ROOT}/scripts/push-bash-coverage.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"bash.json unchanged (91%) — skipping push"* ]]
  refute_grep "commit -m" "${MOCK_CALLS_FILE}"
  refute_grep "push origin coverage-data" "${MOCK_CALLS_FILE}"
  [ ! -d "${COVERAGE_WORKTREE}" ]
}

@test "push-bash-coverage.sh removes a stale coverage-data worktree before adding a fresh one" {
  mkdir -p "${COVERAGE_WORKTREE}"
  touch "${COVERAGE_WORKTREE}/leftover-junk"
  export MOCK_GIT_DIFF_EXIT=1
  run bash "${REPO_ROOT}/scripts/push-bash-coverage.sh"
  [ "$status" -eq 0 ]
  grep -q "worktree remove --force ${COVERAGE_WORKTREE}" "${MOCK_CALLS_FILE}"
  [[ "$output" == *"Pushed bash.json (91%) to coverage-data branch"* ]]
  [ ! -d "${COVERAGE_WORKTREE}" ]
}

@test "push-bash-coverage.sh is idempotent across repeated runs when nothing changed" {
  export MOCK_GIT_DIFF_EXIT=0
  run bash "${REPO_ROOT}/scripts/push-bash-coverage.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"unchanged"* ]]
  first_output="$output"

  : > "${MOCK_CALLS_FILE}"
  run bash "${REPO_ROOT}/scripts/push-bash-coverage.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"unchanged"* ]]
  [ "$output" = "$first_output" ]
  refute_grep "push origin coverage-data" "${MOCK_CALLS_FILE}"
}

@test "push-bash-coverage.sh exits 1 and never attempts a worktree add when fetch fails" {
  export MOCK_GIT_FETCH_EXIT=1
  run bash "${REPO_ROOT}/scripts/push-bash-coverage.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ERROR: coverage-data branch not found on remote"* ]]
  grep -q "fetch origin coverage-data" "${MOCK_CALLS_FILE}"
  refute_grep "worktree add" "${MOCK_CALLS_FILE}"
}

@test "push-bash-coverage.sh exits 1 when the badge JSON was never produced" {
  export STUB_SKIP_WRITE=1
  run bash "${REPO_ROOT}/scripts/push-bash-coverage.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ERROR: failed to read coverage percentage from"* ]]
  [ ! -s "${MOCK_CALLS_FILE}" ]
}

@test "push-bash-coverage.sh exits 1 when the badge JSON is malformed" {
  export STUB_SKIP_WRITE=1
  printf 'not-json' > "${BADGE_JSON}"
  run bash "${REPO_ROOT}/scripts/push-bash-coverage.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ERROR: failed to read coverage percentage from"* ]]
  [ ! -s "${MOCK_CALLS_FILE}" ]
}

@test "push-bash-coverage.sh exits 1 when the badge JSON is valid but missing the message field" {
  export STUB_SKIP_WRITE=1
  printf '{"schemaVersion":1}' > "${BADGE_JSON}"
  run bash "${REPO_ROOT}/scripts/push-bash-coverage.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ERROR: failed to read coverage percentage from"* ]]
  [ ! -s "${MOCK_CALLS_FILE}" ]
}

# Documents existing behavior rather than desired behavior: push-bash-coverage.sh
# does not check `git ... push`'s exit status, so a remote push failure is
# swallowed and the script still reports success. Recorded so a future fix to
# that gap shows up here as a test needing an update, not as a silent behavior
# change nobody noticed.
@test "push-bash-coverage.sh does not fail when the remote push itself fails" {
  export MOCK_GIT_DIFF_EXIT=1
  export MOCK_GIT_PUSH_EXIT=1
  run bash "${REPO_ROOT}/scripts/push-bash-coverage.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Pushed bash.json (91%) to coverage-data branch"* ]]
  grep -q "push origin coverage-data" "${MOCK_CALLS_FILE}"
}
