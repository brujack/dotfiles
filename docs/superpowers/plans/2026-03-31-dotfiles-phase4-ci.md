# Phase 4: CI + ShellCheck Enforcement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add ShellCheck to `make lint`, create `.github/workflows/ci.yml` that runs lint + tests on every non-master branch push and auto-merges to master on green, and set up branch protection on master requiring the CI `test` job to pass.

**Architecture:** CI uses `actions/checkout@v5` (Node.js 24 native), installs `bats` and `shellcheck` via `apt-get`, runs `make test` (which already includes lint). Auto-merge job runs after the test job passes using `gh pr merge --auto`. ShellCheck is optional locally (prints a warning if missing) but required in CI. Branch protection blocks direct pushes to master and requires the `test` status check.

**Tech Stack:** GitHub Actions, ShellCheck, `gh` CLI, `make`

---

## Files

| File                       | Action                                           |
| -------------------------- | ------------------------------------------------ |
| `Makefile`                 | Modify — add shellcheck to `lint` target         |
| `.github/workflows/ci.yml` | Create — CI workflow with test + auto-merge jobs |

---

## Task 1: Fix ShellCheck issues in existing scripts

**Files:**

- Modify: `setup_env.sh`, `lib/*.sh`, `scripts/*.sh` as needed

ShellCheck must pass before adding it to the lint gate — otherwise CI will fail on the first push.

- [ ] **Step 1: Install ShellCheck locally if not present**

```bash
brew install shellcheck
```

- [ ] **Step 2: Run ShellCheck on all shell files**

```bash
shellcheck $(find . -name "*.sh" -not -path "*/node_modules/*")
```

- [ ] **Step 3: Fix or suppress all ShellCheck findings**

Common patterns to fix:

**SC2164 — `cd` without exit guard:**

```bash
# Before
cd ${HOME}/software_downloads/awscli

# After
cd "${HOME}/software_downloads/awscli" || exit
```

**SC2086 — unquoted variable expansion:**

```bash
# Before
ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.zshrc ${HOME}/.zshrc

# After
ln -s "${PERSONAL_GITREPOS}/${DOTFILES}/.zshrc" "${HOME}/.zshrc"
```

**SC2046 — unquoted command substitution (e.g. `eval` patterns that cannot be fixed):**

```bash
# Add inline disable with explanation
# shellcheck disable=SC2046 — intentional: eval of brew shellenv output
eval "$(brew shellenv)"
```

**RHEL_KUBECTL_REPO heredoc-in-variable (SC2089/SC2090):**

```bash
# shellcheck disable=SC2089,SC2090 — intentional: heredoc stored as string for deferred eval
RHEL_KUBECTL_REPO="cat <<EOF | ..."
```

For each finding: fix it if possible, add `# shellcheck disable=SCxxxx — <reason>` if not.

- [ ] **Step 4: Confirm ShellCheck passes**

```bash
shellcheck $(find . -name "*.sh" -not -path "*/node_modules/*")
```

Expected: exit 0 with no output (or only disabled warnings shown inline).

---

## Task 2: Update `Makefile` lint target with ShellCheck

**Files:**

- Modify: `Makefile`

- [ ] **Step 1: Add `SHELLCHECK` variable and update `lint` target**

Current `Makefile` top section and `lint` target:

```makefile
BATS := $(shell command -v bats 2>/dev/null)
SHELL_FILES := $(shell find . -name "*.sh" -not -path "*/node_modules/*")

lint:
	@failed=0; \
	for f in $(SHELL_FILES); do \
	  bash -n "$$f" && printf "bash  OK  %s\n" "$$f" || { printf "bash FAIL %s\n" "$$f"; failed=1; }; \
	  zsh  -n "$$f" && printf "zsh   OK  %s\n" "$$f" || { printf "zsh  FAIL %s\n" "$$f"; failed=1; }; \
	done; \
	exit $$failed
```

Updated version:

```makefile
BATS := $(shell command -v bats 2>/dev/null)
SHELLCHECK := $(shell command -v shellcheck 2>/dev/null)
SHELL_FILES := $(shell find . -name "*.sh" -not -path "*/node_modules/*")

lint:
ifdef SHELLCHECK
	shellcheck $(SHELL_FILES)
else
	@printf "shellcheck not found — skipping (install: brew install shellcheck)\n"
endif
	@failed=0; \
	for f in $(SHELL_FILES); do \
	  bash -n "$$f" && printf "bash  OK  %s\n" "$$f" || { printf "bash FAIL %s\n" "$$f"; failed=1; }; \
	  zsh  -n "$$f" && printf "zsh   OK  %s\n" "$$f" || { printf "zsh  FAIL %s\n" "$$f"; failed=1; }; \
	done; \
	exit $$failed
```

- [ ] **Step 2: Run `make test` to confirm lint + tests still pass**

```bash
make test
```

Expected: exit 0. ShellCheck runs (if installed) and all BATS tests pass.

- [ ] **Step 3: Commit ShellCheck fixes and Makefile update**

```bash
git add Makefile setup_env.sh lib/ scripts/
git commit -m "feat: add shellcheck to make lint target

shellcheck is optional locally (skipped with warning if not installed)
but will be required in CI. All existing shellcheck findings fixed
or suppressed with inline disable comments explaining why.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 3: Create `.github/workflows/ci.yml`

**Files:**

- Create: `.github/workflows/ci.yml`

- [ ] **Step 1: Create the `.github/workflows/` directory structure**

```bash
mkdir -p .github/workflows
```

- [ ] **Step 2: Create `.github/workflows/ci.yml`**

```yaml
name: CI

on:
  push:
    branches-ignore: [master]

env:
  FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: true

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - name: Install bats and shellcheck
        run: sudo apt-get install -y bats shellcheck
      - name: Run tests
        run: make test

  auto-merge:
    needs: [test]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - name: Auto-merge to master
        run: gh pr merge --auto --merge "${{ github.ref_name }}"
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

- [ ] **Step 3: Validate YAML syntax**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))" && printf "YAML valid\n"
```

Expected: `YAML valid` with no errors. (python3 and PyYAML are available on macOS via brew; if not available, skip this step and rely on GitHub's validator.)

- [ ] **Step 4: Commit the CI workflow**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: add GitHub Actions CI with auto-merge on green

On any push to a non-master branch:
- Installs bats and shellcheck on ubuntu-latest
- Runs make test (lint + all BATS tests)
- Auto-merges the PR to master if all checks pass

Uses actions/checkout@v5 (Node.js 24 native) and
FORCE_JAVASCRIPT_ACTIONS_TO_NODE24 for third-party actions.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 4: Set up branch protection on master

This is a one-time manual step run after the CI workflow is pushed and has run at least once (so the `test` context exists in GitHub).

- [ ] **Step 1: Push the current branch to create a PR so CI runs**

```bash
git push -u origin phase/4-ci-shellcheck
gh pr create --title "Phase 4: CI + ShellCheck enforcement" --body "Adds shellcheck to make lint and GitHub Actions CI with auto-merge."
```

- [ ] **Step 2: Wait for CI to pass and confirm the `test` context exists**

```bash
gh pr checks
```

Expected: `test` check shows as passed.

- [ ] **Step 3: Set up branch protection on master**

```bash
gh api repos/brujack/dotfiles/branches/master/protection \
  --method PUT \
  --field required_status_checks='{"strict":true,"contexts":["test"]}' \
  --field enforce_admins=false \
  --field required_pull_request_reviews=null \
  --field restrictions=null
```

Expected: HTTP 200 response with the updated protection rules JSON.

- [ ] **Step 4: Verify branch protection is active**

```bash
gh api repos/brujack/dotfiles/branches/master/protection | python3 -m json.tool | grep -A3 "required_status_checks"
```

Expected: `"contexts": ["test"]` visible in output.

---

## Task 5: Verify auto-merge on the Phase 4 PR

- [ ] **Step 1: Confirm the Phase 4 PR was auto-merged after CI passed**

```bash
gh pr list --state merged --limit 5
```

Expected: the Phase 4 PR shows as merged.

If auto-merge did not trigger (e.g., the PR was created before branch protection existed), merge manually:

```bash
gh pr merge --merge phase/4-ci-shellcheck
```
