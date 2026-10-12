# Ansible Venv Interpreter Guard Implementation Plan

spec: docs/superpowers/specs/2026-10-11-ansible-venv-interpreter-guard-design.md

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Never delete the `ansible` virtualenv before the interpreter its replacement needs is proven executable, and stop calling `pyenv update` where pyenv has no such command.

**Architecture:** A new `_ensure_pyenv_python` in `lib/developer.sh` owns the interpreter install and its post-install `-x bin/python` test. `setup_ansible` and `recreate_python_venv` call it before any `pyenv virtualenv-delete`. `tests/mocks/pyenv` learns to model a real install under `env -i`, keyed on `HOME` only.

**Tech Stack:** bash, bats, pyenv / pyenv-virtualenv.

## Global Constraints

- Every input the mock's `install` reads is derived from `HOME` or its argument list: `env -i` (`lib/developer.sh:552-561`) strips `BATS_TEST_TMPDIR`, `MOCK_*` and `MOCK_CALLS_FILE`.
- The mock creates a file only when `HOME` matches `*/bats-run-*`, never under `PYENV_ROOT`, never overwriting an existing file.
- No change to the Linux `env -i` build command, its environment, or the build-dependency package list (N1).
- No build-then-swap, no pre-delete snapshot (N2). No `--dry-run` change (N3).
- Shell style per `~/.claude/standards/shell.md`: `[[ ]]`, `${VAR}`, `printf`, `|| return 1` in functions.
- **Session verification:** `make test` exits 0 (V1); each guard behind R2, R3, R5, R6 deleted in turn turns a test red (V2, orchestrator); on `studio`, `-t recreate-venv --venv-name v3probe` with `PYTHON_VER=9.9.9` in a scratch clone exits non-zero and leaves `~/.pyenv/versions/v3probe` unchanged (V3, orchestrator).
- `make test` locally is well under the Bash tool's 600s cap (CI's 2-vCPU `test` job: 8m28s); code tasks gate on it.

---

### Task 1: pyenv mock models install, `-s`, failure injection and `commands`

```yaml-task
id: 1
description: Teach tests/mocks/pyenv to create the interpreter only in a bats HOME, honour -s and a failure file, and print MOCK_PYENV_COMMANDS
model: sonnet
tdd: required
requirements: [R8]
acceptance:
  - cmd: bats tests/setup_env/mocks_pyenv.bats
    exit_code: 0
  - cmd: make lint
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [tests/mocks/pyenv, tests/setup_env/mocks_pyenv.bats]
depends_on: []
```

**Files:** modify `tests/mocks/pyenv`; create `tests/setup_env/mocks_pyenv.bats` (model on `tests/setup_env/mocks_sudo.bats`).

Add to the mock, before its final `exit`:

- `pyenv commands`: print `MOCK_PYENV_COMMANDS` if non-empty; exit 0.
- `pyenv install` (not `--list`, which already returns earlier). Version = last argument; `-s` present anywhere in args. In order:
  1. `${HOME}/.mock-pyenv-install-exit` exists: exit with its contents, create nothing.
  2. `MOCK_PYENV_EXIT` set: exit with it, create nothing.
  3. `-s` and `${HOME}/.pyenv/versions/<ver>` exists: exit 0, create nothing.
  4. `HOME` matches `*/bats-run-*`: if `${HOME}/.pyenv/versions/<ver>/bin/python` does not exist, `mkdir -p` and write an executable stub (`#!/bin/sh` + `exit 0`); exit 0.
  5. Otherwise print `mock pyenv: declined to create interpreter, HOME=<HOME> is not a bats test dir` to stderr; exit 0.

**Tests** (`mocks_pyenv.bats`; `setup` sets `HOME="${BATS_TEST_TMPDIR}/home"`, `PATH` with `tests/mocks` first). Each runs the mock directly:

- install creates an executable `bin/python` for the version; rc 0.
- install with `-s` and an existing bare `versions/<ver>`: rc 0, no `bin/python`.
- failure file containing `5`: rc 5, no `bin/python`.
- `MOCK_PYENV_EXIT=4`: rc 4, no `bin/python`.
- existing `bin/python` with content `keep`: content unchanged after install.
- `HOME=$(mktemp -d /tmp/mpyX.XXXXXX)` (no `bats-run-`): no `bin/python` there, stderr names the decline; positive control in the same test: rerun with the bats `HOME`, file created. Remove the temp dir in `teardown`.
- under `env -i HOME=<bats home> PATH=/usr/bin:/bin <mock> install -s -v 3.99.1`: `bin/python` created (proves the `env -i` path).
- `commands` prints `MOCK_PYENV_COMMANDS`; empty when unset.

**Interfaces:**

- Produces: mock contract above; failure file path `${HOME}/.mock-pyenv-install-exit`; env var `MOCK_PYENV_COMMANDS`.

### Task 2: `_ensure_pyenv_python`

```yaml-task
id: 2
description: Add _ensure_pyenv_python to lib/developer.sh (install-if-missing, gated pyenv update, post-install -x test) with direct tests; not yet wired to callers
model: sonnet
tdd: required
requirements: [R1, R2, R3, R4]
acceptance:
  - cmd: bats tests/setup_env/developer.bats
    exit_code: 0
  - cmd: make lint
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [lib/developer.sh, tests/setup_env/developer.bats]
depends_on: [1]
```

**Files:** `lib/developer.sh` (new function directly above `setup_ansible`); `tests/setup_env/developer.bats`.

Move the body of `setup_ansible`'s `if ! [[ -d …/versions/${PYTHON_VER} ]]` block (`:525-572`) verbatim into `_ensure_pyenv_python`, with these changes only:

- Guard is `local _py="${HOME}/.pyenv/versions/${PYTHON_VER}/bin/python"; [[ -x "${_py}" ]] && return 0`.
- `pyenv update` becomes `if pyenv commands 2>/dev/null | grep -qx update; then pyenv update; fi`.
- After the `elif MACOS` arm, add `else log_error "neither LINUX nor MACOS set — cannot install Python ${PYTHON_VER}"; return 1`.
- After the platform block: if `[[ ! -x "${_py}" ]]`: `log_error "Python ${PYTHON_VER} not installed: ${_py} is not executable"`; if `[[ -d "${HOME}/.pyenv/versions/${PYTHON_VER}" ]]`, also `log_error "remove ${HOME}/.pyenv/versions/${PYTHON_VER}; pyenv install -s skips an existing version directory"`; `return 1`. Else `return 0`.

Leave `setup_ansible`'s copy in place this task (Task 3 replaces it).

**Tests** (call `_ensure_pyenv_python` directly; `HOME` is already `${BATS_TEST_TMPDIR}/home`; set `PYTHON_VER=3.99.1`):

- already executable (fixture `bin/python`), macOS: rc 0, `MOCK_CALLS_FILE` has no `pyenv install`.
- macOS, missing, install succeeds: rc 0, `bin/python` exists.
- macOS, failure file `1`: rc 1, output names the `bin/python` path, no "remove" line (no dir).
- macOS, bare `versions/3.99.1` dir: rc 1, output names the path and contains `remove`.
- Linux (`LINUX=1`, mock copied to `${HOME}/.pyenv/bin/pyenv`), `MOCK_PYENV_COMMANDS=update`: `pyenv update` in the call log; rc 0; `bin/python` exists.
- Linux, `MOCK_PYENV_COMMANDS` unset: no `pyenv update` in the log; rc 0; `bin/python` exists.
- neither platform (`unset LINUX MACOS`): rc 1; output contains `neither LINUX nor MACOS`.

**Interfaces:**

- Produces: `_ensure_pyenv_python` — no args; reads `PYTHON_VER`, `HOME`, `LINUX`, `MACOS`; returns 0 when `${HOME}/.pyenv/versions/${PYTHON_VER}/bin/python` is executable, else 1.

### Task 3: guard `setup_ansible` and `recreate_python_venv`

```yaml-task
id: 3
description: Wire _ensure_pyenv_python ahead of every virtualenv-delete, check pyenv virtualenv, update every existing test the spec names, reword the workflows.sh comment
model: sonnet
tdd: required
requirements: [R5, R6, R7, R9]
acceptance:
  - cmd: bats tests/setup_env/developer.bats tests/setup_env/workflows.bats tests/setup_env/install_functions.bats
    exit_code: 0
  - cmd: make lint
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [lib/developer.sh, lib/workflows.sh, tests/setup_env/developer.bats, tests/setup_env/workflows.bats, tests/setup_env/install_functions.bats]
depends_on: [2]
```

**Production:**

- `setup_ansible`: replace the whole `if ! [[ -d … ]]; then … fi` install block with `_ensure_pyenv_python || return 1`. `pyenv virtualenv "${PYTHON_VER}" ansible` gains `|| return 1`.
- `recreate_python_venv`: `_ensure_pyenv_python || return 1` immediately after `eval "$(pyenv init -)"`, before the `Deleting virtualenv` printf.
- `lib/workflows.sh:1036-1038`: comment says `pyenv update` runs inside `_ensure_pyenv_python` (`lib/developer.sh`), reached from `setup_ansible` and `recreate_python_venv`.

**New tests (`developer.bats`):**

- `setup_ansible`, Linux, `versions/ansible` symlink to an old version dir, failure file `1`: rc 1; no `virtualenv-delete` in the log; `readlink versions/ansible` unchanged.
- same, macOS: same plus `pyenv install` in the log.
- `recreate_python_venv`, macOS, failure file: rc 1; no `virtualenv-delete`; venv symlink unchanged.
- `recreate_python_venv`, macOS, missing interpreter: rc 0; `pyenv install` line precedes `virtualenv-delete` line in the log.
- `setup_ansible`, Linux, missing interpreter: rc 0; `bin/python` exists; `pyenv virtualenv 3.99.1 ansible` in the log.
- `setup_ansible`, `pyenv virtualenv` fails (`MOCK_PYENV_EXIT` scoped by a wrapper that fails only `virtualenv`, interpreter fixture present): rc 1.

**Existing tests to update, each with the change it needs:**

- `developer.bats:688`: set `MOCK_PYENV_COMMANDS=update`.
- `developer.bats:926` (`setup_ansible: pyenv rehash still runs…`): add an executable `bin/python` fixture and scope the rc-3 failure to `rehash` only; fix its comment about unchecked calls.
- `developer.bats:961` (`recreate_python_venv: pyenv rehash still runs…`): add an executable `versions/${PYTHON_VER}/bin/python` fixture.
- `developer.bats:853`, `:877`, `:909`, `workflows.bats:1386`, `:1391`: each `mkdir versions/${PYTHON_VER}` gains an executable `bin/python`.
- Re-check line numbers with `grep -n` before editing; then run the three suites and fix any further failure the same way, listing it in the report.

### Task 4: docs

```yaml-task
id: 4
description: Document the pyenv mock contract in CLAUDE.md Test Seams and add the python-build plugin backlog row (docs-only, no behaviour change)
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: 'grep -q "mock-pyenv-install-exit" CLAUDE.md'
    exit_code: 0
  - cmd: 'grep -qE "plugins/python-build" docs/superpowers/README.md'
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 2
files_touched: [CLAUDE.md, docs/superpowers/README.md]
depends_on: [3]
```

- `CLAUDE.md` Test Seams: one bullet group for `tests/mocks/pyenv`: creates `${HOME}/.pyenv/versions/<ver>/bin/python` only when `HOME` matches `*/bats-run-*`, because `env -i` strips `BATS_TEST_TMPDIR`; inject failure with `${HOME}/.mock-pyenv-install-exit`, not an env var; honours `install -s`; keys on `HOME`, never `PYENV_ROOT`.
- `docs/superpowers/README.md` Backlog: `workstation's git-era ~/.pyenv/plugins/python-build shadows linuxbrew's` row: plugin dirs dated 2024-12 to 2026-10 sit ahead of brew's python-build on `PATH`; `pyenv update` works only because of them (measured 2026-10-11).
- The plan-index row for this plan is added at plan commit time, not here.

## Non-goal check

One fresh reviewer, inputs `plan.md` and the spec's N list. CLEAR 3, CONFLICT 0, UNCLEAR 0.

- **N1 CLEAR.** "Task 2 moves the Linux `env -i` block verbatim into
  `_ensure_pyenv_python`"; its three changes (`-x` guard, gated `pyenv update`, new
  else/post-check) touch neither the build command, its environment nor the package list.
  The reviewer assumed `pyenv update` is a separate step from the `env -i` build; confirmed
  against the code: `pyenv update` is `lib/developer.sh:538`, the `env -i` invocation starts
  at `:552`. No resolution needed.
- **N2 CLEAR.** No build-then-swap or snapshot; only a pre-delete interpreter check.
- **N3 CLEAR.** No `--dry-run` change.
