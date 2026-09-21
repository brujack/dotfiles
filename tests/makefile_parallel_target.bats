#!/usr/bin/env bats
#
# Pins the `make test` recipe's parallel surface: JOBS validation, GNU
# parallel detection with its serial fallback, the find-derived file list,
# and the serial carve-out branch. Reads only the recipe text that
# `make -C <dir> -n test` prints -- nothing here runs a real bats suite.
#
# Every case runs make under a from-scratch PATH, not a prepend. This box
# has a real /usr/bin/parallel, so the "parallel absent" case needs a PATH
# on which nothing can resolve it, not merely a shim searched first
# (shell.md, "A PATH mock shadows the binary your production code needs").

bats_require_minimum_version 1.5.0

# A parent `make test JOBS=N` puts that definition in this process's
# environment twice -- MAKEFLAGS carries the command-line definition and
# JOBS is exported directly -- so unsetting one leaves the default case
# non-discriminating. Called from setup() and again immediately before
# every make invocation, which is what matters for the leak case.
_strip_make_leak_env() {
  unset MAKEFLAGS MFLAGS MAKELEVEL JOBS
}

setup() {
  _strip_make_leak_env
  unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE

  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"

  SHIM="${BATS_TEST_TMPDIR}/shim"
  mkdir -p "${SHIM}"

  # Everything the Makefile's parse-time $(shell ...) calls reach for, plus
  # what `run --separate-stderr` itself needs (mktemp). `find`/`sort` build
  # BATS_ALL_FILES; `grep` is in HAVE_PARALLEL's detection pipeline; `file`
  # and `git` are what scripts/list-shell-files.sh runs.
  local b
  for b in make bats git env bash sed awk grep mktemp find sort file tr cut head; do
    if command -v "${b}" > /dev/null 2>&1; then
      ln -s "$(command -v "${b}")" "${SHIM}/${b}"
    fi
  done
}

_enable_parallel() {
  cat > "${SHIM}/parallel" << 'STUBEOF'
#!/usr/bin/env bash
if [[ "$1" == "--version" ]]; then
  printf 'GNU parallel 20240222\n'
  exit 0
fi
exit 0
STUBEOF
  chmod +x "${SHIM}/parallel"
}

_disable_parallel() {
  rm -f "${SHIM}/parallel"
}

# moreutils ships a `parallel` under the same name at the same PATH
# precedence. `command -v parallel` cannot tell it from GNU parallel; only
# its --version output can, which is why detection greps that output.
_enable_non_gnu_parallel() {
  cat > "${SHIM}/parallel" << 'STUBEOF'
#!/usr/bin/env bash
if [[ "$1" == "--version" ]]; then
  printf 'parallel (moreutils) 20230101\n'
  exit 0
fi
exit 0
STUBEOF
  chmod +x "${SHIM}/parallel"
}

_run_make_dry() {
  _strip_make_leak_env
  PATH="${SHIM}" run --separate-stderr make --no-print-directory \
    -C "${TARGET_DIR:-$REPO_ROOT}" -n test "$@"
}

@test "GNU parallel present: recipe runs bats at --jobs JOBS" {
  _enable_parallel
  _run_make_dry JOBS=12
  [ "$status" -eq 0 ]
  local jobs_line
  jobs_line="$(printf '%s\n' "$output" | grep -m1 '^bats --jobs 12 ')"
  [ -n "$jobs_line" ]
  [[ "$jobs_line" == *"tests/setup_env/unit.bats"* ]]
  [[ "$jobs_line" == *"tests/zshrc.d/unit.bats"* ]]
}

@test "GNU parallel absent: falls back to serial with a notice" {
  _disable_parallel
  _run_make_dry JOBS=12
  [ "$status" -eq 0 ]
  [[ "$output" == *"running bats serially: HAVE_PARALLEL is not yes"* ]]
  local serial_line
  serial_line="$(printf '%s\n' "$output" | grep -E '^bats tests/')"
  [ -n "$serial_line" ]
  [[ "$serial_line" != *"--jobs"* ]]
  [[ "$serial_line" == *"tests/setup_env/unit.bats"* ]]
}

@test "a non-GNU parallel on PATH takes the serial path, not --jobs" {
  _enable_non_gnu_parallel
  _run_make_dry JOBS=12
  [ "$status" -eq 0 ]
  [[ "$output" == *"running bats serially: HAVE_PARALLEL is not yes"* ]]
  if printf '%s\n' "$output" | grep -q '^bats --jobs'; then
    printf 'moreutils parallel was accepted as GNU parallel\n' >&2
    return 1
  fi
}

@test "HAVE_PARALLEL= on the command line forces serial with GNU parallel present" {
  _enable_parallel
  # The escape hatch: a command-line assignment beats the Makefile's own
  # detection, so a machine (or a CI job) that must not run in parallel has
  # one without a second knob to maintain. The notice names both causes,
  # because "GNU parallel not found" would be false here.
  _run_make_dry JOBS=12 HAVE_PARALLEL=
  [ "$status" -eq 0 ]
  [[ "$output" == *"running bats serially: HAVE_PARALLEL is not yes"* ]]
  if printf '%s\n' "$output" | grep -q '^bats --jobs'; then
    printf 'HAVE_PARALLEL= did not force the serial path\n' >&2
    return 1
  fi
}

@test "JOBS=3 resolves to --jobs 3" {
  _enable_parallel
  _run_make_dry JOBS=3
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q '^bats --jobs 3 '
}

@test "JOBS validation rejects empty, zero, leading-zero and non-numeric values" {
  _enable_parallel
  local v
  for v in "" "0" "07" "x" "1 2" "-1"; do
    _run_make_dry "JOBS=${v}"
    if [ "$status" -eq 0 ]; then
      printf 'JOBS=%s was accepted, expected a parse-time error\n' "${v}" >&2
      return 1
    fi
    if [[ "$stderr" != *"JOBS must be a positive integer, got '${v}'"* ]]; then
      printf 'stderr for JOBS=%s did not name the value: %s\n' "${v}" "${stderr}" >&2
      return 1
    fi
  done
}

@test "JOBS defaults to 24 when unset, even under an outer make's leak" {
  _enable_parallel
  # Both halves matter: a command-line JOBS reaches a nested make through
  # MAKEFLAGS *and* the recipe environment, so stripping one leaves this
  # case unable to fail. Dropping either name from _strip_make_leak_env is
  # the mutation that proves it.
  export MAKEFLAGS=' -- JOBS=2' JOBS=2
  _run_make_dry
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q '^bats --jobs 24 '
}

@test "the file list is a filesystem walk: an untracked .bats file is included" {
  _enable_parallel
  local clone
  clone="${BATS_TEST_TMPDIR}/clone"
  git clone --no-hardlinks -q "${REPO_ROOT}" "${clone}"
  # The clone is at HEAD; overlay the working Makefile so the clone
  # exercises the recipe under test rather than whatever master last had.
  cp "${REPO_ROOT}/Makefile" "${clone}/Makefile"
  printf '#!/usr/bin/env bats\n@test "probe" { true; }\n' > "${clone}/tests/zz_probe.bats"

  TARGET_DIR="${clone}" _run_make_dry JOBS=12
  [ "$status" -eq 0 ]
  local jobs_line
  jobs_line="$(printf '%s\n' "$output" | grep -m1 '^bats --jobs 12 ')"
  [ -n "$jobs_line" ]
  [[ "$jobs_line" == *"tests/zz_probe.bats"* ]]
}

@test "a carved-out file leaves the parallel pool and runs alone afterwards" {
  _enable_parallel
  # BATS_SERIAL_FILES is empty in the Makefile today. Overriding it here
  # exercises the carve-out branch without carving anything out, so the
  # shape is under test before the first name needs it.
  _run_make_dry JOBS=12 BATS_SERIAL_FILES=tests/setup_env/git_hooks.bats
  [ "$status" -eq 0 ]
  local jobs_line
  jobs_line="$(printf '%s\n' "$output" | grep -m1 '^bats --jobs 12 ')"
  [ -n "$jobs_line" ]
  # The carved-out file must leave the parallel pool, or it runs twice.
  if [[ "$jobs_line" == *"tests/setup_env/git_hooks.bats"* ]]; then
    printf 'carved-out file is still in the parallel pool: %s\n' "$jobs_line" >&2
    return 1
  fi
  printf '%s\n' "$output" | grep -qx 'bats tests/setup_env/git_hooks.bats'
}

@test "serial path plus a carve-out does not run the carved-out file twice" {
  _disable_parallel
  _run_make_dry JOBS=12 BATS_SERIAL_FILES=tests/setup_env/git_hooks.bats
  [ "$status" -eq 0 ]
  # The serial branch must run BATS_PARALLEL_FILES, not BATS_ALL_FILES:
  # the carve-out phase below it runs the carved file, so the unfiltered
  # list would run it a second time. No other assertion catches that,
  # because both runs pass.
  local n
  n="$(printf '%s\n' "$output" | grep -c '^bats .*tests/setup_env/git_hooks\.bats')"
  if [ "$n" -ne 1 ]; then
    printf 'git_hooks.bats appears in %s bats invocations, expected 1\n' "$n" >&2
    printf '%s\n' "$output" | grep '^bats ' >&2
    return 1
  fi
}

@test "an empty file list refuses to run rather than reporting a pass" {
  _enable_parallel
  # A command-line assignment wins over the Makefile's own `:=`, so this
  # simulates the derivation returning nothing (no find, moved tests/).
  _run_make_dry JOBS=12 BATS_ALL_FILES=
  [ "$status" -eq 0 ]
  [[ "$output" == *"refusing to report a pass over zero tests"* ]]
  [[ "$output" == *"exit 1"* ]]
  if printf '%s\n' "$output" | grep -q '^bats '; then
    printf 'an empty file list still produced a bats invocation\n' >&2
    return 1
  fi
}

@test "no carve-out configured: exactly one bats invocation" {
  _enable_parallel
  _run_make_dry JOBS=12
  [ "$status" -eq 0 ]
  local n
  n="$(printf '%s\n' "$output" | grep -c '^bats ')"
  [ "$n" -eq 1 ]
}
