# `.zshenv` — brew reachable from every zsh actor

**Date:** 2026-08-20
**Status:** BLOCKED — core assumption refuted, see Lens Review
**Supersedes:** `2026-08-20-linuxbrew-login-path-design.md` (RETIRED unbuilt)

## Lens review 2026-08-20 — three lenses, core assumption REFUTED

**The design's mechanism causes a measured regression, and the mechanism is not separable
from the value.** Prepending linuxbrew is how `ssh workstation '<cmd>'` gains `uv`; it is
also how that actor loses the system Python:

```
python3 today  /usr/bin/python3                        3.12.3   import apt_pkg -> OK
python3 after  /home/linuxbrew/.linuxbrew/bin/python3  3.14.7   import apt_pkg -> ModuleNotFoundError
```

208 of 396 linuxbrew binaries shadow something on that actor's PATH. `curl` 8.5.0->8.21.0,
`node` v18->v26, `npm` 9->11, `perl`, `openssl` all flip. **Not** shadowed, verified: `make`,
`git`, `bash`, `bats`, `shellcheck`, `sed`, `awk`, `grep` — so `CLAUDE.md`'s make-version
class and git-hook resolution are untouched, which is the one piece of good news.

### Errors in this spec found by the lenses, all confirmed independently

| spec claimed | measured |
| --- | --- |
| `typeset -U path` is "the load-bearing piece", retires the non-idempotency class | **inert.** `-U` binds the *array*; every producer (`brew shellenv`, `pyenv init`, `rbenv init`, `~/.cargo/env`) scalar-exports. Live proof: the workstation's shell has `-U` active *and* a `pyenv-virtualenv/shims` duplicate simultaneously. Fix is `typeset -TU PATH path` |
| `/opt/homebrew/bin` at position 2 | actor-dependent and unnamed: **2** under `zsh -lc`, **11** under `zsh -lic`. Case 7 goes falsely red against a terminal-equivalent shell |
| `safe_link` destroys the existing `.zshenv` | it **backs up** to `.bak`; recovery is one `mv`. Risk grade was overstated |
| plugin skip means "must replace everything it would have done" | the guard wraps **only** `eval "$(brew shellenv)"`. sbin prepend, `fpath+=`, ~50 aliases and `brews()` run regardless |
| `brew shellenv` emits 4 items | **6** — `export FPATH` and the conditional `MANPATH` line omitted |
| "every negative assertion is paired with a positive control" | **false.** Case 6 passes on an empty result set — the exact defect that killed the predecessor, reproduced in the spec written against it |
| case 6: duplicates appear at 3 nested login shells | present at **depth 1** under the interactive actor; vacuous under the non-interactive one |
| 23 ms for `eval "$(brew shellenv)"` | **confirmed** at 21.6 ms over 100 runs. One lens's 6 ms figure was the outlier |

Also: case 5 cannot fail either way (removing the prepend makes `brew` unresolvable, so the
plugin runs `shellenv` and sets `HOMEBREW_CELLAR` anyway); case 9 is the sole discriminator
for five independent mechanisms; and `run_doctor`'s `_doctor_check_symlinks`
(`lib/helpers.sh:358`) is a flat unconditional array, so a Linux-only `.zshenv` is either
absent from doctor entirely or fails on all 6 macs.

### Cheaper alternative this spec never weighed

Fix `setup_env.sh:30`'s `env which brew` gate to probe the two known prefixes directly. One
file, zero fleet blast radius, **zero shadowing**, and it closes the only consumer this repo
actually documents as broken. It does not make arbitrary `ssh workstation 'uv ...'` work —
but ai-config's step 5 was measured to run under the interactive `update` alias, so no known
consumer needs that.

---

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

## Scope and blast radius — Linux only, by operator constraint

**The `.zshenv` is linked on Linux and nowhere else.** Measured census from `PROFILE_MAP` —
8 hostname entries, which is not the "seven machines" `USER.md` states; the discrepancy is
unresolved and the table is used here because it is what the code reads:
6 macs (`laptop`, `ratna`, `reception`, `studio`, `home-1`, `office`), **1 Linux**
(`workstation`), 1 WSL2 (`cruncher`, unreachable by `ssh`). So this change lands on
**exactly one machine of eight**. The macs are the overwhelming majority and gain
nothing from this change, so they must not carry its risk.

That is not merely a risk trade — it follows from where the defect lives. `USER.md:233`:
"`ssh workstation` is the only cross-machine hop that matters." The workstation is the
**target** of that hop; nothing `ssh`es into a mac to run a command. macOS has the same
structural gap (no `.zshenv`, so `ssh studio '<cmd>'` sees no brew) and **no consumer for
it** — which is exactly the "fixes an actor nothing runs" error that retired the predecessor,
and repeating it on 6 machines instead of 1 would be worse, not better.

So:

- `setup_dotfile_symlinks` links `.zshenv` **only under the `LINUX` branch**. On macOS no
  `~/.zshenv` is created, no existing file is touched, and nothing about a mac's shell
  startup changes. This is a testable claim, not an intention — see verification case 7.
- The file's own body is additionally guarded on the linuxbrew prefix existing, so it is
  inert even if some future change links it more widely. Belt and braces, deliberately:
  the linking guard states the intent, the directory guard survives someone editing it.
- **`cruncher` is included, by operator decision 2026-08-20, dormant today and pre-positioned
  for later.** It is
  WSL2 and cannot be reached by `ssh`, so the defect this fixes — a non-login zsh spawned by
  `ssh host '<cmd>'` — cannot occur there and the file buys it nothing. It is harmless: the
  body guard is a directory test, so with no linuxbrew prefix the file is a no-op beyond
  `typeset -U path`, which is a strict improvement anywhere. A `LINUX` gate is therefore the
  right shape and needs no WSL carve-out — worth noting that one is not available regardless:
  `lib/detect_env.sh:7` sets `LINUX=1` from `uname -s`, true inside WSL2, and `PROFILE_CAPS`
  separates the two profiles only by `snap`/`flatpak`.

  **It may not stay dormant, and that is the point.** The operator notes `cruncher` might
  become native Linux rather than WSL2. If it does, it becomes `ssh`-reachable and acquires a
  linuxbrew prefix — at which moment this file activates on its own, with no edit and no
  second cycle. That is a stronger argument for the plain `LINUX` gate than harmlessness:
  a `PROFILE == linux_workstation` gate would have to be found and widened by whoever does
  that conversion, and would be missed.

  **The residual is epistemic, not operational, and must not be papered over: `cruncher` is
  unreachable, so nothing in the verification suite can run against it.** Whatever this file
  does there is asserted from the design, never measured — the same class of claim this spec's
  own predecessor died for. Two consequences worth carrying: `USER.md` describes `cruncher` as
  the backup-of-last-resort, reached when both development machines are down, so the first
  real execution of this file there may happen under time pressure with degraded judgment; and
  the honest statement of coverage after this ships is **verified on 1 machine, dormant-by-
  design on 1, untouched on 6** — not "works on Linux".

Within the workstation the blast radius is still total — every zsh process there, scripts and
git hooks included. That is the cost of reaching the one actor that is broken, and it is
bounded to the single machine that has the problem.

### If the direction reverses

Confirmed with the operator 2026-08-20: Claude Code sessions flow **macOS -> Linux**, and it
is possible that reverses in future. The Linux-only scope is therefore correct *for the
current direction* rather than permanently — the macs lack a consumer today, not
structurally.

**The design is built so reversing costs one line, not a redesign.** The file body resolves
its prefix by directory test (`/opt/homebrew` first, then `/home/linuxbrew/.linuxbrew`), so
it is already correct on macOS; only the link guard in `setup_dotfile_symlinks` confines it.
Extending is: drop the `LINUX` condition, and re-run the verification suite with case 7
inverted from "macOS untouched" to the macOS equivalents of cases 1-6.

**The trigger to watch for is a consumer, not a preference:** anything that starts running
`ssh <mac> '<cmd>'` for real work — a session hosted on the Linux box reaching back, a cron
job, a CI runner, a peer session delegating a measurement. The moment one exists, the macs
have the same defect *with* a consumer and this scope should widen. Until then, widening it
repeats the predecessor's error at 6x the blast radius.

**Do not read the one-line extension as license to do it pre-emptively.** The risk profile is
not symmetric: 6 machines against 1, and `.zshenv` is read by every zsh process on each of
them. The cheapness of the change is a property of the design; the decision to make it is the
operator's, and it needs a named consumer first.

Explicitly **not** in scope: `sh`/`bash` login actors on either platform, and the macOS
`ssh '<cmd>'` gap. Both keep their backlog rows. Anyone tempted to widen this to macOS must
first name a consumer, because the predecessor died for want of one.

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
| 7 | Studio: `~/.zshenv` still ABSENT, `command -v uv` resolves, `/opt/homebrew/bin` still position 2 | unchanged | proves macOS was not touched at all, not merely 'not broken' |
| 8 | bats: both body-guard branches via `_OVERRIDE_BREW_PREFIX`, **and** that the link step is skipped when `LINUX` is unset | pass | the guard is untestable on a machine lacking the other platform's prefix; the link-skip is the operator constraint and must be pinned by a test, not by intent |
| 9 | mutation: delete the prepend | case 1 and 3 go red | proves the suite discriminates |

Cases 3–5 are the ones the predecessor lacked. Every negative assertion is paired with a
positive control in the same harness.

## Risks

**Highest of any change in this repo's recent history, and the mitigation is the suite
above.** A syntax error in `.zshenv` breaks *every* zsh on the machines it is linked to — worse than
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
