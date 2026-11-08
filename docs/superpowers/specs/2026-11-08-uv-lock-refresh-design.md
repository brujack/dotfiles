# Weekly uv.lock refresh PR

## Problem

Nothing re-asks the resolver whether the locked answer is still current. `uv sync --frozen`
makes installs reproducible, and `uv lock` against an existing lock keeps resolutions the
constraints no longer require (backlog: "Nothing ever re-asks the resolver"). Every `uv.lock`
change since 2026-09-29 was reactive: 8 of the last 12 lock commits (#297, #302, #303, #356,
#364, #422, #423, #425) were bumps for Dependabot alerts.

Measured 2026-11-08 at master `cb57dfb6`, in a `git archive` copy of `pyproject.toml` and
`uv.lock` (population: this repo's lock, one point in time): `uv lock --upgrade --dry-run` exits
0, resolves 269 packages, and changes 103 of them plus one addition (`cloudpickle`).

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

- `scripts/auto-merge-gate.sh` already holds every PR that changes `uv.lock` without
  `pyproject.toml` ("leaving open for a human"), and every bot-authored PR without
  `automerge-ok`. A human reviews and merges this PR whichever identity opens it. The other
  options buy only "CI has already run when you look".
- No new credential exists. The workflow's write scope is its own job's `GITHUB_TOKEN`.
- `ci.yml` triggers on `pull_request` types `opened, synchronize, reopened,
ready_for_review, labeled`. A close and reopen by the operator is a `reopened` event from a
  user, so it starts CI: `gh pr close <n> && gh pr reopen <n>`.
- Precedent: ai-config's learnings-aggregator opens its draft PRs with `GITHUB_TOKEN` and the
  operator's later action starts CI.
- The repo setting "Allow GitHub Actions to create and approve pull requests" is on
  (`can_approve_pull_request_reviews: true`, read 2026-11-08).

### Components

**`scripts/refresh-uv-lock.sh`** holds the logic, so it is testable without GitHub:

1. `uv lock --upgrade`, capturing uv's `Update`/`Add`/`Remove` lines.
2. If `uv.lock` is byte-identical to before, print `no changes` and exit 0.
3. `make sync-requirements-ci`, then `uv lock --check` and `make check-requirements-ci`. If either
   check fails, exit 1 naming the step.
4. Write the PR body to the path given as `$1`. It contains uv's change lines, the change count,
   and the review instructions: start CI with `gh pr close <n> && gh pr reopen <n>`, and read
   the list before merging.
5. Print `changed` and exit 0. The workflow branches on that word, not on the exit status alone.

Any failed `uv` or `make` step exits non-zero naming the step. The script never commits or
pushes.

**`.github/workflows/uv-lock-refresh.yml`**, one job:

- `on: schedule: - cron: "0 6 * * 1"` (Monday 06:00 UTC, after Renovate's "before 5am on
  monday" window) and `workflow_dispatch`.
- `permissions: contents: write, pull-requests: write` at job level; the workflow-level
  default is `contents: read`.
- `timeout-minutes: 10`; `runs-on: ubuntu-latest`; `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: true`,
  like every job in `ci.yml`.
- Checkout pinned by SHA (ADR-0006); uv installed with the same `UV_VER` and `UV_SHA256` as
  `ci.yml`, verified with `sha256sum -c` (ci-002).
- If `gh pr list --head chore/uv-lock-refresh --state open` returns a PR, stop with a notice.
  A refresh never replaces a PR under review.
- Otherwise run the script. On `changed`: commit `uv.lock` and the five renderings to
  `chore/uv-lock-refresh` (force-push, since the branch is the bot's alone), then
  `gh pr create --base master --head chore/uv-lock-refresh --title
"chore(deps): refresh uv.lock" --body-file <body>`.

The force-push replaces whatever `chore/uv-lock-refresh` held. It runs only when no open PR uses
the branch (R8), so what it can destroy is a closed refresh PR's branch, including any commit
the operator pushed there before closing it. That is accepted: a closed refresh is abandoned,
and the next run re-derives the lock from `master` anyway.

### Failure handling

A failed step fails the job, which shows in the Actions tab, and nothing is pushed. A
resolution that `uv lock --check` or `check-requirements-ci` rejects never reaches a PR. A run
that finds an open refresh PR does nothing.

## Testing

- `tests/scripts/refresh_uv_lock.bats` drives the script with a `uv` stub (`_UV_BIN` seam) and
  a fixture root (`REFRESH_UV_LOCK_ROOT` seam) holding a fixture `uv.lock` and renderings. No
  network, no real lock. Cases:
  - lock unchanged: `no changes`, no body written;
  - lock changed and checks pass: `changed`, the body lists the stub's update lines and the CI
    instruction;
  - `uv lock` fails: non-zero, names the step, no body;
  - a check fails after sync: non-zero, names the check.
- `tests/scripts/uv_lock_refresh_workflow.bats` parses the workflow per job:
  - the cron and `workflow_dispatch`;
  - job permissions exactly `contents: write` and `pull-requests: write`;
  - every `uses:` pinned to a 40-hex SHA;
  - a `sha256sum -c` line;
  - `UV_VER`/`UV_SHA256` equal to `ci.yml`'s, read from both files (count-checked, not
    membership);
  - `timeout-minutes` set;
  - the open-PR guard before the script runs.
- Both new files are added to `tests/bats-files.txt`.

## Requirements

- **R1.** `[PR1]` `scripts/refresh-uv-lock.sh` runs `uv lock --upgrade`, then `make sync-requirements-ci`, then `uv lock --check` and `make check-requirements-ci`, and never runs `git commit`, `git push` or `gh`.
- **R2.** `[PR1]` When `uv lock --upgrade` leaves `uv.lock` byte-identical, the script prints `no changes`, writes no body file and exits 0.
- **R3.** `[PR1]` When the lock changed and both checks pass, the script prints `changed`, exits 0, and writes a body file containing every `Update`/`Add`/`Remove` line uv printed and the text `gh pr close` and `gh pr reopen`.
- **R4.** `[PR1]` Any failing `uv` or `make` step makes the script exit non-zero with a message naming that step, and no body file is written.
- **R5.** `[PR1]` `.github/workflows/uv-lock-refresh.yml` triggers on `schedule` cron `0 6 * * 1` and on `workflow_dispatch`, and on nothing else.
- **R6.** `[PR1]` The workflow's job declares `permissions` of exactly `contents: write` and `pull-requests: write`, `timeout-minutes: 10`, and `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: true`; every `uses:` is pinned to a 40-hex SHA.
- **R7.** `[PR1]` The workflow installs uv with the same `UV_VER` and `UV_SHA256` values as `ci.yml` and verifies the download with `sha256sum -c` before running it; a test fails when the two files' values differ.
- **R8.** `[PR1]` The workflow stops before running the script when an open PR from `chore/uv-lock-refresh` exists.
- **R9.** `[PR1]` On `changed`, the workflow commits exactly `uv.lock`, `requirements-ci.txt`, `requirements-runtime-ci.txt`, `requirements-ci-test.txt`, `requirements-ci-mutation.txt` and `requirements-ci-audit.txt` to `chore/uv-lock-refresh`, based on the current `master`, and opens a PR against `master` titled `chore(deps): refresh uv.lock` with the script's body.
- **R10.** `[PR1]` Both new bats files are listed in `tests/bats-files.txt`, and the backlog row "Automate the weekly `uv lock --upgrade` and `make sync-requirements-ci` refresh" is removed.
- **V1.** After merge, run the workflow once with `workflow_dispatch`. It must open a PR from `chore/uv-lock-refresh` whose diff touches only `uv.lock` and the five renderings. After `gh pr close`/`gh pr reopen` by the operator, CI must run on it, and the auto-merge gate must hold it ("uv.lock changed without pyproject.toml").
- **V2.** A second `workflow_dispatch` while that PR is open must open no second PR.
- **N1.** No change to `ci.yml` triggers, `renovate.json` or `scripts/auto-merge-gate.sh`.
- **N2.** No new repository secret, and no token other than the job's `GITHUB_TOKEN`.
- **N3.** The workflow never merges, approves or labels a PR.
