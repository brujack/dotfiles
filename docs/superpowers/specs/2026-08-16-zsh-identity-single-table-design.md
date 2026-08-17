# Single Identity Table for bash, zsh, and .zprofile

**Date:** 2026-08-16
**Status:** Draft — pending review

## Context

This repo answers the question "which machine is this?" in four independent places:

| Source                        | Shell | Sets                                                                   |
| ----------------------------- | ----- | ---------------------------------------------------------------------- |
| `config/profiles.sh`          | bash  | `PROFILE_MAP` / `PROFILE_CAPS` — the profile/capability model          |
| `lib/detect_env.sh`           | bash  | `PROFILE`, `HAS_*`, plus a legacy alias block                          |
| `.config/.zshrc.d/1_init.zsh` | zsh   | `RATNA`/`LAPTOP`/`STUDIO`/`WORKSTATION`/`CRUNCHER`/`RECEPTION`/`HOMES` |
| `.zprofile`                   | zsh   | `LAPTOP`/`STUDIO`/`RECEPTION`/`OFFICE`/`HOMES`/`WORKSTATION`           |

They have drifted. This spec collapses them to one table with three consumers.

The work originates from two backlog rows in `docs/superpowers/README.md` — "bash and zsh
disagree on machine identity" and "keychain block repeats one 4-line group across 7 host
branches". Exploration found both to be symptoms of the same cause, plus a third defect
neither row anticipated that is more consequential than either.

### The framing in the backlog rows was backwards

Both rows read as "the zsh side never adopted the profile/capability model", implying zsh
is the half that is behind. Measurement says the opposite on the point that matters:
`.zprofile` and `1_init.zsh` both enumerate the wireless-interface hostnames, and
`config/profiles.sh` and `lib/detect_env.sh` do not. **zsh handles wireless; bash does
not.**

## Measurements

Every figure below was produced by running the command, on both development machines
(Mac Studio, macOS, bash 5.3.15 / zsh 5.9.2; Linux 7950X, Ubuntu, bash 5.2.21 / zsh 5.9).
Where a row was measured on one box only, that is stated.

### M1 — the `{OFFICE}` guard is a literal string, so it is always true

`.config/.zshrc.d/5_general.zsh:18` reads `[[ -n {OFFICE} ]]` — no `$`. zsh evaluates the
brace text as a literal non-empty string.

```
$ zsh -c 'if [[ -n {OFFICE} ]]; then print "brace=ALWAYS-TRUE"; else print "brace=false"; fi'
Studio       brace=ALWAYS-TRUE
workstation  brace=ALWAYS-TRUE
```

Consequence: `export FZF_BASE=/opt/homebrew/bin/fzf` runs on **every** host, including the
two Linux boxes and `ratna` (x86_64, Homebrew at `/usr/local`), where that path does not
exist.

### M2 — on a wireless hostname the bash side resolves to nothing

`hostname -s` returns `<name>-1` when the machine is on its wireless interface.
`PROFILE_MAP` and `detect_env.sh`'s legacy alias block both key on wired names only.

Measured on the Studio with a `hostname` mock and the ambient identity variables stripped
(`env -u STUDIO -u LAPTOP …`) — without that strip the caller's own exported `STUDIO=1`
leaks into the child and the legacy column reads as a false pass:

```
studio     PROFILE=mac_workstation  legacy=[STUDIO ] HAS_DEVTOOLS=[1] HAS_DOCKER=[1]
studio-1   PROFILE=unknown          legacy=[]        HAS_DEVTOOLS=[]  HAS_DOCKER=[]
laptop     PROFILE=personal_laptop  legacy=[LAPTOP ] HAS_DEVTOOLS=[1] HAS_DOCKER=[1]
laptop-1   PROFILE=unknown          legacy=[]        HAS_DEVTOOLS=[]  HAS_DOCKER=[]
home-1     PROFILE=mac_mini         legacy=[HOMES]   HAS_DEVTOOLS=[]  HAS_DOCKER=[]
```

Population note: measured on the Studio only. The lookup is a pure associative-array read
over data with no platform-dependent behaviour, so the result is a property of the table
rather than of the machine — but only the Studio was actually exercised.

Downstream effect: `HAS_*` gates the Brewfile drift check's `[HAS_*]`-tagged entries, the
`HAS_SNAP`/`HAS_FLATPAK` install branches in `lib/linux_ubuntu.sh`, and several `run_doctor`
checks. All of them degrade silently, because `unknown` is a well-formed profile that
simply has no capabilities. The laptop — the machine most likely to be on wireless — is the
worst-affected.

### M3 — zsh sources bash's `declare -A` table correctly

```
$ zsh -c 'source tbl.sh; print "a=$M[a]"; print "missing=<$M[nosuch]>"'
Studio       a=one   missing=<>
workstation  a=one   missing=<>
```

This is what makes one shared data file possible with no generation step and no drift gate.

### M4 — `${0:A:h}` resolves a symlink to its target directory

A `.zprofile` symlinked from `$HOME` into the repo can locate the repo with no hardcoded
path. Measured cross-directory (link and target in different directories, so the resolution
is actually exercised):

```
                target_dir                      resolved
workstation     /tmp/tmp.xmE…/repo              /tmp/tmp.xmE…/repo
Studio          /var/folders/…/tmp.VZn…/repo    /private/var/folders/…/tmp.VZn…/repo
```

### M5 — zsh does not word-split an unquoted expansion

```
$ s="gui devtools aws"; for c in $s;    do print -n "[$c]"; done   ->  [gui devtools aws]
$ s="gui devtools aws"; for c in ${=s}; do print -n "[$c]"; done   ->  [gui][devtools][aws]
```

Identical on both boxes. `SH_WORD_SPLIT` is off by default in zsh (already recorded in
`CLAUDE.md`). So the **data** can be shared but the **derivation loop** cannot —
`detect_env.sh`'s `for cap in ${PROFILE_CAPS[...]}` splits under bash and does not under
zsh.

## Defects found

| #   | Defect                                                                                                                             | Status                 |
| --- | ---------------------------------------------------------------------------------------------------------------------------------- | ---------------------- |
| B1  | `5_general.zsh:18` `{OFFICE}` missing `$` — always true (M1)                                                                       | needs a targeted fix   |
| B2  | `.zprofile:10-11` matches `homes`/`homes-1`; the other three tables match `home-1`. Disjoint — no hostname satisfies both          | closed by construction |
| B3  | `.zprofile:21` reads `CRUNCHER`; `.zprofile` never sets it, so the rbenv guard there is `WORKSTATION`-only in effect               | closed by construction |
| B4  | `.zprofile:12` and `:13` are identical (`workstation` twice) — one dead line                                                       | closed by construction |
| B5  | `1_init.zsh` never sets `OFFICE`, yet five zsh sites read it. Survives only via `.zprofile`'s export leaking into children         | closed by construction |
| B6  | `1_init.zsh` sets `RATNA`/`WORKSTATION`/`CRUNCHER` which `detect_env.sh` does not; `detect_env.sh` sets `OFFICE` which it does not | closed by construction |
| B7  | `ratna` is absent from `PROFILE_MAP` entirely → `PROFILE=unknown`, zero `HAS_*` on that box                                        | closed by construction |
| B8  | keychain block: 7 host arms, six of them byte-identical                                                                            | collapsed by this work |
| B9  | `2_functions.zsh` `Make()` hardcodes gmake paths per hostname, duplicating `6_path.zsh`'s gnubin prepend                           | out of scope — backlog |
| B10 | On a wireless hostname the bash side resolves `PROFILE=unknown` and zero `HAS_*` (M2)                                              | closed by construction |

### The existing test suite confirms B10 rather than catching it

`tests/setup_env/profiles.bats` has 20 tests. Every one uses a wired hostname, and the test
at line 46 asserts `PROFILE=unknown` for an unrecognised hostname — which `studio-1`
satisfies. The suite was derived from the same wired-only table it tests, so it agrees with
the table by construction and cannot falsify it. This is `behavior.md`'s "a check derived
from the same decision as the thing it checks cannot falsify it", exactly.

## Decision

**One table, legacy variable names derived from it, three consumers.**

The alternative considered was normalisation — strip a trailing `-1` before lookup, keeping
the table at seven rows. It was rejected: `home-1` is a machine name rather than a wireless
suffix, so normalisation needs a carve-out, and a carve-out inside a normaliser is the
loose-allow-path shape `USER.md` names. It becomes clean only if that box is renamed, which
is an operator action on hardware. Enumerating pairs is data rather than logic, cannot
misfire, and costs seven extra rows.

A third option — fix the defects in place and leave four tables standing — was rejected
because four tables is the mechanism that produced all ten defects.

### The table

`config/profiles.sh` remains the single source:

```bash
declare -A PROFILE_MAP=(
  [laptop]="personal_laptop"      [laptop-1]="personal_laptop"
  [studio]="mac_workstation"      [studio-1]="mac_workstation"
  [reception]="mac_workstation"   [reception-1]="mac_workstation"
  [ratna]="mac_workstation"       [ratna-1]="mac_workstation"
  [office]="mac_mini"             [office-1]="mac_mini"
  [home-1]="mac_mini"
  [workstation]="linux_workstation"
  [cruncher]="wsl2_workstation"
)
```

Notes carried as comments in the file itself, because none is inferable from the data:

- A `-1` suffix is the machine's **wireless interface** hostname. `workstation` and
  `cruncher` are wired-only and so have no pair. `home-1` is the exception — there the `-1`
  is part of the machine name, a naming mistake retained because a `home-2` may follow.
- `reception` carries `mac_workstation` rather than `mac_mini` despite being the same class
  of hardware as `office` and `home-1`. It was a full-time dev box at work and still has
  the toolchain installed; the work moved to remote SSH but the capabilities did not.
- `ratna` carries `mac_workstation` because it was a full-time home dev box for years and
  is now a server-room terminal that keeps the full toolchain deliberately.

`PROFILE_CAPS` loses its `[server]` entry — that profile belonged to a retired mac mini and
no hostname has mapped to it since. This closes the standing backlog row
"`PROFILE_CAPS[server]` has no hostname mapping" as retired-not-broken.

`personal_laptop` and `mac_workstation` carry identical capability sets. That is recorded
as an observation, not changed here — collapsing them is a separate decision about whether
the model wants the distinction.

### Consumers

```
config/profiles.sh          data only, no logic
   |
   +-- lib/detect_env.sh          bash   mechanism unchanged, reads the fuller table
   +-- config/profiles.zsh        zsh    derivation: source table, set HAS_*, set legacy vars
          |
          +-- .zprofile                  login shells
          +-- .zshrc.d/1_init.zsh        interactive shells
```

`config/profiles.zsh` is the only new file. It exists because M5 makes the derivation loop
shell-specific while M3 makes the data shareable — so the split is data in `.sh`, derivation
in `.zsh`, rather than two copies of either. It locates the table with `${0:A:h}` (M4) and
must be re-source safe, using `export` rather than `readonly`; `1_init.zsh` already carries
a `${NOBLE+x}` guard for precisely this reason.

The legacy variables become **derived outputs** of the table rather than independent
hostname tests. Every existing read site keeps working unchanged. That is what keeps the
diff proportionate.

Deleted: the nine hostname lines in `1_init.zsh`, the twelve in `.zprofile`, and the
five-entry legacy alias block in `detect_env.sh` (five assignments plus their five
`shellcheck disable` comments, ten lines).

### Most read sites are not identity tests at all

Enumerating and classifying every hostname read site — 19 across four files — was the
correction this spec's self-review produced. The draft said "roughly twenty read sites keep
working unchanged" and left it there, which is true and misses the point:

| What the guard actually expresses                           | Sites | Where                                                                |
| ----------------------------------------------------------- | ----: | -------------------------------------------------------------------- |
| Homebrew prefix — ARM `/opt/homebrew` vs Intel `/usr/local` |     9 | `2_functions:8,12` · `5_general:6,9,18,111,115,191` · `.zprofile:17` |
| "a Linux dev box" — a capability                            |     2 | `5_general:57` · `.zprofile:21`                                      |
| "any known host" — a capability                             |     1 | `7_final:60`                                                         |
| keychain per-host arms                                      |     7 | `5_general:201–241` (B8)                                             |

**Nine of nineteen sites do not need identity.** They are asking which Homebrew prefix this
machine has, and answering it by hostname — which is why `ratna` needs a named branch in
five separate places and why adding an Intel mac would mean editing all of them. The single
table fixes who-am-I; it does not by itself remove the sites that should never have asked.

Converting all nine is not proportionate to this change, so four are in scope and five are
not — the split is by behavioural risk, not by tidiness:

**In scope** — `5_general:6`, `:9`, `:18`, `:191`. The first three are the `CHRUBY_LOC` and
`FZF_BASE` block (lines 5–11 and 18), which collapse to a prefix test with **no hostname at
all**, `RATNA` branch included. The fourth is the keychain binary path, which sits inside the
B8 block being rewritten anyway.

**Out of scope** — `2_functions:8,12` (B9; removing it means relying on `PATH`, and
`CLAUDE.md` documents a live case where a `PATH` prepend inside a hook shadows the test
suite's own `make` mock). `5_general:111,115` (gcloud completion: the ARM arm lists only
`LAPTOP||STUDIO`, so converting it to a prefix test would newly enable completion on
`reception`, `office` and `home-1` — probably correct, definitely a behaviour change on three
machines, and not what this spec is for). `.zprofile:17` (a login-shell `PATH` prepend; its
current five-mac list is correct and it keeps working as a derived-variable read).

### B1 is more than a missing `$`

Lines 5–11 and 18 of `5_general.zsh` enumerate hostnames to express _"an ARM mac"_ — the
`RATNA` arm for the Intel prefix, a five-host list for the ARM one, once for `CHRUBY_LOC` and
once for `FZF_BASE`. Both become:

```zsh
if [[ -d /opt/homebrew ]]; then   # ARM
elif [[ -d /usr/local/opt ]]; then # Intel
fi
```

This deletes the typo rather than patching it, and corrects what the typo was masking:
`FZF_BASE` currently points at an ARM Homebrew path on `ratna` and both Linux boxes. That is
a real behaviour change on three machines. It is the correct behaviour — the path does not
exist there — but it is a change, not a no-op, and line 21's `[ -f ~/.fzf.zsh ] && source`
fallback is what those machines will rely on instead.

### B8 — keychain collapse

Six of the seven mac arms are byte-identical (`id_rsa`, `home`, `github`, `gitlab`, plus
commented-out entries). The Linux split is workstation/cruncher (the same four keys) versus
everything else (`id_rsa` only) — which is "a known profile or not", now expressible.

`home-1`'s arm is the sole outlier: `keychain --eval any home` rather than `--eval home`.
`any` is not a keychain flag, so it is read as a key name. **This spec treats it as a typo
and drops it**, making all six mac arms identical. See Assumptions.

The binary-path selection above the arms (line 191, `RATNA` → `/usr/local/bin/keychain`,
otherwise `/opt/homebrew/bin/keychain`) is one of the nine prefix-tests-in-disguise and
becomes a prefix test here, since the block is being rewritten regardless.
`_OVERRIDE_KEYCHAIN_BIN` and the `[[ -o interactive ]]` guard are both preserved exactly —
`shell.md` records why the seam exists (an absolute-path default silently defeats a `PATH`
mock), and `CLAUDE.md` records that the interactive guard is what stopped `make test` hanging
on leaked `ssh-agent` processes. Neither is incidental and neither moves.

## Out of scope

- **B9** — `Make()` in `2_functions.zsh` routes to `/usr/local/bin/gmake` or
  `/opt/homebrew/bin/gmake` by hostname, duplicating what `6_path.zsh`'s gnubin prepend
  already does. Same disease, but removing it means relying on `PATH`, and `CLAUDE.md`
  documents a live interaction where a `PATH` prepend inside a hook shadows the test
  suite's own `make` mock. Separate cycle; backlog row.
- **The five prefix-test sites not converted** — see the classification table above for the
  per-site reasoning. `5_general:111,115` is the one worth a backlog row on its own: the ARM
  arm lists only `LAPTOP||STUDIO`, so gcloud completion is silently absent on `reception`,
  `office` and `home-1`, and converting the guard would enable it on all three.
- Collapsing `personal_laptop` and `mac_workstation` into one profile.
- Renaming `home-1` on the hardware.

## Added detection

`run_doctor` gains a check that `PROFILE != unknown`, following the existing `command -v`
pattern — roughly six lines plus a test. This is the check that would have surfaced B10:
today an unmapped hostname degrades silently because `unknown` is a well-formed answer with
no capabilities, and nothing reports it.

## Testing

Three groups. `tests/mocks/hostname` already exists.

1. **`profiles.bats` wireless pairs.** For each wireless key, assert it resolves to the same
   `PROFILE` and the same `HAS_*` set as its wired twin. Mutation guard: deleting a wireless
   key from the table must turn this red.
2. **zsh derivation.** Mock `hostname`, source `config/profiles.zsh`, assert both the
   `HAS_*` set and the legacy variable. Includes a re-source idempotency case, since the
   file is sourced by `.zprofile` and again by `1_init.zsh` in a login+interactive shell.
3. **Cross-shell equivalence.** For every key in the table, assert bash and zsh derive
   identical `PROFILE` and `HAS_*` sets. This is the group that matters: two shells reading
   one table is an oracle derived by a different mechanism than the target, which is the
   property the current suite lacks.

Error paths and boundaries required by `tdd.md`: unmapped hostname (`PROFILE=unknown`, zero
capabilities, doctor reports it), empty `hostname -s` output, and a hostname that is a
prefix of a real key (`studio-2`) resolving to `unknown` rather than to `studio`.

Coverage: `config/profiles.sh` is already in the instrumented set and gains only
multi-line array-literal lines, which the tracer excludes from the coverable count, so the
denominator barely moves. `config/profiles.zsh` is zsh and is not instrumented by a bash
tracer — correctly, not as a gap. The test count rises from 1367; `CLAUDE.md`'s figure is
updated post-merge from the CI run, never from a local one.

Lint: `config/profiles.sh` becomes zsh-consumed, so it should join `ZSH_FILES` for `zsh -n`
while remaining in `SHELL_FILES` for `bash -n` and shellcheck. One file, both parsers.

## Assumptions

1. ~~**`keychain --eval any home` on `home-1` is a typo.**~~ **RESOLVED 2026-08-17 —
   confirmed.** The operator ran `ls ~/.ssh/any*` on `home-1`; zsh returned
   `no matches found`. No such key exists, so dropping it lost nothing. Kept here rather
   than deleted: one command settled the only assumption this design shipped on, and a
   reader should be able to see that it was actually run. Original wording follows.
   If `any` is a real key on that
   machine, dropping it stops that key being loaded. Refuted by `ls ~/.ssh/any*` on
   `home-1` returning a key; confirmed by it returning nothing. One-line revert if wrong.
   Retaining it would force a per-host carve-out back into a design whose purpose is
   removing per-host carve-outs, which is why the spec picks a direction rather than
   preserving the outlier.
2. **`hostname -s` is the only identity input.** If any machine's wireless hostname differs
   from `<wired>-1` in a way not captured here, its row is wrong. Refuted by running
   `hostname -s` on each box on each interface.
3. **No consumer depends on a legacy variable being `readonly`.** `detect_env.sh` currently
   declares them `readonly`; the zsh side uses `export`. Refuted by any code that relies on
   assignment to `STUDIO` failing.

## Related

- Backlog rows closed: "bash and zsh disagree on machine identity", "keychain block repeats
  one 4-line group across 7 host branches", "`PROFILE_CAPS[server]` has no hostname mapping".
- Backlog rows added: B9, `Make()` hostname-hardcoded gmake paths; and gcloud completion
  absent on `reception`/`office`/`home-1` because `5_general:115`'s ARM arm lists only
  `LAPTOP||STUDIO`.
- `CLAUDE.md` — Profile Model, Adding a New Machine (gains the wired/wireless pair rule).
- `behavior.md` — "a check derived from the same decision as the thing it checks cannot
  falsify it" (the `profiles.bats` finding).
- `shell.md` — absolute-path defaults defeating `PATH` mocks (the `_OVERRIDE_KEYCHAIN_BIN`
  seam this work must preserve).

## Multi-Lens Review

Reviewed at commit: `ecb811f` (Step 7 self-review commit)

### Goal-Fit

Finding: lens skipped — the session carries a standing instruction not to dispatch the
Agent tool unless the operator asks, and the operator elected to proceed without the
dispatch after being shown the cost and the three open decisions.
Assumption: not produced (lens did not run).
Disposition: Accepted — operator proceeded to `writing-plans` with the skip recorded. The
lenses remain runnable against this SHA if the plan or the implementation turns up
something that makes the design worth re-opening.

### Ergonomics

Finding: lens skipped — same reason.
Assumption: not produced (lens did not run).
Disposition: Accepted — as above.

### Risk

Finding: lens skipped — same reason.
Assumption: not produced (lens did not run).
Disposition: Accepted — as above.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger. There are no arms being
compared, no judge component, and the acceptance criteria are concrete commands (the three
test groups, and cross-shell equivalence over every table key).

### What the skip actually costs here

Recorded so the disposition is legible rather than merely permitted. Step 8's documented
strength is attacking a design; its documented weakness is that it does not question the
population a measurement was drawn from. This spec's design surface is small — one data
file, one new derivation file, three consumers — and all five load-bearing premises (M1–M5)
were measured on both development machines rather than reasoned about.

The two corrections this spec actually needed both came from the Step 7 population check,
not from design critique: an alias block described as five lines that is ten, and a
read-site count that was accurate while concealing that nine of nineteen sites are Homebrew
prefix tests rather than identity tests. Both are the class Step 8 is documented as missing.

The residual risk is therefore concentrated in Assumption 1 (`keychain --eval any home`),
which no lens could settle either — it is answered by `ls ~/.ssh/any*` on `home-1`, a
command, not a review.
