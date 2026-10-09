# ADR-0044: Host kernel limits persist via sysctl.d, never lowering a higher value

**Date:** 2026-10-08
**Status:** Accepted

## Context

The terraform_ansible molecule matrix failed 15 of its 32 scenarios at 18 parallel jobs on
`claude`. The host was at the kernel default `fs.inotify.max_user_instances = 128`. At 1024
the same matrix had no failures (the ansible session's measurement). Docker is rootful on
`claude` and `workstation`, so every container's inotify instances count against root's one
budget. That budget is shared with the GitHub runners on both hosts (12 and 6).

Nothing in dotfiles managed a kernel tunable before this. Three placements were weighed:

- A zsh export of `PARALLEL_JOBS` plus a sysctl. Dropped: a shell export reaches only
  shells started after the merge. It also went live before the sysctl changed, which
  recreated the failing configuration of 18 jobs at 128.
- terraform_ansible's `github_runner` role, which already provisions both hosts and
  already uses `ansible.posix.sysctl`. Weighed in review round 2. The operator chose dotfiles.
- dotfiles `-t setup`/`-t developer` with a doctor check. Chosen.

## Decision

- `_install_ubuntu_inotify` is the first step of `install_ubuntu_packages`. It runs only
  where `HAS_DOCKER` is set and systemd is present.
- It writes `fs.inotify.max_user_instances = 1024` to
  `/etc/sysctl.d/90-dotfiles-inotify.conf`. systemd-sysctl re-applies that file at every
  boot, so the value survives a reboot. Restarting `systemd-sysctl` after forcing the value
  to 128 restored 1024 on both hosts.
- The step writes only when the conf is missing or holds a value below 1024. It never
  overwrites a conf it cannot read or parse. It applies only this key, with `sysctl -w`
  rather than `-p`, and only when the live value is below 1024. It reads the file back
  after writing it.
- `-t doctor` fails when the live value or the conf is below 1024. It prints a one-line fix
  rather than `-t developer`.
- `-t update` does not write `/etc`.
- The per-host `PARALLEL_JOBS` default belongs to its consumer, terraform_ansible's
  `ansible/Makefile`, and not to dotfiles.

## Consequences

- A host gets the limit on its next `-t setup` or `-t developer` run. Until then doctor
  names it. Routine `-t update` never applies it.
- WSL2 without systemd is skipped with no signal, because a sysctl.d file would not persist
  there.
- These gaps are deferred, each with a backlog row:
  - A later-sorting sysctl.d file that sets the key lower wins at boot.
  - A hand-edited conf whose last assignment is non-numeric reads as healthy.
  - The doctor remedy can lower a value that was raised by hand.
- 2026-10-08: the step now persists `max(live, 1024)`. A drop-in that sorts before `90-` with a higher value is still overridden at boot and cannot be detected from the live value. Renaming the conf to sort earlier was declined.
- Whether 1024 covers a local matrix and busy runners at the same time is unmeasured. The
  constant `INOTIFY_MAX_USER_INSTANCES` is the one place to raise it.

## Related

- Spec: [2026-10-08-molecule-host-tuning-design.md](../superpowers/specs/2026-10-08-molecule-host-tuning-design.md)
- Plan: [2026-10-08-molecule-host-tuning.md](../superpowers/plans/2026-10-08-molecule-host-tuning.md)
- PR: #323
