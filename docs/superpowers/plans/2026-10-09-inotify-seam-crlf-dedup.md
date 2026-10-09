# inotify seam, non-text confs, live-value dedup Implementation Plan

> **Status: DONE** (PR #325, merged 2026-10-09)

spec: docs/superpowers/specs/2026-10-09-inotify-seam-crlf-dedup-design.md

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close Backlog rows 181-183: write the `_SYSCTL_CONF` seam without sudo, refuse non-text confs (CR, NUL, non-ASCII), and read the live value through one helper with one cap constant.

**Architecture:** New `INOTIFY_INT_MAX` in `lib/constants.sh`; new `_inotify_read_live` and `_inotify_conf_has_nontext` in `lib/helpers.sh`; new `_inotify_conf_write` in `lib/linux_ubuntu.sh`. `_install_ubuntu_inotify` and `_doctor_check_inotify_limits` call them. The spec's Decision sections 1-3 are the authority for names, messages and order.

**Tech Stack:** bash, awk, tr, bats.

## Global Constraints

- Every test runs under `load_mocks`' seams (`_SYSCTL_CONF`, `_INOTIFY_PROC`, `_SYSCTL_BIN`, `_SYSTEMD_RUN_DIR`). No test reaches `/etc/sysctl.d`, `/proc/sys`, `/usr/sbin/sysctl` or real sudo.
- No test runs `_install_ubuntu_inotify` with `_SYSCTL_CONF` unset (spec N1). `_inotify_conf_write` is called with it unset only after a recording `sudo` shim in `${SHIM_DIR}` is shown to resolve first (`command -v sudo`).
- `tests/mocks/tee` swallows real write errors; drive a write failure with `MOCK_TEE_EXIT=1`.
- Every assertion of an absence is paired with a positive assertion; every accepted reader input asserts the exact printed value.
- Non-goals (spec N1-N4): awk parsers not taught any line ending; no change to written/applied values, doctor remedy text or `_SYSCTL_BIN` handling; no `_inotify_conf_state` helper.
- bash checks shape (`^(0|[1-9][0-9]{0,9})$`) before arithmetic; awk compares `line + 0 <= max`.
- Commit messages via `caveman:caveman-commit`; stage exact paths.
- `make test` is run by the orchestrator once after Task 3, not by any task.

## Verification

- Session gate: `make test < /dev/null` exits 0 in the feature worktree after Task 3.
- Mutation controls (spec Testing), each applied by the implementing task, confirmed red, then reverted; the task report lists each with the failing test name.
- Post-merge V2 on `claude`: `./setup_env.sh -t doctor` passes the inotify check; `-t developer` prints `inotify: already 1024 or higher`; `sha256sum /etc/sysctl.d/90-dotfiles-inotify.conf` unchanged.

---

### Task 1: Cap constant and one live-value reader

```yaml-task
id: 1
description: Add INOTIFY_INT_MAX and _inotify_read_live, route the step, doctor and the awk cap through them, with a fixed-value boundary table
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: 'bats tests/setup_env/linux_ubuntu.bats tests/setup_env/unit.bats < /dev/null'
    exit_code: 0
  - cmd: '! grep -nE "^[^#]*2147483647" lib/helpers.sh lib/linux_ubuntu.sh'
    exit_code: 0
  - cmd: 'grep -q "^readonly INOTIFY_INT_MAX=2147483647$" lib/constants.sh'
    exit_code: 0
  - cmd: 'make lint < /dev/null'
    exit_code: 0
max_retries: 3
files_touched: [lib/constants.sh, lib/helpers.sh, lib/linux_ubuntu.sh, tests/setup_env/unit.bats, tests/setup_env/linux_ubuntu.bats]
depends_on: []
requirements: [R3, R4, R5]
```

**Spec:** Decision 3; Testing "Reader boundary table".

- [ ] `readonly INOTIFY_INT_MAX=2147483647` beside `INOTIFY_MAX_USER_INSTANCES` in `lib/constants.sh`.
- [ ] Tests in `unit.bats` for `_inotify_read_live`: `0`→`0`, `1024`→`1024`, `" 1024\n"`→`1024`, `2147483647`→`2147483647`, each rc 0; unreadable path, empty, `08`, `2147483648`, `12345678901`, `12345678901234567890`, `abc` each rc 1 with empty output. Run red.
- [ ] Implement in `lib/helpers.sh`: `[[ -r $1 ]] || return 1`; `_v="$(<"$1")"`; `_v="${_v//[[:space:]]/}"`; shape regex, then `((_v > INOTIFY_INT_MAX))` → 1; else `printf '%s\n' "${_v}"`.
- [ ] Replace the inline reads at `lib/helpers.sh` (doctor, `cat`) and `lib/linux_ubuntu.sh` (step, `$(<)`) with `_live="$(_inotify_read_live "${_proc}")" || { <existing message>; ...; }`. Messages unchanged.
- [ ] `_inotify_conf_value`: `awk -v max="${INOTIFY_INT_MAX}"`, cap `line + 0 <= max`. Update its comment.
- [ ] One step test and one doctor test with live ` 1024\n` (accepted) and one each with live `08` (rejected, existing message).
- [ ] Mutations: regex accepts `08`; reader always returns 1; awk cap replaced by `9999`. Each red, then reverted.

**Interfaces:** Produces `_inotify_read_live <proc>` (stdout value, rc 0/1) and `INOTIFY_INT_MAX`.

---

### Task 2: Conf write helper, no sudo under the seam

```yaml-task
id: 2
description: Add _inotify_conf_write so the step writes via tee when _SYSCTL_CONF is set and sudo tee on the constant path otherwise, tested directly with a recording sudo shim
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: 'bats tests/setup_env/linux_ubuntu.bats < /dev/null'
    exit_code: 0
  - cmd: 'grep -qF "sudo tee \"\${INOTIFY_SYSCTL_CONF}\"" lib/linux_ubuntu.sh'
    exit_code: 0
  - cmd: 'make lint < /dev/null'
    exit_code: 0
max_retries: 3
files_touched: [lib/linux_ubuntu.sh, tests/setup_env/linux_ubuntu.bats]
depends_on: [1]
requirements: [R1]
```

**Spec:** Decision 1; Testing "Write helper" and "Write failure" bullets.

- [ ] Tests:
  - seam set: `run _inotify_conf_write 4096`; rc 0; conf content exactly `fs.inotify.max_user_instances = 4096`; `MOCK_CALLS_FILE` has a `tee ` line and no `sudo ` line.
  - seam unset: write `${SHIM_DIR}/sudo` (`printf 'sudo %s\n' "$*" >> "${MOCK_CALLS_FILE}"; cat > /dev/null; exit 0`), chmod +x; `unset _SYSCTL_CONF`; assert `[ "$(command -v sudo)" = "${SHIM_DIR}/sudo" ]`; run helper; rc 0; recorded line exactly `sudo tee /etc/sysctl.d/90-dotfiles-inotify.conf`.
  - failure: `MOCK_TEE_EXIT=1`, seam set; rc 1; stderr contains `_SYSCTL_CONF`.
    Run red.
- [ ] Implement `_inotify_conf_write <target>` in `lib/linux_ubuntu.sh` above the step: non-empty `_SYSCTL_CONF` → `printf ... | tee "${_SYSCTL_CONF}" > /dev/null || { printf 'inotify: write failed (%s; _SYSCTL_CONF set, ran without sudo)\n' ... >&2; return 1; }`; else `... | sudo tee "${INOTIFY_SYSCTL_CONF}" > /dev/null || { printf 'inotify: write failed (%s)\n' ... >&2; return 1; }`.
- [ ] `_install_ubuntu_inotify` calls `_inotify_conf_write "${_target}" || return 1` in place of its inline write. Update its header comment (seams never run as root).
- [ ] Mutations: `sudo` restored on the seam branch; unset branch writes `${_conf}`. Each red, then reverted.

**Interfaces:** Consumes nothing new. Produces `_inotify_conf_write <target>` (rc 0/1).

---

### Task 3: Refuse non-text confs

```yaml-task
id: 3
description: Add _inotify_conf_has_nontext and make the step and doctor refuse a conf with any byte outside 0x20-0x7E, tab or newline, before the other-keys check
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: 'bats tests/setup_env/linux_ubuntu.bats tests/setup_env/unit.bats < /dev/null'
    exit_code: 0
  - cmd: 'make lint < /dev/null'
    exit_code: 0
max_retries: 3
files_touched: [lib/helpers.sh, lib/linux_ubuntu.sh, tests/setup_env/unit.bats, tests/setup_env/linux_ubuntu.bats]
depends_on: [2]
requirements: [R2]
```

**Spec:** Decision 2; Testing "Non-text refusal".

- [ ] Fixtures via `printf`: `'fs.inotify.max_user_instances = 1024\r\n'`; `'\r'`; `'# c\0other.key = 5\nfs.inotify.max_user_instances = 512\n'`; `'# caf\303\251\nfs.inotify.max_user_instances = 512\n'`. Controls: `'fs.inotify.max_user_instances = 512\n'` and `'fs.inotify.max_user_instances\t=\t512\n'`.
- [ ] Step tests (live 1024): each fixture rc 1, stderr contains `non-text bytes` and `fix by hand`, conf `cmp`-identical to a saved copy, no `tee ` line recorded. Controls: rewritten to 1024.
- [ ] Doctor tests: each fixture FAILs with `non-text bytes`; the tab control passes or reaches its normal verdict (not non-text).
- [ ] Run red. Implement in `lib/helpers.sh`: `_inotify_conf_has_nontext() { local _n; _n="$(LC_ALL=C tr -d '[:print:]\t\n' < "$1" | wc -c)"; ((_n > 0)); }` with a why-comment (command substitution drops NUL; awks differ on NUL; systemd splits on CR and NUL).
- [ ] Call it in both callers after the readability check, before `_inotify_conf_has_other_keys`: step prints `inotify: <conf> holds non-text bytes (CR, NUL or non-ASCII); fix by hand` to stderr, rc 1; doctor `doctor_fail "inotify" "<conf> holds non-text bytes (CR, NUL or non-ASCII); fix by hand"`, return 0.
- [ ] Mutations: check removed from the step; removed from doctor; `tr` keep-set gains `\r`. Each red, then reverted.

**Interfaces:** Produces `_inotify_conf_has_nontext <conf>` (rc 0 = non-text present).

---

### Task 4: Docs, ADR note, backlog

```yaml-task
id: 4
description: Document the seam and non-text refusal in CLAUDE.md and ADR-0044, delete Backlog rows 181-183 (docs-only, no behaviour change, so TDD does not apply)
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: 'grep -q "_SYSCTL_CONF.*without sudo" CLAUDE.md'
    exit_code: 0
  - cmd: 'grep -q "non-text" CLAUDE.md'
    exit_code: 0
  - cmd: 'grep -qE "^- 2026-10-09.*non-text" docs/adr/0044-host-kernel-limits-persist-via-sysctl-d.md'
    exit_code: 0
  - cmd: '! grep -qE "seam writes an env-chosen path as root|live-value check copied three times|conf parsers reject CRLF" docs/superpowers/README.md'
    exit_code: 0
  - cmd: 'make lint < /dev/null'
    exit_code: 0
max_retries: 2
files_touched: [CLAUDE.md, docs/adr/0044-host-kernel-limits-persist-via-sysctl-d.md, docs/superpowers/README.md]
depends_on: [3]
requirements: [R6]
```

**Spec:** R6.

- [ ] CLAUDE.md Test Seams `_SYSCTL_CONF`/... bullet: replace the line "When `_SYSCTL_BIN` is set the step runs it without sudo; unset, it runs `sudo sysctl -w`." with: when `_SYSCTL_BIN` or `_SYSCTL_CONF` is set the step uses it without sudo; unset, it runs `sudo sysctl -w` and `sudo tee` on the real conf; the write lives in `_inotify_conf_write`, tested directly so no test reads the real conf. Add to the "fix by hand" sentence that a conf holding non-text bytes (CR, NUL, non-ASCII) is refused too.
- [ ] ADR-0044 Consequences: one dated line `- 2026-10-09: the step and doctor refuse a conf holding non-text bytes (CR, NUL, non-ASCII), since systemd splits lines on CR and NUL where awk does not; CRLF confs are refused, not parsed. The `_SYSCTL_CONF` seam is written without sudo.`
- [ ] Delete README Backlog rows 181-183 (match by text, not line number).

## Non-goal check

Reviewer verdicts (fresh subagent, `nongoal-check.md`): N1 CLEAR, N2 CLEAR, N3 CLEAR, N4 CLEAR. No resolution needed.

- N1: the only unset-seam call is Task 2's direct `_inotify_conf_write` test, behind a recording, stdin-draining `${SHIM_DIR}/sudo` shim asserted with `command -v sudo`; no test runs the step unset.
- N3: Task 1 changes which live values are accepted, not what is written or applied; Task 3 adds a new doctor message and leaves the remedy text and `_SYSCTL_BIN` handling unchanged.
