# setup_env.sh Function Extraction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract inline code blocks in `setup_env.sh` into named functions within the same file, with BATS tests for functions containing real conditional logic.

**Architecture:** All 14 new functions are added to `setup_env.sh` before the sourcing guard at line 860, keeping them available for unit testing. Tests for mock-based functions go in `tests/setup_env/install_guards.bats` (which already calls `load_mocks`). The main execution blocks become flat sequences of function calls.

**Tech Stack:** Bash, BATS (Bash Automated Testing System), existing `tests/mocks/` PATH-injection pattern.

---

## Files Modified / Created

| File | Action |
|---|---|
| `setup_env.sh` | Add 14 new functions before line 860; replace inline blocks with calls |
| `tests/setup_env/install_guards.bats` | Add 24 new tests across 8 sections |
| `tests/mocks/ruby-install` | New mock |
| `tests/mocks/rbenv` | New mock |
| `tests/mocks/pyenv` | New mock |
| `tests/mocks/python3` | New mock |

**Key orientation:**
- Functions go after `update_rust()` (ends at line 858), before the comment at line 860.
- `install_guards.bats` already has `load_mocks` and `MOCK_CALLS_FILE` in `setup()` — new tests just append to the existing file.
- Sourcing guard: `[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0` at line 861 — all functions must be BEFORE this line.
- Run tests with `make test` from repo root.

---

## Task 1: `ensure_dnf()`

**Files:**
- Modify: `setup_env.sh` (add function before line 860; replace lines 914–925 in main block)
- Modify: `tests/setup_env/install_guards.bats` (add 3 tests)

- [ ] **Step 1: Add the 3 failing tests to `tests/setup_env/install_guards.bats`**

Append to the end of the file:

```bash
# ── ensure_dnf ───────────────────────────────────────────────────────────────

@test "ensure_dnf skips yum when dnf is already present" {
  export REDHAT=1
  run ensure_dnf
  [ "$status" -eq 0 ]
  [ ! -f "${MOCK_CALLS_FILE}" ] || ! grep -q "yum" "${MOCK_CALLS_FILE}"
}

@test "ensure_dnf runs yum update and yum install dnf when dnf is absent" {
  export REDHAT=1
  export MOCK_WHICH_MISSING=dnf
  run ensure_dnf
  grep -q "yum update -y" "${MOCK_CALLS_FILE}"
  grep -q "yum install dnf -y" "${MOCK_CALLS_FILE}"
}

@test "ensure_dnf does nothing when neither REDHAT nor FEDORA is set" {
  unset REDHAT FEDORA
  run ensure_dnf
  [ "$status" -eq 0 ]
  [ ! -f "${MOCK_CALLS_FILE}" ] || ! grep -q "yum" "${MOCK_CALLS_FILE}"
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
make test
```

Expected: `ensure_dnf: command not found` (or similar) for all 3 new tests.

- [ ] **Step 3: Add `ensure_dnf()` to `setup_env.sh` after `update_rust()` (after line 858)**

Insert before line 860 (`# Allow sourcing...`):

```bash
ensure_dnf() {
  if [[ ${REDHAT} || ${FEDORA} ]]; then
    if ! quiet_which dnf; then
      printf "Installing dnf\\n"
      sudo -H yum update -y
      sudo -H yum install dnf -y
      if ! quiet_which dnf; then
        printf "Failed to install dnf\\n"
        exit 1
      fi
      printf "Installed dnf\\n"
    fi
  fi
}

```

> Note: The original inline code used `[ -x "$(command -v dnf)" ]`. This uses `quiet_which dnf` instead, which is the established codebase pattern and enables MOCK_WHICH_MISSING testing.

- [ ] **Step 4: Replace inline block in main body**

In the `if [[ ${SETUP} || ${SETUP_USER} ]]; then` block (around line 914), replace:

```bash
  # need to make sure that some base packages are installed
  if [[ ${REDHAT} || ${FEDORA} ]]; then
    if ! [ -x "$(command -v dnf)" ]; then
      printf "Installing dnf\\n"
      sudo -H yum update -y
      sudo -H yum install dnf -y
      if ! [ -x "$(command -v dnf)" ]; then
        printf "Failed to install dnf\\n"
        exit 1
      fi
      printf "Installed dnf\\n"
    fi
  fi
```

with:

```bash
  ensure_dnf
```

- [ ] **Step 5: Validate syntax**

```bash
bash -n setup_env.sh && zsh -n setup_env.sh
```

Expected: no output (both exit 0).

- [ ] **Step 6: Run full test suite**

```bash
make test
```

Expected: all 3 new tests pass; all existing tests still pass.

- [ ] **Step 7: Commit**

```bash
git add setup_env.sh tests/setup_env/install_guards.bats
git commit -m "refactor: extract ensure_dnf() with tests"
```

---

## Task 2: `install_cheatsh()`

**Files:**
- Modify: `setup_env.sh`
- Modify: `tests/setup_env/install_guards.bats`

- [ ] **Step 1: Add the 3 failing tests**

Append to `tests/setup_env/install_guards.bats`:

```bash
# ── install_cheatsh ──────────────────────────────────────────────────────────

@test "install_cheatsh downloads cht.sh when ~/bin exists" {
  mkdir -p "${BATS_TEST_TMPDIR}/home/bin"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export UBUNTU=1
  run install_cheatsh
  grep -q "curl.*cht.sh" "${MOCK_CALLS_FILE}"
}

@test "install_cheatsh skips download when ~/bin does not exist" {
  export HOME="${BATS_TEST_TMPDIR}/home"  # no bin subdir
  run install_cheatsh
  [ "$status" -eq 0 ]
  [ ! -f "${MOCK_CALLS_FILE}" ] || ! grep -q "curl.*cht.sh" "${MOCK_CALLS_FILE}"
}

@test "install_cheatsh installs curl via apt on Ubuntu before downloading" {
  mkdir -p "${BATS_TEST_TMPDIR}/home/bin"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export UBUNTU=1
  run install_cheatsh
  grep -q "apt install curl" "${MOCK_CALLS_FILE}"
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
make test
```

Expected: `install_cheatsh: command not found` for all 3 new tests.

- [ ] **Step 3: Add `install_cheatsh()` to `setup_env.sh`**

Insert after `ensure_dnf()` (before line 860):

```bash
install_cheatsh() {
  printf "Setting up cheat.sh\\n"
  if [[ -d ${HOME}/bin ]]; then
    if [[ -n ${UBUNTU} ]]; then
      sudo -H apt update
      sudo -H apt install curl -y
    fi
    if [[ -n ${CENTOS} ]]; then
      sudo -H dnf update -y
      sudo -H dnf install curl -y
    fi
    if [[ -n ${REDHAT} ]] || [[ -n ${FEDORA} ]]; then
      sudo -H yum update
      sudo -H yum install curl -y
    fi
    curl https://cht.sh/:cht.sh > ~/bin/cht.sh
    chmod 750 ${HOME}/bin/cht.sh
  fi
  if [[ -x $(command -v cht.sh) ]]; then
    printf "cht.sh is installed\\n"
  fi
}

```

- [ ] **Step 4: Replace inline block in main body**

In the `if [[ ${SETUP} || ${SETUP_USER} ]]; then` block, replace:

```bash
  printf "Setting up cheat.sh\\n"
  if [[ -d ${HOME}/bin ]]; then
    if [[ -n ${UBUNTU} ]]; then
      sudo -H apt update
      sudo -H apt install curl -y
    fi
    if [[ -n ${CENTOS} ]]; then
      sudo -H dnf update -y
      sudo -H dnf install curl -y
    fi
    if [[ -n ${REDHAT} ]] || [[ -n ${FEDORA} ]]; then
      sudo -H yum update
      sudo -H yum install curl -y
    fi
    curl https://cht.sh/:cht.sh > ~/bin/cht.sh
    chmod 750 ${HOME}/bin/cht.sh
  fi
  if [[ -x $(command -v cht.sh) ]]; then
    printf "cht.sh is installed\\n"
  fi
```

with:

```bash
  install_cheatsh
```

- [ ] **Step 5: Validate syntax**

```bash
bash -n setup_env.sh && zsh -n setup_env.sh
```

- [ ] **Step 6: Run full test suite**

```bash
make test
```

Expected: all 3 new tests pass; all prior tests still pass.

- [ ] **Step 7: Commit**

```bash
git add setup_env.sh tests/setup_env/install_guards.bats
git commit -m "refactor: extract install_cheatsh() with tests"
```

---

## Task 3: `install_go_ubuntu()`

**Files:**
- Modify: `setup_env.sh`
- Modify: `tests/setup_env/install_guards.bats`

- [ ] **Step 1: Add the 3 failing tests**

Append to `tests/setup_env/install_guards.bats`:

```bash
# ── install_go_ubuntu ────────────────────────────────────────────────────────

@test "install_go_ubuntu uses PPA path for Go 1.20" {
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${HOME}/software_downloads"
  export GO_VER=1.20
  run install_go_ubuntu
  grep -q "add-apt-repository.*longsleep" "${MOCK_CALLS_FILE}"
  grep -q "apt install golang-1.20-go" "${MOCK_CALLS_FILE}"
}

@test "install_go_ubuntu uses wget and tar path for Go 1.21" {
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${HOME}/software_downloads"
  export GO_VER=1.21
  export GO_DOWNLOAD_FILENAME="go1.21.linux-amd64.tar.gz"
  export GO_DOWNLOAD_URL="https://go.dev/dl/${GO_DOWNLOAD_FILENAME}"
  run install_go_ubuntu
  grep -q "wget.*go1.21" "${MOCK_CALLS_FILE}"
  grep -q "tar" "${MOCK_CALLS_FILE}"
}

@test "install_go_ubuntu exits 1 for unsupported Go version" {
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${HOME}/software_downloads"
  export GO_VER=9.99
  run install_go_ubuntu
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unsupported Go version"* ]]
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
make test
```

Expected: `install_go_ubuntu: command not found` for all 3 new tests.

- [ ] **Step 3: Add `install_go_ubuntu()` to `setup_env.sh`**

Insert after `install_cheatsh()` (before line 860). The function body is an exact extraction of the Go install block from the Ubuntu developer section (currently lines ~1440–1615). The function wraps that entire case statement:

```bash
install_go_ubuntu() {
  printf "Installing Go Ubuntu\\n"
  sudo -H apt update
  case ${GO_VER} in
    1.16)
      pkgs_to_remove="golang-1.15-go golang-1.15-src"
      ;;
    1.17)
      pkgs_to_remove="golang-1.16-go golang-1.16-src"
      ;;
    1.18)
      pkgs_to_remove="golang-1.17-go golang-1.17-src"
      ;;
    1.19)
      pkgs_to_remove="golang-1.18-go golang-1.18-src"
      ;;
    1.20)
      pkgs_to_remove="golang-1.19-go golang-1.19-src"
      ;;
    1.21)
      pkgs_to_remove="golang-1.20-go golang-1.20-src"
      ;;
    1.22)
      pkgs_to_remove="golang-1.21-go golang-1.21-src"
      ;;
    1.23)
      pkgs_to_remove="golang-1.22-go golang-1.22-src"
      ;;
    1.24)
      pkgs_to_remove="golang-1.23-go golang-1.23-src"
      ;;
    1.25)
      pkgs_to_remove="golang-1.24-go golang-1.24-src"
      ;;
    1.26)
      pkgs_to_remove="golang-1.25-go golang-1.25-src"
      ;;
    *)
      printf "Error: Unsupported Go version %s\\n" "${GO_VER}"
      exit 1
      ;;
  esac
  if [[ -n ${pkgs_to_remove} ]]; then
    sudo -H apt remove ${pkgs_to_remove} -y
  fi
  case ${GO_VER} in
    1.16|1.17|1.18|1.19|1.20)
      sudo add-apt-repository ppa:longsleep/golang-backports -y
      sudo -H apt install "golang-${GO_VER}-go" -y
      ;;
    1.21|1.22|1.23|1.24|1.25|1.26)
      if [[ ! -f ${HOME}/software_downloads/${GO_DOWNLOAD_FILENAME} ]]; then
        wget -O ${HOME}/software_downloads/${GO_DOWNLOAD_FILENAME} ${GO_DOWNLOAD_URL}
        tar xvf ${HOME}/software_downloads/${GO_DOWNLOAD_FILENAME} -C ${HOME}/software_downloads/
        if [[ -d /usr/local/go ]]; then
          sudo rm -rf /usr/local/go
        fi
        if [[ -d ${HOME}/software_downloads/go ]]; then
          sudo mv ${HOME}/software_downloads/go /usr/local/go
          sudo chmod 755 /usr/local/go
          sudo chown -R root:root /usr/local/go
        fi
        if [[ -d ${HOME}/software_downloads/go ]]; then
          rm -rf ${HOME}/software_downloads/go
        fi
      fi
      ;;
    *)
      printf "Error: Unsupported Go version %s\\n" "${GO_VER}"
      exit 1
      ;;
  esac
  INSTALLED_GO_VER=$(go version | awk '{print $3}' | sed 's/go//g')
  if [[ ${INSTALLED_GO_VER} == ${GO_VER} ]]; then
    printf "Go %s is installed\\n" "${GO_VER}"
  fi
}

```

> Note: The original case statement has duplicate bodies for versions 1.21–1.26. This extraction consolidates them into a single `1.21|1.22|1.23|1.24|1.25|1.26)` arm — identical behaviour, less repetition. The first case statement (for packages to remove) still needs individual entries.

- [ ] **Step 4: Replace inline block in main body**

In the Ubuntu section of the `if [[ -n ${SETUP} ]] || [[ -n ${DEVELOPER} ]]; then` block, find the line `printf "Installing Go Ubuntu\\n"` and replace all of the Go install block (through the closing `INSTALLED_GO_VER` check) with:

```bash
    install_go_ubuntu
```

- [ ] **Step 5: Validate syntax**

```bash
bash -n setup_env.sh && zsh -n setup_env.sh
```

- [ ] **Step 6: Run full test suite**

```bash
make test
```

Expected: all 3 new tests pass.

- [ ] **Step 7: Commit**

```bash
git add setup_env.sh tests/setup_env/install_guards.bats
git commit -m "refactor: extract install_go_ubuntu() with tests"
```

---

## Task 4: `install_ruby()` — add mocks + tests + extract

**Files:**
- Create: `tests/mocks/ruby-install`
- Create: `tests/mocks/rbenv`
- Modify: `setup_env.sh`
- Modify: `tests/setup_env/install_guards.bats`

- [ ] **Step 1: Create `tests/mocks/ruby-install`**

```bash
#!/usr/bin/env bash
printf "ruby-install %s\n" "$*" >> "${MOCK_CALLS_FILE:-/tmp/mock_calls}"
exit 0
```

Make it executable: `chmod +x tests/mocks/ruby-install`

- [ ] **Step 2: Create `tests/mocks/rbenv`**

```bash
#!/usr/bin/env bash
printf "rbenv %s\n" "$*" >> "${MOCK_CALLS_FILE:-/tmp/mock_calls}"
exit 0
```

Make it executable: `chmod +x tests/mocks/rbenv`

- [ ] **Step 3: Add the 3 failing tests**

Append to `tests/setup_env/install_guards.bats`:

```bash
# ── install_ruby ─────────────────────────────────────────────────────────────

@test "install_ruby calls ruby-install with --with-openssl-dir on macOS" {
  export MACOS=1
  export HOME="${BATS_TEST_TMPDIR}/home"
  # no ~/.rubies/ruby-$RUBY_VER/bin dir — triggers install
  run install_ruby
  grep -q "ruby-install.*--with-openssl-dir" "${MOCK_CALLS_FILE}"
}

@test "install_ruby calls ruby-install without extra flags on Ubuntu Focal" {
  export LINUX=1
  export UBUNTU=1
  export FOCAL=1
  export HOME="${BATS_TEST_TMPDIR}/home"
  run install_ruby
  grep -q "ruby-install ${RUBY_VER}$" "${MOCK_CALLS_FILE}"
}

@test "install_ruby uses rbenv on Ubuntu Noble" {
  export LINUX=1
  export UBUNTU=1
  export NOBLE=1
  export HOME="${BATS_TEST_TMPDIR}/home"
  run install_ruby
  grep -q "rbenv install" "${MOCK_CALLS_FILE}"
}
```

- [ ] **Step 4: Run tests to confirm they fail**

```bash
make test
```

Expected: `install_ruby: command not found` for all 3 new tests.

- [ ] **Step 5: Add `install_ruby()` to `setup_env.sh`**

Insert after `install_go_ubuntu()` (before line 860):

```bash
install_ruby() {
  if [[ ! -d ${HOME}/.rubies/ruby-${RUBY_VER}/bin ]]; then
    printf "Install ruby %s\\n" "${RUBY_VER}"
    if [[ -n ${MACOS} ]]; then
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
    INSTALLED_RUBY_VERSION=$(ruby --version) | awk '{print $2}'
    if [[ ${INSTALLED_RUBY_VERSION} == ${RUBY_VER} ]]; then
      printf "ruby %s is installed\\n" "${RUBY_VER}"
    fi
  fi
}

```

- [ ] **Step 6: Replace inline block in main body**

In the `if [[ -n ${DEVELOPER} ]] || [[ -n ${ANSIBLE} ]]; then` block, replace the entire `if [[ ! -d ${HOME}/.rubies/ruby-${RUBY_VER}/bin ]]; then ... fi` block (lines ~2255–2281) with:

```bash
  install_ruby
```

- [ ] **Step 7: Validate syntax**

```bash
bash -n setup_env.sh && zsh -n setup_env.sh
```

- [ ] **Step 8: Run full test suite**

```bash
make test
```

Expected: all 3 new tests pass.

- [ ] **Step 9: Commit**

```bash
git add setup_env.sh tests/setup_env/install_guards.bats tests/mocks/ruby-install tests/mocks/rbenv
git commit -m "refactor: extract install_ruby() with tests; add ruby-install and rbenv mocks"
```

---

## Task 5: `install_github_cli()`

**Files:**
- Modify: `setup_env.sh`
- Modify: `tests/setup_env/install_guards.bats`

- [ ] **Step 1: Add the 3 failing tests**

Append to `tests/setup_env/install_guards.bats`:

```bash
# ── install_github_cli ───────────────────────────────────────────────────────

@test "install_github_cli uses apt on Ubuntu" {
  export LINUX=1
  export UBUNTU=1
  run install_github_cli
  grep -q "apt install gh" "${MOCK_CALLS_FILE}"
}

@test "install_github_cli uses dnf on RHEL" {
  export LINUX=1
  export REDHAT=1
  run install_github_cli
  grep -q "dnf install gh" "${MOCK_CALLS_FILE}"
}

@test "install_github_cli does nothing on macOS" {
  export MACOS=1
  unset LINUX
  run install_github_cli
  [ "$status" -eq 0 ]
  [ ! -f "${MOCK_CALLS_FILE}" ] || ! grep -qE "apt|dnf" "${MOCK_CALLS_FILE}"
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
make test
```

Expected: `install_github_cli: command not found` for all 3 new tests.

- [ ] **Step 3: Add `install_github_cli()` to `setup_env.sh`**

Insert after `install_ruby()` (before line 860):

```bash
install_github_cli() {
  if [[ -n ${LINUX} ]]; then
    printf "installing github cli on linux\\n"
    if [[ -n ${UBUNTU} ]]; then
      wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null
      sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
      sudo -H apt update
      sudo -H apt install gh
      if [[ -x $(command -v gh) ]]; then
        printf "gh is installed Ubuntu\\n"
      fi
    elif [[ -n ${REDHAT} ]] || [[ -n ${CENTOS} ]] || [[ -n ${FEDORA} ]]; then
      sudo -H dnf install 'dnf-command(config-manager)'
      sudo -H dnf config-manager --add-repo http://cli.github.com/packages/rpm/gh-cli.repo
      sudo dnf install gh --repo gh-cli
      if [[ -x $(command -v gh) ]]; then
        printf "gh is installed RHEL\\n"
      fi
    fi
  fi
}

```

- [ ] **Step 4: Replace inline block in main body**

In the `if [[ -n ${DEVELOPER} ]] || [[ -n ${ANSIBLE} ]]; then` block, replace the `if [[ -n ${LINUX} ]]; then ... printf "installing github cli on linux"` block (lines ~2283–2302) with:

```bash
  install_github_cli
```

- [ ] **Step 5: Validate syntax**

```bash
bash -n setup_env.sh && zsh -n setup_env.sh
```

- [ ] **Step 6: Run full test suite**

```bash
make test
```

Expected: all 3 new tests pass.

- [ ] **Step 7: Commit**

```bash
git add setup_env.sh tests/setup_env/install_guards.bats
git commit -m "refactor: extract install_github_cli() with tests"
```

---

## Task 6: `setup_ansible_venv()` — add pyenv mock + tests + extract

**Files:**
- Create: `tests/mocks/pyenv`
- Modify: `setup_env.sh`
- Modify: `tests/setup_env/install_guards.bats`

- [ ] **Step 1: Create `tests/mocks/pyenv`**

```bash
#!/usr/bin/env bash
printf "pyenv %s\n" "$*" >> "${MOCK_CALLS_FILE:-/tmp/mock_calls}"
if [[ "$1" == "init" ]] || [[ "$1" == "virtualenv-init" ]]; then
  exit 0  # outputs nothing — eval "$(pyenv init -)" becomes eval "" (no-op)
fi
if [[ "$1" == "which" ]]; then
  printf "python3\n"
  exit 0
fi
exit 0
```

Make it executable: `chmod +x tests/mocks/pyenv`

- [ ] **Step 2: Add the 3 failing tests**

Append to `tests/setup_env/install_guards.bats`:

```bash
# ── setup_ansible_venv ───────────────────────────────────────────────────────

@test "setup_ansible_venv skips pyenv python install when version dir exists" {
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${HOME}/.pyenv/versions/${PYTHON_VER}"
  export LAPTOP=1
  # Also create the ansible symlink so venv creation is also skipped
  mkdir -p "${HOME}/.pyenv/versions"
  ln -sf "${HOME}/.pyenv/versions/${PYTHON_VER}/envs/ansible" \
         "${HOME}/.pyenv/versions/ansible"
  run setup_ansible_venv
  ! grep -q "pyenv install" "${MOCK_CALLS_FILE}" 2>/dev/null || \
    ! grep -q "pyenv install -s" "${MOCK_CALLS_FILE}"
}

@test "setup_ansible_venv skips venv creation when symlink already correct" {
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${HOME}/.pyenv/versions/${PYTHON_VER}"
  mkdir -p "${HOME}/.pyenv/versions"
  ln -sf "${HOME}/.pyenv/versions/${PYTHON_VER}/envs/ansible" \
         "${HOME}/.pyenv/versions/ansible"
  export LAPTOP=1
  run setup_ansible_venv
  [ "$status" -eq 0 ]
  [ ! -f "${MOCK_CALLS_FILE}" ] || ! grep -q "pyenv virtualenv " "${MOCK_CALLS_FILE}"
}

@test "setup_ansible_venv creates venv when symlink absent and host var set" {
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${HOME}/.pyenv/versions/${PYTHON_VER}"
  # No ansible symlink
  export LAPTOP=1
  run setup_ansible_venv
  grep -q "pyenv virtualenv ${PYTHON_VER} ansible" "${MOCK_CALLS_FILE}"
}
```

- [ ] **Step 3: Run tests to confirm they fail**

```bash
make test
```

Expected: `setup_ansible_venv: command not found` for all 3 new tests.

- [ ] **Step 4: Add `setup_ansible_venv()` to `setup_env.sh`**

Insert after `install_github_cli()` (before line 860):

```bash
setup_ansible_venv() {
  if ! [[ -d ${HOME}/.pyenv/versions/${PYTHON_VER} ]]; then
    if [[ -n "${LINUX:-}" ]]; then
      pyenv update

      rm -rf "/tmp/python-build.*" 2>/dev/null || true

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
    if [[ -n ${STUDIO} ]] || [[ -n ${LAPTOP} ]] || [[ -n ${RECEPTION} ]] || [[ -n ${OFFICE} ]] || [[ -n ${HOMES} ]] || [[ -n ${WORKSTATION} ]] || [[ -n ${CRUNCHER} ]] || [[ -n ${RATNA} ]]; then
      export PYENV_ROOT="$HOME/.pyenv"
      export PYENV_VIRTUALENV_DISABLE_PROMPT=1
      if quiet_which pyenv; then
        export PATH="$PYENV_ROOT/bin:$PATH"
        eval "$(pyenv init -)"
      fi
      pyenv virtualenv-delete -f ansible
      pyenv virtualenv "${PYTHON_VER}" ansible
      pyenv activate ansible
      printf "Installing Ansible dependencies...\\n"
      python -m pip install ansible ansible-lint certbot certbot-dns-cloudflare boto3 docker gmpy2 jmespath mpmath netaddr pylint psutil bpytop HttpPy j2cli wheel shell-gpt
    fi
  fi
}

```

- [ ] **Step 5: Replace inline block in main body**

In the `if [[ -n ${DEVELOPER} ]] || [[ -n ${ANSIBLE} ]]; then` block, replace the `printf "ANSIBLE setup\\n"` block and everything through the closing `fi` of the venv creation (lines ~2359–2403) with:

```bash
  printf "ANSIBLE setup\\n"
  setup_ansible_venv
```

- [ ] **Step 6: Validate syntax**

```bash
bash -n setup_env.sh && zsh -n setup_env.sh
```

- [ ] **Step 7: Run full test suite**

```bash
make test
```

Expected: all 3 new tests pass.

- [ ] **Step 8: Commit**

```bash
git add setup_env.sh tests/setup_env/install_guards.bats tests/mocks/pyenv
git commit -m "refactor: extract setup_ansible_venv() with tests; add pyenv mock"
```

---

## Task 7: `update_pip_packages()` — add python3 mock + tests + extract

**Files:**
- Create: `tests/mocks/python3`
- Modify: `setup_env.sh`
- Modify: `tests/setup_env/install_guards.bats`

- [ ] **Step 1: Create `tests/mocks/python3`**

```bash
#!/usr/bin/env bash
printf "python3 %s\n" "$*" >> "${MOCK_CALLS_FILE:-/tmp/mock_calls}"
exit 0
```

Make it executable: `chmod +x tests/mocks/python3`

- [ ] **Step 2: Add the 2 failing tests**

Append to `tests/setup_env/install_guards.bats`:

```bash
# ── update_pip_packages ──────────────────────────────────────────────────────

@test "update_pip_packages calls pyenv and pip when host var is set" {
  export LAPTOP=1
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${HOME}/.pyenv/bin"
  run update_pip_packages
  grep -q "pyenv shell ansible" "${MOCK_CALLS_FILE}"
  grep -q "python3 -m pip install" "${MOCK_CALLS_FILE}"
}

@test "update_pip_packages skips entirely when no host var is set" {
  unset STUDIO LAPTOP RECEPTION OFFICE HOMES WORKSTATION CRUNCHER RATNA
  run update_pip_packages
  [ "$status" -eq 0 ]
  [ ! -f "${MOCK_CALLS_FILE}" ] || ! grep -q "pyenv" "${MOCK_CALLS_FILE}"
}
```

- [ ] **Step 3: Run tests to confirm they fail**

```bash
make test
```

Expected: `update_pip_packages: command not found` for both new tests.

- [ ] **Step 4: Add `update_pip_packages()` to `setup_env.sh`**

Insert after `setup_ansible_venv()` (before line 860):

```bash
update_pip_packages() {
  printf "Updating pip3 packages\n"
  if [[ -n ${STUDIO-} || -n ${LAPTOP-} || -n ${RECEPTION-} || -n ${OFFICE-} || -n ${HOMES-} || -n ${WORKSTATION-} || -n ${CRUNCHER-} || -n ${RATNA-} ]]; then
    export PYENV_ROOT="$HOME/.pyenv"
    export PATH="$PYENV_ROOT/bin:$PYENV_ROOT/shims:$PATH"

    if command -v pyenv >/dev/null 2>&1; then
      eval "$(pyenv init -)"
      eval "$(pyenv virtualenv-init -)" 2>/dev/null || true
    fi

    pyenv shell ansible 2>/dev/null || true
    PYTHON="$(pyenv which python 2>/dev/null || command -v python3)"

    "$PYTHON" -m pip install -U pip setuptools wheel

    "$PYTHON" - <<'PY'
import json, subprocess, sys

cmd = [sys.executable, "-m", "pip", "list", "--outdated", "--format=json"]
out = subprocess.check_output(cmd, text=True)
pkgs = [p["name"] for p in json.loads(out)]

if pkgs:
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-U", *pkgs])
PY

    "$PYTHON" -m pip check || true
    printf "Updated pip packages\n"
  fi
}

```

- [ ] **Step 5: Replace inline block in main body**

In the `if [[ -n ${UPDATE} ]]; then` block, replace the `printf "Updating pip3 packages\n"` block through the closing `fi` (lines ~2446–2474) with:

```bash
  update_pip_packages
```

- [ ] **Step 6: Validate syntax**

```bash
bash -n setup_env.sh && zsh -n setup_env.sh
```

- [ ] **Step 7: Run full test suite**

```bash
make test
```

Expected: both new tests pass.

- [ ] **Step 8: Commit**

```bash
git add setup_env.sh tests/setup_env/install_guards.bats tests/mocks/python3
git commit -m "refactor: extract update_pip_packages() with tests; add python3 mock"
```

---

## Task 8: `update_git_repos()`

**Files:**
- Modify: `setup_env.sh`
- Modify: `tests/setup_env/install_guards.bats`

- [ ] **Step 1: Add the 4 failing tests**

Append to `tests/setup_env/install_guards.bats`:

```bash
# ── update_git_repos ─────────────────────────────────────────────────────────

@test "update_git_repos pulls oh-my-zsh when dir exists" {
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${HOME}/.oh-my-zsh"
  run update_git_repos
  grep -q "git pull" "${MOCK_CALLS_FILE}"
}

@test "update_git_repos skips oh-my-zsh when dir is absent" {
  export HOME="${BATS_TEST_TMPDIR}/home"
  # no .oh-my-zsh dir
  run update_git_repos
  [ ! -f "${MOCK_CALLS_FILE}" ] || ! grep -q "git pull" "${MOCK_CALLS_FILE}"
}

@test "update_git_repos pulls tpm when dir exists" {
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${HOME}/.tmux/plugins/tpm"
  run update_git_repos
  grep -q "git pull" "${MOCK_CALLS_FILE}"
}

@test "update_git_repos skips tpm when dir is absent" {
  export HOME="${BATS_TEST_TMPDIR}/home"
  # no .tmux dir
  run update_git_repos
  [ ! -f "${MOCK_CALLS_FILE}" ] || ! grep -q "git pull" "${MOCK_CALLS_FILE}"
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
make test
```

Expected: `update_git_repos: command not found` for all 4 new tests.

- [ ] **Step 3: Add `update_git_repos()` to `setup_env.sh`**

Insert after `update_pip_packages()` (before line 860):

```bash
update_git_repos() {
  if [[ -d ${HOME}/.tfenv ]]; then
    printf "Updating tfenv\\n"
    cd ${HOME}/.tfenv || exit
    git pull
    cd ${PERSONAL_GITREPOS}/${DOTFILES} || exit
  fi
  if [[ -d ${HOME}/.oh-my-zsh ]]; then
    printf "Updating oh-my-zsh\\n"
    cd ${HOME}/.oh-my-zsh || exit
    git pull
    cd ${PERSONAL_GITREPOS}/${DOTFILES} || exit
  fi
  if [[ -d ${HOME}/.oh-my-zsh/custom/themes/powerlevel10k ]]; then
    printf "Updating powerlevel10k\\n"
    cd ${HOME}/.oh-my-zsh/custom/themes/powerlevel10k || exit
    git pull
    cd ${PERSONAL_GITREPOS}/${DOTFILES} || exit
  fi
  if [[ -d ${HOME}/.tmux/plugins/tpm ]]; then
    printf "Updating tpm\\n"
    cd ${HOME}/.tmux/plugins/tpm || exit
    git pull
    cd ${PERSONAL_GITREPOS}/${DOTFILES} || exit
  fi
  if [[ -f ${HOME}/bin/cht.sh ]]; then
    printf "Updating cheat.sh\\n"
    curl https://cht.sh/:cht.sh > ~/bin/cht.sh
    chmod 754 ${HOME}/bin/cht.sh
  fi
  if [[ -f ${HOME}/.zsh.d/_cht ]]; then
    printf "Updating cheat.sh tab completion\\n"
    curl https://cheat.sh/:zsh > ${HOME}/.zsh.d/_cht
  fi
  if [[ -d ${HOME}/.oh-my-zsh/custom/plugins/zsh-autosuggestions ]]; then
    printf "Updating zsh-autosuggestions\\n"
    cd ${HOME}/.oh-my-zsh/custom/plugins/zsh-autosuggestions || exit
    git pull
    cd ${PERSONAL_GITREPOS}/${DOTFILES} || exit
  fi
}

```

- [ ] **Step 4: Replace inline blocks in main body**

In the `if [[ -n ${UPDATE} ]]; then` block, replace the section from `if [[ -d ${HOME}/.tfenv ]]; then` through the closing `fi` of the zsh-autosuggestions block (lines ~2477–2515) with:

```bash
  update_git_repos
```

- [ ] **Step 5: Validate syntax**

```bash
bash -n setup_env.sh && zsh -n setup_env.sh
```

- [ ] **Step 6: Run full test suite**

```bash
make test
```

Expected: all 4 new tests pass.

- [ ] **Step 7: Commit**

```bash
git add setup_env.sh tests/setup_env/install_guards.bats
git commit -m "refactor: extract update_git_repos() with tests"
```

---

## Task 9: Extract flat functions (no new tests)

Extract the remaining 8 inline blocks into named functions. No new tests are needed — these are flat install lists or pure side effects. Run `make test` after each to confirm existing tests still pass.

**Files:**
- Modify: `setup_env.sh` only

### 9a: `setup_brewfile_symlink()`

- [ ] **Step 1: Add function after `update_git_repos()` (before line 860)**

```bash
setup_brewfile_symlink() {
  printf "Creating %s\\n" "${BREWFILE_LOC}"
  mkdir -p ${BREWFILE_LOC}
  rm -f ${BREWFILE_LOC}/Brewfile
  ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile ${BREWFILE_LOC}/Brewfile
  if [[ -L ${BREWFILE_LOC}/Brewfile ]]; then
    printf "Brewfile is linked\\n"
  fi
}

```

- [ ] **Step 2: Replace inline block**

In the `if [[ -n ${SETUP} ]] || [[ -n ${DEVELOPER} ]]; then` block, within `if [[ -n ${MACOS} ]]; then`, replace the `printf "Creating %s\\n" "${BREWFILE_LOC}"` block (lines ~997–1004) with:

```bash
    setup_brewfile_symlink
```

### 9b: `setup_vim_plug()`

- [ ] **Step 3: Add function after `setup_brewfile_symlink()`**

```bash
setup_vim_plug() {
  printf "vim plugins setup\\n"
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

- [ ] **Step 4: Replace inline block**

In the `if [[ -n ${SETUP} ]] || [[ -n ${DEVELOPER} ]]; then` block, replace the `printf "vim plugins setup\\n"` block (lines ~2215–2227) with:

```bash
  setup_vim_plug
```

### 9c: `install_macos_casks()`

- [ ] **Step 5: Add function after `setup_vim_plug()`**

The function body is an exact extraction of the macOS casks and mas install block currently inside `if [ -x "$(command -v brew)" ]; then` (lines ~1006–1344). The function signature:

```bash
install_macos_casks() {
  # [exact copy of lines 1006–1344 starting after "elif [ -x "$(command -v brew)" ];"
  #  and ending before the closing "fi" of the brew check]
  ...
}
```

> The function body is ~340 lines — copy it exactly from the current source. The `if ! [ -x "$(command -v brew)" ]; then install_homebrew` / `elif [ -x "$(command -v brew)" ]; then` wrapper stays in the main block; `install_macos_casks` contains everything inside the `elif` arm.

Replace the `elif [ -x "$(command -v brew)" ]; then ... fi` arm in the main block with:

```bash
    elif [ -x "$(command -v brew)" ]; then
      install_macos_casks
    fi
```

### 9d: `install_ubuntu_packages()`

- [ ] **Step 6: Add function after `install_macos_casks()`**

The function body is an exact extraction of the Ubuntu apt/PowerShell install block (lines ~1347–1438) inside `if [[ -n ${UBUNTU} ]]; then`. It includes: `sudo -H apt update`, the FOCAL/JAMMY/NOBLE package install conditionals, WORKSTATION snap packages, BIONIC python, pyenv install, and PowerShell per Ubuntu version.

```bash
install_ubuntu_packages() {
  # [exact copy of lines 1347–1438]
  ...
}
```

Replace the corresponding section in the UBUNTU block with `install_ubuntu_packages`.

### 9e: `install_rhel_packages()`

- [ ] **Step 7: Add function after `install_ubuntu_packages()`**

The function body is an exact extraction of lines ~1981–2122 inside `if [[ -n ${REDHAT} ]] || [[ -n ${FEDORA} ]]; then`.

```bash
install_rhel_packages() {
  # [exact copy of lines 1981–2122]
  ...
}
```

Replace `if [[ -n ${REDHAT} ]] || [[ -n ${FEDORA} ]]; then ... fi` block in main body with:

```bash
  if [[ -n ${REDHAT} ]] || [[ -n ${FEDORA} ]]; then
    install_rhel_packages
  fi
```

### 9f: `install_centos_packages()`

- [ ] **Step 8: Add function after `install_rhel_packages()`**

```bash
install_centos_packages() {
  sudo -H yum update -y
  sudo -H yum install curl -y
  sudo -H yum install gcc -y
  sudo -H yum install git -y
  sudo -H yum install htop -y
  sudo -H yum install iotop -y
  sudo -H yum install keychain -y
  sudo -H yum install make -y
  sudo -H yum install python-setuptools -y
  sudo -H yum install python3-setuptools -y
  sudo -H yum install python3-pip -y
  sudo -H yum install the_silver_searcher -y
  sudo -H yum install unzip -y
  sudo -H yum install wget -y
  sudo -H yum install zsh -y
}

```

Replace `if [[ -n ${CENTOS} ]]; then ... fi` in main body with:

```bash
  if [[ -n ${CENTOS} ]]; then
    install_centos_packages
  fi
```

### 9g: `install_developer_gems()`

- [ ] **Step 9: Add function after `install_centos_packages()`**

The function body is an exact extraction of the Kitchen/gems setup block (lines ~2304–2357), which includes sourcing chruby, switching ruby version, and the `gem install` list.

```bash
install_developer_gems() {
  # [exact copy of lines 2304–2357]
  ...
}
```

Replace `printf "Setup kitchen\\n"` through the `gem install terraspace` block in the DEVELOPER/ANSIBLE section with:

```bash
  install_developer_gems
```

### 9h: `clone_personal_repos()`

- [ ] **Step 10: Add function after `install_developer_gems()`**

```bash
clone_personal_repos() {
  printf "personal git repos cloning\\n"
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

Replace the `printf "personal git repos cloning\\n"` block (lines ~2405–2431) in the DEVELOPER/ANSIBLE section with:

```bash
  clone_personal_repos
```

- [ ] **Step 11: Validate syntax**

```bash
bash -n setup_env.sh && zsh -n setup_env.sh
```

- [ ] **Step 12: Run full test suite**

```bash
make test
```

Expected: all tests pass.

- [ ] **Step 13: Commit**

```bash
git add setup_env.sh
git commit -m "refactor: extract flat install functions (no tests needed)"
```

---

## Task 10: Final Validation and CLAUDE.md Update

- [ ] **Step 1: Confirm line count hasn't grown unexpectedly**

```bash
wc -l setup_env.sh
```

The line count should be roughly unchanged (functions + calls ≈ same total lines as the original inline blocks).

- [ ] **Step 2: Run full syntax check**

```bash
bash -n setup_env.sh && zsh -n setup_env.sh && echo "Syntax OK"
```

Expected: `Syntax OK`

- [ ] **Step 3: Run full test suite and confirm total test count**

```bash
make test
```

Expected: all tests pass; test count in `install_guards.bats` is now the original count + 24.

- [ ] **Step 4: Update CLAUDE.md mock table**

Add the 4 new mocks to the mock table in `CLAUDE.md` under the `tests/mocks/` section. The entries to add:

```markdown
| `MOCK_CALLS_FILE` used by new mocks | `ruby-install`, `rbenv`, `pyenv`, `python3` all log to `MOCK_CALLS_FILE` |
```

Actually, these mocks don't introduce new env vars — they use the existing `MOCK_CALLS_FILE` pattern. Just confirm the mock table comment is accurate. No table change needed.

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: note new mocks in CLAUDE.md after function extraction"
```

---

## Test Count Summary

| File | Before | Added | After |
|---|---|---|---|
| `tests/setup_env/install_guards.bats` | existing | 24 | existing + 24 |
| `tests/setup_env/unit.bats` | 17 | 0 | 17 |
| `tests/mocks/` | 34 files | 4 files | 38 files |
