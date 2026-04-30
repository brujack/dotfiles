---
name: Bash ERE regex does not match digits with [A-Z_]
description: Bash [[ =~ ]] regex won't match HAS_K8S with [A-Z_]+ — must include digits in character class
type: feedback
---

When parsing capability tags like `HAS_K8S` (which contains a digit) from shell text, the grep pattern `^[A-Z_]+$` will silently reject it. Use `^[A-Z][A-Z0-9_]+$` instead.

Also: bash `[[ str =~ pattern ]]` with `\[` (escaped bracket) failed to match literal `[` in the pattern on macOS. Use `sed 's/.*# \[//;s/\].*//'` + `grep -E '^[A-Z][A-Z0-9_]+$'` to extract tags reliably.

**Why:** `HAS_K8S` has a digit (`8`) which `[A-Z_]` doesn't cover. The silent failure caused the tag to be ignored and the package to be included in drift results despite the capability being unset.

**How to apply:** Any time parsing SCREAMING*SNAKE_CASE identifiers that may contain digits, use `[A-Z]A-Z0-9*]+`not`[A-Z_]+`.
