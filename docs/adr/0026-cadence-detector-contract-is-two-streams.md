# ADR-0026: The cadence detector contract is two streams, and stderr is published

**Date:** 2026-08-28
**Status:** Accepted

## Context

`scripts/cadence-notify.sh` is the delivery arm for the weekly cadence LaunchAgents
installed by ADR-0024. Detection lives in another repo (`ai-config`); this script runs a
detector, turns its exit code into a verdict, counts its findings, writes a heartbeat, and
pushes to ntfy.

Counting was the problem. The wrapper computed `findings` as `grep -c .` over the
detector's stdout, which cannot distinguish a finding from a progress banner, and it
discarded stderr entirely with `2>/dev/null`.

Both halves were measured on 2026-08-28, against `ai-config`'s `ledger_drift_check.sh`:

| path | reality | reported |
| --- | --- | --- |
| findings | 31 stale entities | `"findings": 32` |
| clean | 0 findings | `"findings": 1`, every week |
| cannot-run | `ERROR: ledger binary not found` on stderr | "cannot determine", no cause named |

The clean-path row is the damaging one — it fires when nothing is wrong, so a healthy
fleet reports a finding indefinitely. It was invisible from this repo: the only heartbeat
available here came from a run that had drift, so only the findings path could be
measured. It was found by the `ai-config` session running all three paths rather than the
one this repo reported.

Two options were considered.

**Weaken the wrapper.** Stop asserting a count the wrapper cannot compute — record `lines`
rather than `findings`, drop the "N finding(s)" prefix. Self-contained, no cross-repo
dependency, and no wrong number is ever published. It costs the count, which nothing in
production currently reads (`_doctor_check_cadence` reads `ts`, `result` and
`max_age_days`).

**Enforce the contract.** The script's header already claimed that a detector "prints
findings to stdout"; the detector was violating a contract that was written down and not
stated sharply enough to be followed. Keep the count, state the contract explicitly, and
fix the detector.

The operator chose to enforce. A third option — a machine-readable `CADENCE-FINDINGS: N`
line — was rejected as more protocol than the problem warrants.

## Decision

The detector contract is **two streams**, stated in the script header and enforced by
convention rather than by code:

- **stdout is findings-only.** One finding per line, nothing else — no progress lines, no
  banners, no diagnosis. This is the channel `_count` measures.
- **stderr is the diagnosis channel.** Captured to its own temp file, surfaced in the ntfy
  push under `Cause:` on the incomplete path and `Diagnostics:` on the held path, and
  never counted.

The wrapper's counting is unchanged and is correct exactly while detectors honour this.
`ai-config#227` moved that detector's banners to stderr, leaving its stdout at 9/0/0 across
findings/clean/cannot-run.

Two supporting decisions fall out of it:

**stderr is capped at the last 20 lines, because it is now published.** `security-review`
raised this: a stream previously discarded is now POSTed to the ntfy endpoint, and stderr
is where tooling prints stack traces, environment dumps and failing URLs. The cap bounds an
accidental dump. It does not make the stream safe, so the header says outright that a
detector must not print credentials there — it was discarded before this change, so nothing
written to it was written on the assumption that anyone would read it.

**A `mktemp` failure takes the INCOMPLETE path with a heartbeat, not an early return.** The
file's existing invariant is that a run that errored and a run that never happened must not
look alike; that distinction is the only reason `doctor` reads the heartbeat at all. A bare
`return 1` would have written nothing, which is indistinguishable from an agent that never
fired. `_RHN_MKTEMP` seams the binary so that branch is reachable in tests on both
platforms — BSD `mktemp` with no template ignores `TMPDIR`, so the obvious seam drives it on
GNU and is inert on every development mac.

## Consequences

**Easier.** A detector that cannot determine an answer now says why, in the push. A
detector that finds things and warns while doing it reports both, in separate sections. The
count means what it says wherever the contract holds.

**Harder.** The count's correctness now depends on a repo this one does not own, and
nothing here can detect a violation — a banner on stdout is indistinguishable from a
finding, by construction. That is the accepted cost of the choice: the alternative removed
the dependency by removing the count. Anyone debugging a wrong count should suspect the
detector's stdout before this wrapper.

**Required going forward.** Any new detector wired into a cadence agent must keep stdout to
findings only and route everything else to stderr, and must not print credentials or
environment dumps there. Read the contract in `scripts/cadence-notify.sh`'s header before
writing one.

**Not covered.** The detector's exit-code contract (0 clean, 1 findings, 2 cannot-determine)
is documented in the same header and was already being violated in a different way — a
detector returning 1 for both *found* and *could-not-run* — which `ai-config#226` fixed
independently. This ADR does not change that contract, only the stream half.

## Related

- [ADR-0024](0024-launchagent-for-the-renovate-held-cadence.md) — the cadence agents this script delivers for
- [ADR-0014](0014-state-ledger-cmdb-integration.md) — the ledger whose drift the first real detector reports on
- dotfiles PR #249 — the implementation
- ai-config PR #227 — the detector-side half; PR #226 — the exit-code half
