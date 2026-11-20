# ADR-0059: Repo sessions on the Linux hosts, with LAN routing pinned by host key

**Date:** 2026-11-20
**Status:** Accepted

## Context

Every Claude Code session used to run on the Mac Studio, reached from the other Macs through
the `*-home-tmux` aliases (`RemoteCommand tmux attach-session || tmux new-session`). Since
2026-09-19 the sessions run on `claude` (and ansible on `workstation`). Nothing recreated them
after a reboot, nothing reported a missing one, and the Macs had no per-repo entry point.

Reaching `claude` and `workstation` from a Mac has two very different paths. At home the hosts
are on the LAN. Away, the only route is the Cloudflare tunnel through `home-secure.conecrazy.ca`,
which the operator uses daily and which works well. The laptop moves between the home LAN and
foreign networks with unknown address space; reception and the work Macs are never on the home
LAN.

Alternatives considered (spec, Approaches and External Review):

- **LAN detection by DNS or subnet.** Rejected: a foreign network can use the same private
  range, so an address match proves nothing about which machine answers.
- **Always route through Cloudflare.** Rejected by the operator: at home it adds connection
  complexity for no gain.
- **Start the sessions when setup installs the unit.** Rejected: linger must be enabled first
  (N1), and setup must not create sessions as a side effect.
- **Trust on first use for the direct route.** Removed in Phase 3 security review: a Mac that
  pulled `.ssh/config` before running `setup_user` would go direct to a private IP on any
  network and prompt to trust whatever answered.

## Decision

1. **Sessions live on the Linux hosts.** `bin/repo-session` creates or attaches one tmux session
   per repo directory, running `claude --name <dir> --remote-control`. `config/repo-sessions.sh`
   lists the directories per host. On a listed host, `setup_user` enables user linger, links the
   `repo-sessions.service` user unit (`Type=oneshot`, `RemainAfterExit`, `KillMode=process`) and
   enables it without starting it. The unit runs `repo-session --detached --all` at boot. Doctor
   FAILs on linger off, unit not enabled or unit failed, and WARNs per missing session. The Macs
   attach through per-machine Warp launch configs (`ssh -t <host> .local/bin/repo-session <dir>`).
   The `*-home-tmux` aliases are removed.
2. **Routing on macOS is chosen by a probe and secured by a pin.** Darwin-gated `Match exec`
   blocks send `claude` and `workstation` direct to their LAN IPs. They go through the Cloudflare
   ProxyJump chain only when `bin/home-lan-probe` is installed and reports the client off the
   LAN. The probe compares the ed25519 fingerprint the IP offers with a pinned value. That key
   is public, so the probe only chooses the route; it is not the security boundary. The boundary
   is `HostKeyAlias` plus `StrictHostKeyChecking yes` against the tracked
   `.ssh/known_hosts_home`, so an impostor is refused, never prompted. Linux hosts match none of
   these blocks.

## Consequences

- Sessions survive a reboot of `claude` or `workstation`, and doctor names a missing one.
- Each remote-control session runs with the operator's ssh-agent and shell environment. Its
  exposure is gated by the claude.ai account, and only hosts listed in `config/repo-sessions.sh`
  get the unit. This is the operator's explicit choice.
- A custom `UserKnownHostsFile` turns off `UpdateHostKeys`, so rotating either host key means
  editing `.ssh/known_hosts_home` and both fingerprints in the `.ssh/config` `Match` lines.
- After pulling, a Mac must run `setup_user` (which links `known_hosts_home`), or `ssh claude`
  refuses an unknown key until it does.
- Off-LAN, `ssh workstation` still asks for a password after a Cloudflare re-login. The cause is
  unknown and backlogged (spec N7).
- `bin/` is outside the bash-coverage instrumented set (backlogged).

## Related

- Spec: [repo-session-management](../superpowers/specs/2026-11-19-repo-session-management-design.md)
- Plan: [repo-session-management](../superpowers/plans/2026-11-19-repo-session-management.md)
- PR: dotfiles#466
