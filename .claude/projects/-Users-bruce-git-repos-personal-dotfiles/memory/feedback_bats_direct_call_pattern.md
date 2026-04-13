---
name: BATS direct-call error-capture pattern
description: Use || _rc=$? to capture non-zero return from a function in a BATS test body without triggering the ERR trap
type: feedback
---

When testing that a shell function returns non-zero, use `|| _rc=$?` instead of a plain direct call followed by `local _rc=$?`. BATS's ERR trap fires on any non-zero return from a bare command in the test body, which marks the test as failed before the assertion runs.

**Wrong:**
```bash
some_function
local _rc=$?
[ "${_rc}" -ne 0 ]   # never reached — ERR trap already fired
```

**Correct:**
```bash
local _rc=0
some_function || _rc=$?
[ "${_rc}" -ne 0 ]   # reached, passes
```

**Why:** The `||` short-circuit prevents BATS's ERR trap from firing. With `exit 1` (pre-fix) the entire BATS shell dies — test fails catastrophically. With `return 1` (post-fix) the `||` branch captures the code and the assertion runs. This makes the test properly distinguish `exit` (bad) from `return` (good).

**How to apply:** Any BATS test that calls a function directly (without `run`) and expects a non-zero return must use `fn || _rc=$?` to capture the exit code.
