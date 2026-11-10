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

Both times `nvidia-cdi-refresh.path` was `failed` (`unit-start-limit-hit`). That failure is
caused by the mismatch: the service runs `nvidia-smi -L`, which fails on it, and five failed
starts trip the start limit. A failed path unit stops watching, so a second driver change
before the reboot regenerates no CDI spec. A reboot recovers both: failed state lives only in
systemd's memory, and `claude`, `failed` on 2026-10-11, has read `active` since its
2026-11-06 boot. Both times `/var/run/reboot-required` was absent, or listed only `libc6`,
because apt does not flag an NVIDIA userspace change.

A failed unit with matching versions has not been seen: since the 2026-10-11 boot both
hosts' journals for the two units hold only `nvsandboxutils` warnings. It is reported anyway,
because then a reboot is not the obvious fix and the watcher stays off until one.

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
- **Include the CDI watcher** (operator, 2026-11-09), reported only when no version finding
  exists (round 1 review, operator: Addressed). With a mismatch the reboot fixes both, and a
  `reset-failed` before it re-arms a watcher that fails again on the same mismatch.
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
   readers call. Prints nothing and returns 0 unless, checked in this order, `LINUX` is set,
   `_nvidia_userspace_version` succeeds and `_nvidia_gpu_present` succeeds. The libcuda
   link comes before `lspci` so that a host or test with no userspace never runs `lspci`.
   Otherwise it prints at most one version finding, or else zero or more unit findings:

   - `mismatch <loaded> <installed>` when `_nvidia_loaded_version` succeeds and its value
     with dashes turned back to dots differs from the userspace version;
   - `not-loaded <installed>` when `_nvidia_loaded_version` fails;
   - only when neither of the above was printed, `cdi-failed <unit>` for each of
     `nvidia-cdi-refresh.path` and `nvidia-cdi-refresh.service`, in that order, whose
     `ActiveState` is `failed`. With a version finding `systemctl` is not called at all: the
     reboot that finding asks for also clears the unit, and the service fails on the
     mismatch anyway (it runs `nvidia-smi -L`). Read with
     `"${_SYSTEMCTL_BIN:-systemctl}" show -P ActiveState <unit>`, one property per call
     (`systemctl show` prints multiple `-P` values in its own property order, not the
     argument order). A missing unit reports `inactive` with exit 0, so it is skipped
     without a special case; a non-zero exit skips that unit.

   It returns 0 in every case: the findings are the output.

3. **`_doctor_check_nvidia_driver`** (`lib/helpers.sh`), called from `run_doctor` directly
   after `_doctor_check_flatpak_gl`. Prints a `NVIDIA driver:` header only when
   `_nvidia_driver_state`'s gates pass, then for each finding:

   - `mismatch`: `doctor_fail` naming both versions and saying `nvidia-smi`, GPU containers
     and the CDI refresh fail until a reboot, and that the reboot is the remedy.
   - `not-loaded`: `doctor_warn` naming the installed version and suggesting a reboot.
   - `cdi-failed`: `doctor_fail` naming the unit, then prints the remedy line
     `    sudo systemctl reset-failed nvidia-cdi-refresh.path nvidia-cdi-refresh.service && sudo systemctl start nvidia-cdi-refresh.path`
     once, however many units failed. `reset-failed` alone leaves the path unit inactive
     rather than watching, hence the `start`. The remedy is printed, never run.
   - No finding: `doctor_pass "nvidia module <v> matches userspace; CDI refresh not failed"`.

4. **`-t update` apt line** (`lib/update_summary.sh`, `apt` case). A version finding becomes
   a reason inside the line's single reboot note, whether or not apt wrote its flag:
   `nvidia <loaded> loaded, <installed> installed` for `mismatch` and
   `nvidia <installed> installed, module not loaded` for `not-loaded`. With apt's flag and
   its `.pkgs` list the note reads `— reboot required (<pkgs>; <nvidia reason>)`; with the
   flag and no list, or with no flag, `— reboot required (<nvidia reason>)`. Each
   `cdi-failed` finding appends `— <unit> failed`. "reboot required" never appears twice
   on the line. Reports only.

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
`libcuda.so.615.71.09`, path unit `failed`) asserts the output is exactly
`mismatch 610.57.04 615.71.09` and that the `systemctl` stub recorded no call. A no-link case
redefines `_nvidia_gpu_present` in the test as a function that records its call, and
asserts the output is empty and no call was recorded.

Doctor and update-summary tests assert the exact rendered text for one mismatch, one
not-loaded, one cdi-failed (remedy printed once for two failed units) and the PASS line,
plus the no-GPU case producing no section and no summary segment. Update-summary cases cover
the three reboot-note shapes: apt flag with `.pkgs`, apt flag without, and no apt flag, each
with a mismatch, asserting "reboot required" appears exactly once.

## Requirements

- **R1.** `_nvidia_userspace_version` prints the version suffix of the `libcuda.so.1` link target (read through `_NVIDIA_LIBCUDA`, default `/usr/lib/x86_64-linux-gnu/libcuda.so.1`) when it matches `^[0-9]+(\.[0-9]+)+$`, and returns 1 printing nothing when the path is not a symlink or the suffix does not match.
- **R2.** `_nvidia_driver_state` prints nothing unless, checked in this order, `LINUX` is set, `_nvidia_userspace_version` succeeds and `_nvidia_gpu_present` succeeds; it does not call `_nvidia_gpu_present` when `_nvidia_userspace_version` fails.
- **R3.** `_nvidia_driver_state` prints `mismatch <loaded> <installed>` when the loaded module version, dashes turned to dots, differs from the userspace version, and `not-loaded <installed>` when `_nvidia_loaded_version` fails.
- **R4.** Only when R3 printed nothing, `_nvidia_driver_state` prints `cdi-failed <unit>` for each of `nvidia-cdi-refresh.path` then `nvidia-cdi-refresh.service` whose `ActiveState`, read by one `systemctl show -P ActiveState <unit>` call through `_SYSTEMCTL_BIN`, is `failed`, and skips a unit whose call exits non-zero; when R3 printed a line it makes no `systemctl` call.
- **R5.** `run_doctor` calls `_doctor_check_nvidia_driver` directly after `_doctor_check_flatpak_gl`; it FAILs on `mismatch` and `cdi-failed`, WARNs on `not-loaded`, PASSes with no finding, and prints no section when `_nvidia_driver_state`'s gates fail.
- **R6.** On any `cdi-failed` finding doctor prints the remedy `sudo systemctl reset-failed nvidia-cdi-refresh.path nvidia-cdi-refresh.service && sudo systemctl start nvidia-cdi-refresh.path` exactly once, and prints no `systemctl` remedy for a `mismatch` or `not-loaded` finding.
- **R7.** The `-t update` apt summary line carries a version finding as a reason inside a single "reboot required" note and each `cdi-failed` finding as a `— <unit> failed` segment, in the forms given in Design component 4, whether or not `/var/run/reboot-required` exists, and never contains "reboot required" twice.
- **R8.** `load_mocks` exports `_NVIDIA_LIBCUDA` to a missing path, and every new test sets its NVIDIA and `systemctl` seams to fixtures.
- **R9.** A bats test replays the 2026-10-11 shape (module `610.57.04`, link `libcuda.so.615.71.09`, path unit `failed`) and asserts the output is exactly `mismatch 610.57.04 615.71.09` with no `systemctl` call recorded.
- **R10.** `tests/stubs/systemctl-stub` answers `show -P ActiveState <unit>` from `MOCK_SYSTEMCTL_ACTIVE_STATE_FILE` (`inactive` for an unlisted unit) with exit `MOCK_SYSTEMCTL_SHOW_EXIT`, and keeps its `tmp.mount` fragment answer for every other `show`.
- **V1.** On `claude` today, `./setup_env.sh -t doctor` shows the NVIDIA driver section PASS with `615.71.09`.
- **N1.** Nothing writes `/var/run/reboot-required`, `/var/run/reboot-required.pkgs` or any file outside the test temp dir.
- **N2.** Nothing runs `systemctl reset-failed`, `restart` or any other state-changing `systemctl` verb.
- **N3.** No change to driver or container-toolkit installation, and no macOS code path.

## Multi-Lens Review

Reviewed at commit: `571c53c9` (Step 7 self-review commit, before Step 8 dispatch)

### Goal-Fit

Finding: Worth building; the mismatch half fits the goal and the `-t update` line closes the measured three-day gap (615 installed by hand 2026-10-08, found 2026-10-11). The CDI half rested on a false premise: "a reboot alone does not recover it" contradicts knowledge §4 ("recovers on reboot or `systemctl reset-failed`"), failed state does not survive a boot, and both recorded `cdi-failed` states came with a mismatch. So `cdi-failed` changes no decision a mismatch does not already force, and the printed `reset-failed` re-arms a watcher that fails again on the same mismatch. Report it, with the remedy, only when there is no version finding.
Assumption: every NVIDIA userspace change goes through `-t update`, not unattended-upgrades. Checked by the orchestrator: `zgrep -l nvidia /var/log/unattended-upgrades/*` is empty on `claude`; on `workstation` the one hit (July) is a kernel upgrade whose only NVIDIA effect was a DKMS module rebuild, with no userspace change.
Disposition: Addressed (operator, 2026-11-09) — Problem text corrected; `cdi-failed` reported only without a version finding, and no `systemctl` call is made with one.

### Ergonomics

Finding: Same false premise, with the mechanism: the service runs `nvidia-smi -L`, which fails on a mismatch, so the start limit trips. With a mismatch the remedy is "reboot", not `reset-failed`. Standalone, `reset-failed` leaves the path unit `inactive`, not watching, so the remedy also needs `systemctl start nvidia-cdi-refresh.path`. Minor: with apt's flag present the summary would print "reboot required" twice.
Assumption: a failed `nvidia-cdi-refresh.service` is always a symptom of a mismatch. Checked by the orchestrator: since the 2026-10-11 boot both hosts' journals for the two units hold only `nvsandboxutils` warnings, no failure with matching versions; older boots hold no entries for these units. Unsettled for older history, which is why the standalone case stays.
Disposition: Addressed (operator, 2026-11-09) — standalone remedy adds `start`; mismatch remedy is the reboot; the NVIDIA reason folds into one "reboot required" note.

### Risk

Finding: No load-bearing issue: report-only, no `set -e` in either file, probes cheap (`lspci -nn` 18 ms). Minor: `load_mocks` does not set `_OVERRIDE_NVIDIA_GPU_PRESENT`, so if the GPU gate ran before the libcuda link, existing doctor and update tests on GPU hosts would run the real `lspci`; check the link first.
Assumption: the update summary assumes the CDI unit is already `failed` when the apt line is built; the start-limit trip may land after apt returns. Unsettled (the workstation's journal for that boot holds no entries for the units), and made moot by the revision: the update line's reboot reason keys off the version files apt itself changes, which are in place when apt returns.
Disposition: Addressed (operator, 2026-11-09) — R2 checks the libcuda link before `_nvidia_gpu_present` and never calls it without one.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.
