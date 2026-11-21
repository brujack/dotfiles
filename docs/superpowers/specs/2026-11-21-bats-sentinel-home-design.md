# Bats suite under a sentinel HOME — design

- **Date:** 2026-11-21
- **Source:** security audit 2026-11-16, findings F15-F20 (ai-config `docs/knowledge/dotfiles-security-audit-2026-11-16.md`); F15 fixed in dotfiles#475.

## Problem

Test isolation from the operator's real `HOME` is a per-file convention, and the convention has already failed once in production: `tests/setup_env/macos.bats` repointed the real `~/brew/Brewfile` on every `make test` run, on `claude`, `workstation` and the Studio, until dotfiles#475. The audit found further gaps of the same class:

- **F16.** `tests/zshrc.d/unit.bats` never assigns `HOME` and sources `.config/.zshrc.d/5_general.zsh`, whose self-heal guard (`[[ ! -d ${HOME}/.oh-my-zsh/custom/plugins/zsh-autosuggestions ]]`) runs `git clone` and whose Linux branch runs `rbenv init`. Latent on `claude` (the real plugin is cloned), live on any machine missing it, where the mock git leaves an empty directory that permanently satisfies the `-d` guard.
- **F17.** No suite-wide `GIT_CONFIG_GLOBAL`/`GIT_CONFIG_SYSTEM` isolation. Latent: the operator's global config sets neither `core.hooksPath` nor `commit.gpgsign` (checked 2026-11-21).
- **F18.** `XDG_*` is never redirected, so real binaries run by tests write the operator's XDG caches.
- **F19.** Mocks default `MOCK_CALLS_FILE` to the shared `/tmp/mock_calls`; on `claude` that file was written by peer sessions at 12:30 on 2026-11-21 (751,745 bytes).

A helper-based fix cannot cover the suite: 44 of 114 tracked `.bats` files do not source `tests/helpers/common.bash` (counted 2026-11-21 with `git ls-files '*.bats'` and `grep -q 'helpers/common.bash'`).

## Measurements (2026-11-21, `claude`, one clone of master at e320a915+#475)

Population: the full bats suite (`bats --jobs 24 --recursive tests/`), run twice in one `git clone`, not in a `git archive` copy (an archive is not a git repo and fails every `git ls-files` test, which confounded a first attempt: 121 failures).

| Run      | Environment                                                                                                                        | not ok    |
| -------- | ---------------------------------------------------------------------------------------------------------------------------------- | --------- |
| baseline | real `HOME`                                                                                                                        | 0 of 4284 |
| sentinel | `HOME`, the four `XDG_*_HOME` and `MOCK_CALLS_FILE` in a scratch dir; `GIT_CONFIG_GLOBAL=/dev/null`, `GIT_CONFIG_SYSTEM=/dev/null` | 8 of 4284 |

All 8 sentinel failures are in `tests/setup_env/requirements_ci.bats`: `resolve_pinned_uv` (`lib/helpers.sh`) defaults to `${HOME}/.local/share/dotfiles/pinned/uv-${UV_VER}/uv`. No other test needs the real `HOME`.

Residue in the sentinel `HOME` (archive-copy run; the residue population does not depend on git): `.oh-my-zsh/custom/plugins/zsh-autosuggestions` and `.rbenv/{shims,versions}` (F16), and `.parallel/tmp/sshlogin/claude` (GNU parallel, started by `bats --jobs` itself, not by a test). Residue in the sentinel XDG dirs: Go telemetry, powershell startup data, tflint version cache, flatpak system cache.

## Design

### 1. Wrapper: `scripts/bats-isolated.sh`

Runs bats with the caller's arguments under a sentinel `HOME`, then fails on anything a test wrote there.

1. Before the swap, if `PINNED_UV_BIN` is unset or empty and `${HOME}/.local/share/dotfiles/pinned/uv-${UV_VER}/uv` is executable (`UV_VER` read by sourcing `lib/constants.sh`), export `PINNED_UV_BIN` as that path.
2. Create one scratch directory with `mktemp -d` (refuse on failure) holding `home/`, `xdg/config`, `xdg/cache`, `xdg/data`, `xdg/state` and `parallel/`.
3. Export `HOME=<s>/home`, `XDG_CONFIG_HOME=<s>/xdg/config`, `XDG_CACHE_HOME=<s>/xdg/cache`, `XDG_DATA_HOME=<s>/xdg/data`, `XDG_STATE_HOME=<s>/xdg/state`, `PARALLEL_HOME=<s>/parallel`, `GIT_CONFIG_GLOBAL=/dev/null`, `GIT_CONFIG_SYSTEM=/dev/null`, and `MOCK_CALLS_FILE=<s>/mock_calls` when the caller's `MOCK_CALLS_FILE` is unset or empty.
4. Run `${_OVERRIDE_BATS_BIN:-bats} "$@"` and keep its exit status.
5. List `find <s>/home -mindepth 1`. For each entry print `bats-isolated: residue: <path relative to <s>/home>` to stderr, then once `bats-isolated: a test wrote to the HOME stand-in; redirect HOME in that test's setup()`.
6. Exit with bats' status when non-zero; otherwise exit 1 when step 5 found residue, else 0.
7. The scratch directory is removed before the wrapper exits, on pass and on fail, by an `EXIT` trap installed after `mktemp -d` inside a subshell (shell-010).

XDG residue never fails the gate: the XDG dirs are redirected so tool caches cannot reach the operator's, and discarded with the scratch.

### 2. Call sites

The three bats command lines in the `test-bats` recipe (parallel, serial fallback, serial carve-out) and the bats invocation in `scripts/run-bash-coverage.sh` call the wrapper. That covers `make test`, the pre-push hook, and every CI shard (Linux `make bash-coverage`, macOS `make test`/`make test-bats`). `_OVERRIDE_BATS_BIN` still selects the bats binary. A direct `bats tests/x.bats` run is unwrapped by choice; the gate forbids the HOME writes such a run could make.

### 3. F16 fix

`tests/zshrc.d/unit.bats` `setup()` exports `HOME="${BATS_TEST_TMPDIR}/home"`, creates `${HOME}/.oh-my-zsh/custom/plugins/zsh-autosuggestions`, and exports `_OVERRIDE_RBENV_BINARY=/nonexistent/rbenv`. Tests that set their own `_fake_home` override it after `setup()`, unchanged.

### 4. Tests: `tests/scripts/bats_isolated.bats`

Drive the wrapper over fixture `.bats` files written per test under `BATS_TEST_TMPDIR`. The wrapper's own `HOME` capture reads the enclosing environment, which under `make test` is the outer sentinel, so nothing here reaches the real `HOME`.

## Error handling

- `mktemp -d` failure: print the cause and exit 1 before running bats.
- bats missing: the Makefile's existing `BATS_MISSING` guard and `run-bash-coverage.sh`'s existing check still fire first; the wrapper does not add a second message.
- A bats failure with residue: bats' status is returned and the residue is still printed, so neither signal hides the other.

## Out of scope

- The `${MOCK_CALLS_FILE:-/tmp/mock_calls}` default in the 67 mocks. Every `make test` run gets a per-run file from the wrapper; a direct bats run still defaults to `/tmp`.
- XDG residue (operator decision 2026-11-21: gate on HOME only).
- Reordering `load_setup_env` before `export HOME` in the 33 `tests/setup_env/` files that do so; the gate catches any of them that writes `HOME`.

## Requirements

- **R1.** `scripts/bats-isolated.sh` exists, starts `#!/usr/bin/env bash`, and runs `${_OVERRIDE_BATS_BIN:-bats}` with exactly the arguments it was given.
- **R2.** While bats runs, `HOME`, `XDG_CONFIG_HOME`, `XDG_CACHE_HOME`, `XDG_DATA_HOME`, `XDG_STATE_HOME` and `PARALLEL_HOME` are `<s>/home`, `<s>/xdg/config`, `<s>/xdg/cache`, `<s>/xdg/data`, `<s>/xdg/state` and `<s>/parallel` for one directory `<s>` created by `mktemp -d`, and `GIT_CONFIG_GLOBAL` and `GIT_CONFIG_SYSTEM` are both `/dev/null`.
- **R3.** While bats runs, `MOCK_CALLS_FILE` is `<s>/mock_calls` when the caller left it unset or empty, and the caller's value otherwise.
- **R4.** While bats runs, `PINNED_UV_BIN` is `<pre-swap HOME>/.local/share/dotfiles/pinned/uv-<UV_VER>/uv` when the caller left it unset or empty and that file is executable, and is the caller's value (or unset) otherwise.
- **R5.** After bats, the wrapper prints `bats-isolated: residue: <path>` to stderr for every entry under `<s>/home`, with `<path>` relative to `<s>/home`, followed once by `bats-isolated: a test wrote to the HOME stand-in; redirect HOME in that test's setup()`.
- **R6.** The wrapper exits with bats' status when it is non-zero, with 1 when bats exited 0 and R5 found at least one entry, and with 0 otherwise.
- **R7.** A write under `<s>/xdg` or `<s>/parallel` alone never makes the wrapper exit non-zero.
- **R8.** `<s>` no longer exists after the wrapper exits, whether bats passed or failed.
- **R9.** Every bats command line in the Makefile `test-bats` recipe runs through `scripts/bats-isolated.sh`.
- **R10.** `scripts/run-bash-coverage.sh` runs bats through `scripts/bats-isolated.sh`, and `_OVERRIDE_BATS_BIN` still selects the bats binary.
- **R11.** `tests/zshrc.d/unit.bats` `setup()` exports `HOME="${BATS_TEST_TMPDIR}/home"`, creates `${HOME}/.oh-my-zsh/custom/plugins/zsh-autosuggestions`, and exports `_OVERRIDE_RBENV_BINARY=/nonexistent/rbenv`.
- **R12.** `tests/scripts/bats_isolated.bats` has a test for each of R2-R8, including one fixture that writes `$HOME/x` and asserts exit 1 with `bats-isolated: residue: x` in the output, and one failing fixture with residue that asserts bats' status and the residue line together.
- **R13.** `tests/bats-files.txt` lists `tests/scripts/bats_isolated.bats`.
- **V1.** `make test` on the finished branch on `claude` exits 0 with no `bats-isolated: residue:` line in its output.
- **V2.** Positive control: on the branch with R11 reverted, `make test-bats` fails and its output names `.oh-my-zsh` and `.rbenv` as residue.
- **V3.** CI is green on the PR, including all three `test-macos-shard` legs and all three `test-shard` legs.
- **N1.** No mock under `tests/mocks/` changes its `MOCK_CALLS_FILE` default.
- **N2.** No `.bats` file other than `tests/zshrc.d/unit.bats` and the new `tests/scripts/bats_isolated.bats` is edited.
- **N3.** The wrapper's own commands, excluding the bats process it runs, read nothing under the pre-swap `HOME` except the R4 executable check and write nothing outside `<s>`.
