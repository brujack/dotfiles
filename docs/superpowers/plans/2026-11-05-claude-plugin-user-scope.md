# Claude Plugins at User Scope Implementation Plan

> **Status: DONE** (dotfiles#427, merged 2026-11-05)

spec: docs/superpowers/specs/2026-11-04-claude-plugin-user-scope-design.md
scope: PR1

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `-t update` updates Claude plugins at user scope and then prunes project/local install records that the user record is at least as new as, so sessions re-mint them at the fresh user version.

**Architecture:** A standalone Python 3.9 program, `lib/claude_plugin_prune.py`, owns all JSON work and prints one summary line. `run_update`'s claude section (`lib/workflows.sh`) passes `-s user` to `claude plugins update`, then calls `_claude_prune_plugin_records`, a thin bash wrapper that runs the program and turns its exit code into a section message.

**Tech Stack:** bash, bats (`tests/setup_env/`), Python 3.9 stdlib `unittest` (`make test-python`).

## Global Constraints

- The prune runs on Python 3.9 (the Studio's `/usr/bin/python3` is 3.9.6): no `datetime.fromisoformat` on `...Z`, no `match`, no 3.10+ syntax.
- Timestamps are parsed with `%Y-%m-%dT%H:%M:%S.%fZ`.
- Version equality is decided before any timestamp is read.
- The prune never modifies `user` or `managed` records or any top-level key other than `plugins`, never removes a plugin's only install record, and reads no project's settings file (N2, N4).
- No repo's `.claude/settings.json` or `.claude/settings.local.json` is edited (N1); no `claude plugin uninstall`, `disable` or `enable` call is added (N3).
- No test reads or writes the real `~/.claude`: every path goes through a seam set at `setup()`/`load_mocks` scope.

## Verification

- `make test` exits 0 (suite ~104 s under `bats --jobs 24` on `claude`, below the 600 s Bash cap).
- After merge, V1-V3 from the spec on `claude`: one `-t update`, then the summary line's prune time, record counts against the newest backup, a `claude -p --output-format stream-json --verbose` session in etch-config reporting `superpowers` at the user version, and the `installedAt` check repeated an hour later.

### Task 1: Prune program and its unit tests

```yaml-task
id: 1
description: lib/claude_plugin_prune.py prunes project/local records the user record is at least as new as, with refusal, race guard, backup and dry-run
role: executor
model: sonnet
tdd: required
requirements: [R2, R3, R4, R5, R8, R9]
acceptance:
  - cmd: python3 -m unittest tests.test_claude_plugin_prune -v
    exit_code: 0
  - cmd: make test-python
    exit_code: 0
max_retries: 3
files_touched:
  - lib/claude_plugin_prune.py
  - tests/test_claude_plugin_prune.py
depends_on: []
```

**Interfaces:**

- Produces: `python3 lib/claude_plugin_prune.py --file <installed_plugins.json> --backup-dir <dir> [--keep 5] [--dry-run]`. Prints exactly one stdout line. Exit codes:
  - `0`: done or nothing to do. The line is `pruned at <UTC %Y-%m-%dT%H:%M:%SZ>: removed N, kept M`, or `no plugins file` when `--file` is absent.
  - `3`: refused. The line is `refused: <reason>`.
  - `4`: skipped because the file changed. The line is `skipped: plugins file changed during prune`.
- Importable functions: `should_remove(record, user_record) -> bool`, `parse_ts(s) -> datetime | None`, `prune(path, backup_dir, keep, dry_run, before_restat=None) -> tuple[int, str]`. `before_restat` is a test hook called just before the re-stat.

- [ ] Write failing tests in `tests/test_claude_plugin_prune.py` (unittest, fixtures written to `tempfile.mkdtemp()`, the module imported from `lib/` with `importlib.util.spec_from_file_location`):
  - **4-record fixture:** two user records with `lastUpdated` `2026-10-01T00:00:00.000Z`, one managed record, and four project records:
    - one at the user version, removed;
    - one at another version with `lastUpdated` `2026-09-01T00:00:00.000Z`, removed;
    - one at another version with `lastUpdated` `2026-10-15T00:00:00.000Z`, kept;
    - one whose plugin has no user record, kept.
      Assert exactly 2 removed, 2 kept, and the user records, the managed record and `version` equal after parsing.
  - At the user version with an unparsable `lastUpdated`: removed. At another version with a missing or unparsable timestamp: kept.
  - `parse_ts("2026-11-05T02:57:23.774Z")` returns a datetime; `parse_ts("x")` returns `None`.
  - Refusals, each with exit 3, the file unchanged and no backup: malformed JSON, no `plugins`, `version` 3.
  - `before_restat` touching the mtime with the size unchanged gives exit 4, file unchanged. `before_restat` replacing the file with a same-content copy (new inode) gives exit 4.
  - `dry_run=True` on the 4-record fixture gives "removed 2", file and backup dir unchanged.
  - A fixture with no project records gives "removed 0", no write, no backup.
  - With six earlier backups present, one run leaves exactly 5 backups, the newest being this run's.
  - The summary line matches `^pruned at \d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ: removed \d+, kept \d+$`.
  - Missing `--file` gives exit 0 and `no plugins file`.
- [ ] Run `python3 -m unittest tests.test_claude_plugin_prune -v`. It must fail on the missing module.
- [ ] Implement:
  - Read `os.stat` (`st_mtime_ns`, `st_ino`) before loading. Validate the shape.
  - Build the new `plugins` map. Write the backup as `<backup-dir>/installed_plugins-<UTC %Y%m%dT%H%M%S%fZ>.json`, then prune old backups down to `--keep`.
  - Write a temp file in the same directory, call `before_restat`, re-stat and compare, then `os.replace`.
  - The no-change and dry-run paths do not write.
- [ ] Run the gates. Commit (`caveman:caveman-commit`).

### Task 2: Wire user-scope update and prune into run_update

```yaml-task
id: 2
description: run_update claude section passes -s user to plugins update and runs _claude_prune_plugin_records after the loop
role: executor
model: sonnet
tdd: required
requirements: [R1, R2, R8]
acceptance:
  - cmd: bats tests/setup_env/update_claude.bats
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - lib/workflows.sh
  - tests/setup_env/update_claude.bats
  - tests/helpers/common.bash
depends_on: [1]
```

**Interfaces:**

- Consumes: Task 1's CLI and exit codes.
- Produces: `_claude_prune_plugin_records` in `lib/workflows.sh`. It prints the program's line, returns 0 for exit 0, and returns 2 (caller WARNs) for 3, 4, or any other non-zero exit (a missing `python3` included). Seams:
  - `_OVERRIDE_CLAUDE_PLUGINS_FILE`, default `${HOME}/.claude/plugins/installed_plugins.json`;
  - `_OVERRIDE_CLAUDE_PLUGIN_BACKUP_DIR`, default `${HOME}/.local/share/dotfiles/claude-plugin-backups`.

- [ ] In `tests/helpers/common.bash` `load_mocks`, export `_OVERRIDE_CLAUDE_PLUGINS_FILE="${BATS_TEST_TMPDIR}/no-such-installed_plugins.json"` and `_OVERRIDE_CLAUDE_PLUGIN_BACKUP_DIR="${BATS_TEST_TMPDIR}/plugin-backups"`. This keeps every existing `run_update` test away from the real file.
- [ ] Write failing bats tests in `tests/setup_env/update_claude.bats`:
  - The recorded update call is `claude plugins update -s user <id>` (from `MOCK_CALLS_FILE`).
  - The prune line appears after the update calls in the section output.
  - With a fixture plugins file holding one project record at the user version: the section output contains `removed 1`, and the fixture afterwards has no project record.
  - With `MOCK_CLAUDE_FAIL_ARGS="plugins update"` and a fixture whose project record is newer-dated at another version: that record survives.
  - With the mock exiting 0 and printing `already at the latest version` and a newer-dated project record: the record survives.
  - With a fixture whose `version` is 3: the section records a WARN containing `refused`, and the file is unchanged.
  - Under `--dry-run`: the fixture is unchanged.
- [ ] Implement:
  - Add `-s user` to the update call.
  - Add `_claude_prune_plugin_records` near the claude helpers. It runs `python3 "${DOTFILES_REPO_ROOT}/lib/claude_plugin_prune.py"` with `--dry-run` when `_dry_run_active`.
  - Call it after the update loop's `fi`, before the settings guard. On return 2, append its line to `_messages` as a WARN.
- [ ] Run the gates. Commit.

### Task 3: ADR, CLAUDE.md lines, backlog row

```yaml-task
id: 3
description: ADR-0055 for the prune, CLAUDE.md seam and update lines, backlog row for the optional settings strip (docs-only, no behavior change)
role: executor
model: sonnet
tdd: not-applicable
requirements: [R6, R7]
acceptance:
  - cmd: make lint
    exit_code: 0
  - cmd: make check-claude-md-budget
    exit_code: 0
  - cmd: grep -q '0055' docs/adr/README.md
    exit_code: 0
  - cmd: grep -q '_OVERRIDE_CLAUDE_PLUGINS_FILE' CLAUDE.md
    exit_code: 0
max_retries: 2
files_touched:
  - docs/adr/0055-prune-claude-plugin-project-records.md
  - docs/adr/README.md
  - CLAUDE.md
  - docs/superpowers/README.md
depends_on: [2]
```

- [ ] Write `docs/adr/0055-prune-claude-plugin-project-records.md`. Follow the Context / Decision / Consequences / Related shape of `docs/adr/0054-*.md`. It must cover:
  - why the prune edits a Claude-owned file;
  - the refusal conditions (shape, `version` 2, mtime and inode);
  - the freshness condition, the downgrade it prevents, and why exit codes cannot decide it;
  - the measured mint rule (probes A-F) and load rule (dotfiles session loaded `context-mode` 2.1.0);
  - the no-op `lastUpdated` measurement, and the command-source exception;
  - that live checkouts move to the user version;
  - its reliance on `.in_use` protection;
  - that skew between updates is bounded by update cadence.
    Copy the figures from the spec; do not re-derive them.
- [ ] Add the ADR row to `docs/adr/README.md`.
- [ ] Add a one-line test-seam rule to `CLAUDE.md`'s Test Seams list: set `_OVERRIDE_CLAUDE_PLUGINS_FILE` and `_OVERRIDE_CLAUDE_PLUGIN_BACKUP_DIR` to fixtures; `load_mocks` points the file at a missing path. Also add one Entry Points bullet: `-t update` updates plugins at user scope, then prunes project/local records (ADR-0055).
- [ ] Add a `docs/superpowers/README.md` P3 features Backlog row: strip redundant `true` entries from repo `enabledPlugins`, only if the prune is removed (spec link).
- [ ] Run the gates. Commit.

## Orchestrator steps

- After Task 3: `make test` once on the worktree, then Phase 3 (`finishing-a-development-branch`).
- Post-merge: run V1-V3. Ask the ai-config session to add the seam description to `docs/knowledge/dotfiles-test-seams.md` (CLAUDE.md Test Seams rule).

## Non-goal check

Fresh reviewer, `~/.claude/skills/writing-plans/nongoal-check.md`, 2026-11-05: 4 CLEAR, 0 CONFLICT, 0 UNCLEAR.

- N1 CLEAR: no `.claude/settings*.json` is edited; the Task 3 backlog row records the strip as possible future work only.
- N2 CLEAR: a project record is removed only when its plugin has a user record; the fixture keeps the record whose plugin has none.
- N3 CLEAR: the only new CLI call is `claude plugins update -s user`.
- N4 CLEAR: the prune reads only `installed_plugins.json` via `--file`.
