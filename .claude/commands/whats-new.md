# /whats-new

Fetch and display the latest Claude Code features and changes live from GitHub.

## Instructions for Claude

1. Use Bash to fetch the current CHANGELOG:

   ```bash
   curl -sf https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md
   ```

2. Use Bash to fetch recent releases for additional context:

   ```bash
   curl -sf "https://api.github.com/repos/anthropics/claude-code/releases?per_page=5"
   ```

3. Extract changes from the last 30 days based on dates in the CHANGELOG.

4. Present a digest structured as:
   - **New Features** — user-facing additions
   - **Improvements** — enhancements to existing behavior
   - **Bug Fixes** — issues resolved

5. Use the release version and date as a subheading for each release block.

6. One bullet per change, one clear sentence. Skip internal-only or tooling-only items.

7. Close with: `Latest version: X.Y.Z — [Full CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)`

## Optional flags

- `--since <date>` — show changes since a specific date (e.g. `--since 2025-01-01`)
- `--versions <n>` — show the last N versions instead of 30-day window (default: all within 30 days)
