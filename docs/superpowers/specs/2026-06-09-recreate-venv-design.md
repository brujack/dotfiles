# Spec: recreate-venv — Python Virtualenv Force-Recreate

## Overview

Add `-t recreate-venv` to `setup_env.sh` to explicitly delete and recreate a named
pyenv virtualenv. The "ansible" venv is the default and primary target; other venv
names create a bare venv without the ansible pip package set.

Existing `-t ansible` keeps its idempotent "create if missing / recreate if symlink
wrong" semantics unchanged.

## Entry Point

```
./setup_env.sh -t recreate-venv [--venv-name <name>]
```

- `--venv-name <name>`: venv to recreate (default: `ansible`)
- Requires Homebrew (same prereq as all other types except `doctor`/`check-versions`)

## Components

### `lib/helpers.sh` — argument parsing + usage

- `usage()`: add `recreate-venv` entry
- `process_args()`: add `--venv-name` long-option → sets `VENV_NAME` readonly var
- `process_args()`: add `recreate-venv` case → sets `RECREATE_VENV=1`

### `lib/developer.sh` — core logic

New function `recreate_python_venv()`:

1. Init pyenv (same env setup block reused from `setup_ansible`)
2. `pyenv virtualenv-delete -f "${_venv_name}"`
3. `pyenv virtualenv "${PYTHON_VER}" "${_venv_name}"`
4. `pyenv activate "${_venv_name}"`
5. If `_venv_name == "ansible"`: run full pip install line from `setup_ansible`

### `lib/workflows.sh` — dispatch

New function `run_recreate_venv()`:

- Reads `VENV_NAME` (defaults to `ansible` if unset)
- Calls `recreate_python_venv "${_venv_name}"`

### `setup_env.sh` — dispatch

Add line:

```bash
[[ -n ${RECREATE_VENV:-} ]] && _run_or_exit run_recreate_venv
```

## Error Handling

- `pyenv virtualenv-delete -f` is a no-op when venv doesn't exist (safe)
- `recreate_python_venv` returns 1 on any step failure; `_run_or_exit` exits non-zero
- pyenv not found: function returns early with `log_error`

## Testing

New tests in `tests/setup_env/unit.bats` and/or `install_functions.bats`:

- `process_args` sets `RECREATE_VENV=1` for `-t recreate-venv`
- `process_args` sets `VENV_NAME` from `--venv-name foo`
- `process_args` leaves `VENV_NAME` unset when flag absent (workflow defaults to `ansible`)
- `run_recreate_venv` calls `recreate_python_venv` with `ansible` when `VENV_NAME` unset
- `run_recreate_venv` calls `recreate_python_venv` with custom name when `VENV_NAME` set
- `recreate_python_venv ansible`: calls delete, create, activate, pip install (mock pyenv)
- `recreate_python_venv myenv`: calls delete, create, activate — no pip install
- `recreate_python_venv` returns 1 when pyenv not found
- `usage()` output contains `recreate-venv`
