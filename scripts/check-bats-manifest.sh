#!/usr/bin/env bash
# Check that the tracked .bats files equal tests/bats-files.txt.
#
# Usage: check-bats-manifest.sh [<repo-root>]   (default: this script's repo)
# Exit: 0 match; 1 mismatch, unsorted or duplicate manifest; 2 input error
# (manifest missing, unreadable or empty, git ls-files failed).
#
# The CI suite gates (ci-suite-report.sh --files, ci-shard-gate.sh) take their
# expected file set from the same walk that builds the shard lists, so deleting
# a .bats file shrinks both sides and every check still passes; the >= 840
# test-count floor that used to catch it went with the untraced test job
# (ADR-0054). This manifest is the anchor that walk cannot move: losing a test
# file now needs a deliberate one-line edit here, visible in review.
#
# Tracked files only (git ls-files, as Makefile's BATS_FILES): an untracked
# scratch .bats file or a parked worktree must not fail the check.

_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly _REPO_ROOT
readonly _MANIFEST_REL="tests/bats-files.txt"

manifest_die() {
  printf 'bats manifest: %s\n' "$1" >&2
  return 2
}

main() {
  local _root="${1:-${_REPO_ROOT}}" _manifest _tracked _listed _sorted _dups
  local _unlisted _gone _rc=0
  _manifest="${_root}/${_MANIFEST_REL}"
  if [[ ! -f "${_manifest}" || ! -r "${_manifest}" ]]; then
    manifest_die "cannot read ${_MANIFEST_REL} in ${_root}" || return 2
  fi
  _listed="$(sed '/^$/d' "${_manifest}")"
  if [[ -z "${_listed}" ]]; then
    manifest_die "${_MANIFEST_REL} is empty" || return 2
  fi
  # git -C does not override an exported GIT_DIR, so strip the four (shell-007).
  _tracked="$(env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE \
    git -C "${_root}" ls-files '*.bats' 2>/dev/null)" || {
    manifest_die "git ls-files failed in ${_root}" || return 2
  }
  _tracked="$(printf '%s\n' "${_tracked}" | sed '/^$/d' | LC_ALL=C sort)"

  _sorted="$(printf '%s\n' "${_listed}" | LC_ALL=C sort)"
  if [[ "${_sorted}" != "${_listed}" ]]; then
    printf 'bats manifest: %s is not sorted (LC_ALL=C)\n' "${_MANIFEST_REL}"
    _rc=1
  fi
  _dups="$(printf '%s\n' "${_sorted}" | LC_ALL=C uniq -d)"
  if [[ -n "${_dups}" ]]; then
    printf '%s\n' "${_dups}" | sed "s|^|bats manifest: duplicate in ${_MANIFEST_REL}: |"
    _rc=1
  fi

  _unlisted="$(LC_ALL=C comm -23 <(printf '%s\n' "${_tracked}") <(printf '%s\n' "${_sorted}" | LC_ALL=C sort -u))"
  _gone="$(LC_ALL=C comm -13 <(printf '%s\n' "${_tracked}") <(printf '%s\n' "${_sorted}" | LC_ALL=C sort -u))"
  if [[ -n "${_unlisted}" ]]; then
    printf '%s\n' "${_unlisted}" | sed "s|^|bats manifest: tracked but not listed in ${_MANIFEST_REL}: |"
    _rc=1
  fi
  if [[ -n "${_gone}" ]]; then
    printf '%s\n' "${_gone}" | sed "s|^|bats manifest: listed in ${_MANIFEST_REL} but not tracked: |"
    _rc=1
  fi

  if [[ ${_rc} -ne 0 ]]; then
    printf "bats manifest: if every change above is intended, regenerate with: git ls-files '*.bats' | LC_ALL=C sort > %s\n" \
      "${_MANIFEST_REL}"
    return 1
  fi
  printf 'bats manifest: %s files match %s\n' \
    "$(printf '%s\n' "${_tracked}" | wc -l | tr -d ' ')" "${_MANIFEST_REL}"
}

[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0
main "$@"
