# recreate-ruby gem update Implementation Plan

> **Status: DONE** — merged via dotfiles#174

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract a shared `update_gems()` function that fixes the Linux rbenv-shims PATH gap in gem updates, then wire it into `recreate_ruby()` (fail-fast) and into `run_update`'s existing gems section (unchanged soft-fail behavior).

**Architecture:** New `update_gems()` in `lib/developer.sh`, placed after `recreate_ruby()`. It prepends the platform-correct gem directory to `PATH` before calling `gem update` — `${HOME}/.rubies/ruby-${RUBY_VER}/bin` on macOS (existing chruby logic, unchanged), `${HOME}/.rbenv/shims` on Linux (new — the missing branch). `recreate_ruby()` calls it after `install_ruby` and fails the whole recreate on a gem-update failure. `run_update`'s gems section in `lib/workflows.sh` swaps its inline `gem update` call for `update_gems()`, keeping its existing tee-to-tmpdir and `_update_record_end` bookkeeping untouched.

**Tech Stack:** bash 5, rbenv (Linux), ruby-install/chruby (macOS), BATS

## Global Constraints

- No custom/pinned gem list — `gem update` (no args) already covers Ruby's bundled default gems (`bundler`, `rake`, `json`, `minitest`, etc.); nothing to enumerate.
- `update_gems()` MUST NOT change macOS behavior — the existing chruby `bin` dir logic is correct today; only the missing Linux branch is added.
- `recreate_ruby()` MUST fail (`return 1`) on gem-update failure — deliberate departure from `run_update`'s soft-fail gems step, per explicit user decision.
- `run_update`'s gems section MUST keep its existing `UPDATE_GEMS`/`_run_all` gating, soft-fail behavior, and `err_gems` tee output unchanged — only the PATH-prepend logic moves into `update_gems()`.
- No new `setup_env.sh` flag, no new entry point.

## Verification Planning

- **Command:** `make test` from repo root.
- **Expected:** exit 0; final bats summary line shows all tests passing (no `not ok` lines); new tests for `update_gems` (macOS dir, Linux dir, dir-absent), `recreate_ruby` gem-update failure path, and `run_update` Linux gem-precedence all present and green.
- **Edge cases exercised:** macOS chruby dir present/absent, Linux rbenv shims dir present/absent, `recreate_ruby` gem-update failure after a successful ruby install (interpreter install must still have happened), `run_update`'s existing macOS gem-precedence test and gems-flag-gating tests must keep passing unchanged (regression guard that the refactor didn't change `run_update` observable behavior).

---

## Files

- Modify: `lib/developer.sh` — add `update_gems()`, extend `recreate_ruby()`
- Modify: `lib/workflows.sh` — swap `run_update`'s inline gem update call for `update_gems()`
- Modify: `tests/setup_env/install_functions.bats` — `update_gems` tests, `recreate_ruby` gem-update tests
- Modify: `tests/setup_env/workflows.bats` — Linux gem-precedence test for `run_update`
- Modify: `CLAUDE.md` — one-sentence note on `update_gems()` in the Ruby Version Manager Split section

---

### Task 1: Add `update_gems()` to `lib/developer.sh`

```yaml-task
id: 1
description: Add update_gems function with platform-correct gem-dir PATH prepend
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: 'bats tests/setup_env/install_functions.bats -f "update_gems"'
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - lib/developer.sh
  - tests/setup_env/install_functions.bats
depends_on: []
```

**Files:**

- Modify: `lib/developer.sh`
- Test: `tests/setup_env/install_functions.bats`

**Interfaces:**

- Produces: `update_gems()` — no arguments, no return value contract beyond `gem update`'s own exit code (propagated via normal bash function return). Later tasks (`recreate_ruby`, `run_update`) call this function directly.

- [ ] **Step 1: Write the failing tests**

Append to `tests/setup_env/install_functions.bats` (end of file, after the `recreate_ruby` section):

```bash

# ── update_gems ──────────────────────────────────────────────────────────────

@test "update_gems on macOS prepends chruby gem dir so it takes precedence over PATH gem" {
  export MACOS=1
  unset LINUX
  export HOME="${BATS_TEST_TMPDIR}"
  export RUBY_VER="4.0.5"
  export PATH="${BATS_TEST_DIRNAME}/../mocks:${PATH}"
  local _chruby_bin="${HOME}/.rubies/ruby-${RUBY_VER}/bin"
  mkdir -p "${_chruby_bin}"
  cat > "${_chruby_bin}/gem" << 'EOF'
#!/usr/bin/env bash
printf "chruby-gem %s\n" "$*" >> "${MOCK_CALLS_FILE}"
EOF
  chmod +x "${_chruby_bin}/gem"
  update_gems
  grep -q "chruby-gem update" "${MOCK_CALLS_FILE}"
}

@test "update_gems on Linux prepends rbenv shims so it takes precedence over PATH gem" {
  export LINUX=1
  unset MACOS
  export HOME="${BATS_TEST_TMPDIR}"
  export RUBY_VER="4.0.5"
  export PATH="${BATS_TEST_DIRNAME}/../mocks:${PATH}"
  local _shims="${HOME}/.rbenv/shims"
  mkdir -p "${_shims}"
  cat > "${_shims}/gem" << 'EOF'
#!/usr/bin/env bash
printf "shims-gem %s\n" "$*" >> "${MOCK_CALLS_FILE}"
EOF
  chmod +x "${_shims}/gem"
  update_gems
  grep -q "shims-gem update" "${MOCK_CALLS_FILE}"
}

@test "update_gems calls gem update via PATH when platform gem dir absent" {
  export LINUX=1
  unset MACOS
  export HOME="${BATS_TEST_TMPDIR}"
  export RUBY_VER="4.0.5"
  export PATH="${BATS_TEST_DIRNAME}/../mocks:${PATH}"
  update_gems
  grep -q "gem update" "${MOCK_CALLS_FILE}"
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bats tests/setup_env/install_functions.bats -f "update_gems"
```

Expected: fail — `update_gems: command not found`.

- [ ] **Step 3: Implement `update_gems()`**

In `lib/developer.sh`, add after `recreate_ruby()`:

```bash
update_gems() {
  local _ruby_gem_dir=""
  if [[ -n ${MACOS} ]]; then
    _ruby_gem_dir="${HOME}/.rubies/ruby-${RUBY_VER}/bin"
  elif [[ -n ${LINUX} ]]; then
    _ruby_gem_dir="${HOME}/.rbenv/shims"
  fi
  local _extra_gem_path=""
  [[ -d "${_ruby_gem_dir}" ]] && _extra_gem_path="${_ruby_gem_dir}:"
  PATH="${_extra_gem_path}${PATH}" gem update
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bats tests/setup_env/install_functions.bats -f "update_gems"
```

Expected: all 3 new tests pass.

- [ ] **Step 5: Commit**

Invoke `caveman:caveman-commit` to generate the message, then commit:

```bash
git add lib/developer.sh tests/setup_env/install_functions.bats
```

---

### Task 2: Wire `update_gems()` into `recreate_ruby()`

```yaml-task
id: 2
description: Call update_gems after install_ruby in recreate_ruby, fail recreate_ruby on gem-update failure
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: 'bats tests/setup_env/install_functions.bats -f "recreate_ruby"'
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - lib/developer.sh
  - tests/setup_env/install_functions.bats
depends_on: [1]
parallel_group: wave-2
```

**Files:**

- Modify: `lib/developer.sh`
- Test: `tests/setup_env/install_functions.bats`

**Interfaces:**

- Consumes: `update_gems()` from Task 1 (no arguments, propagates `gem update`'s exit code).

- [ ] **Step 1: Write the failing test**

Add to `tests/setup_env/install_functions.bats` in the `── recreate_ruby ──` section, after the existing "returns 1 and skips uninstall when rbenv absent" test:

```bash

@test "recreate_ruby macOS: returns 1 when gem update fails after successful install" {
  export MACOS=1
  unset LINUX
  export HOME="${BATS_TEST_TMPDIR}"
  export RUBY_VER="4.0.5"
  export PATH="${BATS_TEST_DIRNAME}/../mocks:${PATH}"
  export MOCK_GEM_EXIT=1
  mkdir -p "${HOME}/.rubies/ruby-${RUBY_VER}/bin"
  run recreate_ruby
  [ "$status" -ne 0 ]
  [[ "$output" == *"gem update failed after ruby recreate"* ]]
  grep -q "ruby-install" "${MOCK_CALLS_FILE}"
}
```

Also update the two existing happy-path tests in the same section to assert `update_gems` ran:

In `"recreate_ruby macOS: deletes .rubies dir then calls install_ruby"`, add after the existing `grep -q "ruby-install" "${MOCK_CALLS_FILE}"` line:

```bash
  grep -q "gem update" "${MOCK_CALLS_FILE}"
```

In `"recreate_ruby Linux: uninstalls via rbenv then reinstalls with RUBY_CONFIGURE_OPTS"`, add after the existing `grep -q "RUBY_CONFIGURE_OPTS=--with-openssl-dir=/usr" "${MOCK_CALLS_FILE}"` line:

```bash
  grep -q "gem update" "${MOCK_CALLS_FILE}"
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bats tests/setup_env/install_functions.bats -f "recreate_ruby"
```

Expected: the two happy-path tests fail on the new `gem update` grep (no such call yet); the new failure test fails because `recreate_ruby` currently returns 0 unconditionally after `install_ruby`.

- [ ] **Step 3: Extend `recreate_ruby()`**

In `lib/developer.sh`, change the last line of `recreate_ruby()` from:

```bash
  install_ruby || return 1
}
```

to:

```bash
  install_ruby || return 1
  update_gems || { log_error "gem update failed after ruby recreate"; return 1; }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bats tests/setup_env/install_functions.bats -f "recreate_ruby"
```

Expected: all `recreate_ruby` tests pass, including the two updated happy-path tests and the new failure test.

- [ ] **Step 5: Commit**

Invoke `caveman:caveman-commit` to generate the message, then commit:

```bash
git add lib/developer.sh tests/setup_env/install_functions.bats
```

---

### Task 3: Swap `run_update`'s inline gem update call for `update_gems()`

```yaml-task
id: 3
description: Use update_gems in run_update gems section, add Linux precedence regression test
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: 'bats tests/setup_env/workflows.bats -f "gem"'
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - lib/workflows.sh
  - tests/setup_env/workflows.bats
depends_on: [1]
parallel_group: wave-2
```

**Files:**

- Modify: `lib/workflows.sh`
- Test: `tests/setup_env/workflows.bats`

**Interfaces:**

- Consumes: `update_gems()` from Task 1.

- [ ] **Step 1: Write the failing test**

Add to `tests/setup_env/workflows.bats`, after the existing `"run_update gem section prepends ruby-install bin so it takes precedence over PATH gem"` test:

```bash

@test "run_update gem section on Linux prepends rbenv shims so it takes precedence over PATH gem" {
  export LINUX=1
  unset MACOS UBUNTU
  export UBUNTU=1
  export HOME="${BATS_TEST_TMPDIR}"
  export RUBY_VER="4.0.5"
  export UPDATE_GEMS=1
  unset UPDATE_BREW UPDATE_PIP UPDATE_MAS UPDATE_CLAUDE
  local _shims="${HOME}/.rbenv/shims"
  mkdir -p "${_shims}"
  cat > "${_shims}/gem" << 'EOF'
#!/usr/bin/env bash
printf "shims-gem %s\n" "$*" >> "${MOCK_CALLS_FILE}"
EOF
  chmod +x "${_shims}/gem"
  run_update
  grep -q "shims-gem update" "${MOCK_CALLS_FILE}"
}
```

- [ ] **Step 2: Run tests to verify the new test fails**

```bash
bats tests/setup_env/workflows.bats -f "gem"
```

Expected: the new Linux test fails — today's `run_update` gems section hardcodes the macOS chruby dir only, so `PATH` never gets the Linux shims dir prepended and the generic mock `gem` (already on `PATH` from `load_mocks`) is called instead of the shims one.

- [ ] **Step 3: Swap in `update_gems()`**

In `lib/workflows.sh`, in the `── gems ──` section of `run_update` (around line 519-530), change:

```bash
  if [[ ${_run_all} -eq 1 ]] || [[ -n ${UPDATE_GEMS:-} ]]; then
    _update_record_start "gems"
    printf "updating ruby gems\\n"
    local _ruby_gem_dir="${HOME}/.rubies/ruby-${RUBY_VER}/bin"
    local _extra_gem_path=""
    [[ -d "${_ruby_gem_dir}" ]] && _extra_gem_path="${_ruby_gem_dir}:"
    PATH="${_extra_gem_path}${PATH}" gem update 2>&1 | tee "${_DOTFILES_RUN_TMPDIR}/err_gems"
    _update_record_end "gems" "${PIPESTATUS[0]}"
  else
    _update_skip "gems" "flag not set"
  fi
```

to:

```bash
  if [[ ${_run_all} -eq 1 ]] || [[ -n ${UPDATE_GEMS:-} ]]; then
    _update_record_start "gems"
    printf "updating ruby gems\\n"
    update_gems 2>&1 | tee "${_DOTFILES_RUN_TMPDIR}/err_gems"
    _update_record_end "gems" "${PIPESTATUS[0]}"
  else
    _update_skip "gems" "flag not set"
  fi
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bats tests/setup_env/workflows.bats -f "gem"
```

Expected: all gem-related `run_update` tests pass, including the pre-existing macOS precedence test (`"run_update gem section prepends ruby-install bin so it takes precedence over PATH gem"`) and the new Linux one.

- [ ] **Step 5: Commit**

Invoke `caveman:caveman-commit` to generate the message, then commit:

```bash
git add lib/workflows.sh tests/setup_env/workflows.bats
```

---

### Task 4: Document `update_gems()` in `CLAUDE.md`

```yaml-task
id: 4
description: "Add one-sentence note on update_gems() PATH handling (docs-only, no behavior change)"
role: executor
model: haiku
tdd: not-applicable
acceptance:
  - cmd: 'grep -q "update_gems" CLAUDE.md'
    exit_code: 0
max_retries: 3
files_touched:
  - CLAUDE.md
depends_on: [1]
parallel_group: wave-2
```

**Files:**

- Modify: `CLAUDE.md`

**Interfaces:**

- Consumes: none (prose-only reference to `update_gems()` from Task 1).

- [ ] **Step 1: Add the note**

In `CLAUDE.md`, in the `### Ruby Version Manager Split` section, add a sentence after the existing paragraph about `install_ruby()`/`install_ruby_tools()`:

```markdown
`update_gems()` in `lib/developer.sh` handles the platform difference for `gem update`'s `PATH`
prepend — the chruby `bin` dir on macOS, the rbenv `shims` dir on Linux — used by both
`recreate_ruby()` and `run_update`'s gems step.
```

- [ ] **Step 2: Verify**

```bash
grep -q "update_gems" CLAUDE.md
```

- [ ] **Step 3: Commit**

Invoke `caveman:caveman-commit` to generate the message, then commit:

```bash
git add CLAUDE.md
```
