# Workflows Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract platform-specific install blocks out of `run_setup_or_developer` and `run_developer_or_ansible` into named functions in the appropriate lib files, then add fine-grained tests for the `run_developer_or_ansible` helpers.

**Architecture:** `run_setup_or_developer` (lines 84–1011) and `run_developer_or_ansible` (lines 1013–1217) in `lib/workflows.sh` contain all platform install logic inline. We move each platform block to the matching lib file (`lib/macos.sh`, `lib/linux.sh`, `lib/developer.sh`), make the workflow functions thin dispatchers, and add ~15-20 tests covering the new helpers.

**Tech Stack:** Bash, BATS, PATH-based mocks in `tests/mocks/`

---

## File Map

| File | Change |
|---|---|
| `lib/macos.sh` | Add `install_macos_packages()` |
| `lib/linux.sh` | Add `install_ubuntu_packages()`, `install_rhel_packages()`, `install_centos_packages()`, `install_linux_packages()` |
| `lib/developer.sh` | Add `install_aws_tools()`, `setup_vim_plugins()`, `install_ruby_tools()`, `install_ruby()`, `install_github_cli_linux()`, `setup_kitchen()`, `setup_ansible()`, `clone_personal_repos()` |
| `lib/workflows.sh` | Replace bodies of `run_setup_or_developer` and `run_developer_or_ansible` with dispatcher calls |
| `tests/setup_env/workflows.bats` | Add tests for all new `lib/developer.sh` helpers |

---

## Task 1: Extract `install_macos_packages()` into `lib/macos.sh`

**Files:**
- Modify: `lib/macos.sh` (append after line 135)
- Modify: `lib/workflows.sh:87-116` (macOS block in `run_setup_or_developer`)
- Test: `tests/setup_env/workflows.bats`

- [ ] **Step 1: Write the failing tests**

Add to `tests/setup_env/workflows.bats` after the `run_setup_or_developer` section:

```bash
# ── install_macos_packages ────────────────────────────────────────────────────

@test "install_macos_packages symlinks Brewfile at BREWFILE_LOC" {
  export MACOS=1
  unset LINUX UBUNTU
  touch "${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile"
  install_macos_packages
  [[ -L "${BREWFILE_LOC}/Brewfile" ]]
}

@test "install_macos_packages calls brew update when brew is present" {
  export MACOS=1
  unset LINUX UBUNTU
  touch "${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile"
  install_macos_packages
  grep -q "brew update" "${MOCK_CALLS_FILE}"
}

@test "install_macos_packages calls softwareupdate" {
  export MACOS=1
  unset LINUX UBUNTU
  touch "${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile"
  install_macos_packages
  grep -q "softwareupdate" "${MOCK_CALLS_FILE}"
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bats tests/setup_env/workflows.bats --filter "install_macos_packages"
```

Expected: FAIL — `install_macos_packages: command not found`

- [ ] **Step 3: Add `install_macos_packages()` to `lib/macos.sh`**

Append after the closing `}` of `install_macos_casks()` at line 135:

```bash
install_macos_packages() {
  printf "Creating %s\n" "${BREWFILE_LOC}"
  mkdir -p ${BREWFILE_LOC}

  rm -f ${BREWFILE_LOC}/Brewfile
  ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile ${BREWFILE_LOC}/Brewfile
  if [[ -L ${BREWFILE_LOC}/Brewfile ]]; then
    printf "Brewfile is linked\n"
  fi

  if ! [ -x "$(command -v brew)" ]; then
    install_homebrew
  elif [ -x "$(command -v brew)" ]; then
    brew_update
    printf "Installing other brew stuff...\n"
    brew_tap_if_missing homebrew/bundle
    install_macos_casks

    printf "Cleaning Homebrew up...\n"
    brew cleanup
  fi

  printf "Updating app store apps via softwareupdate\n"
  sudo -H softwareupdate --install --all --verbose

  printf "Setting up macOS defaults\n"
  ${HOME}/scripts/.osx.sh
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bats tests/setup_env/workflows.bats --filter "install_macos_packages"
```

Expected: 3 tests PASS

- [ ] **Step 5: Replace macOS block in `run_setup_or_developer`**

In `lib/workflows.sh`, replace lines 87–116 (the entire `if [[ -n ${MACOS} ]]; then ... fi` block) with:

```bash
  if [[ -n ${MACOS} ]]; then
    install_macos_packages
  fi
```

- [ ] **Step 6: Run all tests to verify nothing broke**

```bash
make test
```

Expected: all tests pass (242+)

- [ ] **Step 7: Commit**

```bash
git add lib/macos.sh lib/workflows.sh tests/setup_env/workflows.bats
git commit -m "refactor: extract install_macos_packages into lib/macos.sh"
```

---

## Task 2: Extract `install_ubuntu_packages()` into `lib/linux.sh`

**Files:**
- Modify: `lib/linux.sh` (append after line 176)
- Modify: `lib/workflows.sh` (Ubuntu block in `run_setup_or_developer`, currently lines 118–765 after Task 1)
- Test: `tests/setup_env/workflows.bats`

- [ ] **Step 1: Write the failing tests**

Add to `tests/setup_env/workflows.bats` after the `install_macos_packages` section:

```bash
# ── install_ubuntu_packages ───────────────────────────────────────────────────

@test "install_ubuntu_packages calls apt update on Ubuntu Noble" {
  unset MACOS
  export LINUX=1
  export UBUNTU=1
  export NOBLE=1
  install_ubuntu_packages
  grep -q "apt update" "${MOCK_CALLS_FILE}"
}

@test "install_ubuntu_packages calls nala on Noble" {
  unset MACOS
  export LINUX=1
  export UBUNTU=1
  export NOBLE=1
  install_ubuntu_packages
  grep -q "nala" "${MOCK_CALLS_FILE}"
}

@test "install_ubuntu_packages installs snap packages when HAS_SNAP" {
  unset MACOS
  export LINUX=1
  export UBUNTU=1
  export NOBLE=1
  export HAS_SNAP=1
  install_ubuntu_packages
  grep -q "snap" "${MOCK_CALLS_FILE}"
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bats tests/setup_env/workflows.bats --filter "install_ubuntu_packages"
```

Expected: FAIL — `install_ubuntu_packages: command not found`

- [ ] **Step 3: Add `install_ubuntu_packages()` to `lib/linux.sh`**

Append after the closing `}` of `update_system_packages()` at line 176. The function body is the entire Ubuntu block from `run_setup_or_developer` (lines 118–765 as of the original file, now shifted after Task 1). Copy it verbatim, wrapped in:

```bash
install_ubuntu_packages() {
  sudo -H apt update
  if [[ ${FOCAL} ]]; then
    # ... (full Focal block from run_setup_or_developer)
  elif [[ ${JAMMY} ]]; then
    # ... (full Jammy block)
  elif [[ ${NOBLE} ]]; then
    # ... (full Noble block)
  fi
  # ... (rest of Ubuntu block: snap, bionic python, pyenv, powershell, Go, Rust,
  #      Docker, Virtualbox, Teleport, cloudflared, kind, yq, Albert, telepresence,
  #      azure-cli, gcloud-sdk, Consul, Vault, Nomad, Packer, Vagrant,
  #      docker-compose, cf-terraforming, brew Linux packages, Edge, .net8,
  #      glances, kubectl, helm, kustomize, libssl1.1, autoremove)
}
```

**This is a verbatim move** — copy the entire `if [[ -n ${UBUNTU} ]]; then ... fi` block body (everything between the outer braces) into the function. Do not change any logic.

- [ ] **Step 4: Run tests to verify they pass**

```bash
bats tests/setup_env/workflows.bats --filter "install_ubuntu_packages"
```

Expected: 3 tests PASS

- [ ] **Step 5: Replace Ubuntu block in `run_setup_or_developer`**

Replace the entire `if [[ -n ${UBUNTU} ]]; then ... fi` block with:

```bash
  if [[ -n ${UBUNTU} ]]; then
    install_ubuntu_packages
  fi
```

- [ ] **Step 6: Run all tests**

```bash
make test
```

Expected: all tests pass

- [ ] **Step 7: Commit**

```bash
git add lib/linux.sh lib/workflows.sh tests/setup_env/workflows.bats
git commit -m "refactor: extract install_ubuntu_packages into lib/linux.sh"
```

---

## Task 3: Extract RHEL, CentOS, and cross-platform Linux functions

**Files:**
- Modify: `lib/linux.sh` (append three new functions)
- Modify: `lib/workflows.sh` (RHEL, CentOS, Linux blocks in `run_setup_or_developer`)
- Test: `tests/setup_env/workflows.bats`

- [ ] **Step 1: Write the failing tests**

```bash
# ── install_rhel_packages ─────────────────────────────────────────────────────

@test "install_rhel_packages calls dnf on RHEL" {
  unset MACOS UBUNTU
  export LINUX=1
  export REDHAT=1
  install_rhel_packages
  grep -q "dnf" "${MOCK_CALLS_FILE}"
}

# ── install_linux_packages ────────────────────────────────────────────────────

@test "install_linux_packages clones tfenv on Linux" {
  unset MACOS UBUNTU REDHAT CENTOS
  export LINUX=1
  install_linux_packages
  grep -q "git clone" "${MOCK_CALLS_FILE}"
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bats tests/setup_env/workflows.bats --filter "install_rhel_packages|install_linux_packages"
```

Expected: FAIL

- [ ] **Step 3: Add the three functions to `lib/linux.sh`**

Append after `install_ubuntu_packages()`. Each is a verbatim move from the corresponding block in `run_setup_or_developer`:

```bash
install_rhel_packages() {
  # Verbatim copy of the `if [[ -n ${REDHAT} ]] || [[ -n ${FEDORA} ]]; then ... fi` body
  # (approximately lines 767–908 in the original)
  sudo -H dnf update -y
  sudo -H dnf install bzip2 -y
  # ... (full RHEL/Fedora block)
}

install_centos_packages() {
  # Verbatim copy of the `if [[ -n ${CENTOS} ]]; then ... fi` body
  # (approximately lines 910–926 in the original)
  sudo -H yum update -y
  sudo -H yum install curl -y
  # ... (full CentOS block)
}

install_linux_packages() {
  # Verbatim copy of the `if [[ -n ${LINUX} ]]; then ... fi` body
  # (approximately lines 928–970 in the original: tfenv, tflint, tfsec)
  printf "Installing Hashicorp Terraform Linux with tfenv on Linux\n"
  if [[ ! -d ${HOME}/.tfenv ]]; then
    git clone --recursive https://github.com/tfutils/tfenv.git ${HOME}/.tfenv
  fi
  # ... (full cross-platform Linux block)
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bats tests/setup_env/workflows.bats --filter "install_rhel_packages|install_linux_packages"
```

Expected: PASS

- [ ] **Step 5: Replace blocks in `run_setup_or_developer`**

Replace each block with its one-liner dispatcher:

```bash
  if [[ -n ${REDHAT} ]] || [[ -n ${FEDORA} ]]; then
    install_rhel_packages
  fi

  if [[ -n ${CENTOS} ]]; then
    install_centos_packages
  fi

  if [[ -n ${LINUX} ]]; then
    install_linux_packages
  fi
```

- [ ] **Step 6: Run all tests**

```bash
make test
```

- [ ] **Step 7: Commit**

```bash
git add lib/linux.sh lib/workflows.sh tests/setup_env/workflows.bats
git commit -m "refactor: extract install_rhel/centos/linux_packages into lib/linux.sh"
```

---

## Task 4: Extract `install_aws_tools()` and `setup_vim_plugins()` into `lib/developer.sh`

**Files:**
- Modify: `lib/developer.sh` (append two new functions)
- Modify: `lib/workflows.sh` (AWS and vim blocks at end of `run_setup_or_developer`)
- Test: `tests/setup_env/workflows.bats`

- [ ] **Step 1: Write the failing tests**

```bash
# ── install_aws_tools ─────────────────────────────────────────────────────────

@test "install_aws_tools calls wget for AWSCLIV2.pkg on macOS with HAS_AWS" {
  export MACOS=1
  export HAS_AWS=1
  unset LINUX
  mkdir -p "${HOME}/software_downloads/awscli"
  install_aws_tools
  grep -q "AWSCLIV2.pkg" "${MOCK_CALLS_FILE}"
}

@test "install_aws_tools calls wget for awscliv2.zip on Linux with HAS_AWS" {
  unset MACOS
  export LINUX=1
  export HAS_AWS=1
  mkdir -p "${HOME}/software_downloads/awscli"
  install_aws_tools
  grep -q "awscliv2.zip" "${MOCK_CALLS_FILE}"
}

@test "install_aws_tools is a no-op when HAS_AWS is unset" {
  export MACOS=1
  unset HAS_AWS LINUX
  install_aws_tools
  ! grep -q "awscli" "${MOCK_CALLS_FILE}"
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bats tests/setup_env/workflows.bats --filter "install_aws_tools"
```

Expected: FAIL

- [ ] **Step 3: Add `install_aws_tools()` and `setup_vim_plugins()` to `lib/developer.sh`**

Append after `update_rust()`:

```bash
install_aws_tools() {
  if [[ -n ${HAS_AWS} ]] && [[ -n ${MACOS} ]]; then
    mkdir -p ${HOME}/software_downloads/awscli
    printf "Installing aws-cli on MacOS\n"
    if [[ ! -f ${HOME}/software_downloads/awscli/AWSCLIV2.pkg ]]; then
      wget -O ${HOME}/software_downloads/awscli/AWSCLIV2.pkg "https://awscli.amazonaws.com/AWSCLIV2.pkg"
      sudo installer -pkg ${HOME}/software_downloads/awscli/AWSCLIV2.pkg -target /
      rm -f ${HOME}/software_downloads/awscli/AWSCLIV2.pkg
      if [[ -x $(command -v aws) ]]; then
        printf "aws-cli is installed MacOS\n"
      fi
    fi
  fi
  if [[ -n ${HAS_AWS} ]] && [[ -n ${LINUX} ]]; then
    mkdir -p ${HOME}/software_downloads/awscli
    printf "Installing aws-cli on Linux\n"
    if [[ ! -f ${HOME}/software_downloads/awscli/awscliv2.zip ]]; then
      wget -O ${HOME}/software_downloads/awscli/awscliv2.zip "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
      unzip ${HOME}/software_downloads/awscli/awscliv2.zip -d ${HOME}/software_downloads/awscli
      sudo -H ${HOME}/software_downloads/awscli/aws/install --install-dir /usr/local/aws-cli --bin-dir /usr/local/bin
      rm -rf ${HOME}/software_downloads/awscli
      rm -f ${HOME}/software_downloads/awscli/awscliv2.zip
      if [[ -x $(command -v aws) ]]; then
        printf "aws-cli is installed Linux\n"
      fi
    fi
  fi
}

setup_vim_plugins() {
  printf "vim plugins setup\n"
  mkdir -p ${HOME}/.vim/plugged
  if [[ -d ${HOME}/.vim/plugged ]]; then
    chmod 770 ${HOME}/.vim/plugged
  fi
  mkdir -p ${HOME}/.vim/autoload
  if [[ -d ${HOME}/.vim/autoload ]]; then
    chmod 770 ${HOME}/.vim/autoload
  fi
  if [[ ! -f ${HOME}/.vim/autoload/plug.vim ]]; then
    curl -fLo ${HOME}/.vim/autoload/plug.vim --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
  fi
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bats tests/setup_env/workflows.bats --filter "install_aws_tools"
```

Expected: 3 tests PASS

- [ ] **Step 5: Replace blocks in `run_setup_or_developer` and make it a thin dispatcher**

The function body (after previous tasks) should now only contain the remaining two blocks: AWS tools and vim plugins. Replace the full body with:

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

- [ ] **Step 6: Run all tests**

```bash
make test
```

- [ ] **Step 7: Commit**

```bash
git add lib/developer.sh lib/workflows.sh tests/setup_env/workflows.bats
git commit -m "refactor: extract install_aws_tools and setup_vim_plugins into lib/developer.sh"
```

---

## Task 5: Extract `install_ruby_tools()` and `install_ruby()` from `run_developer_or_ansible`

**Files:**
- Modify: `lib/developer.sh` (append two new functions)
- Test: `tests/setup_env/workflows.bats`

- [ ] **Step 1: Write the failing tests**

```bash
# ── install_ruby_tools ────────────────────────────────────────────────────────

@test "install_ruby_tools downloads ruby-install on Linux when absent" {
  unset MACOS
  export LINUX=1
  export UBUNTU=1
  export NOBLE=1
  install_ruby_tools
  grep -q "ruby-install" "${MOCK_CALLS_FILE}"
}

@test "install_ruby_tools downloads chruby on Linux Focal" {
  unset MACOS
  export LINUX=1
  export UBUNTU=1
  export FOCAL=1
  install_ruby_tools
  grep -q "chruby" "${MOCK_CALLS_FILE}"
}

@test "install_ruby_tools is a no-op on macOS" {
  export MACOS=1
  unset LINUX UBUNTU
  install_ruby_tools
  ! grep -q "ruby-install" "${MOCK_CALLS_FILE}"
}

# ── install_ruby ──────────────────────────────────────────────────────────────

@test "install_ruby calls ruby-install on macOS when ruby absent" {
  export MACOS=1
  unset LINUX UBUNTU
  # Ensure ruby dir is absent
  install_ruby
  grep -q "ruby-install" "${MOCK_CALLS_FILE}"
}

@test "install_ruby calls rbenv on Noble when ruby absent" {
  unset MACOS
  export LINUX=1
  export UBUNTU=1
  export NOBLE=1
  install_ruby
  grep -q "rbenv" "${MOCK_CALLS_FILE}"
}

@test "install_ruby skips when ruby dir already exists" {
  export MACOS=1
  unset LINUX UBUNTU
  mkdir -p "${HOME}/.rubies/ruby-${RUBY_VER}/bin"
  install_ruby
  ! grep -q "ruby-install" "${MOCK_CALLS_FILE}"
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bats tests/setup_env/workflows.bats --filter "install_ruby_tools|install_ruby"
```

Expected: FAIL

- [ ] **Step 3: Add `install_ruby_tools()` and `install_ruby()` to `lib/developer.sh`**

Append after `setup_vim_plugins()`:

```bash
install_ruby_tools() {
  if [[ -n ${LINUX} ]]; then
    printf "Installing ruby-install on linux\n"
    if [[ ! -d ${HOME}/software_downloads/ruby-install-${RUBY_INSTALL_VER} ]]; then
      wget -O ${HOME}/software_downloads/ruby-install-${RUBY_INSTALL_VER}.tar.gz https://github.com/postmodern/ruby-install/archive/v${RUBY_INSTALL_VER}.tar.gz
      tar -xzvf ${HOME}/software_downloads/ruby-install-${RUBY_INSTALL_VER}.tar.gz -C ${HOME}/software_downloads/
      cd ${HOME}/software_downloads/ruby-install-${RUBY_INSTALL_VER}/ || exit
      sudo make install
    fi

    printf "Installing chruby on linux\n"
    if [[ -n ${FOCAL} ]] || [[ -n ${JAMMY} ]]; then
      if [[ ! -d ${HOME}/software_downloads/chruby-${CHRUBY_VER} ]]; then
        wget -O ${HOME}/software_downloads/chruby-${CHRUBY_VER}.tar.gz https://github.com/postmodern/chruby/archive/v${CHRUBY_VER}.tar.gz
        tar -xzvf ${HOME}/software_downloads/chruby-${CHRUBY_VER}.tar.gz -C ${HOME}/software_downloads/
        cd ${HOME}/software_downloads/chruby-${CHRUBY_VER}/ || exit
        sudo make install
      fi
    fi
  fi
}

install_ruby() {
  if [[ ! -d ${HOME}/.rubies/ruby-${RUBY_VER}/bin ]]; then
    printf "Install ruby %s\n" "${RUBY_VER}"
    if [[ -n ${MACOS} ]]; then
      # shellcheck disable=SC2046
      ruby-install ${RUBY_VER} -- --with-openssl-dir=$(brew --prefix openssl@3)
    fi
    if [[ -n ${LINUX} ]]; then
      if [[ -n ${FOCAL} ]]; then
        ruby-install ${RUBY_VER}
      elif [[ -n ${JAMMY} ]]; then
        OPENSSL_DIR="$(pkg-config --variable=prefix openssl 2>/dev/null)"
        ruby-install ${RUBY_VER} -- --with-openssl-dir="${OPENSSL_DIR:-/usr}"
      elif [[ -n ${NOBLE} ]]; then
        if ! [[ -d ${HOME}/.rbenv/versions/${RUBY_VER} ]]; then
          OPENSSL_DIR="$(pkg-config --variable=libdir openssl 2>/dev/null | sed 's#/lib$##')"
          RUBY_CONFIGURE_OPTS="--with-openssl-dir=${OPENSSL_DIR:-/usr}" rbenv install ${RUBY_VER}
          rbenv global ${RUBY_VER}
          rbenv rehash
        fi
      fi
    fi
    INSTALLED_RUBY_VERSION=$(ruby --version | awk '{print $2}')
    if [[ ${INSTALLED_RUBY_VERSION} == "${RUBY_VER}" ]]; then
      printf "ruby %s is installed\n" "${RUBY_VER}"
    fi
  fi
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bats tests/setup_env/workflows.bats --filter "install_ruby_tools|install_ruby"
```

Expected: 6 tests PASS

- [ ] **Step 5: Commit (do not wire into run_developer_or_ansible yet)**

```bash
git add lib/developer.sh tests/setup_env/workflows.bats
git commit -m "refactor: add install_ruby_tools and install_ruby helpers to lib/developer.sh"
```

---

## Task 6: Extract `install_github_cli_linux()` and `setup_kitchen()` into `lib/developer.sh`

**Files:**
- Modify: `lib/developer.sh`
- Test: `tests/setup_env/workflows.bats`

- [ ] **Step 1: Write the failing tests**

```bash
# ── install_github_cli_linux ──────────────────────────────────────────────────

@test "install_github_cli_linux calls apt install gh on Ubuntu" {
  unset MACOS
  export LINUX=1
  export UBUNTU=1
  export NOBLE=1
  install_github_cli_linux
  grep -q "apt install gh" "${MOCK_CALLS_FILE}"
}

@test "install_github_cli_linux calls dnf on RHEL" {
  unset MACOS UBUNTU
  export LINUX=1
  export REDHAT=1
  install_github_cli_linux
  grep -q "dnf" "${MOCK_CALLS_FILE}"
}

# ── setup_kitchen ─────────────────────────────────────────────────────────────

@test "setup_kitchen calls gem install test-kitchen on macOS" {
  export MACOS=1
  unset LINUX UBUNTU
  setup_kitchen
  grep -q "gem install test-kitchen" "${MOCK_CALLS_FILE}"
}

@test "setup_kitchen calls gem install test-kitchen on Linux Jammy" {
  unset MACOS
  export LINUX=1
  export UBUNTU=1
  export JAMMY=1
  setup_kitchen
  grep -q "gem install test-kitchen" "${MOCK_CALLS_FILE}"
}

@test "setup_kitchen calls rbenv on Noble" {
  unset MACOS
  export LINUX=1
  export UBUNTU=1
  export NOBLE=1
  setup_kitchen
  grep -q "rbenv" "${MOCK_CALLS_FILE}"
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bats tests/setup_env/workflows.bats --filter "install_github_cli_linux|setup_kitchen"
```

Expected: FAIL

- [ ] **Step 3: Add `install_github_cli_linux()` and `setup_kitchen()` to `lib/developer.sh`**

Append after `install_ruby()`:

```bash
install_github_cli_linux() {
  printf "installing github cli on linux\n"
  if [[ -n ${UBUNTU} ]]; then
    wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null
    sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    sudo -H apt update
    sudo -H apt install gh
    if [[ -x $(command -v gh) ]]; then
      printf "gh is installed Ubuntu\n"
    fi
  elif [[ -n ${REDHAT} ]] || [[ -n ${CENTOS} ]] || [[ -n ${FEDORA} ]]; then
    sudo -H dnf install 'dnf-command(config-manager)'
    sudo -H dnf config-manager --add-repo http://cli.github.com/packages/rpm/gh-cli.repo
    sudo dnf install gh --repo gh-cli
    if [[ -x $(command -v gh) ]]; then
      printf "gh is installed RHEL\n"
    fi
  fi
}

setup_kitchen() {
  printf "Setup kitchen\n"
  if [[ -n ${MACOS} ]]; then
    source ${CHRUBY_LOC}/chruby/chruby.sh
    source ${CHRUBY_LOC}/chruby/auto.sh
    chruby ruby-${RUBY_VER}
  elif [[ -n ${LINUX} ]]; then
    if [[ -n ${FOCAL} ]] || [[ -n ${JAMMY} ]]; then
      source ${CHRUBY_LOC}/chruby/chruby.sh
      source ${CHRUBY_LOC}/chruby/auto.sh
      chruby ruby-${RUBY_VER}
    elif [[ -n ${NOBLE} ]]; then
      if ! [[ -d ${HOME}/.rbenv/versions/${RUBY_VER} ]]; then
        rbenv install ${RUBY_VER}
      fi
    fi
  fi

  if [[ -n ${MACOS} ]]; then
    gem install test-kitchen
    gem install kitchen-ansible
    gem install kitchen-docker
    gem install kitchen-inspec
    gem install kitchen-terraform
    gem install kitchen-verifier-serverspec
    gem install bundle
    gem install bundler
  elif [[ -n ${LINUX} ]]; then
    if [[ -n ${FOCAL} ]] || [[ -n ${JAMMY} ]]; then
      gem install test-kitchen
      gem install kitchen-ansible
      gem install kitchen-docker
      gem install kitchen-inspec
      gem install kitchen-terraform
      gem install kitchen-verifier-serverspec
      gem install bundle
      gem install bundler
    elif [[ -n ${NOBLE} ]]; then
      rbenv shell ${RUBY_VER}
      gem install test-kitchen
      gem install kitchen-ansible
      gem install kitchen-docker
      gem install kitchen-inspec
      gem install kitchen-terraform
      gem install kitchen-verifier-serverspec
      gem install bundle
      gem install bundler
    fi
  fi

  printf "Install terraspace\n"
  gem install terraspace
  if [[ -x $(command -v terraspace) ]]; then
    printf "terraspace is installed\n"
  fi
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bats tests/setup_env/workflows.bats --filter "install_github_cli_linux|setup_kitchen"
```

Expected: 5 tests PASS

- [ ] **Step 5: Commit**

```bash
git add lib/developer.sh tests/setup_env/workflows.bats
git commit -m "refactor: add install_github_cli_linux and setup_kitchen helpers to lib/developer.sh"
```

---

## Task 7: Extract `setup_ansible()` and `clone_personal_repos()` into `lib/developer.sh`

**Files:**
- Modify: `lib/developer.sh`
- Test: `tests/setup_env/workflows.bats`

- [ ] **Step 1: Write the failing tests**

```bash
# ── setup_ansible ─────────────────────────────────────────────────────────────

@test "setup_ansible calls pyenv install when Python version absent" {
  export MACOS=1
  unset LINUX
  export HAS_DEVTOOLS=1
  export MOCK_WHICH_MISSING=""
  setup_ansible
  grep -q "pyenv" "${MOCK_CALLS_FILE}"
}

@test "setup_ansible calls pip install ansible" {
  export MACOS=1
  unset LINUX
  export HAS_DEVTOOLS=1
  setup_ansible
  grep -q "pip install ansible" "${MOCK_CALLS_FILE}"
}

@test "setup_ansible skips pip when HAS_DEVTOOLS is unset" {
  export MACOS=1
  unset LINUX HAS_DEVTOOLS
  setup_ansible
  ! grep -q "pip install ansible" "${MOCK_CALLS_FILE}"
}

# ── clone_personal_repos ──────────────────────────────────────────────────────

@test "clone_personal_repos clones dotfiles when absent" {
  export MACOS=1
  rm -rf "${PERSONAL_GITREPOS}/dotfiles"
  clone_personal_repos
  grep -q "git clone" "${MOCK_CALLS_FILE}"
}

@test "clone_personal_repos skips repos that already exist" {
  export MACOS=1
  mkdir -p "${PERSONAL_GITREPOS}/dotfiles"
  mkdir -p "${PERSONAL_GITREPOS}/docker_container_terraform"
  mkdir -p "${PERSONAL_GITREPOS}/docker_container_terraform_packer_ansible"
  mkdir -p "${PERSONAL_GITREPOS}/kubernetes"
  mkdir -p "${PERSONAL_GITREPOS}/pfsense_config"
  mkdir -p "${PERSONAL_GITREPOS}/python-learning"
  mkdir -p "${PERSONAL_GITREPOS}/terraform_ansible"
  mkdir -p "${PERSONAL_GITREPOS}/terraspace_env"
  clone_personal_repos
  ! grep -q "git clone" "${MOCK_CALLS_FILE}"
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bats tests/setup_env/workflows.bats --filter "setup_ansible|clone_personal_repos"
```

Expected: FAIL

- [ ] **Step 3: Add `setup_ansible()` and `clone_personal_repos()` to `lib/developer.sh`**

Append after `setup_kitchen()`:

```bash
setup_ansible() {
  printf "ANSIBLE setup\n"
  if ! [[ -d ${HOME}/.pyenv/versions/${PYTHON_VER} ]]; then
    if [[ -n "${LINUX:-}" ]]; then
      pyenv update
      rm -rf "/tmp/python-build.*" 2>/dev/null || true
      # shellcheck disable=SC2016
      env -i \
        HOME="$HOME" USER="$USER" SHELL="${SHELL:-/bin/bash}" TERM="$TERM" \
        PYTHON_VER="${PYTHON_VER}" \
        PYENV_ROOT="$HOME/.pyenv" \
        PYENV_VIRTUALENV_DISABLE_PROMPT=1 \
        PYTHON_CONFIGURE_OPTS="--with-system-libmpdec=no" \
        PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
        bash -lc '
          set -euo pipefail
          export PATH="$PYENV_ROOT/bin:$PATH"
          eval "$(pyenv init -)"
          pyenv install -s -v "${PYTHON_VER}"
        '
    elif [[ -n "${MACOS:-}" ]]; then
      pyenv install -s "${PYTHON_VER}"
    fi
  fi

  if ! [[ $(readlink "${HOME}/.pyenv/versions/ansible") == "${HOME}/.pyenv/versions/${PYTHON_VER}/envs/ansible" ]]; then
    if [[ -n ${HAS_DEVTOOLS} ]]; then
      export PYENV_ROOT="$HOME/.pyenv"
      export PYENV_VIRTUALENV_DISABLE_PROMPT=1
      if quiet_which pyenv; then
        export PATH="$PYENV_ROOT/bin:$PATH"
        eval "$(pyenv init -)"
      fi
      pyenv virtualenv-delete -f ansible
      pyenv virtualenv "${PYTHON_VER}" ansible
      pyenv activate ansible
      printf "Installing Ansible dependencies...\n"
      python -m pip install ansible ansible-lint certbot certbot-dns-cloudflare boto3 docker gmpy2 jmespath mpmath netaddr pylint psutil bpytop HttpPy j2cli wheel shell-gpt
    fi
  fi
}

clone_personal_repos() {
  printf "personal git repos cloning\n"
  if ! [[ -d ${PERSONAL_GITREPOS}/dotfiles ]]; then
    git clone git@github.com:brujack/dotfiles.git ${PERSONAL_GITREPOS}/dotfiles
  fi
  if ! [[ -d ${PERSONAL_GITREPOS}/docker_container_terraform ]]; then
    git clone git@github.com:brujack/docker_container_terraform.git ${PERSONAL_GITREPOS}/docker_container_terraform
  fi
  if ! [[ -d ${PERSONAL_GITREPOS}/docker_container_terraform_packer_ansible ]]; then
    git clone git@github.com:brujack/docker_container_terraform_packer_ansible.git ${PERSONAL_GITREPOS}/docker_container_terraform_packer_ansible
  fi
  if ! [[ -d ${PERSONAL_GITREPOS}/kubernetes ]]; then
    git clone git@github.com:brujack/kubernetes.git ${PERSONAL_GITREPOS}/kubernetes
  fi
  if ! [[ -d ${PERSONAL_GITREPOS}/pfsense_config ]]; then
    git clone git@github.com:brujack/pfsense_config.git ${PERSONAL_GITREPOS}/pfsense_config
  fi
  if ! [[ -d ${PERSONAL_GITREPOS}/python-learning ]]; then
    git clone git@github.com:brujack/python-learning.git ${PERSONAL_GITREPOS}/python-learning
  fi
  if ! [[ -d ${PERSONAL_GITREPOS}/terraform_ansible ]]; then
    git clone git@github.com:brujack/terraform_ansible.git ${PERSONAL_GITREPOS}/terraform_ansible
  fi
  if ! [[ -d ${PERSONAL_GITREPOS}/terraspace_env ]]; then
    git clone git@github.com:brujack/terraspace_env.git ${PERSONAL_GITREPOS}/terraspace_env
  fi
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bats tests/setup_env/workflows.bats --filter "setup_ansible|clone_personal_repos"
```

Expected: 5 tests PASS

- [ ] **Step 5: Commit**

```bash
git add lib/developer.sh tests/setup_env/workflows.bats
git commit -m "refactor: add setup_ansible and clone_personal_repos helpers to lib/developer.sh"
```

---

## Task 8: Wire `run_developer_or_ansible()` as a thin dispatcher

**Files:**
- Modify: `lib/workflows.sh:1013-1217`

- [ ] **Step 1: Replace the body of `run_developer_or_ansible()` in `lib/workflows.sh`**

Replace the entire function body (lines 1013–1217) with:

```bash
run_developer_or_ansible() {
  printf "Installing json2yaml via npm\n"
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

- [ ] **Step 2: Run all tests**

```bash
make test
```

Expected: all tests pass

- [ ] **Step 3: Verify `lib/workflows.sh` line count has dropped significantly**

```bash
wc -l lib/workflows.sh
```

Expected: under 600 lines (was 1437)

- [ ] **Step 4: Commit**

```bash
git add lib/workflows.sh
git commit -m "refactor: run_developer_or_ansible is now a thin dispatcher"
```

---

## Task 9: Update docs and superpowers index

**Files:**
- Modify: `docs/superpowers/README.md`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update superpowers README**

In `docs/superpowers/README.md`, find the workflows-refactor row and update Status from `Pending` to `Done`. Also add the plan link:

```
| 2026-04-10 | [workflows-refactor](plans/2026-04-10-workflows-refactor.md) | [spec](specs/2026-04-10-workflows-refactor-design.md) | Done |
```

- [ ] **Step 2: Update CLAUDE.md lib layout comment**

In the Layout table in `CLAUDE.md`, update the `lib/macos.sh`, `lib/linux.sh`, and `lib/developer.sh` descriptions to mention the new functions:

- `lib/macos.sh` → `macOS-specific install functions (install_rosetta, install_homebrew, install_macos_casks, install_macos_packages)`
- `lib/linux.sh` → `Linux-specific install functions (install_ubuntu_packages, install_rhel_packages, install_centos_packages, install_linux_packages, update_system_packages)`
- `lib/developer.sh` → `Cross-platform dev tooling (install_aws_tools, setup_vim_plugins, install_ruby_tools, install_ruby, setup_kitchen, setup_ansible, clone_personal_repos)`

- [ ] **Step 3: Run final test suite**

```bash
make test
```

Expected: all tests pass, exit 0

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/README.md CLAUDE.md
git commit -m "docs: update CLAUDE.md and superpowers index for workflows-refactor"
```
