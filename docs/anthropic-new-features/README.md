# Anthropic & Claude API — New Features Digest

Weekly summaries of Anthropic platform and Python SDK changes, generated every Monday at 8am Eastern.

## Files

- `features-YYYY-MM-DD.md` — weekly digest committed each Monday
- `.platform-state.txt` — last-fetched platform release notes (HTML-stripped; do not edit manually)
- `.sdk-state.md` — last-fetched Python SDK CHANGELOG snapshot (do not edit manually)

## Generating a digest

```bash
# Run manually (commits and pushes if changes found):
scripts/whats-new-anthropic.sh

# Preview without writing or committing:
scripts/whats-new-anthropic.sh --dry-run

# On-demand in Claude Code (fetches live):
/whats-new-anthropic
```

Set `NTFY_URL` in your environment to also push the digest to your ntfy instance.

## Sources

- [Anthropic Platform release notes](https://platform.claude.com/docs/en/release-notes/api)
- [Python SDK CHANGELOG](https://github.com/anthropics/anthropic-sdk-python/blob/main/CHANGELOG.md)

## Automated schedule

A remote Claude Code routine runs every Monday at 8am Eastern and commits the digest automatically. Manage it at https://claude.ai/code/routines
