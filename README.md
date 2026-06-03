# dotfiles

![bash coverage](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/brujack/dotfiles/coverage-data/bash.json)
![PowerShell coverage](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/brujack/dotfiles/coverage-data/powershell.json)

Personal development environment bootstrap for macOS, Linux (Ubuntu), and Windows/WSL.

## What This Does

Running `setup_env.sh -t setup` on a fresh machine:

- Creates `~/git-repos/personal/` and clones related repos
- Installs all tools defined in `Brewfile` (via Homebrew)
- Symlinks dotfiles from this repo into `$HOME` (`.zshrc`, `.vimrc`, `.tmux.conf`, `.gitconfig_*`, etc.)
- Symlinks Claude Code and Cursor config from the `ai-config` repo into `~/.claude/` and `~/.cursor/`
- Installs Oh-My-Zsh, Starship, tpm (tmux plugins), pyenv, rbenv, and Ansible virtualenv
- Sets zsh as the default shell
- Applies macOS system defaults (`.osx.sh`)

## Prerequisites

**macOS:**

- Xcode Command Line Tools: `xcode-select --install`
- SSH key configured for GitHub (needed to clone via `git@github.com:...`)

**Linux (Ubuntu 24.04):**

- `sudo apt-get install -y git curl`
- SSH key configured for GitHub

**All platforms:**

- This repo cloned to `~/git-repos/personal/dotfiles` — the path is hardcoded in `lib/constants.sh`
- The companion `ai-config` repo at `~/git-repos/personal/ai-config` (Claude Code and Cursor config live there)

## Getting Started

### 1. Fork and customize

This is a personal dotfiles repo. Before using it on your own machine:

1. Fork the repo on GitHub
2. Add your machine's hostname to `config/profiles.sh`:

```bash
declare -A PROFILE_MAP=(
  [my-macbook]="personal_laptop"   # ← add your hostname
  ...
)
```

See [Machine Profiles](#machine-profiles) for available profiles and their capabilities.

### 2. Clone to the required path

```bash
mkdir -p ~/git-repos/personal
git clone git@github.com:<your-fork>/dotfiles.git ~/git-repos/personal/dotfiles
cd ~/git-repos/personal/dotfiles
```

> **Note:** The path `~/git-repos/personal/dotfiles` is required. `lib/constants.sh` hardcodes this location.

### 3. (Optional) Set up machine-local config

Copy the example and add secrets/overrides that should not be committed:

```bash
cp config/local.sh.example config/local.sh
```

At minimum, set `GITHUB_PAT` if you want the GitHub MCP server configured automatically (see [Claude Code Integration](#claude-code-integration)).

### 4. Bootstrap and run setup

**macOS:**

```bash
# One-time: installs Homebrew and bash 5
./scripts/bootstrap_mac.sh

# Full setup (installs everything)
./setup_env.sh -t setup --brew-install --mas-install
```

**Linux (Ubuntu):**

```bash
# One-time: installs Homebrew prerequisites + Homebrew
./scripts/bootstrap_linux.sh

# Full setup
./setup_env.sh -t setup
```

### 5. Post-setup

```bash
# Install git hooks (required once per checkout)
make install-hooks

# Restart your shell to pick up the new config
exec zsh
```

### Subsequent machines

On a machine where the repo is already cloned (e.g. synced from another workstation), just run:

```bash
./setup_env.sh -t setup --brew-install
```

### Keeping up to date

```bash
./setup_env.sh -t update
```

This updates Homebrew, apt/snap packages, pip, Ruby gems, Mac App Store apps, and Claude plugins in one pass. See [Update Log](#update-log-dotfiles-updatelog) for the output format.

## Quick Start (Fresh Mac)

```bash
# Step 1: Install Homebrew and bash 5 (one-time, uses macOS default shell)
./scripts/bootstrap_mac.sh

# Step 2: Run setup
./setup_env.sh -t setup
```

## Quick Start (Fresh Linux)

```bash
# Step 1: Install Homebrew prerequisites + Homebrew (one-time)
./scripts/bootstrap_linux.sh

# Step 2: Run setup
./setup_env.sh -t setup
```

## Usage

```bash
./setup_env.sh -t <type>
```

| Type             | Description                                                                                                                                                      |
| ---------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `setup_user`     | Sets up user environment: configs, symlinks, shell, directory structure                                                                                          |
| `setup`          | Full machine setup (`setup_user` + all apps and tools). Flags: `--brew-install`, `--mas-install`                                                                 |
| `developer`      | Dev packages + Python/Ansible virtualenv                                                                                                                         |
| `ansible`        | Ansible venv only — typically used after a Python update                                                                                                         |
| `update`         | Update all packages (brew, apt/snap, pip, mas, Claude plugins, etc.). Prints a structured summary at the end; each run is appended to `~/.dotfiles-update.log`   |
| `doctor`         | Active health checks: symlinks, tool presence, credential dir permissions, version drift. Exits non-zero on any failure                                          |
| `check-versions` | Compare pinned tool versions in `lib/constants.sh` against latest GitHub releases. Exits 1 if any are outdated; `--update` prompts to apply each update in-place |

**Options:**

- `--dry-run` — log mutating operations (symlinks, installs, mkdir) without executing
- `--brew-install` — (setup only) Ensure Homebrew is installed, update, and run brew bundle installs
- `--mas-install` — (setup only) Install/update Mac App Store apps via mas (macOS only)
- `--brew-only` — update Homebrew formulae and casks only (with `-t update`)
- `--pip-only` — update pip packages only (with `-t update`)
- `--gems-only` — update Ruby gems only (with `-t update`)
- `--mas-only` — update Mac App Store apps only (with `-t update`)
- `--claude-only` — update Claude plugins only (with `-t update`)
- `--pkgs-only` — update Linux system packages only (apt/snap) (with `-t update`)
- `--update` — (check-versions only) interactively prompt to update each outdated pin in `lib/constants.sh`

Flags are additive: `./setup_env.sh -t update --brew-only --pip-only` runs only brew and pip.

### Update Log (`~/.dotfiles-update.log`)

Each `update` run appends a timestamped entry to `~/.dotfiles-update.log`. The entry lists every tracked section with its status and what changed:

```
=== Update Summary — 2026-04-13 10:00:00 ===

[OK]   brew             3 formulae (git 2.47.0, curl 8.12.1, openssl 3.4.1)
[OK]   softwareupdate   2 update(s) (Xcode-16.3, macOS Sequoia 15.4.1)
[OK]   apt              14 package(s) (curl 7.88.1, git 2.44.0, ...)
[OK]   snap             2 package(s) (firefox 124.0, chromium 123.0)
[OK]   mas              1 app(s) (Slack (4.42))
[OK]   claude           2 plugin(s) updated (superpowers: 5.0.8, context7: 1.2.0)
[OK]   pip              3 package(s) (ansible, boto3, requests)
[OK]   gems             no changes
[OK]   oh-my-zsh        2 commit(s)
[OK]   tpm              no changes
[OK]   tfenv            no changes
[OK]   cheat.sh         updated
[WARN] brew-drift       2 untracked formulae, 1 missing tap
[SKIP] gems             flag not set

brew-drift details:
  Untracked (installed, not in Brewfile):
    bat
    jq
  Missing (in Brewfile, not installed):
    tap: teamookla/speedtest

7 sections: 5 OK, 0 failed, 1 warnings, 1 skipped
```

Sections show `[OK]`, `[WARN]`, `[FAIL]`, or `[SKIP]`. `WARN` entries are non-blocking advisory findings (e.g. Brewfile drift); detail lines are printed below the table. `FAIL` entries include the exit code; scroll up in the terminal to see the full command output. The log is append-only and never rotated automatically.

### Machine-Local Overrides

To customize a specific machine without committing changes, copy the example and edit:

```bash
cp config/local.sh.example config/local.sh
```

`config/local.sh` is git-ignored and sourced after `detect_env` runs. The `HAS_*` vars, `PROFILE`, and OS vars are all available to override.

### Re-running after shell change

After switching to zsh, run setup again from the new shell:

```bash
./setup_env.sh -t setup
```

### Re-running ansible after Python update

```bash
rm ~/.virtualenvs/ansible && ./setup_env.sh -t ansible
```

## Repository Layout

```
dotfiles/
├── setup_env.sh              # Main entry point — sources lib/, dispatches workflows
├── Brewfile                  # Homebrew bundle manifest (100+ formulae/casks)
├── Brewfile.devtools         # Dev-tools-only Brewfile subset
├── Brewfile.gui              # GUI-only Brewfile subset
├── config/
│   └── profiles.sh           # hostname → profile map; edit here to add a new machine
├── lib/
│   ├── constants.sh          # Version pins, download URLs, directory vars
│   ├── helpers.sh            # Logging, safe_link, install guards, brew helpers
│   ├── detect_env.sh         # OS/version detection + profile/capability resolution
│   ├── macos.sh              # macOS-specific install functions
│   ├── linux_shared.sh       # Shared Linux install functions (git, zsh, bats)
│   ├── linux_ubuntu.sh       # Ubuntu-specific install functions
│   ├── developer.sh          # Cross-platform dev tooling (Ruby, Python, Ansible, etc.)
│   ├── update_summary.sh     # Update run tracking and summary reporting
│   └── workflows.sh          # Top-level workflow functions dispatched by setup_env.sh
├── scripts/
│   ├── bootstrap_mac.sh      # One-time macOS prerequisite installer (Homebrew + bash 5)
│   ├── bootstrap_linux.sh    # One-time Linux prerequisite installer (Homebrew prerequisites + Homebrew)
│   ├── .osx.sh               # macOS system defaults
│   └── ...                   # utility scripts
├── powershell/
│   ├── setup_windows.ps1     # Windows/PowerShell bootstrap
│   └── tests/                # Pester v5 tests
├── .zshrc                    # Main zsh config (sources .zshrc.d modules)
├── .zprofile                 # Zsh login shell config
├── .vimrc                    # Vim config with 50+ plugins
├── .tmux.conf                # Tmux config (Dracula theme, tpm, C-a prefix)
├── .gitconfig_mac            # Git config for macOS
├── .gitconfig_linux          # Git config for Linux
├── .gitconfig_windows        # Git config for Windows
├── .config/.zshrc.d/         # Modular zsh config (7 numbered files)
├── .claude/                  # Claude Code config (symlinked into ~/.claude)
├── .cursor/User/             # Cursor settings (symlinked into Cursor User dir)
├── docs/
│   ├── adr/                  # Architectural Decision Records → [index](docs/adr/README.md)
│   ├── claude-code-new-features/  # Weekly Claude Code feature digests
│   ├── anthropic-new-features/    # Weekly Anthropic & Claude API digests
│   ├── cursor/               # Cursor specs and plans
│   ├── knowledge/            # Reference material (architecture, domain docs)
│   └── superpowers/          # Design specs and implementation plans → [index](docs/superpowers/README.md)
├── tests/
│   ├── setup_env/            # BATS tests (unit, profiles, install_guards, etc.)
│   ├── zshrc.d/              # BATS tests for zsh config modules
│   ├── mocks/                # PATH-injected mock executables
│   └── helpers/
├── .github/
│   └── workflows/
│       └── ci.yml            # lint + test + lint-macos + secret-scan + auto-merge
├── kubernetes_stuff/         # Kubernetes install/init scripts
└── ubuntu_*_packages.txt     # Package lists per Ubuntu version
```

## Machine Profiles

Machines are mapped to profiles in `config/profiles.sh`:

| Profile             | Machines          | Capabilities                                    |
| ------------------- | ----------------- | ----------------------------------------------- |
| `personal_laptop`   | laptop            | GUI, devtools, AWS, k8s, Docker, Rust, printing |
| `mac_workstation`   | studio, reception | GUI, devtools, AWS, k8s, Docker, Rust, printing |
| `mac_mini`          | office, home-1    | GUI, printing                                   |
| `linux_workstation` | workstation       | GUI, devtools, AWS, k8s, Docker, Rust, snap     |
| `wsl2_workstation`  | cruncher          | GUI, devtools, AWS, k8s, Docker, Rust           |
| `server`            | (future)          | devtools, AWS                                   |

**linux_workstation vs wsl2_workstation:** `linux_workstation` (hostname: `workstation`) is a desktop Ubuntu machine with full snap support. `wsl2_workstation` (hostname: `cruncher`) is WSL2 Ubuntu where snap is unavailable — snap-gated installs (Albert, Microsoft Edge, ollama, snap classic packages) are skipped, and Helm is installed via apt instead of snap.

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

## Symlink Strategy

Dotfiles live at the repo root. `.claude/` and `.cursor/` live in the ai-config repo (`~/git-repos/personal/ai-config`). `setup_env.sh` creates symlinks from `$HOME` into the repos. For `.claude/`, each item is symlinked individually into `~/.claude/`, preserving any other files already there (history, sessions, cache, etc.). Cursor user files are symlinked to:

- macOS: `~/Library/Application Support/Cursor/User/`
- Linux: `~/.config/Cursor/User/`

## Windows / WSL Setup

1. Windows 10 Pro or later (required for containers and WSL)
2. Enable WSL2: `wsl --install` in an elevated PowerShell terminal
3. Install Ubuntu from the Microsoft Store (or `wsl --install -d Ubuntu`)
4. Clone this repo into WSL: `git clone git@github.com:<your-fork>/dotfiles.git ~/git-repos/personal/dotfiles`
5. Run `powershell/setup_windows.ps1` in an elevated PowerShell terminal to set up native Windows tooling (Chocolatey, Claude Code, Cursor, symlinks into `~/.claude/` and `~/.cursor/`)
6. Inside WSL, run `./setup_env.sh -t setup`

## Claude Code Integration

### GitHub MCP

Claude Code is configured with the GitHub MCP server for native GitHub operations
(PR review, issue management, repo browsing) across all projects.

**One-time setup per machine:**

1. Create a fine-grained PAT at <https://github.com/settings/tokens?type=beta>
   - Resource owner: your account
   - Repository access: All repositories (or specific repos)
   - Permissions: `Metadata` (read), `Contents` (read), `Issues` (read+write),
     `Pull requests` (read+write)
   - Set expiry: maximum 1 year

2. Add to `config/local.sh`:

   ```bash
   export GITHUB_PAT="github_pat_..."
   export GITHUB_PAT_EXPIRY="2027-04-14"   # your actual expiry date
   ```

3. Run setup:

   ```bash
   ./setup_env.sh -t setup_user
   ```

4. Verify:

   ```bash
   ./setup_env.sh -t doctor
   ```

The generated `~/.claude/mcp.json` is not tracked in git — it is regenerated
from `.claude/mcp.json.template` on each `setup_user` run.

## Branch Workflow

All changes go on feature branches. The pre-push hook runs `make test` locally before the push reaches GitHub. GitHub Actions CI runs `make test`, `lint-macos`, and `secret-scan` on PRs only, and auto-merges when all three pass.

```bash
git checkout -b my-feature
# ... make changes ...
git push -u origin my-feature
gh pr create
# CI runs → auto-merges on green
```

## Testing

Uses [BATS](https://github.com/bats-core/bats-core) (Bash Automated Testing System), installed natively.

```bash
make test          # lint (bash -n, zsh -n, shellcheck) + all BATS tests
make test-unit     # unit + profiles tests only (faster)
make lint          # syntax + shellcheck only
make install-hooks # install pre-commit hook (runs lint + ggshield before each commit)
make sync-agent-guidance  # regenerate .cursor guidance from .claude sources
make check-agent-guidance # fail if generated guidance is out of sync
```

Install bats-core first: `brew install bats-core` (macOS) or `sudo apt-get install bats` (Ubuntu).

- `brew install git-cliff` — CHANGELOG generation (`make changelog`)

### Pre-commit Hook (required)

Run `make install-hooks` once per checkout. The hook runs before every `git commit`:

1. `make lint` — syntax check + shellcheck; blocks the commit on failure
2. `ggshield secret scan pre-commit` — scans staged changes for secrets before they leave the machine; requires [GitGuardian CLI](https://docs.gitguardian.com/ggshield-docs/getting-started) (`brew install gitguardian/tap/ggshield` + `ggshield auth login`); skipped gracefully if not installed

This is the last line of defence before code reaches the remote. The CI `secret-scan` job (gitleaks) is a backstop, not a substitute.

### PowerShell

`powershell/` has its own Makefile. Run from the `powershell/` directory:

```bash
cd powershell
make test        # lint then run Pester tests
make lint        # PSScriptAnalyzer only
```

Prerequisites (one-time install):

```bash
pwsh -Command "Install-Module Pester -Force -Scope CurrentUser -MinimumVersion 5.0"
pwsh -Command "Install-Module PSScriptAnalyzer -Force -Scope CurrentUser"
```
