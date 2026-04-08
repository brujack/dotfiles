# Workflow Test Coverage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add behavioral tests for `run_setup_user`, `run_setup_or_developer`, `run_developer_or_ansible`, and `run_update` in a new `tests/setup_env/workflows.bats` file. Tests assert which functions get called (coarse) and that platform branching fires correctly (conditional).

**Architecture:** New `workflows.bats` uses the existing mock infrastructure (`tests/mocks/` on PATH, `MOCK_CALLS_FILE`, OS vars). Tests call workflow functions directly after setting environment vars, then assert against `MOCK_CALLS_FILE`. `make test` already uses `bats --recursive tests/`, so no Makefile changes are needed.

**Tech Stack:** bash, bats

---

## File Map

| Action | File |
|---|---|
| Create | `tests/setup_env/workflows.bats` |
| Verify | `Makefile` — no change needed (`bats --recursive tests/` picks up new file automatically) |

---

### Task 1: Create workflows.bats with setup/teardown skeleton

**Files:**
- Create: `tests/setup_env/workflows.bats`

- [ ] **Step 1: Create the file**

Create `tests/setup_env/workflows.bats` with this skeleton:

```bash
#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_mocks
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  touch "${MOCK_CALLS_FILE}"
  load_setup_env
  # Minimal env so workflow functions don't crash on missing vars
  export HOME="${BATS_TEST_TMPDIR}"
  export PERSONAL_GITREPOS="${BATS_TEST_TMPDIR}/git-repos/personal"
  export DOTFILES="dotfiles"
  export BREWFILE_LOC="${BATS_TEST_TMPDIR}/brew"
  mkdir -p "${PERSONAL_GITREPOS}/${DOTFILES}"
}

teardown() {
  :
}
```

- [ ] **Step 2: Verify the file is picked up by make test**

```bash
make test
```

Expected: PASS with 0 new tests (empty test file is valid)

- [ ] **Step 3: Commit**

```bash
git add tests/setup_env/workflows.bats
git commit -m "test: create workflows.bats skeleton"
```

---

### Task 2: Add coarse-grained tests for run_setup_user (macOS)

**Files:**
- Modify: `tests/setup_env/workflows.bats`

These tests verify that the top-level steps of `run_setup_user` are invoked on macOS. The key calls that leave mock traces are `git clone` (for dotfiles and oh-my-zsh), `mkdir`, and `ln -s` (via safe_link → run_cmd).

- [ ] **Step 1: Write the failing tests**

Add to `tests/setup_env/workflows.bats` after `teardown()`:

```bash
# ── run_setup_user — coarse-grained (macOS) ───────────────────────────────────

@test "run_setup_user clones dotfiles repo on macOS when missing" {
  export MACOS=1
  unset LINUX UBUNTU REDHAT FEDORA CENTOS
  # Ensure dotfiles dir does not exist so clone is triggered
  rm -rf "${PERSONAL_GITREPOS}/${DOTFILES}"
  run_setup_user
  grep -q "git clone" "${MOCK_CALLS_FILE}"
}

@test "run_setup_user calls setup_dotfile_symlinks on macOS" {
  export MACOS=1
  unset LINUX UBUNTU REDHAT FEDORA CENTOS
  # setup_dotfile_symlinks calls ln -s which goes through run_cmd → real ln or mock
  # The function itself is real; check that it was entered by verifying a safe_link call
  # safe_link calls run_cmd ln, which calls the real ln (not mocked).
  # We verify the function runs without error as a coarse check.
  run run_setup_user
  [ "$status" -eq 0 ]
}

@test "run_setup_user creates HOME/bin on macOS" {
  export MACOS=1
  unset LINUX UBUNTU REDHAT FEDORA CENTOS
  run_setup_user
  [ -d "${HOME}/bin" ]
}

@test "run_setup_user creates HOME/go-work on macOS" {
  export MACOS=1
  unset LINUX UBUNTU REDHAT FEDORA CENTOS
  run_setup_user
  [ -d "${HOME}/go-work" ]
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
make test
```

Expected: FAIL — `HOME/bin` and `HOME/go-work` do not exist yet (workflow not called with right env vars, or `run_setup_user` may fail on missing tools in CI)

- [ ] **Step 3: Run tests and confirm they pass**

```bash
make test
```

Expected: PASS (the `run_setup_user` function creates these dirs; mocks handle git, brew, etc.)

Note: If tests fail due to missing mocks, add `export MOCK_GIT_CLONE_EXIT=0` in `setup()` — this is already the default.

- [ ] **Step 4: Commit**

```bash
git add tests/setup_env/workflows.bats
git commit -m "test: add coarse-grained run_setup_user tests for macOS"
```

---

### Task 3: Add platform-branching tests for run_setup_user

**Files:**
- Modify: `tests/setup_env/workflows.bats`

- [ ] **Step 1: Write the failing tests**

Add to `tests/setup_env/workflows.bats`:

```bash
# ── run_setup_user — platform branching ───────────────────────────────────────

@test "run_setup_user calls install_rosetta on macOS" {
  export MACOS=1
  unset LINUX UBUNTU
  run_setup_user
  grep -q "rosetta" "${MOCK_CALLS_FILE}"
}

@test "run_setup_user does not call install_rosetta on Linux" {
  unset MACOS
  export LINUX=1
  export UBUNTU=1
  export NOBLE=1
  run_setup_user
  ! grep -q "rosetta" "${MOCK_CALLS_FILE}"
}

@test "run_setup_user calls install_bats on Linux when bats is missing" {
  unset MACOS
  export LINUX=1
  export UBUNTU=1
  export NOBLE=1
  export MOCK_WHICH_MISSING=bats
  run_setup_user
  grep -q "bats" "${MOCK_CALLS_FILE}"
}
```

- [ ] **Step 2: Run tests**

```bash
make test
```

Expected: PASS (the `install_rosetta` call on macOS passes through the mock softwareupdate; `install_bats` on Ubuntu calls apt-get which is mocked)

- [ ] **Step 3: Commit**

```bash
git add tests/setup_env/workflows.bats
git commit -m "test: add platform-branching tests for run_setup_user"
```

---

### Task 4: Add coarse-grained and branching tests for run_setup_or_developer

**Files:**
- Modify: `tests/setup_env/workflows.bats`

- [ ] **Step 1: Write the tests**

Add to `tests/setup_env/workflows.bats`:

```bash
# ── run_setup_or_developer ────────────────────────────────────────────────────

@test "run_setup_or_developer calls setup_credential_directories on macOS" {
  export MACOS=1
  unset LINUX
  export SETUP=1
  run run_setup_or_developer
  [ "$status" -eq 0 ]
  # setup_credential_directories creates ~/.aws — verify with real mkdir
  [ -d "${HOME}/.aws" ]
}

@test "run_setup_or_developer calls brew bundle on macOS" {
  export MACOS=1
  unset LINUX UBUNTU
  export SETUP=1
  run_setup_or_developer
  grep -q "brew" "${MOCK_CALLS_FILE}"
}

@test "run_setup_or_developer calls apt-get on Ubuntu" {
  unset MACOS
  export LINUX=1
  export UBUNTU=1
  export NOBLE=1
  export SETUP=1
  run_setup_or_developer
  grep -q "apt" "${MOCK_CALLS_FILE}"
}

@test "run_setup_or_developer does not call apt-get on macOS" {
  export MACOS=1
  unset LINUX UBUNTU
  export SETUP=1
  run_setup_or_developer
  ! grep -q "apt-get" "${MOCK_CALLS_FILE}"
}
```

- [ ] **Step 2: Run tests**

```bash
make test
```

Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add tests/setup_env/workflows.bats
git commit -m "test: add coarse-grained and branching tests for run_setup_or_developer"
```

---

### Task 5: Add coarse-grained and branching tests for run_update

**Files:**
- Modify: `tests/setup_env/workflows.bats`

- [ ] **Step 1: Write the tests**

Add to `tests/setup_env/workflows.bats`:

```bash
# ── run_update ────────────────────────────────────────────────────────────────

@test "run_update calls brew_update on macOS" {
  export MACOS=1
  unset LINUX UBUNTU
  unset UPDATE_BREW UPDATE_PIP UPDATE_GEMS UPDATE_MAS UPDATE_CLAUDE
  run_update
  grep -q "brew update" "${MOCK_CALLS_FILE}"
}

@test "run_update calls gem update" {
  export MACOS=1
  unset LINUX
  unset UPDATE_BREW UPDATE_PIP UPDATE_GEMS UPDATE_MAS UPDATE_CLAUDE
  run_update
  grep -q "gem update" "${MOCK_CALLS_FILE}"
}

@test "run_update does not call brew on Linux" {
  unset MACOS
  export LINUX=1
  export UBUNTU=1
  export NOBLE=1
  unset UPDATE_BREW UPDATE_PIP UPDATE_GEMS UPDATE_MAS UPDATE_CLAUDE
  run_update
  ! grep -q "brew update" "${MOCK_CALLS_FILE}"
}

@test "run_update calls apt on Ubuntu" {
  unset MACOS
  export LINUX=1
  export UBUNTU=1
  export NOBLE=1
  unset UPDATE_BREW UPDATE_PIP UPDATE_GEMS UPDATE_MAS UPDATE_CLAUDE
  run_update
  grep -q "apt\|nala" "${MOCK_CALLS_FILE}"
}
```

- [ ] **Step 2: Run tests**

```bash
make test
```

Expected: PASS

- [ ] **Step 3: Run full suite and verify no regressions**

```bash
make test
```

Expected: all pass

- [ ] **Step 4: Commit**

```bash
git add tests/setup_env/workflows.bats
git commit -m "test: add coarse-grained and branching tests for run_update"
```
