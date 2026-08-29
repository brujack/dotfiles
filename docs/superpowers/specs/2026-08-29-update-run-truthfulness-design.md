# `-t update` run truthfulness — design

Date: 2026-08-29
Backlog rows: 13, and the `run_update` rc lead from 42. Row 62 was retired as stale during
this spec's premise check (`6a1a738`); row 53 was corrected in the same commit.

**Scope was narrowed after Multi-Lens Review.** The first draft (`f37612b`) also proposed a
durable run directory and wired up `package_capture`. Both were split out — see Deferred
below and the review section at the bottom for why.

## Problem

`setup_env.sh -t update` runs on every machine in the fleet and cannot report that a
section failed. `run_update` (`lib/workflows.sh:326-687`) ends on `_update_summary`, whose
own last statement is `_ledger_write_dotfiles_entry || true`, so every path that reaches the
summary returns 0 regardless of how many sections recorded FAIL. `setup_env.sh:89` wraps it
in `_run_or_exit`, a fail-fast runner that therefore never fires for a section failure. No
cron job, git hook, wrapper script, or operator `&&` can branch on the outcome of an update
run.

**"`run_update` always returns 0" is false, and the exception matters to this design.** Five
`cd … || return 1` statements sit inside `run_update` — `lib/workflows.sh:621`, `:631`,
`:641`, `:661`, `:663` — and each aborts the function before the summary. So `_run_or_exit`
*can* fire today, for exactly one cause: a directory that could not be entered. Those paths
are strictly worse than the failure this spec is fixing, because they return 1 having printed
**no summary**, appended **no log line**, and written **no ledger entry** — `_update_summary`
is what performs all three. Found by the second review round; the first draft asserted the
unqualified claim and built the `_run_or_exit` documentation change on it.

A second defect sits underneath that and would survive fixing it alone. `update_aws_cli`
(`lib/developer.sh:16-33`) and `update_rust` (`:37-55`) check the return code of `cd` and
nothing else. `curl` fetching `AWSCLIV2.pkg`, `sudo -H installer`, `rm`, `unzip`, the Linux
`aws/install`, and all six `rustup` invocations are unchecked. The `aws` and `rust` sections
can only ever record OK, so a correct exit contract would still report a clean run over a
failed AWS CLI install.

## Premise — measured before designing

Claims carried in the backlog rows, and one carried in this spec's own first draft, were
false. They are recorded because the original scope was drawn from them.

| claim                                                                                                              | measured                                                                                                                                                                                                                                                                                                                                                    |
| ------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| row 53: "the update summary discards every recorded result"                                                        | False. `lib/update_summary.sh:588` appends the rendered summary and detail blocks to `${UPDATE_LOG_PATH:-${HOME}/.dotfiles-update.log}`, and `:598` calls `_ledger_write_dotfiles_entry`, which writes a state-ledger entry carrying `failure_stage`, `workflows_ran[]` and `packages_updated_count`. Both writes happen before the tmpdir is removed.      |
| row 53: the ledger entry misreports failures                                                                       | False. `_ledger_write_dotfiles_entry` (`:530-532`) passes `${_fail:-0}` — the count computed by `_update_summary` — as the entry's exit code, and `_ledger_write_run_entry` (`:407-408`) sets `success: false` and derives `failure_stage` from the first FAIL section in `_UPDATE_SECTION_ORDER`. The ledger is honest about failure.                      |
| row 62: "`pip check`'s verdict is discarded and `SKIP_UPGRADE` is inert"                                           | Stale in both halves. `lib/workflows.sh:557-562` runs `pip check` and records `pip-check` as OK or FAIL, and `pip-check` is a member of `_UPDATE_SECTION_ORDER`. `grep -rn 'SKIP_UPGRADE' --include='*.sh' --include='*.bats' .` returns no output.                                                                                                         |
| **this spec's first draft**: "`ledger` exits 0 when it cannot commit, printing `WARNING: ... spooling:` to stdout" | **False.** `state-ledger/scripts/ledger.py:473-479` prints that warning to **stderr** and returns **2**, and this repo's `ledger_write_entry` (`lib/workflows.sh:906-909`) already branches on rc 2. The draft imported `ledger classify`'s semantics — documented in `behavior.md` — and applied them to `ledger write`. Right document, wrong subcommand. |

The durable record therefore exists, in two places, and it is accurate. What is missing is a
**process exit code** derived from it, and honest section return codes feeding it.

**Population note.** Every measurement above was taken on the Mac Studio against the working
tree at `003b310`/`f37612b`, by reading the named line ranges rather than grepping for tool
names. The `SKIP_UPGRADE` grep covered tracked and untracked `*.sh` and `*.bats` under the
repo root; it did not cover `.zsh` or the `powershell/` subtree, neither of which
participates in `run_update`.

All four retractions above were caught by reading the source rather than by reasoning about
the documentation, and the fourth is the sharpest form: `behavior.md`'s account of `ledger
classify` is accurate, current, and about a different subcommand than `ledger write`. An
accurate fact about an adjacent thing is what this premise check exists to catch, and no
amount of re-reading the documentation would have surfaced it.

## Design

### 1. Exit contract

`_update_summary` already computes `_fail` as the count of sections whose status file reads
`FAIL`. It is declared `local` at `lib/update_summary.sh:537`, so it is in scope at the end
of the same function body. The final lines become:

```bash
_ledger_write_dotfiles_entry || true
return $(( _fail > 0 ))
```

`run_update` ends on that call (`lib/workflows.sh:686`), so the value propagates unchanged,
`_run_or_exit` fires, and `setup_env.sh -t update` exits 1 when any section failed.

The contract is plain 0 or 1, not a tri-state. `install_git_hooks_all_repos` in this repo
already demonstrates the cost of widening a return contract to `{0,1,2}` — every caller
written as `fn || handler` starts reporting a failure for the not-a-failure case, and one
such call site was missed in dotfiles#194. The only production caller is `_run_or_exit`,
which treats any non-zero identically, so a wider contract would buy nothing and carry that
risk.

`WARN` does not fail the run. The `git-repos`, `legacy-rsync` and `git-hooks` sections
deliberately map partial success to a zero return plus a `_update_warn` line — `git-hooks`
does so explicitly with `$(( _git_hooks_rc == 2 ? 0 : _git_hooks_rc ))`. Treating WARN as
failure would silently reverse that on machines legitimately carrying a subset of the
expected repos.

`pip-check` FAIL does fail the run. The comment at `lib/workflows.sh:546-549` records that
this verdict was ratcheted from warning to failure in the same change that made the sync
apply the lock, on the grounds that a conflict after that point is a real defect.

**This does make a healthy-looking run exit 1 about a third of the time today, and that is
a deliberate acceptance rather than an oversight.** The first draft argued the contract would
fire rarely, citing 50 `[FAIL]` lines across 3938 runs in `~/.dotfiles-update.log` — 1.3%.
That is a correct count of the wrong population: the ratio is dominated by thousands of
April–May development runs, and the question is how often a run *now* would exit 1. Measured
per run rather than per FAIL line:

| window | runs that failed |
| --- | --- |
| last 20 | 5 |
| last 50 | 16 |
| last 100 | 18 |
| last 200 | 18 |
| last 500 | 18 |
| all 3938 | 41 |

Identical counts at 100, 200 and 500 mean all 18 recent failures sit inside the last 100
runs. `brew` accounts for 15 of the last 20 FAIL rows, spread across 2026-07-07 to
2026-08-19 rather than clustered in one debugging session — so it is a standing condition of
this machine, not churn. (By contrast the 21 all-time `claude` failures that inflate the
1.3% figure fall on a single day, 2026-04-11.)

**The operator's ruling is to ship anyway, on the grounds that the noise is the finding.**
`brew` has been failing on roughly a third of runs for six weeks and nothing surfaced it,
which is precisely the condition the exit code exists to end. The first `exit 1` is the
prompt to diagnose `brew`. No per-section opt-in list and no WARN demotion: an exit code that
suppresses the one section actually failing would be a gate that cannot fail, which is the
defect class this repo's standards spend the most words on.

The accepted risk, stated so it is not rediscovered as a surprise: an exit code firing on one
run in three is one an operator can learn to ignore before it acquires a consumer. If `brew`
is still failing a month after this ships, that is the signal to fix `brew` rather than to
loosen the contract.

**Why the cause is not in this spec.** Every recent `brew` FAIL row reads `exit 1` and
nothing more — the `result_` column carries no detail, and `err_brew` dies with the tmpdir.
The artifact that would answer "why does brew fail" is exactly the `err_*` retention deferred
below. That is an argument for doing the deferred work soon, not for widening this spec.

**`_run_or_exit`'s comment is updated in the same change, and must name both meanings.**
`setup_env.sh:75` reads "Fail-fast strict runner: exit immediately on the first failed
selected step." After this change `run_update` returns non-zero for two different situations:
it ran every section and some recorded FAIL, or it aborted early on one of the five `cd`
guards above. A wrapper or cron author needs to know that both exist and that only the first
leaves a summary, a log line, and a ledger entry. The first draft proposed a comment saying
non-zero means "ran all sections, some failed" — which would have been false for the paths
that record nothing, and misleading in the direction of trusting an absent record.

**The `cd`-abort paths are left as they are, and given a backlog row.** Making them record a
FAIL section before returning is the right fix and is a different change: it touches five call
sites inside `run_update`, and the summary they would need to write does not exist yet at
`:621`. Under this contract they are pre-existing behaviour made visible, not behaviour this
spec introduces.

### 2. Return-code propagation in `lib/developer.sh`

Every command in `update_aws_cli` and `update_rust` gets `|| return 1`, per `shell.md`'s
return-code propagation rule: the two `curl` invocations, `sudo -H installer`, `rm`,
`unzip`, `sudo -H .../aws/install`, and the six `rustup` calls across both resolution
branches.

The macOS branch removes the downloaded `AWSCLIV2.pkg` before returning on an installer
failure, so a subsequent run cannot install a half-downloaded file. This is the cleanup
exception `tdd.md` carves out — it runs regardless of the failure.

`_rustup_found` (`lib/developer.sh:40`) is assigned in three branches and never read
anywhere in the repo. It is deleted rather than annotated: a variable nothing reads is dead
code, and suppressing the finding would make it permanent.

This is the section that changes the most verdicts. Its rc reaches `_update_record_end "aws"`
→ `status_aws` → `_fail` → the summary, the ledger's `failure_stage`, and — with section 1 —
the process exit.

### 3. `_update_summary`'s test callers

Section 1 changes `_update_summary` from always-zero to `0`/`1`, and the suite calls it
directly. `tests/setup_env/update_summary.bats` has **14** call sites: 11 via `run
_update_summary` and 3 bare. Both forms break, differently:

- A `run` site followed by `[ "$status" -eq 0 ]` goes red for any test staging a FAIL status
  file — `_update_summary prints FAIL section with exit code` (`:363`) and `_update_summary
prints totals line` (`:391`) both do.
- A **bare** call site is worse. bats runs each test body under `set -e`, so a bare
  `_update_summary` returning 1 aborts the test at that line, before its assertions. The
  three bare sites (`:416`, `:427`, `:438`) stage only OK sections today and are unaffected
  as written — but any future test staging a FAIL and calling bare would abort with a
  message naming the wrong line.

Both classes migrate in the same commit as the contract change, and the FAIL-staging tests
assert `[ "$status" -eq 1 ]` rather than being loosened to ignore status. A test that stops
asserting the status of a function whose status is the point of the change is worse than one
that goes red.

There are **zero** production callers of `_update_summary` outside `run_update`, verified by
grep, so this is the whole of the migration.

## Ordering — the `err_*` one-liner ships first

**Scope change, made after the operator's ruling and flagged rather than folded in
silently.** The ruling is that the noise is the finding: the first `exit 1` is the prompt to
diagnose `brew`. That prompt arrives with nothing behind it. Every recent `brew` FAIL row
reads `exit 1`, `result_brew` carries no cause, and `err_brew` — the only artifact holding
the reason — is removed by the trap at `lib/workflows.sh:108` before anyone can read it. A
contract that starts firing on one run in three, pointing at a diagnostic that does not
exist, is worse than one that fires with the evidence attached.

So the **cheap** retention lands first, in its own commit, ahead of the exit contract:

```bash
# lib/workflows.sh:105-108
_DOTFILES_RUN_TMPDIR=$(mktemp -d -t dotfiles-run)   # was: mktemp -d
trap 'unset _DOTFILES_RUN_TMPDIR' EXIT INT TERM     # was: rm -rf ...; unset ...
```

Two properties make this one line's worth of risk rather than the durable-root project
deferred below:

- **No isolation work.** The directory is still `mktemp`, so every test writes to a throwaway
  path exactly as today. Verified: three tests call `_dotfiles_run_tmpdir_setup` directly —
  `tests/setup_env/install_guards.bats:783`, `tests/setup_env/ledger_integration.bats:294`
  and `:302` — and all three would simply leave a `/var/folders` directory behind, which the
  OS reaps. None of the 372 `_DOTFILES_RUN_TMPDIR` references changes.
- **The directories stay findable.** `mktemp -d -t dotfiles-run` yields
  `/var/folders/.../dotfiles-run.XXXXXXXX` (verified on macOS), so a later prune can select
  them by prefix. Without the prefix, retained directories are indistinguishable from every
  other tool's `tmp.XXXX`.

The cost is that macOS reaps `/var/folders` in roughly three days and Ubuntu's
`systemd-tmpfiles` defaults to ten, so this buys a diagnostic window rather than a record.
That is the right trade for the question it has to answer — *why did brew fail on the run
that just exited 1* — and it is not a substitute for the durable root, which stays deferred.

The EXIT trap itself stays. Dropping `rm -rf` does not remove the trap, so the
bats-trap-clobbering those three test comments describe is unchanged by this spec.

## Verification

The first draft's checks were counted during review: five checks, all expecting PASS, three
of which passed on nothing happening. That is the failure `behavior.md` names — a suite that
tests the comparison and never the measurement feeding it. The checks below each state what
would make them fail.

**Process exit, end to end.** The draft asserted `run_update`'s return value via bats. That
is the wrong artifact: `_run_or_exit` lives in `setup_env.sh`, not in `run_update`, and the
process exit is what the Problem section is about. The check drives the real entry point:

```bash
t="$(mktemp -d)"; HOME="${t}" ./setup_env.sh -t update --claude-only; echo "rc=$?"
```

Fails if rc is 0 on a run whose summary shows a non-zero failed count, and fails equally if
rc is 1 on a run showing `0 failed`. Both directions are asserted; one alone cannot tell a
working contract from an always-1 contract.

**WARN stays zero — and the fixture must actually produce a WARN.** A run whose only non-OK
sections are WARN must exit 0. Asserting the exit code alone is not enough: a fixture with
zero WARN sections exits 0 too, so the check would pass on nothing having happened. The test
asserts the summary contains at least one `[WARN]` row *and* that the process exited 0. If it
exits 1, the `git-hooks` rc-2 mapping has been reversed and machines carrying a repo subset
now fail every update.

**Section rc is real — mutation, both directions.** Make `curl` fail in a fixture and confirm
the `aws` section records FAIL and the process exits 1. Before the change this records OK,
which is what makes it a mutation test rather than a restatement. Then revert the fixture and
confirm it returns to OK, so a permanently-failing section is not mistaken for a working
gate.

**Every new FAIL-staging test uses `run`, never a bare call.** This is the trap section 3
identifies, and this section was about to walk into it: the mutation test above stages a FAIL
and calls the function, so written bare it aborts under bats' `set -e` at the call and reports
a line unrelated to the mutation. The repo has already paid for this class three times —
`tests/setup_env/workflows.bats:237`, `:1796` and `:1930` each carry a comment recording that
`_dotfiles_run_tmpdir_setup`'s EXIT trap clobbers bats' own, reproduced as
`Executed N-1 instead of expected N` with no test name and no line number. `run` isolates the
trap in its subshell. The rule is stated here rather than left to section 3 because
Verification is where the next FAIL-staging test gets written.

**Positive control on the FAIL path.** `[ "$status" -eq 1 ]` alone would pass against a
`_update_summary` that returned 1 unconditionally. The paired assertion is that the same
fixture with every section OK returns 0, in the same test file, so neither constant can
satisfy both.

**Suite is green and no test regressed count.** `make test` exits 0 and the CI test-count
floor (≥ 840; 1545 at `3530241`) is unchanged or higher. The 14 migrated call sites must all
still exist — a migration that deletes assertions rather than updating them would also make
the suite green.

## Deferred — split out during review, not dropped

Two sections of the first draft were removed. Both are real work and each gets a backlog row
in the same change as this spec, per `behavior.md`'s rule that a mentioned-but-unfixed
finding needs a destination.

- **A durable run root under `$HOME`**, named and pruned, with the six-caller and
  sortable-name problems below. Only _package capture_ requires that form. The one-line
  `err_*` retention that was in this bullet has been pulled back into scope — see Ordering
  above.
- **Wiring `package_capture`.** It cannot move any verdict by construction, and it is the
  only reason the run directory must be durable across runs and named by `run_id`. Its own
  defects are now known and belong in its own spec: the hardcoded `"[]"` previous state
  (`:130`, `:136`, `:142`); `| "${LEDGER_BIN}" write || true` at `:112` swallowing the rc 2
  that means _spooled_; and `capture_all_packages` returning 0 silently when `machine-id` is
  absent, which a `HOME`-redirected fixture guarantees — so any test of it passes on a
  capture of nothing unless it pins a non-zero derived value.

Three defects found in the first draft's own design are recorded here so the follow-on spec
does not re-derive them: `_dotfiles_run_tmpdir_setup` has **six** callers
(`lib/workflows.sh:119, 224, 260, 285, 292, 330`), not one; `setup_env.sh:86-87` calls two of
them in a single process, so `-t setup` would produce two run directories per invocation and
the `date -u +%Y%m%dT%H%M%SZ-$$` fallback collides with itself (same second, same PID); and
`run_id` is `uuid4`, so a `find | sort -r | tail -n +11` retention borrowed from the
timestamp-named venv snapshots prunes an arbitrary set rather than the oldest.

Also out of scope: backlog row 14 (18 `run run_update` sites assert no `$status`), which
becomes newly meaningful once `run_update` returns a real value; and row 45
(`_ledger_write_run_entry` is 131 lines).

## Multi-Lens Review

Reviewed at commit: `f37612b` (Step 7 self-review commit, before Step 8 dispatch). The spec
body has since been rewritten in response — the scope below is the first draft's, which
included a durable run directory (§1) and `package_capture` wiring (§4).

### Goal-Fit

Finding: §2 (exit contract) is the whole of the stated problem and is one line; §1, §4 and
the §5 isolation work are a larger, different project riding on it. Applied the reads-it test
per mechanism: §2 changes a decision (`_run_or_exit` branches) but has no new durable
consumer, since the ledger already carries `failure_stage`; §3 changes a decision *and* lands
in the ledger, making it the highest-value section; §4 changes no verdict by construction —
the spec itself states none of its three states is a FAIL — and is the only reason the run
directory must be durable across runs and named by `run_id`, which is what forces the
372-reference audit. Also: §5's audit was scoped from the symptom (`grep _DOTFILES_RUN_TMPDIR`)
rather than the entry point, missing five of six production callers; and the exit-contract
check asserted the function's rc via bats when `_run_or_exit` lives in `setup_env.sh`, so
nothing measured the process exit the Problem section is about. Verified `run_update` always
returns 0 empirically by staging a FAIL section and driving `_update_summary` (`rc = 0`), and
confirmed zero production callers of `capture_all_packages`.

Assumption: that no section in `_UPDATE_SECTION_ORDER` currently records FAIL on a healthy
machine — if any FAILs routinely and benignly, `-t update` exits 1 on every run and the exit
code is noise before it has a consumer. Settled by reading `~/.dotfiles-update.log`, which
already holds every past run's summary. **Checked: refuted.** 3938 runs, 50 `[FAIL]` lines,
eleven of the last twelve runs at `0 failed`. The blanket `_fail > 0` contract is safe; the
measurement is now in the Exit contract section with its population stated.

Disposition: **Addressed.** Operator chose to split. §1 and §4 are removed to Deferred with
their known defects recorded; §2 and §3 ship, and §3 is stated as the highest-value section
rather than a supporting one. The process-exit check now drives `setup_env.sh -t update`.

### Ergonomics

Finding: (a) `run_id` is `uuid4`, so the venv-snapshot retention shape borrowed in §1
(`find | sort -r | tail -n +11`) prunes an arbitrary set — demonstrated against 12 real
directories, where the deletion set included the newest. §1's claim that "keeping the newest
10 always retains the immediately-preceding run" was false, and §4's "newest `pkg_*.json`
older than the current run" had no ordering to read. The tell is the inversion: only the
degraded `python3`-absent fallback name sorts correctly. (b) §4's `packages` three-state does
not fit the renderer — `_update_summary`'s status `case` (`lib/update_summary.sh:553-573`) has
exactly four arms and no default, so a status of `ok`/`spooled`/`failed` prints no row,
increments no counter, and silently under-counts `_total`. (c) `setup_env.sh:75` documents
`_run_or_exit` as "exit immediately on the first failed selected step", which after this
change is misleading for `run_update` alone. (d) No discoverability for the run store: 10
UUIDs in arbitrary order, no `latest` symlink, nothing printed, while `_update_summary`
already prints `Log appended:`.

Assumption: that `capture_all_packages` produces a stable serialization across runs, so two
captures on an unchanged machine are byte-comparable rather than differing by ordering or
embedded timestamps. If unstable, §4 reports spurious adds every week — a different wrong
answer than today's, and one that trains the operator to ignore the section. Refuted or
confirmed by capturing twice back to back and diffing under `jq -S`.

Disposition: **Addressed.** (a) and (b) are moot under the split — both sections are
deferred — but both defects are recorded verbatim in Deferred so the follow-on spec does not
re-derive them, and the assumption is carried there as an open question to settle before that
spec is written. (c) is fixed in the Exit contract section, which now updates the comment in
the same change. (d) is deferred with §1.

### Risk

Finding: (a) `_dotfiles_run_tmpdir_setup` has six production callers
(`lib/workflows.sh:119, 224, 260, 285, 292, 330`), not the one the spec modelled, and
`setup_env.sh:86-87` invokes two in a single process — so `-t setup` would create two run
directories per invocation, and the `date -u +%Y%m%dT%H%M%SZ-$$` fallback collides with
itself (same second, same PID), the second workflow overwriting the first's directory. The
fallback was designed against cross-process collision; the actual collision is same-process.
(b) §4's premise about `ledger` is false: `ledger.py:473-479` prints its warning to **stderr**
and returns **2**, and this repo's `ledger_write_entry` (`lib/workflows.sh:906-909`) already
branches on rc 2 — so the proposed stdout string-matcher re-creates, brittly, a tri-state the
repo already handles structurally, and re-creates the exact collapse `behavior.md` is cited
for one layer down. (c) §6's ordering is necessary but not sufficient: while the default is
still `mktemp -d`, `_DOTFILES_RUNS_DIR` is read by nothing, so a misspelled export in five
`setup()` blocks is indistinguishable from a correct one, and the audit protects only files
that exist today. (d) Three of the five affected bats files do not export `HOME` today, so
adding it changes `ledger_write_entry`'s `${HOME}/.local/bin/ledger` resolution — a
behavioural change wearing an isolation change's clothes. (e) Retention caps a count, not a
size, over unbounded `tee` output. Confirmed correct as written: `_fail` is in lexical scope
for the proposed `return`, and the 372/5-file count is exact.

Assumption: that `ledger write` signals an un-committable write by exiting 0 with a stdout
warning — one of the spec and `ledger_write_entry` had to be stale. **Checked: the spec was
wrong.** `ledger.py:473-479` is `print(..., file=sys.stderr)` followed by `return 2`. The
draft imported `ledger classify`'s documented behaviour and applied it to `ledger write`;
`ledger_write_entry`'s rc-2 branch is live, not dead code.

Disposition: **Addressed.** (b) is corrected in the Premise table as a first-draft retraction,
and the mechanism it was wrong about is deferred with §4 — where the fix is to call
`ledger_write_entry` and branch on 0/2 rather than match a string. A related defect the lens
surfaced in existing code, `package_capture.sh:112`'s `| ledger write || true` swallowing
that same rc 2, is recorded in Deferred. (a), (c), (d) and (e) are moot under the split and
(a) is recorded in Deferred for the follow-on spec.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger. The design proposes a
return-value contract and a return-code sweep; its acceptance criteria are concrete commands
with stated failing conditions, and no component judges or ranks anything.

### Risk — round 2 (scoped)

Reviewed at commit: `b8193ab`. Scope: the narrowed body only. The revision cut four
mechanisms to two, so a single lens was dispatched rather than three, and it was told
explicitly that the round-1 section above is history rather than findings to confirm.

Finding: (a) The "fires rarely" argument was drawn over the wrong window. All-time
`[FAIL]`-lines-over-runs is 1.3%, but per-run over the recent population it is 25–32%, and
`brew` accounts for 15 of the last 20 FAIL rows spread over five weeks rather than clustered
— so the exit code fires on roughly one run in three from day one. Round 1's Goal-Fit lens
named this exact assumption and this spec recorded "Checked: refuted" against the safest of
the available windows. (b) `run_update` does not always reach `_update_summary`: five
`cd … || return 1` paths abort first, so the Problem section's unqualified claim was false,
and the `_run_or_exit` comment the round-1 disposition introduced would have been false for
precisely the paths that record nothing. (c) The rewritten Verification section still had one
check passing on nothing — "WARN stays zero" is satisfied identically by a fixture with no
WARN sections at all. Confirmed correct and not raised: `_fail` is in scope with no early
returns in `_update_summary`'s body; an unset `_DOTFILES_RUN_TMPDIR` leaves `_fail=0` and
fails safe rather than false-1; `_update_check_brewfile_drift`'s rc is discarded at a bare
call site; 14 test call sites and zero production callers both verified; `_rustup_found` is
genuinely write-only; `[FAIL]` appears only as table rows so the log's structure does support
the counting.

Assumption: that the recent `brew` failures are transient rather than a standing condition —
if one recurring cause, the exit code fires on a third of runs forever and is ignored before
it acquires a consumer. The lens proposed settling it by reading each FAIL row's trailing
text. **Checked: that method does not work.** All 15 recent `brew` rows read `exit 1` and
nothing more; the `result_` column carries no cause and `err_brew` is discarded with the
tmpdir. The log cannot answer it, which is itself an argument for the deferred `err_*`
retention. The remaining discriminator is running `-t update --brew-only` live, which mutates
state and is the operator's call rather than a reviewer's.

Disposition: **Accepted, reason: the operator ruled that the noise is the finding — brew has
been failing on a third of runs for six weeks with nothing surfacing it, and the first exit 1
is the prompt to diagnose it.** No per-section opt-in list and no WARN demotion, since an
exit code that suppresses the one section actually failing is a gate that cannot fail. The
measurement itself is **Addressed**: the wrong-window ratio is replaced by the per-window
table with the accepted risk stated. (b) is **Addressed** — the Problem section now states
the five `cd` paths and what they fail to record, the comment change names both meanings, and
the paths get a backlog row rather than a silent fix. (c) is **Addressed** — the WARN check
now asserts at least one `[WARN]` row alongside the exit code.
