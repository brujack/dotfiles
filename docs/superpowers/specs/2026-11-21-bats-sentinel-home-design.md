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

macOS (Mac Studio, one `git clone` of 67909a63, `bats --jobs 12 --recursive tests/` under the same sentinel environment, 2026-11-21): 4284 ok, 0 not ok, exit 0. `HOME` residue: `.oh-my-zsh/custom/plugins/zsh-autosuggestions` and `.pyenv/shims`, and nothing under `Library/`. A per-file probe attributed both to `tests/zshrc.d/unit.bats` alone; `.pyenv/shims` comes from the real `pyenv` the Studio has on `PATH`, which the sourced zsh config initialises. Population: one Mac, which has the operator's toolchain; the `macos-latest` runner has less on `PATH`, so it can only produce a subset of these writes.

## Design

### 1. Wrapper: `scripts/bats-isolated.sh`

Runs the command it is given (`scripts/bats-isolated.sh bats --jobs 24 …`) under a sentinel `HOME`, then fails on anything a test wrote there. The wrapper takes the whole command rather than only bats' arguments, so the bats binary stays chosen where it is chosen today (literal `bats` in the Makefile, `_OVERRIDE_BATS_BIN` in `scripts/run-bash-coverage.sh`), and a recipe line still contains `bats --jobs …` as a substring.

1. Before the swap, if `PINNED_UV_BIN` is unset or empty and `${HOME}/.local/share/dotfiles/pinned/uv-${UV_VER}/uv` is executable (`UV_VER` read by sourcing `lib/constants.sh`), export `PINNED_UV_BIN` as that path.
2. Create one scratch directory with `mktemp -d "${_BATS_ISOLATED_TMP_ROOT:-${TMPDIR:-/tmp}}/bats-isolated.XXXXXX"` (refuse on failure; the seam exists because BSD `mktemp -d` with a template ignores `TMPDIR`, so only it reaches the failure branch on macOS) holding `home/`, `xdg/config`, `xdg/cache`, `xdg/data`, `xdg/state` and `parallel/`.
3. Export `HOME=<s>/home`, `XDG_CONFIG_HOME=<s>/xdg/config`, `XDG_CACHE_HOME=<s>/xdg/cache`, `XDG_DATA_HOME=<s>/xdg/data`, `XDG_STATE_HOME=<s>/xdg/state`, `PARALLEL_HOME=<s>/parallel`, `GIT_CONFIG_GLOBAL=/dev/null`, `GIT_CONFIG_SYSTEM=/dev/null`, and `MOCK_CALLS_FILE=<s>/mock_calls` when the caller's `MOCK_CALLS_FILE` is unset or empty.
4. Run `"$@"` and keep its exit status.
5. List `find <s>/home -mindepth 1`. For each entry print `bats-isolated: residue: <path relative to <s>/home>` to stderr, then once `bats-isolated: a test wrote to the HOME stand-in; redirect HOME in that test's setup()`. When `find` succeeds and lists nothing, print `bats-isolated: residue check: clean` to stderr, so a run that never reached the check is distinguishable from a clean one. When `find` itself fails, print `bats-isolated: residue check failed` and treat it as residue (fail closed).
6. Exit with bats' status when non-zero; otherwise exit 1 when step 5 found residue, else 0.
7. The scratch directory is removed before the wrapper exits, on pass and on fail, by an `EXIT` trap installed after `mktemp -d` inside a subshell (shell-010).

XDG residue never fails the gate: the XDG dirs are redirected so tool caches cannot reach the operator's, and discarded with the scratch.

### 2. Call sites

The three bats command lines in the `test-bats` recipe (parallel, serial fallback, serial carve-out) become `scripts/bats-isolated.sh bats …` with their arguments unchanged, and the bats invocation in `scripts/run-bash-coverage.sh` becomes `"<its own directory>/bats-isolated.sh" "${_bats_bin}" "${_bats_args[@]}"`. That covers `make test`, the pre-push hook, and every CI shard (Linux `make bash-coverage`, macOS `make test`/`make test-bats`). `_OVERRIDE_BATS_BIN` keeps its current scope: the coverage script only. A direct `bats tests/x.bats` run is unwrapped by choice; the gate forbids the HOME writes such a run could make.

Two test files assert the recipe's text through `make -n`, and change with it:

- `tests/makefile_parallel_target.bats` and `tests/makefile_shard_list.bats` grep `make -n` output for lines anchored `^bats`. Each positive match is re-anchored to `^scripts/bats-isolated\.sh bats ` with the rest of its pattern unchanged.
- Four of those greps are absence guards: parallel_target's "non-GNU parallel takes the serial path", "`HAVE_PARALLEL=` forces serial" and "empty file list" tests, and shard_list's "`test-prereqs` plans no bats call". Re-anchoring a negative grep to a new shape leaves it passing forever if the shape changes again, so each absence pattern becomes `^(scripts/bats-isolated\.sh )?bats ` (either shape fails it), and the two serial-path tests also assert that exactly one `^scripts/bats-isolated\.sh bats ` line without `--jobs` is present.

### 3. F16 fix

`tests/zshrc.d/unit.bats` `setup()` exports `HOME="${BATS_TEST_TMPDIR}/home"`, creates `${HOME}/.oh-my-zsh/custom/plugins/zsh-autosuggestions`, and exports `_OVERRIDE_RBENV_BINARY=/nonexistent/rbenv`. Tests that set their own `_fake_home` override it after `setup()`, unchanged.

### 4. Tests: `tests/scripts/bats_isolated.bats`

Drive the wrapper over fixture `.bats` files written per test under `BATS_TEST_TMPDIR`. The wrapper's own `HOME` capture reads the enclosing environment, which under `make test` is the outer sentinel, so nothing here reaches the real `HOME`. The cleanup test records `<s>` from inside the running fixture (the fixture writes its `HOME`'s parent to a file under `BATS_TEST_TMPDIR`), asserts the recorded path existed during the run, then asserts it is gone; an absence check alone would pass if `<s>` were never created. The `mktemp` failure test points `_BATS_ISOLATED_TMP_ROOT` at a missing directory. The wrapper is in the coverage-instrumented set (`scripts/*.sh`), so these tests carry its share of the 91% floor.

## Error handling

- `mktemp -d` failure: print `bats-isolated: cannot create scratch directory under <root>` and exit 1 before running bats.
- bats missing: the Makefile's existing `BATS_MISSING` guard and `run-bash-coverage.sh`'s existing check still fire first; the wrapper does not add a second message.
- A bats failure with residue: bats' status is returned and the residue is still printed, so neither signal hides the other.

## Out of scope

- The `${MOCK_CALLS_FILE:-/tmp/mock_calls}` default in the 67 mocks. Every `make test` run gets a per-run file from the wrapper; a direct bats run still defaults to `/tmp`.
- XDG residue (operator decision 2026-11-21: gate on HOME only).
- Reordering `load_setup_env` before `export HOME` in the 33 `tests/setup_env/` files that do so; the gate catches any of them that writes `HOME`.

## Requirements

- **R1.** `scripts/bats-isolated.sh` exists, starts `#!/usr/bin/env bash`, and runs its arguments as one command (`"$@"`: the first argument is the program, the rest its arguments, unchanged).
- **R2.** While bats runs, `HOME`, `XDG_CONFIG_HOME`, `XDG_CACHE_HOME`, `XDG_DATA_HOME`, `XDG_STATE_HOME` and `PARALLEL_HOME` are `<s>/home`, `<s>/xdg/config`, `<s>/xdg/cache`, `<s>/xdg/data`, `<s>/xdg/state` and `<s>/parallel` for one directory `<s>` created by `mktemp -d "${_BATS_ISOLATED_TMP_ROOT:-${TMPDIR:-/tmp}}/bats-isolated.XXXXXX"`, and `GIT_CONFIG_GLOBAL` and `GIT_CONFIG_SYSTEM` are both `/dev/null`.
- **R3.** While bats runs, `MOCK_CALLS_FILE` is `<s>/mock_calls` when the caller left it unset or empty, and the caller's value otherwise.
- **R4.** While bats runs, `PINNED_UV_BIN` is `<pre-swap HOME>/.local/share/dotfiles/pinned/uv-<UV_VER>/uv` when the caller left it unset or empty and that file is executable, and is the caller's value (or unset) otherwise.
- **R5.** After bats, the wrapper prints `bats-isolated: residue: <path>` to stderr for every entry under `<s>/home`, with `<path>` relative to `<s>/home`, followed once by `bats-isolated: a test wrote to the HOME stand-in; redirect HOME in that test's setup()`; when `<s>/home` is empty it prints `bats-isolated: residue check: clean` to stderr instead; when the listing command fails it prints `bats-isolated: residue check failed` to stderr.
- **R6.** The wrapper exits with bats' status when it is non-zero, with 1 when bats exited 0 and R5 found at least one entry or the listing failed, and with 0 otherwise.
- **R7.** A write under `<s>/xdg` or `<s>/parallel` alone never makes the wrapper exit non-zero.
- **R8.** `<s>` no longer exists after the wrapper exits, whether bats passed or failed.
- **R9.** Each of the three bats command lines in the Makefile `test-bats` recipe starts `scripts/bats-isolated.sh bats ` followed by the arguments it has today.
- **R10.** `scripts/run-bash-coverage.sh` runs `bats-isolated.sh` from its own directory with `"${_bats_bin}"` as the first argument, so `_OVERRIDE_BATS_BIN` still selects the bats binary there and nowhere else.
- **R11.** `tests/zshrc.d/unit.bats` `setup()` exports `HOME="${BATS_TEST_TMPDIR}/home"`, creates `${HOME}/.oh-my-zsh/custom/plugins/zsh-autosuggestions`, and exports `_OVERRIDE_RBENV_BINARY=/nonexistent/rbenv`.
- **R12.** `tests/scripts/bats_isolated.bats` has a test for each of R2-R8 and R15, including one fixture that writes `$HOME/x` and asserts exit 1 with `bats-isolated: residue: x` in the output, one failing fixture with residue that asserts bats' status and the residue line together, one clean fixture that asserts `bats-isolated: residue check: clean`, and an R8 test that records `<s>` from inside the fixture, asserts it existed during the run, and asserts it is gone afterwards.
- **R13.** `tests/bats-files.txt` lists `tests/scripts/bats_isolated.bats`.
- **R14.** In `tests/makefile_parallel_target.bats` and `tests/makefile_shard_list.bats`, every grep of `make -n` output anchored on `^bats` is re-anchored on `^scripts/bats-isolated\.sh bats ` with the rest of its pattern unchanged, except the four absence guards (parallel_target: non-GNU parallel serial path, `HAVE_PARALLEL=` forces serial, empty file list; shard_list: `test-prereqs` plans no bats call), whose absence pattern is `^(scripts/bats-isolated\.sh )?bats `; the two serial-path guards also assert exactly one `^scripts/bats-isolated\.sh bats ` line not containing `--jobs`.
- **R15.** When `mktemp -d` fails, the wrapper prints `bats-isolated: cannot create scratch directory under <root>` to stderr, exits 1, and does not run its command.
- **V1.** `make test` on the finished branch on `claude` exits 0, its output contains `bats-isolated: residue check: clean`, and it contains no `bats-isolated: residue:` line.
- **V2.** Positive control: on the branch with R11 reverted, `make test-bats` on `claude` fails and its output names `.oh-my-zsh` and `.rbenv` as residue.
- **V3.** CI is green on the PR, including all three `test-macos-shard` legs and all three `test-shard` legs.
- **V4.** Positive control for R14: with one Makefile recipe line reverted to a bare `bats`, each of the four absence guards still fails when its forbidden condition is forced (one mutation per guard).
- **N1.** No mock under `tests/mocks/` changes its `MOCK_CALLS_FILE` default.
- **N2.** No `.bats` file other than `tests/zshrc.d/unit.bats`, `tests/makefile_parallel_target.bats`, `tests/makefile_shard_list.bats` and the new `tests/scripts/bats_isolated.bats` is edited, and the two makefile test files change only as R14 states.
- **N3.** The wrapper's own commands, excluding the bats process it runs, read nothing under the pre-swap `HOME` except the R4 executable check and write nothing outside `<s>`.

## Multi-Lens Review

### Round 1

Reviewed at commit: `67909a63` (Step 7 self-review commit, before Step 8 dispatch)

#### Goal-Fit

Finding: Worth building; a reader of the gate's message can act on it. V1 alone is vacuous (it also passes when the residue check never ran); V2 and R12's residue fixtures are the real controls.
Assumption: macOS writes no `HOME` residue beyond what `claude` showed (Go's `os.UserConfigDir` maps to `~/Library/Application Support` there, outside `XDG_*`). Refuted or confirmed by a sentinel run on the Studio.
Disposition: Addressed (operator, 2026-11-21). Studio run measured (Measurements section): residue only `.oh-my-zsh` and `.pyenv/shims`, both from `tests/zshrc.d/unit.bats` and contained by R11; no `Library/`. V1 now requires `bats-isolated: residue check: clean` (R5).

#### Ergonomics

Finding: R9 contradicted N2: 19 `make -n` recipe-text assertions in `tests/makefile_parallel_target.bats` and `tests/makefile_shard_list.bats` anchor on `^bats`, so 16 go red and the absence guards go silently vacuous. Secondary: a residue line names a path, not the test that wrote it.
Assumption: no uncertain assumption found.
Disposition: Addressed (operator, 2026-11-21) for the R9/N2 conflict: the wrapper takes the whole command (R1, R9, R10), N2 widens to the two files, R14 re-anchors them and hardens the four absence guards, V4 is their positive control. Accepted (operator, 2026-11-21) for path-not-test attribution: rare, and per-file bisection is cheap.

#### Risk

Finding: Same R9/N2 conflict, with the vacuous absence guards named. The R8 cleanup test passes if `<s>` was never created. The wrapper joins the coverage-instrumented set, and its `mktemp` failure branch is unreachable on BSD without a seam. Wrapping `_OVERRIDE_BATS_BIN` into the wrapper would widen that seam to the Makefile path.
Assumption: no uncertain assumption found.
Disposition: Addressed (operator, 2026-11-21): R14/V4 as above; R12's R8 test records `<s>` during the run; seam `_BATS_ISOLATED_TMP_ROOT` and R15; `_OVERRIDE_BATS_BIN` stays in the coverage script only (R10).

#### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.
