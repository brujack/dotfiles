# run_tmpdir EXIT Trap Removal Implementation Plan

> **Status: DONE** — merged as dotfiles#254 on 2026-09-05.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Delete `lib/workflows.sh:109`'s EXIT/INT/TERM trap, which swallows abort signals in production and clobbers bats' EXIT trap at 35 test call sites, and pin the resulting invariant so it cannot come back.

**Architecture:** One production line is deleted (Group A). Twenty-seven test-side save/restore blocks written to work around its effect become dead and are removed (Group B). Three guards land: two behavioural tests pinning that `_dotfiles_run_tmpdir_setup` leaves the caller's traps alone and that a run still dies on SIGTERM, and one allowlist ratchet enumerating every `EXIT` trap in `lib/*.sh` (Group C). Docs record the changed exit contract (Group D).

**Tech Stack:** bash, bats-core, GNU/BSD `trap`, `git ls-files`, Make.

**Spec:** [2026-09-04-run-tmpdir-exit-trap-design.md](../specs/2026-09-04-run-tmpdir-exit-trap-design.md) at `bbe4c324`.

## Global Constraints

- **Assert non-zero, never a literal signal number.** 130/143 are conventional, not portable; this suite runs on macOS and Linux.
- **The 27 `run_update` call sites stay bare.** All 27 read `_DOTFILES_RUN_TMPDIR` after the call; `run` executes in a subshell and loses it. Only the save/restore blocks are removed.
- **No `! grep` site is touched anywhere in the repo.** Spec M8: 81 sites, 81 effective, 0 defects. Any change here is out of scope.
- **The allowlist is keyed on file plus count, never on line numbers**, which move on every edit.
- **`lib/developer.sh:72` keeps its EXIT trap.** It is inside a `( )` subshell with its rationale at `lib/developer.sh:38-44`, and it is the allowlisted entry.
- Every task's `acceptance` includes `make test`. Tasks are sequential; no `parallel_group`.

---

### Task 1: Guards G1/G2 and deletion of the trap

```yaml-task
id: 1
description: Add the trap-isolation and SIGTERM-abort tests, watch them fail, then delete lib/workflows.sh:109 and refresh the two stale comments in that file
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: 'bats tests/setup_env/run_tmpdir_traps.bats'
    exit_code: 0
  - cmd: 'bash -c "! grep -qE \"^[[:space:]]*trap[[:space:]].*EXIT\" lib/workflows.sh"'
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - tests/setup_env/run_tmpdir_traps.bats
  - lib/workflows.sh
depends_on: []
```

**Files:** new `tests/setup_env/run_tmpdir_traps.bats`; edit `lib/workflows.sh`.

**Write the tests first and confirm both fail before touching `lib/`.**

- **G1** — `_dotfiles_run_tmpdir_setup` leaves the caller's EXIT, INT and TERM traps identical. Capture `trap -p EXIT`, `trap -p INT`, `trap -p TERM` before and after the call; assert all three unchanged. All three signals, not EXIT alone: a future handler on INT/TERM without an `exit` reintroduces the signal defect while leaving EXIT clean.
- **G2** — a script that sources `lib/workflows.sh`, calls `_dotfiles_run_tmpdir_setup`, then blocks, still dies on SIGTERM. Assert exit status **non-zero**. Both directions matter: a G2 checking only the post-fix direction passes against a trap that never installed.

**Expected RED, measured on `bbe4c324`:** G1 does not print `not ok` — it _vanishes_ from the TAP stream, because the trap it is detecting has already replaced bats' reporting. The run emits `bats warning: Executed N-1 instead of expected N` and exits non-zero. That is the defect demonstrating itself; do not read the missing `not ok` as a pass. G2 fails normally.

**Then** delete line 109, `trap 'unset _DOTFILES_RUN_TMPDIR' EXIT INT TERM`. Nothing replaces it.

**Same commit, same file — two comments whose stated reason is now gone:**

- `lib/workflows.sh:196-205` explains `|| _hooks_rc=$?` as a workaround for this clobber. **Keep the code** — it is independently correct and matches the surrounding `setup_claude_mcp || return 1` style — and rewrite the comment to say so without citing the trap.
- The `_dotfiles_run_tmpdir_setup`-references-its-own-EXIT-trap remark at `lib/workflows.sh:199`.

**Interfaces:**

- Produces: `tests/setup_env/run_tmpdir_traps.bats` with tests named `G1` and `G2`; `_dotfiles_run_tmpdir_setup` installing no trap.
- Consumes: nothing.

---

### Task 2: Remove the 27 dead save/restore blocks

```yaml-task
id: 2
description: Delete the 27 now-dead bats EXIT-trap save/restore blocks in workflows.bats and the stale comment in ledger_integration.bats, proving the ok/not-ok set is unchanged
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: 'bash -c "test $(grep -c \"trap -p EXIT\" tests/setup_env/workflows.bats) -eq 0"'
    exit_code: 0
  - cmd: 'bash -c "test $(grep -cE \"^[[:space:]]*run_update[[:space:]]*$\" tests/setup_env/workflows.bats) -eq 27"'
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - tests/setup_env/workflows.bats
  - tests/setup_env/ledger_integration.bats
depends_on: [1]
```

**`tdd: not-applicable` justification:** this deletes test scaffolding, adds no behaviour, and its correctness claim is behaviour-preservation. The differential below is the gate; a new test would assert nothing a diff does not.

**Files:** `tests/setup_env/workflows.bats`, `tests/setup_env/ledger_integration.bats`.

**Capture the baseline BEFORE editing** — it cannot be reconstructed afterwards:

```bash
bats tests/setup_env/workflows.bats > /tmp/wf-before.tap 2>&1
grep -E '^(ok|not ok)' /tmp/wf-before.tap | sed -E 's/^(ok|not ok) [0-9]+ //' | sort > /tmp/wf-before.set
```

Baseline on `cd9c0a6d` was 214 planned, 214 executed, 0 `not ok`, no warning.

**Then** delete each of the 27 blocks — the `local _bats_exit_trap` declaration, the `_bats_exit_trap="$(trap -p EXIT)"` capture, the `eval "${_bats_exit_trap}"` line, and the `# Bare call so _DOTFILES_RUN_TMPDIR survives; save/restore bats' EXIT trap` comment introducing each. **Leave every `run_update` call itself bare.** Sites include `:1202, 1236, 1253, 1289, 1318, 1353, 1376, 1676, 1760, 1784, 1808, 1840, 1873, 1893, 1915`; find the rest with `grep -n 'trap -p EXIT' tests/setup_env/workflows.bats`.

Also refresh `tests/setup_env/ledger_integration.bats:350`, whose comment explains `run --separate-stderr` as a workaround for the same clobber. Keep the `run` — it is correct for its own reasons — and drop the stale justification.

**Amended after Task 1's spec-compliance review, which surfaced this as uncovered.** Deleting
the 27 blocks removes the 27 `# Bare call so _DOTFILES_RUN_TMPDIR survives; save/restore bats'
EXIT trap` comments with them, but **14 further comment lines in the same file describe the
trap in the present tense and survive**, at roughly 318-319, 1840, 1872-1873, 1914-1915,
1941-1942, 2446-2447, 2580, 2740 and 2899. They say things like "run_update's own EXIT trap
(`_dotfiles_run_tmpdir_setup`) has already clobbered bats' trap-based 'not ok' reporting",
which is false once Task 1 lands.

Rewrite each past-tense, or delete it where the surrounding code no longer needs the
explanation. Two constraints carried from Task 1's own review: **do not cite
`lib/workflows.sh:<line>`** — CLAUDE.md records that exact citation drifting for
`tests/mocks/curl`, so name the enclosing function instead; and where a comment justifies a
construct that is still correct for an independent reason (e.g. `run --separate-stderr` at
`ledger_integration.bats:350`), keep the construct and re-justify it rather than deleting both.

**That enumeration was wrong twice, and the correction is the point.** The first version of
this amendment gave
`grep -nE 'EXIT trap|trap-based|clobber' tests/setup_env/workflows.bats`. It is scoped to one
file, and its pattern cannot match a line that carries none of the three tokens —
`ledger_integration.bats:343` is `# the trap only unsets the variable; it never removes the
dir`, which is false after Task 1 and invisible to that grep. A worklist that reports done
while leaving instances false is the omission-invisible-to-its-own-instrument shape `tdd.md`
describes for coverage denominators.

Enumerate wider, then **read every hit** — this pattern is a starting point, not an oracle:

    git grep -nE 'EXIT trap|trap-based|clobber|the trap|its own trap' -- 'tests/*.bats' \
      | grep -v 'Bare call so _DOTFILES_RUN_TMPDIR survives'

Measured 2026-09-04: 36 hits across 7 files (`scripts/unit.bats`, `setup_env/developer.bats`,
`setup_env/launch_agents.bats`, `setup_env/ledger_integration.bats`,
`setup_env/run_tmpdir_traps.bats`, `setup_env/unit.bats`, `setup_env/workflows.bats`). Most are
unrelated traps and stay; the ones that must change are those describing
`_dotfiles_run_tmpdir_setup`'s trap specifically.

**One of them is a test NAME, and that collides with this task's own gate.**
`ledger_integration.bats:332` is `@test "_dotfiles_run_tmpdir_setup: directory survives the
EXIT trap"`. Renaming it changes the TAP output, and the differential below compares the
`ok`/`not ok` **set** — so a rename fails that gate by construction, not by regression. If the
name is changed, do it in its own commit and record the old and new names in the task report,
so the set comparison is evaluated against a stated one-line substitution rather than silently
re-baselined. Leaving the name alone and fixing only `:343`'s body is also acceptable; say which
was chosen.


**Differential, required:** re-run and diff the sets. `DIVERGING: 0` is the gate.

```bash
bats tests/setup_env/workflows.bats > /tmp/wf-after.tap 2>&1
grep -E '^(ok|not ok)' /tmp/wf-after.tap | sed -E 's/^(ok|not ok) [0-9]+ //' | sort > /tmp/wf-after.set
diff /tmp/wf-before.set /tmp/wf-after.set && echo "DIVERGING: 0"
grep -c 'bats warning: Executed' /tmp/wf-after.tap   # must be 0
```

Compare the **set**, not the count — a count is equal under a swap.

**Interfaces:**

- Consumes: Task 1's deleted trap (the blocks are only dead once it is gone).
- Produces: `workflows.bats` with zero `trap -p EXIT` occurrences and 27 bare `run_update` calls intact.

---

### Task 3: G3, the lib EXIT-trap allowlist ratchet

```yaml-task
id: 3
description: Add a scope-seamed scanner enumerating every EXIT trap in lib/*.sh against a reasoned allowlist, its bats suite, and the make lint wiring
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: 'bats tests/scripts/check_lib_exit_traps.bats'
    exit_code: 0
  - cmd: 'bash scripts/check-lib-exit-traps.sh'
    exit_code: 0
  - cmd: make lint
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - scripts/check-lib-exit-traps.sh
  - tests/scripts/check_lib_exit_traps.bats
  - Makefile
depends_on: [1]
```

**Files:** new `scripts/check-lib-exit-traps.sh`, new `tests/scripts/check_lib_exit_traps.bats`, edit `Makefile`.

**The scanner does not decide scope, deliberately.** After Task 1 the only textual difference between `lib/developer.sh:72`'s permitted subshell trap and a function-scope one is indentation, and deciding containment from text needs a bash parser this repo does not have. Approximating it by position is what the withdrawn `! grep` scanner died of. So the check **enumerates** and compares against an allowlist; a new trap fails until a human adds it with a reason.

**Scanner contract:**

- Scope from `git ls-files 'lib/*.sh'` under `env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE`. The strip is load-bearing: `git -C` does not override an exported `GIT_DIR`, and `scripts/pre-push` runs `make test`, so a push from a worktree would otherwise resolve against the wrong repository.
- Seam `_OVERRIDE_LIB_TRAP_SCOPE` selects an alternate directory, so the bats suite can drive both verdicts against fixtures without touching real `lib/`. Follows the repo's existing `_OVERRIDE_*` convention.
- **Empty scope exits 2, not 1** — a broken scope must be distinguishable from a real finding. Measured: 14 files in scope today.
- Allowlist entries are `path count reason`, keyed on file and count, never line numbers. Sole entry after Task 1: `lib/developer.sh 1`, reason "subshell-scoped gpg homedir cleanup, see lib/developer.sh:38-44".
- Findings name the file and count and point at the allowlist.

**Falsifiability, measured on `bbe4c324` before writing this plan:**

```
pre-change  (trap present):  exit=1, reports "lib/workflows.sh 1"
post-change (trap deleted):  exit=0
empty scope:                 exit=2
```

**Tests, all via the seam against fixtures:**

- An un-allowlisted function-scope trap is reported.
- The allowlisted file at its allowlisted count is clean.
- **A trap inside a `( )` subshell is STILL reported.** This is the point: G3 does not infer containment, so a subshell trap is a finding until allowlisted. Pin it, so a later "improvement" toward inference fails this test.
- A count change in an allowlisted file is reported.
- Empty scope exits 2.
- The real `lib/` is clean against the real allowlist.

**Wire into `make lint`** with the missing-tool-guard idiom already in this Makefile, so the gate degrades with a named remedy rather than locking the machine out of committing.

**Interfaces:**

- Consumes: Task 1's deleted trap (the real-`lib/` test is only clean after it).
- Produces: `scripts/check-lib-exit-traps.sh` honouring `_OVERRIDE_LIB_TRAP_SCOPE`; a `check-lib-exit-traps` Make target reachable from `lint`.

---

### Task 4: Documentation

```yaml-task
id: 4
description: Record the changed exit contract in CLAUDE.md and ADR-0027 (docs-only, no behaviour change, so TDD does not apply)
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: 'grep -qE "SIGINT|SIGTERM" CLAUDE.md'
    exit_code: 0
  - cmd: 'grep -qiE "interrupt" docs/adr/0027-update-run-exit-code-from-section-status.md'
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - CLAUDE.md
  - docs/adr/0027-update-run-exit-code-from-section-status.md
depends_on: [1]
```

**`tdd: not-applicable` justification:** prose only, no executable logic.

**Files:** `CLAUDE.md`, `docs/adr/0027-update-run-exit-code-from-section-status.md`.

**`CLAUDE.md`, the `-t update` row:** SIGINT/SIGTERM now abort the run.

**`CLAUDE.md`, the `recreate-venv` and `recreate-ruby` rows:** an interrupt during the rebuild leaves the toolchain **deleted**, and re-running the same command recovers it. State it plainly rather than as a warning against interrupting — per spec M9 the toolchain is lost on interrupt today as well, and all that changes is that the shell now stops instead of continuing to a verification error. For `recreate-venv`, note that recovery must repeat any `--venv-name` the original invocation carried: a bare re-run rebuilds `ansible` instead, because `lib/developer.sh:547` gates the `uv sync` on that name.

**ADR-0027:** add the interrupt case. An interrupted run exits non-zero with no summary, no `~/.dotfiles-update.log` entry and no state-ledger entry, because `_update_summary` and `_ledger_write_dotfiles_entry` are never reached.

**State it with spec M10 attached**, or it reads as a pure regression: today the same interrupt produces a _complete summary containing FAIL rows for sections the operator killed_ and writes them to the CMDB. The change trades a false record for no record. A partial-but-true record is better than either and is Deferred.

**Interfaces:**

- Consumes: Task 1's behaviour change.
- Produces: nothing consumed by later tasks.

---

## Session-Level Verification

Run after Task 4, from a clean tree:

```bash
make test                                   # exit 0; plan line present and equal to executed
make lint                                   # exit 0
bats tests/setup_env/run_tmpdir_traps.bats  # G1, G2 both ok
bash scripts/check-lib-exit-traps.sh        # exit 0
```

**Assert on the plan line, not only on the absence of a warning.** `grep -c 'bats warning: Executed'` returning 0 passes over a suite that never ran; the plan line is what makes it an assertion about a measurement.

**Mutation control — the whole point of the change.** Restore `trap 'unset _DOTFILES_RUN_TMPDIR' EXIT INT TERM` at `lib/workflows.sh:109` and confirm **all three** go red: G1 (by vanishing, plus the plan-mismatch warning), G2 (`SURVIVED-SIGTERM`, rc 0), and `check-lib-exit-traps.sh` (exit 1, naming `lib/workflows.sh 1`). Then remove it again and confirm all three green. A guard that only passes has not been shown to be able to fail.

**Edge case that must be exercised — the property the change exists to produce.** Spec V8: stage a `run_update` section FAIL, call it bare in a fixture, and assert the outer `bats` output carries `not ok` **with the test's name**. Neither G1 nor G2 asserts this: G1 is about traps, G2 about signals. Pre-change this fixture vanishes; post-change it names itself. Fold into Task 1's suite if a fixture is cheap there; otherwise run it by hand at session level and record the output.

**Out of scope, stated so a reviewer does not look for it:** no `! grep` assertion changes anywhere (spec M8 — 81 sites, 81 effective, 0 defects), and no abort guard for the recreate workflows (spec Group A2, withdrawn — its premise was measured with the wrong actor and the toolchain is lost either way).

## Plan Self-Review

**Spec coverage.** Group A → Task 1. Group B → Task 2. Group C: G1/G2 → Task 1, G3 → Task 3.
Group D → Task 4. Verification: V1/V2 → the session-level mutation control; V3/V4/V5 → Task 3's
fixture suite; V6 → Task 2's differential; V7 → session-level; V8 → session-level, foldable into
Task 1. No spec requirement is unmapped.

**ADR significance — considered, and the answer is no new ADR.** Task 3 adds a gate reachable
from `make lint`, and `repo-structure.md` lists structural patterns and CI approach as
ADR-worthy, so this was not waved through. The comparable gates that did get ADRs
(`perf-regression`, `skill-review`, `skill-retirement`) are Phase 3 gates with HOLD verdicts and
cross-repo reach. G3 is a ~40-line single-repo lint check whose nearest neighbours — the
`shellcheck` wiring, the `.shellcheckrc` policy, `make check-agent-guidance` — are all recorded
in `CLAUDE.md` rather than in an ADR. The contract change that *is* architectural is the exit
semantics of an interrupted `-t update`, and that lands as an amendment to the ADR that already
owns it (ADR-0027, Task 4). Recorded here so the absence reads as a decision.

**Gate falsifiability, measured on `bbe4c324` before dispatch rather than asserted:**

| gate | pre-change | post-change |
| --- | --- | --- |
| G1 | vanishes from TAP + plan-mismatch warning, rc non-zero | `ok` |
| G2 | `SURVIVED-SIGTERM`, rc 0 | dead, rc non-zero |
| G3 | `exit=1`, reports `lib/workflows.sh 1` | `exit=0` |
| G3 empty scope | `exit=2` — distinguishable from a finding | — |

**One wrong implementation that would still pass each gate**, per the skill's third question.
G1 alone is satisfied by a `_dotfiles_run_tmpdir_setup` that installs a trap and restores it
around the `mktemp`, leaving signal handling broken — G2 is the behavioural control for exactly
that, which is why both exist rather than one. G3 alone is satisfied by a scanner that
special-cases `lib/developer.sh` by name and is blind to the class — Task 3's subshell fixture
test is the control, since it requires a subshell trap to be reported rather than excused.
Task 2's differential is satisfied by a no-op edit, which is why its acceptance also asserts the
`trap -p EXIT` count is 0 and the bare `run_update` count is still 27.

**Deliberately not planned:** any `! grep` change (spec M8 — 81 sites, 81 effective, 0 defects),
and any abort guard for the recreate workflows (spec Group A2, withdrawn on measurement).
