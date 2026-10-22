# CLAUDE.md ceiling ratchet Implementation Plan

spec: docs/superpowers/specs/2026-10-22-claude-md-ceiling-ratchet-design.md

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Lower the `CLAUDE.md` byte ceiling from 105,000 to 85,000, put the remedy in the checker's own refusal message, and close the relocation backlog row.

**Architecture:** One constant and one message in `scripts/claude_md_budget.py`, one reworded line in `scripts/pre-push`, boundary tests moved in the Python and bats suites, then an ADR-0047 amendment and backlog bookkeeping.

**Tech Stack:** Python 3 (`unittest`), bash, bats.

## Global Constraints

- Ceiling: `CEILING = 85_000` bytes, measured in bytes, not characters.
- Refusal message: `CLAUDE.md is <n> bytes, ceiling <CEILING>; move detail to ai-config/docs/knowledge/dotfiles-*.md (ADR-0047)`.
- Hook line: `Any message from git or the checker is above.`, with no figure and no remedy.
- No flag, environment variable or trailer that skips or changes the ceiling (N2).
- No `CLAUDE.md` content change (N1); no ai-config file change (N3).
- `tests/test_claude_md_budget.py` keeps its own literal `CEILING = 85_000`, never imported from the script (R7).
- The checker keeps reading `HEAD:CLAUDE.md` via `git show`; `make test` is unchanged.

## Verification

- `make test` exits 0 on the branch (orchestrator, once, after Task 2).
- `python3 scripts/claude_md_budget.py HEAD` prints `CLAUDE.md at HEAD is 75341 bytes (ceiling 85000).` (or the branch's current size) and exits 0.
- Red step: with only the tests changed, the 85,001-byte refusal tests fail against `CEILING = 105_000` (V1). Edge cases: exactly 85,000 allowed, 85,001 refused, 85,002-byte multibyte file refused, the no-checker push passes without the hook header, the remedy text appears in both the checker's and the hook's output.
- Measured at plan time: `bats --filter 'budget gate' tests/scripts/pre_push.bats` runs 10 tests in about 2 s; the R3 grep on master hits only the four files Task 1 edits.

---

### Task 1: Lower the ceiling and move the remedy into the checker

```yaml-task
id: 1
description: CEILING 85_000 with remedy in the checker's refusal message, hook line reworded, boundary tests moved to 85,000
role: executor
model: sonnet
tdd: required
requirements: [R1, R2, R3, R4, R7]
acceptance:
  - cmd: python3 -m unittest discover -s tests -p 'test_claude_md_budget.py'
    exit_code: 0
  - cmd: bats --filter 'budget gate' tests/scripts/pre_push.bats
    exit_code: 0
  - cmd: make lint
    exit_code: 0
  - cmd: grep -qx 'CEILING = 85_000' scripts/claude_md_budget.py
    exit_code: 0
  - cmd: grep -qx 'CEILING = 85_000' tests/test_claude_md_budget.py
    exit_code: 0
  - cmd: grep -qF 'Any message from git or the checker is above.' scripts/pre-push
    exit_code: 0
  - cmd: bash -c "! git grep -qE '105,000|105_000|105000|105001|105002' -- . ':!docs/superpowers/specs' ':!docs/superpowers/plans' ':!docs/adr'"
    exit_code: 0
max_retries: 3
files_touched:
  - scripts/claude_md_budget.py
  - scripts/pre-push
  - tests/test_claude_md_budget.py
  - tests/scripts/pre_push.bats
depends_on: []
```

**Files:** the four above.

- [ ] **RED.** Edit the tests only:
  - `tests/test_claude_md_budget.py`: `CEILING = 85_000` (line 15, a literal; never import it). Replace `105001`→`85001`, `105000`→`85000`, `105002`→`85002` in assertions (lines 74, 75, 92, 126, 155, 243). Multibyte case: `text = "é" * 42_501  # 42,501 characters, 85,002 bytes`. In `test_one_over_ceiling_refused` add `self.assertIn("ai-config/docs/knowledge/dotfiles-*.md", result.stderr)` and `self.assertIn("ADR-0047", result.stderr)`.
  - `tests/scripts/pre_push.bats` (budget section, ~1102-1235): every `_budget_commit 105001`→`85001`, `105000`→`85000`, `105002`→`85002`; test names to match. Replace each `[[ "$output" == *"105,000 bytes"* ]]` with `[[ "$output" == *"ADR-0047"* ]]` and `[[ "$output" == *"dotfiles-*.md"* ]]` (quoted, matched literally). `bytes, ceiling 105000` → `bytes, ceiling 85000`. In "predates the checker" replace `!= *"105,000 bytes"*` with `[[ "$output" != *"CLAUDE.md budget check failed"* ]]`.
- [ ] Run both suites; paste the failing lines. Expect the 85,001/85,002 refusal cases and the `ADR-0047` assertions to fail (checker still allows up to 105,000 and prints no remedy). Exit 1 from a real assertion, not a usage error.
- [ ] **GREEN.** `scripts/claude_md_budget.py`: comment above `CEILING` becomes `# Set by ADR-0047 (amended 2026-10-22); changing it needs another amendment to that ADR.`; `CEILING = 85_000`; refusal line becomes `print(f"CLAUDE.md is {size} bytes, ceiling {CEILING}; move detail to ai-config/docs/knowledge/dotfiles-*.md (ADR-0047)", file=sys.stderr)`. Do not touch the mode-refusal or pass messages.
- [ ] `scripts/pre-push:179`: replace the printf with `printf 'Any message from git or the checker is above.\n' >&2`.
- [ ] Run every acceptance command; all exit 0.
- [ ] Commit (message via `caveman:caveman-commit`).

**Interfaces:** Produces the refusal text above, which Task 2's ADR quotes.

### Task 2: ADR-0047 amendment and backlog bookkeeping

```yaml-task
id: 2
description: ADR-0047 amendment and closed backlog row plus index rows (docs-only, no behaviour change, so TDD does not apply)
role: executor
model: sonnet
tdd: not-applicable
requirements: [R5, R6]
acceptance:
  - cmd: grep -q '^## Amendments' docs/adr/0047-claude-md-size-ceiling.md
    exit_code: 0
  - cmd: grep -qE '85,000-byte ceiling' docs/adr/0047-claude-md-size-ceiling.md
    exit_code: 0
  - cmd: grep -qE 'Move CLAUDE.md reference text to knowledge files.*CLOSED 2026-10-22, superseded by ADR-0047' docs/superpowers/README.md
    exit_code: 0
  - cmd: grep -qF 'plans/2026-10-22-claude-md-ceiling-ratchet.md' docs/superpowers/README.md
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched:
  - docs/adr/0047-claude-md-size-ceiling.md
  - docs/superpowers/README.md
depends_on: [1]
```

**Files:** the two above.

- [ ] ADR-0047 decision 2: "A hard 105,000-byte ceiling" → "A hard 85,000-byte ceiling (amended 2026-10-22; see Amendments)". Leave the Basis section's history as written.
- [ ] Append before `## Related` a `## Amendments` section with one dated entry, `### 2026-10-22: ceiling lowered to 85,000 bytes`, stating: the 85,000-byte ceiling; measured sizes 74,272 B (`48087820`, 2026-10-18) to 75,341 B (`74fcd339`, 2026-10-21), +1,069 B over five commits; 80,000 offered and declined as too tight; lowering, like raising, needs an amendment; the refusal message now carries the remedy so `make test` and CI show it; the open question whether the post-ceiling rate (about 214 B per commit) or the pre-ceiling rate (about 600 B per commit) holds, and that the next amendment records whether the first change to reach 85,000 relocated text or raised the ceiling. Cite `specs/2026-10-22-claude-md-ceiling-ratchet-design.md`.
- [ ] `docs/superpowers/README.md`: cut the row starting `| Move CLAUDE.md reference text to knowledge files |` from P3 — tech-debt and append it as the last row of the "Closed without shipping" table (the table directly above `## Adding a new entry`, never an open table). Title: `Move CLAUDE.md reference text to knowledge files — CLOSED 2026-10-22, superseded by ADR-0047`. Prepend to its notes: `**Closed 2026-10-22:** grouping, one line per rule and the rule-by-rule review shipped with ADR-0047; the UTF-16 target was replaced by its byte ceiling, lowered 2026-10-22 (see ADR-0047 Amendments and specs/2026-10-22-claude-md-ceiling-ratchet-design.md).` Do not write any ceiling figure in the row.
- [ ] Add an All Plans index row above the 2026-10-21 rows: `| 2026-10-22 | [CLAUDE.md ceiling ratchet](plans/2026-10-22-claude-md-ceiling-ratchet.md) | [CLAUDE.md ceiling ratchet: 85,000 bytes, remedy in the checker](specs/2026-10-22-claude-md-ceiling-ratchet-design.md) | In Progress |`.
- [ ] Run the acceptance commands; commit.

**Orchestrator after Task 2:** run `make test </dev/null` once (V2), notify other dotfiles sessions of the 85,000 figure before merge (V3), then Phase 3.

## Non-goal check

Reviewer verdicts (2026-10-22, fresh reviewer, `nongoal-check.md`):

- N1 CLEAR — "None of them is `CLAUDE.md`. The checker still reads `HEAD:CLAUDE.md` but does not write it." No resolution needed.
- N2 CLEAR — "the plan adds no override path. It only changes the constant and the message text." No resolution needed.
- N3 CLEAR — "the new refusal message names the path `ai-config/docs/knowledge/dotfiles-*.md` as text, but nothing writes to ai-config." No resolution needed.
