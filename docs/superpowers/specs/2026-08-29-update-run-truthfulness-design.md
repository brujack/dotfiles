# `-t update` run truthfulness — design

Date: 2026-08-29
Backlog rows: 13, and the `run_update` rc lead from 42. Row 62 was retired as stale during
this spec's premise check (`6a1a738`); row 53 was corrected in the same commit.

**Scope was narrowed after Multi-Lens Review.** The first draft (`f37612b`) also proposed a
durable run directory and wired up `package_capture`. Both were split out — see Deferred
below and the review section at the bottom for why.

## Problem

`setup_env.sh -t update` runs on every machine in the fleet and cannot report that it
failed. `run_update` (`lib/workflows.sh:326-687`) ends on `_update_summary`, whose own last
statement is `_ledger_write_dotfiles_entry || true`, so the function always returns 0.
`setup_env.sh:89` wraps it in `_run_or_exit`, a fail-fast runner that therefore can never
fire for this workflow. No cron job, git hook, wrapper script, or operator `&&` can branch
on the outcome of an update run.

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

**This does not make a healthy run start exiting 1, and that was checked rather than
assumed.** `~/.dotfiles-update.log` on the Studio holds **3938 runs and 50 `[FAIL]` lines**;
eleven of the last twelve runs report `0 failed`. All-time FAIL counts by section: `claude`
21, `brew` 16, `ai-config` 6, `pip` 2, and one each for `tpm`, `terraform-skill`,
`softwareupdate`, `oh-my-zsh`, `npm`. A blanket `_fail > 0` therefore fires rarely and for
real reasons; no per-section opt-in list is needed. Population: the Studio's log only — the
other six machines keep their own, and a machine that routinely fails a section would want
this re-checked before it starts trusting the exit code.

**`_run_or_exit`'s comment is updated in the same change.** `setup_env.sh:75` reads
"Fail-fast strict runner: exit immediately on the first failed selected step." After this
change `run_update` is the one caller where a non-zero return means "ran all sections, some
failed" rather than "stopped early". A wrapper or cron author reading the current comment
would infer the run aborted. The comment gains that distinction; the code does not change.

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

**WARN stays zero.** A run whose only non-OK sections are WARN must exit 0. This is the
discriminating case: if it exits 1, the `git-hooks` rc-2 mapping has been reversed and
machines carrying a repo subset now fail every update.

**Section rc is real — mutation, both directions.** Make `curl` fail in a fixture and confirm
the `aws` section records FAIL and the process exits 1. Before the change this records OK,
which is what makes it a mutation test rather than a restatement. Then revert the fixture and
confirm it returns to OK, so a permanently-failing section is not mistaken for a working
gate.

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

- **A durable run directory** retaining `err_*` past the run. Genuinely useful, and the
  cheap form is one line — delete `rm -rf` from the trap at `lib/workflows.sh:108` and keep
  `mktemp -d`, which preserves interrupted runs and needs no isolation work because tests
  still write to throwaway directories. The expensive form (a durable root under `$HOME`) is
  what forces everything below, and it is only _required_ by package capture.
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
