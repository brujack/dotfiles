# Claude plugins at user scope only

- **Date:** 2026-11-04
- **Repos:** dotfiles (update, prune, doctor, ADR, its own settings), ai-devops, brucejacksonconsulting-site, etch-cli, etch-config, math, state-ledger, terraform_ansible (settings only), ai-config (ADR-0046 amendment)

## Problem

Operator rule, 2026-11-04: external Claude plugins are installed at user scope only.

Measured 2026-11-04 on `claude` from `~/.claude/plugins/installed_plugins.json` (1,045,039
bytes, `version: 2`): 2,501 project-scope install records against 15 user-scope ones, for 11
plugin ids across 279 project paths. 2,407 records name a path that no longer exists (removed
worktrees and `/tmp` copies); 94 name a live path. The population is this one machine; the
other dev machines were not counted.

Two harms follow:

1. **Wrong-scope updates.** `run_update`'s claude section runs `claude plugins update
"${_name}"` with no scope (`lib/workflows.sh`, the loop after `_claude_installed_user_ids`).
   The CLI default is "auto-detect": it updates the most specific scope it finds from the cwd.
   On 2026-11-04 it moved the dotfiles project record of context-mode from 2.0.0 to 2.1.0 and
   left the user record at 2.0.0.
2. **Version skew and clutter.** A project record pins the version current when it was
   minted. Measured: 808 of the 2,501 project records carry a version other than the
   plugin's user record (`context7` 270, `code-review` 195, `security-guidance` 187,
   `skill-creator` 72, `superpowers` 64, `warp` 17, three others 1 each). Whether a session
   in that project loads the project record's older `installPath` was not measured.
   `claude plugins list` prints thousands of entries.

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

So a project `true` that repeats a user `true` mints one project record per plugin per
directory a session starts in. A `false`, or a `true` for a plugin that is off at user scope,
mints none. The test records were removed with `claude plugin uninstall -s project <id>` run
inside each directory, which left the user-scope records intact.

Every repo except ai-config carries the full core set as redundant `true` entries, because
ai-config ADR-0046 scoped `enabledPlugins` per repo by copying the whole map into each repo.
Measured per repo (redundant `true` / redundant `false` / entries that differ from the user
map):

| Repo                        | Redundant `true` | Redundant `false` | Differs from user                                                             |
| --------------------------- | ---------------- | ----------------- | ----------------------------------------------------------------------------- |
| ai-devops                   | 10               | 4                 | `frontend-design: true`                                                       |
| brucejacksonconsulting-site | 8                | 4                 | `frontend-design: true`, `pyright-lsp: false`                                 |
| dotfiles                    | 8                | 5                 | `pyright-lsp: false`                                                          |
| etch-cli                    | 8                | 4                 | `rust-analyzer-lsp: true`, `pyright-lsp: false`                               |
| etch-config                 | 8                | 5                 | `pyright-lsp: false`                                                          |
| math                        | 9                | 4                 | `rust-analyzer-lsp: true`                                                     |
| state-ledger                | 9                | 5                 | none                                                                          |
| terraform_ansible           | 8                | 3                 | `ansible-good-practices: true`, `terraform-skill: true`, `pyright-lsp: false` |

ai-config is different: its tracked `.claude/settings.json` is `~/.claude/settings.json`
through dotfiles' symlink, so in an ai-config checkout every user `true` is also a project
`true`. Its checkouts and worktrees will keep minting records whatever the other repos do.

## Design

### 1. Repo settings: list only differences from the user map

In each of the 8 repos above, delete every `enabledPlugins` entry whose value is `true` and
whose user value is also `true`. Precedence is local > project > user, so the user `true`
still applies and effective enablement in that repo is unchanged.

Kept: every entry that differs from the user map (the repo-specific additions and exclusions in
the last column), and every redundant `false`. A `false` mints no record, and it keeps the
repo excluded if that plugin is later enabled globally, which is the protection ADR-0046 exists
for.

Each repo gets its own PR, announced to its owning session first. dotfiles' own settings change
rides in the dotfiles PR. ai-config is not edited (its settings are the user settings).

### 2. dotfiles `-t update`: user-scope updates and a record prune

**Update.** The claude section calls `claude plugins update -s user "${_name}"`.

**Prune.** A new step in the same section (`_claude_prune_plugin_records`, with the JSON work
in `lib/claude_plugin_prune.py`, run as a file) reads `installed_plugins.json` and removes a
record when all of these hold:

- its `scope` is `project` or `local`; and
- either its `projectPath` does not exist as a directory, or the project at that path no
  longer sets the plugin `true` in its `.claude/settings.json` or `.claude/settings.local.json`;
  and
- the same plugin id has a `user`-scope record in the file.

The third condition means the prune never removes the last install of a plugin. `user`- and
`managed`-scope records are never touched, and neither is any top-level key other than
`plugins`.

Safety, because seven or more Claude sessions read and write this file:

- Refuse (WARN, no write) when the file does not parse, has no `plugins` object, or has a
  `version` other than 2.
- Write a timestamped backup to `~/.local/share/dotfiles/claude-plugin-backups/` before any
  change; keep the newest 5.
- Read the file's mtime and size before parsing; after building the new content, re-stat and
  skip the write (WARN) if either changed. Write to a temporary file in the same directory and
  `os.replace` it.
- Under `--dry-run`, report the counts and write nothing.

The section reports one summary line: records removed, records kept because a live project
still enables them, or the refusal reason. A refusal or a skipped write is a WARN, never a
FAIL: the update itself has succeeded.

### 3. dotfiles `-t doctor`: redundant-`true` check

`_doctor_check_plugin_scope` reads the user `enabledPlugins` map, then each
`<repo>/.claude/settings.json` for every main checkout directly under the personal repos root
(a directory whose `.git` is a directory; linked worktrees, whose `.git` is a file, carry a
branch's settings and are skipped), skipping any file whose real path equals the user settings
file. Any entry `true` in the repo
and `true` at user scope is a FAIL line naming the repo, the plugin id, and the remedy (delete
that entry). A repo with no settings file or no `enabledPlugins` passes.

### 4. Records

- dotfiles ADR: the prune edits a Claude-owned file; why that is acceptable, what it refuses,
  and the measured mint rule above.
- ai-config ADR-0046 amendment (ai-config session): per-repo maps list only differences from
  the user map; a redundant `true` mints a project install record per checkout.

### Expected end state

About 15 user-scope records, plus project records only for live ai-config checkouts (11 per
checkout). Worktrees of the other repos mint none; ai-config worktree records are pruned on the
first `-t update` after the worktree is removed.

## Testing

- bats, `tests/setup_env/`:
  - the update loop passes `-s user` (recording `tests/mocks/claude`);
  - the prune on fixture JSON files: a gone path removed; a live path whose project settings
    still set `true` kept; a live path whose settings no longer set it removed; a record whose
    plugin has no user record kept; `user` and `managed` records untouched; malformed JSON,
    missing `plugins`, `version` 3 each refused with no write; a file changed between read and
    write left untouched; `--dry-run` writes nothing; backup written and capped at 5;
  - doctor: a redundant `true` FAILs naming repo and plugin; a `false`, an addition, a missing
    file and the user-settings symlink each pass.
- All file paths through seams set at `setup()` scope: the plugins file, the user settings
  file, the personal repos root, the backup directory. No test reads or writes the real
  `~/.claude`.

## Requirements

- **R1.** `[PR1]` The claude update loop in `run_update` runs `claude plugins update -s user` for each manifest plugin.
- **R2.** `[PR1]` `_claude_prune_plugin_records` removes a `project` or `local` record only when its plugin has a `user` record and its `projectPath` is missing or no longer sets that plugin `true` in the project's settings or local settings.
- **R3.** `[PR1]` The prune never modifies `user` or `managed` records or any top-level key other than `plugins`.
- **R4.** `[PR1]` The prune writes nothing and reports a WARN when the file does not parse, lacks a `plugins` object, has a `version` other than 2, or changed (mtime or size) between read and write.
- **R5.** `[PR1]` The prune writes a timestamped backup before any change, keeps the newest 5, replaces the file atomically, and writes nothing under `--dry-run`.
- **R6.** `[PR1]` `-t doctor` FAILs on each `enabledPlugins` entry that is `true` in a personal repo's `.claude/settings.json` and `true` in the user settings, naming repo, plugin and remedy, and skips a settings file that resolves to the user settings file.
- **R7.** `[PR1]` dotfiles' `.claude/settings.json` keeps only `enabledPlugins` entries that differ from the user map, plus its redundant `false` entries.
- **R8.** `[PR2]` In each of ai-devops, brucejacksonconsulting-site, etch-cli, etch-config, math, state-ledger and terraform_ansible, `.claude/settings.json` drops every `enabledPlugins` entry that is `true` there and `true` in the user map, and changes no other entry.
- **R9.** `[PR1]` A dotfiles ADR records the prune's edit of `installed_plugins.json`, its refusal conditions and the measured mint rule.
- **V1.** After PR1 merges, one `-t update` on `claude` leaves no project or local record whose `projectPath` is missing, and `installed_plugins.json` parses.
- **V2.** After the PR2 set merges and a second `-t update`, project records exist only for live ai-config checkouts.
- **V3.** `-t doctor` on `claude` reports no redundant `true` after the PR2 set merges.
- **V4.** The ai-config session records the ADR-0046 amendment.
- **N1.** No repo's effective plugin enablement changes.
- **N2.** No redundant `false` entry is removed.
- **N3.** ai-config's `.claude/settings.json` is not edited.
- **N4.** The prune never removes a plugin's only install record.
- **N5.** No `claude plugin uninstall`, `disable` or `enable` call is added.
