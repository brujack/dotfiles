#!/usr/bin/env bash
# Usage: auto-merge-merge.sh <pr> <head_sha>
#
# Runs the auto-merge job's one `gh pr merge` and retries only GitHub's
# "base branch policy prohibits the merge" refusal. That refusal can arrive
# before the required-check state has reached the merge API even though every
# check is green, so a short wait usually clears it. Any other failure, empty
# output included, is not retried and exits 1 at once.
#
# ci.yml runs this script from the base commit (git show "${BASE_SHA}:..."),
# never from the PR checkout, so a PR cannot change the code that merges it.
# AUTO_MERGE_RETRY_DELAY overrides the 30 second wait between attempts; it must
# be a non-negative integer, else the script refuses before any gh call.

readonly _AUTO_MERGE_REFUSAL='base branch policy prohibits the merge'
readonly _AUTO_MERGE_ATTEMPTS=3

auto_merge_merge() {
  local _pr="${1:-}" _sha="${2:-}" _delay="${AUTO_MERGE_RETRY_DELAY:-30}" _n _out _rc
  if [[ -z "${_pr}" || -z "${_sha}" ]]; then
    printf 'usage: auto-merge-merge.sh <pr> <head_sha>\n' >&2
    return 1
  fi
  if [[ ! "${_delay}" =~ ^[0-9]+$ ]]; then
    printf 'usage: AUTO_MERGE_RETRY_DELAY must be a non-negative integer, got %s\n' "${_delay}" >&2
    return 1
  fi
  for ((_n = 1; _n <= _AUTO_MERGE_ATTEMPTS; _n++)); do
    printf 'attempt %d/%d at %s\n' "${_n}" "${_AUTO_MERGE_ATTEMPTS}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    _out="$(gh pr merge "${_pr}" --squash --match-head-commit "${_sha}" 2>&1)"
    _rc=$?
    [[ -n "${_out}" ]] && printf '%s\n' "${_out}"
    [[ "${_rc}" -eq 0 ]] && return 0
    [[ "${_out}" == *"${_AUTO_MERGE_REFUSAL}"* ]] || return 1
    if [[ "${_n}" -lt "${_AUTO_MERGE_ATTEMPTS}" ]]; then
      sleep "${_delay}"
    fi
  done
  printf 'still refused after %d attempts: merge by hand with gh pr merge %s --squash --match-head-commit %s, or re-run all jobs, never failed-only\n' \
    "${_AUTO_MERGE_ATTEMPTS}" "${_pr}" "${_sha}"
  return 1
}

[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0
auto_merge_merge "$@" || exit 1
