# Molecule host tuning: inotify instances and PARALLEL_JOBS

- **Date:** 2026-10-08
- **Status:** Draft

## Problem

The terraform_ansible session runs its molecule matrix in parallel
(`ansible/Makefile:70`, `PARALLEL_JOBS ?= 6`, consumed by `parallel --jobs`). It
measured two things on the Linux hosts and asked dotfiles to persist the result:

- At the kernel default `fs.inotify.max_user_instances = 128`, 15 of its 32 molecule
  scenarios fail at 18 parallel jobs; at 1024, none fail. (The ansible session's
  measurement, on `claude`; not re-measured here.)
- Its full matrix drops from 692s to 319s at `PARALLEL_JOBS=18` on `claude`. It
  re-measured `workstation` and settled on 12 there. (Same source.)

Measured here on 2026-10-08, the premise this design rests on:

```
claude       fs.inotify.max_user_instances = 128   nproc 48   /etc/sysctl.d: README.sysctl only
workstation  fs.inotify.max_user_instances = 128   nproc 32   /etc/sysctl.d: README.sysctl only
workstation  PARALLEL_JOBS unset in a non-interactive ssh shell
```

Nothing in dotfiles writes `/etc/sysctl.d` or sets `PARALLEL_JOBS` today
(`git grep -n -i 'sysctl\|PARALLEL_JOBS\|inotify'` hits only the macOS CPU probe and
its mock). `claude` and `workstation` share profile `linux_workstation` and legacy
variable `WORKSTATION` (`config/profiles.sh`), so no existing variable distinguishes
them; a per-host value needs the hostname.

## Design

### 1. Persist the inotify limit (`lib/linux_ubuntu.sh`)

- `lib/constants.sh` gains `readonly INOTIFY_MAX_USER_INSTANCES=1024`.
- New step `inotify` in `install_ubuntu_packages`' step loop, so `-t setup` and
  `-t developer` reach it. Function `_install_ubuntu_inotify`:
  - Returns 0 at once unless `HAS_DOCKER` is set. Molecule needs docker; the limit is
    raised only where the workload that exhausts it can run.
  - Desired content is one line: `fs.inotify.max_user_instances = 1024`.
  - Writes it to the conf file (`sudo tee`) only when the file's content differs.
  - Runs `sudo sysctl -p <conf>` when the file was written **or** the live value is
    below the target, so a host whose file is right but which never applied it is
    repaired without a reboot.
  - Returns 1 when the write or the apply fails, naming which on stderr. The loop then
    names `inotify` as a failed step and `install_ubuntu_packages` returns 2, like every
    other step; the rest of the run continues.
- Seams, all with production defaults:
  - `_SYSCTL_CONF` — default `/etc/sysctl.d/60-dotfiles-inotify.conf`.
  - `_SYSCTL_BIN` — default `sysctl`. Required, not optional: `tests/mocks/sysctl`
    execs the real `/usr/sbin/sysctl` for anything but the macOS CPU query, and
    `tests/mocks/sudo` execs its command for real, so an unseamed test would set the
    live kernel value on the machine running the suite (`tdd.md` E2).
  - `_INOTIFY_PROC` — default `/proc/sys/fs/inotify/max_user_instances`, the live value.

### 2. Doctor check (`lib/helpers.sh`)

`_doctor_check_inotify_limits`, called from `run_doctor`:

- Returns 0 without output unless `LINUX` and `HAS_DOCKER` are both set.
- `doctor_fail` when the live value (read via `_INOTIFY_PROC`) is below
  `INOTIFY_MAX_USER_INSTANCES`, or when the conf file (via `_SYSCTL_CONF`) is absent or
  does not hold the desired line. The message names `./setup_env.sh -t developer`.
- `doctor_pass` otherwise, showing the live value.
- Every end-to-end `run_doctor` test that stubs sub-checks by name stubs this one too,
  so none reads the real `/proc` value mid-suite.

The doctor check exists because the install step only runs when someone runs setup or
developer; a host that has not re-run since this merged stays at 128 with nothing
naming it.

### 3. PARALLEL_JOBS per host (`.config/.zshrc.d/5_general.zsh`)

```zsh
if [[ -z ${PARALLEL_JOBS} ]]; then
  case "${_OVERRIDE_HOSTNAME:-$(hostname -s)}" in
    claude) export PARALLEL_JOBS=18 ;;
    workstation) export PARALLEL_JOBS=12 ;;
  esac
fi
```

- Only when unset, so a value already in the environment, or a per-run
  `make … PARALLEL_JOBS=n`, still wins (a command-line make variable overrides the
  environment regardless).
- Every other host leaves it unset and the Makefile's own `?= 6` applies.
- Interactive zsh only. Agent shells inherit it, because the harness initialises its
  Bash tool from the user's profile; cron, `ssh host '<cmd>'` and launchd do not, and
  that is acceptable: the matrix is run from a session shell.
- A hostname table rather than a `HAS_*` capability, because this is per-host tuning
  measured on two specific machines, not a capability a profile grants.

## Testing

- `tests/setup_env/linux_ubuntu.bats`, with all three seams pointed at fixtures and a
  recording `_SYSCTL_BIN` stub:
  - conf absent, live 128 → conf written with the exact line, sysctl `-p <conf>` called.
  - conf identical, live 1024 → no write, no sysctl call.
  - conf identical, live 128 → no write, sysctl called.
  - conf with a different value → rewritten and applied.
  - write fails → rc 1, message names the write; sysctl failure → rc 1, message names
    the apply.
  - `HAS_DOCKER` unset → rc 0, conf untouched, no sysctl call.
  - `install_ubuntu_packages` with the inotify step failing → `inotify` named in the
    failed list, rc 2, later steps still called.
- `tests/setup_env/unit.bats` doctor tests: pass; live-low fail; conf-missing fail;
  conf-wrong fail; silent when `LINUX` unset; silent when `HAS_DOCKER` unset.
- `tests/zshrc.d/unit.bats`: claude → 18; workstation → 12; other host → unset;
  pre-set `PARALLEL_JOBS=5` on claude → still 5.

## Verification (post-merge, on the real hosts)

On `claude` and on `workstation`:

```bash
./setup_env.sh -t developer          # or source and call _install_ubuntu_inotify
sysctl fs.inotify.max_user_instances # expect 1024
cat /etc/sysctl.d/60-dotfiles-inotify.conf
./setup_env.sh -t doctor             # inotify check PASS
zsh -i -c 'echo $PARALLEL_JOBS'      # 18 on claude, 12 on workstation
```

## Requirements

- **R1.** `[PR1]` `lib/constants.sh` defines `INOTIFY_MAX_USER_INSTANCES=1024`.
- **R2.** `[PR1]` `install_ubuntu_packages`' step loop calls `_install_ubuntu_inotify`, which writes `fs.inotify.max_user_instances = 1024` to `${_SYSCTL_CONF:-/etc/sysctl.d/60-dotfiles-inotify.conf}` only when the file's content differs.
- **R3.** `[PR1]` `_install_ubuntu_inotify` runs `sysctl -p <conf>` under sudo when it wrote the file or the live value read from `_INOTIFY_PROC` is below 1024, and not otherwise.
- **R4.** `[PR1]` `_install_ubuntu_inotify` returns 0 without writing or applying when `HAS_DOCKER` is unset, and returns 1 naming the failed operation when the write or the apply fails.
- **R5.** `[PR1]` `_doctor_check_inotify_limits` runs only when `LINUX` and `HAS_DOCKER` are set, fails when the live value is below 1024 or the conf file lacks the desired line, and names `./setup_env.sh -t developer` in the failure.
- **R6.** `[PR1]` `.config/.zshrc.d/5_general.zsh` exports `PARALLEL_JOBS=18` on host `claude` and `PARALLEL_JOBS=12` on host `workstation`, only when `PARALLEL_JOBS` is unset, and sets nothing on any other host.
- **R7.** `[PR1]` No test calls the real `sysctl` binary for a write or reads the real `/proc/sys/fs/inotify/max_user_instances`; each uses the `_SYSCTL_BIN`, `_SYSCTL_CONF` and `_INOTIFY_PROC` seams.
- **V1.** After merge, on `claude` and `workstation`, `sysctl fs.inotify.max_user_instances` reports 1024 and `-t doctor` passes the inotify check.
- **V2.** After merge, a new interactive zsh reports `PARALLEL_JOBS` 18 on `claude` and 12 on `workstation`.
- **N1.** No change to `fs.inotify.max_user_watches` or any other sysctl.
- **N2.** No sysctl write from `-t update` or `-t setup_user`.
- **N3.** No change to the terraform_ansible Makefile.

## Multi-Lens Review

Reviewed at commit: `a341e58c` (Step 7 self-review commit, before Step 8 dispatch)

### Goal-Fit

Finding: (1) Section 3 goes live in every new shell at merge, while the sysctl changes only on the next setup/developer run, so `claude` runs 18 jobs against limit 128: the measured failing configuration. Gate the export on the live value. (2) N3 rules out putting the per-host default in terraform_ansible's own `ansible/Makefile`, with no mechanism given; there it would reach every actor and sit next to its consumer. (3) Name who runs the matrix on `claude`. (4) An empty or non-numeric `_INOTIFY_PROC` read compares as 0; gate on `^[0-9]+$`. (5) V2 run from a shell that inherited the variable passes regardless; no case covers the ordering in (1).
Assumption: the 15/32 failures at 18 jobs are `max_user_instances` exhaustion, not `max_user_watches`, docker contention or memory. Refute by running the matrix at 18 on the default limit and grepping failed logs for `inotify_init`/`EMFILE`.
Disposition:

### Ergonomics

Finding: (1) Long-lived sessions keep their launch environment (the Bash tool sources a frozen snapshot; the ansible session on workstation is ~6 days old), so the export reaches nothing until relaunch from a fresh shell; the spec's mechanism sentence is wrong. (2) V2 checks a fresh shell, not the consumer process. (3) Doctor's remedy names `-t developer`, a 10+ minute full install; name the direct one-line apply instead. (4) "Source and call" over ssh leaves `HAS_DOCKER` unset, so the step silently returns 0. (5) N2 means routine `update` never applies it. (6) `_OVERRIDE_HOSTNAME` needs a Test Seams entry.
Assumption: the matrix runs from a process started after merge. Check `/proc/<ansible session pid>/environ` for `PARALLEL_JOBS` after merge. (Orchestrator check: `sudo -n true` succeeds on `claude` and `workstation`.)
Disposition:

### Risk

Finding: (1) HIGH: `_stub_ubuntu_steps` (`tests/setup_env/workflows.bats:715`) stubs 13 steps by name and not the new one, and dev shells export `HAS_DOCKER=1`, so the real step runs with production paths: `make test` goes red on `claude`, green in CI. `linux_ubuntu.bats:4464` exports `HAS_DOCKER=1` explicitly. Set the three seams at `setup()` scope and add the step to the stub list. (2) The "would set the live kernel value" claim is wrong as uid 1000; the real hazard is `tests/mocks/tee` swallowing failures. Verify the write by reading the file back; drive write failure with `MOCK_TEE_EXIT`. (3) WSL2 (`cruncher`) carries `HAS_DOCKER`; without systemd in WSL the conf is never applied at boot and doctor fails after every restart. (4) Unreadable `/proc` read reports "below target"; give it its own message. (5) Raising workstation from 6 to 12 adds docker contention next to its 6 live runners; the measurement covers wall time, not runner interference.
Assumption: `HAS_DOCKER` hosts run systemd-sysctl at boot. Holds on `workstation`; unknown on `cruncher` (ssh refused 2026-10-08, so unmeasured).
Disposition:

### Adversarial Spec Review (comparison/judge designs only)

N/A: spec has no comparison/evaluator/ambiguous-criteria trigger.
