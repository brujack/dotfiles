# CLAUDE.md — dotfiles

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

The guard is required rather than defensive, because bats' own one is inverted: `bats-exec-suite:106` reads `! type -p "$p" && "$p" --version`, so with `parallel` absent the second term invokes the binary just established not to exist, the branch meant to decline is skipped, and `bats --jobs` dies with `command not found`. The error names `$(origin JOBS)`, because a command-line `JOBS` reaches a nested make through **both** `MAKEFLAGS` and the recipe environment, so a test that invokes make inside make must unset both to stay discriminating. An untracked `.bats` file is exactly what a TDD red step produces, and a tracked-only list would report it green by never running it. Never pass `JOBS="$(nproc)"`: on a 2-vCPU runner that is two workers, which ai-config's runner data shows is the worst available setting — slower than serial, while a fixed count well above the core count beats it.

**Before** changing the parallel-jobs detection **on** `Makefile`'s `HAVE_PARALLEL`/`JOBS`, read `ai-config/docs/knowledge/dotfiles-testing-toolchain.md` § `make test parallel jobs: detection, JOBS validation, and the CI file list`.

**Run unit tests only:** `make test-unit` (runs `unit.bats`, `profiles.bats`, and `zshrc.d/unit.bats`)
**Run lint only:** `make lint` — `bash -n` over `SHELL_FILES` (derived by `scripts/list-shell-files.sh`, which emits every tracked file whose first line is a bash/sh shebang, including the `tests/mocks/` fixtures and the two extensionless hooks), `zsh -n` over `ZSH_FILES` (12 tracked files: `.zsh`/`.zsh-theme`/`.zshrc`/`.zprofile` plus `config/profiles.sh`, named explicitly), then shellcheck at default severity for `SHELL_FILES` and `--severity=warning` for `.bats`. `ZSH_FILES` is derived from `git ls-files`; `SHELL_FILES` is content-derived rather than pathspec-derived, for the reason in the ShellCheck section below. Both refuse to report a pass on an empty list. When `shellcheck` is absent the lint step skips it and prints an install hint that names the platform's real path: `brew install shellcheck` on Darwin, and `./setup_env.sh -t developer on Ubuntu` elsewhere, because a `brew install` on Linux would put an unmanaged linuxbrew copy ahead of the pinned `/usr/local/bin/shellcheck`. The recipe reads `_OVERRIDE_PLATFORM` (default `uname -s`) so one machine can test both branches; it changes only the printed string.

`config/profiles.sh` is a bash file — it stays in `SHELL_FILES` for `bash -n` and shellcheck — and is also the one deliberate entry in `ZSH_FILES`: `config/profiles.zsh` sources it from both `.zprofile` and `1_init.zsh`, so `zsh -n` must parse it too. The pathspec is duplicated at two independent call sites — `Makefile`'s `ZSH_FILES` and `.github/workflows/ci.yml`'s `lint-macos` job — and both must carry `config/profiles.sh` together; a fix to one alone leaves the other checking a stale set. **`scripts/phrase_check.py`** verifies the CLAUDE.md four-class re-sort: every classified paragraph carries a row in `docs/superpowers/plans/phrases.md` anchored to a verbatim phrase, and the tool asserts those anchors still hold. Matching is whitespace-normalised and never line-oriented, because a hand-wrapped paragraph routinely splits a sentence across a wrap a `grep` cannot cross; a phrase that begins a sentence, or opens a paragraph, is rejected as a fragile anchor, since a later edit capitalising a leading word would silently break it. `test-python` runs `tests/test_phrase_check.py`, so the checker is tested — but nothing runs the checker against the real manifest, and its only executable call sites are the `acceptance:` blocks of `docs/superpowers/plans/2026-09-21-claude-md-four-class-resort.md`, driven by the orchestrator during Phase 2. Do not read the suite's coverage as evidence the manifest is enforced.

**Before** changing lint scope **on** `Makefile`, `scripts/phrase_check.py`, read `ai-config/docs/knowledge/dotfiles-testing-toolchain.md` § `config/profiles.sh dual lint scope; scripts/phrase_check.py manifest checker`.

**Install hooks:** `make install-hooks` (installs pre-commit and pre-push hooks; run once per checkout)
**Sync agent guidance:** `make sync-agent-guidance` (regenerates `.cursor/rules/global-claude-standards.mdc` from root `CLAUDE.md`'s `@~/.claude/standards/*.md` imports, resolved against the global symlinked standards dir)
**Check agent guidance drift:** `make check-agent-guidance` (fails when generated Cursor guidance is stale)

**The venv is snapshotted before every sync, and that file is the only rollback path.** `--no-deps` is required — the state being restored is one the resolver refuses.

**Before** rolling back the ansible venv **on** `run_update`'s venv-sync step, read `ai-config/docs/knowledge/dotfiles-testing-toolchain.md` § `Ansible venv snapshot before every sync (uv sync prune/downgrade, rollback)`.

| variable | read by | why it exists | | ------------------------ | --------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | | `UV_BIN` | `resolve_uv` (`lib/helpers.sh`) | operator escape hatch, and the only seam a test can use to drive the "not executable" branch — PATH mocking cannot remove the absolute fallback candidates | | `UV_FALLBACK_PATHS` | `resolve_uv` | array of prefix candidates.

**Before** editing **on** `resolve_uv`, read `ai-config/docs/knowledge/dotfiles-testing-toolchain.md` § `Environment overrides added by the uv work (UV_BIN, UV_FALLBACK_PATHS, REQUIREMENTS_CI_TARGET)`.

**Before** editing a requirements-ci rendering **on** `scripts/sync-requirements-ci.sh`, read `ai-config/docs/knowledge/dotfiles-testing-toolchain.md` § `Sync/check CI requirements commands and the five renderings`.

| file                           | group         | pins | consumers                   |
| ------------------------------ | ------------- | ---- | --------------------------- |
| `requirements-ci.txt`          | `test-lint`   | 80   | the full local/dev test set |
| `requirements-runtime-ci.txt`  | `runtime`     | 229  | terraform_ansible           |
| `requirements-ci-test.txt`     | `ci-test`     | 11   | per-PR test/lint jobs       |
| `requirements-ci-mutation.txt` | `ci-mutation` | 30   | mutation jobs               |
| `requirements-ci-audit.txt`    | `ci-audit`    | 28   | dependency-audit steps      |

Do not harmonise them — `tests/setup_env/requirements_ci.bats` asserts distinctness across two tests: "the two renderings are different files with different content" (`test-lint` vs `runtime`) and "all four renderings are distinct files" (three pairwise diffs over `test-lint`, `runtime`, `ci-test`, `ci-mutation`).

**Before** merging a dependency group **on** `pyproject.toml`, read `ai-config/docs/knowledge/dotfiles-testing-toolchain.md` § `Requirements CI groups: do not harmonise (distinctness tests)`.

Dropping every genuinely-uninvoked tool takes the test-lint rendering 80 → 73, so a consumer running three tools still installs 70 it never runs. **The framing that matters, because it was wrong for most of the design: this was never a deletion problem.** A repo-only sweep cannot see that call: **skills are a caller class living outside every repo**, and `pip-audit` and `hypothesis` are skill-invoked too. A `runtime`-group edit moves `uv.lock` without changing the `test-lint` export, so a `uv.lock` SHA in that header would demand a re-render whose only effect is one header line — a gate firing on correct state, forever.

**Before** adding a tool to `ci-test` **on** `pyproject.toml`, read `ai-config/docs/knowledge/dotfiles-testing-toolchain.md` § `Requirements CI groups: purpose over CI/local, and the erosion guard`.

Never hand-edit it.

**Before** moving a package between groups **on** `pyproject.toml`, `uv.lock`, read `ai-config/docs/knowledge/dotfiles-testing-toolchain.md` § `Requirements CI groups: drift-gate blindness and uv export determinism`.

The pre-commit hook is **required**. **Resolved by explicit override, then `PATH`, then absolute prefixes — not by `command -v` alone — and the skip is announced on stderr, never silent.** Measured 2026-08-21 on the Linux workstation, where ggshield 1.53.0 is installed and authenticated at `/home/linuxbrew/.linuxbrew/bin/ggshield`: `zsh -i -c` resolves it, while `zsh -l -c`, `ssh host '<cmd>'`, cron and `env -i sh` all report NOT-ON-PATH, because that prefix reaches `PATH` only through `.config/.zshrc.d/6_path.zsh`, which interactive zsh alone sources. The absent case still exits 0 — a machine lacking ggshield must be able to commit the change that installs it — but it now says so twice on stderr

**Before** editing the pre-commit hook **on** `scripts/pre-commit-hook.sh`, read `ai-config/docs/knowledge/dotfiles-testing-toolchain.md` § `Pre-commit hook: make lint and the ggshield actor-boundary resolution`.

`docs/` and `.github/` are **not** wholesale-inert: `make lint`'s `SHELL_FILES` walk is recursive, so a `.sh` file anywhere in the repo — including `docs/gen.sh` or `.github/scripts/foo.sh` — is linted by `make test` and must still trigger the suite.

**Before** changing the inert-path set **on** `scripts/pre-push`, read `ai-config/docs/knowledge/dotfiles-testing-toolchain.md` § `Pre-push hook: fail-closed inert-path set`.

**Worktree compatibility requirement:** `scripts/pre-push` must resolve repo root with `git rev-parse --show-toplevel` first, and use `git rev-parse --git-common-dir` parent only as a fallback. **Git env strip requirement:** `scripts/pre-push` must `unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE` before invoking `make test`, and that line must stay **below** the range-resolution loop, which legitimately needs the git environment. Git exports `GIT_DIR` into the hook only when the push originates from a worktree; without the strip, every suite that builds a git fixture inherits it and `git -C <fixture>` silently operates on the leaked repo instead — measured at 90 failures, with the local test gate effectively absent for the standard worktree workflow.

**Before** editing repo-root resolution **on** `scripts/pre-push`, read `ai-config/docs/knowledge/dotfiles-testing-toolchain.md` § `Pre-push hook: worktree root resolution and git env strip`.

**Direct-to-master guard:** `scripts/pre-push` refuses a push whose `remote_ref` is `refs/heads/master` when the diff carries an executable-class path — `*.sh`, `*.bash`, `*.bats`, `*.zsh`, `Makefile`, and the extensionless `scripts/pre-push` / `scripts/commit-msg`. Why: `.github/workflows/ci.yml` triggers on `pull_request` only, so a code change pushed straight to master is validated by nothing. Measured 2026-09-11 over 30 days — 263 direct-to-master commits, of which 254 are docs-only and permitted and 3 are `renovate.json` which `git-workflow.md` also permits, leaving 5 genuine code pushes, all from a single session. The verdict **accumulates in a flag inside the stdin loop and is read after it**, never `exit`ing mid-loop, for the same reason the existing range resolution drains every ref line: one push can send a real branch and a deletion together. A docs-only commit stacked on an unpushed executable-class commit is refused, correctly — both commits would reach master. Verified end-to-end against a real `git push` rather than the bats harness: a `README.md`-only commit pushed to master from a branch still carrying an unpushed `deploy.sh` was refused naming `deploy.sh`, while the same commit from a clean base landed. If a docs push is refused and names a file you did not touch in that commit, check `git diff --name-only <remote-sha>..HEAD` before assuming the guard is wrong. **Twelve tests in `tests/scripts/pre_push.bats` push to a feature ref deliberately — do not switch them back to master.** Their subject is the inert set (does this path make the suite run), not master policy; they named `refs/heads/master` only because that is what the harness author typed.

**Before** editing the direct-to-master guard **on** `scripts/pre-push`, read `ai-config/docs/knowledge/dotfiles-testing-toolchain.md` § `Pre-push hook: direct-to-master guard (executable-class paths)`.

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

- The tracer enables tracing through `BASH_ENV`, which non-interactive bash subprocesses inherit, so their trace lines were already being collected and then discarded by a predicate that globbed only `config/` and `lib/`.
- **Before** changing the instrumented file set **on** `scripts/run-bash-coverage.sh`, read `ai-config/docs/knowledge/dotfiles-bash-coverage.md` § `Instrumented set: git ls-files derivation and the scripts/ history`.
- That was 13 of `config/profiles.sh`'s 15 lines and 8 of `lib/helpers.sh`'s. - **Pure-argument backslash continuations** — a continuation line whose only content is more arguments to the command the backslash opened.
- **Before** changing what counts as a coverable line **on** `scripts/run-bash-coverage.sh`, read `ai-config/docs/knowledge/dotfiles-bash-coverage.md` § `Denominator counts commands, not source lines (heredocs, python -c, arrays, continuations)`.
- **The denominator is the union of the static heuristic's coverable-line count and whatever the trace file actually contains for that file, never the heuristic alone.** This is what makes `covered <= coverable` hold by construction rather than by luck — every traced line is by definition a member of the union, so it can never exceed it. A wrongly-excluded line therefore raises the denominator (and the numerator, since the trace hit it) rather than silently lowering the percentage; an over-matching exclusion rule can never manufacture a higher score. **Read it beside the ratio from the same run, never a ratio from another one.**
- **Before** changing the coverable/covered accounting **on** `scripts/run-bash-coverage.sh`, read `ai-config/docs/knowledge/dotfiles-bash-coverage.md` § `Denominator is the union of the heuristic and the real trace`.

- **Before** publishing a coverage figure, or editing **on** `scripts/run-bash-coverage.sh`, read `ai-config/docs/knowledge/dotfiles-bash-coverage.md` § `covered > coverable is now a hard exit; publishing and reading the figure`.

### Test Seams

- **the `_OVERRIDE_VAR` seam idiom** (`local _file="${_OVERRIDE_VAR:-...}"`)

**`_RUSTUP_INIT_URL` / `_RUSTUP_INIT_SHA256` / `_RUSTUP_INIT_BIN` / `_OVERRIDE_CARGO_BIN_DIR`
(`lib/linux_ubuntu.sh`'s `_install_rustup_rs`) exist because every test runs against a fake
`HOME` with no `~/.cargo/bin/rustup`, so all of them would otherwise enter the install path
and reach the network** — `tdd.md` E2, a test whose _failing_ branch touches the outside
world. `_OVERRIDE_CARGO_BIN_DIR` selects the directory the idempotency guard reads, making
both "already installed" and "absent" reachable without a real toolchain.

- **`_RUSTUP_INIT_URL`/`_RUSTUP_INIT_SHA256`/`_RUSTUP_INIT_BIN`/`_OVERRIDE_CARGO_BIN_DIR`** (`_install_rustup_rs`)
  There is no `sha256sum` mock and there must not be one: supplying the expected digest keeps the real check running, so a mismatch is genuinely exercised in both directions. A digest taken over a separate fixture file the mock never copies cannot match, so the success-path test computes its digest over `MOCK_CURL_STDOUT`'s exact bytes.

- **`_OVERRIDE_NVIDIA_GPU_PRESENT`/`_OVERRIDE_NVIDIA_KEYRING`/`_OVERRIDE_NVIDIA_LIST`** (`_install_ubuntu_nvidia`)

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

- **`brew_install_cask` / `brew_cask_installed`** (`lib/helpers.sh`)

- **`config/profiles.zsh`** (`the legacy identity oracle`)
  `lib/detect_env.sh` derives the identical eight variables on the bash side; `tests/zshrc.d/ cross_shell.bats` asserts both shells produce the same `PROFILE`/`HAS_*` set for every table key, which is the property the pre-existing test suite could not check because its own oracle was derived from the same wired-only table it was testing.

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



- **`config/profiles.zsh` vs `lib/detect_env.sh`** (`export` vs `readonly` scope)

- **`_OVERRIDE_HOMEBREW_PREFIX_ARM` / `_OVERRIDE_HOMEBREW_PREFIX_INTEL`** (`.config/.zshrc.d/5_general.zsh`)
  As with the gnubin override pair, the real prefix directories (`/opt/homebrew`, `/usr/local/opt`) exist on any provisioned mac, so a test that forgets to point these at a nonexistent path short-circuits the guard and silently asserts nothing — drive both "present" and "absent" through the override, never through the real filesystem.

- **`_OVERRIDE_KEYCHAIN_BIN`** (`.config/.zshrc.d/5_general.zsh`)
  Without it a regression test could only fail on a machine that has keychain installed, which is neither CI nor macOS, so the test would pass vacuously exactly where it runs most often. Measured 2026-08-16 on the Linux workstation: 16 agents pinning the suite's pipe (4 tests × 4 keychain calls) and 161 accumulated since 2026-07-28, one of which the operator's own keychain pidfile had adopted as the login agent. macOS and CI were never affected only because the Linux branch names an absolute `/usr/bin/keychain` that neither has — not because the defect was absent there.

- **`_OVERRIDE_CURRENT_LOGIN_SHELL`** (`lib/helpers.sh`'s `_current_login_shell`)
  Measured: the three end-to-end `run_doctor` tests stub every sub-check by name, so `_doctor_check_login_shell` must be stubbed there too or it reads the real account mid-suite. The old code checked neither rc and then logged `Changed default shell to ${ZSH_PATH}` unconditionally, so a full provision reported success over a shell it had not changed — found only when the operator logged in and got a bash prompt.

- **`_OVERRIDE_GNUBIN_ARM`/`_OVERRIDE_GNUBIN_INTEL`** (`install_make_macos`)
  Unlike most seams here these are read unconditionally rather than only under test — a stray export changes real shell `PATH`, which grants no capability beyond setting `PATH` directly but is worth knowing.

- **`_OVERRIDE_GNUBIN_LINUX`** (`.config/.zshrc.d/6_path.zsh`)
  See [ADR-0031](docs/adr/0031-gnu-coreutils-precedence-on-resolute.md) for why the install is gated on `RESOLUTE` (Ubuntu 26.04) while this `PATH` prepend is not — it is gated only on `[[ -d ... ]]`.

- **`_OVERRIDE_DOCKER_BIN`** (`.config/.zshrc.d/6_path.zsh`)
  It is read unconditionally inside the `HAS_DOCKER` block, not only under test — a stray export appends a different directory to interactive `PATH`, which grants nothing beyond setting `PATH` directly. Measured 2026-09-10: `docker`, `kubectl` and the three credential helpers are also symlinked into `/usr/local/bin`; `docker-compose`, `docker-compose-v1`, `docker-index` and `com.docker.cli` resolve only through this directory. The actor that loses them is a non-interactive login shell (`zsh -l -c`) — cron, launchd and `ssh host '<cmd>'` read neither `.zprofile` nor `.zshrc`, so they never had the entry — and nothing in this repo invokes any of the four that way on macOS.

- **`GGSHIELD_BIN` / `GGSHIELD_FALLBACK_PATHS`** (`scripts/pre-commit-hook.sh`)
  `GGSHIELD_FALLBACK_PATHS` is a space-separated candidate list, consulted only when `PATH` resolution fails, and it is env-settable **solely** so a test can reach the genuinely not-found branch — on any machine that has ggshield the hardcoded prefixes always resolve, which makes that branch otherwise unreachable. Tests must drive absence through these seams and never by editing `PATH`.

- **`LEDGER_BIN`** (`lib/workflows.sh`'s `ledger_write_entry`)
  Resolution order is `LEDGER_BIN` (if executable), then `command -v ledger`, then the `${HOME}/.local/bin/ledger` fallback — so a seam that only redirects `HOME` cannot force resolution to a fixture, because `command -v` runs first and wins on any machine that already has a real `ledger` on `PATH`. A `HOME`-only seam would therefore pass on the Studio and in CI — cheap to run, uninformative — and silently write to the real ledger on `workstation`/`claude`, where the binary actually lives. `tests/mocks/ledger` closes this because it is a `PATH`-prepended mock: it wins the resolution race before `command -v` ever reaches the real binary, regardless of actor, which is why it is required on every assertion touching `ledger_write_entry` rather than a convenience.

- **`_OVERRIDE_LIB_TRAP_SCOPE`** (`scripts/check-lib-exit-traps.sh`)
  That is what lets the suite drive every verdict — un-allowlisted trap, allowlisted count, subshell trap still reported, count change, empty scope, unresolvable base — without ever mutating real `lib/`, which is the only alternative and would leave the tree dirty mid-run for any concurrent session. The seam grants nothing: it redirects a read-only scan to a directory the caller can already read.

- **`_OVERRIDE_BATS_BIN`** (`scripts/run-bash-coverage.sh`)
  Tests must drive absence through this variable, never by editing `PATH`: on `ubuntu-latest` bats lives in `/usr/bin` alongside bash, grep, sed and mktemp, so removing the directory that contains it removes the toolchain — the same "delete a directory to delete one binary" defect that broke three tests on this branch and is documented for `tests/mocks` in `shell.md`. Both halves of a seam must land in the same commit.

- **`_OVERRIDE_RUN_TMPDIR_ROOT`** (`lib/workflows.sh`'s `_dotfiles_run_tmpdir_setup`)
  **`_OVERRIDE_RUN_TMPDIR_ROOT` is read at exactly one site, `lib/workflows.sh:106`, and is read unconditionally in production, not only under test — the same shape as `_OVERRIDE_GNUBIN_ARM`/`_OVERRIDE_GNUBIN_INTEL` above.**

- **`_PROFILES_LOADED`** (`lib/detect_env.sh`, `lib/helpers.sh`)
  `detect_env()` sets it to `0` unconditionally on entry, then to `1` only after `config/profiles.sh` sources cleanly _and_ `declare -p PROFILE_MAP PROFILE_CAPS PROFILE_LEGACY` confirms all three arrays exist. The seam is never `export`ed, and that non-export is **not** what makes it safe — an environment-supplied value defeats the check entirely (measured: `env _PROFILES_LOADED=1 PROFILE=mac_workstation <the branch>` reports PASS). What actually protects it is the unconditional `=0` on entry to `detect_env`, combined with `detect_env()` always running before `run_doctor` (`setup_env.sh:61`, then the dispatch at `:69`). Measured: with the table unreadable and `PROFILE=mac_workstation` inherited, a pre-sentinel check reported PASS over a machine whose identity table never loaded.

- **`_AWS_GPG_BIN`/`_AWS_PKGUTIL_BIN`/`_AWS_KEY_PATH`** (`_aws_verify_zip`/`_aws_verify_pkg`)
  `_AWS_KEY_PATH` defaults to the repo's vendored `keys/aws-cli-team.asc` and lets a test point at a fixture key instead; without it only the real vendored key could ever be exercised, so the fingerprint-mismatch and key-expiry branches — the latter also read by `_doctor_check_aws_key_expiry` — would be unreachable. `DOTFILES_REPO_ROOT` resolves the same expression at **source time**, which is the only moment a relative `BASH_SOURCE[0]` is guaranteed to mean anything; It is a plain assignment rather than a `${VAR:-}` self-guard: a guard was written first and measurement retired it, since a re-source is either absolute — which resolves correctly from any cwd, verified from `/` — or relative, which cannot locate `lib/constants.sh` after a `cd` at all. The two regression tests at the foot of `tests/setup_env/developer.bats` reproduce the production actor deliberately — `source ./lib/...` relatively from the repo root, then `cd` away — and assert on the **post-import** failure (`signature did not verify against the vendored key`) rather than on the absence of the import failure, since an absence is equally satisfied by the function never running (`behavior.md` E5).

- **`_AWS_BIN`** (`install_aws_tools`)
  **`_AWS_BIN` (`lib/developer.sh`'s `install_aws_tools`) is load-bearing on this development machine specifically, not only in the abstract.**

- **the cadence seams** (`scripts/cadence-notify.sh`)

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

- **the heartbeat contract** (`last-run.json`)
  `_doctor_check_cadence` prefers the written value and **names its source** — `(max 3d, from heartbeat)` versus `(max 8d, default — heartbeat carries none)` — so a fallback is never mistaken for a reading. `doctor` renders the three classes distinctly and a test asserts pairwise inequality — because every other test asserted only that its own branch fires, so a reader rendering `held` as a fault would have passed the whole suite.
- **`findings` is a count of stdout lines, and it is only as good as the detector's discipline.** The wrapper cannot distinguish a finding from a progress banner, so the contract is that stdout carries findings one per line and nothing else, while **stderr carries the diagnosis** — captured separately, surfaced in the push under `Cause:` on the incomplete path and `Diagnostics:` on the held path, and never counted. **That stderr is published**: it is POSTed to the ntfy endpoint, capped at the last 20 lines, so a detector must not print credentials, tokens, or environment dumps there. The second is the damaging one — it fires when nothing is wrong — and it was invisible from this side, because the only heartbeat available here came from a run that had drift.

- **the plist `PATH`** (`cadence.plist.template`)
  **The plist's `PATH` is the agent's whole world, and every detector dependency must be on it.** `ledger` lives in that first entry, which the plist did not originally carry — `lib/workflows.sh`'s `ledger_write_entry` carries the same fallback, so the repo already knew — while the plist as first written named only the two Homebrew prefixes, after `gh` and `python3`. Verify the live file rather than the template after any change here:

- **ntfy delivery** (`_rhn_notify`)
  Credentials go in on **stdin** via `curl -K -`, never `-u`, because argv is readable by any `ps`; and a credential containing a **newline is refused rather than escaped**, since curl's config format is line-oriented and everything after a line break is parsed as further directives.

- **the pyenv-rehash and cargo-tools seams** (`lib/helpers.sh`)

- **`_OVERRIDE_PYENV_ROOT`** (`_pyenv_ansible_venv_bin`, `install_pyenv_rehash_hook`)
  A `HOME`-only redirect does not isolate any of them: `PYENV_ROOT` sits ahead of the `HOME` fallback in that chain, and pyenv's own `init` exports it into every interactive shell, so a test's real `PYENV_ROOT` (if inherited) would outrank a fixture `HOME` and the function would read the operator's live `~/.pyenv`.

**`_CARGO_BIN` (`install_cargo_tools`, `lib/developer.sh`) is exported to a recording mock by `tests/helpers/common.bash`'s `load_mocks`, not left to a test's discretion.** Resolution order is `_CARGO_BIN` (if executable), then `${HOME}/.cargo/bin/cargo`, then `command -v cargo`, checked first and unconditionally — so without the default export, any suite calling `load_mocks` could fall through to a real `~/.cargo/bin/cargo` and compile all eight `CARGO_TOOLS` pins for real (`tdd.md` E2). A test exercising the other two resolution branches deliberately unsets it and is responsible for its own isolation from there.

**`_RELEASE_BIN_DIR` (`_install_pinned_release_binary`, `lib/linux_ubuntu.sh`) and `_TFENV_LINK_DIR` (`_install_ubuntu_tfenv`, same file) both default to `/usr/local/bin` and both exist for the same reason: `tests/mocks/sudo` execs real commands.** Neither function's `sudo install`/`sudo ln` is mockable by stubbing `sudo` alone — a real, unwritable-looking `/usr/local/bin` still gets a real write once `sudo` execs through. Every test pointing at either function's install path sets the corresponding directory seam to a scratch directory the test owns, so no `sudo` branch is ever taken.

- **`_RELEASE_TMP_ROOT`** (`_install_pinned_release_binary`)

- **`_TFLINT_URL`/`_TFLINT_SHA256`/`_TFSEC_URL`/`_TFSEC_SHA256`** (`_install_ubuntu_tflint`/`_install_ubuntu_tfsec`)

- **`_TFENV_ROOT` / `_TFENV_REPO_URL`** (`_install_ubuntu_tfenv`)

- **`_PWSH_BIN` / `_PWSH_PROBE_TIMEOUT`** (`_pwsh_probe_runs`, `lib/linux_ubuntu.sh`)
  Tests drive three states through `_PWSH_BIN`: a stub that exits 0 (installed and working), a stub that exits non-zero (installed but broken), and a nonexistent path (not installed at all) — the probe tests that `pwsh` *runs*, not merely that a `.deb` was downloaded, so all three must be reachable without a real PowerShell install. Reaching it requires a PATH scoped to a directory holding no `timeout`, and a stub written with an **absolute** `#!/bin/bash` shebang — a `#!/usr/bin/env bash` stub exits 127 under that PATH because `env` must resolve `bash` through it too (measured rc 127 on macOS, `workstation` and `claude` alike). The pair must cover both directions, since a one-sided test passes vacuously under the opposite mutation.

- **`_DOCTOR_PROBE_TIMEOUT`** (`_doctor_check_dev_tools`)

- **`_CRATES_API`** (`_check_one_cargo_version`)

- **Claude plugin provisioning** (`_OVERRIDE_CLAUDE_SETTINGS`, `_CLAUDE_GUARD_GIT`, `tests/mocks/claude`)

`_OVERRIDE_CLAUDE_SETTINGS` points every reader above at a fixture instead of `${HOME}/.claude/settings.json`, the real ai-config-managed file. `load_mocks` (`tests/helpers/common.bash`) exports it by default, pointed at a **per-test copy** of `tests/fixtures/claude-settings.json` under `BATS_TEST_TMPDIR` — never the tracked fixture directly. That copy is load-bearing rather than a convenience: `tests/mocks/claude`'s `MOCK_CLAUDE_EDIT_SETTINGS` mode appends a newline to whatever `_OVERRIDE_CLAUDE_SETTINGS` names (to drive the write guard), so pointing it at the tracked file would let any test that forgets to override it again dirty the working tree with an `M tests/fixtures/claude-settings.json` nobody asked for. Every `run_update`/`run_setup_user` test runs under a redirected `HOME` with no settings file at all, so without this default they would all hit the manifest's rc 1 and FAIL for a reason unrelated to what they test — the same shape as the pre-existing `MOCK_PYENV_WHICH_STDOUT`/`_CARGO_BIN` defaults above.

- **`_CLAUDE_GUARD_GIT`** (`_claude_settings_git_state`)
  It exists because `tests/mocks/claude`'s sibling, `tests/mocks/git`, answers almost every subcommand with empty stdout and exit 0 — a mock built for callers that only care whether a `git` call succeeded, not for one whose whole job is to read real repository state (`shell.md`'s "a PATH mock shadows the binary your production code needs"). Guard tests resolve a **real** git with the mocks directory stripped from `PATH` (the same `_clean_path` filter idiom `tests/scripts/unit.bats` already uses) and symlink it into a private shim dir, then export that path — so the shadowing mock never intercepts a guard call, while every other `git`-shaped call in the same test file still hits the fast, harmless mock.

- **`tests/mocks/claude` mock modes** (`MOCK_CLAUDE_*` env vars)
  `tests/mocks/claude` gained five new modes for this: `MOCK_CLAUDE_PLUGINS_LIST_JSON` and `MOCK_CLAUDE_MARKETPLACE_LIST_JSON` are the `--json` payloads `_claude_installed_user_ids`/`_claude_registered_marketplaces` parse (default `[]`, i.e. nothing installed/registered); `MOCK_CLAUDE_FAIL_ARGS` fails any invocation whose full argv contains it as a substring (e.g. `"plugins install"` fails only installs, not the list/marketplace-add calls); `MOCK_CLAUDE_FAIL_ON_CALL=<n>` fails only the *n*th invocation whose argv is exactly `plugins list --json`, counted in a file under `BATS_TEST_TMPDIR`, so `run_update`'s re-list (after `setup_claude_plugins`'s own list call already succeeded) can be made to fail on its own; `MOCK_CLAUDE_EDIT_SETTINGS=<verb>` (`install` or `update`) makes only that verb touch `_OVERRIDE_CLAUDE_SETTINGS`, described above.

- **the stdin redirect and IFS tab-collapse in claude plugin provisioning** (`setup_claude_plugins`)
  **`IFS=$'\t' read` collapses a run of adjacent tabs**, because bash always treats tab as "IFS whitespace" regardless of what else `IFS` holds — an empty middle field (an empty marketplace name, or a git-state line's repo field when the file isn't tracked) would otherwise shift the next field left rather than staying empty. `_claude_manifest_split_line` exists to avoid this for manifest lines, splitting by parameter expansion instead of `read`; `_claude_settings_git_state` sidesteps the same hazard for its own three-field lines by never emitting a genuinely empty field — the repo position is a literal `-` placeholder (`untracked\t-\t<path>`, `unknown\t-\t<path>`) rather than an empty string, so `_claude_settings_guard_check`'s `IFS=$'\t' read -r _bs _br _bp` (which does *not* use the split-line helper) always sees three real fields.

**`_OVERRIDE_CLAUDE_PLUGIN_CACHE` (`_claude_plugin_cache_dir`, `lib/helpers.sh`) points the plugin node-path check and repair at a fixture instead of `~/.claude/plugins/cache`.** Both test files set it in `setup()`, not per test: the repair rewrites files, so a test that forgot it would edit the operator's real plugin cache (`tdd.md` E2). What it guards: context-mode writes `process.execPath` into its cached `hooks/hooks.json` and `.claude-plugin/plugin.json` on Linux ([mksglu/context-mode#1090](https://github.com/mksglu/context-mode/issues/1090)). Under linuxbrew that is the versioned `Cellar/node/<ver>/bin/node`, so `brew upgrade node` deletes it: every hook then fails with `/bin/sh: 1: <path>: not found` and the MCP server does not start. The plugin cannot heal itself, because its repair runs only when that MCP server starts. Measured 2026-09-19 on `claude` (26.8.2) and `workstation` (26.4.0, all six cached versions); `studio` was clean, since upstream skips the rewrite on macOS. The `plugin-node` update section repoints each dead pin at the keg's `opt/` link. The plugin does not rewrite a cache it has already normalized, so the `opt/` path holds until a plugin update extracts a new version. That version is then pinned to whichever versioned node is current, so a later node upgrade needs the repair again. A node upgrade outside `-t update` does not run the repair: `brew bundle` under `-t setup` or `-t developer`, a manual `brew upgrade`, or Claude Code's own background plugin update. `doctor` is the backstop that names each dead pin. Delete the section, the doctor check and the seam once upstream stops writing versioned paths.
- **Before** writing or reviewing a test that drives any seam here, read `ai-config/docs/knowledge/dotfiles-test-seams.md` § `Test seam idiom and override pattern`.

### Mock Pattern

**Before** looking up a `MOCK_*` var **on** `tests/mocks/`, read `ai-config/docs/knowledge/dotfiles-bats-test-infrastructure.md` § `Mock Pattern full reference pointer (superseded by this section)`.

**Before** asserting on state from a mocked call **on** `tests/mocks/ln`/`chmod`/`mv`/`cp`/`tee`, read `ai-config/docs/knowledge/dotfiles-bats-test-infrastructure.md` § `Mock Pattern: pass-through mocks (ln, chmod, mv, cp, tee)`.

**Before** placing a pyenv mock **on** `setup_ansible()`, read `ai-config/docs/knowledge/dotfiles-bats-test-infrastructure.md` § `Mock Pattern: env -i strips PATH (pyenv mock placement) -- CLAUDE.md addendum`.

Production calls curl as `-fsS -o <file> <url>` and `-fLo <file> <url>` (`developer.sh:105`), so the mock's arg loop recognizes any `-[a-zA-Z]+` cluster: an `f` anywhere in it sets the fail-mode flag, and a cluster **ending in `o`** takes the next argument as the `-o` target — a bare `-o` alone would silently never capture `-fLo`'s target. `MOCK_CURL_HTTP_STATUS` simulates curl's `-f`/`--fail` behavior (fail on HTTP error) without a real network call: it only takes effect when `MOCK_CURL_EXIT` is unset, an f-bearing form was actually passed, and the status value matches `^[0-9]+$` and is `>= 400` — the numeric gate runs before the comparison per `shell.md`'s non-numeric-operand pitfall, so a garbage status value falls through to success rather than an undefined comparison. `MOCK_CURL_EXIT` is the older, unconditional knob and always wins when set.

**Before** adding a curl invocation shape **on** `tests/mocks/curl`, read `ai-config/docs/knowledge/dotfiles-bats-test-infrastructure.md` § `Mock Pattern: tests/mocks/curl short-option cluster parsing`.

On success, the mock writes `MOCK_CURL_STDOUT` to the target file **and still also emits it on stdout** — real curl with `-o` writes only to the file and stays silent on stdout. This is kept deliberately because the callers that never pass `-o` (the `whats-new*.sh` scripts, `_fetch_github_latest` in `lib/workflows.sh`, `install_homebrew` in `lib/macos.sh`) require the stdout emission from the same mock, and no current production caller both passes `-o` and consumes stdout — verify that still holds before removing the dual emission.

**Before** changing its `-o` write-ordering **on** `tests/mocks/curl`, read `ai-config/docs/knowledge/dotfiles-bats-test-infrastructure.md` § `Mock Pattern: tests/mocks/curl -o write ordering (deferred success write)`.

### MAKEFLAGS and Stdout Partition

**Before** relying on directory-line suppression **on** `Makefile:1`, read `ai-config/docs/knowledge/dotfiles-bats-test-infrastructure.md` § `MAKEFLAGS: --no-print-directory directive and its GNU Make version limit`.

So any test that captures and measures `make` output must explicitly account for it — tests fall into two categories: Use it only for that — on 4.3 it strips the one mechanism that works and leaves the inert file directive, so a case that merely wants an exact value must be **guarded**, not measuring. Both categories must exist in the test suite.

**Before** writing a test that captures `make` output **on** a `tests/*.bats` `make -C` call, read `ai-config/docs/knowledge/dotfiles-bats-test-infrastructure.md` § `MAKEFLAGS: exported env var; guarded vs measuring test partition`.

**Before** adding a `make -C` call in a test **on** `tests/scripts/makefile_lint_scope.bats`, read `ai-config/docs/knowledge/dotfiles-bats-test-infrastructure.md` § `MAKEFLAGS: partition enforcement test and the git ls-files domain`.

A line scanner can only see what is on the invoking line.

**Before** adding a `$(MAKE)` recursive call **on** `Makefile`, `powershell/Makefile`, read `ai-config/docs/knowledge/dotfiles-bats-test-infrastructure.md` § `MAKEFLAGS: known gap -- recursive sub-make and -w invisible to the scanner`.

## Committing Work

Invoke `caveman:caveman-commit` skill to generate the commit message before running `git commit`. Full format and rules in `~/.claude/CLAUDE.md`.

## Key Conventions

- Machine roles are now driven by the **profile/capability model** in `config/profiles.sh` — prefer `HAS_*` vars over raw hostname patterns for new code
- Measured on `claude` 2026-09-12 with toolkit 1.20.0 already installed; `workstation` had been configured by hand and so never surfaced it.
- **Before** editing GPU provisioning **on** `_install_ubuntu_nvidia`, read `ai-config/docs/knowledge/dotfiles-conventions.md` § `GPU provisioning as the HAS_* exception (not a capability)`.
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
- **Before** validating a change **on** `.zshrc`/`.config/.zshrc.d/`, read `ai-config/docs/knowledge/dotfiles-conventions.md` § `zsh -i -c 'exit' after .zshrc changes, and the worktree caveat`.
- **Before** resolving a path via `$0` **on** a zsh startup file, read `ai-config/docs/knowledge/dotfiles-conventions.md` § `$0 resolution in zsh startup files (${0:A:h} pitfall)`.
- Adding `_update_record_start/end "new-section"` in `run_update()` without also adding `"new-section"` to this array means the section is tracked internally but never printed. Both must be updated together — `zsh-autosuggestions` (added 2026-08-31) sits right after `oh-my-zsh` in the array for exactly this reason.
- **Before** adding a `run_update` section **on** `_UPDATE_SECTION_ORDER`, read `ai-config/docs/knowledge/dotfiles-conventions.md` § `_UPDATE_SECTION_ORDER coupling`.
- **`scripts/sync_git_repos.sh`** replaces the old rsync-only sync script (`scripts/synch_git-repos.sh`, deleted). Two independent modes: git-native fetch/pull/push for `personal/` repos + `state-ledger` (safe on any of the three dev machines — never force-pushes, never auto-merges a diverged repo; dirty does not block a safe push, only a pull), and studio-only rsync push for legacy/no-git-access directories + a full-tree ratna backup. Runs automatically as part of `-t update` (`git-repos`/`legacy-rsync` sections in `_UPDATE_SECTION_ORDER`); `--git-only`/`--legacy-only`/`--dry-run`/`-h` for standalone use, where `--dry-run` suppresses every outbound write and `--git-only` combined with `--legacy-only` is rejected as ambiguous rather than resolved. See `docs/superpowers/specs/2026-07-18-sync-git-repos-design.md` for the full design and the dirty/ahead/behind decision table. **Never invoke this script (or `sync_legacy_dirs`/`sync_git_repos` directly) unmocked outside the BATS test harness** — it performs real `git push`/`rsync --delete` over SSH against real hosts, and `_is_legacy_sync_host` triggers on the real `hostname -s` of whichever machine runs it.
- **`git-hooks` section coupling:** same `_UPDATE_SECTION_ORDER` trap applies to the hook-install sweep (`lib/git_hooks.sh`) — adding `_update_record_start/end "git-hooks"` in `run_update()` without also adding `"git-hooks"` to `_UPDATE_SECTION_ORDER` means the section is tracked internally but never printed, with no error. Separately: the sweep's post-condition check reads the **installed hooks directory** (`.git/hooks/` or the repo's actual hook path), never `scripts/` — a repo whose hooks were installed by a route other than the Makefile (e.g. `ledger init`) must still read as satisfied. **Both** call sites must branch on it: `run_update` maps 2→0 for `_update_record_end` then calls `_update_warn` (the same shape `git-repos` and `legacy-rsync` use), and `run_setup_user` distinguishes rc 1 ("reported failures") from rc 2 ("gaps or a pinned core.hooksPath") rather than treating any non-zero as failure. **The target is resolved by `_git_hooks_target_dir`, not assumed to be at the root:** the root Makefile first, else exactly one tracked `*/Makefile` one level down (terraform_ansible keeps it in `ansible/Makefile`); two or more is reported as `:ambiguous` and never run, and a failed `git ls-files` is reported as `:unreadable` rather than as a missing target. This matters more than a mislabel, because the completeness check reads presence and the executable bit only: a stale `cp`-installed hook passes it, and only re-running the recipe refreshes it.
- **Before** editing the `git-hooks` section **on** `_git_hooks_target_dir`, read `ai-config/docs/knowledge/dotfiles-conventions.md` § `git-hooks section coupling and _git_hooks_target_dir`.
- `install_ubuntu_packages` therefore captures the rc rather than using `|| return 1`: **only rc 1 aborts**, because a bare guard would kill a whole fresh-machine bootstrap over one briefly-unavailable upstream formula, while unchecked calls report success over packages that never landed.
- **Before** calling **on** `_install_ubuntu_brew_packages`, read `ai-config/docs/knowledge/dotfiles-conventions.md` § `_install_ubuntu_brew_packages tri-state return`.
- **Before** changing the plugin install call **on** `setup_claude_plugins`, read `ai-config/docs/knowledge/dotfiles-conventions.md` § `claude plugins install -s user scope flag`.
- That plumbing command walks upward through parent directories looking for a `.git`, and `~/.oh-my-zsh` is itself a git checkout — so a non-clone plugin install (dropped in by hand, or via a tarball) would resolve to the _parent_ repo's `.git` and `git pull` would silently update oh-my-zsh instead, rendering a permanent `[OK] … no changes` for a plugin that was never actually pulled. A future reader will otherwise "tighten" this to the plumbing form; don't.
- **Before** editing this update section **on** `lib/workflows.sh:672-689`, read `ai-config/docs/knowledge/dotfiles-conventions.md` § `zsh-autosuggestions reported update section`.
- The width is not a number to remember and re-check by hand: `tests/setup_env/update_summary.bats` ("`_UPDATE_SECTION_ORDER`'s longest name always leaves the reason column's 2-space gutter") reads the pad width back out of `lib/update_summary.sh`'s own `printf` format via `grep -oE '%-[0-9]+s'` and asserts `pad - max >= 1` against the array's actual longest entry — so a future section name of 20 characters or more fails this test rather than silently colliding with the reason column, with no width literal to update in the test itself.
- **Before** widening a section name **on** `_UPDATE_SECTION_ORDER`, read `ai-config/docs/knowledge/dotfiles-conventions.md` § `Update summary name column width`.
- It previously ran the tab-completion fetch (`~/.zsh.d/_cht`) as a bare statement after `_update_record_end "cheat.sh" ...` had already closed out the section, so a completion-only failure was invisible — the section reported whatever the binary fetch alone had recorded. Progress banners (`"Updating cheat.sh"`, `"Updating cheat.sh tab completion"`) print **outside** the subshell specifically so they never land in `err_cheat.sh`/`detail_cheat.sh`, which feeds `_update_write_detail_from_err`'s `tail -10` — a banner line in that budget would silently displace real diagnostic content.
- **Before** editing this update section **on** `lib/update_summary.sh`, read `ai-config/docs/knowledge/dotfiles-conventions.md` § `cheat.sh section: both artifacts, both failures FAIL the run`.
- One value in it is a **deliberate non-default, not drift**: `agents.warp_agent.other.auto_approve_bypasses_command_denylist = false` (Warp defaults it to `true`, which makes the `execution_profiles` `command_denylist` inert whenever auto-approve is on — `permissions.rs` then consults only the org denylist, and a personal machine has no org). That key carries `sync_to_cloud: Globally`, so a fleet machine still holding `true` can push it back and Warp will rewrite the file; treat a diff flipping it to `true` as a sync reversion to re-pin, never as an upgrade artifact to accept.
- **Before** reviewing a diff **on** `.warp/settings.toml`, read `ai-config/docs/knowledge/dotfiles-conventions.md` § `.warp/settings.toml Warp-owned symlink and auto_approve_bypasses_command_denylist`.
- An **empty or whitespace-only** value is a real pin, not an absent one: `git config --get` reports it as rc 0 with empty stdout, and git honors it — it disables every hook on the machine. `tests/setup_env/git_hooks.bats`'s `setup()` must neutralize `GIT_CONFIG_GLOBAL`/`GIT_CONFIG_SYSTEM`, because the sweep now reads them — without it the suite fails on any machine that actually has a pin, and since `scripts/pre-push` runs `make test`, that developer cannot push.
- **The pin probe must read `--includes`, and the remedy must name the origin file:** `git config --<scope> --get` defaults to `--no-includes`, but git's own hook resolution traverses includes. `-z` is required rather than the default tab-separated `--show-origin` format (the value may be empty or whitespace-only, and NUL is the only delimiter git will not also emit inside a value), and because command substitution silently drops NUL bytes the pair must be consumed with `read -d ''` off a process substitution, never `$(...)`. The remedy differs by origin: a scope-level `--unset` **cannot** clear a key held in an included file — it exits 5 and the pin survives — so the function emits `git config --file <origin> --unset core.hooksPath` for that case and keeps the scope form only for a key in the scope's own file. Remaining limit: a conditional `includeIf "gitdir:…"` is visible only when git evaluates it from a matching directory, and the probe runs once per sweep rather than once per discovered repo.
- **Before** diagnosing dead git hooks **on** `_git_hooks_hookspath_offenders`, read `ai-config/docs/knowledge/dotfiles-conventions.md` § `Global/system core.hooksPath pin: detection and remedy`.

- **It must be a prepend, not `path+=`.** Both Homebrew prefixes are tested for existence (ARM at `/opt/homebrew/opt/make/libexec/gnubin` and Intel at `/usr/local/opt/make/libexec/gnubin`); the invocation never calls `brew --prefix` because this same file is what puts `/opt/homebrew/bin` on `PATH`, so `brew` is not guaranteed resolvable at that point. The `PATH` prepend for the linuxbrew `coreutils` gnubin directory is gated only on `[[ -d ... ]]`, deliberately not on `RESOLUTE`: the install is release-gated, the `PATH` edit is release-blind, and the ADR records why that asymmetry is intentional rather than a bug to reconcile.
- **Before** editing the `PATH` prepend **on** `.config/.zshrc.d/6_path.zsh`, read `ai-config/docs/knowledge/dotfiles-conventions.md` § `Homebrew make gnubin prepend (prepend, not append)`.

- Because `6_path.zsh` is sourced by interactive zsh only, `make`'s version on a provisioned mac is a function of how the process was started. `Makefile:1`'s `MAKEFLAGS += --no-print-directory` is why — it suppresses on 4.x what 3.81 never printed, so the one documented behavioural difference does not reach these gates. Do not reopen this without re-running that comparison; two designs were written and retired on the assumption it mattered (`specs/2026-08-16-system-wide-gnu-make-design.md` and `specs/2026-08-16-hook-make-resolution-design.md`, both carrying the measurements).
- **Before** assuming which `make` resolves **on** a hook that shells out to `make`, read `ai-config/docs/knowledge/dotfiles-conventions.md` § `Which make an actor resolves (gnubin/actor table)`.

It leads `/usr/bin` in `/etc/paths`, but `/etc/paths` is consumed by `path_helper`, which only **login shells** invoke. cron, launchd and sshd use the compiled constants above and never see it. This is `shell.md`'s PATH-mock pitfall inverted — there the mock shadows production, here production shadows the mock — and any future change that manipulates `PATH` in a hook must route through `_OVERRIDE_GNUBIN_ARM`/`_OVERRIDE_GNUBIN_INTEL` so the harness can point it at the mock dir. `6_path.zsh` also appends `/home/linuxbrew/.linuxbrew/bin` on Linux, and that file is sourced by **interactive zsh only**. The macOS bullet above and this one are the same defect at two severities — there it answers wrong for one tool's version, here it refuses the entry point outright — so treat a tool path placed in an interactive-only rc file as gating whichever actor sources that file, not as a machine-wide fact.

**Before** running it non-interactively on Linux **on** `setup_env.sh`, read `ai-config/docs/knowledge/dotfiles-conventions.md` § `setup_env.sh cannot run non-interactively on the Linux workstation (brew PATH)`.
- **`install_cargo_tools` (`lib/developer.sh`) judges each `CARGO_TOOLS` pin (`lib/constants.sh`) by whether the binary runs (`--help`), never by the version string cargo reports, and repairs a non-runnable install with `--force`.**
- `-t update --brew-only` reaches the `cargo-tools` section deliberately — a brew upgrade of a shared library is exactly what can break a linked binary the pin already satisfies by version, so the repair path has to run there too, not only under a full update.
- A first run, or a pin bump in `CARGO_TOOLS`, compiles every `absent`/`older` crate from scratch, which can take tens of minutes — stated rather than hidden, since `workstation` had only two of the eight pins installed before this landed.
- **Before** editing or testing **on** `install_cargo_tools`, read `ai-config/docs/knowledge/dotfiles-conventions.md` § `install_cargo_tools judges by runnability, not version string`.
- It clones `~/.tfenv` if absent, symlinks `tfenv`/`terraform` into `/usr/local/bin` only when neither name is already a regular file or a foreign symlink, and installs `TERRAFORM_VER` only when `~/.tfenv/version` does not exist yet — an operator's chosen version (`workstation` stays on 1.14.9) is never overwritten.
- **Before** editing the tfenv installer **on** `_install_ubuntu_tfenv`, read `ai-config/docs/knowledge/dotfiles-conventions.md` § `terraform on Linux via tfenv, and the checkout guard`.
- **Before** adding a staleness check **on** `run_check_versions`, read `ai-config/docs/knowledge/dotfiles-conventions.md` § `tflint/tfsec staleness gap; CARGO_TOOLS staleness via crates.io`.

## Dependency Automation

Measured 2026-08-23 with config as the only variable: the remote-preset form produced **8 preset errors and 0 extractions**; inlined, **0 errors and 1 extraction**.

**Before** editing **on** `renovate.json`, read `ai-config/docs/knowledge/dotfiles-dependency-automation.md` § `renovate.json inlines the shared preset (private-repo visibility)`.

Do not cite the silent-mode finding as a live constraint without re-reading a current job log.

**Before** changing Renovate config **on** `renovate.json`, read `ai-config/docs/knowledge/dotfiles-dependency-automation.md` § `Renovate confirmed working: pinDigests and auto-merge in production`.

Under silent mode no repo could ever author a PR, so zero was the only reachable value and every "it is not running" verdict built on it was unprovable either way.

**Before** concluding Renovate is inactive **on** a zero-PR count, read `ai-config/docs/knowledge/dotfiles-dependency-automation.md` § `The zero-PR oracle was structurally unfalsifiable under silent mode`.

Measured against all five renderings: only `requirements-ci.txt` matches — the four narrow slices are two-segment names and cannot.

**Before** adding `pip_requirements` **on** `renovate.json`'s `enabledManagers`, read `ai-config/docs/knowledge/dotfiles-dependency-automation.md` § `pip_requirements deliberately absent from enabledManagers`.

**Before** changing Dependabot settings **on** GitHub repo Settings, read `ai-config/docs/knowledge/dotfiles-dependency-automation.md` § `Dependabot: security auto-PRs off, vulnerability alerts on (fleet-wide)`.

- **`automated-security-fixes` is repo-wide — GitHub offers no per-ecosystem toggle.** "Turn Dependabot off for Python" is not expressible; only the whole repo. `DELETE .../automated-security-fixes` returns **422 "Vulnerability alerts must be enabled to configure automated security fixes."**

**Before** toggling Dependabot alerts **on** the GitHub API, read `ai-config/docs/knowledge/dotfiles-dependency-automation.md` § `Dependabot: mechanical details (repo-wide toggle, ordering)`.

**Before** assuming Python gets update PRs **on** `pyproject.toml`, read `ai-config/docs/knowledge/dotfiles-dependency-automation.md` § `Consequence: Python has no automated dependency update path`.

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
