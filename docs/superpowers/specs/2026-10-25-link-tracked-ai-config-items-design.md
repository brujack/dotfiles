# Link only tracked ai-config items into ~/.claude and ~/.cursor

- **Date:** 2026-10-25
- **Backlog row:** "`setup_dotfile_symlinks` links whatever runtime state the ai-config checkout happens to hold" (P2 — bugs and security)

## Problem

`setup_dotfile_symlinks` (`lib/helpers.sh`) links every top-level entry of
`${AI_CONFIG_DIR}/.claude/` into `~/.claude/` (skipping `projects`, linked explicitly, and
`rules`), and every top-level entry of `${AI_CONFIG_DIR}/.cursor/` into `~/.cursor/`
(skipping `User`). Both loops are a shell glob over the checkout's contents, so gitignored
runtime state is linked exactly like tracked configuration. Machines then diverge by what
each checkout happens to hold, and `safe_link` moves a real `~/.claude/<name>` to
`<name>.bak` whenever the checkout grows a same-named runtime directory.

Measured on `workstation`, 2026-09-11 (the backlog row): `ai-config/.claude/dod-log/` existed
with 11 entries, so `safe_link` moved the real `~/.claude/dod-log` (21 entries) to
`~/.claude/dod-log.bak` and linked the ai-config copy. `dod_log.py` writes `~/.claude/dod-log`,
so the 21 older entries became invisible to its pre-push check on that machine.

Measured on `claude`, 2026-10-25 (one machine; the population of the claim is every machine
running `setup_user`):

- On disk in `ai-config/.claude/` but not tracked (`git ls-files .claude`): `aggregator-log`,
  `consolidation-log`, `health`, `settings.local.json`, `worktrees`. All five are linked from
  `~/.claude/`. All five are gitignored in ai-config (`.gitignore` lines 18, 44, 77, 106, 109).
- `~/.claude/dod-log` is a real directory here only because this ai-config checkout has no
  `dod-log`; the next `dod-log` created inside the checkout is linked over it on the next
  `setup_user`.
- On disk in `ai-config/.cursor/` but not tracked: `plugins`, linked from `~/.cursor/`.
- No live writer depends on the five `.claude` links: `learnings_aggregator.py`,
  `memory-consolidation` and `health.py` write `.claude/<dir>` relative to their working
  directory, not through `~/.claude`. The exception is `~/.claude/settings.local.json`, which
  is the project-local settings file for any Claude Code session started in `$HOME`; such
  sessions currently read ai-config's 40 KB project-local permission set.

## Design

The fix replaces the default-allow glob with an allowlist derived from git: an ai-config
`.claude` or `.cursor` item is linked only if git tracks at least one file at or under it.

### Tracked-item helper

`_ai_config_tracked_items <repo_dir> <subdir>` prints, one per line, the distinct first path
component below `<subdir>/` of every file
`env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE git -C <repo_dir> ls-files -z -- <subdir>`
reports (NUL-delimited read, so names with spaces or newlines survive). A directory tracked
only through `.gitkeep` (`cost-log`, `docs-audit`) counts as tracked. Names starting with `.`
are dropped, matching the current glob, which never matched dot entries; this change must not
widen what is linked.

Return codes: 0 with a non-empty list on success; 1 when `git` fails (not a checkout, git
missing) or when the list is empty. Empty is a failure because a healthy ai-config always
tracks `.claude/settings.json` and `.cursor/rules`; an empty answer means the instrument is
broken, not that there is nothing to link.

### The two loops

Each loop iterates the helper's output instead of the glob, keeps its existing skips
(`projects` and `rules` for `.claude`, `User` for `.cursor`) and the explicit
`projects`/`rules` links after it, and still calls `safe_link` per item. An item the helper
names but that is absent on disk (tracked, deleted in the working tree) is skipped, as the
glob's `[[ -e ]]` check does today.

If the helper fails for a subdir, that subdir's loop links nothing, `log_error` names the
directory and the failed command, the rest of the function runs, and the function returns 1
at its end. It never falls back to the glob. `run_setup_user` already treats 1 as a failure
(`lib/workflows.sh:402`).

### Stale-link warning

After each loop, scan `~/.claude/*` (or `~/.cursor/*`). For each entry that is a symlink whose
`readlink` text is exactly `<ai_config_dir>/.claude/<name>` (or `.cursor/<name>`), where
`<name>` is not in the tracked list and is not one of the explicitly-linked names, emit one
`log_warn` naming the link, its target, and the remedy `rm <link>`. The link is never
removed: on `workstation` the stale `dod-log` link holds the live DoD entries, and removing it
mid-session would hide them from the pre-push gate — the same harm this change exists to stop.
Matching on the literal `readlink` text is deliberate: `safe_link` writes that exact string, so
a link the operator pointed elsewhere by hand is never reported.

The warning runs only when the helper succeeded for that subdir; with no tracked list there
is nothing to compare against.

## Testing

All cases in `tests/setup_env/install_guards.bats`, against a fixture ai-config built as a real
git repo under `BATS_TEST_TMPDIR` (with `unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR
GIT_INDEX_FILE` in `setup()`), `HOME` redirected to a fixture at `setup()` scope, and
`_OVERRIDE_AI_CONFIG_DIR` pointing at the fixture.

1. A tracked file and a tracked directory under `.claude` are linked.
2. An untracked directory and an untracked file under `.claude` are not linked.
3. A directory tracked only through `.gitkeep` is linked.
4. `rules` is not linked; `projects` is linked exactly once; `.cursor/User` is not linked
   and `.cursor/rules` is.
5. An untracked `.cursor` directory is not linked.
6. A pre-existing `~/.claude/<untracked>` symlink to the fixture produces exactly one warning
   naming it, and still exists afterwards; a pre-existing symlink to a path outside the
   fixture produces none.
7. A fixture that is not a git repo: return 1, an error naming the directory, and no
   `~/.claude` or `~/.cursor` links into the fixture; links outside ai-config (e.g.
   `~/.vimrc`) are still made.
8. An exported decoy `GIT_DIR` pointing at a different repo does not change which items are
   linked.
9. The helper's output on a fixture with three tracked items is exactly those three names,
   sorted (a pinned non-empty value, so a helper returning nothing cannot pass).

Mutation controls, run during Phase 2 and recorded in the PR: restoring the glob turns case 2
red; removing the empty-list check turns case 7's helper assertion red.

## Requirements

- **R1.** `[PR1]` `setup_dotfile_symlinks` links an ai-config `.claude` or `.cursor` item only when `git ls-files` reports at least one file at or under it.
- **R2.** `[PR1]` An untracked file or directory in `ai-config/.claude/` or `ai-config/.cursor/` is never linked.
- **R3.** `[PR1]` A directory tracked only through `.gitkeep` is linked.
- **R4.** `[PR1]` The existing skips are unchanged: `.claude/rules` and `.cursor/User` are never linked by the loop, `.claude/projects` and `.cursor/rules` are linked exactly once.
- **R5.** `[PR1]` Tracked names starting with `.` are not linked.
- **R6.** `[PR1]` The tracked list is read with `GIT_DIR`, `GIT_WORK_TREE`, `GIT_COMMON_DIR` and `GIT_INDEX_FILE` stripped, so an exported decoy does not change it.
- **R7.** `[PR1]` When the tracked list cannot be read or is empty, that subdir's loop links nothing, an error names the directory, the remaining links are still made, and the function returns 1.
- **R8.** `[PR1]` An existing symlink in `~/.claude` or `~/.cursor` whose `readlink` text is `<ai_config_dir>/<subdir>/<name>` for an untracked, non-explicit `<name>` produces exactly one warning naming it and the `rm` remedy, and is left in place.
- **R9.** `[PR1]` `CLAUDE.md` § Symlink Strategy states that only items git tracks in ai-config are linked and that stale links are warned about, not removed.
- **V1.** On `claude` after merge, run only the function under dry run (`DRY_RUN=1 bash -c 'source setup_env.sh; detect_env; setup_dotfile_symlinks'` from the main checkout, never a full `-t setup_user`); it warns for the five stale `.claude` links and `.cursor/plugins` and its log names no `Linked` line for an untracked item.
- **N1.** No symlink is removed automatically by this change.
- **N2.** No new doctor check.
- **N3.** `safe_link` is not modified.
- **N4.** No fallback to the glob when git fails.

## Multi-Lens Review

Reviewed at commit: `db917b56` (Step 7 self-review commit, before Step 8 dispatch)

### Goal-Fit

Finding: The allowlist is the simplest correct fix and worth building; the stale-link warning is not. (1) Its `rm <link>` remedy destroys data in the cited case: on `workstation` `~/.claude/dod-log` links to `ai-config/.claude/dod-log`, which holds 42 entries, and `dod-log.bak` no longer exists (orchestrator re-measured over `ssh workstation`, 2026-10-25), so `rm` leaves `dod_log.py` an empty directory. For `~/.cursor/plugins` it drops Cursor's live `plugins/cache`. (2) Reads-it test: the warning prints only on `setup_user`/`setup` (sole caller `lib/workflows.sh:402`), with no durable channel, so it does not change a decision in practice. (3) `.cursor/plugins` being linked is documented as deliberate in `ai-config/.claude/memory/ai-config-cursor-plugin-architecture.md:50` and `ai-config/docs/knowledge/dotfiles-conventions.md:341`; the spec reverses that silently and R9 covers only `CLAUDE.md`. (4) Cases 2, 5 and 8 pass on empty helper output; case 8 needs a pinned expected set.
Assumption: Nothing needs an untracked `~/.claude/<name>` link on a fresh machine; main suspect `settings.local.json`. Settled by the orchestrator: Claude Code docs (`code.claude.com/docs/en/permissions.md`) state "`~/.claude/settings.local.json` is still local scope, so Claude Code reads it only in sessions you start in your home directory itself". The spec's premise holds; ai-config's `2026-07-25-role-model-enforcement-design.md:99` ("governs all nine repos") is wrong.
Disposition:

### Ergonomics

Finding: Same remedy defect as Goal-fit: the warning must name a data-preserving remedy when the target is non-empty. Its premise that `workstation` still holds `dod-log.bak` is stale (re-measured: absent). Return 1 now skips the rest of `run_setup_user` (`install_terraform_skill`, default shell, cheat.sh, cadence agents, ledger entry) via `_run_or_exit`; the error line should say so. Possible WSL failure: an ai-config checkout under `/mnt/c` trips git's dubious-ownership check (unverified). Not noise: 6 warnings on a rare run on `claude`.
Assumption: Same `settings.local.json` scope question as Goal-fit; settled by the docs quote above.
Disposition:

### Risk

Finding: The test plan cannot run as written. `load_mocks` prepends `tests/mocks/` to `PATH` (`tests/helpers/common.bash:16`), and `tests/mocks/git` exits `${MOCK_GIT_EXIT:-0}` with empty stdout for `ls-files` (orchestrator read the mock), so the helper takes the empty-list branch under every mocked test. New cases 1, 3, 4, 6, 8 and 9 go red; 2, 5 and 7 go green vacuously; about 47 existing `setup_dotfile_symlinks` tests asserting `status -eq 0` in `install_guards.bats` and `extracted_functions.bats` flip red. Needs a named git seam (the `_CLAUDE_GUARD_GIT` shape, `lib/workflows.sh:100`) and a fixture decision for the existing tests. Second: the mutation control "removing the empty-list check turns case 7 red" is false, since a non-repo exits 128 and never reaches the empty check; add a case with a valid repo tracking nothing under `.claude`.
Assumption: Same `settings.local.json` scope question; settled by the docs quote above.
Disposition:

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.
