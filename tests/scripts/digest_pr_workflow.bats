#!/usr/bin/env bats
#
# Structure tests for .github/workflows/digest-pr.yml. The workflow cannot run
# here, so these pin its shape: the push-only trigger, empty top-level
# permissions, the one job's write scope, pins, the checkout of master (so a
# branch that edits only the script cannot change the script that judges it; the
# workflow file itself comes from the pushed commit), no persisted checkout
# credentials, and the absence of anything that would label, merge or run on
# another event. The logic is tested in digest_pr.bats.

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  WF="${REPO_ROOT}/.github/workflows/digest-pr.yml"
  CI="${REPO_ROOT}/.github/workflows/ci.yml"
  [[ -f "${WF}" ]]
}

# Lines of the one job, from `  <name>:` to the end of the jobs block.
_jobs() {
  awk '
    /^[^[:space:]#]/ { on = ($0 == "jobs:"); next }
    on { print }
  ' "${WF}"
}

@test "triggers on push to digest/** branches only" {
  run awk '/^on:/{on=1;next} /^[^[:space:]#]/{on=0} on{print}' "${WF}"
  [ "${status}" -eq 0 ]
  [ "$(printf '%s\n' "${output}" | sed 's/^ *//; /^$/d; /^#/d' | tr '\n' '|')" = 'push:|branches: ["digest/**"]|' ]
}

@test "never uses pull_request_target, schedule, workflow_dispatch or workflow_run" {
  run ! command grep -nE 'pull_request|schedule:|workflow_dispatch|workflow_run' "${WF}"
}

@test "top-level permissions are empty" {
  command grep -qxF 'permissions: {}' "${WF}"
}

@test "the one job holds exactly contents read and pull-requests write" {
  run awk '/^    permissions:/{p=1;next} p&&/^      [a-z-]+: /{print;next} p{p=0}' "${WF}"
  [ "$(printf '%s\n' "${output}" | sed 's/^ *//' | LC_ALL=C sort | tr '\n' '|')" = 'contents: read|pull-requests: write|' ]
  [ "$(_jobs | command grep -cE '^  [A-Za-z0-9_-]+:[[:space:]]*$')" -eq 1 ]
}

@test "the job skips branch deletions" {
  _jobs | command grep -qF 'if: ${{ !github.event.deleted }}'
}

@test "the job runs on ubuntu-latest with a 10 minute timeout and the Node 24 env" {
  _jobs | command grep -qxF '    runs-on: ubuntu-latest'
  _jobs | command grep -qxF '    timeout-minutes: 10'
  command grep -qxF '  FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: true' "${WF}"
}

@test "every action is pinned by full sha, and checkout matches the pin in ci.yml" {
  local _uses _pin
  [ "$(command grep -cE '^[[:space:]]*-?[[:space:]]*uses:' "${WF}")" -ge 1 ]
  [ "$(command grep -cE '^[[:space:]]*-?[[:space:]]*uses:' "${WF}")" -eq \
    "$(command grep -cE '^[[:space:]]*-?[[:space:]]*uses: [^@[:space:]]+@[0-9a-f]{40} # ' "${WF}")" ]
  _uses="$(command grep -m1 -oE 'actions/checkout@[0-9a-f]{40}' "${WF}")"
  _pin="$(command grep -m1 -oE 'actions/checkout@[0-9a-f]{40}' "${CI}")"
  [ -n "${_uses}" ]
  [ "${_uses}" = "${_pin}" ]
}

@test "checks out master, so a branch that edits only the script does not change the script that judges it" {
  _jobs | command grep -qxF '          ref: master'
  _jobs | command grep -qxF '          fetch-depth: 0'
}

@test "checkout persists no credentials" {
  _jobs | command grep -qxF '          persist-credentials: false'
}

@test "fetches the pushed sha and runs scripts/digest-pr.sh with branch and sha from env" {
  _jobs | command grep -qF 'git fetch -q origin "${SHA}"'
  _jobs | command grep -qF 'bash scripts/digest-pr.sh "${BRANCH}" "${SHA}"'
  _jobs | command grep -qxF '          BRANCH: ${{ github.ref_name }}'
  _jobs | command grep -qxF '          SHA: ${{ github.sha }}'
}

@test "no expression is interpolated inside a run block" {
  run awk '/^ *run: /{r=1} r&&/\$\{\{/&&!/^ *(BRANCH|SHA|GH_TOKEN):/{print}' "${WF}"
  [ -z "${output}" ]
}

@test "GH_TOKEN is the workflow token" {
  command grep -qF 'GH_TOKEN: ${{ github.token }}' "${WF}"
}

@test "adds no label and never merges, edits, closes or reviews a PR" {
  # Comments may name automerge-ok; only executable lines count.
  run ! bash -c 'sed "/^[[:space:]]*#/d" "$1" | command grep -nE -- "--label|gh pr (merge|edit|close|review|comment)|automerge-ok|gh label"' _ "${WF}"
}
