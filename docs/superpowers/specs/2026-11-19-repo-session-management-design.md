# Repo session management (tmux, systemd, Warp, ssh routing) — design

- **Date:** 2026-11-19
- **Status:** Approved
- **Approved:** 2026-11-19

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
  probe runs and no route changes on the Linux hosts. The only `Match exec` work there is a
  `$SHELL -c` (zsh, which sources `~/.zshenv`) evaluating the `uname -s` test, which
  fails.
- Off the LAN, the workstation password is asked only on the first ssh after a Cloudflare
  web re-login, which happens every few days. While the cloudflared token is valid,
  off-LAN ssh connects with no prompt (operator, 2026-11-19). So no connection-sharing
  machinery is built: after a re-login, open one tab first.
- Reception and two other work Macs (`office`, `home`) live in a different namespace
  (`*.centrepointe.genexxelearning.ca`, e.g. `office.centrepointe.genexxelearning.ca`), and
  reception ssh's directly to the other two. All three are managed by this repo, so they
  receive the same `.ssh/config` and Mac scripts. Their routing to each other is untouched.
  The work LAN is `192.168.10.0/24` (operator, 2026-11-19: `nslookup office` on reception
  gave server `192.168.10.5` and `office.centrepointe.genexxelearning.ca` at `192.168.10.12`),
  disjoint from the home `192.168.51.0/24`. The probe therefore fails on a work Mac, which
  then reaches `claude`/`workstation` through Cloudflare, so no hostname rule is needed.

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
| `ssh-keyscan -T 1 -t ed25519 <ip> \| ssh-keygen -lf -` | Studio | `192.168.51.17` gives claude's fingerprint in 0.04 s; unreachable gives nothing in 1.04 s |
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
  reports each failure on stderr while continuing. The exit code is 0 when every dir
  succeeded, otherwise 1.
- **List lookup.** The list is read from
  `${REPO_SESSIONS_FILE:-${HOME}/git-repos/personal/dotfiles/config/repo-sessions.sh}`, a
  fixed path, never from `$(dirname "${BASH_SOURCE[0]}")`. The installed copy is a
  `safe_link` symlink in `~/.local/bin`, and through the symlink that idiom resolves to
  `~/.local/config/` (measured, external review round 1). A missing or unreadable list
  exits 3, with a message naming the path. A readable list with no entry for this host
  exits 0, printing `repo-session: no sessions listed for <host>`. The two are distinct, so
  a broken install can never pass as "nothing to do".
- **Trailing slash.** Trailing `/` characters are stripped from `<dir>` before the name is
  derived, so `dotfiles/` (as tab completion gives) names the session `dotfiles`.
- It refuses, with exit 2 and a message naming the argument, any `<dir>` that is empty
  (including after stripping trailing `/`), absolute, contains a `..` component, or does
  not exist as a directory. ssh passes the
  argument from another machine, so a typo must not create a stray session in `$HOME`.
- If `exec zsh` follows a failed `claude`, the pane stays alive, so a boot-time failure
  leaves a shell in which to rerun `claude`.

### 2. `bin/home-lan-probe` (new script)

`home-lan-probe <ip> <fingerprint>` exits 0 only when the ssh server at `<ip>` presents an
ed25519 host key whose SHA256 fingerprint equals `<fingerprint>`, and 1 otherwise.

- It runs `ssh-keyscan -T 1 -t ed25519 <ip>`, pipes the result through `ssh-keygen -lf -`,
  and compares the fingerprint field.
- **Why identity, not reachability:** the laptop travels to networks with unknown address
  space. A foreign network that also uses `192.168.51.0/24`, with any ssh server at `.17`,
  would pass a TCP probe and send the laptop direct, where the host-key check refuses the
  connection. A fingerprint mismatch instead fails the probe, so the laptop falls back to
  Cloudflare.
- `ssh-keyscan` behaves the same on macOS and Linux. Measured from the Studio on
  2026-11-19: `192.168.51.17` returned `SHA256:ng/HWNyh2AZ1gm9iMy1Vd59+VFq8Sx00SJ6Uh3a7qfY` in 0.04 s, and an unreachable address
  returned nothing in 1.04 s.
- A missing `ssh-keyscan`, no output, or any mismatch exits 1. On empty input
  `ssh-keygen -lf -` exits 255 (measured), so the probe maps every non-match to 1.
- Seam: `_SSH_KEYSCAN_BIN` (default `ssh-keyscan`). `ssh-keyscan` lives in `/usr/bin` on
  both platforms, so a `PATH` mock cannot reach the absent case without also removing the
  toolchain.
- Pinned fingerprints (ed25519, measured 2026-11-19): `claude` `SHA256:ng/HWNyh2AZ1gm9iMy1Vd59+VFq8Sx00SJ6Uh3a7qfY`, `workstation`
  `SHA256:ZVFVKdcncNrEMmWrb/4gDdgn6NP0lgpQm1vxyFe1y/o`. A host-key rotation must update the `.ssh/config` `Match` lines.

### 3. ssh routing (`.ssh/config`)

On macOS, the bare names `claude` and `workstation` become routing aliases. On Linux, no
block applies and both names resolve exactly as today. **The default is direct.** The
Cloudflare chain applies only when the probe exists and reports that the client is off the
LAN:

```
Match host claude exec "[ \"$(uname -s)\" = Darwin ] && test -x $HOME/.local/bin/home-lan-probe && ! $HOME/.local/bin/home-lan-probe 192.168.51.17 SHA256:ng/HWNyh2AZ1gm9iMy1Vd59+VFq8Sx00SJ6Uh3a7qfY"
  ProxyJump home-secure.conecrazy.ca,workstation.home.conecrazy.ca
Match host workstation exec "[ \"$(uname -s)\" = Darwin ] && test -x $HOME/.local/bin/home-lan-probe && ! $HOME/.local/bin/home-lan-probe 192.168.51.12 SHA256:ZVFVKdcncNrEMmWrb/4gDdgn6NP0lgpQm1vxyFe1y/o"
  ProxyJump home-secure.conecrazy.ca
Match host claude exec "[ \"$(uname -s)\" = Darwin ]"
  HostName 192.168.51.17
  HostKeyAlias claude
  User bruce
  IdentityFile ~/.ssh/home
Match host workstation exec "[ \"$(uname -s)\" = Darwin ]"
  HostName 192.168.51.12
  HostKeyAlias workstation
  User bruce
  IdentityFile ~/.ssh/home
```

- **Linux hosts are untouched.** Every block is gated on the `uname -s` test, so on
  `claude` and `workstation` no option changes and no probe runs. `ssh workstation` keeps
  resolving through DNS and the existing `known_hosts` entry (N6).
- **Host keys.** Host-key lookup follows `HostName`. Every machine's `known_hosts` holds
  these hosts under the bare names `claude` and `workstation`, and none under
  `*.home.conecrazy.ca` (measured with `ssh-keygen -F` on `claude`, `workstation` and the
  Studio, Step 8 round 4). A `HostName` of the FQDN made BatchMode connects fail with
  `Host key verification failed`. The literal `HostKeyAlias` keeps the existing entries in
  use on both routes. `HostKeyAlias %n` is not token-expanded on 10.2p1 (measured), so the
  alias is spelled per host.
- **Tracked host keys.** Each Darwin block, plus a
  `Match host workstation.home.conecrazy.ca exec "[ \"$(uname -s)\" = Darwin ]"` block for
  the jump hop, sets
  `UserKnownHostsFile ~/.ssh/known_hosts ~/.ssh/known_hosts_home`. The tracked file
  `.ssh/known_hosts_home`, linked to `~/.ssh/known_hosts_home` on macOS, holds exactly three
  ed25519 lines:
  - `claude ssh-ed25519 …`, fingerprint `SHA256:ng/HWNyh2AZ1gm9iMy1Vd59+VFq8Sx00SJ6Uh3a7qfY`
  - `workstation ssh-ed25519 …`, fingerprint `SHA256:ZVFVKdcncNrEMmWrb/4gDdgn6NP0lgpQm1vxyFe1y/o`
  - `workstation.home.conecrazy.ca ssh-ed25519 …`, the same key as `workstation`

  The bare-name `known_hosts` entries were measured only on `claude`, `workstation` and the
  Studio, and reception and the laptop have reached these hosts only through the FQDN
  `*-home` aliases. Shipping the keys removes trust-on-first-use on both routes for every
  Mac, including the jump hop that the `claude` chain takes through
  `workstation.home.conecrazy.ca`. Host public keys are not secrets.
- **No DNS dependency.** `HostName` is the IP the probe just verified, so a client that
  reaches `192.168.51.0/24` without the home resolver (custom DNS, DoH, a private-network
  route) still connects. Neither name has a public DNS record (measured with `dig` against
  `1.1.1.1` and `8.8.8.8`).
- **Work Macs** are off the home LAN (`192.168.10.0/24`), so the probe fails and they get
  the Cloudflare chain.
- **Failure direction.** A missing, non-executable or failing probe means direct, which is a
  plain connect to the LAN IP. On a work Mac in that state the direct route fails, until
  `setup_user` runs there.
- **`$HOME`, not `%d`.** `%d` comes from the passwd entry and ignores `HOME`, which makes the
  routing untestable. `Match exec` runs through the user's `$SHELL -c` (zsh on every host
  here), not `sh -c`: with `SHELL=/bin/false` the exec failed and the `Match` did not apply
  (measured, external review round 1, OpenSSH 10.2p1). `$HOME` expands there. The commands
  are POSIX, so they behave the same under zsh and bash. An `exec` runs only for a host the
  `Match host` names.
- The fingerprint argument survives ssh_config parsing intact (`+`, `/`, `=`; base64 has no
  `%`): a stub probe recorded the exact argv on 10.2p1 and 10.5p1 (Step 8 round 4).
- `ProxyJump` is set only in the off-LAN `Match` blocks, which come first. The
  first-obtained value wins, so the Darwin blocks below them cannot add a jump on the LAN.
- No ControlMaster is configured. The workstation password appears only after a Cloudflare
  re-login (see Decisions).
- The `*-home-tmux` aliases and their `RemoteCommand` block are deleted. The plain `*-home`
  aliases stay, as an explicit force-Cloudflare route.

### 4. Per-host session list (`config/repo-sessions.sh`)

A tracked bash file defining `REPO_SESSIONS`, an associative array from hostname
(`hostname -s`) to a space-separated list of dirs:

- `claude`: `etch-cli etch-config dotfiles ai-config ai-devops math`
- `workstation`: `terraform_ansible/ansible`

A host with no entry has no sessions.

### 5. `repo-sessions.service` (systemd user unit)

Its distinct value over `repo-session`'s `-A` is that the `--remote-control` sessions exist
after a reboot before any terminal attaches. All seven panes run
`claude --name <repo> --remote-control`, so the sessions are reachable from claude.ai
without an ssh client.

```
[Unit]
Description=Create repo tmux sessions (repo-session --all)

[Service]
Type=oneshot
RemainAfterExit=yes
KillMode=process
TimeoutStartSec=180
ExecStartPre=-/usr/bin/timeout 60 /bin/sh -c 'until nc -z -w 1 api.anthropic.com 443; do sleep 1; done'
ExecStart=%h/.local/bin/repo-session --detached --all

[Install]
WantedBy=default.target
```

- **`KillMode=process` keeps the tmux server alive** even when the unit fails or is
  stopped. Measured in Step 8 with transient units: under `control-group` a failed oneshot
  killed its forked daemon; under `process` the daemon survived both a failure and a
  `stop`.
- **`ExecStart` has no `-` prefix,** so a boot in which any dir failed leaves the unit
  `failed`. Doctor reports that (component 7).
- **`ExecStartPre=-` waits up to 60 s for `api.anthropic.com:443`,** bounded by `timeout`.
  A user unit cannot order itself after the system's `network-online.target`. The `-`
  makes a wait timeout non-fatal.
- **`TimeoutStartSec=180`** sits above the 60 s wait plus `ExecStart`. The user manager's
  default is 90 s, and a start timeout fails the unit before `ExecStart` runs (measured).

### 6. Install (`setup_env.sh -t setup_user`)

- On macOS, link `bin/home-lan-probe` into `~/.local/bin`.
- On a Linux host with a `REPO_SESSIONS` entry:
  - Link `bin/repo-session` into `~/.local/bin`.
  - Create `~/.config/systemd/user/` if absent (`safe_link` does not create parents), then
    link the unit into it.
  - Run `systemctl --user daemon-reload` and `systemctl --user enable repo-sessions.service`.
    The unit is enabled, not started, so it acts from the next boot and leaves running
    sessions alone.
  - Run `sudo loginctl enable-linger "${USER}"` only when `loginctl show-user` reports
    `Linger=no`.
- All links use `safe_link`. Seams: `_SYSTEMD_USER_DIR`, `_SYSTEMCTL_BIN`, `_LOGINCTL_BIN`
  and `_TMUX_BIN`.

### 7. Doctor

On a host with a `REPO_SESSIONS` entry, `-t doctor` reports `repo-sessions` as:

- FAIL when Linger is off, with remedy `sudo loginctl enable-linger "$USER"`.
- FAIL when `systemctl --user is-enabled repo-sessions.service` exits non-zero, with remedy
  `./setup_env.sh -t setup_user`. The check keys on the exit code: before `enable`, a
  linked unit prints `linked` with rc 1 (measured, systemd 259).
- FAIL when `systemctl --user is-failed repo-sessions.service` reports `failed`, with remedy
  `systemctl --user restart repo-sessions.service`. The `failed` state otherwise stays
  latched until the next boot. A restart re-runs `--all` idempotently, keeps the existing
  sessions under `KillMode=process`, and clears the state only if every dir succeeds
  (measured with a transient unit, Step 8 round 4).
- WARN, naming each one, for every listed dir whose session is missing
  (`tmux has-session -t "=<name>"` fails), with remedy `repo-session --detached --all`.
- PASS otherwise.

A host without an entry is not checked.

### 8. Warp launch configs (`.warp/launch_configurations/`)

Every Mac uses Warp. `launch_config.yaml` is deleted.

- `studio.yaml`:
  - `update-studio`: local, cwd `~/git-repos/personal/dotfiles`.
  - `update-laptop`, `update-workstation`, `update-claude`: `ssh -t <host>` to a shell.
    They do not run the update; that stays manual.
  - Then the seven session tabs: `ssh -t claude .local/bin/repo-session <dir>` for each
    `claude` dir, and `ssh -t workstation .local/bin/repo-session terraform_ansible/ansible`.
- `laptop.yaml`: `update-laptop` (local), then the same seven session tabs.
- `reception.yaml`: the seven session tabs only.

The remote path is spelled out because a remote ssh command runs non-interactive zsh,
whose PATH lacks `~/.local/bin` (measured on `workstation`, Step 8). It is relative
because ssh starts the command in `$HOME` (measured: `ssh workstation pwd` gives
`/home/bruce`). Every session tab is titled with its session name.

### 9. Comment fix

`lib/launch_agents.sh`, above the LaunchAgent installer: "the Studio is the tmux host and is
always up" becomes "the Studio is always up". The single-runner rationale is unchanged.

## Testing

- **bats `repo-session`** (tmux mocked through `tests/mocks/`):
  - session name for `dotfiles` and for `terraform_ansible/ansible` (`ansible`)
  - `-A` in attach mode, `-d` in `--detached`
  - `--detached` does nothing when `has-session` succeeds, and creates otherwise
  - `--all` walks the host's list, continues past one failing dir and exits 1; exits 0 when
    all succeed
  - empty, absolute, `..` and missing dirs each exit 2 without calling tmux
  - `dotfiles/` names the session `dotfiles`; `/` alone exits 2
  - `--all` run through a `safe_link` symlink in a fixture `~/.local/bin`, with
    `REPO_SESSIONS_FILE` unset and `HOME` at a fixture holding
    `git-repos/personal/dotfiles/config/repo-sessions.sh`, reads that list
  - a missing list exits 3 naming the path; a host absent from a readable list exits 0
    with the `no sessions listed` message
- **bats `home-lan-probe`**: `ssh-keyscan` replaced through `_SSH_KEYSCAN_BIN` (no real
  network call in any case). A matching fingerprint exits 0.
  A different one, empty keyscan output, and a missing `ssh-keyscan` each exit 1. One case
  pins that the real `ssh-keygen -lf -` parses the mock's output, so the fingerprint field
  is not assumed.
- **ssh routing**: real `ssh -G -F .ssh/config`, with `HOME` pointed at a fixture holding a
  stub `~/.local/bin/home-lan-probe`, `uname` mocked on `PATH`, and `SHELL=/bin/sh` pinned
  in `setup()` (`Match exec` runs under `$SHELL -c`; a `PATH` stub reaches it). One
  further case repeats the Darwin probe-exit-1 check with `SHELL` set to zsh, which is what
  the Macs run:
  - Darwin, probe exit 1: `claude` resolves `hostname 192.168.51.17`,
    `hostkeyalias claude` and
    `proxyjump home-secure.conecrazy.ca,workstation.home.conecrazy.ca`; `workstation`
    resolves `hostname 192.168.51.12`, `hostkeyalias workstation` and
    `proxyjump home-secure.conecrazy.ca`.
  - Darwin, probe exit 0, and Darwin, probe absent: the same `hostname` and `hostkeyalias`
    lines and no `proxyjump`.
  - Linux, probe exit 1: both names resolve `hostname claude` / `hostname workstation`
    (unchanged), no `hostkeyalias`, no `proxyjump`, and the stub is never called.
  - On Darwin the stub records exactly `192.168.51.17 SHA256:ng/HWNyh2AZ1gm9iMy1Vd59+VFq8Sx00SJ6Uh3a7qfY` for `claude` and
    `192.168.51.12 SHA256:ZVFVKdcncNrEMmWrb/4gDdgn6NP0lgpQm1vxyFe1y/o` for `workstation`.
  - No `Host` pattern ending `-home-tmux` and no `RemoteCommand` remain, and `controlmaster`
    resolves `false` for both names.
  - On Darwin, `claude`, `workstation` and `workstation.home.conecrazy.ca` resolve
    `userknownhostsfile ~/.ssh/known_hosts ~/.ssh/known_hosts_home`; on Linux they do not.
- **Tracked host keys**: `ssh-keygen -lf .ssh/known_hosts_home` lists exactly three
  ed25519 keys, for `claude`, `workstation` and `workstation.home.conecrazy.ca`, whose
  fingerprints equal the pinned values in the `.ssh/config` `Match` lines.
- **Warp**: every file under `.warp/launch_configurations/` parses as YAML. Each session tab
  is parsed into a (host, dir) pair from `ssh -t <host> .local/bin/repo-session <dir>`.
  In each config the multiset of pairs equals
  `{(h, d) : d in REPO_SESSIONS[h]}` (seven pairs, no duplicates), so a tab aimed at the
  wrong host fails. No `exec` line contains `repo-session` without the `.local/bin/`
  prefix.
- **Remote PATH**: a session tab's remote command, run under
  `env -i HOME="$HOME" PATH=/usr/bin:/bin zsh -c` from a fixture `$HOME` holding
  `.local/bin/repo-session`, resolves and runs it.
- **Unit**: `systemd-analyze --user verify` passes where available (skipped with a message
  elsewhere). The unit carries `KillMode=process`, `TimeoutStartSec=180` and an `ExecStart=`
  with no `-` prefix.
- **Installer** (seams):
  - linger is enabled only when `Linger=no`
  - the unit is enabled, not started
  - a second run makes no `sudo` call and no state-changing `enable`
  - macOS gets only `home-lan-probe`; a Linux host without a list gets nothing
- **Doctor**: Linger off, unit not enabled, unit failed with all sessions present (remedy
  names `systemctl --user restart repo-sessions.service`), one session missing and two
  sessions missing (each named in the WARN), all OK, and a host not in the list.

## Requirements

- **R1.** `bin/repo-session <dir>` runs `tmux new-session -A -s "${dir##*/}" -c "${HOME}/git-repos/personal/<dir>"` with pane command `zsh -ic 'claude --name "$(basename "$PWD")" --remote-control; exec zsh'`.
- **R2.** `bin/repo-session --detached <dir>` adds `-d`, and exits 0 without creating a session when `tmux has-session -t "=<name>"` succeeds.
- **R3.** `bin/repo-session --detached --all` reads its list from `${REPO_SESSIONS_FILE:-${HOME}/git-repos/personal/dotfiles/config/repo-sessions.sh}` (never relative to the script's own path), runs once per dir in this host's `REPO_SESSIONS` entry, continues past a failing dir, and exits 1 if any dir failed, else 0; a missing or unreadable list exits 3 naming the path; a readable list with no entry for this host exits 0 printing `repo-session: no sessions listed for <host>`.
- **R4.** `bin/repo-session` strips trailing `/` from `<dir>`, then exits 2, naming the argument, without calling tmux, for a `<dir>` that is empty, absolute, contains a `..` component, or is not a directory under `${HOME}/git-repos/personal`.
- **R5.** `bin/home-lan-probe <ip> <fingerprint>` exits 0 only when `${_SSH_KEYSCAN_BIN:-ssh-keyscan} -T 1 -t ed25519 <ip>` piped through `ssh-keygen -lf -` yields a SHA256 fingerprint equal to `<fingerprint>`; mismatch, empty output or a missing `ssh-keyscan` exits 1.
- **R6.** `.ssh/config` carries, in this order: `Match host claude exec "[ \"$(uname -s)\" = Darwin ] && test -x $HOME/.local/bin/home-lan-probe && ! $HOME/.local/bin/home-lan-probe 192.168.51.17 SHA256:ng/HWNyh2AZ1gm9iMy1Vd59+VFq8Sx00SJ6Uh3a7qfY"` setting `ProxyJump home-secure.conecrazy.ca,workstation.home.conecrazy.ca`; `Match host workstation exec "[ \"$(uname -s)\" = Darwin ] && test -x $HOME/.local/bin/home-lan-probe && ! $HOME/.local/bin/home-lan-probe 192.168.51.12 SHA256:ZVFVKdcncNrEMmWrb/4gDdgn6NP0lgpQm1vxyFe1y/o"` setting `ProxyJump home-secure.conecrazy.ca`; then `Match host claude exec "[ \"$(uname -s)\" = Darwin ]"` setting `HostName 192.168.51.17`, `HostKeyAlias claude`, `User bruce`, `IdentityFile ~/.ssh/home`, and the same for `workstation` with `HostName 192.168.51.12` and `HostKeyAlias workstation`. No `Host claude` or `Host workstation` block exists.
- **R7.** With `HOME` at a fixture and `uname` mocked on `PATH`: on Darwin, `ssh -G claude` resolves `hostname 192.168.51.17` and `hostkeyalias claude`, and `ssh -G workstation` resolves `hostname 192.168.51.12` and `hostkeyalias workstation`; with a probe exiting 1 they add `proxyjump home-secure.conecrazy.ca,workstation.home.conecrazy.ca` and `proxyjump home-secure.conecrazy.ca` respectively, and with the probe exiting 0 or absent no `proxyjump`. On Linux both resolve `hostname claude` / `hostname workstation` with no `hostkeyalias` and no `proxyjump`, and the probe is never invoked.
- **R8.** `.ssh/config` configures no `ControlMaster`, `ControlPath` or `ControlPersist` for `claude`, `workstation` or `workstation.home.conecrazy.ca` (`ssh -G` resolves `controlmaster false`).
- **R9.** `.ssh/config` contains no `Host` pattern ending in `-home-tmux` and no `RemoteCommand`.
- **R10.** `config/repo-sessions.sh` maps `claude` to `etch-cli etch-config dotfiles ai-config ai-devops math` and `workstation` to `terraform_ansible/ansible`.
- **R11.** A tracked `repo-sessions.service` user unit has `Type=oneshot`, `RemainAfterExit=yes`, `KillMode=process`, `TimeoutStartSec=180`, `ExecStartPre=-/usr/bin/timeout 60 /bin/sh -c 'until nc -z -w 1 api.anthropic.com 443; do sleep 1; done'`, `ExecStart=%h/.local/bin/repo-session --detached --all` (no `-` prefix) and `WantedBy=default.target`.
- **R12.** `setup_user` links `home-lan-probe` into `~/.local/bin` on macOS only. On macOS it also links `.ssh/known_hosts_home` to `~/.ssh/known_hosts_home`. On a Linux host with a `REPO_SESSIONS` entry it links `repo-session` into `~/.local/bin`, creates `~/.config/systemd/user/` if absent and links the unit into it, runs `systemctl --user daemon-reload` and `systemctl --user enable repo-sessions.service` (never `start`), and runs `sudo loginctl enable-linger "${USER}"` only when Linger is `no`. Other hosts get none of these.
- **R13.** On a host with a `REPO_SESSIONS` entry, doctor FAILs `repo-sessions` with remedy `sudo loginctl enable-linger "$USER"` when Linger is off, with remedy `./setup_env.sh -t setup_user` when `systemctl --user is-enabled repo-sessions.service` exits non-zero, and with remedy `systemctl --user restart repo-sessions.service` when the unit is `failed`; it WARNs naming each listed dir whose `tmux has-session -t "=<name>"` fails, with remedy `repo-session --detached --all`; it passes otherwise, and is silent on a host without an entry.
- **R14.** `.warp/launch_configurations/` holds `studio.yaml`, `laptop.yaml` and `reception.yaml` and no `launch_config.yaml`. In each, the session tabs run `ssh -t <host> .local/bin/repo-session <dir>` and the multiset of (host, dir) pairs equals `{(h, d) : d in REPO_SESSIONS[h]}` with no duplicates, and no `exec` line contains `repo-session` without the `.local/bin/` prefix. `studio.yaml` adds tabs `update-studio` (local), `update-laptop`, `update-workstation` and `update-claude` (`ssh -t <host>`), `laptop.yaml` adds `update-laptop` (local), and `reception.yaml` adds none.
- **R15.** The `lib/launch_agents.sh` comment reads "the Studio is always up" and no longer says "the Studio is the tmux host".
- **R16.** On macOS, `.ssh/config` sets `UserKnownHostsFile ~/.ssh/known_hosts ~/.ssh/known_hosts_home` for `claude`, `workstation` and `workstation.home.conecrazy.ca` (Darwin-gated `Match` blocks), and the tracked `.ssh/known_hosts_home` holds exactly the three ed25519 entries `claude`, `workstation` and `workstation.home.conecrazy.ca` whose fingerprints are `SHA256:ng/HWNyh2AZ1gm9iMy1Vd59+VFq8Sx00SJ6Uh3a7qfY`, `SHA256:ZVFVKdcncNrEMmWrb/4gDdgn6NP0lgpQm1vxyFe1y/o` and `SHA256:ZVFVKdcncNrEMmWrb/4gDdgn6NP0lgpQm1vxyFe1y/o`.
- **V1.** After a reboot of `claude` and of `workstation` with the unit installed and no ssh login, all seven sessions (six on `claude`, `ansible` on `workstation`) appear in claude.ai's Remote Control session list, and `tmux list-panes -a -F '#{session_name} #{pane_current_command}'` shows `claude` in each.
- **V2.** From the Studio, `ssh -G claude` shows no `proxyjump`; from reception, it shows the Cloudflare chain; from the laptop, it changes between the two when moving on and off the home LAN.
- **V3.** From the laptop on a non-home network, `home-lan-probe 192.168.51.17 SHA256:ng/HWNyh2AZ1gm9iMy1Vd59+VFq8Sx00SJ6Uh3a7qfY` exits 1 and a session tab connects through Cloudflare.
- **N1.** No session is created, killed or restarted by `setup_user` or by installing the unit; existing sessions are left alone.
- **N2.** No launch config runs `setup_env.sh -t update` automatically.
- **N3.** No `claude --continue` or `--resume` in any session start.
- **N4.** No change to the `*-home` aliases' existing ProxyJump routes.
- **N5.** No change to how any host other than `claude` and `workstation` is reached: in particular the work Macs' direct ssh to each other (`*.centrepointe.genexxelearning.ca`) is untouched.
- **N6.** No `.ssh/config` option takes effect on `claude` or `workstation`, and no probe runs there: every ssh connection from them resolves exactly as before this change. The only added work is the `$SHELL -c` that evaluates the failing `uname -s` test.
- **N7.** No connection-sharing wrapper or ControlMaster for the off-LAN route; the workstation password is a once-per-Cloudflare-renewal event.

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

### Round 3 (reviewed at `2bfd9e23`)

Goal-Fit — Finding: no load-bearing defect; the boot unit's distinct value (remote-control sessions up before any terminal attaches) is unstated and undetected (doctor checks only linger and enabled); one test passes on empty output (IP table). Assumption: a detached `claude --remote-control` started by the unit registers for remote control with no input. Disposition: Addressed (operator, 2026-11-19) — consumer stated in component 5, doctor FAIL on `is-failed` and WARN per missing session (R13), V1 now checks remote-control registration; the IP-table test went with `home-ssh`.

Ergonomics — Finding: `home-ssh`'s lock cascades into several simultaneous prompts once sshd's 120 s `LoginGraceTime` drops an unattended owner (measured: workstation runs the default); the prompt tab is unpredictable. Assumption: Warp starts all tab commands eagerly. Disposition: Addressed (operator, 2026-11-19) — operator confirmed the workstation password appears only on the first ssh after a Cloudflare re-login, so `home-ssh`, its lock and ControlMaster were removed (N7); after a re-login, open one tab first.

Risk — Finding: (1) `ExecStart=-` is redundant (`KillMode=process` alone kept the child alive with the unit `failed`, measured) and hides a fully failed boot from doctor; (2) `home-ssh`'s trap is inert under `exec` and deferred TERM (measured in bash); (3) R19's first half was a tautology. Routing, quoting and `controlmaster false` on Linux confirmed on 10.2p1 and 10.5p1. Assumption: as Goal-Fit. Disposition: Addressed (operator, 2026-11-19) — no `-` on `ExecStart` (R11) plus doctor `is-failed` (R13); (2) and (3) removed with `home-ssh`.

Identity probe (operator, 2026-11-19, after round 3 dispatch): the laptop travels to networks with unknown address space, so `home-lan-probe` checks the host-key fingerprint, not TCP reachability (component 2, R5). Reviewed in round 4.

### Round 4, scoped Risk (reviewed at `f31c33cb`; components 2, 3, 5, 7, R5-R8, R11-R13, V1-V3, N6-N7)

Risk — Finding: `HostName %h.home.conecrazy.ca` breaks every non-interactive ssh to `workstation`/`claude` because host-key lookup follows HostName and no machine has `known_hosts` entries under the FQDNs (measured: BatchMode `ssh workstation` from `claude` rc 255); contradicts N6. Secondary: doctor's `is-failed` FAIL stays latched with a remedy that clears nothing; the probe's missing-`ssh-keyscan` case needs a seam. Confirmed: fingerprint argv survives ssh_config parsing on 10.2p1 and 10.5p1; `ssh-keyscan`/`ssh-keygen -lf` field 2 on both platforms; doctor reaches the unit's tmux socket; no-`-` `ExecStart` interacts safely with `restart`. Assumption: the laptop resolves `claude.home.conecrazy.ca` whenever the probe passes. Disposition: Addressed (operator, 2026-11-19) — whole alias block macOS-only, `HostName` is the probed IP plus a literal `HostKeyAlias` (removes the DNS assumption; verified with `ssh -G` across Darwin probe 1/0/absent and Linux), doctor remedy `systemctl --user restart repo-sessions.service`, `_SSH_KEYSCAN_BIN` seam, two more doctor cases (component 3, R5-R7, R13, N6).

## External Review

### Round 1 (reviewed at `e8bbc5c5cf437d945d2830b4fe0e1a99ee1b44c2`)

Report: [round1.md](2026-11-19-repo-session-management-design.external-review/round1.md)

#### Author response

| finding | disposition | evidence | reviewer verdict | operator (Step 9) |
| ------- | ----------- | -------- | ---------------- | ----------------- |
| F1.1 | Fixed | Component 1 and R3: the list is read from `${REPO_SESSIONS_FILE:-${HOME}/git-repos/personal/dotfiles/config/repo-sessions.sh}`, never relative to the script; missing or unreadable exits 3, no entry exits 0 with a message; Testing adds a run through a `safe_link` symlink and the missing-list case | unjudged | accepted (operator, 2026-11-19) |
| F1.2 | Fixed | R14 and the Warp test compare the multiset of (host, dir) pairs against `{(h, d) : d in REPO_SESSIONS[h]}`, no duplicates | unjudged | accepted (operator, 2026-11-19) |
| F1.3 | Fixed | Component 3, Decisions and N6 now say `$SHELL -c` (zsh sources `~/.zshenv`); routing tests pin `SHELL=/bin/sh` in `setup()` and add one zsh case | unjudged | accepted (operator, 2026-11-19) |
| F1.4 | Fixed | Ship the keys rather than measure reception and the laptop: tracked `.ssh/known_hosts_home` with `claude`, `workstation` and `workstation.home.conecrazy.ca` ed25519 entries, wired by Darwin-gated `UserKnownHostsFile` for the two aliases and the jump hop (component 3, R12, R16, tests pin the three fingerprints) | unjudged | accepted (operator, 2026-11-19) |
| F1.5 | Fixed | R4 and component 1 strip trailing `/` before deriving the name; `dotfiles/` and `/` test cases added | unjudged | accepted (operator, 2026-11-19) |
| F1.6 | Fixed | Component 6 and R12 create `~/.config/systemd/user/` before linking the unit | unjudged | accepted (operator, 2026-11-19) |
| F1.7 | Fixed | Component 7 and R13 key the not-enabled FAIL on `systemctl --user is-enabled` exiting non-zero | unjudged | accepted (operator, 2026-11-19) |
| F1.8 | Fixed | V1 covers both hosts: seven sessions, six on `claude`, `ansible` on `workstation` | unjudged | accepted (operator, 2026-11-19) |

Stopped: reviewer recommended stopping in round 1

## Amendments

- R4 -> `bin/repo-session` strips trailing `/` from `<dir>`, then exits 2, naming the argument, without calling tmux, for a `<dir>` that is empty, absolute, contains a `.` or `..` component, whose last component contains `.` or `:`, or is not a directory under `${HOME}/git-repos/personal`. — Task 1 code review measured that `.` and `dotfiles/.` started a session named `.`, and that tmux 3.6 renames `my.repo` to `my_repo`, so `has-session -t =my.repo` never matches and every later `--all` run fails; rejecting keeps the session name equal to the directory name.
- R6 -> `.ssh/config` carries, in this order: `Match host claude exec "[ \"$(uname -s)\" = Darwin ] && test -x $HOME/.local/bin/home-lan-probe && ! $HOME/.local/bin/home-lan-probe 192.168.51.17 SHA256:ng/HWNyh2AZ1gm9iMy1Vd59+VFq8Sx00SJ6Uh3a7qfY"` setting `ProxyJump home-secure.conecrazy.ca,workstation.home.conecrazy.ca`; `Match host workstation exec "[ \"$(uname -s)\" = Darwin ] && test -x $HOME/.local/bin/home-lan-probe && ! $HOME/.local/bin/home-lan-probe 192.168.51.12 SHA256:ZVFVKdcncNrEMmWrb/4gDdgn6NP0lgpQm1vxyFe1y/o"` setting `ProxyJump home-secure.conecrazy.ca`; then `Match host claude exec "[ \"$(uname -s)\" = Darwin ]"` setting `HostName 192.168.51.17`, `HostKeyAlias claude`, `User bruce`, `IdentityFile ~/.ssh/home`, `StrictHostKeyChecking yes`, and the same for `workstation` with `HostName 192.168.51.12` and `HostKeyAlias workstation`. No `Host claude` or `Host workstation` block exists. — Phase 3 security-review: a Mac that pulled `.ssh/config` before `setup_user` linked the probe goes direct to the private IP on any network, and with no pinned key known an impostor there got a trust-on-first-use prompt; both keys are pinned, so refusing an unknown key costs nothing and the jump hop stays unchanged per N4.
- finding R12 (2026-11-20, reviewer both): DIFFERS — Two conditions differ: enable-linger runs whenever the Linger read is not exactly 'Linger=yes' (a malformed read included, per test 'a malformed linger read enables linger'), not only when Linger is no; and systemctl --user enable is skipped when is-enabled already prints 'enabled', so setup_user does not always run enable. The rest matches: macOS links home-lan-probe and known_hosts_home, a listed Linux host links repo-session, mkdir -p's the unit dir, links the unit and daemon-reloads with no start, and other hosts get nothing.
- R12 -> `setup_user` links `home-lan-probe` into `~/.local/bin` on macOS only. On macOS it also links `.ssh/known_hosts_home` to `~/.ssh/known_hosts_home`, creating `~/.ssh` with mode 700 if absent. On a Linux host with a `REPO_SESSIONS` entry it links `repo-session` into `~/.local/bin`; returns 1 if `loginctl show-user "${USER}" -p Linger` fails, and otherwise runs `sudo loginctl enable-linger "${USER}"` whenever that output is not exactly `Linger=yes`; then creates `~/.config/systemd/user/` if absent, links the unit into it, runs `systemctl --user daemon-reload`, and runs `systemctl --user enable repo-sessions.service` unless `systemctl --user is-enabled repo-sessions.service` prints exactly `enabled` (never `start`). Other hosts get none of these. — Phase 3 spec alignment: a malformed Linger read is treated as not lingering (fail toward enabling, matching doctor), and the enable is skipped when already persistently enabled so a re-run changes nothing; `enabled-runtime` exits 0 but does not survive a reboot, so the check keys on the word.
- finding R13 (2026-11-20, reviewer both): DIFFERS — The setup_user-remedy FAIL keys on is-enabled printing anything but 'enabled', not a non-zero exit, so it also FAILs on rc-0 words such as enabled-runtime (test 'an is-enabled word other than enabled (rc 0) fails'); and the WARN names each session's last component (ansible) rather than the listed dir (terraform_ansible/ansible). The linger and failed-unit FAIL remedies, WARN remedy, PASS and silence on unlisted hosts match.
- R13 -> On a host with a `REPO_SESSIONS` entry, doctor FAILs `repo-sessions` with remedy `sudo loginctl enable-linger "$USER"` when `loginctl show-user "$USER" -p Linger` does not print exactly `Linger=yes`, with remedy `./setup_env.sh -t setup_user` when `systemctl --user is-enabled repo-sessions.service` does not print exactly `enabled`, and with remedy `systemctl --user restart repo-sessions.service` when `systemctl --user is-failed repo-sessions.service` prints `failed`; it WARNs naming the session (the last path component) of each listed dir whose `tmux has-session -t "=<name>"` fails, with remedy `repo-session --detached --all`; it passes otherwise, and is silent on a host without an entry. — Phase 3 spec alignment: keyed on the printed word because `enabled-runtime` exits 0 yet is not persistent and a linked, unenabled unit prints `linked`; the WARN names the tmux session, which is what `has-session` checks and what the operator attaches to.
- finding N6 (2026-11-20, reviewer A): VIOLATED — Deleting the -home-tmux aliases (required by R9) changes how ssh claude-home-tmux / workstation-home-tmux resolve on claude and workstation too, so not every ssh connection from them resolves exactly as before; this is a conflict between N6's wording and R9, not an implementation error.
- N6 -> Apart from R9's removal of the `*-home-tmux` aliases and their `RemoteCommand`, no `.ssh/config` option takes effect on `claude` or `workstation`, and no probe runs there: every other ssh connection from them resolves exactly as before this change. The only added work is the `$SHELL -c` that evaluates the failing `uname -s` test. — Phase 3 spec alignment: N6 as written contradicted R9, which deletes aliases on every host; the non-goal is about the new Darwin routing, not the alias removal.
- R6 -> `.ssh/config` carries, in this order: `Match host claude exec "[ \"$(uname -s)\" = Darwin ] && test -x $HOME/.local/bin/home-lan-probe && ! $HOME/.local/bin/home-lan-probe 192.168.51.17 SHA256:ng/HWNyh2AZ1gm9iMy1Vd59+VFq8Sx00SJ6Uh3a7qfY"` setting `ProxyJump home-secure.conecrazy.ca,workstation.home.conecrazy.ca`; `Match host workstation exec "[ \"$(uname -s)\" = Darwin ] && test -x $HOME/.local/bin/home-lan-probe && ! $HOME/.local/bin/home-lan-probe 192.168.51.12 SHA256:ZVFVKdcncNrEMmWrb/4gDdgn6NP0lgpQm1vxyFe1y/o"` setting `ProxyJump home-secure.conecrazy.ca`; then `Match host claude exec "[ \"$(uname -s)\" = Darwin ]"` setting `HostName 192.168.51.17`, `HostKeyAlias claude`, `User bruce`, `IdentityFile ~/.ssh/home`, then `IdentityFile ~/.ssh/id_rsa`, `StrictHostKeyChecking yes`, and the same for `workstation` with `HostName 192.168.51.12` and `HostKeyAlias workstation`. No `Host claude` or `Host workstation` block exists. — Post-merge rollout 2026-11-20: the Studio's `~/.ssh/home` is an ed25519 key (SHA256:F2Nay…) whose `.pub` file holds id_rsa's key, and `claude` trusts only id_rsa (SHA256:1oxkq…); with an IdentityFile set ssh stops trying id_rsa by itself, so an agentless `ssh claude` was refused. The spec's earlier measurement read the mismatched `.pub`.
- R14 -> `.warp/launch_configurations/` holds `studio.yaml`, `laptop.yaml` and `reception.yaml` and no `launch_config.yaml`. In each, the session tabs run `ssh -t <host> .local/bin/repo-session <dir>` and the multiset of (host, dir) pairs equals `{(h, d) : d in REPO_SESSIONS[h]}` with no duplicates, and no `exec` line contains `repo-session` without the `.local/bin/` prefix. `studio.yaml` adds tabs `update-studio` (local), `update-laptop`, `update-workstation` and `update-claude` (`ssh -t <host>`; `update-laptop` uses `laptop-1` when `laptop` does not answer on port 22), and the local tabs `ansible-local` (`git status` in `terraform_ansible/ansible`, no `make` at launch), `ratna` (`ssh -t ratna`), `codex-ai-config` (`tmux new-session -A -s codex-ai-config` in `ai-config`), two `scratch` tabs (`~`, no command), `laptop.yaml` adds `update-laptop` (local) then `scratch`, and `reception.yaml` opens with `update-reception` (local), `ansible-local`, `update-home` (`ssh -t home`), `update-office` (`ssh -t office`) and `scratch`, in that order. Every local update tab runs `git status` in `/Users/bruce/git-repos/personal/dotfiles`. — Operator 2026-11-20: keep the Studio's existing local working tabs (read from Warp's tab state) in the tracked config, and give reception and the laptop their own local tabs; update-laptop's wireless fallback is dotfiles#471.
- R14 -> `.warp/launch_configurations/` holds `studio.yaml`, `laptop.yaml` and `reception.yaml` and no `launch_config.yaml`. In each, the session tabs run `ssh -t <host> .local/bin/repo-session <dir>` and the multiset of (host, dir) pairs equals `{(h, d) : d in REPO_SESSIONS[h]}` with no duplicates, and no `exec` line contains `repo-session` without the `.local/bin/` prefix. `studio.yaml` adds tabs `update-studio` (local), `update-laptop`, `update-workstation` and `update-claude` (`ssh -t <host>`; `update-laptop` uses `laptop-1` when `laptop` does not answer on port 22), and the local tabs `ansible-local` (`export ENV=home` then `git status` in `terraform_ansible/ansible`, no `make` at launch), `ratna` (`ssh -t ratna`), `codex-ai-config` (`tmux new-session -A -s codex-ai-config` in `ai-config`), two `scratch` tabs (`~`, no command), `laptop.yaml` adds `update-laptop` (local) then `scratch`, and `reception.yaml` opens with `update-reception` (local), `ansible-local` (`export ENV=genexxe_centrepointe` then `git status`), `update-home` (`ssh -t home`), `update-office` (`ssh -t office`) and `scratch`, in that order. Every local update tab runs `git status` in `/Users/bruce/git-repos/personal/dotfiles`. — Operator 2026-11-20: ansible-local sets the host's ansible ENV, as typed by hand before; the Studio tab order is dotfiles#473.

## Spec alignment (2026-11-20)

- spec: docs/superpowers/specs/2026-11-19-repo-session-management-design.md
- anchor: 41651de0d617987479ccb13e9cbdd7495eef8f7a
- in scope: R1, R2, R3, R4, R5, R6, R7, R8, R9, R10, R11, R12, R13, R14, R15, R16
- out of scope: none

### Findings

| ID | Reviewer | Verdict | Reason | Amendment |
| --- | --- | --- | --- | --- |
| R12 | both | DIFFERS | Two conditions differ: enable-linger runs whenever the Linger read is not exactly 'Linger=yes' (a malformed read included, per test 'a malformed linger read enables linger'), not only when Linger is no; and systemctl --user enable is skipped when is-enabled already prints 'enabled', so setup_user does not always run enable. The rest matches: macOS links home-lan-probe and known_hosts_home, a listed Linux host links repo-session, mkdir -p's the unit dir, links the unit and daemon-reloads with no start, and other hosts get nothing. | - R12 -> `setup_user` links `home-lan-probe` into `~/.local/bin` on macOS only. On macOS it also links `.ssh/known_hosts_home` to `~/.ssh/known_hosts_home`, creating `~/.ssh` with mode 700 if absent. On a Linux host with a `REPO_SESSIONS` entry it links `repo-session` into `~/.local/bin`; returns 1 if `loginctl show-user "${USER}" -p Linger` fails, and otherwise runs `sudo loginctl enable-linger "${USER}"` whenever that output is not exactly `Linger=yes`; then creates `~/.config/systemd/user/` if absent, links the unit into it, runs `systemctl --user daemon-reload`, and runs `systemctl --user enable repo-sessions.service` unless `systemctl --user is-enabled repo-sessions.service` prints exactly `enabled` (never `start`). Other hosts get none of these. — Phase 3 spec alignment: a malformed Linger read is treated as not lingering (fail toward enabling, matching doctor), and the enable is skipped when already persistently enabled so a re-run changes nothing; `enabled-runtime` exits 0 but does not survive a reboot, so the check keys on the word. |
| R13 | both | DIFFERS | The setup_user-remedy FAIL keys on is-enabled printing anything but 'enabled', not a non-zero exit, so it also FAILs on rc-0 words such as enabled-runtime (test 'an is-enabled word other than enabled (rc 0) fails'); and the WARN names each session's last component (ansible) rather than the listed dir (terraform_ansible/ansible). The linger and failed-unit FAIL remedies, WARN remedy, PASS and silence on unlisted hosts match. | - R13 -> On a host with a `REPO_SESSIONS` entry, doctor FAILs `repo-sessions` with remedy `sudo loginctl enable-linger "$USER"` when `loginctl show-user "$USER" -p Linger` does not print exactly `Linger=yes`, with remedy `./setup_env.sh -t setup_user` when `systemctl --user is-enabled repo-sessions.service` does not print exactly `enabled`, and with remedy `systemctl --user restart repo-sessions.service` when `systemctl --user is-failed repo-sessions.service` prints `failed`; it WARNs naming the session (the last path component) of each listed dir whose `tmux has-session -t "=<name>"` fails, with remedy `repo-session --detached --all`; it passes otherwise, and is silent on a host without an entry. — Phase 3 spec alignment: keyed on the printed word because `enabled-runtime` exits 0 yet is not persistent and a linked, unenabled unit prints `linked`; the WARN names the tmux session, which is what `has-session` checks and what the operator attaches to. |
| N6 | A | VIOLATED | Deleting the -home-tmux aliases (required by R9) changes how ssh claude-home-tmux / workstation-home-tmux resolve on claude and workstation too, so not every ssh connection from them resolves exactly as before; this is a conflict between N6's wording and R9, not an implementation error. | - N6 -> Apart from R9's removal of the `*-home-tmux` aliases and their `RemoteCommand`, no `.ssh/config` option takes effect on `claude` or `workstation`, and no probe runs there: every other ssh connection from them resolves exactly as before this change. The only added work is the `$SHELL -c` that evaluates the failing `uname -s` test. — Phase 3 spec alignment: N6 as written contradicted R9, which deletes aliases on every host; the non-goal is about the new Darwin routing, not the alias removal. |

### Reviewed

- none

### Verifications

- V1: no evidence recorded
- V2: no evidence recorded
- V3: no evidence recorded
