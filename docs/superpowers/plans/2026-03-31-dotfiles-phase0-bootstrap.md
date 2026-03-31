# Phase 0: Bootstrap Script + Prerequisite Check Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create `scripts/bootstrap_mac.sh` (standalone macOS prerequisite installer) and add a bash 5 + Homebrew prerequisite check to the top of `setup_env.sh` that fails fast with a clear error pointing to the bootstrap script.

**Architecture:** The bootstrap script uses `#!/bin/bash` (not `#!/usr/bin/env bash`) so it runs on macOS default bash 3.2. The prerequisite check in `setup_env.sh` sits above all existing code — before constants, before functions, before the sourcing guard — so it fires regardless of how the script is invoked. The check reads `BASH_VERSINFO` (built-in array set by the shell) and calls `command -v brew`. Note: function extraction work for the same Phase 0 branch is tracked separately in `docs/superpowers/plans/2026-03-28-setup-env-function-extraction.md`.

**Tech Stack:** Bash, BATS, `tests/mocks/` PATH-injection pattern, `make lint` (bash -n + zsh -n syntax check)

---

## Files

| File | Action |
|---|---|
| `scripts/bootstrap_mac.sh` | Create — standalone Homebrew + bash 5 installer |
| `setup_env.sh` | Modify — add prereq check block after shebang, before existing line 3 |
| `tests/setup_env/unit.bats` | Modify — add prereq check tests |

---

## Task 1: Write failing tests for the prerequisite check

**Files:**
- Modify: `tests/setup_env/unit.bats`

The prereq check runs above the sourcing guard, so it cannot be tested by sourcing `setup_env.sh`. Test it by invoking `bash setup_env.sh` as a subprocess.

- [ ] **Step 1: Add the failing tests to `tests/setup_env/unit.bats`**

Append to the end of the file:

```bash
# ── prerequisite check ────────────────────────────────────────────────────────

@test "setup_env.sh exits 1 with error when brew is not found" {
  export MOCK_WHICH_MISSING=brew
  run bash "${BATS_TEST_DIRNAME}/../../setup_env.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Homebrew not found"* ]]
}

@test "setup_env.sh prereq error message points to bootstrap_mac.sh" {
  export MOCK_WHICH_MISSING=brew
  run bash "${BATS_TEST_DIRNAME}/../../setup_env.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"bootstrap_mac.sh"* ]]
}
```

Note: the bash version check cannot be easily tested by mocking `BASH_VERSINFO` (it is a read-only shell variable set at startup). We verify the check exists in the file via a grep test:

```bash
@test "setup_env.sh contains bash version prerequisite check" {
  run grep -q 'BASH_VERSINFO' "${BATS_TEST_DIRNAME}/../../setup_env.sh"
  [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run the tests to confirm they fail**

```bash
make test-unit
```

Expected: FAIL — `setup_env.sh exits 1 with error when brew is not found` fails because the prereq check does not exist yet.

---

## Task 2: Add the prerequisite check to `setup_env.sh`

**Files:**
- Modify: `setup_env.sh` (insert after line 1, before existing line 3)

Current lines 1–3:
```bash
#!/usr/bin/env bash

# software versions to install
```

- [ ] **Step 1: Insert the prereq check block**

Replace:
```bash
#!/usr/bin/env bash

# software versions to install
```

With:
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

# software versions to install
```

- [ ] **Step 2: Validate syntax**

```bash
bash -n setup_env.sh && printf "bash  OK\n"
zsh  -n setup_env.sh && printf "zsh   OK\n"
```

Expected: both print OK with no errors.

- [ ] **Step 3: Run the tests to confirm they pass**

```bash
make test-unit
```

Expected: all three prereq tests PASS.

- [ ] **Step 4: Run the full test suite**

```bash
make test
```

Expected: all tests pass — exit 0.

- [ ] **Step 5: Commit**

```bash
git add setup_env.sh tests/setup_env/unit.bats
git commit -m "feat: add bash 5 + Homebrew prerequisite check to setup_env.sh

Fails fast with a clear error pointing to scripts/bootstrap_mac.sh
if the invoking shell is bash < 5 or Homebrew is not installed.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 3: Create `scripts/bootstrap_mac.sh`

**Files:**
- Create: `scripts/bootstrap_mac.sh`

- [ ] **Step 1: Verify the scripts/ directory exists**

```bash
ls scripts/
```

Expected: directory exists with existing scripts.

- [ ] **Step 2: Create `scripts/bootstrap_mac.sh`**

```bash
#!/bin/bash
# scripts/bootstrap_mac.sh
# Run once on a fresh Mac before setup_env.sh.
# Installs Homebrew and bash 5 — the only two prerequisites for setup_env.sh.

set -e

if [[ $(uname -s) != "Darwin" ]]; then
  printf "[ERROR] This script is macOS only.\n" >&2
  exit 1
fi

# Install Homebrew if missing
if ! command -v brew &>/dev/null; then
  printf "[INFO]  Installing Homebrew...\n"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
else
  printf "[INFO]  Homebrew already installed.\n"
fi

# Ensure brew is on PATH (Apple Silicon path)
if [[ -f /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# Install bash 5 if missing or version < 5
BASH_VER=$(brew list --versions bash 2>/dev/null | awk '{print $2}' | cut -d. -f1)
if [[ "${BASH_VER:-0}" -lt 5 ]]; then
  printf "[INFO]  Installing bash 5...\n"
  brew install bash
else
  printf "[INFO]  bash 5 already installed.\n"
fi

printf "[INFO]  Bootstrap complete. You can now run: ./setup_env.sh -t <type>\n"
```

- [ ] **Step 3: Make it executable**

```bash
chmod +x scripts/bootstrap_mac.sh
```

- [ ] **Step 4: Validate syntax**

```bash
bash -n scripts/bootstrap_mac.sh && printf "bash  OK\n"
zsh  -n scripts/bootstrap_mac.sh && printf "zsh   OK\n"
```

Expected: both print OK.

Note: `zsh -n` may warn about `[[ ... ]]` syntax since this file uses `#!/bin/bash` — that is acceptable. The script is intentionally a bash script. If zsh -n fails, verify the specific warning and add a `# shellcheck` comment if needed. The `make lint` target runs both — if zsh -n fails on this file, update the lint target to exclude `scripts/bootstrap_mac.sh` from zsh checking with a comment explaining why.

- [ ] **Step 5: Run the full test suite**

```bash
make test
```

Expected: exit 0.

- [ ] **Step 6: Commit**

```bash
git add scripts/bootstrap_mac.sh
git commit -m "feat: add scripts/bootstrap_mac.sh for fresh Mac prerequisites

Standalone script that installs Homebrew and bash 5 on a fresh Mac.
Uses /bin/bash shebang so it runs on macOS default bash 3.2.
setup_env.sh now requires these and points here if missing.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 4: Final verification

- [ ] **Step 1: Run the complete test suite one final time**

```bash
make test
```

Expected: exit 0, all tests green.

- [ ] **Step 2: Verify lint passes cleanly**

```bash
make lint
```

Expected: `bash OK` and `zsh OK` for all files (or zsh exemption comment for bootstrap_mac.sh as noted above).

- [ ] **Step 3: Check the branch is ready**

```bash
git log --oneline -5
```

Expected: two commits visible — prereq check commit and bootstrap_mac.sh commit (plus any prior Phase 0 function extraction commits on this branch).
