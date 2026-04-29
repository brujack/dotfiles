---
name: Dotfiles session 2026-04-11
description: CI hygiene, update summary, bootstrap tests, security tooling — 450 tests on master after linux-package-update-tracking (PR #40)
type: project
originSessionId: 5df32ae8-b5d6-4a2f-91ba-7c1898f285c3
---

Session 2026-04-11 completed:

- **CI hygiene (PR #21)** — CI runs on master pushes, plugin caches excluded from lint-macos, GITLEAKS_VER pinned in constants.sh, pre-commit hook (make lint + ggshield), doctor symlink root check
- **Gitleaks check-versions (PR #22)** — gitleaks added to check-versions tool list
- **Snyk token incident** — was committed in cursor settings; removed + allowlisted old commit; Snyk scan removed from CI (shell-only repo not supported by snyk code test)
- **ggshield pre-commit** — GitGuardian added to pre-commit hook, ggshield in Brewfile.devtools
- **Update summary (PR #24)** — structured end-of-run summary for `./setup_env.sh -t update` with per-section diffs (brew/gems/mas/pip/git tools), appended to ~/.dotfiles-update.log
- **Bootstrap tests (PR #25)** — both bootstrap scripts refactored per ADR 0006 (sourcing guard, function extraction, no set -e), 27 new tests
- **ADR 0006** — shell script testability conventions (#!/usr/bin/env bash, no set-e, sourcing guard)

450 tests on master after 2026-04-11 session.

**PR #54 (2026-04-28): linux.sh split** → 536 tests on master

- lib/linux.sh deleted; replaced by linux_shared.sh, linux_ubuntu.sh, linux_rhel.sh
- 12 private _install_ubuntu_\* helpers extracted from 658-line monolith
- New test files: linux_shared.bats, linux_rhel.bats (8 tests), linux_ubuntu.bats (42 tests), developer.bats (3 tests)

**PR #56 (2026-04-29): Brewfile drift detection** → 554 tests on master

- `_update_check_brewfile_drift` in `lib/update_summary.sh` compares Brewfile vs installed packages (formulae, casks on macOS, taps)
- New `[WARN]` status in `_update_summary`: non-blocking, detail block printed below table
- `_update_ok` and `_update_warn` direct-write helpers (bypass `_update_record_start`/end)
- `_OVERRIDE_BREWFILE_PATH` test seam; `quiet_which brew` for mock-testability
- 19 new tests: 6 WARN infra in `update_summary.bats`, 13 drift tests in new `brewfile_drift.bats`
- Wired into `run_update()` just before `_update_summary`

Backlog: empty.

**Why:** Close CI gaps, add security scanning, make update workflow observable, make bootstrap scripts testable.

**How to apply:** `lib/update_summary.sh` holds all summary infrastructure. Bootstrap scripts follow ADR 0006 sourcing guard pattern. Pre-commit hook runs lint + ggshield.
