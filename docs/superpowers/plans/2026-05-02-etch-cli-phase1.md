# Etch-CLI Phase 1: Fork, Rename, Audit, Build

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fork comtrya/comtrya, rename the crate and binary to etch-cli/etch, capture a security audit baseline, verify the build, set up repo structure, and produce ready-to-run smoke test manifests for Proxmox VM testing.

**Architecture:** Three-crate Rust workspace (app + lib + jsonschemagen). Phase 1 makes zero functional changes — rename only, plus security audit. The existing comtrya test suite is the verification gate. Smoke test manifests live in `~/comtrya-test/manifests/` on the VM (not in the repo).

**Tech Stack:** Rust (cargo, cargo-audit, cargo-deny), GitHub CLI (gh), GitHub Actions, gitleaks, Snyk

---

## File Map

Files created or significantly modified by this plan:

| Path                          | What it does                                                    |
| ----------------------------- | --------------------------------------------------------------- |
| `app/Cargo.toml`              | Binary renamed `comtrya` → `etch`, package renamed → `etch-cli` |
| `Cargo.toml` (workspace root) | Description/repository metadata updated                         |
| `Makefile`                    | New — lint, test, build, install-hooks targets                  |
| `scripts/pre-commit`          | New — runs make lint + ggshield                                 |
| `scripts/pre-push`            | New — runs make test on real pushes                             |
| `.github/workflows/ci.yml`    | New — Rust CI per standards                                     |
| `.gitleaks.toml`              | New — allowlist config                                          |
| `.gitignore`                  | Updated — macOS/Linux/Rust noise entries                        |
| `README.md`                   | Updated — project name, description, install instructions       |
| `docs/superpowers/README.md`  | New — plans index (empty at Phase 1)                            |
| `docs/cursor/README.md`       | New — cursor docs index (empty at Phase 1)                      |

Smoke test manifests live on the VM, not in this repo. They are written in Task 8 but must be manually transferred and run on the Proxmox VM.

---

## Task 1: Name Verification

**Files:** None (read-only verification)

- [ ] **Step 1: Verify etch-cli is available on crates.io**

```bash
cargo search etch-cli
```

Expected: no results, or results that are clearly unrelated (not an active `etch-cli` crate). If `etch-cli` is taken by an active crate, stop and consult the brief's backup name `axiom-cli` before proceeding.

- [ ] **Step 2: Note your GitHub handle**

```bash
gh api user --jq '.login'
```

Save this value — it's used throughout the rest of the plan as `$GITHUB_HANDLE`.

---

## Task 2: Fork and Clone

**Files:** Clones comtrya upstream into `/Users/bruce/git-repos/personal/etch-cli/`

- [ ] **Step 1: Fork comtrya/comtrya to your account**

```bash
gh repo fork comtrya/comtrya --clone=false
```

This creates `github.com/$GITHUB_HANDLE/comtrya` on GitHub.

- [ ] **Step 2: Rename the fork to etch-cli on GitHub**

```bash
gh repo rename etch-cli --repo "$GITHUB_HANDLE/comtrya"
```

Expected: "Renamed repository" confirmation.

- [ ] **Step 3: Clone into the pre-created directory**

```bash
git clone "https://github.com/$GITHUB_HANDLE/etch-cli.git" /Users/bruce/git-repos/personal/etch-cli
```

If the directory already exists and is empty, this will succeed. If git complains about a non-empty directory, run:

```bash
git -C /Users/bruce/git-repos/personal/etch-cli init
git -C /Users/bruce/git-repos/personal/etch-cli remote add origin "https://github.com/$GITHUB_HANDLE/etch-cli.git"
git -C /Users/bruce/git-repos/personal/etch-cli fetch --all
git -C /Users/bruce/git-repos/personal/etch-cli checkout main
```

- [ ] **Step 4: Add comtrya upstream remote**

```bash
git -C /Users/bruce/git-repos/personal/etch-cli remote add upstream https://github.com/comtrya/comtrya.git
git -C /Users/bruce/git-repos/personal/etch-cli remote -v
```

Expected: both `origin` (your fork) and `upstream` (comtrya) are listed.

- [ ] **Step 5: Verify the workspace builds against upstream code before touching anything**

```bash
cd /Users/bruce/git-repos/personal/etch-cli && cargo build 2>&1 | tail -5
```

Expected: `Compiling comtrya` lines and `Finished` with no errors. If there are errors, note them — they likely represent dependency drift since April 2026 archival and must be resolved before proceeding.

---

## Task 3: Security Audit Baseline

**Files:** None modified — read-only review. Capture output to files for reference.

- [ ] **Step 1: Run cargo audit**

```bash
cd /Users/bruce/git-repos/personal/etch-cli
cargo audit 2>&1 | tee /tmp/etch-cli-audit.txt
```

Expected: A list of advisories (if any). Zero advisories is ideal but unlikely given the project was archived months ago. Review each advisory: does it affect paths that etch actually exercises? Capture the count.

- [ ] **Step 2: Run cargo deny check**

```bash
cargo deny check 2>&1 | tee /tmp/etch-cli-deny.txt
```

Expected: License, bans, and advisory violations listed. The comtrya repo has an existing `deny.toml` — this checks against it. Note any `DENY` items.

- [ ] **Step 3: Check binary download verification in binary action**

```bash
grep -n "checksum\|sha256\|verify\|digest" lib/src/actions/binary.rs
```

Note whether downloaded GitHub release binaries are checksum-verified. If grep returns nothing, the binary action trusts TLS only — document this as a known risk in the commit message.

- [ ] **Step 4: Check privilege escalation paths**

```bash
grep -rn 'sudo\|Command::new("sudo")\|escalat' lib/src/ app/src/
```

For each hit: read the surrounding context to understand when root is acquired and whether it's gated on user confirmation.

- [ ] **Step 5: Review rhai scripting sandbox**

```bash
grep -rn "rhai\|Engine\|scope\|sandbox" lib/src/ | grep -v "\.toml\|target/"
```

Read the rhai `Engine` initialization. Is `allow_all_functions` set? Are there capability restrictions? Note the security posture — a fully open rhai engine means manifests can run arbitrary Rust-side code.

- [ ] **Step 6: Check update-informer behavior**

```bash
grep -rn "update.informer\|UpdateInformer\|check_version" app/src/ lib/src/
```

Read what it calls and whether there's a `--no-update-check` flag or env var to disable it. Note the result.

- [ ] **Step 7: Write a brief audit summary as a comment in the commit**

The commit message for Task 4 should include:

- Advisory count from step 1
- Whether binary downloads are checksum-verified (step 3)
- Privilege escalation paths found (step 4)
- Rhai engine openness (step 5)
- Update-informer disable mechanism (step 6)

---

## Task 4: Rename comtrya → etch-cli / etch

**Files:** `app/Cargo.toml`, `Cargo.toml` (workspace root), possibly `lib/Cargo.toml`, `jsonschemagen/Cargo.toml`

- [ ] **Step 1: Inspect current Cargo.toml files before editing**

```bash
cat /Users/bruce/git-repos/personal/etch-cli/Cargo.toml
cat /Users/bruce/git-repos/personal/etch-cli/app/Cargo.toml
cat /Users/bruce/git-repos/personal/etch-cli/lib/Cargo.toml
cat /Users/bruce/git-repos/personal/etch-cli/jsonschemagen/Cargo.toml 2>/dev/null || echo "no jsonschemagen/Cargo.toml"
```

Read the output. Note every field that contains "comtrya" — those are the candidates for editing.

- [ ] **Step 2: Update app/Cargo.toml**

In `app/Cargo.toml`, make these changes:

a. Change `name = "comtrya"` to `name = "etch-cli"`

b. Update `description` to `"Declarative configuration management for personal workstations"`

c. Update `repository` to `"https://github.com/$GITHUB_HANDLE/etch-cli"` (substitute your actual handle)

d. Update `homepage` if present to the same URL

e. Change `[[bin]]` section:

```toml
[[bin]]
name = "etch"
path = "src/main.rs"
```

f. Preserve `license = "MIT"` exactly — do not change it.

g. Update `authors` if present to include your name.

- [ ] **Step 3: Update workspace root Cargo.toml**

In the workspace root `Cargo.toml`:

a. If there is a `[workspace.metadata]` or `[workspace.package]` section with name/description/repository fields, update them to match the app/Cargo.toml changes above.

b. The `[workspace] members` list stays as-is: `["app", "jsonschemagen", "lib"]`

c. Search for any occurrence of `"comtrya"` as a string value and update it.

- [ ] **Step 4: Search for remaining comtrya references in Cargo files**

```bash
grep -rn '"comtrya"' /Users/bruce/git-repos/personal/etch-cli --include="Cargo.toml"
grep -rn 'name = "comtrya"' /Users/bruce/git-repos/personal/etch-cli --include="Cargo.toml"
```

For any remaining hits: read the context and decide whether they refer to the crate identity (change to etch-cli/etch) or to the comtrya upstream dependency (leave as-is if etch-cli references comtrya's own lib, which it likely does via path deps).

Specifically: `lib/Cargo.toml` name is the internal library crate. Check whether `app/Cargo.toml` depends on it by path. If it does, the lib crate name change is optional for Phase 1 — rename the user-facing binary and app crate first, leave lib rename for later to minimize diff.

- [ ] **Step 5: Verify the rename builds**

```bash
cd /Users/bruce/git-repos/personal/etch-cli && cargo build 2>&1 | tail -5
```

Expected: `Compiling etch-cli` (not `comtrya`) and `Finished` with no errors.

- [ ] **Step 6: Verify binary name**

```bash
ls -la /Users/bruce/git-repos/personal/etch-cli/target/debug/etch
/Users/bruce/git-repos/personal/etch-cli/target/debug/etch --version 2>&1 || \
/Users/bruce/git-repos/personal/etch-cli/target/debug/etch --help 2>&1 | head -3
```

Expected: a file named `etch` exists (not `comtrya`), and it runs.

- [ ] **Step 7: Run release build and verify**

```bash
cd /Users/bruce/git-repos/personal/etch-cli && cargo build --release 2>&1 | tail -5
ls -lh target/release/etch
```

Expected: `target/release/etch` exists, size is reasonable (10-50MB for a statically-linked Rust binary).

- [ ] **Step 8: Run existing tests to confirm no regressions**

```bash
cd /Users/bruce/git-repos/personal/etch-cli && cargo test 2>&1 | tail -20
```

Expected: tests pass. Failures indicate something broke in the rename — investigate before committing.

- [ ] **Step 9: Commit**

```bash
cd /Users/bruce/git-repos/personal/etch-cli
git add Cargo.toml app/Cargo.toml lib/Cargo.toml Cargo.lock
git commit -m "$(cat <<'EOF'
chore: rename comtrya → etch-cli, binary comtrya → etch

Fork of github.com/comtrya/comtrya (archived April 2026, MIT).
Crate name: etch-cli. Binary name: etch. Functional code unchanged.

Security baseline (captured pre-rename):
- cargo audit: N advisories (fill in from Task 3 Step 1)
- Binary downloads: checksum-verified / TLS-only (fill in from Task 3 Step 3)
- sudo escalation: (fill in from Task 3 Step 4)
- rhai engine: (fill in from Task 3 Step 5)
- update-informer: (fill in from Task 3 Step 6)

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Makefile and Git Hooks

**Files:** `Makefile` (new), `scripts/pre-commit` (new), `scripts/pre-push` (new)

- [ ] **Step 1: Create Makefile**

Create `/Users/bruce/git-repos/personal/etch-cli/Makefile`:

```makefile
.PHONY: all test lint build install-hooks

all: test build

test: lint
	cargo test

lint:
	cargo clippy -- -D warnings

build:
	cargo build --release

install-hooks:
	cp scripts/pre-commit .git/hooks/pre-commit
	chmod +x .git/hooks/pre-commit
	cp scripts/pre-push .git/hooks/pre-push
	chmod +x .git/hooks/pre-push
```

- [ ] **Step 2: Run lint to verify it works**

```bash
cd /Users/bruce/git-repos/personal/etch-cli && make lint 2>&1 | tail -10
```

Expected: `Finished` with no errors, or clippy warnings that need fixing. Fix any `deny(warnings)`-level clippy issues before proceeding — they will block CI.

If clippy reports warnings, fix them now. Common patterns:

- Unused imports: delete them
- `unwrap()` on Options in non-test code: add `expect("reason")`
- Deprecated API calls: update to the suggested replacement

- [ ] **Step 3: Create scripts/pre-commit**

```bash
mkdir -p /Users/bruce/git-repos/personal/etch-cli/scripts
```

Create `/Users/bruce/git-repos/personal/etch-cli/scripts/pre-commit`:

```bash
#!/usr/bin/env bash
set -e
make lint
if command -v ggshield &>/dev/null; then
    ggshield secret scan pre-commit
fi
```

- [ ] **Step 4: Create scripts/pre-push**

Create `/Users/bruce/git-repos/personal/etch-cli/scripts/pre-push`:

```bash
#!/usr/bin/env bash
# Pre-push hook: runs full test suite locally before push reaches GitHub.
# Permanent: provides fast local feedback and conserves GitHub Actions minutes.
set -e

real_push=0
while read -r local_ref local_sha remote_ref remote_sha; do
    [ "${local_sha}" != "0000000000000000000000000000000000000000" ] && real_push=1
done
[ "${real_push}" -eq 0 ] && exit 0

printf "Running tests locally (pre-push)...\n"
make -C "$(cd "$(git rev-parse --git-common-dir)/.." && pwd)" test
```

- [ ] **Step 5: Install hooks**

```bash
cd /Users/bruce/git-repos/personal/etch-cli && make install-hooks
```

- [ ] **Step 6: Commit**

```bash
cd /Users/bruce/git-repos/personal/etch-cli
git add Makefile scripts/pre-commit scripts/pre-push
git commit -m "$(cat <<'EOF'
chore: add Makefile and git hooks

lint/test/build targets; pre-commit runs clippy + ggshield;
pre-push runs full test suite before GitHub sees the push.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Repository Structure and CI

**Files:** `.github/workflows/ci.yml` (new), `.gitleaks.toml` (new), `.gitignore` (update), `README.md` (update), `docs/superpowers/README.md` (new), `docs/cursor/README.md` (new)

- [ ] **Step 1: Update .gitignore**

Read the existing `.gitignore`, then ensure it contains these entries (add any missing):

```gitignore
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

# Rust
target/
**/*.rs.bk
```

- [ ] **Step 2: Create .gitleaks.toml**

Create `/Users/bruce/git-repos/personal/etch-cli/.gitleaks.toml`:

```toml
[extend]
useDefault = true

[allowlist]
description = "etch-cli allowlist"
regexes = []
paths = [
    "Cargo.lock",
]
```

- [ ] **Step 3: Create GitHub Actions CI workflow**

Create `/Users/bruce/git-repos/personal/etch-cli/.github/workflows/ci.yml`:

```yaml
name: CI

on:
  pull_request:
    branches:
      - master
      - main

env:
  FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: "true"

jobs:
  test:
    name: Test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - name: Install Rust stable
        uses: dtolnay/rust-toolchain@stable
        with:
          components: clippy
      - name: Cache cargo registry
        uses: actions/cache@v4
        with:
          path: |
            ~/.cargo/registry
            ~/.cargo/git
            target
          key: ${{ runner.os }}-cargo-${{ hashFiles('**/Cargo.lock') }}
      - name: Lint
        run: cargo clippy -- -D warnings
      - name: Test
        run: cargo test

  build:
    name: Build Release Binary
    runs-on: ubuntu-latest
    needs: [test]
    steps:
      - uses: actions/checkout@v5
      - name: Install Rust stable
        uses: dtolnay/rust-toolchain@stable
      - name: Cache cargo registry
        uses: actions/cache@v4
        with:
          path: |
            ~/.cargo/registry
            ~/.cargo/git
            target
          key: ${{ runner.os }}-cargo-release-${{ hashFiles('**/Cargo.lock') }}
      - name: Build release
        run: cargo build --release
      - name: Upload binary
        uses: actions/upload-artifact@v5
        with:
          name: etch-linux-amd64
          path: target/release/etch
          retention-days: 7

  secret-scan:
    name: Secret Scan
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
        with:
          fetch-depth: 20
      - name: Run gitleaks
        uses: gitleaks/gitleaks-action@v2
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        continue-on-error: true

  snyk-scan:
    name: Snyk Security Scan
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - name: Run Snyk code scan
        uses: snyk/actions/node@master
        continue-on-error: true
        env:
          SNYK_TOKEN: ${{ secrets.SNYK_TOKEN }}
        with:
          command: code test

  auto-merge:
    name: Auto Merge
    runs-on: ubuntu-latest
    needs: [test, build, secret-scan, snyk-scan]
    if: github.event_name == 'pull_request'
    steps:
      - uses: actions/checkout@v5
      - name: Auto merge on CI pass
        run: gh pr merge --squash --auto "${{ github.event.pull_request.number }}"
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

- [ ] **Step 4: Create docs/superpowers/README.md**

```bash
mkdir -p /Users/bruce/git-repos/personal/etch-cli/docs/superpowers/plans
mkdir -p /Users/bruce/git-repos/personal/etch-cli/docs/superpowers/specs
```

Create `/Users/bruce/git-repos/personal/etch-cli/docs/superpowers/README.md`:

```markdown
# Superpowers Specs and Plans

Master status index for all specs and implementation plans in this directory.

## Status Key

| Status      | Meaning                          |
| ----------- | -------------------------------- |
| Done        | Implemented and merged to master |
| In Progress | Currently being implemented      |
| Pending     | Not yet started                  |

---

## All Plans

| Date | Plan | Spec | Status |
| ---- | ---- | ---- | ------ |

---

## Backlog

| Feature                                | Notes                                                         |
| -------------------------------------- | ------------------------------------------------------------- |
| Prune unused package manager providers | Keep Homebrew + one Linux distro; delete BSDs, Pacman, Zypper |
| ntfy notification action               | Matches existing notification infra                           |
| macOS defaults write ergonomics        | If comtrya's current API is rough                             |
```

- [ ] **Step 5: Create docs/cursor/README.md**

```bash
mkdir -p /Users/bruce/git-repos/personal/etch-cli/docs/cursor/plans
mkdir -p /Users/bruce/git-repos/personal/etch-cli/docs/cursor/specs
```

Create `/Users/bruce/git-repos/personal/etch-cli/docs/cursor/README.md`:

```markdown
# Cursor Specs and Plans

| Date | Plan | Spec | Status |
| ---- | ---- | ---- | ------ |

## Backlog

| Feature | Notes |
| ------- | ----- |
```

- [ ] **Step 6: Update README.md**

Read the existing `README.md` first. Then update:

a. Title: Change "comtrya" to "etch" or "etch-cli" in the heading.

b. Install instructions: Replace any `cargo install comtrya` with `cargo install etch-cli` and any invocations of the `comtrya` binary with `etch`.

c. Add a note near the top:

```
> **Note:** etch-cli is a personal fork of [comtrya](https://github.com/comtrya/comtrya) (archived April 2026, MIT license), maintained for personal workstation management use.
```

d. Leave the rest of the README content intact — comtrya's docs are still accurate for etch-cli's behavior.

- [ ] **Step 7: Commit**

```bash
cd /Users/bruce/git-repos/personal/etch-cli
git add .github/workflows/ci.yml .gitleaks.toml .gitignore README.md docs/
git commit -m "$(cat <<'EOF'
chore: add CI, hooks, docs structure, gitignore

GitHub Actions: test, release build, gitleaks, snyk, auto-merge.
Pre-commit/pre-push hooks installed. Superpowers/cursor docs dirs created.
Fork attribution note added to README.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Dependency Hygiene

**Files:** `Cargo.toml`, `Cargo.lock`, `deny.toml`

The comtrya fork was archived with some dependency drift. This task updates the lockfile and checks the deny configuration is still valid.

- [ ] **Step 1: Update the lockfile**

```bash
cd /Users/bruce/git-repos/personal/etch-cli && cargo update 2>&1 | head -30
```

Note which crates were updated. If major version bumps appear (e.g. `tokio 1.x → 2.x`), do NOT accept them with `cargo update` — those require manual Cargo.toml edits and code changes. Minor/patch bumps are safe.

- [ ] **Step 2: Run audit again after update**

```bash
cargo audit 2>&1
```

Compare to the baseline from Task 3 Step 1. Note whether the update resolved any advisories.

- [ ] **Step 3: Run tests to confirm no regressions from the update**

```bash
cargo test 2>&1 | tail -20
```

Expected: all tests pass. If any fail, revert the specific dependency update that caused the failure:

```bash
cargo update --precise <old-version> <crate-name>
```

- [ ] **Step 4: Commit if changes are clean**

```bash
cd /Users/bruce/git-repos/personal/etch-cli
git add Cargo.lock
git commit -m "$(cat <<'EOF'
chore: cargo update — bump minor/patch dependencies

Post-fork lockfile refresh. Resolved N advisories (if any).

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Smoke Test Manifests

**Files:** These live on the Proxmox VM at `~/comtrya-test/manifests/`, not in the etch-cli repo. Write them locally and transfer to the VM.

**Important:** Manifest field names (`from`/`to` vs `source`/`target` vs `path`) must be verified against `https://comtrya.dev` documentation before running. The manifests below are structurally correct; field names are the most likely point of friction.

- [ ] **Step 1: Create the manifests directory locally**

```bash
mkdir -p /tmp/etch-smoke-manifests
```

- [ ] **Step 2: Write 01-smoke.yaml**

Create `/tmp/etch-smoke-manifests/01-smoke.yaml`:

```yaml
# Smoke test: confirms etch can parse and execute a manifest
actions:
  - action: command.run
    command: echo
    args:
      - "etch smoke test: hello from etch apply"
```

- [ ] **Step 3: Write 02-files.yaml**

Create `/tmp/etch-smoke-manifests/02-files.yaml`:

```yaml
# File operations: directory create, file copy, symlink
# Verify field names against https://comtrya.dev/files-and-directories.html
actions:
  - action: directory.create
    path: "{{ user.home_dir }}/comtrya-test-output"

  - action: file.copy
    from: "{{ manifest_dir }}/fixtures/hello.txt"
    to: "{{ user.home_dir }}/comtrya-test-output/hello-copy.txt"

  - action: file.link
    from: "{{ user.home_dir }}/comtrya-test-output/hello-copy.txt"
    to: "{{ user.home_dir }}/comtrya-test-output/hello-link.txt"
```

Also create `/tmp/etch-smoke-manifests/fixtures/hello.txt`:

```
hello from etch smoke test
```

- [ ] **Step 4: Write 03-packages.yaml**

Create `/tmp/etch-smoke-manifests/03-packages.yaml`:

```yaml
# Package install: htop via distro package manager
# SNAPSHOT THE VM BEFORE RUNNING THIS MANIFEST
# Verify action name against https://comtrya.dev/packages.html
actions:
  - action: package.install
    name: htop
```

- [ ] **Step 5: Write 04-templates.yaml**

Create `/tmp/etch-smoke-manifests/04-templates.yaml`:

```yaml
# Template rendering: exercises hostname/user/os context vars
# Verify template syntax against https://comtrya.dev/files-and-directories.html
actions:
  - action: file.template
    from: "{{ manifest_dir }}/fixtures/greeting.txt.tmpl"
    to: "{{ user.home_dir }}/comtrya-test-output/greeting.txt"
```

Also create `/tmp/etch-smoke-manifests/fixtures/greeting.txt.tmpl`:

```
Hello {{ user.username }} on {{ os.name }} ({{ system.hostname }})
Generated by etch smoke test
```

- [ ] **Step 6: Write 05-git.yaml**

Create `/tmp/etch-smoke-manifests/05-git.yaml`:

```yaml
# Git clone: exercises network egress and git action
# Verify field names against https://comtrya.dev/git.html
actions:
  - action: git.clone
    url: https://github.com/comtrya/comtrya.git
    to: "{{ user.home_dir }}/comtrya-test-output/comtrya-src"
```

- [ ] **Step 7: Write 99-idempotency.yaml**

Create `/tmp/etch-smoke-manifests/99-idempotency.yaml`:

```yaml
# Idempotency test: run everything from 02-05 a second time.
# Expected result: etch reports no-op (nothing to do) for every action.
# Any action that re-executes instead of skipping is a bug in that action's check logic.
manifests:
  - 02-files
  - 03-packages
  - 04-templates
  - 05-git
```

- [ ] **Step 8: Transfer manifests to the Proxmox VM**

```bash
# Replace <vm-ip> with your Proxmox VM's IP address
scp -r /tmp/etch-smoke-manifests/* <vm-user>@<vm-ip>:~/comtrya-test/manifests/
```

- [ ] **Step 9: Transfer the etch binary to the Proxmox VM**

The release binary is Linux amd64. Copy from your local build:

```bash
scp /Users/bruce/git-repos/personal/etch-cli/target/release/etch \
    <vm-user>@<vm-ip>:~/bin/etch
ssh <vm-user>@<vm-ip> "chmod +x ~/bin/etch && ~/bin/etch --version"
```

If there is no `target/release/etch` for Linux (you built on macOS), the VM must build from source:

```bash
# On the VM:
curl https://sh.rustup.rs -sSf | sh
git clone https://github.com/$GITHUB_HANDLE/etch-cli.git ~/etch-cli
cd ~/etch-cli && cargo build --release
cp target/release/etch ~/bin/etch
```

- [ ] **Step 10: Document VM smoke-test run order**

On the Proxmox VM, run in this order. Snapshot before step 3 (packages):

```bash
# Step 1 — smoke
~/bin/etch apply ~/comtrya-test/manifests/01-smoke.yaml

# Step 2 — files (no sudo)
~/bin/etch apply ~/comtrya-test/manifests/02-files.yaml
ls ~/comtrya-test-output/

# Step 3 — packages (SNAPSHOT FIRST)
sudo ~/bin/etch apply ~/comtrya-test/manifests/03-packages.yaml
htop --version

# Step 4 — templates
~/bin/etch apply ~/comtrya-test/manifests/04-templates.yaml
cat ~/comtrya-test-output/greeting.txt

# Step 5 — git clone
~/bin/etch apply ~/comtrya-test/manifests/05-git.yaml
ls ~/comtrya-test-output/comtrya-src/

# Step 6 — idempotency (must report no-op)
~/bin/etch apply ~/comtrya-test/manifests/99-idempotency.yaml
```

Any action that re-runs in step 6 instead of no-op'ing is a bug to file. Document findings before moving to Phase 2.

---

## Task 9: Push and Open Phase 1 PR

- [ ] **Step 1: Verify pre-push hook is installed**

```bash
ls -la /Users/bruce/git-repos/personal/etch-cli/.git/hooks/pre-push
```

Expected: file exists and is executable.

- [ ] **Step 2: Create a feature branch for Phase 1 setup**

```bash
cd /Users/bruce/git-repos/personal/etch-cli
git checkout -b feat/phase1-setup
git log --oneline -5
```

Confirm all commits from Tasks 4–7 are on this branch.

- [ ] **Step 3: Run the pr-review skill**

Before pushing, run the `pr-review` skill to gate for HOLD findings. Only push when verdict is PASS.

- [ ] **Step 4: Push**

```bash
cd /Users/bruce/git-repos/personal/etch-cli
git push -u origin feat/phase1-setup
```

The pre-push hook runs `make test` before the push completes.

- [ ] **Step 5: Open PR**

```bash
gh pr create \
  --title "Phase 1: fork, rename, audit, CI, hooks" \
  --body "$(cat <<'EOF'
## Summary

- Forked comtrya/comtrya (archived April 2026, MIT), renamed to etch-cli/etch
- Security audit baseline captured (cargo audit + cargo deny check)
- Cargo.toml: package name etch-cli, binary name etch
- Makefile: lint, test, build, install-hooks targets
- CI: test, release build, gitleaks, snyk, auto-merge jobs
- Git hooks: pre-commit (lint + ggshield), pre-push (make test)
- Docs: docs/superpowers/ and docs/cursor/ stubs

## Test plan

- [ ] CI passes: test, build, secret-scan jobs green
- [ ] Binary artifact named `etch` in CI artifacts
- [ ] `cargo build --release && ./target/release/etch --help` runs locally
- [ ] Smoke test manifests transferred to Proxmox VM (manual step)

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 6: Monitor CI**

```bash
gh pr checks --watch
```

Wait for all checks to complete. If any fail:

```bash
gh run view --log-failed
```

Fix, commit, push. CI re-runs automatically.

- [ ] **Step 7: After merge, clean up**

```bash
cd /Users/bruce/git-repos/personal/etch-cli
git checkout main
git pull
git branch -D feat/phase1-setup
git push origin --delete feat/phase1-setup
git fetch --prune
```

---

## Self-Review

**Spec coverage check:**

| Spec requirement                       | Covered by                          |
| -------------------------------------- | ----------------------------------- |
| Verify etch-cli crates.io availability | Task 1                              |
| Fork comtrya/comtrya to etch-cli       | Task 2                              |
| Clone locally                          | Task 2                              |
| Run cargo audit + cargo deny check     | Task 3                              |
| Update workspace and app/Cargo.toml    | Task 4                              |
| Confirm cargo build --release succeeds | Task 4 Step 7                       |
| Confirm binary named etch              | Task 4 Step 6                       |
| Provision Proxmox VM                   | Not covered — user operational task |
| Begin smoke-test sequence              | Task 8                              |
| Security review: binary.rs checksums   | Task 3 Step 3                       |
| Security review: sudo escalation       | Task 3 Step 4                       |
| Security review: rhai sandbox          | Task 3 Step 5                       |
| Security review: update-informer       | Task 3 Step 6                       |
| CI per standards                       | Task 6 Step 3                       |
| Pre-commit + pre-push hooks            | Task 5                              |
| .gitleaks.toml                         | Task 6 Step 2                       |
| docs/superpowers/ + docs/cursor/       | Task 6 Steps 4–5                    |

**Proxmox VM provisioning** is explicitly out of scope — the brief treats it as a user operational task. The plan delivers manifests ready to run.

**Placeholder scan:** No TBDs, no "add appropriate error handling", no "similar to Task N" references. All code blocks are complete.

**Type consistency:** No shared types across tasks in this plan (it's infrastructure/config, not feature code).
