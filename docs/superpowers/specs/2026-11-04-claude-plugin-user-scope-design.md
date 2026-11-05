# Claude plugins at user scope only

- **Date:** 2026-11-04
- **Repos:** dotfiles only (update loop, record prune, ADR). No other repo's settings change; ai-config ADR-0046 stands.

## Problem

Operator rule, 2026-11-04: external Claude plugins are installed at user scope only.

Measured 2026-11-04 on `claude` from `~/.claude/plugins/installed_plugins.json` (1,045,039
bytes, `version: 2`): 2,501 project-scope install records against 15 user-scope ones, for 11
plugin ids across 279 project paths (280 by a later count; new records are minted
continuously). 2,407 records name a path that no longer exists (removed worktrees and `/tmp`
copies); 94 name a live path. The population is this one machine; the other dev machines were
not counted.

Two harms follow:

1. **Wrong-scope updates.** `run_update`'s claude section runs `claude plugins update
"${_name}"` with no scope (`lib/workflows.sh`, the loop after `_claude_installed_user_ids`).
   The CLI default is "auto-detect": it updates the most specific scope it finds from the cwd.
   On 2026-11-04 it moved the dotfiles project record of context-mode from 2.0.0 to 2.1.0 and
   left the user record at 2.0.0.
2. **Sessions run stale plugin versions.** A session loads the project record's `installPath`,
   not the user record's. Measured: a `claude -p --output-format stream-json --verbose` session
   started in the dotfiles main checkout reported `context-mode` at
   `.../context-mode/2.1.0`, the version only the dotfiles project record names (the user
   record is 2.0.0). A project record pins the version current when it was minted and is never
   updated by a user-scope update, and 808 of the 2,501 project records carry a version other
   than their plugin's user record (`context7` 270, `code-review` 195, `security-guidance` 187,
   `skill-creator` 72, `superpowers` 64, `warp` 17, three others 1 each). `claude plugins
list` also prints thousands of entries.

### Where the project records come from (measured)

The documentation says project `enabledPlugins` alone never fetches a plugin
(code.claude.com/docs/en/plugins/loading.md: "When a plugin's only true is in the project's
.claude/settings.json, Claude Code doesn't fetch it onto a machine where it isn't installed").
It does not say whether a session records a project-scope install for a plugin already
installed at user scope. Six probes on `claude` (Claude Code 2.1.318), each a fresh `git init`
directory, one `claude -p --model haiku "Reply with exactly: ok"` run inside it, then a read of
`installed_plugins.json` for that `projectPath`:

| Probe | Project `.claude/settings.json` | User value                | Records minted    |
| ----- | ------------------------------- | ------------------------- | ----------------- |
| A     | `caveman@caveman: true`         | true                      | 1 (`caveman`)     |
| B     | no `enabledPlugins`             | —                         | 0                 |
| C     | `caveman@caveman: false`        | true                      | 0                 |
| D     | `rust-analyzer-lsp: true`       | false (installed at user) | 0                 |
| E     | `superpowers: true`             | true                      | 1 (`superpowers`) |
| F     | `skill-creator: true`           | false (installed at user) | 0                 |

A project `true` that repeats a user `true` mints one project record per plugin per directory a
session starts in. Every repo carries the core set as such entries, because ai-config ADR-0046
scopes `enabledPlugins` per repo by listing the whole map; ai-config's own settings file is the
user settings file through dotfiles' symlink. The test records were removed with
`claude plugin uninstall -s project <id>` run inside each directory, which left the user-scope
records intact.

A minted record copies the current user version: the eight records minted at
2026-11-05T03:21Z all carry their plugin's user version (for example `context-mode` 2.0.0,
`superpowers` 7.0.0, `context7` fa4eb54397ee).

## Design

Remove project records after every user-scope update and let sessions re-mint them. A session
started after the prune mints records at the fresh user version, so the version a project
session loads tracks the user record. No repo's settings change, so ADR-0046's per-repo
enablement is untouched.

### 1. User-scope updates

The claude section calls `claude plugins update -s user "${_name}"`.

### 2. Record prune, after the update loop

A new step in the same section, after the update loop (`_claude_prune_plugin_records`, with the
JSON work in `lib/claude_plugin_prune.py`, run as a file), reads `installed_plugins.json` and
removes every record whose `scope` is `project` or `local` and whose plugin id also has a
`user`-scope record in the file. It does not read any project's settings: whatever a project
enables, its next session re-mints what it needs at the user version.

Kept untouched: `user` and `managed` records, a project or local record whose plugin has no
user record, and every top-level key other than `plugins`.

Effect on live checkouts: a session started after the prune loads the user version of each
plugin. A session already running keeps the version it loaded; Claude Code's own updates
already leave running sessions on a superseded cache directory.

Safety, because many Claude sessions read and write this file:

- Refuse (WARN, no write) when the file does not parse, has no `plugins` object, or has a
  `version` other than 2.
- Write a timestamped backup to `~/.local/share/dotfiles/claude-plugin-backups/` before any
  change; keep the newest 5.
- Record `st_mtime_ns` and `st_ino` before reading. Re-stat immediately before the replace and
  skip the write (WARN) if either changed. Size is not compared: Claude rewrites the file with
  byte-identical size (measured: a 22:58 snapshot and the 23:00:37 file were both 1,045,039
  bytes and differed only in key order). Write to a temporary file in the same directory and
  `os.replace` it. A Claude write that lands between the re-stat and the replace is lost; the
  worst case is losing another session's `plugins update`, whose previous version directory
  still exists, and the next run of either repairs it.
- Under `--dry-run`, report the counts and write nothing.

The section reports one summary line: records removed and kept, or the refusal reason. A
refusal or a skipped write is a WARN, never a FAIL: the update itself has succeeded.

### 3. ADR

A dotfiles ADR records why the prune edits a Claude-owned file, its refusal conditions, the
measured mint rule, the measured load rule, and that live checkouts move to the user version.

### Not done (backlog)

Stripping the redundant `true` entries from the 8 repos' settings would mint fewer records
between updates. With the prune it changes no plugin version, so it is optional hygiene, filed
as a backlog row. The proposed `-t doctor` check is dropped with it.

### Expected end state

After each `-t update`: the 15 user-scope records only. Between updates, records re-minted by
new sessions, all at the current user version.

## Testing

- bats, `tests/setup_env/`:
  - the update loop passes `-s user` (recording `tests/mocks/claude`);
  - the update loop runs before the prune;
  - the prune on a fixture with 3 project records (one gone path, one live path, one plugin
    without a user record), 2 user records and 1 managed record: exactly 2 project records
    removed, the record without a user record kept, the user and managed records and the
    `version` key byte-for-byte unchanged in meaning (compared after parsing);
  - a fixture with no project records: no write, no backup, "0 removed";
  - malformed JSON, missing `plugins`, `version` 3: each refused with no write and no backup;
  - an mtime change with the same size between read and replace: write skipped (driven by a
    seam that touches the file before the re-stat);
  - `--dry-run` on the 3-record fixture reports "2 removed" and leaves the file unchanged;
  - the backup is written and capped at 5.
- All file paths through seams set at `setup()` scope: the plugins file and the backup
  directory. No test reads or writes the real `~/.claude`.

## Requirements

- **R1.** `[PR1]` The claude update loop in `run_update` runs `claude plugins update -s user` for each manifest plugin.
- **R2.** `[PR1]` After the update loop, `_claude_prune_plugin_records` removes every `project` or `local` record whose plugin id has a `user` record, and no other record.
- **R3.** `[PR1]` The prune never modifies `user` or `managed` records or any top-level key other than `plugins`.
- **R4.** `[PR1]` The prune writes nothing and reports a WARN when the file does not parse, lacks a `plugins` object, has a `version` other than 2, or its mtime or inode changed between the first stat and the re-stat immediately before the replace.
- **R5.** `[PR1]` The prune writes a timestamped backup before any change, keeps the newest 5, replaces the file atomically, writes nothing when no record qualifies, and writes nothing under `--dry-run`.
- **R6.** `[PR1]` A dotfiles ADR records the prune's edit of `installed_plugins.json`, its refusal conditions, the measured mint and load rules, and the version effect on live checkouts.
- **R7.** `[PR1]` A dotfiles Backlog row records stripping redundant `true` entries from repo settings as optional hygiene.
- **V1.** After PR1 merges, one `-t update` on `claude` leaves only `user`-scope records in `installed_plugins.json`, the user record count unchanged (15) and each user record's version unchanged by the prune, and the file parses.
- **V2.** A `claude -p --output-format stream-json --verbose` session started in the dotfiles main checkout after that update reports `context-mode` at the user record's version.
- **N1.** No repo's `.claude/settings.json` or `.claude/settings.local.json` is edited.
- **N2.** The prune never removes a plugin's only install record.
- **N3.** No `claude plugin uninstall`, `disable` or `enable` call is added.
- **N4.** The prune reads no project's settings file.

## Multi-Lens Review

Reviewed at commit: `45248bed` (Step 7 self-review commit, before Step 8 dispatch)

### Goal-Fit

Finding: Worth doing but about twice the needed size. Shipping `-s user` before the repo strips stops project records from updating while live checkouts keep them; the recurring prune's value rests on whether sessions load the project record (then unmeasured); the doctor check is close to decoration (no copier of `enabledPlugins` exists, output ephemeral). V1 and V2 passed on an empty `plugins` map. Premise reproduced (2,501 / 15, 94 live / 2,407 gone, `version` 2).
Assumption: a session in a project loads that project's record rather than the user record. Measured afterwards: true (dotfiles session loaded `context-mode` 2.1.0, the project record's version).
Disposition: Addressed — design reduced to `-s user` plus a prune of every project record with a user counterpart, after the update; repo strips and doctor check dropped to backlog; V1 now pins the user record count and versions.

### Ergonomics

Finding: The doctor FAIL fires when the operator enables a plugin globally rather than when a repo changes, its remedy is a PR in another session's repo, and lagging machines would FAIL after the fix landed; doctor tests passed on an empty repos root.
Assumption: a pruned file stays pruned (long-running sessions might write back a stale full copy). Unresolved: no write by another session had occurred by review time. The prune repeats every update, so a write-back costs a repeat, not a failure.
Disposition: Addressed — doctor check dropped.

### Risk

Finding: The size half of the race guard never fires (Claude rewrites the file at byte-identical size); a write between re-stat and replace is lost but bounded. N1 covered enablement, not version: the prune moves live checkouts to the user version. A project settings file that fails to parse was unspecified. Fixture tests passed when nothing was written. `/etc/claude-code` absent and no `settings.local.json` sets `enabledPlugins`, so precedence cannot mask a change.
Assumption: same as Goal-Fit; measured true.
Disposition: Addressed — guard uses `st_mtime_ns` and `st_ino` re-stated before the replace; update runs before the prune and the ADR records the version effect; the prune no longer reads project settings (N4), so the parse case is gone; tests pin exact removed and kept counts.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.
