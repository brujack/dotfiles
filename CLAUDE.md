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
│                      #   sync-agent-guidance.sh, list-shell-files.sh,
│                      #   check-lib-exit-traps.sh, sync_git_repos.sh,
│                      #   and the extensionless hooks pre-commit-hook.sh/pre-push/commit-msg
├── LaunchAgents/      # cadence.plist.template — one template, both weekly agents
├── keys/              # aws-cli-team.asc — vendored AWS signing key (_AWS_KEY_PATH default)
├── manifests/         # manifests/dotfiles/*.yaml — state-ledger entity manifests
├── powershell/        # Windows bootstrap: setup_windows.ps1, Pester tests, Makefile
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
`git ls-files | awk -F/ 'NF>1{print $1}' | sort -u` rather than by memory; it has drifted
twice by silent omission (three `lib/` files and four top-level directories, corrected
2026-09-08).

## 10-80-10 Execution Cycle

Sessions in this repo follow the 10-80-10 execution cycle defined in `ai-config` ADR-0009 (with the ADR-0010 wave-dispatch extension):

- **Phase 1 (10%) — Architect.** `brainstorming` → `writing-plans` (emit per-task YAML `yaml-task` blocks with `role`/`model`/`tdd`/`acceptance`/`max_retries`/`files_touched`/`depends_on`/`parallel_group`). Opus role.
- **Phase 2 (80%) — Execute.** `subagent-driven-development` runs iterate-until-green per task; FORBIDDEN list prevents gate cheating; wave-dispatch when `parallel_group` is declared. Sonnet/Haiku per task per the plan.
- **Phase 3 (10%) — Review.** `finishing-a-development-branch` runs the twelve-step gate chain in its own Phase 3 table — `perf-regression` first, `pr-review` second-to-last, the merge/PR step last. Read the order there rather than here: this line named five steps with `pr-review` first until 2026-09-10. Opus role.

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

- `setup_user` — Configs, shells, directory structure, symlinks, GNU make on macOS (`install_make_macos`), GitHub MCP (`setup_claude_mcp`), Claude plugins (`setup_claude_plugins`)
- `setup` — Full machine setup (setup_user + all apps). Flags: `--brew-install`, `--mas-install`
- `developer` — Dev packages + Python/Ansible virtualenv
- `ansible` — Ansible venv setup only (after Python updates)
- `recreate-venv` — Force-delete and recreate a named pyenv virtualenv. Flags: `--venv-name` (default: `ansible`). Runs full pip install when name is `ansible`. **SIGINT/SIGTERM during the rebuild now abort the shell** instead of continuing to a verification error — either way the toolchain is left deleted, since the signal reaches the rebuild child regardless of the trap change. Recover with the same command; if the original invocation carried `--venv-name`, repeat it — a bare re-run rebuilds `ansible` instead, because `recreate_python_venv` gates the `uv sync` on that name.
- `recreate-ruby` — Force-delete and reinstall the pinned Ruby version (`RUBY_VER` in `lib/constants.sh`), reusing `install_ruby()`. **SIGINT/SIGTERM during the rebuild now abort the shell** instead of continuing to `install_ruby()`'s post-install verification error — either way the toolchain is left deleted. Recover by re-running the same command.
- `update` — Update all packages (brew, apt/snap, pip, gems, tools). Supports `--brew-only`, `--pip-only`, `--gems-only`, `--mas-only`, `--claude-only` flags. Prints a structured summary; logs to `~/.dotfiles-update.log`. Also writes a state-ledger entry (advisory, non-fatal). **Exits 1 when any section reports FAIL**; a WARN section still exits 0, preserving the deliberate rc-2 -> 0 mapping in `git-repos`, `legacy-rsync` and `git-hooks`. **SIGINT/SIGTERM now abort the run** rather than being absorbed by `_dotfiles_run_tmpdir_setup`'s former EXIT/INT/TERM trap (deleted). Non-zero has three meanings and only the first records anything — section FAIL, a run-dir creation failure, or an interrupt; see ADR-0027. The five `cd` guards ADR-0027 named as a fourth, recordless case are gone as of 2026-09-01 — see the `zsh-autosuggestions` bullet below. Full internals: `~/git-repos/personal/ai-config/docs/knowledge/dotfiles-update-workflow.md`.
- `doctor` — Active health checks: identity-table load, symlinks, tool presence, credential dir permissions, version drift, global/system core.hooksPath pins, weekly-cadence heartbeats (Studio only). Exits non-zero on any failure
- `check-versions` — Compare pinned versions in `lib/constants.sh` against GitHub latest; exits 1 if outdated. `--update` prompts per-tool to apply updates in-place

**Options:**

- `--dry-run` — log mutating operations (symlinks, installs, mkdir) without executing

## Symlink Strategy

Dotfiles live at the repo root and in the ai-config repo (`.claude/`/`.cursor/`). `setup_env.sh` creates symlinks from `$HOME` into the repos:

- **Repo root** — each dotfile symlinked individually into `$HOME` (e.g. `~/.zshrc → dotfiles/.zshrc`)
- **`.claude/`** — each item symlinked individually into `~/.claude/` from the ai-config repo, except `rules/`, which is never linked, and `projects/`, which the loop skips and then links explicitly (see below).
  Exception: `mcp.json.template` is symlinked as `~/.claude/mcp.json.template` (read-only reference); the live
  `~/.claude/mcp.json` is **generated** by `setup_claude_mcp` via `envsubst` and is not a symlink.
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
- **`setup_env.sh` prereq bypass tests — assert absence, not `status -eq 0`:** Tests for `-t doctor` and `-t check-versions` bypass paths (in `tests/setup_env/unit.bats`) assert `[[ "$output" != *"Homebrew not found"* ]]` without asserting `[ "$status" -eq 0 ]`. Reason: all three take the **same** bypass — `setup_env.sh:13` for `-t doctor`/`-t check-versions` and `:16` for `--brew-install` both set `_REQUIRES_BREW_PREREQ=0` — but `--brew-install` then reaches `setup_env.sh:94`'s `exit 0`, while `-t doctor` / `-t check-versions` call `run_doctor` / `run_check_versions` whose exit varies with mock environment. (This read "terminates cleanly at line 78 (`exit 0`)" until 2026-09-08; there is no `exit 0` at `:78` and never a separate mechanism — the only two are `:94` and `:103`.) Adding `status -eq 0` to the doctor/check-versions tests causes flaky failures.
- **No `set -euo pipefail`** at top-level — conditional installs require non-zero exits to continue.
- **Sourcing guard placement in `lib/`:** where a file carries `[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0`, it goes on the **last line, after all function definitions** — not near the top. The guard's condition is true when the file is sourced, so placing it above the function definitions returns before any function exists and breaks standalone sourcing entirely. Precedent: `lib/git_sync.sh:118` and `lib/legacy_rsync.sh:34` are each the final line of their file. **Not every lib file has one, and the suite does not require it:** measured 2026-09-10, 6 of 13 carry it (`git_hooks`, `git_sync`, `launch_agents`, `legacy_rsync`, `linux_shared`, `linux_ubuntu`), and the bats harness reaches the other seven through `setup_env.sh`, whose own guard is at `setup_env.sh:57`. Re-count with `grep -l '!= "${0}" ]] && return 0' lib/*.sh`. This bullet said every tested lib file must end with the guard, cited `legacy_rsync.sh:28`, and claimed the harness requires it, until 2026-09-10.

### Platform Detection Pattern

The shape used where code branches by OS — for example `lib/detect_env.sh:80` and `.config/.zshrc.d/5_general.zsh:69`. `setup_env.sh` itself contains no such branch, and the exact two-arm form below is illustrative rather than copied from any file (it said "replicated consistently across `setup_env.sh`" until 2026-09-10):

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
GO_VER="1.26"
PYTHON_VER="3.14.6"
RUBY_VER="4.0.5"
```

Update these constants when bumping versions — don't hardcode versions elsewhere.
When a constant is updated, update all other references to that constant across the repo.

### Ruby Version Manager Split

Ruby version managers: **rbenv on Linux** (`lib/linux_ubuntu.sh`); **chruby on macOS** (installed by `Brewfile`, loaded by `.config/.zshrc.d/5_general.zsh`; this said `lib/macos.sh`, which has none, until 2026-09-10). Not interchangeable across platforms. Handled automatically by `install_ruby()`/`install_ruby_tools()` in `developer.sh` — no manual intervention required. Linux build pins `RUBY_CONFIGURE_OPTS="--with-openssl-dir=/usr"` to avoid linking against a Homebrew OpenSSL that breaks gem HTTPS. Full rationale: `~/git-repos/personal/ai-config/docs/knowledge/dotfiles-ruby-version-manager.md`.

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
**Run lint only:** `make lint` — `bash -n` over `SHELL_FILES` (derived by `scripts/list-shell-files.sh`, which emits every tracked file whose first line is a bash/sh shebang — 107 files, measured 2026-09-08, including the `tests/mocks/` fixtures and the two extensionless hooks), `zsh -n` over `ZSH_FILES` (12 tracked files: `.zsh`/`.zsh-theme`/`.zshrc`/`.zprofile` plus `config/profiles.sh`, named explicitly), then shellcheck at default severity for `SHELL_FILES` and `--severity=warning` for `.bats`. `ZSH_FILES` is derived from `git ls-files`; `SHELL_FILES` is content-derived rather than pathspec-derived, for the reason in the ShellCheck section below. Both refuse to report a pass on an empty list.

`config/profiles.sh` is a bash file — it stays in `SHELL_FILES` for `bash -n` and shellcheck — and is also the one deliberate entry in `ZSH_FILES`: `config/profiles.zsh` sources it from both `.zprofile` and `1_init.zsh`, so `zsh -n` must parse it too. One file, both parsers, by design; `tests/scripts/makefile_lint_scope.bats` asserts this is the _only_ `SHELL_FILES`/`ZSH_FILES` overlap and that it is actually present in both, so a future accidental overlap is caught and this deliberate one can't silently disappear. The pathspec is duplicated at two independent call sites — `Makefile`'s `ZSH_FILES` and `.github/workflows/ci.yml`'s `lint-macos` job — and both must carry `config/profiles.sh` together; a fix to one alone leaves the other checking a stale set.
**Install hooks:** `make install-hooks` (installs pre-commit and pre-push hooks; run once per checkout)
**Sync agent guidance:** `make sync-agent-guidance` (regenerates `.cursor/rules/global-claude-standards.mdc` from root `CLAUDE.md`'s `@~/.claude/standards/*.md` imports, resolved against the global symlinked standards dir)
**Check agent guidance drift:** `make check-agent-guidance` (fails when generated Cursor guidance is stale)

**The venv is snapshotted before every sync, and that file is the only rollback path.**
`run_update` writes `pip freeze` to `~/.local/share/dotfiles/venv-snapshots/ansible-<UTC>.txt`
before applying the lock, keeping the newest 10. This is not belt-and-braces: `uv sync` prunes
and downgrades, and the pre-sync state is **not reproducible from the lock** — `uv pip install
-r` of the venv's own freeze fails as unsatisfiable, because pip reached that state
incrementally and the cumulative set is unsolvable. Reverting this repo does not restore the
venv. To roll back:

```bash
"$(pyenv which python)" -m pip install --no-deps -r ~/.local/share/dotfiles/venv-snapshots/ansible-<UTC>.txt
```

`--no-deps` is required — the state being restored is one the resolver refuses.

**Environment overrides added by the uv work.** All three exist for a stated reason and
none grants a capability the operator did not already have:

| variable                 | read by                           | why it exists                                                                                                                                                                                                                                   |
| ------------------------ | --------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `UV_BIN`                 | `resolve_uv` (`lib/helpers.sh`)   | operator escape hatch, and the only seam a test can use to drive the "not executable" branch — PATH mocking cannot remove the absolute fallback candidates                                                                                      |
| `UV_FALLBACK_PATHS`      | `resolve_uv`                      | array of prefix candidates. Exists so a test can reach the genuine not-found branch, which is otherwise unreachable on any machine that has `uv`. Env-settable as a scalar, deliberately; `UV_BIN` is checked first and already grants the same |
| `REQUIREMENTS_CI_TARGET` | `scripts/sync-requirements-ci.sh` | points the drift check at a fixture, so a test that crashes between mutating and restoring cannot leave a modified tracked `requirements-ci.txt` to be committed by accident                                                                    |

**Sync CI requirements:** `make sync-requirements-ci` (renders **all five** CI requirements files from `uv.lock`)
**Check CI requirements drift:** `make check-requirements-ci` (fails when **any** of the five renderings is stale; a prerequisite of `make test`)

**There are five renderings, deliberately separate files.**

| file                           | group         | pins | consumers                   |
| ------------------------------ | ------------- | ---- | --------------------------- |
| `requirements-ci.txt`          | `test-lint`   | 80   | the full local/dev test set |
| `requirements-runtime-ci.txt`  | `runtime`     | 229  | terraform_ansible           |
| `requirements-ci-test.txt`     | `ci-test`     | 11   | per-PR test/lint jobs       |
| `requirements-ci-mutation.txt` | `ci-mutation` | 30   | mutation jobs               |
| `requirements-ci-audit.txt`    | `ci-audit`    | 28   | dependency-audit steps      |

Do not harmonise them — `tests/setup_env/requirements_ci.bats` asserts distinctness across two tests: "the two renderings are different files with different content" (`test-lint` vs `runtime`) and "all four renderings are distinct files" (three pairwise diffs over `test-lint`, `runtime`, `ci-test`, `ci-mutation`). `requirements-ci-audit.txt` has a drift assertion but no distinctness assertion — four of the five are pinned, not all five.

**The CI groups are not "test-lint minus the unused bits", and that shape was measured and rejected rather than skipped.** Dropping every genuinely-uninvoked tool takes the test-lint rendering 80 → 73, so a consumer running three tools still installs 70 it never runs. The useful boundary is **purpose**, not CI-versus-local: `ci-test` is exactly what a per-PR `test`/`lint` job runs, `ci-mutation` exactly what a mutation job runs. Measured 2026-09-08: etch-cli runs `ruff`, `pytest` and `pytest-cov` and needs **19 pins instead of 80** — 61 fewer packages on every PR. (It was 11 when the group was cut; `hypothesis` and its transitive set are the growth, admitted deliberately — see the erosion guard below.)

**The framing that matters, because it was wrong for most of the design: this was never a deletion problem.** The packages are legitimately in the venv — a human might use any of them — and the defect was that CI inherited the venv's shape. Nothing needed removing from anywhere; a job just needed to stop installing what it does not run. The groups are purely additive: the lock is unchanged at 269 packages and no machine's venv moves.

**`ci-test`'s boundary is stated in `pyproject.toml` and guarded by a test, not by review.** The predicted failure is erosion — a repo needs one more tool, it lands in `ci-test` because that is where tools go, and in a year `ci-test` is the union again. `ci-test carries none of the mutation whales` fails if `sqlalchemy`, `aiohttp`, `gitpython`, `yarl`, `frozenlist` or `multidict` ever appear there, and `ci-test is materially smaller than the full test-lint rendering` fails if the two converge. `hypothesis` is the first instance of that pressure and is admitted deliberately, on a measurement rather than a principle: it costs 2 packages against the cost of a third group.

**`bandit`, `radon` and `vulture` stay in `test-lint` and are absent from every CI group, which is the point.** `bandit` is invoked by `security-review/SKILL.md:110` — a Phase 3 gate that runs on a developer machine, so `test-lint` is exactly its right home and `ci-test` exactly the wrong one. A repo-only sweep cannot see that call: **skills are a caller class living outside every repo**, and `pip-audit` and `hypothesis` are skill-invoked too. `radon` and `vulture` are named by `python.md:102-103` as advisory tooling; the operator's ruling is that they stay.

**Provenance does not go in these headers, and that is load-bearing.** A `runtime`-group edit moves `uv.lock` without changing the `test-lint` export, so a `uv.lock` SHA in that header would demand a re-render whose only effect is one header line — a gate firing on correct state, forever. Provenance belongs on a _consumer's_ copy, written at copy time.

**The drift gate cannot see a wrong-group declaration.** It verifies each rendering is faithful to its group; a package in the wrong group renders faithfully and passes. `cosmic-ray` sat in `runtime` through every green run until 2026-08-21 (#231), and was found by enumerating five repos' CI by hand — which is not a mechanism. A green `check-requirements-ci` is not evidence about grouping.

`requirements-ci.txt` is a **rendering, not a declaration** — `pyproject.toml` plus `uv.lock` are the source. It exists so the other repos' CI can `pip install -r` it with stock pip and no `uv` on the runner; verified on macOS and Linux, 80 packages and 655 enforced hashes (measured 2026-09-08). Never hand-edit it.

Two properties are load-bearing and were measured rather than assumed. **`uv export` is not byte-deterministic** — its header echoes the argv it was given, including an absolute `--project` path, so `scripts/sync-requirements-ci.sh` strips that header and writes a fixed one; without this the drift gate would fire on every PR forever. And **the Makefile guard skips when `uv` is absent**, matching lint's `shellcheck` idiom, so CI installs a pinned checksum-verified `uv` to keep the check from being inert exactly where it is the real gate.

The pre-commit hook is **required**. It runs on every `git commit`:

1. `make lint` — blocks the commit on any syntax or shellcheck failure
2. `ggshield secret scan pre-commit` — scans staged changes for secrets before they reach the remote. **Resolved by explicit override, then `PATH`, then absolute prefixes — not by `command -v` alone — and the skip is announced on stderr, never silent.** A git hook is not an actor of its own: it inherits whoever invoked `git`. Measured 2026-08-21 on the Linux workstation, where ggshield 1.53.0 is installed and authenticated at `/home/linuxbrew/.linuxbrew/bin/ggshield`: `zsh -i -c` resolves it, while `zsh -l -c`, `ssh host '<cmd>'`, cron and `env -i sh` all report NOT-ON-PATH, because that prefix reaches `PATH` only through `.config/.zshrc.d/6_path.zsh`, which interactive zsh alone sources. Under the previous bare `command -v` guard the scan ran from a terminal and silently did not run for any of the others — **the gate was not absent, it was invisible**, which is the worse of the two for a security arm because silence is indistinguishable from "scanned and found nothing". This is the same actor-boundary class as the `make` 3.81/4.4.1 split documented above, for a different tool on a different platform. The absent case still exits 0 — a machine lacking ggshield must be able to commit the change that installs it — but it now says so twice on stderr

The pre-push hook is **permanent**. It runs `make test` (lint + bats) on every push before the push reaches GitHub, and it **fails closed** (ADR-0017, `docs/adr/0017-pre-push-trigger-fail-closed.md`): the suite runs unless every changed path is provably inert, and it also fails closed if `git diff` itself cannot resolve the push's revision range (e.g. `remote_sha` names an object the local checkout lacks) rather than silently reading that as "nothing changed". The inert set is deliberately small — `.md` files, `.yml`/`.yaml` files under `.github/`, and `LICENSE` — and is matched with `grep -qv`, so a single changed path outside that set is enough to trigger the run. `docs/` and `.github/` are **not** wholesale-inert: `make lint`'s `SHELL_FILES` walk is recursive, so a `.sh` file anywhere in the repo — including `docs/gen.sh` or `.github/scripts/foo.sh` — is linted by `make test` and must still trigger the suite. This means `starship.toml`, `.zshrc`, `.gitignore_global`, and `ubuntu_common_packages.txt` all trigger the suite even though none is a `.sh`/`.bats`/`.zsh` file, because none is in the inert set. Skips branch deletions. This conserves GitHub Actions minutes — CI runs only on PRs.

**Worktree compatibility requirement:** `scripts/pre-push` must resolve repo root with `git rev-parse --show-toplevel` first, and use `git rev-parse --git-common-dir` parent only as a fallback. Direct `git-common-dir` resolution can run tests against the shared checkout instead of the active worktree branch.

**Git env strip requirement:** `scripts/pre-push` must `unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE` before invoking `make test`, and that line must stay **below** the range-resolution loop, which legitimately needs the git environment. Git exports `GIT_DIR` into the hook only when the push originates from a worktree; without the strip, every suite that builds a git fixture inherits it and `git -C <fixture>` silently operates on the leaked repo instead — measured at 90 failures, with the local test gate effectively absent for the standard worktree workflow. Covered by `tests/scripts/pre_push.bats` ("clears inherited git repo-location vars"), which fails if the line is removed.

**Direct-to-master guard:** `scripts/pre-push` refuses a push whose `remote_ref` is `refs/heads/master` when the diff carries an executable-class path — `*.sh`, `*.bash`, `*.bats`, `*.zsh`, `Makefile`, and the extensionless `scripts/pre-push` / `scripts/commit-msg`. It exits 1, names the offending paths on stderr, and does not run `make test`. Why: `.github/workflows/ci.yml` triggers on `pull_request` only, so a code change pushed straight to master is validated by nothing. Measured 2026-09-11 over 30 days — 263 direct-to-master commits, of which 254 are docs-only and permitted and 3 are `renovate.json` which `git-workflow.md` also permits, leaving 5 genuine code pushes, all from a single session. The background rate outside that session is zero, which is why the guard is local and free rather than a `push:` trigger costing ~3,700 ubuntu-minutes a month to catch nothing.

The scope is **deliberately narrower** than `sdlc-branch-guard.sh`'s `is_safe_file`, and the exclusions are chosen rather than overlooked: `.zshrc`, `starship.toml`, `.shellcheckrc` and `.github/workflows/*.yml` stay pushable direct, and `tests/mocks/*` is extensionless shell the class does not match. The workflow case is the widest remaining hole and carries its own backlog row — those files are inert to this hook _and_ uncovered by CI.

Two implementation constraints, both load-bearing. The verdict **accumulates in a flag inside the stdin loop and is read after it**, never `exit`ing mid-loop, for the same reason the existing range resolution drains every ref line: one push can send a real branch and a deletion together. And the refusal is checked **before** the `needs_test` early-exit, because an inert-but-unsafe path would otherwise skip the guard along with the suite.

**The guard evaluates the push RANGE, not the tip commit, and the first person to hit that will read it as a false positive.** A docs-only commit stacked on an unpushed executable-class commit is refused, correctly — both commits would reach master. Verified end-to-end against a real `git push` rather than the bats harness: a `README.md`-only commit pushed to master from a branch still carrying an unpushed `deploy.sh` was refused naming `deploy.sh`, while the same commit from a clean base landed. If a docs push is refused and names a file you did not touch in that commit, check `git diff --name-only <remote-sha>..HEAD` before assuming the guard is wrong.

**`scripts/pre-push` is itself executable-class, so a defective guard cannot be repaired by a direct push to master.** The fix needs a branch and a PR, or `--no-verify`. That is deliberate rather than an oversight — the escape hatch is the workflow the guard exists to enforce — but it is worth knowing before you need it at speed.

**Twelve tests in `tests/scripts/pre_push.bats` push to a feature ref deliberately — do not switch them back to master.** Their subject is the inert set (does this path make the suite run), not master policy; they named `refs/heads/master` only because that is what the harness author typed. Under the guard, master would answer for them and retire what they assert. One did exactly that before it was re-pointed: `pre-push propagates a make test failure as a non-zero exit` went **green while testing nothing**, because `status -ne 0` is satisfied by the refusal as readily as by the make failure it exists to pin. Mutation-confirmed after re-pointing — flipping its make mock from exit 1 to exit 0 turns it red.

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

`make lint`'s scope comes from `scripts/list-shell-files.sh`, not a literal list, not `find`, and not a `git ls-files` pathspec. A pathspec is extension-keyed and cannot express "every tracked shell script" — it silently drops the extensionless hooks and every mock under `tests/mocks/` — so the script instead reads every tracked file's first line and keeps it when that line is a bash/sh shebang. That covers every tracked shell file, mocks and hooks included — count it with `bash scripts/list-shell-files.sh | wc -l` rather than reading a figure here; this line carried a stale `101` against the Testing section's stale `102` until 2026-09-08, which is what two restated copies of one derivable number buy you — and excludes both untracked scratch files and the copies inside any linked worktree.

**It now covers `tests/mocks/`, which it did not until this branch.** All 64 mocks tracked at that time were extensionless — 65 today, still all extensionless — so the previous `git ls-files '*.sh' '*.bash'` pathspec plus two named hooks never saw them — a shell file modified there was linted by nothing. The shebang-derived scope in `scripts/list-shell-files.sh` picks them up because it reads content rather than filename. `shellcheck` over the 64 found 2 with findings, both fixed on this branch: 4 × `SC2086` site-suppressed in `tests/mocks/brew` (word-splitting is the point there) and 1 × `SC2034` fixed in `tests/mocks/gpg`.

### CI / GitHub Actions

`.github/workflows/ci.yml` runs on PRs to master only (the pre-push hook gates branch pushes locally):

- `test` job: installs a pinned, checksum-verified shellcheck plus bats, runs `make test`, then verifies test count >= 840 (regression proxy)
- `lint-macos` job: runs on `macos-latest` (**blocks auto-merge** — it is in `auto-merge`'s `needs:`), two independent steps: `bash -n` over the derived `SHELL_FILES` list via `make print-SHELL_FILES | tr ' ' '\n' | xargs`, guarded by its own empty-list check — the `tr` is load-bearing, since `print-%` emits one space-separated line and `xargs -I` implies `-L1` and does not split on blanks, and `zsh -n` over the 12 tracked zsh files selected via `git ls-files '*.zsh' '*.zsh-theme' '.zshrc' '.zprofile' 'config/profiles.sh'` — the trailing `config/profiles.sh` is the deliberate overlap described above and must stay in step with `Makefile`'s `ZSH_FILES`; this second step refuses to pass on an empty file list
- `bash-coverage` job: measures bash line coverage via PS4 xtrace on `ubuntu-latest`; **gates at 91%** — blocks auto-merge if coverage drops below floor. **It runs the same suite as `test`, in a separate job, so every tool `make test` depends on must be installed in BOTH jobs.** Measured 2026-08-21 (#226): a pinned `uv` was added to `test` only, 4 tests that pass under `make test` failed here, and the red-suite guard correctly refused to compute coverage over a red run — so the symptom was a coverage job failing on something that is not coverage. Both jobs now install it (`ci.yml:35`, `:158`).
  **A workflow-wide grep cannot catch this.** The test written to prevent it searched the whole file for `UV_SHA256` and passed on presence anywhere — which it had, in the wrong job. An assertion satisfied by a different _job_ than the one under test is the same cause-isolation defect as one satisfied by a different code path; the check must parse per job. It must also account for `working-directory:`, since the naive per-job version flags `powershell` as a false positive — that job runs `make test` under `working-directory: powershell`, i.e. Pester against a different Makefile, finishing in ~56s rather than five minutes.
- `secret-scan` job: runs gitleaks against recent commits (**blocks auto-merge** — it is in `auto-merge`'s `needs:`). This is a deliberate deviation from `ci.md`'s Personal Repos clause, which says the `secret-scan` job "is advisory (non-blocking) but must be present": a leaked credential must not auto-merge, so it fails closed here.
- `auto-merge` job: auto-merges any PR when all CI jobs pass (`needs: [test, lint-macos, powershell, bash-coverage, secret-scan]`). **Every job named there is a gate, and there is no advisory tier.** `ci.yml` carries no `continue-on-error` and `auto-merge`'s only condition is `if: github.event_name == 'pull_request'` — no `always()` — so a failed, cancelled, or skipped dependency blocks the merge. Two of these were documented as advisory here until 2026-08-28; the code was right and the prose was wrong. Adding a job to `needs:` makes it blocking with nothing else to change, which is why the two descriptions above name their status explicitly.
- **Every job declares `timeout-minutes`**, so a hung job can no longer block auto-merge for GitHub's 360-minute default (PR #223 hit this live — `powershell` stalled 30m21s inside `Install PowerShell`). Caps: `test` 20, `bash-coverage` 25, `powershell` 5, and 10 for `lint-macos`, `secret-scan`, `auto-merge`, and `pr-title-lint.yml`'s own job — each sized to roughly 3x its measured p90 — except `powershell`, deliberately tighter at 5 minutes over a 60s p90 as the known-hang job — with a 10-minute floor on the short jobs where 3x p90 would otherwise sit under normal runner variance. Nothing in the suite asserts these values: a guard test was specified and then deliberately dropped across three review rounds — see `docs/superpowers/specs/2026-08-27-ci-job-timeouts-design.md` for the reasoning and the two futures it leaves open.

CI requirements:

- All jobs run on `ubuntu-latest` with `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: true`
- Uses `actions/checkout@v5`

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
- **The denominator is the union of the static heuristic's coverable-line count and whatever the trace file actually contains for that file, never the heuristic alone.** This is what makes `covered <= coverable` hold by construction rather than by luck — every traced line is by definition a member of the union, so it can never exceed it. A wrongly-excluded line therefore raises the denominator (and the numerator, since the trace hit it) rather than silently lowering the percentage; an over-matching exclusion rule can never manufacture a higher score. Each run prints every union-added line as a **heuristic disagreement** — the heuristic said not-coverable, the trace disagreed — so a systematically wrong exclusion rule stays visible instead of being absorbed into a bigger denominator. A non-zero count is a to-do against the heuristic, not a failure of the gate, and it moves with coverage: widening what the suite executes surfaces more traced lines. **Read it beside the ratio from the same run, never a ratio from another one.** A union-added line raises numerator and denominator together, so a count and a ratio from different runs describe a pair that never existed.
- **`covered > coverable` is now a hard, loud non-zero exit — replacing a silent clamp that had been hiding real over-matches.** Before the union approach, `lib/detect_env.sh` read 24/24 = 100% while the trace actually emitted 25 distinct lines for it; the clamp absorbed the discrepancy instead of surfacing it. Under the union rule that discrepancy cannot occur by construction, so a `covered > coverable` result now means an exclusion heuristic double-counted or otherwise over-matched, and the run fails rather than reports a number nobody can trust.

  Inspect one file's denominator, or a full run's coverage against a real trace, without waiting on the bats suite:

  ```bash
  bash scripts/run-bash-coverage.sh --list-sources
  bash scripts/run-bash-coverage.sh --count-coverable lib/helpers.sh
  bash scripts/run-bash-coverage.sh --file-coverage lib/helpers.sh /path/to/trace
  ```

- Publish CI's bash coverage figure in the PR body once CI has run (`gh pr edit <n>`); a local run is a preview, labelled as one.
- `make bash-coverage` measures via PS4 xtrace (`scripts/run-bash-coverage.sh`).
- Before recording or publishing a bash coverage figure, or editing `scripts/run-bash-coverage.sh` or `scripts/bash-tracer.sh`, read `~/git-repos/personal/ai-config/docs/knowledge/dotfiles-bash-coverage.md` (method, floors and ceilings, reading the figure).

### Test Seams

See `~/git-repos/personal/ai-config/docs/knowledge/dotfiles-bats-test-infrastructure.md` for the full override env var table (moved to ai-config per ADR-0020).

Pattern: `local _file="${_OVERRIDE_VAR:-$(dirname "${BASH_SOURCE[0]}")/real/path}"`. Tests set the var and pass a writable temp copy; production code leaves it unset.

**`config/profiles.zsh` is the single zsh-side derivation of `PROFILE`, `HAS_*`, and the
eight legacy identity variables (`LAPTOP`, `STUDIO`, `RECEPTION`, `RATNA`, `OFFICE`, `HOMES`,
`WORKSTATION`, `CRUNCHER`) from `config/profiles.sh`'s table.** Both `.zprofile` (login) and
`.config/.zshrc.d/1_init.zsh` (interactive) source it, so a login+interactive shell runs it
twice in one process — the same pattern `1_init.zsh`'s own `${NOBLE+x}` guard exists for.
`lib/detect_env.sh` derives the identical eight variables on the bash side; `tests/zshrc.d/
cross_shell.bats` asserts both shells produce the same `PROFILE`/`HAS_*` set for every table
key, which is the property the pre-existing test suite could not check because its own
oracle was derived from the same wired-only table it was testing.

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

`tests/helpers/legacy_oracle.bash` carries a `#!/usr/bin/env bash` shebang, which is
what puts it in `make lint`'s scope — `scripts/list-shell-files.sh` derives scope from
first-line shebangs, not filenames, so this file is linted by the same mechanism as the
extensionless hooks, not because its `.bash` extension happens to match a pathspec.

**`config/profiles.zsh` uses `export`; `lib/detect_env.sh` uses `readonly` — this is
deliberate, not drift, and a future reader will otherwise "fix" one to match the other.**
The zsh file is sourced twice per login+interactive shell, and a `readonly` reassignment on
the second pass makes that `source` return 126 — silently degrading the shell's identity
rather than crashing it outright, since nothing else in the chain checks that exit code.
`lib/detect_env.sh`'s `detect_env()` runs exactly once per bash process, so `readonly` there
is safe and keeps the guarantee that nothing later in the process can mutate identity.
Neither scope modifier is a stray choice; each is correct for how often its file re-runs.

**`_OVERRIDE_HOMEBREW_PREFIX_ARM` / `_OVERRIDE_HOMEBREW_PREFIX_INTEL`** replace the
hostname-keyed branches that used to stand in for "which Homebrew prefix does this machine
have" in `.config/.zshrc.d/5_general.zsh` (`CHRUBY_LOC`, `FZF_BASE`, the keychain binary
path) — the actual question those sites were asking, answered directly instead of by proxy
through a hostname list that needed a new arm for every Intel mac. As with the gnubin
override pair, the real prefix directories (`/opt/homebrew`, `/usr/local/opt`) exist on any
provisioned mac, so a test that forgets to point these at a nonexistent path short-circuits
the guard and silently asserts nothing — drive both "present" and "absent" through the
override, never through the real filesystem.

**`_OVERRIDE_KEYCHAIN_BIN` (`.config/.zshrc.d/5_general.zsh`) selects the `keychain`
binary, defaulting to `/usr/local/bin/keychain` (RATNA), `/opt/homebrew/bin/keychain`
(other macOS) or `/usr/bin/keychain` (Linux).** The seam exists because those paths are
absolute, so a `PATH` mock cannot shadow them — `shell.md`'s "an absolute-path default
silently defeats the stub". Without it a regression test could only fail on a machine that
has keychain installed, which is neither CI nor macOS, so the test would pass vacuously
exactly where it runs most often.

**The expansion is quoted — `` `"${_keychain}" --eval …` `` — and the reason is not the one
first given for it.** That was a threat-model argument: anyone able to set
`_OVERRIDE_KEYCHAIN_BIN` in your interactive environment already has code execution as you, so
word-splitting buys an attacker nothing. True, but language-agnostic, and it would license the
same unquoted form in a `.sh` file where it genuinely splits. The real reason the unquoted form
was safe here is narrower: **zsh does not word-split unquoted parameter expansions** —
`SH_WORD_SPLIT` is off by default, unlike bash and sh — so a path containing a space ran
correctly either way. Measured 2026-08-16: `v="/a b/c"; printf "[%s]\n" ${v}` yields one field
in zsh and two in bash.

It is quoted anyway because that safety is a default, not a guarantee. `emulate sh` and
`emulate ksh` both set `SH_WORD_SPLIT`, so any future code path that emulates another shell
before sourcing this file gets splitting back, and `shellcheck` cannot parse zsh at all, so
nothing in `make lint` would ever flag the regression. `tests/zshrc.d/unit.bats` covers it by
setting `setopt shwordsplit` explicitly — without that option the quoted and unquoted forms are
indistinguishable and the test would be vacuous.

The `[[ ${VAR} ]]` tests throughout this file are deliberately **not** quoted: `[[ ]]`
suppresses word splitting regardless of `SH_WORD_SPLIT`, so there is nothing to protect against
and quoting them would be churn. The distinction is command position versus test position, not
a blanket style rule.

The block it guards is wrapped in `[[ -o interactive ]]`, and that guard is load-bearing
rather than tidy: `keychain` starts an `ssh-agent` that daemonizes, reparents to init, and
keeps every fd it inherited. `tests/zshrc.d/unit.bats` sources this file non-interactively
to reach the rbenv branch, so before the guard each source leaked an agent still holding
the `bats-exec-suite` output pipe — `make test` ran every test and then hung forever
waiting on an EOF that could not arrive. Measured 2026-08-16 on the Linux workstation: 16
agents pinning the suite's pipe (4 tests × 4 keychain calls) and 161 accumulated since
2026-07-28, one of which the operator's own keychain pidfile had adopted as the login
agent. macOS and CI were never affected only because the Linux branch names an absolute
`/usr/bin/keychain` that neither has — not because the defect was absent there.

The two tests covering it are a **pair**, and neither works alone. The non-interactive test
asserts zero calls, which is a composite outcome; the interactive test is the control that
proves production actually reads the seam. Mutation-confirmed: reading the seam under a
typo'd name leaves the negative test green and fails only the positive one.

**`_OVERRIDE_CURRENT_LOGIN_SHELL` (`lib/helpers.sh`'s `_current_login_shell`, read by
`setup_zsh_as_default_shell` and `_doctor_check_login_shell`) supplies the ACCOUNT's login
shell.** Production derives it from `getent passwd "${USER}"` on Linux and
`dscl . -read /Users/${USER} UserShell` on macOS — deliberately **not** `${SHELL}`, which
names whichever shell happens to be running. A provision started from zsh read "already
zsh" while the passwd entry still said `/bin/bash`, so the guard could not see the thing it
guarded. The seam exists because the only other way to reach either branch is to read — or
change — the developer's real account. It is not optional in tests: without it they pass on
a mac whose account is already zsh and fail on any runner whose account is `/bin/bash`,
which is the machine's reason rather than the code's, and the same trap the homebrew-prefix
pair above carries. Measured: the three end-to-end `run_doctor` tests stub every sub-check
by name, so `_doctor_check_login_shell` must be stubbed there too or it reads the real
account mid-suite.

**`chsh` is why the rest of that function changed, and the failure was a PASS rather than a
FAIL.** `chsh` is setuid root but authenticates the **invoking** user through PAM, so it
prompts for a password and exits 1 in every non-interactive actor — a provision run, cron,
`ssh host '<cmd>'`. Measured on `claude` 2026-09-12:

```
chsh -s /bin/zsh </dev/null        Password: chsh: PAM: Authentication failure   rc=1, unchanged
sudo -n chsh -s /bin/zsh "$USER"                                                 rc=0, changed
```

The old code checked neither rc and then logged `Changed default shell to ${ZSH_PATH}`
unconditionally, so a full provision reported success over a shell it had not changed —
found only when the operator logged in and got a bash prompt. `run_setup_user`'s
`|| return 1` (`lib/workflows.sh:153`) could not fire either, because the function's last
command was `log_info`. The three pre-existing tests encoded all of it: one asserted only
that `chsh` was _called_, never that it succeeded, and the error-path test asserted
`status -eq 0`, pinning the swallow. `_doctor_check_login_shell` is the independent reader
that would have caught the silent failure, and it renders "could not read the account" as a
WARN rather than a PASS, since an unreadable account is not evidence the shell is correct.

**`_OVERRIDE_GNUBIN_ARM` / `_OVERRIDE_GNUBIN_INTEL` are read by two files in two
languages** — `lib/macos.sh`'s `install_make_macos` (bash) and
`.config/.zshrc.d/6_path.zsh` (zsh, sourced by every interactive shell). Both default to
`/opt/homebrew/opt/make/libexec/gnubin` and `/usr/local/opt/make/libexec/gnubin`
respectively; keep the pairs in step, since a drift makes the install guard and the `PATH`
consumer disagree.

The seam is not optional in tests: the real ARM gnubin dir exists on any provisioned mac,
so a test that forgets to point these at a nonexistent path short-circuits the guard and
silently asserts nothing. `tests/setup_env/install_guards.bats` calls `_gnubin_absent` /
`_gnubin_present` for exactly that reason. Unlike most seams here these are read
unconditionally rather than only under test — a stray export changes real shell `PATH`,
which grants no capability beyond setting `PATH` directly but is worth knowing.

**`_OVERRIDE_DOCKER_BIN` (`.config/.zshrc.d/6_path.zsh`) selects Docker Desktop's CLI
directory, defaulting to `${HOME}/.docker/bin`.** The seam exists for the same reason as the
gnubin pair: that directory is real on any mac running Docker Desktop, so a test of the
absent branch that relied on the filesystem would short-circuit the `-d` guard and assert
nothing. `tests/zshrc.d/unit.bats` points it at `/nonexistent/docker-bin` for that case. It
is read unconditionally inside the `HAS_DOCKER` block, not only under test — a stray export
appends a different directory to interactive `PATH`, which grants nothing beyond setting
`PATH` directly.

The entry used to live in `.zprofile`, written there by Docker Desktop's installer as a
hardcoded `/Users/<name>/.docker/bin`. Moving it here narrows the actors that see it from
login shells to interactive ones — deliberately, and the same boundary `brew` already has on
Linux (see Key Conventions). Measured 2026-09-10: `docker`, `kubectl` and the three
credential helpers are also symlinked into `/usr/local/bin`; `docker-compose`,
`docker-compose-v1`, `docker-index` and `com.docker.cli` resolve only through this directory.
The actor that loses them is a non-interactive login shell (`zsh -l -c`) — cron, launchd and
`ssh host '<cmd>'` read neither `.zprofile` nor `.zshrc`, so they never had the entry — and
nothing in this repo invokes any of the four that way on macOS. If the installer's `.zprofile` lines reappear, delete them
rather than committing them.

**`GGSHIELD_BIN` / `GGSHIELD_FALLBACK_PATHS` (`scripts/pre-commit-hook.sh`) exist for the
same reason, one tool over.** `GGSHIELD_BIN` is the operator escape hatch and is checked
first; a non-executable value there is a hard error rather than a degrade, since an
explicit override that silently falls back is worse than no override.
`GGSHIELD_FALLBACK_PATHS` is a space-separated candidate list, consulted only when `PATH`
resolution fails, and it is env-settable **solely** so a test can reach the genuinely
not-found branch — on any machine that has ggshield the hardcoded prefixes always resolve,
which makes that branch otherwise unreachable. It grants no capability `GGSHIELD_BIN` does
not already grant.

Tests must drive absence through these seams and never by editing `PATH`. Stripping the
directory that contains ggshield takes the toolchain with it — `/opt/homebrew/bin` also
holds `git` and `make` — which is the same "delete a directory to delete one binary"
defect recorded for `tests/mocks` in `shell.md`. `tests/scripts/pre_commit_hook.bats` uses
`MINIMAL_PATH=/usr/bin:/bin` instead: a real PATH that carries `git` and `make` and no
ggshield. Before this seam existed, the case named "ggshield is absent" ran the **real**
ggshield on every dev machine and asserted nothing about the branch it named.

**`_OVERRIDE_LIB_TRAP_SCOPE` (`scripts/check-lib-exit-traps.sh`) points the EXIT-trap
ratchet's scope at a fixture root instead of the repo.** Production derives scope from
`git ls-files 'lib/*.sh'`; under the override it globs `<root>/lib/*.sh` instead, so a
fixture file named `lib/developer.sh` lands on the real allowlist key without needing a
second seam for the allowlist itself. That is what lets the suite drive every verdict —
un-allowlisted trap, allowlisted count, subshell trap still reported, count change, empty
scope, unresolvable base — without ever mutating real `lib/`, which is the only alternative
and would leave the tree dirty mid-run for any concurrent session.

The seam grants nothing: it redirects a read-only scan to a directory the caller can
already read. It is quoted at every use and reaches no `eval`.

**Two code paths, and the tests only exercise one.** Under the override the scope is a
plain glob; in the real repo it is `git ls-files` under the four-variable
`env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE` strip. Every
fixture-driven test therefore certifies the glob path, while CI and the pre-push hook
exercise the git path — the displaced-check shape `behavior.md` describes. The one test
that closes it is "the real lib/ is clean against the real allowlist", which runs with no
override and asserts the scanned set is non-empty; keep it, because without it nothing
in the suite touches the path production actually takes.

**`_OVERRIDE_BATS_BIN` (`scripts/run-bash-coverage.sh`) exists because a `PATH` strip
cannot remove bats on the platform that matters.** The pre-flight guard resolves
`${_OVERRIDE_BATS_BIN:-bats}` and exits 1 when it is unresolvable, deliberately **above**
the `mkfifo`, so the FIFO-reader deadlock it prevents is unreachable rather than merely
unlikely. Tests must drive absence through this variable, never by editing `PATH`: on
`ubuntu-latest` bats lives in `/usr/bin` alongside bash, grep, sed and mktemp, so removing
the directory that contains it removes the toolchain — the same "delete a directory to
delete one binary" defect that broke three tests on this branch and is documented for
`tests/mocks` in `shell.md`.

Both halves of a seam must land in the same commit. This one shipped with the test half
committed and the production half left uncommitted in a worktree: the override was inert
on CI, `command -v bats` resolved the real `/usr/bin/bats`, the guard did not fire, and the
script launched the whole suite under the tracer until the test's `timeout 60` killed it —
a 60-second red on every run. It read as unreproducible for two hours because the local
reproductions were shipped with `git stash create`, which snapshots the **working tree**,
so the workstation ran with the seam and CI ran the commit without it. When reproducing a
CI failure elsewhere, ship `git archive <the sha CI ran>`; if the tree is dirty, that is
the finding. Fixed in `b4ced0d` (#218, merged as `4bd5dd3c`).

**`_OVERRIDE_RUN_TMPDIR_ROOT` is read at exactly one site, `lib/workflows.sh:106`, and is
read unconditionally in production, not only under test — the same shape as
`_OVERRIDE_GNUBIN_ARM`/`_OVERRIDE_GNUBIN_INTEL` above.** `_dotfiles_run_tmpdir_setup`
resolves the run's scratch directory as
`mktemp -d "${_OVERRIDE_RUN_TMPDIR_ROOT:-${TMPDIR:-/tmp}}/dotfiles-run.XXXXXXXX" || return 1`.
The seam grants nothing beyond what setting `TMPDIR` already grants — both select the
parent directory the run's tmpdir is created under, and anyone who can export one can
export the other. It exists because `TMPDIR` alone is not hermetic under bats: bats leaves
`TMPDIR` pointed at the real system temp dir rather than a fixture, and other machinery in
the suite reads it, so a test cannot redirect `TMPDIR` at an unreachable path without also
disturbing everything else that reads it. Without this seam the `|| return 1` guard on that
line has no error-path test at all. What the guard protects: an unreachable root makes
`mktemp` exit 1; without it, `_DOTFILES_RUN_TMPDIR` would be empty, and the 28 write sites
in `lib/workflows.sh` and 107 in `lib/update_summary.sh` that build paths as
`"${_DOTFILES_RUN_TMPDIR}/..."` would all target `/` instead — no status file would be
written, `_fail` would stay 0, and the update summary would report a clean run over one
that did nothing.

**`_PROFILES_LOADED` (`lib/detect_env.sh` and `lib/helpers.sh`) is a sentinel that records whether the identity table loaded successfully** (ADR-0023, `docs/adr/0023-identity-table-load-failure-diverges-by-shell.md`, which amends ADR-0020 with the failure semantics). `detect_env()` sets it to `0` unconditionally on entry, then to `1` only after `config/profiles.sh` sources cleanly _and_ `declare -p PROFILE_MAP PROFILE_CAPS PROFILE_LEGACY` confirms all three arrays exist. `_doctor_check_profile()` in `lib/helpers.sh` branches on it before looking at `PROFILE` at all. The seam is never `export`ed, and that non-export is **not** what makes it safe — an environment-supplied value defeats the check entirely (measured: `env _PROFILES_LOADED=1 PROFILE=mac_workstation <the branch>` reports PASS). What actually protects it is the unconditional `=0` on entry to `detect_env`, combined with `detect_env()` always running before `run_doctor` (`setup_env.sh:61`, then the dispatch at `:69`). Why a sentinel instead of checking `PROFILE`? Because `config/profiles.zsh:46` exports `PROFILE` into every child of a login shell, so after a failed load the stale inherited value survives and `[[ -z ${PROFILE+x} ]]` is false. Measured: with the table unreadable and `PROFILE=mac_workstation` inherited, a pre-sentinel check reported PASS over a machine whose identity table never loaded. A negative control in `tests/setup_env/unit.bats` supplies `_PROFILES_LOADED=1` from the environment _without_ calling `detect_env` and asserts the branch reports PASS — if that test ever starts failing, the mechanism changed and this paragraph is stale.

**`_AWS_GPG_BIN` / `_AWS_PKGUTIL_BIN` / `_AWS_KEY_PATH` (`lib/developer.sh`'s `_aws_verify_zip` and `_aws_verify_pkg`, and `lib/helpers.sh`'s `_doctor_check_aws_key_expiry`) exist for the same absolute-toolchain reason as `_OVERRIDE_KEYCHAIN_BIN` above, applied to the awscli signature-verification path.** `_AWS_GPG_BIN` defaults to `gpg` and `_AWS_PKGUTIL_BIN` to `pkgutil`, each resolved with `command -v` — a `PATH` strip cannot isolate either without removing tools the rest of the suite depends on: stripping `/opt/homebrew/bin` to make `gpg` absent takes `git` and `make` with it, and stripping `/usr/sbin` to make `pkgutil` absent takes the rest of the macOS toolchain that lives there. Each seam makes the verifier-absent branch reachable without disturbing anything else on `PATH` — the same "delete a directory to delete one binary" defect `shell.md` records for `tests/mocks`. `_AWS_KEY_PATH` defaults to the repo's vendored `keys/aws-cli-team.asc` and lets a test point at a fixture key instead; without it only the real vendored key could ever be exercised, so the fingerprint-mismatch and key-expiry branches — the latter also read by `_doctor_check_aws_key_expiry` — would be unreachable.

**`_AWS_KEY_PATH`'s default now comes from `DOTFILES_REPO_ROOT` (`lib/constants.sh`), and the reason is that the previous derivation was cwd-sensitive.** Both consumers computed it inline as `$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/keys/aws-cli-team.asc`. `setup_env.sh:48` sources `lib/developer.sh` by a **relative** path, so `BASH_SOURCE[0]` is `./lib/developer.sh` whenever the entry point is invoked as `./setup_env.sh` — and `update_aws_cli` `cd`s to `${HOME}/software_downloads/awscli` — once per platform arm, before calling the verifier. From there `cd ./lib/..` fails, `&&` short-circuits, the command substitution returns **empty**, and the key resolves to `/keys/aws-cli-team.asc`. Measured 2026-09-07: `setup_env.sh -t update` reported `[FAIL] aws exit 1` on every run, with `gpg: can't open '/keys/aws-cli-team.asc'` and a retry that failed identically. `DOTFILES_REPO_ROOT` resolves the same expression at **source time**, which is the only moment a relative `BASH_SOURCE[0]` is guaranteed to mean anything; It is a plain assignment rather than a `${VAR:-}` self-guard: a guard was written first and measurement retired it, since a re-source is either absolute — which resolves correctly from any cwd, verified from `/` — or relative, which cannot locate `lib/constants.sh` after a `cd` at all. The guard protected nothing reachable and added an env-settable name selecting the directory a cryptographic trust anchor is read from. That would have been fail-closed (`AWSCLI_GPG_FPR` is a plain assignment, so a substituted key still fails the `VALIDSIG` fingerprint check), but an unearned seam on that path is worth less than the case it guarded.

**Sixty-seven `developer.bats` tests covered this code and none could fail for it, which is the durable half.** `load_setup_env` sources `"${REPO_ROOT}/setup_env.sh"` — an **absolute** path — so `BASH_SOURCE[0]` inside every lib file is absolute under bats and the cwd sensitivity is unreachable. Every `update_aws_cli` test additionally stubs `_aws_verify_zip`/`_aws_verify_pkg`, replacing the exact code that fails. That is `behavior.md`'s actor boundary and `tdd.md` E3 with the attribute being **how the file was sourced**: a test that reaches production code by a different path than production does is not testing that path. The two regression tests at the foot of `tests/setup_env/developer.bats` reproduce the production actor deliberately — `source ./lib/...` relatively from the repo root, then `cd` away — and assert on the **post-import** failure (`signature did not verify against the vendored key`) rather than on the absence of the import failure, since an absence is equally satisfied by the function never running (`behavior.md` E5).

**`lib/helpers.sh`'s `_doctor_check_aws_key_expiry` carried the identical expression and was fixed in the same change.** It is latent rather than live — `run_doctor` does not `cd` — but a defect fixed in one of its two copies is not fixed.

**`_AWS_BIN` (`lib/developer.sh`'s `install_aws_tools`) is load-bearing on this development machine specifically, not only in the abstract.** It defaults to `aws` and gates the already-installed guard, `command -v "${_AWS_BIN:-aws}"`. This machine has a real `aws` at `/usr/local/bin/aws`, so without the seam every `install_aws_tools` test silently takes the already-installed branch and asserts nothing about the install path at all — `shell.md`'s absolute-path-default pitfall, sharpened: the binary is not merely resolvable via `PATH`, it exists at the exact absolute location a naive `PATH` strip would leave untouched.

**Cadence seams (`scripts/cadence-notify.sh`, `lib/launch_agents.sh`) — see ADR-0024, and ADR-0026 for the two-stream detector contract.**
The delivery arm and the LaunchAgent installer both resolve absolute paths and external
binaries, so a `PATH` mock cannot reach them (`shell.md`: an absolute-path default silently
defeats the stub). Each seam below exists to make a branch reachable that is otherwise
unreachable on a provisioned machine, and none grants a capability the operator does not
already have by editing `PATH` or the plist directly.

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

**The heartbeat's contract** — `~/.local/share/dotfiles/cadence/<name>/last-run.json`, one
file per cadence, beside that agent's launchd logs:

```json
{
  "ts": "…Z",
  "result": "clean|held|incomplete|pending",
  "exit_code": 0,
  "findings": 0,
  "max_age_days": 8
}
```

Three properties are load-bearing and none is obvious from the shape:

- **`max_age_days` is written, not mirrored.** A reader holding its own copy of the bound
  drifts silently: 8 against a writer that moved to 3 misses four days of staleness and
  reports clean. `_doctor_check_cadence` prefers the written value and **names its source** —
  `(max 3d, from heartbeat)` versus `(max 8d, default — heartbeat carries none)` — so a
  fallback is never mistaken for a reading.
- **`pending` is a state, not a grace period.** The installer seeds it with the install time
  and the bound, so the ordinary staleness rule retires it, a real run overwrites it, and an
  **absent** heartbeat now means genuinely _not installed_. Re-install seeds a missing
  heartbeat and never clobbers a real one, so `setup_user` is the migration path for agents
  provisioned before the field existed.
- **`held` is a finding, not a fault.** `doctor` renders the three classes distinctly and a
  test asserts pairwise inequality — because every other test asserted only that its own
  branch fires, so a reader rendering `held` as a fault would have passed the whole suite.
- **`findings` is a count of stdout lines, and it is only as good as the detector's
  discipline.** The wrapper cannot distinguish a finding from a progress banner, so the
  contract is that stdout carries findings one per line and nothing else, while **stderr
  carries the diagnosis** — captured separately, surfaced in the push under `Cause:` on the
  incomplete path and `Diagnostics:` on the held path, and never counted. **That stderr is
  published**: it is POSTed to the ntfy endpoint, capped at the last 20 lines, so a detector
  must not print credentials, tokens, or environment dumps there. It was discarded before
  2026-08-28, which is exactly why a detector author would not have treated it as published —
  the cap bounds an accidental dump and does not make the stream safe. A detector that
  prints a status line to stdout over-reports by exactly that many lines, silently and
  every week. Measured 2026-08-28 against `ledger_drift_check.sh`, which banner'd on both
  terminal paths: the findings path pushed 31 stale entities as `"findings": 32`, and the
  **clean path pushed `"findings": 1` on a fleet with zero drift**. The second is the
  damaging one — it fires when nothing is wrong — and it was invisible from this side,
  because the only heartbeat available here came from a run that had drift. A count sampled
  on one path is evidence about that path and no other. Fixed in ai-config#227 (stdout now
  9/0/0 across findings/clean/cannot-run), found by that session measuring all three rather
  than the one this repo reported. Nothing here can detect the class — fixing it means
  fixing the detector. Before believing a count, ask what else the detector writes to stdout.

**Every value is closed-form on purpose.** The file is hand-built with `printf` and has two
consumers with opposite constraints: a `sed` reader that breaks on an unquoted value, and a
`json.loads` reader that breaks on anything `printf` cannot escape. Adding a **free-text**
field satisfies the first and breaks the second. Emitting through `python3 -c json.dumps`
was considered and rejected: it puts a hard python3 dependency on the liveness channel, and
since the reader is also bash-calling-python3, one missing interpreter would kill both
channels at once — two channels that fail together are one channel.

**The plist's `PATH` is the agent's whole world, and every detector dependency must be on
it.** A launchd agent sources no profile, so it gets `_PATH_STDPATH` unless the plist says
otherwise — see the actor table under MAKEFLAGS below for the general rule.
`cadence.plist.template` therefore sets `PATH` explicitly, and the entry list is a claim
about what the wired detectors need:
`__HOME__/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin`.

`__HOME__/.local/bin` was missing until 2026-08-28 and the omission was not cosmetic.
`ledger` lives there — `lib/workflows.sh:931` carries that same fallback, so the repo already knew — while the plist listed only the two
Homebrew prefixes, named after `gh` and `python3`. `ledger_drift_check.sh` resolves the
binary with a bare `command -v ledger`, returns **1** when it finds nothing, and its `main`
reads 1 as _stale entities found_, so the ledger-drift agent would have pushed false drift
every Monday for the sole reason that it could not run. Neither agent had fired yet when
this was found (both heartbeats still `pending` from install), so nothing was mis-reported
in the field. The producer-side half — a detector with no way to say "could not determine"
— is ai-config's and is being fixed there.

**When wiring a new detector, resolve its dependencies under this `PATH`, not under yours.**
An interactive shell answers for a different actor and will tell you the tool is present:

```bash
env -i PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin \
  bash -c 'command -v <tool> || echo ABSENT'
```

`tests/setup_env/launch_agents.bats` guards the property rather than the string — it reads
`PATH` out of the **rendered** plist and requires a fixture binary at `~/.local/bin` to
resolve under it, so a change to the placeholder, the substitution, or the entry order is
still measured.

**A plist change does not reach a running agent — the template is the source, not the live
artifact.** `~/Library/LaunchAgents/*.plist` is a rendered copy written at install time, so
merging a template change leaves every already-installed agent on its old contents until
`setup_env.sh -t setup_user` re-installs it. Measured during dotfiles#248: the fix landed on
master while the installed `com.brucejackson.ledger-drift.plist` still carried the pre-fix
`PATH`. Verify the live file rather than the template after any change here:

```bash
grep -A1 '<key>PATH</key>' ~/Library/LaunchAgents/com.brucejackson.ledger-drift.plist
```

**ntfy needs a topic and credentials, and neither is optional.** Measured against the live
endpoint: `POST host` → **400**, `POST host/topic` → **403**, `POST host/topic` with auth →
**200**. `NTFY_URL` holds the host and `NTFY_TOPIC` the topic, so a consumer that POSTs bare
`${NTFY_URL}` cannot deliver — which is what `scripts/whats-new-anthropic.sh` still does.
Credentials go in on **stdin** via `curl -K -`, never `-u`, because argv is readable by any
`ps`; and a credential containing a **newline is refused rather than escaped**, since curl's
config format is line-oriented and everything after a line break is parsed as further
directives.

**The heartbeat is a second channel, deliberately.** The agents are silent when the fleet is
clean — a weekly "still alive" push trains the operator to ignore the channel and destroys
the signal arm — so liveness travels in a file that `_doctor_check_cadence` reads and fails
at 8 days. `ai-config`'s `ledger-drift.yml` is the counter-example the design is built
against: its comment defers real alerting to "an enrolled machine", nothing on any machine
ever ran it, and the honest scoping is precisely what stopped anyone looking.

**`install_ledger_drift_agent` makes that deferral true rather than rewording it**, and the
detector is invoked under `env -u NTFY_URL` so `ledger_drift_check.sh`'s own `ntfy` call
cannot fire — otherwise detection and delivery would fail together and "no drift" would
render identically to "no channel".

### Mock Pattern

See `~/git-repos/personal/ai-config/docs/knowledge/dotfiles-bats-test-infrastructure.md` for the full `MOCK_*` env var reference table and the usage pattern.

**Pass-through mocks:** `ln`, `chmod`, `mv`, `cp`, and `tee` call the real binary (`/bin/cmd "$@" 2>/dev/null || true`) so tests that assert actual filesystem state work correctly. Set the corresponding exit var to a non-zero value to simulate failure instead.

**`env -i` subprocess strips PATH** — `setup_ansible()`'s pyenv calls need the mock placed at `${HOME}/.pyenv/bin/pyenv`, not PATH-injected. Detail and doctor-test conventions (`_DOCTOR_FAIL` vs `_DOCTOR_FAILED`, `log_warn` vs `doctor_warn`, PATH isolation): `~/git-repos/personal/ai-config/docs/knowledge/dotfiles-bats-test-infrastructure.md`.

**`tests/mocks/curl` parses short-option clusters, not just bare `-o`/`--fail`.** Production calls curl as `-fsS -o <file> <url>` and `-fLo <file> <url>` (`developer.sh:105`), so the mock's arg loop recognizes any `-[a-zA-Z]+` cluster: an `f` anywhere in it sets the fail-mode flag, and a cluster **ending in `o`** takes the next argument as the `-o` target — a bare `-o` alone would silently never capture `-fLo`'s target. `MOCK_CURL_HTTP_STATUS` simulates curl's `-f`/`--fail` behavior (fail on HTTP error) without a real network call: it only takes effect when `MOCK_CURL_EXIT` is unset, an f-bearing form was actually passed, and the status value matches `^[0-9]+$` and is `>= 400` — the numeric gate runs before the comparison per `shell.md`'s non-numeric-operand pitfall, so a garbage status value falls through to success rather than an undefined comparison. `MOCK_CURL_EXIT` is the older, unconditional knob and always wins when set.

**`-o`'s write is now deferred until after the exit code is decided, and it is a deliberate deviation from real curl.** A simulated failure (`MOCK_CURL_HTTP_STATUS >= 400` or a nonzero `MOCK_CURL_EXIT`) leaves a pre-seeded target file completely unchanged, mirroring real curl's behavior with `-f`/`-o` on an HTTP error. On success, the mock writes `MOCK_CURL_STDOUT` to the target file **and still also emits it on stdout** — real curl with `-o` writes only to the file and stays silent on stdout. This is kept deliberately because the callers that never pass `-o` (the `whats-new*.sh` scripts, `_fetch_github_latest` in `lib/workflows.sh`, `install_homebrew` in `lib/macos.sh`) require the stdout emission from the same mock, and no current production caller both passes `-o` and consumes stdout — verify that still holds before removing the dual emission. (The mock's own header comment cites `workflows.sh:696` and `macos.sh:82` for these call sites. The first was accurate when written and has since drifted to 721 as later commits inserted code above it; the second still resolves. Naming the enclosing functions — `_fetch_github_latest` and `install_homebrew` — would not drift at all, which is the fix, backlogged rather than applied here because `tests/mocks/curl` is extensionless and so is code to the branch guard, not a docs-safe path.) When no `MOCK_CURL_STDOUT` is set, a successful `-o` call still just `touch`es the target, which is the pre-existing behavior every caller not exercising this failure path already depends on.

### MAKEFLAGS and Stdout Partition

`Makefile:1` carries `MAKEFLAGS += --no-print-directory`. GNU Make 4.0+ prints `Entering directory` / `Leaving directory` on stdout when `-C` changes directory; macOS's `/usr/bin/make` is 3.81 and does not.

**The directive does not cover a direct `make -C` on GNU Make 4.3 — which is what `ubuntu-latest` runs.** Measured on Ubuntu 24.04: with the directive 3 lines, without it 3 lines, byte-identical — `-C` prints the message before the Makefile is parsed, so a directive inside it is too late. 4.4.1 (Homebrew, macOS) does suppress. A per-call `--no-print-directory` and an inherited `MAKEFLAGS` both suppress on **both** versions.

What the directive actually buys is the export: under `make test` every child `make` inherits it, and that works on every version. A direct `make -C …` outside an outer make on 4.3 is uncovered. **The load-bearing protection is the per-call flag and the partition below, not this line** — which is what `tdd.md` pitfall G prescribes first.

**`MAKEFLAGS` is an exported environment variable, not a file-local Makefile directive.** Every `make` a test spawns inherits it. So any test that captures and measures `make` output must explicitly account for it — tests fall into two categories:

- **Guarded:** Per-call `--no-print-directory` flag (overrides the exported `MAKEFLAGS`), for tests that care about exact output shape
- **Measuring:** `env -u MAKEFLAGS` prefix (strips the inherited directive), for tests that genuinely need to observe directory lines. Use it only for that — on 4.3 it strips the one mechanism that works and leaves the inert file directive, so a case that merely wants an exact value must be **guarded**, not measuring. That mistake shipped once and was caught by CI, green on macOS and red on `ubuntu-latest`.

Both categories must exist in the test suite. A test capturing `make` output without guarding or measuring it gets the environment's `MAKEFLAGS`, so it is measuring the environment rather than the Makefile.

**The partition is enforced, not aspirational.** `tests/scripts/makefile_lint_scope.bats:596` ("every stdout-capturing make -C invocation in-domain is guarded or measuring, both sets nonempty") scans every stdout-capturing `make` invocation across the scanner's domain and requires each to land in exactly one of guarded/measuring, with both sets non-empty.

**The domain is derived from `git ls-files`, not listed.** The scanner pulls its file set through `_git_ls_clean 'tests/*.bats' 'tests/*.bash'` — the same four-variable `env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE` strip `ZSH_FILES`/`SHELL_FILES` use, and for the identical reason: `git -C` does not override an exported `GIT_DIR`, and `scripts/pre-push` runs `make test`. An earlier version hardcoded a two-file array (`tests/makefile_scope.bats` and this file) that held exactly the two files already in compliance and excluded the one real violation, `tests/scripts/unit.bats:819` (`make -C "${REPO_ROOT}" -n test-python`, carrying neither guard). That is the same invisible-omission shape `tdd.md`'s Coverage Denominators section describes — an excluded file is absent from both numerator and denominator, so the check reports clean either way — and the third time that shape has shown up in this repo, after the bash coverage tracer's 13-entry `INCLUDE_FILES` array and `make lint`'s original literal file list (both above, under Coverage and ShellCheck).

**Known gap: recursive sub-make and `-w` are invisible to it.** A line scanner can only see what is on the invoking line. `$(MAKE)` recursion and `-w`/`--print-directory` both print `Entering`/`Leaving` with no `-C` anywhere on the line that triggers them, so neither is reachable by this scanner's `-C`/`--directory` pattern. Not exploitable today — the root `Makefile` has zero `$(MAKE)` recipes and `make -n test` emits no sub-make — but `powershell/Makefile` exists and sits outside this scanner's domain entirely. Recorded as an accepted boundary a line scanner cannot close, not a defect to fix.

## Committing Work

Invoke `caveman:caveman-commit` skill to generate the commit message before running `git commit`. Full format and rules in `~/.claude/CLAUDE.md`.

## Key Conventions

- Machine roles are now driven by the **profile/capability model** in `config/profiles.sh` — prefer `HAS_*` vars over raw hostname patterns for new code
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
- After any change to `.zshrc` or `.zshrc.d/` files, run `zsh -i -c 'exit'` before committing to catch re-source crashes before they reach prod. **In a worktree that command is evidence about the main checkout, not about your branch** — `~/.zshrc` and `~/.config/.zshrc.d` are symlinks into the main checkout, so an interactive shell launched from anywhere sources the unmodified files and passes regardless of what the branch changed. Measured 2026-08-17 during #222: the worktree's `1_init.zsh` carried a new `source` line, the main checkout carried zero occurrences of it, and `zsh -i -c exit` returned 0 throughout. From a worktree, source the branch's own files explicitly instead — `zsh -c 'unset -m "HAS_*"; source .zprofile; source .config/.zshrc.d/1_init.zsh; [[ -n ${PROFILE} ]]'` — which is proven falsifiable: rc 0 on the branch, rc 1 on the pre-change tree.
- **`$0` is not the file's path in a zsh startup file, and `${0:A:h}` therefore resolves against `cwd`.** `FUNCTION_ARGZERO` sets `$0` for the `source` builtin and for functions; zsh reads `.zprofile`/`.zshrc` with its own internal reader, where `$0` stays the literal `zsh`. Use `${${(%):-%x}:A:h}` in any file that may be read as a startup file — it names the containing file in both actors, verified at cwd `/` and `/usr`, via `source`, and through a symlink to another directory. Measured in a real login shell with a fixture `$HOME`: the `${0:A:h}` form produced `no such file or directory: //config/profiles.zsh`, lost `PROFILE` and every `HAS_*`, and then skipped the `/opt/homebrew/bin` prepend that `pyenv init` depends on. Every test missed it because bats reaches these files through the `source` builtin — the one actor where `$0` is set.
- **`_UPDATE_SECTION_ORDER` coupling:** `lib/update_summary.sh` has a `readonly _UPDATE_SECTION_ORDER=(...)` array that controls which sections appear in the printed update summary. Adding `_update_record_start/end "new-section"` in `run_update()` without also adding `"new-section"` to this array means the section is tracked internally but never printed. Both must be updated together — `zsh-autosuggestions` (added 2026-08-31) sits right after `oh-my-zsh` in the array for exactly this reason. **The count-assertion warning this bullet used to carry — that adding or removing a section requires manually auditing hardcoded totals like `[[ "$output" == *"9 OK"* ]]` — is stale and was measured wrong.** `_update_summary` `continue`s past any array entry with no `status_<name>` file (`lib/update_summary.sh:547`), and every count assertion in `tests/setup_env/update_summary.bats` seeds its sections by explicit name rather than by iterating the array — one test alone seeds ten named sections (`brew`, `claude`, `mas`, plus seven more via a `for` loop) and asserts `"8 OK"`/`"1 failed"`/`"1 skipped"` against exactly those. Adding `zsh-autosuggestions` to the array changed none of them, because an unseeded array entry is invisible to the tally by construction. The warning would send a future reader auditing assertions that cannot break; the real risk when **removing** a section is a stray reference to its name surviving in a fixture that still seeds it.
- **`scripts/sync_git_repos.sh`** replaces the old rsync-only sync script (`scripts/synch_git-repos.sh`, deleted). Two independent modes: git-native fetch/pull/push for `personal/` repos + `state-ledger` (safe on any of the three dev machines — never force-pushes, never auto-merges a diverged repo; dirty does not block a safe push, only a pull), and studio-only rsync push for legacy/no-git-access directories + a full-tree ratna backup. Runs automatically as part of `-t update` (`git-repos`/`legacy-rsync` sections in `_UPDATE_SECTION_ORDER`); `--git-only`/`--legacy-only`/`-h` for standalone use. See `docs/superpowers/specs/2026-07-18-sync-git-repos-design.md` for the full design and the dirty/ahead/behind decision table. **Never invoke this script (or `sync_legacy_dirs`/`sync_git_repos` directly) unmocked outside the BATS test harness** — it performs real `git push`/`rsync --delete` over SSH against real hosts, and `_is_legacy_sync_host` triggers on the real `hostname -s` of whichever machine runs it.
- **`git-hooks` section coupling:** same `_UPDATE_SECTION_ORDER` trap applies to the hook-install sweep (`lib/git_hooks.sh`) — adding `_update_record_start/end "git-hooks"` in `run_update()` without also adding `"git-hooks"` to `_UPDATE_SECTION_ORDER` means the section is tracked internally but never printed, with no error. Separately: the sweep's post-condition check reads the **installed hooks directory** (`.git/hooks/` or the repo's actual hook path), never `scripts/` — a repo whose hooks were installed by a route other than the Makefile (e.g. `ledger init`) must still read as satisfied. `install_git_hooks_all_repos` returns 0 clean, 1 when a `make install-hooks` call failed, and 2 for partial success — gaps, unreadable hooks, or a `core.hooksPath` pinned at global/system scope. **Both** call sites must branch on it: `run_update` maps 2→0 for `_update_record_end` then calls `_update_warn` (the same shape `git-repos` and `legacy-rsync` use), and `run_setup_user` distinguishes rc 1 ("reported failures") from rc 2 ("gaps or a pinned core.hooksPath") rather than treating any non-zero as failure. Without the `run_update` mapping the section renders `[OK] git-hooks updated` over its own findings.
- **`zsh-autosuggestions` is a reported section** (`lib/workflows.sh:672-689`), not the fire-and-forget `cd`/`git pull`/`cd`-back it used to be — the old block recorded nothing and discarded `git pull`'s status, so the plugin was absent from the summary whether it succeeded or failed. Three `_update_skip` reasons distinguish why it didn't run: `"not installed"` (the plugin directory is absent), `"not a git checkout — reinstall to enable updates"` (the directory exists but has no `.git`, e.g. a tarball drop), and `"flag not set"` (`--tools` wasn't passed to `run_update`). **The guard is `[[ -e ${_zsh_autosug}/.git ]]`, deliberately not `git rev-parse --git-dir`.** That plumbing command walks upward through parent directories looking for a `.git`, and `~/.oh-my-zsh` is itself a git checkout — so a non-clone plugin install (dropped in by hand, or via a tarball) would resolve to the _parent_ repo's `.git` and `git pull` would silently update oh-my-zsh instead, rendering a permanent `[OK] … no changes` for a plugin that was never actually pulled. A future reader will otherwise "tighten" this to the plumbing form; don't. `-e` rather than `-d` is also deliberate: a submodule or a linked worktree has `.git` as a **file** (`gitdir: <path>`), and tightening to `-d` would route that layout to `SKIP` forever — `tests/setup_env/workflows.bats` ("run_update updates zsh-autosuggestions when .git is a gitdir file") pins this after a mutation of `-e` to `-d` left all eight zsh-autosuggestions tests green with nothing catching it.
- **The summary's name column widened from `%-16s` to `%-20s`** to fit `zsh-autosuggestions` (19 characters, the longest `_UPDATE_SECTION_ORDER` member) with its 2-space gutter intact. The width is not a number to remember and re-check by hand: `tests/setup_env/update_summary.bats` ("`_UPDATE_SECTION_ORDER`'s longest name always leaves the reason column's 2-space gutter") reads the pad width back out of `lib/update_summary.sh`'s own `printf` format via `grep -oE '%-[0-9]+s'` and asserts `pad - max >= 1` against the array's actual longest entry — so a future section name of 20 characters or more fails this test rather than silently colliding with the reason column, with no width literal to update in the test itself.
- **The cheat.sh section now covers both artifacts and both failures FAIL the run.** It previously ran the tab-completion fetch (`~/.zsh.d/_cht`) as a bare statement after `_update_record_end "cheat.sh" ...` had already closed out the section, so a completion-only failure was invisible — the section reported whatever the binary fetch alone had recorded. The two fetches now run inside one subshell with a shared `_rc` accumulator: either can fail independently (binary present and stale, completion absent; or vice versa; or both), and the subshell's `exit "${_rc}"` — piped through the same `tee` as before — makes `_update_record_end` see the FAIL. Progress banners (`"Updating cheat.sh"`, `"Updating cheat.sh tab completion"`) print **outside** the subshell specifically so they never land in `err_cheat.sh`/`detail_cheat.sh`, which feeds `_update_write_detail_from_err`'s `tail -10` — a banner line in that budget would silently displace real diagnostic content.
- **`.warp/settings.toml` is Warp-owned and symlinked live** (`~/.warp/settings.toml` → repo, via `safe_link` in `lib/helpers.sh`). Warp rewrites it on upgrade — an unexplained diff there is usually a materialized default, not a hand edit. One value in it is a **deliberate non-default, not drift**: `agents.warp_agent.other.auto_approve_bypasses_command_denylist = false` (Warp defaults it to `true`, which makes the `execution_profiles` `command_denylist` inert whenever auto-approve is on — `permissions.rs` then consults only the org denylist, and a personal machine has no org). That key carries `sync_to_cloud: Globally`, so a fleet machine still holding `true` can push it back and Warp will rewrite the file; treat a diff flipping it to `true` as a sync reversion to re-pin, never as an upgrade artifact to accept.
- **A global/system `core.hooksPath` pin redirects every repo's hooks at once:** `git rev-parse --git-path hooks` honors `core.hooksPath`, so a single global/system pin redirects **every** repo's hooks directory, not just one. The sweep therefore folds the resulting per-repo "no hooks directory" gaps into one aggregated line attributed to the pin, rather than reporting each repo as individually broken with an `install-hooks` remedy that cannot fix it. An **empty or whitespace-only** value is a real pin, not an absent one: `git config --get` reports it as rc 0 with empty stdout, and git honors it — it disables every hook on the machine. Both the doctor check and the sweep summary render it as `(empty)`. `tests/setup_env/git_hooks.bats`'s `setup()` must neutralize `GIT_CONFIG_GLOBAL`/`GIT_CONFIG_SYSTEM`, because the sweep now reads them — without it the suite fails on any machine that actually has a pin, and since `scripts/pre-push` runs `make test`, that developer cannot push.

- **The pin probe must read `--includes`, and the remedy must name the origin file:** `git config --<scope> --get` defaults to `--no-includes`, but git's own hook resolution traverses includes. A pin reached through an `[include]` therefore answered rc 1 with **empty stderr** — byte-identical to a genuinely unset key — while `rev-parse --git-path hooks` returned the pinned path and every repo on the box was silently redirected; both surfaces rendered `[PASS] <scope>: unset` over a live machine-wide redirect. `_git_hooks_hookspath_offenders` now re-reads any apparently-clean scope with `git config --<scope> --includes -z --show-origin --get`. `-z` is required rather than the default tab-separated `--show-origin` format (the value may be empty or whitespace-only, and NUL is the only delimiter git will not also emit inside a value), and because command substitution silently drops NUL bytes the pair must be consumed with `read -d ''` off a process substitution, never `$(...)`. The remedy differs by origin: a scope-level `--unset` **cannot** clear a key held in an included file — it exits 5 and the pin survives — so the function emits `git config --file <origin> --unset core.hooksPath` for that case and keeps the scope form only for a key in the scope's own file. Output contract is `scope<TAB>remedy<TAB>value`, with value last so a tab inside a pinned path cannot truncate the command the operator is told to run. Remaining limit: a conditional `includeIf "gitdir:…"` is visible only when git evaluates it from a matching directory, and the probe runs once per sweep rather than once per discovered repo.

- **Homebrew `make` gnubin prepend:** `.config/.zshrc.d/6_path.zsh` prepends the Homebrew `make` formula's `gnubin` directory on macOS, so plain `make` resolves to GNU 4.x instead of `/usr/bin/make` 3.81. **It must be a prepend, not `path+=`.** This file's existing idiom is append-via-`+=`, which leaves `/usr/bin` ahead of anything it adds — an append here would be completely inert and would still look correct to a reader. Both Homebrew prefixes are tested for existence (ARM at `/opt/homebrew/opt/make/libexec/gnubin` and Intel at `/usr/local/opt/make/libexec/gnubin`); the invocation never calls `brew --prefix` because this same file is what puts `/opt/homebrew/bin` on `PATH`, so `brew` is not guaranteed resolvable at that point.

- **Which `make` an actor resolves — measured, and it does not change any gate verdict.** Because `6_path.zsh` is sourced by interactive zsh only, `make`'s version on a provisioned mac is a function of how the process was started. There are four answers, not the two this file used to describe, all measured 2026-08-16 on the Studio:

  | actor                                                                                                 | `PATH` source                                              | resolves          | version |
  | ----------------------------------------------------------------------------------------------------- | ---------------------------------------------------------- | ----------------- | ------- |
  | interactive zsh; anything descended from it (tmux, Warp, this harness's Bash tool, hooks it launches) | `6_path.zsh` / `.zprofile`                                 | `.../gnubin/make` | 4.4.1   |
  | editor-spawned `git` and its hooks (VS Code measured live)                                            | launchd, plus Homebrew's shim dir                          | `/usr/bin/make`   | 3.81    |
  | cron                                                                                                  | compiled `_PATH_DEFPATH` = `/usr/bin:/bin`                 | `/usr/bin/make`   | 3.81    |
  | launchd job, `ssh host '<cmd>'`                                                                       | compiled `_PATH_STDPATH` = `/usr/bin:/bin:/usr/sbin:/sbin` | `/usr/bin/make`   | 3.81    |

  **The split is real and its consequence to this repo is nil.** The full suite was run under both versions sequentially: `rc=0, 1363 ok, 0 not ok` under each, with an empty `not ok` diff. `make lint` is byte-identical, rc 0 under both. `Makefile:1`'s `MAKEFLAGS += --no-print-directory` is why — it suppresses on 4.x what 3.81 never printed, so the one documented behavioural difference does not reach these gates. Do not reopen this without re-running that comparison; two designs were written and retired on the assumption it mattered (`specs/2026-08-16-system-wide-gnu-make-design.md` and `specs/2026-08-16-hook-make-resolution-design.md`, both carrying the measurements).

  Two traps recorded from those retirements, because both cost real work and neither is obvious:

  - **`/usr/local/bin` reaches none of the non-interactive actors.** It leads `/usr/bin` in `/etc/paths`, but `/etc/paths` is consumed by `path_helper`, which only **login shells** invoke. cron, launchd and sshd use the compiled constants above and never see it. A symlink there changes nothing for any of them.
  - **A `PATH` prepend inside a hook shadows the test suite's own `make` mock.** `tests/scripts/pre_push.bats` builds `PATH="${MAKE_MOCK_DIR}:${CLEAN_PATH}"`; production code prepending a real directory from inside the hook wins that race and the hook then runs the real suite against a bats fixture. Measured at 28 of 36 tests failing. This is `shell.md`'s PATH-mock pitfall inverted — there the mock shadows production, here production shadows the mock — and any future change that manipulates `PATH` in a hook must route through `_OVERRIDE_GNUBIN_ARM`/`_OVERRIDE_GNUBIN_INTEL` so the harness can point it at the mock dir.

- **`setup_env.sh` cannot run non-interactively on the Linux workstation, and the cause is
  the bullet above generalised.** `6_path.zsh` also appends `/home/linuxbrew/.linuxbrew/bin`
  on Linux, and that file is sourced by **interactive zsh only**. `setup_env.sh` gates every
  workflow on `env which brew` (`setup_env.sh:30`), so the entry point resolves `brew` for a
  human at a prompt and not for anything else. Measured 2026-08-14 on the 7950X, which has
  had Homebrew 6.0.17 installed since 2024-12-27:

  ```
  non-interactive bash : ABSENT
  interactive zsh      : /home/linuxbrew/.linuxbrew/bin/brew
  ```

  A non-interactive invocation dies in seconds with `[ERROR] Homebrew not found. On Linux,
run first: ./scripts/bootstrap_linux.sh` — advice that is wrong, because bootstrap already
  ran nineteen months ago. **No cron job, git hook, CI runner, or agent session can run this
  script on that machine**, which bounds anything that would automate through it. Workaround
  for a non-interactive caller is to prepend the prefix explicitly rather than to re-bootstrap:
  `PATH="/home/linuxbrew/.linuxbrew/bin:${PATH}" ./setup_env.sh -t developer`.

  The macOS bullet above and this one are the same defect at two severities — there it
  answers wrong for one tool's version, here it refuses the entry point outright — so treat a
  tool path placed in an interactive-only rc file as gating whichever actor sources that file,
  not as a machine-wide fact. `behavior.md`'s actor-boundary rule states the general form:
  **who runs this in production, and did I run it as them?**

## Dependency Automation

**`renovate.json` inlines the shared preset rather than extending it, and that is
load-bearing.** `ai-config` is a **private** repo and dotfiles is **public**. Renovate
resolves `extends` at `initRepo`, _before any dependency extraction_, so an unfetchable
preset throws `config-validation` and abandons the whole repository — no PRs, no dependency
dashboard, no visible error. Measured 2026-08-23 with config as the only variable: the
remote-preset form produced **8 preset errors and 0 extractions**; inlined, **0 errors and
1 extraction**. `ai-config/renovate-presets/default.json` stays canonical; keep the
`extends`, `schedule`, `labels` and `packageRules` keys in sync with it by hand, because
nothing detects drift between the copies. ADR-0010 predates this and says each repo
_extends_ the shared preset — that half no longer holds.

**Confirmed in production 2026-08-24, and the confirmation is worth more than the
prediction was.** The inlining landed on a repo that had produced **zero** Renovate PRs
in the 98 days since its `renovate.json` was written, and the paragraph above could only
say that a fixture run threw 0 errors instead of 8. Renovate has now actually run here:
**#240** pinned all six `actions/checkout@v6` refs to `d23441a…` and **auto-merged**,
and **#241** raised the `v7` major bump and **did not** — which is `packageRules`
working exactly as written, `automerge: true` for patch/minor and `false` for major.

Two things follow that the earlier analysis got wrong or could not see:

- **`mode=silent` is no longer in force for this repo.** The section in
  `ai-config`'s corpus that established it — from Mend job logs on 2026-08-23, where
  `Branch … creation is disabled because mode=silent` appears verbatim — was correct when
  measured and is now stale. A created branch is the one thing silent mode forbids, and
  there are two. Do not cite the silent-mode finding as a live constraint without
  re-reading a current job log.
- **`pinDigests: true` did the thing it was added for**, on its first real run. The
  description block in `renovate.json` recorded this repo as "0 of 6 refs pinned"; it is
  now 6 of 6, and #241 preserves the pin rather than reverting to a floating tag —
  Renovate rebased it to digest-v6 → digest-v7 once #240 merged. ADR-0006's clause is
  satisfied here by automation rather than by review.

**The zero-PR oracle this repo reasoned from was structurally unfalsifiable, and that is
the durable lesson.** Under silent mode no repo could ever author a PR, so zero was the
only reachable value and every "it is not running" verdict built on it was unprovable
either way. The lesson survives the lift: establish what a mechanism is _permitted_ to do
before drawing any conclusion from what it has not done.

**`pip_requirements` is deliberately absent from `enabledManagers`.** Renovate's pattern is
`(^|/)[\w-]*requirements([-._]\w+)?\.(txt|pip)$`, which allows at most one `[-._]\w+`
group after `requirements`, and `\w` excludes `-`. Measured against all five renderings:
only `requirements-ci.txt` matches — the four narrow slices are two-segment names and cannot.
**That is luck, not design**, so `tests/setup_env/requirements_ci.bats` pins it: renaming a
slice to a single-segment name would silently bring it into scope. All five are generated
from `uv.lock`, so Renovate would raise PRs against generated files that
`check-requirements-ci` fails and the next `make sync-requirements-ci` reverts. The
declaration is `pyproject.toml`; `pep621` is the manager that belongs.

**Decided 2026-08-21, fleet-wide across all 18 non-archived repos: Dependabot
security auto-PRs OFF, Dependabot vulnerability alerts ON.** Verified on this repo
and spot-checked on `math` and `state-ledger` — `GET /vulnerability-alerts` returns
`204`, `GET /automated-security-fixes` returns `enabled: false`.

**This section exists because the decision lives nowhere in any repo.** It is a
GitHub repo-_settings_ toggle, which is the identical defect that produced #227 — a
control governing the repository, declared outside it. A tracked
`.github/dependabot.yml` would not capture it either: that file governs _version_
updates, and these are _security_ updates. Recording state and reasoning here is the
minimum that makes it discoverable, and it is the reason a reader should not conclude
from an absent config file that Dependabot is not running.

**Rationale: alerts are the signal; auto-PRs are an unreviewed write path.** #227,
titled "bump asteval from 1.0.6 to 1.0.9", edited `uv.lock` and nothing else, walked
checkov back a year, and auto-merged because an internally consistent lock passes
every CI check. Keeping alerts and closing auto-PRs gives visibility without letting
a bot modify a lockfile unattended. Anyone re-enabling auto-PRs re-opens that path.

**The fleet-wide measurement inverted the expectation and is the more useful half.**
The premise all day was "an automated bot did something unreviewed." The actual
condition was under-notification: **16 of 18 repos had vulnerability alerts switched
off entirely**, including `math`, `state-ledger`, `etch-cli` and every homelab repo.
One repo had an undeclared write path; sixteen had no signal at all. Net effect is
strictly more visibility and strictly less automation.

Two mechanical details, both non-obvious:

- **`automated-security-fixes` is repo-wide — GitHub offers no per-ecosystem toggle.**
  "Turn Dependabot off for Python" is not expressible; only the whole repo. That cost
  nothing here because `renovate.json` already owns the other ecosystem via
  `enabledManagers: ["github-actions"]`.
- **The flag cannot be cleared while alerts are off.** `DELETE
.../automated-security-fixes` returns **422 "Vulnerability alerts must be enabled to
  configure automated security fixes."** A repo in that state (`terraform_ansible` was)
  is inert but _latently armed_ — enabling alerts later lights auto-PRs instantly. Order
  the calls: `PUT vulnerability-alerts`, then `DELETE automated-security-fixes`.

**Consequence, stated so it is not found as a surprise: Python now has no automated
update path at all.** Dependabot's write path is closed, and Renovate manages no Python
in any repo (`pep621` is enabled nowhere), including this one — despite `pyproject.toml`
and `uv.lock` living here. Alerts will fire with nothing proposing fixes. That is the
right order — visibility before a reviewed write path — but it is a gap with a name and
a duration, not a steady state.

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

**This section has claimed a single-file edit since it was written, and that was already
wrong before this branch — it is being corrected here, not made true for the first time.**
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
note after step 3 below). Read what follows as the sentence going from wrong-by-omission
to correct, not as new steps this branch created.

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
