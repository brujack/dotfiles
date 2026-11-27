#!/usr/bin/env bash
# Usage: digest-pr.sh <branch> <sha>
#
# Run by .github/workflows/digest-pr.yml when a scheduled routine pushes
# digest/<anthropic|claude-code>-<YYYY-MM-DD>. The routine's cloud session can
# push a branch but cannot create a PR (on 2026-11-23 its run logs showed
# `gh pr create` failing with HTTP 403 (GraphQL) and REST contents-API PUTs refused
# by the proxy), so the PR is opened here, with the workflow's GITHUB_TOKEN.
#
# Fails closed: it opens nothing unless the branch name has exactly the digest
# shape and every file the pushed commit adds to origin master lies under that
# digest's own directory. Idempotent: an open same-repo PR for the branch means
# there is nothing to do. Needs a checkout holding <sha> and its history, and
# GITHUB_REPOSITORY (set by Actions) and GH_TOKEN for gh.
#   0 = PR opened or already open; 1 = refused or a step failed (stderr says which);
#   2 = bad usage.

digest_pr() {
  if [[ $# -ne 2 ]]; then
    printf 'usage: digest-pr.sh <branch> <sha>\n' >&2
    return 2
  fi
  local _branch="$1" _sha="$2" _repo="${GITHUB_REPOSITORY:-}"
  local _kind _date _dir _name _title _files _f _count _tip

  if [[ ! "${_branch}" =~ ^digest/(anthropic|claude-code)-([0-9]{4}-[0-9]{2}-[0-9]{2})$ ]]; then
    printf 'Error: refusing %s: not digest/(anthropic|claude-code)-YYYY-MM-DD\n' "${_branch}" >&2
    return 1
  fi
  _kind="${BASH_REMATCH[1]}"
  _date="${BASH_REMATCH[2]}"
  case "${_kind}" in
    anthropic)
      _dir="docs/anthropic-new-features"
      _name="Anthropic"
      ;;
    claude-code)
      _dir="docs/claude-code-new-features"
      _name="Claude Code"
      ;;
  esac
  _title="docs: add ${_name} weekly features digest ${_date}"

  if [[ ! "${_sha}" =~ ^[0-9a-f]{40}$ ]]; then
    printf 'Error: refusing %s: %s is not a 40-digit commit sha\n' "${_branch}" "${_sha}" >&2
    return 1
  fi
  if [[ -z "${_repo}" ]]; then
    printf 'Error: GITHUB_REPOSITORY is unset; cannot say which repository to open the PR in\n' >&2
    return 1
  fi

  git fetch -q origin master || {
    printf 'Error: cannot fetch origin master to check what %s would publish\n' "${_branch}" >&2
    return 1
  }
  # --no-renames: a rename lists only its destination, hiding a deletion outside <dir>.
  _files="$(git diff --no-renames --name-only "FETCH_HEAD...${_sha}")" || {
    printf 'Error: cannot diff %s against origin master\n' "${_sha}" >&2
    return 1
  }
  if [[ -z "${_files}" ]]; then
    printf 'Error: nothing to open a PR for: %s adds nothing to origin master\n' "${_branch}" >&2
    return 1
  fi
  while IFS= read -r _f; do
    [[ "${_f}" == "${_dir}/"* ]] || {
      printf 'Error: refusing %s: %s is outside %s\n' "${_branch}" "${_f}" "${_dir}" >&2
      return 1
    }
  done <<< "${_files}"

  # The repo is public and a fork can name its branch the same; only a PR from
  # this repository counts. A failed lookup stops here: creating blind could
  # open a second PR.
  _count="$(gh pr list --repo "${_repo}" --head "${_branch}" --state open --json number,isCrossRepository \
    --jq '[.[]|select(.isCrossRepository==false)]|length')" || {
    printf 'Error: cannot list open PRs for %s\n' "${_branch}" >&2
    return 1
  }
  if [[ ! "${_count}" =~ ^[0-9]+$ ]]; then
    printf 'Error: unexpected PR count %q for %s\n' "${_count}" "${_branch}" >&2
    return 1
  fi
  if [[ "${_count}" -gt 0 ]]; then
    printf 'A PR for %s is already open; nothing to do\n' "${_branch}"
    return 0
  fi

  # `gh pr create --head` opens whatever the branch tip is when it runs, not the
  # commit the scope check read. A push that landed in between must not ride along:
  # refuse unless origin's tip is still exactly _sha (also refuses a deleted branch).
  _tip="$(git ls-remote origin "refs/heads/${_branch}")" || {
    printf 'Error: cannot read the tip of %s on origin; not opening a PR blind\n' "${_branch}" >&2
    return 1
  }
  _tip="${_tip%%[[:space:]]*}"
  if [[ "${_tip}" != "${_sha}" ]]; then
    printf 'Error: refusing %s: its tip on origin is %s, not the checked commit %s\n' "${_branch}" "${_tip:-<absent>}" "${_sha}" >&2
    return 1
  fi

  gh pr create --repo "${_repo}" --base master --head "${_branch}" --title "${_title}" \
    --body "Opened by the digest-pr workflow from the scheduled routine's push of ${_branch} (commit ${_sha}). Every changed file is under ${_dir}/." || {
    printf 'Error: %s passed the scope check but gh could not open the PR; open it by hand\n' "${_branch}" >&2
    return 1
  }
}

[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0
digest_pr "$@"
exit $?
