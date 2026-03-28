# Remaining Test Coverage Design

**Date:** 2026-03-28
**Status:** Approved

## Goal

Complete test coverage for the three remaining untested functions in `setup_env.sh`, add one missing platform test, fix two bugs in `scripts/`, and add BATS coverage for all eight scripts in `scripts/`.

## Scope

- **In scope:** Tests for `usage`, `brew_update`, `install_homebrew`; one additional `update_system_packages` test; bug fixes in `count_lines.sh` and `count_lines_git.sh`; `tests/scripts/unit.bats` for all 8 scripts; new mocks; CLAUDE.md mock table update
- **Out of scope:** Refactoring existing scripts, changing any function logic in `setup_env.sh`, adding tests for scripts outside `scripts/`

## Architecture

All tests use the existing BATS framework with PATH-based mock injection (`tests/mocks/` prepended to PATH). Scripts under `scripts/` are invoked directly (not sourced) since they are standalone executables. `setup_env.sh` functions continue to be tested via `load_setup_env` + function call pattern. Bug fixes use process substitution `< <(...)` to replace pipe-based while loops that suffer from subshell variable scoping.

---

## Section 1: setup_env.sh remaining gaps

### New mock env vars (additions to existing mocks)

| Variable | Mock | Effect |
|---|---|---|
| `MOCK_BREW_UPDATE_EXIT` | `brew` | Exit code for `brew update` (default: 0) |
| `MOCK_BREW_UPGRADE_EXIT` | `brew` | Exit code for `brew upgrade` (default: 0) |
| `MOCK_BREW_CLEANUP_EXIT` | `brew` | Exit code for `brew cleanup` (default: 0) |
| `MOCK_CURL_STDOUT` | `curl` | Content printed to stdout (used for `$(curl ...)` substitution; default: empty) |
| `MOCK_XCODE_SELECT_PRINT_PATH_EXIT` | `xcode-select` | Exit code for `xcode-select --print-path` (default: 0 = already installed) |
| `MOCK_XCODE_SELECT_EXIT` | `xcode-select` | Exit code for `xcode-select --install` (default: 0) |
| `MOCK_XCODEBUILD_EXIT` | `xcodebuild` | Exit code for `xcodebuild` (default: 0) |

### New mock files

- `tests/mocks/xcode-select` — logs call; returns `MOCK_XCODE_SELECT_PRINT_PATH_EXIT` for `--print-path`, `MOCK_XCODE_SELECT_EXIT` for `--install`, 0 otherwise
- `tests/mocks/xcodebuild` — logs call; returns `MOCK_XCODEBUILD_EXIT`

### Modified mock files

- `tests/mocks/brew` — extend to support `MOCK_BREW_UPDATE_EXIT` (for `brew update`), `MOCK_BREW_UPGRADE_EXIT` (for `brew upgrade` and `brew upgrade --cask --greedy`), `MOCK_BREW_CLEANUP_EXIT` (for `brew cleanup`)
- `tests/mocks/curl` — extend to print `MOCK_CURL_STDOUT` to stdout before exiting (empty by default; enables `$(curl -fsSL ...)` substitution to produce a controllable bash snippet)

### Tests added to existing files

**`tests/setup_env/unit.bats` — 1 new test**

```
@test "usage prints help text and exits 0"
  run usage
  [ "$status" -eq 0 ]
  assert output contains "Usage:", "setup_user", "setup", "developer", "ansible", "update"
```

**`tests/setup_env/extracted_functions.bats` — 1 new test**

```
@test "update_system_packages calls mas upgrade on macOS"
  export MACOS=1; unset UBUNTU REDHAT FEDORA CENTOS
  run update_system_packages
  grep -q "mas upgrade" MOCK_CALLS_FILE
```

**`tests/setup_env/install_guards.bats` — 4 new tests**

```
@test "brew_update returns 1 when running as root"
  MOCK_ID_U=0 → ensure_not_root returns 1 → brew_update returns 1

@test "brew_update calls install_homebrew when brew is absent"
  PATH surgery to hide brew mock → function calls install_homebrew
  (install_homebrew itself will succeed via xcode-select already-installed + empty curl stdout)

@test "brew_update returns 1 when brew update fails"
  MOCK_BREW_UPDATE_EXIT=1 → returns 1, prints failure message

@test "brew_update completes full update sequence on success"
  All brew mock exits default to 0 → brew update, upgrade, upgrade --cask, cleanup all called
```

**`tests/setup_env/install_functions.bats` — 4 new tests**

```
@test "install_homebrew skips xcode setup when xcode-select is already installed"
  MOCK_XCODE_SELECT_PRINT_PATH_EXIT=0 → no xcode-select --install call

@test "install_homebrew installs xcode tools when not present"
  MOCK_XCODE_SELECT_PRINT_PATH_EXIT=1 → xcode-select --install + xcodebuild called

@test "install_homebrew returns 1 when xcode-select --install fails"
  MOCK_XCODE_SELECT_PRINT_PATH_EXIT=1, MOCK_XCODE_SELECT_EXIT=1 → returns 1

@test "install_homebrew returns 1 when brew install script fails"
  MOCK_XCODE_SELECT_PRINT_PATH_EXIT=0, MOCK_CURL_STDOUT="exit 1" → bash -c "exit 1" → returns 1
```

---

## Section 2: Bug fixes + scripts tests

### Bug: total_lines always 0 in count_lines.sh and count_lines_git.sh

**Root cause:** `cmd | while read` runs the loop in a subshell. `shopt -s lastpipe` is unreliable across bash versions. `total_lines` incremented inside the loop is not visible after the loop.

**Fix:** Replace pipe with process substitution in both scripts:

```bash
# Before (count_lines.sh):
find "$dir_path" ... | while read -r file
do
  total_lines=$((total_lines + lines))
done
echo "Total lines: $total_lines"   # always 0

# After:
while read -r file
do
  total_lines=$((total_lines + lines))
done < <(find "$dir_path" ...)
echo "Total lines: $total_lines"   # correct
```

Same pattern for `count_lines_git.sh` (replace `git ls-files | grep | while` with process substitution).

### New mock files

| Mock | Env var | Default |
|---|---|---|
| `tests/mocks/kill` | `MOCK_KILL_EXIT` | 0 |
| `tests/mocks/tmux` | `MOCK_TMUX_EXIT` | 0 |
| `tests/mocks/rsync` | `MOCK_RSYNC_EXIT` | 0 |
| `tests/mocks/hostname` | `MOCK_HOSTNAME_OUTPUT` | `testhost` |
| `tests/mocks/sleep` | `MOCK_SLEEP_EXIT` | 0 |

All mocks log calls to `MOCK_CALLS_FILE`.

### New file: `tests/scripts/unit.bats`

Each script is invoked directly (e.g., `run bash scripts/count_lines.sh`) with `REPO_ROOT` and mocks loaded. `MOCK_CALLS_FILE` is set in setup.

**`count_lines.sh` — 3 tests**
1. Missing arg → prints usage, exits 1
2. With a temp directory of files → total_lines is correct (verifies the fix)
3. Ignore pattern excludes matching subdirectory

**`count_lines_git.sh` — 3 tests**
1. Missing arg → prints usage, exits 1
2. With a temp git-tracked file set → total_lines is correct (verifies the fix)
3. Ignore path pattern filters correctly

**`html2ascii.sh` — 4 tests**
1. Removes HTML tags (e.g., `<p>hello</p>` → `hello`)
2. Replaces `&aring;` and other character entities with correct characters
3. Tokenizes on spaces (one token per output line)
4. Reads from file argument (not just stdin)

**`kill_zombie.sh` — 2 tests**
1. Calls `pgrep` with `<defunct>` pattern
2. Calls `kill -9` with pids returned by pgrep

**`mkill.sh` — 2 tests**
1. Calls `pgrep` with the provided pattern argument
2. Calls `sudo kill -9` for each returned pid

**`restart_fah.sh` — 3 tests**
1. Calls `sudo ... FAHClient stop` before kill loop
2. Calls `sudo ... FAHClient start` after kill loop
3. Calls `pgrep fah` and `kill -9` between stop and start

**`synch_git-repos.sh` — 2 tests**
1. Non-studio hostname → prints "needs to be run on studio", no rsync calls
2. Studio hostname (`MOCK_HOSTNAME_OUTPUT=studio`) → rsync called for all three hosts (laptop-1, workstation, ratna)

**`tmux-workstation.sh` — 2 tests**
1. Creates exactly 5 tmux sessions
2. Session names are: bpytop, cyber1, cyber2, cone1, cone2

### CLAUDE.md mock table update

Add 12 new rows for: `MOCK_BREW_UPDATE_EXIT`, `MOCK_BREW_UPGRADE_EXIT`, `MOCK_BREW_CLEANUP_EXIT`, `MOCK_CURL_STDOUT`, `MOCK_XCODE_SELECT_PRINT_PATH_EXIT`, `MOCK_XCODE_SELECT_EXIT`, `MOCK_XCODEBUILD_EXIT`, `MOCK_KILL_EXIT`, `MOCK_TMUX_EXIT`, `MOCK_RSYNC_EXIT`, `MOCK_HOSTNAME_OUTPUT`, `MOCK_SLEEP_EXIT`.

---

## Test count projection

| File | Before | Added | After |
|---|---|---|---|
| `tests/setup_env/unit.bats` | existing | +1 | +1 |
| `tests/setup_env/extracted_functions.bats` | 21 | +1 | 22 |
| `tests/setup_env/install_guards.bats` | existing | +4 | +4 |
| `tests/setup_env/install_functions.bats` | existing | +4 | +4 |
| `tests/scripts/unit.bats` | 0 | +22 | 22 |
| **Total new** | | **+32** | |
| **Grand total** | **89** | | **~121** |

## Coverage after this plan

| Function/Script | Status |
|---|---|
| `usage` | tested |
| `update_system_packages` (macOS) | tested |
| `brew_update` | tested |
| `install_homebrew` | tested |
| `count_lines.sh` | fixed + tested |
| `count_lines_git.sh` | fixed + tested |
| `html2ascii.sh` | tested |
| `kill_zombie.sh` | tested |
| `mkill.sh` | tested |
| `restart_fah.sh` | tested |
| `synch_git-repos.sh` | tested |
| `tmux-workstation.sh` | tested |
