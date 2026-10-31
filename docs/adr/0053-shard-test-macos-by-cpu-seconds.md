# ADR-0053: Shard test-macos across three runners, weighted by CPU seconds

**Date:** 2026-10-31
**Status:** Accepted

## Context

`test-macos` ran the whole suite as one job on `macos-latest` (3 vCPU). It is a required check
and in `auto-merge`'s `needs:`, so every PR waits on it. The last 14 successful runs took 17 to
29 minutes against a 30-minute `timeout-minutes`, a minute from the cap with no hang. dotfiles#408
needed six attempts to merge one PR.

On bare metal the same suite at `--jobs 3` takes 1415 s, inside the hosted runner's range, so the
cost is macOS process overhead and not virtualization. Splitting the files across parallel hosted
jobs divides wall-clock roughly by the shard count.

## Decision

1. **`test-macos-shard` is a matrix of three macOS legs.** Each leg runs `scripts/bats-shard.sh <i> 3`
   to write one list, `shard-<i>.files`, and runs it through `BATS_FILES_FROM` (shard 1 `make test`,
   the others `make test-bats`). The matrix list is the only place the shard count is written.
2. **`test-macos` becomes an ubuntu aggregation gate** with `needs: test-macos-shard` and
   `if: always()`. It fails unless the shard result is `success`, downloads this attempt's lists and
   runs `scripts/ci-shard-gate.sh`, which requires them to cover every test file exactly once. It is
   the one `always()` in the workflow, so the required check reports red instead of skipped.
3. **Files are packed by CPU seconds, not test count or serial seconds.** `tests/bats-weights.tsv`
   holds user+sys CPU of `bats --jobs 3 <file>` on macOS. A serial-seconds packing came out
   681 / 681 / 681 s and ran in 388 / 458 / 535 s. The trial's shards weigh 815 / 866 / 999 CPU s,
   in the same order as their wall-clock. Packing the 86 files at `ab92a62d`: count 1056 / 881 / 743
   CPU s, serial seconds 815 / 866 / 999, CPU seconds 893 / 894 / 894.
4. **One list per shard, attempt-scoped and success-only.** The list artifact is
   `test-macos-shard-<attempt>-<i>`, uploaded only when the shard passed, so a failed shard leaves
   no list and the gate's coverage check fails independently of the shard result.

## Consequences

- Target V1: over the first 10 PR runs after merge, one in a Monday Renovate window, p90 of gate
  completion with queue included is at most 12 minutes. V2 checks each shard's time per packed
  weight stays within 10% of the mean. A miss means 4 shards or the self-hosted runner.
- A dotfiles PR uses 4 of GitHub's 5 concurrent macOS slots with `lint-macos`, so etch-config or a
  second PR can queue.
- Re-run all jobs, never failed-only: a failed-only attempt has no lists for the shards that
  passed, so the gate fails by design.
- Weights are reseeded by hand per ai-config `docs/knowledge/dotfiles-bats-test-infrastructure.md`
  § `Shard weights: reseed procedure`. A stale table changes balance only, never coverage.
- The heaviest file, `tests/setup_env/linux_ubuntu.bats` at 529 CPU s, would start to bound five
  shards (536 s each), not three.

## Alternatives considered

- **Self-hosted runner on the Studio:** about 5 minutes per run, but the repo is public with 2
  forks and `pull_request` runs the PR head's workflow. Safe use needs approval policy, an
  ephemeral VM, egress rules and a queue watchdog, and 20 cores would hide the starved-runner
  condition. Kept as Phase 2.
- **Weight by `@test` count:** leaves the heaviest shard 18% above the CPU-packed one.
- **Weight by serial seconds:** misses the per-test cost of `bats --jobs` mode.
- **Raise `timeout-minutes` alone:** every PR would still wait about 22 minutes.

## Related

- [ADR-0037](0037-macos-suite-gates-merge.md): the macOS suite gates merge; its single-job shape is superseded here
- Spec: [`docs/superpowers/specs/2026-10-30-test-macos-shard-design.md`](../superpowers/specs/2026-10-30-test-macos-shard-design.md)
- Plan: [`docs/superpowers/plans/2026-10-31-test-macos-shard.md`](../superpowers/plans/2026-10-31-test-macos-shard.md)
