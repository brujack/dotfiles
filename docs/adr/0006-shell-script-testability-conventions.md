# ADR 0006: Shell Script Testability Conventions

**Date:** 2026-04-11
**Status:** Accepted

## Context

Shell scripts in personal repos range from simple utilities to complex bootstrap and setup scripts. Testing these scripts requires the ability to:

1. Source individual functions without executing the script's main logic
2. Mock external commands (brew, curl, sudo, apt-get) via PATH injection
3. Test each branch independently without running the entire script

Several conventions were evolving informally across repos:

- `setup_env.sh` already used a sourcing guard (`[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0`)
- `bootstrap_mac.sh` used `#!/bin/bash` (system bash) and `set -e`, making it untestable
- `bootstrap_linux.sh` used `#!/usr/bin/env bash` but also `set -e`
- No consistent standard existed for when and how to make scripts testable

`set -e` causes subtle issues: it interacts unpredictably with conditionals (`if cmd; then`), pipelines, command substitutions, and functions. These edge cases make scripts harder to reason about and test.

## Decision

All shell scripts across personal repos must follow these conventions:

1. **Shebang:** Always `#!/usr/bin/env bash` — never `#!/bin/bash` or `#!/bin/sh`. This ensures the script uses the user's preferred bash (e.g., Homebrew bash 5 on macOS instead of system bash 3.2).

2. **No `set -e`:** Handle errors explicitly with `|| exit 1`, return code checks, or `|| return 1`. The only exception is pre-commit hooks, where `set -e` is acceptable for fail-fast behavior since hooks are not unit-tested.

3. **Sourcing guard for testability:** Every script that will be tested must extract logic into functions and use a sourcing guard so tests can source the file without executing it:

   ```bash
   #!/usr/bin/env bash
   my_function() { ... }

   # Allow sourcing for testing without executing
   [[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0

   my_function "$@"
   ```

4. **Function extraction:** Complex scripts should break their logic into small, independently testable functions. The script body becomes a thin orchestrator that calls functions in sequence.

## Consequences

**Positive:**
- All scripts become testable via BATS with PATH-injected mocks
- Each branch/condition can be tested independently
- Consistent patterns reduce cognitive overhead when moving between repos
- Explicit error handling is easier to reason about than `set -e` behavior

**Negative:**
- Existing scripts (`bootstrap_mac.sh`, `bootstrap_linux.sh`) need refactoring
- Slightly more verbose than `set -e` for simple linear scripts
- Developers must remember the sourcing guard pattern

**Migration:**
- Existing scripts are updated as they are touched (no bulk migration)
- `bootstrap_mac.sh` and `bootstrap_linux.sh` are the first scripts to be refactored under this ADR

## Related

- [ADR 0001](0001-use-bats-for-shell-testing.md) — BATS testing framework (complements this ADR)
- [ADR 0004](0004-lib-modular-structure-for-setup-env.md) — lib/ modular structure (established the sourcing guard pattern)
