# CLAUDE.md budget: one line per block, and a hard cap that stops regrowth

- **Status:** Draft
- **Revision:** 3 (300/520 caps with a `LIVE:` marker; revision 2 was infeasible)
- **Follows:** ADR-0036 (CLAUDE.md relocation), ai-config ADR-0077 (CLAUDE.md content homes).

## Problem

Measured 2026-10-17 on `claude` with `claude -p "/context" --no-session-persistence` in the
dotfiles main checkout: a session starts at 106.1k tokens, and `CLAUDE.md` is 61.7k of that.
It is the largest single launch load in the fleet. ai-config#307/#308 already cut the shared
`core.md` to 14.5k.

This is the second time. dotfiles#294 (ADR-0036, 2026-09-25) moved narrative out and took
`CLAUDE.md` from 179,422 to 122,627 bytes. On master at `1a21427b` it is 154,265 bytes: 31.6k
regrown in three weeks. 43 of the 48 `CLAUDE.md` commits since 2026-09-25 grew it, mostly by
1–2.6k each and mostly as new `### Test Seams` entries; 34 of the 67 PRs in that window touched
it. Nothing measures the file, so nothing stopped it.

Population of the block counts below: `CLAUDE.md` at `1a21427b`, split on blank lines,
headings excluded. 198 blocks; 113 are over 400 characters and hold 137,423 of the 154,265
bytes. `### Test Seams` alone is 55,332 bytes in 64 blocks, including a 10,043-byte table.

ADR-0036 decision 4 kept test seams whose failing path touches live state whole in
`CLAUDE.md`. A keyword pass (E2, live state, real path, sudo, network) matches 18 Test Seams
blocks, 26,596 bytes; it is a heuristic, not a classification.

**Why not ai-config's ADR-0079 gate.** Round 1 of review (below) found it the wrong
mechanism here: any one-line `Context-Budget-Growth:` reason clears it, so it records growth
rather than stopping it (ai-config: 7 of 7 growing commits since it landed carried a
trailer); it enforces neither a block cap nor a size; it would break `tests/scripts/pre_push.bats`
(fixtures have no `CLAUDE.md`, CI has no `~/.claude`); and it would put ai-config's
main-checkout code on dotfiles' push path. Measured: run in dotfiles it exits 2 on
`CLAUDE.md:253 @~/.claude/standards/powershell.md`.

## Design

1. **One line per block.** Every `CLAUDE.md` block over 300 characters is replaced by
   exactly one line of at most 300 characters stating the rule. A block for a seam or
   command whose failing path touches live state instead becomes one line that starts with
   `LIVE: `, is at most 520 characters, and keeps the seam variable name and the exact safe
   override or command, as ai-config's `core.md` destructive rows keep theirs (operator
   decisions 2026-10-17, superseding ADR-0036 decision 4). The marker is what tells the
   checker which cap applies. A block at or under 300 characters is left byte-identical.
   Feasibility, measured on `1a21427b` with every compressed line at its full cap: 128
   blocks compress, the rest hold 11,184 bytes, and with 18 `LIVE:` lines the file is about
   47.2k bytes.
2. **Detail moves verbatim.** Each compressed block's full text moves byte-for-byte into an
   existing or new `ai-config/docs/knowledge/dotfiles-<topic>.md` under a `###` heading
   unique to that block, as ADR-0036 decision 1 already does. The 10,043-byte seam table
   moves whole and is replaced by one pointer line.
3. **Existing pointer grammar.** Each compressed line ends in ADR-0036's pointer,
   `` → `<file>` § `<heading>` ``, and `scripts/relocation_check.py` verifies it.
4. **Drop the powershell.md import.** `@~/.claude/standards/powershell.md` is replaced with
   one line naming `powershell.md` as required reading before writing or changing PowerShell
   code or its lint and test configuration, and `make sync-agent-guidance` regenerates the
   Cursor mirror.
5. **A local hard cap.** A new `scripts/claude_md_budget.py` reads `CLAUDE.md` at a given
   git revision and exits 1 naming each violation when any non-heading block exceeds 300
   characters (520 when it starts with `LIVE: `) or the file exceeds 50,000 bytes (about 20k tokens at the measured 2.5 bytes
   per token). It exits 0 when the revision has no `CLAUDE.md`, so fixture repos are
   unaffected. There is no trailer or override: the way to grow is to relocate detail.
   - `scripts/pre-push` runs it on each pushed ref's local SHA **before** the inert-file
     early exit, so a `CLAUDE.md`-only push is checked, and accumulates the result to act
     on after draining stdin.
   - `make test` runs it on `HEAD`, so CI enforces it on every PR.
6. **Seam routing.** `CLAUDE.md` states that a new test seam's description goes to
   `ai-config/docs/knowledge/dotfiles-test-seams.md`, with only a one-line entry and pointer
   in `CLAUDE.md`.
7. **A new ADR** records the supersession of ADR-0036 decision 4 and the hard cap.
8. **Delivery.** The knowledge-file additions land first, as a docs commit direct to
   ai-config master, so every pointer resolves when the dotfiles PR merges. The dotfiles PR
   starts only after dotfiles#346 merges, because #346 edits three spots in `CLAUDE.md`.
9. **Operator read before merge.** The operator reads the compressed `CLAUDE.md`, as for
   ai-config#307.

## Out of scope

- `README.md`, other docs, and any `ai-config` file except the knowledge files.
- Any change to ai-config's `context_budget.py`.

## Requirements

- **R1.** `[PR1]` Every non-heading block of dotfiles `CLAUDE.md` is at most 300 characters, or at most 520 when it starts with `LIVE: `.
- **R2.** `[PR1]` Every block that was over 300 characters at the PR's base (the dotfiles master commit it branches from, after dotfiles#346) has its full text, byte-identical, under a unique `###` heading in an `ai-config/docs/knowledge/dotfiles-*.md` file, and its replacement line ends in an ADR-0036 pointer to that heading.
- **R3.** `[PR1]` A block that was at most 300 characters at the base is byte-identical and carries no new pointer.
- **R4.** `[PR1]` A compressed line for a seam or command whose failing path touches live state starts with `LIVE: ` and contains the seam variable name and its safe override or command from the original block.
- **R5.** `[PR1]` dotfiles `CLAUDE.md` no longer contains `@~/.claude/standards/powershell.md`, names `powershell.md` as required reading before writing or changing PowerShell code or its lint and test configuration, and the Cursor mirror is regenerated.
- **R6.** `[PR1]` `scripts/claude_md_budget.py <rev>` exits 1 and names each violating block or the size when any non-heading block of `CLAUDE.md` at `<rev>` exceeds 300 characters (520 when it starts with `LIVE: `) or the file exceeds 50,000 bytes, exits 0 when within both, and exits 0 when `<rev>` has no `CLAUDE.md`.
- **R7.** `[PR1]` `scripts/pre-push` runs `claude_md_budget.py` on each pushed ref with a non-zero local SHA before its inert-file early exit, and refuses the push after draining stdin when any run exits non-zero.
- **R8.** `[PR1]` `make test` runs `claude_md_budget.py HEAD`.
- **R9.** `[PR1]` Tests cover: a block of 301 characters refused, a block of 300 allowed, a `LIVE: ` block of 521 refused, a `LIVE: ` block of 520 allowed, a 301-character block without the marker refused, a file of 50,001 bytes refused, a file of 50,000 allowed, a revision with no `CLAUDE.md` allowed, the violating block named in the output, a `CLAUDE.md`-only push refused by `scripts/pre-push`, and a compliant push allowed.
- **R10.** `[PR1]` `CLAUDE.md` states that a new test seam's description goes to `ai-config/docs/knowledge/dotfiles-test-seams.md` with a one-line entry and pointer in `CLAUDE.md`.
- **R11.** `[PR1]` A new dotfiles ADR records the supersession of ADR-0036 decision 4 and the hard cap, and `docs/adr/README.md` lists it.
- **V1.** `scripts/relocation_check.py check` passes for every relocated block, with arguments sized for this relocation.
- **V2.** An independent reviewer records covered, weakened, missing or wrong for every compressed block against its original; no block is missing or wrong at merge.
- **V3.** `claude -p "/context"` in the dotfiles main checkout after merge shows `CLAUDE.md` at 20k tokens or less, recorded in the PR body with the before figure.
- **V4.** `claude_md_budget.py HEAD` exits 0 at the merge commit.
- **V5.** The operator reads the compressed `CLAUDE.md` and approves it before the PR merges.
- **N1.** No edit to dotfiles `CLAUDE.md` before dotfiles#346 merges.
- **N2.** No change to `context_budget.py` or any other ai-config script.
- **N3.** No rule removed: every compressed block's decision survives in its one line.
- **N4.** `claude_md_budget.py` has no trailer, environment variable or flag that skips or raises its limits.
- **N5.** No edit to `README.md` or to any dotfiles file other than `CLAUDE.md`, `scripts/pre-push`, `scripts/claude_md_budget.py`, their tests, `Makefile`, `.cursor/rules/global-claude-standards.mdc`, the new ADR, `docs/adr/README.md` and `docs/superpowers/**`.

## Multi-Lens Review

Reviewed at commit: `bbb3a96c` (Step 7 self-review commit, before Step 8 dispatch)

### Goal-Fit

Finding: the gate does not guard the invariant the design creates. `context_budget.py` checks only undeclared net growth; any non-empty `Context-Budget-Growth:` reason clears it and it has no per-block cap. 43 of 48 `CLAUDE.md` commits since 2026-09-25 grew the file, each with a true reason, so the gate turns undeclared growth into declared growth. Simpler path: a per-block length check with no trailer escape, plus routing new seam entries to `dotfiles-test-seams.md`. Also R9 (55,000 bytes, about 22k tokens at the measured 2.5 bytes/token) and V3 (20k tokens) disagree, and the 10,043-byte seam table cannot become one line without risking N3.
Assumption: that a trailer-clearable refusal makes feature-PR authors relocate detail rather than add a trailer; settled by asking whether a trailer is an acceptable outcome for a legitimately new seam.
Disposition: Addressed — operator chose "local hard cap" on 2026-10-17: per-block cap and 50,000-byte ceiling with no escape (Design 5, R6–R9, N4), seam routing (Design 6, R10), ceiling aligned to V3, table moves whole.

### Ergonomics

Finding: same core finding (growth check taxes relocation, waves through regrowth for one line; 34 of 67 PRs since 2026-09-25 touched `CLAUDE.md`). New: `scripts/pre-push` exits early for `.md`-only pushes (`needs_test=0`), so a gate placed near `make test` never sees a `CLAUDE.md`-only push; it must run before that exit, with tests for a `CLAUDE.md`-only push and a direct-to-master push. Dropping the powershell.md import makes `check-agent-guidance` drift on `.cursor/rules/global-claude-standards.mdc`, which N5 does not allow editing.
Assumption: that a one-line trailer is enough friction; refuted if the first month of dotfiles PRs after merge are mostly trailered.
Disposition: Addressed — operator chose "local hard cap" on 2026-10-17: the check runs before the inert exit (R7) with a `CLAUDE.md`-only push test (R9); the mirror is regenerated and allowed by N5 (R5).

### Risk

Finding: the hook arm as specified breaks the existing suite. `tests/scripts/pre_push.bats` (100 tests, 63 expecting exit 0) and five other bats files run `scripts/pre-push` against fixtures with no `CLAUDE.md`; the real script exits 2 on an empty set (reproduced), and CI has no `~/.claude`, so the absent-script refusal fires. The hook needs an override seam and every existing test a stub. R7's cases are mostly vacuous (4 of 5 pass if the gate does nothing). The gate enforces neither R1 nor R9 after PR1 (ai-config: 7 of 7 growing commits trailered, 3,291 units, compliance not deterrence). dotfiles' push path would run ai-config main-checkout code live, so a `context_budget.py` change alters dotfiles' gate with no dotfiles diff, and PyYAML is untested on the Macs.
Assumption: same trailer-deterrence assumption; settled now by classifying #306–#344's additions as live-state seams that must stay in `CLAUDE.md`.
Disposition: Addressed — operator chose "local hard cap" on 2026-10-17: a dotfiles-local script with no ai-config dependency, exit 0 when `CLAUDE.md` is absent so fixtures pass, CI runs it via `make test` (R8), and boundary cases at 520/521 characters and 50,000/50,001 bytes (R9).

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.
