---
name: diff trailing-newline mismatch in BATS tests
description: When testing diff-based logic, a no-trailing-newline state file vs a multi-line string with same content-as-first-line produces a `c` (change) diff not `a` (append), making the line appear in `>` output unexpectedly
type: feedback
---

Use the prepend pattern when testing `diff`-based "what's new" logic: state file has the existing content, new content has the new entry at the TOP (like a real CHANGELOG). Avoid `"old line" vs "old line\nnew line"` — the first line of the multi-line string has a trailing newline (because a second line follows), while the state file line doesn't, so `diff` sees them as changed not appended.

**Why:** Discovered when test `extract_new_content: returns only added lines` failed: `printf "old line" > STATE_FILE` writes no trailing `\n`, but `"old line\nnew line"` as an argument makes `old line` the first of two lines (so it has `\n`). diff outputs `c` instead of `a`, making "old line" appear in `>` output.

**How to apply:** When writing diff-based tests, always use the real-world append pattern: existing content at the bottom, new content prepended at the top. Never compare a single-line no-newline file against a multi-line string containing that same line.
