# zsh Legacy-Identity Consolidation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Retire the last `WORKSTATION`/`CRUNCHER` read in `5_general.zsh`, and collapse the hostname→legacy-variable mapping from four hand-typed copies to one production table plus one deliberately independent test oracle.

**Architecture:** `config/profiles.sh` gains a third map, `PROFILE_LEGACY`, read by both production resolvers (`config/profiles.zsh` for zsh, `lib/detect_env.sh` for bash) in place of their `case` statements. Both test suites' per-suite oracles collapse into one hand-typed `tests/helpers/legacy_oracle.bash`, which stays independent of the table by construction so it can still falsify it. The rbenv guard at `5_general.zsh:77` becomes a capability test.

**Tech Stack:** zsh 5.9+, bash 5.2+, bats-core, `make lint` (bash -n / zsh -n / shellcheck), PS4-tracer bash coverage.

**Spec:** [2026-08-17-zsh-legacy-identity-consolidation-design.md](../specs/2026-08-17-zsh-legacy-identity-consolidation-design.md) — three Multi-Lens Review rounds, all dispositions recorded.

## Global Constraints

- **A2, Decision 2, B5 and Decision 3 are CUT.** Do not touch `5_general.zsh:129-143` (the gcloud block), and do not derive any test isolation list from `PROFILE_LEGACY`. `.zshrc:8,11` already owns gcloud sourcing; both are backlog rows.
- `5_general.zsh` must still read `RATNA`, `LAPTOP` and `STUDIO` at `:131`/`:135` when this plan is done. Non-comment count stays exactly **2**. A gate asserts this.
- `config/profiles.zsh` uses `export`, never `readonly` — it is sourced twice per login+interactive shell and a second `source` of a `readonly` assignment returns **126** (measured on zsh 5.9 and 5.9.2). `lib/detect_env.sh` uses `readonly` — it runs once per bash process. This asymmetry is deliberate; do not reconcile it.
- `PROFILE_LEGACY` is written out, never derived. `home-1 → HOMES` breaks strip-`-1`-and-uppercase, which would produce `HOME`, and `export HOME=1` repoints the user's home directory.
- `tests/helpers/legacy_oracle.bash` is hand-typed and MUST NOT read `PROFILE_LEGACY`. An oracle derived from the table under test cannot falsify it (`behavior.md`).
- 13 `PROFILE_MAP` keys, 8 distinct legacy variables, wired+wireless twins mapped identically.
- Per-task gates are **scoped** `bats` runs (measured 1–6s). Full `make test` (~9m34s) crosses the Bash tool's 120s auto-background threshold and would never wake a subagent — it runs once, in Task 7 only.

---

## Verification Planning

**Session-level command that proves the whole change works:**

```bash
make test && make lint && make bash-coverage
```

Expected: `make test` ≥ 1402 tests with 0 `not ok` and rc 0; `make lint` rc 0; coverage ≥ 91%. Baselines are **CI figures on `ubuntu-latest` at `5e1f934`** — a local run reads ~1 point higher on coverage and is a preview, not the gate.

**Observable change:** a shell on any mapped host resolves the same `PROFILE`, `HAS_*` set and legacy identity variable as before, from one table instead of four. `git grep -c` for the eight-name `case` drops from 4 files to 0.

**Edge cases that must be exercised:**

1. A `PROFILE_MAP` key with **no** `PROFILE_LEGACY` entry → `config/profiles.zsh` warns to stderr; the oracle's `*) return 1` arm fires naming the helper.
2. An unmapped hostname → `PROFILE=unknown`, no legacy variable, **no** warning.
3. A wireless twin (`studio-1`) resolves identically to its wired name.
4. `HAS_DEVTOOLS` set and unset, on the rbenv guard — both arms.
5. Cross-shell parity: bash and zsh agree for every one of the 13 keys.

**Part A branch check** — `zsh -i -c exit` is worthless here (`~/.zshrc` symlinks into the main checkout, so it passes regardless of the branch; measured during #222). Run `.zshrc`'s own loop instead:

```bash
if [[ ! -d ${HOME}/.oh-my-zsh/custom/plugins/zsh-autosuggestions ]]; then
  printf 'SKIPPED: needs a provisioned HOME (5_general.zsh:44-46 clones zsh-autosuggestions,\n'
  printf '  which writes to stderr and would fail the empty-stderr assertion unrelatedly).\n'
  printf '  Remedy: setup_env.sh -t setup_user, or run on studio/workstation.\n'
  exit 0
fi
_err=$(mktemp)
zsh -c '
  source .zprofile
  for f in .config/.zshrc.d/*.zsh; do source "$f"; done
  [[ -n ${AWS_HOME} ]] || { print -u2 "5_general.zsh not reached"; exit 1 }
' 2>"${_err}"; rc=$?
[ "${rc}" -eq 0 ] && [ ! -s "${_err}" ] || { cat "${_err}"; false; }
```

`AWS_HOME` is what makes it falsifiable — it is set only by `5_general.zsh`, so without that assertion the check passes on a shell that never sourced the file under test. **On `studio` and `workstation` this must PASS and never SKIP**; a SKIP there means the box is unprovisioned, which is itself the finding.

**Cross-machine run.** `ubuntu-latest` matches the workstation (bash 5.2.21, bats 1.10.0), not the Studio (5.3.15, 1.14.0). Ship the tree, never trust the checkout:

```bash
git archive --format=tar <sha> | ssh workstation 'd=$(mktemp -d); tar -x -C "$d"; cd "$d" && make test'
```

That box is **25 commits behind** and its stale `origin/master` ref makes it self-report `0` behind. Running against its checkout produced a false finding once already this session.

---

## Task 1: A1 — rbenv guard becomes a capability test

```yaml-task
id: 1
description: Replace the WORKSTATION/CRUNCHER hostname guard on the rbenv init at 5_general.zsh:77 with HAS_DEVTOOLS, and update the three tests that drove it by legacy variable
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: 'bats tests/zshrc.d/unit.bats -f rbenv'
    exit_code: 0
  - cmd: '[ "$(grep -vE "^\s*#" .config/.zshrc.d/5_general.zsh | grep -cE "WORKSTATION|CRUNCHER")" -eq 0 ]'
    exit_code: 0
  - cmd: '[ "$(grep -vE "^\s*#" .config/.zshrc.d/5_general.zsh | grep -cE "RATNA|LAPTOP|STUDIO")" -eq 2 ]'
    exit_code: 0
  - cmd: 'zsh -n .config/.zshrc.d/5_general.zsh'
    exit_code: 0
max_retries: 3
files_touched:
  - .config/.zshrc.d/5_general.zsh
  - tests/zshrc.d/unit.bats
depends_on: []
```

**Files:** `.config/.zshrc.d/5_general.zsh:77`, `tests/zshrc.d/unit.bats:148-235`

**Gate provenance (measured on the base tree, 2026-08-17):** the `WORKSTATION|CRUNCHER` count is **1** and must become **0** — a real discriminator. The `RATNA|LAPTOP|STUDIO` count is **2** and must **stay** 2; that is a negative gate proving the cut A2 was not done by mistake. A bare `grep -q HAS_DEVTOOLS` would be vacuous — the keychain block at `:248` already uses it, so it exits 0 before any change.

**Change:**

```zsh
# :77 — before
    if [[ -n ${WORKSTATION} ]] || [[ -n ${CRUNCHER} ]]; then
# :77 — after
    if [[ ${HAS_DEVTOOLS} ]]; then
```

Behaviour-preserving for every mapped host: `PROFILE_CAPS` has exactly two Linux profiles (`linux_workstation`, `wsl2_workstation`), both carry `devtools`, and `PROFILE_MAP` maps exactly `workstation`/`cruncher` to them. Confirmed by four independent review lenses. The enclosing `NOBLE`/`RESOLUTE` guard and the `_OVERRIDE_RBENV_BINARY` seam at `:78` are unchanged.

**Test work — three existing tests break, and two are misnamed after this:**

- `:148` `"...initializes rbenv on Linux Noble WORKSTATION"` — exports `WORKSTATION=1`. Rename to `"...on a Linux Noble dev profile"` and export `HAS_DEVTOOLS=1` instead.
- `:177` `"...initializes rbenv on Linux Resolute CRUNCHER"` — same, exports `CRUNCHER=1`. Rename to `"...on a Linux Resolute dev profile"`.
- `:206` `"...skips rbenv when rbenv binary absent"` — exports `WORKSTATION=1`; swap to `HAS_DEVTOOLS=1`. Name stays correct.

**RED first:** add `"5_general.zsh skips rbenv on a Linux host without devtools"` — `LINUX=1 UBUNTU=1 NOBLE=1`, `HAS_DEVTOOLS` **unset**, `_OVERRIDE_RBENV_BINARY` pointed at the mock. Assert `_RBENV_INIT_CALLED` is `unset`.

**This test does NOT fail before the change** — corrected after review caught the original wording asserting it did. On the base tree the guard reads `WORKSTATION`, which is also unset, so the mock is not called and the assertion holds for the wrong reason. The sentence it replaced said "this fails before the change" and then explained in the same breath why it does not.

So it is a **regression guard, not a RED-first discriminator**, and its entire value is catching a future deletion of the guard — which is why the paired control added in review round 2 matters: without it, deleting the guard *and* repointing the seam at `/nonexistent/rbenv` (a plausible dedupe against `:206`) leaves 49/49 green with the guard gone. Measured.

What genuinely goes RED on the base tree is the two **positive** tests, once their exports change to `HAS_DEVTOOLS=1` — that is the RED to verify first. Both arms per `logic-review.md` item 6.

**Interfaces:**

- Consumes: `HAS_DEVTOOLS`, exported by `config/profiles.zsh` (unchanged by this task).
- Produces: nothing later tasks depend on. `5_general.zsh` still reads `RATNA`/`LAPTOP`/`STUDIO`, which Task 5 and Task 6 rely on when wording reason strings.

---

## Task 2: B1 + C2 + C3 — `PROFILE_LEGACY`, and the two stale claims in the same file

```yaml-task
id: 2
description: Add the PROFILE_LEGACY map to config/profiles.sh and correct the two claims in that file that it falsifies — the add-a-machine comment and the SC2034 reason
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: 'bash -c ''source config/profiles.sh; test ${#PROFILE_LEGACY[@]} -eq 13'''
    exit_code: 0
  - cmd: 'bash -c ''source config/profiles.sh; test "${PROFILE_LEGACY[home-1]}" = HOMES'''
    exit_code: 0
  - cmd: 'bash -c ''source config/profiles.sh; for k in "${!PROFILE_MAP[@]}"; do test -n "${PROFILE_LEGACY[$k]:-}" || exit 1; done'''
    exit_code: 0
  - cmd: '! grep -qi "no other file needs changing" config/profiles.sh'
    exit_code: 0
  - cmd: '! grep -q "both maps below" config/profiles.sh'
    exit_code: 0
  - cmd: 'bash -n config/profiles.sh && zsh -n config/profiles.sh'
    exit_code: 0
  - cmd: 'bats tests/zshrc.d/profiles.bats tests/setup_env/profiles.bats'
    exit_code: 0
max_retries: 3
files_touched:
  - config/profiles.sh
  - tests/setup_env/profiles.bats
depends_on: []
```

**Files:** `config/profiles.sh` (`:4`, `:6`, and a new map after `PROFILE_CAPS`), `tests/setup_env/profiles.bats`

**Gate provenance (base tree):** the three `bash -c` gates use a **single-quoted inner** command so `${#PROFILE_LEGACY[@]}` expands in the inner shell, not the runner's. The double-quoted form was authored first and was a permanently-red gate: the outer shell expanded the array to `0` before `bash -c` ran, leaving `test 0 -eq 13`, which fails on the base tree *and* would still fail after this task lands. It passed the fails-on-base check vacuously. Proven discriminating in the corrected form: exit 1 for `PROFILE_LEGACY` (absent) and exit 0 for `PROFILE_MAP` (present) under the identical construction.

The two `!`-form gates both exit **1** today — the strings are present, single occurrence each, case as written. They are the only form that distinguishes _corrected_ from _untouched_; a `grep -c '...' == 1` gate would pass on an unmodified file. The `13` is the `PROFILE_MAP` key count, a contract, not a guess.

**The map:**

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

**C2 — `:4`.** Currently `# Edit PROFILE_MAP to add a new machine — no other file needs changing.` That has been false since #222 and is now falser: a new host needs both maps here **and** an arm in `tests/helpers/legacy_oracle.bash`. Qualify it — name both maps, and name the oracle as the one other file.

**C3 — `:6`.** The file-wide `SC2034` reason says "**both** maps below are read by `lib/detect_env.sh:detect_env`" and argues a second directive on `PROFILE_CAPS` would be redundant. Three maps now, and `PROFILE_LEGACY` is read by `config/profiles.zsh` too. Update the count and the reader list; the file-wide-directive reasoning is unchanged and stays.

**RED first:** add to `tests/setup_env/profiles.bats` a test asserting every `PROFILE_MAP` key has a `PROFILE_LEGACY` entry and that the value set is exactly the eight expected names. It fails before the map exists.

**Interfaces:**

- Produces: `PROFILE_LEGACY`, an associative array keyed by hostname with an uppercase legacy variable name as its value, available to any file that sources `config/profiles.sh`. Consumed by Tasks 3, 4, 5.

---

## Task 3: B4 + B4a + B4b — one shared oracle, with its own diagnostic and a case that reaches it

```yaml-task
id: 3
description: Replace both per-suite legacy oracles with one hand-typed tests/helpers/legacy_oracle.bash carrying the failure message, and add the fixture case that reaches its *) return 1 arm
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: 'test -f tests/helpers/legacy_oracle.bash'
    exit_code: 0
  - cmd: '! grep -q "_profiles_expected_legacy" tests/zshrc.d/profiles.bats'
    exit_code: 0
  - cmd: 'bats tests/zshrc.d/profiles.bats'
    exit_code: 0
  - cmd: 'bats tests/setup_env/profiles.bats'
    exit_code: 0
  - cmd: '! grep -qE "PROFILE_LEGACY|profiles\.sh" tests/helpers/legacy_oracle.bash'
    exit_code: 0
  - cmd: 'shellcheck --severity=warning tests/helpers/legacy_oracle.bash'
    exit_code: 0
max_retries: 3
files_touched:
  - tests/helpers/legacy_oracle.bash
  - tests/zshrc.d/profiles.bats
  - tests/setup_env/profiles.bats
depends_on: [2]
```

**Files:** new `tests/helpers/legacy_oracle.bash`; `tests/zshrc.d/profiles.bats:93-105,141-146`; `tests/setup_env/profiles.bats:316-328,338-341`

**Gate provenance (base tree):** `test -f` exits 1 (file absent — confirmed), and `! grep _profiles_expected_legacy` exits 1 (present at `:93`). The fifth gate is the one that matters most: it enforces Decision 1 mechanically, so a future author cannot "simplify" the oracle into reading the table it exists to check.

**The helper** holds one hand-typed `_expected_legacy_var()` with the same 8 arms and the same `*) return 1` — an empty return is indistinguishable from "this host legitimately has none", which is the gap that arm closes.

**B4a — the message moves in with the `case` it describes.** Both messages live in the _callers_ today, one line below the call, and each hardcodes the oracle's function name and file; the zsh one also directs the reader at "`config/profiles.zsh`'s own case statement", which Task 4 deletes. Put one message in the helper naming `config/profiles.sh`'s `PROFILE_LEGACY` as the table and the helper itself as the oracle. Callers propagate the non-zero.

**B4b — reach the arm.** Nothing does today: all 13 keys have arms, so the suite exercises the 13-way comparison and never the diagnostic, which is exactly why the stale strings were undetectable.

**Fixture construction — verified 2026-08-17, no production seam needed.** Neither reader takes an override (`config/profiles.zsh:40` and `lib/detect_env.sh:23` resolve the table relative to their _own_ file), so copy the pair into a temp tree and source the copy:

```bash
fx="${BATS_TEST_TMPDIR}/fx"; mkdir -p "$fx/config"
cp "${REPO_ROOT}/config/profiles.zsh" "$fx/config/"
sed 's|^  \[cruncher\]=.*|&\n  [newhost]="mac_mini"|' \
    "${REPO_ROOT}/config/profiles.sh" > "$fx/config/profiles.sh"   # key absent from the oracle
```

`PROFILE=mac_mini` is the discriminator that the fixture table was read rather than bypassed — the real table yields `unknown`. Measured: the arm fires on a key absent from the oracle and does **not** fire on a key present in both, so the case can produce either outcome.

**Rewiring:** `tests/setup_env/profiles.bats` already sources `tests/helpers/common.bash` in `setup()` — add one more `source`. `tests/zshrc.d/profiles.bats` sources no helper; add one in `setup()`. That runs at bats level, outside `_profiles_snapshot`'s `zsh -c`, so its isolation reasoning at `:14-37` is untouched. Keep the `no_legacy` exception set at `:132`. **Do not touch `_profiles_snapshot`'s `unset` line — B5 is cut.**

**Interfaces:**

- Consumes: `PROFILE_LEGACY` (Task 2) — only for the message's wording, never as the oracle's source.
- Produces: `_expected_legacy_var <hostname>` → prints an uppercase legacy variable name on stdout, returns 1 with a diagnostic on stderr for an unmapped key. Sourced by both `profiles.bats` suites.

---

## Task 4: B2 + A3 (zsh half) — `config/profiles.zsh` lookup

```yaml-task
id: 4
description: Replace config/profiles.zsh's eight-arm case with a PROFILE_LEGACY lookup, preserving the drifted-table warning, and narrow its SC2034 reason to the surviving gcloud readers
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: 'bats tests/zshrc.d/profiles.bats'
    exit_code: 0
  - cmd: 'bats tests/zshrc.d/cross_shell.bats'
    exit_code: 0
  - cmd: '! grep -q "laptop | laptop-1" config/profiles.zsh'
    exit_code: 0
  - cmd: 'grep -q "PROFILE_LEGACY" config/profiles.zsh'
    exit_code: 0
  - cmd: '! grep -q "readonly" config/profiles.zsh'
    exit_code: 0
  - cmd: 'zsh -n config/profiles.zsh'
    exit_code: 0
max_retries: 3
files_touched:
  - config/profiles.zsh
  - tests/zshrc.d/profiles.bats
depends_on: [2, 3]
```

**Files:** `config/profiles.zsh:4-10` (header), `:6` region reason, `:63-83` (the `case`), `:85` (`unset`)

**Gate provenance (base tree):** `! grep "laptop | laptop-1"` exits 1 (the case arm is at `:64`). The `! grep readonly` gate is a **regression guard, not a discriminator** — it passes today and must keep passing; a `readonly` here makes the second `source` of this file return 126 (measured on both zsh builds), degrading identity at login rather than crashing.

**Change:**

```zsh
_profiles_legacy="${PROFILE_LEGACY[${_profiles_hostname}]:-}"
if [[ -n ${_profiles_legacy} ]]; then
  export "${_profiles_legacy}=1"
elif [[ -n "${PROFILE_MAP[${_profiles_hostname}]:-}" ]]; then
  print -u2 "config/profiles.zsh: host '${_profiles_hostname}' resolved PROFILE=${PROFILE} but has no PROFILE_LEGACY entry -- add one in config/profiles.sh."
fi
unset _profiles_legacy
```

Warning trigger unchanged: a hostname `PROFILE_MAP` knows but `PROFILE_LEGACY` does not is a drifted table and warns; a genuinely unmapped hostname stays silent. Add `PROFILE_LEGACY` to the `unset` at `:85`.

**A3, zsh half.** The header (`:4-10`) says the keychain block reads none of these "but the rbenv guard (`WORKSTATION`/`CRUNCHER`) and the gcloud completion arms (`RATNA`/`LAPTOP`/`STUDIO`) still do". Task 1 retired the rbenv half — narrow to the gcloud arms alone. **Keep naming `5_general.zsh`**: it still reads three legacy variables at `:131`/`:135`. A reason that stops naming a live reader reads as "nothing uses these", which is how the variables get deleted.

**RED first:** a test that a `PROFILE_MAP` key absent from `PROFILE_LEGACY` produces the warning on stderr, built with the Task 3 temp-tree fixture. Fails before the lookup exists (today's `case` warns on a missing _case arm_, not a missing table entry).

**Interfaces:**

- Consumes: `PROFILE_LEGACY` (Task 2); `_expected_legacy_var` (Task 3).
- Produces: unchanged contract — `PROFILE`, the `HAS_*` set and one exported legacy variable per mapped host.

---

## Task 5: B3 + A3 (bash half) — `lib/detect_env.sh` lookup

```yaml-task
id: 5
description: Replace lib/detect_env.sh's eight-arm case with a PROFILE_LEGACY lookup keeping readonly, and narrow its SC2034 reason to the surviving gcloud readers
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: 'bats tests/setup_env/profiles.bats'
    exit_code: 0
  - cmd: 'bats tests/zshrc.d/cross_shell.bats'
    exit_code: 0
  - cmd: '! grep -q "laptop | laptop-1" lib/detect_env.sh'
    exit_code: 0
  - cmd: 'grep -q "PROFILE_LEGACY" lib/detect_env.sh'
    exit_code: 0
  - cmd: 'grep -E SC1124 lib/detect_env.sh | grep -q 5_general.zsh'
    exit_code: 0
  - cmd: '! grep -E SC1124 lib/detect_env.sh | grep -q "rbenv guard"'
    exit_code: 0
  - cmd: 'bash -n lib/detect_env.sh && shellcheck lib/detect_env.sh'
    exit_code: 0
max_retries: 3
files_touched:
  - lib/detect_env.sh
  - tests/setup_env/profiles.bats
depends_on: [2, 3]
```

**Files:** `lib/detect_env.sh:36-61` (comment + `case`), `:51` (the `SC2034` reason)

**Gate provenance (base tree):** `! grep "laptop | laptop-1"` exits 1 (arm at `:53`). The fifth gate — `grep -q "5_general.zsh"` — passes today and must keep passing: it is the mechanical guard against A3 being edited in the wrong direction, which is the failure this task is most likely to produce.

**Change:**

```bash
local legacy
legacy="${PROFILE_LEGACY[${hn}]:-}"
[[ -n ${legacy} ]] && readonly "${legacy}=1"
```

`readonly`, not `export` — `detect_env` runs once per bash process. Measured on bash 5.2.21 **and** 5.3.15: `readonly` inside a function is global, an empty name errors loudly (`not a valid identifier`, rc 1), and the name position is a table value, never hostname-derived. Update the `:44-50` comment to point at the lookup; its export-vs-readonly reasoning is unchanged.

No warning arm here — `detect_env.sh` has none today, adding one is new bash-side behaviour, and the zsh warning plus Task 3's oracle already cover drift.

**Known, accepted:** `[[ -n ${legacy} ]] && readonly ...` returns rc 1 for an unmapped host where the current `case` returns 0. Safe because the `CHRUBY_LOC` block at `:63-69` follows and masks it — but note the safety is _accidental_: `tests/setup_env/profiles.bats:57` and `tests/zshrc.d/cross_shell.bats:68` both do `if ! detect_env`, so if that trailing block ever moves, two suites go red. Do not restructure the function.

**A3, bash half.** `:51`'s reason must **keep** naming `5_general.zsh`, narrowed to the gcloud arms, and must carry its own maintenance rule so the next editor knows both directions are wrong:

```bash
# shellcheck disable=SC2034 # Read cross-file, which the linter cannot see. This list names EVERY
# read site -- add one when a site is added, remove one when removed, and treat an omission as
# seriously as a stale entry: a list that stops naming a live reader reads as "nothing uses these"
# and is how the variables get deleted. Sites: .config/.zshrc.d/2_functions.zsh, 5_general.zsh
# (gcloud completion arms at :131/:135 only -- its keychain and rbenv blocks read none of these),
# 7_final.zsh, .zprofile. One directive covers the whole case (SC1124: a directive cannot sit on
# a case-arm line).
```

**Interfaces:**

- Consumes: `PROFILE_LEGACY` (Task 2), sourced inside `detect_env()` at `:23` — the array is function-local, same as `PROFILE_MAP` already is (measured on both bash builds).
- Produces: unchanged — one `readonly` legacy variable per mapped host.

---

## Task 6: C1 + C4 — `CLAUDE.md`

```yaml-task
id: 6
description: Correct CLAUDE.md's Adding-a-New-Machine procedure (which has understated the work since #222) and name the new oracle helper in the Testing section (docs-only, no behavior change)
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: '[ "$(grep -c PROFILE_LEGACY CLAUDE.md)" -ge 2 ]'
    exit_code: 0
  - cmd: '[ "$(grep -c legacy_oracle CLAUDE.md)" -ge 2 ]'
    exit_code: 0
  - cmd: 'grep -q "fails the suite" CLAUDE.md'
    exit_code: 0
  - cmd: 'grep -q "No other file needs changing" CLAUDE.md'
    exit_code: 0
  - cmd: 'grep -B3 -A3 "No other file needs changing" CLAUDE.md | grep -q legacy_oracle'
    exit_code: 0
max_retries: 3
files_touched:
  - CLAUDE.md
depends_on: [2, 3]
```

**Files:** `CLAUDE.md:623` region ("Adding a New Machine"), Testing / Test Seams section

**Gate provenance (base tree):** the first three exit 1 (`PROFILE_LEGACY` 0 hits, `legacy_oracle` 0, `fails the suite` absent). The fourth passes today and must keep passing — the sentence is **qualified, not deleted**, because it stays true for production files (both maps live in one file) and becomes false only for the test oracle. A gate expecting its absence would reward deleting the thing being corrected.

**C1.** The section ends "No other file needs changing — `lib/detect_env.sh` and `config/profiles.zsh` both derive … from this one table." That has been wrong since #222, not newly wrong: following it literally today costs **5 edits across 5 files** (`PROFILE_MAP`, two production `case` arms, two test oracles) against a document promising one — reproduced by doing exactly that in a `git archive` copy and watching both suites fail. After this plan it is **3 edits across 2 files**. Write it as correcting a document that has been understating the work, not as documenting friction this change introduces; the opposite framing tells the next reader this change added steps when it removed 40% of them.

Name both maps in the step list with the wired/wireless twin rule applying to `PROFILE_LEGACY` exactly as to `PROFILE_MAP`, name `tests/helpers/legacy_oracle.bash` as the one other file, and state the two failure modes because they differ: a missing oracle arm **fails the suite**; a missing `PROFILE_LEGACY` entry only **warns to stderr at login**.

**C4.** In Testing / Test Seams, name the helper and state that it is deliberately hand-typed rather than derived from `PROFILE_LEGACY` — otherwise the next reader "fixes" it into the circular form Decision 1 rejected, and `behavior.md` is the only thing standing between them and a green `[home-1]=HOME`.

**Interfaces:** none — documentation only.

---

## Task 7: Full verification, cross-machine run, and index

```yaml-task
id: 7
description: Run the full aggregate gates plus the Part A branch check and a workstation run from a shipped archive, then mark the plan index
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: 'make lint'
    exit_code: 0
  - cmd: 'make test'
    exit_code: 0
  - cmd: '[ "$(git grep -lE "laptop \| laptop-1" -- "*.sh" "*.zsh" "*.bats" | wc -l | tr -d " ")" -eq 1 ]'
    exit_code: 0
  - cmd: '[ "$(grep -vE "^\s*#" .config/.zshrc.d/5_general.zsh | grep -cE "WORKSTATION|CRUNCHER")" -eq 0 ]'
    exit_code: 0
  - cmd: '[ "$(grep -vE "^\s*#" .config/.zshrc.d/5_general.zsh | grep -cE "RATNA|LAPTOP|STUDIO")" -eq 2 ]'
    exit_code: 0
  - cmd: 'grep -q "2026-08-17-zsh-legacy-identity-consolidation" docs/superpowers/README.md'
    exit_code: 0
max_retries: 3
files_touched:
  - docs/superpowers/README.md
  - docs/superpowers/plans/2026-08-17-zsh-legacy-identity-consolidation.md
depends_on: [1, 4, 5, 6]
```

**Files:** `docs/superpowers/README.md`, this plan file

**Gate provenance:** the eight-name `case` currently lives in 4 files; after Tasks 3–5 exactly **1** should remain — `tests/helpers/legacy_oracle.bash`, the deliberately independent oracle. Base tree returns 4, so the gate discriminates. That single survivor is Decision 1 made mechanically visible.

**This task is the only one that runs `make test`.** ~9m34s, above the Bash tool's 120s auto-background threshold, so it must run here in the orchestrator's own turn and not inside any earlier task.

**Steps:**

- [ ] `make lint` — rc 0
- [ ] `make test` — capture to a file and read `$?` immediately; **never** pipe to `head`/`tail`, which reports the pipe's status and has already reported a green result over a failing suite in this repo
- [ ] `make bash-coverage` — ≥ 91%. This is a **local preview**, ~1 point high; CI's figure on `ubuntu-latest` is the gate
- [ ] Part A branch check from Verification Planning above. On this machine it must PASS, never SKIP
- [ ] Cross-machine: `git archive --format=tar HEAD | ssh workstation '<extract to mktemp -d>; make test'`. Never against its checkout — 25 commits behind, self-reports `0` behind, and produced a false finding once already
- [ ] Set this plan's row in `docs/superpowers/README.md` to **Done** and add the `> **Status: DONE**` banner at the top of this file
- [ ] Commit via `caveman:caveman-commit`

**Interfaces:** none.

---

## Gate hardening (applied after Task 1, from peer review)

The question "does this check fire?" is weaker than "**what edit would a careful person make
that silently retires it?**" Applying the second to this plan's own gates found one already
vacuous and two retirable. All four fixes measured on the base tree.

| gate | defect | fix |
| ---- | ------ | --- |
| T5 `grep -q "5_general.zsh" lib/detect_env.sh` | **Already vacuous.** That string appears twice — `:51` (the legacy-variable reason A3 edits) and `:63` (an unrelated `CHRUBY_LOC` reason). The gate passes on `:63` whatever happens to `:51`. | Scope to the `SC1124` line, and add a discriminator that the `rbenv guard` clause is **gone** from it (exit 1 on base, so it moves) |
| T3 `! grep -q "PROFILE_LEGACY" <oracle>` | An oracle that sources `config/profiles.sh` and indexes it via a runtime-built name or `eval` never contains the literal, so the Decision-1 guard is bypassable by a change that reads as DRY | Widen to `! grep -qE "PROFILE_LEGACY\|profiles\.sh"` — the oracle must not reach the table by any route |
| T6 `grep -q "No other file needs changing"` | Passes if C1 adds a paragraph elsewhere and never qualifies `:623` — satisfied remotely from the thing it checks | Add a windowed gate requiring `legacy_oracle` within 3 lines of the sentence, so the qualification must land *there* |
| T1's two count gates | Checked in T1 only; nothing re-asserted the A2-cut constraint at plan end, so a later task could touch the gcloud block unobserved | Repeated in T7 |

Task 1's own new negative test was checked the same way and **is** load-bearing: replacing the
guard with `if true` on line 77 alone turns it red, while the keychain test at `:248` stays
green (the two guards are byte-identical lines, so the mutation had to be line-scoped — a
string-scoped one silently matched both and mutated neither).

---

## Self-Review

1. **Spec coverage.** A1→T1, B1→T2, C2/C3→T2, B4/B4a/B4b→T3, B2→T4, A3 zsh→T4, B3→T5, A3 bash→T5, C1/C4→T6, verification→T7. Cut items (A2, Decision 2, B5, Decision 3) are named in Global Constraints as prohibitions with a gate enforcing the A2 one. No gaps.
2. **Placeholders.** None — every change shows its code or its exact string.
3. **Type consistency.** `PROFILE_LEGACY` (assoc array, hostname→uppercase name) and `_expected_legacy_var <hostname>` are named identically in T2–T6.
4. **YAML blocks.** Every task has one; every `cmd` containing `": "` or a `!` is single-quoted. `make validate-plan` run below.
5. **TDD `files_touched` includes the test file.** T1 (`unit.bats`), T2 (`setup_env/profiles.bats`), T3 (both suites), T4 (`zshrc.d/profiles.bats`), T5 (`setup_env/profiles.bats`). T6/T7 are `not-applicable` with justification in `description`.
6. **Token budget.** Every block ≤2KB, flat YAML, no BDD boilerplate.
7. **ADR significance.** No new Phase 3 gate, HOLD-capable check, storage choice or security guardrail — this consolidates an existing table and its docs. No ADR task. (Decision 1's oracle-independence rule is an application of existing `behavior.md`, not a new standard.)
8. **`files_touched` covers the prose.** T1 names 2 files and touches 2. T2's prose covers `config/profiles.sh` plus a new test → both listed. T3 names 3, touches 3. T4/T5 each name 2. T6 names 1, touches 1. No `model: haiku` tasks, so the scope guard is not load-bearing here.

**Every gate was run against the base tree** and each either exits 1 (a real failure: the four `!`-form gates, `test -f`, the count gates, the `grep -c ... -ge 2` gates) or is explicitly labelled a regression guard that must keep passing (`! grep readonly` in T4, `grep 5_general.zsh` in T5, `grep "No other file needs changing"` in T6). No gate exits 2/4/127 — every path and binary each one names was confirmed to exist.
