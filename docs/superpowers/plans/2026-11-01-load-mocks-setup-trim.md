# load_mocks Setup Trim Implementation Plan

spec: docs/superpowers/specs/2026-11-01-load-mocks-setup-trim-design.md

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cut about 40 ms of CPU from every bats test's setup without changing test isolation or production values.

**Architecture:** `load_mocks` (`tests/helpers/common.bash`) stops generating five stub scripts and points at tracked copies in `tests/stubs/`. It merges its `mkdir -p` calls, filters `PATH` by parameter expansion, and builds the ai-config fixture only when a file opts in. `lib/constants.sh` calls `uname -m` once and drops `sed` and `dirname`.

**Tech Stack:** bash 5, bats 1.13, GNU make.

## Global Constraints

- No existing `@test` body changes, except the `doctor_brew_links.bats:17` assertion and moving the `install_guards.bats` fixture-default test to `tests/helpers_load_mocks.bats` (N1).
- No file under `tests/mocks/` changes (N2). `tests/stubs/` is never added to `PATH` (N3). No `setup_file` caching (N4).
- Stub bodies stay byte-for-byte, first line `#!/usr/bin/env bash`. The one exception is `brew-stub`, which logs to `${BATS_TEST_TMPDIR:?}/brew-calls`.
- `_LINUX_ARCH`, `_RUSTUP_TRIPLE` and `DOTFILES_REPO_ROOT` keep their current values on every input.
- Tests that capture `wc -l` compare with `-eq`, never as a string (BSD `wc` pads with spaces).
- Mutation controls run in a `git archive HEAD | tar -x` copy under a `mktemp -d`, never in the worktree. Delete the copy before reporting.

## Verification

- Session-level: `make test` exits 0 at the final head, and every CI leg passes on both platforms.
- V1, run by the orchestrator after Task 4:
  - on `claude`, three interleaved pairs (before = merge-base tree, after = head, ABABAB);
  - each run is `bats --jobs 8 tests/setup_env/linux_ubuntu.bats tests/setup_env/workflows.bats tests/setup_env/install_guards.bats < /dev/null` under `/usr/bin/time -f '%e %U %S'`, with `uptime` before it;
  - every run's ok count equals its tree's `@test` count for those three files, with 0 not ok;
  - each pair's after user+sys is below its before, and the after mean is at least 20 s below the before mean.
  - Baseline: seven runs at `5c5e1c60` spanned 634-652 s.
  - The PR body records each run.
- Edge cases covered by tests:
  - `PATH` shapes: mocks absent, first, middle, last, adjacent duplicate, only entry, leading or trailing empty entry;
  - `uname -m` values `x86_64`, `aarch64`, `arm64`, `x86_64_v2`;
  - three ways of sourcing `constants.sh`, plus `bash -e`;
  - a forgotten opt-in.

---

### Task 1: Static stubs, one mkdir, PATH filter by expansion

```yaml-task
id: 1
description: Move the five load_mocks stubs to tracked tests/stubs files, merge its mkdir calls and replace the PATH-filter loop with parameter expansion
role: executor
model: sonnet
tdd: required
requirements: [R1, R2, R3, R4, R10]
acceptance:
  - cmd: bats tests/helpers_load_mocks.bats tests/setup_env/doctor_brew_links.bats
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - tests/stubs/brew-az
  - tests/stubs/brew-stub
  - tests/stubs/sysctl-stub
  - tests/stubs/systemctl-stub
  - tests/stubs/findmnt-stub
  - tests/helpers/common.bash
  - tests/helpers_load_mocks.bats
  - tests/setup_env/doctor_brew_links.bats
depends_on: []
```

**Steps:**

- [ ] **Red: write the tests first in `tests/helpers_load_mocks.bats`, then run them to see them fail.**
  - Each of `_BREW_AZ_BIN`, `_BREW_BIN`, `_SYSCTL_BIN`, `_SYSTEMCTL_BIN` and `_FINDMNT_BIN` equals `${REPO_ROOT}/tests/stubs/<name>`, is executable, and has first line `#!/usr/bin/env bash`.
  - Running each one records its call:
    - `brew-az`, `sysctl-stub`, `systemctl-stub` and `findmnt-stub` append to a `MOCK_CALLS_FILE` the test sets;
    - `brew-stub x y` writes `x y` to `${BATS_TEST_TMPDIR}/brew-calls`, prints nothing and exits 0.
  - Exec count:
    - put a shim dir first on `PATH` with logging wrappers `mkdir`, `cat` and `chmod`, each forwarding to the real binary by absolute path;
    - call `load_mocks` with `LOAD_MOCKS_AI_CONFIG` unset (Task 2 adds the gate; until then, call it as is);
    - assert the log holds exactly one `mkdir` line, no `cat` line and no `chmod` line.

    The `mkdir` line is the positive control, and Task 2 keeps this test.

  - `PATH` filter:
    - for each shape `M:/usr/bin:/bin`, `/usr/bin:M:/bin`, `/usr/bin:/bin:M`, `M:M:/usr/bin:/bin`, `:/usr/bin:M:/bin` and `/usr/bin:M:/bin:`, where `M=${REPO_ROOT}/tests/mocks`, run `load_mocks` in a subshell with that `PATH`;
    - assert `_AI_CONFIG_GIT` equals `PATH=/usr/bin:/bin command -v git` and does not start with `M`;
    - with `PATH` set to just `M`, `load_mocks` returns 1 and prints `load_mocks: no real git outside tests/mocks on PATH`.
- [ ] **Green.**
  - Create the five files in `tests/stubs/` with each body copied verbatim from its heredoc in `load_mocks`. The one change is in `brew-stub`, whose log path is the literal text `"${BATS_TEST_TMPDIR:?}/brew-calls"`.
  - `chmod 755` all five and `git add` them; check the index mode with `git ls-files -s tests/stubs` (expect 100755).
  - In `load_mocks`:
    - delete the five `cat > … << STUB … STUB` blocks and their `chmod +x` lines, and export the five variables to `${REPO_ROOT}/tests/stubs/<name>`;
    - merge the `mkdir -p` calls at `common.bash:94`, `:125` and `:161` into one, kept under `if [[ -n "${BATS_TEST_TMPDIR:-}" ]]`;
    - replace the `IFS=: read`/`for` loop with parameter expansion:

    ```bash
    local _m="${REPO_ROOT}/tests/mocks" _p=":${PATH}:"
    while [[ ${_p} == *":${_m}:"* ]]; do _p="${_p//:"${_m}":/:}"; done
    _p="${_p#:}"; _clean_path="${_p%:}"
    ```

  - `tests/setup_env/doctor_brew_links.bats:17`: replace `[[ "${_BREW_BIN}" == "${BATS_TEST_TMPDIR}"/* ]]` with `[[ "${_BREW_BIN}" == "${REPO_ROOT}/tests/stubs/brew-stub" ]]`. Keep the test's other lines and its title intent: "_BREW_BIN is an executable stub".
- [ ] **Mutation controls**, in a copy:
  - re-add one `cat > "${_BREW_AZ_BIN}"` line: the exec-count test goes red;
  - drop the `while` loop, leaving the single `//` replacement: the `M:M:` case goes red;
  - change `brew-stub` back to a fixed path: the brew-calls test goes red.
- [ ] **Gates.** `make test`; record the result in the report.
- [ ] **Commit** via `caveman:caveman-commit`.

**Interfaces:** Produces the `${REPO_ROOT}/tests/stubs/<name>` paths and the exec-count test, which Task 2 extends.

### Task 2: ai-config fixture opt-in with loud failure

```yaml-task
id: 2
description: Build the ai-config fixture only under LOAD_MOCKS_AI_CONFIG=1, opt workflows.bats in, move the install_guards fixture test, pin the loud failure and add the static guard
role: executor
model: sonnet
tdd: required
requirements: [R5, R6, R7, R11]
acceptance:
  - cmd: bats tests/helpers_load_mocks.bats tests/setup_env/workflows.bats tests/setup_env/install_guards.bats
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - tests/helpers/common.bash
  - tests/helpers_load_mocks.bats
  - tests/setup_env/workflows.bats
  - tests/setup_env/install_guards.bats
depends_on: [1]
```

**Steps:**

- [ ] **Red: write the tests first.**
  - In `tests/helpers_load_mocks.bats`:
    - Without `LOAD_MOCKS_AI_CONFIG`, `_OVERRIDE_AI_CONFIG_DIR` equals exactly `${BATS_TEST_TMPDIR}/ai-config-absent--set-LOAD_MOCKS_AI_CONFIG=1`, and `[ ! -e "${_OVERRIDE_AI_CONFIG_DIR}" ]`.
    - With `LOAD_MOCKS_AI_CONFIG=1`, `_OVERRIDE_AI_CONFIG_DIR` is under `BATS_TEST_TMPDIR`, and `run _ai_config_tracked_items "${_OVERRIDE_AI_CONFIG_DIR}" .claude` gives status 0 and output `settings.json`. This needs `load_setup_env`. It replaces the `install_guards.bats` test "load_mocks defaults _OVERRIDE_AI_CONFIG_DIR to a tracked fixture under BATS_TEST_TMPDIR" (lines 1887-1893), which you delete there.
    - Static guard. For every file from `git ls-files 'tests/*.bats' 'tests/**/*.bats'` (`env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE`), find lines that call `run_setup_user` or `setup_dotfile_symlinks` in command position:
      - such lines match `^[[:space:]]*(run[[:space:]]+)?(run_setup_user|setup_dotfile_symlinks)([[:space:]]|$)`;
      - skip lines whose first non-blank character is `#`, `@test` lines and `declare -f` lines.

      A file with a calling line must contain `LOAD_MOCKS_AI_CONFIG=1`, or `_OVERRIDE_AI_CONFIG_DIR=`, or a redefinition `^[[:space:]]*(run_setup_user|setup_dotfile_symlinks)\(\)`. Otherwise the test prints `<file>: calls run_setup_user/setup_dotfile_symlinks without LOAD_MOCKS_AI_CONFIG=1` and fails. Positive control: the calling-file set is non-empty and contains `tests/setup_env/workflows.bats`.

      Measured at `5c5e1c60`: the calling files are `extracted_functions`, `install_guards` and `workflows`, the first two with their own override. `launch_agents`, `cargo_tools_update` and `unit` mention the names only in titles, comments or `declare -f`.
  - In `tests/setup_env/workflows.bats`, the loud-failure test:

    ```bash
    unset LOAD_MOCKS_AI_CONFIG; load_mocks
    run run_setup_user
    [ "${status}" -eq 1 ]
    [[ ${output} == *"Cannot list tracked items"* ]]
    [[ ${output} == *"LOAD_MOCKS_AI_CONFIG=1"* ]]
    ```

    Copy the `run_setup_user` stubs the neighbouring `run_setup_user` tests set before calling it.
- [ ] **Green.**
  - In `load_mocks`, wrap the `track_ai_config_fixture` call so it runs only when `[[ ${LOAD_MOCKS_AI_CONFIG:-} == 1 ]]`. Otherwise export `_OVERRIDE_AI_CONFIG_DIR="${BATS_TEST_TMPDIR}/ai-config-absent--set-LOAD_MOCKS_AI_CONFIG=1"` and create nothing.
  - In `tests/setup_env/workflows.bats` `setup()`, add `export LOAD_MOCKS_AI_CONFIG=1` before `load_mocks`.
- [ ] **Mutation controls**, in a copy:
  - always build the fixture: the absent-path test and the loud-failure test go red;
  - delete the `workflows.bats` opt-in: the static guard reports `tests/setup_env/workflows.bats`.
- [ ] **Gates and commit**, as in Task 1.

**Interfaces:** Consumes Task 1's `load_mocks` and exec-count test (which must still show exactly one `mkdir` with the opt-in unset).

### Task 3: constants.sh single uname, no sed or dirname

```yaml-task
id: 3
description: Compute _LINUX_ARCH and _RUSTUP_TRIPLE from one uname -m by substring replacement and DOTFILES_REPO_ROOT without dirname, values unchanged
role: executor
model: sonnet
tdd: required
requirements: [R8, R9]
acceptance:
  - cmd: bats tests/setup_env/unit.bats
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - lib/constants.sh
  - tests/setup_env/unit.bats
depends_on: [2]
```

**Steps:**

- [ ] **Red: write the tests first.** In `tests/setup_env/unit.bats`, add a helper that, for a given `uname -m` value, writes a `uname` stub to a temp dir and prints the variables from a fresh `bash`:

  ```bash
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "%s"\n' "$1" > "${d}/uname"
  chmod +x "${d}/uname"
  PATH="${d}:/usr/bin:/bin" bash -c 'source "$1/lib/constants.sh"; printf "%s %s\n" "$_LINUX_ARCH" "$_RUSTUP_TRIPLE"' _ "${REPO_ROOT}"
  ```

  Assert:
  - `x86_64` gives `amd64 x86_64-unknown-linux-gnu`;
  - `aarch64` gives `arm64 aarch64-unknown-linux-gnu`;
  - `arm64` gives `arm64 arm64-unknown-linux-gnu`;
  - `x86_64_v2` gives `amd64_v2 x86_64_v2-unknown-linux-gnu`.

  Then:
  - `DOTFILES_REPO_ROOT` equals `${REPO_ROOT}` (resolved with `cd … && pwd -P`, compared the same way) when sourced as `lib/constants.sh` from the root, as `../lib/constants.sh` from `tests/`, and as `constants.sh` from `lib/`;
  - `bash -e -c 'cd "$1" && source lib/constants.sh && echo ok' _ "${REPO_ROOT}"` prints `ok`;
  - `_UNAME_M` is set to the stubbed value.

  These tests pass on the old code for every case except the `_UNAME_M` case, which is the red one. Run them on the old code and record which pass.

- [ ] **Green.** In `lib/constants.sh`:
  - `_UNAME_M="$(uname -m)"`;
  - `_LINUX_ARCH="${_UNAME_M/x86_64/amd64}"`, then `_LINUX_ARCH="${_LINUX_ARCH/aarch64/arm64}"`;
  - `_RUSTUP_TRIPLE="${_UNAME_M}-unknown-linux-gnu"`;
  - for `DOTFILES_REPO_ROOT`, use the snippet below, keeping its `readonly` line:

  ```bash
  _CONSTANTS_DIR="${BASH_SOURCE[0]%/*}"
  [[ ${_CONSTANTS_DIR} == "${BASH_SOURCE[0]}" ]] && _CONSTANTS_DIR=.
  DOTFILES_REPO_ROOT="$(cd "${_CONSTANTS_DIR}/.." && pwd)"
  unset _CONSTANTS_DIR
  ```

  The `[[ … ]] && …` line must not be the file's last command; it is not. Keep every existing comment on these lines, updating only text that names `sed` or `dirname`. Add `_UNAME_M` with a one-line `# read by` comment naming its two consumers.

- [ ] **Mutation controls**, in a copy:
  - exact-match `case` for `_LINUX_ARCH`: the `x86_64_v2` case goes red;
  - drop the no-slash fallback: the `constants.sh`-from-`lib/` case goes red.
- [ ] **Gates and commit**, as in Task 1.

### Task 4: CLAUDE.md and Backlog

```yaml-task
id: 4
description: Update the CLAUDE.md fixture-default and mocks-vs-stubs lines and the Backlog part-2 row (docs only, no behaviour change, so no TDD)
role: executor
model: sonnet
tdd: not-applicable
requirements: []
acceptance:
  - cmd: make lint
    exit_code: 0
  - cmd: grep -q 'LOAD_MOCKS_AI_CONFIG=1' CLAUDE.md
    exit_code: 0
  - cmd: grep -q 'tests/stubs/' CLAUDE.md
    exit_code: 0
  - cmd: '! grep -q "defaults \`_OVERRIDE_AI_CONFIG_DIR\` to a tracked fixture" CLAUDE.md'
    exit_code: 0
max_retries: 2
files_touched:
  - CLAUDE.md
  - docs/superpowers/README.md
depends_on: [3]
```

**Steps:**

- [ ] **`CLAUDE.md`, Test Seams.** Replace the line beginning ``- `load_mocks` defaults `_OVERRIDE_AI_CONFIG_DIR` to a tracked fixture`` with:

  > `load_mocks` builds the ai-config fixture only under `LOAD_MOCKS_AI_CONFIG=1` (`workflows.bats`); otherwise `_OVERRIDE_AI_CONFIG_DIR` points at a missing path named after that remedy. A test needing other contents overrides it and calls `track_ai_config_fixture`.

  Keep the existing `→` pointer.

- [ ] **`CLAUDE.md`, Mock Pattern.** Add one bullet:

  > `tests/mocks/` is prepended to `PATH`, so a file there shadows the same-named command; put a stub reached only through a `_*_BIN` seam in `tests/stubs/` when its name would shadow a real command.

- [ ] **`docs/superpowers/README.md`.** In the P1 row "bats process-spawn cost (part 2 of the setup floor)", record the setup trim as shipped (spec path), and keep test-body spawn counts as the open remainder. Do not touch the All Plans status.
- [ ] **Gates.** No `make test`: neither file is read by the suite. Run the four `acceptance:` commands. The orchestrator runs `make test` and V1 afterwards.
- [ ] **Commit** via `caveman:caveman-commit`.

### Orchestrator, after Task 4

- [ ] Run `make test` once at the head.
- [ ] Run V1 as specified in Verification.
- [ ] Update ai-config `docs/knowledge/dotfiles-test-seams.md`, sections `load_mocks _OVERRIDE_AI_CONFIG_DIR default` and `_AI_CONFIG_GIT seam`, to match. Do it in ai-config's own worktree and PR, after messaging the ai-config session per git-workflow-020.

## Non-goal check

One fresh reviewer, 2026-11-01: 4 CLEAR, 0 CONFLICT, 0 UNCLEAR.

- N1 CLEAR: only `doctor_brew_links.bats:17` and the moved `install_guards.bats` test change existing bodies, both named exceptions; the `workflows.bats` edit is in `setup()`.
- N2 CLEAR: nothing under `tests/mocks/` is touched.
- N3 CLEAR: only temp dirs go on `PATH` (Task 1's shim dir, Task 3's `uname` stub dir).
- N4 CLEAR: no `setup_file` anywhere.
