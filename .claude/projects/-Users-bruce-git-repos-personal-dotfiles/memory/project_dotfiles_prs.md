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

**PR #61 (2026-04-30): Fix false log warning** → 558 tests on master

- `{ ... } >> file || warn` pattern: group exit code is the LAST COMMAND's exit, not the redirect's
- When `_detail_output` is empty, `[[ -n "" ]] && printf ...` exits 1 → false `|| warn` fires
- Fix: add `:` as the final command in the group so it always exits 0; `||` only fires on real redirect failure

**PR #62 (2026-04-30): Homebrew auto-tap filter + Brewfile sync** → 559 tests on master

- `brew tap` output always includes `homebrew/bundle`, `homebrew/cask`, `homebrew/core`, `homebrew/services` — Homebrew auto-installs these; filter with `grep -v -E '^homebrew/(bundle|cask|core|services)$'` before drift comparison
- Brewfile synced to actual installed state: +6 user taps, +5 formulae, +4 tap-qualified formulae, +36 casks; removed `docker-slim`; fixed sort order

**PR #63 (2026-04-30): Brewfile studio drift** → 559 tests on master

- `brew "powershell"` added — studio has it installed as both a formula and a cask
- `cask "cf-terraforming"` added — studio has it as a cask in addition to the formula

**PR #64 (2026-04-30): Brewfile capability tags** → 565 tests on master

- Inline `# [HAS_DEVTOOLS]` / `# [HAS_K8S]` etc. tags in Brewfile entries filter expected-set on machines without that capability
- `_brewfile_parse_section()` extracts capability tag via sed+grep (bash `=~` with `\[` fails on macOS; `[A-Z_]+` silently rejects `HAS_K8S` with digit)
- Fixes false "Missing" drift reports for dev tools on non-developer macs (mac_mini)

**PR #65 (2026-04-30): Suppress untracked drift for inactive-capability packages** → 568 tests on master

- Capability-tagged packages are now completely invisible to drift — neither "missing" nor "untracked" — on machines where that capability is unset
- Adds `_brewfile_extract_cap()` helper and `_brewfile_parse_inactive()` to identify inactive-profile packages
- `comm -23` strips inactive packages from installed sets before computing untracked drift
- Fixes: dev tools installed on mac_mini from prior `brew bundle` appeared as "Untracked" after PR #64 fixed the missing side

Backlog: `feature/apt-reboot-required` branch still in-flight.

**Why:** Close CI gaps, add security scanning, make update workflow observable, make bootstrap scripts testable.

**How to apply:** `lib/update_summary.sh` holds all summary infrastructure. Bootstrap scripts follow ADR 0006 sourcing guard pattern. Pre-commit hook runs lint + ggshield.
