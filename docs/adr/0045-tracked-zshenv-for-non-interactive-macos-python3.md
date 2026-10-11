# ADR-0045: A tracked .zshenv puts Homebrew's python3 first for non-interactive macOS zsh

**Date:** 2026-10-11
**Status:** Accepted

## Context

On macOS, a process that sources no shell profile resolves `python3` to Apple's
`/usr/bin/python3`, which is 3.9.6. Measured on the Studio on 2026-10-11, that covers
`ssh studio '<cmd>'` (a non-interactive, non-login `/bin/zsh` with
`PATH=/usr/bin:/bin:/usr/sbin:/sbin`) and both cadence LaunchAgents. One consumer broke on
it: state-ledger's `ledger.py` failed under 3.9 until state-ledger#22, and the
`ledger-drift` agent runs it. Interactive shells are governed by pyenv and were out of scope.

The only startup file a non-interactive, non-login zsh reads is `~/.zshenv`. This repo did
not track one. The retired `2026-08-20-linuxbrew-login-path` spec found two reasons not to
add a `PATH` change at login: nested shells duplicated the entry, and a `.zprofile` change
demoted linuxbrew through the oh-my-zsh `brew` plugin.

Approaches weighed (spec `2026-10-11-macos-noninteractive-python3-design.md`):

- A tracked `.zshenv` plus the plist `PATH`. Chosen.
- `launchctl config user path`, which needs sudo and a reboot and still misses ssh.
- `pyenv global` plus shims on the non-interactive `PATH`, which pins the venv's version
  rather than Homebrew's latest, contrary to what the operator asked for.

## Decision

- `.zshenv` is tracked at the repo root and linked by `setup_dotfile_symlinks`.
- In a non-interactive zsh it prepends `<prefix>/opt/python@3/libexec/bin` for the first of
  `/opt/homebrew` and `/usr/local` where that directory exists. It does this only when the
  inherited `PATH` resolves `python3` to `/usr/bin/python3` or to nothing, so a child zsh of a
  pyenv or venv shell keeps that interpreter. `typeset -U path` keeps nested shells from
  duplicating the entry. Linux is unaffected because neither directory exists there.
- `.zshenv` sources `~/.zshenv.local` in every zsh. An existing regular `~/.zshenv` is
  adopted into `~/.zshenv.local` before linking. If both already exist, setup warns and
  leaves both untouched. If the move fails, setup warns and continues.
- The cadence plist template's `PATH` lists both `python@3` libexec directories ahead of
  `/usr/bin`.

## Consequences

- `ssh studio '<cmd>'`, editor-spawned `zsh -c`, and both LaunchAgents get Homebrew's
  current `python3` after `./setup_env.sh -t setup_user` re-links the dotfiles and
  re-renders the agents.
- Login non-interactive zsh (`zsh -lc`, `ssh -t`) is not covered: macOS `/etc/zprofile`
  runs `path_helper`, which moves the prepended directory behind `/usr/bin`. Fixing it would
  need a `.zprofile` change, which the spec ruled out.
- Processes that never start zsh (cron's `/bin/sh`, editor-spawned git hooks) still get
  3.9. state-ledger#22 keeps `ledger` runnable under 3.9 regardless.
- When `brew upgrade` moves `python@3` to a new series, pip packages installed for the old
  series stop being visible to non-interactive scripts.
- An installer that appends to `~/.zshenv` writes through the symlink into the tracked file.
  That shows as a dirty tree; machine-local lines belong in `~/.zshenv.local`.
- `-t doctor` reports `~/.zshenv` missing on any machine until `setup_user` is re-run.

## Related

- Spec: `docs/superpowers/specs/2026-10-11-macos-noninteractive-python3-design.md`
- Retired: `docs/superpowers/specs/2026-08-20-linuxbrew-login-path-design.md`
- state-ledger#22; postmortem `ai-config/.claude/postmortems/state-ledger-2026-10-11-ledger-py39-annotation.md`
