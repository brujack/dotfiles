# uv.lock Refresh Cooldown Implementation Plan

> **Status: DONE** (dotfiles#454, merged 440e7df0)

spec: docs/superpowers/specs/2026-11-09-uv-lock-refresh-cooldown-design.md

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The weekly uv.lock refresh holds every release younger than 14 days at its newest aged release (or master's version), reports what it held, and fails closed when its own change accounting disagrees with uv.

**Architecture:** A stdlib-only Python helper (`scripts/uv_lock_cooldown.py`) reads `upload-time` from two `uv.lock` files and answers four questions (`cutoff`, `plan`, `verify`, `diff`, `held`). `scripts/refresh-uv-lock.sh` keeps its shape and calls the helper around one extra `uv lock` cap call and one plain `uv lock`. The change list feeding the downgrade check and the PR body comes from the helper's `diff`, not from grepping uv's output.

**Tech Stack:** bash, Python 3 standard library (`tomllib`), uv 0.13.0 (CI pin), bats, `unittest`.

## Global Constraints

- Cooldown is 14 days; `REFRESH_COOLDOWN_DAYS` equals the day count of `renovate.json`'s `"minimumReleaseAge": "14 days"`.
- Age of a version = the earliest `upload-time` among its files; a changed version with no `upload-time` is fresh.
- No security-advisory lookup and no network call besides uv's own resolution (N1).
- No global `--exclude-newer`; no `exclude-newer` left in a committed `uv.lock` (N2).
- `plan` emits nothing for a package whose version set is unchanged (N3).
- No change to the five renderings' groups, and no ai-config change besides the `dotfiles-test-seams.md` seam entry (N4 as amended).
- The helper uses the Python standard library only (CI test jobs install no Python packages), like `scripts/uv_lock_downgrades.py`.
- Cutoff and timestamps are computed in Python, never with `date -d` (BSD `date` on the macOS shards has no `-d`).

## Session-level verification

- `make test` exits 0 with the new tests in the count.
- V1/V3 (orchestrator, after Task 2): replay `scripts/refresh-uv-lock.sh` against a scratch copy of the tree at `41893754` with the checksum-verified uv 0.13.0 binary as `_UV_BIN` and `REFRESH_COOLDOWN_NOW=2026-11-09T19:00:00Z`. Expected: exit 0, `changed`; 0 versions uploaded after 2026-10-26T19:00:00Z; 0 packages below base; `uv lock --check` exit 0; `command grep -c exclude-newer uv.lock` prints 0; at least one package at an older aged release and one at base; the relock moved 0 versions; capped packages' wheel counts equal a plain `uv lock` of their final versions.
- V2: the first scheduled run after merge (Monday 06:00 UTC) is read against PyPI upload times.

---

### Task 1: Cooldown helper

```yaml-task
id: 1
description: Add scripts/uv_lock_cooldown.py (cutoff, plan, verify, diff, held) with its unittest suite
role: executor
model: sonnet
tdd: required
requirements: [R1, R3, R4, R5, R8]
acceptance:
  - cmd: python3 -m unittest tests.test_uv_lock_cooldown -v
    exit_code: 0
    stderr_match: 'Ran [1-9][0-9]* tests'
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [scripts/uv_lock_cooldown.py, tests/test_uv_lock_cooldown.py]
depends_on: []
```

**Files:** create `scripts/uv_lock_cooldown.py` (executable, `#!/usr/bin/env python3`, module docstring stating exit codes like `uv_lock_downgrades.py`), create `tests/test_uv_lock_cooldown.py` (`unittest`, fixture locks written to a `tempfile.TemporaryDirectory`, the helper run with `subprocess` as `[sys.executable, helper, ...]`).

**Interfaces (produces, exact):**

- Exit codes for every subcommand: 0 success, 1 findings (`verify` only), 2 usage error, unreadable/invalid TOML, a lock with zero registry packages, a registry package with no readable `version`, or any uncaught exception (never 1 for a crash).
- A registry package is a `[[package]]` whose `source` has a `registry` key. Versions are grouped per name as a set (a name may appear more than once across resolution forks). Age = min `upload-time` over `sdist` and `wheels[]`; none = fresh.
- `cutoff NOW DAYS` → prints `NOW − DAYS days` as `YYYY-MM-DDTHH:MM:SSZ`. NOW is RFC 3339 (`Z` or offset).
- `plan BASE NEW CUTOFF REPORT` → stdout one uv argument per line. For each name (sorted) whose version set differs and whose NEW versions not in BASE include a fresh one: if BASE has a fresh version V of it, `--upgrade-package` then `P==V`; else `--upgrade-package`, `P`, `--exclude-newer-package`, `P=CUTOFF`. Writes REPORT as TSV `name<TAB>newest<TAB>earliest-upload` (newest = the fresh NEW version) for each emitted name; empty file when none. Fresh = earliest upload strictly later than CUTOFF (equal is aged).
- `verify BASE FINAL CUTOFF` → for each name whose FINAL version set differs from BASE (added names included), any FINAL version not in BASE that is fresh: print the name, exit 1.
- `diff BASE FINAL` → uv's format, names sorted: `Updated P vA -> vB` (multi-version sides joined by `, v`), `Added P vB`, `Removed P vA`; nothing when the version sets are equal.
- `held REPORT FINAL` → one `- P: newest X uploaded T; took Y` line per REPORT row, Y = FINAL's version(s) for P joined by `, `.

**Tests (write each red first, then the code):** unchanged package emits nothing; fresh change with aged base → `--exclude-newer-package`; fresh base version → `P==base`; added fresh package → `--exclude-newer-package`; aged change emits nothing; missing `upload-time` is fresh; boundary: upload exactly at CUTOFF is aged, one second later fresh; multi-version name compared as a set; `verify` exit 1 naming a fresh changed and a fresh added package, exit 0 when FINAL holds only aged or base versions; `diff` on Updated/Added/Removed and multi-version; `diff` empty on equal version sets with different wheel lists; exit 2 on a lock with zero registry packages, on a package with no `version`, on unparseable TOML, on a wrong argument count; `cutoff` for `2026-11-09T19:00:00Z 14` prints `2026-10-26T19:00:00Z`; `held` line format.

- [ ] Write tests one behaviour at a time, red then green, then commit (`caveman:caveman-commit`).

### Task 2: Wire the cooldown into refresh-uv-lock.sh

```yaml-task
id: 2
description: Run the cap pass, relock, verify, diff, cross-check and held section from refresh-uv-lock.sh, with a sequenced uv stub and reworked bats
role: executor
model: sonnet
tdd: required
requirements: [R2, R3, R4, R5, R6, R7, R8, R9, R11, R12]
acceptance:
  - cmd: bats tests/scripts/refresh_uv_lock.bats
    exit_code: 0
    stdout_match: 'ok [0-9]+ a fresh change is capped and the body lists it'
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [scripts/refresh-uv-lock.sh, tests/stubs/uv-refresh-stub, tests/scripts/refresh_uv_lock.bats]
depends_on: [1]
```

**Script changes (`_refresh_run`, after the existing `uv lock --upgrade` and its rc check):**

1. `readonly REFRESH_COOLDOWN_DAYS=14` at file scope; `_COOLDOWN_HELPER` seam (default `uv_lock_cooldown.py` beside the script, like `_DOWNGRADE_HELPER`). Cutoff once: `python3 "${_COOLDOWN_HELPER}" cutoff "${REFRESH_COOLDOWN_NOW:-$(python3 -c ...utc now...)}" "${REFRESH_COOLDOWN_DAYS}"` (the default NOW also via Python).
2. Keep the existing `cmp -s uv.lock before` → `no changes` early exit.
3. `plan before uv.lock cutoff report` into a args file; rc ≠ 0 → `cooldown helper failed (rc N)`. If non-empty: `mapfile -t` the args; `uv lock --color never "${args[@]}"` (fail → `cooldown re-resolve failed`), then `uv lock --color never` (fail → `cooldown lock rewrite failed`). The script writes `uv.lock` only via uv or the R5 copy.
4. `verify before uv.lock cutoff`: rc 1 → `cooldown not honoured: <names joined ", ">`; rc 2+ → helper failed.
5. `diff before uv.lock` into the lines file; check rc before content (rc ≠ 0 → helper failed). Empty → `cp before uv.lock`, print `no changes`, exit 0.
6. R12: every name in the upgrade call's `^(Updated|Added|Removed) ` lines must appear in the diff lines or the report's first column, else `cooldown change list disagrees with uv: <names>`.
7. Downgrade check, renderings, checks unchanged; body = existing text plus, when the report is non-empty, `### Held by the 14-day cooldown` and the `held report uv.lock` lines. Delete the old grep-based `uv printed no change lines` refusal (superseded by R5/R12).

**Stub (`tests/stubs/uv-refresh-stub`):** keep the argv log and stderr lines; add `STUB_UV_LOCK_DIR`: on call N (counter file in `${STUB_UV_LOCK_DIR}`) copy `${STUB_UV_LOCK_DIR}/N.lock` to `./uv.lock` when it exists; `STUB_UV_LINES` printed on call 1 only; `STUB_UV_FAIL_CALL=N` exits 1 on call N. Keep `STUB_UV_CHANGE`/`STUB_UV_EXIT` working for existing tests or migrate them; never print the sentinel on stderr.

**Bats:** add a `_lock` helper writing minimal registry TOML (`[[package]] name/version/source = { registry = "https://pypi.org/simple" }`, an `sdist` with `upload-time`). Rework every existing test whose lock is `version = 1` so the helper parses it. New tests: no fresh change makes exactly one uv call; `a fresh change is capped and the body lists it` (asserts the exact cap argv line, a plain relock call after it, the held section line); cap restoring every version → `no changes` and `uv.lock` byte-equal to base; the final `uv.lock` holds no `exclude-newer` after a cap whose stub lock wrote an `[options] exclude-newer-package` table (N2); each failure-table message; R12 disagreement; `REFRESH_COOLDOWN_DAYS` equals `renovate.json`'s `minimumReleaseAge` day count (read with `python3 -c 'import json…'`).

- [ ] Red then green per behaviour; `make test`; commit.

### Task 3: Docs, ADR and Backlog

```yaml-task
id: 3
description: ADR-0057, CLAUDE.md refresh bullet and test-seam line, Backlog row removal, plan index (docs-only, no behaviour change)
role: executor
model: sonnet
tdd: not-applicable
requirements: [R10]
acceptance:
  - cmd: 'command grep -qF "14-day" CLAUDE.md'
    exit_code: 0
  - cmd: '! command grep -qF "Weekly lock refresh has no release-age cooldown" docs/superpowers/README.md'
    exit_code: 0
  - cmd: test -f docs/adr/0057-uv-lock-refresh-release-cooldown.md
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 2
files_touched: [CLAUDE.md, docs/adr/0057-uv-lock-refresh-release-cooldown.md, docs/adr/README.md, docs/superpowers/README.md]
depends_on: [2]
```

- `CLAUDE.md` `uv-lock-refresh.yml` bullet: add that changes younger than 14 days (Renovate's `minimumReleaseAge`) are held at their newest aged release or master's version and listed under "Held by the 14-day cooldown", with the spec path. In the "Test Seams" refresh line add `REFRESH_COOLDOWN_NOW` and `_COOLDOWN_HELPER`.
- ADR-0057 (Context, Decision, Consequences, Related; `**Status:** Accepted`): per-package cap over a global `--exclude-newer`, no CVE bypass, the relock's role, the parser cross-check. Add its README row.
- `docs/superpowers/README.md`: remove the Backlog row "Weekly lock refresh has no release-age cooldown"; set the plan row's plan link and status `In Progress`.
- The suite reads none of these files, so this task does not run `make test`; the orchestrator runs it after this task.

## Orchestrator steps

1. Before Task 3: message `ai-config [625068]` that dotfiles adds two test seams and that the `dotfiles-test-seams.md` entry "uv lock refresh seams" needs `REFRESH_COOLDOWN_NOW` and `_COOLDOWN_HELPER`; ask it to add them (that repo is its own).
2. After Task 2: run V1/V3 as stated under Session-level verification, and record the output in the PR body.
3. After Task 3: `make test`, then Phase 3.

## Non-goal check

Reviewer: one fresh Opus subagent with `~/.claude/skills/writing-plans/nongoal-check.md`, 2026-11-09.

- N1 CLEAR.
- N2 UNCLEAR — quote: Task 2 step 3, "`uv lock --color never "${args[@]}"` … then `uv lock --color never`"; the plan relied on the relock to strip `exclude-newer-package` with no check. Resolution: plan revision. Before: Task 2's bats list ended "each failure-table message; R12 disagreement;" and V1 had no `exclude-newer` check. After: Task 2 adds "the final `uv.lock` holds no `exclude-newer` after a cap whose stub lock wrote an `[options] exclude-newer-package` table (N2)", and V1 adds "`command grep -c exclude-newer uv.lock` prints 0".
- N3 CLEAR.
- N4 CONFLICT — quote: Orchestrator step 1, "ask it to add them" (the `dotfiles-test-seams.md` entry). Resolution: spec amendment `N4 -> … no ai-config change besides the dotfiles-test-seams.md entry that dotfiles' CLAUDE.md requires for a new test seam`, since that entry is mandatory; Global Constraints line updated to match.

