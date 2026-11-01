# load_mocks setup trim

- **Date:** 2026-11-01
- **Backlog row:** "bats process-spawn cost (part 2 of the setup floor)". The operator chose option 3: this setup trim first, as its own PR, and test-body spawn counts as a later spec.

## Problem

Per-test setup is about a fifth of the bats suite's CPU. Measured on `claude` (bats 1.13, synthetic
100-test files, `bats --jobs 1`, CPU per test):

| Layer                           | CPU per test |
| ------------------------------- | ------------ |
| bats' own floor (empty `setup`) | 27 ms        |
| + `load_mocks`                  | 93 ms        |
| + `load_setup_env`              | 172 ms       |

`load_mocks` alone takes about 64 ms wall time (50 calls, outside bats). An `strace -f -e execve`
count shows 22 successful external execs, in four groups:

- **Five stub scripts** (`brew-az`, `brew-stub`, `sysctl`, `systemctl`, `findmnt`), each written
  with a `cat` heredoc and then `chmod +x`: 10 execs. Four have fixed contents that read the
  environment when they run. Only `brew-stub` expands `BATS_TEST_TMPDIR` when written.
- **Five `mkdir -p` calls.**
- **The ai-config fixture** (`track_ai_config_fixture`): `mkdir`, `find`, `git init` and `git add`.
  About 10 ms of the 64.
- **The real-git lookup:** one `command -v` subshell.

`load_setup_env` adds 13 execs from top-level code in `lib/constants.sh` and the other libs:

- `_LINUX_ARCH="$(uname -m | sed ...)"` and `_RUSTUP_TRIPLE="$(uname -m)-..."`. With mocks on
  `PATH`, each `uname` starts `tests/mocks/uname`, which then runs the real one, so the pair costs
  4 execs plus a `sed`.
- Five `dirname` calls, among them `DOTFILES_REPO_ROOT="$(cd "$(dirname ...)/.." && pwd)"`.

Population: these figures come from `claude` (Linux). The macOS legs run the same code, so the
saving applies there too, but at a different absolute size, which this spec does not measure.

The fixture is mostly unused. 52 bats files (2,946 tests) call `load_mocks`, but only five reference
`_OVERRIDE_AI_CONFIG_DIR`, `_ai_config_tracked_items` or `setup_dotfile_symlinks`:

- `tests/setup_env/unit.bats`
- `tests/setup_env/install_guards.bats`
- `tests/setup_env/ai_config_sync.bats`
- `tests/setup_env/workflows.bats`
- `tests/setup_env/extracted_functions.bats`

Checked and ruled out: the environment is not inflated (9.7 KB, no exported functions). A child
`bash -c :` starts in 1.74 ms against 1.37 ms bare.

## Design

### Static stubs in `tests/stubs/`

The five stubs become tracked, executable files in a new `tests/stubs/` directory. It is
deliberately not on `PATH`: a `sysctl` or `systemctl` there would shadow the real binaries for every
test. Their bodies stay byte-for-byte the same, with one exception: `brew-stub` writes to
`"${BATS_TEST_TMPDIR}/brew-calls"`, expanded when it runs rather than when it is written. bats
exports `BATS_TEST_TMPDIR` to child processes (checked on 1.13: a child `bash -c` sees it
non-empty).

`load_mocks` keeps exporting `_BREW_AZ_BIN`, `_BREW_BIN`, `_SYSCTL_BIN`, `_SYSTEMCTL_BIN` and
`_FINDMNT_BIN`, now pointing into `tests/stubs/`, and writes no stub files. No test writes to those
paths: a grep finds writers only inside `load_mocks`. A tracked stub therefore cannot be modified by
a test.

The stubs keep having no shebang line, so `exec` falls back to running them as shell scripts,
exactly as the generated ones do today.

### One `mkdir -p`

The directories `load_mocks` creates under `BATS_TEST_TMPDIR` are made by one `mkdir -p`.

### ai-config fixture opt-in

`load_mocks` builds the fixture only when `LOAD_MOCKS_AI_CONFIG=1`. The five files above set it in
`setup()` before calling `load_mocks`.

Otherwise `_OVERRIDE_AI_CONFIG_DIR` points at `${BATS_TEST_TMPDIR}/ai-config-absent`, which does not
exist, so no test can reach the real `~/git-repos/personal/ai-config`:

- `_ai_config_tracked_items` (real git via `_AI_CONFIG_GIT`) fails on a missing directory and
  returns 1, so `setup_dotfile_symlinks` links nothing from it.
- `setup_ai_config` resolves `git` through `PATH`, so it runs `tests/mocks/git`. A "clone" is a
  recorded mock call that creates the directory under `BATS_TEST_TMPDIR`.

A test outside the five files that needs the fixture goes red rather than silently reading a real
repo.

### `lib/constants.sh`

- One `uname -m` into `_UNAME_M`, a new variable. `_LINUX_ARCH` is derived from it by parameter
  expansion (`x86_64` becomes `amd64`, `aarch64` becomes `arm64`, anything else is unchanged, as
  with today's `sed`), and `_RUSTUP_TRIPLE` is `"${_UNAME_M}-unknown-linux-gnu"`.
- `DOTFILES_REPO_ROOT` uses `${BASH_SOURCE[0]%/*}` in place of `dirname` and keeps
  `cd ... && pwd`, so the value stays absolute. When `BASH_SOURCE[0]` has no slash
  (`source constants.sh` from `lib/`), the expansion leaves the bare name. The code handles that by
  falling back to `.`, matching `dirname`'s answer for that case.

These lines are production code, so their values must not change on any input. The tests below pin
them.

## Testing

`tests/helpers_load_mocks.bats` gains these cases:

- Each of the five stub paths is an executable file under `tests/stubs/`, and each still records its
  call:
  - `brew-az`, `sysctl`, `systemctl` and `findmnt` log to `MOCK_CALLS_FILE`;
  - `brew-stub` logs to `${BATS_TEST_TMPDIR}/brew-calls`.
- Without `LOAD_MOCKS_AI_CONFIG`, `_OVERRIDE_AI_CONFIG_DIR` names a path that does not exist.
- With `LOAD_MOCKS_AI_CONFIG=1`, `_ai_config_tracked_items "${_OVERRIDE_AI_CONFIG_DIR}" .claude`
  prints `settings.json`. That is a specific non-empty value, not just rc 0.
- An exec count: one `load_mocks` call under a counting `PATH` shim records no `cat` and no `chmod`.

`tests/setup_env/doctor_brew_links.bats:17` currently pins `_BREW_BIN` under `BATS_TEST_TMPDIR`.
It changes to pin the behaviour instead: the stub exits 0, prints nothing and logs its argv under
`BATS_TEST_TMPDIR`. The neighbouring test at line 22 already checks that.

The `lib/constants.sh` values are tested in `tests/setup_env/unit.bats`, each in a fresh `bash` that
sources the file with a `uname` stub first on `PATH`:

- `x86_64` gives `_LINUX_ARCH=amd64` and `_RUSTUP_TRIPLE=x86_64-unknown-linux-gnu`.
- `aarch64` gives `arm64` and `aarch64-unknown-linux-gnu`.
- `arm64` (macOS) gives `arm64` and `arm64-unknown-linux-gnu`, matching today's `sed`, which leaves
  `arm64` alone.
- `DOTFILES_REPO_ROOT` is the absolute repo root when sourced as `lib/constants.sh` from the root,
  as `../lib/constants.sh` from `tests/`, and as `constants.sh` from `lib/`.

## Docs

- `CLAUDE.md`, Test Seams: the line "`load_mocks` defaults `_OVERRIDE_AI_CONFIG_DIR` to a tracked
  fixture" becomes "builds the fixture only under `LOAD_MOCKS_AI_CONFIG=1`, otherwise points it at
  a missing path". The ai-config `dotfiles-test-seams.md` section it points to gets the same
  correction plus the `tests/stubs/` location.
- The Backlog part-2 row records part 2a as shipped and keeps test-body spawn counts as the open
  remainder.

## Requirements

- **R1.** `[PR1]` `tests/stubs/` holds tracked, executable `brew-az`, `brew-stub`, `sysctl`, `systemctl` and `findmnt`; `load_mocks` exports the five `_*_BIN` paths into it and writes no stub file.
- **R2.** `[PR1]` `tests/stubs/brew-stub` logs its argv to `${BATS_TEST_TMPDIR}/brew-calls` expanded at run time, exits 0 and prints nothing.
- **R3.** `[PR1]` `load_mocks` creates its directories under `BATS_TEST_TMPDIR` with one `mkdir -p` call.
- **R4.** `[PR1]` `load_mocks` builds the ai-config fixture only when `LOAD_MOCKS_AI_CONFIG=1`, and otherwise sets `_OVERRIDE_AI_CONFIG_DIR` to `${BATS_TEST_TMPDIR}/ai-config-absent`, which it does not create.
- **R5.** `[PR1]` `tests/setup_env/unit.bats`, `install_guards.bats`, `ai_config_sync.bats`, `workflows.bats` and `extracted_functions.bats` set `LOAD_MOCKS_AI_CONFIG=1` before `load_mocks`.
- **R6.** `[PR1]` `lib/constants.sh` runs `uname -m` once, into `_UNAME_M`, derives `_LINUX_ARCH` and `_RUSTUP_TRIPLE` from it without `sed`, and computes `DOTFILES_REPO_ROOT` without `dirname`.
- **R7.** `[PR1]` `_LINUX_ARCH`, `_RUSTUP_TRIPLE` and `DOTFILES_REPO_ROOT` hold the same values as before for `uname -m` outputs `x86_64`, `aarch64` and `arm64`, and for sourcing as `lib/constants.sh`, `../lib/constants.sh` and `constants.sh`.
- **R8.** `[PR1]` One `load_mocks` call execs no `cat` and no `chmod`.
- **V1.** On `claude`, the part-1 A/B: two runs per arm of `tests/setup_env/linux_ubuntu.bats`, `workflows.bats` and `install_guards.bats` at `bats --jobs 8`, before and after, with every test ok; the PR body records wall, user and sys for each run.
- **V2.** `make test` passes in full at the PR head, and every CI leg passes on both platforms.
- **N1.** No `@test` body changes, except the one `doctor_brew_links.bats` assertion named above.
- **N2.** No file under `tests/mocks/` changes.
- **N3.** `tests/stubs/` is not added to `PATH` anywhere.
- **N4.** No `setup_file` caching of a sourced environment or fixture.
