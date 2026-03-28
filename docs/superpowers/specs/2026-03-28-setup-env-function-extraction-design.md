# setup_env.sh Function Extraction Design

**Date:** 2026-03-28
**Status:** Approved

## Goal

Extract the inline code blocks in `setup_env.sh` (lines 860–2522) into named functions within the same file. The main execution blocks become flat sequences of function calls. All new functions are defined before the `[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0` guard so they are available for unit testing.

## Scope

- **In scope:** Extract inline blocks in SETUP/SETUP_USER, SETUP/DEVELOPER, DEVELOPER/ANSIBLE, and UPDATE blocks into named functions; add BATS tests for functions containing real conditional logic
- **Out of scope:** Functions that are already extracted (e.g., `install_homebrew`, `brew_install_formula`, `setup_credential_directories`, `clone_or_update_dotfiles`); flat install lists with no branching logic; any changes to existing function behaviour

---

## Architecture

All 14 new functions are added to `setup_env.sh` in the existing functions section (before line 860). No new files are created. The main execution blocks (lines 912–2522) are replaced with flat sequences of function calls. Tests are added to `tests/setup_env/unit.bats` using the existing `load_mocks` + `MOCK_CALLS_FILE` pattern.

---

## Function Extraction Map

### Functions with tests

These contain real conditional logic with meaningful branches to verify:

| Function | Source lines | Logic |
|---|---|---|
| `ensure_dnf()` | 914–925 | Skips if dnf present; exits 1 if yum install fails |
| `install_cheatsh()` | 959–977 | Platform-conditional curl install; skips if already downloaded |
| `install_go_ubuntu()` | 1440–1615 | `case $GO_VER`: PPA path (≤1.20) vs wget/tar path (≥1.21); exits 1 on unknown version |
| `install_ruby()` | 2255–2281 | macOS vs Focal vs Jammy vs Noble each take different paths |
| `install_github_cli()` | 2283–2302 | Ubuntu uses apt+keyring; RHEL/Fedora uses dnf; macOS skips |
| `setup_ansible_venv()` | 2359–2403 | Skips pyenv install if version exists; skips venv if symlink correct; host-gated |
| `update_git_repos()` | 2477–2515 | `[[ -d ]]` guards for tfenv, omz, p10k, tpm, zsh-autosuggestions |
| `update_pip_packages()` | 2446–2474 | Host-gated; pyenv activation before pip upgrade |

### Functions without tests

Flat install lists or pure side effects — no branching logic worth unit testing:

| Function | Source lines | Why no tests |
|---|---|---|
| `setup_brewfile_symlink()` | 997–1004 | mkdir + rm + ln, no branching |
| `install_macos_casks()` | 1006–1344 | `app_dir_exists` + `brew_install_cask` list, all side effects |
| `install_ubuntu_packages()` | 1347–1438 | apt install from files + PowerShell `.deb` per version, all side effects |
| `install_rhel_packages()` | 1981–2122 | Flat `dnf install` list, all side effects |
| `install_centos_packages()` | 2124–2140 | Flat `yum install` list, all side effects |
| `install_developer_gems()` | 2304–2357 | `gem install` list under chruby/rbenv activation, all side effects |
| `clone_personal_repos()` | 2405–2431 | `git clone` with `[[ -d ]]` guards, trivial existence checks |
| `setup_vim_plug()` | 2215–2227 | mkdir + curl with `[[ ! -f ]]` guard, no branching |

---

## Main Block Shape After Extraction

```bash
if [[ ${SETUP} || ${SETUP_USER} ]]; then
  ensure_dnf
  if [[ -n ${MACOS} ]]; then install_rosetta; fi
  if [[ -n ${MACOS} ]] || [[ -n ${FEDORA} ]] || [[ -n ${CENTOS} ]]; then install_git; fi
  mkdir -p ${HOME}/software_downloads
  if [[ ${MACOS} || ${UBUNTU} || ${FEDORA} || ${CENTOS} ]]; then install_zsh; fi
  if [[ -n ${LINUX} ]]; then install_bats; fi
  mkdir -p ${HOME}/bin
  mkdir -p ${PERSONAL_GITREPOS}
  clone_or_update_dotfiles
  setup_dotfile_symlinks
  setup_zsh_as_default_shell
  install_cheatsh
  mkdir -p ${HOME}/.zsh.d
  if [[ ! -f ${HOME}/.zsh.d/_cht ]]; then
    curl https://cheat.sh/:zsh > ${HOME}/.zsh.d/_cht
  fi
  mkdir -p ${HOME}/go-work
fi

if [[ -n ${SETUP} ]] || [[ -n ${DEVELOPER} ]]; then
  setup_credential_directories
  if [[ -n ${MACOS} ]]; then setup_brewfile_symlink; fi
  if [[ -n ${MACOS} ]]; then install_macos_casks; fi
  if [[ -n ${UBUNTU} ]]; then install_ubuntu_packages; fi
  if [[ -n ${REDHAT} ]] || [[ -n ${FEDORA} ]]; then install_rhel_packages; fi
  if [[ -n ${CENTOS} ]]; then install_centos_packages; fi
  if [[ -n ${UBUNTU} ]]; then install_go_ubuntu; fi
  if [[ -n ${LINUX} ]]; then install_linux_infra_tools; fi
  install_aws_cli
  setup_vim_plug
fi

if [[ -n ${DEVELOPER} ]] || [[ -n ${ANSIBLE} ]]; then
  install_ruby
  install_github_cli
  install_developer_gems
  setup_ansible_venv
  clone_personal_repos
fi

if [[ -n ${UPDATE} ]]; then
  update_pip_packages
  update_git_repos
fi
```

---

## Section 1: New Tests — `tests/setup_env/unit.bats`

All tests use the existing `load_mocks` + `MOCK_CALLS_FILE` pattern. The file is sourced with `source setup_env.sh` (the guard at line 861 skips execution when sourced).

### `ensure_dnf()` — 3 tests

| # | Scenario | Setup | Assert |
|---|---|---|---|
| 1 | Skips install when dnf already present | dnf mock in PATH | `yum` not called |
| 2 | Runs yum update + yum install dnf when missing | `MOCK_WHICH_MISSING=dnf`; `REDHAT=1` | `yum update` and `yum install dnf` in `MOCK_CALLS_FILE` |
| 3 | Exits 1 when dnf install fails | `MOCK_WHICH_MISSING=dnf`; `MOCK_YUM_EXIT=1`; `REDHAT=1` | `status -eq 1` |

### `install_cheatsh()` — 3 tests

| # | Scenario | Setup | Assert |
|---|---|---|---|
| 1 | Downloads cht.sh when `~/bin` exists and not yet present | Create `$HOME/bin`; `UBUNTU=1` | curl called with cht.sh URL |
| 2 | Skips download when cht.sh already present | Create `$HOME/bin/cht.sh` | curl not called for cht.sh |
| 3 | Installs curl via apt on Ubuntu before downloading | `UBUNTU=1`; no pre-existing cht.sh | `apt install curl` logged before curl download |

### `install_go_ubuntu()` — 3 tests

| # | Scenario | Setup | Assert |
|---|---|---|---|
| 1 | Uses PPA path for Go ≤1.20 | `GO_VER=1.20` | `add-apt-repository` and `apt install golang-1.20-go` in `MOCK_CALLS_FILE` |
| 2 | Uses wget+tar path for Go ≥1.21 | `GO_VER=1.21`; no pre-existing download file | `wget` and `tar` logged |
| 3 | Exits 1 for unsupported Go version | `GO_VER=9.99` | `status -eq 1`; output contains "Unsupported Go version" |

### `install_ruby()` — 3 tests

| # | Scenario | Setup | Assert |
|---|---|---|---|
| 1 | Calls ruby-install with `--with-openssl-dir` on macOS | `MACOS=1`; no `~/.rubies/ruby-$RUBY_VER` dir | `ruby-install` called with `--with-openssl-dir` |
| 2 | Calls ruby-install without extra flags on Ubuntu Focal | `LINUX=1`; `UBUNTU=1`; `FOCAL=1` | `ruby-install $RUBY_VER` without `--with-openssl-dir` |
| 3 | Uses rbenv on Ubuntu Noble | `LINUX=1`; `UBUNTU=1`; `NOBLE=1` | `rbenv install` logged |

### `install_github_cli()` — 3 tests

| # | Scenario | Setup | Assert |
|---|---|---|---|
| 1 | Uses apt+keyring on Ubuntu | `LINUX=1`; `UBUNTU=1` | `apt install gh` in `MOCK_CALLS_FILE` |
| 2 | Uses dnf on RHEL | `LINUX=1`; `REDHAT=1` | `dnf install gh` logged |
| 3 | Does nothing when not Linux | `MACOS=1` (unset `LINUX`) | no package manager logged |

### `setup_ansible_venv()` — 3 tests

| # | Scenario | Setup | Assert |
|---|---|---|---|
| 1 | Skips pyenv python install when version dir already exists | Create `$HOME/.pyenv/versions/$PYTHON_VER` | no `pyenv install` in output |
| 2 | Skips venv creation when symlink already correct | Create symlink `$HOME/.pyenv/versions/ansible` → `$HOME/.pyenv/versions/$PYTHON_VER/envs/ansible` | no `pyenv virtualenv` logged |
| 3 | Creates venv when symlink absent and host var set | `LAPTOP=1`; pyenv mock in PATH; no symlink | `pyenv virtualenv` logged |

### `update_git_repos()` — 4 tests

| # | Scenario | Setup | Assert |
|---|---|---|---|
| 1 | Updates oh-my-zsh when dir exists | Create `$HOME/.oh-my-zsh` | `git pull` logged |
| 2 | Skips oh-my-zsh when dir absent | No `$HOME/.oh-my-zsh` | no `git pull` for that path |
| 3 | Updates tpm when dir exists | Create `$HOME/.tmux/plugins/tpm` | `git pull` logged |
| 4 | Skips tpm when dir absent | No dir | no `git pull` for that path |

### `update_pip_packages()` — 2 tests

| # | Scenario | Setup | Assert |
|---|---|---|---|
| 1 | Runs pip upgrade when host var set | `LAPTOP=1`; pyenv mock in PATH | `pip install -U` in `MOCK_CALLS_FILE` |
| 2 | Skips entirely when no host var set | No host var | no `pip` logged |

---

## Test Count

| File | Before | Added | After |
|---|---|---|---|
| `tests/setup_env/unit.bats` | existing | 24 | existing + 24 |
