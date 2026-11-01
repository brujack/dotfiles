# load_mocks setup trim

- **Date:** 2026-11-01
- **Approved:** 2026-11-01
- **Backlog row:** "bats process-spawn cost (part 2 of the setup floor)". The operator chose option 3: this setup trim first, as its own PR, and test-body spawn counts as a later spec.

## Problem

Per-test setup is about a fifth of the bats suite's CPU. Measured on `claude` (bats 1.13, synthetic
100-test files, `bats --jobs 1`, CPU per test):

| Layer                           | CPU per test |
| ------------------------------- | ------------ |
| bats' own floor (empty `setup`) | 27 ms        |
| + `load_mocks`                  | 86-93 ms     |
| + `load_setup_env`              | 172 ms       |

Two costs make up `load_mocks`, and the second one does not show in an exec count:

- **External execs.** `strace -f -e execve` on one call finds about 20 (outside bats):
  - five stub scripts (`brew-az`, `brew-stub`, `sysctl-stub`, `systemctl-stub`, `findmnt-stub`), each
    written with a `cat` heredoc and then `chmod +x`, for 10 execs. Four have fixed contents that read
    the environment when they run. Only `brew-stub` expands `BATS_TEST_TMPDIR` when written;
  - separate `mkdir -p` calls;
  - the ai-config fixture (`track_ai_config_fixture`): `mkdir`, `find`, `git init` and `git add`.
- **Per-command overhead.** bats traces every command a test runs through a DEBUG trap. 100 bare `:`
  commands in `setup` cost 12 ms per test. The `for` loop that filters `tests/mocks` out of `PATH`
  before resolving the real git is fork-free and still costs about 13 ms per test. The same filter
  done with parameter expansion costs about 2 ms.

Measured by the round-1 Goal-fit lens, on variants of `common.bash` with parts cut out (CPU per
test, mean of 3 runs):

| `setup`                                          | CPU per test        |
| ------------------------------------------------ | ------------------- |
| `load_mocks` as it is                            | 86-88 ms            |
| without the fixture                              | 73 ms               |
| without the fixture and the stubs' `cat`/`chmod` | 62 ms               |
| only the `PATH`-filter loop                      | 42 ms (27 ms floor) |
| the same filter by parameter expansion           | 29 ms               |

`load_setup_env` adds top-level commands in `lib/constants.sh`:

- `_LINUX_ARCH="$(uname -m | sed ...)"` and `_RUSTUP_TRIPLE="$(uname -m)-..."`. In the 18 files
  that call `load_mocks` before `load_setup_env`, each `uname` starts `tests/mocks/uname`, which runs
  the real one, so the pair costs 4 execs plus a `sed`. In the 19 files that call them the other way
  round, it costs 2 execs plus the `sed`.
- `DOTFILES_REPO_ROOT="$(cd "$(dirname ...)/.." && pwd)"`.

The ai-config fixture is mostly unused. 52 bats files (about 2,940 tests) call `load_mocks`. Two
round-1 lenses instrumented `_ai_config_tracked_items`, `setup_dotfile_symlinks` and
`setup_ai_config` across a full suite run (3755 ok):

- Only `tests/setup_env/install_guards.bats` and `tests/setup_env/workflows.bats` read the default
  fixture.
- `extracted_functions.bats` and `ai_config_sync.bats` set their own directory, and `unit.bats` stubs
  `setup_ai_config`.
- `setup_ai_config` is also reached through `run_update` from three files outside those two:
  `cargo_tools_update.bats` (6 calls), `update_noop_skip.bats` (7) and `update_plugin_node.bats` (1).
  With the fixture they take the "update" branch against `tests/mocks/git`; without it they take the
  mock "clone" branch, which `mkdir`s under `BATS_TEST_TMPDIR`. Both are mocks, and the tests stay
  green.

Population: all figures come from `claude` (Linux). The macOS legs run the same code, so the saving
applies there too, but at a different absolute size, which this spec does not measure.

Predicted saving, weighted over about 2,940 tests: about 11 ms from the stubs, 12 ms from the
`PATH` filter, 2-3 ms from merging `mkdir`, 6-12 ms from `constants.sh` (depending on call order) and
about 10 ms from the fixture opt-in (13.5 ms on the roughly 2,480 tests that drop it). Total: about
40 ms per test. This is a prediction; V1 measures it.

Checked and ruled out: the environment is not inflated (9.7 KB, no exported functions). A child
`bash -c :` starts in 1.74 ms against 1.37 ms bare.

## Design

### Static stubs in `tests/stubs/`

The five stubs become tracked, executable files in a new `tests/stubs/` directory, keeping their
current names: `brew-az`, `brew-stub`, `sysctl-stub`, `systemctl-stub`, `findmnt-stub`. The `-stub`
suffix keeps them distinct from the different `tests/mocks/sysctl` and `tests/mocks/systemctl`. The
directory is deliberately not on `PATH`: a `sysctl` or `systemctl` there would shadow the real
binaries for every test.

Their bodies stay byte-for-byte the same, `#!/usr/bin/env bash` first line included, so
`scripts/list-shell-files.sh` keeps them in `make lint` scope. The one exception is `brew-stub`,
which writes to `"${BATS_TEST_TMPDIR:?}/brew-calls"`, expanded when it runs rather than when it is
written. bats exports `BATS_TEST_TMPDIR` to child processes (checked on 1.13: a child `bash -c` sees
it non-empty). The `:?` makes a call with it unset fail loudly instead of writing `/brew-calls`.

`load_mocks` keeps exporting `_BREW_AZ_BIN`, `_BREW_BIN`, `_SYSCTL_BIN`, `_SYSTEMCTL_BIN` and
`_FINDMNT_BIN`, now pointing into `tests/stubs/`, and writes no stub files. No test writes, chmods,
moves or deletes those paths: a grep of `tests/`, `lib/` and `setup_env.sh` finds writers only
inside `load_mocks`, and the 32 reassignments in tests only point the variables elsewhere. A tracked
stub therefore cannot be modified by a test.

### `PATH` filter by parameter expansion

`load_mocks` removes every `${REPO_ROOT}/tests/mocks` entry from `PATH` by parameter expansion on
`":${PATH}:"`, with the entry quoted inside the pattern so characters in `REPO_ROOT` match literally,
repeated until no entry remains (`${p//:x:/:}` leaves one of two adjacent copies), then trims the
outer colons. It resolves the same real git as the current loop for every `PATH`: entry absent,
first, middle, last, repeated adjacent, the only entry, and with a leading or trailing empty entry.
The two strings differ only there: the loop drops leading and trailing empty entries (`read -a` and
the `${_clean_path:+:}` join) and the expansion keeps them. An empty entry means the current
directory, so the git found differs only when the bats working directory holds a `git`, and the
expansion is then the more faithful filter.

### One `mkdir -p`

Without the opt-in, the directories `load_mocks` creates under `BATS_TEST_TMPDIR` are made by one
`mkdir -p`. With it, `track_ai_config_fixture` adds its own.

### ai-config fixture opt-in

`load_mocks` builds the fixture only when `LOAD_MOCKS_AI_CONFIG=1`. `workflows.bats` sets it in
`setup()` before calling `load_mocks`. `install_guards.bats` needs the fixture for one test only
(`load_mocks defaults _OVERRIDE_AI_CONFIG_DIR to a tracked fixture under BATS_TEST_TMPDIR`), whose
title becomes false under this design; that test moves to `tests/helpers_load_mocks.bats` as the
opt-in-positive case below.

Otherwise `_OVERRIDE_AI_CONFIG_DIR` is
`${BATS_TEST_TMPDIR}/ai-config-absent--set-LOAD_MOCKS_AI_CONFIG=1`, which does not exist. The name
carries the remedy, so any output that shows the path also shows the fix. No test can reach the real
`~/git-repos/personal/ai-config`:

- `setup_ai_config` resolves `git` through `PATH`, so it runs `tests/mocks/git`. A "clone" is a
  recorded mock call that creates the directory, empty, under `BATS_TEST_TMPDIR`.
- `_ai_config_tracked_items` (real git via `_AI_CONFIG_GIT`) then fails, whether the directory is
  missing (`cannot change to`) or empty after that mock clone (`not a git repository`, or no tracked
  names inside an enclosing repo). Either way `setup_dotfile_symlinks` logs `Cannot list tracked
  items` with the path and links nothing, and `run_setup_user` returns 1.

A test that needs the fixture and lacks the opt-in goes red. Measured in round 2, 21 of 29 such
failures in `workflows.bats` printed only a bare assertion, because `run` captures the output that
names the path. So a static guard test (below) puts the remedy in the one line bats always prints.

### `lib/constants.sh`

- One `uname -m` into `_UNAME_M`, a new variable. `_LINUX_ARCH` is
  `${_UNAME_M/x86_64/amd64}` followed by `/aarch64/arm64`: the same first-occurrence substring
  replacement the current `sed` makes, so `x86_64_v2` still becomes `amd64_v2`. `_RUSTUP_TRIPLE` is
  `"${_UNAME_M}-unknown-linux-gnu"`.
- `DOTFILES_REPO_ROOT` uses `${BASH_SOURCE[0]%/*}` in place of `dirname` and keeps
  `cd ... && pwd`, so the value stays absolute. When `BASH_SOURCE[0]` has no slash
  (`source constants.sh` from `lib/`), the code falls back to `.`, matching `dirname`. The fallback
  is written so that it never leaves a failing status at top level, because the CI `secret-scan` step
  sources this file under `set -e`.

These lines are production code, so their values must not change on any input. The tests below pin
them.

## Testing

`tests/helpers_load_mocks.bats` gains these cases:

- Each of the five stub paths is an executable file under `tests/stubs/`, and each records its
  call: `brew-az`, `sysctl-stub`, `systemctl-stub` and `findmnt-stub` log to `MOCK_CALLS_FILE`, and
  `brew-stub` logs to `${BATS_TEST_TMPDIR}/brew-calls`.
- Without the opt-in, `_OVERRIDE_AI_CONFIG_DIR` equals exactly
  `${BATS_TEST_TMPDIR}/ai-config-absent--set-LOAD_MOCKS_AI_CONFIG=1`, and that path does not exist.
  An empty or unset value fails this test.
- With `LOAD_MOCKS_AI_CONFIG=1`, `_ai_config_tracked_items "${_OVERRIDE_AI_CONFIG_DIR}" .claude`
  prints `settings.json`.
- An exec count: one `load_mocks` call without the opt-in, under a counting shim, records exactly
  one `mkdir` (covering R3 and proving the shim records), and no `cat` and no `chmod`.
- The opt-in-positive case, moved from `install_guards.bats`: with `LOAD_MOCKS_AI_CONFIG=1`,
  `_OVERRIDE_AI_CONFIG_DIR` is under `BATS_TEST_TMPDIR` and `_ai_config_tracked_items` lists
  `settings.json` under `.claude`.
- A static guard: every `tests/**/*.bats` file whose text calls `run_setup_user` or
  `setup_dotfile_symlinks` also sets `LOAD_MOCKS_AI_CONFIG=1`, sets `_OVERRIDE_AI_CONFIG_DIR` itself,
  or redefines the function it calls. A file that does none fails, naming the file and
  `LOAD_MOCKS_AI_CONFIG=1`. The guard has a positive control: it finds at least one calling file.
  Any file it flags at the PR head is fixed in the same PR.
- The `PATH` filter: for each `PATH` shape listed in the Design, leading and trailing empty
  entries included, the resolved `_AI_CONFIG_GIT` is the same real git the current loop finds, or, when `tests/mocks` is the only entry, `load_mocks` fails
  with its existing message.

`tests/setup_env/workflows.bats` gains one loud-failure test. Its body unsets
`LOAD_MOCKS_AI_CONFIG`, calls `load_mocks` again (safe: the filter strips the existing mocks entry
and prepends it once), runs `run_setup_user`, and asserts rc 1 with output containing `Cannot list
tracked items` and `LOAD_MOCKS_AI_CONFIG=1`. It fails if `load_mocks` regresses to always building
the fixture.

`tests/setup_env/doctor_brew_links.bats:17` currently pins `_BREW_BIN` under `BATS_TEST_TMPDIR`.
It changes to pin the behaviour instead: the stub exits 0, prints nothing and logs its argv under
`BATS_TEST_TMPDIR`. The neighbouring test at line 22 already checks that.

The `lib/constants.sh` values are tested in `tests/setup_env/unit.bats`, each in a fresh `bash` that
sources the file with a `uname` stub first on `PATH`:

- `x86_64` gives `_LINUX_ARCH=amd64` and `_RUSTUP_TRIPLE=x86_64-unknown-linux-gnu`.
- `aarch64` gives `arm64` and `aarch64-unknown-linux-gnu`.
- `arm64` (macOS) gives `arm64` and `arm64-unknown-linux-gnu`.
- `x86_64_v2` gives `amd64_v2`, as `sed` does.
- `DOTFILES_REPO_ROOT` is the absolute repo root when sourced as `lib/constants.sh` from the root,
  as `../lib/constants.sh` from `tests/`, and as `constants.sh` from `lib/`.
- `bash -e -c 'source lib/constants.sh; echo ok'` prints `ok`.

## Docs

- `CLAUDE.md`, Test Seams: the line "`load_mocks` defaults `_OVERRIDE_AI_CONFIG_DIR` to a tracked
  fixture" becomes "builds the fixture only under `LOAD_MOCKS_AI_CONFIG=1` (`workflows.bats`);
  otherwise it points at a missing path named after that remedy".
- `CLAUDE.md`, Mock Pattern, one new line: "`tests/mocks/` is prepended to `PATH`, so a file there
  shadows the same-named command; put a stub reached only through a `_*_BIN` seam in `tests/stubs/`
  when its name would shadow a real command, as the `sysctl-stub`/`systemctl-stub` names once did."
- The ai-config `dotfiles-test-seams.md` sections those lines point to get the same corrections.
- The Backlog part-2 row records this trim as shipped and keeps test-body spawn counts as the open
  remainder.

## Requirements

- **R1.** `[PR1]` `tests/stubs/` holds tracked, executable `brew-az`, `brew-stub`, `sysctl-stub`, `systemctl-stub` and `findmnt-stub`, each starting `#!/usr/bin/env bash`; `load_mocks` exports the five `_*_BIN` paths into it and writes no stub file.
- **R2.** `[PR1]` `tests/stubs/brew-stub` logs its argv to `${BATS_TEST_TMPDIR:?}/brew-calls` expanded at run time, exits 0 and prints nothing.
- **R3.** `[PR1]` Without `LOAD_MOCKS_AI_CONFIG`, `load_mocks` creates its directories under `BATS_TEST_TMPDIR` with one `mkdir -p` call.
- **R4.** `[PR1]` `load_mocks` removes `tests/mocks` from `PATH` by parameter expansion, with no loop over `PATH` entries, and resolves the same real git as the current loop for every `PATH` shape in the Design, leading and trailing empty entries included.
- **R5.** `[PR1]` `load_mocks` builds the ai-config fixture only when `LOAD_MOCKS_AI_CONFIG=1`, and otherwise sets `_OVERRIDE_AI_CONFIG_DIR` to `${BATS_TEST_TMPDIR}/ai-config-absent--set-LOAD_MOCKS_AI_CONFIG=1`, which it does not create.
- **R6.** `[PR1]` `tests/setup_env/workflows.bats` sets `LOAD_MOCKS_AI_CONFIG=1` before `load_mocks`, and no other file does; the `install_guards.bats` fixture-default test moves to `tests/helpers_load_mocks.bats`.
- **R7.** `[PR1]` A `workflows.bats` test unsets `LOAD_MOCKS_AI_CONFIG`, calls `load_mocks` again, and pins that `run_setup_user` returns 1 with output containing `Cannot list tracked items` and `LOAD_MOCKS_AI_CONFIG=1`.
- **R8.** `[PR1]` `lib/constants.sh` runs `uname -m` once, into `_UNAME_M`, derives `_LINUX_ARCH` by first-occurrence substring replacement and `_RUSTUP_TRIPLE` from it without `sed`, and computes `DOTFILES_REPO_ROOT` without `dirname`.
- **R9.** `[PR1]` `_LINUX_ARCH`, `_RUSTUP_TRIPLE` and `DOTFILES_REPO_ROOT` hold the same values as before for `uname -m` outputs `x86_64`, `aarch64`, `arm64` and `x86_64_v2`, and for sourcing as `lib/constants.sh`, `../lib/constants.sh` and `constants.sh`; sourcing under `bash -e` succeeds.
- **R10.** `[PR1]` One `load_mocks` call without the opt-in execs exactly one `mkdir` and no `cat` and no `chmod`.
- **R11.** `[PR1]` A static guard test fails, naming the file and `LOAD_MOCKS_AI_CONFIG=1`, for any `tests/**/*.bats` file that calls `run_setup_user` or `setup_dotfile_symlinks` without setting the opt-in, setting `_OVERRIDE_AI_CONFIG_DIR` itself, or redefining the called function; it finds at least one calling file.
- **V1.** On `claude`, three interleaved before/after pairs (ABABAB) of `tests/setup_env/linux_ubuntu.bats`, `workflows.bats` and `install_guards.bats` at `bats --jobs 8`, with `uptime` recorded per run: every run's ok count equals its tree's `@test` count for those files and no test is not ok; each pair's after user+sys is below its before; and the after mean is at least 20 s below the before mean (the per-file prediction is about 39.5 s, and seven before-runs spanned 634-652 s). The PR body records wall, user, sys and load for each run.
- **V2.** `make test` passes in full at the PR head, and every CI leg passes on both platforms.
- **N1.** No existing `@test` body changes, except the `doctor_brew_links.bats:17` assertion and the `install_guards.bats` fixture-default test's move to `tests/helpers_load_mocks.bats`, both named above.
- **N2.** No file under `tests/mocks/` changes.
- **N3.** `tests/stubs/` is not added to `PATH` anywhere.
- **N4.** No `setup_file` caching of a sourced environment or fixture.

## Amendments

- R11 -> A static guard test fails, naming the file and `LOAD_MOCKS_AI_CONFIG=1`, for any `tests/**/*.bats` file that calls `run_setup_user` or `setup_dotfile_symlinks` without either a line setting `LOAD_MOCKS_AI_CONFIG=1` or one setting `_OVERRIDE_AI_CONFIG_DIR`; it finds at least one calling file. — a redefinition exemption let `workflows.bats` pass with its opt-in deleted, because one of its tests stubs `setup_dotfile_symlinks`; measured in Task 2's mutation control.

## Multi-Lens Review

Reviewed at commit: `78c1a781` (Step 7 self-review commit, before Step 8 dispatch)

### Goal-Fit

Finding: Worth building, but the spec framed the cost as execs and missed per-command overhead: bats
traces every command, and the fork-free `PATH`-filter loop alone costs about 13 ms per test, as much
as the fixture opt-in. The fixture opt-in ranks last on value per unit of risk (about 10 ms weighted,
the only change to a safety default). The `uname` saving is only full where `load_mocks` runs first
(18 of 37 files). V1 had no threshold, and R8 passed on an empty count.
Assumption: no test outside the opted-in files reaches `setup_dotfile_symlinks` and stays green when
it returns 1. Settled by probing every call with its `BATS_TEST_FILENAME` over a full suite run.
Disposition: Addressed (operator, 2026-11-01): `PATH` filter by parameter expansion added (R4);
predicted saving restated with the call-order caveat; V1 given a threshold; R10 gains a positive
control.

### Ergonomics

Finding: Forgetting the opt-in gave 30 red tests in `workflows.bats`, 29 printing only a bare
assertion. Only `install_guards` and `workflows` read the fixture; the other three files' opt-in
would teach the wrong rule. The `tests/stubs/sysctl` and `systemctl` names collided with different
mocks, the "no shebang" sentence was wrong (all five stubs start `#!/usr/bin/env bash`, which keeps
them in lint scope), and CLAUDE.md never named `tests/stubs/`. The absent-path test passed on an
empty value.
Assumption: no future test reaching `run_setup_user` without the opt-in asserts only absence and
passes vacuously. Settled by pinning the opt-out failure as loud.
Disposition: Addressed (operator, 2026-11-01): opt-in narrowed to two files (R6); the absent path is
named after its remedy (R5); a loud-failure test is pinned (R7); `-stub` names kept; the shebang
sentence corrected; a CLAUDE.md mocks-versus-stubs line added; the absent-path test asserts the exact
value.

### Risk

Finding: No isolation hole: a full suite run with the opt-in applied logged 432 ai-config reads, none
with the override unset, and the three `run_update` files outside the opt-in switch from mock update
to mock clone under `BATS_TEST_TMPDIR`. Gaps: the R8 and absent-path tests passed on empty output;
the "no shebang" sentence would have broken `_BREW_BIN` under `timeout` (dash runs it); "anything else
is unchanged" allowed an exact-match `case` that differs from `sed` on `x86_64_v2`; the CI
`secret-scan` step sources `constants.sh` under `set -e`.
Assumption: `tests/mocks/git` leads `PATH` in every `run_update` test outside the opted-in files, so
the switch to the clone branch stays a mock. Confirmed on Linux; a future test without the prepend
would reach a real clone.
Disposition: Addressed (operator, 2026-11-01): substring-replacement form specified and `x86_64_v2`
added to R9; `bash -e` sourcing test added; `brew-stub` uses `${BATS_TEST_TMPDIR:?}`; positive
controls added.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.

### Round 2 (`0d6cf67a`, all three lenses)

- **Goal-Fit.** Worth building; payoff modest (about 118 s suite-wide, about 6% of the V1 files).
  V1 passed on zero tests and cited a weighted figure; the per-file sum for the V1 files is about
  39.5 s. Three before-runs spanned 8.6 s as load rose; arms should interleave. R7 must re-call
  `load_mocks`. Assumption: run-to-run noise stays well below 20 s; four more before-runs by the
  orchestrator spanned 13.4 s (634.3-647.7 s), seven in all 634-652 s.
- **Ergonomics.** With the opt-in forgotten, 21 of 29 `workflows.bats` failures hid the remedy
  (`run` captures it); a static guard is needed. `install_guards` needs the fixture for one
  mislabelled test only. The CLAUDE.md stubs line was already false (`cargo` and `gpg-dearmor` are
  `_BIN` stubs in `tests/mocks/`). Assumption: forgotten opt-ins mostly happen in `workflows.bats`;
  the static guard removes the dependence on it.
- **Risk.** No isolation hole. R3/R10 contradicted the opt-in path (the fixture has its own
  `mkdir`); V1 passed on zero tests; the `PATH` equivalence was false as worded (leading/trailing
  empty entries), though the resolved git is the same; the isolation sentence misdescribed the
  mechanism (the mock clone creates the directory first); R7 was underspecified;
  `${BATS_TEST_TMPDIR:?}` changes no caller today (exit 127 if ever unset). Assumption: V1's margin
  exceeds run-to-run spread; settled by the interleaved pairs.
- **Disposition:** Addressed (operator, 2026-11-01): all eight fixes applied (R3/R10 scoped, V1
  interleaved with pinned counts, R4 restated, isolation sentence corrected, R7 re-calls
  `load_mocks`, R11 static guard, opt-in narrowed to `workflows.bats` with the one test moved, CLAUDE.md
  line restated). Review stopped at round 2: every finding was in the test apparatus or wording, and
  the design shrank (opt-in from five files to one).
