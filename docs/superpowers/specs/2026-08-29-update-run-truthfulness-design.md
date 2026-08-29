# `-t update` run truthfulness — design

Date: 2026-08-29
Backlog rows: 13, 53 (partial), 42 (the `run_update` rc lead). Row 62 is retired as stale — see Premise below.

## Problem

`setup_env.sh -t update` runs on every machine in the fleet and cannot report that it
failed. `run_update` (`lib/workflows.sh:326-687`) ends on `_update_summary`, whose own
last statement is `_ledger_write_dotfiles_entry || true`, so the function always returns 0. `setup_env.sh:89` wraps it in `_run_or_exit`, a fail-fast runner that therefore can
never fire for this workflow. No cron job, git hook, wrapper script, or operator shell
can branch on the outcome of an update run.

Two contributing defects sit underneath that:

- `update_aws_cli` (`lib/developer.sh:16-33`) and `update_rust` (`:37-55`) check the
  return code of `cd` and nothing else. `curl` fetching `AWSCLIV2.pkg`, `sudo -H
installer`, `rm`, `unzip`, the Linux `aws/install`, and all six `rustup` invocations
  are unchecked. The `aws` and `rust` sections can only ever record OK, so even a
  correct exit contract would report a clean run over a failed AWS CLI install.
- Raw per-section output (`err_*`) is written into a `mktemp -d` whose `EXIT INT TERM`
  trap removes it (`lib/workflows.sh:105-108`). The rendered summary and the trimmed
  `detail_*` tails reach `~/.dotfiles-update.log`, but the full output of a failing
  section is gone by the time anyone reads the log.

Separately, `lib/package_capture.sh` has zero production callers and passes a literal
`"[]"` as previous state at `:130`, `:136` and `:142`, so wiring it up as written would
report every installed package as newly added on every run, forever.

## Premise — what is already correct, measured before designing

Three claims carried in the backlog rows were false or stale when checked against the
tree at `003b310`. They are recorded here because the original scope was drawn from them.

| claim                                                                    | measured                                                                                                                                                                                                                                                                                                                                               |
| ------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| row 53: "the update summary discards every recorded result"              | False. `lib/update_summary.sh:588` appends the rendered summary and detail blocks to `${UPDATE_LOG_PATH:-${HOME}/.dotfiles-update.log}`, and `:601` calls `_ledger_write_dotfiles_entry`, which writes a state-ledger entry carrying `failure_stage`, `workflows_ran[]` and `packages_updated_count`. Both writes happen before the tmpdir is removed. |
| row 53: the ledger entry misreports failures                             | False. `_ledger_write_dotfiles_entry` (`:530-532`) passes `${_fail:-0}` — the count computed by `_update_summary` — as the entry's exit code, and `_ledger_write_run_entry` (`:407-408`) sets `success: false` and derives `failure_stage` from the first FAIL section in `_UPDATE_SECTION_ORDER`. The ledger is honest about failure.                 |
| row 62: "`pip check`'s verdict is discarded and `SKIP_UPGRADE` is inert" | Stale in both halves. `lib/workflows.sh:557-562` runs `pip check` and records `pip-check` as OK or FAIL, and `pip-check` is a member of `_UPDATE_SECTION_ORDER` (`update_summary.sh:6`). `grep -rn 'SKIP_UPGRADE' --include='*.sh' --include='*.bats' .` returns no output — the variable does not exist anywhere in the repo.                         |

The durable record therefore exists, in two places, and it is accurate. What is missing
is a **process exit code** derived from it, honest section return codes feeding it, and
retention of the raw output behind it.

**Population note.** Every measurement above was taken on the Mac Studio against the
working tree at commit `003b310`, by reading the named line ranges rather than by
grepping for tool names. The `SKIP_UPGRADE` grep covered tracked and untracked `*.sh`
and `*.bats` files under the repo root; it did not cover `.zsh` files or the
`powershell/` subtree, neither of which participates in `run_update`. The claims above
are scoped to `run_update` and its callees, not to the repo as a whole.

## Design

### 1. The run directory replaces the temporary directory

`_dotfiles_run_tmpdir_setup` (`lib/workflows.sh:105-118`) currently creates a
`mktemp -d` and registers a trap that removes it. It instead creates a named directory
under a durable root:

```bash
_DOTFILES_RUN_TMPDIR="${_DOTFILES_RUNS_DIR:-${HOME}/.local/share/dotfiles/runs}/${_run_id}"
mkdir -p -m 700 "${_DOTFILES_RUN_TMPDIR}"
trap 'unset _DOTFILES_RUN_TMPDIR' EXIT INT TERM
```

Replacing the directory rather than copying out of it at the end is deliberate: a run
killed part way through keeps its output, and that is exactly the run whose output is
worth having. A copy step placed in `_update_summary` would lose output on precisely
those runs, because `_update_summary` is what never gets reached.

Two ordering consequences follow and both are load-bearing:

- `run_id` is generated at `:112`, after the directory exists today. It must move above
  the `mkdir`, since it now names the directory.
- Its current fallback chain ends in `|| true`, which on a machine without `python3`
  leaves an **empty** `run_id`. That would resolve the path to the runs root itself. The
  fallback becomes `date -u +%Y%m%dT%H%M%SZ-$$`, so a missing interpreter degrades to a
  valid unique name rather than a broken path.

Mode `700` because `err_*` files carry repository paths, hostnames, and the output of
`git`, `brew` and `apt` invocations.

Retention: keep the newest 10 run directories, pruning older ones at setup time. This
matches the venv-snapshot retention already implemented in the pip arm
(`lib/workflows.sh:530-533`), including its `find | sort -r | tail -n +11` shape.

Pruning at setup time cannot remove the baseline section 4 depends on: keeping the
newest 10 always retains the immediately-preceding run, which is the one the baseline
lookup reads. The two mechanisms only interact if the retention count is ever lowered to
zero, and the no-baseline path in section 4 handles that case correctly rather than
depending on it never happening.

`_DOTFILES_RUNS_DIR` exists as a test seam. It is not merely convenient: after this
change the default path resolves under the operator's real `$HOME`, so a test that fails
to override it writes into live state. See section 5.

### 2. Exit contract

`_update_summary` already computes `_fail` as the count of sections whose status file
reads `FAIL`. Its final line becomes:

```bash
_ledger_write_dotfiles_entry || true
return $(( _fail > 0 ))
```

`run_update` ends on that call, so its return value propagates unchanged, `_run_or_exit`
fires, and `setup_env.sh -t update` exits 1 when any section failed.

The contract is plain 0 or 1, not a tri-state. `install_git_hooks_all_repos` in this repo
already demonstrates the cost of widening a return contract to `{0,1,2}` — every caller
written as `fn || handler` starts reporting a failure for the not-a-failure case, and one
such call site was missed in dotfiles#194. The only production caller here is
`_run_or_exit`, which treats any non-zero identically, so a wider contract would buy
nothing and carry that risk.

`WARN` does not fail the run. The `git-repos`, `legacy-rsync` and `git-hooks` sections
deliberately map partial success to a zero return plus a `_update_warn` line — `git-hooks`
does so explicitly with `$(( _git_hooks_rc == 2 ? 0 : _git_hooks_rc ))`. Treating WARN as
failure would silently reverse that decision on machines that legitimately carry a subset
of the expected repos.

`pip-check` FAIL does fail the run. The comment at `lib/workflows.sh:546-549` records
that this verdict was ratcheted from warning to failure in the same change that made the
sync apply the lock, on the grounds that a conflict after that point is a real defect.
This design honours that rather than re-litigating it.

### 3. Return-code propagation in `lib/developer.sh`

Every command in `update_aws_cli` and `update_rust` gets `|| return 1`, per `shell.md`'s
return-code propagation rule. Specifically: the two `curl` invocations, `sudo -H
installer`, `rm`, `unzip`, `sudo -H .../aws/install`, and the six `rustup` calls across
both resolution branches.

The macOS branch removes the downloaded `AWSCLIV2.pkg` before returning on an installer
failure, so a subsequent run cannot install a half-downloaded file. This is the one place
where a cleanup step must run regardless of the failure, per `tdd.md`'s exception for
cleanup.

`_rustup_found` (`lib/developer.sh:40`) is assigned in three branches and never read
anywhere in the repo. It is deleted rather than annotated: a variable nothing reads is
dead code, and suppressing the finding would make it permanent.

### 4. `package_capture` baseline and wiring

`capture_all_packages` writes `pkg_<ecosystem>.json` into the current run directory on
every run. That file is never mutated — it is the record of what was installed at that
run, and the current state is derived by reading the newest one, which matches the
append-then-derive design the state ledger itself uses.

Previous state is the newest `runs/*/pkg_<ecosystem>.json` older than the current run.
When none exists — a first run, or one whose predecessor has been pruned —
`capture_all_packages` records the baseline and **skips** `capture_package_diff`
entirely, reporting `baseline recorded, no diff`. The literal `"[]"` arguments at `:130`,
`:136` and `:142` are removed.

This is the substantive fix. The `"[]"` literal is a symptom; the defect is that the
absence of a baseline was rendered as "every package was added", which is a well-formed
and completely wrong answer.

The production call site is a new `packages` section in `run_update`, placed after all
update sections and before `_update_check_brewfile_drift`. Adding it requires adding
`packages` to `_UPDATE_SECTION_ORDER` (`lib/update_summary.sh:5-8`) in the same change —
a section recorded but absent from that array is tracked internally and never printed,
with no error, which this repo's `CLAUDE.md` records as a live coupling trap.

The section reports **three** states, not two. `ledger` exits 0 when it cannot commit,
printing `WARNING: ... spooling:` to stdout, so a caller branching on `$?` records
success over a degraded ledger. This is the failure `behavior.md` documents from
`migration-classifier`, where an `ok|failed` field collapsed a third state that mattered
more than either. The `packages` section therefore reads ledger's output and records
`ok`, `spooled`, or `failed`. None of the three is a FAIL status: package capture is
advisory and must not fail an otherwise-successful update.

### 5. Test isolation

There are 372 references to `_DOTFILES_RUN_TMPDIR` across five bats files
(`brewfile_drift.bats` 69, `ledger_integration.bats` 21, `update_summary.bats` 196,
`unit.bats` 4, `workflows.bats` 82). Today the default is a `mktemp -d`, so a test that
does not override it writes to a throwaway directory and no harm follows.

After this change the default resolves under the operator's real `$HOME`. A test whose
failing path calls `_dotfiles_run_tmpdir_setup` without an override would write into live
state — the destructive-failing-path hazard `tdd.md` names as pitfall E2, and the same
shape as the `test-machine` spool residue this repo has already paid for once.

Mitigation is at `setup()` scope, never per test, so the trap is not left armed for the
next test someone adds to the file:

```bash
setup() {
  export HOME="${BATS_TEST_TMPDIR}"
  export _DOTFILES_RUNS_DIR="${BATS_TEST_TMPDIR}/runs"
  ...
}
```

Both are set, not one. `_DOTFILES_RUNS_DIR` is the direct seam; the `HOME` redirect means
that a test which somehow bypasses the seam still fails at an earlier guard having
touched nothing outside the fixture.

Every call site of `_dotfiles_run_tmpdir_setup` in the suite is audited before the
production change lands, not after. The audit is a precondition of the change, because
after the change an un-audited call site is a live write to the operator's home
directory.

### 5b. `_update_summary`'s own test callers

Section 2 changes `_update_summary` from always-zero to `0`/`1`, and the suite calls it
directly. `tests/setup_env/update_summary.bats` has **14** call sites: 11 via `run
_update_summary` and 3 bare. Both forms break, differently:

- A `run` site followed by `[ "$status" -eq 0 ]` goes red for any test that stages a FAIL
  status file — `_update_summary prints FAIL section with exit code` (`:363`) and
  `_update_summary prints totals line` (`:391`) both do.
- A **bare** call site is worse. bats runs each test body under `set -e`, so a bare
  `_update_summary` returning 1 aborts the test at that line, before its assertions. The
  three bare sites (`:416`, `:427`, `:438`) stage only OK sections today and so are
  unaffected as written — but any future test that stages a FAIL and calls bare would
  abort with a message about the wrong line.

Both classes are migrated in the same commit as the contract change, and the FAIL-staging
tests assert `[ "$status" -eq 1 ]` rather than being loosened to ignore status. A test
that stops asserting the status of a function whose status is the point of the change is
worse than one that goes red.

This is the same widening-a-return-contract hazard the exit contract section cites for
production callers, arriving on the test side, where nothing enumerates the call sites for
you.

### 6. Ordering

The test-isolation seam and the `setup()` changes land **first**, in their own commit,
while the default is still `mktemp -d` and therefore harmless. Only then does
`_dotfiles_run_tmpdir_setup` switch to the durable root. This ordering means there is no
window in which an un-isolated test can write to live state.

## Verification

Each item states the command and the expected observable. Where the command can be run
against existing state it has been; where it depends on code not yet written, that is
said explicitly.

**Exit contract.** Not runnable until section 2 exists. After: drive a fixture run with
one FAIL section and assert the process exit.

```bash
t="$(mktemp -d)"
HOME="${t}" _DOTFILES_RUNS_DIR="${t}/runs" bats tests/setup_env/workflows.bats \
  -f 'run_update returns non-zero'
# expect rc=1 with a FAIL section present, rc=0 with only OK/WARN/SKIP
```

The WARN case is the discriminating one and must be asserted separately: a run whose only
non-OK sections are WARN must still exit 0, or the `git-hooks` rc-2 mapping has been
reversed.

**Run directory survives interruption.** Not runnable until section 1 exists.

```bash
t="$(mktemp -d)"
HOME="${t}" _DOTFILES_RUNS_DIR="${t}/runs" ./setup_env.sh -t update & sleep 2; kill -INT $!
ls "${t}"/runs/*/err_brew    # expect the file to exist
```

This is the case the copy-at-the-end alternative fails, so it is the case that justifies
the chosen approach and must be asserted rather than assumed.

**No-baseline emits no diff.** Two consecutive runs against an empty runs root: the first
writes `pkg_brew.json` and records `baseline recorded, no diff`; the second emits a diff
whose added-set is empty when no packages changed between them. A first run that emits a
non-empty added-set is the original defect reproduced.

**Blast radius.** Runnable now, and it is the control for section 5:

```bash
before=$(ls ~/.local/share/dotfiles/runs 2>/dev/null | wc -l)
make test
after=$(ls ~/.local/share/dotfiles/runs 2>/dev/null | wc -l)
[[ "${before}" == "${after}" ]]
```

Measured before implementation: the directory does not currently exist, so `before` is 0.
Any non-zero `after` means a test wrote to live state and the isolation seam has a hole.
Asserting on the count rather than on a test's own mock is deliberate — a test asserting
on its mock proves the mock was called, not that nothing else changed.

**Section rc is real.** Mutation check on `lib/developer.sh`: make `curl` fail in a
fixture and confirm the `aws` section records FAIL. Before the change this returns OK,
which is what makes it a mutation test rather than a restatement.

## Out of scope

- Backlog row 14 (18 `run run_update` sites assert no `$status`). Those tests become
  newly meaningful once `run_update` returns a real value, but auditing all 18 is its own
  change and would triple this diff.
- Backlog row 45 (`_ledger_write_run_entry` is 131 lines). Untouched here.
- Any change to what the ledger entry contains. The entry is accurate today; this design
  adds a caller-visible exit code and raw-output retention alongside it, not a
  replacement for it.
