# Claude Code — New Features Digest

Weekly summaries of Claude Code changes, generated every Monday at 8am Eastern.

## Files

- `features-YYYY-MM-DD.md` — weekly digest committed each Monday
- `.changelog-state.md` — last-fetched CHANGELOG snapshot used to compute diffs (do not edit manually)

## Generating a digest

```bash
# Run manually (commits and pushes if changes found):
scripts/whats-new-claude-code.sh

# Preview without writing or committing:
scripts/whats-new-claude-code.sh --dry-run

# On-demand in Claude Code (fetches live from GitHub):
/whats-new
```

Set `NTFY_URL` in your environment to also push the digest to your ntfy instance.

## Automated schedule

A remote Claude Code routine runs every Monday at 8am Eastern and commits the digest automatically. Manage it at https://claude.ai/code/routines
