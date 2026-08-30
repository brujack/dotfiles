# ADR-0027: The update run's exit code

**Date:** 2026-08-29
**Status:** Accepted

## Context

`setup_env.sh -t update` runs `run_update`, which ends on `_update_summary`
(`lib/update_summary.sh`). Every path that reached the summary returned 0 regardless of how
many sections had recorded FAIL — the function's last statement was
`_ledger_write_dotfiles_entry || true`. `setup_env.sh:89` wraps the call in `_run_or_exit`, a
fail-fast runner that exits non-zero on whatever the wrapped function returns, so it never
fired for a section failure: there was nothing non-zero to catch.

The record itself was not the problem. `_update_summary` already appends the rendered
summary and per-section detail blocks to `~/.dotfiles-update.log`, and
`_ledger_write_dotfiles_entry` already writes a state-ledger entry carrying an accurate
`failure_stage`, derived from the same `_fail` count the summary computes. Both writes were
correct before this change. The gap was narrower than the whole observability chain: nothing
converted that already-accurate internal count into the one value a caller outside the
process can see — the exit code. No cron job, git hook, wrapper script, or operator `&&`
could tell that an update run had failed a section.

## Decision

`_update_summary` ends on `return $(( _fail > 0 ))` (`lib/update_summary.sh:599`).
`run_update` returns that value unchanged, `_run_or_exit` propagates it, and
`setup_env.sh -t update` now exits 1 when any section recorded FAIL.

The contract is plain 0 or 1, not a tri-state. This repo already paid for the alternative:
`install_git_hooks_all_repos` was widened to a `{0,1,2}` return, and a call site written as
`fn || handler` in `run_setup_user` started reporting a "failure" for the new, explicitly
not-a-failure value (dotfiles#194). The only production caller of `_update_summary`'s return
value is `_run_or_exit`, which treats any non-zero identically — a wider contract here would
buy nothing and reproduce that risk for no reason.

WARN does not fail the run. The `git-repos`, `legacy-rsync` and `git-hooks` sections
deliberately map partial success — a machine legitimately missing some of the expected
repos, or a `core.hooksPath` gap — to a zero return plus a `_update_warn` line;
`git-hooks` does so explicitly via `$(( _git_hooks_rc == 2 ? 0 : _git_hooks_rc ))`. Treating
WARN as failure would silently reverse a decision those sections already made on purpose.

## Consequences

**This makes a nontrivial fraction of runs on this machine exit 1, and that is an accepted
cost rather than a surprise to be corrected later.** Counting FAIL rows against all 3938
historical log entries gives 1.3%, which understates the current rate — that ratio is
dominated by thousands of April–May development runs. Counting failures per **run**, over
recent windows of `~/.dotfiles-update.log`, gives a different picture:

| window   | runs that failed |
| -------- | ---------------- |
| last 20  | 5                |
| last 50  | 16               |
| last 100 | 18               |
| last 200 | 18               |
| last 500 | 18               |
| all 3938 | 41               |

The identical counts at 100, 200 and 500 mean all 18 recent failures sit inside the last 100
runs — the failures are recent and concentrated, not evenly spread across the log's history.
`brew` accounts for 15 of the last 20 FAIL rows, spread across 2026-07-07 to 2026-08-19
rather than clustered in one debugging session, which makes it a standing condition of this
machine rather than churn. (For contrast, the 21 all-time `claude`-section failures that
inflate the 1.3% all-time figure fall on a single day, 2026-04-11 — a one-off, not a
pattern.) Taken together this means roughly a quarter to a third of runs will exit 1 the
moment this contract ships.

**There is deliberately no per-section opt-in list and no WARN demotion for `brew`.** An
exit code that suppresses the one section that is actually failing is a gate that cannot
fail — exactly the defect class this repo's standards spend the most words on. The noise is
treated as the finding: `brew` has been failing on roughly a third of runs for six weeks and
nothing surfaced it, which is the condition this exit code exists to end. The first `exit 1`
is the prompt to diagnose `brew`, not a false alarm to silence.

**This contract immediately surfaced a real defect rather than only a diagnostic gap.** Once
section return codes were made to actually propagate (a prerequisite change in the same
series), nine `run_update` tests went red against production code: `update_aws_cli`'s macOS
branch `cd`ed into `${HOME}/software_downloads/awscli` with no preceding `mkdir -p`, while
its Linux branch created the directory first. The asymmetry had been invisible for as long
as the function existed, because nothing propagated the failure it caused. It was fixed in
the same change.

**After this decision, `run_update` can return non-zero for three distinct situations, and
only one of them leaves any evidence.** `setup_env.sh`'s `_run_or_exit` comment now
enumerates them:

1. It ran every section and at least one recorded FAIL — a summary, a
   `~/.dotfiles-update.log` line, and a ledger entry are all written.
2. It could not create its run directory (`lib/workflows.sh:331`) and aborted before any
   section ran — nothing is recorded anywhere.
3. It aborted mid-run on one of five `cd` guards (`lib/workflows.sh:621`, `:631`, `:641`,
   `:661`, `:663`) — also nothing is recorded.

A wrapper or cron job that sees a non-zero exit and finds no corresponding log line is in
case 2 or 3, not case 1. Cases 2 and 3 are pre-existing behavior made externally visible by
this change, not behavior it introduces; making them record a FAIL section before returning
is a separate fix, tracked as its own backlog row rather than folded in here.

**The review trigger, and the fact that nothing enforces it.** If `brew` is still failing a
month after this ships, the correct response is to fix `brew`, not to loosen this contract
back toward a WARN demotion or an opt-in list. Nothing schedules that review — there is no
mechanism that will prompt anyone to look again in a month. This is named as an open gap
rather than implied to be covered, the same way ADR-0025 names the absence of a mechanical
guard for CI job timeouts as a bet rather than a closed question.

## Related

- Spec: [2026-08-29-update-run-truthfulness-design.md](../superpowers/specs/2026-08-29-update-run-truthfulness-design.md) — full measurements and the ordering rationale for shipping `err_*` retention ahead of this contract.
- [ADR-0017](0017-pre-push-trigger-fail-closed.md) — the same shape of decision: what a gate does when it cannot say "clean," and why the noisier failure mode is the one worth accepting.
- [ADR-0025](0025-no-mechanical-guard-for-ci-job-timeouts.md) — the pattern this ADR's review trigger follows: naming an unenforced gap explicitly rather than implying a mechanism exists.
- Backlog rows in `docs/superpowers/README.md`: `run_update`'s five `cd` guards return 1 having recorded nothing; a durable run root under `$HOME` for `err_*` retention; `package_capture` is dead code that would report every package as added.
