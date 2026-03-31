# Phase 2: Hardening — Logging and Safe Symlinks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `log_info`/`log_warn`/`log_error` colored logging helpers and `safe_link()` idempotent symlink function to `lib/helpers.sh`, then migrate all `printf` informational calls and `rm -f + ln -s` patterns throughout `lib/*.sh`.

**Architecture:** All three logging functions use ANSI color codes with bracketed prefixes. `log_warn` and `log_error` write to stderr. `safe_link()` is a no-op for existing symlinks, backs up regular files with `.bak` suffix before overwriting, and uses `log_warn` for the backup notification. Migration of `printf` to `log_*` is mechanical — informational messages use `log_info`, error exits use `log_error`, and `printf` inside `usage()` (which formats help text with deliberate formatting) is left unchanged.

**Tech Stack:** Bash, BATS, `BATS_TEST_TMPDIR` for safe_link filesystem tests

---

## Files

| File | Action |
|---|---|
| `lib/helpers.sh` | Modify — add logging constants + functions + safe_link() |
| `lib/constants.sh` | Modify — replace printf calls with log_info/log_error |
| `lib/detect_env.sh` | Modify — replace printf calls with log_info/log_error |
| `lib/macos.sh` | Modify — replace printf calls with log_info/log_error |
| `lib/linux.sh` | Modify — replace printf calls with log_info/log_error |
| `lib/developer.sh` | Modify — replace printf calls with log_info/log_error |
| `tests/setup_env/unit.bats` | Modify — add logging function tests |
| `tests/setup_env/install_guards.bats` | Modify — add safe_link tests |

---

## Task 1: Write failing tests for logging functions

**Files:**
- Modify: `tests/setup_env/unit.bats`

- [ ] **Step 1: Add the failing logging tests to `tests/setup_env/unit.bats`**

Append to the end of the file:

```bash
# ── logging helpers ───────────────────────────────────────────────────────────

@test "log_info output contains [INFO] prefix" {
  run log_info "test message"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[INFO]"* ]]
}

@test "log_info output contains the message" {
  run log_info "hello world"
  [ "$status" -eq 0 ]
  [[ "$output" == *"hello world"* ]]
}

@test "log_warn output contains [WARN] prefix" {
  run log_warn "test warning"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[WARN]"* ]]
}

@test "log_error output contains [ERROR] prefix" {
  run log_error "test error"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[ERROR]"* ]]
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
make test-unit
```

Expected: FAIL — `log_info output contains [INFO] prefix` fails because `log_info` is not defined yet.

---

## Task 2: Add logging to `lib/helpers.sh`

**Files:**
- Modify: `lib/helpers.sh`

- [ ] **Step 1: Add logging constants and functions at the top of `lib/helpers.sh`** (after the shebang line)

Insert after `#!/usr/bin/env bash`:

```bash
# Logging helpers
readonly _RED='\033[0;31m'
readonly _YELLOW='\033[0;33m'
readonly _GREEN='\033[0;32m'
readonly _NC='\033[0m'

log_info()  { printf "${_GREEN}[INFO]${_NC}  %s\n" "$*"; }
log_warn()  { printf "${_YELLOW}[WARN]${_NC}  %s\n" "$*" >&2; }
log_error() { printf "${_RED}[ERROR]${_NC} %s\n" "$*" >&2; }
```

- [ ] **Step 2: Run the logging tests to confirm they pass**

```bash
make test-unit
```

Expected: all four logging tests PASS.

- [ ] **Step 3: Run the full test suite**

```bash
make test
```

Expected: exit 0.

- [ ] **Step 4: Commit**

```bash
git add lib/helpers.sh tests/setup_env/unit.bats
git commit -m "feat: add log_info/log_warn/log_error helpers to lib/helpers.sh

Colored, prefixed logging functions with [INFO]/[WARN]/[ERROR] brackets.
warn and error write to stderr.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 3: Write failing tests for `safe_link()`

**Files:**
- Modify: `tests/setup_env/install_guards.bats`

- [ ] **Step 1: Add the failing safe_link tests to `tests/setup_env/install_guards.bats`**

Append to the end of the file:

```bash
# ── safe_link ─────────────────────────────────────────────────────────────────

@test "safe_link creates symlink when dest does not exist" {
  local src="${BATS_TEST_TMPDIR}/src_file"
  local dest="${BATS_TEST_TMPDIR}/dest_link"
  touch "${src}"
  run safe_link "${src}" "${dest}"
  [ "$status" -eq 0 ]
  [ -L "${dest}" ]
}

@test "safe_link is a no-op when dest is already a symlink" {
  local src="${BATS_TEST_TMPDIR}/src_file"
  local dest="${BATS_TEST_TMPDIR}/dest_link"
  touch "${src}"
  ln -s "${src}" "${dest}"
  run safe_link "${src}" "${dest}"
  [ "$status" -eq 0 ]
  [ -L "${dest}" ]
}

@test "safe_link backs up existing regular file then creates symlink" {
  local src="${BATS_TEST_TMPDIR}/src_file"
  local dest="${BATS_TEST_TMPDIR}/dest_file"
  touch "${src}"
  touch "${dest}"
  run safe_link "${src}" "${dest}"
  [ "$status" -eq 0 ]
  [ -L "${dest}" ]
  [ -f "${dest}.bak" ]
}

@test "safe_link symlink points to the correct source" {
  local src="${BATS_TEST_TMPDIR}/src_file"
  local dest="${BATS_TEST_TMPDIR}/dest_link"
  touch "${src}"
  safe_link "${src}" "${dest}"
  local target
  target=$(readlink "${dest}")
  [ "${target}" = "${src}" ]
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
bats tests/setup_env/install_guards.bats
```

Expected: FAIL — `safe_link creates symlink when dest does not exist` fails because `safe_link` is not defined yet.

---

## Task 4: Add `safe_link()` to `lib/helpers.sh`

**Files:**
- Modify: `lib/helpers.sh`

- [ ] **Step 1: Add `safe_link()` to `lib/helpers.sh`** (after the logging functions, before the existing helper functions)

```bash
safe_link() {
  local src="$1" dest="$2"
  if [[ -L "${dest}" ]]; then
    return 0  # already a symlink, nothing to do
  fi
  if [[ -e "${dest}" ]]; then
    log_warn "Backing up existing file: ${dest} → ${dest}.bak"
    mv "${dest}" "${dest}.bak"
  fi
  ln -s "${src}" "${dest}"
  log_info "Linked ${dest} → ${src}"
}
```

- [ ] **Step 2: Run the safe_link tests to confirm they pass**

```bash
bats tests/setup_env/install_guards.bats
```

Expected: all four safe_link tests PASS.

- [ ] **Step 3: Run the full test suite**

```bash
make test
```

Expected: exit 0.

- [ ] **Step 4: Commit**

```bash
git add lib/helpers.sh tests/setup_env/install_guards.bats
git commit -m "feat: add safe_link() to lib/helpers.sh

Idempotent symlink creation: no-op for existing symlinks,
backs up regular files with .bak before linking.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 5: Migrate `printf` calls to `log_*` in `lib/*.sh`

**Files:**
- Modify: `lib/constants.sh`, `lib/helpers.sh`, `lib/detect_env.sh`, `lib/macos.sh`, `lib/linux.sh`, `lib/developer.sh`

Rules:
- Informational messages: `printf "Installing...\n"` → `log_info "Installing..."`
- Error exits: `printf "Error...\n" >&2` → `log_error "Error..."` (log_error already writes to stderr)
- Non-fatal warnings: `printf "Warning...\n"` → `log_warn "Warning..."`
- Leave `printf` inside `usage()` unchanged — it formats help text with deliberate indentation
- Leave `printf` inside the prereq check in `setup_env.sh` unchanged — it runs before lib/ is sourced

The migration is mechanical. For each `lib/*.sh` file:

- [ ] **Step 1: Migrate `lib/macos.sh`**

Replace every `printf "...\n"` informational line with `log_info "..."`.
Replace every `printf "...\n" >&2` error line with `log_error "..."`.

Example transformation:
```bash
# Before
printf "Installing Rosetta...\n"

# After
log_info "Installing Rosetta..."
```

- [ ] **Step 2: Migrate `lib/linux.sh`**

Same pattern as macos.sh.

- [ ] **Step 3: Migrate `lib/developer.sh`**

Same pattern.

- [ ] **Step 4: Migrate `lib/detect_env.sh`**

Same pattern.

- [ ] **Step 5: Migrate `lib/helpers.sh`** (non-logging, non-usage functions)

Replace informational printf calls in functions like `brew_install_formula`, `brew_install_cask`, etc.

- [ ] **Step 6: Validate syntax of all modified files**

```bash
make lint
```

Expected: `bash OK` and `zsh OK` for all files.

- [ ] **Step 7: Run the full test suite**

```bash
make test
```

Expected: exit 0.

- [ ] **Step 8: Commit**

```bash
git add lib/
git commit -m "refactor: migrate printf calls to log_info/log_warn/log_error in lib/*.sh

All informational output now uses structured, colored logging helpers.
usage() printf calls left unchanged (intentional help text formatting).

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 6: Migrate `setup_dotfile_symlinks()` to use `safe_link()`

**Files:**
- Modify: `lib/helpers.sh` (where `setup_dotfile_symlinks` lives after Phase 1)

- [ ] **Step 1: Replace all `rm -f + ln -s` pairs in `setup_dotfile_symlinks()`**

For every pattern like:
```bash
rm -f ${HOME}/.zshrc
ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.devcontainer/.zshrc ${HOME}/.zshrc
```

Replace with:
```bash
safe_link "${PERSONAL_GITREPOS}/${DOTFILES}/.devcontainer/.zshrc" "${HOME}/.zshrc"
```

There are approximately 15-20 such pairs in `setup_dotfile_symlinks()`. Replace all of them.

- [ ] **Step 2: Validate syntax**

```bash
bash -n lib/helpers.sh && printf "bash  OK\n"
zsh  -n lib/helpers.sh && printf "zsh   OK\n"
```

Expected: both OK.

- [ ] **Step 3: Run the full test suite**

```bash
make test
```

Expected: exit 0.

- [ ] **Step 4: Commit**

```bash
git add lib/helpers.sh
git commit -m "refactor: replace rm -f + ln -s with safe_link in setup_dotfile_symlinks

safe_link backs up existing files and is a no-op for existing symlinks,
making repeated runs of setup_user safe and predictable.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```
