# Bootstrap Tests Design

## Goal

Refactor `scripts/bootstrap_mac.sh` and `scripts/bootstrap_linux.sh` to follow ADR 0006 (sourcing guard, function extraction, `#!/usr/bin/env bash`, no `set -e`) and add comprehensive BATS tests covering all branches, error paths, and boundary cases.

## Architecture

Each bootstrap script is refactored into:
1. **Functions** — small, independently testable units extracted from the current linear script body
2. **Sourcing guard** — `[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0`
3. **Main orchestrator** — a `bootstrap_mac_main` / `bootstrap_linux_main` function that calls the extracted functions in order, with explicit error handling

Tests go in `tests/scripts/unit.bats` (existing file). All external commands are mocked via PATH injection using the established mock pattern.

## File Structure

| File | Change |
|---|---|
| `scripts/bootstrap_mac.sh` | Refactored — function extraction, shebang fix, remove `set -e`, add sourcing guard |
| `scripts/bootstrap_linux.sh` | Refactored — function extraction, remove `set -e`, add sourcing guard |
| `tests/scripts/unit.bats` | Modified — add tests for both bootstrap scripts |
| `tests/mocks/bash` | New — mock that returns configurable version string |

## bootstrap_mac.sh — Refactored Structure

```bash
#!/usr/bin/env bash

_bootstrap_check_macos() { ... }
_bootstrap_mac_install_homebrew() { ... }
_bootstrap_mac_setup_brew_path() { ... }
_bootstrap_mac_install_bash5() { ... }
bootstrap_mac_main() { ... }

[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0
bootstrap_mac_main
```

### Functions

**`_bootstrap_check_macos`**
- Checks `uname -s` == `Darwin`
- Returns 1 with error message if not macOS

**`_bootstrap_mac_install_homebrew`**
- If `command -v brew` succeeds: prints "already installed", returns 0
- Otherwise: runs `curl` + `/bin/bash` to install Homebrew
- Returns curl/install exit code on failure

**`_bootstrap_mac_setup_brew_path`**
- If `/opt/homebrew/bin/brew` exists: evals `brew shellenv`
- Otherwise: no-op (Intel Mac or brew not installed)

**`_bootstrap_mac_install_bash5`**
- Runs `bash --version` and extracts major version number
- If major version >= 5: prints "already installed", returns 0
- Otherwise: runs `brew install bash`
- Returns brew exit code on failure

**`bootstrap_mac_main`**
- Calls each function in order
- Each call uses `|| { log message; exit 1; }` for explicit error handling
- Prints completion message on success

## bootstrap_linux.sh — Refactored Structure

```bash
#!/usr/bin/env bash

_bootstrap_check_linux() { ... }
_bootstrap_linux_detect_distro() { ... }
_bootstrap_linux_install_prereqs() { ... }
_bootstrap_linux_install_homebrew() { ... }
_bootstrap_linux_setup_brew_path() { ... }
bootstrap_linux_main() { ... }

[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0
bootstrap_linux_main
```

### Functions

**`_bootstrap_check_linux`**
- Checks `uname -s` == `Linux`
- Returns 1 with error message if not Linux

**`_bootstrap_linux_detect_distro`**
- Sources `/etc/os-release` if it exists
- Sets `_DISTRO_FAMILY` to one of: `ubuntu`, `fedora`, `rhel`, `unknown`
- Detection logic: checks `ID` first, then `ID_LIKE` for matches

**`_bootstrap_linux_install_prereqs`**
- Takes `_DISTRO_FAMILY` as input (or reads it from the variable set by detect_distro)
- Ubuntu: `sudo apt-get update && sudo apt-get install -y build-essential curl file git procps`
- Fedora: `sudo dnf groupinstall -y "Development Tools" && sudo dnf install -y curl file git procps-ng`
- RHEL/CentOS: `sudo yum groupinstall -y "Development Tools" && sudo yum install -y curl file git procps-ng`
- Unknown: prints warning, returns 0 (non-fatal)

**`_bootstrap_linux_install_homebrew`**
- Same logic as mac variant: checks `command -v brew`, installs via curl if missing

**`_bootstrap_linux_setup_brew_path`**
- If `/home/linuxbrew/.linuxbrew/bin/brew` exists: evals `brew shellenv`
- Otherwise: no-op

**`bootstrap_linux_main`**
- Calls each function in order with explicit error handling
- Prints completion message on success

## New Mock: `tests/mocks/bash`

A mock for the `bash` command that supports version output:

```bash
#!/usr/bin/env bash
if [[ "$1" == "--version" ]]; then
  printf "GNU bash, version %s\n" "${MOCK_BASH_VERSION_OUTPUT:-5.2.0(1)-release}"
  exit 0
fi
printf "bash %s\n" "$*" >> "${MOCK_CALLS_FILE:-/tmp/mock_calls}"
exit "${MOCK_BASH_EXIT:-0}"
```

Controlled by `MOCK_BASH_VERSION_OUTPUT` (default: `5.2.0(1)-release`).

Note: this mock must only be used via explicit PATH in tests that need it — adding it to the global mock PATH would break BATS itself (which runs under bash). Tests that need this mock prepend a test-specific temp dir to PATH containing just the bash mock.

## Tests

All tests added to `tests/scripts/unit.bats`.

### bootstrap_mac.sh tests

| Test | What it verifies |
|---|---|
| `_bootstrap_check_macos` passes on Darwin | `MOCK_UNAME_S=Darwin`, returns 0 |
| `_bootstrap_check_macos` fails on Linux | `MOCK_UNAME_S=Linux`, returns 1, error message |
| `_bootstrap_mac_install_homebrew` skips when brew installed | no curl call in MOCK_CALLS_FILE |
| `_bootstrap_mac_install_homebrew` calls curl when brew missing | `MOCK_WHICH_MISSING=brew`, curl call logged |
| `_bootstrap_mac_install_homebrew` returns error when curl fails | `MOCK_CURL_EXIT=1`, returns non-zero |
| `_bootstrap_mac_install_bash5` skips when bash >= 5 | `MOCK_BASH_VERSION_OUTPUT=5.2.0(1)-release`, no `brew install bash` |
| `_bootstrap_mac_install_bash5` installs when bash < 5 | `MOCK_BASH_VERSION_OUTPUT=3.2.57(1)-release`, `brew install bash` called |
| `_bootstrap_mac_install_bash5` returns error when brew fails | `MOCK_BREW_INSTALL_EXIT=1`, returns non-zero |
| `bootstrap_mac_main` calls all functions in order | verify MOCK_CALLS_FILE has expected sequence |

### bootstrap_linux.sh tests

| Test | What it verifies |
|---|---|
| `_bootstrap_check_linux` passes on Linux | `MOCK_UNAME_S=Linux`, returns 0 |
| `_bootstrap_check_linux` fails on Darwin | `MOCK_UNAME_S=Darwin`, returns 1, error message |
| `_bootstrap_linux_detect_distro` detects Ubuntu | os-release with `ID=ubuntu`, `_DISTRO_FAMILY=ubuntu` |
| `_bootstrap_linux_detect_distro` detects Fedora | os-release with `ID=fedora`, `_DISTRO_FAMILY=fedora` |
| `_bootstrap_linux_detect_distro` detects RHEL via ID | os-release with `ID=rhel`, `_DISTRO_FAMILY=rhel` |
| `_bootstrap_linux_detect_distro` detects CentOS via ID_LIKE | os-release with `ID=centos ID_LIKE=rhel`, `_DISTRO_FAMILY=rhel` |
| `_bootstrap_linux_detect_distro` returns unknown for unrecognized distro | os-release with `ID=alpine`, `_DISTRO_FAMILY=unknown` |
| `_bootstrap_linux_detect_distro` handles missing os-release | no file, `_DISTRO_FAMILY=unknown` |
| `_bootstrap_linux_install_prereqs` calls apt-get for ubuntu | `_DISTRO_FAMILY=ubuntu`, `apt-get install` in MOCK_CALLS_FILE |
| `_bootstrap_linux_install_prereqs` calls dnf for fedora | `_DISTRO_FAMILY=fedora`, `dnf install` in MOCK_CALLS_FILE |
| `_bootstrap_linux_install_prereqs` calls yum for rhel | `_DISTRO_FAMILY=rhel`, `yum install` in MOCK_CALLS_FILE |
| `_bootstrap_linux_install_prereqs` prints warning for unknown | `_DISTRO_FAMILY=unknown`, warning in output |
| `_bootstrap_linux_install_prereqs` returns error when apt-get fails | `MOCK_APT_EXIT=1`, returns non-zero |
| `_bootstrap_linux_install_homebrew` skips when brew installed | no curl call |
| `_bootstrap_linux_install_homebrew` calls curl when brew missing | `MOCK_WHICH_MISSING=brew`, curl called |
| `bootstrap_linux_main` calls all functions in order | verify sequence |

## Test Seam

The `_bootstrap_linux_detect_distro` function needs to read `/etc/os-release`. In tests, this is redirected via an override variable:

| Seam | Used by | Effect |
|---|---|---|
| `_BOOTSTRAP_OS_RELEASE` | `_bootstrap_linux_detect_distro` | Path to os-release file; defaults to `/etc/os-release` |

## Error Handling

- Each function returns non-zero on failure (no `set -e`)
- `bootstrap_*_main` checks each return code: `_bootstrap_check_macos || exit 1`
- If a prerequisite install fails, the main function exits immediately with error message
- Homebrew install failure is fatal
- Unknown distro on Linux is a warning (non-fatal) — the user may have installed prerequisites manually
