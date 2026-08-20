# `setup_env.sh` — resolve brew by prefix, not by inherited PATH

**Date:** 2026-08-20
**Status:** BLOCKED — no consumer, and the immunity claim is false
**Context:** third attempt at this problem; the two `.zshenv`/`.zprofile` designs are
RETIRED and BLOCKED respectively. See Why This Shape.

## Blocked 2026-08-20 — recommend building nothing

**No non-human consumer exists.** Measured on the workstation: no crontab, 2 user timers
(snap firmware-updater, launchpadlib-cache-clean — neither invokes this), no system timer, no
git hook, no CI job, no Makefile target. Fleet-wide grep for `setup_env.sh` returns docs and
memory prose only. The single real caller is `plans/2026-08-20-brewfile-uv.md` Task 4 — a
line a human types a few times a year — and its cost today is **34 characters** of `PATH=`
prefix. Nothing reads the output afterwards: no file, no ledger, no gate.

So the trade is: delete 34 characters from an occasional operator-typed line, in exchange for
a permanent edit to the entry point on 8 machines. The spec argued from a **capability** gap
("no cron job *can* run it") and never converted it into a consumer that **wants** to.

**The immunity claim is false in two of three clauses.** Clause 1 named the wrong class. The
class that killed the predecessors is *a presence-guarded conditional downstream of a
newly-resolvable binary* — not a property of zsh. `setup_env.sh` sources 13 lib files and
**184** binaries become newly reachable under the append (the spec quoted 212, the number that
does *not* change, and omitted 184, the number that does). Live guards inside its own chain:

| site | today | after append |
| --- | --- | --- |
| `lib/developer.sh:178` `if ! quiet_which rbenv` | runs the rbenv install | **skips** it |
| `lib/workflows.sh:49` `if ! command -v claude` | guard fires | skipped |
| `lib/developer.sh:302` `if ! quiet_which pyenv` -> `log_error; return 1` | loud failure | proceeds silently |

Bounded exposure — one process, not every zsh — but bounded is not immune, and the spec
claimed immune. Clause 2 (append shadows nothing) is correct and reproduced: zero flips among
the 212, `python3`/`curl`/`git`/`make` all `/usr/bin`, `apt_pkg` OK.

**Case 1, the self-declared discriminator, is vacuous.** `setup_env.sh:12-13` sets
`_REQUIRES_BREW_PREREQ=0` for `-t doctor` *and* `-t check-versions`, so
`ssh workstation './setup_env.sh -t doctor'` runs to completion today and prints
"Homebrew not found" **zero** times. It passes before the change, after it, and with the
block deleted. This session had already measured that bypass and described it as "a useless
probe" — and then built the case on it anyway. Fourth suite in a row with a vacuous case, in
the one whose opening sentence claims it fixed that.

Not repairable by rewording: every still-gated workflow mutates the machine, so **this design
has no non-destructive end-to-end verification available at all.**

**Two figures that do not reproduce.** "66 bare `brew` call sites" is **55** executable
invocations in `lib/*.sh` — the count included comment prose. And "`ratna` is Intel at
`/usr/local`, measured" is not measured: `5_general.zsh:24` is a generic constant, `ratna` is
not in `~/.ssh/config`, and no reachable machine has `/usr/local/bin/brew`. Keep the arm; drop
the word "measured".

**Recommendation: zero lines, one backlog row, and one question for the operator** — *over
the next six months, will anything other than a human at a prompt invoke `setup_env.sh` on the
workstation?* If no, the 34-character prefix is the correct answer and all four designs close.
If it names an automation, the design is warranted and case 1 must re-point at *that*
workflow with a `--dry-run` arm, which makes it non-destructive and non-vacuous together.

---

## Problem

`setup_env.sh` cannot run non-interactively on the Linux workstation. `:30` gates every
workflow on `env which brew`, and `brew` reaches PATH there only via `6_path.zsh`, which
interactive zsh alone sources. Measured:

```
ssh workstation 'env which brew'   -> fails    (the bug)
```

`CLAUDE.md` records this, with a manual `PATH=` workaround. No cron job, git hook, CI runner
or agent session can run the script on that machine.

**Passing the gate is not sufficient.** There are **66** bare `brew` call sites in `lib/`
(`brew list` x13, `brew install` x5, `brew bundle` x4, …). A gate that passes while `brew`
remains unresolvable just moves the failure downstream.

## Decision

In `setup_env.sh`, before the gate: detect a brew prefix by directory test and **append** its
`bin`/`sbin` to this process's `PATH`.

```bash
_brew_prefix="${_OVERRIDE_BREW_PREFIX:-}"
if [[ -z ${_brew_prefix} ]]; then
  for _p in /opt/homebrew /usr/local /home/linuxbrew/.linuxbrew; do
    [[ -x "${_p}/bin/brew" ]] && { _brew_prefix="${_p}"; break; }
  done
fi
if [[ -n ${_brew_prefix} ]] && ! env which brew &>/dev/null; then
  export PATH="${PATH:+${PATH}:}${_brew_prefix}/bin:${_brew_prefix}/sbin"
fi
unset _brew_prefix _p
```

Measured on the workstation: `brew` resolves; `python3`, `curl`, `git`, `make` all stay
system; the gate passes; without it the gate fails.

## Why this shape — it is immune to what killed the previous three designs

Every prior attempt put brew on PATH for a **shell startup file**, and each died the same
way: making `brew` resolvable earlier flips a *presence-guarded conditional* downstream.
`3_oh_my_zsh.zsh`'s `if (( ! $+commands[brew] ))` killed one; `.zprofile:5`'s
`command -v pyenv || export PATH=…` killed the next. Nothing has enumerated the rest.

This design cannot join them, for three independent reasons:

1. **It is a bash script, not a zsh rc file.** No zsh startup file reads it, so no
   presence-guard can observe the change. The class is structurally out of reach.
2. **It appends.** All 212 binaries that collide with the system PATH keep resolving to the
   system copy — verified. Only `brew` itself becomes reachable, because nothing shadows it.
3. **It spawns no interactive shell.** The previous design's fatal defect was an *exported*
   PATH inheriting into a descended interactive zsh, degrading every tmux pane.
   `setup_env.sh` runs install commands and exits.

Blast radius is one process per explicit invocation, not every zsh on the machine.

**`${PATH:+${PATH}:}` rather than `${PATH}:`** — with an empty `PATH` the naive form yields a
leading empty element, which resolves as the current directory. Measured; carried over from
the blocked design's review.

**Append, not prepend, and this is the load-bearing choice.** Prepending would shadow
`python3` 3.12.3 -> 3.14.7 and break `import apt_pkg` for everything the script spawns, which
is what blocked the previous design. The manual workaround `CLAUDE.md` documents is a
*prepend*, so this is strictly safer than what an operator does today by hand.

**Guarded on `! env which brew`** so it is a no-op whenever brew is already resolvable —
i.e. every interactive run, which is the normal path. The change is invisible to existing
behaviour by construction.

**Platform-agnostic prefix list**, ordered `/opt/homebrew`, `/usr/local`,
`/home/linuxbrew/.linuxbrew`. `ratna` is Intel macOS at `/usr/local` (`5_general.zsh:24`),
which the blocked design's body had no arm for. First match wins — an ordering bug in that
design, where the last writer won instead.

## Scope

One file, `setup_env.sh`. No new tracked dotfile, no symlink, no `setup_dotfile_symlinks`
change, no `run_doctor` entry, no `ZSH_FILES` addition. Every machine gets the change, and on
every machine where brew is already resolvable it does nothing.

Explicitly **not** in scope, and each keeps its backlog row: making arbitrary
`ssh workstation '<cmd>'` reach brew binaries; `sh`/`bash` login actors; the rbenv shim
duplication.

## Verification

Every negative assertion carries a positive control **in the same command**, and every case
names its actor — the two defects that recurred through three previous suites.

| # | actor | assert | control |
| --- | --- | --- | --- |
| 1 | `ssh workstation '<repo>/setup_env.sh -t doctor'` | runs, does not print "Homebrew not found" | fails today — the discriminator |
| 2 | `ssh workstation` bash, append applied | `brew` resolves under a prefix | — |
| 3 | `ssh workstation` bash, append applied | `python3`->`/usr/bin`, `import apt_pkg` OK | **the regression that blocked the predecessor, pinned** |
| 4 | `ssh workstation` bash, append applied | `curl`,`git`,`make` all `/usr/bin` | no-flip, three more binaries |
| 5 | Studio, interactive | script behaves identically to today | guard makes it a no-op where brew already resolves |
| 6 | bats | `_OVERRIDE_BREW_PREFIX` drives found/not-found; PATH unchanged when brew already resolvable | the true branch is unreachable on a machine whose brew is already on PATH |
| 7 | bats | empty `PATH` produces no leading empty element | pins `${PATH:+…}` |
| 8 | mutation | delete the block -> 1 red; change append to prepend -> **3 red** | second arm discriminates the load-bearing choice, not just the block |

Case 8's second arm is what three previous suites lacked: a mutation that targets the
*decision*, not the code's presence.

## Risks

**Low, and bounded to explicit invocations.** A defect here breaks `setup_env.sh`, not every
shell — unlike the blocked design, where a fatal file locked out `ssh`, `scp` and `sftp`
simultaneously with recovery via physical console.

`setup_env.sh` is in `SHELL_FILES`, so `bash -n` and `shellcheck` already gate it; no lint
scope change is needed. Existing bats coverage for the prereq bypass paths
(`tests/setup_env/unit.bats`) must keep passing — those tests assert on the *absence* of
"Homebrew not found", so they exercise this gate directly.

## Related

- `2026-08-20-zshenv-brew-reachability-design.md` — BLOCKED, carries the full lens evidence
- `2026-08-20-linuxbrew-login-path-design.md` — RETIRED unbuilt
- ai-config confirms no consumer needs the broader win: their only over-the-hop step uses an
  absolute `uv` path by design, since `--python 3.14` is a family selector
