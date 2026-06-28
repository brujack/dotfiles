# ADR-0014: State-Ledger CMDB Integration for Update Run Metadata

**Date:** 2026-06-28
**Status:** Accepted

## Context

The dotfiles `update` run (`./setup_env.sh -t update`) performs package updates
across brew, apt, snap, pip, gems, mas, and several git-tracked tools. Each run
produces a structured summary in `~/.dotfiles-update.log`, but no machine-readable
CMDB record was ever written — the data was human-readable only and local to each
machine.

`state-ledger` is a private git-backed CMDB at `~/git-repos/personal/state-ledger/`
(runtime symlink: `~/.local/share/state-ledger`). It stores JSON entries under
`entries/<tool>/<entity-id>/YYYY/MM/DD-HH-MM-SS.json` and auto-commits+pushes on
every write, giving a cross-machine audit trail queryable via `ledger status` and
`ledger drift`.

Two problems prevented the integration from working:

1. `ledger_write_entry()` and `ledger_flush_spool()` were defined in `lib/workflows.sh`
   but never called — dead code. No entry was ever written to state-ledger.
2. `~/.local/bin/ledger` was not in the PATH of the update subshell. Even if the
   functions had been called, `command -v ledger` returned nothing and the write
   was silently skipped.

Alternatives considered:

- **Call `ledger` directly from `run_update()`:** Couples the ledger write to the
  update orchestration. Test isolation harder — every `run_update` test would need
  to mock ledger.
- **Write to a spool file; flush later:** The existing `ledger_flush_spool()` handles
  this for offline scenarios, but requires a separate daemon or cron trigger.
- **Write at the end of `_update_summary()`:** Keeps ledger coupling out of the
  update orchestration, isolated to the summary reporting layer. Chosen approach.

## Decision

State-ledger writes are wired into `_update_summary()` as a single advisory call:

1. `run_update()` captures `started_at` (ISO-8601), `start_epoch` (Unix), `run_id`
   (UUID), and `git_sha` (dotfiles HEAD SHA) into `_UPDATE_TMPDIR` at the start of
   every update run.

2. `_ledger_write_dotfiles_entry()` in `lib/update_summary.sh` reads those files,
   computes duration, reads the failure count from the `_fail` variable visible via
   bash dynamic scoping, builds a schema v1.0 JSON payload with all base fields plus
   dotfiles-specific extension fields (`sections_ok`, `sections_failed`, `sections_warn`,
   `sections_skip`, `git_sha`), and calls `ledger_write_entry "${_json}"`.

3. `ledger_write_entry()` and `ledger_flush_spool()` both fall back to
   `~/.local/bin/ledger` when `command -v ledger` finds nothing — resolving the
   PATH gap in the update subshell.

4. **The call is advisory.** `_update_summary()` invokes `_ledger_write_dotfiles_entry || true`
   — a ledger failure never aborts or fails the update summary. The update run result
   is always surface to the user regardless of CMDB state.

5. **Guard against non-`run_update` callers.** `_ledger_write_dotfiles_entry` returns
   early when `${_UPDATE_TMPDIR}/started_at` is absent. `_update_summary()` can be
   called directly in tests and from other paths that don't go through `run_update()`;
   without this guard, the actual `~/.local/bin/ledger` binary would be invoked in
   those contexts.

**Prerequisites on each machine (one-time):**

```bash
# Symlink runtime location to dev checkout
ln -s ~/git-repos/personal/state-ledger ~/.local/share/state-ledger

# Bootstrap ledger binary and machine-id
python3 ~/.local/share/state-ledger/scripts/ledger.py init
```

## Consequences

**Enabled:**

- Every `setup_env.sh -t update` run produces a CMDB record in state-ledger.
- Cross-machine audit trail queryable via `ledger status` and `ledger drift`.
- Run metadata (duration, outcome, git SHA, section counts) is preserved for
  trend analysis and debugging regression patterns.
- Spool mechanism (`ledger_flush_spool`) handles offline scenarios (no network
  during update run); entries are committed on next successful push.

**Constraints going forward:**

- New update sections must also populate the ledger payload fields if they affect
  pass/fail/warn/skip counts — `_ledger_write_dotfiles_entry` reads counts from
  `_UPDATE_TMPDIR/status_*` files, so sections using `_update_record_end` are
  automatically included.
- The advisory `|| true` is permanent. Ledger write failures must be surfaced as
  warnings to stderr, not as hard errors that break the update workflow.
- Tests that call `_update_summary()` directly must NOT create
  `${_UPDATE_TMPDIR}/started_at` unless they intend to exercise the ledger path.
  The guard prevents spurious ledger invocations from the test suite.

## Related

- PR dotfiles#166 — `ledger_write_entry` fallback + `_ledger_write_dotfiles_entry` implementation
- PR dotfiles#167 — advisory `|| true` guard and `started_at` guard for test isolation
- `state-ledger/scripts/ledger.py` — CMDB tool (schema v1.0)
- `lib/update_summary.sh:_ledger_write_dotfiles_entry` — integration point
- `lib/workflows.sh:ledger_write_entry`, `ledger_flush_spool` — write + spool functions
- `tests/setup_env/ledger_integration.bats` — 17 tests covering fallback, guards, JSON shape
