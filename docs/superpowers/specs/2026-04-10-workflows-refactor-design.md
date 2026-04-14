# Workflows Refactor Design

## Context

`lib/workflows.sh` is 1,437 lines. `run_setup_or_developer()` spans ~844 lines (lines 84–928) with large platform-specific install blocks inlined directly. `run_developer_or_ansible()` spans ~205 lines (lines 1013–1218) with no unit tests. This makes both functions hard to read, test, and maintain.

## Decision

Split platform-specific install blocks out of `run_setup_or_developer()` into named functions in the appropriate platform lib files (`lib/macos.sh`, `lib/linux.sh`, `lib/developer.sh`). Split `run_developer_or_ansible()` into logical helpers in `lib/developer.sh` for testability. Both workflow functions become thin dispatchers.

## Consequences

- `run_setup_or_developer()` shrinks to ~30 lines
- `run_developer_or_ansible()` shrinks to ~15 lines
- Platform libs grow but each owns its own domain
- Fine-grained helpers enable ~15–20 new targeted tests

---

## Extracted Functions

### `lib/macos.sh` — new: `install_macos_packages()`

Absorbs the macOS block from `run_setup_or_developer`:

- Symlink Brewfile to `${BREWFILE_LOC}/Brewfile`
- Install or update Homebrew (`install_homebrew` or `brew_update`)
- `brew_tap_if_missing homebrew/bundle`
- `install_macos_casks`
- `brew cleanup`
- `sudo -H softwareupdate --install --all --verbose`
- `${HOME}/scripts/.osx.sh`

### `lib/linux.sh` — new: `install_ubuntu_packages()`

Absorbs the Ubuntu block from `run_setup_or_developer`:

- `sudo -H apt update`
- HWE kernel install + package list install (Focal/Jammy/Noble branches)
- `check_and_install_nala` + nala installs for Jammy/Noble
- Snap/workstation packages when `HAS_SNAP`
- pyenv install via curl
- PowerShell install (per Ubuntu version)
- Go install
- Docker install
- kubectl install
- Helm install
- Kind install
- GitHub CLI install
- Terraform/tflint/tfsec
- Vault
- Packer
- Nomad
- Consul
- Vagrant
- Additional tooling (yq, jq, etc.)

### `lib/linux.sh` — new: `install_rhel_packages()`

Absorbs the RHEL/Fedora block from `run_setup_or_developer`.

### `lib/linux.sh` — new: `install_centos_packages()`

Absorbs the CentOS block from `run_setup_or_developer`.

### `lib/linux.sh` — new: `install_linux_packages()`

Absorbs the cross-platform Linux block (tools installed regardless of distro).

### `lib/developer.sh` — new: `install_aws_tools()`

Absorbs AWS CLI install blocks for both macOS and Linux from `run_setup_or_developer`.

### `lib/linux.sh` — new: `setup_vim_plugins()`

Absorbs the vim plugin setup block (plug.vim install, existing plugged dir check).

### `lib/developer.sh` — new helpers from `run_developer_or_ansible()`

| Function                     | Responsibility                                               |
| ---------------------------- | ------------------------------------------------------------ |
| `install_ruby_tools()`       | ruby-install + chruby download/install on Linux              |
| `install_ruby()`             | ruby-install for target `RUBY_VER` (platform/distro-aware)   |
| `install_github_cli_linux()` | gh CLI install for Ubuntu and RHEL variants                  |
| `setup_kitchen()`            | chruby/rbenv activation, gem installs for test-kitchen suite |
| `setup_ansible()`            | pyenv Python install, ansible virtualenv create/activate     |
| `clone_personal_repos()`     | clone each personal git repo if missing                      |

---

## Workflow Functions After Refactor

### `run_setup_or_developer()` (~30 lines)

```bash
run_setup_or_developer() {
  setup_credential_directories

  if [[ -n ${MACOS} ]]; then
    install_macos_packages
  fi

  if [[ -n ${UBUNTU} ]]; then
    install_ubuntu_packages
  fi

  if [[ -n ${REDHAT} ]] || [[ -n ${FEDORA} ]]; then
    install_rhel_packages
  fi

  if [[ -n ${CENTOS} ]]; then
    install_centos_packages
  fi

  if [[ -n ${LINUX} ]]; then
    install_linux_packages
  fi

  install_aws_tools
  setup_vim_plugins
}
```

### `run_developer_or_ansible()` (~20 lines)

```bash
run_developer_or_ansible() {
  npm install json2yaml

  install_ruby_tools
  install_ruby
  if [[ -n ${LINUX} ]]; then
    install_github_cli_linux
  fi
  setup_kitchen
  setup_ansible
  clone_personal_repos
}
```

---

## Testing

New tests in `tests/setup_env/workflows.bats` for the `run_developer_or_ansible` helpers:

### `install_ruby_tools`

- Calls `wget` to download ruby-install on Linux
- Calls `wget` to download chruby on Linux (Focal/Jammy)
- Is a no-op on macOS (neither called)

### `install_ruby`

- Calls `ruby-install` when `~/.rubies/ruby-<VER>` is absent
- Skips when `~/.rubies/ruby-<VER>` already exists
- Calls `ruby-install` with `--with-openssl-dir` on macOS
- Calls `rbenv install` on Noble

### `setup_kitchen`

- Calls `gem install test-kitchen` on macOS
- Calls `gem install test-kitchen` on Linux Focal/Jammy
- Calls `rbenv install` path on Noble

### `setup_ansible`

- Calls `pyenv install` when Python version not present
- Creates ansible virtualenv when symlink absent
- Calls `pip install ansible` inside venv

### `clone_personal_repos`

- Calls `git clone` for each repo when directory absent
- Skips `git clone` for repos that already exist

### `install_github_cli_linux`

- Calls `apt install gh` on Ubuntu
- Calls `dnf install gh` on RHEL/Fedora
- Is a no-op on macOS

---

## Related

- `lib/workflows.sh` — `run_setup_or_developer`, `run_developer_or_ansible`
- `lib/macos.sh`, `lib/linux.sh`, `lib/developer.sh` — destination for extracted functions
- `tests/setup_env/workflows.bats` — new tests
