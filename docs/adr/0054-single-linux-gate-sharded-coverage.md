# ADR-0054: One sharded, traced Linux gate replaces the untraced test job and bash-coverage

**Date:** 2026-10-31
**Status:** Accepted

## Context

After ADR-0053 the `test-macos` gate finished in about 9 minutes and the Linux jobs became the long
pole: on dotfiles#411's own run `test` took 11m02s and `bash-coverage` 15m57s. Both ran the same bats
suite; `bash-coverage` ran it under the `BASH_ENV`/PS4 tracer and already refused to score a red run,
so it proved the suite passes on Linux. The untraced `test` job added three things: `make test`'s
non-bats prerequisites (`lint`, `check-lock`, `check-requirements-ci`, `test-python`,
`check-claude-md-budget`), the `Tool versions` step, and a "test count >= 840" floor.

## Decision

1. **`test-shard` is a matrix of three ubuntu legs** (30 minutes, `contents: read`). Each runs
   `scripts/bats-shard.sh <i> 3`, then `make bash-coverage` with step-env `BATS_FILES_FROM` and
   `COVERAGE_TRACE_DIR`, so it runs its list under the tracer and writes `bats_run.log` and a
   `sort -u` trace. Shard 1 also runs `make test-prereqs`.
2. **`test` is the single Linux gate** (`needs: test-shard`, `if: always()`, 10 minutes,
   `contents: write` for the badge push). It keeps the required-check name. It runs
   `scripts/ci-shard-gate.sh --with-traces`, which requires the lists to cover every test file once and
   exactly one non-empty trace per list, then `scripts/run-bash-coverage.sh --score` on the union of
   the traces, the 91% floor and the badge.
3. **The untraced `test` job, the single `bash-coverage` job and the >= 840 count floor are deleted.**
   Per-leg `scripts/ci-suite-report.sh <log> --files <list>` (executed equals declared and is above
   zero) plus the gate's coverage check prove more than the floor did.
4. **`make test` is `test-prereqs` plus `test-bats`**, the literal prerequisite list kept on the `test:`
   line; a test guards the two lists against drift.
5. **`scripts/pre-push` runs `make test` under `env -u MAKEFLAGS -u MFLAGS -u MAKELEVEL -u BATS_FILES_FROM`**,
   so an exported shard list cannot narrow the local gate.

## Consequences

- **Accepted gap (operator, 2026-10-31):** CI no longer runs the Linux bats suite untraced. The tracer
  runs `set -x` and sets `PS4` and `BASH_XTRACEFD` in every bash, and no collision with it exists in
  `lib/` or `scripts/` today. The pre-push hook still runs the suite untraced on `claude` for the
  operator's and agents' pushes; bot PRs never run pre-push, so a tracer-only difference would not show
  on them.
- The 91% floor now applies to the union of three runs on 4-vCPU runners, a different execution profile
  from one run of all files. A draft-PR headroom proof compared the union with a single traced baseline
  before merge (spec V1).
- Branch protection must drop `bash-coverage` from its required checks, an operator action at merge.
  `auto-merge`'s `needs:` is `[test, lint-macos, test-macos, powershell, secret-scan]`.
- Re-run all jobs, never failed-only, now applies to both aggregation gates (`test-macos` and `test`):
  a failed-only attempt has no lists or traces for the shards that passed.
- `always()` appears only as the `if:` of those two gates.
- A red shard uploads its traced log as `test-shard-log-<i>`, and every traced run passes
  `--print-output-on-failure`.
- Open PRs must be rebased or re-run after merge: their old runs carry the untraced `test`.

## Alternatives considered

- **Keep the untraced `test` job beside the shards:** the long pole stays at about 11 minutes.
- **Shard but score each trace alone:** a per-shard figure is not the suite's figure; only the union is.
- **Pass the list through the environment to the script:** a nested `make bash-coverage` inside a test
  inherited it (measured `not ok 162`); the Makefile passes arguments and `unexport`s the variables.

## Related

- [ADR-0037](0037-macos-suite-gates-merge.md): its Linux job list is partly superseded here
- [ADR-0053](0053-shard-test-macos-by-cpu-seconds.md): the macOS shard this mirrors
- Spec: [`docs/superpowers/specs/2026-10-31-bash-coverage-shard-design.md`](../superpowers/specs/2026-10-31-bash-coverage-shard-design.md)
- Plan: [`docs/superpowers/plans/2026-10-31-bash-coverage-shard.md`](../superpowers/plans/2026-10-31-bash-coverage-shard.md)
