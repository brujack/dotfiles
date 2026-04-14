# Machine-Local Overrides Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Source a git-ignored `config/local.sh` after `detect_env` runs so individual machines can customize `HAS_*` vars, PATH, and secrets without committing them.

**Architecture:** Three-part change — `.gitignore` prevents accidental commits; `setup_env.sh` conditionally sources the file after `detect_env`; `config/local.sh.example` documents the pattern.

**Tech Stack:** bash, bats

---

## File Map

| Action | File                        |
| ------ | --------------------------- |
| Modify | `.gitignore`                |
| Create | `config/local.sh.example`   |
| Modify | `setup_env.sh`              |
| Modify | `tests/setup_env/unit.bats` |
| Modify | `CLAUDE.md`                 |
| Modify | `README.md`                 |

---

### Task 1: Add config/local.sh to .gitignore + test

**Files:**

- Modify: `.gitignore`
- Modify: `tests/setup_env/unit.bats`

- [ ] **Step 1: Write the failing test**

Add at the end of `tests/setup_env/unit.bats` (before EOF):

```bash
# ── local overrides ───────────────────────────────────────────────────────────

@test ".gitignore contains config/local.sh" {
  grep -q '^config/local\.sh$' "${REPO_ROOT}/.gitignore"
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
make test-unit
```

Expected: FAIL — `grep: no match`

- [ ] **Step 3: Add entry to .gitignore**

In `.gitignore`, append after the existing entries:

```
config/local.sh
```

- [ ] **Step 4: Run test to verify it passes**

```bash
make test-unit
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add .gitignore tests/setup_env/unit.bats
git commit -m "chore: git-ignore config/local.sh"
```

---

### Task 2: Create config/local.sh.example

**Files:**

- Create: `config/local.sh.example`

- [ ] **Step 1: Create the example file**

Create `config/local.sh.example` with this exact content:

```bash
#!/usr/bin/env bash
# config/local.sh — machine-local overrides (git-ignored, not committed)
#
# This file is sourced after detect_env(), so HAS_* vars and PROFILE are set.
# Copy this file to config/local.sh and customise for this machine.
#
# Examples:

# Override a capability var (e.g. disable Docker installs on this machine)
# unset HAS_DOCKER

# Add a machine-specific PATH entry
# export PATH="${HOME}/.local/bin:${PATH}"

# Source a work-specific secrets file
# [[ -f "${HOME}/.work_env" ]] && source "${HOME}/.work_env"

# Add a custom symlink
# safe_link "${HOME}/work/dotfiles/.gitconfig_work" "${HOME}/.gitconfig_work"
```

- [ ] **Step 2: Verify lint passes**

```bash
make lint
```

Expected: all OK (`.example` extension is not checked by shellcheck or bash -n)

- [ ] **Step 3: Commit**

```bash
git add config/local.sh.example
git commit -m "feat: add config/local.sh.example template"
```

---

### Task 3: Add source block to setup_env.sh + tests

**Files:**

- Modify: `setup_env.sh`
- Modify: `tests/setup_env/unit.bats`

- [ ] **Step 1: Write the failing tests**

Add after the `.gitignore` test in `tests/setup_env/unit.bats`:

```bash
@test "setup_env sources config/local.sh when present" {
  local local_cfg="${REPO_ROOT}/config/local.sh"
  printf '#!/usr/bin/env bash\nLOCAL_SENTINEL=42\n' > "${local_cfg}"
  run bash -c "
    source '${REPO_ROOT}/setup_env.sh'
    [[ \${LOCAL_SENTINEL} -eq 42 ]]
  "
  rm -f "${local_cfg}"
  [ "$status" -eq 0 ]
}

@test "setup_env does not error when config/local.sh is absent" {
  local local_cfg="${REPO_ROOT}/config/local.sh"
  rm -f "${local_cfg}"
  run bash -c "source '${REPO_ROOT}/setup_env.sh'"
  [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
make test-unit
```

Expected: FAIL — `LOCAL_SENTINEL` not set (source block does not exist yet)

- [ ] **Step 3: Add source block to setup_env.sh**

In `setup_env.sh`, replace:

```bash
detect_env

[[ -n ${DOCTOR:-} ]] && { run_doctor; exit 0; }
```

With:

```bash
detect_env

# Machine-local overrides (git-ignored, sourced if present)
_LOCAL_CFG="$(dirname "${BASH_SOURCE[0]}")/config/local.sh"
[[ -f "${_LOCAL_CFG}" ]] && source "${_LOCAL_CFG}"
unset _LOCAL_CFG

[[ -n ${DOCTOR:-} ]] && { run_doctor; exit 0; }
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
make test-unit
```

Expected: PASS

- [ ] **Step 5: Verify full test suite**

```bash
make test
```

Expected: all pass

- [ ] **Step 6: Commit**

```bash
git add setup_env.sh tests/setup_env/unit.bats
git commit -m "feat: source config/local.sh after detect_env for machine-local overrides"
```

---

### Task 4: Update docs

**Files:**

- Modify: `CLAUDE.md`
- Modify: `README.md`

- [ ] **Step 1: Update CLAUDE.md**

In `CLAUDE.md`, in the `## Local-Only State` section, add after the last bullet:

```
- `config/local.sh` — machine-local overrides; copy from `config/local.sh.example`, git-ignored
```

- [ ] **Step 2: Update README.md**

In `README.md`, after the `**Options:**` block (after the `--dry-run` line), add:

````markdown
### Machine-Local Overrides

To customize a specific machine without committing changes, copy the example and edit:

```bash
cp config/local.sh.example config/local.sh
```
````

`config/local.sh` is git-ignored and sourced after `detect_env` runs. The `HAS_*` vars, `PROFILE`, and OS vars are all available to override.

````

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md README.md
git commit -m "docs: document config/local.sh machine-local overrides"
````
