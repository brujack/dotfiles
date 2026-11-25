# perf_event_paranoid ceiling on the Linux development boxes

- **Status:** Approved
- **Approved:** 2026-11-25
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
persist `max(live, floor)` and apply when live is below the floor. For a resource limit, persisting
a higher live value only adds capacity. Mirrored onto this key as `min(live, 2)`, it would persist
whatever looser value happened to be live when setup ran (a one-off `sysctl -w ...=-1` for
`perf record -a`), which the operator did not approve (Step 8 round 1, Goal-Fit and Risk). So this
key gets a fixed value, not a mirrored floor: dotfiles persists exactly 2 and applies exactly 2.

`_sysctl_read_live` and `_sysctl_conf_value` accept only `0` or a positive integer, which covers
every value this design writes or leaves alone (0, 1, 2 and above). `-1` is a valid kernel value
but nothing sets it (math session, 2026-11-25), so a `-1` live or conf value fails closed through the
existing readers ("live value ... unreadable or below 0" / "unparseable; fix by hand") and nothing is written. The
operator chose this over a signed parse mode in round 2, which leaves the shared readers unchanged.

The conf-refusal block (unreadable, non-text, other keys, unparseable) already sits inline in both
`_sysctl_floor_step` and `_doctor_sysctl_floor`; R13 keeps those bodies frozen, so the ceiling step
and ceiling doctor carry a third and fourth copy (external review F1.2). This spec accepts that to
keep the floor paths untouched, as approach B was chosen for. Extracting one shared classifier is a
Backlog row added in the implementation PR.

## Design

Approach B, chosen by the operator: sibling functions beside the floor ones, sharing the conf
classifiers, with the floor logic unchanged.

### Constants (`lib/constants.sh`)

```bash
readonly PERF_EVENT_PARANOID_MAX=2
readonly PERF_SYSCTL_CONF=/etc/sysctl.d/90-dotfiles-perf.conf
readonly PERF_EVENT_PARANOID_PROC=/proc/sys/kernel/perf_event_paranoid
```

### Install step: `_install_ubuntu_perf` (`lib/linux_ubuntu.sh`)

Runs in `install_ubuntu_packages`' step loop, directly after `kernel_keys`. Gates, in order:

- `HAS_DEVTOOLS` unset: print `perf: skipped (HAS_DEVTOOLS unset)`, return 0.
- `${_SYSTEMD_RUN_DIR:-${SYSTEMD_RUN_DIR}}` not a directory: print `perf: skipped (no systemd at <dir>)`, return 0.
- The proc file (`${_PERF_PROC:-${PERF_EVENT_PARANOID_PROC}}`) does not exist: print `perf: skipped (no <proc>)`, return 0. A kernel without perf events has nothing to tune.

The gate reaches `claude` and `workstation` (`linux_workstation`) and also `wsl2_workstation`
(`cruncher`) when WSL systemd is on. Its WSL kernel was not measured (`ssh cruncher` refused,
2026-11-25): if the proc file is absent the third gate skips; if present, the step writes 2 and
applies only a value above 2. Either way it never loosens anything.

Then `_sysctl_ceiling_step perf kernel.perf_event_paranoid "${PERF_EVENT_PARANOID_MAX}" <conf> <proc> <seam_name>`, where conf
is `${_PERF_CONF:-${PERF_SYSCTL_CONF}}`, proc is `${_PERF_PROC:-${PERF_EVENT_PARANOID_PROC}}`, and
seam_name is `_PERF_CONF` when that seam is set, else empty.

### `_sysctl_ceiling_step <label> <key> <ceiling> <conf> <proc> <seam_name>`

1. Classify an existing conf exactly as `_sysctl_floor_step` does, with the same messages and rc 1:
   unreadable, non-text bytes, other keys, unparseable (a `-1` value is unparseable and is refused).
2. Read live with the existing reader (a `-1` fails here); failure prints `<label>: live value in <proc> unreadable or below 0; fix by hand` and returns 1.
3. Conf absent, or its value above the ceiling: write `<key> = <ceiling>` through
   `_sysctl_conf_write`, read back (mismatch prints `<label>: read-back mismatch (<conf>)`, rc 1),
   and print `<label>: conf written (<ceiling>)` for a new conf or
   `<label>: persisted <ceiling> to <conf> (was <old>)` for a rewrite. A conf at or below the
   ceiling is left byte-identical, including a hand-set value below it.
4. Live at or below the ceiling: print `<label>: already <ceiling> or lower` unless step 3 wrote,
   return 0. Live is never changed when it is at or below the ceiling.
5. Live above the ceiling: run `sysctl -w <key>=<ceiling>` (through `_SYSCTL_BIN` without sudo when
   that seam is set, else `sudo sysctl`). Never `sysctl -p`. Print `<label>: applied`, or
   `<label>: apply failed` / `<label>: apply failed (_SYSCTL_BIN set, ran without sudo)` with rc 1.

| live | conf before | conf after     | applied  | message / rc                       |
| ---- | ----------- | -------------- | -------- | ---------------------------------- |
| 4    | absent      | 2              | `-w …=2` | conf written (2), applied          |
| 2    | absent      | 2              | no       | conf written (2)                   |
| 1    | absent      | 2              | no       | conf written (2)                   |
| 0    | absent      | 2              | no       | conf written (2)                   |
| 4    | 2           | 2 (untouched)  | `-w …=2` | applied                            |
| 4    | 1           | 1 (untouched)  | `-w …=2` | applied                            |
| 4    | 3           | 2              | `-w …=2` | persisted 2 … (was 3), applied     |
| 1    | 2           | 2 (untouched)  | no       | already 2 or lower                 |
| 2    | 2           | 2 (untouched)  | no       | already 2 or lower                 |
| -1   | absent      | absent         | no       | live value … below 0; fix by hand, rc 1 |
| 4    | -1          | -1 (untouched) | no       | … exists but is unparseable, rc 1  |

### Doctor: `_doctor_check_perf_paranoid` (`lib/helpers.sh`)

Listed in `run_doctor` after `_doctor_check_kernel_keys`. Gated on `LINUX`, `HAS_DEVTOOLS`, the
systemd run dir and the proc file existing (all as the step); prints the heading `perf events:` then calls
`_doctor_sysctl_ceiling perf kernel.perf_event_paranoid "${PERF_EVENT_PARANOID_MAX}" <conf> <proc>`; the ceiling functions take the value as an argument and print it, so no literal `2` appears in either.

`_doctor_sysctl_ceiling` reads live first, as `_doctor_sysctl_floor` does, then classifies the conf as the step does (same FAIL texts). It never prints a
`tee` remedy for a conf the step would keep, so a hand-set value below 2 gets no overwrite remedy.
Let tee be `printf 'kernel.perf_event_paranoid = 2\n' | sudo tee '<conf>'`. First match wins:

| condition    | verdict | message                                             | remedy line                                                              |
| ------------ | ------- | --------------------------------------------------- | ------------------------------------------------------------------------ |
| live unreadable | FAIL | `live value in <proc> unreadable or below 0` | none |
| conf unreadable | FAIL | `<conf> exists but is unreadable; fix by hand` | none |
| conf non-text | FAIL | `<conf> holds non-text bytes (control or non-ASCII, e.g. CR, NUL); fix by hand` | none |
| conf other keys | FAIL | `<conf> holds other keys; fix by hand` | none |
| conf unparseable (incl. `-1`) | FAIL | `<conf> exists but is unparseable; fix by hand` | none |
| conf missing | FAIL    | `<conf> missing; next boot: kernel default; fix:`   | tee, plus ` && sudo sysctl -w kernel.perf_event_paranoid=2` when live > 2 |
| conf > 2     | FAIL    | `<conf> value <v> above 2; next boot: <v>; fix:`    | same as above                                                            |
| live > 2     | FAIL    | `live value <live> above 2; fix:`                   | `sudo sysctl -w kernel.perf_event_paranoid=2`                            |
| conf < 2     | WARN    | `<conf> value <v> below 2; set outside dotfiles`    | none                                                                     |
| live < 2     | WARN    | `live value <live> below 2; next boot: <v>; fix:`   | `sudo sysctl -w kernel.perf_event_paranoid=2`                            |
| otherwise    | PASS    | `perf perf_event_paranoid <live>`                   | none                                                                     |

### Tests

`load_mocks` (`tests/helpers/common.bash`) exports `_PERF_CONF` and `_PERF_PROC` under
`BATS_TEST_TMPDIR` beside the existing sysctl seams, seeding the proc file with `2`, so no test
reaches the real `/etc/sysctl.d` or `/proc`. Install tests go in `tests/setup_env/linux_ubuntu.bats`,
doctor tests beside the kernel-keys doctor tests. Cases:

- every row of the step table, asserting the conf bytes, the message, and the exact `sysctl-stub`
  argument or that the stub was never called;
- both skips; each classifier refusal leaving the conf byte-identical; both apply-failure messages;
- a live `-1` failing with `live value in <proc> unreadable or below 0; fix by hand` and a conf `-1`
  refused as unparseable, each leaving the conf byte-identical and the stub uncalled;
- each doctor conf refusal (unreadable, non-text, other keys, unparseable at conf `-1`), asserting
  the FAIL text and that no `tee` line is printed;
- a wiring test that `declare -f _install_ubuntu_perf` and `declare -f _doctor_check_perf_paranoid`
  each contain `PERF_EVENT_PARANOID_MAX`, as the kernel-keys wiring test does;
- stubs: `_install_ubuntu_perf() { :; }` in `_stub_ubuntu_steps` (`tests/setup_env/workflows.bats`)
  and `_doctor_check_perf_paranoid() { :; }` beside every `_doctor_check_kernel_keys() { :; }` stub
  (three in `tests/setup_env/unit.bats`, one in `tests/setup_env/plugin_node_paths.bats`), with the
  kernel-keys stub-count test extended to the perf check, so no end-to-end test runs the real step
  on a host that exports `HAS_DEVTOOLS`;
- the proc-absent skip, with no conf written;
- each doctor row. The `conf < 2` WARN runs at conf `1`, live `1`, so the message pins the derived
  value `1`. The `live < 2` WARN is reachable only with conf exactly 2 (first match), so it runs at
  live `1`, conf `2`: its `<live>` field pins the derived value, and its `next boot:` field is the
  constant 2 by construction.

The existing floor tests run unedited.

## Exposure

`claude` runs one runner account, `github-runner` (uid 995), with 18 `Runner.Listener` instances
and 66 processes (measured 2026-11-25 on `claude`; `workstation` not counted). Yama
`ptrace_scope` is 1, which gates only `PTRACE_MODE_ATTACH`, while `perf_event_open` checks
`PTRACE_MODE_READ`. So at 2 a CI job can count user-space events on any process of that uid,
including concurrent jobs. That uid can already read `/proc/<pid>/environ` of the same jobs, so the
added surface is small. Kernel and CPU-wide events stay blocked, and other uids stay out of reach.
The operator chose 2 with this known.

The math session confirmed (2026-11-25) that `perf stat` runs in a host shell as `bruce` on its own
processes, user-space only, and that nothing will set the key below 2.

## Rollout

Not a new `-t` path: the step runs in `-t setup` and `-t developer` on Ubuntu. For this change the
step alone is run on each box (V1), not a full `-t developer`.

## Docs

`CLAUDE.md` sits at 84997 of its 85000-byte ceiling (push hook, 2026-11-25), so it gains no new line. The Entry Points sysctl line and the sysctl seams line are reworded in place to name the perf ceiling and `_PERF_CONF`/`_PERF_PROC`, with detail moved to ai-config `docs/knowledge/dotfiles-test-seams.md` (§ `CLAUDE.md relocation: sysctl and kernel keys seams`) after messaging ai-config. The `CLAUDE.md` byte count must not rise above 85000.

## Requirements

- **R1.** `lib/constants.sh` defines `readonly PERF_EVENT_PARANOID_MAX=2`, `readonly PERF_SYSCTL_CONF=/etc/sysctl.d/90-dotfiles-perf.conf` and `readonly PERF_EVENT_PARANOID_PROC=/proc/sys/kernel/perf_event_paranoid`, and `_install_ubuntu_perf` and `_doctor_check_perf_paranoid` pass `${PERF_EVENT_PARANOID_MAX}` as the ceiling, with no literal `2` in either.
- **R2.** `_install_ubuntu_perf` prints `perf: skipped (no <proc>)` and returns 0, writing nothing, when the proc file does not exist; `_doctor_check_perf_paranoid` returns silently in the same case.
- **R3.** `install_ubuntu_packages`' step loop runs `perf` directly after `kernel_keys`, calling `_install_ubuntu_perf`.
- **R4.** `_install_ubuntu_perf` prints `perf: skipped (HAS_DEVTOOLS unset)` and returns 0 when `HAS_DEVTOOLS` is empty, and prints `perf: skipped (no systemd at <dir>)` and returns 0 when the systemd run dir is absent, writing nothing in either case.
- **R5.** `_install_ubuntu_perf` resolves the conf from `_PERF_CONF` else `PERF_SYSCTL_CONF` and the proc file from `_PERF_PROC` else `PERF_EVENT_PARANOID_PROC`, and writes the conf without sudo when `_PERF_CONF` is set.
- **R6.** `_sysctl_ceiling_step` writes `kernel.perf_event_paranoid = 2` when the conf is absent or holds a value above 2, and leaves a conf holding a value from 0 to 2 byte-identical.
- **R7.** `_sysctl_ceiling_step` runs `sysctl -w kernel.perf_event_paranoid=2` only when live is above 2, never `sysctl -p` and never another value, and prints `perf: already 2 or lower` when live is at or below 2 and nothing was written.
- **R8.** `_sysctl_ceiling_step` refuses an existing conf that is unreadable, holds non-text bytes, holds other keys or is unparseable (a `-1` value included), returning 1 with the same `fix by hand` messages as `_sysctl_floor_step`, and leaves it byte-identical; a live value of `-1` or an unreadable live file returns 1 with `perf: live value in <proc> unreadable or below 0; fix by hand` and writes nothing.
- **R9.** `_sysctl_ceiling_step` prints `perf: conf written (2)` for a new conf, `perf: persisted 2 to <conf> (was <old>)` for a rewrite, and `perf: applied` after a successful apply.
- **R10.** `run_doctor` calls `_doctor_check_perf_paranoid` after `_doctor_check_kernel_keys`; it returns silently unless `LINUX` and `HAS_DEVTOOLS` are set and the systemd run dir exists.
- **R11.** `_doctor_sysctl_ceiling` reports, first match in this order: FAIL `live value in <proc> unreadable or below 0`; FAIL `<conf> exists but is unreadable; fix by hand`; FAIL `<conf> holds non-text bytes (control or non-ASCII, e.g. CR, NUL); fix by hand`; FAIL `<conf> holds other keys; fix by hand`; FAIL `<conf> exists but is unparseable; fix by hand`; FAIL `<conf> missing; next boot: kernel default; fix:`; FAIL `<conf> value <v> above 2; next boot: <v>; fix:`; FAIL `live value <live> above 2; fix:`; WARN `<conf> value <v> below 2; set outside dotfiles` with no remedy line; WARN `live value <live> below 2; next boot: <v>; fix:`; else PASS `perf perf_event_paranoid <live>`; the five refusal FAILs print no remedy line, and every printed `tee` remedy writes `kernel.perf_event_paranoid = 2`.
- **R12.** `load_mocks` exports `_PERF_CONF` and `_PERF_PROC` under `BATS_TEST_TMPDIR`.
- **R13.** `_sysctl_floor_step`, `_doctor_sysctl_floor`, `_sysctl_read_live` and `_sysctl_conf_value` bodies are unchanged by this work.
- **V1.** On `claude` and on `workstation`, run `_install_ubuntu_perf` alone with real sudo (the plan gives the exact sourcing command), then as the normal user math's own form `perf stat -x, -e cycles,instructions true 2>&1 >/dev/null` prints a count above 0 for both events and no `<not supported>` or `<not counted>` line.
- **V2.** On both boxes, persistence without touching other keys: `sudo sysctl -w kernel.perf_event_paranoid=4`, then `sudo /usr/lib/systemd/systemd-sysctl /etc/sysctl.d/90-dotfiles-perf.conf`, then `/proc/sys/kernel/perf_event_paranoid` reads `2`; `/usr/lib/systemd/systemd-sysctl --cat-config` shows no later file setting the key.
- **V3.** On both boxes, `./setup_env.sh -t doctor` prints `perf perf_event_paranoid 2` as a PASS.
- **N1.** No package list, Brewfile or apt install changes; `linux-tools-generic` is not added.
- **N2.** No write sets the perf conf to any value other than 2, no apply sets the live value to any value other than 2, and no conf holding a value at or below 2 is rewritten.
- **N3.** No `sysctl -p` and no write to any conf other than the perf conf.

## Multi-Lens Review

Reviewed at commit: `4986af4e` (Step 7 self-review commit, before Step 8 dispatch)

### Goal-Fit

Finding: `target = min(live, 2)` mirrors the floor step onto a security knob, so a transient looser value (`sysctl -w kernel.perf_event_paranoid=-1` for `perf record -a`) is persisted by the next `-t setup`/`-t developer`, and the doctor PASSes it ("otherwise PASS"); this contradicts the Exposure section the operator approved 2 against. Simpler design: persist exactly 2, apply when live > 2, flag a conf or live below 2; the signed conf reader, the `min()` target and step-table rows 3, 4, 6 then go. Second: V1's exit status does not prove counters count (`perf stat` exits 0 on `<not supported>`); pin a non-zero `instructions:u` count. Premise verified on both boxes (paranoid 4, bare metal, cpu PMU present, linux-tools -43/-44 installed, both `linux_workstation` with devtools).
Assumption: the zeta runs needing counters execute on the host as `bruce`, not in a docker container (default seccomp blocks `perf_event_open`) or a runner job; settled by asking the math session where `perf stat` runs (asked 2026-11-25).
Disposition: Addressed, operator 2026-11-25: persist exactly 2 and apply exactly 2; a conf or live value below 2 is left alone and doctor WARNs (signed readers kept so `-1` can be read and left alone); V1 pins a non-zero `instructions:u` count. Assumption confirmed by the math session 2026-11-25: host shell as `bruce`, no container or runner.

### Ergonomics

Finding: V2's `sudo systemctl restart systemd-sysctl` re-applies every sysctl.d key (the `net.ipv4.conf.*.rp_filter` glob reaches docker bridges and veths, `kernel.core_pattern`, `kptr_restrict`, `sysrq`) under the live runners, which is the whole-system `-p` that N3 exists to avoid; use `sudo /usr/lib/systemd/systemd-sysctl /etc/sysctl.d/90-dotfiles-perf.conf`. V1 needs a pasteable command. Minor: "conf missing" FAILs even when live is already at or below 2, and the `HAS_DEVTOOLS` gate also reaches `wsl2_workstation` (`cruncher`), unnamed in scope. Every step and doctor row pins a derived value; only a test asserting `perf: already 2 or lower` alone would pass on empty output.
Assumption: same as Goal-Fit (host shell as the login user, not a container or runner job).
Disposition: Addressed, operator 2026-11-25: V2 applies only the perf conf via `/usr/lib/systemd/systemd-sysctl <conf>`; V1 points to an exact command in the plan; conf-missing FAIL kept (the conf is what survives reboot), wsl2_workstation reach stated as harmless.

### Risk

Finding: the same `min(live, 2)` loosening ratchet, independently: rows `1/absent -> 1`, `-1/absent -> -1` and `1/2 -> 1` persist a transient value, the last destroying the operator's `2` (and any comments) through the whole-file `_sysctl_conf_write`; the doctor WARN's tee remedy tells the operator to do the same. N2 forbids raising, not loosening, so every requirement passes. Fix: persist 2 when the conf is absent or above 2, read live only to decide the apply, drop the WARN. Exposure correction: `claude` has one runner account (`github-runner:995`, 18 `Runner.Listener`, 66 processes); `ptrace_scope` 1 gates only ATTACH while `perf_event_open` checks READ, so at 2 a job can count events on concurrent jobs' processes under the same uid. Tests: the seeded proc `2` equals the ceiling, so a PASS printing the constant instead of live passes; pin a PASS at live 1 or -1, and add a live 2/conf 2 no-op row asserting no `sysctl-stub` call. WSL scope as Ergonomics.
Assumption: a live value below 2 is a deliberate, durable choice rather than a transient debugging setting; settled by asking the operator and math whether anyone sets it below 2 by hand.
Disposition: Addressed, operator 2026-11-25: fixed value 2 as Goal-Fit; Exposure rewritten with the single runner uid and the ATTACH/READ distinction; doctor WARN rows tested at `-1` to pin a derived value; live 2 / conf 2 no-op row added with no `sysctl-stub` call. Assumption confirmed by the math session 2026-11-25: nothing sets the key below 2.

### Round 2 (re-reviewed at `a48b3546`, all three lenses, after the fixed-value revision)

Goal-Fit (`a48b3546`): no correctness flaw; the signed parse mode serves only `-1`, which nothing sets, while editing two readers every floor caller shares; drop it and let `-1` fail closed. Assumption: perf at 2 still falls back to user-only counting for unmodified events, so math's own `cycles,instructions` form works; V1 should run that form.
Disposition: Addressed, operator 2026-11-25: signed mode dropped (R2 replaced, R13 widened to the two readers); V1 runs `perf stat -x, -e cycles,instructions true` and requires non-zero counts for both.

Ergonomics (`a48b3546`): the test plan ran the `live < 2` WARN at conf `-1`, unreachable under first-match order; R11 lacked the unreadable-live FAIL row `_doctor_sysctl_floor` has. Assumption: `cruncher`'s WSL kernel exposes `/proc/sys/kernel/perf_event_paranoid`; unmeasured (`ssh cruncher` refused).
Disposition: Addressed 2026-11-25: test rows corrected; `cannot read <proc>` FAIL added first; a proc-absent skip (new R2) removes the dependence on the cruncher measurement.

Risk (`a48b3546`): no load-bearing issue; same unreachable test row as Ergonomics; `man systemd-sysctl` confirms a path argument applies only that file (V2 sound). No uncertain assumption beyond perf working at 2, which V1 measures.
Disposition: Addressed 2026-11-25: as Ergonomics.

Stop: round 2's findings all sat in the test plan and wording, and its one design change removed surface (the signed mode); both stop signals agree.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.

## External Review

### Round 1 (reviewed at `a5903494`)

Report: [round1.md](2026-11-25-perf-event-paranoid-ceiling-design.external-review/round1.md)

#### Author response

| finding | disposition | evidence | reviewer verdict | operator (Step 9) |
| ------- | ----------- | -------- | ---------------- | ----------------- |
| F1.1 | Fixed | Doctor table and R11 now list the four conf-refusal FAILs (texts from `_doctor_sysctl_floor`) after the live-unreadable row, with no remedy line; Tests add one doctor case per refusal (unparseable at conf `-1`) asserting no `tee` line. | unjudged || Accepted — operator, 2026-11-25: "Accept all, approve" |
| F1.2 | Rebutted | Approach B was chosen to leave the floor paths untouched; extracting a shared classifier edits both floor bodies that guard three live keys. The trade (four copies) is now recorded in "Why the existing sysctl step cannot be reused", and the extraction goes to the Backlog in the implementation PR. | unjudged || Accepted — operator, 2026-11-25: "Accept all, approve" |
| F1.3 | Fixed | Both call sites pass `"${PERF_EVENT_PARANOID_MAX}"` (R1 extended: no literal `2` in either caller); Tests add a `declare -f` wiring test. | unjudged || Accepted — operator, 2026-11-25: "Accept all, approve" |
| F1.4 | Fixed | Tests name `_install_ubuntu_perf` in `_stub_ubuntu_steps` and `_doctor_check_perf_paranoid` beside all four `_doctor_check_kernel_keys` stubs, and extend the stub-count test. | unjudged || Accepted — operator, 2026-11-25: "Accept all, approve" |
| F1.5 | Fixed | R6 now reads "a value from 0 to 2"; `-1` is covered only by R8's refusal. | unjudged || Accepted — operator, 2026-11-25: "Accept all, approve" |
| F1.6 | Fixed | Step and doctor live-read failure text is now `live value in <proc> unreadable or below 0` (R8, R11, both tables), naming both causes. | unjudged || Accepted — operator, 2026-11-25: "Accept all, approve" |
| F1.7 | Declined to run | Measuring the fallback needs `sudo sysctl -w kernel.perf_event_paranoid=2` on a box running live runners; V1 measures it on both boxes after the step applies 2. | unjudged || Accepted — operator, 2026-11-25: "Accept all, approve" |

Stopped: reviewer recommended stopping in round 1
