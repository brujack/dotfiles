# linux.sh Split — Design Spec

## Context

`lib/linux.sh` is 1046 lines. The core problem is `install_ubuntu_packages()` at 658 lines — a sequential monolith that installs ~15 distinct tools with no internal boundaries. This makes the file hard to navigate and the logic nearly impossible to test in isolation.

Goals:

- Split into smaller, focused files along OS-family lines
- Extract private per-tool helper functions from the Ubuntu monolith
- Achieve ≥90% line coverage across the new files

## Decision

Replace `lib/linux.sh` with three files sourced in the same order from `setup_env.sh`. No logic changes — pure structural refactor.

## File Structure

### `lib/linux_shared.sh` (~175 lines)

Cross-distro functions, unchanged from current `linux.sh`:

- `install_git_linux` — Ubuntu/CentOS/Fedora/RHEL git install
- `install_zsh_linux` — Ubuntu/CentOS/Fedora/RHEL zsh install
- `install_bats` — BATS install for Ubuntu/RHEL/generic
- `update_system_packages` — snap/dnf/yum/nala update dispatch

### `lib/linux_ubuntu.sh` (~450 lines)

`install_ubuntu_packages` becomes a ~30-line orchestrator calling 12 private helpers in sequence. Private helpers are not called by anything outside this file.

| Helper                          | Responsibility                                                                                            |
| ------------------------------- | --------------------------------------------------------------------------------------------------------- |
| `_install_ubuntu_base_packages` | apt update, hwe kernel, version-specific package lists (`ubuntu_common_packages.txt` etc.), snap packages |
| `_install_ubuntu_pyenv`         | curl + run pyenv installer script                                                                         |
| `_install_ubuntu_powershell`    | per-version (Bionic/Focal/Jammy/Noble) `.deb` download + dpkg install                                     |
| `_install_ubuntu_go`            | version-dispatch: apt PPA for ≤1.20, tarball install for ≥1.21                                            |
| `_install_ubuntu_rust`          | rustup install, guarded by `HAS_RUST`                                                                     |
| `_install_ubuntu_docker`        | docker-ce + plugins via apt, guarded by `HAS_DOCKER`                                                      |
| `_install_ubuntu_k8s_tools`     | kind, telepresence, kubectl, kustomize, helm (snap or apt depending on `HAS_SNAP`)                        |
| `_install_ubuntu_hashicorp`     | consul, vault, nomad, packer, vagrant via wget + unzip                                                    |
| `_install_ubuntu_cloud_tools`   | azure-cli, gcloud SDK, teleport, cloudflared, cf-terraforming                                             |
| `_install_ubuntu_brew_packages` | Homebrew install if missing, then `brew_install_formula` calls                                            |
| `_install_ubuntu_gui_tools`     | albert launcher, microsoft-edge — gated on `HAS_SNAP`; virtualbox — gated on `HAS_DEVTOOLS`               |
| `_install_ubuntu_misc`          | docker-compose, yq, .net SDK, glances, libssl1.1 fix, autoremove                                          |

Orchestrator shape:

```bash
install_ubuntu_packages() {
  _install_ubuntu_base_packages  || return 1
  _install_ubuntu_pyenv          || return 1
  _install_ubuntu_powershell     || return 1
  _install_ubuntu_go             || return 1
  _install_ubuntu_rust           || return 1
  _install_ubuntu_docker         || return 1
  _install_ubuntu_k8s_tools      || return 1
  _install_ubuntu_hashicorp      || return 1
  _install_ubuntu_cloud_tools    || return 1
  _install_ubuntu_brew_packages  || return 1
  _install_ubuntu_gui_tools      || return 1
  _install_ubuntu_misc           || return 1
}
```

### `lib/linux_rhel.sh` (~200 lines)

RHEL/CentOS functions, unchanged from current `linux.sh`:

- `install_rhel_packages`
- `install_centos_packages`
- `install_linux_packages`

### `setup_env.sh`

Replace line 46 (`source .../linux.sh`) with:

```bash
source "$(dirname "${BASH_SOURCE[0]}")/lib/linux_shared.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/linux_ubuntu.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/linux_rhel.sh"
```

Delete `lib/linux.sh`.

## Testing

Three test files replace `tests/setup_env/linux.bats`.

### `tests/setup_env/linux_shared.bats`

Existing tests from `linux.bats` move here, excluding `setup_vim_plugins` tests — that function lives in `developer.sh` and its tests belong in `tests/setup_env/developer.bats` (create if it doesn't exist). No new logic otherwise.

### `tests/setup_env/linux_ubuntu.bats`

For each `_install_ubuntu_*` helper:

- **Happy path:** correct commands called for relevant capability/version flags
- **Skip path:** helper is no-op when capability flag absent (`HAS_DOCKER` unset → no docker commands)
- **Idempotency:** tool already installed (download file exists, `command -v` finds binary) → install command not called
- **Error path:** underlying command fails → helper returns non-zero

### `tests/setup_env/linux_rhel.bats`

Tests for `install_rhel_packages`, `install_centos_packages`, `install_linux_packages`.

### Makefile

No change needed. `make test` uses `bats --recursive tests/` — new `.bats` files are auto-discovered.

### Coverage floor

≥90% line coverage across all three new files, matching the project standard.

## Migration Sequence

Each step is its own commit on a feature branch:

1. Create `lib/linux_shared.sh` — move four shared functions verbatim
2. Create `lib/linux_rhel.sh` — move three RHEL/CentOS functions verbatim
3. Create `lib/linux_ubuntu.sh` — extract 12 private helpers, write thin orchestrator
4. Update `setup_env.sh` — replace one source line with three
5. Delete `lib/linux.sh`
6. Rename/split test files; add tests for extracted helpers
7. Update `Makefile` if file list is explicit
8. Update `CLAUDE.md` layout section and `docs/superpowers/README.md`

## Constraints

- **No logic changes.** All conditionals, guards, and install commands are moved exactly as written. Logic fixes are a separate concern.
- **No behavior change.** `make test` must pass after every commit in the sequence.
- **Private helpers stay private.** `_install_ubuntu_*` functions are not exported or called from outside `linux_ubuntu.sh`.
