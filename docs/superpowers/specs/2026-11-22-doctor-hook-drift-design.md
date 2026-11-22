# Doctor check: installed hooks that drift from the committed script

**Date:** 2026-11-22
**Status:** Draft
**Source:** security audit 2026-11-16, finding F7 (ai-config
`docs/knowledge/dotfiles-security-audit-2026-11-16.md`).

## Problem

dotfiles, etch-config and math install their hooks as symlinks into the main checkout's
working tree (`ln -sf` in `install-hooks`). The hook that runs, for the main checkout and
every linked worktree, is therefore whatever that working tree holds. An uncommitted edit to
`scripts/pre-push` in the main checkout, or a branch checked out there that changes it,
changes the gate for every push from every worktree.

`_git_hooks_identity` (`lib/git_hooks.sh`, ADR-0061) reports such a symlink as `match`
because it checks only that the target is a tracked source candidate. A copy-installed hook
is judged against the working-tree file (`cmp -s`), so a copy taken from a dirty working
tree also reads as `match`, while a correct copy beside a dirty working tree reads as
`stale`.

This is an integrity gap, not a confidentiality one. Any process that can edit the main
checkout can equally write `.git/hooks` directly, so nothing here raises the bar against an
attacker. What it fixes is a gate that changes silently.

### Measured

- Hook shape, all nine `HOOK_EXPECTED_REPOS` on `claude`, 2026-11-22: symlinks in dotfiles,
  etch-config and math; copies in the other six (state-ledger's pre-commit is a generated
  pre-commit shim with no tracked candidate).
- A dirty-tree episode, observed: on 2026-11-22 at 17:06 a review subagent's probe ran in
  the dotfiles main checkout after a failed `cd` and replaced `scripts/pre-push` with a
  two-line `echo hi` stub. Every dotfiles hook symlinks to that file, so for about two
  minutes every push from every worktree would have skipped the suite. It was found because
  the subagent reported it, not by any check; the file was restored from HEAD at 17:07, and
  GitHub's event log shows no push in that window.
- Branch episodes: the dotfiles main checkout's reflog (53 days, 2026-09-30 to 2026-11-22)
  holds 42 `checkout: moving` lines; 4 name a ref other than master, making two off-master
  episodes (47 seconds on `origin/fix/nvidia-driver-open` on 2026-10-12; 3h41m detached at
  `origin/master` on 2026-10-03). In both, `git rev-parse <ref>:scripts/<hook>` equals
  master's blob at the time for all three hooks, so neither changed the gate. Population:
  one repo's main checkout on one machine.
- Predicted effect on today's fleet: for each of the 26 hooks with a tracked candidate (all
  27 mandated hooks minus state-ledger's generated pre-commit), the installed content hashes
  to the candidate's blob on the local default branch, and every main checkout is clean and
  on that branch. The change below therefore reports `match` for all of them. Population:
  `claude` only.
- How often doctor runs: the operator runs `setup_env.sh -t doctor` after setup and
  updates only. This check is therefore a diagnostic for when something already looks
  wrong, not a monitor; it cannot be relied on to catch a two-minute window.

## Design

### 1. `_git_hooks_identity` judges content against the default branch's blob

The reference is the candidate's blob on the repo's local default branch:
`git rev-parse --verify -q refs/heads/<default>:<candidate>`, where `<default>` is `main`
when `refs/heads/main` exists and `refs/heads/master` does not, else `master`. The installed
content is hashed with `git hash-object --path=<candidate> <file>`, so the candidate's
attributes apply (an `eol=crlf` checkout compares equal to its LF blob). A symlink is hashed
through to its target. All git calls use the
`env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE` wrapper the function
already uses. No temporary file, no network, no `origin` ref.

Comparing against the default branch rather than HEAD means a branch checked out in the main
tree warns only when it actually changes the hook script, which was never the case in the
measured episodes.

| Installed hook       | Content vs default-branch blob                                     | Before             | After                                                       |
| -------------------- | ------------------------------------------------------------------ | ------------------ | ----------------------------------------------------------- |
| symlink to candidate | equal                                                              | `match`            | `match`                                                     |
| symlink to candidate | different                                                          | `match`            | `drift` (rc 1), reason `<candidate> differs from <default>` |
| symlink to candidate | candidate absent from `<default>`                                  | `match`            | `drift` (rc 1), reason `<candidate> is not on <default>`    |
| copy                 | equal to some candidate's blob                                     | `match` or `stale` | `match`                                                     |
| copy                 | equal to no candidate's blob                                       | `match` or `stale` | `stale`                                                     |
| any                  | a hash call fails or prints nothing, or no default branch resolves | n/a                | `error` (rc 2), reason naming the failed call               |

A copy has no `drift` row. Its content is fixed at install time, so the remedy is always a
reinstall, which is exactly what `stale` and its existing remedy already say. A symlink to a
candidate whose file is missing stays `stale`; symlinks into worktrees or outside the repo
keep `worktree` and `foreign`; the generated-shim path is unchanged. Candidates are still
filtered by hook name first, so a pre-commit copied from a pre-push script still fails
(ADR-0061's matching-by-name rule).

### 2. Doctor arm

`_doctor_check_git_hooks` (`lib/helpers.sh`) gains one arm:

- `drift` gives `doctor_warn "<repo>" "<hook> runs <reason> in the main checkout — remedy: inspect with git -C <dir> diff <default> -- <candidate>, then return <dir> to a clean <default> once no session owns the change"`.

WARN, not FAIL: the hook is still the repo's own script and the state is usually
short-lived. The remedy names no `commit` and no `switch`: committing on the main checkout's
default branch is a direct-to-master commit, and switching could move another session's
tree. The existing `stale` arm and its remedy are unchanged. The fail-closed `*)` arm is
unchanged, so any other identity word still FAILs.

### 3. Tests and documentation

- `tests/setup_env/git_hooks_identity.bats`: one fixture-repo case per row of the table in
  section 1, including a failed hash call; a mutation control that compares against the
  working-tree file instead of the default-branch blob must turn the symlink `drift` case red.
- `tests/setup_env/doctor_git_hooks.bats`: the `drift` message with its remedy text.
- ADR-0061 gets a dated amendment section recording the default-branch blob comparison and
  the `drift` word; its decision (doctor judges hook identity, read-only) is unchanged.

### Alternatives considered

- **A self-check inside `scripts/pre-push`**, comparing its own bytes with the default
  branch's blob on every push. Rejected: the file doing the checking is the file that
  drifted. A modified hook script can delete or bypass its own check, and the measured
  episode replaced the whole file. A check is only meaningful outside the thing it checks.
- **Compare against HEAD and warn separately when the main checkout is off its default
  branch.** Rejected in review: both measured branch episodes left the hook bytes unchanged,
  so a branch-name test warns about states that never change the gate.
- **Install copies everywhere.** Not chosen: it reverses the symlink direction ADR-0016
  records and brings back copies that go stale until reinstalled.

## Requirements

- **R1.** `_git_hooks_identity` resolves the default branch as `main` when `refs/heads/main` exists and `refs/heads/master` does not, else `master`, and compares installed content against `git rev-parse --verify -q refs/heads/<default>:<candidate>`.
- **R2.** `_git_hooks_identity` hashes installed content with `git hash-object --path=<candidate> <file>`, following a symlink to its target.
- **R3.** `_git_hooks_identity` prints `match` and returns 0 for a symlink to a source candidate whose content hash equals the candidate's default-branch blob, whatever branch the repo's HEAD is on.
- **R4.** `_git_hooks_identity` prints `drift`, a TAB and `<candidate> differs from <default>`, and returns 1, for a symlink to a source candidate whose content hash differs from the candidate's default-branch blob.
- **R5.** `_git_hooks_identity` prints `drift`, a TAB and `<candidate> is not on <default>`, and returns 1, for a symlink to a source candidate that has no blob on the default branch.
- **R6.** `_git_hooks_identity` prints `match` and returns 0 for a regular-file hook whose content hash equals the default-branch blob of a source candidate, whatever the working-tree file holds.
- **R7.** `_git_hooks_identity` prints `stale` and returns 1 for a regular-file hook whose content hash equals no source candidate's default-branch blob.
- **R8.** `_git_hooks_identity` prints `error`, a TAB and a reason naming the failed call, and returns 2, when `git hash-object` exits non-zero or prints an empty hash, when `git rev-parse --verify -q` for a default-branch blob exits with a status other than 0 or 1 (1 means the blob is missing), or when neither `refs/heads/master` nor `refs/heads/main` exists; an empty or failed hash is never compared.
- **R9.** `_doctor_check_git_hooks` calls `doctor_warn "<repo>" "<hook> runs <reason> in the main checkout — remedy: inspect with git -C <dir> diff <default> -- <candidate>, then return <dir> to a clean <default> once no session owns the change"` for `drift`.
- **R10.** Every git call added to `lib/git_hooks.sh` or `lib/helpers.sh` runs under `env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE`.
- **R11.** `tests/setup_env/git_hooks_identity.bats` has at least one case for each of R3 to R8, and `tests/setup_env/doctor_git_hooks.bats` has a case for R9.
- **R12.** `docs/adr/0061-doctor-hook-identity-and-ggshield-probe.md` gains an amendment section dated 2026-11-22 naming the default-branch blob comparison and the `drift` word.
- **V1.** A mutation that compares against the working-tree file instead of the default-branch blob turns at least the R4 case red.
- **V2.** `./setup_env.sh -t doctor` on `claude` after the change reports no `drift` line and no new `stale` line for any of the nine repos (prediction from the Measured section).
- **V3.** In a scratch clone whose hooks are installed as symlinks by its own `make install-hooks`, an uncommitted edit to `scripts/pre-push` makes the doctor arm print the R9 warning for that clone.
- **V4.** In a scratch clone with copy-installed hooks, a hook copied from a non-default branch whose script differs makes the doctor arm report that hook as stale.
- **N1.** No repo's `install-hooks` target changes, and doctor never reinstalls, copies, relinks, restores, commits or switches anything.
- **N2.** No added code reads a remote ref (`origin/*`) or performs a fetch or other network call.
- **N3.** No identity word other than `match`, `stale` and the new `drift` changes when it is printed; `worktree`, `foreign`, `generated`, `generated-broken` and `generated-unverified` are printed for exactly the inputs they were before.

## Multi-Lens Review

Reviewed at commit: `531c10f4` (round 1, first draft; the body above is the revision)

### Goal-Fit

Finding: `off-branch` keyed on the branch name, not the hook's content; both measured branch
episodes had byte-identical hooks, so both would have been false positives. Proposed
comparing against the default branch's blob instead. Also proposed a `scripts/pre-push`
self-check as a simpler, stronger home, and noted the doctor-only consumer changes a
decision only if doctor runs during a drift window.
Assumption: doctor runs often enough to catch drift; settled by asking the operator.
Disposition: Addressed — default-branch blob comparison, `off-branch` dropped; the pre-push
self-check is rejected under Alternatives considered (the drifted file would check itself).
Operator answered that doctor runs after setup and updates only, so the spec now calls the
check a diagnostic, not a monitor.

### Ergonomics

Finding: the remedy "commit, stash or discard" was wrong for copy-installed hooks (six of
nine repos) and "commit" on the main checkout is a direct-to-master commit; `switch` could
move another session's tree; the branch-name test produced false positives; V2 passes
vacuously when the arm emits nothing.
Assumption: a dirty hook script in a main checkout is rare; settled by sampling
`git status --porcelain -- 'scripts/*'` across the nine main checkouts.
Disposition: Addressed — copies report `stale` with the existing reinstall remedy; the
`drift` remedy inspects and names no commit or switch; V4 adds a copy-side positive check.
A real dirty episode was observed during this review (Measured section).

### Risk

Finding: a failed `hash-object` or `rev-parse` prints nothing, and two empty strings compare
equal, so a broken implementation lands on `match`; N3 contradicted R1–R4; `--no-filters`
reports false drift under an `eol=crlf` attribute (latent: no fleet repo sets it). The
lens's own probe wrote into the dotfiles main checkout after a failed `cd`, the episode
recorded under Measured.
Assumption: no uncertain assumption found (weakest: no fleet checkout writes CRLF into a
hook script, checkable on the Windows box with `git check-attr eol -- scripts/pre-push`).
Disposition: Addressed — R8 makes a failed or empty hash an `error`; N3 rewritten;
`hash-object --path=<candidate>` replaces `--no-filters`.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.
