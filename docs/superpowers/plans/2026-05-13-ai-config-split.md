# ai-config Split Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract `.claude/` and `.cursor/` from the public dotfiles repo into a new private `ai-config` repo, with automated bootstrap via `setup_env.sh`.

**Architecture:** Create and populate `ai-config` first so symlinks can be re-pointed before anything is deleted from dotfiles — safe to interrupt at any step. Dotfiles gains two new constants (`AI_CONFIG`, `AI_CONFIG_DIR`), a `setup_ai_config` bootstrap function, and updated symlink/mcp wiring. The `sync-agent-guidance` script moves to `ai-config` unchanged since both `.claude/` and `.cursor/` share its new root.

**Tech Stack:** Bash, BATS, git, gh CLI, GitHub Actions, Python 3 (sync script)

---

## File Map

**Created in `ai-config`:**

- `~/git-repos/personal/ai-config/.gitignore`
- `~/git-repos/personal/ai-config/.gitleaks.toml`
- `~/git-repos/personal/ai-config/README.md`
- `~/git-repos/personal/ai-config/Makefile`
- `~/git-repos/personal/ai-config/scripts/sync-agent-guidance.sh` (moved from dotfiles)
- `~/git-repos/personal/ai-config/scripts/pre-commit-hook.sh`
- `~/git-repos/personal/ai-config/scripts/pre-push-hook.sh`
- `~/git-repos/personal/ai-config/.github/workflows/ci.yml`
- `~/git-repos/personal/ai-config/.claude/` (copied from dotfiles)
- `~/git-repos/personal/ai-config/.cursor/` (copied from dotfiles)
- `~/git-repos/personal/ai-config/.claude/settings.local.json.example`

**Modified in dotfiles:**

- `lib/constants.sh` — add `AI_CONFIG`, `AI_CONFIG_DIR`
- `lib/workflows.sh` — add `setup_ai_config`, update `setup_claude_mcp`, wire into `run_setup_user`
- `lib/helpers.sh` — update `setup_dotfile_symlinks` to source from `AI_CONFIG_DIR`
- `Makefile` — remove `sync-agent-guidance` and `check-agent-guidance` targets
- `.github/workflows/ci.yml` — remove `check-agent-guidance` step

**Deleted from dotfiles:**

- `.claude/` (entire directory)
- `.cursor/` (entire directory)
- `scripts/sync-agent-guidance.sh`

**Modified in ai-config (after copy):**

- `.claude/CLAUDE.md` — update memory convention to reference `ai-config`

**Tests modified in dotfiles:**

- `tests/setup_env/install_guards.bats` — add `setup_ai_config` tests, update symlink tests

---

### Task 1: Create ai-config repo scaffold

**Files:**

- Create: `~/git-repos/personal/ai-config/.gitignore`
- Create: `~/git-repos/personal/ai-config/.gitleaks.toml`
- Create: `~/git-repos/personal/ai-config/README.md`

- [ ] **Step 1: Create the private GitHub repo and clone it**

```bash
gh repo create brujack/ai-config --private --description "Claude Code and Cursor configuration"
git clone git@github.com:brujack/ai-config ~/git-repos/personal/ai-config
cd ~/git-repos/personal/ai-config
```

- [ ] **Step 2: Create `.gitignore`**

```
# macOS
.DS_Store
.DS_Store?
._*
.Spotlight-V100
.Trashes
.AppleDouble
.LSOverride

# Linux
*~
.fuse_hidden*
.directory
.Trash-*
.nfs*

# Machine-local Claude config
.claude/mcp.json
.claude/settings.local.json

# Claude Code conversation history (memory/ subdirs are tracked)
.claude/projects/**/*.jsonl

# Plugin-managed skills (installed via claude plugins install)
.claude/skills/terraform-skill/

# Claude Code runtime files
.claude/cache/
.claude/sessions/
.claude/history.jsonl
.claude/backups/
```

- [ ] **Step 3: Create `.gitleaks.toml`**

```toml
[allowlist]
  description = "ai-config allowlist"
  paths = [
    '''\.claude/mcp\.json\.template''',
  ]
```

- [ ] **Step 4: Create `README.md`**

```markdown
# ai-config

Private Claude Code and Cursor configuration — skills, standards, hooks, memory, and settings.

Managed by [dotfiles](https://github.com/brujack/dotfiles) via `setup_env.sh -t setup_user`.

## Setup

Cloned automatically when running:

\`\`\`bash
./setup_env.sh -t setup_user
\`\`\`

Install hooks after cloning (run once per checkout):

\`\`\`bash
make install-hooks
\`\`\`

Sync Cursor rules from Claude standards:

\`\`\`bash
make sync-agent-guidance
\`\`\`
```

- [ ] **Step 5: Commit and push scaffold**

```bash
git add .gitignore .gitleaks.toml README.md
git commit -m "chore: initial scaffold"
git push -u origin master
```

---

### Task 2: Populate ai-config with .claude/ and .cursor/ content

**Files:**

- Create: `~/git-repos/personal/ai-config/.claude/` (copied from dotfiles)
- Create: `~/git-repos/personal/ai-config/.cursor/` (copied from dotfiles)
- Create: `~/git-repos/personal/ai-config/.claude/settings.local.json.example`

- [ ] **Step 1: Copy .claude/ and .cursor/ from dotfiles**

```bash
cd ~/git-repos/personal/ai-config
cp -r ~/git-repos/personal/dotfiles/.claude .
cp -r ~/git-repos/personal/dotfiles/.cursor .
```

- [ ] **Step 2: Create settings.local.json.example**

```bash
cat > .claude/settings.local.json.example << 'EOF'
{
  "theme": "dark"
}
EOF
```

- [ ] **Step 3: Verify .gitignore excludes runtime files**

```bash
git status --short | head -30
# Should NOT see: .claude/mcp.json, .claude/settings.local.json,
# .claude/cache/, .claude/sessions/, .claude/history.jsonl
# SHOULD see: .claude/CLAUDE.md, .claude/standards/, .claude/skills/, etc.
```

- [ ] **Step 4: Commit and push content**

```bash
git add .claude .cursor
git commit -m "feat: add Claude Code and Cursor configuration"
git push
```

---

### Task 3: Move sync-agent-guidance to ai-config and create Makefile

**Files:**

- Create: `~/git-repos/personal/ai-config/scripts/sync-agent-guidance.sh`
- Create: `~/git-repos/personal/ai-config/Makefile`

- [ ] **Step 1: Copy sync-agent-guidance.sh**

```bash
cd ~/git-repos/personal/ai-config
mkdir -p scripts
cp ~/git-repos/personal/dotfiles/scripts/sync-agent-guidance.sh scripts/
chmod +x scripts/sync-agent-guidance.sh
```

The script uses `repo_root()` which resolves to the directory containing `scripts/` — since both `.claude/` and `.cursor/` are at the `ai-config` root, no changes to the script are needed.

- [ ] **Step 2: Create Makefile**

```makefile
SHELL := /bin/bash

.PHONY: sync-agent-guidance check-agent-guidance install-hooks

sync-agent-guidance:
	./scripts/sync-agent-guidance.sh sync

check-agent-guidance:
	./scripts/sync-agent-guidance.sh check

install-hooks:
	cp scripts/pre-commit-hook.sh .git/hooks/pre-commit
	chmod +x .git/hooks/pre-commit
	cp scripts/pre-push-hook.sh .git/hooks/pre-push
	chmod +x .git/hooks/pre-push
	@printf "Hooks installed.\n"
```

- [ ] **Step 3: Verify sync-agent-guidance works from ai-config root**

```bash
cd ~/git-repos/personal/ai-config
make check-agent-guidance
# Expected: "Agent guidance is in sync" (or regenerate with make sync-agent-guidance first)
```

If it reports drift, run `make sync-agent-guidance` then re-check.

- [ ] **Step 4: Commit**

```bash
git add scripts/sync-agent-guidance.sh Makefile
git commit -m "feat: add sync-agent-guidance script and Makefile"
git push
```

---

### Task 4: Update memory convention in ai-config CLAUDE.md

**Files:**

- Modify: `~/git-repos/personal/ai-config/.claude/CLAUDE.md`

- [ ] **Step 1: Update the Memory for Personal Repos section**

In `~/git-repos/personal/ai-config/.claude/CLAUDE.md`, replace:

```
All repos under `~/git-repos/personal/` have their Claude project memories stored in `~/git-repos/personal/dotfiles/.claude/projects/` and symlinked into `~/.claude/projects/`. This means memories are shared across machines via the dotfiles repo.
```

With:

```
All repos under `~/git-repos/personal/` have their Claude project memories stored in `~/git-repos/personal/ai-config/.claude/projects/` and symlinked into `~/.claude/projects/`. This means memories are shared across machines via the ai-config repo.
```

- [ ] **Step 2: Commit**

```bash
cd ~/git-repos/personal/ai-config
git add .claude/CLAUDE.md
git commit -m "docs: update memory convention to reference ai-config"
git push
```

---

### Task 5: Add AI_CONFIG constants to dotfiles lib/constants.sh

**Files:**

- Modify: `lib/constants.sh`
- Test: `tests/setup_env/unit.bats`

- [ ] **Step 1: Write the failing test**

In `tests/setup_env/unit.bats`, add:

```bash
@test "AI_CONFIG is set to ai-config" {
  [ "${AI_CONFIG}" = "ai-config" ]
}

@test "AI_CONFIG_DIR is PERSONAL_GITREPOS/ai-config" {
  [ "${AI_CONFIG_DIR}" = "${PERSONAL_GITREPOS}/ai-config" ]
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
make test-unit 2>&1 | grep -A2 "AI_CONFIG"
# Expected: FAIL — AI_CONFIG not found
```

- [ ] **Step 3: Add constants to lib/constants.sh**

Find the block of repo-path constants (near `DOTFILES=`) and add after the `DOTFILES` constant:

```bash
readonly AI_CONFIG="ai-config"
readonly AI_CONFIG_DIR="${PERSONAL_GITREPOS}/${AI_CONFIG}"
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
make test-unit 2>&1 | grep -A2 "AI_CONFIG"
# Expected: PASS
```

- [ ] **Step 5: Commit**

```bash
cd ~/git-repos/personal/dotfiles
git add lib/constants.sh tests/setup_env/unit.bats
git commit -m "feat: add AI_CONFIG and AI_CONFIG_DIR constants"
```

---

### Task 6: Add setup_ai_config function to dotfiles workflows.sh

**Files:**

- Modify: `lib/workflows.sh`
- Test: `tests/setup_env/install_guards.bats`

- [ ] **Step 1: Write failing tests**

In `tests/setup_env/install_guards.bats`, add:

```bash
@test "setup_ai_config clones repo when AI_CONFIG_DIR absent" {
  load_mocks
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  export AI_CONFIG_DIR="${BATS_TEST_TMPDIR}/nonexistent-ai-config"

  run setup_ai_config
  [ "${status}" -eq 0 ]
  grep -q "git clone git@github.com:brujack/ai-config ${BATS_TEST_TMPDIR}/nonexistent-ai-config" "${MOCK_CALLS_FILE}"
}

@test "setup_ai_config skips clone when AI_CONFIG_DIR exists" {
  load_mocks
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  export AI_CONFIG_DIR="${BATS_TEST_TMPDIR}/ai-config"
  mkdir -p "${AI_CONFIG_DIR}"

  run setup_ai_config
  [ "${status}" -eq 0 ]
  ! grep -q "git clone" "${MOCK_CALLS_FILE}"
}

@test "setup_ai_config returns 1 when clone fails" {
  load_mocks
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  export MOCK_GIT_CLONE_EXIT=1
  export AI_CONFIG_DIR="${BATS_TEST_TMPDIR}/nonexistent-ai-config"

  local _rc=0
  setup_ai_config || _rc=$?
  [ "${_rc}" -eq 1 ]
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
make test 2>&1 | grep -A2 "setup_ai_config"
# Expected: FAIL — setup_ai_config not found
```

- [ ] **Step 3: Add setup_ai_config to lib/workflows.sh**

Add before `run_setup_user`:

```bash
setup_ai_config() {
  if [[ ! -d "${AI_CONFIG_DIR}" ]]; then
    log_info "ai-config not found — cloning..."
    git clone git@github.com:brujack/ai-config "${AI_CONFIG_DIR}" || return 1
  fi
}
```

- [ ] **Step 4: Wire into run_setup_user**

In `run_setup_user`, add after `clone_or_update_dotfiles || return 1`:

```bash
setup_ai_config || return 1
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
make test 2>&1 | grep -A2 "setup_ai_config"
# Expected: all three tests PASS
```

- [ ] **Step 6: Commit**

```bash
git add lib/workflows.sh tests/setup_env/install_guards.bats
git commit -m "feat: add setup_ai_config bootstrap function"
```

---

### Task 7: Update setup_dotfile_symlinks to source from AI_CONFIG_DIR

**Files:**

- Modify: `lib/helpers.sh`
- Test: `tests/setup_env/install_guards.bats`

- [ ] **Step 1: Write failing tests**

In `tests/setup_env/install_guards.bats`, add:

```bash
@test "setup_dotfile_symlinks creates .claude symlinks from AI_CONFIG_DIR" {
  load_mocks
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  export AI_CONFIG_DIR="${BATS_TEST_TMPDIR}/ai-config"
  mkdir -p "${AI_CONFIG_DIR}/.claude"
  touch "${AI_CONFIG_DIR}/.claude/CLAUDE.md"
  local _home="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${_home}"
  export HOME="${_home}"

  run setup_dotfile_symlinks
  [ "${status}" -eq 0 ]
  [ -L "${_home}/.claude/CLAUDE.md" ]
  [[ "$(readlink "${_home}/.claude/CLAUDE.md")" == "${AI_CONFIG_DIR}/.claude/CLAUDE.md" ]]
}

@test "setup_dotfile_symlinks creates .cursor symlinks from AI_CONFIG_DIR" {
  load_mocks
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  export AI_CONFIG_DIR="${BATS_TEST_TMPDIR}/ai-config"
  mkdir -p "${AI_CONFIG_DIR}/.cursor"
  touch "${AI_CONFIG_DIR}/.cursor/testfile"
  local _home="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${_home}"
  export HOME="${_home}"

  run setup_dotfile_symlinks
  [ "${status}" -eq 0 ]
  [ -L "${_home}/.cursor/testfile" ]
  [[ "$(readlink "${_home}/.cursor/testfile")" == "${AI_CONFIG_DIR}/.cursor/testfile" ]]
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
make test 2>&1 | grep -A2 "AI_CONFIG_DIR"
# Expected: FAIL — symlinks point at DOTFILES, not AI_CONFIG_DIR
```

- [ ] **Step 3: Update the .claude loop in lib/helpers.sh**

Find the `.claude` symlink loop (around line 666) and change:

```bash
for _claude_item in "${PERSONAL_GITREPOS}/${DOTFILES}/.claude/"*; do
```

to:

```bash
for _claude_item in "${AI_CONFIG_DIR}/.claude/"*; do
```

- [ ] **Step 4: Update the .cursor loop in lib/helpers.sh**

Find the `.cursor` symlink loop and change:

```bash
for _cursor_item in "${PERSONAL_GITREPOS}/${DOTFILES}/.cursor/"*; do
```

to:

```bash
for _cursor_item in "${AI_CONFIG_DIR}/.cursor/"*; do
```

Also update the `.cursor/rules` explicit symlink immediately after that loop:

```bash
safe_link "${PERSONAL_GITREPOS}/${DOTFILES}/.cursor/rules" "${HOME}/.cursor/rules"
```

to:

```bash
safe_link "${AI_CONFIG_DIR}/.cursor/rules" "${HOME}/.cursor/rules"
```

Also update `CURSOR_DOTFILES_USER_DIR` (around line 698):

```bash
CURSOR_DOTFILES_USER_DIR="${PERSONAL_GITREPOS}/${DOTFILES}/.cursor/User"
```

to:

```bash
CURSOR_DOTFILES_USER_DIR="${AI_CONFIG_DIR}/.cursor/User"
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
make test 2>&1 | grep -A2 "AI_CONFIG_DIR"
# Expected: both tests PASS
```

- [ ] **Step 6: Commit**

```bash
git add lib/helpers.sh tests/setup_env/install_guards.bats
git commit -m "feat: update setup_dotfile_symlinks to source from AI_CONFIG_DIR"
```

---

### Task 8: Update setup_claude_mcp template path

**Files:**

- Modify: `lib/workflows.sh`
- Test: `tests/setup_env/install_guards.bats`

- [ ] **Step 1: Write failing test**

In `tests/setup_env/install_guards.bats`, add:

```bash
@test "setup_claude_mcp uses template from AI_CONFIG_DIR" {
  load_mocks
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  export AI_CONFIG_DIR="${BATS_TEST_TMPDIR}/ai-config"
  export GITHUB_PAT="test-pat-value"
  mkdir -p "${AI_CONFIG_DIR}/.claude"
  printf '{"token": "${GITHUB_PAT}"}\n' > "${AI_CONFIG_DIR}/.claude/mcp.json.template"
  local _home="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${_home}/.claude"
  export HOME="${_home}"

  run setup_claude_mcp
  [ "${status}" -eq 0 ]
  grep -q "test-pat-value" "${_home}/.claude/mcp.json"
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
make test 2>&1 | grep -A2 "mcp.*AI_CONFIG"
# Expected: FAIL — template not found at AI_CONFIG_DIR path
```

- [ ] **Step 3: Update template path in lib/workflows.sh**

In `setup_claude_mcp`, change:

```bash
local _template="${PERSONAL_GITREPOS}/${DOTFILES}/.claude/mcp.json.template"
```

to:

```bash
local _template="${AI_CONFIG_DIR}/.claude/mcp.json.template"
```

- [ ] **Step 4: Run test to verify it passes**

```bash
make test 2>&1 | grep -A2 "mcp.*AI_CONFIG"
# Expected: PASS
```

- [ ] **Step 5: Commit**

```bash
git add lib/workflows.sh tests/setup_env/install_guards.bats
git commit -m "feat: update setup_claude_mcp to read template from AI_CONFIG_DIR"
```

---

### Task 9: Re-point symlinks on the current machine and verify

No code changes — run the updated setup and verify the machine is working from ai-config before removing anything from dotfiles.

- [ ] **Step 1: Run setup_user to re-point symlinks**

```bash
cd ~/git-repos/personal/dotfiles
./setup_env.sh -t setup_user
```

- [ ] **Step 2: Verify .claude symlinks point to ai-config**

```bash
ls -la ~/.claude/CLAUDE.md ~/.claude/standards ~/.claude/skills ~/.claude/hooks
# Each should be a symlink pointing to ~/git-repos/personal/ai-config/.claude/...
```

- [ ] **Step 3: Verify .cursor symlinks point to ai-config**

```bash
ls -la ~/.cursor/rules ~/.cursor/plugins
# Each should be a symlink pointing to ~/git-repos/personal/ai-config/.cursor/...
```

- [ ] **Step 4: Verify Claude Code still works**

```bash
claude --version
# Open a new Claude Code session and run /help to verify skills load
```

- [ ] **Step 5: Run the dotfiles test suite to confirm no regressions**

```bash
make test
# Expected: all tests PASS
```

---

### Task 10: Remove .claude/, .cursor/, sync-agent-guidance from dotfiles

Only proceed once Task 9 verification passes.

**Files:**

- Delete: `.claude/` from dotfiles
- Delete: `.cursor/` from dotfiles
- Delete: `scripts/sync-agent-guidance.sh` from dotfiles
- Modify: `Makefile` — remove sync-agent-guidance targets
- Modify: `.github/workflows/ci.yml` — remove check-agent-guidance step

- [ ] **Step 1: Remove .claude/ and .cursor/ from dotfiles git**

```bash
cd ~/git-repos/personal/dotfiles
git rm -r .claude .cursor
```

- [ ] **Step 2: Remove sync-agent-guidance.sh**

```bash
git rm scripts/sync-agent-guidance.sh
```

- [ ] **Step 3: Remove sync-agent-guidance targets from dotfiles Makefile**

Remove the `sync-agent-guidance` and `check-agent-guidance` targets and their `.PHONY` entries from `Makefile`.

- [ ] **Step 4: Remove check-agent-guidance from CI**

In `.github/workflows/ci.yml`, remove any step that runs `make check-agent-guidance`.

- [ ] **Step 5: Run tests to confirm nothing broke**

```bash
make test
# Expected: all tests PASS (tests that referenced .claude/ fixtures now use AI_CONFIG_DIR)
```

- [ ] **Step 6: Commit and push via PR**

```bash
git add -A
git commit -m "chore: remove .claude/ and .cursor/ — now managed by ai-config repo"
git checkout -b chore/ai-config-split
git push -u origin chore/ai-config-split
gh pr create --title "chore: migrate .claude/ and .cursor/ to ai-config repo" \
  --body "$(cat <<'EOF'
## Summary
- Remove .claude/, .cursor/, scripts/sync-agent-guidance.sh from dotfiles
- Both directories now live in the private ai-config repo
- setup_env.sh auto-clones ai-config and re-points symlinks on setup_user

## Test plan
- [ ] CI passes
- [ ] setup_env.sh -t doctor passes on current machine
EOF
)"
```

---

### Task 11: End-to-end verification

- [ ] **Step 1: Run doctor**

```bash
./setup_env.sh -t doctor
# Expected: all checks pass including AI_CONFIG_DIR check
```

- [ ] **Step 2: Verify Cursor agent guidance is in sync**

```bash
cd ~/git-repos/personal/ai-config
make check-agent-guidance
# Expected: "Agent guidance is in sync"
```

- [ ] **Step 3: Open a fresh Claude Code session and verify**

```bash
claude
# Type /help — verify skills list shows pr-review, tdd, refactor
# Verify standards are loaded (CLAUDE.md @ includes resolve)
```

- [ ] **Step 4: Monitor PR CI and merge**

```bash
gh pr checks --watch
# Once all checks pass, PR auto-merges
```

- [ ] **Step 5: Post-merge cleanup**

```bash
git fetch --prune
git pull
git branch -D chore/ai-config-split
git push origin --delete chore/ai-config-split
```

---

### Task 12: Add CI and hooks to ai-config

**Files:**

- Create: `~/git-repos/personal/ai-config/.github/workflows/ci.yml`
- Create: `~/git-repos/personal/ai-config/scripts/pre-commit-hook.sh`
- Create: `~/git-repos/personal/ai-config/scripts/pre-push-hook.sh`

- [ ] **Step 1: Create pre-commit hook**

```bash
cat > ~/git-repos/personal/ai-config/scripts/pre-commit-hook.sh << 'EOF'
#!/usr/bin/env bash
set -e
if command -v ggshield &>/dev/null; then
    ggshield secret scan pre-commit
fi
EOF
chmod +x ~/git-repos/personal/ai-config/scripts/pre-commit-hook.sh
```

- [ ] **Step 2: Create pre-push hook**

```bash
cat > ~/git-repos/personal/ai-config/scripts/pre-push-hook.sh << 'EOF'
#!/usr/bin/env bash
# Pre-push hook: checks agent guidance sync before push reaches GitHub.
set -e

real_push=0
while read -r local_ref local_sha remote_ref remote_sha; do
    [ "${local_sha}" != "0000000000000000000000000000000000000000" ] && real_push=1
done
[ "${real_push}" -eq 0 ] && exit 0

printf "Checking agent guidance sync (pre-push)...\n"
make -C "$(cd "$(git rev-parse --git-common-dir)/.." && pwd)" check-agent-guidance
EOF
chmod +x ~/git-repos/personal/ai-config/scripts/pre-push-hook.sh
```

- [ ] **Step 3: Create .github/workflows/ci.yml**

```bash
mkdir -p ~/git-repos/personal/ai-config/.github/workflows
cat > ~/git-repos/personal/ai-config/.github/workflows/ci.yml << 'EOF'
name: CI

on:
  pull_request:
    branches:
      - master

env:
  FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: true

jobs:
  secret-scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
        with:
          fetch-depth: 0
      - name: Run Gitleaks
        uses: gitleaks/gitleaks-action@v2
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}

  auto-merge:
    needs: [secret-scan]
    runs-on: ubuntu-latest
    if: github.event_name == 'pull_request'
    steps:
      - uses: actions/checkout@v5
      - name: Auto-merge PR
        run: gh pr merge --squash --auto "${{ github.event.pull_request.number }}"
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
EOF
```

- [ ] **Step 4: Install hooks locally**

```bash
cd ~/git-repos/personal/ai-config
make install-hooks
```

- [ ] **Step 5: Commit and push via PR to exercise CI**

```bash
git add .github/workflows/ci.yml scripts/pre-commit-hook.sh scripts/pre-push-hook.sh
git commit -m "ci: add secrets scan, auto-merge, and git hooks"
git checkout -b ci/add-ci
git push -u origin ci/add-ci
gh pr create --title "ci: add secrets scan, auto-merge, and git hooks" \
  --body "Exercises CI pipeline for the first time. Verifies gitleaks scan and auto-merge work."
gh pr checks --watch
```

- [ ] **Step 6: Post-merge cleanup**

```bash
git fetch --prune && git pull
git branch -D ci/add-ci
git push origin --delete ci/add-ci
```

---

## Completion Checklist

- [ ] `ai-config` repo exists at `git@github.com:brujack/ai-config` (private)
- [ ] `~/.claude/` symlinks all resolve to `~/git-repos/personal/ai-config/.claude/`
- [ ] `~/.cursor/` symlinks all resolve to `~/git-repos/personal/ai-config/.cursor/`
- [ ] `setup_env.sh -t doctor` passes
- [ ] `make check-agent-guidance` passes in ai-config
- [ ] dotfiles no longer contains `.claude/` or `.cursor/`
- [ ] New machine bootstrap still works with single `setup_env.sh -t setup_user` command
- [ ] ai-config CI (gitleaks + auto-merge) is active
