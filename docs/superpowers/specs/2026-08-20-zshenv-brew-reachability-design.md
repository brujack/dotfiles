# `.zshenv` — brew reachable from every zsh actor

**Date:** 2026-08-20
**Status:** Proposed
**Supersedes:** `2026-08-20-linuxbrew-login-path-design.md` (RETIRED unbuilt)

## Problem

`ssh workstation '<cmd>'` cannot resolve any brew-installed binary. Measured:

```
ssh workstation 'command -v uv'                 -> NOT-ON-PATH
ssh workstation 'echo $PYENV_ROOT'              -> []          (so: no .zprofile)
ssh workstation 'zsh -lc "echo \$PYENV_ROOT"'   -> /home/bruce/.pyenv
```

`USER.md` calls that hop "the only cross-machine hop that matters". It runs a **non-login,
non-interactive** zsh, which reads `.zshenv` and nothing else — not `.zprofile`, not
`.zshrc`. The predecessor spec targeted `.zprofile` and was retired for exactly this: it
fixed an actor with no producers while leaving this one broken.

## The trap that retired the predecessor, and why it governs this design too

`3_oh_my_zsh.zsh` loads the oh-my-zsh `brew` plugin, guarded by
`if (( ! $+commands[brew] ))` — **presence, not position**. Today on the workstation `brew`
is unresolvable when `.zshrc` runs, so the plugin executes `brew shellenv`, which prepends
linuxbrew and exports the `HOMEBREW_*` set.

**Any change that makes `brew` resolvable earlier skips that block.** `.zshenv` is read
before `.zshrc` by every actor, so this design triggers the skip on both machines. It is
therefore not enough to add a PATH entry — the design must replace everything the plugin
would have done, or it regresses the interactive shell.

Measured `brew shellenv` output on the workstation:

```
HOMEBREW_PREFIX, HOMEBREW_CELLAR, HOMEBREW_REPOSITORY, INFOPATH   (exports)
fpath[1,0]=".../share/zsh/site-functions"                          (completions)
PATH="<prefix>/bin:<prefix>/sbin:$PATH"                            (PREPEND)
```

Two consequences:

- **Prepend, not append.** `shellenv` prepends, so preserving today's behaviour means
  prepending. Measured position of `linuxbrew/bin` in the workstation's interactive PATH:
  **5**, ahead of `/bin` (10), `/usr/bin` (11), `/usr/local/bin` (13). On the Studio
  `/opt/homebrew/bin` is at **2**, ahead of `/usr/bin` at 6. The two machines already agree.
  The predecessor's append choice was taken on the inverted belief that linuxbrew sat behind
  `/usr/bin`; appending would have demoted 206 of 396 colliding binaries and taken `node`
  from v26.7.0 to v18.19.1.
- **Static exports, not `eval "$(brew shellenv)"`.** Measured at **23 ms** per call. `.zshenv`
  is read by every zsh — every script, every `ssh host '<cmd>'` — so a subprocess there is a
  standing tax on the fleet's most common non-interactive path.

## The asymmetry this also corrects

The Studio has been skipping the plugin since `.zprofile:7` was written: measured,
`HOMEBREW_CELLAR` is **empty** in a macOS interactive shell and set on the workstation. So
macOS has run without the `HOMEBREW_*` set indefinitely with no known cost — useful evidence
that losing them is survivable, but not a reason to lose them. Setting them statically costs
nothing and makes the two machines agree.

## Decision

Track a `.zshenv`, link it like the other dotfiles, and have it do three things:

1. `typeset -U path` — **first**, before anything appends.
2. Resolve a brew prefix by directory test (`/opt/homebrew`, else
   `/home/linuxbrew/.linuxbrew`, overridable) and, if found, prepend `bin`/`sbin` and export
   the `HOMEBREW_*` set plus the `fpath` completion entry.
3. Source `~/.cargo/env` when present — preserving the workstation's existing 21-byte
   `.zshenv`, which is otherwise destroyed by linking over it.

`typeset -U path` in `.zshenv` is the load-bearing piece and does more than tidy: it is read
by **every** actor, so it retires the whole non-idempotency class rather than this one
instance. `6_path.zsh:1` sets it today but is interactive-only, which is why nested login
shells accumulate duplicates — measured, `~/.rbenv/shims` appears twice at depth 3, and
`tmux default-command` is empty so `ssh -> tmux -> pane` reaches that depth in normal use.
Declaring it in `.zshenv` fixes that backlog item as a side effect.

## Scope and blast radius — stated plainly

This adds a file to **all 7 machines**, read by **every** zsh process on them, including
scripts and git hooks. That is a materially larger blast radius than the retired spec's, and
it is the reason this is worth doing: it is also the only file that reaches the broken actor.

The Studio currently has **no** `.zshenv` at all, so linking creates one there. Its
observable macOS effects: `HOMEBREW_*` and brew's `fpath` entry become set where they are
empty today, and `path` becomes deduped. `/opt/homebrew/bin` keeps position 2 because
`.zprofile:7` prepends the same directory and `typeset -U` keeps the first occurrence.

Explicitly **not** in scope: `sh`/`bash` login actors. `.zshenv` is a zsh file; git hooks and
cron invoking `sh` remain unfixed on both machines. That gap keeps its backlog row.

## Verification

The predecessor's suite had six cases, six expecting PASS, only one falsifiable, none
exercising an interactive shell — and the regression that killed it was invisible to all six.
This suite is built against those failures.

| # | case | must | falsifiable because |
| --- | --- | --- | --- |
| 1 | `ssh workstation 'command -v uv'` | resolves | fails today — the discriminator |
| 2 | `ssh workstation 'command -v ls'` | resolves | positive control: an inert harness goes red |
| 3 | workstation interactive `node --version` | `v26.7.0` | pins the regression that killed the predecessor |
| 4 | workstation interactive `command -v curl` | linuxbrew | same, second binary |
| 5 | workstation interactive `$HOMEBREW_CELLAR` | non-empty | proves the plugin skip was compensated |
| 6 | `path` at 3 nested login shells | no duplicates | idempotency, at the depth tmux actually produces |
| 7 | Studio `command -v uv` + position of `/opt/homebrew/bin` | resolves, still 2 | no macOS regression |
| 8 | bats, both guard branches via `_OVERRIDE_BREW_PREFIX` | pass | the guard is untestable on a machine lacking the other platform's prefix |
| 9 | mutation: delete the prepend | case 1 and 3 go red | proves the suite discriminates |

Cases 3–5 are the ones the predecessor lacked. Every negative assertion is paired with a
positive control in the same harness.

## Risks

**Highest of any change in this repo's recent history, and the mitigation is the suite
above.** A syntax error in `.zshenv` breaks *every* zsh on 7 machines — worse than
`.zprofile`, which breaks only login shells. `zsh -n` covers it in `make lint`, and the file
must be added to `ZSH_FILES` at both call sites (`Makefile:51`, `ci.yml:60`) in the same
change, or the gate that would catch this does not see the file.

Second: linking over the workstation's existing untracked `.zshenv` destroys its
`. "$HOME/.cargo/env"` line unless the tracked file carries it. `safe_link` replaces; it does
not merge. Point 3 of the Decision exists for this, and case 2's control would not catch it —
add an explicit assertion that `~/.cargo/bin` is still on PATH after the change.

## Related

- `2026-08-20-linuxbrew-login-path-design.md` — retired predecessor, carries the three-lens
  evidence and the inverted-premise correction
- dotfiles#225 — installed `uv`; its plan carries the reachability record
- backlog: the `sh`/`bash` login gap; the rbenv duplication this design closes incidentally
