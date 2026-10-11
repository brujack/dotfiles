# Bump Python to 3.14.8 and Ruby to 4.0.7

- **Status:** Approved
- **Approved:** 2026-10-10

## Problem

Python 3.14.8 and Ruby 4.0.7 carry security fixes; the pins are 3.14.6 and 4.0.5.

Both are published and buildable (measured 2026-10-10): pyenv's `python-build` has a
`3.14.8` definition, ruby-build has `4.0.7`, and both source tarballs return 200.

## Design

- `lib/constants.sh`: `PYTHON_VER="3.14.8"`, `RUBY_VER="4.0.7"`.
- `.config/.zshrc.d/5_general.zsh:7`: the hand-maintained duplicate `RUBY_VER` read by
  `chruby` moves with it, or macOS shells keep selecting 4.0.5.
- `pyproject.toml` (`requires-python = "==3.14.*"`) and `uv.lock` stay: same series.
- Test fixtures that set their own `RUBY_VER="4.0.5"` / `PYTHON_VER="3.14.6"` stay; they
  do not read the constants.

After merge, on `claude`, the Studio and the workstation (operator runs; the ansible
session on the workstation is told first):

| | macOS | Linux |
|---|---|---|
| python venv | `pyenv install 3.14.8 && ./setup_env.sh -t ansible` | `./setup_env.sh -t ansible` |
| ruby | `./setup_env.sh -t developer` | `./setup_env.sh -t developer` |

`setup_ansible` deletes the old venv before building the new one, so a failed build
leaves no venv until re-run (backlog row). The ruby path installs alongside 4.0.5.

## Requirements

- **R1.** `[PR1]` `lib/constants.sh` sets `PYTHON_VER="3.14.8"` and `RUBY_VER="4.0.7"`.
- **R2.** `[PR1]` `.config/.zshrc.d/5_general.zsh` sets `RUBY_VER="4.0.7"`.
- **V1.** On `claude`, the Studio and the workstation, the ansible venv's `python --version` reports 3.14.8 and `ruby --version` reports 4.0.7.
- **N1.** No `pyproject.toml` or `uv.lock` change.
- **N2.** No installer logic change.
