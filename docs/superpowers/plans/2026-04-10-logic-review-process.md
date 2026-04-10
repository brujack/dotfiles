# Logic Review Process Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a comprehensive logic review process to `~/.claude/CLAUDE.md` covering pre-commit checks, deep on-demand review, and enhanced TDD test requirements.

**Architecture:** Three edits to one file (`~/.claude/CLAUDE.md`): extend the TDD section with mandatory test categories, add a new Logic Review section after Linting, and add a cross-reference in Committing Work.

**Tech Stack:** Markdown (documentation only — no code changes)

---

## Files

| File | Action | Purpose |
|---|---|---|
| `~/.claude/CLAUDE.md` | Modify | Add logic review process (3 edits to existing file) |
| `docs/superpowers/README.md` | Modify | Add plan entry to index |

---

## Task 1: Extend TDD section with mandatory test categories

**Files:**
- Modify: `~/.claude/CLAUDE.md:46-60` (Test-Driven Development section)

- [ ] **Step 1: Add test categories after the TDD cycle**

Find this block in `~/.claude/CLAUDE.md`:

```markdown
**Never write implementation before the test.** If you find yourself writing code and then adding tests afterward, stop — you are doing it wrong.

Tests must be added alongside the code they cover, not as a separate pass. Every new function, every changed function, every bug fix gets a test in the same commit.
```

Insert the following immediately before `Tests must be added alongside the code they cover`:

```markdown
### Mandatory Test Categories

Every test must cover more than just the happy path. These three categories are required for every function:

**Boundary value tests** — For every function that takes input (arguments, env vars, file paths), test at boundaries:
- Empty / zero / null input
- Single element vs multiple elements
- Minimum and maximum valid values
- One above and one below valid range (where applicable)

**Error path tests** — For every function that can fail, test:
- What happens when it fails (correct error message, correct exit code)
- What happens when a dependency it calls fails (does it propagate or handle?)
- Partial failure — if step 2 of 3 fails, is state left clean?

**State transition tests** — For functions that modify state (variables, files, symlinks):
- Before and after assertions — verify the expected state change occurred
- Verify no unintended side effects (other state unchanged)
- Idempotency — calling the function twice produces the same result as calling it once

A test that only covers the happy path is incomplete.

```

- [ ] **Step 2: Verify the edit reads correctly**

Read `~/.claude/CLAUDE.md` from the TDD section and confirm the new subsection appears between the TDD cycle and the "never write implementation before the test" rule, and that the closing "Tests must be added alongside..." line is still present.

- [ ] **Step 3: Commit**

```bash
git add ~/.claude/CLAUDE.md
git commit -m "docs: add mandatory test categories to TDD section in global CLAUDE.md"
```

---

## Task 2: Add Logic Review section

**Files:**
- Modify: `~/.claude/CLAUDE.md:62-68` (after Linting, before GitHub Actions / CI)

- [ ] **Step 1: Insert the Logic Review section**

Find this block in `~/.claude/CLAUDE.md`:

```markdown
## GitHub Actions / CI
```

Insert the following immediately before `## GitHub Actions / CI`:

```markdown
## Logic Review

### Pre-Commit Checklist

Run this checklist against staged changes before every commit. Read the diff and check each item:

1. **Conditional logic** — Are all operators correct (`&&`/`||`, `-eq`/`-ne`, `==`/`!=`)? Is grouping precedence explicit (no reliance on implicit `||`/`&&` precedence)?
2. **Boundary values** — Does every conditional handle the boundary case? Off-by-one in loops? Empty string / zero / null inputs?
3. **Variable state** — Is every variable initialized before use? Could any variable be stale from a prior iteration or branch? Are `readonly` / `export` / `unset` correct?
4. **Error paths** — Does every function that can fail have its failure handled? Are early returns / exit codes correct?
5. **Integration assumptions** — If calling another function, does the caller match the callee's actual signature and return behavior?

If any item reveals an issue, fix it before committing.

### Deep Review

Invoke the code-reviewer subagent after completing a major feature or complex change, before opening a PR. Trigger when: the change spans 3+ functions, modifies control flow or error handling, or touches integration points between modules.

The subagent reviews against this rubric:

**Conditional logic:**
- Trace each branch — can dead branches exist? Can two branches both execute when only one should?
- Check negation logic — are `!` / `not` / `-z` / `-n` inverted correctly?
- Verify grouping — are compound conditions grouped explicitly rather than relying on precedence?

**State and data flow:**
- Trace each variable from assignment to use — can it be modified between those points?
- Check for stale state across loop iterations, function calls, or conditional branches
- Verify scope — are variables local when they should be? Could a global leak into a function?

**Integration mismatches:**
- For every function call, verify: argument count, argument types/meaning, return value semantics, side effects
- Check that mock behavior in tests matches real behavior of the mocked component
- Verify that changes to a function's contract are reflected in all callers

**Edge cases and boundaries:**
- Empty collections, zero-length strings, single-element vs multi-element
- First and last iteration of loops
- Numeric boundaries: 0, 1, -1, MAX, MIN
- Permission/existence checks before file operations

**Error propagation:**
- Trace what happens when each function in the call chain fails
- Verify error messages are accurate (do they name the right function/variable?)
- Check that partial failures don't leave state half-modified

The subagent reports findings as a list of issues with file, line, category, and suggested fix. No issues found = explicit "clean" result.

```

- [ ] **Step 2: Verify the edit reads correctly**

Read `~/.claude/CLAUDE.md` and confirm the new "Logic Review" section appears between "Linting" and "GitHub Actions / CI", with both "Pre-Commit Checklist" and "Deep Review" subsections.

- [ ] **Step 3: Commit**

```bash
git add ~/.claude/CLAUDE.md
git commit -m "docs: add Logic Review section to global CLAUDE.md"
```

---

## Task 3: Add cross-reference in Committing Work section

**Files:**
- Modify: `~/.claude/CLAUDE.md:10-24` (Committing Work section)

- [ ] **Step 1: Add logic review reference**

Find this line in the "Committing Work" section of `~/.claude/CLAUDE.md`:

```markdown
Common types: `feat`, `fix`, `docs`, `ci`, `refactor`, `test`, `chore`.
```

Insert the following immediately after that line:

```markdown

Before committing, run the pre-commit logic review checklist (see "Logic Review" section) against staged changes.
```

- [ ] **Step 2: Verify the edit reads correctly**

Read `~/.claude/CLAUDE.md` from the Committing Work section and confirm the new line appears after the commit types and before the Memory section.

- [ ] **Step 3: Commit**

```bash
git add ~/.claude/CLAUDE.md
git commit -m "docs: add pre-commit logic review reference to Committing Work section"
```

---

## Task 4: Update superpowers index

**Files:**
- Modify: `docs/superpowers/README.md`

- [ ] **Step 1: Add plan entry**

Add a new row to the All Plans table in `docs/superpowers/README.md`:

```markdown
| 2026-04-10 | [logic-review-process](plans/2026-04-10-logic-review-process.md) | [spec](specs/2026-04-10-logic-review-process-design.md) | Done |
```

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/README.md
git commit -m "docs: add logic-review-process to superpowers index"
```
