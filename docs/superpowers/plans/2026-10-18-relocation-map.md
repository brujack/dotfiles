# CLAUDE.md Test Seams relocation map

Maps each changed block of the `### Test Seams` subsection of `CLAUDE.md` to the `ai-config/docs/knowledge/dotfiles-test-seams.md` heading holding it byte-for-byte.

```relocation-map
MOVE | - `tests/mocks/pyenv` `install` (`lib/developer.sh:_ensure_p | dotfiles-test-seams.md | CLAUDE.md relocation: pyenv mock install under env -i
MOVE | **`_RUSTUP_INIT_URL` / `_RUSTUP_INIT_SHA256` / `_RUSTUP_INIT | dotfiles-test-seams.md | CLAUDE.md relocation: rustup install seams and digest rule
MOVE | - `_RUSTUP_INIT_SHA256` (`lib/linux_ubuntu.sh:_install_rustu | dotfiles-test-seams.md | CLAUDE.md relocation: rustup install seams and digest rule
MOVE | - `_OVERRIDE_NVIDIA_GPU_PRESENT` (`lib/linux_ubuntu.sh:_nvid | dotfiles-test-seams.md | CLAUDE.md relocation: NVIDIA detection and keyring seams
MOVE | **`_OVERRIDE_DOCKER_DAEMON_JSON` (`_install_ubuntu_nvidia`)  | dotfiles-test-seams.md | CLAUDE.md relocation: docker daemon.json seam and nvidia-ctk mock
MOVE | - `brew_install_cask`/`brew_cask_installed` (`lib/helpers.sh | dotfiles-test-seams.md | CLAUDE.md relocation: cask helper rule
MOVE | - `config/profiles.zsh` and `lib/detect_env.sh` must derive  | dotfiles-test-seams.md | CLAUDE.md relocation: profile table single source and hand-typed oracle
MOVE | **`tests/helpers/legacy_oracle.bash` is that shared oracle,  | dotfiles-test-seams.md | CLAUDE.md relocation: profile table single source and hand-typed oracle
MOVE | - `config/profiles.zsh` must use `export`, never `readonly`  | dotfiles-test-seams.md | CLAUDE.md relocation: profiles export versus readonly
MOVE | - `_OVERRIDE_HOMEBREW_PREFIX_ARM`/`_OVERRIDE_HOMEBREW_PREFIX | dotfiles-test-seams.md | CLAUDE.md relocation: homebrew prefix override seams
MOVE | - `_OVERRIDE_KEYCHAIN_BIN` (`.config/.zshrc.d/5_general.zsh` | dotfiles-test-seams.md | CLAUDE.md relocation: keychain override seam and interactive guard
MOVE | - `_OVERRIDE_CURRENT_LOGIN_SHELL` (`lib/helpers.sh:_current_ | dotfiles-test-seams.md | CLAUDE.md relocation: login shell override seam and chsh guard
MOVE | - `_OVERRIDE_GNUBIN_ARM`/`_OVERRIDE_GNUBIN_INTEL` (`lib/maco | dotfiles-test-seams.md | CLAUDE.md relocation: gnubin arm and intel seams
MOVE | - `_OVERRIDE_GNUBIN_LINUX` (`.config/.zshrc.d/6_path.zsh`, ` | dotfiles-test-seams.md | CLAUDE.md relocation: gnubin linux seam
MOVE | - `_OVERRIDE_DOCKER_BIN` (`.config/.zshrc.d/6_path.zsh`)   - | dotfiles-test-seams.md | CLAUDE.md relocation: docker bin override seam
MOVE | - `GGSHIELD_BIN`/`GGSHIELD_FALLBACK_PATHS` (`scripts/pre-com | dotfiles-test-seams.md | CLAUDE.md relocation: ggshield override seams
MOVE | - `LEDGER_BIN` (`lib/workflows.sh:ledger_write_entry`)   - A | dotfiles-test-seams.md | CLAUDE.md relocation: ledger bin seam
MOVE | - `_OVERRIDE_LIB_TRAP_SCOPE` (`scripts/check-lib-exit-traps. | dotfiles-test-seams.md | CLAUDE.md relocation: lib trap scope seam
MOVE | - `_OVERRIDE_BATS_BIN` (`scripts/run-bash-coverage.sh`)   -  | dotfiles-test-seams.md | CLAUDE.md relocation: bats bin override seam
MOVE | - `_OVERRIDE_RUN_TMPDIR_ROOT` (`lib/workflows.sh:_dotfiles_r | dotfiles-test-seams.md | CLAUDE.md relocation: run tmpdir root seam
MOVE | - `_PROFILES_LOADED` (`lib/detect_env.sh:detect_env`, `lib/h | dotfiles-test-seams.md | CLAUDE.md relocation: profiles loaded sentinel
MOVE | - `_AWS_GPG_BIN`/`_AWS_PKGUTIL_BIN`/`_AWS_KEY_PATH` (`lib/de | dotfiles-test-seams.md | CLAUDE.md relocation: AWS verification seams and key path
MOVE | - `_MS_GPG_BIN`/`_MS_AR_BIN`/`_MS_KEY_PATH` (`lib/linux_ubun | dotfiles-test-seams.md | CLAUDE.md relocation: Microsoft deb verification seams
MOVE | - `_AWS_BIN` (`lib/developer.sh:install_aws_tools`)   - Set  | dotfiles-test-seams.md | CLAUDE.md relocation: aws bin seam
MOVE | - `_EDGE_SOURCES_DIR`/`_EDGE_BOOTSTRAP_KEYRING` (`lib/linux_ | dotfiles-test-seams.md | CLAUDE.md relocation: edge source seams
MOVE | - `_APT_SOURCES_DIR`/`_APT_TRUSTED_DIR`/`_APT_KEYRINGS_DIR`  | dotfiles-test-seams.md | CLAUDE.md relocation: apt directory and hashicorp seams
MOVE | - `_HASHICORP_SOURCE_DIR`/`_HASHICORP_KEY_PATH`/`_APT_SOURCE | dotfiles-test-seams.md | CLAUDE.md relocation: apt directory and hashicorp seams
MOVE | - `_BREW_AZ_BIN` (azure-cli migration in `lib/linux_ubuntu.s | dotfiles-test-seams.md | CLAUDE.md relocation: brew az probe seam
MOVE | - `_build_pinned_keyring <key> <keyring> <fpr>` (`lib/linux_ | dotfiles-test-seams.md | CLAUDE.md relocation: pinned keyring builder
MOVE | - Every cadence seam exists because the delivery arm and the | dotfiles-test-seams.md | CLAUDE.md relocation: cadence seams overview line
MOVE | | variable                   | read by                       | dotfiles-test-seams.md | CLAUDE.md relocation: cadence seam table
MOVE | - `result`/`findings`/`max_age_days` (`scripts/cadence-notif | dotfiles-test-seams.md | CLAUDE.md relocation: cadence heartbeat contract rules
MOVE | - `PATH` (`LaunchAgents/cadence.plist.template`, `lib/launch | dotfiles-test-seams.md | CLAUDE.md relocation: cadence agent PATH rules
MOVE | - `NTFY_URL`/`NTFY_TOPIC` (`scripts/cadence-notify.sh:_rhn_n | dotfiles-test-seams.md | CLAUDE.md relocation: cadence ntfy delivery rules
MOVE | - `_OVERRIDE_PYENV_ROOT` (`lib/helpers.sh:_pyenv_ansible_ven | dotfiles-test-seams.md | CLAUDE.md relocation: pyenv root override seam
MOVE | **`_CARGO_BIN` (`install_cargo_tools`, `lib/developer.sh`) i | dotfiles-test-seams.md | CLAUDE.md relocation: cargo and rustup keg default exports
MOVE | **`_OVERRIDE_RUSTUP_BREW_KEGS` (`_resolve_rustup`, `_rustup_ | dotfiles-test-seams.md | CLAUDE.md relocation: cargo and rustup keg default exports
MOVE | **`_RELEASE_BIN_DIR` (`_install_pinned_release_binary`, `lib | dotfiles-test-seams.md | CLAUDE.md relocation: release bin dir and tfenv link dir seams
MOVE | - `_RELEASE_TMP_ROOT` (`lib/linux_ubuntu.sh:_install_pinned_ | dotfiles-test-seams.md | CLAUDE.md relocation: release tmp root seam
MOVE | - `_DL_STAMP_DIR`/`_DL_TMP_ROOT`/`_DL_BIN_DIR`/`_DL_UNZIP_BI | dotfiles-test-seams.md | CLAUDE.md relocation: fetched binary install seams
MOVE | - Release asset pins (kind, yq, shellcheck; ADR-0046)   - Pi | dotfiles-test-seams.md | CLAUDE.md relocation: release asset sha256 pins
MOVE | - `_GO_INSTALL_ROOT` (`lib/linux_ubuntu.sh:_install_go_from_ | dotfiles-test-seams.md | CLAUDE.md relocation: go install seams
MOVE | - `MOCK_WGET_FAIL_URL`/`MOCK_CURL_FAIL_URL`/`MOCK_APT_FAIL_S | dotfiles-test-seams.md | CLAUDE.md relocation: mock failure knobs and SHIM_DIR shims
MOVE | - `_TFLINT_URL`/`_TFLINT_SHA256`/`_TFSEC_URL`/`_TFSEC_SHA256 | dotfiles-test-seams.md | CLAUDE.md relocation: tflint and tfsec seams
MOVE | - `_TFENV_ROOT`/`_TFENV_REPO_URL` (`lib/linux_ubuntu.sh:_ins | dotfiles-test-seams.md | CLAUDE.md relocation: tfenv root and repo url seams
MOVE | - `_PWSH_BIN`/`_PWSH_PROBE_TIMEOUT` (`lib/linux_ubuntu.sh:_p | dotfiles-test-seams.md | CLAUDE.md relocation: pwsh probe seams
MOVE | - `_NVIDIA_MODULE_VERSION_FILE` (`lib/linux_shared.sh:_nvidi | dotfiles-test-seams.md | CLAUDE.md relocation: nvidia module version and flatpak mock rules
MOVE | - `_DOCTOR_PROBE_TIMEOUT` (`lib/helpers.sh:_doctor_check_dev | dotfiles-test-seams.md | CLAUDE.md relocation: doctor probe timeout seam
MOVE | - `_CRATES_API` (`lib/workflows.sh:_check_one_cargo_version` | dotfiles-test-seams.md | CLAUDE.md relocation: crates api seam
MOVE | - `_SYSCTL_CONF`/`_SYSCTL_BIN`/`_INOTIFY_PROC`/`_SYSTEMD_RUN | dotfiles-test-seams.md | CLAUDE.md relocation: sysctl and kernel keys seams
MOVE | - `_GITHUB_API` (`lib/helpers.sh:_github_api_base`, read by  | dotfiles-test-seams.md | CLAUDE.md relocation: github api seam and http listener
MOVE | - `_OVERRIDE_CLAUDE_SETTINGS`, `_CLAUDE_GUARD_GIT` and `test | dotfiles-test-seams.md | CLAUDE.md relocation: claude settings override seam
MOVE | `_OVERRIDE_CLAUDE_SETTINGS` points every reader above at a f | dotfiles-test-seams.md | CLAUDE.md relocation: claude settings override seam
MOVE | - `_CLAUDE_GUARD_GIT` (`lib/workflows.sh:_claude_settings_gi | dotfiles-test-seams.md | CLAUDE.md relocation: claude guard git seam
MOVE | - `MOCK_CLAUDE_*` (`tests/mocks/claude`)   - Use `MOCK_CLAUD | dotfiles-test-seams.md | CLAUDE.md relocation: tests/mocks/claude modes
MOVE | - Every `claude` call inside a `while read` loop in `setup_c | dotfiles-test-seams.md | CLAUDE.md relocation: claude loop stdin and IFS tab rules
MOVE | **`_OVERRIDE_CLAUDE_PLUGIN_CACHE` (`_claude_plugin_cache_dir | dotfiles-test-seams.md | CLAUDE.md relocation: claude plugin cache override seam
MOVE | - Detect GNU parallel by version string (`parallel --version | dotfiles-bats-test-infrastructure.md | Testing: make test parallelism and lint targets
MOVE | **Run unit tests only:** `make test-unit` (runs `unit.bats`, | dotfiles-bats-test-infrastructure.md | Testing: make test parallelism and lint targets
MOVE | - Keep `config/profiles.sh` in both `SHELL_FILES` (`bash -n` | dotfiles-bats-test-infrastructure.md | Testing: make test parallelism and lint targets
MOVE | - The venv is snapshotted (`pip freeze`) before every sync,  | dotfiles-bats-test-infrastructure.md | Testing: requirements CI renderings and venv rollback
MOVE | - `UV_BIN` (`resolve_uv`, `lib/helpers.sh`) is the operator  | dotfiles-bats-test-infrastructure.md | Testing: requirements CI renderings and venv rollback
MOVE | - `make sync-requirements-ci` renders all five CI requiremen | dotfiles-bats-test-infrastructure.md | Testing: requirements CI renderings and venv rollback
MOVE | | file                           | group         | pins | co | dotfiles-bats-test-infrastructure.md | Testing: requirements CI renderings and venv rollback
MOVE | - Scope CI requirements groups by purpose, not by pruning un | dotfiles-bats-test-infrastructure.md | Testing: requirements CI renderings and venv rollback
MOVE | - The drift gate only verifies a rendering is faithful to it | dotfiles-bats-test-infrastructure.md | Testing: requirements CI renderings and venv rollback
MOVE | - The pre-commit hook is required: run `make lint` (blocks o | dotfiles-bats-test-infrastructure.md | Testing: pre-commit and pre-push hooks
MOVE | - The pre-push hook is permanent — it runs `make test` (lint | dotfiles-bats-test-infrastructure.md | Testing: pre-commit and pre-push hooks
MOVE | - `scripts/pre-push` must resolve repo root with `git rev-pa | dotfiles-bats-test-infrastructure.md | Testing: pre-commit and pre-push hooks
MOVE | - Refuse any push to `refs/heads/master` whose range carries | dotfiles-bats-test-infrastructure.md | Testing: pre-commit and pre-push hooks
MOVE | `.shellcheckrc` at the repo root carries **one** suppression | dotfiles-bats-test-infrastructure.md | Testing: shellcheck conventions and lint scope
MOVE | **This reverses the previous convention, deliberately.** Unt | dotfiles-bats-test-infrastructure.md | Testing: shellcheck conventions and lint scope
MOVE | The blanket was not free. One of the four `SC2181` sites it  | dotfiles-bats-test-infrastructure.md | Testing: shellcheck conventions and lint scope
MOVE | - **Every `# shellcheck disable=` carries a reason on the sa | dotfiles-bats-test-infrastructure.md | Testing: shellcheck conventions and lint scope
MOVE | `make lint`'s scope comes from `scripts/list-shell-files.sh` | dotfiles-bats-test-infrastructure.md | Testing: shellcheck conventions and lint scope
MOVE | **It now covers `tests/mocks/`, which it did not until this  | dotfiles-bats-test-infrastructure.md | Testing: shellcheck conventions and lint scope
MOVE | - `test` job: installs a pinned, checksum-verified shellchec | dotfiles-bats-test-infrastructure.md | Testing: CI workflow jobs
MOVE |     `/opt/homebrew/bin` on a provisioned mac holds more than | dotfiles-bats-test-infrastructure.md | Testing: CI workflow jobs
MOVE | - **`load_setup_env()` does NOT set OS vars, and this bullet | dotfiles-bats-test-infrastructure.md | Testing: Testing Rules detail
MOVE | - Floor: 90%. `make test` and CI both fail on any drop below | dotfiles-bash-coverage.md | Testing: PowerShell coverage scope
MOVE | - Derive the instrumented set from `git ls-files`, never a g | dotfiles-bash-coverage.md | Testing: bash coverage rules
MOVE | - Publish CI's bash coverage figure in the PR body once CI h | dotfiles-bash-coverage.md | Testing: bash coverage rules
MOVE | - `tests/mocks/ln`, `chmod`, `mv`, `cp` and `tee` pass throu | dotfiles-bats-test-infrastructure.md | Testing: mock pattern detail
MOVE | - Recognize any `-[a-zA-Z]+` short-option cluster in `tests/ | dotfiles-bats-test-infrastructure.md | Testing: mock pattern detail
MOVE | - `tests/mocks/curl`'s `-o` write is deferred until **after* | dotfiles-bats-test-infrastructure.md | Testing: mock pattern detail
MOVE | - `Makefile:1`'s `MAKEFLAGS += --no-print-directory` suppres | dotfiles-bats-test-infrastructure.md | Testing: MAKEFLAGS partition detail
MOVE | - `MAKEFLAGS` is an exported env var every spawned `make` in | dotfiles-bats-test-infrastructure.md | Testing: MAKEFLAGS partition detail
MOVE | - `tests/scripts/makefile_lint_scope.bats` enforces the part | dotfiles-bats-test-infrastructure.md | Testing: MAKEFLAGS partition detail
MOVE | - The partition scanner sees only the invoking line, so it i | dotfiles-bats-test-infrastructure.md | Testing: MAKEFLAGS partition detail
MOVE | - Machine roles are now driven by the **profile/capability m | dotfiles-conventions.md | CLAUDE.md relocation: Key Conventions platform, update-section and install-function rules
MOVE | - The Homebrew `make` gnubin directory must be prepended to  | dotfiles-conventions.md | CLAUDE.md relocation: Homebrew make gnubin PATH prepend rules
MOVE | - Which `make` an actor resolves depends on whether the proc | dotfiles-conventions.md | CLAUDE.md relocation: which make an actor resolves
MOVE | - `setup_env.sh` gates every workflow on `env which brew`, a | dotfiles-conventions.md | CLAUDE.md relocation: Linux workstation brew PATH, cargo tools and tfenv
MOVE | - `setup_user` — Configs, shells, directory structure, symli | dotfiles-conventions.md | CLAUDE.md relocation: setup_env.sh workflow catalog
MOVE | - `--dry-run` — guarantees **no outbound write**: no `git pu | dotfiles-conventions.md | CLAUDE.md relocation: --dry-run option semantics
MOVE | - **`env which` vs `command -v`:** `setup_env.sh` uses `whic | dotfiles-conventions.md | CLAUDE.md relocation: shell conventions (env which, prereq tests, sudo dpkg, apt conffile, sourcing guard)
MOVE | **A `# [HAS_*]` tag selects drift expectations only — it doe | dotfiles-conventions.md | CLAUDE.md relocation: Brewfile HAS_ tag selects drift only
MOVE | Two consequences worth holding: tagging an entry does not ke | dotfiles-conventions.md | CLAUDE.md relocation: Brewfile HAS_ tag consequences
MOVE | **Formula/cask dedup rule:** never add both a formula and a  | dotfiles-conventions.md | CLAUDE.md relocation: Brewfile formula/cask dedup and tap trust
MOVE | - `~/.claude/` — `settings.json`, `CLAUDE.md`, `mcp.json.tem | dotfiles-conventions.md | CLAUDE.md relocation: Windows AI config link targets
MOVE | Ruby version managers: **rbenv on Linux** (`lib/linux_ubuntu | dotfiles-conventions.md | CLAUDE.md relocation: Ruby version manager split
MOVE | ``` dotfiles/ ├── setup_env.sh       # Main entry — sources  | dotfiles-conventions.md | CLAUDE.md budget: Layout directory tree
MOVE | - **Phase 1 (10%) — Architect.** `brainstorming` → `writing- | dotfiles-conventions.md | CLAUDE.md budget: 10-80-10 phase list
MOVE | - **Repo root** — each dotfile symlinked individually into ` | dotfiles-conventions.md | CLAUDE.md budget: Symlink repo-root and .claude rules
MOVE |   **The live `~/.claude/mcp.json` is ALSO a symlink, and tem | dotfiles-conventions.md | CLAUDE.md budget: Symlink mcp.json is a symlink
MOVE |   **`projects/` IS symlinked, wholesale, and this line said  | dotfiles-conventions.md | CLAUDE.md budget: Symlink projects is linked wholesale
MOVE |   **The consequence is not local and it has bitten three ses | dotfiles-conventions.md | CLAUDE.md budget: Symlink projects is linked wholesale
MOVE | `.cursor/plugins/` and `.cursor/skills-cursor/` are symlinke | dotfiles-conventions.md | CLAUDE.md budget: Cursor Claude Code parity
MOVE | - Inline the shared Renovate preset into `renovate.json`, do | dotfiles-conventions.md | CLAUDE.md budget: Dependency Renovate preset inline
MOVE | - Treat Renovate as confirmed running here, not merely confi | dotfiles-conventions.md | CLAUDE.md budget: Dependency Renovate running
MOVE | - Never conclude Renovate is inactive from a zero-PR count a | dotfiles-conventions.md | CLAUDE.md budget: Dependency zero-PR count
MOVE | - Do not add `pip_requirements` to `renovate.json`'s `enable | dotfiles-conventions.md | CLAUDE.md budget: Dependency pip_requirements absent
MOVE | - Keep Dependabot security auto-PRs OFF, vulnerability alert | dotfiles-conventions.md | CLAUDE.md budget: Dependency Dependabot policy
MOVE | - `automated-security-fixes` is repo-wide — there is no per- | dotfiles-conventions.md | CLAUDE.md budget: Dependency automated-security-fixes ordering
MOVE | - Do not assume Python packages get automated update PRs her | dotfiles-conventions.md | CLAUDE.md budget: Dependency Python no update path
MOVE | - `~/.aws/` — AWS credentials and config - `~/.tf_creds/` —  | dotfiles-conventions.md | CLAUDE.md budget: Local-only state paths
MOVE | | Var            | Values                                    | dotfiles-conventions.md | CLAUDE.md budget: Profile var matrix
MOVE | `workstation`, `cruncher` and `claude` take a single key bec | dotfiles-conventions.md | CLAUDE.md budget: Profile single-key hostnames
MOVE | Measured directly against `origin/master` (this branch's mer | dotfiles-conventions.md | CLAUDE.md budget: New machine edit counts
MOVE | 1. Edit `config/profiles.sh` — add **both** the wired and th | dotfiles-conventions.md | CLAUDE.md budget: New machine step 1
MOVE | 2. In the same file, add the identical wired/wireless pair t | dotfiles-conventions.md | CLAUDE.md budget: New machine step 2
MOVE | 3. Add a case arm to `tests/helpers/legacy_oracle.bash` for  | dotfiles-conventions.md | CLAUDE.md budget: New machine step 3
MOVE |    Measured directly: skipping either step **fails the suite | dotfiles-conventions.md | CLAUDE.md budget: New machine step 3 failure modes
MOVE |    **A wired-only host (no `-1` twin, like `workstation`, `c | dotfiles-conventions.md | CLAUDE.md budget: New machine wired-only fourth edit
MOVE | **No other file needs changing** — true for production, sinc | dotfiles-conventions.md | CLAUDE.md budget: New machine no other file
```
