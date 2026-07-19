# scripts/ dir cleanup — design spec

Date: 2026-07-19
Status: Approved (pending plan)

## Context

`scripts/` is a holder of small personal-use utility scripts, not part of the core
`setup_env.sh` workflow chain. A few of the oldest ones (some dated 2022, one embedding
a 1996 academic script) have drifted from current repo conventions and, in one case, a
real bug.

## Scope

- `kill_zombie.sh` — real bug: `kill -9 "${processes}"` quotes the full multi-line
  `pgrep` output as a single argument. Works only when exactly one defunct process
  exists; silently fails to kill any of them when there are multiple. Untested against
  the multi-PID case.
- `mkill.sh` — otherwise correct (already loops per-PID), but has no argument
  validation — an empty/missing pattern silently reaches `pgrep`.
- `html2ascii.sh` — 1996-origin script, still used. Needs modernizing to current
  `shell.md` conventions (unquoted `$1`, `[ ]` instead of `[[ ]]`, embedded raw
  non-ASCII bytes in the entity-replacement `sed` table) without changing behavior.
- `tmux-workstation.sh` — to be deleted outright (confirmed with user), along with its
  2 BATS tests. No other references to it in the repo.

## Non-Goals

- No changes to any other `scripts/*.sh` file — this is a narrowly scoped cleanup of
  4 specific files, not a repo-wide `scripts/` audit.
- No behavior change to `html2ascii.sh`'s actual output — modernization is
  style/quoting/correctness only, existing 4 tests must keep passing unmodified.

## Changes

### `kill_zombie.sh`

```bash
#!/usr/bin/env bash

pattern="<defunct>"
for pid in $(pgrep "${pattern}"); do
  kill -9 "${pid}"
done
```

### `mkill.sh`

```bash
#!/usr/bin/env bash

pattern="${1:?Usage: mkill.sh <pattern>}"

for pid in $(pgrep "${pattern}"); do
  sudo kill -9 "${pid}"
done
```

### `html2ascii.sh`

Same sed-pipeline logic, converted to current conventions:

- `if [[ -z "$1" ]]` instead of `if [ -z "$1" ]`
- `cat "$1"` instead of `cat $1`
- Non-ASCII entity-replacement bytes (currently mangled Latin-1) replaced with correct
  UTF-8 characters (ä, Ä, å, Å, ö, Ö) so the sed table actually does what its own
  comments claim.
- Dead/decorative comment banners trimmed to what's still accurate; behavior and output
  format unchanged.

### `tmux-workstation.sh`

Deleted. Its 2 tests (`tests/scripts/unit.bats` lines ~241-257, "creates exactly 5 tmux
sessions" / "uses correct session names") deleted alongside it.

## Testing

- `kill_zombie.sh`: new tests for zero-match (no-op, exit 0) and multi-match (kills
  each PID individually — the exact case currently broken) using the existing
  `pgrep`/`kill` mock pattern already in `tests/scripts/unit.bats`.
- `mkill.sh`: new test — no argument → non-zero exit with usage message.
- `html2ascii.sh`: existing 4 tests must pass unmodified (behavior-preserving
  refactor); no new tests needed since scope is style/quoting only.
- `make test` / `make lint` must pass; test count decreases by 2 (tmux-workstation.sh
  tests removed) and increases by 3 (kill_zombie.sh x2 + mkill.sh x1) — net +1.

## Rollout

Single feature branch, single PR — small, contained cleanup. Full Phase 3 gate chain
via `finishing-a-development-branch` applies (code change, not docs-only).
