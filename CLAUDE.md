# CLAUDE.md — dotfiles

## Repository Overview

Personal development environment bootstrapping system for macOS and Linux (Ubuntu/RHEL). Manages shell configs, tool installation, and symlink setup across multiple machine types.

## Layout

```
dotfiles/
├── setup_env.sh              # Main entry point — sources lib/, dispatches workflows
├── Brewfile                  # Homebrew bundle manifest (100+ formulae/casks)
├── config/
│   └── profiles.sh           # hostname → profile map; edit here to add a new machine
├── docs/
│   ├── adr/                  # Architectural Decision Records (cross-cutting decisions)
│   │   ├── README.md         # ADR index table
│   │   └── NNNN-title.md     # Individual ADRs (0001, 0002, …)
│   └── superpowers/          # Design specs and implementation plans
│       ├── specs/            # Design documents (YYYY-MM-DD-*-design.md)
│       └── plans/            # Implementation plans (YYYY-MM-DD-*.md)
├── lib/
│   ├── constants.sh          # Version pins, download URLs, directory vars
│   ├── helpers.sh            # Logging (log_info/warn/error), safe_link, install guards, brew helpers
│   ├── detect_env.sh         # OS/version detection + profile/capability resolution
│   ├── macos.sh              # macOS install functions (install_macos_packages)
│   ├── linux.sh              # Linux install functions (install_ubuntu_packages, install_rhel_packages, install_centos_packages, install_linux_packages)
│   ├── developer.sh          # Cross-platform dev tools (install_ruby_tools, install_ruby, setup_kitchen, setup_ansible, clone_personal_repos, etc.)
│   ├── update_summary.sh     # Update run tracking and summary reporting
│   └── workflows.sh          # Top-level workflow functions dispatched by setup_env.sh
├── scripts/
│   ├── bootstrap_mac.sh      # One-time macOS prerequisite installer (Homebrew + bash 5)
│   ├── .osx.sh               # macOS system defaults (run during setup)
│   └── ...                   # utility scripts
├── powershell/
│   ├── setup_windows.ps1     # Windows/PowerShell bootstrap
│   ├── Makefile              # lint + test targets for PowerShell
│   ├── PSScriptAnalyzerSettings.psd1  # PSScriptAnalyzer rule config
│   ├── run-lint.ps1          # lint script with module path restoration (called by make lint)
│   ├── run-tests.ps1         # combined lint+test script (called by make test)
│   └── tests/
│       └── setup_windows.Tests.ps1   # Pester v5 unit tests (22 tests)
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
├── .claude/                  # Claude Code config (settings, plugins, memory)
│   └── projects/             # Per-repo memories (symlinked from ~/.claude/projects/)
├── .cursor/                  # Cursor config (plugins, skills-cursor)
│   └── User/                 # Cursor user settings (symlinked into platform Cursor user dir)
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
├── .github/
│   └── workflows/
│       └── ci.yml            # lint + test + auto-merge on non-master branches
├── kubernetes_stuff/         # Kubernetes installation/init scripts
├── .ssh/                     # SSH config
└── ubuntu_*_packages.txt     # Package lists per Ubuntu version
```

## Entry Points

```bash
./setup_env.sh -t <type>
```

| Type             | Purpose                                                                                                                                                                                                                                       |
| ---------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `setup_user`     | Configs, shells, directory structure, symlinks                                                                                                                                                                                                |
| `setup`          | Full machine setup (setup_user + all apps). Flags: `--brew-install`, `--mas-install`                                                                                                                                                          |
| `developer`      | Dev packages + Python/Ansible virtualenv                                                                                                                                                                                                      |
| `ansible`        | Ansible venv setup only (after Python updates)                                                                                                                                                                                                |
| `update`         | Update all packages (brew, apt/dnf/yum, pip, gems, tools). Supports `--brew-only`, `--pip-only`, `--gems-only`, `--mas-only`, `--claude-only` flags. Prints a structured summary at the end; each run is appended to `~/.dotfiles-update.log` |
| `doctor`         | Active health checks: symlinks, tool presence, credential dir permissions, version drift. Exits non-zero on any failure                                                                                                                       |
| `check-versions` | Compare pinned versions in `lib/constants.sh` against GitHub latest; exits 1 if outdated. `--update` prompts per-tool to apply updates in-place                                                                                               |

**Options:**

- `--dry-run` — log mutating operations (symlinks, installs, mkdir) without executing

## Symlink Strategy

Dotfiles live in `.devcontainer/`, `.claude/`, and `.cursor/`. `setup_env.sh` creates symlinks from `$HOME` into the repo:

- **`.devcontainer/`** — each file symlinked individually into `$HOME` (e.g. `~/.zshrc → …/.devcontainer/.zshrc`)
- **`.claude/`** — each item symlinked individually into `~/.claude/`, preserving any non-repo files already there
- **`.cursor/`** — each item (excluding `User/`) symlinked individually into `~/.cursor/`; `User/` contents are symlinked into the platform Cursor user settings dir

Always remove the old file before symlinking (`rm -f` then `ln -s`). Validate symlinks with `[[ -L ${HOME}/.file ]]`.

### Cursor ↔ Claude Code Parity

`.cursor/plugins/` and `.cursor/skills-cursor/` are symlinked from this repo alongside `.claude/`. When adding or updating Claude Code plugins, skills, or MCP servers (Context7, Superpowers, Warp, etc.), check whether the same capability should be reflected in the Cursor config. The symlink setup means both tools share the same plugin/skills files on disk — but Cursor rules, model settings, and MCP server registration live in `.cursor/User/` and may need separate updates.

## Code Standards

### Shell Scripts

- **Shebang:** `#!/usr/bin/env bash` — always bash, never `/bin/sh`
- **Conditionals:** `[[ ... ]]` not `[ ... ]`
- **Variables:** `${VAR}` expansion with braces
- **Output:** `printf "message\n"` not `echo`
- **Functions:** `snake_case()` naming
- **Constants:** `SCREAMING_SNAKE_CASE`, marked `readonly` after assignment
- **Error handling:** Check `$?` or use `|| exit 1`; guard installs with `command -v`/`quiet_which()`
- **`env which` vs `command -v`:** `setup_env.sh` uses `which` (via `env which`) for the brew prerequisite check instead of `command -v` so that BATS tests can mock `which` through PATH injection. `command -v` is a shell builtin and ignores PATH mocks. Use `command -v` everywhere else; only reach for `which` when testability via PATH mock is required.
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

### PowerShell Scripts

- **Noun naming:** Functions must use singular nouns (`Install-ChocolateyPackage`, not `Install-ChocolateyPackages`) — PSUseSingularNouns rule
- **Avoid built-in collisions:** Do not name functions the same as Windows built-in cmdlets (e.g., use `Enable-RequiredWindowsOptionalFeature`, not `Enable-WindowsOptionalFeature`)
- **COM object wrappers:** Wrap `New-Object -ComObject` calls in thin functions (`Get-UpdateSearcher`, etc.) so Pester can mock them on macOS
- **Null comparisons:** `$null -eq $result` not `$result -eq $null` (PSPossibleIncorrectComparisonWithNull)
- **No aliases:** `Invoke-Expression` not `iex`; full cmdlet names throughout
- **Cross-platform test stubs:** Windows-only cmdlets that don't exist on macOS must be stubbed as `function global:CmdletName { }` in `BeforeAll`

### Version Pinning

All tool versions are defined as constants in `lib/constants.sh`:

```bash
GO_VER="1.26"
PYTHON_VER="3.14.2"
RUBY_VER="4.0.2"
```

Update these constants when bumping versions — don't hardcode versions elsewhere.
When a constant is updated, update all other references to that constant across the repo.

## Testing

Uses **BATS** (Bash Automated Testing System), installed natively:

- macOS: `brew install bats-core` (in `Brewfile`)
- Ubuntu: `sudo apt-get install -y bats` (via `install_bats()` in `setup_env.sh`)
- RHEL/CentOS/Fedora: direct GitHub release install (via `install_bats()`)

**Run tests:** `make test` (runs lint then all BATS tests)
**Run unit tests only:** `make test-unit` (runs `unit.bats`, `profiles.bats`, and `zshrc.d/unit.bats`)
**Run lint only:** `make lint` (bash -n + zsh -n + shellcheck on all .sh files)
**Install pre-commit hook:** `make install-hooks` (symlinks `scripts/pre-commit-hook.sh` into `.git/hooks/pre-commit`; run once per checkout)

### ShellCheck

`.shellcheckrc` at the repo root suppresses pervasive intentional patterns:

- `SC2086`: unquoted variables — intentional style throughout
- `SC2034`: unused variables — many used externally via source
- `SC1091`: not following source — expected for sourced lib architecture
- `SC2181`: checking `$?` directly — intentional pattern

Inline disables (`# shellcheck disable=SCxxxx # reason`) are used for remaining site-specific suppressions.

### CI / GitHub Actions

`.github/workflows/ci.yml` runs on every push (all branches including master) and PRs to master:

- `test` job: installs bats + shellcheck, runs `make test`
- `lint-macos` job: runs `bash -n` and `zsh -n` on all `.sh` files on `macos-latest` (advisory, not blocking auto-merge)
- `secret-scan` job: runs gitleaks against recent commits (advisory, not blocking auto-merge)
- `auto-merge` job: auto-merges any PR when all three CI jobs pass (depends on `test`, `lint-macos`, `secret-scan`)

CI requirements:

- All jobs run on `ubuntu-latest` with `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: true`
- Uses `actions/checkout@v5`

### Testing Rules

- Every new function in `setup_env.sh` must have a test in `tests/setup_env/unit.bats` (pure logic) or `tests/setup_env/install_guards.bats` (side effects requiring mocks)
- Every modification to an existing function must update its test
- New shell scripts get their own directory under `tests/` (e.g., `tests/scripts/`)
- Never modify real system state in tests — use PATH-based mocks from `tests/mocks/`
- `make test` must exit 0 before committing

### PowerShell Testing

Run from the `powershell/` directory:

```bash
cd powershell
make test   # runs PSScriptAnalyzer lint then Pester tests
make lint   # PSScriptAnalyzer only
```

Prerequisites (one-time):

```bash
brew install --cask powershell
pwsh -Command "Install-Module Pester -Force -Scope CurrentUser -MinimumVersion 5.0"
pwsh -Command "Install-Module PSScriptAnalyzer -Force -Scope CurrentUser"
```

### Test Seams

Functions that operate on specific file paths use override env vars to redirect to temp files in tests:

| Seam                       | Used by                          | Effect                                                                             |
| -------------------------- | -------------------------------- | ---------------------------------------------------------------------------------- |
| `_OVERRIDE_CONSTANTS_PATH` | `_update_version_pin()`          | Redirects to a temp copy of `lib/constants.sh`; defaults to real path when unset   |
| `UPDATE_LOG_PATH`          | `_update_summary()`              | Redirects log writes to a temp file in tests; defaults to `~/.dotfiles-update.log` |
| `_UPDATE_TMPDIR`           | all summary functions            | Set to `${BATS_TEST_TMPDIR}` in tests to isolate snapshot files                    |
| `_BOOTSTRAP_OS_RELEASE`    | `_bootstrap_linux_detect_distro` | Path to os-release file; defaults to `/etc/os-release`                             |

Pattern: `local _file="${_OVERRIDE_VAR:-$(dirname "${BASH_SOURCE[0]}")/real/path}"`. Tests set the var and pass a writable temp copy; production code leaves it unset.

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
| `MOCK_ID_U` | Value returned by `id -u` (default: 1000) |
| `MOCK_YUM_LIST_EXIT` | Exit code for `yum list installed` (default: 0) |
| `MOCK_YUM_EXIT` | Exit code for other `yum` commands (default: 0) |
| `MOCK_AWK_OS_NAME` | Distro name returned when `awk` parses `os-release` |
| `MOCK_SW_VERS_PRODUCTVERSION` | OS version returned by `sw_vers -productVersion` (default: 12.0.0) |
| `MOCK_SYSCTL_CPU` | CPU brand string returned by `sysctl -n machdep.cpu.brand_string` (default: Apple M1) |
| `MOCK_PGREP_EXIT` | Exit code for `pgrep` (default: 1 = process not found) |
| `MOCK_SOFTWAREUPDATE_EXIT` | Exit code for `softwareupdate` (default: 0) |
| `MOCK_WGET_EXIT` | Exit code for `wget` (default: 0); `-O` target file is created |
| `MOCK_DPKG_EXIT` | Exit code for `dpkg` (default: 0) |
| `MOCK_CHSH_EXIT` | Exit code for `chsh` (default: 0) |
| `MOCK_APT_ONLY_EXIT` | Exit code for `apt` only (overrides MOCK_APT_EXIT for apt; default: MOCK_APT_EXIT) |
| `MOCK_ADD_APT_REPO_EXIT` | Exit code for `add-apt-repository` (default: 0) |
| `MOCK_DNF_EXIT` | Exit code for `dnf` (default: 0) |
| `MOCK_INSTALLER_EXIT` | Exit code for `installer` (default: 0) |
| `MOCK_UNZIP_EXIT` | Exit code for `unzip` (default: 0) |
| `MOCK_GIT_CLONE_EXIT` | Exit code for `git clone` (default: 0); target directory is created |
| `MOCK_GIT_EXIT` | Exit code for all other `git` commands (default: 0) |
| `MOCK_MAS_EXIT` | Exit code for `mas` (default: 0) |
| `MOCK_MAS_UPGRADE_OUTPUT` | Lines printed to stdout by `mas upgrade` mock (default: empty); use `==> Updated AppName (version)` lines to simulate updated apps |
| `MOCK_TEE_EXIT` | Exit code for `tee` (default: 0); real `/usr/bin/tee` is called unless exit ≠ 0 |
| `MOCK_GEM_EXIT` | Exit code for `gem` (default: 0) |
| `MOCK_SNAP_EXIT` | Exit code for `snap` (default: 0) |
| `MOCK_NALA_EXIT` | Exit code for `nala` (default: 0) |
| `MOCK_RUSTUP_EXIT` | Exit code for `rustup` (default: 0) |
| `MOCK_BREW_UPDATE_EXIT` | Exit code for `brew update` (default: 0) |
| `MOCK_BREW_UPGRADE_EXIT` | Exit code for `brew upgrade` and `brew upgrade --cask --greedy` (default: 0) |
| `MOCK_BREW_CLEANUP_EXIT` | Exit code for `brew cleanup` (default: 0) |
| `MOCK_CURL_STDOUT` | Content printed to stdout by `curl` mock (used for `$(curl ...)` substitution; default: empty) |
| `MOCK_XCODE_SELECT_PRINT_PATH_EXIT` | Exit code for `xcode-select --print-path` (default: 0 = already installed) |
| `MOCK_XCODE_SELECT_EXIT` | Exit code for `xcode-select --install` (default: 0) |
| `MOCK_XCODEBUILD_EXIT` | Exit code for `xcodebuild` (default: 0) |
| `MOCK_KILL_EXIT` | Exit code for `kill` (default: 0) |
| `MOCK_TMUX_EXIT` | Exit code for `tmux` (default: 0) |
| `MOCK_RSYNC_EXIT` | Exit code for `rsync` (default: 0) |
| `MOCK_HOSTNAME_OUTPUT` | Value returned by `hostname -s` (default: `testhost`) |
| `MOCK_SLEEP_EXIT` | Exit code for `sleep` (default: 0) |
| `MOCK_PGREP_OUTPUT` | PIDs printed to stdout by `pgrep` mock (default: empty; used to simulate found processes) |
| `MOCK_LN_EXIT` | Exit code for `ln` (default: 0); real `/bin/ln` is called unless exit ≠ 0 |
| `MOCK_CHMOD_EXIT` | Exit code for `chmod` (default: 0); real `/bin/chmod` is called unless exit ≠ 0 |
| `MOCK_MV_EXIT` | Exit code for `mv` (default: 0); real `/bin/mv` is called unless exit ≠ 0 |
| `MOCK_CP_EXIT` | Exit code for `cp` (default: 0); real `/bin/cp` is called unless exit ≠ 0 |
| `MOCK_RPM_EXIT` | Exit code for `rpm` (default: 0) |
| `MOCK_TAR_EXIT` | Exit code for `tar` (default: 0); when non-zero, suppresses stub directory creation so tests can simulate extraction failure and trigger `cd` failure |
| `MOCK_CPAN_EXIT` | Exit code for `cpan` (default: 0) |
| `MOCK_CPANM_EXIT` | Exit code for `cpanm` (default: 0) |

**Pass-through mocks:** `ln`, `chmod`, `mv`, `cp`, and `tee` call the real binary (`/bin/cmd "$@" 2>/dev/null || true`) so tests that assert actual filesystem state (permissions, file existence, symlinks, captured output files) work correctly. Set the corresponding exit var to a non-zero value to simulate failure instead. Any mock that needs to support tests checking real filesystem state must use this pattern — a log-only mock will cause silent assertion failures.

## Key Conventions

- Machine roles are now driven by the **profile/capability model** in `config/profiles.sh` — prefer `HAS_*` vars over raw hostname patterns for new code
- Legacy hostname vars (`LAPTOP`, `STUDIO`, `RECEPTION`, `OFFICE`, `HOMES`) are preserved as readonly aliases in `detect_env.sh` — `WORKSTATION` and `CRUNCHER` have been removed; use `HAS_*` vars instead
- Ubuntu version detection uses `lsb_release -rs` → `FOCAL`, `JAMMY`, `NOBLE` vars
- Credential directories (`.aws`, `.tf_creds`, `.tsh`) are created with `chmod 700`
- Git repos are cloned to `~/git-repos/personal/` and `~/git-repos/work/`
- Python environments managed via **pyenv** + **pyenv-virtualenv**; the `ansible` venv is the primary one
- Application installs are kept in alphabetical order
- For shell syntax-only fixes in `setup_env.sh`, validate with both `bash -n setup_env.sh` and `zsh -n setup_env.sh` before commit

## Local-Only State

The following paths are machine-local and must **never** be committed to this repo:

- `~/.aws/` — AWS credentials and config
- `~/.tf_creds/` — Terraform cloud credentials
- `~/.ssh/` private keys — only `config` and `teleport.cfg` are tracked in `.ssh/` in the repo
- `~/.azure_creds/` — Azure credentials
- `~/.gcloud_creds/` — GCloud credentials
- `~/.tsh/` — Teleport session tokens
- `~/.claude/projects/<path>/` conversation history jsonl files — only `memory/` subdirs are tracked
- `config/local.sh` — machine-local overrides; copy from `config/local.sh.example`, git-ignored

The `secret-scan` CI job (`gitleaks`) scans recent commits for credential patterns. If it fires on a legitimate file, add an allowlist entry to `.gitleaks.toml`.

## Profile Model

After `detect_env()` runs, the following vars are set:

| Var            | Values                                                                                                                    |
| -------------- | ------------------------------------------------------------------------------------------------------------------------- |
| `PROFILE`      | String: `personal_laptop`, `mac_workstation`, `mac_mini`, `linux_workstation`, `wsl2_workstation`, `server`, or `unknown` |
| `HAS_GUI`      | Set for: personal_laptop, mac_workstation, mac_mini, linux_workstation, wsl2_workstation                                  |
| `HAS_DEVTOOLS` | Set for: personal_laptop, mac_workstation, linux_workstation, wsl2_workstation, server                                    |
| `HAS_AWS`      | Set for: personal_laptop, mac_workstation, linux_workstation, wsl2_workstation, server                                    |
| `HAS_K8S`      | Set for: personal_laptop, mac_workstation, linux_workstation, wsl2_workstation                                            |
| `HAS_DOCKER`   | Set for: personal_laptop, mac_workstation, linux_workstation, wsl2_workstation                                            |
| `HAS_RUST`     | Set for: personal_laptop, mac_workstation, linux_workstation, wsl2_workstation                                            |
| `HAS_SNAP`     | Set for: linux_workstation only (not wsl2_workstation — snap unavailable in WSL2)                                         |
| `HAS_PRINTING` | Set for: personal_laptop, mac_workstation, mac_mini                                                                       |

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

3. Push a feature branch — CI validates → auto-merges to master.

No other files need changing.
