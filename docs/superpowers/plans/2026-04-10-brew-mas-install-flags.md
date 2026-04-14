# Brew and MAS Install Flags Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `--brew-install` and `--mas-install` flags to `-t setup` so brew and Mac App Store installs can be run without a full machine setup.

**Architecture:** Two new standalone workflow functions (`run_brew_install`, `run_mas_install`) in `lib/workflows.sh`, dispatched from `setup_env.sh` before the full setup path — same pattern as `doctor` and `check-versions`. Two new flags parsed in `process_args()`. Both functions use `quiet_which` (not `command -v`) for brew/mas presence checks so `MOCK_WHICH_MISSING` works in tests.

**Tech Stack:** bash, BATS, existing mock infrastructure (`tests/mocks/`, `MOCK_CALLS_FILE`, `MOCK_WHICH_MISSING`)

---

## Files

| File                             | Action | Purpose                                                                    |
| -------------------------------- | ------ | -------------------------------------------------------------------------- |
| `lib/helpers.sh`                 | Modify | Add `--brew-install`/`--mas-install` to `process_args()`; update `usage()` |
| `lib/workflows.sh`               | Modify | Add `run_brew_install()` and `run_mas_install()`                           |
| `setup_env.sh`                   | Modify | Add dispatch lines for `SETUP_BREW` and `SETUP_MAS`                        |
| `tests/setup_env/unit.bats`      | Modify | Tests for new `process_args` cases and updated `usage()`                   |
| `tests/setup_env/workflows.bats` | Modify | Tests for `run_brew_install()` and `run_mas_install()`                     |
| `docs/superpowers/README.md`     | Modify | Add entry for this plan, mark Done                                         |

---

## Task 1: process_args flags and usage

**Files:**

- Modify: `tests/setup_env/unit.bats` (after line 465, the existing `process_args sets multiple UPDATE flags` test)
- Modify: `lib/helpers.sh:200-222` (usage), `lib/helpers.sh:423-460` (process_args)

- [ ] **Step 1: Write the failing tests**

Add after the `process_args sets multiple UPDATE flags when multiple flags given` test in `tests/setup_env/unit.bats`:

```bash
@test "process_args sets SETUP_BREW for --brew-install" {
  process_args -t setup --brew-install
  [ "${SETUP_BREW}" -eq 1 ]
}

@test "process_args sets SETUP_MAS for --mas-install" {
  process_args -t setup --mas-install
  [ "${SETUP_MAS}" -eq 1 ]
}

@test "process_args sets both SETUP_BREW and SETUP_MAS when both flags given" {
  process_args -t setup --brew-install --mas-install
  [ "${SETUP_BREW}" -eq 1 ]
  [ "${SETUP_MAS}" -eq 1 ]
}
```

Also update the existing `usage prints help text and exits 0` test to include the new flags:

```bash
@test "usage prints help text and exits 0" {
  run usage
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"setup_user"* ]]
  [[ "$output" == *"setup"* ]]
  [[ "$output" == *"developer"* ]]
  [[ "$output" == *"ansible"* ]]
  [[ "$output" == *"update"* ]]
  [[ "$output" == *"--brew-install"* ]]
  [[ "$output" == *"--mas-install"* ]]
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
make test 2>&1 | grep "not ok"
```

Expected: 4 failures — `process_args sets SETUP_BREW`, `process_args sets SETUP_MAS`, `process_args sets both`, and `usage` flag checks.

- [ ] **Step 3: Implement — process_args in lib/helpers.sh**

In the long-option pre-processing loop (around line 428), add two cases after `--claude-only`:

```bash
      --brew-install)  readonly SETUP_BREW=1 ;;
      --mas-install)   readonly SETUP_MAS=1 ;;
```

The full loop should read:

```bash
  for _arg in "$@"; do
    case "${_arg}" in
      --dry-run)      readonly DRY_RUN=1 ;;
      --brew-only)    readonly UPDATE_BREW=1 ;;
      --pip-only)     readonly UPDATE_PIP=1 ;;
      --gems-only)    readonly UPDATE_GEMS=1 ;;
      --mas-only)     readonly UPDATE_MAS=1 ;;
      --claude-only)  readonly UPDATE_CLAUDE=1 ;;
      --brew-install) readonly SETUP_BREW=1 ;;
      --mas-install)  readonly SETUP_MAS=1 ;;
      *) _short_args+=("${_arg}") ;;
    esac
  done
```

- [ ] **Step 4: Implement — usage() in lib/helpers.sh**

Update the `setup` line and add entries to the Options section:

```bash
usage() {
  cat << EOF
Usage: $0 -t <type> [--dry-run] [-w]
Types:
  setup_user : Sets up a basic user environment for the current user
  setup      : Runs a full machine and developer setup
               Flags: --brew-install, --mas-install
  developer  : Runs a developer setup with packages and python virtual environment for running ansible
  ansible    : Just runs the ansible setup using a python virtual environment. Typically used after a python update
  update     : Does a system update of packages including brew packages
               Flags: --brew-only, --pip-only, --gems-only, --mas-only, --claude-only
  doctor     : Active health checks: symlinks, tools, credential dir permissions, version drift. Exits non-zero on failure
  check-versions : Compare pinned tool versions in lib/constants.sh against latest GitHub releases
Options:
  --dry-run       : Log mutating operations (symlinks, installs, mkdir) without executing them
  --brew-install  : (setup only) Ensure Homebrew is installed, update, and run brew bundle installs
  --mas-install   : (setup only) Install/update Mac App Store apps via mas (macOS only)
  --brew-only     : (update only) Update Homebrew formulae and casks only
  --pip-only      : (update only) Update pip packages only
  --gems-only     : (update only) Update Ruby gems only
  --mas-only      : (update only) Update Mac App Store apps only
  --claude-only   : (update only) Update Claude plugins only
  -w              : Optional -- Specify w for a redhat computer, sets up terraform 0.11 instead of default 0.12
EOF
  exit 0
}
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
make test 2>&1 | grep "not ok"
```

Expected: no output (all passing).

- [ ] **Step 6: Commit**

```bash
git add lib/helpers.sh tests/setup_env/unit.bats
git commit -m "feat: add --brew-install and --mas-install flags to process_args"
```

---

## Task 2: run_brew_install

**Files:**

- Modify: `tests/setup_env/workflows.bats` (add after last `run_update` test)
- Modify: `lib/workflows.sh` (add `run_brew_install()` before `run_update()`)

- [ ] **Step 1: Write the failing tests**

Add a new section at the end of `tests/setup_env/workflows.bats`:

```bash
# ── run_brew_install ──────────────────────────────────────────────────────────

@test "run_brew_install calls brew update" {
  export MACOS=1
  unset LINUX UBUNTU
  touch "${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile"
  run_brew_install
  grep -q "brew update" "${MOCK_CALLS_FILE}"
}

@test "run_brew_install calls brew bundle" {
  export MACOS=1
  unset LINUX UBUNTU
  touch "${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile"
  run_brew_install
  grep -q "brew bundle" "${MOCK_CALLS_FILE}"
}

@test "run_brew_install calls brew cleanup" {
  export MACOS=1
  unset LINUX UBUNTU
  touch "${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile"
  run_brew_install
  grep -q "brew cleanup" "${MOCK_CALLS_FILE}"
}

@test "run_brew_install calls install_homebrew when brew is missing" {
  export MACOS=1
  unset LINUX UBUNTU
  touch "${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile"
  export MOCK_WHICH_MISSING=brew
  run_brew_install 2>/dev/null || true
  grep -q "curl" "${MOCK_CALLS_FILE}"
}
```

> **Note on the brew-missing test:** `quiet_which brew` (used in the implementation) goes through the `which` mock, which respects `MOCK_WHICH_MISSING`. After `install_homebrew` runs, it calls `curl` to download the Homebrew installer — so `curl` appearing in `MOCK_CALLS_FILE` confirms `install_homebrew` was invoked. The mock `brew` is still in PATH for subsequent calls (`brew_update` etc.) so the function continues to completion.

- [ ] **Step 2: Run tests to verify they fail**

```bash
make test 2>&1 | grep "not ok"
```

Expected: 4 failures — all `run_brew_install` tests.

- [ ] **Step 3: Implement run_brew_install() in lib/workflows.sh**

Find `run_update()` in `lib/workflows.sh` and insert this function immediately before it:

```bash
run_brew_install() {
  mkdir -p "${BREWFILE_LOC}"
  rm -f "${BREWFILE_LOC}/Brewfile"
  ln -s "${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile" "${BREWFILE_LOC}/Brewfile"

  if ! quiet_which brew; then
    install_homebrew
  fi
  brew_update
  brew_tap_if_missing homebrew/bundle
  install_macos_casks
  brew cleanup
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
make test 2>&1 | grep "not ok"
```

Expected: no output (all passing).

- [ ] **Step 5: Commit**

```bash
git add lib/workflows.sh tests/setup_env/workflows.bats
git commit -m "feat: add run_brew_install workflow function"
```

---

## Task 3: run_mas_install

**Files:**

- Modify: `tests/setup_env/workflows.bats` (add after `run_brew_install` tests)
- Modify: `lib/workflows.sh` (add `run_mas_install()` after `run_brew_install()`)

- [ ] **Step 1: Write the failing tests**

Add after the `run_brew_install` tests in `tests/setup_env/workflows.bats`:

```bash
# ── run_mas_install ───────────────────────────────────────────────────────────

@test "run_mas_install calls mas upgrade on macOS" {
  export MACOS=1
  unset LINUX UBUNTU
  run_mas_install
  grep -q "mas upgrade" "${MOCK_CALLS_FILE}"
}

@test "run_mas_install is a no-op on Linux" {
  unset MACOS
  export LINUX=1
  export UBUNTU=1
  run run_mas_install
  [ "$status" -eq 0 ]
  ! grep -q "mas" "${MOCK_CALLS_FILE}"
}

@test "run_mas_install fails when mas is not installed" {
  export MACOS=1
  unset LINUX UBUNTU
  export MOCK_WHICH_MISSING=mas
  run run_mas_install
  [ "$status" -eq 1 ]
  [[ "$output" == *"mas not found"* ]]
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
make test 2>&1 | grep "not ok"
```

Expected: 3 failures — all `run_mas_install` tests.

- [ ] **Step 3: Implement run_mas_install() in lib/workflows.sh**

Add immediately after `run_brew_install()`:

```bash
run_mas_install() {
  if [[ -z ${MACOS} ]]; then
    log_info "Skipping mas install — macOS only"
    return 0
  fi
  if ! quiet_which mas; then
    log_error "mas not found — run --brew-install first"
    return 1
  fi
  log_info "Installing/updating Mac App Store apps"
  mas upgrade
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
make test 2>&1 | grep "not ok"
```

Expected: no output (all passing).

- [ ] **Step 5: Commit**

```bash
git add lib/workflows.sh tests/setup_env/workflows.bats
git commit -m "feat: add run_mas_install workflow function"
```

---

## Task 4: Dispatch and docs

**Files:**

- Modify: `setup_env.sh` (add dispatch lines before existing `SETUP`/`SETUP_USER` lines)
- Modify: `docs/superpowers/README.md` (add plan entry)

- [ ] **Step 1: Add dispatch lines to setup_env.sh**

The current dispatch section (around line 50) reads:

```bash
[[ -n ${DOCTOR:-} ]] && { run_doctor; exit $?; }
[[ -n ${CHECK_VERSIONS:-} ]] && { run_check_versions; exit $?; }

[[ -n ${SETUP_USER:-} || -n ${SETUP:-} ]] && run_setup_user
[[ -n ${SETUP:-} || -n ${DEVELOPER:-} ]] && run_setup_or_developer
[[ -n ${DEVELOPER:-} || -n ${ANSIBLE:-} ]] && run_developer_or_ansible
[[ -n ${UPDATE:-} ]] && run_update
```

Add the new lines after `run_check_versions` and before the `SETUP_USER` line:

```bash
[[ -n ${DOCTOR:-} ]] && { run_doctor; exit $?; }
[[ -n ${CHECK_VERSIONS:-} ]] && { run_check_versions; exit $?; }

[[ -n ${SETUP_BREW:-} ]] && run_brew_install
[[ -n ${SETUP_MAS:-} ]]  && run_mas_install
[[ -n ${SETUP_BREW:-} || -n ${SETUP_MAS:-} ]] && exit 0

[[ -n ${SETUP_USER:-} || -n ${SETUP:-} ]] && run_setup_user
[[ -n ${SETUP:-} || -n ${DEVELOPER:-} ]] && run_setup_or_developer
[[ -n ${DEVELOPER:-} || -n ${ANSIBLE:-} ]] && run_developer_or_ansible
[[ -n ${UPDATE:-} ]] && run_update
```

- [ ] **Step 2: Run make test to verify nothing broke**

```bash
make test 2>&1 | grep "not ok"
```

Expected: no output (all passing).

- [ ] **Step 3: Update docs/superpowers/README.md**

Add a new row to the All Plans table:

```
| 2026-04-10 | [brew-mas-install-flags](plans/2026-04-10-brew-mas-install-flags.md) | [spec](specs/2026-04-10-brew-mas-install-flags-design.md) | Done |
```

- [ ] **Step 4: Commit**

```bash
git add setup_env.sh docs/superpowers/README.md
git commit -m "feat: dispatch --brew-install and --mas-install flags in setup_env.sh"
```
