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

The isolation has to hold for a direct `bats tests/x.bats` run too, not only for `make`. A new test's first runs are direct (TDD red and green, and CLAUDE.md's Studio repro recipe), so a boundary drawn at the Makefile lets an F15-class test write the real `HOME` before `make test` ever sees it.

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

bats' own suite hooks (2026-11-21, `claude`, bats 1.13.0; one `git clone` of 348a1d3e with a prototype of the design below):

- `bats` resolves `setup_suite.bash` from the directory of the first argument that holds one (`libexec/bats-core/bats`, the `potential_setup_suite_file` loop), so `--recursive tests/` uses `tests/setup_suite.bash` and a direct `bats tests/setup_env/x.bats` uses `tests/setup_env/setup_suite.bash`. `setup_suite` runs once per invocation, before GNU parallel starts under `--jobs`; `teardown_suite` runs from bats' `EXIT` trap, also when `setup_suite` failed.
- Full suite, `bats --jobs 24 --recursive tests/`, R2's redirects in `setup_suite`, R11 not applied: 4284 ok, then `not ok 4285 teardown_suite` naming `.rbenv`, `.zcompdump` and `.oh-my-zsh`, exit 1, 2:18; the sentinel was removed. This is the same residue the `workstation` row above attributes to `tests/zshrc.d/unit.bats`.
- `make bash-coverage` (the CI `test-shard` shape: `BATS_FILES_FROM` and `COVERAGE_TRACE_DIR` in the environment) over one fixture file writing `$HOME/x`: `bats_run.log` holds `not ok 3 teardown_suite` and the residue lines, and `scripts/run-bash-coverage.sh` printed both and refused to score (exit 2 from make). With the write removed it exited 0, in parallel and in serial mode (`HAVE_PARALLEL=`).
- `PARALLEL_HOME` is load-bearing: without it the same coverage run also reported `.parallel` as residue, because GNU parallel starts after `setup_suite` has swapped `HOME`.
- A `# …` line written to fd 3 by `teardown_suite` appears in the TAP stream; `scripts/ci-suite-report.sh` counted `executed=35 declared=35` for `tests/setup_env/profiles.bats` under `--jobs 4` with that line present.
- A symlinked `setup_suite.bash` sees `BATS_TEST_FILENAME` and `BASH_SOURCE[0]` as the symlink's path, so a path computed from it resolved `lib/constants.sh` from the wrong directory and a direct run of `tests/setup_env/requirements_ci.bats` failed. A regular file that sources the shared helper, which resolves paths from its own `BASH_SOURCE[0]`, passed 37 of 37.
- When `setup_suite` failed before setting the sentinel variable, bats still ran `teardown_suite`; the prototype's unguarded teardown then listed `/home` and ran `rm -rf ""`. R5's guard exists for this.
- Same run with the round-7 helper (sorted single residue line): 4284 ok, `not ok 4285 teardown_suite`, then the message and `residue: .oh-my-zsh .rbenv .zcompdump`, then `bats warning: Executed 4285 instead of expected 4284 tests`, then bats' end-of-run block of nine `BW02` warnings, so the log's `tail -3` showed warning text. A planted, exported `_BATS_SENTINEL` named `bats-sentinel.keep` survived a nested run whose `setup_suite` failed on a missing `_BATS_SENTINEL_TMP_ROOT`; a helper copy without `lib/constants.sh` printed the fd-3 message and its test ran `ok`.
- The `macos-latest` runner installs bats-core 1.14.0 (`test-macos-shard (1)` log, run 44930453010); suite hooks need 1.7 or later. Between the v1.13.0 and v1.14.0 tags, `libexec/bats-core/bats-exec-suite` changes only in empty-suite handling (`--allow-empty-suite`), and no `setup_suite` line of `libexec/bats-core/bats` changes.

## Design

### 1. Suite hooks: `tests/helpers/suite_isolation.bash`

One shared file defines bats' `setup_suite` and `teardown_suite`. Each of the four directories that hold tracked `.bats` files (`tests`, `tests/scripts`, `tests/setup_env`, `tests/zshrc.d`) holds a `setup_suite.bash` whose only command sources it, so every bats invocation (make, coverage, pre-push, CI and a direct run) gets the same isolation without any change to the Makefile, `scripts/run-bash-coverage.sh` or the CI workflow. Regular files rather than symlinks, because a symlinked hook sees its own path as the symlink's (Measurements).

bats calls `setup_suite` under `set -eET`, so any failing command in it aborts the suite with `not ok 1 setup_suite`; every command there that may fail on purpose is guarded. `teardown_suite` is the reverse: bats calls it as `teardown_suite … || status=$?`, so errexit is off inside it and every step checks its own status. Both run in the same shell (`bats-exec-suite`), so a plain shell variable set in `setup_suite` reaches `teardown_suite` without being exported.

`setup_suite`:

1. `unset _BATS_SENTINEL`, as the first command. A nested `bats` started from a test inherits the outer run's environment; without this, a nested run whose `setup_suite` failed before step 3 would hand the outer sentinel to its own `teardown_suite`, which would pass the guard and delete it while sibling tests run (Round 7).
2. Before the swap, read `UV_VER` with `sed -n 's/^UV_VER="\(.*\)"$/\1/p'` from `${BASH_SOURCE[0]%/*}/../../lib/constants.sh` (the helper's own repo, whatever the caller's directory), never by sourcing it, and only when that file is readable (`[[ -r ]]`), with `|| ` an empty fallback so a failed read cannot abort the suite. When the value is empty, print `# bats isolation: cannot read UV_VER from <path>` to fd 3, leave `PINNED_UV_BIN` alone and carry on, so the later `resolve_pinned_uv` failure is not mistaken for a missing install. Otherwise, if `PINNED_UV_BIN` is unset or empty and the uv binary `${HOME}/.local/share/dotfiles/pinned/uv-${UV_VER}/uv` is executable, export `PINNED_UV_BIN` as that binary's path.
3. Create one sentinel directory with `mktemp -d "${_BATS_SENTINEL_TMP_ROOT:-${TMPDIR:-/tmp}}/bats-sentinel.XXXXXX"` (the seam exists because BSD `mktemp -d` with a template ignores `TMPDIR`) and hold its path in the shell variable `_BATS_SENTINEL`, never exported, and create `home/`, `xdg/config`, `xdg/cache`, `xdg/data`, `xdg/state` and `parallel/` in it. On failure print `bats isolation: cannot create sentinel under <root>` and return 1; bats then reports `not ok 1 setup_suite` and runs no test.
4. Export `HOME=<s>/home`, `XDG_CONFIG_HOME=<s>/xdg/config`, `XDG_CACHE_HOME=<s>/xdg/cache`, `XDG_DATA_HOME=<s>/xdg/data`, `XDG_STATE_HOME=<s>/xdg/state`, `PARALLEL_HOME=<s>/parallel`, `ZDOTDIR=<s>/home`, `TMPPREFIX=<s>/zsh`, `GIT_CONFIG_GLOBAL=/dev/null`, `GIT_CONFIG_SYSTEM=/dev/null`, and `MOCK_CALLS_FILE=<s>/mock_calls` when the caller's `MOCK_CALLS_FILE` is unset or empty.

`teardown_suite`:

1. Guard: unless `_BATS_SENTINEL` is non-empty, names a directory, and its last path component matches `bats-sentinel.*`, print `bats isolation: no sentinel to check` and return 1 without running `cd`, `find` or `rm` (bats runs `teardown_suite` even when `setup_suite` failed).
2. List the top-level entries of `<s>/home` with `cd "<s>/home" && find . -mindepth 1 -maxdepth 1` (the `&&` matters: with errexit off, a failed `cd` would otherwise list bats' working directory).
3. Remove `<s>`.
4. When the listing has entries, print `bats isolation: a test wrote to the HOME stand-in; redirect HOME in that test's setup()`, then, as the last line, `residue: <names>` with every entry's name relative to `HOME` (no leading `./`), `LC_ALL=C` sorted and space-separated, and return 1; bats reports `not ok <n+1> teardown_suite` with those lines and exits 1. One line, so a single grep for `residue: ` returns every name. It is not guaranteed to be the log's last line: bats appends its own `Executed N instead of expected M` warning and, when any test triggered one, its end-of-run warning block (nine `BW02` entries on master). When `cd` or `find` fails, remove `<s>`, print `bats isolation: residue check failed` and return 1. When the listing is empty, print `# bats isolation: residue check: clean` to fd 3 and return 0, so a clean run is distinguishable from one that never reached the check.

`ZDOTDIR` is redirected by name because zsh writes `.zcompdump` to `${ZDOTDIR:-$HOME}` and every `zsh` reads `${ZDOTDIR}/.zshenv`: with the operator's `ZDOTDIR=$HOME` exported (as on `claude`), `tests/zshrc.d/unit.bats` rewrote the real `~/.zcompdump` while the sentinel stayed clean, which is why `claude`'s residue list lacked the `.zcompdump` that `workstation`'s had. Other exported variables that point into the home are measured by V7 rather than scanned at run time: a generic unset would change 17 variables (on `claude`) the suite has never run without, and a generic warning would print on every run.

XDG and `parallel/` residue never fails the gate: those dirs are redirected so tool caches cannot reach the operator's, and discarded with the sentinel.

How a residue failure surfaces on each path, with no change to any of them: `make test` and `make test-bats` exit non-zero with the `not ok … teardown_suite` block in bats' output; `make bash-coverage` and every Linux CI shard list `not ok … teardown_suite` among the failing tests and refuse to score, with the names in `bats_run.log` (uploaded as an artifact on CI failure) and on the terminal only when no bats warning block follows them, since the script prints just `tail -3` of the log (operator decision 2026-11-21: accepted, no script change); the macOS CI shard fails on make's exit status and prints the names through `ci-suite-report.sh`'s `print_failures`, which runs in the same step and prints every `not ok` block with its `#` lines. `scripts/ci-suite-report.sh` additionally reports one more executed test than declared, which also fails closed.

### 2. F16 fix

`tests/zshrc.d/unit.bats` `setup()` exports `HOME="${BATS_TEST_TMPDIR}/home"`, creates `${HOME}/.oh-my-zsh/custom/plugins/zsh-autosuggestions`, exports `ZDOTDIR="${HOME}"`, and exports `_OVERRIDE_RBENV_BINARY=/nonexistent/rbenv`. Tests that set their own `_fake_home` override it after `setup()`, unchanged.

### 3. Tests: `tests/suite_isolation.bats`

A coverage guard reads `tests/bats-files.txt` and fails, naming the directory, for any directory holding a listed `.bats` file that lacks a `setup_suite.bash` sourcing the helper; a new test directory without one would otherwise run unisolated. The behaviour tests run a nested `bats` over fixture `.bats` files in a fixture directory under `BATS_TEST_TMPDIR` whose `setup_suite.bash` sources the real helper by absolute path. The nested run's pre-swap `HOME` is the outer suite's sentinel, so nothing here reaches the real `HOME`. The cleanup test records `<s>` from inside the running fixture (the fixture writes its `HOME`'s parent to a file under `BATS_TEST_TMPDIR`), asserts the recorded path existed during the run, then asserts it is gone; an absence check alone would pass if `<s>` were never created. The guard tests call `teardown_suite` directly with `_BATS_SENTINEL` empty and with it pointing at a canary directory whose name does not match, and assert the canary is unchanged. The inherited-sentinel test plants a directory named `bats-sentinel.<x>`, exports it as `_BATS_SENTINEL`, runs a nested `bats` whose `setup_suite` fails (`_BATS_SENTINEL_TMP_ROOT` at a missing directory), and asserts the planted directory still exists. The empty-`UV_VER` test runs a copy of the helper from a fixture tree without `lib/constants.sh` and asserts its fixture test is `ok`. `tests/` is outside the coverage-instrumented set, so the helper carries no share of the 91% floor and these tests are its only check.

## Error handling

- `mktemp -d` failure: `bats isolation: cannot create sentinel under <root>`, `not ok 1 setup_suite`, no test runs, exit 1.
- `setup_suite` failing before `_BATS_SENTINEL` is set, at top level or nested inside a test: step 1's `unset` leaves the variable empty, so `teardown_suite`'s guard prints `bats isolation: no sentinel to check` and touches nothing, including an outer run's sentinel.
- `lib/constants.sh` unreadable or without a `UV_VER` line: the fd-3 message prints and the tests run.
- A test failure with residue: bats exits 1 and reports both the failing test and `not ok … teardown_suite`, so neither signal hides the other.
- Interrupted run (Ctrl-C, `TERM`): bats' `EXIT` trap runs `teardown_suite`, which removes `<s>` (V8).

## Out of scope

- The `${MOCK_CALLS_FILE:-/tmp/mock_calls}` default in the 67 mocks; every bats invocation now gets a per-run file from `setup_suite`.
- XDG residue (operator decision 2026-11-21: gate on HOME only).
- Reordering `load_setup_env` before `export HOME` in the 33 `tests/setup_env/` files that do so; the gate catches any of them that writes `HOME`.
- Teaching `scripts/ci-suite-report.sh` to name a `teardown_suite` failure; its executed-versus-declared mismatch already fails closed, and make's own failure output names the residue.

## Requirements

- **R1.** `tests/helpers/suite_isolation.bash` exists, starts `#!/usr/bin/env bash`, and defines `setup_suite` and `teardown_suite`.
- **R2.** After `setup_suite`, `HOME`, `XDG_CONFIG_HOME`, `XDG_CACHE_HOME`, `XDG_DATA_HOME`, `XDG_STATE_HOME`, `PARALLEL_HOME`, `ZDOTDIR` and `TMPPREFIX` are exported as `<s>/home`, `<s>/xdg/config`, `<s>/xdg/cache`, `<s>/xdg/data`, `<s>/xdg/state`, `<s>/parallel`, `<s>/home` and `<s>/zsh` for one directory `<s>` created by `mktemp -d "${_BATS_SENTINEL_TMP_ROOT:-${TMPDIR:-/tmp}}/bats-sentinel.XXXXXX"` whose path is held in the shell variable `_BATS_SENTINEL`, which is not exported and which `setup_suite` unsets as its first command, the six directories `home`, `xdg/config`, `xdg/cache`, `xdg/data`, `xdg/state` and `parallel` exist under `<s>`, and `GIT_CONFIG_GLOBAL` and `GIT_CONFIG_SYSTEM` are both exported as `/dev/null`.
- **R3.** After `setup_suite`, `MOCK_CALLS_FILE` is `<s>/mock_calls` when the caller left it unset or empty, and the caller's value otherwise.
- **R4.** After `setup_suite`, `PINNED_UV_BIN` is `<pre-swap HOME>/.local/share/dotfiles/pinned/uv-<UV_VER>/uv` when the caller left `PINNED_UV_BIN` unset or empty and that uv binary is executable, and is the caller's value (or unset) otherwise; `<UV_VER>` is read by `sed` from the `UV_VER="…"` line of `${BASH_SOURCE[0]%/*}/../../lib/constants.sh` (resolved from the helper file's own path), without sourcing it, only when that file is readable, and with an empty fallback on a failed read; when the value is empty, `setup_suite` prints `# bats isolation: cannot read UV_VER from <path>` to fd 3, returns 0, and the tests run.
- **R5.** `teardown_suite` first checks that `_BATS_SENTINEL` is non-empty, is a directory, and has a last path component matching `bats-sentinel.*`; otherwise it prints `bats isolation: no sentinel to check` and returns 1 without running `cd`, `find` or `rm`. Otherwise it runs `cd "<s>/home" && find . -mindepth 1 -maxdepth 1`, removes `<s>`, and then: when `cd` or `find` failed, prints `bats isolation: residue check failed` and returns 1; when the listing has at least one entry, prints `bats isolation: a test wrote to the HOME stand-in; redirect HOME in that test's setup()` and then, as its last output line, `residue: <names>`, where `<names>` is every entry's path relative to `<s>/home` without a leading `./`, sorted under `LC_ALL=C` and joined by single spaces, and returns 1; when the listing is empty, prints `# bats isolation: residue check: clean` to fd 3 and returns 0.
- **R6.** A write under `<s>/xdg` or `<s>/parallel` alone never makes `teardown_suite` return non-zero.
- **R7.** When R5's guard passes, `<s>` no longer exists after `teardown_suite` returns, whether the tests passed or failed.
- **R8.** When `mktemp -d` fails, `setup_suite` prints `bats isolation: cannot create sentinel under <root>` and returns 1.
- **R9.** Each of `tests`, `tests/scripts`, `tests/setup_env` and `tests/zshrc.d` holds a regular file (not a symlink) `setup_suite.bash` that starts `#!/usr/bin/env bash` and whose only command is `source "${BASH_SOURCE[0]%/*}/<relative path>/suite_isolation.bash"`, the relative path naming `tests/helpers` from that directory.
- **R10.** `tests/suite_isolation.bats` has a test that fails, naming the directory, for any directory of a path listed in `tests/bats-files.txt` without a `setup_suite.bash` sourcing `suite_isolation.bash`; and tests for each of R2-R8, including one fixture that writes `$HOME/x` and asserts exit 1 with `not ok` `teardown_suite` and `residue: x` in the output, one that writes `${ZDOTDIR}/x` likewise, one failing fixture with residue that asserts both the failing test and the residue line, one clean fixture that asserts `# bats isolation: residue check: clean`, one that writes only under `${XDG_CACHE_HOME}` and asserts exit 0, an R7 test that records `<s>` from inside the fixture, asserts it existed during the run and is gone afterwards, an R8 test with `_BATS_SENTINEL_TMP_ROOT` pointing at a missing directory, two R5 guard tests (empty `_BATS_SENTINEL`, and a canary directory whose name does not match `bats-sentinel.*`) asserting the message and that the canary is unchanged, an inherited-sentinel test that exports `_BATS_SENTINEL` as a planted directory named `bats-sentinel.<x>`, runs a nested `bats` whose `setup_suite` fails on a missing `_BATS_SENTINEL_TMP_ROOT`, and asserts the planted directory still exists, a residue fixture writing three entries that asserts the R5 message line is followed immediately by `residue: <a> <b> <c>` in `LC_ALL=C` order, and an R4 test that runs a copy of the helper from a fixture tree without `lib/constants.sh` and asserts the `cannot read UV_VER` line and that its fixture test is `ok`.
- **R11.** `tests/zshrc.d/unit.bats` `setup()` exports `HOME="${BATS_TEST_TMPDIR}/home"`, creates `${HOME}/.oh-my-zsh/custom/plugins/zsh-autosuggestions`, exports `ZDOTDIR="${HOME}"`, and exports `_OVERRIDE_RBENV_BINARY=/nonexistent/rbenv`.
- **R12.** `tests/bats-files.txt` lists `tests/suite_isolation.bats`.
- **V1.** `make test` and `make bash-coverage` on the finished branch on `claude` each exit 0, and the `make test` output and the `make bash-coverage` `bats_run.log` each contain `# bats isolation: residue check: clean` and no `residue: ` line.
- **V2.** Positive control: on the branch with R11 reverted, `make test-bats` and `make bash-coverage` on `claude` each fail; `make test-bats`'s terminal output and the `make bash-coverage` `bats_run.log` each contain `residue: .oh-my-zsh .rbenv .zcompdump` (the three entries `claude` produced in the round-6 and round-7 prototypes), and `make bash-coverage`'s terminal output contains `not ok` and `teardown_suite` on one line.
- **V3.** CI is green on the PR, including all three `test-macos-shard` legs and all three `test-shard` legs.
- **V4.** Direct-run control: on the branch with R11 reverted, `bats tests/zshrc.d/unit.bats` on `claude` exits 1 with `teardown_suite` naming `.oh-my-zsh` as residue, and the operator's real `~/.zcompdump` mtime is unchanged by the run.
- **V5.** CI positive control: a temporary commit on the PR branch adding a test that writes `$HOME/x` turns at least one `test-shard` leg and one `test-macos-shard` leg red; the macOS leg's job log and the Linux leg's uploaded `test-shard-log-<i>` artifact each contain `residue: x`; the commit is then reverted and V3 is read on the reverted head.
- **V6.** On the Studio, `make test-bats` on the finished branch exits 0 with `# bats isolation: residue check: clean`, and with R11 reverted a direct `bats tests/zshrc.d/unit.bats` exits 1 naming residue.
- **V7.** On `claude`, the Studio and `workstation`, `make test-bats` on the finished branch, run with every variable listed by `env | grep "=${HOME}"` in an agent session pointed at its own empty decoy directory, exits 0 and leaves every decoy empty; a decoy that receives a write gets a named redirect in R2 before merge.
- **V8.** On `claude`, a `bats --jobs 24 --recursive tests/` run sent `TERM` mid-run leaves no `bats-sentinel.*` directory under `${TMPDIR:-/tmp}`.
- **N1.** No mock under `tests/mocks/` changes its `MOCK_CALLS_FILE` default.
- **N2.** No `.bats` file other than `tests/zshrc.d/unit.bats` and the new `tests/suite_isolation.bats` is edited.
- **N3.** `Makefile`, `scripts/run-bash-coverage.sh`, `scripts/ci-suite-report.sh` and `.github/workflows/ci.yml` are not edited.
- **N4.** `setup_suite` reads nothing under the pre-swap `HOME` except R4's executable check of the uv binary and files inside this repository, and `setup_suite` and `teardown_suite` create, modify or remove no file outside `<s>`; writes to stdout, stderr, fd 3 and the coverage tracer's own fd 9 are not file writes for this purpose.

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

### Round 6

Reviewed at commit: `c6496585` (round-5 revision)

#### Goal-Fit

Finding: the design's reason for leaving direct `bats` runs unwrapped was wrong. The gate forbids repeat writes, but a new test runs directly first (TDD red and green, CLAUDE.md's Studio repro), so an F15-class test writes the real `HOME` before `make test` sees it. bats' own `setup_suite`/`teardown_suite` covers every invocation, including direct runs, with no Makefile, coverage-script or CI change, and removes the recipe-text machinery (R14's unwrap helper and its 10 sites, V4, V6, the shim change, R10's log routing, R16) where every earlier round had found a new hole.
Assumption: the macOS runner's bats supports suite hooks, and `make bash-coverage` reports a `teardown_suite` failure; both verified before the switch (bats-core 1.14.0 on `macos-latest`; `bats_run.log` held `not ok 3 teardown_suite` and the script refused to score).
Disposition: Addressed (operator, 2026-11-21): the design moves to suite hooks. Design, Error handling, Out of scope and the Requirements block are rewritten; R1-R16, V1-V7 and N1-N3 of rounds 1-5 are superseded by the block above (R2-R4, R6-R8, R11 and V7 carry over with the wrapper replaced by the hooks). The prototype in Measurements adds three items the switch needed: `PARALLEL_HOME` is load-bearing (`.parallel` residue without it), the per-directory hook is a sourcing regular file rather than a symlink (a symlink resolved `lib/constants.sh` from the wrong directory), and `teardown_suite` guards an unset or foreign sentinel (an unguarded prototype listed `/home` and ran `rm -rf ""` after `setup_suite` failed).

#### Ergonomics

Finding: R16 still let the macOS shard go green on a red run: a grep placed between `ci-suite-report.sh` and `report_rc=$?` met R16's words and overwrote `report_rc` with grep's 0. Minor: `_unwrap_bats_lines` missed `$(BATS) …`, `cd x && bats` and `FOO=1 bats`, and the R4 empty-read branch was testable only on a wrapper copy, outside the coverage floor.
Assumption: no new assumption.
Disposition: Addressed (operator, 2026-11-21): moot under the suite-hook design, which edits neither `ci.yml` nor the makefile tests (N3, N2); the empty-read branch is tested on a helper copy (R10), and `tests/` carries no coverage share.

#### Risk

Finding: the same R16 masking defect, independently. Confirmed elsewhere: full suite under the wrapper with 8 home-pointing variables decoyed, 4284 ok, clean, every decoy empty, 2:17; R11 reverted shows `.zcompdump .rbenv .oh-my-zsh`.
Assumption: round 2's runner-residue assumption (Accepted); V3, V5 and V6 settle it.
Disposition: Addressed (operator, 2026-11-21): as Ergonomics.

#### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.

### Round 7

Reviewed at commit: `1d7629bc` (round-6 revision, suite hooks)

#### Goal-Fit

Finding: `_BATS_SENTINEL` was exported, so a nested bats run inherited the outer value; when the nested `setup_suite` failed before `mktemp` (the spec's own R8 test), its `teardown_suite` passed the guard on the outer sentinel and deleted it while sibling tests ran, turning every `make test` red. Prototype: `REMOVED .../bats-sentinel.Vlxvsw`. Hook resolution, the four hook directories and every existing nested bats run were checked and hold.
Assumption: `setup_suite` and `teardown_suite` share one shell on bats 1.14.0 as on 1.13.0; settled by diffing the two tags.
Disposition: Addressed (operator, 2026-11-21): `setup_suite` unsets `_BATS_SENTINEL` first and never exports it (Design §1 step 1, R2); R10 adds an inherited-sentinel test.

#### Ergonomics

Finding: (1) on the coverage path only `tail -3` of `bats_run.log` is printed, so one residue name per line hid the rest and V2 could not pass; (2) bats runs `setup_suite` under `set -eET`, so R4's empty-`UV_VER` branch aborted before its message; (3) R4's "that file is executable" read as `constants.sh` (mode 644), and N4 forbade reading the repo, which lives under `HOME`.
Assumption: the hooks behave the same on macOS under `--jobs`; V6 measures it.
Disposition: Addressed (operator, 2026-11-21): R4 guards the read, returns 0 and names the uv binary; N4 excepts files inside the repository; R5 prints one sorted `residue:` line. The full-suite re-run then showed bats' end-of-run warning block after that line, so no output shape survives `tail -3`; the operator chose to accept that (option A: no change to `run-bash-coverage.sh`), V2 reads the coverage names from `bats_run.log`, and V5 becomes a CI positive control.

#### Risk

Finding: the same inherited-sentinel deletion, independently prototyped (`# OUTER SENTINEL DESTROYED`); the same errexit abort; and `teardown_suite` runs with errexit off, so a failed `cd` would let `find` list bats' working directory.
Assumption: as Goal-Fit; settled.
Disposition: Addressed (operator, 2026-11-21): as Goal-Fit and Ergonomics; R5 requires `cd … && find` and treats a failed `cd` as a failed check.

#### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.
