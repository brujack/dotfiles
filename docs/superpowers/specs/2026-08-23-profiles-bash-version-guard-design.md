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

**`config/profiles.sh`'s failure under bash 3.2 is non-zero by accident, and one appended
line silences it.** This is the subtle half, and it is the whole case for the guard.

Change 2 above appears to make a version guard redundant: measured under real bash 3.2,
`source config/profiles.sh` already returns 2 with no guard present, so propagating that
status is enough to fail closed today.

```
env -i PATH=/usr/bin:/bin /bin/bash -c 'source config/profiles.sh; echo SOURCE_RC=$?'
SOURCE_RC=2
```

But a sourced file returns the status of its **last executed command**, and the last
statement in this file is the `PROFILE_LEGACY` `declare -A` at `:55` — which fails under
3.2. That is positional, not structural. Append any succeeding statement that succeeds —
a `readonly`, an `export`, a `printf`, a helper function definition, a trailing
`return 0` someone adds for tidiness — and the file returns 0 under bash 3.2 while every
lookup in it is still wrong. Change 2 then reports success and goes blind to the exact
class it was added for, with nothing in either file to indicate it.

The guard makes the non-zero return **structural** rather than positional: it fires
before any table is declared, so no later edit can move it.

**The argument this spec does not make, deliberately.** An earlier draft justified the
guard as insurance against "any future second entry point that sources
`lib/detect_env.sh`". That argument was measured and dropped: over this repo's full
history there has only ever been one production sourcer of the chain — `setup_env.sh`,
established when `5dc1efd` split the monolith into `lib/*.sh` — and no new file sourcing
`lib/detect_env.sh` or `config/profiles.sh` has ever been added. The cross-repo and
machine-local cases were checked too: the single hit outside dotfiles
(`math/scripts/run-bash-coverage.sh:372`) is a comment, and `config/local.sh` on the
Studio contains no reference. So that is insurance against an event with no observed
rate, and it is not why this ships. The appended-statement fragility is, and unlike the
entry-point argument it is falsifiable today — see Group A case 7.

## Design

Files touched, so the scope is a statement rather than an inference:

| file | change |
| --- | --- |
| `config/profiles.sh` | version guard, above the first `declare -A` |
| `lib/detect_env.sh` | propagate the `source` failure at `:23` |
| `setup_env.sh` | read `detect_env`'s status at `:61` |
| `lib/helpers.sh` | `_doctor_check_profile` must distinguish unset from `unknown` |
| `docs/superpowers/README.md` | rewrite backlog row [14] to record the falsification |
| `tests/setup_env/*.bats`, `tests/zshrc.d/*.bats` | the three test groups below |

### 1. `config/profiles.sh` — version guard

Placed above the first `declare -A`:

```bash
if [[ -z ${ZSH_VERSION:-} && ${_OVERRIDE_BASH_MAJOR:-${BASH_VERSINFO[0]:-0}} -lt 5 ]]; then
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

**`-z ${ZSH_VERSION:-}` is load-bearing and is the whole reason this guard needs a design
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

### 4. `lib/helpers.sh` — let `doctor` name the right cause

Change 3 keeps `-t doctor` running so the operator can diagnose this class. Without this
fourth change that decision backfires: `detect_env` now returns at `:23`, *before* `:31`
assigns `PROFILE`, and `_doctor_check_profile` (`lib/helpers.sh:397-410`) tests
`${PROFILE:-unknown}` — which collapses "the table never loaded" into "this hostname is
not in the table" by construction. On the Studio it would print:

```
[FAIL] PROFILE: unmapped hostname 'studio' — add a row to config/profiles.sh
```

for a hostname that is on line 32 of that file. `detect_env`'s accurate stderr line is
printed first, but `doctor_fail` is what sets the exit code and the summary line, so the
misdiagnosis is the durable artifact and the accurate line scrolls past.

This is two `behavior.md` failures at once — a guard's failure branch absorbing the
failure of the guard itself, and a two-valued field reporting a three-valued outcome —
landing in the one workflow change 3 deliberately kept alive *so that it could report
this*. The fix is a third branch, distinguishing unset from `"unknown"`:

```bash
if [[ -z ${PROFILE+x} ]]; then
  doctor_fail "PROFILE" "config/profiles.sh did not load — the identity table is unavailable, so no hostname can resolve. Check the file exists, is readable, and that this shell is bash 5+."
elif [[ "${PROFILE}" == "unknown" ]]; then
  doctor_fail "PROFILE" "unmapped hostname '$(hostname -s)' — add a row to config/profiles.sh"
else
  doctor_pass "PROFILE (${PROFILE})"
fi
```

`${PROFILE+x}` rather than `${PROFILE:-}` is deliberate: it distinguishes *unset* from
*set-but-empty*, and only the unset case means the table never loaded.

**Two related degradations, one of which was reported and is wrong.** A review lens
claimed `lib/helpers.sh:710`'s `[[ -n ${HAS_DEVTOOLS} ]]` block would silently skip. It
would not, for two reasons: that line is in `run_setup_user`'s symlink section, not in
`run_doctor`, and it sits inside a `[[ -n ${LINUX} ]]` branch while this whole class is
macOS-only. Recorded rather than silently dropped, because the claim is plausible on its
face and the next reader will re-derive it.

What is real and is being left alone: `run_doctor`'s environment dump prints
`CHRUBY_LOC=<unset>` (`lib/helpers.sh:378`), because `CHRUBY_LOC` is assigned at the end
of `detect_env` (`:57-61`), after the early return. That output is accurate — the
variable genuinely is unset — so it needs no change.

## Testing

Three groups. The split exists because **CI runs on `ubuntu-latest`, which has no bash
3.2**, so a real-3.2 test is macOS-only and its green is not CI evidence — `tdd.md`
pitfall G.

**Every case below states what it would take to fail.** An earlier draft did not, and
three independent review lenses found the same structural defect in it: several cases
asserted an *absence* that is true before the test runs. "`CRUNCHER` is not set" cannot
fail on any machine where the test can execute — `/bin/bash` 3.2 is macOS-only and
`cruncher` is the WSL2 box, so `CRUNCHER` is unset by construction. "`PROFILE_MAP` is
unset" is the same shape: bash arrays cannot be exported, so no parent can ever supply
one. A wrong fixture path, a `source` that silently no-ops, or a guard that never
executes would each have passed.

### Group A — seam-driven, runs everywhere including CI

| # | case | fails when |
| --- | --- | --- |
| A1 | `profiles.sh` sourced with `_OVERRIDE_BASH_MAJOR=4` | rc is 0, or stderr lacks both "bash 5+" and `bootstrap_mac.sh` |
| A2 | `profiles.sh` sourced normally under bash 5 | rc non-zero, or `PROFILE_MAP[studio]` is not `mac_workstation` |
| A3 | `detect_env` with `config/profiles.sh` unreadable (`chmod 000` on a fixture copy) | rc is 0, or stderr does not name the file |
| A4 | `detect_env` normal | `PROFILE` is not `mac_workstation` **or** `STUDIO` is not `1` — a value assertion, not `rc -eq 0`, because `PROFILE="${PROFILE_MAP[…]:-unknown}"` at `detect_env.sh:31` cannot fail and rc 0 survives an empty table |
| A5 | `setup_env.sh -t update` with `detect_env` forced to fail | it does not exit 1, or it reaches a workflow function |
| A6 | `setup_env.sh -t doctor` with `detect_env` forced to fail | `run_doctor` is not reached |
| A7 | **fragility pin** — a fixture copy of `profiles.sh` with the guard removed and a trailing `printf ''` appended, sourced under `_OVERRIDE_BASH_MAJOR=4` semantics | `source` returns non-zero. It must return **0**, proving the un-guarded file's failure signal is positional. Then the same fixture *with* the guard must return non-zero. This is the test for the argument the guard actually ships on |
| A8 | `doctor` with `PROFILE` unset vs `PROFILE=unknown` | both produce the same `doctor_fail` message — they must differ, and the unset one must not say "add a row" |

### Group B — real bash 3.2, macOS only

Skipped, not passed, when `/bin/bash` is not 3.x, so the skip is visible. **Every case
runs under `env -i`**: a zsh login shell `export`s `PROFILE`, `STUDIO` and seven `HAS_*`
into every child including bats, so a value assertion without `env -i` reads the parent's
environment rather than the code's output.

| # | case | fails when |
| --- | --- | --- |
| B1 | **positive control** — real `/bin/bash`, `_OVERRIDE_BASH_MAJOR=9` to bypass the guard, `source lib/detect_env.sh; detect_env` | `PROFILE` is not `wsl2_workstation`, or `CRUNCHER` is not `1`. This case must reproduce the defect. If it ever goes green-by-passing, the harness is not reaching the code and every other case in this group is uninformative |
| B2 | same, guard active | `PROFILE` is set at all, or `CRUNCHER` is set, or `detect_env` returns 0 |
| B3 | `/bin/bash -c 'source config/profiles.sh'` | stderr lacks the remedy string. **Not** asserted on rc alone — the un-guarded file already returns non-zero under 3.2, so an rc assertion here passes with the guard deleted |

B1 is the case the earlier draft lacked. Verified reachable during review:

```
env -i HOME=$HOME PATH=/usr/bin:/bin /bin/bash -c 'source lib/detect_env.sh; detect_env; …'
rc=0 PROFILE=[wsl2_workstation] CRUNCHER=[1] STUDIO=[] HAS_DEVTOOLS=[]
```

### Group C — zsh

| # | case | fails when |
| --- | --- | --- |
| C1 | `zsh -c 'source config/profiles.sh'` | rc non-zero, or `PROFILE_MAP[studio]` is not `mac_workstation` — a value, not "the array is populated" |
| C2 | **mutation check** — C1 re-run against a fixture copy with `-z ${ZSH_VERSION:-} &&` deleted from the guard | it stays green. It must go red |

C2 is the point of Group C. C1's assertion alone is largely already covered by
`tests/zshrc.d/cross_shell.bats:132`, which sources `config/profiles.sh` and derives every
host from `PROFILE_MAP` through a zsh snapshot with a non-empty guard at `:145` — so a
guard wrongly firing under zsh already turns that suite red. C1 is kept as a local,
readable statement of the property; C2 is what makes this group earn its place.

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

## Multi-Lens Review

Reviewed at commit: `675c595` (Step 7 self-review commit, before Step 8 dispatch)

### Goal-Fit

Finding: The reads-it test splits the spec. Changes 2 and 3 pass — they change a real
verdict and fire on version-independent cases (missing/unreadable/malformed). Change 1
fails as the spec argued it: measured `source config/profiles.sh` under real bash 3.2
returns rc=2 **with no guard present**, so once change 2 lands the production graph
already fails closed and the guard changes no verdict today. The one honest argument for
keeping it, which the spec never made, is that rc=2 is *incidental* — it holds only
because the file's last statement is the failing `PROFILE_LEGACY` `declare -A` at `:55`.
Also: the doctor exemption preserves the diagnostic but corrupts its message
(`helpers.sh:405` tells the operator to add a row to the file that just failed to load),
and only one of nine test cases pinned a derived value.

Assumption: That a second bash entry point sourcing `lib/detect_env.sh` or
`config/profiles.sh` is likely enough to justify change 1. Settle with a base rate:
count how many times a *new* file sourcing either has been added over the repo's history.

Disposition: **Addressed.** The base rate was measured and the assumption refuted — one
production sourcer ever (`setup_env.sh`, from the `5dc1efd` lib split), no new sourcer
ever added; the single cross-repo hit (`math/scripts/run-bash-coverage.sh:372`) is a
comment and `config/local.sh` on the Studio has no reference. The entry-point argument
was therefore deleted from the spec and replaced with the appended-statement fragility,
which is falsifiable today and is pinned by Group A case 7. Change 1 still ships, on the
rewritten argument. The doctor defect became Design §4; the test-case defect was fixed in
the Testing rewrite.

### Ergonomics

Finding: Same doctor defect, located precisely — `_doctor_check_profile`
(`lib/helpers.sh:397-410`) tests `${PROFILE:-unknown}`, collapsing "table never loaded"
into "hostname not in table" by construction, and `doctor_fail` sets the exit code and
summary so the misdiagnosis is the durable artifact. Additionally: Group B case 1 was
non-discriminating on rc, since the un-guarded file already returns non-zero under 3.2.
Also claimed `lib/helpers.sh:710`'s `HAS_DEVTOOLS` block would silently skip, and that
`CHRUBY_LOC` prints `<unset>`.

Assumption: That adding the guard turns no currently-green bats test red on the macOS 3.2
actor — the spec's only version-boundary measurement is "CI is ubuntu-latest, no 3.2" and
it never measures the actor that gates pushes locally. Settle with a before/after `not ok`
diff under `_PATH_STDPATH`.

Disposition: **Addressed**, with one half of the finding rejected on measurement. The
doctor defect became Design §4 and Group A case 8; Group B case 3 now asserts on the
remedy string rather than rc. The `helpers.sh:710` claim is **wrong** — that line is in
`run_setup_user`'s symlink section, not `run_doctor`, and sits inside a `[[ -n ${LINUX} ]]`
branch while this class is macOS-only; recorded in Design §4 rather than dropped, since
the claim is plausible and will be re-derived. `CHRUBY_LOC=<unset>` is real and accurate
output, left alone. The assumption is **moot as stated**: `bats` is not found under
`_PATH_STDPATH` at all, so the suite cannot run in that actor; separately, no test
executes `/bin/bash` as an interpreter and plain `bash` in bats resolves
`/opt/homebrew/bin/bash` 5.3.

### Risk

Finding: The mechanism is sound — verified that `return 1` from a file sourced inside a
function does not early-return `detect_env`; that `if ! detect_env && [[ … ]]` runs
`detect_env` exactly once and behaves under every argv shape (`process_args` sets both
globals `readonly` before `:61`, and `getopts` routes malformed `-t` through `usage; exit`);
that the guard cannot fire under zsh, both directions; and that splicing it above line 30
does not displace the file-wide `SC2034` directive (shellcheck 0.11.0, rc=0, three findings
when the directive is deleted). The risk is entirely in the test design: zero of nine cases
pinned a non-zero value the mechanism produces, and Group B's discriminating assertion
("`CRUNCHER` is not set") is true before the test does anything, because `/bin/bash` 3.2 is
macOS-only and `cruncher` is the WSL2 box. Secondary: `setup_env.sh:61`'s `DOCTOR`/
`CHECK_VERSIONS` carve-out is a second hand-maintained copy of the argv carve-out at
`:9-18`, which has a third member (`--brew-install`). Also `${ZSH_VERSION}` should be
`${ZSH_VERSION:-}`.

Assumption: That the sourcing graph is complete — it is derived from this repo's tracked
shell scope, which is structurally blind to a consumer in another repo or a machine-local
file (`config/local.sh` is git-ignored). Settle by grepping the other eight repos and
`config/local.sh` on each development machine.

Disposition: **Addressed**, except the carve-out duplication which is **backlogged**. The
Testing section was rewritten around the positive control the lens supplied (Group B case
1, `_OVERRIDE_BASH_MAJOR=9` under real 3.2, asserting `PROFILE=wsl2_workstation` and
`CRUNCHER=1`), every case now states its failure condition, and Group B runs under
`env -i`. `${ZSH_VERSION:-}` applied. The carve-out duplication is real but not a defect
today and is a separate change; it is filed as a backlog row rather than widened into this
diff. The assumption was checked and refuted for the Studio — the one cross-repo hit is a
comment, `config/local.sh` has no reference — with the honest caveat that `config/local.sh`
is per-machine and only the Studio was measured.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison, no evaluator/judge component, and its acceptance criteria
are concrete commands with stated expected output.

