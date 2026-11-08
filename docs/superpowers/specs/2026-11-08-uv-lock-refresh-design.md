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

The script passes `--exclude-newer` set to 14 days before the run, matching Renovate's
`"minimumReleaseAge": "14 days"` (`renovate.json`). Without it a Monday run takes releases
published minutes earlier, and the merged lock reaches every machine's `-t update`
(`uv sync --frozen`). Nothing in CI installs `requirements-runtime-ci.txt` (ansible,
ansible-core, ansible-lint, molecule), and ai-config CI installs the other renderings live
from master, with `--require-hashes` pinned to this same resolution. The cutoff is computed by
the script, with `REFRESH_UV_LOCK_NOW` as a test seam for the reference time.

### Components

**`scripts/refresh-uv-lock.sh`** holds the logic, so it is testable without GitHub. Given a
body path as `$1`:

1. Compute the cutoff (reference time minus 14 days, UTC, RFC 3339) and run
   `uv lock --upgrade --exclude-newer <cutoff>`, capturing its `Updated`/`Added`/`Removed`
   lines.
2. If `uv.lock` is byte-identical to before, print `no changes` and exit 0.
3. If the lock changed but no `Updated`/`Added`/`Removed` line was captured, exit 1: uv's
   output format moved and the PR would carry an empty change list.
4. `make sync-requirements-ci`, then `REQUIRE_TOOLS=1 make check-lock` and
   `REQUIRE_TOOLS=1 make check-requirements-ci`, so a missing uv fails rather than skips. If
   either fails, exit 1 naming the step.
5. Write the PR body to `$1`: the cutoff, the change count, the captured lines, and the review
   instructions. To start CI, run `gh pr close <n> && gh pr reopen <n>` or apply a label. Read
   the list before merging. If the PR conflicts, the next weekly run replaces it, or run
   `gh workflow run uv-lock-refresh.yml` to replace it now.
6. Print `changed` and exit 0. The workflow branches on that word, not on the exit status
   alone.

Any failed `uv` or `make` step exits non-zero naming the step. The script never commits, pushes
or calls `gh`.

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
- Open-PR rule: read the open PR from `chore/uv-lock-refresh`, if any, with
  `gh pr list --head chore/uv-lock-refresh --state open --json number,mergeable`.
  - Open and not `CONFLICTING`: stop with a notice. A refresh never replaces a reviewable PR.
  - Open and `CONFLICTING`: comment that it is being replaced, close it, and continue.
  - `UNKNOWN` is GitHub still computing; treat it as not conflicting and stop.
- Run the script. On `changed`: commit exactly `uv.lock` and the five renderings to
  `chore/uv-lock-refresh` on top of current `master` (force-push), then
  `gh pr create --base master --head chore/uv-lock-refresh --title
"chore(deps): refresh uv.lock" --body-file <body>`.
- `if: failure()` step: open an issue titled `uv.lock refresh failed` with the run URL, or
  comment on the open one with that title if it exists. The operator watches the repo, so
  the issue notifies him. ai-config's aggregator failed for five months with only the Actions
  tab to show it.

The force-push replaces whatever `chore/uv-lock-refresh` held. It runs only after the open-PR
rule, so what it can destroy is a closed refresh PR's branch, including a conflicted one it
just closed and any commit the operator pushed there. That is accepted: a closed refresh is
abandoned, and the run re-derives the lock from `master`.

### Failure handling

A failed step fails the job, nothing is pushed, and the failure step opens or updates the
issue. A resolution that `check-lock` or `check-requirements-ci` rejects never reaches a PR. A
run that finds a reviewable refresh PR does nothing.

## Testing

- `tests/scripts/refresh_uv_lock.bats` drives the script with a `uv` stub (`_UV_BIN` seam) and
  a fixture root (`REFRESH_UV_LOCK_ROOT` seam). The root holds a fixture `uv.lock` and the five
  renderings; `make` is stubbed so the real Makefile never runs against the fixture. No
  network, no real lock. The stub's change lines are copied from the real `uv lock --upgrade`
  capture above. Cases:
  - lock unchanged: `no changes`, no body written;
  - lock changed and checks pass: `changed`, the body lists every stub change line and the CI
    instruction;
  - lock changed but the stub prints no change lines: non-zero, no body;
  - `uv lock` fails: non-zero, names the step, no body;
  - a check fails after sync: non-zero, names the check;
  - the checks run with `REQUIRE_TOOLS=1` in their environment (recorded by the `make` stub);
  - with `REFRESH_UV_LOCK_NOW` fixed, the stub receives the exact `--exclude-newer` value
    14 days earlier.
- `tests/scripts/uv_lock_refresh_workflow.bats` parses the workflow per job:
  - the cron and `workflow_dispatch`, and no other trigger;
  - workflow-level `contents: read`; job permissions exactly the three named;
  - every `uses:` pinned to a 40-hex SHA;
  - a `sha256sum -c` line;
  - `UV_VER`/`UV_SHA256` equal to `ci.yml`'s `test-shard` job values, read from that job
    alone;
  - `timeout-minutes: 10`;
  - the open-PR rule before the script step, reading `mergeable`;
  - an `if: failure()` step that names the issue title.
- Both new files are added to `tests/bats-files.txt`.

## Requirements

- **R1.** `[PR1]` Before any other change, a throwaway probe shows that a PR opened by a `workflow_dispatch` run with `GITHUB_TOKEN`, then closed and reopened by the operator, gets runs of all six required checks recorded against its head SHA; if it does not, implementation stops and the identity decision returns to the operator.
- **R2.** `[PR1]` `scripts/refresh-uv-lock.sh` runs `uv lock --upgrade --exclude-newer <cutoff>`, with `<cutoff>` exactly 14 days before the reference time (`REFRESH_UV_LOCK_NOW`, default now, UTC); it then runs `make sync-requirements-ci`, `REQUIRE_TOOLS=1 make check-lock` and `REQUIRE_TOOLS=1 make check-requirements-ci`, and never runs `git commit`, `git push` or `gh`.
- **R3.** `[PR1]` When `uv.lock` is byte-identical after the upgrade, the script prints `no changes`, writes no body file and exits 0.
- **R4.** `[PR1]` When the lock changed, at least one `Updated`/`Added`/`Removed` line was captured and both checks pass, the script prints `changed`, exits 0, and writes a body file containing the cutoff, every captured line, `gh pr close`, `gh pr reopen` and `gh workflow run uv-lock-refresh.yml`.
- **R5.** `[PR1]` When the lock changed but no `Updated`/`Added`/`Removed` line was captured, or any `uv` or `make` step fails, the script exits non-zero with a message naming the cause, and no body file is written.
- **R6.** `[PR1]` `.github/workflows/uv-lock-refresh.yml` triggers on `schedule` cron `0 6 * * 1` and on `workflow_dispatch`, and on nothing else.
- **R7.** `[PR1]` The workflow sets workflow-level `permissions: contents: read`; its job declares exactly `contents: write`, `pull-requests: write` and `issues: write`, `timeout-minutes: 10` and `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: true`; every `uses:` is pinned to a 40-hex SHA.
- **R8.** `[PR1]` The workflow installs uv with the `UV_VER` and `UV_SHA256` of `ci.yml`'s `test-shard` job and verifies the download with `sha256sum -c`; a test fails when the two differ.
- **R9.** `[PR1]` When an open PR from `chore/uv-lock-refresh` exists and is not `CONFLICTING`, the workflow stops before running the script; when it is `CONFLICTING`, the workflow comments on it, closes it, and continues.
- **R10.** `[PR1]` On `changed`, the workflow commits exactly `uv.lock`, `requirements-ci.txt`, `requirements-runtime-ci.txt`, `requirements-ci-test.txt`, `requirements-ci-mutation.txt` and `requirements-ci-audit.txt` to `chore/uv-lock-refresh` on top of current `master`, and opens a PR against `master` titled `chore(deps): refresh uv.lock` with the script's body.
- **R11.** `[PR1]` When any step fails, the workflow opens an issue titled `uv.lock refresh failed` containing the run URL, or comments the run URL on the open issue with that title.
- **R12.** `[PR1]` Both new bats files are listed in `tests/bats-files.txt`, and the backlog row "Automate the weekly `uv lock --upgrade` and `make sync-requirements-ci` refresh" is removed.
- **V1.** After merge, run the workflow once with `workflow_dispatch`. It must open a PR from `chore/uv-lock-refresh` whose diff touches only the six files in R10. The auto-merge gate must hold it as `bot PR (...) lacks automerge-ok`. After the operator's close and reopen, all six required checks must run on it.
- **V2.** A second `workflow_dispatch` while that PR is open and mergeable must open no second PR.
- **N1.** No change to `ci.yml` triggers, `renovate.json` or `scripts/auto-merge-gate.sh`.
- **N2.** No new repository secret, and no token other than the job's `GITHUB_TOKEN`.
- **N3.** The workflow never merges, approves or labels a PR, and never closes a PR that GitHub does not report as `CONFLICTING`.

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
