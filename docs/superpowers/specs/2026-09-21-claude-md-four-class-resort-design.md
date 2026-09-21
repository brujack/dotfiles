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

The binding constraint is not the 1M main-thread window. It is **haiku executor headroom**, and
it is now measured rather than inferred.

**Measured 2026-09-21, this repo.** A Haiku 4.5 subagent dispatched from a dotfiles session with
the entire prompt `Reply with exactly the word OK. Do not use any tools. Do not explain.` --
so everything consumed is preamble:

```
turn 1   input=10   cache_read=16,588   cache_creation=168,534   output=39
         starting context = 185,132 tokens
         headroom against Haiku 4.5's 200,000 = 14,868      92.6% of the window consumed
```

**Method**, because a subagent cannot introspect its own context and the parent can: the harness
persists the subagent transcript as JSONL with a `message.usage` block per turn, at the task's
`<output-file>` path. Turn 1's `input_tokens + cache_read_input_tokens +
cache_creation_input_tokens` is the starting context. Owed to the ai-config session, which
established the method and measured its own repo first.

**Do not use the `subagent_tokens` figure from the task notification.** For this probe it read
190,214 against a true 185,132 -- a 5,082 overstatement, close enough to look usable and a
different quantity (cumulative across turns, including cache re-reads). Comparing it to a window
size is a category error that happens to land near the right answer at this length.

`roleModels.executor-mechanical` is Haiku, and `.claude/scripts/validate-plan.py:105`
`_haiku_scope_errors` checks `files_touched` length and forbidden patterns and never checks
context budget -- so such a task is certified green with 14,868 tokens for its prompt, tool
schemas, file reads and output. Two dotfiles dispatches have already failed this way.

**The failure mode reproduced during this probe**, at both repos' preambles. The agent replied
`OK` on turn 1 as instructed, then ran four more turns on a prompt forbidding tools, and on turn
4 spent 786 output tokens writing a summary of a session that never happened -- "resuming from a
prior context-limited session", "No action items or pending work", a list of standards it had
loaded. It did not fail. It complied, failed to stop, and confabulated history. ai-config saw the
same shape at 81.5% consumed; this was 92.6%.

Stated as headroom, not overflow: 185,132 is under 200,000. The claim is that 14,868 is not
enough room, not that the window is exceeded.

**A correction to every estimate in this document's earlier drafts.** The Problem statement
previously said "~165,000 tokens of markdown" and "roughly 35k" of headroom, both derived by
bytes / 4 over the launch-loaded set. Measured, the preamble is 185,132: **bytes / 4 understated
it by about 12%**, in the direction that flatters the current state. Every bytes / 4 figure that
survives below is labelled as such and should be read as a floor.

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
gate 4 below re-verifies every pair at implementation time rather than trusting this table.

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
- **No `.claude/rules/` destination.** `~/.claude/rules` does **not exist at all** -- verified
  `ls`, `readlink` and `find ~/.claude -maxdepth 1 -name 'rules*'`, all absent. This corpus
  describes it as a "dangling symlink" in several places, including the 2026-09-11 re-sort spec's
  out-of-scope list; that characterisation is wrong and was inherited here before being checked.
  The practical conclusion is unchanged -- that home does not exist today -- but the stated
  mechanism was.
- **No launch-load ratchet.** Deferred in ai-config with three rounds of findings; this spec does
  not revive it.

## Verification

Run before implementation, not predicted:

1. **Baseline, recorded at the implementation commit's parent SHA:**
   `wc -c CLAUDE.md` and the per-section byte counts for `### Test Seams` and
   `### MAKEFLAGS and Stdout Partition`.
2. **Phrase manifest, written first and locked.** Before any edit, produce
   `docs/superpowers/plans/<plan>-phrases.md`: one row per sub-paragraph of both sections, its
   class, and a distinctive phrase taken from the pre-change text at the parent SHA. Commit it
   before the first edit. This is the ground truth gates 4, 5 and 6 check against, and it is the
   per-paragraph classification that does not otherwise exist -- without it gate 5 has no universe
   beyond the candidate table.

   **2a. The manifest must be complete, and completeness is asserted, not trusted.** Row count
   must equal a paragraph count re-derived from the two sections at the parent SHA by a blank-line
   split. At `60e72a02` that count is **88** -- 78 in `### Test Seams`, 10 in
   `### MAKEFLAGS and Stdout Partition`. A short count fails the gate. Without this, an omitted row
   is invisible to every later gate: gate 5's universe *is* the manifest, and gate 6 is scoped to
   what the manifest classed HAZARD, so an omitted paragraph is unprotected by both while the
   gates report clean. That is `tdd.md`'s hand-maintained-denominator failure, and every previous
   revision of this spec added a check on classification *correctness* while leaving *completeness*
   ungated.

   **2b. Phrase selection has three mechanical constraints, all checked before the manifest is
   locked.** Each exists because the obvious phrasing breaks the check:

   - **Unique.** The phrase must occur exactly once in the pre-change file. A phrase that also
     appears elsewhere lets gate 5 match an unrelated surviving occurrence and report a gutted
     paragraph as preserved -- the gate defeated by its own instrument. Measured: a 4-word window
     from a paragraph's first sentence collides in 2 of 78 cases, so this is uncommon rather than
     routine, and cheap to assert.
   - **Not sentence-initial.** The phrase must not begin at a sentence boundary. The HAZARD remedy
     moves the claim to the first sentence, which requires capitalising its first word, and the
     search is case-sensitive -- so a sentence-initial phrase fails on a correct rewrite.
   - **Wrap-tolerant by construction of the check, not by choosing short phrases.** See 3a.

3. **The check is a whitespace-normalised substring search, never `grep -n`.** `CLAUDE.md` is
   hand-wrapped at 80-100 columns and `grep` is line-oriented, so a phrase spanning a wrap returns
   no hit **on unmodified text**. Measured at `60e72a02`: **46 of 78** `### Test Seams` paragraphs
   have a first sentence that itself spans a wrap, so a phrase drawn from the claim sentence --
   which this spec's own rule directs -- is unfindable by `grep` in the majority of cases, and
   gates 5 and 6 would false-HOLD on correct, untouched work. Normalise both sides and count:

   ```python
   import re
   norm = lambda s: re.sub(r'\s+', ' ', s)
   hits = norm(open('CLAUDE.md').read()).count(norm(phrase))
   ```

   `hits == 1` before locking the manifest; `hits >= 1` after the change for a HAZARD row.

   **3a.** Because the check normalises, phrases may be full claim clauses rather than short
   wrap-safe fragments. An earlier draft would have relied on authors picking short phrases by
   unstated convention while the stated rule pointed the other way.

4. **Every DUPLICATE deletion: every sentence removed has a counterpart.** Per candidate, per
   sub-paragraph, the normalised search of gate 3 run against the source file for **each sentence
   being deleted**, not one phrase authorising a block. A miss means that sentence is not part of
   a duplicate -- it stays, and the candidate is recorded as partial. Verdict plus reason recorded
   per candidate.

5. **No hazard claim lost.** Every manifest phrase whose row is classed HAZARD returns a hit in
   the post-change file under the gate 3 search. Not a byte count -- a byte count cannot
   distinguish compression from deletion.

   **Compression must preserve the manifest phrase**, modulo the whitespace the search normalises.
   That is a constraint on the compressor, not a property the gate discovers.

   **What this gate does not do.** The manifest is committed before editing, so the compressor
   works with the phrases in view. Gate 5 detects **outright loss of a claim** and nothing else.
   It cannot detect a claim silently weakened -- a specific measured failure mode replaced by a
   vague summary that still contains the phrase -- and committing the manifest makes that easier
   to hit, not harder. Substance is carried by gate 6, not by this gate.

6. **Substance review by a non-implementer, with a recorded verdict.** For every HAZARD paragraph
   the compression touched, a reviewer who did not perform the compression reads the pre-change
   text at the parent SHA against the post-change text and judges whether the claim still says the
   same thing. **Verdict plus one-line reason recorded per paragraph**, in the manifest file, the
   same way gate 4 records per candidate -- without a record this gate produces a PASS that is
   purely an assertion, which is the trust-signal failure `USER.md` names. This is the only check
   on weakening; it is judgement rather than mechanism and is named as such.

   **Batch bound.** Roughly 52 sub-paragraphs are HAZARD-classed. Compression and this review run
   in batches of at most 10 paragraphs per dispatch. Nothing detects a single subagent attempting
   all 52 in one pass, and that is the shape most likely to produce uniform shallow rewrites that
   each retain their phrase.

   **Separation is two actors, not three, and nothing mechanically enforces it.** Gate 2's phrase
   author and this gate's reviewer may be the same actor; only the compressor must differ. That
   maps onto the existing ADR-0009 cycle -- operator writes the manifest in Phase 1, dispatches a
   compressor in Phase 2, reviews in Phase 3 -- so it is not new ceremony. But no gate checks that
   the manifest commit and the compression commits came from different actors, and nothing stops
   the compressor editing the locked manifest. If one context does both, the separation is fiction
   and nothing says so.

7. **`make test` green** — `make lint` covers `CLAUDE.md` only via `check-agent-guidance`, so
   `make sync-agent-guidance` runs if `.cursor/rules/global-claude-standards.mdc` goes stale.
   Note that target is generated from the `@`-imports, not from body prose, so a body-only edit
   should leave it unchanged — if it does not, that is a finding.
8. **Post-change size reported with its denominator**, not as a bare figure: bytes before, bytes
   after, and the estimated token delta labelled as bytes ÷ 4.

**Falsifiability rests on gates 4, 5 and 6 together, and each covers a different failure.**
Gate 4 can refuse a planned deletion when a sentence has no counterpart. Gate 5 catches a hazard
claim disappearing outright; a change that hits its size target by deleting hazard text passes
1, 7 and 8 and fails 5. Gate 6 is the only check on a claim surviving as a string while being
weakened as a claim, and it is a human reading rather than a mechanism -- so the spec is
refutable on deletion mechanically and on weakening only by review. Saying that plainly is
better than an earlier draft's claim that the phrase gate alone made the spec refutable, which was true
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
until gate 4 has run**, which is the correct place for it: gate 4 adjudicates every candidate
per sub-paragraph and records the verdict, so the figure is an output of the implementation
rather than an input to it.

HAZARD compression is not sized at all. It is judgement work with no predictable yield, and
claiming a figure for it would be the restated-count failure this corpus records.

**The fleet combined target, restated against the measurement and decomposed per repo.** There
is no single fleet headroom figure, because `dotfiles/CLAUDE.md` is in dotfiles' launch-load and
not in ai-config's, and the two repos start from different bases:

| | today | + standards work | + this spec | after |
| --- | --- | --- | --- | --- |
| dotfiles | 14,868 measured | ~31,605 | <=6,300 upper bound | **~52,800** |
| ai-config | 36,909 measured | ~31,605 | n/a | **~68,500** |
| other 7 repos | unmeasured | ~31,605 | n/a | unmeasured |

**An earlier draft claimed `~35k -> ~73k` and both terms were wrong.** The base was bytes / 4 and
understated by 12%; the target counted this spec's dotfiles gain against a fleet-wide base, which
is two different denominators. Corrected, dotfiles goes from **7.4% of the window free to about
26%** -- roughly tripling, which is a real result and not the one previously claimed.

The other seven repos are deliberately left unmeasured rather than represented by a figure. Each
has its own `CLAUDE.md` and skill surface, and the two measured repos differ by 22,041 tokens
against a markdown delta that does not account for all of it -- so interpolating the rest would
be inventing numbers in exactly the way this spec's history has already been burned by twice.

**Durability: the trim refills, and the rate is measured.** dotfiles `CLAUDE.md` grew +16.0
lines/day over the 11 days since ADR-0077's writer routing went live (23 commits, +176 net),
against +7.9/day over the 90 days before it. At roughly 240 tokens/day, this spec's <=6,300
tokens refill in about **26 days**. The fleet-wide trim is larger and buys proportionally longer.
Attribution matters and cuts against reading this as routing having failed: the post-routing
split is `fix` +83, `feat` +47, `docs` +46, so the dominant writer is feature work documenting
itself, which ADR-0077's routing does not govern and arguably should not. Caveats: 11 days
against 90, 23 commits, three of them unusually documentation-heavy. Not a trend -- the
defensible claim is that **trim durability is not secured by routing alone**, which is the
argument for the launch-load ratchet ADR-0077 deferred.

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

## Multi-Lens Review, round 2 (aborted and re-dispatched)

**All three round-2 lenses were pointed at a stale file and the round was voided.** The lenses
were given `/home/bruce/git-repos/personal/dotfiles/...`, the main checkout, which was three
revisions behind: every spec commit after `20023924` was pushed from the worktree
`dotfiles-wt-launchload` and the main checkout was never fast-forwarded. The goal-fit lens read a
document ending at "Expected outcome" with no review section, correctly reported that as either
a recurrence of the deletion incident or a briefing mismatch, and said so rather than working
around it. The other two were stopped before spending their remaining budget on the same text.

**Round 1's ergonomics lens reported this exact condition and it was not acted on.** Its words:
*"I had to locate the spec on an uncommitted-to-master branch... it isn't on `master` or in the
working tree, so the path given in the task didn't resolve directly; worth flagging in case that
branch state itself is a coordination gap for review."* It was flagged, it was a coordination
gap, and it then invalidated a whole round. A reviewer pointed at the wrong artifact produces a
correct verdict about something else, which is this corpus's displaced-check failure arriving
through a checkout rather than through a file path.

**How to apply, for any future dispatch:** state the SHA the reviewer should see and have it
verify with `git log --oneline -1 -- <path>` before reading, so a stale tree fails loudly at the
first command instead of silently producing a review of superseded text. Syncing the checkout is
the fix; the verification step is what makes the fix checkable.

Two findings from the voided round transfer to the current text and are taken:

- **`~/.claude/rules` does not exist at all**, rather than being a dangling symlink. Verified
  three ways. Corrected in Non-goals, with the note that the wrong characterisation was inherited
  from this corpus rather than invented here.
- **The gap has never been measured.** Neither this spec nor the referenced knowledge file
  records how much headroom the two failed dispatches actually needed, so every figure sizes the
  fix without knowing the size of the problem. Recorded in Expected outcome as an open item, with
  the cheap closing procedure named.

A third finding -- that Expected outcome double-counts AMBIGUOUS as certainly movable -- was
already addressed at `4250cf5b`, before the lens read the file. Its own text now reads "AMBIGUOUS
is adjudicated per paragraph rather than moved wholesale, so its 3,402B is a ceiling too."

## Multi-Lens Review, round 2 (re-dispatched against `60e72a02`)

All three lenses ran the SHA check as their first command and all three reported `60e72a02`.
The check is the remedy for the voided round above and it worked.

### Goal-Fit (round 2)

Finding: manifest exhaustiveness is required in prose and gated nowhere. Nothing compares the
manifest's row count to an independently derived paragraph count. An omitted row is invisible to
every later gate, because the hazard gate's universe *is* the manifest and the substance review
is scoped to what the manifest classed HAZARD. `tdd.md`'s hand-maintained-denominator failure.
Sharper framing: all three prior fixes added checks on classification *correctness* and none on
manifest *completeness*. Proportionality remains a soft spot -- eight gates and two review roles
for an upper bound the spec says will shrink -- noted as open rather than as a new defect.
Assumption: that the manifest will be exhaustive by diligence alone. Refute by asserting row
count against a re-derived split before trusting the hazard gate.
Disposition: **Addressed** (operator, 2026-09-21). Gate 2a asserts row count against a blank-line
split at the parent SHA. The baseline is measured and stated: **88** -- 78 in Test Seams, 10 in
MAKEFLAGS.

### Ergonomics (round 2)

Finding: **demonstrated against unmodified text, not reasoned.** `grep -n` is line-oriented and
`CLAUDE.md` is hand-wrapped, so a phrase spanning a wrap returns no hit on the *original* file --
reproduced on lines 496-497. The spec's own rule ("taken from the claim sentence") points authors
at exactly the phrases most likely to break it. Re-measured here: **46 of 78** Test Seams
paragraphs have a first sentence that itself spans a wrap, so the gates would false-HOLD on
correct untouched work in the majority of cases. Compounding: the HAZARD remedy moves the claim to
sentence-initial position, which requires capitalising its first word, and the search is
case-sensitive. Also corrected the brief's premise: the spec requires **two** actors, not three --
the phrase author and the substance reviewer may be the same, only the compressor must differ --
which maps onto the existing ADR-0009 cycle rather than being new ceremony. And nothing bounds
batch size over the ~52 HAZARD paragraphs.
Assumption: that authors will pick short wrap-safe phrases by unstated convention while the
stated rule points the other way.
Disposition: **Addressed** (operator, 2026-09-21). The check is now a whitespace-normalised
substring search with the code given, never `grep -n`, which removes the wrap problem at the
mechanism rather than by convention and lets phrases be full claim clauses. Phrases must not be
sentence-initial, which removes the capitalisation break. The two-actor correction and the
batch bound of 10 are both written into gate 6.

### Risk (round 2)

Finding 1: gate 4 had no uniqueness requirement on its phrase, so it could match an unrelated
surviving occurrence and report a gutted claim preserved -- the gate defeated by its own
instrument. Finding 2: the substance review had no recorded verdict, unlike the per-candidate
gate beside it, and nothing detects it being skipped or performed by the implementer: a PASS that
is purely an assertion, which is `USER.md`'s trust-signal rule. Finding 3: manifest completeness
ungated, independently of Goal-Fit. Gate renumbering checked across 21 cross-references and found
clean. Empty input: the deletion gate is vacuously satisfied when nothing is deleted, so the full
machinery can run for a DUPLICATE yield of zero with nothing flagging it -- proportionality risk,
not a correctness defect.
Assumption: that the chosen phrase is actually distinctive. Refute by `grep -c` per row before
locking.
Disposition: **Addressed** (operator, 2026-09-21) for findings 1-3. Uniqueness is asserted in gate
2b, with the measured collision rate stated (2 of 78 for a 4-word window -- uncommon rather than
routine, and the Risk lens's single-term examples overstated it). Gate 6 now records a verdict
plus reason per paragraph. Completeness is gate 2a. The empty-yield observation is recorded and
**not** designed around: the spec deliberately refuses to promise a floor.

### Adversarial Spec Review

N/A -- no comparison arms, no evaluator component, concrete acceptance criteria.

**Renumbering note.** These fixes took the gate list from 7 to 8. Every cross-reference in the
**body** was retargeted and re-listed; the references inside the review sections above were left
alone, because they record what a lens said against the numbering it read. That is the frozen
reference rule -- a record is not edited to match a present it was not written against.

