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

Use the `tdd` skill when implementing any feature or bug fix. It provides the full workflow; the rules below are the binding constraints.

**TDD is required.** Write the failing test first, then write the minimum code to make it pass. This is not optional — it applies to every new function, feature, or bug fix.

### Tests must verify behavior, not implementation

Tests must exercise the system through its **public interface** only. A test that breaks when you rename an internal function — without changing behavior — is a bad test. Good tests survive refactors because they don't care about internal structure.

Do not:

- Mock internal collaborators
- Test private methods
- Assert on internal state (e.g., querying a database directly instead of using the interface)

### No horizontal slicing

**DO NOT write all tests first, then all implementation.** This produces tests that describe imagined behavior and are insensitive to real changes.

```
WRONG (horizontal):
  RED:   test1, test2, test3, test4
  GREEN: impl1, impl2, impl3, impl4

RIGHT (vertical — one at a time):
  RED→GREEN: test1→impl1
  RED→GREEN: test2→impl2
  ...
```

### The cycle (one behavior at a time)

Before starting: confirm with the user which behaviors to test (you can't test everything — prioritize critical paths).

For each behavior:

1. Write ONE failing test that describes the behavior through the public interface
2. Run it and confirm it fails (wrong reason = wrong test)
3. Write the minimum implementation to make it pass
4. Run tests and confirm they pass
5. Commit
6. Move to the next behavior

Refactor only after all targeted behaviors are green. **Never refactor while RED.**

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

### Universal Testing Pitfalls (All Languages)

These pitfalls apply regardless of language. Check for each when writing or reviewing tests.

**A. Test isolation — tests must not inherit state**

Every test must set up all state it depends on. State left by a prior test, or leaked from the parent process, produces false passes and order-dependent failures.

| Language     | Common leak                                                         | Fix                                                                      |
| ------------ | ------------------------------------------------------------------- | ------------------------------------------------------------------------ |
| Shell (BATS) | Parent shell env vars (`MACOS=1`, `LINUX=1`) leak into subprocesses | `unset MACOS LINUX` before OS-branching tests                            |
| Python       | Module-level globals, `os.environ` mutations persist across tests   | Use `unittest.mock.patch.dict(os.environ, ...)` or restore in `tearDown` |
| Go           | Package-level vars, `os.Setenv` not cleaned up                      | `t.Setenv(k, v)` (auto-restores); restore manually in `t.Cleanup`        |
| Rust         | Static state, `std::env::set_var` across parallel tests             | Run env-sensitive tests with `-- --test-threads=1`; use `temp_env` crate |

Rule: if a test works in isolation but fails when run after another test, it has a state leak.

**B. Return value propagation and fail-fast**

Every caller must check the return value of sub-functions AND propagate that return code to its own caller. A failure anywhere in the call chain must bubble up to the top — swallowing it at any intermediate level reports false success. When step N fails, stop — do not proceed to step N+1 with invalid state.

| Language | Swallowing pattern (wrong)                  | Propagating pattern (correct)                      |
| -------- | ------------------------------------------- | -------------------------------------------------- |
| Shell    | `cmd` (unchecked) or `cmd \|\| true`        | `cmd \|\| return 1`                                |
| Python   | `except: pass` or `except Exception: log()` | `raise` or let it propagate                        |
| Go       | `result, _ := f()`                          | `result, err := f(); if err != nil { return err }` |
| Rust     | `.unwrap_or_default()` hiding errors        | `?` operator or explicit `match`                   |

The requirement applies at every level: if `leaf()` returns 1, `mid()` must return 1 to its caller, and `top()` must return 1 to its caller. A chain of three functions where only `leaf()` propagates correctly but `mid()` swallows the error is broken — the top-level caller still sees false success.

Cleanup steps (temp file removal, resource release) are the exception — they must run regardless of prior failures. Use `defer` (Go), `finally` (Python), `Drop` (Rust), or `trap` (shell) rather than inline error suppression.

Tests must verify that when step N fails, the parent function returns non-zero AND does not execute step N+1. For multi-level chains, test that the top-level caller also returns non-zero.

**C. Test both branches of every guard/conditional**

An inverted condition (`if exists { act }` instead of `if ! exists { act }`) passes all tests if only the happy path is tested. For every cache guard, existence check, or install skip condition, write two tests:

- Condition true → assert the expected action is skipped
- Condition false → assert the expected action runs

This applies equally to shell `[[ -f file ]]`, Python `if path.exists()`, Go `if _, err := os.Stat(p); err == nil`, etc.

**D. Swallowed errors in pipelines and chains**

An error in the middle of a chain can be silently discarded if a later step succeeds.

| Language | Pattern                                    | Problem                                                    |
| -------- | ------------------------------------------ | ---------------------------------------------------------- |
| Shell    | `cmd1 \| cmd2`                             | Exit code is `cmd2`'s; `cmd1` failure is invisible         |
| Shell    | `cmd; capture=$?` after another command    | `$?` is the last command's exit, not `cmd`'s               |
| Python   | `subprocess.run(..., check=False)`         | Non-zero return ignored unless caller checks `.returncode` |
| Go       | Ignoring `err` from the first of two calls | Only second call's error is checked                        |

Fix: capture the exit code/error immediately after the command that can fail, before anything else runs.

**E. Mock fidelity — mocks must behave like the real thing**

A mock that returns success without performing the real operation will pass tests that assert on return code but fail tests that assert on side effects (files created, permissions set, state changed).

- Shell (BATS): filesystem mocks (`ln`, `chmod`, `mv`, `cp`) must pass through to the real binary when tests assert on actual filesystem state
- Python: verify mock return values and side effects match what the real implementation produces
- Go/Rust: verify that mocked interfaces return the same types and error shapes as real implementations

Before committing any test that asserts on state produced by a mocked call, verify the mock actually performs the operation.

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

Shell-specific traps on top of the universal pitfalls above.

**1. Parent environment leakage**

If the developer's shell has `MACOS=1`, `LINUX=1`, or any other env var from dotfiles, it leaks into every BATS subprocess. Tests that simulate a different OS must explicitly `unset` all conflicting variables.

```bash
# Wrong — MACOS=1 from parent shell leaks in
@test "CHRUBY_LOC is /usr/local/share on Linux" {
  export MOCK_UNAME_S="Linux"
  detect_env
  [ "${CHRUBY_LOC}" = "/usr/local/share" ]
}

# Correct
@test "CHRUBY_LOC is /usr/local/share on Linux" {
  unset MACOS
  export MOCK_UNAME_S="Linux"
  detect_env
  [ "${CHRUBY_LOC}" = "/usr/local/share" ]
}
```

**2. `$(grep -q ...)` captures nothing — condition is always true**

`grep -q` suppresses stdout. Command substitution captures stdout only. `$(grep -q "x" file)` is always empty string, making `[[ ! $(grep -q ...) ]]` always true.

```bash
# Wrong — always true, appends duplicate every run
if [[ ! $(grep -Fxq "/usr/local/bin/zsh" /etc/shells) ]]; then ...

# Correct
if ! grep -Fxq "/usr/local/bin/zsh" /etc/shells; then ...
```

Test both: pattern present (function skips) and pattern absent (function acts).

**3. `exit` inside functions terminates the test runner**

`cd /path || exit` terminates the entire shell when the script is sourced for testing. Use `return 1` inside functions. Grep for `|| exit` in function bodies and treat every occurrence as a bug.

```bash
# Wrong
update_repo() { cd "${DIR}" || exit; git pull; }

# Correct
update_repo() { cd "${DIR}" || return 1; git pull; }
```

**4. Pipeline exit code masking**

In a pipeline `cmd1 | cmd2`, the exit code is `cmd2`'s. Capture `$?` immediately after the command that matters, before anything else runs.

```bash
# Wrong — pip_rc is cmd2's exit, not the python heredoc's
python3 <<'EOF'
...
EOF
pip check || true
record_result $?        # always 0

# Correct
python3 <<'EOF'
...
EOF
local _rc=$?
pip check || true
record_result ${_rc}
```

**5. `wc -l` returns 0 for single-line output without trailing newline**

`wc -l` counts newlines. A single line from `"\n".join(items)` has no trailing newline → returns 0. Use `grep -c .` for non-empty line count regardless of trailing newline. Always test the single-item boundary case.

**6. `readonly` crash on double-invocation**

`readonly FLAG=1` crashes if FLAG is already set (bash prints an error). Guard with `${VAR+x}`:

```bash
# Wrong
[[ -n "${1}" ]] && readonly DRY_RUN=1

# Correct — bash 3.2 compatible (macOS ships 3.2; [[ -v VAR ]] requires 4.2+)
[[ -n "${1}" ]] && { [[ -n "${DRY_RUN+x}" ]] || readonly DRY_RUN=1; }
```

Every function that sets `readonly` variables must have a test that calls it twice.

**7. Variables not exported are invisible to subprocesses**

`VAR=value` is local to the current shell. Any subprocess (Python, `bash -c`, etc.) that reads it via `os.environ` or `$VAR` gets nothing. Use `export VAR=value`.

**8. Inverted conditional logic — test both branches**

See Universal pitfall C. For shell specifically: for every `[[ -f file ]]` or `command -v cmd` guard, write one test where the condition is true and one where it is false.

**9. Direct-call error capture — use `|| _rc=$?`, not bare call + `local _rc=$?`**

BATS fires an ERR trap on any non-zero return from a bare command in the test body. If you call a function directly (without `run`) to capture its exit code, a plain call followed by `local _rc=$?` will never reach the capture line — the ERR trap fires first and marks the test failed.

```bash
# Wrong — ERR trap fires at the bare call; local _rc=$? is never reached
some_function
local _rc=$?
[ "${_rc}" -ne 0 ]

# Correct — || prevents ERR trap; _rc captures the exit code
local _rc=0
some_function || _rc=$?
[ "${_rc}" -ne 0 ]
```

This also provides TDD signal: with `exit 1` (pre-fix) the BATS shell itself dies — catastrophic failure. With `return 1` (post-fix) the `||` branch captures the code and the assertion passes. A test using `run` can't distinguish the two because both give `$status=1`.

## Linting

Every project Makefile must have a `lint` target, and `test` must depend on it (`test: lint`).

- Python: `ruff check .`
- Rust: `cargo clippy -- -D warnings`
- PowerShell: `Invoke-ScriptAnalyzer` via PSScriptAnalyzer (use a `PSScriptAnalyzerSettings.psd1` to exclude rules that can't be changed, e.g. `PSAvoidUsingInvokeExpression` for official bootstrapper commands)

## Logic Review

### Pre-Commit Checklist

Applies to every language. Read the diff and check each item before committing:

1. **Conditional logic** — Are all operators correct (`&&`/`||`, `==`/`!=`, `-eq`/`-ne`, `is`/`is not`)? Is precedence explicit — no reliance on implicit operator precedence across `&&`/`||` chains?
2. **Boundary values** — Does every conditional handle the boundary case? Off-by-one in loops? Empty string / zero / null / None inputs? Single element vs. multiple?
3. **Variable/state scope** — Is every variable initialized before use? Could it be stale from a prior iteration or branch? Are scope modifiers (`readonly`, `export`, `final`, `const`, `global`) correct?
4. **Error paths** — Does every function that can fail have its failure handled? Are early returns / exit codes / exceptions correct? Does partial failure leave state half-modified?
5. **Exit code and return value propagation** — Does every caller check the return value of sub-functions? Is error suppression (`|| true`, `except: pass`, `_ =`, `.unwrap_or_default()`) used only where failure is genuinely acceptable? Does failure in step N prevent step N+1 from running on broken state (fail-fast)?
6. **Both branches tested** — For every guard conditional (cache check, existence check, feature flag), is there a test where the condition is true AND a test where it is false? An inverted condition passes all tests if only one branch is exercised.
7. **Integration assumptions** — If calling another function, does the caller match the callee's actual signature, return value semantics, and side effects?

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

After every PR merge, run a full stale branch sweep (not just the current branch):

```bash
# Remote: prune tracking refs, then delete any with merged PRs
git fetch --prune
for branch in $(git branch -r | grep -v master | sed 's|origin/||'); do
  if gh pr list --head "$branch" --state merged --json number --jq '.[0].number' 2>/dev/null | grep -q .; then
    git push origin --delete "$branch"
  fi
done

# Local (squash-merged): git branch --merged misses these, check via gh
for branch in $(git branch | grep -v '^\*' | grep -v master); do
  if gh pr list --head "$branch" --state merged --json number --jq '.[0].number' 2>/dev/null | grep -q .; then
    git branch -D "$branch"
  fi
done

# Local (regular merged): standard check
git branch --merged master | grep -v master | xargs -r git branch -d
```

Also run this sweep at session start and session end to catch accumulated stale branches.

### PR Monitoring

After opening a PR, monitor it until it is resolved — either merged or failed. Do not consider the work done at push time.

**After every `gh pr create`:**

1. Poll CI status with `gh pr checks <number> --watch` until all checks complete
2. If any check fails:
   - Read the failure output: `gh run view <run-id> --log-failed`
   - Fix the issue on the feature branch, commit, and push
   - CI re-runs automatically; return to step 1
3. Once all checks pass and the PR auto-merges, delete the branch:
   ```bash
   git branch -d feature/branch-name
   git push origin --delete feature/branch-name
   ```
4. If the PR does not auto-merge (repo has no auto-merge job), notify the user and wait for instructions

If the session ends before CI finishes, note the PR number and status in the conversation so the user can follow up.

### PR Review Gate

Before pushing any feature branch (Option 2 in finishing-a-development-branch),
run the pr-review skill. Only push when verdict is PASS. If HOLD:

1. Fix all CRITICAL findings
2. Run make test — confirm no regressions
3. Commit the fixes
4. Re-run pr-review
5. Repeat until PASS, or escalate to user after two failed fix attempts

WARNING and INFO findings are advisory — surface them but do not block the push.

This rule is a durable backup: if `claude plugins update superpowers` overwrites
the finishing-a-development-branch skill file, this rule still enforces the gate.

### Dispatching Subagents to Worktrees

When using `superpowers:subagent-driven-development` with a worktree, implementer
subagents must be told the working directory **prominently at the top** of the prompt,
not just buried in a "Work from:" line at the bottom. Without this, subagents
default to the parent repo and commit to the wrong directory.

Required pattern in every implementer prompt:

```
**IMPORTANT: All work must happen in `/path/to/worktree/`. Do not cd anywhere else.**
```

Also have the spec reviewer verify the commit landed on the correct branch:

```bash
git -C /path/to/worktree log --oneline -1
```

## GitHub MCP

The GitHub MCP server is configured globally (user scope) via `~/.claude/mcp.json`.
It provides native GitHub operations — PR review, issue management, repo browsing,
diff access — across all projects without copy-pasting into chat.

Requires `GITHUB_PAT` to be set in `~/git-repos/personal/dotfiles/config/local.sh`.
If it isn't set, run `setup_env.sh -t setup_user` after adding the token.
Verify with `setup_env.sh -t doctor`.

Use it for:

- Fetching PR diffs and changed files
- Reading and creating issues
- Posting structured review comments
- Browsing repo contents

Do not use it to push directly to main/master — normal PR workflow still applies.

## GitHub Actions / CI

- All jobs must run on Node.js 24
- Use `actions/checkout@v5` (natively runs on Node.js 24; v4 used Node.js 20 and is deprecated)
- Set `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: true` as a fallback for third-party actions
- Do not add `actions/setup-node` to Rust or Python jobs that don't need it at the user-code level
- Every Rust build job must upload its release binary as an artifact using `actions/upload-artifact@v5` with 7-day retention
- Build jobs must depend on their test job (`needs: [test]`) — a build will not run if tests fail
- CI badge URLs in `README.md` must use `?event=pull_request` (e.g. `badge.svg?event=pull_request`) — workflows trigger on `pull_request` only so they never run on master directly; `?branch=master` and bare `badge.svg` both default to master runs and always show "no status"

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

5. **Pre-push hook (permanent)** — every repo must have a `scripts/pre-push` file that runs the test suite locally before the push reaches GitHub. Install alongside the pre-commit hook via `make install-hooks`. Never remove it — it is permanent, not a temporary workaround.

   Template for single-Makefile repos:

   ```bash
   #!/usr/bin/env bash
   # Pre-push hook: runs full test suite locally before push reaches GitHub.
   # Permanent: provides fast local feedback and conserves GitHub Actions minutes.
   # GitHub Actions is the final merge gate on PRs.
   set -e

   real_push=0
   while read -r local_ref local_sha remote_ref remote_sha; do
       [ "${local_sha}" != "0000000000000000000000000000000000000000" ] && real_push=1
   done
   [ "${real_push}" -eq 0 ] && exit 0

   printf "Running tests locally (pre-push)...\n"
   make -C "$(cd "$(git rev-parse --git-common-dir)/.." && pwd)" test
   ```

   Template for multi-project repos (detect changed sub-projects, adapt dir list):

   ```bash
   #!/usr/bin/env bash
   # Pre-push hook: runs tests for changed sub-projects before push reaches GitHub.
   # Permanent: provides fast local feedback and conserves GitHub Actions minutes.
   # GitHub Actions is the final merge gate on PRs.
   set -e

   REPO_ROOT="$(cd "$(git rev-parse --git-common-dir)/.." && pwd)"
   DIRS_TO_TEST=()

   while read -r local_ref local_sha remote_ref remote_sha; do
       [ "${local_sha}" = "0000000000000000000000000000000000000000" ] && continue

       if [ "${remote_sha}" = "0000000000000000000000000000000000000000" ]; then
           base="$(git merge-base "${local_sha}" origin/master 2>/dev/null \
               || git rev-list --max-parents=0 "${local_sha}")"
           range="${base}..${local_sha}"
       else
           range="${remote_sha}..${local_sha}"
       fi

       for dir in proj1 proj1/proj1-rs proj2 proj2/proj2-rs; do
           if git diff --name-only "${range}" | grep -q "^${dir}/"; then
               DIRS_TO_TEST+=("${dir}")
           fi
       done
   done

   if [ "${#DIRS_TO_TEST[@]}" -eq 0 ]; then
       printf "No changed sub-projects detected. Skipping tests.\n"
       exit 0
   fi

   for dir in $(printf '%s\n' "${DIRS_TO_TEST[@]}" | sort -u); do
       printf "test: %s\n" "${dir}"
       make -C "${REPO_ROOT}/${dir}" test
   done
   ```

   Key implementation notes:
   - **Drain the full stdin loop before acting** — never `exit` inside the while loop; use a `real_push=0` flag and check after the loop. A single push command can send multiple refs (e.g. a real branch + a deletion); exiting on the first deletion ref would skip testing the real push.
   - **Use `git rev-parse --git-common-dir` not `--show-toplevel`** — in a git worktree, `--show-toplevel` returns the worktree path, not the main repo root. `--git-common-dir` returns the shared `.git` dir; `cd "$(git rev-parse --git-common-dir)/.."` gives the main repo root where the Makefile lives.

6. **GitHub Actions CI triggers** — workflows must trigger on `pull_request` only. Never use bare `push:` or `branches-ignore:` push triggers. The pre-push hook is the gate for branch pushes; GitHub Actions is the PR merge gate.

   ```yaml
   on:
     pull_request:
       branches:
         - master
   ```

## Code Standards

### Idempotency

**Idempotency is a cornerstone of all shell, Ansible, and Terraform work.** Running the same operation twice must produce the same result as running it once — no errors, no duplicate state, no unintended side effects.

**Shell:**

- Always check before acting — guard installs, symlinks, directory creation, and file modifications with existence checks
- Use `command -v tool` before installing, `[[ -f path ]]` before writing, `[[ -L link ]]` before symlinking
- Never append to a file without first checking the content isn't already there
- Tests must verify idempotency: calling a function twice produces the same result as calling it once

**Ansible:**

- Use modules that declare desired state (`package`, `file`, `template`, `service`) rather than `command`/`shell` wherever possible
- When `command`/`shell` is unavoidable, add `creates:`, `removes:`, or a `when:` guard so the task skips if already complete
- Never use `command`/`shell` for something a module handles natively — it bypasses idempotency guarantees

**Terraform:**

- Resources declare desired state by design — do not work around this with `local-exec` provisioners that have side effects
- `local-exec` and `remote-exec` provisioners are not idempotent; avoid them except for bootstrapping that cannot be expressed as state
- Data sources are always safe; prefer them over provisioners for read operations

If a script, playbook, or Terraform config cannot be run twice safely, that is a bug — not an acceptable trade-off.

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
- **Error handling in function bodies:** use `|| return 1` (never `|| exit` — `exit` inside a function terminates the entire process, including the test runner). At top-level scripts, `|| exit 1` is acceptable. Guard installs with `command -v`.
- **Return code propagation:** every function that calls a sub-function must propagate failures with `|| return 1`. The caller of the caller must do the same. Failures must bubble up the entire call chain — swallowing a return code anywhere in the chain reports false success to the top level.

### PowerShell

- **Testing:** Pester v5 (`Invoke-Pester`); `BeforeAll { . "$PSScriptRoot/../script.ps1" }` to dot-source for function-level testing
- **Mocking:** Pester `Mock` intercepts cmdlets and external commands; COM objects (`New-Object -ComObject`) are Windows-only at parameter binding — extract thin wrapper functions (`Get-UpdateSearcher`, etc.) so they can be mocked cross-platform
- **Function naming:** Avoid names that shadow built-in cmdlets (e.g. don't name a wrapper `Enable-WindowsOptionalFeature` — it's already a Windows cmdlet)
- **Cross-platform stubs:** Add `global:` stubs in `BeforeAll` for Windows-only cmdlets (`Get-WindowsOptionalFeature`, `Enable-WindowsOptionalFeature`, etc.) guarded with `if (-Not (Get-Command ...))` so tests run on macOS
- **Variable escaping in Makefile:** Use `$$var` in Makefile recipes to pass `$var` to PowerShell via `pwsh -Command`

### Comments

Code lives a long time. The what is the code — don't restate it. Document the why:

- **Decisions** — why this approach over the obvious alternative
- **Exceptions** — why this case is handled differently
- **Constraints** — external requirements, bugs worked around, non-obvious invariants
- **External limitations** — link to the upstream bug, RFC, vendor decision, or policy that forced a workaround; without this the workaround looks like a mistake

Do not add comments to code that wasn't changed. A comment that describes what the code does is noise. A comment that explains why it does it that way is signal.

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
- A pre-commit hook that runs `ggshield secret scan pre-commit` locally — this catches secrets before they leave the machine. CI gitleaks is a backstop, not a substitute. Run `make install-hooks` once per checkout to activate it.

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

| Status      | Meaning                          |
| ----------- | -------------------------------- |
| Done        | Implemented and merged to master |
| In Progress | Currently being implemented      |
| Pending     | Not yet started                  |

---

## All Plans

| Date       | Plan                  | Spec                  | Status |
| ---------- | --------------------- | --------------------- | ------ |
| YYYY-MM-DD | [name](plans/file.md) | [spec](specs/file.md) | Done   |

---

## Backlog

Ideas approved for future specs, in no particular order:

| Feature      | Notes             |
| ------------ | ----------------- |
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
