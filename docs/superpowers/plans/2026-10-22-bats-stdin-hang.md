# bats stdin hang Implementation Plan

spec: docs/superpowers/specs/2026-10-22-bats-stdin-hang-design.md

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** No bats run started by this repo's recipes inherits a caller's stdin, and `tests/mocks/gpg` reads stdin only when real gpg would.

**Architecture:** `< /dev/null` on every `bats` recipe line in the `Makefile` (`test`, `test-unit`) and on the bats invocation in `scripts/run-bash-coverage.sh`; `tests/mocks/gpg` parses its arguments and drains stdin only for `--dearmor`/`--enarmor` with no file operand, or a `-` operand. bats tests pin both.

**Tech Stack:** GNU make, bash, bats.

## Global Constraints

- Argument-taking options in the gpg rule: `-o`, `--output`, `--homedir`, `--status-fd`, `--keyring`; their argument is not an operand.
- N1: no assertion weakened or removed; an exact-match expectation of a recipe line may change only to include the new redirect (`tests/makefile_parallel_target.bats` "a carved-out file leaves the parallel pool and runs alone afterwards", `grep -qx`).
- N2: no mock other than `tests/mocks/gpg` changes. N3: no `BATS_TEST_TIMEOUT` in the `Makefile`, `scripts/` or `tests/helpers/`.
- New test names start `stdin: ` (the acceptance counts key on it). Fixture git and make calls in tests follow each file's existing helpers and `unset MAKEFLAGS MFLAGS MAKELEVEL JOBS` convention.
- `make test` takes about 2 min here: run it in the foreground with Bash `timeout: 600000`, `< /dev/null`, output to a file.

## Verification Planning

- **V1:** `make test` exits 0 on the branch.
- **V2 (orchestrator, before PR):** from the branch worktree, `mkfifo f; exec 3<>f; timeout 600 bats tests/setup_env/check_versions_feeds.bats tests/setup_env/workflows.bats <&3` completes with `1..393` and 0 `not ok` (on master it stalls after `ok 133`). Record in the PR body.
- **V3 (orchestrator, after merge):** narrow the P2 backlog row to the timeout remainder with the spec's "Why no timeout" measurements.
- Edge cases: `HAVE_PARALLEL=` serial path, a `BATS_SERIAL_FILES` carve-out, `test-unit`, `gpg --dearmor -o -`.

---

### Task 1: Redirect stdin on every bats recipe line

```yaml-task
id: 1
description: Append < /dev/null to the four Makefile bats lines and the coverage runner's bats call, with stdin-prefixed tests
role: executor
model: sonnet
tdd: required
requirements: [R1, R2, R4]
acceptance:
  - cmd: '[ "$(grep -c "^@test \"stdin: " tests/makefile_parallel_target.bats)" -eq 4 ] && [ "$(grep -c "^@test \"stdin: " tests/scripts/unit.bats)" -eq 1 ]'
    exit_code: 0
  - cmd: bats tests/makefile_parallel_target.bats tests/scripts/unit.bats
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [Makefile, scripts/run-bash-coverage.sh, tests/makefile_parallel_target.bats, tests/scripts/unit.bats]
depends_on: []
```

**Change:** append ` < /dev/null` to the `bats --jobs $(JOBS) …`, `bats $(BATS_FLAGS) $(BATS_PARALLEL_FILES)` and `bats $(BATS_FLAGS) $(BATS_SERIAL_FILES)` lines of the `test` recipe and the `bats $(BATS_FLAGS) …` line of `test-unit`; in `scripts/run-bash-coverage.sh` change `"${_bats_bin}" "${_bats_args[@]}" > "${bats_log}" 2>&1` to add `< /dev/null`. Update the `grep -qx` expected string in "a carved-out file leaves the parallel pool and runs alone afterwards" to the new line, keeping `-x`.

**Tests** (reuse the file's existing `make -n` harness, mock `parallel` setup and env unsets):

1. `tests/makefile_parallel_target.bats` "stdin: --jobs line redirects stdin" (GNU parallel present).
2. "stdin: serial line redirects stdin" (`HAVE_PARALLEL=`).
3. "stdin: carve-out line redirects stdin" (`BATS_SERIAL_FILES=tests/setup_env/git_hooks.bats`).
4. "stdin: test-unit line redirects stdin" (`make -n test-unit`).
   Each asserts at least one line starts `bats` and every such line ends with `< /dev/null`.
5. `tests/scripts/unit.bats` "stdin: run-bash-coverage.sh bats call redirects stdin": the line containing `"${_bats_bin}" "${_bats_args[@]}"` also contains `< /dev/null`.

**Mutation control (report):** drop the redirect from each of the four Makefile lines in turn and from the runner; the matching case goes red each time.

---

### Task 2: gpg mock drains stdin only when gpg would

```yaml-task
id: 2
description: Make tests/mocks/gpg drain stdin only for --dearmor/--enarmor with no file operand or a - operand, with five stdin-prefixed tests
role: executor
model: sonnet
tdd: required
requirements: [R3, R4]
acceptance:
  - cmd: '[ "$(grep -c "^@test \"stdin: " tests/setup_env/mocks_gpg.bats)" -eq 5 ]'
    exit_code: 0
  - cmd: bats tests/setup_env/mocks_gpg.bats
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [tests/mocks/gpg, tests/setup_env/mocks_gpg.bats]
depends_on: []
```

**Change:** in `tests/mocks/gpg`, keep the `printf "gpg %s\n" "$*" >> "${MOCK_CALLS_FILE}"` log line; walk `"$@"`: an argument-taking option (Global Constraints list) consumes the next word; `--dearmor`/`--enarmor` sets a flag; `-` is a stdin operand; any other non-option word is a file operand. Drain stdin (the existing `while IFS= read -r _` loop) only if (flag set and no file operand) or a `-` operand was seen. Keep the file `#!/usr/bin/env bash`, executable, shellcheck-clean.

**Tests** — new `tests/setup_env/mocks_gpg.bats`, modelled on `tests/setup_env/mocks_sudo.bats` (set `MOCK_CALLS_FILE` under `BATS_TEST_TMPDIR`; an open FIFO via `mkfifo f; exec 3<>f`; each FIFO case runs under `timeout 5` and closes fd 3 after):

1. "stdin: --list-keys with an open FIFO returns without reading" (rc 0, call logged).
2. "stdin: --dearmor consumes a file on stdin" (feed a file of known bytes on a shared fd; after the mock, a further read on that fd sees EOF).
3. "stdin: --dearmor -o out consumes stdin (-o's argument is not an operand)".
4. "stdin: --dearmor key.asc with an open FIFO returns (file operand)".
5. "stdin: --dearmor -o - consumes stdin (- is -o's argument)".

**Mutation control (report):** always drain → cases 1 and 4 red; never drain → cases 2, 3, 5 red; drop `-o` from the argument list → case 3 or 5 red.

---

## Non-goal check
