# Secure curl-based Software Installs Implementation Plan

> **Status: DONE** — Merged as PR #162 (2026-06-22)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove all `curl|bash` and unverified `curl|sh` install patterns from the dotfiles Linux path, replacing them with Homebrew formula installs, manual apt-source setups, and content-addressable commit-SHA-pinned URLs.

**Architecture:** Tools that have current Homebrew formulae (pyenv, pyenv-virtualenv, helm, kustomize, cargo-nextest) move to `_install_ubuntu_brew_packages()` via `brew_install_formula`. The oh-my-zsh bootstrap switches from `curl|bash HEAD` to `git clone --depth 1 --branch ${OH_MY_ZSH_VER}`. The Homebrew installer URL in three files switches from `/HEAD/` to a pinned commit SHA. The opentofu curl-piped-installer is replaced with an explicit apt-source setup. Two new version-check helpers track the oh-my-zsh tag and the Homebrew installer SHA.

**Tech Stack:** bash, BATS, `brew_install_formula` helper, GitHub REST API (version resolution), `lib/constants.sh` version pins, `lib/workflows.sh` check-versions framework.

## Global Constraints

- All `apt install` / `apt-get install` / `nala install` calls must include `DEBIAN_FRONTEND=noninteractive`.
- All new functions in `lib/*.sh` must include the sourcing guard (`[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0`) — it is already present in each file; do not remove it.
- Every new helper function must use `|| return 1` (never `|| exit`) inside function bodies.
- `make test` must pass (exit 0) at every commit.
- Commit after each task using `caveman:caveman-commit` to generate the message.
- Feature branch: `feat/secure-curl-installs` — all commits go here, not master.

---

## Session-Level Verification

Run at the end of the plan:

```bash
# 1. No curl|bash patterns remain in lib/ for the target tools
grep -r "pyenv.run\|get-helm-3\|install_kustomize.sh\|nexte.st/latest\|sh.rustup.rs\|install-opentofu.sh" lib/
# expected: no output

# 2. Homebrew installer no longer uses HEAD
grep -r "Homebrew/install/HEAD" lib/ scripts/
# expected: no output

# 3. oh-my-zsh no longer uses curl
grep "curl.*ohmyzsh" lib/helpers.sh
# expected: no output

# 4. All tests pass
make test
# expected: exit 0, count ≥ previous

# 5. New constants present
grep "OH_MY_ZSH_VER\|HOMEBREW_INSTALL_SHA" lib/constants.sh
# expected: both lines printed
```

---

## Task 1: Add OH_MY_ZSH_VER and HOMEBREW_INSTALL_SHA to constants.sh

```yaml-task
id: 1
description: Resolve and pin oh-my-zsh release tag and Homebrew installer commit SHA in lib/constants.sh
role: executor
model: haiku
tdd: not-applicable
acceptance:
  - cmd: grep -q "OH_MY_ZSH_VER=" lib/constants.sh
    exit_code: 0
  - cmd: grep -q "HOMEBREW_INSTALL_SHA=" lib/constants.sh
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 2
files_touched:
  - lib/constants.sh
depends_on: []
parallel_group: wave-1
```

**Why `tdd: not-applicable`:** Pure configuration constant addition — no callable behavior to test via failing test first. Values are fetched and pinned; correctness checked by existence assertion in acceptance.

**Steps:**

- [ ] Fetch the current oh-my-zsh latest release tag:

  ```bash
  curl -fsSL "https://api.github.com/repos/ohmyzsh/ohmyzsh/releases/latest" \
    | grep '"tag_name"' | cut -d'"' -f4
  ```

  Record the output (e.g. `v0.173.0`).

- [ ] Fetch the current Homebrew install master commit SHA:

  ```bash
  curl -fsSL "https://api.github.com/repos/Homebrew/install/commits/master" \
    | grep '"sha"' | head -1 | cut -d'"' -f4
  ```

  Record the full 40-character SHA.

- [ ] Open `lib/constants.sh`. Append the two new constants after the existing block (before any blank trailing line):

  ```bash
  # oh-my-zsh bootstrap tag — update via: ./setup_env.sh -t check-versions --update
  OH_MY_ZSH_VER="<value from step 1>"

  # Homebrew install script commit SHA — content-addressable; HEAD deliberately avoided
  HOMEBREW_INSTALL_SHA="<value from step 2>"
  ```

- [ ] Run `make test` — confirm exit 0.

- [ ] Commit:

  ```bash
  git add lib/constants.sh
  # generate message with caveman:caveman-commit skill, then:
  git commit -m "$(cat <<'EOF'
  chore(constants): pin OH_MY_ZSH_VER and HOMEBREW_INSTALL_SHA

  Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
  EOF
  )"
  ```

---

## Task 2: Brew-migrate pyenv

```yaml-task
id: 2
description: Remove _install_ubuntu_pyenv curl installer; add brew_install_formula pyenv + pyenv-virtualenv to brew section
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: 'grep -q "brew_install_formula pyenv$" lib/linux_ubuntu.sh'
    exit_code: 0
  - cmd: 'grep -q "brew_install_formula pyenv-virtualenv" lib/linux_ubuntu.sh'
    exit_code: 0
  - cmd: 'grep -q "pyenv.run" lib/linux_ubuntu.sh'
    exit_code: 1
  - cmd: 'grep -q "_install_ubuntu_pyenv" lib/linux_ubuntu.sh'
    exit_code: 1
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - lib/linux_ubuntu.sh
  - tests/setup_env/linux_ubuntu.bats
depends_on: [1]
parallel_group: wave-2
```

**Files:**

- `lib/linux_ubuntu.sh` — remove function, remove call from orchestrator, add brew lines
- `tests/setup_env/linux_ubuntu.bats` — remove old curl tests, add brew assertion tests

**Steps:**

- [ ] **RED — write failing tests.** Open `tests/setup_env/linux_ubuntu.bats`. Find the `_install_ubuntu_pyenv` section (line ~122). Replace the two existing `_install_ubuntu_pyenv` tests with:

  ```bash
  @test "_install_ubuntu_brew_packages: installs pyenv via brew" {
    run _install_ubuntu_brew_packages
    [ "$status" -eq 0 ]
    grep -q "brew install pyenv" "${MOCK_CALLS_FILE}"
  }

  @test "_install_ubuntu_brew_packages: installs pyenv-virtualenv via brew" {
    run _install_ubuntu_brew_packages
    [ "$status" -eq 0 ]
    grep -q "brew install pyenv-virtualenv" "${MOCK_CALLS_FILE}"
  }

  @test "_install_ubuntu_brew_packages: does not call pyenv.run curl installer" {
    run _install_ubuntu_brew_packages
    [ "$status" -eq 0 ]
    run grep "pyenv.run" "${MOCK_CALLS_FILE:-/dev/null}"
    [ "$status" -ne 0 ]
  }
  ```

  Run `make test` — confirm the new tests fail (pyenv.run not yet removed, brew lines not yet added).

- [ ] **GREEN — modify production code.** In `lib/linux_ubuntu.sh`:
  1. Delete the entire `_install_ubuntu_pyenv()` function (lines ~50-62, including the closing `}`).
  2. In `install_ubuntu_packages()` (top of file, orchestration list), remove the `_install_ubuntu_pyenv || return 1` line.
  3. In `_install_ubuntu_brew_packages()`, add after `brew_install_formula rbenv`:
     ```bash
     brew_install_formula pyenv
     brew_install_formula pyenv-virtualenv
     ```

- [ ] Run `make test` — confirm all tests pass.

- [ ] Commit with `caveman:caveman-commit`.

---

## Task 3: Brew-migrate helm (no-snap) and kustomize

```yaml-task
id: 3
description: Remove helm get-helm-3 curl and kustomize curl installer blocks; add brew_install_formula for both
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: 'grep -q "brew_install_formula helm" lib/linux_ubuntu.sh'
    exit_code: 0
  - cmd: 'grep -q "brew_install_formula kustomize" lib/linux_ubuntu.sh'
    exit_code: 0
  - cmd: 'grep -q "get-helm-3" lib/linux_ubuntu.sh'
    exit_code: 1
  - cmd: 'grep -q "install_kustomize.sh" lib/linux_ubuntu.sh'
    exit_code: 1
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - lib/linux_ubuntu.sh
  - tests/setup_env/linux_ubuntu.bats
depends_on: [2]
```

**Files:**

- `lib/linux_ubuntu.sh` — remove helm no-snap curl block + kustomize block, add brew lines
- `tests/setup_env/linux_ubuntu.bats` — update helm no-snap test + kustomize tests

**Steps:**

- [ ] **RED — write failing tests.** In `tests/setup_env/linux_ubuntu.bats`, find the `"no HAS_SNAP installs helm via official script"` test (~line 390) and the `"helm script curl failure returns non-zero"` test. Replace both with:

  ```bash
  @test "_install_ubuntu_k8s_tools: no HAS_SNAP installs helm via brew" {
    export HAS_K8S=1
    unset HAS_SNAP
    run _install_ubuntu_k8s_tools
    [ "$status" -eq 0 ]
    grep -q "brew install helm" "${MOCK_CALLS_FILE}"
  }

  @test "_install_ubuntu_k8s_tools: no HAS_SNAP does not call get-helm-3 curl" {
    export HAS_K8S=1
    unset HAS_SNAP
    run _install_ubuntu_k8s_tools
    [ "$status" -eq 0 ]
    run grep "get-helm-3" "${MOCK_CALLS_FILE:-/dev/null}"
    [ "$status" -ne 0 ]
  }

  @test "_install_ubuntu_brew_packages: installs kustomize via brew" {
    run _install_ubuntu_brew_packages
    [ "$status" -eq 0 ]
    grep -q "brew install kustomize" "${MOCK_CALLS_FILE}"
  }

  @test "_install_ubuntu_brew_packages: does not call kustomize curl installer" {
    run _install_ubuntu_brew_packages
    [ "$status" -eq 0 ]
    run grep "install_kustomize.sh" "${MOCK_CALLS_FILE:-/dev/null}"
    [ "$status" -ne 0 ]
  }
  ```

  Also find and remove any existing kustomize test that asserts on the curl pattern. Run `make test` — confirm new tests fail.

- [ ] **GREEN — modify `lib/linux_ubuntu.sh` in `_install_ubuntu_k8s_tools()`.** The function currently has:

  ```bash
  if [[ -n ${HAS_SNAP} ]]; then
    sudo snap install helm --classic
  fi
  # can't use snap on wsl2 ... so use the official installer.
  if [[ -z ${HAS_SNAP} ]]; then
    local _helm_script
    _helm_script="$(mktemp)"
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 -o "${_helm_script}" || ...
    bash "${_helm_script}" || ...
    rm -f "${_helm_script}"
    if [[ -x $(command -v helm) ]]; then ...
    fi
  fi

  printf "Installing kustomize\\n"
  cd ${HOME}/software_downloads || return 1
  local _kustomize_script
  _kustomize_script="$(mktemp)"
  curl -fsSL "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" -o "${_kustomize_script}" || ...
  bash "${_kustomize_script}"
  rm -f "${_kustomize_script}"
  if [[ -f ${HOME}/software_downloads/kustomize ]]; then
    sudo -H mv ...
    sudo chmod 755 ...
    sudo chown root:root ...
    if [[ -x $(command -v kustomize) ]]; then ...
  fi
  ```

  Replace the `if [[ -z ${HAS_SNAP} ]]` helm block with nothing (delete it entirely — snap path already covers HAS_SNAP; brew covers no-snap). Delete the entire kustomize block (all ~12 lines).

- [ ] In `_install_ubuntu_brew_packages()`, add after `brew_install_formula pyenv-virtualenv`:

  ```bash
  brew_install_formula helm
  brew_install_formula kustomize
  ```

- [ ] Run `make test` — confirm all pass.

- [ ] Commit with `caveman:caveman-commit`.

---

## Task 4: Brew-migrate cargo-nextest and configure-only rustup (install path)

```yaml-task
id: 4
description: Remove sh.rustup.rs curl and nextest curl from _install_ubuntu_rust; add brew_install_formula cargo-nextest; function becomes rustup configure-only
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: 'grep -q "brew_install_formula cargo-nextest" lib/linux_ubuntu.sh'
    exit_code: 0
  - cmd: 'grep -q "sh.rustup.rs" lib/linux_ubuntu.sh'
    exit_code: 1
  - cmd: 'grep -q "nexte.st" lib/linux_ubuntu.sh'
    exit_code: 1
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - lib/linux_ubuntu.sh
  - tests/setup_env/linux_ubuntu.bats
depends_on: [3]
```

**Files:**

- `lib/linux_ubuntu.sh` — gut `_install_ubuntu_rust()` curl calls; add brew call
- `tests/setup_env/linux_ubuntu.bats` — update rustup and nextest tests

**Current `_install_ubuntu_rust()` (lines ~105-123):**

```bash
_install_ubuntu_rust() {
  if [[ -n ${HAS_RUST} ]]; then
    printf "Installing Rust Ubuntu\\n"
    if [[ ! -x $(command -v rustc) ]] || [[ ! -x $(command -v cargo) ]]; then
      curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    fi
    if [[ -f ${HOME}/.cargo/env ]]; then
      . ${HOME}/.cargo/env
    fi
    if [[ -x $(command -v rustc) ]] && [[ -x $(command -v cargo) ]]; then
      printf "Rust is installed\\n"
      if ! command -v cargo-nextest &>/dev/null; then
        printf "Installing cargo-nextest\\n"
        curl -LsSf https://get.nexte.st/latest/linux | tar zxf - -C "${HOME}/.cargo/bin"
      fi
    fi
  fi
}
```

**Steps:**

- [ ] **RED — write failing tests.** In `tests/setup_env/linux_ubuntu.bats`, find `_install_ubuntu_rust` tests. Replace or augment:

  ```bash
  @test "_install_ubuntu_rust: HAS_RUST set skips rustup curl (brew provides rustup)" {
    export HAS_RUST=1
    run _install_ubuntu_rust
    [ "$status" -eq 0 ]
    run grep "sh.rustup.rs" "${MOCK_CALLS_FILE:-/dev/null}"
    [ "$status" -ne 0 ]
  }

  @test "_install_ubuntu_brew_packages: installs cargo-nextest via brew" {
    run _install_ubuntu_brew_packages
    [ "$status" -eq 0 ]
    grep -q "brew install cargo-nextest" "${MOCK_CALLS_FILE}"
  }

  @test "_install_ubuntu_rust: does not call nextest curl installer" {
    export HAS_RUST=1
    run _install_ubuntu_rust
    [ "$status" -eq 0 ]
    run grep "nexte.st" "${MOCK_CALLS_FILE:-/dev/null}"
    [ "$status" -ne 0 ]
  }
  ```

  Remove the old test `"HAS_RUST set calls curl for rustup installer"` and `"installs cargo-nextest when rust installed but nextest absent"`. Run `make test` — confirm new tests fail.

- [ ] **GREEN.** Rewrite `_install_ubuntu_rust()` to be configure-only:

  ```bash
  _install_ubuntu_rust() {
    if [[ -n ${HAS_RUST} ]]; then
      printf "Configuring Rust Ubuntu\\n"
      if [[ -f ${HOME}/.cargo/env ]]; then
        # shellcheck disable=SC1090
        . ${HOME}/.cargo/env
      fi
      if command -v rustup &>/dev/null; then
        rustup self update
        rustup update
        rustup component add rust-analyzer
      fi
    fi
  }
  ```

  In `_install_ubuntu_brew_packages()`, add after `brew_install_formula kustomize`:

  ```bash
  brew_install_formula cargo-nextest
  ```

- [ ] Run `make test` — confirm all pass.

- [ ] Commit with `caveman:caveman-commit`.

---

## Task 5: Brew-migrate cargo-nextest update path in developer.sh

```yaml-task
id: 5
description: Remove nextest curl from update_rust() in developer.sh; brew_install_formula cargo-nextest (brew manages updates)
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: 'grep -q "nexte.st" lib/developer.sh'
    exit_code: 1
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - lib/developer.sh
  - tests/setup_env/developer.bats
depends_on: [4]
parallel_group: wave-5
```

**Files:**

- `lib/developer.sh` — remove nextest curl from `update_rust()`; brew already manages nextest updates
- `tests/setup_env/developer.bats` — update "updates nextest" test

**Current `update_rust()` nextest block (lines ~54-56):**

```bash
if [[ ${_rustup_found} -eq 1 ]] && command -v cargo-nextest &>/dev/null; then
  curl -LsSf https://get.nexte.st/latest/linux | tar zxf - -C "${HOME}/.cargo/bin"
fi
```

**Steps:**

- [ ] **RED — write failing tests.** In `tests/setup_env/developer.bats`, find `"update_rust: updates nextest when rustup found and cargo-nextest available"` (line ~82). Replace with:

  ```bash
  @test "update_rust: does not call nextest curl when rustup found (brew manages updates)" {
    export UBUNTU=1
    export HAS_RUST=1
    mkdir -p "${HOME}/.cargo/bin"
    cp "${BATS_TEST_DIRNAME}/../../tests/mocks/rustup" "${HOME}/.cargo/bin/rustup"
    chmod +x "${HOME}/.cargo/bin/rustup"
    printf '#!/usr/bin/env bash\n' > "${HOME}/.cargo/bin/cargo-nextest"
    chmod +x "${HOME}/.cargo/bin/cargo-nextest"
    export PATH="${HOME}/.cargo/bin:${PATH}"
    run update_rust
    [ "$status" -eq 0 ]
    run grep "nexte.st" "${MOCK_CALLS_FILE:-/dev/null}"
    [ "$status" -ne 0 ]
  }
  ```

  Run `make test` — confirm the test fails (curl still called).

- [ ] **GREEN.** In `lib/developer.sh`, delete the nextest block inside `update_rust()`:

  ```bash
  # Delete this entire block:
  if [[ ${_rustup_found} -eq 1 ]] && command -v cargo-nextest &>/dev/null; then
    curl -LsSf https://get.nexte.st/latest/linux | tar zxf - -C "${HOME}/.cargo/bin"
  fi
  ```

  Brew updates `cargo-nextest` automatically during `brew upgrade` — no manual curl needed.

- [ ] Run `make test` — confirm all pass.

- [ ] Commit with `caveman:caveman-commit`.

---

## Task 6: Replace oh-my-zsh curl|bash with git clone at pinned tag

```yaml-task
id: 6
description: Replace bash -c "$(curl -fsSL ohmyzsh installer)" in helpers.sh with git clone --depth 1 --branch ${OH_MY_ZSH_VER}
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: 'grep -q "git clone.*OH_MY_ZSH_VER.*ohmyzsh" lib/helpers.sh'
    exit_code: 0
  - cmd: 'grep "curl.*ohmyzsh" lib/helpers.sh'
    exit_code: 1
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - lib/helpers.sh
  - tests/setup_env/install_guards.bats
depends_on: [1]
parallel_group: wave-2
```

**Files:**

- `lib/helpers.sh` — replace line ~616 `bash -c "$(curl -fsSL ...ohmyzsh...install.sh)"` with git clone
- `tests/setup_env/install_guards.bats` — update "installs oh-my-zsh when not present" test to assert git clone

**Current code in `lib/helpers.sh` (~lines 614-622):**

```bash
  log_info "Installing Oh My ZSH..."
  if [[ ! -d ${HOME}/.oh-my-zsh ]]; then
    bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    if [[ -d ${HOME}/.oh-my-zsh ]]; then
      log_info "Installed Oh My ZSH"
    fi
  fi
```

**Steps:**

- [ ] **RED — write failing test.** In `tests/setup_env/install_guards.bats`, find `"setup_dotfile_symlinks: installs oh-my-zsh when not present"` (~line 652). Add a new test immediately after it:

  ```bash
  @test "setup_dotfile_symlinks: installs oh-my-zsh via git clone at pinned tag" {
    local _home="${BATS_TEST_TMPDIR}/home"
    mkdir -p "${_home}"
    export HOME="${_home}"
    export PERSONAL_GITREPOS="${BATS_TEST_TMPDIR}/git-repos/personal"
    export _OVERRIDE_AI_CONFIG_DIR="${BATS_TEST_TMPDIR}/ai-config"
    mkdir -p "${_OVERRIDE_AI_CONFIG_DIR}/.claude" "${_OVERRIDE_AI_CONFIG_DIR}/.cursor"

    run setup_dotfile_symlinks
    [ "${status}" -eq 0 ]
    grep -q "git clone.*ohmyzsh" "${MOCK_CALLS_FILE}"
    run grep "curl.*ohmyzsh" "${MOCK_CALLS_FILE:-/dev/null}"
    [ "$status" -ne 0 ]
  }
  ```

  Run `make test` — confirm the new test fails (curl still present, git clone not yet used).

- [ ] **GREEN.** In `lib/helpers.sh`, replace the oh-my-zsh install block:

  ```bash
  log_info "Installing Oh My ZSH..."
  if [[ ! -d ${HOME}/.oh-my-zsh ]]; then
    git clone --depth 1 --branch "${OH_MY_ZSH_VER}" \
      https://github.com/ohmyzsh/ohmyzsh.git "${HOME}/.oh-my-zsh"
    if [[ -d ${HOME}/.oh-my-zsh ]]; then
      log_info "Installed Oh My ZSH"
    fi
  fi
  ```

- [ ] Run `make test` — confirm all pass. The existing "installs oh-my-zsh when not present" test still passes because the git clone URL contains "ohmyzsh".

- [ ] Commit with `caveman:caveman-commit`.

---

## Task 7: Pin Homebrew installer URL to commit SHA

```yaml-task
id: 7
description: Replace /HEAD/ with /${HOMEBREW_INSTALL_SHA}/ in all three Homebrew install script fetch calls
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: 'grep -rq "Homebrew/install/HEAD" lib/ scripts/'
    exit_code: 1
  - cmd: 'grep -q "HOMEBREW_INSTALL_SHA" lib/macos.sh'
    exit_code: 0
  - cmd: 'grep -q "HOMEBREW_INSTALL_SHA" scripts/bootstrap_linux.sh'
    exit_code: 0
  - cmd: 'grep -q "HOMEBREW_INSTALL_SHA" scripts/bootstrap_mac.sh'
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - lib/macos.sh
  - scripts/bootstrap_linux.sh
  - scripts/bootstrap_mac.sh
  - tests/setup_env/macos.bats
depends_on: [1]
parallel_group: wave-2
```

**Files:**

- `lib/macos.sh:79` — replace `/HEAD/` with `/${HOMEBREW_INSTALL_SHA}/`
- `scripts/bootstrap_linux.sh:48` — replace `/HEAD/` with `/${HOMEBREW_INSTALL_SHA}/`
- `scripts/bootstrap_mac.sh:20` — replace `/HEAD/` with `/${HOMEBREW_INSTALL_SHA}/`
- `tests/setup_env/macos.bats` — add test asserting URL contains SHA variable, not HEAD

**Current lines:**

- `lib/macos.sh:79`: `_brew_script="$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`
- `scripts/bootstrap_linux.sh:48`: `_install_script=$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)`
- `scripts/bootstrap_mac.sh:20`: `_script=$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)`

**Steps:**

- [ ] **RED — write failing test.** In `tests/setup_env/macos.bats`, find the `install_homebrew` section (~line 73). Add after the existing tests:

  ```bash
  @test "install_homebrew: fetches Homebrew installer at pinned commit SHA not HEAD" {
    export MOCK_UNAME_S=Darwin
    export MOCK_XCODE_SELECT_PRINT_PATH_EXIT=0
    export MOCK_CURL_STDOUT="true"
    run install_homebrew
    [ "$status" -eq 0 ]
    run grep "Homebrew/install/HEAD" "${MOCK_CALLS_FILE:-/dev/null}"
    [ "$status" -ne 0 ]
    grep -q "HOMEBREW_INSTALL_SHA\|${HOMEBREW_INSTALL_SHA}" "${MOCK_CALLS_FILE}"
  }
  ```

  Note: the mock captures curl args, so after the fix the call should contain the SHA value. Run `make test` — confirm the test fails.

- [ ] **GREEN.** Make three substitutions:

  In `lib/macos.sh:79`, change:

  ```bash
  _brew_script="$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || {
  ```

  To:

  ```bash
  _brew_script="$(curl -fsSL "https://raw.githubusercontent.com/Homebrew/install/${HOMEBREW_INSTALL_SHA}/install.sh")" || {
  ```

  In `scripts/bootstrap_linux.sh:48`, change:

  ```bash
  _install_script=$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh) || return 1
  ```

  To:

  ```bash
  _install_script=$(curl -fsSL "https://raw.githubusercontent.com/Homebrew/install/${HOMEBREW_INSTALL_SHA}/install.sh") || return 1
  ```

  In `scripts/bootstrap_mac.sh:20`, change:

  ```bash
  _script=$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh) || return 1
  ```

  To:

  ```bash
  _script=$(curl -fsSL "https://raw.githubusercontent.com/Homebrew/install/${HOMEBREW_INSTALL_SHA}/install.sh") || return 1
  ```

  Note: `HOMEBREW_INSTALL_SHA` is defined in `lib/constants.sh` which is sourced by `setup_env.sh`. For `bootstrap_linux.sh` and `bootstrap_mac.sh`, add a source line at the top if constants.sh is not already sourced; check the existing source chain first:

  ```bash
  head -20 scripts/bootstrap_linux.sh
  head -20 scripts/bootstrap_mac.sh
  ```

  If constants.sh is not sourced, add: `source "$(dirname "${BASH_SOURCE[0]}")/../lib/constants.sh"` near the top.

- [ ] Run `make test` — confirm all pass.

- [ ] Commit with `caveman:caveman-commit`.

---

## Task 8: Replace opentofu piped-installer with manual apt setup

```yaml-task
id: 8
description: Remove curl install-opentofu.sh pipe in _install_ubuntu_terraform; replace with manual GPG key + apt source + apt install
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: 'grep -q "install-opentofu.sh" lib/linux_ubuntu.sh'
    exit_code: 1
  - cmd: 'grep -q "opentofu-archive-keyring.gpg" lib/linux_ubuntu.sh'
    exit_code: 0
  - cmd: 'grep -q "DEBIAN_FRONTEND=noninteractive.*opentofu" lib/linux_ubuntu.sh'
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - lib/linux_ubuntu.sh
  - tests/setup_env/linux_ubuntu.bats
depends_on: [4]
parallel_group: wave-5
```

**Files:**

- `lib/linux_ubuntu.sh` — replace opentofu curl-pipe block with apt-source setup
- `tests/setup_env/linux_ubuntu.bats` — update opentofu install test

**Current code (lines ~509-516):**

```bash
if ! command -v tofu &>/dev/null; then
  printf "Installing opentofu\\n"
  curl -fsSL https://get.opentofu.org/install-opentofu.sh | sudo sh -s -- --install-method deb
  if command -v tofu &>/dev/null; then
    printf "opentofu is installed\\n"
  fi
else
  printf "opentofu already installed\\n"
fi
```

**Replacement:**

```bash
if ! command -v tofu &>/dev/null; then
  printf "Installing opentofu\\n"
  curl -fsSL https://packages.opentofu.org/opentofu/tofu/gpgkey \
    | sudo gpg --dearmor -o /etc/apt/keyrings/opentofu-archive-keyring.gpg
  printf "deb [signed-by=/etc/apt/keyrings/opentofu-archive-keyring.gpg] https://packages.opentofu.org/opentofu/tofu/any/ any main\n" \
    | sudo DEBIAN_FRONTEND=noninteractive tee /etc/apt/sources.list.d/opentofu.list > /dev/null
  sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y opentofu
  if command -v tofu &>/dev/null; then
    printf "opentofu is installed\\n"
  fi
else
  printf "opentofu already installed\\n"
fi
```

**Steps:**

- [ ] **RED — write failing tests.** In `tests/setup_env/linux_ubuntu.bats`, find the opentofu test section. Add/replace with:

  ```bash
  @test "_install_ubuntu_terraform: opentofu absent installs via apt (not piped sh)" {
    unset HAS_K8S
    run _install_ubuntu_terraform
    [ "$status" -eq 0 ]
    grep -q "DEBIAN_FRONTEND=noninteractive.*apt-get install.*opentofu" "${MOCK_CALLS_FILE}"
    run grep "install-opentofu.sh" "${MOCK_CALLS_FILE:-/dev/null}"
    [ "$status" -ne 0 ]
  }

  @test "_install_ubuntu_terraform: opentofu apt setup adds GPG key" {
    unset HAS_K8S
    run _install_ubuntu_terraform
    [ "$status" -eq 0 ]
    grep -q "opentofu-archive-keyring.gpg" "${MOCK_CALLS_FILE}"
  }
  ```

  Run `make test` — confirm tests fail.

- [ ] **GREEN.** Replace the opentofu block in `lib/linux_ubuntu.sh` with the new apt-source pattern shown above.

- [ ] Run `make test` — confirm all pass.

- [ ] Commit with `caveman:caveman-commit`.

---

## Task 9: Add check-versions integration for oh-my-zsh and Homebrew SHA

```yaml-task
id: 9
description: Add _check_cv_oh_my_zsh and _check_cv_homebrew_install functions to workflows.sh; call both in run_check_versions
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: 'grep -q "_check_cv_oh_my_zsh" lib/workflows.sh'
    exit_code: 0
  - cmd: 'grep -q "_check_cv_homebrew_install" lib/workflows.sh'
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - lib/workflows.sh
  - tests/setup_env/workflows.bats
depends_on: [1, 6, 7, 8]
```

**Files:**

- `lib/workflows.sh` — add two new check functions; call them at the end of `run_check_versions`
- `tests/setup_env/workflows.bats` — add tool-inclusion tests and function-behavior tests

**New functions to add in `lib/workflows.sh`, after the existing `_check_one_version` definition and before `run_check_versions`:**

```bash
_check_cv_oh_my_zsh() {
  local _latest _pinned="${OH_MY_ZSH_VER}"
  _latest=$(curl -fsSL "https://api.github.com/repos/ohmyzsh/ohmyzsh/releases/latest" \
    2>/dev/null | grep '"tag_name"' | cut -d'"' -f4)
  if [[ -z "${_latest}" ]]; then
    printf "  [WARN]     %-14s could not fetch latest version\n" "oh-my-zsh"
    _warned=$(( _warned + 1 ))
    return 0
  fi
  if [[ "${_pinned}" == "${_latest}" ]]; then
    printf "  [OK]       %-14s pinned=%-10s latest=%s\n" "oh-my-zsh" "${_pinned}" "${_latest}"
    _ok=$(( _ok + 1 ))
  else
    printf "  [OUTDATED] %-14s pinned=%-10s latest=%s\n" "oh-my-zsh" "${_pinned}" "${_latest}"
    _outdated=$(( _outdated + 1 ))
    if [[ -n ${UPDATE_VERSIONS:-} ]]; then
      _prompt_version_update "oh-my-zsh" "OH_MY_ZSH_VER" "${_pinned}" "${_latest}"
    fi
  fi
}

_check_cv_homebrew_install() {
  local _latest _pinned="${HOMEBREW_INSTALL_SHA}"
  _latest=$(curl -fsSL "https://api.github.com/repos/Homebrew/install/commits/master" \
    2>/dev/null | grep '"sha"' | head -1 | cut -d'"' -f4)
  if [[ -z "${_latest}" ]]; then
    printf "  [WARN]     %-14s could not fetch latest SHA\n" "homebrew-install"
    _warned=$(( _warned + 1 ))
    return 0
  fi
  local _pin_short="${_pinned:0:12}" _latest_short="${_latest:0:12}"
  if [[ "${_pinned}" == "${_latest}" ]]; then
    printf "  [OK]       %-14s pinned=%s latest=%s\n" "homebrew-install" "${_pin_short}" "${_latest_short}"
    _ok=$(( _ok + 1 ))
  else
    printf "  [OUTDATED] %-14s pinned=%s latest=%s\n" "homebrew-install" "${_pin_short}" "${_latest_short}"
    _outdated=$(( _outdated + 1 ))
    if [[ -n ${UPDATE_VERSIONS:-} ]]; then
      _prompt_version_update "homebrew-install" "HOMEBREW_INSTALL_SHA" "${_pinned}" "${_latest}"
    fi
  fi
}
```

**In `run_check_versions()`, add two calls at the end of the `_run_cv_check` block (before the `printf "\n%d outdated..."` summary line):**

```bash
_check_cv_oh_my_zsh
_check_cv_homebrew_install
```

Note: `_check_cv_oh_my_zsh` and `_check_cv_homebrew_install` reference `_warned`, `_ok`, `_outdated` — these are declared as locals in `run_check_versions`. The new functions must be defined outside `run_check_versions` (unlike `_run_cv_check` which is nested); they access the counters via the dynamic scoping of bash locals when called from within the outer function. Verify this works by checking the existing pattern: bash `local` variables are visible to functions called from the same shell (not a subshell) — calling `_check_cv_oh_my_zsh` directly (no `run`, no `$(...)`) keeps it in the same shell context.

**Steps:**

- [ ] **RED — write failing tests.** In `tests/setup_env/workflows.bats`, after the `"run_check_versions checks gitleaks version"` test (~line 843), add:

  ```bash
  @test "run_check_versions checks oh-my-zsh tag" {
    local _checked="${BATS_TEST_TMPDIR}/checked"
    _check_cv_oh_my_zsh() { printf "oh-my-zsh\n" >> "${_checked}"; }
    run_check_versions
    grep -q "oh-my-zsh" "${_checked}"
  }

  @test "run_check_versions checks homebrew-install SHA" {
    local _checked="${BATS_TEST_TMPDIR}/checked"
    _check_cv_homebrew_install() { printf "homebrew-install\n" >> "${_checked}"; }
    run_check_versions
    grep -q "homebrew-install" "${_checked}"
  }

  @test "_check_cv_oh_my_zsh emits OK when pinned matches latest" {
    local _ok=0 _outdated=0 _warned=0
    OH_MY_ZSH_VER="v0.173.0"
    curl() { printf '{"tag_name":"v0.173.0"}'; }
    export -f curl
    _check_cv_oh_my_zsh
    [[ "${_ok}" -eq 1 ]]
  }

  @test "_check_cv_oh_my_zsh emits OUTDATED when pinned differs from latest" {
    local _ok=0 _outdated=0 _warned=0
    OH_MY_ZSH_VER="v0.170.0"
    curl() { printf '{"tag_name":"v0.173.0"}'; }
    export -f curl
    local _out
    _out=$(_check_cv_oh_my_zsh 2>&1)
    [[ "${_out}" == *"[OUTDATED]"* ]]
  }

  @test "_check_cv_homebrew_install emits OK when SHA matches" {
    local _ok=0 _outdated=0 _warned=0
    HOMEBREW_INSTALL_SHA="abc123abc123abc123abc123abc123abc123abc1"
    curl() { printf '{"sha":"abc123abc123abc123abc123abc123abc123abc1","commit":{}}'; }
    export -f curl
    _check_cv_homebrew_install
    [[ "${_ok}" -eq 1 ]]
  }

  @test "_check_cv_homebrew_install emits OUTDATED when SHA differs" {
    local _ok=0 _outdated=0 _warned=0
    HOMEBREW_INSTALL_SHA="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    curl() { printf '{"sha":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","commit":{}}'; }
    export -f curl
    local _out
    _out=$(_check_cv_homebrew_install 2>&1)
    [[ "${_out}" == *"[OUTDATED]"* ]]
  }
  ```

  Run `make test` — confirm tests fail (`_check_cv_oh_my_zsh` and `_check_cv_homebrew_install` not yet defined).

- [ ] **GREEN.** Add the two functions to `lib/workflows.sh` as shown above, then add their calls in `run_check_versions`.

- [ ] Run `make test` — confirm all pass.

- [ ] Commit with `caveman:caveman-commit`.

---

## Task 10: Open PR and update superpowers README

```yaml-task
id: 10
description: Open PR for feat/secure-curl-installs branch; update docs/superpowers/README.md plan status (docs-only)
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: 'gh pr view --json state -q .state 2>/dev/null | grep -q "OPEN"'
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 2
files_touched:
  - docs/superpowers/README.md
depends_on: [5, 6, 7, 8, 9]
```

**Why `tdd: not-applicable`:** PR creation and index update are operational/docs steps with no testable behavior to capture in a failing test first.

**Steps:**

- [ ] Run `make test` from the worktree root — confirm exit 0 and test count ≥ previous.

- [ ] Run session-level verification commands (from top of plan) — confirm all pass.

- [ ] Update `docs/superpowers/README.md`: set the 2026-06-21 row's Plan column and Status:
  - Add plan link: `[secure-curl-installs](plans/2026-06-21-secure-curl-installs.md)`
  - Change status from `Pending` to `In Progress`

- [ ] Commit the README update with `caveman:caveman-commit`.

- [ ] Open PR:

  ```bash
  gh pr create \
    --title "feat(security): replace curl|bash installs with brew/apt/SHA-pin" \
    --body "$(cat <<'EOF'
  ## Summary
  - Migrate pyenv, helm (no-snap), kustomize, cargo-nextest, and rustup-initial-install
    from curl|bash to Homebrew formula installs on Linux
  - Replace oh-my-zsh `curl|bash HEAD` bootstrap with `git clone --depth 1 --branch OH_MY_ZSH_VER`
  - Replace Homebrew installer URL `/HEAD/` with pinned commit SHA in three files
  - Replace opentofu piped-installer with explicit apt-source setup
  - Add `_check_cv_oh_my_zsh` and `_check_cv_homebrew_install` to check-versions framework
  - Pin `OH_MY_ZSH_VER` and `HOMEBREW_INSTALL_SHA` in `lib/constants.sh`

  ## Test plan
  - [ ] `make test` passes, count ≥ previous
  - [ ] `grep -r "pyenv.run\|get-helm-3\|install_kustomize.sh\|nexte.st/latest\|sh.rustup.rs\|install-opentofu.sh" lib/` returns no output
  - [ ] `grep -r "Homebrew/install/HEAD" lib/ scripts/` returns no output
  - [ ] `grep "curl.*ohmyzsh" lib/helpers.sh` returns no output
  - [ ] CI passes

  🤖 Generated with [Claude Code](https://claude.ai/claude-code)
  EOF
  )"
  ```

- [ ] Monitor CI: `gh pr checks <number> --watch`
