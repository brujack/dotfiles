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
GO_VER="1.26"
PYTHON_VER="3.14.2"
RUBY_VER="4.0.2"
```

Update these constants when bumping versions — don't hardcode versions elsewhere.
When a constant is updated in `setup_env.sh`, update all other references to that constant across the repo.

## Testing

Uses **BATS** (Bash Automated Testing System), installed natively:
- macOS: `brew install bats-core` (in `Brewfile`)
- Ubuntu: `sudo apt-get install -y bats` (via `install_bats()` in `setup_env.sh`)
- RHEL/CentOS/Fedora: direct GitHub release install (via `install_bats()`)

**Run tests:** `make test`
**Run unit tests only:** `make test-unit`

### Testing Rules

- Every new function in `setup_env.sh` must have a test in `tests/setup_env/unit.bats` (pure logic) or `tests/setup_env/install_guards.bats` (side effects requiring mocks)
- Every modification to an existing function must update its test
- New shell scripts get their own directory under `tests/` (e.g., `tests/scripts/`)
- Never modify real system state in tests — use PATH-based mocks from `tests/mocks/`
- `make test` must exit 0 before committing

### Mock Pattern

```bash
# In setup():
load_mocks           # prepends tests/mocks/ to PATH
export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
export MOCK_BREW_LIST_FORMULA="git wget"  # controls mock brew list output
export MOCK_WHICH_MISSING=bats            # makes which return 1 for 'bats'

# Assert what was called:
grep -q "brew install git" "${MOCK_CALLS_FILE}"
```

Available mock env vars:
| Variable | Effect |
|---|---|
| `MOCK_CALLS_FILE` | File where all mock invocations are logged |
| `MOCK_BREW_LIST_FORMULA` | Space-separated formulas returned by `brew list --formula` |
| `MOCK_BREW_LIST_CASK` | Space-separated casks returned by `brew list --cask` |
| `MOCK_BREW_TAPS` | Space-separated taps returned by `brew tap` |
| `MOCK_BREW_INSTALL_EXIT` | Exit code for `brew install` (default: 0) |
| `MOCK_BREW_TAP_EXIT` | Exit code for `brew tap <name>` (default: 0) |
| `MOCK_APT_EXIT` | Exit code for `apt-get` (default: 0) |
| `MOCK_WHICH_MISSING` | Command name for which `which` returns 1 |
| `MOCK_CURL_EXIT` | Exit code for `curl` (default: 0) |
| `MOCK_UNAME_S` | Value returned by `uname -s` |
| `MOCK_BATS_VER` | BATS_VER used by mock tar to create stub directory |

## Key Conventions

- Machine roles are detected by **hostname patterns** (`LAPTOP`, `WORKSTATION`, `STUDIO`, etc.) — use these conditionals for machine-specific config
- Ubuntu version detection uses `lsb_release -rs` → `FOCAL`, `JAMMY`, `NOBLE` vars
- Credential directories (`.aws`, `.tf_creds`, `.tsh`) are created with `chmod 700`
- Git repos are cloned to `~/git-repos/personal/` and `~/git-repos/work/`
- Python environments managed via **pyenv** + **pyenv-virtualenv**; the `ansible` venv is the primary one
- Application installs are kept in alphabetical order
