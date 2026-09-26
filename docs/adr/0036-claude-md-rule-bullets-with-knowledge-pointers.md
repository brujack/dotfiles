# ADR-0036: CLAUDE.md carries rule bullets; narratives live in ai-config knowledge

**Date:** 2026-09-26
**Status:** Accepted.

## Context

`CLAUDE.md` is loaded by every session in this repo before it reads any file. At `2e38f5e4`
it was 179,422 B, measured at **67.3k tokens** in a fresh session on the Mac Studio
(about 2.67 B/token). Most of its length was incident history and measurements written
next to the rule each incident produced. `~/.claude/CLAUDE.md` already routes that material
to `ai-config/docs/knowledge/<repo>-<topic>.md` (ADR-0020 in ai-config), while gate and
safety rules stay in `CLAUDE.md` (ADR-0077 rule 5 in ai-config).

#293 tried to cut the file by deleting duplicates. It removed a net 228 B.

The first relocation design kept every rule sentence verbatim, selected by a keyword regex.
An independent block review failed it on 58 of 85 groups. The regex missed rules phrased as
plain imperatives, and sentences kept on their own lost the antecedents that gave them
meaning. Full record: `docs/superpowers/specs/2026-09-25-claude-md-relocation-design.md`
and `docs/superpowers/plans/2026-09-25-relocation-map.md`.

## Decision

1. **Narrative moves verbatim.** Each block's incident history and measurements move
   byte-for-byte into `ai-config/docs/knowledge/dotfiles-*.md`, under a `###` heading
   unique to that block.
2. **The rule stays, hand-written.** `CLAUDE.md` keeps 1–3 imperative lines per block. They
   state every rule in the block, self-contained, with any needed "why" in one clause.
3. **A compact pointer closes each block.** The block's last rule line ends in
   `` → `<file>` § `<heading>` ``. One legend line after the H1 says what the arrow means.
4. **Some units stay whole in `CLAUDE.md`:**
   - test seams whose failing path touches live state (every unit citing `tdd.md` E2,
     plus the `sudo`-exec and `_OVERRIDE_CLAUDE_SETTINGS` seams);
   - short standing conventions and commands.
5. **Coverage is checked by an independent reviewer, not by a regex.** Every relocated
   block gets a verdict against its original: covered, weakened, missing, or wrong.
   `scripts/relocation_check.py` verifies what is mechanical: nothing lost from the
   destination, one pointer per block, pointers resolve, and the size bound. That tool
   runs by hand for a relocation; nothing gates on it.

## Consequences

- **`CLAUDE.md` went from 179,422 B to 122,627 B (−31.7%).** Per-file tokens are
  projected at about 46k against the 67.3k baseline. The post-merge fresh-session
  `/context` figure is the measurement.
- **Most of the remaining launch load is out of this repo's reach.** The shared
  standards and `USER.md` are about 149k of the 216k memory-file tokens.
- **A new rule in a narrative-heavy section is written as a bullet plus pointer**, not as
  a paragraph. The story goes into the knowledge file.
- **Paraphrase risk is accepted and bounded by review.** A rule line can weaken a rule.
  Three review rounds took the findings from 58 to 14 to 1 to 0. Any future relocation
  needs the same independent block review.
- **The knowledge files hold dotfiles ADR numbers inside ai-config**, where the same
  numbers name unrelated ADRs. Each affected file carries an ownership note.
- **Pointers depend on ai-config's headings.** Renaming a `###` heading in a
  `dotfiles-*.md` knowledge file breaks a pointer, and nothing but a re-run of
  `relocation_check.py check` detects it.

## Related

- ai-config ADR-0020 (knowledge consolidation); ai-config ADR-0077 (what `CLAUDE.md` holds)
- `docs/superpowers/specs/2026-09-21-claude-md-four-class-resort-design.md` (#293, the
  deletion approach this supersedes for the remaining scope)
- brujack/dotfiles#294, brujack/ai-config#282
