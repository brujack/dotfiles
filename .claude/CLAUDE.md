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

Tests must be added alongside the code they cover, not as a separate pass. Every new function, every changed function, every bug fix gets a test in the same commit.

### PATH-Based Mock Pattern (BATS / Shell Tests)

When using PATH-injected mocks, mocks for commands that **modify real filesystem state** must pass-through to the real binary — not just log and exit 0.

**Affected commands:** `ln`, `chmod`, `mv`, `cp`, and any other command where tests assert actual filesystem state (permissions, file existence, symlinks).

The correct pattern:
```bash
#!/usr/bin/env bash
printf "cmd %s\n" "$*" >> "${MOCK_CALLS_FILE:-/tmp/mock_calls}"
if [[ "${MOCK_CMD_EXIT:-0}" -ne 0 ]]; then
  exit "${MOCK_CMD_EXIT}"
fi
/bin/cmd "$@" 2>/dev/null || true
```

**Why:** A log-only mock exits 0, so the function under test appears to succeed. But if the test then checks `stat` for permissions, `[[ -f dest.bak ]]`, or `[[ -L symlink ]]`, the assertion fails because the real operation never ran. This produces silent failures that look like implementation bugs but are actually mock infrastructure gaps.

**Before committing any test that checks real filesystem state**, verify that every mock in the call chain either passes through or that the test doesn't depend on the real operation having occurred.

### Shell Script Testing Pitfalls (BATS)

These are bugs that shell tests routinely fail to catch. Check for each one when writing or reviewing shell tests.

**1. Parent environment leakage**

Shell tests run as subprocesses. If the developer's shell has `MACOS=1`, `LINUX=1`, or any other env var from their dotfiles, it leaks into every test subprocess. Tests that simulate a different OS must explicitly `unset` all conflicting variables before sourcing or calling the function under test.

```bash
# Wrong — MACOS=1 from parent shell leaks in, making CHRUBY_LOC wrong
@test "CHRUBY_LOC is /usr/local/share on Linux" {
  export MOCK_UNAME_S="Linux"
  detect_env
  [ "${CHRUBY_LOC}" = "/usr/local/share" ]
}

# Correct
@test "CHRUBY_LOC is /usr/local/share on Linux" {
  unset MACOS          # must clear parent shell env
  export MOCK_UNAME_S="Linux"
  detect_env
  [ "${CHRUBY_LOC}" = "/usr/local/share" ]
}
```

Rule: for every OS-branching variable (`MACOS`, `LINUX`, `UBUNTU`, etc.), explicitly `unset` the ones that must be absent. Do not rely on them being unset in the parent.

**2. `$(grep -q ...)` captures nothing — condition is always true**

`grep -q` suppresses all stdout. Command substitution captures stdout only. So `$(grep -q "pattern" file)` is always empty string, making `[[ ! $(grep -q ...) ]]` always true regardless of whether the pattern matches.

```bash
# Wrong — always true, never detects existing entry
if [[ ! $(grep -Fxq "/usr/local/bin/zsh" /etc/shells) ]]; then
  # appends duplicate every time
fi

# Correct — tests exit code directly
if ! grep -Fxq "/usr/local/bin/zsh" /etc/shells; then
  # appends only when missing
fi
```

When you see `$( grep -q ... )` or `$( cmd --quiet ... )`, the test for it must verify behavior when the pattern IS present (function skips) and when it is NOT present (function acts).

**3. `exit` inside functions terminates the test runner**

Functions that call `exit` (e.g., `cd /path || exit`) will terminate the entire shell process when the function is sourced and called from a test. Use `return 1` inside functions.

```bash
# Wrong — kills the test process when cd fails
update_repo() {
  cd "${PERSONAL_GITREPOS}/${DOTFILES}" || exit
  git pull
}

# Correct
update_repo() {
  cd "${PERSONAL_GITREPOS}/${DOTFILES}" || return 1
  git pull
}
```

Every function that could `exit` needs a test that triggers the failure path — if the test hangs or the whole suite aborts, that's the signal. Grep for `|| exit` in any function body and treat it as a bug.

**4. Pipeline exit code masking**

`cmd1 | cmd2 || true` — the `|| true` suppresses `cmd2`'s failure, not `cmd1`'s. But even without `|| true`, in a pipeline without `pipefail`, the exit code is `cmd2`'s. If `cmd1` failing matters, capture `$?` immediately after `cmd1` completes, before any subsequent command can overwrite it.

```bash
# Wrong — pip exit code is lost; $? after `pip check || true` is always 0
python3 <<'EOF'
import pip; ...
EOF
pip check || true
_update_record_end "pip" $?   # always 0

# Correct — capture before anything else runs
python3 <<'EOF'
import pip; ...
EOF
local _pip_rc=$?
pip check || true
_update_record_end "pip" ${_pip_rc}
```

Tests must assert the recorded exit code, not just that the function returned 0.

**9. Exit code propagation and fail-fast**

Every function that calls sub-functions or external commands must propagate failure to its caller. A parent script that swallows exit codes creates silent failures — the caller reports success even when work was skipped or corrupted.

Rules:
- Functions must return a non-zero exit code when they fail. Never return 0 on failure.
- Callers must check return values: use `cmd || return 1`, `cmd || exit 1`, or `if ! cmd; then`.
- Do not use `|| true` on commands whose failure matters — it converts a failure into success.
- When a step fails in a multi-step function, stop immediately (`return 1`) rather than continuing with invalid state. This is fail-fast: detect the problem at the source, not three steps later when the symptom is confusing.
- Exception: cleanup steps (removing temp files, unsetting vars) should run regardless of prior failures. Use a `trap` for cleanup rather than inline `|| true`.

```bash
# Wrong — swallows failure, caller can't detect the problem
run_setup() {
  install_packages     # fails silently
  configure_system     # runs on broken state
  return 0             # always reports success
}

# Correct — fail-fast, propagate exit codes
run_setup() {
  install_packages || return 1
  configure_system || return 1
}
```

Tests must verify that when a step fails, the parent function returns non-zero AND does not execute subsequent steps.

**5. `wc -l` returns 0 for single-line output without trailing newline**

`wc -l` counts newline characters. A single line with no trailing `\n` (common from Python's `"\n".join(items)`) returns 0. Use `grep -c .` to count non-empty lines regardless of trailing newline.

```bash
# Wrong — returns 0 for exactly one package (no trailing newline)
count=$(wc -l < "${file}")

# Correct
count=$(grep -c . "${file}" || true)
```

Always test the single-item case (boundary value) separately from the zero-item and multi-item cases.

**6. `readonly` crash on double-invocation**

`readonly FLAG=1` is a no-op if FLAG is already `readonly` with the same value — but if the variable was previously set (non-readonly) or is readonly with a different value, bash prints an error and the line fails. Functions that set `readonly` variables will crash if called twice in the same shell session (e.g., when sourced by a test setup and then called again).

```bash
# Wrong — crashes on second call
process_args() {
  [[ -n "${1}" ]] && readonly DRY_RUN=1
}

# Correct — use ${VAR+x} (bash 3.2 compatible; [[ -v VAR ]] requires bash 4.2+)
process_args() {
  [[ -n "${1}" ]] && { [[ -n "${DRY_RUN+x}" ]] || readonly DRY_RUN=1; }
}
```

Note: `[[ -v VAR ]]` is bash 4.2+ only. macOS ships bash 3.2. Always use `[[ -n "${VAR+x}" ]]` to test whether a variable is set — it works in both bash 3.2 and 4.x.

Every function that sets `readonly` variables must have a test that calls it twice. If the second call crashes, that's the bug.

**7. Variables not exported are invisible to subprocesses**

A shell variable set with `VAR=value` is local to the current shell. Child processes (Python scripts, subshells with `bash -c`, etc.) cannot see it. Any variable that a called subprocess reads must be `export`ed.

```bash
# Wrong — Python subprocess can't find _UPDATE_TMPDIR
_UPDATE_TMPDIR=$(mktemp -d)
python3 -c "import os; print(os.environ['_UPDATE_TMPDIR'])"  # KeyError

# Correct
export _UPDATE_TMPDIR=$(mktemp -d)
```

If a test passes when run inline but the subprocess writes to a wrong location (e.g., `/tmp` instead of the expected tmpdir), check for missing `export`.

**8. Inverted conditional logic — test both branches**

When a conditional decides whether to download/install something, both branches must be tested:
- When the cached artifact exists → should skip download
- When the cached artifact does not exist → should download

If only the happy path is tested, an inverted condition (downloading when cached, skipping when missing) passes all tests.

```bash
# Wrong — re-downloads when zip exists, never downloads when zip is absent
if [[ -f "${ZIP}" ]]; then
  wget -O "${ZIP}" "${URL}"   # bug: overwrites existing
fi

# Correct
if [[ ! -f "${ZIP}" ]]; then
  wget -O "${ZIP}" "${URL}"
fi
```

For every install/cache guard, write two tests: one with the artifact present (assert download is skipped) and one with it absent (assert download runs).

## Linting

Every project Makefile must have a `lint` target, and `test` must depend on it (`test: lint`).

- Python: `ruff check .`
- Rust: `cargo clippy -- -D warnings`
- PowerShell: `Invoke-ScriptAnalyzer` via PSScriptAnalyzer (use a `PSScriptAnalyzerSettings.psd1` to exclude rules that can't be changed, e.g. `PSAvoidUsingInvokeExpression` for official bootstrapper commands)

## Logic Review

### Pre-Commit Checklist

Run this checklist against staged changes before every commit. Read the diff and check each item:

1. **Conditional logic** — Are all operators correct (`&&`/`||`, `-eq`/`-ne`, `==`/`!=`)? Is grouping precedence explicit (no reliance on implicit `||`/`&&` precedence)?
2. **Boundary values** — Does every conditional handle the boundary case? Off-by-one in loops? Empty string / zero / null inputs?
3. **Variable state** — Is every variable initialized before use? Could any variable be stale from a prior iteration or branch? Are `readonly` / `export` / `unset` correct?
4. **Error paths** — Does every function that can fail have its failure handled? Are early returns / exit codes correct?
5. **Exit code propagation** — Does every caller check the return value of sub-functions? Is `|| true` used only on commands whose failure is genuinely acceptable? Does failure in step N prevent steps N+1 onward from running (fail-fast)?
6. **Integration assumptions** — If calling another function, does the caller match the callee's actual signature and return behavior?

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

## Feature Branches

**Never commit implementation work directly to `main`/`master`.** Always work on a feature branch:

1. Create a worktree on a feature branch before starting implementation (use `superpowers:using-git-worktrees`)
2. Commit work to the feature branch
3. Open a PR — CI runs and auto-merges on pass
4. Before pushing or force-pushing to a branch that has an open PR, verify the PR and branch still exist on remote — if the PR already auto-merged the branch may be gone, and pushing would silently recreate it:
   ```bash
   gh pr view <number> --json state,headRefName
   git ls-remote --heads origin <branch-name>
   ```
5. After the PR merges, delete the feature branch locally and remotely:
   ```bash
   git branch -d feature/branch-name
   git push origin --delete feature/branch-name
   ```

This applies to all repos. Committing directly to master bypasses CI and the review workflow.

Exception: documentation-only fixes (typos, README updates, memory commits) may go directly to master.

When wrapping up a session, check for any stale merged branches and delete them:
```bash
git branch --merged master | grep -v master   # local merged branches
git branch -r --merged origin/master | grep -v master  # remote merged branches
```

## GitHub Actions / CI

- All jobs must run on Node.js 24
- Use `actions/checkout@v5` (natively runs on Node.js 24; v4 used Node.js 20 and is deprecated)
- Set `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: true` as a fallback for third-party actions
- Do not add `actions/setup-node` to Rust or Python jobs that don't need it at the user-code level
- Every Rust build job must upload its release binary as an artifact using `actions/upload-artifact@v5` with 7-day retention
- Build jobs must depend on their test job (`needs: [test]`) — a build will not run if tests fail
- CI badge URLs in `README.md` must use `?event=pull_request` (e.g. `badge.svg?event=pull_request`) — workflows use `branches-ignore: [master]` so they never run on master directly; `?branch=master` and bare `badge.svg` both default to master runs and always show "no status"

### Personal Repos (`~/git-repos/personal/*`)

Every personal repo CI pipeline must have:

1. **Auto-merge** — an `auto-merge` job that merges the PR when all required jobs pass. Use `gh pr merge --squash --auto` triggered on `pull_request` events. Required jobs must be listed in `needs:`.
2. **Secrets scanning** — a `secret-scan` job running `gitleaks` against recent commits. Must have a `.gitleaks.toml` allowlist at the repo root. This job is advisory (non-blocking) but must be present.
3. **Snyk security scan** — only add a `snyk-scan` job to repos that contain languages Snyk Code supports (Python, JavaScript/TypeScript, Java, Go, Ruby, etc.). Do **not** add it to shell-script or config-only repos — `snyk code test` returns `SNYK-CODE-0006` (no supported files) and will always fail. When present, run `snyk code test` with `SNYK_TOKEN` from repository secrets. Never commit Snyk tokens to the repo.
4. **Pre-commit hook** — every repo must have a `scripts/pre-commit` file (committed to the repo, symlinked or copied to `.git/hooks/pre-commit`). The hook must:
   - Run `make lint` first — for single-Makefile repos call it directly; for multi-project repos (no root Makefile) iterate over sub-project dirs and run `make -C <dir> lint` for each dir that has staged changes
   - Run `ggshield secret scan pre-commit` after lint, guarded by `command -v ggshield` so it degrades gracefully if not installed
   - Use `set -e` so any lint failure aborts the commit

   Template for single-Makefile repos:
   ```bash
   #!/usr/bin/env bash
   set -e
   make lint
   if command -v ggshield &>/dev/null; then
       ggshield secret scan pre-commit
   fi
   ```

   Template for multi-project repos (adapt dir list to the repo):
   ```bash
   #!/usr/bin/env bash
   set -e
   for dir in proj1 proj1/proj1-rs proj2 proj2/proj2-rs; do
       if git diff --cached --name-only | grep -q "^${dir}/"; then
           printf "lint: %s\n" "${dir}"
           make -C "${dir}" lint
       fi
   done
   if command -v ggshield &>/dev/null; then
       ggshield secret scan pre-commit
   fi
   ```

## Code Standards

### Shell Scripts

- **Shebang:** `#!/usr/bin/env bash` — always, no exceptions (never `#!/bin/bash` or `#!/bin/sh`)
- **No `set -e`** — handle errors explicitly with `|| exit 1` or return code checks. `set -e` has unpredictable behavior with conditionals, pipes, and subshells. The only exception is pre-commit hooks where `set -e` is acceptable for fail-fast behavior.
- **Sourcing guard for testability** — every shell script that will be tested must use the sourcing guard pattern: extract logic into functions, then gate the main execution block so tests can source the file without running it:
  ```bash
  #!/usr/bin/env bash
  my_function() { ... }
  [[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0
  my_function "$@"
  ```
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

Every git repository must have secrets guarding in place:
- A `gitleaks` secret scan in CI (`.github/workflows/ci.yml`) scanning recent commits
- A `.gitleaks.toml` allowlist config at the repo root
- Credential files and secret paths listed in `.gitignore`

## Architectural Decision Records

**ADRs are required** for all significant architectural choices in every personal repo under `~/git-repos/personal/`. Write the ADR before or alongside the implementation — not after.

- **Cross-cutting decisions** (testing frameworks, CI patterns, tooling standards that apply across repos) → `dotfiles/docs/adr/`
- **Repo-specific decisions** → that repo's own `docs/adr/`
- **Numbering:** Sequential four-digit numbers (`0001`, `0002`, …); each repo's `docs/adr/` starts from `0001` independently
- **Template:** Context → Decision → Consequences → Related (Nygard-style; see any `dotfiles/docs/adr/` file for the full format)
- **Index:** Every `docs/adr/` directory must have a `README.md` with a status table listing all ADRs
- **Status lifecycle:** `Proposed` → `Accepted` → `Deprecated` / `Superseded by ADR-NNNN`

What counts as significant: choice of testing framework, CI tooling, major library adoption, data storage approach, authentication strategy, structural patterns (modularization, lib layout), security guardrails. Routine bug fixes and small features do not need ADRs.

## Superpowers Plans and Specs

Every repo that uses the superpowers brainstorming → writing-plans workflow must have a `docs/superpowers/README.md` that indexes all specs and plans with their status.

**Required format** (see `dotfiles/docs/superpowers/README.md` as the canonical example):

```markdown
# Superpowers Specs and Plans

Master status index for all specs and implementation plans in this directory.

## Status Key

| Status | Meaning |
|---|---|
| Done | Implemented and merged to master |
| In Progress | Currently being implemented |
| Pending | Not yet started |

---

## All Plans

| Date | Plan | Spec | Status |
|---|---|---|---|
| YYYY-MM-DD | [name](plans/file.md) | [spec](specs/file.md) | Done |

---

## Backlog

Ideas approved for future specs, in no particular order:

| Feature | Notes |
|---|---|
| feature name | brief description |

---

## Adding a new entry

When a new spec or plan is created, add a row to the All Plans table. Set status to **In Progress** when implementation starts, **Done** when the PR merges. Also add a `> **Status: DONE**` banner at the top of the plan file once complete. Move backlog items to the All Plans table when their spec is written (remove the backlog row).
```

**Status values:** `In Progress` while implementation is active; `Done` once the PR merges.

**Maintenance rules:**
- All Plans is a single combined table — no separate Specs/Plans split.
- Spec column uses `—` when no spec was written.
- Add a row to All Plans when a new spec or plan is created.
- Set status to `Done` and add a `> **Status: DONE**` banner at the top of the plan file once the feature PR merges.
- Move backlog items to All Plans when their spec is written — delete the backlog row, don't use strikethrough.
- Keep this index current — a stale index causes future agents to treat completed plans as pending work.

## Approach

- Read and understand existing code before suggesting modifications
- Keep solutions simple and focused on the minimum needed
- Don't give time estimates
- If blocked, consider alternatives rather than retrying the same approach
