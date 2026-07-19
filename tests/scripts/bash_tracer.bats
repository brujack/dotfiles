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
