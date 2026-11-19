# Repo session management (tmux, systemd, Warp, ssh routing) — design

- **Date:** 2026-11-19
- **Status:** Draft

## Problem

Every Claude Code session runs in a tmux session on `claude` (six repos), apart from
`ansible`, which runs on `workstation`. Those sessions were created by hand on 2026-11-17 and
nothing recreates them:

- `loginctl show-user bruce -p Linger` reports `Linger=no` on both hosts, so a reboot kills
  them and nothing brings them back.
- The repo has no session tooling. `git grep` for `repo-session`, `remote-control`,
  `enable-linger` and `.config/systemd` (outside `docs/`) returns nothing.
- `.warp/launch_configurations/launch_config.yaml` (last edited 2023-11-24) opens four local
  tabs with `ll`. None of them reaches a session.
- `.ssh/config`'s `*-home-tmux` aliases run `tmux attach-session || tmux new-session`. That
  attaches to whichever session tmux picks, not to a repo.
- `lib/launch_agents.sh` says "the Studio is the tmux host". Since 2026-09-19 the tmux host
  is `claude`.

Reaching the sessions also depends on where the client is. The Studio is always on the LAN,
reception (a work Mac) is never on it, and the laptop is usually at home but sometimes away.
The off-LAN route is Cloudflare, then the bastion, then a password hop on `workstation`.

## Decisions already made (operator)

- One script, `repo-session <dir>`, attaches to or creates the session for a repo directory
  under `~/git-repos/personal`. A new session starts `claude` fresh (no `--continue`). The
  pane command is `zsh -ic`, because the brew and `~/.local/bin` PATH is set only in
  interactive zsh.
- Sessions: on `claude`, etch-cli, etch-config, dotfiles, ai-config, ai-devops and math; on
  `workstation`, `terraform_ansible/ansible` (session name `ansible`).
- Boot: a systemd user unit plus `loginctl enable-linger` creates the sessions detached
  after a reboot. The keychain keys have no passphrase, so a detached pane cannot hang on a
  prompt.
- Warp gets per-machine launch configs (`studio.yaml`, `laptop.yaml`, `reception.yaml`).
- Routing: the Studio always goes direct, reception always goes through Cloudflare, and the
  laptop detects which network it is on, using ssh `Match exec`.
- `claude` and `workstation` are always at home. From a client on the home LAN, `claude` is
  never proxied through `workstation`. From a client off the LAN, `claude` is reached as
  today: Cloudflare, then the bastion, then `workstation`, then `claude`.
- Every ssh connection made from `claude` or `workstation` is a plain ssh connection. No
  probe, no `Match exec`, no ControlMaster and no `home-ssh` is involved on the Linux
  hosts.
- Reception and two other work Macs (`office`, `home`) live in a different namespace
  (`*.centrepointe.genexxelearning.ca`, e.g. `office.centrepointe.genexxelearning.ca`), and
  reception ssh's directly to the other two. All three are managed by this repo, so they
  receive the same `.ssh/config` and Mac scripts. Their routing to each other is untouched.
  The three work Macs (`hostname -s` in `reception`, `reception-1`, `office`, `office-1`,
  `home-1`, the wired and wireless names in `config/profiles.sh`) reach `claude`/`workstation`
  only through Cloudflare. That is chosen by hostname rather than by the probe, because the
  work LAN's addressing is not known to differ from `192.168.51.0/24`.

## Measurements behind the design

All measured on 2026-11-19.

| What                                                                                             | Where                                | Result                                                                                                                                          |
| ------------------------------------------------------------------------------------------------ | ------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| `claude --help`                                                                                  | `claude`                             | `-n, --name <name>` and `--remote-control [name]` exist                                                                                         |
| `tmux ls`                                                                                        | `claude`                             | six sessions named by repo, created 2026-11-17                                                                                                  |
| `tmux ls`                                                                                        | `workstation`                        | `ansible` session                                                                                                                               |
| `Linger`                                                                                         | both hosts                           | `no`                                                                                                                                            |
| `ssh-keygen -y -P ''` on `github`, `gitlab`, `home`, `id_rsa`                                    | `claude`                             | all four load with an empty passphrase                                                                                                          |
| `ssh -G` with a `Match host claude exec` block before a `Host claude` block carrying `ProxyJump` | `claude` (OpenSSH, throwaway config) | when the exec succeeds, the `Match` `HostName` wins, **but the later `ProxyJump` still applies unless the `Match` block sets `ProxyJump none`** |
| `nc -z -w 1 <unreachable>`                                                                       | `claude` (OpenBSD netcat 1.234)      | rc 1, about 0.005 s                                                                                                                             |
| `nc -z -w 1 <unreachable>`                                                                       | Studio (macOS nc)                    | rc 1 after **4 s**. `-w` does not bound the connect on macOS                                                                                    |
| `nc -z -G 1 -w 1 <unreachable>`                                                                  | Studio                               | rc 1 after 1.03 s                                                                                                                               |
| `nc -z -G 1 -w 1 192.168.51.17 22`                                                               | Studio                               | rc 0                                                                                                                                            |
| LAN addresses                                                                                    | DNS                                  | `claude` 192.168.51.17, `workstation` 192.168.51.12                                                                                             |

Scope of these measurements:

- The `ssh -G` precedence test used a throwaway config on one Linux OpenSSH. It is
  OpenSSH's documented first-match rule, not a version quirk.
- The macOS `nc` timings come from the Studio only. The laptop and reception run the same
  macOS nc, but that was not measured on them.

## Design

### 1. `bin/repo-session` (new script)

`repo-session [--detached] <dir>` and `repo-session --detached --all`.

- `<dir>` is a path relative to `${HOME}/git-repos/personal`. The session name is
  `${dir##*/}`.
- It runs
  `tmux new-session -A -s "<name>" -c "${HOME}/git-repos/personal/<dir>" "zsh -ic 'claude --name \"\$(basename \"\$PWD\")\" --remote-control; exec zsh'"`.
  `-A` attaches if the session exists.
- `--detached` adds `-d`. If the session already exists (`tmux has-session -t "=<name>"`),
  it does nothing and exits 0.
- `--all` (detached only) runs once for each dir in this host's list (component 4), and
  reports each failure while continuing. The exit code is 0 when every dir succeeded,
  otherwise 1.
- It refuses, with exit 2 and a message naming the argument, any `<dir>` that is empty,
  absolute, contains a `..` component, or does not exist as a directory. ssh passes the
  argument from another machine, so a typo must not create a stray session in `$HOME`.
- If `exec zsh` follows a failed `claude`, the pane stays alive, so a boot-time network
  failure leaves a shell in which to rerun `claude`.

### 2. `bin/home-lan-probe` (new script)

`home-lan-probe <ip>` exits 0 when TCP port 22 at `<ip>` answers within about 1 s, and 1
otherwise.

- On macOS it runs `nc -z -G 1 -w 1 <ip> 22`; elsewhere `nc -z -w 1 <ip> 22`. The platform
  comes from `uname -s`.
- A missing `nc` exits 1, so the client falls back to the Cloudflare route rather than
  reporting an error.

### 3. ssh routing (`.ssh/config`)

The bare names `claude` and `workstation` become routing aliases on every Mac. **The
default is direct.** The Cloudflare chain applies only when the probe exists and positively
reports that the client is off the LAN:

```
Match host claude,workstation exec "[ \"$(uname -s)\" = Darwin ] && case $(hostname -s) in reception|reception-1|office|office-1|home-1) true;; *) false;; esac"
  ProxyJump PER_HOST_CHAIN
Match host claude exec "[ \"$(uname -s)\" = Darwin ] && test -x $HOME/.local/bin/home-lan-probe && ! $HOME/.local/bin/home-lan-probe 192.168.51.17"
  ProxyJump home-secure.conecrazy.ca,workstation.home.conecrazy.ca
Match host workstation exec "[ \"$(uname -s)\" = Darwin ] && test -x $HOME/.local/bin/home-lan-probe && ! $HOME/.local/bin/home-lan-probe 192.168.51.12"
  ProxyJump home-secure.conecrazy.ca
Host claude workstation
  HostName %h.home.conecrazy.ca
  User bruce
  IdentityFile ~/.ssh/home
```

The work-Mac block is written as two blocks in the real file, one per host, because the
chain differs (`claude`: `home-secure.conecrazy.ca,workstation.home.conecrazy.ca`;
`workstation`: `home-secure.conecrazy.ca`). `PER_HOST_CHAIN` above is shorthand for that,
not literal config.

- **Linux hosts.** Every `exec` starts with the `uname -s` test, so on `claude` and
  `workstation` no probe runs and both names go direct. That makes them plain ssh.
- **The work Macs** match by `hostname -s` and always get the Cloudflare chain, whatever
  network they are on.

- **Failure direction.** A missing, non-executable or failing probe means direct. That is
  how bare `ssh workstation` behaves today, so a host where `setup_user` has not yet run
  (the config is live on `git pull`, because `~/.ssh/config` is a symlink) keeps working.
  This covers `claude` and `workstation` themselves, and `lib/legacy_rsync.sh`'s
  `bruce@workstation:` from the Studio.
- **`$HOME`, not `%d`.** `%d` comes from the passwd entry and ignores `HOME`, which makes the
  routing untestable. `Match exec` runs through `sh -c`, so `$HOME` expands there. Both were
  measured in Step 8.
- The `Match` blocks sit before the `Host claude workstation` block. `ProxyJump` is set
  only in the off-LAN `Match`, so no later block can add a jump on the LAN.
- `User` and `IdentityFile` sit on the alias block, because Host patterns match the alias,
  not the HostName.
- The workstation password hop gets the following, in a
  `Match host workstation.home.conecrazy.ca,workstation exec "[ \"$(uname -s)\" = Darwin ]"`
  block, so the Linux hosts never multiplex:
  - `ControlMaster auto`
  - `ControlPath ~/.ssh/cm-%C`
  - `ControlPersist 10m`
  - `ServerAliveInterval 30`, so a master left dead by a network move is detected
- The `*-home-tmux` aliases and their `RemoteCommand` block are deleted. The plain `*-home`
  aliases stay, as an explicit force-Cloudflare route.

### 3b. `bin/home-ssh` (new script, client side)

`home-ssh <host> <remote command...>` is what every Warp session tab runs. It exists
because seven tabs opened at once off the LAN would each find no `ControlPath` socket and
each prompt for the workstation password.

**One hop argv.** The master and its check both use one array,
`HOP=(-J home-secure.conecrazy.ca workstation.home.conecrazy.ca)`. That is the exact form
OpenSSH uses for the inner hop of an off-LAN `ssh claude` (`exec ssh -J home-secure.conecrazy.ca ... -W ... workstation.home.conecrazy.ca`, measured in Step 8 round 2).
`%C` hashes `%l%h%p%r%j`, so all three resolve to one socket. A LAN-direct `ssh workstation`
has an empty `%j`, so its socket is different, and a LAN master left behind after the laptop
moves can never satisfy the off-LAN check. Round 2 measured the first version, whose check
omitted `-J`: it hashed to a different socket, on OpenSSH 10.2p1 and 10.5p1.

`home-ssh --print-hop-argv` prints `HOP` one element per line. It exists for the controlpath
test.

**Behaviour:**

- **On a work Mac** (`hostname -s` in `reception`, `reception-1`, `office`, `office-1`,
  `home-1`): skip the probe and treat the client as off the LAN.
- **On the LAN** (`home-lan-probe` succeeds for the target's IP): `exec ssh -t <host> <cmd>`.
- **Off the LAN:** loop, for at most 300 s in total:
  1. If `ssh -O check "${HOP[@]}"` succeeds, `exec ssh -t <host> <cmd>`.
  2. If `mkdir ~/.ssh/cm-hop.lock` succeeds, this process owns the lock:
     - Install `trap` on EXIT, INT, TERM and HUP that removes the lock.
     - Run `ssh -fNM -o ControlPersist=10m "${HOP[@]}"`. The password prompt appears in
       this tab.
     - Remove the lock on success or failure, then `exec ssh -t <host> <cmd>`. On failure,
       ssh prompts again in this tab.
  3. Otherwise, the first time, print
     `home-ssh: waiting for the workstation password in another tab`. Then remove the lock
     if `find ~/.ssh/cm-hop.lock -maxdepth 0 -mmin +5` reports it older than 5 minutes
     (BSD and GNU `find` both support this), sleep 1 s, and repeat.
- After 300 s it prints `home-ssh: no shared connection after 300 s; connecting directly`
  and execs ssh anyway.
- A waiter that sees the lock vanish with no live master (a cancelled or failed prompt)
  takes the lock on its next pass and prompts in its own tab.
- The probe IPs per host (`claude` 192.168.51.17, `workstation` 192.168.51.12) must equal
  the ones in the `.ssh/config` `Match` lines; a test asserts this.

### 4. Per-host session list (`config/repo-sessions.sh`)

A tracked bash file defining `REPO_SESSIONS`, an associative array from hostname
(`hostname -s`) to a space-separated list of dirs:

- `claude`: `etch-cli etch-config dotfiles ai-config ai-devops math`
- `workstation`: `terraform_ansible/ansible`

A host with no entry has no sessions.

### 5. `repo-sessions.service` (systemd user unit)

A template tracked in the repo:

```
[Unit]
Description=Create repo tmux sessions (repo-session --all)

[Service]
Type=oneshot
RemainAfterExit=yes
KillMode=process
TimeoutStartSec=180
ExecStartPre=-/usr/bin/timeout 60 /bin/sh -c 'until nc -z -w 1 api.anthropic.com 443; do sleep 1; done'
ExecStart=-%h/.local/bin/repo-session --detached --all

[Install]
WantedBy=default.target
```

- **The tmux server must outlive the unit in every state.** Under the default
  `KillMode=control-group`, a oneshot whose `ExecStart` exits non-zero goes to `failed`, and
  systemd kills its whole cgroup. That cgroup includes the tmux server holding the sessions
  that succeeded, as measured with `systemd-run` in Step 8. A later `stop` does the same.
  - `ExecStart=-` makes a partial failure leave the unit active, not failed.
    `repo-session` still reports each failed dir on stderr, so it lands in the journal.
  - `KillMode=process` limits a `stop` or `restart` to the main process, which has already
    exited, so it never reaches tmux.
- **`ExecStartPre=-` waits up to 60 s for `api.anthropic.com:443`.** A user unit cannot
  order itself after the system's `network-online.target`. The `-` makes a timeout
  non-fatal, and the panes still fall back to `exec zsh`.
  - The wait is bounded by `timeout 60`, not by a pass count. With a slow resolver, each
    `nc` pass can take seconds.
  - `TimeoutStartSec=180` sits above the 60 s wait plus `ExecStart`. The user manager's
    default is 90 s, and a start timeout fails the unit before `ExecStart` runs (measured
    with a transient unit in Step 8 round 2).

### 6. Install (`setup_env.sh -t setup_user`)

On a Linux host with a `REPO_SESSIONS` entry, link `bin/repo-session` into `~/.local/bin`.
On macOS, link `bin/home-lan-probe` and `bin/home-ssh` into `~/.local/bin`. All links use
`safe_link`.

On a Linux host with a `REPO_SESSIONS` entry, also:

- Link the unit into `~/.config/systemd/user/`.
- Run `systemctl --user daemon-reload` and `systemctl --user enable repo-sessions.service`.
  The unit is enabled, not started, so it acts from the next boot and leaves running
  sessions alone.
- Run `sudo loginctl enable-linger "${USER}"` only when `loginctl show-user` reports
  `Linger=no`.

Seams: `_SYSTEMD_USER_DIR`, `_SYSTEMCTL_BIN` and `_LOGINCTL_BIN`.

### 7. Doctor

On a host with a `REPO_SESSIONS` entry, `-t doctor` reports `repo-sessions` as:

- FAIL when Linger is off, with remedy `sudo loginctl enable-linger "$USER"`.
- FAIL when the unit is not enabled, with remedy `./setup_env.sh -t setup_user`.
- PASS otherwise.

A host without an entry is not checked.

### 8. Warp launch configs (`.warp/launch_configurations/`)

`launch_config.yaml` is deleted.

- `studio.yaml`:
  - `update-studio`: local, cwd `~/git-repos/personal/dotfiles`.
  - `update-laptop`, `update-workstation`, `update-claude`: `ssh -t <host>` to a shell.
    They do not run the update; that stays manual.
  - Then the seven session tabs:
    `~/.local/bin/home-ssh claude .local/bin/repo-session <dir>` for each `claude` dir, and
    `~/.local/bin/home-ssh workstation .local/bin/repo-session terraform_ansible/ansible`.
    The remote path is spelled out because a remote ssh command runs non-interactive zsh,
    whose PATH lacks `~/.local/bin` (measured on `workstation`, Step 8). It is relative
    because ssh starts the command in `$HOME`.
- `laptop.yaml`: `update-laptop` (local), then the same seven session tabs.
- `reception.yaml`: the seven session tabs only. Reception is a work Mac that this repo
  does not update.

Every session tab is titled with its session name.

### 9. Comment fix

`lib/launch_agents.sh`, above the LaunchAgent installer: "the Studio is the tmux host and is
always up" becomes "the Studio is always up". The single-runner rationale is unchanged.

## Testing

- **bats `repo-session`** (tmux mocked through `tests/mocks/`):
  - session name for `dotfiles` and for `terraform_ansible/ansible` (`ansible`)
  - `-A` in attach mode, `-d` in `--detached`
  - `--detached` does nothing when `has-session` succeeds
  - `--all` walks the host's list, continues past one failing dir and exits 1
  - empty, absolute, `..` and missing dirs each exit 2 without calling tmux
- **bats `home-lan-probe`**: `nc` mocked by PATH, platform via the `uname -s` seam. The
  macOS argv carries `-G 1 -w 1`, Linux carries `-w 1`. Exit codes pass through, and a
  missing `nc` exits 1.
- **ssh routing**: real `ssh -G -F .ssh/config` with `HOME` pointed at a fixture holding a
  stub `~/.local/bin/home-lan-probe`.
  - Probe exit 0: `claude` resolves to `hostname claude.home.conecrazy.ca` with no
    `proxyjump` line.
  - Probe exit 1: `claude` carries
    `proxyjump home-secure.conecrazy.ca,workstation.home.conecrazy.ca`.
  - **Probe absent** (no stub file): `hostname <host>.home.conecrazy.ca` and no
    `proxyjump` line. This is the failure-direction guard. The `hostname` pin stops it
    passing on empty `ssh -G` output.
  - **ControlPath:** for the argv printed by `home-ssh --print-hop-argv`, `ssh -G` gives
    the same `controlpath` as for `-J home-secure.conecrazy.ca workstation.home.conecrazy.ca`,
    and a different one from `ssh -G workstation.home.conecrazy.ca` (LAN direct).
  - The same three cases for `workstation`.
  - `uname` and `hostname` are mocked on `PATH` (`Match exec` runs through `sh -c`, so a
    `PATH` stub reaches it). On `Linux` with the probe stub exiting 1, both names go direct
    (N6). On `Darwin` with each work hostname (`reception`, `reception-1`, `office`,
    `office-1`, `home-1`) and the probe stub exiting 0, both names get the Cloudflare chain.
  - On `Linux`, `ssh -G workstation` resolves `controlmaster false`. On `Darwin` it resolves
    `controlmaster auto`.
- **bats `home-ssh`** (`ssh` and `home-lan-probe` mocked):
  - LAN: one `ssh -t` call, no `-O check`.
  - Off-LAN with a live master: no `-fNM`.
  - Off-LAN with none: the first caller runs `-fNM -o ControlPersist=10m` with the `HOP`
    argv, and removes the lock.
  - A caller that finds the lock prints the waiting message, makes no `-fNM` call while the
    lock exists, and execs once the mocked check succeeds.
  - The owner's lock is removed when it is killed with TERM, and when `-fNM` exits
    non-zero.
  - A lock older than 5 minutes is removed (set its mtime with `touch -t`).
  - A waiter whose lock vanishes without a master takes the lock and runs `-fNM`.
  - The 300 s timeout path, with the clock seam shortened, prints its message and execs.
  - Its probe IP table equals the IPs in `.ssh/config`'s `Match` lines.
  - A guard asserts that no `Host` pattern ending `-home-tmux` remains.
- **Warp**: every file under `.warp/launch_configurations/` parses as YAML. In each config,
  the set of `repo-session` arguments equals the union of the `REPO_SESSIONS` lists, so the
  tabs cannot drift from the list. No `exec` line contains a bare `repo-session` (one not
  preceded by `.local/bin/`). Every session tab's command starts with
  `~/.local/bin/home-ssh `.
- **Remote PATH**: `ssh workstation 'command -v repo-session'` is not relied on. A test
  runs a session tab's remote command under `env -i HOME="$HOME" PATH=/usr/bin:/bin zsh -c`
  from `$HOME` against a fixture `~/.local/bin/repo-session`, and asserts it resolves.
- **Unit**: `systemd-analyze --user verify` passes on the unit where `systemd-analyze` is
  available; the test is skipped, with a message, where it is not. A test asserts that the
  unit carries `KillMode=process` and an `ExecStart=-` prefix.
- **Installer** (seams):
  - linger is enabled only when `Linger=no`
  - the unit is enabled, not started
  - a second run makes no `sudo` call and no `enable` call that changes state
  - a host without a list gets the links only
- **Doctor**: Linger off, unit not enabled, both OK, and a host not in the list.

## Requirements

- **R1.** `bin/repo-session <dir>` runs `tmux new-session -A -s "${dir##*/}" -c "${HOME}/git-repos/personal/<dir>"` with pane command `zsh -ic 'claude --name "$(basename "$PWD")" --remote-control; exec zsh'`.
- **R2.** `bin/repo-session --detached <dir>` adds `-d`, and exits 0 without creating a session when `tmux has-session -t "=<name>"` succeeds.
- **R3.** `bin/repo-session --detached --all` runs once per dir in this host's `REPO_SESSIONS` entry, continues past a failing dir, and exits 1 if any dir failed, else 0.
- **R4.** `bin/repo-session` exits 2, naming the argument, without calling tmux, for a `<dir>` that is empty, absolute, contains a `..` component, or is not a directory under `${HOME}/git-repos/personal`.
- **R5.** `bin/home-lan-probe <ip>` runs `nc -z -G 1 -w 1 <ip> 22` when `uname -s` is `Darwin` and `nc -z -w 1 <ip> 22` otherwise, exits with nc's status, and exits 1 when `nc` is not found.
- **R6.** On macOS only, `.ssh/config` routes `claude` and `workstation` through Cloudflare (`claude`: `ProxyJump home-secure.conecrazy.ca,workstation.home.conecrazy.ca`; `workstation`: `ProxyJump home-secure.conecrazy.ca`) when `hostname -s` is one of `reception`, `reception-1`, `office`, `office-1`, `home-1`, or when `$HOME/.local/bin/home-lan-probe` is executable and fails for `192.168.51.17` (`claude`) or `192.168.51.12` (`workstation`). Every such `Match ... exec` begins with `[ "$(uname -s)" = Darwin ]`. These blocks precede a `Host claude workstation` block that sets `HostName %h.home.conecrazy.ca` and no `ProxyJump`.
- **R7.** With `HOME` pointing at a fixture and `uname`/`hostname` mocked on `PATH`: on Darwin with a probe exiting 1, or with a work hostname (each of `reception`, `reception-1`, `office`, `office-1`, `home-1`), `ssh -G claude` resolves `proxyjump home-secure.conecrazy.ca,workstation.home.conecrazy.ca` and `ssh -G workstation` resolves `proxyjump home-secure.conecrazy.ca`. On Darwin with the probe exiting 0 or absent, and on Linux whatever the probe returns, both give `hostname <host>.home.conecrazy.ca` and no `proxyjump`.
- **R8.** On macOS only (a `Match host workstation.home.conecrazy.ca,workstation exec "[ \"$(uname -s)\" = Darwin ]"` block), `.ssh/config` sets `ControlMaster auto`, `ControlPath ~/.ssh/cm-%C`, `ControlPersist 10m` and `ServerAliveInterval 30`; on Linux `ssh -G workstation` resolves `controlmaster false`.
- **R9.** `.ssh/config` contains no `Host` pattern ending in `-home-tmux` and no `RemoteCommand`.
- **R10.** `config/repo-sessions.sh` maps `claude` to `etch-cli etch-config dotfiles ai-config ai-devops math` and `workstation` to `terraform_ansible/ansible`.
- **R11.** A tracked `repo-sessions.service` user unit has `Type=oneshot`, `RemainAfterExit=yes`, `KillMode=process`, `TimeoutStartSec=180`, an `ExecStartPre=-/usr/bin/timeout 60 /bin/sh -c 'until nc -z -w 1 api.anthropic.com 443; do sleep 1; done'`, `ExecStart=-%h/.local/bin/repo-session --detached --all` and `WantedBy=default.target`.
- **R12.** `setup_user` links `home-lan-probe` and `home-ssh` into `~/.local/bin` on macOS only, and `repo-session` only on a Linux host with a `REPO_SESSIONS` entry. On such a host it also links the unit into `~/.config/systemd/user/`, runs `systemctl --user daemon-reload` and `systemctl --user enable repo-sessions.service` (never `start`), and runs `sudo loginctl enable-linger "${USER}"` only when Linger is `no`.
- **R13.** On a host with a `REPO_SESSIONS` entry, doctor FAILs `repo-sessions` with remedy `sudo loginctl enable-linger "$USER"` when Linger is off, and with remedy `./setup_env.sh -t setup_user` when the unit is not enabled. It passes otherwise, and is silent on a host without an entry.
- **R14.** `.warp/launch_configurations/` holds `studio.yaml`, `laptop.yaml` and `reception.yaml` and no `launch_config.yaml`. In each, the session tabs run `~/.local/bin/home-ssh <host> .local/bin/repo-session <dir>` for exactly the union of the `REPO_SESSIONS` lists, and no `exec` line contains `repo-session` without the `.local/bin/` prefix. `studio.yaml` adds tabs `update-studio` (local), `update-laptop`, `update-workstation` and `update-claude` (`ssh -t <host>`), `laptop.yaml` adds `update-laptop` (local), and `reception.yaml` adds none.
- **R15.** The `lib/launch_agents.sh` comment reads "the Studio is always up" and no longer says "the Studio is the tmux host".
- **R16.** `.ssh/config` gives the aliases `claude` and `workstation` `User bruce` and `IdentityFile ~/.ssh/home`.
- **R17.** `bin/home-ssh <host> <cmd...>` uses one array `HOP=(-J home-secure.conecrazy.ca workstation.home.conecrazy.ca)` for both `ssh -O check "${HOP[@]}"` and `ssh -fNM -o ControlPersist=10m "${HOP[@]}"`, and `home-ssh --print-hop-argv` prints it one element per line. On a work hostname (`reception`, `reception-1`, `office`, `office-1`, `home-1`) it skips the probe and takes the off-LAN path. Elsewhere it execs `ssh -t <host> <cmd...>` directly when `home-lan-probe` succeeds for `<host>`'s IP (`claude` 192.168.51.17, `workstation` 192.168.51.12) or the check succeeds.
- **R18.** Off the LAN without a live master, the `home-ssh` caller that creates `~/.ssh/cm-hop.lock` with `mkdir` traps EXIT, INT, TERM and HUP to remove it, runs the `-fNM` master, and removes the lock whether `-fNM` succeeds or fails before exec'ing. A caller that finds the lock prints `home-ssh: waiting for the workstation password in another tab` once, removes a lock older than 5 minutes (`find ~/.ssh/cm-hop.lock -maxdepth 0 -mmin +5`), retries once a second, takes the lock itself if it vanishes with no master, and after 300 s prints `home-ssh: no shared connection after 300 s; connecting directly` and execs.
- **R19.** For the argv `home-ssh --print-hop-argv` prints, `ssh -G` resolves the same `controlpath` as `ssh -G -J home-secure.conecrazy.ca workstation.home.conecrazy.ca` and a different one from `ssh -G workstation.home.conecrazy.ca`.
- **V1.** After a reboot of `claude` with the unit installed, `tmux ls` lists all six sessions, each pane running `claude`.
- **V2.** From the laptop off the home LAN, a second session tab within 10 minutes of the first does not prompt for the workstation password.
- **V3.** From the Studio, `ssh -G claude` shows no `proxyjump`; from reception, it shows the Cloudflare chain.
- **V4.** From the laptop off the home LAN, opening `laptop.yaml` with no `~/.ssh/cm-*` socket prompts for the workstation password exactly once, and all seven tabs attach.
- **V5.** The master `home-ssh` starts and the jump connection inside `ssh claude` use the same `~/.ssh/cm-%C` socket (`ls ~/.ssh/cm-*` shows one socket for the hop).
- **V6.** Off the LAN, after the last tab closes, `ssh -O check -J home-secure.conecrazy.ca workstation.home.conecrazy.ca` still succeeds at 9 minutes and fails by 11 minutes (master lifetime is `ControlPersist 10m`).
- **V7.** Timing of a fresh `laptop.yaml` open off the LAN: tabs 2-7 attach within 10 s of the password being entered in tab 1.
- **N1.** No session is created, killed or restarted by `setup_user` or by installing the unit; existing sessions are left alone.
- **N2.** No launch config runs `setup_env.sh -t update` automatically.
- **N3.** No `claude --continue` or `--resume` in any session start.
- **N4.** No change to the `*-home` aliases' existing ProxyJump routes.
- **N5.** No change to how any host other than `claude` and `workstation` is reached: in particular the work Macs' direct ssh to each other (`*.centrepointe.genexxelearning.ca`) is untouched.
- **N6.** No probe, `Match exec` side effect, ControlMaster or `home-ssh` on `claude` or `workstation`: every ssh connection from them is plain.
</content>

</invoke>

## Multi-Lens Review

Reviewed at commit: `4dbd3f71` (Step 7 self-review commit, before Step 8 dispatch)

### Goal-Fit

Finding: Worth building; core (`repo-session`, unit, linger) solves a confirmed problem (both hosts rebooted 2026-11-17 ~11:55, all seven sessions recreated by hand 12:03-12:05; `Linger=no`). Load-bearing defect: every Warp tab runs `ssh -t <host> repo-session <dir>` under non-interactive zsh, whose PATH lacks `~/.local/bin` (measured `ssh workstation 'echo $PATH'`), so all tabs fail `command not found`; no planned check runs a tab.
Assumption: `claude --remote-control` started by a `default.target` user unit before the network is up keeps retrying rather than exiting; if it exits, every reboot leaves bare shells. Settle with `unshare -rn` offline start, or `tmux list-panes -a -F '#{session_name} #{pane_current_command}'` after one reboot.
Disposition: Addressed (operator, 2026-11-19) — tabs run `.local/bin/repo-session` via `home-ssh` (component 3b, R14) with a bare-name guard and a non-interactive PATH test; boot network handled by a bounded `ExecStartPre=-` wait (R11) plus V1.

### Ergonomics

Finding: (1) Same `command not found` PATH defect. (2) The launch configs fire 7 ssh connections at once; off-LAN all go through `workstation.home.conecrazy.ca`, and simultaneous first connections all miss the not-yet-bound `ControlPath` socket, so ControlMaster likely does not prevent up to 7 password prompts; V2 tests only the sequential case. Minor: no `ServerAliveInterval` on the R8 block, so a dead master after a network move can hang new tabs.
Assumption: Warp starts a launch config's tabs concurrently enough that the first master has not bound its socket before the others check. Settle off-LAN on the laptop with a 3-tab config and empty `~/.ssh/cm-*`: count password prompts / sockets.
Disposition: Addressed (operator, 2026-11-19) — PATH as Goal-Fit; the simultaneous-tab race is fixed now, per operator choice over measure-first, by `home-ssh`'s single-master lock (component 3b, R17, V4, V5); `ServerAliveInterval 30` added (R8).

### Risk

Finding: (1) Failure direction: a missing or failing probe falls through to the Cloudflare chain, whose `cloudflared` exists only on macs, so on `claude`/`workstation` bare `ssh workstation` (direct today) breaks; the window is guaranteed because `.ssh/config` is live on `git pull` before `setup_user` installs the probe; `lib/legacy_rsync.sh:34` (`bruce@workstation:`, Studio `-t update`) is also affected. Fix: a missing/erroring probe must mean direct. (2) `Type=oneshot` + R3's exit 1 on a partial failure: systemd marks the unit failed and kills its whole cgroup, including the tmux server holding the sessions that succeeded (measured with `systemd-run`); a later `stop`/`restart` also kills every session. (3) Same PATH defect. (4) Routing tests cannot work: `%d` comes from the passwd entry, not `$HOME` (measured); `$HOME` in the exec string is expanded by the `sh -c` that runs it (measured).
Assumption: same as Goal-Fit (claude at boot without network).
Disposition: Addressed (operator, 2026-11-19) — (1) routing inverted, default direct, Cloudflare only on a positive off-LAN probe, absent-probe case tested (R6, R7); (2) `ExecStart=-` plus `KillMode=process` (R11); (3) as Goal-Fit; (4) `$HOME` in the exec string (R6).

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.

### Round 2 (reviewed at `e88dd010`)

Goal-Fit — Finding: `home-ssh`'s `ssh -O check workstation.home.conecrazy.ca` omits `-J`, so `%C` (`%l%h%p%r%j`) differs from the master's; tabs 2-7 stall 120 s, later tabs re-prompt (measured, OpenSSH 10.2p1). Core worth building. Assumption: reception runs `setup_user` (settled by operator: yes). Disposition: Addressed (operator, 2026-11-19) — one `HOP` argv for check and master, real `ssh -G` controlpath test (component 3b, R17, R19).

Ergonomics — Finding: same ControlPath mismatch (measured on 10.2p1 and Studio 10.5p1); prompt tab unpredictable; Ctrl-C leaks the lock; master lifetime unspecified; absent-probe test passes on empty output. Assumption: Warp launches tab commands concurrently (V7 measures). Disposition: Addressed (operator, 2026-11-19, fix home-ssh now rather than descope) — trap on EXIT/INT/TERM/HUP and on `-fNM` failure, waiter message, `-o ControlPersist=10m` plus V6, `hostname` pinned in the absent-probe case (R18, V6).

Risk — Finding: (1) same ControlPath mismatch, plus a LAN master could satisfy the old check after a move; (2) user manager `DefaultTimeoutStartUSec=1min 30s` fails the unit before `ExecStart` when a count-bounded wait runs long (measured with a transient unit); `KillMode=process` alone confirmed to keep tmux alive on failure and `stop`. Minor: stale-lock check unspecified per platform, probe IPs duplicated. Assumption: `nc` fails fast at boot when it fails. Disposition: Addressed (operator, 2026-11-19) — `-J` in the check separates LAN and off-LAN sockets (R19); `TimeoutStartSec=180` with a `timeout 60` wall-clock wait (R11); portable `find -mmin +5` (R18); IP-table equality test.
