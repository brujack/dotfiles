# ADR-0056: Weekly uv.lock refresh as a bot PR from a split-trust workflow

**Date:** 2026-11-08
**Status:** Accepted

## Context

`uv.lock` and its five `requirements-ci*.txt` renderings were refreshed by hand. Renovate manages
no Python here and Dependabot security auto-PRs are off fleet-wide, so a lock-only security fix
reached master only when someone remembered to run `uv lock --upgrade` and
`make sync-requirements-ci`. The design is in
`docs/superpowers/specs/2026-11-08-uv-lock-refresh-design.md`; this record keeps the choices a
later editor could undo without noticing.

Three facts constrained the design, each measured on 2026-11-08:

- A PR opened with `GITHUB_TOKEN` gets zero-job runs. After the operator closes and reopens it, all
  six required checks run, and the auto-merge gate holds it as a bot PR (probe PR #444).
- A `GITHUB_TOKEN` force-push of a branch that is master plus one lock-only commit is accepted. A
  push whose tip carries workflow files that differ from master's is refused without the
  `workflows` permission (probe runs 42516663365 and the follow-up).
- `uv lock --upgrade` runs PyPI build backends for sdist-only packages (`httppy`, `yattag`) to read
  their metadata. `--no-build` therefore fails resolution today.

## Decision

1. **A scheduled workflow (`uv-lock-refresh.yml`, Monday 06:00 UTC plus `workflow_dispatch`, master
   only) opens or updates one PR from `chore/uv-lock-refresh` with `GITHUB_TOKEN`.** It adds no
   new secret and no app token. The operator starts that PR's CI with a close and reopen and
   merges it by hand. The bot-PR hold in the auto-merge gate stays.
2. **The resolve runs without a write token.** Three jobs:
   - `refresh` has read-only scope, no token exposed to its steps and no persisted credentials.
     It runs the PyPI build code and uploads its output as an artifact.
   - `publish` holds `contents`, `pull-requests` and `issues` write. It takes from that artifact
     only the six named files, a validated result word and the PR body text.
   - `report` holds only `issues: write`. It files the `uv.lock refresh failed` issue from the
     uploaded logs.
3. **No release-age cooldown.** `--exclude-newer` writes `[options]` into `uv.lock` and downgrades
   lock-only security bumps younger than the cutoff (9 packages at 30 days, 12 at 45). The
   operator's review of the PR diff is the gate for brand-new releases. The backlog records the
   fix shape.
4. **The script refuses a downgrade.** A captured `Updated` line whose highest or lowest new
   version is below the old one under PEP 440 fails the run, as does an unparseable line. A
   stdlib comparator does the check, because CI installs no Python packages.

## Consequences

- Moving the resolve back into the job that holds the write scopes reopens the hole decision 2
  closes. `tests/scripts/uv_lock_refresh_workflow.bats` pins the split: refresh has no
  permissions key, no exposed token and `persist-credentials: false`, and only publish pushes or
  calls `gh pr`.
- Code that ran in `refresh` can still shape everything the PR proposes: the lock, the renderings
  and the body. The PR diff, not the body's change list, is what the operator reviews.
- Each refresh PR needs one operator action before CI runs, and one to merge.
- Fixed artifact names carry `overwrite: true`, so a re-run attempt can upload. Download a failed
  attempt's logs before re-running. The backlog records the failure-log attribution gaps.

## Related

- Spec: `docs/superpowers/specs/2026-11-08-uv-lock-refresh-design.md` (R8 and R12 amended for the
  job split)
- ADR-0053, ADR-0054: artifact naming and re-run behaviour in `ci.yml`
- ai-config ADR-0085: bot PRs held by the auto-merge gate
