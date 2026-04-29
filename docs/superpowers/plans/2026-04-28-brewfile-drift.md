# Brewfile Drift Detection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Detect and report drift between the Brewfile manifest and locally installed Homebrew packages (formulae, casks, taps) as part of every `setup_env.sh -t update` run.

**Architecture:** Add `_update_warn` and `_update_ok` helpers + WARN status support to `_update_summary` in `lib/update_summary.sh`; add `_update_check_brewfile_drift` function in the same file; wire it into `run_update()` in `lib/workflows.sh` just before `_update_summary`. Gates on `quiet_which brew` so it works on both macOS and Linux.

**Tech Stack:** Bash, BATS, `comm`, `grep`, `sed`, existing mock infrastructure (`MOCK_BREW_LIST_FORMULA`, `MOCK_BREW_LIST_CASK`, `MOCK_BREW_TAPS`, `MOCK_WHICH_MISSING`).

---

## File Map

| File                                  | Change                                                                                                                                                   |
| ------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/update_summary.sh`               | Add `_update_ok`, `_update_warn`; extend `_update_summary` with WARN + detail blocks; add `_update_check_brewfile_drift`; update `_UPDATE_SECTION_ORDER` |
| `lib/workflows.sh`                    | Call `_update_check_brewfile_drift` before `_update_summary` in `run_update()`                                                                           |
| `tests/setup_env/update_summary.bats` | Add 6 tests for WARN infrastructure                                                                                                                      |
| `tests/setup_env/brewfile_drift.bats` | New — 11 tests for `_update_check_brewfile_drift`                                                                                                        |
| `CLAUDE.md`                           | Add `_OVERRIDE_BREWFILE_PATH` seam to test seam table                                                                                                    |
| `docs/superpowers/README.md`          | Add `brewfile-drift` row                                                                                                                                 |

---

## Task 1: WARN infrastructure in `_update_summary`

**Files:**

- Modify: `lib/update_summary.sh`
- Modify: `tests/setup_env/update_summary.bats`

### Step 1.1: Write failing tests for `_update_ok` and `_update_warn` helpers

Append to `tests/setup_env/update_summary.bats` (after the last existing test):

```bash
# ── _update_ok ───────────────────────────────────────────────────────────────

@test "_update_ok writes OK status and result files" {
  _update_ok "brew-drift" "formulae clean, taps clean"
  [ "$(cat "${_UPDATE_TMPDIR}/status_brew-drift")" = "OK" ]
  [ "$(cat "${_UPDATE_TMPDIR}/result_brew-drift")" = "formulae clean, taps clean" ]
}

# ── _update_warn ─────────────────────────────────────────────────────────────

@test "_update_warn writes WARN status and result files" {
  _update_warn "brew-drift" "3 untracked formulae"
  [ "$(cat "${_UPDATE_TMPDIR}/status_brew-drift")" = "WARN" ]
  [ "$(cat "${_UPDATE_TMPDIR}/result_brew-drift")" = "3 untracked formulae" ]
}

# ── _update_summary WARN support ─────────────────────────────────────────────

@test "_update_summary: WARN section printed with [WARN] prefix" {
  printf "WARN\n" > "${_UPDATE_TMPDIR}/status_brew-drift"
  printf "2 untracked formulae\n" > "${_UPDATE_TMPDIR}/result_brew-drift"
  run _update_summary
  [ "$status" -eq 0 ]
  [[ "$output" == *"[WARN] brew-drift"* ]]
  [[ "$output" == *"2 untracked formulae"* ]]
}

@test "_update_summary: WARN counted in warnings, not failures" {
  printf "WARN\n" > "${_UPDATE_TMPDIR}/status_brew-drift"
  printf "1 untracked formula\n" > "${_UPDATE_TMPDIR}/result_brew-drift"
  run _update_summary
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 warnings"* ]]
  [[ "$output" != *"1 failed"* ]]
}

@test "_update_summary: detail block printed after table" {
  printf "WARN\n" > "${_UPDATE_TMPDIR}/status_brew-drift"
  printf "1 untracked formulae\n" > "${_UPDATE_TMPDIR}/result_brew-drift"
  printf "brew-drift details:\n  Untracked:\n    bat\n" \
    > "${_UPDATE_TMPDIR}/detail_brew-drift"
  run _update_summary
  [ "$status" -eq 0 ]
  [[ "$output" == *"brew-drift details:"* ]]
  [[ "$output" == *"bat"* ]]
}

@test "_update_summary: no detail block when no detail file exists" {
  printf "OK\n" > "${_UPDATE_TMPDIR}/status_brew"
  printf "no changes\n" > "${_UPDATE_TMPDIR}/result_brew"
  run _update_summary
  [ "$status" -eq 0 ]
  [[ "$output" != *"details:"* ]]
}
```

- [ ] **Step 1.2: Run tests to verify they fail**

```bash
cd /Users/bruce/git-repos/personal/dotfiles
bats tests/setup_env/update_summary.bats 2>&1 | tail -20
```

Expected: 6 new tests fail (`_update_ok not found`, `_update_warn not found`, `[WARN]` not in output).

- [ ] **Step 1.3: Add `_update_ok` and `_update_warn` helpers to `lib/update_summary.sh`**

Insert immediately after the `_update_skip` function (after line 38), before `_update_record_start`:

```bash
# _update_ok SECTION MESSAGE
# Records a section as passing with the given message.
_update_ok() {
  local _section="$1" _msg="$2"
  printf "OK\n" > "${_UPDATE_TMPDIR}/status_${_section}"
  printf "%s\n" "${_msg}" > "${_UPDATE_TMPDIR}/result_${_section}"
}

# _update_warn SECTION MESSAGE
# Records a section as a non-blocking warning with the given message.
_update_warn() {
  local _section="$1" _msg="$2"
  printf "WARN\n" > "${_UPDATE_TMPDIR}/status_${_section}"
  printf "%s\n" "${_msg}" > "${_UPDATE_TMPDIR}/result_${_section}"
}
```

- [ ] **Step 1.4: Add `brew-drift` to `_UPDATE_SECTION_ORDER` in `lib/update_summary.sh`**

Change line 5-8 from:

```bash
readonly _UPDATE_SECTION_ORDER=(
  brew softwareupdate apt snap dnf yum mas claude pip gems
  oh-my-zsh p10k tpm tfenv cheat.sh
)
```

To:

```bash
readonly _UPDATE_SECTION_ORDER=(
  brew softwareupdate apt snap dnf yum mas claude pip gems
  oh-my-zsh p10k tpm tfenv cheat.sh brew-drift
)
```

- [ ] **Step 1.5: Add WARN branch and `_warn` counter to `_update_summary`**

In `_update_summary`, change:

```bash
  local _ok=0 _fail=0 _skip=0
```

To:

```bash
  local _ok=0 _fail=0 _skip=0 _warn=0
```

Add the WARN case to the case statement (after the SKIP case, before `esac`):

```bash
      WARN)
        _warn=$(( _warn + 1 ))
        _output+="$(printf "[WARN] %-16s %s" "${_section}" "${_result}")\n"
        ;;
```

Change the footer lines from:

```bash
  local _total=$(( _ok + _fail + _skip ))
  _output+="\n$(printf "%d sections: %d OK, %d failed, %d skipped" "${_total}" "${_ok}" "${_fail}" "${_skip}")\n"
```

To:

```bash
  local _total=$(( _ok + _fail + _skip + _warn ))
  _output+="\n$(printf "%d sections: %d OK, %d failed, %d warnings, %d skipped" "${_total}" "${_ok}" "${_fail}" "${_warn}" "${_skip}")\n"
```

- [ ] **Step 1.6: Add detail block printing to `_update_summary`**

After building `_output` and before the `# Print to terminal` comment, insert:

```bash
  # Build detail output (in section order for deterministic output)
  local _detail_output=""
  for _section in "${_UPDATE_SECTION_ORDER[@]}"; do
    if [[ -f "${_UPDATE_TMPDIR}/detail_${_section}" ]]; then
      _detail_output+="\n$(cat "${_UPDATE_TMPDIR}/detail_${_section}")\n"
    fi
  done
```

Change the print and log blocks from:

```bash
  # Print to terminal
  printf '%b' "${_output}"

  # Append to log file
  local _log="${UPDATE_LOG_PATH:-${HOME}/.dotfiles-update.log}"
  {
    printf "────────────────────────────────────────────────────────\n"
    printf '%b' "${_output}"
  } >> "${_log}" 2>/dev/null || log_warn "Could not write to ${_log}"
```

To:

```bash
  # Print to terminal
  printf '%b' "${_output}"
  [[ -n "${_detail_output}" ]] && printf '%b' "${_detail_output}"

  # Append to log file
  local _log="${UPDATE_LOG_PATH:-${HOME}/.dotfiles-update.log}"
  {
    printf "────────────────────────────────────────────────────────\n"
    printf '%b' "${_output}"
    [[ -n "${_detail_output}" ]] && printf '%b' "${_detail_output}"
  } >> "${_log}" 2>/dev/null || log_warn "Could not write to ${_log}"
```

- [ ] **Step 1.7: Run tests to verify they pass**

```bash
bats tests/setup_env/update_summary.bats 2>&1 | tail -20
```

Expected: all tests pass including the 6 new ones.

- [ ] **Step 1.8: Commit**

```bash
git add lib/update_summary.sh tests/setup_env/update_summary.bats
git commit -m "feat: add WARN status and detail blocks to update summary infrastructure"
```

---

## Task 2: `_update_check_brewfile_drift` — skip gates, formulae, taps

**Files:**

- Modify: `lib/update_summary.sh`
- Create: `tests/setup_env/brewfile_drift.bats`

- [ ] **Step 2.1: Create `tests/setup_env/brewfile_drift.bats` with skip gate and formula/tap tests**

```bash
#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_mocks
  load_setup_env
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  touch "${MOCK_CALLS_FILE}"
  export _UPDATE_TMPDIR="${BATS_TEST_TMPDIR}"
  export UPDATE_LOG_PATH="${BATS_TEST_TMPDIR}/update.log"
  unset MACOS
  unset MOCK_WHICH_MISSING
}

teardown() {
  unset _OVERRIDE_BREWFILE_PATH
  unset MOCK_BREW_LIST_FORMULA
  unset MOCK_BREW_LIST_CASK
  unset MOCK_BREW_TAPS
  unset MOCK_WHICH_MISSING
  unset MACOS
}

# ── skip gates ────────────────────────────────────────────────────────────────

@test "_update_check_brewfile_drift: SKIP when brew not available" {
  export MOCK_WHICH_MISSING=brew
  run _update_check_brewfile_drift
  [ "$status" -eq 0 ]
  [ "$(cat "${_UPDATE_TMPDIR}/status_brew-drift")" = "SKIP" ]
  grep -q "brew not available" "${_UPDATE_TMPDIR}/result_brew-drift"
}

@test "_update_check_brewfile_drift: SKIP when Brewfile not found" {
  export _OVERRIDE_BREWFILE_PATH="${BATS_TEST_TMPDIR}/nonexistent_brewfile"
  run _update_check_brewfile_drift
  [ "$status" -eq 0 ]
  [ "$(cat "${_UPDATE_TMPDIR}/status_brew-drift")" = "SKIP" ]
  grep -q "Brewfile not found" "${_UPDATE_TMPDIR}/result_brew-drift"
}

# ── formula drift ─────────────────────────────────────────────────────────────

@test "_update_check_brewfile_drift: OK when formulae and taps match" {
  printf 'brew "bat"\nbrew "git"\n' > "${BATS_TEST_TMPDIR}/Brewfile"
  export _OVERRIDE_BREWFILE_PATH="${BATS_TEST_TMPDIR}/Brewfile"
  export MOCK_BREW_LIST_FORMULA="bat git"
  export MOCK_BREW_TAPS=""
  run _update_check_brewfile_drift
  [ "$status" -eq 0 ]
  [ "$(cat "${_UPDATE_TMPDIR}/status_brew-drift")" = "OK" ]
  grep -q "formulae clean" "${_UPDATE_TMPDIR}/result_brew-drift"
}

@test "_update_check_brewfile_drift: WARN when formula installed but not in Brewfile" {
  printf 'brew "git"\n' > "${BATS_TEST_TMPDIR}/Brewfile"
  export _OVERRIDE_BREWFILE_PATH="${BATS_TEST_TMPDIR}/Brewfile"
  export MOCK_BREW_LIST_FORMULA="git jq"
  export MOCK_BREW_TAPS=""
  run _update_check_brewfile_drift
  [ "$status" -eq 0 ]
  [ "$(cat "${_UPDATE_TMPDIR}/status_brew-drift")" = "WARN" ]
  grep -q "untracked formulae" "${_UPDATE_TMPDIR}/result_brew-drift"
  grep -q "jq" "${_UPDATE_TMPDIR}/detail_brew-drift"
}

@test "_update_check_brewfile_drift: WARN when formula in Brewfile but not installed" {
  printf 'brew "git"\nbrew "missing-tool"\n' > "${BATS_TEST_TMPDIR}/Brewfile"
  export _OVERRIDE_BREWFILE_PATH="${BATS_TEST_TMPDIR}/Brewfile"
  export MOCK_BREW_LIST_FORMULA="git"
  export MOCK_BREW_TAPS=""
  run _update_check_brewfile_drift
  [ "$status" -eq 0 ]
  [ "$(cat "${_UPDATE_TMPDIR}/status_brew-drift")" = "WARN" ]
  grep -q "missing formulae" "${_UPDATE_TMPDIR}/result_brew-drift"
  grep -q "missing-tool" "${_UPDATE_TMPDIR}/detail_brew-drift"
}

# ── tap drift ─────────────────────────────────────────────────────────────────

@test "_update_check_brewfile_drift: WARN when tap installed but not in Brewfile" {
  printf 'brew "git"\n' > "${BATS_TEST_TMPDIR}/Brewfile"
  export _OVERRIDE_BREWFILE_PATH="${BATS_TEST_TMPDIR}/Brewfile"
  export MOCK_BREW_LIST_FORMULA="git"
  export MOCK_BREW_TAPS="homebrew/cask-fonts"
  run _update_check_brewfile_drift
  [ "$status" -eq 0 ]
  [ "$(cat "${_UPDATE_TMPDIR}/status_brew-drift")" = "WARN" ]
  grep -q "untracked taps" "${_UPDATE_TMPDIR}/result_brew-drift"
  grep -q "tap: homebrew/cask-fonts" "${_UPDATE_TMPDIR}/detail_brew-drift"
}

@test "_update_check_brewfile_drift: WARN when tap in Brewfile but not installed" {
  printf 'brew "git"\ntap "teamookla/speedtest"\n' > "${BATS_TEST_TMPDIR}/Brewfile"
  export _OVERRIDE_BREWFILE_PATH="${BATS_TEST_TMPDIR}/Brewfile"
  export MOCK_BREW_LIST_FORMULA="git"
  export MOCK_BREW_TAPS=""
  run _update_check_brewfile_drift
  [ "$status" -eq 0 ]
  [ "$(cat "${_UPDATE_TMPDIR}/status_brew-drift")" = "WARN" ]
  grep -q "missing taps" "${_UPDATE_TMPDIR}/result_brew-drift"
  grep -q "tap: teamookla/speedtest" "${_UPDATE_TMPDIR}/detail_brew-drift"
}
```

- [ ] **Step 2.2: Run tests to verify they fail**

```bash
bats tests/setup_env/brewfile_drift.bats 2>&1 | tail -20
```

Expected: all 7 tests fail (`_update_check_brewfile_drift: command not found`).

- [ ] **Step 2.3: Add `_update_check_brewfile_drift` to `lib/update_summary.sh`**

Append at the end of `lib/update_summary.sh` (after `_update_summary`):

```bash
# _update_check_brewfile_drift
# Compares Brewfile (formulae, casks on macOS, taps) against locally installed
# Homebrew packages. Records OK/WARN/SKIP into the update summary.
# Uses _OVERRIDE_BREWFILE_PATH seam for testing.
_update_check_brewfile_drift() {
  local _brewfile="${_OVERRIDE_BREWFILE_PATH:-${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile}"

  if ! quiet_which brew; then
    _update_skip "brew-drift" "brew not available"
    return 0
  fi

  if [[ ! -f "${_brewfile}" ]]; then
    _update_skip "brew-drift" "Brewfile not found at ${_brewfile}"
    return 0
  fi

  # Parse Brewfile into sorted temp files
  grep '^brew "' "${_brewfile}" | sed 's/^brew "//;s/".*//' | sort \
    > "${_UPDATE_TMPDIR}/drift_bf_formulae"
  grep '^tap "' "${_brewfile}" | sed 's/^tap "//;s/".*//' | sort \
    > "${_UPDATE_TMPDIR}/drift_bf_taps"

  # Get actual installed state
  brew list --formula 2>/dev/null | sort > "${_UPDATE_TMPDIR}/drift_inst_formulae"
  brew tap 2>/dev/null | sort > "${_UPDATE_TMPDIR}/drift_inst_taps"

  # Compute formula and tap drift
  # comm -13: lines only in file2 = installed but not in Brewfile (untracked)
  # comm -23: lines only in file1 = in Brewfile but not installed (missing)
  local _untracked_formulae _missing_formulae _untracked_taps _missing_taps
  _untracked_formulae=$(comm -13 "${_UPDATE_TMPDIR}/drift_bf_formulae" \
    "${_UPDATE_TMPDIR}/drift_inst_formulae")
  _missing_formulae=$(comm -23 "${_UPDATE_TMPDIR}/drift_bf_formulae" \
    "${_UPDATE_TMPDIR}/drift_inst_formulae")
  _untracked_taps=$(comm -13 "${_UPDATE_TMPDIR}/drift_bf_taps" \
    "${_UPDATE_TMPDIR}/drift_inst_taps")
  _missing_taps=$(comm -23 "${_UPDATE_TMPDIR}/drift_bf_taps" \
    "${_UPDATE_TMPDIR}/drift_inst_taps")

  # Cask drift: macOS only (Linux Homebrew does not support casks)
  local _untracked_casks="" _missing_casks=""
  if [[ -n ${MACOS:-} ]]; then
    grep '^cask "' "${_brewfile}" | sed 's/^cask "//;s/".*//' | sort \
      > "${_UPDATE_TMPDIR}/drift_bf_casks"
    brew list --cask 2>/dev/null | sort > "${_UPDATE_TMPDIR}/drift_inst_casks"
    _untracked_casks=$(comm -13 "${_UPDATE_TMPDIR}/drift_bf_casks" \
      "${_UPDATE_TMPDIR}/drift_inst_casks")
    _missing_casks=$(comm -23 "${_UPDATE_TMPDIR}/drift_bf_casks" \
      "${_UPDATE_TMPDIR}/drift_inst_casks")
  fi

  # Check for any drift
  local _has_drift=0
  [[ -n "${_untracked_formulae}" ]] && _has_drift=1
  [[ -n "${_missing_formulae}" ]]   && _has_drift=1
  [[ -n "${_untracked_taps}" ]]     && _has_drift=1
  [[ -n "${_missing_taps}" ]]       && _has_drift=1
  [[ -n "${_untracked_casks}" ]]    && _has_drift=1
  [[ -n "${_missing_casks}" ]]      && _has_drift=1

  if [[ "${_has_drift}" -eq 0 ]]; then
    local _clean_msg="formulae clean"
    [[ -n ${MACOS:-} ]] && _clean_msg="${_clean_msg}, casks clean"
    _clean_msg="${_clean_msg}, taps clean"
    _update_ok "brew-drift" "${_clean_msg}"
    return 0
  fi

  # Build summary string from non-zero drift counts
  local _untracked_f_count _missing_f_count _untracked_t_count _missing_t_count
  _untracked_f_count=$(printf '%s\n' "${_untracked_formulae}" | grep -c . || true)
  _missing_f_count=$(printf '%s\n' "${_missing_formulae}" | grep -c . || true)
  _untracked_t_count=$(printf '%s\n' "${_untracked_taps}" | grep -c . || true)
  _missing_t_count=$(printf '%s\n' "${_missing_taps}" | grep -c . || true)

  local _summary=""
  [[ "${_untracked_f_count}" -gt 0 ]] && _summary+="${_untracked_f_count} untracked formulae, "
  [[ "${_missing_f_count}" -gt 0 ]]   && _summary+="${_missing_f_count} missing formulae, "
  if [[ -n ${MACOS:-} ]]; then
    local _untracked_c_count _missing_c_count
    _untracked_c_count=$(printf '%s\n' "${_untracked_casks}" | grep -c . || true)
    _missing_c_count=$(printf '%s\n' "${_missing_casks}" | grep -c . || true)
    [[ "${_untracked_c_count}" -gt 0 ]] && _summary+="${_untracked_c_count} untracked casks, "
    [[ "${_missing_c_count}" -gt 0 ]]   && _summary+="${_missing_c_count} missing casks, "
  fi
  [[ "${_untracked_t_count}" -gt 0 ]] && _summary+="${_untracked_t_count} untracked taps, "
  [[ "${_missing_t_count}" -gt 0 ]]   && _summary+="${_missing_t_count} missing taps, "
  _summary="${_summary%, }"

  _update_warn "brew-drift" "${_summary}"

  # Write detail file
  local _detail="brew-drift details:\n"
  if [[ -n "${_untracked_formulae}" ]] || [[ -n "${_untracked_casks}" ]] || [[ -n "${_untracked_taps}" ]]; then
    _detail+="  Untracked (installed, not in Brewfile):\n"
    while IFS= read -r _pkg; do
      [[ -z "${_pkg}" ]] && continue
      _detail+="    ${_pkg}\n"
    done <<< "${_untracked_formulae}"
    while IFS= read -r _pkg; do
      [[ -z "${_pkg}" ]] && continue
      _detail+="    cask: ${_pkg}\n"
    done <<< "${_untracked_casks}"
    while IFS= read -r _pkg; do
      [[ -z "${_pkg}" ]] && continue
      _detail+="    tap: ${_pkg}\n"
    done <<< "${_untracked_taps}"
  fi
  if [[ -n "${_missing_formulae}" ]] || [[ -n "${_missing_casks}" ]] || [[ -n "${_missing_taps}" ]]; then
    _detail+="  Missing (in Brewfile, not installed):\n"
    while IFS= read -r _pkg; do
      [[ -z "${_pkg}" ]] && continue
      _detail+="    ${_pkg}\n"
    done <<< "${_missing_formulae}"
    while IFS= read -r _pkg; do
      [[ -z "${_pkg}" ]] && continue
      _detail+="    cask: ${_pkg}\n"
    done <<< "${_missing_casks}"
    while IFS= read -r _pkg; do
      [[ -z "${_pkg}" ]] && continue
      _detail+="    tap: ${_pkg}\n"
    done <<< "${_missing_taps}"
  fi

  printf '%b' "${_detail}" > "${_UPDATE_TMPDIR}/detail_brew-drift"
}
```

- [ ] **Step 2.4: Run tests to verify they pass**

```bash
bats tests/setup_env/brewfile_drift.bats 2>&1 | tail -20
```

Expected: all 7 tests pass.

- [ ] **Step 2.5: Run full test suite to confirm no regressions**

```bash
make test 2>&1 | tail -10
```

Expected: all tests pass.

- [ ] **Step 2.6: Commit**

```bash
git add lib/update_summary.sh tests/setup_env/brewfile_drift.bats
git commit -m "feat: add _update_check_brewfile_drift with skip gates, formula and tap drift"
```

---

## Task 3: Cask drift, Linux exclusion, mixed drift

**Files:**

- Modify: `tests/setup_env/brewfile_drift.bats`

No new implementation code needed — cask and Linux logic is already in the function from Task 2. These tests verify the branches added there.

- [ ] **Step 3.1: Append cask, Linux, and mixed tests to `tests/setup_env/brewfile_drift.bats`**

```bash
# ── cask drift (macOS only) ───────────────────────────────────────────────────

@test "_update_check_brewfile_drift: WARN when cask installed but not in Brewfile (macOS)" {
  export MACOS=1
  printf 'brew "git"\ncask "visual-studio-code"\n' > "${BATS_TEST_TMPDIR}/Brewfile"
  export _OVERRIDE_BREWFILE_PATH="${BATS_TEST_TMPDIR}/Brewfile"
  export MOCK_BREW_LIST_FORMULA="git"
  export MOCK_BREW_LIST_CASK="visual-studio-code warp"
  export MOCK_BREW_TAPS=""
  run _update_check_brewfile_drift
  [ "$status" -eq 0 ]
  [ "$(cat "${_UPDATE_TMPDIR}/status_brew-drift")" = "WARN" ]
  grep -q "untracked casks" "${_UPDATE_TMPDIR}/result_brew-drift"
  grep -q "cask: warp" "${_UPDATE_TMPDIR}/detail_brew-drift"
}

@test "_update_check_brewfile_drift: WARN when cask in Brewfile but not installed (macOS)" {
  export MACOS=1
  printf 'brew "git"\ncask "missing-app"\n' > "${BATS_TEST_TMPDIR}/Brewfile"
  export _OVERRIDE_BREWFILE_PATH="${BATS_TEST_TMPDIR}/Brewfile"
  export MOCK_BREW_LIST_FORMULA="git"
  export MOCK_BREW_LIST_CASK=""
  export MOCK_BREW_TAPS=""
  run _update_check_brewfile_drift
  [ "$status" -eq 0 ]
  [ "$(cat "${_UPDATE_TMPDIR}/status_brew-drift")" = "WARN" ]
  grep -q "missing casks" "${_UPDATE_TMPDIR}/result_brew-drift"
  grep -q "cask: missing-app" "${_UPDATE_TMPDIR}/detail_brew-drift"
}

# ── Linux: casks not checked ──────────────────────────────────────────────────

@test "_update_check_brewfile_drift: OK on Linux — cask lines in Brewfile ignored" {
  unset MACOS
  printf 'brew "git"\ncask "visual-studio-code"\n' > "${BATS_TEST_TMPDIR}/Brewfile"
  export _OVERRIDE_BREWFILE_PATH="${BATS_TEST_TMPDIR}/Brewfile"
  export MOCK_BREW_LIST_FORMULA="git"
  export MOCK_BREW_TAPS=""
  run _update_check_brewfile_drift
  [ "$status" -eq 0 ]
  [ "$(cat "${_UPDATE_TMPDIR}/status_brew-drift")" = "OK" ]
  local _result
  _result="$(cat "${_UPDATE_TMPDIR}/result_brew-drift")"
  [[ "${_result}" != *"cask"* ]]
}

# ── mixed drift ───────────────────────────────────────────────────────────────

@test "_update_check_brewfile_drift: WARN with all drift types in detail file" {
  export MACOS=1
  printf 'brew "git"\ncask "visual-studio-code"\ntap "teamookla/speedtest"\n' \
    > "${BATS_TEST_TMPDIR}/Brewfile"
  export _OVERRIDE_BREWFILE_PATH="${BATS_TEST_TMPDIR}/Brewfile"
  # jq: untracked formula; git: clean
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

- [ ] **Step 3.2: Run new tests to verify they pass**

```bash
bats tests/setup_env/brewfile_drift.bats 2>&1 | tail -20
```

Expected: all 11 tests pass.

- [ ] **Step 3.3: Run full test suite**

```bash
make test 2>&1 | tail -10
```

Expected: all tests pass.

- [ ] **Step 3.4: Commit**

```bash
git add tests/setup_env/brewfile_drift.bats
git commit -m "test: add cask, Linux, and mixed drift tests for _update_check_brewfile_drift"
```

---

## Task 4: Wire into `run_update`, update docs

**Files:**

- Modify: `lib/workflows.sh`
- Modify: `CLAUDE.md`
- Modify: `docs/superpowers/README.md`
- Modify: `docs/superpowers/plans/2026-04-28-brewfile-drift.md`

- [ ] **Step 4.1: Add drift check call to `run_update` in `lib/workflows.sh`**

Change the end of `run_update()` from:

```bash
  # ── summary ───────────────────────────────────────────────────────────────
  _update_summary
}
```

To:

```bash
  # ── drift check ───────────────────────────────────────────────────────────
  _update_check_brewfile_drift

  # ── summary ───────────────────────────────────────────────────────────────
  _update_summary
}
```

- [ ] **Step 4.2: Run full test suite**

```bash
make test 2>&1 | tail -10
```

Expected: all tests pass.

- [ ] **Step 4.3: Update CLAUDE.md test seam table**

In `CLAUDE.md`, add a row to the Test Seams table (the table under "### Test Seams"):

```
| `_OVERRIDE_BREWFILE_PATH`    | `_update_check_brewfile_drift` | Path to Brewfile; defaults to `${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile` |
```

- [ ] **Step 4.4: Update `docs/superpowers/README.md`**

Add a row to the All Plans table:

```
| 2026-04-28 | [brewfile-drift](plans/2026-04-28-brewfile-drift.md) | [spec](specs/2026-04-28-brewfile-drift-design.md) | Done |
```

Remove the `Brewfile drift detection` row from the Backlog table.

Add `> **Status: DONE**` as the first line of `docs/superpowers/plans/2026-04-28-brewfile-drift.md`.

- [ ] **Step 4.5: Commit**

```bash
git add lib/workflows.sh CLAUDE.md docs/superpowers/README.md \
  docs/superpowers/plans/2026-04-28-brewfile-drift.md
git commit -m "feat: wire brewfile drift check into run_update; update docs"
```
