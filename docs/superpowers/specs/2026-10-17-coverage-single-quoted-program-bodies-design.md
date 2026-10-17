# Bash coverage: exclude multi-line single-quoted program bodies

- **Date:** 2026-10-17
- **Status:** Draft (Phase 1), revised after Step 8 round 1
- **Trigger:** PR #343 (apt stale-signer detection). CI `bash-coverage` read
  `TOTAL 5798 6372 90%` against the 91% gate. The same job's first attempt was cancelled at its
  25-minute cap.

## Problem

`_count_coverable_lines` (`scripts/run-bash-coverage.sh`) counts every non-blank, non-comment,
non-structural line as a coverable command, apart from a few documented exclusions. One of those
exclusions is the body of a multi-line `python3 -c "..."`, which bash xtrace reports as a single
command.

The **single-quoted** form of the same thing has no exclusion. That means a multi-line argument
opened with `'` and closed on a later line, as in `awk … '`, `python3 -c '` or `bash -lc '`. Every
body line counts as coverable and can never be traced, so each one reads as permanently uncovered.

PR #343 put a 28-line `awk` program in `_apt_stale_signer_hosts` (`lib/linux_shared.sh`). That
file's coverable count went from 81 on master to 122 on the branch, and the CI total dropped to
90.99%, which prints as 90%. The new code is tested. The lines it "misses" are awk, not bash.

The CI job's cap is a second, separate problem. `ci.yml` has
`timeout-minutes: 25 # p90 492s, measured 2026-08-27`, and the last 11 CI runs of the job took
14–24 minutes. The cap now sits at about 1x a current run, while the repo's own sizing rule
(CLAUDE.md, CI section) calls for about 3x p90. The slowdown itself is unexplained.

## Measurements

All measurements are from 2026-10-17.

- **M1, PR #343 CI.** Attempt 2's job log reads `TOTAL 5798 6372 90%` /
  `FAIL: bash coverage 90% is below the 91% gate`. Attempt 1 was cancelled in the coverage step
  at 25m13s. Population: one CI run of #343's head `06782300`, on `ubuntu-latest`.
- **M2, coverable count.** `bash scripts/run-bash-coverage.sh --count-coverable` gives 81 for
  `lib/linux_shared.sh` on `origin/master` and 122 at `06782300`, where the awk program spans
  lines 189–218. Population: that one file, on `claude`.
- **M3, rule population on master.** Two independent scans of the instrumented set
  (`--list-sources`) on `claude` found 7 genuine multi-line single-quoted regions, 117 body
  lines in all:
  - `lib/developer.sh:573` (4)
  - `lib/helpers.sh:1030` and `:1072` (13 + 13)
  - `lib/workflows.sh:1353`, `:1393` and `:1428` (29 + 24 + 25)
  - `scripts/refresh-sha256-pins.sh:32` (9)

  One was the orchestrator's own scan. The other was the round-1 risk and ergonomics lenses'
  Python simulation, which also tracked heredoc and `python3 -c "` regions. A raw quote-parity
  rule also flags `scripts/run-bash-coverage.sh:128` as an opener that never closes. That line
  is `_heredoc_open_re='<<-?…["'"'"']?(…)'`: it contains 5 `'` but is a closed one-line
  assignment.

- **M4, xtrace attribution.** Measured with `PS4='+L${LINENO}: ' bash -x` on bash 5.3.9 on
  `claude` and on bash 5.2.21 in `ubuntu:24.04`, run as a non-root user. Bash ignores an
  inherited `PS4` when running as root.
  - A plain command or pipeline whose single-quoted argument spans lines is traced at its
    **opener** line, on both versions.
  - A multi-line `out=$(… | awk '…')` is traced at its **closer** line: the assignment and the
    outer command are at L7 of a 7-line fixture on both versions.
  - The command inside that `$(…)` is traced at L7 on 5.3.9 and at **L9, past end of file**, on
    5.2.21. That shape already exists on master, so the effect is not new. V2 checks that the
    tracer tolerates it.

## Design

### 1. A quote-state lexer in `_count_coverable_lines`

Every line not consumed by an existing exclusion passes through a small lexer. The lexer keeps a
context stack across lines. Its contexts are `CMD` (top level, or inside a `$(`), `DQ`, `SQ` and
`ANSI` (`$'…'`).

| Context | Characters it acts on                                                                                                                                                   |
| ------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `CMD`   | `\x` skips `x`. `'` pushes `SQ`. `$'` pushes `ANSI`. `"` pushes `DQ`. `$(` pushes `CMD`. `)` pops a `$(`-`CMD`. `#` at the start of a word ends the line, as a comment. |
| `DQ`    | `\x` skips `x`. `"` pops. `$(` pushes `CMD`.                                                                                                                            |
| `SQ`    | `'` pops. Nothing else.                                                                                                                                                 |
| `ANSI`  | `\x` skips `x`. `'` pops.                                                                                                                                               |

- **Region.** A line that **ends** with `SQ` on top of the stack opens a region. That is the
  opener. The region covers every following line up to and including the first line on which
  that `SQ` is popped, which is the closer.
- **Which line counts.**
  - Opener, body and closer are one command, so exactly one of the opener and closer counts and
    every body line is excluded.
  - If the stack beneath the opening `SQ` holds a `$(`-`CMD`, the region is inside a command
    substitution. Bash traces it at the closer (M4), so the **closer counts and the opener is
    excluded**.
  - Otherwise the **opener counts and the closer is excluded**.
  - If the guess is ever wrong, the union with the real trace adds the traced line back. That
    can only lower the figure.
- **Scope.** The lexer decides only single-quoted regions. It tracks `DQ` and `ANSI` so that an
  apostrophe inside them is not misread. Multi-line double-quoted strings, other than the
  existing `python3 -c "` rule, stay counted exactly as today.
- **Interaction with existing exclusions.**
  - A line consumed by the heredoc, `python3 -c "`, array or continuation logic is never fed to
    the lexer.
  - The lexer's stack resets to empty whenever one of those regions closes, so a skipped line
    cannot leave stale state.
- **Unterminated.** If the file ends with `SQ` open, the coverage run exits non-zero and names
  the opener line, matching the existing unterminated-`python3 -c` behaviour. A file that ends
  with `DQ` or `ANSI` open is not an error for this rule.
- **Direction of error, restated.**
  - Line 128's `'"'"'` splice, `$'it\'s'`, a bare `\'` and an apostrophe inside a multi-line
    double-quoted string all end with `SQ` closed under the lexer. So none of them opens a
    region.
  - A lexer gap that misses a real region leaves its lines counted, which lowers the figure.
  - A lexer gap that opens a false region could exclude real lines and **raise** the figure. V1
    is the landing check against that: every excluded line must belong to an M3 region.

### 2. CI cap (`.github/workflows/ci.yml`)

- The `bash-coverage` job's `timeout-minutes` goes from 25 to 60. Its comment records the basis:
  runs of 14–24 minutes, measured 2026-10-17, so 60 is about 3x a typical run.
- In `CLAUDE.md`, the CI caps sentence's "`bash-coverage` 25" becomes 60.
- A P2 CI backlog row records the slowdown: about 3x since 2026-08-27, cause unmeasured. The
  raised cap must not become the only record of it.

### 3. Documentation

`CLAUDE.md`'s Bash coverage bullet ("Exclude: heredoc bodies/terminators …") gains a fifth
case. It names the single-quoted region, the lexer, and the opener/closer choice for `$(…)`.

## Alternatives

- **Quote-parity rule.** This was the first draft. Round 1 refuted it:
  - `run-bash-coverage.sh:128` opens a region that never closes, which turns CI red on every PR.
  - `$'it\'s'`, `\'` and apostrophes inside multi-line double-quoted strings open false regions
    that swallow real lines and fail green.
- **Opener with exactly one `'`.** Narrower, but it still misreads multi-line double-quoted
  strings and still gets `$(…)` attribution wrong.
- **awk only, or move the awk to a `.awk` file.** Fixes #343 alone and leaves the 7 master
  regions counted as uncoverable.
- **Lower the gate.** Not considered: the figure is wrong, not the floor.

## Testing

New tests go in `tests/scripts/unit.bats`, beside the `python3 -c` ones. Each builds its fixture
with a heredoc, as the existing tests do, and runs `_run_coverage --count-coverable`. Every case
asserts an exact count.

1. A multi-line `awk -v x="$1" '` program between two bash lines counts 3: both bash lines plus
   the opener.
2. A multi-line `python3 -c '` program counts the same 3.
3. A multi-line awk inside `out=$(… | awk '` … `')` counts the closer, not the opener: the count
   is the bash lines plus 1, and the `--count-coverable` lines-mode output (`_count_coverable_lines
<file> lines`, reached through the CLI or an existing test helper, never by sourcing the
   script) names the closer's line number.
4. A closer with trailing words, `' "$1"`, is excluded, and the next bash line still counts.
5. A single-line `awk '{print $1}' file` counts as 1 and opens no region.
6. **Line 128, verbatim**
   (`_heredoc_open_re='<<-?[[:space:]]*["'"'"']?([A-Za-z_][A-Za-z0-9_]*)'`) opens no region. A
   following bash line still counts, and the run does not fail.
7. `q=$'it\'s'`, `r=it\'`, and a two-line `msg="user's` / `choice: it'"` each open no region.
   Every bash line after them still counts.
8. A file that ends inside a single-quoted region exits non-zero and names the opener line.
9. **Excerpt fixture:** one real region copied from `lib/helpers.sh` (the `awk -v dot= …` block,
   opener to closer, with one bash line on each side) counts exactly 3.

Mutation controls for the plan:

- Drop the `DQ` context: case 7's double-quoted line opens a region, and the count falls.
- Drop the `$(` attribution: case 3 names the opener.
- Drop the `ANSI` context: case 7's `$'it\'s'` opens a region.
- Drop the closer exclusion: case 1's count rises.

## Requirements

- **R1.** `_count_coverable_lines` runs a quote-state lexer with contexts CMD, DQ, SQ and ANSI (`$'…'`), honouring backslash escapes outside SQ, `$(`/`)` nesting and word-initial `#` comments, over every line no existing exclusion consumes, resetting its stack when an existing exclusion region closes.
- **R2.** A line that ends with SQ on top of the lexer stack opens a region whose body lines are excluded, and the region ends on the first line where that SQ is popped (the closer).
- **R3.** Of a region's opener and closer, exactly one is counted: the closer when the opening SQ sits inside a `$(` context, otherwise the opener.
- **R4.** A file that ends with SQ open makes the coverage run exit non-zero with a message naming the opener line number; DQ or ANSI open at end of file is not an error.
- **R5.** `.github/workflows/ci.yml` sets `timeout-minutes: 60` for the `bash-coverage` job, with a comment giving the 2026-10-17 measurement basis.
- **R6.** `CLAUDE.md` lists the single-quoted-region case in the Bash coverage exclusion bullet and gives `bash-coverage` a cap of 60 in the CI caps sentence.
- **R7.** `tests/scripts/unit.bats` contains tests 1–9 from the Testing section, each asserting an exact count, and they pass.
- **V1.** On the branch, run `--count-coverable` over every `--list-sources` file before and after the change; record each file whose count moves and the total moved, and confirm every newly excluded line lies inside one of M3's seven regions and `scripts/run-bash-coverage.sh`'s own count does not move.
- **V2.** Run `bash scripts/run-bash-coverage.sh` (full trace) on the branch; record the overall figure and confirm the heuristic-disagreement count does not rise above master's and the run does not fail on bash 5.3.9.
- **V3.** After merge, re-run PR #343's CI on its head rebased onto the new master; `bash-coverage` passes the 91% gate within the cap on `ubuntu-latest` (bash 5.2.21).
- **N1.** The `python3 -c "`, heredoc, array and continuation exclusions behave exactly as before; every existing `run-bash-coverage` test passes unchanged.
- **N2.** The 91% floor and the union-with-trace rule are unchanged.
- **N3.** No line is excluded on the basis of a tool name; the rule is structural only.
- **N4.** Multi-line double-quoted strings other than `python3 -c "` are not excluded by this change.

## Multi-Lens Review

Reviewed at commit: `8583c586` (Step 7 self-review commit, before Step 8 dispatch)

### Goal-Fit

Finding:

1. Test 9 pinned live `lib/helpers.sh` at 907, which makes it a maintenance trap. Tests 1–3
   already catch a no-op rule.
2. The "cannot raise the figure" claim was false: a false opener that closes early drops real,
   untraced lines.
3. The 60-minute cap hides a 3x slowdown.

Assumption: a region inside `$(…)` or a pipeline is traced at its opener. The orchestrator
measured it (M4): pipelines are traced at the opener, and `$(…)` at the closer.

Disposition: **Addressed (operator, 2026-10-17).**

- Test 9 became an excerpt fixture, with V1 as the landing check.
- The error-direction claim was restated, and the lexer replaces parity.
- The cap stays at 60, with a backlog row for the slowdown.
- `$(…)` attribution is now R3.

### Ergonomics

Finding:

1. **HIGH:** `scripts/run-bash-coverage.sh:128` (`'"'"'` splice, 5 quotes, ends in `'`) opens an
   unterminated region. R2's loud failure would then fire on master's own code and turn CI red on
   every PR. M3's scan hid it because it reported only regions that closed.
2. **LOW:** the cap is sized to the symptom.

Assumption: no legitimate line outside a program body ends in `'` with an odd count. Line 128
refutes it.

Disposition: **Addressed (operator, 2026-10-17).**

- Finding 1: the quote-state lexer reads line 128 as closed, and test 6 pins line 128 verbatim.
- Finding 2: backlog row.

### Risk

Finding:

1. **HIGH:** the same line-128 blocker.
2. **HIGH:** fail-green is reachable. `q=$'it\'s'`, `r=it\'`, and an apostrophe inside a
   multi-line double-quoted string open false regions that swallow real, untested lines up to
   the next genuine closer. That raises the figure without tripping the EOF failure.
3. **LOW:** `$(…)` is traced at the closer.

Assumption: bash 5.2.21 attributes to the opener as 5.3.9 does. The orchestrator measured it in
`ubuntu:24.04`, running as non-root (M4): plain commands are the same on both versions. `$(…)`
goes to the closer on both, and 5.2 places the inner command past EOF.

Disposition: **Addressed (operator, 2026-10-17).**

- The lexer tracks DQ and ANSI context, and test 7 pins each shape.
- R3 sets the `$(…)` attribution.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.
