# Phase 5: Documentation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create `README.md` and update `CLAUDE.md` to accurately reflect the post-Phase-3 modular architecture, profile model, bootstrap workflow, and testing conventions.

**Architecture:** Documentation-only phase. `README.md` is the entry point for new users and fresh machine setup. `CLAUDE.md` is the AI assistant reference for the repo. Both must match the actual state of the repo after Phases 0–4.

**Tech Stack:** Markdown

---

## Files

| File | Action |
|---|---|
| `README.md` | Create — user-facing documentation |
| `CLAUDE.md` | Modify — update Layout, add new conventions, update testing section |

---

## Task 1: Create `README.md`

**Files:**
- Create: `README.md`

- [ ] **Step 1: Create `README.md` with the following content**

```markdown
# dotfiles

Personal development environment bootstrap for macOS and Linux.

## Quick Start (Fresh Mac)

```bash
# Step 1: Install Homebrew and bash 5 (one-time, requires macOS default shell)
./scripts/bootstrap_mac.sh

# Step 2: Run setup
./setup_env.sh -t setup
```

## Setup Types

Run `./setup_env.sh -t <type>`:

| Type | What it does |
|------|-------------|
| `setup_user` | Dotfile symlinks, shell config, credential directories |
| `setup` | Full machine setup (setup_user + all apps for this machine's profile) |
| `developer` | Dev packages + Python/Ansible virtualenv |
| `ansible` | Ansible venv setup only (re-run after Python updates) |
| `update` | Update all packages (brew, apt, pip, gems, tools) |

## Architecture

`setup_env.sh` is an ~80-line orchestrator that sources focused modules:

```
setup_env.sh         # orchestrator: sources lib/, parses args, dispatches
scripts/
  bootstrap_mac.sh   # one-time: installs Homebrew + bash 5 on a fresh Mac
config/
  profiles.sh        # hostname → profile map (edit here to add a machine)
lib/
  constants.sh       # version pins, download URLs, directory vars
  helpers.sh         # logging, safe_link, install guards, brew helpers
  detect_env.sh      # OS/version detection + profile resolution
  macos.sh           # macOS-specific install functions
  linux.sh           # Linux-specific install functions
  developer.sh       # cross-platform dev tooling (Ruby, Python, Ansible, etc.)
tests/
  setup_env/         # BATS tests for setup_env functions
  zshrc.d/           # BATS tests for zsh config modules
  mocks/             # PATH-injected mock executables
```

## Machine Profiles

Machines are mapped to profiles in `config/profiles.sh`. Each profile enables a set of capabilities:

| Profile | Machines | Capabilities |
|---|---|---|
| `personal_laptop` | laptop | GUI, devtools, AWS, k8s, Docker, Rust, printing |
| `mac_workstation` | studio, reception | GUI, devtools, AWS, k8s, Docker, Rust, printing |
| `mac_mini` | office, home-1 | GUI, printing |
| `linux_workstation` | workstation, cruncher | GUI, devtools, AWS, k8s, Docker, Rust |
| `server` | (future) | devtools, AWS |

### Adding a New Machine

Edit one line in `config/profiles.sh`:

```bash
declare -A PROFILE_MAP=(
  [laptop]="personal_laptop"
  [my-new-mac]="mac_workstation"   # ← add this
  ...
)
```

Push a feature branch — CI validates and auto-merges to master.

## Testing

```bash
make test        # lint (bash -n, zsh -n, shellcheck) + all BATS tests
make test-unit   # unit tests only (faster)
make lint        # syntax + shellcheck only
```

BATS is required: `brew install bats-core` (macOS) or `sudo apt-get install bats` (Linux).

## Branch Workflow

All changes go on feature branches. GitHub Actions CI runs `make test` on every push to a non-master branch and auto-merges the PR to master when tests pass.

```bash
git checkout -b my-feature
# ... make changes ...
git push -u origin my-feature
gh pr create
# CI runs → auto-merges on green
```

## Dotfile Locations

Dotfiles live in `.devcontainer/`. `setup_user` creates symlinks from `$HOME` into the repo. Symlinks are idempotent — re-running `setup_user` is safe.

Shell config is modular under `.devcontainer/.config/.zshrc.d/`:

| File | Purpose |
|---|---|
| `1_init.zsh` | OS detection, initial setup |
| `2_functions.zsh` | Shell functions |
| `3_oh-my-zsh.zsh` | Oh-My-Zsh config |
| `4_aliases.zsh` | Aliases |
| `5_general.zsh` | General settings |
| `6_path.zsh` | PATH configuration |
| `7_final.zsh` | Final setup, completions |
```

- [ ] **Step 2: Verify the README renders correctly**

```bash
# Quick check for broken markdown tables or code fences
python3 -c "
content = open('README.md').read()
fences = content.count('\`\`\`')
assert fences % 2 == 0, f'Unmatched code fences: {fences}'
print('README.md looks OK')
"
```

Expected: `README.md looks OK`

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: create README.md with architecture and quick start

Covers: fresh Mac setup, setup types, lib/ architecture, profile
model, adding a new machine, testing, and branch workflow.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 2: Update `CLAUDE.md` — Layout section

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Replace the Layout section**

Find the `## Layout` section in `CLAUDE.md`. Replace its content with:

```markdown
## Layout

```
dotfiles/
├── setup_env.sh              # Orchestrator (~80 lines): sources lib/, dispatches workflows
├── Brewfile                  # Homebrew bundle manifest (100+ formulae/casks)
├── config/
│   └── profiles.sh           # hostname→profile map; edit here to add a new machine
├── lib/
│   ├── constants.sh          # Version pins, download URLs, directory vars
│   ├── helpers.sh            # Logging (log_info/warn/error), safe_link, install guards, brew helpers
│   ├── detect_env.sh         # OS/version detection + profile/capability resolution
│   ├── macos.sh              # macOS-specific install functions
│   ├── linux.sh              # Linux-specific install functions
│   └── developer.sh          # Cross-platform dev tooling (Ruby, Python, Ansible, etc.)
├── scripts/
│   ├── bootstrap_mac.sh      # NEW: one-time macOS prerequisite installer (Homebrew + bash 5)
│   ├── .osx.sh               # macOS system defaults
│   └── ...                   # utility scripts
├── powershell/
│   ├── setup_windows.ps1     # Windows/PowerShell bootstrap
│   └── tests/                # Pester v5 tests
├── .devcontainer/            # Central dotfiles storage
│   ├── .zshrc                # Main zsh config (sources .zshrc.d modules)
│   └── .config/.zshrc.d/     # Modular zsh config (7 numbered files)
├── tests/
│   ├── setup_env/
│   │   ├── unit.bats
│   │   ├── profiles.bats     # Profile + capability resolution tests
│   │   ├── install_guards.bats
│   │   ├── install_functions.bats
│   │   └── extracted_functions.bats
│   ├── zshrc.d/
│   │   └── unit.bats
│   ├── mocks/                # PATH-injected mock executables
│   └── helpers/
│       └── common.bash
└── .github/
    └── workflows/
        └── ci.yml            # lint + test + auto-merge on non-master branches
```
```

- [ ] **Step 2: Update the Entry Points table in `CLAUDE.md`**

The entry point section describes `setup_env.sh -t <type>`. It is still accurate. Verify it has not drifted; if it has, restore the correct table.

---

## Task 3: Add "Adding a New Machine" section to `CLAUDE.md`

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Insert the new section after the "Key Conventions" section**

Add this section at the end of `CLAUDE.md` (before any trailing content):

```markdown
## Adding a New Machine

1. Edit `config/profiles.sh` — add the hostname to `PROFILE_MAP`:

```bash
declare -A PROFILE_MAP=(
  [laptop]="personal_laptop"
  [my-new-host]="mac_workstation"   # ← new line
  ...
)
```

2. If the machine needs a new profile, add it to both `PROFILE_MAP` and `PROFILE_CAPS` in `config/profiles.sh`.

3. Push a feature branch. CI validates → auto-merges to master.

No other files need changing.

## Profile Model

After `detect_env()` runs, the following vars are set:

| Var | Profiles |
|---|---|
| `PROFILE` | String: `personal_laptop`, `mac_workstation`, `mac_mini`, `linux_workstation`, `server`, or `unknown` |
| `HAS_GUI` | personal_laptop, mac_workstation, mac_mini, linux_workstation |
| `HAS_DEVTOOLS` | personal_laptop, mac_workstation, linux_workstation |
| `HAS_AWS` | personal_laptop, mac_workstation, linux_workstation, server |
| `HAS_K8S` | personal_laptop, mac_workstation, linux_workstation |
| `HAS_DOCKER` | personal_laptop, mac_workstation, linux_workstation |
| `HAS_RUST` | personal_laptop, mac_workstation, linux_workstation |
| `HAS_PRINTING` | personal_laptop, mac_workstation, mac_mini |

Legacy hostname vars (`LAPTOP`, `STUDIO`, `WORKSTATION`, etc.) are preserved as readonly aliases for backwards compatibility.
```

---

## Task 4: Update `CLAUDE.md` Testing section

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add `profiles.bats` to the Testing section**

In the "Testing" section of `CLAUDE.md`, find the `make test-unit` description and update it to include `profiles.bats`:

Current:
```
**Run unit tests only:** `make test-unit`
```

The section should note that `test-unit` runs `unit.bats`, `profiles.bats`, and `zshrc.d/unit.bats`.

- [ ] **Step 2: Add CI workflow note**

Add a brief note about the GitHub Actions CI in the Testing section:

```markdown
### CI

GitHub Actions runs `make test` on every push to a non-master branch and auto-merges the PR to master on green. Branch protection on master requires the `test` check to pass.
```

---

## Task 5: Final commit

- [ ] **Step 1: Run the full test suite to confirm nothing is broken**

```bash
make test
```

Expected: exit 0.

- [ ] **Step 2: Commit all doc changes**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md for post-modularization architecture

Updates Layout section to show lib/ structure and config/profiles.sh.
Adds profile model reference, HAS_* capability vars table, and
'Adding a New Machine' guide. Updates testing section to include
profiles.bats and CI workflow note.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```
