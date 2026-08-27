# CI Job Timeouts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give all 7 CI jobs a `timeout-minutes` cap so a hung job cannot block `auto-merge` for GitHub's 360-minute default.

**Architecture:** Seven job-level `timeout-minutes` keys across two workflow files, each sized from a measured p90, plus one documentation line. No new tooling, no new dependency, no test. Spec: `docs/superpowers/specs/2026-08-27-ci-job-timeouts-design.md` @ `1ac17b7`.

**Tech Stack:** GitHub Actions workflow YAML. Acceptance gates use `python3` + `pyyaml`, which is present on this machine (6.0.3) and deliberately **not** in CI.

## Global Constraints

- Exact caps, copied from the spec's Values table. Any other value fails the gate:
  `test: 20`, `bash-coverage: 25`, `powershell: 5`, `lint-macos: 10`, `secret-scan: 10`, `auto-merge: 10` (all `.github/workflows/ci.yml`); `pr-title-lint: 10` (`.github/workflows/pr-title-lint.yml`).
- Every cap carries a trailing comment naming its measured p90 and the date, e.g. `timeout-minutes: 20 # p90 342s, measured 2026-08-27`.
- `.github/workflows/*.yml` is **not** on `is_safe_file`'s safe-list in `~/.claude/hooks/sdlc-branch-guard.sh` (which lists `*.md|*.txt|*.rst|*.mdc`, `renovate.json|.gitleaks.toml|.editorconfig|.gitignore|LICENSE`, plus a key-scoped `.claude/settings.json`). This is code: feature branch + PR + full Phase 3 chain. Not direct to master.
- **Nothing in `make test` asserts these values.** The spec dropped a guard test deliberately after three review rounds; do not add one. `make test` and `make lint` are regression checks here, not gates on the deliverable — the two `python3` asserts are the discriminating gates.
- Do not add `pyyaml` to any workflow. The acceptance gates run locally in Phase 2 only.
- Job-level `timeout-minutes` is not an accepted key on a reusable-workflow (`uses:`) job. All 7 jobs use `steps:`, so this does not arise; do not add a cap to a `uses:` job if one appears.

## Verification Planning

**Command that proves the change works:**

```bash
python3 -c "import yaml;d=yaml.safe_load(open('.github/workflows/ci.yml'))['jobs'];assert [d[k].get('timeout-minutes') for k in ('test','lint-macos','powershell','bash-coverage','secret-scan','auto-merge')]==[20,10,5,25,10,10]"
python3 -c "import yaml;d=yaml.safe_load(open('.github/workflows/pr-title-lint.yml'))['jobs'];assert d['pr-title-lint'].get('timeout-minutes')==10"
make lint && make test
```

**Expected:** both `python3` commands exit 0 silently; `make lint` and `make test` exit 0.

**Falsifiability, measured 2026-08-27 before this plan was written** — the gate is not a coin that only lands one way:

| tree | result |
| --- | --- |
| base (pre-change) | exit **1**, `AssertionError` — both files |
| head simulation | exit **0**, both files |
| mutant `bash-coverage: 25` -> `26` | exit **1**, `AssertionError` |

Exit 1 throughout, never 2/4/127, so the failure is the assert firing rather than a missing file or binary. `.get()` is used rather than `[...]` so an absent key yields `AssertionError` rather than `KeyError`.

**A wrong implementation that would still pass a weaker gate:** `timeout-minutes: 999` on all six `ci.yml` jobs satisfies any presence-or-count check. The gates above compare exact values, so it fails — verified with the `25 -> 26` mutant.

**Edge case the gate deliberately catches:** if a job is added or renamed, the gate's job tuple no longer matches the file and the task fails. That is correct — the plan is then wrong, not the gate. Update the plan.

**Stated limit:** nothing here proves a cap actually fires. That needs a real hang, which cannot be manufactured on demand. GitHub enforces the declaration; the gates prove it is present and correct.

---

### Task 1: Declare timeout-minutes on all 7 CI jobs

```yaml-task
id: 1
description: Add job-level timeout-minutes to all 7 jobs across both workflows and document the caps in CLAUDE.md (config and docs only; no code path changes, so TDD does not apply)
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: python3 -c "import yaml;d=yaml.safe_load(open('.github/workflows/ci.yml'))['jobs'];assert [d[k].get('timeout-minutes') for k in ('test','lint-macos','powershell','bash-coverage','secret-scan','auto-merge')]==[20,10,5,25,10,10]"
    exit_code: 0
  - cmd: python3 -c "import yaml;d=yaml.safe_load(open('.github/workflows/pr-title-lint.yml'))['jobs'];assert d['pr-title-lint'].get('timeout-minutes')==10"
    exit_code: 0
  - cmd: make lint
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - .github/workflows/ci.yml
  - .github/workflows/pr-title-lint.yml
  - CLAUDE.md
depends_on: []
```

**Files:**

- `.github/workflows/ci.yml` — 6 jobs, add one line to each
- `.github/workflows/pr-title-lint.yml` — 1 job, add one line
- `CLAUDE.md` — one bullet in the "CI / GitHub Actions" section

**Interfaces:**

- Consumes: nothing (first and only task)
- Produces: nothing consumed by a later task

**Steps:**

- [ ] Confirm you are on a feature branch, not `master`: `git branch --show-current`
- [ ] In `.github/workflows/ci.yml`, insert `timeout-minutes` immediately **after** each job's `runs-on:` line, one per job, with the trailing comment:
  - `test:` -> `    timeout-minutes: 20 # p90 342s, measured 2026-08-27`
  - `lint-macos:` -> `    timeout-minutes: 10 # p90 12s, floor, measured 2026-08-27`
  - `powershell:` -> `    timeout-minutes: 5 # p90 60s, measured 2026-08-27`
  - `bash-coverage:` -> `    timeout-minutes: 25 # p90 492s, measured 2026-08-27`
  - `secret-scan:` -> `    timeout-minutes: 10 # p90 8s, floor, measured 2026-08-27`
  - `auto-merge:` -> `    timeout-minutes: 10 # p90 11s, floor, measured 2026-08-27`
- [ ] In `.github/workflows/pr-title-lint.yml`, after `runs-on:` in the `pr-title-lint` job: `    timeout-minutes: 10 # p90 4s, floor, measured 2026-08-27`
- [ ] Run the two `python3` gates from Verification Planning above. Both must exit 0.
- [ ] In `CLAUDE.md`, in the "CI / GitHub Actions" bulleted list, add a final bullet after the `auto-merge` bullet:
  `- Every job declares `timeout-minutes`, sized ~3x its measured p90 with a 10-minute floor on the short jobs (`test` 20, `bash-coverage` 25, `powershell` 5, the rest 10). Nothing in the suite asserts these — a guard test was specified and dropped, see `docs/superpowers/specs/2026-08-27-ci-job-timeouts-design.md`.`
- [ ] Run `make lint` then `make test`. Both must exit 0.
- [ ] Invoke `caveman:caveman-commit` to generate the commit message, then commit all three files.
