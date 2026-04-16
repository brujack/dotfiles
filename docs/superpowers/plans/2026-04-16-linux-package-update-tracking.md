# Linux Package Update Tracking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Track apt/snap/dnf/yum package updates with per-package name+version diffs in the update summary, matching the existing brew pre/post snapshot pattern.

**Architecture:** Four new sections (apt, snap, dnf, yum) are added to `_UPDATE_SECTION_ORDER`. `_update_record_start` runs the pre-snapshot or writes SKIP "not applicable" based on distro. `_update_record_end` checks for an existing SKIP file before doing anything, then diffs pre/post snapshots. `run_update` gets a new `# Linux system packages` block that wraps `update_system_packages`; `update_system_packages` is removed from the `mas` block. A new `--pkgs-only` flag mirrors the existing `--brew-only` pattern.

**Tech Stack:** bash, BATS, PATH-injected mock executables, dpkg-query (Ubuntu), snap (Ubuntu), rpm (RHEL/Fedora/CentOS)

---

## File Map

| File                                  | Action | What changes                                                                                                                         |
| ------------------------------------- | ------ | ------------------------------------------------------------------------------------------------------------------------------------ |
| `lib/update_summary.sh`               | Modify | Add apt/snap/dnf/yum to `_UPDATE_SECTION_ORDER`; new cases in `_update_record_start`; SKIP guard + new cases in `_update_record_end` |
| `lib/workflows.sh`                    | Modify | Remove `update_system_packages` from `mas` block; add `# Linux system packages` block                                                |
| `lib/helpers.sh`                      | Modify | Add `UPDATE_PKGS` to `_any_update_flag`; add `--pkgs-only` to `process_args`                                                         |
| `tests/mocks/dpkg-query`              | Create | New mock for `dpkg-query -W`                                                                                                         |
| `tests/mocks/snap`                    | Modify | Extend to return `MOCK_SNAP_LIST_OUTPUT` for `list` subcommand                                                                       |
| `tests/mocks/rpm`                     | Modify | Extend to return `MOCK_RPM_OUTPUT` for `-qa` subcommand                                                                              |
| `tests/setup_env/update_summary.bats` | Modify | Add tests for new `_update_record_start` and `_update_record_end` cases                                                              |
| `tests/setup_env/workflows.bats`      | Modify | Add tests for `run_update` Linux packages block and `--pkgs-only`                                                                    |

---

## Task 0: Set up feature branch worktree

Per CLAUDE.md: implementation work must never go directly to master. Use a git worktree.

**Files:** none (setup only)

- [ ] **Step 1: Create worktree**

```bash
cd ~/git-repos/personal/dotfiles
git worktree add ../dotfiles-linux-pkg-tracking -b feature/linux-package-update-tracking
cd ../dotfiles-linux-pkg-tracking
```

- [ ] **Step 2: Verify**

```bash
git branch --show-current
```

Expected: `feature/linux-package-update-tracking`

---

## Task 1: Extend mocks for package listing

Mocks must exist before any test can exercise `_update_record_start` for the new sections.

**Files:**

- Create: `tests/mocks/dpkg-query`
- Modify: `tests/mocks/snap`
- Modify: `tests/mocks/rpm`

- [ ] **Step 1: Create dpkg-query mock**

```bash
cat > tests/mocks/dpkg-query << 'EOF'
#!/usr/bin/env bash
printf "dpkg-query %s\n" "$*" >> "${MOCK_CALLS_FILE:-/tmp/mock_calls}"
if [[ "${MOCK_DPKG_QUERY_EXIT:-0}" -ne 0 ]]; then
  exit "${MOCK_DPKG_QUERY_EXIT}"
fi
case "$1" in
  -W) printf "%s\n" "${MOCK_DPKG_OUTPUT:-}" ;;
esac
exit 0
EOF
chmod +x tests/mocks/dpkg-query
```

- [ ] **Step 2: Extend snap mock to handle `list`**

Replace `tests/mocks/snap` contents with:

```bash
#!/usr/bin/env bash
printf "snap %s\n" "$*" >> "${MOCK_CALLS_FILE:-/tmp/mock_calls}"
if [[ "${MOCK_SNAP_EXIT:-0}" -ne 0 ]]; then
  exit "${MOCK_SNAP_EXIT}"
fi
case "$1" in
  list) printf "%s\n" "${MOCK_SNAP_LIST_OUTPUT:-}" ;;
esac
exit 0
```

- [ ] **Step 3: Extend rpm mock to handle `-qa`**

Replace `tests/mocks/rpm` contents with:

```bash
#!/usr/bin/env bash
printf "rpm %s\n" "$*" >> "${MOCK_CALLS_FILE:-/tmp/mock_calls}"
if [[ "${MOCK_RPM_EXIT:-0}" -ne 0 ]]; then
  exit "${MOCK_RPM_EXIT}"
fi
case "$1" in
  -qa) printf "%s\n" "${MOCK_RPM_OUTPUT:-}" ;;
esac
exit 0
```

- [ ] **Step 4: Verify mock files are executable and have correct shebang**

```bash
head -1 tests/mocks/dpkg-query tests/mocks/snap tests/mocks/rpm
ls -l tests/mocks/dpkg-query tests/mocks/snap tests/mocks/rpm
```

Expected: all three show `#!/usr/bin/env bash` and are executable (`-rwxr-xr-x`).

- [ ] **Step 5: Commit mock infrastructure**

```bash
git add tests/mocks/dpkg-query tests/mocks/snap tests/mocks/rpm
git commit -m "test: extend mocks for apt/snap/rpm package listing"
```

---

## Task 2: Add sections to `_UPDATE_SECTION_ORDER` and `_update_record_start`

**Files:**

- Modify: `lib/update_summary.sh`
- Modify: `tests/setup_env/update_summary.bats`

### Step 2a — Write failing tests

- [ ] **Step 1: Add `_update_record_start` tests for the four new sections**

Append to `tests/setup_env/update_summary.bats` (after the existing `_update_record_start` block, before the `_update_record_end` block):

```bash
@test "_update_record_start apt creates pre_apt on Ubuntu" {
  unset MACOS REDHAT FEDORA CENTOS
  export LINUX=1
  export UBUNTU=1
  export MOCK_DPKG_OUTPUT="curl 7.88.1-1ubuntu3
git 2.43.0-1ubuntu7"
  _update_record_start "apt"
  [ -f "${_UPDATE_TMPDIR}/pre_apt" ]
  grep -q "curl" "${_UPDATE_TMPDIR}/pre_apt"
}

@test "_update_record_start apt writes SKIP when not Ubuntu" {
  unset UBUNTU LINUX
  export MACOS=1
  _update_record_start "apt"
  grep -q "SKIP" "${_UPDATE_TMPDIR}/status_apt"
  grep -q "not applicable" "${_UPDATE_TMPDIR}/result_apt"
}

@test "_update_record_start snap creates pre_snap on Ubuntu" {
  unset MACOS REDHAT FEDORA CENTOS
  export LINUX=1
  export UBUNTU=1
  export MOCK_SNAP_LIST_OUTPUT="Name    Version
firefox 124.0"
  _update_record_start "snap"
  [ -f "${_UPDATE_TMPDIR}/pre_snap" ]
}

@test "_update_record_start snap writes SKIP when not Ubuntu" {
  unset UBUNTU LINUX
  export MACOS=1
  _update_record_start "snap"
  grep -q "SKIP" "${_UPDATE_TMPDIR}/status_snap"
  grep -q "not applicable" "${_UPDATE_TMPDIR}/result_snap"
}

@test "_update_record_start dnf creates pre_dnf on REDHAT" {
  unset MACOS UBUNTU CENTOS FEDORA
  export LINUX=1
  export REDHAT=1
  export MOCK_RPM_OUTPUT="curl 7.76.1-26.el9
git 2.43.5-1.el9"
  _update_record_start "dnf"
  [ -f "${_UPDATE_TMPDIR}/pre_dnf" ]
  grep -q "curl" "${_UPDATE_TMPDIR}/pre_dnf"
}

@test "_update_record_start dnf creates pre_dnf on FEDORA" {
  unset MACOS UBUNTU CENTOS REDHAT
  export LINUX=1
  export FEDORA=1
  export MOCK_RPM_OUTPUT="curl 7.76.1-26.fc39"
  _update_record_start "dnf"
  [ -f "${_UPDATE_TMPDIR}/pre_dnf" ]
}

@test "_update_record_start dnf writes SKIP when not REDHAT or FEDORA" {
  unset REDHAT FEDORA LINUX
  export MACOS=1
  _update_record_start "dnf"
  grep -q "SKIP" "${_UPDATE_TMPDIR}/status_dnf"
  grep -q "not applicable" "${_UPDATE_TMPDIR}/result_dnf"
}

@test "_update_record_start yum creates pre_yum on CENTOS" {
  unset MACOS UBUNTU REDHAT FEDORA
  export LINUX=1
  export CENTOS=1
  export MOCK_RPM_OUTPUT="curl 7.76.1-26.el8"
  _update_record_start "yum"
  [ -f "${_UPDATE_TMPDIR}/pre_yum" ]
}

@test "_update_record_start yum writes SKIP when not CENTOS" {
  unset CENTOS LINUX
  export MACOS=1
  _update_record_start "yum"
  grep -q "SKIP" "${_UPDATE_TMPDIR}/status_yum"
  grep -q "not applicable" "${_UPDATE_TMPDIR}/result_yum"
}
```

- [ ] **Step 2: Run new tests to confirm they fail**

```bash
make test 2>&1 | grep -A3 "apt creates pre_apt\|apt writes SKIP\|snap creates\|snap writes\|dnf creates\|dnf writes\|yum creates\|yum writes" | head -40
```

Expected: failures with "not found" or "file not found" — confirming the cases don't exist yet.

### Step 2b — Implement

- [ ] **Step 3: Update `_UPDATE_SECTION_ORDER` in `lib/update_summary.sh`**

Replace:

```bash
readonly _UPDATE_SECTION_ORDER=(
  brew softwareupdate mas claude pip gems
  oh-my-zsh p10k tpm tfenv cheat.sh
)
```

With:

```bash
readonly _UPDATE_SECTION_ORDER=(
  brew softwareupdate apt snap dnf yum mas claude pip gems
  oh-my-zsh p10k tpm tfenv cheat.sh
)
```

- [ ] **Step 4: Add apt/snap/dnf/yum cases to `_update_record_start` in `lib/update_summary.sh`**

In the `case "${_section}" in` block inside `_update_record_start`, add after the `softwareupdate)` case and before the `claude)` case:

```bash
    apt)
      if [[ -n ${UBUNTU:-} ]]; then
        dpkg-query -W -f='${Package} ${Version}\n' > "${_UPDATE_TMPDIR}/pre_apt" 2>/dev/null || true
      else
        _update_skip "apt" "not applicable"
      fi
      ;;
    snap)
      if [[ -n ${UBUNTU:-} ]]; then
        snap list --color=never 2>/dev/null \
          | awk 'NR>1 {print $1, $2}' \
          > "${_UPDATE_TMPDIR}/pre_snap" || true
      else
        _update_skip "snap" "not applicable"
      fi
      ;;
    dnf)
      if [[ -n ${REDHAT:-} ]] || [[ -n ${FEDORA:-} ]]; then
        rpm -qa --qf '%{NAME} %{VERSION}-%{RELEASE}\n' > "${_UPDATE_TMPDIR}/pre_dnf" 2>/dev/null || true
      else
        _update_skip "dnf" "not applicable"
      fi
      ;;
    yum)
      if [[ -n ${CENTOS:-} ]]; then
        rpm -qa --qf '%{NAME} %{VERSION}-%{RELEASE}\n' > "${_UPDATE_TMPDIR}/pre_yum" 2>/dev/null || true
      else
        _update_skip "yum" "not applicable"
      fi
      ;;
```

- [ ] **Step 5: Run tests to confirm they pass**

```bash
make test 2>&1 | grep -E "apt creates pre_apt|apt writes SKIP|snap creates|snap writes|dnf creates|dnf writes|yum creates|yum writes"
```

Expected: all lines show `ok`.

- [ ] **Step 6: Commit**

```bash
git add lib/update_summary.sh tests/setup_env/update_summary.bats
git commit -m "feat: add apt/snap/dnf/yum sections to update_summary section order and record_start"
```

---

## Task 3: SKIP guard + `_update_record_end` cases for Linux package managers

**Files:**

- Modify: `lib/update_summary.sh`
- Modify: `tests/setup_env/update_summary.bats`

### Step 3a — Write failing tests

- [ ] **Step 1: Add `_update_record_end` tests for the four new sections**

Append to `tests/setup_env/update_summary.bats` after the existing `_update_record_end` block:

```bash
# ── _update_record_end — SKIP guard ───────────────────────────────────────

@test "_update_record_end does not overwrite SKIP written by _update_record_start for apt" {
  _update_skip "apt" "not applicable"
  _update_record_end "apt" 0
  grep -q "SKIP" "${_UPDATE_TMPDIR}/status_apt"
  grep -q "not applicable" "${_UPDATE_TMPDIR}/result_apt"
}

@test "_update_record_end does not overwrite SKIP written by _update_record_start for snap" {
  _update_skip "snap" "not applicable"
  _update_record_end "snap" 0
  grep -q "SKIP" "${_UPDATE_TMPDIR}/status_snap"
}

@test "_update_record_end does not overwrite SKIP written by _update_record_start for dnf" {
  _update_skip "dnf" "not applicable"
  _update_record_end "dnf" 0
  grep -q "SKIP" "${_UPDATE_TMPDIR}/status_dnf"
}

@test "_update_record_end does not overwrite SKIP written by _update_record_start for yum" {
  _update_skip "yum" "not applicable"
  _update_record_end "yum" 0
  grep -q "SKIP" "${_UPDATE_TMPDIR}/status_yum"
}

# ── _update_record_end — apt diff ─────────────────────────────────────────

@test "_update_record_end apt reports changed packages with name and version" {
  printf "curl 7.88.1-1ubuntu3\ngit 2.43.0-1ubuntu7\n" > "${_UPDATE_TMPDIR}/pre_apt"
  export MOCK_DPKG_OUTPUT="curl 7.88.1-1ubuntu3
git 2.44.0-1ubuntu7"
  _update_record_end "apt" 0
  grep -q "OK" "${_UPDATE_TMPDIR}/status_apt"
  grep -q "git 2.44.0" "${_UPDATE_TMPDIR}/result_apt"
}

@test "_update_record_end apt reports no changes when packages unchanged" {
  printf "curl 7.88.1-1ubuntu3\n" > "${_UPDATE_TMPDIR}/pre_apt"
  export MOCK_DPKG_OUTPUT="curl 7.88.1-1ubuntu3"
  _update_record_end "apt" 0
  grep -q "no changes" "${_UPDATE_TMPDIR}/result_apt"
}

@test "_update_record_end apt reports updated when no pre-snapshot" {
  export MOCK_DPKG_OUTPUT="curl 7.88.1-1ubuntu3"
  _update_record_end "apt" 0
  grep -q "updated" "${_UPDATE_TMPDIR}/result_apt"
}

@test "_update_record_end apt writes FAIL on non-zero exit" {
  _update_record_end "apt" 1
  grep -q "FAIL" "${_UPDATE_TMPDIR}/status_apt"
  grep -q "exit 1" "${_UPDATE_TMPDIR}/result_apt"
}

# ── _update_record_end — snap diff ────────────────────────────────────────

@test "_update_record_end snap reports changed packages with name and version" {
  printf "firefox 123.0\n" > "${_UPDATE_TMPDIR}/pre_snap"
  export MOCK_SNAP_LIST_OUTPUT="Name     Version
firefox  124.0"
  _update_record_end "snap" 0
  grep -q "OK" "${_UPDATE_TMPDIR}/status_snap"
  grep -q "firefox 124.0" "${_UPDATE_TMPDIR}/result_snap"
}

@test "_update_record_end snap reports no changes when packages unchanged" {
  printf "firefox 124.0\n" > "${_UPDATE_TMPDIR}/pre_snap"
  export MOCK_SNAP_LIST_OUTPUT="Name     Version
firefox  124.0"
  _update_record_end "snap" 0
  grep -q "no changes" "${_UPDATE_TMPDIR}/result_snap"
}

# ── _update_record_end — dnf diff ─────────────────────────────────────────

@test "_update_record_end dnf reports changed packages with name and version" {
  printf "curl 7.76.1-26.el9\n" > "${_UPDATE_TMPDIR}/pre_dnf"
  export MOCK_RPM_OUTPUT="curl 7.76.1-29.el9"
  _update_record_end "dnf" 0
  grep -q "OK" "${_UPDATE_TMPDIR}/status_dnf"
  grep -q "curl 7.76.1-29.el9" "${_UPDATE_TMPDIR}/result_dnf"
}

@test "_update_record_end dnf reports no changes when packages unchanged" {
  printf "curl 7.76.1-26.el9\n" > "${_UPDATE_TMPDIR}/pre_dnf"
  export MOCK_RPM_OUTPUT="curl 7.76.1-26.el9"
  _update_record_end "dnf" 0
  grep -q "no changes" "${_UPDATE_TMPDIR}/result_dnf"
}

# ── _update_record_end — yum diff ─────────────────────────────────────────

@test "_update_record_end yum reports changed packages with name and version" {
  printf "curl 7.76.1-26.el8\n" > "${_UPDATE_TMPDIR}/pre_yum"
  export MOCK_RPM_OUTPUT="curl 7.76.1-29.el8"
  _update_record_end "yum" 0
  grep -q "OK" "${_UPDATE_TMPDIR}/status_yum"
  grep -q "curl 7.76.1-29.el8" "${_UPDATE_TMPDIR}/result_yum"
}

@test "_update_record_end yum reports no changes when packages unchanged" {
  printf "curl 7.76.1-26.el8\n" > "${_UPDATE_TMPDIR}/pre_yum"
  export MOCK_RPM_OUTPUT="curl 7.76.1-26.el8"
  _update_record_end "yum" 0
  grep -q "no changes" "${_UPDATE_TMPDIR}/result_yum"
}
```

- [ ] **Step 2: Run new tests to confirm they fail**

```bash
make test 2>&1 | grep -E "does not overwrite SKIP|apt reports changed|apt reports no changes|apt reports updated|apt writes FAIL|snap reports|dnf reports|yum reports" | head -40
```

Expected: failures (status files not written / wrong content).

### Step 3b — Implement

- [ ] **Step 3: Add SKIP guard at top of `_update_record_end` in `lib/update_summary.sh`**

In `_update_record_end`, immediately after `local _result=""`, add:

```bash
  # If _update_record_start already wrote a SKIP (e.g. wrong distro), leave it untouched
  if [[ -f "${_UPDATE_TMPDIR}/status_${_section}" ]]; then
    local _existing_status
    _existing_status=$(cat "${_UPDATE_TMPDIR}/status_${_section}")
    if [[ "${_existing_status}" == "SKIP" ]]; then
      return 0
    fi
  fi
```

- [ ] **Step 4: Add apt/snap/dnf/yum cases to `_update_record_end` in `lib/update_summary.sh`**

In the `case "${_section}" in` block inside `_update_record_end`, add before the `*)` catch-all:

```bash
    apt)
      dpkg-query -W -f='${Package} ${Version}\n' > "${_UPDATE_TMPDIR}/post_apt" 2>/dev/null || true
      if [[ -f "${_UPDATE_TMPDIR}/pre_apt" ]]; then
        local _apt_diff _apt_count
        _apt_diff=$(_update_diff_lines "${_UPDATE_TMPDIR}/pre_apt" "${_UPDATE_TMPDIR}/post_apt")
        _apt_count=$(printf '%s' "${_apt_diff}" | grep -c . || true)
        if [[ ${_apt_count} -gt 0 ]]; then
          _result="${_apt_count} package(s) ($(printf '%s' "${_apt_diff}" | paste -sd', ' -))"
        else
          _result="no changes"
        fi
      else
        _result="updated"
      fi
      ;;
    snap)
      snap list --color=never 2>/dev/null \
        | awk 'NR>1 {print $1, $2}' \
        > "${_UPDATE_TMPDIR}/post_snap" || true
      if [[ -f "${_UPDATE_TMPDIR}/pre_snap" ]]; then
        local _snap_diff _snap_count
        _snap_diff=$(_update_diff_lines "${_UPDATE_TMPDIR}/pre_snap" "${_UPDATE_TMPDIR}/post_snap")
        _snap_count=$(printf '%s' "${_snap_diff}" | grep -c . || true)
        if [[ ${_snap_count} -gt 0 ]]; then
          _result="${_snap_count} package(s) ($(printf '%s' "${_snap_diff}" | paste -sd', ' -))"
        else
          _result="no changes"
        fi
      else
        _result="updated"
      fi
      ;;
    dnf|yum)
      rpm -qa --qf '%{NAME} %{VERSION}-%{RELEASE}\n' > "${_UPDATE_TMPDIR}/post_${_section}" 2>/dev/null || true
      if [[ -f "${_UPDATE_TMPDIR}/pre_${_section}" ]]; then
        local _rpm_diff _rpm_count
        _rpm_diff=$(_update_diff_lines "${_UPDATE_TMPDIR}/pre_${_section}" "${_UPDATE_TMPDIR}/post_${_section}")
        _rpm_count=$(printf '%s' "${_rpm_diff}" | grep -c . || true)
        if [[ ${_rpm_count} -gt 0 ]]; then
          _result="${_rpm_count} package(s) ($(printf '%s' "${_rpm_diff}" | paste -sd', ' -))"
        else
          _result="no changes"
        fi
      else
        _result="updated"
      fi
      ;;
```

- [ ] **Step 5: Run all tests to confirm they pass**

```bash
make test 2>&1 | grep -E "does not overwrite SKIP|apt reports|snap reports|dnf reports|yum reports"
```

Expected: all lines show `ok`.

- [ ] **Step 6: Run full test suite to confirm nothing regressed**

```bash
make test
```

Expected: exit 0, no failures.

- [ ] **Step 7: Commit**

```bash
git add lib/update_summary.sh tests/setup_env/update_summary.bats
git commit -m "feat: add SKIP guard and apt/snap/dnf/yum diff cases to _update_record_end"
```

---

## Task 4: Restructure `run_update` in `workflows.sh`

Remove `update_system_packages` from the `mas` block and add a dedicated Linux system packages block.

**Files:**

- Modify: `lib/workflows.sh`
- Modify: `tests/setup_env/workflows.bats`

### Step 4a — Write failing tests

- [ ] **Step 1: Add `run_update` tests for Linux packages block and mas decoupling**

Append to `tests/setup_env/workflows.bats` after the `run_update skips softwareupdate on Linux` test:

```bash
# ── run_update — Linux system packages block ──────────────────────────────

@test "run_update calls dpkg-query on Ubuntu with no flags" {
  unset MACOS
  export LINUX=1
  export UBUNTU=1
  export NOBLE=1
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  export UPDATE_LOG_PATH="${BATS_TEST_TMPDIR}/update.log"
  unset UPDATE_BREW UPDATE_PIP UPDATE_GEMS UPDATE_MAS UPDATE_CLAUDE UPDATE_PKGS
  run_update
  grep -q "dpkg-query" "${MOCK_CALLS_FILE}"
}

@test "run_update Linux packages block skips apt with not applicable on macOS" {
  export MACOS=1
  unset LINUX UBUNTU
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  export UPDATE_LOG_PATH="${BATS_TEST_TMPDIR}/update.log"
  unset UPDATE_BREW UPDATE_PIP UPDATE_GEMS UPDATE_MAS UPDATE_CLAUDE UPDATE_PKGS
  run run_update
  grep -q "SKIP" "${_UPDATE_TMPDIR}/status_apt"
  grep -q "not applicable" "${_UPDATE_TMPDIR}/result_apt"
}

@test "run_update Linux packages block skips all four sections when UPDATE_PKGS not set and not run_all" {
  export MACOS=1
  unset LINUX UBUNTU
  export UPDATE_BREW=1
  unset UPDATE_PIP UPDATE_GEMS UPDATE_MAS UPDATE_CLAUDE UPDATE_PKGS
  export UPDATE_LOG_PATH="${BATS_TEST_TMPDIR}/update.log"
  run_update
  grep -q "SKIP" "${_UPDATE_TMPDIR}/status_apt"
  grep -q "flag not set" "${_UPDATE_TMPDIR}/result_apt"
  grep -q "flag not set" "${_UPDATE_TMPDIR}/result_snap"
  grep -q "flag not set" "${_UPDATE_TMPDIR}/result_dnf"
  grep -q "flag not set" "${_UPDATE_TMPDIR}/result_yum"
}

@test "run_update Linux packages block runs when UPDATE_PKGS is set on Ubuntu" {
  unset MACOS
  export LINUX=1
  export UBUNTU=1
  export NOBLE=1
  export UPDATE_PKGS=1
  unset UPDATE_BREW UPDATE_PIP UPDATE_GEMS UPDATE_MAS UPDATE_CLAUDE
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  export UPDATE_LOG_PATH="${BATS_TEST_TMPDIR}/update.log"
  run_update
  grep -q "dpkg-query" "${MOCK_CALLS_FILE}"
}

@test "run_update does not call update_system_packages from mas block on Linux" {
  unset MACOS
  export LINUX=1
  export UBUNTU=1
  export NOBLE=1
  export UPDATE_MAS=1
  unset UPDATE_BREW UPDATE_PIP UPDATE_GEMS UPDATE_CLAUDE UPDATE_PKGS
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  export UPDATE_LOG_PATH="${BATS_TEST_TMPDIR}/update.log"
  run_update
  # dpkg-query is called by update_system_packages on Ubuntu — must NOT appear
  ! grep -q "dpkg-query" "${MOCK_CALLS_FILE}"
}

@test "run_update apt section shows not applicable on RHEL" {
  unset MACOS UBUNTU CENTOS
  export LINUX=1
  export REDHAT=1
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  export UPDATE_LOG_PATH="${BATS_TEST_TMPDIR}/update.log"
  unset UPDATE_BREW UPDATE_PIP UPDATE_GEMS UPDATE_MAS UPDATE_CLAUDE UPDATE_PKGS
  run_update
  grep -q "SKIP" "${_UPDATE_TMPDIR}/status_apt"
  grep -q "not applicable" "${_UPDATE_TMPDIR}/result_apt"
}
```

- [ ] **Step 2: Run new tests to confirm they fail**

```bash
make test 2>&1 | grep -E "dpkg-query on Ubuntu|not applicable on macOS|flag not set|UPDATE_PKGS|mas block on Linux|not applicable on RHEL" | head -30
```

Expected: failures.

### Step 4b — Implement

- [ ] **Step 3: Remove `update_system_packages` from the `mas` block in `lib/workflows.sh`**

In `run_update`, find the `# ── mas + system packages` block:

```bash
  # ── mas + system packages ─────────────────────────────────────────────────
  if [[ ${_run_all} -eq 1 ]] || [[ -n ${UPDATE_MAS:-} ]]; then
    _update_record_start "mas"
    update_system_packages
    local _mas_ec=0
```

Replace with:

```bash
  # ── mas ───────────────────────────────────────────────────────────────────
  if [[ ${_run_all} -eq 1 ]] || [[ -n ${UPDATE_MAS:-} ]]; then
    _update_record_start "mas"
    local _mas_ec=0
```

Also update the section comment in the `run_update` function header comment area if needed.

- [ ] **Step 4: Add `# Linux system packages` block to `run_update` in `lib/workflows.sh`**

Insert this block between the `# ── brew + softwareupdate` block and the `# ── claude plugins` block (after the closing `fi` of the brew/softwareupdate block):

```bash
  # ── Linux system packages ─────────────────────────────────────────────────
  if [[ ${_run_all} -eq 1 ]] || [[ -n ${UPDATE_PKGS:-} ]]; then
    if [[ -n ${LINUX} ]]; then
      _update_record_start "apt"
      _update_record_start "snap"
      _update_record_start "dnf"
      _update_record_start "yum"
      update_system_packages
      local _pkg_ec=$?
      _update_record_end "apt"  "${_pkg_ec}"
      _update_record_end "snap" "${_pkg_ec}"
      _update_record_end "dnf"  "${_pkg_ec}"
      _update_record_end "yum"  "${_pkg_ec}"
    else
      _update_skip "apt"  "not applicable"
      _update_skip "snap" "not applicable"
      _update_skip "dnf"  "not applicable"
      _update_skip "yum"  "not applicable"
    fi
  else
    _update_skip "apt"  "flag not set"
    _update_skip "snap" "flag not set"
    _update_skip "dnf"  "flag not set"
    _update_skip "yum"  "flag not set"
  fi
```

- [ ] **Step 5: Run all tests to confirm they pass**

```bash
make test 2>&1 | grep -E "dpkg-query on Ubuntu|not applicable on macOS|flag not set|UPDATE_PKGS|mas block on Linux|not applicable on RHEL"
```

Expected: all lines show `ok`.

- [ ] **Step 6: Run full test suite**

```bash
make test
```

Expected: exit 0.

- [ ] **Step 7: Commit**

```bash
git add lib/workflows.sh tests/setup_env/workflows.bats
git commit -m "feat: add Linux system packages block to run_update, remove from mas block"
```

---

## Task 5: Add `--pkgs-only` flag

**Files:**

- Modify: `lib/helpers.sh`
- Modify: `tests/setup_env/workflows.bats`

### Step 5a — Write failing tests

- [ ] **Step 1: Add `--pkgs-only` and `_any_update_flag` tests**

Append to `tests/setup_env/workflows.bats` after the Linux packages block tests:

```bash
# ── process_args --pkgs-only ──────────────────────────────────────────────

@test "process_args --pkgs-only sets UPDATE_PKGS" {
  unset UPDATE_PKGS
  process_args --pkgs-only
  [ -n "${UPDATE_PKGS:-}" ]
}

@test "process_args --pkgs-only twice does not crash" {
  unset UPDATE_PKGS
  process_args --pkgs-only
  local _rc=0
  process_args --pkgs-only || _rc=$?
  [ "${_rc}" -eq 0 ]
}

@test "_any_update_flag returns true when UPDATE_PKGS is set" {
  unset UPDATE_BREW UPDATE_PIP UPDATE_GEMS UPDATE_MAS UPDATE_CLAUDE UPDATE_PKGS
  export UPDATE_PKGS=1
  _any_update_flag
}

@test "_any_update_flag returns false when only UPDATE_PKGS is unset among all flags" {
  unset UPDATE_BREW UPDATE_PIP UPDATE_GEMS UPDATE_MAS UPDATE_CLAUDE UPDATE_PKGS
  local _rc=0
  _any_update_flag || _rc=$?
  [ "${_rc}" -ne 0 ]
}
```

- [ ] **Step 2: Run new tests to confirm they fail**

```bash
make test 2>&1 | grep -E "pkgs-only sets UPDATE_PKGS|pkgs-only twice|UPDATE_PKGS is set|UPDATE_PKGS is unset" | head -20
```

Expected: failures.

### Step 5b — Implement

- [ ] **Step 3: Add `UPDATE_PKGS` to `_any_update_flag` in `lib/helpers.sh`**

Find `_any_update_flag`:

```bash
_any_update_flag() {
  [[ -n ${UPDATE_BREW:-}   ]] || [[ -n ${UPDATE_PIP:-}    ]] || \
  [[ -n ${UPDATE_GEMS:-}   ]] || [[ -n ${UPDATE_MAS:-}    ]] || \
  [[ -n ${UPDATE_CLAUDE:-} ]]
}
```

Replace with:

```bash
_any_update_flag() {
  [[ -n ${UPDATE_BREW:-}   ]] || [[ -n ${UPDATE_PIP:-}    ]] || \
  [[ -n ${UPDATE_GEMS:-}   ]] || [[ -n ${UPDATE_MAS:-}    ]] || \
  [[ -n ${UPDATE_PKGS:-}   ]] || [[ -n ${UPDATE_CLAUDE:-} ]]
}
```

- [ ] **Step 4: Add `--pkgs-only` case to `process_args` in `lib/helpers.sh`**

In the `for _arg in "$@"` loop inside `process_args`, after the `--claude-only)` line:

```bash
      --pkgs-only)     [[ -n "${UPDATE_PKGS+x}" ]]     || readonly UPDATE_PKGS=1 ;;
```

- [ ] **Step 5: Update the `usage()` string in `lib/helpers.sh`**

Find the update flags section in the usage heredoc:

```
  --claude-only   : (update only) Update Claude plugins only
```

Add after it:

```
  --pkgs-only     : (update only) Update Linux system packages only (apt/snap/dnf/yum)
```

- [ ] **Step 6: Run all tests to confirm they pass**

```bash
make test 2>&1 | grep -E "pkgs-only sets UPDATE_PKGS|pkgs-only twice|UPDATE_PKGS is set|UPDATE_PKGS is unset"
```

Expected: all lines show `ok`.

- [ ] **Step 7: Run full test suite**

```bash
make test
```

Expected: exit 0.

- [ ] **Step 8: Commit**

```bash
git add lib/helpers.sh tests/setup_env/workflows.bats
git commit -m "feat: add --pkgs-only flag for Linux system package updates"
```

---

## Task 6: Update docs and README

**Files:**

- Modify: `README.md`
- Modify: `docs/superpowers/README.md`

- [ ] **Step 1: Update README.md options table**

In the options table, find the `--claude-only` row and add a row after it:

```markdown
- `--pkgs-only` — update Linux system packages only (apt/snap/dnf/yum) (with `-t update`)
```

Also update the update summary example output in README.md to show the new sections. Find the example block and add the four new lines between `softwareupdate` and `mas`:

```
[OK]   apt              14 package(s) (curl 7.88.1, git 2.44.0, ...)
[OK]   snap             2 package(s) (firefox 124.0, chromium 123.0)
[SKIP] dnf              not applicable
[SKIP] yum              not applicable
```

- [ ] **Step 2: Update `docs/superpowers/README.md` plan status**

Change the `linux-package-update-tracking` row from `Pending` to `In Progress`:

```markdown
| 2026-04-16 | [linux-package-update-tracking](plans/2026-04-16-linux-package-update-tracking.md) | [spec](specs/2026-04-16-linux-package-update-tracking-design.md) | In Progress |
```

Also link the plan file:

```markdown
| 2026-04-16 | [linux-package-update-tracking](plans/2026-04-16-linux-package-update-tracking.md) | [spec](specs/2026-04-16-linux-package-update-tracking-design.md) | In Progress |
```

- [ ] **Step 3: Run full test suite one final time**

```bash
make test
```

Expected: exit 0.

- [ ] **Step 4: Commit**

```bash
git add README.md docs/superpowers/README.md docs/superpowers/plans/2026-04-16-linux-package-update-tracking.md
git commit -m "docs: add --pkgs-only to README, mark linux-package-update-tracking in progress"
```

---

## Task 7: Open PR

- [ ] **Step 1: Push feature branch**

```bash
git push -u origin feature/linux-package-update-tracking
```

- [ ] **Step 2: Open PR**

```bash
gh pr create \
  --title "feat: track Linux package updates (apt/snap/dnf/yum) in update summary" \
  --body "$(cat <<'EOF'
## Summary
- Adds apt, snap, dnf, yum sections to the update summary with per-package name+version diffs
- Uses pre/post dpkg-query/snap list/rpm snapshot pattern matching existing brew implementation
- Removes update_system_packages from the mas block; adds dedicated Linux packages block
- Adds --pkgs-only flag for running Linux package updates independently

## Test plan
- [ ] All new _update_record_start cases: apt/snap/dnf/yum create pre-snapshot on correct distro, write SKIP "not applicable" on wrong distro
- [ ] All new _update_record_end cases: diff reports changed packages, "no changes" when unchanged, SKIP not overwritten
- [ ] run_update Linux packages block: apt/snap called on Ubuntu, dnf on RHEL/Fedora, yum on CentOS, all skipped "not applicable" on macOS
- [ ] --pkgs-only flag sets UPDATE_PKGS; double-invocation safe; _any_update_flag recognizes it
- [ ] update_system_packages not called from mas block (UPDATE_MAS-only run on Linux does not call dpkg-query)

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 3: Verify CI passes and PR auto-merges**

```bash
gh pr view --json state,statusCheckRollup
```

Expected: CI green, PR merges automatically.

- [ ] **Step 4: After merge, mark plan Done in `docs/superpowers/README.md`**

Change `In Progress` to `Done` in the `linux-package-update-tracking` row, commit to master, and add `> **Status: DONE**` at the top of this plan file.
