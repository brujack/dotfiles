# CLAUDE.md — dotfiles

## Repository Overview

Personal development environment bootstrapping system for macOS and Linux (Ubuntu/RHEL). Manages shell configs, tool installation, and symlink setup across multiple machine types.

## Layout

```
dotfiles/
├── setup_env.sh              # Main entry point (2388 lines) — run with -t <type>
├── Brewfile                  # Homebrew bundle manifest (100+ formulae/casks)
├── setup_windows.ps1         # Windows/PowerShell bootstrap
├── .devcontainer/            # Central dotfiles storage + dev container config
│   ├── .zshrc                # Main zsh config (sources .zshrc.d modules)
│   ├── .zprofile             # Zsh login shell config
│   ├── .vimrc                # Vim config with 50+ plugins
│   ├── .tmux.conf            # Tmux config (Dracula theme, tpm, C-a prefix)
│   ├── .p10k.zsh             # Powerlevel10k prompt config
│   ├── .gitconfig_mac        # Git config for macOS
│   ├── .gitconfig_linux      # Git config for Linux
│   └── .config/.zshrc.d/     # Modular zsh config (7 numbered files)
│       ├── 1_init.zsh        # OS detection, initial setup
│       ├── 2_functions.zsh   # Shell functions
│       ├── 3_oh-my-zsh.zsh   # Oh-My-Zsh config
│       ├── 4_aliases.zsh     # Aliases
│       ├── 5_general.zsh     # General settings
│       ├── 6_path.zsh        # PATH configuration
│       └── 7_final.zsh       # Final setup, completions
├── scripts/
│   ├── .osx.sh               # macOS system defaults (run during setup)
│   └── tmux-workstation.sh   # Multi-session tmux layout
├── kubernetes_stuff/         # Kubernetes installation/init scripts
├── .ssh/                     # SSH config
├── ubuntu_*_packages.txt     # Package lists per Ubuntu version
└── node_modules/             # bats (testing), json2yaml
```

## Entry Points

```bash
./setup_env.sh -t <type>
```

| Type | Purpose |
|------|---------|
| `setup_user` | Configs, shells, directory structure, symlinks |
| `setup` | Full machine setup (setup_user + all apps) |
| `developer` | Dev packages + Python/Ansible virtualenv |
| `ansible` | Ansible venv setup only (after Python updates) |
| `update` | Update all packages (brew, apt, pip, gems, tools) |

## Symlink Strategy

Dotfiles live in `.devcontainer/` — `setup_env.sh` creates symlinks from `$HOME` into the repo:

```bash
ln -s ${PERSONAL_GITREPOS}/${DOTFILES}/.devcontainer/.zshrc ${HOME}/.zshrc
```

Always remove the old file before symlinking (`rm -f` then `ln -s`). Validate symlinks with `[[ -L ${HOME}/.file ]]`.

## Code Standards

### Shell Scripts

- **Shebang:** `#!/usr/bin/env bash` — always bash, never `/bin/sh`
- **Conditionals:** `[[ ... ]]` not `[ ... ]`
- **Variables:** `${VAR}` expansion with braces
- **Output:** `printf "message\n"` not `echo`
- **Functions:** `snake_case()` naming
- **Constants:** `SCREAMING_SNAKE_CASE`, marked `readonly` after assignment
- **Error handling:** Check `$?` or use `|| exit 1`; guard installs with `command -v`/`quiet_which()`
- **No `set -euo pipefail`** at top-level — conditional installs require non-zero exits to continue

### Installation Guards

Always check before installing to keep the script idempotent:

```bash
if ! command -v <tool> &>/dev/null; then
    install_<tool>
fi
```

### Platform Detection Pattern

Replicated consistently across `setup_env.sh` and `.zshrc.d` modules:

```bash
if [[ -n ${MACOS} ]]; then ...
elif [[ -n ${UBUNTU} ]]; then ...
fi
```

### Homebrew Helpers

Use the established helper functions, don't call `brew` directly:

```bash
brew_formula_installed <formula>
brew_cask_installed <cask>
quiet_which <command>
```

### Version Pinning

All tool versions are defined as constants at the top of `setup_env.sh`:

```bash
GO_VER="1.25"
PYTHON_VER="3.14.2"
RUBY_VER="3.4.8"
```

Update these constants when bumping versions — don't hardcode versions elsewhere.

## Testing

Uses **BATS** (Bash Automated Testing System) via npm (`node_modules/.bin/bats`).

## Key Conventions

- Machine roles are detected by **hostname patterns** (`LAPTOP`, `WORKSTATION`, `STUDIO`, etc.) — use these conditionals for machine-specific config
- Ubuntu version detection uses `lsb_release -rs` → `FOCAL`, `JAMMY`, `NOBLE` vars
- Credential directories (`.aws`, `.tf_creds`, `.tsh`) are created with `chmod 700`
- Git repos are cloned to `~/git-repos/personal/` and `~/git-repos/work/`
- Python environments managed via **pyenv** + **pyenv-virtualenv**; the `ansible` venv is the primary one
