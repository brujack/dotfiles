# Molecule host tuning: persist the inotify instance limit

- **Date:** 2026-10-08
- **Status:** Approved
- **Approved:** 2026-10-08

## Problem

The terraform_ansible session runs its molecule matrix in parallel
(`ansible/Makefile:70`, `PARALLEL_JOBS ?= 6`, consumed by `parallel --jobs`). It
measured two things on the Linux hosts and asked dotfiles to persist the result:

- At the kernel default `fs.inotify.max_user_instances = 128`, 15 of its 32 molecule
  scenarios fail at 18 parallel jobs; at 1024, none fail. (The ansible session's
  measurement, on `claude`; not re-measured here.)
- Its full matrix drops from 692s to 319s at `PARALLEL_JOBS=18` on `claude`; it
  settled on 12 for `workstation`. (Same source.)

Measured here on 2026-10-08, the premise this design rests on:

```
claude       fs.inotify.max_user_instances = 128   /etc/sysctl.d: README.sysctl only   sudo -n: ok
workstation  fs.inotify.max_user_instances = 128   /etc/sysctl.d: README.sysctl only   sudo -n: ok
workstation  systemd-sysctl active; /usr/lib/sysctl.d/30-localsearch.conf sets max_user_watches only
both         no max_user_instances key in /usr/lib/sysctl.d, /etc/sysctl.d or /etc/sysctl.conf
both         rootful docker; in terraform_ansible's [github_runner] group (claude 12, workstation 6)
cruncher     unreachable (ssh refused) -- WSL2 boot behaviour unmeasured
```

Nothing in dotfiles writes `/etc/sysctl.d` today
(`git grep -n -i 'sysctl\|inotify'` hits only the macOS CPU probe and its mock).

### Scope change after review

The original design also exported a per-host `PARALLEL_JOBS` from
`.config/.zshrc.d/5_general.zsh`. Round 1 showed that mechanism reaches only shells
started after merge (the ansible session on `workstation` had been up ~6 days and
keeps its launch environment), reaches no editor- or cron-started push, and goes live
at merge while the sysctl changes only on the next setup run, recreating the measured
18-jobs-at-128 failure. The per-host default moves to terraform_ansible's own
`ansible/Makefile`, read on every `make`, where it can also check the live limit before
choosing a high value. That change is the ansible session's, handed off by message; it
is not part of this spec's PR.

## Design

### Consumers and sizing

Two loads draw on root's single `max_user_instances` budget, because docker is rootful
and container processes run as host uid 0: the CI runners (`claude` 12, `workstation`
6, provisioned by terraform_ansible) and the ansible session's local matrix. The 1024
figure was measured for one 18-job matrix on `claude`; whether it covers a matrix plus
busy runners together is **not measured**. The ansible session will count root's
inotify instances during a concurrent run after this lands; if 1024 proves short, the
constant is the one place to raise it. Placing the limit in dotfiles rather than in
terraform_ansible's `github_runner` role was weighed in round 2 and chosen by the
operator.

### 1. Persist the limit (`lib/linux_ubuntu.sh`)

- `lib/constants.sh` gains `readonly INOTIFY_MAX_USER_INSTANCES=1024`.
- New step `inotify`, **first** in `install_ubuntu_packages`' step loop, so `-t setup`
  and `-t developer` reach it and no later step's failure can skip it. (Only base
  returning 1, an unsupported release, stops the run before the loop.)
- Function `_install_ubuntu_inotify`:
  - **Gate.** Returns 0, printing one skip line naming the reason, unless `HAS_DOCKER`
    is set and `${_SYSTEMD_RUN_DIR:-/run/systemd/system}` is a directory. A sysctl.d
    file persists across reboot only where systemd-sysctl runs at boot; WSL2 without
    systemd (`cruncher` carries `HAS_DOCKER`) is skipped, and stays at its default with
    no signal from dotfiles: an accepted, stated gap.
  - **Conf value.** Parsed as the **last** assignment of `fs.inotify.max_user_instances`
    (or its `/`-separated spelling, optional leading `-`), whitespace around `=`
    ignored, as systemd-sysctl reads it.
  - **Write** only when the conf does not exist (`! -e`), or exists, parses, and holds a
    value below 1024. A conf that exists but cannot be read or parsed is never
    overwritten: rc 1, "exists but unreadable/unparseable; fix by hand". So a raise the
    operator wrote in any spelling, or under a tighter mode, survives. Content written:
    `fs.inotify.max_user_instances = 1024`, via `sudo tee <conf> >/dev/null`.
  - **Read-back** after any write. Unreadable conf → rc 1, "cannot read back <conf>".
    Parsed value not `>= 1024` → rc 1, "write failed". The read-back is the check, not
    tee's rc: `tests/mocks/tee` swallows failures.
  - **Apply** `sudo sysctl -p <conf>` only when the live value (from `_INOTIFY_PROC`,
    gated on `^[0-9]+$`) is below 1024 or non-numeric. Never applies when live is
    already `>= 1024`, so a higher live value is never lowered, even when the step just
    wrote the file. Failure → rc 1, "apply failed".
  - **Boot ordering.** The file is named `90-` so it sorts after the packaged
    `/usr/lib/sysctl.d` files (`10-` to `55-` on these hosts). A later-sorting file that
    sets the key lower would win at boot and nothing here detects it; neither host has
    one today (measured), and this is a stated gap.
  - Prints one line saying what it did: `inotify: conf written`, `inotify: applied`,
    `inotify: already 1024 or higher`, so the operator's run shows the step acted.
  - The loop names `inotify` as a failed step on rc 1; `install_ubuntu_packages`
    returns 2 and the run continues, like every other step.
- Seams, all with production defaults:
  - `_SYSCTL_CONF` — default `/etc/sysctl.d/90-dotfiles-inotify.conf`.
  - `_SYSCTL_BIN` — default `sysctl` (`tests/mocks/sysctl` execs the real binary).
  - `_INOTIFY_PROC` — default `/proc/sys/fs/inotify/max_user_instances`.
  - `_SYSTEMD_RUN_DIR` — default `/run/systemd/system`.

### 2. Doctor check (`lib/helpers.sh`)

`_doctor_check_inotify_limits`, called from `run_doctor`, reading the same four seams:

- Silent unless `LINUX`, `HAS_DOCKER` and the systemd directory are all present.
- Live value unreadable or non-numeric → `doctor_fail` "cannot read <path>".
- Conf missing, unreadable, or parsed value not `>= 1024` → `doctor_fail`, then the fix
  printed on its own indented line:
  `printf 'fs.inotify.max_user_instances = 1024\n' | sudo tee /etc/sysctl.d/90-dotfiles-inotify.conf && sudo sysctl -p /etc/sysctl.d/90-dotfiles-inotify.conf`
- Conf `>= 1024`, live below 1024 → `doctor_fail`, then on its own line
  `sudo sysctl -p /etc/sysctl.d/90-dotfiles-inotify.conf`.
- Otherwise `doctor_pass` with the live value. A conf or live value above 1024 passes.

Neither remedy is `-t developer`, a full package install for one kernel key. The check
exists because the step runs only on setup/developer, and `-t update` deliberately does
not write `/etc` (N2).

## Testing

- **Isolation by default.** `load_mocks` (`tests/helpers/common.bash`) exports the four
  seams for every file that calls it, the same shape as its `_OVERRIDE_CLAUDE_SETTINGS`
  default: `_SYSCTL_CONF` under `BATS_TEST_TMPDIR` (absent), `_INOTIFY_PROC` a fixture
  holding `1024`, `_SYSTEMD_RUN_DIR` a fixture directory, and `_SYSCTL_BIN` a stub under
  `BATS_TEST_TMPDIR` that appends `sysctl <args>` to `MOCK_CALLS_FILE`. This covers
  `workflows.bats:584`, which runs the real `install_ubuntu_packages` without stubs, and
  both subprocess `-t doctor` tests in `unit.bats`, none of which a per-file `setup()`
  export would reach. `workflows.bats`, `linux_ubuntu.bats`, `unit.bats` and
  `plugin_node_paths.bats` all call `load_mocks`.
- Tests that reach the real step (`workflows.bats:584`, `linux_ubuntu.bats:331`, `:345`
  and the clean-run test at `:4464`) set or unset `HAS_DOCKER` themselves, so the branch
  taken does not depend on the shell running the suite. The two `eval` step lists at
  `linux_ubuntu.bats:331`/`:345` gain `inotify` and their count assertion moves 12 to 13.
- `_stub_ubuntu_steps` (`tests/setup_env/workflows.bats`) gains
  `_install_ubuntu_inotify() { :; }`; every stub-by-name `run_doctor` test
  (`unit.bats`, `plugin_node_paths.bats`) gains `_doctor_check_inotify_limits() { :; }`.
- Step cases (each asserts status, the conf content, and the recorded sysctl calls):
  - conf absent, live 128 → conf holds the line; sysctl called `-p <conf>`; prints written + applied.
  - conf absent, live 4096 → conf written; **no** sysctl call.
  - conf `key=1024` (no spaces), live 1024 → unchanged, no call, prints `already`.
  - conf `= 4096`, live 4096 → unchanged, no call, prints `already`.
  - conf `fs/inotify/max_user_instances = 4096`, and conf with `= 512` then `= 4096` → unchanged.
  - conf exists, mode 000 → rc 1 "unreadable", conf untouched; conf with no parseable key → rc 1, untouched.
  - conf `= 512` → rewritten to 1024.
  - conf right, live 128 → no write, sysctl called.
  - conf right, live non-numeric (and live file missing) → sysctl called.
  - write fails via `MOCK_TEE_EXIT=1` → rc 1 "write failed", no sysctl call.
  - tee exits 0 but writes nothing (a `SHIM_DIR` tee shim) → rc 1 "write failed".
  - read-back cannot read the written conf (a `SHIM_DIR` tee shim that writes then `chmod 000`) → rc 1 "cannot read back".
  - sysctl fails → rc 1 "apply failed".
  - `HAS_DOCKER` unset; systemd dir absent → rc 0, skip line, no write, no call.
- Loop: inotify returns 1 → `inotify` in the failed list, rc 2, the next step still runs;
  and inotify is the first step called.
- Doctor (`unit.bats`, `LINUX` exported per test, seams from `load_mocks`): pass at 1024
  and at 4096; live-low fail with the `sysctl -p` line on its own line; conf missing,
  conf 512 and conf unreadable fail with the `tee` line; live non-numeric fails "cannot
  read"; silent (status 0, no output) when `LINUX`, `HAS_DOCKER` or the systemd dir is
  absent.

## Verification (post-merge, on the real hosts)

Order matters: run the step **before** any doctor run or manual fix, or V1 cannot tell
the code from a hand-pasted fix. No interactive shell is needed: sourcing
`setup_env.sh` never runs its brew check, and `detect_env` sets `HAS_DOCKER` from the
hostname.

```bash
cd ~/git-repos/personal/dotfiles && git pull --ff-only -q && bash -c 'source ./setup_env.sh; detect_env; _install_ubuntu_inotify'
ssh workstation 'cd ~/git-repos/personal/dotfiles && git pull --ff-only -q && bash -c "source ./setup_env.sh; detect_env; _install_ubuntu_inotify"' < /dev/null
```

Precondition on each host: the checkout is on `master` with `git status --porcelain`
empty; otherwise stop and ask the operator. Each must print `inotify: conf written` and `inotify: applied`. Then on each host:
`sysctl fs.inotify.max_user_instances` → 1024 and `./setup_env.sh -t doctor` → inotify
PASS. Persistence across reboot rests on systemd-sysctl reading `/etc/sysctl.d` at boot;
no reboot is scheduled to prove it.

## Requirements

- **R1.** `[PR1]` `lib/constants.sh` defines `INOTIFY_MAX_USER_INSTANCES=1024`.
- **R2.** `[PR1]` `_install_ubuntu_inotify` is the first step in `install_ubuntu_packages`' step loop.
- **R3.** `[PR1]` `_install_ubuntu_inotify` writes `fs.inotify.max_user_instances = 1024` to `${_SYSCTL_CONF:-/etc/sysctl.d/90-dotfiles-inotify.conf}` only when the conf does not exist or its last parsed value is below 1024; returns 1 without writing when the conf exists but cannot be read or parsed; and returns 1 when a read-back after a write cannot read the file or finds a value below 1024.
- **R4.** `[PR1]` `_install_ubuntu_inotify` runs `sysctl -p <conf>` under sudo only when the live value read from `_INOTIFY_PROC` is below 1024 or not a non-negative integer, and returns 1 when that call fails.
- **R5.** `[PR1]` `_install_ubuntu_inotify` returns 0 without writing or applying, and prints a skip line, when `HAS_DOCKER` is unset or `${_SYSTEMD_RUN_DIR:-/run/systemd/system}` is not a directory.
- **R6.** `[PR1]` `_doctor_check_inotify_limits` is silent unless `LINUX`, `HAS_DOCKER` and the systemd directory are all present; fails "cannot read" on a non-numeric live value; fails and prints the `sudo tee ... && sudo sysctl -p` line on its own line when the conf is missing, unreadable or below 1024; fails and prints `sudo sysctl -p <conf>` on its own line when the live value is below 1024; passes any conf and live value >= 1024; and never names `-t developer`.
- **R7.** `[PR1]` `load_mocks` in `tests/helpers/common.bash` exports `_SYSCTL_CONF`, `_SYSCTL_BIN`, `_INOTIFY_PROC` and `_SYSTEMD_RUN_DIR` pointing under `BATS_TEST_TMPDIR`; `_stub_ubuntu_steps` stubs `_install_ubuntu_inotify`; every stub-by-name `run_doctor` test stubs `_doctor_check_inotify_limits`.
- **V1.** After merge, the step run on `claude` and over ssh on `workstation`, before any doctor run, prints `inotify: conf written` and `inotify: applied`; then `sysctl fs.inotify.max_user_instances` reports 1024 and `-t doctor` passes the inotify check on both.
- **V2.** `make test` passes on `claude` from a shell that exports `HAS_DOCKER=1` and from one that does not.
- **N1.** No change to `fs.inotify.max_user_watches` or any other sysctl.
- **N2.** No sysctl write from `-t update` or `-t setup_user`.
- **N3.** No `PARALLEL_JOBS` export or default anywhere in dotfiles; that default belongs to terraform_ansible's `ansible/Makefile`.
- **N4.** The step never lowers a live value or a conf value that is already above 1024.

## Amendments

- R4 -> `_install_ubuntu_inotify` runs `sysctl -w fs.inotify.max_user_instances=<conf value>` under sudo only when the live value read from `_INOTIFY_PROC` is a non-negative integer below 1024; returns 1 without applying when the live value cannot be read or is not an integer; and returns 1 when the apply fails. — plan non-goal check: `sysctl -p` applies every key in a kept conf (N1), and applying on an unreadable live value could lower a real value above 1024 (N4).
- R6 -> `_doctor_check_inotify_limits` is silent unless `LINUX`, `HAS_DOCKER` and the systemd directory are all present; fails "cannot read" on a non-numeric live value; fails and prints the `sudo tee ... && sudo sysctl -w fs.inotify.max_user_instances=1024` line on its own line when the conf is missing, unreadable or below 1024; fails and prints `sudo sysctl -w fs.inotify.max_user_instances=<conf value>` on its own line when the live value is below 1024; passes any conf and live value >= 1024; and never names `-t developer`. — same reason as R4: the remedies must touch only this key.
- R6 -> `_doctor_check_inotify_limits` is silent unless `LINUX`, `HAS_DOCKER` and the systemd directory are all present; fails "cannot read" on a live value that is not `0` or a non-zero-led integer; fails and prints the `sudo tee ... && sudo sysctl -w fs.inotify.max_user_instances=1024` line on its own line only when the conf is missing or parses below 1024; fails with "fix by hand" and no `tee` line when the conf exists but is unreadable or unparseable; fails and prints `sudo sysctl -w fs.inotify.max_user_instances=<conf value>` on its own line when the live value is below 1024; passes any conf and live value >= 1024; and never names `-t developer`. — Task 2 code review: the earlier R6 prescribed `tee` over a conf the install step deliberately refuses to touch (N4), which would erase any other key in it.
- finding R4 (2026-10-08, reviewer A): DIFFERS — The apply path matches (sudo `${_bin}` -w with the conf value, only below 1024, rc 1 on apply failure, rc 1 on unreadable or non-numeric live), but the integer test at lib/linux_ubuntu.sh:106 is `^(0|[1-9][0-9]*)$` after stripping all whitespace, so a leading-zero live value such as `08` (a non-negative integer below 1024, which R4 says to apply) instead returns 1 without applying (test 'a leading-zero live value returns 1 and applies nothing'); R6 states that stricter definition for doctor, R4 does not.
- R4 -> `_install_ubuntu_inotify` runs `sysctl -w fs.inotify.max_user_instances=<conf value>` under sudo only when the live value read from `_INOTIFY_PROC` is `0` or a non-zero-led integer below 1024; returns 1 without applying when the live value cannot be read or is any other form (a leading zero such as `08` included); and returns 1 when the apply fails. — Phase 3 maintainability fix aligned the install step's live-value rule with doctor's (amended R6); bash reads `08` as invalid octal, so accepting it would compare wrongly.

## Multi-Lens Review

Reviewed at commit: `a341e58c` (Step 7 self-review commit, before Step 8 dispatch)

### Goal-Fit

Finding: (1) Section 3 goes live in every new shell at merge, while the sysctl changes only on the next setup/developer run, so `claude` runs 18 jobs against limit 128: the measured failing configuration. Gate the export on the live value. (2) N3 rules out putting the per-host default in terraform_ansible's own `ansible/Makefile`, with no mechanism given; there it would reach every actor and sit next to its consumer. (3) Name who runs the matrix on `claude`. (4) An empty or non-numeric `_INOTIFY_PROC` read compares as 0; gate on `^[0-9]+$`. (5) V2 run from a shell that inherited the variable passes regardless; no case covers the ordering in (1).
Assumption: the 15/32 failures at 18 jobs are `max_user_instances` exhaustion, not `max_user_watches`, docker contention or memory. Refute by running the matrix at 18 on the default limit and grepping failed logs for `inotify_init`/`EMFILE`.
Disposition: Addressed (operator 2026-10-08: "terraform_ansible Makefile", "Address all"). Section 3 removed; the PARALLEL_JOBS default, including the live-limit gate of (1), moves to terraform_ansible's Makefile (N3 now says why). (3) moot with it. (4) `^[0-9]+$` gate added to step and doctor. (5) V2 replaced. The assumption (failures are instance exhaustion) rests on the ansible session's measurement and was not re-run here.

### Ergonomics

Finding: (1) Long-lived sessions keep their launch environment (the Bash tool sources a frozen snapshot; the ansible session on workstation is ~6 days old), so the export reaches nothing until relaunch from a fresh shell; the spec's mechanism sentence is wrong. (2) V2 checks a fresh shell, not the consumer process. (3) Doctor's remedy names `-t developer`, a 10+ minute full install; name the direct one-line apply instead. (4) "Source and call" over ssh leaves `HAS_DOCKER` unset, so the step silently returns 0. (5) N2 means routine `update` never applies it. (6) `_OVERRIDE_HOSTNAME` needs a Test Seams entry.
Assumption: the matrix runs from a process started after merge. Check `/proc/<ansible session pid>/environ` for `PARALLEL_JOBS` after merge. (Orchestrator check: `sudo -n true` succeeds on `claude` and `workstation`.)
Disposition: Addressed (same operator answers). (1)(2)(6) moot: no shell export, no `_OVERRIDE_HOSTNAME`. (3) Doctor names the one-line `tee`/`sysctl -p` fix, never `-t developer`. (4) Skip now prints its reason; verification calls `detect_env` first. (5) N2 kept: presented to the operator as accepted, with doctor plus the one-line fix covering hosts that only run `update`; the operator's answers did not change it.

### Risk

Finding: (1) HIGH: `_stub_ubuntu_steps` (`tests/setup_env/workflows.bats:715`) stubs 13 steps by name and not the new one, and dev shells export `HAS_DOCKER=1`, so the real step runs with production paths: `make test` goes red on `claude`, green in CI. `linux_ubuntu.bats:4464` exports `HAS_DOCKER=1` explicitly. Set the three seams at `setup()` scope and add the step to the stub list. (2) The "would set the live kernel value" claim is wrong as uid 1000; the real hazard is `tests/mocks/tee` swallowing failures. Verify the write by reading the file back; drive write failure with `MOCK_TEE_EXIT`. (3) WSL2 (`cruncher`) carries `HAS_DOCKER`; without systemd in WSL the conf is never applied at boot and doctor fails after every restart. (4) Unreadable `/proc` read reports "below target"; give it its own message. (5) Raising workstation from 6 to 12 adds docker contention next to its 6 live runners; the measurement covers wall time, not runner interference.
Assumption: `HAS_DOCKER` hosts run systemd-sysctl at boot. Holds on `workstation`; unknown on `cruncher` (ssh refused 2026-10-08, so unmeasured).
Disposition: Addressed (same operator answers). (1) Seams at `setup()` scope and `_stub_ubuntu_steps` entry (R6, V2). (2) Mechanism sentence corrected; read-back added; write-failure cases name `MOCK_TEE_EXIT` and a tee that writes nothing. (3) Install and doctor gated on `/run/systemd/system`. (4) Own "cannot read" message. (5) Moves with PARALLEL_JOBS to terraform_ansible; presented to the operator as accepted (12 is the ansible session's measured choice).

### Adversarial Spec Review (comparison/judge designs only)

N/A: spec has no comparison/evaluator/ambiguous-criteria trigger.

### Round 2

Reviewed at commit: `9c960590` (round 1 revisions). All three lenses re-ran; the round 1 section above is history.

#### Goal-Fit (round 2)

Finding: (1) The limit's steady consumer is the CI runner fleet (`claude` 12, `workstation` 6, both in terraform_ansible's `[github_runner]` group), which terraform_ansible already provisions and whose roles already use `ansible.posix.sysctl`; the spec never weighed putting the limit there. (2) Problem section names only the ansible session's local matrix. (3) Doctor duplicates the live-limit check the Makefile gate will make on every run. (4) Doctor "silent" cases pass for an undefined function unless they assert status.
Assumption: 1024 covers runners plus a local matrix sharing root's budget (rootful docker); unmeasured.
Disposition: Accepted, reason: operator chose "Keep in dotfiles, fix round 2" (2026-10-08) over moving the limit to the `github_runner` role. (2) Addressed: "Consumers and sizing" names both loads and the open sizing question. (4) Addressed: silent cases assert status 0 and no output.

#### Ergonomics (round 2)

Finding: (1) Verification wrongly required an interactive shell; plain `bash -c` and `ssh` work (measured both hosts). (2) A hand-pasted doctor fix before the snippet makes V1 unable to tell the code ran. (3) The fix command sits mid-line in doctor output. (4) Exact-line match rejects `key=1024`. (5) Step position unspecified; a failed earlier step could skip it.
Assumption: 1024 suffices on `workstation` at 12 jobs beside 6 runners; unmeasured. (The lens's claim that `claude` carries no runners is wrong: 13 `Runner.Listener` processes and 12 instances in the inventory.)
Disposition: Addressed (operator "Keep in dotfiles, fix round 2"). (1) ssh form given, interactive rationale dropped. (2) Order stated; step prints what it did and V1 checks that output. (3) Remedy on its own line. (4) Value parsed, whitespace ignored. (5) First in the loop (R2).

#### Risk (round 2)

Finding: (1) MEDIUM: `workflows.bats:584` runs the real `install_ubuntu_packages` unstubbed; seams only in `linux_ubuntu.bats` leave it reaching production paths, green as uid 1000, live as root. (2) MEDIUM: exact `= 1024` enforcement lowers a higher live limit and fails a deliberate raise. (3) Doctor tests and two subprocess `-t doctor` tests read real `/proc`. (4) Unreadable read-back reported as "write failed". (5) Step position, the tee-writes-nothing shim, and WSL's silent gap unstated.
Assumption: same sizing question as above.
Disposition: Addressed (operator "Keep in dotfiles, fix round 2"). (1)(3) Seam defaults moved into `load_mocks`, covering every file that calls it (R7). (2) Write only when absent or below 1024; apply only when live is below 1024; doctor passes >= 1024 (N4). (4) Own "cannot read back" message. (5) First in loop; `SHIM_DIR` tee shim named; WSL gap stated.

### Round 3 (scoped: Risk only, Design/Testing/Verification/Requirements)

Reviewed at commit: `63d6cd31` (round 2 revisions).

Finding: (1) An unreadable conf, or a raise spelled with `/`, a leading `-` or a duplicate key, parses as "not >= 1024" and is overwritten to 1024, breaking N4. (2) The boot value comes from the merged sysctl.d set; a later-sorting file setting the key lower defeats the step, and doctor's remedy lasts one boot. Not present on either host. (3) The premise table had the localsearch row on the wrong host. (4) claude's verification line never pulls; no guard on a dirty or non-master checkout. (5) V2 cannot fail: the sudo mock never escalates. (6) Tests reaching the real step inherit `HAS_DOCKER` from the shell; the `linux_ubuntu.bats:331/345` step lists omit `inotify`; no-op cases should assert the `already` line; `tee` echoes to stdout.
Assumption: 1024 covers root's budget under matrix plus busy runners; unmeasured; the lens named a root-count command.
Disposition: Addressed within the operator's "Keep in dotfiles, fix round 2" scope (orchestrator-applied; operator confirms at spec review). (1) Write only when absent or parsed below 1024; existing unreadable/unparseable conf gives rc 1 and is never overwritten; last assignment and `/`/`-` spellings parsed. (2) File renamed `90-`; gap stated. (3) Table corrected. (4) claude line pulls; precondition stated. (5) V2 replaced with a suite run both with and without `HAS_DOCKER`. (6) Explicit `HAS_DOCKER` in the four tests; lists to 13; `already` asserted; `tee >/dev/null`. Review stops here: the corrections removed surface (no rewrite of existing confs) and the remaining findings are test apparatus.

## Spec alignment (2026-10-08)

- spec: docs/superpowers/specs/2026-10-08-molecule-host-tuning-design.md
- anchor: a4cd7b77b80b4c2cc1a41da5aeb41c1fab5c97f2
- in scope: R1, R2, R3, R4, R5, R6, R7
- out of scope: none

### Findings

| ID | Reviewer | Verdict | Reason | Amendment |
| --- | --- | --- | --- | --- |
| R4 | A | DIFFERS | The apply path matches (sudo `${_bin}` -w with the conf value, only below 1024, rc 1 on apply failure, rc 1 on unreadable or non-numeric live), but the integer test at lib/linux_ubuntu.sh:106 is `^(0\|[1-9][0-9]*)$` after stripping all whitespace, so a leading-zero live value such as `08` (a non-negative integer below 1024, which R4 says to apply) instead returns 1 without applying (test 'a leading-zero live value returns 1 and applies nothing'); R6 states that stricter definition for doctor, R4 does not. | - R4 -> `_install_ubuntu_inotify` runs `sysctl -w fs.inotify.max_user_instances=<conf value>` under sudo only when the live value read from `_INOTIFY_PROC` is `0` or a non-zero-led integer below 1024; returns 1 without applying when the live value cannot be read or is any other form (a leading zero such as `08` included); and returns 1 when the apply fails. — Phase 3 maintainability fix aligned the install step's live-value rule with doctor's (amended R6); bash reads `08` as invalid octal, so accepting it would compare wrongly. |

### Reviewed

- none

### Verifications

- V1: pending: post-merge run on claude and workstation (spec Verification section)
- V2: make test at ea40719e: 1..2675 ok=2675 not ok=0 EXIT=0 with HAS_DOCKER=1 and with env -u HAS_DOCKER
