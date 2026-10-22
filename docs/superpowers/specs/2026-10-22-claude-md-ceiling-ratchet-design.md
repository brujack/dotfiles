# CLAUDE.md ceiling ratchet: 105,000 to 85,000 bytes, and close the relocation row

- **Approved:** 2026-10-22
- **Status:** Approved
- **Follows:** ADR-0047 (CLAUDE.md size ceiling), ADR-0036 (relocation with pointers),
  `specs/2026-10-17-claude-md-budget-design.md`.

## Problem

The backlog row "Move CLAUDE.md reference text to knowledge files" still sits open. It was
deferred from the 2026-09-11 re-sort and lists four pieces of open work. Measured 2026-10-22
on master `d8c23166`:

- **File-based pointer grouping under a six-file cap: done.** `CLAUDE.md` carries 172
  `` → `<file>` `` matches, and 169 of them name five knowledge files
  (`dotfiles-conventions.md` 78, `dotfiles-test-seams.md` 58,
  `dotfiles-bats-test-infrastructure.md` 29, `dotfiles-bash-coverage.md` 3,
  `dotfiles-testing-toolchain.md` 1). The other three match the pattern but are not knowledge
  pointers (`writing-plans`, `firecrawl-cli`, and the `file` placeholder in the header).
- **Accounting at bullet granularity: done.** ADR-0047 decision 1 made every rule one line.
- **Rule-5 lines for non-derivable hazards: done.** The 2026-10-18 rule-by-rule review gave
  every original rule a verdict and restored 19 weakened or pointer-only rules (ADR-0047,
  Basis for the ceiling).
- **The ≤ 50,000 UTF-16-unit bar: replaced.** During the 2026-10-17 spec the operator moved
  from a 50,000-byte ceiling to 70,000 and then to 105,000, set from two dry runs (that
  spec's Multi-Lens Review dispositions). `CLAUDE.md` is 74,755 UTF-16 units and 75,341
  bytes. Reaching 50,000 would mean replacing ADR-0036's per-line pointers, whose 172
  suffixes alone are 15,473 units. The operator declined that on 2026-10-22.

So the row is superseded. What it was guarding against has not gone away, though: unbounded
regrowth. The file went from 122,627 B to 155,308 B in three weeks after ADR-0036.

The 105,000-byte ceiling now sits 29,659 bytes above the file. Measured sizes of
`CLAUDE.md` at each commit that touched it since the ceiling landed (`git show
<sha>:CLAUDE.md | wc -c`, population: every master commit touching the file since
`48087820`):

| date       | commit     | bytes  |
| ---------- | ---------- | ------ |
| 2026-10-18 | `48087820` | 74,272 |
| 2026-10-18 | `5b18e452` | 74,305 |
| 2026-10-20 | `6d7cfb31` | 74,774 |
| 2026-10-21 | `63ce5323` | 74,982 |
| 2026-10-21 | `487b303f` | 75,291 |
| 2026-10-21 | `74fcd339` | 75,341 |

That is +1,069 B over five commits in three days. At that rate the file reaches 105,000 B in
about 12 weeks. The cut from 155 KB to 75 KB would be about 40% given back before the gate
said anything.

A second copy of the ceiling has already appeared. `scripts/pre-push:179` hard-codes
"The ceiling is 105,000 bytes" in its own failure message, and nothing ties it to
`CEILING` in `scripts/claude_md_budget.py:20`. The checker's own message, printed just above
it, already names the ceiling (`CLAUDE.md is <n> bytes, ceiling <CEILING>`).

The remedy is in the wrong place too. Only the hook prints it. The same checker also runs
in `make test` (`Makefile:163`, through `check-claude-md-budget`) and in CI (`make test` on
the PR's merge ref), and both print only the bare figure. A branch cut before a ceiling
change passes its own pre-push (the hook runs the pushed commit's checker) and then fails in
CI with no remedy.

Detection is after the commit, by design. The checker reads `HEAD:CLAUDE.md` through
`git show`, never the working tree, so a `make test` before committing measures the
pre-edit file. That read is what keeps `tests/scripts/docs_inert_premise.bats` true (no
test reads a tracked `.md` from the working tree), which is what lets a docs-only push skip
the suite. The first refusal is therefore the pre-push hook, whose budget check runs before
its docs-only early exit, or a post-commit `make test`, or CI. This spec keeps that.

## Design

1. **Lower the ceiling to 85,000 bytes.** `scripts/claude_md_budget.py` sets
   `CEILING = 85_000`. That leaves 9,659 B of headroom over today's 75,341 B. At the measured
   rate the file reaches the ceiling in about four weeks. From then on, any change that grows
   `CLAUDE.md` moves detail out to a knowledge file in the same change, which is ADR-0047's
   remedy. 80,000 B was offered and declined as too tight; the operator chose 85,000 on
   2026-10-22.
2. **One copy of the number, and the remedy where every caller sees it.** The checker's
   refusal message carries both: `CLAUDE.md is <n> bytes, ceiling <CEILING>; move detail to
   ai-config/docs/knowledge/dotfiles-*.md (ADR-0047)`. The `scripts/pre-push` failure line
   becomes "Any message from git or the checker is above." (git's own error is what
   precedes it when `git ls-tree` or `git show` fails) and drops the figure and the remedy. The hook's `105,000 bytes` assertions in `tests/scripts/pre_push.bats` are
   replaced by assertions that the output names `ADR-0047` and `dotfiles-*.md`, so deleting
   the remedy fails a test; the `nochecker` case asserts the output does not contain the
   hook's own header `CLAUDE.md budget check failed`. `tests/test_claude_md_budget.py` asserts the remedy in the refusal message.
   The test file's own `CEILING = 85_000` stays a literal and is never imported from the
   script: it is the independent oracle the boundary tests compare against.
3. **Tests pin the new boundary.** In `tests/test_claude_md_budget.py` and
   `tests/scripts/pre_push.bats`, every 105,000 boundary fixture moves to 85,000: exactly
   85,000 B allowed, 85,001 B refused, and the 105,002-byte fixture moves to 85,002. The multibyte case becomes `"é" * 42_501`
   (42,501 characters, 85,002 bytes) and still shows bytes are counted, not characters. The
   red step runs the moved tests against the unchanged 105,000 constant: the 85,001-byte
   refusal cases must fail first.
4. **ADR-0047 amendment.** ADR-0047 gets a dated `## Amendments` entry. It records the new
   ceiling, the measured sizes and rate, the declined 80,000 option, and that lowering the
   ceiling, like raising it, needs an amendment. Decision 2's figure is updated to match and
   cites the amendment. The script comment at `CEILING` names the amendment. The amendment
   also states the open question the review raised: whether the post-ceiling rate (about
   214 B per commit) or the pre-ceiling rate (about 600 B per commit) is the real one, and
   that the next amendment records whether the first change to reach 85,000 relocated text
   or raised the ceiling.
5. **Close the row.** In `docs/superpowers/README.md`, "Move CLAUDE.md reference text to
   knowledge files" moves to the closed table, titled
   `— CLOSED 2026-10-22, superseded by ADR-0047`. Its note cites ADR-0047 and this spec for
   the evidence rather than restating any ceiling figure, so R3 holds. Index rows for this
   spec and its plan are added.
6. **Notice.** Lowering a ceiling can turn another session's push red. Before merge, any
   other session working in dotfiles is told the new figure (git-workflow-020).

## Out of scope

- Changing the pointer format, or moving any `CLAUDE.md` text.
- Any ai-config file.
- Measuring in UTF-16 units: the gate stays in bytes.

## Requirements

- **R1.** `[PR1]` `scripts/claude_md_budget.py` sets `CEILING = 85_000`, and `claude_md_budget.py <rev>` exits 1 for an 85,001-byte `CLAUDE.md` and 0 for an 85,000-byte one.
- **R2.** `[PR1]` `claude_md_budget.py`'s over-ceiling message names the size, the ceiling, `ai-config/docs/knowledge/dotfiles-*.md` and `ADR-0047`, and `scripts/pre-push`'s budget-failure line reads "Any message from git or the checker is above." with no ceiling figure.
- **R3.** `[PR1]` No tracked file outside `docs/superpowers/specs/`, `docs/superpowers/plans/` and `docs/adr/` contains `105,000`, `105_000`, `105000`, `105001` or `105002`.
- **R4.** `[PR1]` `tests/test_claude_md_budget.py` and `tests/scripts/pre_push.bats` test 85,000 B allowed, 85,001 B refused and an 85,002-byte multibyte file refused, and assert the refusal output names `85000`, `ADR-0047` and `dotfiles-*.md`; the pre-push `nochecker` case asserts the output lacks `CLAUDE.md budget check failed`.
- **R5.** `[PR1]` ADR-0047 carries an `## Amendments` entry dated 2026-10-22 stating the 85,000-byte ceiling, the measured 74,272 to 75,341 B growth, that lowering needs an amendment as raising does, and the open growth-rate question; decision 2 states 85,000.
- **R6.** `[PR1]` `docs/superpowers/README.md` has the relocation row in the closed table with `CLOSED 2026-10-22, superseded by ADR-0047`, citing ADR-0047 with no ceiling figure, not in any open table, and indexes this spec and its plan.
- **R7.** `[PR1]` `tests/test_claude_md_budget.py` defines `CEILING = 85_000` as a literal and does not import it from `scripts/claude_md_budget.py`.
- **V1.** The red step's output shows the 85,001-byte refusal tests failing against `CEILING = 105_000` before the constant changes.
- **V2.** `make test` exits 0 on the branch, and `claude_md_budget.py HEAD` reports a size at or below 85,000.
- **V3.** Every other session working in dotfiles has been sent the new figure before merge.
- **N1.** No `CLAUDE.md` content changes.
- **N2.** No flag, environment variable or trailer that skips or changes the ceiling (ADR-0047 decision 3 stands).
- **N3.** No ai-config file changes.

## Amendments

- R4 -> `tests/test_claude_md_budget.py` tests 85,000 B allowed, 85,001 B refused and an 85,002-byte multibyte file refused; `tests/scripts/pre_push.bats` tests 85,000 B allowed and 85,001 B refused; both assert the refusal output names `85000`, `ADR-0047` and `dotfiles-*.md`; the pre-push `nochecker` case asserts the output lacks `CLAUDE.md budget check failed`; and the 85,001-byte pre-push refusal asserts the hook's closing line `Any message from git or the checker is above.` with no `105,0` figure. — the multibyte case belongs to the checker's own suite (design 3), and Task 1 review found the hook's closing line untested.

## Multi-Lens Review

Reviewed at commit: `d1065025` (Step 7 self-review commit, before Step 8 dispatch)

### Goal-Fit

Finding: Worth building and near-minimal. One risk: design item 2's "one copy of the number" could lead an implementer to import `CEILING` into `tests/test_claude_md_budget.py`, making the boundary tests tautological; the test copy should stay an independent oracle.
Assumption: That `CLAUDE.md` still holds relocatable text when the ceiling bites. Measured about 21 KB of non-pointer prose (GitHub MCP, Profile Model, PowerShell prereqs, CI section). Settled by whether the first PR to reach 85,000 relocates text or raises the ceiling.
Disposition: Addressed — operator 2026-10-22: R7 keeps the test's literal; the assumption is accepted (round 2 moved its tracking from a backlog row into the ADR-0047 amendment).

### Ergonomics

Finding: The remedy is printed only by the hook, while `make test` and CI print a bare figure; and R2 had no test once the `105,000 bytes` assertions were deleted.
Assumption: That the post-ceiling rate (about 360 B/day over 3 days) holds rather than the pre-ceiling 1.5 KB/day, which would exhaust the headroom in about 6 days.
Disposition: Addressed — operator 2026-10-22: the remedy moves into the checker's refusal message (design 2, R2), assertions on `ADR-0047` and `dotfiles-*.md` replace the deleted ones (R4); the rate assumption is accepted (round 2 moved its tracking into the ADR-0047 amendment).

### Risk

Finding: Deleting the hook's `105,000 bytes` assertions leaves the remedy line untested; R3 misses `105002` at `tests/scripts/pre_push.bats:1224`. Checked and not raised: stale branches fail closed in CI, no open PR or branch exceeds 85,000 B, R3's scope is otherwise complete.
Assumption: No uncertain assumption found (no in-flight branch exceeds 85,000 B, settled by command); the growth rate changes only when the gate bites.
Disposition: Addressed — operator 2026-10-22: R3 adds `105002` and the fixture moves to 85,002; R4 asserts the remedy.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.

### Round 2 (reviewed at commit `77c39096`)

- Goal-fit: worth building and near-minimal. Findings: the R8 re-measure row is decoration (no decision depends on the rate, nothing triggers it); the closed row's evidence would restate the old figure and break R3. Assumption: when 85,000 is first reached, relocating text is cheaper than raising (about 21 KB of non-pointer prose against 9.7 KB of headroom).
- Ergonomics: the Problem section's "`make test` is where a session meets the limit first" is false, since the checker reads `HEAD` only; and "The checker's own message is above" is false when `git ls-tree` or `git show` fails. Assumption: post-commit detection is acceptable.
- Risk: the closed row versus R3 (as Goal-fit); the `nochecker` test's `ADR-0047` absence assertion cannot fail once the hook stops printing the remedy. Assumption: no uncertain assumption found (no open PR, no branch over 80,000 B).

Disposition: Addressed — operator 2026-10-22, all five: R8 dropped and the rate question moved into the ADR-0047 amendment (design 4, R5); the closed row cites ADR-0047, not a figure (design 5, R6); the Problem section states detection is post-commit by design (the `HEAD`-only read keeps `docs_inert_premise.bats` true), and `make test` is unchanged; the hook line reads "Any message from git or the checker is above." (R2); the `nochecker` case asserts the hook's header is absent (R4). Wording- and test-level changes with the design smaller; no round 3, by the operator's choice.
