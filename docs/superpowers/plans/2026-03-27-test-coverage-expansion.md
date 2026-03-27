# Test Coverage Expansion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expand BATS test coverage from 42% (8/19 functions) to ~95% by adding quick-win and medium tests for untested functions, fixing a bug in `install_git`, making `install_rosetta` testable, and extracting 7 inline code blocks into named, tested functions.

**Architecture:** Tests are organized into three files under `tests/setup_env/`: existing `install_guards.bats` (extended with quick-win tests), new `install_functions.bats` (install_git/zsh/rosetta/nala), and new `extracted_functions.bats` (for the newly extracted functions). New mock executables in `tests/mocks/` shadow system commands via PATH. All extracted functions follow the existing pattern: named function added above the sourcing guard, inline call site replaced with the function call.

**Tech Stack:** BATS 1.11.0, bash mock scripts, PATH-based mock injection

---

## File Structure

**New mock files (all in `tests/mocks/`):**
- `id` — configurable `id -u` output for `ensure_not_root`
- `yum` — configurable exit codes for `yum list installed` and other yum calls
- `awk` — returns `MOCK_AWK_OS_NAME` when invoked against `os-release`, delegates otherwise
- `sw_vers` — returns `MOCK_SW_VERS_PRODUCTVERSION` for `-productVersion`
- `sysctl` — returns `MOCK_SYSCTL_CPU` for `-n machdep.cpu.brand_string`
- `pgrep` — returns `MOCK_PGREP_EXIT` (default 1)
- `softwareupdate` — logs call, returns `MOCK_SOFTWAREUPDATE_EXIT` (default 0)
- `wget` — logs call, creates placeholder output file, returns `MOCK_WGET_EXIT` (default 0)
- `dpkg` — logs call, returns `MOCK_DPKG_EXIT` (default 0)
- `chsh` — logs call, returns `MOCK_CHSH_EXIT` (default 0)
- `apt` — logs call, returns `MOCK_APT_EXIT` (default 0)
- `add-apt-repository` — logs call, returns `MOCK_ADD_APT_REPO_EXIT` (default 0)
- `dnf` — logs call, returns `MOCK_DNF_EXIT` (default 0)
- `installer` — logs call, returns `MOCK_INSTALLER_EXIT` (default 0)
- `unzip` — logs call, returns `MOCK_UNZIP_EXIT` (default 0)
- `git` — logs call, creates target dir on `clone`, returns `MOCK_GIT_EXIT` (default 0)
- `mas` — logs call, returns `MOCK_MAS_EXIT` (default 0)
- `snap` — logs call, returns `MOCK_SNAP_EXIT` (default 0)
- `nala` — logs call, returns `MOCK_NALA_EXIT` (default 0)

**Modified files:**
- `setup_env.sh` — fix `install_git` bug (line 271: `!=` → `==`), remove absolute paths in `install_rosetta` (lines 77/87/94/97), add 7 extracted functions, replace inline blocks with function calls
- `tests/setup_env/install_guards.bats` — add 9 quick-win tests
- `tests/helpers/common.bash` — no changes needed
- `CLAUDE.md` — extend mock env var table

**New files:**
- `tests/setup_env/install_functions.bats` — 14 tests for install_git/zsh/rosetta/nala
- `tests/setup_env/extracted_functions.bats` — 18 tests for 7 extracted functions

---

### Task 1: Add mock executables

**Files:**
- Create: `tests/mocks/id`
- Create: `tests/mocks/yum`
- Create: `tests/mocks/awk`
- Create: `tests/mocks/sw_vers`
- Create: `tests/mocks/sysctl`
- Create: `tests/mocks/pgrep`
- Create: `tests/mocks/softwareupdate`
- Create: `tests/mocks/wget`
- Create: `tests/mocks/dpkg`
- Create: `tests/mocks/chsh`
- Create: `tests/mocks/apt`
- Create: `tests/mocks/add-apt-repository`
- Create: `tests/mocks/dnf`
- Create: `tests/mocks/installer`
- Create: `tests/mocks/unzip`
- Create: `tests/mocks/git`
- Create: `tests/mocks/mas`
- Create: `tests/mocks/snap`
- Create: `tests/mocks/nala`

- [ ] **Step 1: Create id mock**

```bash
#!/usr/bin/env bash
printf "id %s\n" "$*" >> "${MOCK_CALLS_FILE:-/tmp/mock_calls}"
if [[ "$1" == "-u" ]]; then
  printf "%s\n" "${MOCK_ID_U:-1000}"
  exit 0
fi
exec /usr/bin/id "$@"
```

Save to `tests/mocks/id` and `chmod +x tests/mocks/id`.

- [ ] **Step 2: Create yum mock**

```bash
#!/usr/bin/env bash
printf "yum %s\n" "$*" >> "${MOCK_CALLS_FILE:-/tmp/mock_calls}"
if [[ "$1" == "list" ]] && [[ "$2" == "installed" ]]; then
  exit "${MOCK_YUM_LIST_EXIT:-0}"
fi
exit "${MOCK_YUM_EXIT:-0}"
```

Save to `tests/mocks/yum` and `chmod +x`.

- [ ] **Step 3: Create awk mock**

```bash
#!/usr/bin/env bash
printf "awk %s\n" "$*" >> "${MOCK_CALLS_FILE:-/tmp/mock_calls}"
for arg in "$@"; do
  if [[ "$arg" == *"os-release"* ]] && [[ -n "${MOCK_AWK_OS_NAME:-}" ]]; then
    printf "%s\n" "${MOCK_AWK_OS_NAME}"
    exit 0
  fi
done
exec /usr/bin/awk "$@"
```

Save to `tests/mocks/awk` and `chmod +x`.

- [ ] **Step 4: Create sw_vers, sysctl, pgrep, softwareupdate mocks**

```bash
# tests/mocks/sw_vers
#!/usr/bin/env bash
printf "sw_vers %s\n" "$*" >> "${MOCK_CALLS_FILE:-/tmp/mock_calls}"
if [[ "$1" == "-productVersion" ]]; then
  printf "%s\n" "${MOCK_SW_VERS_PRODUCTVERSION:-12.0.0}"
  exit 0
fi
exec /usr/bin/sw_vers "$@"
```

```bash
# tests/mocks/sysctl
#!/usr/bin/env bash
printf "sysctl %s\n" "$*" >> "${MOCK_CALLS_FILE:-/tmp/mock_calls}"
if [[ "$1" == "-n" ]] && [[ "$2" == "machdep.cpu.brand_string" ]]; then
  printf "%s\n" "${MOCK_SYSCTL_CPU:-Apple M1}"
  exit 0
fi
exec sysctl "$@"
```

```bash
# tests/mocks/pgrep
#!/usr/bin/env bash
printf "pgrep %s\n" "$*" >> "${MOCK_CALLS_FILE:-/tmp/mock_calls}"
exit "${MOCK_PGREP_EXIT:-1}"
```

```bash
# tests/mocks/softwareupdate
#!/usr/bin/env bash
printf "softwareupdate %s\n" "$*" >> "${MOCK_CALLS_FILE:-/tmp/mock_calls}"
exit "${MOCK_SOFTWAREUPDATE_EXIT:-0}"
```

`chmod +x` all four.

- [ ] **Step 5: Create wget, dpkg, chsh mocks**

```bash
# tests/mocks/wget
#!/usr/bin/env bash
printf "wget %s\n" "$*" >> "${MOCK_CALLS_FILE:-/tmp/mock_calls}"
i=1
while [[ $i -le $# ]]; do
  if [[ "${!i}" == "-O" ]]; then
    j=$((i+1))
    mkdir -p "$(dirname "${!j}")" 2>/dev/null
    touch "${!j}" 2>/dev/null || true
    break
  fi
  ((i++))
done
exit "${MOCK_WGET_EXIT:-0}"
```

```bash
# tests/mocks/dpkg
#!/usr/bin/env bash
printf "dpkg %s\n" "$*" >> "${MOCK_CALLS_FILE:-/tmp/mock_calls}"
exit "${MOCK_DPKG_EXIT:-0}"
```

```bash
# tests/mocks/chsh
#!/usr/bin/env bash
printf "chsh %s\n" "$*" >> "${MOCK_CALLS_FILE:-/tmp/mock_calls}"
exit "${MOCK_CHSH_EXIT:-0}"
```

`chmod +x` all three.

- [ ] **Step 6: Create apt, add-apt-repository, dnf mocks**

```bash
# tests/mocks/apt
#!/usr/bin/env bash
printf "apt %s\n" "$*" >> "${MOCK_CALLS_FILE:-/tmp/mock_calls}"
exit "${MOCK_APT_EXIT:-0}"
```

```bash
# tests/mocks/add-apt-repository
#!/usr/bin/env bash
printf "add-apt-repository %s\n" "$*" >> "${MOCK_CALLS_FILE:-/tmp/mock_calls}"
exit "${MOCK_ADD_APT_REPO_EXIT:-0}"
```

```bash
# tests/mocks/dnf
#!/usr/bin/env bash
printf "dnf %s\n" "$*" >> "${MOCK_CALLS_FILE:-/tmp/mock_calls}"
exit "${MOCK_DNF_EXIT:-0}"
```

`chmod +x` all three.

- [ ] **Step 7: Create installer, unzip, git, mas, snap, nala mocks**

```bash
# tests/mocks/installer
#!/usr/bin/env bash
printf "installer %s\n" "$*" >> "${MOCK_CALLS_FILE:-/tmp/mock_calls}"
exit "${MOCK_INSTALLER_EXIT:-0}"
```

```bash
# tests/mocks/unzip
#!/usr/bin/env bash
printf "unzip %s\n" "$*" >> "${MOCK_CALLS_FILE:-/tmp/mock_calls}"
exit "${MOCK_UNZIP_EXIT:-0}"
```

```bash
# tests/mocks/git
#!/usr/bin/env bash
printf "git %s\n" "$*" >> "${MOCK_CALLS_FILE:-/tmp/mock_calls}"
if [[ "$1" == "clone" ]]; then
  mkdir -p "${@: -1}"
  exit "${MOCK_GIT_CLONE_EXIT:-0}"
fi
exit "${MOCK_GIT_EXIT:-0}"
```

```bash
# tests/mocks/mas
#!/usr/bin/env bash
printf "mas %s\n" "$*" >> "${MOCK_CALLS_FILE:-/tmp/mock_calls}"
exit "${MOCK_MAS_EXIT:-0}"
```

```bash
# tests/mocks/snap
#!/usr/bin/env bash
printf "snap %s\n" "$*" >> "${MOCK_CALLS_FILE:-/tmp/mock_calls}"
exit "${MOCK_SNAP_EXIT:-0}"
```

```bash
# tests/mocks/nala
#!/usr/bin/env bash
printf "nala %s\n" "$*" >> "${MOCK_CALLS_FILE:-/tmp/mock_calls}"
exit "${MOCK_NALA_EXIT:-0}"
```

`chmod +x` all six.

- [ ] **Step 8: Run existing tests to verify mocks don't break anything**

```bash
make test
```

Expected: all 41 tests pass (new mocks shadow nothing that existing tests rely on, since mocks only intercept when MOCK_* vars are set).

- [ ] **Step 9: Commit**

```bash
git add tests/mocks/
git commit -m "test: add mock executables for id, yum, awk, sw_vers, sysctl, pgrep, softwareupdate, wget, dpkg, chsh, apt, add-apt-repository, dnf, installer, unzip, git, mas, snap, nala"
```

---

### Task 2: Quick-win tests — ensure_not_root, brew_tap_installed, brew_install_cask, rhel_installed_package

**Files:**
- Modify: `tests/setup_env/install_guards.bats`

These four functions already work correctly; the tests just need to be written.

- [ ] **Step 1: Write tests — append to `tests/setup_env/install_guards.bats`**

```bash
# ── ensure_not_root ──────────────────────────────────────────────────────────

@test "ensure_not_root returns 0 when not root" {
  export MOCK_ID_U=1000
  run ensure_not_root
  [ "$status" -eq 0 ]
}

@test "ensure_not_root returns 1 and prints message when root" {
  export MOCK_ID_U=0
  run ensure_not_root
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot run as root"* ]]
}

# ── brew_tap_installed ───────────────────────────────────────────────────────

@test "brew_tap_installed returns 0 when tap is listed" {
  export MOCK_ID_U=1000
  export MOCK_BREW_TAPS="hashicorp/tap homebrew/cask-versions"
  run brew_tap_installed hashicorp/tap
  [ "$status" -eq 0 ]
}

@test "brew_tap_installed returns 1 when tap is not listed" {
  export MOCK_ID_U=1000
  export MOCK_BREW_TAPS=""
  run brew_tap_installed hashicorp/tap
  [ "$status" -eq 1 ]
}

# ── brew_install_cask ────────────────────────────────────────────────────────

@test "brew_install_cask calls brew install --cask when cask is absent" {
  export MOCK_ID_U=1000
  export MOCK_BREW_LIST_CASK=""
  run brew_install_cask docker
  [ "$status" -eq 0 ]
  grep -q "brew install --cask --force --overwrite docker" "${MOCK_CALLS_FILE}"
}

@test "brew_install_cask does not call brew install when cask is present" {
  export MOCK_ID_U=1000
  export MOCK_BREW_LIST_CASK="docker"
  run brew_install_cask docker
  [ "$status" -eq 0 ]
  ! grep -q "brew install --cask" "${MOCK_CALLS_FILE}"
}

# ── rhel_installed_package ───────────────────────────────────────────────────

@test "rhel_installed_package returns 1 when yum is not available" {
  # Source without mocks in PATH so command -v yum fails on macOS
  run bash -c "
    source '${REPO_ROOT}/setup_env.sh'
    rhel_installed_package zsh
  "
  [ "$status" -eq 1 ]
  [[ "$output" == *"yum command not found"* ]]
}

@test "rhel_installed_package returns 0 when yum reports package installed" {
  export MOCK_YUM_LIST_EXIT=0
  run rhel_installed_package zsh
  [ "$status" -eq 0 ]
}

@test "rhel_installed_package returns 1 when yum reports package not installed" {
  export MOCK_YUM_LIST_EXIT=1
  run rhel_installed_package zsh
  [ "$status" -eq 1 ]
}
```

- [ ] **Step 2: Run new tests to verify they pass**

```bash
bats tests/setup_env/install_guards.bats
```

Expected: all tests pass (13 existing + 9 new = 22 tests).

- [ ] **Step 3: Commit**

```bash
git add tests/setup_env/install_guards.bats
git commit -m "test: add quick-win tests for ensure_not_root, brew_tap_installed, brew_install_cask, rhel_installed_package"
```

---

### Task 3: Fix install_git bug and add tests for install_git and install_zsh

**Files:**
- Modify: `setup_env.sh` (line 271)
- Create: `tests/setup_env/install_functions.bats`

`install_git` has `!= "Darwin"` on line 271 (should be `==`), making the Linux branch (`elif Linux`) unreachable. Fix the condition first, then write tests for both macOS and Linux paths. `install_zsh` is correctly structured (no bug).

- [ ] **Step 1: Write failing tests for install_git (correct behavior)**

Create `tests/setup_env/install_functions.bats`:

```bash
#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_setup_env
  load_mocks
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  export MOCK_ID_U=1000
}

teardown() {
  rm -f "${MOCK_CALLS_FILE:-}"
}

# ── install_git ──────────────────────────────────────────────────────────────

@test "install_git on macOS skips when git is already in brew list" {
  export MOCK_UNAME_S=Darwin
  export MACOS=1
  export MOCK_BREW_LIST_FORMULA="git"
  run install_git
  [ "$status" -eq 0 ]
  [[ "$output" == *"already installed"* ]]
  ! grep -q "brew install" "${MOCK_CALLS_FILE}"
}

@test "install_git on macOS calls brew install when git is absent" {
  export MOCK_UNAME_S=Darwin
  export MACOS=1
  export MOCK_BREW_LIST_FORMULA=""
  run install_git
  [ "$status" -eq 0 ]
  grep -q "brew install git" "${MOCK_CALLS_FILE}"
}

@test "install_git on Ubuntu calls apt install" {
  export MOCK_UNAME_S=Linux
  export MOCK_AWK_OS_NAME="Ubuntu"
  run install_git
  [ "$status" -eq 0 ]
  grep -q "apt install git" "${MOCK_CALLS_FILE}"
}

@test "install_git on CentOS calls yum install" {
  export MOCK_UNAME_S=Linux
  export MOCK_AWK_OS_NAME="CentOS Linux"
  run install_git
  [ "$status" -eq 0 ]
  grep -q "yum install git" "${MOCK_CALLS_FILE}"
}

@test "install_git on Fedora calls dnf install" {
  export MOCK_UNAME_S=Linux
  export MOCK_AWK_OS_NAME="Fedora"
  run install_git
  [ "$status" -eq 0 ]
  grep -q "dnf install git" "${MOCK_CALLS_FILE}"
}
```

- [ ] **Step 2: Run to verify the Ubuntu/CentOS/Fedora tests fail (bug present)**

```bash
bats tests/setup_env/install_functions.bats
```

Expected: macOS tests pass, Linux tests fail (Linux path unreachable due to `!= "Darwin"` bug).

- [ ] **Step 3: Fix install_git bug in setup_env.sh**

Line 271 — change:
```bash
  if [[ "$(uname -s)" != "Darwin" ]]; then
```
to:
```bash
  if [[ "$(uname -s)" == "Darwin" ]]; then
```

- [ ] **Step 4: Run tests to verify all install_git tests pass**

```bash
bats tests/setup_env/install_functions.bats
```

Expected: 5 tests pass.

- [ ] **Step 5: Write install_zsh tests — append to `tests/setup_env/install_functions.bats`**

```bash
# ── install_zsh ──────────────────────────────────────────────────────────────

@test "install_zsh on macOS skips when zsh is already in brew list" {
  export MOCK_UNAME_S=Darwin
  export MACOS=1
  export MOCK_BREW_LIST_FORMULA="zsh"
  run install_zsh
  [ "$status" -eq 0 ]
  [[ "$output" == *"already installed"* ]]
  ! grep -q "brew install" "${MOCK_CALLS_FILE}"
}

@test "install_zsh on macOS calls brew install when zsh is absent" {
  export MOCK_UNAME_S=Darwin
  export MACOS=1
  export MOCK_BREW_LIST_FORMULA=""
  run install_zsh
  [ "$status" -eq 0 ]
  grep -q "brew install zsh" "${MOCK_CALLS_FILE}"
}

@test "install_zsh on Ubuntu calls apt install" {
  export MOCK_UNAME_S=Linux
  export MOCK_AWK_OS_NAME="Ubuntu"
  run install_zsh
  [ "$status" -eq 0 ]
  grep -q "apt install zsh" "${MOCK_CALLS_FILE}"
}

@test "install_zsh on CentOS calls yum install" {
  export MOCK_UNAME_S=Linux
  export MOCK_AWK_OS_NAME="CentOS Linux"
  run install_zsh
  [ "$status" -eq 0 ]
  grep -q "yum install zsh" "${MOCK_CALLS_FILE}"
}

@test "install_zsh on Fedora calls dnf install" {
  export MOCK_UNAME_S=Linux
  export MOCK_AWK_OS_NAME="Fedora"
  run install_zsh
  [ "$status" -eq 0 ]
  grep -q "dnf install zsh" "${MOCK_CALLS_FILE}"
}
```

- [ ] **Step 6: Run all tests to verify**

```bash
bats tests/setup_env/install_functions.bats
```

Expected: 10 tests pass.

- [ ] **Step 7: Run full test suite**

```bash
make test
```

Expected: 51 total tests pass (41 existing + 10 new).

- [ ] **Step 8: Commit**

```bash
git add setup_env.sh tests/setup_env/install_functions.bats
git commit -m "fix: correct install_git uname condition (was != Darwin, should be ==)

The != operator caused the Linux install paths (apt/yum/dnf) to be
unreachable since elif Linux was only evaluated when uname == Darwin,
which is impossible.

test: add install_git and install_zsh tests for macOS and Linux paths"
```

---

### Task 4: Tests for install_rosetta and check_and_install_nala

**Files:**
- Modify: `setup_env.sh` (lines 77, 87, 94, 97 — remove absolute paths)
- Modify: `tests/setup_env/install_functions.bats`

`install_rosetta` uses absolute paths (`/usr/bin/sw_vers`, `/usr/sbin/sysctl`, `/usr/bin/pgrep`, `/usr/sbin/softwareupdate`) which bypass PATH-based mocks. Remove the absolute paths to enable testing.

- [ ] **Step 1: Remove absolute paths from install_rosetta**

In `setup_env.sh`, make these four changes:

Line 77: change `"$(/usr/bin/sw_vers -productVersion)"` → `"$(sw_vers -productVersion)"`

Line 87: change `processor=$(/usr/sbin/sysctl -n machdep.cpu.brand_string)` → `processor=$(sysctl -n machdep.cpu.brand_string)`

Line 94: change `if /usr/bin/pgrep oahd >/dev/null 2>&1; then` → `if pgrep oahd >/dev/null 2>&1; then`

Line 97: change `/usr/sbin/softwareupdate --install-rosetta --agree-to-license` → `softwareupdate --install-rosetta --agree-to-license`

- [ ] **Step 2: Write install_rosetta tests — append to `tests/setup_env/install_functions.bats`**

```bash
# ── install_rosetta ──────────────────────────────────────────────────────────

@test "install_rosetta does nothing on macOS older than 11" {
  export MOCK_SW_VERS_PRODUCTVERSION="10.15.7"
  run install_rosetta
  [ "$status" -eq 0 ]
  [[ "$output" == *"No need to install Rosetta"* ]]
  ! grep -q "softwareupdate" "${MOCK_CALLS_FILE}"
}

@test "install_rosetta skips when processor is Intel" {
  export MOCK_SW_VERS_PRODUCTVERSION="12.0.0"
  export MOCK_SYSCTL_CPU="Intel(R) Core(TM) i9-9880H CPU @ 2.30GHz"
  run install_rosetta
  [ "$status" -eq 0 ]
  [[ "$output" == *"No need to install Rosetta"* ]]
  ! grep -q "softwareupdate" "${MOCK_CALLS_FILE}"
}

@test "install_rosetta skips when oahd process is already running" {
  export MOCK_SW_VERS_PRODUCTVERSION="12.0.0"
  export MOCK_SYSCTL_CPU="Apple M1"
  export MOCK_PGREP_EXIT=0
  run install_rosetta
  [ "$status" -eq 0 ]
  [[ "$output" == *"already installed"* ]]
  ! grep -q "softwareupdate --install-rosetta" "${MOCK_CALLS_FILE}"
}

@test "install_rosetta installs Rosetta on Apple Silicon when oahd is absent" {
  export MOCK_SW_VERS_PRODUCTVERSION="12.0.0"
  export MOCK_SYSCTL_CPU="Apple M1"
  export MOCK_PGREP_EXIT=1
  export MOCK_SOFTWAREUPDATE_EXIT=0
  run install_rosetta
  [ "$status" -eq 0 ]
  grep -q "softwareupdate --install-rosetta" "${MOCK_CALLS_FILE}"
  [[ "$output" == *"successfully installed"* ]]
}

@test "install_rosetta returns 1 when softwareupdate fails" {
  export MOCK_SW_VERS_PRODUCTVERSION="12.0.0"
  export MOCK_SYSCTL_CPU="Apple M1"
  export MOCK_PGREP_EXIT=1
  export MOCK_SOFTWAREUPDATE_EXIT=1
  run install_rosetta
  [ "$status" -eq 1 ]
  [[ "$output" == *"installation failed"* ]]
}
```

- [ ] **Step 3: Write check_and_install_nala tests — append to `tests/setup_env/install_functions.bats`**

```bash
# ── check_and_install_nala ───────────────────────────────────────────────────

@test "check_and_install_nala does nothing on non-Linux" {
  export MOCK_UNAME_S=Darwin
  run check_and_install_nala
  [ "$status" -eq 0 ]
  ! grep -q "dpkg" "${MOCK_CALLS_FILE}"
}

@test "check_and_install_nala does nothing on non-Ubuntu Linux" {
  export MOCK_UNAME_S=Linux
  export MOCK_AWK_OS_NAME="Fedora"
  run check_and_install_nala
  [ "$status" -eq 0 ]
  ! grep -q "dpkg" "${MOCK_CALLS_FILE}"
}

@test "check_and_install_nala installs nala via dpkg and apt on Ubuntu when absent" {
  export MOCK_UNAME_S=Linux
  export MOCK_AWK_OS_NAME="Ubuntu"
  export HOME="${BATS_TEST_TMPDIR}"
  mkdir -p "${BATS_TEST_TMPDIR}/software_downloads"
  # nala is not in PATH, so command -v nala fails → install branch taken
  run check_and_install_nala
  [ "$status" -eq 0 ]
  grep -q "dpkg --install" "${MOCK_CALLS_FILE}"
  grep -q "apt install nala" "${MOCK_CALLS_FILE}"
}
```

- [ ] **Step 4: Run all tests**

```bash
bats tests/setup_env/install_functions.bats
```

Expected: 18 tests pass (10 from Task 3 + 5 rosetta + 3 nala).

- [ ] **Step 5: Run full suite**

```bash
make test
```

Expected: 59 tests pass.

- [ ] **Step 6: Commit**

```bash
git add setup_env.sh tests/setup_env/install_functions.bats
git commit -m "test: add install_rosetta and check_and_install_nala tests

Remove absolute paths from install_rosetta (sw_vers, sysctl, pgrep,
softwareupdate) so PATH-based mocks can intercept them. Add 8 tests
covering all install_rosetta decision paths and 3 nala platform cases."
```

---

### Task 5: Extract clone_or_update_dotfiles() and setup_dotfile_symlinks()

**Files:**
- Modify: `setup_env.sh` (extract from SETUP block, add functions before sourcing guard)
- Create: `tests/setup_env/extracted_functions.bats`

`clone_or_update_dotfiles()` wraps the git clone/pull block (lines 598–607).
`setup_dotfile_symlinks()` wraps the large symlink creation block (lines 609–817).

- [ ] **Step 1: Write failing tests for clone_or_update_dotfiles**

Create `tests/setup_env/extracted_functions.bats`:

```bash
#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_setup_env
  load_mocks
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"

  # Fake filesystem layout for extracted function tests
  FAKE_HOME="${BATS_TEST_TMPDIR}/home"
  FAKE_PERSONAL_GITREPOS="${BATS_TEST_TMPDIR}/home/git-repos/personal"
  FAKE_DOTFILES_SRC="${FAKE_PERSONAL_GITREPOS}/dotfiles"

  mkdir -p "${FAKE_HOME}"
  export HOME="${FAKE_HOME}"
  export PERSONAL_GITREPOS="${FAKE_PERSONAL_GITREPOS}"
  export DOTFILES="dotfiles"
}

teardown() {
  rm -f "${MOCK_CALLS_FILE:-}"
}

# ── clone_or_update_dotfiles ─────────────────────────────────────────────────

@test "clone_or_update_dotfiles clones when dotfiles directory does not exist" {
  run clone_or_update_dotfiles
  [ "$status" -eq 0 ]
  grep -q "git clone" "${MOCK_CALLS_FILE}"
  [[ -d "${FAKE_PERSONAL_GITREPOS}/dotfiles" ]]
}

@test "clone_or_update_dotfiles runs git pull when dotfiles directory exists" {
  mkdir -p "${FAKE_DOTFILES_SRC}"
  run clone_or_update_dotfiles
  [ "$status" -eq 0 ]
  grep -q "git pull" "${MOCK_CALLS_FILE}"
  ! grep -q "git clone" "${MOCK_CALLS_FILE}"
}
```

- [ ] **Step 2: Run to verify tests fail**

```bash
bats tests/setup_env/extracted_functions.bats
```

Expected: FAIL — `clone_or_update_dotfiles: command not found`.

- [ ] **Step 3: Extract clone_or_update_dotfiles() into setup_env.sh**

Add this function before the sourcing guard line (`[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0`):

```bash
clone_or_update_dotfiles() {
  printf "Copying %s from Github\\n" "${DOTFILES}"
  if [[ ! -d ${PERSONAL_GITREPOS}/${DOTFILES} ]]; then
    cd ${HOME} || return
    git clone --recursive git@github.com:brujack/${DOTFILES}.git ${PERSONAL_GITREPOS}/${DOTFILES}
  else
    cd ${PERSONAL_GITREPOS}/${DOTFILES} || exit
    git pull
  fi
}
```

Replace the inline block in the SETUP section (the `printf "Copying %s from Github"` block through the `fi`) with:

```bash
  clone_or_update_dotfiles
```

- [ ] **Step 4: Write failing tests for setup_dotfile_symlinks**

Append to `tests/setup_env/extracted_functions.bats`:

```bash
# ── setup_dotfile_symlinks ───────────────────────────────────────────────────

_make_fake_dotfiles() {
  # Create all source files that setup_dotfile_symlinks will symlink
  mkdir -p "${FAKE_DOTFILES_SRC}/.devcontainer/.config/.zshrc.d"
  mkdir -p "${FAKE_DOTFILES_SRC}/.config/ccstatusline"
  mkdir -p "${FAKE_DOTFILES_SRC}/.ssh"
  mkdir -p "${FAKE_DOTFILES_SRC}/.claude"
  mkdir -p "${FAKE_DOTFILES_SRC}/.warp/themes"
  mkdir -p "${FAKE_DOTFILES_SRC}/.warp/launch_configurations"
  touch "${FAKE_DOTFILES_SRC}/.gitconfig_mac"
  touch "${FAKE_DOTFILES_SRC}/.gitconfig_linux"
  touch "${FAKE_DOTFILES_SRC}/.gitconfig_mac_gitlab"
  touch "${FAKE_DOTFILES_SRC}/.gitconfig_linux_gitlab"
  touch "${FAKE_DOTFILES_SRC}/.vimrc"
  touch "${FAKE_DOTFILES_SRC}/.p10k.zsh"
  touch "${FAKE_DOTFILES_SRC}/.tmux.conf"
  touch "${FAKE_DOTFILES_SRC}/scripts"
  touch "${FAKE_DOTFILES_SRC}/bruce.zsh-theme"
  touch "${FAKE_DOTFILES_SRC}/profile.ps1"
  touch "${FAKE_DOTFILES_SRC}/bruce.omp.json"
  touch "${FAKE_DOTFILES_SRC}/starship.toml"
  touch "${FAKE_DOTFILES_SRC}/.zshrc"
  touch "${FAKE_DOTFILES_SRC}/.zprofile"
  touch "${FAKE_DOTFILES_SRC}/.ssh/config"
  touch "${FAKE_DOTFILES_SRC}/.ssh/teleport.cfg"
}

@test "setup_dotfile_symlinks links .gitconfig_mac on macOS" {
  _make_fake_dotfiles
  export MACOS=1
  unset LINUX
  run setup_dotfile_symlinks
  [ "$status" -eq 0 ]
  [[ -L "${FAKE_HOME}/.gitconfig" ]]
  [[ "$(readlink "${FAKE_HOME}/.gitconfig")" == "${FAKE_DOTFILES_SRC}/.gitconfig_mac" ]]
}

@test "setup_dotfile_symlinks links .gitconfig_linux on Linux" {
  _make_fake_dotfiles
  export LINUX=1
  unset MACOS
  run setup_dotfile_symlinks
  [ "$status" -eq 0 ]
  [[ -L "${FAKE_HOME}/.gitconfig" ]]
  [[ "$(readlink "${FAKE_HOME}/.gitconfig")" == "${FAKE_DOTFILES_SRC}/.gitconfig_linux" ]]
}

@test "setup_dotfile_symlinks links .vimrc" {
  _make_fake_dotfiles
  export MACOS=1
  unset LINUX
  run setup_dotfile_symlinks
  [ "$status" -eq 0 ]
  [[ -L "${FAKE_HOME}/.vimrc" ]]
}

@test "setup_dotfile_symlinks links .zshrc" {
  _make_fake_dotfiles
  export MACOS=1
  unset LINUX
  run setup_dotfile_symlinks
  [ "$status" -eq 0 ]
  [[ -L "${FAKE_HOME}/.zshrc" ]]
}
```

- [ ] **Step 5: Run to verify setup_dotfile_symlinks tests fail**

```bash
bats tests/setup_env/extracted_functions.bats
```

Expected: FAIL — `setup_dotfile_symlinks: command not found`.

- [ ] **Step 6: Extract setup_dotfile_symlinks() into setup_env.sh**

Add this function before the sourcing guard (after `clone_or_update_dotfiles`). The body is the entire `printf "Linking %s to their home"` block through the end of the `.tsh` directory creation (~lines 609–840 in the SETUP block). Copy it verbatim:

```bash
setup_dotfile_symlinks() {
  printf "Linking %s to their home\\n" "${DOTFILES}"

  if [[ -n ${MACOS} ]]; then
    rm -f ${HOME}/.gitconfig
    ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.gitconfig_mac ${HOME}/.gitconfig
    if [[ -d ${HOME}/git-repos/gitlab ]]; then
      rm -f ${HOME}/git-repos/gitlab/.gitconfig
      ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.gitconfig_mac_gitlab ${HOME}/git-repos/gitlab/.gitconfig
    fi
    if [[ -L ${HOME}/git-repos/gitlab/.gitconfig ]]; then
      printf "gitlab/.gitconfig is linked\\n"
    fi
  fi
  if [[ -n ${LINUX} ]]; then
    rm -f ${HOME}/.gitconfig
    ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.gitconfig_linux ${HOME}/.gitconfig
    if [[ -n ${WORKSTATION} ]] || [[ -n ${CRUNCHER} ]]; then
      if [[ -d ${HOME}/git-repos/gitlab ]]; then
        rm -f ${HOME}/git-repos/gitlab/.gitconfig
        ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.gitconfig_linux_gitlab ${HOME}/git-repos/gitlab/.gitconfig
      fi
      if [[ -L ${HOME}/git-repos/gitlab/.gitconfig ]]; then
        printf "gitlab/.gitconfig is linked Linux\\n"
      fi
    fi
  fi

  rm -f ${HOME}/.vimrc
  ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.vimrc ${HOME}/.vimrc
  if [[ -L ${HOME}/.vimrc ]]; then
    printf ".vimrc is linked\\n"
  fi

  rm -f ${HOME}/.p10k.zsh
  ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.p10k.zsh ${HOME}/.p10k.zsh
  if [[ -L ${HOME}/.p10k.zsh ]]; then
    printf ".p10k.zsh is linked\\n"
  fi

  rm -f ${HOME}/.tmux.conf
  ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.tmux.conf ${HOME}/.tmux.conf
  if [[ -L ${HOME}/.tmux.conf ]]; then
    printf ".tmux.conf is linked\\n"
  fi

  if [[ -d ${HOME}/scripts ]]; then
    rm -rf ${HOME}/scripts
    ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/scripts ${HOME}/scripts
  elif [[ ! -L ${HOME}/scripts ]]; then
    ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/scripts ${HOME}/scripts
  fi
  if [[ -L ${HOME}/scripts ]]; then
    printf "scripts is linked\\n"
  fi

  if [[ -n ${MACOS} ]] || [[ -n ${LINUX} ]]; then
    printf "Creating %s/.config\\n" "${HOME}"
    mkdir -p ${HOME}/.config
  fi

  if [[ -n ${MACOS} ]] || [[ -n ${LINUX} ]]; then
    printf "Creating %s/.tf_creds\\n" "${HOME}"
    mkdir -p ${HOME}/.tf_creds
    if [[ -d ${HOME}/.tf_creds ]]; then
      chmod 700 ${HOME}/.tf_creds
    fi
    if [[ -d ${HOME}/.tf_creds ]]; then
      printf "Created %s/.tf_creds\\n" "${HOME}"
    fi
  fi

  if [[ -n ${MACOS} ]] || [[ -n ${LINUX} ]]; then
    printf "powershell profile and custom oh-my-posh theme\\n"
    mkdir -p ${HOME}/.config/powershell
    rm -f ${HOME}/.config/powershell/profile.ps1
    ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/profile.ps1 ${HOME}/.config/powershell/profile.ps1
    rm -f ${HOME}/.config/powershell/bruce.omp.json
    ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/bruce.omp.json ${HOME}/.config/powershell/bruce.omp.json
    if [[ -L ${HOME}/.config/powershell/profile.ps1 ]]; then
      printf "powershell profile is linked\\n"
    fi
    if [[ -L ${HOME}/.config/powershell/bruce.omp.json ]]; then
      printf "bruce.omp.json is linked\\n"
    fi
  fi

  if [[ -n ${MACOS} ]] || [[ -n ${LINUX} ]]; then
    printf "starship profile\\n"
    rm -f ${HOME}/.config/starship.toml
    ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/starship.toml ${HOME}/.config/starship.toml
    if [[ -L ${HOME}/.config/starship.toml ]]; then
      printf "starship.toml is linked\\n"
    fi
  fi

  printf "Installing Oh My ZSH...\\n"
  if [[ ! -d ${HOME}/.oh-my-zsh ]]; then
    bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    if [[ -d ${HOME}/.oh-my-zsh ]]; then
      printf "Installed Oh My ZSH\\n"
    fi
  fi

  printf "Installing p10k\\n"
  if [[ ! -d ${HOME}/.oh-my-zsh/custom/themes/powerlevel10k ]]; then
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${HOME}/.oh-my-zsh/custom/themes/powerlevel10k
    if [[ -d ${HOME}/.oh-my-zsh/custom/themes/powerlevel10k ]]; then
      printf "Installed p10k\\n"
    fi
  fi

  printf "linking .zshrc\\n"
  rm -f ${HOME}/.zshrc
  ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.zshrc ${HOME}/.zshrc
  if [[ -L ${HOME}/.zshrc ]]; then
    printf ".zshrc is linked\\n"
  fi

  printf "linking .zshrc.d\\n"
  rm -f ${HOME}/.config/.zshrc.d
  ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.config/.zshrc.d ${HOME}/.config/.zshrc.d
  if [[ -L ${HOME}/.config/.zshrc.d ]]; then
    printf ".zshrc.d is linked\\n"
  fi

  printf "Linking %s/.config/ccstatusline\\n" "${HOME}"
  mkdir -p ${HOME}/.config
  rm -rf ${HOME}/.config/ccstatusline
  ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.config/ccstatusline ${HOME}/.config/ccstatusline
  if [[ -L ${HOME}/.config/ccstatusline ]]; then
    printf ".config/ccstatusline is linked\\n"
  fi

  printf "linking .zprofile\\n"
  rm -f ${HOME}/.zprofile
  ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.zprofile ${HOME}/.zprofile
  if [[ -L ${HOME}/.zprofile ]]; then
    printf ".zprofile is linked\\n"
  fi

  printf "Linking custom bruce.zsh-theme\\n"
  rm -f ${HOME}/.oh-my-zsh/custom/themes/bruce.zsh-theme
  ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/bruce.zsh-theme ${HOME}/.oh-my-zsh/custom/themes/bruce.zsh-theme
  if [[ -L ${HOME}/.oh-my-zsh/custom/themes/bruce.zsh-theme ]]; then
    printf "bruce.zsh-theme is linked\\n"
  fi

  printf "Creating %s/.tmux\\n" "${HOME}"
  mkdir -p ${HOME}/.tmux
  if [[ -d ${HOME}/.tmux ]]; then
    printf "Created %s/.tmux\\n" "${HOME}"
  fi

  if [[ ! -d ${HOME}/.tmux/plugins/tpm ]]; then
    printf "Installing TPM\\n"
    git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
    if [[ -d ${HOME}/.tmux/plugins/tpm ]]; then
      printf "Installed TPM\\n"
    fi
  fi

  printf "Creating %s/.warp\\n" "${HOME}"
  mkdir -p ${HOME}/.warp
  if [[ -d ${HOME}/.warp ]]; then
    chmod 700 ${HOME}/.warp
    if [[ -d ${HOME}/.warp ]]; then
      printf "Created %s/.warp\\n" "${HOME}"
    fi
  fi
  printf "Linking %s/.warp/themes\\n" "${HOME}"
  rm -f ${HOME}/.warp/themes
  ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.warp/themes ${HOME}/.warp/themes
  if [[ -L ${HOME}/.warp/themes ]]; then
    printf ".warp/themes is linked\\n"
  fi

  printf "Linking %s/.warp/launch_configurations\\n" "${HOME}"
  rm -f ${HOME}/.warp/launch_configurations
  ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.warp/launch_configurations ${HOME}/.warp/launch_configurations
  if [[ -L ${HOME}/.warp/launch_configurations ]]; then
    printf ".warp/launch_configurations is linked\\n"
  fi

  printf "Creating %s/.ssh\\n" "${HOME}"
  mkdir -p ${HOME}/.ssh
  if [[ -d ${HOME}/.ssh ]]; then
    chmod 700 ${HOME}/.ssh
    if [[ -d ${HOME}/.ssh ]]; then
      printf "Created %s/.ssh\\n" "${HOME}"
    fi
  fi

  printf "Creating %s/.claude\\n" "${HOME}"
  mkdir -p ${HOME}/.claude
  if [[ -d ${HOME}/.claude ]]; then
    printf "Created %s/.claude\\n" "${HOME}"
  fi
  for _claude_item in ${PERSONAL_GITREPOS}/${DOTFILES}/.claude/*; do
    _claude_target="${HOME}/.claude/$(basename ${_claude_item})"
    printf "Linking %s\\n" "${_claude_target}"
    rm -rf ${_claude_target}
    ln -s ${_claude_item} ${_claude_target}
    if [[ -L ${_claude_target} ]]; then
      printf "%s is linked\\n" "${_claude_target}"
    fi
  done

  printf "Linking %s/.ssh/config\\n" "${HOME}"
  rm -f ${HOME}/.ssh/config
  ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.ssh/config ${HOME}/.ssh/config
  if [[ -L ${HOME}/.ssh/config ]]; then
    printf ".ssh/config is linked\\n"
  fi

  printf "Linking %s/.ssh/teleport.cfg\\n" "${HOME}"
  rm -f ${HOME}/.ssh/teleport.cfg
  ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.ssh/teleport.cfg ${HOME}/.ssh/teleport.cfg
  if [[ -L ${HOME}/.ssh/teleport.cfg ]]; then
    printf ".ssh/teleport.cfg is linked\\n"
  fi

  printf "Creating %s/.tsh\\n" "${HOME}"
  mkdir -p ${HOME}/.tsh
  if [[ -d ${HOME}/.tsh ]]; then
    chmod 700 ${HOME}/.tsh
    if [[ -d ${HOME}/.tsh ]]; then
      printf "Created %s/.tsh\\n" "${HOME}"
    fi
  fi
}
```

Then replace the `printf "Linking %s to their home"` block through the `.tsh` block in the SETUP section with:

```bash
  setup_dotfile_symlinks
```

- [ ] **Step 7: Run tests to verify all 6 extracted_functions tests pass**

```bash
bats tests/setup_env/extracted_functions.bats
```

Expected: 6 tests pass.

- [ ] **Step 8: Run full suite**

```bash
make test
```

Expected: 65 tests pass.

- [ ] **Step 9: Commit**

```bash
git add setup_env.sh tests/setup_env/extracted_functions.bats
git commit -m "refactor: extract clone_or_update_dotfiles() and setup_dotfile_symlinks()

Extract 2 inline SETUP blocks into named functions for readability and
testability. Add 6 tests verifying git clone/pull dispatch and
platform-specific gitconfig/vimrc/zshrc symlink creation."
```

---

### Task 6: Extract setup_credential_directories() and setup_zsh_as_default_shell()

**Files:**
- Modify: `setup_env.sh`
- Modify: `tests/setup_env/extracted_functions.bats`

`setup_credential_directories()` wraps the aws/gcloud/azure credential directory block (lines 892–912 in the SETUP/DEVELOPER block).
`setup_zsh_as_default_shell()` wraps the `chsh` block (lines 842–855 in SETUP).

- [ ] **Step 1: Write failing tests — append to `tests/setup_env/extracted_functions.bats`**

```bash
# ── setup_credential_directories ────────────────────────────────────────────

@test "setup_credential_directories creates .aws with chmod 700" {
  run setup_credential_directories
  [ "$status" -eq 0 ]
  [[ -d "${FAKE_HOME}/.aws" ]]
  perms=$(stat -f "%OLp" "${FAKE_HOME}/.aws" 2>/dev/null || stat -c "%a" "${FAKE_HOME}/.aws")
  [ "$perms" = "700" ]
}

@test "setup_credential_directories creates .gcloud_creds with chmod 700" {
  run setup_credential_directories
  [ "$status" -eq 0 ]
  [[ -d "${FAKE_HOME}/.gcloud_creds" ]]
  perms=$(stat -f "%OLp" "${FAKE_HOME}/.gcloud_creds" 2>/dev/null || stat -c "%a" "${FAKE_HOME}/.gcloud_creds")
  [ "$perms" = "700" ]
}

@test "setup_credential_directories creates .azure_creds with chmod 700" {
  run setup_credential_directories
  [ "$status" -eq 0 ]
  [[ -d "${FAKE_HOME}/.azure_creds" ]]
  perms=$(stat -f "%OLp" "${FAKE_HOME}/.azure_creds" 2>/dev/null || stat -c "%a" "${FAKE_HOME}/.azure_creds")
  [ "$perms" = "700" ]
}

# ── setup_zsh_as_default_shell ───────────────────────────────────────────────

@test "setup_zsh_as_default_shell does nothing when shell is already zsh" {
  export SHELL="/bin/zsh"
  unset REDHAT
  run setup_zsh_as_default_shell
  [ "$status" -eq 0 ]
  ! grep -q "chsh" "${MOCK_CALLS_FILE}"
}

@test "setup_zsh_as_default_shell calls chsh when shell is not zsh" {
  export SHELL="/bin/bash"
  unset REDHAT
  run setup_zsh_as_default_shell
  [ "$status" -eq 0 ]
  grep -q "chsh -s /bin/zsh" "${MOCK_CALLS_FILE}"
}
```

- [ ] **Step 2: Run to verify tests fail**

```bash
bats tests/setup_env/extracted_functions.bats
```

Expected: FAIL — `setup_credential_directories: command not found` and `setup_zsh_as_default_shell: command not found`.

- [ ] **Step 3: Extract setup_credential_directories() into setup_env.sh**

Add before the sourcing guard:

```bash
setup_credential_directories() {
  printf "Creating %s/.aws\\n" "${HOME}"
  mkdir -p ${HOME}/.aws
  if [[ -d ${HOME}/.aws ]]; then
    chmod 700 ${HOME}/.aws
    printf "Created %s/.aws\\n" "${HOME}"
  fi

  printf "Creating %s/.gcloud_creds\\n" "${HOME}"
  mkdir -p ${HOME}/.gcloud_creds
  if [[ -d ${HOME}/.gcloud_creds ]]; then
    chmod 700 ${HOME}/.gcloud_creds
    printf "Created %s/.gcloud_creds\\n" "${HOME}"
  fi

  printf "Creating %s/.azure_creds\\n" "${HOME}"
  mkdir -p ${HOME}/.azure_creds
  if [[ -d ${HOME}/.azure_creds ]]; then
    chmod 700 ${HOME}/.azure_creds
    printf "Created %s/.azure_creds\\n" "${HOME}"
  fi
}
```

Replace the inline block at the top of the `if [[ -n ${SETUP} ]] || [[ -n ${DEVELOPER} ]]; then` section with:

```bash
  setup_credential_directories
```

- [ ] **Step 4: Extract setup_zsh_as_default_shell() into setup_env.sh**

Add before the sourcing guard:

```bash
setup_zsh_as_default_shell() {
  printf "Setting ZSH as shell...\\n"

  # Set the ZSH path based on the value of REDHAT
  ZSH_PATH=${REDHAT:+"/usr/local/bin/zsh"}
  ZSH_PATH=${ZSH_PATH:-"/bin/zsh"}

  if [[ ${SHELL} != "${ZSH_PATH}" ]]; then
    if which "${ZSH_PATH}" >/dev/null 2>&1; then
      chsh -s "${ZSH_PATH}"
      printf "Changed default shell to %s\\n" "${ZSH_PATH}"
    else
      printf "Error: %s does not exist\\n" "${ZSH_PATH}"
    fi
  fi
}
```

Replace the inline `printf "Setting ZSH as shell"` block (through the closing `fi`) in the SETUP section with:

```bash
  setup_zsh_as_default_shell
```

- [ ] **Step 5: Run tests to verify all pass**

```bash
bats tests/setup_env/extracted_functions.bats
```

Expected: 11 tests pass (6 from Task 5 + 3 credential + 2 zsh shell).

- [ ] **Step 6: Run full suite**

```bash
make test
```

Expected: 70 tests pass.

- [ ] **Step 7: Commit**

```bash
git add setup_env.sh tests/setup_env/extracted_functions.bats
git commit -m "refactor: extract setup_credential_directories() and setup_zsh_as_default_shell()

Extract 2 inline blocks for testability. Add 5 tests: credential dirs
verify chmod 700, shell setup verifies chsh is called only when needed."
```

---

### Task 7: Extract update_system_packages(), update_aws_cli(), and update_rust()

**Files:**
- Modify: `setup_env.sh`
- Modify: `tests/setup_env/extracted_functions.bats`

These three functions extract from the UPDATE block (lines 2352–2450).
`update_system_packages()` covers the OS package update logic.
`update_aws_cli()` covers the AWS CLI download and install.
`update_rust()` covers the rustup self update and update.

- [ ] **Step 1: Write failing tests — append to `tests/setup_env/extracted_functions.bats`**

```bash
# ── update_system_packages ───────────────────────────────────────────────────

@test "update_system_packages calls apt update on Ubuntu" {
  export UBUNTU=1
  export FOCAL=1
  unset MACOS LINUX REDHAT FEDORA CENTOS JAMMY NOBLE
  run update_system_packages
  [ "$status" -eq 0 ]
  grep -q "apt update" "${MOCK_CALLS_FILE}"
}

@test "update_system_packages calls nala full-upgrade on Ubuntu Jammy" {
  export UBUNTU=1
  export JAMMY=1
  unset MACOS LINUX REDHAT FEDORA CENTOS FOCAL NOBLE
  run update_system_packages
  [ "$status" -eq 0 ]
  grep -q "nala full-upgrade" "${MOCK_CALLS_FILE}"
}

@test "update_system_packages calls dnf update on RHEL" {
  export REDHAT=1
  unset MACOS LINUX UBUNTU FEDORA CENTOS
  run update_system_packages
  [ "$status" -eq 0 ]
  grep -q "dnf update" "${MOCK_CALLS_FILE}"
}

@test "update_system_packages calls yum update on CentOS" {
  export CENTOS=1
  unset MACOS LINUX UBUNTU FEDORA REDHAT
  run update_system_packages
  [ "$status" -eq 0 ]
  grep -q "yum update" "${MOCK_CALLS_FILE}"
}

# ── update_aws_cli ───────────────────────────────────────────────────────────

@test "update_aws_cli on macOS calls curl and installer" {
  export MACOS=1
  export LAPTOP=1
  unset LINUX WORKSTATION CRUNCHER
  mkdir -p "${FAKE_HOME}/software_downloads/awscli"
  run update_aws_cli
  [ "$status" -eq 0 ]
  grep -q "curl.*AWSCLIV2.pkg" "${MOCK_CALLS_FILE}"
  grep -q "installer -pkg" "${MOCK_CALLS_FILE}"
}

@test "update_aws_cli on Linux calls curl and install script" {
  export LINUX=1
  export WORKSTATION=1
  unset MACOS LAPTOP STUDIO RECEPTION OFFICE HOMES RATNA CRUNCHER
  run update_aws_cli
  [ "$status" -eq 0 ]
  grep -q "curl.*awscli-exe-linux" "${MOCK_CALLS_FILE}"
  grep -q "unzip" "${MOCK_CALLS_FILE}"
}

# ── update_rust ──────────────────────────────────────────────────────────────

@test "update_rust does nothing when not Ubuntu Workstation" {
  export MACOS=1
  unset UBUNTU WORKSTATION CRUNCHER
  run update_rust
  [ "$status" -eq 0 ]
  ! grep -q "rustup" "${MOCK_CALLS_FILE}"
}

@test "update_rust calls system rustup when cargo rustup is absent" {
  export UBUNTU=1
  export WORKSTATION=1
  unset MACOS CRUNCHER
  # .cargo/bin/rustup does not exist in FAKE_HOME; rustup mock is in PATH
  run update_rust
  [ "$status" -eq 0 ]
  grep -q "rustup self update" "${MOCK_CALLS_FILE}"
}

@test "update_rust prints skip message when rustup is not found" {
  export UBUNTU=1
  export WORKSTATION=1
  export MOCK_WHICH_MISSING=rustup
  unset MACOS CRUNCHER
  run update_rust
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipping"* ]]
}
```

**Note:** The `update_rust` tests need a `rustup` mock. Add `tests/mocks/rustup`:

```bash
#!/usr/bin/env bash
printf "rustup %s\n" "$*" >> "${MOCK_CALLS_FILE:-/tmp/mock_calls}"
exit "${MOCK_RUSTUP_EXIT:-0}"
```

`chmod +x tests/mocks/rustup`.

- [ ] **Step 2: Run to verify tests fail**

```bash
bats tests/setup_env/extracted_functions.bats
```

Expected: FAIL — `update_system_packages/aws_cli/rust: command not found`.

- [ ] **Step 3: Extract update_system_packages() into setup_env.sh**

Add before the sourcing guard:

```bash
update_system_packages() {
  if [[ -n ${UBUNTU} ]]; then
    sudo -H apt update
    if [[ ${FOCAL} ]]; then
      sudo -H apt autoremove -y
    elif [[ ${JAMMY} ]]; then
      check_and_install_nala
      sudo -H nala full-upgrade -y
      sudo -H nala autoremove -y
    elif [[ ${NOBLE} ]]; then
      check_and_install_nala
      sudo -H nala full-upgrade -y
      sudo -H nala autoremove -y
    fi
    sudo snap refresh
    printf "Updated snap packages\\n"
  fi
  if [[ -n ${REDHAT} ]] || [[ -n ${FEDORA} ]]; then
    sudo -H dnf update -y
    printf "Updated dnf packages\\n"
  fi
  if [[ -n ${CENTOS} ]]; then
    sudo -H yum update -y
    printf "Updated yum packages\\n"
  fi
  if [[ -n ${MACOS} ]]; then
    printf "Updating mas packages\\n"
    mas upgrade
  fi
}
```

Replace the corresponding inline block in the UPDATE section with:

```bash
  update_system_packages
```

- [ ] **Step 4: Extract update_aws_cli() into setup_env.sh**

Add before the sourcing guard:

```bash
update_aws_cli() {
  if [[ -n ${LAPTOP} ]] || [[ -n ${STUDIO} ]] || [[ -n ${RECEPTION} ]] || [[ -n ${OFFICE} ]] || [[ -n ${HOMES} ]] || [[ -n ${RATNA} ]]; then
    if [[ -n ${MACOS} ]]; then
      printf "Updating MACOS awscli\\n"
      cd ${HOME}/software_downloads/awscli || exit
      curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
      sudo -H installer -pkg AWSCLIV2.pkg -target /
      rm AWSCLIV2.pkg
      cd ${PERSONAL_GITREPOS}/${DOTFILES} || exit
    fi
  fi
  if [[ -n ${WORKSTATION} ]] || [[ -n ${CRUNCHER} ]]; then
    printf "Updating Linux awscli\\n"
    mkdir -p ${HOME}/software_downloads/awscli
    cd ${HOME}/software_downloads/awscli || exit
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip -u -o awscliv2.zip
    sudo -H ${HOME}/software_downloads/awscli/aws/install --install-dir /usr/local/aws-cli --bin-dir /usr/local/bin --update
    cd ${PERSONAL_GITREPOS}/${DOTFILES} || exit
  fi
}
```

Replace the corresponding inline block in the UPDATE section with:

```bash
  update_aws_cli
```

- [ ] **Step 5: Extract update_rust() into setup_env.sh**

Add before the sourcing guard:

```bash
update_rust() {
  if [[ -n ${UBUNTU} ]] && { [[ -n ${WORKSTATION} ]] || [[ -n ${CRUNCHER} ]]; }; then
    printf "Updating Rust Ubuntu\\n"
    if [[ -x ${HOME}/.cargo/bin/rustup ]]; then
      ${HOME}/.cargo/bin/rustup self update
      ${HOME}/.cargo/bin/rustup update
    elif command -v rustup >/dev/null 2>&1; then
      rustup self update
      rustup update
    else
      printf "rustup not found; skipping Rust update\\n"
    fi
  fi
}
```

Replace the corresponding inline block in the UPDATE section with:

```bash
  update_rust
```

- [ ] **Step 6: Run tests to verify all pass**

```bash
bats tests/setup_env/extracted_functions.bats
```

Expected: 20 tests pass (11 from Tasks 5–6 + 4 system packages + 2 aws + 3 rust).

- [ ] **Step 7: Run full suite**

```bash
make test
```

Expected: 79 tests pass.

- [ ] **Step 8: Commit**

```bash
git add setup_env.sh tests/mocks/rustup tests/setup_env/extracted_functions.bats
git commit -m "refactor: extract update_system_packages(), update_aws_cli(), update_rust()

Extract 3 inline UPDATE block sections into named functions. Add rustup
mock and 9 tests covering platform-dispatch logic for each function."
```

---

### Task 8: Update CLAUDE.md mock table and run final verification

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Extend the mock env var table in CLAUDE.md**

Add these rows to the existing mock table under `## Testing`:

```markdown
| `MOCK_ID_U` | Value returned by `id -u` (default: 1000) |
| `MOCK_YUM_LIST_EXIT` | Exit code for `yum list installed` (default: 0) |
| `MOCK_YUM_EXIT` | Exit code for other `yum` commands (default: 0) |
| `MOCK_AWK_OS_NAME` | Distro name returned when `awk` parses `os-release` |
| `MOCK_SW_VERS_PRODUCTVERSION` | OS version returned by `sw_vers -productVersion` (default: 12.0.0) |
| `MOCK_SYSCTL_CPU` | CPU brand string returned by `sysctl -n machdep.cpu.brand_string` (default: Apple M1) |
| `MOCK_PGREP_EXIT` | Exit code for `pgrep` (default: 1 = process not found) |
| `MOCK_SOFTWAREUPDATE_EXIT` | Exit code for `softwareupdate` (default: 0) |
| `MOCK_WGET_EXIT` | Exit code for `wget` (default: 0); `-O` target file is created |
| `MOCK_DPKG_EXIT` | Exit code for `dpkg` (default: 0) |
| `MOCK_CHSH_EXIT` | Exit code for `chsh` (default: 0) |
| `MOCK_APT_EXIT` | Exit code for `apt` (default: 0) |
| `MOCK_ADD_APT_REPO_EXIT` | Exit code for `add-apt-repository` (default: 0) |
| `MOCK_DNF_EXIT` | Exit code for `dnf` (default: 0) |
| `MOCK_INSTALLER_EXIT` | Exit code for `installer` (default: 0) |
| `MOCK_UNZIP_EXIT` | Exit code for `unzip` (default: 0) |
| `MOCK_GIT_CLONE_EXIT` | Exit code for `git clone` (default: 0); target directory is created |
| `MOCK_GIT_EXIT` | Exit code for all other `git` commands (default: 0) |
| `MOCK_MAS_EXIT` | Exit code for `mas` (default: 0) |
| `MOCK_SNAP_EXIT` | Exit code for `snap` (default: 0) |
| `MOCK_NALA_EXIT` | Exit code for `nala` (default: 0) |
| `MOCK_RUSTUP_EXIT` | Exit code for `rustup` (default: 0) |
```

- [ ] **Step 2: Run full test suite one final time**

```bash
make test
```

Expected: 79 tests pass, 0 failures.

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md mock table with 22 new mock env vars"
```

---

## Coverage After This Plan

| Function | Before | After |
|---|---|---|
| `quiet_which` | tested | tested |
| `app_dir_exists` | tested | tested |
| `process_args` | tested | tested |
| `brew_formula_installed` | tested | tested |
| `brew_cask_installed` | tested | tested |
| `brew_install_formula` | tested | tested |
| `brew_tap_if_missing` | tested | tested |
| `install_bats` | tested | tested |
| `ensure_not_root` | — | tested |
| `brew_tap_installed` | — | tested |
| `brew_install_cask` | — | tested |
| `rhel_installed_package` | — | tested |
| `install_git` | — | tested (+ bug fixed) |
| `install_zsh` | — | tested |
| `install_rosetta` | — | tested (+ path fix) |
| `check_and_install_nala` | — | tested |
| `clone_or_update_dotfiles` | — | extracted + tested |
| `setup_dotfile_symlinks` | — | extracted + tested |
| `setup_credential_directories` | — | extracted + tested |
| `setup_zsh_as_default_shell` | — | extracted + tested |
| `update_system_packages` | — | extracted + tested |
| `update_aws_cli` | — | extracted + tested |
| `update_rust` | — | extracted + tested |
| `install_homebrew` | — | — (Xcode mock complexity) |
| `brew_update` | — | — (covered indirectly) |
| `usage` | — | — (trivial output) |

**Coverage: 23/26 functions (88%)**
**Total tests: 79 (was 41)**
