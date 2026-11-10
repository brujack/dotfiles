# Plugin prune gone-path rule Implementation Plan

> **Status: DONE** (#459, merged 2026-11-10)

spec: docs/superpowers/specs/2026-11-10-plugin-prune-gone-path-design.md

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `lib/claude_plugin_prune.py` also removes a project or local record whose absolute
`projectPath` is absent, and drops a plugin key whose record list it empties.

**Architecture:** One new pure function `path_gone(record)` and one extra branch in
`should_remove`; `_prune_records` omits an id whose non-empty list ends empty. The shell wrapper
in `lib/workflows.sh` is untouched. Existing test fixtures whose `projectPath` values do not exist
are moved onto real temp directories first, so their expected values never change.

**Tech Stack:** Python 3.9+ stdlib (`unittest`), bats.

## Global Constraints

- No change to `lib/workflows.sh` (N1).
- No change to the refusal conditions, backup, race guard or exit codes of ADR-0055 decision 3 (N2).
- No new `claude` CLI invocation (N3).
- No record is removed because its `projectPath` is unreadable (any `OSError` other than `FileNotFoundError`), relative, empty, of a non-string type, or because the key is absent (N4).
- Never change an existing test's expected value to make it pass; if one moves, stop and report (R13, R14).
- Python must run on 3.9 (the Studio's `/usr/bin/python3`): no `match`, no `X | Y` type syntax at runtime.

## Verification

- Session gate: `make test` exits 0 in the worktree after Task 2, and again after Task 3.
- Behaviour: Task 2's end-to-end test proves `removed 1, kept 2` and the absent key on a fixture.
- Live check (V1, after merge, read-only): on workstation,
  `python3 lib/claude_plugin_prune.py --dry-run --file ~/.claude/plugins/installed_plugins.json --backup-dir ~/.local/share/dotfiles/claude-plugin-backups`
  prints `removed 7, kept 9` (or counts matching a read-only recount if the file changed).
- Edge cases: dangling symlink kept; `PermissionError` kept; an input id already `[]` kept as `[]`.

---

### Task 1: Bats prune fixture uses a real project directory

```yaml-task
id: 1
description: Move _write_plugins_fixture's projectPath onto a directory under BATS_TEST_TMPDIR, every assertion unchanged (test-only precondition for Task 2; fixture change, no production behaviour)
role: executor
model: haiku
tdd: not-applicable
requirements: [R14]
acceptance:
  - cmd: '! grep -q "\"projectPath\":\"/x\"" tests/setup_env/update_claude.bats'
    exit_code: 0
  - cmd: 'grep -q "mkdir -p" tests/setup_env/update_claude.bats'
    exit_code: 0
  - cmd: 'bats tests/setup_env/update_claude.bats'
    exit_code: 0
max_retries: 3
files_touched: [tests/setup_env/update_claude.bats]
depends_on: []
```

**Files:** `tests/setup_env/update_claude.bats` — function `_write_plugins_fixture` only.

- [ ] In `_write_plugins_fixture`, before the `printf`, add
      `mkdir -p "${BATS_TEST_TMPDIR}/project" || return 1`, and replace the literal
      `"projectPath":"/x"` with `"projectPath":"%s"`, passing `"${BATS_TEST_TMPDIR}/project"` as the
      matching `printf` argument (it sits between the user `lastUpdated` and the project version, so the
      argument order becomes `"$1" "$2" "${BATS_TEST_TMPDIR}/project" "$3" "$4"`).
- [ ] Update the comment above the function: the project record's `projectPath` is a directory that
      exists, so the gone-path prune rule does not apply to these tests.
- [ ] Change nothing else: no `@test` body, no assertion, no `run` line. The reviewer checks that
      `git diff origin/master -- tests/setup_env/update_claude.bats` touches only `_write_plugins_fixture`.
- [ ] `bats tests/setup_env/update_claude.bats` passes. Commit (`caveman:caveman-commit`).

**Interfaces:** Produces: `_write_plugins_fixture <user ver> <user ts> <proj ver> <proj ts>`, same
signature, project record now at an existing path.

### Task 2: path_gone, removal rule and empty-key drop, with tests

```yaml-task
id: 2
description: Add path_gone and the gone-path branch of should_remove, drop emptied plugin keys in _prune_records, and move the Python fixture onto real directories, TDD
role: executor
model: sonnet
tdd: required
requirements: [R1, R2, R3, R4, R5, R6, R7, R8, R12, R13]
acceptance:
  - cmd: 'python3 -m unittest discover -s tests -p test_claude_plugin_prune.py'
    exit_code: 0
  - cmd: 'python3 -c "import runpy,sys; sys.exit(0 if callable(runpy.run_path(\"lib/claude_plugin_prune.py\").get(\"path_gone\")) else 1)"'
    exit_code: 0
  - cmd: 'bats tests/setup_env/update_claude.bats'
    exit_code: 0
  - cmd: 'make lint'
    exit_code: 0
  - cmd: 'git diff --exit-code origin/master -- lib/workflows.sh'
    exit_code: 0
max_retries: 3
files_touched: [lib/claude_plugin_prune.py, tests/test_claude_plugin_prune.py]
depends_on: [1]
```

**Files:** `lib/claude_plugin_prune.py`, `tests/test_claude_plugin_prune.py`.

Step 0, fixture first (R13), before any production change:

- [ ] Add `setUpModule()` creating `_LIVE_ROOT = tempfile.mkdtemp()` with subdirectories `p1`,
      `p2`, `p3`, `p4`, `p`, and `tearDownModule()` removing it (`shutil.rmtree`). Add
      `def live(name): return os.path.join(_LIVE_ROOT, name)`.
- [ ] In `fixture()` replace `"/p1"`..`"/p4"` with `live("p1")`..`live("p4")`; in
      `test_odd_shapes_untouched` replace `"/p"` with `live("p")`; at the line asserting
      `["/p3"]` (currently line 140) assert `[live("p3")]`. No other expected value changes.
- [ ] Run the module: all 46 existing tests still pass. Commit.

Then RED/GREEN, one behaviour at a time, committing after each GREEN:

1. `path_gone(record)` (R1, R6): `True` only when `record.get("projectPath")` is a non-empty
   `str`, `os.path.isabs(p)`, and `os.lstat(p)` raises `FileNotFoundError`; catch
   `FileNotFoundError` → `True`; any other `OSError` → `False`; success → `False`. Tests, each its
   own method: key missing, `""`, `None`, `5`, `"rel/path"`, existing directory, existing file,
   dangling symlink (`os.symlink` to an absent target), absent absolute path, path under a regular
   file (`<file>/x`, `NotADirectoryError`, expect `False`), and `mock.patch.object(P.os, "lstat",
side_effect=PermissionError(errno.EACCES, "denied"))` → `False`.
2. `should_remove` (R2, R3, R4, R7): keep the scope check first; then
   `if path_gone(record): return True`; then the existing body unchanged (`user_record is None` →
   `False`, and so on). Tests: gone path, `user_record=None` → `True`; gone path, user record
   version differs and user `lastUpdated` older → `True`; gone path with `scope` `user` → `False`;
   existing path, no user record → `False`.
3. `_prune_records` (R12): after building `survivors`, if `records` was non-empty and `survivors`
   is empty, do not add the id to `new_plugins`; an input `[]` or non-list value is copied through
   as today. Tests: one id whose only record is gone-path → id absent and counted in removed;
   input `"z@m": []` → present as `[]`.
4. End to end (R5, R8): fixture file with `"g@m": [gone project record]`,
   `"h@m": [project record at live("p1"), no user record]`, `"u@m": [user record]`. `prune(...)`
   returns code 0 and a line ending `removed 1, kept 2`; a backup file exists in the backup dir;
   the rewritten `plugins` has exactly keys `h@m` and `u@m` with their records; `g@m` not in it.
   Same fixture with `dry_run=True`: same line, file bytes unchanged.
5. Module docstring names both removal conditions (user record at least as new; project directory
   gone) and the empty-key drop.

**Mutants to confirm** (report each fails the suite, then revert): `path_gone` always `False`;
`path_gone` always `True`; `_prune_records` without the empty-key drop.

**Interfaces:** Produces `path_gone(record) -> bool` (public name, no underscore).

### Task 3: ADR amendment, CLAUDE.md bullet, backlog row

```yaml-task
id: 3
description: Amend ADR-0055, extend the CLAUDE.md -t update bullet, remove the backlog row (docs-only, no behaviour change)
role: executor
model: sonnet
tdd: not-applicable
requirements: [R9, R10, R11]
acceptance:
  - cmd: 'grep -q "^## Amendments" docs/adr/0055-prune-claude-plugin-project-records.md'
    exit_code: 0
  - cmd: 'grep -qE "2026-11-10.*FileNotFoundError|FileNotFoundError.*2026-11-10" docs/adr/0055-prune-claude-plugin-project-records.md'
    exit_code: 0
  - cmd: 'grep -E "^- .-t update. updates Claude plugins with .-s user." CLAUDE.md | grep -q "directory is gone"'
    exit_code: 0
  - cmd: '! grep -q "Claude Code writes a project-scope plugin record per project and worktree, and none is ever removed" docs/superpowers/README.md'
    exit_code: 0
  - cmd: 'make check-claude-md-budget'
    exit_code: 0
max_retries: 3
files_touched: [docs/adr/0055-prune-claude-plugin-project-records.md, CLAUDE.md, docs/superpowers/README.md, lib/workflows.sh]
depends_on: [2]
```

- [ ] ADR-0055: append `## Amendments` before `## Related`, entry
      `- 2026-11-10: a project or local record whose absolute projectPath is absent (os.lstat raises
FileNotFoundError) is removed whether or not a user record exists, and a plugin key whose list
the prune empties is dropped, as Claude Code's own uninstall does. Measured 2026-11-10: 7 such
records on workstation, all for the removed terraform_ansible-ruff worktree, none with a user
record. Spec: docs/superpowers/specs/2026-11-10-plugin-prune-gone-path-design.md.` (wrap prose at
      100 columns).
- [ ] `CLAUDE.md` Entry Points bullet beginning "`-t update` updates Claude plugins with
      `-s user`": after "the user record is at least as new as" insert " or whose project directory is
      gone". No other `CLAUDE.md` change.
- [ ] `docs/superpowers/README.md`: delete the P2 backlog row beginning "| Claude Code writes a
      project-scope plugin record per project and worktree, and none is ever removed |". Leave the
      plan index rows alone (the orchestrator updates them).
- [ ] `lib/workflows.sh`: comment only, above `_claude_prune_plugin_records`. Replace "that a
  user-scope record already covers" with wording naming both rules: records a user-scope record
  already covers, and records whose project directory is gone (N1 as amended). No code line changes;
  `git diff origin/master -- lib/workflows.sh` must show only `#` lines.
- [ ] Gates are scoped: none of these files is read by the suite. The orchestrator runs `make test`
      once after this task. Commit.

## Non-goal check

Reviewer verdicts (2026-11-10, against N1-N4 of the spec):

- N1 CLEAR — "no task touches `lib/workflows.sh`. Task 2's acceptance checks this with `git diff --exit-code`."
- N2 CLEAR — "Neither is a refusal condition, the backup, the race guard or an exit code."
- N3 CLEAR — "no plan step calls the `claude` CLI."
- N4 CLEAR — "Any other `OSError` returns False, and the plan tests the missing, empty, `None`, int, relative and `PermissionError` cases."

Resolution: none needed. Side note acted on: Task 2's `NotADirectoryError` case now states its
expected value. Before: "path under a regular file (`<file>/x`, `NotADirectoryError`)". After:
"path under a regular file (`<file>/x`, `NotADirectoryError`, expect `False`)".
