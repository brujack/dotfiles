## Linting

Every project Makefile must have a `lint` target, and `test` must depend on it (`test: lint`).

- Python: `ruff check .`
- Rust: `cargo clippy -- -D warnings`
- PowerShell: `Invoke-ScriptAnalyzer` via PSScriptAnalyzer (use a `PSScriptAnalyzerSettings.psd1` to exclude rules that can't be changed, e.g. `PSAvoidUsingInvokeExpression` for official bootstrapper commands)

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
