# Design: Use `brew leaves` for Brewfile Drift Untracked Detection

**Date:** 2026-04-29
**Status:** Approved

## Problem

`_update_check_brewfile_drift` uses `brew list --formula` to get the installed formula set.
This returns all formulae including transitive dependencies managed by Homebrew, producing
massive noise in the "untracked" list (e.g. `abseil`, `brotli`, `zstd` — none of which
belong in a Brewfile).

## Decision

Use a two-set approach for formula drift:

- **Untracked** (installed but not in Brewfile): compare Brewfile vs `brew leaves`
- **Missing** (in Brewfile but not installed): compare Brewfile vs `brew list --formula`

`brew leaves` returns only formulae with no dependents — top-level packages the user
intentionally installed. Transitive dependencies don't appear here, eliminating the noise.

Using `brew list --formula` for the missing side avoids false positives: a Brewfile entry
that is also a dependency of another formula (e.g. `openssl`) is still found as installed.

Casks and taps are unchanged — casks have no transitive dependency structure in Homebrew,
and `brew tap` already returns only explicitly added taps.

## Implementation

### `lib/update_summary.sh`

Replace the single installed-formulae capture (line 448) with two captures:

```bash
brew leaves 2>/dev/null | sort > "${_UPDATE_TMPDIR}/drift_inst_formulae_leaves"
brew list --formula 2>/dev/null | sort > "${_UPDATE_TMPDIR}/drift_inst_formulae_all"
```

Update the `comm` comparisons:

```bash
_untracked_formulae=$(comm -13 "${_UPDATE_TMPDIR}/drift_bf_formulae" \
  "${_UPDATE_TMPDIR}/drift_inst_formulae_leaves")
_missing_formulae=$(comm -23 "${_UPDATE_TMPDIR}/drift_bf_formulae" \
  "${_UPDATE_TMPDIR}/drift_inst_formulae_all")
```

### `tests/mocks/brew`

Add a `leaves` case dispatched before the `list` case:

```bash
leaves)
  printf "%s\n" ${MOCK_BREW_LEAVES:-}
  exit 0
  ;;
```

New env var: `MOCK_BREW_LEAVES` — space-separated formulae returned by `brew leaves`.

### `tests/setup_env/brewfile_drift.bats`

Test classification after the change:

| Scenario                   | Vars needed                                                                                         |
| -------------------------- | --------------------------------------------------------------------------------------------------- |
| Untracked formula only     | `MOCK_BREW_LEAVES` (set to installed+extra), `MOCK_BREW_LIST_FORMULA` (set same as leaves or empty) |
| Missing formula only       | `MOCK_BREW_LEAVES` (set to installed), `MOCK_BREW_LIST_FORMULA` (set to installed — no extra)       |
| Both untracked and missing | Both vars, set independently                                                                        |
| OK (no drift)              | `MOCK_BREW_LEAVES` == Brewfile formulae, `MOCK_BREW_LIST_FORMULA` == same                           |

Existing tests that use `MOCK_BREW_LIST_FORMULA` for the untracked side must be updated
to set `MOCK_BREW_LEAVES` for the untracked formula set. Tests for missing formulae
continue to use `MOCK_BREW_LIST_FORMULA`.

### `CLAUDE.md` mock table

Add `MOCK_BREW_LEAVES` to the mock env var table.

## Testing

All existing drift tests that run with `MACOS=1` must set `MOCK_BREW_LEAVES` (the Linux-gate
tests do not reach `brew leaves` and are unchanged). No new test scenarios are needed — the
existing coverage already exercises both untracked and missing paths; only the var names
change for the untracked side.

`make test` must pass with 555 tests (count unchanged — no new tests, no removed tests).

## Out of Scope

- Cask drift logic: unchanged
- Tap drift logic: unchanged
- `brew_formula_installed` in `helpers.sh`: uses `brew list --formula` for install guards,
  not drift detection — unchanged
