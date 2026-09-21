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
gate 2 below re-verifies every pair at implementation time rather than trusting this table.

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

   **The phrases are chosen by someone other than whoever performs the compression.** A phrase
   selected from surviving text proves only that the edit contains a substring of itself. This is
   the one gate the spec previously called falsifiable, and as first written it could not fail.

3. **Every DUPLICATE deletion: every sentence removed has a counterpart.** Per candidate, per
   sub-paragraph, `grep -n '<phrase>' <source file>` for **each sentence being deleted**, not one
   phrase authorising a block. A miss means that sentence is not part of a duplicate -- it stays,
   and the candidate is recorded as partial. Verdict plus reason recorded per candidate.

4. **No hazard claim lost.** Every phrase in the manifest whose row is classed HAZARD returns
   a hit in the post-change file. Not a byte count -- a byte count cannot distinguish
   compression from deletion. Run by a reviewer who did not perform the compression, against
   the manifest committed at gate 2.

5. **`make test` green** — `make lint` covers `CLAUDE.md` only via `check-agent-guidance`, so
   `make sync-agent-guidance` runs if `.cursor/rules/global-claude-standards.mdc` goes stale.
   Note that target is generated from the `@`-imports, not from body prose, so a body-only edit
   should leave it unchanged — if it does not, that is a finding.
6. **Post-change size reported with its denominator**, not as a bare figure: bytes before, bytes
   after, and the estimated token delta labelled as bytes ÷ 4.

**Falsifiability:** gate 4 is what makes this spec refutable rather than self-confirming. A
change that deletes hazard text while hitting its size target passes gates 1, 5 and 6 and fails
gate 4. Gate 3 is the same shape one level down — it can fail, and a failure means a planned
deletion does not happen.

## Expected outcome

Movable from `dotfiles/CLAUDE.md`: DERIVABLE 21,112B + RECORD 780B + AMBIGUOUS 3,402B ≈ 25,294B
≈ **6,300 tokens**, bytes ÷ 4. HAZARD compression is not sized here — it is judgement work with
no predictable yield, and claiming a figure for it would be the restated-count failure this
corpus records.

Against the fleet plan (ai-config's three items, ~31,600 tokens) the combined target is
~37,900 tokens: a dotfiles session ~165k → ~127k, haiku executor headroom ~35k → ~73k.

The plan-changing threshold for the fleet-wide RECORD figure is ~10,000 tokens, against an
independently bracketed 18k–37k. This spec's own 6,300 is a smaller and more certain number: it
is a byte count of already-classified paragraphs, not an estimate of a class boundary.

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
