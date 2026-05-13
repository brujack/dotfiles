## Shell Scripts

### Idempotency

Always check before acting — guard installs, symlinks, directory creation, and file modifications with existence checks:

- Use `command -v tool` before installing, `[[ -f path ]]` before writing, `[[ -L link ]]` before symlinking
- Never append to a file without first checking the content isn't already there
- Tests must verify idempotency: calling a function twice produces the same result as calling it once

### Script Standards

- **Shebang:** `#!/usr/bin/env bash` — always, no exceptions (never `#!/bin/bash` or `#!/bin/sh`)
- **No `set -e`** — handle errors explicitly with `|| exit 1` or return code checks. `set -e` has unpredictable behavior with conditionals, pipes, and subshells. The only exception is git hooks (pre-commit, pre-push) where `set -e` is acceptable for fail-fast behavior.
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

### Common Pitfalls

**Semver string comparison**

Never use `[[ ${VER} < "1.21" ]]` to compare version strings. Bash `[[` uses lexicographic order: `"1.16" < "1.21"` is **false** because `'6' > '2'` in ASCII. Extract the integer component and use `-lt`/`-gt`:

```bash
local _minor
_minor=$(printf '%s' "${VER}" | cut -d. -f2)
if [[ ${_minor} -lt 21 ]]; then ...
```

**Regex character classes for SCREAMING_SNAKE_CASE**

`[A-Z_]+` silently rejects identifiers containing digits (`HAS_K8S`, `USE_GO119`, etc.). Use `[A-Z][A-Z0-9_]+` whenever matching all-caps identifiers that may contain digits.
