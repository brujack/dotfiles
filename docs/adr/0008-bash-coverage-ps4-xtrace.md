# ADR-0008: Use PS4 Xtrace for Bash Coverage Measurement

- **Date:** 2026-06-01
- **Status:** Accepted

## Context

The dotfiles bash test suite uses BATS (bats-core) to test `setup_env.sh` and its `lib/*.sh` modules. Adding a coverage gate to CI required a mechanism to measure which lines in those shell scripts were executed during the test run.

Three standard approaches were tried and rejected before settling on PS4 xtrace:

1. **kcov (ptrace-based):** kcov works for standalone bash scripts invoked directly, but bats-core forks isolated subshells for each test. Those subshells escape kcov's ptrace attach. Zero coverage data was produced even when kcov was running. Building kcov from source in CI (cmake + libelf + libdw + libiberty) added ~5 minutes to each run with no payoff.

2. **bashcov (LINENO-based):** bashcov is incompatible with bats-core. bats hardcodes a UUID (`608a9069-2672-4fa2-a0e1-2823af783b95`) in its temp file paths; bashcov's LINENO parser chokes on it and produces no output.

3. **BASH_ENV + DEBUG trap:** bats-core overrides the DEBUG trap with its own `bats_debug_trap`. Any custom DEBUG trap set via `BASH_ENV` is replaced at bats startup and never fires.

The PS4 xtrace approach works because bats does not clear `set -x` or redirect `BASH_XTRACEFD`. A tracer script installed via `BASH_ENV` sets `BASH_XTRACEFD=9`, opens a named pipe on fd 9, and a background `grep` process filters the raw trace lines in real time — keeping disk usage at ~200K filtered lines instead of ~33M raw lines. The filtered trace is then parsed post-run to count covered vs coverable lines per file.

**macOS vs Linux runner choice:** The initial CI job ran on `macos-latest` since the xtrace approach was developed locally on macOS. macOS runners queue 30–60+ minutes. PS4 xtrace has no macOS-specific dependencies — `BASH_ENV`, `BASH_XTRACEFD`, and named pipes are standard bash features available on ubuntu-latest. The job was switched to `ubuntu-latest` in the same PR.

## Decision

Use PS4 xtrace (`BASH_XTRACEFD`) as the sole bash coverage mechanism for the dotfiles test suite.

Implementation:

- `scripts/bash-tracer.sh` — installed via `BASH_ENV`; sets `PS4` to emit `BASH_SOURCE:LINENO` and redirects trace to fd 9
- `scripts/run-bash-coverage.sh` — sets up the named pipe, runs `bats --recursive tests/`, drains and parses the trace, reports per-file and overall coverage
- `make bash-coverage` — local measurement target
- `make push-bash-coverage` — measurement + badge push to `coverage-data` branch
- CI `bash-coverage` job on `ubuntu-latest` — runs `make bash-coverage`, fails if overall coverage < 90%, publishes badge JSON

The gate is **90% overall** (not per-file). Per-file floors are defined in `CLAUDE.md` but not yet enforced individually in CI.

Do not attempt kcov, bashcov, or BASH_ENV+DEBUG trap in this repo. All three were confirmed broken with bats-core (see Context above). These dead ends are documented in `CLAUDE.md` to prevent future agents from re-trying them.

## Consequences

**Positive:**

- Coverage measurement works and is accurate — 92% measured at 726 tests as of 2026-06-01
- CI gate blocks merges when coverage drops below 90%
- Named-pipe filtering keeps trace output manageable without sacrificing accuracy
- `ubuntu-latest` runners avoid the 30–60 min macOS queue delay

**Negative / constraints:**

- Some lines are structurally non-traceable by PS4 xtrace:
  - Lines inside `[[ "${BASH_SOURCE[0]}" == "${0}" ]]` blocks are not traced by subprocess bats invocations (fd 9 not inherited)
  - Multi-line array literals, `usage()` heredoc content, and multi-line curl continuation lines are not emitted by bash xtrace
  - Function declaration lines (`funcname() {`) are not consistently traced across bash versions
  - These ceilings are documented per-file in `CLAUDE.md` — do not waste time writing tests to exceed them
- Coverage measurement runs the full BATS suite; no sub-suite option currently

## Related

- ADR-0001: Use BATS for shell testing
- ADR-0006: Shell script testability conventions
- `scripts/run-bash-coverage.sh` — implementation
- `scripts/bash-tracer.sh` — PS4 tracer
- `CLAUDE.md` §Testing > Coverage > Bash — per-file floors, ceilings, and structural non-traceables
- `memory/project_bash_coverage.md` — current coverage state and history
