#!/usr/bin/env bats

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

@test "_dotfiles_run_tmpdir_setup leaves the caller's EXIT INT TERM traps unchanged" {
  # Bare call, never `run`: `run` executes in a subshell, so a trap the callee
  # installed would be confined there and this test could not observe it.
  #
  # This test fails by VANISHING rather than by printing `not ok`. Should
  # _dotfiles_run_tmpdir_setup ever install an EXIT trap again, that trap
  # replaces bats' own for the rest of this test's shell; the assertions below
  # then fail, errexit exits the shell, and the handler that runs is the
  # callee's rather than bats' `not ok` reporting. The run reports
  # `bats warning: Executed N-1 instead of expected N` and exits non-zero.
  # Read a missing `not ok` here as the failure, not as a pass.
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
  # `/bin/sleep`, never bare `sleep`, at BOTH sites below. setup()'s
  # load_mocks prepends tests/mocks/ to PATH and tests/mocks/sleep is a stub
  # that logs its argument and returns immediately, so a bare `sleep` here is
  # not a delay at all: the child reaches it, returns in ~0.014s, and exits 0
  # on its own, racing the kill. Measured 3 failures in 25 runs that way. It
  # is shell.md's PATH-mock pitfall aimed at the test's own blocking
  # primitive rather than at code under test, so no mutation of production
  # code can surface it — only running the test repeatedly does.
  #
  # The child's fds go to /dev/null deliberately. `kill -TERM` reaches the
  # `bash -c` shell, not its process group, so the real sleep briefly outlives
  # it as an orphan; without this redirect that orphan inherits and pins bats'
  # output pipe, which is the suite-hangs-after-its-last-test class.
  #
  # Asserts non-zero, never the literal 143 — signal-derived statuses are not
  # portable and this suite runs on macOS and Linux. Under a reintroduced
  # trap the child is not killed at all: it runs the full sleep and exits 0,
  # which is what makes this assertion discriminate.
  local _ready="${BATS_TEST_TMPDIR}/ready"
  bash -c '
    source "'"${REPO_ROOT}"'/setup_env.sh" >/dev/null 2>&1
    _dotfiles_run_tmpdir_setup
    touch "'"${_ready}"'"
    /bin/sleep 5
  ' >/dev/null 2>&1 &
  local _pid=$!

  local _waited=0
  until [[ -f "${_ready}" ]] || [[ ${_waited} -ge 100 ]]; do
    /bin/sleep 0.05
    _waited=$((_waited + 1))
  done
  [ -f "${_ready}" ]

  kill -TERM "${_pid}"
  local _rc=0
  wait "${_pid}" || _rc=$?
  [ "${_rc}" -ne 0 ]
}
