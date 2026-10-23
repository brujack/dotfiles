# Retire sync-agent-guidance

- **Date:** 2026-10-23
- **Backlog rows closed:** "sync-agent-guidance with zero standards imports" (P2 bugs and security) and "`check-agent-guidance` cannot pass in a worktree" (P2 CI).

## Problem

`scripts/sync-agent-guidance.sh` builds `.cursor/rules/global-claude-standards.mdc` from the `@~/.claude/standards/*.md` imports in root `CLAUDE.md`. Since the CLAUDE.md budget change (ADR-0047, spec `2026-10-17-claude-md-budget-design.md`, R5 amendment) `CLAUDE.md` has no such import, so the tool has no input:

- `git grep -c '^@' CLAUDE.md` on master (1f02084d) prints nothing: zero imports.
- `make sync-agent-guidance` exits 1 with `No standards imports found`.
- The main checkout's `.cursor/rules/global-claude-standards.mdc` (gitignored, untracked) was last written 2026-08-08 and still holds `CLAUDE.md` plus `powershell.md` as they were then. Measured on `claude` only; the other checkouts were not inspected.
- No gate runs either target: `git grep -n agent-guidance -- Makefile scripts/pre-commit scripts/pre-push .github/workflows` hits only the two target definitions, `.PHONY` and the help lines (measured on master, 1f02084d).

The output it would produce is already supplied elsewhere. `~/.cursor/rules` on `claude` is a symlink to `ai-config/.cursor/rules`, whose `global-claude-standards.mdc` (55,817 bytes) ai-config regenerates from the global standards; its last commit is `e7297d97`, 2026-10-23. Cursor therefore gets the global standards in every repo from ai-config, and the dotfiles project-level copy only adds a stale duplicate.

## Design

Delete the tool and every live reference to it.

1. Delete `scripts/sync-agent-guidance.sh` and `tests/scripts/sync_agent_guidance.bats` (17 tests).
2. In `Makefile`, delete the `sync-agent-guidance` and `check-agent-guidance` targets, their two `.PHONY` entries and their two `help` lines.
3. Delete the two `README.md` lines (`make sync-agent-guidance`, `make check-agent-guidance`) and the two `CLAUDE.md` Testing lines (**Sync agent guidance**, **Check agent guidance drift**).
4. In `scripts/sync-requirements-ci.sh`, delete the sentence "Same shape as sync-agent-guidance.sh." from the header comment.
5. In `tests/scripts/docs_inert_premise.bats`, reword the FAIL hint "check-agent-guidance is the known reader (it reads CLAUDE.md), so it must not be a prerequisite." so it names no deleted target. The guard and its logic are unchanged. Fixture Makefiles in that file that use the string `check-agent-guidance` as a target name stay: they are self-contained test data.

Left as they are, because they are dated records of the tree they describe: `docs/adr/0017-pre-push-trigger-fail-closed.md`, dated specs and plans, `docs/knowledge/retrospectives/2026-07-retrospective.md`, and the two `tests/scripts/unit.bats` comments explaining why the coverage heuristic excludes heredoc bodies.

The gitignored `.cursor/rules/global-claude-standards.mdc` in each checkout is not tracked, so no commit can remove it. The PR body gives the manual step `rm -f .cursor/rules/global-claude-standards.mdc`, run per checkout by the operator.

## Testing

The change removes behaviour and adds none, so there is no RED test. Evidence:

- `make test` passes, and its plan count is the master count minus 17.
- `make check-agent-guidance` exits 2 with `No rule to make target`.
- `git grep` for both target names hits only the files listed as left above and the fixture strings in `docs_inert_premise.bats`.
- The CI `bash-coverage` job stays at or above the 91% floor. `scripts/sync-agent-guidance.sh` is in the instrumented set with 43 coverable lines (`run-bash-coverage.sh --count-coverable`); removing well-covered lines lowers the ratio, so this is the one figure that can fail.

## Requirements

- **R1.** `[PR1]` `scripts/sync-agent-guidance.sh` and `tests/scripts/sync_agent_guidance.bats` are deleted.
- **R2.** `[PR1]` `Makefile` has no `sync-agent-guidance` or `check-agent-guidance` target, `.PHONY` entry or help line.
- **R3.** `[PR1]` `README.md` and `CLAUDE.md` contain neither `sync-agent-guidance` nor `check-agent-guidance`.
- **R4.** `[PR1]` `scripts/sync-requirements-ci.sh` does not mention `sync-agent-guidance.sh`.
- **R5.** `[PR1]` The FAIL hint in `tests/scripts/docs_inert_premise.bats` names no deleted target; the prerequisite guard's logic and every existing test in that file are unchanged.
- **V1.** `make test` on the branch passes with a plan count equal to master's minus 17.
- **V2.** `make check-agent-guidance` on the branch exits 2 with `No rule to make target`.
- **V3.** CI `bash-coverage` on the PR reads at least 91%.
- **V4.** Post-merge on master, both backlog rows are removed and the plan index carries a Done row.
- **N1.** No edit to dated records: `docs/adr/`, dated files under `docs/superpowers/specs/` or `docs/superpowers/plans/` other than this spec and its plan, `docs/knowledge/retrospectives/`, or the two `tests/scripts/unit.bats` heredoc comments.
- **N2.** No code that deletes the gitignored `.cursor/rules/global-claude-standards.mdc` on any machine.
- **N3.** No change to ai-config or its Cursor mirror.
