# zsh legacy-identity consolidation — design

Date: 2026-08-17
Repo: dotfiles
Backlog rows closed: "hostname→legacy-variable lives in four tables" (fully); "five hostname
reads survive in `5_general.zsh` — rbenv and gcloud" (**partially** — 1 of its 3 sites).
Backlog rows _re-opened and rewritten_ by this spec: "gcloud completion absent on three work
macs", superseded by the `.zshrc` ownership finding in round 3.

> **Scope was cut twice by review.** Round 1 and 2 reshaped the gcloud work; round 3 removed it
> entirely. What ships is A1 (one rbenv guard), Part B (four mapping tables → two) and Part C
> (four documentation corrections). Decisions 2 and 3 and task A2 are retained below as records
> of why they were cut, not as work to do.


---

## Problem

Two independent residues of the 2026-08-16 zsh-identity work (#222).

**1. `.config/.zshrc.d/5_general.zsh` still reads legacy identity variables at three
sites.** That PR converted this file's `CHRUBY_LOC`, `FZF_BASE` and keychain blocks from
hostname tests to capability or Homebrew-prefix tests, and left three:

| site   | current test                                        | the question it is really asking | in scope |
| ------ | --------------------------------------------------- | -------------------------------- | -------- |
| `:77`  | `[[ -n ${WORKSTATION} ]] \|\| [[ -n ${CRUNCHER} ]]` | is this a Linux dev box?         | **yes** — A1 |
| `:131` | `[[ ${RATNA} ]]`                                    | is this an Intel mac?            | no — cut in round 3 |
| `:135` | `[[ ${LAPTOP} ]] \|\| [[ ${STUDIO} ]]`              | is this an ARM mac?              | no — cut in round 3 |

**Only `:77` is in scope, and the reason the other two are not is the most useful thing this
spec measured.** The `:131`/`:135` pair looked like a live defect — `reception`, `office` and
`home-1` share `studio`'s Homebrew prefix, are absent from the `:135` list, and get no gcloud
completion from this file. All of that is true. What no round of review caught until the third
is that **`.zshrc` already sources both `.inc` files, from the same declared root, with no
hostname guard, on every mac** — five lines below the `.zshrc.d` loop that runs
`5_general.zsh`:

```
.zshrc:3   for FILE in ~/.config/.zshrc.d/*.zsh; do source $FILE; done
.zshrc:8   if [ -f '/opt/homebrew/share/google-cloud-sdk/path.zsh.inc' ];       then . '...'; fi
.zshrc:11  if [ -f '/opt/homebrew/share/google-cloud-sdk/completion.zsh.inc' ]; then . '...'; fi
```

Measured on a shell with `hostname` mocked to `reception`, tracked files only:

| stage                            | gcloud completion | SDK `bin` on `PATH` |
| -------------------------------- | ----------------- | ------------------- |
| after the `.zshrc.d` loop        | **ABSENT**        | no                  |
| after `.zshrc:8,11`              | **LOADED**        | YES                 |

So fixing `:131`/`:135` would have delivered nothing to any ARM mac, and the "three work macs"
framing is refuted. `.zshrc` hardcodes `/opt/homebrew`, so its two lines no-op on Intel, which
leaves `ratna` served only by the `5_general.zsh` copy — meaning a "fix" there would have been a
path change on the single host unreachable by `ssh`, carrying a regression risk and no
measurable gain. The gcloud work is therefore **out of scope and rewritten as a backlog row**:
the real finding is that two files source the same pair of includes, one of them unguarded and
ARM-hardcoded, and that wants one owner rather than a better guard in the duplicate.

**Why three rounds of review missed it, which is the transferable part.** This spec declared its
own population as `grep -rn` over `--include='*.zsh' --include='*.sh' --include='*.bats'` plus
`.zprofile`. `--include='*.zsh'` does not match `.zshrc`:

```
$ grep -c 'google-cloud-sdk' .zshrc                                   # 2
$ grep -rln 'google-cloud-sdk' --include='*.zsh' . | grep -c '\.zshrc$'  # 0
```

That is `shell.md`'s "a pathspec cannot express *every tracked shell script*" — the same defect
as the extensionless-hooks omission — occurring **inside the paragraph that states the
methodology**, and it is the third premise failure this spec has had in the same position. The
census below is corrected to derive from `ZSH_FILES`, which does include `.zshrc`.

**2. The hostname→legacy-variable mapping exists in four byte-identical places.** #222
collapsed hostname→**profile** to one table (`config/profiles.sh`'s `PROFILE_MAP`) but
hostname→**legacy variable** did not follow:

| #   | location                                | role              |
| --- | --------------------------------------- | ----------------- |
| 1   | `config/profiles.zsh:63-83`             | production, zsh   |
| 2   | `lib/detect_env.sh:52-61`               | production, bash  |
| 3   | `tests/zshrc.d/profiles.bats:93-105`    | test oracle, zsh  |
| 4   | `tests/setup_env/profiles.bats:316-328` | test oracle, bash |

All four are the same eight-arm `case` over the same thirteen `PROFILE_MAP` keys, wired and
wireless twins included. Drift between them is currently _detected_ by tests 3 and 4, not
made impossible.

### Premise corrections, measured 2026-08-17 before this spec was written

The backlog row for item 2 asserted `lib/detect_env.sh` carried "5 of 8 vars, no `-1`
twins". **False.** `lib/detect_env.sh:52-61` carries all eight variables, each with its
wireless twin, identical to `config/profiles.zsh`. #222 had already fixed it and the row
was not updated. The row's core claim — four copies, drift detected rather than prevented
— survives; the severity claim does not.

The backlog rows for items titled "five hostname reads survive in `5_general.zsh`" and
"gcloud completion absent on three work macs" **overlap**: the second is a subset of the
first's `:131`/`:135` conversion. This spec treats them as one work item, not two.

**Population of every count in this spec:** all figures are `git`-tracked files in
`~/git-repos/personal/dotfiles` at `HEAD` on 2026-08-17, measured by `grep -rn` over
`--include='*.zsh' --include='*.sh' --include='*.bats'` plus `.zprofile`. They are claims
about this repo only, not about the fleet.

---

## Read-site census (measured 2026-08-17, corrected in round 3)

Every site that reads one of the eight legacy identity variables, outside the four mapping
tables. **The population is `ZSH_FILES` plus `lib/*.sh`, not a `--include='*.zsh'` pathspec** —
that pathspec is what hid `.zshrc` for three rounds (see Problem, item 1). `ZSH_FILES` is the
`Makefile`'s own set and does include `.zshrc` and `.zprofile`.

| file                               | sites                     | in scope here                  |
| ---------------------------------- | ------------------------- | ------------------------------ |
| `.config/.zshrc.d/5_general.zsh`   | 3 (`:77`, `:131`, `:135`) | **1 of 3** — `:77` only (A1)   |
| `.config/.zshrc.d/2_functions.zsh` | 2 (`:8`, `:12`)           | no — `Make()` gmake backlog row |
| `.config/.zshrc.d/7_final.zsh`     | 1 (`:60`)                 | no — see Out of scope          |
| `.zprofile`                        | 2 (`:6`, `:10`)           | no — see Out of scope          |
| `.zshrc`                           | 0                         | reads no identity variable — but see Problem item 1: it sources gcloud unguarded, which is why it belongs in the census at all |

**After this work `5_general.zsh` still reads two legacy identity variables** (`:131`, `:135`),
and 7 sites remain across 4 files. An earlier draft said zero and five-across-three; that was
true only under the dropped A2. This matters beyond bookkeeping — it is what keeps A3 alive and
changes its direction, since the `SC2034` reason strings must go on naming this file.

The variables themselves are not removed and this spec does not claim to reduce the number of
places the mapping is *read* — only the number of places it is *written*.


---

## Decisions

### Decision 1 — the test oracle stays independent of the production table

The backlog row proposed: one `PROFILE_LEGACY` table, both test oracles deleted, both
tests deriving their expectations from that table. That makes the oracle and the thing
under test the same artifact — `behavior.md`, "A check derived from the same decision as
the thing it checks cannot falsify it." Under that shape a `[home-1]=HOME` typo in the
table ships green, because the test would assert the table against itself. (`HOME` is not
a hypothetical: `export HOME=1` in a login shell repoints the user's home directory, which
is why `home-1 → HOMES` is a hand-written carve-out and not a derivation in the first
place.)

**Chosen: four tables → two, with the two derived by different mechanisms.**

- **One production table.** `PROFILE_LEGACY` in `config/profiles.sh`, read by
  `config/profiles.zsh` and `lib/detect_env.sh`. Tables 1 and 2 above become lookups.
- **One test oracle.** `tests/helpers/legacy_oracle.bash`, hand-typed, sourced by both
  suites. Tables 3 and 4 above become one shared helper.

Two artifacts remain, and that is the point: the oracle can still falsify the table, and
the table can still falsify a broken reader. Drift between the two is what the test
reports, which is the same protection tests 3 and 4 give today at half the copies.

Rejected alternative — full collapse plus a content-derived cross-check (grep the repo's
read sites for legacy variable names, assert set-equality against `PROFILE_LEGACY`'s
values). It catches a variable gained or lost but not a swapped mapping
(`[laptop]=STUDIO` leaves both names present), so it does not replace what the oracle
does.

### Decision 2 — cut entirely in round 3 (record only)

**This decision was reversed once and then removed. It is kept as the record of a three-round
failure, because each correction was itself wrong and the pattern is the lesson.**

- **Round 0:** symmetric — source `path.zsh.inc` and `completion.zsh.inc` on both arms.
  Justified to the operator as "`ratna` newly sources `path.zsh.inc`, putting the gcloud CLI on
  its `PATH`". **False**: the cask links `gcloud`/`gsutil`/`bq` into `${prefix}/bin` as `binary`
  artifacts, and `path.zsh.inc` is 31 bytes adding only four unlinked auxiliaries.
- **Round 1:** kept symmetric, replaced a stale cask token with a two-token resolver over
  `Caskroom/<token>/latest/`. **Wrong path**: that is a symlink to a symlink onto the cask's
  declared root, labelled `# HACK` at `gcloud-cli.rb:64` and trashed on uninstall at `:98`.
- **Round 2:** completion-only on the declared root `${prefix}/share/google-cloud-sdk`.
  Correct as code — verified under real zsh on both fleet builds — and justified with a second
  false claim: that `laptop` and `studio` would lose four auxiliaries. **Also false**, because
  `.zshrc:8` puts SDK `bin` on `PATH` unconditionally on ARM.
- **Round 3:** cut. `.zshrc:8,11` already sources both files from that same root on every mac,
  so nothing in this decision changed any ARM machine's behaviour, and its only live effect was
  a path change on `ratna` — the one host no evidence covers.

**Two operator approvals were obtained for this decision and both were obtained against a false
description of `path.zsh.inc`.** That is recorded here rather than quietly dropped: the failure
was not a wrong option chosen, it was the same line of a third-party file described wrongly
twice in a row, by the same author, after the first correction.


### Decision 3 — derived test isolation is cut from this spec (revised after review)

**Round 1 of the Multi-Lens Review killed this decision. It is kept here as the record of
why, not as work to do.**

The original text proposed deriving `tests/zshrc.d/profiles.bats:42`'s hand-typed `unset`
list from `PROFILE_LEGACY`, on the reasoning that isolation must be exhaustive while an
oracle must be independent — and called that line "a **fifth** copy of the name list",
claiming the derivation made isolation "exhaustive by construction".

Both halves failed measurement. The unset-isolation form appears **22 times** across four
test files — 17 in `tests/zshrc.d/unit.bats` alone, 2 in `tests/zshrc.d/profiles.bats`, 2 in
`tests/zshrc.d/cross_shell.bats`, 1 in `tests/setup_env/profiles.bats` — plus 4 more copies
in the reporting loops, one of them 14 lines below the line being converted, inside the same
function. 26 occurrences total, verified independently:

```
$ grep -rc 'LAPTOP STUDIO RECEPTION OFFICE HOMES WORKSTATION CRUNCHER RATNA' \
    --include='*.bats' tests/ | grep -v ':0'
tests/zshrc.d/unit.bats · tests/zshrc.d/cross_shell.bats
tests/zshrc.d/profiles.bats · tests/setup_env/profiles.bats
# 26 occurrences, 4 files
```

Converting one of 22 achieves 4.5% of the stated property while telling the reader the class
is closed — and it buys that 4.5% at the price of a **silent-empty** failure path. A
bash-side derivation interpolated into a `zsh -c` string fails as
`unset: not enough arguments` on stderr the harness does not capture (`profiles.bats:47`
redirects only the `source`), does not change the `zsh -c` exit status, and leaves the
per-host assertion — `grep -qx "LEGACY=..."`, a membership check at `profiles.bats:173` and
`setup_env/profiles.bats:343` — satisfied by whatever is ambient. In CI nothing is ambient,
so an empty derivation is **green**; it trips only on a developer machine whose login shell
exports `STUDIO=1`. The gate that blocks auto-merge cannot see the regression, which inverts
this repo's own rule that CI's figure is the one the gate reads. `profiles.bats:121` already
documents that class 80 lines away, complete with a note that a count comparison was tried
there and removed as circular.

The hazard being hardened against is a _ninth_ legacy variable arriving. The direction of
this work, and of #222 before it, is removing read sites — this spec takes `5_general.zsh`
from three to zero. Paying a CI-invisible silent-pass path in the suite's isolation
mechanism to pre-harden growth that is not happening is negative expected value.

**Cut.** All 26 sites go to a single backlog row, to be converted together with a
non-emptiness and count-pinned guard in front of the derivation. Decision 1's oracle
consolidation (B1–B4) is unaffected and still delivers four tables → two.

---

## Design

### Part A — `.config/.zshrc.d/5_general.zsh`

**A1. rbenv guard, `:77`.** Replace `[[ -n ${WORKSTATION} ]] || [[ -n ${CRUNCHER} ]]` with
`[[ ${HAS_DEVTOOLS} ]]`.

Behaviour-preserving for every currently-mapped host, by the same argument the keychain
block already records at `:215-219`: `config/profiles.sh`'s `PROFILE_CAPS` defines exactly
two Linux profiles, `linux_workstation` and `wsl2_workstation`, both carry `devtools`, and
`PROFILE_MAP` maps exactly `workstation` and `cruncher` to them. The `_OVERRIDE_RBENV_BINARY`
seam at `:78` and the enclosing `NOBLE`/`RESOLUTE` guard are unchanged.

**A2 — cut in round 3. See Decision 2 for the full record.** The gcloud block at `:129-143` is
left exactly as it is, hostname guard and stale cask token included, and becomes a backlog row
naming `.zshrc:8,11` as the real owner. No line of `5_general.zsh`'s gcloud handling is touched
by this spec.

**A3. `SC2034` reason strings — smaller than the earlier draft, and pointing the other way.**
Under the dropped A2 this file would have read no legacy identity variable, and A3 was "remove
`5_general.zsh` from every reader list". With only A1 shipping, `:131` and `:135` still read
`RATNA`, `LAPTOP` and `STUDIO`, so the reason strings in `lib/detect_env.sh:51` and
`config/profiles.zsh:6-10` must **keep** naming this file. What changes is the clause inside
them: both currently say the keychain block reads none of these "but its rbenv guard
(`WORKSTATION`/`CRUNCHER`) and gcloud completion arms (`RATNA`/`LAPTOP`/`STUDIO`) still do". A1
retires the rbenv half, so the clause narrows to the gcloud arms alone.

That is a two-word edit rather than a deletion, and getting it backwards would be the exact
defect A3 exists to prevent — a reason naming a file that no longer reads the variable stops the
next reader checking, and so does a reason that *stops* naming a file which still does. The
second direction is worse: it reads as "nothing here uses this", which is how a variable gets
deleted.

`config/profiles.zsh`'s header comment (`:4-10`) carries the same clause and needs the same
narrowing.

**The reason string must carry the invariant, not only today's fact.** A3's own argument is that a
reason naming a dead reader stops the next reader checking, and a reason that stops naming a live
one reads as "nothing uses this". But the person making the *next* edit is reading the reason
string, not this spec — and if the gcloud arms are ever converted (the backlog row), that clause
needs narrowing again with the identical failure mode available in both directions. So state the
rule where the editor will be standing:

```bash
# shellcheck disable=SC2034 # Read cross-file, which the linter cannot see. This list names
# EVERY read site -- add one when a site is added, remove one when a site is removed, and treat
# an omission as seriously as a stale entry: a list that stops naming a live reader reads as
# "nothing uses these" and is how the variables get deleted. Sites: 2_functions.zsh,
# 5_general.zsh (gcloud completion arms at :131/:135 only -- its keychain and rbenv blocks read
# none of these), 7_final.zsh, .zprofile. One directive covers the whole case (SC1124: a
# directive cannot sit on a case-arm line).
```

This is the one place A3's reasoning applies to A3's own output, which is why it is worth the
extra two lines rather than left to the next author to re-derive.


**B1. `config/profiles.sh`.** Add a third map beside `PROFILE_MAP` and `PROFILE_CAPS`:

```bash
declare -A PROFILE_LEGACY=(
  [laptop]="LAPTOP"          [laptop-1]="LAPTOP"
  [studio]="STUDIO"          [studio-1]="STUDIO"
  [reception]="RECEPTION"    [reception-1]="RECEPTION"
  [ratna]="RATNA"            [ratna-1]="RATNA"
  [office]="OFFICE"          [office-1]="OFFICE"
  [home-1]="HOMES"
  [workstation]="WORKSTATION"
  [cruncher]="CRUNCHER"
)
```

Thirteen keys, matching `PROFILE_MAP` exactly. The existing file-wide `SC2034` directive
at `:6` already covers a third declaration — a directive before the first real command in
a file applies file-wide — and its reason string gains `PROFILE_LEGACY` and
`config/profiles.zsh` as readers.

The mapping is written out rather than derived. `home-1 → HOMES` breaks
strip-`-1`-and-uppercase, and the value that derivation would produce is `HOME`.

**B2. `config/profiles.zsh`.** Replace the `case` at `:63-83` with a lookup:

```zsh
_profiles_legacy="${PROFILE_LEGACY[${_profiles_hostname}]:-}"
if [[ -n ${_profiles_legacy} ]]; then
  export "${_profiles_legacy}=1"
elif [[ -n "${PROFILE_MAP[${_profiles_hostname}]:-}" ]]; then
  print -u2 "config/profiles.zsh: host '${_profiles_hostname}' resolved PROFILE=${PROFILE} but has no PROFILE_LEGACY entry -- add one in config/profiles.sh."
fi
unset _profiles_legacy
```

The warning arm survives the `case` removal with its trigger unchanged: a hostname
`PROFILE_MAP` recognises but `PROFILE_LEGACY` does not is a drifted table and warns; a
genuinely unmapped hostname (`PROFILE=unknown`) stays silent. `export`, not `readonly` —
this file is sourced twice per login+interactive shell and a `readonly` reassignment makes
the second `source` return 126 (`config/profiles.zsh:12-22`).

`PROFILE_LEGACY` joins the `unset` at `:85`.

**B3. `lib/detect_env.sh`.** Replace the `case` at `:52-61` with the bash equivalent:

```bash
local legacy
legacy="${PROFILE_LEGACY[${hn}]:-}"
[[ -n ${legacy} ]] && readonly "${legacy}=1"
```

`readonly`, not `export` — `detect_env` runs once per bash process. The asymmetry with B2
is deliberate and already documented at `:44-50`; that comment is updated to point at the
lookup rather than the `case` but its reasoning is unchanged.

No warning arm here. `detect_env.sh` has no equivalent today and adding one would be new
behaviour on the bash side; the zsh warning plus the test in B4 already cover the drift
case, and the bash side has no interactive stderr channel where a warning would be read.

**B4. Test oracles.** New `tests/helpers/legacy_oracle.bash` holding one hand-typed
`_expected_legacy_var() { case ... }`, identical in behaviour to the two functions it
replaces including the `*) return 1 ;;` arm — an empty return is indistinguishable from
"this host legitimately has none", which is the gap the current `*) return 1` closes.

- `tests/setup_env/profiles.bats` already sources `tests/helpers/common.bash` in `setup()`;
  it gains one more `source` line and deletes `_expected_legacy_var` at `:316-328`.
- `tests/zshrc.d/profiles.bats` sources no helper today. It gains a `source` line in
  `setup()` and deletes `_profiles_expected_legacy` at `:93-105`, updating its call at
  `:141` to the shared name. The `source` runs at bats level, outside the `zsh -c` body of
  `_profiles_snapshot`, so the isolation reasoning at `:14-37` is unaffected.
- The `no_legacy` exception set at `tests/zshrc.d/profiles.bats:132` stays. It is empty
  today and is the reviewable place a future host that should genuinely have no legacy
  variable is declared.

**B4a. The two failure messages move into the helper with the `case` they describe.** They are
in the *callers* today — `tests/zshrc.d/profiles.bats:142` and
`tests/setup_env/profiles.bats:339`, each one line below the call B4 updates — and each
hardcodes the oracle's function name and file. The zsh one also directs the reader to
"`config/profiles.zsh`'s own case statement", which B2 deletes and B1 replaces with
`PROFILE_LEGACY` in `config/profiles.sh`. Porting the oracle without them ships three stale
references in a string an operator reads while debugging, which is the failure A3 exists to
prevent, on a worse surface than a lint comment: `A3` says a reason naming a file that no
longer reads the variable "stops the next reader checking", and this stops them checking the
right file entirely.

One message, in `tests/helpers/legacy_oracle.bash`, naming `config/profiles.sh`'s
`PROFILE_LEGACY` as the table and the helper itself as the oracle — the same four-to-two
consolidation applied to the diagnostic instead of only to the data. Callers then just
propagate the non-zero.

**B4b. One case must actually reach the `*) return 1` arm.** Nothing does today and nothing
would after B4: all 13 `PROFILE_MAP` keys have oracle arms, so the suite exercises the 13-way
comparison and never the diagnostic that fires when the comparison has no oracle entry. That
is precisely why the stale strings above are undetectable by construction. A fixture
`config/profiles.sh` carrying a key absent from the oracle drives the arm, pins the message's
file paths, and is mutation-provable against exactly that defect.

**B5 — cut after round 1 of review; see Decision 3.** The derived-isolation task is not part
of this spec. `_profiles_snapshot`'s `unset` line and the other 25 hand-typed occurrences are
left exactly as they are, and go to one backlog row together. Nothing in Part B touches test
isolation; B4 changes only which file the oracle lives in.

### Part C — documentation

**The premise here was inverted in the first draft and the correction matters, because it
changes what the edit says.** That draft claimed `CLAUDE.md`'s "No other file needs changing"
becomes wrong *after* this work. It is wrong **now**, and has been since #222. Reproduced by
following the documented procedure literally — edit `PROFILE_MAP` only — in a `git archive`
copy:

```
$ bats tests/setup_env/profiles.bats -f 'legacy identity variable in bash'
not ok 1 every PROFILE_MAP hostname sets the right legacy identity variable in bash
# PROFILE_MAP host "newmac-1" has no legacy-variable mapping in _expected_legacy_var
$ bats tests/zshrc.d/profiles.bats -f 'every PROFILE_MAP hostname resolves'
not ok 1 every PROFILE_MAP hostname resolves the right PROFILE, HAS_* set, and legacy var in zsh
```

A new machine costs **5 edits across 5 files today** — `PROFILE_MAP`, both production `case`
arms, both test oracles — against a document claiming one. After B1–B4 it costs **3 edits
across 2 files**: `PROFILE_MAP` and `PROFILE_LEGACY` in `config/profiles.sh`, and one arm in
`tests/helpers/legacy_oracle.bash`. So this work makes the sentence **less** wrong, and C is
correcting a document that has been lying for a day, not documenting friction this change
introduces. Writing it the other way would tell the next reader the procedure was accurate
before #223 and that this change added steps, when it removed 40% of them.

**C1. `CLAUDE.md`, "Adding a New Machine" (`:623`).** Qualify the sentence rather than delete
it: it stays true for production files — both maps live in `config/profiles.sh` — and becomes
false for the test oracle. Name both maps in the step list, with the wired/wireless twin rule
applying to `PROFILE_LEGACY` exactly as to `PROFILE_MAP`, and name
`tests/helpers/legacy_oracle.bash` as the one other file. State the two failure modes, since
they differ and an operator will meet one of them: a missing oracle arm **fails the suite**, a
missing `PROFILE_LEGACY` entry only **warns to stderr at login**.

**C2. `config/profiles.sh:4` — the same claim, inside the diff's own hunk.** That line reads
`# Edit PROFILE_MAP to add a new machine — no other file needs changing.` and sits four lines
above where `PROFILE_LEGACY` is inserted. Fixing the `CLAUDE.md` copy and leaving this one is
the worse outcome of the two, because this is the file the operator is already editing when
they need it. Same qualification.

**C3. `config/profiles.sh:6` — the `SC2034` reason.** It reads "**both** maps below are read by
`lib/detect_env.sh:detect_env`" and argues "a second directive on `PROFILE_CAPS` would be
redundant". B1 makes it three maps, and `PROFILE_LEGACY` is read by `config/profiles.zsh` too.
The count and the reader list both change; the file-wide-directive reasoning does not.

**C4. `CLAUDE.md` Testing / Test Seams.** Name `tests/helpers/legacy_oracle.bash` and state
that it is deliberately hand-typed rather than derived from `PROFILE_LEGACY` — otherwise the
next reader "fixes" it into the circular form Decision 1 rejected, and `behavior.md` is the
only thing standing between them and a green `[home-1]=HOME`.

This is not closeout paperwork for the Phase 3 `docs` skill. That skill is scoped to what the
diff changed, and `CLAUDE.md:623` is in a section this diff does not touch, so it would be
swept only by luck. Documentation Currency puts all four in the same change.


---

## Verification

### The falsifiable form for A2

None — A2 is cut. Every fixture case, the token matrix and the `path.zsh.inc`-not-sourced case
are removed with it. Two of them had already gone stale against each other before the cut: the
round-1 prose still said "both files are sourced" and "2 sources" while the round-2 table below
it said `1 sourced` and required `path.zsh.inc` **not** sourced. An implementer reading top-down
would have written the wrong assertion — worth recording, because that contradiction survived a
full lens round in text nobody flagged.

### The falsifiable form for A1

`_OVERRIDE_RBENV_BINARY` pointed at a mock, with `HAS_DEVTOOLS=1` and with it unset, on a
simulated `LINUX`+`NOBLE` shell: the mock is invoked in the first case and not in the
second. Both arms asserted, per `logic-review.md` item 6.

### The falsifiable form for B

- The two existing per-host assertions (`tests/zshrc.d/profiles.bats`,
  `tests/setup_env/profiles.bats`) keep passing against the shared oracle, which now
  genuinely falsifies `PROFILE_LEGACY` rather than a co-located `case`.
- A negative case for B2's warning arm: a `PROFILE_MAP` key with no `PROFILE_LEGACY` entry
  produces the stderr line.

**How both negative cases are constructed, because "a fixture `profiles.sh`" is not a method
and there is no seam.** Added after peer review supplied the rule that a fixture demonstrates a
mechanism only if it could have produced the opposite result — applying it here showed B2's and
B4b's cases were unrunnable as originally worded, which three lens rounds had not caught.

Neither production reader takes an override:

```
config/profiles.zsh:40   source "${${(%):-%x}:A:h}/profiles.sh"
lib/detect_env.sh:23     source "$(dirname "${BASH_SOURCE[0]}")/../config/profiles.sh"
```

and no existing test injects a table — every one sources the real `config/profiles.sh` and mocks
only `hostname`. So an implementer reading "a fixture `profiles.sh`" either stalls, adds a
production seam that is not needed, or silently points the case at the real table where the arm
can never fire. That last one is the dangerous reading: it passes.

**No seam is required. Copy the pair into a temp tree and source the copy** — both readers
resolve the table relative to their *own* file, so relocating the file relocates the lookup.
`${${(%):-%x}:A:h}` was chosen for symlink resolution (`CLAUDE.md` records why `$0` cannot be
used in a startup file) and this is a second property of that choice. Verified 2026-08-17 on both
sides, against the **current** code:

```bash
fx=$(mktemp -d); mkdir -p "$fx/config" "$fx/lib"
cp config/profiles.zsh "$fx/config/"
cp lib/detect_env.sh   "$fx/lib/"          # ../config/ layout preserved
sed '<insert [newhost]="mac_mini" into PROFILE_MAP>' config/profiles.sh > "$fx/config/profiles.sh"
# hostname mocked to newhost:
#   zsh  -> PROFILE=mac_mini  + stderr "host 'newhost' ... has no legacy-identity case arm"
#   bash -> PROFILE=mac_mini
```

`PROFILE=mac_mini` is the discriminator: the real table would yield `unknown`, so it proves the
fixture was read rather than bypassed. And the warning fires against today's `case` statement —
with a legacy arm present it does not — so the case could have produced the opposite result
before B2 exists, which is the property that makes it evidence rather than decoration.

B4b's oracle-arm case is constructed the same way: the fixture table carries a `PROFILE_MAP` key
absent from `tests/helpers/legacy_oracle.bash`, and the assertion is the oracle's `*) return 1`
message naming the helper. Same discriminator applies — a key present in both must **not** fire
it.
- No B5 case — B5 is cut (Decision 3). Test isolation is untouched by this spec.

### The falsifiable form for C

**The first draft's check was inert.** It was `grep -c 'No other file needs changing' CLAUDE.md`
with no stated expected value — and that returns **1 today, before any work**. It returns 1 if
the sentence is correctly qualified and 1 if it is never touched, so it cannot observe the one
thing C1 exists to do. It also pinned a sentence whose premise is refuted, meaning it would
have failed a reviewer who correctly rewrote it.

Assert the new content instead, with stated expected values:

```bash
# C1 + C4 — CLAUDE.md names both maps and the oracle file
grep -c 'PROFILE_LEGACY' CLAUDE.md                     # >= 2 (step list + worked example)
grep -c 'legacy_oracle' CLAUDE.md                      # >= 2 (step list + Testing section)
grep -c 'fails the suite' CLAUDE.md                    # >= 1 (the oracle-arm failure mode)

# C2 + C3 — config/profiles.sh's own two claims
grep -c 'no other file needs changing' config/profiles.sh   # 0 — unqualified form is gone
grep -c 'PROFILE_LEGACY' config/profiles.sh                 # >= 2 (the map + the SC2034 reason)
grep -c 'both maps below' config/profiles.sh                # 0 — superseded by three
```

The two `0` expectations are the load-bearing ones: they are the only form that distinguishes
"corrected" from "untouched", which is exactly what the inert check could not do. Each is
mutation-provable — revert the doc edit and the count returns to 1.


### Suite-level

| check                | command              | expectation                                                          |
| -------------------- | -------------------- | -------------------------------------------------------------------- |
| tests                | `make test`          | ≥ 1402 tests, 0 `not ok`, rc 0                                       |
| lint                 | `make lint`          | rc 0; `zsh -n` covers `5_general.zsh`, `profiles.zsh`, `profiles.sh` |
| coverage             | `make bash-coverage` | ≥ 91%                                                                |
| branch zsh re-source | see below            | rc 0                                                                 |

Both baseline figures are **CI measurements on `ubuntu-latest` at `5e1f934`**, per
`CLAUDE.md` — not local ones. That distinction is load-bearing: this repo measures bash
coverage about one point higher on macOS than CI does, and ratcheting a floor to a local
number has already failed a PR here once. Read a local `make test` / `make bash-coverage`
as a preview and label it as one; the figure the gate reads is CI's.

Neither figure may be captured through `head`/`tail` — a pipeline's exit status is the last
command's, so `make test 2>&1 | tail -3` reports success over a failing suite
(`shell.md`). Redirect to a file, capture `$?` immediately, then grep the file.

**The branch re-source check must source the branch's own files, not `zsh -i -c 'exit'`.** From
a worktree `~/.zshrc` and `~/.config/.zshrc.d` are symlinks into the main checkout, so an
interactive shell reads the unmodified files and returns 0 regardless of the branch — measured
during #222, where the worktree carried a new `source` line the main checkout had zero
occurrences of and `zsh -i -c exit` passed throughout.

**Two checks are needed, not one, and the first draft had only the wrong one for Part A.** It
carried `CLAUDE.md`'s documented command, which is correct for #222's subject and does not
reach this one: `1_init.zsh` ends at `source config/profiles.zsh`, and `.zshrc:3` is what loops
over `.zshrc.d/*.zsh`. So that command never sources `5_general.zsh` at all. Measured:

```
$ env -i HOME="$HOME" PATH=/usr/bin:/bin zsh -c '
    source .zprofile; source .config/.zshrc.d/1_init.zsh
    print "PROFILE=${PROFILE:-UNSET} AWS_HOME=${AWS_HOME:-UNSET} GPG_TTY=${GPG_TTY:-UNSET}"'
PROFILE=mac_workstation  AWS_HOME=UNSET  GPG_TTY=UNSET
```

`AWS_HOME` and `GPG_TTY` are set only by `5_general.zsh`. The draft presented that command as a
whole-branch guard while it covered Part B and **zero percent of Part A** — the half that runs
in every interactive shell on seven machines. Part A's only other runtime coverage is bats,
which sources the file with `2>/dev/null`, so stderr is discarded there too.

**Part B** — unchanged and correctly scoped; this is `CLAUDE.md`'s command:

```bash
zsh -c 'unset -m "HAS_*"; source .zprofile; source .config/.zshrc.d/1_init.zsh; [[ -n ${PROFILE} ]]'
```

**Part A** — goes through `.zshrc`'s own loop so every `.zshrc.d` file runs, asserts a
`5_general.zsh`-only variable to prove it was reached, asserts no helper leaked, and requires
empty stderr. Redirect to a file and capture `$?` immediately rather than piping — a pipeline's
status is the last command's, and `shell.md` records a green result reported from a suite that
had already failed for exactly that reason:

```bash
_err=$(mktemp)
zsh -c '
  source .zprofile
  for f in .config/.zshrc.d/*.zsh; do source "$f"; done
  [[ -n ${AWS_HOME} ]]               || { print -u2 "5_general.zsh not reached"; exit 1; }
  [[ -z ${_gcloud_prefix+x} ]]       || { print -u2 "_gcloud_prefix leaked"; exit 1; }
  [[ -z ${_homebrew_prefix_arm+x} ]] || { print -u2 "_homebrew_prefix_arm leaked"; exit 1; }
' 2>"${_err}"; rc=$?
[ "${rc}" -eq 0 ] && [ ! -s "${_err}" ] || { cat "${_err}"; false; }
```

The `AWS_HOME` assertion is what makes this falsifiable rather than decorative: without it the
check passes on a shell that never sourced the file under test, which is precisely how the
draft's version passed. Mutation-provable — point the loop at a directory with no
`5_general.zsh` and it goes red.

### Cross-machine verification (required, not optional)

`tdd.md` pitfall G: a suite that shells out to a versioned tool inherits that tool's version
skew, and a local pass is not evidence for the class. This fleet's two development machines
differ on every tool this spec touches, and `ubuntu-latest` matches the **workstation**, not the
Studio:

| tool | workstation (matches CI) | Mac Studio |
| ---- | ------------------------ | ---------- |
| bash | 5.2.21                   | 5.3.15     |
| zsh  | 5.9                      | 5.9.2      |
| bats | 1.10.0                   | 1.14.0     |

Every semantic this spec depends on was measured on **both**, 2026-08-17, and all are identical:

| claim                                                    | both machines           |
| -------------------------------------------------------- | ----------------------- |
| `readonly` inside a bash function is global              | `FOO=1` after return    |
| indirect `readonly` with an empty name                   | errors, rc 1            |
| `[[ -n ${v} ]] && readonly "${v}=1"` on an unmapped host | function rc 1           |
| `declare -A` sourced inside a function                   | function-local          |
| a 2nd `source` of a file doing `readonly X=1`            | **rc 126**              |
| a 2nd `source` of a file doing `export X=1`              | rc 0                    |
| `${(U)x}`, `${=arr}`, `unset -m 'HAS_*'`                 | identical               |

The `126` row settles B2's `export`-not-`readonly` choice empirically rather than by citation to
`profiles.zsh:15`, on both zsh builds.

**Phase 2 and Phase 3 must re-run `make test` on the workstation, and must ship the tree rather
than trust the checkout.** `git archive <sha> | ssh workstation` — never a `git pull` there,
never `git stash create`, never the workstation's own working tree. Measured why:

```
$ ssh workstation 'cd ~/git-repos/personal/dotfiles; git rev-parse --short HEAD; \
    git rev-list --count HEAD..origin/master'
b3b59b3
0                 # <-- FALSE. Its origin/master tracking ref is stale.
$ git rev-list --count b3b59b3..origin/master     # asked from the Studio
25
```

That checkout is 25 commits behind and predates `3387160` (#220), so its `5_general.zsh` has no
`[[ -o interactive ]]` guard on the keychain block. Running the Part A check against it emitted
490 bytes of keychain output and would have produced a **false finding** — that requiring empty
stderr is unrealistic on Linux. Against the shipped tree at `f577e1c` the same check returned
`rc=0`, **stderr empty**, and leaked no `ssh-agent` (2 before, 2 after). This is `CLAUDE.md`'s own
`_OVERRIDE_BATS_BIN` lesson: ship the SHA, because a stale or dirty tree *is* the finding.

**Two measured limits on the Part A check, neither a reason to drop it.** It passes on the
current tree, so as the cited mitigation for a leak the fix has not yet introduced, it cannot
discriminate until A1 lands — its value is regression, not proof.

And on an unprovisioned `HOME` it emits ~398 bytes including a **real network `git clone`**, from
`5_general.zsh:44-46`'s zsh-autosuggestions self-healing branch, which fires whenever
`~/.oh-my-zsh/custom/plugins/zsh-autosuggestions` is absent. The empty-stderr assertion is what
goes red, and the cause named in the output is a clone rather than anything this change touched.

**That scope belongs in the check, not in this paragraph.** A check whose applicability lives only
in prose is one someone runs on a fresh box, reads as a failure, and debugs the wrong thing —
`shell.md`'s own rule that a gate must name its remedy, one level out. Guard on the precondition
rather than on the machine, so the guard stays true if the fleet changes:

```bash
if [[ ! -d ${HOME}/.oh-my-zsh/custom/plugins/zsh-autosuggestions ]]; then
  printf 'SKIPPED: Part A branch check needs a provisioned HOME.\n'
  printf '  5_general.zsh:44-46 clones zsh-autosuggestions when that dir is absent, which\n'
  printf '  writes to stderr and would fail the empty-stderr assertion for an unrelated reason.\n'
  printf '  Remedy: run setup_env.sh -t setup_user, or run this check on studio/workstation.\n'
  exit 0
fi
# ... the check as written above
```

**The skip is bounded by an acceptance criterion, or it is an escape hatch.** On the two
development machines this check must **PASS and never SKIP** — a SKIP there means the box is
unprovisioned, which is itself the finding. The plan carries that as the acceptance wording rather
than accepting either outcome, since a silently-skippable check is one that can be absent
(`behavior.md`: a guard whose output cannot alter what runs after it is not a guard).


## Out of scope

**`Make()`'s gmake hardcode** (`2_functions.zsh:8,12`) stays on the backlog. Its note is
right that removing the hardcode means relying on `PATH`, and this repo has a measured
interaction where a `PATH` prepend inside a hook shadows the test suite's own `make` mock
(28 of 36 tests failed). That needs its own design with the mock interaction planned for.

**`7_final.zsh:60` and `.zprofile:6,10`** are the remaining three read sites and no
backlog row covers them. All three are really "is this host mapped at all" or a capability
question — `7_final.zsh:60` tests all eight variables, which is `PROFILE != unknown`
spelled out longhand; `.zprofile:6` is the five-mac list and `:10` is the Linux pair. A
backlog row is added for them in the same change as this spec, per `behavior.md`'s
Backlog Rows for Deferred Findings.

**The 26 hand-typed isolation and reporting lines** across `tests/zshrc.d/unit.bats` (17),
`tests/zshrc.d/profiles.bats` (4), `tests/zshrc.d/cross_shell.bats` (4) and
`tests/setup_env/profiles.bats` (2) are cut from this spec per Decision 3 and get one backlog
row, added in the same change. Converting them wants a single derived helper sourced by all
four files with a non-emptiness and count-pinned guard in front of the derivation — the guard
is the load-bearing part, since without it an empty derivation is green in CI.

**All gcloud sourcing.** `.zshrc:8,11` is the real owner and `5_general.zsh:129-143` duplicates
it behind a hostname guard with a stale cask token. On ARM the `.zshrc` copy already delivers
both includes unguarded (measured), so the duplicate's guard buys nothing there; on Intel
`.zshrc` no-ops because it hardcodes `/opt/homebrew`, leaving `ratna` served only by the
duplicate. One backlog row, added in the same change. The coherent fix is one owner,
prefix-aware — but `.zshrc` runs *after* the `.zshrc.d` loop, so it cannot reuse
`_homebrew_prefix_arm`/`_intel` (unset at `5_general.zsh:270`), and it has no `_OVERRIDE_*` seam
and no bats coverage today. Its own cycle, not a rider.

**The legacy variables themselves** are not removed. Five read sites survive this work
across three files, so the variables stay. This spec reduces the number of places the
mapping is written, not the number of places it is read.

---

## Risk

| risk                                                                                     | mitigation                                                                                                                                                                                                                                          |
| ---------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| A1 changes a guard in a file every interactive shell sources | `HAS_DEVTOOLS` is set by both `config/profiles.zsh` (zsh) and `lib/detect_env.sh` (bash) for exactly the two Linux profiles `PROFILE_MAP` maps `workstation`/`cruncher` to, so the substitution is behaviour-preserving for every mapped host — confirmed independently by four lenses and re-measured on both fleet bash builds |
| A3's reason string is edited in the wrong direction | it must **keep** naming `5_general.zsh`, because `:131`/`:135` still read `RATNA`/`LAPTOP`/`STUDIO` after A1. A reason that stops naming a live reader reads as "nothing uses this", which is how the variable gets deleted next |
| B2's lookup loses the warning on a drifted table                                         | the warning arm is preserved with an unchanged trigger; B4 adds a negative test for it                                                                                                                                                              |
| B3's `readonly "${legacy}=1"` is an indirect assignment                                  | `legacy` is a lookup from a table whose values are eight fixed identifiers; a hostname cannot inject into it, since the hostname is the _key_, not the value                                                                                        |
| `PROFILE_LEGACY` unset too early in `profiles.zsh`                                       | it joins the existing `unset` at `:85`, after the lookup                                                                                                                                                                                            |
| coverage drops below the 91% floor                                                       | B replaces `case` arms with fewer lines in both instrumented files; net direction is fewer uncovered lines, but the CI figure is the gate and a drop blocks auto-merge                                                                              |

---

## Multi-Lens Review

Reviewed at commit: `4e41a22` (Step 7 self-review commit, before Step 8 dispatch)

Round 1: three lenses, `general-purpose` subagents with no inherited conversation, dispatched
2026-08-17. Two independent convergences resulted, and **both mechanisms were then verified
directly from this session rather than accepted on lens agreement** — three same-model passes
over shared framing agreeing is evidence they were not contradicted, not evidence a claim is
true.

### Goal-Fit

Finding: **A2 preserves a Homebrew cask token this repo retired on 2026-04-30, so it may
enable gcloud completion on zero machines rather than three.** `Brewfile:163` provisions
`cask "gcloud-cli"`; the six path literals in `5_general.zsh:132-140` all name
`Caskroom/google-cloud-sdk`, the pre-rename token. Verified independently in this session:

```
$ ls -ld /opt/homebrew/Caskroom/google-cloud-sdk /opt/homebrew/Caskroom/gcloud-cli
drwxr-xr-x@ 5 bruce admin 160 Aug 15 11:41 /opt/homebrew/Caskroom/gcloud-cli
lrwxr-xr-x@ 1 bruce admin  10 Jul 14  2025 /opt/homebrew/Caskroom/google-cloud-sdk -> gcloud-cli
$ grep -n 'gcloud' Brewfile
163:cask "gcloud-cli"                            # [HAS_DEVTOOLS]
$ grep -c 'Caskroom/google-cloud-sdk' .config/.zshrc.d/5_general.zsh
6
```

The old path resolves on the Studio only through a **rename-compatibility symlink dated
2025-07-14** — created when this machine migrated an existing `google-cloud-sdk` install. A
mac that first installed gcloud after the rename has `Caskroom/gcloud-cli/` and no symlink,
so every literal resolves to nothing and the existence guards make it a silent no-op. This
spec's own measurement ("`/opt/homebrew/Caskroom/google-cloud-sdk` is **present**") was taken
on the one machine in the fleet guaranteed to still carry that symlink, and generalised to the
three machines the change is for — the boundary failure `behavior.md` describes, committed in
a paragraph that names its own population.

The declared method is what made it unreachable: _"Path equivalence is a textual substitution,
checked by reading the current literals rather than by running anything."_ That verifies the
refactor preserves the literal, which was never the question. And every A2 fixture is built
from the same `Caskroom/google-cloud-sdk/...` string under test, so the suite verifies the
guard and can never observe that the path names a retired token — a check derived from the
same decision as the thing it checks.

Reads-it test: passed for every mechanism. `PROFILE_LEGACY` → read by `config/profiles.zsh`
and `lib/detect_env.sh`, changes which of eight variables five surviving read sites see,
durable in a tracked file. `tests/helpers/legacy_oracle.bash` → read by both `profiles.bats`
suites, turns CI red on a drifted table. B5's derived list → changes whether an assertion can
pass on an ambient value. B2's stderr warning changes no verdict and leaves no record, but it
exists today and is preserved rather than added. **No mechanism in this spec is decoration.**

Verdict count: 11 cases, 11 expect PASS, 0 expect a failure. Three pin a specific non-zero
derived value (A2's "2 sources", B5's mutation case, `make test` ≥ 1402), so the suite is not
the pure comparison-only shape — but the gap falls exactly on the finding above.

Assumption: that the three target macs have a `Caskroom/google-cloud-sdk` path at all — i.e.
each carries the rename-compatibility symlink from a pre-2025 install rather than only the
`Caskroom/gcloud-cli` directory a fresh `brew bundle` produces. If false, A2 is pure refactor
and both backlog rows it claims to close stay open. Settled by
`ssh <host> 'ls -ld /opt/homebrew/Caskroom/gcloud-cli /opt/homebrew/Caskroom/google-cloud-sdk'`
on each target.

Disposition: **Addressed** (operator, 2026-08-17). A2 now resolves the Caskroom token by
existence — `gcloud-cli` first, `google-cloud-sdk` as fallback — rather than betting on
either. This removes the assumption instead of measuring it, which matters because neither
target mac is reachable from here to measure. Two verification rows were added, and row 1
(`gcloud-cli` only) is mutation-provable against the actual defect: 0 sources under the
spec's original text, 2 under the revision. The paragraph that declared path equivalence
checkable "by reading rather than by running anything" is deleted, since that method is what
made the defect unreachable.

### Ergonomics

Finding: **B5 converts one hand-typed copy of the eight-name list and leaves the rest,
including the identical line in the sibling bash suite and both lines in the cross-shell
parity suite.** Decision 3's own rationale — "a ninth variable would leave it stale and the
affected assertion would pass on the ambient value" — applies verbatim to every site it does
not touch, one of which sits 14 lines below the line it converts, inside the same function.
Verified independently in this session:

```
$ grep -rc 'LAPTOP STUDIO RECEPTION OFFICE HOMES WORKSTATION CRUNCHER RATNA' --include='*.bats' tests/ | grep -v ':0'
tests/zshrc.d/unit.bats:...
tests/zshrc.d/cross_shell.bats:...
tests/zshrc.d/profiles.bats:...
tests/setup_env/profiles.bats:...
# 26 occurrences across 4 files
```

Three consequences, in cost order: `tests/setup_env/profiles.bats:48` is the same defect in
the sibling suite and the spec never names it — fixing one of an identical pair is the
operator's own "verify one level wider than you fixed"; `profiles.bats:56`'s reporting loop is
the _measurement instrument_ rather than an oracle, so a ninth variable makes the snapshot
omit it and the failure points the next reader at `config/profiles.zsh` instead of at the test
helper; and `cross_shell.bats` is the suite `CLAUDE.md` cites as proving bash and zsh agree, so
a stale isolation line there means the parity claim itself passes on ambient values.

Second finding, on the add-a-machine path: **`CLAUDE.md`'s "Adding a New Machine" section says
"No other file needs changing" after editing `PROFILE_MAP`, and this work makes that wrong in
a new way.** A new hostname will need a `PROFILE_LEGACY` entry (same file) _and_ an arm in
`tests/helpers/legacy_oracle.bash`, or the suite fails. The spec has no documentation task and
no documentation check in Verification; Documentation Currency requires both in the same
change.

Verdict count: 10 expectations, 10 PASS, 0 expecting red. A2's "2 sources" fails on an empty
fixture. **B5's does not** — it is a membership check on a derived list, and nothing pins the
real derived list at eight names. If the bats-level source resolves wrong or the array name is
typo'd, `PROFILE_LEGACY` is empty, the derived `unset` clears nothing, and the per-host
assertion is `grep -qx "LEGACY=..."` (membership, verified at `profiles.bats:173` and
`setup_env/profiles.bats:343`), so extra ambient lines do not fail it. In CI nothing is
ambient, so an empty derivation is **green**; on the Studio it trips only the exact-equality
unmapped-hostname test, and only because that developer's login shell exports `STUDIO=1`. The
one new derived measurement is caught by the operator's own machine and not by the gate —
inverting this repo's "CI is the figure the gate reads" rule.

Assumption: same as Goal-Fit's — that `Caskroom/google-cloud-sdk` resolves on `reception`,
`office` and `home-1`, reached independently and by the same measurement. Two lenses arriving
at one claim from different lenses is why it was verified directly rather than counted twice.

Disposition: **Addressed** (operator, 2026-08-17), on both findings.

The 26-site finding is addressed by **cutting** B5 and Decision 3 rather than widening them —
see the Risk disposition below, which is the same decision. Fixing one of an identical pair
was the objection; shipping neither resolves it without pretending the class is closed.

The documentation finding is addressed by a new **Part C**: `CLAUDE.md`'s "Adding a New
Machine" section and its Testing/Test Seams section are updated in the same change, with a
grep-checked acceptance criterion under "The falsifiable form for C". The lens was right that
the `docs` skill in Phase 3 would have swept this only by luck — that skill is scoped to what
the diff changed, and the stale sentence lives in a section this diff does not touch.

### Risk

Finding: **B5's failure mode outweighs its problem, and Decision 3's count is off by a factor
of 22.** The unset-isolation form appears **22 times** across four test files — 17 in
`tests/zshrc.d/unit.bats` alone — plus 4 more copies in the reporting loops. B5 converts 1 of
22, so the property Decision 3 claims ("exhaustive by construction") is 4.5% achieved while
the reader is told the class is closed.

What that 4.5% costs: B5 replaces a static literal inside a `zsh -c` string with a bash-side
derivation interpolated into it, and the derivation's failure mode is **silent-empty**.
`zsh -c 'L=""; unset ${L}'` emits `unset: not enough arguments` and rc 1 — but that stderr
does not reach `_err_file` (only the `source` is redirected, `profiles.bats:47`), is not
captured by the `snapshot="$(…)"` assignment, and does not change the `zsh -c` exit status. So
a broken source path or renamed table yields _no isolation at all_, quietly, and CI is
structurally incapable of detecting it for the membership-check reason above.

The repo already knows this class: `profiles.bats:121` carries `[ "${#keys[@]}" -gt 0 ]` with a
comment explaining why a derived list needs a non-emptiness guard, and records that a count
comparison was tried there and removed as circular. B5 reintroduces what its neighbour
documents.

Recommendation from the lens: cut B5, or gate it. The scenario it hardens against is a
_ninth_ legacy variable being added, while the direction of this work and of #222 before it is
removing read sites — this spec takes `5_general.zsh` from three to zero. If it stays it must
assert the derived list non-empty and count-pinned against the real table before
interpolation, convert all 22 sites or state plainly that it converts one, and fix Decision 3's
count, since the count is the whole argument.

Checked and explicitly not raised: A1 is genuinely behaviour-preserving (exactly two Linux
profiles, both carrying `devtools`, mapped from exactly `workstation`/`cruncher`; `:77` sits
inside `elif [[ -n ${LINUX} ]]` so macOS `HAS_DEVTOOLS` cannot reach it). Indirect assignment
is safe in both B2 and B3 — `readonly` inside a bash function is global (measured), the
empty-name case errors loudly, both sites guard with `-n` first, and the name position is a
table value never derived from the hostname. `PROFILE_LEGACY` scoping in `detect_env.sh` is
fine, since `config/profiles.sh` is sourced inside `detect_env()` exactly as `PROFILE_MAP`
already is. A2's ARM-first `if/elif` ordering is not a new assumption — `CHRUBY_LOC` at
`:26-31` already uses it. B3's `&&` form returns rc 1 for an unmapped host where the current
`case` returns 0, harmless because the `CHRUBY_LOC` block follows and no caller consumes
`detect_env`'s status.

**That last clause is false and round 2 caught it.** Two harnesses do consume the status —
`tests/setup_env/profiles.bats:57` and `tests/zshrc.d/cross_shell.bats:68`, both
`if ! detect_env; then` (verified). The behaviour is still safe, because the trailing `if`/`elif`
masks the rc, but the safety is *accidental* rather than structural: if that trailing block ever
moves or becomes the function's last statement, two suites go red for an unmapped host. Kept
here rather than silently corrected, because "nobody reads this status" is exactly the kind of
clearance that gets cited later.

Verdict count: 11 cases, 11 PASS, 0 expecting failure; exactly one pins a specific non-zero
derived value. B5's case adds a ninth name to a _fixture_ table and asserts the derived list
contains it — if the derivation against the real `config/profiles.sh` returns empty, that case
still passes and so does everything else.

Assumption: **that `reception`, `office` and `home-1` are ARM macs.** This underlies A2's
headline benefit and cannot be verified from this repo — Intel-vs-ARM is not data in
`config/profiles.sh`, and `office`/`home-1` map to `mac_mini`, a line that was Intel until 2020. If either is Intel, A2's ARM-first `elif` resolves `/usr/local/Caskroom/...` for it; an
Intel mini carrying an empty or unrelated `/opt/homebrew` takes the ARM branch, both guards
fail, and it silently gains nothing while the spec records it as fixed. Settled by
`ssh <host> 'uname -m; ls -d /opt/homebrew'` per machine.

Disposition: **Addressed** on the finding, **Accepted** on the assumption (operator,
2026-08-17).

The finding is addressed in full: **B5 and Decision 3 are cut.** The lens's expected-value
argument holds — the hazard is a ninth legacy variable arriving, while this work removes read
sites — and its measured 22-versus-1 count, plus the silent-empty derivation path that CI
cannot see, were both reproduced from this session before the cut. Decision 3 is rewritten as
the record of why, and all 26 sites go to one backlog row with the guard named.

The assumption — that `reception`, `office` and `home-1` are ARM macs — is **accepted, reason:
A2 introduces no new exposure to it.** The ARM-first `if`/`elif` over the same prefix pair
already shipped in #222 for three other consumers in this same file (`CHRUBY_LOC` at `:26-31`,
`FZF_BASE` at `:38-40`, the keychain binary at `:240-244`). If an Intel mac carrying a stray
`/opt/homebrew` takes the ARM branch, that is a live defect today in chruby, fzf and keychain
resolution — not something A2 creates — so it belongs to whatever change fixes the ordering
for all four consumers, not to this one. Worth noting the direction: A2's own guards fail
closed there (both `.inc` tests miss, nothing is sourced), so the machine gains nothing rather
than sourcing something wrong.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger. There are no arms being
compared, no judge or evaluator component, and acceptance criteria are concrete (mutation-provable
source counts, a CI test count, a CI coverage floor).

### Reachability note on both assumptions

Neither assumption can be settled by measurement from this session. Measured 2026-08-17 on the
Mac Studio:

```
$ ssh -o BatchMode=yes -o ConnectTimeout=4 reception 'uname -m'
ssh: Could not resolve hostname reception: nodename nor servname provided, or not known
# identical for office and home-1
```

`USER.md` records `ssh workstation` as the only cross-machine hop that matters on this fleet;
the three work/mini macs are not directly reachable from here. So both assumptions have to be
**designed away rather than measured** — a resolution that reads whichever Caskroom token
exists, and an ordering that was already shipped in #222 for three other consumers of the same
prefix pair.


---

## Multi-Lens Review — round 2

Reviewed at commit: `688f913` (round-1 revision commit)

Three lenses, fresh `general-purpose` subagents, each told explicitly that the round-1 section
above is **history rather than findings to confirm**, that prior findings must not be assumed
correctly resolved, and to look for defects the revision itself introduced. Round 2 found
strictly worse defects than round 1, including in text round 1 never saw — the token resolver
and Part C did not exist when round 1 ran. Every finding below was verified from the main
session before being acted on.

### Goal-Fit

Finding: **the round-1 correction is built on the wrong path.** `Caskroom/<token>/latest/google-cloud-sdk`
is a symlink to a symlink onto `${HOMEBREW_PREFIX}/share/google-cloud-sdk`, which the cask
declares at line 11 and copies the SDK into at line 58. Line 64 is upstream's own comment
calling `latest` a `# HACK` that exists so shell profiles like this one keep working; line 98
trashes it on uninstall; the cask's caveat text points users at `google_cloud_sdk_root`. So the
revision hardened against one Homebrew shim while depending on another one level below it — the
same defect shape it was written to fix, one path segment along, found only because a lens read
the cask instead of the spec.

Second finding: **Decision 2's operator approval was obtained against a false statement.**
"`ratna` newly sources `path.zsh.inc`, putting the gcloud CLI on its `PATH`" — the CLI is
already there as cask `binary` artifacts (`/opt/homebrew/bin/gcloud` → the versioned SDK bin),
and `path.zsh.inc` is 31 bytes whose only delta is four unlinked auxiliaries. Completion-only
closes the actual backlog row with no `PATH` mutation and needs no approval.

Also confirmed the defect is real and not solved elsewhere: Homebrew symlinks
`completion.zsh.inc` into `share/zsh/site-functions/_google_cloud_sdk`, but the file's first
line is `autoload -U +X bashcompinit` with no `#compdef`, so `compinit` leaves `_comps[gcloud]`
as `NONE` — the manual `source` is genuinely required.

Reads-it test: all mechanisms pass. One near-miss noted and acted on — the `_gcloud_root=` reset
had a justifying paragraph citing `logic-review.md` for an ambient value of a `_`-prefixed
variable the same diff invents. Line kept (now `_gcloud_prefix`), paragraph dropped.

Verdict count: 18 cases, 18 PASS, 0 red; two pinned an empty measurement. Structural gap: all
A2 cases drove the resolver through a temp-dir seam, so the suite could prove the algorithm
handled four enumerated layouts and never that the enumerated family was the right one — round
1's finding relocated one level down, which is what the cask measurement showed had happened.

Assumption: that `gcloud-cli` is installed at all on `office` and `home-1`, sizing A2's benefit
at three machines versus one. Unreachable by `ssh`; `state-ledger/packages/` holds no capture
for any target host.

Disposition: **Addressed** (operator, 2026-08-17). A2 adopts `${prefix}/share/google-cloud-sdk`
— one guard, one source, no loop, no token, no fallback — and drops `path.zsh.inc` for
completion-only on both arms. The four-row token matrix collapses to two plus a
`path.zsh.inc`-not-sourced case. The assumption is addressed by **restating the claim at its
boundary** rather than measuring it: A2 delivers to "every ARM mac with the SDK installed", at
most three, unmeasurable from here — and the closed backlog row is reworded to match. A2's
guards make the difference inert either way.

### Ergonomics

Finding: **C1's premise was inverted.** `CLAUDE.md:623`'s "No other file needs changing" is
wrong *now*, not after this work — reproduced by following the documented procedure literally in
a `git archive` copy and watching both suites fail. A new machine costs 5 edits across 5 files
today against a doc claiming one; this work takes it to 3 across 2, so it makes the sentence
less wrong. And C's own acceptance check pinned a sentence whose premise is refuted, so it would
have failed a reviewer who correctly rewrote it.

Second finding: **B4 ships three stale operator-facing strings.** The oracle's failure messages
are in the callers (`profiles.bats:142`, `setup_env/profiles.bats:339`), one line below the call
B4 updates, and each hardcodes the oracle's function name and file; the zsh one also directs the
reader at "`config/profiles.zsh`'s own case statement", which B2 deletes. This is the class A3
exists to prevent, on a string an operator reads while debugging. Nothing exercises the oracle's
`*) return 1` arm either — all 13 keys have arms — so the stale strings are undetectable by
construction.

Verdict count: 17 cases, 17 PASS, 0 red.

Assumption: same as Goal-Fit's, reached independently — whether the two `mac_mini` hosts carry
the SDK, given `Brewfile:163` tags it `[HAS_DEVTOOLS]` while `lib/macos.sh:193` installs the
main Brewfile unconditionally.

Disposition: **Addressed** (operator, 2026-08-17). Part C is rewritten to lead with the
corrected premise and the 5→3 arithmetic, and grows from two items to four: `CLAUDE.md:623`,
`config/profiles.sh:4` (the same claim inside the diff's own hunk), `config/profiles.sh:6`'s
"both maps below" `SC2034` reason, and `CLAUDE.md`'s Testing section. The inert grep is replaced
with stated expected values including two `0` expectations, which are the only form that
distinguishes corrected from untouched. B4a moves both messages into the helper; B4b adds the
fixture case that reaches the `*) return 1` arm.

### Risk

Finding: converged independently on the cask root, adding that only 2 of 61 installed casks on
this machine carry a `latest` symlink at all, and both are this one cask under its two tokens.
It also ran the round-1 A2 snippet under real zsh 5.9.2 against four fixture layouts and
confirmed the mechanism worked as written, leaked nothing, and discarded an ambient value — so
the finding is proportionality, not correctness.

Second finding: **two verification checks were inert, both in unreviewed new text.** The branch
re-source check never sources `5_general.zsh` — `1_init.zsh` ends at `source config/profiles.zsh`
and `.zshrc:3` is the loop — so it covered Part B and zero percent of Part A, while being
presented as a whole-branch guard. Verified: after that command `PROFILE=mac_workstation` but
`AWS_HOME` and `GPG_TTY` are `UNSET`. And Part C's third grep returned 1 before any work with no
stated expectation.

Third finding: **Part C missed `config/profiles.sh:4`**, four lines above `PROFILE_LEGACY`'s
insertion point, carrying the same false claim — the copy in the file the operator is already
editing. Plus `:6`'s "both maps below", which B1 makes three.

Fourth: **one round-1 claim was false** — `detect_env`'s status *is* consumed, by
`tests/setup_env/profiles.bats:57` and `tests/zshrc.d/cross_shell.bats:68`. Safe, but
accidentally so. Corrected in place in the round-1 record above rather than quietly deleted.

Verdict count: 23 assertions, 23 green, 0 red; two discriminated an empty measurement, one had
no stated expectation at all.

Checked and not raised: A1 behaviour-preserving (again, third independent confirmation);
`readonly "${legacy}=1"` global inside a function and loud on an empty name, with the current
`case` having identical double-invocation behaviour; prefix scope correct; `PROFILE_LEGACY`
scoping matches `PROFILE_MAP`'s; Decision 3's cut leaves nothing dangling; every line and grep
count in the spec accurate to `688f913`.

Assumption: that Homebrew keeps maintaining `Caskroom/gcloud-cli/latest` as a valid symlink
indefinitely — which A2 depended on entirely and the declared root depends on not at all.

Disposition: **Addressed** (operator, 2026-08-17). The assumption is deleted rather than
answered: adopting `share/google-cloud-sdk` removes the dependency on the shim. The inert Part A
check is replaced with one that runs `.zshrc`'s own loop and asserts `AWS_HOME` — the assertion
that makes it falsifiable, since without it the check passes on a shell that never sourced the
file under test. Part B's check stays as `CLAUDE.md` documents it, now labelled with the scope it
actually covers. `config/profiles.sh:4` and `:6` are C2 and C3.

### Adversarial Spec Review (comparison/judge designs only)

N/A — unchanged from round 1. No comparison arms, no judge or evaluator component, concrete
acceptance criteria.

### Stopping assessment

**Not stopping on round 2.** The skill's stopping signal is that a round's findings all sit in
text the previous round already read. Round 2 fails that test twice over: the token resolver and
Part C were both created *by* the round-1 correction, and the two inert verification checks were
new text. Round 3 is scoped rather than full — the body is materially the same for Parts A1, B1–B4
and the Out-of-scope reasoning, all of which have now been independently confirmed three times
each, while Decision 2, A2, Part C and the two verification checks are new since any lens read
them.


---

## Multi-Lens Review — round 3 (scoped)

Reviewed at commit: `f577e1c` (round-2 revision commit)

**Scoped, not full**, per the skill's stopping guidance: one Risk lens pointed at the eight
things rewritten since any lens had read them — Decision 2, A2, Part C's four items, both
verification checks, B4a/B4b, the Risk table and the re-scoped Problem statement. A1, Decision 1,
B1–B4's core and the Out-of-scope reasoning were excluded as independently confirmed three times
each, with the lens told explicitly to say so if it believed a prior confirmation was wrong.

### Risk (scoped)

Finding: **`.zshrc:8,11` already sources both gcloud `.inc` files from the same declared root A2
adopts, with no hostname guard, on every mac.** `.zshrc` is 12 lines; round 2 cited `:3` as the
`.zshrc.d` loop and stopped five lines short. Verified from the main session on a shell with
`hostname` mocked to `reception`: completion **ABSENT** after the `.zshrc.d` loop, **LOADED**
after `.zshrc:8,11`; SDK `bin` absent from `PATH` then present.

Three consequences: A2's benefit reaches **zero** ARM machines, so the "three work macs" framing
is refuted and re-scoping the claim twice had narrowed the machine count while naming the wrong
*file* boundary. The Risk row asserting `laptop`/`studio` would lose four auxiliaries is
**false** — `.zshrc:8` puts SDK `bin` on `PATH` unconditionally on ARM — meaning the operator's
*second* approval was obtained against a second false description of the same line. And A2's only
live effect was on `ratna`, an Intel host unreachable by `ssh`, to which none of Decision 2's
evidence applied since every measurement behind it was taken under ARM `/opt/homebrew`.

Mechanism: this spec's own declared population, `grep -rn` over
`--include='*.zsh' --include='*.sh' --include='*.bats'` plus `.zprofile`. `--include='*.zsh'`
does not match `.zshrc` — 0 hits against that file's 2 real lines. `shell.md`'s pathspec pitfall,
inside the methodology paragraph, third premise failure in the same position.

Second finding: the round-2 reversal left A2's verification prose contradicting its own table —
unedited round-1 text still said "both files are sourced" and "2 sources" ten lines above a table
saying `1 sourced` plus a case requiring `path.zsh.inc` **not** sourced. An implementer reading
top-down writes the wrong assertion. That contradiction survived a full lens round unflagged.

Verdict count: ~22 cases, 22 PASS, 0 red; fail-on-empty coverage genuinely present in five
places, and Part C's two `0` expectations both measured as returning `1` today, so they
discriminate correctly. Structural gap one level up: every case measured whether *`5_general.zsh`*
sources the file, while nothing measured whether an interactive shell ends up with completion —
so the suite drew the same subject boundary the problem statement drew and could only confirm it.

Checked and not raised: the A2 snippet is correct across six fixture layouts under real zsh
(right file every time, ambient value discarded, nothing leaked, `\` inside `[[ ]]` parses, rc 0,
`zsh -n` clean); the Part A check runs rc 0 with empty stderr and leaks no `ssh-agent`; B4a/B4b
are sound and sit outside `_profiles_snapshot`'s `zsh -c`; the cask-root claim survives a
staleness check (`google_cloud_sdk_root` predates the 2026-07-20 `copy` refactor); the compinit
claim measures `_comps[gcloud]=NONE`.

Assumption: that `/usr/local/share/google-cloud-sdk/completion.zsh.inc` exists on `ratna` — the
only machine A2 changed, and the whole of what A2 did. If absent, A2 **removes** completion that
works there today.

Disposition: **Addressed** (operator, 2026-08-17) — by cutting the gcloud work entirely. A2 and
Decision 2 are removed; A1, Part B and Part C ship. The `ratna` assumption is deleted rather than
answered, since nothing changes on that host. `.zshrc:8,11` versus `5_general.zsh:129-143` becomes
one backlog row naming `.zshrc` as the real owner, with the two constraints a future cycle needs:
`.zshrc` runs after the `.zshrc.d` loop so `_homebrew_prefix_*` is already unset, and it has no
test seam. A3 is rewritten in the opposite direction — the `SC2034` reason strings must **keep**
naming `5_general.zsh`, because `:131`/`:135` still read three legacy variables after A1.

### Adversarial Spec Review (comparison/judge designs only)

N/A — unchanged across all three rounds. No comparison arms, no judge or evaluator component,
concrete acceptance criteria.

### Stopping assessment

**Stopping here.** The remaining scope — A1, Part B, Part C — has been read by four independent
lenses across three rounds with no finding against A1 or Decision 1 in any of them, and B1–B4's
only findings (B4a's stale strings, B4b's unexercised arm) are addressed. What round 3 found lived
entirely in the gcloud work, and that work is now out of the spec rather than corrected again.

Three rounds were not excessive and the yield did not decay: round 1 found a stale cask token,
round 2 found the resolver built to fix it was aimed at a symlink, round 3 found the whole
mechanism was redundant with a file five lines away. Each round's finding was in text the previous
round's *correction* created — which is the shape the skill warns about, observed three times in
one spec.

The honest summary is that the surviving spec is the half review never had a problem with, and
the half it kept rejecting is gone. That is the correct outcome, not a diminished one.
