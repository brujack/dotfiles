# ADR-0021: Hand-typed test oracle for the identity table

**Date:** 2026-08-18
**Status:** Accepted

## Context

ADR-0020 established `config/profiles.sh` as the single hostname table, but its Decision
point 3 — `lib/detect_env.sh` "derives the same eight variables from the table" — was
aspirational when written. Both readers still resolved the legacy identity variables through
hardcoded eight-arm `case` statements, and so did both test suites. Four hand-typed copies of
the same hostname→variable mapping.

dotfiles#223 collapsed them: `config/profiles.sh` gained a third map, `PROFILE_LEGACY`, read
by `config/profiles.zsh` (via `export`) and `lib/detect_env.sh` (via `readonly`). Three of the
four copies are gone.

The fourth is deliberate, and this ADR exists because it will look like drift.

`tests/helpers/legacy_oracle.bash` is the shared test oracle, and it is **hand-typed rather
than derived from `PROFILE_LEGACY`**. A future reader who notices one hardcoded table
remaining beside a production table has every reason to "finish the job" by sourcing
`config/profiles.sh` in the oracle. That edit removes the only thing that can detect a class
of defect the rest of the suite is blind to.

## Decision

**The test oracle stays hand-typed. It must not source `config/profiles.sh`, must not read
`PROFILE_LEGACY`, and must not reach either by any indirect route** — `eval`, a
runtime-constructed variable name, or sourcing something that itself sources the table.

The reasoning is measured, not stylistic. Consider a swap of two entries — `[laptop]` and
`[laptop-1]` both to `STUDIO`, `[studio]` and `[studio-1]` both to `LAPTOP`. Every name is
still present, the key count is unchanged, and the table remains internally self-consistent,
so every permutation-invariant assertion in the suite still passes. Measured against a clean
archive of `21671b8`, isolating the two oracle-based per-host assertions:

| oracle      | table            | zsh per-host | bash per-host |
| ----------- | ---------------- | ------------ | ------------- |
| hand-typed  | intact           | green        | green         |
| hand-typed  | consistent swap  | **FIRES**    | **FIRES**     |
| derived     | consistent swap  | green        | green         |
| derived     | intact           | green        | green         |

Row 3 is the decision. A derived oracle follows the table it is checking, so production and
oracle agree on the swapped values and both assertions pass — the defect ships.

`tests/zshrc.d/cross_shell.bats` cannot help here either, and for the same underlying reason
one level out: it compares the two *productions* to each other, so when both read the same
wrong table they agree. Two implementations that agree can be wrong together.

## Consequences

**Adding a machine now costs 3 edits across 2 files** — the wired/wireless pair in
`PROFILE_MAP`, the same pair in `PROFILE_LEGACY`, and a `case` arm in the oracle. Before
#223 it was 5 edits across 5 files, so this is still a reduction, but it is not the
single-file edit `config/profiles.sh`'s header comment claimed before #223 corrected it.

**The duplication is load-bearing and must be defended in prose**, since nothing mechanical
can distinguish it from drift. `CLAUDE.md` carries a do-not-"fix" warning and the oracle file
carries the measurement. Both are part of the decision, not commentary on it.

**A malformed mutation will over-report, and did.** Swapping only the non-suffixed keys
(`[laptop]` without `[laptop-1]`) leaves the table internally *inconsistent*, which the
wireless-twin tests catch without reference to the oracle at all. That mutation reddens 3
tests rather than 2 and therefore demonstrates twin-consistency, not oracle independence. The
oracle's own comment documented that malformed variant through three successive revisions
before the 2×2 above was measured. Any future re-verification must keep the table
self-consistent, or it is testing something else.

**This closes the mirror of a gap ADR-0019 records as open.** There, nothing pins that
`SHELL_FILES` is *derived* rather than *enumerated* — a hardcoded list of today's correct
files would pass every case. Here the risk runs the other way, that a hand-typed oracle is
quietly replaced by a derived one, and the per-host assertions above are what pin it.

## Related

- [ADR-0020](0020-single-identity-table-across-bash-and-zsh.md) — the single table; this ADR
  completes its Decision point 3 and adds `PROFILE_LEGACY`
- [ADR-0019](0019-shebang-derived-lint-scope.md) — records the mirror gap, derived-vs-enumerated
- `docs/superpowers/specs/2026-08-17-zsh-legacy-identity-consolidation-design.md` — the spec,
  its Decision 1, and three rounds of Multi-Lens Review
- `docs/superpowers/plans/2026-08-17-zsh-legacy-identity-consolidation.md` — the plan
- `~/.claude/standards/behavior.md` — "a check derived from the same decision as the thing it
  checks cannot falsify it", the general principle this is one instance of
- `~/.claude/standards/tdd.md` pitfall F — hand-built fixtures validated against the real tool
