# Bootstrap Tests Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor `bootstrap_mac.sh` and `bootstrap_linux.sh` per ADR 0006 (sourcing guard, function extraction, no `set -e`, `#!/usr/bin/env bash`) and add comprehensive BATS tests.

**Architecture:** Each bootstrap script is refactored into testable functions with a sourcing guard. A thin `main` function calls them in order with explicit error handling. Tests go in the existing `tests/scripts/unit.bats` using PATH-injected mocks.

**Tech Stack:** Bash, BATS testing, PATH-injected mocks

---

### Task 1: Refactor bootstrap_mac.sh and add tests

**Files:**
- Modify: `scripts/bootstrap_mac.sh`
- Modify: `tests/scripts/unit.bats`

- [ ] **Step 1: Write failing tests for `_bootstrap_check_macos`**

Append to `tests/scripts/unit.bats`:

```bash
# ── bootstrap_mac.sh ─────────────────────────────────────────────────────────

@test "_bootstrap_check_macos passes on Darwin" {
  source "${REPO_ROOT}/scripts/bootstrap_mac.sh"
  export MOCK_UNAME_S=Darwin
  run _bootstrap_check_macos
  [ "$status" -eq 0 ]
}

@test "_bootstrap_check_macos fails on Linux" {
  source "${REPO_ROOT}/scripts/bootstrap_mac.sh"
  export MOCK_UNAME_S=Linux
  run _bootstrap_check_macos
  [ "$status" -eq 1 ]
  [[ "$output" == *"macOS only"* ]]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bats tests/scripts/unit.bats`
Expected: FAIL — `_bootstrap_check_macos: command not found`

- [ ] **Step 3: Write failing tests for `_bootstrap_mac_install_homebrew`**

Append to `tests/scripts/unit.bats`:

```bash
@test "_bootstrap_mac_install_homebrew skips when brew already installed" {
  source "${REPO_ROOT}/scripts/bootstrap_mac.sh"
  run _bootstrap_mac_install_homebrew
  [ "$status" -eq 0 ]
  [[ "$output" == *"already installed"* ]]
  ! grep -q "curl" "${MOCK_CALLS_FILE}"
}

@test "_bootstrap_mac_install_homebrew calls curl when brew missing" {
  source "${REPO_ROOT}/scripts/bootstrap_mac.sh"
  export MOCK_WHICH_MISSING=brew
  run _bootstrap_mac_install_homebrew
  [ "$status" -eq 0 ]
  grep -q "curl" "${MOCK_CALLS_FILE}"
}

@test "_bootstrap_mac_install_homebrew returns error when curl fails" {
  source "${REPO_ROOT}/scripts/bootstrap_mac.sh"
  export MOCK_WHICH_MISSING=brew
  export MOCK_CURL_EXIT=1
  run _bootstrap_mac_install_homebrew
  [ "$status" -ne 0 ]
}
```

- [ ] **Step 4: Write failing tests for `_bootstrap_mac_install_bash5`**

Append to `tests/scripts/unit.bats`:

```bash
@test "_bootstrap_mac_install_bash5 skips when bash >= 5" {
  source "${REPO_ROOT}/scripts/bootstrap_mac.sh"
  # Create a fake bash that reports version 5
  local _mockdir="${BATS_TEST_TMPDIR}/bash5mock"
  mkdir -p "${_mockdir}"
  printf '#!/usr/bin/env bash\nprintf "GNU bash, version 5.2.0(1)-release\\n"\n' > "${_mockdir}/bash"
  chmod +x "${_mockdir}/bash"
  export PATH="${_mockdir}:${PATH}"
  run _bootstrap_mac_install_bash5
  [ "$status" -eq 0 ]
  [[ "$output" == *"already installed"* ]]
  ! grep -q "brew install bash" "${MOCK_CALLS_FILE}"
}

@test "_bootstrap_mac_install_bash5 installs when bash < 5" {
  source "${REPO_ROOT}/scripts/bootstrap_mac.sh"
  # Create a fake bash that reports version 3
  local _mockdir="${BATS_TEST_TMPDIR}/bash3mock"
  mkdir -p "${_mockdir}"
  printf '#!/usr/bin/env bash\nprintf "GNU bash, version 3.2.57(1)-release\\n"\n' > "${_mockdir}/bash"
  chmod +x "${_mockdir}/bash"
  export PATH="${_mockdir}:${PATH}"
  run _bootstrap_mac_install_bash5
  [ "$status" -eq 0 ]
  grep -q "brew install bash" "${MOCK_CALLS_FILE}"
}

@test "_bootstrap_mac_install_bash5 returns error when brew install fails" {
  source "${REPO_ROOT}/scripts/bootstrap_mac.sh"
  local _mockdir="${BATS_TEST_TMPDIR}/bash3mock2"
  mkdir -p "${_mockdir}"
  printf '#!/usr/bin/env bash\nprintf "GNU bash, version 3.2.57(1)-release\\n"\n' > "${_mockdir}/bash"
  chmod +x "${_mockdir}/bash"
  export PATH="${_mockdir}:${PATH}"
  export MOCK_BREW_INSTALL_EXIT=1
  run _bootstrap_mac_install_bash5
  [ "$status" -ne 0 ]
}
```

- [ ] **Step 5: Write failing test for `bootstrap_mac_main`**

Append to `tests/scripts/unit.bats`:

```bash
@test "bootstrap_mac_main calls functions in order on Darwin" {
  source "${REPO_ROOT}/scripts/bootstrap_mac.sh"
  export MOCK_UNAME_S=Darwin
  # bash version mock — report version 5 so install is skipped
  local _mockdir="${BATS_TEST_TMPDIR}/bash5main"
  mkdir -p "${_mockdir}"
  printf '#!/usr/bin/env bash\nprintf "GNU bash, version 5.2.0(1)-release\\n"\n' > "${_mockdir}/bash"
  chmod +x "${_mockdir}/bash"
  export PATH="${_mockdir}:${PATH}"
  run bootstrap_mac_main
  [ "$status" -eq 0 ]
  [[ "$output" == *"Bootstrap complete"* ]]
}

@test "bootstrap_mac_main fails on non-macOS" {
  source "${REPO_ROOT}/scripts/bootstrap_mac.sh"
  export MOCK_UNAME_S=Linux
  run bootstrap_mac_main
  [ "$status" -eq 1 ]
}
```

- [ ] **Step 6: Run all new tests to verify they fail**

Run: `bats tests/scripts/unit.bats`
Expected: All new bootstrap_mac tests FAIL with "command not found"

- [ ] **Step 7: Refactor `scripts/bootstrap_mac.sh`**

Replace the entire file with:

```bash
#!/usr/bin/env bash
# scripts/bootstrap_mac.sh
# Run once on a fresh Mac before setup_env.sh.
# Installs Homebrew and bash 5 — the only two prerequisites for setup_env.sh.

_bootstrap_check_macos() {
  if [[ $(uname -s) != "Darwin" ]]; then
    printf "[ERROR] This script is macOS only.\n" >&2
    return 1
  fi
}

_bootstrap_mac_install_homebrew() {
  if command -v brew &>/dev/null; then
    printf "[INFO]  Homebrew already installed.\n"
    return 0
  fi
  printf "[INFO]  Installing Homebrew...\n"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
}

_bootstrap_mac_setup_brew_path() {
  if [[ -f /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
}

_bootstrap_mac_install_bash5() {
  local _ver
  _ver=$(bash --version | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  local _major="${_ver%%.*}"
  if [[ "${_major:-0}" -ge 5 ]]; then
    printf "[INFO]  bash 5 already installed (version %s).\n" "${_ver}"
    return 0
  fi
  printf "[INFO]  Installing bash 5...\n"
  brew install bash
}

bootstrap_mac_main() {
  _bootstrap_check_macos || return 1
  _bootstrap_mac_install_homebrew || { printf "[ERROR] Homebrew installation failed.\n" >&2; return 1; }
  _bootstrap_mac_setup_brew_path
  _bootstrap_mac_install_bash5 || { printf "[ERROR] bash 5 installation failed.\n" >&2; return 1; }
  printf "[INFO]  Bootstrap complete. You can now run: ./setup_env.sh -t <type>\n"
}

# Allow sourcing for unit testing without executing
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0

bootstrap_mac_main
exit $?
```

- [ ] **Step 8: Run tests to verify they pass**

Run: `bats tests/scripts/unit.bats`
Expected: All tests PASS

- [ ] **Step 9: Run full test suite**

Run: `make test`
Expected: All tests pass (no regressions)

- [ ] **Step 10: Commit**

```bash
git add scripts/bootstrap_mac.sh tests/scripts/unit.bats
git commit -m "feat: refactor bootstrap_mac.sh with testable functions and add tests

Per ADR 0006: #!/usr/bin/env bash, no set -e, sourcing guard,
function extraction. 10 new tests covering OS guard, homebrew
install, bash5 version check, and main orchestration.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 2: Refactor bootstrap_linux.sh and add tests

**Files:**
- Modify: `scripts/bootstrap_linux.sh`
- Modify: `tests/scripts/unit.bats`

- [ ] **Step 1: Write failing tests for `_bootstrap_check_linux`**

Append to `tests/scripts/unit.bats`:

```bash
# ── bootstrap_linux.sh ────────────────────────────────────────────────────────

@test "_bootstrap_check_linux passes on Linux" {
  source "${REPO_ROOT}/scripts/bootstrap_linux.sh"
  export MOCK_UNAME_S=Linux
  run _bootstrap_check_linux
  [ "$status" -eq 0 ]
}

@test "_bootstrap_check_linux fails on Darwin" {
  source "${REPO_ROOT}/scripts/bootstrap_linux.sh"
  export MOCK_UNAME_S=Darwin
  run _bootstrap_check_linux
  [ "$status" -eq 1 ]
  [[ "$output" == *"Linux only"* ]]
}
```

- [ ] **Step 2: Write failing tests for `_bootstrap_linux_detect_distro`**

Append to `tests/scripts/unit.bats`:

```bash
@test "_bootstrap_linux_detect_distro detects Ubuntu" {
  source "${REPO_ROOT}/scripts/bootstrap_linux.sh"
  local _osrel="${BATS_TEST_TMPDIR}/os-release"
  printf 'ID=ubuntu\nID_LIKE=debian\n' > "${_osrel}"
  export _BOOTSTRAP_OS_RELEASE="${_osrel}"
  _bootstrap_linux_detect_distro
  [ "${_DISTRO_FAMILY}" = "ubuntu" ]
}

@test "_bootstrap_linux_detect_distro detects Fedora" {
  source "${REPO_ROOT}/scripts/bootstrap_linux.sh"
  local _osrel="${BATS_TEST_TMPDIR}/os-release"
  printf 'ID=fedora\n' > "${_osrel}"
  export _BOOTSTRAP_OS_RELEASE="${_osrel}"
  _bootstrap_linux_detect_distro
  [ "${_DISTRO_FAMILY}" = "fedora" ]
}

@test "_bootstrap_linux_detect_distro detects RHEL via ID" {
  source "${REPO_ROOT}/scripts/bootstrap_linux.sh"
  local _osrel="${BATS_TEST_TMPDIR}/os-release"
  printf 'ID=rhel\n' > "${_osrel}"
  export _BOOTSTRAP_OS_RELEASE="${_osrel}"
  _bootstrap_linux_detect_distro
  [ "${_DISTRO_FAMILY}" = "rhel" ]
}

@test "_bootstrap_linux_detect_distro detects CentOS via ID_LIKE" {
  source "${REPO_ROOT}/scripts/bootstrap_linux.sh"
  local _osrel="${BATS_TEST_TMPDIR}/os-release"
  printf 'ID=centos\nID_LIKE="rhel fedora"\n' > "${_osrel}"
  export _BOOTSTRAP_OS_RELEASE="${_osrel}"
  _bootstrap_linux_detect_distro
  [ "${_DISTRO_FAMILY}" = "rhel" ]
}

@test "_bootstrap_linux_detect_distro returns unknown for unrecognized distro" {
  source "${REPO_ROOT}/scripts/bootstrap_linux.sh"
  local _osrel="${BATS_TEST_TMPDIR}/os-release"
  printf 'ID=alpine\n' > "${_osrel}"
  export _BOOTSTRAP_OS_RELEASE="${_osrel}"
  _bootstrap_linux_detect_distro
  [ "${_DISTRO_FAMILY}" = "unknown" ]
}

@test "_bootstrap_linux_detect_distro handles missing os-release" {
  source "${REPO_ROOT}/scripts/bootstrap_linux.sh"
  export _BOOTSTRAP_OS_RELEASE="${BATS_TEST_TMPDIR}/nonexistent"
  _bootstrap_linux_detect_distro
  [ "${_DISTRO_FAMILY}" = "unknown" ]
}
```

- [ ] **Step 3: Write failing tests for `_bootstrap_linux_install_prereqs`**

Append to `tests/scripts/unit.bats`:

```bash
@test "_bootstrap_linux_install_prereqs calls apt-get for ubuntu" {
  source "${REPO_ROOT}/scripts/bootstrap_linux.sh"
  _DISTRO_FAMILY="ubuntu"
  run _bootstrap_linux_install_prereqs
  [ "$status" -eq 0 ]
  grep -q "apt-get install" "${MOCK_CALLS_FILE}"
}

@test "_bootstrap_linux_install_prereqs calls dnf for fedora" {
  source "${REPO_ROOT}/scripts/bootstrap_linux.sh"
  _DISTRO_FAMILY="fedora"
  run _bootstrap_linux_install_prereqs
  [ "$status" -eq 0 ]
  grep -q "dnf" "${MOCK_CALLS_FILE}"
}

@test "_bootstrap_linux_install_prereqs calls yum for rhel" {
  source "${REPO_ROOT}/scripts/bootstrap_linux.sh"
  _DISTRO_FAMILY="rhel"
  run _bootstrap_linux_install_prereqs
  [ "$status" -eq 0 ]
  grep -q "yum" "${MOCK_CALLS_FILE}"
}

@test "_bootstrap_linux_install_prereqs prints warning for unknown" {
  source "${REPO_ROOT}/scripts/bootstrap_linux.sh"
  _DISTRO_FAMILY="unknown"
  run _bootstrap_linux_install_prereqs
  [ "$status" -eq 0 ]
  [[ "$output" == *"Unknown distro"* ]]
}

@test "_bootstrap_linux_install_prereqs returns error when apt-get fails" {
  source "${REPO_ROOT}/scripts/bootstrap_linux.sh"
  _DISTRO_FAMILY="ubuntu"
  export MOCK_APT_EXIT=1
  run _bootstrap_linux_install_prereqs
  [ "$status" -ne 0 ]
}
```

- [ ] **Step 4: Write failing tests for `_bootstrap_linux_install_homebrew` and `bootstrap_linux_main`**

Append to `tests/scripts/unit.bats`:

```bash
@test "_bootstrap_linux_install_homebrew skips when brew already installed" {
  source "${REPO_ROOT}/scripts/bootstrap_linux.sh"
  run _bootstrap_linux_install_homebrew
  [ "$status" -eq 0 ]
  [[ "$output" == *"already installed"* ]]
  ! grep -q "curl" "${MOCK_CALLS_FILE}"
}

@test "_bootstrap_linux_install_homebrew calls curl when brew missing" {
  source "${REPO_ROOT}/scripts/bootstrap_linux.sh"
  export MOCK_WHICH_MISSING=brew
  run _bootstrap_linux_install_homebrew
  [ "$status" -eq 0 ]
  grep -q "curl" "${MOCK_CALLS_FILE}"
}

@test "bootstrap_linux_main calls functions in order on Linux" {
  source "${REPO_ROOT}/scripts/bootstrap_linux.sh"
  export MOCK_UNAME_S=Linux
  # Use ubuntu distro for the test
  local _osrel="${BATS_TEST_TMPDIR}/os-release"
  printf 'ID=ubuntu\n' > "${_osrel}"
  export _BOOTSTRAP_OS_RELEASE="${_osrel}"
  run bootstrap_linux_main
  [ "$status" -eq 0 ]
  [[ "$output" == *"Bootstrap complete"* ]]
}

@test "bootstrap_linux_main fails on non-Linux" {
  source "${REPO_ROOT}/scripts/bootstrap_linux.sh"
  export MOCK_UNAME_S=Darwin
  run bootstrap_linux_main
  [ "$status" -eq 1 ]
}
```

- [ ] **Step 5: Run all new tests to verify they fail**

Run: `bats tests/scripts/unit.bats`
Expected: All new bootstrap_linux tests FAIL with "command not found"

- [ ] **Step 6: Refactor `scripts/bootstrap_linux.sh`**

Replace the entire file with:

```bash
#!/usr/bin/env bash
# scripts/bootstrap_linux.sh
# Run once on a fresh Linux machine before setup_env.sh.
# Installs Homebrew prerequisites and Homebrew.

_bootstrap_check_linux() {
  if [[ $(uname -s) != "Linux" ]]; then
    printf "[ERROR] This script is Linux only.\n" >&2
    return 1
  fi
}

_bootstrap_linux_detect_distro() {
  local _osrel="${_BOOTSTRAP_OS_RELEASE:-/etc/os-release}"
  _DISTRO_FAMILY="unknown"

  if [[ -f "${_osrel}" ]]; then
    local ID="" ID_LIKE=""
    # shellcheck disable=SC1090 # path is variable — os-release or test fixture
    . "${_osrel}"
  fi

  if [[ "${ID:-}" == "ubuntu" ]] || [[ "${ID_LIKE:-}" == *"ubuntu"* ]]; then
    _DISTRO_FAMILY="ubuntu"
  elif [[ "${ID:-}" == "fedora" ]] || [[ "${ID_LIKE:-}" == *"fedora"* ]]; then
    _DISTRO_FAMILY="fedora"
  elif [[ "${ID:-}" == "centos" ]] || [[ "${ID:-}" == "rhel" ]] || [[ "${ID_LIKE:-}" == *"rhel"* ]]; then
    _DISTRO_FAMILY="rhel"
  fi
}

_bootstrap_linux_install_prereqs() {
  case "${_DISTRO_FAMILY}" in
    ubuntu)
      printf "[INFO]  Installing Homebrew prerequisites (Ubuntu)...\n"
      sudo apt-get update || return 1
      sudo apt-get install -y build-essential curl file git procps || return 1
      ;;
    fedora)
      printf "[INFO]  Installing Homebrew prerequisites (Fedora)...\n"
      sudo dnf groupinstall -y "Development Tools" || return 1
      sudo dnf install -y curl file git procps-ng || return 1
      ;;
    rhel)
      printf "[INFO]  Installing Homebrew prerequisites (RHEL/CentOS)...\n"
      sudo yum groupinstall -y "Development Tools" || return 1
      sudo yum install -y curl file git procps-ng || return 1
      ;;
    *)
      printf "[WARN]  Unknown distro. Ensure Homebrew prerequisites are installed: build tools, curl, file, git, procps.\n"
      ;;
  esac
}

_bootstrap_linux_install_homebrew() {
  if command -v brew &>/dev/null; then
    printf "[INFO]  Homebrew already installed.\n"
    return 0
  fi
  printf "[INFO]  Installing Homebrew...\n"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
}

_bootstrap_linux_setup_brew_path() {
  if [[ -x /home/linuxbrew/.linuxbrew/bin/brew ]]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
  fi
}

bootstrap_linux_main() {
  _bootstrap_check_linux || return 1
  _bootstrap_linux_detect_distro
  _bootstrap_linux_install_prereqs || { printf "[ERROR] Prerequisite installation failed.\n" >&2; return 1; }
  _bootstrap_linux_install_homebrew || { printf "[ERROR] Homebrew installation failed.\n" >&2; return 1; }
  _bootstrap_linux_setup_brew_path
  printf "[INFO]  Bootstrap complete. You can now run: ./setup_env.sh -t <type>\n"
}

# Allow sourcing for unit testing without executing
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0

bootstrap_linux_main
exit $?
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `bats tests/scripts/unit.bats`
Expected: All tests PASS

- [ ] **Step 8: Run full test suite**

Run: `make test`
Expected: All tests pass (no regressions)

- [ ] **Step 9: Commit**

```bash
git add scripts/bootstrap_linux.sh tests/scripts/unit.bats
git commit -m "feat: refactor bootstrap_linux.sh with testable functions and add tests

Per ADR 0006: no set -e, sourcing guard, function extraction.
Adds _BOOTSTRAP_OS_RELEASE test seam for distro detection.
15 new tests covering OS guard, distro detection (ubuntu/fedora/
rhel/centos/unknown/missing), prereq install, homebrew install,
and main orchestration.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 3: Documentation updates

**Files:**
- Modify: `CLAUDE.md`
- Modify: `docs/superpowers/README.md`

- [ ] **Step 1: Update CLAUDE.md**

Add to the "Test Seams" table in `CLAUDE.md`:

```
| `_BOOTSTRAP_OS_RELEASE` | `_bootstrap_linux_detect_distro` | Path to os-release file; defaults to `/etc/os-release` |
```

- [ ] **Step 2: Update superpowers README.md**

Add row to `docs/superpowers/README.md`:

```
| 2026-04-11 | [bootstrap-tests](plans/2026-04-11-bootstrap-tests.md) | [spec](specs/2026-04-11-bootstrap-tests-design.md) | In Progress |
```

- [ ] **Step 3: Run lint**

Run: `make lint`
Expected: All OK

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md docs/superpowers/README.md
git commit -m "docs: add bootstrap-tests to CLAUDE.md and superpowers index

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage check:**

| Spec requirement | Task |
|---|---|
| Refactor `bootstrap_mac.sh` — shebang, no set -e, sourcing guard, functions | Task 1 |
| Refactor `bootstrap_linux.sh` — shebang, no set -e, sourcing guard, functions | Task 2 |
| `_bootstrap_check_macos` / `_bootstrap_check_linux` | Task 1 / Task 2 |
| `_bootstrap_mac_install_homebrew` / `_bootstrap_linux_install_homebrew` | Task 1 / Task 2 |
| `_bootstrap_mac_setup_brew_path` / `_bootstrap_linux_setup_brew_path` | Task 1 / Task 2 |
| `_bootstrap_mac_install_bash5` with version check via `bash --version` | Task 1 |
| `_bootstrap_linux_detect_distro` with `_BOOTSTRAP_OS_RELEASE` seam | Task 2 |
| `_bootstrap_linux_install_prereqs` per distro | Task 2 |
| `bootstrap_mac_main` / `bootstrap_linux_main` orchestrators | Task 1 / Task 2 |
| Bash version mock | Task 1 (inline per-test mock, not global) |
| OS guard tests | Task 1 / Task 2 |
| Error path tests (curl fails, brew install fails, apt-get fails) | Task 1 / Task 2 |
| Idempotency (skips when already installed) | Task 1 / Task 2 |
| Boundary: missing os-release, unknown distro | Task 2 |
| Docs | Task 3 |

**Placeholder scan:** No TBDs, TODOs, or "implement later" found. All code blocks are complete.

**Type consistency:** Function names match across tasks: `_bootstrap_check_macos`, `_bootstrap_mac_install_homebrew`, `_bootstrap_mac_setup_brew_path`, `_bootstrap_mac_install_bash5`, `bootstrap_mac_main`, `_bootstrap_check_linux`, `_bootstrap_linux_detect_distro`, `_bootstrap_linux_install_prereqs`, `_bootstrap_linux_install_homebrew`, `_bootstrap_linux_setup_brew_path`, `bootstrap_linux_main`. All consistent between test and implementation sections.
