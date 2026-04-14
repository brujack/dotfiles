# ADR-0004: Modular lib/ Structure for setup_env.sh

**Date:** 2026-03-31
**Status:** Accepted

## Context

`setup_env.sh` was a single file exceeding 2000 lines. Finding any function required grep. Tests were impossible because sourcing the entire file triggered side effects (installs, symlinks, etc.). All platforms, all tools, and all workflows were interleaved.

## Decision

Split `setup_env.sh` into a thin dispatcher that sources seven purpose-specific library files in dependency order:

| File                | Responsibility                                                             |
| ------------------- | -------------------------------------------------------------------------- |
| `lib/constants.sh`  | Version pins, download URLs, directory variables                           |
| `lib/helpers.sh`    | Logging (`log_info/warn/error`), `safe_link`, install guards, brew helpers |
| `lib/detect_env.sh` | OS/version detection + profile/capability resolution                       |
| `lib/macos.sh`      | macOS-specific install functions                                           |
| `lib/linux.sh`      | Linux-specific install functions                                           |
| `lib/developer.sh`  | Cross-platform dev tooling (Ruby, Python, Ansible, etc.)                   |
| `lib/workflows.sh`  | Top-level workflow functions dispatched by `setup_env.sh`                  |

`setup_env.sh` itself only parses args and dispatches to `run_*` functions in `lib/workflows.sh`.

## Consequences

- Each lib file has a single responsibility and can be sourced independently in BATS tests without triggering side effects from other files.
- macOS- and Linux-specific code is cleanly separated — no platform sprawl in shared files.
- New platform support can be added as a new `lib/<platform>.sh` file.
- `setup_env.sh` must source all lib files in dependency order at startup (`constants` → `helpers` → `detect_env` → platform libs → `workflows`).

## Related

- [Spec: dotfiles-modularization](../superpowers/specs/2026-03-31-dotfiles-modularization-design.md)
- [ADR-0003: Profile/capability model](0003-profile-capability-model-for-machine-detection.md)
