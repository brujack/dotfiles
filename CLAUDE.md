# CLAUDE.md — dotfiles

## Repository Overview

Personal development environment bootstrapping system for macOS and Linux (Ubuntu/RHEL). Manages shell configs, tool installation, and symlink setup across multiple machine types.

## Layout

```
dotfiles/
├── setup_env.sh              # Main entry point — sources lib/, dispatches workflows
├── Brewfile                  # Homebrew bundle manifest (100+ formulae/casks); entries tagged # [HAS_*] are capability-gated
├── config/
│   └── profiles.sh           # hostname → profile map; edit here to add a new machine
├── docs/
│   ├── adr/                  # Architectural Decision Records (cross-cutting decisions)
│   │   ├── README.md         # ADR index table
│   │   └── NNNN-title.md     # Individual ADRs (0001, 0002, …)
│   ├── claude-code-new-features/  # Weekly Claude Code feature digests
│   │   ├── README.md         # Usage and schedule docs
│   │   ├── .changelog-state.md   # Last-fetched CHANGELOG snapshot (do not edit)
│   │   └── features-YYYY-MM-DD.md  # Weekly digest committed each Monday
│   ├── anthropic-new-features/  # Weekly Anthropic & Claude API feature digests
│   │   ├── README.md                # Usage and schedule docs
│   │   ├── .platform-state.txt      # Last-fetched platform notes (HTML-stripped; do not edit)
│   │   ├── .sdk-state.md            # Last-fetched Python SDK CHANGELOG (do not edit)
│   │   └── features-YYYY-MM-DD.md   # Weekly digest committed each Monday
│   └── superpowers/          # Design specs and implementation plans
│       ├── specs/            # Design documents (YYYY-MM-DD-*-design.md)
│       └── plans/            # Implementation plans (YYYY-MM-DD-*.md)
├── lib/
│   ├── constants.sh          # Version pins, download URLs, directory vars
│   ├── helpers.sh            # Logging (log_info/warn/error), safe_link, install guards, brew helpers
│   ├── detect_env.sh         # OS/version detection + profile/capability resolution
│   ├── macos.sh              # macOS install functions (install_macos_packages)
│   ├── linux_shared.sh       # Cross-distro: install_git_linux, install_zsh_linux, install_bats, update_system_packages
│   ├── linux_ubuntu.sh       # Ubuntu orchestrator (install_ubuntu_packages) + 12 private _install_ubuntu_* helpers
│   ├── linux_rhel.sh         # RHEL/CentOS: install_rhel_packages, install_centos_packages, install_linux_packages
│   ├── developer.sh          # Cross-platform dev tools (install_ruby_tools, install_ruby, setup_kitchen, setup_ansible, clone_personal_repos, etc.)
│   ├── update_summary.sh     # Update run tracking and summary reporting
│   └── workflows.sh          # Top-level workflow functions dispatched by setup_env.sh
├── scripts/
│   ├── bootstrap_mac.sh      # One-time macOS prerequisite installer (Homebrew + bash 5)
│   ├── .osx.sh               # macOS system defaults (run during setup)
│   ├── whats-new-claude-code.sh  # Weekly Claude Code features digest (fetch, summarize, commit)
│   ├── whats-new-anthropic.sh    # Weekly Anthropic & Claude API digest (fetch, summarize, commit)
│   └── ...                   # utility scripts
├── powershell/
│   ├── setup_windows.ps1     # Windows/PowerShell bootstrap
│   ├── Makefile              # lint + test targets for PowerShell
│   ├── PSScriptAnalyzerSettings.psd1  # PSScriptAnalyzer rule config
│   ├── run-lint.ps1          # lint script with module path restoration (called by make lint)
│   ├── run-tests.ps1         # combined lint+test script (called by make test)
│   └── tests/
│       └── setup_windows.Tests.ps1   # Pester v5 unit tests (22 tests)
├── .zshrc                    # Main zsh config (sources .zshrc.d modules)
├── .zprofile                 # Zsh login shell config
├── .vimrc                    # Vim config with 50+ plugins
├── .tmux.conf                # Tmux config (Dracula theme, tpm, C-a prefix)
├── .p10k.zsh                 # Powerlevel10k prompt config
├── .gitconfig_mac            # Git config for macOS
├── .gitconfig_mac_gitlab     # Git config for macOS (GitLab)
├── .gitconfig_linux          # Git config for Linux
├── .gitconfig_linux_gitlab   # Git config for Linux (GitLab)
├── .config/
│   ├── .zshrc.d/             # Modular zsh config (7 numbered files)
│   │   ├── 1_init.zsh        # OS detection, initial setup
│   │   ├── 2_functions.zsh   # Shell functions
│   │   ├── 3_oh-my-zsh.zsh   # Oh-My-Zsh config
│   │   ├── 4_aliases.zsh     # Aliases
│   │   ├── 5_general.zsh     # General settings
│   │   ├── 6_path.zsh        # PATH configuration
│   │   └── 7_final.zsh       # Final setup, completions
│   └── ccstatusline/         # Claude Code status line config
├── bruce.omp.json            # Oh My Posh prompt theme
├── profile.ps1               # PowerShell profile
├── starship.toml             # Starship prompt config
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

Dotfiles live at the repo root and in the ai-config repo (`.claude/`/`.cursor/`). `setup_env.sh` creates symlinks from `$HOME` into the repos:

- **Repo root** — each dotfile symlinked individually into `$HOME` (e.g. `~/.zshrc → dotfiles/.zshrc`)
- **`.claude/`** — each item (except `projects/`) symlinked individually into `~/.claude/` from the ai-config repo.
  Exception: `mcp.json.template` is symlinked as `~/.claude/mcp.json.template` (read-only reference); the live
  `~/.claude/mcp.json` is **generated** by `setup_claude_mcp` via `envsubst` and is not a symlink.
  The `projects/` subdirectory is **not** symlinked wholesale — per-repo memories are managed individually.
- **`.cursor/`** — each item (excluding `User/`) symlinked individually into `~/.cursor/` from the ai-config repo; `User/` contents are symlinked into the platform Cursor user settings dir

Always remove the old file before symlinking (`rm -f` then `ln -s`). Validate symlinks with `[[ -L ${HOME}/.file ]]`.

### Cursor ↔ Claude Code Parity

`.cursor/plugins/` and `.cursor/skills-cursor/` are symlinked from this repo alongside `.claude/`. When adding or updating Claude Code plugins, skills, or MCP servers (Context7, Superpowers, Warp, etc.), check whether the same capability should be reflected in the Cursor config. The symlink setup means both tools share the same plugin/skills files on disk — but Cursor rules, model settings, and MCP server registration live in `.cursor/User/` and may need separate updates.

## GitHub MCP

The GitHub MCP server is configured globally (user scope) via `~/.claude/mcp.json`.
It provides native GitHub operations — PR review, issue management, repo browsing,
diff access — across all projects without copy-pasting into chat.

Requires `GITHUB_PAT` to be set in `~/git-repos/personal/dotfiles/config/local.sh`.
If it isn't set, run `setup_env.sh -t setup_user` after adding the token.
Verify with `setup_env.sh -t doctor`.

Use it for:

- Fetching PR diffs and changed files
- Reading and creating issues
- Posting structured review comments
- Browsing repo contents

Do not use it to push directly to main/master — normal PR workflow still applies.

## Code Standards

### Shell Scripts

See `~/.claude/standards/shell.md` for the full shell coding standards. Dotfiles-specific notes:

- **`env which` vs `command -v`:** `setup_env.sh` uses `which` (via `env which`) for the brew prerequisite check instead of `command -v` so that BATS tests can mock `which` through PATH injection. `command -v` is a shell builtin and ignores PATH mocks. Use `command -v` everywhere else.
- **No `set -euo pipefail`** at top-level — conditional installs require non-zero exits to continue.
- **Sourcing guard on every lib file:** All files under `lib/` that are tested must include `[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0` near the top. When extracting functions into new lib files, add this guard explicitly — plan specs may omit it but the test harness requires it.

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

### Brewfile Capability Tags

Entries in `Brewfile` can be tagged with a trailing `# [HAS_*]` comment to make them profile-aware. The `brew-drift` check (`_update_check_brewfile_drift`) skips tagged entries when the named capability variable is not set on the current machine:

```
brew "postgresql@14"  # [HAS_DEVTOOLS]
cask "docker"         # [HAS_DOCKER]
cask "lens"           # [HAS_K8S]
brew "rustup"         # [HAS_RUST]
```

Untagged entries are expected on all macs. When adding a new Brewfile entry that is developer-, K8s-, Docker-, or Rust-specific, add the appropriate tag.

### PowerShell Scripts

See `~/.claude/standards/powershell.md` for the full PowerShell coding and testing standards.

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
**Install hooks:** `make install-hooks` (installs pre-commit and pre-push hooks; run once per checkout)
**Sync agent guidance:** `make sync-agent-guidance` (regenerates `.cursor/rules/global-claude-standards.mdc` from `.claude/CLAUDE.md` + `.claude/standards/*.md`)
**Check agent guidance drift:** `make check-agent-guidance` (fails when generated Cursor guidance is stale)

The pre-commit hook is **required**. It runs on every `git commit`:

1. `make lint` — blocks the commit on any syntax or shellcheck failure
2. `ggshield secret scan pre-commit` — scans staged changes for secrets before they reach the remote; skipped gracefully if ggshield is not installed

The pre-push hook is **permanent**. It runs `make test` (lint + bats) on every push before the push reaches GitHub. Skips branch deletions. This conserves GitHub Actions minutes — CI runs only on PRs.

**Worktree compatibility requirement:** `scripts/pre-push` must resolve repo root with `git rev-parse --show-toplevel` first, and use `git rev-parse --git-common-dir` parent only as a fallback. Direct `git-common-dir` resolution can run tests against the shared checkout instead of the active worktree branch.

The CI `secret-scan` job (gitleaks) is a backstop, not a substitute for local scanning. Install ggshield: `brew install gitguardian/tap/ggshield && ggshield auth login`.

### ShellCheck

`.shellcheckrc` at the repo root suppresses pervasive intentional patterns:

- `SC2086`: unquoted variables — intentional style throughout
- `SC2034`: unused variables — many used externally via source
- `SC1091`: not following source — expected for sourced lib architecture
- `SC2181`: checking `$?` directly — intentional pattern

Inline disables (`# shellcheck disable=SCxxxx # reason`) are used for remaining site-specific suppressions.

### CI / GitHub Actions

`.github/workflows/ci.yml` runs on PRs to master only (the pre-push hook gates branch pushes locally):

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
- When moving or renaming a directory that tests reference, run `grep -r "<old-path>" tests/` before claiming no test changes are needed — hardcoded paths in test fixtures will break even when the production code uses `$PERSONAL_GITREPOS/$DOTFILES/` prefixes

### PowerShell Testing

See `~/.claude/standards/powershell.md` for PowerShell coding and testing standards. Run tests in this repo from the `powershell/` directory:

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

### Coverage

#### PowerShell

- **`setup_windows.ps1`: 92.22%** (line coverage, measured by Pester `-CodeCoverage`)
- Floor: 90%. `make test` and CI both fail on any drop below the floor.
- Scope: `setup_windows.ps1` only. `run-tests.ps1` and `run-lint.ps1` are excluded as test/lint glue (per tdd.md "entry-point glue that purely calls already-tested functions"). The top-level `if ($IsWindows) { ... }` dispatcher in `setup_windows.ps1` is also excluded for the same reason — `$IsWindows` is a runtime read-only automatic variable that cannot be overridden in tests; the bodies it calls (`Invoke-DotfilesSetup`, `Invoke-DotfilesUpdate`) are tested directly.
- Re-measure: `cd powershell && make test` prints `Coverage: <N>%` and writes `coverage.xml`.
- Update this figure whenever tests are added or removed.

#### Bash

- **Status: measurement mode — gate not yet enabled.** The CI `bash-coverage` job runs but is non-blocking; it exits 0 with a warning when no coverage data is produced.
- **`make coverage`** runs kcov locally and reports per-file percentages. Works on macOS and Linux VMs where kcov is installed (`brew install kcov`).
- **Per-file floors defined** (not yet enforced): 90% for `setup_env.sh`, `constants.sh`, `detect_env.sh`, `helpers.sh`, `workflows.sh`, `update_summary.sh`, `developer.sh`; 75% for `linux_shared.sh`, `linux_ubuntu.sh`, `linux_rhel.sh`, `macos.sh`.
- **Do not retry kcov or bashcov in GitHub Actions** — both are confirmed broken:
  - **kcov**: ptrace mechanism fails in GH Actions regardless of security settings. Tested: `ptrace_scope=0`, Docker container with `seccomp=unconfined`, `--cap-add SYS_PTRACE`, and `--privileged`. In all cases kcov runs the tests but produces no coverage data and no `index.json`. Root cause: kcov cannot trace bats' test subshells in the GH Actions environment.
  - **bashcov**: incompatible with bats-core. bats hardcodes UUID `608a9069-2672-4fa2-a0e1-2823af783b95` in its temp file paths; bashcov's LINENO parser chokes on it and aborts with no coverage data.
- **Future path**: a custom `BASH_ENV` + DEBUG trap tracer (no ptrace required) is the correct approach for CI bash coverage.

### Test Seams

Functions that operate on specific file paths use override env vars to redirect to temp files in tests:

| Seam                         | Used by                                                              | Effect                                                                             |
| ---------------------------- | -------------------------------------------------------------------- | ---------------------------------------------------------------------------------- |
| `_OVERRIDE_BREWFILE_PATH`    | `_update_check_brewfile_drift`                                       | Path to Brewfile; defaults to `${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile`          |
| `_OVERRIDE_CONSTANTS_PATH`   | `_update_version_pin()`                                              | Redirects to a temp copy of `lib/constants.sh`; defaults to real path when unset   |
| `UPDATE_LOG_PATH`            | `_update_summary()`                                                  | Redirects log writes to a temp file in tests; defaults to `~/.dotfiles-update.log` |
| `_UPDATE_TMPDIR`             | all summary functions                                                | Set to `${BATS_TEST_TMPDIR}` in tests to isolate snapshot files                    |
| `_BOOTSTRAP_OS_RELEASE`      | `_bootstrap_linux_detect_distro`                                     | Path to os-release file; defaults to `/etc/os-release`                             |
| `_REBOOT_REQUIRED_PATH`      | `_update_record_end` apt case                                        | Path to reboot-required flag file; defaults to `/var/run/reboot-required`          |
| `_REBOOT_REQUIRED_PKGS_PATH` | `_update_record_end` apt case                                        | Path to reboot-required.pkgs file; defaults to `/var/run/reboot-required.pkgs`     |
| `_OVERRIDE_FEATURES_DIR`     | `scripts/whats-new-claude-code.sh`, `scripts/whats-new-anthropic.sh` | Redirects output and state files to a temp dir                                     |
| `_OVERRIDE_DOTFILES_ROOT`    | `scripts/whats-new-claude-code.sh`, `scripts/whats-new-anthropic.sh` | Redirects the repo root used for `cd` before git operations                        |
| `_OVERRIDE_AI_CONFIG_DIR`    | `setup_ai_config`, `setup_dotfile_symlinks`                          | Overrides `AI_CONFIG_DIR` (readonly) for test isolation                            |

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
| `MOCK_BREW_LIST_FORMULA` | Space-separated formulas returned by `brew list --formula --full-name` (use tap-qualified names, e.g. `teamookla/speedtest/speedtest`) |
| `MOCK_BREW_LIST_CASK` | Space-separated casks returned by `brew list --cask` |
| `MOCK_BREW_LEAVES` | Space-separated formulae returned by `brew leaves` (top-level installs only; default: empty) |
| `MOCK_BREW_TAPS` | Space-separated taps returned by `brew tap` |
| `MOCK_BREW_INSTALL_EXIT` | Exit code for `brew install` (default: 0) |
| `MOCK_BREW_TAP_EXIT` | Exit code for `brew tap <name>` (default: 0) |
| `MOCK_APT_EXIT` | Exit code for `apt-get` (default: 0) |
| `MOCK_WHICH_MISSING` | Command name for which `which` returns 1 |
| `MOCK_CURL_EXIT` | Exit code for `curl` (default: 0); use 22 for HTTP auth failure (FAIL), 28 for timeout (WARN), 6 for DNS failure (WARN) in `_doctor_check_github_mcp` tests |
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
| `MOCK_DPKG_QUERY_EXIT` | Exit code for `dpkg-query` (default: 0) |
| `MOCK_DPKG_OUTPUT` | Lines printed to stdout by `dpkg-query -W` mock (default: empty) |
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
| `MOCK_SNAP_LIST_OUTPUT` | Lines printed to stdout by `snap list` mock (default: empty); include a header line as first line since awk skips `NR>1` |
| `MOCK_NALA_EXIT` | Exit code for `nala` (default: 0) |
| `MOCK_RUSTUP_EXIT` | Exit code for `rustup` (default: 0) |
| `MOCK_BREW_UPDATE_EXIT` | Exit code for `brew update` (default: 0) |
| `MOCK_BREW_UPGRADE_EXIT` | Exit code for `brew upgrade` and `brew upgrade --cask --greedy` (default: 0) |
| `MOCK_BREW_CLEANUP_EXIT` | Exit code for `brew cleanup` (default: 0) |
| `MOCK_CURL_STDOUT` | Content printed to stdout by `curl` mock (used for `$(curl ...)` substitution; default: empty) |
| `MOCK_CURL_PLATFORM_STDOUT` | Content returned by `curl` mock when URL contains `platform.claude.com`; used by `whats-new-anthropic.sh` (default: falls back to `MOCK_CURL_STDOUT`) |
| `MOCK_CURL_SDK_STDOUT` | Content returned by `curl` mock when URL contains `githubusercontent.com`; used by `whats-new-anthropic.sh` (default: falls back to `MOCK_CURL_STDOUT`) |
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
| `MOCK_RPM_OUTPUT` | Lines printed to stdout by `rpm -qa` mock (default: empty) |
| `MOCK_TAR_EXIT` | Exit code for `tar` (default: 0); when non-zero, suppresses stub directory creation so tests can simulate extraction failure and trigger `cd` failure |
| `MOCK_CPAN_EXIT` | Exit code for `cpan` (default: 0) |
| `MOCK_CPANM_EXIT` | Exit code for `cpanm` (default: 0) |
| `MOCK_CLAUDE_EXIT` | Exit code for `claude` (default: 0); applies to all `claude` calls including `-p` |
| `MOCK_CLAUDE_STDOUT` | Content printed to stdout by `claude -p` mock (default: `## New Features\n- Mock feature added`); used by scripts that call `claude -p "prompt"` to summarize content |
| `MOCK_CLAUDE_PLUGINS_LIST_OUTPUT` | Lines printed to stdout by `claude plugins list` mock (default: empty) |

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
