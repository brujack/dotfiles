# CLAUDE.md — dotfiles

## Repository Overview

Personal development environment bootstrapping system for macOS and Linux (Ubuntu). Manages shell configs, tool installation, and symlink setup across multiple machine types.

## Layout

```
dotfiles/
├── setup_env.sh       # Main entry — sources lib/, dispatches workflows
├── Brewfile           # Homebrew bundle (100+ formulae/casks; [HAS_*] tags are capability-gated)
├── lib/               # Shell libraries: constants, helpers, detect_env, macos, linux_shared,
│                      #   linux_ubuntu, developer, update_summary, workflows, git_hooks
├── config/            # profiles.sh (hostname→profile map); local.sh (machine overrides, git-ignored);
│                      #   hook_repos.sh (expected-repos list for the git-hooks sweep)
├── scripts/           # bootstrap_mac.sh, whats-new-*.sh, run-bash-coverage.sh
├── powershell/        # Windows bootstrap: setup_windows.ps1, Pester tests, Makefile
├── tests/             # BATS tests: setup_env/, zshrc.d/, mocks/, helpers/
├── docs/              # ADRs, knowledge/, superpowers/, claude-code-new-features/,
│                      #   anthropic-new-features/
├── .github/workflows/ # CI: test, lint-macos, bash-coverage, powershell, secret-scan, auto-merge
├── .zshrc, .vimrc, .tmux.conf, .gitconfig_*, starship.toml, bruce.omp.json, profile.ps1
└── ubuntu_*_packages.txt, .ssh/
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

| Type             | Purpose                                                                                                                                                                                                                                                                                                                                                                                                             |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `setup_user`     | Configs, shells, directory structure, symlinks, GitHub MCP (`setup_claude_mcp`), Claude plugins (`setup_claude_plugins`)                                                                                                                                                                                                                                                                                            |
| `setup`          | Full machine setup (setup_user + all apps). Flags: `--brew-install`, `--mas-install`                                                                                                                                                                                                                                                                                                                                |
| `developer`      | Dev packages + Python/Ansible virtualenv                                                                                                                                                                                                                                                                                                                                                                            |
| `ansible`        | Ansible venv setup only (after Python updates)                                                                                                                                                                                                                                                                                                                                                                      |
| `recreate-venv`  | Force-delete and recreate a named pyenv virtualenv. Flags: `--venv-name` (default: `ansible`). Runs full pip install when name is `ansible`.                                                                                                                                                                                                                                                                        |
| `recreate-ruby`  | Force-delete and reinstall the pinned Ruby version (`RUBY_VER` in `lib/constants.sh`), reusing `install_ruby()`.                                                                                                                                                                                                                                                                                                    |
| `update`         | Update all packages (brew, apt/snap, pip, gems, tools). Supports `--brew-only`, `--pip-only`, `--gems-only`, `--mas-only`, `--claude-only` flags. Prints a structured summary; logs to `~/.dotfiles-update.log`. Also writes a state-ledger entry (advisory, non-fatal). Full internals: [`dotfiles-update-workflow`](https://github.com/brujack/ai-config/blob/master/docs/knowledge/dotfiles-update-workflow.md). |
| `doctor`         | Active health checks: symlinks, tool presence, credential dir permissions, version drift, global/system core.hooksPath pins. Exits non-zero on any failure                                                                                                                                                                                                                                                          |
| `check-versions` | Compare pinned versions in `lib/constants.sh` against GitHub latest; exits 1 if outdated. `--update` prompts per-tool to apply updates in-place                                                                                                                                                                                                                                                                     |

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
- **Sourcing guard on every lib file:** All files under `lib/` that are tested must include `[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0` as the **last line, after all function definitions** — not near the top. The guard's condition is true when the file is sourced, so placing it above the function definitions returns before any function exists and breaks standalone sourcing entirely. Precedent: `lib/git_sync.sh:118` and `lib/legacy_rsync.sh:28` are each the final line of their file. When extracting functions into new lib files, add this guard explicitly at the end — plan specs may omit it but the test harness requires it.

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

**Formula/cask dedup rule:** never add both a formula and a cask for the same tool (breaks `brew bundle` symlinking). **Tap trust (Homebrew 6.0):** new third-party taps must also be added to the `brew trust` call in `install_macos_casks`/`_install_ubuntu_brew_packages`. Rationale and detail: [`dotfiles-brewfile-conventions`](https://github.com/brujack/ai-config/blob/master/docs/knowledge/dotfiles-brewfile-conventions.md).

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

Ruby version managers: **rbenv on Linux** (`lib/linux_ubuntu.sh`); **chruby on macOS** (`lib/macos.sh`). Not interchangeable across platforms. Handled automatically by `install_ruby()`/`install_ruby_tools()` in `developer.sh` — no manual intervention required. Linux build pins `RUBY_CONFIGURE_OPTS="--with-openssl-dir=/usr"` to avoid linking against a Homebrew OpenSSL that breaks gem HTTPS. Full rationale: [`dotfiles-ruby-version-manager`](https://github.com/brujack/ai-config/blob/master/docs/knowledge/dotfiles-ruby-version-manager.md).

## Language Standards

Language-specific standards for this repo. These supplement the universal standards loaded
from `~/.claude/CLAUDE.md` (tdd, behavior, git-workflow, ci, code-standards, logic-review,
repo-structure, shell).

@~/.claude/standards/powershell.md

## Testing

Uses **BATS** (Bash Automated Testing System), installed natively:

`install_bats()` in `lib/helpers.sh` is a platform dispatcher (mirrors `install_zsh()`'s shape): `run_setup_user` calls it unconditionally on both macOS and Linux, so bats provisioning is no longer Linux-only.

- macOS: `install_bats_macos()` in `lib/macos.sh` — `brew install bats-core` (also listed in `Brewfile` for `brew bundle` parity)
- Ubuntu: `install_bats_linux()` in `lib/linux_shared.sh` — `sudo apt-get install -y bats`

**Run tests:** `make test` (runs lint then all BATS tests)
**Run unit tests only:** `make test-unit` (runs `unit.bats`, `profiles.bats`, and `zshrc.d/unit.bats`)
**Run lint only:** `make lint` — `bash -n` over `SHELL_FILES` (36 tracked `.sh`/`.bash` files plus the two extensionless hooks `scripts/pre-push` and `scripts/commit-msg`), `zsh -n` over `ZSH_FILES` (the 10 tracked `.zsh`/`.zsh-theme`/`.zshrc`/`.zprofile` files), then shellcheck at default severity for `SHELL_FILES` and `--severity=warning` for `.bats`. Both `SHELL_FILES` and `ZSH_FILES` are derived from `git ls-files` and each refuses to report a pass on an empty list.
**Install hooks:** `make install-hooks` (installs pre-commit and pre-push hooks; run once per checkout)
**Sync agent guidance:** `make sync-agent-guidance` (regenerates `.cursor/rules/global-claude-standards.mdc` from root `CLAUDE.md`'s `@~/.claude/standards/*.md` imports, resolved against the global symlinked standards dir)
**Check agent guidance drift:** `make check-agent-guidance` (fails when generated Cursor guidance is stale)

The pre-commit hook is **required**. It runs on every `git commit`:

1. `make lint` — blocks the commit on any syntax or shellcheck failure
2. `ggshield secret scan pre-commit` — scans staged changes for secrets before they reach the remote; skipped gracefully if ggshield is not installed

The pre-push hook is **permanent**. It runs `make test` (lint + bats) on every push before the push reaches GitHub, and it **fails closed** (ADR-0017, `docs/adr/0017-pre-push-trigger-fail-closed.md`): the suite runs unless every changed path is provably inert, and it also fails closed if `git diff` itself cannot resolve the push's revision range (e.g. `remote_sha` names an object the local checkout lacks) rather than silently reading that as "nothing changed". The inert set is deliberately small — `.md` files, `.yml`/`.yaml` files under `.github/`, and `LICENSE` — and is matched with `grep -qv`, so a single changed path outside that set is enough to trigger the run. `docs/` and `.github/` are **not** wholesale-inert: `make lint`'s `SHELL_FILES` walk is recursive, so a `.sh` file anywhere in the repo — including `docs/gen.sh` or `.github/scripts/foo.sh` — is linted by `make test` and must still trigger the suite. This means `starship.toml`, `.zshrc`, `.gitignore_global`, and `ubuntu_common_packages.txt` all trigger the suite even though none is a `.sh`/`.bats`/`.zsh` file, because none is in the inert set. Skips branch deletions. This conserves GitHub Actions minutes — CI runs only on PRs.

**Worktree compatibility requirement:** `scripts/pre-push` must resolve repo root with `git rev-parse --show-toplevel` first, and use `git rev-parse --git-common-dir` parent only as a fallback. Direct `git-common-dir` resolution can run tests against the shared checkout instead of the active worktree branch.

**Git env strip requirement:** `scripts/pre-push` must `unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE` before invoking `make test`, and that line must stay **below** the range-resolution loop, which legitimately needs the git environment. Git exports `GIT_DIR` into the hook only when the push originates from a worktree; without the strip, every suite that builds a git fixture inherits it and `git -C <fixture>` silently operates on the leaked repo instead — measured at 90 failures, with the local test gate effectively absent for the standard worktree workflow. Covered by `tests/scripts/pre_push.bats` ("clears inherited git repo-location vars"), which fails if the line is removed.

The CI `secret-scan` job (gitleaks) is a backstop, not a substitute for local scanning. Install ggshield: `brew install gitguardian/tap/ggshield && ggshield auth login`.

### ShellCheck

`.shellcheckrc` at the repo root carries **one** suppression, `SC1091`, and the file is byte-identical across the four repos that use the shared minimal config. `etch-cli` layers it beneath its own stricter baseline (`enable=all`, `source-path=SCRIPTDIR`, `disable=SC2154`) — a deliberate per-repo choice, not drift. `SC1091` is structurally unavoidable rather than a preference: the lib architecture resolves source paths at runtime through `$(dirname "${BASH_SOURCE[0]}")`, which does not exist at lint time. Everything else is suppressed at its site with a reason on the same line, or fixed.

**This reverses the previous convention, deliberately.** Until 2026-08-08 the file blanket-disabled `SC2086`, `SC2034`, `SC1091` and `SC2181`, and this section described unquoted variables as "intentional style throughout." All 271 findings behind that blanket were cleared — 206 `SC2086` resolved (194 quoted, 12 retired by deleting `kubernetes_stuff/`), 60 `SC2034` resolved (nine of them by deleting a dead constant — eight in `lib/constants.sh` plus `WINDOWS` in `lib/detect_env.sh`), 4 `SC2181` rewritten, 1 `SC2317`. **That 271 is measured over the set the blanket actually covered — tracked `*.sh` and `*.bash`.** Widening the scope to the two extensionless hooks surfaced 2 further `SC2034` (`local_ref`/`remote_ref` in `scripts/pre-push`, suppressed with the git protocol named), so the figure over the _current_ 36-file scope is 273. Both are true; a finding count without its denominator is not a finding count. A reader who remembers the old rule should know it was reversed on purpose, not eroded.

The blanket was not free. One of the four `SC2181` sites it covered was a real defect: `install_homebrew` ran `xcodebuild -license accept` and `xcodebuild -runFirstLaunch` back to back and then tested `$?`, so a license failure followed by a successful second command was reported as success. The suppression's own comment called that pattern intentional.

Rules for any new suppression:

- **Every `# shellcheck disable=` carries a reason on the same line**, and the reason names the mechanism — for `SC2034`, the file and function that consume the variable, not "used elsewhere."
- **Prefer deleting to suppressing.** A variable nothing reads is dead code; annotating it makes it permanent.
- **Verify the directive is live before writing its reason.** Delete it, re-run shellcheck, and confirm its finding returns. A reason attached to a directive that cannot fire is worse than a bare one, because it stops the next reader checking. Two such shipped on this branch before the check became routine.
- **A bare directive before the first non-comment command in a file is file-wide**, not scoped to the next command — verified against shellcheck 0.11.0. `lib/constants.sh` and `config/profiles.sh` use that deliberately and say so; anywhere else it is a footgun, because a directive added at the top of a file to silence one line silences the rule everywhere.
- **shellcheck rejects a directive on a `case`-arm line** (`SC1124`). It must precede the whole `case`, which means it covers every arm — state the blast radius when you write one.

`make lint`'s scope comes from `git ls-files`, not a literal list and not `find`. That covers all 36 tracked shell files including the two extensionless hooks (`scripts/pre-push`, `scripts/commit-msg`) and excludes both untracked scratch files and the copies inside any linked worktree.

### CI / GitHub Actions

`.github/workflows/ci.yml` runs on PRs to master only (the pre-push hook gates branch pushes locally):

- `test` job: installs a pinned, checksum-verified shellcheck plus bats, runs `make test`, then verifies test count ≥ 840 (regression proxy; 1294 tests, CI-measured 2026-08-12)
- `lint-macos` job: runs on `macos-latest` (advisory, not blocking auto-merge), two independent steps: `bash -n` over every `*.sh` file found via `find` (unchanged), and `zsh -n` over the 10 tracked zsh files selected via `git ls-files '*.zsh' '*.zsh-theme' '.zshrc' '.zprofile'` — this second step refuses to pass on an empty file list
- `bash-coverage` job: measures bash line coverage via PS4 xtrace on `ubuntu-latest`; **gates at 91%** — blocks auto-merge if coverage drops below floor
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

- **Overall: 91%** (3107/3390 commands, 1294 tests) as measured by CI on `ubuntu-latest` for `f2b10cd` — the figure the gate actually reads. The same commit measures **92% (3122/3388)** on macOS: 15 covered lines more and 2 coverable fewer. The platform gap has held at one percentage point across every commit measured both ways, and the 15/2 split now reproduces exactly — it was 11/2 on 2026-08-09 and 15/2 on 2026-08-10, so the point is the stable part and the ratio is not; re-read it, never carry it forward. **This entry is what a reconciled figure looks like.** The 92% was written here first as an explicitly-labelled local preview with "do not publish until CI measures it" attached, and CI then returned 91% — the preview was one point high, exactly as the caveat predicted. Label a local number as a preview and it costs nothing when it turns out wrong; publish it as the headline and the repo carries a figure no gate agrees with. Publish the CI figure; treat a local number as a preview. Coverage is over **34 of the 35 files the predicate matches**; the 36th tracked shell file, `tests/helpers/common.bash`, is a test helper and outside the predicate. Gated in CI at **91%**, one point below the measurement (`bash-coverage` job, blocks auto-merge on drop). A percentage without its denominator is not a coverage figure — report both.
- **The instrumented set is `setup_env.sh` plus tracked `config/*.sh`, `lib/*.sh`, `scripts/*.sh` and the two extensionless hooks (`scripts/pre-push`, `scripts/commit-msg`), derived from `git ls-files` at run time, less `scripts/bash-tracer.sh`.** It was a 13-entry literal array until 2026-08-07, covering 13 of 36 tracked `.sh` files, so the previously published 91% was computed over 36% of the repo. An omitted file left the percentage unchanged rather than lowering it, which is why nothing surfaced it. The predicate is _reached by the suite_, not _lives in a particular directory_ — `lib/detect_env.sh` sources `config/profiles.sh` and `lib/git_hooks.sh` sources `config/hook_repos.sh`. Check what is measured:
  ```bash
  bash scripts/run-bash-coverage.sh --list-sources
  ```
- **`scripts/` was outside the set until 2026-08-09, and the stated reason for that was wrong.** This bullet used to read "nothing under test sources them, so instrumenting them would add only zeros to the denominator." Measured 2026-08-08: all 19 tracked files under `scripts/` are executed by the bats suite, between 2 and 29 times each — `whats-new-anthropic.sh` 29, `bootstrap_linux.sh` and `sync-agent-guidance.sh` 15 apiece. The tracer enables tracing through `BASH_ENV`, which non-interactive bash subprocesses inherit, so their trace lines were already being collected and then discarded by a predicate that globbed only `config/` and `lib/`. The exclusion was asserted, never measured. The predicate has since widened to include `scripts/`, which is why the instrumented set now reads 34 of the 35 files the predicate matches, rather than 16 — this history is kept here as the record of what the wrong claim cost, not as a live caveat.
- **`scripts/bash-tracer.sh` is the sole remaining exclusion, and it is measured rather than asserted.** `set -x` is its last command, so nothing before it can be traced and nothing follows it to trace. A real run against it attributes zero trace lines to the file — verified directly:
  ```bash
  _COV_TRACE_FILE=$PWD/tr.txt BASH_ENV=scripts/bash-tracer.sh bash -c 'x=1; y=2'
  grep -c 'bash-tracer.sh' tr.txt   # -> 0
  ```
- **`git ls-files` rather than a filesystem glob is load-bearing, not stylistic.** `config/local.sh` is machine-local and git-ignored, but it exists on developer machines and not on a CI runner — a glob would put it in the denominator locally and leave it out in CI, so the same commit would measure two different sets. Deriving from the tracked set makes local and CI agree by construction rather than by coincidence.
- **The denominator counts commands, not source lines.** bash xtrace emits one line per _command_, so any construct where one command spans several lines inflates the count with lines no test can ever reach. Four classes are excluded, each verified against real `bash -x` output rather than assumed:
  - **Heredoc bodies and terminators, in any form** — `<<` and `<<-`, any interpreter (not just bash's own `usage()` blocks) — because a heredoc body can contain arbitrary text, including lines that would otherwise parse as commands, comments, or continuations of their own.
  - **Multi-line `python3 -c "..."` bodies** — 54 of `lib/package_capture.sh`'s 107 counted lines. It reported 22% against a ceiling it could not reach; it now reads 45% of 53 real bash lines.
  - **Multi-line array literals** — `declare -A M=(\n [a]=1\n)` traces as a single `M=([a]=1)`. That was 13 of `config/profiles.sh`'s 15 lines and 8 of `lib/helpers.sh`'s.
  - **Pure-argument backslash continuations** — a continuation line whose only content is more arguments to the command the backslash opened. A continuation that itself begins or contains `||`, `&&`, `|`, or `;` is **not** excluded, because bash starts tracing a new command at that point regardless of the backslash — it is counted like any other command.

  Single-line forms of all four still count.

- **A function-declaration exclusion was tried and removed on evidence, not preference.** The heuristic once dropped lines like `detect_env() {` from the coverable count on the theory that bash doesn't consistently trace them. A real tracer run over the bats suite showed the opposite for roughly 150 instances: `lib/detect_env.sh` line 4 was traced twice, once for the source and once when a caller re-sources it under an already-active `set -x`. The rule was deleted outright rather than narrowed, because the mechanism it assumed was wrong, not just its scope.
- **The denominator is the union of the static heuristic's coverable-line count and whatever the trace file actually contains for that file, never the heuristic alone.** This is what makes `covered <= coverable` hold by construction rather than by luck — every traced line is by definition a member of the union, so it can never exceed it. A wrongly-excluded line therefore raises the denominator (and the numerator, since the trace hit it) rather than silently lowering the percentage; an over-matching exclusion rule can never manufacture a higher score. Each run prints every union-added line as a **heuristic disagreement** — the heuristic said not-coverable, the trace disagreed — so a systematically wrong exclusion rule stays visible instead of being absorbed into a bigger denominator. The current CI run reports 17, down from 192 before the heredoc/continuation rules landed; a non-zero count is a to-do against the heuristic, not a failure of the gate. It rose from 15 when `ZSH_FILES` split the lint scope — widening what the suite executes surfaces more traced lines, so this count moves with coverage and is not a fixed target.
- **`covered > coverable` is now a hard, loud non-zero exit — replacing a silent clamp that had been hiding real over-matches.** Before the union approach, `lib/detect_env.sh` read 24/24 = 100% while the trace actually emitted 25 distinct lines for it; the clamp absorbed the discrepancy instead of surfacing it. Under the union rule that discrepancy cannot occur by construction, so a `covered > coverable` result now means an exclusion heuristic double-counted or otherwise over-matched, and the run fails rather than reports a number nobody can trust.

  Inspect one file's denominator, or a full run's coverage against a real trace, without waiting on the bats suite:

  ```bash
  bash scripts/run-bash-coverage.sh --list-sources
  bash scripts/run-bash-coverage.sh --count-coverable lib/package_capture.sh
  bash scripts/run-bash-coverage.sh --file-coverage lib/package_capture.sh /path/to/trace
  ```

- `make bash-coverage` measures via PS4 xtrace (`scripts/run-bash-coverage.sh`); `make push-bash-coverage` pushes `coverage/bash.json` to the `coverage-data` branch for the README badge.
- Method detail, per-file floors/ceilings, and why kcov/bashcov are ruled out: [`dotfiles-bash-coverage`](https://github.com/brujack/ai-config/blob/master/docs/knowledge/dotfiles-bash-coverage.md).

### Test Seams

See [`ai-config/docs/knowledge/dotfiles-bats-test-infrastructure.md`](https://github.com/brujack/ai-config/blob/master/docs/knowledge/dotfiles-bats-test-infrastructure.md) for the full override env var table (moved to ai-config per ADR-0020).

Pattern: `local _file="${_OVERRIDE_VAR:-$(dirname "${BASH_SOURCE[0]}")/real/path}"`. Tests set the var and pass a writable temp copy; production code leaves it unset.

### Mock Pattern

See [`ai-config/docs/knowledge/dotfiles-bats-test-infrastructure.md`](https://github.com/brujack/ai-config/blob/master/docs/knowledge/dotfiles-bats-test-infrastructure.md) for the full `MOCK_*` env var reference table and the usage pattern.

**Pass-through mocks:** `ln`, `chmod`, `mv`, `cp`, and `tee` call the real binary (`/bin/cmd "$@" 2>/dev/null || true`) so tests that assert actual filesystem state work correctly. Set the corresponding exit var to a non-zero value to simulate failure instead.

**`env -i` subprocess strips PATH** — `setup_ansible()`'s pyenv calls need the mock placed at `${HOME}/.pyenv/bin/pyenv`, not PATH-injected. Detail and doctor-test conventions (`_DOCTOR_FAIL` vs `_DOCTOR_FAILED`, `log_warn` vs `doctor_warn`, PATH isolation): [`dotfiles-bats-test-infrastructure`](https://github.com/brujack/ai-config/blob/master/docs/knowledge/dotfiles-bats-test-infrastructure.md).

### MAKEFLAGS and Stdout Partition

`Makefile:1` carries `MAKEFLAGS += --no-print-directory`. GNU Make 4.0+ prints `Entering directory` / `Leaving directory` on stdout when `-C` changes directory; macOS's `/usr/bin/make` is 3.81 and does not. The directive removes that variance at the source, covering all `make` invocations in the repo without explicit per-call flags.

**`MAKEFLAGS` is an exported environment variable, not a file-local Makefile directive.** Every `make` a test spawns inherits it. So any test that captures and measures `make` output must explicitly account for it — tests fall into two categories:

- **Guarded:** Per-call `--no-print-directory` flag (overrides the exported `MAKEFLAGS`), for tests that care about exact output shape
- **Measuring:** `env -u MAKEFLAGS` prefix (strips the inherited directive), for tests that measure baseline behavior or verify the directive works

Both categories must exist in the test suite. A test capturing `make` output without guarding or measuring it gets the environment's `MAKEFLAGS`, so it is measuring the environment rather than the Makefile.

**The partition is enforced, not aspirational.** `tests/scripts/makefile_lint_scope.bats:596` ("every stdout-capturing make -C invocation in-domain is guarded or measuring, both sets nonempty") scans every stdout-capturing `make` invocation across the scanner's domain and requires each to land in exactly one of guarded/measuring, with both sets non-empty.

**The domain is derived from `git ls-files`, not listed.** The scanner pulls its file set through `_git_ls_clean 'tests/*.bats' 'tests/*.bash'` — the same four-variable `env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE` strip `ZSH_FILES`/`SHELL_FILES` use, and for the identical reason: `git -C` does not override an exported `GIT_DIR`, and `scripts/pre-push` runs `make test`. An earlier version hardcoded a two-file array (`tests/makefile_scope.bats` and this file) that held exactly the two files already in compliance and excluded the one real violation, `tests/scripts/unit.bats:819` (`make -C "${REPO_ROOT}" -n test-python`, carrying neither guard). That is the same invisible-omission shape `tdd.md`'s Coverage Denominators section describes — an excluded file is absent from both numerator and denominator, so the check reports clean either way — and the third time that shape has shown up in this repo, after the bash coverage tracer's 13-entry `INCLUDE_FILES` array and `make lint`'s original literal file list (both above, under Coverage and ShellCheck).

**Known gap: recursive sub-make and `-w` are invisible to it.** A line scanner can only see what is on the invoking line. `$(MAKE)` recursion and `-w`/`--print-directory` both print `Entering`/`Leaving` with no `-C` anywhere on the line that triggers them, so neither is reachable by this scanner's `-C`/`--directory` pattern. Not exploitable today — the root `Makefile` has zero `$(MAKE)` recipes and `make -n test` emits no sub-make — but `powershell/Makefile` exists and sits outside this scanner's domain entirely. Recorded as an accepted boundary a line scanner cannot close, not a defect to fix.

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
- For shell syntax-only fixes, validate with `bash -n <file>` for `.sh`/`.bash` files and the two extensionless hooks, or `zsh -n <file>` for `.zsh`/`.zsh-theme`/`.zshrc`/`.zprofile` files — `make lint` runs both checks over their respective `SHELL_FILES`/`ZSH_FILES` sets before commit
- After any change to `.zshrc` or `.zshrc.d/` files, run `zsh -i -c 'exit'` before committing to catch re-source crashes before they reach prod
- **`_UPDATE_SECTION_ORDER` coupling:** `lib/update_summary.sh` has a `readonly _UPDATE_SECTION_ORDER=(...)` array that controls which sections appear in the printed update summary. Adding `_update_record_start/end "new-section"` in `run_update()` without also adding `"new-section"` to this array means the section is tracked internally but never printed. Both must be updated together. When **removing** a section, a `sed` pass on test fixture loops won't catch hardcoded count assertions like `[[ "$output" == *"9 OK"* ]]` — these must be audited and decremented manually.
- **`scripts/sync_git_repos.sh`** replaces the old rsync-only sync script (`scripts/synch_git-repos.sh`, deleted). Two independent modes: git-native fetch/pull/push for `personal/` repos + `state-ledger` (safe on any of the three dev machines — never force-pushes, never auto-merges a diverged repo; dirty does not block a safe push, only a pull), and studio-only rsync push for legacy/no-git-access directories + a full-tree ratna backup. Runs automatically as part of `-t update` (`git-repos`/`legacy-rsync` sections in `_UPDATE_SECTION_ORDER`); `--git-only`/`--legacy-only`/`-h` for standalone use. See `docs/superpowers/specs/2026-07-18-sync-git-repos-design.md` for the full design and the dirty/ahead/behind decision table. **Never invoke this script (or `sync_legacy_dirs`/`sync_git_repos` directly) unmocked outside the BATS test harness** — it performs real `git push`/`rsync --delete` over SSH against real hosts, and `_is_legacy_sync_host` triggers on the real `hostname -s` of whichever machine runs it.
- **`git-hooks` section coupling:** same `_UPDATE_SECTION_ORDER` trap applies to the hook-install sweep (`lib/git_hooks.sh`) — adding `_update_record_start/end "git-hooks"` in `run_update()` without also adding `"git-hooks"` to `_UPDATE_SECTION_ORDER` means the section is tracked internally but never printed, with no error. Separately: the sweep's post-condition check reads the **installed hooks directory** (`.git/hooks/` or the repo's actual hook path), never `scripts/` — a repo whose hooks were installed by a route other than the Makefile (e.g. `ledger init`) must still read as satisfied. `install_git_hooks_all_repos` returns 0 clean, 1 when a `make install-hooks` call failed, and 2 for partial success — gaps, unreadable hooks, or a `core.hooksPath` pinned at global/system scope. **Both** call sites must branch on it: `run_update` maps 2→0 for `_update_record_end` then calls `_update_warn` (the same shape `git-repos` and `legacy-rsync` use), and `run_setup_user` distinguishes rc 1 ("reported failures") from rc 2 ("gaps or a pinned core.hooksPath") rather than treating any non-zero as failure. Without the `run_update` mapping the section renders `[OK] git-hooks updated` over its own findings.
- **`.warp/settings.toml` is Warp-owned and symlinked live** (`~/.warp/settings.toml` → repo, via `safe_link` in `lib/helpers.sh`). Warp rewrites it on upgrade — an unexplained diff there is usually a materialized default, not a hand edit. One value in it is a **deliberate non-default, not drift**: `agents.warp_agent.other.auto_approve_bypasses_command_denylist = false` (Warp defaults it to `true`, which makes the `execution_profiles` `command_denylist` inert whenever auto-approve is on — `permissions.rs` then consults only the org denylist, and a personal machine has no org). That key carries `sync_to_cloud: Globally`, so a fleet machine still holding `true` can push it back and Warp will rewrite the file; treat a diff flipping it to `true` as a sync reversion to re-pin, never as an upgrade artifact to accept.
- **A global/system `core.hooksPath` pin redirects every repo's hooks at once:** `git rev-parse --git-path hooks` honors `core.hooksPath`, so a single global/system pin redirects **every** repo's hooks directory, not just one. The sweep therefore folds the resulting per-repo "no hooks directory" gaps into one aggregated line attributed to the pin, rather than reporting each repo as individually broken with an `install-hooks` remedy that cannot fix it. An **empty or whitespace-only** value is a real pin, not an absent one: `git config --get` reports it as rc 0 with empty stdout, and git honors it — it disables every hook on the machine. Both the doctor check and the sweep summary render it as `(empty)`. `tests/setup_env/git_hooks.bats`'s `setup()` must neutralize `GIT_CONFIG_GLOBAL`/`GIT_CONFIG_SYSTEM`, because the sweep now reads them — without it the suite fails on any machine that actually has a pin, and since `scripts/pre-push` runs `make test`, that developer cannot push.

- **The pin probe must read `--includes`, and the remedy must name the origin file:** `git config --<scope> --get` defaults to `--no-includes`, but git's own hook resolution traverses includes. A pin reached through an `[include]` therefore answered rc 1 with **empty stderr** — byte-identical to a genuinely unset key — while `rev-parse --git-path hooks` returned the pinned path and every repo on the box was silently redirected; both surfaces rendered `[PASS] <scope>: unset` over a live machine-wide redirect. `_git_hooks_hookspath_offenders` now re-reads any apparently-clean scope with `git config --<scope> --includes -z --show-origin --get`. `-z` is required rather than the default tab-separated `--show-origin` format (the value may be empty or whitespace-only, and NUL is the only delimiter git will not also emit inside a value), and because command substitution silently drops NUL bytes the pair must be consumed with `read -d ''` off a process substitution, never `$(...)`. The remedy differs by origin: a scope-level `--unset` **cannot** clear a key held in an included file — it exits 5 and the pin survives — so the function emits `git config --file <origin> --unset core.hooksPath` for that case and keeps the scope form only for a key in the scope's own file. Output contract is `scope<TAB>remedy<TAB>value`, with value last so a tab inside a pinned path cannot truncate the command the operator is told to run. Remaining limit: a conditional `includeIf "gitdir:…"` is visible only when git evaluates it from a matching directory, and the probe runs once per sweep rather than once per discovered repo.

- **Homebrew `make` gnubin prepend:** `.config/.zshrc.d/6_path.zsh` prepends the Homebrew `make` formula's `gnubin` directory on macOS, so plain `make` resolves to GNU 4.x instead of `/usr/bin/make` 3.81. **It must be a prepend, not `path+=`.** This file's existing idiom is append-via-`+=`, which leaves `/usr/bin` ahead of anything it adds — an append here would be completely inert and would still look correct to a reader. Both Homebrew prefixes are tested for existence (ARM at `/opt/homebrew/opt/make/libexec/gnubin` and Intel at `/usr/local/opt/make/libexec/gnubin`); the invocation never calls `brew --prefix` because this same file is what puts `/opt/homebrew/bin` on `PATH`, so `brew` is not guaranteed resolvable at that point.

## Local-Only State

The following paths are machine-local and must **never** be committed to this repo:

- `~/.aws/` — AWS credentials and config
- `~/.tf_creds/` — Terraform cloud credentials
- `~/.ssh/` private keys — only `config` and `teleport.cfg` are tracked in `.ssh/` in the repo
- `~/.azure_creds/` — Azure credentials
- `~/.gcloud_creds/` — GCloud credentials
- `~/.tsh/` — Teleport session tokens
- `~/.claude/projects/<path>/` — conversation history **and** per-project memory. Nothing here is committed. Per ai-config ADR-0014 the `memory/` subdirectory is a session-local draft location; canonical memory lives at `ai-config/.claude/memory/<repo>-<topic>.md`, and ai-config's `validate_memory.py` fails `make test` on any draft left behind. The one tracked exception is ai-config's own `<encoded>/memory` symlink to the canonical corpus. An earlier version of this line claimed the memory subdirectories were tracked; that was wrong, and it had produced 27 committed drafts before ai-config#138 asserted the invariant
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
