# `.zshenv` — brew reachable from the ssh actor

**Date:** 2026-08-20
**Status:** CLOSED (v2) — same defect class as v1, one file over, AND no consumer. Superseded by ADR-0069 (ai-config). Do not implement.
**Supersedes:** `2026-08-20-linuxbrew-login-path-design.md` (RETIRED unbuilt)

## v2 blocked 2026-08-20 — "zero flips" is false, and the mechanism is v1's

**`.zprofile:5` is `command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"` — a
presence-guarded conditional, exactly like the oh-my-zsh plugin guard that killed v1.**
Appending linuxbrew makes `pyenv` resolvable at `.zshenv` time, so that guard skips,
`~/.pyenv/bin` is never added, and the version manager flips:

```
zsh -lc  today  ~/.pyenv/bin/pyenv  2.7.2      ~/.pyenv/bin on PATH: 1
zsh -lc  after  linuxbrew/bin/pyenv 2.8.4      ~/.pyenv/bin on PATH: 0
```

v2's "zero flips" was measured for `zsh -c` and stated unqualified. `zsh -lc` is
non-interactive, so the guard fires there too — and it is the actor this spec's own Problem
section prints as today's workaround.

**The class, stated once so it is not walked into a fourth time: any design that makes
`brew` resolvable earlier changes every presence-guarded conditional downstream of it.** Two
found so far (`3_oh_my_zsh.zsh`'s plugin, `.zprofile:5`'s pyenv); nothing has enumerated the
rest. v1 died on the first, v2 on the second, and each fix was written by someone who
believed they had addressed the class.

**Worse, and independently fatal: the exported append propagates into descended interactive
shells.** "Untouched by construction" holds only for a *directly launched* interactive shell.
The block exports `PATH`, so a child interactive zsh inherits `brew`, the plugin guard goes
false, and the prepend is skipped. Measured, identical actor chain, only the parent's
`.zshenv` varying:

```
zsh -c -> exec zsh -lic   baseline: node,curl = linuxbrew, linuxbrew/bin at 5
                          after   : node,curl = /usr/bin,  linuxbrew/bin at 15
```

**All 208 binaries flip — the same set as v1, in the opposite direction.** And the actor is
not exotic: `USER.md` calls the 7950X the tmux session host, `tmux default-command` is empty
so every pane is a login shell, and a session is live now. `ssh workstation -t 'tmux attach'`
degrades every pane. `HOMEBREW_CELLAR`/`PREFIX`/`FPATH` are lost outright there — and v2
deleted v1's static-export section, which is exactly what would have covered it, on the
strength of the claim this refutes.

The decision that shape forces, if anyone revisits it: **export, or set for the current shell
only?** An unexported append would serve `ssh '<cmd>'` without reaching a descendant. Nobody
has designed that, and it is not obviously sound either.

Further defects, each verified:

- **Case 7 is vacuous — demonstrated, not argued.** Its control is `$#path` non-zero, true in
  every shell. Against a no-op `.zshenv` it still passes: block never executed, "no
  duplicates" holds trivially. This is the third consecutive spec in which the vacuity
  defect recurs, in the one written to indict its predecessor for it. Fix is to assert
  `linuxbrew/bin` present **exactly once**, not "no duplicates".
- **The escape hatch does not work against the class the spec calls fatal.** sshd runs
  `$SHELL -c '<string>'`, so the outer zsh reads `.zshenv` before parsing the command:
  `zsh -f -c` never starts. A fatal `.zshenv` locks out `ssh <cmd>`, `ssh` login, `scp` and
  `sftp` at once; recovery is physical console or a second account. The spec states the
  opposite.
- **"No top-level `exit`" is incomplete: a hang is equally fatal and nothing gates it.**
  `zsh -n` catches syntax, not liveness. The body's own `[[ -d ... ]]` probe runs
  unconditionally above the interactive guard and would hang interactive login on a stale
  autofs mount.
- **`export PATH="${PATH}:..."` puts cwd on PATH when `PATH` is empty** — leading empty
  element, which zsh resolves as `.`. Measured. `${PATH:+${PATH}:}` fixes it.
- **Two "measured, therefore true" claims are inverted.** The body does *not* resolve
  `/opt/homebrew` first — the linuxbrew line overwrites it, last writer wins. And mac
  reversal is not one line: `ratna` is Intel at `/usr/local`, for which the body has no arm.
  Case 8's position figures are also transposed (`-lc` 21, `-lic` 9 on the Studio today).

Two further v2 findings, both real:

- **"Interactive untouched by construction" is untouched by coincidence.** `. ~/.cargo/env`
  sits outside the guard. It is a no-op on the workstation only because `~/.zshenv` already
  *is* that line. On a machine with no `.zshenv` — the Studio measured as a live proxy, and
  cruncher by assertion — it prepends `~/.cargo/bin`, which the interactive `-U` then pins
  ahead of `6_path.zsh:73`'s deliberate append position. Harmless today (zero name
  collisions), which is compensation, which is the framing v2 claimed to have retired.
- **`.zshenv` would be the only file linked to a real machine while absent from BOTH
  `make lint`'s `ZSH_FILES` and `run_doctor`'s symlink array.** Each gap is flagged
  separately in this spec and never together.

Measured non-issues, recorded so they are not re-litigated: hot-path cost is +0.04 ms per
shell; `_brew_prefix` does not leak; neither arm writes to stdout; `typeset -TU` is correctly
diagnosed and produces a byte-identical `$path` when isolated.

## Recommendation — the narrow fix, and not merely because it is cheaper

> **Stale when written, corrected 2026-08-20: the narrow fix recommended below was itself CLOSED four
> minutes later** — `specs/2026-08-20-setup-env-brew-probe-design.md`, no consumer. Its *structural*
> argument stands (it never puts brew on `PATH`, so no presence guard can observe it) and is the right
> reason to prefer it **if** anyone ever builds either. Neither should be built today. The governing
> decision is ADR-0069.

> **A third finding, from the final lens and not recorded elsewhere: this suite's central safety case is
> unrunnable from the fleet.** Case 6 specifies `workstation zsh -lic`. From the Studio the only route is
> `ssh workstation 'zsh -lic "..."'`, whose parent is the ssh actor that just exported the appended
> `PATH` — so case 6 goes red *because the design works*, and passes only at a physically-local terminal.
> Case 10's discriminating arm is defined in terms of case 6 and inherits that. A suite whose safety case
> cannot be executed over the fleet's only hop is not one you can gate on.

> **And the hop's documented purpose does not need brew at all.** `shell.md:306` and `USER.md:233` send
> you over it to reproduce CI version skew; measured, every tool that needs is a system binary at the
> CI-matching version — bash 5.2.21, bats 1.10.0, make 4.3, shellcheck 0.9.0, git 2.43.0, python3 3.12.3.
> Not one is a brew binary.


Fix `setup_env.sh:30`'s `env which brew` gate to probe the two prefixes directly. It is
immune to this entire class **by construction**: it never puts brew on `PATH`, so no
downstream presence-guard can observe it. That is a structural argument, not an economy one.

`ai-config` confirms no consumer needs the broader win: their step 3 is the only one crossing
the hop and it uses an absolute `uv` path *by design*, because `--python 3.14` is a family
selector (Homebrew 3.14.7 vs the venv's 3.14.6) and PATH resolution would convert a loud
failure into a silent one. Their caveat is honest and stands: they know only their own
consumers.

---

## Problem

`ssh workstation '<cmd>'` cannot resolve any brew-installed binary:

```
ssh workstation 'command -v uv'                 -> NOT-ON-PATH
ssh workstation 'echo $PYENV_ROOT'              -> []            (so: no .zprofile)
ssh workstation 'zsh -lc "echo \$PYENV_ROOT"'   -> /home/bruce/.pyenv
```

`USER.md:233` calls that hop "the only cross-machine hop that matters". It runs a
**non-login, non-interactive** zsh, which reads `.zshenv` and nothing else. This repo already
documents the consequence twice, each with a manual `PATH=` workaround: `CLAUDE.md`'s
"`setup_env.sh` cannot run non-interactively on the Linux workstation", and
`plans/2026-08-20-brewfile-uv.md:174`.

## Design

Linked on Linux only. The entire body:

```zsh
# brew binaries for non-interactive zsh (the `ssh host '<cmd>'` actor).
# Interactive shells are deliberately excluded -- see Why below.
_brew_prefix="${_OVERRIDE_BREW_PREFIX:-}"
if [[ -z ${_brew_prefix} ]]; then
  [[ -d /opt/homebrew ]] && _brew_prefix=/opt/homebrew
  [[ -d /home/linuxbrew/.linuxbrew ]] && _brew_prefix=/home/linuxbrew/.linuxbrew
fi
if [[ ! -o interactive ]] && [[ -n ${_brew_prefix} ]] && [[ -d ${_brew_prefix}/bin ]]; then
  typeset -TU PATH path
  export PATH="${PATH}:${_brew_prefix}/bin:${_brew_prefix}/sbin"
fi
unset _brew_prefix
[[ -f ${HOME}/.cargo/env ]] && . "${HOME}/.cargo/env"
```

## Why this shape — each clause answers a measured finding

**`[[ ! -o interactive ]]` — the clause that makes the whole design safe.** v1 prepended for
every actor and was blocked because prepending swaps the interpreter: `python3` 3.12.3 ->
3.14.7 and `import apt_pkg` fails. Measured, the guarded form against the real ssh actor:

```
uv      -> /home/linuxbrew/.linuxbrew/bin/uv
python3 -> /usr/bin/python3            apt_pkg OK
curl,node -> system copies
```

212 of 396 linuxbrew binaries collide with the system PATH; under **append** all 212 keep
resolving to the system copy. Zero flips. `uv`, `gh` and the rest resolve because nothing
else provides them.

**Interactive shells are untouched by construction, not by compensation.** The block does not
execute there, so `brew` stays unresolvable when `.zshrc` runs, so the oh-my-zsh `brew`
plugin still runs `eval "$(brew shellenv)"` exactly as today — linuxbrew at position 5,
`node` v26.7.0, `curl` linuxbrew, `HOMEBREW_CELLAR` set. **v1's entire static-export section
is therefore deleted**: no `HOMEBREW_*` replication, no `fpath` entry, no shellenv drift
test, no copy of a generated artifact. That removes the largest risk v1 carried.

Verified the actors are distinguishable: `zsh -c` -> not interactive, `zsh -ic` ->
interactive, `zsh -lc` -> not interactive.

**`typeset -TU PATH path`, not `typeset -U path`.** v1 called the latter load-bearing; it is
inert. `-U` binds the *array*, and every producer scalar-exports (`brew shellenv`,
`pyenv init`, `rbenv init`, `~/.cargo/env`). Measured:

```
typeset -TU PATH path, 3 scalar adds of /x -> /x:/usr/bin:/bin
typeset -U   path,     2 scalar adds of /x -> /x:/x:/usr/bin:/bin
```

Scoped inside the guard, so it applies to the actor this file changes and does not alter
declaration semantics for interactive shells.

**`. ~/.cargo/env` last.** The workstation's existing untracked 21-byte `.zshenv` is exactly
this line, and `safe_link` **backs up to `.bak` rather than merging** (`lib/helpers.sh:53`),
so without it the ssh actor loses `cargo` until someone runs one `mv`. Sourced last so
`~/.cargo/bin` keeps its current position ahead of the appended prefix.

## Scope

Linked under the `LINUX` branch only. Census from `PROFILE_MAP` — 13 hostname entries, 8
machines: 6 macs, 1 Linux, 1 WSL2.

- **6 macs: no `~/.zshenv` created, nothing touched.** They have the same structural gap and
  **no consumer** — the workstation is the *target* of the only hop that matters, never the
  source. Widening without naming a consumer repeats the predecessor's fatal error at 6x the
  blast radius. Reversal is one line (the body already resolves `/opt/homebrew` first) plus
  re-running the suite with case 8 inverted; the trigger is a real process running
  `ssh <mac> '<cmd>'`, not a preference.
- **`cruncher`: linked, dormant** — WSL2, unreachable by `ssh`, so no consumer and no
  verification case can run against it. Its behaviour is asserted, not measured. Pre-positioned
  for the possible conversion to native Linux, at which point it activates with no edit.
- **Not covered: `sh`/`bash` actors on either machine.** `.zshenv` is a zsh file. Git hooks
  here are `#!/usr/bin/env bash`. Case 5 records that row **still failing**, deliberately —
  an omitted row invites a later reader to assume it passes.

## Verification

v1's suite had 9 cases, 8 expecting PASS, one passing on an empty result set, and none
covering the actor that changed. This suite is built against those failures: every negative
assertion is paired with a positive control **in the same command**, and every case names its
actor.

| # | actor | assert | control |
| --- | --- | --- | --- |
| 1 | `ssh workstation 'command -v uv'` | resolves under linuxbrew | fails today — the discriminator |
| 2 | `ssh workstation 'command -v python3; python3 -c "import apt_pkg"'` | `/usr/bin/python3`, import OK | **the v1 regression, pinned** |
| 3 | `ssh workstation 'command -v cargo'` | under `~/.cargo/bin` | proves `.zshenv` is read *and* the cargo line survived linking |
| 4 | `ssh workstation 'command -v curl node'` | both system copies | no-flip, second and third binaries |
| 5 | `ssh workstation 'bash -lc "command -v uv"'` + `command -v ls` | uv NOT-FOUND, ls found | out-of-scope row recorded as still-failing, with a control so an inert harness goes red |
| 6 | workstation `zsh -lic` | `node` under linuxbrew, `curl` under linuxbrew, `linuxbrew/bin` ahead of `/usr/bin` | interactive untouched — assert relative order, not a constant |
| 7 | workstation `zsh -c`, nested x3 | `$#path` non-zero **and** no duplicates | idempotency with a non-empty control |
| 8 | Studio | `~/.zshenv` absent, `command -v uv` resolves, `/opt/homebrew/bin` ahead of `/usr/bin` under **`zsh -lic`** | macOS untouched; actor named because position is 2 under `-lc` and 11 under `-lic` |
| 9 | bats | both guard branches via `_OVERRIDE_BREW_PREFIX`; link step skipped when `LINUX` unset | the guard's true branch is unreachable on macOS without the seam |
| 10 | mutation | delete the block -> 1 and 3 red; drop the `! -o interactive` guard -> **6 red** | proves the interactivity guard, not just the block |

Case 10's second arm is the one v1 lacked: it discriminates the clause the whole design rests on.

## Risks

**Lower than v1, and v1's framing was overstated.** Measured: a syntax error in `.zshenv` is
**non-fatal** — the command still runs, rc=0, error to stderr. A top-level `exit` **is** fatal.
So the rule is *no top-level `exit`*, `zsh -n` in `make lint` gates syntax, and
`ssh workstation 'zsh -f -c ...'` is the escape hatch that bypasses the file entirely.

`.zshenv` must be added to `ZSH_FILES` at **both** call sites (`Makefile:51`,
`.github/workflows/ci.yml:60`) in the same change — `*.zsh` does not match `.zshenv`.

**Never write to stdout from this file.** It is on the wire for `ssh host '<cmd>'`, `scp` and
`rsync -e ssh`; a stray `echo` corrupts the command's own output. The proposed body emits
nothing; the rule exists for the first edit that adds a diagnostic.

## Open item, not yet decided

`run_doctor`'s `_doctor_check_symlinks` (`lib/helpers.sh:358`) is a flat unconditional array
covering `~/.zshrc`, `~/.zprofile`, `~/.config/.zshrc.d`. A Linux-only `.zshenv` either gets
an unconditional entry (doctor fails on all 6 macs, and it exits non-zero on any failure) or
no entry (the file is the only linked dotfile doctor never verifies). Needs a platform-aware
entry, which is a change to that function's shape. Flagged for the plan.

---

## History — v1 lens review (BLOCKED)

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

