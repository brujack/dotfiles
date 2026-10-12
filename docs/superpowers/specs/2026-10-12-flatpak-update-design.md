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
  `flatpak list` returns 1.

Both are shared by the update section and the doctor check, so the two cannot disagree
about which refs are stale.

### 2. `update_flatpak_packages` and the `flatpak` update section

In order:

1. `sudo flatpak update -y --noninteractive --system`. Non-zero returns 1.
2. Stale-GL prune, decided per family. The two families are `GL` and `GL32`
   (`org.freedesktop.Platform.GL.nvidia-*` and `org.freedesktop.Platform.GL32.nvidia-*`);
   a ref's version is the text between `nvidia-` and the first `/`. Only when
   `_nvidia_loaded_version` succeeds:
   - A family whose `<family>.nvidia-<loaded>` ref is installed after step 1 has every
     other version of that family marked stale.
   - A family with no `<loaded>` ref installed, but with other versions installed, has
     nothing marked stale. The function prints
     `flatpak: no <family>.nvidia-<loaded> installed (Flathub may not have it yet); kept: <refs>`
     and will return 2 after step 3. Pruning that family would leave Steam with no NVIDIA
     GL of that width; the 64-bit and 32-bit extensions are published separately.
   - A family with no refs at all is left alone, silently.

   All stale refs across both families are removed with one
   `sudo flatpak uninstall -y --noninteractive --system <refs...>`, skipped when there are
   none. Non-zero returns 1.
   - Loaded version unknown: no prune, no message, continue. Nothing can be called stale
     without a reference version.
3. `sudo flatpak uninstall -y --noninteractive --system --unused`. Non-zero returns 1.

`--unused` removes any runtime that no installed app uses, including one an operator
installed deliberately (an SDK, say). Neither box has one: after the 2026-10-11 repair
every remaining runtime is Steam's. A runtime to keep is protected with flatpak's own
`flatpak pin <ref>`, which `--unused` honours; this design adds no keep-list of its own.

Return: 0 clean, 1 failure, 2 warning. A step-1 or step-2 failure returns before later
steps run.

`run_update` gains a `flatpak` section directly after `snap`, inside the same
`UPDATE_PKGS`/`_run_all` and `LINUX` gates. It runs when `command -v flatpak` succeeds,
and otherwise records `_update_skip "flatpak" "flatpak not installed on this host"`. It
mirrors `cargo-tools`' rc-2 handling: `_update_record_end "flatpak" "$(( rc == 2 ? 0 : rc ))"`,
then on rc 2 `_update_warn` plus `_update_write_detail_from_err`. `_UPDATE_SECTION_ORDER`
gains `flatpak` directly after `snap`. Non-Linux and flag-not-set paths record the same
skip reasons `snap` uses.

Ordering note: `apt` runs before `flatpak`, so a run that upgrades the driver still sees
the previously loaded module. The prune then keeps the old GL extension, which is the one
in use until the reboot; the next run after the reboot installs the new one and prunes
the old.

### 3. Doctor: `_doctor_check_flatpak_gl` (`lib/helpers.sh`)

Silent (`return 0`, no output) unless all hold: `LINUX` set, `command -v flatpak`
succeeds, `flatpak list --system --app` lists at least one application, and
`_nvidia_loaded_version` succeeds. Otherwise it prints a `Flatpak NVIDIA GL:` heading and:

- `doctor_warn` when `GL.nvidia-<loaded>` is not installed, naming the loaded driver and
  the remedy `./setup_env.sh -t update`. `GL32` is not required: a host can run only
  64-bit flatpaks.
- `doctor_warn` once per stale ref, naming it and the same remedy, using the update
  section's per-family rule: a ref is stale only when its family's `<loaded>` ref is
  installed. Otherwise doctor would prescribe an update that, correctly, keeps the ref.
- `doctor_pass` when neither applies.
- `doctor_warn` when `_flatpak_nvidia_gl_refs` itself fails ("cannot list flatpak
  runtimes").

It never calls `doctor_fail`: Steam still runs, on software GL. It is wired into
`run_doctor` beside `_doctor_check_conffile_dist`. Its gap-covering value is the window
between a driver bump plus reboot and the next `-t update`.

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
  `MOCK_FLATPAK_FAIL_ARGS` fails only a call whose argv contains the value, so the
  stale-ref uninstall and the `--unused` uninstall can fail separately.
- `_NVIDIA_MODULE_VERSION_FILE` points at a fixture in every test. `load_mocks` exports it
  to a nonexistent path by default, because `claude` and `workstation` have a real
  `/sys/module/nvidia/version` and a test would otherwise read the host's driver.
- `tests/setup_env/linux_ubuntu.bats` sets its own SHIM_DIR `flatpak` shim; it is not
  changed.

## Requirements

- **R1.** `_nvidia_loaded_version` prints `615-71-09` for a file containing `615.71.09\n`, and returns 1 with no output for an absent file, an empty file, and the value `615.71.09-beta`.
- **R2.** `_flatpak_nvidia_gl_refs` prints only `org.freedesktop.Platform.GL.nvidia-*` and `org.freedesktop.Platform.GL32.nvidia-*` refs from `flatpak list --system --runtime --columns=application,arch,branch`, as `application/arch/branch`, and returns 1 when `flatpak list` fails.
- **R3.** `update_flatpak_packages` runs `sudo flatpak update -y --noninteractive --system` first, and returns 1 without any `uninstall` call when it fails.
- **R4.** With loaded version `615-71-09`, `update_flatpak_packages` uninstalls, in one `sudo flatpak uninstall -y --noninteractive --system` call, every `GL.nvidia-*` ref other than `GL.nvidia-615-71-09` when that ref is installed, and every `GL32.nvidia-*` ref other than `GL32.nvidia-615-71-09` when that ref is installed; it never names a `*-615-71-09` ref and makes no such call when nothing is stale.
- **R5.** With the loaded version known, a family (`GL` or `GL32`) that has other versions installed but not `<family>.nvidia-<loaded>` has none of its refs uninstalled; `update_flatpak_packages` prints a line naming the family, the loaded version and the kept refs, still prunes the other family per R4, still runs the `--unused` uninstall, and returns 2.
- **R6.** With the loaded version unknown, `update_flatpak_packages` uninstalls no `GL*.nvidia-*` ref, prints no warning, and returns 0 when update and `--unused` succeed.
- **R7.** `update_flatpak_packages` runs `sudo flatpak uninstall -y --noninteractive --system --unused` last, and returns 1 when it or the stale-ref uninstall fails.
- **R8.** `run_update` records a `flatpak` section directly after `snap` in `_UPDATE_SECTION_ORDER`; rc 0 reports OK, rc 2 reports WARN with the function's output in the detail, rc 1 reports FAIL, and no `flatpak` binary reports SKIP "flatpak not installed on this host".
- **R9.** `_doctor_check_flatpak_gl` prints nothing when `LINUX` is unset, flatpak is absent, no flatpak app is installed, or the loaded version is unknown.
- **R10.** `_doctor_check_flatpak_gl` warns when `GL.nvidia-<loaded>` is missing, warns once per ref that R4 would uninstall (and for no other ref), passes when neither applies, warns when the runtime list fails, and never fails.
- **R11.** `run_doctor` calls `_doctor_check_flatpak_gl`.
- **R12.** The three dotfiles#334 comment fixes in Design §4 are applied.
- **V1.** On `claude` and `workstation`, `./setup_env.sh -t update` reports `flatpak` OK and `-t doctor` reports the flatpak GL check PASS.
- **V2.** `make test` passes, and CI bash coverage stays at or above the 91% floor.
- **N1.** No `--user` flatpak installation is read, updated or uninstalled.
- **N2.** No flatpak app is installed or removed; the Steam install path in `_install_ubuntu_gui_tools` is unchanged.
- **N3.** No GL extension other than `GL.nvidia-*` / `GL32.nvidia-*` is uninstalled by name.
- **N4.** `_doctor_check_flatpak_gl` never calls `doctor_fail` and never runs a mutating flatpak command.
