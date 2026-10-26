#!/usr/bin/env bats

# Ctrl-C and SIGTERM during `-t update` must abort the run (ADR-0027 case 3).
# SIGTERM needs no handler: with no trap, bash dies of it at once. SIGINT does.
#
# A non-interactive bash aborts on SIGINT only when its foreground child DIED
# of SIGINT. sudo, snap, brew and pip catch the signal and exit normally, so
# without a handler of its own run_update carries on into the next section and
# records the interrupted one as FAIL -- `exit 141` when the section is piped
# through tee, because tee dies first. The leaf below behaves like sudo: it
# sends the signal to its own process group, as a terminal's Ctrl-C does, then
# catches it and exits 1.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  source "${REPO_ROOT}/tests/helpers/new_session.bash"
  load_mocks
  load_setup_env
  export HOME="${BATS_TEST_TMPDIR}"
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  touch "${MOCK_CALLS_FILE}"
}

# _signal_fixture <install-handler: 0|1> <INT|TERM> <pipe: 0|1> [wait: 1|0] -- writes a
# script that runs one section whose leaf signals the whole process group,
# then touches an `after` marker. The marker exists only if the run continued.
# pipe=1 pipes the section through tee, as run_update's sections are; pipe=0
# is the deterministic form of the bug: with tee in the pipeline, tee dies of
# the signal and bash 5.2 then sometimes aborts on its own. Measured
# 2026-09-29 in ubuntu:24.04 under CPU load, with no handler: piped continued
# 37 of 40 runs, unpiped 40 of 40. It first showed as a CI-only control
# failure, so the control uses the unpiped form.
# The leaf signals only once its parent is asleep (ps state S), i.e. blocked in
# wait4 with its wait handler installed; until then the shell's SIGINT is at
# the default action. The poll gives up after 500 tries and signals anyway:
# 5 s of sleep, but each try also forks ps, so wall-clock is several times that.
# wait=0 drops the poll; only the positive control below uses it.
_signal_fixture() {
  local _install="$1" _sig="$2" _pipe="$3" _wait="${4:-1}" _f="${BATS_TEST_TMPDIR}/fixture.sh"
  local _poll='_i=0; until [[ $(ps -o stat= -p $PPID) == *S* ]] || (( ++_i > 500 )); do sleep 0.01; done; '
  [[ ${_wait} -eq 1 ]] || _poll=''
  {
    printf 'source %q\n' "${REPO_ROOT}/setup_env.sh"
    [[ ${_install} -eq 1 ]] && printf '_update_trap_sigint\n'
    printf '_leaf() { bash -c %q; }\n' "trap 'exit 1' INT TERM; ${_poll}kill -${_sig} 0; sleep 2"
    if [[ ${_pipe} -eq 1 ]]; then
      printf '_leaf 2>&1 | tee %q > /dev/null\n' "${BATS_TEST_TMPDIR}/tee_out"
    else
      printf '_leaf > /dev/null 2>&1\n'
    fi
    printf 'touch %q\n' "${BATS_TEST_TMPDIR}/after"
  } > "${_f}"
  printf '%s' "${_f}"
}

@test "control: without the handler, a SIGINT-catching leaf lets the run continue" {
  run _in_new_session "$(_signal_fixture 0 INT 0)"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
  [ -e "${BATS_TEST_TMPDIR}/after" ]
}

# A non-interactive bash leaves SIGINT at its default action and installs the
# handler that lets it outlive a child's SIGINT only after forking that child,
# just before wait4. A leaf that signals inside that gap kills the fixture
# shell (130): the CI-only failure of the control above (dotfiles#348). strace
# delays every rt_sigaction the fixture shell makes, holding the gap open; the
# leaf must wait it out. The positive control proves the delay opens the gap
# here, so a pass of the first test is not a pass of a race never run.
_DELAY_SIGACTION=(strace -I4 -o /dev/null -e trace=rt_sigaction -e inject=rt_sigaction:delay_enter=20000)

_skip_unless_strace() {
  [[ "$(uname -s)" == Linux ]] || skip "strace delay injection is Linux-only"
  strace -o /dev/null true 2> /dev/null || skip "strace missing or ptrace not permitted"
}

@test "control: the leaf waits for the fixture shell's wait handler before signalling" {
  _skip_unless_strace
  run _in_new_session "$(_signal_fixture 0 INT 0)" "${_DELAY_SIGACTION[@]}"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
  [ -e "${BATS_TEST_TMPDIR}/after" ]
}

@test "control: with the delay and no wait, the leaf's SIGINT kills the fixture shell" {
  _skip_unless_strace
  run _in_new_session "$(_signal_fixture 0 INT 0 0)" "${_DELAY_SIGACTION[@]}"
  [ "$status" -eq 0 ]
  [ "$output" = "130" ]
  [ ! -e "${BATS_TEST_TMPDIR}/after" ]
}

@test "_update_trap_sigint aborts the run on SIGINT with 130, before the next command" {
  run _in_new_session "$(_signal_fixture 1 INT 0)"
  [ "$status" -eq 0 ]
  [ "$output" = "130" ]
  [ ! -e "${BATS_TEST_TMPDIR}/after" ]
}

@test "_update_trap_sigint aborts a tee-piped section on SIGINT with 130" {
  run _in_new_session "$(_signal_fixture 1 INT 1)"
  [ "$status" -eq 0 ]
  [ "$output" = "130" ]
  [ ! -e "${BATS_TEST_TMPDIR}/after" ]
}

@test "SIGTERM aborts the run with 143 by bash's default action, no handler installed" {
  run _in_new_session "$(_signal_fixture 0 TERM 0)"
  [ "$status" -eq 0 ]
  [ "$output" = "143" ]
  [ ! -e "${BATS_TEST_TMPDIR}/after" ]
}

# _with_default_signals <script> -- runs `bash <script>` with INT and TERM at
# their default action, passing stdout through and exiting with its status.
# Needed because a signal ignored when a non-interactive shell starts cannot
# be trapped, and `bats --jobs` (what `make test` uses) starts every test with
# SIGINT ignored: in-process, `trap ... INT` is a silent no-op there.
# stderr is dropped because subprocess closes fds above 2: under the coverage
# tracer the child inherits BASH_XTRACEFD=9 with fd 9 closed, and bash warns
# about it on stderr before BASH_ENV reopens it.
_with_default_signals() {
  python3 - "$1" <<'PY'
import signal, subprocess, sys
def reset():
    signal.signal(signal.SIGINT, signal.SIG_DFL)
    signal.signal(signal.SIGTERM, signal.SIG_DFL)
sys.exit(subprocess.run(["bash", sys.argv[1]], stdin=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                        preexec_fn=reset).returncode)
PY
}

@test "run_update installs the SIGINT handler, leaves TERM alone, and restores the caller's afterwards" {
  local _f="${BATS_TEST_TMPDIR}/wiring.sh" _seen="${BATS_TEST_TMPDIR}/seen"
  {
    printf 'source %q\n' "${REPO_ROOT}/setup_env.sh"
    printf 'export UPDATE_GEMS=1\n'
    printf 'update_gems() { :; }\n'
    # Runs in run_update's own shell (not piped), so trap -p reports its handler.
    printf '_update_check_brewfile_drift() { trap -p INT TERM > %q; }\n' "${_seen}"
    printf "trap 'printf caller-int' INT\n"
    printf "trap 'printf caller-term' TERM\n"
    printf 'run_update > /dev/null 2>&1\n'
    printf 'trap -p INT TERM\n'
  } > "${_f}"

  run _with_default_signals "${_f}"

  grep -q 'kill -INT' "${_seen}"
  # SIGTERM is left to bash's default: the caller's TERM trap stays in place
  # during the run, not just after it.
  grep -qF "trap -- 'printf caller-term' SIGTERM" "${_seen}"
  [ "${lines[0]}" = "trap -- 'printf caller-int' SIGINT" ]
  [ "${lines[1]}" = "trap -- 'printf caller-term' SIGTERM" ]
}

@test "run_update removes its handler when the caller had none" {
  local _f="${BATS_TEST_TMPDIR}/nocaller.sh" _seen="${BATS_TEST_TMPDIR}/seen"
  {
    printf 'source %q\n' "${REPO_ROOT}/setup_env.sh"
    printf 'export UPDATE_GEMS=1\n'
    printf 'update_gems() { :; }\n'
    printf '_update_check_brewfile_drift() { trap -p INT TERM > %q; }\n' "${_seen}"
    printf 'run_update > /dev/null 2>&1\n'
    printf 'printf "after:[%%s]\\n" "$(trap -p INT TERM)"\n'
  } > "${_f}"

  run _with_default_signals "${_f}"

  # Positive control: an empty result below means removed, not never installed.
  grep -q 'kill -INT' "${_seen}"
  [ "$output" = "after:[]" ]
}

@test "run_update returns _update_summary's status" {
  export UPDATE_GEMS=1
  update_gems() { :; }
  _update_summary() { return 7; }
  local _rc=0
  run_update > /dev/null 2>&1 || _rc=$?
  [ "${_rc}" -eq 7 ]
}
