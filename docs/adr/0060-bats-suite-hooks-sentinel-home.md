# ADR-0060: Bats suite hooks give every run a sentinel HOME

**Date:** 2026-11-21
**Status:** Accepted

## Context

Security audit finding F15 (2026-11-16) showed a test touching the operator's real `HOME`.
Isolation was a per-file convention: a file redirected `HOME` only if it sourced
`tests/helpers/common.bash` or did so itself. 44 of 114 bats files do not source `common.bash`,
so the convention left them unprotected, and a new file was unprotected until someone remembered.

Alternatives considered (spec, Problem, Design and External Review):

- **A wrapper script around the Makefile's bats lines.** Designed, then replaced. Direct `bats`
  runs (the form the Studio repro uses, and what an operator types) escaped the wrapper, and the
  tests that assert the recipe text kept breaking whenever the lines changed.
- **A residue gate in teardown** that fails when a test leaves files in the sentinel `HOME`.
  Rejected (external review F1.1): the `HOME` swap is what protects the real home, so the gate
  would fire on writes that harmed nothing and would re-impose the per-file "redirect `HOME` in
  `setup()`" convention this decision replaces. Its one benefit, keeping one test's leftovers
  from affecting another in the same run, is unmeasured and did not justify the apparatus.

## Decision

Use bats' own suite hooks. `tests/helpers/suite_isolation.bash` defines `setup_suite` and
`teardown_suite`, and a `setup_suite.bash` in each of the four test directories sources it, so
every bats invocation, wrapped or direct, runs them.

- `setup_suite` creates a throwaway sentinel directory and exports `HOME`, the XDG directories
  and `GIT_CONFIG_GLOBAL`/`GIT_CONFIG_SYSTEM` (`/dev/null`) pointing into or away from it.
- `teardown_suite` only guards and removes the sentinel: it refuses to remove anything that is
  not the directory `setup_suite` made, and runs no residue check.

## Consequences

- Direct `bats` runs are covered, with no wrapper and no recipe-text tests to maintain.
- A new test directory needs its own `setup_suite.bash`; `tests/suite_isolation.bats` fails
  until it has one.
- A write that bypasses `HOME` (an absolute path, a hard-coded `/tmp` name) is not prevented.
  The spec's measurement V7 reports it; this ADR does not claim to stop it.
- Reference detail (the `_BATS_SENTINEL_TMP_ROOT` seam, the unset-first rule) lives in
  `ai-config/docs/knowledge/dotfiles-test-seams.md`.

## Related

- Spec: [bats-sentinel-home](../superpowers/specs/2026-11-21-bats-sentinel-home-design.md)
- Plan: [bats-sentinel-home](../superpowers/plans/2026-11-21-bats-sentinel-home.md)
- F15 fix: dotfiles#475
