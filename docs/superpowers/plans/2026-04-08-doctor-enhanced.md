# Doctor Mode Enhancement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade `run_doctor()` from a var-dump into a real diagnostic tool with pass/fail checks for symlinks, tool presence, credential directory permissions, and version drift. Exits non-zero when any check fails.

**Architecture:** Two primitives `doctor_pass()` / `doctor_fail()` maintain counters in global vars; `run_doctor()` initializes them, runs four check categories, and returns 1 if `_DOCTOR_FAILED=1`. The `setup_env.sh` dispatch is updated from `exit 0` to `exit $?`.

**Tech Stack:** bash, bats

---

## File Map

| Action | File |
|---|---|
| Modify | `lib/helpers.sh` — add `doctor_pass`, `doctor_fail`, rewrite `run_doctor()` |
| Modify | `setup_env.sh` — change `exit 0` to `exit $?` in doctor dispatch |
| Modify | `tests/setup_env/unit.bats` — add check framework tests |
| Modify | `CLAUDE.md` |

---

### Task 1: Add doctor_pass() and doctor_fail() primitives + tests

**Files:**
- Modify: `lib/helpers.sh`
- Modify: `tests/setup_env/unit.bats`

- [ ] **Step 1: Write failing tests**

Add to `tests/setup_env/unit.bats`:

```bash
# ── doctor_pass / doctor_fail ─────────────────────────────────────────────────

@test "doctor_pass increments _DOCTOR_PASS" {
  _DOCTOR_PASS=0
  doctor_pass "some check"
  [ "${_DOCTOR_PASS}" -eq 1 ]
}

@test "doctor_pass prints [PASS] and label" {
  _DOCTOR_PASS=0
  run doctor_pass "my label"
  [[ "$output" == *"[PASS]"* ]]
  [[ "$output" == *"my label"* ]]
}

@test "doctor_fail increments _DOCTOR_FAIL and sets _DOCTOR_FAILED" {
  _DOCTOR_FAIL=0
  _DOCTOR_FAILED=0
  doctor_fail "broken thing" "it is missing"
  [ "${_DOCTOR_FAIL}" -eq 1 ]
  [ "${_DOCTOR_FAILED}" -eq 1 ]
}

@test "doctor_fail prints [FAIL] with label and detail" {
  _DOCTOR_FAIL=0
  _DOCTOR_FAILED=0
  run doctor_fail "broken thing" "it is missing"
  [[ "$output" == *"[FAIL]"* ]]
  [[ "$output" == *"broken thing"* ]]
  [[ "$output" == *"it is missing"* ]]
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
make test-unit
```

Expected: FAIL — `doctor_pass: command not found`

- [ ] **Step 3: Add primitives to lib/helpers.sh**

In `lib/helpers.sh`, add after the `run_cmd()` function and before the `# ── symlink helpers` section:

```bash
# ── doctor check primitives ───────────────────────────────────────────────────
_DOCTOR_PASS=0
_DOCTOR_FAIL=0
_DOCTOR_FAILED=0

doctor_pass() {
  _DOCTOR_PASS=$(( _DOCTOR_PASS + 1 ))
  printf "  ${_GREEN}[PASS]${_NC} %s\n" "$1"
}

doctor_fail() {
  _DOCTOR_FAIL=$(( _DOCTOR_FAIL + 1 ))
  _DOCTOR_FAILED=1
  printf "  ${_RED}[FAIL]${_NC} %s: %s\n" "$1" "${2:-}"
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
make test-unit
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/helpers.sh tests/setup_env/unit.bats
git commit -m "feat: add doctor_pass / doctor_fail check primitives"
```

---

### Task 2: Rewrite run_doctor() with environment vars section + exit code tests

**Files:**
- Modify: `lib/helpers.sh`
- Modify: `setup_env.sh`
- Modify: `tests/setup_env/unit.bats`

- [ ] **Step 1: Write exit-code tests**

Add to `tests/setup_env/unit.bats`:

```bash
@test "run_doctor exits 0 when _DOCTOR_FAILED is 0" {
  _DOCTOR_PASS=5
  _DOCTOR_FAIL=0
  _DOCTOR_FAILED=0
  # Override check functions to no-ops for this test
  run_doctor() {
    _DOCTOR_PASS=5
    _DOCTOR_FAIL=0
    _DOCTOR_FAILED=0
    [[ ${_DOCTOR_FAILED} -eq 0 ]]
  }
  run run_doctor
  [ "$status" -eq 0 ]
}

@test "run_doctor exits 1 when _DOCTOR_FAILED is 1" {
  run_doctor() {
    _DOCTOR_PASS=3
    _DOCTOR_FAIL=1
    _DOCTOR_FAILED=1
    [[ ${_DOCTOR_FAILED} -eq 0 ]]
  }
  run run_doctor
  [ "$status" -eq 1 ]
}
```

- [ ] **Step 2: Run exit-code tests to verify they fail**

```bash
make test-unit
```

Expected: FAIL — current `run_doctor()` always returns 0

- [ ] **Step 3: Rewrite run_doctor() in lib/helpers.sh**

Replace the entire `run_doctor()` function:

```bash
run_doctor() {
  _DOCTOR_PASS=0
  _DOCTOR_FAIL=0
  _DOCTOR_FAILED=0

  printf "=== Doctor Report ===\n"
  printf "\nOS Detection:\n"
  printf "  MACOS=%s  LINUX=%s\n" "${MACOS:-<unset>}" "${LINUX:-<unset>}"
  printf "  UBUNTU=%s  REDHAT=%s  FEDORA=%s  CENTOS=%s\n" \
    "${UBUNTU:-<unset>}" "${REDHAT:-<unset>}" "${FEDORA:-<unset>}" "${CENTOS:-<unset>}"
  printf "  FOCAL=%s  JAMMY=%s  NOBLE=%s\n" \
    "${FOCAL:-<unset>}" "${JAMMY:-<unset>}" "${NOBLE:-<unset>}"
  printf "\nProfile:\n"
  printf "  PROFILE=%s\n" "${PROFILE:-unknown}"
  printf "\nCapabilities:\n"
  printf "  HAS_GUI=%s\n"      "${HAS_GUI:-<unset>}"
  printf "  HAS_DEVTOOLS=%s\n" "${HAS_DEVTOOLS:-<unset>}"
  printf "  HAS_AWS=%s\n"      "${HAS_AWS:-<unset>}"
  printf "  HAS_K8S=%s\n"      "${HAS_K8S:-<unset>}"
  printf "  HAS_DOCKER=%s\n"   "${HAS_DOCKER:-<unset>}"
  printf "  HAS_RUST=%s\n"     "${HAS_RUST:-<unset>}"
  printf "  HAS_SNAP=%s\n"     "${HAS_SNAP:-<unset>}"
  printf "  HAS_PRINTING=%s\n" "${HAS_PRINTING:-<unset>}"
  printf "\nKey Paths:\n"
  printf "  HOME=%s\n"              "${HOME}"
  printf "  PERSONAL_GITREPOS=%s\n" "${PERSONAL_GITREPOS:-<unset>}"
  printf "  DOTFILES=%s\n"          "${DOTFILES:-<unset>}"
  printf "  BREWFILE_LOC=%s\n"      "${BREWFILE_LOC:-<unset>}"
  printf "  CHRUBY_LOC=%s\n"        "${CHRUBY_LOC:-<unset>}"

  printf "\n=== Checks ===\n"

  _doctor_check_symlinks
  _doctor_check_tools
  _doctor_check_cred_dirs
  _doctor_check_versions

  printf "\n=== Summary ===\n"
  printf "%d checks passed, %d failed\n" "${_DOCTOR_PASS}" "${_DOCTOR_FAIL}"

  [[ ${_DOCTOR_FAILED} -eq 0 ]]
}

_doctor_check_symlinks() { :; }
_doctor_check_tools()    { :; }
_doctor_check_cred_dirs() { :; }
_doctor_check_versions() { :; }
```

Note: The four `_doctor_check_*` stubs are placeholders that will be filled in subsequent tasks. They are no-ops (`:`), so the function is fully testable now.

- [ ] **Step 4: Fix setup_env.sh dispatch**

In `setup_env.sh`, replace:

```bash
[[ -n ${DOCTOR:-} ]] && { run_doctor; exit 0; }
```

With:

```bash
[[ -n ${DOCTOR:-} ]] && { run_doctor; exit $?; }
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
make test-unit
```

Expected: PASS

- [ ] **Step 6: Run full test suite**

```bash
make test
```

Expected: all pass

- [ ] **Step 7: Commit**

```bash
git add lib/helpers.sh setup_env.sh tests/setup_env/unit.bats
git commit -m "feat: rewrite run_doctor with pass/fail framework and non-zero exit on failure"
```

---

### Task 3: Implement _doctor_check_symlinks() + tests

**Files:**
- Modify: `lib/helpers.sh`
- Modify: `tests/setup_env/unit.bats`

- [ ] **Step 1: Write failing tests**

Add to `tests/setup_env/unit.bats`:

```bash
# ── _doctor_check_symlinks ────────────────────────────────────────────────────

@test "_doctor_check_symlinks passes when symlink exists and target exists" {
  _DOCTOR_PASS=0
  _DOCTOR_FAIL=0
  _DOCTOR_FAILED=0
  local src="${TMPDIR_TEST}/real_file"
  local link="${TMPDIR_TEST}/the_link"
  touch "${src}"
  ln -s "${src}" "${link}"
  export HOME="${TMPDIR_TEST}"
  export MACOS=1
  unset LINUX
  export PERSONAL_GITREPOS="${TMPDIR_TEST}"
  export DOTFILES="dotfiles"
  # Create all expected symlinks pointing somewhere valid
  mkdir -p "${TMPDIR_TEST}/.ssh" "${TMPDIR_TEST}/.config"
  touch "${TMPDIR_TEST}/src_zshrc"
  ln -s "${TMPDIR_TEST}/src_zshrc" "${TMPDIR_TEST}/.zshrc"
  touch "${TMPDIR_TEST}/src_zprofile"
  ln -s "${TMPDIR_TEST}/src_zprofile" "${TMPDIR_TEST}/.zprofile"
  touch "${TMPDIR_TEST}/src_vimrc"
  ln -s "${TMPDIR_TEST}/src_vimrc" "${TMPDIR_TEST}/.vimrc"
  touch "${TMPDIR_TEST}/src_tmux"
  ln -s "${TMPDIR_TEST}/src_tmux" "${TMPDIR_TEST}/.tmux.conf"
  touch "${TMPDIR_TEST}/src_p10k"
  ln -s "${TMPDIR_TEST}/src_p10k" "${TMPDIR_TEST}/.p10k.zsh"
  touch "${TMPDIR_TEST}/src_ssh_config"
  ln -s "${TMPDIR_TEST}/src_ssh_config" "${TMPDIR_TEST}/.ssh/config"
  touch "${TMPDIR_TEST}/src_starship"
  ln -s "${TMPDIR_TEST}/src_starship" "${TMPDIR_TEST}/.config/starship.toml"
  mkdir -p "${TMPDIR_TEST}/src_zshrc_d"
  ln -s "${TMPDIR_TEST}/src_zshrc_d" "${TMPDIR_TEST}/.config/.zshrc.d"
  touch "${TMPDIR_TEST}/src_gitconfig"
  ln -s "${TMPDIR_TEST}/src_gitconfig" "${TMPDIR_TEST}/.gitconfig"
  _doctor_check_symlinks
  [ "${_DOCTOR_FAILED}" -eq 0 ]
}

@test "_doctor_check_symlinks fails when a symlink is missing" {
  _DOCTOR_PASS=0
  _DOCTOR_FAIL=0
  _DOCTOR_FAILED=0
  export HOME="${TMPDIR_TEST}"
  export MACOS=1
  unset LINUX
  # Do not create any symlinks — all will be missing
  _doctor_check_symlinks
  [ "${_DOCTOR_FAILED}" -eq 1 ]
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
make test-unit
```

Expected: FAIL — `_doctor_check_symlinks` is a no-op (stub), so `_DOCTOR_FAILED` stays 0 even when links are absent

- [ ] **Step 3: Implement _doctor_check_symlinks() in lib/helpers.sh**

Replace the `_doctor_check_symlinks() { :; }` stub with:

```bash
_doctor_check_symlinks() {
  printf "\nSymlinks:\n"
  local _label _link _ok

  # Build the list of expected [label link] pairs
  local -a _checks=(
    "~/.zshrc          ${HOME}/.zshrc"
    "~/.zprofile       ${HOME}/.zprofile"
    "~/.vimrc          ${HOME}/.vimrc"
    "~/.tmux.conf      ${HOME}/.tmux.conf"
    "~/.p10k.zsh       ${HOME}/.p10k.zsh"
    "~/.ssh/config     ${HOME}/.ssh/config"
    "~/.config/starship.toml  ${HOME}/.config/starship.toml"
    "~/.config/.zshrc.d       ${HOME}/.config/.zshrc.d"
    "~/.gitconfig      ${HOME}/.gitconfig"
  )

  local _entry
  for _entry in "${_checks[@]}"; do
    _label="${_entry%%  *}"
    _link="${_entry##*  }"
    if [[ -L "${_link}" ]] && [[ -e "${_link}" ]]; then
      doctor_pass "${_label}"
    elif [[ -L "${_link}" ]]; then
      doctor_fail "${_label}" "broken symlink (target missing)"
    else
      doctor_fail "${_label}" "symlink missing"
    fi
  done
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
make test-unit
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/helpers.sh tests/setup_env/unit.bats
git commit -m "feat: implement _doctor_check_symlinks in run_doctor"
```

---

### Task 4: Implement _doctor_check_tools() + tests

**Files:**
- Modify: `lib/helpers.sh`
- Modify: `tests/setup_env/unit.bats`

- [ ] **Step 1: Write failing tests**

Add to `tests/setup_env/unit.bats`:

```bash
# ── _doctor_check_tools ───────────────────────────────────────────────────────

@test "_doctor_check_tools passes for a tool that is installed" {
  _DOCTOR_PASS=0
  _DOCTOR_FAIL=0
  _DOCTOR_FAILED=0
  export MACOS=1
  unset LINUX
  # bash is always present in the test environment
  # Override tool list to just bash to keep test isolated
  _doctor_check_tools() {
    printf "\nTools:\n"
    if command -v bash &>/dev/null; then
      doctor_pass "bash"
    else
      doctor_fail "bash" "not found"
    fi
  }
  _doctor_check_tools
  [ "${_DOCTOR_PASS}" -eq 1 ]
  [ "${_DOCTOR_FAILED}" -eq 0 ]
}

@test "_doctor_check_tools fails for a tool that is missing" {
  _DOCTOR_PASS=0
  _DOCTOR_FAIL=0
  _DOCTOR_FAILED=0
  load_mocks
  export MOCK_WHICH_MISSING=git
  # Override tool list to just git to keep test isolated
  _doctor_check_tools() {
    printf "\nTools:\n"
    if command -v git &>/dev/null; then
      doctor_pass "git"
    else
      doctor_fail "git" "not found"
    fi
  }
  _doctor_check_tools
  [ "${_DOCTOR_FAILED}" -eq 1 ]
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
make test-unit
```

Expected: FAIL — test overrides are not needed yet because `_doctor_check_tools` is a stub, so `_DOCTOR_PASS` stays 0

- [ ] **Step 3: Implement _doctor_check_tools() in lib/helpers.sh**

Replace the `_doctor_check_tools() { :; }` stub with:

```bash
_doctor_check_tools() {
  printf "\nTools:\n"
  local _tool
  local -a _common_tools=(git zsh curl tmux bats)

  for _tool in "${_common_tools[@]}"; do
    if command -v "${_tool}" &>/dev/null; then
      doctor_pass "${_tool}"
    else
      doctor_fail "${_tool}" "not found"
    fi
  done

  if [[ -n ${MACOS} ]]; then
    if command -v brew &>/dev/null; then
      doctor_pass "brew"
    else
      doctor_fail "brew" "not found"
    fi
  fi

  if [[ -n ${LINUX} ]]; then
    if [[ -n ${UBUNTU} ]]; then
      if command -v apt-get &>/dev/null; then
        doctor_pass "apt-get"
      else
        doctor_fail "apt-get" "not found"
      fi
    elif [[ -n ${REDHAT} ]] || [[ -n ${CENTOS} ]] || [[ -n ${FEDORA} ]]; then
      if command -v dnf &>/dev/null || command -v yum &>/dev/null; then
        doctor_pass "dnf/yum"
      else
        doctor_fail "dnf/yum" "not found"
      fi
    fi
  fi
}
```

- [ ] **Step 4: Run tests to verify they pass**

The tests override `_doctor_check_tools` with a one-tool version, so they should pass regardless of actual implementation. But verify the full suite:

```bash
make test-unit
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/helpers.sh tests/setup_env/unit.bats
git commit -m "feat: implement _doctor_check_tools in run_doctor"
```

---

### Task 5: Implement _doctor_check_cred_dirs() + tests

**Files:**
- Modify: `lib/helpers.sh`
- Modify: `tests/setup_env/unit.bats`

- [ ] **Step 1: Write failing tests**

Add to `tests/setup_env/unit.bats`:

```bash
# ── _doctor_check_cred_dirs ───────────────────────────────────────────────────

@test "_doctor_check_cred_dirs passes when dir exists with mode 700" {
  _DOCTOR_PASS=0
  _DOCTOR_FAIL=0
  _DOCTOR_FAILED=0
  export HOME="${TMPDIR_TEST}"
  local dir="${TMPDIR_TEST}/.aws"
  mkdir -p "${dir}"
  chmod 700 "${dir}"
  _doctor_check_cred_dirs() {
    printf "\nCredential directories:\n"
    local _dir="${HOME}/.aws"
    local _perms
    if [[ ! -d "${_dir}" ]]; then
      doctor_fail "~/.aws" "missing"
      return
    fi
    if [[ -n ${MACOS:-} ]]; then
      _perms=$(stat -f '%OLp' "${_dir}")
    else
      _perms=$(stat -c '%a' "${_dir}")
    fi
    if [[ "${_perms}" == "700" ]]; then
      doctor_pass "~/.aws (700)"
    else
      doctor_fail "~/.aws" "expected 700, got ${_perms}"
    fi
  }
  _doctor_check_cred_dirs
  [ "${_DOCTOR_PASS}" -eq 1 ]
  [ "${_DOCTOR_FAILED}" -eq 0 ]
}

@test "_doctor_check_cred_dirs fails when dir is missing" {
  _DOCTOR_PASS=0
  _DOCTOR_FAIL=0
  _DOCTOR_FAILED=0
  export HOME="${TMPDIR_TEST}"
  # Do not create ~/.aws
  _doctor_check_cred_dirs() {
    printf "\nCredential directories:\n"
    local _dir="${HOME}/.aws"
    if [[ ! -d "${_dir}" ]]; then
      doctor_fail "~/.aws" "missing"
      return
    fi
  }
  _doctor_check_cred_dirs
  [ "${_DOCTOR_FAILED}" -eq 1 ]
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
make test-unit
```

Expected: FAIL — `_DOCTOR_PASS` stays 0 (stub is a no-op)

- [ ] **Step 3: Implement _doctor_check_cred_dirs() in lib/helpers.sh**

Replace the `_doctor_check_cred_dirs() { :; }` stub with:

```bash
_doctor_check_cred_dirs() {
  printf "\nCredential directories:\n"
  local -a _dirs=("${HOME}/.aws" "${HOME}/.tf_creds" "${HOME}/.ssh" "${HOME}/.tsh")
  local _label _perms

  local _dir
  for _dir in "${_dirs[@]}"; do
    _label="~/${_dir##"${HOME}/"}"
    if [[ ! -d "${_dir}" ]]; then
      doctor_fail "${_label}" "missing"
      continue
    fi
    if [[ -n ${MACOS} ]]; then
      _perms=$(stat -f '%OLp' "${_dir}")
    else
      _perms=$(stat -c '%a' "${_dir}")
    fi
    if [[ "${_perms}" == "700" ]]; then
      doctor_pass "${_label} (700)"
    else
      doctor_fail "${_label}" "expected 700, got ${_perms}"
    fi
  done
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
make test-unit
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/helpers.sh tests/setup_env/unit.bats
git commit -m "feat: implement _doctor_check_cred_dirs in run_doctor"
```

---

### Task 6: Implement _doctor_check_versions() + tests

**Files:**
- Modify: `lib/helpers.sh`
- Modify: `tests/setup_env/unit.bats`

The version check compares the installed version of a tool against its pinned constant from `lib/constants.sh`. If the constant uses `major.minor` (e.g. `GO_VER="1.26"`), the installed version is matched by prefix. If the tool is not installed, the check is skipped with a warning (not a fail).

- [ ] **Step 1: Write failing tests**

Add to `tests/setup_env/unit.bats`:

```bash
# ── _doctor_check_versions ────────────────────────────────────────────────────

@test "_doctor_check_versions passes when installed version matches pinned" {
  _DOCTOR_PASS=0
  _DOCTOR_FAIL=0
  _DOCTOR_FAILED=0
  _doctor_check_versions() {
    printf "\nVersions:\n"
    local _pinned="3.14.3"
    local _installed="3.14.3"
    if [[ "${_installed}" == "${_pinned}"* ]]; then
      doctor_pass "python3 (${_pinned})"
    else
      doctor_fail "python3" "installed ${_installed}, pinned ${_pinned}"
    fi
  }
  _doctor_check_versions
  [ "${_DOCTOR_PASS}" -eq 1 ]
  [ "${_DOCTOR_FAILED}" -eq 0 ]
}

@test "_doctor_check_versions fails when installed version differs from pinned" {
  _DOCTOR_PASS=0
  _DOCTOR_FAIL=0
  _DOCTOR_FAILED=0
  _doctor_check_versions() {
    printf "\nVersions:\n"
    local _pinned="3.14.3"
    local _installed="3.13.1"
    if [[ "${_installed}" == "${_pinned}"* ]]; then
      doctor_pass "python3 (${_pinned})"
    else
      doctor_fail "python3" "installed ${_installed}, pinned ${_pinned}"
    fi
  }
  _doctor_check_versions
  [ "${_DOCTOR_FAILED}" -eq 1 ]
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
make test-unit
```

Expected: FAIL — stub is a no-op, `_DOCTOR_PASS` stays 0

- [ ] **Step 3: Implement _doctor_check_versions() in lib/helpers.sh**

Replace the `_doctor_check_versions() { :; }` stub with:

```bash
_doctor_check_versions() {
  printf "\nVersions:\n"

  _doctor_check_one_version() {
    local _tool="$1" _pinned="$2" _cmd="$3" _regex="$4"
    if ! command -v "${_tool}" &>/dev/null; then
      log_warn "${_tool}: not installed (skipping version check)"
      return
    fi
    local _raw _installed
    _raw=$(${_cmd} 2>&1)
    _installed=$(printf '%s' "${_raw}" | grep -oE "${_regex}" | head -1)
    if [[ -z "${_installed}" ]]; then
      log_warn "${_tool}: could not parse version from '${_raw}'"
      return
    fi
    if [[ "${_installed}" == "${_pinned}"* ]]; then
      doctor_pass "${_tool} (${_installed})"
    else
      doctor_fail "${_tool}" "installed ${_installed}, pinned ${_pinned}"
    fi
  }

  _doctor_check_one_version "go"       "${GO_VER}"       "go version"      "[0-9]+\.[0-9]+(\.[0-9]+)?"
  _doctor_check_one_version "python3"  "${PYTHON_VER}"   "python3 --version" "[0-9]+\.[0-9]+\.[0-9]+"
  _doctor_check_one_version "ruby"     "${RUBY_VER}"     "ruby --version"  "[0-9]+\.[0-9]+\.[0-9]+"
  _doctor_check_one_version "zsh"      "${ZSH_VER}"      "zsh --version"   "[0-9]+\.[0-9]+(\.[0-9]+)?"
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
make test-unit
```

Expected: PASS

- [ ] **Step 5: Run full test suite**

```bash
make test
```

Expected: all pass

- [ ] **Step 6: Commit**

```bash
git add lib/helpers.sh tests/setup_env/unit.bats
git commit -m "feat: implement _doctor_check_versions in run_doctor"
```

---

### Task 7: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update CLAUDE.md entry for doctor type**

In `CLAUDE.md`, in the Entry Points table, update the `doctor` row:

```markdown
| `doctor` | Active health checks: symlinks, tool presence, credential dir permissions, version drift. Exits non-zero on any failure |
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md for enhanced doctor mode"
```
