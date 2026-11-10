# Auto-merge: skip drafts, retry the policy refusal — Implementation Plan

spec: docs/superpowers/specs/2026-11-10-auto-merge-draft-hold-retry-design.md

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The `auto-merge` job skips drafts and retries only GitHub's `base branch policy prohibits the merge` refusal, through a merge script read from the base commit.

**Architecture:** New `scripts/auto-merge-merge.sh` wraps one `gh pr merge --squash --match-head-commit` call in a 3-attempt loop that retries only the policy refusal. `ci.yml`'s merge step reads that script from `BASE_SHA` (as the hold step already does for the gate) and falls back to today's single direct merge when the base has none. The job's `if:` gains `draft == false`.

**Tech Stack:** bash, bats, GitHub Actions YAML, `gh`.

## Global Constraints

- No `--auto` flag anywhere in `ci.yml`; `allow_auto_merge` stays false (N1).
- `auto-merge`'s `needs:` and branch protection's required checks unchanged (N2).
- Retry only on output containing `base branch policy prohibits the merge` (N3).
- `scripts/auto-merge-gate.sh` unchanged; the gate still runs from `git show "${BASE_SHA}:scripts/auto-merge-gate.sh"` (N4).
- The merge step never runs the PR checkout's `scripts/auto-merge-merge.sh` (N5).
- Shell: `#!/usr/bin/env bash`, no `set -e`, `[[ ]]`, `${VAR}`, `printf`, sourcing guard on the last line before main, functions `|| return 1`, top level `|| exit 1`.
- Adding a `.bats` file updates `tests/bats-files.txt` (`git ls-files '*.bats' | LC_ALL=C sort > tests/bats-files.txt`); `make check-bats-manifest` checks it.

## Verification

- Session gate: `make test` exits 0 in the worktree, run by the orchestrator after Task 2 and after Task 3 (task gates are scoped so no subagent backgrounds the full suite).
- Behaviour: `AUTO_MERGE_RETRY_DELAY=0 bash scripts/auto-merge-merge.sh 1` exits 1 with a usage line and no gh call; the bats file drives every retry branch through a fake `gh` and fake `sleep`.
- After merge (V1): the first draft PR shows `auto-merge` skipped, and its ready run's log shows `attempt 1/3` from the base-commit script. This PR's own merge takes the fallback (`retry off, single direct merge`), since its base has no script.
- V2 already landed (ai-config 8a995ca2). V3 is post-merge observation, recorded in the Backlog.
- Edge cases: `<pr>` alone; refusal then a different error mid-loop; gh exit 1 with no output; default delay 30 versus override.

---

### Task 1: Merge script and its bats file

```yaml-task
id: 1
description: Add scripts/auto-merge-merge.sh (bounded retry of the policy refusal, attempt timestamps, remedy line) with tests/scripts/auto_merge_merge.bats
role: executor
model: sonnet
tdd: required
requirements: [R2, R3, R4, R5, R7, R8, R10]
acceptance:
  - cmd: bats tests/scripts/auto_merge_merge.bats
    exit_code: 0
    stdout_match: 'ok 9 '
  - cmd: make lint
    exit_code: 0
  - cmd: make check-bats-manifest
    exit_code: 0
max_retries: 3
files_touched: [scripts/auto-merge-merge.sh, tests/scripts/auto_merge_merge.bats, tests/bats-files.txt]
depends_on: []
```

**Files:** create `scripts/auto-merge-merge.sh` (mode 755), `tests/scripts/auto_merge_merge.bats`; regenerate `tests/bats-files.txt`.

**Script contract** (`auto_merge_merge <pr> <head_sha>`):

```bash
readonly _AUTO_MERGE_REFUSAL='base branch policy prohibits the merge'
readonly _AUTO_MERGE_ATTEMPTS=3
# empty <pr> or <head_sha>: usage on stderr, return 1, no gh call
# per attempt n: printf 'attempt %d/%d at %s\n' n 3 "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
#   _out="$(gh pr merge "${_pr}" --squash --match-head-commit "${_sha}" 2>&1)"; _rc=$?
#   print _out if non-empty; rc 0 -> return 0
#   _out lacks the refusal substring -> return 1 (R4: any other error, empty output included)
#   n < 3 -> sleep "${AUTO_MERGE_RETRY_DELAY:-30}"
# after 3 refusals:
#   printf 'still refused after 3 attempts: merge by hand with gh pr merge %s --squash --match-head-commit %s, or re-run all jobs, never failed-only\n' "${_pr}" "${_sha}"
#   return 1
```

Last lines: `[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0` then `auto_merge_merge "$@" || exit 1`. Header comment: why it retries (timing refusal, spec Problem) and that `ci.yml` runs it from the base commit.

**Tests** (setup: `REPO_ROOT`, `SCRIPT`, a `${BATS_TEST_TMPDIR}/bin` prepended to `PATH` holding):

- fake `gh`: increments `${BATS_TEST_TMPDIR}/calls`; appends each argument on its own line plus a `--` line to `${BATS_TEST_TMPDIR}/argv`; reads line N of `${FAKE_GH_SEQ}` as `<exit><TAB><message>`; exit 0 prints the message on stdout, non-zero prints a non-empty message on **stderr only**; exits `<exit>`.
- fake `sleep`: appends `$1` to `${BATS_TEST_TMPDIR}/sleeps`, exits 0.
- `REFUSED='X Pull request brujack/dotfiles#354 is not mergeable: the base branch policy prohibits the merge.'`; `MODIFIED='GraphQL: Head branch was modified. Review and try the merge again. (mergePullRequest)'`. Always pass `354 abc123` unless the case says otherwise; `unset AUTO_MERGE_RETRY_DELAY` in setup.

Exactly these nine `@test`s, in this order (R7):

1. merged on the first call: 1 call, status 0, no `sleeps` file.
2. refused then merged, `AUTO_MERGE_RETRY_DELAY=5`: 2 calls, status 0, `sleeps` is `5`.
3. refused three times, delay unset: 3 calls, status 1, `sleeps` is `30` then `30`, output contains `merge by hand with gh pr merge 354 --squash --match-head-commit abc123`, and exactly 3 output lines match `^attempt [1-3]/3 at [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$`.
4. `Head branch was modified`: 1 call, status 1, output contains `Head branch was modified`.
5. refused then `Head branch was modified`: 2 calls, status 1.
6. gh exits 1 with no output (fake prints nothing for an empty message): 1 call, status 1.
7. `<pr>` alone (`bash "${SCRIPT}" 354`): 0 calls, status 1, output contains `usage`.
8. no arguments: 0 calls, status 1.
9. logged argv is exactly `pr`,`merge`,`354`,`--squash`,`--match-head-commit`,`abc123`,`--`.

- [ ] Write the bats file; run it; all nine fail (script missing). Record the RED output.
- [ ] Write the script; run the bats file: 9/9 ok.
- [ ] Mutation control: delete the `sleep` line; cases 2 and 3 fail; restore. Change `2>&1` to nothing; case 2 fails; restore. Report both.
- [ ] Regenerate `tests/bats-files.txt`; run the acceptance gates; commit (`caveman:caveman-commit`).

**Interfaces:** Produces `scripts/auto-merge-merge.sh <pr> <head_sha>`, exit 0 merged / 1 otherwise; Task 2 runs it from the base commit.

### Task 2: ci.yml merge step and draft skip

```yaml-task
id: 2
description: Skip drafts in the auto-merge job and run the merge script from the base commit with a single-merge fallback, pinned by tests/scripts/ci_auto_merge.bats
role: executor
model: sonnet
tdd: required
requirements: [R1, R6]
acceptance:
  - cmd: bats tests/scripts/ci_auto_merge.bats
    exit_code: 0
    stdout_match: 'ok 7 '
  - cmd: make lint
    exit_code: 0
  - cmd: make check-bats-manifest
    exit_code: 0
max_retries: 3
files_touched: [.github/workflows/ci.yml, tests/scripts/ci_auto_merge.bats, tests/bats-files.txt]
depends_on: [1]
```

**Files:** modify `.github/workflows/ci.yml` (job `auto-merge` only); create `tests/scripts/ci_auto_merge.bats`; regenerate `tests/bats-files.txt`.

**ci.yml change:** job `if:` becomes `github.event_name == 'pull_request' && github.event.pull_request.draft == false`. The `Auto-merge passing PRs` step keeps `if: steps.hold.outputs.merge == 'true'`, adds env `BASE_SHA: ${{ github.event.pull_request.base.sha }}`, and runs:

```bash
merge="${RUNNER_TEMP}/auto-merge-merge.sh"
if git show "${BASE_SHA}:scripts/auto-merge-merge.sh" > "${merge}"; then
  bash "${merge}" "${PR_NUMBER}" "${HEAD_SHA}"
else
  echo "no merge script on the base commit -- retry off, single direct merge"
  gh pr merge "${PR_NUMBER}" --squash --match-head-commit "${HEAD_SHA}"
fi
```

Step comment (replace the current one, keep its by-number/head-pin sentence): no `--auto` because (1) `enablePullRequestAutoMerge` is refused for a bot token lacking `workflows` on a PR touching `.github/workflows/**` (ai-config), and (2) `--auto` would merge a later push before its own `auto-merge` run re-ran the gate (terraform_ansible#238); the script is read from the base commit like the gate, since `scripts/` lacks the `workflows` scope and a PR-edited copy holds `pull-requests: write`; the hold step's fetch put `BASE_SHA` in the repo; deleting or renaming `scripts/auto-merge-merge.sh` silently turns the retry off.

**Tests:** helper `_job <name>` prints the lines of one top-level job (from `^  <name>:$` to the next `^  [a-z-]+:$`), and `_merge_step` prints the `Auto-merge passing PRs` step (to the next `     -` or end), each with full-line comments (`^[[:space:]]*#`) dropped. Exactly these seven `@test`s:

1. the job's `if:` is exactly the R1 expression.
2. the merge step keeps `if: steps.hold.outputs.merge == 'true'` and sets `BASE_SHA: ${{ github.event.pull_request.base.sha }}`.
3. the merge step contains `git show "${BASE_SHA}:scripts/auto-merge-merge.sh"` and `bash "${merge}" "${PR_NUMBER}" "${HEAD_SHA}"`, and no line running `scripts/auto-merge-merge.sh` without `git show` (N5).
4. the fallback contains `retry off` and `gh pr merge "${PR_NUMBER}" --squash --match-head-commit "${HEAD_SHA}"`.
5. no non-comment line of the job contains `--auto`.
6. `git -C "${REPO_ROOT}" ls-files --error-unmatch scripts/auto-merge-merge.sh` succeeds.
7. positive control: `_job auto-merge` contains `auto-merge-gate.sh`; `_job test` contains neither `auto-merge-gate.sh` nor `auto-merge-merge.sh`; `_job no-such-job` is empty.

- [ ] Write the bats file; run it against the unchanged `ci.yml`: tests 1-4 fail (6 passes from Task 1; 5 and 7 pass). Record it.
- [ ] Edit `ci.yml`; run the bats file: 7/7 ok.
- [ ] Mutation control: put `--auto` on the fallback line; test 5 fails; restore.
- [ ] Regenerate `tests/bats-files.txt`; run the gates; commit.

**Interfaces:** Consumes Task 1's script path and argv.

### Task 3: CLAUDE.md bullet and Backlog row

```yaml-task
id: 3
description: Docs only, no behavior change - CLAUDE.md auto-merge bullet names the draft skip, policy-refusal retry and base-commit merge script; remove the closed Backlog row
role: executor
model: sonnet
tdd: not-applicable
requirements: [R9]
acceptance:
  - cmd: 'command grep -q "retries only" CLAUDE.md'
    exit_code: 0
  - cmd: '! command grep -q "Auto-merge refused #294 with every required check green" docs/superpowers/README.md'
    exit_code: 0
  - cmd: make check-claude-md-budget
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 2
files_touched: [CLAUDE.md, docs/superpowers/README.md]
depends_on: [2]
```

**CLAUDE.md** (Testing > CI section, the bullet starting `` `auto-merge` needs ``): append one sentence, no other change: ``It skips drafts (job `if:` on `draft == false`) and merges through `scripts/auto-merge-merge.sh`, read from the base commit like the gate, which retries only `base branch policy prohibits the merge` (3 attempts, 30 s apart, `AUTO_MERGE_RETRY_DELAY`); a base without the script falls back to one direct merge.``

**README:** delete the whole Backlog row whose first cell is `Auto-merge refused #294 with every required check green`. Nothing else in the README changes.

- [ ] Run gates 1 and 2 on the base: both fail. Edit; commit; then run all four gates (`check-claude-md-budget` reads `HEAD`, so it must run after the commit; headroom at 9248f31c is 658 bytes of 85000).

## Orchestrator steps

1. Worktree `../dotfiles-wt-amretry` on `feat/auto-merge-retry` from `origin/master`.
2. Dispatch Tasks 1-3 in order; run `make test` (exit 0) after Task 2 and after Task 3.
3. Phase 3 (`finishing-a-development-branch`). The PR's own merge takes the fallback path; confirm the log line.
4. After merge: V1 on the next draft PR; V3 on the next refusal.

No ADR: the spec records the decision, and this changes one CI job's merge mechanics, not a fleet pattern.

## Non-goal check

Fresh reviewer, 2026-11-10, against N1-N5: CLEAR 5, CONFLICT 0, UNCLEAR 0. No plan revision or amendment.

- N1 CLEAR: "the only `--auto` in the plan is Task 2's mutation control, which adds it and then restores it."
- N2 CLEAR: Task 2 changes only the job's `if:`; `needs:` and branch protection are untouched.
- N3 CLEAR: the retry triggers only on the policy-refusal text; the "re-run all jobs" remedy is advice to a person, not a retry.
- N4 CLEAR: the hold step and the gate script are untouched.
- N5 CLEAR: the merge step reads the script with `git show "${BASE_SHA}:..."`, pinned by Task 2's test 3.
