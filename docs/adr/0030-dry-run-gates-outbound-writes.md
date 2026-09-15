# ADR-0030: `--dry-run` gates outbound writes, and fails closed when the predicate is absent

**Date:** 2026-09-14
**Status:** Accepted

## Context

`--dry-run` has been documented as a preview flag for as long as it has existed, and the code
did not match. Under `setup_env.sh --dry-run` the repo performed a real `git push`
(`lib/git_sync.sh:71`), three real `rsync -ar --delete` legs (`sync_legacy_dirs`), and a real
state-ledger entry write (`ledger_write_entry`). A flag whose entire purpose is to change
nothing was writing to three other machines.

Two framing questions had to be settled before anything could be guarded, and the first
answer was wrong.

**What is the gated set?** Round 1 of the design selected ten sites with a destructive-verb
scan and wrapped single lines inside delete-recreate pairs. That produced three regressions —
a guarded delete followed by an unguarded recreate — and closed none of the measured harm. It
was retired rather than repaired.

**Where is the boundary?** The obvious phrasing, "nothing leaves this machine", is false and
was asserted in the docs until Phase 3 measured it. `_git_repo_status` runs `git fetch`
against every personal repo's remote and authenticates with the operator's SSH key on every
dry run; `pull --ff-only` fast-forwards any clean repo that is behind; `npm install -g` (5
sites) and `uv sync` reach their registries. All of that is egress, and none of it is
reversible harm to another machine. Scoping the guarantee to _egress_ would either be a lie
or would demand an offline mode nobody asked for.

## Decision

The gated set is **outbound writes**: operations that write state to another machine. Three
sites, each guarded at the granularity its function's purpose dictates.

| site                                        | guard                          | why                                                              |
| ------------------------------------------- | ------------------------------ | ---------------------------------------------------------------- |
| `ledger_write_entry` (`lib/workflows.sh`)   | function                       | the whole function is the write                                  |
| `_git_sync_one_repo:71` (`lib/git_sync.sh`) | **line**                       | the push is one branch; `pull --ff-only` at `:82` still previews |
| `sync_legacy_dirs` (`lib/legacy_rsync.sh`)  | function, after the host check | the whole function is three `rsync --delete` pushes              |

> **The placement rule.** Guard the function where its purpose **is** the outbound write.
> Guard the line where the outbound write is one branch of a function that does other useful
> work.

`_dry_run_active` (`lib/helpers.sh`) is the single predicate. Its truthiness contract:
`""`, `0`, `false` and `no` all mean dry-run is **off**; any other value means **on**; and an
explicit `--dry-run` flag wins over an inherited falsy `DRY_RUN`. An unrecognised value
therefore fails **safe**, by suppressing.

**The predicate's absence fails closed.** `lib/git_sync.sh` and `lib/legacy_rsync.sh` each
define a fallback stub, guarded by `declare -f`, that returns 0:

```bash
if ! declare -f _dry_run_active >/dev/null 2>&1; then
  _dry_run_active() { return 0; }
fi
```

This is not defensive decoration. Calling an undefined function exits **127**, and `if` reads
any non-zero status as false — which is the fail-**OPEN** direction here, because the
else-branch of each guard is a real `git push` in one file and three real `rsync --delete`
pushes in the other. Sourcing either file without `lib/helpers.sh` would otherwise turn a
missing predicate into an unannounced real write. Suppressing is the only safe answer when
the authority is missing.

## Consequences

**Good.** A preview flag can no longer write to another machine. The boundary is stated
identically in `CLAUDE.md`, `README.md` and the `--help` text. Sourcing either guard-carrying
lib standalone cannot fail open. The placement rule gives the next contributor a decision
procedure rather than three precedents to pattern-match.

**Costs, accepted.**

- **It is not an offline mode, and the docs must keep saying so.** Fetches, ff-only pulls,
  package upgrades, venv rebuilds, `npm install -g` and `uv sync` all still run for real. This
  is the claim most likely to be re-broken by someone tidying the wording.
- **The guarantee is scoped to the state-ledger _entry_ write.** `ensure_state_ledger`
  (`lib/workflows.sh:923-941`) is called ungated from `_dotfiles_run_tmpdir_setup:123` by every
  entry point, so a dry run still clones or pulls the state-ledger repo, runs `ledger.py init`,
  and `rm -rf`s the directory when it exists but is not a valid repo. Those are local writes.
  The outbound-write guarantee survives because `cmd_init` (`ledger.py:372-436`) reaches none
  of that script's four push sites (`:486`, `:668`, `:791`, `:850`) — verified by reading
  `cmd_init`, not by grepping the calling bash for `push`, which cannot see a subprocess.
- **Registry fetches stay ungated**, deliberately. `uv sync` in particular produces a venv
  state that is not reproducible from the lock, which meets a wider "destroys state the remote
  cannot reproduce" criterion without being an outbound write. Deciding it has its own blast
  radius; backlog.
- **Delete-recreate pairs stay ungated.** Gating them requires whole-function guards, which
  changes what a preview reports. Backlog.
- **Nothing detects drift.** No test asserts that the set of outbound-write sites is a subset
  of the gated set, so a new `git push` added elsewhere is silently ungated — the same
  mechanism that produced this defect in the first place.
  `scripts/check-lib-exit-traps.sh` is an in-repo precedent for a scanner ratchet that would
  close it. Backlog, deliberately out of a defect repair.
- **The fallback stub is duplicated in two files.** The natural shared home is
  `lib/helpers.sh`, which is precisely the file whose absence the stub exists to survive, so
  sharing it would defeat it.

## Related

- `docs/superpowers/specs/2026-09-14-dry-run-irreversible-gating-design.md` — the design,
  including the retired round-1 verb-scan scope and the retraction of the "no egress" wording
- `docs/superpowers/plans/2026-09-14-dry-run-egress-gating.md` — the implementation plan
- [ADR-0027](0027-update-run-exit-code-from-section-status.md) — the section-status model the
  dry-run skips are reported through
