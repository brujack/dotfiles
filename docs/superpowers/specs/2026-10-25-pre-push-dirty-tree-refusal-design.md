# pre-push: refuse a push whose tested tree has changes not in the pushed commit

- **Date:** 2026-10-25
- **Backlog row:** `docs/superpowers/README.md` P2, "`scripts/pre-push` tests uncommitted edits along with the pushed commit"
- **Operator decision (2026-10-25):** refuse on a dirty tree (fail closed), rather than testing the pushed commit from a clean export. Consistent with the 2026-10-22 decision in `2026-10-22-pre-push-wrong-tree-refusal-design.md`.

## Problem

`scripts/pre-push:260` runs `make -C "${REPO_ROOT}" test`, which tests the working tree as it
is on disk. The wrong-tree refusal (`:202-246`, from the 2026-10-22 spec) guarantees only that
every pushed ref is at `REPO_ROOT`'s `HEAD`; it says nothing about edits on top of `HEAD`.
That spec named this gap as its N1 and left it open by design.

So an edit that is not in the pushed commit can change the verdict in either direction:

- **False green:** a fix made after the commit, still uncommitted, makes the suite pass for a
  commit that fails without it. CI (which tests the pushed commit from a clean checkout) then
  fails, costing a round trip.
- **False red:** a half-finished edit for the next task fails the suite and blocks a correct
  push.

The hazard includes untracked files, not only edits to tracked ones. The bats file list is a
filesystem walk (CLAUDE.md, Testing), so an untracked `tests/<x>.bats` that is not ignored is
run by the suite. Ignored files (`.venv`, coverage output) do not affect the verdict this way
and are out of scope.

Premise checked 2026-10-25 against `origin/master` a949f37a: nothing in the hook reads the
working-tree status (`grep -n 'status' scripts/pre-push` matches one comment, line 35).

**What else already catches it:** CI's `test` job, against the pushed commit. A false green
therefore cannot merge. Direct-to-master pushes never run the suite (inert paths only), so no
false green can land on master either. The cost of the gap is a wasted CI round trip (false
green) or a blocked correct push (false red), which is why this is P2, not P1.

No submodules exist (`git ls-files -s | grep -c '^160000'` → 0), so no submodule handling is
needed.

## Design

One new check in `scripts/pre-push`, placed after the wrong-tree refusal and before the
`unset GIT_DIR …` line and `make`. Reaching it means the suite would run and every pushed ref
is at `REPO_ROOT`'s `HEAD`.

1. Read the status of the tree `make` will test, with the git environment stripped exactly as
   the `tree_head` read is:

   ```bash
   env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE \
       git -C "${REPO_ROOT}" --no-optional-locks status --porcelain --untracked-files=all
   ```

   The read sits in a conditional (the hook runs under `set -e`). `--no-optional-locks` stops
   `git status` from refreshing the index's stat cache, so the hook writes nothing to the index
   (N2) and cannot contend for `index.lock` with a concurrent session in the same checkout.

2. If the read fails, refuse: exit 1 with the message below plus a line saying the working-tree
   status could not be read. Fail closed.

3. If the output is non-empty, refuse: exit 1 and print to stderr

   ```
   pre-push: the suite tests this checkout's working tree, which has changes not in the pushed commit:
     <porcelain line>
     ...
   Commit them, or set them aside under a unique name and push again:
     git stash push -u -m pre-push-<sha7>
     <re-run the push>
     git stash pop "$(git stash list --format='%gd %s' | awk '/ pre-push-<sha7>$/{print $1; exit}')"
   ```

   `<sha7>` is `tree_head`'s short form, filled in by the hook. The stash stack is shared by
   the main checkout and every worktree, and concurrent sessions push to it, so a bare
   `git stash pop` can restore another session's entry. The pop line resolves the entry by its
   unique message at the moment it runs (measured 2026-10-25 in a scratch repo with three
   stashes, the tagged one in the middle: exactly the tagged entry was popped, the other two
   remained).

   At most 20 porcelain lines are printed; beyond that, one `  … and N more` line.

4. Otherwise fall through to `unset` and `make` unchanged.

**Order:** the wrong-tree check runs first. A push from the wrong checkout is already explained
by that refusal; reporting the other checkout's dirtiness would only confuse the remedy.

**Scope of the trigger:** the check only runs when the suite would run. A push whose every path
is inert exits 0 before it, so docs pushes to master are unaffected by a dirty tree.

## Testing

`tests/scripts/pre_push.bats`, reusing its fixture repo (`setup()`), `_commit_file`,
`_write_make_mock` and `_run_pre_push`. Every case pushes to a feature ref, per the file's
existing convention. Each refusal case asserts `make` was never called (no `MOCK_CALLS_FILE`
line).

| Case                               | Setup                                                                                         | Expect                                                                      |
| ---------------------------------- | --------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| modified tracked file              | commit `a.sh`, then edit it uncommitted                                                       | exit 1, message names ` M a.sh` and `pre-push-<HEAD sha7>`, no `make`                                  |
| staged-only change                 | edit and `git add`, no commit                                                                 | exit 1, path printed, no `make`                                             |
| untracked file                     | create `tests/new.bats`, not added                                                            | exit 1, `?? tests/new.bats` printed, no `make`                              |
| ignored file                       | `.gitignore` lists `cov/`, create `cov/x`                                                     | exit 0, `make test` called                                                  |
| clean tree                         | committed, nothing else                                                                       | exit 0, `make test` called (positive control; existing cases also cover it) |
| inert push, dirty tree             | push only a `.md` change, with an uncommitted `a.sh` edit                                     | exit 0, no `make`, no dirty-tree message                                    |
| worktree push, dirty main checkout | fixture worktree at the pushed commit, clean; main checkout dirty; hook run from the worktree | exit 0, `make -C <worktree> test` called                                    |
| status read fails                  | corrupt the fixture's `.git/index` (`printf x > .git/index`) after committing                 | exit 1, "could not read" line, no `make`                                    |
| cap                                | 25 untracked files                                                                            | exactly 20 porcelain lines, then `… and 5 more`                             |

The status-failure case uses a corrupted index rather than a production seam. Measured
2026-10-25 in a scratch repo of the fixture's shape (one commit, `printf x > .git/index`):
`git rev-parse --verify 'HEAD^{commit}'` exits 0 and `git status --porcelain` exits 128
(`fatal: .git/index: index file smaller than expected`), so the wrong-tree check passes and
the new branch is the one reached.

## Docs

- `CLAUDE.md`, Testing, the pre-push bullet list: one bullet stating the refusal and the stash
  remedy, with a pointer to the knowledge entry.
- `ai-config/docs/knowledge/dotfiles-bats-test-infrastructure.md` § `Testing: pre-commit and
pre-push hooks`: the mechanism, the order relative to the wrong-tree check, and why untracked
  files count.
- `docs/superpowers/README.md`: remove the P2 Backlog row; add the spec and plan rows.

## Requirements

- **R1.** When the suite would run and every pushed ref is at `REPO_ROOT`'s `HEAD`, the hook runs `git --no-optional-locks status --porcelain --untracked-files=all` in `REPO_ROOT` with `GIT_DIR`, `GIT_WORK_TREE`, `GIT_COMMON_DIR` and `GIT_INDEX_FILE` removed from its environment.
- **R2.** A non-empty status output makes the hook exit 1 before `make` is called, printing the porcelain lines and the commit-or-stash remedy to stderr; the remedy's stash and pop lines both name `pre-push-<sha7>`, where `<sha7>` is the first 7 characters of `REPO_ROOT`'s `HEAD`, and no remedy line is a bare `git stash pop`.
- **R3.** A failed status read makes the hook exit 1 before `make` is called, with a line saying the working-tree status could not be read.
- **R4.** At most 20 porcelain lines are printed; any remainder is reported as one `… and N more` line.
- **R5.** The dirty-tree check runs after the wrong-tree refusal and after the inert early exit, so neither of those outcomes changes.
- **R6.** Untracked files that are not ignored count as changes; ignored files do not.
- **R7.** `tests/scripts/pre_push.bats` gains the nine cases in the Testing table.
- **V1.** In a fresh worktree of the branch, run `make test`, then `git status --porcelain`; the output is empty (else the suite refuses its own next push). Record both in the PR body.
- **V2.** Before merge, from a feature worktree with an uncommitted tracked edit, push the branch with the branch's own hook (`git -c core.hooksPath=<worktree>/scripts push`); it is refused with the R2 message. After running the printed stash line, the same push runs the suite, and the printed pop line restores the edit. Record both outputs in the PR body.
- **N1.** The hook does not change what the suite runs against: no `git archive`, no temporary checkout, no switching.
- **N2.** The hook never modifies the working tree, the index or the stash; it never stashes on the operator's behalf.
- **N3.** The inert set, the master guard, the budget check and the wrong-tree refusal are unchanged.
