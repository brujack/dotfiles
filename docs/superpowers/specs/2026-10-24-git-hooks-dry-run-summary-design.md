# git-hooks summary row under --dry-run

- **Date:** 2026-10-24
- **Backlog row:** "`git-repos` and `git-hooks` render `[OK] … updated` in the summary table over a dry run that did nothing" (P2 — bugs and security)

## Problem

Under `setup_env.sh -t update --dry-run`, the summary table prints `[OK] git-hooks updated`.
`install_git_hooks_all_repos` (`lib/git_hooks.sh`) sets `_dry=1` from `_dry_run_active`, and
every hook install goes through `run_cmd`, which only prints the `make` invocation under
`DRY_RUN`. No hook is installed. The sweep knows this: it reports `n/a updated` in its own
summary line, with a comment saying `0` "would falsely assert every repo was already current".
That line goes to `log_info`, which is not the table.

`_update_record_end` (`lib/update_summary.sh`) has no `git-hooks)` arm, so an rc-0 sweep falls
to `*) _result="updated"` and writes status `OK`, result `updated`. Verified 2026-10-24 by
reading the function on `origin/master` `3f14314b`: its arms are `brew`, `mas`, `gems`, `pip`,
`oh-my-zsh|tpm|tfenv|zsh-autosuggestions`, `softwareupdate`, `claude`, `npm`, `apt`, `snap`
and `*`.

### `git-repos` is out of scope by an earlier decision

The backlog row also names `git-repos`. `docs/superpowers/specs/2026-09-14-dry-run-irreversible-gating-design.md`
§2 left `[OK] git-repos` under `--dry-run` deliberately: `_git_repo_status` still runs
`git fetch` on every repo and `pull --ff-only` still runs on every repo that is behind, so only
the pushes are suppressed and the `[OK]` is truthful. A `[SKIP]` there was rejected in that
spec's review as "same lie, opposite sign". This spec does not revisit that.

### Why not SKIP for git-hooks

`legacy-rsync` renders `[SKIP] legacy-rsync dry run`, because under `--dry-run` it does nothing
at all. `git-hooks` does real work under `--dry-run`: the sweep checks every repo, counts gaps,
detects a pinned `core.hooksPath`, and can return 2 (WARN). Only the install step is suppressed.
A SKIP would deny that the checks ran.

## Design

Add a `git-hooks)` arm to the `case "${_section}"` in `_update_record_end`:

- under `_dry_run_active`: `_result="dry run: hooks not installed"`;
- otherwise: `_result="updated"`, unchanged from today.

The status stays `OK` in both cases. The arm sits after the early-return `FAIL` branch, so a
failed sweep (rc 1) still renders `[FAIL]`. A sweep returning 2 reaches `_update_record_end`
as 0 through the existing ternary and then `_update_warn` overwrites status and result to WARN,
exactly as today; under `--dry-run` that WARN still wins.

The rc-2→0 ternary in `run_update` is left as it is (operator decision 2026-10-24; its own
Backlog row stays open).

## Testing

Two cases in `tests/setup_env/update_summary.bats`, written RED first:

1. `DRY_RUN=1`, `_update_record_end "git-hooks" 0`: `status_git-hooks` is `OK` and
   `result_git-hooks` is exactly `dry run: hooks not installed`.
2. `DRY_RUN` unset, `_update_record_end "git-hooks" 0`: `result_git-hooks` is exactly `updated`.

Case 2 stops an arm that always prints the dry-run text from passing; case 1 fails on today's
code, which writes `updated`. The existing test "_update_summary prints a git-hooks row with the
literal result production writes, not a fabricated counts string" seeds its own result file and
is unaffected.

Verification beyond the suite: `./setup_env.sh -t update --dry-run` on `claude` prints
`git-hooks` with `dry run: hooks not installed` in the summary table. That run is not offline:
it fetches, pulls `--ff-only` and installs packages for real (see `CLAUDE.md` `--dry-run`), so it
is run only with the operator's go-ahead.

## Requirements

- **R1.** `_update_record_end` in `lib/update_summary.sh` has a `git-hooks)` case arm that sets `_result` to `dry run: hooks not installed` when `_dry_run_active` succeeds and to `updated` otherwise.
- **R2.** `_update_record_end` still writes status `OK` for `git-hooks` with exit 0, dry run or not.
- **R3.** `tests/setup_env/update_summary.bats` has a test asserting `result_git-hooks` equals `dry run: hooks not installed` and `status_git-hooks` equals `OK` after `_update_record_end "git-hooks" 0` with `DRY_RUN=1`, and a test asserting `result_git-hooks` equals `updated` with `DRY_RUN` unset.
- **R4.** The Backlog row "`git-repos` and `git-hooks` render `[OK] … updated` …" is removed from the open P2 table.
- **V1.** The R3 dry-run test fails on `origin/master` before the R1 change and passes after it.
- **V2.** With the operator's go-ahead, `./setup_env.sh -t update --dry-run` on `claude` shows the `git-hooks` row result `dry run: hooks not installed`.
- **N1.** No change to how `git-repos` renders, dry run or not.
- **N2.** No change to `run_update`'s rc-2→0 ternary for any section.
- **N3.** No change to `lib/git_hooks.sh`.
