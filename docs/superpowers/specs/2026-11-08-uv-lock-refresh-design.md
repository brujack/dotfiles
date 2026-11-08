# Weekly uv.lock refresh PR

- **Approved:** 2026-11-08

## Problem

Nothing re-asks the resolver whether the locked answer is still current. `uv sync --frozen`
makes installs reproducible, and `uv lock` against an existing lock keeps resolutions the
constraints no longer require (backlog: "Nothing ever re-asks the resolver"). Every `uv.lock`
change since 2026-09-29 was reactive: 8 of the last 12 lock commits (#297, #302, #303, #356,
#364, #422, #423, #425) were bumps for Dependabot alerts.

Measured 2026-11-08 at master `cb57dfb6`, in a `git archive` copy of `pyproject.toml` and
`uv.lock`, with uv 0.13.7 (population: this repo's lock, one point in time): a real
`uv lock --upgrade` exits 0, resolves 269 packages, prints 103 `Updated`, 1 `Added`
(`cloudpickle`) and 1 `Removed` (`greenlet`) lines, moves no package below its locked version,
writes no `[options]` block, and leaves `uv lock --check` at rc 0. `--dry-run` prints
`Update`/`Add`/`Remove` instead and omits the `Removed` line, so only the real run's words are
used.

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

A scheduled workflow opens or updates the PR with `GITHUB_TOKEN`, and the operator starts CI
when reviewing (operator's choice, 2026-11-08, over a GitHub App token, a fine-grained PAT and a
local cadence agent). The reasoning:

- `scripts/auto-merge-gate.sh` holds this PR for a human whichever identity opens it. Its
  `_gate_verdict` checks the bot rule first (lines 47-50): a bot-authored PR without
  `automerge-ok` is held as `bot PR (<login>) lacks automerge-ok`. The lock-only rule ("uv.lock
  changed without pyproject.toml") would hold it too, but is reached only after `automerge-ok`
  is applied. The other identity options buy only "CI has already run when you look".
- No new credential exists. The workflow's write scope is its own job's `GITHUB_TOKEN`.
- `ci.yml` triggers on `pull_request` types `opened, synchronize, reopened,
  ready_for_review, labeled`. A close and reopen by the operator is a user event, so it should
  start CI: `gh pr close chore/uv-lock-refresh && gh pr reopen chore/uv-lock-refresh`.
- **This has never been exercised in this fleet.** No github-actions-authored PR exists in
  ai-config or dotfiles, and ai-config's learnings-aggregator, which would have been the
  precedent, has failed every scheduled run from 2026-07-03 to 2026-11-03 (Step 8 round 1).
  R1 makes proving it the first piece of work.
- The repo setting "Allow GitHub Actions to create and approve pull requests" is on
  (`can_approve_pull_request_reviews: true`, read 2026-11-08). Master protection requires the
  six checks `test`, `lint-macos`, `test-macos`, `powershell`, `secret-scan` and
  `renderings-install`, with `enforce_admins: false`. A `GITHUB_TOKEN` write to master is
  rejected for lack of them, so the job can reach only its own branch.

### No release-age cooldown

Round 1 added `--exclude-newer` (14 days, matching Renovate's `minimumReleaseAge`). Rounds 2
and 3 measured that it breaks the design twice over, and the operator dropped it on
2026-11-08:

- It writes `[options] exclude-newer` into `uv.lock`, so a bare `uv lock --check`
  (`make check-lock`) rejects every changed lock. A following plain `uv lock` repairs that.
- It drops locked versions as preferences, so it downgrades every package master holds at a
  release younger than the cutoff. Measured at `cb57dfb6`: a 30-day cutoff downgrades 9
  packages and a 45-day cutoff 12, among them the Dependabot CVE fixes in tornado, certifi,
  pillow and gitpython. Replayed against upload dates, a run on 2026-10-26 would have opened a
  PR reverting #364's certifi, pillow and gitpython fixes, each shown as an ordinary
  `Updated a -> b` line.
- A `pyproject.toml` floor that needs a release younger than the cutoff fails the resolution
  outright (a 90-day cutoff: "only checkov<=3.3.9 is available").

Fresh releases are therefore admitted, and the operator's review of the listed changes is the
gate for them. The cooldown goes to the backlog with these measurements. As a guard against a
silent revert from any cause, such as a yanked release, the script refuses any run that moves a
package below master's version.

### Components

**`scripts/refresh-uv-lock.sh`** does the lock work. Given a body path as `$1`, it:

1. Runs `uv lock --upgrade`, capturing its `Updated`/`Added`/`Removed` lines. On failure it
   exits 1 and prints uv's output.
2. If `uv.lock` is byte-identical to before, prints `no changes` and exits 0.
3. If the lock changed but no `Updated`/`Added`/`Removed` line was captured, exits 1: uv's
   output format moved and the PR would carry an empty change list.
4. Checks every captured `Updated` line for a downgrade. The line is `Updated <pkg> <old> -> <new>`,
   where each side is one or more `v`-prefixed versions joined by `, `. uv prints several when a
   package has more than one locked version across resolution forks, e.g.
   `Updated six v1.15.0, v1.16.0 -> v1.16.0`, and this lock has 5 `resolution-markers` forks.
   A line is a downgrade when the highest new version is lower than the highest old version,
   compared as PEP 440 versions with `packaging.version` in a Python helper run from its own
   file (the coverage rule for long programs). A line that does not parse is treated as a
   downgrade. The script exits 1 naming each such package. A locked release that upstream yanks
   makes every run refuse until a newer one ships; the message says to add a `pyproject.toml`
   floor if that should not wait.
5. Runs `make sync-requirements-ci`, then `REQUIRE_TOOLS=1 make check-lock` and
   `REQUIRE_TOOLS=1 make check-requirements-ci`, so a missing uv fails rather than skips. If
   either fails, exits 1 naming the step.
6. Writes the PR body to `$1`: the change count, the captured lines, and the review steps:
   - start CI with `gh pr close chore/uv-lock-refresh && gh pr reopen chore/uv-lock-refresh`;
   - read the list;
   - merge manually with `gh pr merge chore/uv-lock-refresh --squash`, because the auto-merge
     gate holds bot PRs and a label only re-runs CI;
   - a later weekly run replaces this PR's contents with a fresh refresh from `master`, and
     `gh workflow run uv-lock-refresh.yml` does that now.
7. Prints `changed` and exits 0.

All `uv` and `make` output goes to stderr. The last line of stdout is the result word, and the
workflow reads only that line. The script never commits, never calls `gh` and makes no remote
writes.

**`.github/workflows/uv-lock-refresh.yml`**, one job:

- `on: schedule: - cron: "0 6 * * 1"` (Monday 06:00 UTC, after Renovate's "before 5am on
  monday" window) and `workflow_dispatch`.
- Workflow-level `permissions: contents: read`. The repo's default workflow permission is
  `write`, so this line is load-bearing. Job-level `contents: write`, `pull-requests: write`,
  `issues: write`.
- `timeout-minutes: 10`; `runs-on: ubuntu-latest`; `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: true`,
  like every job in `ci.yml`.
- `concurrency: {group: uv-lock-refresh, cancel-in-progress: false}`, so a scheduled run and a
  `workflow_dispatch` never overlap. Without it both can see no open PR and both run
  `gh pr create`.
- Before committing, `git config user.name "github-actions[bot]"` and
  `git config user.email "github-actions[bot]@users.noreply.github.com"`, as `ci.yml` does for
  its badge commits.
- Checkout pinned by SHA (ADR-0006). uv is installed with the same `UV_VER` and `UV_SHA256` as
  `ci.yml`'s Linux `test-shard` job (`ci.yml` also carries a macOS digest), verified with
  `sha256sum -c` (ci-002).
- Every step after checkout tees its output to `${RUNNER_TEMP}/<step>.log` (the pattern
  `ci.yml` already uses for `make test`), because a later step cannot read an earlier step's
  log through the API until the job ends.
- Steps:
  1. Run `refresh-uv-lock.sh` against current `master`.
  2. Find the open same-repository refresh PR:
     `gh pr list --head chore/uv-lock-refresh --state open --json number,isCrossRepository`,
     filtered to `isCrossRepository == false`. The repo is public, and a fork can name its
     branch `chore/uv-lock-refresh`. More than one match fails the job.
  3. On `changed`:
     - commit exactly `uv.lock` and the five renderings on top of current `master`;
     - force-update `chore/uv-lock-refresh` on origin to that commit;
     - if step 2 found a PR, replace its body with `gh pr edit <n> --body-file <body>`,
       otherwise run `gh pr create --base master --head chore/uv-lock-refresh --title
       "chore(deps): refresh uv.lock" --body-file <body>`.
  4. On `no changes` with an open refresh PR, comment that master already holds the current
     resolution and close it.
  5. If an open issue titled `uv.lock refresh failed` exists, comment the run URL and close it.
- An `if: failure()` step opens an issue titled `uv.lock refresh failed` with the run URL and the
  last 40 lines of the failing step's `${RUNNER_TEMP}` log. If an open issue with that title
  exists, it comments there instead. Every issue lookup selects by exact title
  (`gh issue list --state open --json number,title` filtered with jq `.title == "uv.lock refresh
  failed"`), never by `--search`, which matches loosely.

The force-update replaces whatever `chore/uv-lock-refresh` held, including an open refresh PR's
head and any commit the operator added to it. That is accepted (operator, 2026-11-08): the PR is
bot output rebuilt from `master` in under a minute. A force-update by `GITHUB_TOKEN` starts no
CI, so the new head carries no checks until the operator's next close and reopen. GitHub
refuses to reopen a PR whose head was force-updated while it was closed. A run landing between
the operator's close and reopen therefore leaves that PR closed, and the run's own
edit-or-create step opens a new one.

### Failure handling

A failed step fails the job, and the failure step opens or updates the issue. A refusal from the
script (an empty change list, a downgrade, a failed check) happens before anything is written to
origin. A failure in step 3 after the force-update leaves the branch updated and the PR body
stale. The next run, or `gh workflow run uv-lock-refresh.yml`, repairs both.

### First task: prove the CI path

Before any other change, a throwaway probe settles whether the design works at all:

1. `.github/workflows/probe-token-pr.yml` is committed on a branch `probe/token-pr`, triggered by
   `on: push` for that branch. It creates `probe/token-pr-head` from `master` plus a one-line
   change, commits it as `github-actions[bot]` (the same `git config` lines), writes it to origin
   with `GITHUB_TOKEN`, and opens a PR against `master`. Because the
   head is based on `master`, the PR's diff carries only that one line, not the workflow file.
2. The operator runs `gh pr close <n> && gh pr reopen <n>`.
3. Run `gh api repos/brujack/dotfiles/commits/<sha>/check-runs` and
   `gh run list --event pull_request --commit <sha>`. All six required checks must appear on the
   head SHA, and no run may be `action_required`.
4. Cleanup is manual and is done whatever the result:
   - close the PR;
   - delete `probe/token-pr` and `probe/token-pr-head` on origin.

Nothing reaches master. The auto-merge gate holds the probe PR as a bot PR, so it cannot merge
itself.

## Testing

- `tests/scripts/refresh_uv_lock.bats` drives the script through a `uv` stub (`_UV_BIN` seam)
  and a stubbed `make`, against a fixture root (`REFRESH_UV_LOCK_ROOT` seam). The stub's change
  lines are copied from the real capture above. Cases:
  - lock unchanged: last stdout line `no changes`, no body;
  - lock changed and checks pass: last stdout line `changed`; the body lists every stub line
    plus `gh pr close`, `gh pr reopen`, `gh pr merge` and `gh workflow run uv-lock-refresh.yml`;
  - lock changed with no change lines: non-zero, no body;
  - a stub `Updated x v2.0 -> v1.9` line: non-zero, names `x`, no body;
  - a stub comma-form `Updated six v1.15.0, v1.16.0 -> v1.16.0` line: accepted (no downgrade);
  - a stub comma-form `Updated six v1.15.0, v1.16.0 -> v1.15.0` line: refused, names `six`;
  - a stub `Updated` line that does not parse: refused;
  - `2.9.0.post0 -> 2.9.0.post1` accepted (PEP 440, not string order);
  - the upgrade fails: non-zero, uv's message printed, no body;
  - a check fails: non-zero, names the check;
  - the stubbed `make` sees `REQUIRE_TOOLS=1` for both checks;
  - the `uv` and `make` stubs each print a sentinel on their own stdout, and the sentinel never
    appears on the script's stdout while the result word does.
- `tests/scripts/uv_lock_refresh_workflow.bats` parses the workflow per job:
  - `schedule` with cron `0 6 * * 1` and `workflow_dispatch` are present, and exactly two
    triggers exist;
  - workflow-level `contents: read` is present, and the job permissions are exactly the three
    named;
  - every `uses:` is pinned to a 40-hex SHA, and at least one `uses:` exists;
  - a `sha256sum -c` line;
  - `UV_VER`/`UV_SHA256` equal `ci.yml`'s `test-shard` values, read from that job alone;
  - `timeout-minutes: 10` and the `concurrency` group `uv-lock-refresh`;
  - `git config user.name` and `user.email` before the commit;
  - the issue lookup filters on `.title ==`, and no `gh issue list --search` appears;
  - the refresh step, the `isCrossRepository` filter, `gh pr edit`, `gh pr create`, the
    `no changes` close, the success issue-close and the `if: failure()` issue step are each
    present, in that order;
  - the failure step reads a `${RUNNER_TEMP}` log file.
- Both new files are added to `tests/bats-files.txt`.

## Requirements

- **R1.** `[PR1]` Before any other change, the probe in "First task" runs from a `push`-triggered workflow on `probe/token-pr`. Its GITHUB_TOKEN-opened PR, after the operator closes and reopens it, shows `test`, `lint-macos`, `test-macos`, `powershell`, `secret-scan` and `renderings-install` on its head SHA with no `action_required` run, or implementation stops and the identity decision returns to the operator. The probe PR is closed and both probe branches are deleted on origin either way.
- **R2.** `[PR1]` `scripts/refresh-uv-lock.sh` runs `uv lock --upgrade` (no `--exclude-newer`), then `make sync-requirements-ci`, `REQUIRE_TOOLS=1 make check-lock` and `REQUIRE_TOOLS=1 make check-requirements-ci`; it never commits, never calls `gh` and makes no remote writes.
- **R3.** `[PR1]` The script sends all `uv` and `make` output to stderr, and its last stdout line is exactly `changed` or `no changes` on exit 0.
- **R4.** `[PR1]` When `uv.lock` is byte-identical after the upgrade, the script prints `no changes`, writes no body file and exits 0.
- **R5.** `[PR1]` When the lock changed, at least one `Updated`/`Added`/`Removed` line was captured, no captured `Updated` line moves a package to a lower version, and both checks pass, the script prints `changed`, exits 0, and writes a body file containing every captured line, `gh pr close`, `gh pr reopen`, `gh pr merge` and `gh workflow run uv-lock-refresh.yml`.
- **R6.** `[PR1]` When the lock changed but no `Updated`/`Added`/`Removed` line was captured, when a captured `Updated` line's highest new version is lower than its highest old version under PEP 440 (each side may list several comma-separated versions) or the line does not parse, or when any `uv` or `make` step fails, the script exits non-zero with a message naming the cause, and no body file is written.
- **R7.** `[PR1]` `.github/workflows/uv-lock-refresh.yml` triggers on `schedule` cron `0 6 * * 1` and on `workflow_dispatch`, and on nothing else.
- **R8.** `[PR1]` The workflow sets workflow-level `permissions: contents: read`; its job declares exactly `contents: write`, `pull-requests: write` and `issues: write`, `timeout-minutes: 10`, `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: true` and `concurrency` group `uv-lock-refresh` with `cancel-in-progress: false`, and sets `git config user.name`/`user.email` to `github-actions[bot]` before committing; every `uses:` is pinned to a 40-hex SHA.
- **R9.** `[PR1]` The workflow installs uv with the `UV_VER` and `UV_SHA256` of `ci.yml`'s `test-shard` job and verifies the download with `sha256sum -c`; a test fails when the two differ.
- **R10.** `[PR1]` On `changed`, the workflow commits exactly `uv.lock`, `requirements-ci.txt`, `requirements-runtime-ci.txt`, `requirements-ci-test.txt`, `requirements-ci-mutation.txt` and `requirements-ci-audit.txt` on top of current `master`, force-updates `chore/uv-lock-refresh` to it, and then edits the body of the single open same-repository PR from that branch, or opens one against `master` titled `chore(deps): refresh uv.lock`; more than one such PR fails the job.
- **R11.** `[PR1]` On `no changes`, the workflow closes an open same-repository refresh PR with a comment; it never closes a fork PR.
- **R12.** `[PR1]` When any step fails, the workflow opens an issue titled `uv.lock refresh failed` containing the run URL and the last 40 lines of the failing step's `${RUNNER_TEMP}` log, or comments them on the open issue with that title; when a run succeeds, it comments the run URL on that open issue and closes it. Issues are selected by exact title match, never by `gh issue list --search`.
- **R13.** `[PR1]` Both new bats files are listed in `tests/bats-files.txt`; the backlog row "Automate the weekly `uv lock --upgrade` and `make sync-requirements-ci` refresh" is removed, and a backlog row records the dropped release-age cooldown with this spec's downgrade and `[options]` measurements.
- **V1.** After merge, run the workflow once with `workflow_dispatch`. It must open a PR from `chore/uv-lock-refresh` whose diff touches only the six files in R10. The auto-merge gate must hold it as `bot PR (...) lacks automerge-ok`. After the operator's close and reopen, all six required checks must pass on it.
- **V2.** A second `workflow_dispatch` while that PR is open must update that PR (same number) and open no second PR.
- **N1.** No change to `ci.yml` triggers, `renovate.json` or `scripts/auto-merge-gate.sh`.
- **N2.** No new repository secret, and no token other than the job's `GITHUB_TOKEN`.
- **N3.** The workflow never merges, approves or labels a PR, never closes or edits a PR whose head is not this repository's `chore/uv-lock-refresh`, and never writes to `master`.
- **N4.** No `exclude-newer` setting or flag anywhere: not in `pyproject.toml`, not in the script.

## Amendments

- R6 -> When the lock changed but no `Updated`/`Added`/`Removed` line was captured, when a captured `Updated` line's highest new version is lower than its highest old version or its lowest new version is lower than its lowest old version (each side may list several comma-separated versions, compared as PEP 440 versions by a standard-library comparator that treats any form outside epoch, release, `a`/`b`/`rc`, `.post` and `.dev` as unparseable) or the line does not parse, or when any `uv` or `make` step fails, the script exits non-zero with a message naming the cause (uv's own output when `uv lock` fails), and no body file is written. — Task 2 review: `packaging` is not installed in CI's test jobs or reliably on any runner (Homebrew's python lacks it), and a max-only rule missed a downgrade inside one resolution fork (`v1.0, v3.0 -> v0.5, v3.0`).
- R8 -> The workflow sets workflow-level `permissions: contents: read`, `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: true` and `concurrency` group `uv-lock-refresh` with `cancel-in-progress: false`, and has three jobs, each with `timeout-minutes: 10`. Job `refresh` declares no permissions of its own, sets no `GH_TOKEN`, checks out with `persist-credentials: false`, runs the script and uploads `uv.lock`, the five renderings, the body file and the result word as one artifact, and uploads its step logs as a second artifact whatever the outcome. Job `publish` (`needs: refresh`) declares exactly `contents: write`, `pull-requests: write` and `issues: write`, checks out `master`, copies only those six files and the body from the artifact, validates the result word, sets `git config user.name`/`user.email` to `github-actions[bot]` before committing, and is the only job that commits, pushes or edits a PR. Job `report` (`needs: [refresh, publish]`, runs only on failure or cancellation) declares exactly `issues: write`. — security-review found that `uv lock --upgrade` runs PyPI build code for sdist-only packages (httppy, yattag; probed 2026-11-08), so the resolve must not share a runner with a write token.
- R12 -> When any step fails, the `report` job opens an issue titled `uv.lock refresh failed` containing the run URL and the last 40 lines of the newest step log uploaded by the failed job, or comments them on the open issue with that title; when a run succeeds, `publish` comments the run URL on that open issue and closes it. Issues are selected by exact title match, never by `gh issue list --search`. — the R8 split puts the logs on another runner, so they travel as an artifact.
- finding R1 (2026-11-08, reviewer both): NOT-BUILT — The diff carries no probe workflow or run evidence; the only trace is the ADR's assertion (docs/adr/0056-weekly-uv-lock-refresh-workflow.md:18-19, 'all six required checks run ... (probe PR #444)'), which says nothing about the checks being on the head SHA, the absence of an action_required run, the probe PR being closed, or both probe branches being deleted on origin.
- R1 reviewed: the probe is a precondition whose evidence cannot live in a diff. It ran on 2026-11-08 as PR #444 (`chore: GITHUB_TOKEN CI probe (do not merge)`, head `probe/token-pr-head`). After the operator closed and reopened it, all six required checks ran on its head SHA with no `action_required` run, and the auto-merge gate held it as a bot PR. The plan's `## Probe result` section on master (6cec2214) records it. Re-checked at verdict time: PR #444 is CLOSED and `git ls-remote --heads origin 'probe/*'` returns 0 refs.
- finding R12 (2026-11-08, reviewer both): DIFFERS — The report job merges every `*-logs` artifact and quotes the highest-numbered `NN-*.log` across both jobs (uv-lock-refresh.yml:255-266), not the newest log uploaded by the failed job: when publish fails before its first logged step (checkout, artifact download) it quotes refresh's 20-refresh.log, a gap the diff's own new backlog row ('Refresh failure issue can quote the wrong step's log') records.
- R12 -> When any step fails, the `report` job opens an issue titled `uv.lock refresh failed` containing the run URL and the last 40 lines of the highest-numbered step log uploaded by the run's jobs (normally the failing step), or comments them on the open issue with that title; when a run succeeds, `publish` comments the run URL on that open issue and closes it. Issues are selected by exact title match, never by `gh issue list --search`. — the logs from both jobs are merged into one artifact download, so a publish failure before its first logged step, or a re-run that fails in refresh after an earlier attempt's publish, quotes another step's log; the backlog row "Refresh failure issue can quote the wrong step's log" records the fix shape.

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

### Round 3

Reviewed at commit: `8aecadca`

#### Goal-Fit

Finding: The plain-`uv lock` repair works (0 of 269 pins changed, `--check` rc 0), but the keep/replace/unknown PR script, its polling and its two close paths existed only to preserve an open refresh PR, which is bot output rebuilt in under a minute; regenerating and updating the PR in place removes all of it. The result word shared stdout with `make` output.
Assumption: That the operator's close and reopen of a GITHUB_TOKEN-opened PR runs all six required checks on the head SHA; R1 settles it.
Disposition: Addressed (operator, 2026-11-08): every run regenerates from `master`, force-updates the branch and edits or creates the PR; the PR script and polling are removed; the result word is the last stdout line with tool output on stderr.

#### Ergonomics

Finding: An `if: failure()` step cannot read an earlier step's log; the body's `<n>` cannot be known when the body is written; the failure issue never closed after a later success; the failure-handling sentence contradicted the close-then-create order.
Assumption: Same as goal-fit (R1), plus that reopened runs are not held as `action_required`.
Disposition: Addressed (operator, 2026-11-08): each step tees to `${RUNNER_TEMP}`; the body names the PR by branch; a successful run closes the issue; failure handling restated; R1 also rejects `action_required` runs.

#### Risk

Finding: `--upgrade --exclude-newer` drops locked versions as preferences and downgrades every package master holds at a release younger than the cutoff. Measured: 9 downgrades at 30 days and 12 at 45, including the tornado, certifi, pillow and gitpython CVE fixes; a run on 2026-10-26 would have reverted #364. The probe's cleanup is manual and its head branch base was unstated.
Assumption: Same as goal-fit (R1).
Disposition: Addressed (operator, 2026-11-08): the cooldown is dropped and backlogged with these measurements (plain `uv lock --upgrade` measured with 0 downgrades); any downgrade line refuses the run; probe cleanup is manual and its head is based on `master`.

### Round 4 (scoped: rewritten sections only)

Reviewed at commit: `24065e57`

#### Risk

Finding: Implementation-level only. The downgrade parse missed uv's comma form (`Updated six v1.15.0, v1.16.0 -> v1.16.0`, possible with this lock's 5 forks) and named no comparator; no `concurrency` group, so overlapping runs could both `gh pr create`; no git identity before commits (workflow and probe); a `--search` issue lookup matches loosely; a force-update between close and reopen makes the PR unreopenable; a yanked locked release refuses weekly with no named remedy; the stdout test passed if stubs printed nothing. No R contradicts an N.
Assumption: That the operator's close and reopen of a GITHUB_TOKEN-opened PR runs all six required checks on the head SHA with no `action_required` run; R1 settles it.
Disposition: Addressed (operator, 2026-11-08): all seven folded in (PEP 440 comparison over comma lists, unparseable refuses; `concurrency`; git identity; exact-title jq filter; the reopen edge and the yanked-release remedy documented; sentinel stubs). Approved without a further round: the findings landed in the apparatus, not the design.

## Spec alignment (2026-11-08)

- spec: docs/superpowers/specs/2026-11-08-uv-lock-refresh-design.md
- anchor: 4df3ee290a45408ff8fd92befe2f9b4c2ae936d4
- in scope: R1, R2, R3, R4, R5, R6, R7, R8, R9, R10, R11, R12, R13
- out of scope: none

### Findings

| ID | Reviewer | Verdict | Reason | Amendment |
| --- | --- | --- | --- | --- |
| R1 | both | NOT-BUILT | The diff carries no probe workflow or run evidence; the only trace is the ADR's assertion (docs/adr/0056-weekly-uv-lock-refresh-workflow.md:18-19, 'all six required checks run ... (probe PR #444)'), which says nothing about the checks being on the head SHA, the absence of an action_required run, the probe PR being closed, or both probe branches being deleted on origin. | - R1 reviewed: the probe is a precondition whose evidence cannot live in a diff. It ran on 2026-11-08 as PR #444 (`chore: GITHUB_TOKEN CI probe (do not merge)`, head `probe/token-pr-head`). After the operator closed and reopened it, all six required checks ran on its head SHA with no `action_required` run, and the auto-merge gate held it as a bot PR. The plan's `## Probe result` section on master (6cec2214) records it. Re-checked at verdict time: PR #444 is CLOSED and `git ls-remote --heads origin 'probe/*'` returns 0 refs. |
| R12 | both | DIFFERS | The report job merges every `*-logs` artifact and quotes the highest-numbered `NN-*.log` across both jobs (uv-lock-refresh.yml:255-266), not the newest log uploaded by the failed job: when publish fails before its first logged step (checkout, artifact download) it quotes refresh's 20-refresh.log, a gap the diff's own new backlog row ('Refresh failure issue can quote the wrong step's log') records. | - R12 -> When any step fails, the `report` job opens an issue titled `uv.lock refresh failed` containing the run URL and the last 40 lines of the highest-numbered step log uploaded by the run's jobs (normally the failing step), or comments them on the open issue with that title; when a run succeeds, `publish` comments the run URL on that open issue and closes it. Issues are selected by exact title match, never by `gh issue list --search`. — the logs from both jobs are merged into one artifact download, so a publish failure before its first logged step, or a re-run that fails in refresh after an earlier attempt's publish, quotes another step's log; the backlog row "Refresh failure issue can quote the wrong step's log" records the fix shape. |

### Reviewed

- R1 reviewed: the probe is a precondition whose evidence cannot live in a diff. It ran on 2026-11-08 as PR #444 (`chore: GITHUB_TOKEN CI probe (do not merge)`, head `probe/token-pr-head`). After the operator closed and reopened it, all six required checks ran on its head SHA with no `action_required` run, and the auto-merge gate held it as a bot PR. The plan's `## Probe result` section on master (6cec2214) records it. Re-checked at verdict time: PR #444 is CLOSED and `git ls-remote --heads origin 'probe/*'` returns 0 refs.

### Verifications

- V1: no evidence recorded
- V2: no evidence recorded
