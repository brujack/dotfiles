# ADR-0048: tmp.mount inode ceiling via drop-in

**Date:** 2026-10-20
**Status:** Accepted

## Context

On 2026-10-20, on `claude`, `/tmp` reached 100% of its inodes. It is a tmpfs mounted with
`nr_inodes=1048576`, which is systemd's stock `tmp.mount` default (`nr_inodes=1m`). After that,
every session's Bash tool failed with `ENOSPC` when it tried to create its scratchpad. A
pushed branch whose pre-push suite stalled on the full filesystem sat for 12h51m.

The existing cleanup did not help. `/usr/lib/tmpfiles.d/tmp.conf` carries a 10-day age rule,
but `claude` had booted nine days earlier (2026-10-11) and a tmpfs starts empty, so nothing in
`/tmp` was old enough to delete. After two manual cleanups `/tmp` held 330,691 inodes (32%);
after a further vetted cleanup it held 30,615 (3%).

Nobody chose `nr_inodes=1m` for this machine, which has 247G of RAM and already allows `/tmp`
50% of it for data. On tmpfs `nr_inodes` is a cap, not a reservation: kernel memory is spent
only on inodes in use.

Two placements were weighed for the ceiling:

- terraform_ansible. Rejected: `claude` and the workstation are not in its inventory
  (`ansible/environments/home/hosts` has no development box).
- dotfiles, in `install_ubuntu_packages`. Chosen: it already provisions these boxes and
  already runs `sudo` for apt keyrings, dpkg and the sysctl.d steps of ADR-0044.

An automated reaper of stale scratch was also designed and is deferred; this ADR covers only
the ceiling.

## Decision

- `_install_ubuntu_tmp_inodes` is a step of `install_ubuntu_packages`, run after
  `kernel_keys`. It does nothing (prints `skipped (no tmp.mount)`) where systemd reports no
  `tmp.mount` FragmentPath.
- It writes the drop-in `/etc/systemd/system/tmp.mount.d/override.conf` (constant
  `TMP_MOUNT_DROPIN`) with `nr_inodes=16m` (`TMP_NR_INODES=16777216`), then runs
  `systemctl daemon-reload`.
- It writes only when the drop-in is absent or its `nr_inodes` is lower than
  `TMP_NR_INODES`. A higher existing value is never lowered. It reads the file back after
  writing it.
- There is no live remount. The step never runs `mount`. While the live `nr_inodes` is lower
  than the configured value, every run prints a notice naming the manual command,
  `sudo mount -o remount,nr_inodes=16m /tmp`. The ceiling takes effect at next boot.
- Why no remount: a remount under every live session could not be verified without root, and
  `/tmp` was at 3% after cleanup, so there is no urgency that justifies the risk of breaking
  all sessions at once.

## Consequences

- A drop-in's `Options=` replaces the unit's line rather than editing it, so
  `TMP_MOUNT_OPTIONS` repeats the stock options (`mode=1777,strictatime,nosuid,nodev,size=50%%,`
  `x-systemd.graceful-option=usrquota`) with only `nr_inodes` changed. If a systemd update
  changes the stock options, the copy goes stale. The step compares the stock unit's options
  (read from FragmentPath) with its copy, ignoring `nr_inodes`, and prints
  `stock tmp.mount options changed; review <drop-in>` on a difference. It warns; it does not
  rewrite the drop-in.
- A host gets the ceiling on its next `-t setup` or `-t developer` run, and it applies at the
  next boot. Until then `/tmp` keeps the old cap, and the notice repeats on each run.
- Linux only. The step is skipped where there is no `tmp.mount` unit, such as macOS and
  WSL2 without systemd.
- Behaviour beyond the spec, added in the implementation:
  - A drop-in that exists but is unreadable, or has no parseable `nr_inodes`, is refused with
    `fix by hand` and the step returns 1. It is never overwritten.
  - A failed write, a read-back mismatch or a failed `daemon-reload` returns 1. A failed
    write does not reach `daemon-reload`.
  - If the live mount options carry no `nr_inodes`, no lag notice is printed: tmpfs's
    default is far above the ceiling, so only an explicit lower value counts as lag.
- Deferred: the reaper of stale scratch. The ceiling postpones exhaustion; it does not stop
  scratch accumulating.

## Related

- Spec: `docs/superpowers/specs/2026-10-20-tmp-inode-reaper-design.md` in ai-config
- Plan: `docs/superpowers/plans/2026-10-20-tmp-inode-ceiling.md` in ai-config
- ADR-0044: [Host kernel limits persist via sysctl.d](0044-host-kernel-limits-persist-via-sysctl-d.md)
