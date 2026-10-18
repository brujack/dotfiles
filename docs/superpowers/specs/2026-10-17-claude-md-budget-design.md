# CLAUDE.md budget: one line per rule, and a hard ceiling that stops regrowth

- **Approved:** 2026-10-18
- **Status:** Approved
- **Revision:** 4 (one line per rule, a single 105,000-byte ceiling set from two dry runs; revisions 2 and 3 had per-block caps)
- **Follows:** ADR-0036 (CLAUDE.md relocation), ai-config ADR-0077 (CLAUDE.md content homes).

## Problem

Measured 2026-10-17 on `claude` with `claude -p "/context" --no-session-persistence` in the
dotfiles main checkout: a session starts at 106.1k tokens, and `CLAUDE.md` is 61.7k of that,
the largest single launch load in the fleet.

This is the second time. dotfiles#294 (ADR-0036, 2026-09-25) took `CLAUDE.md` from 179,422
to 122,627 bytes. On master after dotfiles#346 (`727e9cb2`) it is 155,308 bytes. 43 of the 48
`CLAUDE.md` commits between 2026-09-25 and `1a21427b` grew it, mostly by 1–2.6k each and
mostly as new `### Test Seams` entries; 34 of the 67 PRs in that window touched it. Nothing
measures the file, so nothing stopped it.

**Why not ai-config's ADR-0079 gate.** Review round 1 found it the wrong mechanism here: any
one-line `Context-Budget-Growth:` reason clears it (ai-config: 7 of 7 growing commits since
it landed carried one), it enforces no size, it would break `tests/scripts/pre_push.bats`
(fixtures have no `CLAUDE.md`, CI has no `~/.claude`), and it puts ai-config's main-checkout
code on dotfiles' push path.

**Why not a per-block cap.** Review round 2 found revision 3's unit wrong. Split on blank
lines, the 129 blocks over 300 characters on master hold 349 list items and 31 table rows,
up to 37 items in one block, so one line per block cannot keep every rule; and blank lines
between list items defeat a per-block check. The binding constraint is the file size.

**Dry run (2026-10-17).** The 15 largest blocks on master (64,430 bytes, 173 rules) were
compressed by hand to one line per rule, with pure detail moved pointer-only: 96 kept lines,
67 pointer-only, 10 merged into a sibling, 22,643 bytes (ratio 0.351). Projecting the other
114 over-300 blocks (79,691 bytes) at that ratio, plus the 10,721 bytes of short blocks kept
as-is and 466 bytes of separators, gives 61,836 bytes; excluding the two outliers (the seam
table at 0.144 and the directory tree at 0.039) the ratio is about 0.41 and the projection
about 66.7 KB. Population: dotfiles `CLAUDE.md` on master; the 15 blocks are measured, the
rest is a projection. Pointers average 84 characters, about a third of a kept line. Working
files: `ai-config` session scratchpad `dryrun/` (not committed).

**Dry run 2 (2026-10-18).** That projection carried the large blocks' ratio onto smaller
ones. A stratified sample of 12 of the other 114 blocks (three per size quartile, 8,396
bytes) compressed to 0.747: each kept line still carries a 90–130 byte pointer, so blocks
under about 500 bytes barely shrink and two grew. 37 of the 114 (27,428 bytes) are live-state
seams that must keep their variable names and overrides; the three sampled compressed to
0.936. Projected file: 93,342 bytes at one ratio, 98,543 bytes with live-state blocks at
0.936 and the rest at 0.747, so about 37–39k tokens. Working files: scratchpad `dryrun2/`.

## Design

1. **One line per rule.** A rule is a list item, a table row, or a paragraph stating one
   instruction. Each rule a session must hold before reading any file becomes one line
   stating what to do or never do and when. Two items stating one instruction may merge.
   Pure detail (incident history, measurements, reference listings such as the directory
   tree or the task catalog) becomes pointer-only, covered by one shared pointer line for
   its group. A rule for a seam or command whose failing path touches live state keeps the
   seam variable name and the exact safe override or command (operator decision 2026-10-17,
   superseding ADR-0036 decision 4). Adjacent lines whose detail sits under one heading may
   share a single pointer at the end of the group.
2. **Detail moves verbatim.** Every original block that changed moves byte-for-byte into an
   existing or new `ai-config/docs/knowledge/dotfiles-<topic>.md` under a `###` heading
   unique to it, as ADR-0036 decision 1 already does.
3. **Existing pointer grammar.** ADR-0036's `` → `<file>` § `<heading>` ``, verified by
   `scripts/relocation_check.py`.
4. **Drop the powershell.md import.** `@~/.claude/standards/powershell.md` becomes one line
   naming `powershell.md` as required reading before writing or changing PowerShell code or
   its lint and test configuration; `make sync-agent-guidance` regenerates the Cursor mirror.
5. **One hard ceiling.** A new `scripts/claude_md_budget.py <rev>` reads `CLAUDE.md` at
   `<rev>`. It exits 1 naming the size and the ceiling when the file exceeds 105,000 bytes
   (about 42k tokens at the measured 2.5 bytes per token, with 6–12 KB of headroom over the
   93–99 KB dry-run projection; new seams arrive as one line of about 250 bytes, not a
   1–2.6 KB block); exits 0 when within; exits 0 when `git ls-tree` shows `<rev>` has no
   `CLAUDE.md`; and exits 2 when git fails to resolve `<rev>` or read the tree, so a git
   failure never reads as a pass. There is no trailer, flag or environment override.
   - `scripts/pre-push` runs it for each pushed ref with a non-zero local SHA, **before** the
     inert-file early exit, taking the script from the pushed commit itself
     (`git show <sha>:scripts/claude_md_budget.py` piped to `python3 -I -`) so a worktree push
     runs its own branch's checker. It first runs `git ls-tree <sha> --
     scripts/claude_md_budget.py`: a non-zero exit, or a `git show` that fails after the
     path was listed, refuses the push; only an empty listing (the commit has no such
     script) skips the check. It checks every pushed ref, accumulates the results and
     refuses after draining stdin.
   - `make test` runs it on `HEAD` through a new prerequisite target
     `check-claude-md-budget`, so CI enforces the ceiling on every PR. The checker reads
     `CLAUDE.md` only through `git show <rev>:CLAUDE.md`, never the working tree, which is the
     precedent `docs_inert_premise.bats` already records for `tests/test_relocation_check.py`.
     The target is added to `ALLOWED_TEST_PREREQS` with a comment stating that, and that the
     docs-only push path still runs the check because the hook runs it before the inert
     exit.
   - Raising the ceiling is a change to one constant and needs an ADR amendment stating why;
     review, not the tool, enforces that.
   - If master ever exceeds the ceiling (a direct push that skipped the hook, or two PRs that
     each passed), every later PR fails `make test` until a relocation lands. That is the
     intended, loud failure.
6. **Seam routing.** `CLAUDE.md` states that a new test seam's description goes to
   `ai-config/docs/knowledge/dotfiles-test-seams.md`, with a one-line rule and pointer in
   `CLAUDE.md`.
7. **A new ADR** records the supersession of ADR-0036 decision 4, the ceiling, and how the
   ceiling may change.
8. **Delivery.** The knowledge-file additions land first, as a docs commit direct to
   ai-config master, so every pointer resolves when the dotfiles PR merges.
9. **Review before merge.** An independent reviewer gives every original rule a verdict
   against the compressed file (kept, pointer-only, weakened, missing, wrong); the operator
   reads the compressed `CLAUDE.md` and the pointer-only list.

## Out of scope

- `README.md`, other docs, and any `ai-config` file except the knowledge files.
- Any change to ai-config's `context_budget.py`.

## Requirements

- **R1.** `[PR1]` dotfiles `CLAUDE.md` is at most 105,000 bytes.
- **R2.** `[PR1]` Every block of `CLAUDE.md` at the PR's base (the dotfiles master commit it branches from) that the PR changes has its full text, byte-identical, under a unique `###` heading in an `ai-config/docs/knowledge/dotfiles-*.md` file, and the lines that replace it end in, or are grouped under, an ADR-0036 pointer to that heading.
- **R3.** `[PR1]` A block the PR does not change is byte-identical to the base.
- **R4.** `[PR1]` Every kept line for a seam or command whose failing path touches live state contains that seam's variable name and its safe override or command from the original text.
- **R5.** `[PR1]` dotfiles `CLAUDE.md` no longer contains `@~/.claude/standards/powershell.md`, names `powershell.md` as required reading before writing or changing PowerShell code or its lint and test configuration, and the Cursor mirror is regenerated.
- **R6.** `[PR1]` `scripts/claude_md_budget.py <rev>` exits 1 and prints the size and the ceiling when `CLAUDE.md` at `<rev>` exceeds 105,000 bytes, exits 0 when within, exits 0 when `<rev>`'s tree has no `CLAUDE.md`, and exits 2 when git cannot resolve `<rev>` or read its tree.
- **R7.** `[PR1]` `scripts/pre-push` runs the budget check taken from each pushed commit with a non-zero local SHA (via `git show <sha>:scripts/claude_md_budget.py`), before its inert-file early exit; skips only a commit whose `git ls-tree` listing of that path is empty; refuses when `git ls-tree` or `git show` fails; and refuses the push after draining stdin when any check exits non-zero.
- **R8.** `[PR1]` `make test` runs `claude_md_budget.py HEAD` through a `check-claude-md-budget` prerequisite, the checker reads `CLAUDE.md` only via `git show`, and `tests/scripts/docs_inert_premise.bats` lists the target in `ALLOWED_TEST_PREREQS` with a comment giving that reason.
- **R9.** `[PR1]` Tests cover: 105,001 bytes refused, 105,000 allowed, no `CLAUDE.md` allowed, an unresolvable revision exiting 2, the size and ceiling named in the output, a `CLAUDE.md`-only push over the ceiling refused by `scripts/pre-push`, a compliant push allowed, a pushed commit without the script skipped, a `git show` failure on a listed path refused, a fixture whose working-tree checker differs from the pushed commit's (the pushed one decides), a two-ref push whose first ref is over the ceiling refused, and the existing `tests/scripts/pre_push.bats` suite passing unchanged.
- **R10.** `[PR1]` `CLAUDE.md` states that a new test seam's description goes to `ai-config/docs/knowledge/dotfiles-test-seams.md` with a one-line rule and pointer in `CLAUDE.md`.
- **R11.** `[PR1]` A new dotfiles ADR records the supersession of ADR-0036 decision 4, the 105,000-byte ceiling and that raising it needs an ADR amendment, and `docs/adr/README.md` lists it.
- **V1.** `scripts/relocation_check.py check` passes for every relocated block, with arguments sized for this relocation.
- **V2.** An independent reviewer records kept, pointer-only, weakened, missing or wrong for every rule of every changed block; none is missing or wrong at merge, and the pointer-only list goes in the PR body.
- **V3.** `claude -p "/context"` in the dotfiles main checkout after merge shows `CLAUDE.md` at 42k tokens or less, recorded in the PR body with the before figure.
- **V4.** `claude_md_budget.py HEAD` exits 0 at the merge commit.
- **V5.** The operator reads the compressed `CLAUDE.md` and the pointer-only list and approves before the PR merges.
- **N1.** No edit to dotfiles `CLAUDE.md` before dotfiles#346 merges.
- **N2.** No change to `context_budget.py` or any other ai-config script.
- **N3.** No rule removed: every rule of every changed block is either a kept line or pointer-only with its text in the knowledge file.
- **N4.** `claude_md_budget.py` has no trailer, environment variable or flag that skips or raises its ceiling.
- **N5.** No edit to `README.md` or to any dotfiles file other than `CLAUDE.md`, `scripts/pre-push`, `scripts/claude_md_budget.py`, their tests, `tests/scripts/docs_inert_premise.bats`, `Makefile`, `.cursor/rules/global-claude-standards.mdc`, the new ADR, `docs/adr/README.md` and `docs/superpowers/**`.

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

### Round 2 (revision 3, reviewed at commit `2032fae8`)

All three lenses re-ran (design substance changed).

- Goal-fit: worth building, but only the ceiling is; the feasibility figure was wrong (53,798 bytes at full cap with 18 `LIVE:` lines, not 47.2k); one line per block cannot keep about 380 rules (349 list items, 31 table rows) under N3; R8 collides with `docs_inert_premise.bats`; the `LIVE:` marker is self-asserted; "no CLAUDE.md" must not absorb a git failure.
- Ergonomics: the same feasibility error; blank lines between list items defeat a per-block check; `- LIVE:` placement undefined; adding a seam costs a second repo while the lossy short line passes.
- Risk: block unit mismatched (87 of 129 over-300 blocks are lists); master can go over the ceiling (`strict:false`, direct pushes), blocking every later PR; the hook must run the checker from the pushed commit, and the existing pre-push suite must keep passing.

Disposition: Addressed — operator chose "ceiling only plus dry run" and then a 70,000-byte ceiling on 2026-10-17: per-block caps and `LIVE:` removed, one line per rule, ceiling set from the dry-run projection (Problem, Design 1 and 5, R1, R6–R9), git failure exits 2, checker taken from the pushed commit, docs-inert premise recorded, over-ceiling consequence stated.

### Round 3 (revision 4, scoped Risk lens, reviewed at commit `3dd008db`)

Finding: the 70,000-byte projection carries the large blocks' ratio onto the 114 smaller unsampled blocks, all under 1,657 bytes, while sampled blocks under 2.5 KB compress to 0.471 against the 0.454 needed, so the file may land at 70–72 KB and the only remaining lever is demoting rules to pointer-only; the inert-premise edit named the wrong list; "skip when the script is absent" could swallow git failures; R9 could not tell the pushed-commit checker from the working-tree one, nor catch a last-ref-only loop.
Disposition: Addressed (wording, 2026-10-18) — `ALLOWED_TEST_PREREQS` with the `git show` precedent (Design 5, R8); absent versus git failure separated by `git ls-tree` (Design 5, R7); three R9 cases added. Dry run 2 then measured the smaller blocks at 0.747 and the operator chose a 105,000-byte ceiling on 2026-10-18 (Problem, Design 5, R1, R6, R9, R11, V3).

