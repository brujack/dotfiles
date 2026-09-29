#!/usr/bin/env bats

# Ctrl-C and SIGTERM during `-t update` must abort the run (ADR-0027 case 3).
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
  load_mocks
  load_setup_env
  export HOME="${BATS_TEST_TMPDIR}"
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  touch "${MOCK_CALLS_FILE}"
}

# _signal_fixture <install-handler: 0|1> <INT|TERM> -- writes a script that
# runs one tee-piped section whose leaf signals the whole process group, then
# touches an `after` marker. The marker exists only if the run continued.
_signal_fixture() {
  local _install="$1" _sig="$2" _f="${BATS_TEST_TMPDIR}/fixture.sh"
  {
    printf 'source %q\n' "${REPO_ROOT}/setup_env.sh"
    [[ ${_install} -eq 1 ]] && printf '_update_trap_signals\n'
    printf '_leaf() { bash -c %q; }\n' "trap 'exit 1' INT TERM; kill -${_sig} 0; sleep 2"
    printf '_leaf 2>&1 | tee %q > /dev/null\n' "${BATS_TEST_TMPDIR}/tee_out"
    printf 'touch %q\n' "${BATS_TEST_TMPDIR}/after"
  } > "${_f}"
  printf '%s' "${_f}"
}

# _in_new_session <script> -- runs `bash <script>` as the leader of its own
# process group, so `kill -SIG 0` cannot reach bats, with INT and TERM at their
# default action (a child spawned from a non-interactive shell can inherit
# them ignored). Prints the exit as a shell reports it: 128+N for a signal.
# The child's stderr is dropped: bash reports a killed job there
# ("Terminated ..."), and it would otherwise land in $output.
# python3 rather than setsid, which macOS does not ship.
_in_new_session() {
  python3 - "$1" <<'PY'
import signal, subprocess, sys
def reset():
    signal.signal(signal.SIGINT, signal.SIG_DFL)
    signal.signal(signal.SIGTERM, signal.SIG_DFL)
p = subprocess.run(["bash", sys.argv[1]], stdin=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, start_new_session=True,
                   preexec_fn=reset)
print(128 - p.returncode if p.returncode < 0 else p.returncode)
PY
}

@test "control: without the handler, a SIGINT-catching leaf lets the run continue" {
  run _in_new_session "$(_signal_fixture 0 INT)"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
  [ -e "${BATS_TEST_TMPDIR}/after" ]
}

@test "_update_trap_signals aborts the run on SIGINT with 130, before the next command" {
  run _in_new_session "$(_signal_fixture 1 INT)"
  [ "$status" -eq 0 ]
  [ "$output" = "130" ]
  [ ! -e "${BATS_TEST_TMPDIR}/after" ]
}

@test "_update_trap_signals aborts the run on SIGTERM with 143, before the next command" {
  run _in_new_session "$(_signal_fixture 1 TERM)"
  [ "$status" -eq 0 ]
  [ "$output" = "143" ]
  [ ! -e "${BATS_TEST_TMPDIR}/after" ]
}

# _with_default_signals <script> -- runs `bash <script>` with INT and TERM at
# their default action, passing stdout through and exiting with its status.
# Needed because a signal ignored when a non-interactive shell starts cannot
# be trapped, and `bats --jobs` (what `make test` uses) starts every test with
# SIGINT ignored: in-process, `trap ... INT` is a silent no-op there.
_with_default_signals() {
  python3 - "$1" <<'PY'
import signal, subprocess, sys
def reset():
    signal.signal(signal.SIGINT, signal.SIG_DFL)
    signal.signal(signal.SIGTERM, signal.SIG_DFL)
sys.exit(subprocess.run(["bash", sys.argv[1]], stdin=subprocess.DEVNULL,
                        preexec_fn=reset).returncode)
PY
}

@test "run_update installs the abort handler for its sections and restores the caller's afterwards" {
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
  grep -q 'kill -TERM' "${_seen}"
  [ "${lines[0]}" = "trap -- 'printf caller-int' SIGINT" ]
  [ "${lines[1]}" = "trap -- 'printf caller-term' SIGTERM" ]
}

@test "run_update returns _update_summary's status after restoring the caller's handlers" {
  export UPDATE_GEMS=1
  update_gems() { :; }
  _update_summary() { return 7; }
  local _rc=0
  run_update > /dev/null 2>&1 || _rc=$?
  [ "${_rc}" -eq 7 ]
}
