# Ledger run outcome: record partial and failed dotfiles runs

- **Status:** Draft (revised after Step 8 round 1)
- **Date:** 2026-11-04
- **Repos:** dotfiles (writer, callers, dispatcher), state-ledger (display, README)
- **Backlog row:** "setup/developer ledger entries record success over failed steps"

## Problem

Each dotfiles run function writes a state-ledger entry through
`_ledger_write_run_entry RUN_TYPE EXIT_CODE` (`lib/update_summary.sh:588`), whose
`success` field is `exit_code == 0`. Measured 2026-11-04 against `origin/master`
`30f2f40c`:

1. **Partial runs read as clean.** `run_setup_user` (`lib/workflows.sh:420`) and
   `run_setup_or_developer` warn and continue past failed steps, then pass a literal `0`.
   A run that could not install aws-cli, cargo tools or the git hooks is recorded
   `success: true`, shown as `OK`.
2. **Some failures are not even warned.** `clone_personal_repos` (`lib/developer.sh:697`)
   runs seven unchecked `git clone`s, `setup_vim_plugins` (`lib/developer.sh:380`) ignores
   its `curl`, and the cheat.sh block in `run_setup_user` runs two unchecked `apt` lines.
   Each is called bare, so its failure reaches neither the console summary nor the ledger.
3. **Run types disagree.** `run_developer_or_ansible` passes `${_gh_rc}` (2 on a gh
   partial), so its partial is `success: false`, against state-ledger's README ("`true`
   if the run function returned exit 0"); `update` maps WARN to `true`.
4. **Hard failures leave no entry.** Every `|| return 1` in a run function exits before
   `_ledger_write_run_entry`, so a run that died writes nothing and the machine's last
   entry still reads `OK`.

Population: `lib/workflows.sh` lines 420-667 (the run functions that write entries), the
two `lib/developer.sh` functions above, and `lib/update_summary.sh`. `run_brew_install`
and `run_mas_install` write no entry today and stay out of scope (N4).

**Corrected premise.** The backlog row also named the two recreate workflows; they are
correct as written (their literal `0` is reached only on success) and change only through
defect 4.

**Readers.** The operator works at the console. The ledger is read **after a failure**:
by the operator, or by an agent asked to hunt one down, who reads `ledger history` and the
entry JSON. Measured on the live ledger (947 dotfiles entries; `update` 778, `setup` 36,
`developer` 30, `setup_user` 21, `recreate_venv` 64, `recreate_ruby` 18): `ledger status`
shows only the latest entry per machine (`_latest_entry_for` keys on `(tool, entity_id)`),
which on all 10 machines is an `update`; `ledger history` prints `ts STATUS run=<id8>`
with no run type or steps. So for a hunt to find a partial setup, `history` has to name
the run type and the degraded steps. `cmd_drift` also reads the latest entry's
`started_at`; failed entries now count as fresh, which is immaterial because `update`
already writes on FAIL.

## Design

### 1. Schema

Every dotfiles run entry gains two fields:

| Field           | Type                                | Meaning                                                                                     |
| --------------- | ----------------------------------- | ------------------------------------------------------------------------------------------- |
| `outcome`       | `"ok"` \| `"partial"` \| `"failed"` | `failed` when the exit code is non-zero; else `partial` when any step was marked; else `ok` |
| `partial_steps` | array of strings                    | Step names marked during the run, in marking order; `[]` when none                          |

`success` keeps its documented meaning, `exit_code == 0`. Entries written before this
change have no `outcome` and are read by `success` as today. `partial_steps` is kept on a
`failed` entry: steps that degraded before the abort are facts about the run.

The writer reads the marks file line by line and keeps only lines matching
`^[a-z0-9.-]+$`, so a malformed line can never break the hand-built JSON
(`cmd_write`'s `json.loads` sits outside its try, so malformed JSON would be lost).

### 2. Marking partial steps: one helper, warn and mark together

`_run_warn_partial STEP MESSAGE` calls `log_warn "${MESSAGE}"` and appends `STEP` to
`${_DOTFILES_RUN_TMPDIR}/partial_steps`. `STEP` must match `^[a-z0-9.-]+$`: otherwise it
returns 1 having logged nothing and written nothing, so a bad call is a visible test
failure. With `_DOTFILES_RUN_TMPDIR` unset or not a directory it still logs, writes
nothing and returns 0.

Every warn-and-continue site in the three run functions uses it in place of its bare
`log_warn` (or `printf … >&2`). A lint in `make lint` fails on any `log_warn` call inside
the bodies of `run_setup_user`, `run_setup_or_developer` and `run_developer_or_ansible`,
so a future degrade-and-continue site cannot skip the mark silently. The sites and names
are listed in R5.

`run_developer_or_ansible` then passes `0`, since it returns 0 on a gh partial.

### 3. Silent sites report failure

- `clone_personal_repos` attempts every clone as today and returns 1 if any clone failed
  (0 otherwise). `run_developer_or_ansible` marks `personal-repos` on 1.
- `setup_vim_plugins` returns the `curl` status when it downloads `plug.vim`
  (0 otherwise). `run_setup_or_developer` marks `vim-plugins` on non-zero.
- The cheat.sh `apt update` / `apt install curl` lines in `run_setup_user` mark
  `cheat-sh-deps` when either fails and continue to the fetches as today.

None of these becomes an abort: each caller continues exactly as now (N5).

### 4. `update`

`_ledger_write_dotfiles_entry` passes the WARN result as well as `_fail`: `outcome` is
`partial` when `_fail == 0` and `_warn > 0`, and `partial_steps` holds the WARN section
names in `_UPDATE_SECTION_ORDER` order (all 27 names match the step pattern).

### 5. Recording hard failures

`_run_or_exit` in `setup_env.sh`, the single dispatcher:

- unsets `_DOTFILES_RUN_TMPDIR` before calling the function. Unreachable today (a failed
  `X=$(mktemp …) || return 1` already assigns `""`), kept because the failure it guards
  is destructive: a reused `run_id` makes `_write_entry`'s `write_text` overwrite the
  earlier run's entry;
- on a non-zero return calls `_ledger_write_run_entry <run_type> <rc> || true` before
  `exit "${_ec}"`, for `run_setup_user` (`setup_user`), `run_setup_or_developer`
  (`setup`), `run_developer_or_ansible` (`developer`), `run_recreate_venv`,
  `run_recreate_ruby`. `run_update` is not mapped: it writes its own entry in
  `_update_summary`, and its only earlier return is the tmpdir setup, after which no
  entry can be written anyway.

`ledger_write_entry` (`lib/workflows.sh`) runs `ledger write` under
`GIT_SSH_COMMAND="$(_git_ssh_opts)"` (`BatchMode=yes`, `ConnectTimeout=10`). The
failure-path write is most likely to run when ssh is already broken (the hard-abort sites
include `clone_or_update_dotfiles` and `setup_ai_config`), and ledger's git
`pull --rebase`/`push` has no batch mode or timeout of its own; bounding it here also
bounds today's `update` FAIL path.

Not covered: a signal, and an `exit` inside a run function. No `failure_stage` for
non-`update` types (N3): the console names the failing step, and the run type plus
`outcome: failed` tells a hunt where to look.

### 6. state-ledger (separate PR, coordinated with its owning session)

- `cmd_history` prints, per entry, the run type (`run_type` when present), the status
  (`outcome.upper()` when `outcome` is one of `ok`/`partial`/`failed`, else
  `OK`/`FAILED` from `success`) and, when non-empty, `partial_steps` joined with `,`.
- `cmd_status` prints the latest entry's run type beside its status, with the same
  status rule.
- README documents `outcome` and `partial_steps` and adds the missing `recreate_ruby`
  row. `_validate_entry` is unchanged (N1).

The dotfiles PR does not depend on it: the current display reads `success`, which stays
correct.

### 7. Folded in: `pyproject.toml` comment

`pyproject.toml:150` ("Must match what five repos' CI installs. Exported to
requirements-ci.txt.") is rewritten: the group is the full local/dev set rendered to
`requirements-ci.txt`, and consumers install the `ci-*` renderings. Its backlog row is
removed.

## Testing

- Writer: one case per outcome with exact `outcome`, `partial_steps` and `success`; a
  failed run keeps its earlier marks; a marks file containing an invalid line yields only
  the valid names; `update` with WARN and no FAIL gives `partial` with the WARN names.
- `_run_warn_partial`: valid name logs and appends; invalid name (space, quote, newline,
  uppercase) returns 1 and leaves the file unchanged; no tmpdir logs and writes nothing.
- Lint: a fixture run function with a bare `log_warn` fails the lint; the real
  `lib/workflows.sh` passes it.
- Each R5 site: driving its failure through the existing mock or seam yields its name in
  `partial_steps`; one test per run function asserts the full list when every site
  degrades.
- Silent sites: `clone_personal_repos` returns 1 when one of several clones fails and
  still attempts the rest; `setup_vim_plugins` returns the `curl` status; each caller
  still continues.
- `_run_or_exit`: a failing mapped stub writes one `failed` entry with the given rc;
  `run_update` failing writes no dispatcher entry; an unmapped stub writes none. The
  stale-tmpdir case uses a stub that returns 1 with a prior run's tmpdir (with
  `started_at`) still exported, and asserts the ledger mock received no second write and
  the prior run's entry is unchanged — a positive control that fails if the unset is
  removed.
- `ledger_write_entry`: the mock `ledger` records `GIT_SSH_COMMAND` equal to
  `_git_ssh_opts`'s output.
- state-ledger pytest: history and status with `outcome` present (each value), absent,
  and malformed (non-string, unknown value); `partial_steps` empty and non-empty.

## Requirements

- **R1.** `[PR1]` `_ledger_write_run_entry` writes `"outcome"`: `"failed"` when its exit code argument is non-zero, else `"partial"` when at least one valid name is in `${_DOTFILES_RUN_TMPDIR}/partial_steps`, else `"ok"`.
- **R2.** `[PR1]` `_ledger_write_run_entry` writes `"partial_steps"` as a JSON array of the lines of `${_DOTFILES_RUN_TMPDIR}/partial_steps` that match `^[a-z0-9.-]+$`, in file order, `[]` when there are none, for every outcome.
- **R3.** `[PR1]` `_run_warn_partial STEP MESSAGE` calls `log_warn MESSAGE` and appends `STEP` to `${_DOTFILES_RUN_TMPDIR}/partial_steps` when `STEP` matches `^[a-z0-9.-]+$`; it returns 1 having logged and written nothing for any other `STEP`; with `_DOTFILES_RUN_TMPDIR` unset or not a directory it logs, writes nothing and returns 0.
- **R4.** `[PR1]` `run_developer_or_ansible` passes `0` to `_ledger_write_run_entry`.
- **R5.** `[PR1]` These sites call `_run_warn_partial` with these names: `run_setup_user` — `bats-parallel` (install_bats rc 2), `ai-config` (setup_ai_config rc 2), `terraform-skill` (install_terraform_skill rc 2), `cheat-sh-deps` (either cheat.sh `apt` line fails), `cheat-sh-binary`, `cheat-sh-completion`, `claude-plugins` (provision_claude_plugins rc other than 0 and 1), `git-hooks` (install_git_hooks_all_repos rc 1 or 2), `renovate-agent`, `ledger-drift-agent`, `pyenv-rehash-hook`; `run_setup_or_developer` — `ubuntu-packages` (install_ubuntu_packages rc other than 0 and 1), `plugin-node-paths` (repair_plugin_node_paths rc 1), `cargo-tools`, `aws-cli`, `vim-plugins` (setup_vim_plugins non-zero); `run_developer_or_ansible` — `github-cli`, `personal-repos` (clone_personal_repos rc 1).
- **R6.** `[PR1]` `make lint` fails when any `log_warn` call appears inside the bodies of `run_setup_user`, `run_setup_or_developer` or `run_developer_or_ansible`.
- **R7.** `[PR1]` `clone_personal_repos` attempts every clone and returns 1 when any `git clone` failed, 0 otherwise; `setup_vim_plugins` returns the `curl` exit status when it downloads `plug.vim`, 0 otherwise.
- **R8.** `[PR1]` `update` entries have `outcome` `"partial"` when `_fail` is 0 and `_warn` is above 0, with `partial_steps` the WARN section names in `_UPDATE_SECTION_ORDER` order.
- **R9.** `[PR1]` `_run_or_exit` unsets `_DOTFILES_RUN_TMPDIR` before calling its function.
- **R10.** `[PR1]` On a non-zero return from `run_setup_user`, `run_setup_or_developer`, `run_developer_or_ansible`, `run_recreate_venv` or `run_recreate_ruby`, `_run_or_exit` calls `_ledger_write_run_entry <run_type> <rc> || true` and then exits with the function's own exit code; it writes nothing for `run_update` or any unmapped function.
- **R11.** `[PR1]` `ledger_write_entry` runs `ledger write` with `GIT_SSH_COMMAND` set to `_git_ssh_opts`'s output.
- **R12.** `[PR2]` state-ledger `cmd_history` prints each entry's run type, its status (`outcome.upper()` when `outcome` is one of `ok`/`partial`/`failed`, else `OK`/`FAILED` from `success`) and its non-empty `partial_steps`; `cmd_status` prints the latest entry's run type and status by the same rule.
- **R13.** `[PR2]` state-ledger README documents `outcome` and `partial_steps` and lists `recreate_ruby` in the `run_type` table.
- **R14.** `[PR1]` The `pyproject.toml` `test-lint` comment no longer claims any repo's CI installs `requirements-ci.txt`, and its backlog row is removed.
- **V1.** After PR1 merges, the next real `-t update` on `claude` writes an entry whose `outcome` and `partial_steps` match that run's summary table.
- **V2.** dotfiles CI bash coverage stays at or above 91%.
- **N1.** No change to state-ledger `_validate_entry`, and no field becomes required: entries without `outcome` stay valid.
- **N2.** `success` keeps the meaning "the run function returned exit 0" for every run type.
- **N3.** No `failure_stage` field for run types other than `update`.
- **N4.** `run_brew_install` and `run_mas_install` still write no ledger entry.
- **N5.** No run function's exit code changes, and no step that continues today aborts.

## Multi-Lens Review

Reviewed at commit: `be156684` (Step 7 self-review commit, before Step 8 dispatch)

### Goal-Fit

Finding: `partial_steps` had no reader and the relabel did not reach the operator: `ledger status` shows only the latest entry per machine, `ledger history` prints no run type or steps. Proposed deleting the stale-tmpdir unset (unreachable: a failed `X=$(mktemp …) || return 1` assigns `""`, probe `rc=1 X=[]`) and the `ledger_written` marker (leave `run_update` unmapped instead). Missed reader: `cmd_drift` reads `started_at`. Premise verified at `be156684`.
Assumption: the operator reads the ledger to judge a setup run rather than only the console.
Disposition: Addressed. Operator: "I will check the ledger after a failure or ask you to hunt it down. My main interaction is at the console." Readers rewritten around the post-failure hunt; `history` prints run type, status and steps, `status` gains the run type but stays latest-per-machine (revised R12); marker dropped and `run_update` unmapped (revised R10); `cmd_drift` named. The unset is kept (operator choice, see Risk).

### Ergonomics

Finding: the same display gap, measured on the live ledger (all 10 machines' latest entry is `update`; `-t setup` masks `setup_user` within seconds). A future warn-and-continue site can forget the mark; proposed one warn-and-mark helper plus a lint. Silent-ignore sites (`clone_personal_repos`, `setup_vim_plugins`, cheat.sh `apt`) record `ok`. The stale-tmpdir test was vacuous.
Assumption: which command the operator runs after `-t setup`.
Disposition: Addressed. Operator answers: display "History + status by type", narrowed after the console answer to `history` showing type, status and steps and `status` showing the type; silent sites "Bring in". Helper `_run_warn_partial` and its lint added; stale-tmpdir test is now a stub with a positive control.

### Risk

Finding: the failure-path write runs ledger's git with no BatchMode or timeout, most likely exactly when ssh is broken; proposed `GIT_SSH_COMMAND="$(_git_ssh_opts)"` on `ledger_write_entry`. Keep the stale-tmpdir unset, because a reused `run_id` would overwrite the previous entry. Marker semantics on a spooled write. Writer should re-filter step names. All 27 `_UPDATE_SECTION_ORDER` names match the pattern.
Assumption: no prompt is possible on the failure path; refuted if `~/.ssh/github` carries a passphrase (`ssh-keygen -y -P '' -f ~/.ssh/github >/dev/null 2>&1; echo $?` per machine, operator to run).
Disposition: Addressed. Operator chose "Keep, stub-tested" for the unset. `GIT_SSH_COMMAND` bound, writer re-filter added, marker removed so its semantics no longer apply. Passphrase check not yet run; the bound applies whichever way it answers.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.
