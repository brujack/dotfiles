# linuxbrew on the login-shell PATH — Design

**Date:** 2026-08-20
**Status:** RETIRED — do not implement

## Retired 2026-08-20, before any implementation

Three independent Step 8 lenses converged from different angles; all three findings were
re-verified directly before this retirement. The design is not merely unnecessary — it is
actively harmful, and its central claim is false.

**1. It targets an actor nothing produces.** `.zprofile` is read by login zsh only.
*Interactive* login zsh already resolves `uv` via `6_path.zsh`, so tmux panes and `ssh -t`
gain nothing. The only beneficiary is *non-interactive* login zsh, and no producer exists:
`crontab -l` empty, no graphical session process for the user, and `ssh workstation '<cmd>'`
does not read `.zprofile` at all (`PYENV_ROOT=[]` versus `/home/bruce/.pyenv` under
`zsh -lc`). That actor reads `.zshenv`, which this repo neither tracks nor links —
`setup_dotfile_symlinks` covers `.zshrc`, `.zshrc.d` and `.zprofile` only.

**2. The proposed block is not idempotent, and the dedup it relied on does not cover its
own target actor.** Measured at three nested login shells on the workstation: the spec's
`export PATH="${PATH}:..."` form yields `linuxbrew/bin` x3, while `typeset -U path` plus
`path+=` yields x1. `typeset -U path` lives in `6_path.zsh`, sourced by **interactive**
zsh only — so the login-only actor this spec exists for is precisely the one with no dedup
behind it. `.zprofile` already demonstrates the defect: rbenv shims appear twice at depth 3
today. And nesting is the daily workflow, not a contrived depth — `tmux default-command` is
empty, so every pane is a login shell, and ssh -> tmux -> pane is three levels.

**3. The load-bearing claim "appending changes no existing resolution" is FALSE, and
inverted.** `3_oh_my_zsh.zsh` loads the oh-my-zsh `brew` plugin, whose guard is
`if (( ! $+commands[brew] ))` — conditioned on **presence, not position**. Today `brew` is
unresolvable when `.zshrc` runs, so the plugin executes `brew shellenv`, which *prepends*
linuxbrew. Measured on the workstation: `linuxbrew/bin` is at position **5**, ahead of
`/bin` (10), `/usr/bin` (11) and `/usr/local/bin` (13). Making `brew` resolvable in
`.zprofile` skips that block, demoting linuxbrew below all three. 206 of 396 binaries in
`linuxbrew/bin` collide, and `node` goes **v26.7.0 -> v18.19.1** in the operator's daily
shell, on a fleet whose CI standard is Node 24.

So the design is inert where it is safe and unsafe where it is inert.

**The append-vs-prepend decision was taken against an inverted premise and does not carry
forward.** It was posed as "prepend would move linuxbrew ahead of `/usr/bin`" when linuxbrew
is already ahead of it. Whoever respecs this must re-take that decision against the measured
position-5 fact, where the real question is whether linuxbrew leading `/usr/bin` is intended
or an accident of the plugin that nobody chose.

**None of the six proposed verification cases would have caught any of this.** All six
expected PASS; only the deletion-mutation arm was falsifiable. Two asserted an *absence*
with no positive control, so they pass on an ssh failure or an empty PATH. And not one
exercised an interactive shell — the regression in point 3 was structurally invisible to
the entire suite.

Successor work is backlogged in `docs/superpowers/README.md`: `.zshenv` as the only zsh
startup file every actor reads, the `sh`/`bash` login gap the real consumer needs, and the
pre-existing rbenv duplication measured here.

---

## Problem

On the Linux workstation, every linuxbrew-installed binary is unreachable from a login
shell. Measured with a clean environment (`env -i HOME=$HOME <shell> -lc 'command -v uv'`):

| actor | Studio | workstation |
| --- | --- | --- |
| `zsh -lc` | `/opt/homebrew/bin/uv` | **NOT-FOUND** |
| `bash -lc` | NOT-FOUND | NOT-FOUND |
| `sh -lc` | NOT-FOUND | NOT-FOUND |
| interactive zsh | resolves | resolves |

`uv` is installed there (`/home/linuxbrew/.linuxbrew/bin/uv -> ../Cellar/uv/0.12.5/bin/uv`,
dotfiles#225). The binary exists and the login actor cannot see it.

## Mechanism, measured rather than assumed

`.zprofile:7` is `export PATH="/opt/homebrew/bin:$PATH"` inside the macOS branch. That —
not `path_helper` — is what puts Homebrew on a login PATH. Verified:

- `/opt/homebrew/bin` appears in neither `/etc/paths` nor any `/etc/paths.d/*` file.
- Clean-env `bash -lc` PATH is exactly `path_helper`'s output, with no Homebrew in it.
- Clean-env `zsh -lc` PATH is that same tail with `/opt/homebrew/bin` prepended.

Linux has no counterpart line. `.zprofile:11` uses `/home/linuxbrew/.linuxbrew/bin/rbenv`
as an absolute path for `rbenv init` without ever adding the prefix to `PATH`, so the file
already knows the prefix and declines to export it. The only place the Linux prefix reaches
`PATH` is `6_path.zsh:55-59`, which **interactive zsh alone** sources.

**An earlier version of this analysis blamed `path_helper` and called macOS immune. Both
were wrong**, and the correction is why this spec leads with the clean-env control: a shell
spawned from an agent session inherits the operator's interactive PATH, so an unqualified
`bash -lc` measures the caller's environment wearing a login shell's clothes. See
dotfiles#225's plan for the full three-revision history. **The environment a check runs in
is part of the check.**

## Scope — deliberately the smaller of two fixes

This closes the **zsh login** gap on Linux, bringing it to parity with macOS. It does
**not** cover `sh`/`bash` login actors, which are broken on *both* machines (git hooks,
cron, launchd). That is a larger change touching both platforms and is explicitly out of
scope here; the backlog row carries it.

So after this change the table's first row reads `resolves / resolves`, and rows two and
three are unchanged. Stating that plainly because the tempting summary — "fixes the
linuxbrew PATH" — is wider than what ships.

## Decision

Add a directory-guarded block to `.zprofile` appending the linuxbrew `bin` and `sbin`
directories.

```zsh
_linuxbrew_prefix="${_OVERRIDE_LINUXBREW_PREFIX:-/home/linuxbrew/.linuxbrew}"
if [[ -d ${_linuxbrew_prefix}/bin ]]; then
  export PATH="${PATH}:${_linuxbrew_prefix}/bin"
fi
if [[ -d ${_linuxbrew_prefix}/sbin ]]; then
  export PATH="${PATH}:${_linuxbrew_prefix}/sbin"
fi
unset _linuxbrew_prefix
```

Three choices, each with a reason:

**Append, not prepend.** `6_path.zsh:55-59` already appends this prefix and is the
established Linux idiom; `.zprofile:7`'s prepend is the macOS one. `6_path.zsh:1` sets
`typeset -U path`, which keeps the *first* occurrence, so whichever position `.zprofile`
establishes also becomes the interactive order. Prepending would therefore move linuxbrew
ahead of `/usr/bin` for interactive shells too, and brew's `git`/`curl`/`python` would begin
shadowing the system copies on a machine that has run the other way for its whole life.
Appending fixes reachability and changes no existing resolution. Operator decision,
2026-08-20.

**A directory test, not an identity gate.** `.zprofile:10` gates its Linux block on
`WORKSTATION`/`CRUNCHER`. Those legacy variables are already recorded in the backlog as an
is-this-host-mapped question spelled longhand, and "does this machine have linuxbrew" is
answered directly by the directory. This also means the block is correct on any future Linux
box without touching the identity table.

**An override seam, because the guard is otherwise untestable on the machine that runs the
tests.** `/home/linuxbrew/.linuxbrew/bin` never exists on macOS, so on the Studio the guard
can only ever take its false branch — a test asserting "PATH gains the prefix" would be
structurally unable to fail, and one asserting "PATH does not gain it" would pass for the
wrong reason. `_OVERRIDE_LINUXBREW_PREFIX` lets a test drive both branches on either
platform. Same reasoning as the existing `_OVERRIDE_GNUBIN_ARM`/`_OVERRIDE_HOMEBREW_PREFIX_*`
seams, which exist for exactly this hazard.

## Placement

After the existing `eval "$(pyenv init --path)"` at `:9` and before or after the `:10`
Linux block — position is not load-bearing, because nothing earlier in `.zprofile` resolves
a linuxbrew binary through `PATH` (`:11` uses an absolute path). Placing it adjacent to the
existing Linux block keeps related logic together.

## Verification

The acceptance criterion is the clean-env table, **never `command -v` from a session
shell** — that unqualified check is what produced two wrong measurements before this spec
existed.

```bash
# on the workstation, must resolve after the change
ssh workstation 'env -i HOME=$HOME /bin/zsh -lc "command -v uv"'

# on the Studio, must be unchanged (still resolves, still via /opt/homebrew)
env -i HOME="$HOME" /bin/zsh -lc 'command -v uv'

# both must still report NOT-FOUND -- this change does not claim to fix them
ssh workstation 'env -i HOME=$HOME /bin/bash -lc "command -v uv"'
env -i HOME="$HOME" /bin/bash -lc 'command -v uv'
```

Plus bats coverage driving both guard branches through `_OVERRIDE_LINUXBREW_PREFIX`, and a
mutation check that deleting the block turns the positive test red.

## Risks

**Low, with one real one.** The change is additive and guarded; on a machine with no
linuxbrew directory it is a no-op. The genuine risk is PATH-order surprise, and appending is
what bounds it: nothing that resolves today resolves differently afterward.

Second-order: `.zprofile` is sourced by every login zsh on all 7 machines, so a syntax error
there costs every login shell. `zsh -n` covers it in `make lint`, and `.zprofile` is already
in `ZSH_FILES` at both call sites (`Makefile:51`, `ci.yml:60`).

## Related

- dotfiles#225 — installed `uv`; its plan carries the three-revision reachability record
- `docs/superpowers/README.md` backlog — the `sh`/`bash` login gap, out of scope here
- ai-config's Python dependency design, step 5 (`uv sync` inside `run_update`) — the first
  consumer that would trip on the unfixed defect
