# Unwired units: delete four

Date: 2026-09-09
Status: Design

## Problem

Four units under `lib/` have zero production callers once the set is closed. Their 37 tests
and 74 coverable lines sit inside figures CI gates on — test count >= 840, bash coverage

> = 91% — so both numbers partly describe code nothing runs.

| unit                                   | production callers    | tests | why it is dead                                                                                                                                                                              |
| -------------------------------------- | --------------------- | ----- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/package_capture.sh` (5 functions) | 0                     | 24    | not sourced anywhere in production; `capture_all_packages` passes `"[]"` as previous state for brew, apt and pip, so even wired it reports every package as added and can never emit a diff |
| `brew_install_cask`                    | 0                     | 4     | sibling `brew_install_formula` has 37 production uses; casks install via `brew bundle` against the Brewfile                                                                                 |
| `brew_cask_installed`                  | 0 _after_ this change | 4     | its only two references are its own definition (`lib/helpers.sh:187`) and the call at `:214` inside `brew_install_cask`; deleting that caller orphans it                                    |
| `ledger_flush_spool`                   | 0                     | 4     | redundant, not missing — `ledger write` already drains the spool, see below                                                                                                                 |

Plus one collateral test in `tests/setup_env/linux_shared.bats`, giving 37 removed in total.

The 24 is split across **two** files, `tests/test_package_capture.bats` (11) and
`tests/setup_env/package_capture.bats` (13).

`brew_cask_installed` is included deliberately rather than left for a later sweep. Deleting
only its caller relocates the dead-code boundary instead of closing it, and the next unwired
sweep re-raises the same file. `brew_formula_installed` is in the same structural position
and **stays**: its caller `brew_install_formula` has 37 production uses, so it is reachable
transitively. `CLAUDE.md:176` advertises `brew_cask_installed` in the Homebrew Helpers list
and that line goes with it.

Caller counts were measured across the whole tracked repo rather than
`lib/ scripts/ setup_env.sh`, since the narrower path list was the claim's boundary rather
than the hazard's. This block read `1 1 1 1` with the annotation "each hit is that
function's own definition" until round 2. That was false for two of the four, and an
implementer re-running it to check the premise would have got a different answer than the
document:

```
$ for fn in brew_install_cask ledger_flush_spool capture_all_packages capture_package_diff; do
    git grep -n "\b${fn}\b" -- . | grep -vE '^(tests/|docs/)' | wc -l
  done
1 1 2 4        # every hit is INTRA-FILE: a definition, or a call from one deleted
               # function to another inside lib/package_capture.sh
```

This is the trust-signal problem `USER.md` names: a coverage percentage and a test count
carry less confidence than their mechanism implies, because part of what they measure is
unreachable.

### `package_capture.sh` has never fired from production

The live ledger's `packages/` tree holds exactly two records:

```
packages/1f119568-…/2026/08/run-direct.json     run_id "run-direct", a hand invocation
packages/test-machine/2026/08/run-x.json        run_id "run-x", the test fixture
```

Both are `tdd.md` E2 residue. Neither came from a workflow.

### `ledger_flush_spool` is redundant, and the ADR that motivated it is wrong

This unit entered scope as "state-ledger's missing `ledger flush` consumer", and this
design's first version proposed wiring it into `run_update` as a reported section. That was
refuted in round 1. `cmd_write` already drains the spool —
`state-ledger/scripts/ledger.py:443`, above its own validation:

> flush runs first so a payload that fails `_validate_entry` below still doesn't skip **the
> only automatic drain that exists on this fleet** (nothing invokes `ledger flush`).

`run_update` already performs a `ledger write`: `_ledger_write_dotfiles_entry` ->
`ledger_write_entry` -> `ledger write` -> `cmd_write` -> `_flush_spool_internal`. So the
spool drains on every update today, and a wrapper around `ledger flush` adds nothing a
`ledger write` has not already done. Live state on the Studio: 0 active spool entries, 2
quarantined (quarantined entries are excluded from `remaining` by design).

`docs/adr/0014-state-ledger-cmdb-integration.md` is wrong on this in two places:

- `:33-34` — "The existing `ledger_flush_spool()` handles this for offline scenarios, but
  requires a separate daemon or cron trigger." No trigger is required; `cmd_write` drains.
- `:84` — "Spool mechanism (`ledger_flush_spool`) handles offline scenarios (no network)."
  The spool mechanism does handle them. `ledger_flush_spool` is not what makes it work.

## Decisions

### Delete

- `lib/package_capture.sh`, whole file.
- `tests/test_package_capture.bats`, whole file (11 tests).
- `tests/setup_env/package_capture.bats`, whole file (13 tests).
- `brew_install_cask` and `brew_cask_installed` from `lib/helpers.sh`.
- Their 8 tests in `tests/setup_env/install_guards.bats`.
- `ledger_flush_spool` from `lib/workflows.sh` (10 lines).
- Its 4 tests in `tests/setup_env/ledger_integration.bats`.
- `CLAUDE.md:176`, the `brew_cask_installed <cask>` line in Homebrew Helpers.

`ledger_write_entry` stays — it is the live write path with production callers. So does
`brew_formula_installed`, reachable via `brew_install_formula`'s 37 callers.

All deletions are recoverable from git history. `package_capture.sh` would need rewriting
rather than reverting in any case, because the `"[]"` previous state is a design fault and
not a bug.

### Collateral: two live tests reference `package_capture.sh`

The removals are not pure. Two executable sites live in neither dedicated test file:

- `tests/setup_env/linux_shared.bats:130` **sources** `lib/package_capture.sh` and calls
  `_list_apt_packages`. Delete the whole block — the `@test` at `:128`, the
  `# shellcheck disable=SC1091` at `:129`, and the six-line section banner at `:120-126`
  that describes it. Left behind, the banner documents a test that no longer exists and
  points at a file that no longer exists.
- `tests/scripts/unit.bats:1653` names `lib/package_capture.sh` as one of five files in a
  tracer reconciliation loop. **Substitute, do not shrink to four.** That file is the only
  member of the loop carrying `python3 -c` (4 occurrences; the other four have zero), and
  multi-line `python3 -c` bodies are the exclusion class with the largest historical
  denominator error in this repo — 54 of 107 lines, per `CLAUDE.md:447`. Dropping it leaves
  the two-mode reconciliation with no coverage of that construct. `lib/update_summary.sh`
  and `lib/workflows.sh` each carry one; use `lib/update_summary.sh`.

Deleting the `linux_shared.bats` block orphans no mock arm. Measured production
`dpkg-query` callers:

```
lib/linux_shared.sh:5     -f '${db:Status-Abbrev}' -W <pkg>    separate tokens, status form
lib/update_summary.sh:127 -f='${Package} ${Version}\n'         attached token,  list form
lib/update_summary.sh:331 -f='${Package} ${Version}\n'         attached token,  list form
lib/package_capture.sh:31 -W -f '${Package}\t${Version}\n'     separate tokens, list form
```

The mock's explicit `-f`-argument consumption stays required by `linux_shared.sh`, and it
keeps a live **test** driver as well as a production one: `linux_shared.bats:145-146` sets
`MOCK_DPKG_STATUS_zsh` / `_zsh_doc`, driving the separate-token status form through the
shared mock, and sits below the deleted block. What the deletion orphans is the
separate-token **and** list-form combination — precisely and only what the deleted test
drives. A test whose input shape no longer occurs in production guards nothing.

### ADR-0014: amend, and put the pointer where readers pass

Five references to `ledger_flush_spool` survive in that ADR and two of its claims are wrong
(above). An ADR is a historical decision record, so the original reasoning is not rewritten.

An amendment appended at the bottom of a ~110-line ADR is not enough on its own: a reader
meets the wrong claims at `:33-34` and `:84` roughly seventy lines before the correction,
with three further live references asserting the function exists. So the amendment is
accompanied by a pointer in the **Status** line at the top, which every reader passes:

```
**Status:** Accepted — amended 2026-09-09 (ledger_flush_spool deleted; cmd_write is the drain)
```

Mirror the same note in `docs/adr/README.md`'s status column, which would otherwise read a
bare `Accepted`.

### CLAUDE.md edits this change owes

Round 2 found the collateral under-enumerated — Out of scope named only `:447`. Four more
sites are live rather than historical:

| line       | what it is                                                                            | after deletion                                         |
| ---------- | ------------------------------------------------------------------------------------- | ------------------------------------------------------ |
| `:15`      | layout tree, states _"all 14 tracked"_, lists `package_capture`                       | count and membership both wrong                        |
| `:176`     | Homebrew Helpers advertises `brew_cask_installed`                                     | advertises a deleted function                          |
| `:461-462` | copy-pasteable worked examples naming `lib/package_capture.sh`                        | `--count-coverable` fails; substitute `lib/helpers.sh` |
| `:766`     | "`workflows.sh:898`, `:917` and `package_capture.sh:11` all carry that same fallback" | a three-site proof becomes two                         |

`:461-462` is the sharp one: it is the documented way to inspect one file's denominator
without waiting on the suite, and the deleted file is the exemplar in both commands.
Substituting a surviving instrumented file keeps them runnable at no cost.

`LaunchAgents/cadence.plist.template:36` carries the same three-witness citation as `:766`.
It degrades to two rather than breaking; recorded as a decision, not edited, because the
plist is a rendered template and its comment is prose about the agent `PATH`.

The test-count and coverage bullets at `:352` and `:406-410` take the new figures per that
section's own convention — an appended bullet, not an edit.

## Verification

### The acceptance check is a symbol grep, and it must be run before the deletion as well as after

```bash
# executable references only. NO \b — see below.
git grep -nE '^[^#]*(brew_install_cask|brew_cask_installed|ledger_flush_spool|capture_all_packages|capture_package_diff)' \
  -- lib/ scripts/ setup_env.sh tests/
# before deleting: expect 52   (positive control — proves the instrument fires)
# after  deleting: expect 0

git grep -nE '^[^#]*(source|\.)[^#]*package_capture\.sh' \
  -- lib/ scripts/ setup_env.sh tests/
# before: 4      after: 0
```

**Both runs are required.** An absence assertion's success output is also a broken
instrument's output, and this design has already shipped one of each:

- Round 1's check was `git grep … -- lib/ scripts/ setup_env.sh tests/ # expect: 0`. It
  returns **8** after a perfect deletion — the surviving comment references below — so it
  told the implementer the work was incomplete when it was done.
- Round 2's replacement added `\b` inside `-E`. **`git grep -E` does not implement `\b`**;
  git bundles its own engine and `\b` is not POSIX ERE. That check returned **0 on the
  unmodified tree with all 52 references present** — it could not fail. Measured control:
  `git grep -nE '^[^#]*\bbrew_install_formula\b' -- lib/` returns 0 where the same pattern
  without `\b` returns 38, and BRE `git grep -n '\bbrew_install_formula\b'` returns 38.

The second is strictly worse than the first: a loud wrong answer gets investigated, a silent
right one does not. This is `ai-config-git-grep-ere-ignores-word-boundary`, cited in
`behavior.md`, walked into while writing the fix for the previous round's finding on the
same check. The `^[^#]*` anchor does the comment exclusion the `\b` never did — `[^#]*`
cannot cross a `#`.

Verified end to end in a throwaway worktree with the deletions applied: 52 -> 0, and 4 -> 0
for the source check.

A green `make test` is not the instrument. The tests being deleted are the only things that
referenced most of the code being deleted, so the suite goes green either way. The suite is
a backstop; the symbol grep with its positive control is the check.

### Ten comment references survive, deliberately

```
scripts/run-bash-coverage.sh:50, :206, :326      heredoc-heuristic commentary
tests/mocks/dpkg-query:6, :17                    caller-shape commentary
tests/scripts/unit.bats:700, :721                tracer commentary
tests/setup_env/launch_agents.bats:262           ledger-path commentary
tests/setup_env/linux_shared.bats:121, :123      section banner — goes WITH the deleted block
```

Round 1 counted 8 and round 2 corrected it to 10. The last two are not survivors at all
once the banner is deleted with its test, which is why the collateral section above says to
take `:120-126`.

### Figures — measured, not predicted

Both readings local, same machine, 2026-09-08 and 2026-09-09, the second in a worktree with
every deletion above applied:

```
                    BEFORE                AFTER
TOTAL          3607/3931  91.76%    3542/3857  91.83%
helpers.sh      551/565   97%        540/552   97%
workflows.sh    516/555   92%        508/547   92%
tests               1659                 1622
disagreements         20                   18
instrumented          38                   37
```

Rounds 1 and 2 both named the same breaking assumption: that the deleted tests might be the
sole executors of lines in **retained** code, dropping the numerator without the
denominator. They are not, and the discriminator is the ratio of the two drops — orphaned
coverage would show covered falling by _more_ than coverable. `helpers.sh` fell by 11
covered against 13 coverable; `workflows.sh` by 8 against 8. No orphaned coverage in either.

CI is safe by delta rather than by hope. Baseline local 91.76% against CI's last-known
91.38% (#255) is a ~0.38pp gap, and a pure deletion introduces no platform-conditional
branches — the mechanism behind all three documented counter-examples to the
local-reads-one-point-higher prior. CI should land near 91.45%, above the truncation
boundary. CI's own figure is what lands in `CLAUDE.md`.

Test count 1659 -> 1622, a removal of **37**. An earlier revision said 36 and then 32; both
omitted the `linux_shared.bats` collateral test, which counts toward the total like any
other.

## Out of scope

Each item names where it went, so an omission reads as a decision:

- Surfacing spool depth in the update summary. `cmd_write` discards
  `_flush_spool_internal`'s return value, so the operator never learns a pending count.
  Backlog row, with the measurement attached.
- The two `packages/` residue records and the spool's 2 quarantined entries —
  state-ledger's existing test-residue backlog row.
- `ledger history`'s `TypeError` on duplicate timestamps, and entity ids rendered as UUIDs
  in `status`/`drift` — two state-ledger backlog rows filed 2026-09-08.
- The `ledger drift` threshold noise — already specced and descoped in state-ledger.
- `CLAUDE.md:447`'s "now reads 45% of 53 real bash lines", measured 86% — a historical
  record of a heuristic fix, left alone. Distinct from `:15`, `:176`, `:461-462` and `:766`
  above, which are live and are edited.
- `LaunchAgents/cadence.plist.template:36` — degrades from a three-site citation to two,
  recorded rather than edited.
- Whether the advertised `brew_*` helpers are used at all. `brew_formula_installed` has one
  production reference, inside `brew_install_formula`. That is reachable and correct, but
  the Homebrew Helpers list is worth an audit of its own. Backlog row.
- The two `terraform_ansible` docstrings citing `dotfiles' package_capture.sh` as a
  `LEDGER_BIN` exemplar (`state_ledger.py:60`, `test_ledger_callback.py:83`) — a backlog row
  in that repo. No executable consumer outside dotfiles was found.

## Multi-Lens Review

### Round 1 — reviewed at `b3d1efb46bdc7585e9ba30c519f955a67afd7f1e`

That commit proposed deleting two units and wiring `ledger_flush_spool`. Findings are
recorded as written, against the text they were written against.

**Goal-Fit** — Finding: the wire half solved a problem that does not exist; `cmd_write`
already drains the spool and `run_update` already performs a `ledger write`. Also: the ntfy
scrub suppressed a hazard the same change introduced; the acceptance check could not return 0. Assumption: that a spool entry can be stuck — retryable, non-quarantined, still present
after the next write. Disposition: **Addressed.** Verified independently at `ledger.py:443`.
The wiring is gone and `ledger_flush_spool` is deleted rather than wired.

**Ergonomics** — Finding: `NTFY_URL` is live in `run_update`'s environment, not latent;
`setup_env.sh:69` sources `config/local.sh` unconditionally thirty lines above the dispatch
at `:99`. Also: 6 of 6 cases expected PASS and none pinned a derived value. Assumption: that
`ledger` is installed beyond the two development machines. Disposition: **Addressed by
removal.** Verified independently. The original "latent" measurement was taken in the
harness shell rather than `setup_env.sh`'s process — the actor-boundary error `behavior.md`
documents, committed in a spec that cites it. Kept here because the actor error is the
transferable part.

**Risk** — Finding: same `NTFY_URL` inversion, reached independently; same acceptance-check
defect, counted at ~10 rather than 8; the wiring tests named no file, and
`update_summary.bats` does not redirect `HOME`; `_git_commit_and_push` failures are neither
`ValueError` nor `_PermanentSpoolError`, so a rebase conflict would pin `remaining` above
zero indefinitely. Assumption: that quarantined entries are excluded from `remaining` —
could not settle it. Disposition: **Addressed by removal**, assumption settled in the
design's favour (`_flush_spool_internal`'s docstring). **The ~10-versus-8 count was NOT
addressed** — that disposition addressed the wiring and silently dropped the count, which
round 2 re-raised. Corrected above.

### Round 2 — reviewed at `16d17b2c96f979e1fd495609bfa91e2ae1a35a44`

All three lenses were told the round 1 section was history, not settled findings.

**Goal-Fit** — Finding: the acceptance check returns 0 on the unmodified tree; `git grep -E`
does not honour `\b`. Round 1's finding was a check that could not return 0; the fix
produced one that cannot return anything else. Also: Out of scope violates its own rule by
omitting four `CLAUDE.md` sites and the plist. Also: the `1 1 1 1` annotation is false.
Assumption: that the deleted tests cover no line outside the deleted units. Disposition:
**Addressed.** All verified independently; check corrected and given a positive control; the
`CLAUDE.md` sites are now enumerated and edited; the annotation is corrected to `1 1 2 4`.
The assumption was **measured** rather than argued — see Figures.

**Risk** — Finding: same inert check, reached independently, with the corrected form
measured at 52. Also: `brew_cask_installed` is orphaned by the deletion and becomes the next
zero-caller function. Also: the `unit.bats` edit loses the loop's only `python3 -c`
representative. Also: `CLAUDE.md` staleness under-enumerated. Assumption: that CI's
truncated coverage still reads >= 91. Disposition: **Addressed.** `brew_cask_installed` is
now deleted as a fourth unit rather than left to a later sweep; the loop gets a substitution
rather than a shrink; the assumption is measured.

**Ergonomics** — Finding: same inert check, reached independently. Also: the survivor list
says 8 and is 10, and that was a round 1 finding marked resolved and not resolved. Also: the
spec claims `CLAUDE.md` carries 1656 when it carries **1659** (#257, run 34148440502), so
the paragraph explaining the difference explains one that does not exist. Also:
`linux_shared.bats:129` is the shellcheck directive; the `source` is `:130`. Also: the ADR
amendment sits ~70 lines below the wrong claims it corrects. Assumption: that a surviving
test drives the mock's separate-token `-f` consumption. Disposition: **Addressed.** All
verified. The stale 1656 paragraph is deleted; the citation is corrected; the ADR gets a
Status-line pointer and a `docs/adr/README.md` mirror. The assumption is settled in the
design's favour — `linux_shared.bats:145-146` drives that form and survives the deletion.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison, evaluator, or ambiguous-criteria trigger.
