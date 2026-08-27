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

**The incident is now measured directly, and finding it required correcting the
method.** `GET /actions/runs/{id}/jobs` returns only the **latest attempt**, so a
`gh run rerun` — the documented remedy for #223 — erases the incident from the default
view. A 100-run sweep of `powershell` jobs returned 100 successes and no anomaly; that
was an artifact of the default filter, not a finding. Re-querying with `?filter=all`:

```
run 32170309604  attempt 1  2026-08-18  fix/zsh-legacy-identity-consolidation
  powershell: cancelled, 30.4 min
    Install PowerShell            cancelled  1815s
    Install Pester + PSScriptAnalyzer  skipped
    Run tests with coverage gate       skipped
run 32170309604  attempt 2  ->  success, 0.9 min
    Install PowerShell            success      18s
```

**This is a stall, not a slow install**: 1815s of no progress on `Install PowerShell`,
every later step skipped, and 18s on the immediate rerun. Across **105 attempt records**
in the sample, the `Install PowerShell` step is 104 successes (min 8s, p50 14s, p90 21s,
**max 44s**) and the single 1815s cancellation, with **no observation between 44s and
1815s**.

**That gap is an inference, and is labelled one deliberately.** It has exactly one
observation on its far side, and an earlier draft of this section compared a *step*
maximum against a *job* maximum, which is not a like-for-like bound. What the data
supports: across 105 attempts none took between 44s and 30 minutes, so a 300s cap sits
at ~6.8x the observed step maximum. What it cannot support: a claim that a legitimately
slow install can never land in that band. The cost if it does is one rerun.

Anyone re-deriving this must pass `?filter=all`. Both the default job endpoint and the
obvious `gh run list` path hide reran attempts, so the incident this spec exists for is
invisible to the query most likely to be reached for.

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

**Durability: a reduced guard test, and its case is weaker than it first looked.**
Seven YAML lines change nothing about the next job someone adds, and the file reached
0 of 7 by accretion rather than by decision. But measured over the population the
decision actually governs, the guard's expected firing rate is **zero**: `ci.yml` went
2 -> 6 jobs between 2026-04-02 and 2026-04-27, `pr-title-lint.yml` added its single job
on 2026-05-17, and every `.github/` commit in the four months since edits steps inside
existing jobs. An earlier estimate of ~0.4 firings/month was computed over all history
including the bring-up burst — the wrong reference class. A backlog sweep finds **0 of
58 rows** proposing a new CI job.

So the guard is retained in reduced form: the per-file job-name-set assertion and the
scope/enumeration properties that make it trustworthy, and nothing else. An eighth job
turns the suite red on set mismatch, which is the whole of the durability requirement.
Everything that generated defects in review — a `uses:` branch, a re-indentation
mutation needing a production seam — is dropped rather than fixed, because the event
they guard has not occurred in four months and nothing planned would cause it.

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
3 x 12s is smaller than ordinary cold-start and network variance within the job. (An
earlier draft said "queueing"; `timeout-minutes` is measured from job start, not from
queue entry, so queue time is not on the clock. The correction makes the floor more
conservative, not less.) A floor that still converts six hours into ten minutes is the
whole of the benefit.

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

**Reusable-workflow (`uses:`) jobs are out of scope, and that is now an evidence-based
exclusion rather than a deferral.** SchemaStore's `github-workflow.json` — the schema
`actionlint` and most editors validate against — declares `reusableWorkflowCallJob` with
`additionalProperties: false` and **no `timeout-minutes` key**, while `normalJob` has it.
A job-level cap is therefore not expressible on such a job, so both earlier drafts were
wrong: exempting them silently hid a gap, and failing on them created a gate with no
green path — an adopter could neither add the key nor omit it.

The guard asserts nothing about `uses:` jobs. It is inert today (**0 of 7 jobs** use that
form) and, because nothing is asserted, the open question of whether GitHub's runner
*errors* on the key or *silently ignores* it does not need answering to ship this. When a
reusable workflow is first adopted, the cap for it belongs in the called workflow's own
jobs; if that workflow is local, it is already in this guard's scope by pathspec.

Recorded as a known limit rather than solved: a *remote* reusable workflow's jobs are
outside `git ls-files` and this guard cannot see them.

Two corollaries. `ci.md`'s "Reusable Workflow Calls Cannot Use `strategy: matrix`" is
**wrong** — the same schema shows `strategy` **is** permitted on a `uses:` job, and
GitHub now documents "Using a matrix strategy with a reusable workflow". That is a
cross-cutting finding against a standard nine repos read, and belongs in ai-config's
backlog, not here. And SchemaStore is a community model of GitHub's parser rather than
the parser itself — which is exactly why this design no longer depends on it.

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
4. **Parsing is per job, anchored after `^jobs:`, with a matcher wide enough for the
   shapes YAML allows and a fail-closed arm for the ones it is not.** The job-key matcher
   is `^  [^ ].*:$`, not `^  [A-Za-z0-9_-]+:` — the narrow character class silently misses
   a **quoted** job key. Measured: a file with `test:` and `"deploy":` yields `['test',
   'deploy']` to a YAML parser and **only `test`** to the narrow matcher, so an uncapped
   `deploy` is invisible while the file still contributes >=1 job and passes. The parser
   additionally **fails** rather than proceeding when `jobs:` carries trailing content on
   its own line (flow mapping, `jobs: {build: {...}}`, which yields 0 keys to any
   line-oriented matcher) or when the file contains tab indentation. Unknown shape is a
   failure, not a pass — `USER.md`, fail closed on unknown.

   A workflow-wide grep
   for `timeout-minutes` is satisfied by a hit in any job; `CLAUDE.md` records exactly
   that defect in the test written to keep `uv` in both jobs, which passed on a hit in
   the wrong job. Anchoring at `jobs:` is equally load-bearing: an exploratory parser
   written during this design reported `pull_request` as a job in **both** files,
   because the children of the `on:` block sit at the same two-space indent as job
   keys.

## Verification

- `make test` passes.
- **Pin the measurement, not only the verdict.** Assert the parser's derived job-name
  set per file — `ci.yml` yields exactly `test lint-macos powershell bash-coverage
  secret-scan auto-merge`, and `pr-title-lint.yml` exactly `pr-title-lint` — and assert
  every tracked workflow contributes at least one job. A named set beats a count of 7,
  because a count also passes when one real job is dropped and one phantom `on:` child
  is added, which is precisely the error already caught by hand during this design.

  Without this the gate has an unpinned denominator one level below the file list.
  "Every job declares `timeout-minutes`" is **vacuously true over zero jobs**, so a
  tracked file the parser cannot read passes silently. That is not hypothetical: a
  workflow indented four spaces under `jobs:` is valid YAML that GitHub accepts, and
  yields 2 jobs to a YAML parser and **0 jobs** to a two-space anchored matcher.
- **One mutation, required.** Delete one `timeout-minutes` line; confirm red, naming
  that job; restore.

  **A second mutation was specified and then withdrawn, because it cannot run.** The
  draft asked for a copy of `ci.yml` re-indented to four spaces, asserted red. Property 1
  derives scope from `git ls-files`, so an untracked copy is invisible to the parser and
  the mutation returns **green** — it would have shipped as a verification step that
  proves nothing. Executing it needs either a tracked fixture (which the real-files rule
  above discourages) or a declared override seam, the shape this repo already uses for
  `REQUIREMENTS_CI_TARGET`. Neither is built here: under the reduced guard the
  zero-jobs case is covered structurally instead, because the parser now **fails** on the
  shapes that produce it rather than returning an empty set.
- The parser is exercised against the real workflow files, not a hand-written fixture
  (`tdd.md`, pitfall F).

**Where the guard actually runs.** `scripts/pre-push:57` excuses `^\.github/.*\.ya?ml$`
from triggering the local suite, so a workflow-only change — which is what adding a job
is — skips `make test` locally and the guard fires only in CI, in both `test` and
`bash-coverage`. It does run locally when the author also touched `tests/`, i.e. when
they have already done the right thing. Presenting `make test` as the gate would be
wrong; CI is the gate for this guard's own trigger class.

**Stated limit:** nothing here proves a cap actually fires. That requires a real hang,
which cannot be manufactured on demand. The test proves the declarations are present
and stay present; GitHub enforces them.

## What this does not do

- **It does not make a blocked PR self-heal.** A timed-out job is still a red required
  check, so `auto-merge` stays blocked and someone still runs `gh run rerun`.
- **It does not save six hours.** Six hours is GitHub's default, not observed harm: #223
  ran 18:18:50 -> 18:49:11 (30m21s) and was ended by a human `gh run cancel`, with every
  other job green by 18:26:32. The real benefit is **removing the need to notice** — the
  cap ends the job without a person having to be watching — plus bounding the unattended
  case at 25 minutes. Stating it as "six hours saved" overstates a ceiling nobody hit.
- **No retry on timeout.** Retrying a hang spends the cap a second time.
- **No step-level caps** — deferred, with the trigger stated above.
- **No staleness detection** on the values themselves.
- **It does not verify whether GitHub accepts job-level `timeout-minutes` on a
  reusable-workflow job.** That question is now surfaced by a failing test at the moment
  it first matters, rather than answered in advance.

## Related

- Backlog row this replaces: "no CI job declares `timeout-minutes`, so a hung job
  blocks auto-merge for 6 hours" (`docs/superpowers/README.md`).
- `ci.md`, "Job-Level `timeout-minutes` Caps Step-Level".
- `CLAUDE.md`, the `bash-coverage` note on tools needing installation in both jobs.
- `tdd.md`, Coverage Denominators (scope derived from the tracked set) and pitfall F
  (parsers verified against real tool output).

## Multi-Lens Review

Reviewed at commit: `c51bcf8` (Step 7 self-review commit, before Step 8 dispatch)

### Goal-Fit

Finding: Build it — premise verified independently (0 of 7 jobs, 2 workflows, zero
`timeout-minutes` in `.github/`, `auto-merge` does list `powershell` in `needs:`). Job
keys were added 8 times across 7 separate PRs and none carried a cap, so accretion is
measured rather than asserted; expected firing rate of the guard is ~0.4/month. Two
findings: (1) the `uses:` exemption's own follow-up is unreachable, because the
exemption fires silently and the event that would trigger the check is the event it
hides — make it a hard failure instead; (2) the verification suite pins a verdict and
never the parser's enumeration, and only one error direction is covered — an
over-counting parser fails loudly, an under-counting one passes silently.
Assumption: that the #223 incident was an indefinite stall rather than a
slow-but-progressing install — the duration statistics exclude the only records that
could speak to it.
Disposition: **Addressed.** Both findings applied. The assumption was checked before
recording this disposition and is **refuted in the design's favour**: `?filter=all`
shows `Install PowerShell` cancelled at 1815s with every later step skipped, and 18s
on the immediate rerun. Recorded in the Problem section, along with the method
correction that found it.

### Ergonomics

Finding: The guard's job enumeration can return nothing and the test still passes.
Property 3 pins the empty *file* list; an empty *job* list within a found file is
vacuously true and green. Measured: a workflow indented four spaces under `jobs:` is
valid to GitHub and yields 2 jobs to a YAML parser, 0 to the spec's described anchor —
so the eighth job, the exact case the guard exists for, would arrive green. Fix by
asserting a specific non-zero derived count per file rather than a verdict. Second: do
not build the `uses:` exemption at all; `behavior.md` Simplicity First forbids designing
for hypothetical requirements and `USER.md` says unknown is not safe.
Assumption: that the guard's job enumeration is complete — that every workflow GitHub
accepts is one this parser fully enumerates. Already refuted for the four-space case;
the remaining shapes (flow-mapping `jobs: {build: {...}}`, tabs, quoted job keys) cannot
be enumerated without writing the parser, and a false answer produces a green test.
Disposition: **Addressed.** Verification now asserts the derived job-name set per file
and requires a re-indentation mutation proving red rather than green-over-zero. The
exemption is removed. The residual enumeration shapes are handed to Phase 2, where the
parser exists and can be run against them.

### Risk

Finding: The mechanism is proportionate — a timeout firing on a slow run costs one
rerun cycle, reaching the same blocked state in ≤25 min instead of 360, with GitHub
naming the step; the failure mode of the fix is strictly cheaper than the failure it
replaces. The flaw is the guard's per-file job denominator, unguarded — the fourth
instance in this repo of the shape `tdd.md` Coverage Denominators describes. Assert the
derived job *set*, not a count: a count of 7 also passes when one real job is dropped
and one phantom `on:` child is added. Second: the reusable-workflow exemption is a
silent skip in a default-deny gate built for zero instances; the spec names the
consequence itself and *unreported* is the whole defect. Notes that `ci.md`'s
"reusable-workflow jobs cannot carry `strategy: matrix`" is itself possibly stale, so
the analogy rests on a premise that may no longer hold.
Assumption: same as Goal-Fit — that #223 was a hang rather than a legitimately slow
install, since `powershell: 5` is the one deliberately tight cap.
Disposition: **Addressed.** Job-name set (not count) asserted; exemption replaced with
a hard failure. The `ci.md` staleness claim is **not verified here** — two same-model
lenses agreeing is not independent confirmation — but the fix removes the dependency on
it either way. Filed separately as a finding against `ci.md`.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger. No competing arms, no
judge component; acceptance criteria are concrete (`make test` green, two named
mutations each asserted red).

## Multi-Lens Review — Round 2

Reviewed at commit: `b2da333` (round-1 dispositions applied). Round 1's section above is
retained as history; these lenses were told not to treat it as settled.

### Goal-Fit

Finding: Build the seven lines; the guard defends an event that stopped happening four
months ago, and round 1's ~0.4/month rate drew from the wrong population. Measured
per-commit: `ci.yml` 2 -> 6 jobs between 2026-04-02 and 2026-04-27, `pr-title-lint`'s
single job 2026-05-17, and every `.github/` commit since edits steps inside existing
jobs — firing rate over the post-bring-up class is zero. Separately, verification
mutation 2 is not executable: scope comes from `git ls-files`, so an untracked
re-indented copy is invisible and the mutation returns green, meaning round 1's
ergonomics fix would have shipped unproven. Also measured *in the design's favour*: 105
`Install PowerShell` attempts, max 44s, nothing between 44s and 1815s — better evidence
than the spec claimed for itself.
Assumption: that four months of zero job additions is a settled CI surface rather than a
lull; settled by counting backlog rows whose implementation would add a `jobs:` key.
Disposition: **Addressed.** Assumption checked before recording: **0 of 58** backlog rows
propose a new CI job (the one "CI job" match is a CLOSED row stating no CI job invokes
`setup_env.sh`). Guard reduced to the job-name-set assertion plus the properties that
make it trustworthy; mutation 2 withdrawn with its reason recorded; the reference-class
correction and the corrected `Install PowerShell` figures are now in the body.

**One claim from this lens is rejected on measurement.** It declined to raise the
quoted-key/flow-mapping shapes, reasoning they "yield 0 jobs for that file, which the
per-file set assertion turns red." A fixture shows a quoted `"deploy":` yields **1** job
to the narrow matcher, so the file passes both assertions with an uncapped job hidden.
Risk's contrary finding is the correct one; three lenses agreeing would not have
distinguished them.

### Ergonomics

Finding: The hard-failure-on-`uses:` may have no green path — an adopter can neither add
`timeout-minutes` (if GitHub rejects it) nor omit it (the guard fails), leaving them to
edit an unrelated test inside a PR about something else. Could not settle it from
GitHub's docs, which are silent in both directions. Two amplifiers: `scripts/pre-push:57`
excuses `^\.github/.*\.ya?ml$`, so the guard cannot fire locally for its own trigger
class; and any failure message must state a remedy rather than a research task. Confirms
independently that `ci.md`'s `strategy: matrix` claim is stale.
Assumption: that GitHub accepts job-level `timeout-minutes` on a `uses:` job.
Disposition: **Addressed.** Assumption checked before recording and **refuted**:
SchemaStore's `github-workflow.json` declares `reusableWorkflowCallJob` with
`additionalProperties: false` and no `timeout-minutes`. The `uses:` branch is therefore
dropped entirely rather than repaired, which removes the unsatisfiable path and makes the
runner's error-vs-ignore behaviour irrelevant to shipping. The pre-push scoping is now
stated in Verification.

### Risk

Finding: The `uses:` hard failure is very likely unsatisfiable, and deferring authorship
of the exemption to a stranger under time pressure is worse than the silent version it
replaced; proposes a named allowlist that prints. The job-name-set assertion is scoped to
today's two files, so partial under-enumeration inside a future workflow arrives green —
demonstrated with a quoted job key in ten seconds, refuting round 1's disposition that
these shapes needed a parser to enumerate. Two over-claims in the rewritten Problem
section: "measured gap, not inferred" is backwards and mixes step against job units, and
"six hours" is unobserved (#223 was human-cancelled at 30m21s). Property 3 has no
mutation behind it while properties 1 and 4 do.
Assumption: whether GitHub's runner *errors* on the key or *silently ignores* it — the
two need opposite fixes, and silently-ignored is worse because the guard would then be
satisfiable but false.
Disposition: **Addressed**, except the mutation for property 3, which is **Accepted**:
under the reduced guard the empty-file-list case is one assertion in a bats file and
adding a third mutation is Phase 2 work, not spec work. The quoted-key finding was
reproduced independently before acting on it. Both over-claims corrected in the body. The
assumption is **made moot** rather than settled — with no `uses:` branch, neither runner
behaviour changes anything, so no throwaway push is required.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.
