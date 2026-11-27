#!/usr/bin/env bash
# Shared by scripts/whats-new-claude-code.sh and scripts/whats-new-anthropic.sh.
#
# The scheduled routines run these scripts in a cloud sandbox that checks out a
# detached HEAD or a per-run branch with no upstream, so a bare `git push` never
# worked there; each run's model improvised instead (a direct push to master that
# bypassed the required checks, or a branch with no PR). publish_digest pushes the
# committed digest to its own branch and returns non-zero when any step fails.
# It opens no PR: the sandbox's proxy permits git push, but on 2026-11-23 its run
# logs showed `gh pr create` failing with HTTP 403 (GraphQL) and REST contents-API
# PUTs refused ("Write access to this GitHub API path is not permitted through this
# proxy"), so the digest-pr workflow (.github/workflows/digest-pr.yml,
# scripts/digest-pr.sh) opens the PR on the push.

# publish_digest <branch> <title> <dir>
#   Run from the repo root after the digest commit. Refuses unless every file
#   HEAD changes relative to origin's master lies under <dir>, so a sandbox branch
#   carrying other commits cannot reach master through the digest PR (the workflow
#   opens it with GITHUB_TOKEN, so it gets no CI until closed and reopened and is
#   held as a bot PR for the operator to merge).
#   0 = pushed; 1 = refused or push failed (stderr says which); 2 = bad usage.
publish_digest() {
  if [[ $# -ne 3 ]]; then
    printf 'usage: publish_digest <branch> <title> <dir>\n' >&2
    return 2
  fi
  local _branch="$1" _title="$2" _dir="${3%/}" _files _f

  git fetch -q origin master || {
    printf 'Error: cannot fetch origin master to check what %s would publish\n' "${_branch}" >&2
    return 1
  }
  # --no-renames: a rename lists only its destination, hiding a deletion outside <dir>.
  _files="$(git diff --no-renames --name-only FETCH_HEAD...HEAD)" || {
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
  printf 'Pushed %s; the digest-pr workflow will open the PR (%s).\n' "${_branch}" "${_title}"
}
