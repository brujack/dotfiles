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
