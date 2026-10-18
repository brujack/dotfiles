# CLAUDE.md budget: one line per block, and a gate that stops regrowth

- **Status:** Draft
- **Follows:** ADR-0036 (CLAUDE.md relocation), ai-config ADR-0079 (context-budget gate),
  ai-config ADR-0077 (CLAUDE.md content homes).

## Problem

Measured 2026-10-17 on `claude` with `claude -p "/context" --no-session-persistence` in the
dotfiles main checkout: a session starts at 106.1k tokens, and `CLAUDE.md` is 61.7k of that.
It is the largest single launch load in the fleet. ai-config#307/#308 already cut the shared
`core.md` to 14.5k.

This is the second time. dotfiles#294 (ADR-0036, 2026-09-25) moved narrative out and took
`CLAUDE.md` from 179,422 to 122,627 bytes. On master at `1a21427b` it is 154,265 bytes: 31.6k
regrown in three weeks. `git log -- CLAUDE.md` shows almost every feature PR since (#306
through #344) adding to it, mostly new `### Test Seams` entries. No commit carried a growth
declaration, because dotfiles has no budget gate: ADR-0079's gate runs only in ai-config.

Population of the block counts below: `CLAUDE.md` at `1a21427b`, split on blank lines,
headings excluded. 198 blocks; 113 are over 400 characters and hold 137,423 of the 154,265
bytes. `### Test Seams` alone is 55,332 bytes in 64 blocks, including a 10,043-byte table.

ADR-0036 decision 4 kept test seams whose failing path touches live state whole in
`CLAUDE.md`. A keyword pass (E2, live state, real path, sudo, network) matches 18 Test Seams
blocks, 26,596 bytes; it is a heuristic, not a classification.

ai-config's gate does not run unchanged here. `python3 ~/.claude/scripts/context_budget.py
--range 1a21427b~5..1a21427b` in dotfiles exits 2 with `CLAUDE.md:253
@~/.claude/standards/powershell.md` listed as an import outside the launch-loadable set.

## Design

1. **One line per block.** Every `CLAUDE.md` block over its cap is replaced by exactly one
   line stating the rule: at most 400 characters, or 520 for a block that documents a seam
   or command whose failing path touches live state (the operator decision of 2026-10-17
   supersedes ADR-0036 decision 4). That line keeps the seam variable name and the exact
   safe override or command, as ai-config's `core.md` destructive rows keep theirs. A block
   at or under its cap is left byte-identical.
2. **Detail moves verbatim.** Each compressed block's full text moves byte-for-byte into an
   existing or new `ai-config/docs/knowledge/dotfiles-<topic>.md` under a `###` heading
   unique to that block, as ADR-0036 decision 1 already does.
3. **Existing pointer grammar.** Each compressed line ends in ADR-0036's pointer,
   `` → `<file>` § `<heading>` ``, and `scripts/relocation_check.py` verifies it. No new
   pointer format.
4. **Drop the powershell.md import.** `@~/.claude/standards/powershell.md` is replaced with
   one line naming `powershell.md` as required reading before writing or changing PowerShell
   code or its lint and test configuration. That removes about 1.1k tokens and the gate's
   exit 2.
5. **Gate in pre-push.** `scripts/pre-push` runs
   `python3 ~/.claude/scripts/context_budget.py --push <local_sha>` for each pushed ref with
   a non-zero local SHA, and refuses the push on a non-zero exit. When
   `~/.claude/scripts/context_budget.py` is absent it refuses with a message naming the
   missing path and the remedy (`setup_env.sh -t setup_user`). A commit that grows
   `CLAUDE.md` then needs a `Context-Budget-Growth: <reason>` trailer, exactly as in
   ai-config. There is no CI arm: ai-config is private and dotfiles CI cannot read the
   script (operator decision 2026-10-17).
6. **A new ADR** records the supersession of ADR-0036 decision 4 and the gate.
7. **Delivery.** The knowledge-file additions land first, as a docs commit direct to
   ai-config master, so every pointer resolves when the dotfiles PR merges. The dotfiles PR
   (`CLAUDE.md`, ADR, hook, tests) starts only after dotfiles#346 merges, because #346 edits
   three spots in `CLAUDE.md`.
8. **Operator read before merge.** The operator reads the compressed `CLAUDE.md`, as for
   ai-config#307.

## Out of scope

- `README.md`, other docs, and any `ai-config` file except the knowledge files.
- Changing `context_budget.py`.
- A CI arm for the gate.

## Requirements

- **R1.** `[PR1]` Every non-heading block of dotfiles `CLAUDE.md` is at most 400 characters, or 520 for a block documenting a seam or command whose failing path touches live state.
- **R2.** `[PR1]` Every block that was over its cap at the PR's base (the dotfiles master commit it branches from, after dotfiles#346) has its full text, byte-identical, under a unique `###` heading in an `ai-config/docs/knowledge/dotfiles-*.md` file, and its replacement line ends in an ADR-0036 pointer to that heading.
- **R3.** `[PR1]` A block that was at or under its cap is byte-identical to the base and carries no new pointer.
- **R4.** `[PR1]` A compressed live-state line contains the seam variable name and its safe override or command from the original block.
- **R5.** `[PR1]` dotfiles `CLAUDE.md` no longer contains `@~/.claude/standards/powershell.md` and names `powershell.md` as required reading before writing or changing PowerShell code or its lint and test configuration.
- **R6.** `[PR1]` `scripts/pre-push` runs `~/.claude/scripts/context_budget.py --push` for each pushed ref with a non-zero local SHA and refuses the push on its non-zero exit, and refuses with the missing path named when the script is absent.
- **R7.** `[PR1]` Bats tests cover the hook arm: undeclared growth refused, growth with a `Context-Budget-Growth:` trailer allowed, script absent refused, a shrinking commit allowed, a ref deletion skipped.
- **R8.** `[PR1]` A new dotfiles ADR records the supersession of ADR-0036 decision 4 and the pre-push gate, and `docs/adr/README.md` lists it.
- **R9.** `[PR1]` dotfiles `CLAUDE.md` is at most 55,000 bytes.
- **V1.** `scripts/relocation_check.py check` passes for every relocated block.
- **V2.** An independent reviewer records covered, weakened, missing or wrong for every compressed block against its original; no block is missing or wrong at merge.
- **V3.** `claude -p "/context"` in the dotfiles main checkout after merge shows `CLAUDE.md` at 20k tokens or less, recorded in the PR body with the before figure.
- **V4.** `python3 ~/.claude/scripts/context_budget.py --range` over the PR's commits exits 0.
- **V5.** The operator reads the compressed `CLAUDE.md` and approves it before the PR merges.
- **N1.** No edit to dotfiles `CLAUDE.md` before dotfiles#346 merges.
- **N2.** No change to `context_budget.py` or any other ai-config script.
- **N3.** No rule removed: every compressed block's decision survives in its one line.
- **N4.** No CI job runs the budget gate.
- **N5.** No edit to `README.md` or to any dotfiles file other than `CLAUDE.md`, `scripts/pre-push`, its bats tests, the new ADR, `docs/adr/README.md` and `docs/superpowers/**`.

## Multi-Lens Review

Reviewed at commit: `bbb3a96c` (Step 7 self-review commit, before Step 8 dispatch)

### Goal-Fit

Finding: the gate does not guard the invariant the design creates. `context_budget.py` checks only undeclared net growth; any non-empty `Context-Budget-Growth:` reason clears it and it has no per-block cap. 43 of 48 `CLAUDE.md` commits since 2026-09-25 grew the file, each with a true reason, so the gate turns undeclared growth into declared growth. Simpler path: a per-block length check with no trailer escape, plus routing new seam entries to `dotfiles-test-seams.md`. Also R9 (55,000 bytes, about 22k tokens at the measured 2.5 bytes/token) and V3 (20k tokens) disagree, and the 10,043-byte seam table cannot become one line without risking N3.
Assumption: that a trailer-clearable refusal makes feature-PR authors relocate detail rather than add a trailer; settled by asking whether a trailer is an acceptable outcome for a legitimately new seam.
Disposition:

### Ergonomics

Finding: same core finding (growth check taxes relocation, waves through regrowth for one line; 34 of 67 PRs since 2026-09-25 touched `CLAUDE.md`). New: `scripts/pre-push` exits early for `.md`-only pushes (`needs_test=0`), so a gate placed near `make test` never sees a `CLAUDE.md`-only push; it must run before that exit, with tests for a `CLAUDE.md`-only push and a direct-to-master push. Dropping the powershell.md import makes `check-agent-guidance` drift on `.cursor/rules/global-claude-standards.mdc`, which N5 does not allow editing.
Assumption: that a one-line trailer is enough friction; refuted if the first month of dotfiles PRs after merge are mostly trailered.
Disposition:

### Risk

Finding: the hook arm as specified breaks the existing suite. `tests/scripts/pre_push.bats` (100 tests, 63 expecting exit 0) and five other bats files run `scripts/pre-push` against fixtures with no `CLAUDE.md`; the real script exits 2 on an empty set (reproduced), and CI has no `~/.claude`, so the absent-script refusal fires. The hook needs an override seam and every existing test a stub. R7's cases are mostly vacuous (4 of 5 pass if the gate does nothing). The gate enforces neither R1 nor R9 after PR1 (ai-config: 7 of 7 growing commits trailered, 3,291 units, compliance not deterrence). dotfiles' push path would run ai-config main-checkout code live, so a `context_budget.py` change alters dotfiles' gate with no dotfiles diff, and PyYAML is untested on the Macs.
Assumption: same trailer-deterrence assumption; settled now by classifying #306–#344's additions as live-state seams that must stay in `CLAUDE.md`.
Disposition:

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.
