# update_summary.sh: read status files without forking cat

- **Date:** 2026-11-02
- **Backlog row:** "`_update_record_*` forks `cat` and `python3` per section" (P3 tech-debt), option B of part
  2b (`docs/superpowers/specs/2026-11-02-run-update-flag-scoping-design.md`). The P1 row "bats process-spawn
  cost" closes when this ships. The operator chose scope 1 of three: `lib/update_summary.sh` only.

## Problem

`lib/update_summary.sh` reads its per-section state files (`status_<s>`, `result_<s>`, `detail_<s>`,
`pre_<s>`, and the run's `started_at`, `start_epoch`, `run_id`, `git_sha`) with `$(cat "…")` at 13 sites.
Each one forks a subshell and execs `cat`. `_update_summary` alone reads `status_` and `result_` for all 28
`_UPDATE_SECTION_ORDER` names, and every `run_update` test prints the summary, scoped or not.

**Premise check, 2026-11-02, on `claude`:**

- `strace -f -e execve` over one flagless macOS-variable `run_update` test (the section-coverage pin): 706
  successful `execve` calls, 72 of them `cat`.
- A/B timing in two `git archive` copies of `a2539a4e`, the only difference being `$(cat …)` replaced by
  `$(<…)` in `lib/update_summary.sh`:

  | Population                                                           | Before CPU (user+sys) | After CPU       | Saving                          |
  | -------------------------------------------------------------------- | --------------------- | --------------- | ------------------------------- |
  | 26 flagless full-run tests, `bats --jobs 8`, 3 pairs                 | ~60.7 s               | ~55.1 s         | ~0.2 s per test                 |
  | 11 heaviest `run_update` files, 977 tests, `bats --jobs 16`, 2 pairs | 526.5 / 531.8 s       | 493.2 / 492.9 s | ~36 s (~7%), wall ~6.5 s (~10%) |

  Most of the saving is `sys`. Both copies failed the same 3 tests (674, 704, 705), which need a `.git` the
  archive copies lack.

**Population.** The measurements cover one machine (`claude`, bash 5.3.9, load 4–10) and the 11 files that
call `run_update` or `_update_summary` most. The claim is about the same files on every runner. macOS is
unmeasured: bash 3.2 forks a subshell for `$(<file)` but skips the `exec`, and CI's macOS legs run Homebrew
bash 5. V3 measures the Studio.

**The row's `python3` half is misplaced.** The `run_id` uuid fallback in `_ledger_write_run_entry` does not
fire in a run, because `_dotfiles_run_tmpdir_setup` (`lib/workflows.sh`) writes `run_id` first. The
`python3` calls a run actually makes (about 4) are the Claude-plugin helpers in `lib/workflows.sh`: three
JSON parses and one `realpath`. Removing them needs `jq` or platform-specific `realpath`/`uuidgen`
branches, and their cost on `claude` is mostly the pyenv shim (option C). This spec leaves them alone.

No spec or ADR proposed or rejected this change before. `$(<file)` is already used in `lib/`.

## Design

### Semantics, probed with bash 5.3.9

- `$(<f)` strips trailing newlines exactly as `$(cat f)` does.
- On a missing or unreadable file, `$(<f)` fails with rc 1 and prints `No such file or directory` (or the
  permission error) to stderr **even when written `$(< f 2>/dev/null)`**. A redirect on the enclosing
  command silences it: `{ x=$(<f); } 2>/dev/null` and `[[ "$(<f)" == … ]] 2>/dev/null` are both silent.
- An existing empty file yields an empty string and rc 0 for both forms.

### The 13 sites

| Line | Function                  | Today                                                            | After                                                                                        |
| ---- | ------------------------- | ---------------------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| 148  | `_update_status_is_fail`  | `[[ "$(cat f 2>/dev/null)" == "FAIL" ]]`                         | `[[ "$(<f)" == "FAIL" ]] 2>/dev/null`                                                        |
| 336  | `_update_record_end`      | `$(cat f)` behind `[[ -f ]]`                                     | `$(<f)`                                                                                      |
| 439  | `_update_record_end`      | `$(cat pre_…)` behind `[[ -f ]]`                                 | `$(<f)`                                                                                      |
| 598  | `_ledger_write_run_entry` | `$(cat started_at 2>/dev/null \|\| date -u …)`                   | `{ _started_at=$(<f); } 2>/dev/null \|\| _started_at=$(date -u …)`                           |
| 599  | `_ledger_write_run_entry` | `$(cat start_epoch 2>/dev/null \|\| printf '0')`                 | `{ _start_epoch=$(<f); } 2>/dev/null \|\| _start_epoch=0`                                    |
| 602  | `_ledger_write_run_entry` | `$(cat run_id 2>/dev/null \|\| python3 … \|\| printf 'unknown')` | `{ _run_id=$(<f); } 2>/dev/null \|\| _run_id=$(python3 … 2>/dev/null \|\| printf 'unknown')` |
| 604  | `_ledger_write_run_entry` | `$(cat git_sha 2>/dev/null \|\| printf 'unknown')`               | `{ _git_sha=$(<f); } 2>/dev/null \|\| _git_sha=unknown`                                      |
| 680  | `_ledger_write_run_entry` | `[[ "$(cat status_…)" == "FAIL" ]]` behind `[[ -f ]]`            | `$(<f)`                                                                                      |
| 691  | `_ledger_write_run_entry` | `$(cat result_…)` behind `[[ -f ]]`                              | `$(<f)`                                                                                      |
| 705  | `_ledger_write_run_entry` | `$(cat status_…)` behind `[[ -f ]]`                              | `$(<f)`                                                                                      |
| 749  | `_update_summary`         | `$(cat status_…)` after the missing-file `continue`              | `$(<f)`                                                                                      |
| 750  | `_update_summary`         | `$(cat result_… 2>/dev/null)`                                    | `{ _result=$(<f); } 2>/dev/null`                                                             |
| 795  | `_update_summary`         | `$(cat detail_…)` behind `[[ -f ]]`                              | `$(<f)`                                                                                      |

Line numbers are at `a2539a4e`. Line 598's fallback is unreachable today, because the function returns at
its top when `started_at` is absent. The rewrite keeps it, so the edit does not also change that.

`cat "${_fail_result_file}" > "…/result_${_section}"` (line 346) stays. It is a copy, not a substitution,
and runs only on the FAIL path.

### Tests (TDD: characterisation first)

New `@test`s in `tests/setup_env/update_summary.bats`, written before the edit and green on today's code.
Each builds a real `_DOTFILES_RUN_TMPDIR` fixture and calls the real function:

1. `_update_status_is_fail` with no `status_<s>` file: rc 1 and empty stderr.
2. `_update_status_is_fail` with `status_<s>` holding `FAIL` followed by two newlines: rc 0.
3. `_ledger_write_run_entry update 0` with `started_at` and the machine-id present and `start_epoch`, `run_id`
   and `git_sha` absent: the entry (captured from the ledger mock) carries `"run_id": "<uuid or unknown>"`,
   `"git_sha": "unknown"` and a duration computed from epoch 0, and stderr has no `No such file` line.
4. The same with those three files present but empty: the entry carries `"run_id": ""` and
   `"git_sha": ""`, not the fallbacks.
5. `_update_summary` with `status_<s>` present and `result_<s>` absent: the row prints and stderr has no
   `No such file` line.

The mutation control and the old/new differential are V2 and V1.

## Not chosen

- **A `read`-based helper.** `IFS= read -r -d '' var < f` forks nothing even on bash 3.2, but keeps trailing
  newlines where `$(…)` strips them, so every caller's comparisons change.
- **Section state in shell arrays.** Status lives in files on purpose: some writers run in subshells. A
  redesign for a speed gain.
- **`lib/workflows.sh` (7 sites) and `lib/linux_ubuntu.sh` (1).** Unmeasured install-path sites. Operator
  chose scope 1.
- **The `python3` calls.** See Problem.

## Requirements

- **R1.** `[PR1]` `lib/update_summary.sh` contains no `$(cat ` command substitution; the 13 sites read with
  `$(<…)` as in the Design table.
- **R2.** `[PR1]` Every site that passes `2>/dev/null` to `cat` today (lines 148, 598, 599, 602, 604 and 750
  at `a2539a4e`) stays silent on a missing file, through `{ …; } 2>/dev/null` or a `2>/dev/null` on the
  enclosing `[[ ]]`.
- **R3.** `[PR1]` Each `||` fallback at lines 598–604 is kept with its current value: `date -u
+%Y-%m-%dT%H:%M:%SZ`, `0`, the `python3` uuid then `unknown` chain, and `unknown`.
- **R4.** `[PR1]` `tests/setup_env/update_summary.bats` gains the five characterisation tests in the Design,
  and they pass on the pre-change `lib/update_summary.sh`.
- **V1.** In a `git archive` copy, run the old and new `lib/update_summary.sh` functions
  (`_update_status_is_fail`, `_update_record_end`, `_ledger_write_run_entry`, `_update_summary`) over the
  same fixture matrix: missing, empty, trailing-newline, unreadable (mode 000), and `FAIL`/`OK`/`SKIP`
  content. Compare stdout, stderr and rc. Pass: `DIVERGING: 0`.
- **V2.** In a `git archive` copy of the PR head, remove the stderr guard from one site in each group (148;
  one of 598–604; 750). The matching characterisation test goes red. The PR body records each mutation and
  its red test.
- **V3.** One before/after pair of the 11 files in the Problem table at `bats --jobs 16` with
  `/usr/bin/time` and `uptime`, on `claude` and on the Studio (`ssh studio`, bare environment as in
  `CLAUDE.md`). The PR body reports user, sys and wall for each run against the predicted ~36 s CPU on
  `claude`. No pass threshold; a macOS result with no saving is recorded as such.
- **V4.** `make test` passes at the PR head, every `test-shard` and `test-macos-shard` leg passes, and bash
  coverage stays at or above 91%.
- **N1.** No file changes outside `lib/update_summary.sh`, `tests/` and `docs/`.
- **N2.** No `python3` call is removed or added.
- **N3.** No new shell function in `lib/`.
- **N4.** No lint, ratchet or guard on `$(cat` usage.
- **N5.** `tests/bats-weights.tsv` does not change.
