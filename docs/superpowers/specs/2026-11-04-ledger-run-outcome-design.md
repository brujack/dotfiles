# Ledger run outcome: record failed dotfiles runs

- **Status:** Draft (descoped after Step 8 round 2)
- **Date:** 2026-11-04
- **Repos:** dotfiles (writer, dispatcher), state-ledger (display, README)
- **Backlog row:** "setup/developer ledger entries record success over failed steps"

## Problem

Each dotfiles run function writes a state-ledger entry through
`_ledger_write_run_entry RUN_TYPE EXIT_CODE` (`lib/update_summary.sh:588`), whose
`success` field is `exit_code == 0`. Measured 2026-11-04 against `origin/master`
`30f2f40c`:

1. **Hard failures leave no entry.** Every `|| return 1` in `run_setup_user`,
   `run_setup_or_developer`, `run_developer_or_ansible`, `run_recreate_venv` and
   `run_recreate_ruby` (`lib/workflows.sh` 420-667) exits before
   `_ledger_write_run_entry`, so a run that died writes nothing. On the live ledger (947
   dotfiles entries) no non-`update` entry is `success: false`, and the latest
   non-`update` entry on every machine reads `success: true`.
2. **`developer` contradicts the schema.** `run_developer_or_ansible` passes `${_gh_rc}`
   (2 on a gh partial) while returning 0, so that run is `success: false` against
   state-ledger's README ("`true` if the run function returned exit 0").
3. **The display cannot answer a hunt.** `ledger history` prints `ts STATUS run=<id8>`
   with no run type; `ledger status` prints the latest entry per machine with no run
   type. After a failure the reader cannot tell which run failed.

**Readers.** The operator works at the console. The ledger is read after a failure, by the
operator or by an agent asked to hunt one down, through `ledger history`/`status` and the
entry JSON. `cmd_drift` also reads the latest `started_at`; failed entries now count as
fresh, which is immaterial because `update` already writes on FAIL.

**Descoped: partial runs.** The backlog row's original complaint (partial
setup/developer runs recorded as `success: true`) is not addressed here. Two review rounds
showed a `partial` outcome would be standing noise rather than signal: 28 of 34 recent
full `update` runs on `claude` with no FAIL had a WARN, the last 6 all from one bug (the
`git-repos` WARN below), and `install_git_hooks_all_repos` rc 2 is documented as "nothing
failed". The partial work moves to the backlog with those measurements as its blocker,
beside two defects found on the way (see "Backlog rows added").

**Corrected premise.** The backlog row named the two recreate workflows as passing a wrong
literal `0`; they reach it only on success and change here only through defect 1.

## Design

### 1. Schema

Every dotfiles run entry gains `outcome`: `"failed"` when the exit code is non-zero, else
`"ok"`. `success` keeps its documented meaning, `exit_code == 0`, so for now `outcome`
restates it in the form the display and a future `partial` value share. Entries written
before this change have no `outcome` and are read by `success` as today.

### 2. One write per run

`_ledger_write_run_entry` returns 0 without writing when
`${_DOTFILES_RUN_TMPDIR}/ledger_written` exists, and creates that file after invoking
`ledger_write_entry`, whatever its return code. One run directory therefore yields at most
one entry. That closes two overwrite paths, both of which reuse a `run_id`, so
`_write_entry`'s `write_text` would replace the earlier entry:

- a statement added after a run function's own write later fails, and the dispatcher
  writes again;
- the dispatcher writes for a function that failed before creating its own run directory
  while a previous run's directory is still exported (unreachable today, since a failed
  `X=$(mktemp …) || return 1` assigns `""`).

### 3. Recording hard failures

`_run_or_exit` in `setup_env.sh`, the single dispatcher, on a non-zero return from
`run_setup_user` (`setup_user`), `run_setup_or_developer` (`setup`),
`run_developer_or_ansible` (`developer`), `run_recreate_venv` or `run_recreate_ruby`,
calls `_ledger_write_run_entry <run_type> <rc> || true` and then exits with the function's
own exit code. `run_update` is not mapped: it writes its own entry in `_update_summary`
(its outcome follows `_fail`, so WARN-only runs stay `ok`).

`run_developer_or_ansible` passes `0`, matching its return.

### 4. Bounded ledger write

`ledger_write_entry` (`lib/workflows.sh`) runs `ledger write` under
`GIT_SSH_COMMAND="$(_git_ssh_opts)"` (`BatchMode=yes`, `ConnectTimeout=10`). The new
failure-path write is most likely to run when ssh is already broken (the hard-abort sites
include `clone_or_update_dotfiles` and `setup_ai_config`), and ledger's git
`pull --rebase`/`push` has no batch mode or timeout of its own. `_clean_git_env` keeps
`GIT_SSH*`, and `ensure_state_ledger` already pulls the same repo under BatchMode every
run, so this adds no new auth dependency. A BatchMode failure spools the entry. On
`claude` the key has no passphrase and a BatchMode `ls-remote` with `SSH_AUTH_SOCK`
unset returns 0; the 7950X and the Studio are V3. `ConnectTimeout` bounds the connect
only; a stalled transfer is capped by `.ssh/config`'s `ServerAlive*` (about 10 minutes).

Not covered: a signal, and an `exit` inside a run function. No `failure_stage` for
non-`update` types (N3).

### 5. state-ledger (separate PR, coordinated with its owning session)

- `cmd_history` prints each entry's run type (`run_type` when present) and status:
  `outcome.upper()` when `outcome` is `ok` or `failed`, otherwise `OK`/`FAILED` from
  `success`.
- `cmd_status` prints the latest entry's run type and status by the same rule.
- README documents `outcome` and adds the missing `recreate_ruby` row. `_validate_entry`
  is unchanged (N1).

The dotfiles PR does not depend on it: the current display reads `success`, which stays
correct.

### 6. Folded in: `pyproject.toml` comment

`pyproject.toml:150` ("Must match what five repos' CI installs. Exported to
requirements-ci.txt.") is rewritten: the group is the full local/dev set rendered to
`requirements-ci.txt`, and consumers install the `ci-*` renderings. Its backlog row is
removed.

### Backlog rows added (same change as the spec)

- Partial run outcome: blocked on WARN noise (measurements above); revisit once standing
  WARN sources are fixed or classified.
- `git-repos` update section WARNs `/home/bruce/git-repos/personal: not a readable git
repository` on every run on `claude` (`lib/git_sync.sh:76`), treating the parent
  directory as a repo.
- `clone_personal_repos` returns only the last `if`'s status, so an earlier failed clone
  is masked; its caller (`lib/workflows.sh:647`) and `setup_vim_plugins`' caller
  (`:601`) ignore the status, so neither failure is reported.

## Testing

All `_run_or_exit` and writer tests share one fixture: a run directory with `started_at`,
a `machine-id` under the fixture `HOME`, and the recording `ledger` mock on `PATH`. The
absence cases below are controls only beside the positive ones in the same file.

- Writer: exit 0 writes `outcome` `ok`, `success` true; exit 1 writes `failed`/false;
  `developer` with a gh failure writes `ok`/true.
- Once per run: a second `_ledger_write_run_entry` in the same run directory writes
  nothing; the marker exists after a write whose `ledger` mock returns 2 (spooled).
- `_run_or_exit`: a failing mapped stub writes exactly one `failed` entry with its rc and
  exits with that rc; a mapped stub whose own write already ran, then fails, writes no
  second entry; a stub failing with a previous run's directory still exported writes
  nothing and that entry is unchanged; a failing `run_update` and a failing unmapped stub
  get no dispatcher write.
- `ledger_write_entry`: the mock records `GIT_SSH_COMMAND` equal to `_git_ssh_opts`'s
  output.
- state-ledger pytest: history and status with `outcome` `ok`, `failed`, absent and
  malformed, and with and without `run_type`.

## Requirements

- **R1.** `[PR1]` `_ledger_write_run_entry` writes `"outcome": "failed"` when its exit code argument is non-zero and `"outcome": "ok"` otherwise, for every run type including `update`.
- **R2.** `[PR1]` `_ledger_write_run_entry` returns 0 without writing when `${_DOTFILES_RUN_TMPDIR}/ledger_written` exists, and creates that file after invoking `ledger_write_entry` whatever its return code.
- **R3.** `[PR1]` `run_developer_or_ansible` passes `0` to `_ledger_write_run_entry`.
- **R4.** `[PR1]` On a non-zero return from `run_setup_user`, `run_setup_or_developer`, `run_developer_or_ansible`, `run_recreate_venv` or `run_recreate_ruby`, `_run_or_exit` calls `_ledger_write_run_entry <run_type> <rc> || true` with run types `setup_user`, `setup`, `developer`, `recreate_venv`, `recreate_ruby`, then exits with the function's own exit code; it calls nothing for `run_update` or any unmapped function.
- **R5.** `[PR1]` `ledger_write_entry` runs `ledger write` with `GIT_SSH_COMMAND` set to `_git_ssh_opts`'s output.
- **R6.** `[PR2]` state-ledger `cmd_history` prints each entry's run type and status (`outcome.upper()` when `outcome` is `ok` or `failed`, else `OK`/`FAILED` from `success`); `cmd_status` prints the latest entry's run type and status by the same rule.
- **R7.** `[PR2]` state-ledger README documents `outcome` and lists `recreate_ruby` in the `run_type` table.
- **R8.** `[PR1]` The `pyproject.toml` `test-lint` comment no longer claims any repo's CI installs `requirements-ci.txt`; that backlog row is removed and the three rows under "Backlog rows added" are added.
- **V1.** After PR1 merges, the next real `-t update` on `claude` writes an entry with `"outcome": "ok"` or `"failed"` matching its `success`.
- **V2.** dotfiles CI bash coverage stays at or above 91%.
- **V3.** Before PR1 merges, `env -u SSH_AUTH_SOCK GIT_SSH_COMMAND='ssh -o BatchMode=yes -o ConnectTimeout=10' git -C ~/.local/share/state-ledger ls-remote origin HEAD </dev/null` returns 0 on the 7950X and the Studio.
- **N1.** No change to state-ledger `_validate_entry`, and no field becomes required: entries without `outcome` stay valid.
- **N2.** `success` keeps the meaning "the run function returned exit 0" for every run type.
- **N3.** No `failure_stage` field for run types other than `update`.
- **N4.** `run_brew_install` and `run_mas_install` still write no ledger entry.
- **N5.** No run function's exit code changes, and no step that continues today aborts.
- **N6.** No `"partial"` outcome value and no per-step marks.

## Multi-Lens Review

Round 1 reviewed at commit `be156684`; round 2 at `7da66acc`. The descope below was
re-reviewed by a scoped Risk lens (see "Round 3").

### Goal-Fit

Round 1 — Finding: `partial_steps` had no reader; `status` shows latest-per-machine, `history` no run type. Proposed deleting the stale-tmpdir unset and the marker file. Assumption: the operator reads the ledger to judge a setup run.
Disposition: Addressed. Operator: "I will check the ledger after a failure or ask you to hunt it down. My main interaction is at the console." Readers rewritten; history shows run type and status.

Round 2 — Finding: the `log_warn` lint would have missed 7 of the 18 sites, exactly the silent ones; the stale-tmpdir test was a control only with a shared machine-id fixture. Assumption: setup-type runs degrade often enough for marks to record anything.
Disposition: Addressed — descoped. Operator: "descope as recommended." Lint, helper and marks removed (N6); tests share one fixture.

### Ergonomics

Round 1 — Finding: display gap measured on the live ledger; helper plus lint proposed; silent sites; vacuous stale-tmpdir test.
Disposition: Addressed (round 1 revision), then superseded by the descope.

Round 2 — Finding: `partial` would be near-permanent: 28 of 34 clean full `update` runs on `claude` WARN, the last 6 from the `git-repos` parent-directory bug; `git-hooks` rc 2 is "nothing failed". Assumption: a partial is rare on a healthy machine.
Disposition: Addressed — descoped. Operator: "descope as recommended." Partial outcome to the backlog with these measurements; the `git-repos` bug gets its own row.

### Risk

Round 1 — Finding: unbounded ssh on the failure-path write; keep the stale-tmpdir unset; re-filter step names.
Disposition: Addressed (R5); the stale-tmpdir case is now covered by the one-write-per-run guard (R2).

Round 2 — Finding: R1/R2 contradicted R8 for `update`; dropping the marker left a same-run double write unguarded; the lint overclaimed; R7's vim half was already true; `git-hooks` rc 2 would make PARTIAL permanent; absence tests vacuous without a shared fixture. `GIT_SSH*` confirmed honoured; BatchMode `ls-remote` rc 0 on `claude`. Assumption: BatchMode push works on the 7950X and the Studio.
Disposition: Addressed — descoped. Operator: "descope as recommended." Writer-side one-write-per-run guard (R2); partial, lint and silent-site changes removed; shared test fixture; BatchMode on the other two machines is V3.

### Round 3 (scoped Risk re-review of the descope)

Pending.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.
