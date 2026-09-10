# Skip `.claude/rules` in the ai-config symlink loop — Implementation Plan

> **Status: DONE** — merged in #261 (`f57c1b36`), 2026-09-10.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop `setup_dotfile_symlinks` from linking `ai-config/.claude/rules/` into `~/.claude/rules`, where it would load as user-level Claude Code rules in every repo.

**Architecture:** `lib/helpers.sh:874-879` loops over every item in `${_ai_config_dir}/.claude/` and `safe_link`s it into `~/.claude/`, skipping only `projects`. Add `rules` to that skip, pin it with a bats test beside the existing `projects` test, and correct the `CLAUDE.md` bullet that describes the loop.

**Tech Stack:** bash, bats-core, shellcheck.

**Spec:** ai-config `docs/superpowers/specs/2026-09-10-claude-md-rearchitecture-design.md` at `c9641926`, section 1 "Prerequisite for the edit-time class". This change must merge before ai-config's content step creates any `.claude/rules/` file.

## Global Constraints

- Work only in `/Users/bruce/git-repos/personal/dotfiles-worktrees/fix-claude-rules-symlink-skip` on branch `fix/claude-rules-symlink-skip`. Never `cd` to the main checkout.
- `lib/helpers.sh` and `tests/setup_env/install_guards.bats` are code: branch, PR, full Phase 3.
- `dotfiles` `make test` runs about 10 minutes, above the 600s Bash tool cap. Task gates are scoped; the orchestrator runs `make test` once after Task 2, in the background with a completion monitor.
- Shell style per `~/.claude/standards/shell.md`: `[[ ]]`, `${VAR}`, a `# why` comment only where the skip is not self-evident.
- Never run `setup_env.sh` unmocked. Tests use `_OVERRIDE_AI_CONFIG_DIR` and a `BATS_TEST_TMPDIR` `HOME`, as the neighbouring tests do.

## Session-level verification

1. `bats --filter 'does not symlink .claude/rules' tests/setup_env/install_guards.bats` prints `ok 1`, and fails when the skip line is removed (mutation, run by the implementer and reported).
2. The existing `setup_dotfile_symlinks creates .claude symlinks from AI_CONFIG_DIR` and `symlinks .claude/projects to ai-config (not via loop)` tests still pass.
3. `make test` exits 0 once, after Task 2.
4. `make lint` exits 0.

---

### Task 1: Skip `rules` in the `.claude` symlink loop, test first

```yaml-task
id: 1
description: Add a failing bats test that .claude/rules is not symlinked, then skip rules in setup_dotfile_symlinks' loop
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: bats --filter 'does not symlink .claude/rules' tests/setup_env/install_guards.bats
    exit_code: 0
    stdout_match: '^ok 1 '
  - cmd: bats --filter 'setup_dotfile_symlinks' tests/setup_env/install_guards.bats
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched:
  - tests/setup_env/install_guards.bats
  - lib/helpers.sh
depends_on: []
```

**Files:** `tests/setup_env/install_guards.bats` (new test directly after `@test "setup_dotfile_symlinks symlinks .claude/projects to ai-config (not via loop)"`), `lib/helpers.sh` (the loop at `:874-879`).

- [ ] **Write the failing test.** Add:

```bash
@test "setup_dotfile_symlinks does not symlink .claude/rules (would load as user-level rules in every repo)" {
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  export _OVERRIDE_AI_CONFIG_DIR="${BATS_TEST_TMPDIR}/ai-config"
  mkdir -p "${_OVERRIDE_AI_CONFIG_DIR}/.claude/rules"
  touch "${_OVERRIDE_AI_CONFIG_DIR}/.claude/rules/example.md"
  touch "${_OVERRIDE_AI_CONFIG_DIR}/.claude/CLAUDE.md"
  local _home="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${_home}"
  export HOME="${_home}"

  run setup_dotfile_symlinks
  [ "${status}" -eq 0 ]
  # Positive control: the loop ran and linked a sibling item.
  [ -L "${_home}/.claude/CLAUDE.md" ]
  # The rules directory must not exist in ~/.claude in any form.
  [ ! -L "${_home}/.claude/rules" ]
  [ ! -e "${_home}/.claude/rules" ]
}
```

- [ ] **Run it and confirm it fails for the right reason:** `bats --filter 'does not symlink .claude/rules' tests/setup_env/install_guards.bats` must print `not ok 1`, failing on the `[ ! -L ... ]` line (not on setup).
- [ ] **Implement.** In `lib/helpers.sh`, directly after `[[ "$(basename "${_claude_item}")" == "projects" ]] && continue`, add:

```bash
    # rules/ would load as user-level Claude Code rules in every repo;
    # ai-config's .claude/rules is project-scoped to ai-config only.
    [[ "$(basename "${_claude_item}")" == "rules" ]] && continue
```

- [ ] **Run the test; it prints `ok 1`.** Run every `setup_dotfile_symlinks` test; all pass.
- [ ] **Mutation check.** Delete the new `rules` line, re-run the filtered test, confirm `not ok 1`, restore the line, confirm `ok 1`. Report both outputs.
- [ ] `make lint` exits 0.
- [ ] **Commit** via `caveman:caveman-commit`, both files by exact path.

**Interfaces:**

- Consumes: `setup_dotfile_symlinks`, `safe_link`, `_OVERRIDE_AI_CONFIG_DIR` seam.
- Produces: `~/.claude/` never contains an entry for `ai-config/.claude/rules`.

---

### Task 2: Document the skip and backlog the dangling link

```yaml-task
id: 2
description: Docs-only — correct CLAUDE.md's .claude symlink bullet to name the rules skip and add a backlog row for the dangling ~/.claude/rules link; no behaviour change, so TDD does not apply
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: grep -qF 'each item (except `projects/` and `rules/`)' CLAUDE.md
    exit_code: 0
  - cmd: grep -qF '`~/.claude/rules` is a dangling symlink' docs/superpowers/README.md
    exit_code: 0
  - cmd: grep -qF '2026-09-10-claude-rules-symlink-skip.md' docs/superpowers/README.md
    exit_code: 0
max_retries: 3
files_touched:
  - CLAUDE.md
  - docs/superpowers/README.md
depends_on: [1]
```

**Files:** `CLAUDE.md` (Symlink Strategy, the `.claude/` bullet at `:101`), `docs/superpowers/README.md` (All Plans table and Backlog table).

- [ ] In `CLAUDE.md`, change `each item (except `projects/`)` to `each item (except `projects/`and`rules/`)`, and append one sentence to that bullet: `rules/ is skipped because a linked ~/.claude/rules would load ai-config's path-scoped rules as user-level rules in every repo.`
- [ ] **Edit `docs/superpowers/README.md` with a script, not the Edit tool** — the PostToolUse formatter reflows the whole All Plans table on any `Edit` (recorded in the Backlog). Use `python3` to insert, keeping every other line byte-identical:
  - an All Plans row after the last dated row: `| 2026-09-10 | [claude rules symlink skip](plans/2026-09-10-claude-rules-symlink-skip.md) | ai-config spec 2026-09-10-claude-md-rearchitecture | In Progress |`
  - a Backlog row: `| `~/.claude/rules`is a dangling symlink | On the Mac Studio it points at`dotfiles/.claude/rules`, which dotfiles does not track and which does not exist. Harmless today; any future `dotfiles/.claude/rules` would silently load as user-level rules. Remove the link or decide its owner. Found 2026-09-10. |`
- [ ] `git diff --numstat docs/superpowers/README.md` shows exactly 2 insertions and 0 deletions.
- [ ] **Commit** via `caveman:caveman-commit`.

**Interfaces:**

- Consumes: Task 1's behaviour.
- Produces: documentation matching the loop.

---

**After Task 2 (orchestrator):** run `make test` once in the worktree, backgrounded with a monitor (suite exceeds the 600s cap); then `finishing-a-development-branch`.
