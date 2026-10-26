# pre-push: test the pushed commit in a clean checkout when the working tree is dirty

- **Date:** 2026-10-25
- **Backlog row:** `docs/superpowers/README.md` P2, "`scripts/pre-push` tests uncommitted edits along with the pushed commit"
- **Operator decision (2026-10-25, first):** refuse on a dirty tree, rather than testing the pushed commit from a clean export.
- **Operator decision (2026-10-25, revised after Step 8 round 2):** when the tree is dirty, the hook tests the pushed commit in a temporary clean checkout instead of refusing (option A). This reverses N1 of `2026-10-22-pre-push-wrong-tree-refusal-design.md` for the dirty-tree case only. Neither spec recorded a reason for the earlier preference not to export; none was given when A was chosen.
- **Operator decision (2026-10-25, after Step 8 round 3):** keep the temporary checkout for dirty trees only; do not move every suite-running push to a temporary checkout or retire the wrong-tree refusal. Lock the temporary worktree.

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

3. **Dirty, or the read failed:** test `tree_head` in a temporary detached, locked worktree.
   After creating it, print one line to stderr, either

   ```
   pre-push: working tree has <N> uncommitted or untracked path(s); testing committed <sha7> in clean checkout <path>.
   ```

   or, for a failed read, `pre-push: could not read the working-tree status; testing committed <sha7> in clean checkout <path>.`
   If `make` then exits non-zero, print a second line after the suite's output:

   ```
   pre-push: suite failed against committed <sha7> (clean checkout <path>, now removed); uncommitted changes were not tested.
   ```

   The second line exists because the first has scrolled away after about 3 minutes of suite
   output, failing paths point into a directory the trap has deleted, and the natural next
   step (`make test` in the dirty tree) tests a different state.

   The hook installs `trap 'exit 130' INT` and `trap 'exit 143' TERM` in its own shell before
   the subshell. Without them a signal to the process group kills the hook's shell at once,
   while the subshell runs its cleanup afterwards as an orphan: `git push` would return before
   cleanup ends, and the exit code would come from the signal, not the traps (round-4 Risk and
   Goal-Fit lenses, measured with a 1 s delay in the EXIT trap: the directory was still present
   when `wait` returned, 3 runs of 3). With the traps in the hook's shell, bash defers them until
   the foreground subshell finishes (0 leftovers in 15 runs, rc 143).

   Run, in a subshell so the traps and variables do not leak:

   ```bash
   (
       _tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/pre-push.XXXXXX")" || { _no_checkout; exit 1; }
       _tree="${_tmp_root}/pre-push-${tree_head:0:7}"
       trap '_git_stripped worktree remove -f -f "${_tree}" 2>/dev/null; rm -rf "${_tmp_root}"' EXIT
       trap 'exit 130' INT
       trap 'exit 143' TERM
       _git_stripped worktree add --quiet --detach \
           --lock --reason "pre-push pid $$ testing ${tree_head:0:7}" \
           "${_tree}" "${tree_head}" || { _no_checkout; exit 1; }
       <print the dirty or failed-read line>
       unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE
       make -C "${_tree}" test || { _rc=$?; <print the suite-failed line>; exit "${_rc}"; }
   )
   ```

   `_git_stripped` is `env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE git -C "${REPO_ROOT}"`.
   `_no_checkout` prints `pre-push: could not create a temporary checkout of <sha7>; push refused.`
   The hook's exit status is the subshell's: `make`'s; 1 if `mktemp` or `worktree add` failed
   (fail closed); 130 on interrupt.

   - `mktemp -d` gets an explicit template built from `${TMPDIR:-/tmp}`. Without one, BSD
     `mktemp` ignores `TMPDIR`: measured 2026-10-25 on the Studio (macOS 27.0.1),
     `TMPDIR=/tmp/probe.abxa7l mktemp -d` (with or without a trailing slash, `/usr/bin/mktemp`
     and via `bash -c`) returned `/var/folders/…/T/tmp.…`. An explicit template is honoured
     there (Backlog, "Six sites give a false reason…", measured 2026-10-21). Tests export
     `TMPDIR` under `BATS_TEST_TMPDIR`, so no seam is needed.
   - The trap is installed only after `_tmp_root` is non-empty, and the worktree lives one
     level below it, so neither cleanup command can receive an empty or foreign path
     (core.md shell-010).
   - **Lock.** Every session shares `.git/worktrees`, and core.md git-workflow-006/009/018 tell
     sessions to sweep worktrees at start and end. An unlocked detached `/tmp` worktree looks
     like residue, and a peer's `git worktree remove --force` mid-suite would turn the push red
     with no explanation. `--lock --reason` makes `git worktree list -v` show
     `locked: pre-push pid <pid> testing <sha7>`, and `remove --force` refuses it (`fatal: cannot
     remove a locked working tree`, rc 128; measured by the round-3 Ergonomics lens in a scratch
     repo). Cleanup therefore uses `remove -f -f`, which removes a locked worktree (rc 0, same
     measurement). The directory name `pre-push-<sha7>` says the same thing to anyone reading
     `/tmp`.
   - `-f -f` is safe: the worktree is detached, created and locked by this run, and holds no work.
   - `worktree remove --force` deletes both the directory and its registration. The cleanup
     never runs `git worktree prune`: prune clears every stale registration in the repository,
     including other sessions', so it would act on paths this run did not create.
   - Only `kill -9` of the hook skips the trap. The leftover is one locked directory under
     `TMPDIR` and its registration; `git worktree list -v` shows its reason, and the operator
     removes it with `git worktree remove -f -f <path>`. If the directory is later deleted (a
     reboot clearing `/tmp`), the registration stays: `git worktree prune` skips locked
     entries. `remove -f -f <path>` still clears it (rc 0 for a locked, missing directory;
     round-4 Ergonomics lens, git 2.53). A `worktree add` killed mid-write can leave a locked
     registration whose directory has no `.git` file; `remove -f -f` refuses that (rc 128),
     and `git worktree unlock <path>` then `git worktree prune` clears it.
   - Agent pushes do not hit that case routinely. Measured 2026-10-25 with a probe script
     carrying `EXIT`/`INT`/`TERM`/`HUP` traps around `sleep 300`: a Claude Code Bash call that
     exceeds its timeout is moved to the background, not killed; stopping it (`TaskStop`)
     delivered SIGTERM, the TERM trap ran, then the EXIT trap (`trapped 143`), and no `sleep`
     survived.
   - The `interrupt` cases run the hook through `_in_new_session`
     (`tests/setup_env/update_signals.bats:56`, moved to `tests/helpers/` so both files share
     it): python3 `start_new_session=True` with INT and TERM reset to their default action.
     That avoids `setsid`, which macOS does not ship (`test-macos` installs only `bash
     bats-core parallel coreutils`), and SIGINT inherited as ignored under bats.

**Scope of the change:** the clean path, the inert early exit, the budget check, the master
guard and the wrong-tree refusal are unchanged. A dirty tree never refuses a push; only a
failure to create the temporary checkout does.

**Cost:** one `git worktree add` of the repo (seconds) on a dirty push only. The suite's own
time is unchanged. Measured 2026-10-25 on `claude`: the real `make test </dev/null` in a
detached linked worktree of `origin/master` (78d34c6c) under `mktemp -d` in `/tmp`, git
environment stripped, exited 0 in 164 s with 3375 `ok` lines and no `not ok`;
`git status --porcelain --untracked-files=all` was empty afterwards, and
`git worktree remove --force` plus `rm -rf` left `git worktree list` with only the main
checkout and the feature worktree. Repeated the same day on the Studio (macOS, GNU bash
5.3.20 and GNU Make 3.81 from a bare `PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin`
over `ssh`), detached worktree of 2587aa66 under `mktemp -d /tmp/pre-push.XXXXXX`: rc 0 in
287 s, 3375 `ok`, 0 `not ok`, status empty afterwards, cleanup left only the main checkout.
Population: two machines (`claude`, the Studio), one commit each, one run each; the 7950X is
not measured.

**Retained, recorded as backlog:** the wrong-tree refusal (N3) still prints a pasteable remedy
with the defects round 2 found in the dirty-tree remedy (refs printed unquoted; a `HEAD`
local ref becomes a sha source, so a re-run push with `-u` sets no upstream). The operator
kept that refusal; this change adds a Backlog row for its remedy text.

## Testing

`tests/scripts/pre_push.bats`, reusing its fixture repo, `_commit_file`, `_write_make_mock` and
`_run_pre_push`. `setup()` exports `TMPDIR` to a directory under `BATS_TEST_TMPDIR` for the
whole file, so no case (new or existing) can create a worktree in the caller's real `TMPDIR`.
The `make`
mock already records its arguments; for these cases it also records, at the moment it runs,
`git -C <dir> rev-parse HEAD` and `git -C <dir> status --porcelain` for its `-C` directory, so
a case can assert the suite ran in a clean checkout of the pushed commit.

**Existing cases.** About 20 assertions of the form `grep -qE "^make -C .* test$"` match the
temporary directory as well as `REPO_DIR`. Every existing assertion that the suite ran is
anchored to `make -C ${REPO_DIR} test`, so a fixture that goes dirty fails loudly instead of
silently switching paths. `_budget_commit` is not changed: its fixtures are dirty
(` D CLAUDE.md`, never written to disk by design, so a failed path cannot overwrite the real
repo's copy), but no budget case reaches the suite. Measured by the round-4 Risk lens with the
status read logged at the new code's position across a full `pre_push.bats` run: 43 runs
reached the suite, all with empty status, none a budget case (every passing budget push is
inert).

**Paths.** `git worktree list` prints canonical paths, and on macOS `BATS_TEST_TMPDIR` sits
under `/var`, a symlink to `/private/var`. One helper canonicalises (`cd … && pwd -P`, as
`pre_push.bats:1266` already does) every path compared with `git worktree list` output or with
the mock's recorded `-C` directory.

| Case | Setup | Expect |
| ---- | ----- | ------ |
| clean tree | committed, nothing else | exit 0, `make -C <REPO_DIR> test`; no dirty line; no worktree created |
| modified tracked file | commit `a.sh`, then edit it uncommitted | exit 0; dirty line names 1 path, the sha7 and the path; `make -C <TMPDIR>/…/pre-push-<sha7> test`, where that directory was at the pushed sha with empty status and `git worktree list -v` (recorded by the mock) showed it locked with reason `pre-push pid <n> testing <sha7>`; afterwards the directory is gone and `git worktree list` lists only `REPO_DIR` |
| uncommitted edit changes the verdict | committed `tests/x.bats` stub content `A`; working copy content `B`; `make` mock exits 0 only if the `-C` dir's `tests/x.bats` holds `A` | exit 0, and `make -C <TMPDIR>/…/pre-push-<sha7> test` recorded (proves the suite ran, and saw the commit, not the edit) |
| staged-only change | edit and `git add`, no commit | temporary checkout used (as above) |
| untracked file | `tests/new.bats` created, not added | temporary checkout used; the dirty line counts 1 |
| ignored file | `.gitignore` listing `cov/` committed, then `cov/x` created | clean path: `make -C <REPO_DIR> test` |
| suite fails in temp checkout | dirty tree, `make` mock exits 2 | exit 2; `make -C <TMPDIR>/…/pre-push-<sha7> test` recorded; the suite-failed line printed; temp directory gone; `git worktree list` lists only `REPO_DIR` |
| status read fails | corrupt `.git/index` (`printf x > .git/index`) after committing | exit 0 with the "could not read" line; temporary checkout used |
| mktemp fails | dirty tree; `TMPDIR` names a directory that does not exist | exit 1 with the "could not create" line, `make` never called |
| worktree add fails | dirty tree; a `PATH` `git` shim that fails only `worktree add` and passes every other call to the real git | exit 1 with the "could not create" line, `make` never called, the `mktemp` directory gone |
| inert push, dirty tree | push only a `.md` change with an uncommitted `a.sh` edit | exit 0, no `make`, no dirty line |
| worktree push, dirty main checkout | fixture worktree at the pushed commit, clean; main dirty; hook run from the worktree | clean path: `make -C <worktree> test` |
| decoy `GIT_DIR` | main at A, dirty; linked worktree at B (B changes a tracked file), clean; hook run in the worktree with `GIT_DIR=<main>/.git` exported, bypassing `_run_pre_push`'s unset | clean path: `make -C <worktree> test` (without the strip, status reads main's index against the worktree's files and takes the temporary-checkout path) |
| interrupt (TERM) | dirty tree; hook run via `_in_new_session`; the `make` mock records its `-C` dir and whether it is a registered locked worktree, then sends `kill -TERM 0` to its own process group and sleeps at most 10 s | `_in_new_session` reports 143; the recorded dir was registered and locked; immediately after return the temp directory is gone and `git worktree list` lists only `REPO_DIR`; the run ends well before 10 s |
| interrupt (INT) | as above with `kill -INT 0` | reports 130; same cleanup assertions |

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
- `docs/superpowers/README.md`: remove the P2 Backlog row; add the spec and plan rows; add a
  P3 Backlog row for the wrong-tree refusal's remedy text (unquoted refs, `-u` lost for a
  `HEAD` local ref).

## Requirements

- **R1.** When the suite would run and every pushed ref is at `REPO_ROOT`'s `HEAD`, the hook runs `git --no-optional-locks status --porcelain --untracked-files=all` in `REPO_ROOT` with `GIT_DIR`, `GIT_WORK_TREE`, `GIT_COMMON_DIR` and `GIT_INDEX_FILE` removed from its environment.
- **R2.** When that read succeeds with empty output, the hook runs `make -C "${REPO_ROOT}" test` exactly as before.
- **R3.** When the output is non-empty or the read fails, the hook prints one stderr line naming the path count (or the failed read) and the 7-character `HEAD` sha, creates a detached worktree at `HEAD` named `pre-push-<sha7>` under a fresh `mktemp -d "${TMPDIR:-/tmp}/pre-push.XXXXXX"` directory, locked with reason `pre-push pid <pid> testing <sha7>`, prints the path in that line, runs `make -C <that worktree> test`, and exits with `make`'s status; when `make` fails it also prints `pre-push: suite failed against committed <sha7> (clean checkout <path>, now removed); uncommitted changes were not tested.`
- **R4.** The temporary worktree's directory and its registration are removed (`git worktree remove -f -f`, then `rm -rf` of the `mktemp` root) on every exit of that step, including a failing suite and SIGINT/SIGTERM, and finishes before the hook exits (the hook's own shell traps INT and TERM, so it waits for the subshell); cleanup commands only ever receive the path this run created, and the hook never runs `git worktree prune`.
- **R5.** If the temporary directory or worktree cannot be created, the hook exits 1 without running `make`, printing `pre-push: could not create a temporary checkout of <sha7>; push refused.`
- **R6.** Untracked files that are not ignored select the temporary-checkout path; ignored files do not.
- **R7.** `tests/scripts/pre_push.bats` gains the fifteen cases in the Testing table; `setup()` exports `TMPDIR` under `BATS_TEST_TMPDIR` for the whole file; every existing assertion that the suite ran names `make -C ${REPO_DIR} test` exactly; paths compared with `git worktree list` output are canonicalised; `_in_new_session` moves to `tests/helpers/` and `tests/setup_env/update_signals.bats` uses it from there.
- **V1.** In a detached worktree under `/tmp` at the branch tip (the shape R3 creates), run the real `make test`; it exits 0 (already measured on `origin/master` 78d34c6c; repeat at the branch tip). In a fresh feature worktree, after `make test`, `make bash-coverage`, `make -C powershell test` and the `dod_log.py` record and finalize steps, `git status --porcelain --untracked-files=all` is empty, so a gated push takes the clean path. Record commands and outputs in the PR body.
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

### Round 3 (reviewed at `78d34c6c`, all three lenses)

Goal-Fit — Finding: (1) the general mechanism serves one case; always testing in a temporary worktree would retire the status read, the clean/dirty branch and the wrong-tree refusal, whose printed remedy keeps the defects round 2 found; (2) on the gated path the tree is clean, so the new branch fires rarely. Assumption: the real suite passes in a detached `/tmp` worktree — measured true (rc 0, 164 s, 3375 ok, 0 not ok).
Ergonomics — Finding: (1) `interrupt` and `suite fails` cases pass for a null implementation; (2) peers' worktree sweeps can remove an unlocked detached `/tmp` worktree mid-suite; (3) agent Bash timeouts may leak worktrees routinely; (4) one stderr line is not enough when the suite fails. Assumption: a Bash-tool timeout delivers a catchable signal — measured: a timeout backgrounds the call, `TaskStop` sends SIGTERM and the trap runs.
Risk — Finding: (1) `_budget_commit` leaves fixtures dirty, so existing budget cases would silently take the new path under loose `make -C .* test` assertions and no `TMPDIR`; (2) `interrupt` via SIGINT cannot work under bats (SIGINT ignored on entry for background jobs); `env --default-signal` is GNU-only; (3) "uncommitted edit changes the verdict" passes if `make` never runs. Assumption: none uncertain left.
Disposition: Goal-Fit (1) Accepted, reason: operator kept dirty-only (2026-10-25); the wrong-tree remedy defects become a P3 Backlog row. Goal-Fit (2) Accepted with (1). Ergonomics (1) Addressed — both cases assert the temporary `-C` path; `interrupt` waits on a ready file and asserts a locked worktree before signalling. Ergonomics (2) Addressed — operator chose to lock the worktree (`--lock --reason`, `pre-push-<sha7>` directory, `remove -f -f`). Ergonomics (3) Addressed — refuted by measurement, recorded in Design. Ergonomics (4) Addressed — path in the first line, a suite-failed line after a failing run. Risk (1) Addressed — file-wide `TMPDIR`, `_budget_commit` writes what it stages, existing assertions anchored to `${REPO_DIR}`. Risk (2) Addressed — `interrupt` uses SIGTERM to a `setsid` process group with a bounded mock. Risk (3) Addressed — case asserts the temporary `-C` path.

### Round 4 (reviewed at `5d59c138`, all three lenses)

Goal-Fit — Finding: (1) `setsid` is absent on macOS, so the `interrupt` case errors on `test-macos`; (2) a TERM to the process group kills the hook's shell at once, so `exit 143` comes from the signal, not the trap, and the cleanup assertions race the orphaned subshell; (3) the `_budget_commit` rewrite silently reverses that helper's documented no-write safety property. Assumption: dirty-at-push frequency (Accepted, round 1).
Ergonomics — Finding: (1) bare `mktemp -d` ignores `TMPDIR` on the Studio's BSD `mktemp`, which would make the file-wide `TMPDIR` inert and the `mktemp fails` case wrong on `test-macos`; (2) `setsid` (as Goal-Fit 1); (3) `git worktree list` prints canonical paths (`/private/var` on macOS); (4) the `ignored file` case must commit `.gitignore`. Assumption: `macos-latest`'s `mktemp` matches the Studio; the explicit template makes it moot.
Risk — Finding: (1) the interrupt race (as Goal-Fit 2); trapping INT and TERM in the hook's own shell defers them until the subshell finishes (measured 0/15 leftovers); (2) `setsid`; (3) the `_budget_commit` premise is false: 0 of 43 suite-reaching runs were dirty or budget cases; (4) a `worktree add` killed mid-write can leave a locked registration `prune` never clears. Assumption: the verdict does not depend on git-ignored files in `REPO_ROOT`; V1 measured `claude` only.
Proposed revision (applied to the body above, pending operator disposition): explicit `mktemp` template; INT/TERM traps in the hook's shell; `_in_new_session` (moved to `tests/helpers/`) replaces `setsid`, with TERM and INT cases signalled from the `make` mock; canonical-path helper; `.gitignore` committed; `_budget_commit` rewrite dropped, `${REPO_DIR}` anchoring kept; `kill -9` note extended.
Disposition: Addressed — operator, 2026-10-25, as proposed. Risk assumption: Addressed — operator asked for the Studio run; recorded under Design, Cost (rc 0, 3375 ok, 0 not ok).
