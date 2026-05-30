# Coverage: helpers.sh — Gaps 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Raise `helpers.sh` bash coverage from 83% to ≥90% by adding 10 tests for uncovered code paths.

**Architecture:** Tests only — no production code changes. One brew mock update to support independent formula vs cask upgrade failure injection. Tests appended to existing sections in `install_guards.bats` (6 tests) and `unit.bats` (4 tests).

**Tech Stack:** BATS (bash), PATH-injected mocks, `MOCK_*` env vars, direct function calls for flag assertions.

---

## File Structure

| File                                  | Change                                                 |
| ------------------------------------- | ------------------------------------------------------ |
| `tests/mocks/brew`                    | Add `MOCK_BREW_UPGRADE_CASK_EXIT` to `upgrade)` branch |
| `tests/setup_env/install_guards.bats` | Append 6 tests to existing sections                    |
| `tests/setup_env/unit.bats`           | Append 4 tests to existing sections                    |

---

### Task 1: brew_formula/cask_installed root guard and tap-qualified cask tests

**Files:**

- Modify: `tests/setup_env/install_guards.bats`

These tests cover lines in `brew_formula_installed` and `brew_cask_installed` that call `ensure_not_root` and return early when root. The tap-qualified cask test covers the `*/*` branch that uses `--full-name`.

- [ ] **Step 1: Add 3 tests to `tests/setup_env/install_guards.bats`**

Find the line:

```
@test "brew_formula_installed uses full-name flag for tap-qualified formulas" {
```

Append after the closing `}` of that test, before the `# ── brew_cask_installed ──` section header:

```bash
@test "brew_formula_installed returns 1 when root" {
  export MOCK_ID_U=0
  run brew_formula_installed git
  [ "$status" -eq 1 ]
}
```

Find the line:

```
@test "brew_cask_installed returns 1 when cask is not listed" {
```

Append after the closing `}` of that test, before the `# ── brew_install_formula ──` section header:

```bash
@test "brew_cask_installed returns 1 when root" {
  export MOCK_ID_U=0
  run brew_cask_installed docker
  [ "$status" -eq 1 ]
}

@test "brew_cask_installed uses full-name flag for tap-qualified casks" {
  export MOCK_BREW_LIST_CASK="hashicorp/tap/vault-secrets-operator"
  run brew_cask_installed hashicorp/tap/vault-secrets-operator
  [ "$status" -eq 0 ]
  grep -q "brew list --cask --full-name" "${MOCK_CALLS_FILE}"
}
```

- [ ] **Step 2: Run tests to verify they pass**

```bash
bats tests/setup_env/install_guards.bats
```

Expected: all tests pass including the 3 new ones.

- [ ] **Step 3: Commit**

```bash
git add tests/setup_env/install_guards.bats
git commit -m "test(helpers): cover brew_formula/cask_installed root guard and tap-qualified cask"
```

---

### Task 2: Update brew mock and add brew_update failure tests

**Files:**

- Modify: `tests/mocks/brew`
- Modify: `tests/setup_env/install_guards.bats`

The current brew mock uses one exit code (`MOCK_BREW_UPGRADE_EXIT`) for both `brew upgrade` and `brew upgrade --cask --greedy`. This makes it impossible to test the warn-and-continue path (cask upgrade fails but formula upgrade succeeded). Add `MOCK_BREW_UPGRADE_CASK_EXIT` with fallback to `MOCK_BREW_UPGRADE_EXIT`.

- [ ] **Step 1: Update `tests/mocks/brew`**

Find in `tests/mocks/brew`:

```bash
  upgrade)
    exit "${MOCK_BREW_UPGRADE_EXIT:-0}"
    ;;
```

Replace with:

```bash
  upgrade)
    if [[ "$*" == *"--cask"* ]]; then
      exit "${MOCK_BREW_UPGRADE_CASK_EXIT:-${MOCK_BREW_UPGRADE_EXIT:-0}}"
    fi
    exit "${MOCK_BREW_UPGRADE_EXIT:-0}"
    ;;
```

This is backward-compatible: tests that only set `MOCK_BREW_UPGRADE_EXIT=1` still fail both formula and cask upgrade (because the cask fallback is `MOCK_BREW_UPGRADE_EXIT`).

- [ ] **Step 2: Add 3 tests to `tests/setup_env/install_guards.bats`**

Find the closing `}` of the test:

```
@test "brew_update does not proceed past install_homebrew when install_homebrew fails" {
```

Append after that `}`, before the `# ── safe_link ──` section header:

```bash
@test "brew_update returns 1 when brew upgrade fails" {
  export MOCK_ID_U=1000
  export MOCK_BREW_UPGRADE_EXIT=1
  run brew_update
  [ "$status" -eq 1 ]
  [[ "$output" == *"Failed to upgrade formulae"* ]]
}

@test "brew_update warns but continues when cask upgrade fails" {
  export MOCK_ID_U=1000
  export MOCK_BREW_UPGRADE_CASK_EXIT=1
  run brew_update
  [ "$status" -eq 0 ]
  [[ "$output" == *"Some casks failed to upgrade"* ]]
  [[ "$output" == *"Homebrew update process completed successfully"* ]]
}

@test "brew_update returns 1 when brew cleanup fails" {
  export MOCK_ID_U=1000
  export MOCK_BREW_CLEANUP_EXIT=1
  run brew_update
  [ "$status" -eq 1 ]
  [[ "$output" == *"Failed to clean up"* ]]
}
```

- [ ] **Step 3: Run tests to verify they pass**

```bash
bats tests/setup_env/install_guards.bats
```

Expected: all tests pass including the 3 new ones. Verify existing `brew_update returns 1 when brew update fails` still passes (backward-compat check for the mock change).

- [ ] **Step 4: Commit**

```bash
git add tests/mocks/brew tests/setup_env/install_guards.bats
git commit -m "test(helpers): cover brew_update upgrade and cleanup failure branches"
```

---

### Task 3: \_doctor_check_github_mcp expiry parse failure and expired tests

**Files:**

- Modify: `tests/setup_env/unit.bats`

Two uncovered paths in `_doctor_check_github_mcp`:

1. `_expiry_epoch` is empty because `date` could not parse `GITHUB_PAT_EXPIRY` → `doctor_warn`
2. `_diff_days <= 0` (PAT expired) → `doctor_fail`

These tests use **direct calls** (not `run`) so the `_DOCTOR_*` flag counters are visible in the test's shell.

Setup pattern (same as existing expiry tests): set `_DOCTOR_*` counters to 0, create `mcp.json`, set `GITHUB_PAT`, set `MOCK_CURL_EXIT=0`, then call `_doctor_check_github_mcp` directly.

- [ ] **Step 1: Add 2 tests to `tests/setup_env/unit.bats`**

Append at the end of the file, after the closing `}` of:

```
@test "_doctor_check_github_mcp passes when all checks pass" {
```

```bash
@test "_doctor_check_github_mcp warns when GITHUB_PAT_EXPIRY cannot be parsed" {
  _DOCTOR_FAIL=0; _DOCTOR_FAILED=0; _DOCTOR_PASS=0; _DOCTOR_WARN=0
  export GITHUB_PAT="fake-token"
  mkdir -p "${HOME}/.claude"
  printf '{"mcpServers":{}}\n' > "${HOME}/.claude/mcp.json"
  export MOCK_CURL_EXIT=0
  export GITHUB_PAT_EXPIRY="not-a-date"
  _doctor_check_github_mcp
  [ "${_DOCTOR_WARN}" -ge 1 ]
}

@test "_doctor_check_github_mcp fails when GITHUB_PAT has expired" {
  _DOCTOR_FAIL=0; _DOCTOR_FAILED=0; _DOCTOR_PASS=0; _DOCTOR_WARN=0
  export GITHUB_PAT="fake-token"
  mkdir -p "${HOME}/.claude"
  printf '{"mcpServers":{}}\n' > "${HOME}/.claude/mcp.json"
  export MOCK_CURL_EXIT=0
  export GITHUB_PAT_EXPIRY="2020-01-01"
  _doctor_check_github_mcp
  [ "${_DOCTOR_FAILED}" -ge 1 ]
}
```

- [ ] **Step 2: Run tests to verify they pass**

```bash
bats tests/setup_env/unit.bats
```

Expected: all tests pass including the 2 new ones.

- [ ] **Step 3: Commit**

```bash
git add tests/setup_env/unit.bats
git commit -m "test(helpers): cover _doctor_check_github_mcp expiry parse failure and expired paths"
```

---

### Task 4: \_doctor_check_tools Linux apt-get tests

**Files:**

- Modify: `tests/setup_env/unit.bats`

Two uncovered lines in `_doctor_check_tools`: the `LINUX` + `UBUNTU` + apt-get found/missing branches. Existing tests for this function override `_doctor_check_tools` with a stub — they do NOT call the real implementation. These two tests call the real function.

`apt-get` exists in `tests/mocks/` so the "found" test works with normal test PATH. For the "missing" test, use a filtered mocks dir (all mocks except `apt-get`) as a minimal PATH, following the pattern from BATS pitfall #14 (Ubuntu Noble `/bin → /usr/bin` symlink defeats directory stripping — minimal PATH is the safe approach).

Restore `PATH` immediately after the call, before assertions — BATS teardown needs `bash` in `PATH`.

- [ ] **Step 1: Add 2 tests to `tests/setup_env/unit.bats`**

Find the closing `}` of:

```
@test "_doctor_check_tools fails for a tool that is missing" {
```

Append after that `}`, before the `# ── _doctor_check_cred_dirs ──` section header:

```bash
@test "_doctor_check_tools passes apt-get when found on Ubuntu" {
  _DOCTOR_FAIL=0; _DOCTOR_FAILED=0; _DOCTOR_PASS=0; _DOCTOR_WARN=0
  export LINUX=1; export UBUNTU=1; unset MACOS
  _doctor_check_tools
  [ "${_DOCTOR_FAILED}" -eq 0 ]
}

@test "_doctor_check_tools fails when apt-get is missing on Ubuntu" {
  _DOCTOR_FAIL=0; _DOCTOR_FAILED=0; _DOCTOR_PASS=0; _DOCTOR_WARN=0
  export LINUX=1; export UBUNTU=1; unset MACOS
  local _saved_path="$PATH"
  local _mocks_dir; _mocks_dir="$(cd "${BATS_TEST_DIRNAME}/../mocks" && pwd)"
  local _tmp="${BATS_TEST_TMPDIR}/mocks_no_apt"
  mkdir -p "${_tmp}"
  for f in "${_mocks_dir}/"*; do
    [[ "$(basename "$f")" == "apt-get" ]] && continue
    ln -sf "$f" "${_tmp}/$(basename "$f")"
  done
  export PATH="${_tmp}"
  _doctor_check_tools
  export PATH="${_saved_path}"
  [ "${_DOCTOR_FAILED}" -ge 1 ]
}
```

- [ ] **Step 2: Run tests to verify they pass**

```bash
bats tests/setup_env/unit.bats
```

Expected: all tests pass including the 2 new ones.

- [ ] **Step 3: Commit**

```bash
git add tests/setup_env/unit.bats
git commit -m "test(helpers): cover _doctor_check_tools Linux apt-get found and missing paths"
```

---

### Task 5: Verify full suite and open PR

**Files:** none

- [ ] **Step 1: Run full test suite**

```bash
make test
```

Expected: all 693 tests pass (683 before + 10 new).

- [ ] **Step 2: Open PR**

```bash
gh pr create --title "test(coverage): raise helpers.sh coverage from 83% to ≥90%" --body "$(cat <<'EOF'
## Summary
- Add 10 BATS tests covering uncovered paths in `helpers.sh`
- Update `tests/mocks/brew` to support `MOCK_BREW_UPGRADE_CASK_EXIT` (independent formula/cask upgrade failure injection)
- No production code changes

## Test Plan
- [ ] `make test` passes (693 tests)
- [ ] New tests exercise: `brew_formula/cask_installed` root guards, `brew_cask_installed` tap-qualified path, `brew_update` upgrade/cask-upgrade/cleanup failures, `_doctor_check_github_mcp` expiry parse failure and expired paths, `_doctor_check_tools` Linux apt-get found/missing
EOF
)"
```

- [ ] **Step 3: Monitor CI until green**

```bash
gh pr checks --watch
```

Expected: all checks pass, PR auto-merges.

- [ ] **Step 4: Post-merge cleanup** _(Do this directly on main after the PR merges — not inside the worktree)_

```bash
# On main branch (not in worktree):
# 1. Update docs/superpowers/README.md: move coverage-helpers-gaps-2 from backlog to All Plans table (Done)
# 2. Add > **Status: DONE** banner to this plan file
# 3. Update CLAUDE.md: change test count from 683 to 693
# 4. Push the docs commits immediately (don't wait — they'll be wiped if not pushed before next PR merges)
git add docs/superpowers/README.md docs/superpowers/plans/2026-05-29-coverage-helpers-gaps-2.md CLAUDE.md
git commit -m "docs(coverage): mark coverage-helpers-gaps-2 Done"
git push origin master
```
