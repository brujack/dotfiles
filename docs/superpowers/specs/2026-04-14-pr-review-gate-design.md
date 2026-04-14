# PR Review Gate — Design Spec

**Date:** 2026-04-14
**Status:** Accepted

## Context

The `pr-review` skill performs a structured pre-push code review (correctness,
security, test coverage, IaC safety) and emits a **PASS / HOLD** verdict. It
exists as a slash command and a local skill, but is not yet wired into the
development workflow. Currently `finishing-a-development-branch` Option 2
pushes and creates a PR without any code review gate.

## Decision

Insert the `pr-review` skill as a mandatory gate inside `finishing-a-development-branch`
**Option 2 (Push and Create PR)**, between test verification and the push. A
matching rule in `~/.claude/CLAUDE.md` acts as a durable backup that survives
plugin updates.

The gate does **not** apply to:

- Direct master commits (docs, memory, README fixes — per existing exception)
- Option 1 (local merge), Option 3 (keep as-is), Option 4 (discard)
- Any workflow other than `finishing-a-development-branch`

## Modified Option 2 Flow

```
Option 2: Push and Create PR
  1. (existing) Run test suite — abort if failing
  2. NEW: Invoke pr-review skill
       ├── PASS  → proceed to step 3
       └── HOLD  → enter fix loop:
             a. Display all CRITICAL findings
             b. Fix each CRITICAL item
             c. Run make test — confirm no regressions introduced
             d. Commit the fixes
             e. Re-invoke pr-review
             f. If same CRITICAL finding persists after 2 fix attempts,
                escalate to user — do not loop indefinitely
  3. (existing) git push -u origin <branch>
  4. (existing) gh pr create ...
```

WARNING and INFO findings from pr-review are advisory — they are surfaced in
the report but do not block the push.

## Skill File Change

**File:** `~/.claude/plugins/cache/claude-plugins-official/superpowers/<version>/skills/finishing-a-development-branch/SKILL.md`

Insert after the existing "If tests pass: Continue to Step 3" block in Step 1,
before Step 3 (Present Options):

```markdown
### Step 2b: PR Review Gate (Option 2 only — run before pushing)

When the user selects Option 2, run the pr-review skill before pushing:

1. Invoke pr-review skill
2. If verdict is PASS: proceed to push + PR creation
3. If verdict is HOLD:
   - Show CRITICAL findings
   - Fix each CRITICAL item
   - Run tests: confirm no regressions
   - Commit fixes
   - Re-run pr-review
   - Repeat until PASS
   - If the same CRITICAL finding persists after 2 fix attempts: stop,
     present findings to user, ask how to proceed
```

## CLAUDE.md Addition

Added to the `Feature Branches` section of `~/.claude/CLAUDE.md`:

```markdown
### PR Review Gate

Before pushing any feature branch (Option 2 in finishing-a-development-branch),
run the pr-review skill. Only push when verdict is PASS. If HOLD:

1. Fix all CRITICAL findings
2. Run make test — confirm no regressions
3. Commit the fixes
4. Re-run pr-review
5. Repeat until PASS, or escalate to user after two failed fix attempts

WARNING and INFO findings are advisory — surface them but do not block the push.
```

This rule acts as a durable backup: if `claude plugins update superpowers`
overwrites the skill file, CLAUDE.md still enforces the gate.

## Position in the Superpowers Hierarchy

```
Development     → superpowers:test-driven-development (per-function TDD)
                  superpowers:systematic-debugging (bug fixes)

Pre-completion  → superpowers:verification-before-completion (tests/build pass)

Pre-push gate   → pr-review (cross-cutting: security, correctness, coverage)
                  ↑ NEW — wired into finishing-a-development-branch Option 2

Integration     → finishing-a-development-branch (push + PR creation)
```

## Consequences

- Every feature branch push now goes through a structured code review before
  leaving the local machine
- HOLD verdicts are resolved automatically where possible; user is only
  interrupted after two failed fix attempts
- The gate is transparent: the skill file shows it explicitly, CLAUDE.md
  reinforces it
- Plugin updates may overwrite the skill file; CLAUDE.md rule persists. After
  any `claude plugins update superpowers`, re-apply the skill file change as
  part of the update workflow

## Implementation Scope

1. Modify `finishing-a-development-branch/SKILL.md` (plugin cache)
2. Add PR Review Gate section to `~/.claude/CLAUDE.md`
3. Update `docs/superpowers/README.md` plan index
