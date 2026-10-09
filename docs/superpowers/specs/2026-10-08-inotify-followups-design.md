# inotify follow-ups: parser, persisted value, doctor remedy, sysctl seam

- **Date:** 2026-10-08
- **Status:** Approved
- **Approved:** 2026-10-08
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
lowers a higher value", and the code does not keep that promise: with the conf
missing it writes 1024 over a higher live value, and with the conf present it never
compares the two, so a hand raise is dropped at the next boot.

## Decision

The operator chose (2026-10-08) to **persist the live value** when it is above 1024,
over narrowing the "never lowers" wording or writing nothing. Accepted cost: a value
someone raised by hand, temporarily, becomes permanent on the next `-t setup` or
`-t developer` run.

After round-1 review the operator chose option B (2026-10-08): the live value is also
compared against a conf that already exists, so a hand raise after the conf is written
is persisted (install) or reported (doctor). Option C, renaming the conf to sort first
so any other drop-in wins at boot, was declined.

**Known limit, stated rather than fixed:** a drop-in that sorts before `90-` and sets a
higher value is overridden by our file at boot, and live then reads our value, so
nothing here can see it. Measured 2026-10-08 on `claude` and `workstation` across
`/etc/sysctl.d /run/sysctl.d /usr/lib/sysctl.d /usr/local/lib/sysctl.d /lib/sysctl.d
/etc/sysctl.conf`: the only file setting the key is ours. `cruncher` not measured.

## Design

The rule both functions share: the **target** is `max(live, 1024)`, and the conf
needs writing when it is missing or its value is below the target. A conf above the
target is never touched.

### 1. Parser (`lib/helpers.sh:_inotify_conf_value`)

Match the key (either spelling, optional leading `-`, any whitespace around `=`)
with **any** right-hand side. Every matching line resets `val`: to the value when it
is `0` or a non-zero-led integer no greater than 2147483647 (the kernel's `INT_MAX`;
at most 10 digits, then compared numerically as `line + 0 <= 2147483647`; after
`sub()` the field is a string, so a bare `line <= 2147483647` compares as strings and
rejects `4096`), otherwise to empty. An empty
`val` at end of file prints nothing, so install and doctor already report the conf as
unparseable and "fix by hand". No caller changes.

### 2. Install step (`lib/linux_ubuntu.sh:_install_ubuntu_inotify`)

1. Skips (HAS_DOCKER, systemd dir): unchanged.
2. Classify the conf (unreadable or unparseable returns 1): unchanged.
3. Read live. Return 1 with **nothing written** when it is unreadable, is not `0` or a
   non-zero-led integer, or is longer than 10 digits, or is above 2147483647. The
   length check comes first: bash arithmetic wraps, so a 20-digit value reads as 0. This moves the existing check earlier, because the target needs it.
4. Conf missing or below the target: write `fs.inotify.max_user_instances = <target>`,
   read back, and return 1 with `inotify: read-back mismatch` unless the read-back
   value equals the target. On success print `inotify: conf written (<target>)` when
   the conf was missing, or `inotify: persisted <target> to <path> (was <old value>)`
   when it existed.
5. Live at or above 1024: return 0 (prints "already" unless it just wrote).
6. Otherwise apply the conf value with `sysctl -w`.

Step 6 only runs when live is below 1024. The conf is then at least 1024 and above
live, so apply never lowers anything.

### 3. Doctor (`lib/helpers.sh:_doctor_check_inotify_limits`)

After the existing live and conf validation (which also gets the `INT_MAX` cap),
the first matching case wins:

- Conf missing: FAIL `<path> missing; next boot: kernel default`, then the `tee` line
  writing the target.
- Conf value below 1024: FAIL `<path> value <conf value> below 1024; next boot:
  <conf value>`, then the `tee` line writing the target. This wins over "below live"
  when both hold.
- In both FAIL cases, when live is below 1024, the `tee` line gets
  `&& sudo sysctl -w fs.inotify.max_user_instances=1024` appended.
- Conf value below live (so live is above 1024): WARN, not FAIL, `<path> value
  <conf value> below live <live>; a reboot may drop it`, then the `tee` line writing
  the live value. A WARN does not fail doctor: a deliberate temporary raise, or a
  later-sorting drop-in that already persists the value, is not a broken host.
- Live below 1024: unchanged (`sudo sysctl -w ...=<conf value>`).
- Otherwise pass.

### 4. sysctl seam

`_install_ubuntu_inotify` runs `"${_SYSCTL_BIN}" -w ...` **without** sudo when
`_SYSCTL_BIN` is set and non-empty, and `sudo sysctl -w ...` when it is not. When the
seam is set, a failure prints `inotify: apply failed (_SYSCTL_BIN set, ran without
sudo)`. The unset branch is otherwise untested, because `load_mocks` always sets the
seam. One test unsets it and puts a `sysctl` stub first on `PATH`. The stub writes a
unique marker line. The test asserts `command -v sysctl` resolves to the stub before
the run, and asserts the marker after it, because `tests/mocks/sysctl` logs an
identical line and then execs `/usr/sbin/sysctl` (`tdd.md` E2). The test sets live
below 1024, or apply never runs.

### Docs

- CLAUDE.md `setup` entry: "persists the higher of the live value and 1024, never
  lowering a higher conf value or live value; a drop-in sorting before `90-` is
  overridden at boot".
- ADR-0044: add a dated Consequences note with the same known limit. Its title stays,
  qualified by that note.
- CLAUDE.md Test Seams `_SYSCTL_*` bullet: the sysctl seam runs without sudo.
- Delete Backlog rows 180-183; add one row for the `_SYSCTL_CONF` shape (N4).

## Testing

All in `tests/setup_env/linux_ubuntu.bats` and `tests/setup_env/unit.bats`, through the
existing seams. Every case asserting an absence also asserts a positive outcome.

- Parser: `= 2048` then `= abc` is unparseable in both install and doctor; `= 2048`
  then an empty right-hand side is unparseable; `= abc` then `= 2048` reads 2048.
- Install:
  - conf absent, live 4096: writes 4096 and applies nothing (replaces the test that
    pins 1024).
  - conf 1024, live 4096: rewrites the conf to 4096 and prints
    `persisted 4096 to <path> (was 1024)`.
  - conf 8192, live 4096: conf byte-identical, prints `already`.
  - conf 512, live 2048: writes 2048.
  - conf absent, live 128: writes and applies 1024.
  - conf absent, live unreadable: rc 1, stderr `cannot read live value`, conf absent.
  - live 2147483648: rc 1, conf absent.
  - live 18446744073709551616 (20 digits, wraps to 0): rc 1, conf absent.
  - live 2147483647, conf absent: rc 0, conf holds 2147483647, `conf written (2147483647)`.
  - conf `3000000000`: rc 1, stderr `unparseable`, conf byte-identical.
  - a tee that writes 1024 when the target is 4096: rc 1 and stderr
    `read-back mismatch`.
- Doctor:
  - conf missing, live 4096: `tee` with 4096 and no `sysctl -w`.
  - conf missing, live 128: `tee` with 1024 plus the `sysctl -w` half.
  - conf 1024, live 4096: WARN naming `value 1024 below live 4096`, `tee` with 4096,
    and `run_doctor` still exits 0 with only this finding.
  - conf 512, live 4096: FAIL naming `value 512 below 1024`, not `below live`;
    `tee` with 4096 and no `sysctl -w`.
  - conf missing: FAIL message contains `next boot: kernel default`.
  - conf 8192, live 4096: PASS.
  - conf `3000000000`: FAIL `unparseable; fix by hand`, no `tee` line.
- Seam: with `_SYSCTL_BIN` set and live 128, the log has the stub's `sysctl -w` line
  and no `sudo` line; with it unset and the PATH stub, the marker is present and the
  log has `sudo sysctl -w`.
- Mutation controls, each must turn a test red: drop the `val = ""` reset; replace the
  target with 1024; compare the conf only against 1024; raise the cap to 9999999999; compare the cap as a string in awk;
drop the live length check;
swap the "below 1024" and "below live" order; make the below-live case FAIL; drop the
`live < 1024`
  condition on the doctor suffix; always use sudo.

## Requirements

- **R1.** `[PR1]` `_inotify_conf_value` prints the value of the last line assigning `fs.inotify.max_user_instances` (dotted or slash spelling, optional leading `-`), and prints nothing when that last right-hand side is not `0` or a non-zero-led integer no greater than 2147483647, including empty.
- **R2.** `[PR1]` `_install_ubuntu_inotify` returns 1 without writing the conf or applying when the live value is unreadable, not `0`/a non-zero-led integer, longer than 10 digits, or above 2147483647, whatever the conf state.
- **R3.** `[PR1]` When the conf is missing or its value is below `max(live, 1024)`, `_install_ubuntu_inotify` writes `fs.inotify.max_user_instances = <max(live, 1024)>`, returns 1 printing `read-back mismatch` when the read-back value differs from that number, and on success prints the written value, plus the previous value when a conf existed.
- **R4.** `[PR1]` `_install_ubuntu_inotify` applies only when the live value is below 1024; runs `"${_SYSCTL_BIN}" -w` without sudo when `_SYSCTL_BIN` is non-empty and `sudo sysctl -w` otherwise; and names `_SYSCTL_BIN` in the failure message when the seam was set.
- **R5.** `[PR1]` `_doctor_check_inotify_limits` FAILs when the conf is missing (message names `next boot: kernel default`) or its value is below 1024 (message names the value and that it is next boot's value, and wins over below-live), and WARNs, not FAILs, when the conf value is at least 1024 but below live (`a reboot may drop it`); each prints a `tee` line writing `max(live, 1024)`, followed by `&& sudo sysctl -w fs.inotify.max_user_instances=1024` only when the live value is below 1024.
- **R6.** `[PR1]` CLAUDE.md's `setup` entry and Test Seams bullet describe R3 and R4 and the known limit; ADR-0044 carries a dated Consequences note with the known limit; Backlog rows 180-183 are deleted and one row is added for N4.
- **V1.** After merge, on `claude`: `-t doctor` passes the inotify check, and the step prints `inotify: already 1024 or higher` with `/etc/sysctl.d/90-dotfiles-inotify.conf` byte-identical before and after. This is a no-regression check only; R3-R5 are evidenced by V2.
- **V2.** `make test` passes; each mutation in Testing turns at least one test red.
- **N1.** No change to the unreadable/unparseable "fix by hand" path or its messages.
- **N2.** No shared `_inotify_conf_state` helper (Backlog :325 stays open).
- **N3.** No path writes a conf value lower than the live value or lower than the existing conf value, and no path applies a value lower than the live value.
- **N4.** No change to `sudo tee "${_conf}"` when `_SYSCTL_CONF` is set; that shape gets its own Backlog row.
- **N5.** No change to `fs.inotify.max_user_watches` or any other key.
- **N6.** The conf file is not renamed, and no file other than `${_conf}` is written or removed.

## Multi-Lens Review

Round 1 reviewed at commit: `2fcd878e` (spec as first written; Step 7 found nothing to fix). History, not current findings.

### Goal-Fit

Finding: (1) The claim that ADR-0044's title "becomes true" is false. Once
`90-dotfiles-inotify.conf` exists at 1024 (both hosts today), a later `50-` drop-in at
4096 is applied at boot, then overridden by our `90-` file; the step only consults live
when our conf is missing or below 1024, so it never re-checks. N3 is scoped to writes,
so no R/N pair catches it. Suggests fixing rows 180/183 and treating 181/182 as a
wording fix. (2) The read-back test ("tee writes 1024, target 4096") expects rc 1,
which an empty parser also produces via "unparseable"; it must assert the read-back
message. (3) V1 exercises only the unchanged "already" branch: a no-regression check,
not evidence for R3-R5.
Assumption: that a drop-in raising the key will ever appear on fleet hosts. Settle with
`grep -rl max_user_instances` over every sysctl.d directory on each host.
Disposition: Addressed (operator, 2026-10-08) — option B: live compared against an existing conf; known limit named in Decision, CLAUDE.md and ADR-0044; read-back test asserts its message; V1 relabelled no-regression.

### Ergonomics

Finding: (1) "Persist the live value" never fires on an existing host. The realistic
event is a hand raise (`sudo sysctl -w ...=4096`) after our 1024 conf exists: the step
prints "already", doctor passes on the live value, and the next boot drops to 1024
silently. Fix: in the conf-present case, when live exceeds the conf, rewrite the conf
(install) or fail with a `tee` remedy (doctor). (2) Minor: with `_SYSCTL_BIN` set the
call runs without sudo, and a real-host failure says only "apply failed"; name the
seam in the message.
Assumption: that a value hand-raised after the conf exists is meant to survive reboot.
A question for the operator.
Disposition: Addressed (operator, 2026-10-08) — option B covers the hand raise; seam failure message names `_SYSCTL_BIN`.

### Risk

Finding: (1) Same as Goal-Fit (1), plus a second exposure: once the step writes
`max(live, 1024)` into `90-`, any later raise in an earlier-sorting file is shadowed at
boot. (2) The seam test cannot tell which `sysctl` ran: the `load_mocks` stub,
`tests/mocks/sysctl` and the planned PATH stub log identical lines, and
`tests/mocks/sysctl` execs `/usr/sbin/sysctl`. If the stub directory sits behind
`tests/mocks` on PATH, the real binary runs and the log assertion still passes (E2; as
root it changes the live kernel). Fix: the stub writes a unique marker, and the test
asserts `command -v sysctl` resolves to the stub. The case must also set live below
1024, or apply never runs. (3) The live check has no length cap while the read-back
caps at 10 digits; an 11-digit fixture leaves an "unparseable" conf behind. Not
reachable on a real kernel (int max 2147483647). (4) "No sudo line" and "conf does not
exist" are absence checks; each needs a positive companion.
Assumption: that no file sorting after `90-`, or in `/run/sysctl.d` or
`/usr/local/lib/sysctl.d`, sets the key. Measured 2026-10-08 on `claude` and
`workstation` over `/etc/sysctl.d /run/sysctl.d /usr/lib/sysctl.d
/usr/local/lib/sysctl.d /lib/sysctl.d /etc/sysctl.conf`: the only hit is our own
`90-dotfiles-inotify.conf:1` at 1024, live 1024. `cruncher` not measured.
Disposition: Addressed (operator, 2026-10-08) — (1) option B plus stated known limit; (2) marker stub plus `command -v` assertion, live below 1024; (3) 10-digit cap on live; (4) positive companions on absence checks.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.

## Multi-Lens Review — round 2

Reviewed at commit: `006a5308` (option B revision). All three lenses re-ran.

### Goal-Fit

Finding: (1) The doctor "below live" branch says `next boot drops to <conf>`, which
holds only when no file sorting after `90-` sets the key. An operator who persists a
raise in `/etc/sysctl.d/99-local.conf` gets a doctor FAIL with a false message on a
correctly configured host, and install copies the value into our conf, creating a
second owner that N3 then forbids lowering. Measured 2026-10-08 with
`systemd-analyze cat-config sysctl.d` on `claude` and `workstation`: our `90-` file is
the last loaded and neither host has `/etc/sysctl.conf` or `99-sysctl.conf`, so the
message is true on both today. (2) Option B's cost for states no host has reached;
recorded operator choice, not reopened.
Assumption: that live above our conf means the raise is unpersisted. Settle per host
with `systemd-analyze cat-config sysctl.d | grep -n max_user_instances`.
Disposition: Addressed (operator, 2026-10-08) — below-live is a WARN reading `a reboot may drop it`; the second-owner case stays under the accepted cost.

### Ergonomics

Finding: (1) A persisted hand raise prints the same `inotify: conf written` as a
first write; it should name the value and the previous one. (2) Doctor FAILs (exit
non-zero) on a deliberate temporary raise until it is made permanent; "live above
conf" is drift, suggest WARN. (3) The label is unspecified when two cases hold (conf
512, live 4096), and `<conf>` in the message must be the value, not the path. (4) The
`missing` and `below 1024` messages do not say what happens at next boot.
Assumption: that nothing raises the key at runtime (k3s, LXD, a snap, a unit). Grep
of systemd unit and snap trees on `claude` found no writer.
Disposition: Addressed (operator, 2026-10-08) — install names the persisted and previous values; below-live is a WARN; below-1024 wins the label and messages carry the value; missing and below-1024 messages name next boot.

### Risk

Finding: (1) The 10-digit cap admits values the kernel rejects: `INT_MAX` is
2147483647, so a conf of `3000000000` parses, is "never touched", fails at boot
(live 128), and every run then applies a value the kernel refuses (EINVAL): rc 1
forever with a remedy that cannot work. Cap parser and live read at 2147483647 so it
lands in N1's "fix by hand". Pre-existing, repeated by round 1. (2) Same two-case
label gap as Ergonomics (3). R×N clean; edge-value walk agrees between install and
doctor; the seam test's failing branch is inert unless run as root.
Assumption: that live above 1024 is an operator's deliberate raise, not a privileged
molecule container writing the global key. No terraform_ansible role sets it; live on
`claude` is 1024 after molecule runs.
Disposition: Addressed (operator, 2026-10-08) — parser and live read capped at 2147483647; label order fixed (below 1024 wins).

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.

## Multi-Lens Review — round 3 (scoped, Risk only)

Reviewed at commit: `30732a3a`, scoped to the round-2 changes.

### Risk

Finding: (1) After `sub()` the awk field is a string, so `line <= 2147483647` compares
as strings and rejects `4096`/`8192`; the spec must say `line + 0`. (2) R2 dropped the
live length guard; bash arithmetic wraps (`$((18446744073709551616))` is 0), so a
20-digit seam value would pass as 0. Seam-only. (3) "live 2147483647 is accepted" had
no positive assertion. Verified clean: `doctor_warn` never sets `_DOCTOR_FAILED`
(`run_doctor` exit stays 0); install and doctor agree on every requested pair; R×N
clean; no test reaches `/etc` or the kernel. Applied to the spec text at `a3a699da`.
Assumption: that a live value above 1024 is an operator raise, not molecule/k3s/LXD.
Settle with `cat /proc/sys/fs/inotify/max_user_instances` and a writer grep per host.
Disposition: Addressed (operator, 2026-10-08) — `line + 0` cap, live length check before arithmetic, positive assertion on the 2147483647 case.
