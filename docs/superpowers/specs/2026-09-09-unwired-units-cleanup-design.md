# Unwired units: delete three

Date: 2026-09-09
Status: Design

## Problem

Three units under `lib/` have zero production callers. Their 32 tests and roughly 70
coverable lines sit inside figures CI gates on — test count >= 840, bash coverage >= 91% —
so both numbers partly describe code nothing runs.

| unit                                   | production callers | tests | why it is dead                                                                                                                                                                              |
| -------------------------------------- | ------------------ | ----- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/package_capture.sh` (5 functions) | 0                  | 24    | not sourced anywhere in production; `capture_all_packages` passes `"[]"` as previous state for brew, apt and pip, so even wired it reports every package as added and can never emit a diff |
| `brew_install_cask`                    | 0                  | 4     | sibling `brew_install_formula` has 37 production uses; casks install via `brew bundle` against the Brewfile                                                                                 |
| `ledger_flush_spool`                   | 0                  | 4     | redundant, not missing — `ledger write` already drains the spool, see below                                                                                                                 |

The 24 is split across **two** files, `tests/test_package_capture.bats` (11) and
`tests/setup_env/package_capture.bats` (13). Caller counts were measured across the whole
tracked repo rather than `lib/ scripts/ setup_env.sh`, since the narrower path list was the
claim's boundary rather than the hazard's:

```
$ for fn in brew_install_cask ledger_flush_spool capture_all_packages capture_package_diff; do
    git grep -n "\b${fn}\b" -- . | grep -vE '^(tests/|docs/)' | wc -l
  done
1 1 1 1        # each hit is that function's own definition
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

This unit entered scope as "state-ledger's missing `ledger flush` consumer, written and
never called", and this design's first version proposed wiring it into `run_update` as a
reported section. That was refuted in review. `cmd_write` already drains the spool —
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
- `brew_install_cask` from `lib/helpers.sh`.
- Its 4 tests in `tests/setup_env/install_guards.bats`.
- `ledger_flush_spool` from `lib/workflows.sh` (10 lines).
- Its 4 tests in `tests/setup_env/ledger_integration.bats`.

32 tests removed, taking the suite 1659 -> 1627 against a floor of 840. 1659 is this tree
measured locally on 2026-09-09, not `CLAUDE.md`'s 1656 — that is CI's figure for #255 and
the tree has since taken four commits. The gate reads CI's number, so CI's post-change
count is what lands in `CLAUDE.md`.

`ledger_write_entry` stays. It is the live write path and has production callers.

All three deletions are recoverable from git history. `package_capture.sh` would need
rewriting rather than reverting in any case, because the `"[]"` previous state is a design
fault and not a bug.

### Collateral: two live tests reference `package_capture.sh`

The removals are not pure. Two executable sites live in neither dedicated test file:

- `tests/scripts/unit.bats:1653` names `lib/package_capture.sh` as one of five files in a
  tracer reconciliation loop. Drop that one element; the other four keep the test
  meaningful.
- `tests/setup_env/linux_shared.bats:129` **sources** `lib/package_capture.sh` and calls
  `_list_apt_packages`. Its own comment states it is "the only place in the suite that
  drives a real production caller of the two-separate-token legacy form through
  `tests/mocks/dpkg-query` itself."

That second one deletes cleanly rather than needing a new vehicle. Measured production
`dpkg-query` callers:

```
lib/linux_shared.sh:5     -f '${db:Status-Abbrev}' -W <pkg>    separate tokens, status form
lib/update_summary.sh:127 -f='${Package} ${Version}\n'         attached token,  list form
lib/update_summary.sh:331 -f='${Package} ${Version}\n'         attached token,  list form
lib/package_capture.sh:31 -W -f '${Package}\t${Version}\n'     separate tokens, list form
```

The mock's explicit `-f`-argument consumption stays required by `linux_shared.sh`, so the
deletion does not orphan the parser. It orphans the separate-token **and** list-form
combination — precisely and only what that test drives. A test whose input shape no longer
occurs in production guards nothing, so it goes with the file.

### ADR-0014 gets a superseding note, not an edit

Five references to `ledger_flush_spool` survive in that ADR, and two of its claims are
wrong (above). An ADR is a historical decision record, so the original reasoning is not
rewritten. A dated amendment note is appended recording that the function was deleted as
redundant, that `cmd_write` is the drain, and that no daemon or cron trigger was ever
required. That keeps what was decided in 2026-06 readable while stopping the next reader
acting on it.

## Verification

### The acceptance check is a symbol grep, and it is not expected to return zero

A naive path-scoped grep cannot pass. Eight references survive every deletion above, all of
them comments, and this design's own Out of scope section rules that class is left alone:

```
scripts/run-bash-coverage.sh:50, :206, :326      heredoc-heuristic commentary
tests/mocks/dpkg-query:6, :17                    caller-shape commentary
tests/scripts/unit.bats:700, :721                tracer commentary
tests/setup_env/launch_agents.bats:262           ledger-path commentary
```

An earlier version of this design nominated `git grep … -- lib/ scripts/ setup_env.sh
tests/ # expect: 0` as the instrument. It would have returned 8, telling the implementer
the deletion was incomplete and inviting either an unauthorised eight-comment diff or a
silently weakened check. The instrument is instead:

```bash
# executable references only: a call, a source, or a definition
git grep -nE '^[^#]*\b(brew_install_cask|ledger_flush_spool|capture_all_packages|capture_package_diff)\b' \
  -- lib/ scripts/ setup_env.sh tests/                      # expect: 0
git grep -nE '^[^#]*(source|\.)[^#]*package_capture\.sh' \
  -- lib/ scripts/ setup_env.sh tests/                      # expect: 0
```

Run it over `tests/` as well as production, not production alone: both collateral sites
live in `tests/` and in neither dedicated test file, and a production-only sweep reports
clean while `linux_shared.bats` still sources a file that no longer exists.

A green `make test` is not the instrument. The tests being deleted are the only things that
referenced most of the code being deleted, so the suite goes green whether or not something
else still needs it. The suite is a backstop; the symbol grep is the check.

### Figures

Local baseline, measured 2026-09-08 on this tree:

```
TOTAL                  3607   3931   91%      20 heuristic disagreements
package_capture.sh       46     53   86%
helpers.sh              551    565   97%
```

Predicted after: `package_capture.sh` leaves 46 covered of 53 coverable; `brew_install_cask`
and `ledger_flush_spool` remove a further ~17 coverable, well covered, from `helpers.sh` and
`workflows.sh`. Removing an 86% file from a 91.76% total raises the figure slightly;
removing two well-covered functions lowers it slightly. The net is within rounding and the
gate's 91% floor is not at risk from either direction.

That is a prediction. The plan records the measured local figure and CI's is what lands in
`CLAUDE.md`, per that file's rule that the gate reads CI's number and a local reading is a
preview.

## Out of scope

Each item names where it went, so an omission reads as a decision:

- Surfacing spool depth in the update summary. `cmd_write` discards
  `_flush_spool_internal`'s return value, so the operator never learns a pending count —
  genuinely missing observability, and the one real idea the abandoned wiring contained.
  Backlog row, with the measurement attached.
- The two `packages/` residue records and the spool's 2 quarantined entries —
  state-ledger's existing test-residue backlog row, which already proposes quarantine over
  deletion for the same append-only reason.
- `ledger history`'s `TypeError` on duplicate timestamps, and entity ids rendered as UUIDs
  in `status`/`drift` — filed as two state-ledger backlog rows on 2026-09-08.
- The `ledger drift` threshold noise — already specced and descoped in state-ledger after
  three review rounds.
- `CLAUDE.md:447`'s "now reads 45% of 53 real bash lines", measured 86% — a historical
  record of a heuristic fix, left alone.
- The two `terraform_ansible` docstrings citing `dotfiles' package_capture.sh` as a
  `LEDGER_BIN` exemplar (`state_ledger.py:60`, `test_ledger_callback.py:83`) — a backlog row
  in that repo. This spec makes those citations dangle; it is not this spec's place to edit
  another repo's prose. No executable consumer outside dotfiles was found:

  ```
  $ grep -rn 'package_capture\|brew_install_cask\|ledger_flush_spool' ~/git-repos/personal/ \
      --include='*.sh' --include='*.bats' --include='*.py' | grep -v '/dotfiles/'
  ai-config/scripts/run-bash-coverage.sh:230              comment
  math/scripts/run-bash-coverage.sh:236, :356             comment
  terraform_ansible/…/state_ledger.py:60                  docstring
  terraform_ansible/…/test_ledger_callback.py:83          docstring
  ```

## Multi-Lens Review

Reviewed at commit: `b3d1efb46bdc7585e9ba30c519f955a67afd7f1e` (Step 7 self-review commit,
before Step 8 dispatch). That commit's design proposed deleting two units and wiring
`ledger_flush_spool`. Round 1's findings removed the wiring entirely, so several sections
those findings addressed no longer exist. The findings are recorded as written, against the
text they were written against.

### Goal-Fit

Finding: the wire half solved a problem that does not exist. `cmd_write` calls
`_flush_spool_internal` (`ledger.py:443`) with a comment naming it "the only automatic drain
that exists on this fleet", and `run_update` already performs a `ledger write`. The wiring's
marginal drainage was zero; the only new thing was an operator-visible count, which is
observability rather than drainage and was not how the design justified itself. Separately,
the ntfy scrub suppressed a hazard the same PR introduced. Separately again, the deletion
acceptance check could not return 0 — 8 comment references survive, and its collateral
enumeration missed `launch_agents.bats:262`.

Assumption: that a spool entry can be _stuck_ — retryable, non-quarantined, still present
after the next `ledger write`. If not, `remaining` is structurally always 0 and the WARN
branch is dead code. Settled by reading `_flush_spool_internal`'s except branches.

Disposition: **Addressed.** Verified independently — `ledger.py:443` reads as reported. The
wiring is removed from the design entirely and `ledger_flush_spool` is now deleted rather
than wired, which is the stronger consequence of the same finding. The acceptance check is
replaced with a symbol grep and the 8 survivors are listed as deliberate keeps. The
assumption is moot with no flush call; `launch_agents.bats:262` is now enumerated.

### Ergonomics

Finding: `NTFY_URL` is live in `run_update`'s environment, not latent as the design claimed.
`setup_env.sh:69` sources `config/local.sh` unconditionally at top level, thirty lines above
the `run_update` dispatch at `:99`, and `config/local.sh:25` is an `export`. The subshell
scrub was therefore load-bearing rather than defensive, and no verification case asserted
it. Also: 6 of 6 cases expected PASS and none pinned a derived value — `_update_warn` takes
a literal, `cmd_flush` prints the count to stderr, and the design specified no mechanism to
get one to the other.

Assumption: that `ledger` is installed on more than the two development machines. If not,
`[SKIP] ledger-flush` becomes a permanent unactionable row on up to five of seven machines,
and the SKIP reason carried no remedy string.

Disposition: **Addressed by removal.** Verified independently — `setup_env.sh:69` and
`config/local.sh:25` read as reported, and the original "latent" measurement was taken in
the harness shell rather than `setup_env.sh`'s process, which is the actor-boundary error
`behavior.md` documents and which this spec cited while committing it. With no flush call
there is no ntfy path, no WARN reason to populate, and no SKIP row, so all three become
moot. The measurement is kept here because the actor error is the transferable part.

### Risk

Finding: same `NTFY_URL` inversion, reached independently. Same acceptance-check defect,
counted at ~10 rather than 8 by including `linux_shared.bats:121,:123`. Additionally: the
five wiring tests never named the file they would live in, and `update_summary.bats` — the
natural home for section-rendering tests — does not redirect `HOME`, so a wiring test
landing there with a bypassed mock would reach the operator's real `~/.local/bin/ledger` and
commit into state-ledger. Additionally: `_git_commit_and_push` failures are neither
`ValueError` nor `_PermanentSpoolError`, so a rebase conflict in the state-ledger repo would
leave `remaining` stuck above zero indefinitely — a persistent-WARN path the design's
quarantine analysis did not cover.

Assumption: that quarantined entries are excluded from `cmd_flush`'s `remaining`. Could not
settle it.

Disposition: **Addressed by removal**, with one item settled rather than dropped. The
assumption is resolved in the design's favour — `_flush_spool_internal`'s docstring states
"entries quarantined as permanently invalid are not counted" — so the permanent-WARN-via-
quarantine path never existed. The `_git_commit_and_push` path was a real second axis and is
moot with no flush call. The E2 file-naming finding is moot for the same reason, and its
general form already governs the deletions: no new test files are created by this design.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison, evaluator, or ambiguous-criteria trigger.
