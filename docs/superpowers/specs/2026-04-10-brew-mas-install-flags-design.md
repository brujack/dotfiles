# Design: Brew and MAS Install Flags for `-t setup`

**Date:** 2026-04-10
**Status:** Accepted

## Context

`./setup_env.sh -t setup` runs a full machine setup — dotfiles, symlinks, credential directories, brew installs, dev tooling, and more. There is no way to run just the brew or Mac App Store install steps without triggering the entire setup workflow. When brew packages or App Store apps need to be (re)installed on an existing machine, a full setup run is unnecessarily broad.

The update path (`-t update`) already supports granular flags (`--brew-only`, `--mas-only`) for upgrading packages. The same granularity is needed for the install path.

## Decision

Add two new flags to `-t setup`: `--brew-install` and `--mas-install`. Each short-circuits the full setup and runs only the targeted operation. Both flags can be combined in a single invocation.

This follows the existing pattern of standalone workflow functions dispatched from `setup_env.sh` (same as `doctor` and `check-versions`).

## Components

### 1. Flags and dispatch

`process_args()` in `lib/helpers.sh` gains two new long-option cases:

```bash
--brew-install)  readonly SETUP_BREW=1 ;;
--mas-install)   readonly SETUP_MAS=1 ;;
```

`setup_env.sh` gets two new dispatch lines placed before the existing `SETUP`/`SETUP_USER` lines, so they short-circuit full setup:

```bash
[[ -n ${SETUP_BREW:-} ]] && run_brew_install
[[ -n ${SETUP_MAS:-} ]]  && run_mas_install
[[ -n ${SETUP_BREW:-} || -n ${SETUP_MAS:-} ]] && exit 0
```

`usage()` in `lib/helpers.sh` is updated to document both flags under the setup description.

### 2. `run_brew_install()`

New function in `lib/workflows.sh`. Sets up the Brewfile symlink (required by `install_macos_casks`), ensures Homebrew is present, updates, installs all Brewfile packages, and cleans up:

```bash
run_brew_install() {
  mkdir -p "${BREWFILE_LOC}"
  rm -f "${BREWFILE_LOC}/Brewfile"
  ln -s "${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile" "${BREWFILE_LOC}/Brewfile"

  if ! command -v brew &>/dev/null; then
    install_homebrew
  fi
  brew_update
  brew_tap_if_missing homebrew/bundle
  install_macos_casks
  brew cleanup
}
```

`install_macos_casks` already handles profile-gated Brewfiles (`Brewfile.gui`, `Brewfile.devtools`) via `HAS_GUI`/`HAS_DEVTOOLS`, so capability-specific packages are included automatically.

### 3. `run_mas_install()`

New function in `lib/workflows.sh`. Runs `mas upgrade` to install/update all App Store apps. Guards against Linux and missing `mas` binary:

```bash
run_mas_install() {
  if [[ -z ${MACOS} ]]; then
    log_info "Skipping mas install — macOS only"
    return 0
  fi
  if ! command -v mas &>/dev/null; then
    log_error "mas not found — run --brew-install first"
    return 1
  fi
  log_info "Installing/updating Mac App Store apps"
  mas upgrade
}
```

The `mas` binary is installed via Homebrew, so `--brew-install` must be run before `--mas-install` on a fresh machine. The error message makes this dependency explicit.

## Data Flow

```
setup_env.sh -t setup --brew-install --mas-install
  └─ process_args() → SETUP=1, SETUP_BREW=1, SETUP_MAS=1
  └─ detect_env()
  └─ [[ -n SETUP_BREW ]] → run_brew_install()
       └─ mkdir BREWFILE_LOC
       └─ ln -s Brewfile
       └─ install_homebrew (if missing)
       └─ brew_update
       └─ brew_tap_if_missing homebrew/bundle
       └─ install_macos_casks → brew bundle (Brewfile, Brewfile.gui, Brewfile.devtools)
       └─ brew cleanup
  └─ [[ -n SETUP_MAS ]] → run_mas_install()
       └─ guard: macOS only
       └─ guard: mas installed
       └─ mas upgrade
  └─ { SETUP_BREW or SETUP_MAS } → exit 0  (full setup skipped)
```

## Error Handling

- `run_brew_install`: if `install_homebrew` fails, subsequent steps will fail naturally (brew not found)
- `run_mas_install`: returns 1 with a clear message if `mas` is not installed; returns 0 with a log message on Linux

## Testing

New tests added to existing `tests/setup_env/workflows.bats` and `tests/setup_env/unit.bats`.

**`process_args` tests** (`unit.bats`):

- `process_args sets SETUP_BREW when --brew-install is given`
- `process_args sets SETUP_MAS when --mas-install is given`

**`run_brew_install` tests** (`workflows.bats`):

- `run_brew_install installs homebrew when brew is missing`
- `run_brew_install calls brew update`
- `run_brew_install calls install_macos_casks`
- `run_brew_install calls brew cleanup`

**`run_mas_install` tests** (`workflows.bats`):

- `run_mas_install is a no-op on Linux`
- `run_mas_install fails when mas is not installed`
- `run_mas_install calls mas upgrade on macOS`

All tests use the existing mock infrastructure (`MOCK_CALLS_FILE`, `MOCK_WHICH_MISSING`).

## Related

- `lib/macos.sh`: `install_macos_casks()` — called by `run_brew_install`
- `lib/helpers.sh`: `brew_update()`, `brew_tap_if_missing()` — called by `run_brew_install`
- `lib/workflows.sh`: `run_update()` — parallel pattern for the update path
- ADR index: no new ADR required — this extends an existing structural pattern
