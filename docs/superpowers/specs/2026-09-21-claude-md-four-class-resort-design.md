# dotfiles CLAUDE.md four-class re-sort — design

**Date:** 2026-09-21
**Parent convention:** ai-config, ADR-0077 (five content homes, routing sentence) plus the
four-class decision procedure amendment that session is writing. This spec is the dotfiles
sub-project; it does not define the convention, it applies it.
**Backlog rows closed:** `Move CLAUDE.md reference text to knowledge files` (row 244, deferred
from the 2026-09-11 re-sort) and `CLAUDE.md Test Seams duplicates source comments near-verbatim`
(filed `ea32a18b`).
**Peer session:** ai-config owns `~/.claude/standards/*.md` and the ADR-0077 amendment. Nothing
in this spec edits anything under `ai-config/` except new `docs/knowledge/dotfiles-*.md` files,
which are this repo's content living in ai-config's knowledge directory per ADR-0020.

---

## Problem

A dotfiles session loads ~165,000 tokens of markdown before doing any work -- measured on this
session, on `claude`, by summing the launch-loaded files; every dotfiles session loads the same
set, so the figure is per-session rather than per-machine. `dotfiles/CLAUDE.md`
is ~44,700 tokens of it — the largest single file anyone in this fleet loads, larger than any
fleet-wide standard.

The binding constraint is not the 1M main-thread window. It is **haiku executor headroom**.
`roleModels.executor-mechanical` is Haiku 4.5 at 200k, so a dotfiles session leaves a dispatched
mechanical task roughly 35k for its prompt, tool schemas, file reads and output.
`.claude/scripts/validate-plan.py:105` `_haiku_scope_errors` checks `files_touched` length and
forbidden patterns and never checks context budget, so such a task is certified green and then
fails. Two dotfiles dispatches have already failed this way (ai-config backlog row, and
`docs/knowledge/ai-config-haiku-preamble-headroom.md`).

Stated as headroom, not overflow: both totals are under 200k. The claim is that ~35k is not
enough room, not that the window is exceeded. All token figures in this spec are bytes ÷ 4
estimates and are labelled where they matter.

## What was already established, and must not be re-derived

The 2026-09-11 re-sort shipped its clean subset — deleted dated measurement records, flattened
the Entry Points table, replaced unfetchable GitHub links with local paths — and deferred moving
reference text after three review rounds. Two probes from that work stand:

- **Pointers are followed.** 5 of 5 read-only, 4 of 5 with Edit/Write.
- **Moving or deleting source-derivable seam text changed effort, not outcome.**

That spec's own conclusion: _"The open work is the non-derivable hazard text, not the move
itself."_ Three rounds also established that the twelve-file pointer design does not converge —
pointers fire on a **file name**, and the seam groups span 12, 7 and 14 files against a six-file
cap, so a pointer on `lib/helpers.sh` would demand ~25,000 tokens of reading for any edit to it.
That design is not revived here.

## Measurement

Every paragraph of `### Test Seams` and `### MAKEFLAGS and Stdout Partition` (66,125 bytes at `20023924`,
~86 paragraphs; the classification ran against `c2990e5c`, before the parallel-bats PR added
2,513 bytes to this file, so a small number of new paragraphs are unclassified and the plan must
re-run the split rather than reuse the table) classified against real source, 10 spot-verified by grep:

| class     | bytes  | share |
| --------- | ------ | ----- |
| HAZARD    | 40,906 | 61.8% |
| DERIVABLE | 21,112 | 31.9% |
| AMBIGUOUS | 3,402  | 5.1%  |
| RECORD    | 780    | 1.2%  |

**The measurement table and the Design table use different class sets, deliberately, and this
is the reconciliation.** The classifier ran HAZARD / DERIVABLE / AMBIGUOUS / RECORD, where
DERIVABLE means *derivable from source*. The Design below runs HAZARD / DUPLICATE / RECORD /
REFERENCE, where DUPLICATE is the narrower same-argument test. DERIVABLE is therefore a
**superset of DUPLICATE**: every duplicate is derivable, not every derivable paragraph is a
duplicate. **REFERENCE has no row here because it has no instance in these two sections** -- it
is a class of the parent convention, carried so the four classes are stated once fleet-wide, and
in this repo its instances (`ci.md`'s hook bodies, `repo-structure.md`'s template) live in
ai-config's half. Nothing in this spec moves REFERENCE text, which is what the Non-goals forbid.

Instrument: one Sonnet pass, 10 of ~86 paragraphs verified against source, the HAZARD/DERIVABLE
boundary its judgement. The 62/32 split is lopsided enough to be directionally safe through any
reasonable boundary slop; the exact percentages are not quotable.

**RECORD is 1.2% because the 2026-09-11 re-sort already deleted the dated records.** That is the
shipped subset working as intended, and it is why the remedy here differs from the standards'.

**DERIVABLE does not mean inferable from code.** Of the spot-verified paragraphs, most were
derivable only because the source file carries a **near-verbatim duplicate comment**, dates
included:

Pairs are keyed by **symbol, not by line number**, deliberately: a line number drifts the moment
anything is inserted above it, and this repo has already recorded that happening to a comment
citing `workflows.sh:696`. Each row names the file and the symbol whose comment carries the
duplicate prose.

| CLAUDE.md topic | symbol | file | status |
| --- | --- | --- | --- |
| cask guard, incl. `Measured 2026-09-12` | `brew_cask_installed` | `lib/helpers.sh` | **fails** -- source argues why the code is shaped that way, CLAUDE.md argues how to test it |
| ggshield actor boundary | `GGSHIELD_FALLBACK_PATHS` | `scripts/pre-commit-hook.sh` | candidate |
| EXIT-trap ratchet scope | `_OVERRIDE_LIB_TRAP_SCOPE` | `scripts/check-lib-exit-traps.sh` | **fails** -- source argues allowlist-not-inference, CLAUDE.md argues which seam a test drives; also carries a zero-counterpart hazard paragraph |
| FIFO deadlock pre-flight | `_OVERRIDE_BATS_BIN` | `scripts/run-bash-coverage.sh` | candidate |
| rustup seams, why sha256sum is not mocked | `_RUSTUP_INIT_SHA256` | `lib/linux_ubuntu.sh` | candidate |
| login-shell seam, chsh PAM | `_OVERRIDE_CURRENT_LOGIN_SHELL` | `lib/helpers.sh` | **partial** -- one paragraph duplicates, one carries a zero-counterpart sentence |
| `export` vs `readonly` re-source scope | -- | `config/profiles.zsh` | candidate |

**Provenance of this table, stated because it is the kind of claim that gets relayed unchecked.**
Two rows I verified myself by reading the source this session (`brew_cask_installed`,
`_OVERRIDE_LIB_TRAP_SCOPE`). The rest come from a Sonnet classifier's spot-verification list; I
confirmed each symbol resolves to a definition carrying an adjacent explanatory comment, but not
that the prose is near-verbatim. The first draft of this table carried line numbers relayed from
that classifier and **three of seven were wrong** -- `lib/detect_env.sh:59-62` most clearly, where
the `readonly` assignments are at lines 6-11. That is why the table is keyed by symbol, and why
gate 3 below re-verifies every pair at implementation time rather than trusting this table.

So this is a **duplication** problem, not a routing problem. Nothing keeps the copies in sync,
they have no shared source of truth, and a reader cannot tell which is current.

## Design

**Four classes, applied per paragraph. The classification is the convention; the remedy follows
from the class.**

| class         | test                                                                               | remedy in `dotfiles/CLAUDE.md`                               |
| ------------- | ---------------------------------------------------------------------------------- | ------------------------------------------------------------ |
| **HAZARD**    | a consequence reading the source does not reveal, that changes what a session does | **stays**, compressed so the claim is the first sentence     |
| **DUPLICATE** | both copies serve the **same argument** -- not merely the same prose                                             | **delete the CLAUDE.md copy**, keep the one next to the code |
| **RECORD**    | dated provenance whose rule is stated adjacently                                   | move to `ai-config/docs/knowledge/dotfiles-*.md`             |
| **REFERENCE** | bibliography or bootstrapping scaffolding                                          | move to the skill or knowledge file that needs it            |

### 1. DUPLICATE -- delete the CLAUDE.md copy, keep the source comment

**The unit of classification is the sub-paragraph, never the symbol.** A symbol's `CLAUDE.md`
block routinely mixes classes: `_OVERRIDE_CURRENT_LOGIN_SHELL`'s block has one paragraph that is
near-verbatim in `lib/helpers.sh` and another ending *"Measured: the three end-to-end
`run_doctor` tests stub every sub-check by name, so `_doctor_check_login_shell` must be stubbed
there too or it reads the real account mid-suite"* -- which a tree-wide grep places nowhere else.
`_OVERRIDE_LIB_TRAP_SCOPE` is the same shape. Deleting "the pair" destroys the hazard with the
duplicate.

**The test is the same argument, not the same prose.** Where each copy is evidence for a
different claim it is shared evidence: keep both, cross-reference. A citation is not a duplicate
of the thing it cites. Only where one copy adds nothing its neighbour already says is a copy
deleted, and the surviving home is the file whose argument the evidence was gathered for.

Under that test the table above holds **candidates, not confirmed pairs**. Two already fail on
inspection and one is partial. The plan adjudicates each remaining candidate per sub-paragraph
and records the verdict with its reason; the expected surviving set is smaller than seven.

**Why the class is non-empty here and empty in the standards**, which is the best evidence the
classification is real rather than fitted to this file: the ai-config session applied the same
test to all 12 of its above-noise candidates and **0 survived**. Its three highest-ranked hits,
two at containment 1.00, were *citations of the paragraph they matched* -- a cross-reference
necessarily shares its target's words, so in citation-dense prose a lexical scan ranks references
above restatements. The rival copy in this repo is a **source comment**, which has no reason to
cite the standard, so prose matching works here and does not there.

**Cost of this definition, stated rather than discovered:** DUPLICATE was the one class with no
judgement in its remedy and it no longer is. Under "same prose" a script decides; under "same
argument" a reader does. The lexical scan is demoted from measurement to **candidate generator**
-- cheap, no judgement, proposes; the argument test disposes. Its output is a worklist, never a
figure.

Direction, where a pair does survive: delete the `CLAUDE.md` prose, leave the source comment. The
copy next to the code is the one a reader reaches while editing and cannot drift from the code it
annotates without someone seeing both in one diff.

Where deleting the `CLAUDE.md` copy would leave the seam unnamed, a one-line entry stays naming
the variable and the file that defines it, with no rationale.

**Every deletion requires that every sentence being removed has a counterpart**, verified in the
same change -- not one phrase-match authorising the removal of a whole block. A sentence with no
counterpart is not part of a duplicate; it is HAZARD that happens to sit next to one, and it
stays.

### 2. HAZARD — compress in place, claim first

HAZARD is 61.8% and none of it leaves the file. Compression means the non-obvious claim is the
first sentence of its paragraph and the narrative supporting it is cut to what a reader needs to
act. No hazard claim is deleted. No hazard claim moves behind a pointer.

This is the item with no mechanical check and the worst review-cost ratio in the spec. It is
included because it is the reason the work is worth more than the tokens: a preamble that is
two-thirds hazard narrative buries the prescriptive rule inside the incident report.

### 3. RECORD and AMBIGUOUS — 4,182 bytes, resolve individually

RECORD is 780 bytes and AMBIGUOUS is 3,402. Too small to design a process around. Each of the
six AMBIGUOUS paragraphs the classifier named gets a stated call in the implementation plan,
with the reason, rather than a rule applied blindly.

## Non-goals

- **No pointer scheme, and no knowledge-file split of the seam REFERENCE text.** The 780-byte
  RECORD remainder does move to a knowledge file, which is not a contradiction: it is provenance
  nobody needs inline and it needs no pointer, where the seam reference is text a session reads
  while editing and would need one.
- **No twelve-file pointer design.** Three rounds established that
  design does not converge and the probes established the moved text is not outcome-changing.
  What leaves this file is deleted (DUPLICATE) or is a small RECORD remainder.
- **No edits to `~/.claude/standards/*.md`.** ai-config's half.
- **No `.claude/rules/` destination.** `~/.claude/rules` is a dangling symlink (own backlog row),
  so that home does not exist today.
- **No launch-load ratchet.** Deferred in ai-config with three rounds of findings; this spec does
  not revive it.

## Verification

Run before implementation, not predicted:

1. **Baseline, recorded at the implementation commit's parent SHA:**
   `wc -c CLAUDE.md` and the per-section byte counts for `### Test Seams` and
   `### MAKEFLAGS and Stdout Partition`.
2. **Phrase manifest, written first and locked.** Before any edit, produce
   `docs/superpowers/plans/<plan>-phrases.md`: one row per sub-paragraph of both sections, its
   class, and a distinctive phrase **taken from the pre-change text at the parent SHA**. Commit
   it before the first edit. This is the artifact gates 3 and 4 check against, and it is the
   per-paragraph classification the ergonomics lens correctly noted does not otherwise exist --
   without it gate 3 has no ground truth for the ~79 paragraphs outside the candidate table and
   degrades to a spot-check.

   **The phrase is taken from the claim sentence of the sub-paragraph, never from its supporting
   narrative.** The constraint below obliges the compressor to keep the phrase verbatim, so a
   phrase drawn from the narrative would force them to keep prose the HAZARD remedy says to cut.
   Taking it from the claim also makes gate 4 check the same sentence gate 5 judges, rather than
   an arbitrary substring beside it.

   **The phrases are chosen by someone other than whoever performs the compression.** A phrase
   selected from surviving text proves only that the edit contains a substring of itself. The phrase check
   (gate 4) was the gate this spec first called falsifiable, and as first written it could not
   fail.

3. **Every DUPLICATE deletion: every sentence removed has a counterpart.** Per candidate, per
   sub-paragraph, `grep -n '<phrase>' <source file>` for **each sentence being deleted**, not one
   phrase authorising a block. A miss means that sentence is not part of a duplicate -- it stays,
   and the candidate is recorded as partial. Verdict plus reason recorded per candidate.

4. **No hazard claim lost.** Every phrase in the manifest whose row is classed HAZARD returns
   a hit in the post-change file. Not a byte count -- a byte count cannot distinguish compression
   from deletion. Run by a reviewer who did not perform the compression.

   **Compression must preserve the manifest phrase verbatim.** That is a constraint on the
   compressor, not a property the gate discovers. Without it the gate has a false-red mode: the
   HAZARD remedy asks for the claim to move to the first sentence, and a legitimate rewording
   drops the exact phrase chosen from the old narrative, failing the gate on correct work.

   **State plainly what this gate does not do.** The manifest is committed before editing, so the
   compressor works with the phrases in view. Gate 4 therefore detects **outright loss of a
   claim** and nothing else. It cannot detect a claim silently weakened -- a specific measured
   failure mode replaced by a vague summary that still contains the phrase -- and committing the
   manifest makes that easier to hit, not harder. Substance is carried by gate 5, not by gate 4,
   and the spec's falsifiability rests on the two of them together.

5. **Substance review by a non-implementer.** For every HAZARD paragraph the compression touched,
   a reviewer who did not write the compression reads the pre-change text at the parent SHA
   against the post-change text and judges whether the claim still says the same thing. This is
   the only check on weakening, it is judgement rather than mechanism, and it is named as such.
   A HAZARD paragraph that was not touched needs no review beyond gate 4.

6. **`make test` green** — `make lint` covers `CLAUDE.md` only via `check-agent-guidance`, so
   `make sync-agent-guidance` runs if `.cursor/rules/global-claude-standards.mdc` goes stale.
   Note that target is generated from the `@`-imports, not from body prose, so a body-only edit
   should leave it unchanged — if it does not, that is a finding.
7. **Post-change size reported with its denominator**, not as a bare figure: bytes before, bytes
   after, and the estimated token delta labelled as bytes ÷ 4.

**Falsifiability rests on gates 3, 4 and 5 together, and each covers a different failure.**
Gate 3 can refuse a planned deletion when a sentence has no counterpart. Gate 4 catches a hazard
claim disappearing outright; a change that hits its size target by deleting hazard text passes
1, 6 and 7 and fails 4. Gate 5 is the only check on a claim surviving as a string while being
weakened as a claim, and it is a human reading rather than a mechanism -- so the spec is
refutable on deletion mechanically and on weakening only by review. Saying that plainly is
better than an earlier draft's claim that gate 4 alone made the spec refutable, which was true
of string loss and false of the failure the HAZARD section itself calls the worst
review-cost ratio in the spec.

## Expected outcome

**Upper bound, not a count, and the distinction is load-bearing.** The classifier's DERIVABLE
21,112B + RECORD 780B + AMBIGUOUS 3,402B = 25,294B ~= **6,300 tokens** is the most that can
move. It is an upper bound because DERIVABLE was scored under *derivable from source*, and the
Design deletes under the narrower *same argument* test that replaced it. Two of the seven
candidates already fail that test outright and one is partial, so the same-argument test will
remove an unknown share of the 21,112B. AMBIGUOUS is adjudicated per paragraph rather than moved
wholesale, so its 3,402B is a ceiling too.

An earlier draft called this figure "a byte count of already-classified paragraphs, not an
estimate of a class boundary". That was true of the classifier's taxonomy and false of the
Design's, and it survived the revision that replaced the class definition -- the
premise-moved-conclusion-carried shape this corpus records. **The real number is not knowable
until gate 3 has run**, which is the correct place for it: gate 3 adjudicates every candidate
per sub-paragraph and records the verdict, so the figure is an output of the implementation
rather than an input to it.

HAZARD compression is not sized at all. It is judgement work with no predictable yield, and
claiming a figure for it would be the restated-count failure this corpus records.

The fleet combined target (~37,900 tokens, ~165k -> ~127k, haiku headroom ~35k -> ~73k)
inherits this bound and should be quoted the same way: an upper bound whose dotfiles component
will shrink. The fleet-wide RECORD component is unaffected -- it was classified directly rather
than through DERIVABLE.

**Ordering note, recorded rather than actioned here.** Shrinking the preamble raises the ceiling;
it does not make a future overrun legible. Without a budget-aware `_haiku_scope_errors`, the next
file that grows returns the fleet to the starting condition with nothing to say so. That work is
ai-config's file and is referred to that session; this spec improves the odds and does not close
the failure mode.

---

## Multi-Lens Review

Reviewed at commit: `20023924` (Step 7 self-review commit, before Step 8 dispatch).
Three lenses, fresh `general-purpose` subagents, no conversation context.

### Goal-Fit

Finding: Design is sound on goal-fit. The reads-it test passes -- the consumer is
`dotfiles/CLAUDE.md`'s own launch-load, which every session and every dispatched haiku task's
preamble pays for, so shrinking it changes a decision rather than decorating one. Of the 5 gates,
only 2 are pure measurement; gates 2 and 3 are constructed to fail on the nothing-happened case,
which is the opposite of the PASS-dominant pattern this lens looks for. Soft spot: this slice is
~6,300 tokens of a ~37,900 fleet target and the larger payoff depends on a peer effort landing
separately. Sharper: the spec leaves `_haiku_scope_errors` unfixed, and making that validator
budget-aware would close the opening failure mode *loudly at plan-validation time* rather than
making it less likely by shrinking the preamble. Scoped out as ai-config's file, which is a
legitimate split, but this spec alone does not close the failure mode it opens with.

Assumption: The whole quantitative case rests on bytes/4, and this content is table- and
code-block-heavy, which can tokenize at a materially different ratio in either direction.
Refute by running `/context` in a real dotfiles session before and after, or tokenising
`CLAUDE.md` with the real tokenizer instead of bytes/4.

Disposition: **Addressed** for the finding -- the `_haiku_scope_errors` half is referred to the
ai-config session as a question about their file (operator, 2026-09-21); it is not scoped into
this spec. Assumption stands unrefuted: every figure here remains labelled bytes / 4.

### Ergonomics

Finding: The DUPLICATE remedy is specified at symbol/table-row granularity, but the content is
not atomic at that granularity -- verified directly, not inferred. For `_OVERRIDE_LIB_TRAP_SCOPE`
(one of the two pairs this spec says were personally verified), the `CLAUDE.md` block holds two
sub-paragraphs: a mechanics paragraph that *is* a near-verbatim duplicate of the
`scripts/check-lib-exit-traps.sh` header, and a second paragraph -- "Two code paths, and the
tests only exercise one" -- with **zero counterpart** in that source file or its test file. A
literal reading of "delete the CLAUDE.md copy for this pair" deletes the hazard with the
duplicate. The end state is fine when classification is done per sub-paragraph; the gap is
specification precision, and it will produce a wrong result the first time a dispatched task
follows the DUPLICATE section at face value. The commit history already shows this failure at
smaller scale -- 3 of 7 line-number citations wrong in the first draft even after
spot-verification.

Assumption: That a full per-paragraph classification of all ~86 paragraphs will exist as a
durable artifact for gates 2 and 3 to check against. No such artifact is in the repo. If the plan
only restates the 7-row table plus prose, gate 3 has no ground truth for the other ~79 paragraphs
and degrades from a gate to a spot-check. Confirm by checking whether the plan file enumerates
paragraph-level classifications.

Disposition: **Addressed** (operator, 2026-09-21). Classification unit is now the sub-paragraph.
The assumption is closed rather than left open: gate 2 makes the per-paragraph phrase manifest a
committed artifact produced before the first edit, which is exactly the ground truth this lens
found missing.

### Risk

Finding: The coarse classification unit lets a HAZARD sentence be destroyed while **both** gates
report success -- confirmed, not hypothetical. The "login-shell seam, chsh PAM" row maps to two
`CLAUDE.md` paragraphs. Paragraph B is genuinely near-verbatim in `lib/helpers.sh:356-364`.
Paragraph A ends with a sentence that exists only in `CLAUDE.md`: *"Measured: the three
end-to-end `run_doctor` tests stub every sub-check by name, so `_doctor_check_login_shell` must
be stubbed there too or it reads the real account mid-suite."* A tree-wide grep for it returns
zero hits. Gate 2 requires only **one** phrase-match per row to authorize deleting the pair; gate
3 never re-examines it because the classifier scored it DUPLICATE, not HAZARD. It falls into
neither net: an implementer picks a chsh phrase, deletes both paragraphs, gates 2/3/4 go green,
and the test-stubbing guidance is gone with nothing pointing at its absence.

Second finding: gate 3 is circular as written. Nothing requires the distinctive phrase to be
chosen from the **pre-compression** text and locked before editing. A phrase selected from the
surviving text proves only that the edit contains a substring of itself -- `behavior.md`'s "a
check derived from the same decision as the thing it checks cannot falsify it", in this spec's
own gate.

Assumption: Whether HAZARD compression preserves claim substance is decided by execution quality
the spec does not gate on. Gate 3 can detect a claim's complete disappearance but not a claim
silently weakened into a vague summary that still contains the keyword. Confirm or refute by
having a reviewer who did not perform the compression re-derive phrases from
`git show <parent-sha>:CLAUDE.md` and grep the post-compression file -- never a phrase chosen by
the implementer from their own output.

Disposition: **Addressed** (operator, 2026-09-21). Both findings taken. Deletion now requires a
counterpart for every sentence removed, not one phrase per block. Phrases are taken from the
pre-change text, committed before the first edit, and chosen by someone other than the
implementer -- the lens's own refutation procedure is now the gate itself.

### Adversarial Spec Review (comparison/judge designs only)

N/A -- spec has no comparison arms, no evaluator component, and concrete acceptance criteria.

### External finding (ai-config peer session, same round)

Finding: The DUPLICATE test "the source file carries the same prose" is wrong. The correct test
is **both copies must serve the same argument**. Where each copy is evidence for a different
claim it is shared evidence, not restatement: keep both and cross-reference. That session's own
top lexical hit -- the `make` version table at 0.83 containment across `tdd.md` and
`behavior.md` -- fails this test: `tdd.md` uses it to argue *a local mac pass is not evidence and
CI is*, `behavior.md` to argue *a boundary can be an actor rather than a place*. Applied to this
spec, at least two of seven pairs look doubtful: `brew_cask_installed`'s source comment argues
why the code is shaped that way while the `CLAUDE.md` entry argues how to test it, and
`check-lib-exit-traps.sh`'s header argues why an allowlist rather than an inference while the
`CLAUDE.md` entry argues which seam a test drives.

Disposition: **Addressed** (operator, 2026-09-21). The same-argument definition is adopted
wholesale as the class definition rather than as a tiebreak. The candidate table is re-marked:
two fail outright, one is partial, four remain candidates for per-sub-paragraph adjudication in
the plan. The peer's 0-of-12 result and its citation-ranking cause are recorded in Design item 1
as the reason this class is expected non-empty here and empty in the standards.

---

## External Review (architect session, after multi-lens round 1)

Three findings, all taken.

1. **The Expected Outcome was computed from the class definition the Design replaced.** The
   6,300-token figure sums the classifier's DERIVABLE, scored under *derivable from source*,
   while the Design deletes under the *same argument* test that superseded it -- and the draft
   asserted the figure was "a byte count of already-classified paragraphs, not an estimate of a
   class boundary", which was true of the old taxonomy and false of the new one. The sizing was
   not re-derived when the external finding changed the class.
   Disposition: **Addressed** (operator, 2026-09-21). Expected outcome is restated as an upper
   bound, the superseded sentence is deleted and its failure recorded in place, and the real
   figure is made an output of gate 3 rather than an input to the spec.

2. **Gate 4 was open in both directions.** The manifest is committed before editing, so the
   compressor sees the phrases: false green by preserving the phrase and weakening everything
   around it -- which committing the manifest makes easier, not harder -- and false red when a
   legitimate rewording moves the claim to the first sentence and drops the phrase. Gate 4
   refutes deletion of a string, not weakening of a claim.
   Disposition: **Addressed** (operator, 2026-09-21). Compression must now preserve the manifest
   phrase verbatim, which converts the false-red case from a gate failure into a constraint on
   the compressor. Gate 5 is added as a non-implementer substance review, named as judgement
   rather than mechanism. The falsifiability paragraph no longer claims gate 4 alone makes the
   spec refutable.

3. **REFERENCE was a design class with no measurement row and a remedy the Non-goals forbid.**
   The measurement ran HAZARD / DERIVABLE / AMBIGUOUS / RECORD and the Design runs HAZARD /
   DUPLICATE / RECORD / REFERENCE -- two different class sets -- so a plan author reading the
   Design table would move REFERENCE text to a knowledge file and violate the non-goal.
   Disposition: **Addressed** (operator, 2026-09-21). The two taxonomies are reconciled where the
   measurement is stated: DERIVABLE is a superset of DUPLICATE, and REFERENCE has no instance in
   these two sections because its instances in this fleet are in ai-config's half.

Also noted and recorded rather than actioned: without a budget-aware `_haiku_scope_errors`, the
next file that grows returns the fleet to the starting condition with nothing to say so. That is
referred to the ai-config session as their file; the ordering note is in Expected outcome.

### Round-1 external review, second pass

Finding: the revision that addressed the three findings above **deleted the entire Multi-Lens
Review section** -- three lens records, the Adversarial N/A, and the ai-config peer finding that
produced the same-argument test, with their dispositions. The body kept citing them: gate 2 cites
the ergonomics lens, Design item 1 cites the peer's 0-of-12 result, and the Goal-Fit assumption
about bytes / 4 was left unrefuted with its record gone while every figure still depends on it.
Cause: the edit sliced `index("## Expected outcome")` to **end of string**, and the review section
sat after it -- the same unbounded-region class this corpus records twice already. Two smaller
residues from the same revision: two gate cross-references drifted when gates were inserted, and
the new verbatim-phrase constraint made phrase selection load-bearing without giving it a rule.

Disposition: **Addressed** (operator, 2026-09-21). Section restored from `9d28db69` with all
seven dispositions intact, placed after the lens record rather than nested under Expected outcome,
and relabelled -- it followed the multi-lens round rather than being round 1. Both cross-references
corrected. Phrase selection now has a rule: the phrase comes from the **claim sentence** of each
HAZARD sub-paragraph, which also aligns what gate 4 checks with what gate 5 judges. The edit that
restored it used bounded slices and the section list was re-grepped afterwards.
