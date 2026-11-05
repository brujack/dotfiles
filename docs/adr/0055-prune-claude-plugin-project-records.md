# ADR-0055: Prune Claude plugin project records after user-scope updates

**Date:** 2026-11-05
**Status:** Accepted

## Context

External Claude plugins are installed at user scope only (operator rule, 2026-11-04). Measured
2026-11-04 on `claude`, in `~/.claude/plugins/installed_plugins.json` (1,045,039 bytes,
`version: 2`): 2,501 project-scope records against 15 user-scope ones, 2,407 naming a path that no
longer exists. Two harms:

1. `run_update` ran `claude plugins update <name>` with no scope, which auto-detects from the cwd.
   It moved the dotfiles project record of `context-mode` to 2.1.0 and left the user record at 2.0.0.
2. A session loads the project record's `installPath`, not the user record's. Measured: a
   `claude -p --output-format stream-json --verbose` session in the dotfiles main checkout loaded
   `context-mode` 2.1.0, the version only the project record names. 808 of the 2,501 records carry a
   version other than their plugin's user record.

Mint rule, measured on Claude Code 2.1.318 with six probes (fresh `git init` directory, one
`claude -p` run, then a read of the file):

| Probe | Project value            | User value | Records minted |
| ----- | ------------------------ | ---------- | -------------- |
| A     | `caveman` true           | true       | 1              |
| B     | no map                   | -          | 0              |
| C     | `caveman` false          | true       | 0              |
| D     | `rust-analyzer-lsp` true | false      | 0              |
| E     | `superpowers` true       | true       | 1              |
| F     | `skill-creator` true     | false      | 0              |

A project `true` repeating a user `true` mints one project record per plugin per directory a session
starts in. ai-config ADR-0046 lists the whole map in every repo, so every repo does this. A minted
record copies the current user version.

## Decision

1. **`-t update` runs `claude plugins update -s user`**, then `_claude_prune_plugin_records`
   (`lib/workflows.sh`, JSON work in `lib/claude_plugin_prune.py`, run as a file) removes project and
   local records. A session started afterwards re-mints records at the user version, so the version a
   project session loads tracks the user record. No repo's settings change; ADR-0046 stands.
2. **Why edit a Claude-owned file:** the CLI has no bulk verb for this, and one
   `plugin uninstall -s project` per record, run inside each project directory, cannot reach
   the 2,407 records whose directory is gone.
3. **Refusal conditions (WARN, no write):** the file does not parse, has no `plugins` object, has a
   `version` other than 2, or the `st_mtime_ns`, `st_ino` or `st_size` of the resolved file, or of
   the link path itself (`os.lstat`), changed between the first stat and a re-stat immediately
   before the replace; such a run removes its own backup and temp file and exits 4. Size alone
   cannot detect a Claude rewrite (measured: it rewrites at byte-identical size), so mtime and
   inode carry the guard and size only adds a case. The window between the re-stat and
   `os.replace` cannot be closed without a lock. Any `OSError` is a refusal. A timestamped backup in
   `~/.local/share/dotfiles/claude-plugin-backups/` is written first (newest 5 kept); the prune never
   writes without one. The write is a temp file in the same directory plus `os.replace`.
4. **Freshness rule.** A project or local record is removed only when its plugin has a user record
   and either the two `version` strings are equal (decided before any timestamp is read) or the user
   record's `lastUpdated` is at or after the record's own. When versions differ and either timestamp
   is missing or unparsable, the record is kept. Timestamps parse with `%Y-%m-%dT%H:%M:%S.%fZ`
   (2,516 of 2,516 values match), because `datetime.fromisoformat` rejects the trailing `Z` before
   Python 3.11 and the Studio's `/usr/bin/python3` is 3.9.
5. **The downgrade this prevents.** The old unscoped update left project records newer than their user
   record. Measured in the dotfiles checkout: `caveman` project 4.0.1 against user 2.7.0, `firecrawl`
   2.3.0 against 1.0.9, `context-mode` 2.1.0 against 2.0.0. Pruning those would let the next session
   re-mint the older user version. **An exit code cannot decide this:** in Claude Code 2.1.318 the
   update's non-failure outcomes include "up to date", "was not checked for updates" and "skipped",
   none of which proves the user record moved. The decision comes from the file.
6. **No-op `lastUpdated`.** The rule assumes a no-op user update leaves the user `lastUpdated` alone.
   Measured 2026-11-05: `update -s user caveman@caveman` moved the record from 2.7.0 to 4.0.1; a
   second run reported "already at the latest version (4.0.1)" and left `lastUpdated` unchanged.
   **Exception:** in 2.1.318 a plugin whose marketplace source is a command has its `lastUpdated`
   rewritten by an "up to date" outcome when the source command changed, without a version move. No
   record on `claude` has such a source (no `sourceCommand` key).

## Consequences

- Dry run on the live file (2026-11-05): 2,498 records removed, 3 kept (the three above).
- **Load rule (measured):** a dotfiles session loaded `context-mode` 2.1.0 from the project record, so
  after the prune live checkouts move to the user version. A running session keeps the version it
  loaded.
- The prune leaves cache directories with no record pointing at them (93 of 108 `installPath`s on
  `claude`); Claude Code marks them `.orphaned_at` and later deletes them. **It relies on `.in_use`
  protection:** `context-mode/1.0.169` has been orphan-marked since 2026-11-04 12:37 and still exists
  with five `.in_use` pids from sessions started 2026-11-03. Claude Code's own updates rely on the same
  protection each time they supersede a version; the prune orphans more at once, not a new kind.
- Records minted between updates go stale again when the official marketplace auto-updates, so skew is
  bounded by how often `-t update` runs.
- A Claude write landing between the re-stat and the replace is lost. The worst case is losing another
  session's `plugins update`, whose previous version directory still exists; the next run of either
  repairs it.
- Stripping the redundant `true` entries from the repos is a Backlog row, to pick up only if the prune
  is removed.

## Related

- Spec: [`docs/superpowers/specs/2026-11-04-claude-plugin-user-scope-design.md`](../superpowers/specs/2026-11-04-claude-plugin-user-scope-design.md)
- Plan: [`docs/superpowers/plans/2026-11-05-claude-plugin-user-scope.md`](../superpowers/plans/2026-11-05-claude-plugin-user-scope.md)
- ai-config ADR-0046: per-repo `enabledPlugins`, which mints the records
- `lib/claude_plugin_prune.py` and `_claude_prune_plugin_records` in `lib/workflows.sh`
