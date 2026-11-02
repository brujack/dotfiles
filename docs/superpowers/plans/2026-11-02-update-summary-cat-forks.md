# update_summary.sh cat-forks Implementation Plan

> **Status: DONE** (dotfiles#420, merged 2026-11-02)

spec: docs/superpowers/specs/2026-11-02-update-summary-cat-forks-design.md

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Read `lib/update_summary.sh`'s state files with `$(<"…")` instead of forking `cat`, with identical values, exit codes, files written and (silent) stderr.

**Architecture:** Task 1 adds five characterisation tests to `tests/setup_env/update_summary.bats` that pass on today's code. Task 2 rewrites the 13 `$(cat …)` sites per the spec's Design table, adds the load-bearing-braces comment, and proves equivalence with a throwaway differential harness (V1) and three realistic mutations (V2).

**Tech Stack:** bash 5 (3.2 compatible), bats 1.13, GNU make.

## Global Constraints

- Only `lib/update_summary.sh`, `tests/` and `docs/` change (N1). No `python3` call added or removed (N2). No new function in `lib/` (N3). No lint or guard on `$(cat` (N4). `tests/bats-weights.tsv` unchanged (N5).
- Paths stay quoted: `$(<"${_DOTFILES_RUN_TMPDIR}/status_${_section}")`, as `lib/helpers.sh:1042` writes them.
- `$(< f 2>/dev/null)` does NOT silence a missing-file error on bash 3.2 or 5. Silence with `{ x=$(<"…"); } 2>/dev/null` or a `2>/dev/null` on the enclosing `[[ ]]`.
- Line 346 (`cat "${_fail_result_file}" > …`) stays.
- Mutation controls and the V1 harness run in a copy (`SNAP=$(git stash create)` if the tree is dirty, else `HEAD`; `D=$(mktemp -d) && git archive "$SNAP" | tar -x -C "$D"`), and the copy is removed with its path written out. Grep-prove every mutation landed.
- Every new test: `run --separate-stderr` for stderr assertions, `unset LEDGER_BIN`, stub directories under `BATS_TEST_TMPDIR`.

## Verification

- Session: `make test` exits 0 at the head; every `test-shard` and `test-macos-shard` leg passes; bash coverage ≥ 91% (V4).
- V1: `COMPARED: 72, DIVERGING: 0` over the cell list in Task 2.
- V2: each realistic mutation turns its matching test red (148 → test 1; 602 → test 3; 750 → test 5).
- V3 (orchestrator, after Task 2): the Studio before/after pair decides whether the P1 row closes.
- Edge cases: missing, empty, trailing-newline, unreadable files; bash 3.2 semantics were probed during review.

---

### Task 1: Characterisation tests

```yaml-task
id: 1
description: Add five tests pinning today's behaviour of _update_status_is_fail, _ledger_write_run_entry and _update_summary on missing, empty and trailing-newline state files
role: executor
model: sonnet
tdd: required
requirements: [R4]
acceptance:
  - cmd: bats tests/setup_env/update_summary.bats -f 'cat-forks characterisation'
    exit_code: 0
    stdout_match: 'ok 5 '
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [tests/setup_env/update_summary.bats]
depends_on: []
```

Append to `tests/setup_env/update_summary.bats`, after the existing `_ledger_write_run_entry` tests (helpers `_seed_machine_id` and `_mk_ledger_capture` are defined around line 1170–1215; `setup()` sets `_DOTFILES_RUN_TMPDIR="${BATS_TEST_TMPDIR}"` and `HOME="${BATS_TEST_TMPDIR}/home"`). Each test name starts `cat-forks characterisation:`.

1. `_update_status_is_fail` with no `status_brew`: `run --separate-stderr _update_status_is_fail brew`; `[ "$status" -eq 1 ]`; `[ -z "$stderr" ]`.
2. `printf 'FAIL\n\n' > "${_DOTFILES_RUN_TMPDIR}/status_brew"`; `run _update_status_is_fail brew`; `[ "$status" -eq 0 ]`.
3. `_ledger_write_run_entry` fallbacks: `unset LEDGER_BIN`; `export HOME="${BATS_TEST_TMPDIR}"`; `unset MACOS; export LINUX=1 UBUNTU=1`; write only `started_at` (`printf '2026-08-12T00:00:00Z\n'`) and `_seed_machine_id`; a stub dir `${BATS_TEST_TMPDIR}/py3stub` holding an executable `python3` that is `#!/usr/bin/env bash` + `exit 1`; `_ledger_dir="$(_mk_ledger_capture "${_cap}")"`; `PATH="${_ledger_dir}:${BATS_TEST_TMPDIR}/py3stub:${PATH}" run --separate-stderr _ledger_write_run_entry update 0`. Assert rc 0, `[ -z "$stderr" ]`, the capture contains `"run_id": "unknown"` and `"git_sha": "unknown"`, and the integer after `"duration_seconds": ` is `>= $(( $(date +%s) - 60 ))`.
4. Same set-up, but `start_epoch`, `run_id` and `git_sha` exist and are empty (`: > file`): capture contains `"run_id": ""` and `"git_sha": ""`; stderr empty.
5. `printf 'OK\n' > "${_DOTFILES_RUN_TMPDIR}/status_brew"`, no `result_brew`; `run --separate-stderr _update_summary`; `[[ "$output" =~ \[OK\][[:space:]]+brew([[:space:]]|$) ]]`; `[ -z "$stderr" ]`.

- [ ] Write the five tests; run the first gate: all pass on today's code (they characterise it).
- [ ] Red check: in an archive copy, replace line 604's `$(cat … 2>/dev/null || printf 'unknown')` with `$(cat "${_DOTFILES_RUN_TMPDIR}/git_sha")` (grep-prove) and show test 3 goes `not ok` on the stderr or value assertion; remove the copy.
- [ ] `make test` (log-and-poll if backgrounded), then commit `test(update): characterise update_summary state-file reads`.

### Task 2: Replace the 13 cat substitutions

```yaml-task
id: 2
description: Rewrite the 13 $(cat …) sites in lib/update_summary.sh per the spec Design table, add the load-bearing-braces comment, and prove equivalence with V1 and V2
role: executor
model: sonnet
tdd: required
requirements: [R1, R2, R3, R5]
acceptance:
  - cmd: 'bash -c ''! grep -nF "\$(cat " lib/update_summary.sh'''
    exit_code: 0
  - cmd: 'bash -c ''test "$(grep -cF "\$(<\"" lib/update_summary.sh)" -ge 13'''
    exit_code: 0
  - cmd: bats tests/setup_env/update_summary.bats
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [lib/update_summary.sh]
depends_on: [1]
```

Base counts (verified at `fca9316b`): `$(cat ` 13, `$(<"` 0. Edits, by line at `a2539a4e` (unchanged since):

| Line                              | New form                                                                                                                                       |
| --------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| 148                               | `[[ "$(<"${_DOTFILES_RUN_TMPDIR}/status_$1")" == "FAIL" ]] 2>/dev/null`                                                                        |
| 336, 439, 680, 691, 705, 749, 795 | `$(<"<same path>")`                                                                                                                            |
| 598                               | `{ _started_at=$(<"${_DOTFILES_RUN_TMPDIR}/started_at"); } 2>/dev/null \|\| _started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)`                        |
| 599                               | `{ _start_epoch=$(<"…/start_epoch"); } 2>/dev/null \|\| _start_epoch=0`                                                                        |
| 602–603                           | `{ _run_id=$(<"…/run_id"); } 2>/dev/null \|\| _run_id=$(python3 -c "import uuid; print(str(uuid.uuid4()))" 2>/dev/null \|\| printf 'unknown')` |
| 604                               | `{ _git_sha=$(<"…/git_sha"); } 2>/dev/null \|\| _git_sha=unknown`                                                                              |
| 750                               | `{ _result=$(<"…/result_${_section}"); } 2>/dev/null`                                                                                          |

Above line 598 add one comment line (R5): `# Braces are load-bearing: x=$(<f) 2>/dev/null still prints the open error; only { …; } 2>/dev/null silences it.` A failed `$(<…)` still performs the assignment with an empty value (probed on bash 5.3.9 and the Studio's `/bin/bash` 3.2), so 750 needs no reset.

- [ ] Make the edits; `bash -n lib/update_summary.sh`; run `bats tests/setup_env/update_summary.bats`.
- [ ] **V2** in an archive copy of the edited tree, one mutation at a time, grep-proving each, restoring between: (a) line 148 drop the trailing `2>/dev/null` → test 1 red; (b) 602 `{ _run_id=$(<"…"); } 2>/dev/null` → `_run_id=$(<"…") 2>/dev/null` → test 3 red; (c) 750 same brace-drop → test 5 red. Report each `not ok` line.
- [ ] **V1** in a second copy pair (old = `git show HEAD~1:lib/update_summary.sh` before your commit, i.e. the base; new = your edit): a scratch harness (not committed) sources each version under `bash -c` with `_DOTFILES_RUN_TMPDIR`, `HOME` and a `python3` stub that exits 1 on `PATH`, `_UPDATE_SECTION_ORDER` from the file, and a `ledger` capture stub. For each of the 72 cells below it runs old and new in fresh identical fixtures and compares rc, stdout (with the `=== Update Summary — <timestamp> ===` line and `"duration_seconds"` value masked), the sorted file listing plus contents of `_DOTFILES_RUN_TMPDIR`, the ledger capture, and stderr (exact, or emptiness only in the unreadable cell). Prints `COMPARED: <n>, DIVERGING: <m>` and each diverging cell.
  - States (6): missing, empty, `FAIL\n\n`, `OK`, `SKIP`, unreadable (mode 000; skip as an explicit failure if the harness runs as root).
  - `_update_status_is_fail brew` × `status_brew` × 6 = 6.
  - `_update_record_end brew 0` × `status_brew` × 6 = 6; `_update_record_end oh-my-zsh 0` × `pre_oh-my-zsh` × 6 = 6.
  - `_ledger_write_run_entry update 1` × {`started_at`, `start_epoch`, `run_id`, `git_sha`, `status_brew`, `result_brew`} × 6 = 36 (baseline: all four run files seeded as `_seed_ledger_run_files` does, machine-id seeded, `status_brew` `OK`, `result_brew` `no changes`).
  - `_update_summary` × {`status_brew`, `result_brew`, `detail_brew`} × 6 = 18 (baseline `status_brew` `OK`, `result_brew` `no changes`, `detail_brew` `detail text`).
  - Pass: `COMPARED: 72, DIVERGING: 0`. Report the line verbatim. Remove both copies.
- [ ] `make test`, then commit `perf(update): read summary state without forking cat`.

### Orchestrator, after Task 2

- [ ] `make test` at the head.
- [ ] V3: on the Studio, one before/after pair of the 11 files (`tests/setup_env/{workflows,update_apt,update_noop_skip,flatpak,cargo_tools_update,unit,update_claude,linux_shared,update_pyenv_shims,ledger_integration,update_summary}.bats`) at `bats --jobs 16`, in clones of base and head under `mktemp -d`, bare env per `CLAUDE.md`, `/usr/bin/time -l` and `uptime`. Record user, sys, wall in the PR body.
- [ ] After merge, on master: rewrite the P3 row "`_update_record_*` forks `cat` and `python3` per section" (cat half shipped with figures; python3 half closed as misplaced, see spec); close the P1 "bats process-spawn cost" row only if V3's after user+sys is below before, else update it with both figures; mark this plan Done.

## Non-goal check

Run inline by the orchestrator (Opus) on 2026-11-02: the subagent dispatch was refused by the session's
permission classifier, and the operator's standing rule is to run such work inline and disclose it. The
check read only the plan and the N list.

- N1 CLEAR. Files touched: `tests/setup_env/update_summary.bats`, `lib/update_summary.sh`, and `docs/`; the
  V1 harness lives in a scratch copy and is not committed.
- N2 CLEAR, near-miss. Task 2 restructures line 602 (`… || _run_id=$(python3 -c "import uuid; …" 2>/dev/null
  || printf 'unknown')`) but keeps the same single `python3` call; the `python3` stubs are test-only.
- N3 CLEAR. Task 2 adds a comment line, not a function.
- N4 CLEAR, near-miss. Task 2's acceptance gate `! grep -nF "\$(cat " lib/update_summary.sh` is a plan-time
  check run once by the executor, not a lint, ratchet or test committed to the repo.
- N5 CLEAR.
