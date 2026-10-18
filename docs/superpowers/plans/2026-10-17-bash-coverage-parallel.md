# Bash Coverage Parallel Implementation Plan

> **Status: DONE** — merged in #346 (727e9cb2), 2026-10-17. V1 and V2 recorded in the PR body; V3 (cap re-size after three parallel runs) is a backlog row.

spec: docs/superpowers/specs/2026-10-17-bash-coverage-parallel-design.md

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run the traced coverage suite with `bats --jobs`, run `make lint`'s shellcheck passes through `xargs -P`, and provision GNU parallel on Ubuntu.

**Architecture:** The `Makefile` decides whether coverage runs in parallel and hands `COVERAGE_BATS_JOBS` to `scripts/run-bash-coverage.sh`. The script turns that into a bats argv through `_coverage_bats_args`. The trace filter is untouched. `make lint` keeps its file lists and pipes them through `xargs -n 4 -P $(JOBS)`. `install_bats_linux` also ensures GNU parallel, judged by its version string.

**Tech Stack:** bash, GNU Make (4.x and 3.81), bats, shellcheck, xargs (GNU and BSD), apt.

## Global Constraints

- The 91% floor, the union-with-trace rule, the coverable-line heuristic and the trace filter pipeline are unchanged (N1).
- `.github/workflows/ci.yml` is not changed (N2). No bats file is added to `BATS_SERIAL_FILES` (N3).
- No test runs the full traced suite or reaches `run-bash-coverage.sh`'s main run (N4). The main run writes the fixed `coverage/bash_trace.fifo` that CI's own traced run uses.
- `run-bash-coverage.sh`'s `--json` parsing and unknown-option guard are unchanged (N5). New flags are handled above the guard.
- Shellcheck severities, the `SHELL_FILES`/`BATS_FILES` definitions and the missing-tool guard are unchanged (N6).
- Never `source scripts/run-bash-coverage.sh`: it has no sourcing guard.
- `make test` takes about 190s on `claude`. Run it synchronously with `timeout: 600000` and `< /dev/null`.

## Verification

- **Script:** `COVERAGE_BATS_JOBS=24 bash scripts/run-bash-coverage.sh --print-bats-args` prints `--jobs`, `24`, `--recursive`, the tests dir, and `bats mode: parallel (--jobs 24)`.
- **Recipe:** `make --no-print-directory -n bash-coverage` prints `COVERAGE_BATS_JOBS=24` on a host with GNU parallel. With `HAVE_PARALLEL=` it prints `env -u COVERAGE_BATS_JOBS`.
- **Lint:** `make lint` exits 0 and the shellcheck passes run under `xargs -P`. A file with a finding still fails it.
- **V1 (orchestrator):** in `ubuntu:24.04` with `--cpus 4`, as a non-root user, run `make bash-coverage` twice per mode. All four runs show 0 `not ok`, identical unique `file:line` sets, and the same overall figure.
- **V4 (orchestrator):** time `make lint` before and after Task 3.
- **V2:** the PR's `bash-coverage` job logs `bats mode: parallel (--jobs 24)`, passes 91%, and finishes in under 20 minutes.

---

### Task 1: Coverage script builds the bats argv from COVERAGE_BATS_JOBS

```yaml-task
id: 1
description: Add _coverage_bats_args, route the main run's bats call and mode line through it, add --print-bats-args and the -h text
role: executor
model: sonnet
tdd: required
requirements: [R2, R3, R4, R5, R6, R7]
acceptance:
  - cmd: make test
    exit_code: 0
  - cmd: 'COVERAGE_BATS_JOBS=6 bash scripts/run-bash-coverage.sh --print-bats-args'
    exit_code: 0
    stdout_match: 'bats mode: parallel \(--jobs 6\)'
  - cmd: '! command grep -nE "^[[:space:]]*bats --recursive" scripts/run-bash-coverage.sh'
    exit_code: 0
max_retries: 3
files_touched: [scripts/run-bash-coverage.sh, tests/scripts/unit.bats]
depends_on: []
```

**Files:** `scripts/run-bash-coverage.sh` (main run around the `_bats_bin` check, `mkfifo`, and the literal `bats --recursive` call), `tests/scripts/unit.bats`.

**Steps:**

- [ ] Add tests next to `run-bash-coverage.sh -h documents both inspection flags`, covering spec Testing cases 1–4. Drive them through the existing `_run_coverage` helper. Case 2 uses `env -u COVERAGE_BATS_JOBS`, because the variable is inherited inside CI's traced run.
  - Case 3 runs only through `--print-bats-args`, never the bare script, for each of `0`, `07`, `x`, `-1`, `2 3`: exit 2, with stderr naming the value.
  - Case 4 is structural (`command grep`): the main run has `_out="$(_coverage_bats_args)" || exit 2` before the first `mkfifo`, it has `bats "${_bats_args[@]}"`, and no literal `bats --recursive` call remains.
  - Extend the `-h` test to assert `--print-bats-args` and `COVERAGE_BATS_JOBS`.
- [ ] Run the new tests and confirm they are RED for the right reason. `--print-bats-args` should hit the unknown-option guard and exit 2.
- [ ] Implement `_coverage_bats_args`, defined before the flag dispatch. Validate the value with a `case` (a positive integer, no leading zero). On failure print `COVERAGE_BATS_JOBS must be a positive integer, got '<value>'` to stderr and return 1.
- [ ] Add a `--print-bats-args` branch above the unknown-option guard. It prints the lines, then the mode line, and exits 0, or 2 on an invalid value.
- [ ] Main run:
  - Insert the capture right after the `_bats_bin` presence check and before `mkdir -p "${OUTPUT_DIR}"`.
  - Use `mapfile -t _bats_args <<<"${_out}"`. A here-string, not `< <(…)`.
  - Print the mode line, derived from the array.
  - Replace the literal call with `"${_bats_bin}" "${_bats_args[@]}" > "${bats_log}" 2>&1`.
- [ ] Add `--print-bats-args` and a `COVERAGE_BATS_JOBS` paragraph to the usage heredoc.
- [ ] GREEN, then `make test`, then commit.

**Interfaces:**

- Produces: `_coverage_bats_args`. No arguments; reads `COVERAGE_BATS_JOBS`; prints one argument per line; returns 1 on an invalid value.
- Produces: the mode line text `bats mode: parallel (--jobs <n>)` or `bats mode: serial`.

### Task 2: bash-coverage recipe passes COVERAGE_BATS_JOBS

```yaml-task
id: 2
description: Parse-time conditional in the bash-coverage recipe passes COVERAGE_BATS_JOBS=$(JOBS) or runs under env -u, with make -n tests
role: executor
model: sonnet
tdd: required
requirements: [R1, R7]
acceptance:
  - cmd: make test
    exit_code: 0
  - cmd: 'env -u MAKEFLAGS -u JOBS make --no-print-directory -n bash-coverage HAVE_PARALLEL=yes JOBS=6 BATS_SERIAL_FILES='
    exit_code: 0
    stdout_match: 'COVERAGE_BATS_JOBS=6'
  - cmd: 'env -u MAKEFLAGS -u JOBS make --no-print-directory -n bash-coverage HAVE_PARALLEL='
    exit_code: 0
    stdout_match: 'env -u COVERAGE_BATS_JOBS'
max_retries: 3
files_touched: [Makefile, tests/makefile_parallel_target.bats]
depends_on: [1]
```

**Files:** the `Makefile` `bash-coverage:` target (currently `@bash scripts/run-bash-coverage.sh`) and `tests/makefile_parallel_target.bats`.

**Steps:**

- [ ] Add tests for spec cases 5–6 to `tests/makefile_parallel_target.bats`, following its existing `unset MAKEFLAGS MFLAGS MAKELEVEL JOBS` setup. Use `make --no-print-directory -C "${REPO_ROOT}" -n bash-coverage …`, with the `-C` and `--no-print-directory` on the same line so the partition scanner classes it as guarded.
  - Case 6 runs two separate invocations: `HAVE_PARALLEL=`, and `HAVE_PARALLEL=yes BATS_SERIAL_FILES=tests/x.bats`. Assert `env -u COVERAGE_BATS_JOBS` is present and `COVERAGE_BATS_JOBS=` absent.
- [ ] RED, then implement. Inside the recipe, use `ifeq ($(HAVE_PARALLEL)|$(strip $(BATS_SERIAL_FILES)),yes|)`; the existing `ifndef BATS` stays first. The `@COVERAGE_BATS_JOBS=$(JOBS) bash scripts/run-bash-coverage.sh` line goes under the `ifeq`, and `@env -u COVERAGE_BATS_JOBS bash scripts/run-bash-coverage.sh` under the `else`.
- [ ] GREEN, `make test`, commit.

**Interfaces:**

- Consumes: Task 1's script reading `COVERAGE_BATS_JOBS`.

### Task 3: make lint runs shellcheck through xargs -P

```yaml-task
id: 3
description: Both make lint shellcheck passes pipe their unchanged file list through xargs -n 4 -P $(JOBS), failing on any non-zero child
role: executor
model: sonnet
tdd: required
requirements: [R9, R11]
acceptance:
  - cmd: make test
    exit_code: 0
  - cmd: '[ "$(command grep -c "xargs -n 4 -P \$(JOBS)" Makefile)" -eq 2 ]'
    exit_code: 0
max_retries: 3
files_touched: [Makefile, tests/scripts/makefile_lint_scope.bats]
depends_on: [2]
```

**Files:** the `Makefile` `lint:` recipe (the two `shellcheck … $(SHELL_FILES)` and `shellcheck --severity=warning $(BATS_FILES)` lines) and `tests/scripts/makefile_lint_scope.bats`.

**Steps:**

- [ ] Add tests in the style of the `lint skip hint` tests (`env -u GIT_DIR …`, `PATH="${CLEAN_PATH}"`, `make --no-print-directory -C "${REPO_ROOT}" lint …`).
  - Build six shell files under `BATS_TEST_TMPDIR`. Make the sixth (the second `xargs` batch) contain an `SC2086` finding, and pass them as `SHELL_FILES="…" BATS_FILES="<one clean .bats>" ZSH_FILES="<one clean .zsh>"`. Assert non-zero status and no `shellcheck OK` line.
  - Repeat with the bad file in `BATS_FILES` at a warning-level finding, and assert no `shellcheck bats OK`.
  - A clean-only run prints both OK lines.
- [ ] RED. A serial recipe passes the clean case and fails the bad cases already, so pin the parallel form with a structural assertion: each pass line contains `xargs -n 4 -P $(JOBS)`.
- [ ] Implement:
  - `printf '%s\n' $(SHELL_FILES) | xargs -n 4 -P $(JOBS) shellcheck && printf "shellcheck OK\n" || { …failed=1; }`
  - the same for `BATS_FILES` with `--severity=warning`.

  Leave the guards, severities and lists untouched. A non-zero `xargs` (GNU 123/124/125, BSD 1) fails the pass.

- [ ] GREEN, `make test`, commit.

### Task 4: install_bats_linux ensures GNU parallel

```yaml-task
id: 4
description: install_bats_linux checks _PARALLEL_BIN for GNU parallel regardless of bats, apt-installs parallel when not GNU, re-checks, warns and returns non-zero if still not GNU
role: executor
model: sonnet
tdd: required
requirements: [R10, R11]
acceptance:
  - cmd: make test
    exit_code: 0
  - cmd: 'command grep -q "_PARALLEL_BIN" lib/linux_shared.sh'
    exit_code: 0
max_retries: 3
files_touched: [lib/linux_shared.sh, tests/setup_env/install_guards.bats]
depends_on: [3]
```

**Files:** `lib/linux_shared.sh` `install_bats_linux` (it currently returns 0 early when bats is present) and `tests/setup_env/install_guards.bats`.

**Steps:**

- [ ] Add tests covering every case R11 names. Drive parallel only through `_PARALLEL_BIN` stubs written under `BATS_TEST_TMPDIR`: one prints `GNU parallel 20240222`, one prints `parallel from moreutils`, and one is a nonexistent path.
  - Use `tests/mocks/apt-get` and `MOCK_CALLS_FILE` for install assertions, and `SHIM_APT_FAIL_PKGS` or `MOCK_APT_FAIL_SUBCMD` for an install failure.
  - For "still non-GNU after install", the stub keeps printing moreutils. Assert a warning naming `command -v parallel` and a non-zero rc.
  - Pin the existing `skips install when bats is already present` test to the GNU stub.
- [ ] RED, then implement:
  - Restructure so the bats check no longer returns early. Each of bats and parallel is ensured independently, and any failure yields rc 1.
  - The parallel install is `sudo -H DEBIAN_FRONTEND=noninteractive apt-get install "${APT_CONFFILE_OPTS[@]}" -y parallel`, the form `tests/scripts/dpkg_sudo_frontend.bats` already accepts.
  - The seam line is `local _parallel="${_PARALLEL_BIN:-parallel}"`.
- [ ] GREEN, `make test`, commit.

### Task 5: Document the parallel coverage, lint and provisioning

```yaml-task
id: 5
description: CLAUDE.md Coverage > Bash bullet for COVERAGE_BATS_JOBS and overrides; lint and install_bats_linux notes (docs-only, no behaviour change)
role: executor
model: haiku
tdd: not-applicable
requirements: [R8]
acceptance:
  - cmd: 'command grep -q "COVERAGE_BATS_JOBS" CLAUDE.md'
    exit_code: 0
  - cmd: 'command grep -q "make bash-coverage HAVE_PARALLEL=" CLAUDE.md'
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 2
files_touched: [CLAUDE.md]
depends_on: [4]
```

**Steps:**

- [ ] Under `### Coverage` > `#### Bash`, add one bullet after the "Publish CI's bash coverage figure" bullet. It says that `make bash-coverage` passes `COVERAGE_BATS_JOBS=$(JOBS)` when GNU parallel is detected and `BATS_SERIAL_FILES` is empty, and runs serially otherwise. It names the overrides `make bash-coverage HAVE_PARALLEL=` and `JOBS=<n>`, and notes that `HAVE_PARALLEL= make …` is ignored, because the `Makefile` reassigns it with `:=`.
- [ ] In the Testing bullet beginning "Detect GNU parallel by version string", add one sentence: `install_bats_linux` installs GNU `parallel` on Ubuntu, because the apt package diverts moreutils' binary to `/usr/bin/parallel.moreutils`.
- [ ] In the **Run lint only** paragraph, add one sentence: both shellcheck passes run through `xargs -n 4 -P $(JOBS)`.
- [ ] `make lint`, commit. The orchestrator runs `make test` once after this task.

---

## Orchestrator steps after Task 5

- [ ] Record V4: `make lint` time on `claude`, against the 56.6s pre-change baseline measured on `1e29afb1`.
- [ ] Run V1 in `ubuntu:24.04` with `--cpus 4`, as a non-root user with bats, parallel, shellcheck and zsh installed: two runs of `make bash-coverage HAVE_PARALLEL=` and two of `make bash-coverage`. Then `comm -3` the four `coverage/bash_trace.txt` unique sets, and compare the `Overall bash coverage:` lines.
- [ ] Open the PR. It is a normal PR, since all tasks are done before the push. Watch CI and record V2 in the PR body.

## Non-goal check

Reviewer verdicts (2026-10-17): N1 CLEAR, N2 CLEAR, N3 CLEAR, N5 CLEAR, N6 CLEAR.

- **N4 — UNCLEAR.**
  - **Quote:** Task 1 says "Case 3 checks each of `0`, `07`, `x`, `-1`, `2 3`: exit 2, with stderr naming the value." It also says "Insert the capture right after the `_bats_bin` presence check and before `mkdir -p "${OUTPUT_DIR}"`."
  - **Why:** the plan did not say whether case 3 invokes `--print-bats-args`, which is inert, or the bare script, which would enter the main run.
  - **Resolution (plan revision):**
    - Before: "Case 3 checks each of `0`, `07`, `x`, `-1`, `2 3`: exit 2, with stderr naming the value."
    - After: "Case 3 runs only through `--print-bats-args`, never the bare script, for each of `0`, `07`, `x`, `-1`, `2 3`: exit 2, with stderr naming the value."

