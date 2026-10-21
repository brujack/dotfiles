#!/usr/bin/env bats
#
# The test-macos job prints only the last 40 lines of `make test` when it
# fails. On dotfiles#358 that tail showed 3327 ok lines, no `not ok`, and bats
# still exiting 1, so the cause was not in the log the job kept. These tests
# pin the step that uploads the whole log on failure, scoped to the
# test-macos job rather than grepped from the whole workflow.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  WF="${WORKFLOW_UNDER_TEST:-${REPO_ROOT}/.github/workflows/ci.yml}"
}

# Prints the steps of one job, one per line, as "key=value;" pairs for the
# keys these tests read. A step starts at "      - " and a job at "  <name>:".
_job_steps() {
  awk -v want="$1" '
    /^  [a-z-]+:$/ { job=$1; sub(/:$/, "", job); next }
    job != want { next }
    /^      - / { if (step != "") print step; step="" }
    /^ *(- )?(uses|if|name):/ || /^ +(path|name|retention-days):/ {
      line=$0; sub(/^ *(- )?/, "", line); step=step line ";"
    }
    END { if (step != "") print step }
  ' "${WF}"
}

@test "test-macos uploads the full make test log when the job fails" {
  local _steps
  _steps="$(_job_steps test-macos)"
  # positive control: the scan found the job and its test step
  [[ "${_steps}" == *"Run tests"* ]]
  local _upload
  _upload="$(printf '%s\n' "${_steps}" | command grep -E 'uses: actions/upload-artifact@' || true)"
  if [[ -z "${_upload}" ]]; then
    printf 'test-macos has no upload-artifact step\n' >&2
    return 1
  fi
  [[ "${_upload}" == *"if: failure()"* ]]
  [[ "${_upload}" == *"path: /tmp/make-test.log"* ]]
}

@test "the test-macos log upload is pinned to a full commit SHA" {
  local _uses
  _uses="$(_job_steps test-macos | command grep -oE 'uses: actions/upload-artifact@[^;]*' || true)"
  [ -n "${_uses}" ]
  [[ "${_uses}" =~ @[0-9a-f]{40}( |$) ]]
}

@test "the log upload sits in test-macos, not only in another job" {
  # A copy in a different job would satisfy a whole-file grep and leave
  # test-macos without the log.
  local _other
  _other="$(_job_steps test | command grep -c 'upload-artifact' || true)"
  _job_steps test-macos | command grep -q 'upload-artifact'
  [ "${_other}" -eq 0 ]
}
