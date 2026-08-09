#!/usr/bin/env bats

# NOTE: only the guard-clause (early-return) path is tested here. The
# positive path (actually enabling BASH_XTRACEFD/set -x) is deliberately
# NOT exercised by these tests: bash-tracer.sh is the exact mechanism
# `make bash-coverage` uses to instrument the whole bats run via a
# globally-exported BASH_ENV, so any test that re-triggers real xtrace
# is testing the tracer while it's already active on itself. A version of
# this file that did trigger the positive path hung for 17+ minutes at
# 88% CPU under `make bash-coverage` (confirmed by reproduction, then
# killed) — the ambient coverage FIFO/filter pipeline is not designed to
# be re-entered this way. The eval-removal refactor in the same commit is
# still validated: characterization behavior (does the script still work
# end-to-end) is covered by `make bash-coverage` completing successfully
# against the real tracer, which exercises the positive path for real,
# outside of a nested/recursive test scenario.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
}

@test "bash-tracer.sh returns 0 without enabling xtrace when _COV_TRACE_FILE is unset" {
  run env -i PATH="${PATH}" HOME="${HOME}" bash -c \
    "source '${REPO_ROOT}/scripts/bash-tracer.sh'; [[ -z \"\${BASH_XTRACEFD:-}\" ]] && echo GUARD_HELD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"GUARD_HELD"* ]]
}

# Regression: `exec 9>>f 2>/dev/null` — exec with redirections and NO command
# applies ALL of them to the current shell permanently, so the `2>/dev/null`
# meant to hide the exec's own failure silenced the traced shell's stderr for
# its whole lifetime. Every bash subprocess the tracer touched lost fd 2.
# Found when ai-config ported this file and a stderr-asserting bats test
# passed standalone but failed under the tracer.
#
# This DOES take the positive path the header warns about, but safely:
# `env -i` drops the ambient BASH_ENV so the running coverage tracer is not
# re-entered, and `set +x` stops tracing on the next line so nothing streams
# into the live FIFO. That is the combination the 17-minute hang lacked.
@test "bash-tracer.sh leaves the traced shell's stderr intact" {
  local _trace="${BATS_TEST_TMPDIR}/trace.txt"
  run env -i PATH="${PATH}" HOME="${HOME}" _COV_TRACE_FILE="${_trace}" bash -c \
    "source '${REPO_ROOT}/scripts/bash-tracer.sh'; set +x; printf 'STDERR_ALIVE\n' >&2"
  [ "$status" -eq 0 ]
  # bats merges the subshell's stderr into $output; with the defect this line
  # is swallowed by /dev/null and the assertion fails.
  [[ "$output" == *"STDERR_ALIVE"* ]]
  # fd 9 must still have been opened — the fix must not cost the tracing it
  # exists to do. A passing stderr assertion over a dead tracer is no fix.
  [ -s "${_trace}" ]
}
