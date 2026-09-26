# Rule bullets — dotfiles-test-seams.md

One entry per MOVE group (G0–G35), per the 2026-09-25 relocation re-plan Task 8.

### Test seam idiom and override pattern

lead: none

- A test seam is a variable with a production default — `local _file="${VAR:-<real path>}"` — not a naming rule: seams below are named `_RUSTUP_INIT_*`, `GGSHIELD_BIN`, `LEDGER_BIN`, `_AWS_*`, `_RHN_*`, `_CARGO_BIN`, and more.
- In tests, set the seam variable to a writable temp copy; leave it unset in production code.
  trigger: adding a new test seam | `lib/*.sh`, `scripts/*`, `.config/.zshrc.d/*.zsh`
  covers:
  - a: "Pattern: `local _file=\"${_OVERRIDE_VAR:-$(dirname \"${"
  - b: "Tests set the var and pass a writable temp copy; produ"

### Rustup signature verification seams (_RUSTUP_INIT_URL / _RUSTUP_INIT_SHA256 / _RUSTUP_INIT_BIN / _OVERRIDE_CARGO_BIN_DIR)

lead: `_RUSTUP_INIT_SHA256` (`lib/linux_ubuntu.sh:_install_rustup_rs`)

- Never mock `sha256sum`; supply the real digest via `_RUSTUP_INIT_SHA256` so a mismatch is genuinely exercised in both directions.
- `tests/mocks/curl` never fetches — it writes `MOCK_CURL_STDOUT` to the `-o` target (or touches it when unset); compute the success-path digest over `MOCK_CURL_STDOUT`'s exact bytes, never a separate fixture file the mock never copies.
  trigger: writing a rustup install or signature-verification test | `lib/linux_ubuntu.sh`, `tests/mocks/curl`
  covers:
  - a: "There is no `sha256sum` mock and there must not be one"
  - a: "A digest taken over a separate fixture file the mock nev"
  - b: "A digest taken over a separate fixture file the mock nev" (needs unit: "the mock" = `tests/mocks/curl`)

### NVIDIA GPU detection seams (_OVERRIDE_NVIDIA_GPU_PRESENT / _OVERRIDE_NVIDIA_KEYRING / _OVERRIDE_NVIDIA_LIST)

lead: `_OVERRIDE_NVIDIA_GPU_PRESENT` (`lib/linux_ubuntu.sh:_nvidia_gpu_present`, `_install_ubuntu_nvidia`)

- `lspci` is never mocked; `_OVERRIDE_NVIDIA_GPU_PRESENT` is what makes both the install and skip branches testable on a machine with no NVIDIA card.
- Point `_OVERRIDE_NVIDIA_KEYRING`/`_OVERRIDE_NVIDIA_LIST` at fixtures so no test ever writes to the real `/usr/share/keyrings` or `/etc/apt/sources.list.d`.
  trigger: testing NVIDIA driver or container-toolkit install | `lib/linux_ubuntu.sh`
  covers:
  - a: "`lspci` is **not** mocked, and the suite runs on a machi"
  - b: "The other two redirect the keyring and apt source list a"

### brew_install_cask / brew_cask_installed seam

lead: `brew_install_cask`/`brew_cask_installed` (`lib/helpers.sh`)

- Use `brew_install_cask`/`brew_cask_installed` for a Cask, never `brew_formula_installed` — it greps `brew list --formula` in both branches, never matches an installed cask, and the caller reinstalls it every run.
  trigger: installing or testing a Homebrew Cask | `lib/helpers.sh`
  covers:
  - a: "" (lead retained with no body)
  - b: "are a separate pair from the formula helpers, deliberate"

### config/profiles.zsh and the legacy identity oracle

lead: none

- `config/profiles.zsh` and `lib/detect_env.sh` must derive `PROFILE`/`HAS_*`/all eight legacy identity vars from the same `config/profiles.sh` table; `tests/zshrc.d/cross_shell.bats` asserts both shells agree on every table key.
- `tests/helpers/legacy_oracle.bash` must stay hand-typed, never derived from `PROFILE_LEGACY` — a derived oracle would agree with a mis-mapped table entry and pass silently.
  trigger: adding a machine, or editing the legacy-variable derivation | `config/profiles.sh`, `config/profiles.zsh`, `lib/detect_env.sh`, `tests/helpers/legacy_oracle.bash`
  covers:
  - a: "is the single zsh-side derivation of `PROFILE`, `HAS_*`,"
  - a: "derives the identical eight variables on the bash side"

### config/profiles.zsh export vs lib/detect_env.sh readonly

lead: none

- `config/profiles.zsh` must use `export`, never `readonly` — it is sourced twice per login+interactive shell, and a `readonly` reassignment on the second source makes that `source` return 126, silently degrading shell identity.
- `lib/detect_env.sh`'s `detect_env()` runs exactly once per bash process, so `readonly` there is correct; do not "fix" one file to match the other.
  trigger: changing a scope modifier in `config/profiles.zsh` or `lib/detect_env.sh`
  covers:
  - a: "" (lead retained with no body)
  - b: "deliberate, not drift, and a future reader will otherwis"

### _OVERRIDE_HOMEBREW_PREFIX_ARM / _OVERRIDE_HOMEBREW_PREFIX_INTEL seam

lead: `_OVERRIDE_HOMEBREW_PREFIX_ARM`/`_OVERRIDE_HOMEBREW_PREFIX_INTEL` (`.config/.zshrc.d/5_general.zsh`)

- Drive both "present" and "absent" through the override, never through the real filesystem — both real prefixes (`/opt/homebrew`, `/usr/local/opt`) exist on any provisioned mac, so an unset override short-circuits the guard and asserts nothing.
  trigger: testing `CHRUBY_LOC`/`FZF_BASE`/keychain-path resolution | `.config/.zshrc.d/5_general.zsh`
  covers:
  - a: "replace the hostname-keyed branches that used to stand i"

### _OVERRIDE_KEYCHAIN_BIN seam and the interactive guard

lead: `_OVERRIDE_KEYCHAIN_BIN` (`.config/.zshrc.d/5_general.zsh`)

- `_OVERRIDE_KEYCHAIN_BIN` exists because keychain's real path is absolute and unmockable via `PATH`; without it, an absent-branch test only fails where keychain is actually installed.
- Keep `"${_keychain}" --eval …` quoted — a default (zsh doesn't word-split unquoted params), not a guarantee, since `emulate sh`/`ksh` re-enable `SH_WORD_SPLIT`. Keep the block wrapped in `[[ -o interactive ]]`: sourcing it non-interactively starts a daemonizing `ssh-agent` that holds the bats pipe and hangs `make test` (measured: 16/run, 161 accumulated).
- Leave every `[[ ${VAR} ]]` test here unquoted — `[[ ]]` suppresses splitting regardless of `SH_WORD_SPLIT`; quoting them is churn (command vs. test position, not a style rule). `tests/zshrc.d/unit.bats` must keep `setopt shwordsplit`, or the quoting assertion above is vacuous.
- The non-interactive (zero calls) and interactive (seam read) tests are a pair; neither alone catches a typo'd seam name.
  trigger: editing `_OVERRIDE_KEYCHAIN_BIN` or the keychain block | `.config/.zshrc.d/5_general.zsh`, `tests/zshrc.d/unit.bats`
  covers:
  - a: "selects the `keychain` binary, defaulting to"
  - a: "The expansion is quoted"
  - b: "It is quoted anyway because that safety is a default"
  - b: "The block it guards is wrapped in `[[ -o interactive ]]`"
  - c: "The `[[ ${VAR} ]]` tests throughout this file are delibe"
  - c: "without that option the quoted and unquoted forms are in"
  - b: "Measured 2026-08-16 on the Linux workstation: 16 agents" (needs unit)

### _OVERRIDE_CURRENT_LOGIN_SHELL seam and the chsh guard

lead: `_OVERRIDE_CURRENT_LOGIN_SHELL` (`lib/helpers.sh:_current_login_shell`)

- Derive login shell from `getent passwd`/`dscl UserShell`, never `${SHELL}` — `${SHELL}` names the running shell, not the account's, so a provision started from zsh can misread a `/bin/bash` account as already-zsh.
- Tests must set `_OVERRIDE_CURRENT_LOGIN_SHELL`: without it they pass on a mac already on zsh and fail on any runner whose account is `/bin/bash` — a machine-dependent pass, not a code-dependent one.
- Check both `chsh`'s and `sudo -n chsh`'s exit codes rather than logging "Changed default shell" unconditionally — `chsh` authenticates via PAM and exits 1 non-interactively, so an unchecked rc reports success over an unchanged shell.
- The end-to-end `run_doctor` tests stub every sub-check by name; stub `_doctor_check_login_shell` there too, or it reads the real account mid-suite.
  trigger: editing `setup_zsh_as_default_shell` or `_doctor_check_login_shell` | `lib/helpers.sh`
  covers:
  - a: "supplies the ACCOUNT's login shell"
  - a: "`chsh` is why the rest of that function changed"
  - a: "the three end-to-end `run_doctor` tests stub every sub-c"
  - b: "deliberately **not** `${SHELL}`, which names whichever s"
  - b: "It is not optional in tests: without it they pass on"

### _OVERRIDE_GNUBIN_ARM / _OVERRIDE_GNUBIN_INTEL seam

lead: `_OVERRIDE_GNUBIN_ARM`/`_OVERRIDE_GNUBIN_INTEL` (`lib/macos.sh:install_make_macos`, `.config/.zshrc.d/6_path.zsh`)

- Keep the ARM/Intel default pair (`/opt/homebrew/opt/make/libexec/gnubin`, `/usr/local/opt/make/libexec/gnubin`) identical in `install_make_macos` and `6_path.zsh` — a drift makes the install guard and the `PATH` consumer disagree.
- Tests must set the override to a nonexistent path to reach the absent branch — the real ARM gnubin dir exists on any provisioned mac and an unset override asserts nothing.
  trigger: editing GNU `make` PATH resolution | `lib/macos.sh`, `.config/.zshrc.d/6_path.zsh`, `tests/setup_env/install_guards.bats`
  covers:
  - a: "are read by two files in two languages"
  - b: "keep the pairs in step, since a drift makes the install"
  - b: "The seam is not optional in tests: the real ARM gnubin d"

### _OVERRIDE_GNUBIN_LINUX seam

lead: `_OVERRIDE_GNUBIN_LINUX` (`.config/.zshrc.d/6_path.zsh`, `lib/helpers.sh:_doctor_check_gnu_coreutils`)

- Tests must set `_OVERRIDE_GNUBIN_LINUX` to a nonexistent path to reach the absent branch — the real linuxbrew coreutils gnubin dir exists on any `claude`-class box and an unset override short-circuits the `-d` guard.
- Keep the default identical in both readers and assert they stay equal, or the doctor diagnosis and the shell's actual `PATH` disagree about what "the gnubin directory" means.
  trigger: editing Linux coreutils PATH resolution | `.config/.zshrc.d/6_path.zsh`, `lib/helpers.sh`
  covers:
  - a: "is the same pattern one platform and one tool over"
  - b: "That directory is real on any `claude`-class box once th"

### _OVERRIDE_DOCKER_BIN seam

lead: `_OVERRIDE_DOCKER_BIN` (`.config/.zshrc.d/6_path.zsh`)

- Point `tests/zshrc.d/unit.bats` at `/nonexistent/docker-bin` to reach the absent branch — the real `${HOME}/.docker/bin` exists on any mac running Docker Desktop.
- If Docker Desktop's installer re-adds its `.zprofile` PATH lines, delete them rather than committing them — the entry belongs only in the interactive `6_path.zsh` block.
  trigger: editing Docker CLI PATH resolution | `.config/.zshrc.d/6_path.zsh`, `.zprofile`
  covers:
  - a: "selects Docker Desktop's CLI directory, defaulting to"
  - b: "If the installer's `.zprofile` lines reappear, delete th"

### GGSHIELD_BIN / GGSHIELD_FALLBACK_PATHS seams

lead: `GGSHIELD_BIN`/`GGSHIELD_FALLBACK_PATHS` (`scripts/pre-commit-hook.sh`)

- Drive ggshield absence only through `GGSHIELD_BIN`/`GGSHIELD_FALLBACK_PATHS`, never by editing `PATH` — stripping the directory holding ggshield also removes `git`/`make` from that same directory.
- A non-executable `GGSHIELD_BIN` is a hard error, not a silent degrade.
  trigger: editing ggshield resolution in the pre-commit hook | `scripts/pre-commit-hook.sh`
  covers:
  - a: "exist for the same reason, one tool over"
  - a: "Tests must drive absence through these seams and never b"

### LEDGER_BIN seam

lead: `LEDGER_BIN` (`lib/workflows.sh:ledger_write_entry`)

- Always prepend `tests/mocks/ledger` to `PATH`; a `HOME`-only redirect cannot force resolution to a fixture, because `command -v ledger` runs before the `${HOME}/.local/bin/ledger` fallback and wins on any machine (`workstation`/`claude`) that already has a real `ledger` on `PATH`.
  trigger: testing `ledger_write_entry` or any ledger-writing code | `lib/workflows.sh`
  covers:
  - a: "is checked before `command -v ledger`, and `tests/mocks/"

### _OVERRIDE_LIB_TRAP_SCOPE seam

lead: `_OVERRIDE_LIB_TRAP_SCOPE` (`scripts/check-lib-exit-traps.sh`)

- Under the override the scope is a plain glob (`<root>/lib/*.sh`); in the real repo it is `git ls-files 'lib/*.sh'` under the four-variable `env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE` strip — a fixture-only suite never exercises the git path CI and the pre-push hook actually run.
- Keep the one test that runs with no override against the real `lib/` and the real allowlist, asserting the scanned set is non-empty — without it, nothing in the suite touches the path production actually takes.
  trigger: editing the EXIT-trap scope resolution | `scripts/check-lib-exit-traps.sh`
  covers:
  - a: "points the EXIT-trap ratchet's scope at a fixture root"
  - b: "Two code paths, and the tests only exercise one." (needs unit: "That is what lets the suite drive every verdict")
  - b: "The one test that closes it is"

### _OVERRIDE_BATS_BIN seam

lead: `_OVERRIDE_BATS_BIN` (`scripts/run-bash-coverage.sh`)

- Drive bats absence only through `_OVERRIDE_BATS_BIN`, never by editing `PATH` — on `ubuntu-latest`, bats shares a directory with bash/grep/sed/mktemp, so removing that directory removes the toolchain, not just bats.
- Both halves of a seam (test and production) must land in the same commit; reproduce a suspected CI-only failure from `git archive <the sha CI ran>`, never a dirty working tree — a `git stash create` snapshot can silently include a seam CI never had.
  trigger: adding a run-bash-coverage seam, or reproducing a CI-only failure | `scripts/run-bash-coverage.sh`
  covers:
  - a: "exists because a `PATH` strip cannot remove bats on the"
  - b: "When reproducing a CI failure elsewhere, ship `git archi"

### _OVERRIDE_RUN_TMPDIR_ROOT seam

lead: `_OVERRIDE_RUN_TMPDIR_ROOT` (`lib/workflows.sh:_dotfiles_run_tmpdir_setup`)

- `_OVERRIDE_RUN_TMPDIR_ROOT` is read unconditionally in production, the same shape as `_OVERRIDE_GNUBIN_ARM`/`_INTEL` — it exists because bats leaves `TMPDIR` pointed at the real system temp dir, so `TMPDIR` alone cannot isolate the `mktemp -d ... || return 1` error path.
  trigger: testing `_dotfiles_run_tmpdir_setup`'s mktemp failure path | `lib/workflows.sh`
  covers:
  - a: "is read at exactly one site, `lib/workflows.sh:106`"

### _PROFILES_LOADED sentinel

lead: `_PROFILES_LOADED` (`lib/detect_env.sh:detect_env`, `lib/helpers.sh`)

- `detect_env()` must set `_PROFILES_LOADED=0` unconditionally on entry, `1` only after `config/profiles.sh` sources cleanly and all three arrays exist — never derive the check from `PROFILE` alone, since `config/profiles.zsh` exports it into child shells and a stale value survives a failed load.
- Never trust an environment-supplied `_PROFILES_LOADED=1` unexamined — the unconditional reset plus `detect_env()` always running before `run_doctor` is what protects it, not the variable being unexported.
  trigger: editing profile-load failure detection | `lib/detect_env.sh`, `lib/helpers.sh`
  covers:
  - a: "is a sentinel that records whether the identity table lo"

### _AWS_GPG_BIN / _AWS_PKGUTIL_BIN / _AWS_KEY_PATH seams

lead: `_AWS_GPG_BIN`/`_AWS_PKGUTIL_BIN`/`_AWS_KEY_PATH` (`lib/developer.sh:_aws_verify_zip`/`_aws_verify_pkg`, `lib/helpers.sh:_doctor_check_aws_key_expiry`)

- Resolve `_AWS_GPG_BIN`/`_AWS_PKGUTIL_BIN` via `command -v`, never by stripping `PATH` — stripping `/opt/homebrew/bin` or `/usr/sbin` removes the rest of the toolchain those dirs hold.
- `_AWS_KEY_PATH` defaults via `DOTFILES_REPO_ROOT`, resolved at **source time** in `lib/constants.sh` as a **plain assignment**, never a `${VAR:-}` self-guard — tried and retired, since a guard only adds an env-settable name selecting where a trust anchor is read from. Never re-derive the expression inline as `$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)`, which returns empty once the caller (e.g. `update_aws_cli`) has already `cd`'d elsewhere.
- An absolute-path suite (bats' `load_setup_env`) can't exercise this cwd-sensitivity; regression tests must `source ./lib/...` relatively, `cd` away, then assert on the **post-import failure message** — never on absence (tdd.md E5), which an unrelated skip satisfies equally.
  trigger: editing AWS CLI signature verification or its key path | `lib/developer.sh`, `lib/helpers.sh`, `lib/constants.sh`
  covers:
  - a: "exist for the same absolute-toolchain reason as"
  - a: "It is a plain assignment rather than a `${VAR:-}` self-gu"
  - a: "assert on the **post-import** failure"
  - b: "`DOTFILES_REPO_ROOT` resolves the same expression at **s" (needs unit: "the same expression" = the cd/dirname derivation)

### _AWS_BIN seam

lead: `_AWS_BIN` (`lib/developer.sh:install_aws_tools`)

- Set `_AWS_BIN` in every `install_aws_tools` test on this machine — a real `aws` exists at `/usr/local/bin/aws`, so without the seam the already-installed guard is always taken and the install path is never asserted.
  trigger: testing `install_aws_tools` | `lib/developer.sh`
  covers:
  - a: "is load-bearing on this development machine specifically"
  - b: "This machine has a real `aws` at `/usr/local/bin/aws`, so"

### Cadence seams overview (scripts/cadence-notify.sh, lib/launch_agents.sh)

lead: none

- Every cadence seam exists because the delivery arm and the LaunchAgent installer resolve absolute paths and external binaries that a `PATH` mock cannot reach; none grants a capability beyond what editing `PATH` or the plist directly would already grant.
  trigger: adding a new cadence detector or LaunchAgent | `scripts/cadence-notify.sh`, `lib/launch_agents.sh`
  covers:
  - a: "see ADR-0024, and ADR-0026 for the two-stream detector co"

### Cadence heartbeat contract

lead: `result`/`findings`/`max_age_days` (`scripts/cadence-notify.sh`, `lib/launch_agents.sh:_doctor_check_cadence`)

- Write `max_age_days` into the heartbeat; when a heartbeat carries none, the reader falls back to its own default (8) and must **name its source** (`from heartbeat` vs `default`), so a fallback is never mistaken for a reading. Render `held`/`incomplete`/`clean`/`pending` as pairwise-unequal states — `pending` is seeded at install (not a grace period), absent means "not installed", and a reinstall must never clobber a real heartbeat.
- stdout carries findings one per line and nothing else; a stray status/banner line silently over-reports (measured: a clean fleet reporting `"findings": 1`) — check what else the detector writes to stdout before trusting a count. stderr carries the diagnosis, capped at 20 lines and POSTed to ntfy, so never print credentials or env dumps there.
- Keep heartbeat fields closed-form via `printf`; never add a free-text field or shell out to `python3 -c json.dumps` — free text breaks the `sed`/`json.loads` readers, and a python3 dependency would take down both sides of the one liveness channel.
  trigger: writing or changing a cadence detector's stdout/heartbeat contract | `scripts/cadence-notify.sh`, `lib/launch_agents.sh`
  covers:
  - a: "`max_age_days` is written, not mirrored."
  - a: "prefers the written value and **names its source**"
  - a: "`pending` is a state, not a grace period."
  - a: "`held` is a finding, not a fault."
  - a: "`findings` is a count of stdout lines"
  - b: "Before believing a count, ask what else the detector writ"
  - b: "Every value is closed-form on purpose."
  - b: "The second is the damaging one" (needs unit)

### Cadence agent PATH and plist rendering

lead: `PATH` (`LaunchAgents/cadence.plist.template`, `lib/launch_agents.sh`)

- Every detector dependency must be listed in the plist's `PATH` (`__HOME__/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin`) — launchd sources no profile, so an absent tool (e.g. `ledger`, in the first entry) makes the agent silently unable to run.
- Resolve a new detector's dependencies under that exact `PATH` (`env -i PATH=<the plist PATH> bash -c 'command -v <tool>'`), never under an interactive shell, which answers for a different actor.
- A template edit does not reach an installed agent — the live `~/Library/LaunchAgents/*.plist` is a rendered copy from install time. Re-run `setup_env.sh -t setup_user`, then verify the **live** file (`grep -A1 '<key>PATH</key>' <plist>`), not the template.
  trigger: editing `LaunchAgents/cadence.plist.template` or adding a cadence detector | `lib/launch_agents.sh`, `LaunchAgents/cadence.plist.template`
  covers:
  - a: "The plist's `PATH` is the agent's whole world"
  - a: "`tests/setup_env/launch_agents.bats` guards the property"
  - a: "A plist change does not reach a running agent"
  - b: "When wiring a new detector, resolve its dependencies unde"
  - b: "`ledger` lives in that first entry" (needs unit)
  - b: "Verify the live file rather than the template after any" (needs unit)

### Cadence ntfy delivery and heartbeat rationale

lead: `NTFY_URL`/`NTFY_TOPIC` (`scripts/cadence-notify.sh:_rhn_ntfy_target`)

- ntfy needs both a topic and credentials — POSTing bare `${NTFY_URL}` (host only) cannot deliver; always POST to `${NTFY_URL}/${NTFY_TOPIC}` with auth.
- Send credentials on **stdin** via `curl -K -`, never `-u` (argv is readable by `ps`), and refuse (never escape) a credential containing a newline — curl's config is line-oriented and reads past a break as a further directive.
- Keep the heartbeat as a second, silent-when-clean channel; wrap the detector call in `env -u NTFY_URL` so delivery failure and detection failure never collapse into one "no drift" signal.
  trigger: adding or editing an ntfy-delivering detector | `scripts/cadence-notify.sh`, `lib/launch_agents.sh`
  covers:
  - a: "Credentials go in on **stdin** via `curl -K -`"
  - a: "The heartbeat is a second channel, deliberately."
  - a: "`install_ledger_drift_agent` makes that deferral true"
  - b: "ntfy needs a topic and credentials, and neither is optio"

### Pyenv-rehash and cargo-tools seams overview

lead: none

- This group covers the pyenv shim defect and the cargo plugin repair added 2026-09-17; treat each seam below individually, not as one combined pyenv/cargo unit.
  trigger: touching a pyenv-shim or cargo-tools test seam | `lib/helpers.sh`, `lib/developer.sh`, `lib/workflows.sh`
  covers:
  - a: "the pyenv shim defect and the cargo plugin repair added"

### _OVERRIDE_PYENV_ROOT seam

lead: `_OVERRIDE_PYENV_ROOT` (`lib/helpers.sh:_pyenv_ansible_venv_bin`, `install_pyenv_rehash_hook`; `lib/workflows.sh` pyenv-shims section)

- Set `_OVERRIDE_PYENV_ROOT` explicitly in every test touching shim counting or the hook install — a `HOME`-only redirect cannot isolate these functions, because `PYENV_ROOT` (exported by pyenv's own `init` into every interactive shell) is checked before the `HOME` fallback and would outrank a fixture `HOME`.
  trigger: testing pyenv shim counting or `install_pyenv_rehash_hook` | `lib/helpers.sh`, `lib/workflows.sh`
  covers:
  - a: "is read by `_pyenv_ansible_venv_bin` and `install_pyenv_r"
  - b: "The seam exists precisely to remove that ordering hazard"

### _RELEASE_TMP_ROOT seam

lead: `_RELEASE_TMP_ROOT` (`lib/linux_ubuntu.sh:_install_pinned_release_binary`)

- Set `_RELEASE_TMP_ROOT` when asserting the failure-path cleanup of `_install_pinned_release_binary` — BSD `mktemp -d` with a template argument ignores `TMPDIR` entirely, and the Studio's `mktemp` is BSD, so a `TMPDIR`-based assertion is silently inert there (same fix as `_OVERRIDE_RUN_TMPDIR_ROOT`).
  trigger: testing `_install_pinned_release_binary`'s temp-dir cleanup | `lib/linux_ubuntu.sh`
  covers:
  - a: "exists because BSD `mktemp -d` with a template argument"
  - b: "a `TMPDIR`-based assertion of the failure-path cleanup wo"

### _TFLINT_URL / _TFLINT_SHA256 / _TFSEC_URL / _TFSEC_SHA256 seams

lead: `_TFLINT_URL`/`_TFLINT_SHA256`/`_TFSEC_URL`/`_TFSEC_SHA256` (`lib/linux_ubuntu.sh:_install_ubuntu_tflint`/`_install_ubuntu_tfsec`)

- Drive `_install_pinned_release_binary` with a local fixture URL and a deliberately wrong checksum via these four vars; never mock `sha256sum` itself, mirroring the rustup rule — mocking it would make every mismatch case vacuous.
  trigger: testing tflint/tfsec install or checksum mismatch | `lib/linux_ubuntu.sh`
  covers:
  - a: "let a test drive `_install_pinned_release_binary` against"

### _TFENV_ROOT / _TFENV_REPO_URL seams

lead: `_TFENV_ROOT`/`_TFENV_REPO_URL` (`lib/linux_ubuntu.sh:_install_ubuntu_tfenv`)

- Isolate the clone target from a real `~/.tfenv` with `_TFENV_ROOT`, and drive the clone-failure branch (bad/unreachable URL) with `_TFENV_REPO_URL` — never a real network call.
  trigger: testing `_install_ubuntu_tfenv` | `lib/linux_ubuntu.sh`
  covers:
  - a: "isolates the clone target from a real `~/.tfenv`"

### _PWSH_BIN / _PWSH_PROBE_TIMEOUT seams

lead: `_PWSH_BIN`/`_PWSH_PROBE_TIMEOUT` (`lib/linux_ubuntu.sh:_pwsh_probe_runs`)

- Drive all three pwsh states — working, installed-but-broken, not-installed — through `_PWSH_BIN`, since `_pwsh_probe_runs` tests that `pwsh` actually _runs_, not merely that a `.deb` was downloaded.
- Test the `timeout`-absent fallback with a `PATH` scoped to a directory holding no `timeout` **and** an absolute `#!/bin/bash`-shebang stub (`#!/usr/bin/env bash` exits 127 there, since `env` must resolve `bash` through the same scoped `PATH`); cover both directions — a one-sided test passes vacuously under the opposite mutation.
  trigger: testing `_pwsh_probe_runs` or its `timeout` fallback | `lib/linux_ubuntu.sh`
  covers:
  - a: "are both read by `_pwsh_probe_runs`"
  - b: "The `timeout`-absent fallback inside that helper needs it"
  - b: "Reaching it requires a PATH scoped to a directory holdin" (needs unit)
  - b: "The pair must cover both directions"

### _DOCTOR_PROBE_TIMEOUT seam

lead: `_DOCTOR_PROBE_TIMEOUT` (`lib/helpers.sh:_doctor_check_dev_tools`)

- Drive the timeout branch with a stub that sleeps under `_DOCTOR_PROBE_TIMEOUT=1`; never wait on the real 10-second default to prove a hung version probe doesn't block doctor.
  trigger: testing `_doctor_check_dev_tools`'s timeout handling | `lib/helpers.sh`
  covers:
  - a: "overrides the `timeout` bound each tool's version probe r"

### _CRATES_API seam

lead: `_CRATES_API` (`lib/workflows.sh:_check_one_cargo_version`)

- Override `_CRATES_API` (default `https://crates.io/api/v1/crates`) for any test of `CARGO_TOOLS` staleness that must exercise an unreachable crates.io, mirroring the tflint/tfsec URL-override pattern.
  trigger: testing `_check_one_cargo_version` | `lib/workflows.sh`
  covers:
  - a: "overrides the crates.io API base the `CARGO_TOOLS` stalen"

### Claude plugin provisioning seams overview

lead: none

- `_OVERRIDE_CLAUDE_SETTINGS`, `_CLAUDE_GUARD_GIT` and `tests/mocks/claude` together isolate every one of `_claude_settings_path`, `_claude_plugin_manifest`, `_claude_registered_marketplaces`, `_claude_installed_user_ids`, `_claude_settings_git_state`, `_claude_settings_guard_check`, `_claude_manifest_split_line`, `setup_claude_plugins` and `provision_claude_plugins` from the real `${HOME}/.claude/settings.json` and the real `claude`/`git` binaries.
  trigger: editing any Claude-plugin-provisioning function | `lib/workflows.sh`
  covers:
  - a: "`lib/workflows.sh`'s `_claude_settings_path`, `_claude_pl"

### _CLAUDE_GUARD_GIT seam

lead: `_CLAUDE_GUARD_GIT` (`lib/workflows.sh:_claude_settings_git_state`)

- Resolve git through `_CLAUDE_GUARD_GIT`, never through `tests/mocks/git` alone — that mock returns empty stdout and exit 0 for almost every subcommand and shadows the real repository state `_claude_settings_git_state` needs.
- In guard tests, strip the mocks directory from `PATH`, symlink the real `git` into a private shim dir, and export that path as `_CLAUDE_GUARD_GIT`, so every other `git`-shaped call in the same file still hits the fast mock.
  trigger: testing `_claude_settings_git_state` | `lib/workflows.sh`
  covers:
  - a: "is what `_claude_settings_git_state` resolves git through"

### tests/mocks/claude seam modes

lead: `MOCK_CLAUDE_*` (`tests/mocks/claude`)

- Use `MOCK_CLAUDE_PLUGINS_LIST_JSON`/`MOCK_CLAUDE_MARKETPLACE_LIST_JSON` for the `--json` payload (default `[]`); `MOCK_CLAUDE_FAIL_ARGS` to fail only invocations whose argv contains a given substring; `MOCK_CLAUDE_FAIL_ON_CALL=<n>` to fail only the nth `plugins list --json` call; and `MOCK_CLAUDE_EDIT_SETTINGS=<verb>` to make only `install` or `update` touch `_OVERRIDE_CLAUDE_SETTINGS`.
- Every invocation is still recorded to `MOCK_CALLS_FILE` regardless of mode.
  trigger: adding a `tests/mocks/claude` mode or asserting on its call log | `tests/mocks/claude`
  covers:
  - a: "gained five new modes for this"

### Claude plugin provisioning: stdin redirect and IFS tab collapse

lead: none

- Every `claude` call inside a `while read` loop in `setup_claude_plugins`/`run_update`'s claude section must redirect stdin from `/dev/null` (e.g. `claude plugins marketplace add "${_ref}" < /dev/null`) — without it, `claude` consumes the loop's own `<<<"${_manifest}"` here-string, truncating iteration after the first external call.
- `IFS=$'\t' read` collapses adjacent tabs, so an empty field shifts the next one left instead of staying empty — split manifest lines with `_claude_manifest_split_line`'s parameter expansion, and never emit a genuinely empty tab-separated field (use a literal `-` placeholder, as `_claude_settings_git_state` does).
  trigger: editing a `while read` loop or a tab-separated line in claude plugin provisioning | `lib/workflows.sh`
  covers:
  - a: "`IFS=$'\\t' read` collapses a run of adjacent tabs"
  - b: "Every `claude` call inside a `while read` loop in `setu"
