## Linting

Every project Makefile must have a `lint` target, and `test` must depend on it (`test: lint`).

- Python: `ruff check .`
- Rust: `cargo clippy -- -D warnings`
- PowerShell: `Invoke-ScriptAnalyzer` via PSScriptAnalyzer (use a `PSScriptAnalyzerSettings.psd1` to exclude rules that can't be changed, e.g. `PSAvoidUsingInvokeExpression` for official bootstrapper commands)

## Code Standards

### Idempotency

**Idempotency is a cornerstone of all shell, Ansible, and Terraform work.** Running the same operation twice must produce the same result as running it once — no errors, no duplicate state, no unintended side effects. If a script, playbook, or config cannot be run twice safely, that is a bug — not an acceptable trade-off. See `shell.md`, `ansible.md`, and `terraform.md` for language-specific rules.

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
