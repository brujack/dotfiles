# /whats-new-anthropic

Fetch and display the latest Anthropic platform and Python SDK changes live.

## Instructions for Claude

1. Use Bash to fetch the current platform release notes:

   ```bash
   curl -sL https://platform.claude.com/docs/en/release-notes/api | python3 -c "
   import sys, re
   content = sys.stdin.read()
   text = re.sub(r'<[^>]+>', ' ', content)
   text = re.sub(r'\s+', ' ', text).strip()
   print(text[:8000])
   "
   ```

2. Use Bash to fetch the Python SDK CHANGELOG:

   ```bash
   curl -sf https://raw.githubusercontent.com/anthropics/anthropic-sdk-python/main/CHANGELOG.md | head -200
   ```

3. Extract changes from the last 30 days based on dates in both sources.

4. Present a combined digest structured as:
   - **Model & API Changes** — new models, deprecations, beta announcements
   - **SDK Changes** — new API methods, breaking changes, client improvements
   - **Bug Fixes** — issues resolved

5. One bullet per change, one clear sentence. Skip internal tooling items.

6. Close with links to both sources:
   `[Platform release notes](https://platform.claude.com/docs/en/release-notes/api) | [Python SDK CHANGELOG](https://github.com/anthropics/anthropic-sdk-python/blob/main/CHANGELOG.md)`

## Optional flags

- `--since <date>` — show changes since a specific date (e.g. `--since 2026-01-01`)
