# CLAUDE.md — dotfiles

## Repository Overview

Personal development environment bootstrapping system for macOS and Linux (Ubuntu). Manages shell configs, tool installation, and symlink setup across multiple machine types.

## Layout

```
dotfiles/
├── setup_env.sh       # Main entry — sources lib/, dispatches workflows
├── Brewfile           # Homebrew bundle (100+ formulae/casks; [HAS_*] tags are capability-gated)
├── lib/               # Shell libraries: constants, helpers, detect_env, macos, linux_shared,
│                      #   linux_ubuntu, developer, update_summary, workflows
├── config/            # profiles.sh (hostname→profile map); local.sh (machine overrides, git-ignored)
├── scripts/           # bootstrap_mac.sh, whats-new-*.sh, run-bash-coverage.sh
├── powershell/        # Windows bootstrap: setup_windows.ps1, Pester tests, Makefile
├── tests/             # BATS tests: setup_env/, zshrc.d/, mocks/, helpers/
├── docs/              # ADRs, knowledge/, superpowers/, claude-code-new-features/,
│                      #   anthropic-new-features/
├── .github/workflows/ # CI: test, lint-macos, bash-coverage, powershell, secret-scan, auto-merge
├── .zshrc, .vimrc, .tmux.conf, .gitconfig_*, starship.toml, bruce.omp.json, profile.ps1
└── ubuntu_*_packages.txt, kubernetes_stuff/, .ssh/
```

## 10-80-10 Execution Cycle

Sessions in this repo follow the 10-80-10 execution cycle defined in `ai-config` ADR-0009 (with the ADR-0010 wave-dispatch extension):

- **Phase 1 (10%) — Architect.** `brainstorming` → `writing-plans` (emit per-task YAML `yaml-task` blocks with `role`/`model`/`tdd`/`acceptance`/`max_retries`/`files_touched`/`depends_on`/`parallel_group`). Opus role.
- **Phase 2 (80%) — Execute.** `subagent-driven-development` runs iterate-until-green per task; FORBIDDEN list prevents gate cheating; wave-dispatch when `parallel_group` is declared. Sonnet/Haiku per task per the plan.
- **Phase 3 (10%) — Review.** `finishing-a-development-branch` chains `pr-review` → `security-review` → `bug-scan` → `docs` → `learnings` → finish. Opus role.

Validate a plan before dispatch:

```bash
make validate-plan PLAN=docs/superpowers/plans/<file>.md
```

The validator (`~/.claude/scripts/validate-plan.py`, shared from ai-config) enforces required fields, valid role/model/tdd values, haiku scope guard, and disjoint `files_touched` within each `parallel_group`.

## Knowledge Directory

Reference material for this repo lives in `ai-config/docs/knowledge/` under `dotfiles-<topic>.md` naming (per ADR-0020). The local `docs/knowledge/README.md` is a pointer stub. See `ai-config/docs/knowledge/README.md` for the master index.

When web research (web-research skill) or context-mode fetches produce findings worth preserving, save to `ai-config/docs/knowledge/dotfiles-<topic>.md`.

## Entry Points

```bash
./setup_env.sh -t <type>
```

| Type             | Purpose                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| ---------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `setup_user`     | Configs, shells, directory structure, symlinks, GitHub MCP (`setup_claude_mcp`), Claude plugins (`setup_claude_plugins`)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| `setup`          | Full machine setup (setup_user + all apps). Flags: `--brew-install`, `--mas-install`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| `developer`      | Dev packages + Python/Ansible virtualenv                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| `ansible`        | Ansible venv setup only (after Python updates)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| `recreate-venv`  | Force-delete and recreate a named pyenv virtualenv. Flags: `--venv-name` (default: `ansible`). Runs full pip install when name is `ansible`.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| `recreate-ruby`  | Force-delete and reinstall the pinned Ruby version (`RUBY_VER` in `lib/constants.sh`), reusing `install_ruby()`.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| `update`         | Update all packages (brew, apt/snap, pip, gems, tools). Supports `--brew-only`, `--pip-only`, `--gems-only`, `--mas-only`, `--claude-only` flags. Prints a structured summary at the end; each run is appended to `~/.dotfiles-update.log`. Also writes a schema v1.0 JSON entry to state-ledger (`~/.local/share/state-ledger`) when `~/.config/dotfiles/machine-id` is present — advisory, never fails the run. Pip update excludes `packaging`, `pathspec`, `rich`, `psutil`, `wheel` from the "upgrade all outdated" sweep — these have upper-bound conflicts with other installed packages; let the resolver manage them. State-ledger run_type: `update`. |
| `doctor`         | Active health checks: symlinks, tool presence, credential dir permissions, version drift. Exits non-zero on any failure                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| `check-versions` | Compare pinned versions in `lib/constants.sh` against GitHub latest; exits 1 if outdated. `--update` prompts per-tool to apply updates in-place                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |

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
- **`setup_env.sh` prereq bypass tests — assert absence, not `status -eq 0`:** Tests for `-t doctor` and `-t check-versions` bypass paths (in `tests/setup_env/unit.bats`) assert `[[ "$output" != *"Homebrew not found"* ]]` without asserting `[ "$status" -eq 0 ]`. Reason: `--brew-install` terminates cleanly at line 78 (`exit 0`), but `-t doctor` / `-t check-versions` call `run_doctor` / `run_check_versions` whose exit varies with mock environment. Adding `status -eq 0` to the doctor/check-versions tests causes flaky failures.
- **No `set -euo pipefail`** at top-level — conditional installs require non-zero exits to continue.
- **Sourcing guard on every lib file:** All files under `lib/` that are tested must include `[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0` near the top. When extracting functions into new lib files, add this guard explicitly — plan specs may omit it but the test harness requires it.

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
brew "lazydocker"     # [HAS_DOCKER]
cask "lens"           # [HAS_K8S]
brew "rustup"         # [HAS_RUST]
```

Untagged entries are expected on all macs. When adding a new Brewfile entry that is developer-, K8s-, Docker-, or Rust-specific, add the appropriate tag.

**Formula/cask dedup rule:** Never add both a formula and a cask for the same tool. Homebrew installs completion files to the same paths regardless of install method — having both causes `brew bundle` to fail with "Could not symlink" on every setup run. Canonical rule: use whichever form provides the complete tool (cask for GUI apps like Docker Desktop and PowerShell; formula only when no equivalent cask exists). `docker-desktop` cask provides the docker CLI; `powershell` formula provides `pwsh` — no separate formula or cask counterpart needed.

**Homebrew tap trust (Homebrew 6.0):** When adding a new third-party tap, also add it to the `brew trust` call in the relevant install function — `install_macos_casks` (macOS) and `_install_ubuntu_brew_packages` (Linux). `brew trust` is idempotent and ignores absent taps; omitting a tap causes a warning in Homebrew 5.2+ and will block installs in 6.0. `brew_update()` in `lib/helpers.sh` also re-establishes trust on every update run — this covers Homebrew major version upgrades that reset trust without requiring a full setup re-run.

### PowerShell Scripts

See `~/.claude/standards/powershell.md` for the full PowerShell coding and testing standards.

### Windows AI Config Setup

`setup_windows.ps1 -setup` links ai-config into native Windows alongside WSL2:

- `~/.claude/` — `settings.json`, `CLAUDE.md`, `mcp.json.template` as symlinks; `skills/`, `commands/`, `standards/` as junctions
- `~/.claude/mcp.json` — generated from template with `$env:GITHUB_PAT` substitution; set `GITHUB_PAT` in system environment before running setup
- `~/.cursor/` — `plugins/`, `rules/`, `skills-cursor/` as junctions
- `$env:APPDATA\Cursor\User\` — `settings.json`, `keybindings.json` as symlinks; `snippets/` as junction

**Hooks gap:** `.claude/hooks/` bash scripts are not linked on native Windows — they run only in WSL2 via `setup_env.sh`.

`setup_windows.ps1 -update` pulls the latest ai-config (`Install-AiConfig`) and updates npm globals (`Set-NpmGlobalPackages` → `firecrawl-cli`).

Requires: admin terminal (symlinks need elevation), `GITHUB_PAT` env var for MCP config, Node.js (installed via Chocolatey `nodejs`).

### Version Pinning

All tool versions are defined as constants in `lib/constants.sh`:

```bash
GO_VER="1.26"
PYTHON_VER="3.14.6"
RUBY_VER="4.0.5"
```

Update these constants when bumping versions — don't hardcode versions elsewhere.
When a constant is updated, update all other references to that constant across the repo.

### Ruby Version Manager Split

Ruby version managers: **rbenv on Linux** (`rbenv` installed via Homebrew in `lib/linux_ubuntu.sh`);
**chruby on macOS** (via `lib/macos.sh`). The two are not interchangeable across platforms.
Platform-specific installation and configuration is handled automatically by `install_ruby()` and
`install_ruby_tools()` in `developer.sh` — no manual intervention required.

On Linux, `install_ruby()` refreshes ruby-build definitions from git (an rbenv plugin clone/pull
at `~/.rbenv/plugins/ruby-build`, which shadows the brew-managed definitions) before running
`rbenv install --skip-existing ${RUBY_VER}`. This is required because the Homebrew ruby-build
bottle lags upstream — e.g. Ruby 4.0.5 on Ubuntu 26.04 was absent from the bottle but present in
git. A failed `rbenv install` warns and returns 0 (non-fatal) rather than aborting setup.
The build passes `RUBY_CONFIGURE_OPTS="--with-openssl-dir=/usr"` so Ruby's `openssl` extension links
against the **system** OpenSSL — the libcrypto the rbenv ruby loads at runtime. It must not derive the
dir from `pkg-config`: on machines with linuxbrew on `PATH`, `brew shellenv` puts the keg-only
`openssl@3` on `PKG_CONFIG_PATH`, so the extension would link against a newer Homebrew OpenSSL whose
versioned symbols (e.g. `OPENSSL_3.4.0`) are absent from the older system libcrypto (Ubuntu 24.04 ships
3.0.13) — breaking every `gem` HTTPS operation with "OpenSSL is not available". Passing
`--with-openssl-dir` makes the openssl gem's extconf skip `pkg-config` entirely.

`update_gems()` in `lib/developer.sh` handles the platform difference for `gem update`'s `PATH`
prepend — the chruby `bin` dir on macOS, the rbenv `shims` dir on Linux — used by both
`recreate_ruby()` and `run_update`'s gems step.

## Language Standards

Language-specific standards for this repo. These supplement the universal standards loaded
from `~/.claude/CLAUDE.md` (tdd, behavior, git-workflow, ci, code-standards, logic-review,
repo-structure, shell).

@~/.claude/standards/powershell.md

## Testing

Uses **BATS** (Bash Automated Testing System), installed natively:

- macOS: `brew install bats-core` (in `Brewfile`)
- Ubuntu: `sudo apt-get install -y bats` (via `install_bats()` in `setup_env.sh`)

**Run tests:** `make test` (runs lint then all BATS tests)
**Run unit tests only:** `make test-unit` (runs `unit.bats`, `profiles.bats`, and `zshrc.d/unit.bats`)
**Run lint only:** `make lint` (bash -n + zsh -n + shellcheck on all .sh files)
**Install hooks:** `make install-hooks` (installs pre-commit and pre-push hooks; run once per checkout)
**Sync agent guidance:** `make sync-agent-guidance` (regenerates `.cursor/rules/global-claude-standards.mdc` from `.claude/CLAUDE.md` + `.claude/standards/*.md`)
**Check agent guidance drift:** `make check-agent-guidance` (fails when generated Cursor guidance is stale)

The pre-commit hook is **required**. It runs on every `git commit`:

1. `make lint` — blocks the commit on any syntax or shellcheck failure
2. `ggshield secret scan pre-commit` — scans staged changes for secrets before they reach the remote; skipped gracefully if ggshield is not installed

The pre-push hook is **permanent**. It runs `make test` (lint + bats) on every push before the push reaches GitHub, but only when the push includes changes to `.sh` files, `.bats` files, `Makefile`, or anything under `tests/`. Pushes touching only config files (`.toml`, `.json`, `.md`, etc.) skip the test run entirely. Skips branch deletions. This conserves GitHub Actions minutes — CI runs only on PRs.

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

- `test` job: installs bats + shellcheck, runs `make test`, then verifies test count ≥ 840 (regression proxy; 865 tests as of 2026-07-05)
- `lint-macos` job: runs `bash -n` and `zsh -n` on all `.sh` files on `macos-latest` (advisory, not blocking auto-merge)
- `bash-coverage` job: measures bash line coverage via PS4 xtrace on `ubuntu-latest`; **gates at 90%** — blocks auto-merge if coverage drops below floor
- `secret-scan` job: runs gitleaks against recent commits (advisory, not blocking auto-merge)
- `auto-merge` job: auto-merges any PR when all CI jobs pass (depends on `test`, `lint-macos`, `powershell`, `bash-coverage`, `secret-scan`)

CI requirements:

- All jobs run on `ubuntu-latest` with `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: true`
- Uses `actions/checkout@v5`

### Testing Rules

- **`load_setup_env()` automatically sets OS vars:** All BATS test files in `tests/setup_env/` call `load_setup_env()` in their `setup()` function. This sources `setup_env.sh` → `detect_env.sh`, setting `MACOS=1` on macOS or `LINUX=1` + `UBUNTU=1` on Ubuntu Noble. Tests that call OS-branching functions do NOT need to explicitly export `MACOS` — they inherit the real OS detection. Only override (e.g. `unset MACOS; export LINUX=1; export UBUNTU=1`) when a test needs to simulate a different OS than the test machine.
- **`run_update` tests appear to hang due to real pip:** `load_setup_env()` sets `HAS_DEVTOOLS=1` on developer machines. Generic `run_update` tests (e.g. `run_update calls brew update on macOS`) call the full `run_update` function, which enters the pip section. Without `MOCK_PYENV_WHICH_STDOUT` set, the pyenv mock falls back to `command -v python3` (real python3), causing real `pip install` to run. The test passes but can take 1–3 min in the full suite. Workaround: set `MOCK_PYENV_WHICH_STDOUT="${BATS_TEST_DIRNAME}/../mocks/python"` in any test that calls `run_update` with `_run_all=1` and needs to be fast. Now automatic: load_mocks exports MOCK_PYENV_WHICH_STDOUT by default, so run_update tests stay hermetic without a per-test setting.
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

- **`setup_windows.ps1`: 95.54%** (line coverage, measured by Pester `-CodeCoverage`)
- Floor: 90%. `make test` and CI both fail on any drop below the floor.
- Scope: `setup_windows.ps1` only. `run-tests.ps1` and `run-lint.ps1` are excluded as test/lint glue (per tdd.md "entry-point glue that purely calls already-tested functions"). The top-level `if ($IsWindows) { ... }` dispatcher in `setup_windows.ps1` is also excluded for the same reason — `$IsWindows` is a runtime read-only automatic variable that cannot be overridden in tests; the bodies it calls (`Invoke-DotfilesSetup`, `Invoke-DotfilesUpdate`) are tested directly.
- Re-measure: `cd powershell && make test` prints `Coverage: <N>%` and writes `coverage.xml`.
- Update this figure whenever tests are added or removed.

#### Bash

- **Overall: 92%** (measured 2026-06-01 across 782 BATS tests; 861 tests as of 2026-07-05 after recreate-ruby feature + silent-failure fix PRs #172-173; per-file: `setup_env.sh` 89%, `helpers.sh` 90%, `workflows.sh` 91%, `update_summary.sh` 97%, `developer.sh` 91%, `linux_ubuntu.sh` 91%, `macos.sh` 97%, `constants.sh`/`detect_env.sh`/`linux_shared.sh` 96-100%)
- **`make bash-coverage`** measures coverage via `BASH_ENV` + PS4 xtrace tracer (`scripts/run-bash-coverage.sh`). Runs all bats tests with xtrace active; filters trace output through a named pipe to keep disk usage small (~200K lines vs ~33M raw).
- **`make push-bash-coverage`** runs `bash-coverage`, generates `coverage/bash.json` in shields.io format, and pushes it to the `coverage-data` branch. The README badge pulls from that branch.
- **Cron job (manual install)**: `(crontab -l 2>/dev/null; echo "0 2 * * * cd ~/git-repos/personal/dotfiles && make push-bash-coverage >> ~/.dotfiles-coverage.log 2>&1") | crontab -`
- **Per-file floors** (not yet enforced): 90% for `constants.sh`, `detect_env.sh`, `helpers.sh`, `workflows.sh`, `update_summary.sh`, `developer.sh`; 75% for `linux_shared.sh`, `linux_ubuntu.sh`, `macos.sh`.
- **Per-file ceilings** — some lines are inherently untraceable by the PS4 xtrace approach; don't waste time trying to test them:
  - `setup_env.sh`: ceiling ~89% — lines 70-85 (the direct-execution dispatch block) are inside `[[ "${BASH_SOURCE[0]}" == "${0}" ]]`; `run bash setup_env.sh` in BATS does not inherit FD 9, so subprocess xtrace output is lost. Floor set to 89% not 90%.
  - `helpers.sh`/`workflows.sh`: multi-line array literals (individual string entries not traced), `usage()` heredoc content lines, and continuation lines of multi-line curl commands are not emitted by bash xtrace. ~25-30 lines per file are structural non-traceables.
  - `macos.sh`: function declaration lines (`funcname() {`) not consistently traced across bash versions (~3 lines).
- **Status: gated in CI at 90%** — `bash-coverage` job runs on `ubuntu-latest` using the PS4 xtrace approach; blocks auto-merge if overall coverage drops below 90%.
- **Do not retry kcov or bashcov** — both confirmed broken:
  - **kcov**: works for direct bash scripts but cannot trace scripts sourced through bats; bats's test subshells are not captured. No data produced even locally.
  - **bashcov**: incompatible with bats-core. bats hardcodes UUID `608a9069-2672-4fa2-a0e1-2823af783b95` in its temp file paths; bashcov's LINENO parser chokes on it.
  - **BASH_ENV + DEBUG trap**: blocked by bats-core overriding the DEBUG trap with its own `bats_debug_trap`. PS4 xtrace (the implemented approach) works because bats does not clear `set -x` or `BASH_XTRACEFD`.
- **Coverable lines**: non-blank, non-comment lines only; structural keywords (`fi`, `done`, `}`, `else`, `then`, `do`, `esac`, `;;`) excluded — these are not emitted by bash xtrace and counting them would lower coverage artificially.
- **Coverage sprints: one PR per lib file.** Anti-pattern: 8 PRs in one day (May 28) touching the same framework. Future coverage work must be batched — one PR per lib file. This prevents context thrash and keeps CI load predictable.

### Test Seams

See [`ai-config/docs/knowledge/dotfiles-bats-test-infrastructure.md`](https://github.com/brujack/ai-config/blob/master/docs/knowledge/dotfiles-bats-test-infrastructure.md) for the full override env var table (moved to ai-config per ADR-0020).

Pattern: `local _file="${_OVERRIDE_VAR:-$(dirname "${BASH_SOURCE[0]}")/real/path}"`. Tests set the var and pass a writable temp copy; production code leaves it unset.

### Mock Pattern

See [`ai-config/docs/knowledge/dotfiles-bats-test-infrastructure.md`](https://github.com/brujack/ai-config/blob/master/docs/knowledge/dotfiles-bats-test-infrastructure.md) for the full `MOCK_*` env var reference table and the usage pattern.

**Pass-through mocks:** `ln`, `chmod`, `mv`, `cp`, and `tee` call the real binary (`/bin/cmd "$@" 2>/dev/null || true`) so tests that assert actual filesystem state work correctly. Set the corresponding exit var to a non-zero value to simulate failure instead.

**`env -i` subprocess strips PATH — place pyenv mock at `$PYENV_ROOT/bin/pyenv`:** `setup_ansible()` on Linux uses `env -i ... bash -lc '... pyenv install ...'` with a stripped environment. PATH-injected mocks in `tests/mocks/` are invisible to this subprocess because `env -i` clears `PATH`. To intercept pyenv calls in these tests, create the mock directly at `${HOME}/.pyenv/bin/pyenv` (the hardcoded path pyenv resolves to):

```bash
mkdir -p "${HOME}/.pyenv/bin"
cp "${BATS_TEST_DIRNAME}/../mocks/pyenv" "${HOME}/.pyenv/bin/pyenv"
chmod +x "${HOME}/.pyenv/bin/pyenv"
```

This pattern applies to any function that strips the environment and invokes pyenv by absolute path.

### Doctor Test Conventions

When writing tests for `_doctor_check_*` functions in `tests/setup_env/unit.bats`:

- **`_DOCTOR_FAIL` vs `_DOCTOR_FAILED`:** `_DOCTOR_FAIL` is the count (incremented by `doctor_fail`); `_DOCTOR_FAILED` is the 0/1 flag (set once when any failure occurs). Use `-ge N` on `_DOCTOR_FAIL` to assert a specific failure count; use `-eq 0` on `_DOCTOR_FAILED` to assert no failures. Using `-ge 4` on `_DOCTOR_FAILED` always fails — it can only be 0 or 1.
- **`log_warn` vs `doctor_warn`:** `log_warn` does **not** increment `_DOCTOR_WARN`. Only `doctor_warn` does. When a branch calls `log_warn` (e.g. tool not installed), assert `_DOCTOR_FAILED -eq 0` and `_rc -eq 0`; do not assert on `_DOCTOR_WARN`.
- **`_doctor_check_one_version` is nested:** Defined inside `_doctor_check_versions`; cannot be called in isolation. Test it by calling `_doctor_check_versions` directly with PATH controlled to expose the desired branch.
- **Full PATH isolation for version tests:** For `_doctor_check_versions` tests, use `PATH="${_tmp}"` (minimal — no other tools), not `PATH="${_tmp}:${PATH}"`. Real installed tools (zsh, python3, ruby) found via `${PATH}` may have versions that don't match the pinned constants in `lib/constants.sh`, causing spurious `doctor_fail` calls that break assertions.

## Committing Work

Invoke `caveman:caveman-commit` skill to generate the commit message before running `git commit`. Full format and rules in `~/.claude/CLAUDE.md`.

## Key Conventions

- Machine roles are now driven by the **profile/capability model** in `config/profiles.sh` — prefer `HAS_*` vars over raw hostname patterns for new code
- Legacy hostname vars (`LAPTOP`, `STUDIO`, `RECEPTION`, `OFFICE`, `HOMES`) are preserved as readonly aliases in `detect_env.sh` — `WORKSTATION` and `CRUNCHER` have been removed; use `HAS_*` vars instead
- Ubuntu version detection uses `lsb_release -rs` → `NOBLE` var (24.04) or `RESOLUTE` var (26.04); both set in `detect_env.sh` and `.zshrc.d/1_init.zsh`
- Credential directories (`.aws`, `.tf_creds`, `.tsh`) are created with `chmod 700`
- Git repos are cloned to `~/git-repos/personal/` and `~/git-repos/work/`
- Python environments managed via **pyenv** + **pyenv-virtualenv**; the `ansible` venv is the primary one
- **Ansible venv packages (explicit):** ansible, ansible-lint, molecule, molecule-plugins[docker], certbot, certbot-dns-cloudflare, checkov, boto3, docker, gmpy2, jmespath, mpmath, netaddr, pylint, psutil, bpytop, HttpPy, j2cli, wheel, shell-gpt, pyright, cosmic-ray, hypothesis, passlib, scikit-learn, scipy, bandit, pip-audit, ruff, pytest, pytest-cov, pytest-xdist, mypy, pandas, matplotlib, seaborn, ipython, jupyterlab, pre-commit, radon, vulture (+macOS: mlx)
- **ruff is venv-managed** (not brew); run `brew uninstall ruff` once after venv recreate to remove the legacy brew install
- **Test runner:** `pytest` — runs `unittest.TestCase` tests natively; test file contents do not change
- Application installs are kept in alphabetical order
- For shell syntax-only fixes in `setup_env.sh`, validate with both `bash -n setup_env.sh` and `zsh -n setup_env.sh` before commit
- After any change to `.zshrc` or `.zshrc.d/` files, run `zsh -i -c 'exit'` before committing to catch re-source crashes before they reach prod
- **`_UPDATE_SECTION_ORDER` coupling:** `lib/update_summary.sh` has a `readonly _UPDATE_SECTION_ORDER=(...)` array that controls which sections appear in the printed update summary. Adding `_update_record_start/end "new-section"` in `run_update()` without also adding `"new-section"` to this array means the section is tracked internally but never printed. Both must be updated together. When **removing** a section, a `sed` pass on test fixture loops won't catch hardcoded count assertions like `[[ "$output" == *"9 OK"* ]]` — these must be audited and decremented manually.

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
| `HAS_FLATPAK`  | Set for: linux_workstation only (gates Steam flatpak install in `_install_ubuntu_gui_tools`)                              |
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

---
