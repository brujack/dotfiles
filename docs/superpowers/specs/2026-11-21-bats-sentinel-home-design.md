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

Linux `workstation` (7950X, one `git clone` of d1e648f7, `bats --jobs 24 --recursive tests/` under the same sentinel environment with the linuxbrew prefix on `PATH`, 2026-11-21): 4284 ok, 0 not ok, exit 0. `HOME` residue: `.rbenv/{shims,versions}`, `.zcompdump` and `.oh-my-zsh/custom/plugins`; a per-file probe attributed all three to `tests/zshrc.d/unit.bats` alone, so R11's `HOME` redirect contains them.

## Design

### 1. Wrapper: `scripts/bats-isolated.sh`

Runs the command it is given (`scripts/bats-isolated.sh bats --jobs 24 …`) under a sentinel `HOME`, then fails on anything a test wrote there. The wrapper takes the whole command rather than only bats' arguments, so the bats binary stays chosen where it is chosen today (literal `bats` in the Makefile, `_OVERRIDE_BATS_BIN` in `scripts/run-bash-coverage.sh`), and a recipe line still contains `bats --jobs …` as a substring.

1. Before the swap, if `PINNED_UV_BIN` is unset or empty and `${HOME}/.local/share/dotfiles/pinned/uv-${UV_VER}/uv` is executable (`UV_VER` read with `sed -n 's/^UV_VER="\(.*\)"$/\1/p'` from `${BASH_SOURCE[0]%/*}/../lib/constants.sh` (the wrapper's own repo, whatever the caller's directory), never by sourcing it: sourcing runs `uname` and `hostname`, which the restricted `PATH` in `tests/makefile_shard_list.bats` does not provide), export `PINNED_UV_BIN` as that path. When that read yields an empty `UV_VER`, print `bats-isolated: cannot read UV_VER from <path>` to stderr and leave `PINNED_UV_BIN` alone, so the later `resolve_pinned_uv` failure is not mistaken for a missing install.
2. Create one scratch directory with `mktemp -d "${_BATS_ISOLATED_TMP_ROOT:-${TMPDIR:-/tmp}}/bats-isolated.XXXXXX"` (refuse on failure; the seam exists because BSD `mktemp -d` with a template ignores `TMPDIR`, so only it reaches the failure branch on macOS) holding `home/`, `xdg/config`, `xdg/cache`, `xdg/data`, `xdg/state` and `parallel/`.
3. Export `HOME=<s>/home`, `XDG_CONFIG_HOME=<s>/xdg/config`, `XDG_CACHE_HOME=<s>/xdg/cache`, `XDG_DATA_HOME=<s>/xdg/data`, `XDG_STATE_HOME=<s>/xdg/state`, `PARALLEL_HOME=<s>/parallel`, `ZDOTDIR=<s>/home`, `TMPPREFIX=<s>/zsh`, `GIT_CONFIG_GLOBAL=/dev/null`, `GIT_CONFIG_SYSTEM=/dev/null`, and `MOCK_CALLS_FILE=<s>/mock_calls` when the caller's `MOCK_CALLS_FILE` is unset or empty.
4. Run `"$@"` and keep its exit status.
5. List `find <s>/home -mindepth 1 -maxdepth 1` (top-level entries only, so the lines name the offending directory rather than its deepest subpaths). For each entry print `bats-isolated: residue: <path relative to <s>/home>` to stderr, then once `bats-isolated: a test wrote to the HOME stand-in; redirect HOME in that test's setup()`. When `find` succeeds and lists nothing, print `bats-isolated: residue check: clean` to stderr, so a run that never reached the check is distinguishable from a clean one. When `find` itself fails, print `bats-isolated: residue check failed` and treat it as residue (fail closed).
6. Exit with bats' status when non-zero; otherwise exit 1 when step 5 found residue, else 0.
7. The scratch directory is removed before the wrapper exits, on pass and on fail, by an `EXIT` trap installed after `mktemp -d` inside a subshell (shell-010).

`ZDOTDIR` is redirected by name because zsh writes `.zcompdump` to `${ZDOTDIR:-$HOME}` and every `zsh` reads `${ZDOTDIR}/.zshenv`: with the operator's `ZDOTDIR=$HOME` exported (as on `claude`), `tests/zshrc.d/unit.bats` rewrote the real `~/.zcompdump` while the sentinel stayed clean, which is why `claude`'s residue list lacked the `.zcompdump` that `workstation`'s had. Pointing it at `<s>/home` puts that write where the gate sees it. Other exported variables that point into the home are measured by V7 rather than scanned at run time: a generic unset would change 17 variables (on `claude`) the suite has never run without, and a generic warning would print on every run.

XDG residue never fails the gate: the XDG dirs are redirected so tool caches cannot reach the operator's, and discarded with the scratch.

### 2. Call sites

The four bats command lines in the Makefile (the `test-bats` recipe's parallel, serial fallback and serial carve-out lines, and the `test-unit` recipe's line) become `scripts/bats-isolated.sh bats …` with their arguments unchanged, and the bats invocation in `scripts/run-bash-coverage.sh` becomes `"<its own directory>/bats-isolated.sh" "${_bats_bin}" "${_bats_args[@]}"`. That covers `make test`, the pre-push hook, and every CI shard (Linux `make bash-coverage`, macOS `make test`/`make test-bats`). `_OVERRIDE_BATS_BIN` keeps its current scope: the coverage script only. A direct `bats tests/x.bats` run is unwrapped by choice; the gate forbids the HOME writes such a run could make.

Two test files assert the recipe's text through `make -n`, and change with it:

- `tests/makefile_parallel_target.bats` and `tests/makefile_shard_list.bats` match `make -n` output against bats command lines in 19 places (counted 2026-11-21): 17 greps anchored `^bats`, one exact-line `grep -qx` literal and one `^[[:space:]]*bats[[:space:]]` guard. Four of them are absence guards, and several assert that *every* bats line has some property (stdin redirect, `--print-output-on-failure`, a line count). Rewriting the patterns to the wrapped shape breaks both kinds: an either-shape absence pattern drops the `--jobs` a serial-path guard forbids, and a re-anchored "every line" check silently skips a bare line. So the patterns do not change. A new helper, `_unwrap_bats_lines` in `tests/helpers/unwrap_bats_lines.bash`, runs on every `make -n` capture in the two files before its first assertion: 10 at origin/master (`tests/makefile_parallel_target.bats` `_run_make_dry` and the inline runs at lines 271, 279, 287, 293 and 343; `tests/makefile_shard_list.bats` lines 132, 171, 184 and 197, four of which put `-n` on a continuation line). Each file may fold its inline runs into one helper that runs `make -n` and always unwraps, so a new test cannot forget the call. It fails when any line is a bare bats call (`^[[:space:]]*bats[[:space:]]`), then strips the leading `scripts/bats-isolated.sh ` from every line, so every existing pattern sees today's text and keeps its exact meaning. The helper is the single guard that every recipe line is wrapped.
- `tests/makefile_shard_list.bats` runs `make test-bats` for real under a `PATH` restricted to a shim directory (`make git env bash sed awk grep mktemp find sort file tr cut head cat python3` plus a recording `bats` stub). The wrapper runs inside that `PATH`, so the shim list gains `mkdir` and `rm`. The wrapper uses only bash builtins and those shim tools.

`scripts/run-bash-coverage.sh` sends bats' stdout and stderr to `bats_run.log`, so on the coverage path (every Linux CI shard and local `make bash-coverage`) the wrapper's lines land only in the log. A green run with residue would then print `bats suite failed (exit 1, 0 test(s) not ok)` with an empty failure list. `_check_red_suite` therefore also copies every line of the log starting `bats-isolated: ` to stderr when the suite is red.

### 3. F16 fix

`tests/zshrc.d/unit.bats` `setup()` exports `HOME="${BATS_TEST_TMPDIR}/home"`, creates `${HOME}/.oh-my-zsh/custom/plugins/zsh-autosuggestions`, exports `ZDOTDIR="${HOME}"`, and exports `_OVERRIDE_RBENV_BINARY=/nonexistent/rbenv`. Tests that set their own `_fake_home` override it after `setup()`, unchanged.

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
- **R2.** While bats runs, `HOME`, `XDG_CONFIG_HOME`, `XDG_CACHE_HOME`, `XDG_DATA_HOME`, `XDG_STATE_HOME`, `PARALLEL_HOME`, `ZDOTDIR` and `TMPPREFIX` are `<s>/home`, `<s>/xdg/config`, `<s>/xdg/cache`, `<s>/xdg/data`, `<s>/xdg/state`, `<s>/parallel`, `<s>/home` and `<s>/zsh` for one directory `<s>` created by `mktemp -d "${_BATS_ISOLATED_TMP_ROOT:-${TMPDIR:-/tmp}}/bats-isolated.XXXXXX"`, and `GIT_CONFIG_GLOBAL` and `GIT_CONFIG_SYSTEM` are both `/dev/null`.
- **R3.** While bats runs, `MOCK_CALLS_FILE` is `<s>/mock_calls` when the caller left it unset or empty, and the caller's value otherwise.
- **R4.** While bats runs, `PINNED_UV_BIN` is `<pre-swap HOME>/.local/share/dotfiles/pinned/uv-<UV_VER>/uv`, with `<UV_VER>` read by `sed` from the `UV_VER="…"` line of `${BASH_SOURCE[0]%/*}/../lib/constants.sh` without sourcing that file, when the caller left it unset or empty and that file is executable, and is the caller's value (or unset) otherwise; when that `sed` read yields an empty value the wrapper prints `bats-isolated: cannot read UV_VER from <path>` to stderr.
- **R5.** After bats, the wrapper prints `bats-isolated: residue: <path>` to stderr for every top-level entry of `<s>/home` (`find -mindepth 1 -maxdepth 1`), with `<path>` relative to `<s>/home`, followed once by `bats-isolated: a test wrote to the HOME stand-in; redirect HOME in that test's setup()`; when `<s>/home` is empty it prints `bats-isolated: residue check: clean` to stderr instead; when the listing command fails it prints `bats-isolated: residue check failed` to stderr.
- **R6.** The wrapper exits with bats' status when it is non-zero, with 1 when bats exited 0 and R5 found at least one entry or the listing failed, and with 0 otherwise.
- **R7.** A write under `<s>/xdg` or `<s>/parallel` alone never makes the wrapper exit non-zero.
- **R8.** `<s>` no longer exists after the wrapper exits, whether bats passed or failed.
- **R9.** Each of the four bats command lines in the Makefile (three in the `test-bats` recipe, one in the `test-unit` recipe) starts `scripts/bats-isolated.sh bats ` followed by the arguments it has today.
- **R10.** `scripts/run-bash-coverage.sh` runs `bats-isolated.sh` from its own directory with `"${_bats_bin}"` as the first argument, so `_OVERRIDE_BATS_BIN` still selects the bats binary there and nowhere else; when the suite is red, `_check_red_suite` also prints every `bats_run.log` line starting `bats-isolated: ` to stderr.
- **R11.** `tests/zshrc.d/unit.bats` `setup()` exports `HOME="${BATS_TEST_TMPDIR}/home"`, creates `${HOME}/.oh-my-zsh/custom/plugins/zsh-autosuggestions`, exports `ZDOTDIR="${HOME}"`, and exports `_OVERRIDE_RBENV_BINARY=/nonexistent/rbenv`.
- **R12.** `tests/scripts/bats_isolated.bats` has a test for each of R2-R8 and R15, including one fixture that writes `$HOME/x` and asserts exit 1 with `bats-isolated: residue: x` in the output, one failing fixture with residue that asserts bats' status and the residue line together, one clean fixture that asserts `bats-isolated: residue check: clean`, an R8 test that records `<s>` from inside the fixture, asserts it existed during the run, and asserts it is gone afterwards, one fixture that writes `${ZDOTDIR}/x` and asserts `bats-isolated: residue: x`, and two tests of `_unwrap_bats_lines`: with `output='bats --jobs 1 x < /dev/null'` it fails and prints `unwrapped bats recipe line:`, and with `output='scripts/bats-isolated.sh bats x'` it succeeds and leaves both `$output` and `${lines[0]}` equal to `bats x`.
- **R13.** `tests/bats-files.txt` lists `tests/scripts/bats_isolated.bats`.
- **R14.** `tests/helpers/unwrap_bats_lines.bash` defines `_unwrap_bats_lines`, which fails (non-zero, printing `unwrapped bats recipe line: <line>`) when any line of `$output` matches `^[[:space:]]*bats[[:space:]]`, and otherwise removes a leading `scripts/bats-isolated.sh ` from every line of `$output` and rebuilds `lines` from the result; `tests/makefile_parallel_target.bats` and `tests/makefile_shard_list.bats` load it, and every `make … -n` run in those two files (10 at origin/master: parallel_target's `_run_make_dry` and its inline runs at lines 271, 279, 287, 293 and 343, shard_list's runs at lines 132, 171, 184 and 197) calls it before the first assertion on that run's output, directly or through one per-file helper that runs `make -n` and always calls it; every existing grep pattern, glob and `grep -qx` literal in the two files stays byte-identical; the shim tool list in `tests/makefile_shard_list.bats` `setup()` gains `mkdir` and `rm`.
- **R15.** When `mktemp -d` fails, the wrapper prints `bats-isolated: cannot create scratch directory under <root>` to stderr, exits 1, and does not run its command.
- **R16.** The `Run tests` step of the `test-macos-shard` job in `.github/workflows/ci.yml` runs `grep '^bats-isolated: ' /tmp/make-test.log` after the `rc=$?` line and before the step's first `exit`, so neither `rc` nor the step's exit status depends on the grep; `tests/scripts/bats_isolated.bats` asserts that within that step the grep line is present and its line number is greater than that of `rc=$?` and less than that of the first `exit`.
- **V1.** `make test` and `make bash-coverage` on the finished branch on `claude` each exit 0; the `make test` output and the `make bash-coverage` `bats_run.log` each contain `bats-isolated: residue check: clean`, and it contains no `bats-isolated: residue:` line.
- **V2.** Positive control: on the branch with R11 reverted, `make test-bats` and `make bash-coverage` on `claude` each fail, and each one's terminal output names `.oh-my-zsh` and `.rbenv` as residue.
- **V3.** CI is green on the PR, including all three `test-macos-shard` legs and all three `test-shard` legs.
- **V4.** Positive control for R14: reverting each of the four Makefile bats recipe lines to a bare `bats …` in turn (four mutations) turns at least one test in the two makefile test files red with `unwrapped bats recipe line:` in its output.
- **V5.** On the PR, the downloaded log of one `test-shard` leg and one `test-macos-shard` leg each contain `bats-isolated: residue check: clean` (read each green leg's job log with `gh run view --log`: the Linux leg prints it through `run-bash-coverage.sh`'s `tail -3` of `bats_run.log`, the macOS leg through R16).
- **V6.** `tests/makefile_shard_list.bats` passes against the real wrapper on `claude` and on the Studio.
- **V7.** On `claude`, the Studio and `workstation`, `make test-bats` on the finished branch, run with every variable listed by `env | grep "=${HOME}"` in an agent session pointed at its own empty decoy directory, exits 0 and leaves every decoy empty; a decoy that receives a write gets a named redirect in R2 before merge.
- **N1.** No mock under `tests/mocks/` changes its `MOCK_CALLS_FILE` default.
- **N2.** No `.bats` file other than `tests/zshrc.d/unit.bats`, `tests/makefile_parallel_target.bats`, `tests/makefile_shard_list.bats` and the new `tests/scripts/bats_isolated.bats` is edited, and the two makefile test files change only as R14 states (the helper file `tests/helpers/unwrap_bats_lines.bash` is new and is not a `.bats` file; folding a file's inline `make -n` runs into its R14 per-file helper is an R14 change).
- **N3.** The wrapper's own commands, excluding the bats process it runs, read nothing under the pre-swap `HOME` except the R4 executable check and create or modify no file outside `<s>`; writes to stdout, stderr and the coverage tracer's own fd 9 (opened by `bash-tracer.sh`, which `BASH_ENV` sources into the wrapper under `make bash-coverage`) are not file writes for this purpose.

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

### Round 2

Reviewed at commit: `d1e648f7` (round-1 revision)

#### Goal-Fit

Finding: No issues. The gate changes a verdict (`make test`, pre-push, every CI shard) and its output persists in CI job logs. The premise was re-measured on `claude` with the session's real-`HOME` exports (`PYENV_ROOT`, `GOPATH`, `ZSH`) pointed at decoys: nothing wrote through them.
Assumption: the CI runners produce only a subset of the `HOME` writes seen on the Studio and `claude`; a runner-only tool could write `HOME` there and nowhere else. Settled by V3 and V5.
Disposition: Accepted (operator, 2026-11-21): a wrong assumption shows up as a red PR, not a broken merge.

#### Ergonomics

Finding: On the coverage path (every Linux CI shard, local `make bash-coverage`), `run-bash-coverage.sh` sends bats' stderr to `bats_run.log`, so a green run with residue printed `bats suite failed (exit 1, 0 test(s) not ok)` and an empty failure list, with only `tail -3` of deep subpaths as a clue; and no V item exercised that path, so V3 could pass with the coverage script unwrapped.
Assumption: the 7950X `workstation`, a development box that pushes dotfiles, writes no extra `HOME` residue. Settled by a sentinel run there.
Disposition: Addressed (operator, 2026-11-21): `_check_red_suite` surfaces `bats-isolated:` lines (R10); top-level residue only (R5); V1 and V2 also run `make bash-coverage`; V5 reads a CI shard log for the clean marker. Workstation measured (Measurements section): only `tests/zshrc.d/unit.bats` writes, contained by R11.

#### Risk

Finding: R9 still conflicted with N2: `tests/makefile_shard_list.bats` runs `make test-bats` for real under a shim `PATH` without `mkdir`, `rm`, `uname` or `hostname`, and a prototype wrapper failed 5 of its tests and leaked its scratch directories. Minor: under `make bash-coverage` the wrapper's xtrace goes to fd 9, outside `<s>`, contradicting N3's wording.
Assumption: same as Goal-Fit (runner-only `HOME` writes, for example a self-heal triggered by a tool missing on the runner).
Disposition: Addressed (operator, 2026-11-21): the shim gains `mkdir` and `rm` (R14); `UV_VER` is read with `sed`, not by sourcing (R4); the wrapper uses only builtins and shim tools; V6 runs the file against the real wrapper; N3 exempts inherited file descriptors. Runner assumption Accepted as under Goal-Fit.

#### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.

### Round 3

Reviewed at commit: `c976ed0a` (round-2 revision)

#### Goal-Fit

Finding: No issues. The residue gate is what makes leaving a direct `bats` run unwrapped safe, so it is not decoration; the gate would have reported `residue: brew` for F15; `PARALLEL_HOME` measured to keep GNU parallel's writes out of the gated `HOME`.
Assumption: no uncertain assumption found beyond round 2's runner-residue assumption (Accepted).
Disposition: N/A — clean, no action needed.

#### Ergonomics

Finding: V5 could not pass on a green macOS leg: `make test` output goes only to `/tmp/make-test.log` (`ci.yml:292`), printed and uploaded only on failure, so the clean marker never reaches any record.
Assumption: no uncertain assumption found.
Disposition: Addressed (operator, 2026-11-21): R16 prints the wrapper's lines from `/tmp/make-test.log` in the macOS job log on every run; V5 names both routes.

#### Risk

Finding: R14 still contradicted N2. A prototype turned 3 of 20 `tests/makefile_parallel_target.bats` tests red: two re-anchored helpers are shared with `make -n test-unit`, whose recipe line R9 left unwrapped, and the exact-line `grep -qx 'bats …'` at line 199 has no `^` anchor, so R14's wording did not reach it. Minor: N3 called the tracer's fd 9 inherited; `bash-tracer.sh` opens it inside the wrapper.
Assumption: round 2's runner-residue assumption (Accepted).
Disposition: Addressed (operator, 2026-11-21): R9 wraps all four bats recipe lines, `test-unit` included; R14 enumerates its 19-match population; N3 reworded.

#### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.

### Round 4

Reviewed at commit: `8c191919` (round-3 revision)

#### Goal-Fit

Finding: R14's either-shape absence pattern `^(scripts/bats-isolated\.sh )?bats ` drops `--jobs` from the two serial-path guards, which forbid `^bats --jobs`; each then contradicts its own "exactly one serial line" assertion.
Assumption: no new assumption; round 2's runner-residue assumption (Accepted).
Disposition: Addressed (operator, 2026-11-21) by a different approach: patterns stay byte-identical and `_unwrap_bats_lines` normalises every `make -n` capture (R14, V4).

#### Ergonomics

Finding: re-anchoring the "every bats line" checks (the stdin-redirect and print-output helpers, the line counts) narrows them to wrapped lines, so a future bare `bats` recipe line escapes both the HOME sentinel and the stdin-deadlock guard with every test green.
Assumption: no uncertain assumption found.
Disposition: Addressed (operator, 2026-11-21): as Goal-Fit; the helper fails on any bare line before any check runs, and V4 mutates each recipe line.

#### Risk

Finding: (1) Prototype confirmed the Goal-Fit defect: 2 tests red. (2) R16 let the grep sit between `make` and `rc=$?`, where its 0 exit becomes `rc` and a red macOS shard reports green; `ci-suite-report.sh` does not fail on `not ok`, so auto-merge fires; R16's presence-only test cannot see the placement. Prototype with a corrected R14: `make test` rc 0 (4284 ok, `residue check: clean`), `make bash-coverage` rc 0 at 92%.
Assumption: round 2's runner-residue assumption (Accepted).
Disposition: Addressed (operator, 2026-11-21): (1) as Goal-Fit; (2) R16 places the grep after `rc=$?` and before the first `exit`, and its test asserts the line order.

#### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.

### Round 5

Reviewed at commit: `a790d57b` (round-4 revision)

#### Goal-Fit

Finding: the sentinel covers only paths built from `HOME`. `ZDOTDIR=/home/bruce` is exported on `claude`, so `tests/zshrc.d/unit.bats` rewrote the real `~/.zcompdump` (52584 bytes, mtime inside the measurement window) while the gate reported clean; this is why `claude`'s residue list lacked `workstation`'s `.zcompdump`. R11 alone would not stop it.
Assumption: `HOME` is the only route from a test into the operator's home; refuted for `ZDOTDIR`, open for the other home-pointing variables (17 on `claude`).
Disposition: Addressed (operator, 2026-11-21): R2 redirects `ZDOTDIR` and `TMPPREFIX` by name, R11 sets `ZDOTDIR`, R12 adds a `ZDOTDIR` residue fixture, V7 measures every home-pointing variable on three boxes; a generic scan was rejected (unmeasured unsets, per-run noise).

#### Ergonomics

Finding: (1) R14's "every `make -n` run" was uncounted (10 sites, four with `-n` on a continuation line), and N2 forbade the always-unwrap helper that makes forgetting impossible. (2) `_unwrap_bats_lines` had no test in the suite, only V4's one-off mutation. (3) R4 did not pin `lib/constants.sh`'s location, and an empty read surfaced as a misleading `run make install-pinned-uv`.
Assumption: no new assumption; round 2's runner-residue assumption (Accepted).
Disposition: Addressed (operator, 2026-11-21): R14 lists the 10 sites and allows one always-unwrapping helper per file (N2 widened); R12 tests the helper both ways; R4 pins `${BASH_SOURCE[0]%/*}/../lib/constants.sh` and prints `bats-isolated: cannot read UV_VER from <path>`.

#### Risk

Finding: the same `ZDOTDIR` leak, reproduced with a decoy (`.zcompdump` landed in the decoy, outside the gate); a full-suite run with `ZDOTDIR`, `TMPPREFIX`, `AWS_HOME`, `ANSIBLE_VAULT_PASSWORD_FILE`, `TMUX_PLUGIN_MANAGER_PATH` and `CLAUDE_CODE_PLUGIN_DIRS` decoyed was 4284 ok with only the `ZDOTDIR` decoy written. Prototype of the rest: R14 helper 40/40 ok direct and nested; V4 mutations of Makefile 226/232/236/329 turned 11/6/4/2 tests red, each naming `unwrapped bats recipe line:`; 255 ok across other files reading the coverage script and CI steps; `<s>` removed on TERM and HUP.
Assumption: as Goal-Fit; unmeasured on the Studio and `workstation`.
Disposition: Addressed (operator, 2026-11-21): as Goal-Fit; V7 covers the two unmeasured boxes.

#### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.
