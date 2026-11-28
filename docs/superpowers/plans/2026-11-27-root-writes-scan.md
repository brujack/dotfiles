# Root-writes scan Implementation Plan

spec: docs/superpowers/specs/2026-11-27-root-writes-scan-design.md

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fail a CI test shard when the bats suite changed real host paths under `/etc /usr/local /usr/share/keyrings /opt`, measured on the filesystem rather than through mock-call ledgers.

**Architecture:** `scripts/root-writes.sh` (`mark` / `check`) walks each resolved root with `find -newer/-cnewer` against a marker; the `test-shard` and `test-macos-shard` jobs in `ci.yml` mark before the bats work and check after it. Before the CI wiring merges, a never-merged scratch branch measures background writers and proves a deliberate escape is caught.

**Tech Stack:** bash, GNU and BSD `find`/`ls`, bats, GitHub Actions.

## Global Constraints

- Roots: `/etc /usr/local /usr/share/keyrings /opt`; `ROOT_WRITES_ROOTS` replaces them only when `BATS_TEST_TMPDIR` is non-empty (use `_bats_seam` from `lib/helpers.sh`).
- Resolve each root with `cd <root>/. && pwd -P`; walk with `find <resolved> -xdev`, no `-H`.
- No Makefile target runs the scan (N2). No change to `assert_no_real_root_paths`, `_unguarded_path_resets` or any ledger (N1). The scan never writes, moves or deletes under its roots (N4). No check the two jobs run today is dropped or weakened (N5).
- Prunes never equal or contain `/etc/apt`, `/etc/docker`, `/etc/sysctl.d`, `/usr/share/keyrings`, `/usr/local/bin`, `/opt/homebrew`, `/private/etc/apt`, `/private/etc/docker`, `/private/etc/sysctl.d`.
- No test may run the real `sudo`: the script resolves sudo through `ROOT_WRITES_SUDO` (default `sudo`), honoured only under bats; tests point it at a stub.
- Never name `lib/workflows.sh` in a Bash command (a privacy hook refuses it).
- `make test` takes about 3 minutes on `claude`, under the 600 s tool cap.

## Verification (session level)

- `make test </dev/null` exits 0 with 0 `not ok`, and the root-directory snapshot is unchanged across it.
- The scratch-branch rollout (orchestrator step O1) records V1-V3: 10 null windows per OS all `none` with clean `find` status, 2 suite windows per OS with visited counts and scan time, and a red step showing `root-writes: the suite changed real host paths:` for a deliberate `/usr/bin/sudo` escape on both OSes.
- After merge, every shard log shows `root-writes: none (` with non-zero counts for non-empty roots (V4).

---

### Task 1: `scripts/root-writes.sh` with fixture-root tests

```yaml-task
id: 1
description: Add scripts/root-writes.sh (mark, check, prune list) and tests/scripts/root_writes.bats covering R1-R8 and R12 against fixture roots
role: executor
model: sonnet
tdd: required
requirements: [R1, R2, R3, R4, R5, R6, R7, R8, R12]
acceptance:
  - cmd: bats tests/scripts/root_writes.bats
    exit_code: 0
    stdout_match: 'ok [0-9]+ check reports a file created after the marker'
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [scripts/root-writes.sh, tests/scripts/root_writes.bats, tests/bats-files.txt]
depends_on: []
```

**Behaviour (from the spec's Requirements, verbatim strings):**

- `mark <marker>` creates the file; exit 1 if it cannot.
- `check <marker>`: per existing root, resolve (`cd <root>/. && pwd -P`), decide emptiness with `ls -A <root>/.` run with the same privilege as `find`, walk with `find <resolved> -xdev`, each prune as `-path <p> -prune -o`, then `\( -newer <marker> -o -cnewer <marker> \) -print`. Count entries visited below the root.
- Output: hits → `root-writes: the suite changed real host paths:` then one path per line, exit 1. Clean → `root-writes: none (<root> <count>, ...)`, exit 0. Missing root → skipped and named. Empty root (listing succeeds, empty) → `empty: <root>`, not a failure. Listing refused → exit 1. Non-empty listing but zero visited below → exit 1. Missing marker → exit 1.
- Privilege: if `"${ROOT_WRITES_SUDO}" -n true` succeeds, `find` and `ls` run through `"${ROOT_WRITES_SUDO}" -n`, and any non-zero `find` status exits 1. Otherwise run as the user; `find` status 1 is accepted only if every stderr line ends in `Permission denied`, each such directory printed as `not scanned: <dir>`, hits elsewhere still reported; any other status or stderr line exits 1.
- Prune lists: `ROOT_WRITES_PRUNE_LINUX=()` and `ROOT_WRITES_PRUNE_DARWIN=()` (empty), chosen by `uname -s`; `ROOT_WRITES_PRUNE` replaces the chosen list only under bats.
- Source `lib/helpers.sh` for `_bats_seam`; sourcing guard on the last line, shell standards (`#!/usr/bin/env bash`, no `set -e`, `[[ ]]`, `printf`).

**Tests (`tests/scripts/root_writes.bats`, write each failing first):** untouched → `none` with counts, exit 0; file created / rewritten / chmodded / deleted after the marker each reported (deletion as its directory), exit 1; symlinked root resolved and a file created through it reported; mutation of the resolution away fails the check (assert in the test via a copy of the script with the `pwd -P` line removed, or record it as the task's mutation control); empty root → `empty:`, exit 0; listing refused (stub sudo absent, chmod 000 root) → exit 1; without sudo an unreadable subdirectory → `not scanned:` and a hit beside it still reported; a non-`Permission denied` stderr line → exit 1; with a stub sudo that execs its arguments, a non-zero `find` → exit 1; missing marker → exit 1; missing root skipped and named; `ROOT_WRITES_ROOTS` ignored with `BATS_TEST_TMPDIR` empty; prune: a write beside a pruned subtree reported, inside it not; a test reading both prune arrays fails if any entry equals or contains a forbidden directory. Set the marker's mtime in the past (`touch -t`) so ns-equal timestamps cannot hide a hit. Compare paths after `pwd -P` (macOS `/var/folders` resolves to `/private/var/folders`). Every PATH a test builds uses `refusing_sudo_path`.

**Interfaces:** Produces `bash scripts/root-writes.sh mark <file>` and `check <file>` with the outputs above, consumed by Task 2.

### Task 2: Wire the scan into `test-shard` and `test-macos-shard`

```yaml-task
id: 2
description: Run root-writes mark/check around the bats work in both CI shard jobs, composing exit statuses, with a per-job ci.yml test
role: executor
model: sonnet
tdd: required
requirements: [R9, R10]
acceptance:
  - cmd: bats tests/scripts/ci_root_writes.bats
    exit_code: 0
    stdout_match: 'ok [0-9]+ test-shard marks before the shard-1 prerequisites step'
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [.github/workflows/ci.yml, tests/scripts/ci_root_writes.bats, tests/bats-files.txt]
depends_on: [1]
```

**Changes:**

- `test-shard`: a new step `Mark root-writes window` running `bash scripts/root-writes.sh mark "${RUNNER_TEMP}/root-writes.marker"`, placed before `Run test prerequisites (shard 1 only)` and running on every shard. `Run traced suite` becomes `set +e; make bash-coverage < /dev/null; rc=$?; bash scripts/root-writes.sh check "${RUNNER_TEMP}/root-writes.marker"; check_rc=$?; [ "${rc}" -ne 0 ] && exit "${rc}"; exit "${check_rc}"` (its run body today is exactly `make bash-coverage < /dev/null`, ci.yml line 98, so no existing line is dropped; its `env:` block is kept unchanged, and the separate `Check executed tests equal declared` step is unchanged).
- `test-macos-shard` `Run tests`: `mark` before the make `if`; after the existing `ci-suite-report.sh` call, run `check`; exit with make's status if make failed, else the report's if it failed, else `check`'s. Keep every existing line of that step (log path, report call, `printf 'make exited %d'`).

**Test (`tests/scripts/ci_root_writes.bats`)** in the per-job style of `tests/scripts/ci_test_shard.bats` (`_job_text` / comment stripping, never grep the whole file): `test-shard marks before the shard-1 prerequisites step`; its suite step runs `check` after `make bash-coverage` with no `exit` between; its final exit can come from `check_rc`; `test-macos-shard` runs `mark` before make and `check` after the report call with no `exit` between make and `check`; the macOS step still exits with the report status when make passed and the report failed. Show each fails against the unwired `ci.yml` first.

### Task 3: Backlog rows

```yaml-task
id: 3
description: Rewrite the two guard Backlog rows as measured watch items and add a builtin-read-probe row (docs-only, no behaviour change, so TDD does not apply)
role: executor
model: haiku
tdd: not-applicable
requirements: [R11]
acceptance:
  - cmd: 'grep -c "Measured 2026-11-27: 0 hidden hits" docs/superpowers/README.md'
    exit_code: 0
    stdout_match: '^2$'
  - cmd: 'grep -q "builtin read probes" docs/superpowers/README.md'
    exit_code: 0
max_retries: 2
files_touched: [docs/superpowers/README.md]
depends_on: []
```

- Row "The real-root-path guard has blind spots": keep its text, append `Measured 2026-11-27: 0 hidden hits (private ledgers of tfenv.bats, repo_sessions.bats and zshrc.d/unit.bats; the 64 files without load_mocks; multi-line PATH builds). The CI root-writes scan (spec 2026-11-27-root-writes-scan-design.md) now catches any write these blind spots would hide; kept as a watch item.`
- Row "The refusing-sudo PATH guard sees single-line assignments only": append the same `Measured 2026-11-27: 0 hidden hits ...` sentence adapted to multi-line PATH builds (0 in tracked .bats files).
- New P3 row: `| Builtin read probes make test outcomes depend on host state | Tests that probe the host with builtins such as [[ -f /etc/... ]] pass on a provisioned box and fail on a clean runner (the class behind dotfiles#495's CI failure); no write is involved, so the root-writes scan does not cover it. |`

### Task 4: ADR-0062

```yaml-task
id: 4
description: Write ADR-0062 recording the CI root-writes scan decision and index it (docs-only, so TDD does not apply)
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: test -f docs/adr/0062-ci-root-writes-scan.md
    exit_code: 0
  - cmd: 'grep -q "0062" docs/adr/README.md'
    exit_code: 0
max_retries: 2
files_touched: [docs/adr/0062-ci-root-writes-scan.md, docs/adr/README.md]
depends_on: [2]
```

Context, Decision, Consequences, Related, following `docs/adr/0061-doctor-hook-identity-and-ggshield-probe.md`'s shape. Decision: a filesystem scan in CI around the bats work, fail-only, CI-only; no local mode (noise measured on `claude`); prune list with forbidden install directories; not tamper-proof. Related: the spec, dotfiles#494/#495/#497, the plan. Add the index row in `docs/adr/README.md` with status Accepted.

---

## Orchestrator steps

- **O1, after Task 2 (V1-V3, before the feature PR leaves draft):** branch `scratch/root-writes-rollout` from the feature branch; add `.github/workflows/root-writes-null.yml` (`on: push` to that branch only; matrix `os: [ubuntu-latest, macos-latest]`, `run: [1..10]`; steps: checkout, `mark`, `sleep` the longest shard's measured suite duration, `check`, print `find` status/stderr) and `tests/scripts/root_writes_escape.bats` (no `load_mocks`; `[[ -n ${GITHUB_ACTIONS:-} ]] || skip`; `/usr/bin/sudo touch /usr/local/bin/root-writes-escape`), listed in `tests/bats-files.txt`. Push it (pre-push skips the escape locally) and open it as a **draft** PR so `ci.yml` runs; re-run the ci jobs once for the second suite window. Record V1 (20 null outputs), V2 (4 suite outputs, counts, scan time, macOS `sudo -n true`) and V3 (red step with the hit line on both OSes) in the feature PR body. Any hit or non-clean status: amend the spec (prune under R12) or stop. Then close the draft PR and delete the branch.
- **O2:** open the feature PR as `gh pr create --draft`; `gh pr ready` only after O1's results are recorded and Phase 3 passes.
- **O3, after merge (V4):** read every shard log for `root-writes: none (` with non-zero counts for non-empty roots; record in the PR body.

## Non-goal check

Reviewer output (`nongoal.json`): N1 CLEAR, N2 CLEAR, N3 CLEAR, N4 CLEAR, N5 UNCLEAR.

- **N5 — UNCLEAR.** Quote: "Task 2: `Run traced suite` becomes `set +e; make bash-coverage < /dev/null; rc=$?; ... exit "${check_rc}"`". Why: "becomes" could drop lines beyond `make bash-coverage`. Resolution: plan revision after checking the repo (ci.yml line 98: the step's run body is exactly `make bash-coverage < /dev/null`). Before: "(the separate `Check executed tests equal declared` step is unchanged)." After: "(its run body today is exactly `make bash-coverage < /dev/null`, ci.yml line 98, so no existing line is dropped; its `env:` block is kept unchanged, and the separate `Check executed tests equal declared` step is unchanged)."
