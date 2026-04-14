# Bash / Shell PR Review Reference

## Security
- All variables quoted: `"$VAR"` not `$VAR` — unquoted variables allow word splitting and globbing
- No `eval` on user input or external data
- Temporary files created with `mktemp` — never predictable names in `/tmp`
- No world-writable files or directories created (`chmod 777`)
- Sensitive values not passed as command-line arguments (visible in `ps`)
- Credentials not echoed or logged

## TDD / Tests
- `bats` (Bash Automated Testing System) tests expected for scripts with logic
- `shellcheck` is the minimum bar — must pass with no errors
- Test both success and failure paths; test with and without required env vars

## Code Quality
- `set -euo pipefail` at the top of every non-trivial script
  - `-e`: exit on error
  - `-u`: error on unset variables
  - `-o pipefail`: catch failures in pipelines
- Functions defined before use; long scripts broken into functions
- No magic numbers — use named variables
- `readonly` for constants
- Heredocs preferred over multi-line echo chains
- Logging to stderr (`>&2`), output to stdout — keep them separate

## Logic
- Exit codes returned correctly (`exit 0` / `exit 1`)
- Pipelines: `PIPESTATUS` checked when pipeline exit code matters
- Arithmetic: `$(( ))` not `expr`
- Array handling: quote expansions `"${arr[@]}"`
- `[[ ]]` preferred over `[ ]` for conditionals

## Commands to run
```bash
shellcheck **/*.sh 2>&1      # or specific files
bash -n script.sh 2>&1       # syntax check
bats tests/ 2>&1             # if bats tests exist
```
