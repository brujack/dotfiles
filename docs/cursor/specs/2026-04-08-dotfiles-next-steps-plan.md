# Dotfiles Next Steps Plan

**Date:** 2026-04-08
**Status:** Draft
**Scope:** Define the next implementation tranche after the initial modularization and capability migration work.

## Goals

1. Shrink `setup_env.sh` into a thin dispatcher by moving remaining workflow logic into `lib/`.
2. Improve operational safety and debuggability with `doctor` and dry-run support.
3. Strengthen guardrails around secrets, local state, and CI behavior.
4. Keep changes incremental, test-backed, and low-risk.

## Non-Goals

- Full rewrite of install workflows.
- Broad behavior changes to package sets or host profile mappings.
- Replacing existing package managers or bootstrap conventions.

## Current-State Snapshot

- `lib/` modularization exists (`constants`, `helpers`, `detect_env`, `macos`, `linux`, `developer`).
- Profile/capability model is in place and documented in `CLAUDE.md`.
- `setup_env.sh` still contains large mode blocks (`setup_user`, `setup/developer`, `update`) and remains the main complexity hotspot.
- CI runs lint/tests and has auto-merge behavior that should be made more explicit and safer.

## Recommended Next Sequence

### Step 1: Extract Remaining Workflow Blocks

**Objective:** Make `setup_env.sh` orchestration-only.

- Add `lib/workflows.sh` with:
  - `run_setup_user`
  - `run_setup_or_developer`
  - `run_update`
  - `run_developer_or_ansible`
- Move existing code blocks without intentional behavior changes.
- Keep function names and command order stable where possible.

**Exit Criteria**
- `setup_env.sh` only parses args, detects env, and dispatches workflow functions.
- Existing tests pass with no behavior regression.

### Step 2: Add `doctor` and `--dry-run`

**Objective:** Improve traceability and reduce risk when running on new machines.

- Add `-t doctor` to print:
  - OS/version detection result
  - `PROFILE` and active `HAS_*` capabilities
  - key path resolutions (`PERSONAL_GITREPOS`, `CURSOR_USER_DIR`, etc.)
- Add `--dry-run` support for key mutating operations:
  - symlink operations
  - package install/upgrade commands
  - directory creation/chmod operations
- Dry-run output should show exactly what would run.

**Exit Criteria**
- `doctor` executes without side effects.
- `--dry-run` produces deterministic action output for each type.

### Step 3: Secrets and Local-State Guardrails

**Objective:** Prevent accidental commits of machine-local state and credentials.

- Add explicit ignore/override pattern for machine-local config where needed.
- Add a lightweight secret scanning step (pre-commit hook or CI job).
- Document safe handling for repo-managed Cursor and Claude files.

**Exit Criteria**
- Known secret-bearing keys are blocked from commit/merge.
- Local-only state has a documented and enforceable location.

### Step 4: CI Safety and Clarity Pass

**Objective:** Make CI behavior explicit and predictable.

- Refine `.github/workflows/ci.yml` conditions for `auto-merge` with explicit grouping.
- Restrict auto-merge scope (for example: PR-only and/or bot-only policy).
- Add at least one macOS-focused lint/syntax check job for cross-platform drift detection.

**Exit Criteria**
- CI conditionals are unambiguous.
- Auto-merge policy matches intended trust model.
- Cross-platform syntax drift is caught in CI.

### Step 5: Plan Hygiene and Status Tracking

**Objective:** Keep planning docs aligned with repository reality.

- Update `docs/cursor/specs/2026-03-31-dotfiles-improvements-plan.md`:
  - mark completed portions
  - add links to follow-on specs/plans
- Add a short “active roadmap” section to `docs/cursor/specs/README.md`.

**Exit Criteria**
- Latest status is discoverable in one place.
- Future sessions can continue without reconstructing context.

## PR Breakdown (Recommended)

1. **PR A — Workflows extraction**
   - Add `lib/workflows.sh`
   - Refactor dispatcher calls in `setup_env.sh`
   - Add/update tests for dispatch boundaries

2. **PR B — Doctor + dry-run**
   - Extend argument parsing
   - Implement doctor report
   - Add dry-run wrappers and tests

3. **PR C — Secrets/local-state policy**
   - Add ignore/override docs and rules
   - Add secret scan step
   - Add tests/docs updates

4. **PR D — CI behavior hardening**
   - Refine workflow conditionals
   - Add macOS check job
   - Verify expected triggers

5. **PR E — Documentation alignment**
   - Update prior spec status
   - Add roadmap pointers in README

## Validation Strategy

- Required local checks before each PR:
  - `make lint`
  - `make test-unit`
  - targeted BATS file for changed functionality
- For behavior-preserving refactors:
  - compare before/after logs for `-t setup_user`, `-t setup`, `-t update` in a controlled environment
- For CI changes:
  - validate trigger matrix in a branch PR before merge.

## Risks and Mitigations

- **Risk:** Workflow extraction changes runtime order.  
  **Mitigation:** keep code movement mechanical, add dispatch-level tests, and compare smoke logs.

- **Risk:** Dry-run implementation diverges from real execution path.  
  **Mitigation:** centralize command wrappers and use one execution pathway with mode flags.

- **Risk:** Secret scanning adds noise/false positives.  
  **Mitigation:** start with high-signal patterns and explicit allowlist mechanism.

- **Risk:** CI auto-merge policy changes affect merge velocity.  
  **Mitigation:** roll out in one PR with clear policy notes and fallback.

## Success Criteria

- `setup_env.sh` is materially smaller and easier to reason about.
- Running setup/update on new machines is safer and more observable.
- Secrets/local-state handling is explicit and enforced.
- CI behavior is clear, deterministic, and aligned with team intent.
