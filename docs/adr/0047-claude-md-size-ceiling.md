# ADR-0047: CLAUDE.md has a hard size ceiling, one line per rule

**Date:** 2026-10-18
**Status:** Accepted

## Context

ADR-0036 moved narrative out of `CLAUDE.md` and took it from 179,422 B to 122,627 B. Nothing
measured the file afterwards, and in three weeks it regrew to 155,308 B, mostly as new
`### Test Seams` entries. `CLAUDE.md` is loaded by every session in this repo before it reads
any file, so regrowth is paid for on every launch.

Two mechanisms were rejected:

- **ai-config's ADR-0079 trailer gate.** Any one-line `Context-Budget-Growth:` reason clears
  it, so it records growth instead of stopping it, and it would put ai-config's main-checkout
  code on dotfiles' push path.
- **A per-block length cap.** A cap on each block does not bound the file, and it forces
  every rule into a shape that some rules do not fit; a ceiling on the whole file leaves the
  author to choose what to relocate.

ADR-0036 decision 4 kept test seams whose failing path touches live state whole in
`CLAUDE.md`. That kept the largest entries in the file and is the main source of regrowth.

Full record: `docs/superpowers/specs/2026-10-17-claude-md-budget-design.md`.

## Decision

1. **One line per rule.** `CLAUDE.md` states each rule in one line. Verbatim detail lives in
   `ai-config/docs/knowledge/dotfiles-*.md`, reached by ADR-0036's pointer
   (`` → `<file>` § `<heading>` ``).
2. **A hard 105,000-byte ceiling.** `scripts/claude_md_budget.py` fails when `CLAUDE.md`
   exceeds it. It runs in `scripts/pre-push`, using the checker taken from the pushed commit
   and running before the docs-only early exit so a `CLAUDE.md`-only push is checked, and in
   `make test` through the `check-claude-md-budget` target.
3. **No override.** There is no trailer, flag or environment variable that skips or raises
   the limit. Raising the ceiling requires an amendment to this ADR stating why.
4. **Seam routing.** A new test seam's description goes to
   `ai-config/docs/knowledge/dotfiles-test-seams.md`; `CLAUDE.md` carries only a one-line
   entry and pointer.
5. **Supersedes ADR-0036 decision 4.** Live-state seams no longer stay whole. Their lines
   keep the seam variable and the exact safe override, as ai-config's `core.md` destructive
   rows do, and the detail moves to the knowledge file. ADR-0036 is otherwise unchanged and
   is not edited; this ADR references it.

### Basis for the ceiling

Two dry runs projected the compressed file at 93-99 KB: a ratio of 0.351 measured on the 15
largest blocks, and 0.747 on a stratified sample of the remaining blocks. The shipped file
measured about 74 KB at merge (about 70 KB before the rule-by-rule review restored 19 weakened or pointer-only rules); `wc -c CLAUDE.md` gives the current figure. 105,000 B sits above the projection with room for ordinary growth,
and well below the 155,308 B regrowth point.

## Consequences

- The pre-push hook runs code taken from the pushed commit. That is the same trust level as
  `make test` running the checked-out tree, but it means pushing a ref you did not author
  runs that ref's checker.
- If master ever exceeds the ceiling, every later PR fails `make test` until a relocation
  lands. The remedy is relocation, never a bypass.
- A legitimately large new seam is relocated to the knowledge file, so a feature PR now
  touches two repos when it adds a seam.
- Pointers depend on ai-config's headings, as in ADR-0036; renaming a `###` heading in a
  `dotfiles-*.md` knowledge file breaks a pointer.

## Related

- ADR-0036 (relocation of narrative to ai-config knowledge; decision 4 superseded here)
- ai-config ADR-0020 (knowledge consolidation); ai-config ADR-0077 (what `CLAUDE.md` holds);
  ai-config ADR-0079 (the trailer gate, rejected here)
- `docs/superpowers/specs/2026-10-17-claude-md-budget-design.md`
