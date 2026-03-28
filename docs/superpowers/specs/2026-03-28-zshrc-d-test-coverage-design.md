# zshrc.d Test Coverage Design

**Date:** 2026-03-28
**Status:** Approved

## Goal

Expand `tests/zshrc.d/` from 10 syntax/smoke tests to 43 tests by adding behavioural coverage for `2_functions.zsh`, `5_general.zsh`, `6_path.zsh`, and `7_final.zsh`.

## Scope

- **In scope:** New test files for `2_functions.zsh`, `5_general.zsh`, `6_path.zsh`, `7_final.zsh`; bug fix for `mkill()` `exit 1` → `return 1`
- **Out of scope:** Tests for aliases (`4_aliases.zsh`), Oh-My-Zsh/completion sourcing in `5_general.zsh`, external-service paths in `awsuse`/`tssh`/`rssh`/`sh`/`sshu` (only arg-validation tested)

---

## File Structure

```
tests/zshrc.d/
├── unit.bats        # existing — syntax checks + 1_init.zsh functional tests (10 tests, unchanged)
├── functions.bats   # new — 2_functions.zsh (13 tests)
├── general.bats     # new — 5_general.zsh (6 tests)
├── path.bats        # new — 6_path.zsh (8 tests)
└── final.bats       # new — 7_final.zsh (6 tests)
```

---

## Bug Fix

### `mkill()` uses `exit 1` instead of `return 1`

**File:** `.devcontainer/.config/.zshrc.d/2_functions.zsh`

**Root cause:** The no-args guard uses `exit 1`, which kills the entire interactive shell session when the function is called without arguments.

**Fix:**
```zsh
# Before
if [ $# -eq 0 ]; then
  echo "Please provide the name of the process to kill as an argument."
  exit 1
fi

# After
if [ $# -eq 0 ]; then
  echo "Please provide the name of the process to kill as an argument."
  return 1
fi
```

---

## Section 1: `tests/zshrc.d/functions.bats` — 13 tests

All tests source `2_functions.zsh` inside a `zsh -c` subprocess with mock commands injected via `PATH`.

### `Make()` — 4 tests

| # | Test | Setup | Assert |
|---|------|-------|--------|
| 1 | Uses `task` when `Taskfile.yml` exists | Create `Taskfile.yml` in `$BATS_TEST_TMPDIR`; `cd` there; mock `task` | `task` called |
| 2 | Uses `task` when `Taskfile.yaml` exists | Create `Taskfile.yaml` in `$BATS_TEST_TMPDIR`; `cd` there; mock `task` | `task` called |
| 3 | Uses `gmake` when no Taskfile and `gmake` in PATH | No Taskfile; mock `gmake` in PATH | `gmake` called |
| 4 | Falls back to `make` when no Taskfile and no `gmake` | No Taskfile; no `gmake` mock | `make` called |

### `quiet_which()` — 3 tests

| # | Test | Assert |
|---|------|--------|
| 1 | Returns 1 and prints usage when no args | `status -eq 1`; output contains "Usage" |
| 2 | Returns 0 when command exists | `status -eq 0` |
| 3 | Returns 1 when command does not exist | `status -eq 1` |

### `mkill()` — 2 tests

| # | Test | Setup | Assert |
|---|------|-------|--------|
| 1 | Returns 1 and prints message when no args | — | `status -eq 1`; output contains "Please provide" |
| 2 | Prints "not running" when process not found | Mock `pgrep` returns 1 | output contains "not running" |

### `findStringInFile()` — 2 tests

| # | Test | Assert |
|---|------|--------|
| 1 | Prints error when no file arg | output contains "No file supplied" |
| 2 | Prints error when no string arg | output contains "No string supplied" |

### Arg-validation for external-call functions — 4 tests (1 each)

| # | Function | Assert |
|---|----------|--------|
| 1 | `tssh()` | `status -eq 1`; output contains "No arguments" |
| 2 | `sh()` | `status -eq 1`; output contains "No arguments" |
| 3 | `sshu()` | `status -eq 1`; output contains "No arguments" |
| 4 | `search_pkg()` | `status -eq 1`; output contains "No arguments" |

---

## Section 2: `tests/zshrc.d/general.bats` — 6 tests

All tests source `5_general.zsh` inside a `zsh -c` subprocess. Platform variables (`MACOS`, `LINUX`) and `SSH_CONNECTION` are set/unset before sourcing. The sourcing call uses `2>/dev/null` to suppress errors from optional `source` statements for files that don't exist on the test machine.

### `EDITOR` / `GIT_EDITOR` — 3 tests

| # | Test | Setup | Assert |
|---|------|-------|--------|
| 1 | Sets `EDITOR=vim` on Linux | `LINUX=1`; unset `SSH_CONNECTION` | `EDITOR=vim`; `GIT_EDITOR=vim` |
| 2 | Sets `EDITOR=code` on macOS without SSH | `MACOS=1`; unset `SSH_CONNECTION` | `EDITOR=code`; `GIT_EDITOR=code` |
| 3 | Sets `EDITOR=vim` on macOS when SSH | `MACOS=1`; `SSH_CONNECTION=1` | `EDITOR=vim`; `GIT_EDITOR=vim` |

### `PSHOME` — 2 tests

| # | Test | Setup | Assert |
|---|------|-------|--------|
| 4 | Sets `PSHOME` on macOS | `MACOS=1` | `PSHOME=/usr/local/microsoft/powershell/7/` |
| 5 | Sets `PSHOME` on Linux | `LINUX=1` | `PSHOME=/opt/microsoft/powershell/7/` |

### `ANSIBLEUSER` — 1 test

| # | Test | Assert |
|---|------|--------|
| 6 | Sets `ANSIBLEUSER=ubuntu` always | `ANSIBLEUSER=ubuntu` |

---

## Section 3: `tests/zshrc.d/path.bats` — 8 tests

All tests source `6_path.zsh` inside a `zsh -c` subprocess. Tests create real temporary directories under `$BATS_TEST_TMPDIR` and override `HOME` to point there, so existence checks (`-d`) work correctly without touching the real filesystem.

| # | Test | Setup | Assert |
|---|------|-------|--------|
| 1 | Adds `~/bin` to PATH when it exists | Create `$HOME/bin` | PATH contains `$HOME/bin` |
| 2 | Does not add `~/bin` when absent | Do not create `$HOME/bin` | PATH does not contain `$HOME/bin` |
| 3 | Adds `~/scripts` to PATH when it exists | Create `$HOME/scripts` | PATH contains `$HOME/scripts` |
| 4 | Adds `/opt/homebrew/bin` on macOS when present | `MACOS=1`; `/opt/homebrew/bin` exists on the dev machine | PATH contains `/opt/homebrew/bin` |
| 5 | Does not add `/opt/homebrew/bin` on Linux | `LINUX=1`; unset `MACOS` | PATH does not contain `/opt/homebrew/bin` |
| 6 | Adds `~/.cargo/bin` when present | Create `$HOME/.cargo/bin` | PATH contains it |
| 7 | Adds `/home/linuxbrew/.linuxbrew/bin` on Linux when present | `LINUX=1`; create dir | PATH contains it |
| 8 | PATH contains no duplicates after sourcing twice | Source `6_path.zsh` twice | No duplicate entries in PATH |

---

## Section 4: `tests/zshrc.d/final.bats` — 6 tests

All tests source `7_final.zsh` inside a `zsh -c` subprocess. `quiet_which` (called by `7_final.zsh` via `zoxide` check) is stubbed to return 1 so `eval "$(zoxide init zsh)"` and `eval "$(starship init zsh)"` are skipped cleanly.

### `GOROOT` / `GOPATH` — 4 tests

| # | Test | Setup | Assert |
|---|------|-------|--------|
| 1 | Sets `GOROOT` when `/usr/local/go` exists | Create dir stub | `GOROOT=/usr/local/go` |
| 2 | Does not set `GOROOT` when absent | No dir | `GOROOT` unset |
| 3 | Sets `GOPATH` when `~/go-work` exists | Create `$HOME/go-work` | `GOPATH=$HOME/go-work` |
| 4 | Does not set `GOPATH` when absent | No dir | `GOPATH` unset |

### `ICON` — 2 tests

| # | Test | Setup | Assert |
|---|------|-------|--------|
| 5 | Sets macOS icon on macOS | `MACOS=1` | `ICON=` |
| 6 | Sets Ubuntu icon on Linux | `LINUX=1`; mock `/etc/os-release` with `ID=ubuntu` | `ICON=` |

---

## Test Count Projection

| File | Before | Added | After |
|------|--------|-------|-------|
| `tests/zshrc.d/unit.bats` | 10 | 0 | 10 |
| `tests/zshrc.d/functions.bats` | 0 | 13 | 13 |
| `tests/zshrc.d/general.bats` | 0 | 6 | 6 |
| `tests/zshrc.d/path.bats` | 0 | 8 | 8 |
| `tests/zshrc.d/final.bats` | 0 | 6 | 6 |
| **Total** | **10** | **33** | **43** |
