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
#
# jq makes every decision, comparing whole paths as strings. Splitting paths
# on newlines in shell let a filename containing one pose as pyproject.toml,
# and a field that is missing or of the wrong type must stop the gate, not
# compare as null and quietly skip a check.
#
# `app/renovate` is what `gh pr view --json author` returns. REST says
# `renovate[bot]` for the SAME PR, and mixing them fails open. Do NOT settle
# it with `gh pr list --author`: it accepts BOTH and bare `renovate` returns
# 0, indistinguishable from "no PRs".
#
# AFFIRMATIVE label, not `!major`: excluding a negative fails OPEN, since every
# way labelling can break yields a PR without the label. Scoped to Renovate:
# the label comes from renovate.json, so no human PR can carry it.
_gate_verdict() {
  # shellcheck disable=SC2016 # $f is a jq variable; this program must reach jq unexpanded
  jq -r '
  if (.author.login | type) != "string" or (.changedFiles | type) != "number"
     or (.files | type) != "array" or (.labels | type) != "array"
  then error("malformed payload") else . end
  | [.files[].path] as $f
  | if .author.login == "app/renovate"
       and (any(.labels[]; .name == "automerge-ok") | not) then "renovate-unlabelled"
    elif ($f | length) < .changedFiles then "truncated"
    elif any($f[]; . == "uv.lock") and (any($f[]; . == "pyproject.toml") | not) then "lock-only"
    else "clear" end'
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

  local _verdict
  _verdict="$(_gate_verdict <<< "${_json}" 2> /dev/null)" || {
    printf 'cannot read PR %s -- refusing to auto-merge\n' "${_pr}" >&2
    return 1
  }

  case "${_verdict}" in
    renovate-unlabelled)
      printf 'renovate PR lacks automerge-ok -- leaving open for triage\n'
      ;;
    truncated)
      printf 'gh could not list every changed file -- leaving open for a human\n'
      ;;
    lock-only)
      printf 'uv.lock changed without pyproject.toml -- leaving open for a human\n'
      ;;
    clear)
      printf 'merge=true\n' >> "${GITHUB_OUTPUT}"
      printf 'cleared to merge\n'
      return 0
      ;;
    *)
      printf 'unexpected gate verdict %s -- refusing to auto-merge\n' "${_verdict}" >&2
      return 1
      ;;
  esac
  printf 'merge=false\n' >> "${GITHUB_OUTPUT}"
}

[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0
auto_merge_gate "$@"
