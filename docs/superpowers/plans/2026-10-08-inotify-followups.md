# inotify follow-ups Implementation Plan

spec: docs/superpowers/specs/2026-10-08-inotify-followups-design.md

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix backlog rows 180-183: parser reset, persist `max(live, 1024)` including a hand raise over an existing conf, doctor messages and WARN, and the `_SYSCTL_BIN` seam without sudo.

**Architecture:** Three functions change: `_inotify_conf_value` and `_doctor_check_inotify_limits` in `lib/helpers.sh`, `_install_ubuntu_inotify` in `lib/linux_ubuntu.sh`. Both callers share one rule: target = `max(live, 1024)`; the conf needs writing when missing or below the target. The spec's Design sections 1-4 are the authority for order, messages and caps.

**Tech Stack:** bash, awk, bats.

## Global Constraints

- The kernel cap is 2147483647. awk compares `line + 0 <= 2147483647`, never a bare `line <=` (after `sub()` it is a string). bash checks `[[ ${v} =~ ^(0|[1-9][0-9]{0,9})$ ]]` before any arithmetic, because bash arithmetic wraps.
- Every test runs under `load_mocks`' seams (`_SYSCTL_CONF`, `_INOTIFY_PROC`, `_SYSCTL_BIN`, `_SYSTEMD_RUN_DIR`). No test may reach `/etc/sysctl.d`, `/proc/sys`, `/usr/sbin/sysctl` or real sudo.
- Every assertion of an absence is paired with a positive assertion.
- Non-goals N1-N6 (spec): "fix by hand" path and messages unchanged; no `_inotify_conf_state` helper; nothing writes below live or below an existing conf; `sudo tee "${_conf}"` unchanged; no other key; conf not renamed, no other file written or removed.
- Commit messages via `caveman:caveman-commit`; stage exact paths.
- `make test` is run by the orchestrator once after Task 2, not by any task.

## Verification

- Session gate: `make test < /dev/null` exits 0 in the feature worktree after Task 2.
- Mutation controls (spec Testing), each applied by the implementing task, confirmed red, then reverted: drop the awk `val = ""` reset; compare the awk cap as a string; raise the cap to 9999999999; drop the bash live length check; replace the target with 1024; compare the conf only against 1024; always use sudo (Task 1); swap the doctor "below 1024"/"below live" order; make the below-live case FAIL; drop the `live < 1024` condition on the doctor suffix (Task 2).
- Post-merge V1 on `claude`: `./setup_env.sh -t doctor` passes the inotify check; the step prints `inotify: already 1024 or higher`; `sha256sum /etc/sysctl.d/90-dotfiles-inotify.conf` is unchanged. No-regression only.

---

### Task 1: Parser, install step and sysctl seam

```yaml-task
id: 1
description: Rewrite _inotify_conf_value (any RHS resets, INT_MAX cap) and _install_ubuntu_inotify (live first, target max(live,1024), messages, seam without sudo) with their tests
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: 'bats tests/setup_env/linux_ubuntu.bats tests/setup_env/workflows.bats < /dev/null'
    exit_code: 0
  - cmd: 'env -u HAS_DOCKER bats tests/setup_env/linux_ubuntu.bats < /dev/null'
    exit_code: 0
  - cmd: 'grep -q "persisted 4096 to" tests/setup_env/linux_ubuntu.bats'
    exit_code: 0
  - cmd: 'grep -q "read-back mismatch" lib/linux_ubuntu.sh'
    exit_code: 0
  - cmd: 'make lint < /dev/null'
    exit_code: 0
max_retries: 3
files_touched: [lib/helpers.sh, lib/linux_ubuntu.sh, tests/setup_env/linux_ubuntu.bats]
depends_on: []
requirements: [R1, R2, R3, R4]
```

**Files:** as `files_touched`. In `lib/helpers.sh` touch only `_inotify_conf_value`.

**Spec:** Design sections 1, 2 and 4; Testing "Parser", "Install" and "Seam" bullets.

- [ ] Parser: the awk match becomes key + `[ \t]*=` + any remainder; strip to the right-hand side; `val` = it when `^(0|[1-9][0-9]*)$`, `length <= 10` and `line + 0 <= 2147483647`, else `""`. Update the header comment.
- [ ] Install order: skips; conf classify (unchanged); read live from `_proc`, strip whitespace, reject unless `^(0|[1-9][0-9]{0,9})$` and `<= 2147483647` (stderr `inotify: cannot read live value <proc>`, rc 1, nothing written); `target=$(( live > 1024 ? live : 1024 ))` using `INOTIFY_MAX_USER_INSTANCES`; write when `_val` empty or `< target`; read back, rc 1 with stderr `inotify: read-back mismatch (<conf>)` unless it equals target; print `inotify: conf written (<target>)` (was missing) or `inotify: persisted <target> to <conf> (was <old>)`; live `>= 1024` returns 0; else apply.
- [ ] Apply: `if [[ -n ${_SYSCTL_BIN} ]]; then "${_SYSCTL_BIN}" -w ...; else sudo sysctl -w ...; fi`. On failure with the seam set: `inotify: apply failed (_SYSCTL_BIN set, ran without sudo)`; otherwise `inotify: apply failed`.
- [ ] Tests: replace `absent conf and live 4096 writes the conf and never applies` (now expects 4096). Update every test asserting the old `conf written` text. Add each Install, Parser and Seam case from the spec Testing section. The unset-seam test: `unset _SYSCTL_BIN`; a stub dir first on PATH holding `sysctl` that appends `STUB-MARKER-<unique> $*` to `MOCK_CALLS_FILE`; assert `[ "$(command -v sysctl)" = "${stub}/sysctl" ]` before the run; live 128; assert the marker line and a `sudo sysctl -w` line.
- [ ] Mutations (Verification list, Task 1 items): apply each, run the bats gate, confirm red, revert. Report each mutation and the failing test name.
- [ ] Commit.

**Interfaces:**

- Produces: `_inotify_conf_value <file>` prints a value in `0..2147483647` or nothing. Task 2 relies on this.

---

### Task 2: Doctor check

```yaml-task
id: 2
description: Rewrite _doctor_check_inotify_limits for the target rule, case order, WARN on below-live, next-boot messages and the INT_MAX live cap, with tests
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: 'bats tests/setup_env/unit.bats tests/setup_env/plugin_node_paths.bats < /dev/null'
    exit_code: 0
  - cmd: 'env -u HAS_DOCKER bats tests/setup_env/unit.bats < /dev/null'
    exit_code: 0
  - cmd: 'grep -q "a reboot may drop it" lib/helpers.sh'
    exit_code: 0
  - cmd: 'grep -q "next boot: kernel default" tests/setup_env/unit.bats'
    exit_code: 0
  - cmd: 'make lint < /dev/null'
    exit_code: 0
max_retries: 3
files_touched: [lib/helpers.sh, tests/setup_env/unit.bats]
depends_on: [1]
requirements: [R5]
```

**Files:** as `files_touched`. In `lib/helpers.sh` touch only `_doctor_check_inotify_limits`.

**Spec:** Design section 3; Testing "Doctor" bullets.

- [ ] Live read: same `^(0|[1-9][0-9]{0,9})$` plus `<= 2147483647` check as Task 1, else FAIL `cannot read <proc>` (existing text).
- [ ] Conf classification unchanged (N1). Then `target = max(live, 1024)` and, first match wins:
  - conf missing: FAIL `<conf> missing; next boot: kernel default; fix:`, then the `tee` line writing target.
  - conf value `< 1024`: FAIL `<conf> value <v> below 1024; next boot: <v>; fix:`, then the `tee` line writing target.
  - In both FAILs, append `&& sudo sysctl -w fs.inotify.max_user_instances=1024` only when live `< 1024`.
  - conf value `< live`: `doctor_warn` `<conf> value <v> below live <live>; a reboot may drop it; fix:`, then the `tee` line writing live.
  - live `< 1024`: unchanged remedy (`sudo sysctl -w ...=<conf value>`).
  - else PASS (unchanged text).
- [ ] Tests: update the existing missing/below tests to the new messages; add each Doctor case from the spec Testing section. The WARN case also runs `run_doctor` with every other sub-check stubbed by name, as `run_doctor runs the inotify check, and its FAIL fails doctor` does, and asserts exit 0 plus the WARN line.
- [ ] Mutations (Verification list, Task 2 items): apply, confirm red, revert, report.
- [ ] Commit.

**Interfaces:**

- Consumes: `_inotify_conf_value` from Task 1; `doctor_fail`, `doctor_warn`, `doctor_pass` in `lib/helpers.sh`.

---

### Task 3: Documentation and backlog

```yaml-task
id: 3
description: Docs-only (no behavior change, so tdd not-applicable) — CLAUDE.md setup entry and seam bullet, ADR-0044 consequences note, backlog rows 180-183 removed and one added
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: 'grep -q "higher of the live value and 1024" CLAUDE.md'
    exit_code: 0
  - cmd: 'grep -q "without sudo" CLAUDE.md'
    exit_code: 0
  - cmd: 'grep -qE "sorts? before .90-" docs/adr/0044-host-kernel-limits-persist-via-sysctl-d.md'
    exit_code: 0
  - cmd: '! grep -q "keeps an earlier value when the last assignment is non-numeric" docs/superpowers/README.md'
    exit_code: 0
  - cmd: 'grep -q "_SYSCTL_CONF. seam writes an env-chosen path as root" docs/superpowers/README.md'
    exit_code: 0
  - cmd: 'make lint < /dev/null'
    exit_code: 0
max_retries: 2
files_touched: [CLAUDE.md, docs/adr/0044-host-kernel-limits-persist-via-sysctl-d.md, docs/superpowers/README.md]
depends_on: [2]
requirements: [R6]
```

**Files:** as `files_touched`. None is read by the suite, so the gate is scoped; the orchestrator's `make test` after Task 2 covers behaviour.

- [ ] `CLAUDE.md:84` (`setup` entry): replace "never lowering a higher value" with "persisting the higher of the live value and 1024, never lowering a higher conf or live value; a drop-in that sorts before `90-` is overridden at boot".
- [ ] `CLAUDE.md` Test Seams `_SYSCTL_*` bullet (~line 656): add a sub-bullet "When `_SYSCTL_BIN` is set the step runs it without sudo; unset, it runs `sudo sysctl -w`."
- [ ] ADR-0044 `## Consequences`: add a dated (2026-10-08) note: the step now persists `max(live, 1024)`; a drop-in that sorts before `90-` with a higher value is still overridden at boot and cannot be detected from the live value; renaming was declined.
- [ ] `docs/superpowers/README.md`: delete Backlog rows 180-183; add a row `| \`_SYSCTL_CONF\` seam writes an env-chosen path as root | \`sudo tee "${_conf}"\` in \`_install_ubuntu_inotify\` honours the seam under sudo, the same shape \`_SYSCTL_BIN\` had (inotify-followups spec N4) |`.
- [ ] Commit.

### Task 4: Refuse confs with other keys (Phase 3 bug-scan fix)

```yaml-task
id: 4
description: R7 (amendment) - step returns 1 and doctor FAILs "other keys; fix by hand" when the conf assigns any key besides max_user_instances; pin the sudo apply arm to the conf value
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: 'bats tests/setup_env/linux_ubuntu.bats tests/setup_env/unit.bats < /dev/null'
    exit_code: 0
  - cmd: 'grep -q "other keys; fix by hand" lib/helpers.sh'
    exit_code: 0
  - cmd: 'make lint < /dev/null'
    exit_code: 0
max_retries: 3
files_touched: [lib/helpers.sh, lib/linux_ubuntu.sh, tests/setup_env/linux_ubuntu.bats, tests/setup_env/unit.bats]
depends_on: [3]
requirements: [R7]
```

Added in Phase 3 after the bug-scan HOLD: a whole-file `tee` deleted any other key in the conf, newly reachable for a valid conf below live. Also fixes the test-quality HOLD (sudo apply arm `${_val}` unpinned).

---

## Orchestrator steps

- [ ] After Task 2: `make test < /dev/null > <scratch>/test.log 2>&1; echo rc=$?`, then grep `not ok`. rc must be 0.
- [ ] After Task 3: proceed to `finishing-a-development-branch`.

## Non-goal check

Fresh reviewer, 2026-10-08, against N1-N6 from `spec_contract.py`: all CLEAR, 0 CONFLICT, 0 UNCLEAR. Nearest case, N1: the parser reset routes more confs to "fix by hand", but the path and its messages are unchanged and both tasks keep conf classification as is. No plan revision, no amendment.
