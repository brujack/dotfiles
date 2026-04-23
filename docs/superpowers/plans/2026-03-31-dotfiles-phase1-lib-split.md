# Phase 1: lib/ Split Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split `setup_env.sh` into focused `lib/*.sh` files, reducing `setup_env.sh` to an ~80-line orchestrator that sources the lib files and dispatches workflows. Zero behavior change.

**Architecture:** Six lib files each with one responsibility, sourced in dependency order by `setup_env.sh`. All function names are preserved during the move so existing BATS tests continue to pass — tests source `setup_env.sh` which now sources lib/, so they get all functions via the chain. Each lib file can also be sourced independently. `setup_dotfile_symlinks` and `setup_credential_directories` live in `lib/helpers.sh` (cross-platform, OS branches inside them). The `detect_env()` function wraps the inline OS/version/hostname detection block that currently lives in the main execution area.

**Tech Stack:** Bash, BATS, `tests/mocks/` PATH-injection pattern

---

## Files

| File                        | Action                                                                                                                                                                                                                                                                                                                                                       |
| --------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `lib/constants.sh`          | Create — version pins, download URLs, directory vars (from lines 3–57 of `setup_env.sh`)                                                                                                                                                                                                                                                                     |
| `lib/helpers.sh`            | Create — `quiet_which`, `rhel_installed_package`, `brew_formula_installed`, `brew_cask_installed`, `brew_install_formula`, `brew_install_cask`, `brew_tap_installed`, `brew_tap_if_missing`, `brew_update`, `check_and_install_nala`, `app_dir_exists`, `ensure_not_root`, `usage`, `process_args`, `setup_dotfile_symlinks`, `setup_credential_directories` |
| `lib/detect_env.sh`         | Create — `detect_env()` wrapping the inline block at lines 898–930 of `setup_env.sh`                                                                                                                                                                                                                                                                         |
| `lib/macos.sh`              | Create — `install_rosetta`, `install_homebrew`, `install_git` (macOS), `install_zsh` (macOS), `setup_zsh_as_default_shell`                                                                                                                                                                                                                                   |
| `lib/linux.sh`              | Create — `install_bats`, `install_git` (Linux), `install_zsh` (Linux), `update_system_packages`                                                                                                                                                                                                                                                              |
| `lib/developer.sh`          | Create — `clone_or_update_dotfiles`, `update_aws_cli`, `update_rust` + any developer tooling functions extracted in Phase 0                                                                                                                                                                                                                                  |
| `setup_env.sh`              | Modify — remove all functions and constants; add `source` calls; keep prereq check, sourcing guard, and workflow dispatch blocks                                                                                                                                                                                                                             |
| `tests/setup_env/unit.bats` | Modify — add lib/ source tests                                                                                                                                                                                                                                                                                                                               |

**Key orientation:**

- Current `setup_env.sh` structure: lines 1–57 constants, line 58 HOSTNAME, lines 61–890 functions, line 892 sourcing guard, lines 894+ execution.
- Functions `install_git` and `install_zsh` are long and contain MACOS/LINUX branches — they stay as single cross-platform functions but move to `lib/macos.sh` (since they are predominantly macOS) or split into per-platform functions. Simplest: keep them whole in `lib/macos.sh` since they already have `if [[ -n ${MACOS} ]]` / `elif [[ -n ${LINUX} ]]` guards.
- `HOSTNAME=$(hostname -s)` at line 58 moves inside `detect_env()`.
- Source order in `setup_env.sh`: constants → helpers → detect_env → macos → linux → developer.

---

## Task 1: Write failing source tests for each lib file

**Files:**

- Modify: `tests/setup_env/unit.bats`

These tests verify each lib file sources without error. They will fail because the lib/ files don't exist yet.

- [ ] **Step 1: Append to `tests/setup_env/unit.bats`**

```bash
# ── lib/ source tests ─────────────────────────────────────────────────────────

@test "lib/constants.sh sources without error" {
  run bash -c "source lib/constants.sh"
  [ "$status" -eq 0 ]
}

@test "lib/helpers.sh sources without error" {
  run bash -c "source lib/constants.sh; source lib/helpers.sh"
  [ "$status" -eq 0 ]
}

@test "lib/detect_env.sh sources without error" {
  run bash -c "source lib/constants.sh; source lib/helpers.sh; source lib/detect_env.sh"
  [ "$status" -eq 0 ]
}

@test "lib/macos.sh sources without error" {
  run bash -c "source lib/constants.sh; source lib/helpers.sh; source lib/macos.sh"
  [ "$status" -eq 0 ]
}

@test "lib/linux.sh sources without error" {
  run bash -c "source lib/constants.sh; source lib/helpers.sh; source lib/linux.sh"
  [ "$status" -eq 0 ]
}

@test "lib/developer.sh sources without error" {
  run bash -c "source lib/constants.sh; source lib/helpers.sh; source lib/developer.sh"
  [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
make test-unit
```

Expected: all 6 lib source tests fail — `lib/constants.sh: No such file or directory`.

---

## Task 2: Create `lib/constants.sh`

**Files:**

- Create: `lib/constants.sh`

- [ ] **Step 1: Create `lib/` directory and `lib/constants.sh`**

Move the contents of `setup_env.sh` lines 3–57 (all version vars, URL vars, and directory vars) into `lib/constants.sh`. Include `HOSTNAME=$(hostname -s)` here temporarily — it will move to `detect_env()` in Task 4.

```bash
#!/usr/bin/env bash
# lib/constants.sh — version pins, download URLs, directory locations

# software versions to install
BATS_VER="1.11.0"
CF_TERRAFORMING_VER="0.16.1"
CHRUBY_VER="0.3.9"
CONSUL_VER="1.16.0"
DOCKER_COMPOSE_VER="v2.20.2"
GIT_VER="2.53.0"
GO_VER="1.26"
GO_DOWNLOAD_FILENAME="go1.26.1.linux-amd64.tar.gz"
GO_DOWNLOAD_URL="https://go.dev/dl/${GO_DOWNLOAD_FILENAME}"
KIND_VER="0.31.0"
NOMAD_VER="1.6.1"
PACKER_VER="1.15.1"
PYTHON_VER="3.14.3"
RUBY_INSTALL_VER="0.9.1"
RUBY_VER="4.0.2"
SHELLCHECK_VER="0.9.0"
TERRAFORM_VER="1.3.5"
TFLINT_VER="0.61.0"
TFSEC_VER="1.28.4"
VAGRANT_VER="2.4.9"
VAULT_VER="1.14.1"
VIRTUALBOX_VER="virtualbox-7.0"
YQ_VER="4.52.4"
ZSH_VER="5.10"
KUBERNETES_VER="v1.35"

CF_TERRAFORMING_URL="https://github.com/cloudflare/cf-terraforming/releases/download/v${CF_TERRAFORMING_VER}/cf-terraforming_${CF_TERRAFORMING_VER}_linux_amd64.tar.gz"
GIT_URL="https://mirrors.edge.kernel.org/pub/software/scm/git"
DOCKER_COMPOSE_URL="https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VER}/docker-compose-$(uname -s)-$(uname -m)"
HASHICORP_URL="https://releases.hashicorp.com"
KIND_URL="https://kind.sigs.k8s.io/dl/v${KIND_VER}/kind-linux-amd64"
TELEPRESENCE_URL="https://app.getambassador.io/download/tel2/linux/amd64/latest/telepresence"
TFLINT_URL="https://github.com/terraform-linters/tflint/releases/download/v${TFLINT_VER}/tflint_linux_amd64.zip"
TFSEC_URL="https://github.com/liamg/tfsec/releases/download/v${TFSEC_VER}/tfsec-linux-amd64"
YQ_URL="https://github.com/mikefarah/yq/releases/download/v${YQ_VER}/yq_linux_amd64"

RHEL_KUBECTL_REPO="cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/${KUBERNETES_VER}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/${KUBERNETES_VER}/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF"

# directory locations
BREWFILE_LOC="${HOME}/brew"
DOTFILES="dotfiles"
GITREPOS="${HOME}/git-repos"
PERSONAL_GITREPOS="${GITREPOS}/personal"
WSL_HOME="/mnt/c/Users/${USER}"

HOSTNAME=$(hostname -s)
```

- [ ] **Step 2: Validate syntax**

```bash
bash -n lib/constants.sh && printf "bash  OK\n"
zsh  -n lib/constants.sh && printf "zsh   OK\n"
```

- [ ] **Step 3: Run the constants source test**

```bash
bats tests/setup_env/unit.bats --filter "lib/constants.sh sources without error"
```

Expected: PASS.

---

## Task 3: Create `lib/helpers.sh`

**Files:**

- Create: `lib/helpers.sh`

Move these functions from `setup_env.sh` into `lib/helpers.sh`:

- `quiet_which` (line 61)
- `rhel_installed_package` (line 65)
- `brew_update` (line 156)
- `ensure_not_root` (line 193)
- `brew_formula_installed` (line 201)
- `brew_cask_installed` (line 213)
- `brew_install_formula` (line 225)
- `brew_install_cask` (line 235)
- `brew_tap_installed` (line 245)
- `brew_tap_if_missing` (line 253)
- `app_dir_exists` (line 263)
- `check_and_install_nala` (line 452)
- `usage` (line 469)
- `process_args` (line 484)
- `setup_dotfile_symlinks` (line 517)
- `setup_credential_directories` (line 783)

- [ ] **Step 1: Create `lib/helpers.sh`**

```bash
#!/usr/bin/env bash
# lib/helpers.sh — install guards, brew helpers, symlink utilities, argument parsing
```

Then copy the body of each function listed above verbatim from `setup_env.sh`.

- [ ] **Step 2: Validate syntax**

```bash
bash -n lib/helpers.sh && printf "bash  OK\n"
zsh  -n lib/helpers.sh && printf "zsh   OK\n"
```

- [ ] **Step 3: Run the helpers source test**

```bash
bats tests/setup_env/unit.bats --filter "lib/helpers.sh sources without error"
```

Expected: PASS.

---

## Task 4: Create `lib/detect_env.sh`

**Files:**

- Create: `lib/detect_env.sh`

The inline OS/version/hostname detection block currently lives in the main execution area of `setup_env.sh` (after the sourcing guard, around lines 898–930). Wrap it in a `detect_env()` function and move it to `lib/detect_env.sh`.

Current inline block (approximately):

```bash
[[ $(uname -s) = "Darwin" ]] && readonly MACOS=1
[[ $(uname -s) = "Linux" ]] && readonly LINUX=1

if [[ -n ${LINUX} ]]; then
  LINUX_TYPE=$(awk -F= '/^NAME/{print $2}' /etc/os-release | tr -d '"')
  [[ ${LINUX_TYPE} = "Ubuntu" ]] && readonly UBUNTU=1
  [[ ${LINUX_TYPE} = "CentOS Linux" ]] && readonly CENTOS=1
  [[ ${LINUX_TYPE} = "Red Hat Enterprise Linux Server" ]] && readonly REDHAT=1
  [[ ${LINUX_TYPE} = "Fedora" ]] && readonly FEDORA=1
  [[ ${LINUX_TYPE} = "elementary OS" ]] && readonly UBUNTU=1 && readonly ELEMENTARY=1
  ...
fi
... hostname detection (LAPTOP, STUDIO, etc.) ...
```

Read the full block from `setup_env.sh` before creating the file to capture all lines accurately.

- [ ] **Step 1: Read the detection block**

```bash
sed -n '894,960p' setup_env.sh
```

Note every line between the sourcing guard and the first `if [[ ${SETUP_USER}` block.

- [ ] **Step 2: Create `lib/detect_env.sh`**

```bash
#!/usr/bin/env bash
# lib/detect_env.sh — OS/version detection and hostname-based role vars

detect_env() {
  # <paste the entire inline block here, verbatim>
}
```

- [ ] **Step 3: Replace the inline block in `setup_env.sh` with a `detect_env` call**

After `process_args "$@"` in the main execution area, replace the inline detection block with:

```bash
detect_env
```

- [ ] **Step 4: Validate syntax of both files**

```bash
bash -n lib/detect_env.sh && printf "bash  OK detect_env\n"
zsh  -n lib/detect_env.sh && printf "zsh   OK detect_env\n"
bash -n setup_env.sh && printf "bash  OK setup_env\n"
zsh  -n setup_env.sh && printf "zsh   OK setup_env\n"
```

- [ ] **Step 5: Run the detect_env source test**

```bash
bats tests/setup_env/unit.bats --filter "lib/detect_env.sh sources without error"
```

Expected: PASS.

---

## Task 5: Create `lib/macos.sh`

**Files:**

- Create: `lib/macos.sh`

Move these functions from `setup_env.sh`:

- `install_rosetta` (line 73)
- `install_homebrew` (line 116)
- `install_git` (line 269) — full function including Linux branch
- `install_zsh` (line 348) — full function including Linux branch
- `setup_zsh_as_default_shell` (line 806)

Note: `install_git` and `install_zsh` contain both macOS and Linux branches inside them. Keep them whole in `lib/macos.sh` since they are invoked in the macOS setup flow and contain their own OS guards.

- [ ] **Step 1: Create `lib/macos.sh`**

```bash
#!/usr/bin/env bash
# lib/macos.sh — macOS-specific install functions
```

Copy each function body verbatim.

- [ ] **Step 2: Validate syntax**

```bash
bash -n lib/macos.sh && printf "bash  OK\n"
zsh  -n lib/macos.sh && printf "zsh   OK\n"
```

- [ ] **Step 3: Run the macos source test**

```bash
bats tests/setup_env/unit.bats --filter "lib/macos.sh sources without error"
```

Expected: PASS.

---

## Task 6: Create `lib/linux.sh`

**Files:**

- Create: `lib/linux.sh`

Move these functions from `setup_env.sh`:

- `install_bats` (line 430)
- `update_system_packages` (line 823)

Any additional Linux-specific functions extracted in Phase 0 (e.g., `ensure_dnf`, `install_ubuntu_packages`, etc.) also go here.

- [ ] **Step 1: Create `lib/linux.sh`**

```bash
#!/usr/bin/env bash
# lib/linux.sh — Linux-specific install and update functions
```

Copy each function body verbatim.

- [ ] **Step 2: Validate syntax**

```bash
bash -n lib/linux.sh && printf "bash  OK\n"
zsh  -n lib/linux.sh && printf "zsh   OK\n"
```

- [ ] **Step 3: Run the linux source test**

```bash
bats tests/setup_env/unit.bats --filter "lib/linux.sh sources without error"
```

Expected: PASS.

---

## Task 7: Create `lib/developer.sh`

**Files:**

- Create: `lib/developer.sh`

Move these functions from `setup_env.sh`:

- `clone_or_update_dotfiles` (line 504)
- `update_aws_cli` (line 854)
- `update_rust` (line 876)

Any developer tooling functions extracted in Phase 0 (install_ruby, install_github_cli, setup_ansible_venv, update_pip_packages, clone_personal_repos, setup_vim_plug, install_developer_gems, etc.) also go here.

- [ ] **Step 1: Create `lib/developer.sh`**

```bash
#!/usr/bin/env bash
# lib/developer.sh — cross-platform developer tooling (Ruby, Python, Ansible, AWS CLI, Rust, etc.)
```

Copy each function body verbatim.

- [ ] **Step 2: Validate syntax**

```bash
bash -n lib/developer.sh && printf "bash  OK\n"
zsh  -n lib/developer.sh && printf "zsh   OK\n"
```

- [ ] **Step 3: Run the developer source test**

```bash
bats tests/setup_env/unit.bats --filter "lib/developer.sh sources without error"
```

Expected: PASS.

---

## Task 8: Rewrite `setup_env.sh` as the orchestrator

**Files:**

- Modify: `setup_env.sh`

At this point all functions and constants have been moved to lib/ files. `setup_env.sh` should contain only:

1. The shebang
2. The Phase 0 prereq check block
3. The six `source` calls (in dependency order)
4. The sourcing guard
5. The argument parsing and workflow dispatch blocks (the main execution area)

- [ ] **Step 1: Replace `setup_env.sh` with the orchestrator**

The new `setup_env.sh` (after removing all functions and constants that were moved):

```bash
#!/usr/bin/env bash

# Prerequisite check — must be first
_BASH_MAJOR="${BASH_VERSINFO[0]:-0}"
if [[ "${_BASH_MAJOR}" -lt 5 ]]; then
  printf "[ERROR] bash 5+ required (running bash %s).\n" "${BASH_VERSION}" >&2
  printf "        On macOS, run first: ./scripts/bootstrap_mac.sh\n" >&2
  exit 1
fi
if ! command -v brew &>/dev/null; then
  printf "[ERROR] Homebrew not found.\n" >&2
  printf "        On macOS, run first: ./scripts/bootstrap_mac.sh\n" >&2
  exit 1
fi

source "$(dirname "$0")/lib/constants.sh"
source "$(dirname "$0")/lib/helpers.sh"
source "$(dirname "$0")/lib/detect_env.sh"
source "$(dirname "$0")/lib/macos.sh"
source "$(dirname "$0")/lib/linux.sh"
source "$(dirname "$0")/lib/developer.sh"

# Allow sourcing for unit testing without executing the main script body
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0

[[ $# -eq 0 ]] && usage
process_args "$@"
detect_env

# ... remaining workflow dispatch blocks (SETUP_USER, SETUP, DEVELOPER, ANSIBLE, UPDATE) ...
# These blocks call the functions defined in lib/*.sh — keep them verbatim.
```

Keep all the `if [[ ${SETUP_USER} || ${SETUP} ]]; then ... fi` blocks intact after `detect_env`. Only the function definitions and constants are removed from `setup_env.sh`.

- [ ] **Step 2: Validate syntax**

```bash
bash -n setup_env.sh && printf "bash  OK\n"
zsh  -n setup_env.sh && printf "zsh   OK\n"
```

- [ ] **Step 3: Run all lib source tests**

```bash
bats tests/setup_env/unit.bats --filter "sources without error"
```

Expected: all 6 pass.

- [ ] **Step 4: Run the full test suite**

```bash
make test
```

Expected: exit 0 — ALL existing tests still pass. The lib/ split is transparent to the test suite because sourcing `setup_env.sh` now sources all lib/ files first.

- [ ] **Step 5: Commit**

```bash
git add lib/ setup_env.sh tests/setup_env/unit.bats
git commit -m "refactor: split setup_env.sh into lib/*.sh modules

setup_env.sh is now an ~80-line orchestrator. All functions and
constants moved to focused lib files:
  lib/constants.sh  — version pins, URLs, directory vars
  lib/helpers.sh    — install guards, brew helpers, symlinks, arg parsing
  lib/detect_env.sh — OS/version detection (detect_env function)
  lib/macos.sh      — macOS-specific install functions
  lib/linux.sh      — Linux-specific functions
  lib/developer.sh  — developer tooling functions

Zero behavior change. All existing tests pass.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```
