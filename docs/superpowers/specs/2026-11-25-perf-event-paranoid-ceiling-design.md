# perf_event_paranoid ceiling on the Linux development boxes

- **Status:** Draft
- **Requested by:** the math session (2026-11-24), for hardware counters (IPC, cache misses) on zeta runs
- **Operator decisions:** set the key to 2 (2026-11-24); drop the package half; sibling ceiling functions (approach B) (2026-11-25)

## Problem

`perf stat -e cycles,instructions true` fails as the normal user on `claude` and `workstation`:

```
>= 1: Disallow CPU event access
>= 2: Disallow kernel profiling
To make the adjusted perf_event_paranoid setting permanent preserve it
in /etc/sysctl.conf (e.g. kernel.perf_event_paranoid = <setting>)
```

`/proc/sys/kernel/perf_event_paranoid` reads `4` on both (measured 2026-11-25, both boxes). That is
the Ubuntu kernel's built-in default: `/usr/lib/systemd/systemd-sysctl --cat-config` on `claude`
lists no file setting the key, and `grep -rn perf_event` over `/etc/sysctl.conf`, `/etc/sysctl.d`,
`/usr/lib/sysctl.d` and `/run/sysctl.d` finds nothing (both measured on `claude` and `workstation`).

Value 2 lets an unprivileged user count events on processes it may ptrace, user space only. 1 adds
kernel events, 0 and below add CPU-wide access. The operator chose 2.

## Premise check: the install half is already done

The request also asked for `linux-tools-generic`. It is not needed.

- `perf` runs on both boxes; it is blocked only by the sysctl (the output above, both boxes).
- `linux-generic-hwe-26.04` 7.0.0-44.44, installed by `_install_ubuntu_base_packages` with
  `--install-recommends`, carries `Recommends: linux-tools-7.0.0-44-generic`, and
  `APT::Install-Recommends "1"` holds (measured on `claude`; `workstation`'s `linux-generic` carries
  the same Recommends).
- apt history on `claude` shows unattended-upgrade installing `linux-tools-<ver>-generic` as
  `automatic` with every kernel: -31, -34, -38, -42 and -44. dpkg logs on both boxes show
  `linux-tools-7.0.0-43-generic` installed 2026-11-06, so the request's "absent for the running
  -43 kernel" reading was wrong.

The operator dropped the package half. This spec covers only the sysctl.

## Why the existing sysctl step cannot be reused

`_sysctl_floor_step` and `_doctor_sysctl_floor` (inotify, kernel keys) only raise a value: they
persist `max(live, floor)` and apply when live is below the floor. This key needs the mirror: a
ceiling that persists `min(live, ceiling)`, never raising a lower conf or live value.

`_sysctl_read_live` and `_sysctl_conf_value` accept only `0` or a positive integer. `-1` is a valid
`perf_event_paranoid` value, and already below the ceiling, so an unsigned reader would turn a
more permissive box into "cannot read live value".

## Design

Approach B, chosen by the operator: sibling ceiling functions beside the floor ones, sharing the
conf classifiers, with the floor logic unchanged.

### Constants (`lib/constants.sh`)

```bash
readonly PERF_EVENT_PARANOID_MAX=2
readonly PERF_SYSCTL_CONF=/etc/sysctl.d/90-dotfiles-perf.conf
readonly PERF_EVENT_PARANOID_PROC=/proc/sys/kernel/perf_event_paranoid
```

### Signed parse mode

`_sysctl_read_live <path> [signed]` and `_sysctl_conf_value <conf> <key> [signed]`. With the third
argument `signed`, a value matches `-?(0|[1-9][0-9]*)`, at most 10 digits, within
`-2147483648..2147483647`; `-0` is rejected. Without it both behave exactly as today, so every
floor caller is unchanged.

### Install step: `_install_ubuntu_perf` (`lib/linux_ubuntu.sh`)

Runs in `install_ubuntu_packages`' step loop, directly after `kernel_keys`. Gates, in order:

- `HAS_DEVTOOLS` unset: print `perf: skipped (HAS_DEVTOOLS unset)`, return 0.
- `${_SYSTEMD_RUN_DIR:-${SYSTEMD_RUN_DIR}}` not a directory: print `perf: skipped (no systemd at <dir>)`, return 0.

Then `_sysctl_ceiling_step perf kernel.perf_event_paranoid 2 <conf> <proc> <seam_name>`, where conf
is `${_PERF_CONF:-${PERF_SYSCTL_CONF}}`, proc is `${_PERF_PROC:-${PERF_EVENT_PARANOID_PROC}}`, and
seam_name is `_PERF_CONF` when that seam is set, else empty.

### `_sysctl_ceiling_step <label> <key> <ceiling> <conf> <proc> <seam_name>`

1. Classify an existing conf exactly as `_sysctl_floor_step` does, with the same messages and rc 1:
   unreadable, non-text bytes, other keys, unparseable (read with `signed`).
2. Read live with `signed`; failure prints `<label>: cannot read live value <proc>` and returns 1.
3. Target is `min(live, ceiling)`. Write through `_sysctl_conf_write` when the conf is absent or its
   value is above the target. Read back; a mismatch prints `<label>: read-back mismatch (<conf>)`.
   Messages: `<label>: conf written (<target>)` for a new conf,
   `<label>: persisted <target> to <conf> (was <old>)` for a rewrite. A conf at or below the target
   is left alone.
4. Live at or below the ceiling: print `<label>: already <ceiling> or lower` unless step 3 wrote,
   return 0.
5. Live above the ceiling: apply `sysctl -w <key>=<conf value>` (through `_SYSCTL_BIN` without sudo
   when that seam is set, else `sudo sysctl`). Never `sysctl -p`. Print `<label>: applied`, or
   `<label>: apply failed` / `<label>: apply failed (_SYSCTL_BIN set, ran without sudo)` with rc 1.

| live | conf before | conf after     | applied   |
| ---- | ----------- | -------------- | --------- |
| 4    | absent      | 2              | `-w …=2`  |
| 2    | absent      | 2              | no        |
| 1    | absent      | 1              | no        |
| -1   | absent      | -1             | no        |
| 4    | 2           | 2 (untouched)  | `-w …=2`  |
| 4    | -1          | -1 (untouched) | `-w …=-1` |
| 4    | 3           | 2              | `-w …=2`  |
| 1    | 2           | 1              | no        |

### Doctor: `_doctor_check_perf_paranoid` (`lib/helpers.sh`)

Listed in `run_doctor` after `_doctor_check_kernel_keys`. Gated on `LINUX`, `HAS_DEVTOOLS` and the
systemd run dir; prints the heading `perf events:` then calls
`_doctor_sysctl_ceiling perf kernel.perf_event_paranoid 2 <conf> <proc>`.

`_doctor_sysctl_ceiling` classifies the conf as the step does (same FAIL texts, never a `tee`
remedy for a conf the step would refuse). Let target be `min(live, ceiling)`, tee be
`printf 'kernel.perf_event_paranoid = <target>\n' | sudo tee '<conf>'`. First match wins:

| condition    | verdict | message                                                           | remedy line                                                               |
| ------------ | ------- | ----------------------------------------------------------------- | ------------------------------------------------------------------------- |
| conf missing | FAIL    | `<conf> missing; next boot: kernel default; fix:`                 | tee, plus ` && sudo sysctl -w kernel.perf_event_paranoid=2` when live > 2 |
| conf > 2     | FAIL    | `<conf> value <v> above 2; next boot: <v>; fix:`                  | same as above                                                             |
| conf > live  | WARN    | `<conf> value <v> above live <live>; a reboot may raise it; fix:` | tee                                                                       |
| live > 2     | FAIL    | `live value <live> above 2; fix:`                                 | `sudo sysctl -w kernel.perf_event_paranoid=<v>`                           |
| otherwise    | PASS    | `perf perf_event_paranoid <live>`                                 | none                                                                      |

### Tests

`load_mocks` (`tests/helpers/common.bash`) exports `_PERF_CONF` and `_PERF_PROC` under
`BATS_TEST_TMPDIR` beside the existing sysctl seams, seeding the proc file with `2`, so no test
reaches the real `/etc/sysctl.d` or `/proc`. Install tests go in `tests/setup_env/linux_ubuntu.bats`,
doctor tests beside the kernel-keys doctor tests. Cases: every row of the step table (asserting the
conf content and the `sysctl-stub` call), both skips, each classifier refusal leaving the conf
byte-identical, both apply-failure messages, the signed reader on `-1`, `-0`, `-2147483649` and a
floor caller still rejecting `-1`, and each doctor row. The existing floor tests run unedited.

## Exposure

`claude` and `workstation` also run GitHub runners under their own `github-*` uids (about 36 runner
processes on `claude`, measured 2026-11-25). At 2, a CI job can count user-space events on its own
processes. It still cannot observe other uids, the kernel, or CPU-wide events. The operator chose 2
with this known.

## Rollout

Not a new `-t` path: the step runs in `-t setup` and `-t developer` on Ubuntu. For this change the
step alone is run on each box (V1), not a full `-t developer`.

## Docs

`CLAUDE.md` sits at 84997 of its 85000-byte ceiling (push hook, 2026-11-25), so it gains no new line. The Entry Points sysctl line and the sysctl seams line are reworded in place to name the perf ceiling and `_PERF_CONF`/`_PERF_PROC`, with detail moved to ai-config `docs/knowledge/dotfiles-test-seams.md` (§ `CLAUDE.md relocation: sysctl and kernel keys seams`) after messaging ai-config. The `CLAUDE.md` byte count must not rise above 85000.

## Requirements

- **R1.** `lib/constants.sh` defines `readonly PERF_EVENT_PARANOID_MAX=2`, `readonly PERF_SYSCTL_CONF=/etc/sysctl.d/90-dotfiles-perf.conf` and `readonly PERF_EVENT_PARANOID_PROC=/proc/sys/kernel/perf_event_paranoid`.
- **R2.** `_sysctl_read_live` and `_sysctl_conf_value` accept an optional final argument `signed`; with it, `-1` and `-2147483648` parse and `-0` and `-2147483649` do not; without it, `-1` is rejected as before.
- **R3.** `install_ubuntu_packages`' step loop runs `perf` directly after `kernel_keys`, calling `_install_ubuntu_perf`.
- **R4.** `_install_ubuntu_perf` prints `perf: skipped (HAS_DEVTOOLS unset)` and returns 0 when `HAS_DEVTOOLS` is empty, and prints `perf: skipped (no systemd at <dir>)` and returns 0 when the systemd run dir is absent, writing nothing in either case.
- **R5.** `_install_ubuntu_perf` resolves the conf from `_PERF_CONF` else `PERF_SYSCTL_CONF` and the proc file from `_PERF_PROC` else `PERF_EVENT_PARANOID_PROC`, and writes the conf without sudo when `_PERF_CONF` is set.
- **R6.** `_sysctl_ceiling_step` writes `kernel.perf_event_paranoid = <min(live, 2)>` when the conf is absent or holds a value above `min(live, 2)`, and leaves a conf holding a value at or below `min(live, 2)` byte-identical.
- **R7.** `_sysctl_ceiling_step` runs `sysctl -w kernel.perf_event_paranoid=<conf value>` only when live is above 2, never `sysctl -p`, and prints `perf: already 2 or lower` when live is at or below 2 and nothing was written.
- **R8.** `_sysctl_ceiling_step` refuses an existing conf that is unreadable, holds non-text bytes, holds other keys or is unparseable, returning 1 with the same `fix by hand` messages as `_sysctl_floor_step`, and leaves it byte-identical.
- **R9.** `_sysctl_ceiling_step` prints `perf: conf written (<target>)` for a new conf and `perf: persisted <target> to <conf> (was <old>)` for a rewrite, and `perf: applied` after a successful apply.
- **R10.** `run_doctor` calls `_doctor_check_perf_paranoid` after `_doctor_check_kernel_keys`; it returns silently unless `LINUX` and `HAS_DEVTOOLS` are set and the systemd run dir exists.
- **R11.** `_doctor_sysctl_ceiling` reports FAIL `<conf> missing; next boot: kernel default; fix:`, FAIL `<conf> value <v> above 2; next boot: <v>; fix:`, WARN `<conf> value <v> above live <live>; a reboot may raise it; fix:`, FAIL `live value <live> above 2; fix:`, else PASS `perf perf_event_paranoid <live>`, first match in that order.
- **R12.** `load_mocks` exports `_PERF_CONF` and `_PERF_PROC` under `BATS_TEST_TMPDIR`.
- **R13.** `_sysctl_floor_step` and `_doctor_sysctl_floor` bodies are unchanged by this work.
- **V1.** On `claude` and on `workstation`, run `_install_ubuntu_perf` alone with real sudo, then `perf stat -e cycles,instructions true` exits 0 as the normal user.
- **V2.** On both boxes, persistence: `sudo sysctl -w kernel.perf_event_paranoid=4`, `sudo systemctl restart systemd-sysctl`, then `/proc/sys/kernel/perf_event_paranoid` reads `2`.
- **V3.** On both boxes, `./setup_env.sh -t doctor` prints `perf perf_event_paranoid 2` as a PASS.
- **N1.** No package list, Brewfile or apt install changes; `linux-tools-generic` is not added.
- **N2.** No write or apply sets `kernel.perf_event_paranoid` above the lower of the live value and the existing conf value (the live value when no conf exists).
- **N3.** No `sysctl -p` and no write to any conf other than the perf conf.

## Multi-Lens Review

Reviewed at commit: `4986af4e` (Step 7 self-review commit, before Step 8 dispatch)

### Goal-Fit

Finding: `target = min(live, 2)` mirrors the floor step onto a security knob, so a transient looser value (`sysctl -w kernel.perf_event_paranoid=-1` for `perf record -a`) is persisted by the next `-t setup`/`-t developer`, and the doctor PASSes it ("otherwise PASS"); this contradicts the Exposure section the operator approved 2 against. Simpler design: persist exactly 2, apply when live > 2, flag a conf or live below 2; the signed conf reader, the `min()` target and step-table rows 3, 4, 6 then go. Second: V1's exit status does not prove counters count (`perf stat` exits 0 on `<not supported>`); pin a non-zero `instructions:u` count. Premise verified on both boxes (paranoid 4, bare metal, cpu PMU present, linux-tools -43/-44 installed, both `linux_workstation` with devtools).
Assumption: the zeta runs needing counters execute on the host as `bruce`, not in a docker container (default seccomp blocks `perf_event_open`) or a runner job; settled by asking the math session where `perf stat` runs (asked 2026-11-25).
Disposition:

### Ergonomics

Finding: V2's `sudo systemctl restart systemd-sysctl` re-applies every sysctl.d key (the `net.ipv4.conf.*.rp_filter` glob reaches docker bridges and veths, `kernel.core_pattern`, `kptr_restrict`, `sysrq`) under the live runners, which is the whole-system `-p` that N3 exists to avoid; use `sudo /usr/lib/systemd/systemd-sysctl /etc/sysctl.d/90-dotfiles-perf.conf`. V1 needs a pasteable command. Minor: "conf missing" FAILs even when live is already at or below 2, and the `HAS_DEVTOOLS` gate also reaches `wsl2_workstation` (`cruncher`), unnamed in scope. Every step and doctor row pins a derived value; only a test asserting `perf: already 2 or lower` alone would pass on empty output.
Assumption: same as Goal-Fit (host shell as the login user, not a container or runner job).
Disposition:

### Risk

Finding: the same `min(live, 2)` loosening ratchet, independently: rows `1/absent -> 1`, `-1/absent -> -1` and `1/2 -> 1` persist a transient value, the last destroying the operator's `2` (and any comments) through the whole-file `_sysctl_conf_write`; the doctor WARN's tee remedy tells the operator to do the same. N2 forbids raising, not loosening, so every requirement passes. Fix: persist 2 when the conf is absent or above 2, read live only to decide the apply, drop the WARN. Exposure correction: `claude` has one runner account (`github-runner:995`, 18 `Runner.Listener`, 66 processes); `ptrace_scope` 1 gates only ATTACH while `perf_event_open` checks READ, so at 2 a job can count events on concurrent jobs' processes under the same uid. Tests: the seeded proc `2` equals the ceiling, so a PASS printing the constant instead of live passes; pin a PASS at live 1 or -1, and add a live 2/conf 2 no-op row asserting no `sysctl-stub` call. WSL scope as Ergonomics.
Assumption: a live value below 2 is a deliberate, durable choice rather than a transient debugging setting; settled by asking the operator and math whether anyone sets it below 2 by hand.
Disposition:

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.
