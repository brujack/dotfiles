# Global Claude Code Instructions

## Communication Style

- Be concise and direct — no filler words, preamble, or trailing summaries
- Lead with the answer or action, not the reasoning
- No emojis unless explicitly requested
- Short, direct sentences over long explanations

## Committing Work

Create a git commit at the end of each logical unit of work. A unit of work is a self-contained change: a new feature, a bug fix, a docs update, a refactor, or any combination that belongs together. Do not batch unrelated changes into one commit and do not leave work uncommitted.

Commit message format:

```
<type>: <short summary>

<optional body explaining why, not what>

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
```

Common types: `feat`, `fix`, `docs`, `ci`, `refactor`, `test`, `chore`.

Before committing, run the pre-commit logic review checklist (see "Logic Review" section) against staged changes.

## Memory

Whenever memory files are created or updated, commit them immediately as part of the same logical unit of work — or as a standalone commit if the session is wrapping up. Memory changes are not committed automatically; you must `git add` and `git commit` them explicitly.

## Memory for Personal Repos

All repos under `~/git-repos/personal/` have their Claude project memories stored in `~/git-repos/personal/dotfiles/.claude/projects/` and symlinked into `~/.claude/projects/`. This means memories are shared across machines via the dotfiles repo.

When working in any personal repo, save memories as normal — they are automatically persisted and synced.

## After Every PR Merge or Direct Master Commit

Before closing out the work, ask yourself two questions:

1. **What did I learn?** — Any non-obvious pattern, gotcha, constraint, or decision that came up.
2. **Where should I document this?** — CLAUDE.md, a memory file, an ADR, or a code comment. If it's worth remembering, write it down before moving on.

## Keeping CLAUDE.md Up To Date

When making any change to a repository, update the relevant `CLAUDE.md` file(s) before finishing. These files are the primary reference for future sessions — stale documentation is worse than none.

At the end of each session, update `~/.claude/CLAUDE.md` and any relevant repo-level `CLAUDE.md` files with new learnings, preferences, or conventions discovered during the session.

## Keeping README.md Up To Date

Update the top-level `README.md` whenever a change affects anything it documents — new features, changed commands, updated dependencies, new project structure, etc. The README should always reflect the current state of the repository.

## Approach

- Read and understand existing code before suggesting modifications
- Keep solutions simple and focused on the minimum needed
- Don't give time estimates
- If blocked, consider alternatives rather than retrying the same approach

---

@~/.claude/standards/tdd.md
@~/.claude/standards/logic-review.md
@~/.claude/standards/git-workflow.md
@~/.claude/standards/ci.md
@~/.claude/standards/code-standards.md
@~/.claude/standards/repo-structure.md
@~/.claude/standards/behavior.md
@~/.claude/standards/rust.md
