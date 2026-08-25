# ADR-0024: A LaunchAgent for the Renovate held-major cadence

## Status

Accepted — 2026-08-25

## Context

Major dependency updates stopped auto-merging on 2026-08-24/25 (verified 9/9 in
`renovate.json`, 8/8 in CI). That converted *merged unreviewed* into *open
indefinitely*: `renovate-triage` is invoked by hand, has no cadence and no owner, and at
the time of writing has never run against a real held major because none has ever
existed — 32 of 32 Renovate PRs fleet-wide are merged.

Something has to ask. Three routes were considered and two failed on facts:

- **GitHub Actions** cannot see the other eight repos. `GITHUB_TOKEN` is repo-scoped,
  `gh secret list -R brujack/ai-config` returns empty, and no existing workflow attempts a
  cross-repo read. It needs a new long-lived PAT the operator must mint.
- **`CronCreate`** is session-only and in-memory, gone when the session exits, 7-day
  auto-expiry. A within-session reminder, not infrastructure.

**launchd on the Studio was chosen by the operator.** `gh` is already authenticated there
for all nine repos — demonstrated, not assumed — so no credential is created.

## Decision

**A LaunchAgent on the Studio, plus a heartbeat read by `doctor`.** Two channels, two
purposes:

| channel | carries | fires |
| --- | --- | --- |
| ntfy push | signal — held majors, or a check that could not answer | only when there is something to say |
| heartbeat file → `_doctor_check_renovate_cadence` | liveness — *did this run at all* | on inspection |

**Detection and delivery are separate programs.** `ai-config` owns the detector, which
prints findings to stdout and exits `0` (clean) / `1` (held) / `2` (incomplete, and it
dominates `1`). `dotfiles` owns `scripts/renovate-held-notify.sh`, which maps that to a
push and a heartbeat.

**This is the first LaunchAgent in `dotfiles`**, hence an ADR. It installs only on the
Studio, and that is not arbitrary: the check is fleet-wide, so a second machine running it
produces duplicate pushes for the same PR — the fastest way to train the operator to mute
the channel.

## Consequences

**The design's whole shape comes from a local counter-example.** `ai-config`'s
`ledger-drift.yml` runs weekly and its alerting has never fired on any machine: its comment
defers real alerting to "an enrolled machine", and `launchctl`/`crontab` on the Studio have
nothing, while across every tracked file in all nine repos `ledger_drift_check` has exactly
one executing invocation — the CI job that says it is not the real one. **The honest
scoping is what hides it**: a reader meets the comment, is reassured, stops looking.

Three properties follow directly from that:

- **A weekly "still alive" push was rejected.** It trains the operator to ignore the
  channel, which destroys the signal arm. Liveness goes in a file instead.
- **The detector must not alert.** `ledger_drift_check.sh` makes its own ntfy call, so an
  unset `NTFY_URL` degrades detection *and* delivery together and still returns 0 — "no
  drift" and "no channel" render identically. Here a missing channel prints to stderr and
  never touches the exit code, pinned by two tests.
- **Unknown is not clean, anywhere.** A missing detector, an unexpected exit code, an
  unparsable heartbeat and a stale heartbeat all FAIL. `incomplete` on a *fresh* run also
  fails `doctor`: "nothing held" and "could not tell" are exactly the pair this design
  exists to keep apart.

**The control is the hard part and it does not live here.** With zero majors held anywhere,
`exit 0` and a probe that queries nothing are byte-identical, and `exit 0` is the expected
result for at least a week — precisely when nobody looks. The detector therefore asserts
each repo returns ≥1 row for `--state all` (independently known non-empty, 32 fleet-wide)
and treats zero there as a broken query rather than a quiet repo. **That control does not
depend on a held PR ever existing**, which is what makes the cadence verifiable from day
one. Owned by `ai-config`; specified in
`ai-config/docs/superpowers/specs/2026-08-25-renovate-held-cadence-design.md`.

**Accepted costs.** It does not run when the Studio is off. It is machine-scoped, so a
rebuild must re-run `setup_env.sh -t setup_user` — which the stale-heartbeat check catches
within 8 days rather than silently. And it may have no subject: nothing has ever been held.
Building before the first held major is deliberate — a cadence written after a PR rots is
written in response to the rot.

**Every guard is mutation-verified.** Five mutants against the doctor arm and four against
the wrapper; two survived on first pass and both were real. One found a decorative return
value hiding an untested delivery-failure branch; the other found a test going red for a
different guard than the one it named — the cause-isolation defect, recurring in a test
written the same session it was fixed elsewhere.

## Related

- `ai-config/docs/superpowers/specs/2026-08-25-renovate-held-cadence-design.md` — the design
- `ai-config/docs/superpowers/plans/2026-08-25-stop-major-auto-merge.md` — the precondition
- ADR-0017 — pre-push fail-closed, the same unknown-is-not-safe posture
