# Remove the wall-clock bound from the pre-push signal cases

Backlog row: "`dirty-tree: interrupt (TERM)` fails its 8 s wall-clock bound on the macOS
runner". Recurred 2026-11-10 on dotfiles#460 (run 42945438847, attempt 1, `test-macos-shard
(3)`, `not ok 310`, the hook's status correct at `143`); attempt 2 of the same SHA passed.

## Problem

`_signal_case` in `tests/scripts/pre_push.bats` (used by `dirty-tree: interrupt (TERM)` and
`dirty-tree: interrupt (INT)`) sets `SECONDS=0` before running the hook and then asserts
`[ "${SECONDS}" -lt 8 ]`. On a loaded macOS runner the case can exceed 8 s while every
behavioural assertion holds, so the bound fails a correct hook.

The row framed the question as "find a bound that still catches a hook that exits without
waiting for its cleanup subshell". That premise is false: measured below, the bound catches
nothing, and a hook that does not wait is caught by `_assert_temp_gone`.

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

The hang protection the 2026-10-25 dirty-tree spec asked for ("a bounded mock", Risk (2))
is the mock's own `sleep 10` after `kill`, not this assertion. It stays.

## Design

Delete `SECONDS=0` and `[ "${SECONDS}" -lt 8 ]` from `_signal_case`. Above the remaining
assertions add a comment stating that a hook which exits before its cleanup finishes is
caught by `_assert_temp_gone` (the `git` shim slows `worktree remove` by 1 s) and a suite
that survives INT by the status assertion, and that the wall-clock bound was removed because
it caught neither. Remove the backlog row.

No change to `scripts/pre-push`, to the `make` mock, or to any other case.

## Rejected

- **Widen the bound (for example to 30 s).** Keeps an assertion that discriminates nothing,
  so its only remaining effect is a rarer timing failure.
- **A marker file written by the mock if it survives the signal.** Tests the harness's own
  signal delivery, not a hook requirement.

## Verification

Before committing: delete the bound, run both signal cases (pass); apply M2 and re-run the
TERM case (fails at `_assert_temp_gone`); revert. `make test` exits 0.

## Requirements

- **R1.** `_signal_case` in `tests/scripts/pre_push.bats` contains neither `SECONDS=0` nor `[ "${SECONDS}" -lt 8 ]`, and `tests/scripts/pre_push.bats` contains no `SECONDS` assertion in any `dirty-tree: interrupt` case.
- **R2.** `_signal_case` carries a comment naming `_assert_temp_gone` as the check that catches a hook exiting before its cleanup finishes, and stating the wall-clock bound was removed because it caught neither that nor a suite surviving INT.
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
Disposition:

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
Disposition:

### Risk

Finding: Premise false, as Goal-Fit: a bounded retry loop added to the EXIT trap
(`for _i in 1..6; do [[ -e "${_tree}.lock" ]] && break; sleep 1; done`) fails both cases at
line 1651 with the bound and passes both with it removed (17.5 s). Practical weight low: a
Ctrl-C or TaskStop waits extra seconds, nothing is lost. The "Rejected: widen" reasoning
rests on the same false premise, since a 30 s bound would still catch a cleanup looping for
tens of seconds. Untouched pre-existing gap: no test sends a pid-only TERM.
Assumption: `_assert_temp_gone` reliably catches M2 on a loaded macOS runner; its detection
is a 1 s race. Settle by running bound-removed plus M2 about 20 times under load.
Disposition:

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.

### Orchestrator measurement after the lenses

On the Studio (macOS, 20 cores), archive of `6d12ca85` with the bound replaced by a line
logging `SECONDS`, TERM case only: idle, 10 runs, elapsed 2 s x5 and 3 s x5, 0 failures;
under 40 busy `yes` processes (load average about 58), 10 runs, elapsed 2 s x2 and 3 s x8,
0 failures. No run approached the mock's 10 s. Population: one fast Mac, CPU load only; the
CI runner is a 3-vCPU VM with I/O contention, so this supports but does not prove the load
explanation.
