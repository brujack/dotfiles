# Doctor check: installed hooks that drift from the committed script

**Date:** 2026-11-22
**Status:** Draft
**Source:** security audit 2026-11-16, finding F7 (ai-config
`docs/knowledge/dotfiles-security-audit-2026-11-16.md`).

## Problem

dotfiles, etch-config and math install their hooks as symlinks into the main checkout's
working tree (`ln -sf` in `install-hooks`). The hook that runs, for the main checkout and
every linked worktree, is therefore whatever that working tree holds: an uncommitted edit
to `scripts/pre-push`, or a feature branch checked out in the main tree, changes the gate
for every push from every worktree.

`_git_hooks_identity` (`lib/git_hooks.sh`, ADR-0061) reports such a symlink as `match`
because it checks only that the target is a tracked source candidate. A copy-installed hook
is judged the same way against the working-tree file (`cmp -s`), so a copy taken from a
dirty working tree also reads as `match`, and a clean copy beside a dirty working tree reads
as `stale`.

This is an integrity gap, not a confidentiality one. Any process that can edit the main
checkout can equally write `.git/hooks` directly, so nothing here raises the bar against
an attacker. What it fixes is a gate that changes silently.

### Measured

- Hook shape, all nine `HOOK_EXPECTED_REPOS` on `claude`, 2026-11-22: symlinks in dotfiles,
  etch-config and math; copies in the other six (state-ledger's pre-commit is a generated
  pre-commit shim with no tracked candidate).
- How often the hazard occurs: the dotfiles main checkout's reflog (53 days, 2026-09-30 to
  2026-11-22) holds 42 `checkout: moving` lines; 4 of them name a ref other than master, making two
  off-master episodes. The main checkout
  sat on `origin/fix/nvidia-driver-open` for 47 seconds on 2026-10-12 and detached at
  `origin/master` for 3h41m on 2026-10-03. Population: one repo's main checkout on one
  machine. Dirty-tree episodes leave no reflog line and are not measured.
- Predicted effect on today's fleet: for each of the 26 hooks with a tracked candidate
  (all 27 mandated hooks minus state-ledger's generated pre-commit), the installed content's `git hash-object --no-filters` equals
  `git rev-parse HEAD:<candidate>`, and every main checkout is clean and on `master` or
  `main`. The change below therefore reports `match` for all of them: no new warning on
  `claude` today. Population: `claude` only.

## Design

### 1. `_git_hooks_identity` judges content against HEAD

For an installed hook that is a symlink to a source candidate, or a regular file, compare
its bytes with the candidate's committed blob:
`git hash-object --no-filters <file>` against `git rev-parse --verify -q HEAD:<candidate>`,
both through the `env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE`
wrapper the function already uses. No temporary file, no network, no `origin` ref.

| Installed hook       | Content                                                   | Before             | After                                                        |
| -------------------- | --------------------------------------------------------- | ------------------ | ------------------------------------------------------------ |
| symlink to candidate | equals HEAD blob, main HEAD on `master` or `main`         | `match`            | `match`                                                      |
| symlink to candidate | equals HEAD blob, main HEAD on another branch or detached | `match`            | `off-branch` (rc 1), reason `<branch or detached HEAD>`      |
| symlink to candidate | differs from HEAD blob                                    | `match`            | `drift` (rc 1), reason `uncommitted changes in <candidate>`  |
| symlink to candidate | candidate absent from HEAD                                | `match`            | `drift` (rc 1), reason `<candidate> not committed at HEAD`   |
| copy                 | equals some candidate's HEAD blob                         | `match` or `stale` | `match`                                                      |
| copy                 | equals a candidate's working file, not its HEAD blob      | `match`            | `drift` (rc 1), reason `copied from uncommitted <candidate>` |
| copy                 | equals neither                                            | `stale`            | `stale`                                                      |

A copy has no `off-branch` row: its content is fixed at install time, so the main
checkout's branch does not change what runs. A symlink to a candidate whose file is
missing stays `stale`, and symlinks into worktrees or outside the repo keep `worktree` and
`foreign`. The generated-shim path is unchanged.

The default-branch test uses the same `master|main` convention as the doctor's existing
`stale` arm, read with `git symbolic-ref --short -q HEAD`.

### 2. Doctor arm

`_doctor_check_git_hooks` (`lib/helpers.sh`) gains two arms, both `doctor_warn`:

- `drift`: `<hook> runs <reason> from the main checkout — remedy: commit, stash or discard the change in <dir>`
- `off-branch`: `<hook> runs <reason>'s <hook> script, not the default branch's — remedy: git -C <dir> switch <default>`,
  where `<default>` is `main` when a local `main` branch exists and the repo has no local
  `master`, else `master`.

WARN, not FAIL: the hook is still the repo's own script, the state is usually short-lived,
and the existing off-branch `stale` message is a WARN. The fail-closed `*)` arm is unchanged,
so any other identity word still FAILs.

### 3. Tests and documentation

- `tests/setup_env/git_hooks_identity.bats`: one fixture-repo case per row of the table in
  section 1, plus a mutation control that compares against the working-tree file instead of
  the HEAD blob and must turn the drift cases red.
- `tests/setup_env/doctor_git_hooks.bats`: the two new messages, each with its remedy text.
- ADR-0061 gets a dated amendment section recording the HEAD comparison and the two new
  words; its decision (doctor judges hook identity, read-only) is unchanged.

## Requirements

- **R1.** `_git_hooks_identity` prints `match` and returns 0 for a symlink to a source candidate whose content's `git hash-object --no-filters` equals `git rev-parse HEAD:<candidate>` when the repo's HEAD is on branch `master` or `main`.
- **R2.** `_git_hooks_identity` prints `off-branch`, a TAB and the branch name (or `detached HEAD`), and returns 1, for a symlink to a source candidate whose content equals its HEAD blob when the repo's HEAD is on any branch other than `master` or `main`, or detached.
- **R3.** `_git_hooks_identity` prints `drift`, a TAB and `uncommitted changes in <candidate>`, and returns 1, for a symlink to a source candidate whose content differs from its HEAD blob.
- **R4.** `_git_hooks_identity` prints `drift`, a TAB and `<candidate> not committed at HEAD`, and returns 1, for a symlink to a source candidate absent from HEAD.
- **R5.** `_git_hooks_identity` prints `match` and returns 0 for a regular-file hook whose `git hash-object --no-filters` equals the HEAD blob of any source candidate, whatever the working-tree file holds.
- **R6.** `_git_hooks_identity` prints `drift`, a TAB and `copied from uncommitted <candidate>`, and returns 1, for a regular-file hook that is byte-identical to a candidate's working-tree file but equals no candidate's HEAD blob.
- **R7.** `_git_hooks_identity` prints `stale` and returns 1 for a regular-file hook that equals neither any candidate's HEAD blob nor any candidate's working-tree file, as before.
- **R8.** `_doctor_check_git_hooks` calls `doctor_warn` with `<hook> runs <reason> from the main checkout — remedy: commit, stash or discard the change in <dir>` for `drift`.
- **R9.** `_doctor_check_git_hooks` calls `doctor_warn` with `<hook> runs <reason>'s <hook> script, not the default branch's — remedy: git -C <dir> switch <default>` for `off-branch`, where `<default>` is `main` if the repo has a local `main` branch and no local `master`, else `master`.
- **R10.** Every git call added to `lib/git_hooks.sh` or `lib/helpers.sh` runs under `env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE`.
- **R11.** `tests/setup_env/git_hooks_identity.bats` has at least one case for each of R1 to R7, and `tests/setup_env/doctor_git_hooks.bats` has a case for each of R8 and R9.
- **R12.** `docs/adr/0061-doctor-hook-identity-and-ggshield-probe.md` gains an amendment section dated 2026-11-22 naming the HEAD-blob comparison and the `drift` and `off-branch` words.
- **V1.** A mutation that compares against the working-tree file instead of the HEAD blob turns at least the R3 and R6 cases red.
- **V2.** `./setup_env.sh -t doctor` on `claude` after the change reports no `drift` or `off-branch` line for any of the nine repos (prediction from the Measured section).
- **V3.** With an uncommitted edit to `scripts/pre-push` in a scratch clone whose hooks are installed by its own `make install-hooks`, the doctor arm prints the R8 warning for that clone.
- **N1.** No repo's `install-hooks` target changes, and no hook is reinstalled, copied or relinked by doctor.
- **N2.** No added code reads a remote ref (`origin/*`) or performs a fetch or other network call.
- **N3.** No existing identity word changes meaning except `match` and `stale` for regular-file hooks as stated in R5 to R7.
