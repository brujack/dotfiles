# Retire sync-agent-guidance

- **Date:** 2026-10-23
- **Backlog rows closed:** "sync-agent-guidance with zero standards imports" (P2 bugs and security) and "`check-agent-guidance` cannot pass in a worktree" (P2 CI).

## Problem

`scripts/sync-agent-guidance.sh` builds `.cursor/rules/global-claude-standards.mdc` from the `@~/.claude/standards/*.md` imports in root `CLAUDE.md`. Since the CLAUDE.md budget change (ADR-0047, spec `2026-10-17-claude-md-budget-design.md`, R5 amendment) `CLAUDE.md` has no such import, so the tool has no input:

- `git grep -c '^@' CLAUDE.md` on master (1f02084d) prints nothing: zero imports.
- `make sync-agent-guidance` exits 1 with `No standards imports found`.
- The main checkout's `.cursor/rules/global-claude-standards.mdc` (gitignored, untracked) was last written 2026-08-08 and still holds `CLAUDE.md` plus `powershell.md` as they were then. Measured on `claude` only; the other checkouts were not inspected.
- No gate runs either target: `git grep -n agent-guidance -- Makefile scripts/pre-commit scripts/pre-push .github/workflows` hits only the two target definitions, `.PHONY` and the help lines (measured on master, 1f02084d).

The tool has no input, so it cannot be repaired by running it, and the copy it last wrote no longer matches `CLAUDE.md`. A stale copy is worse than none: a Cursor session opened in a dotfiles checkout reads guidance that is two months out of date.

This spec does not claim Cursor gets the same standards from elsewhere. `~/.cursor/rules` on `claude` is a symlink to `ai-config/.cursor/rules`, whose `global-claude-standards.mdc` ai-config regenerates (last commit `e7297d97`, 2026-10-23), but whether Cursor loads a home-directory `.cursor/rules` at all is unverified: Cursor is not installed on `claude` (`~/.config/Cursor/User` does not exist), and its documented rule sources are a project's `.cursor/rules/` and the Settings rules UI. The retirement does not depend on the answer.

## Design

Delete the tool and every live reference to it.

1. Delete `scripts/sync-agent-guidance.sh` and `tests/scripts/sync_agent_guidance.bats` (17 tests).
2. In `Makefile`, delete the `sync-agent-guidance` and `check-agent-guidance` targets, their two `.PHONY` entries and their two `help` lines.
3. Delete the two `README.md` lines (`make sync-agent-guidance`, `make check-agent-guidance`) and the two `CLAUDE.md` Testing lines (**Sync agent guidance**, **Check agent guidance drift**).
4. In `scripts/sync-requirements-ci.sh`, delete the sentence "Same shape as sync-agent-guidance.sh." from the header comment.
5. In `tests/scripts/docs_inert_premise.bats`, reword the FAIL hint "check-agent-guidance is the known reader (it reads CLAUDE.md), so it must not be a prerequisite." and the header comment's example "e.g. sync-agent-guidance.sh defaults" so neither names a deleted tool. The guard and its logic are unchanged. Fixture Makefiles in that file that use the string `check-agent-guidance` as a target name stay: they are self-contained test data.
6. In `docs/superpowers/README.md`, delete the two Backlog rows this spec closes, in the same PR.

After merge, the one live reference outside this repo is fixed through the ai-config session: the `scripts/` entry for `sync-agent-guidance.sh` in the Layout tree of `ai-config/docs/knowledge/dotfiles-conventions.md`, which dotfiles `CLAUDE.md`'s Layout rule points readers to.

Left as they are, because they are dated records of the tree they describe: `docs/adr/0017-pre-push-trigger-fail-closed.md`, dated specs and plans, `docs/knowledge/retrospectives/2026-07-retrospective.md`, and the two `tests/scripts/unit.bats` comments explaining why the coverage heuristic excludes heredoc bodies.

The gitignored `.cursor/rules/global-claude-standards.mdc` in each checkout is not tracked, so no commit can remove it. The PR body says it is stale since 2026-08-08 and now orphaned, and that removing it is optional cleanup (`rm -f .cursor/rules/global-claude-standards.mdc`): it is not a recommended step, because whether Cursor would then see any standards in dotfiles is the open question above.

## Testing

The change removes behaviour and adds none, so there is no RED test. Evidence:

- `make test` passes, and its plan count is the master count minus 17.
- `make check-agent-guidance` exits 2 with `No rule to make target`.
- `git grep` for both target names hits only the files listed as left above, this spec and its plan, and the fixture strings in `docs_inert_premise.bats`.
- The CI `bash-coverage` job stays at or above the 91% floor. This is a sanity check, not evidence of the deletion: in CI run 39975729257 (dotfiles#366) the script measured 38/43 (88%) against a total of 6092/6667 (91.37%), so removing it raises the total to about 91.39%.

## Requirements

- **R1.** `[PR1]` `scripts/sync-agent-guidance.sh` and `tests/scripts/sync_agent_guidance.bats` are deleted.
- **R2.** `[PR1]` `Makefile` has no `sync-agent-guidance` or `check-agent-guidance` target, `.PHONY` entry or help line.
- **R3.** `[PR1]` `README.md` and `CLAUDE.md` contain neither `sync-agent-guidance` nor `check-agent-guidance`.
- **R4.** `[PR1]` `scripts/sync-requirements-ci.sh` does not mention `sync-agent-guidance.sh`.
- **R5.** `[PR1]` Neither the FAIL hint nor the header comment in `tests/scripts/docs_inert_premise.bats` names `sync-agent-guidance.sh` or describes `check-agent-guidance` as an existing target; the prerequisite guard's logic and every existing test in that file are unchanged.
- **R6.** `[PR1]` `docs/superpowers/README.md` no longer has the Backlog rows "sync-agent-guidance with zero standards imports" and "`check-agent-guidance` cannot pass in a worktree".
- **V1.** `make test` on the branch passes with a plan count equal to master's minus 17.
- **V2.** `make check-agent-guidance` on the branch exits 2 with `No rule to make target`.
- **V3.** CI `bash-coverage` on the PR reads at least 91% (sanity check; the deletion raises the ratio).
- **V4.** Post-merge on master, the plan index carries a Done row for this plan.
- **V5.** Post-merge, the Layout tree in `ai-config/docs/knowledge/dotfiles-conventions.md` no longer lists `sync-agent-guidance.sh`.
- **N1.** No edit to dated records: `docs/adr/`, dated files under `docs/superpowers/specs/` or `docs/superpowers/plans/` other than this spec and its plan, `docs/knowledge/retrospectives/`, or the two `tests/scripts/unit.bats` heredoc comments.
- **N2.** No code that deletes the gitignored `.cursor/rules/global-claude-standards.mdc` on any machine.
- **N3.** No change to ai-config or its Cursor mirror, except the one Layout-tree line V5 names.

## Multi-Lens Review

Reviewed at commit: `6df3ed56` (Step 7 self-review commit, before Step 8 dispatch)

### Goal-Fit

Finding: No blocking issue; deletion is the simplest path. Nothing outside dotfiles calls either dotfiles target or reads dotfiles' `.cursor/rules/` (every executable hit in the fleet is ai-config acting on its own target). Cursor is not installed on `claude`, so the "supplied elsewhere" sentence was never tested. Side note: `etch-config/.claude/settings.local.json:72` holds a dead permission entry for `./scripts/sync-agent-guidance.sh check`, harmless and out of scope.
Assumption: Cursor loads `~/.cursor/rules/*.mdc` as global rules. Settle it on a machine with Cursor: open a repo with no project rules and check the rules panel lists `global-claude-standards`. If false, the design holds but the Problem rationale must not claim the content is supplied elsewhere.
Disposition: Addressed — Problem section now rests on "no input, stale copy worse than none" and states the Cursor question as unverified.

### Ergonomics

Finding: `ai-config/docs/knowledge/dotfiles-conventions.md:270` (the Layout tree dotfiles `CLAUDE.md` points to) still lists `sync-agent-guidance.sh`, and N3 blocked fixing it. No ai-config skill or standard tells anyone to run either target in dotfiles.
Assumption: same Cursor global-rules question as Goal-Fit; if false, the per-checkout `rm` removes the only (stale) standards Cursor sees in dotfiles.
Disposition: Addressed — N3 carves out that one line, fixed post-merge via the ai-config session (V5); the `rm` is now optional cleanup, not a recommended step.

### Risk

Finding: (1) V3 was framed backwards: the script measured 38/43 (88%) against 91.37% in CI run 39975729257, so deleting it raises coverage and V3 passes on a no-op. (2) The spec's own `git grep` check would fail: `tests/scripts/docs_inert_premise.bats:35` (a comment) and the two Backlog rows in `docs/superpowers/README.md` were in neither list. Test-count floor, ci-suite-report, `makefile_lint_scope.bats`, the CLAUDE.md budget and phrase/relocation manifests are unaffected.
Assumption: same Cursor global-rules question.
Disposition: Addressed — V3 reworded as a sanity check with the figures; R5 covers the line-35 comment; Backlog rows removed in the PR (R6), V4 keeps only the plan-index row.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.
