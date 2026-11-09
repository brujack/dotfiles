# Weekly uv.lock refresh: 14-day release-age cooldown

- **Date:** 2026-11-09
- **Repo:** dotfiles
- **Parent spec:** `2026-11-08-uv-lock-refresh-design.md` ("No release-age cooldown")
- **Backlog row closed:** "Weekly lock refresh has no release-age cooldown"

## Problem

`scripts/refresh-uv-lock.sh` runs a bare `uv lock --upgrade`, so the weekly refresh PR admits
releases published minutes before the run. On 2026-11-09 it proposed `typer` 0.29.0, uploaded
at 18:48:11Z, about ten minutes before the run (dotfiles#451). The operator's review of the
change list is the only gate. Renovate does not manage Python here and `dependency-review`
does not run on a bot PR merged by hand, so nothing else in the pipeline checks release age.

The fleet's policy for this exists already: Renovate's `minimumReleaseAge` is `14 days`
(dotfiles `renovate.json`, ai-config preset, operator decision 2026-10-26), on the reasoning
that a compromised release is usually caught and yanked within days.

The parent spec tried a global `--exclude-newer` and dropped it on three measured defects:
it writes `[options] exclude-newer` into `uv.lock` so `make check-lock` fails; it drops
locked versions as preferences and so downgrades packages master holds at young versions,
CVE fixes among them; and a `pyproject.toml` floor that needs a young release fails
resolution. This design avoids all three by capping only the packages the run changed.

## Decisions taken

- A change younger than the cooldown is held back, not merely flagged, and not allowed to
  block the rest of the run (operator, 2026-11-09).
- The cooldown is 14 days, equal to Renovate's `minimumReleaseAge`.
- No security bypass: every fresh release is held uniformly. Dependabot alerts stay on, so
  a CVE in a held package still alerts and can be bumped by hand (operator, 2026-11-09).

## Design

### Age

A version's age is the earliest `upload-time` among its files in `uv.lock` (wheels and
sdist). uv records `upload-time` for every registry package (268 of 268 at `f34ddbeb`), so
no network lookup is needed. A version is **fresh** when that earliest upload is later than
the cutoff, `now − 14 days`. A changed version with no `upload-time` at all is treated as
fresh (fail closed).

A package locked at several versions across resolution forks is compared as a set of
versions per name, as `uv_lock_downgrades.py` already does.

### Flow

`_refresh_run` keeps its current shape, with one pass inserted after the upgrade:

1. Copy `uv.lock` to `base` (unchanged).
2. `uv lock --upgrade` (unchanged).
3. **Cap pass.** `scripts/uv_lock_cooldown.py plan <base> uv.lock <cutoff>` prints the uv
   arguments for every package whose version set differs from `base` and contains a fresh
   version:
   - when `base` holds the package and one of its base versions is itself fresh (a fix
     taken by hand inside the window), `--upgrade-package P==<base version>`, so the cap
     never reverts it;
   - otherwise `--upgrade-package P --exclude-newer-package P=<cutoff>`, which resolves P to
     its newest release at least 14 days old.

   It also writes one report line per capped package to a file. When it prints no
   arguments the pass is skipped. Otherwise the script runs one `uv lock` with all of them,
   then a plain `uv lock`. That relock does two things: it removes the `[options]` table the cap pass wrote, and it restores files the cap filtered out. uv applies the cutoff per file, so a capped package's aged version can lose wheels uploaded after the cutoff (measured on `configobj` 5.0.9 in a scratch project), and the relock, which keeps the capped versions as preferences, puts them back. It re-resolves at all only because the cap's `[options]` table no longer matches the request; a plain `uv lock` on a lock that is still valid restores nothing. The script never edits `uv.lock` text itself.

4. **Post-condition.** `uv_lock_cooldown.py verify <base> uv.lock <cutoff>` exits 1 and names
   any package whose version changed from `base` to a fresh version, so a cap uv did not
   honour fails the run instead of shipping.
5. **Net change list.** `uv_lock_cooldown.py diff <base> uv.lock` prints the net changes from
   `base` to the final lock as `Updated P vA -> vB`, `Added P vB` and `Removed P vA` lines,
   uv's own format. This replaces the grep of uv's output, which describes only the last uv
   call. It feeds the downgrade check (unchanged) and the PR body. When it prints nothing, the version sets of `base` and the final lock are equal: `base` is copied back over `uv.lock` and the script prints `no changes`. `uv lock --upgrade` refreshes the file lists of versions it keeps, so a lock can differ from `base` by a newly uploaded wheel alone; such file-list-only changes wait for a run that moves a version, rather than failing a week in which the cap held every change. To keep a broken parser from reporting `no changes` silently, `diff` exits 2 when either lock parses to zero registry packages.
6. Renderings, `check-lock`, `check-requirements-ci` and the body follow as today.

Nothing is capped except packages this run changed, so a package master holds at a young
version keeps it (no downgrade), and no `pyproject.toml` floor sees a cutoff it has to
satisfy unless the run moved that package.

### PR body

When any package was capped, the body gains a section after the change list:

```
### Held by the 14-day cooldown

- typer: newest 0.29.0 uploaded 2026-11-09T18:48:11Z; took 0.28.0
```

`took` names the version the final lock holds, which is either an older aged release or
master's version. The section is absent when nothing was capped.

### Clock and constant

- `REFRESH_COOLDOWN_DAYS` is a `readonly` 14 in `scripts/refresh-uv-lock.sh`. A bats test
  asserts it equals the day count of `renovate.json`'s `minimumReleaseAge`.
- `REFRESH_COOLDOWN_NOW` (RFC 3339, UTC) is a test seam with a production default of the
  current UTC time. The cutoff is computed from it once per run and passed to every helper
  call and to `--exclude-newer-package` in the same string.

### Failure behaviour

| Failure                                                                            | Result                                                                                          |
| ---------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| The cap `uv lock` fails (e.g. a fresh package new to the lock has no aged release) | exit non-zero, `cooldown re-resolve failed`; the workflow's existing report job files the issue |
| The plain `uv lock` after it fails                                                 | exit non-zero, `cooldown lock rewrite failed`                                                   |
| `verify` finds a fresh version                                                     | exit non-zero, `cooldown not honoured: <names>`                                                 |
| A helper exits 2 (unreadable lock, a lock with zero registry packages, crash)                                          | exit non-zero, `cooldown helper failed (rc N)`                                                  |

### Measured feasibility

Replayed on the tree at `41893754` (2026-11-04) with uv 0.13.7 on `claude`, cutoff
2026-10-26T19:00Z. Population: dotfiles' own `pyproject.toml` and `uv.lock` at that commit,
against PyPI as of 2026-11-09. `uv lock --upgrade` changed 105 packages and added 1.

- 55 aged upgrades kept at the latest version, none lost.
- 41 fresh changes moved to their newest aged release (e.g. ansible 14.3.1 → 14.5.0 rather
  than 14.6.0).
- 9 fresh changes held at the base version.
- 0 fresh versions admitted, 0 packages below base.
- The cap pass wrote `[options]`; the plain `uv lock` removed it with no further change,
  and `uv lock --check` exited 0.

Holding fresh changes at the base version alone was rejected: a package that releases more
often than every 14 days (hypothesis, regex, typer in this replay) would never move.

## Testing

- `tests/test_uv_lock_cooldown.py` (stdlib `unittest`, like `test_uv_lock_downgrades.py`)
  drives `plan`, `verify` and `diff` on small fixture locks: unchanged packages emit nothing;
  a fresh change with an aged base gets `--exclude-newer-package`; a fresh base version gets
  `==base`; a missing `upload-time` is fresh; multi-version packages compare as sets;
  boundaries at exactly the cutoff (not fresh) and one second after (fresh); exit 2 on an
  unreadable lock.
- `tests/scripts/refresh_uv_lock.bats` drives the script through the existing `_UV_BIN`
  stub, extended to rewrite `uv.lock` per call, for: no fresh change (no cap call made);
  a capped run (cap call made with the expected arguments, then a plain `uv lock`, body
  section present); a cap that restores every version while a wheel was added to an unchanged version (`no changes`,
  `uv.lock` byte-equal to base afterwards); `diff` on a fixture pair cut from the real `41893754`
  base and upgraded locks prints the expected non-empty line set, and exits 2 on a lock with no
  registry packages; each row of the failure table. The capped-run case asserts the exact
  argument list the stub received, not only that a call was made. The cutoff is computed in
  Python, since BSD `date` on the macOS shards has no `-d`.
- The constant test compares `REFRESH_COOLDOWN_DAYS` with `renovate.json`.

## Requirements

- **R1.** `[PR1]` `scripts/uv_lock_cooldown.py plan BASE NEW CUTOFF` prints, for each package whose version set differs between BASE and NEW and contains a version whose earliest `upload-time` is later than CUTOFF (or has none), `--upgrade-package P==V` when BASE holds P at a version V whose earliest `upload-time` is later than CUTOFF, else `--upgrade-package P --exclude-newer-package P=CUTOFF`; it prints nothing for any other package.
- **R2.** `[PR1]` `refresh-uv-lock.sh` runs one `uv lock` with `plan`'s arguments followed by a plain `uv lock` only when `plan` printed arguments, and makes no extra `uv lock` call otherwise.
- **R3.** `[PR1]` `uv_lock_cooldown.py verify BASE FINAL CUTOFF` exits 1 and names each package whose version changed from BASE, or which BASE lacks, to a version whose earliest `upload-time` is later than CUTOFF, and the refresh exits non-zero with `cooldown not honoured:` when it does.
- **R4.** `[PR1]` The change list passed to the downgrade check and written to the PR body is `uv_lock_cooldown.py diff BASE FINAL`, in uv's `Updated`/`Added`/`Removed` line format, not a grep of uv's output.
- **R5.** `[PR1]` When `diff` prints nothing, the refresh copies BASE over `uv.lock` and prints `no changes`; `diff` exits 2 when either lock holds zero registry packages.
- **R6.** `[PR1]` When any package was capped, the PR body contains a `### Held by the 14-day cooldown` section with one line per capped package naming its newest version, that version's earliest upload time and the version taken; the section is absent otherwise.
- **R7.** `[PR1]` `REFRESH_COOLDOWN_DAYS` is 14, and a test fails if it differs from the day count in `renovate.json`'s `minimumReleaseAge`.
- **R8.** `[PR1]` `REFRESH_COOLDOWN_NOW` overrides the clock; the cutoff string passed to `plan`, `verify` and `--exclude-newer-package` is computed once per run.
- **R9.** `[PR1]` Each failure in the failure table exits non-zero with its stated message.
- **R10.** `[PR1]` The Backlog row "Weekly lock refresh has no release-age cooldown" is removed, and the CLAUDE.md `uv-lock-refresh.yml` bullet states the 14-day cooldown.
- **R11.** `[PR1]` After every cap `uv lock`, `refresh-uv-lock.sh` runs a plain `uv lock`, and the script writes `uv.lock` only through uv or R5's copy of BASE.
- **V1.** Replaying the refresh at `41893754` with uv 0.13.0 (the CI pin) and `REFRESH_COOLDOWN_NOW=2026-11-09T19:00:00Z` admits 0 versions uploaded after 2026-10-26T19:00:00Z, moves 0 packages below base, passes `make check-lock`, and leaves every changed package either at the newest release uploaded on or before the cutoff or at its base version, with at least one package in each of those two states (measured 2026-11-09: 55 kept at latest, 41 at an older aged release, 9 at base; context, not a pass criterion).
- **V2.** The first scheduled run after merge either reports `no changes` or opens a PR whose held section matches the upload times on PyPI for each listed package.
- **V3.** In the V1 replay, the plain relock after the cap moves 0 versions and every capped package's final entry has the same wheel count as a plain `uv lock` of that version.
- **N1.** No security-advisory lookup and no network call besides uv's own resolution.
- **N2.** No global `--exclude-newer` and no `exclude-newer` left in a committed `uv.lock`.
- **N3.** `plan` emits no argument for a package whose version set is the same in BASE and NEW.
- **N4.** No change to the five renderings' groups or to ai-config.

## Multi-Lens Review

Reviewed at commit: `d47b9b77` (Step 7 self-review commit, before Step 8 dispatch)

### Goal-Fit

Finding: R5 moves the "nothing changed" decision from `cmp` onto the new `diff` helper's output. A `diff` that wrongly prints nothing with rc 0 (a parse bug, a future lock format) would restore base and report `no changes` every week, closing the PR with no issue filed. Today's refusal `uv printed no change lines but uv.lock changed` exists for exactly this and was added on purpose in the parent spec. Keep `cmp` as the authority: a byte difference with an empty `diff` must fail the run. V1 and V2 also pass on a run that does nothing.
Assumption: one cap pass is enough, i.e. capping P never moves another package Q to a fresh version. Checked by the orchestrator: the planned flow replayed at five weekly points (2026-10-05, 10-12, 10-19, 10-26, 11-02; PyPI simulated with `--exclude-newer` at each date, cutoff 14 days earlier) plus `41893754` admitted 0 fresh versions in 6 of 6 runs and left no `[options]`.
Disposition: Addressed (operator, 2026-11-09) — R5 rewritten: `cmp` alone decides `no changes`, and a byte difference with an empty `diff` fails the run; failure-table row added.

### Ergonomics

Finding: V1, V2 and the bats "restores everything" case all expect PASS and all pass on a cap pass that holds everything at base; a no-op or over-holding cap would show as a quiet weekly `no changes`. Pin V1 to the measured split at `41893754` (55 kept, 41 moved to an aged release, 9 held at base, ansible at 14.5.0). Not raised: the first run's held section will be large (about 50 lines) once; compute the cutoff in Python, since BSD `date` on the macOS shards has no `-d`.
Assumption: CI pins uv 0.13.0, not the 0.13.7 the design was measured with. Checked by the orchestrator: the checksum-verified 0.13.0 binary reproduces the `41893754` replay exactly (55 / 41 / 9, 0 fresh admitted, `[options]` removed, `uv lock --check` rc 0).
Disposition: Addressed (operator, 2026-11-09) — V1 pinned to the 55 / 41 / 9 split under uv 0.13.0 with ansible at 14.5.0; the bats capped-run case asserts the exact arguments; the cutoff is computed in Python.

### Risk

Finding: (1) Same vacuity as Ergonomics: V1 and V2 cannot fail on a run that measures nothing. (2) The plain `uv lock` does more than remove `[options]`: uv's per-file cutoff can drop an aged version's late-uploaded wheels in the cap call (measured on `configobj` 5.0.9 in a scratch project), and the plain relock restores them. The spec does not say so and no test pins it, so skipping the relock (e.g. stripping `[options]` with sed) would leave sdist-only entries. (3) R3 says "changed from BASE"; an added package that a cap failed to honour is not clearly covered. Should read "changed or added".
Assumption: the plain relock keeps every capped version and restores dropped files. Checked by the orchestrator at full scale with uv 0.13.0: between the capped lock and the final lock, 0 versions moved and 0 wheel counts changed.
Disposition: Addressed (operator, 2026-11-09) — the Flow states the relock's file-restoring role; R11 requires the relock after every cap and forbids non-uv writes to `uv.lock`; V3 pins 0 version moves and matching wheel counts; R3 covers added packages.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.

### Round 2 (all three lenses, re-reviewed at `21d68dcf`)

- Goal-Fit (`21d68dcf`): V1's exact counts depend on PyPI's state and drift within days; assert invariants instead and keep the counts as context. Assumption (a cap moves an unnamed package to a fresh version): checked by the orchestrator, 0 of 6 replays (one unnamed mover, `greenlet`, aged). Disposition: Addressed — V1 asserts the invariants plus at least one package at an older aged release and one at base; counts kept as context.
- Ergonomics (`21d68dcf`): no load-bearing issue; the round-1 R5 refusal named no package and would recur weekly. Assumption (R5 refusals stay rare): 0 of 6 replays reached the path. Disposition: Addressed — superseded by the Risk decision below, which removes the refusal.
- Risk (`21d68dcf`): R5 with a version-only `diff` fails a week in which the cap holds every change while `uv lock --upgrade` added a wheel to an unchanged version (reproduced in a scratch project); R11 contradicted the workflow's own staging copy. Assumption (uv 0.13.0 relock keeps capped versions): checked by the orchestrator with the checksum-verified 0.13.0 binary, 0 versions moved. Disposition: Addressed (operator, 2026-11-09: "Same versions = no changes") — R5 restores BASE when the version sets are equal, `diff` exits 2 on a lock with zero registry packages, R11 scoped to the script and allows R5's copy. Incident: this lens ran `uv lock` in the main checkout twice after failed `cd`s and restored `uv.lock` itself; the orchestrator confirmed the blob equals HEAD and no tracked change remained.
