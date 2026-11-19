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

The bare names `claude` and `workstation` become auto-routing aliases on every machine:

```
Match host claude exec "%d/.local/bin/home-lan-probe 192.168.51.17"
  HostName claude.home.conecrazy.ca
  ProxyJump none
Match host workstation exec "%d/.local/bin/home-lan-probe 192.168.51.12"
  HostName workstation.home.conecrazy.ca
  ProxyJump none
Host claude
  HostName claude.home.conecrazy.ca
  ProxyJump home-secure.conecrazy.ca,workstation.home.conecrazy.ca
Host workstation
  HostName workstation.home.conecrazy.ca
  ProxyJump home-secure.conecrazy.ca
```

- `%d` is the local home directory, so the probe resolves without an interactive PATH.
- `ProxyJump none` is load-bearing (see Measurements).
- The `Match` blocks sit before every `Host` block that sets `HostName` or `ProxyJump`
  for these names.
- `User bruce` and `IdentityFile ~/.ssh/home` come from a `Host claude workstation` block,
  because Host patterns match the alias, not the HostName.
- The workstation password hop gets `ControlMaster auto`, `ControlPath ~/.ssh/cm-%C` and
  `ControlPersist 10m`, so the password is typed once per 10 minutes rather than once per
  tab. It goes on `Host workstation.home.conecrazy.ca` and the `workstation` aliases.
- The `*-home-tmux` aliases and their `RemoteCommand` block are deleted. The plain `*-home`
  aliases stay, as an explicit force-Cloudflare route.

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
ExecStart=%h/.local/bin/repo-session --detached --all

[Install]
WantedBy=default.target
```

`RemainAfterExit=yes` keeps the unit active, so systemd never stops it, and its default
`KillMode=control-group` never kills the tmux server it started.

### 6. Install (`setup_env.sh -t setup_user`)

On every machine, link `bin/repo-session` and `bin/home-lan-probe` into `~/.local/bin` with
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
  - Then the seven session tabs: `ssh -t claude repo-session <dir>` for each `claude` dir,
    and `ssh -t workstation repo-session terraform_ansible/ansible`.
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
  - The same two cases for `workstation`.
  - A guard asserts that no `Host` pattern ending `-home-tmux` remains.
- **Warp**: every file under `.warp/launch_configurations/` parses as YAML. In each config,
  the set of `repo-session` arguments equals the union of the `REPO_SESSIONS` lists, so the
  tabs cannot drift from the list.
- **Unit**: `systemd-analyze --user verify` passes on the unit where `systemd-analyze` is
  available; the test is skipped, with a message, where it is not.
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
- **R6.** `.ssh/config` has `Match host claude exec "%d/.local/bin/home-lan-probe 192.168.51.17"` and `Match host workstation exec "%d/.local/bin/home-lan-probe 192.168.51.12"` blocks, each setting `HostName <host>.home.conecrazy.ca` and `ProxyJump none`, placed before any `Host` block that sets `HostName` or `ProxyJump` for those names.
- **R7.** When the probe fails, `ssh -G claude` resolves `proxyjump home-secure.conecrazy.ca,workstation.home.conecrazy.ca` and `ssh -G workstation` resolves `proxyjump home-secure.conecrazy.ca`.
- **R8.** `.ssh/config` sets `ControlMaster auto`, `ControlPath ~/.ssh/cm-%C` and `ControlPersist 10m` for `workstation.home.conecrazy.ca`.
- **R9.** `.ssh/config` contains no `Host` pattern ending in `-home-tmux` and no `RemoteCommand`.
- **R10.** `config/repo-sessions.sh` maps `claude` to `etch-cli etch-config dotfiles ai-config ai-devops math` and `workstation` to `terraform_ansible/ansible`.
- **R11.** A tracked `repo-sessions.service` user unit has `Type=oneshot`, `RemainAfterExit=yes`, `ExecStart=%h/.local/bin/repo-session --detached --all` and `WantedBy=default.target`.
- **R12.** `setup_user` links `repo-session` and `home-lan-probe` into `~/.local/bin` on every machine. On a Linux host with a `REPO_SESSIONS` entry, it also links the unit into `~/.config/systemd/user/`, runs `systemctl --user daemon-reload` and `systemctl --user enable repo-sessions.service` (never `start`), and runs `sudo loginctl enable-linger "${USER}"` only when Linger is `no`.
- **R13.** On a host with a `REPO_SESSIONS` entry, doctor FAILs `repo-sessions` with remedy `sudo loginctl enable-linger "$USER"` when Linger is off, and with remedy `./setup_env.sh -t setup_user` when the unit is not enabled. It passes otherwise, and is silent on a host without an entry.
- **R14.** `.warp/launch_configurations/` holds `studio.yaml`, `laptop.yaml` and `reception.yaml` and no `launch_config.yaml`. In each, the session tabs run `ssh -t <host> repo-session <dir>` for exactly the union of the `REPO_SESSIONS` lists. `studio.yaml` adds tabs `update-studio` (local), `update-laptop`, `update-workstation` and `update-claude` (`ssh -t <host>`), `laptop.yaml` adds `update-laptop` (local), and `reception.yaml` adds none.
- **R15.** The `lib/launch_agents.sh` comment reads "the Studio is always up" and no longer says "the Studio is the tmux host".
- **R16.** `.ssh/config` gives the aliases `claude` and `workstation` `User bruce` and `IdentityFile ~/.ssh/home`.
- **V1.** After a reboot of `claude` with the unit installed, `tmux ls` lists all six sessions, each pane running `claude`.
- **V2.** From the laptop off the home LAN, a second session tab within 10 minutes of the first does not prompt for the workstation password.
- **V3.** From the Studio, `ssh -G claude` shows no `proxyjump`; from reception, it shows the Cloudflare chain.
- **N1.** No session is created, killed or restarted by `setup_user` or by installing the unit; existing sessions are left alone.
- **N2.** No launch config runs `setup_env.sh -t update` automatically.
- **N3.** No `claude --continue` or `--resume` in any session start.
- **N4.** No change to the `*-home` aliases' existing ProxyJump routes.
</content>

</invoke>
