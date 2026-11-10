# Auto-merge: skip drafts, retry the policy refusal

- **Date:** 2026-11-10
- **Repo:** dotfiles
- **Approved:** 2026-11-10, operator: "yes" (at 8ef058f7)
- **Backlog row closed:** "Auto-merge refused #294 with every required check green"

## Problem

The `auto-merge` job in `.github/workflows/ci.yml` runs `scripts/auto-merge-gate.sh` from
the base commit and, on `merge=true`, runs
`gh pr merge "${PR_NUMBER}" --squash --match-head-commit "${HEAD_SHA}"`. The backlog row
asks why that merge was refused with every required check green, and whether the job
should use `--auto`.

Measured 2026-11-10 over the last 400 `ci.yml` runs (2026-05-28 to 2026-11-10): the
`auto-merge` job failed in 9. Eight logs are readable; one (run 27289760867, 2026-06-10)
has expired.

| Cause                                                       | PRs (run)                                                                                      | Mechanism                                                                                                                                                                                                                                                   |
| ----------------------------------------------------------- | ---------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `GraphQL: Pull Request is still a draft (mergePullRequest)` | #306 (37071158713), #424 (41910690526), #426 (41938741258), `chore/macos-canary` (41141921049) | The gate does not look at draft state, so the merge step runs on a draft and fails.                                                                                                                                                                         |
| `the base branch policy prohibits the merge`, timing        | #241 (32680501470), #414 (41259553982)                                                          | #241's attempt 1 ran 3 s after the last required job finished, and a re-run merged it 8 min later. #414 was refused on attempt 1 and on attempt 2, a full re-run (every job carries `run_attempt` 2), 9 s after `test-macos` finished; it later merged by `github-actions`. |
| same refusal, persistent                                    | #354 (39279309044)                                                                             | Refused on attempt 1 (15:48:44Z, 9 s after `test-macos`) and on attempt 2, a full re-run, at 16:42:24Z: at least 54 min. Its branch `feat/python-hold` was also ai-config#316, refused three times in run 39279301026; the operator merged both by hand at 16:45:23Z and 16:45:28Z. Cause unknown. It is not the `workflows`-permission refusal: #354 touched no `.github/workflows/` file, while #241 and #414 did and merged by `github-actions`. |
| same refusal, failed-only re-run                            | #294 (36211991794, attempt 3)                                                                  | A failed-only re-run; #408 (backlog row) showed one strands the earlier attempt's required checks. #294 was also `UNSTABLE` from its own failed draft-period `auto-merge` run, but `auto-merge` is not a required context, so that did not block it. |

The population is this repo's `ci.yml` runs only. The timing reading for #241 and #414 is
an inference from the 3-9 s gap; ai-config measured the same refusal 40 s after the last
check on its PR #292, and a re-run merged it.

ai-config already runs the retry this spec proposes (3 attempts, 30 s apart). Measured
2026-11-10 over its last 400 `pull_request` runs (2026-06-13 to 2026-11-09): 2 merge jobs
were refused. Run 41102075051 (2026-10-30) was refused at 18:01:42Z and 18:02:13Z and
merged on the third attempt. Run 39279301026 (2026-10-19) was refused three times and
failed; it is the same persistent event as dotfiles #354 above, not a second timing case.
So the retry has met one timing refusal and cleared it, and has met one persistent
refusal, which it cannot clear. The retry rescues timing refusals only; a persistent or
failed-only refusal still fails after about 60 s, as today, and then prints a remedy.

Branch protection on `master` requires exactly the six jobs in `auto-merge`'s `needs:`
(`test`, `lint-macos`, `test-macos`, `powershell`, `secret-scan`, `renderings-install`),
`strict` off. The repo has `allow_auto_merge=false`.

## Why not `--auto`

Two peer repos measured it and chose a direct merge:

- **ai-config** (`ci.yml`, merge step comment): `--auto` calls
  `enablePullRequestAutoMerge`, which GitHub refuses for a bot without the `workflows`
  permission on any PR touching `.github/workflows/**`. dotfiles merges with the same
  `GITHUB_TOKEN`.
- **terraform_ansible#238**: a direct merge with `--match-head-commit` means only the head
  the run tested can merge. With `--auto` enabled, a later push merges as soon as the
  required checks pass, before that push's `auto-merge` job has run the gate, so a held
  shape (bot PR, `uv.lock` without `pyproject.toml`) could merge unexamined.

`--auto` would also need `allow_auto_merge` turned on. The fleet standard (`ci.md`) says
`--squash --auto`; dotfiles, ai-config and terraform_ansible all deviate for the reasons
above.

## Design

### 1. The job skips drafts

The `auto-merge` job's `if:` becomes
`github.event_name == 'pull_request' && github.event.pull_request.draft == false`, the
shape ai-config's `ci.yml` already uses. A draft run shows `auto-merge` as skipped instead
of failed. A red draft run never blocked a merge (`auto-merge` is not a required context),
but it reads as a failure to `gh pr checks --watch` and to the operator. When the draft is
marked ready, the existing `ready_for_review` trigger re-runs the whole workflow, whose
payload then carries `draft: false`.

`scripts/auto-merge-gate.sh` is unchanged. Skipping a draft is not a trust decision, so it
needs no base-commit isolation, and a job-level filter adds no new way for the gate to
fail. The `ci.yml` comment that rejects job-level filters ("skips read as passing")
concerns required gating jobs; for a non-required merge job a skip on a draft is the
intended outcome.

### 2. A merge script retries the policy refusal

New `scripts/auto-merge-merge.sh <pr> <head_sha>`:

- Runs `gh pr merge <pr> --squash --match-head-commit <head_sha>`.
- gh's stdout and stderr are captured together (`2>&1`): gh writes its refusals to
  stderr (`X Pull request brujack/dotfiles#354 is not mergeable: the base branch policy
  prohibits the merge.`, run 39279309044), so a stdout-only capture never matches.
- Exit 0 from gh: print its output, exit 0.
- Before each gh call, print `attempt <n>/3 at <UTC time>` (`date -u +%Y-%m-%dT%H:%M:%SZ`),
  so the next refusals record how long the delay really is.
- Output containing `base branch policy prohibits the merge`: retry, at most 3 attempts in
  total, sleeping `${AUTO_MERGE_RETRY_DELAY:-30}` seconds between attempts. After the third
  refusal, print one remedy line and exit 1:
  `still refused after 3 attempts: merge by hand with gh pr merge <pr> --squash
  --match-head-commit <sha>, or re-run all jobs, never failed-only` (with the real `<pr>`
  and `<sha>`). The reflex "Re-run failed jobs" is #294's pattern, which cannot succeed.
- Any other failure, `Head branch was modified` included: print gh's output and exit 1
  at once.
- Fewer than two arguments: print usage, exit 1, no gh call. One argument alone must not
  reach gh, or the merge would run with `--match-head-commit ""`.

It runs as it exists on the **base** commit, like the gate. With `merge=true` and
`pull-requests: write`, a PR-edited copy could merge a different PR the gate is holding,
or drop `--match-head-commit`. That grants nothing to anyone with push access (same-repo
authors already run PR code with `contents: write` in `test` and `powershell`), but it
would undo the reason the gate is read from the base commit: `scripts/` is not guarded by
the `workflows` token scope that guards `ci.yml`. A base commit without the script (this
spec's own PR) falls back to today's single direct merge, so the retry takes effect from
the PR after this one. Worst case the script waits 60 s, inside the job's 10-minute
timeout.

### 3. `ci.yml`

The merge step gains `BASE_SHA: ${{ github.event.pull_request.base.sha }}` and its `run:`
becomes (the hold step has already fetched the base commit, and a failed fetch made it
red, so the merge step never runs then):

```bash
merge="${RUNNER_TEMP}/auto-merge-merge.sh"
if git show "${BASE_SHA}:scripts/auto-merge-merge.sh" > "${merge}"; then
  bash "${merge}" "${PR_NUMBER}" "${HEAD_SHA}"
else
  echo "no merge script on the base commit -- retry off, single direct merge"
  gh pr merge "${PR_NUMBER}" --squash --match-head-commit "${HEAD_SHA}"
fi
```

Its comment states why the merge is direct and not `--auto`, citing the two reasons above,
why the script is read from the base commit, and that deleting or renaming
`scripts/auto-merge-merge.sh` silently turns the retry off.

### 4. Out of scope

An agent watching `gh pr checks --watch` on a PR that ends green but unmerged (a bot PR
held by the gate, or a draft) gets no prompt: `finishing-a-development-branch` assumes the
PR auto-merged. That skill lives in ai-config; it is filed as an ai-config backlog row, not
changed here.

A failed-only re-run that strands required checks (#294, #408) is not handled here:
`ai-config`'s `finishing-a-development-branch` already says to re-run all jobs, never
`--failed`, and `CLAUDE.md` says the same for `test` and `test-macos`. Nor is the
persistent refusal (#354): its cause is unknown, and the remedy line points to a hand
merge.

## Testing

- New `tests/scripts/auto_merge_merge.bats`, with a fake `gh` that logs one argument per
  line per call and replays a scripted sequence of (exit, message) responses, writing
  every failure message to stderr only and a success message to stdout, and a fake `sleep`
  on `PATH` that logs its argument and returns at once. Cases: merged on the first call
  (1 call, exit 0, no sleep); refused then merged with `AUTO_MERGE_RETRY_DELAY=5` (2 calls,
  exit 0, sleep log `5`); refused three times with the delay unset (3 calls, exit 1, sleep
  log `30` twice, the remedy line naming the real PR number and SHA); `Head branch was
  modified` (1 call, exit 1); refused then `Head branch was modified` (2 calls, exit 1); gh
  exits 1 with no output (1 call, exit 1); only `<pr>` given (0 calls, exit 1); no arguments
  (0 calls, exit 1); the logged argv is exactly
  `pr merge <pr> --squash --match-head-commit <sha>`. The refused-three-times case also
  asserts exactly 3 lines matching
  `^attempt [1-3]/3 at [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$`.
- A CI-file assertion, parsed per job like `tests/scripts/ci_runner_pins.bats`, that the
  `auto-merge` job's merge step reads `scripts/auto-merge-merge.sh` with
  `git show "${BASE_SHA}:scripts/auto-merge-merge.sh"`, runs it with `PR_NUMBER` and
  `HEAD_SHA`, falls back to the single direct merge, that the job's `if:` skips drafts, that
  no step in the job passes `--auto`, and that `scripts/auto-merge-merge.sh` is tracked in
  the repo.

## Requirements

- **R1.** The `auto-merge` job's `if:` is `github.event_name == 'pull_request' && github.event.pull_request.draft == false`.
- **R2.** `scripts/auto-merge-merge.sh <pr> <head_sha>` runs `gh pr merge <pr> --squash --match-head-commit <head_sha>` and exits 0 when gh exits 0.
- **R3.** The script reads gh's stdout and stderr together; when that output contains `base branch policy prohibits the merge` it retries, at most 3 gh calls in total, sleeping `AUTO_MERGE_RETRY_DELAY` seconds (default 30) between calls, and after the third refusal prints `still refused after 3 attempts: merge by hand with gh pr merge <pr> --squash --match-head-commit <sha>, or re-run all jobs, never failed-only` with the real values and exits 1.
- **R4.** Any other gh failure, including one with no output, makes the script exit 1 after that call, printing gh's output.
- **R5.** With fewer than two arguments (none, or `<pr>` alone) the script prints a usage line, makes no gh call and exits 1.
- **R6.** The `auto-merge` job's merge step sets `BASE_SHA` from `github.event.pull_request.base.sha`, writes `git show "${BASE_SHA}:scripts/auto-merge-merge.sh"` to a file under `RUNNER_TEMP` and runs it with `bash` and `"${PR_NUMBER}" "${HEAD_SHA}"`; when the base commit has no such file it runs the single `gh pr merge "${PR_NUMBER}" --squash --match-head-commit "${HEAD_SHA}"`. It keeps `if: steps.hold.outputs.merge == 'true'`, and its comment gives the two reasons the merge is not `--auto`, why the script is read from the base commit, and that removing the script turns the retry off. The fallback's message says the retry is off. The CI-file test asserts `scripts/auto-merge-merge.sh` is tracked.
- **R7.** The bats fake `gh` writes every failure message to stderr only, a fake `sleep` on `PATH` logs its argument, and the cases are exactly: merged first call (no sleep); refused then merged with `AUTO_MERGE_RETRY_DELAY=5` (sleep log `5`); refused three times with the delay unset (sleep log `30` twice, remedy line); `Head branch was modified`; refused then `Head branch was modified`; exit 1 with no output; `<pr>` alone; no arguments; logged argv; and the refused-three-times case asserts exactly 3 `attempt` lines.
- **R8.** `tests/bats-files.txt` lists `tests/scripts/auto_merge_merge.bats`.
- **R9.** `CLAUDE.md`'s `auto-merge` bullet says the job skips drafts, retries only the policy refusal, and runs the merge script from the base commit; the backlog row "Auto-merge refused #294 with every required check green" is removed.
- **R10.** Before each gh call the script prints `attempt <n>/3 at <UTC time>`, the time in `date -u +%Y-%m-%dT%H:%M:%SZ` form.
- **V1.** The first draft PR opened after the merge shows `auto-merge` as skipped, and its ready run merges through the base-commit script (its log shows an `attempt 1/3` line).
- **V2.** An ai-config backlog row records that `finishing-a-development-branch` has no branch for a PR that ends green but unmerged.
- **V3.** On each of the next policy refusals, read the `attempt` timestamps and record time-to-success in the Backlog, and check the log's refusal text still contains `base branch policy prohibits the merge`; if the next 2-3 timing refusals still fail after 60 s, propose deleting the retry.
- **N1.** No `--auto` flag anywhere in `ci.yml`, and `allow_auto_merge` stays false.
- **N2.** No change to which jobs `auto-merge` needs, nor to branch protection's required checks.
- **N3.** No retry of any gh error other than `base branch policy prohibits the merge`.
- **N4.** The gate keeps running from the base commit (`git show "${BASE_SHA}:scripts/auto-merge-gate.sh"`), and `scripts/auto-merge-gate.sh` is not changed.
- **N5.** The merge step never runs the PR checkout's `scripts/auto-merge-merge.sh`.

## Amendments

- adds R11: A non-empty `AUTO_MERGE_RETRY_DELAY` that is not a non-negative integer makes the script print a usage line, make no gh call and exit 1. — Task 1 code review: `AUTO_MERGE_RETRY_DELAY=abc` made `sleep` fail and all three attempts run in 0.03 s; fail closed instead.
- R7 -> The bats fake `gh` writes every failure message to stderr only, a fake `sleep` on `PATH` logs its argument, and the cases are exactly: merged first call (no sleep); refused then merged with `AUTO_MERGE_RETRY_DELAY=5` (sleep log `5`); refused three times with the delay unset (sleep log `30` twice, remedy line); `Head branch was modified`; refused then `Head branch was modified`; exit 1 with no output; `<pr>` alone; no arguments; logged argv; a non-numeric `AUTO_MERGE_RETRY_DELAY` (0 calls, exit 1); a `not mergeable` merge-conflict message (1 call, exit 1); and the refused-three-times case asserts exactly 3 `attempt` lines. — adds the R11 case and, after test-quality-review, a conflict case that shares `is not mergeable:` with the refusal.

## Multi-Lens Review

Reviewed at commit: `286e6228` (Step 7 self-review commit, before Step 8 dispatch)

### Goal-Fit

Finding: Worth building, small. The retry changes an outcome (merged vs not) and passes the reads-it test. The draft verdict changes no merge outcome: `auto-merge` is not a required context, so a red draft run only colours the check. A job-level `!github.event.pull_request.draft` (as ai-config's `ci.yml` does) gives the same result without the jq schema change or R1's new way for the gate to go red. The "#294 was also `UNSTABLE`" aside does not explain its refusal: `UNSTABLE` from a non-required check does not block; the stranded required checks do. Also raised the stderr gap (see Risk) and a missing gh-exit-1-with-empty-output case.
Assumption: the policy refusal clears within about 60 s. Orchestrator measured after the round: ai-config's identical 3 x 30 s retry, last 400 PR runs (2026-06-13 to 2026-11-09), refused in 2 jobs. Run 41102075051 (2026-10-30) was refused at 18:01:42Z and 18:02:13Z and merged on attempt 3. Run 39279301026 (2026-10-19) was refused three times (16:30:45Z to 16:31:47Z) and failed; dotfiles #354 was refused the same day at 16:42Z, so that day looks like a longer GitHub-side delay. One of two cleared inside the window.
Disposition: Addressed (operator "Yes", 2026-11-10) — draft handling moved to a job-level `if:` (R1), gate unchanged (N4); stderr capture and the empty-output case added (R3, R4, R7); the #294 `UNSTABLE` aside corrected. Assumption accepted on the ai-config measurement (1 of 2 refusals cleared inside 60 s); 3 x 30 s kept.

### Ergonomics

Finding: (1) A held-green draft leaves the agent stuck: `finishing-a-development-branch` says "once all checks pass and the PR auto-merges" with no branch for "all green, PR still open"; the bot hold already has the gap and drafts are more frequent. Cheap fix: surface the hold on the checks page; better: the skill checks `gh pr view <n> --json state,isDraft` after the watch (an ai-config backlog row). (2) gh writes the refusal to stderr; if the fake `gh` writes to stdout and the script captures stdout only, every case passes and the retry never fires in CI. The fake must emit on stderr and the script must capture `2>&1`; add a gh-exit-1-with-empty-output case. (3) Cosmetic: `ready_for_review` re-runs the whole workflow, not the job.
Assumption: same as Goal-Fit (refusal clears within 60 s); see the measurement there.
Disposition: (1) Accepted, reason: the skill is in ai-config; filed as an ai-config backlog row (V2). (2) Addressed — fake writes failures to stderr only, script captures `2>&1`, empty-output case added (R3, R4, R7). (3) Addressed — wording now says the trigger re-runs the whole workflow. Operator "Yes", 2026-11-10.

### Risk

Finding: (1) Load-bearing: the stderr gap above; confirmed from run 39279309044 attempt 2 and run 32680501470, where the refusal is the step's error output. R5/R6 must say the match covers stderr. (2) Of the 4 policy refusals only #241 and #354 are timing; #294 and #414 were stranded failed-only re-runs that a retry cannot fix (it waits 60 s, then fails as today). (3) Section 2's trust reason is wrong in its stated mechanism: `ci.yml` is guarded by the `workflows` token scope and `scripts/` is not. No new surface in effect, because the merge runs only after the base-commit gate writes `merge=true`; the prose should say that. (4) No new failure from head movement or the draft hold. (5) Add cases: gh exit 1 with empty output (1 call, exit 1); refused then `Head branch was modified` (2 calls, exit 1), proving N3 mid-loop.
Assumption: same as Goal-Fit; see the measurement there.
Disposition: Addressed (operator "Yes", 2026-11-10) — (1) stderr capture (R3, R7); (2) acknowledged in Problem, failed-only re-runs stay out of scope; (3) trust paragraph rewritten around the base-commit gate; (5) both cases added (R7).

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.

### Round 2 (all three lenses, revised design)

Reviewed at commit: `d5dbcd78`. Lenses were told the round-1 section is history.

#### Goal-Fit

Finding: Worth building; every mechanism passes the reads-it test. (1) #354 is not a timing refusal: attempt 1 was also refused (15:48:44Z, 9 s after `test-macos`) and attempt 2, a full re-run, at 16:42:24Z, so it persisted at least 54 min. ai-config run 39279301026 is the same branch (`feat/python-hold`, ai-config#316); the operator merged ai-config#316 at 16:45:23Z and dotfiles#354 at 16:45:28Z. One persistent event on two repos, cause unknown, so "one of two cleared inside 60 s" is really one of one timing case. (2) Every test case runs with `AUTO_MERGE_RETRY_DELAY=0`, so a script that never sleeps passes all of them; add a case with a PATH-mocked `sleep` that logs its argument (unset delay: `30`, twice). (3) If the cause stays unknown, print a timestamp on every attempt so future refusals settle the window.
Assumption: the refusal is mostly a short propagation delay. Orchestrator check: the persistent event is not the workflows-permission refusal, since #354 touched no `.github/workflows/` file while #241 and #414 did and still merged by `github-actions`.
Disposition: Addressed (Operator "yes", 2026-11-10.) — #354 restated as persistent in Problem; fake `sleep` cases (R7); `attempt` timestamps (R10, V3).

#### Ergonomics

Finding: (1) #414 is misclassified: attempt 2 re-ran every job (all carry `run_attempt` 2) and was refused 9 s after `test-macos`, as was attempt 1, so #414 is a timing refusal; #294 alone was failed-only. (2) After the third refusal the script gives no remedy, and the reflex ("Re-run failed jobs") is #294's pattern, which can never succeed. Print one line naming the fixes: merge by hand with `gh pr merge <pr> --squash --match-head-commit <sha>`, or re-run all jobs, never failed-only; assert it in bats. (3) The draft skip removes the red signal a draft gives today.
Assumption: an agent finishing a draft runs `gh pr ready` before `gh pr checks --watch`. Orchestrator check: `finishing-a-development-branch` says to update an existing draft's body "before `gh pr ready`", so finishing a draft marks it ready first; the skipped run is replaced by the `ready_for_review` run.
Disposition: (1) Addressed — #414 restated as timing. (2) Addressed — remedy line (R3) asserted in bats (R7). (3) Accepted — the finishing skill runs `gh pr ready` before the watch, so the `ready_for_review` run replaces the skipped one. Operator "yes", 2026-11-10.

#### Risk

Finding: (1) The retry rescues only timing cases; drop any wording that implies a failed-only re-run (#294) is fixed. (2) The trust argument is weaker than stated: with `pull-requests: write` and `merge=true`, a PR-edited `scripts/auto-merge-merge.sh` could merge a different, held PR, or drop `--match-head-commit`. Not an escalation for anyone with push access (same-repo authors already run PR code with `contents: write` in `test` and `powershell`), but it breaks the base-commit isolation the gate relies on. Cheap symmetry: run the merge script from `git show "${BASE_SHA}:scripts/auto-merge-merge.sh"` too, falling back to a single direct merge when the base has none. (3) The job `if:` reads the event payload: re-running a draft-era run now skips `auto-merge` for good (re-run the `ready_for_review` run instead); converting to draft mid-run fails once as today; `cancel-in-progress` keeps the newest payload. No hazard.
Assumption: the timing refusal clears in seconds; settle it by recording time-to-success on the next refusals, and delete the retry if the next 2-3 still fail after 60 s.
Disposition: Addressed (Operator "yes", 2026-11-10.) — (1) Problem no longer implies #294 is fixed; (2) merge script read from the base commit with a single-merge fallback (Design 2, 3; R6, N5); assumption recorded as V3. Re-review scoped to Risk on the rewritten Design 2 and 3.

### Round 3 (Risk only, Design 2 and 3)

Reviewed at commit: `8f37fa52`.

Finding: No design flaw. (1) R5 versus R7: the missing-argument case did not say how many
arguments it passes; a script checking only `$1` passes a zero-argument test and, given
`<pr>` alone, would merge with `--match-head-commit ""`. (2) The fallback cannot tell an
absent file from another `git show` failure; after the hold step's fetch absence is the
only realistic cause and the fallback is today's merge, so it admits nothing new. But a
later PR deleting or renaming the script turns the retry off silently, and the CI-file
assertion still passes. (3) "One `attempt` line per gh call" named no case. Confirmed:
the base commit is present in the merge step (the hold step's
`git fetch --depth=1 origin "${BASE_SHA}"`); #354 refused at 15:48 and 16:42 (both
jobs `run_attempt` 2 on the second), merged by `brujack` at 16:45:28Z; no R contradicts
an N; a PR changing the script is merged by the base copy, as intended.
Assumption: gh's refusal text stays `base branch policy prohibits the merge` on
`ubuntu-latest`; if reworded, the retry never fires and every fake-gh case still passes.
Confirm against the next real refusal's log.
Disposition: Addressed (operator "yes", 2026-11-10) — (1) `<pr>`-alone and no-argument
cases (R5, R7); (2) fallback message and comment say the retry is off, CI-file test
asserts the script is tracked (R6); (3) pinned to the refused-three-times case, exactly 3
lines (R7). Assumption accepted: ai-config matches the same substring; V3 now checks the
text. No further round: the changes are test and wording only.

## Spec alignment (2026-11-10)

- spec: docs/superpowers/specs/2026-11-10-auto-merge-draft-hold-retry-design.md
- anchor: 9248f31ca19028c4478a97b54edf4d4e91b39db4
- in scope: R1, R2, R3, R4, R5, R6, R7, R8, R9, R10, R11
- out of scope: none

### Findings

| ID | Reviewer | Verdict | Reason | Amendment |
| --- | --- | --- | --- | --- |

### Reviewed

- none

### Verifications

- V1: no evidence recorded
- V2: ai-config master 8a995ca2 adds the Backlog row: finishing-a-development-branch has no branch for a PR that ends green but unmerged.
- V3: no evidence recorded
