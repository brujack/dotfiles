# NVIDIA driver state check: module/userspace mismatch and failed CDI refresh

- **Date:** 2026-11-09
- **Repo:** dotfiles
- **Backlog row closed:** "An nvidia userspace change without a reboot breaks GPU containers and disables CDI refresh, and nothing reports it"
- **Measurements:** `ai-config/docs/knowledge/dotfiles-apt-upgrade-hazards.md` §4
- **Approved:** 2026-11-09, operator: "Approved"

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
   A fourth gate follows: when the module version file
   (`${_NVIDIA_MODULE_VERSION_FILE:-/sys/module/nvidia/version}`) exists but
   `_nvidia_loaded_version` fails (unreadable, or not a dotted version), it prints nothing,
   since "could not read a version" is not "no module". Otherwise its first line is always
   exactly one version line, so a host whose gates pass is never silent:

   - `mismatch <loaded> <installed>` when `_nvidia_loaded_version` succeeds and its value
     with dashes turned back to dots differs from the userspace version;
   - `not-loaded <installed>` when the module version file does not exist;
   - `ok <version>` when the two versions are equal.

   Only after `ok` does it read the units, printing for each of `nvidia-cdi-refresh.path` and
   `nvidia-cdi-refresh.service`, in that order, `cdi-failed <unit>` when its `ActiveState` is
   `failed` and `cdi-unknown <unit>` when the read exits non-zero. After `mismatch` or
   `not-loaded`, `systemctl` is not called at all: the service runs `nvidia-smi -L`, which
   fails in both states, and a mismatch's reboot also clears the unit. Read with
   `"${_SYSTEMCTL_BIN:-systemctl}" show -P ActiveState <unit>`, one property per call
   (`systemctl show` prints multiple `-P` values in its own property order, not the
   argument order). A missing unit reports `inactive` with exit 0, so it needs no special
   case.

   Empty output means a gate failed; it returns 0 in every case.

3. **`_doctor_check_nvidia_driver`** (`lib/helpers.sh`), called from `run_doctor` directly
   after `_doctor_check_flatpak_gl`. Prints nothing when `_nvidia_driver_state` prints
   nothing (a gate failed); otherwise a `NVIDIA driver:` header, then:

   - `mismatch`: `doctor_fail` naming both versions and saying `nvidia-smi`, GPU containers
     and the CDI refresh fail until a reboot, and that the reboot is the remedy.
   - `not-loaded`: `doctor_warn` "nvidia module not loaded (userspace <v> installed): reboot
     if the driver was just installed, otherwise check `dkms status`". It does not assert a
     reboot fixes it: a DKMS build that failed for a new kernel produces the same state, and
     there the reboot caused it.
   - `cdi-failed`: `doctor_fail` naming the unit, then prints the remedy line
     `    sudo systemctl reset-failed nvidia-cdi-refresh.path nvidia-cdi-refresh.service && sudo systemctl start nvidia-cdi-refresh.path`
     once, however many units failed. `reset-failed` alone leaves the path unit inactive
     rather than watching, hence the `start`. The remedy is printed, never run.
   - `cdi-unknown`: `doctor_warn` "cannot read <unit> state".
   - `ok <v>` with no `cdi-failed` and no `cdi-unknown` line:
     `doctor_pass "nvidia module <v> matches userspace; CDI refresh not failed"`. With any
     `cdi-failed` or `cdi-unknown` line: `doctor_pass "nvidia module <v> matches userspace"`,
     beside that line's FAIL or WARN, so the PASS never states a unit state it did not read
     or that is failed.

4. **`-t update` apt line** (`lib/update_summary.sh`, `apt` case). A `mismatch` becomes the
   reason `nvidia <loaded> loaded, <installed> installed` inside the line's single reboot
   note, whether or not apt wrote its flag: with apt's flag and its `.pkgs` list the note
   reads `— reboot required (<pkgs>; <nvidia reason>)`; with the flag and no list, or with
   no flag, `— reboot required (<nvidia reason>)`. "reboot required" never appears twice on
   the line. A `not-loaded` appends `— nvidia module not loaded (<installed> installed)`,
   outside the reboot note. Each `cdi-failed` appends `— <unit> failed (see -t doctor)`.
   `ok` and `cdi-unknown` add nothing. Reports only.

### Data flow

`/sys/module/nvidia/version` and the `libcuda.so.1` link feed the version comparison;
`systemctl show` feeds the unit check; `_nvidia_driver_state` turns them into finding lines;
doctor and the update summary format the same lines. No state is stored.

### Error handling

An unreadable or malformed version input closes a gate, so the host gets no section and no
summary text rather than a false FAIL; a host with no GPU or no userspace is the same. An
unreadable unit state is reported as `cdi-unknown` (a doctor WARN), never folded into a PASS.

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

Cases for `_nvidia_driver_state`: versions match (exactly `ok 615.71.09`); mismatch; module
file absent (`not-loaded`); module file malformed and module file unreadable (each
empty output, with a valid link); no libcuda link; a regular file instead of a link; a
malformed suffix; no GPU;
`LINUX` unset; path unit failed; service unit failed; both failed; unit missing (`inactive`,
output exactly `ok <v>`); `systemctl` exit non-zero with the unit listed as `failed` in the
state file (output `cdi-unknown`, never `cdi-failed`). Every case asserts the exact output.
The empty-output cases (no link, regular file, malformed suffix, no GPU, `LINUX` unset)
each seed module `610.57.04` and, where a link exists, `libcuda.so.615.71.09`, so the case
would print a `mismatch` if its own gate did not close; a function that prints nothing
fails every case that expects `ok` or a finding. A replay of the 2026-10-11 shape (module `610.57.04`, link
`libcuda.so.615.71.09`, path unit `failed`) asserts the output is exactly
`mismatch 610.57.04 615.71.09` and that the `systemctl` stub recorded no call. A no-link case
redefines `_nvidia_gpu_present` in the test as a function that records its call, and
asserts the output is empty and no call was recorded.

Doctor and update-summary tests assert the exact rendered text for one mismatch, one
not-loaded (no "reboot required" on the update line), one cdi-failed (remedy printed once
for two failed units), one cdi-unknown (WARN plus the PASS without "CDI refresh not
failed"), one `ok` with one cdi-failed (FAIL plus the PASS without "CDI refresh not
failed") and the full PASS line, plus the no-GPU case producing no section and no summary
segment. Update-summary cases cover
the three reboot-note shapes: apt flag with `.pkgs`, apt flag without, and no apt flag, each
with a mismatch, asserting "reboot required" appears exactly once.

## Requirements

- **R1.** `_nvidia_userspace_version` prints the version suffix of the `libcuda.so.1` link target (read through `_NVIDIA_LIBCUDA`, default `/usr/lib/x86_64-linux-gnu/libcuda.so.1`) when it matches `^[0-9]+(\.[0-9]+)+$`, and returns 1 printing nothing when the path is not a symlink or the suffix does not match.
- **R2.** `_nvidia_driver_state` prints nothing unless, checked in this order, `LINUX` is set, `_nvidia_userspace_version` succeeds and `_nvidia_gpu_present` succeeds; it does not call `_nvidia_gpu_present` when `_nvidia_userspace_version` fails; and it also prints nothing when the module version file (`_NVIDIA_MODULE_VERSION_FILE`) exists but `_nvidia_loaded_version` fails.
- **R3.** When its gates pass, `_nvidia_driver_state`'s first line is exactly one of `mismatch <loaded> <installed>` (the loaded module version, dashes turned to dots, differs from the userspace version), `not-loaded <installed>` (the module version file does not exist) or `ok <version>` (the two are equal).
- **R4.** Only after `ok`, `_nvidia_driver_state` reads `nvidia-cdi-refresh.path` then `nvidia-cdi-refresh.service` with one `systemctl show -P ActiveState <unit>` call each through `_SYSTEMCTL_BIN`, printing `cdi-failed <unit>` when the state is `failed` and `cdi-unknown <unit>` when the call exits non-zero; after `mismatch` or `not-loaded` it makes no `systemctl` call.
- **R5.** `run_doctor` calls `_doctor_check_nvidia_driver` directly after `_doctor_check_flatpak_gl`; it prints no section on empty output, FAILs on `mismatch` and `cdi-failed`, WARNs on `not-loaded` (naming `dkms status` and not asserting a reboot fixes it) and on `cdi-unknown`, and PASSes on `ok`, with the PASS text claiming "CDI refresh not failed" only when no `cdi-failed` or `cdi-unknown` line was printed.
- **R6.** On any `cdi-failed` finding doctor prints the remedy `sudo systemctl reset-failed nvidia-cdi-refresh.path nvidia-cdi-refresh.service && sudo systemctl start nvidia-cdi-refresh.path` exactly once, and prints no `systemctl` remedy for a `mismatch` or `not-loaded` finding.
- **R7.** The `-t update` apt summary line carries a `mismatch` as a reason inside a single "reboot required" note, a `not-loaded` as `— nvidia module not loaded (<installed> installed)` outside that note, and each `cdi-failed` as `— <unit> failed (see -t doctor)`, in the forms given in Design component 4, whether or not `/var/run/reboot-required` exists; it never contains "reboot required" twice, and `ok` or `cdi-unknown` add nothing.
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

### Round 2 (all three lenses, re-reviewed at `f3369e22`)

- Goal-fit (`f3369e22`): a healthy host and a failed gate both printed nothing and returned 0, so doctor could not tell when to print its PASS, and a no-op `_nvidia_driver_state` passed all 8 empty-output cases (present since `571c53c9`; round 1 missed it). Assumption (driver changes bypass `-t update`, so the update line adds little): refuted by the orchestrator; the 2026-10-08 615 switch on `claude` was nala `full-upgrade` at 11:56:17 then `autoremove` at 11:56:19, the `-t update` apt step. Disposition: Addressed (operator, 2026-11-09) — a host whose gates pass always prints one version line, `ok <version>` on a match; the gate cases seed a mismatch so each tests its own gate.
- Ergonomics (`f3369e22`): `not-loaded` asserted a reboot fixes it, but a failed DKMS build for a new kernel gives the same state, caused by the reboot, so every `-t update` would print "reboot required" indefinitely; the update-line `cdi-failed` segment had no pointer to an action. Assumption (`not-loaded` is always transient): unseen and plausible; DKMS shows `nvidia/615.71.09 installed` for kernels 7.0.0-42 and 7.0.0-43 on both hosts, and the workstation has no failed `make.log`. Disposition: Addressed (operator, 2026-11-09) — `not-loaded` wording is neutral and names `dkms status`, and sits outside the reboot note; `cdi-failed` segments end `(see -t doctor)`.
- Risk (`f3369e22`): the PASS claimed "CDI refresh not failed" after a unit read had exited non-zero and been skipped; the non-zero-exit test could not discriminate unless its fixture listed the unit as `failed`. Assumption (the `libcuda.so.1` link flips at unpack, not by a deferred step): settled; `dpkg -S` shows `libnvidia-compute-615` ships the link. Disposition: Addressed (operator, 2026-11-09) — a failed read prints `cdi-unknown <unit>`, a doctor WARN, and the PASS drops its CDI claim; the test lists the unit as `failed` while the stub errors.

### Round 3 (scoped Risk lens on the round-2 revision, `7a500430`)

- Risk (`7a500430`): `_nvidia_loaded_version` returns 1 for an absent, unreadable or malformed module file, and R3 mapped all three to `not-loaded`, so a loaded module with an unreadable version file would be reported as not loaded, contradicting Error handling; minor, no PASS shape was pinned for `ok` with a `cdi-failed`. Assumption: none uncertain left (link shipped by the package, `systemctl` exit codes probed, unattended path checked). Disposition: Addressed (operator, 2026-11-09) — `not-loaded` only when the module file does not exist; an existing file that fails to read or parse closes the gate (R2), with tests for both; any `cdi-failed` or `cdi-unknown` line drops the PASS's CDI claim, with a test for `ok` plus `cdi-failed`. Review stops here: the finding was mechanical, the fix adds no mechanism, and the lens had no uncertain assumption left; the next instrument is Phase 2's first red test.
