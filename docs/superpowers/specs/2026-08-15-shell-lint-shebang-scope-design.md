# Design: derive the shell lint scope by shebang, not by filename

**Date:** 2026-08-15
**Status:** Proposed
**Repos affected:** dotfiles only

> **Revised four times under Step 8, and every round found a defect introduced by the
> previous round's own correction.** Round 1 cut the scope from three PRs to one, on a
> measurement that drift-immunity has zero instances outside `tests/mocks/` fleet-wide.
> Round 2 found that a filename pathspec produces a byte-identical set, so the justification
> was rebuilt around the one property that separates the two mechanisms — now measured rather
> than asserted. Round 3 found that property had no test at all: the equivalent pathspec
> passed all ten oracle cases. Round 4 found the test written for it pinned a filename a
> pathspec can exclude, and that the floor guarding it broke on an ordinary python-shebang
> mock.
>
> Then the base-rate sweep the round-4 note had deferred was actually run, and it **inverted
> that note's premise**: the property looked like insurance against nothing only because the
> question had been scoped to `tests/mocks/` (0 of 68). Scoped to the real hazard — any
> directory a pathspec must glob — it is **20 of 136 across five repos**.
>
> **Read the base-rate sweep and the convergence note at the end before the body.** The design
> is correct; what remains is a narrow cost question, no longer resting on an unmeasured number.

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
| dotfiles          |                   35 |             100 |    65 |                         1 |           **65** |        **5** |
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
not one. Verified consistent across all five rows by re-deriving each repo's real
shellcheck argv from its own Makefile.

**dotfiles' template/fixture count is 1, not 0.** `config/local.sh.example` matches the same
`*.example|*.j2|*.tpl|*.fixture` shape that counts terraform_ansible's `.sh.tpl` as a
template. An earlier version of this row said 0 and the Non-goals section built an argument
on it; both corrected. It is the only such file in the repo
(`git ls-files | grep -iE '\.(example|j2|tpl|fixture|template|sample)$'`), and it lints
clean today, so it is counted rather than excluded — see Non-goals.

**Zero files are lost in any repo** — the shebang-derived set is a strict superset of the
current scope everywhere, verified by `comm -23` in both directions, independently by three
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
# Content-derived rather than name-derived, because the set must be correct in
# BOTH directions: a pathspec cannot express "every tracked shell script" (so
# extensionless hooks and mocks fall out of scope silently), and a directory
# glob added to compensate cannot express "only the shell ones" (so a README
# dropped into tests/mocks/ enters shellcheck's argv and reddens the gate).
_root="$(env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE \
           git rev-parse --show-toplevel 2>/dev/null)" || exit 1
cd "${_root}" || exit 1
env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE \
  git ls-files -z | while IFS= read -r -d '' f; do
    [[ -f "${f}" ]] || continue
    first=
    # `read` returns 1 at EOF-without-delimiter while STILL populating the
    # variable, so a bare `|| continue` discards a single-line file whose only
    # line is an unterminated shebang.
    #
    # 2>/dev/null MUST precede the input redirect: bash applies redirections
    # left to right, so a failing `< "${f}"` on an unreadable file reports to
    # the not-yet-redirected stderr. Verified -- with the order reversed, an
    # unreadable tracked file prints `Permission denied` at every make parse,
    # i.e. on every git commit.
    IFS= read -r first 2>/dev/null < "${f}" || [[ -n "${first}" ]] || continue
    case "${first}" in
      '#!'*/bash|'#!'*/bash\ *|'#!'*env\ bash|'#!'*env\ bash\ *|\
      '#!'*/sh|'#!'*/sh\ *|'#!'*env\ sh|'#!'*env\ sh\ *) printf '%s\n' "${f}" ;;
    esac
  done
```

### Why a script and not a wider pathspec — the only argument that survives measurement

**A filename pathspec produces a byte-identical set today.** Measured:

```
git ls-files '*.sh' '*.bash' 'scripts/pre-push' 'scripts/commit-msg' \
             'tests/mocks/*' 'config/local.sh.example'    → 100
scripts/list-shell-files.sh                               → 100
diff                                                      →   0
```

So the script buys **0 net files and 0 net findings** over a one-line pathspec widening. All
65 files and all 5 findings accrue to the _widening_, which both routes deliver. Any
justification resting on scope size is therefore false, and an earlier version of this spec
rested on exactly that. This matters because the same criterion — "N files, 0 findings,
against a new script and a bats suite" — is what defers math below; applying it to dotfiles
would defer the script too.

**What separates them is bidirectional correctness, and it is measurable.** A pathspec must
name `tests/mocks/*` as a directory glob to reach the mocks, and a directory glob cannot
express "only the shell ones". Reproduced in a scratch repo, both routes over the same tree:

```
baseline (shell files only)         pathspec rc=0    shebang rc=0
after `touch tests/mocks/README.md` pathspec rc=1    shebang rc=0
                                    ^ SC2148: "Tips depend on target shell and yours is
                                      unknown. Add a shebang or a 'shell' directive."
```

The pathspec route turns `make lint` red — and therefore blocks `git commit`, since
`scripts/pre-commit-hook.sh:5` runs it — for a Markdown file that is not shell and was never
meant to be linted. The content-derived set self-corrects: a file enters scope when it starts
being shell and leaves when it stops.

That is the whole case for the script. It is a correctness property, not a coverage one, and
it is worth +43ms of parse time and seven test cases only if that property is worth having.
Stated plainly so a later reader can disagree with the actual reason rather than a
reconstructed one.

### Three load-bearing details

**The interpreter must follow `/` or `env `.** A naive `'#!'*sh` pattern matches
`#!/usr/bin/env zsh` — "zsh" ends in "sh" — and also `#!/usr/bin/env fish`. Verified against
eleven shebang forms: the corrected pattern accepts `#!/usr/bin/env bash`, `#!/bin/bash`,
`#!/bin/bash -e`, `#!/bin/sh`, `#!/usr/bin/env sh` and rejects all three zsh spellings, fish,
python3, and a non-shebang first line. The naive pattern accepts all four of the wrong ones.

**Note what this does and does not currently guard.** All 100 files in the derived set carry
the _identical_ shebang `#!/usr/bin/env bash` — 100 of 100, and 65 of 65 across the delta. So
seven of the pattern's eight arms match zero tracked files today, and the zsh/fish
discrimination above guards a form the repo does not contain. That is the right pattern to
write, and dotfiles carries 10 tracked zsh files that could gain a shebang at any time — but
the discrimination is insurance, not a described property of the current tree, and the oracle
cases below reflect that split.

**`env -u` on both git calls.** git exports `GIT_DIR` into the `pre-push` hook environment
when the push originates from a worktree, and `scripts/pre-push` runs `make test`. Without
the strip, this parse-time derivation resolves against the wrong repository — `git -C` does
not override an exported `GIT_DIR` (`shell.md`), and the failure mode is a plausible smaller
file list rather than an error.

**`read` reads only the first line.** No tracked file in the repo is a binary (the 8
non-text hits are JSON plus two empty `.gitkeep`), and the longest first line anywhere is
114 bytes, so the parse-time cost is bounded regardless of file size — measured **0.072s
against the pathspec's 0.014s**, over 406 tracked files. An earlier figure of 0.03/0.01
measured the bare loop rather than the script; the script adds a process spawn and a
`rev-parse`. A round-2 re-measurement got 52ms vs 9ms over 407 files, so 0.072/0.014 is
conservative in the safe direction. Call it **+43 to +58ms** on every `make` invocation
including `make help`.

### Rejected: inline `$(shell ...)` in the Makefile

The obvious form — the same loop written directly into the `SHELL_FILES` assignment — does
not work, and fails in two independent ways that were only visible by running it:

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
to sidestep the comment character — does work correctly on both make versions. It is rejected
on testability: it can only be exercised _through_ make, whereas a script is directly
testable with bats, which is this repo's idiom. The `HASH := \#` indirection is also the kind
of cleverness `code-standards.md` rejects.

### A failure mode neither guard catches

**`$(shell ...)` discards the command's exit status.** A script that dies partway through
yields a truncated but non-empty list, and the `-z` empty-guard cannot see it. Verified:

```make
V := $(shell /tmp/partial.sh)   # prints "a\nb", then exits 1
                                # -> got [a b]
```

There is no runtime defence against this — make offers `.SHELLSTATUS` only for `!=`
assignments, not `$(shell)` in a `:=`. The oracle's structural floor (case 8 below) is what
catches it, in the suite rather than at runtime. Recorded rather than solved.

### Self-consistency

`scripts/list-shell-files.sh` carries a bash shebang and is tracked, so it appears in its own
output and is linted by the gate it defines. The tool that decides the scope cannot exempt
itself from it.

## Scope — one PR, dotfiles

- Add `scripts/list-shell-files.sh`; `SHELL_FILES` calls it. 35 → 100 files.
- Keep the existing empty-list guard and **put the remedy in its message, not the cause.**
  It fails closed, which is right, but today it names only _"git absent from PATH, or this
  tree was exported without .git"_. Under this design the dominant cause becomes a broken or
  non-executable script — and `scripts/pre-commit-hook.sh:5` runs `make lint`, so the
  operator is locked out of committing the fix. The message must carry
  `chmod +x scripts/list-shell-files.sh`, per `shell.md`'s missing-tool-guard rule; naming
  the script as a "cause" only sends the operator off to read it.
- Fix the 5 findings the widening surfaces:
  - `tests/mocks/brew`, 4 × `SC2086` — **site suppression with the reason, not a quote.**
    `printf "%s\n" ${MOCK_BREW_LEAVES:-}` relies on word splitting: it is what turns
    `MOCK_BREW_LEAVES="bat git"` into `brew leaves`' one-per-line output. Quoting collapses it
    to a single line and breaks `tests/setup_env/brewfile_drift.bats`. This is exactly the
    case `shell.md` names for a site-local disable.
  - `tests/mocks/gpg`, 1 × `SC2034` — **real fix.** `while IFS= read -r line; do :; done`
    drains stdin and never reads `line`; rename to `_`.
- **Give the `bash -n` arm a deferred one-line summary.** The recipe prints one line per file
  for `bash -n` but one line total for `shellcheck`. `make lint` emits **47** lines today
  (35 bash + 10 zsh + 2 shellcheck); after the widening it emits **112** (100+10+2), 64 of
  them `bash  OK  tests/mocks/<stub>`, on every `git commit`.

  Two details. The shellcheck arm's shape is **not transplantable** — it is a single
  invocation over the whole list, and `bash -n` takes one file at a time — so this is a loop
  that accumulates and prints once, not a copy of line 80. And the failing case loses
  nothing: `bash -n` writes its own diagnostic to stderr naming the file
  (`x.sh: line 3: syntax error near unexpected token`), so only the `OK` chatter goes. Net
  result is 13 lines (1 bash + 10 zsh + 2 shellcheck) — below today's 47, which inverts the
  asymmetry so zsh becomes 10 of 13. Acceptable; noted so it is not a surprise.

- **CI `lint-macos`: replace the `find`-based `bash -n` step with the derived list — and note
  the transport, which the round-1 version of this spec got wrong.** `print-%`
  (`Makefile:147-148`) emits `$(SHELL_FILES)` as **one space-separated line**. The sibling zsh
  step is newline-oriented because `git ls-files` emits newlines, so copying its
  `printf '%s\n' "${files}" | xargs -I{}` shape fails — `xargs -I` implies `-L1` and does not
  split on blanks:

  ```
  $ files=$(make print-SHELL_FILES); printf '%s\n' "${files}" | xargs -I{} bash -n {}
  xargs: command line cannot be assembled, too long
  ```

  The working form inserts `tr ' ' '\n'`, verified against the real target:

  ```bash
  files=$(make print-SHELL_FILES | tr ' ' '\n' | grep -c .)
  if [ "${files}" -eq 0 ]; then
    printf 'shell file list is EMPTY - refusing to pass having checked nothing\n' >&2
    exit 1
  fi
  make print-SHELL_FILES | tr ' ' '\n' | xargs -I{} bash -n {}
  ```

  This also deletes a dead exclusion — the job carries `-not -path './tests/mocks/*'` under a
  `-name '*.sh'` predicate that never matched an extensionless mock, so that line has never
  excluded anything (`find . -path './tests/mocks/*' -name '*.sh'` returns 0).

- Update `CLAUDE.md`: the "35 tracked shell files" figure, the ShellCheck section's scope
  paragraph, and the note stating mocks are covered by nothing.
- Remove the `make lint cannot see any of the 64 mocks` backlog row; add the deferred rows.

## Deferred, with the measurement that decided it

Nothing outside dotfiles is changed. Four repos and the `shell.md` mandate are deferred, each
for a measured reason.

**Drift-immunity — the argument for a fleet-wide rule — has no instance outside one
directory.** Arrival history of every extensionless shell file in dotfiles: 34 in 2026-03,
29 in 2026-04, 1 in 2026-05 (`tests/mocks/npm`), 1 in 2026-07 (`tests/mocks/systemctl`).
**65 of 65 are under `tests/mocks/`.** Same in math (4 of 4). Across all five repos there is
not one extensionless shell file outside `tests/mocks/` or an already-named hook path.

Note this measurement cuts against the _fleet-wide_ arm specifically. It does not argue
against dotfiles, because dotfiles is justified on the bidirectional-correctness property
above rather than on drift — a different claim, measured separately. The two arms rest on
different evidence on purpose.

| repo              | net new lintable | why deferred                                                                                               |
| ----------------- | ---------------: | ---------------------------------------------------------------------------------------------------------- |
| math              |                4 | 4 test mocks, 0 findings, against a new script + a bats scope suite it does not have                       |
| ai-config         |                0 | entire delta is 10 `tests/fixtures/shell-pitfalls/*.fixture`; needs an exclusion predicate to gain nothing |
| terraform_ansible |                0 | entire delta is 5 `.sh.j2` + 3 `.sh.tpl` templates, 38 findings between them; same                         |
| etch-cli          |                0 | delta is literally zero — its 4 tracked shell files already are its shebang set                            |

**What a later adopter needs, so it is not re-derived:** the exclusion belongs in `shell.md`
as a **predicate** — _a template extension (`.j2`, `.tpl`), or a deliberately-defective
pitfall fixture_ — never a filename list. Verified complete for the two repos that need it:
delta minus `*.j2|*.tpl|*.fixture` leaves exactly the already-named hooks in both. It does
**not** cover `*.example`, so the predicate is complete for those two repos rather than for
the class — see Non-goals. Of ai-config's 10 shebang-carrying fixtures, **3 fail shellcheck
at default severity by design** (`SC2168`, `SC2155`, `SC2072`); the other 7 pass today but
are excluded as a class rather than by current verdict, since a shellcheck upgrade that
starts flagging one would redden `make lint` for a file working as designed.

**The forward-looking half is settleable.** Run
`git log --diff-filter=A --name-only --format=%ad --date=format:%Y-%m` over the
shebang-minus-pathspec set in the deferred repos. A single hit outside `tests/mocks/` or a
named hook makes drift real and carries the fleet-wide arm; a fourth empty result confirms it
guards nothing.

## Non-goals

- **The bash coverage denominator is untouched.** `scripts/run-bash-coverage.sh` derives its
  own instrumented set (`setup_env.sh` + tracked `config/*.sh lib/*.sh scripts/*.sh` + hooks,
  less `bash-tracer.sh`). Switching it to shebang derivation would sweep the 64 mocks into
  the denominator — and because the bats suite _executes_ mocks, into the numerator too. The
  figure would stop meaning "production code covered" while moving very little, which is the
  worst combination. The two derivations stay independent, recorded here so a later reader
  does not "unify" them as tidiness.
- **`BATS_FILES` is unchanged**, still linted separately at `--severity=warning`. bats'
  `run`/`@test` model emits `SC2030`/`SC2031` structurally — 2,698 findings here against the
  mocks' 5, which is why that tier is about bats rather than about the code.
- **No exclusion predicate is implemented, and the honest reason is that the one candidate
  passes.** An earlier version claimed dotfiles has "zero template/fixture files", which is
  false: `config/local.sh.example` is one, and is the only tracked file matching
  `*.example|*.j2|*.tpl|*.fixture|*.template|*.sample`. It lints clean at default severity,
  so it is **included and gated** rather than excluded. That is a bet, not a proof — the same
  bet ai-config's fixtures lost, where 3 of 10 fail by design. If `local.sh.example` ever
  fails, the choice is to fix it or to build the predicate; there is no third option, because
  `make lint` gates `git commit`.

  **The mock class was sized rather than assumed**, since a lens raised whether mocks are
  themselves defective-by-intent: `shellcheck --enable=all` over the 64 returns **28 findings
  across 11 of 64 files** (15 `SC2250`, 4 `SC2249`, 4 `SC2086`, 2 `SC2292`, 2 `SC2154`, 1
  `SC2034`). At the default severity the gate runs, **only 5 fire**. `shellcheck -S style`
  returns the same 5, so nothing hides at an intermediate tier. Realising this risk requires
  a future shellcheck release promoting an optional check to default — see Risks for why
  that lands on a dev machine and not on CI.

## Test oracle

`SHELL_FILES` is now shebang-derived, so a test that re-derives it from shebangs is circular
and can only agree — `behavior.md`, "a check derived from the same decision as the thing it
checks cannot falsify it."

**The oracle is the old pathspec, i.e. a different mechanism: name.** But a subset oracle
alone is not enough, and that was this spec's own worst defect across both review rounds:

- **Round 1** — all three lenses found that a subset assertion is satisfied by
  `derived == name`, so a silent collapse back to the 35-file pathspec left every relational
  case green. Verified by simulating the collapse.
- **Round 2** — the added membership case is satisfied by a _plausible partial_ regression.
  A refactor to `git ls-files '*.sh' '*.bash' 'tests/mocks/*' <hooks>` — a one-line collapse,
  not a strawman — yields **99 of 100 files**, keeps `tests/mocks/brew`, and silently drops
  `config/local.sh.example`. Verified. And `∅ ⊆ anything` is true, so the subset case is
  vacuous if the _oracle itself_ returns empty — which a leaked `GIT_DIR` or an absent git
  produces, and the oracle has no strip of its own.
- **Round 3** — the cases added in round 2 close the _too-small_ collapses and none of the
  _right-sized_ one. The **equivalent** pathspec —
  `'*.sh' '*.bash' <hooks> 'tests/mocks/*' 'config/local.sh.example'` — produces the same 100
  files and passes **all ten** cases. Verified: `total=100 mocks=64`, name-subset misses 0,
  both case-7 pins present, floor satisfied at `100 >= 35+65`. So the property the script is
  bought for — bidirectional correctness — had no case and no mutation row at all, and the
  suite could not tell the two mechanisms apart. That is the round-1 defect two levels out:
  each round closed a narrower collapse and left the wider one. Case 11 and the fourth
  mutation row exist for exactly this.

Cases to add, in `tests/scripts/makefile_lint_scope.bats`:

1. **The name oracle is itself non-empty**, derived through `_git_ls_clean` (already at
   `makefile_lint_scope.bats:126`) so it carries the same four-variable `env -u` strip as the
   derivation. Without this, case 2 is vacuous.
2. Every file matched by the old pathspec is present in `SHELL_FILES` (name oracle ⊆ derived).
3. `SHELL_FILES` is non-empty, and `make lint` exits non-zero when it is empty.
4. `SHELL_FILES` and `ZSH_FILES` remain disjoint, **both asserted non-empty first** — an empty
   set is disjoint from everything.
5. A fixture with each of the four rejected shebangs (`zsh` ×3, `fish`) is **excluded**; one
   with each of the five accepted forms is **included**. Note this is the insurance case: 7 of
   the 8 pattern arms match zero tracked files today.

   **Plus one fixture that is a shebang and nothing else, with no final newline** — the shape
   the `read` guard exists for. Without it the guard's mutation row (below) has no assertion
   to turn red: no tracked file in the repo has that shape, so reverting the guard is
   invisible to every other case.

6. `SHELL_FILES` survives a leaked `GIT_DIR` pointed at a decoy repo.
7. **`tests/mocks/brew` and `config/local.sh.example` are both members** of
   `make print-SHELL_FILES`. Two pins, not one: the mock catches a collapse to names, the
   `.example` catches the partial regression above. Neither is producible by name-derivation.
8. **A structural floor, derived at HEAD on every run — not a hardcoded constant.** Round 2
   proposed `mocks >= 64` and `total >= name-oracle + 65`. Both are hand-maintained numbers,
   which is this spec's own target defect one level up, and both break on a legitimate
   **deletion**: dropping one obsolete mock gives `mocks=63` and `total=99`, reddening both
   arms at once while `make test` gates `git push`. Round 2 fixed the addition direction and
   left its mirror.

   **Round 3's replacement was also wrong, in the mirror direction, and is retired too.** It
   proposed a weaker oracle — "every tracked file under `tests/mocks/` whose first line begins
   with `#!` is a member of `SHELL_FILES`" — on the reasoning that a weaker predicate is
   non-circular. It is non-circular, and it is also **wrong on any mock that is not bash**.
   Verified: a `tests/mocks/python-helper` carrying `#!/usr/bin/env python3` is listed by that
   oracle and correctly excluded by production, so case 8 reddens and `git push` is blocked by
   an ordinary, legitimate addition — `tests/mocks/python` and `tests/mocks/pyenv` already
   exist, so a python-implemented mock is unremarkable. Round 2 broke on deletion; round 3
   broke on addition. Both were hand-built numbers or hand-built predicates wearing different
   clothes.

   **Drop the count entirely.** The floor's only job was to catch a truncated `$(shell)`
   result, and a count is the wrong instrument for that — every count needs a reference value,
   and every reference value is either hardcoded or derived by a predicate that can disagree
   with production. Assert the two things that actually characterise a truncation, neither of
   which needs a number:

   > `scripts/list-shell-files.sh` **exits 0**, and `SHELL_FILES` ⊇ the name oracle

   The script must therefore be written to fail loudly — `set -o pipefail`, an explicit check
   on the `git ls-files` call — so that a partial walk is a non-zero exit rather than a short
   list. That converts the untestable `$(shell)`-swallows-status hole into something the suite
   can see, at the one place it is observable: invoking the script directly, outside make.
   Case 2 already carries the ⊇ half; case 8 adds the exit status.

9. The count is identical under a `<4` make and a `>=4` make. **The rationale in the round-1
   spec was wrong and is retired**: this does not detect reintroduction of the inline form,
   since two make versions agree on that form's correct branch too. It is kept only as a
   general cross-version invariant. **It needs both 3.81 and ≥4.0 present**, which
   `ubuntu-latest` does not have (4.3 only) — so it must skip with a stated reason there
   rather than pass silently, or it becomes another vacuous green.
10. **The CI step's empty-list guard has its own case.** It is new machinery in `ci.yml` that
    nothing in the bats suite currently reaches.
11. **A tracked non-shell file under `tests/mocks/` is absent from `SHELL_FILES`.**

    **The fixture must be extensionless, and that is the whole point of the case.** Round 3
    specified `tests/mocks/README.md`, inherited from the round-2 differential where it was
    fine as a _measurement_. As a _test fixture_ it is worthless: verified, the pathspec
    `git ls-files '*.sh' '*.bash' <hooks> 'tests/mocks/*' ':(exclude)*.md'` passes this case
    while still shipping `tests/mocks/fixture-data` and `tests/mocks/python-helper` — both
    non-shell — into shellcheck's argv. A `.md` file is excludable **by name**, which is
    precisely the thing a pathspec can do. Use two fixtures with no discriminating extension:

    - `tests/mocks/fixture-data` — plain data, no shebang at all
    - `tests/mocks/python-helper` — `#!/usr/bin/env python3`, i.e. a shebang the production
      predicate must reject on interpreter rather than on name

    Only an extensionless non-shell file separates the two mechanisms, because it is the one
    shape no pathspec can exclude without enumerating it.

    **This is the only case that pins the property the script is bought for**, and it was
    missing through three review rounds while the spec's entire justification rested on it.
    Every other case asserts the set is not too _small_; this one asserts it is not too
    _large_, which is the half a pathspec cannot deliver. Without it the suite passes
    identically for the script and for the equivalent pathspec — verified.

## Verification

Commands already run, with real output. Every row was independently re-derived by at least
one Step 8 lens; rows marked _predicted_ are arithmetic about a state that does not exist
yet, and are labelled as such per `behavior.md` rather than presented as measurement.

| check                                       | result                                                                       | status        |
| ------------------------------------------- | ---------------------------------------------------------------------------- | ------------- |
| `scripts/list-shell-files.sh \| wc -l`      | 100                                                                          | measured      |
| strict superset, no file lost               | 0 lost across all 5 repos                                                    | measured ×3   |
| pathspec alternative produces identical set | `diff` → 0                                                                   | measured      |
| **bidirectional differential**              | `+ tests/mocks/README.md` → pathspec rc=1 (`SC2148`), shebang rc=0           | measured      |
| rejected shebangs                           | zsh ×3, fish, python3 excluded                                               | measured      |
| new findings                                | 5, in 2 files                                                                | measured ×3   |
| script form under make 3.81 and 4.x         | identical output                                                             | measured      |
| inline `$(shell)` form                      | fails on both, two distinct causes                                           | measured      |
| `$(shell)` swallows exit status             | script exiting 1 → `got [a b]`                                               | measured      |
| parse-time cost                             | 0.072s vs 0.014s (re-measured 52ms vs 9ms)                                   | measured      |
| CI's `-not -path './tests/mocks/*'` is dead | `find` returns 0                                                             | measured      |
| CI form as first specified                  | `xargs: command line cannot be assembled, too long`                          | measured      |
| CI form with `tr ' ' '\n'`                  | works, 35 files today                                                        | measured      |
| `make lint` output volume                   | 47 lines                                                                     | measured      |
| `make lint` after widening                  | 112 lines (100+10+2)                                                         | **predicted** |
| `--enable=all` over mocks                   | 28 findings / 11 files; 5 at default                                         | measured      |
| oracle cases under a simulated collapse     | all green — the round-1 defect                                               | measured      |
| partial regression (pathspec + mocks glob)  | 99 files, `brew` present, `.example` dropped                                 | measured      |
| **equivalent pathspec vs all 10 cases**     | 100 files, `mocks=64`, 0 subset misses, both pins, floor met — **all green** | measured      |
| **`read` on an unterminated line 1**        | rc=1 with the variable populated → old form drops the file                   | measured      |
| unterminated line 1, real exposure          | 1 of 9 no-final-newline tracked files is single-line, and is not shell       | measured      |
| floor stability on a mock deletion          | `mocks=63`, `total=99` — both round-2 arms red at once                       | measured      |
| shebang uniformity                          | 100/100 `#!/usr/bin/env bash`                                                | measured      |
| mock edit rate                              | 24 commits since 2026-04-15 (vs 5 arrivals)                                  | measured      |

Pending implementation:

| check                                                            | expected                                            |
| ---------------------------------------------------------------- | --------------------------------------------------- |
| `make lint`                                                      | exit 0 after the two mock fixes                     |
| **mutation: `gpg` fix reverted**                                 | `make lint` goes **red**                            |
| **mutation: `SHELL_FILES` forced back to the pathspec**          | cases 7 and 8 go **red**, the rest stay green       |
| **mutation: `SHELL_FILES` forced to pathspec + `tests/mocks/*`** | cases 7 **and 11** go red                           |
| **mutation: script body replaced by the _equivalent_ pathspec**  | cases 5 **and** 11 go red; 1–4, 6–10 stay green     |
| **mutation: `read` guard reverted to bare `\|\| continue`**      | case 5's shebang-only unterminated fixture goes red |
| `make test`                                                      | exit 0, no regression against the 1334-test floor   |
| `make bash-coverage`                                             | unchanged figure (denominator untouched)            |

**Every mutation row names its target explicitly, because the previous version did not and
was unsatisfiable as a result.** Cases 7 and 8 read `make print-SHELL_FILES`, so a Makefile
mutation reaches them; cases 5 and 11 build a fixture repo and invoke the script, so only a
mutation of the **script body** reaches those. The round-3 row said "`SHELL_FILES` forced to
the equivalent pathspec → case 11 red, 1–10 green", which is false under either reading — a
Makefile mutation leaves case 11 green, and a script mutation also reddens case 5, since a
pathspec ignores shebangs entirely. Stating the target and both expected reds is the fix.

The equivalent-pathspec row is the load-bearing one: it is the only check that distinguishes
this design from the one-line alternative it costs a script, +43ms, and eleven test cases
more than. If it does not turn case 11 red, the whole package reduces to a more expensive way
of producing the same set. Without the others a green suite is equally consistent
with "the scope is correct" and "the scope silently narrowed again", and a test believed to
guard something it does not is worse than no test.

## Risks

- **A file gains a shebang and silently enters the lint scope.** By design, but a new file can
  turn `make lint` red without anyone editing the Makefile.
- **The friction rate is edits, not arrivals — and the earlier version priced the wrong one.**
  Arrivals under `tests/mocks/` run ~1/month (65 of them landed in a single 2026-03/04 burst;
  2 since). But every _edit_ to a mock must now clear default-severity shellcheck inside the
  pre-commit hook, and that rate is **24 commits touching `tests/mocks/` since 2026-04-15**,
  roughly 6/month. The class is quiet (5 findings across 64 files), so this is a mispriced
  number rather than a blocker — but it is the number that governs day-to-day friction, and
  mocks are files the owner edits while debugging tests, i.e. at the worst moment to be
  interrupted.
- **A shell file with no shebang is now invisible where the pathspec would have caught it.**
  Measured as zero across all five repos today. Cases 1–2 pin it: if a `.sh` file ever lacks a
  shebang, the name-oracle test fails loudly rather than the file being dropped silently.
- **Local `shellcheck` is unpinned while CI's is pinned, and this change triples the locally
  gated surface.** `Makefile:12` resolves it via `command -v`; `ci.yml:22` installs and
  checksum-verifies 0.11.0. A newer shellcheck arrives on a dev machine by `brew upgrade` —
  which `setup_env.sh -t update` runs — and never reaches CI. If one promotes an optional
  check to default, `make lint` reddens locally on 100 files, `git commit` is blocked, and CI
  stays green, so nothing surfaces it except an operator who cannot commit. **Measured on the
  Mac Studio only: 0.11.0, matching the pin.** The other six machines are unmeasured, and the
  Windows/WSL box accepts no inbound SSH.
- **The script must be resolvable and executable at Makefile parse time, for every actor and
  checkout.** Two routes: `core.fileMode=false` on the Windows/WSL box can carry it at mode
  644, and a `make -f` from another cwd breaks the relative path. Either yields an empty
  `$(shell ...)`, which the guard catches — the remedy in the guard message is what stops the
  operator being sent after the wrong cause. **Partially settled:** this machine reports
  `core.fileMode=true` with every tracked script at `100755`. The Windows/WSL box is
  unverifiable remotely.
- **Parse-time I/O on every `make` invocation**, including `make help`: +43 to +58ms.

## Multi-Lens Review

### Round 1 — reviewed at commit `e05feef`

**All three lenses independently found the same primary defect**: the proposed oracle could
not detect a collapse back to the 35-file pathspec, because `name ⊆ name` holds. Verified by
simulating the collapse.

**Goal-Fit.** PR 1 sound; PR 2 and PR 3 carried by an argument the corpus does not
instantiate. Three errors: math's baseline was `SHELL_TRACKED` (25) where it lints
`SHELL_SOURCES` (28), so its real delta is 4 not 7; drift-immunity has 65-of-65 arrivals
under `tests/mocks/` and zero instances elsewhere fleet-wide; oracle Test 6 could not fail
for its stated reason. Premise re-derived from scratch and held exactly.
**Disposition: Addressed** — scope cut to dotfiles, math row corrected to 28/4, Test 6
rationale corrected.

**Ergonomics.** `make lint` goes 47 → 112 lines on every commit, 64 of them mock chatter;
`print-%` has no empty-list guard; parse figure understated ~2.4× (0.072/0.014, not
0.03/0.01). Premise held exactly.
**Disposition: Addressed** — `bash -n` summary, CI guard, corrected figure.

**Risk.** All six oracle cases relational, so a collapse stays green; guard message names a
cause the operator cannot act on. Sized the mock class at `--enable=all` 28/11, of which 5
fire at default. Recorded honestly that its first count was a vacuous 0 from macOS `xargs`
lacking `-a`.
**Disposition: Addressed** — case 7 added, guard message extended.

**Adversarial Spec Review:** N/A — no comparison, evaluator, or ambiguous-criteria trigger.

### Round 2 — reviewed at commit `ec4d881`

Full re-run of all three lenses, since the round-1 revision changed design substance. Each
found defects the revision itself introduced.

#### Goal-Fit

Finding: **the widening is clearly worth it; the mechanism is over-built and the spec never
priced the cheap alternative on the row it is actually building.** A pathspec widening
produces a byte-identical 100-file set, verified — so script-over-pathspec is 0 net files and
0 net findings, and applying the spec's own deferral criterion to dotfiles would defer the
script too. The strongest real argument — that a directory glob cannot express "only the
shell ones", so a README in `tests/mocks/` reddens the gate — **was not in the document**.

Revision-introduced: Non-goals claimed dotfiles has zero template/fixture files while
`config/local.sh.example` is one and is named 184 lines earlier; the gap table's "of which
template/fixture: 0" was wrong by one under the same definition applied to
terraform_ansible; "112 lines after — measured" is arithmetic labelled as measurement inside
a table whose header cites the rule against exactly that; case 7's floor count had no value;
the new CI guard had no oracle case.

Premise: re-derived all five rows from each repo's real shellcheck argv. Every figure held,
including the corrected math row and zero-lost in all five directions.

**Disposition: Addressed.** Justification rewritten around bidirectional correctness and the
differential **measured** rather than asserted (`+ tests/mocks/README.md` → pathspec rc=1
`SC2148`, shebang rc=0). Template/fixture count corrected to 1 in both the table and
Non-goals, with the honest reason stated — the file is included and gated because it passes,
which is a bet rather than a proof. "112" relabelled **predicted**. Floor replaced with
derivation rules (case 8). CI guard given case 10.

#### Ergonomics

Finding: **the CI step as specified does not work.** `print-%` emits one space-separated
line; `xargs -I` implies `-L1` and does not split on blanks, so the sibling zsh step's shape
cannot be copied. Verified: `xargs: command line cannot be assembled, too long`. Also: the
Risks row priced arrivals (~1/month) where the friction rate is **edits** — 24 commits
touching `tests/mocks/` since 2026-04-15, ~6/month, 12× the priced figure. And the guard
message names a cause where `shell.md` requires the remedy.

Confirmed sound: the `bash -n` one-line summary loses nothing diagnostic, since `bash -n`
names the file on stderr itself. Caveat raised: the shellcheck arm's shape is a single
invocation over the whole list and is **not transplantable** to `bash -n`, which takes one
file — it needs a loop with a deferred summary.

Revision-introduced: items 1 and 3 are both round-1 dispositions that were verified by
reading rather than running — the spec's own thesis, one level up. Also new: `$(shell ...)`
discards exit status, so a script dying partway yields a truncated non-empty list the `-z`
guard cannot see.

Premise: 47/112 arithmetic held exactly (35+10+2, 100+10+2); timing re-measured at 52ms vs
9ms over 407 files, so the spec's figure is conservative in the safe direction.

**Disposition: Addressed.** CI form corrected to `tr ' ' '\n'` and **verified working**
against the real target. Guard message now carries `chmod +x`. Risks row repriced on the
edit rate. `bash -n` summary respecified as a loop with deferred output, with the
non-transplantable note. `$(shell)` exit-status behaviour measured and recorded as an
unsolved failure mode with case 8 as the compensating control.

#### Risk

Finding: two mechanism defects of the same class the spec exists to close. **Case 1 is
vacuous if the oracle itself returns empty** (`∅ ⊆ anything`), and the name oracle is a
pathspec with no `GIT_DIR` strip of its own. **`config/local.sh.example` is pinned by no
case** — a refactor to `pathspec + 'tests/mocks/*'` keeps `brew`, keeps 99 of 100 files, and
silently drops it, leaving case 7 green. Verified. And the floor count has no value, where
both wrong choices are bad in opposite directions — too tight reddens `make test` (which
gates `git push`) on a legitimate addition, too loose permits the partial regression.

Also raised: local shellcheck is unpinned (`Makefile:12`) while CI pins 0.11.0, so drift
lands on the machine that gates `git commit` and never on CI.

Not raised after checking: the `bash -n` summary does not lose which file failed;
`tests/mocks/brew` is stable enough to pin (5 commits, referenced by 7 test files).

Revision-introduced: **the scope cut wrote a measurement that undercuts the arm it kept.**
The 65-of-65 drift measurement defers four repos, while dotfiles is kept on a principle
claim — an asymmetry the round-1 text never confronted, and which did not exist in round 1
because all three repos were in scope on one argument. Also: case 6 was retained with a
rationale the spec itself calls wrong, and needs both make 3.81 and ≥4.0 present, which
`ubuntu-latest` (4.3 only) does not have.

Premise: re-ran the derivation and confirmed 35 → 100, 0 lost, 65 delta. Additionally
reported what the spec had not: **all 100 files carry the identical shebang**, so 7 of the
pattern's 8 arms match zero tracked files.

**Disposition: Addressed.** Case 1 now asserts the oracle is non-empty and routes it through
`_git_ls_clean` for the same `env -u` strip. Case 7 pins `config/local.sh.example` alongside
`tests/mocks/brew`, with a third mutation row proving the partial regression turns it red.
Case 8's floor expressed as derivation rules. Case 9 (was 6) keeps only the general
cross-version invariant and must **skip with a stated reason** on `ubuntu-latest` rather than
pass vacuously. Shebang uniformity recorded, and case 5 relabelled insurance. The
unpinned-shellcheck exposure added to Risks with its boundary named — measured on the Studio
only.

**Adversarial Spec Review:** N/A — unchanged, no comparison/evaluator/ambiguous-criteria
trigger.

### Round 3 — scoped Risk lens, reviewed at commit `58611ec`

Finding: **the oracle could not detect removal of the thing the spec exists to add.** The
_equivalent_ pathspec produces the same 100 files and passes **all ten** cases — verified:
`total=100 mocks=64`, 0 subset misses, both case-7 pins present, floor met at `100 >= 35+65`.
So bidirectional correctness, the sole justification after round 2, had no case and no
mutation row. The mutation table stopped one short: it mutated to the 99-file _partial_
pathspec but never to the _equivalent_ one. Each round closed a narrower collapse and left
the wider one.

The lens's own summary is worth keeping verbatim in substance: the package as it stood was
"strictly worse than the pathspec: same set, same findings, more machinery, and a test suite
that cannot tell the two apart."

Revision-introduced: case 8's round-2 floor (`mocks >= 64`, `total >= oracle + 65`) is two
hand-maintained constants — the spec's own target defect one level up — and breaks on a
legitimate **deletion**: removing one obsolete mock reddens both arms at once while
`make test` gates `git push`. Round 2 fixed the addition direction and left its mirror.
Verified: `mocks=63`, `total=99`.

Second: `IFS= read -r first < "${f}" || continue` returns rc=1 at EOF-without-delimiter
**while populating the variable**, so it silently discards a file whose only line is an
unterminated shebang.

**One correction to the lens.** It reported the precondition as "nine tracked files already
lack a final newline," implying nine exposures. Measured: the bug fires only when **line 1
itself** is unterminated, i.e. a single-line file. Eight of those nine have terminated first
lines and would be unaffected even if they were shell; exactly one is single-line
(`docs/anthropic-new-features/.platform-state.txt`), and it is not shell. Real exposure today
is **zero**, and the realistic future case is a shebang-only script. The bug is real and the
fix is free; its stated precondition was 9× too broad.

Not raised after checking: case 7's two filename pins are not a reintroduction of the
hand-maintained-list defect — a pin is an assertion about known-discriminating members, with
no denominator role, so it cannot go silently short. CRLF on the Windows/WSL box is a
non-issue: `.gitattributes` carries `* text=auto eol=lf`.

Assumption: _a non-shell file will eventually be committed under `tests/mocks/`._ Base rate
is **zero across five repos over the only window that exists** — 65 of 65 arrivals were
shell. If it never happens, the script buys nothing over one line of pathspec. Settled by
retargeting the sweep already proposed above: `git log --diff-filter=A --name-only --
'tests/mocks/*'` across all five repos, counting _non-shell_ arrivals.

**Disposition: Addressed.** Case 11 added — a tracked non-shell file under `tests/mocks/`
must be absent from `SHELL_FILES` — with a fourth mutation row forcing the equivalent
pathspec and requiring case 11 red while 1–10 stay green. Case 8's floor rederived at HEAD
by a non-circular weaker predicate (`#!` on line 1) that moves with additions and deletions
alike. The `read` guard fixed to `|| [[ -n "${first}" ]] || continue`, verified against
single-line-unterminated, multi-line-unterminated, empty, blank-line, and non-shell inputs,
including confirming `read` clears the variable on a truly empty file so no stale value can
leak. A fifth mutation row covers reverting that guard.

### Round 4 — scoped Risk lens, reviewed at commit `446564f`

Five findings, **four of them introduced by round 3's own three fixes** — one per fix, plus
one pre-existing. The loop has not converged; this is the fourth consecutive round in which
the previous round's correction carried the next round's defect.

**F1 — the equivalent-pathspec mutation row was unsatisfiable as written.** Its siblings
mutate the Makefile's `SHELL_FILES :=` assignment, which is what cases 7 and 8 read. But
case 11 builds a fixture repo and invokes the **script**, so a Makefile mutation leaves it
green and the row's central claim is false; mutating the script instead reddens case 5 too,
contradicting "1–10 stay green". **Addressed** — every row now names its target, and the
script-mutation row states both expected reds.

**F2 — case 11 pinned a filename, not the property.** Verified: the pathspec
`'*.sh' '*.bash' <hooks> 'tests/mocks/*' ':(exclude)*.md'` passes case 11 while still
shipping `tests/mocks/fixture-data` and `tests/mocks/python-helper` into shellcheck's argv.
`README.md` was inherited from the round-2 differential, where it was sound as a
_measurement_; as a _fixture_ it is excludable by name, which is exactly what a pathspec can
do. **Addressed** — the fixtures are now extensionless (`fixture-data`, and `python-helper`
carrying a `python3` shebang so the predicate must reject on interpreter rather than name),
because an extensionless non-shell file is the only shape no pathspec can exclude without
enumerating it.

**F3 — case 8's rederived floor broke on a legitimate _addition_, the mirror of the defect it
fixed.** Verified: a mock carrying `#!/usr/bin/env python3` is listed by the weaker `#!`
oracle and correctly excluded by production, so case 8 reddens and `git push` is blocked —
and `tests/mocks/python` and `tests/mocks/pyenv` already exist, so a python-implemented mock
is unremarkable rather than exotic. Round 2 broke on deletion, round 3 on addition.
**Addressed by deleting the count, not by a third number.** A count needs a reference value;
every reference value is hardcoded or derived by a predicate that can disagree with
production. Case 8 now asserts the script **exits 0** plus the ⊇ already in case 2, and the
script must fail loudly (`set -o pipefail`, explicit check on `git ls-files`) so a partial
walk is a non-zero exit rather than a short list. That also converts the previously
untestable `$(shell)`-swallows-status hole into something the suite can observe, by invoking
the script outside make.

**F4 — the `read` guard shipped with a mutation row but no assertion.** No tracked file has
the shape it protects (a shebang-only file with no final newline), so reverting the guard was
invisible to every case. **Addressed** — case 5 gains that fixture.

**F5 — `2>/dev/null` was inert where it sat.** Bash applies redirections left to right, so a
failing `< "${f}"` reports to the not-yet-redirected stderr. Verified both orders: after the
redirect it leaks `Permission denied`, before it is silent. Behaviour was still correct (the
file is skipped) but an unreadable tracked file would print a bash diagnostic at every make
parse — i.e. every `git commit`. **Addressed** — moved ahead of the input redirect.

**Held on inspection, not raised:** the guard is correct on empty, blank-line,
whitespace-only, broken symlink, symlink-to-directory, and unreadable inputs; case 8's
round-3 floor was genuinely stable under deletion as claimed; a NUL-prefixed first line
requires a tracked binary, already bounded.

**One item recorded and not fixed:** no case pins that the set is _derived_ rather than
_enumerated_ — a hardcoded literal list of the correct 100 files passes every case today.
Cases 2 and 8 would redden on the next addition, so it fails loudly rather than silently,
which is why it is recorded rather than closed. It is also this repo's exact `INCLUDE_FILES`
precedent, so it is worth knowing the suite does not currently distinguish the two.

Assumption: that an operator blocked from `git push` by a gate whose message says "this is a
deliberate decision point" will treat it as one rather than edit past the assertion. Now
largely moot — F3's disposition removes the gate that would have posed it.

### The base-rate sweep — run, not deferred

The round-4 note handed the operator a proportionality decision and left the deciding number
unmeasured, while this spec's own standard says a verification command executable at spec time
must be executed rather than predicted. That was the one place the document did not follow its
own rule. Corrected: the sweep is below.

**The question was scoped to the wrong directory.** The hazard is not "a non-shell file lands
in `tests/mocks/`" — it is "a non-shell file lands in **any directory a pathspec would have to
glob**", i.e. any directory holding extensionless shell files. Counting non-shell arrivals into
those directories, over full history, with each file classified by its content **at the time it
was added**:

| repo              | glob-target dir    | arrivals | non-shell |
| ----------------- | ------------------ | -------: | --------: |
| dotfiles          | `tests/mocks/`     |       64 |     **0** |
| dotfiles          | `scripts/`         |       25 |     **1** |
| math              | `tests/mocks/`     |        4 |     **0** |
| math              | `scripts/`         |       12 |     **4** |
| ai-config         | `scripts/`         |       10 |     **2** |
| terraform_ansible | `ansible/scripts/` |       15 |    **11** |
| etch-cli          | `scripts/`         |        6 |     **2** |
|                   |                    |  **136** |    **20** |

**So the base rate is zero for `tests/mocks/` and 20 fleet-wide for the class.** Both numbers
are real and they answer different questions. The round-3 assumption line asked the narrow one
and got zero; the design protects against the wide one.

`terraform_ansible` is the sharpest row: **11 of 15** arrivals into `ansible/scripts/` were
non-shell. A pathspec globbing that directory would have been broken almost immediately, and
repeatedly.

**Why dotfiles has never felt this, and why that is the argument rather than a counter to it.**
The current pathspec reaches its two extensionless hooks by _naming them individually_ rather
than globbing `scripts/*` — and it must, because `scripts/` mixes shell and non-shell. That
hand-naming is precisely the defect class this spec exists to remove. The repo is not immune
to the hazard; it has been paying for immunity in the currency the spec objects to.

One honest subtraction: dotfiles' single instance, `scripts/dropbox.py`, lived 2020-04-06 to
2023-11-24, while `scripts/pre-push` and `scripts/commit-msg` arrived 2026-04 and 2026-05. They
never coexisted, so dotfiles has not actually had the collision — only the conditions for it.
The fleet-wide 20 is what carries the argument; the dotfiles row does not, and is reported at
its real strength rather than at the strength the conclusion would prefer.

**This also dissolves a tension rather than resolving it.** The recorded-not-fixed item — no
case pins that the set is _derived_ rather than _enumerated_, so a hardcoded list of the correct
100 passes every case — is tolerable only because additions are frequent enough that such a list
reddens soon. That is the same arrival rate the base-rate question turns on, and the two look
like they pull opposite ways: frequent arrivals make an enumerated list fail loudly (good) but
also make a non-shell arrival plausible (bad for the pathspec). Measured, there is no tension:
**136 arrivals and 20 non-shell ones**. Additions are frequent, so an enumerated list fails
loudly; and non-shell arrivals into mixed directories demonstrably happen, so the property the
script buys is exercised. Both arguments point the same way once the number exists.

### Convergence — round 5 not scheduled

**Four rounds, four sets of introduced defects.** The honest read is that the fix rate is not
outrunning the defect rate, and a fifth round should be expected to find a fifth set rather
than to come back clean.

Two things argue against simply continuing. First, the findings are narrowing sharply in
consequence: round 1 cut the scope by two thirds, round 3 invalidated the entire
justification, round 4's are a fixture filename, a redirect order, and two mutation rows that
named no target. Second, three of round 4's four fixes **removed** machinery rather than
adding it — the floor count is gone entirely — which is the direction that ends this kind of
loop, since each round's defect has lived in the machinery the previous round added.

The proportionality question the round-4 note left open is now **measured and answered** — see
the base-rate sweep above. The property is exercised **20 times across five repos**; the zero
that made it look like insurance against nothing was an artifact of scoping the question to
`tests/mocks/` rather than to the class of directories a pathspec must glob. dotfiles avoids the
hazard today only by hand-naming its two hooks, which is the defect the spec targets.

What remains for the operator is narrower and no longer turns on an unmeasured number: whether
+43ms per `make` invocation and eleven test cases are worth removing a two-entry hand-maintained
list, given the fleet has hit the underlying hazard 20 times and this repo has not yet.

**The most transferable finding is not about shell at all.** For four rounds the base-rate
question was asked about `tests/mocks/` and returned 0 of 68, which read as "insurance against
nothing" and nearly retired the design. The hazard's real domain was the class of directories a
pathspec must glob, where it returns 20 of 136. Three independent lenses, four rounds, and every
one of them attacked the _answer_ rather than the _scope of the question_ — which is
`behavior.md`'s "a claim is only as wide as the boundary its measurement covered", encountered
from the inside: the boundary was wrong in the direction that made the evidence look conclusive.
