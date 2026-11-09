# ADR-0057: Per-package 14-day release cooldown in the weekly uv.lock refresh

**Date:** 2026-11-09
**Status:** Accepted

## Context

ADR-0056 chose no release-age cooldown for `uv-lock-refresh.yml`: a global `--exclude-newer`
writes `[options]` into `uv.lock`, so bare `uv lock --check` fails every changed run, it drops
locked versions as preferences, and it downgrades lock-only security bumps younger than the
cutoff (9 packages at 30 days, 12 at 45; measured at `cb57dfb6`, uv 0.13.7). That left the
operator's reading of the PR change list as the only gate for a release published minutes before
the Monday run. Renovate already holds fleet updates to a 14-day `minimumReleaseAge`; the lock
refresh was the one path without an equivalent. The design is in
`docs/superpowers/specs/2026-11-09-uv-lock-refresh-cooldown-design.md`.

## Decision

1. **Cap per package, never globally.** After `uv lock --upgrade`, `scripts/uv_lock_cooldown.py`
   (`cutoff`, `plan`, `verify`, `diff`, `held`) finds each changed package whose new release is
   younger than 14 days. `scripts/refresh-uv-lock.sh` re-resolves with per-package flags only for
   those packages: `--upgrade-package name --exclude-newer-package name=<cutoff>` for a package
   held at an aged release, or `--upgrade-package name==<base version>` for one held at base.
   Packages with no young release are untouched, so none of the three global defects arises.
2. **Hold rule.** A young package is held at its newest release at least 14 days old; when master's
   own version is itself younger than the cutoff, it is held at master's version (base).
3. **No security bypass.** A fresh release stays held even when it fixes a vulnerability. Letting
   one through is an operator decision made by hand, not a rule in the script.
4. **A plain relock follows the capped resolve.** `uv lock` with no flags removes any `[options]`
   written by the caps and restores file entries that the cutoff filtered, so the committed lock
   carries no `exclude-newer`. `verify` then fails the run if any version younger than the cutoff
   remains.
5. **Cross-check against a misreading parser.** The helper reads `uv.lock` itself, so a parser that
   misreads versions would yield an empty diff and a false `no changes`. Every package named on an
   `Updated`/`Added`/`Removed` line of uv's output must appear in the helper's diff or in the held
   report; a name in neither fails the run.
6. **Same version set means `no changes`.** When the caps put every version back to base, the
   script restores the exact base `uv.lock` bytes and prints `no changes`.
7. **Held packages are reported.** The PR body lists them under "Held by the 14-day cooldown".
   The clock is `REFRESH_COOLDOWN_NOW` for tests, now in production.

Measured replay at `41893754` on uv 0.13.0: of 105 changed packages, 55 were kept, 41 were held
at an aged release and 9 at base; 0 fresh versions were admitted.

## Consequences

- The first run after merge holds about 50 packages, so its PR is small and later runs catch up
  as releases age.
- A local `+` version (`1.0+local`) or a change in uv's lock format that the helper cannot parse
  fails the run closed and opens the `uv.lock refresh failed` issue; it never degrades to a quiet
  pass.
- A security fix younger than 14 days waits for the next run, or for the operator to bump it by
  hand.
- The backlog row "Weekly lock refresh has no release-age cooldown" is retired.

## Related

- ADR-0056: weekly uv.lock refresh as a bot PR (its "No release-age cooldown" decision is
  superseded here).
- `docs/superpowers/specs/2026-11-08-uv-lock-refresh-design.md` (parent spec).
- `docs/superpowers/specs/2026-11-09-uv-lock-refresh-cooldown-design.md`.
- Renovate shared preset `minimumReleaseAge` (14 days), `renovate.json`.
