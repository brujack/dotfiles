# pre-push: test the pushed commit in a clean checkout when the working tree is dirty

- **Date:** 2026-10-25
- **Backlog row:** `docs/superpowers/README.md` P2, "`scripts/pre-push` tests uncommitted edits along with the pushed commit"
- **Operator decision (2026-10-25, first):** refuse on a dirty tree, rather than testing the pushed commit from a clean export.
- **Operator decision (2026-10-25, revised after Step 8 round 2):** when the tree is dirty, the hook tests the pushed commit in a temporary clean checkout instead of refusing (option A). This reverses N1 of `2026-10-22-pre-push-wrong-tree-refusal-design.md` for the dirty-tree case only. Neither spec recorded a reason for the earlier preference not to export; none was given when A was chosen.

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

The hazard includes untracked files, not only edits to tracked ones. `Makefile:92` builds the
bats file list with a `find tests` walk (deliberately, so new untracked `.bats` files run), so
an untracked `tests/<x>.bats` that is not ignored is run by the suite. Ignored files do not
reach the verdict this way.

Premise checked 2026-10-25 against `origin/master` a949f37a: nothing in the hook reads the
working-tree status (`grep -n 'status' scripts/pre-push` matches one comment, line 35).

**What else already catches it:** CI's `test` job, against the pushed commit. A false green
therefore cannot merge, and direct-to-master pushes never run the suite (inert paths only).
The cost of the gap is a wasted CI round trip (false green) or a blocked correct push (false
red), which is why this is P2. How often either has happened is unmeasured; the operator
accepted proceeding without that measurement.

**Why not refuse.** Step 8 round 2 reviewed a refuse-plus-remedy design and found every
finding in the remedy: printed lines sharing shell state an agent's Bash calls do not keep, a
3-minute suite under a 120 s default tool timeout, `-u`/`--force-with-lease` silently dropped,
unquoted refs pasted into a shell, an untested push line, and a "delete them" line inviting
an agent to destroy files. The remedy was a hand-run clean checkout; doing the same thing in
the hook removes the remedy and both verdict errors.

No submodules exist (`git ls-files -s | grep -c '^160000'` → 0). No `post-checkout` hook is
installed (`.git/hooks` holds `commit-msg`, `pre-commit`, `pre-push` only), so
`git worktree add` runs no repo hook.

## Design

One change in `scripts/pre-push`, after the wrong-tree refusal, replacing the final
`make -C "${REPO_ROOT}" test`. Reaching it means the suite would run and every pushed ref is at
`tree_head`, `REPO_ROOT`'s `HEAD`.

1. **Read the status** of `REPO_ROOT`, with the git environment stripped exactly as the
   `tree_head` read is:

   ```bash
   env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE \
       git -C "${REPO_ROOT}" --no-optional-locks status --porcelain --untracked-files=all
   ```

   Inside a conditional (the hook runs under `set -e`). `--no-optional-locks` keeps `git status`
   from rewriting the index's stat cache, so the hook writes nothing to the index and cannot
   contend for `index.lock` with a concurrent session.

2. **Clean (read succeeded, output empty):** unchanged path. `unset GIT_DIR …`, then
   `make -C "${REPO_ROOT}" test`.

3. **Dirty, or the read failed:** test `tree_head` in a temporary detached worktree. Print one
   line to stderr, either

   ```
   pre-push: working tree has <N> uncommitted or untracked path(s); testing <sha7> in a clean temporary checkout.
   ```

   or, for a failed read, `pre-push: could not read the working-tree status; testing <sha7> in a clean temporary checkout.`
   Then run, in a subshell so the traps and variables do not leak:

   ```bash
   (
       _tmp_root="$(mktemp -d)" || { _no_checkout; exit 1; }
       _tree="${_tmp_root}/tree"
       trap '_git_stripped worktree remove --force "${_tree}" 2>/dev/null; rm -rf "${_tmp_root}"' EXIT
       trap 'exit 130' INT TERM
       _git_stripped worktree add --quiet --detach "${_tree}" "${tree_head}" || { _no_checkout; exit 1; }
       unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE
       make -C "${_tree}" test
   )
   ```

   `_git_stripped` is `env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE git -C "${REPO_ROOT}"`.
   `_no_checkout` prints `pre-push: could not create a temporary checkout of <sha7>; push refused.`
   The hook's exit status is the subshell's: `make`'s; 1 if `mktemp` or `worktree add` failed
   (fail closed); 130 on interrupt.

   - `mktemp -d` takes no template, so it honours `TMPDIR` on GNU and BSD alike; tests point
     `TMPDIR` at `BATS_TEST_TMPDIR`.
   - The trap is installed only after `_tmp_root` is non-empty, and the worktree lives one
     level below it, so neither cleanup command can receive an empty or foreign path
     (core.md shell-010).
   - `--force` is safe: the worktree is detached, created by this run, and holds no work.
   - `worktree remove --force` deletes both the directory and its registration. The cleanup
     never runs `git worktree prune`: prune clears every stale registration in the repository,
     including other sessions', so it would act on paths this run did not create.
   - Only `kill -9` of the hook skips the trap. The leftover is one directory under `TMPDIR`
     and its registration; `git worktree list` shows it, and the operator removes it.
   - Measured 2026-10-25 on a stand-alone script, not the hook itself: a
     `( mktemp -d; trap … EXIT; trap 'exit 130' INT TERM; sleep )` subshell sent SIGINT ran its
     EXIT trap and removed the directory. The `interrupt` case measures the hook.

**Scope of the change:** the clean path, the inert early exit, the budget check, the master
guard and the wrong-tree refusal are unchanged. A dirty tree never refuses a push; only a
failure to create the temporary checkout does.

**Cost:** one `git worktree add` of the repo (seconds) on a dirty push only. The suite's own
time is unchanged. Two Step 8 lenses measured `make test` in a fresh checkout of `25cb6760` /
`8a2f55fd`: rc 0, about 2.5-3 min, `git status --porcelain --untracked-files=all` empty after.

## Testing

`tests/scripts/pre_push.bats`, reusing its fixture repo, `_commit_file`, `_write_make_mock` and
`_run_pre_push`, with `TMPDIR` exported to a directory under `BATS_TEST_TMPDIR`. The `make`
mock already records its arguments; for these cases it also records, at the moment it runs,
`git -C <dir> rev-parse HEAD` and `git -C <dir> status --porcelain` for its `-C` directory, so
a case can assert the suite ran in a clean checkout of the pushed commit.

| Case | Setup | Expect |
| ---- | ----- | ------ |
| clean tree | committed, nothing else | exit 0, `make -C <REPO_DIR> test`; no dirty line; no worktree created |
| modified tracked file | commit `a.sh`, then edit it uncommitted | exit 0; dirty line names 1 path and the sha7; `make -C <TMPDIR>/…/tree test`, where that directory was at the pushed sha with empty status; afterwards the directory is gone and `git worktree list` lists only `REPO_DIR` |
| uncommitted edit changes the verdict | committed `tests/x.bats` stub content `A`; working copy content `B`; `make` mock exits 0 only if the `-C` dir's `tests/x.bats` holds `A` | exit 0 (proves the suite saw the commit, not the edit) |
| staged-only change | edit and `git add`, no commit | temporary checkout used (as above) |
| untracked file | `tests/new.bats` created, not added | temporary checkout used; the dirty line counts 1 |
| ignored file | `.gitignore` lists `cov/`, `cov/x` created | clean path: `make -C <REPO_DIR> test` |
| suite fails in temp checkout | dirty tree, `make` mock exits 2 | exit non-zero; temp directory gone; `git worktree list` lists only `REPO_DIR` |
| status read fails | corrupt `.git/index` (`printf x > .git/index`) after committing | exit 0 with the "could not read" line; temporary checkout used |
| mktemp fails | dirty tree; `TMPDIR` names a directory that does not exist | exit 1 with the "could not create" line, `make` never called |
| worktree add fails | dirty tree; a `PATH` `git` shim that fails only `worktree add` and passes every other call to the real git | exit 1 with the "could not create" line, `make` never called, the `mktemp` directory gone |
| inert push, dirty tree | push only a `.md` change with an uncommitted `a.sh` edit | exit 0, no `make`, no dirty line |
| worktree push, dirty main checkout | fixture worktree at the pushed commit, clean; main dirty; hook run from the worktree | clean path: `make -C <worktree> test` |
| decoy `GIT_DIR` | main at A, dirty; linked worktree at B (B changes a tracked file), clean; hook run in the worktree with `GIT_DIR=<main>/.git` exported, bypassing `_run_pre_push`'s unset | clean path: `make -C <worktree> test` (without the strip, status reads main's index against the worktree's files and takes the temporary-checkout path) |
| interrupt | dirty tree; `make` mock sleeps; send SIGINT to the hook's process group | non-zero exit; temp directory gone; `git worktree list` lists only `REPO_DIR` |

The status-failure case uses a corrupted index. Measured 2026-10-25 in a scratch repo of the
fixture's shape: `git rev-parse --verify 'HEAD^{commit}'` exits 0 and `git status --porcelain`
exits 128 (`fatal: .git/index: index file smaller than expected`), so the wrong-tree check
passes and the new branch is reached. `git worktree add` reads objects, not the index, so the
temporary checkout still succeeds; if implementation measures otherwise, the expectation
becomes exit 1 with the "could not create" line and R3 is amended.

## Docs

- `CLAUDE.md`, Testing, the pre-push bullet list: one bullet stating that a dirty tree makes the
  hook test the pushed commit in a temporary clean checkout, with a pointer to the knowledge
  entry.
- `ai-config/docs/knowledge/dotfiles-bats-test-infrastructure.md` § `Testing: pre-commit and
  pre-push hooks`: the mechanism, the cleanup guarantees and their `kill -9` limit, and why
  untracked files count.
- `docs/superpowers/README.md`: remove the P2 Backlog row; add the spec and plan rows.

## Requirements

- **R1.** When the suite would run and every pushed ref is at `REPO_ROOT`'s `HEAD`, the hook runs `git --no-optional-locks status --porcelain --untracked-files=all` in `REPO_ROOT` with `GIT_DIR`, `GIT_WORK_TREE`, `GIT_COMMON_DIR` and `GIT_INDEX_FILE` removed from its environment.
- **R2.** When that read succeeds with empty output, the hook runs `make -C "${REPO_ROOT}" test` exactly as before.
- **R3.** When the output is non-empty or the read fails, the hook prints one stderr line naming the path count (or the failed read) and the 7-character `HEAD` sha, creates a detached worktree at `HEAD` under a fresh `mktemp -d` directory, runs `make -C <that worktree> test`, and exits with `make`'s status.
- **R4.** The temporary worktree's directory and its registration are removed on every exit of that step, including a failing suite and SIGINT/SIGTERM; cleanup commands only ever receive the path this run created.
- **R5.** If the temporary directory or worktree cannot be created, the hook exits 1 without running `make`, printing `pre-push: could not create a temporary checkout of <sha7>; push refused.`
- **R6.** Untracked files that are not ignored select the temporary-checkout path; ignored files do not.
- **R7.** `tests/scripts/pre_push.bats` gains the fourteen cases in the Testing table, run with `TMPDIR` under `BATS_TEST_TMPDIR`.
- **V1.** In a detached worktree under `/tmp` at the branch tip (the shape R3 creates), run the real `make test`; it exits 0. In a fresh feature worktree, after `make test`, `make bash-coverage`, `make -C powershell test` and the `dod_log.py` record and finalize steps, `git status --porcelain --untracked-files=all` is empty, so a gated push takes the clean path. Record commands and outputs in the PR body.
- **V2.** Before merge, from the feature worktree with an uncommitted tracked edit, run the branch's hook on the branch's real ref line (`printf '<ref line>' | bash scripts/pre-push origin <url>`, not `-c core.hooksPath`, which leaks `GIT_CONFIG_PARAMETERS` into the suite): it prints the dirty line, the suite runs in a `/tmp` worktree and passes, the edit is still present afterwards, and `git worktree list` shows no leftover. Record the output in the PR body.
- **N1.** The hook never modifies `REPO_ROOT`'s working tree, index or stash, and never commits, stashes or deletes on the operator's behalf.
- **N2.** A dirty tree alone never refuses a push.
- **N3.** The inert set, the master guard, the budget check and the wrong-tree refusal are unchanged; the clean path runs `make -C "${REPO_ROOT}" test` as today.

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

### Round 2 (reviewed at `8a2f55fd`, all three lenses)

Goal-Fit — Finding: (1) The printed remedy was the declined clean-export design done by hand: a temporary detached worktree, safe enough to print, is safe enough for the hook to run, and doing so also removes the false red. (2) V2's pass half ran the installed master hook, not the branch's; `-c core.hooksPath` leaks `GIT_CONFIG_PARAMETERS` into the suite. Assumption: false-green frequency (unmeasured, as round 1).
Ergonomics — Finding: (1) the remedy dropped `-u`/`--force-with-lease`, and for a `HEAD` local ref could not keep `-u`; (2) the three lines share `d`, and the 2.5-3 min suite exceeds the 120 s default Bash timeout; (3) no case ran the printed push line; (4) `worktree remove` refuses untracked residue. Assumption: sessions run the remedy as one shell unit.
Risk — Finding: (1) per-call Bash loses `d`, so the push runs from the dirty tree and the worktree leaks; (2) "delete them" invites destructive agent action (behavior-004); (3) dropped flags; (4) no test ran the printed push line; (5) unquoted refs in pasted lines. Assumption: refused sessions follow the remedy rather than `--no-verify`.
Disposition: Addressed — operator chose option A (2026-10-25): the hook tests the pushed commit in a temporary clean checkout instead of refusing, so the printed remedy and every finding on it are gone; V2 now runs the branch's hook directly with no `core.hooksPath`. The false-green-frequency assumption stays Accepted (round 1). The two remedy-behaviour assumptions no longer apply.
