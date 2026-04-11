---
name: Mock pass-through pattern for filesystem commands
description: Mocks for commands that modify real filesystem state must pass-through to the real binary, not just log and exit 0
type: feedback
---

Mocks for `ln`, `chmod`, `mv`, `cp` (and similar filesystem commands) must call the real binary, not just log the call and exit 0.

**Why:** Tests that check actual filesystem state (permissions via `stat`, file existence, symlink creation) will silently pass the function call but fail the assertion if the mock only logs. PR #19 was pushed with tests failing for this exact reason — subagents wrote tests checking `stat` for 700 permissions and `[[ -f dest.bak ]]`, but `chmod` and `mv` mocks were log-only.

**How to apply:** The correct pattern for any mock that needs to support real filesystem operations:
```bash
#!/usr/bin/env bash
printf "cmd %s\n" "$*" >> "${MOCK_CALLS_FILE:-/tmp/mock_calls}"
if [[ "${MOCK_CMD_EXIT:-0}" -ne 0 ]]; then
  exit "${MOCK_CMD_EXIT}"
fi
/bin/cmd "$@" 2>/dev/null || true
```

Currently implemented for: `ln`, `chmod`, `mv`, `cp`.

When writing new tests that check real filesystem state, verify that any mocks in the call chain actually perform the operation. The `make test` exit code alone is not sufficient — also check that test assertions verify state, not just that functions ran.
