# Weekly uv.lock refresh PR Implementation Plan

spec: docs/superpowers/specs/2026-11-08-uv-lock-refresh-design.md

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A weekly GitHub workflow regenerates `uv.lock` and the five CI renderings and opens or updates one PR, which the operator kicks into CI and merges by hand.

**Architecture:** `scripts/refresh-uv-lock.sh` does the lock work and writes the PR body; a Python helper decides downgrades with PEP 440. `.github/workflows/uv-lock-refresh.yml` runs it, force-updates `chore/uv-lock-refresh`, edits or creates the PR, and opens/closes a failure issue. Task 1 first proves that a GITHUB_TOKEN-opened PR gets CI after the operator reopens it; if not, the plan stops.

**Tech Stack:** bash, bats, Python 3 (`packaging`), GitHub Actions, `gh`, uv 0.13.0 (CI pin).

## Global Constraints

- No `exclude-newer` flag or setting anywhere (N4).
- No change to `ci.yml` triggers, `renovate.json` or `scripts/auto-merge-gate.sh` (N1).
- No new repository secret; no token other than the job's `GITHUB_TOKEN` (N2).
- The workflow never merges, approves or labels a PR, never closes or edits a PR whose head is not this repository's `chore/uv-lock-refresh`, and never writes to `master` (N3).
- Every `uses:` pinned to a 40-hex SHA (ADR-0006); uv download verified with `sha256sum -c` (ci-002).
- New `.bats` files are added to `tests/bats-files.txt` in the same task (`make check-bats-manifest` fails otherwise).
- Shell follows CLAUDE.md: `#!/usr/bin/env bash`, no `set -e`, `[[ ]]`, `${VAR}`, `printf`; long Python lives in its own file under `scripts/`, never a multi-line `python3 -c`.

## Verification

- Whole change: `make test` exits 0 (suite about 2.5 min on `claude`, under the 600 s cap); CI green on the PR.
- After merge (V1, V2): `gh workflow run uv-lock-refresh.yml` opens a PR from `chore/uv-lock-refresh` touching only `uv.lock` and the five renderings, held by the gate as `bot PR (...) lacks automerge-ok`; close and reopen run all six checks; a second dispatch updates the same PR number.
- Edge cases: unchanged lock (no PR); a downgrade line, including uv's comma form (refused); an unparseable line (refused); a missing uv under `REQUIRE_TOOLS=1` (refused); a fork PR on the same branch name (ignored).

---

### Task 1: Prove a GITHUB_TOKEN PR gets CI after the operator reopens it

```yaml-task
id: 1
description: Orchestrator-run probe (R1), no product code, so TDD does not apply; gates every later task
role: planner
tdd: not-applicable
requirements: [R1]
acceptance:
  - cmd: 'grep -qE "^Probe result: PASS" docs/superpowers/plans/2026-11-08-uv-lock-refresh.md'
    exit_code: 0
  - cmd: 'test -z "$(git ls-remote --heads origin probe/token-pr probe/token-pr-head)"'
    exit_code: 0
max_retries: 1
files_touched:
  - docs/superpowers/plans/2026-11-08-uv-lock-refresh.md
depends_on: []
```

Run by the orchestrator, not a subagent. The orchestrator's `gh` calls are the operator's identity, so its close/reopen is the operator's user event.

- [ ] Create branch `probe/token-pr` from `origin/master` in a fresh worktree with one file, `.github/workflows/probe-token-pr.yml`:

```yaml
name: probe-token-pr
on:
  push:
    branches: [probe/token-pr]
permissions:
  contents: write
  pull-requests: write
jobs:
  probe:
    runs-on: ubuntu-latest
    timeout-minutes: 5
    env:
      FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: true
      GH_TOKEN: ${{ github.token }}
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7
        with:
          ref: master
      - run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git switch -c probe/token-pr-head
          printf 'probe %s\n' "${GITHUB_RUN_ID}" > probe-token-pr.txt
          git add probe-token-pr.txt
          git commit -m "chore: GITHUB_TOKEN CI probe (do not merge)"
          git push origin probe/token-pr-head
          gh pr create --base master --head probe/token-pr-head \
            --title "chore: GITHUB_TOKEN CI probe (do not merge)" \
            --body "Throwaway probe for docs/superpowers/specs/2026-11-08-uv-lock-refresh-design.md R1."
```

- [ ] Push `probe/token-pr`; wait for the probe run; read the PR number and head SHA (`gh pr view probe/token-pr-head --json number,headRefOid`).
- [ ] `gh pr close <n> && gh pr reopen <n>`; wait for CI (`gh pr checks <n> --watch`).
- [ ] Verify: `gh api repos/brujack/dotfiles/commits/<sha>/check-runs --jq '.check_runs[].name' | sort -u` contains `test`, `lint-macos`, `test-macos`, `powershell`, `secret-scan`, `renderings-install`; `gh run list --event pull_request --commit <sha> --json status,conclusion` shows no `action_required`.
- [ ] Cleanup whatever the result: `gh pr close <n>`; delete `probe/token-pr` and `probe/token-pr-head` on origin; remove the worktree.
- [ ] Append `## Probe result` to this plan with `Probe result: PASS` or `Probe result: FAIL`, the PR number, SHA and check list; commit to master. On FAIL stop and return the identity decision to the operator.

### Task 2: refresh-uv-lock.sh with a PEP 440 downgrade check

```yaml-task
id: 2
description: Lock refresh script, downgrade helper and their tests
role: executor
model: sonnet
tdd: required
requirements: [R2, R3, R4, R5, R6]
acceptance:
  - cmd: python3 -m unittest tests.test_uv_lock_downgrades
    exit_code: 0
  - cmd: bats tests/scripts/refresh_uv_lock.bats
    exit_code: 0
    stdout_match: 'ok [0-9]+ .*comma'
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - scripts/refresh-uv-lock.sh
  - scripts/uv_lock_downgrades.py
  - tests/test_uv_lock_downgrades.py
  - tests/scripts/refresh_uv_lock.bats
  - tests/stubs/uv-refresh-stub
  - tests/stubs/make-refresh-stub
  - tests/bats-files.txt
depends_on: [1]
```

**`scripts/uv_lock_downgrades.py`**: reads uv `Updated`/`Added`/`Removed` lines on stdin; for each `Updated <pkg> <old> -> <new>` (each side one or more `v`-prefixed versions joined by `, `), prints `<pkg>` when `max(new) < max(old)` by `packaging.version.Version`; prints the raw line prefixed `unparseable: ` for an `Updated` line that does not match; exit 0 when nothing printed, 1 otherwise.

**`scripts/refresh-uv-lock.sh <body-file>`**, seams `_UV_BIN` (default `uv`), `_MAKE_BIN` (default `make`), `REFRESH_UV_LOCK_ROOT` (default repo root):

1. `cd` to the root; copy `uv.lock` aside; run `"${_UV_BIN}" lock --upgrade` with stdout+stderr to a temp log, echoed to stderr; non-zero exits 1 with `uv lock --upgrade failed`.
2. Capture `^(Updated|Added|Removed) ` lines from the log.
3. `cmp` the lock with the copy: identical prints `no changes`, exit 0, no body.
4. Changed with zero captured lines: exit 1, `uv printed no change lines`.
5. Pipe captured lines to `python3 scripts/uv_lock_downgrades.py`; non-zero exits 1, `refusing downgrade: <pkgs>` plus the yanked-release floor hint.
6. `"${_MAKE_BIN}" sync-requirements-ci`, then `REQUIRE_TOOLS=1 "${_MAKE_BIN}" check-lock` and `REQUIRE_TOOLS=1 "${_MAKE_BIN}" check-requirements-ci`, all output to stderr; a failure exits 1 naming the target.
7. Write the body: count, captured lines, and the spec's four review steps (`gh pr close chore/uv-lock-refresh && gh pr reopen chore/uv-lock-refresh`, read, `gh pr merge chore/uv-lock-refresh --squash`, `gh workflow run uv-lock-refresh.yml`); print `changed`.

All tool output goes to stderr; stdout carries only the result word. No `git commit`, `gh` or remote writes. Temp files in a `( )` subshell with an `EXIT` trap after `mktemp -d || exit 1` (shell-010).

**Tests.** `tests/test_uv_lock_downgrades.py` (unittest): plain upgrade passes; `v2.0 -> v1.9` flags; comma `v1.15.0, v1.16.0 -> v1.16.0` passes; comma `-> v1.15.0` flags; `2.9.0.post0 -> 2.9.0.post1` passes; garbage `Updated` line is unparseable; `Added`/`Removed` lines ignored; empty input exit 0.
`tests/scripts/refresh_uv_lock.bats`: stubs read `STUB_UV_LINES` (lines printed, copied from the real capture `Updated acme v5.7.0 -> v5.9.0` etc.), `STUB_UV_EXIT`, `STUB_UV_CHANGE` (1 = rewrite fixture `uv.lock`), `STUB_MAKE_FAIL` (target to fail), `STUB_MAKE_LOG` (records target and `REQUIRE_TOOLS`); both stubs print `STUB-SENTINEL` on their stdout. Cases: unchanged; changed (body has every line and the four commands); changed with no lines; downgrade; comma downgrade; unparseable; upgrade fails; each check fails; `REQUIRE_TOOLS=1` recorded for both checks; sentinel absent from script stdout while the last line is the result word. Add the file to `tests/bats-files.txt` (`git ls-files '*.bats' | LC_ALL=C sort` after `git add`).

**Interfaces.** Produces: `scripts/refresh-uv-lock.sh <body-file>`, last stdout line `changed` or `no changes`, exit 0; non-zero on refusal. Task 3 consumes exactly this.

### Task 3: uv-lock-refresh workflow and its structure tests

```yaml-task
id: 3
description: Scheduled workflow that runs the refresh and owns the PR and failure issue
role: executor
model: sonnet
tdd: required
requirements: [R7, R8, R9, R10, R11, R12]
acceptance:
  - cmd: bats tests/scripts/uv_lock_refresh_workflow.bats
    exit_code: 0
    stdout_match: 'ok [0-9]+ .*test-shard'
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - .github/workflows/uv-lock-refresh.yml
  - tests/scripts/uv_lock_refresh_workflow.bats
  - tests/bats-files.txt
depends_on: [2]
```

Workflow per the spec's Components: workflow-level `permissions: contents: read`; one job `refresh` with `contents: write`, `pull-requests: write`, `issues: write`, `timeout-minutes: 10`, `concurrency: {group: uv-lock-refresh, cancel-in-progress: false}`, env `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: true` and `GH_TOKEN: ${{ github.token }}`; checkout `actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7` with `fetch-depth: 0`; uv install copied from `ci.yml`'s `test-shard` step (same `UV_VER`, `UV_SHA256`, `sha256sum -c`). Steps, each teeing to `${RUNNER_TEMP}/<step>.log`:

1. `bash scripts/refresh-uv-lock.sh "${RUNNER_TEMP}/body.md" | tee "${RUNNER_TEMP}/refresh.log"`; result word = `tail -n 1`, written to `$GITHUB_OUTPUT`.
2. Open refresh PR: `gh pr list --head chore/uv-lock-refresh --state open --json number,isCrossRepository --jq '[.[]|select(.isCrossRepository==false)]'`; more than one fails.
3. On `changed`: git identity, `git switch -C chore/uv-lock-refresh`, `git add` the six files by name, commit `chore(deps): refresh uv.lock`, `git push --force origin chore/uv-lock-refresh`; then `gh pr edit <n> --body-file` or `gh pr create --base master --head chore/uv-lock-refresh --title "chore(deps): refresh uv.lock" --body-file`.
4. On `no changes` with an open PR: `gh pr comment` then `gh pr close`.
5. Success: open issue with exact title `uv.lock refresh failed` (jq `.title ==`) gets a comment with the run URL and is closed.
6. `if: failure()`: create or comment the issue with the run URL and `tail -n 40` of the newest `${RUNNER_TEMP}/*.log`.

Tests (`tests/scripts/uv_lock_refresh_workflow.bats`, per-job awk/grep like `makefile_lint_scope.bats`'s CI parse): exactly two triggers (schedule cron `0 6 * * 1`, `workflow_dispatch`); workflow-level `contents: read`; job permissions exactly the three; every `uses:` 40-hex and at least one; `sha256sum -c`; `UV_VER`/`UV_SHA256` equal to `ci.yml`'s `test-shard` job values (read from that job only); `timeout-minutes: 10`; `concurrency` group; `git config user.name`/`user.email` before `git commit`; `.title ==` present and no `--search`; ordering refresh < `isCrossRepository` < `gh pr edit` < `gh pr create` < `gh pr close` < issue close < `if: failure()`, each asserted present; failure step reads `${RUNNER_TEMP}`. Add the file to `tests/bats-files.txt`.

### Task 4: Backlog rows, CLAUDE.md CI line, plan index

```yaml-task
id: 4
description: Docs-only bookkeeping (backlog, CLAUDE.md line, index); no behaviour change, so TDD does not apply
role: executor
model: sonnet
tdd: not-applicable
requirements: [R13]
acceptance:
  - cmd: make check-claude-md-budget
    exit_code: 0
  - cmd: '! grep -q "Automate the weekly .uv lock --upgrade." docs/superpowers/README.md'
    exit_code: 0
  - cmd: 'grep -qE "release-age cooldown" docs/superpowers/README.md'
    exit_code: 0
  - cmd: 'grep -q "uv-lock-refresh" CLAUDE.md'
    exit_code: 0
max_retries: 2
files_touched:
  - docs/superpowers/README.md
  - CLAUDE.md
depends_on: [3]
```

- Remove backlog row "Automate the weekly `uv lock --upgrade` and `make sync-requirements-ci` refresh".
- Add a P2 backlog row "Weekly lock refresh has no release-age cooldown" citing the spec's measurements: `--exclude-newer` writes `[options]` and fails `check-lock`; it downgrades lock-only bumps (9 at 30 days, 12 at 45, a 2026-10-26 run would revert #364); a floor younger than the cutoff fails resolution. Fix shape: restore downgraded packages with `uv lock --upgrade-package <pkg>==<master version>` after a cooldown run.
- Update the plan index row for 2026-11-08 to name this plan, status `In progress`.
- `CLAUDE.md` CI section: one bullet, `uv-lock-refresh.yml` (Monday 06:00 UTC + dispatch) opens or updates the `chore/uv-lock-refresh` PR with `GITHUB_TOKEN`; start CI with close/reopen, merge manually; failures open the `uv.lock refresh failed` issue; spec `docs/superpowers/specs/2026-11-08-uv-lock-refresh-design.md`.

The orchestrator runs `make test` once after this task.

## Non-goal check

Reviewer verdicts (2026-11-08, fresh reviewer, plan and N1-N4 only): N1 CLEAR, N2 CLEAR, N3 CLEAR, N4 CLEAR. No plan revision or amendment needed. The reviewer noted that Task 1's PR close/reopen and plan commit are the orchestrator's (operator identity), not the workflow's, and that `gh pr merge` appears only as body text.

## Probe result

Probe result: PASS (2026-11-08, Task 1, R1).

- Probe PR #444, opened by `app/github-actions` (`is_bot: true`) with `GITHUB_TOKEN` from a `push`-triggered workflow on `probe/token-pr`; head `ceae0b3e0b8388581aeb4c379f8793978278b43e`, based on `master`.
- At open, `pull_request` runs for `CI` and `PR Title Lint` were created with actor `github-actions[bot]` and completed `failure` with 0 jobs. They carry no required context, but they show red in the PR's run list until the reopen.
- After `gh pr close 444 && gh pr reopen 444` (operator identity), CI run 42511893512 (actor `brujack`) passed. The check-runs on the head SHA include `test`, `lint-macos`, `test-macos`, `powershell`, `secret-scan` and `renderings-install`, all `success`; 0 runs `action_required`; `mergeStateStatus` `CLEAN`.
- The auto-merge gate held it: `bot PR (app/github-actions) lacks automerge-ok -- leaving open for triage`. Not merged.
- Cleanup: #444 closed; `probe/token-pr` and `probe/token-pr-head` deleted on origin; nothing reached master.
