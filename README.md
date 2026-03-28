# dotfiles

Personal development environment bootstrapping system for macOS, Linux (Ubuntu/RHEL), and Windows/WSL.

## Prerequisites

- **macOS:** Install [Homebrew](https://brew.sh) first — this pulls in Xcode Command Line Tools (and git).
- **Linux:** Ensure `git` and `curl` are installed (`sudo apt install git curl` or equivalent).
- **All platforms:** Ability to clone this repo before running setup.

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
├── setup_env.sh              # Main entry point
├── Brewfile                  # Homebrew bundle manifest
├── powershell/
│   └── setup_windows.ps1     # Windows/PowerShell bootstrap
├── .devcontainer/            # Dotfiles storage (symlinked into $HOME)
│   ├── .zshrc                # Main zsh config
│   ├── .zprofile             # Zsh login shell config
│   ├── .vimrc                # Vim config
│   ├── .tmux.conf            # Tmux config
│   ├── .p10k.zsh             # Powerlevel10k prompt config
│   ├── .gitconfig_mac        # Git config for macOS
│   ├── .gitconfig_linux      # Git config for Linux
│   └── .config/.zshrc.d/     # Modular zsh config (numbered load order)
├── .claude/                  # Claude Code config (symlinked into ~/.claude)
│   ├── CLAUDE.md             # Global Claude Code instructions
│   └── settings.json         # Claude Code settings
├── scripts/
│   ├── .osx.sh               # macOS system defaults
│   ├── count_lines.sh        # Count lines across files in a directory
│   ├── count_lines_git.sh    # Count lines across git-tracked files
│   ├── html2ascii.sh         # Strip HTML tags, output one token per line
│   ├── kill_zombie.sh        # Kill zombie (defunct) processes
│   ├── mkill.sh              # Kill processes by name pattern
│   ├── restart_fah.sh        # Restart Folding@Home client
│   ├── synch_git-repos.sh    # Rsync git-repos to remote hosts (studio only)
│   └── tmux-workstation.sh   # Multi-session tmux layout
├── kubernetes_stuff/         # Kubernetes install/init scripts
├── .ssh/                     # SSH config
└── ubuntu_*_packages.txt     # Package lists per Ubuntu version
```

## Symlink Strategy

Dotfiles live in `.devcontainer/` and `.claude/`. `setup_env.sh` creates symlinks from `$HOME` into the repo. For `.claude/`, each item is symlinked individually into `~/.claude/`, preserving any other files already there (history, sessions, cache, etc.).

## Windows / WSL Setup

1. Windows 10 Pro or later (required for containers and WSL)
2. Install [Boxstarter](https://boxstarter.org/) using the command in `windows_boxstarter.ps1`
3. Clone this repo (recommended: [Sourcetree](https://www.sourcetreeapp.com/))
4. Run `setup_windows.ps1` to install Windows programs and services
5. Install Ubuntu from the Microsoft Store
6. Run `./setup_env.sh -t setup` inside WSL

## Testing

Uses [BATS](https://github.com/bats-core/bats-core) (Bash Automated Testing System), installed natively.

```bash
make test        # lint all .sh files then run all BATS tests
make test-unit   # run unit tests only (no lint)
make lint        # check bash/zsh syntax of all .sh files
```

Install bats-core first: `brew install bats-core` (macOS) or `sudo apt-get install bats` (Ubuntu).
