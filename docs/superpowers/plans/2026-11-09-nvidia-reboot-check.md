# NVIDIA Driver State Check Implementation Plan

> **Status: DONE** (dotfiles#455, merged 4f64366e)

spec: docs/superpowers/specs/2026-11-09-nvidia-reboot-check-design.md

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `-t doctor` and the `-t update` apt line report an NVIDIA module/userspace version mismatch, a missing module, and (with versions matching) a failed or unreadable `nvidia-cdi-refresh` unit, without changing any system state.

**Architecture:** Two readers in `lib/linux_shared.sh` (`_nvidia_userspace_version`, the existing `_nvidia_loaded_version`) feed one decision function, `_nvidia_driver_state`, which prints a fixed set of lines (`mismatch`, `not-loaded`, `ok`, then `cdi-failed`/`cdi-unknown` only after `ok`). `_doctor_check_nvidia_driver` (`lib/helpers.sh`) and the apt case of `_update_record_end` (`lib/update_summary.sh`) only format those lines.

**Tech Stack:** bash, bats, the existing `tests/stubs/systemctl-stub` and `load_mocks` seams.

## Global Constraints

- Report only: nothing writes `/var/run/reboot-required` or `.pkgs`, and nothing runs a state-changing `systemctl` verb (N1, N2). Remedies are printed, never run.
- No change to driver or container-toolkit installation; no macOS code path (N3).
- Userspace version = the dotted suffix of the `libcuda.so.1` link target, read with one-level `readlink` through `_NVIDIA_LIBCUDA` (default `/usr/lib/x86_64-linux-gnu/libcuda.so.1`), matching `^[0-9]+(\.[0-9]+)+$`.
- Gate order in `_nvidia_driver_state`: `LINUX` set, then `_nvidia_userspace_version`, then `_nvidia_gpu_present`; then the module-file gate (file exists but `_nvidia_loaded_version` fails: print nothing).
- `systemctl` is read only after `ok`, one `"${_SYSTEMCTL_BIN:-systemctl}" show -P ActiveState <unit>` call per unit, `nvidia-cdi-refresh.path` then `nvidia-cdi-refresh.service`.
- Every test sets `_NVIDIA_MODULE_VERSION_FILE`, `_NVIDIA_LIBCUDA`, `_OVERRIDE_NVIDIA_GPU_PRESENT` and `LINUX` itself (developer shells export `LINUX`); no test reads the host's `/sys/module/nvidia/version`, `libcuda.so.1`, `lspci` or `systemctl`.
- A new `.bats` file needs its line in `tests/bats-files.txt` (`git ls-files '*.bats' | LC_ALL=C sort`, after `git add`) and a row in `tests/bats-weights.tsv` (C-sorted; weight 8.0 until reseeded).
- Lib functions: `snake_case`, `local` variables, `${VAR}` quoting, `|| return 1`, `printf` not `echo`.

## Session-level verification

- `make test` exits 0 (orchestrator, once after Task 4; the suite runs past the Bash tool's 600 s cap, so no task gate runs it).
- V1 (orchestrator, after Task 4): from the branch worktree on `claude`, `zsh +Z -i -c './setup_env.sh -t doctor'` prints a `NVIDIA driver:` section whose PASS names `615.71.09` and reads "CDI refresh not failed".
- R9's replay test (Task 2) is the incident check: module `610.57.04`, link `libcuda.so.615.71.09`, path unit `failed` gives exactly `mismatch 610.57.04 615.71.09` and no `systemctl` call.

---

### Task 1: Test seams for the NVIDIA check

```yaml-task
id: 1
description: Add the systemctl-stub ActiveState branch and the load_mocks _NVIDIA_LIBCUDA default, with tests in a new nvidia_driver_state.bats
role: executor
model: sonnet
tdd: required
requirements: [R8, R10]
acceptance:
  - cmd: bats tests/setup_env/nvidia_driver_state.bats tests/helpers_load_mocks.bats
    exit_code: 0
  - cmd: make lint
    exit_code: 0
  - cmd: make check-bats-manifest
    exit_code: 0
max_retries: 3
files_touched: [tests/stubs/systemctl-stub, tests/helpers/common.bash, tests/helpers_load_mocks.bats, tests/setup_env/nvidia_driver_state.bats, tests/bats-files.txt, tests/bats-weights.tsv]
depends_on: []
```

**Stub** (`tests/stubs/systemctl-stub`): before the existing `show` branch, when `$1 == show && $2 == -P && $3 == ActiveState`, print the second field of the line in `${MOCK_SYSTEMCTL_ACTIVE_STATE_FILE}` whose first tab-separated field equals `$4`, else `inactive` (also when the variable is unset or the file is missing), then `exit "${MOCK_SYSTEMCTL_SHOW_EXIT:-0}"`. Keep the call log line first. Every other `show` keeps printing the `tmp.mount` fragment.

**load_mocks** (`tests/helpers/common.bash`, beside `_NVIDIA_MODULE_VERSION_FILE`): `export _NVIDIA_LIBCUDA="${BATS_TEST_TMPDIR:-/nonexistent}/no-libcuda"` with a one-line comment that `claude` and `workstation` carry a real link.

**Tests:** in `tests/helpers_load_mocks.bats`, one case that `load_mocks` exports `_NVIDIA_LIBCUDA` under `BATS_TEST_TMPDIR` and the path does not exist. New `tests/setup_env/nvidia_driver_state.bats` (header comment naming the spec; `setup()` sources `common.bash`, `load_setup_env`, `load_mocks`, sets `MOCK_CALLS_FILE`) with stub cases: a listed unit prints its state; an unlisted unit prints `inactive`; `MOCK_SYSTEMCTL_SHOW_EXIT=1` exits 1; `show -P FragmentPath tmp.mount` still prints the fragment. Add the file to `tests/bats-files.txt` and `tests/bats-weights.tsv` (`tests/setup_env/nvidia_driver_state.bats<TAB>8.0`, C-sorted).

**Interfaces:** Produces `MOCK_SYSTEMCTL_ACTIVE_STATE_FILE` (`<unit>\t<state>` lines), `MOCK_SYSTEMCTL_SHOW_EXIT`, `_NVIDIA_LIBCUDA`, and the test file Task 2 extends.

### Task 2: Version reader and decision function

```yaml-task
id: 2
description: Add _nvidia_userspace_version and _nvidia_driver_state to lib/linux_shared.sh with their bats cases, including the 2026-10-11 replay
role: executor
model: sonnet
tdd: required
requirements: [R1, R2, R3, R4, R9]
acceptance:
  - cmd: bats tests/setup_env/nvidia_driver_state.bats tests/setup_env/flatpak.bats
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched: [lib/linux_shared.sh, tests/setup_env/nvidia_driver_state.bats]
depends_on: [1]
```

Place both functions after `_nvidia_loaded_version` (`lib/linux_shared.sh:139`). `_nvidia_userspace_version`: `local _l="${_NVIDIA_LIBCUDA:-/usr/lib/x86_64-linux-gnu/libcuda.so.1}" _t`; `[[ -L "${_l}" ]] || return 1`; `_t="$(readlink "${_l}")" || return 1`; `_t="${_t##*/}"`; require `libcuda.so.` prefix, strip it, require the version regex, `printf '%s\n'`.

`_nvidia_driver_state` follows Design component 2 exactly: gates in the Global Constraints order; `_loaded` from `_nvidia_loaded_version` with `${_loaded//-/.}`; module file `${_NVIDIA_MODULE_VERSION_FILE:-/sys/module/nvidia/version}` absent gives `not-loaded <installed>`; exists-but-unparseable prints nothing; equal gives `ok <v>` then the unit loop (`cdi-failed`/`cdi-unknown`). Always `return 0`.

**Tests** (exact `[ "${output}" = "..." ]` on `run`): versions match is exactly `ok 615.71.09`; mismatch; module file absent is `not-loaded 615.71.09`; module file malformed and module file unreadable (`chmod 000`, skip when `id -u` is 0) each give empty output with a valid link; no link; regular file at the link path; malformed suffix; `_OVERRIDE_NVIDIA_GPU_PRESENT=1`; `LINUX` unset. Each empty case seeds module `610.57.04` and, where a link exists, `libcuda.so.615.71.09`, so a closed gate is the only way to stay empty. Unit cases after `ok`: path failed, service failed, both failed (two lines, path first), unlisted unit (exactly `ok <v>`), `MOCK_SYSTEMCTL_SHOW_EXIT=1` with the unit listed `failed` gives `cdi-unknown` lines and no `cdi-failed`. No-link case redefines `_nvidia_gpu_present` to append to `${BATS_TEST_TMPDIR}/gpu-probe-calls` and asserts that file is empty or absent. R9 replay asserts exactly `mismatch 610.57.04 615.71.09` and no `systemctl` line in `MOCK_CALLS_FILE`. Mutation check before commit: swap the `mismatch`/`ok` comparison and confirm cases fail; revert.

**Interfaces:** Consumes Task 1's seams. Produces `_nvidia_driver_state` (no args, lines on stdout, returns 0) and `_nvidia_userspace_version`.

### Task 3: Doctor section

```yaml-task
id: 3
description: Add _doctor_check_nvidia_driver to lib/helpers.sh, call it from run_doctor after _doctor_check_flatpak_gl, with exact-text tests
role: executor
model: sonnet
tdd: required
requirements: [R5, R6]
acceptance:
  - cmd: bats tests/setup_env/doctor_nvidia_driver.bats tests/setup_env/doctor_flatpak_gl.bats
    exit_code: 0
  - cmd: make lint
    exit_code: 0
  - cmd: make check-bats-manifest
    exit_code: 0
max_retries: 3
files_touched: [lib/helpers.sh, tests/setup_env/doctor_nvidia_driver.bats, tests/bats-files.txt, tests/bats-weights.tsv]
depends_on: [2]
```

Follow Design component 3 for every line. Read `_nvidia_driver_state` once into a variable; empty returns 0 with no output. Header `printf "\nNVIDIA driver:\n"`. `mismatch` FAIL text names both versions and "reboot"; `not-loaded` WARN text is exactly `nvidia module not loaded (userspace <v> installed): reboot if the driver was just installed, otherwise check dkms status`; `cdi-failed` FAIL per unit, then the remedy line printed once with four-space indent: `sudo systemctl reset-failed nvidia-cdi-refresh.path nvidia-cdi-refresh.service && sudo systemctl start nvidia-cdi-refresh.path`; `cdi-unknown` WARN `cannot read <unit> state`; `ok <v>` PASS `nvidia module <v> matches userspace; CDI refresh not failed` when no cdi line, else `nvidia module <v> matches userspace`. Insert the call on the line after `_doctor_check_flatpak_gl` in `run_doctor`.

**Tests** (new file modelled on `doctor_flatpak_gl.bats`: call in the current shell, read `_DOCTOR_*` counters, capture to `OUT`; stub `_nvidia_driver_state` with a function printing fixed lines): empty output gives no header and zero counters; one case per line kind asserting exact text and counter deltas; two `cdi-failed` lines print the remedy exactly once; `mismatch` and `not-loaded` print no `systemctl` remedy; `ok` plus `cdi-unknown` and `ok` plus `cdi-failed` print the short PASS; a `run_doctor` source-order case asserts `_doctor_check_nvidia_driver` is the line after `_doctor_check_flatpak_gl` (`grep -A1`). Register the file in `tests/bats-files.txt` and `tests/bats-weights.tsv` (8.0).

**Interfaces:** Consumes `_nvidia_driver_state`, `doctor_pass`/`doctor_warn`/`doctor_fail`.

### Task 4: Update summary apt line

```yaml-task
id: 4
description: Fold _nvidia_driver_state findings into the apt result line of _update_record_end, with tests in update_summary.bats
role: executor
model: sonnet
tdd: required
requirements: [R7]
acceptance:
  - cmd: bats tests/setup_env/update_summary.bats
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched: [lib/update_summary.sh, tests/setup_env/update_summary.bats]
depends_on: [2]
```

Replace the reboot block at `lib/update_summary.sh:534-545` per Design component 4. Read `_nvidia_driver_state` once. Build the reboot reasons: apt's `.pkgs` list (when the flag and file exist) and the mismatch reason `nvidia <loaded> loaded, <installed> installed`, joined with `; `. Append `— reboot required (<reasons>)` when any reason exists, `— reboot required` when only the flag exists. Then `— nvidia module not loaded (<v> installed)` for `not-loaded` and `— <unit> failed (see -t doctor)` per `cdi-failed`. `ok` and `cdi-unknown` add nothing.

**Tests** (add beside the existing reboot cases at line 655; stub `_nvidia_driver_state` per test; existing four cases keep passing with the stub printing nothing): mismatch with flag and `.pkgs` gives `— reboot required (linux-image-6.8.0-58-generic; nvidia 610.57.04 loaded, 615.71.09 installed)`; mismatch with flag and no `.pkgs`; mismatch with no flag; each asserts `grep -o 'reboot required' | wc -l` equals 1 (compare numerically: BSD `wc` pads); `not-loaded` gives the segment and no `reboot required`; `cdi-failed` gives `— nvidia-cdi-refresh.path failed (see -t doctor)`; `ok` and `cdi-unknown` leave the line unchanged.

**Interfaces:** Consumes `_nvidia_driver_state`.

### Task 5: Docs

```yaml-task
id: 5
description: CLAUDE.md seam rule line and backlog row removal (docs-only, no behaviour change, so no TDD)
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: 'grep -q "_NVIDIA_LIBCUDA" CLAUDE.md'
    exit_code: 0
  - cmd: '! grep -q "An nvidia userspace change without a reboot breaks GPU containers" docs/superpowers/README.md'
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 2
files_touched: [CLAUDE.md, docs/superpowers/README.md]
depends_on: [3, 4]
```

In `CLAUDE.md` § Test Seams, after the `load_mocks` `_NVIDIA_MODULE_VERSION_FILE`/flatpak bullet, add one bullet: `load_mocks` points `_NVIDIA_LIBCUDA` at a missing path; NVIDIA driver-state tests set it, `_NVIDIA_MODULE_VERSION_FILE`, `_OVERRIDE_NVIDIA_GPU_PRESENT` and `MOCK_SYSTEMCTL_ACTIVE_STATE_FILE`/`MOCK_SYSTEMCTL_SHOW_EXIT` (`tests/stubs/systemctl-stub`) to fixtures, ending `→ dotfiles-test-seams.md § NVIDIA driver state seams`. In `docs/superpowers/README.md` delete the Backlog row "An nvidia userspace change without a reboot breaks GPU containers and disables CDI refresh, and nothing reports it". Leave the plan index rows alone.

**Orchestrator, not this task:** message the ai-config session first, then add `## NVIDIA driver state seams` to `ai-config/docs/knowledge/dotfiles-test-seams.md` and a "Detected since dotfiles#<n>" line to `dotfiles-apt-upgrade-hazards.md` §4.

## Non-goal check

Run 2026-11-09 against the plan before commit (one fresh reviewer, `nongoal-check.md`).

- N1 CLEAR — "Task 4 only reads `/var/run/reboot-required` and `.pkgs`; fixtures stay under `BATS_TEST_TMPDIR`." No resolution needed.
- N2 CLEAR — "The only `systemctl` call is `show -P ActiveState`; the `reset-failed && start` remedy is printed via `printf`, never run." No resolution needed.
- N3 CLEAR — "No task touches driver or toolkit installation; `_nvidia_driver_state` is gated on `LINUX`." No resolution needed.
