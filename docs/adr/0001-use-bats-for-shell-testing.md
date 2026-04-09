# ADR-0001: Use BATS for Shell Testing

**Date:** 2026-03-27
**Status:** Accepted

## Context

`setup_env.sh` was untested. Changes risked silently breaking machine setup. A testing framework was needed that could test bash scripts natively without a heavy runtime or translation layer. Options considered: BATS, shunit2, custom test harness.

## Decision

Use BATS (Bash Automated Testing System) for all shell script tests. Tests live in `tests/`, organized by script. Mocking is done via PATH injection — mock executables in `tests/mocks/` are prepended to `$PATH` in test setup, intercepting calls to `brew`, `apt-get`, `curl`, etc. Mock behavior is controlled via `MOCK_*` environment variables.

## Consequences

- Tests run in a real bash environment — no translation layer, no surprises from shell-to-language conversion.
- Lightweight: single executable, no runtime dependencies beyond bash.
- PATH-injected mocks allow simulating external tools without network or system access.
- Limited assertion vocabulary compared to xUnit frameworks (`run` + `$status` + `$output`).
- Mock management requires discipline: `MOCK_*` env vars and mock executables must be kept in sync with what real tools actually output.

## Related

- [Spec: bats-testing](../superpowers/specs/2026-03-27-bats-testing-design.md)
