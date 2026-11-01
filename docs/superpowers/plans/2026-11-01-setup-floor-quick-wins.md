# Setup Floor Quick Wins Implementation Plan

> **Status: DONE** (dotfiles#415, merged 2026-11-01 as 591e7a6f)

spec: docs/superpowers/specs/2026-11-01-setup-floor-quick-wins-design.md

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development (the local override) to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cut the bats per-test setup floor by moving `load_mocks`' `PATH` prepend last and resolving `setup_env.sh`'s directory once, without changing what any test sees.

**Architecture:** Two independent edits to existing helpers (`tests/helpers/common.bash`, `setup_env.sh`), each with its own red-first test; a docs task narrows the Backlog row and records part 2.

**Tech Stack:** bash, bats 1.13, GNU make; CI on ubuntu-latest and macos-latest.

## Global Constraints

- No change to any file under `tests/mocks/` (N1).
- No change to what any existing test asserts (N2).
- No `setup_file`, no cached or exported function definitions (N3).
- `_LOCAL_CFG` keeps its own `$(dirname "${BASH_SOURCE[0]}")`; `_SETUP_ENV_DIR` is unset before the sourcing guard.
- Relative path for R3 is built with `cd "${REPO_ROOT}/lib" && source ../setup_env.sh`, never `realpath --relative-to`.
- `make test` takes ~2m48s on `claude`: pass Bash `timeout: 600000`; every bats/make command gets `< /dev/null`.

## Verification Planning

- **Whole change:** `make test < /dev/null` exits 0 with `1..N` equal to the executed count.
- **Observable:** `load_mocks` writes nothing to `MOCK_CALLS_FILE`; `setup_env.sh` forks `dirname` once when sourced.
- **Edge cases:** a lib's `source` line deleted (R3 red); a `source` line in the old `$(dirname` form (R2 red); `/tmp/mock_calls` stops growing from `load_mocks` (checked after merge by size before and after one full suite run).
- **V1 (informational):** the PR body carries the spec's `claude` A/B and this PR's `test-macos-shard` leg timings beside master's latest run.

---

### Task 1: `load_mocks` prepends `tests/mocks` last

```yaml-task
id: 1
description: Move load_mocks' PATH prepend to its last statement so its own chmod/cp run real binaries and write nothing to MOCK_CALLS_FILE
role: executor
model: sonnet
tdd: required
requirements: [R1]
acceptance:
  - cmd: bats --jobs 4 tests/helpers_load_mocks.bats tests/helpers_git_env.bats < /dev/null
    exit_code: 0
  - cmd: make test < /dev/null
    exit_code: 0
max_retries: 3
files_touched: [tests/helpers/common.bash, tests/helpers_load_mocks.bats]
depends_on: []
```

**Files:** `tests/helpers/common.bash` (`load_mocks`), new `tests/helpers_load_mocks.bats` (header comment explains the shared `/tmp/mock_calls` leak, in the style of `tests/helpers_git_env.bats`).

**Test (write first, see red):** `setup()` sources `common.bash`; the test sets `MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/calls"`, creates it empty, calls `load_mocks`, then asserts the file is empty (print it with `cat` on failure) and that `${PATH%%:*}` equals `${REPO_ROOT}/tests/mocks`. Red on master: 6 lines (5 `chmod`, 1 `cp`).

**Change:** delete `export PATH="${REPO_ROOT}/tests/mocks:${PATH}"` from its current position and make it the last statement of `load_mocks`, after the `_OVERRIDE_CLAUDE_SETTINGS` export, with a comment saying why it must stay last (anything after it that runs `chmod`/`cp`/`ln`/`mv`/`tee`/`rm` resolves to a logging mock and writes outside the test tmpdir when `MOCK_CALLS_FILE` is not yet set). Reword the top comment that says "before the prepend below" to match.

**Mutant to report:** move the prepend back to its old line; the new test must go red.

**Interfaces:** Produces: `load_mocks` leaves the same environment and files as before, minus mock-log writes.

### Task 2: `setup_env.sh` resolves its directory once for the lib block

```yaml-task
id: 2
description: Set _SETUP_ENV_DIR with one dirname, use it for the 13 lib source lines, unset it before the sourcing guard; structural and separate-process tests
role: executor
model: sonnet
tdd: required
requirements: [R2, R3]
acceptance:
  - cmd: bats --jobs 8 tests/setup_env/unit.bats < /dev/null
    exit_code: 0
  - cmd: make test < /dev/null
    exit_code: 0
max_retries: 3
files_touched: [setup_env.sh, tests/setup_env/unit.bats]
depends_on: []
```

**Files:** `setup_env.sh` lines 42-54 (13 `source` lines), the guard at line 57 (`[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0`), `_LOCAL_CFG` at line 67 (unchanged); `tests/setup_env/unit.bats` (append two tests).

**R2 test (write first, red on master):** read `${REPO_ROOT}/setup_env.sh`; locate the guard as the first line matching `&& return 0` (never the first `BASH_SOURCE[0]`-vs-`${0}` comparison: line 4 is another); collect top-level lines matching `^source ` above it; assert their count equals `$(git -C "${REPO_ROOT}" ls-files 'lib/*.sh' | wc -l)` (strip GIT_* as `common.bash` already does), that each contains `${_SETUP_ENV_DIR}` and none contains `$(dirname`; then assert `[[ -z ${_SETUP_ENV_DIR+x} ]]` in the test shell (`setup()` already sourced the script). Print offending lines on failure.

**R3 test (characterization, green on master):** a `lib:marker` table, one row per tracked lib: `constants.sh:GO_VER detect_env.sh:detect_env developer.sh:clone_or_update_dotfiles git_hooks.sh:install_git_hooks_all_repos git_sync.sh:sync_git_repos helpers.sh:log_info launch_agents.sh:install_renovate_held_agent legacy_rsync.sh:sync_legacy_dirs linux_shared.sh:install_git_linux linux_ubuntu.sh:install_ubuntu_packages macos.sh:install_rosetta update_summary.sh:_update_summary workflows.sh:setup_claude_plugins` (each function verified defined in exactly one lib on 2026-11-01). Assert the table's row count equals the tracked lib count. Then `run env -u GO_VER bash -c '...'` that does `cd "${REPO_ROOT}/lib" && source ../setup_env.sh`, loops the table, prints `missing <marker> (lib/<file>)` for any marker not defined (`declare -F` for functions, `[[ -n ${GO_VER+x} ]]` for constants), and exits 1 if any is missing. Assert status 0 and empty `missing` output.

**Change:** insert `_SETUP_ENV_DIR="$(dirname "${BASH_SOURCE[0]}")"` before line 42, rewrite the 13 lines to `source "${_SETUP_ENV_DIR}/lib/<name>.sh"`, add `unset _SETUP_ENV_DIR` after the last of them with a one-line comment (value is `.` when run as `./setup_env.sh`; unset so no lib reuses it), leave `_LOCAL_CFG` as is.

**Mutants to report:** (a) restore one `source` line to the `$(dirname` form, R2 red; (b) delete the `lib/git_sync.sh` line, R3 red with `missing sync_git_repos (lib/git_sync.sh)`; (c) drop the `unset`, R2 red.

**Interfaces:** Produces: no new global after sourcing.

### Task 3: Backlog rows for part 1 and part 2

```yaml-task
id: 3
description: Narrow the P1 setup-floor Backlog row to part 1 shipped and add the part-2 process-spawn row (docs-only, no behaviour change)
role: executor
model: haiku
tdd: not-applicable
requirements: []
acceptance:
  - cmd: 'grep -q "process-spawn" docs/superpowers/README.md'
    exit_code: 0
  - cmd: make lint < /dev/null
    exit_code: 0
max_retries: 2
files_touched: [docs/superpowers/README.md]
depends_on: [1, 2]
```

**Change:** in the open P1 performance table, rewrite the "Per-test setup floor dominates many bats files" row: part 1 (this PR; spec `docs/superpowers/specs/2026-11-01-setup-floor-quick-wins-design.md`) cut ~10% CPU / ~5% wall on the three heaviest files on `claude`; the Linux re-measure put setup at ~17% of per-test CPU, not the Studio's 61%. Add a new P2 test-gaps or P1 performance row titled "bats process-spawn cost (part 2)": `sys` was 62% of CPU in the A/B; every mock is `#!/usr/bin/env bash` and `env` makes ~9 failed `execve` attempts walking `PATH`; other mocks still fall back to the shared `/tmp/mock_calls`. Never append to the last table ("Closed without shipping"). Task 3 runs no `make test`: its file cannot change the suite.

## Orchestrator steps

- [ ] After Task 3: `make test < /dev/null` once; record `1..N`, ok, not ok.
- [ ] Phase 3 gate chain; push the branch and open the PR (not draft: no mid-plan push).
- [ ] After CI: put V1 in the PR body (spec A/B, this PR's `test-macos-shard` timings vs master's latest run).
- [ ] After merge: record `/tmp/mock_calls` size before and after one full suite run on `claude`; ask the operator before deleting the stale file.

## Non-goal check

Reviewer run 2026-11-01 against `N1`-`N3` (`spec_contract.py`), plan as validated above. 3 CLEAR, 0 CONFLICT, 0 UNCLEAR; no plan revision or amendment needed.

- **N1 CLEAR** — "no task's files_touched lists a file under `tests/mocks/`".
- **N2 CLEAR** — "the plan adds new tests ... and edits no existing assertion".
- **N3 CLEAR** — "the new test uses `setup()`, not `setup_file`. `_SETUP_ENV_DIR` is a plain variable: it is not exported, not a function, and gets unset before the guard".
