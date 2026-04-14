# BATS Testing Infrastructure Design

**Date:** 2026-03-27
**Status:** Approved

## Overview

Add full BATS (Bash Automated Testing System) test coverage to the dotfiles repo. Replace the stale npm-managed bats install with native installation on macOS and Linux. Establish a Makefile-based test runner and a PATH-mock pattern for testing functions with side effects.

## BATS Installation

### macOS

Add `bats-core` to `Brewfile` as a formula. The existing `brew_install_formula` helper handles idempotency.

### Linux (Ubuntu)

Add `install_bats()` to `setup_env.sh`:

- Focal/Jammy/Noble: `sudo apt-get install -y bats`
- RHEL: curl the bats-core GitHub release tarball, extract, run `./install.sh /usr/local`
- Guarded with `if ! command -v bats &>/dev/null`
- Called in the `setup_user` block (available on all machine types)

### npm cleanup

- Remove `bats` from `package.json` devDependencies
- Remove `node_modules/bats/`
- Update `package-lock.json`

## Test Infrastructure Layout

```
dotfiles/
├── Makefile
├── tests/
│   ├── mocks/
│   │   ├── brew          # stub: records calls, configurable exit via MOCK_BREW_EXIT
│   │   └── apt-get       # stub: records calls, configurable exit via MOCK_APT_EXIT
│   ├── helpers/
│   │   └── common.bash   # load_mocks(), mock_macos(), mock_linux()
│   ├── setup_env/
│   │   ├── unit.bats           # pure logic tests
│   │   └── install_guards.bats # mocked side-effect tests
│   └── zshrc.d/
│       └── unit.bats           # sourcing/syntax tests
```

### Makefile targets

| Target           | Description                               |
| ---------------- | ----------------------------------------- |
| `make test`      | Run all tests (`bats tests/` recursively) |
| `make test-unit` | Run only `tests/*/unit.bats`              |
| `make help`      | List available targets                    |

### Mock pattern

Each test file sources `tests/helpers/common.bash` in `setup()`. `load_mocks()` prepends `tests/mocks/` to PATH for the duration of the test. Mock executables:

- Record invocation args to a temp file so tests can assert what was called
- Return exit code from an env var (e.g., `MOCK_BREW_EXIT=0` for success, `MOCK_BREW_EXIT=1` to simulate not-installed)

## Test Coverage

### `tests/setup_env/unit.bats` — pure logic, no mocks

- `quiet_which`: exits 0 for existing commands, 1 for missing
- `app_dir_exists`: exits 0/1 based on real tmpdir presence
- `process_args`: `-t setup/developer/update/ansible/setup_user` set correct flag vars; unknown args exit non-zero
- Version constants: all `*_VER` vars are non-empty and match semver pattern

### `tests/setup_env/install_guards.bats` — PATH-mocked

- `brew_formula_installed`: 0 when mock brew lists formula; 1 when not
- `brew_cask_installed`: same for casks
- `brew_install_formula`: mock brew called with `install <formula>` when absent; not called when present
- `brew_tap_if_missing`: `brew tap` called only when tap is absent
- `install_bats` (Linux): `apt-get install -y bats` called on Ubuntu; curl+install on RHEL

### `tests/zshrc.d/unit.bats` — sourcing tests

- Each of the 7 `.zshrc.d` files sources without error in a clean bash environment
- `1_init.zsh`: `MACOS`/`LINUX` vars set correctly based on mocked `uname` output

## CLAUDE.md Updates

The repo-level `CLAUDE.md` Testing section is expanded with:

- How to install BATS (macOS/Linux)
- `make test` as the standard run command
- Rules: every new/modified function needs a corresponding test
- Mock pattern documentation
- Requirement: `make test` exits 0 before committing

## Constraints

- No `set -euo pipefail` in setup_env.sh — tests must account for non-zero exits in conditional install paths
- Tests must not modify real system state — mocks only, always clean up tmpdir in `teardown()`
- BATS version used: whatever `bats-core` ships via brew/apt (currently 1.11.x) — no version pinning at the dotfiles level
