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
is 44,012 tokens of it — the largest single file anyone in this fleet loads, larger than any
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

Every paragraph of `### Test Seams` and `### MAKEFLAGS and Stdout Partition` (66,200 bytes,
~86 paragraphs) classified against real source, 10 spot-verified by grep:

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

| CLAUDE.md topic | symbol | file |
| --- | --- | --- |
| cask guard, incl. `Measured 2026-09-12` | `brew_cask_installed` | `lib/helpers.sh` |
| ggshield actor boundary | `GGSHIELD_FALLBACK_PATHS` | `scripts/pre-commit-hook.sh` |
| EXIT-trap ratchet scope | `_OVERRIDE_LIB_TRAP_SCOPE` | `scripts/check-lib-exit-traps.sh` |
| FIFO deadlock pre-flight | `_OVERRIDE_BATS_BIN` | `scripts/run-bash-coverage.sh` |
| rustup seams, why sha256sum is not mocked | `_RUSTUP_INIT_SHA256` | `lib/linux_ubuntu.sh` |
| login-shell seam, chsh PAM | `_OVERRIDE_CURRENT_LOGIN_SHELL` | `lib/helpers.sh` |
| `export` vs `readonly` re-source scope | -- | `config/profiles.zsh` |

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
| **DUPLICATE** | the source file carries the same prose                                             | **delete the CLAUDE.md copy**, keep the one next to the code |
| **RECORD**    | dated provenance whose rule is stated adjacently                                   | move to `ai-config/docs/knowledge/dotfiles-*.md`             |
| **REFERENCE** | bibliography or bootstrapping scaffolding                                          | move to the skill or knowledge file that needs it            |

### 1. DUPLICATE — delete the CLAUDE.md copy, keep the source comment

For each pair in the table above: delete the `CLAUDE.md` prose, leave the source comment
untouched. **Direction is fixed and not a per-pair judgement** — the copy next to the code is
the one a reader reaches while editing, and it cannot drift from the code it annotates without
someone seeing both in one diff.

Where deleting the `CLAUDE.md` copy would leave the seam unnamed, a one-line entry stays naming
the variable and the file that defines it, with no rationale. The rationale is in the source.

Every deletion requires the source copy to be **verified present for the named symbol in the
same change**, not assumed from this table. A pair where the source comment has since been trimmed is
not a DUPLICATE — it is the only surviving copy and it stays.

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
2. **Every DUPLICATE deletion has its source copy asserted present first:**
   for each pair, `grep -n '<distinctive phrase>' <source file>` returns a hit at the named line
   **before** the `CLAUDE.md` prose is removed. A miss means that pair is not a DUPLICATE and
   the `CLAUDE.md` copy stays. This gate runs per pair, not once.
3. **No hazard claim lost:** every paragraph classified HAZARD is present in the post-change file,
   verified by a distinctive-phrase grep per paragraph, not by a byte count. A byte count cannot
   distinguish compression from deletion.
4. **`make test` green** — `make lint` covers `CLAUDE.md` only via `check-agent-guidance`, so
   `make sync-agent-guidance` runs if `.cursor/rules/global-claude-standards.mdc` goes stale.
   Note that target is generated from the `@`-imports, not from body prose, so a body-only edit
   should leave it unchanged — if it does not, that is a finding.
5. **Post-change size reported with its denominator**, not as a bare figure: bytes before, bytes
   after, and the estimated token delta labelled as bytes ÷ 4.

**Falsifiability:** gate 3 is what makes this spec refutable rather than self-confirming. A
change that deletes hazard text while hitting its size target passes gates 1, 4 and 5 and fails
gate 3. Gate 2 is the same shape one level down — it can fail, and a failure means a planned
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
