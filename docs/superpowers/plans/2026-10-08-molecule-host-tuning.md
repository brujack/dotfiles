# Molecule Host Tuning (inotify limit) Implementation Plan

> **Status: DONE** — merged in #323 (cf5577e8), 2026-10-08.

spec: docs/superpowers/specs/2026-10-08-molecule-host-tuning-design.md

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist `fs.inotify.max_user_instances = 1024` on Linux docker hosts via `-t setup`/`-t developer`, and report it in `-t doctor`.

**Architecture:** A new first step `_install_ubuntu_inotify` in `install_ubuntu_packages` writes `/etc/sysctl.d/90-dotfiles-inotify.conf` and applies it, never lowering a higher value. `_doctor_check_inotify_limits` reports live and conf state. Four seams with production defaults; `load_mocks` points them at temp files for every test.

**Tech Stack:** bash, bats, existing `tests/mocks/*` and `SHIM_DIR` pattern.

**Worktree:** `/home/bruce/git-repos/personal/dotfiles-inotify`, branch `feat/inotify-limit`. All work happens there.

## Global Constraints

- Constant: `readonly INOTIFY_MAX_USER_INSTANCES=1024` in `lib/constants.sh`.
- Conf default `/etc/sysctl.d/90-dotfiles-inotify.conf`; content exactly `fs.inotify.max_user_instances = 1024`.
- Seams: `_SYSCTL_CONF`, `_SYSCTL_BIN` (default `sysctl`), `_INOTIFY_PROC` (default `/proc/sys/fs/inotify/max_user_instances`), `_SYSTEMD_RUN_DIR` (default `/run/systemd/system`).
- Never lower a live value or conf value above 1024 (N4). Never overwrite an existing conf that cannot be read or parsed.
- No `PARALLEL_JOBS` anywhere (N3); no other sysctl key (N1); nothing from `-t update`/`-t setup_user` (N2).
- Every bats/make invocation from a subagent ends `< /dev/null` (harness stdin socket deadlock).
- Commit messages via `caveman:caveman-commit`; end with the session's Co-Authored-By / Claude-Session trailers.

## Session-level verification

- `make test` (orchestrator, once, after Task 2) exits 0 from a shell with `HAS_DOCKER=1` and again with `env -u HAS_DOCKER`.
- Post-merge V1 per the spec's Verification section: step prints `inotify: conf written` and `inotify: applied` on `claude` and over ssh on `workstation`; then `sysctl` reads 1024 and doctor passes.
- Edge cases exercised by tests: conf `key=1024`, `/` spelling, duplicate keys (last wins), mode-000 conf, live non-numeric/missing, live 4096 (no apply), tee failure and tee writing nothing.

---

### Task 1: Install step, constant, seam defaults

```yaml-task
id: 1
description: Add INOTIFY_MAX_USER_INSTANCES, _install_ubuntu_inotify as first loop step, load_mocks seam defaults, and step tests
role: executor
model: sonnet
tdd: required
requirements: [R1, R2, R3, R4, R5, R7]
acceptance:
  - cmd: 'bats tests/setup_env/linux_ubuntu.bats tests/setup_env/workflows.bats < /dev/null'
    exit_code: 0
  - cmd: 'env -u HAS_DOCKER bats tests/setup_env/linux_ubuntu.bats tests/setup_env/workflows.bats < /dev/null'
    exit_code: 0
  - cmd: 'make lint < /dev/null'
    exit_code: 0
max_retries: 3
files_touched: [lib/constants.sh, lib/helpers.sh, lib/linux_ubuntu.sh, tests/helpers/common.bash, tests/setup_env/linux_ubuntu.bats, tests/setup_env/workflows.bats]
depends_on: []
```

**Files:** as `files_touched`.

**Steps (TDD, one behaviour at a time; write each failing test, run it red, implement, run green):**

1. `tests/helpers/common.bash` `load_mocks`: export `_SYSCTL_CONF="${BATS_TEST_TMPDIR}/sysctl.d/90-dotfiles-inotify.conf"` (create the `sysctl.d` dir, not the file), `_INOTIFY_PROC="${BATS_TEST_TMPDIR}/inotify_max_user_instances"` holding `1024`, `_SYSTEMD_RUN_DIR="${BATS_TEST_TMPDIR}/run-systemd"` (created dir), `_SYSCTL_BIN="${BATS_TEST_TMPDIR}/sysctl-stub"`: an executable stub appending `sysctl $*` to `${MOCK_CALLS_FILE}` and exiting `${MOCK_SYSCTL_STUB_EXIT:-0}`. Follow the existing `_BREW_AZ_BIN` stub shape there.
2. `lib/constants.sh`: `readonly INOTIFY_MAX_USER_INSTANCES=1024` near other pins.
3. `lib/linux_ubuntu.sh` `_install_ubuntu_inotify` (add a short why-comment citing the spec):
   - Gate: `HAS_DOCKER` set and `-d "${_SYSTEMD_RUN_DIR:-/run/systemd/system}"`, else print `inotify: skipped (<reason>)` to stdout, return 0.
   - Helper `_inotify_conf_value <file>` in `lib/helpers.sh` (shared with Task 2's doctor check): prints the last value assigned to `fs.inotify.max_user_instances` or `fs/inotify/max_user_instances`, optional leading `-`, whitespace around `=` ignored; prints nothing when no key. Use `awk`, not `read` (tabs).
   - Conf exists but `! -r` → stderr `inotify: <conf> exists but is unreadable; fix by hand`, return 1. Exists, readable, no parseable integer value → same with "unparseable", return 1. Never write in either case.
   - Write when absent or parsed value `< 1024`: `printf 'fs.inotify.max_user_instances = %s\n' "${INOTIFY_MAX_USER_INSTANCES}" | sudo tee "${_conf}" >/dev/null`; print `inotify: conf written`. Then read back: `! -r` → `inotify: cannot read back <conf>` rc 1; value not `>= 1024` → `inotify: write failed` rc 1.
   - Live: read `_INOTIFY_PROC`; not readable or not `^[0-9]+$` → stderr `inotify: cannot read live value <path>`, return 1, no apply. `>= 1024` → print `inotify: already 1024 or higher` (only when nothing written), return 0. Below 1024 → `sudo "${_SYSCTL_BIN:-sysctl}" -w "fs.inotify.max_user_instances=<conf value>"` (applies only this key, never `-p`); failure → `inotify: apply failed` rc 1; success → `inotify: applied`.
   - Add `inotify` as the FIRST element of the step loop in `install_ubuntu_packages`.
4. Tests in `tests/setup_env/linux_ubuntu.bats` (each sets `export HAS_DOCKER=1` or `unset HAS_DOCKER` explicitly), asserting status, conf content, recorded `sysctl` lines in `MOCK_CALLS_FILE`, and output line:
   - absent/live 128 → written + `sysctl -w fs.inotify.max_user_instances=1024` + `applied`; absent/live 4096 → written, no sysctl line.
   - `fs.inotify.max_user_instances=1024` live 1024 → unchanged, no call, `already`; `= 4096` live 4096 → unchanged, `already`.
   - `fs/inotify/max_user_instances = 4096` → unchanged; `= 512` then `= 4096` → unchanged; `= 512` → rewritten to 1024.
   - conf right, live 128 → no write (compare file content and `stat -c %Y` before/after), sysctl `-w ...=1024` called; conf `= 4096`, live 128 → `-w ...=4096`; live `abc` and live file missing → rc 1 `cannot read live value`, no sysctl call; conf holding an extra key (`fs.inotify.max_user_watches = 1`) and live 128 → only the instances key applied.
   - mode 000 conf → rc 1 `unreadable`, untouched; conf `# nothing` → rc 1 `unparseable`, untouched.
   - `MOCK_TEE_EXIT=1` → rc 1 `write failed`, no sysctl; `SHIM_DIR` `tee` shim that exits 0 writing nothing → rc 1 `write failed`; shim `tee` that writes then `chmod 000` → rc 1 `cannot read back`.
   - `MOCK_SYSCTL_STUB_EXIT=1` → rc 1 `apply failed`.
   - `HAS_DOCKER` unset, and `_SYSTEMD_RUN_DIR` absent → rc 0, `skipped` line, no file, no call.
   - Loop: inotify stub returning 1 → stderr names `inotify`, rc 2, a later step still ran; inotify is first called.
   - Existing tests at `:331`/`:345`: add `inotify` to the eval list, count 12 → 13. Clean-run test (`~:4464`) keeps `HAS_DOCKER=1` and now also asserts `inotify: conf written` in output.
5. `tests/setup_env/workflows.bats`: `_stub_ubuntu_steps` gains `_install_ubuntu_inotify() { :; }`; the "run_setup_or_developer calls apt-get on Ubuntu" test sets `unset HAS_DOCKER`.
6. Commit.

**Interfaces:**

- Produces: `INOTIFY_MAX_USER_INSTANCES`; `_inotify_conf_value <file>` (stdout value or empty, rc 0); the four seam defaults in `load_mocks`; `MOCK_SYSCTL_STUB_EXIT`.

---

### Task 2: Doctor check

```yaml-task
id: 2
description: Add _doctor_check_inotify_limits to run_doctor with tests and stubs in every stub-by-name run_doctor test
role: executor
model: sonnet
tdd: required
requirements: [R6, R7]
acceptance:
  - cmd: 'bats tests/setup_env/unit.bats tests/setup_env/plugin_node_paths.bats < /dev/null'
    exit_code: 0
  - cmd: 'env -u HAS_DOCKER bats tests/setup_env/unit.bats tests/setup_env/plugin_node_paths.bats < /dev/null'
    exit_code: 0
  - cmd: 'make lint < /dev/null'
    exit_code: 0
max_retries: 3
files_touched: [lib/helpers.sh, tests/setup_env/unit.bats, tests/setup_env/plugin_node_paths.bats]
depends_on: [1]
```

**Steps (TDD):**

1. `lib/helpers.sh` `_doctor_check_inotify_limits`, called from `run_doctor` after `_doctor_check_conffile_dist`. Uses the four seams and `_inotify_conf_value` (defined in `lib/helpers.sh` by Task 1).
   - Silent `return 0` unless `LINUX`, `HAS_DOCKER` and `-d` systemd dir.
   - Prints `\ninotify instances:\n` header like peers.
   - Live not `^[0-9]+$` → `doctor_fail "inotify" "cannot read ${_proc}"`.
   - Conf missing, unreadable, or value not `>= 1024` → `doctor_fail "inotify" "<conf> missing or below 1024; fix:"` then `printf '    %s\n' "printf 'fs.inotify.max_user_instances = 1024\n' | sudo tee <conf> && sudo sysctl -w fs.inotify.max_user_instances=1024"` (literal `\n` in the printed command).
   - Live `< 1024` → `doctor_fail "inotify" "live value <n> below 1024; fix:"` then `printf '    sudo sysctl -w fs.inotify.max_user_instances=%s\n' "<conf value>"`.
   - Else `doctor_pass "inotify" "max_user_instances <n>"`. Never mention `-t developer`.
2. Tests in `unit.bats` (export `LINUX=1 HAS_DOCKER=1` per test; seams from `load_mocks`): pass at 1024 and 4096; live 128 fail with the `sudo sysctl -w` line on its own line; conf missing, conf 512, conf mode 000 fail with the `tee` line; live `abc` fails `cannot read`; status 0 and empty output when `LINUX` unset, when `HAS_DOCKER` unset, when systemd dir absent. Assert output never contains `-t developer`.
3. Add `_doctor_check_inotify_limits() { :; }` beside every `_doctor_check_conffile_dist() { :; }` stub in `unit.bats` and `plugin_node_paths.bats` (`grep -n '_doctor_check_conffile_dist() { :; }'` lists them).
4. Commit.

**Interfaces:** Consumes `_inotify_conf_value`, `INOTIFY_MAX_USER_INSTANCES`, seam defaults from Task 1.

---

### Task 3: Documentation

```yaml-task
id: 3
description: CLAUDE.md Test Seams and doctor entry, README doctor line (docs-only, no behaviour change, so TDD not applicable)
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: 'grep -q "_SYSCTL_CONF" CLAUDE.md'
    exit_code: 0
  - cmd: 'grep -q "inotify" CLAUDE.md'
    exit_code: 0
  - cmd: 'make lint < /dev/null'
    exit_code: 0
max_retries: 2
files_touched: [CLAUDE.md, README.md]
depends_on: [2]
```

**Steps:**

1. `CLAUDE.md` Entry Points: `doctor` bullet lists "inotify instance limit (Linux docker hosts)"; `setup`/`developer` note that the Ubuntu loop's first step persists `fs.inotify.max_user_instances=1024`.
2. `CLAUDE.md` Test Seams: one bullet group for `_SYSCTL_CONF`/`_SYSCTL_BIN`/`_INOTIFY_PROC`/`_SYSTEMD_RUN_DIR` stating `load_mocks` exports them under `BATS_TEST_TMPDIR`, why (`tests/mocks/sudo` and `tests/mocks/sysctl` exec real binaries; `tests/mocks/tee` swallows failures, hence the read-back), and that tests reaching the real step set `HAS_DOCKER` themselves.
3. `README.md`: only if it lists doctor checks or setup steps; add one line in the same style. Otherwise leave it.
4. Commit.

Orchestrator after Task 3: `make test < /dev/null` with and without `HAS_DOCKER` (V2).

## Non-goal check

Reviewer: fresh reviewer subagent, 2026-10-08, against N1–N4.

- N1 UNCLEAR — quote: "`sudo sysctl -p \"${_conf}\"`, including when it keeps an existing conf". `-p` applies every key in a kept conf. Resolution: spec amendment R4/R6; plan before "`sudo \"${_SYSCTL_BIN:-sysctl}\" -p \"${_conf}\"`", after "`sudo \"${_SYSCTL_BIN:-sysctl}\" -w \"fs.inotify.max_user_instances=<conf value>\"`"; doctor remedies use `-w` too; new test with an extra key.
- N4 UNCLEAR — quote: "live `abc` and live file missing -> sysctl called". Could lower a real value above 1024. Resolution: spec amendment R4; plan before "live `abc` and live file missing → sysctl called", after "live `abc` and live file missing → rc 1 `cannot read live value`, no sysctl call".
- N2 CLEAR. N3 CLEAR.

