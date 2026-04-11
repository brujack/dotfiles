---
name: Dotfiles PRs 19 and 20
description: Two major feature PRs opened 2026-04-10 — workflows refactor and interactive version update
type: project
---

Two PRs opened 2026-04-10, pending CI auto-merge:

**PR #19** — `refactor: split run_setup_or_developer and run_developer_or_ansible into named helpers`
- `lib/workflows.sh` reduced from 1,437 → 343 lines
- Extracted 12 named functions into `lib/macos.sh`, `lib/linux.sh`, `lib/developer.sh`
- ~20 new BATS tests

**PR #20** — `feat: add --update flag to check-versions for interactive pin updates`
- `--update` flag on `check-versions` prompts per-tool to update `lib/constants.sh` in-place
- Handles URL constants embedding the version (GO_DOWNLOAD_FILENAME, GO_DOWNLOAD_URL, YQ_URL)
- `_OVERRIDE_CONSTANTS_PATH` test seam pattern used for test isolation
- 11 new BATS tests

**Why:** Improve maintainability of the install scripts and reduce manual effort for version pin updates.

**How to apply:** When these PRs merge, the main `lib/workflows.sh` will be a thin dispatcher; any future installs go into the appropriate platform lib file.
