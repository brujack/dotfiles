# ADR-0011: linux.sh Split into linux_ubuntu.sh and linux_shared.sh

**Date:** 2026-04-28
**Status:** Accepted

## Context

ADR-0004 established the `lib/` modular structure with `lib/linux.sh` as the single Linux-specific file. As dotfiles expanded to manage both Ubuntu (main workstation) and potentially other Linux distributions, `lib/linux.sh` grew to mix Ubuntu-specific apt/snap/dpkg commands with logic that was general to all Linux systems (rbenv, chruby, PATH detection, shared tooling).

The split was driven by three pressures:

- Ubuntu-specific code (apt-get, snap, dpkg, Ubuntu version checks) should not run on non-Ubuntu Linux systems.
- Shared Linux logic (PATH exports, `detect_env` usage, non-package-manager tooling) needed to be accessible without pulling in Ubuntu-specific side effects.
- BATS tests for Ubuntu behavior needed to isolate Ubuntu-specific functions from shared ones to allow clean test setup without mocking irrelevant package manager calls.

## Decision

Split `lib/linux.sh` into two files:

| File                  | Responsibility                                                                                         |
| --------------------- | ------------------------------------------------------------------------------------------------------ |
| `lib/linux_ubuntu.sh` | All Ubuntu-specific functions: apt installs, snap, dpkg, package manager guards, Ubuntu version checks |
| `lib/linux_shared.sh` | Functions common to all Linux systems: rbenv/chruby setup, PATH manipulation, shared tooling installs  |

`setup_env.sh` sources both files. Platform detection in `lib/detect_env.sh` determines which functions are called at runtime — both files are sourced on all Linux machines, but Ubuntu-specific functions guard themselves with `[[ "${DISTRO}" == "Ubuntu" ]]` or are only called from Ubuntu-specific workflows.

Coverage floors were adjusted per-file after the split: each file has independent coverage targets reflecting reachable branches on the test machine.

## Consequences

- Linux coverage tests can import only the relevant file (`linux_ubuntu.sh` or `linux_shared.sh`) for cleaner test isolation without unwanted side effects from the other file.
- Non-Ubuntu Linux support is possible without modifying the Ubuntu-specific file.
- `lib/linux_shared.sh` is the correct import for cross-platform Linux logic in BATS tests.
- BATS tests that previously sourced `linux.sh` must be updated to source the appropriate split file.
- `lib/linux.sh` is removed; any reference to it in `setup_env.sh` or tests is a bug.

## Related

- [ADR-0004: Modular lib/ structure for setup_env.sh](0004-lib-modular-structure-for-setup-env.md)
- [ADR-0003: Profile/capability model for machine detection](0003-profile-capability-model-for-machine-detection.md)
