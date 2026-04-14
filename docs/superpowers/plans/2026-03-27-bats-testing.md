# BATS Testing Infrastructure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add full BATS test coverage to the dotfiles repo with native bats-core installation on macOS/Linux and a Makefile-based test runner.

**Architecture:** Replace the stale npm-managed bats with native `bats-core` (brew on macOS, apt/curl on Linux). Add a sourcing guard to `setup_env.sh` so functions can be loaded in isolation by tests. Tests are organized under `tests/<script>/` and use PATH-based mocks in `tests/mocks/` to stub system commands without modifying real state.

**Tech Stack:** BATS (bats-core ≥1.11), bash, Makefile, PATH-based mock stubs

---

### Task 1: Remove bats from npm and add bats-core to Brewfile

**Files:**

- Modify: `package.json`
- Modify: `Brewfile`

- [ ] **Step 1: Write the test (verify bats is no longer in package.json)**

  There's no automated test for this — it's a config change. Verify manually in Step 4.

- [ ] **Step 2: Remove bats from package.json devDependencies**

  Edit `package.json` to remove the `devDependencies` block entirely (bats was the only entry):

  ```json
  {
    "dependencies": {
      "json2yaml": "^1.1.0"
    }
  }
  ```

- [ ] **Step 3: Add bats-core to Brewfile (alphabetically between `bat` and `bison`)**

  Current lines 6-7 of `Brewfile`:

  ```
  brew "bat"
  brew "bison"
  ```

  Change to:

  ```
  brew "bat"
  brew "bats-core"
  brew "bison"
  ```

- [ ] **Step 4: Update package-lock.json**

  ```bash
  cd /path/to/dotfiles
  npm install
  ```

  Expected: `node_modules/bats/` is removed, `package-lock.json` no longer references bats.

- [ ] **Step 5: Commit**

  ```bash
  git add package.json package-lock.json Brewfile
  git commit -m "chore: replace npm bats with native bats-core install"
  ```

---

### Task 2: Add BATS_VER constant and install_bats() to setup_env.sh

**Files:**

- Modify: `setup_env.sh` (lines 3-4 for constant; after line 343 for function; after line 515 for call)

- [ ] **Step 1: Write the failing test**

  Create `tests/setup_env/install_guards.bats` with a skeleton (full content in Task 8). For now, add just the bats install test to verify it fails:

  ```bash
  #!/usr/bin/env bats

  setup() {
    REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    source "${REPO_ROOT}/tests/helpers/common.bash"
    load_setup_env
    load_mocks
    export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
    export MOCK_WHICH_MISSING=bats
  }

  teardown() {
    rm -f "${MOCK_CALLS_FILE:-}"
  }

  @test "install_bats on Ubuntu calls apt-get install" {
    export UBUNTU=1
    unset REDHAT CENTOS FEDORA
    run install_bats
    [ "$status" -eq 0 ]
    grep -q "apt-get install -y bats" "${MOCK_CALLS_FILE}"
  }
  ```

- [ ] **Step 2: Run test to verify it fails**

  ```bash
  bats tests/setup_env/install_guards.bats
  ```

  Expected: FAIL — `install_bats: command not found` (function doesn't exist yet).

- [ ] **Step 3: Add BATS_VER constant at line 4 of setup_env.sh (before CF_TERRAFORMING_VER)**

  Current line 4:

  ```bash
  CF_TERRAFORMING_VER="0.16.1"
  ```

  Insert before it:

  ```bash
  BATS_VER="1.11.0"
  ```

- [ ] **Step 4: Add install_bats() function to setup_env.sh after install_zsh() (after line 343)**

  Insert after the closing `}` of `install_zsh` (line 343), before `check_and_install_nala()`:

  ```bash
  install_bats() {
    if quiet_which bats; then
      printf "bats already installed\\n"
      return 0
    fi

    printf "Installing bats\\n"

    if [[ -n ${UBUNTU} ]]; then
      sudo -H apt-get install -y bats
    elif [[ -n ${REDHAT} ]] || [[ -n ${CENTOS} ]] || [[ -n ${FEDORA} ]]; then
      curl -fsSL "https://github.com/bats-core/bats-core/archive/refs/tags/v${BATS_VER}.tar.gz" \
        -o /tmp/bats.tar.gz
      tar -xzf /tmp/bats.tar.gz -C /tmp
      sudo -H /tmp/bats-core-${BATS_VER}/install.sh /usr/local
      rm -rf /tmp/bats.tar.gz /tmp/bats-core-${BATS_VER}
    else
      printf "Unsupported platform for bats install\\n"
      return 1
    fi
  }

  ```

- [ ] **Step 5: Add install_bats call in the setup_user block (after line 515)**

  Current lines 513-515:

  ```bash
  if [[ ${MACOS} || ${UBUNTU} || ${FEDORA} || ${CENTOS} ]]; then
    install_zsh
  fi
  ```

  Insert after this block:

  ```bash
  if [[ -n ${LINUX} ]]; then
    install_bats
  fi
  ```

- [ ] **Step 6: Run test again — should still fail (helpers/mocks not created yet)**

  ```bash
  bats tests/setup_env/install_guards.bats
  ```

  Expected: FAIL — `tests/helpers/common.bash: No such file or directory`. Correct — proceed to Task 6 to create helpers.

- [ ] **Step 7: Commit**

  ```bash
  git add setup_env.sh
  git commit -m "feat: add install_bats function and BATS_VER constant"
  ```

---

### Task 3: Add sourcing guard to setup_env.sh

**Files:**

- Modify: `setup_env.sh` (line 396, between end of `process_args` and `[[ $# -eq 0 ]] && usage`)

  The guard must go between line 395 (closing `}` of `process_args`) and line 397 (`[[ $# -eq 0 ]] && usage`). When the file is sourced (by BATS), the guard returns before the main execution body. When run directly, it falls through.

- [ ] **Step 1: Write the failing test**

  Create `tests/setup_env/unit.bats` with a skeleton (full content in Task 7):

  ```bash
  #!/usr/bin/env bats

  setup() {
    REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    source "${REPO_ROOT}/tests/helpers/common.bash"
    load_setup_env
  }

  @test "quiet_which returns 0 for existing command" {
    run quiet_which bash
    [ "$status" -eq 0 ]
  }
  ```

- [ ] **Step 2: Run test to verify it fails**

  ```bash
  bats tests/setup_env/unit.bats
  ```

  Expected: FAIL — sourcing `setup_env.sh` executes the main body and calls `usage` (which calls `exit 0`), so BATS hangs or exits early.

- [ ] **Step 3: Add the sourcing guard**

  Insert between line 395 and line 397 of `setup_env.sh`:

  ```bash
  # Allow sourcing for unit testing without executing the main script body
  [[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0
  ```

  After the edit, lines 394-400 should read:

  ```bash
  done
  }

  # Allow sourcing for unit testing without executing the main script body
  [[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0

  [[ $# -eq 0 ]] && usage
  process_args "$@"
  ```

- [ ] **Step 4: Verify setup_env.sh still works when executed directly**

  ```bash
  bash setup_env.sh
  ```

  Expected output:

  ```
  Usage: setup_env.sh -t <type> [-w]
  Types:
  ...
  ```

  The sourcing guard does not affect direct execution (exits at `[[ $# -eq 0 ]] && usage` as before).

- [ ] **Step 5: Commit**

  ```bash
  git add setup_env.sh
  git commit -m "feat: add sourcing guard to setup_env.sh for unit testing"
  ```

---

### Task 4: Create Makefile

**Files:**

- Create: `Makefile`

- [ ] **Step 1: Write the failing test (manual)**

  No automated test for the Makefile itself. Verify with `make help` in Step 3.

- [ ] **Step 2: Create Makefile**

  ```makefile
  BATS := $(shell command -v bats 2>/dev/null)

  .PHONY: test test-unit help

  help:
  	@printf "Available targets:\n"
  	@printf "  make test       Run all BATS tests\n"
  	@printf "  make test-unit  Run unit tests only\n"
  	@printf "  make help       Show this help\n"

  test:
  ifndef BATS
  	$(error bats not found. Install: brew install bats-core (macOS) or sudo apt-get install bats (Linux))
  endif
  	bats --recursive tests/

  test-unit:
  ifndef BATS
  	$(error bats not found. Install: brew install bats-core (macOS) or sudo apt-get install bats (Linux))
  endif
  	bats tests/setup_env/unit.bats tests/zshrc.d/unit.bats
  ```

  **Important:** The indentation in the Makefile must use a literal TAB character (not spaces).

- [ ] **Step 3: Verify Makefile targets are listed**

  ```bash
  make help
  ```

  Expected:

  ```
  Available targets:
    make test       Run all BATS tests
    make test-unit  Run unit tests only
    make help       Show this help
  ```

- [ ] **Step 4: Commit**

  ```bash
  git add Makefile
  git commit -m "feat: add Makefile with test targets"
  ```

---

### Task 5: Create mock stubs

**Files:**

- Create: `tests/mocks/brew`
- Create: `tests/mocks/apt-get`
- Create: `tests/mocks/sudo`
- Create: `tests/mocks/which`
- Create: `tests/mocks/curl`
- Create: `tests/mocks/tar`
- Create: `tests/mocks/uname`

All mock executables must be `chmod +x`.

- [ ] **Step 1: Create tests/mocks/brew**

  ```bash
  #!/usr/bin/env bash
  printf "brew %s\n" "$*" >> "${MOCK_CALLS_FILE:-/tmp/mock_calls}"

  case "$1" in
    list)
      if [[ "$*" == *"--cask"* ]]; then
        printf "%s\n" ${MOCK_BREW_LIST_CASK:-}
      else
        printf "%s\n" ${MOCK_BREW_LIST_FORMULA:-}
      fi
      exit 0
      ;;
    tap)
      if [[ $# -eq 1 ]]; then
        printf "%s\n" ${MOCK_BREW_TAPS:-}
        exit 0
      fi
      exit "${MOCK_BREW_TAP_EXIT:-0}"
      ;;
    install)
      exit "${MOCK_BREW_INSTALL_EXIT:-0}"
      ;;
    *)
      exit "${MOCK_BREW_EXIT:-0}"
      ;;
  esac
  ```

  ```bash
  chmod +x tests/mocks/brew
  ```

- [ ] **Step 2: Create tests/mocks/apt-get**

  ```bash
  #!/usr/bin/env bash
  printf "apt-get %s\n" "$*" >> "${MOCK_CALLS_FILE:-/tmp/mock_calls}"
  exit "${MOCK_APT_EXIT:-0}"
  ```

  ```bash
  chmod +x tests/mocks/apt-get
  ```

- [ ] **Step 3: Create tests/mocks/sudo**

  Passes all arguments through so the next mock in PATH is invoked:

  ```bash
  #!/usr/bin/env bash
  # Drop -H flag if present; exec remaining args with current PATH (preserves mocks)
  args=()
  for arg in "$@"; do
    [[ "$arg" == "-H" ]] && continue
    args+=("$arg")
  done
  exec "${args[@]}"
  ```

  ```bash
  chmod +x tests/mocks/sudo
  ```

- [ ] **Step 4: Create tests/mocks/which**

  ```bash
  #!/usr/bin/env bash
  if [[ "${MOCK_WHICH_MISSING:-}" == "$1" ]]; then
    exit 1
  fi
  exec /usr/bin/which "$@"
  ```

  ```bash
  chmod +x tests/mocks/which
  ```

- [ ] **Step 5: Create tests/mocks/curl**

  ```bash
  #!/usr/bin/env bash
  printf "curl %s\n" "$*" >> "${MOCK_CALLS_FILE:-/tmp/mock_calls}"
  # Handle -o <file>: create an empty placeholder file
  outfile=""
  while [[ $# -gt 0 ]]; do
    if [[ "$1" == "-o" ]]; then
      outfile="$2"
      shift 2
    else
      shift
    fi
  done
  [[ -n "${outfile}" ]] && touch "${outfile}"
  exit "${MOCK_CURL_EXIT:-0}"
  ```

  ```bash
  chmod +x tests/mocks/curl
  ```

- [ ] **Step 6: Create tests/mocks/tar**

  Creates the expected bats-core directory so the install.sh path exists:

  ```bash
  #!/usr/bin/env bash
  printf "tar %s\n" "$*" >> "${MOCK_CALLS_FILE:-/tmp/mock_calls}"
  # Find -C argument and create stub bats-core directory there
  target=""
  args=("$@")
  for ((i=0; i<${#args[@]}; i++)); do
    if [[ "${args[i]}" == "-C" ]]; then
      target="${args[$((i+1))]}"
      break
    fi
  done
  if [[ -n "${target}" ]] && [[ -n "${MOCK_BATS_VER}" ]]; then
    mkdir -p "${target}/bats-core-${MOCK_BATS_VER}"
    printf '#!/usr/bin/env bash\nprintf "bats installed\n"\n' \
      > "${target}/bats-core-${MOCK_BATS_VER}/install.sh"
    chmod +x "${target}/bats-core-${MOCK_BATS_VER}/install.sh"
  fi
  exit 0
  ```

  ```bash
  chmod +x tests/mocks/tar
  ```

- [ ] **Step 7: Create tests/mocks/uname**

  ```bash
  #!/usr/bin/env bash
  if [[ -n "${MOCK_UNAME_S}" ]] && [[ "$1" == "-s" ]]; then
    printf "%s\n" "${MOCK_UNAME_S}"
    exit 0
  fi
  exec /usr/bin/uname "$@"
  ```

  ```bash
  chmod +x tests/mocks/uname
  ```

- [ ] **Step 8: Commit**

  ```bash
  git add tests/mocks/
  git commit -m "test: add PATH-based mock stubs for brew, apt-get, sudo, which, curl, tar, uname"
  ```

---

### Task 6: Create tests/helpers/common.bash

**Files:**

- Create: `tests/helpers/common.bash`

- [ ] **Step 1: Create the file**

  ```bash
  #!/usr/bin/env bash
  # Shared BATS test helpers

  # Absolute path to repo root (two levels up from tests/helpers/)
  REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

  # Prepend tests/mocks/ to PATH so mock executables shadow real ones
  load_mocks() {
    export PATH="${REPO_ROOT}/tests/mocks:${PATH}"
  }

  # Source setup_env.sh — the sourcing guard prevents main body execution
  load_setup_env() {
    source "${REPO_ROOT}/setup_env.sh"
    export BATS_VER  # export so mock scripts can reference it
  }
  ```

- [ ] **Step 2: Run the unit test skeleton from Task 3 to verify helpers load correctly**

  ```bash
  bats tests/setup_env/unit.bats
  ```

  Expected: PASS — `quiet_which bash` finds bash and returns 0.

- [ ] **Step 3: Commit**

  ```bash
  git add tests/helpers/common.bash
  git commit -m "test: add common.bash test helpers with load_mocks and load_setup_env"
  ```

---

### Task 7: Create tests/setup_env/unit.bats

**Files:**

- Create: `tests/setup_env/unit.bats` (replace skeleton from Task 3)

- [ ] **Step 1: Write the full unit.bats**

  ```bash
  #!/usr/bin/env bats

  setup() {
    REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    source "${REPO_ROOT}/tests/helpers/common.bash"
    load_setup_env
    TMPDIR_TEST="$(mktemp -d)"
  }

  teardown() {
    rm -rf "${TMPDIR_TEST}"
  }

  # ── quiet_which ─────────────────────────────────────────────────────────────

  @test "quiet_which returns 0 for a command that exists" {
    run quiet_which bash
    [ "$status" -eq 0 ]
  }

  @test "quiet_which returns 1 for a command that does not exist" {
    run quiet_which __no_such_command_xyz__
    [ "$status" -eq 1 ]
  }

  @test "quiet_which produces no output" {
    run quiet_which bash
    [ -z "$output" ]
  }

  # ── app_dir_exists ───────────────────────────────────────────────────────────

  @test "app_dir_exists returns 0 when directory exists" {
    run app_dir_exists "${TMPDIR_TEST}"
    [ "$status" -eq 0 ]
  }

  @test "app_dir_exists returns 1 when directory does not exist" {
    run app_dir_exists "${TMPDIR_TEST}/nonexistent"
    [ "$status" -eq 1 ]
  }

  @test "app_dir_exists handles paths with escaped spaces" {
    local dir_with_space="${TMPDIR_TEST}/my app"
    mkdir -p "${dir_with_space}"
    run app_dir_exists "${TMPDIR_TEST}/my\\ app"
    [ "$status" -eq 0 ]
  }

  # ── process_args ────────────────────────────────────────────────────────────

  @test "process_args sets SETUP_USER for -t setup_user" {
    process_args -t setup_user
    [ "${SETUP_USER}" -eq 1 ]
  }

  @test "process_args sets SETUP for -t setup" {
    process_args -t setup
    [ "${SETUP}" -eq 1 ]
  }

  @test "process_args sets DEVELOPER for -t developer" {
    process_args -t developer
    [ "${DEVELOPER}" -eq 1 ]
  }

  @test "process_args sets ANSIBLE for -t ansible" {
    process_args -t ansible
    [ "${ANSIBLE}" -eq 1 ]
  }

  @test "process_args sets UPDATE for -t update" {
    process_args -t update
    [ "${UPDATE}" -eq 1 ]
  }

  @test "process_args sets WORK for -w" {
    process_args -t setup -w
    [ "${WORK}" -eq 1 ]
  }

  # ── version constants ────────────────────────────────────────────────────────

  @test "BATS_VER is set and non-empty" {
    [ -n "${BATS_VER}" ]
  }

  @test "GO_VER is set and non-empty" {
    [ -n "${GO_VER}" ]
  }

  @test "PYTHON_VER is set and non-empty" {
    [ -n "${PYTHON_VER}" ]
  }

  @test "RUBY_VER is set and non-empty" {
    [ -n "${RUBY_VER}" ]
  }

  @test "TERRAFORM_VER matches semver pattern" {
    [[ "${TERRAFORM_VER}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
  }

  @test "BATS_VER matches semver pattern" {
    [[ "${BATS_VER}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
  }
  ```

- [ ] **Step 2: Run tests**

  ```bash
  bats tests/setup_env/unit.bats
  ```

  Expected: all tests PASS.

  Note: the `process_args` tests each run in their own BATS subshell, so `readonly` declarations from one test do not leak into another.

- [ ] **Step 3: Commit**

  ```bash
  git add tests/setup_env/unit.bats
  git commit -m "test: add setup_env unit tests for quiet_which, app_dir_exists, process_args, constants"
  ```

---

### Task 8: Create tests/setup_env/install_guards.bats

**Files:**

- Modify: `tests/setup_env/install_guards.bats` (replace skeleton from Task 2)

- [ ] **Step 1: Write the full install_guards.bats**

  ```bash
  #!/usr/bin/env bats

  setup() {
    REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    source "${REPO_ROOT}/tests/helpers/common.bash"
    load_setup_env
    load_mocks
    export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
    export MOCK_BATS_VER="${BATS_VER}"
  }

  teardown() {
    rm -f "${MOCK_CALLS_FILE:-}"
    rm -rf "/tmp/bats-core-${BATS_VER}" "/tmp/bats.tar.gz"
  }

  # ── brew_formula_installed ───────────────────────────────────────────────────

  @test "brew_formula_installed returns 0 when formula is listed" {
    export MOCK_BREW_LIST_FORMULA="git wget"
    run brew_formula_installed git
    [ "$status" -eq 0 ]
  }

  @test "brew_formula_installed returns 1 when formula is not listed" {
    export MOCK_BREW_LIST_FORMULA="wget"
    run brew_formula_installed git
    [ "$status" -eq 1 ]
  }

  @test "brew_formula_installed uses full-name flag for tap-qualified formulas" {
    export MOCK_BREW_LIST_FORMULA="hashicorp/tap/vault"
    run brew_formula_installed hashicorp/tap/vault
    [ "$status" -eq 0 ]
    grep -q "brew list --formula --full-name" "${MOCK_CALLS_FILE}"
  }

  # ── brew_cask_installed ──────────────────────────────────────────────────────

  @test "brew_cask_installed returns 0 when cask is listed" {
    export MOCK_BREW_LIST_CASK="docker firefox"
    run brew_cask_installed docker
    [ "$status" -eq 0 ]
  }

  @test "brew_cask_installed returns 1 when cask is not listed" {
    export MOCK_BREW_LIST_CASK="firefox"
    run brew_cask_installed docker
    [ "$status" -eq 1 ]
  }

  # ── brew_install_formula ─────────────────────────────────────────────────────

  @test "brew_install_formula calls brew install when formula is absent" {
    export MOCK_BREW_LIST_FORMULA=""
    run brew_install_formula git
    [ "$status" -eq 0 ]
    grep -q "brew install git" "${MOCK_CALLS_FILE}"
  }

  @test "brew_install_formula does not call brew install when formula is present" {
    export MOCK_BREW_LIST_FORMULA="git"
    run brew_install_formula git
    [ "$status" -eq 0 ]
    ! grep -q "brew install git" "${MOCK_CALLS_FILE}"
  }

  # ── brew_tap_if_missing ──────────────────────────────────────────────────────

  @test "brew_tap_if_missing calls brew tap when tap is absent" {
    export MOCK_BREW_TAPS=""
    run brew_tap_if_missing hashicorp/tap
    [ "$status" -eq 0 ]
    grep -q "brew tap hashicorp/tap" "${MOCK_CALLS_FILE}"
  }

  @test "brew_tap_if_missing does not call brew tap when tap is present" {
    export MOCK_BREW_TAPS="hashicorp/tap"
    run brew_tap_if_missing hashicorp/tap
    [ "$status" -eq 0 ]
    # Only one call: the listing call, not a tap add call
    count=$(grep -c "brew tap" "${MOCK_CALLS_FILE}")
    [ "$count" -eq 1 ]
    grep -q "brew tap$" "${MOCK_CALLS_FILE}"
  }

  # ── install_bats ─────────────────────────────────────────────────────────────

  @test "install_bats skips install when bats is already present" {
    unset MOCK_WHICH_MISSING  # which finds bats normally
    export UBUNTU=1
    run install_bats
    [ "$status" -eq 0 ]
    [[ "$output" == *"already installed"* ]]
    ! grep -q "apt-get" "${MOCK_CALLS_FILE}"
  }

  @test "install_bats on Ubuntu calls apt-get install when bats is absent" {
    export MOCK_WHICH_MISSING=bats
    export UBUNTU=1
    unset REDHAT CENTOS FEDORA
    run install_bats
    [ "$status" -eq 0 ]
    grep -q "apt-get install -y bats" "${MOCK_CALLS_FILE}"
  }

  @test "install_bats on RHEL downloads bats-core tarball from GitHub" {
    export MOCK_WHICH_MISSING=bats
    export REDHAT=1
    unset UBUNTU CENTOS FEDORA
    run install_bats
    [ "$status" -eq 0 ]
    grep -q "curl.*bats-core.*${BATS_VER}.*tar.gz" "${MOCK_CALLS_FILE}"
  }

  @test "install_bats returns 1 on unsupported platform" {
    export MOCK_WHICH_MISSING=bats
    unset UBUNTU REDHAT CENTOS FEDORA
    run install_bats
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unsupported platform"* ]]
  }
  ```

- [ ] **Step 2: Run tests**

  ```bash
  bats tests/setup_env/install_guards.bats
  ```

  Expected: all tests PASS.

- [ ] **Step 3: Commit**

  ```bash
  git add tests/setup_env/install_guards.bats
  git commit -m "test: add install_guards tests for brew helpers and install_bats"
  ```

---

### Task 9: Create tests/zshrc.d/unit.bats

**Files:**

- Create: `tests/zshrc.d/unit.bats`

- [ ] **Step 1: Write the failing test**

  ```bash
  #!/usr/bin/env bats

  setup() {
    REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    ZSHRC_D="${REPO_ROOT}/.devcontainer/.config/.zshrc.d"
    source "${REPO_ROOT}/tests/helpers/common.bash"
    load_mocks
  }

  @test "1_init.zsh has valid zsh syntax" {
    run zsh -n "${ZSHRC_D}/1_init.zsh"
    [ "$status" -eq 0 ]
  }
  ```

- [ ] **Step 2: Run test to verify it passes (syntax is valid)**

  ```bash
  bats tests/zshrc.d/unit.bats
  ```

  Expected: PASS.

- [ ] **Step 3: Write the full tests/zshrc.d/unit.bats**

  ```bash
  #!/usr/bin/env bats

  setup() {
    REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    ZSHRC_D="${REPO_ROOT}/.devcontainer/.config/.zshrc.d"
    source "${REPO_ROOT}/tests/helpers/common.bash"
    load_mocks
  }

  # ── syntax checks ────────────────────────────────────────────────────────────

  @test "1_init.zsh has valid zsh syntax" {
    run zsh -n "${ZSHRC_D}/1_init.zsh"
    [ "$status" -eq 0 ]
  }

  @test "2_functions.zsh has valid zsh syntax" {
    run zsh -n "${ZSHRC_D}/2_functions.zsh"
    [ "$status" -eq 0 ]
  }

  @test "3_oh-my-zsh.zsh has valid zsh syntax" {
    run zsh -n "${ZSHRC_D}/3_oh-my-zsh.zsh"
    [ "$status" -eq 0 ]
  }

  @test "4_aliases.zsh has valid zsh syntax" {
    run zsh -n "${ZSHRC_D}/4_aliases.zsh"
    [ "$status" -eq 0 ]
  }

  @test "5_general.zsh has valid zsh syntax" {
    run zsh -n "${ZSHRC_D}/5_general.zsh"
    [ "$status" -eq 0 ]
  }

  @test "6_path.zsh has valid zsh syntax" {
    run zsh -n "${ZSHRC_D}/6_path.zsh"
    [ "$status" -eq 0 ]
  }

  @test "7_final.zsh has valid zsh syntax" {
    run zsh -n "${ZSHRC_D}/7_final.zsh"
    [ "$status" -eq 0 ]
  }

  # ── 1_init.zsh functional tests ──────────────────────────────────────────────

  @test "1_init.zsh sets MACOS=1 on Darwin" {
    run zsh -c "
      export PATH='${REPO_ROOT}/tests/mocks:\${PATH}'
      export MOCK_UNAME_S=Darwin
      source '${ZSHRC_D}/1_init.zsh'
      printf '%s\n' \"\${MACOS}\"
    "
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
  }

  @test "1_init.zsh sets LINUX=1 on Linux" {
    run zsh -c "
      export PATH='${REPO_ROOT}/tests/mocks:\${PATH}'
      export MOCK_UNAME_S=Linux
      source '${ZSHRC_D}/1_init.zsh'
      printf '%s\n' \"\${LINUX}\"
    "
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
  }

  @test "1_init.zsh does not set MACOS on Linux" {
    run zsh -c "
      export PATH='${REPO_ROOT}/tests/mocks:\${PATH}'
      export MOCK_UNAME_S=Linux
      source '${ZSHRC_D}/1_init.zsh'
      printf '%s\n' \"\${MACOS:-unset}\"
    "
    [ "$status" -eq 0 ]
    [ "$output" = "unset" ]
  }
  ```

- [ ] **Step 4: Run all tests**

  ```bash
  bats tests/zshrc.d/unit.bats
  ```

  Expected: all tests PASS.

- [ ] **Step 5: Commit**

  ```bash
  git add tests/zshrc.d/unit.bats
  git commit -m "test: add zshrc.d syntax and platform detection tests"
  ```

---

### Task 10: Run full test suite and verify

- [ ] **Step 1: Run all tests via make**

  ```bash
  make test
  ```

  Expected: all test files run, zero failures. Output resembles:

  ```
  tests/setup_env/unit.bats
   ✓ quiet_which returns 0 for a command that exists
   ✓ quiet_which returns 1 for a command that does not exist
   ...

  tests/setup_env/install_guards.bats
   ✓ brew_formula_installed returns 0 when formula is listed
   ...

  tests/zshrc.d/unit.bats
   ✓ 1_init.zsh has valid zsh syntax
   ...

  N tests, 0 failures
  ```

- [ ] **Step 2: Run unit tests only via make**

  ```bash
  make test-unit
  ```

  Expected: only `unit.bats` files run, zero failures.

- [ ] **Step 3: Verify setup_env.sh still executes correctly when run directly**

  ```bash
  bash setup_env.sh
  ```

  Expected: prints usage and exits 0. The sourcing guard does not affect direct execution.

---

### Task 11: Update CLAUDE.md and README.md

**Files:**

- Modify: `CLAUDE.md`
- Modify: `README.md`

- [ ] **Step 1: Replace the Testing section in CLAUDE.md**

  Current content (lines 119-121):

  ```markdown
  ## Testing

  Uses **BATS** (Bash Automated Testing System) via npm (`node_modules/.bin/bats`).
  ```

  Replace with:

  ````markdown
  ## Testing

  Uses **BATS** (Bash Automated Testing System), installed natively:

  - macOS: `brew install bats-core` (in `Brewfile`)
  - Ubuntu: `sudo apt-get install -y bats` (via `install_bats()` in `setup_env.sh`)
  - RHEL/CentOS/Fedora: direct GitHub release install (via `install_bats()`)

  **Run tests:** `make test`
  **Run unit tests only:** `make test-unit`

  ### Testing Rules

  - Every new function in `setup_env.sh` must have a test in `tests/setup_env/unit.bats` (pure logic) or `tests/setup_env/install_guards.bats` (side effects requiring mocks)
  - Every modification to an existing function must update its test
  - New shell scripts get their own directory under `tests/` (e.g., `tests/scripts/`)
  - Never modify real system state in tests — use PATH-based mocks from `tests/mocks/`
  - `make test` must exit 0 before committing

  ### Mock Pattern

  ```bash
  # In setup():
  load_mocks           # prepends tests/mocks/ to PATH
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  export MOCK_BREW_LIST_FORMULA="git wget"  # controls mock brew list output
  export MOCK_WHICH_MISSING=bats            # makes which return 1 for 'bats'

  # Assert what was called:
  grep -q "brew install git" "${MOCK_CALLS_FILE}"
  ```
  ````

  Available mock env vars:
  | Variable | Effect |
  |---|---|
  | `MOCK_CALLS_FILE` | File where all mock invocations are logged |
  | `MOCK_BREW_LIST_FORMULA` | Space-separated formulas returned by `brew list --formula` |
  | `MOCK_BREW_LIST_CASK` | Space-separated casks returned by `brew list --cask` |
  | `MOCK_BREW_TAPS` | Space-separated taps returned by `brew tap` |
  | `MOCK_BREW_INSTALL_EXIT` | Exit code for `brew install` (default: 0) |
  | `MOCK_BREW_TAP_EXIT` | Exit code for `brew tap <name>` (default: 0) |
  | `MOCK_APT_EXIT` | Exit code for `apt-get` (default: 0) |
  | `MOCK_WHICH_MISSING` | Command name for which `which` returns 1 |
  | `MOCK_CURL_EXIT` | Exit code for `curl` (default: 0) |
  | `MOCK_UNAME_S` | Value returned by `uname -s` |
  | `MOCK_BATS_VER` | BATS_VER used by mock tar to create stub directory |

  ```

  ```

- [ ] **Step 2: Update README.md to add make test**

  Find the testing section of `README.md` (or add one). Add:

  ````markdown
  ## Testing

  ```bash
  make test        # run all BATS tests
  make test-unit   # run unit tests only
  ```
  ````

  Install bats-core first: `brew install bats-core` (macOS) or `sudo apt-get install bats` (Ubuntu).

  ```

  ```

- [ ] **Step 3: Commit**

  ```bash
  git add CLAUDE.md README.md
  git commit -m "docs: expand testing section in CLAUDE.md and README with mock pattern and rules"
  ```

---

## Self-Review

**Spec coverage check:**

| Spec requirement                                                                   | Covered by |
| ---------------------------------------------------------------------------------- | ---------- |
| Remove npm bats, add bats-core natively                                            | Task 1     |
| Brewfile: `brew install bats-core`                                                 | Task 1     |
| `install_bats()` for Ubuntu/RHEL in `setup_env.sh`                                 | Task 2     |
| Sourcing guard for testability                                                     | Task 3     |
| `make test`, `make test-unit`, `make help`                                         | Task 4     |
| `tests/mocks/` with brew, apt-get, sudo, which, curl, tar, uname                   | Task 5     |
| `tests/helpers/common.bash` with `load_mocks()`, `load_setup_env()`                | Task 6     |
| `tests/setup_env/unit.bats` — quiet_which, app_dir_exists, process_args, constants | Task 7     |
| `tests/setup_env/install_guards.bats` — brew helpers + install_bats                | Task 8     |
| `tests/zshrc.d/unit.bats` — syntax + MACOS/LINUX detection                         | Task 9     |
| CLAUDE.md testing section expanded                                                 | Task 11    |
| README.md updated                                                                  | Task 11    |

**No placeholders found.** All code blocks are complete and runnable.

**Type/function consistency check:** All function names used in tests (`quiet_which`, `app_dir_exists`, `process_args`, `brew_formula_installed`, `brew_cask_installed`, `brew_install_formula`, `brew_tap_if_missing`, `brew_tap_installed`, `install_bats`) match their definitions in `setup_env.sh`. All mock env vars referenced in `install_guards.bats` match the variables declared in the mock stub files.
