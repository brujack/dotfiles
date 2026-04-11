# Update Summary Design

## Goal

Add a structured end-of-run summary to `./setup_env.sh -t update` that shows which sections ran, their pass/fail status, and exactly what changed (packages upgraded, commits pulled, files updated). Append each summary to `~/.dotfiles-update.log` with a timestamp so past runs are reviewable.

## Architecture

A new file `lib/update_summary.sh` holds all summary infrastructure. `run_update()` in `lib/workflows.sh` remains responsible for what to run; the new lib is responsible for tracking and reporting results. `setup_env.sh` sources `lib/update_summary.sh` alongside the existing lib files.

`run_update()` wraps each section with three calls:

```bash
_update_record_start "section"
# ... existing section body unchanged ...
_update_record_end "section" $?
```

Sections that don't run (flag not set, tool not installed) call:

```bash
_update_skip "section" "reason"
```

At the end of `run_update()`, a single call to `_update_summary` prints the table to the terminal and appends it to `~/.dotfiles-update.log`.

A temp directory created at the start of `run_update()` holds all snapshot files. It is removed at the end of `run_update()` whether or not the update succeeded.

## File Structure

| File | Change |
|---|---|
| `lib/update_summary.sh` | New — all summary infrastructure |
| `lib/workflows.sh` | Modified — `run_update()` calls summary functions |
| `setup_env.sh` | Modified — source `lib/update_summary.sh` |
| `tests/setup_env/update_summary.bats` | New — unit tests for summary infrastructure |
| `tests/setup_env/workflows.bats` | Modified — tests that `run_update()` calls summary functions |

## Snapshot Strategy

Each section captures state before it runs; after it completes the diff determines what changed.

| Section | Pre-snapshot | Diff method |
|---|---|---|
| brew formulae | `brew list --formula --versions` | line diff: changed lines = upgrades |
| brew casks | `brew list --cask --versions` | line diff |
| softwareupdate | none | parse "Installing X" from section stdout |
| mas | `mas list` | line diff |
| pip | outdated package list already built before upgrade in Python block | use directly |
| gems | `gem list` | line diff |
| claude plugins | none | pass/fail only |
| oh-my-zsh, p10k, tpm, tfenv | `git -C DIR rev-parse HEAD` | after pull: `git -C DIR log OLD_SHA..HEAD --oneline` |
| cheat.sh | none | pass/fail only |

Snapshots are written to a temp directory (`_UPDATE_TMPDIR`) created at the start of `run_update()`:

```bash
_UPDATE_TMPDIR=$(mktemp -d)
```

Cleaned up in all exit paths at the end of `run_update()`:

```bash
rm -rf "${_UPDATE_TMPDIR}"
```

## Functions in `lib/update_summary.sh`

**`_update_snapshot SECTION COMMAND...`**
Runs COMMAND and writes stdout to `${_UPDATE_TMPDIR}/pre_SECTION`. Called by `_update_record_start`.

**`_update_record_start SECTION`**
Takes the pre-snapshot appropriate for the section (calls the correct snapshot command based on section name). Records start time in `${_UPDATE_TMPDIR}/start_SECTION`.

**`_update_record_end SECTION EXIT_CODE`**
Takes the post-snapshot, diffs against pre-snapshot, stores the result string and exit code in `${_UPDATE_TMPDIR}/result_SECTION` and `${_UPDATE_TMPDIR}/status_SECTION`.

**`_update_skip SECTION REASON`**
Writes `SKIP` and REASON to `${_UPDATE_TMPDIR}/status_SECTION` and `${_UPDATE_TMPDIR}/result_SECTION`. No snapshots taken.

**`_update_diff_lines PRE_FILE POST_FILE`**
Outputs lines present in POST_FILE but not in PRE_FILE (new or changed). Used by `_update_record_end` for brew, gems, mas.

**`_update_git_diff DIR OLD_SHA`**
Outputs `git -C DIR log OLD_SHA..HEAD --oneline`. Used by `_update_record_end` for git-based sections.

**`_update_summary`**
Reads all `${_UPDATE_TMPDIR}/status_*` and `${_UPDATE_TMPDIR}/result_*` files in section order. Prints the formatted table to stdout. Appends separator + table to `${UPDATE_LOG_PATH:-${HOME}/.dotfiles-update.log}`.

## Section Order

Sections are recorded in this fixed order regardless of which flags are set:

1. `brew` (formulae + casks combined)
2. `softwareupdate`
3. `mas`
4. `claude`
5. `pip`
6. `gems`
7. `oh-my-zsh`
8. `p10k`
9. `tpm`
10. `tfenv`
11. `cheat.sh`

## Output Format

Terminal and log output:

```
=== Update Summary — 2026-04-11 18:45:02 ===

[OK]   brew          4 formulae (git 2.44.0→2.45.0, node 20.11.0→20.12.0, wget 1.21.3→1.21.4, curl 8.6.0→8.7.1)
                     1 cask (docker 4.28.0→4.29.0)
[OK]   softwareupdate  2 updates installed
[SKIP] mas            --brew-only flag set
[OK]   pip           3 packages (pip 23.3→24.0, setuptools 68.0→69.1, wheel 0.41→0.43)
[OK]   gems          no changes
[FAIL] claude         exit 1 — see output above
[OK]   oh-my-zsh    3 commits
[OK]   p10k          no changes
[OK]   tpm           1 commit
[SKIP] tfenv          not installed
[OK]   cheat.sh      updated

9 sections: 7 OK, 1 failed, 2 skipped
Log appended: ~/.dotfiles-update.log
```

Log file entries are separated by a rule:

```
────────────────────────────────────────────────────────
=== Update Summary — 2026-04-11 18:45:02 ===
...
```

`[OK]` with no changes prints "no changes". `[FAIL]` always prints the exit code. `[SKIP]` always prints the reason.

## Log File

Path: `${UPDATE_LOG_PATH:-${HOME}/.dotfiles-update.log}`

- Created if missing
- Appended (never overwritten) on each run
- Each entry preceded by a separator line and timestamp header

`UPDATE_LOG_PATH` is an override env var for tests (same pattern as `_OVERRIDE_CONSTANTS_PATH`).

## Error Handling

- If a pre-snapshot command fails (e.g., `brew` not installed), the section proceeds without a snapshot and reports pass/fail only with a note.
- If `_update_summary` cannot write to the log file, it prints a warning but does not fail the update run.
- `run_update()` exit code is unchanged — it reflects overall update success, not summary success.

## Testing

**`tests/setup_env/update_summary.bats`** — new file:

- `_update_diff_lines` returns correct new/changed lines given known before/after
- `_update_diff_lines` returns empty when no changes
- `_update_snapshot` writes tool output to correct temp file
- `_update_record_start` creates pre-snapshot file for brew section
- `_update_record_end` with exit 0 writes OK status and diff result
- `_update_record_end` with exit 1 writes FAIL status and exit code
- `_update_skip` writes SKIP status and reason
- `_update_git_diff` returns correct commit lines from mock git log
- `_update_summary` output contains all section names
- `_update_summary` output shows correct status labels ([OK], [FAIL], [SKIP])
- `_update_summary` creates log file when missing
- `_update_summary` appends (not overwrites) existing log file
- `_update_summary` writes separator before each entry
- pip section uses pre-built outdated list directly

**`tests/setup_env/workflows.bats`** — additions:

- `run_update()` calls `_update_record_start` for brew section
- `run_update()` calls `_update_record_end` for brew section
- `run_update()` calls `_update_summary` at end
- `run_update()` calls `_update_skip` for a section when its flag is not set

## Test Seams

| Seam | Used by | Effect |
|---|---|---|
| `UPDATE_LOG_PATH` | `_update_summary` | Redirects log writes to a temp file in tests; defaults to `~/.dotfiles-update.log` |
| `_UPDATE_TMPDIR` | all summary functions | Set to `${BATS_TEST_TMPDIR}` in tests to isolate snapshot files |
