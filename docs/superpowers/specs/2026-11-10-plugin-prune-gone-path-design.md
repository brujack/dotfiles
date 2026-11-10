# Plugin prune: remove records whose project directory is gone

**Date:** 2026-11-10
**Status:** Draft
**Backlog row:** "Claude Code writes a project-scope plugin record per project and worktree, and
none is ever removed" (P2, bugs/security)

## Problem

ADR-0055's prune (`lib/claude_plugin_prune.py`, run by `-t update`) removes a `project` or `local`
record from `~/.claude/plugins/installed_plugins.json` only when the plugin also has a `user`
record at least as new (decision 4). A record for a plugin with no user record is kept forever,
even when its `projectPath` no longer exists. The backlog row closed on 2026-11-07 with "revisit
only if one appears". One has appeared.

Measured 2026-11-10, read-only, each host's own file:

| Host        | user | project/local | gone `projectPath` | kept by today's rule |
| ----------- | ---- | ------------- | ------------------ | -------------------- |
| claude      | 15   | 0             | 0                  | 0                    |
| workstation | 9    | 7             | 7                  | 7                    |
| studio      | 16   | 0             | 0                  | 0                    |

All 7 workstation records name one `projectPath`, the removed worktree
`terraform_ansible-ruff`, with `lastUpdated` 2026-11-09. None of the 7 plugin ids has a user
record on workstation: `context7@claude-plugins-official`, `terraform-skill@antonbabenko`
(1.17.2), `firecrawl@firecrawl` (2.4.0), `ansible-good-practices@claude-ansible-skills` (2.2.2),
`skill-creator@claude-plugins-official`, `frontend-design` (1.1.1), `rust-analyzer-lsp` (1.0.0).
The prune ran on workstation at 2026-11-10T17:12:33Z and kept all 7. Population: the three hosts'
whole files, all records; the claim covers the same population.

Harm: clutter only. No session can start in a directory that does not exist, so no session loads
these records. Each removed worktree whose plugins lack a user install adds records that never
leave.

ADR-0055 decision 2 already notes the CLI cannot reach these records: `claude plugins uninstall
-s project` runs inside the project directory, and the directory is gone.

Prior designs checked: ADR-0055, the 2026-11-04 user-scope spec and the retired 2026-11-06
doctor spec. None rejects a gone-path rule. The 11-06 spec's Ergonomics lens noted that a gone
directory cannot be cleared by any CLI remedy. The 11-07 backlog text rejected the rule only
because it would remove nothing then.

## Design

### 1. Gone-path test

New function `path_gone(record)` in `lib/claude_plugin_prune.py`. It returns `True` only when
all of these hold:

- `record["projectPath"]` is a non-empty `str`;
- `os.path.isabs` is true for it;
- `os.lstat` on it raises `FileNotFoundError`.

Every other case returns `False`: the key missing, empty, not a string or relative; the path
present (a dangling symlink at the path counts as present, since `lstat` succeeds);
`PermissionError`, `NotADirectoryError` or any other `OSError`. Unknown is not gone, so the
record is kept (fail closed).

### 2. Removal rule

`should_remove(record, user_record)` keeps its scope check first: a record whose `scope` is not
`project` or `local` is never removed. Next, a record for which `path_gone` is true is removed,
with or without a user record and whatever its version or timestamps. Otherwise ADR-0055
decision 4 applies unchanged.

### 3. What does not change

- `_prune_records`, the refusal conditions, the backup, the race guard, `--dry-run` and the
  exit codes.
- The stdout line keeps its form, `pruned at <UTC>: removed <n>, kept <m>`; gone-path removals
  count in `removed`. The shell wrapper `_claude_prune_plugin_records` only prints the line, so
  it needs no change.
- No `claude` CLI call is added. The file edit is the only route (ADR-0055 decision 2).

### 4. Accepted risk

A directory that is absent now but comes back later (an unmounted volume, a re-cloned repo)
loses its records. For a plugin with a user record, the next session there re-mints the record
at the user version (ADR-0055 mint rule). For a plugin with no user record, the plugin is no
longer installed for that project, and Claude Code offers the install again at that session.
Measured 2026-11-10: every `projectPath` on the three hosts sits under the account's home
directory (`/home/bruce/...`), none on a removable volume. `installed_plugins.json` is
machine-local and untracked by ai-config (`git ls-files .claude/plugins` is empty), so a path
from another host cannot appear in it.

### 5. Documentation

- ADR-0055 gains an `## Amendments` section with one dated entry stating the gone-path rule and
  the 2026-11-10 workstation measurement.
- The module docstring of `lib/claude_plugin_prune.py` names both removal conditions.
- The `CLAUDE.md` Entry Points bullet that begins "`-t update` updates Claude plugins with
  `-s user`" adds "or whose project directory is gone".
- The backlog row named above is removed from `docs/superpowers/README.md`.

## Testing

`tests/test_claude_plugin_prune.py` (unittest), with `projectPath` values built under a
`tempfile.TemporaryDirectory`:

- `path_gone`: missing key; empty string; non-string (`None`, `5`); relative path; existing
  directory; existing regular file; dangling symlink; absent path; path under a regular file
  (`NotADirectoryError`); `os.lstat` patched to raise `PermissionError`.
- `should_remove`: gone path and no user record gives `True`; gone path with a user record whose
  version differs and whose `lastUpdated` is older gives `True`; gone path with `scope: user`
  gives `False`; present path and no user record gives `False` (today's behaviour).
- `prune` end to end on a fixture file holding one gone-path record without a user record, one
  present-path record without a user record and one user record: the line reads `removed 1,
kept 2`, a backup exists, and the rewritten file holds exactly the two kept records.
- `--dry-run` on the same fixture: the same line and the file byte-identical afterwards.

Verification on workstation after merge: run the prune with `--dry-run` against the live file,
expect `removed 7, kept 9`; then the next `-t update` removes them.

## Requirements

- **R1.** `lib/claude_plugin_prune.py` defines `path_gone(record)`, which returns `True` only when `record.get("projectPath")` is a non-empty `str`, `os.path.isabs` of it is true, and `os.lstat` of it raises `FileNotFoundError`; it returns `False` in every other case, including any other `OSError`.
- **R2.** `should_remove(record, user_record)` returns `False` for a record whose `scope` is neither `project` nor `local`, before any other check.
- **R3.** `should_remove` returns `True` for a `project` or `local` record for which `path_gone` is true, whether `user_record` is `None` or not, and regardless of `version` and `lastUpdated`.
- **R4.** For a record for which `path_gone` is false, `should_remove` returns exactly what it returned before this change.
- **R5.** The prune's stdout line keeps the form `pruned at <UTC>: removed <n>, kept <m>`, and gone-path removals are counted in `<n>`.
- **R6.** `tests/test_claude_plugin_prune.py` covers `path_gone` for: key missing, empty string, `None`, `5`, a relative path, an existing directory, an existing regular file, a dangling symlink, an absent path, a path under a regular file, and `os.lstat` raising `PermissionError`.
- **R7.** `tests/test_claude_plugin_prune.py` covers `should_remove` for: gone path with no user record (`True`); gone path with a user record of a different version and older `lastUpdated` (`True`); gone path with `scope` `user` (`False`); present path with no user record (`False`).
- **R8.** `tests/test_claude_plugin_prune.py` runs `prune` on a fixture with one gone-path record lacking a user record, one present-path record lacking a user record and one user record, and asserts the line ends `removed 1, kept 2`, a backup file exists, and the rewritten `plugins` map holds exactly the two kept records; the same fixture under `dry_run=True` leaves the file byte-identical.
- **R9.** `docs/adr/0055-prune-claude-plugin-project-records.md` has an `## Amendments` section with an entry dated 2026-11-10 stating that a `project` or `local` record whose absolute `projectPath` is absent (`FileNotFoundError` from `os.lstat`) is removed whether or not a user record exists.
- **R10.** The `CLAUDE.md` bullet beginning "`-t update` updates Claude plugins with `-s user`" says the prune also removes records whose project directory is gone.
- **R11.** The backlog row "Claude Code writes a project-scope plugin record per project and worktree, and none is ever removed" is removed from `docs/superpowers/README.md`.
- **V1.** After merge, on workstation, `python3 lib/claude_plugin_prune.py --dry-run --file ~/.claude/plugins/installed_plugins.json --backup-dir ~/.local/share/dotfiles/claude-plugin-backups` prints `removed 7, kept 9`, unless the file changed since 2026-11-10, in which case the counts match a read-only recount.
- **N1.** No change to `lib/workflows.sh`.
- **N2.** No change to the refusal conditions, backup, race guard or exit codes of ADR-0055 decision 3.
- **N3.** No new `claude` CLI invocation.
- **N4.** No record is removed because its path is unreadable, relative, missing or of a non-string type.

## Multi-Lens Review

Reviewed at commit: `7c85d1fa` (Step 7 self-review commit, before Step 8 dispatch)

### Goal-Fit

Finding: The gone-path rule is the first that can empty a plugin's record list, and the spec
does not say what happens to the key. `_prune_records` assigns `new_plugins[plugin_id] =
survivors` unconditionally, so V1 would leave 7 `"<id>": []` keys on workstation. Claude Code
2.1.322 never writes that shape: its uninstall path runs `length===0) delete e.plugins[n]`. Some
readers do not filter on length (the updater iterates `Object.keys(plugins)`; the same-name
collision check `Lt` scans `Object.keys` unfiltered), so an empty key may not be inert. Fix: drop
the key when survivors is empty; R8 must assert the id is absent, since "holds exactly the two
kept records" passes with `[]` present; section 3's "`_prune_records` does not change" is false.
Worth building: one hand edit clears today's 7, but every removed worktree whose plugins lack a
user install recurs. Reads-it test passes (output is the file Claude Code reads). Checked and not
raised: `lstat` fail-closed semantics, remount risk (all paths under `/home/bruce`), doc edits.
No empty-list key exists today in the live files or any backup on `claude` or workstation.
Assumption: a `"plugin@mkt": []` key is harmless to Claude Code. Settle by reading `Lt` and the
updater in the binary, or a scratch-`HOME` probe; deleting the empty key removes the question.
Disposition:

### Ergonomics

Finding: The rule silently changes the meaning of the existing tests. The shared `fixture()` in
`tests/test_claude_plugin_prune.py` (lines 41-55) uses absolute `projectPath` values `/p1`..`/p4`,
none of which exists, so under R1 all are gone: line 338's `removed 2, kept 5` becomes
`removed 4, kept 3`, line 140's kept `/p3` (newer than the user record) is removed, and `c@m`
`/p4` (no user record) is removed; lines 133, 210, 489 and 566 move with it.
`test_odd_shapes_untouched` (`/p`) stays at `removed 1, kept 2` but no longer exercises the old
rule alone. The easy wrong fix is editing the expected counts, which hides an R4 regression. The
spec needs: existing fixture paths become directories that exist, expected counts unchanged.
Verdict balance fine (always-False fails R7 case 1 and R8; always-True fails the present-path
cases). Checked and not raised: wrapper output, dangling-symlink choice, PermissionError,
automount hang (paths under `/home`), V1 arithmetic.
Assumption: a gone `projectPath` is dead for good. Worktrees follow `<repo>-<branch-slug>`, so a
recurring branch name (the next ruff bump) recreates `terraform_ansible-ruff`; a prune in the gap
drops the records of the 7 plugins with no user install, and the operator re-accepts install
prompts there. The main terraform_ansible checkout holds none of these records, and 3 of the 7
are `false` in its tracked settings, suggesting an explicit per-worktree install rather than an
automatic mint. Settle by the workstation reflog for repeated `ruff` worktrees and the
2026-11-09 session transcript for an install call.
Disposition:

### Risk

Finding: No load-bearing risk. The newly admitted delete removes only `installed_plugins.json`
records whose `projectPath` is absent; it touches no cache or data directory (the only data dir
among the 7 on workstation, `plugins/data/context7-claude-plugins-official`, is empty). No
realistic false-gone input: `docker inspect` on `claude` and workstation shows no container
bind-mounting `~/.claude`. One smaller new failure point the spec does not name: the empty
`"<id>": []` key (same as Goal-Fit). Claude Code's writer deletes an emptied key; sampled readers
guard with `?.length`, but the schema was not found, and a non-empty constraint would make the
file unreadable ("installed_plugins.json could not be read"), losing every plugin. Fix: drop the
empty key. Checked and not raised: verdict balance, PermissionError and macOS TCC EPERM kept,
dangling symlink present, re-created-worktree loss (re-prompts from tracked settings; accepted).
Assumption: Claude Code tolerates `plugins["<id>"] == []`. Settle by finding the plugins-file
schema in the bundle, or a throwaway `CLAUDE_CONFIG_DIR` probe with `claude plugins list`.
Dropping empty keys removes the dependency.
Disposition:

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.
