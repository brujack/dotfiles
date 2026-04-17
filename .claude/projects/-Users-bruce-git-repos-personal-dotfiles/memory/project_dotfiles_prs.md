---
name: Dotfiles session 2026-04-11
description: CI hygiene, update summary, bootstrap tests, security tooling — 450 tests on master after linux-package-update-tracking (PR #40)
type: project
---

Session 2026-04-11 completed:

- **CI hygiene (PR #21)** — CI runs on master pushes, plugin caches excluded from lint-macos, GITLEAKS_VER pinned in constants.sh, pre-commit hook (make lint + ggshield), doctor symlink root check
- **Gitleaks check-versions (PR #22)** — gitleaks added to check-versions tool list
- **Snyk token incident** — was committed in cursor settings; removed + allowlisted old commit; Snyk scan removed from CI (shell-only repo not supported by snyk code test)
- **ggshield pre-commit** — GitGuardian added to pre-commit hook, ggshield in Brewfile.devtools
- **Update summary (PR #24)** — structured end-of-run summary for `./setup_env.sh -t update` with per-section diffs (brew/gems/mas/pip/git tools), appended to ~/.dotfiles-update.log
- **Bootstrap tests (PR #25)** — both bootstrap scripts refactored per ADR 0006 (sourcing guard, function extraction, no set -e), 27 new tests
- **ADR 0006** — shell script testability conventions (#!/usr/bin/env bash, no set-e, sourcing guard)

450 tests on master (was 345 after 2026-04-11 session). Backlog: linux.sh split, Brewfile drift detection.

**Why:** Close CI gaps, add security scanning, make update workflow observable, make bootstrap scripts testable.

**How to apply:** `lib/update_summary.sh` holds all summary infrastructure. Bootstrap scripts follow ADR 0006 sourcing guard pattern. Pre-commit hook runs lint + ggshield.
