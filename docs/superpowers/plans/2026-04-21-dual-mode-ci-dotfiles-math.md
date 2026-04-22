> **Status: DONE**

# Dual-Mode CI: Pre-push Local Gate + GitHub Actions Final Gate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a permanent pre-push hook to dotfiles and math repos that runs tests locally before every push, and change GitHub Actions CI triggers to PR-only so GitHub is the final merge gate.

**Architecture:** Three independent targets — dotfiles repo, math repo, and the global `~/.claude/CLAUDE.md` (which is a symlink into the dotfiles repo). Each repo gets a new `scripts/pre-push` file, an updated `make install-hooks` target, and CI workflow trigger changes. The global CLAUDE.md gets two new bullets codifying this as the standard for all personal repos.

**Tech Stack:** bash (pre-push hooks), Makefile, GitHub Actions YAML, Markdown

---

## File Map

**dotfiles repo** (`/home/bruce/git-repos/personal/dotfiles/`):

- Create: `scripts/pre-push`
- Modify: `Makefile` (install-hooks target)
- Modify: `.github/workflows/ci.yml` (remove push trigger)
- Modify: `CLAUDE.md` (update Testing section)
- Modify: `.claude/CLAUDE.md` (global, add pre-push + CI trigger bullets)

**math repo** (`/home/bruce/git-repos/personal/math/`):

- Create: `scripts/pre-push`
- Modify: `Makefile` (install-hooks target)
- Modify: `.github/workflows/fib-rs.yml` (remove push trigger)
- Modify: `.github/workflows/pi-rs.yml` (remove push trigger)
- Modify: `.github/workflows/prime-rs.yml` (remove push trigger)
- Modify: `.github/workflows/sq-rs.yml` (remove push trigger)
- Modify: `.github/workflows/twin-primes-rs.yml` (remove push trigger)
- Modify: `.github/workflows/pi-py.yml` (remove push trigger)
- Modify: `.github/workflows/fib-py.yml` (remove push trigger)
- Modify: `.github/workflows/sq-py.yml` (remove push trigger)
- Modify: `CLAUDE.md` (update CI section and new-project template)

---

### Task 1: Dotfiles — feature branch + scripts/pre-push

**Files:**

- Create: `scripts/pre-push` (in dotfiles worktree)

- [ ] **Step 1: Create a worktree for the feature branch**

```bash
cd /home/bruce/git-repos/personal/dotfiles
git fetch origin
git worktree add .worktrees/feat/dual-mode-ci feat/dual-mode-ci 2>/dev/null \
  || (git branch feat/dual-mode-ci origin/master 2>/dev/null || git branch feat/dual-mode-ci master; \
      git worktree add .worktrees/feat/dual-mode-ci feat/dual-mode-ci)
```

All subsequent dotfiles steps work in: `/home/bruce/git-repos/personal/dotfiles/.worktrees/feat/dual-mode-ci`

- [ ] **Step 2: Create scripts/pre-push**

Write `/home/bruce/git-repos/personal/dotfiles/.worktrees/feat/dual-mode-ci/scripts/pre-push` with this exact content:

```bash
#!/usr/bin/env bash
# Pre-push hook: runs full test suite locally before push reaches GitHub.
# Permanent: provides fast local feedback and conserves GitHub Actions minutes.
# GitHub Actions is the final merge gate on PRs.
set -e

while read -r local_ref local_sha remote_ref remote_sha; do
    [ "${local_sha}" = "0000000000000000000000000000000000000000" ] && exit 0
done

printf "Running tests locally (pre-push)...\n"
make -C "$(git rev-parse --show-toplevel)" test
```

- [ ] **Step 3: Make it executable**

```bash
chmod +x /home/bruce/git-repos/personal/dotfiles/.worktrees/feat/dual-mode-ci/scripts/pre-push
```

- [ ] **Step 4: Verify the file is executable and content is correct**

```bash
ls -la /home/bruce/git-repos/personal/dotfiles/.worktrees/feat/dual-mode-ci/scripts/pre-push
head -5 /home/bruce/git-repos/personal/dotfiles/.worktrees/feat/dual-mode-ci/scripts/pre-push
```

Expected: `-rwxrwxr-x` permissions and shebang line visible.

- [ ] **Step 5: Commit**

```bash
cd /home/bruce/git-repos/personal/dotfiles/.worktrees/feat/dual-mode-ci
git add scripts/pre-push
git commit -m "feat: add permanent pre-push hook to run tests locally

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 2: Dotfiles — update Makefile install-hooks

**Files:**

- Modify: `Makefile` (in dotfiles worktree)

All steps run in: `/home/bruce/git-repos/personal/dotfiles/.worktrees/feat/dual-mode-ci`

- [ ] **Step 1: Read the current install-hooks target**

Run: `grep -A 3 "install-hooks:" Makefile`

Expected current content:

```makefile
install-hooks:
	ln -sf "$(shell pwd)/scripts/pre-commit-hook.sh" .git/hooks/pre-commit
	@printf "Pre-commit hook installed at .git/hooks/pre-commit\n"
```

- [ ] **Step 2: Replace the install-hooks target**

Edit `Makefile` — replace the install-hooks target with:

```makefile
install-hooks:
	ln -sf "$(shell pwd)/scripts/pre-commit-hook.sh" .git/hooks/pre-commit
	ln -sf "$(shell pwd)/scripts/pre-push" .git/hooks/pre-push
	@printf "Pre-commit and pre-push hooks installed\n"
```

- [ ] **Step 3: Run install-hooks and verify both symlinks exist**

```bash
make install-hooks
ls -la .git/hooks/pre-commit .git/hooks/pre-push
```

Expected: both are symlinks pointing to their respective scripts files.

- [ ] **Step 4: Commit**

```bash
git add Makefile
git commit -m "feat: install-hooks now installs pre-push alongside pre-commit

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 3: Dotfiles — update CI workflow to PR-only

**Files:**

- Modify: `.github/workflows/ci.yml` (in dotfiles worktree)

All steps run in: `/home/bruce/git-repos/personal/dotfiles/.worktrees/feat/dual-mode-ci`

- [ ] **Step 1: Read the current trigger block**

Run: `head -10 .github/workflows/ci.yml`

Expected:

```yaml
name: CI

on:
  push:
  pull_request:
    branches:
      - master
```

- [ ] **Step 2: Replace the trigger block**

Edit `.github/workflows/ci.yml` — replace:

```yaml
on:
  push:
  pull_request:
    branches:
      - master
```

with:

```yaml
on:
  pull_request:
    branches:
      - master
```

- [ ] **Step 3: Verify**

Run: `head -10 .github/workflows/ci.yml`

Expected: no `push:` line present, only `pull_request:`.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: trigger on PRs only, pre-push hook handles branch-push gate

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 4: Dotfiles — update dotfiles CLAUDE.md + global CLAUDE.md

**Files:**

- Modify: `CLAUDE.md` (in dotfiles worktree)
- Modify: `.claude/CLAUDE.md` (global, in dotfiles worktree — symlinked to `~/.claude/CLAUDE.md`)

All steps run in: `/home/bruce/git-repos/personal/dotfiles/.worktrees/feat/dual-mode-ci`

- [ ] **Step 1: Update dotfiles CLAUDE.md Testing section**

In `CLAUDE.md`, find the line:

```
**Install pre-commit hook:** `make install-hooks` (symlinks `scripts/pre-commit-hook.sh` into `.git/hooks/pre-commit`; run once per checkout)
```

Replace it with:

```
**Install hooks:** `make install-hooks` (symlinks `scripts/pre-commit-hook.sh` into `.git/hooks/pre-commit` and `scripts/pre-push` into `.git/hooks/pre-push`; run once per checkout)
```

Then find the paragraph:

```
The pre-commit hook is **required**. It runs on every `git commit`:

1. `make lint` — blocks the commit on any syntax or shellcheck failure
2. `ggshield secret scan pre-commit` — scans staged changes for secrets before they reach the remote; skipped gracefully if ggshield is not installed

The CI `secret-scan` job (gitleaks) is a backstop, not a substitute for local scanning. Install ggshield: `brew install gitguardian/tap/ggshield && ggshield auth login`.
```

Replace it with:

```
Both hooks are **required**. Run `make install-hooks` once per checkout.

**Pre-commit hook** (`scripts/pre-commit-hook.sh`) — runs on every `git commit`:

1. `make lint` — blocks the commit on any syntax or shellcheck failure
2. `ggshield secret scan pre-commit` — scans staged changes for secrets; skipped gracefully if not installed

**Pre-push hook** (`scripts/pre-push`) — runs on every `git push`:

1. `make test` — runs lint + full BATS test suite; blocks the push on any failure
2. Permanent: conserves GitHub Actions minutes. GitHub Actions is the final merge gate on PRs.

The CI `secret-scan` job (gitleaks) is a backstop, not a substitute for local scanning. Install ggshield: `brew install gitguardian/tap/ggshield && ggshield auth login`.
```

- [ ] **Step 2: Update the global CLAUDE.md Personal Repos section**

In `.claude/CLAUDE.md`, find the Personal Repos section. It currently ends with item 4 (pre-commit hook) and two template blocks. Add items 5 and 6 immediately after the last template block (the multi-project template that ends with `fi`):

After the closing `   ` (end of item 4's multi-project template), add:

````markdown
5. **Pre-push hook (permanent):** every personal repo must have a `scripts/pre-push` file (committed to the repo, symlinked via `make install-hooks`). The hook must:
   - Run the repo's test suite (e.g. `make test`) before every push
   - Skip branch deletions (zero SHA check on `local_sha`)
   - For multi-project repos, detect changed sub-projects using the push range (`remote_sha..local_sha`) and run `make -C <dir> test` only for those dirs
   - Be permanent — not a temporary workaround. Document it as such in comments.

   Template for single-Makefile repos:

   ```bash
   #!/usr/bin/env bash
   # Pre-push hook: runs full test suite locally before push reaches GitHub.
   # Permanent: provides fast local feedback and conserves GitHub Actions minutes.
   # GitHub Actions is the final merge gate on PRs.
   set -e

   while read -r local_ref local_sha remote_ref remote_sha; do
       [ "${local_sha}" = "0000000000000000000000000000000000000000" ] && exit 0
   done

   printf "Running tests locally (pre-push)...\n"
   make -C "$(git rev-parse --show-toplevel)" test
   ```
````

Template for multi-project repos (adapt dir list to the repo):

```bash
#!/usr/bin/env bash
# Pre-push hook: runs tests for changed sub-projects before push reaches GitHub.
# Permanent: provides fast local feedback and conserves GitHub Actions minutes.
# GitHub Actions is the final merge gate on PRs.
set -e

REPO_ROOT="$(git rev-parse --show-toplevel)"
DIRS_TO_TEST=()

while read -r local_ref local_sha remote_ref remote_sha; do
    [ "${local_sha}" = "0000000000000000000000000000000000000000" ] && continue

    if [ "${remote_sha}" = "0000000000000000000000000000000000000000" ]; then
        base="$(git merge-base "${local_sha}" origin/master 2>/dev/null \
            || git rev-list --max-parents=0 "${local_sha}")"
        range="${base}..${local_sha}"
    else
        range="${remote_sha}..${local_sha}"
    fi

    for dir in proj1 proj1/proj1-rs proj2 proj2/proj2-rs; do
        if git diff --name-only "${range}" | grep -q "^${dir}/"; then
            DIRS_TO_TEST+=("${dir}")
        fi
    done
done

if [ "${#DIRS_TO_TEST[@]}" -eq 0 ]; then
    printf "No changed sub-projects detected. Skipping tests.\n"
    exit 0
fi

for dir in $(printf '%s\n' "${DIRS_TO_TEST[@]}" | sort -u); do
    printf "test: %s\n" "${dir}"
    make -C "${REPO_ROOT}/${dir}" test
done
```

6. **GitHub Actions CI triggers:** workflows must trigger on `pull_request` only — never on bare `push:` or `branches-ignore:` push triggers. The pre-push hook is the branch-push gate; GitHub Actions is the PR merge gate. For badge URLs, use `?event=pull_request` (e.g. `badge.svg?event=pull_request`) — workflows only run on PRs so they never run on master directly; `?branch=master` and bare `badge.svg` always show "no status".

```

- [ ] **Step 3: Also update the CI badge URL note in the GitHub Actions / CI section**

In `.claude/CLAUDE.md`, find the line in "## GitHub Actions / CI":
```

- CI badge URLs in `README.md` must use `?event=pull_request` (e.g. `badge.svg?event=pull_request`) — workflows use `branches-ignore: [master]` so they never run on master directly; `?branch=master` and bare `badge.svg` both default to master runs and always show "no status"

```

Replace with:
```

- CI badge URLs in `README.md` must use `?event=pull_request` (e.g. `badge.svg?event=pull_request`) — workflows trigger on `pull_request` only, so they never run on master directly; `?branch=master` and bare `badge.svg` both default to master runs and always show "no status"

````

- [ ] **Step 4: Verify both files look correct**

```bash
grep -A 5 "Pre-push hook" CLAUDE.md
grep -A 3 "Pre-push hook (permanent)" .claude/CLAUDE.md
grep "CI badge URLs" .claude/CLAUDE.md
````

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md .claude/CLAUDE.md
git commit -m "docs: document dual-mode CI strategy in CLAUDE.md files

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 5: Dotfiles — push PR and monitor

**Files:** none (git operations only)

All steps run in: `/home/bruce/git-repos/personal/dotfiles/.worktrees/feat/dual-mode-ci`

- [ ] **Step 1: Verify the branch looks clean**

```bash
git log --oneline origin/master..HEAD
```

Expected: 4 commits (pre-push script, Makefile, CI workflow, CLAUDE.md updates).

- [ ] **Step 2: Push the branch**

```bash
git push -u origin feat/dual-mode-ci
```

- [ ] **Step 3: Create the PR**

```bash
gh pr create \
  --title "feat: dual-mode CI — permanent pre-push hook + PR-only GitHub Actions" \
  --body "$(cat <<'EOF'
## Summary
- Add permanent `scripts/pre-push` hook that runs `make test` before every push
- Update `make install-hooks` to install pre-push alongside pre-commit
- Remove bare `push:` trigger from CI workflow; GitHub Actions now triggers on PRs only
- Update `CLAUDE.md` and global `~/.claude/CLAUDE.md` with dual-mode CI strategy

## Test Plan
- [ ] `make install-hooks` creates symlinks for both pre-commit and pre-push in `.git/hooks/`
- [ ] `git push` on a feature branch triggers the pre-push hook and runs `make test`
- [ ] CI workflow only triggers on PRs, not on bare branch pushes
EOF
)"
```

- [ ] **Step 4: Monitor CI**

```bash
gh pr checks --watch
```

Wait for all checks to pass. If any fail, read the failure output:

```bash
gh run view --log-failed
```

Fix, commit, push — CI re-runs automatically.

- [ ] **Step 5: After CI passes, note the PR number for cleanup**

```bash
gh pr view --json number,state
```

---

### Task 6: Math — feature branch + scripts/pre-push

**Files:**

- Create: `scripts/pre-push` (in math worktree)

- [ ] **Step 1: Create a worktree for the feature branch**

```bash
cd /home/bruce/git-repos/personal/math
git fetch origin
git worktree add .worktrees/feat/dual-mode-ci feat/dual-mode-ci 2>/dev/null \
  || (git branch feat/dual-mode-ci origin/master 2>/dev/null || git branch feat/dual-mode-ci master; \
      git worktree add .worktrees/feat/dual-mode-ci feat/dual-mode-ci)
```

All subsequent math steps work in: `/home/bruce/git-repos/personal/math/.worktrees/feat/dual-mode-ci`

- [ ] **Step 2: Create scripts/pre-push**

Write `/home/bruce/git-repos/personal/math/.worktrees/feat/dual-mode-ci/scripts/pre-push` with this exact content:

```bash
#!/usr/bin/env bash
# Pre-push hook: runs tests for changed sub-projects before push reaches GitHub.
# Permanent: provides fast local feedback and conserves GitHub Actions minutes.
# GitHub Actions is the final merge gate on PRs.
set -e

REPO_ROOT="$(git rev-parse --show-toplevel)"
DIRS_TO_TEST=()

while read -r local_ref local_sha remote_ref remote_sha; do
    [ "${local_sha}" = "0000000000000000000000000000000000000000" ] && continue

    if [ "${remote_sha}" = "0000000000000000000000000000000000000000" ]; then
        base="$(git merge-base "${local_sha}" origin/master 2>/dev/null \
            || git rev-list --max-parents=0 "${local_sha}")"
        range="${base}..${local_sha}"
    else
        range="${remote_sha}..${local_sha}"
    fi

    for dir in pi pi/pi-rs prime/prime-rs fib fib/fib-rs sq sq/sq-rs twin-primes/twin-primes-rs; do
        if git diff --name-only "${range}" | grep -q "^${dir}/"; then
            DIRS_TO_TEST+=("${dir}")
        fi
    done
done

if [ "${#DIRS_TO_TEST[@]}" -eq 0 ]; then
    printf "No changed sub-projects detected. Skipping tests.\n"
    exit 0
fi

for dir in $(printf '%s\n' "${DIRS_TO_TEST[@]}" | sort -u); do
    printf "test: %s\n" "${dir}"
    make -C "${REPO_ROOT}/${dir}" test
done
```

- [ ] **Step 3: Make it executable**

```bash
chmod +x /home/bruce/git-repos/personal/math/.worktrees/feat/dual-mode-ci/scripts/pre-push
```

- [ ] **Step 4: Verify**

```bash
ls -la /home/bruce/git-repos/personal/math/.worktrees/feat/dual-mode-ci/scripts/pre-push
```

Expected: `-rwxrwxr-x` permissions.

- [ ] **Step 5: Commit**

```bash
cd /home/bruce/git-repos/personal/math/.worktrees/feat/dual-mode-ci
git add scripts/pre-push
git commit -m "feat: add permanent pre-push hook for changed sub-projects

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 7: Math — update root Makefile install-hooks

**Files:**

- Modify: `Makefile` (in math worktree)

All steps run in: `/home/bruce/git-repos/personal/math/.worktrees/feat/dual-mode-ci`

- [ ] **Step 1: Read the current install-hooks target**

Run: `cat Makefile`

Expected:

```makefile
.PHONY: install-hooks

install-hooks:
	ln -sf "../../scripts/pre-commit" "$$(git rev-parse --git-path hooks)/pre-commit"
	@printf "pre-commit hook installed\n"
```

- [ ] **Step 2: Replace the install-hooks target**

Write `Makefile` with this exact content:

```makefile
.PHONY: install-hooks

install-hooks:
	ln -sf "../../scripts/pre-commit" "$$(git rev-parse --git-path hooks)/pre-commit"
	ln -sf "../../scripts/pre-push" "$$(git rev-parse --git-path hooks)/pre-push"
	@printf "pre-commit and pre-push hooks installed\n"
```

- [ ] **Step 3: Run install-hooks and verify both symlinks exist**

```bash
make install-hooks
ls -la "$(git rev-parse --git-path hooks)/pre-commit" "$(git rev-parse --git-path hooks)/pre-push"
```

Expected: both symlinks point to `../../scripts/pre-commit` and `../../scripts/pre-push` respectively.

- [ ] **Step 4: Commit**

```bash
git add Makefile
git commit -m "feat: install-hooks now installs pre-push alongside pre-commit

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 8: Math — update all CI workflow triggers

**Files:**

- Modify: `.github/workflows/fib-rs.yml`, `pi-rs.yml`, `prime-rs.yml`, `sq-rs.yml`, `twin-primes-rs.yml`, `pi-py.yml`, `fib-py.yml`, `sq-py.yml`

All steps run in: `/home/bruce/git-repos/personal/math/.worktrees/feat/dual-mode-ci`

All 8 workflows currently have this trigger block:

```yaml
on:
  push:
    branches-ignore:
      - master
  pull_request:
    branches:
      - master
```

Replace with this in every file:

```yaml
on:
  pull_request:
    branches:
      - master
```

- [ ] **Step 1: Update fib-rs.yml**

Edit `.github/workflows/fib-rs.yml` — replace the trigger block (lines 3-9) with:

```yaml
on:
  pull_request:
    branches:
      - master
```

- [ ] **Step 2: Update pi-rs.yml**

Edit `.github/workflows/pi-rs.yml` — same replacement as Step 1.

- [ ] **Step 3: Update prime-rs.yml**

Edit `.github/workflows/prime-rs.yml` — same replacement as Step 1.

- [ ] **Step 4: Update sq-rs.yml**

Edit `.github/workflows/sq-rs.yml` — same replacement as Step 1.

- [ ] **Step 5: Update twin-primes-rs.yml**

Edit `.github/workflows/twin-primes-rs.yml` — same replacement as Step 1.

- [ ] **Step 6: Update pi-py.yml**

Edit `.github/workflows/pi-py.yml` — same replacement as Step 1.

- [ ] **Step 7: Update fib-py.yml**

Edit `.github/workflows/fib-py.yml` — same replacement as Step 1.

- [ ] **Step 8: Update sq-py.yml**

Edit `.github/workflows/sq-py.yml` — same replacement as Step 1.

- [ ] **Step 9: Verify no workflow still has the push trigger**

```bash
grep -l "branches-ignore" .github/workflows/*.yml
```

Expected: no output (no files match).

- [ ] **Step 10: Commit**

```bash
git add .github/workflows/
git commit -m "ci: trigger on PRs only, pre-push hook handles branch-push gate

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 9: Math — update math CLAUDE.md

**Files:**

- Modify: `CLAUDE.md` (in math worktree)

All steps run in: `/home/bruce/git-repos/personal/math/.worktrees/feat/dual-mode-ci`

- [ ] **Step 1: Update the CI section intro line**

In `CLAUDE.md`, find:

```
Nine workflow files. Project workflows run on feature branch pushes and on PRs to `master` (never on direct master pushes).
```

Replace with:

```
Nine workflow files. Project workflows run on PRs to `master` only (never on direct branch or master pushes). The pre-push hook handles local testing on branch pushes.
```

- [ ] **Step 2: Update the pre-commit hook paragraph to mention pre-push**

Find:

```
**Pre-commit hook** — `scripts/pre-commit` is committed to the repo and installed as a symlink via `make install-hooks`. It runs `make lint` on staged sub-projects and `ggshield secret scan pre-commit` (skipped if not installed). CI gitleaks is a backstop — install and activate ggshield locally so secrets are caught before they leave the machine.
```

Replace with:

```
**Pre-commit hook** — `scripts/pre-commit` is committed to the repo and installed as a symlink via `make install-hooks`. It runs `make lint` on staged sub-projects and `ggshield secret scan pre-commit` (skipped if not installed). CI gitleaks is a backstop — install and activate ggshield locally so secrets are caught before they leave the machine.

**Pre-push hook** — `scripts/pre-push` is committed to the repo and installed as a symlink via `make install-hooks`. It detects which sub-projects have commits in the push range (`remote_sha..local_sha`) and runs `make test` for each. Permanent: conserves GitHub Actions minutes. GitHub Actions is the final merge gate on PRs. Run `make install-hooks` once per checkout to activate both hooks.
```

- [ ] **Step 3: Update the "When adding a new project" trigger template**

Find:

```
- Trigger: `push: branches-ignore: [master]` and `pull_request: branches: [master]`
```

Replace with:

```
- Trigger: `pull_request: branches: [master]` only (pre-push hook handles branch-push testing locally)
```

Also add the new sub-project dir to `scripts/pre-push` — find the line in the "When adding a new project" section that describes workflow file creation and append:

Find the bullet that starts `- A badge for the new workflow` (or the last bullet in that list) and add a new bullet after it:

```
- Add the new sub-project dir (and its `-rs` sibling if applicable) to the `for dir in ...` list in `scripts/pre-push`
```

- [ ] **Step 4: Verify changes**

```bash
grep -A 3 "Project workflows run" CLAUDE.md
grep -A 2 "Pre-push hook" CLAUDE.md
grep "Trigger:" CLAUDE.md
```

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CI section for pre-push hook and PR-only triggers

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 10: Math — push PR and monitor

**Files:** none (git operations only)

All steps run in: `/home/bruce/git-repos/personal/math/.worktrees/feat/dual-mode-ci`

- [ ] **Step 1: Verify branch commits**

```bash
git log --oneline origin/master..HEAD
```

Expected: 4 commits (pre-push script, Makefile, CI workflows, CLAUDE.md).

- [ ] **Step 2: Push and create PR**

```bash
git push -u origin feat/dual-mode-ci

gh pr create \
  --title "feat: dual-mode CI — permanent pre-push hook + PR-only GitHub Actions" \
  --body "$(cat <<'EOF'
## Summary
- Add permanent `scripts/pre-push` hook that detects changed sub-projects by push range and runs `make test` for each
- Update `make install-hooks` to install pre-push alongside pre-commit
- Remove `push: branches-ignore: [master]` trigger from all 8 sub-project CI workflows; GitHub Actions now triggers on PRs only
- Update `CLAUDE.md` with pre-push hook docs and updated new-project template

## Test Plan
- [ ] `make install-hooks` creates symlinks for both pre-commit and pre-push
- [ ] `git push` on a branch with fib changes triggers tests for `fib` and `fib/fib-rs` only
- [ ] `git push` on a branch with no sub-project changes prints "No changed sub-projects" and exits 0
- [ ] No CI workflow has a `push: branches-ignore:` trigger
EOF
)"
```

- [ ] **Step 3: Monitor CI**

```bash
gh pr checks --watch
```

Wait for all checks to pass. If any fail:

```bash
gh run view --log-failed
```

Fix the issue, commit, push — CI re-runs automatically.

- [ ] **Step 4: Note the PR number**

```bash
gh pr view --json number,state
```
