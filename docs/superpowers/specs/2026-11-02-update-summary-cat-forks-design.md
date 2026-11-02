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

In the table `f` abbreviates the full quoted path, written as the file's other `$(<` sites write it:
`$(<"${_DOTFILES_RUN_TMPDIR}/status_${_section}")` (compare `lib/helpers.sh:1042`).

The braces in `{ x=$(<"…"); } 2>/dev/null` are load-bearing and look redundant: `x=$(<"…") 2>/dev/null`
keeps every value (rc 1 still reaches the `||`) and leaks only the error to stderr, because a redirect on
the assignment does not reach the substitution's open. The first braced site carries a one-line comment
saying so, and V2 mutates exactly that simplification.

`cat "${_fail_result_file}" > "…/result_${_section}"` (line 346) stays. It is a copy, not a substitution,
and runs only on the FAIL path.

### Tests (TDD: characterisation first)

New `@test`s in `tests/setup_env/update_summary.bats`, written before the edit and green on today's code.
Each builds a real `_DOTFILES_RUN_TMPDIR` fixture and calls the real function:

Every stderr assertion uses `run --separate-stderr` (the file already sets `bats_require_minimum_version
1.5.0`), since plain `run` merges stderr into `$output`. The ledger tests reuse `_seed_machine_id` and
`_mk_ledger_capture`. Each new test unsets `LEDGER_BIN` (an exported one overrides the capture mock) and puts any
stub directory under `BATS_TEST_TMPDIR`.

1. `_update_status_is_fail` with no `status_<s>` file: rc 1 and empty stderr.
2. `_update_status_is_fail` with `status_<s>` holding `FAIL` followed by two newlines: rc 0.
3. `_ledger_write_run_entry update 0` with `started_at` and the machine-id present and `start_epoch`, `run_id`
   and `git_sha` absent, and a test-local `python3` stub that exits 1 first on `PATH` (`tests/mocks/` has no
   `python3`, so without it the real one prints a uuid): the entry (captured from the ledger mock) carries
   `"run_id": "unknown"` and `"git_sha": "unknown"`, its `duration_seconds` is at least `$(date +%s) - 60`
   (the epoch-0 fallback), and stderr is empty.
4. The same with those three files present but empty: the entry carries `"run_id": ""` and
   `"git_sha": ""`, not the fallbacks.
5. `_update_summary` with `status_brew` holding `OK` and no `result_brew`: `$output` contains the row
   matching `\[OK\][[:space:]]+brew([[:space:]]|$)`, and stderr is empty.

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
- **R3.** `[PR1]` Each `||` fallback at lines 598–604 is kept with its current value:
  `date -u +%Y-%m-%dT%H:%M:%SZ`, `0`, the `python3` uuid then `unknown` chain, and `unknown`.
- **R4.** `[PR1]` `tests/setup_env/update_summary.bats` gains the five characterisation tests in the Design,
  and they pass on the pre-change `lib/update_summary.sh`.
- **R5.** `[PR1]` The first `{ x=$(<"…"); } 2>/dev/null` site carries a one-line comment stating that the
  braces are load-bearing because `x=$(<f) 2>/dev/null` does not silence the open error.
- **V1.** In a `git archive` copy, run the old and new `lib/update_summary.sh` functions
  (`_update_status_is_fail`, `_update_record_end`, `_ledger_write_run_entry`, `_update_summary`) over the
  same cells. A cell is one function, one input file it reads, and one state of that file: missing, empty,
  `FAIL` followed by two newlines, `OK`, `SKIP`, or unreadable (mode 000). Exactly one file departs from
  valid content per cell; every other input the function reads is present and readable. Compare stdout, rc
  and the file listing and contents of `_DOTFILES_RUN_TMPDIR` after the call exactly. Compare stderr exactly,
  except in the unreadable cell, where only whether it is empty is compared (`cat: f: Permission denied` and
  `bash: line N: f: Permission denied` are the same event in different words, and only one file is
  unreadable). The plan lists every cell; the harness prints `COMPARED: <n>, DIVERGING: <m>`. Pass: n equals
  the plan's cell count and m is 0. The PR body records the line.
- **V2.** In a `git archive` copy of the PR head, apply the realistic regression to one site in each group:
  move `2>/dev/null` off the enclosing `[[ ]]` at 148, and replace `{ x=$(<"…"); } 2>/dev/null` with
  `x=$(<"…") 2>/dev/null` at one of 599, 602 or 604 (598's mutant cannot go red: the function returns early
  without `started_at`, which test 3 must create) and at 750. The matching characterisation test goes red. The PR
  body records each mutation and its red test.
- **V3.** On the Studio (`ssh studio`, bare environment as in `CLAUDE.md`), one before/after pair of the 11
  files in the Problem table at `bats --jobs 16`, with `/usr/bin/time` and `uptime`. The PR body reports
  user, sys and wall for each run. The P1 "bats process-spawn cost" row closes only if the after run's
  user+sys is below the before run's; otherwise it stays open carrying both figures. The `claude` figure is
  the premise A/B above and is not re-run; the CI `test-macos-shard` legs are not used (the same leg ranged
  150–439 s across the last four green master runs).
- **V4.** `make test` passes at the PR head, every `test-shard` and `test-macos-shard` leg passes, and bash
  coverage stays at or above 91%.
- **N1.** No file changes outside `lib/update_summary.sh`, `tests/` and `docs/`.
- **N2.** No `python3` call is removed or added.
- **N3.** No new shell function in `lib/`.
- **N4.** No lint, ratchet or guard on `$(cat` usage.
- **N5.** `tests/bats-weights.tsv` does not change.

## Multi-Lens Review

Reviewed at commit: `f3b0b15d` (Step 7 self-review commit, before Step 8 dispatch)

### Goal-Fit

Finding: Worth building as scoped. `strace` confirmed `x=$(<f)` makes 0 forks against 1 for `$(cat f)` on bash
5.3.9, and the Studio's Homebrew bash (what CI's macOS legs install) is 5.3.20. The blind `sed` substitution
the premise A/B measured is not shippable: it leaks `No such file` at 148, 598–604 and 750, so R2's rework is
necessary. Reads-it test: V1 has no named consumer and passes on zero comparisons (`DIVERGING: 0` with nothing
compared); pin a comparison count and record it in the PR body. V2 passes the test. V3 fails it: no
threshold, so no result changes a decision; either name the decision it feeds or cut it to the Studio run as
data. The honest consumer is the PR's `test-macos-shard` leg durations against master's last run.
Assumption: that the saving reaches the macOS CI shards. Settled by comparing `test-macos-shard` leg
durations on the PR with the last master run.
Disposition: Addressed (operator, 2026-11-02) — V1 compares unreadable-case stderr by emptiness and
prints `COMPARED: <n>, DIVERGING: <m>` with n > 0; V3 is now the PR's macOS shard legs plus one Studio pair,
as data.

### Ergonomics

Finding: No design issue. All five tests were written in an archive copy with existing helpers
(`_seed_machine_id`, `_mk_ledger_capture`, `run --separate-stderr`; the file already requires bats 1.5.0) and
pass before and after the new forms. Probed on bash 5.3.9, 3.2.57 and 5.3.20: identical rc and value for
missing, empty, trailing-newline and mode-000 files; `x=$(< f 2>/dev/null)` still prints `No such file` on
both 3.2 and 5. Maintainability trap: a maintainer "simplifying" `{ x=$(<f); } 2>/dev/null || …` to
`x=$(<f) 2>/dev/null || …` keeps every value and leaks only stderr; add a one-line comment that the braces
are load-bearing, and make that the V2 mutation. Apparatus: test 3's `"<uuid or unknown>"` is a disjunction
(the real `python3` runs; `tests/mocks/` has none), so pin one branch with a failing `python3` stub and
assert `"unknown"`; "duration from epoch 0" needs a concrete bound (`>= $(date +%s) - 60`); spell the paths
quoted, `$(<"${_DOTFILES_RUN_TMPDIR}/…")`, as `lib/helpers.sh:1042` does; test 5 should pin `[OK]` and the
section name in the row.
Assumption: none on correctness (probed on all three bashes); the only uncertain one is whether the CPU saving
exists on the macOS shards, which V3 measures.
Disposition: Addressed (operator, 2026-11-02) — R5 adds the load-bearing-braces comment and V2 mutates that
simplification; test 3 pins `unknown` with a failing `python3` stub and bounds the duration; test 5 pins the
`[OK]` brew row under `run --separate-stderr`; paths are spelled quoted.

### Risk

Finding: Design sound; V1 cannot pass as written. `cat` and `$(<)` word the unreadable-file error differently
(`cat: u: Permission denied` against `bash: line 1: u: Permission denied`), and the seven unguarded sites sit
behind `[[ -f ]]`, which a mode-000 file passes, so a byte comparison of stderr always diverges. Compare rc
and stderr-emptiness for that case, and require a non-zero comparison count. Probes on all three bashes:
values and fallback firing match for missing, unreadable, empty and `FAIL\n\n`; the only divergence is a
directory in place of a file (bash 5 `$(<dir)` gives rc 0 and empty), unreachable because only
`_dotfiles_run_tmpdir_setup` writes those files. `set -e` and ERR traps behave the same, and no caller or test
reads `cat`'s stderr text. Test 5 needs `run --separate-stderr` and an exact row.
Assumption: no uncertain assumption found.
Disposition: Addressed (operator, 2026-11-02) — V1 as in Goal-Fit; test 5 as in Ergonomics.

### Round 2

Reviewed at commit: `b0763bed` (round-1 dispositions applied). All three lenses re-ran.

#### Goal-Fit (round 2, `b0763bed`)

Finding: Still worth building; the 13 sites and line numbers are unchanged since `a2539a4e`. V2's "one of
598–604" admits 598, whose mutant cannot go red: the function returns early without `started_at`, which test 3
must seed. V3 fails the reads-it test: the P1 row closes whatever it shows, and V3(a) is noise (the same
`test-macos-shard` leg ranged 150–439 s across the last four green master runs), so drop (a) and let (b), the
Studio pair, decide whether the P1 row closes. V1's `COMPARED > 0` passes with n = 1: enumerate the
function × state cells and pin `COMPARED == N`. Apparatus: lines 336 and 439 steer early return and files
written, not stdout, so V1 should also diff `_DOTFILES_RUN_TMPDIR` after each call.
Assumption: that `$(<f)` saves real CPU on the macOS legs (Homebrew bash 5 under bats); settled by V3(b).
Disposition: Addressed (operator, 2026-11-02) — V2 names 599, 602 or 604; V3 is the Studio pair alone and
decides whether the P1 row closes; V1 enumerates cells, pins `COMPARED` to the plan's count and diffs
`_DOTFILES_RUN_TMPDIR` after each call. No round 3 (operator): the remaining findings are apparatus.

#### Ergonomics (round 2, `b0763bed`)

Finding: No design issue. Tests 3 and 5 written and run as specified: with the `python3` stub the entry carries
`"run_id": "unknown"`, without it a real uuid (so the stub is needed); line 602 is the only `python3` in the
function. Test 5's regex matches the real padded row (`[OK]   brew                 $`) and a no-`status_brew`
control fails it. Apparatus: put the stub dir under `BATS_TEST_TMPDIR` (not `_mk_ledger_capture`'s leaking
`mktemp -d` pattern); add `unset LEDGER_BIN` to the new tests, since an exported one overrides the capture mock.
Assumption: no uncertain assumption found on this lens.
Disposition: Addressed (operator, 2026-11-02) — new tests unset `LEDGER_BIN` and keep stub dirs under
`BATS_TEST_TMPDIR`.

#### Risk (round 2, `b0763bed`)

Finding: V1's emptiness rule can hide a real regression. With `status_brew` and `result_brew` both mode 000,
old, new and a 750 brace-drop mutant all write stderr (3, 3 and 4 lines), so emptiness matches and V1 reports
`DIVERGING: 0`; with only `result_brew` unreadable, old and new write 0 lines and the mutant 1, so V1 catches
it. Fix: one unreadable file per case, or strip the `cat: ` and `<file>: line N: ` prefixes and compare the
remaining lines exactly. V2 probed: 148 → test 1 red; 599, 602, 604 → test 3 red (602 on the stderr
assertion alone, values intact); 750 → test 5 red; 598 → none red. Name the sites 599, 602 or 604.
Assumption: no uncertain assumption found.
Disposition: Addressed (operator, 2026-11-02) — V1 makes exactly one file unreadable per cell; V2 sites as
in Goal-Fit.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.
