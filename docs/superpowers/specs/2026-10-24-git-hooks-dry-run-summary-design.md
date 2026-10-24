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

- under `_dry_run_active`: `_result="dry run: install skipped"`;
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
   `result_git-hooks` is exactly `dry run: install skipped`.
2. `unset DRY_RUN` in the test itself (bats inherits the caller's environment), then `_update_record_end "git-hooks" 0`: `result_git-hooks` is exactly `updated`.

Case 2 stops an arm that always prints the dry-run text from passing; case 1 fails on today's
code, which writes `updated`. The existing test "_update_summary prints a git-hooks row with the
literal result production writes, not a fabricated counts string" seeds its own result file and
is unaffected.

Optional verification beyond the suite: `./setup_env.sh -t update --dry-run` on `claude` prints
`git-hooks` with `dry run: install skipped` in the summary table. That run is not offline:
it fetches, pulls `--ff-only` and installs packages for real (see `CLAUDE.md` `--dry-run`), so it
is run only if the operator asks for it. The dry-run sweep itself returns 0 on all three development boxes (measured 2026-10-24: `9 checked, n/a updated, 0 gaps`, rc 0 on `claude`, `workstation` and the Studio), so the new text is what those machines would show; on a machine with gaps the WARN replaces it, as today.

## Requirements

- **R1.** `_update_record_end` in `lib/update_summary.sh` has a `git-hooks)` case arm that sets `_result` to `dry run: install skipped` when `_dry_run_active` succeeds and to `updated` otherwise.
- **R2.** `_update_record_end` still writes status `OK` for `git-hooks` with exit 0, dry run or not.
- **R3.** `tests/setup_env/update_summary.bats` has a test asserting `result_git-hooks` equals `dry run: install skipped` and `status_git-hooks` equals `OK` after `_update_record_end "git-hooks" 0` with `DRY_RUN=1`, and a test that runs `unset DRY_RUN` itself and asserts `result_git-hooks` equals `updated`.
- **R4.** The Backlog row "`git-repos` and `git-hooks` render `[OK] … updated` …" is removed from the open P2 table.
- **R5.** The existing Backlog row "no-op update sections render `updated`" gains one sentence saying that for `git-hooks` the file `err_git-hooks` already holds the sweep's `<N> checked, <M> updated` summary line (written by the `tee` in `run_update`), so a count-reading arm needs no change to `lib/git_hooks.sh`. No new Backlog row is added for this gap.
- **V1.** The R3 dry-run test fails on `origin/master` before the R1 change and passes after it.
- **V2.** Optional, only if the operator asks: `./setup_env.sh -t update --dry-run` on `claude` shows the `git-hooks` row result `dry run: install skipped`.
- **N1.** No change to how `git-repos` renders, dry run or not.
- **N2.** No change to `run_update`'s rc-2→0 ternary for any section.
- **N3.** No change to `lib/git_hooks.sh`.

## Multi-Lens Review

Reviewed at commit: `d60fdce1`

### Round 1

#### Goal-Fit

Finding: No blocking issues; premise verified on `origin/master`. Non-blocking: a non-dry run still says `updated` when the sweep installed 0 hooks (needs `lib/git_hooks.sh`, outside N3), worth a Backlog row so R4 does not drop it; V2 costs a real update run to check a label the unit test pins, so make it optional.
Assumption: no uncertain assumption found (probe on `claude`: sweep under `DRY_RUN=1` returns 0, no gaps, no `core.hooksPath` pin).
Disposition: Addressed (operator, 2026-10-24) — V2 is optional. The R5 part was revised in round 2: the gap is already the open row "no-op update sections render `updated`", and the claim that the fix needs `lib/git_hooks.sh` is false (see Round 2).

#### Ergonomics

Finding: `dry run: hooks not installed` reads two ways in a scanned table (install skipped, or repos have no hooks); `dry run: install skipped` names the suppressed action like `[SKIP] legacy-rsync dry run`. Case 2 should `unset DRY_RUN` itself.
Assumption: the sweep returns 0, not 2, where `--dry-run` actually runs, else WARN hides the new text. Settled 2026-10-24: rc 0 with `9 checked, n/a updated, 0 gaps` on `claude`, `workstation` and the Studio.
Disposition: Addressed (operator, 2026-10-24) — text changed to `dry run: install skipped`; R3 and Testing require `unset DRY_RUN`.

#### Risk

Finding: No blocking issues. Arm ordering, SKIP/FAIL/WARN paths, ledger and width all unaffected; the spec should say `unset DRY_RUN` literally. Minor, accepted by design: under `--dry-run` an rc-2 WARN row does not say its gaps are pre-run state (the detail block does).
Assumption: no uncertain assumption found.
Disposition: Addressed (operator, 2026-10-24) — `unset DRY_RUN` written into R3; the WARN-row point stays accepted as already stated in Design.

### Round 2

Reviewed at commit: `e52391a8` (scoped re-check of the round-1 changes)

#### Ergonomics

Finding: R5 duplicates the open Backlog row "no-op update sections render `updated`", which already names `git-hooks` and proposes a `mas)`-shaped arm counting lines in `err_<section>`. R5's premise is also false: `run_update` pipes the sweep through `tee "${_DOTFILES_RUN_TMPDIR}/err_git-hooks"`, so the `<N> checked, <M> updated` summary line is already in that file, and N3 does not block the fix. The text change, `unset DRY_RUN` in R3 and the optional V2 read correctly.
Assumption: no uncertain assumption found (both claims verified by grep on `e52391a8`: the row in `docs/superpowers/README.md`, the `tee` in `lib/workflows.sh`, the summary line in `lib/git_hooks.sh`).
Disposition: Addressed (operator, 2026-10-24) — R5 now edits the existing row instead of adding one, and records the `err_git-hooks` route.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.
