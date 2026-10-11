# Non-interactive shells on macOS resolve Homebrew's python3, not Apple's 3.9

- **Status:** Draft
- **Backlog row:** go and python3 differ across macOS and Linux, and python3 outside the venv is ancient (P2, python half)

## Problem

On macOS, every actor that does not start an interactive shell resolves `python3` to Apple's
`/usr/bin/python3`, which is 3.9.6. Interactive shells are out of scope: pyenv governs them.

Measured 2026-10-11 with `PYENV_VERSION` unset:

| actor                                       | claude                             | workstation | Studio    |
| ------------------------------------------- | ---------------------------------- | ----------- | --------- |
| interactive zsh                             | 3.15.0 (linuxbrew, pyenv `system`) | 3.15.0      | 3.9.6     |
| `env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin` | 3.14.4 (apt)                       | 3.14.4      | **3.9.6** |
| `ssh host '<cmd>'`                          | 3.14.4                             | 3.14.4      | **3.9.6** |

Linux non-interactive actors get apt's 3.14.4, which is current enough; this spec is macOS only.

### A live break behind it

`~/.local/bin/ledger` is `state-ledger/scripts/ledger.py`, `#!/usr/bin/env python3`. Since
state-ledger `054ecb7` (2026-08-04) it carries `filename: str | None = None` at line 217, a
runtime-evaluated annotation with no `from __future__ import annotations`. Under 3.9 it dies:

```
$ env -i PATH=<the LaunchAgent PATH> HOME=$HOME ledger --help   # on the Studio
TypeError: unsupported operand type(s) for |: 'type' and 'NoneType'   rc=1
```

The weekly `ledger-drift` LaunchAgent runs `ledger`. Its last heartbeat is 2026-10-05; its next
run hits this. `renovate_held_check.py`, the other agent's detector, runs on 3.9 today (rc 0).

### The actors and where their PATH comes from (Studio, measured 2026-10-11)

- `ssh studio '<cmd>'`: the account's login shell is `/bin/zsh`, run non-interactive and
  non-login, `PATH=/usr/bin:/bin:/usr/sbin:/sbin`. The only startup file it reads is
  `~/.zshenv`, which does not exist. Bash and Python children inherit its `PATH`.
- `zsh -c` from editors and scripts: same file, same default.
- LaunchAgents: no shell. `PATH` comes only from the plist; `launchctl getenv PATH` is empty.
  Both cadence plists set `__HOME__/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:…`,
  and `/opt/homebrew/bin` holds `python3.13` and `python3.14` but no `python3`.
- cron: `/bin/sh` with cron's own `PATH`. The only crontab entry is the coverage push already
  recorded as a dead entry in the backlog.

An existing `~/.zshenv` (measured 2026-10-11): none on the Studio or `claude`; on the
workstation a 21-byte regular file holding rustup's installer line `. "$HOME/.cargo/env"`, the
only thing putting `~/.cargo/bin` on that machine's non-interactive `PATH` (interactive shells
get it from `6_path.zsh`). `safe_link` would move it to `~/.zshenv.bak` and stop it running.
This repo's own rustup install passes `--no-modify-path`, so the line came from an earlier
manual install; a future installer that appends to `~/.zshenv` would, through a symlink, write
into the tracked repo file.

`/opt/homebrew/opt/python@3` points at `python@3.14` 3.14.8 and its `libexec/bin` holds an
unversioned `python3`. That directory follows Homebrew's current default series.

### Prior art

`2026-08-20-linuxbrew-login-path-design.md` (retired) found that `ssh host cmd` reads only
`.zshenv`, that this repo neither tracks nor links one, and that an unguarded `PATH` append
duplicates across nested shells without `typeset -U path`. This design answers both: it adds a
tracked, linked `.zshenv`, and dedups. It also found a `.zprofile` change demoted linuxbrew via
the oh-my-zsh `brew` plugin; this design does not touch interactive shells, where that plugin runs.

## Design

### 1. `.zshenv` (new, repo root)

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

- macOS only by what exists on disk: linuxbrew is `/home/linuxbrew/.linuxbrew`, not a candidate,
  and Linux has no `/opt/homebrew` or `/usr/local/opt/python@3`.
- Reuses the `_OVERRIDE_HOMEBREW_PREFIX_ARM`/`_INTEL` seams `5_general.zsh` already reads.
- Non-login only. A login shell (`zsh -l`, `ssh -t`) then reads `/etc/zprofile`, whose
  `path_helper` rebuilds `PATH` from `/etc/paths` and appends the prior entries, moving this
  directory behind `/usr/bin`: measured on the Studio, `zsh -c` resolves 3.14.8 and `zsh -lc`
  resolves `/usr/bin/python3` 3.9.6. Login non-interactive shells are out of scope (N1 forbids
  a `.zprofile` fix). `ssh studio '<cmd>'` is non-login (measured: `$0=zsh`, `[[ -o login ]]`
  false, parent `sshd-session: bruce@notty`), so the ssh actor is covered.

### 2. Linking and doctor

`setup_dotfile_symlinks` adopts an existing `~/.zshenv` before linking:

"Regular file" means `[[ -f ~/.zshenv && ! -L ~/.zshenv ]]`: `-f` alone follows a symlink, so
a second setup run would move the linked file to `.zshenv.local`, which then sources itself and
prints `job table full or recursion limit exceeded` in every non-interactive zsh. The move runs
through `run_cmd`, so `--dry-run` moves nothing.

- `~/.zshenv` is a regular file and `~/.zshenv.local` does not exist: move it to
  `~/.zshenv.local`, then `safe_link` the repo's `.zshenv`. The workstation keeps its cargo line,
  now sourced from `.zshenv.local`.
- `~/.zshenv` is a regular file and `~/.zshenv.local` already exists: warn naming both files and
  skip the `.zshenv` link, leaving both untouched. Nothing is merged or overwritten.
- Otherwise (absent, or already a symlink): `safe_link` as for `.zprofile`.

`run_doctor`'s symlink list adds `~/.zshenv`.

### 3. Lint scope

`.zshenv` joins `Makefile`'s `ZSH_FILES` pathspec and `ci.yml`'s `lint-macos` pathspec in the
same change (CLAUDE.md requires both call sites move together).

### 4. LaunchAgent template

`LaunchAgents/cadence.plist.template`'s `PATH` becomes:

```
__HOME__/.local/bin:/opt/homebrew/opt/python@3/libexec/bin:/opt/homebrew/bin:/usr/local/opt/python@3/libexec/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
```

A missing directory on `PATH` is skipped. Installed agents are re-rendered by
`./setup_env.sh -t setup_user`, which does not overwrite a real heartbeat.

### 5. Docs

`CLAUDE.md`: the Repository Overview tree and the Symlink Strategy paragraph name `.zshenv`; one
sentence says non-interactive macOS shells get Homebrew's `python3` through it.

### Rollout (operator, after merge)

On the Studio: `git pull`, then `./setup_env.sh -t setup_user`. Then `ssh studio 'python3 --version'`
reports Homebrew's version, and both rendered plists carry the new `PATH`.

### Out of scope

- cron (`/bin/sh`, own `PATH`); its only entry is the dead coverage push in the backlog.
- Login non-interactive zsh (`zsh -lc`), reordered by `path_helper`; see Design §1.
- Editor-spawned git hooks and other processes that never start zsh: they read no `.zshenv`.
- A `brew upgrade` that moves `python@3` to a new series: pip packages installed into the old
  series are no longer visible to non-interactive scripts. Accepted, documented here.
- A bare `env -i` with no `PATH`.
- Linux non-interactive actors (apt 3.14.4).
- state-ledger's `from __future__ import annotations` fix: a different repo. Backlog row there.
- Installing a Homebrew python: `python@3.14` is already present on every mac as a dependency.

## Testing

All zsh cases set `HOME` and `ZDOTDIR` (in `setup()`) to a fixture directory holding only
`.zshenv` (a symlink to the repo's file), so no real startup file and no real `.zshenv.local`
is read, and pass a fixture prefix through
`_OVERRIDE_HOMEBREW_PREFIX_ARM`/`_INTEL` holding `opt/python@3/libexec/bin/python3`, a stub
printing a marker.

- `zsh -c 'python3'` prints the marker (positive control: the prepend happened and resolves).
- `zsh -i -c 'print -r -- $PATH'` does not contain the fixture directory.
- With the fixture's `libexec/bin` absent, `zsh -c 'print -r -- $PATH'` equals the input `PATH`.
- `zsh -c 'zsh -c "print -r -- \$PATH"'` contains the fixture directory exactly once.
- The rendered plist's `PATH` lists `/opt/homebrew/opt/python@3/libexec/bin` before `/usr/bin`;
  `env -i PATH=<rendered PATH with a fixture prefix substituted> /bin/sh -c 'command -v python3'`
  resolves the fixture `python3`.
- `setup_dotfile_symlinks` creates `~/.zshenv`; `run_doctor`'s symlink check reports it.
- Adoption: a pre-existing regular `~/.zshenv` with content `X` ends as `~/.zshenv.local` with
  content `X` (byte-identical) and `~/.zshenv` a symlink; a non-interactive `zsh -c` with that
  `HOME` then runs `X` (a marker line) once. With both files pre-existing, both are byte-identical
  afterwards, `~/.zshenv` is not a symlink, and a warning names both. Running setup twice leaves
  the same state as once.
- Adoption run twice: after the second run `~/.zshenv.local` is not a symlink and holds the
  original content, and a non-interactive `zsh -c true` prints nothing on stderr.
- Adoption under `DRY_RUN=1` leaves an existing `~/.zshenv` in place and creates no `.zshenv.local`.
- `.zshenv.local` is sourced in interactive shells too (a marker set there is visible to
  `zsh -i -c`), matching what a plain `~/.zshenv` did before.
- `make lint`'s `zsh -n` covers `.zshenv` (asserted by the existing lint-scope tests' file list).

## Requirements

- **R1.** `[PR1]` A tracked `.zshenv` at the repo root prepends `<prefix>/opt/python@3/libexec/bin` to `path` only in non-interactive shells, for the first of `${_OVERRIDE_HOMEBREW_PREFIX_ARM:-/opt/homebrew}` and `${_OVERRIDE_HOMEBREW_PREFIX_INTEL:-/usr/local}` whose `opt/python@3/libexec/bin` is a directory.
- **R2.** `[PR1]` `.zshenv` declares `typeset -U path` before prepending, so nested non-interactive shells carry the directory once.
- **R3.** `[PR1]` `.zshenv` leaves `PATH` unchanged in interactive shells and when neither candidate directory exists.
- **R4.** `[PR1]` `setup_dotfile_symlinks` links `${HOME}/.zshenv` to the repo's `.zshenv`, and `run_doctor`'s symlink list includes `~/.zshenv`.
- **R5.** `[PR1]` `.zshenv` is in `Makefile`'s `ZSH_FILES` and in `ci.yml`'s `lint-macos` zsh pathspec.
- **R6.** `[PR1]` `LaunchAgents/cadence.plist.template`'s `PATH` is `__HOME__/.local/bin:/opt/homebrew/opt/python@3/libexec/bin:/opt/homebrew/bin:/usr/local/opt/python@3/libexec/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin`.
- **R7.** `[PR1]` Bats tests cover each Testing bullet, run zsh with `ZDOTDIR` pointed at a fixture, and include the positive control that a fixture `python3` resolves.
- **R8.** `[PR1]` `CLAUDE.md` names `.zshenv` in the Repository Overview tree and the Symlink Strategy section.
- **R9.** `[PR1]` `.zshenv` sources `${HOME}/.zshenv.local` when readable, in interactive and non-interactive shells.
- **R10.** `[PR1]` Before linking, a `~/.zshenv` that is a regular file and not a symlink, with no `~/.zshenv.local`, is moved to `~/.zshenv.local` unchanged through `run_cmd`; when both exist, setup warns naming both and does not link `~/.zshenv`.
- **V1.** After merge and `./setup_env.sh -t setup_user` on the Studio, `ssh studio 'python3 --version'` reports Homebrew's python@3 version (3.14.x today), not 3.9.6.
- **V2.** On the Studio, `env -i PATH=<rendered ledger-drift plist PATH> HOME=$HOME ledger --help` exits 0.
- **V3.** After `./setup_env.sh -t setup_user` on the workstation, `ssh workstation 'python3 --version; command -v cargo'` reports apt 3.14.4 and `~/.cargo/bin/cargo`, as before.
- **N1.** No change to interactive shell startup (`.zshrc`, `.zshrc.d/`, `.zprofile`).
- **N2.** No `PATH` change on Linux: `.zshenv` adds no `/home/linuxbrew` path, and a machine whose old `~/.zshenv` is adopted runs the same lines it ran before.
- **N3.** No new environment-variable seam.
- **N4.** No `sudo`, no write outside `${HOME}`, and no `launchctl config`.
- **N5.** Setup never deletes or overwrites a pre-existing regular-file `~/.zshenv` or any `~/.zshenv.local` (an existing `~/.zshenv` symlink is replaced, as `safe_link` does for every dotfile).

## Multi-Lens Review

Reviewed at commit: `8868401a` (Step 7 self-review commit, before Step 8 dispatch)

### Goal-Fit

Finding: Premises verified on the Studio (ssh cmd reads `~/.zshenv`; `ledger --help` under the plist PATH dies rc 1; prepending the libexec dir fixes it, rc 0). Two cheaper fixes each remove the live break alone: `from __future__ import annotations` in state-ledger's `ledger.py` (reaches every actor, including editor-spawned git hooks, which never start zsh and so never read `.zshenv`), and section 4's plist PATH. That leaves `.zshenv` plus adoption serving only `ssh studio cmd` and `zsh -c`, while rewiring the workstation's live `~/.zshenv` (its only non-interactive `~/.cargo/bin`) where it does nothing for python. Recommends: land the ledger.py fix now, ship section 4, re-propose `.zshenv` only with a named zsh consumer needing python >= 3.10. Tests discriminate (positive control and nested-once fail on a no-op `.zshenv`).
Assumption: some recurring Studio actor runs through zsh, calls `python3`, and needs >= 3.10. Confirm/refute by enumerating ssh call sites and scheduled jobs against the Studio for python3 through zsh.
Disposition: Accepted, reason: operator scoped this to every non-interactive shell on purpose; keep `.zshenv`. The `ledger.py` `from __future__ import annotations` fix lands now as a separate state-ledger PR (operator, 2026-10-11).

### Ergonomics

Finding: The Design §1 sentence about `zsh -lc` is false. `/etc/zprofile` runs `path_helper`, which rebuilds PATH from `/etc/paths` and appends the prior entries, moving the prepended dir behind `/usr/bin`. Measured on the Studio: `zsh -c` resolves 3.14.8, `zsh -lc` resolves `/usr/bin/python3` 3.9.6. No test covers `-lc`, and only macOS can show it. Fix: declare `zsh -l` actors out of scope and delete the sentence, or pin the limitation with a macOS-only test; a `.zprofile` fix breaks N1. Also: `opt/python@3` moves series on `brew upgrade`, silently dropping pip-installed packages for scripts that relied on them.
Assumption: no actor that matters starts zsh as a non-interactive login shell. Measured after the lens: `ssh studio cmd` is `$0=zsh`, non-login, parent `sshd-session: bruce@notty`.
Disposition: Addressed — Design §1 sentence replaced: login non-interactive zsh declared out of scope, with the `path_helper` measurement and the ssh non-login measurement; added to Out of scope. Series-move of `python@3` accepted and documented in Out of scope.

### Risk

Finding: (1) Same `path_helper` defect as Ergonomics. (2) Tests redirect only `ZDOTDIR` but `.zshenv` sources `${HOME}/.zshenv.local`; on the workstation after rollout the real cargo line runs and the "PATH unchanged" case goes red there only. Fix: set `HOME` to the fixture in `setup()`. (3) Adoption's "regular file" test must be `[[ -f ~/.zshenv && ! -L ~/.zshenv ]]`; a naive `-f` on the second setup run moves the symlink to `.zshenv.local`, and every non-interactive zsh then prints `job table full or recursion limit exceeded` (rc 0). Reproduced in scratch. Also: the adoption `mv` must go through `run_cmd` so `--dry-run` moves nothing.
Assumption: the actors that matter are non-login. Same measurement as Ergonomics: `ssh studio cmd` is non-login.
Disposition: Addressed — (1) as Ergonomics; (2) Testing sets `HOME` and `ZDOTDIR` in `setup()`; (3) adoption predicate is `-f && ! -L`, the move goes through `run_cmd`, R10 reworded, twice-run and dry-run cases added.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.
