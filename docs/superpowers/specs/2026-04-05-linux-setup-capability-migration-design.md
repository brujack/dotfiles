# Design: Linux setup_env.sh Capability Migration

**Date:** 2026-04-05
**Status:** Approved

## Summary

Migrate the Linux (Ubuntu) section of `setup_env.sh` from deprecated hostname vars (`WORKSTATION`, `CRUNCHER`) to `HAS_*` capability vars. Introduce a new `wsl2_workstation` profile for `cruncher` (WSL2 Ubuntu) and a `HAS_SNAP` capability for `linux_workstation` (desktop Ubuntu) to distinguish the two environments. Update `README.md` to document the difference. Remove the `CRUNCHER` legacy alias from `detect_env.sh`.

## Motivation

`WORKSTATION` and `CRUNCHER` currently both map to `linux_workstation` in `config/profiles.sh`, but they have meaningfully different installation constraints: `workstation` is a desktop Ubuntu machine with full snap support, while `cruncher` is WSL2 where snap is unavailable. This difference is not captured in the capability model, forcing the use of raw hostname vars for snap-gated blocks. Introducing a `wsl2_workstation` profile and `HAS_SNAP` capability makes the distinction explicit and allows all Linux gates to use capability vars.

## Changes

### `config/profiles.sh`

Change `cruncher` to map to a new `wsl2_workstation` profile. Add `snap` to `linux_workstation` capabilities. Add `wsl2_workstation` profile with the same capabilities minus `snap`:

```bash
declare -A PROFILE_MAP=(
  [laptop]="personal_laptop"
  [studio]="mac_workstation"
  [reception]="mac_workstation"
  [office]="mac_mini"
  [home-1]="mac_mini"
  [workstation]="linux_workstation"
  [cruncher]="wsl2_workstation"       # was linux_workstation
)

declare -A PROFILE_CAPS=(
  [personal_laptop]="gui devtools aws k8s docker rust printing"
  [mac_workstation]="gui devtools aws k8s docker rust printing"
  [mac_mini]="gui printing"
  [linux_workstation]="gui devtools aws k8s docker rust snap"   # snap added
  [wsl2_workstation]="gui devtools aws k8s docker rust"         # new — no snap
  [server]="devtools aws"
)
```

### `lib/detect_env.sh`

Remove the `CRUNCHER` legacy hostname alias. `cruncher` now has its own profile (`wsl2_workstation`) so the alias is no longer needed. The `WORKSTATION` alias is also removed since all `linux_workstation` call sites in `setup_env.sh` will be replaced with `HAS_*` vars.

### `setup_env.sh` — Linux hostname var replacements

All `WORKSTATION` and `CRUNCHER` references in the Ubuntu block replaced with capability vars:

| Line | Old gate                    | New gate               | Rationale                                              |
| ---- | --------------------------- | ---------------------- | ------------------------------------------------------ |
| 186  | `WORKSTATION`               | `HAS_SNAP`             | Snap package installs — desktop only                   |
| 439  | `WORKSTATION \|\| CRUNCHER` | `HAS_RUST`             | Rust install                                           |
| 453  | `WORKSTATION \|\| CRUNCHER` | `HAS_DOCKER`           | Docker install                                         |
| 477  | `WORKSTATION \|\| CRUNCHER` | `HAS_DEVTOOLS`         | VirtualBox                                             |
| 488  | `WORKSTATION \|\| CRUNCHER` | `HAS_DEVTOOLS`         | Teleport                                               |
| 499  | `WORKSTATION \|\| CRUNCHER` | `HAS_DEVTOOLS`         | cloudflared                                            |
| 510  | `WORKSTATION \|\| CRUNCHER` | `HAS_K8S`              | kind                                                   |
| 524  | `WORKSTATION \|\| CRUNCHER` | `HAS_DEVTOOLS`         | yq                                                     |
| 538  | `WORKSTATION`               | `HAS_SNAP`             | Albert launcher — snap-based                           |
| 575  | `WORKSTATION \|\| CRUNCHER` | `HAS_K8S`              | telepresence                                           |
| 729  | `WORKSTATION \|\| CRUNCHER` | `HAS_DEVTOOLS`         | claude-code + plugins                                  |
| 737  | `WORKSTATION`               | `HAS_SNAP`             | ollama — desktop only                                  |
| 742  | `WORKSTATION`               | `HAS_SNAP`             | Microsoft Edge — desktop only                          |
| 749  | `WORKSTATION \|\| CRUNCHER` | `HAS_DEVTOOLS`         | dotnet-sdk-8.0                                         |
| 765  | `WORKSTATION`               | `HAS_SNAP`             | snap classic installs (code, helm, slack, etc.)        |
| 776  | `CRUNCHER`                  | `[[ -z ${HAS_SNAP} ]]` | helm via apt — WSL2 only (already inside Ubuntu block) |
| 796  | `WORKSTATION \|\| CRUNCHER` | `HAS_DEVTOOLS`         | libssl1.1                                              |
| 1033 | `WORKSTATION \|\| CRUNCHER` | `HAS_AWS`              | Linux aws-cli (within Linux block)                     |

### `README.md`

Update the Machine Profiles table to reflect the new `wsl2_workstation` profile. Expand the Linux row with a note explaining the desktop vs WSL2 distinction and the `HAS_SNAP` capability:

- `linux_workstation` (hostname: `workstation`) — desktop Ubuntu, full snap support. Capabilities: GUI, devtools, AWS, k8s, Docker, Rust, **snap**
- `wsl2_workstation` (hostname: `cruncher`) — WSL2 Ubuntu, no snap. Snap-gated installs (Albert, Edge, ollama, snap classic packages) are skipped. Helm is installed via apt instead of snap.

Also update the Adding a New Machine section and the Windows/WSL section to reference the correct profile name for WSL2 machines.

## No-Change Items

- Red Hat / Fedora section — no hostname var usage there
- The `BIONIC` Ubuntu version block — correctly ungated (all Ubuntu 18.04 machines get this)
- Ungated Linux installs (azure-cli, gcloud-sdk, Hashicorp tools, Go, pyenv, powershell, kubectl) — these run on all Ubuntu machines regardless of profile and are intentionally ungated

## Testing

- `bash -n setup_env.sh && zsh -n setup_env.sh` must pass
- `make test` must exit 0
- Profiles tests (`tests/setup_env/profiles.bats`) must be updated to reflect the new `wsl2_workstation` profile and `HAS_SNAP` capability
- `CRUNCHER` mock var references in tests must be updated to use `HAS_SNAP`/`wsl2_workstation` as appropriate
