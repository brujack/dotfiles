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

## Memory

Whenever memory files are created or updated, commit them immediately as part of the same logical unit of work — or as a standalone commit if the session is wrapping up. Memory changes are not committed automatically; you must `git add` and `git commit` them explicitly.

## Memory for Personal Repos

All repos under `~/git-repos/personal/` have their Claude project memories stored in `~/git-repos/personal/dotfiles/.claude/projects/` and symlinked into `~/.claude/projects/`. This means memories are shared across machines via the dotfiles repo.

When working in any personal repo, save memories as normal — they are automatically persisted and synced.

## Keeping CLAUDE.md Up To Date

When making any change to a repository, update the relevant `CLAUDE.md` file(s) before finishing. These files are the primary reference for future sessions — stale documentation is worse than none.

At the end of each session, update `~/.claude/CLAUDE.md` and any relevant repo-level `CLAUDE.md` files with new learnings, preferences, or conventions discovered during the session.

## Keeping README.md Up To Date

Update the top-level `README.md` whenever a change affects anything it documents — new features, changed commands, updated dependencies, new project structure, etc. The README should always reflect the current state of the repository.

## Test-Driven Development

**TDD is required.** Write the failing test first, then write the minimum code to make it pass. This is not optional — it applies to every new function, feature, or bug fix.

The cycle is:
1. Write a failing test that defines the expected behavior
2. Run it and confirm it fails (wrong reason = wrong test)
3. Write the minimum implementation to make it pass
4. Run tests and confirm they pass
5. Commit
6. Refactor if needed, keeping tests green

**Never write implementation before the test.** If you find yourself writing code and then adding tests afterward, stop — you are doing it wrong.

Tests must be added alongside the code they cover, not as a separate pass. Every new function, every changed function, every bug fix gets a test in the same commit.

## Linting

Every project Makefile must have a `lint` target, and `test` must depend on it (`test: lint`).

- Python: `ruff check .`
- Rust: `cargo clippy -- -D warnings`
- PowerShell: `Invoke-ScriptAnalyzer` via PSScriptAnalyzer (use a `PSScriptAnalyzerSettings.psd1` to exclude rules that can't be changed, e.g. `PSAvoidUsingInvokeExpression` for official bootstrapper commands)

## GitHub Actions / CI

- All jobs must run on Node.js 24
- Use `actions/checkout@v5` (natively runs on Node.js 24; v4 used Node.js 20 and is deprecated)
- Set `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: true` as a fallback for third-party actions
- Do not add `actions/setup-node` to Rust or Python jobs that don't need it at the user-code level
- Every Rust build job must upload its release binary as an artifact using `actions/upload-artifact@v5` with 7-day retention
- Build jobs must depend on their test job (`needs: [test]`) — a build will not run if tests fail

## Code Standards

### Shell Scripts

- **Shebang:** `#!/usr/bin/env bash`
- **Conditionals:** `[[ ... ]]` not `[ ... ]`
- **Variables:** `${VAR}` with braces
- **Output:** `printf "message\n"` not `echo`
- **Functions:** `snake_case()` naming
- **Constants:** `SCREAMING_SNAKE_CASE`, marked `readonly`
- **Error handling:** Check `$?` or use `|| exit 1`; guard installs with `command -v`

### PowerShell

- **Testing:** Pester v5 (`Invoke-Pester`); `BeforeAll { . "$PSScriptRoot/../script.ps1" }` to dot-source for function-level testing
- **Mocking:** Pester `Mock` intercepts cmdlets and external commands; COM objects (`New-Object -ComObject`) are Windows-only at parameter binding — extract thin wrapper functions (`Get-UpdateSearcher`, etc.) so they can be mocked cross-platform
- **Function naming:** Avoid names that shadow built-in cmdlets (e.g. don't name a wrapper `Enable-WindowsOptionalFeature` — it's already a Windows cmdlet)
- **Cross-platform stubs:** Add `global:` stubs in `BeforeAll` for Windows-only cmdlets (`Get-WindowsOptionalFeature`, `Enable-WindowsOptionalFeature`, etc.) guarded with `if (-Not (Get-Command ...))` so tests run on macOS
- **Variable escaping in Makefile:** Use `$$var` in Makefile recipes to pass `$var` to PowerShell via `pwsh -Command`

### General

- Avoid over-engineering — only make changes directly requested or clearly necessary
- Don't add features, refactor, or "improve" beyond what was asked
- Don't add docstrings, comments, or type annotations to code that wasn't changed
- Don't create helpers or abstractions for one-time operations
- Prefer editing existing files over creating new ones
- No backwards-compatibility shims for removed code

## Repository Structure

Every git repository must have a `README.md` at the top level.

## Approach

- Read and understand existing code before suggesting modifications
- Keep solutions simple and focused on the minimum needed
- Don't give time estimates
- If blocked, consider alternatives rather than retrying the same approach
