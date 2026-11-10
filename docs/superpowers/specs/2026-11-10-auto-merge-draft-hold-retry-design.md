# Auto-merge: hold drafts, retry the policy refusal

- **Date:** 2026-11-10
- **Repo:** dotfiles
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
| `the base branch policy prohibits the merge`, attempt 1     | #241 (32680501470)                                                                             | The merge ran 3 s after the last required job finished. A re-run merged it 8 min later.                                                                                                                                                                     |
| same refusal, re-run attempt                                | #354 (39279309044, attempt 2), #294 (36211991794, attempt 3), #414 (41259553982, attempt 2)    | #354 ran 4 s after the last required job. #294 and #414 were failed-only re-runs; #408 (backlog row) showed a failed-only re-run strands the earlier attempt's required checks. #294 was also `UNSTABLE` from its own failed draft-period `auto-merge` run. |

The population is this repo's `ci.yml` runs only. The timing reading for #241 and #354 is
an inference from the 3-4 s gap; ai-config measured the same refusal 40 s after the last
check on its PR #292, and a re-run merged it.

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

### 1. The gate holds drafts

`scripts/auto-merge-gate.sh` adds `isDraft` to its `gh pr view --json` fields. The jq
program treats a missing or non-boolean `isDraft` as a malformed payload (exit 1, no
decision), as it does for its other fields. A new `draft` verdict is evaluated before every
other verdict, so a draft bot PR, even one labelled `automerge-ok`, is held as a draft. On
`draft` the gate prints `draft PR -- held until marked ready`, writes `merge=false` and
exits 0. The workflow's existing `ready_for_review` trigger re-runs the job when the draft
is marked ready.

The gate runs as it exists on the base commit, so the hold applies only to PRs whose base
already contains it. The PR that adds it is judged by the old gate.

### 2. A merge script retries the policy refusal

New `scripts/auto-merge-merge.sh <pr> <head_sha>`:

- Runs `gh pr merge <pr> --squash --match-head-commit <head_sha>`.
- Exit 0 from gh: print its output, exit 0.
- Output containing `base branch policy prohibits the merge`: retry, at most 3 attempts in
  total, sleeping `${AUTO_MERGE_RETRY_DELAY:-30}` seconds between attempts. After the third
  refusal, exit 1.
- Any other failure, `Head branch was modified` included: print gh's output and exit 1
  at once.
- A missing argument: print usage, exit 1, no gh call.

It runs from the PR's checkout, not the base commit. That grants a PR nothing new: the
inline step it replaces lives in `ci.yml`, which the PR also controls, and it runs only
after the base-commit gate wrote `merge=true`. Worst case it waits 60 s, inside the job's
10-minute timeout.

### 3. `ci.yml`

The merge step's `run:` becomes `bash scripts/auto-merge-merge.sh "${PR_NUMBER}" "${HEAD_SHA}"`.
Its comment states why the merge is direct and not `--auto`, citing the two reasons above.

### 4. Out of scope

A failed-only re-run that strands required checks (#294, #408, #414) is not handled here:
`ai-config`'s `finishing-a-development-branch` already says to re-run all jobs, never
`--failed`, and `CLAUDE.md` says the same for `test` and `test-macos`.

## Testing

- `tests/scripts/auto_merge_gate.bats` (extends the existing fake-`gh` harness):
  a draft human PR is held; a draft bot PR labelled `automerge-ok` is held; a payload
  without `isDraft` exits 1 with nothing written; a string `isDraft` exits 1; a non-draft
  PR is still cleared (existing cases gain `isDraft:false`).
- New `tests/scripts/auto_merge_merge.bats`, with a fake `gh` that logs one argument per
  line per call and replays a scripted sequence of (exit, output) responses, and
  `AUTO_MERGE_RETRY_DELAY=0`: merged on the first call (1 call, exit 0); refused then merged
  (2 calls, exit 0); refused three times (3 calls, exit 1); `Head branch was modified`
  (1 call, exit 1); a missing argument (0 calls, exit 1); the logged argv is exactly
  `pr merge <pr> --squash --match-head-commit <sha>`.
- A CI-file assertion, parsed per job like `tests/scripts/ci_runner_pins.bats`, that the
  `auto-merge` job's merge step runs `scripts/auto-merge-merge.sh` with `PR_NUMBER` and
  `HEAD_SHA`, and that no step in the job passes `--auto`.

## Requirements

- **R1.** `scripts/auto-merge-gate.sh` requests `isDraft` from `gh pr view` and exits 1 without writing to `GITHUB_OUTPUT` when `isDraft` is absent or not a boolean.
- **R2.** For a PR with `isDraft: true` the gate prints `draft PR -- held until marked ready`, writes `merge=false` and exits 0 for any otherwise well-formed payload, whatever its author, labels or files.
- **R3.** For a PR with `isDraft: false` every existing gate verdict is unchanged.
- **R4.** `scripts/auto-merge-merge.sh <pr> <head_sha>` runs `gh pr merge <pr> --squash --match-head-commit <head_sha>` and exits 0 when gh exits 0.
- **R5.** When gh's output contains `base branch policy prohibits the merge`, the script retries, at most 3 gh calls in total, sleeping `AUTO_MERGE_RETRY_DELAY` seconds (default 30) between calls, and exits 1 after the third refusal.
- **R6.** Any other gh failure makes the script exit 1 after that one call, printing gh's output.
- **R7.** With fewer than two arguments the script prints a usage line, makes no gh call and exits 1.
- **R8.** The `auto-merge` job's merge step runs `bash scripts/auto-merge-merge.sh "${PR_NUMBER}" "${HEAD_SHA}"`, keeps `if: steps.hold.outputs.merge == 'true'`, and its comment gives the two reasons the merge is not `--auto`.
- **R9.** `tests/bats-files.txt` lists `tests/scripts/auto_merge_merge.bats`.
- **R10.** `CLAUDE.md`'s `auto-merge` bullet says the job holds drafts and retries only the policy refusal; the backlog row "Auto-merge refused #294 with every required check green" is removed.
- **V1.** The first draft PR opened after the merge shows `auto-merge` green with `draft PR -- held until marked ready` in its log.
- **N1.** No `--auto` flag anywhere in `ci.yml`, and `allow_auto_merge` stays false.
- **N2.** No change to which jobs `auto-merge` needs, nor to branch protection's required checks.
- **N3.** No retry of any gh error other than `base branch policy prohibits the merge`.
- **N4.** The gate keeps running from the base commit (`git show "${BASE_SHA}:scripts/auto-merge-gate.sh"`).
