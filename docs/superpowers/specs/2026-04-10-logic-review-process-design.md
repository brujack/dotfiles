# Design: Comprehensive Logic Review Process

**Date:** 2026-04-10
**Status:** Accepted

## Context

The current development workflow has linting (syntax/style), TDD (behavioral correctness for tested paths), and mocking (isolation of side effects). None of these systematically catch logic errors: wrong operators, stale variables, integration mismatches, missing edge cases, or broken error propagation. These bugs survive because they require reasoning about the code's intent, not just its syntax or test coverage.

A logic review process fills this gap at two levels: a lightweight pre-commit check and a thorough on-demand review.

## Decision

Add three things to `~/.claude/CLAUDE.md`:

1. A **pre-commit logic review checklist** run inline before every commit
2. A **deep logic review** via the code-reviewer subagent, invoked after major features before opening a PR
3. **Enhanced TDD requirements** mandating boundary, error path, and state transition tests

## 1. Pre-Commit Logic Review

A lightweight checklist run against staged changes before every commit. Not a separate tool — Claude reads the diff and checks each item inline:

1. **Conditional logic** — Are all operators correct (`&&`/`||`, `-eq`/`-ne`, `==`/`!=`)? Is grouping precedence explicit (no reliance on implicit `||`/`&&` precedence)?
2. **Boundary values** — Does every conditional handle the boundary case? Off-by-one in loops? Empty string / zero / null inputs?
3. **Variable state** — Is every variable initialized before use? Could any variable be stale from a prior iteration or branch? Are `readonly` / `export` / `unset` correct?
4. **Error paths** — Does every function that can fail have its failure handled? Are early returns / exit codes correct?
5. **Integration assumptions** — If calling another function, does the caller match the callee's actual signature and return behavior?

If any item reveals an issue, fix it before committing. This adds seconds, not minutes.

### Placement in CLAUDE.md

Add one line to the existing "Committing Work" section referencing the checklist. The checklist itself lives in a new "Logic Review" section placed after "Linting" and before "GitHub Actions / CI".

## 2. Deep Logic Review

Invoked explicitly after completing a major feature or complex change, before opening a PR. Trigger when: the change spans 3+ functions, modifies control flow or error handling, or touches integration points between modules. Uses the code-reviewer subagent with a structured rubric:

**Conditional logic:**
- Trace each branch — can dead branches exist? Can two branches both execute when only one should?
- Check negation logic — are `!` / `not` / `-z` / `-n` inverted correctly?
- Verify grouping — are compound conditions grouped explicitly with `{ }` or `( )` rather than relying on precedence?

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

### Placement in CLAUDE.md

Described in the same "Logic Review" section, under a "Deep Review" subsection.

## 3. Enhanced TDD Requirements

Extends the existing TDD section with three mandatory test categories beyond the happy path:

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

These are additions to existing tests for each function, not separate test files. A test that only covers the happy path is incomplete.

### Placement in CLAUDE.md

Added as a subsection within the existing "Test-Driven Development" section, after the TDD cycle steps and before the "never write implementation before the test" rule.

## Consequences

**Positive:**
- Logic errors caught before they reach commits (pre-commit) or PRs (deep review)
- Enhanced TDD requirements prevent the most common class of undertested code
- Both levels are language-agnostic — same process for bash, Python, Rust, PowerShell
- Pre-commit checklist has near-zero overhead

**Negative:**
- Deep review costs tokens and time (mitigated by being on-demand, not automatic)
- Enhanced TDD requirements increase test volume per function
- Pre-commit checklist relies on Claude's discipline to run it

## Related

- Existing TDD section in `~/.claude/CLAUDE.md`
- Existing Linting section in `~/.claude/CLAUDE.md`
- `code-reviewer` subagent (superpowers plugin)
