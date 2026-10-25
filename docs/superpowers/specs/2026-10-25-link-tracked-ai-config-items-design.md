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

git is resolved through a seam, `_AI_CONFIG_GIT` (default `git`), in the shape of
`_CLAUDE_GUARD_GIT` (`lib/workflows.sh:100`). Under `load_mocks`, `tests/mocks/git` shadows
real git and answers `ls-files` with rc 0 and empty stdout, so without the seam every mocked
test would take the empty-list branch. `load_mocks` points `_AI_CONFIG_GIT` at a private shim
directory holding a symlink to the real git, so the helper queries the fixture's real index.

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

### Home stores

Tracked is not the same as config. `ai-config/.claude/dod-log/.gitkeep` was tracked from
`1b73df1d` (2026-06-30) to `2a1e5b9d` (2026-07-29); in that window the allowlist alone would
have linked `dod-log` over the real `~/.claude/dod-log`. (The actual `workstation` link was
born 2026-09-11, `stat -c %w`, after the `.gitkeep` was gone, so the allowlist would have
prevented that instance; the class remains.)

A readonly array `CLAUDE_HOME_STORES` in `lib/constants.sh` names the items that ai-config's
own code writes through `~/.claude/<name>` and that must stay machine-local:
`dod-log`, `logs`, `plugin-verdicts.json`, `skill-log`, `skip-ledger.jsonl`. Measured
2026-10-25 by `git grep` over ai-config's non-test `*.py`/`*.sh` for `Path.home() / ".claude"
/ "<name>"` and `${HOME}/.claude/<name>` (population: ai-config's tracked scripts and hooks at
that commit; Claude Code's own `~/.claude` writers are not ai-config items and are not in
scope). `dispatch-log` (`hooks/dispatch-log.sh:64`) and the four
`telemetry_path.STREAMS` (`cost-log`, `loop-log`, `review-cycle`, `triage-log`; their
`Path.home()` fallback is built from a variable, so the grep cannot see it and they were
enumerated by reading `scripts/telemetry_path.py`) are also written through `~/.claude`, but
they are tracked and linked by design, so their home-path fallback lands in ai-config; they
are deliberately not in the list. A name in the list is never linked by the loop, tracked or not. A new
home-anchored writer must be added to the list by hand; nothing detects the omission.

### The two loops

Each loop iterates the helper's output instead of the glob, keeps its existing skips
(`projects` and `rules` for `.claude`, `User` for `.cursor`) and the explicit
`projects`/`rules` links after it, and still calls `safe_link` per item. An item the helper
names but that is absent on disk (tracked, deleted in the working tree) is skipped, as the
glob's `[[ -e ]]` check does today.

If the helper fails for a subdir, that subdir's loop links nothing (including the explicit
`projects` link for `.claude` and `rules` link for `.cursor`, so nothing at all is linked
from that subdir), `log_error` names the
directory and the failed command, the rest of the function runs, and the function returns 1
at its end. Because `run_setup_user` calls it as `setup_dotfile_symlinks || return 1`, that
return skips every later `setup_user` step (`install_terraform_skill`, the default-shell
step, cheat.sh, the cadence agents, the ledger entry), so the error line says the remaining
setup steps were skipped. The branch is close to unreachable in production:
`setup_ai_config` clones or updates the same checkout with the same git one line earlier. It never falls back to the glob. `run_setup_user` already treats 1 as a failure
(`lib/workflows.sh:402`).

### Stale-link warning

After each loop, scan `~/.claude/*` (or `~/.cursor/*`). For each entry that is a symlink whose
`readlink` text is exactly `<ai_config_dir>/.claude/<name>` (or `.cursor/<name>`), where
`<name>` is either not in the tracked list or is in `CLAUDE_HOME_STORES`, and is not one of
the explicitly-linked names, emit one `log_warn` naming the link, its target, and a remedy
chosen by the name:

- `<name>` in `CLAUDE_HOME_STORES` and the target is a non-empty directory:
  `rm <link> && mkdir <link> && cp -a <target>/. <link>/`, which leaves ai-config's copy in
  place as a backup. A bare `rm` there is wrong: on `workstation` `~/.claude/dod-log` links to
  an ai-config directory holding 42 entries and no `dod-log.bak` exists (measured 2026-10-25),
  so `rm` alone would hand `dod_log.py` an empty directory. For a home-store file target
  (`skip-ledger.jsonl`, `plugin-verdicts.json`): `rm <link> && cp -a <target> <link>`.
- every other stale link: `rm <link>`. The data stays in ai-config, and no ai-config code
  reads these names through `~/.claude`. Copying them would be wrong for `worktrees`: a
  non-empty `ai-config/.claude/worktrees` holds live git worktrees whose `.git` files point
  at shared admin directories, and a copy would be a second checkout of each.

The warning fires only on `setup_user`/`setup` (the function's sole caller,
`lib/workflows.sh:402`); a doctor check is out of scope (N2). The link is never
removed: on `workstation` the stale `dod-log` link holds the live DoD entries, and removing it
mid-session would hide them from the pre-push gate — the same harm this change exists to stop.
Matching on the literal `readlink` text is deliberate: `safe_link` writes that exact string, so
a link the operator pointed elsewhere by hand is never reported.

The warning runs only when the helper succeeded for that subdir; with no tracked list there
is nothing to compare against.

## Testing

Existing tests: about 47 tests in `install_guards.bats` and `extracted_functions.bats` call
`setup_dotfile_symlinks` against plain-directory ai-config fixtures and assert `status -eq 0`.
They move to one shared fixture builder in `tests/helpers/common.bash` that `git init`s the
fixture and `git add`s its `.claude`/`.cursor` contents with no commit (`ls-files` reads the
index; a commit fails on CI, which has no `user.name`, and would expose the fixture to a
global `commit.gpgsign` or hook), and strips the four `GIT_*` variables, so their assertions
stay unchanged.

A second group is affected and is not reached by that builder: `run_setup_user` tests
(`workflows.bats`, `unit.bats`, `developer.bats`) leave
`AI_CONFIG_DIR` at its source-time default derived from the real `HOME`
(`lib/constants.sh`). On CI that path does not exist, so the helper fails, the function
returns 1, and `run_setup_user` stops before the steps those tests assert; on `claude` the
same path is the real ai-config, so they would pass locally by reading the real index.
`load_mocks` therefore also defaults `_OVERRIDE_AI_CONFIG_DIR` to a per-test git fixture built
by the same helper, rooted under `BATS_TEST_TMPDIR` (never `HOME`: `workflows.bats` calls
`load_mocks` before it redirects `HOME`) and tracking at least one item under each of
`.claude` and `.cursor`, so the default never takes the empty-list branch. The plan counts both groups with `grep`, not by estimate.

All new cases in `tests/setup_env/install_guards.bats`, against a fixture ai-config built as a real
git repo under `BATS_TEST_TMPDIR` (with `unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR
GIT_INDEX_FILE` in `setup()`), `HOME` redirected to a fixture at `setup()` scope, and
`_OVERRIDE_AI_CONFIG_DIR` pointing at the fixture.

1. A tracked file and a tracked directory under `.claude` are linked.
2. An untracked directory and an untracked file under `.claude` are not linked, while a
   tracked sibling is (positive control) and the function returns 0.
3. A directory tracked only through `.gitkeep` is linked.
4. `rules` is not linked; `projects` is linked exactly once; `.cursor/User` is not linked
   and `.cursor/rules` is.
5. An untracked `.cursor` directory is not linked, while `.cursor/skills-cursor` (tracked)
   is, and the function returns 0.
6. A pre-existing `~/.claude/<untracked>` symlink to the fixture produces exactly one warning
   naming it, and still exists afterwards; a pre-existing symlink to a path outside the
   fixture produces none.
7. A fixture that is not a git repo: return 1, an error naming the directory, and no
   `~/.claude` or `~/.cursor` links into the fixture; links outside ai-config (e.g.
   `~/.vimrc`) are still made.
8. An exported decoy `GIT_DIR` pointing at a different repo does not change which items are
   linked: the linked set equals a pinned expected list, not merely the decoy-free run.
9. The helper's output on a fixture with three tracked items is exactly those three names,
   sorted (a pinned non-empty value, so a helper returning nothing cannot pass).

10. A valid repo that tracks nothing under `.claude`: return 1 with the empty-list error and
    no `.claude` links (this is the case that kills the empty-check mutant; case 7 cannot,
    because a non-repo exits 128 before the empty check).
11. A stale `dod-log` link to a non-empty directory names the `cp -a` remedy; a stale
    non-empty `worktrees` link names `rm <link>`.
12. A tracked, `.gitkeep`-only `dod-log` in the fixture, with a real `~/.claude/dod-log`
    present, is not linked and no `~/.claude/dod-log.bak` appears.
Mutation controls, run during Phase 2 and recorded in the PR: restoring the glob turns case 2
red; removing the empty-list check turns case 10 red.

## Requirements

- **R1.** `[PR1]` `setup_dotfile_symlinks` links an ai-config `.claude` or `.cursor` item only when `git ls-files` reports at least one file at or under it.
- **R2.** `[PR1]` An untracked file or directory in `ai-config/.claude/` or `ai-config/.cursor/` is never linked.
- **R3.** `[PR1]` A directory tracked only through `.gitkeep` is linked.
- **R4.** `[PR1]` The existing skips are unchanged: `.claude/rules` and `.cursor/User` are never linked by the loop, `.claude/projects` and `.cursor/rules` are linked exactly once.
- **R5.** `[PR1]` Tracked names starting with `.` are not linked.
- **R6.** `[PR1]` The tracked list is read with `GIT_DIR`, `GIT_WORK_TREE`, `GIT_COMMON_DIR` and `GIT_INDEX_FILE` stripped, so an exported decoy does not change it.
- **R7.** `[PR1]` When the tracked list cannot be read or is empty, that subdir's loop links nothing, an error names the directory, the remaining links are still made, and the function returns 1.
- **R8.** `[PR1]` An existing symlink in `~/.claude` or `~/.cursor` whose `readlink` text is `<ai_config_dir>/<subdir>/<name>` for an untracked, non-explicit `<name>` produces exactly one warning naming it and a remedy chosen by the name (`rm <link> && mkdir <link> && cp -a <target>/. <link>/` for a `CLAUDE_HOME_STORES` directory with contents, `rm <link> && cp -a <target> <link>` for a `CLAUDE_HOME_STORES` file, `rm <link>` otherwise), and is left in place; a link to a `CLAUDE_HOME_STORES` name warns even when the name is tracked.
- **R9.** `[PR1]` The helper resolves git through `_AI_CONFIG_GIT` (default `git`), and `load_mocks` points it at real git so mocked tests query the fixture's real index.
- **R10.** `[PR1]` `CLAUDE.md` § Symlink Strategy states that only items git tracks in ai-config are linked and that stale links are warned about, not removed.
- **R11.** `[PR1]` A name in `CLAUDE_HOME_STORES` (`dod-log`, `logs`, `plugin-verdicts.json`, `skill-log`, `skip-ledger.jsonl`) is never linked into `~/.claude`, even when ai-config tracks it.
- **R12.** `[PR1]` `load_mocks` defaults `_OVERRIDE_AI_CONFIG_DIR` to a per-test git fixture under `BATS_TEST_TMPDIR` that tracks at least one item under each of `.claude` and `.cursor`, so no test reads the real ai-config index.
- **V1.** On `claude` after merge, run only the function under dry run (`DRY_RUN=1 bash -c 'source setup_env.sh; detect_env; setup_dotfile_symlinks'` from the main checkout, never a full `-t setup_user`); it warns for the five stale `.claude` links and `.cursor/plugins` and its log names no `Linked` line for an untracked item.
- **V2.** In ai-config, after notifying its session: update `.claude/memory/ai-config-cursor-plugin-architecture.md` and `docs/knowledge/dotfiles-conventions.md` (both describe `~/.cursor/plugins` as linked) and add a Backlog row correcting `docs/superpowers/specs/2026-07-25-role-model-enforcement-design.md:99`, which claims `~/.claude/settings.local.json` governs all nine repos (Claude Code reads it only for sessions started in `$HOME`, per `code.claude.com/docs/en/permissions.md`).
- **N1.** No symlink is removed automatically by this change.
- **N2.** No new doctor check.
- **N3.** `safe_link` is not modified.
- **N4.** No fallback to the glob when git fails.

## Multi-Lens Review

Reviewed at commit: `db917b56` (Step 7 self-review commit, before Step 8 dispatch)

### Goal-Fit

Finding: The allowlist is the simplest correct fix and worth building; the stale-link warning is not. (1) Its `rm <link>` remedy destroys data in the cited case: on `workstation` `~/.claude/dod-log` links to `ai-config/.claude/dod-log`, which holds 42 entries, and `dod-log.bak` no longer exists (orchestrator re-measured over `ssh workstation`, 2026-10-25), so `rm` leaves `dod_log.py` an empty directory. For `~/.cursor/plugins` it drops Cursor's live `plugins/cache`. (2) Reads-it test: the warning prints only on `setup_user`/`setup` (sole caller `lib/workflows.sh:402`), with no durable channel, so it does not change a decision in practice. (3) `.cursor/plugins` being linked is documented as deliberate in `ai-config/.claude/memory/ai-config-cursor-plugin-architecture.md:50` and `ai-config/docs/knowledge/dotfiles-conventions.md:341`; the spec reverses that silently and R9 covers only `CLAUDE.md`. (4) Cases 2, 5 and 8 pass on empty helper output; case 8 needs a pinned expected set.
Assumption: Nothing needs an untracked `~/.claude/<name>` link on a fresh machine; main suspect `settings.local.json`. Settled by the orchestrator: Claude Code docs (`code.claude.com/docs/en/permissions.md`) state "`~/.claude/settings.local.json` is still local scope, so Claude Code reads it only in sessions you start in your home directory itself". The spec's premise holds; ai-config's `2026-07-25-role-model-enforcement-design.md:99` ("governs all nine repos") is wrong.
Disposition: Addressed — remedy is now chosen by target contents (`cp -a` for a non-empty directory); case 8 pins an expected set; V2 updates the two ai-config docs and the wrong 2026-07-25 line. Reads-it: Accepted, operator 2026-10-25 — chose the data-safe-remedy option whose stated cost is that the warning still prints only on setup_user.

### Ergonomics

Finding: Same remedy defect as Goal-fit: the warning must name a data-preserving remedy when the target is non-empty. Its premise that `workstation` still holds `dod-log.bak` is stale (re-measured: absent). Return 1 now skips the rest of `run_setup_user` (`install_terraform_skill`, default shell, cheat.sh, cadence agents, ledger entry) via `_run_or_exit`; the error line should say so. Possible WSL failure: an ai-config checkout under `/mnt/c` trips git's dubious-ownership check (unverified). Not noise: 6 warnings on a rare run on `claude`.
Assumption: Same `settings.local.json` scope question as Goal-fit; settled by the docs quote above.
Disposition: Addressed — data-safe remedy; error line names the skipped setup steps. WSL `/mnt/c` ownership: not addressed, unverified and not where the WSL checkout lives today.

### Risk

Finding: The test plan cannot run as written. `load_mocks` prepends `tests/mocks/` to `PATH` (`tests/helpers/common.bash:16`), and `tests/mocks/git` exits `${MOCK_GIT_EXIT:-0}` with empty stdout for `ls-files` (orchestrator read the mock), so the helper takes the empty-list branch under every mocked test. New cases 1, 3, 4, 6, 8 and 9 go red; 2, 5 and 7 go green vacuously; about 47 existing `setup_dotfile_symlinks` tests asserting `status -eq 0` in `install_guards.bats` and `extracted_functions.bats` flip red. Needs a named git seam (the `_CLAUDE_GUARD_GIT` shape, `lib/workflows.sh:100`) and a fixture decision for the existing tests. Second: the mutation control "removing the empty-list check turns case 7 red" is false, since a non-repo exits 128 and never reaches the empty check; add a case with a valid repo tracking nothing under `.claude`.
Assumption: Same `settings.local.json` scope question; settled by the docs quote above.
Disposition: Addressed — `_AI_CONFIG_GIT` seam (R9), shared git fixture builder for the existing tests, case 10 for the empty-check mutant.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.

### Round 2

Reviewed at commit: `0df33b5c` (all three lenses re-run: the round-1 revision changed design substance).

**Goal-Fit.** Finding: tracked is not config. `dod-log/.gitkeep` was tracked 2026-06-30 to 07-29 (`1b73df1d`..`2a1e5b9d`, orchestrator re-ran `git log`), so the allowlist alone re-arms the incident whenever a home-anchored store gains a `.gitkeep`; eight `.gitkeep`-only log dirs are tracked today. The `cp -a` remedy keyed on contents copies orphan logs nobody reads. Assumption: no home-anchored store is or becomes tracked; `ssh workstation 'stat -c %w ~/.claude/dod-log'` returned 2026-09-11 (after the `.gitkeep` was removed), so the allowlist would have prevented that instance. Disposition: Addressed — operator chose the named home-store list (2026-10-25): `CLAUDE_HOME_STORES` (R11), never linked even when tracked; remedy keyed on the name.

**Ergonomics.** Finding: no load-bearing issues; remedies paste-safe on `claude` and `workstation` (`workstation` adds stale `scheduled_tasks.lock`, remedy `rm`). Cases 2 and 5 pass vacuously on a silent helper and need a positive control; case numbering out of order; R7 wording loose on whether the explicit `projects` link survives a helper failure. Assumption: none genuinely uncertain. Disposition: Addressed — positive controls in cases 2 and 5, cases renumbered, R7 failure path now skips the explicit links too.

**Risk.** Finding: about 50 `run_setup_user` tests in `workflows.bats`, `unit.bats`, `launch_agents.bats` and `developer.bats` leave `AI_CONFIG_DIR` at the real-`HOME` default; on CI that path is missing, so the helper fails and `run_setup_user` stops (red on CI, green on `claude` via the real index). The fixture builder's `git commit` fails with no `user.name` on CI; `git add` alone suffices. `cp -a` on a non-empty `worktrees` would duplicate live worktrees. Assumption: nothing writes through the untracked links with cwd=`$HOME` on any machine. Disposition: Addressed — R12 (`load_mocks` defaults `_OVERRIDE_AI_CONFIG_DIR` to a git fixture), builder uses `git add` only, `worktrees` and every non-home-store name get `rm <link>`.

### Round 3 (scoped)

Reviewed at commit: `a366a7af`, Risk lens only, scoped to the round-2 diff (`0df33b5c..a366a7af`).

**Risk.** Finding: no load-bearing issues; `CLAUDE_HOME_STORES` re-derived by a wider grep (`Path.home()`, `expanduser`, `${HOME}/.claude`, 47 hits) and found correct and complete. Three precision gaps: the carve-out omitted `telemetry_path.STREAMS` (`cost-log`, `review-cycle`, `triage-log`), correct only because they are tracked; R12 did not fix the fixture's root or minimum contents; `launch_agents.bats` was wrongly listed as affected. Assumption: none genuinely uncertain; future home-anchored writers are a disclosed limit. Disposition: Addressed — wording-level fixes to the carve-out, R12 and the affected-file list; no further round.
