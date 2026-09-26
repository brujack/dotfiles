# CLAUDE.md — dotfiles

A trailing `` → `file` § `heading` `` on a rule means: before acting on that rule's subject, read `ai-config/docs/knowledge/<file>` at that heading for the incident history and measurements.

## Repository Overview

Personal development environment bootstrapping system for macOS and Linux (Ubuntu). Manages shell configs, tool installation, and symlink setup across multiple machine types.

## Layout

```
dotfiles/
├── setup_env.sh       # Main entry — sources lib/, dispatches workflows
├── Brewfile           # Homebrew bundle (100+ formulae/casks; [HAS_*] tags are capability-gated)
├── lib/               # Shell libraries — all 13 tracked: constants, detect_env, developer,
│                      #   git_hooks, git_sync, helpers, launch_agents, legacy_rsync,
│                      #   linux_shared, linux_ubuntu, macos,
│                      #   update_summary, workflows
├── config/            # profiles.sh (hostname→profile map, bash); profiles.zsh (the zsh-side
│                      #   derivation of the same table); local.sh (machine overrides,
│                      #   git-ignored; local.sh.example is tracked);
│                      #   hook_repos.sh (expected-repos list for the git-hooks sweep)
├── scripts/           # bootstrap_{mac,linux}.sh, whats-new-*.sh, run-bash-coverage.sh,
│                      #   bash-tracer.sh, cadence-notify.sh, sync-requirements-ci.sh,
│                      #   sync-agent-guidance.sh, list-shell-files.sh, phrase_check.py,
│                      #   check-lib-exit-traps.sh, sync_git_repos.sh,
│                      #   and the extensionless hooks pre-commit-hook.sh/pre-push/commit-msg
├── LaunchAgents/      # cadence.plist.template — one template, both weekly agents
├── keys/              # aws-cli-team.asc — vendored AWS signing key (_AWS_KEY_PATH default)
├── manifests/         # manifests/dotfiles/*.yaml — state-ledger entity manifests
├── powershell/        # Windows bootstrap: setup_windows.ps1, Pester tests, Makefile
├── pyenv.d/           # rehash/dotfiles-register-all-executables.bash — installed as a
│                      #   copy into ${PYENV_ROOT}/pyenv.d/rehash/, never symlinked
├── tests/             # BATS tests: setup_env/, zshrc.d/, scripts/, mocks/, helpers/
├── docs/              # adr/, knowledge/, superpowers/, cursor/,
│                      #   claude-code-new-features/, anthropic-new-features/
├── .config/           # .zshrc.d/{1_init..7_final}.zsh; ccstatusline/settings.json
├── .github/workflows/ # CI: test, lint-macos, bash-coverage, powershell, secret-scan, auto-merge
├── .claude/           # settings.json, scripts/triage_log.py (the standards live at
│                      #   ~/.claude/standards/, symlinked from ai-config — not tracked here)
├── .warp/             # settings.toml (Warp-owned, symlinked live), themes/, launch_configurations/
├── .vscode/           # settings.json
├── .ssh/              # config, teleport.cfg only — never private keys
├── .zshrc, .zprofile, .vimrc, .tmux.conf, .gitconfig_*, starship.toml, bruce.omp.json,
│                      #   bruce.zsh-theme, profile.ps1, Vagrantfile, etch.yaml, cliff.toml
├── pyproject.toml, uv.lock, requirements-*.txt   # the five CI renderings; see Testing
└── ubuntu_*_packages.txt, Brewfile.gui, Brewfile.devtools
```

The tree is **exhaustive at the top level** — every tracked top-level directory appears — and
illustrative within a directory except `lib/`, which is complete. Regenerate with
`git ls-files | awk -F/ 'NF>1{print $1}' | sort -u` rather than by memory.

## 10-80-10 Execution Cycle

Sessions in this repo follow the 10-80-10 execution cycle defined in `ai-config` ADR-0009 (with the ADR-0010 wave-dispatch extension):

- **Phase 1 (10%) — Architect.** `brainstorming` → `writing-plans` (emit per-task YAML `yaml-task` blocks with `role`/`model`/`tdd`/`acceptance`/`max_retries`/`files_touched`/`depends_on`/`parallel_group`). Opus role.
- **Phase 2 (80%) — Execute.** `subagent-driven-development` runs iterate-until-green per task; FORBIDDEN list prevents gate cheating; wave-dispatch when `parallel_group` is declared. Sonnet/Haiku per task per the plan.
- **Phase 3 (10%) — Review.** `finishing-a-development-branch` runs the twelve-step gate chain in its own Phase 3 table — `perf-regression` first, `pr-review` second-to-last, the merge/PR step last. Read the order there rather than here. Opus role.

Validate a plan before dispatch:

```bash
make validate-plan PLAN=docs/superpowers/plans/<file>.md
```

The validator (`~/.claude/scripts/validate-plan.py`, shared from ai-config) enforces required fields, valid role/model/tdd values, haiku scope guard, and disjoint `files_touched` within each `parallel_group`.

## Knowledge Directory

Reference material for this repo lives in `ai-config/docs/knowledge/` under `dotfiles-<topic>.md` naming (per ADR-0020). The local `docs/knowledge/README.md` is a pointer stub.

When web research (web-research skill) or context-mode fetches produce findings worth preserving, save to `ai-config/docs/knowledge/dotfiles-<topic>.md`.

## Entry Points

```bash
./setup_env.sh -t <type>
```

- `setup_user` — Configs, shells, directory structure, symlinks, GNU make on macOS (`install_make_macos`), GitHub MCP (`setup_claude_mcp`), Claude plugins (`provision_claude_plugins`, wrapping `setup_claude_plugins`). The manifest — which marketplaces to register, which plugins to install — comes from ai-config's `~/.claude/settings.json` (`extraKnownMarketplaces`, `enabledPlugins`), never a hardcoded list: marketplaces are registered first (`claude plugins marketplace add`), then every declared plugin whose value is `true` is installed at user scope (`claude plugins install -s user`). A partial result — one failed install, an unsupported marketplace source — warns and `run_setup_user` continues; only an unreadable or unparsable settings file, or a missing `python3`, aborts the run. See ADR-0034 and the Test Seams entry below for `_OVERRIDE_CLAUDE_SETTINGS`.
- `setup` — Full machine setup (setup_user + all apps). Flags: `--brew-install`, `--mas-install`
- `developer` — Dev packages + Python/Ansible virtualenv
- `ansible` — Ansible venv setup only (after Python updates)
- `recreate-venv` — Force-delete and recreate a named pyenv virtualenv. Flags: `--venv-name` (default: `ansible`). Runs full pip install when name is `ansible`. **SIGINT/SIGTERM during the rebuild now abort the shell** instead of continuing to a verification error — either way the toolchain is left deleted, since the signal reaches the rebuild child regardless of the trap change. Recover with the same command; if the original invocation carried `--venv-name`, repeat it — a bare re-run rebuilds `ansible` instead, because `recreate_python_venv` gates the `uv sync` on that name.
- `recreate-ruby` — Force-delete and reinstall the pinned Ruby version (`RUBY_VER` in `lib/constants.sh`), reusing `install_ruby()`. **SIGINT/SIGTERM during the rebuild now abort the shell** instead of continuing to `install_ruby()`'s post-install verification error — either way the toolchain is left deleted. Recover by re-running the same command.
- `update` — Update all packages (brew, apt/snap, pip, gems, tools). Supports `--brew-only`, `--pip-only`, `--gems-only`, `--mas-only`, `--claude-only` flags. Prints a structured summary; logs to `~/.dotfiles-update.log`. Also writes a state-ledger entry (advisory, non-fatal; skipped under `--dry-run`). **Exits 1 when any section reports FAIL**; a WARN section still exits 0, preserving the deliberate rc-2 -> 0 mapping in `git-repos`, `legacy-rsync`, `git-hooks` and `cargo-tools`. `pyenv-shims` uses the same record-then-overwrite shape — `_update_record_end "pyenv-shims" 0` unconditionally, then `_update_warn` decides afterwards from the rehash and missing-shim results — and `lib/update_summary.sh`'s header comment on `_update_warn` describes both shapes. It deliberately names no sections: a hand-kept list went stale the first time a section was added without it (`plugin-node`, #288), so `git grep -n '_update_warn ' lib/` is the list. **SIGINT/SIGTERM now abort the run** rather than being absorbed by `_dotfiles_run_tmpdir_setup`'s former EXIT/INT/TERM trap (deleted). Non-zero has three meanings and only the first records anything — section FAIL, a run-dir creation failure, or an interrupt; see ADR-0027. The five `cd` guards ADR-0027 named as a fourth, recordless case are gone as of 2026-09-01 — see the `zsh-autosuggestions` bullet below. **The `ai-config` section now runs immediately before `claude` in `_UPDATE_SECTION_ORDER`, and only for a full run** (`_run_all`, never `--claude-only`), so the plugin reconcile reads the `settings.json` this same run just pulled rather than a stale copy. `--claude-only` skips the `ai-config` pull and reconciles against whatever the current checkout already has on disk. The `claude` section itself: reconcile (`setup_claude_plugins`, adds missing marketplaces, installs missing enabled plugins), then re-list installed plugins and run `claude plugins update <id>` for every declared id actually installed at user scope — including a `false` one, since update is unfiltered by the enabled flag. A reconcile rc 1 (unreadable settings) or a failed re-list skips the update loop and FAILs the section, naming the reason, rather than updating nothing and reporting OK; a reconcile rc 2 alone WARNs, and any individual `update` failure FAILs the section. Full internals: `~/git-repos/personal/ai-config/docs/knowledge/dotfiles-update-workflow.md`.
- `doctor` — Active health checks: identity-table load, symlinks, tool presence, credential dir permissions, version drift, global/system core.hooksPath pins, Claude plugin configs pinning a deleted Homebrew node, weekly-cadence heartbeats (Studio only). Exits non-zero on any failure
- `check-versions` — Compare pinned versions in `lib/constants.sh` against GitHub latest; exits 1 if outdated. `--update` prompts per-tool to apply updates in-place

**Options:**

- `--dry-run` — guarantees **no outbound write**: no `git push`, no `rsync --delete`, no state-ledger **entry** write. Nothing this flag covers mutates state on another machine. **It is not an offline mode, and the earlier wording here ("no operation that leaves this machine") was false** — reads still leave: `_git_repo_status` runs `git fetch` against every personal repo's remote and authenticates with your SSH key, `pull --ff-only` fast-forwards any clean repo that is behind, and package upgrades, venv rebuilds, the five `npm install -g` calls and `uv sync` all reach their registries. **"Entry" is load-bearing and was added after `bug-scan` measured the gap:** `ensure_state_ledger` (`lib/workflows.sh:923-941`) is called ungated from `_dotfiles_run_tmpdir_setup:123` by every entry point, so a dry run still does `git pull --ff-only`, `git clone`, `ledger.py init`, and an `rm -rf` of the directory when it exists but is not a valid repo. Its bash body carries no `push`, but that grep cannot see the `ledger.py init` subprocess it spawns — the guarantee holds because `cmd_init` (`ledger.py:372-436`) reaches none of that script's four push sites (`:486`, `:668`, `:791`, `:850`). It is still a local state-ledger write, so the unqualified "no state-ledger write" claimed more than the code delivers. Truthiness: `DRY_RUN=0`, `false`, `no`, empty, and unset all mean dry-run is off; any other value means on; an explicit `--dry-run` flag wins over an inherited falsy `DRY_RUN`.

## Symlink Strategy

Dotfiles live at the repo root and in the ai-config repo (`.claude/`/`.cursor/`). `setup_env.sh` creates symlinks from `$HOME` into the repos:

- **Repo root** — each dotfile symlinked individually into `$HOME` (e.g. `~/.zshrc → dotfiles/.zshrc`)
- **`.claude/`** — each item symlinked individually into `~/.claude/` from the ai-config repo, except `rules/`, which is never linked, and `projects/`, which the loop skips and then links explicitly (see below).
  Exception: `mcp.json.template` is symlinked as `~/.claude/mcp.json.template` (read-only reference).

  **The live `~/.claude/mcp.json` is ALSO a symlink, and template generation is unreachable — this line
  claimed the opposite until 2026-09-14.** The loop above links every item in `ai-config/.claude/` except
  `projects` and `rules`, and `mcp.json` is tracked there, so it is linked by `setup_dotfile_symlinks`
  (`lib/workflows.sh:157`). `setup_claude_mcp` runs afterwards at `:188`, finds a valid symlink, and returns 0
  with two WARN lines rather than writing credentials into a tracked file (`lib/workflows.sh:32`). The ordering
  makes that every run on every machine, not a race. Verified on the Studio 2026-09-14: the live file resolves
  into `ai-config/.claude/mcp.json`, and that tracked target holds 1 `mcpServers`
  key, 0 credential-shaped strings and 0 unexpanded `$GITHUB_PAT` placeholders — so the guard is working and
  nothing has leaked. **`-t doctor` cannot verify this**: `_doctor_check_github_mcp` reports
  `[PASS] ~/.claude/mcp.json (generated)` (`lib/helpers.sh:757`) for a path it only tested for existence, so
  the word "generated" asserts a mechanism that never ran. Read the GitHub MCP section below with that in mind.
  `rules/` is never linked because a `~/.claude/rules` pointing into ai-config would load ai-config's project rules as user-level rules in every repo: rules without `paths:` load at launch, and how user-level rules with `paths:` behave is unmeasured.

  **`projects/` IS symlinked, wholesale, and this line said the opposite until 2026-08-25.**
  The loop skips it — `[[ "$(basename "${_claude_item}")" == "projects" ]] && continue` — and the
  very next statement is `safe_link "${_ai_config_dir}/.claude/projects" "${HOME}/.claude/projects"`.
  So "each item **except** `projects/`" is true of the _loop_ and false of the _outcome_, and the
  bullet above is worded for the mechanism while readers take it for the result. Verified on disk,
  not from the code: `readlink ~/.claude/projects` →
  `/Users/bruce/git-repos/personal/ai-config/.claude/projects`.

  **The consequence is not local and it has bitten three sessions.** Anything written under
  `~/.claude/` is physically inside **ai-config's working tree** — including
  `~/.claude/projects/<encoded-repo>/memory/`, whose name suggests per-repo scratch space. That
  path is inside ai-config's `make test` scope, where `validate-memory` is a `test` prerequisite,
  so a draft one session treats as private is a hard-failing gate for every session trying to
  commit to ai-config. Measured 2026-08-25: three promoted-but-undeleted drafts there blocked
  commits for two other sessions. Before writing scratch state under `~/.claude/`, note that you
  are writing into another repo.

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
- **`setup_env.sh` prereq bypass tests — assert absence, not `status -eq 0`:** Tests for `-t doctor` and `-t check-versions` bypass paths (in `tests/setup_env/unit.bats`) assert `[[ "$output" != *"Homebrew not found"* ]]` without asserting `[ "$status" -eq 0 ]`. Reason: all three take the **same** bypass — `setup_env.sh:13` for `-t doctor`/`-t check-versions` and `:16` for `--brew-install` both set `_REQUIRES_BREW_PREREQ=0` — but `--brew-install` then reaches `setup_env.sh:94`'s `exit 0`, while `-t doctor` / `-t check-versions` call `run_doctor` / `run_check_versions` whose exit varies with mock environment. (The only `exit 0` paths are `:94` and `:103`.) Adding `status -eq 0` to the doctor/check-versions tests causes flaky failures.
- **No `set -euo pipefail`** at top-level — conditional installs require non-zero exits to continue.
- **Sourcing guard placement in `lib/`:** where a file carries `[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0`, it goes on the **last line, after all function definitions** — not near the top. The guard's condition is true when the file is sourced, so placing it above the function definitions returns before any function exists and breaks standalone sourcing entirely. Precedent: `lib/git_sync.sh:118` and `lib/legacy_rsync.sh:34` are each the final line of their file. **Not every lib file has one, and the suite does not require it:** measured 2026-09-10, 6 of 13 carry it (`git_hooks`, `git_sync`, `launch_agents`, `legacy_rsync`, `linux_shared`, `linux_ubuntu`), and the bats harness reaches the other seven through `setup_env.sh`, whose own guard is at `setup_env.sh:57`. Re-count with `grep -l '!= "${0}" ]] && return 0' lib/*.sh`.

### Platform Detection Pattern

The shape used where code branches by OS — for example `lib/detect_env.sh:80` and `.config/.zshrc.d/5_general.zsh:69`. `setup_env.sh` itself contains no such branch, and the exact two-arm form below is illustrative rather than copied from any file:

```bash
if [[ -n ${MACOS} ]]; then ...
elif [[ -n ${UBUNTU} ]]; then ...
fi
```

### Homebrew Helpers

Use the established helper functions, don't call `brew` directly:

```bash
brew_formula_installed <formula>
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

**A `# [HAS_*]` tag selects drift expectations only — it does NOT gate installation, and reading it as a gate is the natural mistake.** `install_macos_casks` (`lib/macos.sh:193`) runs `brew bundle --file "${BREWFILE_LOC}/Brewfile"` with no enclosing `HAS_*` conditional; the guards at `:194` and `:197` wrap only `Brewfile.gui` and `Brewfile.devtools`. So **every mac installs every entry in the main Brewfile regardless of its tag** — a `mac_mini` with no `HAS_DEVTOOLS` still receives `pyenv`, `python@3.13` and `uv`. The tag's only readers are `_brewfile_parse_section` and `_brewfile_parse_inactive` (`lib/update_summary.sh:600`/`:620`), reached solely from the drift check, which uses it to decide whether a missing formula counts as drift _on this machine_.

Two consequences worth holding: tagging an entry does not keep it off a machine, so a tag is never a way to avoid installing something; and an entry present in the Brewfile but not installed produces one advisory `Missing (in Brewfile, not installed): <name>` line per machine whose profile carries the named capability — 6 of the 8 hostname entries carry `devtools`, so that is the blast radius of adding a `[HAS_DEVTOOLS]` entry, not the 2 machines an author usually has in mind. Verified during dotfiles#225 by two independent reviewers reading `lib/macos.sh` rather than trusting the tag's name.

**Formula/cask dedup rule:** never add both a formula and a cask for the same tool (breaks `brew bundle` symlinking). **Tap trust (Homebrew 6.0):** new third-party taps must also be added to the `brew trust` call in `install_macos_casks`/`_install_ubuntu_brew_packages`. Rationale and detail: `~/git-repos/personal/ai-config/docs/knowledge/dotfiles-brewfile-conventions.md`.

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
# see lib/constants.sh for current pins: GO_VER, PYTHON_VER, RUBY_VER, RUSTUP_VER
```

Update these constants when bumping versions — don't hardcode versions elsewhere.
When a constant is updated, update all other references to that constant across the repo.

### Ruby Version Manager Split

Ruby version managers: **rbenv on Linux** (`lib/linux_ubuntu.sh`); **chruby on macOS** (installed by `Brewfile`, loaded by `.config/.zshrc.d/5_general.zsh`). Not interchangeable across platforms. Handled automatically by `install_ruby()`/`install_ruby_tools()` in `developer.sh` — no manual intervention required. Linux build pins `RUBY_CONFIGURE_OPTS="--with-openssl-dir=/usr"` to avoid linking against a Homebrew OpenSSL that breaks gem HTTPS. Full rationale: `~/git-repos/personal/ai-config/docs/knowledge/dotfiles-ruby-version-manager.md`.

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

**Run tests:** `make test` (runs lint, the lock and requirements-CI drift checks, the Python suite, then all BATS tests)

- Detect GNU parallel by version string (`parallel --version` matching `^GNU parallel`), never by presence — moreutils ships an incompatible `parallel` under the same name, and bats' own absence-guard is inverted, so a fooled detector dies with `command not found`.
- `JOBS` defaults to 24; override per invocation with `make test JOBS=6`, and never pass `JOBS="$(nproc)"` (worst setting on a 2-vCPU runner).
- In a **test** that invokes make inside make, `unset MAKEFLAGS MFLAGS MAKELEVEL JOBS` (`tests/makefile_parallel_target.bats:21`) — a command-line `JOBS` reaches the nested make via both `MAKEFLAGS` and the recipe environment, which is why the error names `$(origin JOBS)`. Test-scoped: stripping `MAKEFLAGS` elsewhere also strips `--no-print-directory` (see MAKEFLAGS section).
- Force serial anywhere with `make test HAVE_PARALLEL=`. The bats file list is a filesystem walk, not `git ls-files` (untracked `.bats` files still run); add to `BATS_SERIAL_FILES` only with a measurement showing failure under `--jobs`. → `dotfiles-testing-toolchain.md` § `make test parallel jobs: detection, JOBS validation, and the CI file list`

**Run unit tests only:** `make test-unit` (runs `unit.bats`, `profiles.bats`, and `zshrc.d/unit.bats`)
**Run lint only:** `make lint` — `bash -n` over `SHELL_FILES` (derived by `scripts/list-shell-files.sh`, which emits every tracked file whose first line is a bash/sh shebang, including the `tests/mocks/` fixtures and the two extensionless hooks), `zsh -n` over `ZSH_FILES` (12 tracked files: `.zsh`/`.zsh-theme`/`.zshrc`/`.zprofile` plus `config/profiles.sh`, named explicitly), then shellcheck at default severity for `SHELL_FILES` and `--severity=warning` for `.bats`. `ZSH_FILES` is derived from `git ls-files`; `SHELL_FILES` is content-derived rather than pathspec-derived, for the reason in the ShellCheck section below. Both refuse to report a pass on an empty list. When `shellcheck` is absent the lint step skips it and prints an install hint that names the platform's real path: `brew install shellcheck` on Darwin, and `./setup_env.sh -t developer on Ubuntu` elsewhere, because a `brew install` on Linux would put an unmanaged linuxbrew copy ahead of the pinned `/usr/local/bin/shellcheck`. The recipe reads `_OVERRIDE_PLATFORM` (default `uname -s`) so one machine can test both branches; it changes only the printed string.

- Keep `config/profiles.sh` in both `SHELL_FILES` (`bash -n`, shellcheck) and `ZSH_FILES` (`zsh -n`) — it is sourced from `.zprofile` and `1_init.zsh` and must parse under both. Update the pathspec at both call sites, `Makefile`'s `ZSH_FILES` and `ci.yml`'s `lint-macos` job, together, or the other silently checks a stale set.
- `scripts/phrase_check.py` must verify every classified CLAUDE.md paragraph has a `phrases.md` anchor that still holds, matching whitespace-normalised (never line-oriented, so a wrapped sentence isn't missed) and rejecting any anchor that opens a sentence or paragraph as too fragile.
- `test-python` only runs the checker's own unit tests, not the checker against the real manifest — that only runs from the four-class-resort plan's `acceptance:` blocks, so do not read this suite's coverage as evidence the manifest is enforced. → `dotfiles-testing-toolchain.md` § `config/profiles.sh dual lint scope; scripts/phrase_check.py manifest checker`

**Install hooks:** `make install-hooks` (installs pre-commit and pre-push hooks; run once per checkout)
**Sync agent guidance:** `make sync-agent-guidance` (regenerates `.cursor/rules/global-claude-standards.mdc` from root `CLAUDE.md`'s `@~/.claude/standards/*.md` imports, resolved against the global symlinked standards dir)
**Check agent guidance drift:** `make check-agent-guidance` (fails when generated Cursor guidance is stale)

- The venv is snapshotted (`pip freeze`) before every sync, and that snapshot is the only rollback path — `uv sync` prunes and downgrades, and the pre-sync state cannot be reproduced from `uv.lock`. Reverting this repo does not restore the venv.
- To roll back, run `"$(pyenv which python)" -m pip install --no-deps -r ~/.local/share/dotfiles/venv-snapshots/ansible-<UTC>.txt` — `--no-deps` is required because the resolver refuses the exact state being restored. → `dotfiles-testing-toolchain.md` § `Ansible venv snapshot before every sync (uv sync prune/downgrade, rollback)`

`--no-deps` is required — the state being restored is one the resolver refuses.

- `UV_BIN` (`resolve_uv`, `lib/helpers.sh`) is the operator escape hatch and the only seam that can drive the "not executable" branch — PATH mocking cannot remove the absolute fallback candidates.
- `UV_FALLBACK_PATHS` (`resolve_uv`) holds prefix candidates so a test can reach the genuine not-found branch, otherwise unreachable on any machine with `uv`; it is env-settable as a scalar deliberately, since `UV_BIN`, checked first, already grants the same capability.
- `REQUIREMENTS_CI_TARGET` (`scripts/sync-requirements-ci.sh`) points the drift check at a fixture, so a test that crashes between mutating and restoring cannot leave a modified tracked `requirements-ci.txt` to be committed by accident. → `dotfiles-testing-toolchain.md` § `Environment overrides added by the uv work (UV_BIN, UV_FALLBACK_PATHS, REQUIREMENTS_CI_TARGET)`

- `make sync-requirements-ci` renders all five CI requirements files from `uv.lock`; `make check-requirements-ci` fails when any of the five renderings is stale and is a prerequisite of `make test`.
- There are five renderings, and they are deliberately separate files — never collapse them into one. → `dotfiles-testing-toolchain.md` § `Sync/check CI requirements commands and the five renderings`

| file                           | group         | pins | consumers                   |
| ------------------------------ | ------------- | ---- | --------------------------- |
| `requirements-ci.txt`          | `test-lint`   | 80   | the full local/dev test set |
| `requirements-runtime-ci.txt`  | `runtime`     | 229  | terraform_ansible           |
| `requirements-ci-test.txt`     | `ci-test`     | 11   | per-PR test/lint jobs       |
| `requirements-ci-mutation.txt` | `ci-mutation` | 30   | mutation jobs               |
| `requirements-ci-audit.txt`    | `ci-audit`    | 28   | dependency-audit steps      |

- Never harmonise the five requirements-CI renderings — `tests/setup_env/requirements_ci.bats` asserts distinctness: `test-lint` differs from `runtime`, and `test-lint`/`runtime`/`ci-test`/`ci-mutation` are four pairwise-distinct files. → `dotfiles-testing-toolchain.md` § `Requirements CI groups: do not harmonise (distinctness tests)`

- Scope CI requirements groups by purpose, not by pruning uninvoked tools — pruning still leaves a rendering installing packages a consumer never runs (test-lint 80→73 still left 70 unused for a 3-tool consumer). Not a deletion problem: the packages belong in the venv; each group installs only what its own job runs (`ci-test` = per-PR test/lint, `ci-mutation` = mutation).
- Keep `bandit`, `radon` and `vulture` in `test-lint` only — `bandit` runs via `security-review` on a dev machine, not CI; skills are a caller class a repo-only sweep can't see (`pip-audit`, `hypothesis` too).
- Never put provenance (a `uv.lock` SHA) in a rendering's header — a `runtime`-group edit moves `uv.lock` without changing `test-lint`'s export, forcing a re-render on unrelated changes. Provenance belongs on a consumer's own copy, at copy time.
- `ci-test`'s boundary is stated in `pyproject.toml` and **guarded by a test, not by review**: `ci-test carries none of the mutation whales` fails if `sqlalchemy`/`aiohttp`/`gitpython`/`yarl`/`frozenlist`/`multidict` ever appear there, and `ci-test is materially smaller than the full test-lint rendering` fails if the two converge. Add a tool only on a measurement, as `hypothesis` was — never because "that is where tools go". → `dotfiles-testing-toolchain.md` § `Requirements CI groups: purpose over CI/local, and the erosion guard`

- The drift gate only verifies a rendering is faithful to its declared group — a package in the wrong group still renders faithfully and passes, so a green `check-requirements-ci` is not evidence about grouping (`cosmic-ray` sat wrongly grouped through every green run for months).
- `requirements-ci.txt` is a rendering of `pyproject.toml` plus `uv.lock`, not a declaration — never hand-edit it.
- `uv export` is not byte-deterministic (its header echoes the invoking argv), so `scripts/sync-requirements-ci.sh` must strip and replace that header, or the drift gate fires on every PR; the Makefile guard must skip cleanly when `uv` is absent, and CI must install a pinned, checksum-verified `uv`. → `dotfiles-testing-toolchain.md` § `Requirements CI groups: drift-gate blindness and uv export determinism`

- The pre-commit hook is required: run `make lint` (blocks on any syntax/shellcheck failure), then `ggshield secret scan pre-commit` (scans staged changes for secrets before they reach the remote).
- Resolve `ggshield` by explicit override, then `PATH`, then absolute prefixes — never `command -v` alone — since a git hook inherits whoever invoked `git`, and an interactive-only `PATH` prepend makes `ggshield` invisible to cron and `ssh host '<cmd>'`.
- If `ggshield` is unresolvable, exit 0 (a machine lacking it must still be able to commit the fix that installs it) but announce the skip twice on stderr — never silently. → `dotfiles-testing-toolchain.md` § `Pre-commit hook: make lint and the ggshield actor-boundary resolution`

- The pre-push hook is permanent — it runs `make test` (lint + bats) on every push and fails closed: the suite runs unless every changed path is provably inert, and an unresolvable diff range also fails closed rather than reading as no-change.
- `docs/` and `.github/` are **not** wholesale-inert: `make lint`'s `SHELL_FILES` walk is recursive, so any `.sh` file anywhere in the repo — including under `docs/` or `.github/` — is linted by `make test` and must still trigger the suite. → `dotfiles-testing-toolchain.md` § `Pre-push hook: fail-closed inert-path set`

- `scripts/pre-push` must resolve repo root with `git rev-parse --show-toplevel` first, falling back to the `git rev-parse --git-common-dir` parent only if that fails — direct `--git-common-dir` resolution can test the shared checkout instead of the active worktree branch.
- `scripts/pre-push` must `unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE` before invoking `make test`, and that line must stay below the range-resolution loop (which needs the git environment) — without the strip, a worktree push leaks `GIT_DIR` into every fixture-building test and `git -C <fixture>` silently operates on the leaked repo instead. → `dotfiles-testing-toolchain.md` § `Pre-push hook: worktree root resolution and git env strip`

- Refuse any push to `refs/heads/master` whose diff carries an executable-class path (`*.sh`, `*.bash`, `*.bats`, `*.zsh`, `Makefile`, or the extensionless `scripts/pre-push`/`scripts/commit-msg`) — `ci.yml` triggers on `pull_request` only, so nothing else validates a direct-to-master code push.
- Accumulate the refusal in a flag inside the stdin loop, read it after the loop finishes (never exit mid-loop — one push can carry a branch and a deletion together), and check it **before** the `needs_test` early-exit, or an inert-but-unsafe path skips the guard too.
- Evaluate the refusal against the whole push RANGE, not the tip commit: a docs-only commit stacked on an unpushed executable-class commit is still refused, since both would reach master. If a docs push is refused naming a file you did not touch in that commit, run `git diff --name-only <remote-sha>..HEAD` before assuming the guard is wrong. Never repoint the twelve `tests/scripts/pre_push.bats` tests from their feature ref to master, or they stop testing the inert-set logic and start testing this guard.
- `scripts/pre-push` is itself executable-class, so a defective guard needs a branch and a PR to fix — or `--no-verify` — never a direct push to master. → `dotfiles-testing-toolchain.md` § `Pre-push hook: direct-to-master guard (executable-class paths)`

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

`make lint`'s scope comes from `scripts/list-shell-files.sh`, not a literal list, not `find`, and not a `git ls-files` pathspec. A pathspec is extension-keyed and cannot express "every tracked shell script" — it silently drops the extensionless hooks and every mock under `tests/mocks/` — so the script instead reads every tracked file's first line and keeps it when that line is a bash/sh shebang. That covers every tracked shell file, mocks and hooks included — count it with `bash scripts/list-shell-files.sh | wc -l` rather than reading a figure here; this line carried a stale `101` against the Testing section's stale `102` until 2026-09-08, which is what two restated copies of one derivable number buy you — and excludes both untracked scratch files and the copies inside any linked worktree.

**It now covers `tests/mocks/`, which it did not until this branch.** All 64 mocks tracked at that time were extensionless — 65 today, still all extensionless — so the previous `git ls-files '*.sh' '*.bash'` pathspec plus two named hooks never saw them — a shell file modified there was linted by nothing. The shebang-derived scope in `scripts/list-shell-files.sh` picks them up because it reads content rather than filename. `shellcheck` over the 64 found 2 with findings, both fixed on this branch: 4 × `SC2086` site-suppressed in `tests/mocks/brew` (word-splitting is the point there) and 1 × `SC2034` fixed in `tests/mocks/gpg`.

### CI / GitHub Actions

`.github/workflows/ci.yml` runs on PRs to master only (the pre-push hook gates branch pushes locally):

- `test` job: installs a pinned, checksum-verified shellcheck plus bats, runs `make test`, then verifies test count >= 840 (regression proxy)
- `lint-macos` job: runs on `macos-latest` (**blocks auto-merge** — it is in `auto-merge`'s `needs:`), two independent steps: `bash -n` over the derived `SHELL_FILES` list via `make print-SHELL_FILES | tr ' ' '\n' | xargs`, guarded by its own empty-list check — the `tr` is load-bearing, since `print-%` emits one space-separated line and `xargs -I` implies `-L1` and does not split on blanks, and `zsh -n` over the 12 tracked zsh files selected via `git ls-files '*.zsh' '*.zsh-theme' '.zshrc' '.zprofile' 'config/profiles.sh'` — the trailing `config/profiles.sh` is the deliberate overlap described above and must stay in step with `Makefile`'s `ZSH_FILES`; this second step refuses to pass on an empty file list
- `bash-coverage` job: measures bash line coverage via PS4 xtrace on `ubuntu-latest`; **gates at 91%** — blocks auto-merge if coverage drops below floor. **It runs the same suite as `test`, in a separate job, so every tool `make test` depends on must be installed in BOTH jobs.** Measured 2026-08-21 (#226): a pinned `uv` was added to `test` only, 4 tests that pass under `make test` failed here, and the red-suite guard correctly refused to compute coverage over a red run — so the symptom was a coverage job failing on something that is not coverage. Both jobs now install it (`ci.yml:35`, `:158`).
  **A workflow-wide grep cannot catch this.** The test written to prevent it searched the whole file for `UV_SHA256` and passed on presence anywhere — which it had, in the wrong job. An assertion satisfied by a different _job_ than the one under test is the same cause-isolation defect as one satisfied by a different code path; the check must parse per job. It must also account for `working-directory:`, since the naive per-job version flags `powershell` as a false positive — that job runs `make test` under `working-directory: powershell`, i.e. Pester against a different Makefile, finishing in ~56s rather than five minutes.
- `secret-scan` job: runs gitleaks against recent commits (**blocks auto-merge** — it is in `auto-merge`'s `needs:`). This is a deliberate deviation from `ci.md`'s Personal Repos clause, which says the `secret-scan` job "is advisory (non-blocking) but must be present": a leaked credential must not auto-merge, so it fails closed here.
- `auto-merge` job: auto-merges any PR when all CI jobs pass (`needs: [test, lint-macos, powershell, bash-coverage, secret-scan]`). **Every job named there is a gate, and there is no advisory tier.** `ci.yml` carries no `continue-on-error` and `auto-merge`'s only condition is `if: github.event_name == 'pull_request'` — no `always()` — so a failed, cancelled, or skipped dependency blocks the merge. Adding a job to `needs:` makes it blocking with nothing else to change, which is why the two descriptions above name their status explicitly.
- **Every job declares `timeout-minutes`**, so a hung job can no longer block auto-merge for GitHub's 360-minute default (PR #223 hit this live — `powershell` stalled 30m21s inside `Install PowerShell`). Caps: `test` 20, `bash-coverage` 25, `powershell` 5, and 10 for `lint-macos`, `secret-scan`, `auto-merge`, and `pr-title-lint.yml`'s own job — each sized to roughly 3x its measured p90 — except `powershell`, deliberately tighter at 5 minutes over a 60s p90 as the known-hang job — with a 10-minute floor on the short jobs where 3x p90 would otherwise sit under normal runner variance. Nothing in the suite asserts these values: a guard test was specified and then deliberately dropped across three review rounds — see `docs/superpowers/specs/2026-08-27-ci-job-timeouts-design.md` for the reasoning and the two futures it leaves open.

CI requirements:

- All jobs run on `ubuntu-latest` with `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: true`

### Testing Rules

- **`load_setup_env()` does NOT set OS vars, and this bullet said the opposite until 2026-09-10.** It sources `setup_env.sh`, which _defines_ `detect_env` via `lib/detect_env.sh` but returns at its sourcing guard (`setup_env.sh:57`) before the call at `:62`. So `MACOS`, `LINUX`, `UBUNTU` and every `HAS_*` hold whatever the parent shell exported — set in an interactive developer shell, empty under `env -i`, and different again on a CI runner. Measured 2026-09-10 under `env -i` with a scratch `HOME`: `MACOS`, `LINUX` and `HAS_DEVTOOLS` all empty after `load_setup_env`, and `MACOS=1` after an explicit `detect_env` in the same shell. A test whose outcome depends on OS detection must set the variables itself (e.g. `unset MACOS; export LINUX=1; export UBUNTU=1`) or call `detect_env`, never inherit them. 16 of the 21 files in `tests/setup_env/` call `load_setup_env()`; `cadence_doctor`, `launch_agents`, `mocks_curl`, `profiles` and `requirements_ci` do not.
- **`run_update` tests stay off real pip because `load_mocks` exports `MOCK_PYENV_WHICH_STDOUT` by default** (`tests/helpers/common.bash:13`). Without it the pyenv mock falls back to `command -v python3`, and a `run_update` test that enters the pip section runs a real `pip install` — the test passes but takes 1–3 min in the full suite. A file that calls `load_setup_env` without `load_mocks` loses that default. (This bullet previously led with a per-test workaround the default had replaced, and claimed `load_setup_env()` sets `HAS_DEVTOOLS=1` — false for the reason in the bullet above.)
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

- Floor: 90%. `make test` and CI both fail on any drop below the floor.
- Scope: `setup_windows.ps1` only. `run-tests.ps1` and `run-lint.ps1` are excluded as test/lint glue (per tdd.md "entry-point glue that purely calls already-tested functions"). The top-level `if ($IsWindows) { ... }` dispatcher in `setup_windows.ps1` is also excluded for the same reason — `$IsWindows` is a runtime read-only automatic variable that cannot be overridden in tests; the bodies it calls (`Invoke-DotfilesSetup`, `Invoke-DotfilesUpdate`) are tested directly.
- Re-measure: `cd powershell && make test` prints `Coverage: <N>%` and writes `coverage.xml`.

#### Bash

- Derive the instrumented set from `git ls-files`, never a glob — `config/local.sh` is git-ignored and machine-local, so a glob would diverge from CI. Set: `setup_env.sh` plus tracked `config/*.sh`, `lib/*.sh`, `scripts/*.sh` and the two extensionless hooks, less `scripts/bash-tracer.sh`. The predicate is "reached by the suite" via `BASH_ENV` tracing, not "lives in a directory" — a directory-only predicate silently discards already-collected trace lines, which is how `scripts/` was wrongly excluded, on a claim that was asserted, never measured.
- Check the current set: `bash scripts/run-bash-coverage.sh --list-sources`. → `dotfiles-bash-coverage.md` § `Instrumented set: git ls-files derivation and the scripts/ history`
- The denominator counts commands, not source lines — bash xtrace emits one line per command. Exclude: heredoc bodies/terminators (any interpreter); multi-line `python3 -c "..."` bodies; multi-line array literals (trace as one line — cost `config/profiles.sh` 13 of its 15 lines and `lib/helpers.sh` 8); and pure-argument backslash continuations (only more arguments — **not** excluded if it begins or contains `||`, `&&`, `|`, or `;`). A one-line instance of any of the four is still counted normally.
- Never add a function-declaration exclusion — tried and removed on evidence: a real trace showed `lib/detect_env.sh` line 4 traced twice (source, then re-source under an active `set -x`), so the assumption was wrong, not just too broad. → `dotfiles-bash-coverage.md` § `Denominator counts commands, not source lines (heredocs, python -c, arrays, continuations)`
- The coverable-line denominator is the union of the static heuristic's count and whatever the real trace actually contains — never the heuristic alone — so `covered <= coverable` holds by construction: a wrongly-excluded line raises the denominator (and numerator) rather than lowering the percentage. Each run prints every union-added line as a heuristic-disagreement count; read that count beside the ratio from the same run, never a ratio from a different one.
- Treat `covered > coverable` as a hard, loud non-zero exit, never a silent clamp — it means an exclusion heuristic over-matched, and the run must fail rather than report a number nobody can trust.
- Inspect a file's denominator or a run's coverage against a real trace: `bash scripts/run-bash-coverage.sh --count-coverable <file>` and `--file-coverage <file> <trace>`. → `dotfiles-bash-coverage.md` § `Denominator is the union of the heuristic and the real trace`

- Publish CI's bash coverage figure in the PR body once CI has run (`gh pr edit <n>`); a local run is a preview and must be labelled as one. → `dotfiles-bash-coverage.md` § `covered > coverable is now a hard exit; publishing and reading the figure`

### Test Seams

- A test seam is a variable with a production default — `local _file="${VAR:-<real path>}"` — not a naming rule: seams below are named `_RUSTUP_INIT_*`, `GGSHIELD_BIN`, `LEDGER_BIN`, `_AWS_*`, `_RHN_*`, `_CARGO_BIN`, and more.
- In tests, set the seam variable to a writable temp copy; leave it unset in production code. → `dotfiles-test-seams.md` § `Test seam idiom and override pattern`

**`_RUSTUP_INIT_URL` / `_RUSTUP_INIT_SHA256` / `_RUSTUP_INIT_BIN` / `_OVERRIDE_CARGO_BIN_DIR`
(`lib/linux_ubuntu.sh`'s `_install_rustup_rs`) exist because every test runs against a fake
`HOME` with no `~/.cargo/bin/rustup`, so all of them would otherwise enter the install path
and reach the network** — `tdd.md` E2, a test whose _failing_ branch touches the outside
world. `_OVERRIDE_CARGO_BIN_DIR` selects the directory the idempotency guard reads, making
both "already installed" and "absent" reachable without a real toolchain.

- `_RUSTUP_INIT_SHA256` (`lib/linux_ubuntu.sh:_install_rustup_rs`)
  - Never mock `sha256sum`; supply the real digest via `_RUSTUP_INIT_SHA256` so a mismatch is genuinely exercised in both directions.
  - `tests/mocks/curl` never fetches — it writes `MOCK_CURL_STDOUT` to the `-o` target (or touches it when unset); compute the success-path digest over `MOCK_CURL_STDOUT`'s exact bytes, never a separate fixture file the mock never copies. → `dotfiles-test-seams.md` § `Rustup signature verification seams (_RUSTUP_INIT_URL / _RUSTUP_INIT_SHA256 / _RUSTUP_INIT_BIN / _OVERRIDE_CARGO_BIN_DIR)`

- `_OVERRIDE_NVIDIA_GPU_PRESENT` (`lib/linux_ubuntu.sh:_nvidia_gpu_present`, `_install_ubuntu_nvidia`)
  - `lspci` is never mocked; `_OVERRIDE_NVIDIA_GPU_PRESENT` is what makes both the install and skip branches testable on a machine with no NVIDIA card.
  - Point `_OVERRIDE_NVIDIA_KEYRING`/`_OVERRIDE_NVIDIA_LIST` at fixtures so no test ever writes to the real `/usr/share/keyrings` or `/etc/apt/sources.list.d`. → `dotfiles-test-seams.md` § `NVIDIA GPU detection seams (_OVERRIDE_NVIDIA_GPU_PRESENT / _OVERRIDE_NVIDIA_KEYRING / _OVERRIDE_NVIDIA_LIST)`

**`_OVERRIDE_DOCKER_DAEMON_JSON` (`_install_ubuntu_nvidia`) and `tests/mocks/nvidia-ctk` are
a pair, and the mock is load-bearing rather than a convenience.** The seam points the
before/after `daemon.json` comparison at a fixture. The mock exists because the `sudo`
mock's `command -v nvidia-ctk` otherwise resolves the **real** binary — `claude` and
`workstation` have both carried it since 2026-09-12 — and execs it against the live
`/etc/docker/daemon.json`. That is `tdd.md` E2: a test's failing path must be inert, and
this one would rewrite the operator's docker config. **The Studio cannot reproduce it,
because macOS has no `nvidia-ctk`**, so a green local run is not evidence for this class —
`tdd.md` pitfall G, reached through a binary that exists on two of three machines.
`MOCK_NVIDIA_CTK_WRITES` / `MOCK_NVIDIA_CTK_TARGET` emulate the config write so the caller's
before/after comparison has something to observe, and `MOCK_NVIDIA_CTK_EXIT` drives the
failure path.

- `brew_install_cask`/`brew_cask_installed` (`lib/helpers.sh`)
  - Use `brew_install_cask`/`brew_cask_installed` for a Cask, never `brew_formula_installed` — it greps `brew list --formula` in both branches, never matches an installed cask, and the caller reinstalls it every run. → `dotfiles-test-seams.md` § `brew_install_cask / brew_cask_installed seam`

- `config/profiles.zsh` and `lib/detect_env.sh` must derive `PROFILE`/`HAS_*`/all eight legacy identity vars from the same `config/profiles.sh` table; `tests/zshrc.d/cross_shell.bats` asserts both shells agree on every table key.
- `tests/helpers/legacy_oracle.bash` must stay hand-typed, never derived from `PROFILE_LEGACY` — a derived oracle would agree with a mis-mapped table entry and pass silently. → `dotfiles-test-seams.md` § `config/profiles.zsh and the legacy identity oracle`

**`tests/helpers/legacy_oracle.bash` is that shared oracle, sourced by both
`tests/setup_env/profiles.bats` and `tests/zshrc.d/profiles.bats`, and it is deliberately
hand-typed rather than derived from `PROFILE_LEGACY` in `config/profiles.sh`.** Do not
"fix" the apparent duplication by sourcing `config/profiles.sh` here, or by building the
case statement from it indirectly (`eval`, a runtime-built variable name, or sourcing
something that itself sources it) — a derived oracle follows the same table it is meant to
check, so a hostname swapped onto the wrong legacy variable in `PROFILE_LEGACY` would agree
with itself and pass silently (`behavior.md`: a check derived from the same decision as the
thing it checks cannot falsify it). [ADR-0021](docs/adr/0021-hand-typed-test-oracle-for-the-identity-table.md)
carries the 2x2 that measures this, and **two** caveats on re-verifying it -- both required, and
each one was learned by getting it wrong. First, the mutation must be a **self-consistent** swap
(both members of each wired/wireless pair), because swapping only the non-suffixed keys leaves the
table internally inconsistent and the wireless-twin assertions then catch it without reference to
the oracle at all -- proving twin-consistency instead. Second, the pair must be one whose
**legacy variable is not pinned host-specifically by any other assertion**: `laptop` and `studio`
are pinned that way elsewhere (a hardcoded
`"STUDIO"` literal in `tests/zshrc.d/profiles.bats` and a studio-specific assertion in
`tests/zshrc.d/unit.bats`), so a self-consistent swap of _that_ pair is caught even when the
oracle is derived, and the suite going red proves nothing about this file. `reception<->ratna` is
the documented pair because neither has its legacy variable pinned that way. Both hostnames
_are_ named host-specifically elsewhere -- `tests/setup_env/profiles.bats:94` and `:485` assert
`PROFILE=mac_workstation` for each -- but `PROFILE` comes from `PROFILE_MAP`, which the swap does
not touch, which is why those two stay green. The qualifier is the whole criterion: drop it and a
two-second grep appears to refute the rule.

- `config/profiles.zsh` must use `export`, never `readonly` — it is sourced twice per login+interactive shell, and a `readonly` reassignment on the second source makes that `source` return 126, silently degrading shell identity.
- `lib/detect_env.sh`'s `detect_env()` runs exactly once per bash process, so `readonly` there is correct; do not "fix" one file to match the other. → `dotfiles-test-seams.md` § `config/profiles.zsh export vs lib/detect_env.sh readonly`

- `_OVERRIDE_HOMEBREW_PREFIX_ARM`/`_OVERRIDE_HOMEBREW_PREFIX_INTEL` (`.config/.zshrc.d/5_general.zsh`)
  - Drive both "present" and "absent" through the override, never through the real filesystem — both real prefixes (`/opt/homebrew`, `/usr/local/opt`) exist on any provisioned mac, so an unset override short-circuits the guard and asserts nothing. → `dotfiles-test-seams.md` § `_OVERRIDE_HOMEBREW_PREFIX_ARM / _OVERRIDE_HOMEBREW_PREFIX_INTEL seam`

- `_OVERRIDE_KEYCHAIN_BIN` (`.config/.zshrc.d/5_general.zsh`)
  - `_OVERRIDE_KEYCHAIN_BIN` exists because keychain's real path is absolute and unmockable via `PATH`; without it, an absent-branch test only fails where keychain is actually installed.
  - Keep `"${_keychain}" --eval …` quoted — a default (zsh doesn't word-split unquoted params), not a guarantee, since `emulate sh`/`ksh` re-enable `SH_WORD_SPLIT`. Keep the block wrapped in `[[ -o interactive ]]`: sourcing it non-interactively starts a daemonizing `ssh-agent` that holds the bats pipe and hangs `make test` (measured: 16/run, 161 accumulated).
  - Leave every `[[ ${VAR} ]]` test here unquoted — `[[ ]]` suppresses splitting regardless of `SH_WORD_SPLIT`; quoting them is churn (command vs. test position, not a style rule). `tests/zshrc.d/unit.bats` must keep `setopt shwordsplit`, or the quoting assertion above is vacuous.
  - The non-interactive (zero calls) and interactive (seam read) tests are a pair; neither alone catches a typo'd seam name. → `dotfiles-test-seams.md` § `_OVERRIDE_KEYCHAIN_BIN seam and the interactive guard`

- `_OVERRIDE_CURRENT_LOGIN_SHELL` (`lib/helpers.sh:_current_login_shell`)
  - Derive login shell from `getent passwd`/`dscl UserShell`, never `${SHELL}` — `${SHELL}` names the running shell, not the account's, so a provision started from zsh can misread a `/bin/bash` account as already-zsh.
  - Tests must set `_OVERRIDE_CURRENT_LOGIN_SHELL`: without it they pass on a mac already on zsh and fail on any runner whose account is `/bin/bash` — a machine-dependent pass, not a code-dependent one.
  - Check both `chsh`'s and `sudo -n chsh`'s exit codes rather than logging "Changed default shell" unconditionally — `chsh` authenticates via PAM and exits 1 non-interactively, so an unchecked rc reports success over an unchanged shell.
  - The end-to-end `run_doctor` tests stub every sub-check by name; stub `_doctor_check_login_shell` there too, or it reads the real account mid-suite. → `dotfiles-test-seams.md` § `_OVERRIDE_CURRENT_LOGIN_SHELL seam and the chsh guard`

- `_OVERRIDE_GNUBIN_ARM`/`_OVERRIDE_GNUBIN_INTEL` (`lib/macos.sh:install_make_macos`, `.config/.zshrc.d/6_path.zsh`)
  - Keep the ARM/Intel default pair (`/opt/homebrew/opt/make/libexec/gnubin`, `/usr/local/opt/make/libexec/gnubin`) identical in `install_make_macos` and `6_path.zsh` — a drift makes the install guard and the `PATH` consumer disagree.
  - Tests must set the override to a nonexistent path to reach the absent branch — the real ARM gnubin dir exists on any provisioned mac and an unset override asserts nothing. → `dotfiles-test-seams.md` § `_OVERRIDE_GNUBIN_ARM / _OVERRIDE_GNUBIN_INTEL seam`

- `_OVERRIDE_GNUBIN_LINUX` (`.config/.zshrc.d/6_path.zsh`, `lib/helpers.sh:_doctor_check_gnu_coreutils`)
  - Tests must set `_OVERRIDE_GNUBIN_LINUX` to a nonexistent path to reach the absent branch — the real linuxbrew coreutils gnubin dir exists on any `claude`-class box and an unset override short-circuits the `-d` guard.
  - Keep the default identical in both readers and assert they stay equal, or the doctor diagnosis and the shell's actual `PATH` disagree about what "the gnubin directory" means. → `dotfiles-test-seams.md` § `_OVERRIDE_GNUBIN_LINUX seam`

- `_OVERRIDE_DOCKER_BIN` (`.config/.zshrc.d/6_path.zsh`)
  - Point `tests/zshrc.d/unit.bats` at `/nonexistent/docker-bin` to reach the absent branch — the real `${HOME}/.docker/bin` exists on any mac running Docker Desktop.
  - If Docker Desktop's installer re-adds its `.zprofile` PATH lines, delete them rather than committing them — the entry belongs only in the interactive `6_path.zsh` block. → `dotfiles-test-seams.md` § `_OVERRIDE_DOCKER_BIN seam`

- `GGSHIELD_BIN`/`GGSHIELD_FALLBACK_PATHS` (`scripts/pre-commit-hook.sh`)
  - Drive ggshield absence only through `GGSHIELD_BIN`/`GGSHIELD_FALLBACK_PATHS`, never by editing `PATH` — stripping the directory holding ggshield also removes `git`/`make` from that same directory.
  - A non-executable `GGSHIELD_BIN` is a hard error, not a silent degrade. → `dotfiles-test-seams.md` § `GGSHIELD_BIN / GGSHIELD_FALLBACK_PATHS seams`

- `LEDGER_BIN` (`lib/workflows.sh:ledger_write_entry`)
  - Always prepend `tests/mocks/ledger` to `PATH`; a `HOME`-only redirect cannot force resolution to a fixture, because `command -v ledger` runs before the `${HOME}/.local/bin/ledger` fallback and wins on any machine (`workstation`/`claude`) that already has a real `ledger` on `PATH`. → `dotfiles-test-seams.md` § `LEDGER_BIN seam`

- `_OVERRIDE_LIB_TRAP_SCOPE` (`scripts/check-lib-exit-traps.sh`)
  - Under the override the scope is a plain glob (`<root>/lib/*.sh`); in the real repo it is `git ls-files 'lib/*.sh'` under the four-variable `env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE` strip — a fixture-only suite never exercises the git path CI and the pre-push hook actually run.
  - Keep the one test that runs with no override against the real `lib/` and the real allowlist, asserting the scanned set is non-empty — without it, nothing in the suite touches the path production actually takes. → `dotfiles-test-seams.md` § `_OVERRIDE_LIB_TRAP_SCOPE seam`

- `_OVERRIDE_BATS_BIN` (`scripts/run-bash-coverage.sh`)
  - Drive bats absence only through `_OVERRIDE_BATS_BIN`, never by editing `PATH` — on `ubuntu-latest`, bats shares a directory with bash/grep/sed/mktemp, so removing that directory removes the toolchain, not just bats.
  - Both halves of a seam (test and production) must land in the same commit; reproduce a suspected CI-only failure from `git archive <the sha CI ran>`, never a dirty working tree — a `git stash create` snapshot can silently include a seam CI never had. → `dotfiles-test-seams.md` § `_OVERRIDE_BATS_BIN seam`

- `_OVERRIDE_RUN_TMPDIR_ROOT` (`lib/workflows.sh:_dotfiles_run_tmpdir_setup`)
  - `_OVERRIDE_RUN_TMPDIR_ROOT` is read unconditionally in production, the same shape as `_OVERRIDE_GNUBIN_ARM`/`_INTEL` — it exists because bats leaves `TMPDIR` pointed at the real system temp dir, so `TMPDIR` alone cannot isolate the `mktemp -d ... || return 1` error path. → `dotfiles-test-seams.md` § `_OVERRIDE_RUN_TMPDIR_ROOT seam`

- `_PROFILES_LOADED` (`lib/detect_env.sh:detect_env`, `lib/helpers.sh`)
  - `detect_env()` must set `_PROFILES_LOADED=0` unconditionally on entry, `1` only after `config/profiles.sh` sources cleanly and all three arrays exist — never derive the check from `PROFILE` alone, since `config/profiles.zsh` exports it into child shells and a stale value survives a failed load.
  - Never trust an environment-supplied `_PROFILES_LOADED=1` unexamined — the unconditional reset plus `detect_env()` always running before `run_doctor` is what protects it, not the variable being unexported. → `dotfiles-test-seams.md` § `_PROFILES_LOADED sentinel`

- `_AWS_GPG_BIN`/`_AWS_PKGUTIL_BIN`/`_AWS_KEY_PATH` (`lib/developer.sh:_aws_verify_zip`/`_aws_verify_pkg`, `lib/helpers.sh:_doctor_check_aws_key_expiry`)
  - Resolve `_AWS_GPG_BIN`/`_AWS_PKGUTIL_BIN` via `command -v`, never by stripping `PATH` — stripping `/opt/homebrew/bin` or `/usr/sbin` removes the rest of the toolchain those dirs hold.
  - `_AWS_KEY_PATH` defaults via `DOTFILES_REPO_ROOT`, resolved at **source time** in `lib/constants.sh` as a **plain assignment**, never a `${VAR:-}` self-guard — tried and retired, since a guard only adds an env-settable name selecting where a trust anchor is read from. Never re-derive the expression inline as `$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)`, which returns empty once the caller (e.g. `update_aws_cli`) has already `cd`'d elsewhere.
  - An absolute-path suite (bats' `load_setup_env`) can't exercise this cwd-sensitivity; regression tests must `source ./lib/...` relatively, `cd` away, then assert on the **post-import failure message** — never on absence (tdd.md E5), which an unrelated skip satisfies equally. → `dotfiles-test-seams.md` § `_AWS_GPG_BIN / _AWS_PKGUTIL_BIN / _AWS_KEY_PATH seams`

- `_AWS_BIN` (`lib/developer.sh:install_aws_tools`)
  - Set `_AWS_BIN` in every `install_aws_tools` test on this machine — a real `aws` exists at `/usr/local/bin/aws`, so without the seam the already-installed guard is always taken and the install path is never asserted. → `dotfiles-test-seams.md` § `_AWS_BIN seam`

- Every cadence seam exists because the delivery arm and the LaunchAgent installer resolve absolute paths and external binaries that a `PATH` mock cannot reach; none grants a capability beyond what editing `PATH` or the plist directly would already grant. → `dotfiles-test-seams.md` § `Cadence seams overview (scripts/cadence-notify.sh, lib/launch_agents.sh)`

| variable                   | read by                                         | why it exists                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| -------------------------- | ----------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `_RHN_DETECTOR`            | tests only, via argv `$2`                       | production passes the detector path positionally from the plist; tests substitute a fixture that returns a chosen exit code                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| `_RHN_STATE_DIR`           | `_rhn_state_dir`, `_renovate_cadence_state_dir` | heartbeat root. Defaults under `~/.local/share/dotfiles/cadence/<name>/` — a test pointing at the real path would assert against the machine's live cadence state                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| `_RHN_MKTEMP`              | `run_cadence_notify`                            | selects the `mktemp` used for the detector's stderr capture. Exists because BSD `mktemp` with no template ignores `TMPDIR`, so the obvious seam drives the failure branch on GNU and is inert on every development mac — a test green where it runs most often. Grants nothing beyond `_RHN_CURL_BIN`/`_RHN_LAUNCHCTL`, which already resolve an arbitrary binary from the environment                                                                                                                                                                                                                                                                                                                                                                                           |
| `_RHN_CURL_BIN`            | `_rhn_notify`                                   | `curl` is resolved by name, but a test must capture the payload rather than send it. Every ntfy assertion in the suite reads this capture                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| `_RHN_LAUNCHCTL`           | `_rhn_launchctl`                                | `launchctl load` on a real plist would register a live weekly job on the developer's machine — the destructive-failing-path hazard `tdd.md` E2 names                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| `_RHN_AGENT_DIR`           | `_rhn_agent_dir`                                | defaults to `~/Library/LaunchAgents`; tests must never write there                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| `_OVERRIDE_DOTFILES_ROOT`  | `_rhn_dotfiles_root`                            | lets a test build a fixture root — including one whose path contains `&`, which is how the plist-substitution corruption was found                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| `_OVERRIDE_AI_CONFIG_ROOT` | `_rhn_ai_config_root`                           | the detector lives in ai-config; a test must not depend on that repo being present or on its script existing                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| `_RHN_LOCAL_CFG`           | `_rhn_load_channel`                             | points the channel config at a fixture, and **`tests/scripts/cadence_notify.bats` sets it in `setup()`, not per-test**. The hazard runs in both directions and only one was documented until 2026-09-05. Absent: `config/local.sh` is git-ignored, so an end-to-end run in a worktree reports `no channel to deliver on` for that reason alone — a test-environment fault, not a code fault. Present: in the main checkout it carries a live `NTFY_URL`, so any case that does `unset NTFY_URL` without setting this seam silently reads the operator's real channel and asserts against it. That is why the export is at setup scope — three cases set it per-test and a fourth did not, which left `make test` red on a provisioned machine and green in CI and every worktree |
| `_RHN_MAX_AGE_DAYS`        | `_rhn_max_age_days`                             | the staleness bound the writer stamps into the heartbeat. A test must round-trip it at a **non-default** value: written and read at the default 8, a reader that always fell back to its own constant would agree, and the check would pass while measuring nothing                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |

- `result`/`findings`/`max_age_days` (`scripts/cadence-notify.sh`, `lib/launch_agents.sh:_doctor_check_cadence`)
  - Write `max_age_days` into the heartbeat; when a heartbeat carries none, the reader falls back to its own default (8) and must **name its source** (`from heartbeat` vs `default`), so a fallback is never mistaken for a reading. Render `held`/`incomplete`/`clean`/`pending` as pairwise-unequal states — `pending` is seeded at install (not a grace period), absent means "not installed", and a reinstall must never clobber a real heartbeat.
  - stdout carries findings one per line and nothing else; a stray status/banner line silently over-reports (measured: a clean fleet reporting `"findings": 1`) — check what else the detector writes to stdout before trusting a count. stderr carries the diagnosis, capped at 20 lines and POSTed to ntfy, so never print credentials or env dumps there.
  - Keep heartbeat fields closed-form via `printf`; never add a free-text field or shell out to `python3 -c json.dumps` — free text breaks the `sed`/`json.loads` readers, and a python3 dependency would take down both sides of the one liveness channel. → `dotfiles-test-seams.md` § `Cadence heartbeat contract`

- `PATH` (`LaunchAgents/cadence.plist.template`, `lib/launch_agents.sh`)
  - Every detector dependency must be listed in the plist's `PATH` (`__HOME__/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin`) — launchd sources no profile, so an absent tool (e.g. `ledger`, in the first entry) makes the agent silently unable to run.
  - Resolve a new detector's dependencies under that exact `PATH` (`env -i PATH=<the plist PATH> bash -c 'command -v <tool>'`), never under an interactive shell, which answers for a different actor.
  - A template edit does not reach an installed agent — the live `~/Library/LaunchAgents/*.plist` is a rendered copy from install time. Re-run `setup_env.sh -t setup_user`, then verify the **live** file (`grep -A1 '<key>PATH</key>' <plist>`), not the template. → `dotfiles-test-seams.md` § `Cadence agent PATH and plist rendering`

- `NTFY_URL`/`NTFY_TOPIC` (`scripts/cadence-notify.sh:_rhn_ntfy_target`)
  - ntfy needs both a topic and credentials — POSTing bare `${NTFY_URL}` (host only) cannot deliver; always POST to `${NTFY_URL}/${NTFY_TOPIC}` with auth.
  - Send credentials on **stdin** via `curl -K -`, never `-u` (argv is readable by `ps`), and refuse (never escape) a credential containing a newline — curl's config is line-oriented and reads past a break as a further directive.
  - Keep the heartbeat as a second, silent-when-clean channel; wrap the detector call in `env -u NTFY_URL` so delivery failure and detection failure never collapse into one "no drift" signal. → `dotfiles-test-seams.md` § `Cadence ntfy delivery and heartbeat rationale`

- This group covers the pyenv shim defect and the cargo plugin repair added 2026-09-17; treat each seam below individually, not as one combined pyenv/cargo unit. → `dotfiles-test-seams.md` § `Pyenv-rehash and cargo-tools seams overview`

- `_OVERRIDE_PYENV_ROOT` (`lib/helpers.sh:_pyenv_ansible_venv_bin`, `install_pyenv_rehash_hook`; `lib/workflows.sh` pyenv-shims section)
  - Set `_OVERRIDE_PYENV_ROOT` explicitly in every test touching shim counting or the hook install — a `HOME`-only redirect cannot isolate these functions, because `PYENV_ROOT` (exported by pyenv's own `init` into every interactive shell) is checked before the `HOME` fallback and would outrank a fixture `HOME`. → `dotfiles-test-seams.md` § `_OVERRIDE_PYENV_ROOT seam`

**`_CARGO_BIN` (`install_cargo_tools`, `lib/developer.sh`) is exported to a recording mock by `tests/helpers/common.bash`'s `load_mocks`, not left to a test's discretion.** Resolution order is `_CARGO_BIN` (if executable), then `${HOME}/.cargo/bin/cargo`, then `command -v cargo`, checked first and unconditionally — so without the default export, any suite calling `load_mocks` could fall through to a real `~/.cargo/bin/cargo` and compile all eight `CARGO_TOOLS` pins for real (`tdd.md` E2). A test exercising the other two resolution branches deliberately unsets it and is responsible for its own isolation from there.

**`_RELEASE_BIN_DIR` (`_install_pinned_release_binary`, `lib/linux_ubuntu.sh`) and `_TFENV_LINK_DIR` (`_install_ubuntu_tfenv`, same file) both default to `/usr/local/bin` and both exist for the same reason: `tests/mocks/sudo` execs real commands.** Neither function's `sudo install`/`sudo ln` is mockable by stubbing `sudo` alone — a real, unwritable-looking `/usr/local/bin` still gets a real write once `sudo` execs through. Every test pointing at either function's install path sets the corresponding directory seam to a scratch directory the test owns, so no `sudo` branch is ever taken.

- `_RELEASE_TMP_ROOT` (`lib/linux_ubuntu.sh:_install_pinned_release_binary`)
  - Set `_RELEASE_TMP_ROOT` when asserting the failure-path cleanup of `_install_pinned_release_binary` — BSD `mktemp -d` with a template argument ignores `TMPDIR` entirely, and the Studio's `mktemp` is BSD, so a `TMPDIR`-based assertion is silently inert there (same fix as `_OVERRIDE_RUN_TMPDIR_ROOT`). → `dotfiles-test-seams.md` § `_RELEASE_TMP_ROOT seam`

- `_TFLINT_URL`/`_TFLINT_SHA256`/`_TFSEC_URL`/`_TFSEC_SHA256` (`lib/linux_ubuntu.sh:_install_ubuntu_tflint`/`_install_ubuntu_tfsec`)
  - Drive `_install_pinned_release_binary` with a local fixture URL and a deliberately wrong checksum via these four vars; never mock `sha256sum` itself, mirroring the rustup rule — mocking it would make every mismatch case vacuous. → `dotfiles-test-seams.md` § `_TFLINT_URL / _TFLINT_SHA256 / _TFSEC_URL / _TFSEC_SHA256 seams`

- `_TFENV_ROOT`/`_TFENV_REPO_URL` (`lib/linux_ubuntu.sh:_install_ubuntu_tfenv`)
  - Isolate the clone target from a real `~/.tfenv` with `_TFENV_ROOT`, and drive the clone-failure branch (bad/unreachable URL) with `_TFENV_REPO_URL` — never a real network call. → `dotfiles-test-seams.md` § `_TFENV_ROOT / _TFENV_REPO_URL seams`

- `_PWSH_BIN`/`_PWSH_PROBE_TIMEOUT` (`lib/linux_ubuntu.sh:_pwsh_probe_runs`)
  - Drive all three pwsh states — working, installed-but-broken, not-installed — through `_PWSH_BIN`, since `_pwsh_probe_runs` tests that `pwsh` actually _runs_, not merely that a `.deb` was downloaded.
  - Test the `timeout`-absent fallback with a `PATH` scoped to a directory holding no `timeout` **and** an absolute `#!/bin/bash`-shebang stub (`#!/usr/bin/env bash` exits 127 there, since `env` must resolve `bash` through the same scoped `PATH`); cover both directions — a one-sided test passes vacuously under the opposite mutation. → `dotfiles-test-seams.md` § `_PWSH_BIN / _PWSH_PROBE_TIMEOUT seams`

- `_DOCTOR_PROBE_TIMEOUT` (`lib/helpers.sh:_doctor_check_dev_tools`)
  - Drive the timeout branch with a stub that sleeps under `_DOCTOR_PROBE_TIMEOUT=1`; never wait on the real 10-second default to prove a hung version probe doesn't block doctor. → `dotfiles-test-seams.md` § `_DOCTOR_PROBE_TIMEOUT seam`

- `_CRATES_API` (`lib/workflows.sh:_check_one_cargo_version`)
  - Override `_CRATES_API` (default `https://crates.io/api/v1/crates`) for any test of `CARGO_TOOLS` staleness that must exercise an unreachable crates.io, mirroring the tflint/tfsec URL-override pattern. → `dotfiles-test-seams.md` § `_CRATES_API seam`

- `_OVERRIDE_CLAUDE_SETTINGS`, `_CLAUDE_GUARD_GIT` and `tests/mocks/claude` together isolate every one of `_claude_settings_path`, `_claude_plugin_manifest`, `_claude_registered_marketplaces`, `_claude_installed_user_ids`, `_claude_settings_git_state`, `_claude_settings_guard_check`, `_claude_manifest_split_line`, `setup_claude_plugins` and `provision_claude_plugins` from the real `${HOME}/.claude/settings.json` and the real `claude`/`git` binaries. → `dotfiles-test-seams.md` § `Claude plugin provisioning seams overview`

`_OVERRIDE_CLAUDE_SETTINGS` points every reader above at a fixture instead of `${HOME}/.claude/settings.json`, the real ai-config-managed file. `load_mocks` (`tests/helpers/common.bash`) exports it by default, pointed at a **per-test copy** of `tests/fixtures/claude-settings.json` under `BATS_TEST_TMPDIR` — never the tracked fixture directly. That copy is load-bearing rather than a convenience: `tests/mocks/claude`'s `MOCK_CLAUDE_EDIT_SETTINGS` mode appends a newline to whatever `_OVERRIDE_CLAUDE_SETTINGS` names (to drive the write guard), so pointing it at the tracked file would let any test that forgets to override it again dirty the working tree with an `M tests/fixtures/claude-settings.json` nobody asked for. Every `run_update`/`run_setup_user` test runs under a redirected `HOME` with no settings file at all, so without this default they would all hit the manifest's rc 1 and FAIL for a reason unrelated to what they test — the same shape as the pre-existing `MOCK_PYENV_WHICH_STDOUT`/`_CARGO_BIN` defaults above.

- `_CLAUDE_GUARD_GIT` (`lib/workflows.sh:_claude_settings_git_state`)
  - Resolve git through `_CLAUDE_GUARD_GIT`, never through `tests/mocks/git` alone — that mock returns empty stdout and exit 0 for almost every subcommand and shadows the real repository state `_claude_settings_git_state` needs.
  - In guard tests, strip the mocks directory from `PATH`, symlink the real `git` into a private shim dir, and export that path as `_CLAUDE_GUARD_GIT`, so every other `git`-shaped call in the same file still hits the fast mock. → `dotfiles-test-seams.md` § `_CLAUDE_GUARD_GIT seam`

- `MOCK_CLAUDE_*` (`tests/mocks/claude`)
  - Use `MOCK_CLAUDE_PLUGINS_LIST_JSON`/`MOCK_CLAUDE_MARKETPLACE_LIST_JSON` for the `--json` payload (default `[]`); `MOCK_CLAUDE_FAIL_ARGS` to fail only invocations whose argv contains a given substring; `MOCK_CLAUDE_FAIL_ON_CALL=<n>` to fail only the nth `plugins list --json` call; and `MOCK_CLAUDE_EDIT_SETTINGS=<verb>` to make only `install` or `update` touch `_OVERRIDE_CLAUDE_SETTINGS`.
  - Every invocation is still recorded to `MOCK_CALLS_FILE` regardless of mode. → `dotfiles-test-seams.md` § `tests/mocks/claude seam modes`

- Every `claude` call inside a `while read` loop in `setup_claude_plugins`/`run_update`'s claude section must redirect stdin from `/dev/null` (e.g. `claude plugins marketplace add "${_ref}" < /dev/null`) — without it, `claude` consumes the loop's own `<<<"${_manifest}"` here-string, truncating iteration after the first external call.
- `IFS=$'\t' read` collapses adjacent tabs, so an empty field shifts the next one left instead of staying empty — split manifest lines with `_claude_manifest_split_line`'s parameter expansion, and never emit a genuinely empty tab-separated field (use a literal `-` placeholder, as `_claude_settings_git_state` does). → `dotfiles-test-seams.md` § `Claude plugin provisioning: stdin redirect and IFS tab collapse`

**`_OVERRIDE_CLAUDE_PLUGIN_CACHE` (`_claude_plugin_cache_dir`, `lib/helpers.sh`) points the plugin node-path check and repair at a fixture instead of `~/.claude/plugins/cache`.** Both test files set it in `setup()`, not per test: the repair rewrites files, so a test that forgot it would edit the operator's real plugin cache (`tdd.md` E2). What it guards: context-mode writes `process.execPath` into its cached `hooks/hooks.json` and `.claude-plugin/plugin.json` on Linux ([mksglu/context-mode#1090](https://github.com/mksglu/context-mode/issues/1090)). Under linuxbrew that is the versioned `Cellar/node/<ver>/bin/node`, so `brew upgrade node` deletes it: every hook then fails with `/bin/sh: 1: <path>: not found` and the MCP server does not start. The plugin cannot heal itself, because its repair runs only when that MCP server starts. Measured 2026-09-19 on `claude` (26.8.2) and `workstation` (26.4.0, all six cached versions); `studio` was clean, since upstream skips the rewrite on macOS. The `plugin-node` update section repoints each dead pin at the keg's `opt/` link. The plugin does not rewrite a cache it has already normalized, so the `opt/` path holds until a plugin update extracts a new version. That version is then pinned to whichever versioned node is current, so a later node upgrade needs the repair again. A node upgrade outside `-t update` does not run the repair: `brew bundle` under `-t setup` or `-t developer`, a manual `brew upgrade`, or Claude Code's own background plugin update. `doctor` is the backstop that names each dead pin. Delete the section, the doctor check and the seam once upstream stops writing versioned paths.

### Mock Pattern

- The full `MOCK_*` env var reference table and the general mock usage pattern live in `dotfiles-bats-test-infrastructure.md` — this group's own suffix target, not a `CLAUDE.md` section. → `dotfiles-bats-test-infrastructure.md` § `Mock Pattern full reference pointer (superseded by this section)`

- `tests/mocks/ln`, `chmod`, `mv`, `cp` and `tee` pass through to the real binary (`/bin/cmd "$@" 2>/dev/null || true`), so a test asserting real filesystem state gets a real result.
- Set the mock's exit-code variable to a non-zero value to simulate a failure instead of calling through. → `dotfiles-bats-test-infrastructure.md` § `Mock Pattern: pass-through mocks (ln, chmod, mv, cp, tee)`

- `env -i` strips `PATH`, so a `PATH`-injected pyenv mock is invisible to `setup_ansible()`'s pyenv calls — place the mock binary at the absolute path `${HOME}/.pyenv/bin/pyenv` instead. → `dotfiles-bats-test-infrastructure.md` § `Mock Pattern: env -i strips PATH (pyenv mock placement) -- CLAUDE.md addendum`

- Recognize any `-[a-zA-Z]+` short-option cluster in `tests/mocks/curl`'s arg loop, not just bare `-o`/`--fail`: an `f` anywhere sets fail-mode, a cluster ending in `o` takes the next arg as the `-o` target (production passes `-fsS -o` and `-fLo`, `developer.sh:105`).
- Gate `MOCK_CURL_HTTP_STATUS` on all three: `MOCK_CURL_EXIT` unset, an f-bearing form passed, and the value matching `^[0-9]+$` before comparing `>= 400` (numeric check first, per `shell.md`). `MOCK_CURL_EXIT` always wins when set. → `dotfiles-bats-test-infrastructure.md` § `Mock Pattern: tests/mocks/curl short-option cluster parsing`

- `tests/mocks/curl`'s `-o` write is deferred until **after** the exit code is decided, a deliberate deviation from real curl: a simulated failure (`MOCK_CURL_HTTP_STATUS >= 400` or a nonzero `MOCK_CURL_EXIT`) leaves a pre-seeded target file completely unchanged.
- On success it writes `MOCK_CURL_STDOUT` to the target file AND still emits it on stdout — keep the dual emission: `whats-new*.sh`, `_fetch_github_latest` (`lib/workflows.sh`) and `install_homebrew` (`lib/macos.sh`) never pass `-o` and need the stdout copy from this mock.
- Before removing it, verify no current caller both passes `-o` and consumes stdout. → `dotfiles-bats-test-infrastructure.md` § `Mock Pattern: tests/mocks/curl -o write ordering (deferred success write)`

### MAKEFLAGS and Stdout Partition

- `Makefile:1`'s `MAKEFLAGS += --no-print-directory` suppresses `Entering`/`Leaving directory` only for a child `make` that inherits it, and only on GNU Make 4.0+ (macOS's 3.81 never prints them).
- It does not cover a direct `make -C` on GNU Make 4.3 (`ubuntu-latest`) — that line prints before the Makefile parses, so an in-file directive is too late. The load-bearing protection is the per-call flag plus the partition below, never this directive alone. → `dotfiles-bats-test-infrastructure.md` § `MAKEFLAGS: --no-print-directory directive and its GNU Make version limit`

- `MAKEFLAGS` is an exported env var every spawned `make` inherits — a test capturing `make` output must be guarded or measuring, never neither.
- Guarded: per-call `--no-print-directory` flag, for an exact output-shape assertion.
- Measuring: `env -u MAKEFLAGS` prefix, only to observe directory lines — on GNU Make 4.3 it strips the one working suppression, so never use it for a guarded assertion. Both categories must exist in the suite. → `dotfiles-bats-test-infrastructure.md` § `MAKEFLAGS: exported env var; guarded vs measuring test partition`

- `tests/scripts/makefile_lint_scope.bats` enforces the partition mechanically: it scans every stdout-capturing `make -C` invocation in its domain and requires each in exactly one category, both sets non-empty.
- Derive that domain from `git ls-files` (the same four-variable `env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE` strip), never a hardcoded list — an earlier two-file array excluded the one real violation and still reported clean. → `dotfiles-bats-test-infrastructure.md` § `MAKEFLAGS: partition enforcement test and the git ls-files domain`

- The partition scanner sees only the invoking line, so it is blind to recursive `$(MAKE)` calls and to `-w`/`--print-directory` — both print `Entering`/`Leaving` with no `-C` on the line that triggers them.
- Not exploitable today (the root `Makefile` has no `$(MAKE)` recipes), but `powershell/Makefile` sits outside this scanner's domain entirely — treat this as an accepted boundary, not a defect to silently fix. → `dotfiles-bats-test-infrastructure.md` § `MAKEFLAGS: known gap -- recursive sub-make and -w invisible to the scanner`

## Committing Work

Invoke `caveman:caveman-commit` skill to generate the commit message before running `git commit`. Full format and rules in `~/.claude/CLAUDE.md`.

## Key Conventions

- Machine roles are now driven by the **profile/capability model** in `config/profiles.sh` — prefer `HAS_*` vars over raw hostname patterns for new code
- GPU provisioning gates on detected hardware — `_nvidia_gpu_present` matching PCI vendor `10de:` in `lspci -nn` — never a `HAS_*` capability, since `claude` and `workstation` share the `linux_workstation` profile but not a GPU, and WSL2's driver lives Windows-side. Absent `lspci`, default to skip, not attempt.
- Installing the driver does not bind it (nouveau holds the card until reboot), and installing `nvidia-container-toolkit` does not register it with docker — run `nvidia-ctk runtime configure --runtime=docker` after install, and restart docker only when `daemon.json` actually changed, since these boxes run live GitHub runners. → `dotfiles-conventions.md` § `GPU provisioning as the HAS_* exception (not a capability)`
- All eight legacy hostname vars (`LAPTOP`, `STUDIO`, `RECEPTION`, `RATNA`, `OFFICE`, `HOMES`, `WORKSTATION`, `CRUNCHER`) are derived from `PROFILE_LEGACY` in `config/profiles.sh` — `WORKSTATION` and `CRUNCHER` remain live, and are read by `.zprofile:10` and `.config/.zshrc.d/7_final.zsh:60`; new code should still prefer `HAS_*` vars
- Ubuntu version detection uses `lsb_release -rs` → `NOBLE` var (24.04) or `RESOLUTE` var (26.04); both set in `detect_env.sh` and `.zshrc.d/1_init.zsh`
- Credential directories (`.aws`, `.tf_creds`, `.tsh`) are created with `chmod 700`
- Git repos are cloned to `~/git-repos/personal/` and `~/git-repos/work/`
- Python environments managed via **pyenv** + **pyenv-virtualenv**; the `ansible` venv is the primary one
- **Ansible venv packages:** declared once in `pyproject.toml` under `[dependency-groups]` (`runtime` and `test-lint`), pinned transitively by `uv.lock`. Both venv-creating sites in `lib/developer.sh` install with `uv sync --frozen`; nothing installs from a name list. `mlx` is gated to macOS by a `sys_platform == 'darwin'` marker in the manifest, not by a shell branch. Change a version by editing `pyproject.toml` and re-running `uv lock`.
- **ruff is venv-managed** (not brew); run `brew uninstall ruff` once after venv recreate to remove the legacy brew install
- **Test runner:** `pytest` — runs `unittest.TestCase` tests natively; test file contents do not change
- Application installs are kept in alphabetical order
- For shell syntax-only fixes, validate with `bash -n <file>` for any file `scripts/list-shell-files.sh` picks up (every tracked bash/sh-shebang file, extension or not — includes the hooks and the `tests/mocks/` fixtures), or `zsh -n <file>` for `.zsh`/`.zsh-theme`/`.zshrc`/`.zprofile` files — `make lint` runs both checks over their respective `SHELL_FILES`/`ZSH_FILES` sets before commit
- After any change to `.zshrc` or `.zshrc.d/`, run `zsh -i -c 'exit'` before committing, to catch a re-source crash before it reaches prod.
- In a worktree that command only proves the main checkout is sane, since `~/.zshrc` symlinks there — source the branch's own files explicitly instead. → `dotfiles-conventions.md` § `zsh -i -c 'exit' after .zshrc changes, and the worktree caveat`
- `$0` is not a startup file's own path in zsh — its internal startup reader leaves `$0` as the literal `zsh`, so `${0:A:h}` resolves against cwd instead of the file's directory.
- Use `${${(%):-%x}:A:h}` in any file that may be sourced as a startup file — it names the containing file correctly in both actors. → `dotfiles-conventions.md` § `$0 resolution in zsh startup files (${0:A:h} pitfall)`
- `lib/update_summary.sh`'s `_UPDATE_SECTION_ORDER` array controls which sections print. Add `_update_record_start/end "new-section"` and the array entry together — omitting the entry tracks the section internally but never prints it, with no error.
- Don't audit hardcoded count assertions (`[[ "$output" == *"9 OK"* ]]`) on add/remove — `tests/setup_env/update_summary.bats` seeds sections by name, so an unseeded entry is invisible to the tally by construction.
- The real risk is on **removal**: grep fixtures for a stray reference to the removed name that still seeds it. → `dotfiles-conventions.md` § `_UPDATE_SECTION_ORDER coupling`
- **`scripts/sync_git_repos.sh`** replaces the old rsync-only sync script (`scripts/synch_git-repos.sh`, deleted). Two independent modes: git-native fetch/pull/push for `personal/` repos + `state-ledger` (safe on any of the three dev machines — never force-pushes, never auto-merges a diverged repo; dirty does not block a safe push, only a pull), and studio-only rsync push for legacy/no-git-access directories + a full-tree ratna backup. Runs automatically as part of `-t update` (`git-repos`/`legacy-rsync` sections in `_UPDATE_SECTION_ORDER`); `--git-only`/`--legacy-only`/`--dry-run`/`-h` for standalone use, where `--dry-run` suppresses every outbound write and `--git-only` combined with `--legacy-only` is rejected as ambiguous rather than resolved. See `docs/superpowers/specs/2026-07-18-sync-git-repos-design.md` for the full design and the dirty/ahead/behind decision table. **Never invoke this script (or `sync_legacy_dirs`/`sync_git_repos` directly) unmocked outside the BATS test harness** — it performs real `git push`/`rsync --delete` over SSH against real hosts, and `_is_legacy_sync_host` triggers on the real `hostname -s` of whichever machine runs it.
- The `git-hooks` section carries the same `_UPDATE_SECTION_ORDER` trap as above, one function over — miss the array entry and the section is tracked internally but never printed.
- The sweep's post-condition reads the installed hooks directory, never `scripts/`, so hooks installed by any route (e.g. `ledger init`) still count; only presence and the executable bit are checked, so a stale `cp`-installed hook still passes.
- `install_git_hooks_all_repos` returns 0 clean / 1 hard failure / 2 partial (gaps or a pinned `core.hooksPath`); both `run_update` and `run_setup_user` must branch on all three. `_git_hooks_target_dir` resolves the Makefile target (root, else exactly one `*/Makefile` one level down, else `:ambiguous`/`:unreadable`) rather than assuming root. → `dotfiles-conventions.md` § `git-hooks section coupling and _git_hooks_target_dir`
- `_install_ubuntu_brew_packages` returns 0 clean, 1 hard failure, 2 partial success, with failed packages named on stderr.
- `install_ubuntu_packages` captures that rc rather than using `|| return 1`: only rc 1 aborts, since a bare guard would kill a whole bootstrap over one briefly-unavailable formula, while an unchecked call reports success over packages that never landed. → `dotfiles-conventions.md` § `_install_ubuntu_brew_packages tri-state return`
- `claude plugins install` takes `-s user` and a `plugin@marketplace` id; the flag pins scope (already the CLI's own default) rather than fixing a defect — keep it so a future default change can't silently move installs. → `dotfiles-conventions.md` § `claude plugins install -s user scope flag`
- The zsh-autosuggestions guard is `[[ -e ${_zsh_autosug}/.git ]]`, never `git rev-parse --git-dir` — that plumbing command walks upward through parent directories, and `~/.oh-my-zsh` is itself a git checkout, so a non-clone install would silently update oh-my-zsh instead and report a permanent false "no changes".
- Use `-e`, not `-d`: a submodule or linked worktree has `.git` as a file, and `-d` would route that layout to SKIP forever. → `dotfiles-conventions.md` § `zsh-autosuggestions reported update section`
- The update summary's name-column width is derived, not hardcoded: a test reads the pad width out of `lib/update_summary.sh`'s `printf` format and asserts it stays >= 1 wider than `_UPDATE_SECTION_ORDER`'s longest entry, so a section name of 20+ characters fails the test rather than silently colliding with the reason column. → `dotfiles-conventions.md` § `Update summary name column width`
- The cheat.sh update section (`lib/workflows.sh`) fetches the binary and the tab-completion file inside one subshell sharing an `_rc`, so either fetch's failure fails the section — it previously ran the completion fetch as a bare statement after the section had already closed, hiding a completion-only failure.
- Progress banners print outside that subshell so they never land in `err_cheat.sh`/`detail_cheat.sh`, which feeds the `tail -10` diagnostic budget. → `dotfiles-conventions.md` § `cheat.sh section: both artifacts, both failures FAIL the run`
- `.warp/settings.toml` is Warp-owned and symlinked live (`~/.warp/settings.toml` -> repo); Warp rewrites it on upgrade, so an unexplained diff there is usually a materialized default, not a hand edit.
- `agents.warp_agent.other.auto_approve_bypasses_command_denylist = false` is a deliberate non-default (Warp defaults `true`, which makes `command_denylist` inert under auto-approve). It syncs globally, so a diff flipping it back to `true` is a sync reversion to re-pin, never an upgrade artifact to accept. → `dotfiles-conventions.md` § `.warp/settings.toml Warp-owned symlink and auto_approve_bypasses_command_denylist`
- `core.hooksPath` set at global/system scope redirects every repo's hooks at once (`git rev-parse --git-path hooks` honors it); empty or whitespace-only counts as a real pin — `git config --get` returns rc 0 with empty stdout and git still disables every hook on the machine.
- Probe with `--includes` (the default `--no-includes` misses a pin reached through an include) and `-z`, consumed via `read -d ''` off a process substitution, never `$(...)`. A key held in an included file needs `git config --file <origin> --unset core.hooksPath`; a scope-level `--unset` there exits 5 and leaves the pin. Output contract is `scope<TAB>remedy<TAB>value`, value last, so a tab in a pinned path can't truncate the remedy.
- `tests/setup_env/git_hooks.bats`'s `setup()` must neutralize `GIT_CONFIG_GLOBAL`/`GIT_CONFIG_SYSTEM`, or the suite fails on any machine with a pin — and since `scripts/pre-push` runs `make test`, that developer cannot push. → `dotfiles-conventions.md` § `Global/system core.hooksPath pin: detection and remedy`

- The Homebrew `make` gnubin directory must be prepended to `PATH`, never appended (`path+=`) — `.config/.zshrc.d/6_path.zsh`'s existing idiom appends, which would leave `/usr/bin/make` 3.81 ahead and be completely inert.
- Test both Homebrew prefixes for existence (ARM `/opt/homebrew/opt/make/libexec/gnubin`, Intel `/usr/local/opt/make/libexec/gnubin`) rather than calling `brew --prefix`, since `.config/.zshrc.d/6_path.zsh` is what puts `brew` on `PATH`. The linuxbrew coreutils gnubin prepend is gated only on `[[ -d ... ]]`, deliberately not on `RESOLUTE` — the install is release-gated, the `PATH` edit is release-blind. → `dotfiles-conventions.md` § `Homebrew make gnubin prepend (prepend, not append)`

- Which `make` an actor resolves depends on whether the process sourced `6_path.zsh`: interactive zsh and everything descended from it (tmux, hooks it launches, this harness's own shell) get GNU 4.4.1; cron, launchd, `ssh host '<cmd>'`, and editor-spawned git hooks get `/usr/bin/make` 3.81.
- The split is currently harmless to this repo's gates: `Makefile:1`'s `MAKEFLAGS += --no-print-directory` suppresses on 4.x what 3.81 never printed. Do not reopen this without re-running that comparison (`specs/2026-08-16-system-wide-gnu-make-design.md`, `specs/2026-08-16-hook-make-resolution-design.md`). → `dotfiles-conventions.md` § `Which make an actor resolves (gnubin/actor table)`

- `setup_env.sh` gates every workflow on `env which brew`, and `6_path.zsh`'s linuxbrew `PATH` prepend is sourced by interactive zsh only — so no cron job, git hook, CI runner, or agent session can run `setup_env.sh` non-interactively on the Linux workstation; it fails with a misleading "run bootstrap_linux.sh first" even after bootstrap has already run.
- This is the macOS `make`-resolution trap one severity worse: treat a tool path placed in an interactive-only rc file as gating whichever actor sources that file, never as a machine-wide fact. A `PATH` prepend inside a hook shadows `tests/scripts/pre_push.bats`'s own `make` mock (measured: 28 of 36 tests failed) — route any future hook `PATH` edit through `_OVERRIDE_GNUBIN_ARM`/`_OVERRIDE_GNUBIN_INTEL` instead.
- On macOS, a `/usr/local/bin` symlink cannot fix `make` for hooks, cron, launchd or `ssh host '<cmd>'`: `/etc/paths` is read only by `path_helper`, which only login shells run — measured, it changes nothing for any non-interactive actor.
- Workaround for a non-interactive caller: prepend the prefix explicitly rather than re-bootstrapping — `PATH="/home/linuxbrew/.linuxbrew/bin:${PATH}" ./setup_env.sh -t developer`. → `dotfiles-conventions.md` § `setup_env.sh cannot run non-interactively on the Linux workstation (brew PATH)`
- **`install_cargo_tools` (`lib/developer.sh`) judges each `CARGO_TOOLS` pin (`lib/constants.sh`) by whether the binary runs (`--help`), never by the version string cargo reports, and repairs a non-runnable install with `--force`.** `-t update --brew-only` reaches the `cargo-tools` section deliberately — a brew upgrade of a shared library is exactly what can break a linked binary the pin already satisfies by version, so the repair path has to run there too, not only under a full update. A first run, or a pin bump in `CARGO_TOOLS`, compiles every `absent`/`older` crate from scratch, which can take tens of minutes — stated rather than hidden, since `workstation` had only two of the eight pins installed before this landed.
- `_install_ubuntu_tfenv` clones `~/.tfenv` if absent, symlinks `tfenv`/`terraform` into `/usr/local/bin` only when neither name already exists as a regular file or a foreign symlink, and installs `TERRAFORM_VER` only when `~/.tfenv/version` is absent — an operator's chosen version is never overwritten.
- The `[[ ! -x "${_root}/bin/tfenv" ]]` guard must run and return before the symlink loop: running the loop first plants two dangling symlinks that the **loop's own** `-L` branch (`[[ -L "${_link}" ]]`, further down) then treats as already repaired on every subsequent run. The remedy for a broken checkout (`rm -rf ${_root}`) belongs in the WARN, not in doctor. → `dotfiles-conventions.md` § `terraform on Linux via tfenv, and the checkout guard`
- `tflint`/`tfsec` staleness is not checked by `check-versions` (tracked as a Backlog gap). The eight `CARGO_TOOLS` pins are checked, against crates.io's `max_stable_version`, which needs a `-A "dotfiles check-versions (bjackson@pobox.com)"` header or the request 403s. → `dotfiles-conventions.md` § `tflint/tfsec staleness gap; CARGO_TOOLS staleness via crates.io`

## Dependency Automation

- Inline the shared Renovate preset into `renovate.json`, don't `extends` it — ai-config is private, dotfiles public, and an unfetchable `extends` throws `config-validation` at `initRepo` and silently abandons the repo (measured: `extends` gave 8 errors/0 extractions; inlined gave 0/1). ADR-0010's "each repo extends the preset" no longer holds.
- Hand-sync `extends`/`schedule`/`labels`/`packageRules` with canonical `ai-config/renovate-presets/default.json` — nothing detects drift between the copies. → `dotfiles-dependency-automation.md` § `renovate.json inlines the shared preset (private-repo visibility)`

- Treat Renovate as confirmed running here, not merely configured: #240 pinned every `actions/checkout` ref to a digest and auto-merged, #241 raised a major bump and did not — `packageRules` working as written — and `pinDigests: true` moved this repo from 0-of-6 pinned refs to 6-of-6.
- Do not cite the `mode=silent` finding as a live constraint without re-reading a current Mend job log — silent mode is no longer in force here (a created branch is the one thing it forbids). → `dotfiles-dependency-automation.md` § `Renovate confirmed working: pinDigests and auto-merge in production`

- Never conclude Renovate is inactive from a zero-PR count alone: under `mode=silent` zero was the only reachable value, so every "not running" verdict built on it was unprovable either way.
- Before concluding anything from what a mechanism has not done, establish what it was even permitted to do — this holds even once silent mode is lifted elsewhere. → `dotfiles-dependency-automation.md` § `The zero-PR oracle was structurally unfalsifiable under silent mode`

- Do not add `pip_requirements` to `renovate.json`'s `enabledManagers` — deliberately absent. Its pattern allows only one suffix after "requirements", so of five generated renderings only `requirements-ci.txt` matches, by luck not design; `tests/setup_env/requirements_ci.bats` pins it since a rename would silently widen scope.
- All five renderings are generated from `uv.lock`; enabling the manager would raise PRs against generated files `check-requirements-ci` fails. The real declaration is `pyproject.toml`, owned by `pep621`. → `dotfiles-dependency-automation.md` § `pip_requirements deliberately absent from enabledManagers`

- Keep Dependabot security auto-PRs OFF, vulnerability alerts ON, fleet-wide across all 18 non-archived repos (decided 2026-08-21) — a GitHub repo-Settings toggle no tracked file captures (`dependabot.yml` governs version updates, not security), so absence from any file is not evidence it's unset.
- Rationale: alerts are the signal, auto-PRs an unreviewed write path — #227 auto-merged an unattended lockfile edit because it passed CI. Don't re-enable auto-PRs without deliberately re-opening that path; 16 of 18 repos had alerts off entirely before this decision. → `dotfiles-dependency-automation.md` § `Dependabot: security auto-PRs off, vulnerability alerts on (fleet-wide)`

- `automated-security-fixes` is repo-wide — there is no per-ecosystem toggle, so "turn Dependabot off for Python only" is not expressible.
- The flag cannot be cleared while alerts are off: `DELETE automated-security-fixes` 422s "Vulnerability alerts must be enabled…" on a repo left inert but latently armed. Always call `PUT vulnerability-alerts` first, then `DELETE automated-security-fixes` — never the reverse. → `dotfiles-dependency-automation.md` § `Dependabot: mechanical details (repo-wide toggle, ordering)`

- Do not assume Python packages get automated update PRs here: Dependabot's write path is closed (auto-PRs off) and Renovate manages no Python anywhere (`pep621` enabled in no repo), including this one, despite `pyproject.toml`/`uv.lock` living here — vulnerability alerts will fire with nothing proposing a fix. → `dotfiles-dependency-automation.md` § `Consequence: Python has no automated dependency update path`

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

`config/profiles.sh` is the single hostname→identity table, sourced by both bash
(`lib/detect_env.sh`) and zsh (`config/profiles.zsh`, itself sourced by `.zprofile` and
`.config/.zshrc.d/1_init.zsh`). After `detect_env()` (bash) or `config/profiles.zsh` (zsh)
runs, the following vars are set:

| Var            | Values                                                                                                          |
| -------------- | --------------------------------------------------------------------------------------------------------------- |
| `PROFILE`      | String: `personal_laptop`, `mac_workstation`, `mac_mini`, `linux_workstation`, `wsl2_workstation`, or `unknown` |
| `HAS_GUI`      | Set for: personal_laptop, mac_workstation, mac_mini, linux_workstation, wsl2_workstation                        |
| `HAS_DEVTOOLS` | Set for: personal_laptop, mac_workstation, linux_workstation, wsl2_workstation                                  |
| `HAS_AWS`      | Set for: personal_laptop, mac_workstation, linux_workstation, wsl2_workstation                                  |
| `HAS_K8S`      | Set for: personal_laptop, mac_workstation, linux_workstation, wsl2_workstation                                  |
| `HAS_DOCKER`   | Set for: personal_laptop, mac_workstation, linux_workstation, wsl2_workstation                                  |
| `HAS_RUST`     | Set for: personal_laptop, mac_workstation, linux_workstation, wsl2_workstation                                  |
| `HAS_SNAP`     | Set for: linux_workstation only (not wsl2_workstation — snap unavailable in WSL2)                               |
| `HAS_FLATPAK`  | Set for: linux_workstation only (gates Steam flatpak install in `_install_ubuntu_gui_tools`)                    |
| `HAS_PRINTING` | Set for: personal_laptop, mac_workstation, mac_mini                                                             |

`server` is gone — it belonged to a retired mac mini that no hostname has mapped to since,
and `PROFILE_CAPS[server]` was deleted with it.

**A `-1` suffix on a hostname is that machine's wireless-interface name** — `hostname -s`
returns it whenever the machine is off ethernet — and both spellings resolve to the same `PROFILE`/`HAS_*` set.

`workstation`, `cruncher` and `claude` take a single key because each holds **one** DHCP/DNS
registration — that is the criterion, not the interface count and not the absence of wireless
hardware. `workstation` has `wlp14s0` and NetworkManager and still reports `workstation`;
`claude` has `wlo2`, down and unconfigured, and its wired side is a **bond**, so several
physical NICs hold one registration between them. A `-1` name is a second registration, so it
appears only for a machine that actually connects both ways. `home-1` is the one exception to the suffix meaning "wireless": there
the `-1` is part of the machine's actual name (a naming mistake kept in case a `home-2`
follows), and it has no separate `home` entry.

An unmapped hostname resolves to `PROFILE=unknown` with zero `HAS_*` — that is a silent,
well-formed answer, not an error, which is why `run_doctor` now checks for it explicitly
(see Adding a New Machine).

## Adding a New Machine

Measured directly against `origin/master` (this branch's merge-base): before the
`PROFILE_LEGACY` consolidation, a new machine's legacy identity variable needed a
hardcoded case arm in **five** separate files — `config/profiles.sh` (`PROFILE_MAP`),
`config/profiles.zsh`'s own case statement, `lib/detect_env.sh`'s own case statement, and
two independently hand-typed oracles duplicated across `tests/setup_env/profiles.bats`
and `tests/zshrc.d/profiles.bats`. `tests/helpers/legacy_oracle.bash` did not exist at
that commit. This branch's `PROFILE_LEGACY` table plus one shared test oracle brought that
down to **three edits across two files** for a host with a wireless twin — a 40%
reduction, not an addition — or **four edits across three files** for a wired-only host,
which also needs an entry in `tests/setup_env/profiles.bats`'s `wired_only` set (see the
note after step 3 below).

1. Edit `config/profiles.sh` — add **both** the wired and the wireless-interface hostname to
   `PROFILE_MAP`, mapped to the same profile. A machine added under only its wired name
   silently loses every capability the moment it's on wifi — `PROFILE` resolves to `unknown`
   and no `HAS_*` var is set — which is the defect this table's design exists to prevent:

```bash
declare -A PROFILE_MAP=(
  [laptop]="personal_laptop"        [laptop-1]="personal_laptop"
  [my-new-host]="mac_workstation"   [my-new-host-1]="mac_workstation"   # ← new pair
  ...
)
```

2. In the same file, add the identical wired/wireless pair to `PROFILE_LEGACY`, mapping
   both hostnames to the same legacy identity variable name (`LAPTOP`, `STUDIO`, ...) — the
   same twin rule `PROFILE_MAP` follows, for the same reason: an entry only under the wired
   name loses its legacy variable the moment the machine is on wifi. If the machine needs a
   new profile, also add it to `PROFILE_CAPS`.

3. Add a case arm to `tests/helpers/legacy_oracle.bash` for the new hostname(s), naming the
   same legacy variable. This oracle is deliberately hand-typed rather than derived from
   `PROFILE_LEGACY` — a derived oracle would follow whatever the production table says, so a
   hostname swapped onto the wrong legacy variable in `PROFILE_LEGACY` itself would agree
   with the very table it exists to check, and pass silently.

   Measured directly: skipping either step **fails the suite** — a dedicated test
   (`every PROFILE_MAP key has a PROFILE_LEGACY entry`) catches a missing `PROFILE_LEGACY`
   entry, and the per-host oracle comparison catches a missing `legacy_oracle.bash` arm — so
   the normal push → CI → auto-merge path blocks either mistake before it ships. They differ
   only in what happens if a mistake reaches a real shell anyway (a bypassed hook, a
   disabled test): a missing `PROFILE_LEGACY` entry
   degrades gracefully — `config/profiles.zsh` prints a warning to stderr at login and the
   shell keeps going, never crashing — while a missing oracle arm has no production
   consequence at all, because `tests/helpers/legacy_oracle.bash` is read only by the test
   suite and no login shell ever sources it.

   **A wired-only host (no `-1` twin, like `workstation`, `cruncher`, and `claude`) needs a
   fourth edit, in a third file:** add its key to the `wired_only` set in
   `tests/setup_env/profiles.bats`, or the test `every wired PROFILE_MAP key has a wireless
-1 twin on the same profile` fails, since that test expects every `PROFILE_MAP` key to
   have a `-1` twin unless explicitly exempted.

4. Push a feature branch — CI validates → auto-merges to master.

**No other file needs changing** — true for production, since `lib/detect_env.sh` and
`config/profiles.zsh` both derive `PROFILE`/`HAS_*`/the legacy identity variables from
`PROFILE_MAP`/`PROFILE_LEGACY` in this one file — but not for tests: `tests/helpers/legacy_oracle.bash`
(step 3) is a second, deliberately independent copy of the same mapping and needs its own
edit too, and a wired-only host needs a third test edit besides — its key added to
`tests/setup_env/profiles.bats`'s `wired_only` set.

If a hostname is missing from the table, `run_doctor` fails and names the hostname and
`config/profiles.sh` in its message — that is the check that catches the omission in step 1
rather than letting the machine silently run with no capabilities.

---
