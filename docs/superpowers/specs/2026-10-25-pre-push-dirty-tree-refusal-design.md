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

**The trade this design makes.** It removes the false green and does not remove the false red:
it widens it. Today a dirty tree blocks a push only when the edit fails the suite; with this
check any dirty tree blocks every push that would run the suite, pass or fail. In exchange the
verdict, when the suite runs, is always the pushed commit's. The one design that removes both
directions (test the pushed commit from a clean export) was declined by the operator on
2026-10-22 and 2026-10-25. How often a dirty tree has actually produced a false green is
unmeasured; the operator accepted proceeding without that measurement (Multi-Lens Review,
Goal-Fit and Ergonomics assumptions).

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

**No stash in the remedy.** The stash stack is shared by the main checkout and every worktree,
and `core.md` git-workflow-018 tells every session to drop stashes that look abandoned at
session start and end. Work parked there for the length of a suite run can be dropped by a
peer's sweep, and a per-commit tag cannot tell two worktrees at the same `HEAD` apart. The
remedy therefore never routes work through the stash.

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
   If they belong in this push: commit them, then push again.
   If they belong nowhere: delete them, or move them out of the repository.
   To keep them where they are, push from a clean checkout of the pushed commit:
     d="$(mktemp -d)" && git worktree add --detach "${d}" <sha>
     git -C "${d}" push <remote> <src>:<remote_ref>
     git worktree remove "${d}"
   ```

   `<sha>` is `tree_head` in full; there is one `push` line per pushed ref, built exactly as
   the wrong-tree remedy builds its lines (`<remote>` only when `$1` is a configured remote
   name, `<src>` the `local_ref` when it starts with `refs/`, else the full `local_sha`). The
   wrong-tree check has already established that every pushed ref is at `tree_head`, so one
   worktree serves all of them. In that worktree `HEAD` is the pushed commit and the tree is
   clean, so the hook's wrong-tree and dirty-tree checks both pass there and the suite tests
   exactly what is pushed. Nothing is placed in shared state a peer can remove.

   The delete-or-move line exists so the easiest way past the refusal is not committing a
   stray file into the PR.

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
| modified tracked file              | commit `a.sh`, then edit it uncommitted                                                       | exit 1, message names ` M a.sh`, the three remedy lines with the full `HEAD` sha and the pushed ref, and no line containing `git stash`; no `make` |
| staged-only change                 | edit and `git add`, no commit                                                                 | exit 1, path printed, no `make`                                             |
| untracked file                     | create `tests/new.bats`, not added                                                            | exit 1, `?? tests/new.bats` printed, no `make`                              |
| ignored file                       | `.gitignore` lists `cov/`, create `cov/x`                                                     | exit 0, `make test` called                                                  |
| clean tree                         | committed, nothing else                                                                       | exit 0, `make test` called (positive control; existing cases also cover it) |
| inert push, dirty tree             | push only a `.md` change, with an uncommitted `a.sh` edit                                     | exit 0, no `make`, no dirty-tree message                                    |
| worktree push, dirty main checkout | fixture worktree at the pushed commit, clean; main checkout dirty; hook run from the worktree | exit 0, `make -C <worktree> test` called                                    |
| status read fails                  | corrupt the fixture's `.git/index` (`printf x > .git/index`) after committing                 | exit 1, "could not read" line, no `make`                                    |
| cap                                | 25 untracked files                                                                            | exactly 20 porcelain lines, then `… and 5 more`                             |
| decoy `GIT_DIR`                    | main checkout at commit A, dirty; linked worktree at commit B (B changes a tracked file), clean; hook run with cwd in the worktree and `GIT_DIR=<main>/.git` exported, bypassing `_run_pre_push`'s unset | exit 0, `make -C <worktree> test` called (without the `env -u` strip, status reads main's index against the worktree's files and refuses) |
| remedy works                       | dirty fixture checkout refused; then run the printed `worktree add` line and the hook from that worktree with the same ref line | second run exits 0 and calls `make -C <temp worktree> test`                 |

The status-failure case uses a corrupted index rather than a production seam. Measured
2026-10-25 in a scratch repo of the fixture's shape (one commit, `printf x > .git/index`):
`git rev-parse --verify 'HEAD^{commit}'` exits 0 and `git status --porcelain` exits 128
(`fatal: .git/index: index file smaller than expected`), so the wrong-tree check passes and
the new branch is the one reached.

## Docs

- `CLAUDE.md`, Testing, the pre-push bullet list: one bullet stating the refusal and the
  clean-worktree remedy, with a pointer to the knowledge entry.
- `ai-config/docs/knowledge/dotfiles-bats-test-infrastructure.md` § `Testing: pre-commit and
pre-push hooks`: the mechanism, the order relative to the wrong-tree check, and why untracked
  files count.
- `docs/superpowers/README.md`: remove the P2 Backlog row; add the spec and plan rows.

## Requirements

- **R1.** When the suite would run and every pushed ref is at `REPO_ROOT`'s `HEAD`, the hook runs `git --no-optional-locks status --porcelain --untracked-files=all` in `REPO_ROOT` with `GIT_DIR`, `GIT_WORK_TREE`, `GIT_COMMON_DIR` and `GIT_INDEX_FILE` removed from its environment.
- **R2.** A non-empty status output makes the hook exit 1 before `make` is called, printing to stderr the porcelain lines and a remedy with three options: commit; delete or move out of the repository; or push from a detached worktree at `REPO_ROOT`'s full `HEAD` sha, with one literal `git -C "${d}" push` line per pushed ref. No remedy line names `git stash`.
- **R3.** A failed status read makes the hook exit 1 before `make` is called, with a line saying the working-tree status could not be read.
- **R4.** At most 20 porcelain lines are printed; any remainder is reported as one `… and N more` line.
- **R5.** The dirty-tree check runs after the wrong-tree refusal and after the inert early exit, so neither of those outcomes changes.
- **R6.** Untracked files that are not ignored count as changes; ignored files do not.
- **R7.** `tests/scripts/pre_push.bats` gains the eleven cases in the Testing table.
- **V1.** In a fresh worktree of the branch, run `make test`, `make bash-coverage`, `make -C powershell test` and the `dod_log.py` record and finalize steps of the Phase 3 chain, then `git status --porcelain --untracked-files=all`; the output is empty (else the gate chain refuses its own push). Record the commands and the empty output in the PR body.
- **V2.** Before merge, from a feature worktree with an uncommitted tracked edit, push the branch with the branch's own hook (`git -c core.hooksPath=<worktree>/scripts push`); it is refused with the R2 message. Running the three printed remedy lines pushes the branch with the suite run in the temporary worktree, and the edit is still present, unchanged, in the feature worktree afterwards. Record both outputs in the PR body.
- **N1.** The hook itself does not change what the suite runs against: it creates no `git archive`, no temporary checkout and no switch. (The remedy's worktree is created by the operator, not the hook.)
- **N2.** The hook never modifies the working tree, the index or the stash, and never runs the remedy on the operator's behalf.
- **N3.** The inert set, the master guard, the budget check and the wrong-tree refusal are unchanged.

## Multi-Lens Review

Reviewed at commit: `25cb6760` (Step 7 self-review commit, before Step 8 dispatch)

### Goal-Fit

Finding: (1) The Problem section overclaims. The check removes false greens but makes false reds worse: today a half-finished edit blocks a push only when it fails the suite, and under the check any dirty tree blocks every push that runs the suite. The honest trade is that the hook fails closed on every dirty push in exchange for removing the false-green CI round trip. (2) The stash remedy parks uncommitted work in the stash stack, which every worktree shares, and `core.md` git-workflow-018 tells peer sessions to drop stashes that look abandoned at session start and end. A `pre-push-<sha7>` entry sitting there through a multi-minute suite run can be dropped by a peer's sweep. The awk resolver fixes popping the wrong entry; it does nothing about the entry being deleted. (3) The reads-it test passes: the refusal changes a decision (exit 1 before `make`). (4) Of the nine cases, five expect refusal and four expect a pass. A status read that always returned empty, or always returned non-empty, would fail some of them, so the cases discriminate.
Assumption: false greens caused by a dirty tree happen often enough to justify a hard refusal. Confirm or refute from the CI history: in the `test`-job failures among the last 200 `ci.yml` runs (about 14 branches), check whether the next commit only added content the pusher already had locally.
Disposition: Addressed — (1) Problem states the trade: false green removed, false red widened. (2) Stash removed from the remedy; a clean detached worktree replaces it. Assumption: Accepted, reason: operator accepted proceeding without measuring false-green frequency (2026-10-25).
### Ergonomics

Finding: (1) The remedy makes committing junk the easiest way past the refusal: "commit them" is one command, while the stash route is three plus a hand re-run. The trigger also fires on stray untracked files the suite never reads. The message needs a delete-or-move option for files that do not belong in the commit, and should print the literal push command, the way the wrong-tree remedy already does, instead of `<re-run the push>`. Measured, no defect: `make test` in a fresh clone of 25cb6760 exits 0 and leaves `git status --porcelain --untracked-files=all` empty (residue only in the ignored `.hypothesis/` and `tests/__pycache__/`). `.claude/*`, `coverage/` and `.coverage` are ignored. The pop line with no matching tag fails with rc 1 and touches nothing.
Assumption: worktrees are usually clean when a session pushes, so most refusals point at a real hazard. Unmeasured. Confirm or refute from the `git status` output in dotfiles session transcripts just before a `git push`, or from a two-week log of refusals split into suite-read paths and stray files.
Disposition: Addressed — remedy offers commit, delete-or-move, and a literal clean-worktree push (no placeholders). Assumption: Accepted, reason: operator accepted proceeding without measuring how often worktrees are dirty at push (2026-10-25).
### Risk

Finding: (1) Nothing tests R1's environment strip. Every case runs through `_run_pre_push`, which unsets the `GIT_*` variables first (`pre_push.bats:58`), so a `git status` with no `env -u` prefix passes all nine cases. Measured: with `GIT_DIR=<main>/.git`, `git -C wt status` reads the main checkout's index against wt's files, so when the two HEADs differ it would refuse a clean push. Needs a tenth case: export `GIT_DIR` naming the other checkout, put the worktree at a different commit with a clean tree, and expect exit 0. (2) `pre-push-<sha7>` is unique per commit, not per checkout. Two worktrees at the same HEAD get the same tag, and the pop line takes the newest match (measured: of two entries with the same tag, `stash@{0}` is returned).
Assumption: the full Phase 3 gate chain leaves the worktree clean under `--untracked-files=all`, not just `make test`. If any gate writes a file that is not ignored, every gated push is refused. Confirm by running `make test`, `make bash-coverage`, `cd powershell && make test` and the `dod_log.py` record and finalize steps in a fresh worktree, then `git status --porcelain --untracked-files=all`.
Disposition: Addressed — (1) tenth Testing case `decoy GIT_DIR` added (plus an eleventh, `remedy works`). (2) Stash tag removed with the stash. Assumption: Addressed — V1 widened to the gate chain (`bash-coverage`, powershell, `dod_log.py`).
### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.
