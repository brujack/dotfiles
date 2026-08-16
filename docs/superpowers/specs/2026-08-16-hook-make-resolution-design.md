# GNU make resolution inside git hooks

**Date:** 2026-08-16
**Status:** Draft — awaiting review
**Closes:** `docs/superpowers/README.md` backlog rows "Decide whether GNU make should resolve for non-interactive shells, or only interactively" and "An agent tool shell is not the 3.81 actor `CLAUDE.md` describes"
**Supersedes:** `2026-08-16-system-wide-gnu-make-design.md` (retired — see below)
**Related:** ADR-0018 (GNU Make 4.x on macOS), dotfiles#214

---

## Problem

A `git commit` or `git push` issued from an editor UI runs this repo's hooks under a
different `make` than the same command issued from a terminal. Measured on the Studio,
2026-08-16, against the **running** VS Code process (pid 22156):

```
$ ps eww -o command= -p 22156 | tr ' ' '\n' | grep '^PATH='
PATH=/opt/homebrew/Library/Homebrew/shims/shared:/usr/bin:/bin:/usr/sbin:/sbin

$ ls /opt/homebrew/Library/Homebrew/shims/shared/
curl  git  rustc_wrapper  ...          # provides git and curl -- NOT make
```

`make` therefore falls through to `/usr/bin/make`. The consequence is behavioural, not
cosmetic:

| lineage                       | `command -v make` | version        | `make -C <dir> <target>` output    |
| ----------------------------- | ----------------- | -------------- | ---------------------------------- |
| editor-spawned (`PATH` above) | `/usr/bin/make`   | GNU Make 3.81  | **0 lines**                        |
| terminal / session            | `.../gnubin/make` | GNU Make 4.4.1 | **2 lines** (`Entering`/`Leaving`) |

The operator commits from an editor UI sometimes. So `scripts/pre-commit-hook.sh` →
`make lint` and `scripts/pre-push` → `make test` genuinely run under 3.81 for those commits,
while every other route runs 4.4.1 — and nothing reports which one ran.

This matters beyond the version number. `CLAUDE.md`'s "MAKEFLAGS and Stdout Partition"
section and `tests/scripts/makefile_lint_scope.bats` exist because print-directory behaviour
differs across make versions; `tdd.md` pitfall G records the same class. A gate that silently
selects its own make version by how the commit was launched is the actor-boundary failure
`behavior.md` describes: _who runs this in production, and did I run it as them?_

## What was tried first, and why it failed

The predecessor spec proposed a symlink at `/usr/local/bin/make`, reasoning from `/etc/paths`
that `/usr/local/bin` precedes `/usr/bin` on "the system default `PATH`". Three independent
review lenses killed it and four measurements confirmed the kill: `/etc/paths` governs
**login shells** via `path_helper`, and none of the actors in question consult it.

| actor              | `PATH`                                           | source                                                  |
| ------------------ | ------------------------------------------------ | ------------------------------------------------------- |
| cron               | `/usr/bin:/bin`                                  | compiled `_PATH_DEFPATH`, stamped into every child      |
| launchd job        | `/usr/bin:/bin:/usr/sbin:/sbin`                  | compiled `_PATH_STDPATH`; `launchctl getenv PATH` unset |
| `ssh host '<cmd>'` | `/usr/bin:/bin:/usr/sbin:/sbin`                  | sshd; a non-login zsh never calls `path_helper`         |
| VS Code            | `.../shims/shared:/usr/bin:/bin:/usr/sbin:/sbin` | launchd, plus Homebrew's shim dir                       |

None contains `/usr/local/bin`. The full record, including the two test-design defects the
lenses found, is in the retired spec; it is kept rather than deleted because it documents a
real dead end with the measurements that closed it.

The lesson carried forward into this design: **verify which `PATH` the actual actor has, by
reading a live process, before proposing anything that manipulates `PATH`.**

## Decision

Prepend the Homebrew `make` gnubin directory to `PATH` inside this repo's two hook entry
points, immediately before they invoke `make`.

This targets the gates themselves rather than the environment. It works under every lineage —
editor, terminal, cron, ssh, launchd — because it does not depend on what the caller's `PATH`
happened to be. It requires no `sudo`, no reboot, and changes nothing outside this repo.

```bash
# scripts/pre-push, immediately above `make -C "${REPO_ROOT}" test`
# scripts/pre-commit-hook.sh, immediately above `make lint`
#
# Resolve GNU make regardless of how this hook was launched. An editor-spawned
# git inherits launchd's PATH (/usr/bin:/bin:/usr/sbin:/sbin), which has no
# gnubin, so `make` would be /usr/bin/make 3.81 while the same commit from a
# terminal gets 4.4.1 -- two different gates for one repo. Measured 2026-08-16
# against the running VS Code process; see
# docs/superpowers/specs/2026-08-16-hook-make-resolution-design.md
_gnubin=
for _d in /opt/homebrew/opt/make/libexec/gnubin /usr/local/opt/make/libexec/gnubin; do
    [[ -d "${_d}" ]] && { _gnubin="${_d}"; break; }
done
[[ -n "${_gnubin}" ]] && PATH="${_gnubin}:${PATH}"
unset _gnubin _d
```

Both prefixes are scanned, arm64 first — the same pair `install_make_macos` and `6_path.zsh`
already use, and here the pairing is correct rather than a deliberate divergence, because a
hook must work on whichever mac it runs on. On Linux neither directory exists and the loop is
a no-op, which is right: `make` there is already GNU 4.x.

### Why not the alternatives

**A machine-wide `PATH` change** (`sudo launchctl config user path`, plus a `PATH=` line in
the crontab) would reach the same actors and more. Rejected: it rewrites `PATH` for every GUI
application on the machine to fix four hooks, needs `sudo` and a reboot to take effect, and
is invisible from inside any repo — a future operator debugging a hook would find no
explanation in the code they are reading.

**Re-exec'ing the Makefile under GNU make when `$(MAKE_VERSION)` starts with 3** was
considered and rejected on readability. It requires a catch-all `%:` rule, which is exactly
the cleverness `USER.md` calls out; a five-line `PATH` prepend at the call site says what it
does.

**`.zshenv`** remains rejected for the reason the predecessor spec gave: it reaches zsh and
every actor here is bash.

## Scope

This spec covers `dotfiles` only. Three other repos have the same hole — `math`,
`etch-cli` and `state-ledger` each run `make` from a bash `scripts/pre-push` — but they are
separate repos with their own sessions and their own gate chains, and `behavior.md`'s
Surgical Changes rule puts them out of this diff.

They are not merely dropped. `math` and `etch-cli` have live sessions and are messaged with
the measurement directly; `state-ledger` has none, so it gets a backlog row in its own repo
per `behavior.md`'s Backlog Rows for Deferred Findings. That row names this spec, so the
finding does not depend on anyone remembering the conversation.

**A note on that handoff, recorded because this session already hit it once today.** A
cross-repo finding is written down in the source repo and discharged in the target repo, and
nothing links the two. The direction that goes stale is the source-side row: the work gets
done in the target, and the row advertising it as outstanding sits there until someone reads
it. Whoever closes the `state-ledger` row should delete it in the same change, not after.

## Attestation

The predecessor spec proposed a `doctor` check. This design deliberately has none, and the
reason is the substance of what the lenses found: a `doctor` probe would have to invent an
actor to measure, and an invented actor attests nothing about a real one.

The attestation belongs in the test suite instead, where the **real** hostile lineage can be
reproduced exactly:

```bash
env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME="${HOME}" bash <hook>
```

That is byte-for-byte launchd's `_PATH_STDPATH` — the environment an editor-spawned git
actually hands the hook — rather than a synthetic `env -i` default. A test that runs the hook
under it and asserts the resolved `make` is 4.x is testing the thing that broke.

**Platform boundary, stated rather than discovered later:** this assertion is meaningful on
macOS only. On `ubuntu-latest` neither gnubin exists, `make` is already GNU 4.3, and the test
must skip rather than pass — a skip is honest, a pass would be vacuous. So the guard runs
locally on the machines that have the problem and is explicitly not a CI gate. That is a real
limitation of this design and it is why the assertion is written as a behavioural check
(below) rather than a version-string check.

## Tests

`tests/scripts/pre_push.bats` and a new `tests/scripts/pre_commit.bats`, all three mandatory
categories from `tdd.md`:

| case                                                            | category         | asserts                                                               |
| --------------------------------------------------------------- | ---------------- | --------------------------------------------------------------------- |
| hook run under launchd's exact `PATH`, gnubin present           | state transition | the `make` the hook resolves is GNU 4.x, not 3.81                     |
| same, gnubin absent (both prefixes seamed to nonexistent paths) | boundary         | hook still runs; `PATH` unchanged; no error                           |
| gnubin present at the arm64 prefix only                         | boundary         | arm64 prefix selected                                                 |
| gnubin present at the x86_64 prefix only                        | boundary         | x86_64 prefix selected                                                |
| both prefixes present                                           | boundary         | arm64 wins (first match, loop breaks)                                 |
| hook run under a `PATH` that already has gnubin                 | idempotency      | no duplicate entry ahead of the rest; behaviour unchanged             |
| the prepend is a prepend, not an append                         | state transition | resolved `make` is the gnubin one even though `/usr/bin` is on `PATH` |

That last row is the one that matters most and it is not ceremony: `6_path.zsh` carries a
comment recording that this file's neighbouring idiom is `path+=`, that an append would leave
`/usr/bin` ahead, and that **an append would be inert and would still look correct**. The
same trap exists here verbatim. The test must assert the resolved binary, never that the
directory appears somewhere in `PATH`.

**Mutation check.** Change `PATH="${_gnubin}:${PATH}"` to `PATH="${PATH}:${_gnubin}"` and
confirm the prepend test goes red. Delete the loop entirely and confirm the launchd-lineage
test goes red. A guard that survives its own deletion is not being tested.

**Existing-suite risk.** Hooks currently resolve 3.81 under an editor lineage and 4.4.1
otherwise; after this change they always resolve 4.4.1 on a provisioned mac. Anything in the
suite that passes only under 3.81 will surface. That is the intended effect — it removes a
divergence rather than creating one — but the full suite must be green before merge, and a
new failure there is a finding to investigate, not a regression this change introduced.

## Documentation

| file                                      | change                                                                                                                                                                                                                               |
| ----------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `CLAUDE.md` (dotfiles)                    | Add the measured four-actor `PATH` table; state that hooks now resolve GNU make independently of their caller, and that this is the mechanism rather than the profile lineage                                                        |
| `CLAUDE.md` Testing section               | Note the macOS-only boundary on the launchd-lineage assertion                                                                                                                                                                        |
| `ai-config/.claude/standards/behavior.md` | The actor-boundary table's `make` row is the section's own worked example. It gains the editor lineage, which is the case that makes the point best: a _third_ answer, from a real process, that neither prior measurement predicted |
| `ai-config/.claude/standards/tdd.md`      | Pitfall G's premise gains the same qualifier                                                                                                                                                                                         |
| `docs/adr/0020-hook-make-resolution.md`   | New ADR, `Related: extends ADR-0018`                                                                                                                                                                                                 |
| `docs/superpowers/README.md`              | Delete backlog rows 9 and 17; mark both specs' All Plans rows                                                                                                                                                                        |

The two `ai-config` files are edited only after re-measuring that repo's tree state and
messaging its live session — that checkout's cleanliness is not a standing property, because
`~/.claude/settings.json` symlinks into it.

## Verification

**Already run** (recorded so the before/after is checkable rather than asserted):

```bash
ps eww -o command= -p <vscode-pid> | tr ' ' '\n' | grep '^PATH='
  → PATH=/opt/homebrew/Library/Homebrew/shims/shared:/usr/bin:/bin:/usr/sbin:/sbin
env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME=$HOME bash -c 'command -v make; make --version|head -1'
  → /usr/bin/make ; GNU Make 3.81
```

**Post-implementation:**

```bash
make test                                   # full suite green, new cases included
env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME="$HOME" bash scripts/pre-commit-hook.sh
                                            # resolves 4.4.1 -- currently 3.81
git commit from the editor UI, then from a terminal, and diff what each hook resolved
```

The last one is the end-to-end proof against the actual actor, and it is the check that
would have caught the predecessor design before it was written.

## Out of scope

- `math`, `etch-cli`, `state-ledger` — same hole, handled per the Scope section.
- The machine-wide `PATH` question (`launchctl config user path`) — rejected above.
- The dead `push-bash-coverage` crontab entry, which has its own backlog row and two
  independent failures unrelated to make's version.
- `/usr/local/bin` in any form — measured to reach nothing here.
