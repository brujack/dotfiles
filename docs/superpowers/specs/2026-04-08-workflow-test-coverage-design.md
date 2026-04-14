# Workflow Test Coverage Design

**Status:** Draft
**Date:** 2026-04-08

## Goal

Add behavioral test coverage for the four workflow functions in `lib/workflows.sh`. Currently only existence is tested. New tests assert which functions get called (coarse-grained) and that platform-specific branching works correctly (conditional branching).

## Architecture

New file `tests/setup_env/workflows.bats`. Uses existing mock infrastructure (`tests/mocks/`, `MOCK_CALLS_FILE`, `MOCK_UNAME_S`, etc.) — no new mocks required.

Each test sources `setup_env.sh` (which sources all of `lib/`), sets the appropriate vars (`SETUP_USER=1`, `MACOS=1`, etc.), calls the workflow function directly, and asserts against `MOCK_CALLS_FILE`.

## Test Structure

### Coarse-grained: top-level function calls

For each workflow function, verify that the expected top-level functions are called when run under the right conditions.

**`run_setup_user`** (with `MACOS=1`):

- `clone_or_update_dotfiles` called
- `setup_dotfile_symlinks` called
- `setup_zsh_as_default_shell` called
- `mkdir` called for `${HOME}/bin` and `${HOME}/go-work`

**`run_setup_or_developer`** (with `SETUP=1`, `MACOS=1`):

- `setup_credential_directories` called
- `brew_update` called
- `install_homebrew_packages` called (or `brew bundle`)

**`run_developer_or_ansible`** (with `DEVELOPER=1`):

- python virtualenv setup step called
- ansible install step called

**`run_update`** (with `UPDATE=1`, `MACOS=1`):

- `brew_update` called
- `gem update` called

### Conditional branching: platform-specific calls

Test that macOS-only and Linux-only code paths fire (or don't) based on `MOCK_UNAME_S` / OS vars.

**`run_setup_user` on macOS (`MACOS=1`):**

- `install_rosetta` called

**`run_setup_user` on Linux (`LINUX=1`, `UBUNTU=1`):**

- `install_rosetta` NOT called
- `install_bats` called

**`run_setup_or_developer` on macOS (`MACOS=1`):**

- `brew bundle` (or equivalent) called
- `apt-get` NOT called

**`run_setup_or_developer` on Linux (`LINUX=1`, `UBUNTU=1`):**

- `apt-get` called
- `brew` NOT called (or brew guard skipped)

**`run_update` on macOS (`MACOS=1`):**

- `brew_update` called
- `apt` NOT called

**`run_update` on Linux (`LINUX=1`, `UBUNTU=1`):**

- `apt` or `nala` called
- `brew` NOT called

## Mock Setup Pattern

```bash
setup() {
  load_mocks
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  touch "${MOCK_CALLS_FILE}"
  # Source setup_env.sh to load all functions
  source "${REPO_ROOT}/setup_env.sh"
}
```

For platform branching tests, set OS vars before calling the workflow function:

```bash
@test "run_setup_user calls install_rosetta on macOS" {
  export MACOS=1
  unset LINUX
  run_setup_user
  grep -q "install_rosetta" "${MOCK_CALLS_FILE}"
}
```

## Scope Limit

Tests assert that functions are _called_, not that their internals succeed. The install function internals are already covered by `install_guards.bats` and `install_functions.bats`. This avoids double-testing and keeps workflow tests focused on dispatch logic.

## Files Modified

| Action | File                                                                                           |
| ------ | ---------------------------------------------------------------------------------------------- |
| Create | `tests/setup_env/workflows.bats`                                                               |
| Modify | `Makefile` — ensure `test` target includes `workflows.bats` (verify it's already glob-matched) |
