#!/usr/bin/env bash
# Shared by scripts/whats-new-claude-code.sh and scripts/whats-new-anthropic.sh.
#
# The scheduled routines run these scripts in a cloud sandbox that checks out a
# detached HEAD or a per-run branch with no upstream, so a bare `git push` never
# worked there; each run's model improvised instead (a direct push to master that
# bypassed the required checks, or a branch with no PR). publish_digest pushes the
# committed digest to its own branch and opens a PR, so the digest reaches master
# through CI and auto-merge, and returns non-zero when any step fails.

# publish_digest <branch> <title> <dir>
#   Run from the repo root after the digest commit. Refuses unless every file
#   HEAD changes relative to origin's master lies under <dir>, so a sandbox branch
#   carrying other commits cannot ride an auto-merged digest PR into master.
#   0 = pushed and PR opened; 1 = refused, push or PR failed (stderr says which);
#   2 = bad usage.
publish_digest() {
  if [[ $# -ne 3 ]]; then
    printf 'usage: publish_digest <branch> <title> <dir>\n' >&2
    return 2
  fi
  local _branch="$1" _title="$2" _dir="${3%/}" _gh="${_DIGEST_GH_BIN:-gh}"
  local _repo="${DIGEST_REPO:-brujack/dotfiles}" _files _f

  git fetch -q origin master || {
    printf 'Error: cannot fetch origin master to check what %s would publish\n' "${_branch}" >&2
    return 1
  }
  _files="$(git diff --name-only FETCH_HEAD...HEAD)" || {
    printf 'Error: cannot diff HEAD against origin master\n' >&2
    return 1
  }
  if [[ -z "${_files}" ]]; then
    printf 'Error: nothing to publish: HEAD adds nothing to origin master\n' >&2
    return 1
  fi
  while IFS= read -r _f; do
    [[ "${_f}" == "${_dir}/"* ]] || {
      printf 'Error: refusing to publish %s: %s is outside %s\n' "${_branch}" "${_f}" "${_dir}" >&2
      return 1
    }
  done <<< "${_files}"

  # An explicit refspec works from a detached HEAD and needs no upstream. A plain
  # push never forces, so an existing branch with other history is left alone.
  git push origin "HEAD:refs/heads/${_branch}" || {
    printf 'Error: git push of %s failed; the digest is committed locally only\n' "${_branch}" >&2
    return 1
  }
  # --repo: gh otherwise infers the repo from origin's URL, which a sandbox may rewrite.
  "${_gh}" pr create --repo "${_repo}" --base master --head "${_branch}" --title "${_title}" \
    --body "Weekly digest committed by the scheduled routine." || {
    printf 'Error: pushed %s but could not open the PR; open it by hand\n' "${_branch}" >&2
    return 1
  }
}
