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
