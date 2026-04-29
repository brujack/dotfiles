---
name: Test that conditional file writes don't create the file on the false branch
description: Functions that conditionally write a file must have a test asserting the file is absent when the condition is false
type: feedback
originSessionId: 5df32ae8-b5d6-4a2f-91ba-7c1898f285c3
---

For every function that conditionally writes a file (e.g. a detail block only written on WARN), the "condition false" test must assert `[ ! -f path/to/file ]` to confirm the file was not created.

**Why:** During brewfile-drift final review, the code reviewer caught that the OK-path test didn't assert `[ ! -f "${_UPDATE_TMPDIR}/detail_brew-drift" ]`. Without it, a regression where the detail file is always written would pass all tests. The absence assertion is as important as the presence assertion.

**How to apply:** When writing a test for the clean/skip/ok path of a function that writes a detail or output file on its warn/fail path, always include `[ ! -f <file> ]` to lock in the negative case.
