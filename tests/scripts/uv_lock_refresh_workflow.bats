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
_absent() {
  if command grep "$@" "${WF}"; then
    return 1
  fi
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

@test "every uses: is pinned to a 40-hex SHA and at least one exists" {
  local _total _pinned
  _total="$(command grep -cE '^[[:space:]]*-?[[:space:]]*uses:' "${WF}")"
  _pinned="$(command grep -cE '^[[:space:]]*-?[[:space:]]*uses: [^@[:space:]]+@[0-9a-f]{40}( |$)' "${WF}")"
  [ "${_total}" -ge 1 ]
  [ "${_total}" -eq "${_pinned}" ]
  command grep -qF 'fetch-depth: 0' "${WF}"
}

@test "uv download is verified with sha256sum -c" {
  command grep -qF 'sha256sum -c' "${WF}"
  _assert_order 'sha256sum -c' 'tar -xzf'
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
  command grep -qF '.title == "uv.lock refresh failed"' "${WF}"
  _absent -qF -- '--search'
}

@test "no event free-text interpolation and no merge, approve, label or master write" {
  _absent -qF 'github.event'
  _absent -qF 'gh pr merge'
  _absent -qF -- '--approve'
  _absent -qF 'gh pr review'
  _absent -qF 'label'
  _absent -qE 'git push[^#]*master'
  _absent -qF 'exclude-newer'
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
  command grep -qF 'select(.isCrossRepository==false)' "${WF}"
  command grep -qE '(-gt|-ge) 1|-gt 1' "${WF}"
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
  local _tees
  _tees="$(command grep -cF 'tee "${RUNNER_TEMP}/' "${WF}")"
  # uv install, refresh, find PR, publish, close, issue close; failure step posts.
  [ "${_tees}" -ge 5 ]
}
