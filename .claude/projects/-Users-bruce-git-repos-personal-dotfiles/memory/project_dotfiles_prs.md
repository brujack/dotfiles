---
name: Dotfiles PRs 19 and 20
description: Both PRs merged 2026-04-11 — workflows refactor and interactive version update
type: project
---

Both PRs merged 2026-04-11. Branches and worktrees cleaned up.

**PR #19** ✅ merged — `refactor: split run_setup_or_developer and run_developer_or_ansible into named helpers`
- `lib/workflows.sh` reduced from 1,437 → 343 lines
- Extracted 12 named functions into `lib/macos.sh`, `lib/linux.sh`, `lib/developer.sh`
- ~20 new BATS tests; 254 tests total on master

**PR #20** ✅ merged — `feat: add --update flag to check-versions for interactive pin updates`
- `--update` flag on `check-versions` prompts per-tool to update `lib/constants.sh` in-place
- Handles URL constants embedding the version (GO_DOWNLOAD_FILENAME, GO_DOWNLOAD_URL, YQ_URL)
- `_OVERRIDE_CONSTANTS_PATH` test seam pattern used for test isolation

**Why:** Improve maintainability of the install scripts and reduce manual effort for version pin updates.

**How to apply:** `lib/workflows.sh` is now a thin dispatcher; future platform-specific installs go into `lib/macos.sh`, `lib/linux.sh`, or `lib/developer.sh`.
