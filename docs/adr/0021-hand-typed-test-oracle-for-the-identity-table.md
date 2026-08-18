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

The reasoning is measured, not stylistic. Consider a swap of two entries — `[reception]` and
`[reception-1]` both to `RATNA`, `[ratna]` and `[ratna-1]` both to `RECEPTION`. All 13 keys
remain, all eight names remain, the value multiset is unchanged, and the table stays
internally self-consistent, so every permutation-invariant assertion in the suite still
passes. Measured with one fresh `git archive` per cell and the baseline verified green before
any mutation was believed, isolating the two oracle-based per-host assertions:

| oracle      | table               | zsh per-host | bash per-host |
| ----------- | ------------------- | ------------ | ------------- |
| hand-typed  | intact              | green        | green         |
| hand-typed  | `reception<->ratna` | **FIRES**    | **FIRES**     |
| derived     | `reception<->ratna` | green        | green         |
| derived     | intact              | green        | green         |

Row 3 is the decision. A derived oracle follows the table it is checking, so production and
oracle agree on the swapped values and both assertions pass — the defect ships. Under this
swap the hand-typed oracle produces exactly those two reds and nothing else across all four
affected suites; a derived one produces none.

**Why this pair and not `laptop<->studio`, which the first version of this ADR used.** That
version's Row 3 was wider than its measurement: two further detectors catch a
`laptop<->studio` swap and fire *even when the oracle is derived* — a hardcoded `"STUDIO"`
literal in `tests/zshrc.d/profiles.bats` and a studio-specific assertion in
`tests/zshrc.d/unit.bats`. So "the defect ships" was false for that pair; the suite still
went red, just not via the oracle. Measured over `tests/**` `.bats`/`.bash` excluding the
oracle: `STUDIO` on **66 lines** (68 occurrences), `LAPTOP` on **43 lines** (45) — line counts,
since `grep -c` counts lines rather than matches, and a receipt on its fourth revision because
its numbers were wrong should say which it means. Those counts include real per-host
assertions. `reception` and
`ratna` appear only as members of the eight-name set — in `unset` isolation lists, in
`for v in <all eight>` loops, and in the set-equality want-list — never as "host X must
resolve to Y", which is what makes them the pair that isolates the variable under test.

Choosing a mutation that isolates the variable is not the same as re-wording a mutation to
preserve a false count. An earlier revision of the oracle's own comment warned against the
latter, correctly, and that warning does not apply here.

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

**Choosing the mutation is the hard part, and it took four attempts.** The receipt for this
decision was wrong four times, and each revision fixed the previous one's *number* while
leaving the *question* unexamined:

1. "Exactly 2 tests fail, and only an oracle notices." Wrong count.
2. "3 tests fail; the third is a `studio`/`studio-1` snapshot comparison." Right count, but the
   mutation swapped only the non-suffixed keys, leaving the table internally *inconsistent* —
   so the wireless-twin assertions caught it with no reference to the oracle. It measured
   twin-consistency.
3. A self-consistent `laptop<->studio` swap. Right mutation shape, wrong population: two
   detectors outside the two counted assertions fire even under a derived oracle, so the
   central "the defect ships" claim was false.
4. `reception<->ratna`, above. Every cell true as written.

Revisions 1–3 were each caught by someone re-running the command rather than reading the
reasoning; revision 3 was caught by an independent `pr-review`, and revision 2's own
correction introduced it. Revision 4's own correction then introduced a fifth defect (a
compressed restatement in `CLAUDE.md` that dropped the qualifier making its criterion true),
which is worth recording because it is the same shape one level down: **compressing this
material loses load-bearing precision**, and that is now measured rather than feared.

**This receipt has an expiry condition, and it is not mechanically guarded.** The pair choice is
true of the suite as it stands. Nothing prevents a future test from pinning `reception`'s or
`ratna`'s legacy variable host-specifically, and that would silently un-isolate the documented
mutation — a fifth revision arriving with nobody having edited the receipt, and per the paragraph
above, the failure would look like a working measurement. If any test later pins either host's
legacy variable that way, the pair stops isolating and the 2×2 must be re-measured against a
different pair.

No guard is proposed for this, deliberately. A mechanical check over a 13-row table is
over-engineering, and this ADR already concedes that nothing mechanical can distinguish the
duplication it defends from drift. This is `USER.md`'s "known-good is a point-in-time attestation,
not a durable truth" applied to a receipt rather than to a revert target — the attestation names
its own staleness condition instead of pretending not to have one.

Note also what the criterion does **not** mean: both hostnames *are* named host-specifically
elsewhere (`tests/setup_env/profiles.bats:94` and `:485` assert `PROFILE=mac_workstation` for
each). `PROFILE` comes from `PROFILE_MAP`, which the swap does not touch, so those stay green.
The qualifier is "legacy variable", and dropping it makes the rule appear refutable by a
two-second grep — which is exactly how it was dropped once already. **Any future re-verification must keep the table self-consistent AND
pick a host pair no other assertion names**, or it is measuring something else — and the
failure will look like a working measurement, because the count will be plausible.

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
