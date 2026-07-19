# scripts/ world-class pass — design spec

Date: 2026-07-19
Status: Approved (pending plan)

## Context

Follow-up to the scripts-dir-cleanup pass (PR dotfiles#183/#184). A survey of the
remaining `scripts/*.sh` files found no further bugs, but consistent gaps: most have
no `-h`/`--help`, two (`count_lines.sh`, `count_lines_git.sh`) are still on the old
`[ ]`/`echo` style already fixed elsewhere, and `run-coverage.sh` (kcov-based) is
confirmed dead/broken per existing memory `dotfiles-bash-coverage.md` — kcov cannot
trace through bats subshells, so it silently produces zero/garbage coverage data. Hit
this exact thing tonight: ran `make coverage` by mistake, burned 5+ minutes.

## Scope

**Add `-h`/`--help` only** (logic unchanged, already correct):

- `restart_fah.sh`
- `push-bash-coverage.sh`
- `bootstrap_mac.sh`
- `bootstrap_linux.sh`
- `sync-agent-guidance.sh`

**Modernize to `shell.md` conventions + add `-h`/`--help`** (behavior-preserving):

- `count_lines.sh` — `[ -z "$1" ]` → `[[ -z "${1:-}" ]]`, `echo` → `printf`, quote all
  var expansions.
- `count_lines_git.sh` — same.

**Delete**:

- `scripts/run-coverage.sh`
- `Makefile`'s `coverage:` target and its `make help` line (the help text's claim
  "CI-enforced" is actively wrong — CI enforces via `bash-coverage`, not `coverage`)

**Unchanged**: `bash-tracer.sh` (internal `BASH_ENV` glue, not directly invoked by a
human, no `-h` needed).

## Non-Goals

- No new functionality — `-h` additions print usage and exit 0, don't change any
  existing code path.
- No changes to `count_lines.sh`/`count_lines_git.sh`'s actual line-counting logic —
  same output, same behavior, style/quoting only.
- No changes to `KCOV` variable detection in the Makefile beyond removing the
  `coverage:` target itself (the `KCOV := $(shell command -v kcov ...)` line becomes
  unused and can be removed too, checked at implementation time).

## Testing

- Each `-h`/`--help` addition gets 2 new tests (both flag spellings) in the relevant
  test file, following the exact pattern established for `kill_zombie.sh`/`mkill.sh`/
  `html2ascii.sh`/`sync_git_repos.sh` tonight: usage printed, exits 0, no side-effecting
  command invoked (asserted via the existing mock pattern where applicable).
- `count_lines.sh`/`count_lines_git.sh`: existing behavior tests (if any exist —
  check at implementation time) must pass unmodified; add boundary tests for
  missing-argument (already has a usage-and-exit-1 path, lock it in if untested).
- `run-coverage.sh` deletion: remove any tests referencing it (check at implementation
  time), verify no other file references `run-coverage.sh` or `make coverage` before
  deleting (README badges, CI workflows, other docs).
- `make test` / `make lint` must pass throughout.

## Rollout

Single feature branch, single PR. Full Phase 3 gate chain via
`finishing-a-development-branch` applies.
