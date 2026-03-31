# Dotfiles Modularization Design

**Date:** 2026-03-31
**Status:** Approved

## Goal

Modularize `setup_env.sh` into focused `lib/*.sh` files, introduce a profile/capability system to replace hostname branching, add colored logging, harden idempotency, and enforce CI with auto-merge on feature branches. Zero user-facing behavior change throughout.

## Scope

- **In scope:** lib/ split, profile abstraction, logging helpers, safe symlinks, ShellCheck lint, GitHub Actions CI with auto-merge, branch workflow, docs update
- **Out of scope:** Rewriting bootstrap in another language, removing host-specific behavior, replacing package managers

---

## Phase Sequence

All phases run on feature branches. GitHub Actions validates → auto-merges to master on green.

| Phase | Name | Prerequisite |
|---|---|---|
| 0 | Function extraction | — (already planned at `docs/superpowers/plans/2026-03-28-setup-env-function-extraction.md`) |
| 1 | lib/ split | Phase 0 complete |
| 2 | Hardening (logging + safe_link) | Phase 1 complete |
| 3 | Profile abstraction | Phase 2 complete |
| 4 | CI + ShellCheck enforcement | Phase 1 complete (can run in parallel with 2–3) |
| 5 | Docs | Phases 2–4 complete |

---

## Architecture

### Repository Structure After Phase 3

```
setup_env.sh           # ~80-line orchestrator: sources lib/, parses args, dispatches workflows
config/
  profiles.sh          # hostname → profile map; edit here to add a new machine
lib/
  constants.sh         # version pins, download URLs, directory locations
  helpers.sh           # logging, install guards, safe_link, common utilities
  detect_env.sh        # OS/version detection + profile/capability resolution
  macos.sh             # all macOS-specific install functions
  linux.sh             # all Linux-specific install functions
  developer.sh         # cross-platform developer tooling (Ruby, Python, Ansible, etc.)
tests/
  setup_env/
    unit.bats          # pure logic tests
    install_guards.bats
    install_functions.bats
    extracted_functions.bats
    profiles.bats      # NEW: profile + capability resolution tests
  zshrc.d/
    unit.bats
  mocks/               # PATH-injected mock executables
  helpers/
    common.bash
.github/
  workflows/
    ci.yml             # lint + test + auto-merge
```

### `setup_env.sh` After Phase 1

```bash
#!/usr/bin/env bash
source "$(dirname "$0")/lib/constants.sh"
source "$(dirname "$0")/lib/helpers.sh"
source "$(dirname "$0")/lib/detect_env.sh"
source "$(dirname "$0")/lib/macos.sh"
source "$(dirname "$0")/lib/linux.sh"
source "$(dirname "$0")/lib/developer.sh"

[[ $# -eq 0 ]] && usage
process_args "$@"
detect_env

[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0

# SETUP_USER block
if [[ ${SETUP} || ${SETUP_USER} ]]; then
  ...
fi
# remaining workflow blocks
```

---

## Section 1: `config/profiles.sh`

Sourced by `lib/detect_env.sh`. Edit this file to add a new machine — no other file needs changing.

```bash
#!/usr/bin/env bash
# config/profiles.sh
# Add a new machine: add a hostname entry to resolve_profile() and
# add a capability entry to resolve_caps().
# Uses case statements (not associative arrays) for bash 3.2 compatibility
# (macOS ships bash 3.2).

resolve_profile() {
  local hostname="$1"
  case "${hostname}" in
    laptop)                echo "personal_laptop" ;;
    studio|reception)      echo "mac_workstation" ;;
    office|home-1)         echo "mac_mini" ;;
    workstation|cruncher)  echo "linux_workstation" ;;
    *)                     echo "unknown" ;;
  esac
}

resolve_caps() {
  local profile="$1"
  case "${profile}" in
    personal_laptop)    echo "gui devtools aws k8s docker rust printing" ;;
    mac_workstation)    echo "gui devtools aws k8s docker rust printing" ;;
    mac_mini)           echo "gui printing" ;;
    linux_workstation)  echo "gui devtools aws k8s docker rust" ;;
    server)             echo "devtools aws" ;;
    *)                  echo "" ;;
  esac
}
```

**Profile descriptions:**

| Profile | Machines | Description |
|---|---|---|
| `personal_laptop` | laptop | MacBook Pro, full dev workstation |
| `mac_workstation` | studio, reception | Mac Studio, full dev workstation |
| `mac_mini` | office, home-1 | Mac Mini, GUI apps only, no devtools |
| `linux_workstation` | workstation, cruncher | Linux, full dev including Docker + Rust |
| `server` | (future) | Headless Linux, devtools + AWS only |

---

## Section 2: `lib/detect_env.sh`

Moves the current inline detection block (lines 867–908 of `setup_env.sh`) into a `detect_env()` function, then adds profile resolution.

```bash
detect_env() {
  [[ $(uname -s) == "Darwin" ]] && readonly MACOS=1
  [[ $(uname -s) == "Linux" ]]  && readonly LINUX=1
  # ... existing OS/version detection ...

  # Profile resolution (sources config/profiles.sh for resolve_profile/resolve_caps)
  local hostname
  hostname=$(hostname -s)
  PROFILE="$(resolve_profile "${hostname}")"
  for cap in $(resolve_caps "${PROFILE}"); do
    declare -g "HAS_$(printf '%s' "$cap" | tr '[:lower:]' '[:upper:]')=1"
  done
}
```

**Capability vars set after `detect_env`:**

| Var | Set for profiles |
|---|---|
| `HAS_GUI` | personal_laptop, mac_workstation, mac_mini, linux_workstation |
| `HAS_DEVTOOLS` | personal_laptop, mac_workstation, linux_workstation |
| `HAS_AWS` | all except mac_mini |
| `HAS_K8S` | personal_laptop, mac_workstation, linux_workstation |
| `HAS_DOCKER` | personal_laptop, mac_workstation, linux_workstation |
| `HAS_RUST` | personal_laptop, mac_workstation, linux_workstation |
| `HAS_PRINTING` | personal_laptop, mac_workstation, mac_mini |

**Migration:** Existing `LAPTOP`, `STUDIO`, `WORKSTATION` etc. vars are preserved as aliases during Phase 3 migration (set from profile) so tests continue to pass. Removed in a follow-up cleanup commit once all call sites are updated.

---

## Section 3: `lib/helpers.sh`

### Logging

```bash
readonly _RED='\033[0;31m'
readonly _YELLOW='\033[0;33m'
readonly _GREEN='\033[0;32m'
readonly _NC='\033[0m'

log_info()  { printf "${_GREEN}[INFO]${_NC}  %s\n" "$*"; }
log_warn()  { printf "${_YELLOW}[WARN]${_NC}  %s\n" "$*" >&2; }
log_error() { printf "${_RED}[ERROR]${_NC} %s\n" "$*" >&2; }
```

All `printf "..."` calls in `lib/*.sh` are replaced with `log_info` during Phase 2. Error messages use `log_error`. Non-fatal warnings use `log_warn`.

### `safe_link()`

```bash
safe_link() {
  local src="$1" dest="$2"
  if [[ -L "${dest}" ]]; then
    return 0  # already a symlink, nothing to do
  fi
  if [[ -e "${dest}" ]]; then
    log_warn "Backing up existing file: ${dest} → ${dest}.bak"
    mv "${dest}" "${dest}.bak"
  fi
  ln -s "${src}" "${dest}"
  log_info "Linked ${dest} → ${src}"
}
```

Replaces all `rm -f + ln -s` patterns in `setup_dotfile_symlinks()`.

### Existing helpers that move here unchanged

`quiet_which`, `app_dir_exists`, `rhel_installed_package`, `brew_formula_installed`, `brew_cask_installed`, `brew_install_formula`, `brew_install_cask`, `brew_tap_if_missing`, `brew_update`, `check_and_install_nala`, `ensure_not_root`.

---

## Section 4: `lib/` File Responsibilities

| File | Contents |
|---|---|
| `lib/constants.sh` | Version pins (`GO_VER`, `PYTHON_VER`, etc.), download URLs, directory vars (`BREWFILE_LOC`, `PERSONAL_GITREPOS`, etc.) |
| `lib/helpers.sh` | Logging, `safe_link`, install guards, `quiet_which`, brew helpers, `usage`, `process_args` |
| `lib/detect_env.sh` | `detect_env()`: OS/version detection + profile resolution; sources `config/profiles.sh` |
| `lib/macos.sh` | `install_rosetta`, `install_git` (macOS), `setup_brewfile_symlink`, `install_macos_casks`, `setup_zsh_as_default_shell` (macOS) |
| `lib/linux.sh` | `ensure_dnf`, `install_bats`, `install_ubuntu_packages`, `install_rhel_packages`, `install_centos_packages`, `install_go_ubuntu`, `install_cheatsh`, `update_system_packages` |
| `lib/helpers.sh` (addition) | `setup_dotfile_symlinks` — single function with `if [[ -n ${MACOS} ]]` / `elif [[ -n ${LINUX} ]]` branches; lives in helpers since it is cross-platform |
| `lib/developer.sh` | `install_ruby`, `install_github_cli`, `install_developer_gems`, `setup_ansible_venv`, `update_pip_packages`, `clone_personal_repos`, `setup_vim_plug`, `update_aws_cli`, `update_rust`, `update_git_repos` |

---

## Section 5: GitHub Actions CI + Branch Workflow

### `.github/workflows/ci.yml`

```yaml
name: CI

on:
  push:
    branches-ignore: [master]

env:
  FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: true

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - name: Install bats
        run: sudo apt-get install -y bats shellcheck
      - name: Run tests
        run: make test

  auto-merge:
    needs: [test]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - name: Auto-merge to master
        run: gh pr merge --auto --merge "${{ github.ref_name }}"
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

### `make lint` updated

```makefile
lint:
    shellcheck $(SHELL_FILES)
    @failed=0; \
    for f in $(SHELL_FILES); do \
      bash -n "$$f" && printf "bash  OK  %s\n" "$$f" || { printf "bash FAIL %s\n" "$$f"; failed=1; }; \
      zsh  -n "$$f" && printf "zsh   OK  %s\n" "$$f" || { printf "zsh  FAIL %s\n" "$$f"; failed=1; }; \
    done; \
    exit $$failed
```

### Branch naming convention

```
phase/0-function-extraction
phase/1-lib-split
phase/2-hardening
phase/3-profile-abstraction
phase/4-ci-shellcheck
phase/5-docs
```

### One-time branch protection setup

```bash
gh api repos/{owner}/{repo}/branches/master/protection \
  --method PUT \
  --field required_status_checks='{"strict":true,"contexts":["test"]}' \
  --field enforce_admins=false \
  --field required_pull_request_reviews=null \
  --field restrictions=null
```

---

## Section 6: Testing Strategy

### Existing tests

All existing BATS tests carry forward unchanged. Function names are preserved during the lib/ split.

### New tests by phase

**Phase 1** — `tests/setup_env/unit.bats`: each `lib/*.sh` file sources without error.

**Phase 2** — `tests/setup_env/unit.bats`:
- `log_info` output contains `[INFO]` prefix
- `log_warn` output contains `[WARN]` prefix
- `log_error` output contains `[ERROR]` prefix

`tests/setup_env/install_guards.bats`:
- `safe_link` creates symlink when dest absent
- `safe_link` backs up existing file then creates symlink
- `safe_link` is a no-op when dest is already a correct symlink

**Phase 3** — new `tests/setup_env/profiles.bats`:
- `detect_env` sets `PROFILE=personal_laptop` for hostname `laptop`
- `detect_env` sets `PROFILE=mac_workstation` for hostname `studio`
- `detect_env` sets `PROFILE=mac_workstation` for hostname `reception`
- `detect_env` sets `PROFILE=mac_mini` for hostname `office`
- `detect_env` sets `PROFILE=unknown` for unrecognised hostname
- `HAS_DEVTOOLS` is set for `personal_laptop`
- `HAS_DEVTOOLS` is set for `mac_workstation`
- `HAS_DEVTOOLS` is unset for `mac_mini`
- `HAS_GUI` is set for all Mac profiles
- `HAS_DOCKER` is unset for `mac_mini`
- `HAS_PRINTING` is set for `mac_mini`

### `make test-unit` updated

```makefile
test-unit:
    bats tests/setup_env/unit.bats tests/setup_env/profiles.bats tests/zshrc.d/unit.bats
```

---

## Risks and Mitigations

| Risk | Mitigation |
|---|---|
| lib/ split breaks sourcing order (e.g., helpers used before they're defined) | Enforce strict source order in `setup_env.sh`; test each lib file sources independently |
| ShellCheck flags existing code that can't be changed | Add `# shellcheck disable=SCxxxx` inline with comment explaining why |
| Auto-merge merges a broken branch | CI must pass; branch protection blocks direct master pushes |
| Profile abstraction changes behavior for a machine | Keep legacy hostname vars as aliases until all call sites verified; one machine at a time |
| `declare -A` not available in bash 3.2 (macOS default) | Use `case` statements in `config/profiles.sh` instead of associative arrays — already reflected in design |
