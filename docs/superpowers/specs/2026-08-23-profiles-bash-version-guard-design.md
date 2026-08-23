# Fail closed when the identity table does not load

**Date:** 2026-08-23
**Backlog row:** [14] `config/profiles.sh` silently mis-resolves under bash 3.2 — no version guard
**Status:** design (scope narrowed after three review rounds — the bash-version guard was cut; see Out of scope)

---

## Summary

**Ships:** `lib/detect_env.sh` propagates the `source` failure it currently discards;
`setup_env.sh` reads that status; `lib/helpers.sh` gets a sentinel branch so `doctor` does
not regress as a result. Three production files, version-independent, testable on CI.

**Cut:** a bash-version guard in `config/profiles.sh` — backlog row [14]'s proposal, and
this spec's original thesis. It was designed, survived three review rounds, and was removed
on the accounting. See Out of scope; the reasoning is kept because the next reader will
re-derive the row.

**Why the sections below open on bash 3.2 anyway:** that is where the investigation started
and it is what falsified the row. The material is history and boundary-setting, not the
justification for what ships. The gap that ships is stated under "What is actually wrong".

## Origin — backlog row [14], and what measuring it changed

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

## What is actually wrong

**`lib/detect_env.sh:23` discards a failure.** It is a bare `source` whose exit status is
never read. `shell.md`'s return-code propagation rule requires `|| return 1` at every level
of a call chain, and the zsh twin already complies:

```zsh
# config/profiles.zsh:41
if ! source "${${(%):-%x}:A:h}/profiles.sh"; then
  print -u2 "config/profiles.zsh: failed to source … -- PROFILE will default to 'unknown' …"
fi
```

The bash side has no equivalent. The gap fires on a **missing**, **unreadable**, or
**malformed** `profiles.sh`, and on a wrong bash version — the general case, of which bash
3.2 is one instance.

**The consequence lands on the provisioning path, not the diagnostic one.** `run_doctor`
already reports correctly today (`[FAIL] PROFILE: unmapped hostname`, exit 1) because
`detect_env.sh:31` unconditionally assigns `PROFILE` after the failed source. What has no
such backstop is `-t setup`, `-t update`, `-t developer`: those continue with
`PROFILE=unknown` and zero `HAS_*`, and go on to install packages and create symlinks keyed
on exactly those values. That is where a broken identity table silently provisions a
machine as a capability-less host.

## Design

Three changes, one production concern. Files touched, so the scope is a statement rather
than an inference:

| file | change |
| --- | --- |
| `lib/detect_env.sh` | propagate the `source` failure at `:23`; set a `_PROFILES_LOADED` sentinel |
| `setup_env.sh` | read `detect_env`'s status at `:61` |
| `lib/helpers.sh` | `_doctor_check_profile` branches on the sentinel |
| `tests/setup_env/*.bats` | the cases below, plus repair of two existing tests §3 breaks |
| `docs/superpowers/README.md` | rewrite backlog row [14]; add two new rows |

**A bash-version guard in `config/profiles.sh` was designed, reviewed across three rounds,
and cut.** The reasoning is in Out of scope — it is the most useful part of this spec's
history and is kept rather than deleted.

### 1. `lib/detect_env.sh:23` — propagate the failure

```bash
_PROFILES_LOADED=0
if ! source "$(dirname "${BASH_SOURCE[0]}")/../config/profiles.sh"; then
  printf "lib/detect_env.sh: failed to source config/profiles.sh -- PROFILE would be 'unknown', no HAS_* capability set, and no legacy identity variable set. Refusing to continue.\n" >&2
  return 1
fi
_PROFILES_LOADED=1
```

**This is deliberately stricter than the zsh twin, and the asymmetry is justified by actor,
not drift.** `config/profiles.zsh:29-40` documents its choice to warn and continue: that
file is sourced by `.zprofile` at login, and aborting a login shell over a degraded lookup
is worse than the problem. That reason does not transfer. `lib/detect_env.sh` is sourced by
exactly one thing — `setup_env.sh`, which provisions the machine.

The change carries a comment saying so, sited next to the existing `readonly`-here /
`export`-there note at `detect_env.sh:44`, which is the same shape of deliberate bash/zsh
asymmetry and is the comment a future reader will find first.

**`_PROFILES_LOADED` exists for §3 and its safety property is not the obvious one.** The
tempting justification — "it is never `export`ed, so it cannot arrive from a parent" — is
false, and was measured:

```
env _PROFILES_LOADED=1 PROFILE=mac_workstation <the §3 branch>   ->  [PASS] PROFILE (mac_workstation)
```

An environment-supplied value defeats the read. What actually protects it is the
**unconditional `_PROFILES_LOADED=0` on entry to `detect_env`**, combined with `detect_env`
always running before `run_doctor` (`setup_env.sh:61` then `:69`). Anyone who makes that
`=0` conditional reopens the hole, which is why the reason is recorded here rather than
left to inference.

No test seam is added for the path. An earlier revision proposed `_OVERRIDE_PROFILES_SH` on
the grounds that testing the unreadable branch otherwise requires `chmod 000` on the tracked
`config/profiles.sh` — whose failing path would leave that file unreadable and break every
subsequent login shell on the machine (`tdd.md` E2). The hazard is real; the seam is not the
remedy. `$(dirname "${BASH_SOURCE[0]}")/../config/profiles.sh` resolves relative to the
*copy* of `detect_env.sh`, so a fixture directory reaches the branch with no product change
at all. Measured:

```
cp lib/detect_env.sh $F/lib/; cp config/profiles.sh $F/config/; chmod 000 $F/config/profiles.sh
bash -c "source $F/lib/detect_env.sh; detect_env"
  -> $F/lib/detect_env.sh: line 23: $F/lib/../config/profiles.sh: Permission denied
  -> tracked config/profiles.sh still -rw-r--r--
```

### 2. `setup_env.sh:61` — read the return value

Without this, `detect_env`'s `return 1` changes no decision — `:61` calls it bare.

```bash
if ! detect_env && [[ -z ${DOCTOR:-} && -z ${CHECK_VERSIONS:-} ]]; then
  exit 1
fi
```

`DOCTOR` and `CHECK_VERSIONS` are readonly globals set by `process_args`
(`lib/helpers.sh:641`) at `:59`, so both are readable at `:61`; their dispatch sites are
`:69` and `:70`. Verified across argv shapes: `!` binds to the pipeline only, `detect_env`
runs exactly once, and `getopts ":ht:w"` routes every malformed `-t` through `usage; exit`.

**Why those two continue rather than abort.** Both are read-only reporters and both already
bypass the Homebrew prerequisite at `:12` for the same reason — they must run on a broken
machine. Aborting before `run_doctor` would remove the diagnostic's ability to report this
class and take the other checks down with it. `behavior.md`: under pressure, surface more.

`--brew-install` is deliberately absent from this carve-out: it is a flag on `-t setup`,
which genuinely needs the identity table.

Change 2's premise was checked and holds: `MACOS`, `LINUX`, `UBUNTU`, `NOBLE` and
`RESOLUTE` are all assigned at `detect_env.sh:6-19`, above the `:23` return, so the
surviving doctor checks (`helpers.sh:463,471,494,619`) still work. Only `PROFILE`, `HAS_*`,
the legacy variable and `CHRUBY_LOC` are lost.

### 3. `lib/helpers.sh` — repair the regression §1 introduces in `doctor`

**This is not a bonus fix of a pre-existing defect. It is mandatory repair of a regression
this diff creates**, and the distinction matters because the earlier framing invited a
future reader to strip it as scope creep.

Today `_doctor_check_profile` (`lib/helpers.sh:397-410`) tests `${PROFILE:-unknown}`.
`config/profiles.zsh:46` exports `PROFILE`, so that value is inherited — but
`detect_env.sh:31` unconditionally overwrites it after the failed source, so master reports
this process's answer. Measured on an unmodified tree, `PROFILE=mac_workstation` exported,
`config/profiles.sh` unreadable:

```
  PROFILE=unknown
  [FAIL] PROFILE: unmapped hostname 'studio' — add a row to config/profiles.sh
  24 checks passed, 4 failed, 0 warnings          exit 1
```

Wrong *message*, correct verdict and exit code.

Change 1's early return at `:23` skips `:31`. The inherited `mac_workstation` then survives
and doctor reports:

```
  [PASS] PROFILE (mac_workstation)
```

A PASS over a machine whose identity table never loaded — introduced here. `[[ -z ${PROFILE+x} ]]`
does not fix it: `PROFILE` is *set*, just stale. The fix is to branch on the sentinel:

```bash
if [[ "${_PROFILES_LOADED:-0}" != 1 ]]; then
  doctor_fail "PROFILE" "config/profiles.sh did not load this run — any PROFILE value shown above came from the parent shell, not from this process. Check the file exists and is readable: ls -l config/profiles.sh"
elif [[ "${PROFILE:-unknown}" == "unknown" ]]; then
  doctor_fail "PROFILE" "unmapped hostname '$(hostname -s)' — add a row to config/profiles.sh"
else
  doctor_pass "PROFILE (${PROFILE})"
fi
```

Verified to discriminate in the operator actor — same tree, same unreadable file, same
inherited `PROFILE=mac_workstation`:

```
  [FAIL] PROFILE: config/profiles.sh did not load this run -- any PROFILE shown above came from the parent shell
```

**Net operator-visible delta on the doctor path is one message string.** Master and this
change set both produce `24 checks passed, 4 failed, 0 warnings` and the same exit code.
That is the honest accounting: §3 keeps doctor correct, it does not make it more correct.
The value of this spec is on the provisioning path, per the Problem section.

**Two prior review claims, both rejected on measurement, recorded rather than dropped.** A
lens claimed `lib/helpers.sh:710`'s `[[ -n ${HAS_DEVTOOLS} ]]` block would silently skip —
it would not: that line is in `run_setup_user`'s symlink section, not `run_doctor`, and sits
inside a `[[ -n ${LINUX} ]]` branch. A second claimed the doctor false-PASS was pre-existing
on master; its control had been run with changes 1-2 already applied, and true master fails
as shown above. Both are plausible on their face and will be re-derived by the next reader.

`run_doctor`'s environment dump printing `CHRUBY_LOC=<unset>` (`helpers.sh:378`) is accurate
output and is left alone.

## Testing

One group. It runs everywhere including CI, because nothing here is version-specific — that
was the point of cutting the guard.

### Harness: never `env -i`, and the reason is not the obvious one

`config/profiles.zsh` exports `PROFILE`, `STUDIO` and seven `HAS_*` into every child of a
login shell, including `bats` under the pre-push hook, so a value assertion that does not
clear them reads the parent's environment rather than the code's output. Two revisions of
this section reached for `env -i` to do that, and both were wrong.

**`env -i bash` resolves bash 3.2 on a mac.** `env -i` clears `PATH` too, and `env` execs
through the *new* environment, so the lookup falls back to the confstr default. Measured on
the Studio:

```
env -i bash -c 'echo $BASH $BASH_VERSION; echo $PATH'
  /bin/bash 3.2.57(1)-release
  /usr/gnu/bin:/usr/local/bin:/bin:/usr/bin:.

command -v bash  ->  /opt/homebrew/bin/bash   5.3.15
```

That reintroduces, as the *test actor*, the exact bash-3.2 class this spec declared
unreachable and moved to Out of scope. A previous revision split the rule by
source-versus-execute on the theory that only the executing cases were exposed; the
discriminator is **which bash binary runs**, and it applies to both.

`env -i` also drops `tests/mocks` from `PATH`, which is where this repo's hostname control
lives. `tests/setup_env/profiles.bats:50-53` is the established mechanism and every case
below follows it:

```bash
unset "${!HAS_@}"
export MOCK_HOSTNAME_OUTPUT='studio'
export MOCK_UNAME_S='Darwin'
export PATH="${REPO_ROOT}/tests/mocks:${PATH}"
```

**The rule for every case: clear the inherited identity names explicitly, keep a `PATH` that
resolves bash 5 and reaches `tests/mocks`, and pin the hostname through
`MOCK_HOSTNAME_OUTPUT`.** Without the mock, a value assertion on `PROFILE` is host-specific
and `ubuntu-latest` resolves `unknown`.

### Cases

| # | case | fails when |
| --- | --- | --- |
| T1 | `detect_env` against a fixture-dir `profiles.sh` that is unreadable | rc is not **1** specifically, or stderr does not contain the exact string `Refusing to continue` — not merely "names `config/profiles.sh`", which a bash-3.2 run also satisfies with a *readable* fixture |
| T2 | `detect_env` normal, `MOCK_HOSTNAME_OUTPUT=studio` | `PROFILE` is not `mac_workstation`, `STUDIO` is not `1`, or `_PROFILES_LOADED` is not `1` |
| T3 | `setup_env.sh -t update` against a fixture tree whose `profiles.sh` is unreadable | it does not exit 1, **or** stderr lacks `Refusing to continue`, **or** a workflow marker file exists. All three arms are required — see the hazard note below |
| T4 | same, `-t doctor` | `run_doctor` is not reached |
| T5 | **the regression pin** — `PROFILE=mac_workstation` left set, fixture `profiles.sh` unreadable, `run_doctor` | doctor reports PASS for PROFILE. Fails with change 1 alone; passes only with §3 |
| T6 | `_doctor_check_profile` across all three states — loaded + mapped, loaded + unmapped, not loaded | any two of the three produce the same verdict/message pair |
| T7 | **negative control on the sentinel read** — `_PROFILES_LOADED=1` supplied in the environment, `detect_env` **not** called | the function is undefined or produces no output (assert a non-empty `[PASS]` line, not merely "no FAIL"), or it reports FAIL. It must report PASS, pinning that the environment *can* defeat the read — so the protection is `detect_env`'s unconditional `=0`, not non-export. If this starts failing, someone changed the mechanism and §1's recorded reasoning is stale |

**T1's assertion on `_PROFILES_LOADED` is deliberately omitted.** Asserting it is `0` cannot
discriminate "`detect_env` ran and failed" from "`detect_env` was never reached", because the
`${_PROFILES_LOADED:-0}` read production uses returns `0` for a never-assigned variable too.
rc **1** and the stderr string carry that case.

**T3 and T4 must not be able to run a real workflow, and T3's exit code alone proves
nothing.** `run_update` calls `brew_update` and `sudo -H softwareupdate --install --all`
(`lib/workflows.sh:325-334`) before the git-repos sync, so on the day change 2 regresses a
naive T3 performs a machine-wide update — `tdd.md` E2, an armed destructive failing path.
Two constraints follow. The `PATH` must carry `tests/mocks` (which supplies `brew`, `sudo`,
`softwareupdate` and `git`) so the regressed path is inert rather than real. And `exit 1` is
**not** a discriminating oracle on its own: `setup_env.sh:20` (bash < 5) and `:30` (no brew)
both produce exit 1 too, so a mac resolving 3.2 or a `PATH` without `brew` makes T3 pass
against unmodified master. Assert the stderr string and the absence of a workflow marker
alongside the code.

### Two existing tests break, and only one of the two repairs is safe

Measured on a patched copy, `bats tests/setup_env/unit.bats`:

```
not ok 118 _doctor_check_profile passes for a mapped profile
not ok 119 _doctor_check_profile fails for an unmapped profile and names the hostname
ok  120 run_doctor exit code reflects an unmapped profile
```

`load_setup_env()` (`tests/helpers/common.bash:38`) sources `setup_env.sh`, whose sourcing
guard at `:56` returns before `:61`, so `detect_env` never runs and all `run_doctor` /
`_doctor_check_profile` call sites read an unset sentinel. Test 120 is the worse case: it
still passes, through the sentinel branch rather than the branch its name describes, and
must be re-pointed.

Two repairs suggest themselves and **they are not interchangeable**:

- **Set `_PROFILES_LOADED=1` at function scope in the affected tests.** Correct.
- **Call `detect_env`.** Wrong. `detect_env.sh:31` assigns `PROFILE` unconditionally, and
  `PROFILE` is the exact variable tests 118 and 119 control. Calling it clobbers the fixture.
- **Export `_PROFILES_LOADED=1` from `load_setup_env`.** Also wrong, and worse: it makes the
  sentinel environment-supplied in precisely the suite meant to guard against an
  environment-supplied oracle, rebuilding the defect §3 exists to remove.

## Verification

Run before claiming done, with output recorded:

```bash
make lint
make test
# regression pin, from a normal terminal shell (PROFILE inherited):
PROFILE=mac_workstation ./setup_env.sh -t doctor      # after breaking a fixture table
```

## Out of scope, and why — including one design that was cut

**The bash-version guard in `config/profiles.sh`.** Backlog row [14] proposed it; it was
designed, survived three review rounds, and was cut on the accounting rather than on a
defect. The reasoning is worth keeping because the next reader will re-derive the row.

The degradation it targets is real and is measured in the Origin section above. Change 1
above already fails closed on it, because `source config/profiles.sh` returns 2
under bash 3.2 today. The guard's remaining value was that **the 2 is positional, not
structural** — the file's last statement is the failing `PROFILE_LEGACY` `declare -A` at
`:55`. Measured, two copies of the real file differing only by a trailing `printf ''`:

```
plain     rc=2
appended  rc=0        MAP[studio]=[wsl2_workstation]
```

One appended line and change 1 goes blind while reporting success. Real, and the class has
an observed instance: `21671b8` did append a new top-level statement after what was then the
file's last. But that statement was itself a `declare -A`, which fails under 3.2 and
therefore *preserves* the rc=2. **Zero adverse observed instances**, against a cost of a
fourth production file and six of fourteen test cases, all macOS-only or mutation-only, for
a path no entry point reaches — `setup_env.sh:20` has guarded bash 5 since `3d2e0a6`
(2026-04-01). Filed as a backlog row instead.

**`declare -g` at `detect_env.sh:33`.** Invalid under bash 3.2, unreachable through the
guarded entry point, and now unreachable through change 1 as well.

**`setup_env.sh:20`'s entry-point guard.** It works, and it is what falsified backlog row
[14].

**`config/profiles.zsh`'s warn-and-continue semantics.** Deliberate, documented at `:29-40`,
correct for a login shell.

## Backlog

Row [14] is rewritten rather than deleted, to record that its reachability claim was false
at the time of filing. Two rows are added: the positional-rc fragility above, and the
observation that `-t doctor` cannot run over `ssh` to a mac at all today — `/usr/bin/env bash`
resolves 3.2 under sshd's `_PATH_STDPATH` and `setup_env.sh:20` exits first, which is
pre-existing and unrelated to this change.


---

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
which is falsifiable today and is pinned by Group B case 4. Change 1 still ships, on the
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

---

## Multi-Lens Review — Round 2

Reviewed at commit: `3149022`. Round 1 is above; its dispositions were all **Addressed**,
and because the revision changed design substance — a fourth production file, a replaced
justification, a rewritten test suite — all three lenses re-ran on the revised text rather
than only the lens that raised each finding.

All three converged on one defect, and it was introduced by round 1's own correction.

### Goal-Fit

Finding: §4 fails the reads-it test — both its branches call `doctor_fail`, so the verdict
and exit code are identical and only the message differs, and `run_doctor` persists
nothing. Worse, its discriminator is falsified in the real actor: `config/profiles.zsh:46`
exports `PROFILE`, so `[[ -z ${PROFILE+x} ]]` is false wherever an operator types the
command and §4 falls through to `doctor_pass`. Separately: change 1 defends change 2's
signal in a state the spec itself established is unreachable, and generates 6 of 13 test
cases — half the test surface, all macOS-only or mutation-only — for the least-reachable
third of the value. And spec:204 rested change 1's whole justification on "Group A case 7",
which commit `3149022` had moved to B4 without updating the reference.

Assumption: That no machine-local `config/local.sh`, launchd job or cron entry on the four
macs **other than the Studio** sources `config/profiles.sh` or `lib/detect_env.sh` outside
`setup_env.sh` — only the Studio was measured.

Disposition: **Addressed**, except the drop-change-1 recommendation which is **Accepted,
reason: the operator confirmed the scope call after the fragility argument was reproduced
independently by all three lenses.** §4 was rebuilt on a `_PROFILES_LOADED` sentinel that
`detect_env` sets and never exports, which changes a real verdict, is falsifiable in every
actor, and additionally fixes a pre-existing defect (see Risk). The dangling reference is
fixed. The Studio-only caveat stands and is stated in the Boundaries section; the four
remote macs were not measured and this spec does not claim they were.

### Ergonomics

Finding: Same defect, reached independently — §4's branch is unreachable in the operator's
normal invocation path and the failure it exists to report renders as PASS there.
Additionally: round 1's `env i` fix was **relocated, not applied** — Group B carried the
rule and Group A did not, while A4 asserted `PROFILE` is `mac_workstation` and `STUDIO` is
`1`, both exported into bats before the test runs, so A4 passed if `detect_env` did nothing
at all. A3's `chmod 000` on the tracked file is a `tdd.md` E2 destructive failure branch —
its failing path breaks every subsequent login shell on the machine — and there is no seam
to avoid it. §4's remedy text named no command and one third of it ("check this shell is
bash 5+") is unreachable, since `setup_env.sh:20-28` exits before `-t doctor` dispatches.
C2's mutation is a string substitution that would silently stop mutating if the guard is
reformatted.

Assumption: That the operator only invokes `-t doctor` from a shell that has already
exported `PROFILE`, making §4's unset branch dead code.

Disposition: **Addressed**, and the assumption was **settled by the operator: terminal
only.** That makes the unset branch dead in 100% of real runs rather than merely most,
which is why §4 was rebuilt on a sentinel instead of patched. The `env -i` rule is now
stated once for all three groups rather than per-group. `_OVERRIDE_PROFILES_SH` was added
to change 2 so A3 never touches the tracked file. The remedy text now names `ls -l` and
drops the unreachable bash-5 clause. C2 gained a second arm asserting the edit actually
changed the fixture.

### Risk

Finding: Same defect, with the strongest evidence — applied all four changes to a scratch
copy, made `config/profiles.sh` unreadable, and ran `./setup_env.sh -t doctor` from a
terminal-descended shell, getting `[PASS] PROFILE (mac_workstation)` over a machine whose
identity table never loaded, plus `_DOCTOR_FAILED=0`. Re-ran against the **unmodified**
`${PROFILE:-unknown}` check and got the same `[PASS]` — establishing that this is
pre-existing behaviour on master, not a regression, and that `${PROFILE+x}` does not change
it. Also: B2's three conditions are satisfiable by a wrong fixture path (a failed source
makes `detect_env` an unknown command, rc 127). Verified and **not** raising: change 3's
premise holds (`MACOS`/`LINUX`/`UBUNTU`/`NOBLE`/`RESOLUTE` are all assigned above the `:23`
return, so the surviving doctor checks still work); the guard's placement does not displace
the file-wide `SC2034` directive; `_OVERRIDE_BASH_MAJOR` reuse is safe; and round 1's
rejection of the `helpers.sh:710` claim is correct.

Assumption: That `run_doctor` observes `detect_env`'s output rather than the ambient
environment. It does not.

Disposition: **Addressed.** The assumption was refuted by the lens's own measurement and is
now the design's premise rather than an open question: §4 branches on `_PROFILES_LOADED`,
which `detect_env` assigns and never exports. Verified to discriminate in the operator
actor — same scratch copy, same unreadable file, same inherited `PROFILE=mac_workstation`,
`[FAIL]` with the correct cause where both master and `${PROFILE+x}` return `[PASS]`. B2
now asserts rc **1** specifically and checks the sentinel. One framing correction recorded
in §4: "converts a loud misdiagnosis into a silent PASS" overstates it — the lens's own
data shows the unmodified check also passes silently there, so `${PROFILE+x}` is *inert* in
that actor, not worse.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison, no evaluator/judge component, and its acceptance criteria
are concrete commands with stated expected output.

---

## Multi-Lens Review — Round 3 (scoped)

Reviewed at commit: `c98a4f2`. Scoped to the sections the round-2 revision rewrote — the
`_PROFILES_LOADED` sentinel, the `_OVERRIDE_PROFILES_SH` seam, the rebuilt §4, and the
rewritten Testing section. Two lenses rather than three: the Problem, Boundaries, the
backlog-row falsification and the propagation/carve-out design were unchanged and had been
independently reproduced by six prior passes.

Both lenses found defects, and four of the five were introduced by round 2's own correction.
That is three consecutive rounds in which the fix carried its own defect, which is the
argument against budgeting review rounds on an assumption of decaying yield.

### Goal-Fit

Finding: §4's headline claim was false. The spec asserted `_doctor_check_profile` reports
the login shell's answer "on every run today on master" and that master therefore PASSes
over a broken table. Reproduced on a true unmodified tree, `PROFILE=mac_workstation`
exported, `config/profiles.sh` unreadable: master returns `[FAIL] PROFILE: unmapped hostname
'studio'`, exit 1 — because `detect_env.sh:31` unconditionally overwrites the inherited
export. The `[PASS]` appears only once change 1's early return skips that assignment. Round
2's Risk lens had run its "unmodified check" control with changes 1-2 still applied — the
wrong baseline, and the third consecutive round in which a control was derived from the
state under test. Consequences: §4 is mandatory repair of a regression this diff introduces,
not a courtesy fix, so the Surgical-Changes question resolves the opposite way to how the
spec framed it. `_OVERRIDE_PROFILES_SH` fails the reads-it test — a fixture directory
reaches the unreadable branch with no product change, since the relative path resolves
against the copied `detect_env.sh`. And the net operator-visible delta on the doctor path is
one message string, while the real value sits on the provisioning path.

Assumption: That a future append to `config/profiles.sh` will be a statement that *succeeds*
under bash 3.2 — the guard's sole surviving justification. Refute or confirm by classifying
every historical commit that appended a top-level statement after the file's then-last
declaration.

Disposition: **Addressed.** Every claim was independently re-verified before acting on it,
given the control problem it identified. True master fails, exit 1 — confirmed. The seam is
unnecessary — confirmed, tracked file untouched. The assumption was settled and cuts against
the guard: the one historical instance (`21671b8`, `PROFILE_LEGACY`) is itself a `declare -A`
that fails under 3.2 and therefore *preserves* the rc=2, so the class has an observed rate of
one and **zero adverse instances**. On that basis the operator narrowed the scope: the guard
and its six test cases are cut, `_OVERRIDE_PROFILES_SH` is removed, and §4 is reframed as
regression repair. The one-message-string accounting is now stated in §3 rather than implied.

### Risk

Finding: The §4 measurement reproduces and the sentinel is sound — correct scope and
lifetime, survives the return, resets on a second `detect_env` call, coverage stays at
91.18% above the floor, and `--brew-install`'s absence from the carve-out is correct. Four
defects: (1) **two existing tests go red and the spec never budgets for them** —
`unit.bats` 118 and 119 fail because `load_setup_env()` sources `setup_env.sh`, whose
sourcing guard returns before `:61`, so `detect_env` never runs and all 22 doctor call sites
read an unset sentinel; test 120 still passes but via the sentinel branch rather than the
branch it names. (2) The spec stated the **wrong safety mechanism** — "never `export`ed" is
false, since an environment-supplied `_PROFILES_LOADED=1` defeats the read; what protects it
is the unconditional `=0` on entry plus `detect_env` always preceding `run_doctor`. (3) The
blanket `env -i` rule **breaks three cases**: `setup_env.sh` is `#!/usr/bin/env bash`, so
under `env -i PATH=/usr/bin:/bin` a mac resolves bash 3.2 and the pre-existing guard exits
first — A5 passed against master, A6 and A7 were unconstructible. (4) A3's sentinel
assertion was latently vacuous, since `${_PROFILES_LOADED:-0}` returns `0` for a
never-assigned variable.

Assumption: That `-t doctor` is only ever invoked from a profile-sourcing shell. Round 2
recorded this as settled by the operator, but that is a statement about habit, not a property
of the code.

Disposition: **Addressed**, assumption **Accepted with a backlog row.** All four defects were
independently reproduced before acting: `not ok 118` / `not ok 119` / `ok 120`, and
`env _PROFILES_LOADED=1 … -> [PASS]`. The Testing section now splits the harness by whether
a case sources a function (`env -i`) or executes `setup_env.sh` (`env -u`, bash 5 on PATH),
the existing-test breakage is budgeted with the note that the obvious repair — exporting the
sentinel from `load_setup_env` — would rebuild the very defect §3 removes, the safety
mechanism is stated correctly in §1, and T1 drops the non-discriminating sentinel assertion.
T7 was added as a negative control pinning that the environment *can* defeat the read, so the
recorded reasoning cannot go stale unnoticed. On the assumption: the lens is right that habit
is not a code property, and the answer is worse than either round assumed — `-t doctor` cannot
run over `ssh` to a mac at all today, because `/usr/bin/env bash` resolves 3.2 under sshd's
`_PATH_STDPATH` and `setup_env.sh:20` exits first. That is pre-existing and unrelated to this
diff, so it is filed as a backlog row rather than widened into it.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison, no evaluator/judge component, and its acceptance criteria are
concrete commands with stated expected output.

---

## Multi-Lens Review — Round 4 (scoped, one lens)

Reviewed at commit: `1824501`. One lens rather than three: the design had been unchanged
and independently reproduced since round 3, and the only substantially new text was the
Testing section and the Out-of-scope rationale for the cut guard.

### Risk

Finding: The narrowing left the Out-of-scope reasoning coherent — the rc=2 dependency only
has to hold on a path `setup_env.sh:20` already blocks, verified. The incoherence is one
section later: **the Testing harness resurrected bash 3.2 as the test actor, in exactly the
class the spec had just declared unreachable.** `env -i` clears `PATH`, and `env` execs
through the new environment, so bash resolves via the confstr default. Measured on the
Studio: `env -i bash -c 'echo $BASH $BASH_VERSION'` → `/bin/bash 3.2.57(1)-release` with
`PATH=/usr/gnu/bin:/usr/local/bin:/bin:/usr/bin:.`, against `command -v bash` =
`/opt/homebrew/bin/bash` 5.3.15. The previous revision split the rule by
source-versus-execute; the discriminator is which bash binary runs, and it applies to both.
Consequences: T2 red on every mac, and red on CI for a second reason — `env -i` also drops
`tests/mocks`, so a `PROFILE` assertion becomes host-specific and `ubuntu-latest` yields
`unknown`. T1 non-discriminating on macs, since a *readable* fixture under 3.2 also gives
rc=1 with the file named. T7 passes on nothing: its failure condition was "it reports FAIL",
which an empty result satisfies. T3 executes `setup_env.sh -t update` for real, and
`run_update` (`lib/workflows.sh:325-334`) runs `brew_update` then
`sudo -H softwareupdate --install --all` — so on the day change 2 regresses the test
performs a machine-wide update; and its expected `exit 1` is also what `setup_env.sh:20` and
`:30` produce, so a mac-3.2 or brew-less `PATH` makes it pass against master. The
existing-test diagnosis is correct, but the two prescribed repairs are not interchangeable:
"call `detect_env`" clobbers `PROFILE` at `detect_env.sh:31`, the exact variable tests 118
and 119 control, so only the function-scope assignment works. Verified and **not** raising:
`_PROFILES_LOADED`'s double-call and no-`detect_env` behaviour are sound; `run_doctor` is
reachable only from `setup_env.sh:69`, after `:61`; `CHRUBY_LOC` is read only by the dump at
`helpers.sh:378`, so the "one message string" delta claim survives.

Assumption: That the `PATH` each `env` invocation actually constructs resolves bash 5 and
reaches `tests/mocks`, and that the executing cases' expected `exit 1` is not what
`setup_env.sh:20`/`:30` produce. Settle by running the invocations verbatim on a mac and on
`ubuntu-latest` and checking `$BASH_VERSION`, `command -v hostname`, `command -v brew`.

Disposition: **Addressed.** Both headline claims were independently re-verified before
acting — `env -i bash` → 3.2.57 with the confstr `PATH`, and `run_update`'s
`brew_update`/`softwareupdate` calls. `env -i` is now prohibited outright and the section
states why, since the reason is non-obvious and two revisions reached for it. Every case
now clears the identity names explicitly, keeps a `PATH` resolving bash 5 and reaching
`tests/mocks`, and pins the hostname through `MOCK_HOSTNAME_OUTPUT` per the existing
mechanism at `tests/setup_env/profiles.bats:50-53`. T1 asserts the exact `Refusing to
continue` string rather than the filename. T3 gained a three-arm oracle and an explicit
hazard note. T7 asserts a non-empty `[PASS]`. The existing-test repair now names the one
safe option and both wrong ones with their mechanisms. The assumption is the correct
stopping point for spec review and is discharged in Phase 2 rather than in prose — see
below.

### Note on stopping

Four rounds, ten lens passes. The **design** — three production changes — has been stable
and independently reproduced since round 3; every round-4 finding was in the *test harness*.
That is the signal to stop reviewing prose: a harness defect costs one red test in Phase 2's
iterate-until-green loop, and reasoning about `PATH` construction in a document is a worse
instrument than running it. The remaining assumption above is answered by writing the tests,
not by another lens.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison, no evaluator/judge component, and its acceptance criteria are
concrete commands with stated expected output.

