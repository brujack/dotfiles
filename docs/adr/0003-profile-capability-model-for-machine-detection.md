# ADR-0003: Profile/Capability Model for Machine Detection

**Date:** 2026-03-31
**Status:** Accepted

## Context

`setup_env.sh` used raw hostname comparisons (`[[ "${HOSTNAME}" == "laptop" ]]`) scattered throughout the file. Adding a new machine required searching for and modifying many conditional blocks. Hostname-based logic was not unit-testable without mocking the hostname itself.

## Decision

Introduce a two-layer model:

1. **Profile** — `config/profiles.sh` maps hostnames to named profiles (`personal_laptop`, `mac_workstation`, `mac_mini`, `linux_workstation`, `wsl2_workstation`, `server`).
2. **Capabilities** — `detect_env()` in `lib/detect_env.sh` reads the profile and sets `HAS_*` boolean vars (`HAS_GUI`, `HAS_DEVTOOLS`, `HAS_AWS`, `HAS_K8S`, `HAS_DOCKER`, `HAS_RUST`, `HAS_SNAP`, `HAS_PRINTING`).

All capability-gated code checks `HAS_*` vars, never raw hostnames.

## Consequences

- Adding a new machine requires editing one line in `config/profiles.sh` — no logic changes.
- `HAS_*` vars are testable by setting them directly in BATS tests without mocking hostname.
- Profile names are human-readable and stable across hostname changes.
- Legacy hostname vars (`LAPTOP`, `STUDIO`, etc.) are preserved as readonly aliases in `detect_env.sh` for backwards compatibility.
- Profile and capability maps must be kept in sync when new capabilities are introduced.

## Related

- [Spec: dotfiles-modularization](../superpowers/specs/2026-03-31-dotfiles-modularization-design.md)
- [ADR-0004: Modular lib/ structure](0004-lib-modular-structure-for-setup-env.md)
