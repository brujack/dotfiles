# Machine-Local Overrides Design

**Status:** Draft
**Date:** 2026-04-08

## Goal

Allow per-machine customizations that don't belong in the repo. A `config/local.sh` file is git-ignored and sourced after `detect_env` runs, giving local overrides access to all `HAS_*`, `PROFILE`, and OS vars.

## Architecture

### Source point in `setup_env.sh`

After `detect_env` and before the doctor dispatch and workflow calls:

```bash
detect_env

# Machine-local overrides (git-ignored, sourced if present)
_LOCAL_CFG="$(dirname "${BASH_SOURCE[0]}")/config/local.sh"
[[ -f "${_LOCAL_CFG}" ]] && source "${_LOCAL_CFG}"
unset _LOCAL_CFG

[[ -n ${DOCTOR:-} ]] && { run_doctor; exit $?; }
[[ -n ${SETUP_USER:-} ]] || ...
```

Sourced after `detect_env` so that `HAS_*`, `PROFILE`, OS vars are all available. Sourced before dispatch so overrides can affect workflow behavior.

### `.gitignore` entry

`config/local.sh` added to `.gitignore`.

### `config/local.sh.example`

Committed to the repo as a documented template. Shows the available override patterns:

```bash
#!/usr/bin/env bash
# config/local.sh — machine-local overrides (git-ignored, not committed)
#
# This file is sourced after detect_env(), so HAS_* vars and PROFILE are set.
# Copy this file to config/local.sh and customise for this machine.
#
# Examples:

# Override a capability var (e.g. disable Docker installs on this machine)
# unset HAS_DOCKER

# Add a machine-specific PATH entry
# export PATH="${HOME}/.local/bin:${PATH}"

# Source a work-specific secrets file
# [[ -f "${HOME}/.work_env" ]] && source "${HOME}/.work_env"

# Add a custom symlink
# safe_link "${HOME}/work/dotfiles/.gitconfig_work" "${HOME}/.gitconfig_work"
```

### What local overrides can do

- Unset or set any `HAS_*` var to suppress or add capability-gated installs
- Override `PROFILE`
- Add custom `safe_link` calls
- Source external secrets files (e.g. `~/.work_env`)
- Extend `PATH` or set env vars needed by the rest of setup

### What local overrides cannot do

- Override `readonly` vars already set (e.g. `MACOS`, `LINUX` — these are set before `detect_env` returns)
- Affect the sourcing guard (`[[ "${BASH_SOURCE[0]}" != "${0}" ]]`) — that runs before the override

## Testing

- `setup_env.sh` sources `config/local.sh` when it exists (mock a temp local.sh, verify it's sourced via a sentinel var it sets)
- `setup_env.sh` does not error when `config/local.sh` is absent
- `.gitignore` contains `config/local.sh` entry

## Files Modified

| Action | File |
|---|---|
| Modify | `setup_env.sh` — add local override source block |
| Create | `config/local.sh.example` — documented template |
| Modify | `.gitignore` — add `config/local.sh` |
| Modify | `tests/setup_env/unit.bats` — add sourcing tests |
| Modify | `CLAUDE.md` — document local overrides pattern |
| Modify | `README.md` — mention `config/local.sh.example` |
