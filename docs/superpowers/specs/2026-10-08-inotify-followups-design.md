# inotify follow-ups: parser, persisted value, doctor remedy, sysctl seam

- **Date:** 2026-10-08
- **Status:** Draft
- **Follows:** `2026-10-08-molecule-host-tuning-design.md` (#323)

## Problem

Four findings from #323's review sit in the Backlog (`docs/superpowers/README.md`
rows 180-183). Each was checked against the code and the two reachable hosts on
2026-10-08 before this design was written.

| Row | Finding                                                                                 | Premise check                                                                                                                                                                                                                                                                      |
| --- | --------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 180 | `_inotify_conf_value` keeps an earlier value when the last assignment is non-numeric    | **Reproduced.** A conf of `= 2048` then `= abc` returns `2048`. The awk regex matches only numeric right-hand sides, so the bad last line is skipped rather than clearing `val`. systemd-sysctl applies the last assignment, fails on `abc`, and boot stays at the kernel default. |
| 181 | doctor's `tee` remedy carries `&& sudo sysctl -w ...=1024` even when live is above 1024 | **Latent.** True of the code; no host is in that state.                                                                                                                                                                                                                            |
| 182 | the step writes 1024 when the conf is missing, even when live is higher                 | **Latent.** Same.                                                                                                                                                                                                                                                                  |
| 183 | `sudo "${_SYSCTL_BIN:-sysctl}"` runs an env-chosen binary as root                       | **Hygiene.** Requires control of the operator's environment; tests never need root, since `tests/mocks/sudo` execs.                                                                                                                                                                |

Host state, measured 2026-10-08 (population: `claude` and `workstation`; `cruncher`
unreachable, not measured):

```
claude       live 1024   /etc/sysctl.d: 90-dotfiles-inotify.conf (1024), README.sysctl
workstation  live 1024   same conf at 1024; /usr/lib/sysctl.d/30-localsearch.conf sets max_user_watches only
both         no other file in /etc/sysctl.d, /usr/lib/sysctl.d or /etc/sysctl.conf sets max_user_instances
```

So rows 181 and 182 need either a live value above 1024 with the conf missing, or an
earlier-sorting sysctl.d file carrying a higher value. Neither exists today. They are
fixed anyway because ADR-0044's title and CLAUDE.md both promise the step "never
lowers a higher value", and the code does not keep that promise: a flat 1024 in a
`90-` file beats an earlier `50-` file's 4096 at boot.

## Decision

The operator chose (2026-10-08) to **persist the live value** when it is above 1024,
over narrowing the "never lowers" wording or writing nothing. Accepted cost: a value
someone raised by hand, temporarily, becomes permanent on the next `-t setup` or
`-t developer` run.

## Design

### 1. Parser (`lib/helpers.sh:_inotify_conf_value`)

Match the key — either spelling, optional leading `-`, any whitespace around `=` —
with **any** right-hand side. Every matching line resets `val`: to the value when it
is `0` or a non-zero-led integer of at most 10 digits, otherwise to empty. An empty
`val` at end of file prints nothing, so install and doctor already report the conf as
unparseable and "fix by hand". No caller changes.

### 2. Install step (`lib/linux_ubuntu.sh:_install_ubuntu_inotify`)

Read and validate the live value **before** deciding whether to write. The target is
`max(live, 1024)`. Order:

1. Skips (HAS_DOCKER, systemd dir) — unchanged.
2. Classify the conf (unreadable / unparseable returns 1) — unchanged.
3. Read live. Unreadable or not `0`/non-zero-led integer: return 1, **nothing written**.
   This moves the existing check earlier; the target cannot be computed without it.
4. Conf missing or below 1024: write `fs.inotify.max_user_instances = <target>`,
   read back, and return 1 unless the read-back value equals the target.
5. Live at or above 1024: return 0 (prints "already" unless it just wrote).
6. Otherwise apply the conf value with `sysctl -w`.

Step 6 only runs when live is below 1024, where the target is 1024, so apply never
uses the live value.

### 3. Doctor (`lib/helpers.sh:_doctor_check_inotify_limits`)

In the missing-or-below branch, the `tee` line writes `max(live, 1024)`, and
`&& sudo sysctl -w fs.inotify.max_user_instances=1024` is appended only when live is
below 1024. Live is already validated earlier in the function. Other branches are
unchanged.

### 4. sysctl seam

`_install_ubuntu_inotify` runs `"${_SYSCTL_BIN}" -w ...` **without** sudo when
`_SYSCTL_BIN` is set and non-empty, and `sudo sysctl -w ...` when it is not. The
production branch is otherwise untested, because `load_mocks` always sets the seam;
one test unsets it and puts a recording `sysctl` stub first on `PATH`, so the sudo
mock execs the stub, never the real binary (`tests/mocks/sysctl` execs
`/usr/sbin/sysctl`, which `tdd.md` E2 forbids reaching).

### Docs

- CLAUDE.md `setup` entry: "persists the higher of the live value and 1024".
- CLAUDE.md Test Seams `_SYSCTL_*` bullet: the sysctl seam runs without sudo.
- Delete Backlog rows 180-183; add one row for the `_SYSCTL_CONF` shape (N4).
- ADR-0044 is unchanged: its title becomes true rather than needing an amendment.

## Testing

All in `tests/setup_env/linux_ubuntu.bats` and `tests/setup_env/unit.bats`, through the
existing seams.

- Parser: `= 2048` then `= abc` is unparseable in both install and doctor; `= 2048`
  then an empty right-hand side is unparseable; `= abc` then `= 2048` reads 2048
  (the reset runs in both directions).
- Install: conf absent with live 4096 writes 4096 and applies nothing (replaces the
  test that pins 1024); conf 512 with live 2048 writes 2048; conf absent with live 128
  writes and applies 1024; conf absent with an unreadable live value returns 1 and
  the conf does **not** exist afterwards; a tee that writes 1024 when the target is
  4096 fails the read-back.
- Doctor: missing conf with live 4096 prints the `tee` with 4096 and no `sysctl -w`;
  missing conf with live 128 prints the `tee` with 1024 and the `sysctl -w` half.
- Seam: with `_SYSCTL_BIN` set, the call log has `sysctl -w` and no `sudo` line for
  it; with it unset and a `PATH` stub, the log has `sudo sysctl -w`.
- Mutation controls, each must turn a test red: drop the `val = ""` reset; replace the
  target with 1024; drop the `live < 1024` condition on the doctor suffix; always use
  sudo.

## Requirements

- **R1.** `[PR1]` `_inotify_conf_value` prints the value of the last line assigning `fs.inotify.max_user_instances` (dotted or slash spelling, optional leading `-`), and prints nothing when that last right-hand side is not `0` or a non-zero-led integer of at most 10 digits, including empty.
- **R2.** `[PR1]` `_install_ubuntu_inotify` returns 1 without writing the conf or applying when the live value is unreadable or not `0`/a non-zero-led integer, whatever the conf state.
- **R3.** `[PR1]` When the conf is missing or its value is below 1024, `_install_ubuntu_inotify` writes `fs.inotify.max_user_instances = <max(live, 1024)>`, and returns 1 when the read-back value differs from that number.
- **R4.** `[PR1]` `_install_ubuntu_inotify` applies only when the live value is below 1024, and runs `"${_SYSCTL_BIN}" -w` without sudo when `_SYSCTL_BIN` is non-empty, `sudo sysctl -w` otherwise.
- **R5.** `[PR1]` When the conf is missing or below 1024, `_doctor_check_inotify_limits` prints a `tee` line writing `max(live, 1024)`, followed by `&& sudo sysctl -w fs.inotify.max_user_instances=1024` only when the live value is below 1024.
- **R6.** `[PR1]` CLAUDE.md's `setup` entry and Test Seams bullet describe R3 and R4; Backlog rows for these four findings are deleted and one row is added for N4.
- **V1.** After merge, on `claude`: `-t doctor` passes the inotify check and the step prints `inotify: already 1024 or higher` with `/etc/sysctl.d/90-dotfiles-inotify.conf` byte-identical before and after.
- **V2.** `make test` passes; each mutation in Testing turns at least one test red.
- **N1.** No change to the unreadable/unparseable "fix by hand" path or its messages.
- **N2.** No shared `_inotify_conf_state` helper (Backlog :325 stays open).
- **N3.** No path writes a conf value or applies a live value lower than the live value or an existing conf value above 1024.
- **N4.** No change to `sudo tee "${_conf}"` when `_SYSCTL_CONF` is set; that shape gets its own Backlog row.
- **N5.** No change to `fs.inotify.max_user_watches` or any other key.
