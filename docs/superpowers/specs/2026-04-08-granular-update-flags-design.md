# Granular Update Flags Design

**Status:** Draft
**Date:** 2026-04-08

## Goal

Allow `./setup_env.sh -t update` to run only specific subsystems via additive long-option flags. If no flags are set, all subsystems run (fully backward compatible).

## Flags

| Flag            | Subsystem                                            |
| --------------- | ---------------------------------------------------- |
| `--brew-only`   | Homebrew update + upgrade + cleanup (macOS only)     |
| `--pip-only`    | pip / pyenv virtualenv upgrades                      |
| `--gems-only`   | `gem update`                                         |
| `--mas-only`    | Mac App Store updates via `mas upgrade` (macOS only) |
| `--claude-only` | Claude Code plugin updates                           |

Flags are additive: `--brew-only --pip-only` runs only brew and pip. Any combination is valid.

## Architecture

### `process_args()` in `lib/helpers.sh`

The existing long-option pre-processing loop (used for `--dry-run`) is extended:

```bash
for _arg in "$@"; do
  [[ "${_arg}" == "--dry-run"    ]] && readonly DRY_RUN=1
  [[ "${_arg}" == "--brew-only"  ]] && readonly UPDATE_BREW=1
  [[ "${_arg}" == "--pip-only"   ]] && readonly UPDATE_PIP=1
  [[ "${_arg}" == "--gems-only"  ]] && readonly UPDATE_GEMS=1
  [[ "${_arg}" == "--mas-only"   ]] && readonly UPDATE_MAS=1
  [[ "${_arg}" == "--claude-only" ]] && readonly UPDATE_CLAUDE=1
done
```

All `UPDATE_*` vars are unset by default. The `--*-only` flags are only meaningful with `-t update` but are parsed regardless — no error if combined with other types (they'll simply be ignored).

### `run_update()` in `lib/workflows.sh`

A helper `_any_update_flag()` returns true if any `UPDATE_*` var is set:

```bash
_any_update_flag() {
  [[ -n ${UPDATE_BREW:-}   ]] || [[ -n ${UPDATE_PIP:-}    ]] || \
  [[ -n ${UPDATE_GEMS:-}   ]] || [[ -n ${UPDATE_MAS:-}    ]] || \
  [[ -n ${UPDATE_CLAUDE:-} ]]
}
```

Each subsystem block is guarded:

```bash
run_update() {
  # If no flags set, run everything (backward compat)
  local _run_all=0
  _any_update_flag || _run_all=1

  if [[ ${_run_all} -eq 1 ]] || [[ -n ${UPDATE_BREW:-} ]]; then
    # brew update block
  fi

  if [[ ${_run_all} -eq 1 ]] || [[ -n ${UPDATE_PIP:-} ]]; then
    # pip block
  fi

  if [[ ${_run_all} -eq 1 ]] || [[ -n ${UPDATE_GEMS:-} ]]; then
    # gem update block
  fi

  if [[ ${_run_all} -eq 1 ]] || [[ -n ${UPDATE_MAS:-} ]]; then
    # mas upgrade block (guarded by [[ -n ${MACOS} ]])
  fi

  if [[ ${_run_all} -eq 1 ]] || [[ -n ${UPDATE_CLAUDE:-} ]]; then
    # claude plugin update block
  fi
}
```

### `usage()` in `lib/helpers.sh`

Updated to document the new flags under the `update` type description and in the Options section.

## Backward Compatibility

`./setup_env.sh -t update` with no flags: `_any_update_flag` returns false → `_run_all=1` → all subsystems run exactly as before.

## Testing

New tests in `tests/setup_env/unit.bats`:

- `process_args` sets `UPDATE_BREW` for `--brew-only`
- `process_args` sets `UPDATE_PIP` for `--pip-only`
- `process_args` sets multiple flags when multiple `--*-only` flags given
- `_any_update_flag` returns true when any flag set, false when none
- `run_update` with `--brew-only` only calls brew subsystem (mock assertion)
- `run_update` with no flags calls all subsystems

## Files Modified

| Action | File                                                                             |
| ------ | -------------------------------------------------------------------------------- |
| Modify | `lib/helpers.sh` — extend long-option loop in `process_args()`, update `usage()` |
| Modify | `lib/workflows.sh` — refactor `run_update()` with `_any_update_flag` guard       |
| Modify | `tests/setup_env/unit.bats` — add flag parsing and update dispatch tests         |
| Modify | `CLAUDE.md` — document new flags in Entry Points section                         |
| Modify | `README.md` — document new flags in Usage section                                |
