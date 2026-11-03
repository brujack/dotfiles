# filelock 4.2.1 Upgrade Implementation Plan

> **Status: DONE** (dotfiles#422, merged 2026-11-03)

spec: docs/superpowers/specs/2026-11-02-filelock-4-upgrade-design.md

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move `filelock` from 3.32.3 to 4.2.1 in `uv.lock` and its three renderings, and prove the venv's filelock consumers still lock correctly.

**Architecture:** One lock command, one render command, one scratch-only verification harness (V2). The PR is held by the auto-merge gate's lock-only rule; the operator merges it.

**Tech Stack:** uv, GNU make, bats, Python 3.14.

## Global Constraints

- `pyproject.toml` does not change (N1). Only `filelock` changes version in `uv.lock` (N2). No change to `checkov`, `packaging` or `virtualenv` (N3).
- Never hand-edit a rendering; regenerate with `make sync-requirements-ci`.
- V2 runs only inside a `mktemp -d` archive copy; never touch `~/.pyenv`, the real ansible venv, or the real `HOME`. Remove the copy with its full path written out.

## Verification

- Session: `make test` green; CI legs green; the `auto-merge` job prints `uv.lock changed without pyproject.toml -- leaving open for a human` (V1, V4).
- V2 (Task 1): both venvs, three checks, numbers recorded for the PR body.
- V3 (orchestrator, after the operator merges): the spec's exact `gh api` query reports `48 filelock fixed` and `30 virtualenv open`.

---

### Task 1: Lock, render, verify

```yaml-task
id: 1
description: Bump filelock to 4.2.1 in uv.lock, regenerate the renderings, and run the V2 consumer harness in a scratch copy (dependency bump, no code path to test-drive; V2 is the behavioural check)
role: executor
model: sonnet
tdd: not-applicable
requirements: [R1, R2]
acceptance:
  - cmd: 'bash -c ''grep -A1 "^name = \"filelock\"" uv.lock | grep -qx "version = \"4.2.1\""'''
    exit_code: 0
  - cmd: 'bash -c ''test "$(git diff --name-only origin/master -- uv.lock "requirements*.txt" | sort | tr "\n" " ")" = "requirements-ci-audit.txt requirements-ci.txt requirements-runtime-ci.txt uv.lock "'''
    exit_code: 0
  - cmd: 'bash -c ''test "$(git diff -U0 origin/master -- uv.lock | grep -cE "^[-+]version = ")" -eq 2'''
    exit_code: 0
  - cmd: make check-requirements-ci
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [uv.lock, requirements-ci.txt, requirements-ci-audit.txt, requirements-runtime-ci.txt]
depends_on: []
```

Gate proof on the base tree (`fc12e583`): gate 1 exits 1 (version is 3.32.3), gate 2 exits 1 (empty diff), gate 3 exits 1 (0 version lines changed).

- [ ] `uv lock --upgrade-package filelock==4.2.1`; expect exactly `Updated filelock v3.32.3 -> v4.2.1`.
- [ ] `make sync-requirements-ci`; expect changes only in the three renderings that already carry `filelock`.
- [ ] Run gates 1–4.
- [ ] **V2** in `D=$(mktemp -d)`:
  - Extract the head tree (`git stash create` if uncommitted, else `HEAD`) to `$D/head` and the base (`origin/master`) to `$D/base`. In each, `UV_PROJECT_ENVIRONMENT="$D/<side>/.venv" uv sync --frozen --group runtime --group test-lint`.
  - Probe: `$D/probe/sitecustomize.py` that wraps `filelock.BaseFileLock.acquire` and appends `<pid> filelock=<filelock.__version__> <type(self).__name__>` to `$D/<side>.acq` on each call; set `PYTHONPATH="$D/probe"`.
  - Environment for every run: `PATH="$D/<side>/.venv/bin:$PATH"`, `HOME="$D/<side>/home"` (fresh, so ansible-lint's cache is fresh), `ANSIBLE_COLLECTIONS_PATH="$D/<side>/collections"`.
  - (a) `$D/play/site.yml` with exactly:
    ```yaml
    - hosts: localhost
      tasks:
        - shell: echo hi
    ```
    Run `ansible-lint site.yml` from `$D/play`. Pass: rc 2; output names exactly `command-instead-of-shell`, `fqcn[action-core]`, `name[missing]`, `name[play]`, `no-changed-when` (amended; see the spec's Amendments); exactly 1 acquire line in the log for this run.
  - (b) `virtualenv "$D/<side>/vv"`: rc 0 and at least 1 acquire.
  - (c) contention: a Python process holds `filelock.FileLock("$D/c.lock")` and signals ready; a second process's `FileLock("$D/c.lock").acquire(timeout=0.1)` raises `filelock.Timeout`.
  - Every run: output contains no `/.pyenv/`, and every log line reports that side's version (4.2.1 head, 3.32.3 base).
  - Report a table of side × check with rc, findings, acquire count; remove `$D` (`rm -rf -- "<full path>"`).
- [ ] `make test` (log-and-poll), then commit `fix(deps): bump filelock to 4.2.1` with the four files only.

### Orchestrator

- [ ] Phase 3, PR body leading with: "Lock-only PR: the auto-merge gate holds it (dotfiles#227); merge by hand after reading the 6-line `uv.lock` diff."
- [ ] Confirm the `auto-merge` job printed the lock-only hold (V4); ask the operator to merge.
- [ ] After merge, wait for Dependabot to rescan, then run the spec's V3 query; record its output.
- [ ] On master: close the filelock Backlog row; add a P2 row for the 30 `virtualenv` alerts blocked by `checkov`'s `packaging<24` pin (checkov 3.4.3 still declares it); mark this plan Done; tell the ai-devops session that state-ledger's byte-copied renderings can now be refreshed.

## Non-goal check

Run inline by the orchestrator (Opus), 2026-11-02, reading only this plan and the spec's N list (subagent
dispatches were being refused by the session's permission classifier; operator's standing rule: run inline and
disclose).

- N1 CLEAR. `files_touched` excludes `pyproject.toml`; gate 2 fails if any file beyond the four changes.
- N2 CLEAR. Gate 3 requires exactly two `version =` lines in the `uv.lock` diff (filelock's old and new).
- N3 CLEAR. No step names `checkov`, `packaging` or `virtualenv` except V2's read-only use of `virtualenv`.
