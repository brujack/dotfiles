# Ledger Run Outcome Implementation Plan

> **Status: DONE** (dotfiles#426, merged 2026-11-04)

spec: docs/superpowers/specs/2026-11-04-ledger-run-outcome-design.md
scope: PR1

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Record failed dotfiles runs in state-ledger with an `outcome` field, at most one entry per run, through an ssh-bounded write.

**Architecture:** `_ledger_write_run_entry` (`lib/update_summary.sh`) gains `outcome` and a one-write-per-run marker. `_run_or_exit` moves from `setup_env.sh` (where the sourcing guard hides it from tests) into `lib/workflows.sh` and writes a `failed` entry when a mapped run function returns non-zero. `ledger_write_entry` runs `ledger write` under `_git_ssh_opts`.

**Tech Stack:** bash, bats (`tests/setup_env/`), `tests/mocks/ledger`.

## Global Constraints

- `success` keeps the meaning "the run function returned exit 0" for every run type (N2).
- No run function's exit code changes, and no step that continues today aborts (N5).
- `run_brew_install` and `run_mas_install` still write no ledger entry (N4).
- No `"partial"` outcome value and no per-step marks (N6).
- No `failure_stage` for run types other than `update` (N3).
- Every task's gate includes `make test` (suite ~104 s on `claude`, under the 600 s Bash cap) and `make lint`.

## Verification (session level)

- `make test` exits 0 with `not ok` count 0, and CI bash coverage stays at or above 91% (V2).
- Hand probe after Task 3: in a scratch `HOME` with a `machine-id` and `LEDGER_BIN` pointed at `tests/mocks/ledger`, sourcing `lib/workflows.sh` and running `_run_or_exit` on a stub that returns 1 records exactly one `ledger write` whose payload has `"outcome": "failed"` and `"success": false`, and the call exits 1.
- V1 (post-merge, real `-t update` on `claude`) and V3 (BatchMode `ls-remote` on the 7950X and the Studio, operator) are recorded in the PR body.

---

### Task 1: Writer `outcome` field and one write per run

```yaml-task
id: 1
description: Add outcome ok/failed to _ledger_write_run_entry and a ledger_written marker that limits a run directory to one write
role: executor
model: sonnet
tdd: required
requirements: [R1, R2]
acceptance:
  - cmd: bats tests/setup_env/ledger_integration.bats tests/setup_env/update_summary.bats
    exit_code: 0
  - cmd: make lint
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [lib/update_summary.sh, tests/setup_env/ledger_integration.bats, tests/setup_env/update_summary.bats]
depends_on: []
```

**Files:** `lib/update_summary.sh` (`_ledger_write_run_entry`, line 588), `tests/setup_env/ledger_integration.bats`, `tests/setup_env/update_summary.bats`.

- [ ] RED tests in `ledger_integration.bats`, using that file's existing capture pattern (lines 252-293):
  - exit 0 gives `"outcome": "ok"` and `"success": true`;
  - exit 1 gives `"outcome": "failed"` and `"success": false`;
  - `update` with exit 1 gives `"outcome": "failed"`, and with exit 0 gives `"ok"`;
  - a second call in the same `_DOTFILES_RUN_TMPDIR` invokes the ledger binary zero more times. Count the calls with `tests/mocks/ledger` and `MOCK_CALLS_FILE`.
  - with `MOCK_LEDGER_EXIT=2` (spooled), `${_DOTFILES_RUN_TMPDIR}/ledger_written` exists after the call.
- [ ] Implement:
  - Add `"outcome": "%s"` beside `"success"` in the base `printf` (value `failed` when `_exit_code -ne 0`, else `ok`).
  - At the top, after the `started_at`/`machine-id` early returns, `[[ -f "${_DOTFILES_RUN_TMPDIR}/ledger_written" ]] && return 0`.
  - Run `: > "${_DOTFILES_RUN_TMPDIR}/ledger_written"` after each `ledger_write_entry` call, whatever its rc.
  - Preserve the function's existing return value from `ledger_write_entry`.
- [ ] `update_summary.bats` cases 20 and 21 (lines ~1311-1355) write twice in one directory. Make `_seed_ledger_run_files` (line 1163) also run `rm -f "${_DOTFILES_RUN_TMPDIR}/ledger_written"`; keep their assertions unchanged.
- [ ] Mutation control, reported in the task summary: delete the guard line and confirm the second-call test fails; restore it.
- [ ] Commit (`caveman:caveman-commit`).

**Interfaces:**

- Produces: `_ledger_write_run_entry RUN_TYPE EXIT_CODE` writes `outcome` and refuses a second write per run directory; the marker file is `${_DOTFILES_RUN_TMPDIR}/ledger_written`.

### Task 2: `developer` passes 0

```yaml-task
id: 2
description: run_developer_or_ansible passes 0 to _ledger_write_run_entry, matching its own return value
role: executor
model: sonnet
tdd: required
requirements: [R3]
acceptance:
  - cmd: bats tests/setup_env/workflows.bats
    exit_code: 0
  - cmd: make lint
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [lib/workflows.sh, tests/setup_env/workflows.bats]
depends_on: [1]
```

**Files:** `lib/workflows.sh` (`run_developer_or_ansible`, ledger call near line 654), `tests/setup_env/workflows.bats` (test at line 2561, which today asserts `^ledger developer 2$`).

- [ ] RED: change that test's assertion to `^ledger developer 0$`, keep its warn assertion, and rename it to "...warns and ledgers 0...". Confirm it fails.
- [ ] Implement: `_ledger_write_run_entry "developer" 0 || true`. Keep `_gh_rc` for the existing `log_warn` branch.
- [ ] Commit.

**Interfaces:** none new.

### Task 3: `_run_or_exit` records hard failures

```yaml-task
id: 3
description: Move _run_or_exit into lib/workflows.sh and write a failed ledger entry when a mapped run function returns non-zero
role: executor
model: sonnet
tdd: required
requirements: [R4]
acceptance:
  - cmd: bats tests/setup_env/run_or_exit.bats
    exit_code: 0
  - cmd: make lint
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [lib/workflows.sh, setup_env.sh, tests/setup_env/run_or_exit.bats]
depends_on: [1, 2]
```

**Files:** `setup_env.sh` (delete `_run_or_exit`, lines 90-94; the dispatch lines 96-105 stay), `lib/workflows.sh` (new `_run_or_exit`), new `tests/setup_env/run_or_exit.bats`.

- [ ] RED `run_or_exit.bats`.
  - **Shared fixture.** `load_setup_env` and `load_mocks`; `export HOME="${BATS_TEST_TMPDIR}/home"` with a `machine-id` at `${HOME}/.config/dotfiles/machine-id`; `LEDGER_BIN="${PROJECT_ROOT}/tests/mocks/ledger"`; `MOCK_CALLS_FILE`. Stubs call `_dotfiles_run_tmpdir_setup` then return a chosen rc. Run `_run_or_exit` in a subshell (`run bash -c` or `( … )`) because it calls `exit`.
  - Mapped stub `run_setup_user` returning 1: exactly one `ledger write` call, payload contains `"outcome": "failed"`, `"run_type": "setup_user"` and `"success": false`; exit status 1.
  - Stub `run_setup_user` that runs its own `_ledger_write_run_entry setup_user 0` and then returns 1: exactly one ledger call.
  - Stub `run_setup_user` returning 1 without creating a run directory, while a previous run's directory (with `started_at` and `ledger_written`) is exported: zero ledger calls.
  - `run_update` stub returning 1: zero ledger calls from the dispatcher.
  - Unmapped `run_brew_install` returning 1: zero calls.
  - Each mapped name maps to its run type: `setup_user`, `setup`, `developer`, `recreate_venv`, `recreate_ruby` (one table-driven test).
  - Return 0: zero dispatcher calls, exit 0.
  - Structural pin (N2): for each of the five mapped run functions, the last statement of its body in `lib/workflows.sh` is its `_ledger_write_run_entry … || true` line (extract with `declare -f <fn>` and compare the last statement). A function that wrote `0` and then failed would otherwise keep a `success: true` entry, because the one-write guard blocks the dispatcher's `failed` write.
- [ ] Implement in `lib/workflows.sh` before the file's sourcing guard:

```bash
# Dispatches one run function; on failure records a failed ledger entry
# (at most one per run directory, see _ledger_write_run_entry) and exits.
_run_or_exit() {
  "$@"
  local _ec=$? _type=""
  [[ ${_ec} -eq 0 ]] && return 0
  case "$1" in
    run_setup_user)           _type=setup_user ;;
    run_setup_or_developer)   _type=setup ;;
    run_developer_or_ansible) _type=developer ;;
    run_recreate_venv)        _type=recreate_venv ;;
    run_recreate_ruby)        _type=recreate_ruby ;;
  esac
  [[ -n "${_type}" ]] && { _ledger_write_run_entry "${_type}" "${_ec}" || true; }
  exit "${_ec}"
}
```

- [ ] Delete the old definition from `setup_env.sh`; `grep -n '_run_or_exit()' setup_env.sh lib/workflows.sh` shows only `lib/workflows.sh`.
- [ ] Mutation control, reported: delete the `_ledger_write_run_entry` line and confirm the first test fails.
- [ ] Commit.

**Interfaces:**

- Consumes: Task 1's marker guard.
- Produces: `_run_or_exit FUNC [ARGS…]` in `lib/workflows.sh`.

### Task 4: Bound the ledger write's ssh

```yaml-task
id: 4
description: ledger_write_entry runs ledger write with GIT_SSH_COMMAND set to _git_ssh_opts output
role: executor
model: sonnet
tdd: required
requirements: [R5]
acceptance:
  - cmd: bats tests/setup_env/ledger_integration.bats
    exit_code: 0
  - cmd: make lint
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [lib/workflows.sh, tests/setup_env/ledger_integration.bats]
depends_on: [3]
```

**Files:** `lib/workflows.sh` (`ledger_write_entry`, line ~2245), `tests/setup_env/ledger_integration.bats`.

- [ ] RED: a stub ledger, written with the existing `_mk_ledger_capture`-style pattern, records `printf '%s\n' "${GIT_SSH_COMMAND-UNSET}"` to a file. Assert the file equals `ssh -o BatchMode=yes -o ConnectTimeout=10`. Run the test with `GIT_SSH_COMMAND` unset first so the base fails with `UNSET`.
- [ ] Implement: `printf '%s' "${_json}" | GIT_SSH_COMMAND="$(_git_ssh_opts)" "${_ledger_bin}" write`.
- [ ] Commit.

**Interfaces:** none new.

### Task 5: `pyproject.toml` comment and backlog rows

```yaml-task
id: 5
description: Fix the pyproject test-lint comment and update backlog rows (docs and comment only, no behaviour, so TDD does not apply)
role: executor
model: sonnet
tdd: not-applicable
requirements: [R8]
acceptance:
  - cmd: '! grep -q "five repos" pyproject.toml'
    exit_code: 0
  - cmd: 'grep -q "ci-\*" pyproject.toml'
    exit_code: 0
  - cmd: 'grep -qi "partial run outcome" docs/superpowers/README.md'
    exit_code: 0
  - cmd: make check-lock
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 2
files_touched: [pyproject.toml, docs/superpowers/README.md]
depends_on: [4]
```

**Files:** `pyproject.toml` (line 150 comment), `docs/superpowers/README.md` (Backlog).

- [ ] Replace `# Must match what five repos' CI installs. Exported to requirements-ci.txt.` with `# The full local/dev test set, rendered to requirements-ci.txt. Consumers' CI installs the ci-* renderings below, not this one.`
- [ ] Remove the backlog row "`pyproject.toml`'s `test-lint` comment claims five repos' CI install it".
- [ ] Add three P3 rows, text taken from the spec's "Backlog rows added":
  - "Partial run outcome: blocked on WARN noise";
  - the `git-repos` parent-directory WARN (`lib/git_sync.sh:76`);
  - `clone_personal_repos` masking earlier clone failures, with its caller at `lib/workflows.sh:647` and `setup_vim_plugins`' caller at `:601`.

  Each row cites `specs/2026-11-04-ledger-run-outcome-design.md`.

- [ ] The orchestrator runs `make test` after this task; this task's files cannot change the suite.
- [ ] Commit.

**Interfaces:** none.

## Orchestrator steps

- Worktree `../dotfiles-wt-ledger` on branch `feat/ledger-run-outcome`, from `origin/master`.
- After Task 5: `make test`, then Phase 3 (`finishing-a-development-branch`).
- The PR body records V3's per-machine results (operator) and the V1 follow-up.
- PR2 (state-ledger R6, R7) goes to the state-ledger owning session after PR1 merges. Its scope is `cmd_history`/`cmd_status` display and the README only; `_validate_entry` and the set of required fields stay unchanged (N1).

## Non-goal check

Reviewer run 2026-11-04 over the plan above and N1-N6. CLEAR: N3, N4, N5, N6. CONFLICT: none.

- **N1 — UNCLEAR.** Quote: "PR2 (state-ledger R6, R7) goes to the state-ledger owning session after PR1 merges." Resolution: plan revision. Before: that sentence alone. After: the same sentence plus "Its scope is `cmd_history`/`cmd_status` display and the README only; `_validate_entry` and the set of required fields stay unchanged (N1)."
- **N2 — UNCLEAR.** Quote: "Stub `run_setup_user` that runs its own `_ledger_write_run_entry setup_user 0` and then returns 1: exactly one ledger call." Resolution: plan revision. Verified that the case is unreachable today: in all five mapped run functions the ledger call is the last statement (`lib/workflows.sh` 555, 602, 654, 661, 667, each followed by `}`), so writing `0` implies returning 0. Before: no test pinned that. After: Task 3 adds a structural test asserting it, so a future edit that breaks it fails the suite instead of recording a false `success: true`.
