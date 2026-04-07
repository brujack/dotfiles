# dotfiles

Personal development environment bootstrap for macOS, Linux (Ubuntu/RHEL), and Windows/WSL.

## Quick Start (Fresh Mac)

```bash
# Step 1: Install Homebrew and bash 5 (one-time, uses macOS default shell)
./scripts/bootstrap_mac.sh

# Step 2: Run setup
./setup_env.sh -t setup
```

## Usage

```bash
./setup_env.sh -t <type>
```

| Type | Description |
|------|-------------|
| `setup_user` | Sets up user environment: configs, symlinks, shell, directory structure |
| `setup` | Full machine setup (`setup_user` + all apps and tools) |
| `developer` | Dev packages + Python/Ansible virtualenv |
| `ansible` | Ansible venv only — typically used after a Python update |
| `update` | Update all packages (brew, apt/dnf/yum, pip, mas, Claude plugins, etc.) |

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
├── config/
│   └── profiles.sh           # hostname → profile map; edit here to add a new machine
├── lib/
│   ├── constants.sh          # Version pins, download URLs, directory vars
│   ├── helpers.sh            # Logging, safe_link, install guards, brew helpers
│   ├── detect_env.sh         # OS/version detection + profile/capability resolution
│   ├── macos.sh              # macOS-specific install functions
│   ├── linux.sh              # Linux-specific install functions
│   └── developer.sh          # Cross-platform dev tooling (Ruby, Python, Ansible, etc.)
├── scripts/
│   ├── bootstrap_mac.sh      # One-time macOS prerequisite installer (Homebrew + bash 5)
│   ├── .osx.sh               # macOS system defaults
│   └── ...                   # utility scripts
├── powershell/
│   ├── setup_windows.ps1     # Windows/PowerShell bootstrap
│   └── tests/                # Pester v5 tests
├── .devcontainer/            # Dotfiles storage (symlinked into $HOME)
│   ├── .zshrc                # Main zsh config (sources .zshrc.d modules)
│   ├── .zprofile             # Zsh login shell config
│   ├── .vimrc                # Vim config with 50+ plugins
│   ├── .tmux.conf            # Tmux config (Dracula theme, tpm, C-a prefix)
│   ├── .p10k.zsh             # Powerlevel10k prompt config
│   ├── .gitconfig_mac        # Git config for macOS
│   ├── .gitconfig_linux      # Git config for Linux
│   └── .config/.zshrc.d/     # Modular zsh config (7 numbered files)
├── .claude/                  # Claude Code config (symlinked into ~/.claude)
├── .cursor/User/             # Cursor settings (symlinked into Cursor User dir)
├── tests/
│   ├── setup_env/            # BATS tests (unit, profiles, install_guards, etc.)
│   ├── zshrc.d/              # BATS tests for zsh config modules
│   ├── mocks/                # PATH-injected mock executables
│   └── helpers/
├── .github/
│   └── workflows/
│       └── ci.yml            # lint + test + auto-merge on non-master branches
├── kubernetes_stuff/         # Kubernetes install/init scripts
└── ubuntu_*_packages.txt     # Package lists per Ubuntu version
```

## Machine Profiles

Machines are mapped to profiles in `config/profiles.sh`:

| Profile | Machines | Capabilities |
|---|---|---|
| `personal_laptop` | laptop | GUI, devtools, AWS, k8s, Docker, Rust, printing |
| `mac_workstation` | studio, reception | GUI, devtools, AWS, k8s, Docker, Rust, printing |
| `mac_mini` | office, home-1 | GUI, printing |
| `linux_workstation` | workstation | GUI, devtools, AWS, k8s, Docker, Rust, snap |
| `wsl2_workstation` | cruncher | GUI, devtools, AWS, k8s, Docker, Rust |
| `server` | (future) | devtools, AWS |

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

Dotfiles live in `.devcontainer/`, `.claude/`, and `.cursor/`. `setup_env.sh` creates symlinks from `$HOME` into the repo. For `.claude/`, each item is symlinked individually into `~/.claude/`, preserving any other files already there (history, sessions, cache, etc.). Cursor user files are symlinked to:
- macOS: `~/Library/Application Support/Cursor/User/`
- Linux: `~/.config/Cursor/User/`

## Windows / WSL Setup

1. Windows 10 Pro or later (required for containers and WSL)
2. Install [Boxstarter](https://boxstarter.org/) using the command in `windows_boxstarter.ps1`
3. Clone this repo (recommended: [Sourcetree](https://www.sourcetreeapp.com/))
4. Run `powershell/setup_windows.ps1` to install Windows programs and services
5. Install Ubuntu from the Microsoft Store
6. Run `./setup_env.sh -t setup` inside WSL

## Branch Workflow

All changes go on feature branches. GitHub Actions CI runs `make test` on every push to a non-master branch and auto-merges the PR to master when tests pass.

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
make test        # lint (bash -n, zsh -n, shellcheck) + all BATS tests
make test-unit   # unit + profiles tests only (faster)
make lint        # syntax + shellcheck only
```

Install bats-core first: `brew install bats-core` (macOS) or `sudo apt-get install bats` (Ubuntu).

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
