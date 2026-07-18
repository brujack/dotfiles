# sync_git_repos refactor — design spec

Date: 2026-07-18
Status: Approved (pending plan)

## Context

`scripts/synch_git-repos.sh` (typo'd filename) is a one-way `rsync -ar --delete`
push of the entire `~/git-repos` tree from studio to hardcoded hosts
(`laptop-1`, `workstation`, `ratna`). It predates multi-machine development:

- `terraform_ansible` (and other `personal/` repos) are now actively written
  on both studio and workstation, not just studio. A blind `rsync --delete`
  push from studio would clobber workstation-only commits.
- `state-ledger` (`~/.local/share/state-ledger`, outside `~/git-repos`) is
  already git-clone/pull based via `ensure_state_ledger()` in
  `lib/workflows.sh`, but drifts across studio/laptop/workstation because
  local `ledger_write_entry` writes are never pushed back, and
  `pull --ff-only` failures are swallowed as a non-fatal warning.
- `ai-config` is already git-sync'd via `setup_ai_config()`, but skills
  created by Claude Code during a session can sit uncommitted long enough for
  Cursor's own updater to wipe them before they reach GitHub. This is a
  Cursor-side bug/interaction and is **out of scope** for this refactor — the
  fix here only makes the drift _visible_ early (see Non-Goals).
- Legacy client work directories (`~/git-repos/{other,cybernetiq,edc,fortis,
fullscript,leonovus,multiview,securekey,warpdotdev}`) are copies of
  repositories the user no longer has git access to. Studio remains the
  single source of truth for these; a one-way rsync push is still correct
  and does not need to change in spirit.
- `ratna` runs no development at all — it is a pure backup sink.

## Goals

1. Git-native sync (fetch/fast-forward/warn) for `personal/` repos +
   `state-ledger`, safe to run on any of the three dev machines
   (studio, workstation, laptop) without ever clobbering local work.
2. Preserve simple one-way rsync push for legacy/no-git-access directories,
   studio-only, with corrected (non-stale) target hosts.
3. Full-tree backup rsync (including `personal/`) to `ratna` only, since it
   never diverges (no dev happens there).
4. Callable both standalone (`./scripts/sync_git_repos.sh`) and automatically
   as part of `setup_env.sh -t update`.
5. `-h`/`--help` output on the standalone entrypoint describing both sync
   modes, flags, and exit behavior.

## Non-Goals

- Does not fix Cursor's skill-file-wiping behavior — that is a separate,
  external bug. This refactor only surfaces uncommitted/ahead/behind state
  earlier (via the `git-repos` update-summary section) so drift is caught
  before Cursor's next update can eat it.
- Does not auto-resolve diverged repos (local unpushed commits + new remote
  commits). Diverged repos are reported and skipped — manual
  rebase/merge required.
- Does not change how `state-ledger`'s own ledger binary writes entries —
  only how the repo itself is kept in sync across machines.

## Architecture

### New files

- `lib/git_sync.sh` — git-native sync logic, sourcing-guarded, unit-testable.
  - `_git_repo_status <path>` → runs `git fetch` first (required — `@{u}` is
    a local remote-tracking ref and is stale without an explicit fetch; a
    machine that hasn't fetched since another machine pushed would otherwise
    read 0/0 ahead-behind and misclassify a genuinely `behind` repo as
    `clean`). A fetch failure (unreachable remote) is its own outcome, not a
    fallthrough to whatever the stale ref says.
    Echoes a compound result: `dirty=<0|1> ahead=<n> behind=<n>` (or
    `unreachable` if fetch failed, `missing` if path doesn't exist / not a
    git repo). Dirty and ahead/behind are independent dimensions, not a
    single enum — see decision table below.
  - `_git_sync_one_repo <path>` → calls `_git_repo_status`, then decides
    per this explicit precedence (dirty does **not** block a safe push —
    only pull, since `push` never touches the working tree):

    | dirty | ahead | behind | action                                             |
    | ----- | ----- | ------ | -------------------------------------------------- |
    | any   | 0     | 0      | no-op (clean or dirty-with-no-commits-to-move)     |
    | any   | >0    | 0      | `git push` (safe regardless of dirty working tree) |
    | 0     | 0     | >0     | `git pull --ff-only`                               |
    | 1     | 0     | >0     | warn + skip (dirty tree, unsafe to pull)           |
    | any   | >0    | >0     | warn + skip, "diverged" (never auto-merge)         |
    | —     | —     | —      | `unreachable`/`missing` → warn + skip              |

    This resolves the ai-config motivating case in Context: locally
    committed-but-unpushed skills now push even when an unrelated scratch
    file is dirty elsewhere in the tree.

  - `sync_git_repos()` → discovers repos via
    `find "${PERSONAL_GITREPOS}" -maxdepth 2 -name .git -type d` (dedup to
    parent dirs; `-type d` intentionally excludes git worktrees, whose
    `.git` is a file containing a gitdir pointer — worktrees are ephemeral
    branch checkouts and should not be synced) plus the explicit
    `${HOME}/.local/share/state-ledger` path. Calls `_git_sync_one_repo` per
    repo, prints a one-line status per repo, and returns **2** if any repo
    was skipped (dirty+behind, diverged, unreachable, or missing), **0** if
    every repo synced cleanly. Never returns a hard-failure code — no
    `set -e`, no `exit` — this is "completed, possibly with warnings," not
    "aborted."

- `lib/legacy_rsync.sh` — rsync logic, sourcing-guarded, unit-testable.
  - `sync_legacy_dirs()` keeps its own internal
    `[[ $(hostname -s) == "studio" ]]` gate (prints a skip message, returns 0,
    runs no rsync on non-studio hosts) — this is the safety net that makes
    the function correct to call unconditionally, including standalone via
    `scripts/sync_git_repos.sh` on any machine. Separately, `run_update`'s
    `_update_record_start` gets its own `legacy-rsync)` case calling
    `_update_skip` (see Modified files) — this is a second, independent
    check whose only purpose is accurate summary _reporting_ (`SKIP` instead
    of a misleading `OK`), not safety; the function-level gate is what
    actually prevents the rsync calls from running.
    - `rsync -ar --delete --exclude=personal "${HOME}/git-repos/" "bruce@workstation:~/git-repos/"`
    - `rsync -ar --delete --exclude=personal "${HOME}/git-repos/" "bruce@laptop-1:~/git-repos/"`
    - `rsync -ar --delete "${HOME}/git-repos/" "bruce@ratna:~/git-repos/"` (no exclude — full backup)
    - Each rsync call's failure is warned and does not block the others.
      Returns 2 if any of the three legs failed, 0 if all three succeeded.

- `scripts/sync_git_repos.sh` — thin executable entrypoint, sourcing-guarded
  (testable + runnable). Sources `lib/git_sync.sh` and `lib/legacy_rsync.sh`
  via the same lib-loading pattern `setup_env.sh` uses. Supports:
  - `-h` / `--help` — prints usage: what the two sync modes do, which host
    runs the rsync leg, examples, exit codes. Exits 0.
  - no args (default) → runs `sync_git_repos` then `sync_legacy_dirs`
  - `--git-only` → runs only `sync_git_repos`
  - `--legacy-only` → runs only `sync_legacy_dirs`

### Modified files

- `lib/workflows.sh` `run_update()` — inside the existing `_run_all`
  git-tools block (alongside `setup_ai_config`), add:
  ```bash
  _update_record_start "git-repos"
  sync_git_repos 2>&1 | tee "${_DOTFILES_RUN_TMPDIR}/err_git-repos"
  _git_repos_rc="${PIPESTATUS[0]}"
  _update_record_end "git-repos" "$(( _git_repos_rc == 2 ? 0 : _git_repos_rc ))"
  [[ ${_git_repos_rc} -eq 2 ]] && _update_warn "git-repos" "one or more repos skipped — see detail"

  _update_record_start "legacy-rsync"
  sync_legacy_dirs 2>&1 | tee "${_DOTFILES_RUN_TMPDIR}/err_legacy-rsync"
  _legacy_rsync_rc="${PIPESTATUS[0]}"
  _update_record_end "legacy-rsync" "$(( _legacy_rsync_rc == 2 ? 0 : _legacy_rsync_rc ))"
  [[ ${_legacy_rsync_rc} -eq 2 ]] && _update_warn "legacy-rsync" "one or more rsync targets unreachable"
  ```
  Exit code 2 ("completed with warnings," defined in New files above) is
  translated to `_update_record_end`'s success path (0) so it isn't
  mis-recorded as `FAIL`, then immediately overridden to `WARN` via
  `_update_warn` — matching the existing `brew-drift` precedent
  (`_update_warn` called standalone, not through `_update_record_end`) and
  giving the summary a status distinct from both `OK` and `FAIL`. A real
  exit 1 (hard failure — should not occur given no `set -e`/`exit` in either
  function, but the wiring stays defensive) still records `FAIL`.
- `lib/workflows.sh` — add a `legacy-rsync)` branch inside
  `_update_record_start()`'s case statement (same pattern as the existing
  `apt`/`snap` "not applicable" branches):
  ```bash
  legacy-rsync)
    [[ "$(hostname -s)" != "studio" ]] && _update_skip "legacy-rsync" "not studio"
    ;;
  ```
  This is a reporting-only duplicate of the safety gate already inside
  `sync_legacy_dirs()` itself (see New files) — it exists so non-studio
  machines show `SKIP` in the summary instead of a misleading `OK`/"updated"
  (the function would already safely no-op without it; this only fixes what
  the summary _displays_).
- `lib/update_summary.sh` — add `git-repos legacy-rsync` to
  `_UPDATE_SECTION_ORDER`.
- Delete `scripts/synch_git-repos.sh` (replaced in place, per user decision).
- Any doc/README references to the old filename updated.

## Data flow

```
setup_env.sh -t update
  └─ run_update()
       └─ [_run_all git-tools block]
            ├─ sync_git_repos()        (every machine; exit 2 = warnings present)
            │    ├─ discover repos (personal/* + state-ledger)
            │    └─ per repo: fetch → classify (dirty × ahead × behind) → pull|push|warn
            └─ sync_legacy_dirs()      (skipped via _update_skip on non-studio;
                                         exit 2 = a target was unreachable)
                 ├─ rsync → workstation (exclude personal/)
                 ├─ rsync → laptop-1   (exclude personal/)
                 └─ rsync → ratna      (full tree)

./scripts/sync_git_repos.sh [--git-only|--legacy-only|-h]
  (same two functions, standalone, no run_update dependency)
```

## Error handling

- No `exit`/`set -e` anywhere in the two new libs — every failure path is a
  `log_warn` + continue, matching existing `setup_ai_config`/`ensure_state_ledger`
  resilience conventions. A single unreachable host or dirty repo never
  aborts the rest of the sync.
- Dirty repos are never stashed, force-pushed, or force-pulled — untouched,
  always.
- Diverged repos are never auto-merged or auto-rebased — reported only.
- `git fetch` failure is classified as `unreachable`, not silently treated
  as "no change since last fetch" — this is the difference between an
  honest "can't tell" and a false `clean`.
- Both sync functions use a 3-way return contract: `0` = fully synced/no
  action needed, `2` = completed with one or more repos/targets skipped
  (surfaced in the summary as `WARN` via `_update_warn`, called _after_
  `_update_record_end` so its write isn't the one getting overwritten — the
  reverse order is what `update_summary.sh`'s existing comment warns
  against), anything else = genuine bug (not expected in normal operation,
  since no path in either function calls `exit`).

## Testing

- `tests/setup_env/git_sync.bats` (new): `_git_repo_status` classification
  exercised against **real** temp git repos (bare "origin" + working clone),
  covering clean/dirty/ahead/behind/diverged/missing/unreachable — per
  repo's existing pitfall-F rule (no hand-typed git plumbing fixtures for
  parser-style logic). Explicit case: push new commits to the bare "origin"
  from a second clone _without_ fetching in the first clone, then call
  `_git_repo_status` — must report `behind`, not `clean` (this is the exact
  bug the fetch-first ordering fixes; a regression here would silently
  reintroduce it). Explicit case: `git fetch` against an unreachable/removed
  remote path reports `unreachable`, not a stale-ref-derived state.
  All 6 rows of the `_git_sync_one_repo` decision table get one test each,
  including dirty+ahead (must still push) and dirty+behind (must skip, not
  pull). Idempotency check: running `sync_git_repos` twice on an
  already-clean repo produces identical no-op output and exit 0 both times.
  Exit-code contract: a run with at least one skipped repo returns 2; a run
  with all repos clean/synced returns 0.
- `tests/setup_env/legacy_rsync.bats` (new): rsync invocation tested via
  mocked `hostname` and pass-through-asserting mocked `rsync` (verifies
  `--exclude=personal` present for workstation/laptop-1 targets, absent for
  ratna). Exit-code contract: one failed leg (mocked rsync non-zero) → 2;
  all three succeed → 0.
  `-h`/`--help` output tested for both flag spellings, exits 0, mentions both
  sync modes.
- `tests/setup_env/unit.bats`: extend `_update_record_start` coverage with
  the new `legacy-rsync)` case — both branches (studio → no skip write;
  non-studio → `_update_skip` called with "not studio").
- `run_update` integration: existing `tests/setup_env/*.bats` patterns
  extended to assert the two new sections appear, respect `_run_all` gating,
  and that an exit-2 return from either sync function ends up as `WARN` (not
  `OK` or `FAIL`) in `status_git-repos`/`status_legacy-rsync` — this is the
  regression test for finding 2 (false green): assert the file content
  directly, not just that the function returned non-fatally.
- All new BATS files added to `make test-unit` coverage; `make lint`
  (shellcheck + bash -n + zsh -n) must pass on both new lib files and the
  entrypoint script.

## Rollout

Single feature branch, single PR — this is one cohesive unit of work, not
staged phases. Full Phase 3 gate chain via `finishing-a-development-branch`
applies (it's a `.sh` code change, not docs-only).
