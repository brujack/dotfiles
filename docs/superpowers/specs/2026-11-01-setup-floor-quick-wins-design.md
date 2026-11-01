# Setup floor, part 1: two quick wins in the bats setup helpers

## Problem

The P1 backlog row "Per-test setup floor dominates many bats files" measured, serially on the
Studio, about 190 ms of setup per test (`load_setup_env` ~95 ms plus `load_mocks` ~95 ms) and
estimated that `tests/setup_env/linux_ubuntu.bats` spends ~61% of its time in setup.

Re-measured on `claude` (Linux, 2026-11-01, `bash` timing harness sourcing
`tests/helpers/common.bash`, 5 samples each):

| Helper           | Per call | Tests that call it in `setup()` |
| ---------------- | -------- | ------------------------------- |
| `load_mocks`     | 54-64 ms | 2771 of 3752                    |
| `load_setup_env` | 60-78 ms | 2644 of 3752                    |

Population: the per-call figures are from one process on one Linux box, outside bats; the
caller counts are a static scan of every tracked `tests/**/*.bats` `setup()` body.

Two causes are mechanical, not inherent, and both were located with a `PS4` timestamp trace
and an `strace -e execve` count:

1. **`load_mocks` calls its own mocks.** It prepends `tests/mocks` to `PATH` part-way through,
   then runs `chmod +x` five times (generated stubs) and `cp` once (the claude-settings copy).
   Those resolve to the pass-through wrappers `tests/mocks/chmod` and `tests/mocks/cp`. Each
   wrapper is `#!/usr/bin/env bash`, so each call costs `env`, a `PATH` walk (9 failed `execve`
   attempts before `bash`), a bash start and the real binary: 6.4-7.1 ms per call, about 37 ms
   of the 60 ms.
2. **`setup_env.sh` forks `dirname` 14 times.** Each of its 13 `source` lines and the
   `_LOCAL_CFG` assignment runs `$(dirname "${BASH_SOURCE[0]}")`, about 1.1-1.6 ms each.

Cause 1 also breaks isolation. Every `setup()` that was checked calls `load_mocks` before it
sets `MOCK_CALLS_FILE` (`tests/setup_env/linux_ubuntu.bats`, `tests/setup_env/workflows.bats`),
and the wrappers log to `${MOCK_CALLS_FILE:-/tmp/mock_calls}`. So every such test appends six
lines to one shared file outside its tmpdir, from every test, in every run, in parallel. On
`claude` that file was 83,391,304 bytes on 2026-11-01. No test reads those lines: tests read
the per-test `MOCK_CALLS_FILE` they set afterwards.

The row's 61% figure does not carry to Linux. An A/B over the three heaviest files
(`linux_ubuntu.bats`, `workflows.bats`, `install_guards.bats`; 976 tests; `bats --jobs 8`; two
runs per arm in `git archive` copies; all 976 ok in every run) gave:

| Arm        | Wall              | user              | sys               | CPU total |
| ---------- | ----------------- | ----------------- | ----------------- | --------- |
| baseline   | 166.26 / 166.12 s | 269.30 / 267.36 s | 437.19 / 437.49 s | ~706 s    |
| both fixes | 158.66 / 158.26 s | 254.43 / 254.54 s | 381.12 / 379.94 s | ~635 s    |

So setup is ~17% of per-test CPU on Linux (about 120 ms of ~723 ms), and the two fixes save
~10% CPU and ~5% wall on those files. `sys` is 62% of the baseline CPU: the larger cost is
process creation throughout the test bodies, which is part 2 (a separate spec).

## Design

### `load_mocks` prepends `tests/mocks` last

Move `export PATH="${REPO_ROOT}/tests/mocks:${PATH}"` from its current position to the last
statement of `load_mocks`. Everything `load_mocks` runs before it (`cat`, `chmod`, `cp`,
`mkdir`, `printf` into generated stubs and fixtures) then resolves to real binaries.

The environment `load_mocks` leaves behind is unchanged: the same exports, the same files under
`BATS_TEST_TMPDIR`, and `tests/mocks` first on `PATH`. The only observable difference is that
`load_mocks` itself no longer writes to `MOCK_CALLS_FILE` (or its `/tmp/mock_calls` fallback).

### `setup_env.sh` resolves its directory once

Before the first `source` line, set `_SETUP_ENV_DIR="$(dirname "${BASH_SOURCE[0]}")"`, and use
`"${_SETUP_ENV_DIR}/lib/<name>.sh"` in the 13 `source` lines and
`"${_SETUP_ENV_DIR}/config/local.sh"` for `_LOCAL_CFG`. `dirname` keeps its exact semantics,
including `.` for a bare `setup_env.sh`, because it is still `dirname`, called once.

## Testing

TDD, bats, red first:

- `tests/helpers_git_env.bats` or a new `tests/helpers_load_mocks.bats` (the plan decides,
  following where `tests/helpers/common.bash` is already tested): with `MOCK_CALLS_FILE` set to
  an existing empty file before `load_mocks`, the file is still empty afterwards, and the first
  `PATH` entry afterwards is `${REPO_ROOT}/tests/mocks`. Red on master: six `chmod`/`cp` lines.
- `tests/setup_env/unit.bats`: sourcing `setup_env.sh` by a relative path from a directory
  other than the repo root defines one function from each of the 13 lib files.
- The full suite stays green.

## Measurement

Repeat the A/B on the Studio (bash from Homebrew, BSD userland), where process creation costs
more, and record both machines' figures in the PR body.

## Out of scope

- Mocks themselves (shebangs, the `/tmp/mock_calls` fallback in other mocks), bats structure
  (`setup_file`, caching the sourced env), and any test body: part 2, a separate spec on
  process-spawn cost.
- Deleting the existing `/tmp/mock_calls` on any machine: an operator decision after merge.

## Requirements

- **R1.** `[PR1]` `load_mocks` prepends `${REPO_ROOT}/tests/mocks` to `PATH` as its last statement, so with `MOCK_CALLS_FILE` set to an empty file before the call the file is still empty afterwards, and the first `PATH` entry afterwards is `${REPO_ROOT}/tests/mocks`.
- **R2.** `[PR1]` `setup_env.sh` calls `dirname` once to set `_SETUP_ENV_DIR` and uses it for all 13 lib `source` lines and for `_LOCAL_CFG`.
- **R3.** `[PR1]` Sourcing `setup_env.sh` by a relative path from a directory other than the repo root defines a function from each of the 13 lib files, under a test that fails if any lib is not sourced.
- **V1.** The three-file A/B (`linux_ubuntu.bats`, `workflows.bats`, `install_guards.bats`, `bats --jobs 8`, two runs per arm) is run on `claude` and on the Studio with all tests ok in every run, and the PR body records wall, user and sys for each arm on each machine.
- **N1.** No change to any file under `tests/mocks/`.
- **N2.** No change to what any existing test asserts.
- **N3.** No change to bats structure: no `setup_file`, no cached or exported function definitions.
