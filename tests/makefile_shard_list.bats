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
  unset BATS_FILES_FROM
  unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE

  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  SHIM="${BATS_TEST_TMPDIR}/shim"
  RECORD="${BATS_TEST_TMPDIR}/bats.calls"
  mkdir -p "${SHIM}"
  : > "${RECORD}"

  local b
  for b in make git env bash sed awk grep mktemp find sort file tr cut head cat; do
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
  expected="$(cd "${REPO_ROOT}" && find tests -name '*.bats' | LC_ALL=C sort | tr '\n' ' ')"
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
