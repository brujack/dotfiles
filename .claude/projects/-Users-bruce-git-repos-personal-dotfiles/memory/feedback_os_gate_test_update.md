---
name: OS gate test update pattern
description: When adding a new OS gate as the first check in an existing function, all pre-existing tests need the gate var set explicitly
type: feedback
---

When inserting a new platform gate (e.g. `[[ -z ${MACOS:-} ]]` early-return) into an existing function, every pre-existing test for that function implicitly relied on the gate variable being unset. They all need `export MACOS=1` (or the relevant platform var) added explicitly to preserve their original test intent.

**Why:** Without it, the tests hit the new gate, emit SKIP, and pass vacuously — the actual logic under test is never exercised. The failure is silent: all tests green, zero coverage of the real code paths.

**How to apply:** Any time a new OS/platform gate is added to a function with existing tests, audit every test for that function and add `export <PLATFORM_VAR>=1` to each one that tests macOS-specific behavior. Confirm by checking the status files — they should show OK/WARN/FAIL, not SKIP.
