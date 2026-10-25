# ensure_state_ledger failure cause Implementation Plan

> **Status: DONE**

spec: docs/superpowers/specs/2026-10-24-ensure-state-ledger-failure-cause-design.md

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** each `ensure_state_ledger` warning (pull, clone, init) is followed by the stderr lines that say why the step failed.

**Architecture:** a new helper `_ledger_warn_with_cause` in `lib/workflows.sh` prints the existing warning text, then the first 3 and the last non-empty stderr lines (or `(no stderr output)`). `ensure_state_ledger` captures each command's stderr with `_err=$(cmd 2>&1 >/dev/null)` and hands it to the helper on failure. `tests/mocks/git` gains `MOCK_GIT_STDERR`.

**Tech Stack:** bash, bats.

## Global Constraints

- The three warning texts stay byte-identical (N1).
- No warning when a command exits 0, whatever it wrote to stderr (N2).
- No change to the state-ledger repo (N3).
- `ledger.py init` still runs after a failed pull (N4).

## Verification

- Session-level: `make test` exits 0, run once by the orchestrator after Task 2.
- V1 (orchestrator, before dispatching Task 1): put the six new tests on a `git archive` copy of the base and confirm tests 1, 2 and 3 fail there.
- Task gates use `tests/setup_env/install_guards.bats` only (108 tests, 7 s with `--jobs 12`, measured 2026-10-24).

---

### Task 1: capture stderr and name the cause

```yaml-task
id: 1
description: Add _ledger_warn_with_cause, capture stderr in ensure_state_ledger's three steps, add MOCK_GIT_STDERR and six tests
role: executor
model: sonnet
tdd: required
requirements: [R1, R2, R3, R4, R5, R6]
acceptance:
  - cmd: 'bats --jobs 12 tests/setup_env/install_guards.bats < /dev/null'
    exit_code: 0
  - cmd: 'bats -f "ensure_state_ledger names cause" tests/setup_env/install_guards.bats < /dev/null'
    exit_code: 0
    stdout_match: "1\\.\\.6\\n"
  - cmd: 'for t in "state-ledger pull failed — continuing without ledger sync" "state-ledger clone failed — continuing without ledger" "ledger init failed — continuing"; do test "$(grep -cF "$t" lib/workflows.sh)" -eq 1 || exit 1; done'
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched: [lib/workflows.sh, tests/mocks/git, tests/setup_env/install_guards.bats]
depends_on: []
```

**Interfaces:** Produces `_ledger_warn_with_cause <msg> <stderr>` (always returns 0). Consumes `log_warn` (`lib/helpers.sh`, writes to stderr).

- [ ] **Step 1: mock knob.** In `tests/mocks/git`, add this line immediately before `exit "${MOCK_GIT_CLONE_EXIT:-0}"` and again immediately before the final `exit "${MOCK_GIT_EXIT:-0}"` (never on the `rev-parse --git-dir` or `config --get` paths):

```bash
[[ -n "${MOCK_GIT_STDERR:-}" ]] && printf '%s\n' "${MOCK_GIT_STDERR}" >&2
```

- [ ] **Step 2: failing tests.** Append to `tests/setup_env/install_guards.bats` after the test `ensure_state_ledger uses SSH BatchMode to avoid hanging on host-key prompt`. The stub writes to **stderr**, because stdout stays discarded:

```bash
# Writes an executable ledger.py stub that prints <file>'s contents to stderr,
# appends a marker to MOCK_CALLS_FILE, and exits <rc>.
_make_ledger_stub() {
  local _rc="$1" _stderr_file="$2"
  mkdir -p "${_OVERRIDE_STATE_LEDGER_DIR}/scripts"
  printf '#!/usr/bin/env bash\ncat "%s" >&2\nprintf "ledger-init-called\\n" >> "%s"\nexit %s\n' \
    "${_stderr_file}" "${MOCK_CALLS_FILE}" "${_rc}" > "${_OVERRIDE_STATE_LEDGER_DIR}/scripts/ledger.py"
  chmod +x "${_OVERRIDE_STATE_LEDGER_DIR}/scripts/ledger.py"
}

@test "ensure_state_ledger names cause: pull failure shows git's cause line" {
  export MOCK_GIT_EXIT=1
  export MOCK_GIT_STDERR=$'git@github.com: Permission denied (publickey).\nfatal: Could not read from remote repository.\n\nPlease make sure you have the correct access rights\nand the repository exists.'
  export _OVERRIDE_STATE_LEDGER_DIR="${BATS_TEST_TMPDIR}/state-ledger"
  mkdir -p "${_OVERRIDE_STATE_LEDGER_DIR}"
  run ensure_state_ledger
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"state-ledger pull failed"* ]]
  [[ "${output}" == *"Permission denied (publickey)"* ]]
  [[ "${output}" == *"fatal: Could not read from remote repository."* ]]
}

@test "ensure_state_ledger names cause: init traceback shows git's fatal line" {
  export _OVERRIDE_STATE_LEDGER_DIR="${BATS_TEST_TMPDIR}/state-ledger"
  cat > "${BATS_TEST_TMPDIR}/tb.txt" <<'EOF'
fatal: cannot change to '/nonexistent-x': No such file or directory
Traceback (most recent call last):
  File "<string>", line 1, in <module>
    import subprocess; subprocess.run(["git","-C","/nonexistent-x","pull","--ff-only"], check=True)
                       ~~~~~~~~~~~~~~^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/lib/python3.14/subprocess.py", line 578, in run
    raise CalledProcessError(retcode, process.args,
                             output=stdout, stderr=stderr)
subprocess.CalledProcessError: Command '['git', '-C', '/nonexistent-x', 'pull', '--ff-only']' returned non-zero exit status 128.
EOF
  _make_ledger_stub 1 "${BATS_TEST_TMPDIR}/tb.txt"
  run ensure_state_ledger
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"ledger init failed"* ]]
  [[ "${output}" == *"fatal: cannot change to"* ]]
  [[ "${output}" == *"CalledProcessError: Command"* ]]
}

@test "ensure_state_ledger names cause: clone failure shows cause and returns 0" {
  export MOCK_GIT_CLONE_EXIT=1
  export MOCK_GIT_STDERR="fatal: clone-cause"
  export _OVERRIDE_STATE_LEDGER_DIR="${BATS_TEST_TMPDIR}/nonexistent-state-ledger"
  run ensure_state_ledger
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"state-ledger clone failed"* ]]
  [[ "${output}" == *"fatal: clone-cause"* ]]
}

@test "ensure_state_ledger names cause: keeps first 3 and last stderr lines only" {
  export _OVERRIDE_STATE_LEDGER_DIR="${BATS_TEST_TMPDIR}/state-ledger"
  printf 'line-e1\nline-e2\n\nline-e3\nline-e4\nline-e5\nline-e6\n' > "${BATS_TEST_TMPDIR}/six.txt"
  _make_ledger_stub 1 "${BATS_TEST_TMPDIR}/six.txt"
  run ensure_state_ledger
  [[ "${output}" == *"line-e1"* && "${output}" == *"line-e2"* ]]
  [[ "${output}" == *"line-e3"* && "${output}" == *"line-e6"* ]]
  [[ "${output}" != *"line-e4"* && "${output}" != *"line-e5"* ]]
}

@test "ensure_state_ledger names cause: empty stderr says so" {
  export _OVERRIDE_STATE_LEDGER_DIR="${BATS_TEST_TMPDIR}/state-ledger"
  : > "${BATS_TEST_TMPDIR}/empty.txt"
  _make_ledger_stub 1 "${BATS_TEST_TMPDIR}/empty.txt"
  run ensure_state_ledger
  [[ "${output}" == *"ledger init failed"* ]]
  [[ "${output}" == *"(no stderr output)"* ]]
}

@test "ensure_state_ledger names cause: success with stderr chatter stays quiet" {
  export MOCK_GIT_STDERR="From github.com:brujack/state-ledger"
  export _OVERRIDE_STATE_LEDGER_DIR="${BATS_TEST_TMPDIR}/state-ledger"
  printf 'WARNING: `pre-commit` not on PATH\n' > "${BATS_TEST_TMPDIR}/warn.txt"
  _make_ledger_stub 0 "${BATS_TEST_TMPDIR}/warn.txt"
  run ensure_state_ledger
  [ "${status}" -eq 0 ]
  [[ "${output}" != *"[WARN]"* ]]
  grep -q "ledger-init-called" "${MOCK_CALLS_FILE}"
}
```

- [ ] **Step 3:** run `bats -f "ensure_state_ledger names cause" tests/setup_env/install_guards.bats < /dev/null`; tests 1-5 fail (no cause lines), test 6 passes.

- [ ] **Step 4: helper.** In `lib/workflows.sh`, directly above `ensure_state_ledger()`:

```bash
# Warn, then show the stderr lines that say why. The cause sits near the top
# (git prints it before "fatal:"; ledger.py's traceback follows git's own
# "fatal:" line) and ledger.py's own "ERROR:" line comes last, so keep the
# first 3 non-empty lines and the last one.
_ledger_warn_with_cause() {
  local _msg="$1" _err="$2" _line
  local -a _lines=() _pick=()
  log_warn "${_msg}"
  while IFS= read -r _line; do
    [[ "${_line}" =~ ^[[:space:]]*$ ]] && continue
    _lines+=("${_line}")
  done <<< "${_err}"
  if [[ ${#_lines[@]} -eq 0 ]]; then
    log_warn "  (no stderr output)"
    return 0
  fi
  if [[ ${#_lines[@]} -le 4 ]]; then
    _pick=("${_lines[@]}")
  else
    _pick=("${_lines[@]:0:3}" "${_lines[${#_lines[@]}-1]}")
  fi
  for _line in "${_pick[@]}"; do
    log_warn "  ${_line}"
  done
  return 0
}
```

- [ ] **Step 5: capture.** In `ensure_state_ledger`, add `local _err` on its own line after `_url`, then replace the three calls (texts unchanged):

```bash
    _err=$(GIT_SSH_COMMAND="$(_git_ssh_opts)" git -C "${_dir}" pull --ff-only 2>&1 >/dev/null) \
      || _ledger_warn_with_cause "state-ledger pull failed — continuing without ledger sync" "${_err}"
```

```bash
    _err=$(GIT_SSH_COMMAND="$(_git_ssh_opts)" git clone "${_url}" "${_dir}" 2>&1 >/dev/null) \
      || { _ledger_warn_with_cause "state-ledger clone failed — continuing without ledger" "${_err}"; return 0; }
```

```bash
  if [[ -x "${_dir}/scripts/ledger.py" ]]; then
    _err=$("${_dir}/scripts/ledger.py" init 2>&1 >/dev/null) \
      || _ledger_warn_with_cause "ledger init failed — continuing" "${_err}"
  fi
```

Keep `return 0` at the end. Do not add any skip of init after a failed pull (N4).

- [ ] **Step 6:** run all acceptance commands; all pass.
- [ ] **Step 7:** commit the three files.

### Task 2: Backlog row

```yaml-task
id: 2
description: Remove the P2 ensure_state_ledger backlog row (docs-only, no behavior change)
role: executor
model: haiku
tdd: not-applicable
requirements: [R7]
acceptance:
  - cmd: '! command grep -qF "| \`ensure_state_ledger\` hides why \`ledger init\` failed |" docs/superpowers/README.md'
    exit_code: 0
  - cmd: 'test "$(git diff --numstat HEAD~1 -- docs/superpowers/README.md | cut -f1,2)" = "$(printf "0\t1")"'
    exit_code: 0
max_retries: 2
files_touched: [docs/superpowers/README.md]
depends_on: [1]
```

**Files:** `docs/superpowers/README.md` only; the suite does not read it, so no `make test` gate.

- [ ] **Step 1:** under `### P2 — bugs and security`, delete the one table row beginning ``| `ensure_state_ledger` hides why `ledger init` failed |``. Delete nothing else.
- [ ] **Step 2:** commit, then run the acceptance commands (the second reads the committed diff).

### Orchestrator, after Task 2

- [ ] `make test < /dev/null` exits 0 (background run).
- [ ] Phase 3 via `finishing-a-development-branch`.
- [ ] Post-merge docs: `MOCK_GIT_STDERR` is a new mock knob; ask the ai-config session to add it to the mock table in `dotfiles-bats-test-infrastructure.md`.

## Non-goal check

Reviewer (fresh subagent, 2026-10-24): N1 CLEAR, N2 CLEAR, N3 CLEAR, N4 CLEAR. No plan revision.

- N1: "Step 5 keeps all three warning texts as they are, and the Task 1 grep acceptance check requires each text to appear exactly once."
- N2: "the warning call only runs on `|| _ledger_warn_with_cause`, so it fires only on a non-zero exit. Test 6 checks that a command exiting 0 with stderr output prints no `[WARN]`."
- N3: "Task 1 changes only `lib/workflows.sh`, `tests/mocks/git` and `tests/setup_env/install_guards.bats`; Task 2 changes only `docs/superpowers/README.md`."
- N4: "a failed pull only warns, then init runs whenever the script is executable. Step 5 says not to add any skip of init."
