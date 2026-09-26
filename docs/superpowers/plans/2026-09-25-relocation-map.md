# CLAUDE.md relocation map

Relocation map for [docs/superpowers/plans/2026-09-25-claude-md-relocation.md](2026-09-25-claude-md-relocation.md) Task 2, against `docs/superpowers/specs/2026-09-25-claude-md-relocation-design.md`.

```relocation-map
SECTION | ### Test Seams
SECTION | ## Key Conventions
SECTION | ## Testing
SECTION | #### Bash
SECTION | ## Dependency Automation
SECTION | ### Mock Pattern
SECTION | ### MAKEFLAGS and Stdout Partition

INLINE | **`_RUSTUP_INIT_URL` / `_RUSTUP_INIT_SHA256` / `_RUSTUP_INIT
INLINE | **`_OVERRIDE_DOCKER_DAEMON_JSON` (`_install_ubuntu_nvidia`) 
INLINE | **`tests/helpers/legacy_oracle.bash` is that shared oracle, 
INLINE | | variable | read by | why it exists | | -------------------------- | ----------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | | `_RHN_DETECTOR` | tests
INLINE | **`_CARGO_BIN` (`install_cargo_tools`, `lib/developer.sh`) i
INLINE | **`_RELEASE_BIN_DIR` (`_install_pinned_release_binary`, `lib
INLINE | `_OVERRIDE_CLAUDE_SETTINGS` points every reader above at a f
INLINE | **`_OVERRIDE_CLAUDE_PLUGIN_CACHE` (`_claude_plugin_cache_dir
INLINE | - Machine roles are now driven by the **profile/capability m
INLINE | - All eight legacy hostname vars (`LAPTOP`, `STUDIO`, `RECEP
INLINE | - Ubuntu version detection uses `lsb_release -rs` → `NOBLE` 
INLINE | - Credential directories (`.aws`, `.tf_creds`, `.tsh`) are c
INLINE | - Git repos are cloned to `~/git-repos/personal/` and `~/git
INLINE | - Python environments managed via **pyenv** + **pyenv-virtua
INLINE | - **Ansible venv packages:** declared once in `pyproject.tom
INLINE | - **ruff is venv-managed** (not brew); run `brew uninstall r
INLINE | - **Test runner:** `pytest` — runs `unittest.TestCase` tests
INLINE | - Application installs are kept in alphabetical order
INLINE | - For shell syntax-only fixes, validate with `bash -n <file>
INLINE | - **`scripts/sync_git_repos.sh`** replaces the old rsync-onl
INLINE | Uses **BATS** (Bash Automated Testing System), installed nat
INLINE | `install_bats()` in `lib/helpers.sh` is a platform dispatche
INLINE | - macOS: `install_bats_macos()` in `lib/macos.sh` — `brew in
INLINE | - Ubuntu: `install_bats_linux()` in `lib/linux_shared.sh` — 
INLINE | **Run tests:** `make test` (runs lint, the lock and requirem
INLINE | **Run unit tests only:** `make test-unit` (runs `unit.bats`,
INLINE | **Install hooks:** `make install-hooks` (installs pre-commit
INLINE | | file | group | pins | consumers | | ----------------------

WAIVE | The suite's positive control is the mismatch case, which asserts the spy binary **never ran**, not merely that the function returned 1. | narrative: describes what the test's own positive control observes, not a directive
WAIVE | `brew_formula_installed` greps `brew list --formula` in _both_ branches, so an installed **cask** never matches there and the caller would reinstall it on every setup run — an idempotency break, which `code-standards.md` treats as a bug rather than a tradeoff. | narrative: describes a bug mechanism (an idempotency break already named as such), not a directive
WAIVE | Mutation-confirmed: reading the seam under a typo'd name leaves the negative test green and fails only the positive one. | narrative: describes what a mutation-confirmation run showed, not a directive
WAIVE | The seam exists because the only other way to reach either branch is to read — or change — the developer's real account. | narrative: explains why the seam is needed (rationale), not itself a rule
WAIVE | The three pre-existing tests encoded all of it: one asserted only that `chsh` was _called_, never that it succeeded, and the error-path test asserted `status -eq 0`, pinning the swallow. | narrative: describes what pre-existing tests happened to assert, historical
WAIVE | **Two code paths, and the tests only exercise one.** | narrative: describes test coverage as observed (one of two paths exercised)
WAIVE | Re-install seeds a missing heartbeat and never clobbers a real one, so `setup_user` is the migration path for agents provisioned before the field existed. | narrative: describes the installer's guarantee as a property, not an instruction to the reader
WAIVE | The `rm -rf` in the WARN is the only thing that does. | narrative: describes what the WARN's rm -rf accomplishes, not a directive
WAIVE | This conserves GitHub Actions minutes — CI runs only on PRs. | narrative: states a consequence (GitHub Actions minutes), not a directive
WAIVE | The fix needs a branch and a PR, or `--no-verify`. | narrative: --no-verify is a flag name; \bverify\b matches inside it incidentally
WAIVE | This bullet used to read "nothing under test sources them, so instrumenting them would add only zeros to the denominator." | narrative: quotes a retracted claim from an earlier draft of this same bullet
WAIVE | The exclusion was asserted, never measured. | narrative: describes how an exclusion was arrived at (asserted vs measured), historical
WAIVE | A union-added line raises numerator and denominator together, so a count and a ratio from different runs describe a pair that never existed. | narrative: explains why a cross-run ratio comparison is meaningless, not a directive

MOVE | See `~/git-repos/personal/ai-config/docs/knowledge/dotfiles-bats-test-infrastructure.md` for the full override env  | dotfiles-test-seams.md | Test seam idiom and override pattern
MOVE | Pattern: `local _file="${_OVERRIDE_VAR:-$(dirname "${BASH_SO | dotfiles-test-seams.md | Test seam idiom and override pattern
MOVE | **`_RUSTUP_INIT_SHA256` is exposed rather than mocking `sha2 | dotfiles-test-seams.md | Rustup signature verification seams (_RUSTUP_INIT_URL / _RUSTUP_INIT_SHA256 / _RUSTUP_INIT_BIN / _OVERRIDE_CARGO_BIN_DIR)
MOVE | Note `tests/mocks/curl` does not fetch: it writes `MOCK_CURL | dotfiles-test-seams.md | Rustup signature verification seams (_RUSTUP_INIT_URL / _RUSTUP_INIT_SHA256 / _RUSTUP_INIT_BIN / _OVERRIDE_CARGO_BIN_DIR)
MOVE | **`_OVERRIDE_NVIDIA_GPU_PRESENT` / `_OVERRIDE_NVIDIA_KEYRING | dotfiles-test-seams.md | NVIDIA GPU detection seams (_OVERRIDE_NVIDIA_GPU_PRESENT / _OVERRIDE_NVIDIA_KEYRING / _OVERRIDE_NVIDIA_LIST)
MOVE | **`brew_install_cask` / `brew_cask_installed` (`lib/helpers. | dotfiles-test-seams.md | brew_install_cask / brew_cask_installed seam
MOVE | **`config/profiles.zsh` is the single zsh-side derivation of | dotfiles-test-seams.md | config/profiles.zsh and the legacy identity oracle
MOVE | `tests/helpers/legacy_oracle.bash` carries a `#!/usr/bin/env | dotfiles-test-seams.md | config/profiles.zsh and the legacy identity oracle
MOVE | **`config/profiles.zsh` uses `export`; `lib/detect_env.sh` u | dotfiles-test-seams.md | config/profiles.zsh export vs lib/detect_env.sh readonly
MOVE | **`_OVERRIDE_HOMEBREW_PREFIX_ARM` / `_OVERRIDE_HOMEBREW_PREF | dotfiles-test-seams.md | _OVERRIDE_HOMEBREW_PREFIX_ARM / _OVERRIDE_HOMEBREW_PREFIX_INTEL seam
MOVE | **`_OVERRIDE_KEYCHAIN_BIN` (`.config/.zshrc.d/5_general.zsh` | dotfiles-test-seams.md | _OVERRIDE_KEYCHAIN_BIN seam and the interactive guard
MOVE | **The expansion is quoted — `` `"${_keychain}" --eval …` ``  | dotfiles-test-seams.md | _OVERRIDE_KEYCHAIN_BIN seam and the interactive guard
MOVE | It is quoted anyway because that safety is a default, not a  | dotfiles-test-seams.md | _OVERRIDE_KEYCHAIN_BIN seam and the interactive guard
MOVE | The `[[ ${VAR} ]]` tests throughout this file are deliberate | dotfiles-test-seams.md | _OVERRIDE_KEYCHAIN_BIN seam and the interactive guard
MOVE | The block it guards is wrapped in `[[ -o interactive ]]`, an | dotfiles-test-seams.md | _OVERRIDE_KEYCHAIN_BIN seam and the interactive guard
MOVE | The two tests covering it are a **pair**, and neither works  | dotfiles-test-seams.md | _OVERRIDE_KEYCHAIN_BIN seam and the interactive guard
MOVE | **`_OVERRIDE_CURRENT_LOGIN_SHELL` (`lib/helpers.sh`'s `_curr | dotfiles-test-seams.md | _OVERRIDE_CURRENT_LOGIN_SHELL seam and the chsh guard
MOVE | **`chsh` is why the rest of that function changed, and the f | dotfiles-test-seams.md | _OVERRIDE_CURRENT_LOGIN_SHELL seam and the chsh guard
MOVE | The old code checked neither rc and then logged `Changed def | dotfiles-test-seams.md | _OVERRIDE_CURRENT_LOGIN_SHELL seam and the chsh guard
MOVE | **`_OVERRIDE_GNUBIN_ARM` / `_OVERRIDE_GNUBIN_INTEL` are read | dotfiles-test-seams.md | _OVERRIDE_GNUBIN_ARM / _OVERRIDE_GNUBIN_INTEL seam
MOVE | The seam is not optional in tests: the real ARM gnubin dir e | dotfiles-test-seams.md | _OVERRIDE_GNUBIN_ARM / _OVERRIDE_GNUBIN_INTEL seam
MOVE | **`_OVERRIDE_GNUBIN_LINUX` is the same pattern one platform  | dotfiles-test-seams.md | _OVERRIDE_GNUBIN_LINUX seam
MOVE | **`_OVERRIDE_DOCKER_BIN` (`.config/.zshrc.d/6_path.zsh`) sel | dotfiles-test-seams.md | _OVERRIDE_DOCKER_BIN seam
MOVE | The entry used to live in `.zprofile`, written there by Dock | dotfiles-test-seams.md | _OVERRIDE_DOCKER_BIN seam
MOVE | **`GGSHIELD_BIN` / `GGSHIELD_FALLBACK_PATHS` (`scripts/pre-c | dotfiles-test-seams.md | GGSHIELD_BIN / GGSHIELD_FALLBACK_PATHS seams
MOVE | Tests must drive absence through these seams and never by ed | dotfiles-test-seams.md | GGSHIELD_BIN / GGSHIELD_FALLBACK_PATHS seams
MOVE | **`LEDGER_BIN` (`lib/workflows.sh`'s `ledger_write_entry`) i | dotfiles-test-seams.md | LEDGER_BIN seam
MOVE | **`_OVERRIDE_LIB_TRAP_SCOPE` (`scripts/check-lib-exit-traps. | dotfiles-test-seams.md | _OVERRIDE_LIB_TRAP_SCOPE seam
MOVE | The seam grants nothing: it redirects a read-only scan to a  | dotfiles-test-seams.md | _OVERRIDE_LIB_TRAP_SCOPE seam
MOVE | **Two code paths, and the tests only exercise one.** Under t | dotfiles-test-seams.md | _OVERRIDE_LIB_TRAP_SCOPE seam
MOVE | **`_OVERRIDE_BATS_BIN` (`scripts/run-bash-coverage.sh`) exis | dotfiles-test-seams.md | _OVERRIDE_BATS_BIN seam
MOVE | Both halves of a seam must land in the same commit. This one | dotfiles-test-seams.md | _OVERRIDE_BATS_BIN seam
MOVE | **`_OVERRIDE_RUN_TMPDIR_ROOT` is read at exactly one site, ` | dotfiles-test-seams.md | _OVERRIDE_RUN_TMPDIR_ROOT seam
MOVE | **`_PROFILES_LOADED` (`lib/detect_env.sh` and `lib/helpers.s | dotfiles-test-seams.md | _PROFILES_LOADED sentinel
MOVE | **`_AWS_GPG_BIN` / `_AWS_PKGUTIL_BIN` / `_AWS_KEY_PATH` (`li | dotfiles-test-seams.md | _AWS_GPG_BIN / _AWS_PKGUTIL_BIN / _AWS_KEY_PATH seams
MOVE | **`_AWS_KEY_PATH`'s default now comes from `DOTFILES_REPO_RO | dotfiles-test-seams.md | _AWS_GPG_BIN / _AWS_PKGUTIL_BIN / _AWS_KEY_PATH seams
MOVE | **Sixty-seven `developer.bats` tests covered this code and n | dotfiles-test-seams.md | _AWS_GPG_BIN / _AWS_PKGUTIL_BIN / _AWS_KEY_PATH seams
MOVE | **`lib/helpers.sh`'s `_doctor_check_aws_key_expiry` carried  | dotfiles-test-seams.md | _AWS_GPG_BIN / _AWS_PKGUTIL_BIN / _AWS_KEY_PATH seams
MOVE | **`_AWS_BIN` (`lib/developer.sh`'s `install_aws_tools`) is l | dotfiles-test-seams.md | _AWS_BIN seam
MOVE | **Cadence seams (`scripts/cadence-notify.sh`, `lib/launch_ag | dotfiles-test-seams.md | Cadence seams overview (scripts/cadence-notify.sh, lib/launch_agents.sh)
MOVE | **The heartbeat's contract** — `~/.local/share/dotfiles/cade | dotfiles-test-seams.md | Cadence heartbeat contract
MOVE | Three properties are load-bearing and none is obvious from t | dotfiles-test-seams.md | Cadence heartbeat contract
MOVE | - **`max_age_days` is written, not mirrored.** A reader hold | dotfiles-test-seams.md | Cadence heartbeat contract
MOVE | - **`pending` is a state, not a grace period.** The installe | dotfiles-test-seams.md | Cadence heartbeat contract
MOVE | - **`held` is a finding, not a fault.** `doctor` renders the | dotfiles-test-seams.md | Cadence heartbeat contract
MOVE | - **`findings` is a count of stdout lines, and it is only as | dotfiles-test-seams.md | Cadence heartbeat contract
MOVE | **Every value is closed-form on purpose.** The file is hand- | dotfiles-test-seams.md | Cadence heartbeat contract
MOVE | **The plist's `PATH` is the agent's whole world, and every d | dotfiles-test-seams.md | Cadence agent PATH and plist rendering
MOVE | `ledger` lives in that first entry, which the plist did not  | dotfiles-test-seams.md | Cadence agent PATH and plist rendering
MOVE | **When wiring a new detector, resolve its dependencies under | dotfiles-test-seams.md | Cadence agent PATH and plist rendering
MOVE | `tests/setup_env/launch_agents.bats` guards the property rat | dotfiles-test-seams.md | Cadence agent PATH and plist rendering
MOVE | **A plist change does not reach a running agent — the templa | dotfiles-test-seams.md | Cadence agent PATH and plist rendering
MOVE | **ntfy needs a topic and credentials, and neither is optiona | dotfiles-test-seams.md | Cadence ntfy delivery and heartbeat rationale
MOVE | **The heartbeat is a second channel, deliberately.** The age | dotfiles-test-seams.md | Cadence ntfy delivery and heartbeat rationale
MOVE | **`install_ledger_drift_agent` makes that deferral true rath | dotfiles-test-seams.md | Cadence ntfy delivery and heartbeat rationale
MOVE | **Pyenv-rehash and cargo-tools seams (`lib/helpers.sh`, `lib | dotfiles-test-seams.md | Pyenv-rehash and cargo-tools seams overview
MOVE | **`_OVERRIDE_PYENV_ROOT` is read by `_pyenv_ansible_venv_bin | dotfiles-test-seams.md | _OVERRIDE_PYENV_ROOT seam
MOVE | **`_RELEASE_TMP_ROOT` (`_install_pinned_release_binary`) exi | dotfiles-test-seams.md | _RELEASE_TMP_ROOT seam
MOVE | **`_TFLINT_URL`/`_TFLINT_SHA256`/`_TFSEC_URL`/`_TFSEC_SHA256 | dotfiles-test-seams.md | _TFLINT_URL / _TFLINT_SHA256 / _TFSEC_URL / _TFSEC_SHA256 seams
MOVE | **`_TFENV_ROOT` (`_install_ubuntu_tfenv`) isolates the clone | dotfiles-test-seams.md | _TFENV_ROOT / _TFENV_REPO_URL seams
MOVE | **`_PWSH_BIN` and `_PWSH_PROBE_TIMEOUT` are both read by `_p | dotfiles-test-seams.md | _PWSH_BIN / _PWSH_PROBE_TIMEOUT seams
MOVE | **The `timeout`-absent fallback inside that helper needs its | dotfiles-test-seams.md | _PWSH_BIN / _PWSH_PROBE_TIMEOUT seams
MOVE | **`_DOCTOR_PROBE_TIMEOUT` (`_doctor_check_dev_tools`, `lib/h | dotfiles-test-seams.md | _DOCTOR_PROBE_TIMEOUT seam
MOVE | **`_CRATES_API` (`_check_one_cargo_version`, `lib/workflows. | dotfiles-test-seams.md | _CRATES_API seam
MOVE | **Claude plugin provisioning seams (`_OVERRIDE_CLAUDE_SETTIN | dotfiles-test-seams.md | Claude plugin provisioning seams overview
MOVE | `_CLAUDE_GUARD_GIT` (default `git`) is what `_claude_setting | dotfiles-test-seams.md | _CLAUDE_GUARD_GIT seam
MOVE | `tests/mocks/claude` gained five new modes for this: `MOCK_C | dotfiles-test-seams.md | tests/mocks/claude seam modes
MOVE | Two non-obvious facts a future reader needs. **Every `claude | dotfiles-test-seams.md | Claude plugin provisioning: stdin redirect and IFS tab collapse
MOVE | - **GPU provisioning is the one deliberate exception to that | dotfiles-conventions.md | GPU provisioning as the HAS_* exception (not a capability)
MOVE | - **Installing the NVIDIA driver does not bind it** — nouvea | dotfiles-conventions.md | GPU provisioning as the HAS_* exception (not a capability)
MOVE | - **Installing `nvidia-container-toolkit` does not register  | dotfiles-conventions.md | GPU provisioning as the HAS_* exception (not a capability)
MOVE | - After any change to `.zshrc` or `.zshrc.d/` files, run `zs | dotfiles-conventions.md | zsh -i -c 'exit' after .zshrc changes, and the worktree caveat
MOVE | - **`$0` is not the file's path in a zsh startup file, and ` | dotfiles-conventions.md | $0 resolution in zsh startup files (${0:A:h} pitfall)
MOVE | - **`_UPDATE_SECTION_ORDER` coupling:** `lib/update_summary. | dotfiles-conventions.md | _UPDATE_SECTION_ORDER coupling
MOVE | - **`git-hooks` section coupling:** same `_UPDATE_SECTION_OR | dotfiles-conventions.md | git-hooks section coupling and _git_hooks_target_dir
MOVE | - **`_install_ubuntu_brew_packages` returns the same tri-sta | dotfiles-conventions.md | _install_ubuntu_brew_packages tri-state return
MOVE | - **`claude plugins install` takes `-s user` and a `plugin@m | dotfiles-conventions.md | claude plugins install -s user scope flag
MOVE | - **`zsh-autosuggestions` is a reported section** (`lib/work | dotfiles-conventions.md | zsh-autosuggestions reported update section
MOVE | - **The summary's name column widened from `%-16s` to `%-20s | dotfiles-conventions.md | Update summary name column width
MOVE | - **The cheat.sh section now covers both artifacts and both  | dotfiles-conventions.md | cheat.sh section: both artifacts, both failures FAIL the run
MOVE | - **`.warp/settings.toml` is Warp-owned and symlinked live** | dotfiles-conventions.md | .warp/settings.toml Warp-owned symlink and auto_approve_bypasses_command_denylist
MOVE | - **A global/system `core.hooksPath` pin redirects every rep | dotfiles-conventions.md | Global/system core.hooksPath pin: detection and remedy
MOVE | - **The pin probe must read `--includes`, and the remedy mus | dotfiles-conventions.md | Global/system core.hooksPath pin: detection and remedy
MOVE | - **Homebrew `make` gnubin prepend:** `.config/.zshrc.d/6_pa | dotfiles-conventions.md | Homebrew make gnubin prepend (prepend, not append)
MOVE | - **Which `make` an actor resolves — measured, and it does n | dotfiles-conventions.md | Which make an actor resolves (gnubin/actor table)
MOVE | | actor | `PATH` source | resolves | version | | ----------- | dotfiles-conventions.md | Which make an actor resolves (gnubin/actor table)
MOVE | **The split is real and its consequence to this repo is nil. | dotfiles-conventions.md | Which make an actor resolves (gnubin/actor table)
MOVE | Two traps recorded from those retirements, because both cost | dotfiles-conventions.md | Which make an actor resolves (gnubin/actor table)
MOVE | - **`/usr/local/bin` reaches none of the non-interactive act | dotfiles-conventions.md | setup_env.sh cannot run non-interactively on the Linux workstation (brew PATH)
MOVE | - **`setup_env.sh` cannot run non-interactively on the Linux | dotfiles-conventions.md | setup_env.sh cannot run non-interactively on the Linux workstation (brew PATH)
MOVE | A non-interactive invocation dies in seconds with `[ERROR] H | dotfiles-conventions.md | setup_env.sh cannot run non-interactively on the Linux workstation (brew PATH)
MOVE | The macOS bullet above and this one are the same defect at t | dotfiles-conventions.md | setup_env.sh cannot run non-interactively on the Linux workstation (brew PATH)
INLINE | - **`install_cargo_tools` (`lib/developer.sh`) judges each `
MOVE | - **terraform on Linux now comes through tfenv** (`_install_ | dotfiles-conventions.md | terraform on Linux via tfenv, and the checkout guard
MOVE | - **A `~/.tfenv` that exists but is not a usable checkout is | dotfiles-conventions.md | terraform on Linux via tfenv, and the checkout guard
MOVE | - **`tflint` and `tfsec` staleness is invisible to `check-ve | dotfiles-conventions.md | tflint/tfsec staleness gap; CARGO_TOOLS staleness via crates.io
MOVE | `make test` runs bats at `--jobs $(JOBS)` when **GNU** paral | dotfiles-testing-toolchain.md | make test parallel jobs: detection, JOBS validation, and the CI file list
MOVE | - **Detection asks what the binary is, not that one exists.* | dotfiles-testing-toolchain.md | make test parallel jobs: detection, JOBS validation, and the CI file list
MOVE | - **`JOBS` defaults to 24 and is validated in pure make at p | dotfiles-testing-toolchain.md | make test parallel jobs: detection, JOBS validation, and the CI file list
MOVE | - **The file list is a filesystem walk, not `git ls-files`.* | dotfiles-testing-toolchain.md | make test parallel jobs: detection, JOBS validation, and the CI file list
MOVE | `BATS_SERIAL_FILES` carves a file out of the parallel pool t | dotfiles-testing-toolchain.md | make test parallel jobs: detection, JOBS validation, and the CI file list
MOVE | **CI takes the parallel path too, and not because the workfl | dotfiles-testing-toolchain.md | make test parallel jobs: detection, JOBS validation, and the CI file list
MOVE | `config/profiles.sh` is a bash file — it stays in `SHELL_FIL | dotfiles-testing-toolchain.md | config/profiles.sh dual lint scope; scripts/phrase_check.py manifest checker
MOVE | **Its suite runs in `make test`; the tool does not.** `test- | dotfiles-testing-toolchain.md | config/profiles.sh dual lint scope; scripts/phrase_check.py manifest checker
MOVE | **The venv is snapshotted before every sync, and that file i | dotfiles-testing-toolchain.md | Ansible venv snapshot before every sync (uv sync prune/downgrade, rollback)
INLINE | `--no-deps` is required — the state being restored is one th
MOVE | **Environment overrides added by the uv work.** All three ex | dotfiles-testing-toolchain.md | Environment overrides added by the uv work (UV_BIN, UV_FALLBACK_PATHS, REQUIREMENTS_CI_TARGET)
MOVE | | variable | read by | why it exists | | ------------------------ | --------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | | `UV_BIN` | `resolve_uv` (`lib/helpers.sh`) | operato | dotfiles-testing-toolchain.md | Environment overrides added by the uv work (UV_BIN, UV_FALLBACK_PATHS, REQUIREMENTS_CI_TARGET)
MOVE | **Sync CI requirements:** `make sync-requirements-ci` (rende | dotfiles-testing-toolchain.md | Sync/check CI requirements commands and the five renderings
MOVE | **There are five renderings, deliberately separate files.** | dotfiles-testing-toolchain.md | Sync/check CI requirements commands and the five renderings
MOVE | Do not harmonise them — `tests/setup_env/requirements_ci.bat | dotfiles-testing-toolchain.md | Requirements CI groups: do not harmonise (distinctness tests)
MOVE | **The CI groups are not "test-lint minus the unused bits", a | dotfiles-testing-toolchain.md | Requirements CI groups: purpose over CI/local, and the erosion guard
MOVE | **The framing that matters, because it was wrong for most of | dotfiles-testing-toolchain.md | Requirements CI groups: purpose over CI/local, and the erosion guard
MOVE | **`ci-test`'s boundary is stated in `pyproject.toml` and gua | dotfiles-testing-toolchain.md | Requirements CI groups: purpose over CI/local, and the erosion guard
MOVE | **`bandit`, `radon` and `vulture` stay in `test-lint` and ar | dotfiles-testing-toolchain.md | Requirements CI groups: purpose over CI/local, and the erosion guard
MOVE | **Provenance does not go in these headers, and that is load- | dotfiles-testing-toolchain.md | Requirements CI groups: purpose over CI/local, and the erosion guard
MOVE | **The drift gate cannot see a wrong-group declaration.** It  | dotfiles-testing-toolchain.md | Requirements CI groups: drift-gate blindness and uv export determinism
MOVE | `requirements-ci.txt` is a **rendering, not a declaration**  | dotfiles-testing-toolchain.md | Requirements CI groups: drift-gate blindness and uv export determinism
MOVE | Two properties are load-bearing and were measured rather tha | dotfiles-testing-toolchain.md | Requirements CI groups: drift-gate blindness and uv export determinism
MOVE | The pre-commit hook is **required**. It runs on every `git c | dotfiles-testing-toolchain.md | Pre-commit hook: make lint and the ggshield actor-boundary resolution
MOVE | 1. `make lint` — blocks the commit on any syntax or shellche | dotfiles-testing-toolchain.md | Pre-commit hook: make lint and the ggshield actor-boundary resolution
MOVE | 2. `ggshield secret scan pre-commit` — scans staged changes  | dotfiles-testing-toolchain.md | Pre-commit hook: make lint and the ggshield actor-boundary resolution
MOVE | The pre-push hook is **permanent**. It runs `make test` (lin | dotfiles-testing-toolchain.md | Pre-push hook: fail-closed inert-path set
MOVE | **Worktree compatibility requirement:** `scripts/pre-push` m | dotfiles-testing-toolchain.md | Pre-push hook: worktree root resolution and git env strip
MOVE | **Git env strip requirement:** `scripts/pre-push` must `unse | dotfiles-testing-toolchain.md | Pre-push hook: worktree root resolution and git env strip
MOVE | **Direct-to-master guard:** `scripts/pre-push` refuses a pus | dotfiles-testing-toolchain.md | Pre-push hook: direct-to-master guard (executable-class paths)
MOVE | The scope is **deliberately narrower** than `sdlc-branch-gua | dotfiles-testing-toolchain.md | Pre-push hook: direct-to-master guard (executable-class paths)
MOVE | Two implementation constraints, both load-bearing. The verdi | dotfiles-testing-toolchain.md | Pre-push hook: direct-to-master guard (executable-class paths)
MOVE | **The guard evaluates the push RANGE, not the tip commit, an | dotfiles-testing-toolchain.md | Pre-push hook: direct-to-master guard (executable-class paths)
MOVE | **`scripts/pre-push` is itself executable-class, so a defect | dotfiles-testing-toolchain.md | Pre-push hook: direct-to-master guard (executable-class paths)
MOVE | **Twelve tests in `tests/scripts/pre_push.bats` push to a fe | dotfiles-testing-toolchain.md | Pre-push hook: direct-to-master guard (executable-class paths)
MOVE | The CI `secret-scan` job (gitleaks) is a backstop, not a sub | dotfiles-testing-toolchain.md | Pre-push hook: direct-to-master guard (executable-class paths)
MOVE | - **The instrumented set is `setup_env.sh` plus tracked `con | dotfiles-bash-coverage.md | Instrumented set: git ls-files derivation and the scripts/ history
MOVE | - **`scripts/` was outside the set until 2026-08-09, and the | dotfiles-bash-coverage.md | Instrumented set: git ls-files derivation and the scripts/ history
MOVE | - **`scripts/bash-tracer.sh` is the sole remaining exclusion | dotfiles-bash-coverage.md | Instrumented set: git ls-files derivation and the scripts/ history
MOVE | - **`git ls-files` rather than a filesystem glob is load-bea | dotfiles-bash-coverage.md | Instrumented set: git ls-files derivation and the scripts/ history
MOVE | - **The denominator counts commands, not source lines.** bas | dotfiles-bash-coverage.md | Denominator counts commands, not source lines (heredocs, python -c, arrays, continuations)
MOVE | Single-line forms of all four still count. | dotfiles-bash-coverage.md | Denominator counts commands, not source lines (heredocs, python -c, arrays, continuations)
MOVE | - **A function-declaration exclusion was tried and removed o | dotfiles-bash-coverage.md | Denominator counts commands, not source lines (heredocs, python -c, arrays, continuations)
MOVE | - **The denominator is the union of the static heuristic's c | dotfiles-bash-coverage.md | Denominator is the union of the heuristic and the real trace
MOVE | - **`covered > coverable` is now a hard, loud non-zero exit  | dotfiles-bash-coverage.md | Denominator is the union of the heuristic and the real trace
MOVE | Inspect one file's denominator, or a full run's coverage aga | dotfiles-bash-coverage.md | Denominator is the union of the heuristic and the real trace
MOVE | - Publish CI's bash coverage figure in the PR body once CI h | dotfiles-bash-coverage.md | covered > coverable is now a hard exit; publishing and reading the figure
MOVE | - `make bash-coverage` measures via PS4 xtrace (`scripts/run | dotfiles-bash-coverage.md | covered > coverable is now a hard exit; publishing and reading the figure
MOVE | - Before recording or publishing a bash coverage figure, or  | dotfiles-bash-coverage.md | covered > coverable is now a hard exit; publishing and reading the figure
MOVE | **`renovate.json` inlines the shared preset rather than exte | dotfiles-dependency-automation.md | renovate.json inlines the shared preset (private-repo visibility)
MOVE | **Confirmed in production 2026-08-24, and the confirmation i | dotfiles-dependency-automation.md | Renovate confirmed working: pinDigests and auto-merge in production
MOVE | Two things follow that the earlier analysis got wrong or cou | dotfiles-dependency-automation.md | Renovate confirmed working: pinDigests and auto-merge in production
MOVE | - **`mode=silent` is no longer in force for this repo.** The | dotfiles-dependency-automation.md | Renovate confirmed working: pinDigests and auto-merge in production
MOVE | - **`pinDigests: true` did the thing it was added for**, on  | dotfiles-dependency-automation.md | Renovate confirmed working: pinDigests and auto-merge in production
MOVE | **The zero-PR oracle this repo reasoned from was structurall | dotfiles-dependency-automation.md | The zero-PR oracle was structurally unfalsifiable under silent mode
MOVE | **`pip_requirements` is deliberately absent from `enabledMan | dotfiles-dependency-automation.md | pip_requirements deliberately absent from enabledManagers
MOVE | **Decided 2026-08-21, fleet-wide across all 18 non-archived  | dotfiles-dependency-automation.md | Dependabot: security auto-PRs off, vulnerability alerts on (fleet-wide)
MOVE | **This section exists because the decision lives nowhere in  | dotfiles-dependency-automation.md | Dependabot: security auto-PRs off, vulnerability alerts on (fleet-wide)
MOVE | **Rationale: alerts are the signal; auto-PRs are an unreview | dotfiles-dependency-automation.md | Dependabot: security auto-PRs off, vulnerability alerts on (fleet-wide)
MOVE | **The fleet-wide measurement inverted the expectation and is | dotfiles-dependency-automation.md | Dependabot: security auto-PRs off, vulnerability alerts on (fleet-wide)
MOVE | Two mechanical details, both non-obvious: | dotfiles-dependency-automation.md | Dependabot: mechanical details (repo-wide toggle, ordering)
MOVE | - **`automated-security-fixes` is repo-wide — GitHub offers  | dotfiles-dependency-automation.md | Dependabot: mechanical details (repo-wide toggle, ordering)
MOVE | - **The flag cannot be cleared while alerts are off.** `DELE | dotfiles-dependency-automation.md | Dependabot: mechanical details (repo-wide toggle, ordering)
MOVE | **Consequence, stated so it is not found as a surprise: Pyth | dotfiles-dependency-automation.md | Consequence: Python has no automated dependency update path
MOVE | See `~/git-repos/personal/ai-config/docs/knowledge/dotfiles-bats-test-infrastructure.md` for the full `MOCK_*` env  | dotfiles-bats-test-infrastructure.md | Mock Pattern full reference pointer (superseded by this section)
MOVE | **Pass-through mocks:** `ln`, `chmod`, `mv`, `cp`, and `tee` | dotfiles-bats-test-infrastructure.md | Mock Pattern: pass-through mocks (ln, chmod, mv, cp, tee)
MOVE | **`env -i` subprocess strips PATH** — `setup_ansible()`'s py | dotfiles-bats-test-infrastructure.md | Mock Pattern: env -i strips PATH (pyenv mock placement) -- CLAUDE.md addendum
MOVE | **`tests/mocks/curl` parses short-option clusters, not just  | dotfiles-bats-test-infrastructure.md | Mock Pattern: tests/mocks/curl short-option cluster parsing
MOVE | **`-o`'s write is now deferred until after the exit code is  | dotfiles-bats-test-infrastructure.md | Mock Pattern: tests/mocks/curl -o write ordering (deferred success write)
MOVE | `Makefile:1` carries `MAKEFLAGS += --no-print-directory`. GN | dotfiles-bats-test-infrastructure.md | MAKEFLAGS: --no-print-directory directive and its GNU Make version limit
MOVE | **The directive does not cover a direct `make -C` on GNU Mak | dotfiles-bats-test-infrastructure.md | MAKEFLAGS: --no-print-directory directive and its GNU Make version limit
MOVE | What the directive actually buys is the export: under `make  | dotfiles-bats-test-infrastructure.md | MAKEFLAGS: --no-print-directory directive and its GNU Make version limit
MOVE | **`MAKEFLAGS` is an exported environment variable, not a fil | dotfiles-bats-test-infrastructure.md | MAKEFLAGS: exported env var; guarded vs measuring test partition
MOVE | - **Guarded:** Per-call `--no-print-directory` flag (overrid | dotfiles-bats-test-infrastructure.md | MAKEFLAGS: exported env var; guarded vs measuring test partition
MOVE | - **Measuring:** `env -u MAKEFLAGS` prefix (strips the inher | dotfiles-bats-test-infrastructure.md | MAKEFLAGS: exported env var; guarded vs measuring test partition
MOVE | Both categories must exist in the test suite. A test capturi | dotfiles-bats-test-infrastructure.md | MAKEFLAGS: exported env var; guarded vs measuring test partition
MOVE | **The partition is enforced, not aspirational.** `tests/scri | dotfiles-bats-test-infrastructure.md | MAKEFLAGS: partition enforcement test and the git ls-files domain
MOVE | **The domain is derived from `git ls-files`, not listed.** T | dotfiles-bats-test-infrastructure.md | MAKEFLAGS: partition enforcement test and the git ls-files domain
MOVE | **Known gap: recursive sub-make and `-w` are invisible to it | dotfiles-bats-test-infrastructure.md | MAKEFLAGS: known gap -- recursive sub-make and -w invisible to the scanner
```

BASELINE rule_sentences=139 floor=101681


## Notes

**Span semantics.** A SECTION's span is its heading line through the line before the next
heading of **any** level (body only), not "next heading of level <= this one's" (the
pre-fix `find_heading_span` behaviour, which would have made `## Testing` swallow
ShellCheck/CI/Testing Rules/PowerShell/Coverage/Test Seams/Mock Pattern/MAKEFLAGS). Fixed in
`21d39bfa`, landed before this map's first commit.

**The map's field parsing is now structural, not a naive `" | "` split.** Fixed in
`8dc3cad6` ("fix(relocation): structural map parse, unit completeness"): `parse_map` peels
the record-type tag off the left with one split, then SECTION/INLINE take the remainder
whole (pipes and all) while MOVE/WAIVE peel their fixed trailing fields off the _right_ with
`rsplit`, leaving anything left over — including embedded `" | "` — as the anchor or
sentence. This is what makes a markdown-table anchor expressible at all; the previous
revision of this map worked around the naive-split limitation by exempting four table units
from INLINE/MOVE entirely, which is no longer necessary and no longer done (see below).

**The same commit added a completeness check: every unit inside a SECTION span must be
claimed by exactly one INLINE or MOVE record.** `measure`/`check` now list every unmatched
unit and exit 1 rather than silently treating an unclaimed unit as "stays, but only its rule
sentences are retained" — a decision this map had made implicitly (18 unlisted units) without
recording it as one. All units are now claimed; see the classification list below.

Re-run against the real tool:

```
python3 scripts/relocation_check.py measure --pre-rev 2e38f5e4 \
  --map docs/superpowers/plans/2026-09-25-relocation-map.md
```

Output: `units=175 rule_sentences=143 rule_bytes=33064 floor=101679` — matches the BASELINE
line below and my independent throwaway body-only-span implementation
(`/tmp/claude-1000/scratch/measure_body.py`), run before and after this classification pass.

**Every anchor was verified against the whole-document unit list**
(`/tmp/claude-1000/scratch/verify_map.py`), not eyeballed: all 175 MOVE anchors and all 28
INLINE anchors resolve to **exactly one** unit each among the 326 units `extract_units()`
finds in the whole `2e38f5e4:CLAUDE.md` (not just the 7 moving sections) — confirming
check4's first-match-in-document-order search targets the intended unit for every record.

**Four anchors are longer than 60 normalised characters, deliberately** — the map format is
"prefix-matched", and 60 is the _default_ length, not a hard requirement.

- Test Seams unit 0 and Mock Pattern unit 0 both open with "See `.../dotfiles-bats-test-infrastructure.md` for the full ..."; identical for their first 102 normalised
  characters, diverging only at byte 103. Both extended to 115 chars.
- Test Seams unit 43 (the cadence seams table) and Testing unit 18 (the uv overrides table)
  open with the _identical_ header-and-separator row (`| variable | read by | why it exists
|`), which only diverges from padding width at byte 65 — too fragile to anchor on, since a
  table-reformatting pass could change dash counts without changing content. Per the
  orchestrator's instruction, each anchor instead runs past the separator into its first real
  data row: Test Seams unit 43 to 900 chars (well past `` `_RHN_DETECTOR` ``, its first
  variable cell), Testing unit 18 to 400 chars (well past `` `UV_BIN` ``, its first variable
  cell).

**Classification of every unit that the structural-parse fix's completeness check newly
requires a record for** (previously either exempted for the pipe-collision reason above, or
left with no record at all, relying on slack) — decided by the orchestrator:

- `## Key Conventions` unit indices 0, 4-13 (11 short standing conventions: profile/capability
  model, legacy hostname vars, Ubuntu version detection, credential dir chmod 700, git repo
  layout, pyenv, Ansible venv packages, ruff venv-managed, pytest runner, alphabetical
  installs, shell syntax-only fixes) — now **INLINE**: a session needs these at start.
- `## Testing` unit indices 0-4, 11, 14 (the BATS intro, the `install_bats()` dispatcher, the
  macOS/Ubuntu install lines, and the **Run tests**, **Run unit tests only** and **Install
  hooks** command bullets) — now **INLINE**, same reason.
- `## Testing` unit index 21 (the `| file | group | pins | consumers |` five-renderings
  table) — now **INLINE**: it is small, and the "do not harmonise" retained rule sentence
  refers to it directly.
- `### Test Seams` unit index 43 (the cadence seams table) — now **INLINE**, as the plan
  already mandated ("the cadence seam table", one of the 5 `E2`-token units); previously
  un-expressible, now expressed directly with the 900-char anchor above.
- `## Testing` unit index 18 (the `UV_BIN`/`UV_FALLBACK_PATHS`/`REQUIREMENTS_CI_TARGET`
  overrides table) — now a **MOVE** to `dotfiles-testing-toolchain.md`, sharing the heading of
  the narrative unit (17) it belongs to ("Environment overrides added by the uv work").
- `## Key Conventions` unit index 29 (the actor/`PATH`-source/resolves/version table) — now a
  **MOVE** to `dotfiles-conventions.md`, sharing the heading of the gnubin/actor narrative it
  belongs to ("Which make an actor resolves (gnubin/actor table)").

One waiver was dropped as a side effect: "The hazard runs in both directions and only one was
documented until 2026-09-05." was a fragment of the cadence table (unit 43) that fell into
`retained_sentences` only because that unit was not yet INLINE. Now that it is, the
sentence-extraction step never runs over it, so the WAIVE would match nothing — removed
rather than left as dead weight. **Waiver count is now 13**, all narrative/historical/
incidental keyword matches, per-sentence reasons given inline in the fence. 143 rule
sentences remain retained after waiving.

- **Reclassified MOVE → INLINE after Task 4 attempt 1 (orchestrator, 2026-09-25):** the `install_cargo_tools` bullet and the `--no-deps is required` sentence. Every sentence of each is a retained rule sentence, so check 2 requires the unit's full text in `CLAUDE.md` while check 4 forbids it. A unit whose whole text is retained stays whole. Their verbatim copies in the knowledge files are harmless duplicates.

## Block review verdicts

Reviewed at `41bf8cc7` by an independent reviewer (Task 5). `CLAUDE.md` and this map are unchanged through `d4af17b1`; the two later commits touch only `phrases.md`.

Method: `/tmp/claude-1000/rv/pair.py` resolved every MOVE anchor to its pre-change unit with `relocation_check.extract_units`, grouped units by destination heading (85 groups), split each unit with the checker's pinned splitter, and marked each sentence present or absent in the normalised post-change `CLAUDE.md`. The script only paired the text. Every verdict below comes from reading the pre-change block beside what remains in `CLAUDE.md`, including where the retained sentences sit relative to their pointer. A group can have both a missing rule and a sentence that needs its unit. Such groups are marked with both and counted under each.

Borderline calls are marked *(borderline)*. Everything else I would defend as a clear finding.

| group (dest § heading) | verdict | detail |
| --- | --- | --- |
| G0 test-seams § Test seam idiom and override pattern | rule missing | "Tests set the var and pass a writable temp copy; production code leaves it unset." Only the idiom line survives. |
| G1 test-seams § Rustup signature verification seams | needs unit | "A digest taken over a separate fixture file the mock never copies cannot match, so the success-path test computes its digest over `MOCK_CURL_STDOUT`'s exact bytes." Here "the mock" is `tests/mocks/curl`, and the sentence explaining what it writes moved. |
| G2 test-seams § NVIDIA GPU detection seams | rule missing | "The other two redirect the keyring and apt source list at fixtures, so no test writes to `/usr/share/keyrings` or `/etc/apt/sources.list.d`." This is a live-state (E2-class) hazard, and the lead now carries no body. |
| G3 test-seams § brew_install_cask / brew_cask_installed seam | rule missing | "**`brew_install_cask` / `brew_cask_installed` (`lib/helpers.sh`) are a separate pair from the formula helpers, deliberately.**" Only the name survives, and "use the cask helpers for casks" is gone. |
| G4 test-seams § config/profiles.zsh and the legacy identity oracle | complete | |
| G5 test-seams § config/profiles.zsh export vs lib/detect_env.sh readonly | rule missing | "**`config/profiles.zsh` uses `export`; `lib/detect_env.sh` uses `readonly` — this is deliberate, not drift, and a future reader will otherwise "fix" one to match the other.**" The lead survives with an empty body. |
| G6 test-seams § _OVERRIDE_HOMEBREW_PREFIX_ARM / _INTEL seam | complete | |
| G7 test-seams § _OVERRIDE_KEYCHAIN_BIN seam and the interactive guard | rule missing + needs unit | Missing: "It is quoted anyway because that safety is a default, not a guarantee." and "The block it guards is wrapped in `[[ -o interactive ]]`, and that guard is load-bearing rather than tidy: …". Needs unit: "Measured 2026-08-16 on the Linux workstation: 16 agents pinning the suite's pipe …" cannot be read once the agent leak it measures has moved. |
| G8 test-seams § _OVERRIDE_CURRENT_LOGIN_SHELL seam and the chsh guard | rule missing | "It is not optional in tests: without it they pass on a mac whose account is already zsh and fail on any runner whose account is `/bin/bash`, …". Also the prohibition "deliberately **not** `${SHELL}`". |
| G9 test-seams § _OVERRIDE_GNUBIN_ARM / _INTEL seam | rule missing | Missing: "Both default to … respectively; keep the pairs in step, since a drift makes the install guard and the `PATH` consumer disagree." and "The seam is not optional in tests: … a test that forgets to point these at a nonexistent path short-circuits the guard and silently asserts nothing." |
| G10 test-seams § _OVERRIDE_GNUBIN_LINUX seam | rule missing | "That directory is real on any `claude`-class box …, so a test that forgets to point this seam at a nonexistent path short-circuits the `-d` guard and silently asserts nothing, …" |
| G11 test-seams § _OVERRIDE_DOCKER_BIN seam | rule missing | "If the installer's `.zprofile` lines reappear, delete them rather than committing them." |
| G12 test-seams § GGSHIELD_BIN / GGSHIELD_FALLBACK_PATHS seams | complete | |
| G13 test-seams § LEDGER_BIN seam | complete | |
| G14 test-seams § _OVERRIDE_LIB_TRAP_SCOPE seam | rule missing + needs unit | Missing: "The one test that closes it is "the real lib/ is clean against the real allowlist", …; keep it, because without it nothing in the suite touches the path production actually takes." Needs unit: "That is what lets the suite drive every verdict — …", whose "That" is the fixture glob, and that sentence moved. |
| G15 test-seams § _OVERRIDE_BATS_BIN seam | rule missing | "When reproducing a CI failure elsewhere, ship `git archive <the sha CI ran>`; if the tree is dirty, that is the finding." |
| G16 test-seams § _OVERRIDE_RUN_TMPDIR_ROOT seam | complete | |
| G17 test-seams § _PROFILES_LOADED sentinel | complete | |
| G18 test-seams § _AWS_GPG_BIN / _AWS_PKGUTIL_BIN / _AWS_KEY_PATH seams | needs unit | "`DOTFILES_REPO_ROOT` resolves the same expression at **source time**, …": "the same expression" is the inline `cd`/`dirname` derivation, and that sentence moved. |
| G19 test-seams § _AWS_BIN seam | rule missing *(borderline)* | "This machine has a real `aws` at `/usr/local/bin/aws`, so without the seam every `install_aws_tools` test silently takes the already-installed branch and asserts nothing about the install path at all …" The retained lead says the seam is "load-bearing" but never says that tests must set it. |
| G20 test-seams § Cadence seams overview | complete | |
| G21 test-seams § Cadence heartbeat contract | rule missing + needs unit | Missing: "**Every value is closed-form on purpose.** … Adding a **free-text** field satisfies the first and breaks the second." and "Before believing a count, ask what else the detector writes to stdout." Needs unit: "The second is the damaging one — …", whose two cases moved. Also "`doctor` renders the three classes distinctly …", which depends on the `result` values in the moved JSON contract. |
| G22 test-seams § Cadence agent PATH and plist rendering | rule missing + needs unit | Missing: "**When wiring a new detector, resolve its dependencies under this `PATH`, not under yours.**" Needs unit: "`ledger` lives in that first entry, …", where "that first entry" names the moved `PATH` list. Also "Verify the live file rather than the template after any change here:" now ends in a colon with nothing after it, because its `grep` command moved. |
| G23 test-seams § Cadence ntfy delivery and heartbeat rationale | rule missing | "**ntfy needs a topic and credentials, and neither is optional.**" The consequence also moved: POSTing bare `${NTFY_URL}` cannot deliver. |
| G24 test-seams § Pyenv-rehash and cargo-tools seams overview | complete | |
| G25 test-seams § _OVERRIDE_PYENV_ROOT seam | rule missing *(borderline)* | "The seam exists precisely to remove that ordering hazard, and every test that touches shim counting or the hook install sets it explicitly rather than relying on `HOME`." |
| G26 test-seams § _RELEASE_TMP_ROOT seam | rule missing *(borderline)* | "**`_RELEASE_TMP_ROOT` … exists because BSD `mktemp -d` with a template argument ignores `TMPDIR` entirely** — … a `TMPDIR`-based assertion of the failure-path cleanup would be silently inert there." Check 8 task B depends on a session knowing to set this seam. |
| G27 test-seams § _TFLINT_URL / _TFLINT_SHA256 / _TFSEC_URL / _TFSEC_SHA256 seams | complete | The never-mock-`sha256sum` rule survives, but only under the rustup bullet. The tflint lead has no body. |
| G28 test-seams § _TFENV_ROOT / _TFENV_REPO_URL seams | complete | |
| G29 test-seams § _PWSH_BIN / _PWSH_PROBE_TIMEOUT seams | rule missing + needs unit | Missing: "**The `timeout`-absent fallback inside that helper needs its own two tests, and this is why.**" Needs unit: "Reaching it requires a PATH scoped to a directory holding no `timeout`, …", where "it" is the fallback branch, and "The pair must cover both directions, …", where "the pair" is the two tests. |
| G30 test-seams § _DOCTOR_PROBE_TIMEOUT seam | complete | |
| G31 test-seams § _CRATES_API seam | complete | |
| G32 test-seams § Claude plugin provisioning seams overview | complete | |
| G33 test-seams § _CLAUDE_GUARD_GIT seam | complete | |
| G34 test-seams § tests/mocks/claude seam modes | complete | |
| G35 test-seams § Claude plugin provisioning: stdin redirect and IFS tab collapse | rule missing | "**Every `claude` call inside a `while read` loop in `setup_claude_plugins`/`run_update`'s claude section redirects stdin from `/dev/null`** … without it, `claude` would … consume the remaining manifest lines …, silently truncating iteration after the first external call." The lead still names "the stdin redirect", but its rule is gone. |
| G36 conventions § GPU provisioning as the HAS_* exception | rule missing + needs unit | Missing: "**GPU provisioning is the one deliberate exception to that rule.**" (gate on hardware, not a `HAS_*` capability). This matters because the retained first Key Conventions bullet says "prefer `HAS_*` vars". Also missing: "the `systemctl restart docker` is **conditional on `daemon.json` actually changing** — … an unconditional bounce every provision would kill a live job". Needs unit: the standalone bullet "Measured on `claude` 2026-09-12 with toolkit 1.20.0 already installed; `workstation` … never surfaced it." |
| G37 conventions § zsh -i -c 'exit' after .zshrc changes | rule missing | "After any change to `.zshrc` or `.zshrc.d/` files, run `zsh -i -c 'exit'` before committing to catch re-source crashes before they reach prod." and "From a worktree, source the branch's own files explicitly instead — …". Only the pointer remains. |
| G38 conventions § $0 resolution in zsh startup files | rule missing | "Use `${${(%):-%x}:A:h}` in any file that may be read as a startup file — …". Only the pointer remains. |
| G39 conventions § _UPDATE_SECTION_ORDER coupling | needs unit | "Adding `_update_record_start/end "new-section"` in `run_update()` without also adding `"new-section"` to this array …": "this array" was named only in the moved lead. |
| G40 conventions § git-hooks section coupling and _git_hooks_target_dir | needs unit | "**Both** call sites must branch on it: …" is the spec's own example. "it" is `install_git_hooks_all_repos`'s 0/1/2 return, and that sentence moved. Also "This matters more than a mislabel, …". |
| G41 conventions § _install_ubuntu_brew_packages tri-state return | needs unit | "`install_ubuntu_packages` therefore captures the rc rather than using `\|\| return 1`: **only rc 1 aborts**, …": "therefore" rests on the moved 0/1/2 contract. |
| G42 conventions § claude plugins install -s user scope flag | rule missing | "**`claude plugins install` takes `-s user` and a `plugin@marketplace` id; the flag pins the scope rather than fixing a defect.**" Only the pointer remains. |
| G43 conventions § zsh-autosuggestions reported update section | rule missing + needs unit | Missing: "`-e` rather than `-d` is also deliberate: … tightening to `-d` would route that layout to `SKIP` forever …". Needs unit: "That plumbing command walks upward …" and "A future reader will otherwise "tighten" this to the plumbing form; don't." The guard they refer to is named only in the moved bold sentence. |
| G44 conventions § Update summary name column width | complete | |
| G45 conventions § cheat.sh section: both artifacts, both failures FAIL the run | needs unit | "It previously ran the tab-completion fetch …": "It" is the cheat.sh section, named only in the moved lead. |
| G46 conventions § .warp/settings.toml Warp-owned symlink | needs unit | "One value in it is a **deliberate non-default, not drift**: …": "it" is `.warp/settings.toml`, named only in the moved lead. |
| G47 conventions § Global/system core.hooksPath pin: detection and remedy | needs unit | "An **empty or whitespace-only** value is a real pin, not an absent one: …": the value of what? `core.hooksPath` is introduced only in the moved lead. |
| G48 conventions § Homebrew make gnubin prepend | needs unit | "**It must be a prepend, not `path+=`.**": "It" is the gnubin prepend in the moved lead. |
| G49 conventions § Which make an actor resolves (gnubin/actor table) | needs unit | "`Makefile:1`'s `MAKEFLAGS += --no-print-directory` is why — …" and "Do not reopen this without re-running that comparison; …": the claim and the comparison both moved. The block also ends on "Two traps recorded from those retirements, …:", while the traps themselves are grouped under G50. |
| G50 conventions § setup_env.sh cannot run non-interactively on the Linux workstation | rule missing + needs unit | Missing: "Workaround for a non-interactive caller is to prepend the prefix explicitly rather than to re-bootstrap: `PATH="/home/linuxbrew/.linuxbrew/bin:${PATH}" ./setup_env.sh -t developer`." Needs unit: "It leads `/usr/bin` in `/etc/paths`, …", where "It" is `/usr/local/bin`, and "The macOS bullet above and this one are the same defect at two severities — …". |
| G51 conventions § terraform on Linux via tfenv, and the checkout guard | rule missing | "That ordering is load-bearing: run the loop first and it plants two dangling symlinks, …": the guard must stay before the symlink loop. This comes with "**… the remedy is in the WARN, not in doctor.**" |
| G52 conventions § tflint/tfsec staleness gap; CARGO_TOOLS staleness | complete | |
| G53 testing-toolchain § make test parallel jobs | rule missing + needs unit | Missing: "Override it per invocation (`make test JOBS=6`).", "To force serial anywhere, `make test HAVE_PARALLEL=`." and "A name here needs a measurement beside it." (`BATS_SERIAL_FILES`). Needs unit: "The guard is required rather than defensive, …" (the detection bullet moved) and "The error names `$(origin JOBS)`, …". |
| G54 testing-toolchain § config/profiles.sh dual lint scope; phrase_check.py | complete | |
| G55 testing-toolchain § Ansible venv snapshot before every sync | rule missing + needs unit | Missing: "Reverting this repo does not restore the venv." and the rollback procedure ("To roll back:" plus its fenced `pip install --no-deps -r …` command). Needs unit: the INLINE "`--no-deps` is required — …" now qualifies a command that is no longer in `CLAUDE.md`. |
| G56 testing-toolchain § Environment overrides added by the uv work | needs unit | The splitter cut the table into sentences, so the retained "sentence" is the header row, the separator row and a truncated `UV_FALLBACK_PATHS` row ending at "array of prefix candidates." `CLAUDE.md:282` is now a broken, partial table. Keep the table whole. |
| G57 testing-toolchain § Sync/check CI requirements commands | rule missing *(borderline)* | "**Sync CI requirements:** `make sync-requirements-ci` … **Check CI requirements drift:** `make check-requirements-ci` …" is a command entry of the same class as the **Run tests**/**Install hooks** units that stayed INLINE. |
| G58 testing-toolchain § Requirements CI groups: do not harmonise | complete | |
| G59 testing-toolchain § Requirements CI groups: purpose over CI/local | rule missing + needs unit | Missing: "**Provenance does not go in these headers, and that is load-bearing.**" with "Provenance belongs on a _consumer's_ copy, written at copy time." Also "**`bandit`, `radon` and `vulture` stay in `test-lint` and are absent from every CI group, which is the point.**" Needs unit: "**The framing that matters …: this was never a deletion problem.**" and "A `runtime`-group edit moves `uv.lock` … in that header …". |
| G60 testing-toolchain § Requirements CI groups: drift-gate blindness | needs unit + rule missing | Needs unit: "Never hand-edit it." stands alone at `CLAUDE.md:304`, and "it" (`requirements-ci.txt`) is gone. Missing: "A green `check-requirements-ci` is not evidence about grouping." |
| G61 testing-toolchain § Pre-commit hook: make lint and ggshield | needs unit | "**Resolved by explicit override, then `PATH`, then absolute prefixes — …**" has no subject, because the ggshield step moved. Also "The absent case still exits 0 — … but it now says so twice on stderr". |
| G62 testing-toolchain § Pre-push hook: fail-closed inert-path set | rule missing + needs unit | Missing: "The pre-push hook is **permanent**." Needs unit: "`docs/` and `.github/` are **not** wholesale-inert: …", because the inert set it qualifies moved. |
| G63 testing-toolchain § Pre-push hook: worktree root resolution and git env strip | complete | |
| G64 testing-toolchain § Pre-push hook: direct-to-master guard | rule missing | "And the refusal is checked **before** the `needs_test` early-exit, because an inert-but-unsafe path would otherwise skip the guard along with the suite." This is one of "two implementation constraints, both load-bearing". Its sibling survived. |
| G65 bash-coverage § Instrumented set: git ls-files derivation | rule missing + needs unit | Missing: "**`git ls-files` rather than a filesystem glob is load-bearing, not stylistic.**" Needs unit: the retained bullet "The tracer enables tracing through `BASH_ENV`, … discarded by a predicate that globbed only `config/` and `lib/`." is history cut off from its context. |
| G66 bash-coverage § Denominator counts commands, not source lines | needs unit | "That was 13 of `config/profiles.sh`'s 15 lines and 8 of `lib/helpers.sh`'s. - **Pure-argument backslash continuations** — …" is a fragment spanning two items of a list that was split, and it renders as one garbled bullet. |
| G67 bash-coverage § Denominator is the union of the heuristic and the real trace | needs unit | "**Read it beside the ratio from the same run, never a ratio from another one.**": "it" is the heuristic-disagreement count, and that sentence moved. |
| G68 bash-coverage § covered > coverable is now a hard exit; publishing and reading the figure | rule missing | "Publish CI's bash coverage figure in the PR body once CI has run (`gh pr edit <n>`); a local run is a preview, labelled as one." |
| G69 dependency-automation § renovate.json inlines the shared preset | rule missing + needs unit | Missing: "`ai-config/renovate-presets/default.json` stays canonical; keep the `extends`, `schedule`, `labels` and `packageRules` keys in sync with it by hand, …". Needs unit: "Measured 2026-08-23 with config as the only variable: the remote-preset form …" now opens `## Dependency Automation` without saying what was varied. |
| G70 dependency-automation § Renovate confirmed working | complete | |
| G71 dependency-automation § The zero-PR oracle was structurally unfalsifiable | rule missing | "The lesson survives the lift: establish what a mechanism is _permitted_ to do before drawing any conclusion from what it has not done." |
| G72 dependency-automation § pip_requirements deliberately absent from enabledManagers | rule missing + needs unit | Missing: "**`pip_requirements` is deliberately absent from `enabledManagers`.**" Needs unit: "Measured against all five renderings: only `requirements-ci.txt` matches — …". What it matches is Renovate's pattern, and that sentence moved. |
| G73 dependency-automation § Dependabot: security auto-PRs off, alerts on | rule missing *(borderline)* | "**Decided 2026-08-21, fleet-wide across all 18 non-archived repos: Dependabot security auto-PRs OFF, Dependabot vulnerability alerts ON.**" This policy state is now held by nothing in `CLAUDE.md` except the pointer's trigger. |
| G74 dependency-automation § Dependabot: mechanical details | rule missing | "Order the calls: `PUT vulnerability-alerts`, then `DELETE automated-security-fixes`." |
| G75 dependency-automation § Consequence: Python has no automated update path | complete | |
| G76 bats-test-infrastructure § Mock Pattern full reference pointer | complete | |
| G77 bats-test-infrastructure § Mock Pattern: pass-through mocks | rule missing | "Set the corresponding exit var to a non-zero value to simulate failure instead." The pass-through fact also moved: `ln`/`chmod`/`mv`/`cp`/`tee` call the real binary. |
| G78 bats-test-infrastructure § Mock Pattern: env -i strips PATH | rule missing | "**`env -i` subprocess strips PATH** — `setup_ansible()`'s pyenv calls need the mock placed at `${HOME}/.pyenv/bin/pyenv`, not PATH-injected." |
| G79 bats-test-infrastructure § tests/mocks/curl short-option cluster parsing | complete | |
| G80 bats-test-infrastructure § tests/mocks/curl -o write ordering | complete | |
| G81 bats-test-infrastructure § MAKEFLAGS: --no-print-directory directive | rule missing *(borderline)* | "**The load-bearing protection is the per-call flag and the partition below, not this line**". Also "The directive does not cover a direct `make -C` on GNU Make 4.3 …". |
| G82 bats-test-infrastructure § MAKEFLAGS: guarded vs measuring test partition | needs unit + rule missing | `CLAUDE.md:596` reads "… tests fall into two categories: Use it only for that — …". Both categories were deleted between the colon and "Use it", so "it" and "Both categories must exist" have no referent. Missing: "- **Guarded:** Per-call `--no-print-directory` flag …, for tests that care about exact output shape" and "- **Measuring:** `env -u MAKEFLAGS` prefix …". This whole block should be INLINE. |
| G83 bats-test-infrastructure § MAKEFLAGS: partition enforcement test | complete | |
| G84 bats-test-infrastructure § MAKEFLAGS: known gap | complete | The retained "A line scanner can only see what is on the invoking line." is orphaned but harmless. |

### Waivers

| waived sentence (abridged) | verdict | note |
| --- | --- | --- |
| The suite's positive control is the mismatch case, … | narrative | |
| `brew_formula_installed` greps `brew list --formula` in _both_ branches, … | narrative | The rule it motivates is missing separately (G3). |
| Mutation-confirmed: reading the seam under a typo'd name … | narrative | |
| The seam exists because the only other way to reach either branch … | narrative | |
| The three pre-existing tests encoded all of it: … | narrative | |
| **Two code paths, and the tests only exercise one.** | narrative | The rule it sets up ("keep it") is missing separately (G14). |
| Re-install seeds a missing heartbeat and never clobbers a real one, … | **rule** | This is an installer invariant any edit to the installer must preserve. "never clobbers a real one" is a prohibition on the code, not a description of the past. |
| The `rm -rf` in the WARN is the only thing that does. | narrative | |
| This conserves GitHub Actions minutes — CI runs only on PRs. | narrative | |
| The fix needs a branch and a PR, or `--no-verify`. | **rule** | The reason given ("`verify` matches inside `--no-verify`") is true, but it does not address whether the sentence is a rule. It is: a defective guard cannot be fixed by a direct push to master, and the sentence names the permitted route. |
| This bullet used to read "nothing under test sources them, …" | narrative | |
| The exclusion was asserted, never measured. | narrative | |
| A union-added line raises numerator and denominator together, … | narrative | This is the rationale for the retained "Read it beside the ratio …" rule. |

### Pointers

All 50 pointer lines are pointer-only: each matches `^(- )?**Before** … read … § \`…\`.$`, with no text before or after. Most triggers name a concrete path or symbol. The exceptions:

| pointer | score | why |
| --- | --- | --- |
| `CLAUDE.md:640` cheat.sh, "**on** `lib/update_summary.sh`" | weak trigger | The cheat.sh section is in `lib/workflows.sh` (`_update_record_end "cheat.sh"` at `:1114`). A session editing it touches `lib/workflows.sh`, not the file named. |
| `CLAUDE.md:636` zsh-autosuggestions, "**on** `lib/workflows.sh:672-689`" | weak trigger | The line range is stale: that code is now at `lib/workflows.sh:1118-1126`. A session searching for the lines will not match them. |
| `CLAUDE.md:651` "**on** a hook that shells out to `make`" | weak trigger | Names no path or symbol. |
| `CLAUDE.md:270` "changing lint scope **on** `Makefile`, `scripts/phrase_check.py`" | weak trigger | The target heading joins two unrelated blocks. A session wiring `phrase_check.py` into a gate is not "changing lint scope", so the phrase_check half never fires. |
| `CLAUDE.md:578` "looking up a `MOCK_*` var" | ok trigger, stub target | The cited heading holds a single sentence that points back at the same file. The pointer resolves, but to a stub. |
| `CLAUDE.md:574` Test Seams single pointer | ok | This is the only pointer for `### Test Seams`. It cites only the idiom heading, and none of the ~35 per-seam headings in `dotfiles-test-seams.md` is reachable by name from `CLAUDE.md`. The spec allows "a pointer to `dotfiles-test-seams.md`", so this is acceptable, but a session following it lands on the idiom block, not on its seam. |
| `CLAUDE.md:679`, `:683` Dependabot "on GitHub repo Settings" / "the GitHub API" | ok | No in-repo artifact exists, and the block says so, so naming the setting is the best available trigger. |

### Structure findings

Test Seams (`CLAUDE.md:408-574`):

1. **A lead labels a different seam's INLINE unit.** The `_OVERRIDE_NVIDIA_GPU_PRESENT`/`_KEYRING`/`_LIST` lead (`:422`) has no body. It is immediately followed by the INLINE `_OVERRIDE_DOCKER_DAEMON_JSON` / `nvidia-ctk` unit, so the NVIDIA lead visually heads the docker-daemon seam.
2. **Same defect, twice more.** The `config/profiles.zsh` lead (`:439`) is followed by the INLINE `tests/helpers/legacy_oracle.bash` unit. The `the stdin redirect and IFS tab-collapse …` lead (`:570`) is followed by the INLINE `_OVERRIDE_CLAUDE_PLUGIN_CACHE` unit. In both cases the lead names a different subject from the INLINE unit under it. The INLINE `_CARGO_BIN` and `_RELEASE_BIN_DIR` units likewise follow the `_OVERRIDE_PYENV_ROOT` bullet with no lead of their own.
3. **A lead duplicates an INLINE unit's own bold lead.** The INLINE rustup unit (`:412`) opens with bold `_RUSTUP_INIT_URL` / `_RUSTUP_INIT_SHA256` / `_RUSTUP_INIT_BIN` / `_OVERRIDE_CARGO_BIN_DIR`. The bullet lead that follows (`:419`) repeats those four names, and it comes after the unit it is meant to label. `_OVERRIDE_RUN_TMPDIR_ROOT` and `_AWS_BIN` do the same with their own retained bold sentences, which repeat the lead.
4. **Invented prose beyond seam names.** The spec allows only seam-name leads plus pointers. These leads carry descriptive text that is neither a seam name nor a reader:
   - "(`the legacy identity oracle`)", which is backticked prose in the reader slot;
   - "`config/profiles.zsh` vs `lib/detect_env.sh` (`export` vs `readonly` scope)", which names no seam and has no body;
   - "the stdin redirect and IFS tab-collapse in claude plugin provisioning";
   - "the heartbeat contract (`last-run.json`)", "the plist `PATH` (`cadence.plist.template`)", "ntfy delivery (`_rhn_notify`)" and "`tests/mocks/claude` mock modes (`MOCK_CLAUDE_*` env vars)".

   Each is short, but each is new text that no check covers. Reader slots are also inconsistent with the spec's `file:function` form. Some give a function only (`install_make_macos`, `_install_rustup_rs`). One is wrong: "the pyenv-rehash and cargo-tools seams (`lib/helpers.sh`)", when the cargo seam is in `lib/developer.sh`.
5. **The seam idiom line is cut down.** It keeps `local _file="${_OVERRIDE_VAR:-...}"`, but "Tests set the var and pass a writable temp copy; production code leaves it unset." is gone (G0).

Outside Test Seams:

6. **Retained sentences are placed as orphans before their pointer.** Across `## Testing`, `## Key Conventions` and `## Dependency Automation`, most MOVE groups become "retained sentence(s), then pointer". The sentence is read before the pointer that would supply its antecedent, which is why the needs-unit count is high. Placing the pointer first would not fix a dangling "it", but it would at least put the subject in front of the reader.
7. **Splitter artefacts render as broken markdown.** The splitter cut a table (`CLAUDE.md:282`, G56) and a flattened nested list (`CLAUDE.md:401`, G66) mid-structure. The retained "sentences" are fragments of a table row and of a list item. Spec check 2 treats them as sentences, but they are not.
8. **Knowledge-file grouping mismatches**, which affect what a pointer delivers:
   - G49 ends with "Two traps recorded from those retirements …:", but the two traps are filed under G50's heading (`setup_env.sh cannot run non-interactively …`).
   - G68's heading begins "covered > coverable is now a hard exit", but that unit is filed under G67.
   - G54's heading joins two unrelated blocks (`config/profiles.sh` dual scope, `phrase_check.py`).

### Summary

complete: 27, rule missing: 44, needs unit: 31, weak trigger: 4, waiver-is-rule: 2

85 MOVE groups: 27 complete and 58 with findings. 17 groups carry both a missing rule and a sentence that needs its unit, and are counted under each. 6 of the 44 rule-missing verdicts are marked borderline (G19, G25, G26, G57, G73, G81). Excluding them still leaves 38 clear findings. Under spec check 5, every needs-unit verdict sends its unit back inline. The volume of rule-missing verdicts shows that the regex-keyed retention rule loses imperatives and "is not optional"/"deliberately" prohibitions routinely, not occasionally.

## Block review verdicts — round 2 (rule bullets)

Reviewed at 4516504e by an independent reviewer (Task 10).

Method: `/tmp/claude-1000/rv2/pair.py` resolved every MOVE anchor to its unit in `2e38f5e4:CLAUDE.md`, grouped the units by destination heading (85 groups), recomputed each group's (a) set with the checker's own splitter, rule regex and waivers, and located the group's single compact pointer in `CLAUDE.md` at HEAD. `/tmp/claude-1000/rv2/dump.py` put the original block, its (a) sentences, its round-1 row and the authors' rules-file section side by side. `/tmp/claude-1000/rv2/suffix.py` checked placement mechanically: every rules-file bullet appears verbatim in `CLAUDE.md` within the 8 lines above its group's pointer, the pointer suffix sits on that group's last bullet, and each Test Seams lead is present. The scripts only paired the text. I made every verdict below by reading the original block against the rule lines. The rules files' `covers:` lists were not taken as evidence. Leads and function claims were checked by extracting each named function's body and grepping it for the variable.

| group | verdict | detail |
| --- | --- | --- |
| G0 test-seams § Test seam idiom and override pattern | wrong: "Name a test seam `_OVERRIDE_VAR`" | The original gives the idiom (`${_OVERRIDE_VAR:-…}`, a placeholder), not a naming rule. Read as a convention, the line contradicts most seams in the same section: `_RUSTUP_INIT_*`, `GGSHIELD_BIN`, `LEDGER_BIN`, `_AWS_*`, `_RHN_*`, `_RELEASE_TMP_ROOT`, `_TFLINT_*`, `_PWSH_*`, `_CRATES_API`, `_CLAUDE_GUARD_GIT`, `_CARGO_BIN`. The (b) item "set it to a writable temp copy; leave it unset in production" is covered. |
| G1 test-seams § Rustup signature verification seams | covered | |
| G2 test-seams § NVIDIA GPU detection seams | covered | |
| G3 test-seams § brew_install_cask / brew_cask_installed seam | covered | |
| G4 test-seams § config/profiles.zsh and the legacy identity oracle | covered | |
| G5 test-seams § config/profiles.zsh export vs lib/detect_env.sh readonly | covered | |
| G6 test-seams § _OVERRIDE_HOMEBREW_PREFIX_ARM / _INTEL seam | covered | |
| G7 test-seams § _OVERRIDE_KEYCHAIN_BIN seam and the interactive guard | missing: "The `[[ ${VAR} ]]` tests throughout this file are deliberately **not** quoted" | Round 1 and the authors both missed this (c) prohibition. `[[ ]]` suppresses splitting regardless of `SH_WORD_SPLIT`, so quoting them is churn. The line says to keep one expansion quoted, which invites a reader to quote the rest. The companion rule is also absent: `tests/zshrc.d/unit.bats` must keep `setopt shwordsplit`, because without it the quoting test is vacuous. Everything in (a) and (b) is covered. |
| G8 test-seams § _OVERRIDE_CURRENT_LOGIN_SHELL seam and the chsh guard | missing: "the three end-to-end `run_doctor` tests stub every sub-check by name, so `_doctor_check_login_shell` must be stubbed there too or it reads the real account mid-suite" | This is an (a) sentence with "must". The rule lines tell tests to set `_OVERRIDE_CURRENT_LOGIN_SHELL`, which does not cover the `run_doctor` tests, which stub by name. The `sudo -n chsh` then `chsh` claim checks out against `setup_zsh_as_default_shell` (`lib/helpers.sh`). |
| G9 test-seams § _OVERRIDE_GNUBIN_ARM / _INTEL seam | covered | |
| G10 test-seams § _OVERRIDE_GNUBIN_LINUX seam | covered | |
| G11 test-seams § _OVERRIDE_DOCKER_BIN seam | covered | |
| G12 test-seams § GGSHIELD_BIN / GGSHIELD_FALLBACK_PATHS seams | covered | |
| G13 test-seams § LEDGER_BIN seam | covered | |
| G14 test-seams § _OVERRIDE_LIB_TRAP_SCOPE seam | covered | |
| G15 test-seams § _OVERRIDE_BATS_BIN seam | covered | |
| G16 test-seams § _OVERRIDE_RUN_TMPDIR_ROOT seam | covered | |
| G17 test-seams § _PROFILES_LOADED sentinel | covered | |
| G18 test-seams § _AWS_GPG_BIN / _AWS_PKGUTIL_BIN / _AWS_KEY_PATH seams | missing: "It is a plain assignment rather than a `${VAR:-}` self-guard" | Part of an (a) sentence. The self-guard was written, measured, and retired. It added an env-settable name that selects where a cryptographic trust anchor is read from. Nothing in the rule lines stops a reader from re-adding it. `lib/constants.sh:185` is a plain assignment today. Also weakened: the (a) rule that the regression tests "assert on the **post-import** failure rather than on the absence of the import failure" (E5) is gone. What remains is "`cd` away before asserting", which an absence assertion satisfies. |
| G19 test-seams § _AWS_BIN seam | covered | |
| G20 test-seams § Cadence seams overview | covered | |
| G21 test-seams § Cadence heartbeat contract | weakened: `max_age_days` fallback — "names its source" dropped | (a) sentence: `_doctor_check_cadence` prefers the written value and **names its source**, `(max 3d, from heartbeat)` versus `(max 8d, default — heartbeat carries none)`, "so a fallback is never mistaken for a reading". The rule line says "never mirror the bound in the reader", but the reader does carry a default of 8. The line forbids that default without saying it must be labelled when used. Everything else in (a) and (b) is covered, including closed-form fields, the stdout discipline and "never clobber". |
| G22 test-seams § Cadence agent PATH and plist rendering | covered | |
| G23 test-seams § Cadence ntfy delivery and heartbeat rationale | covered | See structure finding 2 on the lead's reader. |
| G24 test-seams § Pyenv-rehash and cargo-tools seams overview | covered | The original has no rule. The rule line is filler ("treat each seam below individually"). |
| G25 test-seams § _OVERRIDE_PYENV_ROOT seam | covered | |
| G26 test-seams § _RELEASE_TMP_ROOT seam | covered | |
| G27 test-seams § _TFLINT_URL / _TFLINT_SHA256 / _TFSEC_URL / _TFSEC_SHA256 seams | covered | |
| G28 test-seams § _TFENV_ROOT / _TFENV_REPO_URL seams | covered | |
| G29 test-seams § _PWSH_BIN / _PWSH_PROBE_TIMEOUT seams | covered | |
| G30 test-seams § _DOCTOR_PROBE_TIMEOUT seam | covered | |
| G31 test-seams § _CRATES_API seam | covered | |
| G32 test-seams § Claude plugin provisioning seams overview | covered | |
| G33 test-seams § _CLAUDE_GUARD_GIT seam | covered | |
| G34 test-seams § tests/mocks/claude seam modes | covered | |
| G35 test-seams § Claude plugin provisioning: stdin redirect and IFS tab collapse | covered | |
| G36 conventions § GPU provisioning as the HAS_* exception | covered | |
| G37 conventions § zsh -i -c 'exit' after .zshrc changes | covered | The explicit worktree sourcing command is left to the pointer. The rule ("source the branch's own files") stands. |
| G38 conventions § $0 resolution in zsh startup files | covered | |
| G39 conventions § _UPDATE_SECTION_ORDER coupling | missing *(borderline)*: "the real risk when **removing** a section is a stray reference to its name surviving in a fixture that still seeds it" | Round 1 and the authors both missed this (c) item. The original also retracts the older rule that hardcoded count assertions must be audited. Without that retraction, a reader may reinstate the audit or skip the fixture check. |
| G40 conventions § git-hooks section coupling and _git_hooks_target_dir | covered | Not raised: the newline/tab and non-regular-file (FIFO) skips in discovery. They are code invariants stated descriptively, not directives. |
| G41 conventions § _install_ubuntu_brew_packages tri-state return | covered | |
| G42 conventions § claude plugins install -s user scope flag | covered | |
| G43 conventions § zsh-autosuggestions reported update section | covered | |
| G44 conventions § Update summary name column width | covered | |
| G45 conventions § cheat.sh section: both artifacts, both failures FAIL the run | covered | |
| G46 conventions § .warp/settings.toml Warp-owned symlink | covered | |
| G47 conventions § Global/system core.hooksPath pin: detection and remedy | missing: "`tests/setup_env/git_hooks.bats`'s `setup()` must neutralize `GIT_CONFIG_GLOBAL`/`GIT_CONFIG_SYSTEM`" | This is an (a) sentence. Without it, the suite fails on any machine that has a pin, and because pre-push runs `make test`, that developer cannot push. The output-contract rule is also absent: `scope<TAB>remedy<TAB>value` with the value last, so a tab in a pinned path cannot truncate the remedy command. |
| G48 conventions § Homebrew make gnubin prepend | covered | See structure finding 4: "this file" is dangling. |
| G49 conventions § Which make an actor resolves | covered | |
| G50 conventions § setup_env.sh cannot run non-interactively on the Linux workstation | wrong: "`/usr/local/bin` cannot substitute: it reaches login shells only via `/etc/paths`/`path_helper`" | `/etc/paths` and `path_helper` are macOS-only. The original trap is about macOS `make` resolution: a symlink in `/usr/local/bin` does not reach cron, launchd or sshd. Here it is stated as the reason `/usr/local/bin` cannot fix a Linux-workstation problem, where that mechanism does not exist. Also weakened: the (a) generalisation "treat a tool path placed in an interactive-only rc file as gating whichever actor sources that file, not as a machine-wide fact" became a Linux-specific statement. The hook-`PATH` rule kept its instruction but lost its reason: it shadows `tests/scripts/pre_push.bats`'s `make` mock, and 28 of 36 tests failed. |
| G51 conventions § terraform on Linux via tfenv, and the checkout guard | wrong: "…dangling symlinks that the guard's own `-L` branch then treats as already repaired" | The `-L` branch belongs to the symlink loop, not the `-x` guard. See the code's own comment in `_install_ubuntu_tfenv` ("the loop's own `-L` branch") and the loop at the `for _name in tfenv terraform` / `[[ -L "${_link}" ]]` lines. The ordering rule itself is correct and covered. |
| G52 conventions § tflint/tfsec staleness gap; CARGO_TOOLS staleness | covered | |
| G53 testing-toolchain § make test parallel jobs | weakened: "Unset `MAKEFLAGS` and the recipe environment when nesting make — the `$(origin JOBS)` error depends on both being clear" | Original: "a **test** that invokes make inside make must unset both [routes by which a command-line `JOBS` arrives] to stay discriminating". The line drops the test-only condition. As written, it tells anyone nesting make to strip `MAKEFLAGS`, which also strips `--no-print-directory` (see the MAKEFLAGS section). It also misstates the reason: the error *names* `$(origin JOBS)` because `JOBS` arrives by two routes. It does not depend on them being clear. `tests/makefile_parallel_target.bats:21` shows the real form: `unset MAKEFLAGS MFLAGS MAKELEVEL JOBS`. |
| G54 testing-toolchain § config/profiles.sh dual lint scope; phrase_check.py | covered | |
| G55 testing-toolchain § Ansible venv snapshot before every sync | covered | See structure finding 6. |
| G56 testing-toolchain § Environment overrides added by the uv work | covered | See structure finding 4 on "the three-row variable table". |
| G57 testing-toolchain § Sync/check CI requirements commands | covered | |
| G58 testing-toolchain § Requirements CI groups: do not harmonise | covered | |
| G59 testing-toolchain § Requirements CI groups: purpose over CI/local, and the erosion guard | missing: "**`ci-test`'s boundary is stated in `pyproject.toml` and guarded by a test, not by review.**" | Round 1 and the authors both missed this (c) item, even though the heading names "the erosion guard". The rule: do not add a tool to `ci-test` because "that is where tools go". The `mutation whales` and `materially smaller` tests guard the boundary, and additions are admitted only on a measurement, as `hypothesis` was. None of the three rule lines mentions it. |
| G60 testing-toolchain § Requirements CI groups: drift-gate blindness | covered | Minor: "for months" is not in the original, which gives only "until 2026-08-21 (#231)". |
| G61 testing-toolchain § Pre-commit hook: make lint and ggshield | covered | |
| G62 testing-toolchain § Pre-push hook: fail-closed inert-path set | covered | |
| G63 testing-toolchain § Pre-push hook: worktree root resolution and git env strip | covered | |
| G64 testing-toolchain § Pre-push hook: direct-to-master guard | missing: "`scripts/pre-push` is itself executable-class, so a defective guard cannot be repaired by a direct push to master. The fix needs a branch and a PR, or `--no-verify`." | Round 1 ruled this waived sentence a rule (waiver table). No rule line carries it. Also missing from (a): "If a docs push is refused and names a file you did not touch in that commit, check `git diff --name-only <remote-sha>..HEAD` before assuming the guard is wrong." The range rule survives, but its diagnostic does not. |
| G65 bash-coverage § Instrumented set: git ls-files derivation | covered | |
| G66 bash-coverage § Denominator counts commands, not source lines | covered | |
| G67 bash-coverage § Denominator is the union of the heuristic and the real trace | covered | |
| G68 bash-coverage § covered > coverable is now a hard exit; publishing the figure | covered | |
| G69 dependency-automation § renovate.json inlines the shared preset | covered | |
| G70 dependency-automation § Renovate confirmed working | covered | |
| G71 dependency-automation § The zero-PR oracle was structurally unfalsifiable | covered | |
| G72 dependency-automation § pip_requirements deliberately absent from enabledManagers | covered | |
| G73 dependency-automation § Dependabot: security auto-PRs off, alerts on | covered | |
| G74 dependency-automation § Dependabot: mechanical details | covered | |
| G75 dependency-automation § Consequence: Python has no automated update path | covered | |
| G76 bats-test-infrastructure § Mock Pattern full reference pointer | wrong: "use this file's own `Mock Pattern` section below rather than looking elsewhere — this heading exists only to receive the pointer" | In `CLAUDE.md`, "this file" is `CLAUDE.md`. There is no Mock Pattern section below this line, because it is the first line of `### Mock Pattern`. The full `MOCK_*` table is not in `CLAUDE.md`: it is in the knowledge file, which the original named. "This heading exists only to receive the pointer" describes the knowledge file's heading, not anything a `CLAUDE.md` reader can see. The line sends the reader away from the table. |
| G77 bats-test-infrastructure § Mock Pattern: pass-through mocks | covered | |
| G78 bats-test-infrastructure § Mock Pattern: env -i strips PATH | covered | |
| G79 bats-test-infrastructure § tests/mocks/curl short-option cluster parsing | covered | |
| G80 bats-test-infrastructure § tests/mocks/curl -o write ordering | missing: "**`-o`'s write is now deferred until after the exit code is decided, and it is a deliberate deviation from real curl.** A simulated failure … leaves a pre-seeded target file completely unchanged" | Round 1 and the authors both missed this (c) item, even though it is what the group's heading names. The rule lines cover only the dual stdout emission. A reader editing the mock is not told that the write must follow the exit decision. |
| G81 bats-test-infrastructure § MAKEFLAGS: --no-print-directory directive | covered | |
| G82 bats-test-infrastructure § MAKEFLAGS: guarded vs measuring test partition | covered | |
| G83 bats-test-infrastructure § MAKEFLAGS: partition enforcement test | covered | |
| G84 bats-test-infrastructure § MAKEFLAGS: known gap | covered | |

### Structure findings

1. **Legend line is correct.** `CLAUDE.md:3` says a trailing `` → `file` § `heading` `` means "before acting on that rule's subject, read `ai-config/docs/knowledge/<file>` at that heading". That matches amendment (b). Its placeholder `file` does not match `_POINTER_RE` (`dotfiles-…`), so the legend is not counted as a pointer: 86 `§` suffixes, 85 pointers.
2. **Test Seams leads: 28 of 29 name the right seam with the right reader.** I checked every function-qualified lead by extracting the function body and grepping it for the variable. All resolve. One is wrong: the G23 lead `` `NTFY_URL`/`NTFY_TOPIC` (`scripts/cadence-notify.sh:_rhn_notify`) `` (`CLAUDE.md:554`). `_rhn_notify` does not read `NTFY_TOPIC`. `_rhn_ntfy_target` (`scripts/cadence-notify.sh:90-96`) is the only reader, and it joins host and topic. Minor: G22's lead cites `cadence.plist.template`, which lives at `LaunchAgents/cadence.plist.template`. G21's lead (`result`/`findings`/`max_age_days`) names heartbeat fields rather than a seam. That fits the group, but the fields are not seams.
3. **No lead labels an INLINE unit.** All eight INLINE units in Test Seams (rustup, `_OVERRIDE_DOCKER_DAEMON_JSON`, `legacy_oracle.bash`, the cadence table, `_CARGO_BIN`, `_RELEASE_BIN_DIR`, `_OVERRIDE_CLAUDE_SETTINGS`, `_OVERRIDE_CLAUDE_PLUGIN_CACHE`) stand as their own paragraphs. Each lead's nested lines end at its own pointer. Round-1 structure findings 1–3 are resolved.
4. **Dangling references in rule lines:**
   - G48 (`CLAUDE.md:676-677`): "this file's existing idiom appends" and "this same file is what puts `brew` on `PATH`". `6_path.zsh` appears in neither line. It was in the rules file's `trigger:`, which the compact pointer dropped. In `CLAUDE.md`, "this file" reads as `CLAUDE.md`.
   - G56 (`CLAUDE.md:285`): "Keep the three-row variable table whole — never split it across a pointer." No such table exists in `CLAUDE.md`. The rule lines replaced it with three bullets, and the table moved.
   - G76 (`CLAUDE.md:606`): "this file's own `Mock Pattern` section below" / "this heading". See the G76 verdict.
5. **Every suffix closes its own group.** For all 85 groups, the pointer suffix sits on the group's last rules-file bullet, and every bullet of the group is within the 8 lines above it (`suffix.py`, 0 mismatches). Each (dest, heading) has exactly one pointer.
6. **Redundant INLINE unit.** `CLAUDE.md:281` (INLINE "`--no-deps` is required — the state being restored is one the resolver refuses.") now repeats G55's second rule line directly above it. The duplicate is harmless, and it resolves round-1's needs-unit on G55. The INLINE record could now be dropped.
7. **Not raised.** These were checked and left alone:
   - `covers:` claims that cite round-1 items verbatim but map to a paraphrase. I judged the paraphrase itself instead.
   - Omitted measurement detail: agent counts, PR numbers and the fixture-hostname rationale. It is narrative, not rule.
   - G40's discovery skips (newline/tab, FIFO): descriptive invariants.
   - G22's "silently unable to run". The original consequence is a false-drift push rather than silence, but the rule (list every dependency on the plist `PATH`) is intact.

### Summary

covered: 71, weakened: 2, missing: 8, wrong: 4

Non-covered: G0 (wrong), G7 (missing), G8 (missing), G18 (missing), G21 (weakened), G39 (missing, borderline), G47 (missing), G50 (wrong), G51 (wrong), G53 (weakened), G59 (missing), G64 (missing), G76 (wrong), G80 (missing). Four of the eight missing verdicts (G7, G39, G59, G80) are (c) items that round 1 and the authors both missed. Round 1 flagged G64's item as a waiver that is really a rule. G8, G18 and G47 lost an (a) sentence containing "must" or its equivalent. Under check 5, all 14 block.
