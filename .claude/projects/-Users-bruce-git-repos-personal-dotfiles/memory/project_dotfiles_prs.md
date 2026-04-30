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

**PR #57 (2026-04-29): Brewfile Linux gate** → 555 tests on master

- `_update_check_brewfile_drift` now returns SKIP immediately when `MACOS` is unset (Linux/non-macOS)
- Previous behavior ran on Linux but only skipped cask lines; now skips entirely since Brewfile is macOS-only
- All existing drift tests updated with `export MACOS=1`; one new Linux-gate test added

**PR #58 (2026-04-29): Brewfile drift leaves** → 556 tests on master

- `_update_check_brewfile_drift` now uses `brew leaves` (top-level installs only) for untracked detection, eliminating transitive-dependency noise (e.g. `abseil`, `brotli`, `zstd`)
- `brew list --formula` kept for missing detection (avoids false positives when a Brewfile entry is also a dep of another formula)
- New `MOCK_BREW_LEAVES` mock env var; new test verifying transitive deps are not flagged
- Also fixed pre-existing Linux CI bug in `scripts/sync-agent-guidance.sh` (lowercase `claude.md` → `CLAUDE.md`)

**PR #60 (2026-04-30): Brewfile drift fixup** → 557 tests on master

- `brew list --formula --full-name` for missing detection (was `--formula`, returning short names that never matched tap-qualified Brewfile entries like `teamookla/speedtest/speedtest`)
- `brew leaves` already returns tap-qualified names — untracked side was correct all along
- Brewfile formula renames: `gpg→gnupg`, `icu4c→icu4c@78`, `mongodb-atlas→mongodb-atlas-cli`, `pkg-config→pkgconf`, `openssl→openssl@3`, `python3→python@3.13`; removed duplicate `brew "gh"`
- New test: tap-qualified formula in Brewfile matches `--full-name` output → OK

Backlog: `feature/apt-reboot-required` branch still in-flight.

**Why:** Close CI gaps, add security scanning, make update workflow observable, make bootstrap scripts testable.

**How to apply:** `lib/update_summary.sh` holds all summary infrastructure. Bootstrap scripts follow ADR 0006 sourcing guard pattern. Pre-commit hook runs lint + ggshield.
