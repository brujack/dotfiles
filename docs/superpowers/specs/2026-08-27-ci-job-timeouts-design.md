# CI Job Timeouts

Date: 2026-08-27
Status: Proposed

## Problem

No job in either tracked workflow declares `timeout-minutes`, so every job inherits
GitHub's 360-minute default. A hung job therefore blocks `auto-merge` for six hours
with nothing reporting a cause.

This is not hypothetical. On PR #223 the `powershell` job hung inside its
`Install PowerShell` step. Because `auto-merge` lists `powershell` in `needs:`, the PR
sat blocked with every other check green, and clearing it required a manual
`gh run cancel` followed by `gh run rerun`.

**Attribution of the two figures, because they have different sources.** The
**29+ minute hang** is from the backlog row recording the incident (measured
2026-08-18); it is not reproduced here and no run in this spec's sample exhibits it.
The **sub-minute baseline** is independently measured below (p50 54s over 40 runs) and
corroborates the backlog row's own figure of 47-54s over 7 runs. So the baseline half
is confirmed twice and the hang half rests on the earlier record alone.

The backlog row that recorded this said "0 of 6 jobs", counting `ci.yml` alone.
`pr-title-lint.yml` carries a seventh job with no cap either. The correct figure is
**0 of 7 jobs across 2 workflows**.

## Measurements

All figures below were taken on 2026-08-27 via the GitHub Actions API.

**Population:** the 40 most recent runs of `ci.yml` and the 40 most recent runs of
`pr-title-lint.yml` — 80 runs, yielding 280 job records (268 `success`, 7 `failure`,
3 `skipped`, 2 `cancelled`). Duration statistics below are computed over the 268
**successful** records only; failed and cancelled jobs are excluded because their
durations describe how long a failure took, not how long the work takes.

| job | n | p50 | p90 | max | min |
| --- | --: | --: | --: | --: | --: |
| `bash-coverage` | 36 | 464s | 492s | 645s | 294s |
| `test` | 37 | 313s | 342s | 412s | 258s |
| `powershell` | 40 | 54s | 60s | 65s | 46s |
| `auto-merge` | 35 | 10s | 11s | 13s | 7s |
| `lint-macos` | 40 | 9s | 12s | 15s | 6s |
| `secret-scan` | 40 | 7s | 8s | 11s | 4s |
| `PR Title Lint` | 40 | 3s | 4s | 5s | 2s |

The `powershell` row corroborates the backlog row's independently-taken figure
(47–54s over 7 runs) against a 40-run sample.

## Decisions

Three forks were settled before this spec was written.

**Sizing: generous per-job, not tight and not blanket.** The two long jobs grow with
the suite — 1478 tests today against a CI floor of 840 — so a cap sized tightly to
today's p90 becomes a flake generator, and a flaky cap on an unrelated PR costs a
rerun cycle and a diagnosis ("hang, or just slower?"). A blanket value was rejected
for the opposite reason: one number gives `bash-coverage` only 1.9x headroom over its
observed max while giving `secret-scan` roughly 170x more than it needs.

**Granularity: job-level only.** `ci.md` states the job-level cap is the binding one,
and GitHub's UI names the in-progress step when it kills a job, so the culprit step is
still identified without a step-level cap. Step-level caps on the 9 network-bound
install steps would cut `powershell` detection from 5 minutes to about 2 — a
second-order gain against 9 more numbers, each carrying an invariant (a step cap above
its job cap is silently ignored). Deferred, with a stated trigger: revisit if an
install step hits its job cap again under this change.

**Durability: a guard test, not the seven lines alone.** Seven YAML lines change
nothing about the next job someone adds. The file reached 0 of 7 by accretion, not by
decision, and without a guard the eighth job re-creates the defect silently.

## Values

| job | file | p90 | cap | basis |
| --- | --- | --: | --: | --- |
| `bash-coverage` | `ci.yml` | 492s | 25 | ~3x p90 |
| `test` | `ci.yml` | 342s | 20 | ~3.5x p90 |
| `powershell` | `ci.yml` | 60s | 5 | 5x p90 — the known-hang job, where a tighter cap is the one that pays |
| `lint-macos` | `ci.yml` | 12s | 10 | floor |
| `secret-scan` | `ci.yml` | 8s | 10 | floor |
| `auto-merge` | `ci.yml` | 11s | 10 | floor |
| `pr-title-lint` | `pr-title-lint.yml` | 4s | 10 | floor |

The four short jobs take a 10-minute floor rather than a multiple of p90, because
3 x 12s is smaller than ordinary runner queueing and cold-start variance. A floor that
still converts six hours into ten minutes is the whole of the benefit.

Each line carries its measured p90 and this date as a trailing comment:

```yaml
  test:
    runs-on: ubuntu-latest
    timeout-minutes: 20 # p90 342s, measured 2026-08-27 over 37 runs
```

Nothing detects these going stale. The comment exists so the next reader can judge
staleness without re-deriving the baseline, which is the cheapest thing that helps and
is not a mechanism.

## Guard test

`tests/scripts/workflow_timeouts.bats` asserts that every job in every tracked
workflow declares `timeout-minutes`.

**No new dependency: the parser is awk, not a YAML library.** The `test` job installs
`bats`, `zsh`, `shellcheck` and `uv`, and no Python packages. `pyyaml` is present on
this machine (6.0.3, under pyenv Python 3.14.6) and is **not installed by any step in
either workflow** — so a test importing it would be relying on the contents of the
`ubuntu-latest` runner image, which is unpinned and can change between runs. Whether
that image ships `pyyaml` today was not measured and is deliberately not relied upon.
`CLAUDE.md` already records the cost of the adjacent mistake: `uv` was added to the
`test` job only, and `bash-coverage` runs the same `make test`, so four tests failed in
the job that was not updated. Any tool a new test needs must be installed in both jobs;
needing none avoids the question.

**Exemption: jobs whose body is a reusable-workflow call.** A job that declares
`uses:` at job level instead of `steps:` is skipped by the assertion. `ci.md` already
records that such jobs cannot carry `strategy: matrix`, and job-level `timeout-minutes`
is believed to be constrained the same way — **that specific constraint is unverified**,
and it should be checked before this exemption is ever relied on. It is inert today:
**0 of 7 jobs** across both workflows use the `uses:` form, all seven declare `steps:`.
Without the exemption the test would demand a key GitHub may reject, turning the guard
into a blocker the first time a reusable workflow is adopted; with it, a reusable-workflow
job added later goes uncapped and unreported. Both directions are bad, which is why the
constraint needs verifying rather than assuming.

Four properties, each answering a defect this repo has already paid for:

1. **Scope derives from the tracked set** —
   `git ls-files '.github/workflows/*.yml' '.github/workflows/*.yaml'` — never a
   literal file list. An omitted file is absent from the assertion entirely and cannot
   make it fail (`tdd.md`, Coverage Denominators). `*.yaml` is included because GitHub
   accepts both extensions; zero such files exist today.
2. **The `git ls-files` call is wrapped in
   `env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE`**, reusing the
   `_git_ls_clean` helper already in `tests/scripts/makefile_lint_scope.bats`.
   `scripts/pre-push` runs `make test`, git exports `GIT_DIR` into a hook when the push
   originates from a worktree, and `git -C` does not override it.
3. **An empty file list fails the test.** A pathspec that matches nothing must not
   report a pass — the same rule `SHELL_FILES` and `ZSH_FILES` already follow in the
   `Makefile`.
4. **Parsing is per job and anchored after the `^jobs:` line.** A workflow-wide grep
   for `timeout-minutes` is satisfied by a hit in any job; `CLAUDE.md` records exactly
   that defect in the test written to keep `uv` in both jobs, which passed on a hit in
   the wrong job. Anchoring at `jobs:` is equally load-bearing: an exploratory parser
   written during this design reported `pull_request` as a job in **both** files,
   because the children of the `on:` block sit at the same two-space indent as job
   keys.

## Verification

- `make test` passes.
- **Positive control, required.** Delete one `timeout-minutes` line, confirm the test
  goes red and names that job, then restore it. Without this the test passing is
  indistinguishable from the test examining nothing — the failure mode `bug-scan`
  Step 6 exists for.
- The parser is exercised against the real workflow files, not a hand-written fixture
  (`tdd.md`, pitfall F).

**Stated limit:** nothing here proves a cap actually fires. That requires a real hang,
which cannot be manufactured on demand. The test proves the declarations are present
and stay present; GitHub enforces them.

## What this does not do

- **It does not make a blocked PR self-heal.** A timed-out job is still a red required
  check, so `auto-merge` stays blocked and someone still runs `gh run rerun`. The
  change converts six hours of silence into at most 25 minutes with a named cause.
- **No retry on timeout.** Retrying a hang spends the cap a second time.
- **No step-level caps** — deferred, with the trigger stated above.
- **No staleness detection** on the values themselves.

## Related

- Backlog row this replaces: "no CI job declares `timeout-minutes`, so a hung job
  blocks auto-merge for 6 hours" (`docs/superpowers/README.md`).
- `ci.md`, "Job-Level `timeout-minutes` Caps Step-Level".
- `CLAUDE.md`, the `bash-coverage` note on tools needing installation in both jobs.
- `tdd.md`, Coverage Denominators (scope derived from the tracked set) and pitfall F
  (parsers verified against real tool output).
