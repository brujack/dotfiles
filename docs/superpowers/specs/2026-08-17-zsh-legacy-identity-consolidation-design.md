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

### Decision 3 — isolation is derived, the oracle is not

`tests/zshrc.d/profiles.bats:42` hand-types the eight variable names in a `unset` line
inside the `zsh -c` body. It is a **fifth** copy of the name list, and it is not an oracle
— it exists so an ambient `STUDIO=1` from the developer's own login shell cannot satisfy
an assertion that should fail. A ninth variable would leave it stale and the affected
assertion would pass on the ambient value.

Isolation must cover whatever the table can possibly set, so **derive that list from
`PROFILE_LEGACY`**. This is not a contradiction of Decision 1: an oracle states what the
answer should be and must be independent; isolation states what must be cleared and must
be exhaustive. Deriving the second from the table makes it exhaustive by construction.

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
  _gcloud_root=
  if [[ -d ${_homebrew_prefix_arm} ]]; then
    _gcloud_root="${_homebrew_prefix_arm}/Caskroom/google-cloud-sdk/latest/google-cloud-sdk"
  elif [[ -d ${_homebrew_prefix_intel} ]]; then
    _gcloud_root="${_homebrew_prefix_intel}/Caskroom/google-cloud-sdk/latest/google-cloud-sdk"
  fi
  if [[ -n ${_gcloud_root} ]]; then
    [[ -f ${_gcloud_root}/path.zsh.inc ]]       && source "${_gcloud_root}/path.zsh.inc"
    [[ -f ${_gcloud_root}/completion.zsh.inc ]] && source "${_gcloud_root}/completion.zsh.inc"
  fi
  unset _gcloud_root
fi
```

`_homebrew_prefix_arm` / `_homebrew_prefix_intel` are assigned at `:23-24` and unset at
`:270`, so both are in scope at `:131`. Reusing them rather than introducing a third
prefix literal is required by that pair's own contract comment (`:12-22`): the seam **is**
the Homebrew prefix, and every consumer derives its path from it. The `_OVERRIDE_HOMEBREW_
PREFIX_ARM` / `_INTEL` test seams therefore cover this block for free.

The explicit `_gcloud_root=` reset is not cosmetic: without it an ambient `_gcloud_root`
from the invoking environment survives a mac where neither prefix directory exists, and the
`-n` guard then sources from a path nothing in this file chose (`logic-review.md` item 3,
stale state across branches).

Path equivalence is a textual substitution, checked by reading the current literals rather
than by running anything: ARM `${_homebrew_prefix_arm}` = `/opt/homebrew` reproduces
`:136`/`:139` character-for-character; Intel `${_homebrew_prefix_intel}` = `/usr/local`
reproduces `:132`. The runtime check that this actually holds is the fixture test below,
not this paragraph.

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

**B5. Derived isolation.** `_profiles_snapshot`'s `unset` line
(`tests/zshrc.d/profiles.bats:42`) stops hand-typing the eight names and derives them from
`PROFILE_LEGACY` — source `config/profiles.sh` in the bats-level helper, build the sorted
unique value list, and interpolate it into the `zsh -c` body. `unset -m 'HAS_*'` and
`PROFILE` stay as they are; only the eight explicit names become derived.

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

The fixture must be a temp directory, never a real Homebrew prefix. Measured 2026-08-17 on
the Mac Studio (`studio`, ARM, one machine — not a fleet claim):
`/opt/homebrew/Caskroom/google-cloud-sdk` is **present**,
`/usr/local/Caskroom/google-cloud-sdk` is **absent**. So a test that forgets to override the
ARM seam short-circuits the guard and asserts nothing on every ARM mac, while the same
omission on the Intel seam would fail for the wrong reason — the absolute-path-defeats-the-stub
failure `shell.md` records, and what the existing `_gnubin_absent`/`_gnubin_present` helpers
exist for. Both prefixes get fixtures; neither test reads a real one.

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
- B5 is verified by mutation: add a ninth name to `PROFILE_LEGACY`'s values in a fixture
  and confirm the derived `unset` list contains it.

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

**The legacy variables themselves** are not removed. Five read sites survive this work
across three files, so the variables stay. This spec reduces the number of places the
mapping is written, not the number of places it is read.

---

## Risk

| risk                                                          | mitigation                                                                                                                                                             |
| ------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| A2 newly sources `path.zsh.inc` on four macs, altering `PATH` | existence-guarded; `path.zsh.inc` is Google's own file and is what ARM macs already source. Operator-approved.                                                         |
| B2's lookup loses the warning on a drifted table              | the warning arm is preserved with an unchanged trigger; B4 adds a negative test for it                                                                                 |
| B3's `readonly "${legacy}=1"` is an indirect assignment       | `legacy` is a lookup from a table whose values are eight fixed identifiers; a hostname cannot inject into it, since the hostname is the _key_, not the value           |
| `PROFILE_LEGACY` unset too early in `profiles.zsh`            | it joins the existing `unset` at `:85`, after the lookup                                                                                                               |
| coverage drops below the 91% floor                            | B replaces `case` arms with fewer lines in both instrumented files; net direction is fewer uncovered lines, but the CI figure is the gate and a drop blocks auto-merge |
