# Molecule host tuning: persist the inotify instance limit

- **Date:** 2026-10-08
- **Status:** Draft (revised after Step 8 round 1)

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
workstation  systemd-sysctl active; no inotify key in /usr/lib/sysctl.d or /etc/sysctl.conf
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

### 1. Persist the limit (`lib/linux_ubuntu.sh`)

- `lib/constants.sh` gains `readonly INOTIFY_MAX_USER_INSTANCES=1024`.
- New step `inotify` in `install_ubuntu_packages`' step loop, so `-t setup` and
  `-t developer` reach it. Function `_install_ubuntu_inotify`:
  - Returns 0 at once, printing one skip line naming the reason, unless `HAS_DOCKER`
    is set **and** `${_SYSTEMD_RUN_DIR:-/run/systemd/system}` is a directory. Molecule
    needs docker; a sysctl.d file only persists across reboot where systemd-sysctl runs
    at boot, which is not guaranteed on WSL2 (`cruncher` carries `HAS_DOCKER`). The
    printed reason keeps a skip from reading as success when the caller's environment
    lacks `HAS_DOCKER` (sourcing `setup_env.sh` does not run `detect_env`).
  - Desired content is one line: `fs.inotify.max_user_instances = 1024`.
  - Writes it (`sudo tee`) only when the file's content differs, then **reads the file
    back** and returns 1 ("write failed") unless it now holds exactly that line. The
    read-back is the check, not tee's rc: `tests/mocks/tee` swallows failures, and a
    silently failed write is what the step must not report as success.
  - Runs `sudo sysctl -p <conf>` when the file was written or the live value is below
    the target; returns 1 ("apply failed") when that fails.
  - The live value is read from `_INOTIFY_PROC` and gated on `^[0-9]+$`. An unreadable
    or non-numeric value is treated as "needs apply" (never as 0 in arithmetic), so the
    step applies rather than skips.
  - The loop names `inotify` as a failed step on rc 1; `install_ubuntu_packages` returns
    2 and the rest of the run continues, like every other step.
- Seams, all with production defaults:
  - `_SYSCTL_CONF` — default `/etc/sysctl.d/60-dotfiles-inotify.conf`.
  - `_SYSCTL_BIN` — default `sysctl`. `tests/mocks/sysctl` execs the real
    `/usr/sbin/sysctl`; a test must observe the call, not depend on it failing.
  - `_INOTIFY_PROC` — default `/proc/sys/fs/inotify/max_user_instances`.
  - `_SYSTEMD_RUN_DIR` — default `/run/systemd/system`.

### 2. Doctor check (`lib/helpers.sh`)

`_doctor_check_inotify_limits`, called from `run_doctor`:

- Returns 0 without output unless `LINUX`, `HAS_DOCKER` and the systemd directory are
  all present (same gate as the install step).
- Live value unreadable or non-numeric → `doctor_fail` "cannot read <path>" (its own
  message; never "below target").
- Conf missing or not exactly the desired line → `doctor_fail` naming the one-line fix:
  `printf 'fs.inotify.max_user_instances = 1024\n' | sudo tee /etc/sysctl.d/60-dotfiles-inotify.conf && sudo sysctl -p /etc/sysctl.d/60-dotfiles-inotify.conf`.
- Conf right, live value below 1024 → `doctor_fail` naming
  `sudo sysctl -p /etc/sysctl.d/60-dotfiles-inotify.conf`.
- Otherwise `doctor_pass` showing the live value.

Neither remedy is `-t developer`: that is a full package install for one kernel key.
The doctor check exists because the install step runs only on setup/developer; a host
that has not re-run since merge stays at 128 with nothing naming it, and `-t update`
deliberately does not write `/etc` (N2).

## Testing

- `tests/setup_env/linux_ubuntu.bats` exports `_SYSCTL_CONF`, `_SYSCTL_BIN`,
  `_INOTIFY_PROC` and `_SYSTEMD_RUN_DIR` at **`setup()` scope**, pointing at fixtures
  and a recording sysctl stub, so every test in the file is isolated, including the
  existing "clean run, every step real" case that exports `HAS_DOCKER=1`.
- `_stub_ubuntu_steps` in `tests/setup_env/workflows.bats` gains
  `_install_ubuntu_inotify() { :; }`. Without it, a dev shell's exported `HAS_DOCKER=1`
  runs the real step there and the suite goes red locally and green in CI.
- Step cases:
  - conf absent, live 128 → conf holds exactly the line; sysctl called with `-p <conf>`.
  - conf identical, live 1024 → conf unchanged (mtime too), no sysctl call.
  - conf identical, live 128 → no write, sysctl called.
  - conf with a different value → rewritten and applied.
  - live value non-numeric, conf identical → sysctl called.
  - write fails (`MOCK_TEE_EXIT=1`, and separately a tee that "succeeds" without
    writing) → rc 1, stderr names the write, no sysctl call.
  - sysctl fails → rc 1, stderr names the apply.
  - `HAS_DOCKER` unset → rc 0, skip line on output, conf untouched, no sysctl call.
  - systemd dir absent → rc 0, skip line, no write, no call.
- Loop: inotify step failing → `inotify` named in the failed list, rc 2, later steps run.
- Doctor (`tests/setup_env/unit.bats`): pass; live-low fail with the `sysctl -p`
  remedy; conf-missing and conf-wrong fail with the `tee` remedy; unreadable live value
  fails with "cannot read"; silent when `LINUX`, `HAS_DOCKER` or the systemd dir is
  absent. Every end-to-end `run_doctor` test that stubs sub-checks by name stubs this one.

## Verification (post-merge, on the real hosts)

On `claude` and `workstation`, from an interactive shell (so `HAS_DOCKER` and brew's
`PATH` are present):

```bash
bash -c 'source ./setup_env.sh; detect_env; _install_ubuntu_inotify'
sysctl fs.inotify.max_user_instances    # expect 1024
cat /etc/sysctl.d/60-dotfiles-inotify.conf
./setup_env.sh -t doctor                # inotify check PASS
```

Persistence across reboot rests on systemd-sysctl reading `/etc/sysctl.d` at boot, which
is standard on both hosts; no reboot is scheduled to prove it, and that is stated rather
than claimed.

## Requirements

- **R1.** `[PR1]` `lib/constants.sh` defines `INOTIFY_MAX_USER_INSTANCES=1024`.
- **R2.** `[PR1]` `install_ubuntu_packages`' step loop calls `_install_ubuntu_inotify`, which writes `fs.inotify.max_user_instances = 1024` to `${_SYSCTL_CONF:-/etc/sysctl.d/60-dotfiles-inotify.conf}` only when the file's content differs, and returns 1 unless a read-back afterwards finds exactly that line.
- **R3.** `[PR1]` `_install_ubuntu_inotify` runs `sysctl -p <conf>` under sudo when it wrote the file or the live value read from `_INOTIFY_PROC` is below 1024 or not a non-negative integer, and not otherwise; it returns 1 when that call fails.
- **R4.** `[PR1]` `_install_ubuntu_inotify` returns 0 without writing or applying, and prints a skip line, when `HAS_DOCKER` is unset or `${_SYSTEMD_RUN_DIR:-/run/systemd/system}` is not a directory.
- **R5.** `[PR1]` `_doctor_check_inotify_limits` is silent unless `LINUX`, `HAS_DOCKER` and the systemd directory are all present; it fails with "cannot read" on a non-numeric live value, fails naming the `sudo tee ... && sudo sysctl -p` line when the conf is missing or wrong, fails naming `sudo sysctl -p <conf>` when the live value is below 1024, and never names `-t developer`.
- **R6.** `[PR1]` `tests/setup_env/linux_ubuntu.bats` exports `_SYSCTL_CONF`, `_SYSCTL_BIN`, `_INOTIFY_PROC` and `_SYSTEMD_RUN_DIR` in `setup()`, and `_stub_ubuntu_steps` stubs `_install_ubuntu_inotify`.
- **V1.** After merge, on `claude` and `workstation`, `sysctl fs.inotify.max_user_instances` reports 1024 and `-t doctor` passes the inotify check.
- **V2.** `make test` passes on `claude` from a shell that exports `HAS_DOCKER=1`.
- **N1.** No change to `fs.inotify.max_user_watches` or any other sysctl.
- **N2.** No sysctl write from `-t update` or `-t setup_user`.
- **N3.** No `PARALLEL_JOBS` export or default anywhere in dotfiles; that default belongs to terraform_ansible's `ansible/Makefile`.

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
