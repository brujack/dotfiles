# Brewfile Drift: Use `brew leaves` for Untracked Detection

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `brew list --formula` with `brew leaves` for untracked formula detection so transitive dependencies no longer appear as drift noise.

**Architecture:** Two-set approach — `brew leaves` (top-level installs only) for the "untracked" comparison, `brew list --formula` (all installed) for the "missing" comparison. Mock gets a new `leaves` case. All existing drift tests that run with `MACOS=1` and reach formula comparison need `MOCK_BREW_LEAVES` set.

**Tech Stack:** Bash, BATS

---

## Files

- Modify: `tests/mocks/brew` — add `leaves` subcommand case
- Modify: `tests/setup_env/brewfile_drift.bats` — add `MOCK_BREW_LEAVES` to teardown; update affected tests; add one new RED→GREEN test
- Modify: `lib/update_summary.sh:448-458` — replace single formula set with two sets; update `comm` calls
- Modify: `CLAUDE.md` — add `MOCK_BREW_LEAVES` to mock env var table

---

## Task 1: Add `leaves` case to the brew mock

**Files:**

- Modify: `tests/mocks/brew`
- Modify: `tests/setup_env/brewfile_drift.bats` (teardown only)

- [ ] **Step 1: Add the `leaves` case to `tests/mocks/brew`**

  Insert the `leaves)` case immediately before the existing `list)` case. The full mock after the change:

  ```bash
  #!/usr/bin/env bash
  printf "brew %s\n" "$*" >> "${MOCK_CALLS_FILE:-/tmp/mock_calls}"

  case "$1" in
    leaves)
      printf "%s\n" ${MOCK_BREW_LEAVES:-}
      exit 0
      ;;
    list)
      if [[ "$*" == *"--cask"* ]]; then
        printf "%s\n" ${MOCK_BREW_LIST_CASK:-}
      else
        printf "%s\n" ${MOCK_BREW_LIST_FORMULA:-}
      fi
      exit 0
      ;;
    tap)
      if [[ $# -eq 1 ]]; then
        printf "%s\n" ${MOCK_BREW_TAPS:-}
        exit 0
      fi
      exit "${MOCK_BREW_TAP_EXIT:-0}"
      ;;
    install)
      exit "${MOCK_BREW_INSTALL_EXIT:-0}"
      ;;
    update)
      exit "${MOCK_BREW_UPDATE_EXIT:-0}"
      ;;
    upgrade)
      exit "${MOCK_BREW_UPGRADE_EXIT:-0}"
      ;;
    cleanup)
      exit "${MOCK_BREW_CLEANUP_EXIT:-0}"
      ;;
    *)
      exit "${MOCK_BREW_EXIT:-0}"
      ;;
  esac
  ```

- [ ] **Step 2: Add `MOCK_BREW_LEAVES` to teardown in `tests/setup_env/brewfile_drift.bats`**

  ```bash
  teardown() {
    unset _OVERRIDE_BREWFILE_PATH
    unset MOCK_BREW_LEAVES
    unset MOCK_BREW_LIST_FORMULA
    unset MOCK_BREW_LIST_CASK
    unset MOCK_BREW_TAPS
    unset MOCK_WHICH_MISSING
    unset MACOS
  }
  ```

- [ ] **Step 3: Run tests to confirm existing tests still pass**

  ```bash
  cd /path/to/repo && make test 2>&1 | tail -10
  ```

  Expected: `555` tests pass, exit 0.

- [ ] **Step 4: Commit**

  ```bash
  git add tests/mocks/brew tests/setup_env/brewfile_drift.bats
  git commit -m "test: add brew leaves mock case and teardown"
  ```

---

## Task 2: Write the failing test (RED)

This test proves the current implementation has the transitive dep noise problem and will be the RED→GREEN signal for Task 3.

**Files:**

- Modify: `tests/setup_env/brewfile_drift.bats`

- [ ] **Step 1: Add the new test after the "OK when formulae and taps match" test (after line 67)**

  ```bash
  @test "_update_check_brewfile_drift: OK when formula is dep of another — not flagged untracked" {
    export MACOS=1
    printf 'brew "git"\n' > "${BATS_TEST_TMPDIR}/Brewfile"
    export _OVERRIDE_BREWFILE_PATH="${BATS_TEST_TMPDIR}/Brewfile"
    # brew leaves returns only top-level installs; openssl/zstd are transitive deps
    export MOCK_BREW_LEAVES="git"
    export MOCK_BREW_LIST_FORMULA="git openssl zstd"
    export MOCK_BREW_TAPS=""
    run _update_check_brewfile_drift
    [ "$status" -eq 0 ]
    [ "$(cat "${_UPDATE_TMPDIR}/status_brew-drift")" = "OK" ]
    [ ! -f "${_UPDATE_TMPDIR}/detail_brew-drift" ]
  }
  ```

- [ ] **Step 2: Run the new test to confirm it fails**

  ```bash
  cd /path/to/repo && make test 2>&1 | grep "not flagged untracked"
  ```

  Expected: `not ok ... OK when formula is dep of another — not flagged untracked`

  The failure happens because the current implementation uses `brew list --formula`, which returns `git openssl zstd` via `MOCK_BREW_LIST_FORMULA`. `openssl` and `zstd` are not in the Brewfile so they appear as untracked → status is WARN, not OK.

- [ ] **Step 3: Commit the failing test**

  ```bash
  git add tests/setup_env/brewfile_drift.bats
  git commit -m "test: red — transitive deps should not appear as untracked formulae"
  ```

---

## Task 3: Implement two-set approach and update existing tests (GREEN)

**Files:**

- Modify: `lib/update_summary.sh:448-458`
- Modify: `tests/setup_env/brewfile_drift.bats`

- [ ] **Step 1: Replace the single formula capture in `lib/update_summary.sh`**

  Find (around line 447-448):

  ```bash
    # Get actual installed state
    brew list --formula 2>/dev/null | sort > "${_UPDATE_TMPDIR}/drift_inst_formulae"
  ```

  Replace with:

  ```bash
    # Get actual installed state — two sets:
    # leaves: top-level installs only (for untracked detection, filters transitive deps)
    # all: every installed formula (for missing detection, avoids false positives)
    brew leaves 2>/dev/null | sort > "${_UPDATE_TMPDIR}/drift_inst_formulae_leaves"
    brew list --formula 2>/dev/null | sort > "${_UPDATE_TMPDIR}/drift_inst_formulae_all"
  ```

- [ ] **Step 2: Update the `comm` comparisons for formula drift**

  Find (around line 454-458):

  ```bash
    _untracked_formulae=$(comm -13 "${_UPDATE_TMPDIR}/drift_bf_formulae" \
      "${_UPDATE_TMPDIR}/drift_inst_formulae")
    _missing_formulae=$(comm -23 "${_UPDATE_TMPDIR}/drift_bf_formulae" \
      "${_UPDATE_TMPDIR}/drift_inst_formulae")
  ```

  Replace with:

  ```bash
    _untracked_formulae=$(comm -13 "${_UPDATE_TMPDIR}/drift_bf_formulae" \
      "${_UPDATE_TMPDIR}/drift_inst_formulae_leaves")
    _missing_formulae=$(comm -23 "${_UPDATE_TMPDIR}/drift_bf_formulae" \
      "${_UPDATE_TMPDIR}/drift_inst_formulae_all")
  ```

- [ ] **Step 3: Update the existing formula drift tests in `brewfile_drift.bats`**

  The tests below reach formula comparison (they run with `MACOS=1` and don't return early). Each needs `MOCK_BREW_LEAVES` set so the leaves comparison works correctly.

  **"OK when formulae and taps match"** — set leaves to same as the full list:

  ```bash
  @test "_update_check_brewfile_drift: OK when formulae and taps match" {
    export MACOS=1
    printf 'brew "bat"\nbrew "git"\n' > "${BATS_TEST_TMPDIR}/Brewfile"
    export _OVERRIDE_BREWFILE_PATH="${BATS_TEST_TMPDIR}/Brewfile"
    export MOCK_BREW_LEAVES="bat git"
    export MOCK_BREW_LIST_FORMULA="bat git"
    export MOCK_BREW_TAPS=""
    run _update_check_brewfile_drift
    [ "$status" -eq 0 ]
    [ "$(cat "${_UPDATE_TMPDIR}/status_brew-drift")" = "OK" ]
    grep -q "formulae clean" "${_UPDATE_TMPDIR}/result_brew-drift"
    [ ! -f "${_UPDATE_TMPDIR}/detail_brew-drift" ]
  }
  ```

  **"OK when Brewfile has no brew/tap/cask lines"** — both empty:

  ```bash
  @test "_update_check_brewfile_drift: OK when Brewfile has no brew/tap/cask lines" {
    export MACOS=1
    printf "# comment only\n" > "${BATS_TEST_TMPDIR}/Brewfile"
    export _OVERRIDE_BREWFILE_PATH="${BATS_TEST_TMPDIR}/Brewfile"
    export MOCK_BREW_LEAVES=""
    export MOCK_BREW_LIST_FORMULA=""
    export MOCK_BREW_TAPS=""
    run _update_check_brewfile_drift
    [ "$status" -eq 0 ]
    [ "$(cat "${_UPDATE_TMPDIR}/status_brew-drift")" = "OK" ]
  }
  ```

  **"WARN when formula installed but not in Brewfile"** — `jq` is a top-level install (leaf) not in Brewfile:

  ```bash
  @test "_update_check_brewfile_drift: WARN when formula installed but not in Brewfile" {
    export MACOS=1
    printf 'brew "git"\n' > "${BATS_TEST_TMPDIR}/Brewfile"
    export _OVERRIDE_BREWFILE_PATH="${BATS_TEST_TMPDIR}/Brewfile"
    export MOCK_BREW_LEAVES="git jq"
    export MOCK_BREW_LIST_FORMULA="git jq"
    export MOCK_BREW_TAPS=""
    run _update_check_brewfile_drift
    [ "$status" -eq 0 ]
    [ "$(cat "${_UPDATE_TMPDIR}/status_brew-drift")" = "WARN" ]
    grep -q "untracked formulae" "${_UPDATE_TMPDIR}/result_brew-drift"
    grep -q "jq" "${_UPDATE_TMPDIR}/detail_brew-drift"
  }
  ```

  **"WARN when formula in Brewfile but not installed"** — `missing-tool` not in either set:

  ```bash
  @test "_update_check_brewfile_drift: WARN when formula in Brewfile but not installed" {
    export MACOS=1
    printf 'brew "git"\nbrew "missing-tool"\n' > "${BATS_TEST_TMPDIR}/Brewfile"
    export _OVERRIDE_BREWFILE_PATH="${BATS_TEST_TMPDIR}/Brewfile"
    export MOCK_BREW_LEAVES="git"
    export MOCK_BREW_LIST_FORMULA="git"
    export MOCK_BREW_TAPS=""
    run _update_check_brewfile_drift
    [ "$status" -eq 0 ]
    [ "$(cat "${_UPDATE_TMPDIR}/status_brew-drift")" = "WARN" ]
    grep -q "missing formulae" "${_UPDATE_TMPDIR}/result_brew-drift"
    grep -q "missing-tool" "${_UPDATE_TMPDIR}/detail_brew-drift"
  }
  ```

  **"WARN when tap installed but not in Brewfile"** — formula side is clean:

  ```bash
  @test "_update_check_brewfile_drift: WARN when tap installed but not in Brewfile" {
    export MACOS=1
    printf 'brew "git"\n' > "${BATS_TEST_TMPDIR}/Brewfile"
    export _OVERRIDE_BREWFILE_PATH="${BATS_TEST_TMPDIR}/Brewfile"
    export MOCK_BREW_LEAVES="git"
    export MOCK_BREW_LIST_FORMULA="git"
    export MOCK_BREW_TAPS="homebrew/cask-fonts"
    run _update_check_brewfile_drift
    [ "$status" -eq 0 ]
    [ "$(cat "${_UPDATE_TMPDIR}/status_brew-drift")" = "WARN" ]
    grep -q "untracked taps" "${_UPDATE_TMPDIR}/result_brew-drift"
    grep -q "tap: homebrew/cask-fonts" "${_UPDATE_TMPDIR}/detail_brew-drift"
  }
  ```

  **"WARN when tap in Brewfile but not installed"** — formula side is clean:

  ```bash
  @test "_update_check_brewfile_drift: WARN when tap in Brewfile but not installed" {
    export MACOS=1
    printf 'brew "git"\ntap "teamookla/speedtest"\n' > "${BATS_TEST_TMPDIR}/Brewfile"
    export _OVERRIDE_BREWFILE_PATH="${BATS_TEST_TMPDIR}/Brewfile"
    export MOCK_BREW_LEAVES="git"
    export MOCK_BREW_LIST_FORMULA="git"
    export MOCK_BREW_TAPS=""
    run _update_check_brewfile_drift
    [ "$status" -eq 0 ]
    [ "$(cat "${_UPDATE_TMPDIR}/status_brew-drift")" = "WARN" ]
    grep -q "missing taps" "${_UPDATE_TMPDIR}/result_brew-drift"
    grep -q "tap: teamookla/speedtest" "${_UPDATE_TMPDIR}/detail_brew-drift"
  }
  ```

  **"WARN when cask installed but not in Brewfile (macOS)"** — formula side is clean:

  ```bash
  @test "_update_check_brewfile_drift: WARN when cask installed but not in Brewfile (macOS)" {
    export MACOS=1
    printf 'brew "git"\ncask "visual-studio-code"\n' > "${BATS_TEST_TMPDIR}/Brewfile"
    export _OVERRIDE_BREWFILE_PATH="${BATS_TEST_TMPDIR}/Brewfile"
    export MOCK_BREW_LEAVES="git"
    export MOCK_BREW_LIST_FORMULA="git"
    export MOCK_BREW_LIST_CASK="visual-studio-code warp"
    export MOCK_BREW_TAPS=""
    run _update_check_brewfile_drift
    [ "$status" -eq 0 ]
    [ "$(cat "${_UPDATE_TMPDIR}/status_brew-drift")" = "WARN" ]
    grep -q "untracked casks" "${_UPDATE_TMPDIR}/result_brew-drift"
    grep -q "cask: warp" "${_UPDATE_TMPDIR}/detail_brew-drift"
  }
  ```

  **"WARN when cask in Brewfile but not installed (macOS)"** — formula side is clean:

  ```bash
  @test "_update_check_brewfile_drift: WARN when cask in Brewfile but not installed (macOS)" {
    export MACOS=1
    printf 'brew "git"\ncask "missing-app"\n' > "${BATS_TEST_TMPDIR}/Brewfile"
    export _OVERRIDE_BREWFILE_PATH="${BATS_TEST_TMPDIR}/Brewfile"
    export MOCK_BREW_LEAVES="git"
    export MOCK_BREW_LIST_FORMULA="git"
    export MOCK_BREW_LIST_CASK=""
    export MOCK_BREW_TAPS=""
    run _update_check_brewfile_drift
    [ "$status" -eq 0 ]
    [ "$(cat "${_UPDATE_TMPDIR}/status_brew-drift")" = "WARN" ]
    grep -q "missing casks" "${_UPDATE_TMPDIR}/result_brew-drift"
    grep -q "cask: missing-app" "${_UPDATE_TMPDIR}/detail_brew-drift"
  }
  ```

  **"WARN with all drift types in detail file"** — `jq` is untracked leaf formula; `git` is installed (leaf + in Brewfile):

  ```bash
  @test "_update_check_brewfile_drift: WARN with all drift types in detail file" {
    export MACOS=1
    printf 'brew "git"\ncask "visual-studio-code"\ntap "teamookla/speedtest"\n' \
      > "${BATS_TEST_TMPDIR}/Brewfile"
    export _OVERRIDE_BREWFILE_PATH="${BATS_TEST_TMPDIR}/Brewfile"
    # jq: untracked leaf formula; git: clean
    export MOCK_BREW_LEAVES="git jq"
    export MOCK_BREW_LIST_FORMULA="git jq"
    # warp: untracked cask; visual-studio-code: missing cask
    export MOCK_BREW_LIST_CASK="warp"
    # homebrew/cask-fonts: untracked tap; teamookla/speedtest: missing tap
    export MOCK_BREW_TAPS="homebrew/cask-fonts"
    run _update_check_brewfile_drift
    [ "$status" -eq 0 ]
    [ "$(cat "${_UPDATE_TMPDIR}/status_brew-drift")" = "WARN" ]
    grep -q "jq" "${_UPDATE_TMPDIR}/detail_brew-drift"
    grep -q "cask: warp" "${_UPDATE_TMPDIR}/detail_brew-drift"
    grep -q "tap: homebrew/cask-fonts" "${_UPDATE_TMPDIR}/detail_brew-drift"
    grep -q "cask: visual-studio-code" "${_UPDATE_TMPDIR}/detail_brew-drift"
    grep -q "tap: teamookla/speedtest" "${_UPDATE_TMPDIR}/detail_brew-drift"
  }
  ```

- [ ] **Step 4: Run all tests — expect GREEN**

  ```bash
  cd /path/to/repo && make test 2>&1 | tail -10
  ```

  Expected: `556` tests pass (555 existing + 1 new), exit 0.

- [ ] **Step 5: Commit**

  ```bash
  git add lib/update_summary.sh tests/setup_env/brewfile_drift.bats
  git commit -m "fix: use brew leaves for untracked formula detection — filters transitive deps"
  ```

---

## Task 4: Update CLAUDE.md mock table

**Files:**

- Modify: `CLAUDE.md`

- [ ] **Step 1: Add `MOCK_BREW_LEAVES` entry to the mock env var table**

  Find the `MOCK_BREW_TAPS` row in the mock env var table in `CLAUDE.md`:

  ```
  | `MOCK_BREW_TAPS` | Space-separated taps returned by `brew tap` |
  ```

  Add `MOCK_BREW_LEAVES` immediately before it:

  ```
  | `MOCK_BREW_LEAVES` | Space-separated formulae returned by `brew leaves` (top-level installs only; default: empty) |
  | `MOCK_BREW_TAPS` | Space-separated taps returned by `brew tap` |
  ```

- [ ] **Step 2: Run tests to confirm no regressions**

  ```bash
  cd /path/to/repo && make test 2>&1 | tail -5
  ```

  Expected: 556 tests pass, exit 0.

- [ ] **Step 3: Commit**

  ```bash
  git add CLAUDE.md
  git commit -m "docs: add MOCK_BREW_LEAVES to mock env var table"
  ```
