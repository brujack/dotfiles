# zshrc.d Test Coverage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expand `tests/zshrc.d/` from 10 to 43 tests by adding behavioural coverage for `2_functions.zsh`, `5_general.zsh`, `6_path.zsh`, and `7_final.zsh`, plus fix the `mkill()` `exit 1` bug.

**Architecture:** Four new BATS files follow the pattern in `tests/zshrc.d/unit.bats` — each test sources the target `.zsh` file inside a `zsh -c` subprocess, injects per-test mock executables via `PATH`, and asserts on stdout or exit status. `load_mocks()` is NOT called in `setup()` because prepending `tests/mocks/` to the outer `PATH` corrupts PATH for zsh subprocesses. Mocks are injected per-test inside `zsh -c` invocations.

**Tech Stack:** BATS (Bash Automated Testing System), zsh subprocesses, per-test PATH-based mock injection

---

## Files

| Action | Path                                                                                    |
| ------ | --------------------------------------------------------------------------------------- |
| Create | `tests/zshrc.d/functions.bats`                                                          |
| Modify | `.devcontainer/.config/.zshrc.d/2_functions.zsh` (fix `exit 1` → `return 1` in `mkill`) |
| Create | `tests/zshrc.d/general.bats`                                                            |
| Create | `tests/zshrc.d/path.bats`                                                               |
| Create | `tests/zshrc.d/final.bats`                                                              |
| Modify | `README.md` (update PowerShell layout section)                                          |

---

### Task 1: `functions.bats` — 13 tests + `mkill()` bug fix

**Files:**

- Create: `tests/zshrc.d/functions.bats`
- Modify: `.devcontainer/.config/.zshrc.d/2_functions.zsh`

**Context:** `2_functions.zsh` defines `Make()`, `quiet_which()`, `mkill()`, `findStringInFile()`, `tssh()`, `sh()`, `sshu()`, and `search_pkg()`. The `mkill()` function has a bug: it uses `exit 1` instead of `return 1` in its no-args guard, which kills the interactive shell session when called without arguments. In the test subprocess `exit 1` and `return 1` behave identically (both exit the subprocess with status 1), so the test passes before and after the fix — fix it anyway because `exit 1` in a function is always wrong in interactive shells.

The `Make()` tests need platform variables (`MACOS`, `LINUX`, `RATNA`, `LAPTOP`, etc.) explicitly unset so the hostname-specific hardcoded gmake paths (`/usr/local/bin/gmake`, `/opt/homebrew/bin/gmake`) are bypassed and the `command -v gmake` fallback is tested cleanly. Tests 3 and 4 use a minimal PATH with only the mock dir so the outcome is deterministic.

- [ ] **Step 1: Write the failing tests — create `tests/zshrc.d/functions.bats`**

```bash
#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  ZSHRC_D="${REPO_ROOT}/.devcontainer/.config/.zshrc.d"
  source "${REPO_ROOT}/tests/helpers/common.bash"
}

# ── Make() ───────────────────────────────────────────────────────────────────

@test "Make uses task when Taskfile.yml exists" {
  local mock_dir="${BATS_TEST_TMPDIR}/mocks_make_yml"
  local work_dir="${BATS_TEST_TMPDIR}/work_make_yml"
  mkdir -p "${mock_dir}" "${work_dir}"
  printf '#!/bin/zsh\nprintf "task called\\n"' > "${mock_dir}/task"
  chmod +x "${mock_dir}/task"
  touch "${work_dir}/Taskfile.yml"

  run zsh -c "
    export PATH='${mock_dir}:${PATH}'
    cd '${work_dir}'
    unset MACOS LINUX RATNA LAPTOP STUDIO RECEPTION OFFICE HOMES
    source '${ZSHRC_D}/2_functions.zsh' 2>/dev/null
    Make
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"task called"* ]]
}

@test "Make uses task when Taskfile.yaml exists" {
  local mock_dir="${BATS_TEST_TMPDIR}/mocks_make_yaml"
  local work_dir="${BATS_TEST_TMPDIR}/work_make_yaml"
  mkdir -p "${mock_dir}" "${work_dir}"
  printf '#!/bin/zsh\nprintf "task called\\n"' > "${mock_dir}/task"
  chmod +x "${mock_dir}/task"
  touch "${work_dir}/Taskfile.yaml"

  run zsh -c "
    export PATH='${mock_dir}:${PATH}'
    cd '${work_dir}'
    unset MACOS LINUX RATNA LAPTOP STUDIO RECEPTION OFFICE HOMES
    source '${ZSHRC_D}/2_functions.zsh' 2>/dev/null
    Make
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"task called"* ]]
}

@test "Make uses gmake when no Taskfile and gmake is available" {
  local mock_dir="${BATS_TEST_TMPDIR}/mocks_make_gmake"
  local work_dir="${BATS_TEST_TMPDIR}/work_make_gmake"
  mkdir -p "${mock_dir}" "${work_dir}"
  printf '#!/bin/zsh\nprintf "gmake called\\n"' > "${mock_dir}/gmake"
  chmod +x "${mock_dir}/gmake"

  run zsh -c "
    export PATH='${mock_dir}'
    cd '${work_dir}'
    unset MACOS LINUX RATNA LAPTOP STUDIO RECEPTION OFFICE HOMES
    source '${ZSHRC_D}/2_functions.zsh' 2>/dev/null
    Make
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"gmake called"* ]]
}

@test "Make falls back to make when no Taskfile and no gmake" {
  local mock_dir="${BATS_TEST_TMPDIR}/mocks_make_fallback"
  local work_dir="${BATS_TEST_TMPDIR}/work_make_fallback"
  mkdir -p "${mock_dir}" "${work_dir}"
  printf '#!/bin/zsh\nprintf "make called\\n"' > "${mock_dir}/make"
  chmod +x "${mock_dir}/make"

  run zsh -c "
    export PATH='${mock_dir}'
    cd '${work_dir}'
    unset MACOS LINUX RATNA LAPTOP STUDIO RECEPTION OFFICE HOMES
    source '${ZSHRC_D}/2_functions.zsh' 2>/dev/null
    Make
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"make called"* ]]
}

# ── quiet_which() ─────────────────────────────────────────────────────────────

@test "quiet_which prints usage and returns 1 when called with no args" {
  run zsh -c "
    source '${ZSHRC_D}/2_functions.zsh' 2>/dev/null
    quiet_which
  "
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage"* ]]
}

@test "quiet_which returns 0 when command exists" {
  local mock_dir="${BATS_TEST_TMPDIR}/mocks_qw_exists"
  mkdir -p "${mock_dir}"
  printf '#!/bin/zsh\n' > "${mock_dir}/sometool"
  chmod +x "${mock_dir}/sometool"

  run zsh -c "
    export PATH='${mock_dir}'
    source '${ZSHRC_D}/2_functions.zsh' 2>/dev/null
    quiet_which sometool
  "
  [ "$status" -eq 0 ]
}

@test "quiet_which returns 1 when command does not exist" {
  run zsh -c "
    export PATH='${BATS_TEST_TMPDIR}/empty'
    source '${ZSHRC_D}/2_functions.zsh' 2>/dev/null
    quiet_which nonexistentcommand12345
  "
  [ "$status" -eq 1 ]
}

# ── mkill() ──────────────────────────────────────────────────────────────────

@test "mkill returns 1 and prints message when called with no args" {
  run zsh -c "
    source '${ZSHRC_D}/2_functions.zsh' 2>/dev/null
    mkill
  "
  [ "$status" -eq 1 ]
  [[ "$output" == *"Please provide"* ]]
}

@test "mkill prints not running when process is not found" {
  local mock_dir="${BATS_TEST_TMPDIR}/mocks_mkill_notfound"
  mkdir -p "${mock_dir}"
  printf '#!/bin/zsh\nexit 1' > "${mock_dir}/pgrep"
  chmod +x "${mock_dir}/pgrep"

  run zsh -c "
    export PATH='${mock_dir}:${PATH}'
    source '${ZSHRC_D}/2_functions.zsh' 2>/dev/null
    mkill someprocess
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"not running"* ]]
}

# ── findStringInFile() ───────────────────────────────────────────────────────

@test "findStringInFile prints error when no file arg" {
  run zsh -c "
    source '${ZSHRC_D}/2_functions.zsh' 2>/dev/null
    findStringInFile
  "
  [[ "$output" == *"No file supplied"* ]]
}

@test "findStringInFile prints error when no string arg" {
  local tmp_file="${BATS_TEST_TMPDIR}/testfile.txt"
  touch "${tmp_file}"

  run zsh -c "
    source '${ZSHRC_D}/2_functions.zsh' 2>/dev/null
    findStringInFile '${tmp_file}'
  "
  [[ "$output" == *"No string supplied"* ]]
}

# ── arg-validation for external-call functions ────────────────────────────────

@test "tssh returns 1 and prints message when called with no args" {
  run zsh -c "
    source '${ZSHRC_D}/2_functions.zsh' 2>/dev/null
    tssh
  "
  [ "$status" -eq 1 ]
  [[ "$output" == *"No arguments"* ]]
}

@test "sh returns 1 and prints message when called with no args" {
  run zsh -c "
    source '${ZSHRC_D}/2_functions.zsh' 2>/dev/null
    sh
  "
  [ "$status" -eq 1 ]
  [[ "$output" == *"No arguments"* ]]
}

@test "sshu returns 1 and prints message when called with no args" {
  run zsh -c "
    source '${ZSHRC_D}/2_functions.zsh' 2>/dev/null
    sshu
  "
  [ "$status" -eq 1 ]
  [[ "$output" == *"No arguments"* ]]
}

@test "search_pkg returns 1 and prints message when called with no args" {
  run zsh -c "
    source '${ZSHRC_D}/2_functions.zsh' 2>/dev/null
    search_pkg
  "
  [ "$status" -eq 1 ]
  [[ "$output" == *"No arguments"* ]]
}
```

- [ ] **Step 2: Run the tests to see initial state**

```bash
cd /path/to/dotfiles
bats tests/zshrc.d/functions.bats
```

Expected: `mkill returns 1` test passes (exit 1 in subprocess = status 1), all others pass for existing functions.

- [ ] **Step 3: Fix `mkill()` — change `exit 1` to `return 1`**

In `.devcontainer/.config/.zshrc.d/2_functions.zsh`, find:

```zsh
function mkill() {
  if [ $# -eq 0 ]; then
    echo "Please provide the name of the process to kill as an argument."
    exit 1
  fi
```

Change to:

```zsh
function mkill() {
  if [ $# -eq 0 ]; then
    echo "Please provide the name of the process to kill as an argument."
    return 1
  fi
```

- [ ] **Step 4: Run the full test suite to confirm all tests pass**

```bash
make test
```

Expected: all existing tests pass + 13 new tests in `functions.bats` pass. Total BATS count increases by 13.

- [ ] **Step 5: Commit**

```bash
git add tests/zshrc.d/functions.bats .devcontainer/.config/.zshrc.d/2_functions.zsh
git commit -m "test: add functions.bats for 2_functions.zsh; fix mkill exit 1 to return 1"
```

---

### Task 2: `tests/zshrc.d/general.bats` — 6 tests

**Files:**

- Create: `tests/zshrc.d/general.bats`

**Context:** `5_general.zsh` contains an unconditional `git clone` call guarded only by the absence of `~/.oh-my-zsh/custom/plugins/zsh-autosuggestions`. Every test must create that directory under a fake `HOME` (`${BATS_TEST_TMPDIR}/home_<name>`) to prevent a real network call. Setting `HOME` to a fake dir inside `zsh -c` works because `5_general.zsh` uses `${HOME}` (not `~`) for that guard. `2>/dev/null` suppresses errors from optional `source` calls (keychain with absolute path `/usr/bin/keychain` — not in PATH on macOS — evaluates to empty string, which is a no-op), `eval "$(tty)"` errors, and `autoload` failures.

- [ ] **Step 1: Write the failing tests — create `tests/zshrc.d/general.bats`**

```bash
#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  ZSHRC_D="${REPO_ROOT}/.devcontainer/.config/.zshrc.d"
  source "${REPO_ROOT}/tests/helpers/common.bash"
}

# Helper: create a fake HOME pre-populated with the zsh-autosuggestions dir
# so 5_general.zsh does not attempt a git clone during tests.
_make_general_home() {
  local fake_home="$1"
  mkdir -p "${fake_home}/.oh-my-zsh/custom/plugins/zsh-autosuggestions"
}

# ── EDITOR / GIT_EDITOR ──────────────────────────────────────────────────────

@test "5_general.zsh sets EDITOR=vim and GIT_EDITOR=vim on Linux" {
  local fake_home="${BATS_TEST_TMPDIR}/home_general_linux_editor"
  _make_general_home "${fake_home}"

  run zsh -c "
    export HOME='${fake_home}'
    export LINUX=1
    unset MACOS SSH_CONNECTION ZSH_CUSTOM
    source '${ZSHRC_D}/5_general.zsh' 2>/dev/null
    printf '%s %s\n' \"\$EDITOR\" \"\$GIT_EDITOR\"
  "
  [ "$status" -eq 0 ]
  [ "$output" = "vim vim" ]
}

@test "5_general.zsh sets EDITOR=code and GIT_EDITOR=code on macOS without SSH" {
  local fake_home="${BATS_TEST_TMPDIR}/home_general_macos_editor"
  _make_general_home "${fake_home}"

  run zsh -c "
    export HOME='${fake_home}'
    export MACOS=1
    unset LINUX SSH_CONNECTION ZSH_CUSTOM
    source '${ZSHRC_D}/5_general.zsh' 2>/dev/null
    printf '%s %s\n' \"\$EDITOR\" \"\$GIT_EDITOR\"
  "
  [ "$status" -eq 0 ]
  [ "$output" = "code code" ]
}

@test "5_general.zsh sets EDITOR=vim and GIT_EDITOR=vim on macOS with SSH_CONNECTION set" {
  local fake_home="${BATS_TEST_TMPDIR}/home_general_macos_ssh"
  _make_general_home "${fake_home}"

  run zsh -c "
    export HOME='${fake_home}'
    export MACOS=1
    export SSH_CONNECTION=1
    unset LINUX ZSH_CUSTOM
    source '${ZSHRC_D}/5_general.zsh' 2>/dev/null
    printf '%s %s\n' \"\$EDITOR\" \"\$GIT_EDITOR\"
  "
  [ "$status" -eq 0 ]
  [ "$output" = "vim vim" ]
}

# ── PSHOME ───────────────────────────────────────────────────────────────────

@test "5_general.zsh sets PSHOME to macOS path on macOS" {
  local fake_home="${BATS_TEST_TMPDIR}/home_general_pshome_mac"
  _make_general_home "${fake_home}"

  run zsh -c "
    export HOME='${fake_home}'
    export MACOS=1
    unset LINUX SSH_CONNECTION ZSH_CUSTOM
    source '${ZSHRC_D}/5_general.zsh' 2>/dev/null
    printf '%s\n' \"\$PSHOME\"
  "
  [ "$status" -eq 0 ]
  [ "$output" = "/usr/local/microsoft/powershell/7/" ]
}

@test "5_general.zsh sets PSHOME to Linux path on Linux" {
  local fake_home="${BATS_TEST_TMPDIR}/home_general_pshome_linux"
  _make_general_home "${fake_home}"

  run zsh -c "
    export HOME='${fake_home}'
    export LINUX=1
    unset MACOS SSH_CONNECTION ZSH_CUSTOM
    source '${ZSHRC_D}/5_general.zsh' 2>/dev/null
    printf '%s\n' \"\$PSHOME\"
  "
  [ "$status" -eq 0 ]
  [ "$output" = "/opt/microsoft/powershell/7/" ]
}

# ── ANSIBLEUSER ──────────────────────────────────────────────────────────────

@test "5_general.zsh sets ANSIBLEUSER=ubuntu" {
  local fake_home="${BATS_TEST_TMPDIR}/home_general_ansibleuser"
  _make_general_home "${fake_home}"

  run zsh -c "
    export HOME='${fake_home}'
    export MACOS=1
    unset LINUX SSH_CONNECTION ZSH_CUSTOM
    source '${ZSHRC_D}/5_general.zsh' 2>/dev/null
    printf '%s\n' \"\$ANSIBLEUSER\"
  "
  [ "$status" -eq 0 ]
  [ "$output" = "ubuntu" ]
}
```

- [ ] **Step 2: Run the tests**

```bash
bats tests/zshrc.d/general.bats
```

Expected: all 6 tests pass.

- [ ] **Step 3: Run the full test suite**

```bash
make test
```

Expected: all tests pass. BATS count increases by 6.

- [ ] **Step 4: Commit**

```bash
git add tests/zshrc.d/general.bats
git commit -m "test: add general.bats for 5_general.zsh (EDITOR, PSHOME, ANSIBLEUSER)"
```

---

### Task 3: `tests/zshrc.d/path.bats` — 8 tests

**Files:**

- Create: `tests/zshrc.d/path.bats`

**Context:** `6_path.zsh` adds directories to the `path` array (which is tied to `$PATH`) using `typeset -U path` for automatic deduplication. Tests use a fake `HOME` in `BATS_TEST_TMPDIR` so `${HOME}/bin`, `${HOME}/scripts`, `${HOME}/.cargo/bin` checks hit temp dirs. Tests 4 and 7 use `skip` guards for hardcoded paths (`/opt/homebrew/bin`, `/home/linuxbrew/.linuxbrew/bin`) that can only be tested when those directories exist on the machine.

- [ ] **Step 1: Write the failing tests — create `tests/zshrc.d/path.bats`**

```bash
#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  ZSHRC_D="${REPO_ROOT}/.devcontainer/.config/.zshrc.d"
  source "${REPO_ROOT}/tests/helpers/common.bash"
}

# ── ~/bin ────────────────────────────────────────────────────────────────────

@test "6_path.zsh adds ~/bin to PATH when it exists" {
  local fake_home="${BATS_TEST_TMPDIR}/home_path_bin"
  mkdir -p "${fake_home}/bin"

  run zsh -c "
    export HOME='${fake_home}'
    unset MACOS LINUX UBUNTU REDHAT
    source '${ZSHRC_D}/6_path.zsh' 2>/dev/null
    printf '%s\n' \"\$PATH\"
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"${fake_home}/bin"* ]]
}

@test "6_path.zsh does not add ~/bin to PATH when it does not exist" {
  local fake_home="${BATS_TEST_TMPDIR}/home_path_nobin"
  mkdir -p "${fake_home}"

  run zsh -c "
    export HOME='${fake_home}'
    unset MACOS LINUX UBUNTU REDHAT
    source '${ZSHRC_D}/6_path.zsh' 2>/dev/null
    printf '%s\n' \"\$PATH\"
  "
  [ "$status" -eq 0 ]
  [[ "$output" != *"${fake_home}/bin"* ]]
}

# ── ~/scripts ────────────────────────────────────────────────────────────────

@test "6_path.zsh adds ~/scripts to PATH when it exists" {
  local fake_home="${BATS_TEST_TMPDIR}/home_path_scripts"
  mkdir -p "${fake_home}/scripts"

  run zsh -c "
    export HOME='${fake_home}'
    unset MACOS LINUX UBUNTU REDHAT
    source '${ZSHRC_D}/6_path.zsh' 2>/dev/null
    printf '%s\n' \"\$PATH\"
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"${fake_home}/scripts"* ]]
}

# ── /opt/homebrew/bin ────────────────────────────────────────────────────────

@test "6_path.zsh adds /opt/homebrew/bin on macOS when present" {
  [ -d /opt/homebrew/bin ] || skip "/opt/homebrew/bin not present on this machine"
  local fake_home="${BATS_TEST_TMPDIR}/home_path_homebrew"
  mkdir -p "${fake_home}"

  run zsh -c "
    export HOME='${fake_home}'
    export MACOS=1
    unset LINUX UBUNTU REDHAT
    source '${ZSHRC_D}/6_path.zsh' 2>/dev/null
    printf '%s\n' \"\$PATH\"
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"/opt/homebrew/bin"* ]]
}

@test "6_path.zsh does not add /opt/homebrew/bin when LINUX is set" {
  local fake_home="${BATS_TEST_TMPDIR}/home_path_linux_no_homebrew"
  mkdir -p "${fake_home}"

  run zsh -c "
    export HOME='${fake_home}'
    export LINUX=1
    unset MACOS UBUNTU REDHAT
    source '${ZSHRC_D}/6_path.zsh' 2>/dev/null
    printf '%s\n' \"\$PATH\"
  "
  [ "$status" -eq 0 ]
  [[ "$output" != *"/opt/homebrew/bin"* ]]
}

# ── ~/.cargo/bin ─────────────────────────────────────────────────────────────

@test "6_path.zsh adds ~/.cargo/bin to PATH when it exists" {
  local fake_home="${BATS_TEST_TMPDIR}/home_path_cargo"
  mkdir -p "${fake_home}/.cargo/bin"

  run zsh -c "
    export HOME='${fake_home}'
    unset MACOS LINUX UBUNTU REDHAT
    source '${ZSHRC_D}/6_path.zsh' 2>/dev/null
    printf '%s\n' \"\$PATH\"
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"${fake_home}/.cargo/bin"* ]]
}

# ── /home/linuxbrew ──────────────────────────────────────────────────────────

@test "6_path.zsh adds /home/linuxbrew/.linuxbrew/bin on Linux when present" {
  [ -d /home/linuxbrew/.linuxbrew/bin ] || skip "/home/linuxbrew not present on this machine"
  local fake_home="${BATS_TEST_TMPDIR}/home_path_linuxbrew"
  mkdir -p "${fake_home}"

  run zsh -c "
    export HOME='${fake_home}'
    export LINUX=1
    unset MACOS UBUNTU REDHAT
    source '${ZSHRC_D}/6_path.zsh' 2>/dev/null
    printf '%s\n' \"\$PATH\"
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"/home/linuxbrew/.linuxbrew/bin"* ]]
}

# ── deduplication ────────────────────────────────────────────────────────────

@test "6_path.zsh does not add duplicate PATH entries when sourced twice" {
  local fake_home="${BATS_TEST_TMPDIR}/home_path_dedup"
  mkdir -p "${fake_home}/bin"

  run zsh -c "
    export HOME='${fake_home}'
    unset MACOS LINUX UBUNTU REDHAT
    source '${ZSHRC_D}/6_path.zsh' 2>/dev/null
    source '${ZSHRC_D}/6_path.zsh' 2>/dev/null
    count=\$(printf '%s' \"\$PATH\" | tr ':' '\n' | grep -c '${fake_home}/bin')
    printf '%s\n' \"\$count\"
  "
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}
```

- [ ] **Step 2: Run the tests**

```bash
bats tests/zshrc.d/path.bats
```

Expected: all tests pass (tests 4 and 7 may be skipped on macOS dev machine without linuxbrew).

- [ ] **Step 3: Run the full test suite**

```bash
make test
```

Expected: all tests pass. BATS count increases by 8 (minus any skipped).

- [ ] **Step 4: Commit**

```bash
git add tests/zshrc.d/path.bats
git commit -m "test: add path.bats for 6_path.zsh (PATH additions and deduplication)"
```

---

### Task 4: `tests/zshrc.d/final.bats` — 6 tests

**Files:**

- Create: `tests/zshrc.d/final.bats`

**Context:** `7_final.zsh` calls `quiet_which zoxide` (defined in `2_functions.zsh`, not in `7_final.zsh`). Define `function quiet_which() { return 1; }` before sourcing in each test to prevent the undefined-function error and skip the `zoxide init` block. `eval "$(starship init zsh)"` always runs — mock `starship` in each test via a mock dir prepended to PATH that contains a no-op starship script. `GOROOT`/`GOPATH` tests that depend on hardcoded paths use complementary `skip` guards. ICON test 6 tests the "no platform set" case instead of Ubuntu (the Ubuntu distro detection uses a glob `/etc/*-release` that fails silently on macOS, leaving `ICON` unset rather than set to the Ubuntu icon).

- [ ] **Step 1: Write the failing tests — create `tests/zshrc.d/final.bats`**

```bash
#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  ZSHRC_D="${REPO_ROOT}/.devcontainer/.config/.zshrc.d"
  source "${REPO_ROOT}/tests/helpers/common.bash"

  # Create a no-op starship mock used by all tests.
  # 7_final.zsh always calls eval "$(starship init zsh)".
  # Without this mock, the real starship (if installed) would run and
  # pollute the test output.
  MOCK_DIR="${BATS_TEST_TMPDIR}/mocks"
  mkdir -p "${MOCK_DIR}"
  printf '#!/bin/zsh\n' > "${MOCK_DIR}/starship"
  chmod +x "${MOCK_DIR}/starship"
}

# ── GOROOT ───────────────────────────────────────────────────────────────────

@test "7_final.zsh sets GOROOT when /usr/local/go exists" {
  [ -d /usr/local/go ] || skip "/usr/local/go not present on this machine"

  run zsh -c "
    function quiet_which() { return 1; }
    export PATH='${MOCK_DIR}:${PATH}'
    unset MACOS LINUX GOROOT
    source '${ZSHRC_D}/7_final.zsh' 2>/dev/null
    printf '%s\n' \"\${GOROOT:-unset}\"
  "
  [ "$status" -eq 0 ]
  [ "$output" = "/usr/local/go" ]
}

@test "7_final.zsh does not set GOROOT when /usr/local/go is absent" {
  [ ! -d /usr/local/go ] || skip "/usr/local/go present on this machine"

  run zsh -c "
    function quiet_which() { return 1; }
    export PATH='${MOCK_DIR}:${PATH}'
    unset MACOS LINUX GOROOT
    source '${ZSHRC_D}/7_final.zsh' 2>/dev/null
    printf '%s\n' \"\${GOROOT:-unset}\"
  "
  [ "$status" -eq 0 ]
  [ "$output" = "unset" ]
}

# ── GOPATH ───────────────────────────────────────────────────────────────────

@test "7_final.zsh sets GOPATH when ~/go-work exists" {
  local fake_home="${BATS_TEST_TMPDIR}/home_final_gopath"
  mkdir -p "${fake_home}/go-work"

  run zsh -c "
    function quiet_which() { return 1; }
    export PATH='${MOCK_DIR}:${PATH}'
    export HOME='${fake_home}'
    unset MACOS LINUX GOPATH
    source '${ZSHRC_D}/7_final.zsh' 2>/dev/null
    printf '%s\n' \"\${GOPATH:-unset}\"
  "
  [ "$status" -eq 0 ]
  [ "$output" = "${fake_home}/go-work" ]
}

@test "7_final.zsh does not set GOPATH when ~/go-work is absent" {
  local fake_home="${BATS_TEST_TMPDIR}/home_final_no_gopath"
  mkdir -p "${fake_home}"

  run zsh -c "
    function quiet_which() { return 1; }
    export PATH='${MOCK_DIR}:${PATH}'
    export HOME='${fake_home}'
    unset MACOS LINUX GOPATH
    source '${ZSHRC_D}/7_final.zsh' 2>/dev/null
    printf '%s\n' \"\${GOPATH:-unset}\"
  "
  [ "$status" -eq 0 ]
  [ "$output" = "unset" ]
}

# ── ICON ─────────────────────────────────────────────────────────────────────

@test "7_final.zsh sets ICON on macOS" {
  run zsh -c "
    function quiet_which() { return 1; }
    export PATH='${MOCK_DIR}:${PATH}'
    export MACOS=1
    unset LINUX ICON
    source '${ZSHRC_D}/7_final.zsh' 2>/dev/null
    printf '%s\n' \"\${ICON:-unset}\"
  "
  [ "$status" -eq 0 ]
  [ "$output" != "unset" ]
}

@test "7_final.zsh does not set ICON when neither MACOS nor LINUX is set" {
  run zsh -c "
    function quiet_which() { return 1; }
    export PATH='${MOCK_DIR}:${PATH}'
    unset MACOS LINUX ICON
    source '${ZSHRC_D}/7_final.zsh' 2>/dev/null
    printf '%s\n' \"\${ICON:-unset}\"
  "
  [ "$status" -eq 0 ]
  [ "$output" = "unset" ]
}
```

- [ ] **Step 2: Run the tests**

```bash
bats tests/zshrc.d/final.bats
```

Expected: all 6 tests pass (GOROOT tests may be skipped depending on machine).

- [ ] **Step 3: Run the full test suite**

```bash
make test
```

Expected: all tests pass. Total BATS count is now 43 (minus any skipped).

- [ ] **Step 4: Commit**

```bash
git add tests/zshrc.d/final.bats
git commit -m "test: add final.bats for 7_final.zsh (GOROOT, GOPATH, ICON)"
```

---

### Task 5: Update README with current PowerShell layout

**Files:**

- Modify: `README.md`

**Context:** The README `Repository Layout` section still shows the old single-file PowerShell layout from before the Makefile and test infrastructure was added.

- [ ] **Step 1: Update the PowerShell section in `README.md`**

Find:

```
├── powershell/
│   └── setup_windows.ps1     # Windows/PowerShell bootstrap
```

Replace with:

```
├── powershell/
│   ├── setup_windows.ps1     # Windows/PowerShell bootstrap
│   ├── Makefile              # lint + test targets
│   ├── PSScriptAnalyzerSettings.psd1  # PSScriptAnalyzer rule config
│   ├── run-lint.ps1          # lint script with module path restoration
│   ├── run-tests.ps1         # lint + Pester test runner
│   └── tests/
│       └── setup_windows.Tests.ps1   # Pester v5 unit tests (22 tests)
```

- [ ] **Step 2: Verify README renders correctly**

```bash
head -80 README.md
```

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: update README PowerShell layout to reflect current structure"
```

---

## Test Count Summary

| File                           | Before | Added  | After  |
| ------------------------------ | ------ | ------ | ------ |
| `tests/zshrc.d/unit.bats`      | 10     | 0      | 10     |
| `tests/zshrc.d/functions.bats` | 0      | 13     | 13     |
| `tests/zshrc.d/general.bats`   | 0      | 6      | 6      |
| `tests/zshrc.d/path.bats`      | 0      | 8      | 8      |
| `tests/zshrc.d/final.bats`     | 0      | 6      | 6      |
| **Total**                      | **10** | **33** | **43** |
