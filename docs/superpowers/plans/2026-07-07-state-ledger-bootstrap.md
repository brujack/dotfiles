# state-ledger bootstrap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace dead `ensure_machine_id()` with `ensure_state_ledger()` — a non-fatal clone/pull
bootstrap for `~/.local/share/state-ledger`, called from every dotfiles run entry point.

**Architecture:** New `ensure_state_ledger()` in `lib/workflows.sh` mirrors the existing
`setup_ai_config()` clone-or-pull pattern, then delegates machine-id/hook/symlink setup to the
already-idempotent `ledger.py init`. Wired into `_dotfiles_run_tmpdir_setup()` — the single helper
shared by every `run_*` workflow — so one change covers `setup_user`, `setup`, `developer`,
`recreate_venv`, `recreate_ruby`, and `update`.

**Tech Stack:** bash, BATS, PATH-injected `git` mock (`tests/mocks/git`).

## Global Constraints

- Every failure path (clone fails, pull fails, `ledger.py init` fails) is non-fatal:
  `log_warn` + continue. Ledger sync must never fail a dotfiles setup/update run.
- Clone URL is hardcoded: `git@github.com:brujack/state-ledger.git` (matches `setup_ai_config()`'s
  hardcoded `ai-config` URL — no new `config/local.sh` variable).
- Test seam: `_OVERRIDE_STATE_LEDGER_DIR` env var (mirrors `_OVERRIDE_AI_CONFIG_DIR`), defaulting to
  `${HOME}/.local/share/state-ledger`.
- No changes to `_ledger_write_run_entry()`, `ledger_write_entry()`, or any `ledger.py` code — this
  plan is dotfiles-only (`lib/workflows.sh`, its test file, `CLAUDE.md`).

---

## Verification (session level)

- `make test` passes — all BATS suites green, including the new `ensure_state_ledger` tests.
- `bats tests/setup_env/install_guards.bats` — targeted run, all `ensure_state_ledger` and
  `_dotfiles_run_tmpdir_setup` tests pass.
- `grep -n "ensure_machine_id" lib/*.sh` returns no matches (dead function fully removed, not just
  unused).
- `grep -n "ensure_state_ledger" lib/workflows.sh` shows both the function definition and its call
  inside `_dotfiles_run_tmpdir_setup()`.
- Edge cases exercised by the test suite: dir absent (clone path), dir present (pull path), clone
  failure (non-fatal), pull failure (non-fatal, init still attempted), `ledger.py` present+executable
  (init invoked), `ledger.py` absent (init skipped, no error).

---

### Task 1: `ensure_state_ledger()` clone/pull core, replacing dead `ensure_machine_id()`

```yaml-task
id: 1
description: Add ensure_state_ledger() clone-or-pull logic to lib/workflows.sh, removing dead ensure_machine_id(), with tests for clone/pull/failure paths
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: bats tests/setup_env/install_guards.bats
    exit_code: 0
  - cmd: '! grep -n "ensure_machine_id" lib/workflows.sh'
    exit_code: 0
max_retries: 3
files_touched:
  - lib/workflows.sh
  - tests/setup_env/install_guards.bats
depends_on: []
```

**Files:**

- `lib/workflows.sh:721` — delete the existing `ensure_machine_id()` function (dead code, never
  called — confirmed by `grep -rn "ensure_machine_id" . --include="*.sh"` matching only its own
  definition). Replace with:

```bash
ensure_state_ledger() {
  local _dir="${_OVERRIDE_STATE_LEDGER_DIR:-${HOME}/.local/share/state-ledger}"
  local _url="git@github.com:brujack/state-ledger.git"

  if [[ -d "${_dir}" ]]; then
    git -C "${_dir}" pull --ff-only >/dev/null 2>&1 \
      || log_warn "state-ledger pull failed — continuing without ledger sync"
  else
    git clone "${_url}" "${_dir}" >/dev/null 2>&1 \
      || { log_warn "state-ledger clone failed — continuing without ledger"; return 0; }
  fi
}
```

(The `ledger.py init` delegation is added in Task 2 — this task covers only the clone/pull core
so each behavior gets its own RED→GREEN cycle.)

- `tests/setup_env/install_guards.bats` — new section after the existing `setup_ai_config` block
  (after line 476), following the exact same test conventions:

```bash
# ── ensure_state_ledger ──────────────────────────────────────────────────────

@test "ensure_state_ledger clones repo when state-ledger dir absent" {
  export _OVERRIDE_STATE_LEDGER_DIR="${BATS_TEST_TMPDIR}/nonexistent-state-ledger"

  run ensure_state_ledger
  [ "${status}" -eq 0 ]
  grep -q "git clone git@github.com:brujack/state-ledger.git ${BATS_TEST_TMPDIR}/nonexistent-state-ledger" "${MOCK_CALLS_FILE}"
}

@test "ensure_state_ledger does not clone when state-ledger dir exists" {
  export _OVERRIDE_STATE_LEDGER_DIR="${BATS_TEST_TMPDIR}/state-ledger"
  mkdir -p "${_OVERRIDE_STATE_LEDGER_DIR}"

  run ensure_state_ledger
  [ "${status}" -eq 0 ]
  ! grep -q "git clone" "${MOCK_CALLS_FILE}"
}

@test "ensure_state_ledger pulls (--ff-only) when state-ledger dir exists" {
  export _OVERRIDE_STATE_LEDGER_DIR="${BATS_TEST_TMPDIR}/state-ledger"
  mkdir -p "${_OVERRIDE_STATE_LEDGER_DIR}"

  run ensure_state_ledger
  [ "${status}" -eq 0 ]
  grep -q "git -C ${_OVERRIDE_STATE_LEDGER_DIR} pull --ff-only" "${MOCK_CALLS_FILE}"
}

@test "ensure_state_ledger warns and returns 0 when clone fails" {
  export MOCK_GIT_CLONE_EXIT=1
  export _OVERRIDE_STATE_LEDGER_DIR="${BATS_TEST_TMPDIR}/nonexistent-state-ledger"

  run ensure_state_ledger
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"state-ledger clone failed"* ]]
}

@test "ensure_state_ledger warns and returns 0 when pull fails" {
  export MOCK_GIT_EXIT=1
  export _OVERRIDE_STATE_LEDGER_DIR="${BATS_TEST_TMPDIR}/state-ledger"
  mkdir -p "${_OVERRIDE_STATE_LEDGER_DIR}"

  run ensure_state_ledger
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"state-ledger pull failed"* ]]
}
```

**Interfaces:**

- Consumes: `log_warn()` (`lib/helpers.sh:11`, signature `log_warn(msg...)`, prints to stderr).
  `MOCK_GIT_EXIT` / `MOCK_GIT_CLONE_EXIT` env vars honored by `tests/mocks/git` (already exists,
  no changes needed).
- Produces: `ensure_state_ledger()` — no args, always returns 0 (non-fatal by design). Task 2
  extends this same function body (adds the `ledger.py init` call after the if/else block) — do
  not add a `return` at the end of the if/else in this task, the function should fall through so
  Task 2 can append code after it.

---

### Task 2: `ledger.py init` delegation + wire into `_dotfiles_run_tmpdir_setup`

```yaml-task
id: 2
description: Extend ensure_state_ledger() to invoke ledger.py init when present, and call it from _dotfiles_run_tmpdir_setup
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: bats tests/setup_env/install_guards.bats
    exit_code: 0
  - cmd: 'grep -A 12 "^_dotfiles_run_tmpdir_setup" lib/workflows.sh | grep -q "ensure_state_ledger"'
    exit_code: 0
max_retries: 3
files_touched:
  - lib/workflows.sh
  - tests/setup_env/install_guards.bats
depends_on: [1]
```

**Files:**

- `lib/workflows.sh` — append to the end of `ensure_state_ledger()` (after the if/else block from
  Task 1):

```bash
  [[ -x "${_dir}/scripts/ledger.py" ]] && \
    { "${_dir}/scripts/ledger.py" init >/dev/null 2>&1 \
      || log_warn "ledger init failed — continuing"; }
}
```

- `lib/workflows.sh:95-105` — `_dotfiles_run_tmpdir_setup()`, add the call as the last line inside
  the function body:

```bash
_dotfiles_run_tmpdir_setup() {
  _DOTFILES_RUN_TMPDIR=$(mktemp -d)
  export _DOTFILES_RUN_TMPDIR
  trap 'rm -rf "${_DOTFILES_RUN_TMPDIR}"; unset _DOTFILES_RUN_TMPDIR' EXIT INT TERM
  date -u +%Y-%m-%dT%H:%M:%SZ > "${_DOTFILES_RUN_TMPDIR}/started_at"
  date +%s > "${_DOTFILES_RUN_TMPDIR}/start_epoch"
  python3 -c "import uuid; print(str(uuid.uuid4()))" \
    > "${_DOTFILES_RUN_TMPDIR}/run_id" 2>/dev/null || true
  git -C "${PERSONAL_GITREPOS}/${DOTFILES}" rev-parse HEAD \
    > "${_DOTFILES_RUN_TMPDIR}/git_sha" 2>/dev/null || true
  ensure_state_ledger || true
}
```

- `tests/setup_env/install_guards.bats` — add to the `ensure_state_ledger` section:

```bash
@test "ensure_state_ledger invokes ledger.py init when script is executable" {
  export _OVERRIDE_STATE_LEDGER_DIR="${BATS_TEST_TMPDIR}/state-ledger"
  mkdir -p "${_OVERRIDE_STATE_LEDGER_DIR}/scripts"
  printf '#!/usr/bin/env bash\nprintf "ledger-init-called\\n" >> "%s"\n' \
    "${MOCK_CALLS_FILE}" > "${_OVERRIDE_STATE_LEDGER_DIR}/scripts/ledger.py"
  chmod +x "${_OVERRIDE_STATE_LEDGER_DIR}/scripts/ledger.py"

  run ensure_state_ledger
  [ "${status}" -eq 0 ]
  grep -q "ledger-init-called" "${MOCK_CALLS_FILE}"
}

@test "ensure_state_ledger skips ledger.py init when script absent" {
  export _OVERRIDE_STATE_LEDGER_DIR="${BATS_TEST_TMPDIR}/state-ledger"
  mkdir -p "${_OVERRIDE_STATE_LEDGER_DIR}"

  run ensure_state_ledger
  [ "${status}" -eq 0 ]
  ! grep -q "ledger-init-called" "${MOCK_CALLS_FILE}"
}

@test "_dotfiles_run_tmpdir_setup calls ensure_state_ledger" {
  ensure_state_ledger() { printf "stub-ensure-state-ledger-called\n" >> "${MOCK_CALLS_FILE}"; }

  run _dotfiles_run_tmpdir_setup
  [ "${status}" -eq 0 ]
  grep -q "stub-ensure-state-ledger-called" "${MOCK_CALLS_FILE}"
}
```

**Interfaces:**

- Consumes: `ensure_state_ledger()` from Task 1 (same function, extended in place — no new
  signature). `_dotfiles_run_tmpdir_setup()` (`lib/workflows.sh:95`, no args, sets
  `_DOTFILES_RUN_TMPDIR` and exports it).
- Produces: `ensure_state_ledger()` final form — no args, always returns 0, invokes `ledger.py init`
  as a side effect when present+executable. This is the last task that touches
  `lib/workflows.sh`/the test file — Task 3 only touches `CLAUDE.md`.

---

### Task 3: CLAUDE.md documentation update

```yaml-task
id: 3
description: Document ensure_state_ledger bootstrap in CLAUDE.md state-ledger notes (docs-only, no behavior change)
role: executor
model: haiku
tdd: not-applicable
acceptance:
  - cmd: 'grep -q "ensure_state_ledger" CLAUDE.md'
    exit_code: 0
max_retries: 3
files_touched:
  - CLAUDE.md
depends_on: [2]
```

**Files:**

- `CLAUDE.md` — in the `Entry Points` table's `update` row, the existing sentence ends with "...
  advisory, never fails the run." Add one sentence immediately after: "`ensure_state_ledger()` (in
  `lib/workflows.sh`, called from `_dotfiles_run_tmpdir_setup`) clones or pulls
  `~/.local/share/state-ledger` and runs `ledger.py init` at the start of every run type (not just
  `update`) — non-fatal on failure."

**Interfaces:**

- Consumes: nothing (prose-only edit).
- Produces: nothing (terminal task, no later task depends on this).

---

## Post-Plan

After Task 3 merges: update `docs/superpowers/README.md` row for this plan from `In Progress` to
`Done`, and add the `> **Status: DONE**` banner to the top of this plan file.
