# zsh legacy-identity consolidation — design

Date: 2026-08-17
Repo: dotfiles
Backlog rows closed: "five hostname reads survive in `5_general.zsh` — rbenv and gcloud",
"gcloud completion absent on three work macs", "hostname→legacy-variable lives in four tables"

---

## Problem

Two independent residues of the 2026-08-16 zsh-identity work (#222).

**1. `.config/.zshrc.d/5_general.zsh` still reads legacy identity variables at three
sites.** That PR converted this file's `CHRUBY_LOC`, `FZF_BASE` and keychain blocks from
hostname tests to capability or Homebrew-prefix tests, and left three:

| site   | current test                                        | the question it is really asking |
| ------ | --------------------------------------------------- | -------------------------------- |
| `:77`  | `[[ -n ${WORKSTATION} ]] \|\| [[ -n ${CRUNCHER} ]]` | is this a Linux dev box?         |
| `:131` | `[[ ${RATNA} ]]`                                    | is this an Intel mac?            |
| `:135` | `[[ ${LAPTOP} ]] \|\| [[ ${STUDIO} ]]`              | is this an ARM mac?              |

The `:131`/`:135` pair is also a live defect: `reception`, `office` and `home-1` are ARM
macs with the same Homebrew prefix as `studio` and `laptop`, and they are absent from the
`:135` list, so they source neither `path.zsh.inc` nor `completion.zsh.inc` and get no
gcloud completion at all. The fix newly enables completion on three machines, which is why
it was held out of #222 rather than folded in. **The operator approved that behaviour
change on 2026-08-17**, along with the fourth machine's change described under Decision 2.

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

## Read-site census (measured 2026-08-17)

Every site outside the four tables that reads one of the eight legacy identity variables:

| file                               | sites                     | in scope here             |
| ---------------------------------- | ------------------------- | ------------------------- |
| `.config/.zshrc.d/5_general.zsh`   | 3 (`:77`, `:131`, `:135`) | **yes**                   |
| `.config/.zshrc.d/2_functions.zsh` | 2 (`:8`, `:12`)           | no — separate backlog row |
| `.config/.zshrc.d/7_final.zsh`     | 1 (`:60`)                 | no — see Out of scope     |
| `.zprofile`                        | 2 (`:6`, `:10`)           | no — see Out of scope     |

After this work `5_general.zsh` reads **zero** legacy identity variables and five sites
remain across three files. The variables themselves are therefore still required; this
spec does not remove them and does not claim to.

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

### Decision 2 — the gcloud block becomes symmetric

Today the two arms differ: ARM sources `path.zsh.inc` **and** `completion.zsh.inc`; the
Intel (`RATNA`) arm sources `completion.zsh.inc` only. Collapsing to a single
prefix-derived root forces a choice.

**Chosen: symmetric — one root, both `.inc` files, each existence-guarded.** `ratna` newly
sources `path.zsh.inc`, putting the gcloud CLI on its `PATH`; operator-approved
2026-08-17. The asymmetry has no recorded reason and preserving it would mean carrying an
extra branch a future reader has to find a justification for.

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

**A2. gcloud block, `:129-143`.** Replace the two hostname arms with one prefix-derived
root:

```zsh
if [[ ${MACOS} ]]; then
  _gcloud_prefix=
  [[ -d ${_homebrew_prefix_arm} ]] && _gcloud_prefix="${_homebrew_prefix_arm}"
  [[ -z ${_gcloud_prefix} && -d ${_homebrew_prefix_intel} ]] && _gcloud_prefix="${_homebrew_prefix_intel}"

  # gcloud-cli first: google-cloud-sdk is the pre-2026-04-30 cask token and
  # survives only as a Homebrew rename symlink on machines that migrated an
  # existing install. A mac provisioned from the current Brewfile has only
  # gcloud-cli. Probing both means neither vintage is a silent no-op.
  _gcloud_root=
  if [[ -n ${_gcloud_prefix} ]]; then
    for _gcloud_token in gcloud-cli google-cloud-sdk; do
      if [[ -d ${_gcloud_prefix}/Caskroom/${_gcloud_token}/latest/google-cloud-sdk ]]; then
        _gcloud_root="${_gcloud_prefix}/Caskroom/${_gcloud_token}/latest/google-cloud-sdk"
        break
      fi
    done
  fi

  if [[ -n ${_gcloud_root} ]]; then
    [[ -f ${_gcloud_root}/path.zsh.inc ]]       && source "${_gcloud_root}/path.zsh.inc"
    [[ -f ${_gcloud_root}/completion.zsh.inc ]] && source "${_gcloud_root}/completion.zsh.inc"
  fi
  unset _gcloud_prefix _gcloud_root _gcloud_token
fi
```

The inner directory name stays `google-cloud-sdk` under both tokens — that is the SDK's own
layout inside the cask, not the cask token, and Homebrew did not rename it. Only the
`Caskroom/<token>` segment moved.

`_homebrew_prefix_arm` / `_homebrew_prefix_intel` are assigned at `:23-24` and unset at
`:270`, so both are in scope at `:131`. Reusing them rather than introducing a third
prefix literal is required by that pair's own contract comment (`:12-22`): the seam **is**
the Homebrew prefix, and every consumer derives its path from it. The `_OVERRIDE_HOMEBREW_
PREFIX_ARM` / `_INTEL` test seams therefore cover this block for free.

The explicit `_gcloud_root=` reset is not cosmetic: without it an ambient `_gcloud_root`
from the invoking environment survives a mac where neither prefix directory exists, and the
`-n` guard then sources from a path nothing in this file chose (`logic-review.md` item 3,
stale state across branches).

**The cask token is the reason A2 is not a pure guard swap, and it was found by review
rather than by this spec (revised after round 1).** The original text preserved the six
`Caskroom/google-cloud-sdk` literals character-for-character and justified that by reading
them rather than running anything — "path equivalence is a textual substitution". That
verifies the refactor preserves the literal, which was never the question. The literal names
a cask token this repo retired on 2026-04-30:

```
$ grep -n 'gcloud' Brewfile
163:cask "gcloud-cli"                            # [HAS_DEVTOOLS]
$ ls -ld /opt/homebrew/Caskroom/google-cloud-sdk /opt/homebrew/Caskroom/gcloud-cli
drwxr-xr-x@ 5 bruce admin 160 Aug 15 11:41 /opt/homebrew/Caskroom/gcloud-cli
lrwxr-xr-x@ 1 bruce admin  10 Jul 14  2025 /opt/homebrew/Caskroom/google-cloud-sdk -> gcloud-cli
```

The old path resolves on this machine only through a **rename-compatibility symlink dated
2025-07-14**, created when the Studio migrated an existing `google-cloud-sdk` install. A mac
that first installed gcloud after the rename has `Caskroom/gcloud-cli/` and no symlink, so
every literal resolves to nothing and the existence guards turn A2 into a silent no-op — on
exactly the three machines whose newly-enabled completion is A2's entire benefit.

The spec's original measurement said `/opt/homebrew/Caskroom/google-cloud-sdk` is "present",
which was true, taken on the one machine in the fleet guaranteed to still carry that symlink,
and then generalised to three machines it was not measured on. `behavior.md`'s boundary rule,
violated in a paragraph that named its own population.

Neither target mac is reachable to settle it — `reception`, `office` and `home-1` do not
resolve from the Studio (measured; `USER.md` records `ssh workstation` as the only
cross-machine hop on this fleet). So the token is **designed away rather than measured**: the
resolver above probes `gcloud-cli` first and falls back to `google-cloud-sdk`, which is
correct on a fresh install, on a migrated install, and on a machine carrying only the old
directory. Fixing the `Brewfile`-to-zsh drift left by `8b52490` is in scope here because A2
cannot deliver its stated benefit otherwise; it is the deliverable, not an adjacent tidy-up.

Prefix equivalence to the current literals still holds by substitution: ARM
`${_homebrew_prefix_arm}` = `/opt/homebrew` reproduces `:136`/`:139`; Intel
`${_homebrew_prefix_intel}` = `/usr/local` reproduces `:132`. The check that this holds at
runtime is the fixture test below, not this paragraph.

The `UBUNTU` arm at `:144-148` reads no hostname and is untouched.

**A3. `SC2034` reason strings.** After A1 and A2, `5_general.zsh` reads no legacy identity
variable, so the reader lists in `lib/detect_env.sh:51` and `config/profiles.zsh:6-10`
(and `config/profiles.zsh`'s header at `:4-10`) must drop it in the same commit. This
repo's shellcheck convention requires a suppression's reason to name the mechanism; a
reason naming a file that no longer reads the variable is worse than a bare directive,
because it stops the next reader checking. `2_functions.zsh`, `7_final.zsh` and
`.zprofile` remain correct entries in those lists.

### Part B — `PROFILE_LEGACY`

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

**B5 — cut after round 1 of review; see Decision 3.** The derived-isolation task is not part
of this spec. `_profiles_snapshot`'s `unset` line and the other 25 hand-typed occurrences are
left exactly as they are, and go to one backlog row together. Nothing in Part B touches test
isolation; B4 changes only which file the oracle lives in.

### Part C — documentation

**C1. `CLAUDE.md`, "Adding a New Machine".** That section currently ends "No other file needs
changing — `lib/detect_env.sh` and `config/profiles.zsh` both derive `PROFILE`/`HAS_*`/the
legacy identity variables from this one table." After B1–B4 that is wrong in a new way: a new
hostname needs a `PROFILE_MAP` entry **and** a `PROFILE_LEGACY` entry (same file, so the
"no other file" claim survives for production) **and** an arm in
`tests/helpers/legacy_oracle.bash`, or the suite fails on the next run with the oracle's
`*) return 1` message.

Both maps and the oracle arm must be named in the step list, with the wired/wireless twin rule
applying to `PROFILE_LEGACY` exactly as it does to `PROFILE_MAP`. The failure mode is worth
stating in that section too, since it is the one an operator will actually hit: a missing
oracle arm fails the suite, while a missing `PROFILE_LEGACY` entry only warns to stderr at
login.

**C2. `CLAUDE.md`, Test Seams / Testing.** Name `tests/helpers/legacy_oracle.bash` and state
that it is deliberately hand-typed rather than derived from `PROFILE_LEGACY` — otherwise the
next reader "fixes" it into the circular form Decision 1 rejected, and the repo's own
`behavior.md` rule is the only thing standing between them and a green `[home-1]=HOME`.

This is not closeout paperwork deferred to the `docs` skill in Phase 3. That skill is scoped
to what the diff changed, and the stale sentence lives in a section this diff does not touch —
so it would be swept only by luck. Documentation Currency puts it in the same change.

---

## Verification

### The falsifiable form for A2

The new gcloud code reads no hostname, so there is no hostname to fake. The test asserts
the absence of the hostname dependency instead: with `_OVERRIDE_HOMEBREW_PREFIX_ARM`
pointed at a fixture directory containing both `.inc` files and **every legacy identity
variable unset** — the state a `reception` shell is in — both files are sourced.

- Under the new code: 2 sources.
- Under the current code: 0 sources, because `:135` requires `LAPTOP` or `STUDIO`.

Mutation-provable in both directions. A second case with `_OVERRIDE_HOMEBREW_PREFIX_ARM`
absent and `_OVERRIDE_HOMEBREW_PREFIX_INTEL` pointed at a fixture asserts the Intel arm
reaches both files too, which is the assertion that pins Decision 2 rather than the
comparison.

**Two token cases, added after round 1 — these are the cases that would have caught the
retired-token defect, and the original A2 suite could not.** Every original fixture was built
from the same `Caskroom/google-cloud-sdk/...` string that was under test, so the suite could
verify the guard and never observe that the path named a retired token: a check derived from
the same decision as the thing it checks.

| fixture Caskroom layout         | old literal | new resolver | represents                |
| ------------------------------- | ----------- | ------------ | ------------------------- |
| `gcloud-cli/latest/` only       | 0 sources   | 2 sources    | fresh `brew bundle`       |
| `google-cloud-sdk/latest/` only | 2 sources   | 2 sources    | pre-rename install        |
| both (symlink shape)            | 2 sources   | 2 sources    | migrated mac, e.g. Studio |
| neither                         | 0 sources   | 0 sources    | gcloud not installed      |

Row 1 is the load-bearing one: it fails under the spec's original text and passes under the
revision, so it is mutation-provable against the actual defect rather than against the guard.
Row 4 pins that the resolver does not source anything when nothing is installed — the empty
measurement, which otherwise no case in this suite would distinguish from success.

The fixture must be a temp directory, never a real Homebrew prefix. Measured 2026-08-17 on
the Mac Studio (`studio`, ARM, one machine — not a fleet claim):
`/opt/homebrew/Caskroom/gcloud-cli` is a real directory,
`/opt/homebrew/Caskroom/google-cloud-sdk` is a symlink to it dated 2025-07-14, and
`/usr/local/Caskroom/` carries neither. So a test that forgets to override the ARM seam
short-circuits the guard and asserts nothing on every ARM mac — and worse, it would read the
symlink and make row 1 unreachable, which is exactly how the defect survived. The same
omission on the Intel seam fails for a different wrong reason. Both prefixes get fixtures;
no test reads a real one.

### The falsifiable form for A1

`_OVERRIDE_RBENV_BINARY` pointed at a mock, with `HAS_DEVTOOLS=1` and with it unset, on a
simulated `LINUX`+`NOBLE` shell: the mock is invoked in the first case and not in the
second. Both arms asserted, per `logic-review.md` item 6.

### The falsifiable form for B

- The two existing per-host assertions (`tests/zshrc.d/profiles.bats`,
  `tests/setup_env/profiles.bats`) keep passing against the shared oracle, which now
  genuinely falsifies `PROFILE_LEGACY` rather than a co-located `case`.
- A negative case for B2's warning arm: a `PROFILE_MAP` key with no `PROFILE_LEGACY` entry
  produces the stderr line. Constructed by sourcing a fixture `profiles.sh`, not by
  editing the real one.
- No B5 case — B5 is cut (Decision 3). Test isolation is untouched by this spec.

### The falsifiable form for C

`CLAUDE.md`'s "Adding a New Machine" section names `PROFILE_LEGACY` and
`tests/helpers/legacy_oracle.bash`, and its worked example carries a `PROFILE_LEGACY` pair
alongside the `PROFILE_MAP` pair. Checked by grep in the same commit, not by reading:

```bash
grep -c 'PROFILE_LEGACY' CLAUDE.md          # >= 2 (step list + example)
grep -c 'legacy_oracle' CLAUDE.md           # >= 1
grep -c 'No other file needs changing' CLAUDE.md   # the old sentence, revised not deleted
```

The third is the one that matters: that sentence stays true for production files and becomes
false for the test oracle, so it must be qualified rather than removed.

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

The re-source check must source the branch's own files, not `zsh -i -c 'exit'`. From a
worktree `~/.zshrc` and `~/.config/.zshrc.d` are symlinks into the main checkout, so an
interactive shell reads the unmodified files and returns 0 regardless of the branch —
measured during #222, where the worktree carried a new `source` line the main checkout had
zero occurrences of and `zsh -i -c exit` passed throughout.

```bash
zsh -c 'unset -m "HAS_*"; source .zprofile; source .config/.zshrc.d/1_init.zsh; [[ -n ${PROFILE} ]]'
```

`config/profiles.sh` and `lib/detect_env.sh` are both in the bash-coverage instrumented
set (`config/*.sh`, `lib/*.sh` derived from `git ls-files`), so B moves the coverage
figure and the gate reads it.

---

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

**The legacy variables themselves** are not removed. Five read sites survive this work
across three files, so the variables stay. This spec reduces the number of places the
mapping is written, not the number of places it is read.

---

## Risk

| risk                                                                                     | mitigation                                                                                                                                                                                                                                          |
| ---------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| A2 newly sources `path.zsh.inc` on four macs, altering `PATH`                            | existence-guarded; `path.zsh.inc` is Google's own file and is what ARM macs already source. Operator-approved.                                                                                                                                      |
| B2's lookup loses the warning on a drifted table                                         | the warning arm is preserved with an unchanged trigger; B4 adds a negative test for it                                                                                                                                                              |
| B3's `readonly "${legacy}=1"` is an indirect assignment                                  | `legacy` is a lookup from a table whose values are eight fixed identifiers; a hostname cannot inject into it, since the hostname is the _key_, not the value                                                                                        |
| `PROFILE_LEGACY` unset too early in `profiles.zsh`                                       | it joins the existing `unset` at `:85`, after the lookup                                                                                                                                                                                            |
| coverage drops below the 91% floor                                                       | B replaces `case` arms with fewer lines in both instrumented files; net direction is fewer uncovered lines, but the CI figure is the gate and a drop blocks auto-merge                                                                              |
| A2's token resolver picks the wrong vintage on an unreachable mac                        | it probes both tokens and takes the first that exists, so no machine depends on which one it has. The loop is bounded at two literal tokens — not a glob over `Caskroom/`, which would newly source from any cask whose name happened to sort first |
| A2's resolver runs a 2-iteration loop plus 2 `-d` tests on every interactive shell start | four `stat` calls at most, on a path the shell already touches for the `.inc` guards; the `-o interactive` cost profile of this file is dominated by the keychain block further down, which forks a binary per key                                  |
| `_gcloud_prefix` / `_gcloud_token` leak into the user's shell                            | both join the `unset` on the last line of the block, alongside `_gcloud_root`; verified by the branch re-source check, which would show them in `typeset` output                                                                                    |

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
