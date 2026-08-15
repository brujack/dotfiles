# Design: derive the shell lint scope by shebang, not by filename

**Date:** 2026-08-15
**Status:** Proposed
**Repos affected:** dotfiles only

> **Revised after Step 8 round 1.** The original scope was three PRs (dotfiles, math,
> ai-config `shell.md`). The Goal-Fit lens measured that drift-immunity — the entire
> justification for the other two — has zero instances outside `tests/mocks/` anywhere in the
> fleet, and that math's baseline was misstated in a way that reduced its real gain to 4 files
> and 0 findings. Scope cut to dotfiles. See Multi-Lens Review at the bottom for the full
> findings and dispositions.

## Problem

`make lint`'s `SHELL_FILES` is derived by filename:

```make
SHELL_FILES := $(shell env -u GIT_DIR ... git ls-files '*.sh' '*.bash' 'scripts/pre-push' 'scripts/commit-msg')
```

A pathspec is extension-keyed, so every shell file that carries no `.sh`/`.bash` suffix is
invisible to it. The repo works around this by appending literal hook paths — a
hand-maintained list, silently stale the moment a file is added.

The omission cannot be seen in the gate's own output. An unlinted file is absent from the
scope and from the report alike, so `make lint` prints the same clean result whether the set
is complete or short by sixty-five files. This is the failure `tdd.md` describes under
Coverage Denominators, and the third instance of it in this repo — after the bash coverage
tracer's 13-entry `INCLUDE_FILES` array and the Makefile-partition scanner's hardcoded
two-file domain.

### Measured gap

All five shell-carrying repos, measured 2026-08-15 on the Mac Studio, shellcheck 0.11.0.
Only the dotfiles row is acted on; the rest is the evidence that decided the scope.

| repo              | effective lint scope | shebang-derived | delta | of which template/fixture | net new lintable | new findings |
| ----------------- | -------------------: | --------------: | ----: | ------------------------: | ---------------: | -----------: |
| dotfiles          |                   35 |             100 |    65 |                         0 |           **65** |        **5** |
| math              |                   28 |              32 |     4 |                         0 |                4 |            0 |
| ai-config         |                   32 |              42 |    10 |                        10 |                0 |            0 |
| terraform_ansible |                   20 |              28 |     8 |                         8 |                0 |            0 |
| etch-cli          |                    4 |               4 |     0 |                         0 |                0 |            0 |

**"Effective lint scope" means what the repo's lint target actually passes to shellcheck**,
not what its primary derived variable holds. An earlier version of this table used math's
`SHELL_TRACKED` (25) and reported a delta of 7. That was wrong: math lints `SHELL_SOURCES`
= `SHELL_TRACKED` + 3 named hooks = **28** (`math/Makefile:19,21,65`), so three of those
"new" files were already linted and its real delta is **4**. Corrected after the Goal-Fit
lens caught it — the column has to mean the same thing in every row or the comparison is
not one.

**Zero files are lost in any repo** — the shebang-derived set is a strict superset of the
current scope everywhere, verified by `comm -23` in both directions, independently by two
lenses.

dotfiles' 65 are the 64 extensionless files under `tests/mocks/` plus
`config/local.sh.example`, which `git ls-files '*.sh'` does not match because the glob
requires the name to _end_ in `.sh`.

## Rule

`SHELL_FILES` is every tracked file whose **first line** is a bash or sh shebang.

The derivation lives in a script, `scripts/list-shell-files.sh`, invoked from the Makefile:

```make
SHELL_FILES := $(shell ./scripts/list-shell-files.sh)
```

```bash
#!/usr/bin/env bash
# Emit every tracked file whose FIRST line is a bash/sh shebang, one per line.
#
# Derived rather than listed: a pathspec is extension-keyed and cannot express
# "every tracked shell script", so extensionless hooks and mocks are invisible to
# one. An omitted file leaves the gate's output unchanged rather than failing it
# (tdd.md, Coverage Denominators), so the omission is undetectable in the very
# report meant to reveal it.
_root="$(env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE \
           git rev-parse --show-toplevel 2>/dev/null)" || exit 1
cd "${_root}" || exit 1
env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE \
  git ls-files -z | while IFS= read -r -d '' f; do
    [[ -f "${f}" ]] || continue
    IFS= read -r first < "${f}" 2>/dev/null || continue
    case "${first}" in
      '#!'*/bash|'#!'*/bash\ *|'#!'*env\ bash|'#!'*env\ bash\ *|\
      '#!'*/sh|'#!'*/sh\ *|'#!'*env\ sh|'#!'*env\ sh\ *) printf '%s\n' "${f}" ;;
    esac
  done
```

Three details are load-bearing:

**The interpreter must follow `/` or `env `.** A naive `'#!'*sh` pattern matches
`#!/usr/bin/env zsh` — "zsh" ends in "sh" — and also `#!/usr/bin/env fish`. Verified
against eleven shebang forms: the corrected pattern accepts `#!/usr/bin/env bash`,
`#!/bin/bash`, `#!/bin/bash -e`, `#!/bin/sh`, `#!/usr/bin/env sh` and rejects all three
zsh spellings, fish, python3, and a non-shebang first line. The naive pattern accepts all
four of the wrong ones. dotfiles carries 10 tracked zsh files; none has a shebang today,
so the naive form would have measured identically and been wrong the first day one gained
one.

**`env -u` on both git calls.** git exports `GIT_DIR` into the `pre-push` hook environment
when the push originates from a worktree, and `scripts/pre-push` runs `make test`. Without
the strip, this parse-time derivation resolves against the wrong repository — `git -C`
does not override an exported `GIT_DIR` (`shell.md`), and the failure mode is a plausible
smaller file list rather than an error.

**`read` reads only the first line.** No tracked file in the repo is a binary (the 8
non-text hits are JSON plus two empty `.gitkeep`), and the longest first line anywhere is
114 bytes, so the parse-time cost is bounded regardless of file size — measured **0.072s
against the pathspec's 0.014s**, over 406 tracked files. An earlier figure of 0.03/0.01 in
this spec measured the bare loop rather than the script; the script adds a process spawn and
a `rev-parse`. Corrected after the Ergonomics lens re-measured it. +58ms on every `make`
invocation including `make help`.

### Rejected: inline `$(shell ...)` in the Makefile

The obvious form — the same loop written directly into the `SHELL_FILES` assignment —
does not work, and fails in two independent ways that were only visible by running it:

1. **`\#` is version-divergent.** `#` starts a comment in make, so the shebang literal must
   be escaped. GNU make 4.x passes `'\#!'` through to the shell verbatim; make 3.81 correctly
   emits `'#!'`. Since agent shells and git hooks on macOS resolve `/usr/bin/make` 3.81 while
   an interactive zsh resolves Homebrew 4.4.1, the same recipe would behave differently for a
   developer at a prompt than for the hook that actually gates. That is `tdd.md` pitfall G
   reproduced inside the fix for a different pitfall.
2. **Escaped spaces do not survive line continuation.** `bash\ *` is mangled by make's
   continuation processing; the observed expansion dropped the loop body's argument entirely
   (`printf '%s\n' ;;`).

A second alternative — a single `awk 'FNR==1 && ...'` one-liner with a `HASH := \#` variable
to sidestep the comment character — does work correctly on both make versions. It is
rejected on testability: it can only be exercised _through_ make, whereas a script is
directly testable with bats, which is this repo's idiom. The `HASH := \#` indirection is also
the kind of cleverness `code-standards.md` rejects.

The script form was verified on both make versions and standalone, returning identical
results.

### Self-consistency

`scripts/list-shell-files.sh` carries a bash shebang and is tracked, so it appears in its
own output and is linted by the gate it defines. This is a property worth keeping: the tool
that decides the scope cannot exempt itself from it.

## Scope — one PR, dotfiles

- Add `scripts/list-shell-files.sh`; `SHELL_FILES` calls it. 35 → 100 files.
- Keep the existing empty-list guard, and **extend its message**. It fails closed, which is
  the right direction, but today it names only _"git absent from PATH, or this tree was
  exported without .git"_. Under this design the dominant cause becomes a broken, renamed, or
  non-executable script — and the operator hitting it is locked out of `git commit`, since
  `scripts/pre-commit-hook.sh:5` runs `make lint`. Name the script as a third cause.
- Fix the 5 findings the widening surfaces:
  - `tests/mocks/brew`, 4 × `SC2086` — **site suppression with the reason, not a quote.**
    `printf "%s\n" ${MOCK_BREW_LEAVES:-}` relies on word splitting: it is what turns
    `MOCK_BREW_LEAVES="bat git"` into `brew leaves`' one-per-line output. Quoting collapses
    it to a single line and breaks `tests/setup_env/brewfile_drift.bats`. This is exactly the
    case `shell.md` names for a site-local disable.
  - `tests/mocks/gpg`, 1 × `SC2034` — **real fix.** `while IFS= read -r line; do :; done`
    drains stdin and never reads `line`; rename to `_`.
- **Give the `bash -n` arm a one-line summary.** The recipe prints one line per file for
  `bash -n` but one line total for `shellcheck`. Measured: `make lint` emits **47** lines
  today (35 bash + 10 zsh + 2 shellcheck); after the widening it emits **112**, 64 of them
  `bash  OK  tests/mocks/<stub>`. Since that runs on every `git commit`, a single
  `bash FAIL` or the ggshield verdict gets pushed off a standard terminal by mock chatter.
  The recipe already contains the right shape in its shellcheck arm; the PR that triples N
  is the one that should carry the fix.
- CI `lint-macos`: replace the `find`-based `bash -n` step with the derived list via
  `make print-SHELL_FILES` (`print-%` already exists at `Makefile:147`). This also deletes a
  dead exclusion — the job carries `-not -path './tests/mocks/*'` under a `-name '*.sh'`
  predicate that never matched an extensionless mock in the first place, so that line has
  never excluded anything (`find . -path './tests/mocks/*' -name '*.sh'` returns 0).
- **Add an empty-list guard to that CI step.** `print-%` (`Makefile:147-148`) has none, so an
  empty derivation would yield a vacuous green. The sibling zsh step in `ci.yml` eight lines
  below already carries exactly that guard; copy it. Not a regression — the current
  `find | xargs` is equally fail-open — but the PR is touching that step.
- Update `CLAUDE.md`: the "35 tracked shell files" figure, the ShellCheck section's scope
  paragraph, and the note stating mocks are covered by nothing.
- Remove the `make lint cannot see any of the 64 mocks` backlog row; add the deferred rows
  below.

## Deferred, with the measurement that decided it

Nothing outside dotfiles is changed. Four repos and the `shell.md` mandate are deferred, each
for a reason that was measured rather than assumed.

**Drift-immunity — the whole argument for a fleet-wide rule — has no instance outside one
directory.** Arrival history of every extensionless shell file in dotfiles: 34 in 2026-03,
29 in 2026-04, 1 in 2026-05 (`tests/mocks/npm`), 1 in 2026-07 (`tests/mocks/systemctl`).
**65 of 65 are under `tests/mocks/`.** Same in math (4 of 4). Across all five repos there is
not one extensionless shell file outside `tests/mocks/` or an already-named hook path. A
one-line pathspec widening would capture 100% of today's gap and 100% of every historical
arrival.

That is not an argument for the pathspec — the derived form is genuinely better, is
self-selecting, and retires a list-shaped defect this repo has now hit three times. It is
the reason the _fleet-wide_ arm is deferred: it would guard a class this fleet has never
produced, at the cost of a script, a bats suite, and a CLAUDE.md edit in each repo.

Per-repo:

| repo              | net new lintable | why deferred                                                                                               |
| ----------------- | ---------------: | ---------------------------------------------------------------------------------------------------------- |
| math              |                4 | 4 test mocks, 0 findings, against a new script + a bats scope suite it does not currently have             |
| ai-config         |                0 | entire delta is 10 `tests/fixtures/shell-pitfalls/*.fixture`; needs an exclusion predicate to gain nothing |
| terraform_ansible |                0 | entire delta is 5 `.sh.j2` + 3 `.sh.tpl` templates, 38 findings between them; same                         |
| etch-cli          |                0 | delta is literally zero — its 4 tracked shell files already are its shebang set                            |

**What a later adopter needs, so it is not re-derived:** the exclusion belongs in `shell.md`
as a **predicate** — _a template extension (`.j2`, `.tpl`), or a deliberately-defective
pitfall fixture_ — never a filename list. Verified complete today: delta minus
`*.j2|*.tpl|*.fixture` leaves exactly the already-named hooks in both repos that need it.
Of ai-config's 10 shebang-carrying fixtures, **3 fail shellcheck at default severity by
design** (`SC2168`, `SC2155`, `SC2072` — reproducing those findings is the fixtures' entire
purpose); the other 7 pass today but are excluded as a class rather than by current verdict,
since a shellcheck upgrade that starts flagging one would turn `make lint` red for a file
working as designed.

**The forward-looking half is settleable.** Run
`git log --diff-filter=A --name-only --format=%ad --date=format:%Y-%m` over the
shebang-minus-pathspec set in the deferred repos. A single hit outside `tests/mocks/` or a
named hook makes drift real and carries the fleet-wide arm; a fourth empty result confirms it
guards nothing.

## Non-goals

- **The bash coverage denominator is untouched.** `scripts/run-bash-coverage.sh` derives its
  own instrumented set (`setup_env.sh` + tracked `config/*.sh lib/*.sh scripts/*.sh` + hooks,
  less `bash-tracer.sh`). Switching that to shebang derivation would sweep the 64 mocks into
  the denominator — and because the bats suite _executes_ mocks, into the numerator too. The
  figure would stop meaning "production code covered" while moving very little, which is the
  worst combination. The two derivations stay independent and the reason is recorded here so
  a later reader does not "unify" them as tidiness.
- **`BATS_FILES` is unchanged**, still linted separately at `--severity=warning`. bats' own
  `run`/`@test` model emits `SC2030`/`SC2031` structurally — 2,698 findings here against the
  mocks' 5, which is why that tier is about bats rather than about the code.
- **No exclusion predicate is implemented in dotfiles.** It has zero template/fixture files,
  so the exclusion would be unfalsifiable — no test could distinguish it working from it
  being absent. Adding an untestable branch to guard a file class that does not exist is the
  exact defect shape this change removes.

  **Sized rather than assumed**, since the Risk lens raised whether mocks are themselves a
  defective-by-intent class: `shellcheck --enable=all` over the 64 mocks returns **28
  findings across 11 of 64 files** (15 `SC2250`, 4 `SC2249`, 4 `SC2086`, 2 `SC2292`, 2
  `SC2154`, 1 `SC2034`). At the default severity the gate actually runs, **only 5 fire** —
  the same ones already planned. The other 23 are opt-in checks that cannot fire under the
  current invocation, and `shellcheck -S style` returns the same 5, so nothing hides at an
  intermediate tier either. Mocks are therefore not ai-config's fixture case, where 3 of 10
  fail _at default severity_. Realising this risk requires a future shellcheck release
  promoting an optional check to default.

## Test oracle

`SHELL_FILES` is now shebang-derived, so a test that re-derives it from shebangs is circular
and can only agree — `behavior.md`, "a check derived from the same decision as the thing it
checks cannot falsify it."

**The oracle is the old pathspec, i.e. a different mechanism: name.** Assert
`name-derived ⊆ shebang-derived` — every `*.sh`, `*.bash`, and named hook still appears. This
mirrors the existing `ZSH_FILES` test, which unions a name arm with a shebang arm for the same
reason and found `.zprofile` on its first execution.

**A subset oracle alone is not enough, and that was this spec's own worst defect.** All three
Step 8 lenses independently found it: cases 1–6 below are _relational_ — subset, non-empty,
disjoint, decoy-survival, cross-version equality — and every one stays green if `SHELL_FILES`
silently collapses back to the 35-file pathspec, because `name ⊆ name` holds. Verified by
simulating the collapse. Case 7 is what makes the suite able to fail.

Tests to add, in `tests/scripts/makefile_lint_scope.bats`:

1. Every file matched by the old pathspec is present in `SHELL_FILES` (name oracle ⊆ derived).
2. `SHELL_FILES` is non-empty, and `make lint` exits non-zero when it is empty.
3. `SHELL_FILES` and `ZSH_FILES` remain disjoint.
4. A fixture with each of the four rejected shebangs (`zsh` in all three spellings, `fish`)
   is **excluded**; one with each of the five accepted forms is **included**.
5. `SHELL_FILES` survives a leaked `GIT_DIR` pointed at a decoy repo.
6. The count is identical under a `<4` make and a `>=4` make. **Note the stated rationale is
   wrong and the test is kept anyway:** the `\#` divergence is a property of the _rejected_
   inline form, and routing the literal through a script make never parses makes the class
   structurally unreachable here. It stays as a guard against reintroducing the inline form,
   not as evidence about this derivation.
7. **`tests/mocks/brew` is a member of `make print-SHELL_FILES`**, plus a floor count. This is
   the only case that can distinguish "mocks are in scope" from "the derivation collapsed back
   to names" — name-derivation provably cannot produce an extensionless non-hook member.

## Verification

Commands already run, with real output, per `behavior.md`'s rule against predicted output.
Every row was independently re-derived by at least one Step 8 lens.

| check                                       | expected                             | status              |
| ------------------------------------------- | ------------------------------------ | ------------------- |
| `scripts/list-shell-files.sh \| wc -l`      | 100                                  | **measured**        |
| strict superset, no file lost               | 0 lost across all 5 repos            | **measured**, twice |
| rejected shebangs                           | zsh ×3, fish, python3 all excluded   | **measured**        |
| new findings                                | 5, in 2 files                        | **measured**, twice |
| script form under make 3.81 and 4.x         | identical output                     | **measured**        |
| inline `$(shell)` form                      | fails on both, two distinct causes   | **measured**        |
| parse-time cost                             | 0.072s vs 0.014s over 406 files      | **measured**        |
| CI's `-not -path './tests/mocks/*'` is dead | `find` returns 0                     | **measured**        |
| `make lint` output volume                   | 47 lines now, 112 after              | **measured**        |
| `--enable=all` over mocks                   | 28 findings / 11 files; 5 at default | **measured**        |
| oracle cases 1–6 under a simulated collapse | all green — the defect               | **measured**        |

Pending implementation:

| check                      | expected                                                                       |
| -------------------------- | ------------------------------------------------------------------------------ |
| `make lint`                | exit 0 after the two mock fixes                                                |
| **mutation check**         | revert the `tests/mocks/gpg` fix → `make lint` goes **red**                    |
| **oracle case 7 mutation** | force `SHELL_FILES` back to the pathspec → case 7 goes **red**, 1–6 stay green |
| `make test`                | exit 0, no regression against the 1334-test floor                              |
| `make bash-coverage`       | unchanged figure (denominator untouched)                                       |

The two mutation rows are load-bearing. Without the first, a green `make lint` is equally
consistent with "mocks are linted and clean" and "mocks were silently dropped from the scope
again". Without the second, nothing demonstrates that case 7 actually closes the hole the
lenses found — and a test believed to guard something it does not is worse than no test.

## Risks

- **A file gains a shebang and silently enters the lint scope.** By design, but it means a new
  file can turn `make lint` red without anyone editing the Makefile. Measured rate: ~0.5
  files/month — 64 of the 65 landed in a single 2026-03/04 burst, 2 in the four months since.
  Mitigated by the gate being local-first (pre-commit), so it surfaces immediately.
- **A shell file with no shebang is now invisible where the pathspec would have caught it.**
  Measured as zero across all five repos today, and no tracked `*.sh`/`*.bash` in this repo
  lacks a shebang — but it is a genuine inversion of the failure mode. Test 1 pins it: if a
  `.sh` file ever lacks a shebang, the name-oracle test fails loudly rather than the file
  being dropped silently.
- **The script must be resolvable and executable at Makefile parse time, for every actor and
  every checkout.** Two routes to failure: a checkout with `core.fileMode=false` — the
  Windows/WSL backup-of-last-resort box — can carry it at mode 644, and a `make -f` from
  another cwd breaks the relative path. Either yields an empty `$(shell ...)`, which the
  guard catches; the extended guard message above is what stops the operator being sent after
  the wrong cause. **Partially settled:** this machine reports `core.fileMode=true` with every
  tracked script at `100755`. The Windows/WSL box is unverifiable remotely — it accepts no
  inbound SSH — so this is stated as an open boundary rather than a cleared one.
- **Parse-time I/O on every `make` invocation**, including `make help`. Measured at +58ms.

## Multi-Lens Review

### Round 1 — reviewed at commit `e05feef`

**All three lenses independently reached the same primary finding**: the proposed oracle
could not detect a collapse back to the 35-file pathspec. That convergence is not three
confirmations of one insight — it is three same-model passes over shared framing — but the
finding was verified directly by simulating the collapse, and it held.

#### Goal-Fit

Finding: **PR 1 is sound and worth building; PR 2 and PR 3 are carried by an argument the
corpus does not instantiate.** Three errors found.

1. **math's baseline was misstated.** The table used `SHELL_TRACKED` (25), but math lints
   `SHELL_SOURCES` = `SHELL_TRACKED` + 3 named hooks = **28** (`math/Makefile:19,21,65`).
   Real delta is **4 files, not 7** — `tests/mocks/{ggshield,gh,git,make}`. PR 2 would buy 4
   test mocks and 0 findings against a script, a new bats suite, and a CLAUDE.md edit.
2. **Drift-immunity has no measured instance outside `tests/mocks/`.** 65 of 65 dotfiles
   arrivals, 4 of 4 in math, and zero such files anywhere in the fleet outside `tests/mocks/`
   or a named hook path.
3. **Oracle Test 6 cannot fail for the reason it was written** — the `\#` divergence belongs
   to the rejected inline form.

Premise verified: re-derived the dotfiles row from scratch — 35 / 100 / 65 / 0 lost / 5
findings in 2 files, and `find . -path './tests/mocks/*' -name '*.sh'` → 0 confirming the
dead CI exclusion. All held exactly. Also confirmed the exclusion predicate is complete
today, and refuted the objection that mocks are a noisy class like `.bats` (5 findings vs
2,698).

Assumption: that extensionless shell files will keep arriving **outside `tests/mocks/`**.
Partially settled already and it went against the spec. Settled forward by
`git log --diff-filter=A --name-only` over the shebang-minus-pathspec set in the deferred
repos.

**Disposition: Addressed.** Scope cut to dotfiles only. math and the `shell.md` mandate
moved to Deferred with the arrival-history measurement recorded; math's row corrected to
28 / 4 throughout; Test 6's rationale corrected in place and the test kept as an
inline-form guard.

#### Ergonomics

Finding: **the pre-commit output nearly triples and the spec priced only the parse cost.**
`make lint` emits **47** lines today; after the widening, **112**, 64 of them
`bash  OK  tests/mocks/<stub>`. `scripts/pre-commit-hook.sh:5` runs `make lint`, so a single
`bash FAIL` or the ggshield verdict is pushed off a standard terminal by mock chatter.

Secondary: `print-%` (`Makefile:147-148`) has **no empty-list guard**, so the CI step this
spec introduces would yield a vacuous green on an empty derivation. Also corrected the
parse-time figure to **0.072s vs 0.014s** (understated ~2.4×), and measured that nothing
hides at an intermediate tier — `shellcheck -S style` returns the same 5 findings.

Premise verified: ran the spec's script verbatim — 35 → 100, 65 delta, 0 lost, 5 findings by
exact file:line. No tracked `*.sh`/`*.bash` lacks a shebang.

Assumption: that `scripts/list-shell-files.sh` is resolvable and executable at parse time for
every actor and checkout. Routes: `core.fileMode=false` on the Windows/WSL box; `make -f`
from another cwd. **Partially settled** — this machine reports `core.fileMode=true` and every
tracked script at `100755`; the Windows/WSL box accepts no inbound SSH and is unverifiable
remotely.

**Disposition: Addressed.** `bash -n` arm gets shellcheck's one-line summary shape; the CI
step gets the sibling zsh step's empty-list guard; parse figure corrected to 0.072/0.014
with the reason for the earlier number; the fileMode/cwd routes recorded as an open boundary
under Risks rather than claimed cleared.

#### Risk

Finding: **the permanent suite could not detect the failure it exists to prevent.** All six
oracle cases are relational and every one stays green if `SHELL_FILES` collapses back to the
35-file pathspec — Test 1 (`name ⊆ derived`) is satisfied by `derived == name`; Test 2 catches
only total emptiness; Test 4 exercises the script against fixtures so it passes even if the
Makefile stops calling it; Test 6 compares the derivation to itself. **Nothing pinned the 65
files that are the entire point.** The only discriminating check sat in the one-shot
"Pending implementation" table, not in the suite.

Secondary: the empty-list guard fails closed, which is right, but its message names only
_"git absent from PATH, or this tree was exported without .git"_ — while the dominant cause
becomes a broken or non-executable script, with the operator locked out of `git commit`.

Judged adequate: the `GIT_DIR` / `git archive` / chmod surfaces, the alternative rejections,
and the coverage-denominator non-goal.

Premise verified: re-implemented the derivation independently, `comm -23` across all five
repos, **LOST=0 everywhere**. Recorded honestly that its first findings count returned a
vacuous 0 because macOS `xargs` has no `-a` — a false refutation that looked like a real one.

Assumption: that `tests/mocks/` is production-shaped source rather than a defective-by-intent
class. Measured `--enable=all` at **28 findings / 11 of 64 files**. **Checked, and narrower
than it reads:** only 5 fire at the default severity the gate runs; the other 23 are opt-in
checks. Mocks are not ai-config's fixture case, where 3 of 10 fail at default severity.

**Disposition: Addressed.** Oracle case 7 added — `tests/mocks/brew ∈ SHELL_FILES` plus a
floor count — with its own mutation row requiring cases 1–6 to stay green while 7 goes red.
Guard message extended to name the script as a third cause. The `--enable=all` figures and
the default-severity qualifier recorded under Non-goals.

#### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger. It proposes a scope
derivation with concrete, measured acceptance criteria and no judge component.

### Round 2 — pending

All three round-1 dispositions are **Addressed**, and the revision changed design substance
(scope cut from three PRs to one, oracle gained a discriminating case, two figures
corrected). Per the re-review rule, that requires **all three lenses re-run**, not only the
lens that raised each finding — a correction is new design and carries its own new defects.
