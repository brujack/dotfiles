# Design: derive the shell lint scope by shebang, not by filename

**Date:** 2026-08-15
**Status:** Proposed
**Repos affected:** dotfiles (PR 1), math (PR 2), ai-config `shell.md` (PR 3)

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

| repo              | current scope | shebang-derived | delta | of which template/fixture | net new lintable | new findings |
| ----------------- | ------------: | --------------: | ----: | ------------------------: | ---------------: | -----------: |
| dotfiles          |            35 |             100 |    65 |                         0 |           **65** |        **5** |
| math              |            25 |              32 |     7 |                         0 |            **7** |            0 |
| ai-config         |            32 |              42 |    10 |                        10 |                0 |            0 |
| terraform_ansible |            20 |              28 |     8 |                         8 |                0 |            0 |
| etch-cli          |             4 |               4 |     0 |                         0 |                0 |            0 |

Measured 2026-08-15 on the Mac Studio, shellcheck 0.11.0. **Zero files are lost in any
repo** — the shebang-derived set is a strict superset of the current pathspec everywhere,
verified by `comm -23` in both directions.

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
114 bytes, so the parse-time cost is bounded regardless of file size — measured 0.03s
against the pathspec's 0.01s, over 406 tracked files.

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

## Scope

### PR 1 — dotfiles

- Add `scripts/list-shell-files.sh`; `SHELL_FILES` calls it. 35 → 100 files.
- Keep the existing empty-list guard. It now also covers a broken or missing script:
  the derivation fails closed rather than linting nothing and reporting a pass.
- Fix the 5 findings the widening surfaces:
  - `tests/mocks/brew`, 4 × `SC2086` — **site suppression with the reason, not a quote.**
    `printf "%s\n" ${MOCK_BREW_LEAVES:-}` relies on word splitting: it is what turns
    `MOCK_BREW_LEAVES="bat git"` into `brew leaves`' one-per-line output. Quoting collapses
    it to a single line and breaks `tests/setup_env/brewfile_drift.bats`. This is exactly the
    case `shell.md` names for a site-local disable.
  - `tests/mocks/gpg`, 1 × `SC2034` — **real fix.** `while IFS= read -r line; do :; done`
    drains stdin and never reads `line`; rename to `_`.
- CI `lint-macos`: replace the `find`-based `bash -n` step with the derived list via
  `make print-SHELL_FILES` (`print-%` already exists at `Makefile:147`). This also deletes a
  dead exclusion — the job carries `-not -path './tests/mocks/*'` under a `-name '*.sh'`
  predicate that never matched an extensionless mock in the first place, so that line has
  never excluded anything.
- Update `CLAUDE.md`: the "35 tracked shell files" figure, the ShellCheck section's scope
  paragraph, and the note stating mocks are covered by nothing.
- Remove the `make lint cannot see any of the 64 mocks` backlog row.

### PR 2 — math

- Same script, same rule. `SHELL_TRACKED` 25 → 32, **0 new findings**.
- Collapse `SHELL_SOURCES := $(SHELL_TRACKED)`. The split exists solely so that appending
  three literal hook paths cannot mask an empty `git ls-files` — with no literal appends
  left, it has no job. The empty-guard stays on the derived value.
- math has no scope tests today; add them (see Test Oracle).
- Update math's `CLAUDE.md` figure.

### PR 3 — ai-config `shell.md`

- Replace the mandated pathspec pattern with shebang derivation.
- State the exclusion as a **predicate** — _a template extension (`.j2`, `.tpl`), or a
  deliberately-defective pitfall fixture_ — never a filename list. This matters because the
  two deferred repos need one:
  - ai-config tracks 10 shebang-carrying `tests/fixtures/shell-pitfalls/*.fixture` files.
    **3 of the 10 fail shellcheck by design** — `SC2168` (`local` outside a function),
    `SC2155`, and `SC2072` (decimal comparison) — because reproducing those findings is the
    fixtures' entire purpose. The remaining 7 pass today, but they are defective-by-intent
    source whose whole job is to demonstrate defects; they are excluded as a class rather
    than by current verdict, since a shellcheck upgrade that starts flagging one of the 7
    would turn `make lint` red for a file working as designed.
  - terraform_ansible tracks 5 `.sh.j2` and 3 `.sh.tpl` templates that are not shell at all
    — one carries 39 Jinja lines — producing 38 findings between them.
- Update the "Where the repos actually stand" table.
- One cross-cutting backlog row in ai-config covering adoption in the three deferred repos,
  carrying the measured reason.

## Deferred, with the measurement that decided it

ai-config, terraform_ansible and etch-cli are **not** changed in this cycle. Each gains
**zero** net new lintable files. Two of the three would additionally require inventing and
testing an exclusion predicate purely to gain that zero, and etch-cli's diff would be a
literal no-op — its 4 tracked shell files already are its shebang set exactly.

What they would still gain is drift-immunity: no hand-named hook list to forget. That is
real but not urgent, and it is cheaper to take once `shell.md` carries the predicate and one
landed reference implementation exists.

Recording this as priced rather than missed is the point of the backlog row.

## Non-goals

- **The bash coverage denominator is untouched.** `scripts/run-bash-coverage.sh` derives its
  own instrumented set (`setup_env.sh` + tracked `config/*.sh lib/*.sh scripts/*.sh` + hooks,
  less `bash-tracer.sh`). Switching that to shebang derivation would sweep the 64 mocks into
  the denominator — and because the bats suite _executes_ mocks, into the numerator too. The
  figure would stop meaning "production code covered" while moving very little, which is the
  worst combination. The two derivations stay independent and the reason is recorded here so
  a later reader does not "unify" them as tidiness.
- **`BATS_FILES` is unchanged**, still linted separately at `--severity=warning`. bats' own
  `run`/`@test` model emits `SC2030`/`SC2031` structurally; that tier is about bats, not about
  the code.
- **No exclusion predicate is implemented in dotfiles or math.** Both have zero
  template/fixture files, so the exclusion would be unfalsifiable — no test could distinguish
  it working from it being absent. Adding an untestable branch to guard against a file class
  that does not exist is the exact defect shape this change removes.

## Test oracle

`SHELL_FILES` is now shebang-derived, so a test that re-derives it from shebangs is circular
and can only agree — `behavior.md`, "a check derived from the same decision as the thing it
checks cannot falsify it."

**The oracle is the old pathspec, i.e. a different mechanism: name.** Assert
`name-derived ⊆ shebang-derived` — every `*.sh`, `*.bash`, and named hook still appears. This
mirrors the existing `ZSH_FILES` test, which unions a name arm with a shebang arm for the same
reason and found `.zprofile` on its first execution.

Tests to add, in `tests/scripts/makefile_lint_scope.bats` (dotfiles) and a new equivalent in
math:

1. Every file matched by the old pathspec is present in `SHELL_FILES` (name oracle ⊆ derived).
2. `SHELL_FILES` is non-empty, and `make lint` exits non-zero when it is empty.
3. `SHELL_FILES` and `ZSH_FILES` remain disjoint.
4. A fixture file with each of the four rejected shebangs (`zsh` in all three spellings,
   `fish`) is **excluded**; one with each of the five accepted forms is **included**.
5. `SHELL_FILES` survives a leaked `GIT_DIR` pointed at a decoy repo — the existing
   `print-ZSH_FILES` test's shape, applied to the new derivation.
6. The count is identical under a `<4` make and a `>=4` make, per the repo's existing
   partition discipline.

## Verification

Commands already run, with real output, per `behavior.md`'s rule against predicted output:

| check                                  | expected                           | status       |
| -------------------------------------- | ---------------------------------- | ------------ |
| `scripts/list-shell-files.sh \| wc -l` | dotfiles 100, math 32              | **measured** |
| strict superset, no file lost          | 0 lost across all 5 repos          | **measured** |
| rejected shebangs                      | zsh ×3, fish, python3 all excluded | **measured** |
| new findings                           | dotfiles 5 (2 files), math 0       | **measured** |
| script form under make 3.81 and 4.x    | identical output                   | **measured** |
| inline `$(shell)` form                 | fails on both, two distinct causes | **measured** |
| parse-time cost                        | 0.03s vs 0.01s over 406 files      | **measured** |

Pending implementation:

| check                | expected                                                    |
| -------------------- | ----------------------------------------------------------- |
| `make lint`          | exit 0 after the two mock fixes                             |
| **mutation check**   | revert the `tests/mocks/gpg` fix → `make lint` goes **red** |
| `make test`          | exit 0, no regression against the 1334-test floor           |
| `make bash-coverage` | unchanged figure (denominator untouched)                    |

The mutation row is load-bearing. Without it a green `make lint` is equally consistent with
"mocks are linted and clean" and "mocks were silently dropped from the scope again" — which is
the original defect wearing the original disguise. `test-quality-review` Step 4b mandates this
technique; here it is the only check that distinguishes the fix from its absence.

## Risks

- **A file gains a shebang and silently enters the lint scope.** By design — that is the
  whole point — but it means a new file can turn `make lint` red without anyone editing the
  Makefile. Mitigated by the gate being local-first (pre-commit) so it surfaces immediately,
  not in CI.
- **A shell file with no shebang is now invisible where the pathspec would have caught it.**
  Measured as zero across all five repos today (the "lost" column is empty everywhere), but it
  is a genuine inversion of the failure mode. Test 1 pins it: if a `.sh` file ever lacks a
  shebang, the name-oracle test fails loudly rather than the file being dropped silently.
- **Parse-time I/O on every `make` invocation**, including `make help`. Measured at +20ms.
