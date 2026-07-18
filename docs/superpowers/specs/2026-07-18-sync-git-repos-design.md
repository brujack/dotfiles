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
  - `_git_repo_status <path>` → echoes one of `clean`, `dirty`, `ahead`,
    `behind`, `diverged`, `missing` based on `git status --porcelain` and
    `git rev-list --left-right --count HEAD...@{u}`.
  - `_git_sync_one_repo <path>` → calls `_git_repo_status`, then:
    - `clean` → no-op
    - `dirty` → `log_warn "<repo>: uncommitted changes, skipping"`
    - `behind` → `git pull --ff-only`
    - `ahead` → `git push`
    - `diverged` → `log_warn "<repo>: diverged, skipping (manual rebase/merge required)"`
    - `missing` (path doesn't exist / not a git repo) → skip silently
  - `sync_git_repos()` → discovers repos via
    `find "${PERSONAL_GITREPOS}" -maxdepth 2 -name .git -type d` (dedup to
    parent dirs) plus the explicit `${HOME}/.local/share/state-ledger` path,
    calls `_git_sync_one_repo` per repo, prints a one-line status summary per
    repo, returns 0 always (non-fatal, matches `run_update` resilience
    pattern) — individual repo failures are warnings, not aborts.

- `lib/legacy_rsync.sh` — rsync logic, sourcing-guarded, unit-testable.
  - `sync_legacy_dirs()`:
    - Gate: `[[ $(hostname -s) == "studio" ]]` — non-studio hosts print a
      skip message and return 0.
    - `rsync -ar --delete --exclude=personal "${HOME}/git-repos/" "bruce@workstation:~/git-repos/"`
    - `rsync -ar --delete --exclude=personal "${HOME}/git-repos/" "bruce@laptop-1:~/git-repos/"`
    - `rsync -ar --delete "${HOME}/git-repos/" "bruce@ratna:~/git-repos/"` (no exclude — full backup)
    - Each rsync call's failure is warned and does not block the others.

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
  _update_record_end "git-repos" "${PIPESTATUS[0]}"

  _update_record_start "legacy-rsync"
  sync_legacy_dirs 2>&1 | tee "${_DOTFILES_RUN_TMPDIR}/err_legacy-rsync"
  _update_record_end "legacy-rsync" "${PIPESTATUS[0]}"
  ```
- `lib/update_summary.sh` — add `git-repos legacy-rsync` to
  `_UPDATE_SECTION_ORDER`.
- Delete `scripts/synch_git-repos.sh` (replaced in place, per user decision).
- Any doc/README references to the old filename updated.

## Data flow

```
setup_env.sh -t update
  └─ run_update()
       └─ [_run_all git-tools block]
            ├─ sync_git_repos()        (every machine)
            │    ├─ discover repos (personal/* + state-ledger)
            │    └─ per repo: fetch → classify → pull|push|warn
            └─ sync_legacy_dirs()      (studio only; no-op elsewhere)
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

## Testing

- `tests/setup_env/git_sync.bats` (new): `_git_repo_status` classification
  exercised against **real** temp git repos (bare "origin" + working clone),
  covering clean/dirty/ahead/behind/diverged/missing — per repo's existing
  pitfall-F rule (no hand-typed git plumbing fixtures for parser-style logic).
  Idempotency check: running `sync_git_repos` twice on an already-clean repo
  produces identical no-op output both times.
- `tests/setup_env/legacy_rsync.bats` (new): hostname gate tested both
  branches (studio → rsync invoked; non-studio → skip message, rsync never
  invoked) via mocked `hostname` and pass-through-asserting mocked `rsync`
  (verifies `--exclude=personal` present for workstation/laptop-1 targets,
  absent for ratna).
  `-h`/`--help` output tested for both flag spellings, exits 0, mentions both
  sync modes.
- `run_update` integration: existing `tests/setup_env/*.bats` patterns
  extended to assert the two new `_update_record_start/end` sections appear
  and respect `_run_all` gating.
- All new BATS files added to `make test-unit` coverage; `make lint`
  (shellcheck + bash -n + zsh -n) must pass on both new lib files and the
  entrypoint script.

## Rollout

Single feature branch, single PR — this is one cohesive unit of work, not
staged phases. Full Phase 3 gate chain via `finishing-a-development-branch`
applies (it's a `.sh` code change, not docs-only).
