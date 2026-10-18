# CLAUDE.md Budget Implementation Plan

spec: docs/superpowers/specs/2026-10-17-claude-md-budget-design.md

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cut dotfiles `CLAUDE.md` from 155,308 bytes to at most 105,000 with one line per rule, and stop regrowth with a hard ceiling checked at push and in CI.

**Architecture:** Two worktrees. `../dotfiles-budget` (branch `feat/claude-md-budget`) holds the checker, hook, tests, ADR and the compressed `CLAUDE.md`. `../ai-config-dkb` (branch `docs/dotfiles-claude-md-knowledge`) receives the verbatim detail as `docs/knowledge/dotfiles-*.md` sections; it is pushed to ai-config master before the dotfiles PR opens. A scratch checker gates each compression task and is never committed.

**Tech Stack:** python3 (unittest), bats, GNU make, `scripts/relocation_check.py`.

## Global Constraints

- Base: `b4b60c28846550d6e052a24c516b71122bbe00ec` (dotfiles master after dotfiles#346; `CLAUDE.md` 155,308 bytes).
- Ceiling: 105,000 bytes. `claude_md_budget.py` exits 1 over, 0 within, 0 when the tree has no `CLAUDE.md`, 2 on git failure. No trailer, flag or environment override (N4).
- Rule unit: a list item, table row, or paragraph stating one instruction. Pure detail goes pointer-only under one shared pointer line. A live-state seam rule keeps its variable name and safe override (R4).
- Pointer: `` → `dotfiles-<topic>.md` § `<heading>` ``; every pointer resolves to exactly one `### <heading>` in `../ai-config-dkb/docs/knowledge/`.
- A base block of at most 300 characters stays byte-identical. Every changed block's full text is copied byte-for-byte into a knowledge section.
- Checker: `C=/tmp/claude-1000/-home-bruce-git-repos-personal-ai-config/679cf0fc-4125-445f-ba6c-e91a2c2ada7a/scratchpad/budget_check.py`, run from `../dotfiles-budget` as `python3 "$C" --base b4b60c28846550d6e052a24c516b71122bbe00ec --kdir ../ai-config-dkb/docs/knowledge ...`. Proven on the base: exit 1 (`scope did not shrink`) for every scope; on a mutation it reports an unrelocated block and an unresolved pointer.
- Each compression task appends `MOVE | <block's first 60 chars> | <file> | <heading>` lines to `docs/superpowers/plans/2026-10-18-relocation-map.md` (fenced ```` ```relocation-map ````) for V1.
- `make test` reads no working-tree `CLAUDE.md` (`tests/scripts/docs_inert_premise.bats`), so compression tasks gate on the checker and `make lint`; the orchestrator runs `make test` after Tasks 2 and 6 (about 104 s).
- N5 file list is binding; N2: no ai-config script changes.

## Verification Planning

- Whole change: `python3 scripts/claude_md_budget.py HEAD` exits 0; `wc -c CLAUDE.md` at most 105,000; `python3 "$C" ... --all` exits 0; `python3 scripts/relocation_check.py check --pre-rev <base> --post CLAUDE.md --dest ../ai-config-dkb/docs/knowledge --map docs/superpowers/plans/2026-10-18-relocation-map.md --rules-mode bullets --min-relocated 40000 --slack 8000` exits 0 (V1); `make test` exits 0; a `CLAUDE.md`-only push with the file over the ceiling is refused by the hook.
- After merge: `/context` in the dotfiles main checkout shows `CLAUDE.md` at 42k tokens or less (V3).
- Edge cases: 105,000 vs 105,001 bytes; no `CLAUDE.md`; unresolvable revision; two-ref push; pushed checker differs from the working tree's.

---

### Task 1: Budget checker

```yaml-task
id: 1
description: Add scripts/claude_md_budget.py with its unittest suite
model: sonnet
tdd: required
requirements: [R6]
acceptance:
  - cmd: python3 -m unittest tests.test_claude_md_budget -v
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched: [scripts/claude_md_budget.py, tests/test_claude_md_budget.py]
depends_on: []
```

`claude_md_budget.py <rev>`: run `git ls-tree <rev> -- CLAUDE.md` in the inherited environment, so a hook run from a worktree push resolves the pushed repo. Non-zero exit: print the git error, exit 2. Empty listing: exit 0. Else `git show <rev>:CLAUDE.md`; failure exits 2. Over 105,000 bytes: print `CLAUDE.md is <n> bytes, ceiling 105000` to stderr, exit 1. Else exit 0. Constant `CEILING = 105_000` with a comment pointing at the new ADR. Tests build a temp git repo per case: 105,000 allowed, 105,001 refused with both numbers in stderr, no `CLAUDE.md` allowed, an unknown revision exits 2, a multibyte file measured in bytes not characters.

### Task 2: Hook and make wiring

```yaml-task
id: 2
description: Run the checker from scripts/pre-push and make test, and record the reader in docs_inert_premise
model: sonnet
tdd: required
requirements: [R7, R8, R9]
acceptance:
  - cmd: bats --jobs 24 tests/scripts/pre_push.bats tests/scripts/docs_inert_premise.bats < /dev/null
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched: [scripts/pre-push, tests/scripts/pre_push.bats, Makefile, tests/scripts/docs_inert_premise.bats]
depends_on: [1]
```

In `scripts/pre-push`, inside the existing ref loop and before the `needs_test` early exit: for each ref with a non-zero local SHA, run `git ls-tree "${local_sha}" -- scripts/claude_md_budget.py`; non-zero exit sets the refuse flag; empty output skips; else `git show "${local_sha}:scripts/claude_md_budget.py" | python3 -I - "${local_sha}"` and set the flag on any non-zero exit (including `git show` failure). Act on the flag after the loop drains stdin. Makefile: target `check-claude-md-budget` running `python3 scripts/claude_md_budget.py HEAD`, added to `test:`'s prerequisites; in `docs_inert_premise.bats` add it to `ALLOWED_TEST_PREREQS` with a comment that it reads `CLAUDE.md` only via `git show` and the docs push path runs it in the hook. New bats cases: over-ceiling `CLAUDE.md`-only push refused; compliant push allowed; pushed commit without the script skipped; `git show` failure on a listed path refused; working-tree checker differs from the pushed one (pushed decides); two-ref push with the first over the ceiling refused. Existing cases must pass unchanged. Orchestrator runs `make test` after this task.

### Task 3: Compress Test Seams

```yaml-task
id: 3
description: Compress the Test Seams subsection to one line per rule and copy its blocks verbatim to knowledge (prose relocation, so TDD does not apply)
model: sonnet
tdd: not-applicable
requirements: [R2, R3, R4, R10]
acceptance:
  - cmd: 'python3 /tmp/claude-1000/-home-bruce-git-repos-personal-ai-config/679cf0fc-4125-445f-ba6c-e91a2c2ada7a/scratchpad/budget_check.py --base b4b60c28846550d6e052a24c516b71122bbe00ec --kdir ../ai-config-dkb/docs/knowledge --scope "### Test Seams"'
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 2
files_touched: [CLAUDE.md, docs/superpowers/plans/2026-10-18-relocation-map.md, ../ai-config-dkb/docs/knowledge/dotfiles-test-seams.md]
depends_on: [2]
```

Add new `###` sections to `dotfiles-test-seams.md` (keep its frontmatter; never rewrite existing sections). The seam table moves whole. Add the seam-routing rule (R10) as the subsection's first line.

### Task 4: Compress the rest of Testing

```yaml-task
id: 4
description: Compress the Testing section except Test Seams, copying blocks verbatim to knowledge (prose relocation, so TDD does not apply)
model: sonnet
tdd: not-applicable
requirements: [R2, R3, R4]
acceptance:
  - cmd: 'python3 /tmp/claude-1000/-home-bruce-git-repos-personal-ai-config/679cf0fc-4125-445f-ba6c-e91a2c2ada7a/scratchpad/budget_check.py --base b4b60c28846550d6e052a24c516b71122bbe00ec --kdir ../ai-config-dkb/docs/knowledge --scope "## Testing" --exclude "### Test Seams"'
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 2
files_touched: [CLAUDE.md, docs/superpowers/plans/2026-10-18-relocation-map.md, ../ai-config-dkb/docs/knowledge/dotfiles-bats-test-infrastructure.md, ../ai-config-dkb/docs/knowledge/dotfiles-bash-coverage.md]
depends_on: [3]
```

### Task 5: Compress conventions, entry points and code standards

```yaml-task
id: 5
description: Compress Key Conventions, Entry Points, Code Standards and Language Standards, and swap the powershell.md import (prose relocation, so TDD does not apply)
model: sonnet
tdd: not-applicable
requirements: [R2, R3, R4, R5]
acceptance:
  - cmd: 'python3 /tmp/claude-1000/-home-bruce-git-repos-personal-ai-config/679cf0fc-4125-445f-ba6c-e91a2c2ada7a/scratchpad/budget_check.py --base b4b60c28846550d6e052a24c516b71122bbe00ec --kdir ../ai-config-dkb/docs/knowledge --scope "## Key Conventions" --scope "## Entry Points" --scope "## Code Standards" --scope "## Language Standards"'
    exit_code: 0
  - cmd: 'bash -c "! command grep -q \"^@~/.claude/standards/powershell.md\" CLAUDE.md"'
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 2
files_touched: [CLAUDE.md, docs/superpowers/plans/2026-10-18-relocation-map.md, ../ai-config-dkb/docs/knowledge/dotfiles-conventions.md]
depends_on: [4]
```

Replace the line `@~/.claude/standards/powershell.md` with exactly: ``Read `~/.claude/standards/powershell.md` before writing or changing PowerShell code or its lint and test configuration; it is not loaded at session start.`` The standard itself is unchanged and stays in ai-config.

### Task 6: Compress the remaining sections

```yaml-task
id: 6
description: Compress every remaining section and bring the file under the ceiling (prose relocation, so TDD does not apply)
model: sonnet
tdd: not-applicable
requirements: [R1, R2, R3, R4]
acceptance:
  - cmd: 'python3 /tmp/claude-1000/-home-bruce-git-repos-personal-ai-config/679cf0fc-4125-445f-ba6c-e91a2c2ada7a/scratchpad/budget_check.py --base b4b60c28846550d6e052a24c516b71122bbe00ec --kdir ../ai-config-dkb/docs/knowledge --all'
    exit_code: 0
  - cmd: 'test "$(wc -c < CLAUDE.md)" -le 105000'
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 2
files_touched: [CLAUDE.md, docs/superpowers/plans/2026-10-18-relocation-map.md, ../ai-config-dkb/docs/knowledge/dotfiles-conventions.md]
depends_on: [5]
```

Sections: Repository Overview, Layout, 10-80-10 Execution Cycle, Knowledge Directory, Symlink Strategy, GitHub MCP, Committing Work, Dependency Automation, Local-Only State, Profile Model, Adding a New Machine. After committing, the orchestrator runs `python3 scripts/claude_md_budget.py HEAD` and `make test`.

### Task 7: ADR and mirror

```yaml-task
id: 7
description: Write the ADR, index it, and regenerate the Cursor mirror (docs and generated files, so TDD does not apply)
model: sonnet
tdd: not-applicable
requirements: [R5, R11]
acceptance:
  - cmd: 'grep -q "0047" docs/adr/README.md'
    exit_code: 0
  - cmd: 'grep -qE "105,?000" docs/adr/0047-claude-md-size-ceiling.md'
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 2
files_touched: [docs/adr/0047-claude-md-size-ceiling.md, docs/adr/README.md, .cursor/rules/global-claude-standards.mdc]
depends_on: [6]
```

ADR-0047: supersedes ADR-0036 decision 4; records the 105,000-byte ceiling, its derivation from the spec's two dry runs, no override, and that raising it needs an amendment to this ADR. Run `make sync-agent-guidance` with `_OVERRIDE_TARGET_PATH` pointing at the worktree's mirror.

## Orchestrator steps after Task 7

1. V2: dispatch an independent reviewer with the base and compressed `CLAUDE.md` and the knowledge sections; it records kept (a faithful one-line compression), pointer-only, weakened, missing or wrong per rule; fix every weakened, missing or wrong rule and re-review those rules until each is kept or pointer-only (N3).
2. V1 command from Verification Planning.
3. Push `../ai-config-dkb` content to ai-config master (docs-direct), verify each pointer resolves on `origin/master`.
4. Operator read (V5) of `CLAUDE.md` and the pointer-only list, then Phase 3, PR, merge, V3.

## Non-goal check

Reviewer output: `dnongoal.json` (fresh reviewer, 2026-10-18). N1, N2, N4, N5 CLEAR.

- **N3 UNCLEAR.** Quote: orchestrator step 1 "fix any missing or wrong" lets a weakened rule ship; Task 5 never named what replaces the import. Resolution: plan revised. Step 1 before: "fix any missing or wrong"; after: "fix every weakened, missing or wrong rule and re-review those rules until each is kept or pointer-only (N3)". Task 5 gained the exact replacement line.
