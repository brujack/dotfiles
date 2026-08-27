# ADR-0025: No mechanical guard for CI job timeout-minutes

**Date:** 2026-08-27
**Status:** Accepted

## Context

Until #247, no job in either workflow declared `timeout-minutes`, so every job
inherited GitHub's 360-minute default. A hung job therefore blocked `auto-merge`
with nothing reporting a cause — hit live on #223, where `powershell` stalled
30m21s inside `Install PowerShell` and needed a manual `gh run cancel` while every
other check was already green.

#247 added seven caps sized from measured p90s. That fixes the present state and
says nothing about the next job someone adds: the file reached 0 of 7 by accretion,
not by decision.

A guard test — `tests/scripts/workflow_timeouts.bats`, asserting every job in every
tracked workflow declares `timeout-minutes` — was therefore specified, and revised
across three rounds of multi-lens review. Each round's fix produced the next round's
defect:

1. Reusable-workflow (`uses:`) jobs were **exempted**. The exemption fired silently,
   so the event that would prompt anyone to verify its premise was the same event
   that hid it.
2. The exemption was replaced with a **hard failure**. SchemaStore's
   `github-workflow.json` declares `reusableWorkflowCallJob` with
   `additionalProperties: false` and no `timeout-minutes` key, so an adopter could
   neither add the key nor omit it — a gate with no green path.
3. The branch was **removed entirely**, and removing it dropped the *detection*
   rather than the coverage: the job-key matcher is shape-blind, so a `uses:` job
   matched like any other and the assertion applied to it regardless. The spec
   asserted three times that the guard "asserts nothing about reusable-workflow
   jobs" and no mechanism implemented that.

Independently, a line-oriented matcher cannot enumerate YAML. Three shapes were
found, each in about ten seconds once someone looked: a quoted key (`"deploy":`), a
key with a trailing comment (`deploy: # …`), and an inline flow job
(`quick: {runs-on: …}`). Each is invisible to `^  [^ ].*:$` while the file still
yields jobs and passes. Widening the character class fixed instances, not the class
— and the expected job-name set was derived by the very matcher whose completeness
was in question, which is the circularity ADR-0021 exists to prevent.

The failure mode compounds: because the expected set is pinned to today's names, a
new job the matcher cannot see leaves the derived set *identical*. Both assertions
green, uncapped job unreported — the guard reporting clean on its own trigger class.

Against that, the guard's measured value is zero. `ci.yml` went 2 → 6 jobs between
2026-04-02 and 2026-04-27, `pr-title-lint.yml` added its single job on 2026-05-17,
and every `.github/` commit in the four months since edits steps inside existing
jobs. A sweep found 0 of 58 dotfiles backlog rows and 0 of 151 ai-config backlog
rows proposing a new CI job.

## Decision

Ship the seven `timeout-minutes` caps. **Do not build the guard test.**

Nothing in `make test` asserts these values, and that is deliberate rather than an
oversight. An eighth job added without a cap will not be caught by anything.

The alternative was not "a better parser" but a different mechanism, and two are
recorded as viable futures rather than rejected:

1. A real YAML front end (`pyyaml`) instead of `awk` — removing the whole class of
   matcher defects, at the cost of a dependency installed in **both** the `test` and
   `bash-coverage` jobs, since both run `make test`.
2. `actionlint` as a pinned, checksum-verified CI tool per `ci.md`. It validates
   workflows generally and subsumes this check entirely.

## Consequences

**Easier.** The seven caps ship with no new dependency, no new test surface, and no
gate whose own failure mode is a false green. Reviewers reading `make test` are not
misled into believing timeouts are asserted.

**Harder.** The regression this guard was written for is now unguarded and
disclosed: nothing catches an eighth job added without a cap, and the failure would
be the same 360-minute default this ADR describes. The bet is explicit — zero job
additions in four months, zero backlog rows that would cause one.

**The bet's population is narrower than it looks, and the exception is named.** What
was counted is changes originating in a backlog. A fleet-wide tooling decision
arrives here as a per-repo PR with no backlog row anywhere, and unadopted tooling of
exactly that kind lives in standards and specs instead: `shfmt`, recorded in
`shell.md` as specified and unadopted, and `actionlint`, named above. So this ADR's
own stated remedy is the change most likely to falsify its premise.

**Required going forward.** Anyone adding a job to either workflow adds its
`timeout-minutes` by hand. Anyone reaching for a guard should read the spec's "What
was considered and dropped" section first — the three parser shapes are reproducible
in seconds and are the reason a fourth attempt at the same mechanism is not worth
making.

## Related

- Spec: [2026-08-27-ci-job-timeouts-design.md](../superpowers/specs/2026-08-27-ci-job-timeouts-design.md) — full measurements, three review rounds, dispositions
- Plan: [2026-08-27-ci-job-timeouts.md](../superpowers/plans/2026-08-27-ci-job-timeouts.md)
- Shipped as #247 (`ecd5d51`)
- [ADR-0021](0021-hand-typed-test-oracle-for-the-identity-table.md) — an oracle derived from the thing it checks cannot falsify it; the same circularity defeated this guard's job-name set
- [ADR-0019](0019-shebang-derived-lint-scope.md) — a pathspec cannot express "every tracked shell script"; the same class of scope defect, solved there by deriving from content
