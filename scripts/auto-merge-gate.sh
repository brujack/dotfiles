#!/usr/bin/env bash
# auto-merge-gate.sh <pr-number> -- decides whether ci.yml's auto-merge job may
# merge a PR whose checks are green. Writes merge=true or merge=false to
# $GITHUB_OUTPUT and exits 0; exits 1 without writing a decision when it
# cannot decide, so a broken query can never fall through to a merge.
#
# Held for a human (merge=false, green):
#   - a Renovate PR without the automerge-ok label;
#   - any PR that changes uv.lock without changing pyproject.toml;
#   - any PR whose file list gh truncated, since uv.lock could be the hidden one.
#
# Moved out of ci.yml so it can be tested; the comments below came with it.

# The lock-without-manifest rule is deliberately actor-agnostic. dotfiles#227
# (uv.lock +20/-85, manifest untouched) was authored by Dependabot, which no
# tracked file here configures, and it merged because an internally
# consistent lock passes every check. A deliberate `uv lock --upgrade-package`
# has the same shape and is held too: a human merges it after reading it.
_gate_lock_without_manifest() {
  local _files="$1"
  grep -qx 'uv.lock' <<< "${_files}" && ! grep -qx 'pyproject.toml' <<< "${_files}"
}

auto_merge_gate() {
  local _pr="$1"
  if [[ -z "${_pr}" ]]; then
    printf 'usage: auto-merge-gate.sh <pr-number>\n' >&2
    return 1
  fi

  local _json
  _json="$(gh pr view "${_pr}" --json author,labels,files,changedFiles)" || {
    printf 'cannot query PR %s -- refusing to auto-merge\n' "${_pr}" >&2
    return 1
  }

  # `app/renovate` is what `gh pr view --json author` returns. REST says
  # `renovate[bot]` for the SAME PR, and mixing them fails open. Do NOT settle
  # it with `gh pr list --author`: it accepts BOTH and bare `renovate` returns
  # 0, indistinguishable from "no PRs".
  local _author _labels _files _listed _changed
  if ! _author="$(jq -er '.author.login' <<< "${_json}")" ||
    ! _labels="$(jq -r '.labels[].name' <<< "${_json}")" ||
    ! _files="$(jq -r '.files[].path' <<< "${_json}")" ||
    ! _listed="$(jq -e '.files | length' <<< "${_json}")" ||
    ! _changed="$(jq -e '.changedFiles' <<< "${_json}")"; then
    printf 'cannot read PR %s -- refusing to auto-merge\n' "${_pr}" >&2
    return 1
  fi

  # AFFIRMATIVE label, not `!major`: excluding a negative fails OPEN, since every
  # way labelling can break yields a PR without the label. Scoped to Renovate:
  # the label comes from renovate.json, so no human PR can carry it.
  if [[ "${_author}" == "app/renovate" ]] && ! grep -qx 'automerge-ok' <<< "${_labels}"; then
    printf 'renovate PR lacks automerge-ok -- leaving open for triage\n'
    printf 'merge=false\n' >> "${GITHUB_OUTPUT}"
    return 0
  fi

  if [[ "${_listed}" -lt "${_changed}" ]]; then
    printf 'gh listed %s of %s changed files -- leaving open for a human\n' "${_listed}" "${_changed}"
    printf 'merge=false\n' >> "${GITHUB_OUTPUT}"
    return 0
  fi

  if _gate_lock_without_manifest "${_files}"; then
    printf 'uv.lock changed without pyproject.toml -- leaving open for a human\n'
    printf 'merge=false\n' >> "${GITHUB_OUTPUT}"
    return 0
  fi

  printf 'merge=true\n' >> "${GITHUB_OUTPUT}"
  printf 'cleared to merge (author=%s)\n' "${_author}"
}

[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0
auto_merge_gate "$@"
