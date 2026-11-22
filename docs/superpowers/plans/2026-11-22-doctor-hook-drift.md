# Doctor hook drift check Implementation Plan

spec: docs/superpowers/specs/2026-11-22-doctor-hook-drift-design.md

> **Status: DONE** — merged as dotfiles#483 (59e7b077), 2026-11-22.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `setup_env.sh -t doctor` warns when a symlink-installed hook's target differs from the committed script on the repo's local default branch (security audit F7).

**Architecture:** `_git_hooks_identity` (`lib/git_hooks.sh`) gains a content check for the symlink-to-candidate path, which today returns `match` unconditionally; it resolves the local default branch, hashes the target with `git hash-object --no-filters` and compares it with the candidate's default-branch blob. `drift` prints four TAB fields so `_doctor_check_git_hooks` (`lib/helpers.sh`) can build its remedy without parsing prose. Regular-file hooks and generated shims are untouched.

**Tech Stack:** bash, git 2.53, bats.

## Global Constraints

- Every added git call runs under `env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE` (R9).
- Every added `git hash-object` call passes `--no-filters`; no clean or smudge filter runs (N3).
- No added code reads `origin/*` or touches the network (N2); doctor never reinstalls, copies, relinks, restores, commits or switches (N1).
- Regular-file hooks, generated shims, and symlink `worktree`/`foreign`/`stale` inputs keep today's identity words (R7, N4).
- Fixture repos in tests are created with an explicit `git init -q -b <branch>`; `tests/helpers/common.bash` already unsets the four `GIT_*` variables.
- `make test` on `claude` completes inside the 600 s Bash cap (measured 2026-11-22: full suite, `JOBS=12`, foreground, 1..4406), so code tasks gate on it directly.

## Verification

- Whole change: `make test` exits 0; `bats tests/setup_env/git_hooks_identity.bats tests/setup_env/doctor_git_hooks.bats` passes with the new cases.
- V1 (mutation): in a `git archive HEAD` copy, replace the default-branch blob comparison with a comparison against the working-tree file; the R4 case must go red.
- V2 (live, predicted): sourcing `lib/helpers.sh` on `claude` and running `_doctor_check_git_hooks` prints no `drifts:` line and no `cannot verify hooks` line for the nine repos (all 9 symlinked hooks measured equal to their default-branch blob, 2026-11-22).
- V3 (end to end): `HOME` and `GITREPOS` set to a scratch dir, a clone at `<scratch>/personal/dotfiles` with `make install-hooks` run inside it, `HOOK_EXPECTED_REPOS=(dotfiles)`; editing the clone's `scripts/pre-push` makes `_doctor_check_git_hooks` print the R8 warning, and `git -C <clone> checkout -- scripts/pre-push` restores the pass line.
- Edge cases: relative symlink (math's `../../scripts/pre-commit`), a repo reached through a symlinked path, a `main`-only repo, a repo with both `main` and `master`, a symlink to a candidate deleted from the working tree (stays `stale`).

---

### Task 1: Symlink content check in `_git_hooks_identity`

```yaml-task
id: 1
description: Judge a symlink-to-candidate hook against the candidate's blob on the local default branch, adding drift and error results
role: executor
model: sonnet
tdd: required
requirements: [R1, R2, R3, R4, R5, R6, R7, R9, R10]
acceptance:
  - cmd: bats tests/setup_env/git_hooks_identity.bats
    exit_code: 0
  - cmd: 'bats -f "drift|default branch" tests/setup_env/git_hooks_identity.bats'
    exit_code: 0
    stdout_match: 'ok [0-9]+ identity: .*drift'
  - cmd: make lint
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [lib/git_hooks.sh, tests/setup_env/git_hooks_identity.bats]
depends_on: []
```

**Files:** `lib/git_hooks.sh` (`_git_hooks_identity`, its header comment), `tests/setup_env/git_hooks_identity.bats`.

Change only the `match` branch of the symlink path (today: target equals `${_repo_phys}/${_cand}` and `-f`). Before printing `match`:

1. Resolve `<default>` with `git show-ref --verify -q refs/heads/main` / `.../master`: only one exists, use it; both exist, use `git symbolic-ref --short -q HEAD` if it is `main` or `master`, else print `error<TAB>both main and master exist`, rc 2; neither, `error<TAB>no local main or master branch`, rc 2.
2. `git hash-object --no-filters "${_target}"`: non-zero rc or empty output gives `error<TAB>cannot hash <target>`, rc 2.
3. `git rev-parse --verify -q "refs/heads/<default>:<cand>"`: rc 1 gives `drift<TAB><cand> is not on <default><TAB><default><TAB><cand>`, rc 1; any other non-zero `<n>` gives `error<TAB>cannot read refs/heads/<default>:<cand> (rc <n>)`, rc 2.
4. Equal hashes: `match`, rc 0. Different: `drift<TAB><cand> differs from <default><TAB><default><TAB><cand>`, rc 1.

Every git call uses the existing `env -u ...` wrapper with `-C "${_repo_dir}"`. Update the header comment with `drift` and the new `error` reasons. Change the file's `make_repo` to `git init -q -b master` and keep every existing test green.

New tests (one per item, names start `identity:`): R1 main-only, master-only, both refs with HEAD on main, both refs with HEAD on a feature branch (error), neither ref (error, via `git update-ref -d`); R3 clean match while HEAD is on a feature branch whose script equals master's; R4 dirty target (drift, assert all four fields); R5 candidate staged but never committed on the default branch (drift); R6 hash failure through an unreadable target (`chmod 000`, skip when running as root) asserting `cannot hash`; R7 regression: a regular-file copy of a dirty working-tree file is still `match`.

**Interfaces:** Produces the `drift` line `drift<TAB><reason><TAB><default><TAB><candidate>` (rc 1) consumed by Task 2.

### Task 2: Doctor arm for `drift`

```yaml-task
id: 2
description: Read the drift fields in _doctor_check_git_hooks and warn with the inspect-then-clean remedy
role: executor
model: sonnet
tdd: required
requirements: [R8, R10]
acceptance:
  - cmd: bats tests/setup_env/doctor_git_hooks.bats
    exit_code: 0
  - cmd: 'bats -f "drift" tests/setup_env/doctor_git_hooks.bats'
    exit_code: 0
    stdout_match: 'ok [0-9]+ .*drift'
  - cmd: make lint
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [lib/helpers.sh, tests/setup_env/doctor_git_hooks.bats]
depends_on: [1]
```

**Files:** `lib/helpers.sh` (`_doctor_check_git_hooks`), `tests/setup_env/doctor_git_hooks.bats`.

Change `IFS=$'\t' read -r _word _reason <<< "${_out}"` to `IFS=$'\t' read -r _word _reason _default _cand <<< "${_out}"` (declare both locals). Add before `*)`:

```bash
        drift)
          doctor_warn "${_name}" "${_hook} drifts: ${_reason} — remedy: inspect with git -C ${_dir} diff ${_default} -- ${_cand}, then return ${_dir} to a clean ${_default} once no session owns the change"
          _faulty=1 ;;
```

Tests: a `master` fixture repo with symlinked hooks and a dirty `scripts/pre-push` asserts the exact remedy line; the same for a `main` repo (`git init -q -b main`); a clean symlinked repo still prints the pass line. Existing tests stay green.

**Interfaces:** Consumes Task 1's `drift` line.

### Task 3: ADR-0061 amendment and plan index

```yaml-task
id: 3
description: Record the default-branch blob comparison and the drift word in ADR-0061 (docs-only, no behaviour change, so TDD does not apply)
role: executor
model: haiku
tdd: not-applicable
requirements: [R11]
acceptance:
  - cmd: 'grep -qE "^## Amendment.*2026-11-22" docs/adr/0061-doctor-hook-identity-and-ggshield-probe.md'
    exit_code: 0
  - cmd: 'grep -q "drift" docs/adr/0061-doctor-hook-identity-and-ggshield-probe.md'
    exit_code: 0
max_retries: 2
files_touched: [docs/adr/0061-doctor-hook-identity-and-ggshield-probe.md]
depends_on: [2]
```

**Files:** `docs/adr/0061-doctor-hook-identity-and-ggshield-probe.md` only.

Append `## Amendment 1 (2026-11-22)` (the corpus style: ADR-0014, ADR-0040, ADR-0055), headed by one sentence that symlinked hooks are now judged against the default-branch blob, stating: a symlink to a source candidate is `match` only when `git hash-object --no-filters` of its target equals the candidate's blob on the local default branch (`main` or `master`, the one HEAD is on when both exist); otherwise `drift` (doctor WARN, remedy inspect then return the main checkout to a clean default branch) or `error` (doctor FAIL). Regular-file hooks are unchanged. Cite spec `docs/superpowers/specs/2026-11-22-doctor-hook-drift-design.md` and security audit F7. The decision (doctor judges hook identity, read-only) is unchanged.

The orchestrator runs `make test` once after this task; the ADR is not read by the suite.

## Non-goal check

Reviewer: fresh reviewer-role subagent, `~/.claude/skills/writing-plans/nongoal-check.md`, 2026-11-22.

- N1 CLEAR — "the plan does not change any `install-hooks` target. The doctor drift arm only warns, and its remedy is advice text. The `make install-hooks` and `git checkout --` in V3 are verification steps on a scratch clone, not added code." Resolution: none needed.
- N2 CLEAR — "every added ref read is `refs/heads/main` or `refs/heads/master`, or `refs/heads/<default>:<cand>`. Nothing reads `origin/*`." Resolution: none needed.
- N3 CLEAR — "the only added `git hash-object` call (Task 1 step 2) passes `--no-filters`." Resolution: none needed.
- N4 CLEAR — "Task 1 changes only the symlink `match` branch ... Task 2 widens the read to 4 fields but does not change any word that is printed." Resolution: none needed.
