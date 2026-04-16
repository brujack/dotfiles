> **Status: DONE**

# Refactor Skill Implementation Plan

**Goal:** Add a `refactor` skill to `~/.claude/skills/refactor/SKILL.md` providing a consistent, structured approach to code refactoring across all projects.

**Architecture:** Single skill file. No shell functions, tests, or CI changes required — skill activation is handled by Claude Code's skill loading mechanism.

**Tech Stack:** Claude Code skills (`~/.claude/skills/`), dotfiles symlink infrastructure

---

## Task 1: Write refactor SKILL.md

**Files:**

- Create: `.claude/skills/refactor/SKILL.md`

**Steps:**

1. Write skill covering golden rules (no behavior changes, tests first, small incremental steps)
2. Include code smell catalogue: Bloaters, OO Abusers, Change Preventers, Dispensables, Couplers
3. Include refactoring techniques: Extract Method, Extract Class, Replace Conditional with Polymorphism, Introduce Parameter Object
4. Include safe process: verify green → one change → run tests → commit → repeat
5. Include structured output format: Current Issue / Proposed Change / Step-by-Step Plan / Risk Assessment

**Acceptance Criteria:**

- Skill activates when user asks to refactor, clean up code smells, or improve code quality
- Behavior change and structural change remain in separate commits
- Output format is reviewable before execution

---

## Task 2: Add skill to dotfiles and update index

**Files:**

- Create: `.claude/skills/refactor/SKILL.md` (via dotfiles symlink)
- Modify: `docs/superpowers/README.md`

**Steps:**

1. Place `SKILL.md` in `.claude/skills/refactor/` within dotfiles repo
2. Add row to All Plans table in `docs/superpowers/README.md`
3. Mark status Done once PR merges

**Acceptance Criteria:**

- Skill is available via `~/.claude/skills/refactor/` symlink on all machines
- README index entry links to this plan and the spec
