# Fail closed when `config/profiles.sh` is read by a shell that cannot read it

**Date:** 2026-08-23
**Backlog row:** [14] `config/profiles.sh` silently mis-resolves under bash 3.2 — no version guard
**Status:** design

---

## Problem

`config/profiles.sh` is the single hostname→identity table. It declares three
associative arrays and its header says "requires bash 5+". Nothing enforces that.

Under bash 3.2 — macOS's `/bin/bash` — `declare -A` is rejected (`declare: -A: invalid
option`), the literal collapses to an **indexed** array, and every string subscript is
evaluated as an arithmetic expression. An unset name evaluates to `0`, so every wired
key writes element `0` and the last one wins; every `-1`-suffixed key evaluates to `-1`
and errors with `bad array subscript`, which bash 3.2 does not support.

The result is not an empty table. It is a table that answers **every** hostname with the
last wired entry's value.

### Measured, clean environment

`env -i HOME=… PATH=/usr/bin:/bin /bin/bash`, GNU bash 3.2.57(1)-release (arm64), on
the Mac Studio, `hostname -s` = `studio`:

```
detect_env rc=0
PROFILE=[wsl2_workstation]
LAPTOP=[] STUDIO=[] RECEPTION=[] RATNA=[] OFFICE=[] HOMES=[] WORKSTATION=[] CRUNCHER=[1]
HAS_DEVTOOLS=[] HAS_GUI=[] HAS_SNAP=[]
```

Same commands under bash 5:

```
PROFILE=[mac_workstation]
STUDIO=[1]
```

Four distinct consequences, and the first three are silent:

1. **`PROFILE` names a different machine class.** `wsl2_workstation` on a mac.
2. **The wrong legacy identity variable is set `readonly`.** `detect_env.sh:54` runs
   `readonly "${legacy}=1"` with `legacy=CRUNCHER`. `readonly` inside a bash function is
   global and irreversible for the process, so nothing later can correct it.
3. **Zero `HAS_*` capabilities are set.** This is worse than the backlog row predicted.
   The row expected the wrong profile's capabilities; measurement shows **none at all**,
   because `declare -g` (`detect_env.sh:33`) is also invalid in bash 3.2 and the
   capability loop silently sets nothing.
4. **`detect_env` returns 0.** The `source` on line 23 returns 2 and its status is
   discarded, so no caller can detect any of the above.


### Boundaries of these measurements

Stated separately from the claims they support, because three of them are narrower than
the sentences above would suggest on their own.

**The whole class is macOS-only.** The degradation needs `/usr/bin/env bash` to resolve
bash 3.x, and that is a macOS property, not a general one. Measured on the Linux
workstation over `ssh`, under the same `_PATH_STDPATH`:

```
env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin /usr/bin/env bash -c 'echo $BASH ${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}'
/usr/bin/bash 5.2
```

So on Linux no actor reaches bash 3.2 at all. Every claim below about cron, launchd and
`ssh host '<cmd>'` covers the five macs and excludes the two Linux boxes.

**The reproduction covers one machine.** It was run on the Mac Studio, `hostname -s` =
`studio`. The *mechanism* is a bash 3.2 language property and does not vary by host; the
*resolved value* is likewise host-independent, because element 0 is whatever the last
non-suffixed `PROFILE_MAP` key wrote — today `[cruncher]="wsl2_workstation"` and
`[cruncher]="CRUNCHER"`. What does vary by host is whether that answer is wrong.

**On `cruncher` itself, bash 3.2 returns the correct answer by accident.** Its true
profile *is* `wsl2_workstation` and its true legacy variable *is* `CRUNCHER`, so it is the
one hostname in the table for which the degraded lookup and the correct lookup agree.
That is not a reason to narrow the fix — it is a reason not to use `cruncher` as a test
fixture, since a test written against it cannot discriminate. Group B below uses `studio`
for exactly this reason.

**`declare -g` is a second, independent failure.** Consequence 3 above is caused by
`detect_env.sh:33`, not by `config/profiles.sh`. The guard in this design prevents it by
making line 33 unreachable under bash 3.2, rather than by fixing it — see Out of scope.

## What the backlog row got wrong, and why it is being corrected rather than implemented

Row [14] states the defect is reachable "because `setup_env.sh` is `#!/usr/bin/env bash`
and `ssh host '<cmd>'`, cron and launchd all get `_PATH_STDPATH`, where
`/usr/bin/env bash` finds 3.2".

The first half is true and was re-measured:

```
env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin /usr/bin/env bash -c 'echo $BASH ${BASH_VERSINFO[0]}'
/bin/bash  3
```

The conclusion is false. `setup_env.sh:20` already carries a bash-5 guard, and it runs
_before_ the Homebrew prerequisite check and _before_ any `source`:

```
env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin /usr/bin/env bash ./setup_env.sh -t doctor
[ERROR] bash 5+ required (running bash 3.2.57(1)-release).
        On macOS, run first: ./scripts/bootstrap_mac.sh
```

That guard landed in `3d2e0a6`, **2026-04-01** — four and a half months before the row
was filed on 2026-08-18. The row was wrong when written, not stale.

The full sourcing graph is one chain, and it is fully enumerated:

| file                     | sources              | guarded?                        |
| ------------------------ | -------------------- | ------------------------------- |
| `setup_env.sh:44`        | `lib/detect_env.sh`  | yes, `setup_env.sh:20`          |
| `lib/detect_env.sh:23`   | `config/profiles.sh` | **no**                          |
| `config/profiles.zsh:41` | `config/profiles.sh` | n/a — zsh has associative arrays |

That enumeration is derived from the repo's own content-derived shell scope
(`scripts/list-shell-files.sh`, 104 files — every tracked file whose first line is a
bash/sh shebang, so extensionless hooks and `tests/mocks/` fixtures are included) unioned
with the tracked zsh files, 115 in total. An extension-keyed `git ls-files '*.sh'`
pathspec was tried first and is the wrong instrument here, for the reason `shell.md`
gives: it cannot express "every tracked shell script" and silently drops the hooks.

Three further textual hits are comments, not sources: `config/hook_repos.sh:17`,
`scripts/run-bash-coverage.sh:135`, and `lib/helpers.sh:406` (a `doctor_fail` message
string).

`.bats` files sit outside that scope — they carry no shebang — and several do source
`config/profiles.sh` directly (`tests/zshrc.d/cross_shell.bats:133`,
`tests/zshrc.d/profiles.bats:108`). Those are test harnesses rather than entry points, so
they are treated as consumers to keep green, not as part of the production graph.

So **no entry point in the repo today reaches the degradation.** This spec therefore does
not claim to fix a live incident. It closes two structural gaps that the entry-point guard
happens to mask, and corrects the backlog row to record the falsification.

## What is actually wrong, independent of bash version

**`lib/detect_env.sh:23` discards a failure.** It is a bare `source` whose exit status is
never read. `shell.md`'s return-code propagation rule requires `|| return 1` at every
level of a call chain, and the zsh twin already complies:

```zsh
# config/profiles.zsh:41
if ! source "${${(%):-%x}:A:h}/profiles.sh"; then
  print -u2 "config/profiles.zsh: failed to source … -- PROFILE will default to 'unknown' …"
fi
```

The bash side has no equivalent. That gap fires on a **missing**, **unreadable**, or
**malformed** `profiles.sh` — not only on a wrong bash version. It is the general case
of which bash 3.2 is one instance.

**`config/profiles.sh` asserts a requirement it does not enforce.** Its header comment
says "requires bash 5+". A comment is not a gate. Any future second entry point that
sources `lib/detect_env.sh` — or `config/profiles.sh` directly — inherits the full
degradation with nothing between it and a wrong machine identity.

## Design

Files touched, so the scope is a statement rather than an inference:

| file | change |
| --- | --- |
| `config/profiles.sh` | version guard, above the first `declare -A` |
| `lib/detect_env.sh` | propagate the `source` failure at `:23` |
| `setup_env.sh` | read `detect_env`'s status at `:61` |
| `docs/superpowers/README.md` | rewrite backlog row [14] to record the falsification |
| `tests/setup_env/*.bats`, `tests/zshrc.d/*.bats` | the three test groups below |

### 1. `config/profiles.sh` — version guard

Placed above the first `declare -A`:

```bash
if [[ -z ${ZSH_VERSION} && ${_OVERRIDE_BASH_MAJOR:-${BASH_VERSINFO[0]:-0}} -lt 5 ]]; then
  printf "config/profiles.sh: bash 5+ required (running %s) -- under bash 3.2 declare -A is rejected, every hostname subscript evaluates arithmetically to 0, and each lookup below returns the last wired entry rather than this machine's.\n" \
    "${BASH_VERSION:-unknown}" >&2
  printf "        On macOS, run first: ./scripts/bootstrap_mac.sh\n" >&2
  return 1
fi
```

Four decisions, each with its reason:

**`return`, never `exit`.** This file is only ever sourced, never executed. `exit` would
terminate the caller — including, on the zsh path, a login shell. Verified that `return`
propagates a status out of a sourced file in both shells: `source /tmp/g.sh` containing
`return 3` yields rc=3 under zsh 5.9.2 and under bash 3.2.57.

**`-z ${ZSH_VERSION}` is load-bearing and is the whole reason this guard needs a design
rather than a one-liner.** The backlog row proposes
`[[ ${BASH_VERSINFO[0]:-0} -ge 4 ]]`. Measured under zsh:

```
zsh -c 'echo "raw=[${BASH_VERSINFO[0]:-UNSET}]"'
raw=[UNSET]
```

`BASH_VERSINFO` does not exist in zsh, so `:-0` supplies `0`, the guard fires, and
`profiles.zsh` — sourced by `.zprofile` at login and by `1_init.zsh` interactively —
loses the table. The row's own suggested fix delivers the exact failure the row exists to
prevent, on every mac and the Linux workstation, at login. `ZSH_VERSION` discriminates
cleanly: `5.9.2` under zsh, empty under both bash 3.2 and bash 5.

**Pinned at 5, not 4.** `declare -A` needs bash 4 and `declare -g` (used by
`detect_env.sh:33`) needs 4.2, so 4 is not sufficient for the chain even though it is
sufficient for this file. 5 also matches `setup_env.sh:20` and this file's own header,
and no fleet machine runs bash 4 — macOS ships 3.2, Ubuntu ships 5.x.

**Reuses `_OVERRIDE_BASH_MAJOR`.** That seam already exists at `setup_env.sh:6` and is
already exercised by `tests/setup_env/unit.bats:297,307`. Reusing it avoids inventing a
second name for the same concept. A test that sets it while sourcing `setup_env.sh` will
now trip both guards, which is coherent — both mean "pretend this bash is too old".

### 2. `lib/detect_env.sh:23` — propagate the failure

```bash
if ! source "$(dirname "${BASH_SOURCE[0]}")/../config/profiles.sh"; then
  printf "lib/detect_env.sh: failed to source config/profiles.sh -- PROFILE would be 'unknown', no HAS_* capability set, and no legacy identity variable set. Refusing to continue.\n" >&2
  return 1
fi
```

**This is deliberately stricter than the zsh twin, and the asymmetry is justified by
actor, not drift.** `config/profiles.zsh:29-40` documents its choice to warn and
continue: that file is sourced by `.zprofile` at login, and aborting a login shell over a
degraded lookup is worse than the problem. That reason does not transfer.
`lib/detect_env.sh` is sourced by exactly one thing — `setup_env.sh`, a provisioning
script that installs packages, creates symlinks, and writes files keyed on `PROFILE` and
`HAS_*`. Continuing with `PROFILE=unknown` provisions the machine as a capability-less
host, silently and durably.

The change carries a comment saying so, sited next to the existing `readonly`-here /
`export`-there note at `detect_env.sh:44`, which is the same shape of deliberate
bash/zsh asymmetry and is the comment a future reader will find first.

### 3. `setup_env.sh:61` — read the return value

Without this, `detect_env`'s new `return 1` changes no decision — `setup_env.sh:61` calls
it bare. The reads-it test is what makes this a three-file production change rather
than two — four files counting the backlog correction, plus the test files.

```bash
if ! detect_env && [[ -z ${DOCTOR:-} && -z ${CHECK_VERSIONS:-} ]]; then
  exit 1
fi
```

`DOCTOR` and `CHECK_VERSIONS` are readonly globals set by `process_args`
(`lib/helpers.sh:641`), which runs at `:59`, so both are readable at `:61`. Their
dispatch sites are `:69` and `:70`, after this line.

**Why those two workflows continue rather than abort.** Both are read-only reporters and
both already bypass the Homebrew prerequisite at `setup_env.sh:12` for the same reason:
they must be able to run on a machine that is broken. `run_doctor` already has a
`PROFILE` check (`lib/helpers.sh:406`) that reports an unmapped hostname and fails the
run. Aborting before `run_doctor` would remove the diagnostic tool's ability to diagnose
this exact class, and would take the other checks — symlinks, tool presence, credential
directory permissions, `core.hooksPath` pins — down with it. `behavior.md`: under
pressure, surface more, not less.

The repo has no `set -e`, per `shell.md`, so `! detect_env && …` runs `detect_env`
exactly once and the compound condition is evaluated normally.

## Testing

Three groups. The split exists because **CI runs on `ubuntu-latest`, which has no bash
3.2**, so a real-3.2 test is macOS-only and its green is not CI evidence — `tdd.md`
pitfall G.

**Group A — seam tests, run everywhere.** Drive `_OVERRIDE_BASH_MAJOR` so the branch is
reachable on Linux and on CI:

| case                                                   | assert                                                                       |
| ------------------------------------------------------ | ---------------------------------------------------------------------------- |
| `profiles.sh` sourced with `_OVERRIDE_BASH_MAJOR=4`    | rc non-zero, stderr names bash 5 and `bootstrap_mac.sh`, `PROFILE_MAP` unset |
| `profiles.sh` sourced with the seam unset, real bash 5 | rc 0, `PROFILE_MAP[studio]` = `mac_workstation`                              |
| `detect_env` with `config/profiles.sh` unreadable      | rc 1, stderr names the file                                                  |
| `detect_env` normal                                    | rc 0 (guards against the propagation change breaking the happy path)         |
| `setup_env.sh -t update` with `detect_env` failing     | exits 1, does not reach any workflow                                         |
| `setup_env.sh -t doctor` with `detect_env` failing     | reaches `run_doctor`                                                         |

**Group B — real bash 3.2, macOS only, skipped elsewhere.** Guarded by an explicit
version probe on `/bin/bash`, skipping rather than passing when absent, so a skip is
visible rather than a silent green:

- `/bin/bash -c 'source config/profiles.sh'` returns non-zero and prints the remedy
- `/bin/bash` sourcing `lib/detect_env.sh` and calling `detect_env` returns non-zero,
  and **`CRUNCHER` is not set** — the specific irreversible symptom, asserted directly

**Group C — zsh, pinning the trap.** `zsh -c 'source config/profiles.sh'` returns 0 and
`PROFILE_MAP` is populated. **Mutation-checked**: with `-z ${ZSH_VERSION} &&` removed
from the guard, this test must go red. A test that passes both with and without the
clause tests nothing, and this clause is the single highest-risk line in the change.

## Verification

Run before claiming done, with output recorded:

```bash
make lint                                  # bash -n, zsh -n, shellcheck
make test                                  # full bats suite
zsh -c 'source config/profiles.sh; echo "${PROFILE_MAP[studio]}"'   # -> mac_workstation
/bin/bash -c 'source config/profiles.sh'; echo "rc=$?"              # -> rc=1 + remedy
env -i PATH=/usr/bin:/bin /bin/bash -c 'source lib/detect_env.sh; detect_env; echo rc=$?; echo "CRUNCHER=[${CRUNCHER}]"'
                                           # -> rc=1, CRUNCHER=[]
```

The `zsh -c` line is the regression check for the trap this design exists around, and it
must be run from the worktree rather than relying on `zsh -i -c 'exit'` — `~/.zshrc` and
`~/.config/.zshrc.d` are symlinks into the main checkout, so an interactive shell sources
the unmodified files and passes regardless of what the branch changed (`CLAUDE.md`,
measured during #222).

## Out of scope

- **Changing `config/profiles.zsh`'s warn-and-continue semantics.** Deliberate, documented
  at `:29-40`, and correct for a login shell.
- **`declare -g` at `detect_env.sh:33`.** Also invalid under bash 3.2, but with the guard
  in place that line is unreachable under 3.2, so rewriting it is a fix for a state that
  can no longer occur.
- **Any change to the entry-point guard at `setup_env.sh:20`.** It works; it is what
  falsified the backlog row.

## Backlog

Row [14] is rewritten in the same change, not deleted, to record that its reachability
claim was false at the time of filing and what replaced it. `behavior.md`'s
premise-verification rule is the reason: a row that is quietly removed teaches nothing,
and the next reader re-derives the same wrong claim.
