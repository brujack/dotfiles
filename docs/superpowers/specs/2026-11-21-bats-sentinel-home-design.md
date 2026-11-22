# Bats suite under a sentinel HOME — design

- **Date:** 2026-11-21
- **Source:** security audit 2026-11-16, findings F15-F20 (ai-config `docs/knowledge/dotfiles-security-audit-2026-11-16.md`); F15 fixed in dotfiles#475.
- **Approved:** 2026-11-21

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

Linux `workstation` (7950X, one `git clone` of d1e648f7, `bats --jobs 24 --recursive tests/` under the same sentinel environment with the linuxbrew prefix on `PATH`, 2026-11-21): 4284 ok, 0 not ok, exit 0. `HOME` residue: `.rbenv/{shims,versions}`, `.zcompdump` and `.oh-my-zsh/custom/plugins`; a per-file probe attributed all three to `tests/zshrc.d/unit.bats` alone, so R10's `HOME` redirect contains them.

bats' own suite hooks (2026-11-21, `claude`, bats 1.13.0; one `git clone` of 348a1d3e with a prototype of the design below):

- `bats` resolves `setup_suite.bash` from the directory of the first argument that holds one (`libexec/bats-core/bats`, the `potential_setup_suite_file` loop), so `--recursive tests/` uses `tests/setup_suite.bash` and a direct `bats tests/setup_env/x.bats` uses `tests/setup_env/setup_suite.bash`. `setup_suite` runs once per invocation, before GNU parallel starts under `--jobs`; `teardown_suite` runs from bats' `EXIT` trap, also when `setup_suite` failed.
- Full suite, `bats --jobs 24 --recursive tests/`, R2's redirects in `setup_suite`, R10 not applied (R11 at the time): 4284 ok, then `not ok 4285 teardown_suite` naming `.rbenv`, `.zcompdump` and `.oh-my-zsh`, exit 1, 2:18; the sentinel was removed. This is the same residue the `workstation` row above attributes to `tests/zshrc.d/unit.bats`.
- `make bash-coverage` (the CI `test-shard` shape: `BATS_FILES_FROM` and `COVERAGE_TRACE_DIR` in the environment) over one fixture file writing `$HOME/x`: `bats_run.log` holds `not ok 3 teardown_suite` and the residue lines, and `scripts/run-bash-coverage.sh` printed both and refused to score (exit 2 from make). With the write removed it exited 0, in parallel and in serial mode (`HAVE_PARALLEL=`).
- `PARALLEL_HOME` keeps GNU parallel's state out of the stand-in `HOME`: without it the same coverage run also reported `.parallel` as residue, because GNU parallel starts after `setup_suite` has swapped `HOME`.
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
2. Before the swap, read `UV_VER` with `sed -n 's/^UV_VER="\(.*\)"$/\1/p'` from `${BASH_SOURCE[0]%/*}/../../lib/constants.sh` (the helper's own repo, whatever the caller's directory), never by sourcing it, and only when that file is readable (`[[ -r ]]`), with `|| ` an empty fallback so a failed read cannot abort the suite. When the value is empty, print `# bats isolation: cannot read UV_VER from <path>` to fd 3, leave `PINNED_UV_BIN` alone and continue with steps 3 and 4 (never an early return, which would run the suite against the real `HOME`), so the later `resolve_pinned_uv` failure is not mistaken for a missing install. Otherwise, if `PINNED_UV_BIN` is unset or empty and the uv binary `${HOME}/.local/share/dotfiles/pinned/uv-${UV_VER}/uv` is executable, export `PINNED_UV_BIN` as that binary's path.
3. Create one sentinel directory with `mktemp -d "${_BATS_SENTINEL_TMP_ROOT:-${TMPDIR:-/tmp}}/bats-sentinel.XXXXXX"` (the seam exists because BSD `mktemp -d` with a template ignores `TMPDIR`) and hold its path in the shell variable `_BATS_SENTINEL`, never exported, and create `home/`, `xdg/config`, `xdg/cache`, `xdg/data`, `xdg/state` and `parallel/` in it. On failure print `bats isolation: cannot create sentinel under <root>` and return 1; bats then reports `not ok 1 setup_suite` and runs no test.
4. Export `HOME=<s>/home`, `XDG_CONFIG_HOME=<s>/xdg/config`, `XDG_CACHE_HOME=<s>/xdg/cache`, `XDG_DATA_HOME=<s>/xdg/data`, `XDG_STATE_HOME=<s>/xdg/state`, `PARALLEL_HOME=<s>/parallel`, `ZDOTDIR=<s>/home`, `TMPPREFIX=<s>/zsh`, `GIT_CONFIG_GLOBAL=/dev/null`, `GIT_CONFIG_SYSTEM=/dev/null`, and `MOCK_CALLS_FILE=<s>/mock_calls` when the caller's `MOCK_CALLS_FILE` is unset or empty.

`teardown_suite`:

1. Guard: unless `_BATS_SENTINEL` is non-empty, names a directory, and its last path component matches `bats-sentinel.*`, print `bats isolation: no sentinel to check` and return 1 without running `rm` (bats runs `teardown_suite` even when `setup_suite` failed).
2. Run `rm -rf <s>`, then judge the removal by `[[ -e <s> ]]`, never by `rm`'s exit status: `tests/mocks/rm` ends `/bin/rm "$@" 2>/dev/null || true`, so a nested run with the mocks on `PATH` gets status 0 from a removal that failed. When `<s>` still exists, print `bats isolation: cannot remove <s>; run: chmod -R u+w <s> && rm -rf <s>` and return 1; otherwise return 0.

There is no residue check (operator decision 2026-11-21, external review F1.1). The swap in `setup_suite` is what keeps tests off the real `HOME`: a test that writes `$HOME` after it writes the sentinel, which is discarded. A residue failure would fire on writes that harmed nothing and would enforce the per-file "redirect HOME in `setup()`" convention the Problem section calls a failure; its one real benefit, keeping files that one test leaves in the shared sentinel `HOME` from affecting another test in the same run, is unmeasured today (with R10, no file leaves any) and does not justify the apparatus.

`ZDOTDIR` is redirected by name because zsh writes `.zcompdump` to `${ZDOTDIR:-$HOME}` and every `zsh` reads `${ZDOTDIR}/.zshenv`: with the operator's `ZDOTDIR=$HOME` exported (as on `claude`), `tests/zshrc.d/unit.bats` rewrote the real `~/.zcompdump` while `HOME` pointed at the sentinel. Other exported variables that point into the home are measured by V5 rather than scanned at run time: a generic unset would change 17 variables (on `claude`) the suite has never run without, and a generic warning would print on every run.

How a hook failure surfaces, with no change to any path: a failed `setup_suite` is `not ok 1 setup_suite` and runs no test; a failed `teardown_suite` is `not ok <n+1> teardown_suite` with its message; either makes bats exit 1, so `make test`, `make bash-coverage` (which refuses to score a red run) and both CI shard types fail. `scripts/ci-suite-report.sh` additionally reports one more executed test than declared, which also fails closed.

### 2. F16 fix

`tests/zshrc.d/unit.bats` `setup()` exports `HOME="${BATS_TEST_TMPDIR}/home"`, creates `${HOME}/.oh-my-zsh/custom/plugins/zsh-autosuggestions`, exports `ZDOTDIR="${HOME}"`, and exports `_OVERRIDE_RBENV_BINARY=/nonexistent/rbenv`. Tests that set their own `_fake_home` override it after `setup()`, unchanged.

### 3. Tests: `tests/suite_isolation.bats`

A coverage guard reads `tests/bats-files.txt` and fails, naming the directory, for any directory holding a listed `.bats` file that lacks a `setup_suite.bash` sourcing the helper; a new test directory without one would otherwise run unisolated. A top-level test asserts that its own `HOME` lies under a `bats-sentinel.*` directory, so every run that includes the file proves the hook ran. The behaviour tests run a nested `bats` over fixture `.bats` files in a fixture directory under `BATS_TEST_TMPDIR` whose `setup_suite.bash` sources the real helper by absolute path; the nested run's pre-swap `HOME` is the outer suite's sentinel, so nothing here reaches the real `HOME`. Every hand-made sentinel or canary these tests create lives under `BATS_TEST_TMPDIR`. `tests/` is outside the coverage-instrumented set, so the helper carries no share of the 91% floor and these tests are its only check.

## Error handling

- `mktemp -d` failure: `bats isolation: cannot create sentinel under <root>`, `not ok 1 setup_suite`, no test runs, exit 1.
- `setup_suite` failing before `_BATS_SENTINEL` is set, at top level or nested inside a test: step 1's `unset` leaves the variable empty, so `teardown_suite`'s guard prints `bats isolation: no sentinel to check` and touches nothing, including an outer run's sentinel.
- `lib/constants.sh` unreadable or without a `UV_VER` line: the fd-3 message prints and the tests run.
- Sentinel not removable (a test left a directory without write permission under it): `not ok … teardown_suite` with the `chmod -R u+w` remedy.
- Interrupted run (Ctrl-C, `TERM` to the process group): bats' `EXIT` trap runs `teardown_suite`, which removes `<s>` (V6). A `TERM` to the top `bats` process alone leaves `bats-exec-suite` running; it finishes the suite and removes `<s>` then (round-8 prototype: about 20 s later).

## Out of scope

- The `${MOCK_CALLS_FILE:-/tmp/mock_calls}` default in the 67 mocks; every bats invocation now gets a per-run file from `setup_suite`.
- Any residue check on the sentinel `HOME` or XDG dirs (operator decisions 2026-11-21: gate on HOME only, then no residue gate at all, external review F1.1).
- Reordering `load_setup_env` before `export HOME` in the 33 `tests/setup_env/` files that do so; any `HOME` write they make lands in the sentinel.
- Teaching `scripts/ci-suite-report.sh` to name a `teardown_suite` failure; its executed-versus-declared mismatch already fails closed.

## Requirements

- **R1.** `tests/helpers/suite_isolation.bash` exists, starts `#!/usr/bin/env bash`, and defines `setup_suite` and `teardown_suite`.
- **R2.** After `setup_suite`, `HOME`, `XDG_CONFIG_HOME`, `XDG_CACHE_HOME`, `XDG_DATA_HOME`, `XDG_STATE_HOME`, `PARALLEL_HOME`, `ZDOTDIR` and `TMPPREFIX` are exported as `<s>/home`, `<s>/xdg/config`, `<s>/xdg/cache`, `<s>/xdg/data`, `<s>/xdg/state`, `<s>/parallel`, `<s>/home` and `<s>/zsh` for one directory `<s>` created by `mktemp -d "${_BATS_SENTINEL_TMP_ROOT:-${TMPDIR:-/tmp}}/bats-sentinel.XXXXXX"` whose path is held in the shell variable `_BATS_SENTINEL`, which is not exported and which `setup_suite` unsets as its first command, the six directories `home`, `xdg/config`, `xdg/cache`, `xdg/data`, `xdg/state` and `parallel` exist under `<s>`, and `GIT_CONFIG_GLOBAL` and `GIT_CONFIG_SYSTEM` are both exported as `/dev/null`.
- **R3.** After `setup_suite`, `MOCK_CALLS_FILE` is `<s>/mock_calls` when the caller left it unset or empty, and the caller's value otherwise.
- **R4.** After `setup_suite`, `PINNED_UV_BIN` is `<pre-swap HOME>/.local/share/dotfiles/pinned/uv-<UV_VER>/uv` when the caller left `PINNED_UV_BIN` unset or empty and that uv binary is executable, and is the caller's value (or unset) otherwise; `<UV_VER>` is read by `sed` from the `UV_VER="…"` line of `${BASH_SOURCE[0]%/*}/../../lib/constants.sh` (resolved from the helper file's own path), without sourcing it, only when that file is readable, and with an empty fallback on a failed read; when the value is empty, `setup_suite` prints `# bats isolation: cannot read UV_VER from <path>` to fd 3, leaves `PINNED_UV_BIN` alone, and continues with the sentinel steps (R2, R3), so the tests run under the sentinel `HOME`.
- **R5.** `teardown_suite` first checks that `_BATS_SENTINEL` is non-empty, is a directory, and has a last path component matching `bats-sentinel.*`; otherwise it prints `bats isolation: no sentinel to check` and returns 1 without running `rm`. Otherwise it runs `rm -rf <s>` and judges the removal by whether `<s>` still exists (`[[ -e ]]`), not by `rm`'s exit status: when `<s>` still exists it prints `bats isolation: cannot remove <s>; run: chmod -R u+w <s> && rm -rf <s>` (with the path in both places) and returns 1; otherwise it returns 0. It neither lists nor inspects the contents of `<s>`.
- **R6.** When R5's guard passes and `teardown_suite` does not print `bats isolation: cannot remove`, `<s>` no longer exists after it returns, whether the tests passed or failed.
- **R7.** When `mktemp -d` fails, `setup_suite` prints `bats isolation: cannot create sentinel under <root>` and returns 1.
- **R8.** Each of `tests`, `tests/scripts`, `tests/setup_env` and `tests/zshrc.d` holds a regular file (not a symlink) `setup_suite.bash` that starts `#!/usr/bin/env bash` and whose only command is `source "${BASH_SOURCE[0]%/*}/<relative path>/suite_isolation.bash"`, the relative path naming `tests/helpers` from that directory.
- **R9.** `tests/suite_isolation.bats` has: a test that fails, naming the directory, for any directory of a path listed in `tests/bats-files.txt` without a `setup_suite.bash` sourcing `suite_isolation.bash`; a top-level test asserting its own `HOME` matches `*/bats-sentinel.*/home`; and nested-fixture tests (fixture directory and every hand-made sentinel or canary under `BATS_TEST_TMPDIR`) for each of R2-R7: one asserting the R2 and R3 values from inside a fixture test; an R6 test that records `<s>` from inside the fixture, asserts it existed during the run and is gone afterwards; an R7 test with `_BATS_SENTINEL_TMP_ROOT` pointing at a missing directory; two R5 guard tests (empty `_BATS_SENTINEL`, and a canary directory whose name does not match `bats-sentinel.*`) asserting the message and that the canary is unchanged; an inherited-sentinel test that exports `_BATS_SENTINEL` as a planted directory named `bats-sentinel.<x>`, runs a nested `bats` whose `setup_suite` fails on a missing `_BATS_SENTINEL_TMP_ROOT`, and asserts the planted directory still exists and the nested output contains both `bats isolation: cannot create sentinel under` and `bats isolation: no sentinel to check`; an R4 test that runs a copy of the helper from a fixture tree without `lib/constants.sh` and asserts the `cannot read UV_VER` line, exit 0, and that the fixture test saw `HOME` under a `bats-sentinel.*` directory; and an R5 removal-failure test whose sentinel is a directory named `bats-sentinel.<x>`, which calls `teardown_suite` with a `rm` shim first on `PATH` that exits 0 and removes nothing, asserts `bats isolation: cannot remove` and return 1, and removes that directory itself afterwards.
- **R10.** `tests/zshrc.d/unit.bats` `setup()` exports `HOME="${BATS_TEST_TMPDIR}/home"`, creates `${HOME}/.oh-my-zsh/custom/plugins/zsh-autosuggestions`, exports `ZDOTDIR="${HOME}"`, and exports `_OVERRIDE_RBENV_BINARY=/nonexistent/rbenv`.
- **R11.** `tests/bats-files.txt` lists `tests/suite_isolation.bats`.
- **V1.** `make test` and `make bash-coverage` on the finished branch on `claude` each exit 0. Run once more with `R=$(mktemp -d)` and `_BATS_SENTINEL_TMP_ROOT="$R" make test-bats` (a per-command prefix, never exported, so the checking shell's own environment does not hold the root): 60 seconds after it exits, `find "$R" -name 'bats-sentinel.*'`, `pgrep -f -- "[${R:0:1}]${R:1}"` (the bracket keeps the pattern from matching the command line of the shell that runs it) and, on Linux, `grep -l "$R" /proc/[0-9]*/environ 2>/dev/null` all return nothing.
- **V2.** Positive control for the goal, on `claude` in a throwaway clone of the finished branch: a probe file `tests/zz_probe.bats` whose one test runs `touch "${HOME}/sentinel-probe-<random>"` is run directly (`bats tests/zz_probe.bats`) and through `BATS_FILES_FROM=<list naming it> make test-bats`; after each, the operator's real `~/sentinel-probe-<random>` does not exist. The same probe run in a clone of `origin/master` (no hooks) does create it, and is then deleted, which shows the probe can reach the real home.
- **V3.** CI is green on the PR, including all three `test-macos-shard` legs and all three `test-shard` legs, and one `test-shard` leg's `bats_run.log` (or job log) shows `ok` for R9's top-level `HOME`-under-sentinel test.
- **V4.** On the Studio, `make test-bats` on the finished branch exits 0, and V2's direct-run probe leaves the real `~/sentinel-probe-<random>` absent.
- **V5.** On `claude` (agent session), and on the Studio and `workstation` (interactive `zsh -i` over ssh), `make test-bats` on the finished branch exits 0 and leaves every decoy empty when run with each decoyed variable pointed at its own empty decoy directory. The decoyed variables are those listed by `env | grep "=${HOME}"` in that environment whose value is a single absolute path to a directory under `$HOME`; excluded and named in the evidence are `HOME`, `PWD`, `OLDPWD`, every colon-separated list (`PATH`, `FPATH`), and every value that is not a directory (`SSH_AUTH_SOCK`, a file such as `ANSIBLE_VAULT_PASSWORD_FILE`). A run without decoys comes first; any `not ok` that appears only with decoys is a test broken by a decoy, recorded and resolved. A decoy that receives a write gets a named redirect in R2 before merge.
- **V6.** On `claude`, with `_BATS_SENTINEL_TMP_ROOT` pointing at a private empty directory, a `bats --jobs 24 --recursive tests/` run started in its own process group (`setsid`) is observed to have created at least one `bats-sentinel.*` under that root, is then sent `TERM` to its process group mid-run, and within 10 seconds of exiting leaves no `bats-sentinel.*` directory under that root.
- **V7.** Writes that bypass `HOME` (`ssh` reads the home from the passwd database, macOS `defaults` ignores `HOME`), which neither the sentinel nor V5 can see. On `claude` and `workstation`: `strace -f -qq -e trace=%file -e status=successful -o <log> make test-bats < /dev/null` from a clone outside `$HOME`, then every logged call that creates, writes, renames, links or removes (`openat`/`open` with `O_WRONLY`, `O_RDWR` or `O_CREAT`, and `mkdir*`, `rename*`, `link*`, `symlink*`, `unlink*`, `rmdir`, `truncate`) on a path under the real `$HOME` is listed; the list is empty. On the Studio: `find "$HOME" -xdev -newer <stamp>` and `find ~/Library/Preferences -newer <stamp>` after `make test-bats`, diffed against the same two commands over an equal-length window with no suite running; the difference is empty.
- **N1.** No mock under `tests/mocks/` changes its `MOCK_CALLS_FILE` default.
- **N2.** No `.bats` file other than `tests/zshrc.d/unit.bats` and the new `tests/suite_isolation.bats` is edited in the branch (V2's probe lives only in a throwaway clone).
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

### Round 8

Reviewed at commit: `4b5868cb` (round-7 revision)

#### Goal-Fit

Finding: no load-bearing issue; the round-7 fixes hold. A clone run of the full R2 environment gave 4284 ok, 0 not ok and no added skip, with residue exactly `.oh-my-zsh .rbenv .zcompdump` (V2's string). Minor: R5 did not say the `cd` runs in a subshell.
Assumption: none genuinely uncertain; a change in bats' hook resolution on `macos-latest` would turn R10's nested fixtures red.
Disposition: Addressed (operator, 2026-11-21): R5 and Design §1 put the `cd` inside the command substitution explicitly.

#### Ergonomics

Finding: (1) R4's "returns 0" read as an early return that skips the sentinel; a prototype ran its fixture against the real `HOME` (`HOME=/home/bruce`) while R10's R4 test passed. (2) V5 named no file for the `$HOME/x` writer; 54 of 114 files redirect `HOME` themselves, and a new file trips `check-bats-manifest` first.
Assumption: that `cd` into `<s>/home` then `rm -rf <s>` leaves bats in a deleted directory; refuted, the `cd` runs inside `$(…)`.
Disposition: Addressed (operator, 2026-11-21): R4 and Design §1 say the hook continues with the sentinel steps, and R10's R4 test asserts exit 0 and the clean marker; V5 names `tests/suite_isolation.bats`.

#### Risk

Finding: (1) V5 as written could not be pushed without bypassing the pre-push hook, and a failed control would auto-merge the `$HOME/x` writer. (2) V8 passed when no sentinel was ever made and depended on which process got `TERM` (top `bats` only: sentinel removed about 20 s later by the orphaned `bats-exec-suite`; process group: removed at once). (3) `teardown_suite` ignored `rm -rf`'s status. (4) V7's population included `HOME`, `PWD` and `OLDPWD` and did not require the clean marker.
Assumption: no test-started process outlives the run and writes into, or recreates, the sentinel.
Disposition: Addressed (operator, 2026-11-21): V5 guards the write on `GITHUB_ACTIONS` and keeps the PR in draft until the revert head is green and Phase 3 is done; V8 uses a private root, observes the sentinel and signals the process group; R5 reports a failed removal; V7 excludes the three variables and requires the clean marker; V1 adds a 60-second post-run check for leftover sentinels and processes.

#### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.

### Round 9

Reviewed at commit: `e9e1be20` (round-8 revision)

#### Goal-Fit

Finding: the design meets its goal; the round-8 fixes to R4, R5, V5 and V8 hold. V7 could not run on `workstation`: its `PATH` starts at `/home/bruce/.pyenv/plugins/pyenv-virtualenv/shims`, so the grep lists `PATH`, and decoying it hides `make`; `SSH_AUTH_SOCK` (a socket) and `FPATH` (a list) cannot be decoyed as directories either, and the Studio hosts no agent session. Minor: R5 reported a failed removal instead of the residue names; V1's `pgrep -f` cannot see a process holding the root only in its environment.
Assumption: every test write into the home goes through `HOME` or a variable V7 enumerates; V7 settles it once runnable.
Disposition: Addressed (operator, 2026-11-21): V7 decoys only single-path directory variables, names the exclusions, and runs from `zsh -i` over ssh on the Studio and `workstation`; V1 adds a `/proc/*/environ` search on Linux.

#### Ergonomics

Finding: (1) R5's order hid the residue names and the remedy exactly when a removal fails, whose usual cause is residue (58 write-removing `chmod` calls in `tests/`). (2) R10 did not say where its hand-made sentinels live, so the removal-failure test could leak a `bats-sentinel.*` into `/tmp` on every run and trip V1. Minor: V8's "one" sentinel should be "at least one" because nested fixtures inherit the root.
Assumption: a failing `teardown_suite`'s lines follow `not ok N teardown_suite` in the macOS log; V5's CI half settles it.
Disposition: Addressed (operator, 2026-11-21): R5 lists first and prints residue, then the removal failure; R10's hand-made sentinels live under `BATS_TEST_TMPDIR` and the removal-failure test plants an entry and cleans up; V8 says "at least one".

#### Risk

Finding: `tests/mocks/rm` always exits 0, so a removal judged by `rm`'s status is silent under any nested run with the mocks on `PATH` (prototype: a `chmod 555` subdirectory survived, `rc=0`); R7 contradicted R5's removal-failure branch. Minor: V1's `pgrep -f` blind spot; the R10 removal test's `/tmp` leak.
Assumption: every `teardown_suite` runs with an `rm` that reports failure truthfully; refuted where `tests/mocks` is on `PATH`.
Disposition: Addressed (operator, 2026-11-21): R5 judges removal by `[[ -e <s> ]]`, and R10's shim exits 0 while removing nothing, so it tests exactly that; R7 is qualified by the `cannot remove` branch.

#### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.

### Round 10

Reviewed at commit: `1dde8f50` (round-9 revision)

#### Goal-Fit

Finding: the design meets its goal; the round-9 changes hold. (1) V1's leftover-process check matched the checking shell itself: `pgrep -f` with the root written literally returned the wrapping shells, and `/proc/*/environ` returned grep's own process when the root was exported. (2) R5's `residue check failed` branch had no R10 test, so an implementation discarding the listing's status (`local x=$(…)`) would report a test running `rm -rf "$HOME"` as clean.
Assumption: none genuinely uncertain.
Disposition: Addressed (operator, 2026-11-21): V1 passes the root as a per-command prefix and uses a self-excluding `pgrep` pattern; R10 adds the `rm -rf "${HOME}"` fixture.

#### Ergonomics

Finding: (1) the same V1 self-match, measured in the agent shell, plus missing commas in V1. (2) On a tty bats' pretty formatter prints `${line:2}`, so the clean marker loses its `# ` and V6 (and V7 over `ssh -t`) would grep for text that is absent. Minor: `cannot remove` named no remedy.
Assumption: V7's decoys leave every test passing on the Studio and `workstation`.
Disposition: Addressed (operator, 2026-11-21): V1, V6 and V7 match the marker without `# `; R5's message carries `run: chmod -R u+w <s> && rm -rf <s>`; V7 runs a no-decoy baseline first.

#### Risk

Finding: (1) the inherited-sentinel test passed when the fixture's hook failed to source the helper (prototype: `not ok 1 setup_suite`, planted directory survived), and the XDG test asserted only exit 0. (2) The guard test's canary had no required location, so a regressed guard could delete it wherever it pointed.
Assumption: no test writes the operator's home through a path other than `HOME` or a V7 variable (`ssh`'s passwd lookup, macOS `defaults`).
Disposition: Addressed (operator, 2026-11-21): the inherited test also asserts `cannot create sentinel under` and `no sentinel to check`, the XDG test asserts the clean marker, the canary lives under `BATS_TEST_TMPDIR`; V9 measures home writes against a timestamp on three boxes. Further lens rounds stopped here by operator decision: rounds 8-10 found only defects in the previous round's verification wording and test assertions, and Step 8.5's external review re-reads the whole spec.

#### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.

## External Review

### Round 1 (reviewed at `b6bfca4ff0d8aa857f9ce8ec6c860d471ed8ccb1`)

Report: [round1.md](2026-11-21-bats-sentinel-home-design.external-review/round1.md) (its requirement IDs are those at the reviewed SHA)

#### Author response

| finding | disposition | evidence | reviewer verdict | operator (Step 9) |
| ------- | ----------- | -------- | ---------------- | ----------------- |
| F1.1 | Fixed | Operator chose to drop the residue gate (2026-11-21). `teardown_suite` now only guards and removes the sentinel (R5, R6); the residue branch, the XDG-residue requirement, the residue fixtures, the `residue check failed` fixture, the clean marker and the residue-based controls (old V2, V4, V5 and V6's second half) are deleted; Design §1 states that the swap is what protects the real `HOME`. New V2 is a direct positive control on the goal: a probe test touching `$HOME/sentinel-probe-<random>` leaves the real home untouched on the branch and reaches it on `origin/master`. R9 adds a top-level test asserting `HOME` lies under `bats-sentinel.*`, so every run proves the hook ran. | unjudged | |
| F1.2 | Fixed | V7 (was V9) uses `strace -f -qq -e trace=%file -e status=successful` on `claude` and `workstation` (strace 6.19 present on both, `ptrace_scope` 1) and lists write-flagged calls under the real `$HOME`; the Studio diffs `find -newer` against an equal-length window with no suite. | unjudged | |

Stopped: reviewer recommended stopping in round 1

## Amendments

- finding R9 (2026-11-22, reviewer A): DIFFERS — All required tests exist, but the inherited-sentinel test asserts only the substrings 'cannot create sentinel under' and 'no sentinel to check', not the spec's literal 'bats isolation: cannot create sentinel under' and 'bats isolation: no sentinel to check', so it would pass on output lacking the 'bats isolation:' prefix (the other tests assert the full strings).
- R9 reviewed: the `bats isolation: ` prefix of both messages is pinned by other tests in tests/suite_isolation.bats: the mktemp-failure test asserts `bats isolation: cannot create sentinel under` and the three guard tests assert `bats isolation: no sentinel to check`, so a helper dropping the prefix fails four tests; the inherited-sentinel test's job is that the planted directory survives and both branches ran, which its substring checks establish.
- V7 -> Writes that bypass `HOME` (`ssh` reads the home from the passwd database, macOS `defaults` ignores `HOME`), which neither the sentinel nor V5 can see. On `claude` and `workstation`: `strace -f -qq -e trace=%file -e status=successful -o <log> make test-bats < /dev/null` from a clone outside `$HOME`, then every logged call that creates, writes, renames, links or removes (`openat`/`open` with `O_WRONLY`, `O_RDWR` or `O_CREAT`, and `mkdir*`, `rename*`, `link*`, `symlink*`, `unlink*`, `rmdir`, `truncate`) on a path under the real `$HOME` is listed; the list is empty. On the Studio: `find "$HOME" -xdev -newer <stamp>` and `find ~/Library/Preferences -newer <stamp>` after `make test-bats`, diffed against the same two commands over a window of equal length with no suite running; the difference contains no entry attributable to the suite, and every remaining entry is named and attributed to its owning process or app in the evidence. — on a Mac with desktop apps open, macOS services and apps write to ~/Library continuously, so an empty difference is unreachable (2026-11-22 run: 166 entries, all Photos/mediaanalysisd, caches, desktop apps and three Preferences plists, none suite-attributable); the precise instrument, fs_usage, needs sudo (operator decision 2026-11-22).

## Spec alignment (2026-11-22)

- spec: docs/superpowers/specs/2026-11-21-bats-sentinel-home-design.md
- anchor: 4124de9ff48ade717f1afd82b8573ca1b58b38e0
- in scope: R1, R2, R3, R4, R5, R6, R7, R8, R9, R10, R11
- out of scope: none

### Findings

| ID | Reviewer | Verdict | Reason | Amendment |
| --- | --- | --- | --- | --- |
| R9 | A | DIFFERS | All required tests exist, but the inherited-sentinel test asserts only the substrings 'cannot create sentinel under' and 'no sentinel to check', not the spec's literal 'bats isolation: cannot create sentinel under' and 'bats isolation: no sentinel to check', so it would pass on output lacking the 'bats isolation:' prefix (the other tests assert the full strings). | - R9 reviewed: the `bats isolation: ` prefix of both messages is pinned by other tests in tests/suite_isolation.bats: the mktemp-failure test asserts `bats isolation: cannot create sentinel under` and the three guard tests assert `bats isolation: no sentinel to check`, so a helper dropping the prefix fails four tests; the inherited-sentinel test's job is that the planted directory survives and both branches ran, which its substring checks establish. |

### Reviewed

- R9 reviewed: the `bats isolation: ` prefix of both messages is pinned by other tests in tests/suite_isolation.bats: the mktemp-failure test asserts `bats isolation: cannot create sentinel under` and the three guard tests assert `bats isolation: no sentinel to check`, so a helper dropping the prefix fails four tests; the inherited-sentinel test's job is that the planted directory survives and both branches ran, which its substring checks establish.

### Verifications

- V1: no evidence recorded
- V2: no evidence recorded
- V3: no evidence recorded
- V4: no evidence recorded
- V5: no evidence recorded
- V6: no evidence recorded
- V7: no evidence recorded
