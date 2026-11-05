# Claude plugins at user scope only

- **Date:** 2026-11-04
- **Approved:** 2026-11-05
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
   `skill-creator` 72, `superpowers` 64, `warp` 17, three others 1 each). For 260 of those
   (`code-review` 131, `security-guidance` 123 and others) the project and user records share
   a `gitCommitSha` and differ only in the version string, so the content skew is closer to 548.
   `claude plugins list` also prints thousands of entries.

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
removes a record when all of these hold:

- its `scope` is `project` or `local`;
- its plugin id has a `user`-scope record in the file; and
- the user record is at least as new as it, decided in this order: if the two `version`
  strings are equal, the record is removed without reading any timestamp; otherwise it is
  removed only when the user record's `lastUpdated` is at or after the record's own. Timestamps
  are parsed with the explicit format `%Y-%m-%dT%H:%M:%S.%fZ` (every value in the file has that
  form, measured: 2,516 of 2,516), because `datetime.fromisoformat` rejects the trailing `Z`
  before Python 3.11 and the Studio's `/usr/bin/python3` is 3.9. When versions differ and either
  timestamp is missing or does not parse, the record is kept.

The freshness condition decides from the file, not from the update's exit code. Some project
records are newer than their user record: the old unscoped update moved the project record and
left the user record behind. Measured on `claude`, dotfiles main checkout: `caveman` project
4.0.1 against user 2.7.0, `firecrawl` 2.3.0 against 1.0.9, `context-mode` 2.1.0 against 2.0.0.
Pruning such a record would let the next session re-mint the older user version, a silent
downgrade. An exit code cannot rule that out: in Claude Code 2.1.318 the update's non-failure
outcomes include "up to date", "was not checked for updates" and "skipped", none of which
proves the user record moved. A failed, skipped or unchecked update leaves the user
`lastUpdated` behind, so the newer record is kept until a user update overtakes it.

Dry run on the live file (2026-11-05, read-only simulation of this rule): 2,498 records would
be removed and exactly 3 kept, the three dotfiles records above; no record lacks `lastUpdated`.

The rule assumes a no-op user update leaves the user record's `lastUpdated` alone. Measured
2026-11-05 on `claude`: `claude plugins update -s user caveman@caveman` moved the user record
from 2.7.0 (`lastUpdated` 2026-09-15T16:27:41.612Z) to 4.0.1 (2026-11-05T14:37:03.717Z); a
second run reported "already at the latest version (4.0.1)" and left `lastUpdated` unchanged.
One exception exists in the 2.1.318 code: for a plugin whose marketplace source is a command,
an "up to date" outcome rewrites `lastUpdated` when the source command changed, without moving
the version. No record on `claude` has such a source (no `sourceCommand` key); the ADR names it.

The prune still runs after the update loop so that a user update in the same run can make a
newer project record prunable. It runs even when the update loop failed: the freshness
condition makes that safe.

It does not read any project's settings: whatever a project enables, its next session re-mints
what it needs at the user version. (A project `true` for a plugin whose user value is `false`
mints nothing, probes D and F; such a project loads it from the user record as before.)

Kept untouched: `user` and `managed` records, every record the user record is not at least as
new as, a project or local record whose plugin has no user record, and every top-level key other
than `plugins`.

Effect on live checkouts: a session started after the prune loads the user version of each
plugin. A session already running keeps the version it loaded. The prune leaves cache
directories with no record pointing at them (93 of 108 `installPath`s on `claude` are named only
by project records), and Claude Code marks such a directory `.orphaned_at` and later deletes it.
A directory a running session uses carries `.in_use/<pid>` entries: measured, `context-mode/1.0.169`
has been orphan-marked since 2026-11-04 12:37 and still exists with five `.in_use` pids from
sessions started 2026-11-03. The prune relies on the same protection Claude Code's own updates
rely on every time they supersede a version; it orphans more directories at once, not a new
kind.

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

The section reports one summary line: the UTC time the prune read the file, records removed
and kept, or the refusal reason. The newest backup is the before-state for V1. A
refusal or a skipped write is a WARN, never a FAIL: the update itself has succeeded.

### 3. ADR

A dotfiles ADR records why the prune edits a Claude-owned file, its refusal conditions, the
freshness condition and the downgrade it prevents (and why exit codes cannot decide it), its dependency on a no-op update leaving `lastUpdated` alone and the command-source exception, the measured mint and load rules, that live
checkouts move to the user version, its reliance on `.in_use` protection for running sessions,
and that records minted between updates go stale again when the official marketplace
auto-updates, so the remaining skew is bounded by how often `-t update` runs.

### Not done (backlog)

Stripping the redundant `true` entries from the 8 repos' settings would mint fewer records
between updates. With the prune it changes no plugin version, so it is filed as a backlog row
to pick up only if the prune is ever removed. The proposed `-t doctor` check is dropped with it.

### Expected end state

After each `-t update` whose updates all succeed: the 15 user-scope records, plus any record
minted by a session started after the prune. Records minted between updates carry the user
version current at minting, which an official-marketplace auto-update can overtake before the
next `-t update`.

## Testing

- bats, `tests/setup_env/`:
  - the update loop passes `-s user` (recording `tests/mocks/claude`);
  - the update loop runs before the prune;
  - the prune on a fixture with 4 project records, 2 user records (`lastUpdated`
    2026-10-01T00:00:00Z) and 1 managed record: one record at the user version (removed), one
    older record with a different version and `lastUpdated` 2026-09-01 (removed), one newer
    record with a different version and `lastUpdated` 2026-10-15 (kept), one record whose plugin
    has no user record (kept): exactly 2 removed, 2 kept, the user and managed records and the
    `version` key unchanged (compared after parsing);
  - the update mock exits 0 reporting "already at the latest version" while a newer-dated
    project record exists for that plugin: that record survives (0 removed for that id);
  - a record with no `lastUpdated`, and one with an unparsable value, at a version other than
    the user's: both kept;
  - a record at the user's version with an unparsable `lastUpdated`: removed (the version check
    decides first);
  - the timestamp parser accepts the file's `...123Z` form under the interpreter `run_update`
    uses (a unit test of the parse helper with a real value);
  - a fixture with no project records: no write, no backup, "0 removed";
  - malformed JSON, missing `plugins`, `version` 3: each refused with no write and no backup;
  - an mtime change with the same size between read and replace: write skipped (driven by a
    seam that touches the file before the re-stat);
  - an inode change (the file replaced by a same-content copy) between read and replace: write
    skipped;
  - `--dry-run` on the 4-record fixture reports "2 removed" and leaves the file unchanged;
  - the summary line carries a UTC timestamp;
  - the backup is written and capped at 5.
- All file paths through seams set at `setup()` scope: the plugins file and the backup
  directory. No test reads or writes the real `~/.claude`.

## Requirements

- **R1.** `[PR1]` The claude update loop in `run_update` runs `claude plugins update -s user` for each manifest plugin.
- **R2.** `[PR1]` After the update loop, `_claude_prune_plugin_records` removes a `project` or `local` record only when its plugin id has a `user` record and either the two `version` strings are equal (decided before any timestamp is read) or the user record's `lastUpdated` is at or after the record's own; with differing versions, a missing or unparsable timestamp keeps the record.
- **R3.** `[PR1]` The prune never modifies `user` or `managed` records or any top-level key other than `plugins`.
- **R4.** `[PR1]` The prune writes nothing and reports a WARN when the file does not parse, lacks a `plugins` object, has a `version` other than 2, or its mtime or inode changed between the first stat and the re-stat immediately before the replace.
- **R5.** `[PR1]` The prune writes a timestamped backup before any change, keeps the newest 5, replaces the file atomically, writes nothing when no record qualifies, and writes nothing under `--dry-run`.
- **R6.** `[PR1]` A dotfiles ADR records the prune's edit of `installed_plugins.json`, its refusal conditions, the freshness condition and why an exit code cannot decide it, the measured mint and load rules, the version effect on live checkouts, its reliance on `.in_use` protection, and that skew between updates is bounded by update cadence.
- **R7.** `[PR1]` A dotfiles Backlog row records stripping redundant `true` entries from repo settings, to be done only if the prune is removed.
- **R8.** `[PR1]` The prune's summary line reports the UTC time it read the file.
- **R9.** `[PR1]` The prune parses timestamps with the explicit format `%Y-%m-%dT%H:%M:%S.%fZ` and runs on Python 3.9.
- **V1.** After PR1 merges, one `-t update` on `claude` leaves no `project` or `local` record with `installedAt` earlier than the summary line's prune time except those whose user record is older (the kept newer records), 15 user records whose versions match the newest backup's, and a file that parses.
- **V2.** A `claude -p --output-format stream-json --verbose` session started in the etch-config main checkout after that update reports `superpowers` at the post-update user record's version, not 6.3.0 (its pre-prune project record).
- **V3.** One hour after that update, with the long-running sessions still up, V1's `installedAt` check still holds and the user record count is still 15 (a pre-prune `installedAt` reappearing means a session wrote back a stale copy).
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

### Round 2

Reviewed at commit: `d0d24aaa` (all three lenses re-run; the revision changed design substance)

- Risk and Goal-Fit, independently: the prune ran whatever the update did, so a project record
  newer than its user record (dotfiles: `caveman` 4.0.1 vs 2.7.0, `firecrawl` 2.3.0 vs 1.0.9,
  `context-mode` 2.1.0 vs 2.0.0) would be deleted after a failed or skipped update and re-minted
  older. Disposition: Addressed — prune only ids whose user update exited 0 this run, skip the
  prune when the loop did not run (R2, R8), tests for both.
- Goal-Fit: V2 passed without the prune, since the update equalizes `context-mode`.
  Disposition: Addressed — V2 pins etch-config `superpowers` 7.0.0 against its 6.3.0 record.
- Goal-Fit: records minted between updates go stale again on an official-marketplace
  auto-update. Disposition: Accepted, reason: bounded by `-t update` cadence; recorded in the
  ADR (R6).
- Goal-Fit: the backlog row would be dead with the prune in place. Disposition: Addressed —
  reworded to "only if the prune is removed" (R7).
- Ergonomics: V1 as worded fails whenever a session starts after the prune. Disposition:
  Addressed — V1 compares `installedAt` with the prune time.
- Ergonomics: the prune orphans most of the cache at once and relies on unnamed `.in_use`
  protection. Disposition: Accepted, reason: same protection Claude Code's own updates rely on,
  observed holding for `context-mode/1.0.169`; recorded in the ADR (R6).
- Ergonomics: no test for the inode half of the guard. Disposition: Addressed — test added.
- Goal-Fit assumption: a pruned file stays pruned (no stale write-back). Disposition:
  Addressed — V3 counts dead-path records an hour after the prune.
- Risk assumption: `update -s user` can move the lagging user records. Settled by V1 (the
  first post-merge run either moves them or the updated-set rule keeps their project records).

### Round 3

Reviewed at commit: `e42c102a` (all three lenses)

- Goal-Fit and Risk, independently: exit 0 does not prove the user record moved (Claude Code
  2.1.318's non-failure outcomes include "up to date", "not checked for updates" and
  "skipped"), so the updated-set rule could still downgrade. Disposition: Addressed — the prune
  decides from the file (`version` equal or user `lastUpdated` at or after the record's); the
  updated set and the skip-when-no-loop requirement are removed; dry-run on the live file keeps
  exactly the 3 newer records.
- Ergonomics and Goal-Fit: V3 counted dead-path records, which ordinary short-lived worktrees
  mint every day (62 in 24 h). Disposition: Addressed — V3 re-checks V1's `installedAt`
  condition and the user count.
- Ergonomics: V2 pinned 7.0.0, which an update in the same run could move; V1 and V3 had no
  recorded prune time or before-state. Disposition: Addressed — V2 compares with the post-update
  user version; the summary line carries the prune time (R8) and the newest backup is the
  before-state.
- Risk: no test for an "already latest" exit 0 while a newer project record exists.
  Disposition: Addressed — test added.
- Goal-Fit: 260 of the 808 skewed records differ only in the version string. Disposition:
  Addressed — noted in the Problem section; the harm stands without them.

### Round 4 (scoped: Risk lens on the round-3 changes)

Reviewed at commit: `a586371d`

- F1: the rule did not say whether an unparsable timestamp blocks an equal-version removal; on
  the Studio (`/usr/bin/python3` 3.9) `fromisoformat` rejects every `...Z` value, so the prune
  would silently remove nothing. Disposition: Addressed — version equality decides first;
  explicit `%Y-%m-%dT%H:%M:%S.%fZ` parsing on 3.9 (R2, R9); fixtures added.
- F2: a command-source plugin's "up to date" outcome can advance `lastUpdated` without the
  version. Disposition: Addressed — not live on `claude`; recorded in the Design section and
  the ADR (R6).
- Assumption (no-op update leaves `lastUpdated` alone): settled by measurement, operator
  approved — two `update -s user caveman@caveman` runs; the second, a no-op, left
  `lastUpdated` unchanged.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.

## Amendments

- finding R4 (2026-11-05, reviewer B): DIFFERS — Parse failure, non-dict, version != 2 and missing plugins object refuse before any write (lines 156-164) and the wrapper returns 2 so run_update adds a message (workflows.sh:1025), but the change guard compares a signature of (st_mtime_ns, st_ino, st_size) for both the resolved file and the lstat of the link path, so it also refuses on a size or link-path change the requirement does not name (and the ADR in the same diff states 'Size is not compared'); in the changed branch it has already written a backup and temp file and deletes them rather than writing nothing.
- R4 -> The prune writes nothing and reports a WARN when the file does not parse, lacks a `plugins` object, or has a `version` other than 2; when the `st_mtime_ns`, `st_ino` or `st_size` of the resolved file or of its link path (`os.lstat`) changed between the first stat and the re-stat immediately before the replace, it removes the backup and temp file it had written, leaves the plugins file untouched and reports a WARN. — review hardening added the size and link-path checks; a changed-file run cleans up its own files rather than writing nothing at all.
- finding R6 (2026-11-05, reviewer A): DIFFERS — The ADR records all listed topics, but its refusal conditions state "Size is not compared: Claude rewrites the file at byte-identical size", while the code's race signature is `(st.st_mtime_ns, st.st_ino, st.st_size)` (lib/claude_plugin_prune.py:262, docstring line 276 'mtime, inode and size') and test_size_change_exit4 exists, so the ADR misstates the refusal conditions it is required to record (it also omits the link-path lstat comparison).
- R6 reviewed: fixed in 2eec1e2d
- finding R2 (2026-11-05, reviewer B): DIFFERS — The prune runs after the loop (workflows.sh:1019-1025) and the user-record, timestamp >= and missing/unparsable-keeps rules match, but the equal-version branch fires only when both versions are non-empty strings (`_nonempty_str(mine_v) and _nonempty_str(user_v)`, line 45), so two equal empty-string versions are not removed on equality and fall through to the timestamp rule, a narrower condition than 'the two version strings are equal' (conservative edge case).
- R2 -> After the update loop, `_claude_prune_plugin_records` removes a `project` or `local` record only when its plugin id has a `user` record and either both `version` values are non-empty strings and equal (decided before any timestamp is read) or the user record's `lastUpdated` is at or after the record's own; otherwise, including a missing or unparsable timestamp, the record is kept. — review found that two missing or empty versions compared equal and removed a record on no evidence; the narrower rule fails closed.

## Spec alignment (2026-11-05)

- spec: docs/superpowers/specs/2026-11-04-claude-plugin-user-scope-design.md
- anchor: 9a90aa04e03e46f9f5b1a046b9601f12354a62ff
- in scope: R1, R2, R3, R4, R5, R6, R7, R8, R9
- out of scope: none

### Findings

| ID | Reviewer | Verdict | Reason | Amendment |
| --- | --- | --- | --- | --- |
| R2 | B | DIFFERS | The prune runs after the loop (workflows.sh:1019-1025) and the user-record, timestamp >= and missing/unparsable-keeps rules match, but the equal-version branch fires only when both versions are non-empty strings (`_nonempty_str(mine_v) and _nonempty_str(user_v)`, line 45), so two equal empty-string versions are not removed on equality and fall through to the timestamp rule, a narrower condition than 'the two version strings are equal' (conservative edge case). | - R2 -> After the update loop, `_claude_prune_plugin_records` removes a `project` or `local` record only when its plugin id has a `user` record and either both `version` values are non-empty strings and equal (decided before any timestamp is read) or the user record's `lastUpdated` is at or after the record's own; otherwise, including a missing or unparsable timestamp, the record is kept. — review found that two missing or empty versions compared equal and removed a record on no evidence; the narrower rule fails closed. |

### Reviewed

- R6 reviewed: fixed in 2eec1e2d

### Verifications

- V1: no evidence recorded
- V2: no evidence recorded
- V3: no evidence recorded
