#!/usr/bin/env bash
# Shared by scripts/whats-new-claude-code.sh and scripts/whats-new-anthropic.sh.
#
# The scheduled routines run these scripts in a cloud sandbox that checks out a
# detached HEAD or a per-run branch with no upstream, so a bare `git push` never
# worked there; each run's model improvised instead (a direct push to master that
# bypassed the required checks, or a branch with no PR). publish_digest pushes the
# committed digest to its own branch and opens a PR, so the digest reaches master
# through CI and auto-merge, and returns non-zero when either step fails.

# publish_digest <branch> <title>
#   Run from the repo root after the digest commit. 0 = pushed and PR opened;
#   1 = push or PR failed (stderr says which); 2 = bad usage.
publish_digest() {
  if [[ $# -ne 2 ]]; then
    printf 'usage: publish_digest <branch> <title>\n' >&2
    return 2
  fi
  local _branch="$1" _title="$2" _gh="${_DIGEST_GH_BIN:-gh}"

  # An explicit refspec works from a detached HEAD and needs no upstream. A plain
  # push never forces, so an existing branch with other history is left alone.
  git push origin "HEAD:refs/heads/${_branch}" || {
    printf 'Error: git push of %s failed; the digest is committed locally only\n' "${_branch}" >&2
    return 1
  }
  "${_gh}" pr create --base master --head "${_branch}" --title "${_title}" \
    --body "Weekly digest committed by the scheduled routine." || {
    printf 'Error: pushed %s but could not open the PR; open it by hand\n' "${_branch}" >&2
    return 1
  }
}
