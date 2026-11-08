#!/usr/bin/env bats
#
# Structure tests for .github/workflows/uv-lock-refresh.yml (spec R7-R12, N3).
# The workflow cannot run here, so these pin its shape: triggers, permissions,
# pins, step order and the guards that keep it from touching anything but its
# own refresh PR. Every check asserts presence first so a missing step fails.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  WF="${REPO_ROOT}/.github/workflows/uv-lock-refresh.yml"
  CI="${REPO_ROOT}/.github/workflows/ci.yml"
  [[ -f "${WF}" ]]
}

# First line number of a fixed string in the workflow; empty when absent.
_line() {
  command grep -n -m1 -F -- "$1" "${WF}" | cut -d: -f1
}

# Fails when grep finds the pattern; a function, because bats does not fail a
# test on a mid-body `!` (SC2314).
# Only grep's rc 1 (no match) passes: rc 2 is a bad pattern or an unreadable
# file, which must fail the test rather than read as absence.
_absent() {
  local _rc=0
  command grep "$@" "${WF}" > /dev/null || _rc=$?
  [[ "${_rc}" -eq 1 ]]
}

# Lines of one step (from its `- name:` line to the next step), by name.
_step() {
  awk -v name="$1" '
    /^      - / { on = ($0 == "      - name: " name) }
    on { print }
  ' "${WF}"
}

# Workflow lines that are not comments.
_code() {
  command grep -vE '^[[:space:]]*#' "${WF}"
}

# Fails unless every argument is present in the workflow, in increasing order.
_assert_order() {
  local _prev=0 _marker _n
  for _marker in "$@"; do
    _n="$(_line "${_marker}")"
    if [[ -z "${_n}" ]]; then
      printf 'missing marker: %s\n' "${_marker}" >&2
      return 1
    fi
    if ((_n <= _prev)); then
      printf 'marker out of order (line %s <= %s): %s\n' "${_n}" "${_prev}" "${_marker}" >&2
      return 1
    fi
    _prev="${_n}"
  done
}

# Value of KEY ("UV_VER" / "UV_SHA256") inside one job of one workflow file.
_job_value() {
  local _file="$1" _job="$2" _key="$3"
  awk -v job="${_job}" -v key="${_key}" '
    /^  [A-Za-z0-9_-]+:[[:space:]]*$/ { cur = $1; sub(/:$/, "", cur); next }
    cur == job && $1 == key ":" { v = $2; gsub(/"/, "", v); print v; exit }
  ' "${_file}"
}

@test "triggers are exactly schedule (cron 0 6 * * 1) and workflow_dispatch" {
  local _triggers
  # Child keys of the top-level `on:` block.
  _triggers="$(awk '
    /^on:/ { inon = 1; next }
    inon && /^[^[:space:]#]/ { inon = 0 }
    inon && /^  [A-Za-z_]+:/ { k = $1; sub(/:$/, "", k); print k }
  ' "${WF}")"
  [[ "${_triggers}" == *schedule* ]]
  [[ "${_triggers}" == *workflow_dispatch* ]]
  [ "$(printf '%s\n' "${_triggers}" | wc -l)" -eq 2 ]
  command grep -qF -- 'cron: "0 6 * * 1"' "${WF}"
}

@test "workflow-level permissions are contents: read only" {
  local _block
  _block="$(awk '
    /^permissions:/ { p = 1; next }
    p && /^[^[:space:]]/ { p = 0 }
    p && NF { print $1 " " $2 }
  ' "${WF}")"
  [ "${_block}" = "contents: read" ]
}

@test "the single job declares exactly contents, pull-requests and issues write" {
  local _jobs _perms
  # Children of the top-level `jobs:` block.
  _jobs="$(awk '
    /^jobs:/ { inj = 1; next }
    inj && /^[^[:space:]#]/ { inj = 0 }
    inj && /^  [A-Za-z0-9_-]+:[[:space:]]*$/ { n++ }
    END { print n + 0 }
  ' "${WF}")"
  [ "${_jobs}" -eq 1 ]
  # Job-level block: 6-space children of the 4-space `permissions:` key.
  _perms="$(awk '
    /^    permissions:/ { inp = 1; next }
    inp && /^      [a-z-]+: / { print; next }
    inp { inp = 0 }
  ' "${WF}" | sed 's/^ *//' | LC_ALL=C sort)"
  [ "${_perms}" = "$(printf 'contents: write\nissues: write\npull-requests: write')" ]
}

@test "job sets timeout, concurrency without cancel, Node 24 flag and GH_TOKEN" {
  command grep -qE '^    timeout-minutes: 10$' "${WF}"
  command grep -qE '^    runs-on: ubuntu-latest$' "${WF}"
  command grep -qE '^      group: uv-lock-refresh$' "${WF}"
  command grep -qE '^      cancel-in-progress: false$' "${WF}"
  command grep -qE 'FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: true' "${WF}"
  command grep -qF 'GH_TOKEN: ${{ github.token }}' "${WF}"
}

@test "job default shell is bash, which supplies pipefail for the tee pipelines" {
  local _shell
  _shell="$(awk '
    /^    defaults:$/ { d = 1; next }
    d && /^      run:$/ { r = 1; next }
    d && r && /^        shell: / { print $2; exit }
    /^    [A-Za-z]/ { d = 0; r = 0 }
  ' "${WF}")"
  [ "${_shell}" = "bash" ]
}

@test "a guard step refuses any ref but master, runs before checkout, and checkout pins ref: master" {
  local _guard
  _guard="$(_step "Require master ref")"
  [[ -n "${_guard}" ]]
  [[ "${_guard}" == *'GITHUB_REF'* ]]
  [[ "${_guard}" == *'refs/heads/master'* ]]
  [[ "${_guard}" == *'exit 1'* ]]
  _assert_order '- name: Require master ref' 'actions/checkout@'
  command grep -qE '^          ref: master$' "${WF}"
}

@test "every uses: is pinned to a 40-hex SHA and at least one exists" {
  local _total _pinned
  _total="$(command grep -cE '^[[:space:]]*-?[[:space:]]*uses:' "${WF}")"
  _pinned="$(command grep -cE '^[[:space:]]*-?[[:space:]]*uses: [^@[:space:]]+@[0-9a-f]{40}( |$)' "${WF}")"
  [ "${_total}" -ge 1 ]
  [ "${_total}" -eq "${_pinned}" ]
  command grep -qF 'fetch-depth: 0' "${WF}"
}

@test "uv download is verified with sha256sum -c" {
  # On a non-comment line of the install step, ahead of the extraction.
  local _install
  _install="$(_step "Install uv (pinned)" | command grep -vE '^[[:space:]]*#')"
  [[ "${_install}" == *'sha256sum -c'* ]]
  [[ "${_install}" == *'tar -xzf'* ]]
  _install="${_install%%tar -xzf*}"
  [[ "${_install}" == *'sha256sum -c'* ]]
}

@test "UV_VER and UV_SHA256 equal the test-shard job's values in ci.yml" {
  local _ci_ver _ci_sha _wf_ver _wf_sha
  _ci_ver="$(_job_value "${CI}" test-shard UV_VER)"
  _ci_sha="$(_job_value "${CI}" test-shard UV_SHA256)"
  _wf_ver="$(awk '$1 == "UV_VER:" { gsub(/"/, "", $2); print $2; exit }' "${WF}")"
  _wf_sha="$(awk '$1 == "UV_SHA256:" { gsub(/"/, "", $2); print $2; exit }' "${WF}")"
  # Positive control: the parse found real values, not two empty strings.
  [[ "${_ci_ver}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
  [[ "${_ci_sha}" =~ ^[0-9a-f]{64}$ ]]
  [ "${_wf_ver}" = "${_ci_ver}" ]
  [ "${_wf_sha}" = "${_ci_sha}" ]
}

@test "git identity is set before the commit" {
  _assert_order 'git config user.name "github-actions[bot]"' \
    'git config user.email "github-actions[bot]@users.noreply.github.com"' \
    'git commit'
}

@test "commit names exactly the six refresh files and the push is a forced branch push" {
  local _add
  _add="$(command grep -F 'git add' "${WF}")"
  [ "$(printf '%s\n' "${_add}" | wc -l)" -eq 1 ]
  [[ "${_add}" == *' uv.lock '* ]]
  local _f
  for _f in requirements-ci.txt requirements-runtime-ci.txt requirements-ci-test.txt \
    requirements-ci-mutation.txt requirements-ci-audit.txt; do
    [[ "${_add}" == *" ${_f}"* ]]
  done
  [[ "${_add}" != *' . '* && "${_add}" != *' -A'* && "${_add}" != *' -u'* ]]
  command grep -qF 'git push --force origin chore/uv-lock-refresh' "${WF}"
  command grep -qF 'git switch -C chore/uv-lock-refresh' "${WF}"
}

@test "issue lookup selects by exact title and never by search" {
  # One lookup in the success step, one in the failure step; both exact.
  [ "$(_code | command grep -cF 'select(.title == "uv.lock refresh failed")')" -eq 2 ]
  [ "$(_code | command grep -cF 'gh issue list')" -eq 2 ]
  command grep -qF -- '--title "uv.lock refresh failed"' "${WF}"
  _absent -qF -- '--search'
  _absent -qF 'contains('
}

@test "no event free-text interpolation and no merge, approve, label or master write" {
  _absent -qF 'github.event'
  _absent -qF 'gh pr merge'
  _absent -qF -- '--approve'
  _absent -qF 'gh pr review'
  _absent -qF 'label'
  _absent -qE 'git push[^#]*master'
  _absent -qF 'exclude-newer'
  _absent -qF -- '--delete-branch'
}

@test "steps appear in order: refresh, fork filter, edit, create, close, issue close, failure" {
  _assert_order 'refresh-uv-lock.sh' 'isCrossRepository' 'gh pr edit' 'gh pr create' \
    'gh pr close' 'gh issue close' 'if: failure()'
}

@test "refresh result is read with tail -n 1 and passed on through GITHUB_OUTPUT" {
  command grep -qF 'tail -n 1' "${WF}"
  command grep -qF 'GITHUB_OUTPUT' "${WF}"
  command grep -qF "== 'changed'" "${WF}"
  command grep -qF "== 'no changes'" "${WF}"
}

@test "more than one open same-repo refresh PR fails the job" {
  local _find _guard
  _find="$(_step "Find open refresh PR")"
  [[ "${_find}" == *'select(.isCrossRepository==false)'* ]]
  # The exit must sit inside the `-gt 1` block, not merely somewhere nearby.
  _guard="$(printf '%s\n' "${_find}" | awk '
    /if \[\[ "\$\{count\}" -gt 1 \]\]; then/ { b = 1; next }
    b && /^ *fi$/ { exit }
    b { print }
  ')"
  [[ "${_guard}" == *'exit 1'* ]]
}

@test "PR number, base branch and close are pinned to the found PR and master" {
  local _pub _close
  _pub="$(_step "Publish refresh branch and PR")"
  [[ "${_pub}" == *'PR_NUMBER: ${{ steps.find_pr.outputs.number }}'* ]]
  [[ "${_pub}" == *'gh pr edit "${PR_NUMBER}" --body-file "${RUNNER_TEMP}/body.md"'* ]]
  [[ "${_pub}" == *'--base master'* ]]
  [[ "${_pub}" == *'--head chore/uv-lock-refresh'* ]]
  _close="$(_step "Close refresh PR when nothing changed")"
  [[ "${_close}" == *'PR_NUMBER: ${{ steps.find_pr.outputs.number }}'* ]]
  [[ "${_close}" == *'gh pr comment "${PR_NUMBER}"'* ]]
  [[ "${_close}" == *'gh pr close "${PR_NUMBER}"'* ]]
  # The close line carries no extra flags (no branch deletion, no reopen tricks).
  printf '%s\n' "${_close}" | command grep -qE '^ +gh pr close "\$\{PR_NUMBER\}"$'
  [[ "${_close}" == *"steps.refresh.outputs.result == 'no changes'"* ]]
}

@test "success issue-close runs only on success and the failure step also runs on cancel" {
  local _step_if
  _step_if="$(_step "Close failure issue" | command grep -E '^        if:' || true)"
  [[ -z "${_step_if}" || "${_step_if}" == "        if: success()" ]]
  [[ "$(_step "Close failure issue")" == *'gh issue close'* ]]
  # timeout-minutes cancels the job; failure() alone does not fire on a cancel.
  [[ "$(_step "Report failure" | command grep -E '^        if:')" == "        if: failure() || cancelled()" ]]
}

@test "failure step reads the newest RUNNER_TEMP log, last 40 lines, and links the run" {
  local _fail
  _fail="$(awk '/if: failure\(\)/ { f = 1 } f { print }' "${WF}")"
  [[ -n "${_fail}" ]]
  [[ "${_fail}" == *'${RUNNER_TEMP}'* ]]
  [[ "${_fail}" == *'tail -n 40'* ]]
  [[ "${_fail}" == *'${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}'* ]]
  [[ "${_fail}" == *'gh issue create'* ]]
  [[ "${_fail}" == *'gh issue comment'* ]]
}

@test "every step after checkout tees to a RUNNER_TEMP log" {
  local _name
  for _name in "Install uv (pinned)" "Refresh lock" "Find open refresh PR" \
    "Publish refresh branch and PR" "Close refresh PR when nothing changed" \
    "Close failure issue"; do
    [[ "$(_step "${_name}")" == *'| tee "${RUNNER_TEMP}/'* ]] || {
      printf 'no tee in step: %s\n' "${_name}" >&2
      return 1
    }
  done
}
