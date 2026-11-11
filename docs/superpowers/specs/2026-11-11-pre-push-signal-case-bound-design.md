# Remove the wall-clock bound from the pre-push signal cases

Backlog row: "`dirty-tree: interrupt (TERM)` fails its 8 s wall-clock bound on the macOS
runner". Recurred 2026-11-10 on dotfiles#460 (run 42945438847, attempt 1, `test-macos-shard
(3)`, `not ok 310`, the hook's status correct at `143`); attempt 2 of the same SHA passed.

- **Approved:** 2026-11-11, operator: "Yes"

## Problem

`_signal_case` in `tests/scripts/pre_push.bats` (used by `dirty-tree: interrupt (TERM)` and
`dirty-tree: interrupt (INT)`) sets `SECONDS=0` before running the hook and then asserts
`[ "${SECONDS}" -lt 8 ]`. On a loaded macOS runner the case can exceed 8 s while every
behavioural assertion holds, so the bound fails a correct hook.

The row framed the question as "find a bound that still catches a hook that exits without
waiting for its cleanup subshell". That premise is false: measured below, a hook that does not
wait is caught by `_assert_temp_gone`, and the bound detects only a slow-but-correct
interrupted exit (a cleanup that takes longer than about 5 s but finishes), which no
requirement forbids: the 2026-10-25 dirty-tree spec's R4 requires only that cleanup finish
before the hook exits.

## Measurements

All on `claude` (Linux, bash 5.3), in a detached worktree of master `eb431118`, running
`bats -f` on the one or two signal cases. Each mutation was applied, run, and reverted with
`git checkout --`.

| Run     | Change                                                    | Result                                     | Assertion that failed                                   |
| ------- | --------------------------------------------------------- | ------------------------------------------ | ------------------------------------------------------- |
| base x3 | none                                                      | TERM passes, 3.2 s each (whole `bats` run) | none                                                    |
| M2      | hook's `trap 'exit 143' TERM` replaced by `: no-trap`     | TERM fails in 1 s                          | `_assert_temp_gone` (line 1371)                         |
| M1-TERM | `make` mock runs `trap "" TERM INT` before `kill -TERM 0` | TERM passes in 3 s                         | none                                                    |
| M1-INT  | the same mock change, INT case                            | INT fails in 13 s                          | `[ "$output" = "${_want}" ]` (line 1650), not the bound |
| control | bound line deleted                                        | TERM and INT both pass                     | none                                                    |
| control | bound line deleted, plus M2                               | TERM fails                                 | `_assert_temp_gone`                                     |
| M4      | `sleep 9;` prepended to the hook's EXIT-trap cleanup (Step 8 Goal-Fit) | both fail with the bound (line 1651); both pass without it, 23 s | the bound only |

Population: one machine, an unloaded Linux box, one or two cases per run. The claim drawn
from it is about which assertion each mutation trips, which does not depend on load; the
macOS timing itself was not measured here (the CI log records only the failure).

Why each result holds:

- **M2.** The test's `git` shim sleeps 1 s on every `worktree remove`, so a hook that exits
  without waiting returns while the temporary checkout still exists. `_assert_temp_gone`
  sees it. This is the guard the row attributed to the bound.
- **M1-TERM.** A TERM to the process group kills the cleanup subshell too; its EXIT trap
  cleans up and nothing waits for the orphaned `make`. Real `make` dies on TERM, so a
  surviving suite is a property of the mock, not of the hook.
- **M1-INT.** bash waits for a foreground child on SIGINT and, when the child survives,
  does not exit with 130. The status assertion catches it before the bound is read.
- **M4.** A slow cleanup still finishes before the hook exits, so status, worktree and
  temp-gone assertions all hold; only elapsed time differs. Promptness of an interrupted
  push is not a requirement, so losing this detection is accepted (operator, 2026-11-11).

`_assert_temp_gone` is itself timing-based: it sees a no-wait hook only if bats reaches it
within the shim's 1 s sleep. On a heavily loaded runner it can miss M2, which fails in the
safe direction (a silent pass, never a red on a correct hook). This is unchanged by the
spec.

The hang protection the 2026-10-25 dirty-tree spec asked for ("a bounded mock", Risk (2))
is the mock's own `sleep 10` after `kill`, not this assertion. It stays.

## Design

Delete `SECONDS=0` and `[ "${SECONDS}" -lt 8 ]` from `_signal_case`. Rewrite the existing
comment above the `git` shim ("Slow the cleanup's worktree removal so a hook shell that
exits without waiting ... is caught, not raced") in place rather than adding a second one, dropping "not raced": it names
`_assert_temp_gone` as the check that catches that hook, says the check relies on the 1 s
delay and that a miss is a silent pass, and says there is no wall-clock bound because it detected only a slow-but-correct
interrupted exit, which no requirement forbids. Remove the backlog row.

No change to `scripts/pre-push`, to the `make` mock, or to any other case.

## Rejected

- **Widen the bound (for example to 30 s).** Would still catch a cleanup that runs for tens
  of seconds, with a much wider flake margin. Rejected by the operator (2026-11-11): it pins
  a property no requirement asks for, at a standing timing risk.
- **A marker file written by the mock if it survives the signal.** Tests the harness's own
  signal delivery, not a hook requirement.

## Verification

Before committing: delete the bound, run both signal cases (pass); apply M2 and re-run the
TERM case (fails at `_assert_temp_gone`); revert. `make test` exits 0.

## Requirements

- **R1.** `_signal_case` in `tests/scripts/pre_push.bats` contains neither `SECONDS=0` nor `[ "${SECONDS}" -lt 8 ]`, and `tests/scripts/pre_push.bats` contains no `SECONDS` assertion in any `dirty-tree: interrupt` case.
- **R2.** The existing comment in `_signal_case` beginning "Slow the cleanup's worktree removal" is rewritten in place, with no second comment added: it no longer says "not raced"; it names `_assert_temp_gone` as the check that catches a hook exiting before its cleanup finishes; it says that check relies on the shim's 1 s delay and that a miss is a silent pass, never a failure of a correct hook; and it says there is no wall-clock bound because it detected only a slow-but-correct interrupted exit.
- **R3.** The `make` mock's `sleep 10` after `kill -"${MAKE_MOCK_SIGNAL}" 0` is unchanged.
- **R4.** The Backlog row of `docs/superpowers/README.md` beginning "`dirty-tree: interrupt (TERM)` fails its 8 s wall-clock bound" is removed.
- **V1.** With the bound removed, replacing `trap 'exit 143' TERM` in `scripts/pre-push` with a no-op makes `dirty-tree: interrupt (TERM)` fail at `_assert_temp_gone`; reverted afterwards.
- **V2.** CI on the PR is green, and both `dirty-tree: interrupt` cases report `ok` in the macOS shard that runs `tests/scripts/pre_push.bats`.
- **N1.** No change to `scripts/pre-push`.
- **N2.** No `@test` block in `tests/scripts/pre_push.bats` is added or removed, and no helper other than `_signal_case` changes.

## Multi-Lens Review

Reviewed at commit: `6d12ca85` (Step 7 self-review commit, before Step 8 dispatch)

### Goal-Fit

Finding: Worth building; deletion is the simplest path. But the premise "the bound catches
nothing" is false: mutation M4 (`sleep 9;` prepended to the hook's EXIT-trap cleanup) passes
with the bound removed (both cases `ok`, 23 s) and fails at the `SECONDS` line with it kept.
The bound is the only check that an interrupted push returns promptly; no requirement asks
for that (2026-10-25 R4 requires only that cleanup finish before the hook exits). It never
caught an infinite hang, since it is read only after `run` returns. Reword the Problem
section and R2 to "detects only a slow-but-correct interrupted exit, which no requirement
forbids". A hook replaced by `exit 0` fails the remaining assertions, so they are not vacuous.
Assumption: the macOS overrun was runner load stretching a normal ~3 s case, not the hook
waiting out the mock's `sleep 10`; the attempt-1 log and artifact are gone. Settle by timing
the case on macOS under load.
Disposition: Addressed (operator "Delete, reworded", 2026-11-11) — Problem section and R2 now say the bound detects only a slow-but-correct interrupted exit; M4 added to the table. Assumption: Studio timing below found 2-3 s idle and under load, no run near 10 s.

### Ergonomics

Finding: No blocking issue; premise reproduced (M2 3/3 at `_assert_temp_gone`; `exit 0`
hook fails at the status line; `exit 143` hook fails at `tree_lock`). Notes: (1) the M2 guard
is a 1 s race between the `git` shim's sleep and bats' assertion latency, so a loaded runner
can miss a no-wait hook (a silent pass, never a red on a correct hook); the comment should
say it is timing-based. (2) R2 partly duplicates the existing "Slow the cleanup's worktree
removal ..." comment; merge them. V2 proves only that nothing broke, since attempt 2 of the
failing SHA already passed. Hang exposure is unchanged: the mock's `sleep 10` bounds only a
surviving `make`; any other hang runs to the job's `timeout-minutes: 30`.
Assumption: as Goal-Fit (load, not a macOS-only wait on the mock's `sleep 10`).
Disposition: Addressed (operator "Delete, reworded", 2026-11-11) — R2 now extends the existing shim comment instead of adding a second, and states the 1 s timing dependence; the M2 race is recorded in Measurements as unchanged by this spec.

### Risk

Finding: Premise false, as Goal-Fit: a bounded retry loop added to the EXIT trap
(`for _i in 1..6; do [[ -e "${_tree}.lock" ]] && break; sleep 1; done`) fails both cases at
line 1651 with the bound and passes both with it removed (17.5 s). Practical weight low: a
Ctrl-C or TaskStop waits extra seconds, nothing is lost. The "Rejected: widen" reasoning
rests on the same false premise, since a 30 s bound would still catch a cleanup looping for
tens of seconds. Untouched pre-existing gap: no test sends a pid-only TERM.
Assumption: `_assert_temp_gone` reliably catches M2 on a loaded macOS runner; its detection
is a 1 s race. Settle by running bound-removed plus M2 about 20 times under load.
Disposition: Addressed (operator "Delete, reworded", 2026-11-11) — premise and the Rejected widen reasoning reworded; widening rejected by the operator. Assumption accepted: the M2 race fails safe and predates this spec.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.

### Orchestrator measurement after the lenses

On the Studio (macOS, 20 cores), archive of `6d12ca85` with the bound replaced by a line
logging `SECONDS`, TERM case only: idle, 10 runs, elapsed 2 s x5 and 3 s x5, 0 failures;
under 40 busy `yes` processes (load average about 58), 10 runs, elapsed 2 s x2 and 3 s x8,
0 failures. No run approached the mock's 10 s. Population: one fast Mac, CPU load only; the
CI runner is a 3-vCPU VM with I/O contention, so this supports but does not prove the load
explanation.

### Round 2 (Risk only, changed sections)

Reviewed at commit: `f72663b2`.

Finding: R2 said "extend" the comment that reads "is caught, not raced", while the
Measurements section now says `_assert_temp_gone` is itself a 1 s race; an implementer could
meet R2 and ship "not raced" beside it, and "relies on the 1 s delay" could read as a
guarantee. Proposed fix (applied above, pending disposition): R2 rewrites the comment in
place, drops "not raced", and states a miss is a silent pass. Confirmed true: line numbers,
the 1 s figure (first remove plus `rm -rf`), the 2026-10-25 R4 wording, M4's 23 s; no R
contradicts an N; no new design decision.
Assumption: on a loaded macOS runner bats reaches `_assert_temp_gone` within 1 s of the
hook returning, so M2 is still caught. Measured after the review on the Studio, archive of
`f72663b2` with the bound removed and M2 applied, TERM case: 10 runs idle and 10 under 40
busy `yes` processes (load average about 58), 0 passes in 20, so M2 was caught every time.
Population: one fast Mac, CPU load only.
Disposition: Addressed (operator "Yes", 2026-11-11) — R2 rewrites the comment in place, drops "not raced", states a miss is a silent pass. No further round: wording only.
