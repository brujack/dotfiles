# Kernel keyring limits on docker hosts

- **Date:** 2026-10-10
- **Requested by:** the terraform_ansible session (cross-session message, 2026-10-10)
- **Approved:** 2026-10-10
- **Operator:** approved starting the work and changing live sysctl on `claude` and `workstation`

## Problem

terraform_ansible#209's CI leg `users:docker` (run 38069910125, job 114265671453, runner
`claude` r12) failed at container start:

```
runc create failed: ... unable to join session keyring: unable to create session key: disk quota exceeded
```

That is the per-uid kernel keyring quota. The rootless `docker-ci` daemon runs as
`github-runner`, so every key created by **root inside a CI container** is charged to that
one uid. (A process running as a non-root user inside a container is charged to its own
subuid instead; `/proc/key-users` on `claude` lists subuids 166537 and 2320xx with 2-6 keys
each. These floors raise those limits too, since the sysctl is global, but the failure here
is the container-root case.) The 30-runner fleet (terraform_ansible#208) running a full
matrix exhausted it.

Measured 2026-10-10 from this session, by reading `/proc/sys/kernel/keys/*` and
`/proc/key-users` on each host directly (the population is exactly the two runner hosts):

| host          | maxkeys | maxbytes | github-runner uid | idle keys | idle bytes |
| ------------- | ------- | -------- | ----------------- | --------- | ---------- |
| `claude`      | 200     | 20000    | 995               | 37/200    | 956/20000  |
| `workstation` | 200     | 20000    | 997               | 29/200    | 762/20000  |

Both hosts run the kernel defaults. Nothing in dotfiles sets either key today. No CI
container was running on either host when this was measured, so these are idle figures.

Idle usage is ~26 bytes per key, so at the defaults the key count (200, ~5.2 KB) is reached
about 4x before the byte cap. That ratio is an **idle** figure and understates the CI case:
runc names each container session keyring `_ses.<64-hex id>`, charged at about 70 bytes per
key (the ansible session's figure, from the name length plus terminator). At 2000 keys that
is ~140 KB, only 1.4x under a 10x byte cap of 200000, so bytes would bind almost as soon as
keys. `maxbytes` is therefore raised to 500000, keeping ~3.5x headroom over 2000 keys at 70
bytes each.

**Measured per-container cost.** Every one of terraform_ansible's 36 molecule docker
platforms runs `geerlingguy/docker-ubuntu2404-ansible` with systemd as PID 1, and systemd
gives each service its own session keyring, all charged to container root, i.e. this uid.
Probed 2026-10-10 on `claude` (operator-approved): one container started on the `docker-ci`
daemon with the molecule platform's own flags (`--privileged --cgroupns private`, the cgroup2
remount, `exec /lib/systemd/systemd`), booted to `degraded` in 2 s:

| sample                | uid 995 keys | bytes |
| --------------------- | ------------ | ----- |
| before                | 37           | 956   |
| booted (and +5 s)     | 46           | 1182  |
| removed (and +5 s)    | 37           | 956   |

So one booted container costs **9 keys and 226 bytes (~25 B/key)**, and its keys are
released the moment it is removed: no residue, no five-minute delay. That accounts for the
failure exactly: 37 idle + 18 runners x 9 = 199, against a limit of 200. At 2000 keys a
booted fleet uses ~199, about 10x headroom; at ~25 B/key, bytes stay far below 500000, so
keys bind first, not bytes. The probe covers a booted, unconverged container only: a role
that starts more services, and each `docker exec` an Ansible task makes, add keys. V3
measures that peak during a real matrix. The floors are minimums, so raising them later is a
constant change. `kernel.keys.maxkeys`/`maxbytes` apply to non-root uids only
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

**Gate.** The step runs where inotify's does: Ubuntu, `HAS_DOCKER` set, systemd present.
`HAS_DOCKER` is a stand-in for "runs the rootless CI runner daemon"; it also covers docker
hosts without runners (the wsl2 profile), where the raise is harmless.

**Getting it onto the running hosts.** The step runs inside `install_ubuntu_packages`,
reachable only from a full `-t setup` or `-t developer`, which also upgrades packages, docker
and nvidia and cannot run non-interactively on these hosts. The operator route for hosts
already provisioned is the doctor remedy: run `./setup_env.sh -t doctor`, paste the remedy
line it prints for each failing key (`printf '<key> = <v>\n' | sudo tee '<conf>' && sudo sysctl
-w <key>=<v>`), and re-run doctor. New hosts get it from the normal setup run.

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
Both helpers compare the key as an **exact string**: strip leading spaces and tabs and an
optional `-`, take the text before the first `=`, trim trailing spaces and tabs, and compare
it to the two spellings with `==`. Today's code is already correct here: the inotify regex
escapes its dots, and `_inotify_conf_has_other_keys` already compares with `==`. The rule
exists because the generic version must not build a regex from `<key>`, which would turn
every `.` into a wildcard and read a line such as `fsXinotify.max_user_instances = 5` as the
key while systemd-sysctl treats it as a different one.
`INOTIFY_INT_MAX` becomes `SYSCTL_INT_MAX`; `kernel.keys.maxkeys` and `maxbytes` are `int`
in the kernel too, so the same cap holds. No compatibility aliases for the old names.

### Step (`lib/linux_ubuntu.sh`)

The body of `_install_ubuntu_inotify` moves into
`_sysctl_floor_step <label> <key> <floor> <conf> <proc> <seam_name>`, and
`_inotify_conf_write` into `_sysctl_conf_write <label> <key> <value> <conf> <seam_name>`.
`<label>` prefixes every message (`inotify:` stays `inotify:`). `<seam_name>` is the name
of the caller's conf seam variable when that variable is set (`_SYSCTL_CONF` for inotify,
`_KEYS_MAXKEYS_CONF` / `_KEYS_MAXBYTES_CONF` for kernel keys), or empty when the conf is the
real path. Non-empty selects a plain `tee` over `sudo tee`, and is the name the write-failure
message prints, so the inotify text `inotify: write failed (%s; _SYSCTL_CONF set, ran without
sudo)` is unchanged. `_sysctl_floor_step` takes the same argument in place of
`<conf_seamed>`. `_SYSCTL_BIN` keeps selecting the unprivileged apply for
every caller. Each generic function carries a header comment naming its positional
arguments in order, since two are paths and two are numbers and a swap runs silently.

- `_install_ubuntu_inotify` keeps its name and becomes a single call.
- New `_install_ubuntu_kernel_keys` calls the step for `maxkeys`, then `maxbytes`, with
  labels `kernel-keys maxkeys:` and `kernel-keys maxbytes:`. Both are always attempted; it
  returns 1 if either returned non-zero. The `HAS_DOCKER` and systemd skip lines print once,
  under `kernel-keys:`. Not "keyring": in `lib/linux_ubuntu.sh` that word already means apt
  signing keyrings (`_install_apt_keyring`, `_build_pinned_keyring`, `nvidia: keyring:`).
- The Ubuntu step list gains `kernel_keys` directly after `inotify`.

Every rule the inotify step enforces holds per key, unchanged: persist `max(live, floor)`;
never lower a higher conf or live value; refuse ("fix by hand") an unreadable, unparseable,
non-text or other-key conf; read the file back and compare; apply live with
`sysctl -w <key>=<value>` only when live is below the floor; never `sysctl -p`/`--system`.

### Doctor (`lib/helpers.sh`)

The body of `_doctor_check_inotify_limits` moves into
`_doctor_sysctl_floor <label> <key> <floor> <conf> <proc>`; the inotify check keeps its
header and becomes a single call. New `_doctor_check_kernel_keys` prints
`kernel keys:` and checks both keys with the same PASS/WARN/FAIL rules and
remedies. It is called from `run_doctor` directly after the inotify check and carries the
same gate (`LINUX`, `HAS_DOCKER`, systemd) inside the function, as the inotify check does.

### Constants (`lib/constants.sh`)

`KEYS_MAXKEYS=2000`, `KEYS_MAXBYTES=500000`, `KEYS_MAXKEYS_CONF`, `KEYS_MAXBYTES_CONF`,
`KEYS_MAXKEYS_PROC=/proc/sys/kernel/keys/maxkeys`,
`KEYS_MAXBYTES_PROC=/proc/sys/kernel/keys/maxbytes`, all `readonly`, with a comment pointing
at this spec.

### Test seams

`_SYSCTL_CONF` and `_INOTIFY_PROC` name one file each and cannot address two keys, so each
key gets its own: `_KEYS_MAXKEYS_CONF`, `_KEYS_MAXKEYS_PROC`, `_KEYS_MAXBYTES_CONF`,
`_KEYS_MAXBYTES_PROC`. `_SYSCTL_CONF` keeps its name even though it governs only the inotify
conf: renaming it would edit ~150 inotify test lines and the inotify write-failure message,
and the extraction's evidence of preserved behaviour is that no inotify assertion changes.
The Test Seams entry in `CLAUDE.md` states which conf it governs. `_SYSCTL_BIN` is genuinely
shared.

`load_mocks` exports all four under `BATS_TEST_TMPDIR` because `tests/mocks/sudo` execs real
commands and an unset seam would aim `tee` at the real `/etc/sysctl.d` (`tdd.md` E2). The
confs start absent and the procs are seeded **at the floors** (2000 and 500000), exactly as
`_INOTIFY_PROC` is seeded at 1024. An absent conf is written whatever the live value, so the
seeding does not prevent writes; it prevents applies. Seeded at the kernel defaults, every
test that reaches the step would call the shared `_SYSCTL_BIN` stub twice, and a test setting
`MOCK_SYSCTL_STUB_EXIT` to fail one apply would fail these too.

`workflows.bats`' `_stub_ubuntu_steps` stubs every Ubuntu step by name so that "the ONLY
variable is the return code of the step under test"; `_install_ubuntu_kernel_keys` is added
to it. Two further hand-kept step lists name every step and must gain `kernel_keys`: the
"every later step runs when one fails, and names it" loop in `workflows.bats` and the
one-by-one stub test in `linux_ubuntu.bats` whose `grep -c '^ran '` count becomes 14.
Without them the real step runs, takes its `HAS_DOCKER`-unset skip, returns 0, and the
tests pass while saying nothing about it.

The end-to-end `run_doctor` tests stub every doctor sub-check by name (10 sites stub
`_doctor_check_inotify_limits() { :; }`, in `unit.bats` and `plugin_node_paths.bats`).
Each gains a `_doctor_check_kernel_keys() { :; }` stub. The check's gate reads `LINUX` and
`HAS_DOCKER` from the parent shell, which a developer shell on `claude` exports, so an
unstubbed check FAILs there and passes silently in CI, and `plugin_node_paths.bats`' "its
FAIL fails doctor" would pass even with the plugin check deleted. A test asserts the two
stub counts are equal.

## Testing

- The existing inotify tests stay green with only helper renames applied; no inotify
  assertion changes. That is the evidence the extraction preserved behaviour.
- Kernel-keys step: each key below the floor (written and applied), at the floor with no
  conf (conf written holding the floor, no apply), above it (conf persists the live value, no
  apply); a higher existing conf is kept (no write, no apply); one key's conf refused while the other key is still written; rc 1 when either fails;
  skip lines under `HAS_DOCKER` unset and no systemd.
- **Every "no write" or "no apply" case also asserts a positive control**, so a step that
  does nothing fails it: at-floor asserts the conf now exists holding the floor; a kept
  higher conf asserts its value is unchanged *and* the step printed its "already" line; a
  no-apply case asserts the `_SYSCTL_BIN` stub exists and is executable before asserting it
  recorded no call; the skip cases assert the skip line.
- A swap test: with only `maxbytes` below its floor, the write lands in `_KEYS_MAXBYTES_CONF`
  holding `kernel.keys.maxbytes = 500000`, and `_KEYS_MAXKEYS_CONF` is untouched.
- Near-miss keys, for each of the three keys: `_sysctl_conf_value` called directly on a
  conf holding only a line whose key differs from the real one by a `.` replaced with another
  character prints nothing. Called directly, because through the step the other-keys check
  refuses that line first, so a step-level test passes even against a wildcard regex.
- `sysctl -w` receives exactly `kernel.keys.maxkeys=<v>` / `kernel.keys.maxbytes=<v>`, one
  call per key that is below the floor, and never `-p` or `--system`.
- Doctor: both keys reported; a below-floor or missing conf FAILs and prints a remedy
  naming that key's own file; a conf holding the other kernel-keys key is refused as "other keys".
- `install_ubuntu_packages` runs `kernel_keys` after `inotify`.

## Requirements

- **R1.** `[PR1]` `_install_ubuntu_kernel_keys` persists `kernel.keys.maxkeys` to `/etc/sysctl.d/90-dotfiles-keys-maxkeys.conf` with value `max(live, 2000)`.
- **R2.** `[PR1]` `_install_ubuntu_kernel_keys` persists `kernel.keys.maxbytes` to `/etc/sysctl.d/90-dotfiles-keys-maxbytes.conf` with value `max(live, 500000)`.
- **R3.** `[PR1]` Each kernel-keys conf file holds exactly one assignment, of its own key, in the form `<key> = <value>`.
- **R4.** `[PR1]` A live kernel-keys value below its floor is raised with `sysctl -w <key>=<value>` for that key only; a live value at or above the floor is not written to the kernel.
- **R5.** `[PR1]` An existing kernel-keys conf whose value is at or above its target is not rewritten.
- **R6.** `[PR1]` A kernel-keys conf that is unreadable, unparseable, holds non-text bytes, or holds any other key is refused with a "fix by hand" message and not written.
- **R7.** `[PR1]` `_install_ubuntu_kernel_keys` processes both keys even when the first fails, and returns 1 when either fails.
- **R8.** `[PR1]` `_install_ubuntu_kernel_keys` returns 0 without writing when `HAS_DOCKER` is unset or the systemd run directory is absent.
- **R9.** `[PR1]` The Ubuntu package step list runs `kernel_keys` immediately after `inotify`, and `_stub_ubuntu_steps` stubs `_install_ubuntu_kernel_keys`.
- **R10.** `[PR1]` `_doctor_check_kernel_keys` reports both keys under the `inotify` gate conditions, using the same PASS/WARN/FAIL rules as the inotify check, and prints remedies naming each key's own conf file.
- **R11.** `[PR1]` The inotify step and doctor check are callers of the shared `_sysctl_floor_step` and `_doctor_sysctl_floor`; their output and behaviour are unchanged.
- **R12.** `[PR1]` `load_mocks` exports `_KEYS_MAXKEYS_CONF`, `_KEYS_MAXKEYS_PROC`, `_KEYS_MAXBYTES_CONF` and `_KEYS_MAXBYTES_PROC` under `BATS_TEST_TMPDIR`, with the procs seeded at 2000 and 500000.
- **R13.** `[PR1]` `CLAUDE.md` documents the kernel-keys step under `setup`/`developer`/`doctor`, the doctor-remedy route for provisioned hosts (paste one remedy line at a time), the four new seams, and that `_SYSCTL_CONF` governs only the inotify conf.
- **R14.** `[PR1]` `_sysctl_conf_value` and `_sysctl_conf_has_other_keys` match the key by exact string comparison against its dotted and slash spellings, never by a regex built from the key.
- **R15.** `[PR1]` Every `run_doctor` test that stubs `_doctor_check_inotify_limits` also stubs `_doctor_check_kernel_keys`, and a test asserts the two stub counts are equal.
- **R16.** `[PR1]` The `workflows.bats` failed-step loop and the `linux_ubuntu.bats` one-by-one stub test both include `kernel_keys`; the latter's expected run count is 14.
- **R17.** `[PR1]` Every operator-facing string, the doctor header and the knowledge-file name use the term "kernel keys", never "keyring".
- **V1.** After merge, on `claude` and on `workstation`: run `-t doctor`, paste the printed remedy for each failing kernel-keys key one line at a time, re-run doctor; both keys PASS and `/proc/sys/kernel/keys/maxkeys`/`maxbytes` read at least 2000/500000.
- **V2.** On one host, prove persistence without rebooting: lower a live value below its floor, restart `systemd-sysctl`, and read it back at the conf value.
- **V3.** After V1, during a full terraform_ansible matrix on `claude`, sample the `github-runner` row of `/proc/key-users` every second alongside the running container count, then again 5 minutes after the matrix drains. Record peak keys, peak bytes, keys per container and the drained count in `ai-config/docs/knowledge/dotfiles-kernel-keys-limits.md`. If peak keys or bytes reach half the floor, or the drained count stays above the pre-run idle count (a leak), open a follow-up.
- **V4.** The ansible session is told the two conf file names before its preflight lands.
- **N1.** No change to any inotify message text, floor, file path, seam name, or doctor verdict.
- **N2.** No `sysctl -p` or `sysctl --system` anywhere.
- **N3.** No kernel-keys sysctl is set on macOS, or on a Linux host without `HAS_DOCKER` or systemd.
- **N4.** No step or doctor remedy writes a conf file holding a line for any key other than its own.
- **N5.** No compatibility aliases for the renamed `_inotify_*` helpers or `INOTIFY_INT_MAX`.
- **N6.** No new `setup_env.sh` entry point (`-t` type) for applying sysctls.

## Multi-Lens Review

Reviewed at commit: `45f96015` (Step 7 self-review commit, before Step 8 dispatch)

### Round 1

#### Goal-Fit

Finding: Worth building; sysctl in dotfiles is the right lever (runc's `NoNewKeyring` would
not stop systemd's per-unit keyrings inside the container). The sizing model was wrong: all
36 molecule docker platforms run systemd as PID 1, so one container may hold tens of keys,
not one `_ses` keyring, and whether 2000 covers 18 runners is unmeasured. The `gc_delay`
"five minutes" claim is very likely false (unreferenced keys release quota at the last
`key_put`; `gc_delay` governs expired and revoked keys). V3's output had no durable home.
`HAS_DOCKER` is a stand-in for "runner host" and should be named as one.
Assumption: peak keys for uid 995 is bounded by concurrent work and sits under 2000. Refuted
by a full-matrix peak near 2000, or a drained count that stays above idle (a leak). Settled
by V3's sampling.
Disposition: Addressed. Sizing paragraph added; the floors stay at the agreed 2000/500000
and V3 now records peak, per-container and drained counts in a knowledge file (operator
chose "ship and measure"); `gc_delay` claim removed; `HAS_DOCKER` named as a stand-in.

#### Ergonomics

Finding: (1) No route onto the provisioned hosts except a full `-t setup`/`-t developer`.
(2) The `keyring` label collides with apt signing keyrings in `lib/linux_ubuntu.sh`.
(3) `_SYSCTL_CONF` reads as generic but names only the inotify conf. (4) Positional
arguments swap silently. (5) The no-write test cases pass for a step that does nothing.
(6) The `gc_delay` premise looked wrong.
Assumption: the charged uid is 995 (container root); a non-root container user would charge
a subuid row that doctor and V3 do not watch. Settled by V3's sampling of all rows.
Disposition: Addressed. Doctor-remedy route named, with V1 rewritten to use it; renamed to
`kernel-keys` / `_install_ubuntu_kernel_keys` / `_doctor_check_kernel_keys`; `_SYSCTL_CONF`
renamed `_INOTIFY_CONF` (R15); argument header comments plus a key-swap test; positive
controls on every no-write case; `gc_delay` claim removed; subuid charging stated in Problem.

#### Risk

Finding: (1) Seeding the test procs at the kernel defaults, below the floors, would make
every test that reaches the step write two confs and call the shared sysctl stub, and the
step was missing from `_stub_ubuntu_steps`. (2) A key regex built from the key name turns
`.` into a wildcard; no existing test pins that. (3) Kernel constraints: no blocker (`int`,
min 1, `SYSCTL_INT_MAX` cap; slash spelling accepted). (4) No conflicting conf on `claude`.
(5) Subuids exist in `/proc/key-users`; the one-uid claim holds only for container root.
(6) `gc_delay` claim probably wrong. (7) No widened write found. (8) The extraction is
proportionate.
Assumption: key load is bounded by concurrency, not a leak; the idle 37 could be residue.
Refuted by an idle count that rises run over run. Settled by V3's drained sample.
Disposition: Addressed. Procs seeded at the floors and the step added to
`_stub_ubuntu_steps` (R9, R12); exact-string key match (R14) with near-miss tests; subuid
note in Problem; `gc_delay` claim removed; leak check in V3.

### Round 2

Reviewed at commit: `0c7d073f`. All three lenses re-ran, told the round-1 section is history.

#### Goal-Fit

Finding: (1) The round-1 `_SYSCTL_CONF` -> `_INOTIFY_CONF` rename forces edits to inotify
assertions and the inotify write-failure message, which voids "no inotify assertion changes"
as the extraction's evidence. (2) Two hand-kept step lists (`workflows.bats` failed-step loop,
`linux_ubuntu.bats` one-by-one stub test, count 13) omit the new step and would still pass.
(3) The seeding rationale was half wrong: an absent conf is written either way.
Assumption: the idle 37 keys are a stable baseline, not a slow leak. Refuted by a daily
`/proc/key-users` sample rising over a week of CI.
Disposition: Addressed. Rename dropped (N1 now covers seam names); both lists gain
`kernel_keys` (R16); seeding rationale corrected. The probe below shows keys released the
moment a container is removed.

#### Ergonomics

Finding: (1) The doctor-remedy route works as written; paste one line at a time, as a sudo
prompt can swallow the second. (2) The 10 `run_doctor` stub sites do not stub the new check;
on a developer shell exporting `LINUX`/`HAS_DOCKER` it FAILs there and passes in CI.
(3) The inotify write-failure message names `_SYSCTL_CONF`; the generic write had no seam-name
argument. (4) Three names for one thing (kernel-keys, `KEYS_*`, "kernel keyring").
Assumption: peak keys for uid 995 under a full matrix stays under 2000. Settled in part by the
probe below; V3 settles the converged peak.
Disposition: Addressed. Stubs added with a count-equality test (R15); `<seam_name>` argument
keeps the inotify text identical; "kernel keys" in every operator-facing string (R17);
one-line-at-a-time in V1 and R13.

#### Risk

Finding: (1) R14 changes no parse outcome today (the inotify regex escapes its dots) and the
planned near-miss tests could not fail, because the other-keys check refuses those lines
first. (2) "At floor (no write)" contradicted its own positive control. (3) The `run_doctor`
stub gap, as above, with `plugin_node_paths.bats`' FAIL test passing for the wrong reason.
(4) The rename touched ~150 test lines and an asserted message. (5) No R/N contradiction and
no widened write. Residual: a later-sorting drop-in lowering a key would beat the 90- conf at
boot, the same accepted gap as inotify.
Assumption: per-container keys x 18 stays under 2000; suggested a one-container probe before
merge.
Disposition: Addressed. Near-miss tests call `_sysctl_conf_value` directly; at-floor wording
fixed; stubs and rename as above. Probe run with operator approval: 9 keys and 226 bytes per
booted container, released on removal; recorded in Problem.

Stopping after round 2 (operator decision): the round-2 findings sit in the test apparatus
(step lists, stub sites, seeding, a message string), and the one design change removed
surface (the rename) rather than adding mechanism.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.
