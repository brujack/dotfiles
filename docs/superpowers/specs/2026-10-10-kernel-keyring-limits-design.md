# Kernel keyring limits on docker hosts

- **Date:** 2026-10-10
- **Requested by:** the terraform_ansible session (cross-session message, 2026-10-10)
- **Operator:** approved starting the work and changing live sysctl on `claude` and `workstation`

## Problem

terraform_ansible#209's CI leg `users:docker` (run 38069910125, job 114265671453, runner
`claude` r12) failed at container start:

```
runc create failed: ... unable to join session keyring: unable to create session key: disk quota exceeded
```

That is the per-uid kernel keyring quota. The rootless `docker-ci` daemon runs every CI
container as `github-runner`, so every container's session keyring counts against one uid.
The 30-runner fleet (terraform_ansible#208) running a full matrix exhausted it.

Measured 2026-10-10 from this session, by reading `/proc/sys/kernel/keys/*` and
`/proc/key-users` on each host directly (the population is exactly the two runner hosts):

| host          | maxkeys | maxbytes | github-runner uid | idle keys | idle bytes |
| ------------- | ------- | -------- | ----------------- | --------- | ---------- |
| `claude`      | 200     | 20000    | 995               | 37/200    | 956/20000  |
| `workstation` | 200     | 20000    | 997               | 29/200    | 762/20000  |

Both hosts run the kernel defaults. Nothing in dotfiles sets either key today.
`gc_delay` is 300, so a dead container's keys count for five minutes after it exits.

Idle usage is ~26 bytes per key, so at the defaults the key count (200, ~5.2 KB) is reached
about 4x before the byte cap. That ratio is an **idle** figure and understates the CI case:
runc names each container session keyring `_ses.<64-hex id>`, charged at about 70 bytes per
key (the ansible session's figure, from the name length plus terminator). At 2000 keys that
is ~140 KB, only 1.4x under a 10x byte cap of 200000, so bytes would bind almost as soon as
keys. `maxbytes` is therefore raised to 500000, keeping ~3.5x headroom over 2000 keys at 70
bytes each. No peak sample from a full matrix exists yet (see V3). `kernel.keys.maxkeys`/`maxbytes` apply to non-root uids only
(root has `root_maxkeys`, 1000000 here), and `github-runner` is non-root, so these are the
keys that bind.

## Decision

Raise `maxkeys` 10x and `maxbytes` 25x on docker hosts, persisted in `/etc/sysctl.d/`, using the same
mechanism that already persists `fs.inotify.max_user_instances`
(`_install_ubuntu_inotify`, `_doctor_check_inotify_limits`; specs
`2026-10-08-molecule-host-tuning-design.md`, `2026-10-08-inotify-followups-design.md`,
`2026-10-09-inotify-seam-crlf-dedup-design.md`).

| key                    | floor  | conf file                                      |
| ---------------------- | ------ | ---------------------------------------------- |
| `kernel.keys.maxkeys`  | 2000   | `/etc/sysctl.d/90-dotfiles-keys-maxkeys.conf`  |
| `kernel.keys.maxbytes` | 500000 | `/etc/sysctl.d/90-dotfiles-keys-maxbytes.conf` |

**One key per file, deliberately.** Every guard in the inotify step assumes its conf holds
exactly one key: the write is a whole-file `tee`, and the step refuses any conf holding a
line it does not own (default-deny, added after bug-scan on #324 found the whole-file write
deleting another key). A two-key file would make raising one key a rewrite that must
preserve the other key's value, which is a new way to destroy a setting that none of that
hardening covers. Two files keep the invariant and cost only a second file name.

Alternatives rejected: one two-key file (the destruction surface above); a copy of the
inotify step for keys (~250 lines duplicated, every future fix made twice).

terraform_ansible's `github_runner` role will add a preflight that fails below these floors
and names these two files as the fix. It does not set the sysctl itself, the same contract
as inotify.

## Design

### Shared helpers (`lib/helpers.sh`)

The four inotify helpers lose their inotify-specific names and take the key as a parameter.
Their logic is unchanged.

| today                                 | becomes                                    |
| ------------------------------------- | ------------------------------------------ |
| `_inotify_read_live <path>`           | `_sysctl_read_live <path>`                 |
| `_inotify_conf_value <conf>`          | `_sysctl_conf_value <conf> <key>`          |
| `_inotify_conf_has_nontext <conf>`    | `_sysctl_conf_has_nontext <conf>`          |
| `_inotify_conf_has_other_keys <conf>` | `_sysctl_conf_has_other_keys <conf> <key>` |

The dotted and slash spellings both helpers accept are derived from `<key>` (`.` -> `/`).
`INOTIFY_INT_MAX` becomes `SYSCTL_INT_MAX`; `kernel.keys.maxkeys` and `maxbytes` are `int`
in the kernel too, so the same cap holds. No compatibility aliases for the old names.

### Step (`lib/linux_ubuntu.sh`)

The body of `_install_ubuntu_inotify` moves into
`_sysctl_floor_step <label> <key> <floor> <conf> <proc> <conf_seamed>`, and
`_inotify_conf_write` into `_sysctl_conf_write <label> <key> <value> <conf> <conf_seamed>`.
`<label>` prefixes every message (`inotify:` stays `inotify:`). `<conf_seamed>` is 1 when
the caller's conf path came from a test seam, and selects a plain `tee` over `sudo tee`,
as `_SYSCTL_CONF` does today. `_SYSCTL_BIN` keeps selecting the unprivileged apply for
every caller.

- `_install_ubuntu_inotify` keeps its name and becomes a single call.
- New `_install_ubuntu_keyring` calls the step for `maxkeys`, then `maxbytes`. Both are
  always attempted; it returns 1 if either returned non-zero. The `HAS_DOCKER` and systemd
  skip lines print once, under the `keyring:` label.
- The Ubuntu step list gains `keyring` directly after `inotify`.

Every rule the inotify step enforces holds per key, unchanged: persist `max(live, floor)`;
never lower a higher conf or live value; refuse ("fix by hand") an unreadable, unparseable,
non-text or other-key conf; read the file back and compare; apply live with
`sysctl -w <key>=<value>` only when live is below the floor; never `sysctl -p`/`--system`.

### Doctor (`lib/helpers.sh`)

The body of `_doctor_check_inotify_limits` moves into
`_doctor_sysctl_floor <label> <key> <floor> <conf> <proc>`; the inotify check keeps its
header and becomes a single call. New `_doctor_check_keyring_limits` prints
`kernel keyring limits:` and checks both keys with the same PASS/WARN/FAIL rules and
remedies. It is registered in `run_doctor` directly after the inotify check, under the same
gate (`LINUX`, `HAS_DOCKER`, systemd).

### Constants (`lib/constants.sh`)

`KEYS_MAXKEYS=2000`, `KEYS_MAXBYTES=500000`, `KEYS_MAXKEYS_CONF`, `KEYS_MAXBYTES_CONF`,
`KEYS_MAXKEYS_PROC=/proc/sys/kernel/keys/maxkeys`,
`KEYS_MAXBYTES_PROC=/proc/sys/kernel/keys/maxbytes`, all `readonly`, with a comment pointing
at this spec.

### Test seams

`_SYSCTL_CONF` and `_INOTIFY_PROC` name one file each and cannot address two keys, so each
key gets its own: `_KEYS_MAXKEYS_CONF`, `_KEYS_MAXKEYS_PROC`, `_KEYS_MAXBYTES_CONF`,
`_KEYS_MAXBYTES_PROC`. `load_mocks` exports all four under `BATS_TEST_TMPDIR` (confs absent,
procs seeded at the kernel defaults 200 and 20000), as it already does for inotify, because
`tests/mocks/sudo` execs real commands and an unset seam would aim `tee` at the real
`/etc/sysctl.d` (`tdd.md` E2).

## Testing

- The existing inotify tests stay green with only helper renames applied; no inotify
  assertion changes. That is the evidence the extraction preserved behaviour.
- Keyring step: each key below the floor (written and applied), at the floor (no write, no
  apply), above it (conf persists the live value, no apply); a higher existing conf is kept;
  one key's conf refused while the other key is still written; rc 1 when either fails;
  skip lines under `HAS_DOCKER` unset and no systemd.
- `sysctl -w` receives exactly `kernel.keys.maxkeys=<v>` / `kernel.keys.maxbytes=<v>`, one
  call per key that is below the floor, and never `-p` or `--system`.
- Doctor: both keys reported; a below-floor or missing conf FAILs and prints a remedy
  naming that key's own file; a conf holding the other keyring key is refused as "other keys".
- `install_ubuntu_packages` runs `keyring` after `inotify`.

## Requirements

- **R1.** `[PR1]` `_install_ubuntu_keyring` persists `kernel.keys.maxkeys` to `/etc/sysctl.d/90-dotfiles-keys-maxkeys.conf` with value `max(live, 2000)`.
- **R2.** `[PR1]` `_install_ubuntu_keyring` persists `kernel.keys.maxbytes` to `/etc/sysctl.d/90-dotfiles-keys-maxbytes.conf` with value `max(live, 500000)`.
- **R3.** `[PR1]` Each keyring conf file holds exactly one assignment, of its own key, in the form `<key> = <value>`.
- **R4.** `[PR1]` A live keyring value below its floor is raised with `sysctl -w <key>=<value>` for that key only; a live value at or above the floor is not written to the kernel.
- **R5.** `[PR1]` An existing keyring conf whose value is at or above its target is not rewritten.
- **R6.** `[PR1]` A keyring conf that is unreadable, unparseable, holds non-text bytes, or holds any other key is refused with a "fix by hand" message and not written.
- **R7.** `[PR1]` `_install_ubuntu_keyring` processes both keys even when the first fails, and returns 1 when either fails.
- **R8.** `[PR1]` `_install_ubuntu_keyring` returns 0 without writing when `HAS_DOCKER` is unset or the systemd run directory is absent.
- **R9.** `[PR1]` The Ubuntu package step list runs `keyring` immediately after `inotify`.
- **R10.** `[PR1]` `_doctor_check_keyring_limits` reports both keys under the `inotify` gate conditions, using the same PASS/WARN/FAIL rules as the inotify check, and prints remedies naming each key's own conf file.
- **R11.** `[PR1]` The inotify step and doctor check are callers of the shared `_sysctl_floor_step` and `_doctor_sysctl_floor`; their output and behaviour are unchanged.
- **R12.** `[PR1]` `load_mocks` exports `_KEYS_MAXKEYS_CONF`, `_KEYS_MAXKEYS_PROC`, `_KEYS_MAXBYTES_CONF` and `_KEYS_MAXBYTES_PROC` under `BATS_TEST_TMPDIR`.
- **R13.** `[PR1]` `CLAUDE.md` documents the keyring step under `setup`/`developer`/`doctor` and the four new seams in Test Seams.
- **V1.** After merge, on `claude` and on `workstation`: run the keyring step, then `-t doctor`; both keys PASS and `/proc/sys/kernel/keys/maxkeys`/`maxbytes` read at least 2000/500000.
- **V2.** On one host, prove persistence without rebooting: lower a live value below its floor, restart `systemd-sysctl`, and read it back at the conf value.
- **V3.** After V1, compare the ansible session's peak `qnkeys`/`qnbytes` for `github-runner` from a full-matrix run against 2000/500000; if either reaches half its floor, open a follow-up to raise it.
- **V4.** The ansible session is told the two conf file names before its preflight lands.
- **N1.** No change to any inotify message text, floor, file path, or doctor verdict.
- **N2.** No `sysctl -p` or `sysctl --system` anywhere.
- **N3.** No keyring sysctl is set on macOS, or on a Linux host without `HAS_DOCKER` or systemd.
- **N4.** No step or doctor remedy writes a conf file holding a line for any key other than its own.
- **N5.** No compatibility aliases for the renamed `_inotify_*` helpers or `INOTIFY_INT_MAX`.
