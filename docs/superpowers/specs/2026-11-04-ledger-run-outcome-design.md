# Ledger run outcome: record partial and failed dotfiles runs

- **Status:** Draft
- **Date:** 2026-11-04
- **Repos:** dotfiles (writer, callers, dispatcher), state-ledger (display, README)
- **Backlog row:** "setup/developer ledger entries record success over failed steps"

## Problem

Each dotfiles run function writes a state-ledger entry through
`_ledger_write_run_entry RUN_TYPE EXIT_CODE` (`lib/update_summary.sh:588`), whose
`success` field is `exit_code == 0`. Three defects, measured 2026-11-04 against
`origin/master` `30f2f40c`:

1. **Partial runs read as clean.** `run_setup_user` (`lib/workflows.sh:420`) and
   `run_setup_or_developer` warn and continue past 15 failed steps in total (listed in
   R5), then pass a literal `0`. A run that could not install aws-cli, cargo tools or the
   git hooks is recorded `success: true` and shown as `OK` by `ledger status`.
2. **Run types disagree.** `run_developer_or_ansible` passes `${_gh_rc}` (2 on a gh
   partial), so its partial run is `success: false`. That contradicts state-ledger's
   README, which defines `success` as "`true` if the run function returned exit 0", and
   the function returns 0 there. `update` maps WARN to `success: true`.
3. **Hard failures leave no entry.** Every `|| return 1` in a run function exits before
   `_ledger_write_run_entry`, so a run that died writes nothing. `ledger status` keeps
   showing the machine's last `OK` run, which is the strongest false-trust signal of the
   three.

Population: the counts come from `lib/workflows.sh` lines 420-667 (the five run functions
that write entries) and `lib/update_summary.sh`; `run_brew_install` and `run_mas_install`
write no entry today and are out of scope (N4).

**Corrected premise.** The backlog row also named the two recreate workflows. They are
correct as written: `run_recreate_venv` and `run_recreate_ruby` reach their literal `0`
only on success, since every failure returns 1 first. They change only through defect 3.

**Readers of the field** (measured: `git grep success` in state-ledger and ai-config):
state-ledger `cmd_status` (`scripts/ledger.py:881`) and `cmd_history` (`:945`), which
print `OK`/`FAILED`, and the `ledger-status` skill that runs them. No automated decision
reads a dotfiles run's `success`; `rollback-cycle` reads the migration-classifier and
deploy ledgers. The consumer is the operator reading status output.

## Design

### 1. Schema

Every dotfiles run entry gains two fields:

| Field           | Type                                | Meaning                                                                                             |
| --------------- | ----------------------------------- | --------------------------------------------------------------------------------------------------- |
| `outcome`       | `"ok"` \| `"partial"` \| `"failed"` | `failed` when the exit code is non-zero; else `partial` when any step was marked partial; else `ok` |
| `partial_steps` | array of strings                    | Step names marked partial during the run, in marking order; `[]` when none                          |

`success` keeps its documented meaning, `exit_code == 0`. A partial run is
`success: true, outcome: "partial"`; a hard failure is `success: false, outcome: "failed"`.
Entries written before this change have no `outcome` and are read by `success` as today.

`partial_steps` is kept on a `failed` entry too: steps that degraded before the abort are
still facts about the run.

### 2. Marking partial steps

A new helper, `_run_mark_partial STEP`, appends `STEP` and a newline to
`${_DOTFILES_RUN_TMPDIR}/partial_steps`. `STEP` must match `^[a-z0-9.-]+$` (`.` admits update's `cheat.sh` section); anything else
returns 1 and writes nothing. That keeps the field closed-form, so no step text can break
the hand-built JSON. With `_DOTFILES_RUN_TMPDIR` unset or missing, it returns 0 and writes
nothing, as the writer already no-ops there.

Each warn-and-continue site calls it beside its existing `log_warn` or `printf`. The 15
sites and their step names are listed in R5. The run functions' control flow and return
codes do not change (N5).

`run_developer_or_ansible` then passes `0`, since it returns 0 on a gh partial; its
partial is carried by the `github-cli` mark instead of by `success`.

### 3. `update`

`_ledger_write_dotfiles_entry` already reads `_fail` from `_update_summary`'s dynamic
scope. It also passes the WARN result: `outcome` is `partial` when `_fail == 0` and
`_warn > 0`, and `partial_steps` holds the names of the sections whose status is WARN, in
`_UPDATE_SECTION_ORDER` order. Update section names already match the same pattern.

### 4. Recording hard failures

`_run_or_exit` in `setup_env.sh` is the single dispatcher for every run function. It
changes in two ways:

- Before calling the function it unsets `_DOTFILES_RUN_TMPDIR`. Without this, a second
  run function in the same invocation (`-t setup` runs `run_setup_user` then
  `run_setup_or_developer`) that failed before its own tmpdir setup would write an entry
  carrying the first run's `run_id` and `started_at`. With it, such a failure finds no
  `started_at` and the writer no-ops, as it does today.
- On a non-zero return it calls `_ledger_write_run_entry <run_type> <rc>` before
  `exit`, mapping `run_setup_user`, `run_setup_or_developer`, `run_developer_or_ansible`,
  `run_update`, `run_recreate_venv`, `run_recreate_ruby` to their existing run types.
  `run_setup_or_developer`'s type stays `setup` (the value the function writes today).

  `run_update` already writes its own entry from `_update_summary` and then returns
  `_fail > 0`, so the dispatcher must not write a second one. A run function that wrote
  its own entry records that in the tmpdir (`${_DOTFILES_RUN_TMPDIR}/ledger_written`), and
  the dispatcher skips when the marker exists.

Not covered: a run killed by a signal, and an `exit` inside a run function. No
`failure_stage` is added for non-`update` types (N3); the console names the failing step.

### 5. state-ledger

- `cmd_status` and `cmd_history` print `entry["outcome"].upper()` when `outcome` is a
  string in `{"ok", "partial", "failed"}`, otherwise `OK`/`FAILED` from `success` as now.
- The README's dotfiles field table documents `outcome` and `partial_steps`, and the
  `run_type` table gains the missing `recreate_ruby` row.
- `_validate_entry` is unchanged: it shape-checks only named fields, so the new fields
  pass (N1).

The state-ledger change ships as its own PR, coordinated with the session that owns
state-ledger; the dotfiles change does not depend on it (old display shows
`OK`/`FAILED` from `success`, which stays correct).

### 6. Folded in: `pyproject.toml` comment

`pyproject.toml:150` reads "Must match what five repos' CI installs. Exported to
requirements-ci.txt." No repo installs `requirements-ci.txt` (backlog row, measured
2026-10-29). The comment is rewritten to say the group is the full local/dev set rendered
to `requirements-ci.txt`, and that consumers install the `ci-*` renderings. The backlog
row is removed in the same change.

## Testing

- dotfiles bats, writer: one case per outcome with the exact `outcome`,
  `partial_steps` and `success` values; a failed run that marked a step before aborting
  keeps it; `update` with WARN and no FAIL gives `partial` with the WARN section names.
  The writer's no-op paths keep their existing tests.
- `_run_mark_partial`: a valid name is appended; an invalid name (space, quote, newline,
  uppercase) returns 1 and leaves the file unchanged; no tmpdir returns 0 and writes
  nothing.
- Each of the 15 sites: driving the step's failure through its existing mock or seam
  produces its step name in `partial_steps`. One test per run function asserts the full
  list for a run where every site degrades.
- `_run_or_exit`: a failing mapped function writes one `failed` entry; a failing
  `run_update` writes exactly one entry; a second run function failing before its tmpdir
  setup writes nothing (stale-tmpdir guard); an unmapped function writes nothing.
- state-ledger pytest: status and history with `outcome` present (each value), absent,
  and malformed (non-string, unknown value), the last falling back to `success`.

## Requirements

- **R1.** `[PR1]` `_ledger_write_run_entry` writes `"outcome"`: `"failed"` when its exit code argument is non-zero, else `"partial"` when `${_DOTFILES_RUN_TMPDIR}/partial_steps` is non-empty, else `"ok"`.
- **R2.** `[PR1]` `_ledger_write_run_entry` writes `"partial_steps"` as a JSON array of the lines of `${_DOTFILES_RUN_TMPDIR}/partial_steps` in file order, `[]` when the file is absent or empty, for every outcome.
- **R3.** `[PR1]` `_run_mark_partial STEP` appends `STEP` plus a newline to `${_DOTFILES_RUN_TMPDIR}/partial_steps` when `STEP` matches `^[a-z0-9.-]+$`, returns 1 and writes nothing otherwise, and returns 0 writing nothing when `_DOTFILES_RUN_TMPDIR` is unset or not a directory.
- **R4.** `[PR1]` `run_developer_or_ansible` passes `0` to `_ledger_write_run_entry` and marks `github-cli` when `install_github_cli_linux` fails.
- **R5.** `[PR1]` These sites call `_run_mark_partial` with these names when they warn and continue: `run_setup_user` — `bats-parallel` (install_bats rc 2), `ai-config` (setup_ai_config rc 2), `terraform-skill` (install_terraform_skill rc 2), `cheat-sh-binary`, `cheat-sh-completion`, `claude-plugins` (provision_claude_plugins rc other than 0 and 1), `git-hooks` (install_git_hooks_all_repos rc 1 or 2), `renovate-agent`, `ledger-drift-agent`, `pyenv-rehash-hook`; `run_setup_or_developer` — `ubuntu-packages` (install_ubuntu_packages rc other than 0 and 1), `plugin-node-paths` (repair_plugin_node_paths rc 1), `cargo-tools`, `aws-cli`; `run_developer_or_ansible` — `github-cli`.
- **R6.** `[PR1]` `update` entries have `outcome` `"partial"` when `_fail` is 0 and `_warn` is above 0, with `partial_steps` the WARN section names in `_UPDATE_SECTION_ORDER` order.
- **R7.** `[PR1]` `_run_or_exit` unsets `_DOTFILES_RUN_TMPDIR` before calling its function.
- **R8.** `[PR1]` On a non-zero return from a mapped run function, `_run_or_exit` calls `_ledger_write_run_entry <run_type> <rc>` before `exit`, unless `${_DOTFILES_RUN_TMPDIR}/ledger_written` exists; `_ledger_write_run_entry` creates that marker after writing; a failed ledger write never changes the exit code `_run_or_exit` exits with.
- **R9.** `[PR2]` state-ledger `cmd_status` and `cmd_history` print `outcome.upper()` when `outcome` is one of `ok`, `partial`, `failed`, and otherwise `OK`/`FAILED` from `success`.
- **R10.** `[PR2]` state-ledger README documents `outcome` and `partial_steps` and lists `recreate_ruby` in the `run_type` table.
- **R11.** `[PR1]` The `pyproject.toml` `test-lint` comment no longer claims any repo's CI installs `requirements-ci.txt`, and the backlog row for it is removed.
- **V1.** After PR1 merges, the next real `-t update` on `claude` writes an entry whose `outcome` and `partial_steps` match that run's summary table (`ledger history` plus the entry JSON).
- **V2.** dotfiles CI bash coverage stays at or above 91%.
- **N1.** No change to state-ledger `_validate_entry`, and no new field is required of entries: entries without `outcome` stay valid.
- **N2.** `success` keeps the meaning "the run function returned exit 0" for every run type.
- **N3.** No `failure_stage` field for run types other than `update`.
- **N4.** `run_brew_install` and `run_mas_install` still write no ledger entry.
- **N5.** No run function's return code or abort-versus-continue behaviour changes.
