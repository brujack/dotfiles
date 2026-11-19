# Repo Session Management Implementation Plan

spec: docs/superpowers/specs/2026-11-19-repo-session-management-design.md

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Recreate the per-repo Claude tmux sessions on `claude` and `workstation` at boot,
attach to them from Warp on every Mac, and route the Macs to those hosts directly on the
home LAN and through Cloudflare elsewhere.

**Architecture:** Two small scripts in a new top-level `bin/` (`repo-session`,
`home-lan-probe`), a per-host list in `config/repo-sessions.sh`, a systemd user unit,
installer and doctor functions in a new `lib/repo_sessions.sh`, Darwin-gated
`.ssh/config` routing with a tracked `known_hosts_home`, and three Warp launch configs.

**Tech Stack:** bash, bats, OpenSSH (`ssh -G`, `ssh-keyscan`, `ssh-keygen`), tmux 3.6,
systemd user units, Warp YAML.

## Global Constraints

- The spec at the path above is approved and frozen; every exact string, path, IP and
  fingerprint comes from its Design section and its Requirements block. Read the spec
  before each task.
- Pinned values: `claude` 192.168.51.17 `SHA256:ng/HWNyh2AZ1gm9iMy1Vd59+VFq8Sx00SJ6Uh3a7qfY`;
  `workstation` 192.168.51.12 `SHA256:ZVFVKdcncNrEMmWrb/4gDdgn6NP0lgpQm1vxyFe1y/o`.
- Shell standards: `#!/usr/bin/env bash`, no `set -e`, `[[ ]]`, `${VAR}`, `printf`, functions
  `|| return 1`. Every new `.bats` file is added to `tests/bats-files.txt`
  (`git ls-files '*.bats' | LC_ALL=C sort`, after `git add`), or `make test` fails.
- No test touches real state: no real `tmux`, `systemctl`, `loginctl`, `sudo`,
  `ssh-keyscan` or network. Use seams and `tests/mocks/`.
- **Never run a Bash command whose text names `lib/workflows.sh`** (the privacy hook refuses
  it). Read and edit that file with the Read and Edit tools only.
- `make test` runs in about 140 s here, under the 600 s Bash cap: every code task gates on
  it.
- N1: nothing in this plan creates, kills or restarts a session or starts the unit.

## Verification (session level)

- `make test` exits 0 with every new test present (`ok` lines for each new file).
- `bash scripts/run-bash-coverage.sh --list-sources` includes `lib/repo_sessions.sh`, and
  CI's bash coverage stays at or above 91%.
- After merge, by the operator: V1 (reboot both hosts, seven sessions registered for Remote
  Control), V2 (`ssh -G claude` from the Studio, reception and the moving laptop), V3
  (laptop on a foreign network falls back to Cloudflare).

---

### Task 1: `repo-session` and the session list

```yaml-task
id: 1
description: bin/repo-session (attach/create, --detached, --all, path guard, trailing slash, list lookup) and config/repo-sessions.sh
role: executor
model: sonnet
tdd: required
requirements: [R1, R2, R3, R4, R10]
acceptance:
  - cmd: bats tests/scripts/repo_session.bats
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [bin/repo-session, config/repo-sessions.sh, tests/scripts/repo_session.bats, tests/bats-files.txt]
depends_on: []
```

**Files:** create `bin/repo-session` (executable), `config/repo-sessions.sh`,
`tests/scripts/repo_session.bats`; update `tests/bats-files.txt`.

**Behaviour** (spec component 1, R1–R4, R10): tmux via `${_TMUX_BIN:-tmux}`; list via
`${REPO_SESSIONS_FILE:-${HOME}/git-repos/personal/dotfiles/config/repo-sessions.sh}`; host via
`${_REPO_SESSION_HOST:-$(hostname -s)}`; exits 0/1/2/3 as R3/R4 state.

**Tests (RED first, one behaviour at a time):** the Testing bullet "bats `repo-session`" in
the spec, every sub-bullet, with a recording `_TMUX_BIN` stub that logs argv to a file and
answers `has-session` from a knob. The symlink case runs `--all` through
`ln -s <repo>/bin/repo-session "${HOME}/.local/bin/repo-session"` with `HOME` at a fixture.

**Interfaces:** Produces `bin/repo-session`, `REPO_SESSIONS` (assoc array keyed by
`hostname -s`), seams `_TMUX_BIN`, `REPO_SESSIONS_FILE`, `_REPO_SESSION_HOST`.

### Task 2: `home-lan-probe`

```yaml-task
id: 2
description: bin/home-lan-probe host-key fingerprint probe with _SSH_KEYSCAN_BIN seam
role: executor
model: sonnet
tdd: required
requirements: [R5]
acceptance:
  - cmd: bats tests/scripts/home_lan_probe.bats
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [bin/home-lan-probe, tests/scripts/home_lan_probe.bats, tests/bats-files.txt]
depends_on: [1]
```

**Behaviour** (spec component 2, R5):
`"${_SSH_KEYSCAN_BIN:-ssh-keyscan}" -T 1 -t ed25519 "${ip}" 2>/dev/null | ssh-keygen -lf - 2>/dev/null`,
compare field 2 with the argument; any non-match, empty output, keygen rc 255 or a missing
binary exits 1; a match exits 0. Wrong arg count exits 2.

**Tests:** the spec's "bats `home-lan-probe`" bullet. The keyscan stub prints a real
ed25519 public-key line generated in `setup()` with
`ssh-keygen -q -t ed25519 -N '' -f "${BATS_TEST_TMPDIR}/k"`, so the real `ssh-keygen -lf -`
parses it (no hand-typed fingerprint). Missing binary: `_SSH_KEYSCAN_BIN` pointing at a
nonexistent path.

**Interfaces:** Produces `bin/home-lan-probe <ip> <fingerprint>`.

### Task 3: ssh routing and tracked host keys

```yaml-task
id: 3
description: Darwin-gated Match blocks for claude/workstation, known_hosts_home, delete *-home-tmux, routing tests via ssh -G
role: executor
model: sonnet
tdd: required
requirements: [R6, R7, R8, R9, R16]
acceptance:
  - cmd: bats tests/scripts/ssh_routing.bats
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [.ssh/config, .ssh/known_hosts_home, tests/scripts/ssh_routing.bats, tests/bats-files.txt]
depends_on: [2]
```

**Behaviour:** the spec's component 3 block, verbatim, placed before any existing block
that could set `HostName`, `ProxyJump` or `UserKnownHostsFile` for these names; plus the
`Match host workstation.home.conecrazy.ca exec "[ \"$(uname -s)\" = Darwin ]"` block and
`UserKnownHostsFile ~/.ssh/known_hosts ~/.ssh/known_hosts_home` on each Darwin block.
Delete `workstation-home-tmux`/`claude-home-tmux` from the alias lines, the
`*-home-tmux` pattern, and the `RemoteCommand` block with its comment. `.ssh/known_hosts_home`:
three lines, keys from `ssh-keyscan -t ed25519 192.168.51.17 192.168.51.12` with the host
field replaced by `claude`, `workstation`, `workstation.home.conecrazy.ca`.

**Tests:** the spec's "ssh routing" and "Tracked host keys" bullets. `ssh -G -F
.ssh/config` with `HOME` at a fixture (stub probe recording argv), a `uname` stub on
`PATH`, `SHELL=/bin/sh` in `setup()`, and one zsh case. Pin `hostname`, `hostkeyalias`,
`proxyjump`, `controlmaster false`, `userknownhostsfile`, probe argv, and "stub never
called" on Linux. N4 guard: on Darwin and Linux, `ssh -G claude-home` still resolves
`proxyjump home-secure.conecrazy.ca,workstation.home.conecrazy.ca` and
`ssh -G workstation-home` still resolves `proxyjump home-secure.conecrazy.ca`. The
`workstation.home.conecrazy.ca` block sets only `UserKnownHostsFile`.

### Task 4: unit, installer and doctor

```yaml-task
id: 4
description: config/systemd/repo-sessions.service, lib/repo_sessions.sh install_repo_sessions and _doctor_check_repo_sessions, sourced by setup_env.sh
role: executor
model: sonnet
tdd: required
requirements: [R11, R12, R13]
acceptance:
  - cmd: bats tests/setup_env/repo_sessions.bats
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [config/systemd/repo-sessions.service, lib/repo_sessions.sh, setup_env.sh, tests/setup_env/repo_sessions.bats, tests/bats-files.txt]
depends_on: [3]
```

**Behaviour:** the unit is the spec's component 5 text verbatim. `install_repo_sessions`
(component 6, R12): macOS links `bin/home-lan-probe` and `.ssh/known_hosts_home`; a Linux
host with a `REPO_SESSIONS` entry links `bin/repo-session`, runs
`sudo loginctl enable-linger` only on `Linger=no` **first**, then `mkdir -p` and links the
unit, then `daemon-reload` and `enable` (never `start`). Linger comes first because
enabling linger with no user manager running starts one, and a manager started after
`enable` would start the unit and create sessions (N1). Returns 0, or 1 on a failed step with a `log_warn` naming it.
`_doctor_check_repo_sessions` (component 7, R13) with the exact remedies.
Seams: `_SYSTEMD_USER_DIR`, `_SYSTEMCTL_BIN`, `_LOGINCTL_BIN`, `_TMUX_BIN`,
`REPO_SESSIONS_FILE`, `_REPO_SESSION_HOST`, all set at `setup()` scope. Source the new lib
from `setup_env.sh` after `lib/launch_agents.sh`; last line is the sourcing guard.

**Tests:** the spec's "Unit", "Installer" and "Doctor" bullets, plus a recorded-call-order
case: the `loginctl enable-linger` call precedes the `systemctl --user enable` call (`systemd-analyze --user
verify` skipped with a message where absent).

**Interfaces:** Produces `install_repo_sessions`, `_doctor_check_repo_sessions`.

### Task 5: wire into setup_user and doctor

```yaml-task
id: 5
description: call install_repo_sessions from run_setup_user and _doctor_check_repo_sessions from run_doctor, with call-site regression tests
role: executor
model: sonnet
tdd: required
requirements: [R12, R13]
acceptance:
  - cmd: bats -f 'call site' tests/setup_env/repo_sessions.bats
    exit_code: 0
    stdout_match: 'ok [0-9]+ .*call site'
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [lib/workflows.sh, lib/helpers.sh, tests/setup_env/repo_sessions.bats]
depends_on: [4]
```

**Behaviour:** in `run_setup_user`, after `install_ledger_drift_agent`, add
`install_repo_sessions || log_warn "repo sessions not installed — see above"` (advisory,
like its neighbours). In `run_doctor`, call `_doctor_check_repo_sessions` beside
`_doctor_check_cred_dirs`. Edit `lib/workflows.sh` with the Read/Edit tools only.

**Tests:** two tests named `... call site ...` asserting, from `declare -f run_setup_user`
and `declare -f run_doctor` after `load_setup_env`, that each body calls the function
(the next reader's tests will call the functions directly, so the wiring needs its own
guard).

### Task 6: Warp launch configs

```yaml-task
id: 6
description: studio.yaml, laptop.yaml, reception.yaml; delete launch_config.yaml; pair-based tab test
role: executor
model: sonnet
tdd: required
requirements: [R14]
acceptance:
  - cmd: bats tests/scripts/warp_launch_configs.bats
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [.warp/launch_configurations/studio.yaml, .warp/launch_configurations/laptop.yaml, .warp/launch_configurations/reception.yaml, .warp/launch_configurations/launch_config.yaml, tests/scripts/warp_launch_configs.bats, tests/bats-files.txt]
depends_on: [5]
```

**Behaviour:** component 8. Use `launch_config.yaml`'s existing shape
(`name:`, `windows: - tabs: - title: / layout: / cwd: / commands: - exec:`). Session tab
`exec:` lines are exactly `ssh -t <host> .local/bin/repo-session <dir>`, titled with the
session name; the `update-*` tabs as listed. Remove `launch_config.yaml`.

**Tests:** the spec's "Warp" and "Remote PATH" bullets. Parse tabs with awk into
(host, dir) pairs and compare the sorted multiset with the one built from
`config/repo-sessions.sh`. YAML parse with `python3 -c 'import yaml'`, skipped with a message
where PyYAML is absent. N2 guard: no `exec:` line in any config contains `-t update` or
`setup_env.sh`. Remote PATH: `env -i HOME=<fixture> PATH=/usr/bin:/bin zsh -c
'.local/bin/repo-session --help'` from the fixture `$HOME`, with a stub `repo-session`.

### Task 7: comment fix and repo docs

```yaml-task
id: 7
description: launch_agents.sh comment (R15) and CLAUDE.md layout/entry-point notes (docs and a comment only, no behaviour change)
role: executor
model: sonnet
tdd: not-applicable
requirements: [R15]
acceptance:
  - cmd: '! command grep -q "the Studio is the tmux host" lib/launch_agents.sh'
    exit_code: 0
  - cmd: 'command grep -q "the Studio is always up" lib/launch_agents.sh'
    exit_code: 0
  - cmd: 'command grep -qE "Tracked top-level dirs:.*\`bin/\`" CLAUDE.md'
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 2
files_touched: [lib/launch_agents.sh, CLAUDE.md]
depends_on: [6]
```

**Behaviour:** R15 wording in the LaunchAgent comment. In `CLAUDE.md`: add `bin/` to the
Layout line's tracked-dirs list (regenerate with the command that line names), and one
Entry Points bullet: `repo-session <dir>` attaches to or creates a repo's tmux session;
`repo-sessions.service` recreates them at boot on hosts listed in `config/repo-sessions.sh`
(spec: `docs/superpowers/specs/2026-11-19-repo-session-management-design.md`). Respect the
CLAUDE.md byte ceiling the pre-commit hook enforces.
</content>
</invoke>
<invoke name="Bash">
<parameter name="command">cd /home/bruce/git-repos/personal/dotfiles-wt-spec && make validate-plan PLAN=docs/superpowers/plans/2026-11-19-repo-session-management.md 2>&1 | tail -6

## Non-goal check

Reviewer: fresh Opus subagent with `nongoal-check.md`, 2026-11-19. Result: 4 CLEAR (N3, N5, N6, N7), 3 UNCLEAR (N1, N2, N4), 0 CONFLICT.

- **N1, UNCLEAR.** Quote: "Task 4 runs `enable`, then `sudo loginctl enable-linger`. If no user manager is running, enable-linger starts user@UID, which starts the enabled unit and creates sessions." Resolution, plan revision in Task 4. Before: "`mkdir -p` then links the unit, runs `daemon-reload` and `enable` (never `start`), and `sudo loginctl enable-linger` only on `Linger=no`". After: linger first, then link, `daemon-reload` and `enable`; plus a call-order test.
- **N2, UNCLEAR.** Quote: "Task 6 says only 'the `update-*` tabs as listed'. Their `exec:` could run `-t update` at launch." Resolution, plan revision in Task 6. Added a test asserting no `exec:` line contains `-t update` or `setup_env.sh`.
- **N4, UNCLEAR.** Quote: "the new `Match host workstation.home.conecrazy.ca` block could change how the `*-home` aliases reach their ProxyJump hop." Resolution, plan revision in Task 3. Added `ssh -G claude-home`/`workstation-home` proxyjump pins on both platforms, and stated that the block sets only `UserKnownHostsFile`.
