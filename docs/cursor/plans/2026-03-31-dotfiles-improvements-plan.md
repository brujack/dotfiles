# Dotfiles Repo Improvements Plan

**Date:** 2026-03-31
**Status:** Superseded — see `docs/cursor/plans/2026-04-08-dotfiles-next-steps-plan.md`
**Scope:** Improve maintainability, safety, and testability of `setup_env.sh` and related repo structure without changing user-facing behavior.

## Current Status

This plan is superseded. All phases were either completed or subsumed into superpowers-tracked work.

**Completed work (as of 2026-04-08):**

- Phase 0: Baseline tests and CI established
- Phase 1: `lib/` modularization complete (`constants`, `helpers`, `detect_env`, `macos`, `linux`, `developer`)
- Phase 2: Idempotency hardening via `safe_link()` and structured logging
- Phase 3: Profile/capability model (`config/profiles.sh`, `HAS_*` vars, `PROFILE` map)
- Phase 4: CI gate active (lint + BATS tests + auto-merge)
- Phase 5: Partially complete — docs updated for profile model, lib architecture documented

**Remaining work is tracked in:**

- `docs/cursor/plans/2026-04-08-dotfiles-next-steps-plan.md`
- `docs/superpowers/specs/` and `docs/superpowers/plans/`

## Goals

1. Reduce change risk by splitting monolithic setup logic into focused modules.
2. Increase confidence through stronger automated testing and CI checks.
3. Harden installation/update flows for reliability and repeatability.
4. Preserve current machine bootstrap behavior across supported platforms.

## Non-Goals

- Rewriting the bootstrap flow in a different language.
- Removing current host-specific profiles in a single large change.
- Replatforming package managers or replacing existing tools.

## Current-State Risks

- `setup_env.sh` is very large and couples argument parsing, OS detection, symlinking, installs, and updates.
- Extensive host and OS branching makes safe edits harder and increases regression risk.
- Some install/update paths are repetitive, making drift likely.
- Test coverage exists but does not yet fully protect critical branching and idempotency paths.

## Target End State

- A modular shell architecture where each file has one responsibility.
- Shared helper library for repeated install/update patterns.
- Stronger test matrix (unit + mocked integration) covering high-risk flows.
- CI gates that prevent regressions before merge.
- Clear docs for how to run setup, update, and validation safely.

## Phased Implementation Plan

### Phase 0: Baseline and Safety Net

**Objective:** Capture current behavior before refactoring.

- Record current command behavior for:
  - `./setup_env.sh -t setup_user`
  - `./setup_env.sh -t setup`
  - `./setup_env.sh -t developer`
  - `./setup_env.sh -t ansible`
  - `./setup_env.sh -t update`
- Expand tests for existing pure functions and argument handling.
- Ensure `make lint` and `make test-unit` are green as a baseline.

**Exit Criteria**

- Behavior checklist documented and approved.
- Baseline tests pass locally.

### Phase 1: Extract Core Script Modules (No Behavior Change)

**Objective:** Split `setup_env.sh` into sourceable modules with zero intended behavior changes.

Proposed structure:

```
setup_env.sh
lib/
  constants.sh
  args.sh
  detect_env.sh
  symlinks.sh
  packages_macos.sh
  packages_linux.sh
  updates.sh
  common.sh
```

- Move constants, helper functions, and grouped operations into `lib/*.sh`.
- Keep `setup_env.sh` as orchestrator only (parse args -> detect env -> run selected workflow).
- Preserve function names initially where possible to limit migration risk.

**Exit Criteria**

- All existing tests still pass.
- A smoke run of each `-t` mode completes without functional regressions.

### Phase 2: Idempotency and File-Safety Hardening

**Objective:** Make repeated runs safer and predictable.

- Add guard helpers for file operations:
  - safe link creation
  - optional backup of non-symlink destination files
  - consistent directory creation and permissions
- Standardize command wrappers for package installs/updates with clear error handling.
- Add logging helpers for structured output (`info`, `warn`, `error`).

**Exit Criteria**

- Re-running `setup_user` twice produces no destructive side effects.
- Symlink behavior is deterministic and covered by tests.

### Phase 3: Configuration-Driven Profile Logic

**Objective:** Reduce hostname branching complexity while preserving behavior.

- Introduce profile abstraction (for example: `laptop`, `workstation`, `server`).
- Map hostnames to profiles in one place.
- Convert feature gates from raw hostname checks to profile/capability checks.

**Exit Criteria**

- Host profile map is centralized and documented.
- Existing host behavior remains unchanged.

### Phase 4: Test Expansion and CI Enforcement

**Objective:** Turn tests into a reliable merge gate.

- Add tests for:
  - OS/version detection
  - profile resolution
  - key install guard paths
  - update path decisions
  - symlink backup and overwrite behavior
- Add CI workflow running:
  - shell syntax linting
  - ShellCheck
  - `make test-unit`
  - targeted mocked integration tests

**Exit Criteria**

- CI is required for protected branches.
- New changes fail fast when core flows regress.

### Phase 5: Documentation and Operational Readiness

**Objective:** Make ongoing maintenance straightforward.

- Update README with:
  - module architecture
  - profile model
  - safe rerun expectations
  - troubleshooting
- Add contributor guide for:
  - where to place new functions
  - required tests for new logic
  - release/update checklist

**Exit Criteria**

- Documentation reflects actual architecture and workflow.
- New contributors can run tests and make safe changes without tribal knowledge.

## Work Breakdown by Deliverable

1. **Architecture extraction PR** (Phase 1)
2. **Idempotency hardening PR** (Phase 2)
3. **Profile abstraction PR** (Phase 3)
4. **CI + test depth PR** (Phase 4)
5. **Docs and maintenance guide PR** (Phase 5)

Keep PRs narrow and behavior-preserving wherever possible.

## Validation Strategy

- Local:
  - `make lint`
  - `make test-unit`
  - `make test` (where environment supports full test run)
- Behavioral:
  - smoke execution per `-t` mode in a controlled environment
  - rerun tests to verify idempotency
- Change control:
  - one phase per PR
  - explicit rollback note in each PR description

## Risks and Mitigations

- **Risk:** Refactor introduces subtle branch regressions.  
  **Mitigation:** baseline capture, phase isolation, and expanded mocked tests.

- **Risk:** Cross-platform drift during extraction.  
  **Mitigation:** keep platform-specific code in dedicated modules and run focused smoke tests.

- **Risk:** CI flakiness from environment-dependent tests.  
  **Mitigation:** keep CI tests deterministic with PATH mocks and unit-style assertions.

## Suggested Execution Order

1. Implement Phase 0 immediately (baseline + test guardrails).
2. Perform Phase 1 refactor as the first major change.
3. Apply Phase 2 hardening before profile abstraction.
4. Complete Phase 3 after confidence in modular architecture.
5. Enforce Phase 4 CI gate, then finalize docs in Phase 5.

## Success Criteria

- Setup flows remain functionally equivalent for current machines.
- Script becomes significantly easier to reason about and modify safely.
- Regressions are caught by tests/CI before merge.
- Repo gains long-term maintainability without a disruptive rewrite.
