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
because it checks only that the target is a tracked source candidate, whatever the target's
content. Copy-installed hooks are out of scope: their content is fixed at install time and
the existing `stale` check already compares them with the working tree.

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
- Predicted effect on today's fleet: all 9 symlinked hooks (dotfiles, etch-config and math,
  three each) hash with `--no-filters` to their candidate's blob on the local default branch,
  and all three main checkouts are clean and on that branch. The change below therefore
  reports `match` for all of them, and copy-installed hooks are untouched. Population:
  `claude` only.
- How often doctor runs: the operator runs `setup_env.sh -t doctor` after setup and
  updates only. This check is therefore a diagnostic for when something already looks
  wrong, not a monitor; it cannot be relied on to catch a two-minute window.

## Design

### 1. `_git_hooks_identity` judges a symlinked hook against the default branch's blob

Scope: symlink-installed hooks only. A copy-installed hook is judged exactly as today
(byte-compared with the candidate's working-tree file, `stale` when it differs, with the
existing `stale` arm and remedy). A copy's content is fixed at install time, its staleness
already has a check, and F7 is about symlinks; changing copy semantics was tried in review
round 1 and made the existing `stale` arm report false text (see Multi-Lens Review).

For a symlink whose target is a source candidate in the main working tree (today's `match`
condition), the reference is that candidate's blob on the repo's local default branch:

1. `<default>` is chosen from the local refs, tested with
   `git show-ref --verify -q refs/heads/<name>`: if only one of `main` and `master` exists,
   it is that one; if both exist, it is the one HEAD is symbolically on
   (`git symbolic-ref --short -q HEAD`), and `error` (`both main and master exist`) when HEAD
   is on neither; if neither exists, `error`. A leftover local `master` in a `main` repo is
   therefore never chosen while the checkout is on `main`.
2. Only then is the blob looked up with `git rev-parse --verify -q refs/heads/<default>:<candidate>`.
   Because the ref is known to exist, rc 1 means the path is not on `<default>`; any other
   non-zero rc is `error`.
3. The installed content is hashed with `git hash-object --no-filters <target>`, the target
   being the symlink's resolved path. `--no-filters` compares raw bytes and runs no
   configured clean filter, so the check executes no repo-supplied code. Known limit: a
   checkout under an `eol=crlf` attribute would read as `drift`; no fleet repo sets one
   (dotfiles sets `eol=lf`, the other eight have no `.gitattributes`).
4. Known limit, chosen: the reference is local, so a commit to a hook script made directly
   on the main checkout's default branch and not yet pushed becomes the reference and reads
   `match`. Reading `refs/remotes/origin/<default>` would close this without network, but
   it would also warn on every lagging checkout (see Alternatives considered), and
   core.md git-workflow-001/-003 already forbid direct commits of executable files to the
   default branch. Today all three symlinked repos are 0 commits ahead of origin.

All git calls use the `env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE`
wrapper the function already uses. No temporary file, no network, no `origin` ref.

The reference is the local default branch, not `origin`: F7 is about the main checkout's
working tree differing from what is committed there. A local branch lagging origin is the
update sweep's concern; on `claude` today four repos lag (dotfiles 2, math 1,
terraform_ansible 3, state-ledger 9 commits) and none of the lag touches a hook script.

Comparing against the default branch rather than HEAD means a branch checked out in the main
tree warns only when it actually changes the hook script, which was never the case in the
measured branch episodes.

| Symlink to candidate, target content | Before | After |
| --- | --- | --- |
| equals the default-branch blob | `match` | `match` |
| differs from the default-branch blob | `match` | `drift` (rc 1), reason `<candidate> differs from <default>` |
| candidate path not on `<default>` | `match` | `drift` (rc 1), reason `<candidate> is not on <default>` |
| hash fails or prints nothing; default ref missing; blob lookup rc other than 0 or 1 | `match` | `error` (rc 2), reason naming the failed call |

A symlink to a candidate whose file is missing stays `stale`; symlinks into worktrees or
outside the repo keep `worktree` and `foreign`; regular files and generated shims are
unchanged. Candidates are still filtered by hook name first (ADR-0061's matching-by-name
rule).

### 2. Doctor arm

`drift` prints four TAB-separated fields, `drift<TAB><reason><TAB><default><TAB><candidate>`,
so the doctor arm reads `<default>` and `<candidate>` as data instead of parsing the reason
or re-deriving the default branch. Every other word keeps its current field count.

`_doctor_check_git_hooks` (`lib/helpers.sh`) reads the identity line into
`_word _reason _default _cand` and gains one arm:

- `drift` gives `doctor_warn "<repo>" "<hook> drifts: <reason> — remedy: inspect with git -C <dir> diff <default> -- <candidate>, then return <dir> to a clean <default> once no session owns the change"`.

WARN, not FAIL: the hook is still the repo's own script and the state is usually
short-lived. The remedy names no `commit` and no `switch`: committing on the main checkout's
default branch is a direct-to-master commit, and switching could move another session's
tree. Every other arm, `stale` included, is unchanged; `error` already FAILs through the
existing rc 2 path, and the fail-closed `*)` arm still FAILs any unknown word.

### 3. Tests and documentation

- `tests/setup_env/git_hooks_identity.bats`: one fixture-repo case per row of the table in
  section 1, plus a copy-hook regression case showing a copy is still judged against the
  working tree. A mutation control that compares against the working-tree file instead of
  the default-branch blob must turn the `drift` case red.
- `tests/setup_env/doctor_git_hooks.bats`: the `drift` message with its remedy text.
- ADR-0061 gets a dated amendment section recording the default-branch blob comparison for
  symlinks and the `drift` word; its decision (doctor judges hook identity, read-only) is
  unchanged.

### Alternatives considered

- **A self-check inside `scripts/pre-push`**, comparing its own bytes with the default
  branch's blob on every push. Rejected: the file doing the checking is the file that
  drifted. A modified hook script can delete or bypass its own check, and the measured
  episode replaced the whole file. A check is only meaningful outside the thing it checks.
- **Compare against HEAD and warn separately when the main checkout is off its default
  branch.** Rejected in review round 1: both measured branch episodes left the hook bytes
  unchanged, so a branch-name test warns about states that never change the gate.
- **Also judge copies against the default-branch blob.** Rejected in review round 2: every
  copy-installing `install-hooks` copies from the working tree, so the `stale` remedy would
  reinstall the same bytes and never clear, and the existing off-branch `stale` text would
  name the wrong reference.
- **Compare against `origin/<default>`.** Rejected: it would warn on every lagging main
  checkout (four repos on `claude` today) for a state that does not change the gate.
- **Install copies everywhere.** Not chosen: it reverses the symlink direction ADR-0016
  records and brings back copies that go stale until reinstalled.

## Requirements

- **R1.** A source candidate for hook `<hook>` is a path listed by `git ls-files` whose basename is `<hook>` or `<hook>-hook.sh`. For a symlink whose resolved target is a source candidate in the repo's main working tree, `_git_hooks_identity` resolves `<default>` with `git show-ref --verify -q`: the one of `refs/heads/main` and `refs/heads/master` that exists when only one does; when both exist, the one `git symbolic-ref --short -q HEAD` names, and otherwise it prints `error`, a TAB and `both main and master exist`, returning 2; when neither exists it prints `error`, a TAB and `no local main or master branch`, returning 2.
- **R2.** For such a symlink, `_git_hooks_identity` hashes the resolved target with `git hash-object --no-filters <target>` and looks up the reference with `git rev-parse --verify -q refs/heads/<default>:<candidate>`, only after `refs/heads/<default>` is known to exist.
- **R3.** `_git_hooks_identity` prints `match` and returns 0 for such a symlink when the target's hash equals the candidate's default-branch blob, whatever branch the repo's HEAD is on.
- **R4.** `_git_hooks_identity` prints the four TAB-separated fields `drift`, `<candidate> differs from <default>`, `<default>` and `<candidate>`, and returns 1, for such a symlink when the target's hash differs from the candidate's default-branch blob.
- **R5.** `_git_hooks_identity` prints the four TAB-separated fields `drift`, `<candidate> is not on <default>`, `<default>` and `<candidate>`, and returns 1, for such a symlink when `git rev-parse --verify -q refs/heads/<default>:<candidate>` exits 1.
- **R6.** `_git_hooks_identity` prints `error`, a TAB and a reason, and returns 2, for such a symlink: reason `cannot hash <target>` when `git hash-object` exits non-zero or prints an empty string, and reason `cannot read refs/heads/<default>:<candidate> (rc <n>)` when the blob lookup exits with a status `<n>` other than 0 or 1; an empty or failed hash is never compared.
- **R7.** `_git_hooks_identity` judges a regular-file hook exactly as before: `match` when it is byte-identical (`cmp -s`) to a candidate's working-tree file, otherwise `stale`, or for a repo tracking no candidate one of `generated`, `generated-broken` and `generated-unverified` as today.
- **R8.** `_doctor_check_git_hooks` reads the identity line's third and fourth TAB-separated fields as `<default>` and `<candidate>` and calls `doctor_warn "<repo>" "<hook> drifts: <reason> — remedy: inspect with git -C <dir> diff <default> -- <candidate>, then return <dir> to a clean <default> once no session owns the change"` for `drift`.
- **R9.** Every git call added to `lib/git_hooks.sh` or `lib/helpers.sh` runs under `env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE`.
- **R10.** `tests/setup_env/git_hooks_identity.bats` has separate cases for R1 choosing `main` (only `refs/heads/main` exists), R1 choosing `master` (only `refs/heads/master` exists), R1 choosing `main` when both exist and HEAD is on `main`, R1's `error` when both exist and HEAD is on neither, and R1's `error` when neither exists, and at least one case for each of R3 to R7, and `tests/setup_env/doctor_git_hooks.bats` has R8 cases asserting the full remedy line for a `master` repo and for a `main` repo.
- **R11.** `docs/adr/0061-doctor-hook-identity-and-ggshield-probe.md` gains an amendment section dated 2026-11-22 naming the default-branch blob comparison for symlinked hooks and the `drift` word.
- **V1.** A mutation that compares the symlink target against the working-tree file instead of the default-branch blob turns at least the R4 case red.
- **V2.** `./setup_env.sh -t doctor` on `claude` after the change reports no `drift` line and no `error` line for any of the nine repos (prediction from the Measured section).
- **V3.** With `HOME` and `GITREPOS` both set to a scratch directory and a clone at `<scratch>/personal/dotfiles` whose hooks are installed as symlinks by its own `make install-hooks`, calling `_doctor_check_git_hooks` (not the full `-t doctor`) after an uncommitted edit to `scripts/pre-push` prints the R8 warning for that clone, and reverting the edit makes it print the repo's pass line again.
- **N1.** No repo's `install-hooks` target changes, and doctor never reinstalls, copies, relinks, restores, commits or switches anything.
- **N2.** No added code reads a remote ref (`origin/*`) or performs a fetch or other network call.
- **N3.** No added code runs a git clean or smudge filter; every added `git hash-object` call passes `--no-filters`.
- **N4.** For regular-file hooks and generated shims, every identity word is printed for exactly the inputs it was before; `worktree`, `foreign` and `stale` for symlinks are printed for exactly the inputs they were before.

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
A real dirty episode was observed during this review (Measured section). (Superseded: V4 was
removed in round 2 when copies left scope.)

### Risk

Finding: a failed `hash-object` or `rev-parse` prints nothing, and two empty strings compare
equal, so a broken implementation lands on `match`; N3 contradicted R1–R4; `--no-filters`
reports false drift under an `eol=crlf` attribute (latent: no fleet repo sets it). The
lens's own probe wrote into the dotfiles main checkout after a failed `cd`, the episode
recorded under Measured.
Assumption: no uncertain assumption found (weakest: no fleet checkout writes CRLF into a
hook script, checkable on the Windows box with `git check-attr eol -- scripts/pre-push`).
Disposition: Addressed — R8 (now R6) makes a failed or empty hash an `error`; N3 rewritten;
`hash-object --path=<candidate>` replaces `--no-filters`.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.

### Round 2

Reviewed at commit: `ab1f7ce9` (round-1 revision; the body above is the round-2 revision)

- **Goal-Fit.** Finding: R6/R7 changed what `stale` means for copies while the `stale` doctor
  arm, declared unchanged, still branches on the HEAD branch name, so a copy taken on a
  feature branch is reported as differing from the branch it equals, and on master the
  reinstall remedy copies the same dirty bytes and never clears. Assumption: the local
  default ref is current when doctor runs. Disposition: Addressed — copies are out of scope
  and judged exactly as before (R7, N4); the local default branch stays the reference
  (operator, 2026-11-22), recorded under Alternatives considered.
- **Ergonomics.** Finding: the same copy-side `stale` defect (every copy-installing
  `install-hooks` copies from the working tree: ai-config, etch-cli, the site, state-ledger);
  the R9 sentence was ungrammatical; lag and worktree edits do not fire (26 of 26 `match`
  with four repos lagging origin). Assumption: an off-default main checkout never coincides
  with copies installed from that branch. Disposition: Addressed — copy scope removed, remedy
  sentence reworded to `<hook> drifts: <reason>`.
- **Risk.** Finding: the same copy-side `stale` defect; `rev-parse --verify -q` returns rc 1
  for both a missing path and a missing branch, so R8's rc rule needs the ref checked first;
  `hash-object --path` reads working-tree attributes and runs configured clean filters (code
  execution inside a read-only check); a missing default ref turns a former `match` into a
  FAIL. Assumption: the local default branch is a sound reference (math lags origin in two
  `scripts/crate_templates/` files, not hook scripts). Disposition: Addressed — ref existence
  is tested with `show-ref` before the blob lookup (R1, R2); `--no-filters` restored with the
  CRLF limit documented (N3); the local reference kept by operator decision.

### Round 3 (scoped Risk lens on Design, Alternatives and Requirements)

Reviewed at commit: `8bc9547f`

Finding: no blocking defect. R10 let one case satisfy R1's three outcomes (`main`, `master`,
`error`), leaving etch-config's `main` path covered only by V2; "source candidate", R6's
reason and R7's shim words were not self-contained. Probed: missing path and missing ref both
`rc=1` for `rev-parse --verify -q`, `show-ref --verify -q` missing `rc=1`, corrupt subtree
`rc=128`; relative symlinks (math) and symlinked repo paths resolve physically; all 9
candidates are mode `100755`; no R contradicts N3 or N4; R7 matches the current code. The
wording fixes (R1 candidate definition, exact R6 reasons, listed shim words, three R1 cases
in R10) were applied in the next commit.
Assumption: the main checkout's local default branch is reviewed content. A direct local
commit to a hook script would become the reference and read `match`. Today every symlinked
repo's default branch is 0 commits ahead of origin, and no dotfiles reflog commit touched a
hook script; core.md git-workflow-001/-003 allow only docs and pure data direct to master.
Disposition:

## External Review

### Round 1 (reviewed at `29d7faf8`)

Report: [round1.md](2026-11-22-doctor-hook-drift-design.external-review/round1.md)

#### Author response

| finding | disposition | evidence | reviewer verdict | operator (Step 9) |
| ------- | ----------- | -------- | ---------------- | ----------------- |
| F1.1 | Fixed | R1 and Design 1 step 1: with both refs, the branch HEAD is symbolically on wins; HEAD on neither is `error` (`both main and master exist`); R10 gains the two both-refs cases. On `claude` no symlinked repo has both refs (dotfiles master, etch-config main, math master). | unjudged | |
| F1.2 | Fixed | `drift` prints `drift<TAB><reason><TAB><default><TAB><candidate>` (R4, R5, Design 2); the doctor reads fields 3 and 4 (R8); R10 asserts the remedy line for a `master` and a `main` repo. | unjudged | |
| F1.3 | Fixed | V3 sets `HOME` and `GITREPOS` to scratch, places the clone at `<scratch>/personal/dotfiles`, and calls `_doctor_check_git_hooks` only. | unjudged | |
| F1.4 | Fixed | Design 1 step 4 records the unpushed-local-commit limit as a chosen trade, citing the origin alternative and git-workflow-001/-003; round 3's disposition stays for the operator at Step 9. | unjudged | |
| F1.5 | Fixed | Round 1 Ergonomics and Risk dispositions annotated as superseded (V4 removed; R8 is now R6). | unjudged | |

Stopped: reviewer recommended stopping in round 1
