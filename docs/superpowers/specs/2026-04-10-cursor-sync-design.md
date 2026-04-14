# Design: Cursor Configuration Sync

**Date:** 2026-04-10
**Status:** Accepted

## Context

`~/.cursor/` holds Cursor IDE configuration. The `plugins/` and `skills-cursor/` subdirectories contain plugin cache and built-in skills that should be consistent across machines. Currently these are machine-local and lost on a new machine setup.

The repo already handles `~/.claude/` using a loop-based symlink pattern: `dotfiles/.claude/*` → `~/.claude/*`, with a carve-out for subdirectories that need special handling. The same pattern applies here.

The existing Cursor handling in `setup_dotfile_symlinks()` symlinks `settings.json`, `keybindings.json`, and `snippets/` from `dotfiles/.cursor/User/` into the platform-specific app data directory (`~/Library/Application Support/Cursor/User/` on macOS, `~/.config/Cursor/User/` on Linux). This remains unchanged.

## Decision

Add a loop in `setup_dotfile_symlinks()` that symlinks `dotfiles/.cursor/*` → `~/.cursor/*`, skipping `User/` (handled by the existing block). Move `~/.cursor/plugins/` and `~/.cursor/skills-cursor/` into `dotfiles/.cursor/`.

**What gets synced** (lives in `dotfiles/.cursor/`, git-tracked per Cursor's `.gitignore`):

- `plugins/` — plugin cache
- `skills-cursor/` — built-in Cursor skills
- Any future allowlisted dirs (`skills/`, `commands/`, `plans/`, `subagents/`, `rules/`) are picked up automatically when added to `dotfiles/.cursor/`

**What stays machine-local** (real `~/.cursor/`, never in dotfiles):

- `extensions/` — large, machine-specific installs
- `ai-tracking/` — local telemetry database
- `ide_state.json`, `argv.json` — machine-local runtime state
- `.gitignore` — Cursor manages this file at `~/.cursor/.gitignore` directly
- `projects/` — project-specific MCP/transcript state

## Implementation

One addition to `setup_dotfile_symlinks()` in `lib/helpers.sh`, after the existing `.claude/` loop:

```bash
mkdir -p "${HOME}/.cursor"
for _cursor_item in "${PERSONAL_GITREPOS}/${DOTFILES}/.cursor/"*; do
  # Skip User/ — handled separately via CURSOR_USER_DIR symlinks
  [[ "$(basename ${_cursor_item})" == "User" ]] && continue
  _cursor_target="${HOME}/.cursor/$(basename ${_cursor_item})"
  safe_link "${_cursor_item}" "${_cursor_target}"
done
```

No platform guard — `~/.cursor/` is the same path on macOS and Linux.

## Testing

Tests in `tests/setup_env/extracted_functions.bats`, in the existing `setup_dotfile_symlinks` block. `_make_fake_dotfiles()` gets `dotfiles/.cursor/plugins/` and `dotfiles/.cursor/skills-cursor/` dirs added.

Three tests:

1. `setup_dotfile_symlinks creates ~/.cursor/plugins symlink` — assert symlink points into dotfiles
2. `setup_dotfile_symlinks creates ~/.cursor/skills-cursor symlink` — same
3. `setup_dotfile_symlinks does not symlink User/ under ~/.cursor` — assert `~/.cursor/User` is absent (User/ is handled by the separate CURSOR_USER_DIR block)

## Consequences

**Positive:**

- `plugins/` and `skills-cursor/` survive a fresh machine setup
- Follows the established `.claude/` loop pattern — no new concepts
- Platform-agnostic: same loop works on macOS and Linux
- Future allowlisted dirs picked up automatically

**Negative:**

- `plugins/cache/` can grow large — already git-ignored by Cursor's `.gitignore` so only `plugins/local/` (small) is tracked
- Moving `plugins/` and `skills-cursor/` from `~/.cursor/` into dotfiles requires a one-time manual migration step

## Related

- Existing `.claude/` loop in `setup_dotfile_symlinks()` (`lib/helpers.sh`)
- Existing `CURSOR_USER_DIR` block in `setup_dotfile_symlinks()` (`lib/helpers.sh`)
- `dotfiles/.cursor/User/` — settings.json, keybindings.json, snippets
