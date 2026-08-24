# ADR-0023: The identity table's two consumers diverge on load failure

**Status:** Accepted
**Date:** 2026-08-23

## Context

ADR-0020 established `config/profiles.sh` as the single hostname→identity table,
read by two consumers in two languages: `lib/detect_env.sh` (bash, sourced only by
`setup_env.sh`) and `config/profiles.zsh` (zsh, sourced by `.zprofile` at login and
again by `.config/.zshrc.d/1_init.zsh`).

Until this change the bash consumer discarded the result entirely:

```bash
source "$(dirname "${BASH_SOURCE[0]}")/../config/profiles.sh"
```

A failure produced `PROFILE=unknown`, no `HAS_*` capability, and no legacy identity
variable — and `setup_env.sh` then provisioned the machine anyway. Every
capability-gated branch went dark silently, because `unknown` is a well-formed
answer rather than an error. That is the same shape ADR-0017 closed for the pre-push
trigger: a default that cannot distinguish "nothing to do" from "the check did not
run."

Two further properties made a naive guard insufficient:

- **`source` returns the status of its last executed command.** `config/profiles.sh`
  ends with `declare -A PROFILE_LEGACY=(...)`, so a failure confined to an earlier
  statement leaves `source` returning 0 with the table incomplete. Measured:
  `rc=0 LOADED=1 PROFILE=unknown` with `HAS_DEVTOOLS` inherited from the login shell.
- **`config/profiles.zsh` exports `PROFILE` into every child of a login shell.** A
  stale inherited value therefore survives a failed load, so `[[ -z ${PROFILE+x} ]]`
  is false and any check reading `PROFILE` alone reports PASS over a machine whose
  table never loaded this run.

## Decision

The bash consumer **fails closed**; the zsh consumer **warns and continues**. This
divergence is deliberate and is not drift to reconcile.

1. `detect_env` guards the source *and* asserts a post-condition —
   `declare -p PROFILE_MAP PROFILE_CAPS PROFILE_LEGACY` — turning the check from
   "the last statement succeeded" into "the three arrays the caller depends on
   exist". Either failure returns 1.
2. A sentinel, `_PROFILES_LOADED`, is set to `0` unconditionally on entry to
   `detect_env` and to `1` only after both guards pass. `_doctor_check_profile`
   branches on the sentinel *before* looking at `PROFILE` at all, so a stale
   inherited `PROFILE` cannot produce a PASS. The unconditional `=0` on entry, not
   the absence of an `export`, is what makes the sentinel trustworthy.
3. `setup_env.sh` aborts on a failed `detect_env`, with a carve-out for `-t doctor`
   and `-t check-versions` — the two read-only workflows, whose whole purpose is to
   report the broken state.

The zsh side keeps its existing `print -u2` warning and continues, because
`config/profiles.zsh` is sourced by `.zprofile` at login: aborting a login shell over
a degraded lookup is worse than the degraded lookup.

## Consequences

- A machine whose identity table cannot load can no longer be provisioned. It can
  still be diagnosed: `-t doctor` runs and reports `[FAIL] PROFILE: config/profiles.sh
  did not load this run`.
- An unmapped *hostname* is unaffected and still provisions — `PROFILE=unknown` with
  a doctor FAIL is the pre-existing, intended behavior for a new machine. `detect_env`
  returns 0 in that case, which is now load-bearing at `setup_env.sh:61` and is pinned
  by a test.
- `detect_env`'s exit status is meaningful for the first time. Its value rests on the
  terminal statement being a no-`else` `if`; the line above it returns 1 whenever the
  host has no `PROFILE_LEGACY` entry. Reordering the two would lock every unmapped
  machine out of setup. `tests/setup_env/unit.bats` pins this in both the Darwin and
  Linux arms.
- The rationale for the divergence is now stated in both files, near-verbatim, with
  the bash side citing the zsh side by line number. Nothing forces the two copies
  consistent; that exposure is backlogged rather than fixed, because deleting either
  copy removes the warning from the site where someone would try to reconcile them.

## Related

- ADR-0020 — single identity table across bash and zsh (this amends its failure semantics)
- ADR-0021 — hand-typed test oracle for the identity table
- ADR-0017 — the pre-push trigger fails closed (same decision shape, different gate)
- `docs/superpowers/specs/2026-08-23-profiles-bash-version-guard-design.md`
