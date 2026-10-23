# ADR-0049: pre-push refuses a push whose refs are not at the tested tree

**Date:** 2026-10-22
**Status:** Accepted

## Context

`scripts/pre-push` runs `make test` in `REPO_ROOT`, the top of the checkout that issued the
push. Nothing tied that tree to the commit being pushed, so a branch pushed from the main
checkout was gated on master's tree and the verdict was reported as the branch's. Measured
2026-09-11: a main-checkout push of `docs/claude-workstation` failed on a RED test that
existed only on master, and the same push from the branch's worktree passed. The opposite
case passes a broken branch on a green tree. `.git/hooks/pre-push` links the main checkout's
copy, so the hook decides for every worktree.

Two alternatives were rejected:

- **Test in the worktree that holds the pushed commit.** The hook would choose a tree from
  `git worktree list` and would have nothing to test when no worktree holds the commit.
- **Test a `git archive` of the pushed commit.** This tests exactly the pushed tree, but it
  drops the untracked state the suite relies on and is slower on every push.

Full record: `docs/superpowers/specs/2026-10-22-pre-push-wrong-tree-refusal-design.md`.

## Decision

1. Once the suite would run (`needs_test=1`), every non-deletion ref must name, peeled to a
   commit, the `HEAD` of `REPO_ROOT`. Otherwise the push is refused before `make`. An
   inert-only push is never checked.
2. `HEAD` is read from `REPO_ROOT` with `GIT_DIR`, `GIT_WORK_TREE`, `GIT_COMMON_DIR` and
   `GIT_INDEX_FILE` stripped. A read through an inherited `GIT_DIR` named a different `HEAD`
   than the one `make` tests, and a wrong-tree push passed.
3. The check fails closed. An unresolvable `HEAD` or an unpeelable ref is refused, and two
   empty values never count as a match.
4. The check runs after the unresolved-range, CLAUDE.md budget and direct-to-master
   refusals, so their messages keep precedence.
5. The refusal prints the exact `git push <remote> <src>:<remote_ref>` to re-run, and
   names the remote only when it is a configured remote, so a URL carrying a token is
   never printed.

## Consequences

- A push carrying refs at two or more commits that needs the suite can never pass, for
  example a stacked-branch push or `--follow-tags` with an older tag. Push each ref on its
  own. The only escape is `--no-verify`, which skips every check in the hook.
- The fleet rule git-workflow-043 ("push from main") prescribed the refused push. It was
  rewritten in ai-config#325 to say: push from the branch's worktree, and strip `GIT_*` in
  the hook when tests fail only during push.
- The suite still runs against the working tree as it is on disk, so uncommitted edits in
  the right checkout are tested along with the commit. This is a separate backlog row.

## Related

- ADR-0017 (pre-push trigger fails closed), which owns the inert set this check skips.
- dotfiles#365, ai-config#325.
