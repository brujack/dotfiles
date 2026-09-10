# Unwired Units Cleanup Implementation Plan

> **Status: DONE**

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Delete four `lib/` units with zero production callers, so the gated test count and coverage figure stop describing code nothing runs.

**Architecture:** Pure deletion. Three whole files and three functions go, along with 37 tests. Two surviving tests that referenced the deleted file are edited rather than removed. One ADR gets a dated amendment plus a Status-line pointer; `CLAUDE.md` gets four content edits and two figure bullets.

**Tech Stack:** bash, bats, `scripts/run-bash-coverage.sh` (PS4 xtrace tracer), `make lint` / `make test`.

Spec: [2026-09-09-unwired-units-cleanup-design.md](../specs/2026-09-09-unwired-units-cleanup-design.md) at `6b57a15b`.

## Global Constraints

- Work in a linked worktree on a feature branch. Never commit in the main checkout — a peer session may hold it.
- `make test` runs `lint` first; `lint` covers `bash -n` + shellcheck over `SHELL_FILES` (shebang-derived) and `zsh -n` over `ZSH_FILES`.
- Test count floor is **840**. Suite goes 1659 -> 1622. No task may leave the suite red.
- Bash coverage floor is **91%**, CI-gated, blocks auto-merge. Measured post-deletion: `3542/3857` = 91.83% local.
- `ledger_write_entry` STAYS — live write path, has production callers.
- `brew_formula_installed` STAYS — reachable via `brew_install_formula`'s 37 callers.
- Deleting a function means deleting its contiguous comment block above it too.
- Every `git grep` gate below uses `-E` **without** `\b`. `git grep -E` does not implement `\b`; it silently matches nothing. Verified: `git grep -nE '^[^#]*\bbrew_install_formula\b' -- lib/` returns 0 where the same pattern without `\b` returns 38.

## Session-Level Verification

**Command that proves the whole change works:**

```bash
make test                                    # exit 0, 1622 tests
git grep -nE '^[^#]*(brew_install_cask|brew_cask_installed|ledger_flush_spool|capture_all_packages|capture_package_diff)' \
  -- lib/ scripts/ setup_env.sh tests/ | wc -l          # 62 before, 0 after
git grep -nE '^[^#]*(source|\.)[^#]*package_capture\.sh' \
  -- lib/ scripts/ setup_env.sh tests/ | wc -l          # 4 before, 0 after
bash scripts/run-bash-coverage.sh                       # TOTAL >= 91%
```

**Expected observable change:** `make test` reports 1622 tests instead of 1659; both symbol greps go to 0; coverage holds at 91%.

**Edge cases exercised:** the two collateral tests must still pass after editing (they are the ones most likely to break); `bash scripts/run-bash-coverage.sh --list-sources` must drop from 38 to 37 entries.

**Baseline conditions.** Every figure above was measured on this tree under the current `.shellcheckrc` and the current instrumented set, neither of which this plan changes. The coverage figure was measured in a worktree with all deletions applied, not predicted.

---

### Task 1: Delete `lib/package_capture.sh` and its two dedicated test files

```yaml-task
id: 1
description: Remove the package_capture module and both of its dedicated bats files (docs-free code deletion, no behavior to test-drive since the module has zero production callers)
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: 'test ! -e lib/package_capture.sh'
    exit_code: 0
  - cmd: 'test ! -e tests/test_package_capture.bats'
    exit_code: 0
  - cmd: 'test ! -e tests/setup_env/package_capture.bats'
    exit_code: 0
max_retries: 3
files_touched:
  - lib/package_capture.sh
  - tests/test_package_capture.bats
  - tests/setup_env/package_capture.bats
depends_on: []
```

**Files:** delete all three outright. `git rm` them.

`tdd: not-applicable` — this is removal of a module with no production callers; there is no behaviour to drive with a failing test. The two collateral tests that DO reference it are Task 2's job, so `make test` will still be red at the end of this task. That is expected and Task 2 closes it.

**Interfaces:**

- Consumes: nothing.
- Produces: the absence of `lib/package_capture.sh`. Tasks 2 and 5 both depend on that absence.

---

### Task 2: Fix the two collateral tests that reference the deleted file

```yaml-task
id: 2
description: Delete the linux_shared.bats block that sources package_capture.sh and substitute update_summary.sh for it in the unit.bats tracer loop (test-only edit, verified by the suite going green)
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: 'git grep -nE "^[^#]*(source|\.)[^#]*package_capture\.sh" -- lib/ scripts/ setup_env.sh tests/ | wc -l | grep -qx 0'
    exit_code: 0
  - cmd: 'grep -q "lib/update_summary.sh" tests/scripts/unit.bats'
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - tests/setup_env/linux_shared.bats
  - tests/scripts/unit.bats
depends_on: [1]
```

**Files:**

`tests/setup_env/linux_shared.bats` — delete the whole block: the six-line section banner at `:120-126`, the `@test "shared dpkg-query mock: _list_apt_packages parses the two-token legacy form"` at `:128`, its `# shellcheck disable=SC1091` at `:129`, and the body through its closing brace. Leave nothing behind — the banner describes a test that no longer exists and names a file that no longer exists.

Do NOT touch `:145-146` (`MOCK_DPKG_STATUS_zsh` / `_zsh_doc`). Those drive the mock's separate-token **status** form, which `lib/linux_shared.sh:5` still uses in production, and they are the surviving test driver for the mock's `-f` argument consumption.

`tests/scripts/unit.bats:1653` — **substitute, do not shrink.** Change:

```bash
for _f in lib/git_sync.sh lib/package_capture.sh scripts/bootstrap_mac.sh scripts/pre-push lib/helpers.sh; do
```

to:

```bash
for _f in lib/git_sync.sh lib/update_summary.sh scripts/bootstrap_mac.sh scripts/pre-push lib/helpers.sh; do
```

`lib/package_capture.sh` is the only member of that loop carrying `python3 -c` (4 occurrences; the other four files have zero). That is the exclusion class with the largest historical denominator error in this repo — 54 of 107 lines, per `CLAUDE.md:447`. Dropping to four members leaves the two-mode reconciliation with no coverage of that construct. `lib/update_summary.sh` carries one and is in the instrumented set.

`tdd: not-applicable` — both edits are to test files; the suite itself is the test.

**Interfaces:**

- Consumes: absence of `lib/package_capture.sh` from Task 1.
- Produces: a green `make test` at 1622 tests. Tasks 3 and 4 assume the suite is green.

---

### Task 3: Delete `brew_install_cask` and `brew_cask_installed` with their 8 tests

```yaml-task
id: 3
description: Remove both cask helpers from lib/helpers.sh and their 8 tests from install_guards.bats (removal of functions with zero reachable callers)
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: 'git grep -nE "^[^#]*(brew_install_cask|brew_cask_installed)" -- lib/ scripts/ setup_env.sh tests/ | wc -l | grep -qx 0'
    exit_code: 0
  - cmd: 'git grep -nE "^[^#]*brew_formula_installed" -- lib/ | wc -l | grep -qx 2'
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - lib/helpers.sh
  - tests/setup_env/install_guards.bats
depends_on: [2]
```

**Files:**

`lib/helpers.sh` — delete `brew_cask_installed()` (`:187`) and `brew_install_cask()` (`:209`), each with its contiguous comment block above.

`brew_cask_installed` goes because its only two references are its own definition and the call at `:214` inside `brew_install_cask`. Deleting only the caller would relocate the dead-code boundary instead of closing it.

**`brew_formula_installed` STAYS.** It is in the identical structural position — definition at `:175`, one call at `:204` inside `brew_install_formula` — but `brew_install_formula` has 37 production callers, so it is reachable transitively. The second acceptance gate pins this at exactly 2 occurrences so an over-eager deletion fails.

`tests/setup_env/install_guards.bats` — delete the 4 `@test "brew_install_cask ...` and the 4 `@test "brew_cask_installed ...` blocks, plus any section banner comment introducing them.

**Interfaces:**

- Consumes: green suite from Task 2.
- Produces: `lib/helpers.sh` without either cask helper. Task 6 removes `CLAUDE.md:176`, which advertises `brew_cask_installed`.

---

### Task 4: Delete `ledger_flush_spool` and its 4 tests

```yaml-task
id: 4
description: Remove the redundant ledger flush wrapper from lib/workflows.sh and its 4 tests (cmd_write already drains the spool, so the wrapper adds nothing)
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: 'git grep -nE "^[^#]*ledger_flush_spool" -- lib/ scripts/ setup_env.sh tests/ | wc -l | grep -qx 0'
    exit_code: 0
  - cmd: 'git grep -nE "^[^#]*ledger_write_entry" -- lib/ | wc -l | grep -vqx 0'
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - lib/workflows.sh
  - tests/setup_env/ledger_integration.bats
depends_on: [3]
```

**Files:**

`lib/workflows.sh` — delete `ledger_flush_spool()` at `:947`, 10 lines, plus its comment block.

**`ledger_write_entry` STAYS** — it is the live write path with production callers. The second gate asserts it is still present; a non-zero count is the contract, not a specific number, because the count is not what this task controls.

`tests/setup_env/ledger_integration.bats` — delete the section banner at `:88` and the 4 `@test "ledger_flush_spool: ...` blocks (`:90`, `:97`, `:105`, `:126`).

**Interfaces:**

- Consumes: green suite from Task 3.
- Produces: `lib/workflows.sh` without the wrapper. Task 5 amends the ADR that cites it.

---

### Task 5: Amend ADR-0014 and mirror the note in the ADR index

```yaml-task
id: 5
description: Append a dated amendment to ADR-0014, add a Status-line pointer, and mirror it in docs/adr/README.md (docs-only, no behavior change)
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: 'grep -qE "^\*\*Status:\*\*.*amended 2026-09-09" docs/adr/0014-state-ledger-cmdb-integration.md'
    exit_code: 0
  - cmd: 'grep -qiE "amendment" docs/adr/0014-state-ledger-cmdb-integration.md'
    exit_code: 0
  - cmd: 'grep -qE "0014.*amended" docs/adr/README.md'
    exit_code: 0
max_retries: 3
files_touched:
  - docs/adr/0014-state-ledger-cmdb-integration.md
  - docs/adr/README.md
depends_on: [4]
```

**Files:**

`docs/adr/0014-state-ledger-cmdb-integration.md` — **do not rewrite the original reasoning.** An ADR is a historical record. Two things:

1. `:4` currently reads `**Status:** Accepted`. Change to:
   `**Status:** Accepted — amended 2026-09-09 (ledger_flush_spool deleted; cmd_write is the drain)`
2. Append an `## Amendment 2026-09-09` section at the bottom recording: `ledger_flush_spool` was deleted as redundant; `cmd_write` calls `_flush_spool_internal` at `state-ledger/scripts/ledger.py:443` and is the only automatic drain on this fleet; no daemon or cron trigger was ever required, contrary to `:33-34`; the spool mechanism claim at `:84` is true but names the wrong mechanism.

The Status-line pointer exists because the two wrong claims sit ~70 lines above any appended note, and a reader acts on them before reaching it.

`docs/adr/README.md:20` — status cell currently `Accepted`. Add the amendment marker so the index does not read a bare `Accepted`.

**Gate note:** the Status pattern is `grep -qE` with `.*`, deliberately tolerant. 25 of 30 ADRs use `**Status:**` and a literal-byte match would mandate where the asterisks go rather than test the content. An artifact that satisfies the intent and would fail a stricter pattern: `**Status:** Accepted (amended 2026-09-09)` — the tolerant form accepts it, an exact-substring form would not.

**Interfaces:**

- Consumes: `ledger_flush_spool` gone, from Task 4.
- Produces: an ADR that stops asserting a deleted function is the drain.

---

### Task 6: Four CLAUDE.md content edits

```yaml-task
id: 6
description: Fix the layout tree, the Homebrew Helpers list, the two runnable worked examples, and the three-site ledger citation (docs-only, no behavior change)
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: 'git grep -nE "^[^#]*package_capture" -- CLAUDE.md | wc -l | grep -qx 0'
    exit_code: 0
  - cmd: 'grep -q "brew_cask_installed" CLAUDE.md; test $? -ne 0'
    exit_code: 0
  - cmd: 'bash scripts/run-bash-coverage.sh --count-coverable lib/helpers.sh'
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched:
  - CLAUDE.md
depends_on: [5]
```

**Files:** `CLAUDE.md`, four sites.

`:15` — the layout tree's `lib/` entry says **"all 14 tracked"** and lists `package_capture`. Remove it from the list and change the count to **13**. Both the count and the membership are wrong otherwise.

`:176` — delete the `brew_cask_installed <cask>` line from the Homebrew Helpers block. Leave `brew_formula_installed <formula>` and `quiet_which <command>`.

`:461-462` — the two worked examples name the deleted file:

```bash
bash scripts/run-bash-coverage.sh --count-coverable lib/package_capture.sh
bash scripts/run-bash-coverage.sh --file-coverage lib/package_capture.sh /path/to/trace
```

Substitute `lib/helpers.sh`. These are copy-pasteable commands a reader is invited to run; leaving them names a file that does not exist. The third acceptance gate runs the substituted command for real.

`:766` — reads "`lib/workflows.sh:898`, `:917` and `lib/package_capture.sh:11` all carry that same fallback". It is now two sites, not three. Reword to name the two survivors.

**Leave `:447` alone.** It is a historical record of a heuristic fix ("it reported 22% against a ceiling it could not reach"), not live drift. It is the one `package_capture` mention in `CLAUDE.md` that stays — which is why the first gate is anchored `^[^#]*` and `:447` is inside a markdown bullet, not a comment. Verify by running the gate: if it returns 1 because of `:447`, exclude that line explicitly rather than deleting the history.

**Interfaces:**

- Consumes: all deletions complete.
- Produces: `CLAUDE.md` free of live references. Task 7 adds the figures.

---

### Task 7: Record the measured test count and coverage figures

```yaml-task
id: 7
description: Append the post-change test-count and coverage bullets per that section's own convention (docs-only, figures measured not predicted)
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: 'grep -qE "162[0-9] tests" CLAUDE.md'
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - CLAUDE.md
depends_on: [6]
```

**Files:** `CLAUDE.md`, two figure sites.

`:352` — the `test` job bullet carries `1659 tests, CI-measured 2026-09-07 on bb7b6ab, run 34148440502`. Update to the count `make test` actually reports on this branch. Do not guess: run `make test` and read the final `1..N` line.

`:406-410` — the coverage bullets. That section's own convention is an **appended bullet, not an edit**: each reading supersedes the one above it and the history stays readable. Add a new bullet in the same shape as its neighbours, carrying the local figure and stating plainly that it is local rather than CI — CI's figure replaces it post-merge, per that section's rule that the gate reads CI's number.

Local measurement, already taken in a worktree with every deletion applied:

```
TOTAL          3542/3857  91.83%
tests               1622
disagreements         18
instrumented          37
```

Do not write a CI run id — there is not one yet. Say "local, pending CI".

**Interfaces:**

- Consumes: green suite from Task 6.
- Produces: `CLAUDE.md` figures matching the tree.

---

### Task 8: Retire the three resolved backlog rows

```yaml-task
id: 8
description: Remove the three backlog rows this plan closes and mark the plan index row Done (docs-only, index maintenance)
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: 'grep -qE "has no production caller|dead code that would report every package" docs/superpowers/README.md; test $? -ne 0'
    exit_code: 0
  - cmd: 'grep -qE "2026-09-09-unwired-units-cleanup" docs/superpowers/README.md'
    exit_code: 0
  - cmd: 'grep -q "Status: DONE" docs/superpowers/plans/2026-09-09-unwired-units-cleanup.md'
    exit_code: 0
max_retries: 3
files_touched:
  - docs/superpowers/README.md
  - docs/superpowers/plans/2026-09-09-unwired-units-cleanup.md
depends_on: [7]
```

**Files:** `docs/superpowers/README.md`.

Remove three now-closed Backlog rows:

- `` `brew_install_cask` has no production caller ``
- `` `ledger_flush_spool` has no production caller, and an ADR asserts it works ``
- `` `package_capture` is dead code that would report every package as added ``

**Keep** the two rows this plan created and did not close: the spool-depth observability row, and the `brew_*` helpers audit row.

In the All Plans table, add the plan row pointing at this file with status `Done`, and add a `> **Status: DONE**` banner at the top of this plan file.

**Gate corrected mid-execution (re-plan, Swap approach).** The original gate was
`grep -q "brew_install_cask" ... ; test $? -ne 0` — a bare-symbol grep over the whole file.
It was unsatisfiable: the KEPT row "Are the advertised `brew_*` helpers actually used?"
legitimately names `brew_install_cask` in its prose, explaining why that helper was deleted.
The only way to pass was to alter or delete a row the same task's FORBIDDEN list protected.
The executor refused and reported a blocker rather than contorting the file, which is the
correct response to a gate that cannot pass. Replaced with a scoped property matching the
deleted rows' own identifying text. The work itself was correct and needed no change.

`model: sonnet` — two files. This was authored as `haiku` with one file declared while the prose described editing two; the scope guard would have accepted the under-declaration rather than catching it, and the mismatch would have surfaced at dispatch.

**Interfaces:**

- Consumes: everything above complete.
- Produces: a backlog with no stale rows.
