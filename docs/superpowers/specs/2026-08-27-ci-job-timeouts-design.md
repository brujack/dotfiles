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

**Durability: nothing mechanical. This was decided against, on measurement.**
Seven YAML lines change nothing about the next job someone adds, and the file reached
0 of 7 by accretion rather than by decision — so a guard test was specified across three
review rounds and then dropped. Measured over the population the decision governs, its
firing rate is **zero**, and every defect found in nine lens reports was inside it while
the seven lines drew none. Full reasoning, the three shapes its parser missed, and two
viable futures are under "What was considered and dropped" below.

What replaces it is honest disclosure rather than a mechanism: an eighth job added
without a cap will not be caught by anything, and that is stated in "What this does not
do" instead of being papered over by a check that reports clean on its own trigger class.

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

## What was considered and dropped: a guard test

Three review rounds specified a `tests/scripts/workflow_timeouts.bats` asserting that
every job in every tracked workflow declares `timeout-minutes`. It is **not** part of
this design. The reasons are recorded here rather than in the review log, because the
next person to have this idea should find them.

**Its firing rate over the population the decision governs is zero.** `ci.yml` went
2 -> 6 jobs between 2026-04-02 and 2026-04-27, `pr-title-lint.yml` added its single job
on 2026-05-17, and every `.github/` commit in the four months since edits steps inside
existing jobs — #243 added 42 lines to `auto-merge` as steps, not a job. A sweep of the
backlog finds **0 of 58** rows whose implementation would add one. An earlier estimate of
~0.4 firings/month was computed over all history including the bring-up burst, which is
the wrong reference class.

**A line-oriented matcher cannot enumerate YAML, and three rounds found three shapes it
misses.** A quoted key (`"deploy":`), a key with a trailing comment (`deploy: # …`), and
an inline flow job (`quick: {runs-on: …}`) are each invisible to `^  [^ ].*:$` while the
file still yields jobs and passes. Each was found in about ten seconds once someone
looked; there is no reason to believe the list is complete. Widening the character class
fixed instances, not the class — and the expected job-name set is derived by the very
matcher whose completeness is in question, which `behavior.md` names as a check that
cannot falsify its subject.

**Its failure mode is worse than its absence.** Because the expected set is pinned to
today's names, a new job the matcher cannot see leaves the derived set identical to the
pinned set: both assertions green, the uncapped job unreported. A gate that reports clean
on its own trigger class is a reason not to look.

**And an intent is not a mechanism.** A draft asserted three times that the guard
"asserts nothing about reusable-workflow jobs." No code did that. The matcher is
shape-blind, so a `uses:` job key matches like any other, enters the set, and gets
asserted on — recreating exactly the unsatisfiable state the sentence claimed to have
removed, now reached by silence rather than by a stated rule.

**Two futures, either of which would work**, recorded so this is a deferral with named
options rather than a rejection:

1. A real YAML front end (`pyyaml`) instead of `awk` — removing the whole class of
   matcher defects, at the cost of a dependency installed in **both** `test` and
   `bash-coverage`, since both run `make test` and `CLAUDE.md` records what a one-job
   install cost last time.
2. `actionlint` as a pinned, checksum-verified CI tool per `ci.md`. It validates
   workflows generally, subsumes this check entirely, and would catch defect classes
   this guard was never going to see.

Neither is in scope here. A backlog row carries this forward.

## Verification

- The seven values are declared and GitHub enforces them. There is nothing to test in
  this repo's suite: a `timeout-minutes` key is data read by the runner, not code.
- **What proves it works is a real timeout, which cannot be manufactured on demand.**
  Recorded as a limit rather than papered over with a test that would assert the string
  is present in a file — which is what the dropped guard reduced to.
- `make test` and `make lint` must stay green, which for a workflow-only change is a
  statement about not having broken anything else.

**Where a change like this is actually gated.** `scripts/pre-push:57` excuses
`^\.github/.*\.ya?ml$` from triggering the local suite, so a workflow-only change skips
`make test` locally and is checked by CI alone — in both `test` and `bash-coverage`.
Worth knowing before assuming a local green means anything here.

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
- **Nothing stops an eighth job being added with no cap.** This is the requirement the
  dropped guard existed to meet, and it is now unmet by design rather than by oversight.
  The bet is explicit: zero job additions in four months, zero backlog rows that would
  cause one, against a guard that produced every defect three review rounds found. If a
  job does get added uncapped, the failure is the same six-hour default this spec
  describes, and the backlog row names two mechanisms that would have caught it.

  **The bet's population is narrower than "will a job be added", and the gap is named
  rather than hidden.** What was counted is *changes originating in this repo*: 0 of 58
  dotfiles backlog rows, and 0 of 151 ai-config backlog rows, propose adding a CI job.
  But a fleet-wide tooling decision lands here as a per-repo PR with no backlog row in
  either place — and unadopted tooling of exactly that kind lives in **standards and
  specs**, which a backlog sweep cannot see. Two candidates exist today: `shfmt`, which
  `shell.md` records as specified and unadopted, and `actionlint`, named as a future in
  this spec's own dropped-guard section. Neither appears in any backlog. So the honest
  statement is that the counted population returned zero twice and is not the population
  that would falsify the bet — a complete count of the wrong set.

  Note the self-reference, because it is easy to read past: **this spec names `actionlint`
  as the future that "subsumes this check entirely", and adopting `actionlint` is exactly
  the change that would add a CI job here.** The bet's own stated escape hatch is the event
  most likely to falsify it.
- **It does not verify whether GitHub accepts job-level `timeout-minutes` on a
  reusable-workflow job.** SchemaStore says it is not an accepted key, independently
  derived twice; whether the runner *errors* or *silently ignores* is unsettled and
  needs a throwaway branch push nobody has made. With no guard, nothing in this repo
  depends on the answer — and that claim is now load-bearing enough to state carefully,
  because an earlier draft made it while a shape-blind matcher quietly did depend on it.

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

## Multi-Lens Review — Round 3

Reviewed at commit: `1c80ff1` (round-2 dispositions applied). Rounds 1 and 2 above are
history; these lenses were told so, and told the last change was a *subtraction* and to
look for what a subtraction breaks.

### Goal-Fit

Finding: Build the seven lines. The reduction's stated replacement for the withdrawn
mutation is factually wrong about the shape it claims to cover — a four-space `jobs:`
block trips neither fail-closed arm (those are trailing-content and tabs), so the parser
returns an empty set silently and the case is caught by the `>=1 job` assertion, not
"structurally". Correct outcome, wrong reason, and the wrong reason is what stops the
next reader checking. Verification is 4 PASS to 1 RED, and the single RED exercises only
the timeout assertion, so the two enumeration assertions added *because* vacuous truth
was the discovered defect ship unfalsified. The withdrawal was a false dichotomy: it
considered mutating the data (an untracked copy, correctly identified as invisible to
`git ls-files`) and never mutating the *checker* — break the anchor, confirm red. No
fixture, no seam, one line.
Assumption: that the harm window is genuinely unattended; the only observed incident was
noticed and cancelled by a human at 30m21s, n=1, so if the operator reliably notices
within ~30 minutes then `test: 20` and `bash-coverage: 25` buy nothing over the human
they replace and only `powershell: 5` beats the observed response.
Disposition: **Addressed by removal.** The guard is dropped, so the false justification,
the unfalsified assertions and the missing checker-mutation all go with it. The
assumption is **Accepted, reason: it argues against the guard, not the caps** — the caps
are seven lines whose worst case is one rerun, and "removing the need to notice" is worth
that whether or not a human usually notices at 30 minutes.

### Ergonomics

Finding: The reduced guard's only blocking assertion fires on the *correct* action —
adding an eighth job **with** a proper cap still goes red on set mismatch — and four
costs compound: no local feedback (`pre-push:57` excuses workflow YAML), two CI reds with
one misattributed as a coverage failure via `bash-coverage`'s red-suite guard (the #226
shape, already documented), a mandatory second round-trip because the remedy edit touches
`tests/` and re-arms the local suite, and no remedy in the message. Round 2's "state a
remedy" finding was marked Addressed but addressed only by deleting a different branch;
a grep for remedy language over the guard and verification sections returns 0. Half a
finding dispositioned as whole.
Assumption: that `jobs:` is the last top-level key in every workflow file — true today by
authoring order, not by design, and YAML mappings are unordered, so a trailing `env:` or
`concurrency:` would contribute phantom jobs. One-token fix (`/^[^ ]/{j=0}`).
Disposition: **Addressed by removal.** Every cost named is a cost of the guard. The
half-dispositioned remedy finding is recorded here as a process defect rather than
carried: marking a finding Addressed because an adjacent change made one of its instances
moot is how the other half survives.

### Risk

Finding: Dropping the `uses:` branch dropped the *detection*, not the coverage. The
matcher is shape-blind, so a reusable-workflow job key matches like any other, enters the
derived set, and the timeout assertion applies to it — the same unsatisfiable state round
2 removed, now undocumented and reached by silence. The spec's claim that it "asserts
nothing about `uses:` jobs" is implemented by no mechanism. Two further silent misses
found in one command: a trailing comment on a job key, and an inline flow job. Because
the expected set is pinned to today's names, a new job the matcher cannot see leaves the
derived set identical — both assertions green, uncapped job unreported, the guard's own
trigger class arriving fully green. The widening addressed the instance, not the class,
because the oracle is derived by the matcher whose completeness is in question. Verdict:
either give the parser a real YAML front end, or drop the guard and keep the seven lines.
Assumption: that GitHub's parser actually rejects job-level `timeout-minutes` on a
`uses:` job, rather than ignoring it — decides whether the shape-blind matcher is
harmless or a shipping blocker.
Disposition: **Addressed by removal**, which is this lens's own stated second option. The
three silent-miss shapes were reproduced independently before acting. The assumption
becomes genuinely moot once no guard exists — this time as a consequence of there being
no mechanism at all, rather than as an intent asserted over a mechanism that did the
opposite.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.

### Note on stopping

Three rounds, nine lens reports, 2,006,685 subagent tokens. Every round's fix produced
the next round's defect: round 1's hard-failure was unsatisfiable, round 2's widened
matcher was still incomplete and its `uses:` removal re-enrolled the jobs it claimed to
exempt, and round 3 found three more shapes in one command. That pattern is the argument
for the outcome rather than for a fourth round — the findings stopped being about a
fixable design and started being about the mechanism's fitness. The seven YAML lines drew
no defect in any round.
