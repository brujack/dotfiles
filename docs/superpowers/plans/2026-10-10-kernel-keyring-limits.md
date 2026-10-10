# Kernel Keys Limits Implementation Plan

spec: docs/superpowers/specs/2026-10-10-kernel-keyring-limits-design.md

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist `kernel.keys.maxkeys >= 2000` and `kernel.keys.maxbytes >= 500000` on Ubuntu docker hosts, one key per `/etc/sysctl.d` file, by generalising the hardened inotify floor step.

**Architecture:** The inotify step, its doctor check and their helpers become key-parameterised `_sysctl_*` functions; `_install_ubuntu_inotify` and `_doctor_check_inotify_limits` become one-line callers. A new `_install_ubuntu_kernel_keys` step and `_doctor_check_kernel_keys` check call the same functions twice, once per key.

**Tech Stack:** bash 5, bats, awk, the existing `load_mocks` seams.

## Global Constraints

- Floors: `kernel.keys.maxkeys` 2000 -> `/etc/sysctl.d/90-dotfiles-keys-maxkeys.conf`; `kernel.keys.maxbytes` 500000 -> `/etc/sysctl.d/90-dotfiles-keys-maxbytes.conf`.
- One key per conf file. Never `sysctl -p` or `sysctl --system`.
- No change to any inotify message text, floor, file path, seam name (`_SYSCTL_CONF`, `_INOTIFY_PROC`, `_SYSCTL_BIN`, `_SYSTEMD_RUN_DIR` keep their names) or doctor verdict.
- No compatibility aliases for renamed `_inotify_*` helpers or `INOTIFY_INT_MAX`.
- Operator-facing strings say "kernel keys" / `kernel-keys`, never "keyring".
- Key matching in `_sysctl_conf_value` / `_sysctl_conf_has_other_keys` is exact string `==` on the dotted and slash spellings, never a regex built from the key.
- Base for differentials: `87aff846` (master when this plan was written).
- Measured before planning: `bats --jobs 24` on `tests/setup_env/linux_ubuntu.bats` 24 s (390 ok), `unit.bats` 11 s (281), `workflows.bats` 21 s (283), `plugin_node_paths.bats` 1 s (20). The `_doctor_check_inotify_limits() { :; }` stub sites number **5** (unit.bats 1027, 1048, 1458, 2782; plugin_node_paths.bats 266); the spec's prose figure of 10 came from a lens and is wrong.
- Every task runs in the feature worktree. The orchestrator runs `make test` once after Task 4.

## Verification

- Whole change: `make test` exits 0 in the worktree; CI green on the PR.
- Behaviour preservation: `bash <scratch>/inotify_diff.sh <base-archive> <worktree>` prints `DIVERGING: 0` (Task 1 gate). Proven before planning: 0 of 440 base-vs-base, 17 of 440 with two one-character message mutations.
- Live (post-merge, spec V1-V3): doctor FAILs on `claude`/`workstation`, the pasted remedies make it PASS, `/proc/sys/kernel/keys/*` read 2000/500000, and the `systemd-sysctl` restart proof holds.

The differential script lives at
`/tmp/claude-1000/-home-bruce-git-repos-personal-dotfiles/f1505336-02c5-4b82-ba0e-357e855352a3/scratchpad/inotify_diff.sh`
(written and verified by the orchestrator; not committed). Build the base tree once with
`git archive 87aff846 | tar -x -C <dir>`.

---

### Task 1: Extract the inotify step, doctor check and helpers into key-parameterised functions

```yaml-task
id: 1
description: Behaviour-preserving extraction of the inotify floor step, doctor check and helpers into _sysctl_* functions (tdd not-applicable - no behaviour change, gated by a 440-case differential and the unchanged inotify suite)
role: executor
model: sonnet
tdd: not-applicable
requirements: [R11]
acceptance:
  - cmd: 'D=$(mktemp -d) && git archive 87aff846 | tar -x -C "$D" && bash /tmp/claude-1000/-home-bruce-git-repos-personal-dotfiles/f1505336-02c5-4b82-ba0e-357e855352a3/scratchpad/inotify_diff.sh "$D" "$PWD" | tail -1'
    exit_code: 0
    stdout_match: '^DIVERGING: 0$'
  - cmd: 'bats --jobs 24 tests/setup_env/linux_ubuntu.bats tests/setup_env/unit.bats < /dev/null'
    exit_code: 0
  - cmd: '! git grep -nE "_inotify_(read_live|conf_value|conf_has_nontext|conf_has_other_keys|conf_write)\b|INOTIFY_INT_MAX" -- lib tests setup_env.sh'
    exit_code: 0
  - cmd: 'git diff 87aff846 -- tests | grep -E "^[-+][^-+]" | grep -vE "_sysctl_|SYSCTL_INT_MAX" | wc -l'
    exit_code: 0
    stdout_match: '^0$'
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched: [lib/helpers.sh, lib/linux_ubuntu.sh, lib/constants.sh, tests/setup_env/unit.bats, tests/setup_env/linux_ubuntu.bats]
depends_on: []
```

**Do:**

- `lib/constants.sh`: rename `INOTIFY_INT_MAX` -> `SYSCTL_INT_MAX` (comment: kernel INT_MAX, the largest value an `int` sysctl accepts).
- `lib/helpers.sh`: rename `_inotify_read_live` -> `_sysctl_read_live <path>`; `_inotify_conf_has_nontext` -> `_sysctl_conf_has_nontext <conf>`; `_inotify_conf_value <conf>` -> `_sysctl_conf_value <conf> <key>`; `_inotify_conf_has_other_keys <conf>` -> `_sysctl_conf_has_other_keys <conf> <key>`. In the two key-taking helpers pass `-v dot=<key> -v slash=<key with . -> />` to awk. In `_sysctl_conf_value` replace the `match(line, /^(fs\.inotify…)…=/)` regex with: if `line ~ /=/`, `k = line; sub(/[ \t]*=.*$/, "", k)`; act only when `k == dot || k == slash`. Keep every other line of both awk programs.
- `lib/helpers.sh`: move the body of `_doctor_check_inotify_limits` into `_doctor_sysctl_floor <label> <key> <floor> <conf> <proc>` (label is the doctor item name, e.g. `inotify`). `_doctor_check_inotify_limits` keeps its seam resolution, gate and `printf "\ninotify instances:\n"` header, then calls `_doctor_sysctl_floor inotify fs.inotify.max_user_instances "${INOTIFY_MAX_USER_INSTANCES}" "${_conf}" "${_proc}"`. Inside, every literal `fs.inotify.max_user_instances` becomes `${key}`, every `INOTIFY_MAX_USER_INSTANCES` becomes `${floor}`, and the PASS text `inotify max_user_instances ${_live}` must still print exactly that for inotify: build it as `"${label} ${key##*.} ${_live}"`.
- `lib/linux_ubuntu.sh`: `_inotify_conf_write` -> `_sysctl_conf_write <label> <key> <value> <conf> <seam_name>`: non-empty `<seam_name>` -> plain `tee <conf>` and message `<label>: write failed (<conf>; <seam_name> set, ran without sudo)`; empty -> `sudo tee <conf>` and `<label>: write failed (<conf>)`. Move the body of `_install_ubuntu_inotify` into `_sysctl_floor_step <label> <key> <floor> <conf> <proc> <seam_name>`, without the `HAS_DOCKER` and systemd gates. `_install_ubuntu_inotify` keeps the seam resolution and both gates, then calls `_sysctl_floor_step inotify fs.inotify.max_user_instances "${INOTIFY_MAX_USER_INSTANCES}" "${_conf}" "${_proc}" "${_SYSCTL_CONF:+_SYSCTL_CONF}"`.
- Each new generic function gets a header comment naming its positional arguments in order.
- Tests: change only calls to the renamed helpers and `INOTIFY_INT_MAX`. Change no assertion, no test name, no message string. The gate counts every other changed line in `tests/` and requires 0.

**Interfaces — Produces:** `_sysctl_read_live`, `_sysctl_conf_value`, `_sysctl_conf_has_nontext`, `_sysctl_conf_has_other_keys`, `_sysctl_conf_write`, `_sysctl_floor_step`, `_doctor_sysctl_floor`, `SYSCTL_INT_MAX`, with the signatures above.

- [ ] Rename and extract; [ ] run the differential; [ ] run both bats files; [ ] `make lint`; [ ] commit `refactor(inotify): extract sysctl floor helpers`.

---

### Task 2: Kernel-keys step, constants, seams, exact-key tests and step-list wiring

```yaml-task
id: 2
description: Add _install_ubuntu_kernel_keys (two keys, one conf each) with constants, load_mocks seams, exact-key near-miss tests and every hand-kept step list updated
role: executor
model: sonnet
tdd: required
requirements: [R1, R2, R3, R4, R5, R6, R7, R8, R9, R12, R14, R16]
acceptance:
  - cmd: 'bats --jobs 24 tests/setup_env/linux_ubuntu.bats tests/setup_env/workflows.bats tests/setup_env/unit.bats < /dev/null'
    exit_code: 0
  - cmd: 'grep -c "kernel_keys" tests/setup_env/linux_ubuntu.bats tests/setup_env/workflows.bats | awk -F: "\$2==0{z=1} END{exit z}"'
    exit_code: 0
  - cmd: 'grep -q "^_install_ubuntu_kernel_keys()" lib/linux_ubuntu.sh && ! awk "/^_install_ubuntu_kernel_keys\\(\\)/,/^}/" lib/linux_ubuntu.sh | grep -qi keyring'
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched: [lib/linux_ubuntu.sh, lib/constants.sh, tests/helpers/common.bash, tests/setup_env/linux_ubuntu.bats, tests/setup_env/workflows.bats, tests/setup_env/unit.bats]
depends_on: [1]
```

**Do (TDD, one behaviour at a time):**

- `lib/constants.sh` (readonly, comment pointing at the spec): `KEYS_MAXKEYS=2000`, `KEYS_MAXBYTES=500000`, `KEYS_MAXKEYS_CONF=/etc/sysctl.d/90-dotfiles-keys-maxkeys.conf`, `KEYS_MAXBYTES_CONF=/etc/sysctl.d/90-dotfiles-keys-maxbytes.conf`, `KEYS_MAXKEYS_PROC=/proc/sys/kernel/keys/maxkeys`, `KEYS_MAXBYTES_PROC=/proc/sys/kernel/keys/maxbytes`.
- `tests/helpers/common.bash` `load_mocks`, beside the inotify seams: export `_KEYS_MAXKEYS_CONF` / `_KEYS_MAXBYTES_CONF` under `${BATS_TEST_TMPDIR}/sysctl.d/` (absent), `_KEYS_MAXKEYS_PROC` / `_KEYS_MAXBYTES_PROC` under `BATS_TEST_TMPDIR` seeded `2000` / `500000`. Comment: seeded at the floor so no apply happens unless a test lowers it; an absent conf is still written.
- `lib/linux_ubuntu.sh` `_install_ubuntu_kernel_keys`: `HAS_DOCKER` unset -> print `kernel-keys: skipped (HAS_DOCKER unset)`, return 0; no systemd run dir -> `kernel-keys: skipped (no systemd at <dir>)`, return 0. Then call `_sysctl_floor_step "kernel-keys maxkeys" kernel.keys.maxkeys "${KEYS_MAXKEYS}" <conf> <proc> "${_KEYS_MAXKEYS_CONF:+_KEYS_MAXKEYS_CONF}"` and the same for maxbytes; run both; return 1 if either is non-zero.
- Step list: add `kernel_keys` immediately after `inotify` in `install_ubuntu_packages`.
- Test wiring: `workflows.bats` `_stub_ubuntu_steps` gains `_install_ubuntu_kernel_keys() { :; }`; its "runs every later step when any one step fails" loop gains `kernel_keys`. In `linux_ubuntu.bats`, the four tests whose step loops list `inotify … misc` gain `kernel_keys` after `inotify`, and every `grep -c '^ran ' … -eq 13` becomes `-eq 14`.
- Tests in `linux_ubuntu.bats`, each with a positive control (spec Testing section): per key below floor (conf `<key> = <floor>`, one `-w <key>=<floor>` call); at floor with no conf (conf holds the floor, stub exists and executable, zero calls); above floor (conf holds live, zero calls); higher existing conf kept (unchanged bytes, "already" line printed); one key's conf holding another key refused while the other key's conf is written, rc 1; both skip lines; a swap test (only maxbytes below: `_KEYS_MAXBYTES_CONF` holds `kernel.keys.maxbytes = 500000`, `_KEYS_MAXKEYS_CONF` is the at-floor write); no call ever contains `-p` or `--system`.
- Tests in `unit.bats` (R14): `_sysctl_conf_value` called directly on a conf holding only a near-miss line (one `.` replaced by `X`) prints nothing, for each of `fs.inotify.max_user_instances`, `kernel.keys.maxkeys`, `kernel.keys.maxbytes`; and prints the value for the exact dotted and slash spellings.

**Interfaces — Consumes:** Task 1's `_sysctl_floor_step`, `_sysctl_conf_value`. **Produces:** `_install_ubuntu_kernel_keys`, the six `KEYS_*` constants, the four `_KEYS_*` seams.

- [ ] RED/GREEN per behaviour; [ ] gates; [ ] commit `feat(linux): persist kernel keys floors`.

---

### Task 3: Kernel-keys doctor check, run_doctor wiring and stub sites

```yaml-task
id: 3
description: Add _doctor_check_kernel_keys (header "kernel keys:"), call it from run_doctor after the inotify check, and stub it at every run_doctor test site with a count-equality test
role: executor
model: sonnet
tdd: required
requirements: [R10, R15, R17]
acceptance:
  - cmd: 'bats --jobs 24 tests/setup_env/unit.bats tests/setup_env/plugin_node_paths.bats < /dev/null'
    exit_code: 0
  - cmd: 'test "$(git grep -c "_doctor_check_inotify_limits() { :; }" -- tests | awk -F: "{s+=\$2} END{print s}")" = "$(git grep -c "_doctor_check_kernel_keys() { :; }" -- tests | awk -F: "{s+=\$2} END{print s}")"'
    exit_code: 0
  - cmd: 'grep -q "^_doctor_check_kernel_keys()" lib/helpers.sh && ! awk "/^_doctor_check_kernel_keys\\(\\)/,/^}/" lib/helpers.sh | grep -qi keyring'
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched: [lib/helpers.sh, tests/setup_env/unit.bats, tests/setup_env/plugin_node_paths.bats]
depends_on: [2]
```

**Do:**

- `lib/helpers.sh` `_doctor_check_kernel_keys`: gate `[[ -n ${LINUX} && -n ${HAS_DOCKER} && -d ${_rundir} ]] || return 0` (seam `_SYSTEMD_RUN_DIR`), `printf "\nkernel keys:\n"`, then `_doctor_sysctl_floor kernel-keys kernel.keys.maxkeys "${KEYS_MAXKEYS}" "${_KEYS_MAXKEYS_CONF:-${KEYS_MAXKEYS_CONF}}" "${_KEYS_MAXKEYS_PROC:-${KEYS_MAXKEYS_PROC}}"` and the same for maxbytes. Call it in `run_doctor` on the line after `_doctor_check_inotify_limits`.
- Stub `_doctor_check_kernel_keys() { :; }` beside each of the 5 `_doctor_check_inotify_limits() { :; }` sites (unit.bats 1027, 1048, 1458, 2782; plugin_node_paths.bats 266).
- Add a test in `unit.bats` asserting the two stub counts over `tests/` are equal and non-zero (positive control).
- Doctor tests in `unit.bats` (with `LINUX=1 HAS_DOCKER=1` set explicitly): default seeding (no confs, live at floor) -> FAIL for each key naming its own conf, remedy line printed per key; both confs at floor and live at floor -> both PASS lines; maxbytes conf below floor -> FAIL naming `90-dotfiles-keys-maxbytes` (via seam path) only; a conf holding the other kernel-keys key -> "holds other keys; fix by hand"; gate off (`HAS_DOCKER` unset) -> no output.

**Interfaces — Consumes:** Task 1's `_doctor_sysctl_floor`, Task 2's constants and seams. **Produces:** `_doctor_check_kernel_keys`.

- [ ] RED/GREEN; [ ] gates; [ ] commit `feat(doctor): check kernel keys floors`.

---

### Task 4: Document the kernel-keys step, route and seams in CLAUDE.md

```yaml-task
id: 4
description: Update CLAUDE.md setup/developer/doctor entries, the doctor-remedy route and Test Seams (tdd not-applicable - docs only; no file the suite reads)
role: executor
model: sonnet
tdd: not-applicable
requirements: [R13]
acceptance:
  - cmd: 'grep -q "90-dotfiles-keys-maxkeys.conf" CLAUDE.md && grep -q "_KEYS_MAXBYTES_PROC" CLAUDE.md && grep -qi "one at a time" CLAUDE.md'
    exit_code: 0
  - cmd: 'grep -n "_SYSCTL_CONF" CLAUDE.md | grep -qi "inotify"'
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 2
files_touched: [CLAUDE.md]
depends_on: [3]
```

**Do:** In `CLAUDE.md`: (1) the `setup` and `developer` bullets: the same Ubuntu docker step also persists `kernel.keys.maxkeys`/`maxbytes` floors (2000/500000) in `90-dotfiles-keys-maxkeys.conf` / `90-dotfiles-keys-maxbytes.conf`, never lowering a higher value. (2) The `doctor` bullet: add "kernel keys limits (Linux docker hosts)". (3) A sentence: on an already-provisioned host, apply by running `-t doctor` and pasting each printed remedy line one at a time (a sudo prompt can swallow the next line), then re-running doctor. (4) Test Seams, the inotify seam entry: add `_KEYS_MAXKEYS_CONF`/`_KEYS_MAXKEYS_PROC`/`_KEYS_MAXBYTES_CONF`/`_KEYS_MAXBYTES_PROC` (seeded at the floors by `load_mocks`), and state that `_SYSCTL_CONF` governs only the inotify conf. Edit in place; no new section. Say "kernel keys", not "keyring".

- [ ] Edit; [ ] gates; [ ] commit `docs: kernel keys step`.

---

## Orchestrator steps

- [ ] Create the worktree from master before Task 1; build the differential base tree.
- [ ] After Task 4: `make test` in the worktree, redirected to a file, rc captured.
- [ ] Phase 3 via `finishing-a-development-branch`.

## Non-goal check

Reviewer run 2026-10-10 against the N list from `spec_contract.py`. 0 CONFLICT, 0 UNCLEAR.

| N | Verdict | Reviewer's basis | Resolution |
| --- | --- | --- | --- |
| N1 | CLEAR | Task 1's parameterised messages (write failed, doctor PASS line) reproduce today's inotify text at `lib/linux_ubuntu.sh:56,62` and `lib/helpers.sh:1097`; backed by the `DIVERGING: 0` gate | none needed |
| N2 | CLEAR | no `sysctl -p`/`--system`; Task 2 asserts no call contains either | none needed |
| N3 | CLEAR | step gated on `HAS_DOCKER` and the systemd run dir, reachable only from `install_ubuntu_packages`; doctor also gated on `LINUX` | none needed |
| N4 | CLEAR | one conf per key; every write and remedy targets its own key's conf | none needed |
| N5 | CLEAR | grep gate requires zero old `_inotify_*` names and `INOTIFY_INT_MAX` | none needed |
| N6 | CLEAR | no new `-t` type | none needed |
