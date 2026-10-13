# Flatpak update section and NVIDIA GL check

- **Date:** 2026-10-12
- **Status:** Spec
- **Backlog row:** "**Next spec:** flatpak is install-only; no update, unused-runtime prune, or GL/driver match check"

## Problem

`_install_ubuntu_gui_tools` (`lib/linux_ubuntu.sh`) installs Steam from Flathub once, on
`HAS_FLATPAK` hosts (`claude` and `workstation`, profile `linux_workstation`). Nothing
afterwards touches flatpak: `-t update` has no flatpak section and `doctor` has no flatpak
check (`grep -n -i flatpak lib/*.sh` finds only the install block).

Measured 2026-10-11, before any hand repair:

- `workstation` ran only `org.freedesktop.Platform.GL.nvidia-580-159-03` against a loaded
  host driver of 615.71.09 (`/sys/module/nvidia/version`). Steam therefore had no GL
  extension for the running driver.
- `claude`'s Steam had no NVIDIA GL extension at all.
- Both carried a dead 25.08 runtime set beside the live one: 10 refs on `claude`, 11 on
  `workstation`.

Both boxes were repaired by hand the same day. The repair established three facts the
design rests on (all measured on those two boxes, flatpak 1.16.6, system installation;
neither has a `--user` installation):

1. **`flatpak update` pulls the GL extension for the loaded driver by itself.** On
   `workstation`, `sudo -n flatpak update -y --noninteractive --system` returned 0 and
   installed `GL.nvidia-615-71-09` and `GL32.nvidia-615-71-09` beside the stale 580 pair.
   On `claude`, which had no NVIDIA GL at all, the same command installed the 615 pair.
   No other step was needed. The mismatch existed only because nothing ever ran
   `flatpak update`.
2. **`flatpak uninstall --unused` does not remove a stale `GL.nvidia-*`.** Flatpak counts
   every `GL.nvidia-*` and `GL32.nvidia-*` as used by Steam ("Info: applications using
   the extension org.freedesktop.Platform.GL.nvidia-580-159-03 branch 1.4:
   com.valvesoftware.Steam"). The 580 pair had to be removed by name. Each driver series
   bump therefore leaves another stale pair behind (GL plus GL32, ~450 MB each).
   `--unused` did remove the dead 25.08 set: 10 refs on `claude`, 11 on `workstation`.
   Qualified 2026-10-12: `flatpak update` itself removes GL extensions for drivers outside
   its active list. Running it on `claude` with `FLATPAK_GL_DRIVERS=nvidia-999-99-99`
   uninstalled `GL.default` and the 615 pair (a plain `flatpak update` restored them). Why
   the 580 pair survived the 2026-10-11 update is not established; the likeliest cause is
   that it hung off the 25.08 Platform, which that update did not reconsider.
   Source note, flatpak 1.16.6, read 2026-10-12: the live 26.08 Platform metadata declares
   `autoprune-unless = active-gl-driver` on its `GL` extension group, and Steam's metadata
   declares it on its `GL32` group. `find_used_refs` (`common/flatpak-dir.c`) does not count an auto-pruned
   related ref as used. A plain `flatpak update` with no ref arguments sets
   `include_unused_uninstall_ops` (`app/flatpak-builtins-update.c`), so
   `add_uninstall_unused_ops` (`common/flatpak-transaction.c`) removes every unused,
   auto-pruned ref. That is the mechanism behind the probe above, and it means
   `flatpak update` removes an inactive driver's GL pair by itself under the current
   metadata. Why the 580 pair survived on 2026-10-11 remains unproven: the 25.08 refs
   installed then are gone, so their metadata cannot be read.
3. **flatpak 1.16 has no dry run for `uninstall`.** `--assumeno` is rejected with
   `error: Unknown option --assumeno`, so any listing must come from `flatpak list`.

## Design

### 1. Shared helpers (`lib/linux_shared.sh`, beside `update_snap_packages`)

- `_nvidia_loaded_version` reads the file named by `_NVIDIA_MODULE_VERSION_FILE`
  (default `/sys/module/nvidia/version`). It accepts only `^[0-9]+(\.[0-9]+)+$` and prints
  the value in flatpak's ref form, dots replaced by dashes (`615.71.09` -> `615-71-09`).
  An absent, unreadable, empty or non-matching file returns 1 and prints nothing: the
  nvidia module is not loaded (no GPU, nouveau, or a driver installed but not yet
  rebooted into).
- `_flatpak_nvidia_gl_refs` prints one line per installed system runtime whose
  application id matches `^org\.freedesktop\.Platform\.GL(32)?\.nvidia-`, in
  `application/arch/branch` form, read from
  `flatpak list --system --runtime --columns=application,arch,branch`. A failed
  `flatpak list` returns 1. Measured on `claude` 2026-10-12: off a tty the output is
  tab-separated with no header line, and it also lists `org.freedesktop.Platform.VAAPI.nvidia`
  and `VAAPI.nvidia.i386`, which the pattern must not match.
- `_flatpak_has_apps` returns 0 when `flatpak list --system --app --columns=application`
  prints at least one line, 1 when it prints none, and 2 when `flatpak list` fails.

All three are shared by the update section and the doctor check, so the two read the
same state.

### 2. `update_flatpak_packages` and the `flatpak` update section

In order:

1. `sudo flatpak update -y --noninteractive --system`. Non-zero returns 1. With no ref
   arguments, flatpak itself also removes every unused runtime marked for auto-pruning.
   That includes each `GL` / `GL32` extension for a driver other than the active one
   (Fact 2, source note). This design removes nothing by name.
2. `sudo flatpak uninstall -y --noninteractive --system --unused`. Non-zero returns 1.
   This catches unused runtimes that are not auto-pruned, such as the dead 25.08 set of
   Fact 2.
3. Missing-GL check, only when `_nvidia_loaded_version` succeeds. It reads
   `_flatpak_nvidia_gl_refs` and `_flatpak_has_apps`; a failed list or `_flatpak_has_apps`
   rc 2 returns 1. When an app is installed and no
   `org.freedesktop.Platform.GL.nvidia-<loaded>` ref of any arch is installed, the
   function prints
   `flatpak: no GL.nvidia-<loaded> installed for loaded driver <dotted version>; flatpak apps get no NVIDIA GL. Flathub may not publish it yet: re-run -t update later.`
   and returns 2. An empty or misparsed runtime list produces the same line, so a parsing
   defect surfaces as a WARN rather than an OK. `GL32` is not required: a host can run
   only 64-bit flatpaks.

`--unused` removes any runtime that no installed app uses, including one an operator
installed deliberately (an SDK, say). Neither box has one: after the 2026-10-11 repair
every remaining runtime is Steam's. A runtime to keep is protected with flatpak's own
`flatpak pin <ref>`, which `--unused` honours; this design adds no keep-list of its own.

When the nvidia module is not loaded (no reboot yet into an installed driver, or a
failed DKMS build for a new kernel), flatpak's active driver list holds only `default`
and `host`, so step 1 auto-prunes every `GL*.nvidia-*` ref. The section still reports OK
(R6) and doctor stays silent (R9). Nothing is lost that the host could use: no NVIDIA GL
extension can be mounted without the module, and the next `-t update` after the module
loads downloads the pair again (~900 MB).

Step 1 can also rebase an app whose branch is end-of-life onto its successor, since it
runs with `-y --noninteractive`. That is flatpak's own update behaviour, not something
this code does by name (N2).

Known limitation: a root `--system --unused` cannot see `--user` installations, so it can
remove a system runtime that a `--user` app needs. Neither box has a `--user` installation
(0 refs on both, 2026-10-11). The design accepts this rather than reading `--user` state
(N1).

Open question, settled during `writing-plans` before any task is dispatched: does a plain
`flatpak uninstall --system --unused` succeed (deferring deletion) when a runtime it
removes is in use by a running Steam, or does it refuse? The same question applies to the
auto-prune removals inside step 1. Settle it by reading `flatpak_dir_undeploy` and the
uninstall transaction in the flatpak 1.16.6 source, not by a live probe. If it refuses,
the step handling changes before Phase 2.

Return: 0 clean, 1 failure, 2 warning. A failure in any step returns before later steps
run. The only warning is step 3's, printed last, so it is inside the 10-line tail that
`_update_write_detail_from_err` keeps.

`run_update` gains a `flatpak` section directly after `snap`, inside the same
`UPDATE_PKGS`/`_run_all` and `LINUX` gates. It runs when `command -v flatpak` succeeds,
and otherwise records `_update_skip "flatpak" "flatpak not installed on this host"`. It
mirrors `cargo-tools`' rc-2 handling: `_update_record_end "flatpak" "$(( rc == 2 ? 0 : rc ))"`,
then on rc 2 `_update_warn "flatpak" "no NVIDIA GL extension for the loaded driver — see detail"`
plus `_update_write_detail_from_err`. `_UPDATE_SECTION_ORDER` gains `flatpak` directly
after `snap`. Non-Linux and flag-not-set paths record the same skip reasons `snap` uses.

Ordering note: `apt` runs before `flatpak`, so a run that upgrades the driver still sees
the previously loaded module. flatpak then keeps the old GL extension, which is the one
in use until the reboot; the next run after the reboot installs the new one and flatpak
auto-prunes the old.

Operator notes:

- `--dry-run` does not skip this section. It updates and removes runtimes as it would
  otherwise, like the `apt`, `snap` and `brew` sections: `--dry-run` guarantees only that
  nothing is written to another machine.
- Download size: each NVIDIA GL extension is ~450 MB (Fact 2), so a driver point release
  costs ~900 MB for the pair, and a Platform branch bump adds its own runtime set. The
  output goes through `tee` with no progress bar.
- The section makes two `sudo` calls. A long step 1 can outlive the sudo timestamp, and
  the next call then prompts for a password. This is the same exposure the run already
  has between `apt` and `snap`; the design adds no mitigation.

### 3. Doctor: `_doctor_check_flatpak_gl` (`lib/helpers.sh`)

Silent (`return 0`, no output) unless all hold: `LINUX` set, `command -v flatpak`
succeeds, `_flatpak_has_apps` returns 0, and `_nvidia_loaded_version` succeeds. Otherwise
it prints a `Flatpak NVIDIA GL:` heading and:

- `doctor_warn` when `GL.nvidia-<loaded>` is not installed (any arch), naming the loaded
  driver and both causes:
  `no GL.nvidia-<loaded> for loaded driver <dotted>: run ./setup_env.sh -t update; if it already ran since the reboot, Flathub does not publish it yet and nothing local fixes it`.
  This warning stays until Flathub publishes the extension, which is correct: Steam has no
  matching GL until then. `GL32` is not required: a host can run only 64-bit flatpaks.
- `doctor_warn` once per installed `GL.nvidia-*` or `GL32.nvidia-*` ref whose version is
  not the loaded one, any arch, with a pastable remedy line:
  `stale <application/arch/branch> (driver <version> not loaded); remove with: sudo flatpak uninstall -y --noninteractive --system <application/arch/branch>`.
  Removing it loses nothing for the running driver: the Platform metadata's `GL` group
  and Steam's `GL32` group each declare `enable-if = active-gl-driver`, so flatpak never
  mounts an inactive driver's extension.
  Booting back into the old driver costs one re-download at the next `-t update`. In
  normal operation this never fires, because step 1's auto-prune removes such refs; it
  exists to catch a repeat of the unexplained 2026-10-11 survival of the 580 pair.
- `doctor_pass` when neither applies.
- `doctor_warn` when `_flatpak_nvidia_gl_refs` fails ("cannot list flatpak runtimes") or
  `_flatpak_has_apps` returns 2.

It never calls `doctor_fail` (Steam still runs, on software GL) and never runs a mutating
flatpak command: the remedy is printed for the operator to run. It is wired into
`run_doctor` beside `_doctor_check_conffile_dist`. Its gap-covering value is the window
between a driver bump plus reboot and the next `-t update`, plus the stale-ref detection.

### 4. Comment fixes carried from dotfiles#334's code review

- `lib/linux_ubuntu.sh`: the header comment above `_install_ubuntu_nvidia` joined two
  sentences onto one ~130-character line; re-wrap it to the surrounding width.
- `tests/setup_env/linux_ubuntu.bats`, `_nvidia_dpkg_shim` comment: it claims real dpkg
  "always prints a header". Real `dpkg -l <unknown-name>` prints only
  `dpkg-query: no packages found matching ...` and exits 1. Reword to say the shim prints
  a header and per-package rows and does not mimic the no-match case.
- `tests/setup_env/linux_ubuntu.bats`, `setup()` SHIM_DIR comment: name the dpkg shim that
  `_nvidia_dpkg_shim` writes lazily.

### Testing

- New `tests/mocks/flatpak`, recording every call to `MOCK_CALLS_FILE`. `list` prints
  `MOCK_FLATPAK_LIST_RUNTIME` for `--runtime` and `MOCK_FLATPAK_LIST_APP` for `--app`.
  `MOCK_FLATPAK_FAIL_SUBCMD` fails one subcommand (`update`, `uninstall`, `list`).
  `MOCK_FLATPAK_FAIL_ARGS` fails only a call whose argv contains the value, so
  `list --app` and `list --runtime` can fail separately.
- `_NVIDIA_MODULE_VERSION_FILE` points at a fixture in every test. `load_mocks` exports it
  to a nonexistent path by default, because `claude` and `workstation` have a real
  `/sys/module/nvidia/version` and a test would otherwise read the host's driver.
- `tests/setup_env/linux_ubuntu.bats` sets its own SHIM_DIR `flatpak` shim; it is not
  changed.
- Runtime-list fixtures are captured from real `flatpak list --system --runtime
  --columns=application,arch,branch` output on `claude` (tab-separated, no header,
  including the `VAAPI.nvidia` refs) and committed under `tests/fixtures/flatpak/`.
  Doctor's stale-ref cases are edits of that captured file, not hand-typed lists.
- One host-gated, read-only test runs the real `flatpak list` (mocks directory stripped
  from `PATH`) through `_flatpak_nvidia_gl_refs`. It skips where flatpak is absent, as on
  CI. It asserts that every output line matches
  `^org\.freedesktop\.Platform\.GL(32)?\.nvidia-[0-9-]+/[^/]+/[^/]+$`, that no `VAAPI` ref
  appears, and, when `/sys/module/nvidia/version` is readable, that the output contains
  the loaded version's `GL.nvidia-` ref.

## Requirements

- **R1.** `_nvidia_loaded_version` prints `615-71-09` for a file containing `615.71.09\n`, and returns 1 with no output for an absent file, an empty file, and the value `615.71.09-beta`.
- **R2.** `_flatpak_nvidia_gl_refs` prints only `org.freedesktop.Platform.GL.nvidia-*` and `org.freedesktop.Platform.GL32.nvidia-*` refs from `flatpak list --system --runtime --columns=application,arch,branch`, as `application/arch/branch`, and returns 1 when `flatpak list` fails.
- **R3.** `update_flatpak_packages` runs `sudo flatpak update -y --noninteractive --system` first, and returns 1 without any `uninstall` call when it fails.
- **R4.** Withdrawn in round 2: `update_flatpak_packages` no longer removes GL refs by name (see R16).
- **R5.** Withdrawn in round 2, with the per-group keep rule it described.
- **R6.** With the loaded version unknown, `update_flatpak_packages` runs no missing-GL check, prints no warning, and returns 0 when update and `--unused` succeed.
- **R7.** `update_flatpak_packages` runs `sudo flatpak uninstall -y --noninteractive --system --unused` after the update, and returns 1 without running the missing-GL check when it fails.
- **R8.** `run_update` records a `flatpak` section directly after `snap` in `_UPDATE_SECTION_ORDER`; rc 0 reports OK, rc 2 reports WARN with the function's output in the detail, rc 1 reports FAIL, and no `flatpak` binary reports SKIP "flatpak not installed on this host".
- **R9.** `_doctor_check_flatpak_gl` prints nothing when `LINUX` is unset, flatpak is absent, no flatpak app is installed, or the loaded version is unknown.
- **R10.** `_doctor_check_flatpak_gl` warns when `GL.nvidia-<loaded>` is missing, with a message naming both `-t update` and Flathub not yet publishing it; warns once per installed `GL.nvidia-*` / `GL32.nvidia-*` ref whose version is not the loaded one, printing `sudo flatpak uninstall -y --noninteractive --system <ref>` for that ref; passes when neither applies; warns when the runtime list or the app list fails; and never fails.
- **R11.** `run_doctor` calls `_doctor_check_flatpak_gl`.
- **R12.** The three dotfiles#334 comment fixes in Design §4 are applied.
- **R13.** With loaded version `615-71-09` and at least one flatpak app installed, `update_flatpak_packages` returns 2 and prints the missing-GL line when no `GL.nvidia-615-71-09` ref is installed after the update and `--unused` steps, including when the runtime list contains no `GL*.nvidia-*` ref at all; with no app installed it prints no such line.
- **R14.** Withdrawn in round 2, with the (family, arch) grouping it described.
- **R15.** With the loaded version known, `update_flatpak_packages` returns 1 when `_flatpak_nvidia_gl_refs` fails or `_flatpak_has_apps` returns 2.
- **R16.** The only `flatpak uninstall` call `update_flatpak_packages` makes is the `--unused` one; it never names a ref.
- **V1.** On `claude` and `workstation`, `./setup_env.sh -t update` reports `flatpak` OK and `-t doctor` reports the flatpak GL check PASS. Both hosts hold only the loaded pair, so V1 shows the section runs clean; doctor's stale detection is covered by bats against captured real output.
- **V2.** `make test` passes, and CI bash coverage stays at or above the 91% floor.
- **V3.** Post-merge, not a merge gate: after the next NVIDIA point release is installed and booted on either host, `-t update` leaves only that release's `GL`/`GL32` pair in `flatpak list --system --runtime` (flatpak's own auto-prune), and `-t doctor` reports PASS. Recorded in a follow-up commit when it happens.
- **N1.** No `--user` flatpak installation is read, updated or uninstalled.
- **N2.** This change installs or removes no flatpak app by name, and the Steam install path in `_install_ubuntu_gui_tools` is unchanged. flatpak's own update may rebase an end-of-life app (Design §2).
- **N3.** No code in this change uninstalls a flatpak ref by name; doctor's remove command is printed, never run.
- **N4.** `_doctor_check_flatpak_gl` never calls `doctor_fail` and never runs a mutating flatpak command.

## Multi-Lens Review

Reviewed at commit: `7d0df709` (Step 7 self-review commit, before Step 8 dispatch)

Every reference in a round's blocks — step numbers, requirement numbers, section names — is frozen at the commit that round reviewed; later revisions renumbered the steps and withdrew R4, R5 and R14.

### Goal-Fit

Finding: Worth building; driver churn is higher than the spec says (workstation's dpkg log: 610 installed 2026-09-15, upgraded 2026-10-02, 615 installed 2026-10-08; Flathub already lists `GL.nvidia-615-78-08`), and every point release is a new ref name, so stale pairs accrue per point release, not per series. Load-bearing gap: the update section reports OK when `GL.nvidia-<loaded>` is absent and no other version is installed (§2 step 2, "a family with no refs at all is left alone, silently") — exactly `claude`'s original defect, and also what an empty or misparsed `flatpak list` produces. R4, R6, R7, R8-OK and V1 all pass on an empty list; only doctor would notice. Fix: warn (rc 2) whenever the loaded version is known, an app is installed, and `GL.nvidia-<loaded>` is absent after step 1. Doctor (§3) passes the reads-it test only marginally once that lands. Shared derivation means doctor cannot catch a helper defect.
Assumption: `sudo flatpak update` keeps pulling `GL.nvidia-<loaded>` for every point release at the moment the update runs. Confirm after the next point release (615.78.08) plus reboot: `-t update`, then `flatpak list --system --runtime --columns=application | grep "nvidia-$(tr . - </sys/module/nvidia/version)"` shows GL and GL32.
Disposition: Addressed (user, 2026-10-12) — §2 step 4 and R13 warn (rc 2) when the loaded version is known, an app is installed and `GL.nvidia-<loaded>` is absent, which also covers an empty or misparsed list.

### Ergonomics

Finding: (1) §3/R10: in the Flathub-lag state doctor prescribes `-t update`, which cannot fix it; doctor and update then point at each other on every run. (2) §2 does not state `--dry-run` behaviour; step 2 and 3 delete ~900 MB+ and an operator may not expect that under `--dry-run`. (3) No run-time/download-size note for a runtime bump in an unattended run. (4) Three separate `sudo` calls; a long step 1 can outlive the sudo timestamp and hang step 2 on a prompt (same exposure as apt-then-snap today; say so). (5) The `_update_warn` reason text is unspecified. (6) V1 cannot falsify the prune: both hosts hold only the 615 pair, so a prune that does nothing reports OK. Premise verified: `flatpak --gl-drivers` -> `nvidia-615-71-09 / default / host`; Platform 26.08 metadata `[Extension org.freedesktop.Platform.GL]` has `download-if = active-gl-driver`, `autodelete = false`.
Assumption: `flatpak update` exits 0 when the active driver's GL extension is missing from Flathub; if non-zero, step 1 FAILs and the R5 WARN path is unreachable.
Assumption measured by the orchestrator, 2026-10-12 on `claude`: `sudo -n env FLATPAK_GL_DRIVERS=nvidia-999-99-99 flatpak update -y --noninteractive --system` returned **rc 0** with no error, confirming it. The probe was not read-only: it **uninstalled** `GL.default` (26.08, 26.08-extra), `GL.nvidia-615-71-09` and their GL32 counterparts, because they no longer matched the overridden driver list. A plain `flatpak update` restored all six within minutes. This shows `flatpak update` itself removes GL extensions for drivers not in its active list, which qualifies Fact 2: why the 580 pair survived the 2026-10-11 update is not established (likely it hung off the 25.08 Platform, which that update did not reconsider).
Disposition: Addressed (user, 2026-10-12) — (1) doctor's message names both causes; (2) `--dry-run` behaviour stated; (3) download-size note; (4) sudo-timestamp note; (5) WARN reason and printed lines specified; (6) V1 reworded, V3 added post-merge. Assumption measured (rc 0); Fact 2 qualified.

### Risk

Finding: Deletions fail toward keeping refs for every newly admitted input (table in the lens report: malformed version, unloaded module, apt-without-reboot, multiple installations all lose nothing; booting an older kernel costs one ~900 MB re-download). The risk is that the prune never meets real `flatpak list` output (tdd.md pitfall F): fixtures must be captured from real bytes (tab-separated, no header off-tty), plus one read-only host-gated R2 test parsing real output. (2) Doctor's warning can never clear in the R5 state (same as Ergonomics 1). (3) Families are keyed by application id, not arch; a stale ref under a second arch would be pruned with no same-arch replacement (latent: all refs measured `x86_64`). (4) `sudo flatpak uninstall --system --unused` as root may remove a system runtime that a future `--user` app depends on (latent: 0 `--user` refs on both boxes). Premise verified: `strings $(command -v flatpak)` contains `/sys/module/nvidia/version` and `FLATPAK_GL_DRIVERS`, so flatpak and `_nvidia_loaded_version` read the same source.
Assumption: plain `flatpak uninstall --system --unused` (no `--force-remove`) succeeds, deferring deletion, when a runtime it removes is still in use by a running Steam; if it refuses, R7 FAILs every `-t update` run while Steam is open. Settle by reading `flatpak_dir_undeploy` in the 1.16.6 source, or by running step 3 on a box with Steam running and a stale runtime present.
Disposition: Addressed (user, 2026-10-12) — (1) fixtures captured from real bytes plus a host-gated read-only test; (2) doctor's message states the warning holds until Flathub publishes; (3) grouping by (family, arch), R14; (4) `--user` stated as a known limitation. Steam-in-use assumption: settled by reading the flatpak 1.16.6 source during writing-plans, before dispatch.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.

## Multi-Lens Review — round 2

Reviewed at commit: `3271ecf4` (round-1 revision; all three lenses re-run, told round 1 is history)

### Goal-Fit (round 2, `3271ecf4`)

Finding: Worth building, but cut the stale-GL prune (§2 step 2, R4, R5, R14, doctor's per-ref stale warnings) unless shown necessary. Steps 1, 3 and 4 (update, `--unused`, missing-GL WARN) close both measured defects, which came from `flatpak update` never running. The prune rests on one unexplained observation (580 survived 2026-10-11); the spec's "hung off 25.08" explanation is refuted by the live 26.08 Platform metadata, which already relates `GL` branch `1.4`. Reads-it: update WARN persists in `~/.dotfiles-update.log` (ledger records no WARN); doctor is print-only and marginal; host test feeds `make test` via pre-push.
Assumption: `flatpak update` does not reliably remove a superseded `GL.nvidia-<old>`; settle by reading flatpak 1.16.6's related-ref/autoprune logic, or by V3 before building the prune.
Assumption checked by the orchestrator, 2026-10-12, flatpak 1.16.6 source plus live metadata on `claude`: refuted for the current install. Both the 26.08 Platform metadata and Steam's metadata declare `autoprune-unless = active-gl-driver` on the GL / GL32 extensions. `find_used_refs` (`common/flatpak-dir.c` ~16828) does not count an autoprune related ref as used. A plain `flatpak update` with no ref arguments sets `include_unused_uninstall_ops` (`app/flatpak-builtins-update.c` ~246), so `add_uninstall_unused_ops` (`common/flatpak-transaction.c` ~4981) removes every unused, autopruned ref with no "already unused" exclusion. That is the mechanism behind the round-1 probe. Why 580 survived 2026-10-11 remains unproven; the 25.08 refs installed then are gone, so their metadata cannot be read.
Disposition: Addressed (user, 2026-10-12) — prune, keep rule and arch grouping removed (R4, R5, R14 withdrawn; R16 added); the update relies on flatpak's own auto-prune, which the source read confirms. Doctor keeps stale detection and prints the remove command (user's choice over dropping it).

### Ergonomics (round 2, `3271ecf4`)

Finding: The WARN detail can lose the line that explains it: `_update_write_detail_from_err` (`lib/update_summary.sh:82-93`) keeps `tail -10` of the section output, and the step-2 "kept" line prints before step 3's `--unused` table (10-11 refs on a Platform bump). Fix: print collected warnings last, or build the detail from them; add a bats case with >=10 lines of `--unused` output. Reasoned from the helper, not measured. Premise verified: Flathub lists 610.43.02/.03, 610.57.04, 615.71.09, 615.78.08 while Ubuntu ships 615.71.09, so the WARNs should rarely fire unattended.
Assumption: Flathub keeps publishing `GL.nvidia-<ver>` before or with Ubuntu's `nvidia-driver-*-open`; check `apt-cache madison` and `flatpak remote-ls` on the day of the next driver bump.
Disposition: Addressed (user, 2026-10-12) — moot after the prune was removed: the only warning (step 3) now prints last, inside the 10-line detail tail.

### Risk (round 2, `3271ecf4`)

Finding: The keep branch (R5, R14) guards a deletion step 1 has already done: `flatpak update` removes GL extensions outside its active driver list, and that list comes from the same `/sys/module/nvidia/version`. In the Flathub-lag case step 1 removes the old pair before R5 "keeps" it, so the kept line is likely unreachable and step 4 fires instead. Step 1 can also EOL-rebase an app under `-y --noninteractive`, which N2 ("no flatpak app is installed or removed") cannot promise and no test can show. Step 2 deletes only by-name nvidia refs; step 3 is correct with zero apps. Arch grouping never splits anything on these hosts (all `x86_64`, branch `1.4`).
Assumption: step 1 leaves a stale pair in place when the new driver's extension is unavailable; settle in the flatpak source (`add_related`/autoprune for GL on a Platform with no pending commit).
Assumption checked by the orchestrator: see Goal-Fit round 2 — with current metadata, flatpak's own update autoprunes inactive-driver GL extensions, so the assumption is false for this install.
Disposition: Addressed (user, 2026-10-12) — keep branch removed with the prune; N2 narrowed to removals by name and the EOL rebase stated in Design §2.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.

## Multi-Lens Review — round 3

Reviewed at commit: `c40b0d7c` (round-2 revision; all three lenses re-run, told rounds 1-2 are history)

### Goal-Fit (round 3, `c40b0d7c`)

Finding: The value is §2 steps 1-2 and the section wiring. Reads-it: the step-3 missing-GL WARN fires only when Flathub has not published the extension, and its remedy ("re-run later") is what the operator does anyway; doctor missing-GL is stdout-only and closes itself at the next `-t update` (no cron or timer runs `setup_env.sh` on Linux); doctor stale-ref "never fires" by the spec's own account. Simpler path: ship steps 1-2 plus V3, add detection only if V3 shows stale pairs surviving. Note: this reverses round 1's Goal-fit, which asked for the missing-GL WARN because it is the only check that turns an empty or misparsed runtime list (and `claude`'s original no-GL state) into something other than OK.
Assumption: on a driver point release a plain `flatpak update` auto-prunes the previous pair; if the decision reads `autoprune-unless` only from the GL ref's parent Platform, a pair whose Platform branch changed escapes, which would explain 580 and predict recurrence at the next Platform bump. Settle by V3, or by reading `find_used_refs` for which metadata supplies the related refs.
Disposition:

### Ergonomics (round 3, `c40b0d7c`)

Finding: Doctor's missing-GL remedy is prose with a condition ("run ./setup_env.sh -t update; if it already ran ..."), not a pastable line, and the command it names runs every update section (apt can install another driver) to fetch one runtime. Fix: condition on its own line, then the bare command `sudo flatpak update -y --noninteractive --system` (or `./setup_env.sh -t update --pkgs-only`, `lib/helpers.sh:1399`); R10 should require the printed line. Verified: flatpak reads `/sys/module/nvidia/version` with the same dot-to-dash transform (`common/flatpak-utils.c:490`); the stale remove command is correct as typed (`ID/ARCH/BRANCH` accepted; `--noninteractive` implies `-y`); rc-2 mapping matches cargo-tools.
Assumption: the next driver bump plus reboot plus plain `flatpak update` removes the old pair; settled by V3.
Disposition:

### Risk (round 3, `c40b0d7c`)

Finding: Step 2 (`--unused`) is the only deletion not bounded by flatpak's own policy, and it buys only timing. `flatpak update` already removes unused refs that are EOL or auto-pruned (`common/flatpak-transaction.c:5050-5056`); `uninstall --unused` uses `FLATPAK_DIR_FILTER_NONE` (`app/flatpak-builtins-uninstall.c:348`) and removes any unpinned runtime root's `find_used_refs` does not see, including an operator's SDK and a runtime a `--user` app needs. Its one measured benefit, the dead 25.08 set, will be removed by step 1 once Flathub EOLs 25.08 (24.08 already reports End-of-life). Dropping step 2 and R7 removes the N1 hazard and the open Steam-running question for `--unused`. Also: a failed DKMS build leaves the module unloaded, so flatpak's active list holds only `default`/`host` and step 1 removes every `GL*.nvidia-*` ref while R6 reports OK and R9 keeps doctor silent; the cost is a re-download, worth one line. Wording: "both metadata files" declare the GL rule for one group each (Platform: GL; Steam: GL32). No R prescribes what an N forbids.
Assumption: 580 survived because of the 25.08 metadata, not a path that still counts a stale GL ref as used; settled by V3.
Disposition: `--unused` kept — Accepted (user, 2026-10-12, "Keep unused"). DKMS-unloaded note and the metadata-group wording fix — Addressed (user, "Fold in risks").

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.
