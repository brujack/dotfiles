# recreate-ruby Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `setup_env.sh -t recreate-ruby` that force-deletes and reinstalls the pinned Ruby version (`RUBY_VER`), reusing existing `install_ruby()` logic on both platforms.

**Architecture:** New `recreate_ruby()` in `lib/developer.sh` guards tool presence, deletes the existing install (macOS: `rm -rf` the `.rubies/` dir; Linux: `rbenv uninstall -f`), then calls the existing `install_ruby()` to rebuild — no duplicated build logic. `run_recreate_ruby()` in `lib/workflows.sh` dispatches and writes a ledger entry. `process_args()`/`usage()` in `lib/helpers.sh` expose the new `-t` type. `setup_env.sh` adds one dispatch line.

**Tech Stack:** bash 5, rbenv (Linux), ruby-install/chruby (macOS), BATS

## Global Constraints

- No `--ruby-version` flag — always targets the single pinned `RUBY_VER` constant.
- No `DRY_RUN` support — matches `recreate_python_venv` and `install_ruby`, neither of which respect it today.
- Tool presence (`ruby-install` on macOS, `rbenv` on Linux) MUST be checked before any destructive delete — mirrors `recreate_python_venv`'s `quiet_which pyenv` check ordering.
- `recreate_ruby()` MUST call the existing `install_ruby()` for the rebuild step, not reimplement its build flags (`RUBY_CONFIGURE_OPTS="--with-openssl-dir=/usr"`, ruby-build git refresh, `--skip-existing`).
- No gemset isolation, no per-project Ruby envs — out of scope per spec.

## Verification Planning

- **Command:** `make test` from repo root.
- **Expected:** exit 0; final bats summary line shows all tests passing (no `not ok` lines); new tests for `recreate_ruby`, `run_recreate_ruby`, `process_args -t recreate-ruby`, and `usage()` all present and green.
- **Edge cases exercised:** macOS delete+rebuild path, Linux delete+rebuild path (with `RUBY_CONFIGURE_OPTS` regression assertion), tool-absent error path on both platforms (no delete attempted), arg parsing sets `RECREATE_RUBY=1`, `run_recreate_ruby` calls `recreate_ruby` and writes the ledger entry.

---

## Files

- Modify: `lib/helpers.sh` — `usage()` and `process_args()`
- Modify: `lib/developer.sh` — add `recreate_ruby()`
- Modify: `lib/workflows.sh` — add `run_recreate_ruby()`
- Modify: `setup_env.sh` — dispatch line for `RECREATE_RUBY`
- Modify: `lib/update_summary.sh` — `RUN_TYPE` comment list
- Modify: `tests/setup_env/unit.bats` — `process_args`, `usage`, `run_recreate_ruby` tests
- Modify: `tests/setup_env/install_functions.bats` — `recreate_ruby` tests
- Modify: `CLAUDE.md` — entry-points table, test count figure

---

### Task 1: Add `recreate-ruby` to `usage()` and `process_args()`

```yaml-task
id: 1
description: Add recreate-ruby type to usage() and process_args() arg parsing
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: make test
    exit_code: 0
  - cmd: './setup_env.sh -h 2>&1 | grep -q "recreate-ruby"'
    exit_code: 0
max_retries: 3
files_touched:
  - lib/helpers.sh
  - tests/setup_env/unit.bats
depends_on: []
```

**Files:**

- Modify: `lib/helpers.sh`
- Test: `tests/setup_env/unit.bats`

**Interfaces:**

- Produces: `RECREATE_RUBY` readonly var, set to `1` when `-t recreate-ruby` is passed. Later tasks (`run_recreate_ruby`, `setup_env.sh` dispatch) read this var.

- [ ] **Step 1: Write the failing tests**

Add to `tests/setup_env/unit.bats` after the existing `process_args sets RECREATE_VENV for -t recreate-venv` test:

```bash
@test "process_args sets RECREATE_RUBY for -t recreate-ruby" {
  run bash -c "
    source '${BATS_TEST_DIRNAME}/../../setup_env.sh'
    process_args -t recreate-ruby
    printf '%s' \"\${RECREATE_RUBY}\"
  "
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}
```

Add to the existing `usage` test block:

```bash
  [[ "$output" == *"recreate-ruby"* ]]
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
make test 2>&1 | grep -A2 "recreate-ruby\|RECREATE_RUBY"
```

Expected: fail — `RECREATE_RUBY` unset, usage missing the entry.

- [ ] **Step 3: Add `recreate-ruby` to `usage()`**

In `lib/helpers.sh`, in the `usage()` heredoc after the `recreate-venv` line:

```bash
  recreate-ruby  : Force-delete and reinstall the pinned Ruby version
```

- [ ] **Step 4: Add `recreate-ruby` case to the `-t` option in `process_args()`**

In the `case ${OPTARG}` block inside `process_args()`, after `recreate-venv)  readonly RECREATE_VENV=1 ;;`:

```bash
          recreate-ruby)  readonly RECREATE_RUBY=1 ;;
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
make test 2>&1 | grep -E "recreate-ruby|RECREATE_RUBY|ok|not ok" | head -20
```

Expected: new test and updated usage test both pass.

- [ ] **Step 6: Commit**

Invoke `caveman:caveman-commit` to generate the message, then commit:

```bash
git add lib/helpers.sh tests/setup_env/unit.bats
```

---

### Task 2: Add `recreate_ruby()` to `lib/developer.sh`

```yaml-task
id: 2
description: Add recreate_ruby function with platform-specific delete-then-rebuild logic
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: make test
    exit_code: 0
  - cmd: 'grep -q "^recreate_ruby()" lib/developer.sh'
    exit_code: 0
max_retries: 3
files_touched:
  - lib/developer.sh
  - tests/setup_env/install_functions.bats
depends_on:
  - 1
```

**Files:**

- Modify: `lib/developer.sh`
- Test: `tests/setup_env/install_functions.bats`

**Interfaces:**

- Consumes: existing `install_ruby()` (no signature change), existing `quiet_which()`, existing `log_error()`, `RUBY_VER` constant from `lib/constants.sh`.
- Produces: `recreate_ruby()` — no args, returns 0 on success, 1 on tool-absent or `install_ruby` failure. Consumed by Task 3's `run_recreate_ruby()`.

- [ ] **Step 1: Write the failing tests**

Add to `tests/setup_env/install_functions.bats` after the existing `install_ruby` tests:

```bash
# ── recreate_ruby ──────────────────────────────────────────────────────────

@test "recreate_ruby macOS: deletes .rubies dir then calls install_ruby" {
  export MACOS=1
  unset LINUX
  export PATH="${BATS_TEST_DIRNAME}/../mocks:${PATH}"
  mkdir -p "${HOME}/.rubies/ruby-${RUBY_VER}/bin"
  recreate_ruby
  [ ! -d "${HOME}/.rubies/ruby-${RUBY_VER}" ]
  grep -q "ruby-install" "${MOCK_CALLS_FILE}"
}

@test "recreate_ruby macOS: returns 1 and skips delete when ruby-install absent" {
  export MACOS=1
  unset LINUX
  export PATH="/usr/bin:/bin"
  mkdir -p "${HOME}/.rubies/ruby-${RUBY_VER}/bin"
  local _rc=0
  recreate_ruby || _rc=$?
  [ "${_rc}" -ne 0 ]
  [ -d "${HOME}/.rubies/ruby-${RUBY_VER}" ]
}

@test "recreate_ruby Linux: uninstalls via rbenv then reinstalls with RUBY_CONFIGURE_OPTS" {
  export LINUX=1
  export UBUNTU=1
  unset MACOS
  export HOME="${BATS_TEST_TMPDIR}"
  mkdir -p "${HOME}/.rbenv/bin" "${HOME}/.rbenv/versions/${RUBY_VER}" "${HOME}/.rbenv/plugins/ruby-build/.git"
  export PATH="${BATS_TEST_DIRNAME}/../mocks:${HOME}/.rbenv/bin:${PATH}"
  cp "${BATS_TEST_DIRNAME}/../mocks/rbenv" "${HOME}/.rbenv/bin/rbenv"
  chmod +x "${HOME}/.rbenv/bin/rbenv"
  recreate_ruby
  grep -q "uninstall -f ${RUBY_VER}" "${MOCK_CALLS_FILE}"
  grep -q "RUBY_CONFIGURE_OPTS=--with-openssl-dir=/usr" "${MOCK_CALLS_FILE}"
}

@test "recreate_ruby Linux: returns 1 and skips uninstall when rbenv absent" {
  export LINUX=1
  export UBUNTU=1
  unset MACOS
  export PATH="/usr/bin:/bin"
  local _rc=0
  recreate_ruby || _rc=$?
  [ "${_rc}" -ne 0 ]
  run grep "uninstall" "${MOCK_CALLS_FILE}"
  [ "$status" -ne 0 ]
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
make test 2>&1 | grep -A2 "recreate_ruby"
```

Expected: fail — `recreate_ruby` not defined.

- [ ] **Step 3: Write `recreate_ruby()` in `lib/developer.sh`**

Add immediately after `install_ruby()`:

```bash
recreate_ruby() {
  if [[ -n ${MACOS} ]]; then
    if ! quiet_which ruby-install; then
      log_error "ruby-install not found — cannot recreate ruby"
      return 1
    fi
    printf "Deleting ruby %s\\n" "${RUBY_VER}"
    rm -rf "${HOME}/.rubies/ruby-${RUBY_VER}"
  fi
  if [[ -n ${LINUX} ]]; then
    if ! quiet_which rbenv; then
      log_error "rbenv not found — cannot recreate ruby"
      return 1
    fi
    export PATH="${HOME}/.rbenv/bin:${PATH}"
    eval "$(rbenv init -)"
    printf "Deleting ruby %s\\n" "${RUBY_VER}"
    rbenv uninstall -f "${RUBY_VER}" 2>/dev/null || true
  fi
  install_ruby || return 1
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
make test 2>&1 | grep -E "recreate_ruby|ok|not ok" | head -30
```

Expected: all 4 `recreate_ruby` tests pass.

- [ ] **Step 5: Commit**

Invoke `caveman:caveman-commit` to generate the message, then commit:

```bash
git add lib/developer.sh tests/setup_env/install_functions.bats
```

---

### Task 3: Add `run_recreate_ruby()` and dispatch wiring

```yaml-task
id: 3
description: Add run_recreate_ruby workflow, setup_env.sh dispatch, and RUN_TYPE entry
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: make test
    exit_code: 0
  - cmd: 'grep -q "RECREATE_RUBY" setup_env.sh'
    exit_code: 0
max_retries: 3
files_touched:
  - lib/workflows.sh
  - setup_env.sh
  - lib/update_summary.sh
  - tests/setup_env/unit.bats
depends_on:
  - 2
```

**Files:**

- Modify: `lib/workflows.sh`
- Modify: `setup_env.sh`
- Modify: `lib/update_summary.sh`
- Test: `tests/setup_env/unit.bats`

**Interfaces:**

- Consumes: `recreate_ruby()` (Task 2), `_ledger_write_run_entry()` (existing), `RECREATE_RUBY` var (Task 1).
- Produces: `run_recreate_ruby()` — no args, returns 1 if `recreate_ruby` fails, else 0.

- [ ] **Step 1: Write the failing tests**

Add to `tests/setup_env/unit.bats` after the existing `run_recreate_venv` tests:

```bash
@test "run_recreate_ruby is defined after sourcing setup_env" {
  declare -f run_recreate_ruby &>/dev/null
  [ "$?" -eq 0 ]
}

@test "run_recreate_ruby calls recreate_ruby and writes ledger entry" {
  recreate_ruby() { printf "recreate_ruby called\n"; return 0; }
  _ledger_write_run_entry() { printf "ledger %s %s\n" "$1" "$2"; }
  run run_recreate_ruby
  [[ "$output" == *"recreate_ruby called"* ]]
  [[ "$output" == *"ledger recreate_ruby 0"* ]]
}

@test "run_recreate_ruby returns 1 when recreate_ruby fails" {
  recreate_ruby() { return 1; }
  run run_recreate_ruby
  [ "$status" -eq 1 ]
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
make test 2>&1 | grep -A2 "run_recreate_ruby"
```

Expected: fail — `run_recreate_ruby` not defined.

- [ ] **Step 3: Add `run_recreate_ruby()` to `lib/workflows.sh`**

Add immediately after `run_recreate_venv()`:

```bash
run_recreate_ruby() {
  recreate_ruby || return 1
  _ledger_write_run_entry "recreate_ruby" 0 || true
}
```

- [ ] **Step 4: Add dispatch line to `setup_env.sh`**

After the existing `[[ -n ${RECREATE_VENV:-} ]] && _run_or_exit run_recreate_venv` line:

```bash
[[ -n ${RECREATE_RUBY:-} ]] && _run_or_exit run_recreate_ruby
```

- [ ] **Step 5: Add `recreate_ruby` to the `RUN_TYPE` comment list**

In `lib/update_summary.sh`, update the comment:

```bash
# RUN_TYPE: update | setup_user | setup | developer | recreate_venv | recreate_ruby
```

- [ ] **Step 6: Run tests to verify they pass**

```bash
make test 2>&1 | grep -E "run_recreate_ruby|ok|not ok" | head -20
```

Expected: all 3 `run_recreate_ruby` tests pass.

- [ ] **Step 7: Commit**

Invoke `caveman:caveman-commit` to generate the message, then commit:

```bash
git add lib/workflows.sh setup_env.sh lib/update_summary.sh tests/setup_env/unit.bats
```

---

### Task 4: Update CLAUDE.md entry-points table

```yaml-task
id: 4
description: "Document recreate-ruby entry point in CLAUDE.md (docs-only, no behavior change)"
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: 'grep -q "recreate-ruby" CLAUDE.md'
    exit_code: 0
max_retries: 3
files_touched:
  - CLAUDE.md
depends_on:
  - 3
```

**Files:**

- Modify: `CLAUDE.md`

- [ ] **Step 1: Add `recreate-ruby` row to the entry-points table**

In `CLAUDE.md`, after the `recreate-venv` row:

```markdown
| `recreate-ruby` | Force-delete and reinstall the pinned Ruby version (`RUBY_VER`) via rbenv (Linux) or ruby-install (macOS). No flags — always targets the single pinned version. |
```

- [ ] **Step 2: Commit**

Invoke `caveman:caveman-commit` to generate the message, then commit:

```bash
git add CLAUDE.md
```
