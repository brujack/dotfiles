# Flatpak Update Section and NVIDIA GL Check Implementation Plan

spec: docs/superpowers/specs/2026-10-12-flatpak-update-design.md

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `-t update` updates system flatpaks and removes unused runtimes; update and doctor report a missing or stale NVIDIA GL extension.

**Architecture:** Three read helpers in `lib/linux_shared.sh` feed `update_flatpak_packages` (same file) and `_doctor_check_flatpak_gl` (`lib/helpers.sh`). `run_update` gains a `flatpak` section after `snap`. A new `tests/mocks/flatpak` plus a captured real `flatpak list` fixture drive the tests.

**Tech Stack:** bash, bats, flatpak 1.16.6.

## Global Constraints

- No `--user` flatpak installation is read, updated or uninstalled (N1).
- No code uninstalls a flatpak ref by name; the only uninstall is `--unused` (R16, N3).
- `_doctor_check_flatpak_gl` never calls `doctor_fail` and never runs a mutating flatpak command (N4).
- Every `sudo` call that runs flatpak is `sudo flatpak ... -y --noninteractive --system`.
- Every test sets `_NVIDIA_MODULE_VERSION_FILE` to a fixture; `load_mocks` defaults it to a nonexistent path (`claude` and `workstation` have a real `/sys/module/nvidia/version`).
- No test runs a real mutating `flatpak` command. `tests/mocks/sudo` execs its argument, so `sudo flatpak` resolves to `tests/mocks/flatpak` only while the mocks dir leads `PATH`.

## Settled before planning: uninstall with Steam running

Read in flatpak 1.16.6 (`common/flatpak-dir.c`, `flatpak_dir_undeploy`): an undeploy renames the checkout into `.removed/` and deletes it only when `dir_is_locked` reports no running instance holds it; otherwise deletion is deferred to later cleanup. `--force-remove` changes only that deferral. Nothing in `common/flatpak-transaction.c` or `app/flatpak-builtins-uninstall.c` refuses on a running app. So neither step 1's auto-prune nor `--unused` fails while Steam runs, and the design needs no change. `uninstall --unused` with nothing to remove prints `Nothing unused to uninstall` and exits 0 (`app/flatpak-builtins-uninstall.c:368-371`).

## Verification

- `make test` exits 0; `make lint` exits 0.
- On `claude`: `./setup_env.sh -t update --pkgs-only` shows `flatpak` OK; `./setup_env.sh -t doctor` shows `Flatpak NVIDIA GL:` with one `[PASS]` (V1). Run `workstation` the same way over `ssh workstation`.
- CI `bash-coverage` stays at or above 91% (V2); publish the CI figure in the PR body.
- Edge cases the bats suite must exercise: absent/empty/non-numeric version file; runtime list empty; list containing only `VAAPI.nvidia`; `GL32` present without `GL`; no apps; each list command failing; `update` and `--unused` failing separately.

---

### Task 1: Read helpers, flatpak mock, captured fixture

```yaml-task
id: 1
description: Add _flatpak_available, _nvidia_loaded_version, _flatpak_nvidia_gl_refs, _flatpak_has_apps, tests/mocks/flatpak, a captured runtime-list fixture and the load_mocks default
role: executor
model: sonnet
tdd: required
requirements: [R1, R2]
acceptance:
  - cmd: make lint
    exit_code: 0
  - cmd: bats tests/setup_env/flatpak.bats
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [lib/linux_shared.sh, tests/mocks/flatpak, tests/fixtures/flatpak/runtime-list.tsv, tests/helpers/common.bash, tests/setup_env/flatpak.bats]
depends_on: []
```

**Fixture:** capture real bytes, never hand-type:
`flatpak list --system --runtime --columns=application,arch,branch > tests/fixtures/flatpak/runtime-list.tsv`
Then check `grep -c $'\t'` equals the line count, and that it holds `GL.nvidia-615-71-09`, `GL32.nvidia-615-71-09`, `VAAPI.nvidia` and `VAAPI.nvidia.i386` lines.

**Mock `tests/mocks/flatpak`:** log `flatpak $*` to `MOCK_CALLS_FILE`. If `MOCK_FLATPAK_FAIL_SUBCMD` equals `$1`, exit 1; if `MOCK_FLATPAK_FAIL_ARGS` is non-empty and `$*` contains it, exit 1. `list` with `--runtime` prints the file named by `MOCK_FLATPAK_LIST_RUNTIME` (nothing when unset); with `--app` prints `MOCK_FLATPAK_LIST_APP` (a string, may contain `\n`). Everything else exits 0.

**`load_mocks`:** `export _NVIDIA_MODULE_VERSION_FILE="${BATS_TEST_TMPDIR:-/nonexistent}/no-nvidia-version"` with a comment naming the hazard.

**Code (`lib/linux_shared.sh`, after `update_snap_packages`):**

```bash
# A seam, like _snap_available: a test that strips PATH to hide flatpak would
# expose the real /usr/bin/flatpak on claude and workstation (tdd.md E2).
_flatpak_available() {
  command -v flatpak > /dev/null 2>&1
}

# flatpak names NVIDIA GL extensions after the loaded module's version with dots
# turned into dashes, read from this same file (flatpak 1.16.6 common/flatpak-utils.c).
_nvidia_loaded_version() {
  local _f="${_NVIDIA_MODULE_VERSION_FILE:-/sys/module/nvidia/version}" _v=""
  [[ -r "${_f}" ]] || return 1
  IFS= read -r _v < "${_f}" || [[ -n "${_v}" ]] || return 1
  [[ "${_v}" =~ ^[0-9]+(\.[0-9]+)+$ ]] || return 1
  printf '%s\n' "${_v//./-}"
}

_flatpak_nvidia_gl_refs() {
  local _list
  _list="$(flatpak list --system --runtime --columns=application,arch,branch)" || return 1
  awk -F'\t' '$1 ~ /^org\.freedesktop\.Platform\.GL(32)?\.nvidia-/ { print $1 "/" $2 "/" $3 }' <<<"${_list}"
}

# 0 apps installed, 1 none, 2 the list failed.
_flatpak_has_apps() {
  local _list
  _list="$(flatpak list --system --app --columns=application)" || return 2
  [[ -n "${_list//[[:space:]]/}" ]]
}
```

**Tests (`tests/setup_env/flatpak.bats`, setup = `load_setup_env`, `load_mocks`, `MOCK_CALLS_FILE`, scratch `HOME`):**

- R1: `615.71.09\n` -> `615-71-09` rc 0; no trailing newline -> same; absent file, empty file, `615.71.09-beta`, `615` -> rc 1, empty output.
- R2: fixture -> exactly the two `GL*.nvidia-615-71-09/x86_64/1.4` lines, no `VAAPI`; `GL.default` excluded; empty list -> empty, rc 0; `MOCK_FLATPAK_FAIL_SUBCMD=list` -> rc 1.
- `_flatpak_has_apps`: one app -> 0; empty -> 1; list fails -> 2.
- Host-gated read-only test: strip `tests/mocks` from `PATH` (idiom in `shell.md` "A PATH mock shadows"), skip unless `command -v flatpak` then resolves; it runs only `flatpak list`; unset `_NVIDIA_MODULE_VERSION_FILE`; every output line matches `^org\.freedesktop\.Platform\.GL(32)?\.nvidia-[0-9-]+/[^/]+/[^/]+$`; no `VAAPI`; if `/sys/module/nvidia/version` is readable, output contains `GL.nvidia-$(tr . - </sys/module/nvidia/version)/`.

**Interfaces — Produces:** `_flatpak_available` (rc 0/1), `_nvidia_loaded_version` (stdout dashed version, rc 0/1), `_flatpak_nvidia_gl_refs` (stdout `app/arch/branch` lines, rc 0/1), `_flatpak_has_apps` (rc 0/1/2), mock vars `MOCK_FLATPAK_LIST_RUNTIME`, `MOCK_FLATPAK_LIST_APP`, `MOCK_FLATPAK_FAIL_SUBCMD`, `MOCK_FLATPAK_FAIL_ARGS`.

- [ ] Write failing tests, run, confirm red for the missing functions
- [ ] Implement, run gates, commit (`caveman:caveman-commit`)

### Task 2: update_flatpak_packages and the run_update section

```yaml-task
id: 2
description: Add update_flatpak_packages and a flatpak run_update section after snap with rc-2 WARN handling
role: executor
model: sonnet
tdd: required
requirements: [R3, R6, R7, R8, R13, R15, R16]
acceptance:
  - cmd: make lint
    exit_code: 0
  - cmd: bats tests/setup_env/flatpak.bats
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [lib/linux_shared.sh, lib/workflows.sh, lib/update_summary.sh, tests/setup_env/flatpak.bats]
depends_on: [1]
```

**Code (`lib/linux_shared.sh`, after the helpers):**

```bash
# Spec: docs/superpowers/specs/2026-10-12-flatpak-update-design.md
# Removes nothing by name: a plain `flatpak update` already auto-prunes GL
# extensions for inactive drivers (autoprune-unless = active-gl-driver).
update_flatpak_packages() {
  local _loaded _refs _apps_rc
  sudo flatpak update -y --noninteractive --system || { log_error "flatpak update failed"; return 1; }
  sudo flatpak uninstall -y --noninteractive --system --unused || { log_error "flatpak uninstall --unused failed"; return 1; }
  if ! _loaded="$(_nvidia_loaded_version)"; then
    log_info "Updated flatpak runtimes"
    return 0
  fi
  _refs="$(_flatpak_nvidia_gl_refs)" || { log_error "flatpak: cannot list runtimes"; return 1; }
  _flatpak_has_apps
  _apps_rc=$?
  [[ ${_apps_rc} -ne 2 ]] || { log_error "flatpak: cannot list apps"; return 1; }
  if [[ ${_apps_rc} -eq 0 ]] && ! grep -q "^org\.freedesktop\.Platform\.GL\.nvidia-${_loaded}/" <<<"${_refs}"; then
    printf 'flatpak: no GL.nvidia-%s installed for loaded driver %s; flatpak apps get no NVIDIA GL. Flathub may not publish it yet: re-run -t update later.\n' \
      "${_loaded}" "${_loaded//-/.}"
    return 2
  fi
  log_info "Updated flatpak runtimes"
}
```

**`lib/workflows.sh`:** inside the Linux block after the snap `if`, mirror cargo-tools (`lib/workflows.sh:1277-1281`): `_flatpak_available` -> `_update_record_start "flatpak"`, run piped to `tee "${_DOTFILES_RUN_TMPDIR}/err_flatpak"`, capture `${PIPESTATUS[0]}` into `_flatpak_rc`, `_update_record_end "flatpak" "$(( _flatpak_rc == 2 ? 0 : _flatpak_rc ))"`, on 2 `_update_warn "flatpak" "no NVIDIA GL extension for the loaded driver — see detail"` and `_update_write_detail_from_err "flatpak" "update output"`; else `_update_skip "flatpak" "flatpak not installed on this host"`. Add `_update_skip "flatpak" "not applicable"` and `"flag not set"` beside snap's. **`lib/update_summary.sh`:** `flatpak` directly after `snap` in `_UPDATE_SECTION_ORDER`.

**Tests (append to `tests/setup_env/flatpak.bats`):** version fixture `615.71.09`, `MOCK_FLATPAK_LIST_RUNTIME` = the Task 1 fixture or a copy with a line deleted, `MOCK_FLATPAK_LIST_APP=com.valvesoftware.Steam` unless stated.

- R3: update fails -> rc 1, no `uninstall` line in `MOCK_CALLS_FILE`.
- R7: `MOCK_FLATPAK_FAIL_ARGS=--unused` -> rc 1, no `list` call after it; `update` logged before `uninstall`.
- R16: on success the only `flatpak uninstall` line is `uninstall -y --noninteractive --system --unused`.
- R6: no version file -> rc 0, no `flatpak:` line, no `list` call.
- R13: fixture with the `GL.nvidia-615-71-09` line removed -> rc 2 and the line; empty runtime list -> rc 2; `GL32` only -> rc 2; full fixture -> rc 0; no apps (`MOCK_FLATPAK_LIST_APP=`) with GL missing -> rc 0, no line.
- R15: runtime list fails -> rc 1; app list fails (`MOCK_FLATPAK_FAIL_ARGS=--app`) -> rc 1.
- R8: via `run_update` with `UPDATE_PKGS=1 LINUX=1`: OK / WARN (reason text and `detail_flatpak` contains the `flatpak:` line) / FAIL / SKIP when flatpak is absent (override `_flatpak_available() { return 1; }`, never `PATH`, as the snap test at `tests/setup_env/workflows.bats:2148` does); `_UPDATE_SECTION_ORDER` has `flatpak` at index of `snap` + 1.

- [ ] Write failing tests, run red
- [ ] Implement, run gates, commit

### Task 3: Doctor check `_doctor_check_flatpak_gl`

```yaml-task
id: 3
description: Add _doctor_check_flatpak_gl (missing and stale NVIDIA GL refs, pastable remedies), wire it into run_doctor, stub it in the run_doctor end-to-end tests
role: executor
model: sonnet
tdd: required
requirements: [R9, R10, R11]
acceptance:
  - cmd: make lint
    exit_code: 0
  - cmd: bats tests/setup_env/doctor_flatpak_gl.bats
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [lib/helpers.sh, tests/setup_env/doctor_flatpak_gl.bats, tests/setup_env/unit.bats, tests/setup_env/plugin_node_paths.bats]
depends_on: [2]
```

**Code (`lib/helpers.sh`, after `_doctor_check_conffile_dist`; call it right after that call in `run_doctor`):**

```bash
# Spec: docs/superpowers/specs/2026-10-12-flatpak-update-design.md. Reports
# only; the remedies are printed for the operator, never run.
_doctor_check_flatpak_gl() {
  [[ -n ${LINUX} ]] || return 0
  _flatpak_available || return 0
  local _loaded _refs _apps_rc _ref _ver _warned=0
  _loaded="$(_nvidia_loaded_version)" || return 0
  _flatpak_has_apps
  _apps_rc=$?
  [[ ${_apps_rc} -ne 1 ]] || return 0
  printf "\nFlatpak NVIDIA GL:\n"
  if [[ ${_apps_rc} -eq 2 ]] || ! _refs="$(_flatpak_nvidia_gl_refs)"; then
    doctor_warn "flatpak" "cannot list flatpak runtimes or apps"
    return 0
  fi
  if ! grep -q "^org\.freedesktop\.Platform\.GL\.nvidia-${_loaded}/" <<<"${_refs}"; then
    doctor_warn "GL.nvidia-${_loaded}" "no GL.nvidia-${_loaded} for loaded driver ${_loaded//-/.}; if this command already ran since the reboot, Flathub does not publish it yet and nothing local fixes it. Fetch it with:"
    printf '    sudo flatpak update -y --noninteractive --system\n'
    _warned=1
  fi
  while IFS= read -r _ref; do
    [[ -n "${_ref}" ]] || continue
    _ver="${_ref%%/*}"
    _ver="${_ver##*.nvidia-}"
    [[ "${_ver}" != "${_loaded}" ]] || continue
    doctor_warn "${_ref}" "stale (driver ${_ver//-/.} not loaded); remove with:"
    printf '    sudo flatpak uninstall -y --noninteractive --system %s\n' "${_ref}"
    _warned=1
  done <<<"${_refs}"
  [[ ${_warned} -eq 1 ]] || doctor_pass "GL.nvidia-${_loaded} installed; no stale NVIDIA GL refs"
}
```

**Tests (`tests/setup_env/doctor_flatpak_gl.bats`, setup like `doctor_conffile_dist.bats`; every case sets or unsets `LINUX`):**

- R9: silent (empty output, all counters 0) for `LINUX` unset; `_flatpak_available` overridden to return 1; no apps; version file absent.
- R10: full fixture -> one `[PASS]`, no `[WARN]`; `GL.nvidia-615` line removed -> one `[WARN]` naming Flathub, the next line exactly `    sudo flatpak update -y --noninteractive --system`; fixture plus an appended `org.freedesktop.Platform.GL.nvidia-580-159-03<TAB>x86_64<TAB>1.4` and its GL32 twin -> two `[WARN]`, each followed by `    sudo flatpak uninstall -y --noninteractive --system <that ref>`, no warning for any `615` ref; runtime list fails -> one `[WARN]` "cannot list"; app list fails -> same; `_DOCTOR_FAILED` stays 0 in every case; `MOCK_CALLS_FILE` holds no `flatpak update`/`uninstall` line in any case (N4).
- R11: `run_doctor` body contains `_doctor_check_flatpak_gl` directly after `_doctor_check_conffile_dist` (`declare -f run_doctor`).
- Existing end-to-end `run_doctor` tests stub every check by name: add `_doctor_check_flatpak_gl() { :; }` beside each `_doctor_check_conffile_dist() { :; }` stub (`tests/setup_env/unit.bats` 6 sites, `tests/setup_env/plugin_node_paths.bats` 1).

- [ ] Write failing tests, run red
- [ ] Implement, run gates, commit

### Task 4: dotfiles#334 comment fixes

```yaml-task
id: 4
description: Apply the three dotfiles#334 code-review comment fixes (comments only, no behaviour change, so TDD does not apply)
role: executor
model: sonnet
tdd: not-applicable
requirements: [R12]
acceptance:
  - cmd: make lint
    exit_code: 0
  - cmd: bats tests/setup_env/linux_ubuntu.bats
    exit_code: 0
  - cmd: 'bash -c "! git diff origin/master -- lib/linux_ubuntu.sh tests/setup_env/linux_ubuntu.bats | grep -E \"^[+-][^+-]\" | grep -vE \"^[+-][[:space:]]*#\""'
    exit_code: 0
max_retries: 2
files_touched: [lib/linux_ubuntu.sh, tests/setup_env/linux_ubuntu.bats]
depends_on: [3]
```

1. `lib/linux_ubuntu.sh`, comment above `_install_ubuntu_nvidia`: the second line (`# 615.71.09-0ubuntu0.26.04.2 on resolute), so it needs no third-party source. The container toolkit does, and that repo's GPG`) is ~130 characters; re-wrap the paragraph to the surrounding ~85-column width, words unchanged.
2. `tests/setup_env/linux_ubuntu.bats`, comment above `_nvidia_dpkg_shim`: replace "Like real dpkg it always prints a header" with wording that the shim prints a header and per-package rows and does not mimic real `dpkg -l <unknown>`, which prints only `dpkg-query: no packages found matching ...` and exits 1.
3. Same file, `setup()` comment above `export SHIM_DIR=`: name the `dpkg` shim that `_nvidia_dpkg_shim` writes into `SHIM_DIR` lazily, per test.

The third gate fails if any changed line in those files is not a comment line.

- [ ] Edit, run gates, commit

### Task 5: CLAUDE.md

```yaml-task
id: 5
description: Document the flatpak update section, doctor check and test seams in CLAUDE.md (docs only, so TDD does not apply)
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: make lint
    exit_code: 0
  - cmd: 'grep -q "_NVIDIA_MODULE_VERSION_FILE" CLAUDE.md'
    exit_code: 0
  - cmd: 'grep -q "MOCK_FLATPAK_LIST_RUNTIME" CLAUDE.md'
    exit_code: 0
max_retries: 2
files_touched: [CLAUDE.md]
depends_on: [4]
```

- `update` entry point: one sentence that a `flatpak` section runs after `snap` (system installation only: `flatpak update`, then `uninstall --unused`), and WARNs when the loaded driver's `GL.nvidia-*` extension is missing.
- `doctor` entry point list: add "flatpak NVIDIA GL extension missing or stale (Linux, flatpak apps installed)".
- Test Seams: one bullet group for `_NVIDIA_MODULE_VERSION_FILE` (`lib/linux_shared.sh:_nvidia_loaded_version`, defaulted by `load_mocks` to a nonexistent path because the real file exists on `claude`/`workstation`) and `tests/mocks/flatpak` (`MOCK_FLATPAK_LIST_RUNTIME` is a file path, `MOCK_FLATPAK_LIST_APP` a string, `MOCK_FLATPAK_FAIL_SUBCMD`, `MOCK_FLATPAK_FAIL_ARGS`; the runtime fixture is captured real output, never hand-typed).
- Match the surrounding bullet style; no measured figures.

- [ ] Edit, run gates, commit

## Orchestrator steps

- [ ] Before Task 1: worktree `../dotfiles-flatpak` on branch `feat/flatpak-update` from `origin/master`.
- [ ] After Task 5: `make test` once, then Phase 3 (`finishing-a-development-branch`).
- [ ] Post-merge: add `MOCK_FLATPAK_*` rows to `ai-config/docs/knowledge/dotfiles-bats-test-infrastructure.md`; V3 is recorded when the next NVIDIA point release lands.

## Non-goal check

Fresh reviewer, 2026-10-12, against N1-N4 of the spec: 4 CLEAR, 0 CONFLICT, 0 UNCLEAR. No plan revision or amendment was needed.

- N1 CLEAR: every flatpak call in the plan passes `--system`, including the fixture capture and the host-gated read-only test.
- N2 CLEAR: the only removal is `uninstall --unused`; no task touches `_install_ubuntu_gui_tools`; Task 4 changes comments only.
- N3 CLEAR: the doctor check prints the `sudo flatpak uninstall ... <ref>` line with `printf` and never runs it.
- N4 CLEAR: the doctor check uses only `doctor_warn`/`doctor_pass` and list helpers; R10 tests assert `_DOCTOR_FAILED` stays 0 and no update/uninstall call is logged.
