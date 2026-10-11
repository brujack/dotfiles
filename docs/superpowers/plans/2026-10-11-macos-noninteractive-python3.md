# macOS Non-Interactive python3 Implementation Plan

spec: docs/superpowers/specs/2026-10-11-macos-noninteractive-python3-design.md
scope: PR1

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Non-interactive zsh on macOS, and the cadence LaunchAgents, resolve Homebrew's `python@3` `python3` instead of Apple's 3.9.6.

**Architecture:** A tracked `.zshenv` prepends `<prefix>/opt/python@3/libexec/bin` when the shell is not interactive and sources `~/.zshenv.local`. `setup_dotfile_symlinks` links it, first adopting any existing regular `~/.zshenv` into `~/.zshenv.local`. The plist template gains the same directory.

**Tech Stack:** zsh, bash (`lib/helpers.sh`), bats, GNU make, GitHub Actions.

## Global Constraints

- Prefix candidates, in order: `${_OVERRIDE_HOMEBREW_PREFIX_ARM:-/opt/homebrew}`, `${_OVERRIDE_HOMEBREW_PREFIX_INTEL:-/usr/local}`. No new environment variable (N3).
- No change to `.zshrc`, `.config/.zshrc.d/`, `.zprofile` (N1).
- No `sudo`, no write outside `${HOME}`, no `launchctl config` (N4).
- Setup never deletes or overwrites a regular-file `~/.zshenv` or any `~/.zshenv.local` (N5).
- "Regular file" means `[[ -f ~/.zshenv && ! -L ~/.zshenv ]]`; the adoption move goes through `run_cmd`.
- Every zsh test sets `HOME` and `ZDOTDIR` to a fixture in `setup()`.
- `make test` runs ~160s on `claude`: call it with `timeout: 600000` and `< /dev/null`, and wait for it in the same turn.

## Verification

- `make test` exits 0 with the new tests present.
- Mutation controls named per task go red, then green on revert.
- After merge (operator, V1–V3): `ssh studio 'python3 --version'` reports Homebrew's python@3 version; `env -i PATH=<rendered ledger-drift plist PATH> HOME=$HOME ledger --help` exits 0 on the Studio; `ssh workstation 'python3 --version; command -v cargo'` still reports apt 3.14.4 and `~/.cargo/bin/cargo`.

---

### Task 1: Tracked .zshenv and its lint scope

```yaml-task
id: 1
description: Add .zshenv (non-interactive python@3 prepend, typeset -U, .zshenv.local source), its bats suite, and add it to both zsh lint pathspecs
role: executor
model: sonnet
tdd: required
requirements: [R1, R2, R3, R5, R7, R9]
acceptance:
  - cmd: bats tests/zshrc.d/zshenv.bats
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [.zshenv, tests/zshrc.d/zshenv.bats, Makefile, .github/workflows/ci.yml, tests/scripts/makefile_lint_scope.bats]
depends_on: []
```

**`.zshenv`** (repo root), as in spec §1:

```zsh
# Non-interactive shells (ssh host cmd, zsh -c from editors and scripts) read only this
# file, and on macOS their default PATH resolves python3 to Apple's 3.9.6. Put Homebrew's
# current python3 first. Interactive shells are left to pyenv.
if [[ ! -o interactive ]]; then
  for _py_prefix in "${_OVERRIDE_HOMEBREW_PREFIX_ARM:-/opt/homebrew}" "${_OVERRIDE_HOMEBREW_PREFIX_INTEL:-/usr/local}"; do
    if [[ -d "${_py_prefix}/opt/python@3/libexec/bin" ]]; then
      typeset -U path
      path=("${_py_prefix}/opt/python@3/libexec/bin" $path)
      break
    fi
  done
  unset _py_prefix
fi

# Machine-local additions (installer-written lines such as rustup's) live here, never in
# this tracked file.
[[ -r "${HOME}/.zshenv.local" ]] && source "${HOME}/.zshenv.local"
```

**`tests/zshrc.d/zshenv.bats`** (new). `setup()`: `HOME="${BATS_TEST_TMPDIR}/home"`, `ZDOTDIR="${BATS_TEST_TMPDIR}/zdot"` holding only a symlink `.zshenv` -> repo `.zshenv`; fixture prefix `${BATS_TEST_TMPDIR}/brew` with `opt/python@3/libexec/bin/python3` = `#!/bin/sh` + `echo FIXTURE_PY3`, exported as `_OVERRIDE_HOMEBREW_PREFIX_ARM`; `_OVERRIDE_HOMEBREW_PREFIX_INTEL` set to a nonexistent path; `PATH=/usr/bin:/bin`. Cases, each via `run env HOME=… ZDOTDIR=… PATH=/usr/bin:/bin _OVERRIDE_…=… zsh …`:

1. `zsh -c 'python3'` prints `FIXTURE_PY3` (positive control).
2. `zsh -c 'print -r -- $PATH'` starts with the fixture `libexec/bin`.
3. `zsh +Z -i -c 'print -r -- $PATH'` does not contain the fixture directory.
4. With the fixture `libexec/bin` removed, `zsh -c 'print -r -- $PATH'` equals `/usr/bin:/bin`.
5. ARM absent, INTEL set to the fixture: the INTEL directory is prepended.
6. `zsh -c 'zsh -c "print -r -- \$PATH"'` contains the fixture directory exactly once.
7. `~/.zshenv.local` setting `export ZSHENV_LOCAL_MARK=1`: visible in both `zsh -c` and `zsh +Z -i -c`.

**Lint scope:** add `'.zshenv'` after `'.zprofile'` in `Makefile`'s `ZSH_FILES` pathspec, in `ci.yml`'s `lint-macos` `git ls-files` line, and in both `expected=` pathspecs in `tests/scripts/makefile_lint_scope.bats`.

**Mutation controls (report each red, then revert):** delete `typeset -U path` (case 6 red); replace `! -o interactive` with `-o interactive` (cases 1 and 3 red); delete the `.zshenv.local` line (case 7 red).

**Interfaces:** Produces `.zshenv` at repo root; Task 2 links it.

### Task 2: Link and adopt ~/.zshenv; doctor symlink list

```yaml-task
id: 2
description: setup_dotfile_symlinks adopts a regular ~/.zshenv into ~/.zshenv.local then links .zshenv; run_doctor lists ~/.zshenv
role: executor
model: sonnet
tdd: required
requirements: [R4, R7, R10]
acceptance:
  - cmd: bats tests/setup_env/extracted_functions.bats
    exit_code: 0
  - cmd: bats tests/setup_env/unit.bats
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [lib/helpers.sh, tests/setup_env/extracted_functions.bats, tests/setup_env/unit.bats]
depends_on: [1]
```

In `setup_dotfile_symlinks` (`lib/helpers.sh`), beside the `.zprofile` `safe_link`:

- `[[ -f ${HOME}/.zshenv && ! -L ${HOME}/.zshenv ]]` and `.zshenv.local` absent, tested as `[[ ! -e ${HOME}/.zshenv.local && ! -L ${HOME}/.zshenv.local ]]` (a dangling symlink, or a symlink to a directory, counts as present, so `mv` can never overwrite it or move the file into another directory): under dry run, `log_info` the move and the link and skip both; otherwise `run_cmd mv "${HOME}/.zshenv" "${HOME}/.zshenv.local" || return 1`, then `safe_link`.
- Regular file and `.zshenv.local` present (any kind, including a dangling symlink): `log_warn` naming both paths; do not link; continue.
- Otherwise: `safe_link "${PERSONAL_GITREPOS}/${DOTFILES}/.zshenv" "${HOME}/.zshenv"`.

Add `"~/.zshenv        ${HOME}/.zshenv"` to `_doctor_check_symlinks`' `_checks` array.

**Tests** in `extracted_functions.bats` (add `touch "${FAKE_DOTFILES_SRC}/.zshenv"` to `setup()`):

1. Absent `~/.zshenv`: becomes a symlink to the repo `.zshenv`; no `.zshenv.local`.
2. Run twice from ABSENT: after run 2, `~/.zshenv.local` does not exist and `~/.zshenv` is still the symlink.
3. Regular `~/.zshenv` holding `X`: ends as `.zshenv.local` with content `X` (`cmp`), `~/.zshenv` a symlink. Run twice: `.zshenv.local` is not a symlink and still holds `X`.
4. Both regular `~/.zshenv` and `.zshenv.local` present: both byte-identical afterwards, `~/.zshenv` not a symlink, output names both paths.
5. `DRY_RUN=1` with a regular `~/.zshenv`: unchanged, no `.zshenv.local`, no `.zshenv.bak`.
6. Regular `~/.zshenv` plus a DANGLING symlink `~/.zshenv.local`: both unchanged (`~/.zshenv` content `cmp`-equal, `.zshenv.local` still the same dangling link via `readlink`), output warns naming both.

In `unit.bats`, add `.zshenv` to the `_links` array of the `_doctor_check_symlinks` pass test, and add a case where only `~/.zshenv` is missing that fails naming it.

**Mutation controls:** replace `! -L` predicate with plain `-f` (case 2 red); drop `&& ! -L ${HOME}/.zshenv.local` from the absence test (case 6 red); drop the dry-run skip (case 5 red); remove the `~/.zshenv` row from `_checks` (doctor case red).

**Interfaces:** Consumes `.zshenv` from Task 1.

### Task 3: LaunchAgent PATH carries python@3 libexec

```yaml-task
id: 3
description: Prepend both python@3 libexec dirs to the cadence plist PATH and test that the rendered PATH resolves a python@3 python3 before /usr/bin
role: executor
model: sonnet
tdd: required
requirements: [R6, R7]
acceptance:
  - cmd: bats tests/setup_env/launch_agents.bats
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [LaunchAgents/cadence.plist.template, tests/setup_env/launch_agents.bats]
depends_on: [2]
```

Set the template `PATH` string to exactly:
`__HOME__/.local/bin:/opt/homebrew/opt/python@3/libexec/bin:/opt/homebrew/bin:/usr/local/opt/python@3/libexec/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin`

New test beside "a binary in ~/.local/bin resolves under the plist's PATH": install the agent, read the rendered `PATH` the same way, assert `/opt/homebrew/opt/python@3/libexec/bin` appears before `/usr/bin`; then replace `/opt/homebrew` in it with a fixture dir holding `opt/python@3/libexec/bin/python3` (stub) and `/usr/bin` with a fixture holding a decoy `python3`, and assert `env -i PATH=<that> /bin/sh -c 'command -v python3'` returns the libexec stub.

**Mutation control:** move the libexec entry after `/usr/bin` in the template; the new test goes red.

### Task 4: Document .zshenv in CLAUDE.md

```yaml-task
id: 4
description: Name .zshenv in CLAUDE.md's layout tree and Symlink Strategy (docs-only; no behaviour, so TDD does not apply)
role: executor
model: sonnet
tdd: not-applicable
requirements: [R8]
acceptance:
  - cmd: 'grep -c "zshenv" CLAUDE.md'
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 2
files_touched: [CLAUDE.md]
depends_on: [3]
```

- Layout tree: add `.zshenv` to the `.zshrc, .zprofile, …` root dotfiles line.
- Symlink Strategy, "Repo root" bullet: one sentence — `.zshenv` is linked like the rest; non-interactive zsh on macOS reads it and resolves Homebrew's `python@3` `python3` ahead of Apple's 3.9; an existing regular `~/.zshenv` is adopted as `~/.zshenv.local`, which `.zshenv` sources; login non-interactive zsh (`zsh -lc`) is not covered, because `path_helper` reorders `PATH`.

The orchestrator runs `make test` after this task (the task edits no file the suite reads).

## Non-goal check

Reviewer run 2026-10-11 against N1–N5 (3 CLEAR, 2 UNCLEAR, 0 CONFLICT).

- **N1 CLEAR** — "No task edits `.zshrc`, `.config/.zshrc.d/` or `.zprofile`."
- **N2 UNCLEAR** — "If either directory exists on a Linux machine, that machine's non-interactive `PATH` changes." Resolution: measured 2026-10-11, neither `/opt/homebrew/opt/python@3/libexec/bin` nor `/usr/local/opt/python@3/libexec/bin` exists on `claude` or `workstation` (linuxbrew is `/home/linuxbrew/.linuxbrew`), so the prepend cannot fire on the fleet's Linux machines. No plan change; no Darwin guard added, since the spec selects macOS by what exists on disk.
- **N3 CLEAR** — "The plan reuses `_OVERRIDE_HOMEBREW_PREFIX_ARM` and `_OVERRIDE_HOMEBREW_PREFIX_INTEL`."
- **N4 CLEAR** — "The `mv`, the symlink and the plist all write inside `${HOME}`."
- **N5 UNCLEAR** — "If it is written as `[[ ! -e ]]`, a dangling symlink at `~/.zshenv.local` counts as absent, and `mv` overwrites it." Resolution: plan revised. Before: "and no `${HOME}/.zshenv.local`". After: absence tested as `[[ ! -e … && ! -L … ]]`, any present kind (including a dangling symlink) takes the warn branch, test case 6 and a matching mutation control added.

