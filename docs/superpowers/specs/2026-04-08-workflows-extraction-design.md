# Design: lib/workflows.sh — Workflow Block Extraction

**Date:** 2026-04-08
**Status:** Approved

## Summary

Move the four main workflow blocks from `setup_env.sh` into a new `lib/workflows.sh` module as named functions. `setup_env.sh` becomes a thin dispatcher: parse args → detect env → call workflow function → exit.

## Motivation

`setup_env.sh` is ~1340 lines. The main body contains four long `if` blocks that implement the actual workflows. Keeping these inline makes the file hard to read, hard to test in isolation, and risky to edit safely. Extracting them into named functions in a dedicated module:
- makes each workflow independently navigable and testable
- makes `setup_env.sh` readable at a glance (sources + dispatch calls)
- unblocks future dry-run and doctor features (which need to wrap or inspect workflow functions)

## Changes

### New file: `lib/workflows.sh`

Four functions extracted from `setup_env.sh` with no behavior change:

| Function | Current location in setup_env.sh |
|---|---|
| `run_setup_user()` | Lines 36–114 (the `SETUP \|\| SETUP_USER` block) |
| `run_setup_or_developer()` | Lines 116–1044 (the `SETUP \|\| DEVELOPER` block) |
| `run_developer_or_ansible()` | Lines 1046–1250 (the `DEVELOPER \|\| ANSIBLE` block) |
| `run_update()` | Lines 1252–1337 (the `UPDATE` block) |

### Modified: `setup_env.sh`

Remove the four `if` blocks. Add `source lib/workflows.sh`. Replace with dispatch:

```bash
source "$(dirname "${BASH_SOURCE[0]}")/lib/workflows.sh"
...
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0
[[ $# -eq 0 ]] && usage
process_args "$@"
detect_env

[[ -n ${SETUP_USER:-} ]] || [[ -n ${SETUP:-} ]] && run_setup_user
[[ -n ${SETUP:-} ]] || [[ -n ${DEVELOPER:-} ]] && run_setup_or_developer
[[ -n ${DEVELOPER:-} ]] || [[ -n ${ANSIBLE:-} ]] && run_developer_or_ansible
[[ -n ${UPDATE:-} ]] && run_update

/usr/bin/env zsh "${HOME}/.zshrc"
exit 0
```

### Modified: `tests/setup_env/unit.bats`

Add tests asserting each workflow function is defined after sourcing `setup_env.sh`.

## Constraints

- Zero behavior change. Code is moved mechanically, not rewritten.
- Function names stay as listed above.
- `lib/workflows.sh` uses the same shebang and style conventions as other `lib/` files.
- All existing tests must continue to pass.
