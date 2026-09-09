# Unwired units: delete two, wire one

Date: 2026-09-09
Status: Design

## Problem

Three units under `lib/` have zero production callers. Their 32 tests and 52 coverable
lines sit inside figures CI gates on — test count >= 840, bash coverage >= 91% — so both
numbers currently describe code nothing runs. Measured 2026-09-08 by locating each
symbol's call sites rather than by grepping for its name:

| unit                                   | production callers | tests | note                                                                                                             |
| -------------------------------------- | ------------------ | ----- | ---------------------------------------------------------------------------------------------------------------- |
| `lib/package_capture.sh` (5 functions) | 0                  | 24    | not sourced anywhere in production; `capture_all_packages` passes `"[]"` as previous state for brew, apt and pip |
| `brew_install_cask`                    | 0                  | 4     | sibling `brew_install_formula` has 37 production uses; casks install via `brew bundle` against the Brewfile      |
| `ledger_flush_spool`                   | 0                  | 4     | is state-ledger's missing `ledger flush` consumer, written and never called                                      |

The 24 is split across **two** files — `tests/test_package_capture.bats` (11) and
`tests/setup_env/package_capture.bats` (13). This design said 11 until self-review, having
found the first file and stopped. That is the find-first-rather-than-enumerate error
`tdd.md` records against its own coverage table, reproduced in the session that cited it.

The caller count was re-measured across the **whole tracked repo**, not
`lib/ scripts/ setup_env.sh` — the narrower path list was the claim's own boundary rather
than the hazard's:

```
$ for fn in brew_install_cask ledger_flush_spool capture_all_packages capture_package_diff; do
    git grep -n "\b${fn}\b" -- . \
      | grep -vE '^(lib/(helpers|workflows|package_capture)\.sh|tests/|docs/)' | wc -l
  done
0 0 0 0
```

Two of the three are dead. The third is unwired, and
`docs/adr/0014-state-ledger-cmdb-integration.md` asserts the spool mechanism "handles
offline scenarios (no network)" — an ADR describing a behaviour nothing invokes.

This is the trust-signal problem `USER.md` names: a coverage percentage and a test count
carry less confidence than their mechanism implies, because part of what they measure is
unreachable.

### What `package_capture.sh` has actually produced

Nothing, from production. The live ledger's `packages/` tree holds exactly two records:

```
packages/1f119568-…/2026/08/run-direct.json     run_id "run-direct", a hand invocation
packages/test-machine/2026/08/run-x.json        run_id "run-x", the test fixture
```

Both are `tdd.md` E2 residue, and the spool separately carries `run_id=run-x` quarantined.
Neither came from a workflow. Even wired up the file could not emit a diff: the hardcoded
`"[]"` previous state means every package reports as added on every run.

## Decisions

One PR covering all three units. The deletions and the wiring touch disjoint files
(`lib/helpers.sh` and `lib/package_capture.sh` versus `lib/workflows.sh` and
`lib/update_summary.sh`), and the coverage argument for splitting them did not survive
measurement — see Measurements below.

### Delete

- `lib/package_capture.sh`, whole file.
- `tests/test_package_capture.bats`, whole file (11 tests).
- `tests/setup_env/package_capture.bats`, whole file (13 tests).
- `brew_install_cask` from `lib/helpers.sh`.
- Its 4 tests in `tests/setup_env/install_guards.bats`.

28 tests removed in total, taking the suite 1659 -> 1631 before the wiring's own tests are
added. The floor is 840.

1659 is this tree measured locally on 2026-09-09, not `CLAUDE.md`'s 1656 — that is CI's
figure for #255 and the tree has since taken four commits. The gate reads CI's number, so
CI's post-change count is what lands in `CLAUDE.md`; the local figure is what the
arithmetic above is done against.

#### Collateral: two live tests reference the deleted file and are not in either dedicated file

The removals are **not** pure. Self-review found two more sites, both executable:

- `tests/scripts/unit.bats:1653` names `lib/package_capture.sh` as one of five files in a
  tracer reconciliation loop. Drop that one element; the other four keep the test
  meaningful.
- `tests/setup_env/linux_shared.bats:129` **sources** `lib/package_capture.sh` and calls
  `_list_apt_packages`. Its own comment states it is "the only place in the suite that
  drives a real production caller of the two-separate-token legacy form through
  `tests/mocks/dpkg-query` itself."

That second one deletes cleanly rather than needing a new vehicle, and the reason is worth
recording because it is not obvious. Measured production `dpkg-query` callers:

```
lib/linux_shared.sh:5     -f '${db:Status-Abbrev}' -W <pkg>    separate tokens, status form
lib/update_summary.sh:127 -f='${Package} ${Version}\n'         attached token,  list form
lib/update_summary.sh:331 -f='${Package} ${Version}\n'         attached token,  list form
lib/package_capture.sh:31 -W -f '${Package}\t${Version}\n'     separate tokens, list form
```

The mock's explicit `-f`-argument consumption stays required by `linux_shared.sh`, so
deleting `package_capture.sh` does not orphan the parser. What it orphans is the
separate-token **and** list-form combination — precisely and only what that test drives.
A test whose input shape no longer occurs in production guards nothing, so it goes with
the file.

Both deletions are recoverable from git history. `package_capture.sh` would need
rewriting rather than reverting in any case, because the `"[]"` previous state is a design
fault and not a bug.

### Wire

`ledger_flush_spool` becomes a reported section of `run_update`. The function itself does
not change: its body already ends in `"${_ledger_bin}" flush`, so it propagates flush's
exit code today.

`cmd_flush` is already three-valued, so the outcome contract exists upstream and this
design does not invent one:

```
rc 0    "Spool: empty."                            nothing pending
rc 2    "WARNING: N spool entries still pending"   retryable entries remain, + ntfy alert
rc 2    "WARNING: ledger flush failed: <exc>"      error
```

Entries quarantined as permanently invalid are explicitly excluded from `remaining`, so
they cannot pin the count above zero indefinitely.

Two call-site changes:

1. `lib/workflows.sh` — record the section, map rc 2 to 0 for `_update_record_end`, then
   `_update_warn`. This is the idiom `CLAUDE.md` already documents for `git-repos`,
   `legacy-rsync` and `git-hooks`: a WARN section must not fail the run.
2. `lib/update_summary.sh` — add `"ledger-flush"` to `_UPDATE_SECTION_ORDER`. Without
   this the section is tracked internally and never printed, with no error.

Three outcomes reach the summary:

```
[OK]   ledger-flush                             rc 0
[WARN] ledger-flush  N entries still pending    rc 2
[SKIP] ledger-flush  no ledger binary           binary absent
```

### The skip case is probed at the call site, not signalled by a return code

`ledger_flush_spool` returns 0 both when the flush succeeded and when there is no ledger
binary. The call site resolves the binary first and records SKIP without invoking, rather
than widening the function's return contract to `{0,2,3}`.

Widening was considered and rejected on `shell.md`'s contract-widening entry, which
records this hazard in this repo (PR #194): `||` fires on any non-zero and cannot
distinguish "failed" from "succeeded with a caveat", so a new return value silently breaks
every `cmd || handler` caller. The enumeration would have to cover the 4 direct tests plus
every `run_update` test that reaches the function transitively — the failure mode
`shell.md` records from `update_aws_cli`, where a corrected grep still missed 15 tests
because they call `run_update` and never name the function.

The accepted cost is that binary resolution then exists in two places. That cost is
pinned by a test rather than a comment — see Verification, test 5.

### The ntfy push is scrubbed with a subshell

`cmd_flush` calls `_ntfy_spool_alert(remaining)` on rc 2, POSTing to `$NTFY_URL`.
Measured: `NTFY_URL` is unset in `run_update`'s environment — `config/local.sh` carries it
but only `setup_claude_mcp` sources it, and nothing in `.zshrc.d` exports it. The push is
therefore latent, not live, and one `source config/local.sh` in the update path away from
firing on every update with a pending spool, on top of the WARN line the operator is
already reading.

It is foreclosed at the call site so the summary stays the only channel:

```bash
( unset NTFY_URL; ledger_flush_spool )
```

**Not `env -u NTFY_URL ledger_flush_spool`.** `env` execs a file and
`ledger_flush_spool` is a shell function, so that form exits **127** without running it —
and 127 reaches `_update_record_end` as a FAIL, which would report `[FAIL] ledger-flush`
on every update forever, on machines where flushing works fine. Measured:

```
env -u NTFY_URL myfn    env: myfn: No such file or directory   rc=127
( unset NTFY_URL; myfn ) ran, NTFY_URL=[<unset>]               rc=2
NTFY_URL='' myfn         ran, NTFY_URL=[<unset>]               rc=2
```

This is `shell.md`'s "`env` cannot run a shell builtin" entry reached through a function
rather than a builtin. The `install_ledger_drift_agent` precedent that motivated the
scrub uses `env -u` correctly, because there it wraps a script **path**.

The prefix form works too but relies on `_ntfy_spool_alert`'s `if not ntfy_url` treating
an empty string as absent. The subshell genuinely unsets, so it does not depend on the
consumer's falsy check.

### Ordering: flush drains the previous run, never its own

`_ledger_write_dotfiles_entry` is the last statement of `_update_summary`, after the
summary is printed and logged. A reported section must run before the summary is
rendered, so `ledger-flush` necessarily precedes this run's own ledger write. An offline
run spools its entry and the _next_ run drains it.

Steady state is correct and lagged by one run. This is recorded so that a future reader
does not read the lag as a defect, or "fix" it by moving the call after
`_ledger_write_dotfiles_entry`, where it can no longer be reported at all.

### ADR-0014

Amended to name the consumer — `run_update`'s `ledger-flush` section drains the spool on
the next run — rather than asserting the mechanism abstractly. Naming the consumer is
what makes the claim checkable.

## Verification

### Deletions

The acceptance check is a reference count, run after the removal:

```bash
git grep -n 'package_capture\|brew_install_cask\|capture_all_packages\|capture_package_diff' \
  -- lib/ scripts/ setup_env.sh tests/          # expect: 0
```

Run it over `tests/` as well as production, not production alone: the two collateral sites
above live in `tests/` and in neither dedicated test file, and a production-only sweep
reports clean while `linux_shared.bats` still sources a file that no longer exists.

A green `make test` is not evidence here. The tests being deleted are the only things
that referenced the code being deleted, so the suite goes green whether or not something
else still needs it. The reference count is the instrument; the suite is a backstop.

### Wiring

Five tests. The fifth is the one that guards the accepted duplication.

1. rc 0 renders `[OK] ledger-flush`.
2. rc 2 renders `[WARN] ledger-flush` carrying the pending count, **and `run_update`'s
   own exit code is unchanged** — the rc-2-to-0 mapping is what stops a pending spool
   failing the whole update.
3. Binary absent renders `[SKIP] ledger-flush — no ledger binary`.
4. `"ledger-flush"` is present in `_UPDATE_SECTION_ORDER`.
5. **Binary resolvable only at `~/.local/bin/ledger` and not on `PATH` runs the section
   rather than skipping it.** This is the exact input where a call-site probe written as a
   bare `command -v ledger` diverges from `ledger_flush_spool`'s own two-step resolution.
   Without it the duplication drifts silently and the section reports SKIP on a machine
   with a working ledger.

### Harness constraints

`shell.md`: `ledger_flush_spool` falls back to an absolute `${HOME}/.local/bin/ledger`, so
a `PATH` strip cannot make it absent. Test 3 redirects `HOME` to a fixture.
`tests/setup_env/ledger_integration.bats` already has a case doing this for the fallback,
so the pattern exists in-repo.

`tdd.md` E2: every failing path must be inert. A wiring test whose mock is not reached
invokes the real `ledger`, which commits into the live state-ledger repo — the residue
this design already documents two records of. `HOME` is redirected at `setup()` scope,
not per-test, so the trap is not left armed for the next test someone adds to the file.

## Measurements

Local baseline, measured 2026-09-08 on this tree:

```
TOTAL                  3607   3931   91%      20 heuristic disagreements
package_capture.sh       46     53   86%
helpers.sh              551    565   97%
```

Test count 1659 locally on 2026-09-09 (`CLAUDE.md` carries 1656, CI's figure at #255,
four commits behind this tree). Floor 840.

**A splitting argument was made and then refuted by this measurement, and the refutation
is recorded because it is the more useful half.** The original recommendation was two PRs,
on the ground that the deletions and the wiring would move coverage in opposite directions
within one CI run and neither delta would be attributable. Removing an 86% file from a
91.76% total gives `3561/3878` = 91.83%, a rise of **0.07pp**, invisible at reported
precision. There is nothing for the wiring's delta to net against, so the ground for
splitting did not exist. One PR.

The post-change figure is a prediction. The plan records the measured local figure and
CI's is what lands in `CLAUDE.md`, per that file's own rule that the gate reads CI's
number and a local reading is a preview.

## Out of scope

Each item names where it went, so an omission reads as a decision:

- The two `packages/` residue records and the spool's 2 quarantined entries — state-ledger's
  existing test-residue backlog row, which already proposes quarantine over deletion for
  the same append-only reason.
- `ledger history`'s `TypeError` on duplicate timestamps, and entity ids rendered as UUIDs
  in `status`/`drift` — filed as two state-ledger backlog rows on 2026-09-08.
- The `ledger drift` threshold noise — already specced and descoped in state-ledger after
  three review rounds.
- `CLAUDE.md:447`'s "now reads 45% of 53 real bash lines", measured 86% — flagged, and
  left alone as a historical record of a heuristic fix rather than live drift.
- The two `terraform_ansible` docstrings citing `dotfiles' package_capture.sh` as a
  `LEDGER_BIN` exemplar — a backlog row in that repo, per the rule that a deferred
  finding goes to the repo the finding is about. This spec makes those citations dangle;
  it is not this spec's place to edit another repo's prose.

## Assumptions

- `cmd_flush`'s `{0, 2}` contract is stable. If state-ledger changes flush's exit codes,
  the rc-2-to-0 mapping and the WARN rendering both need revisiting. Refuted by:
  `sed -n '/^def cmd_flush/,/^def /p' scripts/ledger.py` in state-ledger showing a return
  value other than 0 or 2.
  The second assumption this design started with — that nothing outside dotfiles consumes
  `lib/package_capture.sh` — was checkable, so it was checked rather than shipped as an
  assumption. Measured 2026-09-09 across `~/git-repos/personal/`:

```
ai-config/scripts/run-bash-coverage.sh:230          comment
math/scripts/run-bash-coverage.sh:236, :356         comment
terraform_ansible/ansible/scripts/state_ledger.py:60        docstring
terraform_ansible/ansible/scripts/test_ledger_callback.py:83 docstring
```

**No executable consumer outside dotfiles.** But the two `terraform_ansible` docstrings
cite this file by name as one of three writers honouring the `LEDGER_BIN` seam — "
`ledger_smoke_check.sh` and dotfiles' `package_capture.sh` already honour `LEDGER_BIN`;
this makes the third writer agree" — written after 33 sub-second localhost runs reached
the live ledger corpus through exactly that gap.

So the deletion is safe to execute and leaves a dangling cross-repo citation: a
convention exemplar disappears from a repo that deliberately aligned to it, and nothing
in this change would tell them. That belongs in `terraform_ansible`'s backlog, not this
spec — recorded under Out of scope.

The two `run-bash-coverage.sh` comments are copies of this repo's tracer citing the file
as an example of the heredoc heuristic problem. They date themselves rather than break,
and are left alone.
