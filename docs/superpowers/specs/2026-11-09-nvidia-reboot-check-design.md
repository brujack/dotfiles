# NVIDIA driver state check: module/userspace mismatch and failed CDI refresh

- **Date:** 2026-11-09
- **Repo:** dotfiles
- **Backlog row closed:** "An nvidia userspace change without a reboot breaks GPU containers and disables CDI refresh, and nothing reports it"
- **Measurements:** `ai-config/docs/knowledge/dotfiles-apt-upgrade-hazards.md` §4

## Problem

An apt upgrade can replace the NVIDIA userspace (`libcuda`, `libnvidia-ml`) while the
running kernel keeps the old module. Until a reboot, `nvidia-smi` fails with
`Driver/library version mismatch` and GPU containers fail to start. It happened twice:

- **2026-09-16, workstation.** `nvidia-driver-610` removed the 580 userspace. The module
  stayed `580.173.02`, only `libcuda.so.610.57.04` remained, and `ai.service`
  restart-looped on `open /usr/lib/x86_64-linux-gnu/libcuda.so.580.173.02`.
- **2026-10-11, claude and workstation.** `nvidia-driver-610` became a transitional package
  to 615, so an ordinary upgrade installed `615.71.09` userspace over a loaded `610.57.04`
  module.

Both times `nvidia-cdi-refresh.path` was `failed` (`unit-start-limit-hit`). A failed path
unit stops watching, so a reboot alone does not recover it: the next driver change
regenerates no CDI spec. Both times `/var/run/reboot-required` was absent, or listed only
`libc6`, because apt does not flag an NVIDIA userspace change.

Premise checks, run 2026-11-09 against `60433c07`:

- **Hazard:** the two incidents above, from the knowledge entry. `claude` is healthy today
  (module `615.71.09`, `libcuda.so.1 -> libcuda.so.615.71.09`, path unit `active`), so the
  broken states come from fixtures, not this host.
- **Mitigation:** `run_doctor`'s only NVIDIA-aware check is `_doctor_check_flatpak_gl`, which
  reads the loaded version and never compares it to the userspace. The `apt` line in
  `lib/update_summary.sh` reports reboot only from `/var/run/reboot-required`. No spec or
  ADR proposed or rejected a check like this (`grep -ril 'cdi-refresh\|libcuda' docs/`
  finds only the backlog row).

## Decisions taken

- **Report only** (operator, 2026-11-09). No write to `/var/run/reboot-required`, no
  automatic `systemctl reset-failed`. The operator reads the update summary and doctor; a
  root write adds no reader.
- **Include the CDI watcher** (operator, 2026-11-09). A failed `nvidia-cdi-refresh` unit is
  the half of the incident that recurs.
- **Userspace version from the `libcuda.so.1` link target** (operator, 2026-11-09), not
  `dpkg-query` (package names changed once already, 610 to 615, and two can be installed
  during a transition) and not `nvidia-smi` (a binary to time out, absent when the
  userspace is removed, and silent on which version is installed). The link target is the
  file containers load.

## Design

### Components

1. **`_nvidia_userspace_version`** (`lib/linux_shared.sh`, beside `_nvidia_loaded_version`).
   Reads the link target of `${_NVIDIA_LIBCUDA:-/usr/lib/x86_64-linux-gnu/libcuda.so.1}`
   with `readlink` (one level, not `-f`), takes the part after `libcuda.so.`, and prints it
   when it matches `^[0-9]+(\.[0-9]+)+$`. Returns 1, printing nothing, when the path is not
   a symlink or the suffix does not match. The default path is amd64 multiarch; every GPU
   host in the fleet is amd64, and the seam overrides it.

2. **`_nvidia_driver_state`** (`lib/linux_shared.sh`). The one decision function both
   readers call. Prints nothing and returns 0 unless `LINUX` is set, `_nvidia_gpu_present`
   succeeds and `_nvidia_userspace_version` succeeds. Otherwise it prints zero or more
   finding lines, in this order:

   - `mismatch <loaded> <installed>` when `_nvidia_loaded_version` succeeds and its value
     with dashes turned back to dots differs from the userspace version;
   - `not-loaded <installed>` when `_nvidia_loaded_version` fails;
   - `cdi-failed <unit>` for each of `nvidia-cdi-refresh.path` and
     `nvidia-cdi-refresh.service`, in that order, whose `ActiveState` is `failed`. Read with
     `"${_SYSTEMCTL_BIN:-systemctl}" show -P ActiveState <unit>`, one property per call
     (`systemctl show` prints multiple `-P` values in its own property order, not the
     argument order). A missing unit reports `inactive` with exit 0, so it is skipped
     without a special case; a non-zero exit skips that unit.

   It returns 0 in every case: the findings are the output.

3. **`_doctor_check_nvidia_driver`** (`lib/helpers.sh`), called from `run_doctor` directly
   after `_doctor_check_flatpak_gl`. Prints a `NVIDIA driver:` header only when
   `_nvidia_driver_state`'s gates pass, then for each finding:

   - `mismatch`: `doctor_fail` naming both versions and saying `nvidia-smi` and GPU
     containers fail until a reboot.
   - `not-loaded`: `doctor_warn` naming the installed version and suggesting a reboot.
   - `cdi-failed`: `doctor_fail` naming the unit, then prints the remedy line
     `    sudo systemctl reset-failed nvidia-cdi-refresh.path nvidia-cdi-refresh.service`
     once, however many units failed. The remedy is printed, never run.
   - No finding: `doctor_pass "nvidia module <v> matches userspace; CDI refresh not failed"`.

4. **`-t update` apt line** (`lib/update_summary.sh`, `apt` case). After apt's own reboot
   note, appends one segment per finding, whether or not apt wrote its flag:
   `— reboot required (nvidia <loaded> loaded, <installed> installed)` for `mismatch`,
   `— reboot required (nvidia <installed> installed, module not loaded)` for `not-loaded`,
   and `— <unit> failed` for `cdi-failed`. Reports only.

### Data flow

`/sys/module/nvidia/version` and the `libcuda.so.1` link feed the version comparison;
`systemctl show` feeds the unit check; `_nvidia_driver_state` turns them into finding lines;
doctor and the update summary format the same lines. No state is stored.

### Error handling

An unreadable or malformed input skips that signal and never produces a finding: a check
that cannot read its inputs stays quiet rather than raising a false FAIL. A host with no
GPU or no userspace gets no section and no summary text.

## Testing

bats, TDD, one behaviour per RED/GREEN step. Fixtures only: `_NVIDIA_MODULE_VERSION_FILE`,
`_NVIDIA_LIBCUDA` (a symlink in `BATS_TEST_TMPDIR`), `_SYSTEMCTL_BIN` and
`_OVERRIDE_NVIDIA_GPU_PRESENT`, all set at `setup()` scope. `load_mocks` already points
`_SYSTEMCTL_BIN` at `tests/stubs/systemctl-stub`, which answers every `show` with the
`tmp.mount` fragment path. The stub gains one branch: for `show -P ActiveState <unit>` it
prints `MOCK_SYSTEMCTL_ACTIVE_STATE_FILE`'s line for that unit (`<unit><TAB><state>`),
`inactive` for a unit not listed, and exits `MOCK_SYSTEMCTL_SHOW_EXIT` (default 0). The
`tmp.mount` path is unchanged. `load_mocks` points `_NVIDIA_LIBCUDA` at a missing path by default, as it
already does for `_NVIDIA_MODULE_VERSION_FILE`, so no test reads `claude`'s real driver.

Cases for `_nvidia_driver_state`: versions match; mismatch; module absent; no libcuda link;
a regular file instead of a link; a malformed suffix; no GPU; `LINUX` unset; path unit
failed; service unit failed; both failed; unit missing (`inactive`); `systemctl` exit
non-zero. Every case asserts the exact output, so a function that prints nothing fails every
finding case. A replay of the 2026-10-11 shape (module `610.57.04`, link
`libcuda.so.615.71.09`, path unit `failed`) asserts both the `mismatch` and the
`cdi-failed` lines.

Doctor and update-summary tests assert the exact rendered text for one mismatch, one
not-loaded, one cdi-failed (remedy printed once for two failed units) and the PASS line,
plus the no-GPU case producing no section and no summary segment.

## Requirements

- **R1.** `_nvidia_userspace_version` prints the version suffix of the `libcuda.so.1` link target (read through `_NVIDIA_LIBCUDA`, default `/usr/lib/x86_64-linux-gnu/libcuda.so.1`) when it matches `^[0-9]+(\.[0-9]+)+$`, and returns 1 printing nothing when the path is not a symlink or the suffix does not match.
- **R2.** `_nvidia_driver_state` prints nothing unless `LINUX` is set, `_nvidia_gpu_present` succeeds and `_nvidia_userspace_version` succeeds.
- **R3.** `_nvidia_driver_state` prints `mismatch <loaded> <installed>` when the loaded module version, dashes turned to dots, differs from the userspace version, and `not-loaded <installed>` when `_nvidia_loaded_version` fails.
- **R4.** `_nvidia_driver_state` prints `cdi-failed <unit>` for each of `nvidia-cdi-refresh.path` then `nvidia-cdi-refresh.service` whose `ActiveState`, read by one `systemctl show -P ActiveState <unit>` call through `_SYSTEMCTL_BIN`, is `failed`, and skips a unit whose call exits non-zero.
- **R5.** `run_doctor` calls `_doctor_check_nvidia_driver` directly after `_doctor_check_flatpak_gl`; it FAILs on `mismatch` and `cdi-failed`, WARNs on `not-loaded`, PASSes with no finding, and prints no section when `_nvidia_driver_state`'s gates fail.
- **R6.** On any `cdi-failed` finding doctor prints the remedy `sudo systemctl reset-failed nvidia-cdi-refresh.path nvidia-cdi-refresh.service` exactly once.
- **R7.** The `-t update` apt summary line appends one segment per finding, in the forms given in Design component 4, whether or not `/var/run/reboot-required` exists.
- **R8.** `load_mocks` exports `_NVIDIA_LIBCUDA` to a missing path, and every new test sets its NVIDIA and `systemctl` seams to fixtures.
- **R9.** A bats test replays the 2026-10-11 shape (module `610.57.04`, link `libcuda.so.615.71.09`, path unit `failed`) and asserts both the `mismatch 610.57.04 615.71.09` and the `cdi-failed nvidia-cdi-refresh.path` lines.
- **R10.** `tests/stubs/systemctl-stub` answers `show -P ActiveState <unit>` from `MOCK_SYSTEMCTL_ACTIVE_STATE_FILE` (`inactive` for an unlisted unit) with exit `MOCK_SYSTEMCTL_SHOW_EXIT`, and keeps its `tmp.mount` fragment answer for every other `show`.
- **V1.** On `claude` today, `./setup_env.sh -t doctor` shows the NVIDIA driver section PASS with `615.71.09`.
- **N1.** Nothing writes `/var/run/reboot-required`, `/var/run/reboot-required.pkgs` or any file outside the test temp dir.
- **N2.** Nothing runs `systemctl reset-failed`, `restart` or any other state-changing `systemctl` verb.
- **N3.** No change to driver or container-toolkit installation, and no macOS code path.
