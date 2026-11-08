#!/usr/bin/env bats
#
# Structure tests for .github/workflows/uv-lock-refresh.yml (spec R7-R12, N3).
# The workflow cannot run here, so these pin its shape: triggers, the three-job
# trust split (a token-less resolve, a write-scoped publish, a report), pins,
# step order and the guards that keep it from touching anything but its own
# refresh PR. Every check asserts presence first so a missing step fails.

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  WF="${REPO_ROOT}/.github/workflows/uv-lock-refresh.yml"
  CI="${REPO_ROOT}/.github/workflows/ci.yml"
  [[ -f "${WF}" ]]
}

# --- parsing helpers ----------------------------------------------------------

# Lines of one job (from `  <job>:` to the next job), by name.
_job() {
  awk -v j="$1" '
    /^[^[:space:]#]/ { injobs = ($0 == "jobs:"); on = 0 }
    injobs && /^  [A-Za-z0-9_-]+:[[:space:]]*$/ { on = ($1 == j ":") }
    on { print }
  ' "${WF}"
}

# Lines of one step of one job, by step name.
_step() {
  _job "$1" | awk -v name="$2" '
    /^      - / { on = ($0 == "      - name: " name) }
    on { print }
  '
}

# Lines of a top-level key's block (e.g. `permissions`, `defaults`).
_top() {
  awk -v k="$1" '
    /^[^[:space:]#]/ { on = ($0 == k ":") }
    on { print }
  ' "${WF}"
}

# Names of the jobs, in file order.
_job_names() {
  awk '
    /^[^[:space:]#]/ { injobs = ($0 == "jobs:") }
    injobs && /^  [A-Za-z0-9_-]+:[[:space:]]*$/ { n = $1; sub(/:$/, "", n); print n }
  ' "${WF}"
}

# Sorted `key: value` children of a job's `permissions:` block.
_job_perms() {
  _job "$1" | awk '
    /^    permissions:/ { inp = 1; next }
    inp && /^      [a-z-]+: / { print; next }
    inp { inp = 0 }
  ' | sed 's/^ *//' | LC_ALL=C sort
}

# Workflow lines that are not comments.
_code() {
  command grep -vE '^[[:space:]]*#' "${WF}"
}

# Fails unless stdin-less TEXT ($1) holds no match for the grep args that follow.
# Only grep's rc 1 passes: rc 2 is a bad pattern, which must fail the test
# rather than read as absence. (bats does not fail a test on a mid-body `!`.)
_none_in() {
  local _text="$1" _rc=0
  shift
  printf '%s\n' "${_text}" | command grep "$@" > /dev/null || _rc=$?
  [[ "${_rc}" -eq 1 ]]
}

_absent() {
  local _rc=0
  command grep "$@" "${WF}" > /dev/null || _rc=$?
  [[ "${_rc}" -eq 1 ]]
}

# First line number of a fixed string in TEXT ($1); empty when absent.
_line_in() {
  printf '%s\n' "$1" | command grep -n -m1 -F -- "$2" | cut -d: -f1
}

# Fails unless every marker after TEXT is present in it, in increasing order.
_order_in() {
  local _text="$1" _prev=0 _marker _n
  shift
  for _marker in "$@"; do
    _n="$(_line_in "${_text}" "${_marker}")"
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

# 40-hex SHA a workflow file pins an action to (first use), empty when absent.
_pin_of() {
  command grep -oE "uses: $2@[0-9a-f]{40}" "$1" | head -n 1 | sed 's/.*@//'
}

# --- workflow level -----------------------------------------------------------

@test "triggers are exactly schedule (cron 0 6 * * 1) and workflow_dispatch" {
  local _triggers
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

@test "workflow level sets the Node 24 flag, concurrency without cancel, and the bash shell" {
  local _env _conc _def
  _env="$(_top env)"
  [[ "${_env}" == *'  FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: true'* ]]
  _conc="$(_top concurrency)"
  [[ "${_conc}" == *'  group: uv-lock-refresh'* ]]
  [[ "${_conc}" == *'  cancel-in-progress: false'* ]]
  # bash supplies pipefail, without which `{ ...; } | tee` swallows failures.
  _def="$(_top defaults)"
  [[ "${_def}" == *'  run:'* ]]
  [[ "${_def}" == *'    shell: bash'* ]]
  # No step or job picks a different shell.
  [ "$(command grep -cE '^[[:space:]]+shell:' "${WF}")" -eq 1 ]
}

@test "exactly three jobs: refresh, publish, report, each ubuntu-latest with a 10 minute timeout" {
  [ "$(_job_names | tr '\n' ' ')" = "refresh publish report " ]
  local _j
  for _j in refresh publish report; do
    _job "${_j}" | command grep -qE '^    timeout-minutes: 10$'
    _job "${_j}" | command grep -qE '^    runs-on: ubuntu-latest$'
  done
}

@test "every uses: is pinned to a 40-hex SHA and at least one exists" {
  local _total _pinned
  _total="$(command grep -cE '^[[:space:]]*-?[[:space:]]*uses:' "${WF}")"
  _pinned="$(command grep -cE '^[[:space:]]*-?[[:space:]]*uses: [^@[:space:]]+@[0-9a-f]{40}( |$)' "${WF}")"
  [ "${_total}" -ge 1 ]
  [ "${_total}" -eq "${_pinned}" ]
}

@test "artifact actions are pinned to the same SHAs as ci.yml" {
  local _up_ci _up_wf _down_ci _down_wf
  _up_ci="$(_pin_of "${CI}" 'actions/upload-artifact')"
  _down_ci="$(_pin_of "${CI}" 'actions/download-artifact')"
  _up_wf="$(_pin_of "${WF}" 'actions/upload-artifact')"
  _down_wf="$(_pin_of "${WF}" 'actions/download-artifact')"
  # Positive control: the parse found real SHAs.
  [[ "${_up_ci}" =~ ^[0-9a-f]{40}$ ]]
  [[ "${_down_ci}" =~ ^[0-9a-f]{40}$ ]]
  [ "${_up_wf}" = "${_up_ci}" ]
  [ "${_down_wf}" = "${_down_ci}" ]
  # Every artifact use is that pin, not just the first.
  [ "$(command grep -cE 'uses: actions/upload-artifact@' "${WF}")" -eq "$(command grep -cE "uses: actions/upload-artifact@${_up_ci}" "${WF}")" ]
  [ "$(command grep -cE 'uses: actions/download-artifact@' "${WF}")" -eq "$(command grep -cE "uses: actions/download-artifact@${_down_ci}" "${WF}")" ]
}

@test "UV_VER and UV_SHA256 equal the test-shard job's values in ci.yml" {
  local _ci_ver _ci_sha _wf_ver _wf_sha
  _ci_ver="$(_job_value "${CI}" test-shard UV_VER)"
  _ci_sha="$(_job_value "${CI}" test-shard UV_SHA256)"
  _wf_ver="$(awk '$1 == "UV_VER:" { gsub(/"/, "", $2); print $2; exit }' "${WF}")"
  _wf_sha="$(awk '$1 == "UV_SHA256:" { gsub(/"/, "", $2); print $2; exit }' "${WF}")"
  [[ "${_ci_ver}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
  [[ "${_ci_sha}" =~ ^[0-9a-f]{64}$ ]]
  [ "${_wf_ver}" = "${_ci_ver}" ]
  [ "${_wf_sha}" = "${_ci_sha}" ]
}

@test "no event free-text interpolation and no merge, approve, label, branch delete or master write" {
  _absent -qF 'github.event'
  _absent -qF 'gh pr merge'
  _absent -qF -- '--approve'
  _absent -qF 'gh pr review'
  _absent -qF 'label'
  _absent -qE 'git push[^#]*master'
  _absent -qF 'exclude-newer'
  _absent -qF -- '--delete-branch'
  _absent -qF -- '--search'
  _absent -qF 'contains('
}

# --- job refresh: no token, no persisted credentials --------------------------

@test "refresh job has no permissions key, no token, no gh, no push and persist-credentials: false" {
  local _r
  _r="$(_job refresh)"
  [[ -n "${_r}" ]]
  _none_in "${_r}" -E '^    permissions:'
  _none_in "${_r}" -E 'GH_TOKEN|GITHUB_TOKEN|github\.token|secrets\.'
  _none_in "${_r}" -E '(^|[^[:alnum:]_/.-])gh [a-z]'
  _none_in "${_r}" -E 'git push|git commit|git config'
  [[ "${_r}" == *'persist-credentials: false'* ]]
}

@test "refresh job: master guard first, checkout pins ref: master, then uv, then the refresh" {
  local _r _guard
  _r="$(_job refresh)"
  _guard="$(_step refresh "Require master ref")"
  [[ -n "${_guard}" ]]
  [[ "${_guard}" == *'GITHUB_REF'* ]]
  [[ "${_guard}" == *'refs/heads/master'* ]]
  [[ "${_guard}" == *'exit 1'* ]]
  [[ "${_r}" == *'          ref: master'* ]]
  _order_in "${_r}" '- name: Require master ref' 'actions/checkout@' '- name: Install uv (pinned)' \
    '- name: Refresh lock' '- name: Upload refresh output' '- name: Upload refresh logs'
}

@test "uv download is verified with sha256sum -c on a non-comment line, before extraction" {
  local _install
  _install="$(_step refresh "Install uv (pinned)" | command grep -vE '^[[:space:]]*#')"
  [[ "${_install}" == *'sha256sum -c'* ]]
  [[ "${_install}" == *'tar -xzf'* ]]
  _install="${_install%%tar -xzf*}"
  [[ "${_install}" == *'sha256sum -c'* ]]
}

@test "refresh writes result and body under RUNNER_TEMP/out and copies the six files on changed" {
  local _s
  _s="$(_step refresh "Refresh lock")"
  [[ "${_s}" == *'refresh-uv-lock.sh'* ]]
  [[ "${_s}" == *'mkdir -p "${RUNNER_TEMP}/out"'* ]]
  [[ "${_s}" == *'"${RUNNER_TEMP}/out/body.md"'* ]]
  [[ "${_s}" == *'tail -n 1'* ]]
  [[ "${_s}" == *'> "${RUNNER_TEMP}/out/result"'* ]]
  [[ "${_s}" == *'"changed" | "no changes"'* ]]
  local _f
  for _f in uv.lock requirements-ci.txt requirements-runtime-ci.txt requirements-ci-test.txt \
    requirements-ci-mutation.txt requirements-ci-audit.txt; do
    [[ "${_s}" == *"cp "*" ${_f} "* || "${_s}" == *"cp ${_f} "* ]]
  done
  [[ "${_s}" == *'"${RUNNER_TEMP}/out/"'* ]]
}

@test "refresh uploads RUNNER_TEMP/out as refresh-out and its logs as refresh-logs with if: always()" {
  local _out _logs
  _out="$(_step refresh "Upload refresh output")"
  [[ "${_out}" == *'actions/upload-artifact@'* ]]
  [[ "${_out}" == *'name: refresh-out'* ]]
  [[ "${_out}" == *'path: ${{ runner.temp }}/out'* ]]
  [[ "${_out}" == *'if-no-files-found: error'* ]]
  _logs="$(_step refresh "Upload refresh logs")"
  [[ "${_logs}" == *'actions/upload-artifact@'* ]]
  [[ "${_logs}" == *'name: refresh-logs'* ]]
  [[ "${_logs}" == *'path: ${{ runner.temp }}/*.log'* ]]
  [[ "$(printf '%s\n' "${_logs}" | command grep -E '^        if:')" == "        if: always()" ]]
}

# --- job publish: the only holder of write scopes -----------------------------

@test "publish job needs refresh, declares exactly the three write permissions and GH_TOKEN" {
  local _p
  _p="$(_job publish)"
  [[ "${_p}" == *'    needs: refresh'* ]]
  [ "$(_job_perms publish)" = "$(printf 'contents: write\nissues: write\npull-requests: write')" ]
  [[ "${_p}" == *'      GH_TOKEN: ${{ github.token }}'* ]]
}

@test "publish checkout pins ref: master, fetches full history and keeps its credentials" {
  local _p
  _p="$(_job publish)"
  [[ "${_p}" == *'          ref: master'* ]]
  [[ "${_p}" == *'          fetch-depth: 0'* ]]
  _none_in "${_p}" -F 'persist-credentials'
  [ "$(command grep -cE '^          ref: master$' "${WF}")" -eq 2 ]
}

@test "only publish contains git push and gh pr" {
  local _j
  for _j in refresh report; do
    _none_in "$(_job "${_j}")" -E 'git push|(^|[^[:alnum:]_/.-])gh pr'
  done
  [[ "$(_job publish)" == *'git push --force origin chore/uv-lock-refresh'* ]]
  [[ "$(_job publish)" == *'gh pr create'* ]]
  [[ "$(_job publish)" == *'git switch -C chore/uv-lock-refresh'* ]]
}

@test "publish validates the result word and passes it on through GITHUB_OUTPUT" {
  local _s
  _s="$(_step publish "Read refresh result")"
  [[ -n "${_s}" ]]
  [[ "${_s}" == *'${RUNNER_TEMP}/in/result'* ]]
  [[ "${_s}" == *'"changed" | "no changes"'* ]]
  [[ "${_s}" == *'exit 1'* ]]
  [[ "${_s}" == *'GITHUB_OUTPUT'* ]]
  [[ "${_s}" == *'id: refresh'* ]]
}

@test "publish stages exactly the six files by explicit name, never a glob or recursive copy" {
  local _s _f _n
  _s="$(_step publish "Stage refreshed files")"
  [[ -n "${_s}" ]]
  [[ "${_s}" == *"if: steps.refresh.outputs.result == 'changed'"* ]]
  for _f in uv.lock requirements-ci.txt requirements-runtime-ci.txt requirements-ci-test.txt \
    requirements-ci-mutation.txt requirements-ci-audit.txt; do
    [[ "${_s}" == *"cp \"\${RUNNER_TEMP}/in/${_f}\" ${_f}"* ]] || {
      printf 'missing explicit copy of %s\n' "${_f}" >&2
      return 1
    }
  done
  _n="$(printf '%s\n' "${_s}" | command grep -cE '^ +cp ')"
  [ "${_n}" -eq 6 ]
  _none_in "${_s}" -E 'cp +-[a-zA-Z]*[rR]|\*|in/\.|rsync|tar |unzip'
}

@test "git identity is set before the commit" {
  _order_in "$(_job publish)" 'git config user.name "github-actions[bot]"' \
    'git config user.email "github-actions[bot]@users.noreply.github.com"' 'git commit'
}

@test "commit names exactly the six refresh files" {
  local _add
  _add="$(_job publish | command grep -F 'git add')"
  [ "$(printf '%s\n' "${_add}" | wc -l)" -eq 1 ]
  [[ "${_add}" == *' uv.lock '* ]]
  local _f
  for _f in requirements-ci.txt requirements-runtime-ci.txt requirements-ci-test.txt \
    requirements-ci-mutation.txt requirements-ci-audit.txt; do
    [[ "${_add}" == *" ${_f}"* ]]
  done
  [[ "${_add}" != *' . '* && "${_add}" != *' -A'* && "${_add}" != *' -u'* ]]
}

@test "publish steps appear in order: result, stage, fork filter, edit, create, close, issue close, logs" {
  _order_in "$(_job publish)" '- name: Read refresh result' '- name: Stage refreshed files' \
    'isCrossRepository' 'gh pr edit' 'gh pr create' 'gh pr close' 'gh issue close' \
    '- name: Upload publish logs'
  _order_in "$(cat "${WF}")" 'refresh-uv-lock.sh' '  publish:' 'gh pr edit' '  report:'
}

@test "more than one open same-repo refresh PR fails the job" {
  local _find _guard
  _find="$(_step publish "Find open refresh PR")"
  [[ "${_find}" == *'select(.isCrossRepository==false)'* ]]
  # The exit must sit inside the `-gt 1` block, not merely somewhere nearby.
  _guard="$(printf '%s\n' "${_find}" | awk '
    /if \[\[ "\$\{count\}" -gt 1 \]\]; then/ { b = 1; next }
    b && /^ *fi$/ { exit }
    b { print }
  ')"
  [[ "${_guard}" == *'exit 1'* ]]
}

@test "PR number, base branch, body file and close are pinned to the found PR and master" {
  local _pub _close
  _pub="$(_step publish "Publish refresh branch and PR")"
  [[ "${_pub}" == *"if: steps.refresh.outputs.result == 'changed'"* ]]
  [[ "${_pub}" == *'PR_NUMBER: ${{ steps.find_pr.outputs.number }}'* ]]
  [[ "${_pub}" == *'gh pr edit "${PR_NUMBER}" --body-file "${RUNNER_TEMP}/in/body.md"'* ]]
  [[ "${_pub}" == *'--base master'* ]]
  [[ "${_pub}" == *'--head chore/uv-lock-refresh'* ]]
  [[ "${_pub}" == *'--body-file "${RUNNER_TEMP}/in/body.md"'* ]]
  _close="$(_step publish "Close refresh PR when nothing changed")"
  [[ "${_close}" == *'PR_NUMBER: ${{ steps.find_pr.outputs.number }}'* ]]
  [[ "${_close}" == *'gh pr comment "${PR_NUMBER}"'* ]]
  [[ "${_close}" == *'gh pr close "${PR_NUMBER}"'* ]]
  # The close line carries no extra flags (no branch deletion).
  printf '%s\n' "${_close}" | command grep -qE '^ +gh pr close "\$\{PR_NUMBER\}"$'
  [[ "${_close}" == *"steps.refresh.outputs.result == 'no changes'"* ]]
}

@test "success issue-close runs only on success" {
  local _step_if _s
  _s="$(_step publish "Close failure issue")"
  [[ "${_s}" == *'gh issue close'* ]]
  _step_if="$(printf '%s\n' "${_s}" | command grep -E '^        if:' || true)"
  [[ -z "${_step_if}" || "${_step_if}" == "        if: success()" ]]
}

@test "issue lookups select by exact title: one in publish, one in report" {
  [ "$(_code | command grep -cF 'select(.title == "uv.lock refresh failed")')" -eq 2 ]
  [ "$(_job publish | command grep -cF 'select(.title == "uv.lock refresh failed")')" -eq 1 ]
  [ "$(_job report | command grep -cF 'select(.title == "uv.lock refresh failed")')" -eq 1 ]
  [ "$(_code | command grep -cF 'gh issue list')" -eq 2 ]
  command grep -qF -- '--title "uv.lock refresh failed"' "${WF}"
}

@test "publish uploads its logs as publish-logs with if: always()" {
  local _logs
  _logs="$(_step publish "Upload publish logs")"
  [[ "${_logs}" == *'actions/upload-artifact@'* ]]
  [[ "${_logs}" == *'name: publish-logs'* ]]
  [[ "${_logs}" == *'path: ${{ runner.temp }}/*.log'* ]]
  [[ "$(printf '%s\n' "${_logs}" | command grep -E '^        if:')" == "        if: always()" ]]
}

@test "publish downloads refresh-out into RUNNER_TEMP/in before using it" {
  local _p
  _p="$(_job publish)"
  [[ "${_p}" == *'actions/download-artifact@'* ]]
  [[ "${_p}" == *'name: refresh-out'* ]]
  [[ "${_p}" == *'path: ${{ runner.temp }}/in'* ]]
  _order_in "${_p}" 'actions/download-artifact@' '- name: Read refresh result'
}

# --- job report: issues only --------------------------------------------------

@test "report job needs both jobs, runs on failure or cancel, holds only issues: write and has no checkout" {
  local _r
  _r="$(_job report)"
  [[ "${_r}" == *'    needs: [refresh, publish]'* ]]
  [[ "$(printf '%s\n' "${_r}" | command grep -E '^    if:')" == '    if: ${{ failure() || cancelled() }}' ]]
  [ "$(_job_perms report)" = "issues: write" ]
  [[ "${_r}" == *'      GH_TOKEN: ${{ github.token }}'* ]]
  _none_in "${_r}" -F 'actions/checkout'
  _none_in "${_r}" -E 'git push|(^|[^[:alnum:]_/.-])gh pr'
}

@test "report downloads every *-logs artifact merged, with if: always() on both steps" {
  local _dl _rep
  _dl="$(_step report "Download step logs")"
  [[ "${_dl}" == *'actions/download-artifact@'* ]]
  [[ "${_dl}" == *"pattern: \"*-logs\""* ]]
  [[ "${_dl}" == *'merge-multiple: true'* ]]
  [[ "${_dl}" == *'path: ${{ runner.temp }}/logs'* ]]
  [[ "$(printf '%s\n' "${_dl}" | command grep -E '^        if:')" == "        if: always()" ]]
  _rep="$(_step report "Report failure")"
  [[ "$(printf '%s\n' "${_rep}" | command grep -E '^        if:')" == "        if: always()" ]]
}

@test "report step reads the newest log, last 40 lines, links the run and tolerates no logs" {
  local _rep
  _rep="$(_step report "Report failure")"
  [[ -n "${_rep}" ]]
  [[ "${_rep}" == *'${RUNNER_TEMP}/logs'* ]]
  [[ "${_rep}" == *'tail -n 40'* ]]
  [[ "${_rep}" == *'${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}'* ]]
  [[ "${_rep}" == *'gh issue create'* ]]
  [[ "${_rep}" == *'gh issue comment'* ]]
  [[ "${_rep}" == *'No step log was written before the failure.'* ]]
}

# --- tee coverage -------------------------------------------------------------

@test "every working step after checkout in refresh and publish tees to a RUNNER_TEMP log" {
  local _name
  for _name in "Install uv (pinned)" "Refresh lock"; do
    [[ "$(_step refresh "${_name}")" == *'| tee "${RUNNER_TEMP}/'* ]] || {
      printf 'no tee in refresh step: %s\n' "${_name}" >&2
      return 1
    }
  done
  for _name in "Read refresh result" "Stage refreshed files" "Find open refresh PR" \
    "Publish refresh branch and PR" "Close refresh PR when nothing changed" \
    "Close failure issue"; do
    [[ "$(_step publish "${_name}")" == *'| tee "${RUNNER_TEMP}/'* ]] || {
      printf 'no tee in publish step: %s\n' "${_name}" >&2
      return 1
    }
  done
}
