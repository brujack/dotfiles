# pre-push: refuse a push whose tested tree is not the pushed commit

- **Date:** 2026-10-22
- **Backlog row:** `docs/superpowers/README.md` P2, "`scripts/pre-push` gates the wrong tree when the push comes from the main checkout"
- **Operator decision (2026-10-22):** refuse with a message, rather than testing in the owning worktree or testing an archive of the pushed commit.

## Problem

`scripts/pre-push:7` sets `REPO_ROOT` from `git rev-parse --show-toplevel`, and `:206` runs
`make -C "${REPO_ROOT}" test`. That tests the working tree of whichever checkout issued the
push. Nothing in the hook relates that tree to the commit being pushed (`local_sha` on the
ref line). Pushing branch `X` from a checkout that has `master` checked out therefore runs
master's suite and reports its verdict as `X`'s.

Measured 2026-09-11 (the backlog row): a push of `docs/claude-workstation` issued from the
main checkout failed on a RED test that existed only on master; the same push from the
branch's worktree passed first time. The failure named the test, not the actor mismatch, so
the cause was not visible from the output. The opposite direction is the dangerous one and
has the same mechanism: a broken branch pushed from a checkout holding a green tree passes.

Premise checked 2026-10-22 against `origin/master` 566dd444: `:7` and `:206` are as described,
and no line between them reads `HEAD` or compares any ref line's `local_sha` with the tree.
No spec or ADR in `docs/` has proposed or rejected a fix for this (grep for `pre-push` and
`show-toplevel` over `docs/adr` and `docs/superpowers/specs`); ADR-0017 and the 2026-10-02
master-guard spec cover the trigger set and the master guard only.

Every worktree runs this file: `.git/hooks/pre-push` is a symlink to the main checkout's
`scripts/pre-push`, so the change reaches every push in the repo once it is on master.

## Design

### Which refs must match

A ref line **needs the tree** when its own diff range sets `needs_test`: the diff failed to
resolve, or at least one changed path is not inert by `_path_is_inert`. This is the same test
the loop already applies; the change records it per ref instead of only in the aggregate.
Deletion lines (`local_sha` all zeros) are already skipped and stay skipped.

A ref that is inert-only never needs the tree, so a doc push from any checkout behaves exactly
as today.

### The check

After the loop, after the existing three refusals (unresolved range, CLAUDE.md budget,
direct-to-master), and only when `needs_test=1`:

1. Resolve the tested tree's commit: `git rev-parse --verify --quiet 'HEAD^{commit}'`, run
   before the `unset GIT_DIR ...` line so a worktree push reads the worktree's own `HEAD`.
2. For each ref that needs the tree, peel its `local_sha`:
   `git rev-parse --verify --quiet "${local_sha}^{commit}"`. Peeling makes an annotated tag at
   `HEAD` match.
3. Refuse (exit 1, before `make`) if step 1 fails, if any peel fails, or if any peeled commit
   differs from step 1's commit. All three are fail-closed.

Placing it last keeps the existing refusals' messages and precedence unchanged; a push that
would already be refused for another reason reports that reason.

### The refusal message

To stderr, in the hook's existing style:

```
pre-push: the suite tests this checkout's working tree, not the pushed commit.
  <local_ref> is at <short sha>; this checkout is at <short sha> (<path>).
```

followed by one remedy per mismatched ref:

- If `git worktree list --porcelain` has an entry whose `HEAD` line equals the peeled commit,
  print `Push from the worktree that has it checked out:` and `  cd <that path> && git push ...`.
- Otherwise print `Check it out first, then push from there:` with
  `  git switch <branch>` or `  git worktree add <path> <branch>`, where `<branch>` is
  `local_ref` without `refs/heads/` (for a non-branch ref, the short sha).

The listing is read for the message only; it never changes the verdict. If
`git worktree list` itself fails, the generic remedy is printed.

### What does not change

- No `REPO_ROOT` override seam. The row suggested copying `terraform_ansible`'s
  `${REPO_ROOT:-...}`; that seam serves a different fix (choosing a tree), and a refusal
  needs none.
- The suite still runs against the working tree as it is on disk. Uncommitted edits in the
  correct checkout are still tested along with the commit; that is a separate gap (N1).

## Testing

New cases in `tests/scripts/pre_push.bats`, each building a fixture repo and feeding a
synthetic ref line:

| Case                     | Ref line                                                    | Expect                                                     |
| ------------------------ | ----------------------------------------------------------- | ---------------------------------------------------------- |
| mismatch refused         | non-inert change, `local_sha` = an older commit, HEAD ahead | exit 1, message names both short shas, `make` never called |
| match runs suite         | same change, `local_sha` = HEAD                             | exit 0, `make` called once                                 |
| inert-only mismatch      | `.md`-only change, `local_sha` != HEAD                      | exit 0, no refusal text, `make` not called                 |
| tag peeled               | annotated tag object at HEAD, non-inert change              | exit 0, `make` called                                      |
| worktree named           | mismatch, a fixture worktree has the commit checked out     | message contains that worktree's path                      |
| generic remedy           | mismatch, no worktree has it                                | message contains `git worktree add`                        |
| two refs, one mismatched | branch at HEAD plus a second non-inert ref elsewhere        | exit 1, names only the mismatched ref                      |

The "match runs suite" case is the one that proves the check computes: a check that never
read HEAD (always refusing, or always passing) fails it or the "mismatch refused" case.

Existing cases: any of the 110 that feeds a non-inert ref whose `local_sha` is not the fixture's
HEAD and asserts `make` ran will now be refused. Not yet measured; the plan's first task counts
them and changes each to push the fixture's HEAD, never weakening an assertion.

## Requirements

- **R1.** `scripts/pre-push` exits 1 without invoking `make` when a ref line whose diff sets `needs_test` has a `local_sha` that, peeled to a commit, differs from the hook checkout's `HEAD` commit.
- **R2.** `scripts/pre-push` exits 1 without invoking `make` when `HEAD` or a needs-test ref's `local_sha` cannot be peeled to a commit.
- **R3.** A push whose every ref line is inert-only is never refused by the R1/R2 check, whatever commit it names.
- **R4.** The R1 refusal message names the mismatched `local_ref`, both short SHAs and the checkout path.
- **R5.** When `git worktree list --porcelain` shows a worktree whose `HEAD` is the pushed commit, the refusal prints that worktree's path; otherwise it prints a `git worktree add` remedy.
- **R6.** The R1/R2 check runs after the unresolved-range, CLAUDE.md budget and direct-to-master refusals, so each of those keeps its existing message when it also applies.
- **R7.** `HEAD` is resolved before the hook's `unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE` line.
- **R8.** `tests/scripts/pre_push.bats` carries the seven cases in the Testing table.
- **V1.** `make test` exits 0 on the branch.
- **V2.** A real push of the feature branch from its own worktree passes the hook; a real push of the same branch from the main checkout (on master) is refused with the R4 message. Record both outputs in the PR body.
- **N1.** The hook does not change what the suite runs against: no `git archive`, no switching, no temporary checkout.
- **N2.** No `REPO_ROOT` override seam is added.
- **N3.** No existing pre_push.bats assertion is deleted or weakened; an existing case is changed only to push its fixture's HEAD.
- **N4.** ai-config's and terraform_ansible's hooks are not changed.
