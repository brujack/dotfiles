# perf_event_paranoid ceiling Implementation Plan

> **Status: DONE** — merged as dotfiles#486 (7efe913f), 2026-11-25.

spec: docs/superpowers/specs/2026-11-25-perf-event-paranoid-ceiling-design.md

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist and apply `kernel.perf_event_paranoid = 2` on Ubuntu devtools hosts, never loosening a lower value, with a doctor check.

**Architecture:** A new `_sysctl_ceiling_step` sits beside `_sysctl_floor_step` in `lib/linux_ubuntu.sh` and reuses the existing conf classifiers and `_sysctl_conf_write`. `_install_ubuntu_perf` gates on `HAS_DEVTOOLS`, systemd and the proc file and joins `install_ubuntu_packages`' step loop after `kernel_keys`. A new `_doctor_sysctl_ceiling` plus `_doctor_check_perf_paranoid` sit beside the floor doctor in `lib/helpers.sh`.

**Tech Stack:** bash, bats, shellcheck.

## Global Constraints

- Value is exactly 2, read from `PERF_EVENT_PARANOID_MAX`; no literal `2` in `_install_ubuntu_perf` or `_doctor_check_perf_paranoid`.
- `_sysctl_floor_step`, `_doctor_sysctl_floor`, `_sysctl_read_live`, `_sysctl_conf_value` bodies are byte-unchanged (R13). Gated as: no existing line in `lib/helpers.sh` is removed, and in `lib/linux_ubuntu.sh` only the step-loop line is (the diff's `^-` count).
- Never `sysctl -p`; never write any conf but the perf conf; never write or apply a value other than 2; never rewrite a conf holding 0..2 (N2, N3).
- No package, Brewfile or apt list change (N1).
- `CLAUDE.md` stays at or below 85000 bytes (currently 84997).
- No test reaches the real `/etc/sysctl.d`, `/proc` or `sysctl`: seams `_PERF_CONF`, `_PERF_PROC`, `_SYSCTL_BIN`, `_SYSTEMD_RUN_DIR` under `BATS_TEST_TMPDIR`.
- Never name `lib/workflows.sh` in a Bash command (privacy hook); use the Read tool if needed.

## Verification Planning

- Suite: orchestrator runs `make test < /dev/null` once after Task 3 (the full suite runs ~10 min, over the 600 s Bash cap for a subagent, so task gates are scoped). Expect exit 0.
- V1 (both boxes, after Task 2, from the implementation worktree): `sudo -n` is passwordless on `claude` and `workstation` (measured 2026-11-25). Run
  `bash -c 'cd <wt> && source lib/constants.sh && source lib/helpers.sh && source lib/linux_ubuntu.sh && HAS_DEVTOOLS=1 _install_ubuntu_perf'`
  then `perf stat -x, -e cycles,instructions true 2>&1 >/dev/null`; expect a count above 0 on both event lines and no `<not supported>`/`<not counted>`. If sourcing fails, find the minimal source set with `bash -n` and record it. Operator "yes" before the first sudo run on each box.
- V2: `sudo sysctl -w kernel.perf_event_paranoid=4 && sudo /usr/lib/systemd/systemd-sysctl /etc/sysctl.d/90-dotfiles-perf.conf && cat /proc/sys/kernel/perf_event_paranoid` prints `2`; `/usr/lib/systemd/systemd-sysctl --cat-config | grep -n perf_event` shows only `90-dotfiles-perf.conf`.
- V3: `bash -c 'cd <wt> && ./setup_env.sh -t doctor' </dev/null` output contains `perf perf_event_paranoid 2`.
- Edge cases covered by bats: every step-table and doctor-table row of the spec, `-1` live and conf, proc absent, both skips.

---

### Task 1: Ceiling step, constants, seams and step tests

```yaml-task
id: 1
description: Add PERF constants, _sysctl_ceiling_step, _install_ubuntu_perf in the step loop, load_mocks seams, and their bats tests
role: executor
model: sonnet
tdd: required
requirements: [R1, R2, R3, R4, R5, R6, R7, R8, R9, R12, R13]
acceptance:
  - cmd: make lint
    exit_code: 0
  - cmd: bats --jobs 12 -f 'perf' tests/setup_env/linux_ubuntu.bats
    exit_code: 0
    stdout_match: 'ok [0-9]+ perf: absent conf at live 4 writes 2 and applies 2'
  - cmd: bats --jobs 12 tests/setup_env/linux_ubuntu.bats tests/setup_env/workflows.bats
    exit_code: 0
  - cmd: '[ "$(git diff "$(git merge-base origin/master HEAD)" -- lib/linux_ubuntu.sh lib/helpers.sh | grep -cE "^-[^-]")" -le 1 ]'
    exit_code: 0
max_retries: 3
files_touched: [lib/constants.sh, lib/linux_ubuntu.sh, tests/helpers/common.bash, tests/setup_env/linux_ubuntu.bats, tests/setup_env/workflows.bats]
depends_on: []
```

**Files:** as `files_touched`.

1. `lib/constants.sh`, after `KEYS_MAXBYTES_PROC`, with a comment naming the spec and the readers (`_install_ubuntu_perf`, `_doctor_check_perf_paranoid`):
   `readonly PERF_EVENT_PARANOID_MAX=2`, `readonly PERF_SYSCTL_CONF=/etc/sysctl.d/90-dotfiles-perf.conf`, `readonly PERF_EVENT_PARANOID_PROC=/proc/sys/kernel/perf_event_paranoid`.
2. `tests/helpers/common.bash` `load_mocks`, beside the kernel-keys seams: export `_PERF_CONF="${BATS_TEST_TMPDIR}/sysctl.d/90-dotfiles-perf.conf"`, `_PERF_PROC="${BATS_TEST_TMPDIR}/perf_event_paranoid"`, seed `printf '2\n' > "${_PERF_PROC}"`.
3. `lib/linux_ubuntu.sh`: add `perf` to the step loop directly after `kernel_keys`. Add after `_install_ubuntu_kernel_keys`:

```bash
# Ubuntu's kernel default perf_event_paranoid (4) blocks unprivileged perf stat.
# Persist and apply exactly PERF_EVENT_PARANOID_MAX, never loosening a lower value.
# Spec: docs/superpowers/specs/2026-11-25-perf-event-paranoid-ceiling-design.md
_install_ubuntu_perf() {
  local _rundir="${_SYSTEMD_RUN_DIR:-${SYSTEMD_RUN_DIR}}"
  local _conf="${_PERF_CONF:-${PERF_SYSCTL_CONF}}" _proc="${_PERF_PROC:-${PERF_EVENT_PARANOID_PROC}}"
  if [[ -z ${HAS_DEVTOOLS} ]]; then printf 'perf: skipped (HAS_DEVTOOLS unset)\n'; return 0; fi
  if [[ ! -d ${_rundir} ]]; then printf 'perf: skipped (no systemd at %s)\n' "${_rundir}"; return 0; fi
  if [[ ! -e ${_proc} ]]; then printf 'perf: skipped (no %s)\n' "${_proc}"; return 0; fi
  _sysctl_ceiling_step perf kernel.perf_event_paranoid "${PERF_EVENT_PARANOID_MAX}" "${_conf}" "${_proc}" "${_PERF_CONF:+_PERF_CONF}"
}
```

Add `_sysctl_ceiling_step <label> <key> <ceiling> <conf> <proc> <seam_name>` after `_sysctl_floor_step`, with a header comment: why a fixed value, not `min(live, ceiling)`; that the conf-refusal block is a deliberate copy (spec, F1.2). Body: copy the floor step's existing-conf classification block verbatim (same four messages, rc 1). Then: live via `_sysctl_read_live`; on failure print `%s: live value in %s unreadable or below 0; fix by hand` to stderr, rc 1. If conf absent or `_val > _ceiling`: `_sysctl_conf_write … "${_ceiling}" …`, read back (`%s: cannot read back %s` / `%s: read-back mismatch (%s)`, rc 1), print `%s: conf written (%s)` (new) or `%s: persisted %s to %s (was %s)` (rewrite). If `_live <= _ceiling`: print `%s: already %s or lower` unless written, rc 0. Else `-w "${_key}=${_ceiling}"` through `_SYSCTL_BIN` (no sudo) or `sudo sysctl`, messages `%s: apply failed (_SYSCTL_BIN set, ran without sudo)` / `%s: apply failed`, success `%s: applied`. 4. Tests in `tests/setup_env/linux_ubuntu.bats`, new section `# ── _install_ubuntu_perf ──`, names starting `perf:`. Each sets `export HAS_DEVTOOLS=1` (or unsets for the skip) and writes `_PERF_PROC`/`_PERF_CONF` itself. One test per spec step-table row, asserting conf bytes (`[ "$(cat "${_PERF_CONF}")" = 'kernel.perf_event_paranoid = 2' ]` or byte-identical via `cmp` to a saved copy), the message, and `grep -c 'sysctl -w kernel.perf_event_paranoid=2' "${MOCK_CALLS_FILE}"` = 1 or the stub never called. First row's name: `perf: absent conf at live 4 writes 2 and applies 2`. Plus: both skips and proc-absent skip (no conf created); conf unreadable / non-text / other keys / `-1` refused, byte-identical, rc 1; live `-1` rc 1 with the message; `MOCK_SYSCTL_STUB_EXIT=1` gives the `_SYSCTL_BIN set` apply-failure message; one test with `_SYSCTL_BIN` unset (keep `_PERF_CONF` set, so the conf write stays a plain `tee` into the fixture) behind a recording `sudo` shim in `${SHIM_DIR}` that runs nothing, asserting the call log is exactly `sudo sysctl -w kernel.perf_event_paranoid=2` (shim pattern: test `inotify_conf_write: seam unset pipes to sudo tee on the constant path`, ~line 5902). Never unset `_PERF_CONF` in a test: the step would then read the real `/etc` path. 5. Step-list tests: add `perf` after `kernel_keys` in the five loops in `linux_ubuntu.bats` (lines ~343, 359, 372, 2819, 5522) and bump the two `-eq 15` counts to `-eq 16`; in `workflows.bats` add `_install_ubuntu_perf() { :; }` to `_stub_ubuntu_steps` and `perf` after `kernel_keys` in the failing-step loop (~942).

**Interfaces:** Produces `PERF_EVENT_PARANOID_MAX`, `PERF_SYSCTL_CONF`, `PERF_EVENT_PARANOID_PROC`, `_PERF_CONF`/`_PERF_PROC` seams, `_install_ubuntu_perf`.

### Task 2: Doctor check and its tests

```yaml-task
id: 2
description: Add _doctor_sysctl_ceiling and _doctor_check_perf_paranoid to run_doctor, stub it in end-to-end doctor tests, and test every doctor row
role: executor
model: sonnet
tdd: required
requirements: [R1, R2, R10, R11, R13]
acceptance:
  - cmd: make lint
    exit_code: 0
  - cmd: bats --jobs 12 -f 'perf' tests/setup_env/unit.bats
    exit_code: 0
    stdout_match: 'ok [0-9]+ perf doctor: conf -1 fails unparseable with no tee remedy'
  - cmd: bats --jobs 12 tests/setup_env/unit.bats tests/setup_env/plugin_node_paths.bats
    exit_code: 0
  - cmd: '[ "$(git diff "$(git merge-base origin/master HEAD)" -- lib/helpers.sh | grep -cE "^-[^-]")" -eq 0 ]'
    exit_code: 0
max_retries: 3
files_touched: [lib/helpers.sh, tests/setup_env/unit.bats, tests/setup_env/plugin_node_paths.bats]
depends_on: [1]
```

**Files:** as `files_touched`.

1. `lib/helpers.sh`: `_doctor_check_perf_paranoid` after `_doctor_check_kernel_keys`: resolve conf/proc/rundir as `_install_ubuntu_perf` does; `[[ -n ${LINUX} && -n ${HAS_DEVTOOLS} && -d ${_rundir} && -e ${_proc} ]] || return 0`; `printf "\nperf events:\n"`; `_doctor_sysctl_ceiling perf kernel.perf_event_paranoid "${PERF_EVENT_PARANOID_MAX}" "${_conf}" "${_proc}"`. Add the call to `run_doctor` after `_doctor_check_kernel_keys`.
2. `_doctor_sysctl_ceiling <label> <key> <ceiling> <conf> <proc>` after `_doctor_sysctl_floor`; first match wins, every FAIL/WARN `return 0`:
   live unreadable → `doctor_fail "${_label}" "live value in ${_proc} unreadable or below 0"`; the four conf refusals with `_doctor_sysctl_floor`'s exact texts, no remedy; conf missing → FAIL `${_conf} missing; next boot: kernel default; fix:`; conf > ceiling → FAIL `${_conf} value ${_val} above ${_ceiling}; next boot: ${_val}; fix:`; both print `    printf '<key> = <ceiling>\n' | sudo tee '<conf>'` plus ` && sudo sysctl -w <key>=<ceiling>` when live > ceiling; live > ceiling → FAIL `live value ${_live} above ${_ceiling}; fix:` + `    sudo sysctl -w <key>=<ceiling>`; conf < ceiling → WARN `${_conf} value ${_val} below ${_ceiling}; set outside dotfiles`, no remedy; live < ceiling → WARN `live value ${_live} below ${_ceiling}; next boot: ${_val}; fix:` + `    sudo sysctl -w <key>=<ceiling>`; else `doctor_pass "${_label} ${_key##*.} ${_live}"`.
3. Stubs: `_doctor_check_perf_paranoid() { :; }` beside each `_doctor_check_kernel_keys() { :; }` (unit.bats ~1037, ~1451, ~2576; plugin_node_paths.bats ~430). Extend the "kernel keys doctor: stub count" test with a perf count equal to the inotify count.
4. Tests in unit.bats, section `# ── _doctor_check_perf_paranoid ──`, names starting `perf doctor:`; each exports `LINUX=1 HAS_DEVTOOLS=1` and `mkdir -p "${_SYSTEMD_RUN_DIR}"`. One per doctor row: conf unreadable (chmod 000, skip as root), non-text, other keys, `perf doctor: conf -1 fails unparseable with no tee remedy` (assert `[[ "$output" != *"sudo tee"* ]]`), missing at live 4 (tee + `&& sudo sysctl -w`), missing at live 2 (tee, no `sysctl -w`), conf 3, live 4 conf 2, conf 1 live 1 (WARN text contains `value 1 below 2`, no tee), live 1 conf 2 (WARN `live value 1 below 2; next boot: 2`), live `-1` FAIL, PASS at live 2 conf 2 (`perf perf_event_paranoid 2`); each gate skip (LINUX, HAS_DEVTOOLS, rundir, proc absent) prints nothing. A wiring test: `declare -f _install_ubuntu_perf` and `declare -f _doctor_check_perf_paranoid` each contain `PERF_EVENT_PARANOID_MAX` and `${_PERF_CONF:-${PERF_SYSCTL_CONF}}` and `${_PERF_PROC:-${PERF_EVENT_PARANOID_PROC}}`, and neither has a line matching `perf_event_paranoid" *2|paranoid 2 `. A constants test: `PERF_EVENT_PARANOID_PROC` = `/proc/sys/${key//.//}` and `PERF_EVENT_PARANOID_MAX` = 2.

**Interfaces:** Consumes Task 1's constants and seams. Produces `_doctor_check_perf_paranoid`.

### Task 3: CLAUDE.md, Backlog and plan index

```yaml-task
id: 3
description: Docs-only (tdd not-applicable) — reword CLAUDE.md sysctl lines in place for perf, add the classifier-extraction Backlog row and the plan index row
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: '[ "$(wc -c < CLAUDE.md)" -le 85000 ]'
    exit_code: 0
  - cmd: 'grep -q "perf_event_paranoid" CLAUDE.md && grep -q "_PERF_CONF" CLAUDE.md && grep -q "_PERF_PROC" CLAUDE.md'
    exit_code: 0
  - cmd: 'grep -q "plans/2026-11-25-perf-event-paranoid-ceiling.md" docs/superpowers/README.md && grep -q "_sysctl_conf_classify" docs/superpowers/README.md'
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched: [CLAUDE.md, docs/superpowers/README.md]
depends_on: [2]
```

1. `CLAUDE.md` Entry Points: reword the `setup`/`developer` sysctl bullet so it also says `perf_event_paranoid` is held at exactly 2 on devtools hosts, never loosened. Testing seams bullet: add `_PERF_CONF`, `_PERF_PROC` to the sysctl seam list. Net bytes must not exceed 85000; tighten the same bullets' wording to pay for it, keeping every `→` pointer and every rule intact. Run `wc -c CLAUDE.md` and record before/after in the commit body.
2. `docs/superpowers/README.md`: All Plans row `| 2026-11-25 | [perf_event_paranoid ceiling](plans/2026-11-25-perf-event-paranoid-ceiling.md) | [perf_event_paranoid ceiling on the Linux development boxes](specs/2026-11-25-perf-event-paranoid-ceiling-design.md) | In progress |` at the top of the table. P3 tech-debt Backlog row: `| Extract one shared sysctl conf classifier (_sysctl_conf_classify) | The unreadable/non-text/other-keys/unparseable block is copied in _sysctl_floor_step, _doctor_sysctl_floor, _sysctl_ceiling_step and _doctor_sysctl_ceiling (spec specs/2026-11-25-perf-event-paranoid-ceiling-design.md, external review F1.2). One helper keeps step and doctor agreeing on which confs they touch. |`

Orchestrator, after Task 3: run `make test < /dev/null`; run V1–V3; message ai-config to add `_PERF_CONF`/`_PERF_PROC` to `dotfiles-test-seams.md` § `CLAUDE.md relocation: sysctl and kernel keys seams` before Phase 3.

## Non-goal check

Reviewer verdicts (2026-11-25): N1 CLEAR, N3 CLEAR, N2 UNCLEAR.

- N2 UNCLEAR. Quote: "Verification Planning, V2 (line 29): `sudo sysctl -w kernel.perf_event_paranoid=4 && sudo /usr/lib/systemd/systemd-sysctl /etc/sysctl.d/90-dotfiles-perf.conf && cat /proc/sys/kernel/perf_event_paranoid` prints `2`". Resolution: spec amendment scoping N2 to the shipped code; V2's transient 4 is restored to 2 within the same command. Plan text unchanged.

