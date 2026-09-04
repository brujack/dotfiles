#!/usr/bin/env bats
#
# `run --separate-stderr` needs bats >= 1.5.0 (CI 1.10.0, this box 1.14.0).
bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_mocks
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  touch "${MOCK_CALLS_FILE}"
  load_setup_env
  export HOME="${BATS_TEST_TMPDIR}"
  export PERSONAL_GITREPOS="${BATS_TEST_TMPDIR}/git-repos/personal"
  export DOTFILES="dotfiles"
  mkdir -p "${PERSONAL_GITREPOS}/${DOTFILES}"
  # bats sets BATS_TEST_TMPDIR but leaves TMPDIR at the system temp dir, so
  # without this _dotfiles_run_tmpdir_setup leaks a real dotfiles-run.* dir.
  export TMPDIR="${BATS_TEST_TMPDIR}"
}

teardown() {
  :
}

@test "_dotfiles_run_tmpdir_setup leaves the caller's EXIT INT TERM traps unchanged" {
  # Bare (non-`run`) call, deliberately: this is the RED case this test
  # exists to pin. While lib/workflows.sh:109 still installs
  # `trap 'unset _DOTFILES_RUN_TMPDIR' EXIT INT TERM`, this bare call
  # replaces bats' own EXIT trap for the remainder of this test's subshell.
  # If the assertions below then fail, bats' errexit fires the shell exit
  # immediately -- but the trap that runs is production's `unset` handler,
  # not bats' trap-based "not ok" reporting, so the test does not print a
  # `not ok` line at all. It vanishes from the TAP stream, and the overall
  # run reports `bats warning: Executed N-1 instead of expected N` with a
  # non-zero exit. That IS the failure this test is meant to surface.
  local _exit_before _int_before _term_before
  _exit_before="$(trap -p EXIT)"
  _int_before="$(trap -p INT)"
  _term_before="$(trap -p TERM)"

  _dotfiles_run_tmpdir_setup

  [[ "$(trap -p EXIT)" == "${_exit_before}" ]]
  [[ "$(trap -p INT)" == "${_int_before}" ]]
  [[ "$(trap -p TERM)" == "${_term_before}" ]]
}

@test "a script blocked after _dotfiles_run_tmpdir_setup still dies on SIGTERM" {
  # Do not assert the literal 143 -- signal-derived exit statuses are not
  # portable across shells/platforms. Only that it is non-zero: while
  # lib/workflows.sh:109's trap is in place, bash defers running a trapped
  # signal's handler until the current foreground command (the `sleep`
  # below) completes on its own, the handler only unsets a variable, and
  # the script then falls off the end and exits 0 -- so SIGTERM is
  # silently absorbed rather than aborting the run.
  #
  # `/bin/sleep`, not bare `sleep`: this file's own load_mocks (setup(),
  # above) prepends tests/mocks/ to PATH, and tests/mocks/sleep is a stub
  # that logs the call and returns immediately rather than blocking --
  # exactly the shell.md "PATH mock shadows the binary your production
  # code needs" pitfall, except here it's the TEST's own blocking
  # primitive that gets shadowed, not code under test. A bare `sleep 30`
  # in the child measured flaky (~15-40% over several 25-run batches):
  # the child would "block", touch the ready file, then its `sleep`
  # would return in milliseconds and the whole script would exit 0 on
  # its own, racing this test's `kill -TERM` for who got there first.
  # The absolute path bypasses PATH resolution entirely and reaches the
  # real, actually-blocking binary. Confirmed via `date +%s.%N` either
  # side of the mocked `sleep 30`: 0.014s elapsed, not 30s.
  local _ready="${BATS_TEST_TMPDIR}/ready"
  bash -c '
    source "'"${REPO_ROOT}"'/setup_env.sh" >/dev/null 2>&1
    _dotfiles_run_tmpdir_setup
    touch "'"${_ready}"'"
    /bin/sleep 30
  ' &
  local _pid=$!

  local _waited=0
  until [[ -f "${_ready}" ]] || [[ ${_waited} -ge 50 ]]; do
    /bin/sleep 0.1
    _waited=$((_waited + 1))
  done
  [ -f "${_ready}" ]

  kill -TERM "${_pid}"
  local _rc=0
  wait "${_pid}" || _rc=$?
  [ "${_rc}" -ne 0 ]
}
