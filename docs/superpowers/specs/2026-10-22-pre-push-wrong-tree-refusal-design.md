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

Once the suite will run (`needs_test=1` after the loop), **every non-deletion ref line** must
name the commit the hook's checkout has at `HEAD`. Deletion lines (`local_sha` all zeros) are
already skipped and stay skipped. A push whose every ref is inert-only exits 0 before the
check, as today, so a doc push from any checkout is unaffected.

Operator decision 2026-10-22: every ref rather than only the refs whose own diff is non-inert.
The per-ref form allows `git push origin feat docs/x` with `docs/x` elsewhere, needs per-ref
bookkeeping and a test of its own, and a tally of dotfiles session transcripts found zero
multi-ref pushes, so it would carry cost for no current user.

**Accepted limitation.** A push of two or more branches at different commits that needs the
suite can never pass; push each ref on its own. A stacked-branch push is the only legitimate
shape this refuses, and its only escape is `--no-verify`, which drops every check in the chain
(git-workflow-046). The tally found none.

### The check

After the loop, after the existing three refusals (unresolved range, CLAUDE.md budget,
direct-to-master), and only when `needs_test=1`:

1. Resolve the tested tree's commit: `git rev-parse --verify --quiet 'HEAD^{commit}'`.
2. For each non-deletion ref line, peel its `local_sha`:
   `git rev-parse --verify --quiet "${local_sha}^{commit}"`. Peeling makes an annotated tag at
   `HEAD` match. The loop records `local_ref`, `local_sha` and `remote_ref` per line for this.
3. Refuse (exit 1, before `make`) if step 1 fails, if any peel fails, or if any peeled commit
   differs from step 1's commit. All three are fail-closed.

Every git read in steps 1-2 runs inside a conditional (`if ! x="$(...)"`), so under the hook's
`set -e` a failure reaches the refusal message rather than exiting silently.

Placing it last keeps the existing refusals' messages and precedence unchanged; a push that
would already be refused for another reason reports that reason.

### The refusal message

To stderr, in the hook's existing style, one block per mismatched or unpeelable ref:

```
pre-push: the suite tests this checkout's working tree, not the pushed commit.
  <local_ref> is at <short sha>; this checkout (<path>) is at <short sha>.
Push each ref from a checkout whose HEAD is that commit:
  git push <remote> <local_ref>:<remote_ref>
```

`<remote>` is the hook's `$1`. An unresolvable `HEAD` or `local_sha` prints `unresolved` in
place of its short SHA. No worktree lookup: operator decision 2026-10-22, since it changes no
verdict and the two SHAs plus the exact command already say what to do.

### What does not change

- No `REPO_ROOT` override seam. The row suggested copying `terraform_ansible`'s
  `${REPO_ROOT:-...}`; that seam serves a different fix (choosing a tree), and a refusal
  needs none.
- The suite still runs against the working tree as it is on disk. Uncommitted edits in the
  correct checkout are still tested along with the commit; that is a separate gap (N1),
  backlogged.
- Where `HEAD` is read relative to the `unset GIT_DIR ...` line does not matter: measured by
  all three round-1 lenses, a worktree push resolves the same `HEAD` either side of it, since
  discovery from the hook's cwd finds the worktree's `.git` file. Keep git reads above the
  `unset` by convention, matching the existing range resolution.

### The fleet rule this contradicts

core.md `git-workflow-043` ends "Tests failing only in push: push from main", and its knowledge
entry (`ai-config/docs/knowledge/ai-config-standards-core.md` § git-workflow-043) gives a
`git -C /path/to/main/repo` push of the branch. After this change that push is refused in
dotfiles for any branch needing the suite, and it is exactly the push that tests the wrong
tree. Its original reason, `GIT_DIR` leaking from a worktree push into fixture-building tests,
is already handled here by the hook's `unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR
GIT_INDEX_FILE`. Operator decision 2026-10-22: amend the rule in ai-config in the same release
(V3), after messaging the ai-config session, so the always-loaded instruction stops
prescribing a push the hook refuses.

## Testing

New cases in `tests/scripts/pre_push.bats`, each building a fixture repo and feeding a
synthetic ref line:

| Case                        | Ref lines                                                          | Expect                                                         |
| --------------------------- | ------------------------------------------------------------------ | -------------------------------------------------------------- |
| mismatch refused            | non-inert change, `local_sha` = an older commit, HEAD ahead        | exit 1, message names both short SHAs, `make` never called     |
| match runs suite            | same change, `local_sha` = HEAD                                    | exit 0, `make` called once                                     |
| inert-only mismatch         | `.md`-only change, `local_sha` != HEAD                             | exit 0, no refusal text, `make` not called                     |
| tag peeled                  | annotated tag object at HEAD, non-inert change                     | exit 0, `make` called                                          |
| mixed refs refused          | non-inert ref at HEAD plus an inert ref at another commit          | exit 1, names only the ref not at HEAD                         |
| unpeelable ref              | non-inert ref whose `local_sha` is a tag object pointing at a blob | exit 1, `unresolved` in the message, `make` never called       |
| unborn HEAD                 | fixture with no commit checked out, non-inert ref                  | exit 1, `make` never called                                    |
| master refusal wins         | non-inert ref to `refs/heads/master` at a non-HEAD commit          | exit 1 with the existing direct-to-master text, not this one's |
| remedy is the exact command | mismatch                                                           | message contains the R4 command with `origin` and both refs    |

"Match runs suite" and "tag peeled" prove the check computes: a check whose `HEAD` read returns
nothing refuses both, and one that never records the ref lines passes "mismatch refused".

Existing cases, measured by two round-1 lenses on a prototype: 109 cases, 108 pass, one is
refused. It is #83, "live_paths is reset per ref" (`pre_push.bats:884`), which pushes `feat/x`
at `sha1` with `HEAD` at `sha2`. Pushing `feat/x` at `sha2` keeps its subject (the branch range
still carries `deploy.sh`, the master range stays `.md`-only).

## Requirements

- **R1.** When the suite would run, `scripts/pre-push` exits 1 without invoking `make` if any non-deletion ref line's `local_sha`, peeled to a commit, differs from the hook checkout's `HEAD` commit.
- **R2.** When the suite would run, `scripts/pre-push` exits 1 without invoking `make` if `HEAD` or any non-deletion ref's `local_sha` cannot be peeled to a commit.
- **R3.** A push whose every ref line is inert-only is never refused by the R1/R2 check, whatever commit it names.
- **R4.** The refusal names each offending `local_ref`, its short SHA (or `unresolved`), the checkout path and its `HEAD` short SHA (or `unresolved`), and prints the push command `git push <remote> <local_ref>:<remote_ref>` for it, with `<remote>` taken from the hook's first argument.
- **R5.** The R1/R2 check runs after the unresolved-range, CLAUDE.md budget and direct-to-master refusals, so each of those keeps its existing message when it also applies.
- **R6.** `tests/scripts/pre_push.bats` carries the nine cases in the Testing table.
- **V1.** `make test` exits 0 on the branch.
- **V2.** Before merge, run the branch's own hook on real pushes by passing `-c core.hooksPath=<worktree>/scripts` to git: from the feature worktree it passes; from the main checkout (on master) the same branch push is refused with the R4 message. Record both outputs in the PR body.
- **V3.** An ai-config change amending core.md `git-workflow-043` and its knowledge entry so neither prescribes pushing a branch from the main checkout is merged in the same release; the dotfiles PR body links it.
- **N1.** The hook does not change what the suite runs against: no `git archive`, no switching, no temporary checkout.
- **N2.** No `REPO_ROOT` override seam is added.
- **N3.** No existing pre_push.bats assertion is deleted or weakened; an existing case is changed only in the commit its ref line pushes or the commit its fixture has at `HEAD`.
- **N4.** ai-config's and terraform_ansible's hooks are not changed.
- **N5.** The hook does not read `git worktree list`.

## Multi-Lens Review

Reviewed at commit: `d9e42816` (Step 7 self-review commit, before Step 8 dispatch)

### Goal-Fit

Finding: Worth building at this size; a ~15-line prototype of R1 refused 1 of the 109 existing cases (not 110): #83 "live_paths is reset per ref" (`pre_push.bats:884`), fixable under N3. (1) V2 cannot produce its evidence before merge: `.git/hooks/pre-push` symlinks the main checkout's `scripts/pre-push`, which is master's, so both pushes run the old hook; run them with `git -c core.hooksPath=<worktree>/scripts push`. (2) R7 is unobservable: in a worktree-push fixture `git rev-parse HEAD` returned the same commit before and after the `unset`, because discovery from cwd finds the worktree's `.git` file. (3) R2 and R6 have no test case (unborn HEAD, unpeelable `local_sha`, a push that also hits the master refusal). (4) R5's worktree listing changes no verdict and its output is stderr only; R4's two SHAs plus path already tell the reader what to do.
Assumption: no routine workflow pushes a non-inert ref other than the issuing checkout's HEAD; settle by tallying push commands in dotfiles transcripts.
Disposition: Addressed (operator, 2026-10-22). V2 runs the branch hook via `core.hooksPath`; R7 dropped (now a convention note); unborn-HEAD, unpeelable-ref and master-precedence cases added; R5 worktree lookup cut to the exact push command (operator: "Cut to generic line"). Assumption settled by the Ergonomics lens transcript tally: zero multi-ref pushes.

### Ergonomics

Finding: (1) R1's per-ref scoping is untested: an implementation that checks every ref whenever the aggregate `needs_test=1` passes all seven cases yet refuses an inert ref at a non-HEAD commit pushed with a non-inert ref at HEAD. (2) R2/R7 as Goal-Fit. (3) Remedies are not pasteable: print the exact `git push <remote> <local_ref>:<remote_ref>` instead of `...`; drop `git switch` (contradicts git-workflow-019 and fails "already checked out"); give `git worktree add` a concrete path. (4) Breakage measured: 108/109, #83 fails; it pushes feat/x at sha1 and master at sha2, so "push its fixture's HEAD" may not keep its subject, and N3 should also allow moving the fixture's HEAD. (5) Transcript tally across dotfiles sessions: ~300 inert `HEAD:master` pushes and ~40 single-ref `push -u origin <branch>` from the branch's worktree; zero multi-ref, sha-refspec, `--tags` or `--all` pushes. Stacked multi-branch pushes are the only legitimate shape refused, and their only escape is `--no-verify`; say so.
Assumption: no uncertain assumption found (the transcript tally settles the push-shape question on current habits).
Disposition: Addressed (operator, 2026-10-22). Per-ref scoping replaced by every non-deletion ref (operator: "Every non-deletion ref"), so the mixed shape is refused and tested; remedy prints the exact push command, no `git switch`; N3 widened to allow moving a fixture's HEAD; stacked pushes stated as an accepted limitation.

### Risk

Finding: (1) V2 as Goal-Fit. (2) core.md `git-workflow-043` and its knowledge entry (`ai-config-standards-core.md:418`) tell sessions "Tests failing only in push: push from main" (`git -C /path/to/main/repo push origin branch-name`); after this change that workaround is refused for any branch needing the suite, and the 2026-09-11 incident looks like it being followed. (3) R7 as Goal-Fit. (4) 109 cases, #83 the only breakage. (5) A multi-ref remedy that replays the same push can never pass: tell the reader to push each ref alone. `git worktree list --porcelain` lists `prunable` entries, so skip them. A bare `$(git rev-parse ...)` under `set -e` exits silently: the spec should require each read inside a conditional. Checked clean: paths with spaces, worktree `GIT_DIR`, deletions, tag peel, R6 order, no R/N contradiction.
Assumption: no skill pushes a needs-suite ref from a cwd other than the branch's worktree. Checked 2026-10-22: `grep -rn 'git -C [^|]*push' ~/.claude/skills/*/SKILL.md` finds `add-claude-plugin:171` (`git -C ~/git-repos/personal/dotfiles push`), which pushes the main checkout's current branch, so HEAD equals the pushed commit and it passes. Refuted for skills; the fleet rule in (2) is the live conflict.
Disposition: Addressed (operator, 2026-10-22). git-workflow-043 amended in ai-config in the same release (V3; operator: "Amend it in ai-config now"); the remedy tells the reader to push each ref alone; the prunable-entry edge went with the worktree lookup; every git read is required inside a conditional.

### Round 2

Reviewed at commit: `c7df2897` (all three lenses re-run: the round-1 revision changed design substance). Each lens was told the round-1 record is history, not findings.

#### Goal-Fit (round 2)

Finding: (1) The "unpeelable ref" case cannot pass as written: a tag at a blob fails the budget step's `git ls-tree` (`pre-push:117`) and is refused there, so `unresolved` is never printed; R5 keeps that order. A tag at a tree passes the loop (today it runs `make`) and fails `^{commit}`; use that. `--quiet` still prints `error: ... expected commit type` on stderr. (2) V3's justification holds for dotfiles (hook `unset`) and ai-config (`Makefile` `unexport`), not terraform_ansible, whose hook strips `GIT_*` only for the `REPO_ROOT` read and whose Makefiles have no `unexport`; amending 043 fleet-wide removes a workaround that may still be needed there. "Same release" is undefined for dotfiles. Verdict count 6 refuse / 3 pass; an empty HEAD read or empty ref record fails at least two cases each.
Assumption: no fleet repo other than dotfiles still needs the 043 workaround; refuted for terraform_ansible by `grep -nE 'unexport|unset GIT_DIR'` over its Makefiles and hook at origin/master (no hit on a `test-*` path).
Disposition:

#### Ergonomics (round 2)

Finding: (1) Unpeelable case as Goal-Fit; measured a raw tree / tag-to-tree passes `ls-tree` and the diff, and fails the peel. (2) R4's command is wrong for a `local_ref` outside `refs/`: `HEAD~1:refs/heads/x` hands the hook the literal `HEAD~1`, which re-run elsewhere pushes a different commit; print `local_ref` only when it starts with `refs/`, else the full `local_sha`. The command also drops `-u` and `--force-with-lease`/`+`, so after a rebase the pasted command is rejected; add a line to re-add the original flags. (3) V3 deletes the workaround with no replacement; name it (push from the branch's own worktree; if tests fail only during push, strip `GIT_*` in that repo's hook or Makefile) and backlog terraform_ansible's missing `unexport`. (4) Testing prose inverted: an implementation recording no ref lines exits 0 and so fails "mismatch refused", not passes it.
Assumption: every suite-needing push is issued from a shell whose cwd is the branch's worktree. `finishing-a-development-branch` pushes `git push -u origin "${BRANCH}"` with no `cd`/`-C` (`SKILL.md:457`), and 12 dotfiles transcript pushes name a branch other than the recorded `gitBranch` with no `cd` (cwd may be stale). Any such push today tests the wrong tree; after this change it is refused, which is the intended behaviour but a habit change for the orchestrator.
Disposition:

#### Risk (round 2)

Finding: (1) Unpeelable case as above. (2) R1 reads the wrong HEAD when the caller exported `GIT_DIR`, and fails open. Measured: `GIT_DIR=<main>/.git/worktrees/wt` with cwd=main, push `feat`: hook HEAD is `feat` (match) while `REPO_ROOT` is main, so master's tree is tested; the reverse gives a false refusal. Read step 1 as `env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE git -C "${REPO_ROOT}" rev-parse --verify --quiet 'HEAD^{commit}'` (shell-007), and add a decoy-`GIT_DIR` case. (3) A second copy of the workaround is at `ai-config/docs/knowledge/ai-config-bats-testing-pitfalls.md:104`; V3 misses it. (4) Every-ref matching also refuses `--follow-tags` or a named tag at another commit; dotfiles has 0 tags and `push.followTags` unset, so say so rather than claim stacked pushes are the only shape. (5) `$1` is the literal URL when a push names a URL; an https URL with a token would be echoed into stderr and transcripts.
Assumption: dotfiles pushes never run with a caller-exported `GIT_DIR` that disagrees with the hook's cwd; finding 2 removes the dependence by reading HEAD from `REPO_ROOT` with the environment stripped.
Disposition:

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.
