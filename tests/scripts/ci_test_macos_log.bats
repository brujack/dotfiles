#!/usr/bin/env bats
#
# The test-macos job prints only the last 40 lines of `make test` when it
# fails. On dotfiles#358 that tail showed 3327 ok lines, no `not ok`, and bats
# still exiting 1, so the cause was not in the log the job kept. These tests
# pin the step that uploads the whole log, scoped to the test-macos job rather
# than grepped from the whole workflow.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  WF="${WORKFLOW_UNDER_TEST:-${REPO_ROOT}/.github/workflows/ci.yml}"
}

# Prints the steps of one job, one per line, as "key: value;" pairs for the
# keys these tests read. A job header is any two-space-indented id (GitHub
# allows letters, digits, `_` and `-`), so a following job never inherits the
# previous job's steps; a step starts at the job's six-space "- ".
_job_steps() {
  awk -v want="$1" '
    /^  [A-Za-z_][A-Za-z0-9_-]*:$/ { job=$1; sub(/:$/, "", job); next }
    job != want { next }
    /^      - / { if (started) print step; step=""; started=1 }
    /^ *(- )?(uses|if|name|path):/ {
      line=$0; sub(/^ *(- )?/, "", line); step=step line ";"
    }
    END { if (started) print step }
  ' "${WF}"
}

@test "test-macos uploads the full make test log when the job fails or is cancelled" {
  local _steps
  _steps="$(_job_steps test-macos)"
  # Structural control: a layout the scanner does not understand (another
  # step indent, a renamed job) collapses the job to one record or none, and
  # must fail here rather than let any single step satisfy the checks below.
  [ "$(printf '%s\n' "${_steps}" | command grep -c .)" -gt 1 ]
  local _upload
  _upload="$(printf '%s\n' "${_steps}" | command grep -E 'uses: actions/upload-artifact@' || true)"
  if [[ -z "${_upload}" ]]; then
    printf 'test-macos has no upload-artifact step\n' >&2
    return 1
  fi
  # A job timeout ends as cancelled, where failure() alone is false; that is
  # the hang case, when the full log matters most.
  [[ "${_upload}" == *"if: failure() || cancelled();"* ]]
  [[ "${_upload}" == *"path: /tmp/make-test.log;"* ]]
}

@test "the test-macos log upload runs after the step that writes the log" {
  local _order
  _order="$(_job_steps test-macos | awk '/name: Run tests;/ { t=NR } /upload-artifact@/ { u=NR } END { print t+0, u+0 }')"
  read -r _tests _upload <<< "${_order}"
  [ "${_tests}" -gt 0 ]
  [ "${_upload}" -gt "${_tests}" ]
}

@test "the test-macos log upload is pinned to a full commit SHA" {
  local _uses
  _uses="$(_job_steps test-macos | command grep -oE 'uses: actions/upload-artifact@[^;]*' || true)"
  [ -n "${_uses}" ]
  [[ "${_uses}" =~ @[0-9a-f]{40}( |$) ]]
}
