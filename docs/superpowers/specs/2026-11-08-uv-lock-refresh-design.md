# Weekly uv.lock refresh PR

## Problem

Nothing re-asks the resolver whether the locked answer is still current. `uv sync --frozen`
makes installs reproducible, and `uv lock` against an existing lock keeps resolutions the
constraints no longer require (backlog: "Nothing ever re-asks the resolver"). Every `uv.lock`
change since 2026-09-29 was reactive: 8 of the last 12 lock commits (#297, #302, #303, #356,
#364, #422, #423, #425) were bumps for Dependabot alerts.

Measured 2026-11-08 at master `cb57dfb6`, in a `git archive` copy of `pyproject.toml` and
`uv.lock`, with uv 0.13.7 (population: this repo's lock, one point in time): a real
`uv lock --upgrade` exits 0, resolves 269 packages and prints 103 `Updated`, 1 `Added`
(`cloudpickle`) and 1 `Removed` (`greenlet`) lines. `--dry-run` prints `Update`/`Add`/`Remove`
instead, and omits the `Removed` line. With `--exclude-newer` set 14 days back, the same run
changes 96 packages (Step 8 goal-fit lens, same copy).

Renovate cannot do this refresh. It runs with `enabledManagers` `github-actions`, `npm` and
`pep621` and no `lockFileMaintenance`. Across its whole history it opened two PRs touching
`uv.lock` (#350 and #352, both the `requires-python` 3.15 bump, both closed with `test`,
`test-macos` and `bash-coverage` failed). Mend-hosted Renovate cannot run
`make sync-requirements-ci`, and `make check-requirements-ci` fails any lock change whose five
renderings were not regenerated.

The backlog row ("Automate the weekly `uv lock --upgrade` and `make sync-requirements-ci`
refresh") named the blocker: a PR opened with a workflow's `GITHUB_TOKEN` starts no
`pull_request` workflows, so CI never runs on it on its own.

## Decision

A scheduled workflow opens the PR with `GITHUB_TOKEN`, and the operator starts CI when
reviewing (operator's choice, 2026-11-08, over a GitHub App token, a fine-grained PAT and a
local cadence agent). The reasoning:

- `scripts/auto-merge-gate.sh` holds this PR for a human whichever identity opens it. Its
  `_gate_verdict` checks the bot rule first (lines 47-50): a bot-authored PR without
  `automerge-ok` is held as `bot PR (<login>) lacks automerge-ok`. The lock-only rule ("uv.lock
  changed without pyproject.toml") would hold it too, but is reached only after `automerge-ok`
  is applied. The other identity options buy only "CI has already run when you look".
- No new credential exists. The workflow's write scope is its own job's `GITHUB_TOKEN`.
- `ci.yml` triggers on `pull_request` types `opened, synchronize, reopened,
ready_for_review, labeled`. A close and reopen by the operator, or the operator applying any
  label, is a user event, so it should start CI: `gh pr close <n> && gh pr reopen <n>`.
- **This has never been exercised in this fleet.** ai-config's learnings-aggregator was cited
  as precedent, but every scheduled run from 2026-07-03 to 2026-11-03 failed, and no
  github-actions-authored PR exists in ai-config or dotfiles (Step 8 ergonomics lens). R1 makes
  proving it the first piece of work, before anything else is built.
- The repo setting "Allow GitHub Actions to create and approve pull requests" is on
  (`can_approve_pull_request_reviews: true`, read 2026-11-08). Master protection has required
  checks and `enforce_admins: false`; a `GITHUB_TOKEN` push to master is rejected for lack of
  them, so the job can reach only its own branch.

### Release-age cooldown

The refresh resolves with `--exclude-newer` set to 14 days before the run, matching Renovate's
`"minimumReleaseAge": "14 days"` (`renovate.json`). Without it a Monday run takes releases
published minutes earlier, and the merged lock reaches every machine's `-t update`
(`uv sync --frozen`). Nothing in CI installs `requirements-runtime-ci.txt` (ansible,
ansible-core, ansible-lint, molecule), and ai-config CI installs the other renderings live
from master, with `--require-hashes` pinned to this same resolution.

`--exclude-newer` writes the cutoff into `uv.lock` as `[options] exclude-newer`, and a bare
`uv lock --check` (`make check-lock`) then rejects the lock: "Resolving despite existing
lockfile due to removal of global exclude newer" (Step 8 round 2, reproduced). So the cutoff run
is followed by a plain `uv lock`, which drops the option and keeps every pin. Measured at
`cb57dfb6` with uv 0.13.7: 0 of 269 `name`/`version` pairs changed, no `[options]` left, and
`uv lock --check` rc 0. Reproduced offline on a dependency-free fixture project: `--check`
rc 1 with the option, rc 0 after the plain `uv lock`.

When a `pyproject.toml` floor requires a release younger than the cutoff, the cutoff resolution
fails outright. Measured with a 90-day cutoff at `cb57dfb6`: "only checkov<=3.3.9 is available
and dotfiles-venv:runtime depends on checkov>=3.3.13". The run then fails and the failure issue
carries uv's message naming the package (operator's choice, 2026-11-08). It clears without
action once that release is 14 days old, so at most two weekly runs fail.

### Components

**`scripts/refresh-uv-lock.sh`** does the lock work. Given a body path as `$1`:

1. Compute the cutoff: the reference time minus 14 days, UTC, RFC 3339. `REFRESH_UV_LOCK_NOW`
   is the test seam for the reference time; the default is now.
2. Run `uv lock --upgrade --exclude-newer <cutoff>`, capturing its `Updated`/`Added`/`Removed`
   lines. On failure, exit 1 and print uv's output.
3. Run plain `uv lock` to drop `[options] exclude-newer`.
4. If `uv.lock` is byte-identical to before step 2, print `no changes` and exit 0.
5. If the lock changed but no `Updated`/`Added`/`Removed` line was captured, exit 1: uv's output
   format moved and the PR would carry an empty change list.
6. Run `make sync-requirements-ci`, then `REQUIRE_TOOLS=1 make check-lock` and
   `REQUIRE_TOOLS=1 make check-requirements-ci`, so a missing uv fails rather than skips. If
   either fails, exit 1 naming the step.
7. Write the PR body to `$1`. It contains the cutoff, the change count and the captured lines,
   plus the review steps:
   - start CI with `gh pr close <n> && gh pr reopen <n>`;
   - read the list;
   - merge manually with `gh pr merge <n> --squash`, because the auto-merge gate holds bot PRs
     and a label only re-runs CI;
   - if the PR conflicts, the next weekly run replaces it, or run
     `gh workflow run uv-lock-refresh.yml` to replace it now.
8. Print `changed` and exit 0. The workflow branches on that word, not on the exit status
   alone.

The script never commits or calls `gh`, and makes no remote writes.

**`scripts/uv-lock-refresh-pr.sh`** decides what to do about an existing refresh PR, so its
branches are testable. It takes `$1`, the path of a JSON array from
`gh pr list --head chore/uv-lock-refresh --state open --json number,mergeable,isCrossRepository`,
and prints one word:

- `none`: no same-repository PR. Fork PRs (`isCrossRepository: true`) are ignored, because the
  repo is public and a fork can name its branch `chore/uv-lock-refresh`.
- `keep <n>`: a same-repository PR whose `mergeable` is `MERGEABLE`.
- `replace <n>`: a same-repository PR whose `mergeable` is `CONFLICTING`.
- `unknown <n>`: `mergeable` is `UNKNOWN`. GitHub computes it lazily, and an idle PR reads
  `UNKNOWN` on the first query. Measured 2026-11-08 on five idle fleet PRs: all `UNKNOWN`, then
  `MERGEABLE` 20 seconds later.

More than one same-repository PR exits 1. Malformed JSON exits 2.

**`.github/workflows/uv-lock-refresh.yml`**, one job:

- `on: schedule: - cron: "0 6 * * 1"` (Monday 06:00 UTC, after Renovate's "before 5am on
  monday" window) and `workflow_dispatch`.
- Workflow-level `permissions: contents: read`. The repo's default workflow permission is
  `write`, so this line is load-bearing. Job-level `contents: write`, `pull-requests: write`,
  `issues: write`.
- `timeout-minutes: 10`; `runs-on: ubuntu-latest`; `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: true`,
  like every job in `ci.yml`.
- Checkout pinned by SHA (ADR-0006). uv is installed with the same `UV_VER` and `UV_SHA256` as
  `ci.yml`'s Linux `test-shard` job (`ci.yml` also carries a macOS digest), verified with
  `sha256sum -c` (ci-002).
- Steps:
  1. Run `uv-lock-refresh-pr.sh`. On `unknown`, re-query up to 6 times, 10 seconds apart; still
     `unknown` fails the job.
  2. On `keep`, stop with a notice.
  3. On `none` or `replace`, run `refresh-uv-lock.sh`.
  4. Only after it prints `changed`:
     - on `replace`, comment on the old PR and close it;
     - commit exactly `uv.lock` and the five renderings to `chore/uv-lock-refresh` on top of
       current `master` (force-update of that branch on origin);
     - run `gh pr create --base master --head chore/uv-lock-refresh --title
       "chore(deps): refresh uv.lock" --body-file <body>`.
  5. On `no changes` with a `replace`, comment on the conflicted PR that master already holds
     the current resolution, and close it.
- An `if: failure()` step opens an issue titled `uv.lock refresh failed` with the run URL and the
  last 40 lines of the failing step's log. If an open issue with that title exists, it comments
  there instead. ai-config's aggregator failed for five months with only the Actions tab to show
  it.

The force-update replaces whatever `chore/uv-lock-refresh` held. It runs only after the open-PR
rule and after a successful refresh, so what it can destroy is a closed refresh PR's branch,
including any commit the operator added there. That is accepted: a closed refresh is
abandoned, and the run re-derives the lock from `master`.

### Failure handling

A failed step fails the job, nothing is written to origin or closed, and the failure step opens
or updates the issue. A resolution that `check-lock` or `check-requirements-ci` rejects never
reaches a PR. A run that finds a mergeable refresh PR does nothing.

### First task: prove the CI path

Before any other change, a throwaway probe settles whether the design works at all.
1. `.github/workflows/probe-token-pr.yml` on a branch `probe/token-pr`, triggered by `on: push`
   for that branch, commits a one-line change with `GITHUB_TOKEN` to `probe/token-pr-head` and
   opens a PR against `master`.
2. The operator runs `gh pr close <n> && gh pr reopen <n>`.
3. Check `gh pr checks <n>` and `gh api repos/brujack/dotfiles/commits/<sha>/check-runs`. The
   required contexts must all appear on the head SHA: `test`, `lint-macos`, `test-macos`,
   `powershell`, `secret-scan` and `renderings-install`.
4. Cleanup, whatever the result:
   - close the PR;
   - delete both probe branches on origin;
   - nothing reaches master.

The auto-merge gate holds the probe PR as a bot PR, so it cannot merge itself.

## Testing

- `tests/scripts/refresh_uv_lock.bats` drives `refresh-uv-lock.sh` through a `uv` stub
  (`_UV_BIN` seam) and a stubbed `make`, against a fixture root (`REFRESH_UV_LOCK_ROOT` seam).
  The stub's change lines are copied from the real capture above. Cases:
  - lock unchanged: `no changes`, no body;
  - lock changed and checks pass: `changed`, the body lists every stub line plus `gh pr close`,
    `gh pr reopen`, `gh pr merge` and `gh workflow run uv-lock-refresh.yml`;
  - lock changed with no change lines: non-zero, no body;
  - the upgrade fails: non-zero, uv's message printed, no body;
  - a check fails: non-zero, names the check;
  - the stubbed `make` sees `REQUIRE_TOOLS=1` for both checks;
  - with `REFRESH_UV_LOCK_NOW` fixed, the stub receives exactly the cutoff 14 days earlier, and a
    plain `uv lock` call follows the cutoff call.
- One real-uv case, skipped only when `uv` is absent, runs offline (`UV_OFFLINE=1`) on a
  dependency-free fixture project. `uv lock --exclude-newer` makes `uv lock --check` fail, and
  after the script's plain `uv lock` it passes. A stub cannot show either half.
- `tests/scripts/uv_lock_refresh_pr.bats` gives `uv-lock-refresh-pr.sh` fixture JSON for each
  word: empty array, fork-only, `MERGEABLE`, `CONFLICTING`, `UNKNOWN`, two same-repo PRs (exit
  1) and malformed JSON (exit 2).
- `tests/scripts/uv_lock_refresh_workflow.bats` parses the workflow per job:
  - the cron and `workflow_dispatch`, and no other trigger;
  - workflow-level `contents: read`; job permissions exactly the three named;
  - every `uses:` pinned to a 40-hex SHA;
  - a `sha256sum -c` line;
  - `UV_VER`/`UV_SHA256` equal to `ci.yml`'s `test-shard` values, read from that job alone;
  - `timeout-minutes: 10`;
  - the PR-rule script runs before the refresh script, the close follows the refresh, and the
    `if: failure()` step names the issue title.
- All three new files are added to `tests/bats-files.txt`.

## Requirements

- **R1.** `[PR1]` Before any other change, the probe in "First task" runs from a `push`-triggered workflow on `probe/token-pr`. Its GITHUB_TOKEN-opened PR, after the operator closes and reopens it, shows `test`, `lint-macos`, `test-macos`, `powershell`, `secret-scan` and `renderings-install` on its head SHA, or implementation stops and the identity decision returns to the operator. The probe PR is closed and both probe branches are deleted on origin either way.
- **R2.** `[PR1]` `scripts/refresh-uv-lock.sh` runs `uv lock --upgrade --exclude-newer <cutoff>` with `<cutoff>` exactly 14 days before the reference time (`REFRESH_UV_LOCK_NOW`, default now, UTC), then plain `uv lock`, then `make sync-requirements-ci`, `REQUIRE_TOOLS=1 make check-lock` and `REQUIRE_TOOLS=1 make check-requirements-ci`; it never commits, never calls `gh` and makes no remote writes.
- **R3.** `[PR1]` When `uv.lock` is byte-identical after both `uv lock` runs, the script prints `no changes`, writes no body file and exits 0.
- **R4.** `[PR1]` When the lock changed, at least one `Updated`/`Added`/`Removed` line was captured and both checks pass, the script prints `changed`, exits 0, and writes a body file containing the cutoff, every captured line, `gh pr close`, `gh pr reopen`, `gh pr merge` and `gh workflow run uv-lock-refresh.yml`.
- **R5.** `[PR1]` When the lock changed but no `Updated`/`Added`/`Removed` line was captured, or any `uv` or `make` step fails, the script exits non-zero with a message naming the cause (uv's own output when `uv lock` fails), and no body file is written.
- **R6.** `[PR1]` `scripts/uv-lock-refresh-pr.sh` prints `none` when no PR in its input has `isCrossRepository` false, otherwise `keep <n>`, `replace <n>` or `unknown <n>` for `MERGEABLE`, `CONFLICTING` or `UNKNOWN`; it exits 1 for more than one same-repository PR and 2 for malformed input.
- **R7.** `[PR1]` `.github/workflows/uv-lock-refresh.yml` triggers on `schedule` cron `0 6 * * 1` and on `workflow_dispatch`, and on nothing else.
- **R8.** `[PR1]` The workflow sets workflow-level `permissions: contents: read`; its job declares exactly `contents: write`, `pull-requests: write` and `issues: write`, `timeout-minutes: 10` and `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: true`; every `uses:` is pinned to a 40-hex SHA.
- **R9.** `[PR1]` The workflow installs uv with the `UV_VER` and `UV_SHA256` of `ci.yml`'s `test-shard` job and verifies the download with `sha256sum -c`; a test fails when the two differ.
- **R10.** `[PR1]` On `unknown` the workflow re-queries up to 6 times, 10 seconds apart, and fails if still `unknown`; on `keep` it stops before the refresh; on `replace` it closes the old PR only after the refresh prints `changed` or `no changes`, never before.
- **R11.** `[PR1]` On `changed`, the workflow commits exactly `uv.lock`, `requirements-ci.txt`, `requirements-runtime-ci.txt`, `requirements-ci-test.txt`, `requirements-ci-mutation.txt` and `requirements-ci-audit.txt` to `chore/uv-lock-refresh` on top of current `master`, and opens a PR against `master` titled `chore(deps): refresh uv.lock` with the script's body.
- **R12.** `[PR1]` When any step fails, the workflow opens an issue titled `uv.lock refresh failed` containing the run URL and the failing step's last 40 log lines, or comments them on the open issue with that title.
- **R13.** `[PR1]` All three new bats files are listed in `tests/bats-files.txt`, and the backlog row "Automate the weekly `uv lock --upgrade` and `make sync-requirements-ci` refresh" is removed.
- **V1.** After merge, run the workflow once with `workflow_dispatch`. It must open a PR from `chore/uv-lock-refresh` whose diff touches only the six files in R11 and whose `uv.lock` has no `[options]` block. The auto-merge gate must hold it as `bot PR (...) lacks automerge-ok`. After the operator's close and reopen, all six required checks must pass on it.
- **V2.** A second `workflow_dispatch` while that PR is open and mergeable must open no second PR.
- **N1.** No change to `ci.yml` triggers, `renovate.json` or `scripts/auto-merge-gate.sh`.
- **N2.** No new repository secret, and no token other than the job's `GITHUB_TOKEN`.
- **N3.** The workflow never merges, approves or labels a PR, never closes a PR that is not a same-repository `CONFLICTING` refresh PR, and never writes to `master`.
- **N4.** `pyproject.toml` gets no `exclude-newer` setting; the cooldown applies to the scheduled refresh only.

## Multi-Lens Review

Reviewed at commit: `39932f11` (round 1, before revision)

### Goal-Fit

Finding: Worth building, but the refresh had no release-age cooldown (`renovate.json` sets `minimumReleaseAge` 14 days; about 9 packages per refresh would be younger), and dotfiles CI never installs `requirements-runtime-ci.txt`. R3 named dry-run words (`Update`) where the real command prints `Updated`/`Added`/`Removed`, and no test failed on an empty change capture. V1 expected the lock-only hold message, but the gate's bot rule fires first.
Assumption: The operator handles each refresh PR within about a week; otherwise one stale PR blocks every later refresh. Settled by the operator's stale-PR decision below.
Disposition: Addressed (operator, 2026-11-08): `--exclude-newer` 14 days; `Updated`/`Added`/`Removed` parsing with an empty-capture refusal; V1 corrected; conflicted PRs are replaced.

### Ergonomics

Finding: The cited precedent (ai-config's learnings-aggregator) has failed every scheduled run since 2026-07-03 and no github-actions PR exists in the fleet, so close/reopen is unproven; a failed run notifies nobody; a refresh PR made conflicting by a Dependabot bump could only be cleared by hand, and the recovery was undocumented; V1's hold message was wrong.
Assumption: A user's close/reopen of a GITHUB_TOKEN-opened PR starts the six required checks and they count for protection. Settled by R1's probe before anything is built.
Disposition: Addressed (operator, 2026-11-08): R1 probe first; failure opens or updates a `uv.lock refresh failed` issue; a `CONFLICTING` refresh PR is closed and replaced; the body carries the recovery commands.

### Risk

Finding: Contained push scope and force-push; the real exposure was supply chain (no cooldown while ai-config CI installs the renderings live from master, `--require-hashes` from the same resolution) and a vacuous pass (`make check-requirements-ci` skips and exits 0 without uv unless `REQUIRE_TOOLS=1`). V1 wrong; R7 ambiguous because `ci.yml` has Linux and macOS `UV_SHA256` values. Workflow-level `contents: read` is load-bearing because the repo default is `write`.
Assumption: A weekly bump that passes dotfiles CI leaves ai-config's and state-ledger's CI green at merge; nothing in dotfiles CI runs the consumers' suites.
Disposition: Addressed (operator, 2026-11-08) for the cooldown, `REQUIRE_TOOLS=1`, V1, the Linux-job pin and a test on workflow-level `contents: read`. The consumer-suite assumption is not addressed by this design; the 14-day cooldown narrows it and the operator reviews every refresh PR.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.

### Round 2

Reviewed at commit: `49e39cbb`

#### Goal-Fit

Finding: The cooldown added in round 1 made every changed run fail: `--exclude-newer` writes `[options] exclude-newer` into `uv.lock`, and bare `uv lock --check` (`make check-lock`, also a `test` prerequisite) then rejects it. Reproduced at `cb57dfb6`. The stubbed tests could not see it.
Assumption: That the operator's close and reopen of a GITHUB_TOKEN-opened PR runs all six required checks on its head SHA; settled by R1's probe.
Disposition: Addressed (operator, 2026-11-08): a plain `uv lock` follows the cutoff run (measured: 0 of 269 pins changed, `--check` rc 0), with an offline real-uv test that reproduces both the failure and the fix.

#### Ergonomics

Finding: `mergeable` is computed lazily: five idle fleet PRs read `UNKNOWN`, then `MERGEABLE` 20 s later, so "UNKNOWN means stop" left the conflicted-PR replacement nearly dead and silent. The R1 probe needed a workflow merged to master. The body offered a label as a merge route.
Assumption: Same as goal-fit (R1).
Disposition: Addressed (operator, 2026-11-08): poll up to 6 times 10 s apart and fail if still `UNKNOWN`; the PR rule moved into a tested script; a push-triggered probe on a throwaway branch; the body says merge manually.

#### Risk

Finding: Same `[options]` defect; the conflicted PR was closed before a refresh that always failed; a fork PR named `chore/uv-lock-refresh` matched the branch filter in this public repo; the R1 trigger was impossible as written. A floor demanding a release younger than the cutoff fails the resolution (measured with a 90-day cutoff: checkov).
Assumption: That the plain `uv lock` keeps the cutoff's pins when a locked package is newer than the cutoff. Measured with a 90-day cutoff: that resolution fails outright instead (above), so the fix never runs on such input; with 14 days it kept all 269 pins.
Disposition: Addressed (operator, 2026-11-08): close only after the refresh; `isCrossRepository == false` filter; push-triggered probe with cleanup. A floor younger than the cutoff fails the run and the issue reports it (operator's choice over auto-exemption or dropping the cooldown).
