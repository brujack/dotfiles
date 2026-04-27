# Bash/BATS Coverage Gate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add per-file kcov coverage floors to all bash source files (`setup_env.sh` + `lib/*.sh`), enforce them in CI via a new `bash-coverage` job, and document figures in `CLAUDE.md`.

**Architecture:** A new `scripts/run-coverage.sh` script runs kcov over the full BATS suite, parses per-file JSON from `coverage/kcov-merged/index.json`, checks each file against a hardcoded floor (90% cross-platform, 75% platform-specific), prints a pass/fail table, and exits 1 on failure. A `make coverage` target calls this script; kcov is skipped gracefully if absent locally (CI always has it). A new `bash-coverage` CI job enforces the gate on every PR. `make test` is unchanged.

**Tech Stack:** bash, BATS 1.13, kcov (Ubuntu apt), jq, GitHub Actions (ubuntu-latest).

---

## File Map

| File                         | Action                                                             |
| ---------------------------- | ------------------------------------------------------------------ |
| `scripts/run-coverage.sh`    | Create — kcov runner + per-file gate                               |
| `Makefile`                   | Modify — add `coverage` target + `.PHONY` + `help` entry           |
| `.gitignore`                 | Modify — add `coverage/`                                           |
| `.github/workflows/ci.yml`   | Modify — add `bash-coverage` job; later add to `auto-merge needs:` |
| `tests/setup_env/macos.bats` | Create — coverage for `lib/macos.sh`                               |
| `tests/setup_env/linux.bats` | Create — coverage for untested `lib/linux.sh` paths                |
| `CLAUDE.md`                  | Modify — add "Bash Coverage" subsection with per-file table        |

---

## Phase 1: Infrastructure

### Task 0: Verify baseline

**Files:** none

- [ ] **Step 1: Confirm current tests pass**

```bash
make test
```

Run from the repo root (`~/git-repos/personal/dotfiles`). Expected: all BATS tests pass, exit 0.

- [ ] **Step 2: Confirm clean branch**

```bash
git status
git branch
```

Expected: on `spec/bash-coverage-gate`, working tree clean.

---

### Task 1: Create `scripts/run-coverage.sh` (measurement mode — no gate yet)

**Files:**

- Create: `scripts/run-coverage.sh`

- [ ] **Step 1: Create the script**

```bash
cat > scripts/run-coverage.sh << 'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${REPO_ROOT}/coverage"

declare -A FLOORS=(
  ["setup_env.sh"]=90
  ["constants.sh"]=90
  ["detect_env.sh"]=90
  ["helpers.sh"]=90
  ["workflows.sh"]=90
  ["update_summary.sh"]=90
  ["developer.sh"]=90
  ["linux.sh"]=75
  ["macos.sh"]=75
)

INCLUDE_PATH="${REPO_ROOT}/setup_env.sh:${REPO_ROOT}/lib"

rm -rf "${OUTPUT_DIR}"
kcov --include-path="${INCLUDE_PATH}" "${OUTPUT_DIR}" bats --recursive "${REPO_ROOT}/tests/"

INDEX="${OUTPUT_DIR}/kcov-merged/index.json"
if [[ ! -f "${INDEX}" ]]; then
  printf "ERROR: kcov did not produce %s — verify kcov >= 38\n" "${INDEX}" >&2
  exit 1
fi

failed=0
printf "\n%-30s %10s %10s %10s\n" "File" "Coverage" "Floor" "Status"
printf "%-30s %10s %10s %10s\n" "----" "--------" "-----" "------"

while IFS= read -r file_json; do
  filepath=$(printf '%s' "${file_json}" | jq -r '.file')
  percent=$(printf '%s' "${file_json}" | jq -r '.percent_covered')
  basename="${filepath##*/}"
  floor="${FLOORS[${basename}]:-90}"
  pct_int=$(printf '%.0f' "${percent}")
  if [[ "${pct_int}" -lt "${floor}" ]]; then
    status="FAIL"
    failed=1
  else
    status="PASS"
  fi
  printf "%-30s %9s%% %9s%% %10s\n" "${basename}" "${pct_int}" "${floor}" "${status}"
done < <(jq -c '.files[]' "${INDEX}")

# Gate not yet enabled — measurement mode only
if [[ "${failed}" -ne 0 ]]; then
  printf "\nFiles below floor noted above (gate will be enabled after floors are met)\n"
fi
printf "\nCoverage measurement complete\n"
SCRIPT
chmod +x scripts/run-coverage.sh
```

- [ ] **Step 2: Verify the script is syntactically valid**

```bash
bash -n scripts/run-coverage.sh
```

Expected: no output, exit 0.

---

### Task 2: Update Makefile and `.gitignore`

**Files:**

- Modify: `Makefile`
- Modify: `.gitignore`

- [ ] **Step 1: Add `coverage/` to `.gitignore`**

Add this line after `powershell/coverage.xml`:

```
# bash/kcov coverage output
coverage/
```

- [ ] **Step 2: Update Makefile**

Replace the existing Makefile with this version (adds `KCOV`, `coverage` target, updated `.PHONY`, updated `help`):

```makefile
BATS := $(shell command -v bats 2>/dev/null)
SHELLCHECK := $(shell command -v shellcheck 2>/dev/null)
KCOV := $(shell command -v kcov 2>/dev/null)
SHELL_FILES := $(shell find . -name "*.sh" -not -path "*/node_modules/*" -not -path "*/.cursor/plugins/cache/*")

.PHONY: test test-unit lint coverage install-hooks help

help:
	@printf "Available targets:\n"
	@printf "  make test       Run all BATS tests\n"
	@printf "  make test-unit  Run unit tests only\n"
	@printf "  make lint       Check bash/zsh syntax + ShellCheck all .sh files\n"
	@printf "  make coverage   Run kcov coverage gate (requires kcov; CI-enforced)\n"
	@printf "  make install-hooks Install pre-commit and pre-push hooks (run once per checkout)\n"
	@printf "  make help       Show this help\n"

lint:
	@failed=0; \
	for f in $(SHELL_FILES); do \
	  bash -n "$$f" && printf "bash  OK  %s\n" "$$f" || { printf "bash FAIL %s\n" "$$f"; failed=1; }; \
	  zsh  -n "$$f" && printf "zsh   OK  %s\n" "$$f" || { printf "zsh  FAIL %s\n" "$$f"; failed=1; }; \
	done; \
	if [ -n "$(SHELLCHECK)" ]; then \
	  shellcheck $(SHELL_FILES) && printf "shellcheck OK\n" || { printf "shellcheck FAIL\n"; failed=1; }; \
	else \
	  printf "shellcheck not found, skipping (install: brew install shellcheck)\n"; \
	fi; \
	exit $$failed

test: lint
ifndef BATS
	$(error bats not found. Install: brew install bats-core (macOS) or sudo apt-get install bats (Linux))
endif
	bats --recursive tests/

coverage:
ifeq ($(KCOV),)
	@printf "kcov not found — skipping coverage (CI enforces the gate). Install: brew install kcov\n"
else
	@bash scripts/run-coverage.sh
endif

install-hooks:
	ln -sf "$(shell pwd)/scripts/pre-commit-hook.sh" .git/hooks/pre-commit
	ln -sf "$(shell pwd)/scripts/pre-push" .git/hooks/pre-push
	@printf "Pre-commit and pre-push hooks installed\n"

test-unit:
ifndef BATS
	$(error bats not found. Install: brew install bats-core (macOS) or sudo apt-get install bats (Linux))
endif
	bats tests/setup_env/unit.bats tests/setup_env/profiles.bats tests/zshrc.d/unit.bats
```

- [ ] **Step 3: Verify Makefile is valid**

```bash
make help
```

Expected: help text with all five targets listed including `coverage`.

- [ ] **Step 4: Verify `make test` still passes**

```bash
make test
```

Expected: lint + all BATS tests pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/run-coverage.sh Makefile .gitignore
git commit -m "feat: add bash coverage measurement script and make target

Measurement mode only — gate (exit 1) will be enabled after floors are met.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 3: Add `bash-coverage` CI job (non-blocking)

**Files:**

- Modify: `.github/workflows/ci.yml`

The job is added to the workflow but NOT yet added to `auto-merge needs:` — that happens in Task 9 after the gate is enabled.

- [ ] **Step 1: Add `bash-coverage` job**

In `.github/workflows/ci.yml`, insert this new job between the `powershell:` job and the `secret-scan:` job:

```yaml
bash-coverage:
  runs-on: ubuntu-latest
  env:
    FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: "true"
  steps:
    - uses: actions/checkout@v5

    - name: Install dependencies
      run: sudo apt-get install -y bats shellcheck zsh kcov jq

    - name: Run coverage gate
      run: make coverage
```

**Important:** Do NOT modify the `auto-merge needs:` line yet. It still reads:

```yaml
needs: [test, lint-macos, powershell, secret-scan]
```

- [ ] **Step 2: Verify YAML is valid**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))" && echo "YAML OK"
```

Expected: `YAML OK`

- [ ] **Step 3: Commit and push**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: add bash-coverage job (non-blocking — gate not yet enabled)

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
git push -u origin spec/bash-coverage-gate
```

---

### Task 4: Create PR and capture baseline

**Files:** none

- [ ] **Step 1: Create PR**

```bash
gh pr create \
  --title "feat: bash/BATS coverage gate (>=90%/75% per-file floors)" \
  --body "$(cat <<'EOF'
## Summary
- Adds kcov coverage measurement for all bash source files
- Per-file floors: 90% (cross-platform), 75% (linux.sh, macos.sh)
- New \`bash-coverage\` CI job; gate enabled after floors are met
- New \`make coverage\` target (skips gracefully if kcov absent locally)

## Test plan
- [ ] bash-coverage CI job passes (measurement mode — not gating yet)
- [ ] All existing BATS tests continue to pass
- [ ] Coverage table visible in bash-coverage job logs
EOF
)"
```

- [ ] **Step 2: Wait for CI to complete**

```bash
gh pr checks
```

Wait until `bash-coverage` shows `pass`.

- [ ] **Step 3: Read baseline coverage from CI logs**

```bash
gh run list --branch spec/bash-coverage-gate --json databaseId,name --jq '.[0].databaseId'
# Use the run ID to get the bash-coverage job log:
gh run view <RUN_ID> --log | grep -A 20 "Coverage measurement complete"
```

Expected output looks like:

```
File                           Coverage      Floor    Status
----                           --------      -----    ------
setup_env.sh                        82%        90%      FAIL
constants.sh                        95%        90%      PASS
detect_env.sh                       88%        90%      FAIL
helpers.sh                          91%        90%      PASS
workflows.sh                        92%        90%      PASS
update_summary.sh                   87%        90%      FAIL
developer.sh                        78%        90%      FAIL
linux.sh                            61%        75%      FAIL
macos.sh                            12%        75%      FAIL
```

- [ ] **Step 4: Record the baseline**

Note each file's percentage. Any file showing `FAIL` needs new tests before the gate is enabled. Files showing `PASS` are already meeting their floor — no test work needed for those.

**If ALL files show `PASS`:** skip Tasks 5–7, go straight to Task 8 (enable the gate).

**If any file shows `PASS` already above its floor:** note which ones — do not add tests for those files.

---

## Phase 2: Fill coverage gaps

### Task 5: Add `tests/setup_env/macos.bats`

**Files:**

- Create: `tests/setup_env/macos.bats`

This task is always needed — `lib/macos.sh` is almost certainly below 75% because macOS-only functions (`install_rosetta`, `install_homebrew`) are never called without mocking, and no existing test file covers them.

- [ ] **Step 1: Verify macos.sh is below 75% in baseline**

Confirm `macos.sh` showed `FAIL` in Task 4 output. If it showed `PASS`, skip this task.

- [ ] **Step 2: Create `tests/setup_env/macos.bats`**

```bash
cat > tests/setup_env/macos.bats << 'BATS'
#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_setup_env
  load_mocks
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  export MOCK_ID_U=1000
}

teardown() {
  rm -f "${MOCK_CALLS_FILE:-}"
}

# ── install_rosetta ──────────────────────────────────────────────────────────

@test "install_rosetta: Intel processor - no Rosetta needed" {
  export MOCK_SW_VERS_PRODUCTVERSION="12.0.0"
  export MOCK_SYSCTL_CPU="Intel(R) Core(TM) i9-9900K CPU"
  run install_rosetta
  [ "$status" -eq 0 ]
  [[ "$output" == *"No need to install Rosetta"* ]]
}

@test "install_rosetta: Apple Silicon, oahd already running" {
  export MOCK_SW_VERS_PRODUCTVERSION="12.0.0"
  export MOCK_SYSCTL_CPU="Apple M1"
  export MOCK_PGREP_EXIT=0
  run install_rosetta
  [ "$status" -eq 0 ]
  [[ "$output" == *"already installed and running"* ]]
}

@test "install_rosetta: Apple Silicon, installs when oahd absent" {
  export MOCK_SW_VERS_PRODUCTVERSION="12.0.0"
  export MOCK_SYSCTL_CPU="Apple M1"
  export MOCK_PGREP_EXIT=1
  export MOCK_SOFTWAREUPDATE_EXIT=0
  run install_rosetta
  [ "$status" -eq 0 ]
  grep -q "softwareupdate --install-rosetta" "${MOCK_CALLS_FILE}"
}

@test "install_rosetta: softwareupdate fails returns exit 1" {
  export MOCK_SW_VERS_PRODUCTVERSION="12.0.0"
  export MOCK_SYSCTL_CPU="Apple M1"
  export MOCK_PGREP_EXIT=1
  export MOCK_SOFTWAREUPDATE_EXIT=1
  run install_rosetta
  [ "$status" -eq 1 ]
}

@test "install_rosetta: macOS 10 - no Rosetta needed" {
  export MOCK_SW_VERS_PRODUCTVERSION="10.15.7"
  run install_rosetta
  [ "$status" -eq 0 ]
  [[ "$output" == *"No need to install Rosetta on this version"* ]]
}

# ── install_homebrew ─────────────────────────────────────────────────────────

@test "install_homebrew: xcode already installed, brew install succeeds" {
  export MOCK_UNAME_S=Darwin
  export MOCK_XCODE_SELECT_PRINT_PATH_EXIT=0
  export MOCK_CURL_STDOUT="true"
  run install_homebrew
  [ "$status" -eq 0 ]
  ! grep -q "xcode-select --install" "${MOCK_CALLS_FILE}"
}

@test "install_homebrew: xcode not installed, installs xcode then brew" {
  export MOCK_UNAME_S=Darwin
  export MOCK_XCODE_SELECT_PRINT_PATH_EXIT=1
  export MOCK_XCODE_SELECT_EXIT=0
  export MOCK_XCODEBUILD_EXIT=0
  export MOCK_CURL_STDOUT="true"
  run install_homebrew
  [ "$status" -eq 0 ]
  grep -q "xcode-select --install" "${MOCK_CALLS_FILE}"
}

@test "install_homebrew: curl failure returns exit 1" {
  export MOCK_UNAME_S=Darwin
  export MOCK_XCODE_SELECT_PRINT_PATH_EXIT=0
  export MOCK_CURL_EXIT=1
  run install_homebrew
  [ "$status" -eq 1 ]
}

# ── install_git_macos ────────────────────────────────────────────────────────

@test "install_git_macos: git already in brew list" {
  export MOCK_BREW_LIST_FORMULA="git wget"
  run install_git_macos
  [ "$status" -eq 0 ]
  [[ "$output" == *"already installed"* ]]
}

@test "install_git_macos: brew present, git not installed - installs via brew" {
  export MOCK_BREW_LIST_FORMULA=""
  run install_git_macos
  [ "$status" -eq 0 ]
  grep -q "brew install git" "${MOCK_CALLS_FILE}"
}

# ── install_zsh_macos ────────────────────────────────────────────────────────

@test "install_zsh_macos: zsh already in brew list" {
  export MOCK_BREW_LIST_FORMULA="zsh wget"
  run install_zsh_macos
  [ "$status" -eq 0 ]
  [[ "$output" == *"already installed"* ]]
}

@test "install_zsh_macos: brew present, zsh not installed - installs via brew" {
  export MOCK_BREW_LIST_FORMULA=""
  run install_zsh_macos
  [ "$status" -eq 0 ]
  grep -q "brew install zsh" "${MOCK_CALLS_FILE}"
}

# ── install_macos_casks ──────────────────────────────────────────────────────

@test "install_macos_casks: no GUI, no devtools - runs base Brewfile only" {
  export BREWFILE_LOC="${BATS_TEST_TMPDIR}/brew"
  export PERSONAL_GITREPOS="${BATS_TEST_TMPDIR}/git-repos/personal"
  export DOTFILES="dotfiles"
  mkdir -p "${BREWFILE_LOC}" "${PERSONAL_GITREPOS}/${DOTFILES}"
  touch "${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile.gui"
  touch "${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile.devtools"
  ln -sf "${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile.gui" "${BREWFILE_LOC}/Brewfile"
  unset HAS_GUI HAS_DEVTOOLS
  run install_macos_casks
  [ "$status" -eq 0 ]
}

@test "install_macos_casks: with HAS_GUI set - runs gui Brewfile" {
  export BREWFILE_LOC="${BATS_TEST_TMPDIR}/brew"
  export PERSONAL_GITREPOS="${BATS_TEST_TMPDIR}/git-repos/personal"
  export DOTFILES="dotfiles"
  mkdir -p "${BREWFILE_LOC}" "${PERSONAL_GITREPOS}/${DOTFILES}"
  touch "${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile.gui"
  touch "${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile.devtools"
  ln -sf "${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile.gui" "${BREWFILE_LOC}/Brewfile"
  export HAS_GUI=1
  run install_macos_casks
  [ "$status" -eq 0 ]
}
BATS
```

- [ ] **Step 3: Run the new tests**

```bash
bats tests/setup_env/macos.bats
```

Expected: all tests pass. If any test fails due to unexpected output, check the mock values match the function's actual output strings by reading `lib/macos.sh` and adjusting the assertion text.

- [ ] **Step 4: Commit**

```bash
git add tests/setup_env/macos.bats
git commit -m "test(macos): add coverage tests for lib/macos.sh

Covers install_rosetta (all 5 branches), install_homebrew (3 paths),
install_git_macos, install_zsh_macos, install_macos_casks.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 6: Add `tests/setup_env/linux.bats`

**Files:**

- Create: `tests/setup_env/linux.bats`

This covers `lib/linux.sh` paths not exercised by existing tests — primarily the CentOS/Fedora distro branches in `install_git_linux`/`install_zsh_linux`, the RHEL/Fedora/CENTOS paths in `install_bats`, and `update_system_packages`/`install_centos_packages` entry points.

- [ ] **Step 1: Verify linux.sh is below 75% in baseline**

Confirm `linux.sh` showed `FAIL` in Task 4 output. If it showed `PASS` (≥75%), skip this task.

- [ ] **Step 2: Create `tests/setup_env/linux.bats`**

```bash
cat > tests/setup_env/linux.bats << 'BATS'
#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_setup_env
  load_mocks
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  export MOCK_ID_U=1000
  export HOME="${BATS_TEST_TMPDIR}"
  mkdir -p "${HOME}/software_downloads"
}

teardown() {
  rm -f "${MOCK_CALLS_FILE:-}"
}

# ── install_git_linux ────────────────────────────────────────────────────────

@test "install_git_linux: CentOS path calls yum install git" {
  export MOCK_AWK_OS_NAME="CentOS Linux"
  run install_git_linux
  [ "$status" -eq 0 ]
  grep -q "yum install git" "${MOCK_CALLS_FILE}"
}

@test "install_git_linux: Fedora path calls dnf install git" {
  export MOCK_AWK_OS_NAME="Fedora"
  run install_git_linux
  [ "$status" -eq 0 ]
  grep -q "dnf install git" "${MOCK_CALLS_FILE}"
}

@test "install_git_linux: REDHAT flag triggers dnf install chain" {
  export MOCK_AWK_OS_NAME="Ubuntu"
  export REDHAT=1
  export GIT_VER="2.44.0"
  export GIT_URL="https://github.com/git/git/archive"
  export MOCK_WGET_EXIT=0
  export MOCK_TAR_EXIT=0
  run install_git_linux
  [ "$status" -eq 0 ]
  grep -q "dnf install asciidoc" "${MOCK_CALLS_FILE}"
}

# ── install_zsh_linux ────────────────────────────────────────────────────────

@test "install_zsh_linux: CentOS path calls yum install zsh" {
  export MOCK_AWK_OS_NAME="CentOS Linux"
  run install_zsh_linux
  [ "$status" -eq 0 ]
  grep -q "yum install zsh" "${MOCK_CALLS_FILE}"
}

@test "install_zsh_linux: Fedora path calls dnf install zsh" {
  export MOCK_AWK_OS_NAME="Fedora"
  run install_zsh_linux
  [ "$status" -eq 0 ]
  grep -q "dnf install zsh" "${MOCK_CALLS_FILE}"
}

@test "install_zsh_linux: REDHAT flag triggers compile chain" {
  export MOCK_AWK_OS_NAME="Ubuntu"
  export REDHAT=1
  export ZSH_VER="5.9"
  export MOCK_WGET_EXIT=0
  export MOCK_TAR_EXIT=0
  run install_zsh_linux
  [ "$status" -eq 0 ]
  grep -q "yum install gcc" "${MOCK_CALLS_FILE}"
}

# ── install_bats ─────────────────────────────────────────────────────────────

@test "install_bats: already installed - returns 0 without installing" {
  # bats is in the mocks PATH so quiet_which bats succeeds
  run install_bats
  [ "$status" -eq 0 ]
  [[ "$output" == *"already installed"* ]]
}

@test "install_bats: UBUNTU path calls apt-get install bats" {
  export MOCK_WHICH_MISSING=bats
  export UBUNTU=1
  run install_bats
  [ "$status" -eq 0 ]
  grep -q "apt-get install" "${MOCK_CALLS_FILE}"
}

@test "install_bats: RHEL path downloads from github" {
  export MOCK_WHICH_MISSING=bats
  export REDHAT=1
  export BATS_VER="1.11.0"
  export MOCK_CURL_EXIT=0
  export MOCK_TAR_EXIT=0
  run install_bats
  [ "$status" -eq 0 ]
  grep -q "bats-core" "${MOCK_CALLS_FILE}"
}

@test "install_bats: unsupported platform returns 1" {
  export MOCK_WHICH_MISSING=bats
  unset UBUNTU REDHAT CENTOS FEDORA
  run install_bats
  [ "$status" -eq 1 ]
}

# ── update_system_packages ───────────────────────────────────────────────────

@test "update_system_packages: UBUNTU+JAMMY calls nala upgrade" {
  export UBUNTU=1
  export JAMMY=1
  run update_system_packages
  [ "$status" -eq 0 ]
  grep -q "nala full-upgrade" "${MOCK_CALLS_FILE}"
}

@test "update_system_packages: UBUNTU+NOBLE calls nala upgrade" {
  export UBUNTU=1
  export NOBLE=1
  run update_system_packages
  [ "$status" -eq 0 ]
  grep -q "nala full-upgrade" "${MOCK_CALLS_FILE}"
}

@test "update_system_packages: REDHAT calls dnf update" {
  export REDHAT=1
  unset UBUNTU CENTOS FEDORA
  run update_system_packages
  [ "$status" -eq 0 ]
  grep -q "dnf update" "${MOCK_CALLS_FILE}"
}

@test "update_system_packages: CENTOS calls yum update" {
  export CENTOS=1
  unset UBUNTU REDHAT FEDORA
  run update_system_packages
  [ "$status" -eq 0 ]
  grep -q "yum update" "${MOCK_CALLS_FILE}"
}

# ── install_centos_packages ──────────────────────────────────────────────────

@test "install_centos_packages: calls yum install for base packages" {
  run install_centos_packages
  [ "$status" -eq 0 ]
  grep -q "yum install curl" "${MOCK_CALLS_FILE}"
}

# ── install_linux_packages ───────────────────────────────────────────────────

@test "install_linux_packages: clones tfenv when not present" {
  export MOCK_GIT_CLONE_EXIT=0
  run install_linux_packages
  [ "$status" -eq 0 ]
  grep -q "tfenv.git" "${MOCK_CALLS_FILE}"
}

@test "install_linux_packages: installs tflint when zip absent" {
  export MOCK_WGET_EXIT=0
  export MOCK_UNZIP_EXIT=0
  run install_linux_packages
  [ "$status" -eq 0 ]
  grep -q "tflint" "${MOCK_CALLS_FILE}"
}
BATS
```

- [ ] **Step 3: Run the new tests**

```bash
bats tests/setup_env/linux.bats
```

Expected: all tests pass. If any fail due to mock behaviour not matching, check the function's branch conditions against the mock env vars in the test and adjust accordingly. Common issue: a function checks `[[ -n ${UBUNTU} ]]` but the test also exports `LINUX=1` — add that export if the function checks both.

- [ ] **Step 4: Commit**

```bash
git add tests/setup_env/linux.bats
git commit -m "test(linux): add coverage tests for lib/linux.sh untested paths

CentOS/Fedora distro branches, RHEL compile chains, install_bats
platform paths, update_system_packages, install_centos_packages,
install_linux_packages.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 7: Close remaining gaps (iterate to floors)

**Files:**

- Possibly modify: `tests/setup_env/unit.bats`, `tests/setup_env/install_functions.bats`, `tests/setup_env/workflows.bats`, `tests/setup_env/update_summary.bats`

This task is driven by the CI coverage output. After Tasks 5–6 land, push to update the CI run and read the new coverage table.

- [ ] **Step 1: Push tasks 5–6 and get updated coverage**

```bash
git push
```

Wait for `bash-coverage` CI job to complete, then:

```bash
gh run list --branch spec/bash-coverage-gate --json databaseId --jq '.[0].databaseId'
gh run view <RUN_ID> --log | grep -A 20 "Coverage measurement complete"
```

- [ ] **Step 2: For each file still showing FAIL, open the HTML report locally (if kcov available) or inspect uncovered lines from kcov output**

If kcov is installed locally:

```bash
make coverage
open coverage/kcov-merged/index.html   # macOS
# or: xdg-open coverage/kcov-merged/index.html  # Linux
```

The HTML report shows which exact lines in each file are uncovered (highlighted in red).

If kcov is not available locally, read the CI HTML artifact if uploaded, or infer from the function list which functions have no corresponding tests.

- [ ] **Step 3: For each uncovered function, add a test using the mock pattern**

The mock pattern from `tests/setup_env/install_functions.bats`:

```bash
@test "function_name: description of what this path covers" {
  export MOCK_UNAME_S=Linux     # or Darwin
  export LINUX=1                 # or MACOS=1
  export MOCK_BREW_LIST_FORMULA=""  # or specific packages
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  run function_name
  [ "$status" -eq 0 ]
  grep -q "expected command" "${MOCK_CALLS_FILE}"
}
```

For error paths (functions that `return 1` on failure):

```bash
@test "function_name: returns 1 when dependency fails" {
  export MOCK_APT_EXIT=1
  local _rc=0
  function_name || _rc=$?
  [ "${_rc}" -eq 1 ]
}
```

- [ ] **Step 4: After adding tests, run full suite to confirm no regressions**

```bash
make test
```

Expected: all tests pass.

- [ ] **Step 5: Push and confirm all files now show PASS in CI**

```bash
git add tests/
git commit -m "test: close remaining coverage gaps per kcov report

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
git push
```

Wait for CI. Read coverage table. Repeat Step 2–5 until all files show PASS.

---

## Phase 3: Enable gate and finalize

### Task 8: Enable the coverage gate in `scripts/run-coverage.sh`

**Files:**

- Modify: `scripts/run-coverage.sh`

Do this only after all files show PASS in the CI coverage table.

- [ ] **Step 1: Confirm all files show PASS in the most recent CI run**

```bash
gh run list --branch spec/bash-coverage-gate --json databaseId --jq '.[0].databaseId'
gh run view <RUN_ID> --log | grep -E "PASS|FAIL"
```

Expected: every file shows `PASS`.

- [ ] **Step 2: Replace the measurement-mode exit block with the gate**

Find and replace the last block of `scripts/run-coverage.sh`. The current tail is:

```bash
# Gate not yet enabled — measurement mode only
if [[ "${failed}" -ne 0 ]]; then
  printf "\nFiles below floor noted above (gate will be enabled after floors are met)\n"
fi
printf "\nCoverage measurement complete\n"
```

Replace with:

```bash
if [[ "${failed}" -ne 0 ]]; then
  printf "\nCoverage gate FAILED — one or more files below floor\n" >&2
  exit 1
fi
printf "\nCoverage gate PASSED\n"
```

- [ ] **Step 3: Verify the script syntax**

```bash
bash -n scripts/run-coverage.sh
```

Expected: exit 0, no output.

- [ ] **Step 4: Test gate locally (if kcov available)**

If kcov is installed:

```bash
make coverage
```

Expected: exits 0, prints `Coverage gate PASSED`.

To verify the gate fires correctly, temporarily edit the threshold for one file to 999% and re-run:

```bash
# In scripts/run-coverage.sh, change ["setup_env.sh"]=90 to ["setup_env.sh"]=999
make coverage
# Expected: exits 1, shows FAIL for setup_env.sh
# Revert the change:
# Change ["setup_env.sh"]=999 back to ["setup_env.sh"]=90
```

If kcov is NOT available locally, skip the local test — CI will verify.

- [ ] **Step 5: Commit**

```bash
git add scripts/run-coverage.sh
git commit -m "feat: enable coverage gate in run-coverage.sh

Gate was in measurement-only mode while floors were being reached.
All 9 files now meet their floors — gate is live.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 9: Add `bash-coverage` to `auto-merge needs:`

**Files:**

- Modify: `.github/workflows/ci.yml`

- [ ] **Step 1: Update `auto-merge needs:`**

In `.github/workflows/ci.yml`, change:

```yaml
needs: [test, lint-macos, powershell, secret-scan]
```

to:

```yaml
needs: [test, lint-macos, powershell, bash-coverage, secret-scan]
```

- [ ] **Step 2: Verify YAML**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))" && echo "YAML OK"
```

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: add bash-coverage to auto-merge required jobs

Coverage gate is now live — PRs must pass the coverage floor to auto-merge.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 10: Update `CLAUDE.md`

**Files:**

- Modify: `CLAUDE.md`

- [ ] **Step 1: Add "Bash Coverage" subsection**

In `CLAUDE.md`, find the `### Coverage` subsection (PowerShell coverage). Add the new "Bash Coverage" subsection immediately after it (before `### Test Seams`):

```markdown
### Bash Coverage

- Floor: 90% for cross-platform files, 75% for platform-specific files. CI fails on any drop below the floor.
- Re-measure: `make coverage` prints the per-file table and writes `coverage/`. Requires kcov (`brew install kcov` locally; installed automatically in CI).
- Update the figures below whenever tests are added or removed.

| File                    | Coverage  | Floor |
| ----------------------- | --------- | ----- |
| `setup_env.sh`          | <ACTUAL>% | 90%   |
| `lib/constants.sh`      | <ACTUAL>% | 90%   |
| `lib/detect_env.sh`     | <ACTUAL>% | 90%   |
| `lib/helpers.sh`        | <ACTUAL>% | 90%   |
| `lib/workflows.sh`      | <ACTUAL>% | 90%   |
| `lib/update_summary.sh` | <ACTUAL>% | 90%   |
| `lib/developer.sh`      | <ACTUAL>% | 90%   |
| `lib/linux.sh`          | <ACTUAL>% | 75%   |
| `lib/macos.sh`          | <ACTUAL>% | 75%   |
```

Replace each `<ACTUAL>%` with the real percentages from the last CI coverage run (use the PASS values from Task 8 Step 1 — those are the gate-passing figures).

Also update the CI job bullet list under `### CI / GitHub Actions` to mention `bash-coverage`:

Find:

```markdown
- `auto-merge` job: auto-merges any PR when all three CI jobs pass (depends on `test`, `lint-macos`, `secret-scan`)
```

Replace with:

```markdown
- `bash-coverage` job: runs kcov over the full BATS suite and enforces per-file coverage floors (blocking auto-merge)
- `auto-merge` job: auto-merges any PR when all required CI jobs pass (depends on `test`, `lint-macos`, `powershell`, `bash-coverage`, `secret-scan`)
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: record bash coverage figures in CLAUDE.md

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 11: End-to-end verification

**Files:** none

- [ ] **Step 1: Push all commits**

```bash
git push
```

- [ ] **Step 2: Wait for all CI jobs**

```bash
gh pr checks
```

Wait until all jobs show `pass`.

- [ ] **Step 3: Confirm `bash-coverage` job output shows gate PASSED**

```bash
gh run list --branch spec/bash-coverage-gate --json databaseId --jq '.[0].databaseId'
gh run view <RUN_ID> --log | grep "Coverage gate"
```

Expected: `Coverage gate PASSED`

- [ ] **Step 4: Confirm all files are at or above their floors**

```bash
gh run view <RUN_ID> --log | grep -A 15 "File.*Coverage.*Floor.*Status"
```

Expected: every file shows `PASS`, no file shows `FAIL`.

- [ ] **Step 5: Confirm auto-merge is unblocked**

```bash
gh pr view --json mergeStateStatus
```

Expected: `{"mergeStateStatus":"CLEAN"}` (or `BLOCKED` only if there is a non-coverage reason).

- [ ] **Step 6: Mark PR ready for merge**

```bash
gh pr merge --squash
```

Or let the `auto-merge` job handle it automatically once all required jobs pass.
