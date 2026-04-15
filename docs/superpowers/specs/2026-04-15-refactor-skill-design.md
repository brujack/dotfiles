# Refactor Skill — Design Spec

**Date:** 2026-04-15
**Status:** Accepted

## Context

Code refactoring is a recurring activity across all projects but lacks a
consistent, structured approach. Without a guiding skill, refactoring tends to:

- Mix behavior changes with structural changes in the same commit
- Proceed without verifying tests first, making it hard to confirm nothing broke
- Skip identification of specific code smells, leading to incomplete cleanup
- Apply techniques inconsistently across languages and codebases

The existing `tdd` skill covers the red-green-refactor loop at the cycle level,
but does not provide detail on how to identify what to refactor or how to
execute it safely. A dedicated `refactor` skill fills this gap.

## Decision

Add a `refactor` skill to `~/.claude/skills/refactor/SKILL.md` that provides:

1. **Golden rules** — behavior must not change during a refactor; tests must
   exist before starting; changes must be small and incremental
2. **Code smell catalogue** — Bloaters, OO Abusers, Change Preventers,
   Dispensables, and Couplers with concrete examples of each
3. **Refactoring techniques** — Extract Method, Extract Class, Replace
   Conditional with Polymorphism, Introduce Parameter Object
4. **Safe process** — verify green → one change → run tests → commit → repeat
5. **Backward compatibility** — strategies for public API changes
6. **Structured output format** — Current Issue / Proposed Change /
   Step-by-Step Plan / Risk Assessment

The skill is triggered when the user asks to refactor code, clean up code
smells, restructure a class or function, or improve code quality without
changing behavior.

## Relationship to Other Skills

```
tdd      → red-green-refactor loop (macro cycle, per behavior)
refactor → how to identify smells and execute structural changes safely
           (used during the REFACTOR phase of the tdd cycle, or standalone)
```

The `refactor` skill is complementary to `tdd`, not a replacement. During TDD's
refactor phase, invoke `refactor` for guidance on what to change and how.

## Implementation

Single file: `.claude/skills/refactor/SKILL.md`

No plan file is needed — this is a skill addition with no dotfiles
implementation work (no shell functions, tests, or CI changes required).

## Consequences

- Refactoring sessions have a consistent structure: smells identified first,
  technique selected, safe incremental process followed
- Behavior changes and structural changes remain in separate commits
- The skill activates automatically when the user asks to "refactor" or
  "clean up" code, providing the catalogue and process without manual lookup
- The output format (Current Issue / Proposed Change / Plan / Risk) makes
  refactoring proposals reviewable before execution
