# ADR-0008: Use PS4 Xtrace for Bash Coverage Measurement

- **Date:** 2026-06-01
- **Status:** Accepted (amended 2026-08-07 — see Amendment below)

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

- Coverage measurement works — 92% measured at 726 tests as of 2026-06-01. **The word "accurate" in the original text was wrong and is retracted; see the Amendment below.** That figure was computed over a hand-maintained 13-file subset of 36 tracked shell sources
- CI gate blocks merges when coverage drops below 90%
- Named-pipe filtering keeps trace output manageable without sacrificing accuracy
- `ubuntu-latest` runners avoid the 30–60 min macOS queue delay

**Negative / constraints:**

- Some lines are structurally non-traceable by PS4 xtrace:
  - Lines inside `[[ "${BASH_SOURCE[0]}" == "${0}" ]]` blocks are not traced by subprocess bats invocations (fd 9 not inherited)
  - Multi-line array literals, `usage()` heredoc content, and multi-line curl continuation lines are not emitted by bash xtrace. **The array-literal case is no longer treated as a per-file ceiling — it is excluded from the denominator as of 2026-08-07; see the Amendment.** The heredoc and curl-continuation cases remain unaddressed
  - Function declaration lines (`funcname() {`) are not consistently traced across bash versions
  - The remaining ceilings are documented per-file in `CLAUDE.md` — do not waste time writing tests to exceed them
- Coverage measurement runs the full BATS suite; no sub-suite option currently

## Amendment (2026-08-07)

The PS4-xtrace decision stands. Two things this ADR asserted did not.

**The accuracy claim was false when written.** `INCLUDE_FILES` was a hand-maintained
array naming 13 files against 36 tracked `.sh` sources, so "92% accurate" described 36%
of the repo. A literal list cannot fail loudly here: an omitted file is absent from the
numerator *and* the denominator, so leaving one out does not lower the percentage — it
leaves it unchanged. `lib/git_hooks.sh` was missed exactly that way and only surfaced
because someone noticed its absence from the report by eye; `lib/package_capture.sh`
stayed missing afterwards. The set is now derived at run time from `git ls-files` over
`setup_env.sh`, `config/*.sh`, and `lib/*.sh`, and the script exits non-zero rather than
measuring a short set. The predicate is *reached by the suite* — `config/` qualifies
because `lib/detect_env.sh` sources `config/profiles.sh` and `lib/git_hooks.sh` sources
`config/hook_repos.sh`.

**The ceiling policy is reversed for two construct classes.** This ADR listed multi-line
array literals among lines "not emitted by bash xtrace" and directed readers not to waste
time testing them. That guidance was correct about the mechanism and wrong about the
remedy: a line no instrument can ever reach does not belong in the denominator at all.
Counting it reports a permanent shortfall as though it were a testing gap, and every
reader who checks the file concludes it is under-tested. Two classes are now excluded,
each verified against real `bash -x` output rather than assumed:

- multi-line `python3 -c "..."` bodies — 54 of `lib/package_capture.sh`'s 107 counted
  lines, which is why that file read 22% against a ceiling it could not reach
- multi-line array literals — `declare -A M=(` … `)` traces as one `M=([a]=1 [b]=2)`
  line; 13 of `config/profiles.sh`'s 15 counted lines and 8 of `lib/helpers.sh`'s

Single-line forms of both are ordinary commands and still count. `usage()` heredoc
content and multi-line curl continuations are the same class and remain **unaddressed** —
two heredoc openers exist in the instrumented set today (`lib/workflows.sh` and
`lib/helpers.sh`), so the residual inflation is small but real.

Post-amendment: 2449/2688 = 91% at 1161 tests. The gate stays at 90%. That the figure
matches the original 91% is a coincidence of two different denominators, not evidence the
old number was right.

## Related

- ADR-0001: Use BATS for shell testing
- ADR-0006: Shell script testability conventions
- `scripts/run-bash-coverage.sh` — implementation
- `scripts/bash-tracer.sh` — PS4 tracer
- `CLAUDE.md` §Testing > Coverage > Bash — per-file floors, ceilings, and structural non-traceables
- `memory/project_bash_coverage.md` — current coverage state and history
