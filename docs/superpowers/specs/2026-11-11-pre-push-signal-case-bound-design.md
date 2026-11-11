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
