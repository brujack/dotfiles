#!/usr/bin/env bats
#
# Pins `make test-bats`'s shard-list surface: BATS_FILES_FROM replaces the
# find-derived file list, is never exported to bats, and the serial and
# parallel passes are filtered from that list and guarded separately.
#
# bats is a recording stub on a from-scratch PATH: nothing here runs a real
# suite. The list variable is set in the ENVIRONMENT, the way CI sets it,
# never as a make argument (under `unexport` a command-line assignment does
# not reach recipes, but it rides MAKEFLAGS into every nested make).

bats_require_minimum_version 1.5.0

_strip_make_leak_env() {
  unset MAKEFLAGS MFLAGS MAKELEVEL JOBS
}

setup() {
  _strip_make_leak_env
  # An outer run's shard list must not leak into the unset case.
  unset BATS_FILES_FROM COVERAGE_TRACE_DIR _OVERRIDE_COVERAGE_ROOT
  unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE

  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  SHIM="${BATS_TEST_TMPDIR}/shim"
  RECORD="${BATS_TEST_TMPDIR}/bats.calls"
  mkdir -p "${SHIM}"
  : > "${RECORD}"

  local b
  for b in make git env bash sed awk grep mktemp find sort file tr cut head cat python3; do
    if command -v "${b}" > /dev/null 2>&1; then
      ln -s "$(command -v "${b}")" "${SHIM}/${b}"
    fi
  done

  # Stub bats: record argv and what it sees of BATS_FILES_FROM, one call per line.
  cat > "${SHIM}/bats" << STUBEOF
#!/usr/bin/env bash
printf '%s | from=%s\n' "\$*" "\${BATS_FILES_FROM-unset}" >> "${RECORD}"
exit 0
STUBEOF
  chmod +x "${SHIM}/bats"

  # GNU parallel stub so the --jobs arm is taken.
  cat > "${SHIM}/parallel" << 'STUBEOF'
#!/usr/bin/env bash
[[ "$1" == "--version" ]] && printf 'GNU parallel 20240222\n'
exit 0
STUBEOF
  chmod +x "${SHIM}/parallel"

  LIST="${BATS_TEST_TMPDIR}/shard.files"
  printf 'tests/alpha.bats\ntests/beta.bats\n' > "${LIST}"
}

_run_test_bats() {
  _strip_make_leak_env
  PATH="${SHIM}" run --separate-stderr make --no-print-directory \
    -C "${REPO_ROOT}" test-bats "$@"
}

_calls() { wc -l < "${RECORD}" | tr -d ' '; }

@test "BATS_FILES_FROM unset: bats gets every find-derived file" {
  _run_test_bats JOBS=4
  [ "$status" -eq 0 ]
  [ "$(_calls)" -eq 1 ]
  local expected
  # Mirrors the Makefile's BATS_ALL_FILES derivation, plain `sort` included: it
  # collates in the caller's locale, so LC_ALL=C here would disagree on a dev box.
  expected="$(cd "${REPO_ROOT}" && find tests -name '*.bats' 2>/dev/null | sort | tr '\n' ' ')"
  [ "$(cat "${RECORD}")" = "--jobs 4 --print-output-on-failure ${expected}| from=unset" ]
}

@test "BATS_FILES_FROM set in the environment: bats gets exactly the listed files, and does not see the variable" {
  _strip_make_leak_env
  export BATS_FILES_FROM="${LIST}"
  PATH="${SHIM}" run --separate-stderr make --no-print-directory \
    -C "${REPO_ROOT}" test-bats JOBS=4
  [ "$status" -eq 0 ]
  [ "$(_calls)" -eq 1 ]
  [ "$(cat "${RECORD}")" = "--jobs 4 --print-output-on-failure tests/alpha.bats tests/beta.bats | from=unset" ]
}

@test "serial carve-out: a listed serial file runs alone; an unlisted one never runs" {
  export BATS_FILES_FROM="${LIST}"
  _run_test_bats JOBS=4 "BATS_SERIAL_FILES=tests/beta.bats tests/gamma.bats"
  [ "$status" -eq 0 ]
  [ "$(_calls)" -eq 2 ]
  [ "$(sed -n 1p "${RECORD}")" = "--jobs 4 --print-output-on-failure tests/alpha.bats | from=unset" ]
  [ "$(sed -n 2p "${RECORD}")" = "--print-output-on-failure tests/beta.bats | from=unset" ]
  ! command grep -q gamma "${RECORD}"
}

@test "serial-only list: no parallel call, exit 0" {
  printf 'tests/beta.bats\n' > "${LIST}"
  export BATS_FILES_FROM="${LIST}"
  _run_test_bats JOBS=4 BATS_SERIAL_FILES=tests/beta.bats
  [ "$status" -eq 0 ]
  [ "$(_calls)" -eq 1 ]
  [ "$(cat "${RECORD}")" = "--print-output-on-failure tests/beta.bats | from=unset" ]
}

@test "no GNU parallel: serial fallback notice and one filtered serial call" {
  export BATS_FILES_FROM="${LIST}"
  _run_test_bats JOBS=4 HAVE_PARALLEL=
  [ "$status" -eq 0 ]
  [[ "$output" == *"running bats serially: HAVE_PARALLEL is not yes"* ]]
  [ "$(cat "${RECORD}")" = "--print-output-on-failure tests/alpha.bats tests/beta.bats | from=unset" ]
}

@test "BATS_FILES_FROM naming a missing file refuses before bats" {
  export BATS_FILES_FROM="${BATS_TEST_TMPDIR}/nope.files"
  _run_test_bats JOBS=4
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"refusing to report a pass over zero tests"* ]]
  [ "$(_calls)" -eq 0 ]
}

@test "BATS_FILES_FROM naming an empty file refuses before bats" {
  : > "${LIST}"
  export BATS_FILES_FROM="${LIST}"
  _run_test_bats JOBS=4
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"refusing to report a pass over zero tests"* ]]
  [ "$(_calls)" -eq 0 ]
}

@test "make test reaches the bats phase through test-bats" {
  _strip_make_leak_env
  PATH="${SHIM}" run --separate-stderr make --no-print-directory -n \
    -C "${REPO_ROOT}" test JOBS=4
  [ "$status" -eq 0 ]
  [[ "$output" == *"bats --jobs 4 --print-output-on-failure tests/"* ]]
}

# --- make test-prereqs and make bash-coverage forwarding -------------------
#
# The coverage script is a recording stub: the `bash` on SHIM passes through
# to the real bash for everything except scripts/run-bash-coverage.sh, so the
# Makefile's parse-time `bash scripts/...` calls still work. No traced suite
# runs here.

_install_coverage_stub() {
  COV_RECORD="${BATS_TEST_TMPDIR}/coverage.calls"
  : > "${COV_RECORD}"
  rm -f "${SHIM}/bash"
  cat > "${SHIM}/bash" << STUBEOF
#!$(command -v bash)
if [[ "\$1" == scripts/run-bash-coverage.sh ]]; then
  shift
  printf 'jobs=%s\\n' "\${COVERAGE_BATS_JOBS-unset}" >> "${COV_RECORD}.jobs"
  printf 'args=%s | files=%s trace=%s root=%s\\n' "\$*" "\${BATS_FILES_FROM-unset}" \\
    "\${COVERAGE_TRACE_DIR-unset}" "\${_OVERRIDE_COVERAGE_ROOT-unset}" >> "${COV_RECORD}"
  exit 0
fi
exec $(command -v bash) "\$@"
STUBEOF
  chmod +x "${SHIM}/bash"
}

_run_bash_coverage() {
  _strip_make_leak_env
  PATH="${SHIM}" run --separate-stderr make --no-print-directory \
    -C "${REPO_ROOT}" bash-coverage HAVE_PARALLEL=
}

@test "make -n test runs test-prereqs' work once, before the bats call" {
  _strip_make_leak_env
  PATH="${SHIM}" run --separate-stderr make --no-print-directory -n \
    -C "${REPO_ROOT}" test JOBS=4
  [ "$status" -eq 0 ]
  [ "$(command grep -c 'claude_md_budget.py' <<< "${output}")" -eq 1 ]
  local budget_line bats_line
  budget_line="$(command grep -n 'claude_md_budget.py' <<< "${output}" | cut -d: -f1)"
  bats_line="$(command grep -n 'bats --jobs 4' <<< "${output}" | head -1 | cut -d: -f1)"
  [ -n "${bats_line}" ]
  [ "${budget_line}" -lt "${bats_line}" ]
}

@test "make -n test-prereqs plans no bats call" {
  _strip_make_leak_env
  PATH="${SHIM}" run --separate-stderr make --no-print-directory -n \
    -C "${REPO_ROOT}" test-prereqs JOBS=4
  [ "$status" -eq 0 ]
  [[ "$output" == *"claude_md_budget.py"* ]]
  # An executed bats call is a line starting with `bats` (lint merely prints
  # .bats file names inside other commands).
  ! command grep -qE '^[[:space:]]*bats[[:space:]]' <<< "${output}"
}

@test "bash-coverage: both variables set pass --files and --trace-only as arguments, never as environment" {
  _install_coverage_stub
  export BATS_FILES_FROM="${LIST}"
  export COVERAGE_TRACE_DIR="${BATS_TEST_TMPDIR}/trace-out"
  _run_bash_coverage
  [ "$status" -eq 0 ]
  [ "$(cat "${COV_RECORD}")" = "args=--files ${LIST} --trace-only ${BATS_TEST_TMPDIR}/trace-out | files=unset trace=unset root=unset" ]
}

@test "bash-coverage: an exported _OVERRIDE_COVERAGE_ROOT does not reach the script" {
  _install_coverage_stub
  export _OVERRIDE_COVERAGE_ROOT="${BATS_TEST_TMPDIR}/elsewhere"
  _run_bash_coverage
  [ "$status" -eq 0 ]
  [ "$(cat "${COV_RECORD}")" = "args= | files=unset trace=unset root=unset" ]
}

@test "bash-coverage: both variables unset gives today's argv" {
  _install_coverage_stub
  _run_bash_coverage
  [ "$status" -eq 0 ]
  [ "$(cat "${COV_RECORD}")" = "args= | files=unset trace=unset root=unset" ]
}

@test "bash-coverage: only the list set passes only --files" {
  _install_coverage_stub
  export BATS_FILES_FROM="${LIST}"
  _run_bash_coverage
  [ "$status" -eq 0 ]
  [ "$(cat "${COV_RECORD}")" = "args=--files ${LIST} | files=unset trace=unset root=unset" ]
}

@test "bash-coverage: only the trace dir set passes only --trace-only" {
  _install_coverage_stub
  export COVERAGE_TRACE_DIR="${BATS_TEST_TMPDIR}/trace-out"
  _run_bash_coverage
  [ "$status" -eq 0 ]
  [ "$(cat "${COV_RECORD}")" = "args=--trace-only ${BATS_TEST_TMPDIR}/trace-out | files=unset trace=unset root=unset" ]
}

@test "bash-coverage: a missing list is refused before the script runs" {
  _install_coverage_stub
  export BATS_FILES_FROM="${BATS_TEST_TMPDIR}/nope.files"
  _run_bash_coverage
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"refusing"* ]]
  [ ! -s "${COV_RECORD}" ]
}

@test "bash-coverage: an empty list is refused before the script runs" {
  _install_coverage_stub
  : > "${LIST}"
  export BATS_FILES_FROM="${LIST}"
  _run_bash_coverage
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"refusing"* ]]
  [ ! -s "${COV_RECORD}" ]
}

@test "bash-coverage: the parallel arm forwards both arguments too, with COVERAGE_BATS_JOBS set" {
  _install_coverage_stub
  export BATS_FILES_FROM="${LIST}"
  export COVERAGE_TRACE_DIR="${BATS_TEST_TMPDIR}/trace-out"
  _strip_make_leak_env
  PATH="${SHIM}" run --separate-stderr make --no-print-directory \
    -C "${REPO_ROOT}" bash-coverage HAVE_PARALLEL=yes BATS_SERIAL_FILES= JOBS=6
  [ "$status" -eq 0 ]
  [ "$(cat "${COV_RECORD}")" = "args=--files ${LIST} --trace-only ${BATS_TEST_TMPDIR}/trace-out | files=unset trace=unset root=unset" ]
  [ "$(cat "${COV_RECORD}.jobs")" = "jobs=6" ]
}

# `test:` keeps its prerequisites spelled out (other tests read that line), so
# test-prereqs could drift from it unseen. Pin: test-prereqs' set equals the
# set on `test:` minus test-prereqs and test-bats.
@test "test-prereqs lists exactly the non-bats prerequisites of test" {
  local pre test_line expected
  pre="$(sed -n 's/^test-prereqs:[[:space:]]*//p' "${REPO_ROOT}/Makefile" | tr ' ' '\n' | sed '/^$/d' | sort)"
  test_line="$(sed -n 's/^test:[[:space:]]*//p' "${REPO_ROOT}/Makefile")"
  expected="$(printf '%s\n' ${test_line} | command grep -vxE 'test-prereqs|test-bats' | sort)"
  [ -n "${pre}" ]
  [ -n "${expected}" ]
  [ "${pre}" = "${expected}" ]
}
