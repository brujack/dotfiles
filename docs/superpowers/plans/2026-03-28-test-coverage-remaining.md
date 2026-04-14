# Remaining Test Coverage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete test coverage for 3 untested `setup_env.sh` functions, 1 missing platform test, 2 bug fixes in `scripts/`, and BATS tests for all 8 scripts in `scripts/`.

**Architecture:** All tests use BATS with PATH-based mock injection (`tests/mocks/` prepended via `load_mocks`). `setup_env.sh` functions are tested by sourcing via `load_setup_env` then calling the function directly. Scripts in `scripts/` are invoked as subprocesses (`run bash scripts/foo.sh`). The `sudo` mock is updated to log invocations before delegating, enabling `scripts/` tests that call `sudo` with absolute-path commands (e.g., `sudo /etc/init.d/FAHClient`).

**Tech Stack:** BATS 1.11.0, bash mock scripts, PATH-based mock injection

---

## File Structure

**New mock files (all in `tests/mocks/`):**

- `xcode-select` — configurable exit for `--print-path` and `--install`
- `xcodebuild` — configurable exit
- `kill` — logs call, configurable exit
- `tmux` — logs call, configurable exit
- `rsync` — logs call, configurable exit
- `hostname` — returns `MOCK_HOSTNAME_OUTPUT` for `-s`; delegates otherwise
- `sleep` — logs call, configurable exit

**Modified mock files:**

- `tests/mocks/sudo` — add logging before delegation; skip exec when target doesn't exist
- `tests/mocks/brew` — add `update`, `upgrade`, `cleanup` cases with individual exit codes
- `tests/mocks/curl` — add `MOCK_CURL_STDOUT` output for command-substitution use
- `tests/mocks/pgrep` — add `MOCK_PGREP_OUTPUT` for PID simulation

**Modified test files:**

- `tests/setup_env/unit.bats` — add 1 test (`usage`)
- `tests/setup_env/extracted_functions.bats` — add 1 test (macOS mas path)
- `tests/setup_env/install_functions.bats` — add 4 tests (`install_homebrew`)
- `tests/setup_env/install_guards.bats` — add 4 tests (`brew_update`)

**New test file:**

- `tests/scripts/unit.bats` — 22 tests for all 8 scripts in `scripts/`

**Bug fixes:**

- `scripts/count_lines.sh` — replace `pipe | while` with `while < <(...)` process substitution
- `scripts/count_lines_git.sh` — same fix

**Docs:**

- `CLAUDE.md` — add 12 new mock env var rows to the mock table

---

### Task 1: Create xcode-select and xcodebuild mocks; update sudo mock

**Files:**

- Create: `tests/mocks/xcode-select`
- Create: `tests/mocks/xcodebuild`
- Modify: `tests/mocks/sudo`

**Context:** The `sudo` mock currently drops `-H` and `exec`s remaining args without logging. This means `sudo /etc/init.d/FAHClient stop` (used in `restart_fah.sh`) tries to exec an absolute path that doesn't exist on a dev machine and fails silently. The fix: log first, then only exec if the target command exists. This does not break existing tests — they check for mock-logged commands like `apt install`, which are still logged by the delegated mock.

- [ ] **Step 1: Create tests/mocks/xcode-select**

```bash
#!/usr/bin/env bash
printf "xcode-select %s\n" "$*" >> "${MOCK_CALLS_FILE:-/tmp/mock_calls}"
if [[ "$1" == "--print-path" ]]; then
  exit "${MOCK_XCODE_SELECT_PRINT_PATH_EXIT:-0}"
fi
if [[ "$1" == "--install" ]]; then
  exit "${MOCK_XCODE_SELECT_EXIT:-0}"
fi
exit 0
```

```bash
chmod +x tests/mocks/xcode-select
```

- [ ] **Step 2: Create tests/mocks/xcodebuild**

```bash
#!/usr/bin/env bash
printf "xcodebuild %s\n" "$*" >> "${MOCK_CALLS_FILE:-/tmp/mock_calls}"
exit "${MOCK_XCODEBUILD_EXIT:-0}"
```

```bash
chmod +x tests/mocks/xcodebuild
```

- [ ] **Step 3: Update tests/mocks/sudo**

Replace the entire file with:

```bash
#!/usr/bin/env bash
# Log the full invocation first (enables assertions in scripts/unit.bats tests
# that call sudo with absolute paths like /etc/init.d/FAHClient)
printf "sudo %s\n" "$*" >> "${MOCK_CALLS_FILE:-/tmp/mock_calls}"
# Drop -H flag; collect remaining args
args=()
for arg in "$@"; do
  [[ "$arg" == "-H" ]] && continue
  args+=("$arg")
done
# Only exec the target if it exists — absolute paths like /etc/init.d/FAHClient
# are absent on dev machines and should not cause exec to fail
if [[ "${#args[@]}" -gt 0 ]] && { [[ -x "${args[0]}" ]] || command -v "${args[0]}" &>/dev/null; }; then
  exec "${args[@]}"
fi
exit "${MOCK_SUDO_EXIT:-0}"
```

- [ ] **Step 4: Run make test to verify no existing tests break**

```bash
make test
```

Expected: all 89 tests pass, exit 0.

- [ ] **Step 5: Commit**

```bash
git add tests/mocks/xcode-select tests/mocks/xcodebuild tests/mocks/sudo
git commit -m "test: add xcode-select and xcodebuild mocks; update sudo mock to log invocations

sudo mock now logs before delegating and skips exec for absent absolute-path
commands (e.g. /etc/init.d/FAHClient), enabling scripts/unit.bats tests.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 2: Extend brew, curl, and pgrep mocks

**Files:**

- Modify: `tests/mocks/brew`
- Modify: `tests/mocks/curl`
- Modify: `tests/mocks/pgrep`

**Context:** `brew_update` calls `brew update`, `brew upgrade`, and `brew cleanup` — all currently handled by the catch-all `MOCK_BREW_EXIT`. We need per-subcommand control. `install_homebrew` uses `/bin/bash -c "$(curl -fsSL ...)"` — the curl mock must emit `MOCK_CURL_STDOUT` to stdout so the command substitution produces a controllable bash snippet. `mkill.sh` and `restart_fah.sh` need pgrep to emit PIDs so the kill loop can be tested.

- [ ] **Step 1: Update tests/mocks/brew**

Replace the entire file with:

```bash
#!/usr/bin/env bash
printf "brew %s\n" "$*" >> "${MOCK_CALLS_FILE:-/tmp/mock_calls}"

case "$1" in
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

- [ ] **Step 2: Update tests/mocks/curl**

Replace the entire file with:

```bash
#!/usr/bin/env bash
printf "curl %s\n" "$*" >> "${MOCK_CALLS_FILE:-/tmp/mock_calls}"
# Handle -o <file>: create an empty placeholder file
outfile=""
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "-o" ]]; then
    outfile="$2"
    shift 2
  else
    shift
  fi
done
[[ -n "${outfile}" ]] && touch "${outfile}"
# Emit MOCK_CURL_STDOUT to stdout if set — used by install_homebrew's
# /bin/bash -c "$(curl -fsSL ...)" so the substituted snippet is controllable
[[ -n "${MOCK_CURL_STDOUT:-}" ]] && printf "%s\n" "${MOCK_CURL_STDOUT}"
exit "${MOCK_CURL_EXIT:-0}"
```

- [ ] **Step 3: Update tests/mocks/pgrep**

Replace the entire file with:

```bash
#!/usr/bin/env bash
printf "pgrep %s\n" "$*" >> "${MOCK_CALLS_FILE:-/tmp/mock_calls}"
# Emit MOCK_PGREP_OUTPUT to stdout if set — used to simulate found PIDs
# so that for-loop callers (mkill.sh, restart_fah.sh) can be tested
[[ -n "${MOCK_PGREP_OUTPUT:-}" ]] && printf "%s\n" "${MOCK_PGREP_OUTPUT}"
exit "${MOCK_PGREP_EXIT:-1}"
```

- [ ] **Step 4: Run make test to verify no existing tests break**

```bash
make test
```

Expected: all 89 tests pass, exit 0.

- [ ] **Step 5: Commit**

```bash
git add tests/mocks/brew tests/mocks/curl tests/mocks/pgrep
git commit -m "test: extend brew, curl, pgrep mocks with new env vars

brew: add per-subcommand exit codes for update/upgrade/cleanup
curl: add MOCK_CURL_STDOUT for command-substitution testing
pgrep: add MOCK_PGREP_OUTPUT to simulate returned PIDs

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 3: Add usage and mas tests

**Files:**

- Modify: `tests/setup_env/unit.bats`
- Modify: `tests/setup_env/extracted_functions.bats`

**Context:** `usage` prints a heredoc and calls `exit 0` — BATS `run` executes in a subshell so exit is captured as status. The mas test adds macOS coverage to `update_system_packages`, whose other platform tests already exist in `extracted_functions.bats`.

- [ ] **Step 1: Run existing unit.bats and extracted_functions.bats to confirm current counts**

```bash
bats tests/setup_env/unit.bats
bats tests/setup_env/extracted_functions.bats
```

Note how many tests pass (baselines for verifying new tests were added).

- [ ] **Step 2: Append usage test to tests/setup_env/unit.bats**

Append to the end of the file:

```bash
# ── usage ────────────────────────────────────────────────────────────────────

@test "usage prints help text and exits 0" {
  run usage
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"setup_user"* ]]
  [[ "$output" == *"setup"* ]]
  [[ "$output" == *"developer"* ]]
  [[ "$output" == *"ansible"* ]]
  [[ "$output" == *"update"* ]]
}
```

- [ ] **Step 3: Append mas test to tests/setup_env/extracted_functions.bats**

Append to the end of the file (after the existing `update_system_packages` tests):

```bash
@test "update_system_packages calls mas upgrade on macOS" {
  export MACOS=1
  unset UBUNTU REDHAT FEDORA CENTOS
  run update_system_packages
  [ "$status" -eq 0 ]
  grep -q "mas upgrade" "${MOCK_CALLS_FILE}"
}
```

- [ ] **Step 4: Run both files to verify new tests pass**

```bash
bats tests/setup_env/unit.bats
bats tests/setup_env/extracted_functions.bats
```

Expected: each file has one more passing test than the baseline.

- [ ] **Step 5: Run full suite**

```bash
make test
```

Expected: 91 tests pass.

- [ ] **Step 6: Commit**

```bash
git add tests/setup_env/unit.bats tests/setup_env/extracted_functions.bats
git commit -m "test: add usage and update_system_packages macOS tests

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 4: Add install_homebrew tests

**Files:**

- Modify: `tests/setup_env/install_functions.bats`

**Context:** `install_homebrew` in `setup_env.sh` (lines 116-154) checks `uname -s == Darwin`, runs `xcode-select --print-path` to detect Xcode, installs Xcode tools if absent, then runs `/bin/bash -c "$(curl -fsSL ...)"`. The uname mock is already in place. The xcode-select, xcodebuild mocks were added in Task 1. The curl MOCK_CURL_STDOUT was added in Task 2.

Key: `/bin/bash -c "$(curl ...)"` — when `MOCK_CURL_STDOUT` is empty, `/bin/bash -c ""` exits 0 (success). When `MOCK_CURL_STDOUT="exit 1"`, `/bin/bash -c "exit 1"` exits 1 (failure).

- [ ] **Step 1: Append 4 tests to tests/setup_env/install_functions.bats**

```bash
# ── install_homebrew ─────────────────────────────────────────────────────────

@test "install_homebrew skips xcode setup when xcode-select is already installed" {
  export MOCK_UNAME_S=Darwin
  export MOCK_XCODE_SELECT_PRINT_PATH_EXIT=0
  run install_homebrew
  [ "$status" -eq 0 ]
  [[ "$output" == *"Homebrew has been successfully installed"* ]]
  run grep -q "xcode-select --install" "${MOCK_CALLS_FILE}"
  [ "$status" -ne 0 ]
}

@test "install_homebrew installs xcode tools when not present" {
  export MOCK_UNAME_S=Darwin
  export MOCK_XCODE_SELECT_PRINT_PATH_EXIT=1
  export MOCK_XCODE_SELECT_EXIT=0
  export MOCK_XCODEBUILD_EXIT=0
  run install_homebrew
  [ "$status" -eq 0 ]
  grep -q "xcode-select --install" "${MOCK_CALLS_FILE}"
  grep -q "xcodebuild -license accept" "${MOCK_CALLS_FILE}"
}

@test "install_homebrew returns 1 when xcode-select --install fails" {
  export MOCK_UNAME_S=Darwin
  export MOCK_XCODE_SELECT_PRINT_PATH_EXIT=1
  export MOCK_XCODE_SELECT_EXIT=1
  run install_homebrew
  [ "$status" -eq 1 ]
  [[ "$output" == *"Failed to install Xcode Command Line Tools"* ]]
}

@test "install_homebrew returns 1 when brew install script fails" {
  # Use Linux to skip xcode block; test only the brew install failure path
  export MOCK_UNAME_S=Linux
  export MOCK_CURL_STDOUT="exit 1"
  run install_homebrew
  [ "$status" -eq 1 ]
  [[ "$output" == *"Failed to install Homebrew"* ]]
}
```

- [ ] **Step 2: Run install_functions.bats to verify all 4 new tests pass**

```bash
bats tests/setup_env/install_functions.bats
```

Expected: 4 new tests pass alongside the existing 18.

- [ ] **Step 3: Run full suite**

```bash
make test
```

Expected: 95 tests pass.

- [ ] **Step 4: Commit**

```bash
git add tests/setup_env/install_functions.bats
git commit -m "test: add install_homebrew tests for xcode and brew install paths

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 5: Add brew_update tests

**Files:**

- Modify: `tests/setup_env/install_guards.bats`

**Context:** `brew_update` (lines 156-191 of `setup_env.sh`) calls `ensure_not_root`, checks `command -v brew` (bash builtin, can't be PATH-mocked), then calls `brew update`, `brew upgrade`, `brew upgrade --cask --greedy`, `brew cleanup`. The "brew absent" test uses a subprocess with PATH surgery to exclude the brew mock AND any real brew from PATH, then verifies that `install_homebrew` was called (curl appears in MOCK_CALLS_FILE). The function's exit status is non-zero in this case (brew stays absent after install), but that's expected — we only assert the install_homebrew call.

- [ ] **Step 1: Append 4 tests to tests/setup_env/install_guards.bats**

```bash
# ── brew_update ──────────────────────────────────────────────────────────────

@test "brew_update returns 1 when running as root" {
  export MOCK_ID_U=0
  run brew_update
  [ "$status" -eq 1 ]
  [[ "$output" == *"Homebrew cannot run as root"* ]]
}

@test "brew_update calls install_homebrew when brew is absent" {
  export MOCK_ID_U=1000
  export MOCK_XCODE_SELECT_PRINT_PATH_EXIT=0
  # Build a filtered mocks dir without the brew mock
  local tmp_mocks="${BATS_TEST_TMPDIR}/mocks_no_brew"
  mkdir -p "${tmp_mocks}"
  for f in "${REPO_ROOT}/tests/mocks/"*; do
    [[ "$(basename "$f")" == "brew" ]] && continue
    ln -sf "$f" "${tmp_mocks}/$(basename "$f")"
  done
  # Build a PATH that excludes tests/mocks and any directory containing a real brew binary
  local clean_path
  clean_path="$(printf "%s" "${PATH}" | tr ':' '\n' | grep -v "tests/mocks" | tr '\n' ':' | sed 's/:$//')"
  clean_path="$(printf "%s" "${clean_path}" | tr ':' '\n' | while read -r dir; do
    [[ -x "${dir}/brew" ]] || printf "%s\n" "${dir}"
  done | tr '\n' ':' | sed 's/:$//')"
  run bash -c "
    export PATH='${tmp_mocks}:${clean_path}'
    export MOCK_CALLS_FILE='${MOCK_CALLS_FILE}'
    export MOCK_ID_U=1000
    export MOCK_XCODE_SELECT_PRINT_PATH_EXIT=0
    source '${REPO_ROOT}/setup_env.sh'
    brew_update
  "
  # Function exits non-zero (brew stays absent after install_homebrew) — only assert install was reached
  grep -q "curl" "${MOCK_CALLS_FILE}"
}

@test "brew_update returns 1 when brew update fails" {
  export MOCK_ID_U=1000
  export MOCK_BREW_UPDATE_EXIT=1
  run brew_update
  [ "$status" -eq 1 ]
  [[ "$output" == *"Failed to update Homebrew"* ]]
}

@test "brew_update runs full update sequence on success" {
  export MOCK_ID_U=1000
  run brew_update
  [ "$status" -eq 0 ]
  grep -q "brew update" "${MOCK_CALLS_FILE}"
  grep -q "brew upgrade" "${MOCK_CALLS_FILE}"
  grep -q "brew cleanup" "${MOCK_CALLS_FILE}"
  [[ "$output" == *"Homebrew update process completed successfully"* ]]
}
```

- [ ] **Step 2: Run install_guards.bats to verify all 4 new tests pass**

```bash
bats tests/setup_env/install_guards.bats
```

Expected: 4 new tests pass alongside the existing tests.

- [ ] **Step 3: Run full suite**

```bash
make test
```

Expected: 99 tests pass.

- [ ] **Step 4: Commit**

```bash
git add tests/setup_env/install_guards.bats
git commit -m "test: add brew_update tests for root check, absent brew, step failure, success

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 6: Create script-layer mocks (kill, tmux, rsync, hostname, sleep)

**Files:**

- Create: `tests/mocks/kill`
- Create: `tests/mocks/tmux`
- Create: `tests/mocks/rsync`
- Create: `tests/mocks/hostname`
- Create: `tests/mocks/sleep`

- [ ] **Step 1: Create tests/mocks/kill**

```bash
#!/usr/bin/env bash
printf "kill %s\n" "$*" >> "${MOCK_CALLS_FILE:-/tmp/mock_calls}"
exit "${MOCK_KILL_EXIT:-0}"
```

```bash
chmod +x tests/mocks/kill
```

- [ ] **Step 2: Create tests/mocks/tmux**

```bash
#!/usr/bin/env bash
printf "tmux %s\n" "$*" >> "${MOCK_CALLS_FILE:-/tmp/mock_calls}"
exit "${MOCK_TMUX_EXIT:-0}"
```

```bash
chmod +x tests/mocks/tmux
```

- [ ] **Step 3: Create tests/mocks/rsync**

```bash
#!/usr/bin/env bash
printf "rsync %s\n" "$*" >> "${MOCK_CALLS_FILE:-/tmp/mock_calls}"
exit "${MOCK_RSYNC_EXIT:-0}"
```

```bash
chmod +x tests/mocks/rsync
```

- [ ] **Step 4: Create tests/mocks/hostname**

```bash
#!/usr/bin/env bash
printf "hostname %s\n" "$*" >> "${MOCK_CALLS_FILE:-/tmp/mock_calls}"
if [[ "$1" == "-s" ]]; then
  printf "%s\n" "${MOCK_HOSTNAME_OUTPUT:-testhost}"
  exit 0
fi
exec /bin/hostname "$@"
```

```bash
chmod +x tests/mocks/hostname
```

- [ ] **Step 5: Create tests/mocks/sleep**

```bash
#!/usr/bin/env bash
printf "sleep %s\n" "$*" >> "${MOCK_CALLS_FILE:-/tmp/mock_calls}"
exit "${MOCK_SLEEP_EXIT:-0}"
```

```bash
chmod +x tests/mocks/sleep
```

- [ ] **Step 6: Run make test to verify no existing tests break**

```bash
make test
```

Expected: 99 tests pass, exit 0.

- [ ] **Step 7: Commit**

```bash
git add tests/mocks/kill tests/mocks/tmux tests/mocks/rsync tests/mocks/hostname tests/mocks/sleep
git commit -m "test: add kill, tmux, rsync, hostname, sleep mocks for scripts/unit.bats

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 7: Fix count_lines bugs using TDD

**Files:**

- Create: `tests/scripts/unit.bats` (initial version with count_lines tests only)
- Modify: `scripts/count_lines.sh`
- Modify: `scripts/count_lines_git.sh`

**Context:** Both scripts use `cmd | while read` which runs the loop in a subshell — `total_lines` accumulates inside the subshell and is discarded when the subshell exits. `shopt -s lastpipe` was intended to fix this but is unreliable across bash versions. Fix: replace the pipe with process substitution `while read -r f; do ...; done < <(cmd)` which runs the loop in the current shell.

For `count_lines_git.sh` tests: `git ls-files` needs a real git repo. Tests run `git` in a subprocess with the git mock excluded from PATH (since the mock outputs nothing).

- [ ] **Step 1: Create tests/scripts/unit.bats with count_lines tests**

```bash
#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_mocks
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
}

teardown() {
  rm -f "${MOCK_CALLS_FILE:-}"
}

# ── count_lines.sh ───────────────────────────────────────────────────────────

@test "count_lines.sh exits 1 and prints usage when no argument given" {
  run bash "${REPO_ROOT}/scripts/count_lines.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "count_lines.sh reports correct total line count" {
  local tmpdir="${BATS_TEST_TMPDIR}/testfiles"
  mkdir -p "${tmpdir}"
  printf "line1\nline2\nline3\n" > "${tmpdir}/file1.txt"
  printf "line1\nline2\n" > "${tmpdir}/file2.txt"
  run bash "${REPO_ROOT}/scripts/count_lines.sh" "${tmpdir}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Total lines: 5"* ]]
}

@test "count_lines.sh excludes files in the ignore directory" {
  local tmpdir="${BATS_TEST_TMPDIR}/testfiles2"
  mkdir -p "${tmpdir}/keep" "${tmpdir}/ignore"
  printf "line1\nline2\n" > "${tmpdir}/keep/file.txt"
  printf "line1\nline2\nline3\n" > "${tmpdir}/ignore/file.txt"
  run bash "${REPO_ROOT}/scripts/count_lines.sh" "${tmpdir}" "${tmpdir}/ignore"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Total lines: 2"* ]]
}

# ── count_lines_git.sh ───────────────────────────────────────────────────────

@test "count_lines_git.sh exits 1 and prints usage when no argument given" {
  run bash "${REPO_ROOT}/scripts/count_lines_git.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "count_lines_git.sh reports correct total line count for tracked files" {
  local tmpdir="${BATS_TEST_TMPDIR}/gitrepo"
  mkdir -p "${tmpdir}"
  # Use real git (exclude git mock from PATH so git ls-files works)
  local clean_path
  clean_path="$(printf "%s" "${PATH}" | tr ':' '\n' | grep -v "tests/mocks" | tr '\n' ':' | sed 's/:$//')"
  bash -c "
    export PATH='${clean_path}'
    git -C '${tmpdir}' init --quiet
    git -C '${tmpdir}' config user.email 'test@test.com'
    git -C '${tmpdir}' config user.name 'Test'
    printf 'line1\nline2\nline3\n' > '${tmpdir}/file1.txt'
    printf 'line1\nline2\n' > '${tmpdir}/file2.txt'
    git -C '${tmpdir}' add .
    git -C '${tmpdir}' commit --quiet -m 'test'
  "
  run bash -c "export PATH='${clean_path}'; bash '${REPO_ROOT}/scripts/count_lines_git.sh' '${tmpdir}'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Total lines: 5"* ]]
}

@test "count_lines_git.sh excludes files matching the ignore prefix" {
  local tmpdir="${BATS_TEST_TMPDIR}/gitrepo2"
  mkdir -p "${tmpdir}/keep" "${tmpdir}/vendor"
  local clean_path
  clean_path="$(printf "%s" "${PATH}" | tr ':' '\n' | grep -v "tests/mocks" | tr '\n' ':' | sed 's/:$//')"
  bash -c "
    export PATH='${clean_path}'
    git -C '${tmpdir}' init --quiet
    git -C '${tmpdir}' config user.email 'test@test.com'
    git -C '${tmpdir}' config user.name 'Test'
    printf 'line1\nline2\n' > '${tmpdir}/keep/file.txt'
    printf 'line1\nline2\nline3\n' > '${tmpdir}/vendor/file.txt'
    git -C '${tmpdir}' add .
    git -C '${tmpdir}' commit --quiet -m 'test'
  "
  run bash -c "export PATH='${clean_path}'; bash '${REPO_ROOT}/scripts/count_lines_git.sh' '${tmpdir}' 'vendor'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Total lines: 2"* ]]
}
```

- [ ] **Step 2: Run tests to verify they fail (expose the bug)**

```bash
bats tests/scripts/unit.bats
```

Expected: `count_lines.sh reports correct total line count` and `count_lines_git.sh reports correct total line count` FAIL with `Total lines: 0` rather than `Total lines: 5`. Usage and ignore tests may also fail since the file is new. The key failures are the total_lines tests.

- [ ] **Step 3: Fix scripts/count_lines.sh**

Replace the entire file with:

```bash
#!/usr/bin/env bash

# Check if a directory path is provided
if [ -z "$1" ]; then
  echo "Usage: $0 directory_path directory_path_to_ignore with no trailing slashes"
  exit 1
fi

dir_path="$1"
dir_ignore="$2"

total_lines=0

while read -r file
do
  lines=$(wc -l <"$file")
  total_lines=$((total_lines + lines))
  echo "$file has $lines lines"
done < <(find "$dir_path" -type d -path "$dir_ignore" -prune -o -type f -print)

echo "Total lines: $total_lines"
```

- [ ] **Step 4: Fix scripts/count_lines_git.sh**

Replace the entire file with:

```bash
#!/usr/bin/env bash

# Check if a directory path is provided
if [ -z "$1" ]; then
  echo "Usage: $0 directory_path directory_path_to_ignore with no trailing slashes"
  exit 1
fi

dir_path="$1"
dir_ignore="$2"

total_lines=0

while read -r file
do
  lines=$(wc -l <"$dir_path/$file")
  total_lines=$((total_lines + lines))
  echo "$file has $lines lines"
done < <(git -C "$dir_path" ls-files | grep -v "^$dir_ignore/")

echo "Total lines: $total_lines"
```

- [ ] **Step 5: Run tests to verify all 6 count_lines tests now pass**

```bash
bats tests/scripts/unit.bats
```

Expected: all 6 tests pass.

- [ ] **Step 6: Run full suite**

```bash
make test
```

Expected: 105 tests pass.

- [ ] **Step 7: Commit**

```bash
git add scripts/count_lines.sh scripts/count_lines_git.sh tests/scripts/unit.bats
git commit -m "fix: replace pipe with process substitution in count_lines scripts

The pipe | while pattern ran the loop in a subshell, causing total_lines
to always be 0. Process substitution < <(...) keeps the loop in the
current shell so the accumulator is preserved.

test: add tests/scripts/unit.bats with count_lines coverage

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 8: Write tests for remaining 6 scripts

**Files:**

- Modify: `tests/scripts/unit.bats`

**Context:** Scripts are invoked as `run bash "${REPO_ROOT}/scripts/foo.sh"`. Mocks (kill, tmux, rsync, hostname, sleep, pgrep, sudo) are loaded via `load_mocks` in setup. `html2ascii.sh` pipes stdin through sed/tr — no mocks needed. `synch_git-repos.sh` uses `hostname -s` which is intercepted by the hostname mock. `restart_fah.sh` calls `sudo /etc/init.d/FAHClient` — the updated sudo mock logs then exits 0 (FAHClient doesn't exist on dev machine). `tmux-workstation.sh` uses the tmux mock.

- [ ] **Step 1: Append remaining 6 scripts' tests to tests/scripts/unit.bats**

```bash
# ── html2ascii.sh ─────────────────────────────────────────────────────────────

@test "html2ascii.sh removes HTML tags from input" {
  run bash -c "printf '<p>hello</p>\n' | bash '${REPO_ROOT}/scripts/html2ascii.sh'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"hello"* ]]
  [[ "$output" != *"<p>"* ]]
}

@test "html2ascii.sh tokenizes on spaces (one token per line)" {
  run bash -c "printf 'hello world\n' | bash '${REPO_ROOT}/scripts/html2ascii.sh'"
  [ "$status" -eq 0 ]
  # Each word should be on its own line
  local line_count
  line_count=$(printf "%s\n" "$output" | grep -c ".")
  [ "$line_count" -ge 2 ]
}

@test "html2ascii.sh reads from a file argument" {
  local tmpfile="${BATS_TEST_TMPDIR}/test.html"
  printf "<b>bold</b> text\n" > "${tmpfile}"
  run bash "${REPO_ROOT}/scripts/html2ascii.sh" "${tmpfile}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"bold"* ]]
  [[ "$output" != *"<b>"* ]]
}

@test "html2ascii.sh exits 0" {
  run bash -c "printf 'hello\n' | bash '${REPO_ROOT}/scripts/html2ascii.sh'"
  [ "$status" -eq 0 ]
}

# ── kill_zombie.sh ─────────────────────────────────────────────────────────────

@test "kill_zombie.sh calls pgrep with defunct pattern" {
  run bash "${REPO_ROOT}/scripts/kill_zombie.sh"
  grep -q "pgrep <defunct>" "${MOCK_CALLS_FILE}"
}

@test "kill_zombie.sh calls kill -9" {
  run bash "${REPO_ROOT}/scripts/kill_zombie.sh"
  grep -q "kill -9" "${MOCK_CALLS_FILE}"
}

# ── mkill.sh ──────────────────────────────────────────────────────────────────

@test "mkill.sh calls pgrep with the provided pattern" {
  run bash "${REPO_ROOT}/scripts/mkill.sh" myprocess
  grep -q "pgrep myprocess" "${MOCK_CALLS_FILE}"
}

@test "mkill.sh calls sudo kill -9 for each returned pid" {
  export MOCK_PGREP_EXIT=0
  export MOCK_PGREP_OUTPUT="1234
5678"
  run bash "${REPO_ROOT}/scripts/mkill.sh" myprocess
  grep -q "kill -9 1234" "${MOCK_CALLS_FILE}"
  grep -q "kill -9 5678" "${MOCK_CALLS_FILE}"
}

# ── restart_fah.sh ─────────────────────────────────────────────────────────────

@test "restart_fah.sh calls FAHClient stop" {
  run bash "${REPO_ROOT}/scripts/restart_fah.sh"
  grep -q "sudo /etc/init.d/FAHClient stop" "${MOCK_CALLS_FILE}"
}

@test "restart_fah.sh calls FAHClient start" {
  run bash "${REPO_ROOT}/scripts/restart_fah.sh"
  grep -q "sudo /etc/init.d/FAHClient start" "${MOCK_CALLS_FILE}"
}

@test "restart_fah.sh calls pgrep fah between stop and start" {
  export MOCK_PGREP_EXIT=0
  export MOCK_PGREP_OUTPUT="4321"
  run bash "${REPO_ROOT}/scripts/restart_fah.sh"
  grep -q "pgrep fah" "${MOCK_CALLS_FILE}"
  grep -q "kill -9 4321" "${MOCK_CALLS_FILE}"
}

# ── synch_git-repos.sh ────────────────────────────────────────────────────────

@test "synch_git-repos.sh prints error message when not on studio" {
  export MOCK_HOSTNAME_OUTPUT=testhost
  run bash "${REPO_ROOT}/scripts/synch_git-repos.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"needs to be run on studio"* ]]
  run grep -q "rsync" "${MOCK_CALLS_FILE}"
  [ "$status" -ne 0 ]
}

@test "synch_git-repos.sh calls rsync for all three hosts when on studio" {
  export MOCK_HOSTNAME_OUTPUT=studio
  export HOME="${BATS_TEST_TMPDIR}"
  mkdir -p "${BATS_TEST_TMPDIR}/git-repos"
  run bash "${REPO_ROOT}/scripts/synch_git-repos.sh"
  [ "$status" -eq 0 ]
  grep -q "rsync.*laptop-1" "${MOCK_CALLS_FILE}"
  grep -q "rsync.*workstation" "${MOCK_CALLS_FILE}"
  grep -q "rsync.*ratna" "${MOCK_CALLS_FILE}"
}

# ── tmux-workstation.sh ───────────────────────────────────────────────────────

@test "tmux-workstation.sh creates exactly 5 tmux sessions" {
  run bash "${REPO_ROOT}/scripts/tmux-workstation.sh"
  local count
  count=$(grep -c "^tmux new" "${MOCK_CALLS_FILE}")
  [ "$count" -eq 5 ]
}

@test "tmux-workstation.sh uses correct session names" {
  run bash "${REPO_ROOT}/scripts/tmux-workstation.sh"
  grep -q "tmux new -s 'bpytop'" "${MOCK_CALLS_FILE}"
  grep -q "tmux new -s 'cyber1'" "${MOCK_CALLS_FILE}"
  grep -q "tmux new -s 'cyber2'" "${MOCK_CALLS_FILE}"
  grep -q "tmux new -s 'cone1'" "${MOCK_CALLS_FILE}"
  grep -q "tmux new -s 'cone2'" "${MOCK_CALLS_FILE}"
}
```

- [ ] **Step 2: Run tests/scripts/unit.bats to verify all 22 tests pass**

```bash
bats tests/scripts/unit.bats
```

Expected: all 22 tests pass.

- [ ] **Step 3: Run full suite**

```bash
make test
```

Expected: 120 tests pass (89 + 31 new), exit 0.

- [ ] **Step 4: Commit**

```bash
git add tests/scripts/unit.bats
git commit -m "test: add tests/scripts/unit.bats for all 8 scripts in scripts/

Covers html2ascii, kill_zombie, mkill, restart_fah, synch_git-repos,
tmux-workstation. Relies on updated sudo mock to handle absolute-path
commands and pgrep mock's MOCK_PGREP_OUTPUT for kill-loop testing.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 9: Update CLAUDE.md mock table

**Files:**

- Modify: `CLAUDE.md`

- [ ] **Step 1: Add 13 new rows to the mock env var table in CLAUDE.md**

In `CLAUDE.md` under `## Testing`, find the existing mock table and append these rows:

```markdown
| `MOCK_BREW_UPDATE_EXIT` | Exit code for `brew update` (default: 0) |
| `MOCK_BREW_UPGRADE_EXIT` | Exit code for `brew upgrade` and `brew upgrade --cask --greedy` (default: 0) |
| `MOCK_BREW_CLEANUP_EXIT` | Exit code for `brew cleanup` (default: 0) |
| `MOCK_CURL_STDOUT` | Content printed to stdout by `curl` mock (used for `$(curl ...)` substitution; default: empty) |
| `MOCK_XCODE_SELECT_PRINT_PATH_EXIT` | Exit code for `xcode-select --print-path` (default: 0 = already installed) |
| `MOCK_XCODE_SELECT_EXIT` | Exit code for `xcode-select --install` (default: 0) |
| `MOCK_XCODEBUILD_EXIT` | Exit code for `xcodebuild` (default: 0) |
| `MOCK_KILL_EXIT` | Exit code for `kill` (default: 0) |
| `MOCK_TMUX_EXIT` | Exit code for `tmux` (default: 0) |
| `MOCK_RSYNC_EXIT` | Exit code for `rsync` (default: 0) |
| `MOCK_HOSTNAME_OUTPUT` | Value returned by `hostname -s` (default: `testhost`) |
| `MOCK_SLEEP_EXIT` | Exit code for `sleep` (default: 0) |
| `MOCK_PGREP_OUTPUT` | PIDs printed to stdout by `pgrep` mock (default: empty; used to simulate found processes) |
```

- [ ] **Step 2: Run full test suite one final time**

```bash
make test
```

Expected: all 121 tests pass, exit 0.

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md mock table with 13 new mock env vars

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```
