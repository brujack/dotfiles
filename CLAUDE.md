# CLAUDE.md — dotfiles

A trailing `` → `file` § `heading` `` on a rule means: before acting on that rule's subject, read `ai-config/docs/knowledge/<file>` at that heading for the incident history and measurements.

## Repository Overview

Personal development environment bootstrapping system for macOS and Linux (Ubuntu). Manages shell configs, tool installation, and symlink setup across multiple machine types.

## Layout

Tracked top-level dirs: `lib/` (shell libraries), `config/` (`profiles.sh`, git-ignored `local.sh`, `hook_repos.sh`), `scripts/`, `tests/`, `docs/`, `.config/` (`.zshrc.d/`), `.github/` (workflows), `.claude/`, `powershell/`, `LaunchAgents/`, `keys/`, `manifests/`, `pyenv.d/`, `.ssh/`, `.vscode/`, `.warp/`; `pyenv.d/rehash/*.bash` is installed as a copy into `${PYENV_ROOT}/pyenv.d/rehash/`, never symlinked, so edits need a reinstall; regenerate with `git ls-files | awk -F/ 'NF>1{print $1}' | sort -u`, never from memory. → `dotfiles-conventions.md` § `CLAUDE.md budget: Layout directory tree`

## 10-80-10 Execution Cycle

Sessions in this repo follow the 10-80-10 execution cycle defined in `ai-config` ADR-0009 (with the ADR-0010 wave-dispatch extension):

- Phase 1 (10%, Opus): `brainstorming` → `writing-plans`, emitting per-task `yaml-task` blocks.
- Phase 2 (80%, Sonnet/Haiku per plan): `subagent-driven-development` iterate-until-green; never cheat a gate (FORBIDDEN list); wave-dispatch when `parallel_group` is declared.
- Phase 3 (10%, Opus): `finishing-a-development-branch` runs its gate chain; read the order in its Phase 3 table, not here. → `dotfiles-conventions.md` § `CLAUDE.md budget: 10-80-10 phase list`

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

- `setup_user` reads the Claude plugin manifest from ai-config `~/.claude/settings.json` (`extraKnownMarketplaces`, `enabledPlugins`), never a hardcoded list. → `dotfiles-conventions.md` § `CLAUDE.md relocation: setup_env.sh workflow catalog`
- `setup` and `developer` on Ubuntu docker hosts persist inotify and kernel-keys sysctl values in `/etc/sysctl.d/90-dotfiles-*.conf`, never lowering a higher conf or live value; a drop-in sorting before `90-` is overridden. → `dotfiles-conventions.md` § `CLAUDE.md relocation: setup_env.sh workflow catalog`
- An interrupted `recreate-venv`/`recreate-ruby` leaves the toolchain deleted; re-run the same command, repeating `--venv-name` (a bare re-run rebuilds `ansible`). → `dotfiles-conventions.md` § `CLAUDE.md relocation: setup_env.sh workflow catalog`
- `-t update` exits 1 on any FAIL section; WARN exits 0 (deliberate rc 2 to 0 mapping); list sections with `git grep -n '_update_warn ' lib/`, never a hand list. → `dotfiles-conventions.md` § `CLAUDE.md relocation: setup_env.sh workflow catalog`
- The `ai-config` update section runs just before `claude`, full runs only (never `--claude-only`), so plugin reconcile reads fresh settings. → `dotfiles-conventions.md` § `CLAUDE.md relocation: setup_env.sh workflow catalog`
- Run `nala full-upgrade` with `--no-update` after the verb (apt was just refreshed). → `dotfiles-conventions.md` § `CLAUDE.md relocation: setup_env.sh workflow catalog`
- On a provisioned host run `./setup_env.sh -t doctor`, paste each remedy line one at a time (a sudo prompt can swallow the next), then re-run it. → `dotfiles-conventions.md` § `CLAUDE.md relocation: setup_env.sh workflow catalog`
- `check-versions` exits 1 if outdated and 2 (taking precedence) when `GITHUB_TOKEN` contains a line break; `--update` for kind/yq refreshes `*_VER` and digests via `scripts/refresh-sha256-pins.sh`, shellcheck is hand-bumped (three `SC_VER`/`SC_SHA256` sites in `ci.yml`). → `dotfiles-conventions.md` § `CLAUDE.md relocation: setup_env.sh workflow catalog`
- Reference only (workflow flags and descriptions, doctor inventory, update internals, signal handling, flatpak and apt signer checks, go/python3/packer pin writers) → `dotfiles-conventions.md` § `CLAUDE.md relocation: setup_env.sh workflow catalog`

**Options:**

- `--dry-run` guarantees no outbound write (no `git push`, `rsync --delete`, state-ledger entry write) but is not offline: fetches, `pull --ff-only`, package and registry installs still run; even `--dry-run` runs `ensure_state_ledger` ungated (may `git pull --ff-only`/`git clone` the state-ledger checkout, run `ledger.py init`, and `rm -rf` it if it exists but is not a valid repo); `DRY_RUN=0`/`false`/`no`/empty/unset mean off, any other value on, and an explicit flag wins. → `dotfiles-conventions.md` § `CLAUDE.md relocation: --dry-run option semantics`

## Symlink Strategy

Dotfiles live at the repo root and in the ai-config repo (`.claude/`/`.cursor/`). `setup_env.sh` creates symlinks from `$HOME` into the repos:

- Repo-root dotfiles: symlink each individually into `$HOME`, `.zshenv` included (an existing regular `~/.zshenv` is adopted as `~/.zshenv.local`; if both exist setup warns and leaves both).
- `.claude/`: symlink each ai-config `.claude/` item individually into `~/.claude/`, except `rules/` (never linked: it would load ai-config's project rules as user-level rules) and `projects/` (linked explicitly, see below); `mcp.json.template` is linked read-only. → `dotfiles-conventions.md` § `CLAUDE.md budget: Symlink repo-root and .claude rules`

- `~/.claude/mcp.json` is a symlink into `ai-config/.claude/mcp.json`, never generated: `setup_claude_mcp` finds the symlink and returns 0 with two WARN lines instead of writing credentials into a tracked file (its `-L` guard), and `-t doctor`'s `[PASS] ~/.claude/mcp.json (generated)` only tested existence, so do not read it as proof. → `dotfiles-conventions.md` § `CLAUDE.md budget: Symlink mcp.json is a symlink`

- `projects/` IS symlinked wholesale, so `~/.claude/projects/<encoded-repo>/memory/` is inside ai-config's working tree and `make test` scope: before writing scratch state under `~/.claude/`, know you are writing into another repo, and promote or delete any draft, since a leftover one hard-fails `validate-memory` for every session committing to ai-config. → `dotfiles-conventions.md` § `CLAUDE.md budget: Symlink projects is linked wholesale`

- **`.cursor/`** — each item (excluding `User/`) symlinked individually into `~/.cursor/` from the ai-config repo; `User/` contents are symlinked into the platform Cursor user settings dir

Always remove the old file before symlinking (`rm -f` then `ln -s`). Validate symlinks with `[[ -L ${HOME}/.file ]]`.

### Cursor ↔ Claude Code Parity

When adding or updating a Claude Code plugin, skill or MCP server, check whether `.cursor/` needs the same change: plugins and skills are shared by symlink, but Cursor rules, model settings and MCP registration live in `.cursor/User/` and need separate updates. → `dotfiles-conventions.md` § `CLAUDE.md budget: Cursor Claude Code parity`

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

- Use `env which` only for `setup_env.sh`'s brew prereq check (BATS mocks `which` via PATH); use `command -v` everywhere else. → `dotfiles-conventions.md` § `CLAUDE.md relocation: shell conventions (env which, prereq tests, sudo dpkg, apt conffile, sourcing guard)`
- In `-t doctor`/`-t check-versions` prereq-bypass tests assert `[[ "$output" != *"Homebrew not found"* ]]`, never `[ "$status" -eq 0 ]` (exit varies with the mock environment). → `dotfiles-conventions.md` § `CLAUDE.md relocation: shell conventions (env which, prereq tests, sudo dpkg, apt conffile, sourcing guard)`
- No `set -euo pipefail` at top level; conditional installs need non-zero exits to continue. → `dotfiles-conventions.md` § `CLAUDE.md relocation: shell conventions (env which, prereq tests, sudo dpkg, apt conffile, sourcing guard)`
- Every `sudo` dpkg call in `lib/`, `setup_env.sh` and `scripts/` carries `DEBIAN_FRONTEND=noninteractive` on the sudo line (`sudo -H DEBIAN_FRONTEND=noninteractive apt install …`); the caller's environment does nothing. → `dotfiles-conventions.md` § `CLAUDE.md relocation: shell conventions (env which, prereq tests, sudo dpkg, apt conffile, sourcing guard)`
- Every `sudo apt|apt-get|nala install|reinstall|upgrade|full-upgrade|dist-upgrade|build-dep` carries the quoted `"${APT_CONFFILE_OPTS[@]}"` (never unquoted before the verb; the gate cannot see through it); `--force-confmiss` only at the `packages-microsoft-prod.deb` install. → `dotfiles-conventions.md` § `CLAUDE.md relocation: shell conventions (env which, prereq tests, sudo dpkg, apt conffile, sourcing guard)`
- Put a lib file's `[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0` guard on its last line, after all function definitions; not every lib file has one. → `dotfiles-conventions.md` § `CLAUDE.md relocation: shell conventions (env which, prereq tests, sudo dpkg, apt conffile, sourcing guard)`

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

- A `# [HAS_*]` Brewfile tag selects drift expectations only and never gates installation; every mac installs every main-Brewfile entry; to gate installation put the entry in `Brewfile.gui`/`Brewfile.devtools` (wrapped by `HAS_GUI`/`HAS_DEVTOOLS` in `install_macos_casks`). → `dotfiles-conventions.md` § `CLAUDE.md relocation: Brewfile HAS_ tag selects drift only`

- Tagging a Brewfile entry never keeps it off a machine; an uninstalled entry yields one advisory `Missing` line on every machine whose profile has the capability (6 of 8 hostnames for `devtools`). → `dotfiles-conventions.md` § `CLAUDE.md relocation: Brewfile HAS_ tag consequences`

- Never add both a formula and a cask for one tool; add new third-party taps to the `brew trust` call in `install_macos_casks`/`_install_ubuntu_brew_packages`. → `dotfiles-conventions.md` § `CLAUDE.md relocation: Brewfile formula/cask dedup and tap trust`

### PowerShell Scripts

See `~/.claude/standards/powershell.md` for the full PowerShell coding and testing standards.

### Windows AI Config Setup

- `setup_windows.ps1 -setup` links ai-config into `~/.claude/`, `~/.cursor/` and `$env:APPDATA\Cursor\User\`; set `GITHUB_PAT` in the system environment first (it fills `mcp.json`). → `dotfiles-conventions.md` § `CLAUDE.md relocation: Windows AI config link targets`

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

Ruby managers are not interchangeable: rbenv on Linux (`lib/linux_ubuntu.sh`), chruby on macOS; `install_ruby()` handles it, and the Linux build pins `RUBY_CONFIGURE_OPTS="--with-openssl-dir=/usr"`. → `dotfiles-conventions.md` § `CLAUDE.md relocation: Ruby version manager split`

## Language Standards

Language-specific standards for this repo. These supplement the universal standards loaded
from `~/.claude/CLAUDE.md` (tdd, behavior, git-workflow, ci, code-standards, logic-review,
repo-structure, shell).

Read `~/.claude/standards/powershell.md` before writing or changing PowerShell code or its lint and test configuration; it is not loaded at session start.

## Testing

Uses **BATS** (Bash Automated Testing System), installed natively:

`install_bats()` in `lib/helpers.sh` is a platform dispatcher (mirrors `install_zsh()`'s shape): `run_setup_user` calls it unconditionally on both macOS and Linux, so bats provisioning is no longer Linux-only.

- macOS: `install_bats_macos()` in `lib/macos.sh` — `brew install bats-core` (also listed in `Brewfile` for `brew bundle` parity)
- Ubuntu: `install_bats_linux()` in `lib/linux_shared.sh` — `sudo apt-get install -y bats`

**Run tests:** `make test` (runs lint, the lock and requirements-CI drift checks, the Python suite, then all BATS tests)

- Detect GNU parallel by version string (`parallel --version` matching `^GNU parallel`), never by presence — moreutils ships an incompatible `parallel`; `install_bats_linux` installs GNU `parallel` on Ubuntu and returns 2 for a parallel-only failure (a warning in `run_setup_user`).
- `JOBS` defaults to 24; override per call with `make test JOBS=6`, never `JOBS="$(nproc)"` (worst setting on a 2-vCPU runner). Force serial with `make test HAVE_PARALLEL=`.
- In a **test** that invokes make inside make, `unset MAKEFLAGS MFLAGS MAKELEVEL JOBS` (`tests/makefile_parallel_target.bats:21`); test-scoped only, since stripping `MAKEFLAGS` elsewhere drops `--no-print-directory`.
- The bats file list is a filesystem walk; add to `BATS_SERIAL_FILES` only with a measurement showing failure under `--jobs`. → `dotfiles-bats-test-infrastructure.md` § `Testing: make test parallelism and lint targets`

**Run unit tests only:** `make test-unit` (`unit.bats`, `profiles.bats`, `zshrc.d/unit.bats`)
**Run lint only:** `make lint` — `bash -n` over `SHELL_FILES` (from `scripts/list-shell-files.sh`), `zsh -n` over `ZSH_FILES` (from `git ls-files`), shellcheck at default severity for `SHELL_FILES` and `--severity=warning` for `.bats`; an empty list is never a pass. Missing `shellcheck` skips with a platform-correct install hint (`_OVERRIDE_PLATFORM` overrides `uname -s`); on Linux never `brew install` it, the pinned `/usr/local/bin/shellcheck` wins. → `dotfiles-bats-test-infrastructure.md` § `Testing: make test parallelism and lint targets`

- Keep `config/profiles.sh` in both `SHELL_FILES` and `ZSH_FILES` (sourced from `.zprofile` and `1_init.zsh`, must parse under both); update `Makefile`'s `ZSH_FILES` and `ci.yml`'s `lint-macos` pathspec together.
- `scripts/phrase_check.py` matches anchors whitespace-normalised, never line-oriented, and rejects anchors that open a sentence or paragraph; `test-python` runs only the checker's own unit tests, so it is no evidence the manifest is enforced. → `dotfiles-bats-test-infrastructure.md` § `Testing: make test parallelism and lint targets`

**Install hooks:** `make install-hooks` (installs pre-commit and pre-push hooks; run once per checkout)
**Sync agent guidance:** `make sync-agent-guidance` (regenerates `.cursor/rules/global-claude-standards.mdc` from root `CLAUDE.md`'s `@~/.claude/standards/*.md` imports, resolved against the global symlinked standards dir)
**Check agent guidance drift:** `make check-agent-guidance` (fails when generated Cursor guidance is stale)

- The venv is snapshotted (`pip freeze`) before every sync and that is the only rollback — `uv sync` prunes/downgrades and `uv.lock` cannot reproduce the old state. Roll back with `"$(pyenv which python)" -m pip install --no-deps -r ~/.local/share/dotfiles/venv-snapshots/ansible-<UTC>.txt`. → `dotfiles-bats-test-infrastructure.md` § `Testing: requirements CI renderings and venv rollback`

`--no-deps` is required — the state being restored is one the resolver refuses.

- `UV_BIN` (`resolve_uv`, `lib/helpers.sh`) is the operator override and the only seam that reaches the "not executable" branch; `UV_FALLBACK_PATHS` holds prefix candidates so a test can reach the genuine not-found branch (env-settable as a scalar).
- `REQUIREMENTS_CI_TARGET` (`scripts/sync-requirements-ci.sh`) points the drift check at a fixture so a crashed test cannot leave a modified tracked `requirements-ci.txt`. → `dotfiles-bats-test-infrastructure.md` § `Testing: requirements CI renderings and venv rollback`

- `make sync-requirements-ci` renders the five CI requirements files from `uv.lock`; `make check-requirements-ci` fails on any stale one and is a `make test` prerequisite. They are five deliberately separate files, never collapse them. → `dotfiles-bats-test-infrastructure.md` § `Testing: requirements CI renderings and venv rollback`

Renderings: `requirements-ci.txt` (`test-lint`, full local/dev set), `requirements-runtime-ci.txt` (`runtime`, no consumer), `requirements-ci-test.txt` (`ci-test`, per-PR jobs), `requirements-ci-mutation.txt` (`ci-mutation`), `requirements-ci-audit.txt` (`ci-audit`, dependency audit). → `dotfiles-bats-test-infrastructure.md` § `Testing: requirements CI renderings and venv rollback`

- Never harmonise the five requirements-CI renderings — `tests/setup_env/requirements_ci.bats` asserts distinctness: `test-lint` differs from `runtime`, and `test-lint`/`runtime`/`ci-test`/`ci-mutation` are four pairwise-distinct files. → `dotfiles-testing-toolchain.md` § `Requirements CI groups: do not harmonise (distinctness tests)`

- Scope CI requirements groups by purpose, not by pruning uninvoked tools: each group installs only what its own job runs (`ci-test` per-PR test/lint, `ci-mutation` mutation); keep `bandit`, `radon` and `vulture` in `test-lint` only.
- Never put provenance (a `uv.lock` SHA) in a rendering's header; provenance belongs on a consumer's own copy, at copy time.
- `ci-test`'s boundary is guarded by tests (no mutation whales such as `sqlalchemy`/`aiohttp`/`gitpython`; must stay materially smaller than `test-lint`); add a tool only on a measurement. → `dotfiles-bats-test-infrastructure.md` § `Testing: requirements CI renderings and venv rollback`

- A green `check-requirements-ci` is no evidence about grouping — it only proves a rendering is faithful to its declared group.
- Never hand-edit `requirements-ci.txt`; `scripts/sync-requirements-ci.sh` must strip and replace `uv export`'s argv-echoing header (not byte-deterministic), the Makefile guard must skip cleanly when `uv` is absent, and CI must install a pinned, checksum-verified `uv`. → `dotfiles-bats-test-infrastructure.md` § `Testing: requirements CI renderings and venv rollback`

- The pre-commit hook is required: `make lint`, then `ggshield secret scan pre-commit`.
- Resolve `ggshield` by explicit override, then `PATH`, then absolute prefixes — never `command -v` alone (a git hook inherits the invoker's `PATH`). If unresolvable, exit 0 but announce the skip twice on stderr, never silently. → `dotfiles-bats-test-infrastructure.md` § `Testing: pre-commit and pre-push hooks`

- The pre-push hook is permanent: it runs `make test` on every push and fails closed; one predicate, `_path_is_inert`, decides both the suite trigger and the master guard.
- Inert = a `.md` outside root `tests/` or the root `LICENSE`, as a regular file (mode `100644`/`100755`) not starting with `#!`; everything else runs the suite, including `.warp/settings.toml`, `renovate.json` and any `.sh` under `docs/` or `.github/`.
- An unresolvable diff range fails closed: the suite runs and a master push is refused with a message to `git fetch` and retry. → `dotfiles-bats-test-infrastructure.md` § `Testing: pre-commit and pre-push hooks`

- `scripts/pre-push` resolves repo root with `git rev-parse --show-toplevel` first, falling back to the `--git-common-dir` parent only if that fails (else it tests the shared checkout, not the worktree branch).
- It must `unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE` before `make test`, below the range-resolution loop (which needs the git environment); without it a worktree push leaks `GIT_DIR` into fixture-building tests. → `dotfiles-bats-test-infrastructure.md` § `Testing: pre-commit and pre-push hooks`

- Refuse any push to `refs/heads/master` whose range carries a path `_path_is_inert` rejects (`ci.yml` triggers on `pull_request` only); only inert `.md` and the root `LICENSE` go to master directly.
- Accumulate the refusal inside the stdin loop and read it after (never exit mid-loop); evaluate it before the `needs_test` early-exit and against the whole RANGE, not the tip; if it names a file you did not touch, run `git diff --name-only <remote-sha>..HEAD`.
- Emergency route (`hotfix-cycle`, `rollback-cycle`): open the PR and `gh pr merge --admin`; never bypass the hook. `.git/hooks/pre-push` symlinks the main checkout's copy, so a broken hook blocks every worktree; the one sanctioned recovery is a fix branch pushed with `--no-verify`, then a PR.
- `tests/scripts/docs_inert_premise.bats` pins that no test reads a tracked `.md` outside `tests/`; keep inert-set tests in `pre_push.bats` on feature refs and guard tests on master refs. → `dotfiles-bats-test-infrastructure.md` § `Testing: pre-commit and pre-push hooks`

### ShellCheck

`.shellcheckrc` carries **one** suppression, `SC1091` (lib source paths resolve at runtime via `$(dirname "${BASH_SOURCE[0]}")`), byte-identical across the four repos using the shared config; everything else is suppressed at its site with a reason on the same line, or fixed. → `dotfiles-bats-test-infrastructure.md` § `Testing: shellcheck conventions and lint scope`

The old blanket disable of `SC2086`/`SC2034`/`SC1091`/`SC2181` was reversed on purpose (2026-08-08), not eroded; history, finding counts and the `SC2181` defect it hid are in the pointer. → `dotfiles-bats-test-infrastructure.md` § `Testing: shellcheck conventions and lint scope`

Rules for any new suppression:

- Every `# shellcheck disable=` carries a reason on the same line naming the mechanism (for `SC2034`, the file and function that consume the variable); prefer deleting a dead variable to suppressing it.
- Verify the directive is live before writing its reason: delete it, re-run shellcheck, confirm the finding returns.
- A bare directive before a file's first non-comment command is file-wide, not next-command (shellcheck 0.11.0); `lib/constants.sh` and `config/profiles.sh` use that deliberately.
- shellcheck rejects a directive on a `case`-arm line (`SC1124`); it must precede the whole `case` and covers every arm, so state the blast radius. → `dotfiles-bats-test-infrastructure.md` § `Testing: shellcheck conventions and lint scope`

`make lint`'s scope comes from `scripts/list-shell-files.sh` (every tracked file whose first line is a bash/sh shebang, so extensionless hooks and `tests/mocks/` are included), not a literal list, `find` or a `git ls-files` pathspec; count it with `bash scripts/list-shell-files.sh | wc -l`, never a figure here. → `dotfiles-bats-test-infrastructure.md` § `Testing: shellcheck conventions and lint scope`

### CI / GitHub Actions

`.github/workflows/ci.yml` runs on PRs to master only (the pre-push hook gates branch pushes locally):

- `test` job: pinned, checksum-verified shellcheck plus bats, runs `make test`, then verifies test count >= 840 (regression proxy)
- `lint-macos` (blocks auto-merge): `bash -n` over the derived `SHELL_FILES` via `make print-SHELL_FILES | tr ' ' '\n' | xargs` (the `tr` is load-bearing: `xargs -I` does not split on blanks), and `zsh -n` over `git ls-files '*.zsh' '*.zsh-theme' '.zshrc' '.zprofile' 'config/profiles.sh'`, which must stay in step with `Makefile`'s `ZSH_FILES`; each step refuses an empty list.
- `test-macos` (blocks auto-merge; must stay in `auto-merge`'s `needs:` because the merge is a plain `gh pr merge --squash`): `make test` under GNU Make 3.81 with four unpinned Homebrew packages (bash, bats-core, parallel, coreutils for `timeout`); shellcheck and uv are pinned and checksum-verified; `scripts/ci-suite-report.sh <log> tests` fails unless the executed count equals the declared count and is above zero; on failure or cancellation the full log is uploaded as the artifact `test-macos-make-test-log`, since the 40-line tail can miss the cause; download it before re-running, because a re-run attempt replaces it; `permissions: contents: read`. Reasoning: ADR-0037.
  - A macOS failure cannot be reproduced on the Linux development box. Reproduce it on the Studio, in a bare environment like the runner's: → `dotfiles-bats-test-infrastructure.md` § `Testing: CI workflow jobs`

    ```bash
    ssh studio 'cd /tmp/<clone> && env -i HOME="$(mktemp -d)" \
      PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin \
      bats tests/<file>.bats' < /dev/null
    ```

    `/opt/homebrew/bin` on a provisioned mac holds more than the runner has, so the CI job remains the authority.
- `bash-coverage` job (ubuntu-latest, **gates at 91%**, blocks auto-merge): it runs the same suite as `test` in a separate job, so every tool `make test` depends on (e.g. pinned `uv`) must be installed in BOTH jobs and in `test-macos`; a CI-file assertion for that must parse per job and honour `working-directory:`, never grep the whole workflow.
- `secret-scan` (gitleaks over recent commits) blocks auto-merge: a deliberate deviation from `ci.md`'s advisory clause, since a leaked credential must not auto-merge.
- `auto-merge` needs `[test, lint-macos, test-macos, powershell, bash-coverage, secret-scan]` and `scripts/auto-merge-gate.sh` (run from the PR's **base** commit); it holds a bot PR (`author.is_bot`, ai-config ADR-0085) without `automerge-ok`, a `uv.lock` change without `pyproject.toml` and a truncated file list, and merges by PR number with `--match-head-commit`. Every job in `needs:` is a gate with no advisory tier (no `continue-on-error`, no `always()`).
- Every job declares `timeout-minutes` (a hung `powershell` once held auto-merge for GitHub's 360-minute default): `test` 20, `test-macos` 30, `bash-coverage` 60, `powershell` 5, 10 for `lint-macos`, `secret-scan`, `auto-merge` and `pr-title-lint.yml`; nothing asserts these values. → `dotfiles-bats-test-infrastructure.md` § `Testing: CI workflow jobs`

CI requirements:

- `lint-macos` and `test-macos` run on `macos-latest` and every other job on `ubuntu-latest`; every job sets `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: true`

### Testing Rules

- `load_setup_env()` does NOT set OS vars (`setup_env.sh` returns at its sourcing guard before `detect_env`): `MACOS`, `LINUX`, `UBUNTU` and `HAS_*` hold whatever the parent exported. A test depending on OS detection must set them itself (e.g. `unset MACOS; export LINUX=1; export UBUNTU=1`) or call `detect_env`; a test running a real platform tool (`stat`, `date`) sets the platform from `uname -s`.
- `run_update` tests stay off real pip because `load_mocks` (`tests/helpers/common.bash`) exports `MOCK_PYENV_WHICH_STDOUT` by default; a file calling `load_setup_env` without `load_mocks` loses it and a pip-section test then runs a real `pip install` (1–3 min).
- Every new function in `setup_env.sh` needs a test in `tests/setup_env/unit.bats` (pure logic) or `tests/setup_env/install_guards.bats` (side effects, mocks); every modified function updates its test; new shell scripts get their own `tests/` directory (e.g. `tests/scripts/`).
- Never modify real system state in tests — use PATH-based mocks from `tests/mocks/`.
- `tests/helpers/common.bash` unsets `GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE` when sourced (`git -C` does not override an exported `GIT_DIR`; #308); a bats file building git fixtures without that helper must strip the same four itself.
- `make test` must exit 0 before committing.
- When moving or renaming a directory tests reference, run `grep -r "<old-path>" tests/` first — hardcoded fixture paths break even when production code uses `$PERSONAL_GITREPOS/$DOTFILES/` prefixes. → `dotfiles-bats-test-infrastructure.md` § `Testing: Testing Rules detail`

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

- Floor 90%; `make test` and CI fail below it. Scope: `setup_windows.ps1` only (`run-tests.ps1`, `run-lint.ps1` and the top-level `if ($IsWindows)` dispatcher are excluded as glue; `$IsWindows` cannot be overridden in tests).
- Re-measure: `cd powershell && make test` prints `Coverage: <N>%` and writes `coverage.xml`. → `dotfiles-bash-coverage.md` § `Testing: PowerShell coverage scope`

#### Bash

- Derive the instrumented set from `git ls-files`, never a glob (`config/local.sh` is git-ignored and machine-local): `setup_env.sh` plus tracked `config/*.sh`, `lib/*.sh`, `scripts/*.sh` and the two extensionless hooks, less `scripts/bash-tracer.sh`. Check it with `bash scripts/run-bash-coverage.sh --list-sources`.
- The denominator counts commands, not source lines: heredoc bodies, multi-line `python3 -c "..."` bodies, multi-line array literals and pure-argument backslash continuations are excluded (not if the continuation contains `||`, `&&`, `|` or `;`); a multi-line **single-quoted** body (`awk '`, `python3 -c '`) is NOT excluded, so put long awk/python programs in their own file under `lib/` and run them with `-f`. Never add a function-declaration exclusion.
- The denominator is the union of the static heuristic and the real trace, so `covered <= coverable` holds by construction; read the heuristic-disagreement count beside the ratio from the same run. `covered > coverable` is a hard non-zero exit, never a silent clamp. Inspect with `bash scripts/run-bash-coverage.sh --count-coverable <file>` and `--file-coverage <file> <trace>`. → `dotfiles-bash-coverage.md` § `Testing: bash coverage rules`

- Publish CI's bash coverage figure in the PR body once CI has run (`gh pr edit <n>`); a local run is a preview and must be labelled as one.
- `make bash-coverage` runs the traced suite in parallel (`COVERAGE_BATS_JOBS=$(JOBS)`) when GNU parallel is detected and `BATS_SERIAL_FILES` is empty (the log's `bats mode:` line says which); force serial with `make bash-coverage HAVE_PARALLEL=`, set workers with `JOBS=<n>`; `HAVE_PARALLEL= make bash-coverage` does nothing (the `Makefile` reassigns it with `:=`); `bash scripts/run-bash-coverage.sh --print-bats-args` prints the argv. → `dotfiles-bash-coverage.md` § `Testing: bash coverage rules`

### Test Seams

- A new test seam's description goes to `ai-config/docs/knowledge/dotfiles-test-seams.md`; `CLAUDE.md` gets a one-line rule and pointer only.


- A test seam is a variable with a production default — `local _file="${VAR:-<real path>}"` — not a naming rule: seams below are named `_RUSTUP_INIT_*`, `GGSHIELD_BIN`, `LEDGER_BIN`, `_AWS_*`, `_RHN_*`, `_CARGO_BIN`, and more.
- In tests, set the seam variable to a writable temp copy; leave it unset in production code. → `dotfiles-test-seams.md` § `Test seam idiom and override pattern`

- `tests/mocks/pyenv install` creates its version dir only when `HOME` matches `*/bats-run-*` (keyed on `HOME`, never `PYENV_ROOT`); inject failure with `${HOME}/.mock-pyenv-install-exit`, not an env var; assert effects on disk or in `${HOME}/.mock_calls`. → `dotfiles-test-seams.md` § `CLAUDE.md relocation: pyenv mock install under env -i`

- `_RUSTUP_INIT_URL`/`_RUSTUP_INIT_SHA256`/`_RUSTUP_INIT_BIN`/`_OVERRIDE_CARGO_BIN_DIR` stop `_install_rustup_rs` reaching the network from a fake `HOME`; set all four per test.
- Never mock `sha256sum`; supply the real digest in `_RUSTUP_INIT_SHA256`, computed over `MOCK_CURL_STDOUT`'s exact bytes (`tests/mocks/curl` never fetches). → `dotfiles-test-seams.md` § `CLAUDE.md relocation: rustup install seams and digest rule`

- `_OVERRIDE_NVIDIA_GPU_PRESENT` makes install and skip branches testable (never mock `lspci`); point `_OVERRIDE_NVIDIA_KEYRING`/`_OVERRIDE_NVIDIA_LIST` at fixtures, never the real `/usr/share/keyrings` or `/etc/apt/sources.list.d`. → `dotfiles-test-seams.md` § `CLAUDE.md relocation: NVIDIA detection and keyring seams`

- `_OVERRIDE_CONFFILE_DIST_ROOT` (`lib/helpers.sh:_doctor_check_conffile_dist`)
  - Point it at a fixture directory, never the real `/etc`; tests must set or unset `LINUX` explicitly, since developer shells export it and the check returns early without it.

- Set `_OVERRIDE_DOCKER_DAEMON_JSON` to a fixture and always use `tests/mocks/nvidia-ctk` (`MOCK_NVIDIA_CTK_WRITES`/`MOCK_NVIDIA_CTK_TARGET`/`MOCK_NVIDIA_CTK_EXIT`): the `sudo` mock otherwise execs the real `nvidia-ctk` against the live `/etc/docker/daemon.json` (absent on the Studio, so a green local run proves nothing). → `dotfiles-test-seams.md` § `CLAUDE.md relocation: docker daemon.json seam and nvidia-ctk mock`

- Use `brew_install_cask`/`brew_cask_installed` for a Cask, never `brew_formula_installed` (never matches a cask; reinstalls every run). → `dotfiles-test-seams.md` § `CLAUDE.md relocation: cask helper rule`

- `config/profiles.zsh` and `lib/detect_env.sh` derive `PROFILE`/`HAS_*`/the eight legacy identity vars from one `config/profiles.sh` table; `tests/zshrc.d/cross_shell.bats` asserts both agree.
- Keep `tests/helpers/legacy_oracle.bash` hand-typed, never derived from `PROFILE_LEGACY` (no `eval`, no indirect sourcing of `config/profiles.sh`): a derived oracle passes a mis-mapped table. Verify with a self-consistent swap of `reception<->ratna`, never `laptop`/`studio` (ADR-0021). → `dotfiles-test-seams.md` § `CLAUDE.md relocation: profile table single source and hand-typed oracle`

- `config/profiles.zsh` uses `export`, never `readonly` (sourced twice per shell; reassignment returns 126); `lib/detect_env.sh` `readonly` is correct, do not align them. → `dotfiles-test-seams.md` § `CLAUDE.md relocation: profiles export versus readonly`

- Drive `_OVERRIDE_HOMEBREW_PREFIX_ARM`/`_OVERRIDE_HOMEBREW_PREFIX_INTEL` present and absent through the override, never the real filesystem (`/opt/homebrew` and `/usr/local/opt` exist on a provisioned mac, so an unset override asserts nothing). → `dotfiles-test-seams.md` § `CLAUDE.md relocation: homebrew prefix override seams`

- Test keychain absence through `_OVERRIDE_KEYCHAIN_BIN` (the real path is absolute, not mockable via `PATH`); keep the block inside `[[ -o interactive ]]` (non-interactive source starts a daemonizing `ssh-agent` that hangs `make test`), keep `"${_keychain}" --eval` quoted, keep `setopt shwordsplit` in `tests/zshrc.d/unit.bats` (else the `--eval` quoting assertion is vacuous), leave `[[ ${VAR} ]]` tests in `5_general.zsh` unquoted (`[[ ]]` never word-splits; quoting is churn), and keep the non-interactive and interactive tests as a pair. → `dotfiles-test-seams.md` § `CLAUDE.md relocation: keychain override seam and interactive guard`

- Set `_OVERRIDE_CURRENT_LOGIN_SHELL` in every login-shell test (else the pass is machine-dependent); derive the login shell from `getent passwd`/`dscl UserShell`, never `${SHELL}`; check both `chsh` and `sudo -n chsh` exit codes; stub `_doctor_check_login_shell` in end-to-end `run_doctor` tests. → `dotfiles-test-seams.md` § `CLAUDE.md relocation: login shell override seam and chsh guard`

- Set `_OVERRIDE_GNUBIN_ARM`/`_OVERRIDE_GNUBIN_INTEL` to a nonexistent path to reach the absent branch (the real gnubin exists on a provisioned mac); keep the default pair identical in `install_make_macos` and `6_path.zsh`. → `dotfiles-test-seams.md` § `CLAUDE.md relocation: gnubin arm and intel seams`

- Set `_OVERRIDE_GNUBIN_LINUX` to a nonexistent path to reach the absent branch (real linuxbrew gnubin exists on `claude`-class boxes); keep its default identical in both readers and assert they stay equal. → `dotfiles-test-seams.md` § `CLAUDE.md relocation: gnubin linux seam`

- Point `_OVERRIDE_DOCKER_BIN` at `/nonexistent/docker-bin` in `tests/zshrc.d/unit.bats` for the absent branch; delete Docker Desktop's re-added `.zprofile` PATH lines rather than committing them. → `dotfiles-test-seams.md` § `CLAUDE.md relocation: docker bin override seam`

- Drive ggshield absence only via `GGSHIELD_BIN`/`GGSHIELD_FALLBACK_PATHS`, never by editing `PATH` (removes `git`/`make` too); a non-executable `GGSHIELD_BIN` is a hard error. → `dotfiles-test-seams.md` § `CLAUDE.md relocation: ggshield override seams`

- When exercising `LEDGER_BIN`/`ledger_write_entry` always prepend `tests/mocks/ledger` to `PATH`; a `HOME`-only redirect loses to a real `ledger` on `PATH` (`workstation`/`claude`). → `dotfiles-test-seams.md` § `CLAUDE.md relocation: ledger bin seam`

- `_OVERRIDE_LIB_TRAP_SCOPE` makes `scripts/check-lib-exit-traps.sh` use a plain glob; keep one no-override test against the real `lib/` asserting a non-empty scanned set, since the production path (`git ls-files` under the four-variable `env -u GIT_*` strip) is otherwise untested. → `dotfiles-test-seams.md` § `CLAUDE.md relocation: lib trap scope seam`

- Drive bats absence only via `_OVERRIDE_BATS_BIN`, never by editing `PATH` (removes the toolchain); land seam and test in one commit; reproduce a CI-only failure from `git archive <sha>`, never a dirty tree. → `dotfiles-test-seams.md` § `CLAUDE.md relocation: bats bin override seam`

- Set `_OVERRIDE_RUN_TMPDIR_ROOT` to isolate the `mktemp -d` error path in `_dotfiles_run_tmpdir_setup`; `TMPDIR` alone cannot (bats leaves it on the system temp dir). → `dotfiles-test-seams.md` § `CLAUDE.md relocation: run tmpdir root seam`

- `detect_env()` resets `_PROFILES_LOADED=0` on entry and sets `1` only after `config/profiles.sh` loads with all three arrays; never derive it from `PROFILE` and never trust an inherited `_PROFILES_LOADED=1`. → `dotfiles-test-seams.md` § `CLAUDE.md relocation: profiles loaded sentinel`

- Resolve `_AWS_GPG_BIN`/`_AWS_PKGUTIL_BIN` via `command -v`, never by stripping `PATH`; keep `_AWS_KEY_PATH` a plain source-time assignment from `DOTFILES_REPO_ROOT` in `lib/constants.sh` (no `${VAR:-}` self-guard, no inline `dirname BASH_SOURCE`); test its cwd-sensitivity by sourcing relatively, `cd`-ing away and asserting the post-import failure message. → `dotfiles-test-seams.md` § `CLAUDE.md relocation: AWS verification seams and key path`

- Point `_MS_GPG_BIN` (also the gpg for `_build_pinned_keyring`, `_keyring_has_pinned_fpr` and albert) at the real gpg at setup scope in `tests/setup_env/linux_ubuntu.bats` with `MOCK_WGET_FILE` set to `tests/fixtures/packages-microsoft-prod.deb` (`tests/mocks/gpg` verifies nothing); `_MS_AR_BIN` needs GNU `ar` (skip on macOS without it, fail elsewhere); `_MS_KEY_PATH` (default: the vendored `microsoft.asc`) is also read by `_install_ubuntu_edge_source`; never sha256-pin that deb; `_ms_verify_deb` must refuse any archive not listing exactly `debian-binary control.tar.gz data.tar.gz _gpgorigin` in order (dpkg reads the first member, `ar x` the last). → `dotfiles-test-seams.md` § `CLAUDE.md relocation: Microsoft deb verification seams`

- Set `_AWS_BIN` in every `install_aws_tools` test (a real `/usr/local/bin/aws` makes the already-installed guard always taken). → `dotfiles-test-seams.md` § `CLAUDE.md relocation: aws bin seam`

- Set `_EDGE_SOURCES_DIR`/`_EDGE_BOOTSTRAP_KEYRING` at setup scope in `tests/setup_env/linux_ubuntu.bats` (`tests/mocks/sudo` execs real commands; unset writes the real `/etc/apt/sources.list.d` and `/usr/share/keyrings`); the bootstrap fails closed on any unverifiable key, and a gpg or local failure (rc 2/3) keeps the last verified keyring and `.list` (only rc 1 or no non-empty keyring removes them). → `dotfiles-test-seams.md` § `CLAUDE.md relocation: edge source seams`

- Set `_APT_SOURCES_DIR`/`_APT_TRUSTED_DIR`/`_APT_KEYRINGS_DIR` at setup scope in `tests/setup_env/linux_ubuntu.bats` (unset: albert and azure cleanup write and `rm -f` under real `/etc/apt` and `/usr/share/keyrings`).
- `_HASHICORP_SOURCE_DIR`/`_HASHICORP_KEY_PATH` are honoured only when `BATS_TEST_TMPDIR` is non-empty; `_APT_SOURCES_LIST` points the hand-written-source warning at a fixture. → `dotfiles-test-seams.md` § `CLAUDE.md relocation: apt directory and hashicorp seams`

- `_APT_KEY_TMP_ROOT` (`lib/linux_ubuntu.sh:_build_pinned_keyring`, `_install_ubuntu_albert`)
  - Point it at a test-owned directory: BSD `mktemp -d` with a template ignores `TMPDIR`, so a `TMPDIR`-based isolation or cleanup assertion is silently inert on the Studio.

- `_ALBERT_KEY_URL` (`lib/linux_ubuntu.sh:_install_ubuntu_albert`)
  - A production escape hatch for the key URL. Tests feed the key through `MOCK_CURL_STDOUT` per test, never at setup scope, so each case controls which key the fetch returns.

- `load_mocks` stubs `_BREW_AZ_BIN` (`MOCK_BREW_AZ_EXIT`); unset it only for prefix-branch tests; production refuses `/bin/az` and `/usr/bin/az` as the probe. → `dotfiles-test-seams.md` § `CLAUDE.md relocation: brew az probe seam`

- `_build_pinned_keyring <key> <keyring> <fpr>` pins the PRIMARY key fingerprint only and never modifies the final keyring on failure (rc 0 installed, 1 not pinned, 2 no key, 3 local failure). → `dotfiles-test-seams.md` § `CLAUDE.md relocation: pinned keyring builder`

- Cadence seams exist because absolute paths and external binaries are unreachable by a `PATH` mock; none grants more than editing `PATH` or the plist already would. → `dotfiles-test-seams.md` § `CLAUDE.md relocation: cadence seams overview line`

- Cadence seams (`_RHN_STATE_DIR`, `_RHN_LAUNCHCTL`, `_RHN_AGENT_DIR`, `_RHN_LOCAL_CFG` exported in `setup()` not per test, `_RHN_CURL_BIN`, `_RHN_MKTEMP`, `_RHN_DETECTOR`, `_RHN_MAX_AGE_DAYS`, `_OVERRIDE_DOTFILES_ROOT`, `_OVERRIDE_AI_CONFIG_ROOT`): point each at a fixture so no test touches the live heartbeat state, `launchctl`, `~/Library/LaunchAgents`, the real `config/local.sh` or ntfy; round-trip `_RHN_MAX_AGE_DAYS` at a non-default value. → `dotfiles-test-seams.md` § `CLAUDE.md relocation: cadence seam table`

- Write `max_age_days` into the heartbeat and name the source of a fallback (`from heartbeat` vs `default`); keep `held`/`incomplete`/`clean`/`pending` pairwise-unequal, `pending` seeded at install, a reinstall never clobbering a real heartbeat.
- Detector stdout is findings one per line and nothing else; stderr (capped at 20 lines) goes to ntfy, so never print credentials or env dumps there.
- Keep heartbeat fields closed-form via `printf`: no free text, no `python3 -c json.dumps`. → `dotfiles-test-seams.md` § `CLAUDE.md relocation: cadence heartbeat contract rules`

- List every detector dependency in the cadence plist `PATH` (launchd sources no profile) and check a new one with `env -i PATH=<plist PATH> bash -c 'command -v <tool>'`; a template edit does not reach installed agents: re-run `setup_env.sh -t setup_user` and verify the live `~/Library/LaunchAgents/*.plist`. → `dotfiles-test-seams.md` § `CLAUDE.md relocation: cadence agent PATH rules`

- POST to `${NTFY_URL}/${NTFY_TOPIC}` with auth (never bare `${NTFY_URL}`); send credentials on stdin via `curl -K -`, never `-u`; refuse (never escape) a credential containing a newline; run the detector under `env -u NTFY_URL` and keep the heartbeat as a second silent-when-clean channel. → `dotfiles-test-seams.md` § `CLAUDE.md relocation: cadence ntfy delivery rules`

- This group covers the pyenv shim defect and the cargo plugin repair added 2026-09-17; treat each seam below individually, not as one combined pyenv/cargo unit. → `dotfiles-test-seams.md` § `Pyenv-rehash and cargo-tools seams overview`

- Set `_OVERRIDE_PYENV_ROOT` in every test touching shim counting or the pyenv-rehash hook install (`PYENV_ROOT` outranks a fixture `HOME`). → `dotfiles-test-seams.md` § `CLAUDE.md relocation: pyenv root override seam`

- `load_mocks` exports `_CARGO_BIN` to a recording mock (else a real `~/.cargo/bin/cargo` compiles all eight `CARGO_TOOLS`); a test of the other resolution branches unsets it and isolates itself.
- `load_mocks` exports `_OVERRIDE_RUSTUP_BREW_KEGS` to a nonexistent dir (else `update_rust` runs a real `rustup update`); keg-branch tests point it at a fixture. → `dotfiles-test-seams.md` § `CLAUDE.md relocation: cargo and rustup keg default exports`

- Set `_RELEASE_BIN_DIR` (`_install_pinned_release_binary`) and `_TFENV_LINK_DIR` (`_install_ubuntu_tfenv`) to a test-owned scratch dir in every install-path test (`tests/mocks/sudo` execs real writes into `/usr/local/bin`). → `dotfiles-test-seams.md` § `CLAUDE.md relocation: release bin dir and tfenv link dir seams`

- Set `_RELEASE_TMP_ROOT` when asserting `_install_pinned_release_binary` failure-path cleanup (BSD `mktemp -d` with a template ignores `TMPDIR`; the Studio's is BSD). → `dotfiles-test-seams.md` § `CLAUDE.md relocation: release tmp root seam`

- Set `_DL_STAMP_DIR`/`_DL_TMP_ROOT`/`_DL_BIN_DIR`/`_DL_UNZIP_BIN`/`_DL_TAR_BIN` all at setup scope (`tests/mocks/sudo` execs real commands; unset writes the real `/usr/local/bin`); `rm` the stamp file to force a re-install. → `dotfiles-test-seams.md` § `CLAUDE.md relocation: fetched binary install seams`

- Release asset pins (kind, yq, shellcheck; ADR-0046) are `<TOOL>_SHA256_AMD64`/`_ARM64`/`_FOR_VER` in `lib/constants.sh`: bump `*_VER`, run `scripts/refresh-sha256-pins.sh [tool...]`, commit both; tests of callers set the real pin and `_FOR_VER` variables, never `_FETCHED_URL`/`_FETCHED_SHA256`/`_REFRESH_ASSET_URL`/`_OVERRIDE_REFRESH_PINS`. → `dotfiles-test-seams.md` § `CLAUDE.md relocation: release asset sha256 pins`
- packer and vagrant install via `_install_ubuntu_hashicorp`, never the pinned-release route; after the migration, run `brew uninstall packer consul vault nomad` on each mac before the first `-t setup`/`-t developer`/`--brew-install` (`install_macos_casks` refuses while homebrew-core `packer` is present) and on Linux hand-remove unstamped `/usr/local/bin` leftovers. → `dotfiles-test-seams.md` § `CLAUDE.md relocation: release asset sha256 pins`

- Set `_GO_INSTALL_ROOT` at setup scope (default `/usr/local`; unset, a go test replaces the real `/usr/local/go`) and pair it with a per-test `_GO_BIN` stub; `_GO_SHA256` replaces the per-arch pin and `sha256sum` is never mocked. → `dotfiles-test-seams.md` § `CLAUDE.md relocation: go install seams`

- `_APT_KEY_GPG_BIN` (`lib/linux_ubuntu.sh:_install_apt_keyring`)
  - Default `gpg`; tests point it at `tests/mocks/gpg-dearmor`, because `tests/mocks/gpg` never writes its `-o` target and an empty keyring counts as a failed fetch.

- `_DOCKER_KEYRING`/`_DOCKER_SOURCES_LIST` (`lib/linux_ubuntu.sh:_install_ubuntu_docker`)
  - Defaults `/etc/apt/keyrings/docker.asc` and `/etc/apt/sources.list.d/docker.list`; set both at setup scope so the sudo mock cannot write the real `/etc/apt`.

- `MOCK_WGET_FAIL_URL`/`MOCK_CURL_FAIL_URL`/`MOCK_APT_FAIL_SUBCMD`/`MOCK_MV_FAIL_ARGS` fail only the matching call; set `SHIM_*` variables (`SHIM_DIR` in `tests/setup_env/linux_ubuntu.bats`) per test, never at setup scope (real `usermod`/`flatpak` would run). → `dotfiles-test-seams.md` § `CLAUDE.md relocation: mock failure knobs and SHIM_DIR shims`

- Drive tflint/tfsec via `_TFLINT_URL`/`_TFLINT_SHA256`/`_TFSEC_URL`/`_TFSEC_SHA256` with a local fixture URL and a deliberately wrong checksum; never mock `sha256sum`. → `dotfiles-test-seams.md` § `CLAUDE.md relocation: tflint and tfsec seams`

- Isolate tfenv's clone with `_TFENV_ROOT` (not a real `~/.tfenv`) and fail it via `_TFENV_REPO_URL`, never a real network call. → `dotfiles-test-seams.md` § `CLAUDE.md relocation: tfenv root and repo url seams`

- Drive all three pwsh states through `_PWSH_BIN` and the timeout through `_PWSH_PROBE_TIMEOUT`; test the `timeout`-absent fallback with a scoped `PATH` and a `#!/bin/bash` stub, in both directions. → `dotfiles-test-seams.md` § `CLAUDE.md relocation: pwsh probe seams`

- `load_mocks` exports `_NVIDIA_MODULE_VERSION_FILE` to a nonexistent path (a real one exists on `claude`/`workstation`); redefine `_flatpak_available` in tests, never strip `tests/mocks` from `PATH` (exposes the real `/usr/bin/flatpak`). → `dotfiles-test-seams.md` § `CLAUDE.md relocation: nvidia module version and flatpak mock rules`
- Drive `tests/mocks/flatpak` with `MOCK_FLATPAK_LIST_RUNTIME` (a file; exit 99 if missing)/`MOCK_FLATPAK_LIST_APP`/`MOCK_FLATPAK_FAIL_SUBCMD`/`MOCK_FLATPAK_FAIL_ARGS`; `tests/fixtures/flatpak/runtime-list.tsv` is captured real output, never hand-typed. → `dotfiles-test-seams.md` § `CLAUDE.md relocation: nvidia module version and flatpak mock rules`

- Drive the doctor probe timeout with a sleeping stub under `_DOCTOR_PROBE_TIMEOUT=1`, never the real 10 s default. → `dotfiles-test-seams.md` § `CLAUDE.md relocation: doctor probe timeout seam`

- Drive `_doctor_check_brew_links` only through `_BREW_BIN` and `_BREW_FALLBACK_PATHS` (`load_mocks` stubs both, since every fleet and CI box has a real brew at a fallback path) and its bound only through `_TIMEOUT_FALLBACK_PATHS` and `_DOCTOR_BREW_TIMEOUT`; reach the no-brew and no-timeout branches with a per-call scoped `PATH` of stubs (`PATH="${_BIN_DIR}" <call>`), never by editing the inherited `PATH`. → `dotfiles-test-seams.md` § `doctor brew links seams`

- Override `_CRATES_API` for any `CARGO_TOOLS` staleness test that needs an unreachable crates.io. → `dotfiles-test-seams.md` § `CLAUDE.md relocation: crates api seam`

- Set the sysctl seams (`_SYSCTL_CONF`, `_SYSCTL_BIN`, `_INOTIFY_PROC`, `_SYSTEMD_RUN_DIR` and `_KEYS_MAXKEYS_CONF`, `_KEYS_MAXKEYS_PROC`, `_KEYS_MAXBYTES_CONF`, `_KEYS_MAXBYTES_PROC`) under `BATS_TEST_TMPDIR` (`load_mocks` does) so `sudo`/`sysctl` never reach the real `/etc/sysctl.d` or kernel; a test reaching the real inotify step sets or unsets `HAS_DOCKER` itself (developer shells export it); no test runs the step with `_SYSCTL_CONF` unset (`_sysctl_conf_write` is tested behind a recording `sudo` shim). → `dotfiles-test-seams.md` § `CLAUDE.md relocation: sysctl and kernel keys seams`

- `_GITHUB_API` accepts only `https://api.github.com` or `http://127.0.0.1:<port>` (else warns and falls back) so a stray export cannot send the token off-host; every token-bearing curl passes `--noproxy 127.0.0.1` and sends the header via `-H @-` (assert with `MOCK_CURL_STDIN_FILE`); use `tests/helpers/http_listener.bash` for real-curl header tests and call `stop_http_listener` from `teardown()`; `_github_auth_header` refuses a token containing a line break. → `dotfiles-test-seams.md` § `CLAUDE.md relocation: github api seam and http listener`

- Isolate Claude provisioning with `_OVERRIDE_CLAUDE_SETTINGS` (`load_mocks` points it at a per-test copy of `tests/fixtures/claude-settings.json`, never the tracked fixture), `_CLAUDE_GUARD_GIT` and `tests/mocks/claude`, so no test touches the real `${HOME}/.claude/settings.json` or the real `claude`/`git`. → `dotfiles-test-seams.md` § `CLAUDE.md relocation: claude settings override seam`

- Resolve git through `_CLAUDE_GUARD_GIT` in guard tests (private shim dir holding a symlink to the real `git`, mocks stripped from `PATH`), never `tests/mocks/git` alone. → `dotfiles-test-seams.md` § `CLAUDE.md relocation: claude guard git seam`

- Drive `tests/mocks/claude` with `MOCK_CLAUDE_PLUGINS_LIST_JSON`/`MOCK_CLAUDE_MARKETPLACE_LIST_JSON`, `MOCK_CLAUDE_FAIL_ARGS`, `MOCK_CLAUDE_FAIL_ON_CALL=<n>` and `MOCK_CLAUDE_EDIT_SETTINGS=<verb>`. → `dotfiles-test-seams.md` § `CLAUDE.md relocation: tests/mocks/claude modes`

- Redirect stdin from `/dev/null` on every `claude` call inside a `while read` loop (it eats the loop's here-string).
- Split manifest lines with `_claude_manifest_split_line`; never emit an empty tab-separated field (use `-`). → `dotfiles-test-seams.md` § `CLAUDE.md relocation: claude loop stdin and IFS tab rules`

- Set `_OVERRIDE_CLAUDE_PLUGIN_CACHE` in `setup()` of both test files, not per test (the repair rewrites files; unset edits the operator's real `~/.claude/plugins/cache`). → `dotfiles-test-seams.md` § `CLAUDE.md relocation: claude plugin cache override seam`

### Mock Pattern

- The full `MOCK_*` env var reference table and the general mock usage pattern live in `dotfiles-bats-test-infrastructure.md` — this group's own suffix target, not a `CLAUDE.md` section. → `dotfiles-bats-test-infrastructure.md` § `Mock Pattern full reference pointer (superseded by this section)`

- `tests/mocks/ln`, `chmod`, `mv`, `cp` and `tee` pass through to the real binary (`|| true`), so drive a failure with the mock's exit variable (`MOCK_CP_EXIT` / `MOCK_MV_FAIL_ARGS` / `MOCK_TEE_EXIT`) or a `SHIM_DIR` shim, never by expecting the real binary to fail.
- `tests/mocks/sudo` execs with the caller's environment except `DEBIAN_FRONTEND`, which it unsets unless given on the sudo command line (as real sudo does); `tests/setup_env/mocks_sudo.bats` pins that. → `dotfiles-bats-test-infrastructure.md` § `Testing: mock pattern detail`

- `env -i` strips `PATH`, so a `PATH`-injected pyenv mock is invisible to the `env -i` build in `_ensure_pyenv_python` (reached from `setup_ansible` and `recreate_python_venv`) — place the mock binary at the absolute path `${HOME}/.pyenv/bin/pyenv` instead. → `dotfiles-bats-test-infrastructure.md` § `Mock Pattern: env -i strips PATH (pyenv mock placement) -- CLAUDE.md addendum`

- `tests/mocks/curl` parses any `-[a-zA-Z]+` short-option cluster: an `f` sets fail-mode, a cluster ending in `o` takes the next arg as the `-o` target; `MOCK_CURL_HTTP_STATUS` applies only when `MOCK_CURL_EXIT` is unset, an f-bearing form was passed and the value matches `^[0-9]+$` (`>= 400` fails); `MOCK_CURL_EXIT` always wins. → `dotfiles-bats-test-infrastructure.md` § `Testing: mock pattern detail`

- `tests/mocks/curl` defers its `-o` write until after the exit code is decided (a simulated failure leaves a pre-seeded target unchanged); on success it writes `MOCK_CURL_STDOUT` to the target AND still emits it on stdout — keep the dual emission for callers that never pass `-o` (`whats-new*.sh`, `_fetch_github_latest`, `install_homebrew`), and verify no caller both passes `-o` and consumes stdout before removing it. → `dotfiles-bats-test-infrastructure.md` § `Testing: mock pattern detail`

### MAKEFLAGS and Stdout Partition

- `Makefile:1`'s `MAKEFLAGS += --no-print-directory` only silences `Entering`/`Leaving directory` for child makes inheriting it on GNU Make 4.0+; a direct `make -C` on 4.3 still prints before parse, so the per-call flag plus the partition below is the load-bearing protection. → `dotfiles-bats-test-infrastructure.md` § `Testing: MAKEFLAGS partition detail`

- `MAKEFLAGS` is an exported env var every `make` inherits; a test capturing `make` output is either guarded (per-call `--no-print-directory`, for exact output shape) or measuring (`env -u MAKEFLAGS` prefix, only to observe directory lines, never for a guarded assertion on GNU Make 4.3). Both categories must exist. → `dotfiles-bats-test-infrastructure.md` § `Testing: MAKEFLAGS partition detail`

- `tests/scripts/makefile_lint_scope.bats` requires every stdout-capturing `make -C` in exactly one category; derive its domain from `git ls-files` with `env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE`, never a hardcoded list. → `dotfiles-bats-test-infrastructure.md` § `Testing: MAKEFLAGS partition detail`

- The partition scanner is blind to recursive `$(MAKE)` calls and `-w`/`--print-directory`, and `powershell/Makefile` is outside its domain; not exploitable today, an accepted boundary. → `dotfiles-bats-test-infrastructure.md` § `Testing: MAKEFLAGS partition detail`

## Committing Work

Invoke `caveman:caveman-commit` skill to generate the commit message before running `git commit`. Full format and rules in `~/.claude/CLAUDE.md`.

## Key Conventions

- Prefer `HAS_*` vars from `config/profiles.sh` over raw hostname patterns in new code. → `dotfiles-conventions.md` § `CLAUDE.md relocation: Key Conventions platform, update-section and install-function rules`
- Gate GPU provisioning on `_nvidia_gpu_present` (PCI `10de:` in `lspci -nn`), never a `HAS_*` capability; no `lspci` means skip. → `dotfiles-conventions.md` § `CLAUDE.md relocation: Key Conventions platform, update-section and install-function rules`
- After driver/toolkit install run `nvidia-ctk runtime configure --runtime=docker`; restart docker only if `daemon.json` changed (live GitHub runners). → `dotfiles-conventions.md` § `CLAUDE.md relocation: Key Conventions platform, update-section and install-function rules`
- Create credential dirs (`.aws`, `.tf_creds`, `.tsh`) with `chmod 700`. → `dotfiles-conventions.md` § `CLAUDE.md relocation: Key Conventions platform, update-section and install-function rules`
- Ansible venv packages live only in `pyproject.toml` `[dependency-groups]`; change a version there then run `uv lock`; installs use `uv sync --frozen`. → `dotfiles-conventions.md` § `CLAUDE.md relocation: Key Conventions platform, update-section and install-function rules`
- After a venv recreate run `brew uninstall ruff` once (ruff is venv-managed, not brew). → `dotfiles-conventions.md` § `CLAUDE.md relocation: Key Conventions platform, update-section and install-function rules`
- Keep application installs in alphabetical order. → `dotfiles-conventions.md` § `CLAUDE.md relocation: Key Conventions platform, update-section and install-function rules`
- Syntax-check with `bash -n <file>` (files from `scripts/list-shell-files.sh`) or `zsh -n <file>` for zsh files; `make lint` runs both. → `dotfiles-conventions.md` § `CLAUDE.md relocation: Key Conventions platform, update-section and install-function rules`
- After any `.zshrc`/`.zshrc.d/` change run `zsh -i -c 'exit'` before committing; in a worktree it only proves the main checkout, so source the branch's own files explicitly. → `dotfiles-conventions.md` § `CLAUDE.md relocation: Key Conventions platform, update-section and install-function rules`
- Never rely on `$0` as a startup file's path in zsh (it is the literal `zsh`); use `${${(%):-%x}:A:h}` for a file's directory. → `dotfiles-conventions.md` § `CLAUDE.md relocation: Key Conventions platform, update-section and install-function rules`
- A new update section needs `_update_record_start/end` AND its `_UPDATE_SECTION_ORDER` entry together (omitting the entry hides it silently); on removal grep test fixtures for a stray seed of the name. → `dotfiles-conventions.md` § `CLAUDE.md relocation: Key Conventions platform, update-section and install-function rules`
- Never run `scripts/sync_git_repos.sh` (or `sync_git_repos`/`sync_legacy_dirs`) unmocked outside BATS; it does real `git push`/`rsync --delete` over SSH and keys off the real `hostname -s`; `-t update` runs it too (`git-repos`/`legacy-rsync` sections), so `-t update` does the same real push and `rsync --delete`; never run it to exercise a change, and use `--dry-run` to suppress the outbound writes. → `dotfiles-conventions.md` § `CLAUDE.md relocation: Key Conventions platform, update-section and install-function rules`
- The `git-hooks` update section has the same `_UPDATE_SECTION_ORDER` trap; `install_git_hooks_all_repos` returns 0/1/2 (clean/hard fail/partial) and `run_update` and `run_setup_user` must branch on all three. → `dotfiles-conventions.md` § `CLAUDE.md relocation: Key Conventions platform, update-section and install-function rules`
- `install_ubuntu_packages` and `_install_ubuntu_brew_packages` are tri-state (`_install_ubuntu_brew_packages` returns 1 on hard failure and 2 on partial; `install_ubuntu_packages` returns 1 only on an unsupported release and 2 on any failed step, brew rc 1 or 2 included); callers warn on 2 and continue, and `-t developer` then exits 0, so read its output, not its exit code, for package failures. → `dotfiles-conventions.md` § `CLAUDE.md relocation: Key Conventions platform, update-section and install-function rules`
- Install Claude plugins with `claude plugins install -s user <plugin@marketplace>`; keep the scope flag. → `dotfiles-conventions.md` § `CLAUDE.md relocation: Key Conventions platform, update-section and install-function rules`
- Guard the zsh-autosuggestions clone with `[[ -e ${_zsh_autosug}/.git ]]`, never `git rev-parse --git-dir` and never `-d`. → `dotfiles-conventions.md` § `CLAUDE.md relocation: Key Conventions platform, update-section and install-function rules`
- A cheat.sh fetch failure (`_cheat_fetch` rc 1) WARNs; an install failure or missing curl (rc 2) FAILs and is never downgraded by a later WARN. → `dotfiles-conventions.md` § `CLAUDE.md relocation: Key Conventions platform, update-section and install-function rules`
- Treat a diff flipping `auto_approve_bypasses_command_denylist` back to `true` in `.warp/settings.toml` as a reversion to re-pin. → `dotfiles-conventions.md` § `CLAUDE.md relocation: Key Conventions platform, update-section and install-function rules`
- A global/system `core.hooksPath` (even empty) disables every repo's hooks; probe with `git config --includes -z` read via `read -d ''`, and remove an included-file pin with `git config --file <origin> --unset core.hooksPath` (a scope-level `--unset` exits 5). → `dotfiles-conventions.md` § `CLAUDE.md relocation: Key Conventions platform, update-section and install-function rules`
- `tests/setup_env/git_hooks.bats` `setup()` must neutralize `GIT_CONFIG_GLOBAL`/`GIT_CONFIG_SYSTEM`, or the suite fails on any machine with a pin and that developer cannot push. → `dotfiles-conventions.md` § `CLAUDE.md relocation: Key Conventions platform, update-section and install-function rules`
- Legacy hostname vars derive from `PROFILE_LEGACY`; `WORKSTATION`/`CRUNCHER` are still read (`.zprofile`, `7_final.zsh`), so do not remove them; new code uses `HAS_*`. → `dotfiles-conventions.md` § `CLAUDE.md relocation: Key Conventions platform, update-section and install-function rules`
- The git-hooks sweep checks only hook presence and exec bit, so a stale `cp`-installed hook still passes; re-run `make install-hooks` after editing a hook. → `dotfiles-conventions.md` § `CLAUDE.md relocation: Key Conventions platform, update-section and install-function rules`
- Print cheat.sh progress banners outside the section subshell so they never land in `err_cheat.sh`/`detail_cheat.sh` (they feed the `tail -10` diagnostic budget); `.warp/settings.toml` is Warp-owned, so an unexplained diff there is usually a materialized default. → `dotfiles-conventions.md` § `CLAUDE.md relocation: Key Conventions platform, update-section and install-function rules`
- Reference only (NOBLE/RESOLUTE detection, clone dirs, pyenv, pytest, update-section internals, update summary width, cheat.sh internals, Warp symlink, sync modes) → `dotfiles-conventions.md` § `CLAUDE.md relocation: Key Conventions platform, update-section and install-function rules`

- Prepend (never `path+=`) the Homebrew `make` gnubin dir to `PATH`; test both prefixes (`/opt/homebrew/opt/make/libexec/gnubin`, `/usr/local/opt/make/libexec/gnubin`) for existence, not `brew --prefix`. → `dotfiles-conventions.md` § `CLAUDE.md relocation: Homebrew make gnubin PATH prepend rules`

- Which `make` an actor gets depends on whether it sourced `6_path.zsh` (interactive zsh descendants: GNU 4.4.1; cron, launchd, `ssh host '<cmd>'`, editor-spawned hooks: 3.81); harmless to current gates, do not reopen without re-running the comparison. → `dotfiles-conventions.md` § `CLAUDE.md relocation: which make an actor resolves`

- `setup_env.sh` cannot run non-interactively on the Linux workstation (brew `PATH` is interactive-zsh only); prefix `PATH="/home/linuxbrew/.linuxbrew/bin:${PATH}" ./setup_env.sh -t developer`. → `dotfiles-conventions.md` § `CLAUDE.md relocation: Linux workstation brew PATH, cargo tools and tfenv`
- Treat a tool path in an interactive-only rc file as gating that actor only; a hook `PATH` prepend shadows `tests/scripts/pre_push.bats`'s `make` mock, so route any hook `PATH` edit through `_OVERRIDE_GNUBIN_ARM`/`_OVERRIDE_GNUBIN_INTEL` so tests can point it at a nonexistent path. → `dotfiles-conventions.md` § `CLAUDE.md relocation: Linux workstation brew PATH, cargo tools and tfenv`
- The linuxbrew `PATH` prefix causes false `-t doctor` version-drift FAILs; run doctor without it or via `zsh +Z -i -c`. → `dotfiles-conventions.md` § `CLAUDE.md relocation: Linux workstation brew PATH, cargo tools and tfenv`
- `install_cargo_tools` judges pins by whether the binary runs (`--help`), repairs with `--force`, also runs under `-t update --brew-only`, and refuses cargo below `CARGO_MIN_VER` (rc 2); first runs compile for tens of minutes; raise `CARGO_MIN_VER` in `lib/constants.sh` in the same change as a `CARGO_TOOLS` pin bump that needs a newer cargo. → `dotfiles-conventions.md` § `CLAUDE.md relocation: Linux workstation brew PATH, cargo tools and tfenv`
- In `_install_ubuntu_tfenv` the `[[ ! -x "${_root}/bin/tfenv" ]]` guard must return before the symlink loop; the `rm -rf ${_root}` remedy belongs in the WARN, not doctor. → `dotfiles-conventions.md` § `CLAUDE.md relocation: Linux workstation brew PATH, cargo tools and tfenv`
- `_install_ubuntu_tfenv` never replaces a regular file or foreign symlink at `/usr/local/bin/{tfenv,terraform}` and installs `TERRAFORM_VER` only when `~/.tfenv/version` is absent; preserve both. → `dotfiles-conventions.md` § `CLAUDE.md relocation: Linux workstation brew PATH, cargo tools and tfenv`
- `check-versions` does not check tflint/tfsec; its crates.io requests need `-A "dotfiles check-versions (bjackson@pobox.com)"` or they 403. → `dotfiles-conventions.md` § `CLAUDE.md relocation: Linux workstation brew PATH, cargo tools and tfenv`
- Reference only (macOS `/usr/local/bin` symlink limits, `update_rust` resolution, `CARGO_MIN_VER` rationale) → `dotfiles-conventions.md` § `CLAUDE.md relocation: Linux workstation brew PATH, cargo tools and tfenv`

## Dependency Automation

- Inline the shared Renovate preset into `renovate.json`, never `extends` it (ai-config is private, so `extends` throws `config-validation` and Renovate silently abandons the repo); hand-sync `extends`/`schedule`/`labels`/`packageRules` with `ai-config/renovate-presets/default.json`, since nothing detects drift. → `dotfiles-conventions.md` § `CLAUDE.md budget: Dependency Renovate preset inline`

- Treat Renovate as running here (`pinDigests` and auto-merge work in production); do not cite the `mode=silent` finding as a live constraint without re-reading a current Mend job log. → `dotfiles-conventions.md` § `CLAUDE.md budget: Dependency Renovate running`

- Never conclude Renovate is inactive from a zero-PR count alone; first establish what it was permitted to do. → `dotfiles-conventions.md` § `CLAUDE.md budget: Dependency zero-PR count`

- Do not add `pip_requirements` to `renovate.json`'s `enabledManagers`: the five renderings are generated from `uv.lock` and `pyproject.toml` is owned by `pep621`; `tests/setup_env/requirements_ci.bats` pins the absence. → `dotfiles-conventions.md` § `CLAUDE.md budget: Dependency pip_requirements absent`

- Keep Dependabot security auto-PRs OFF and vulnerability alerts ON fleet-wide (decided 2026-08-21); it is a repo-Settings toggle no tracked file captures, so a file's silence is not evidence it is unset; do not re-enable auto-PRs. → `dotfiles-conventions.md` § `CLAUDE.md budget: Dependency Dependabot policy`

- To clear Dependabot's repo-wide `automated-security-fixes`, call `PUT vulnerability-alerts` first, then `DELETE automated-security-fixes`, never the reverse (the DELETE 422s while alerts are off). → `dotfiles-conventions.md` § `CLAUDE.md budget: Dependency automated-security-fixes ordering`

- Do not assume Python packages get automated update PRs here: Dependabot auto-PRs are off and Renovate manages no Python, so alerts fire with nothing proposing a fix. → `dotfiles-conventions.md` § `CLAUDE.md budget: Dependency Python no update path`

## Local-Only State

- Never commit machine-local paths: `~/.aws/`, `~/.tf_creds/`, `~/.azure_creds/`, `~/.gcloud_creds/`, `~/.tsh/`, `~/.ssh/` private keys (only `config` and `teleport.cfg` are tracked), `~/.claude/projects/<path>/` (session history and memory drafts; canonical memory is `ai-config/.claude/memory/<repo>-<topic>.md` and a leftover draft fails ai-config `make test`), and `config/local.sh` (git-ignored; copy from `config/local.sh.example`). → `dotfiles-conventions.md` § `CLAUDE.md budget: Local-only state paths`

The `secret-scan` CI job (`gitleaks`) scans recent commits for credential patterns. If it fires on a legitimate file, add an allowlist entry to `.gitleaks.toml`.

## Profile Model

`config/profiles.sh` is the single hostname→identity table, sourced by both bash
(`lib/detect_env.sh`) and zsh (`config/profiles.zsh`, itself sourced by `.zprofile` and
`.config/.zshrc.d/1_init.zsh`). After `detect_env()` (bash) or `config/profiles.zsh` (zsh)
runs, the following vars are set:

- `detect_env()` (bash) and `config/profiles.zsh` (zsh) set `PROFILE` (`personal_laptop`, `mac_workstation`, `mac_mini`, `linux_workstation`, `wsl2_workstation` or `unknown`) and the `HAS_*` flags (GUI, DEVTOOLS, AWS, K8S, DOCKER, RUST, SNAP, FLATPAK, PRINTING); `HAS_SNAP` and `HAS_FLATPAK` are linux_workstation only; the per-profile matrix is reference. → `dotfiles-conventions.md` § `CLAUDE.md budget: Profile var matrix`

`server` is gone — it belonged to a retired mac mini that no hostname has mapped to since,
and `PROFILE_CAPS[server]` was deleted with it.

**A `-1` suffix on a hostname is that machine's wireless-interface name** — `hostname -s`
returns it whenever the machine is off ethernet — and both spellings resolve to the same `PROFILE`/`HAS_*` set.

- Give `workstation`, `cruncher` and `claude` one key: the criterion is one DHCP/DNS registration, and a `-1` key belongs only to a machine that connects both wired and wireless; `home-1` is a literal name with no separate `home` entry. → `dotfiles-conventions.md` § `CLAUDE.md budget: Profile single-key hostnames`

An unmapped hostname resolves to `PROFILE=unknown` with zero `HAS_*` — that is a silent,
well-formed answer, not an error, which is why `run_doctor` now checks for it explicitly
(see Adding a New Machine).

## Adding a New Machine

Adding a machine takes three edits across two files for a host with a wireless twin, four across three for a wired-only host (steps below). → `dotfiles-conventions.md` § `CLAUDE.md budget: New machine edit counts`

1. Edit `config/profiles.sh`: add **both** the wired and the `-1` wireless hostname to `PROFILE_MAP` with the same profile; a wired-only entry leaves `PROFILE=unknown` and no `HAS_*` on wifi. → `dotfiles-conventions.md` § `CLAUDE.md budget: New machine step 1`

```bash
declare -A PROFILE_MAP=(
  [laptop]="personal_laptop"        [laptop-1]="personal_laptop"
  [my-new-host]="mac_workstation"   [my-new-host-1]="mac_workstation"   # ← new pair
  ...
)
```

2. In the same file, add the same wired/wireless pair to `PROFILE_LEGACY` with the same legacy variable (`LAPTOP`, `STUDIO`, ...); add a new profile to `PROFILE_CAPS` if needed. → `dotfiles-conventions.md` § `CLAUDE.md budget: New machine step 2`

3. Add a case arm for the new hostname(s) to `tests/helpers/legacy_oracle.bash`, hand-typed and never derived from `PROFILE_LEGACY`. → `dotfiles-conventions.md` § `CLAUDE.md budget: New machine step 3`

   Skipping step 2 or step 3 fails the suite, so CI blocks either mistake. → `dotfiles-conventions.md` § `CLAUDE.md budget: New machine step 3 failure modes`

   A wired-only host (`workstation`, `cruncher`, `claude`) needs a fourth edit: its key in the `wired_only` set in `tests/setup_env/profiles.bats`. → `dotfiles-conventions.md` § `CLAUDE.md budget: New machine wired-only fourth edit`

4. Push a feature branch — CI validates → auto-merges to master.

**No other production file needs changing** (`lib/detect_env.sh` and `config/profiles.zsh` derive from `PROFILE_MAP`/`PROFILE_LEGACY`), but tests need `tests/helpers/legacy_oracle.bash` and, for a wired-only host, `wired_only` edited too. → `dotfiles-conventions.md` § `CLAUDE.md budget: New machine no other file`

If a hostname is missing from the table, `run_doctor` fails and names the hostname and
`config/profiles.sh` in its message — that is the check that catches the omission in step 1
rather than letting the machine silently run with no capabilities.

---
