# linuxbrew on the login-shell PATH — Design

**Date:** 2026-08-20
**Status:** Proposed

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
