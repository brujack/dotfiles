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
INLINE | **`_CARGO_BIN` (`install_cargo_tools`, `lib/developer.sh`) i
INLINE | **`_RELEASE_BIN_DIR` (`_install_pinned_release_binary`, `lib
INLINE | `_OVERRIDE_CLAUDE_SETTINGS` points every reader above at a f
INLINE | **`_OVERRIDE_CLAUDE_PLUGIN_CACHE` (`_claude_plugin_cache_dir
INLINE | - **`scripts/sync_git_repos.sh`** replaces the old rsync-onl

WAIVE | The suite's positive control is the mismatch case, which asserts the spy binary **never ran**, not merely that the function returned 1. | narrative: describes what the test's own positive control observes, not a directive
WAIVE | `brew_formula_installed` greps `brew list --formula` in _both_ branches, so an installed **cask** never matches there and the caller would reinstall it on every setup run — an idempotency break, which `code-standards.md` treats as a bug rather than a tradeoff. | narrative: describes a bug mechanism (an idempotency break already named as such), not a directive
WAIVE | Mutation-confirmed: reading the seam under a typo'd name leaves the negative test green and fails only the positive one. | narrative: describes what a mutation-confirmation run showed, not a directive
WAIVE | The seam exists because the only other way to reach either branch is to read — or change — the developer's real account. | narrative: explains why the seam is needed (rationale), not itself a rule
WAIVE | The three pre-existing tests encoded all of it: one asserted only that `chsh` was _called_, never that it succeeded, and the error-path test asserted `status -eq 0`, pinning the swallow. | narrative: describes what pre-existing tests happened to assert, historical
WAIVE | **Two code paths, and the tests only exercise one.** | narrative: describes test coverage as observed (one of two paths exercised)
WAIVE | The hazard runs in both directions and only one was documented until 2026-09-05. | narrative: describes how long a hazard went undocumented, historical
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
MOVE | **The split is real and its consequence to this repo is nil. | dotfiles-conventions.md | Which make an actor resolves (gnubin/actor table)
MOVE | Two traps recorded from those retirements, because both cost | dotfiles-conventions.md | Which make an actor resolves (gnubin/actor table)
MOVE | - **`/usr/local/bin` reaches none of the non-interactive act | dotfiles-conventions.md | setup_env.sh cannot run non-interactively on the Linux workstation (brew PATH)
MOVE | - **`setup_env.sh` cannot run non-interactively on the Linux | dotfiles-conventions.md | setup_env.sh cannot run non-interactively on the Linux workstation (brew PATH)
MOVE | A non-interactive invocation dies in seconds with `[ERROR] H | dotfiles-conventions.md | setup_env.sh cannot run non-interactively on the Linux workstation (brew PATH)
MOVE | The macOS bullet above and this one are the same defect at t | dotfiles-conventions.md | setup_env.sh cannot run non-interactively on the Linux workstation (brew PATH)
MOVE | - **`install_cargo_tools` (`lib/developer.sh`) judges each ` | dotfiles-conventions.md | install_cargo_tools judges by runnability, not version string
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
MOVE | `--no-deps` is required — the state being restored is one th | dotfiles-testing-toolchain.md | Ansible venv snapshot before every sync (uv sync prune/downgrade, rollback)
MOVE | **Environment overrides added by the uv work.** All three ex | dotfiles-testing-toolchain.md | Environment overrides added by the uv work (UV_BIN, UV_FALLBACK_PATHS, REQUIREMENTS_CI_TARGET)
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

BASELINE rule_sentences=155 floor=91112

## Notes

**Span semantics.** Built under the orchestrator's mid-task correction: a SECTION's span is
its heading line through the line before the next heading of **any** level (body only), not
"next heading of level <= this one's" (the pre-fix `find_heading_span` behaviour, which would
have made `## Testing` swallow ShellCheck/CI/Testing Rules/PowerShell/Coverage/Test
Seams/Mock Pattern/MAKEFLAGS). Most of this map's unit inventory and grouping decisions were
made before the fix landed, using a throwaway body-only-span implementation
(`/tmp/claude-1000/scratch/measure_body.py`, mirroring
`analyze_sections`/`compute_floor`/`non_moving_bytes_for` exactly, substituting only
`find_heading_span`) rather than trusting the then-unpatched script's own (inflated,
double-counting) output. `21d39bfa` ("fix(relocation): body-only SECTION spans, line match")
landed before this map was committed. Re-run against the real, now-fixed tool:

```
python3 scripts/relocation_check.py measure --pre-rev 2e38f5e4 \
  --map docs/superpowers/plans/2026-09-25-relocation-map.md
```

Output: `units=195 rule_sentences=155 rule_bytes=37469 floor=91112` — byte-for-byte identical
to the throwaway script's number, which is the BASELINE line below. The two independent
implementations agreeing is what makes 91112 trustworthy, not either one alone.

**Every anchor was verified against the whole-document unit list**
(`/tmp/claude-1000/scratch/verify_map.py`), not eyeballed: all 173 MOVE anchors and all 8
INLINE anchors resolve to **exactly one** unit each among the 326 units `extract_units()`
finds in the whole `2e38f5e4:CLAUDE.md` (not just the 7 moving sections) — confirming
check4's first-match-in-document-order search targets the intended unit for every record.

**Two anchors are longer than 60 normalised characters, deliberately.** Test Seams unit 0
("See `.../dotfiles-bats-test-infrastructure.md` for the full override env var...") and Mock
Pattern unit 0 ("See `.../dotfiles-bats-test-infrastructure.md` for the full `MOCK_\*` env
var...") are identical for their first 102 normalised characters and diverge only at byte 103. Both anchors are extended to 115 chars so `startswith` resolves each to its own unit; the
map format is "prefix-matched", and 60 is the _default_ length, not a hard requirement, so
this is not a deviation from the format, only from the default length.

**Four units cannot be expressed as an INLINE or MOVE record at all: their normalised text
begins, within the first 60 (or, for the two disambiguated anchors above, 115) characters,
with the literal substring `" | "`, which is the map's own field delimiter.** `parse_map` splits every fenced-block line
on `" | "`, so an anchor containing it makes the record parse as more fields than the record
type allows, and `measure`/`check` exit 1 on a `MapError` before any check runs. There is no
escape mechanism in the parser and no way to shorten the anchor below the delimiter's first
occurrence without colliding with an unrelated unit that shares the same header row (see
below) — this is a genuine format/content collision, not a mistake in this map, and it cannot
be fixed from the map side. The four affected units, all markdown tables:

- `### Test Seams` unit index 43 (the cadence seams table, `_RHN_*`/`_OVERRIDE_DOTFILES_ROOT`/
  etc.) — **this one is in the plan's mandatory Inline-whole list** ("the cadence seam
  table", one of the 5 `E2`-token units named in the spec). It cannot be added as an `INLINE`
  record, so `analyze_sections` treats it as an ordinary (non-inline) unit: its rule-matching
  fragments (5 sentences, 2532 of its 10043 raw bytes, several containing stray `|`
  characters from table-cell boundaries the sentence splitter cannot see) land in
  `retained_sentences` and are counted toward the floor; the remaining **7511 bytes are not
  counted anywhere**, even though the plan requires this table to stay whole in `CLAUDE.md`.
  That is close to the entire 8000-byte slack on its own. **Task 4 must keep this table
  exactly where it is** (do not attempt to move it) and should expect `check3` to need
  compensating savings elsewhere if it comes in tight; this map cannot verify the table's
  placement mechanically. Reviewer note for Task 5: this is a "cannot express" case, not a
  "chose not to inline" case.
- `## Testing` unit index 18 (the uv seams table: `UV_BIN`/`UV_FALLBACK_PATHS`/
  `REQUIREMENTS_CI_TARGET`) and unit index 21 (the five-renderings table) — **not** in the
  mandatory Inline-whole list, so Task 4 may relocate these to `dotfiles-testing-toolchain.md`
  by hand; `check1` will still pass (it matches on content present anywhere in the
  destination directory, independent of any MOVE record), just without this map's per-heading
  verification for these two specific units.
- `## Key Conventions` unit index 29 (the actor/`PATH`-source/resolves/version table) —
  likewise not mandatory-inline; Task 4 may relocate it to `dotfiles-conventions.md` by hand,
  same caveat.

Both `## Testing` unit 18 and unit 43 in Test Seams begin with the _identical_ header row
(`| variable | read by | why it exists |`), so even if the pipe collision did not exist, a
60-char anchor would not disambiguate them; this is a second, independent reason a short
prefix cannot serve these units.

**Units left with no map record at all — neither INLINE, MOVE, nor WAIVE — are units this
map decided should simply stay where they are, untouched, relying on the 8000-byte slack
rather than on explicit floor credit:**

- `## Key Conventions` unit indices 0, 4-13 (11 short factual/procedural bullets: machine
  roles pointer, legacy hostname var list, Ubuntu version detection, credential dir chmod,
  git-repos clone paths, pyenv/pyenv-virtualenv note, ansible venv packages, ruff venv-managed,
  pytest runner, alphabetical installs, `bash -n` validation) — none of these read as
  "narrative" under the spec's Destinations row (which names specific topics: git-hooks sweep,
  core.hooksPath, gnubin/actor table, linuxbrew non-interactive, zsh-autosuggestions, summary
  width, cheat.sh, Warp, tfenv, cargo-tools, NVIDIA), and each is short enough (53-442 raw
  bytes, ~2500 bytes total) that leaving them untouched costs a small, bounded slice of the
  slack rather than a modeled INLINE credit.
- `## Testing` unit indices 0-4, 11, 14 (BATS install dispatcher references, the `make
test-unit`/`make lint` command list, the `make install-hooks`/`sync-agent-guidance`/
  `check-agent-guidance` command list) — these are command references, not narrative, and are
  outside the Destinations row's named list (uv/renderings, requirements groups, hook
  internals, `phrase_check`).

If Task 4 finds these do not fit the remaining slack once the rest of the section is
compressed, treat that as a real finding (per the plan's "stop and report" clause), not as
license to silently WAIVE a genuine rule sentence to compensate.

**Waiver count is 14, under the 15-waiver stop threshold**, and every one is a keyword match
on narrative/historical/incidental text (a test's own observed behaviour, a retracted claim
quoted from an earlier draft, or `\bverify\b` matching inside the CLI flag `--no-verify`),
per-sentence reasons given inline in the fence. 155 rule sentences remain retained after
waiving.

**Command used for gate 1**, run against the actual (possibly still-unpatched) checker:

```
python3 scripts/relocation_check.py measure --pre-rev 2e38f5e4 \
  --map docs/superpowers/plans/2026-09-25-relocation-map.md
```

If the checker has landed its SECTION-span fix by the time this is read, re-run the command
above and compare its printed `floor=` against the BASELINE line; they should agree, since
both use body-only spans over the same 7 SECTION headings, INLINE anchors, and WAIVE
sentences. A genuine disagreement means either this map's manual computation or the fixed
checker has a bug — resolve before trusting either number.
