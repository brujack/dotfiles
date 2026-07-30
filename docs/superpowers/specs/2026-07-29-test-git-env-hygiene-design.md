# Strip inherited git repo-location vars in BATS test setup

Date: 2026-07-29
Repo: dotfiles
Status: Spec

## Problem

The pre-push hook is broken for **every worktree push in this repo**, and has been since
2026-07-18. Measured on master at `f77a862`:

```
$ GIT_DIR="$(git rev-parse --absolute-git-dir)" make test
1..1058
91 not ok
make: *** [test] Error 1
```

Re-measured 2026-07-30 at `b9f8bf4` in a fresh local clone, with the leak injected the same
way: **90 not ok**, exit 2. Two differences from the original figure, one explained and one
not — see the failure-distribution table below. The defect and its shape are unchanged; only
the exact count moved.

Git exports `GIT_DIR` into the `pre-push` hook environment **only when pushing from a
worktree** (`git-workflow.md`'s measured table — a normal checkout exports nothing). The
hook runs `make test`. ~90 tests then fail because their _fixtures_ call `git init` and
`git -C … config`, and an inherited `GIT_DIR` overrides `-C` entirely.

A normal-checkout push exports nothing, so the hook passes there. CI passes for the same
reason. That is why this went unnoticed for 11 days despite worktrees being the documented
default workflow in `git-workflow.md`.

The practical effect is not a noisy hook — it is that **the local test gate is absent for
the standard workflow**. The only ways past it are `--no-verify` (which skips the whole
suite) or pushing from the main checkout (which, per `git-workflow.md`, tests whatever is
checked out there rather than the branch being pushed). Either way the gate stops
measuring the thing it exists to measure.

Discovered 2026-07-29 while pushing PR #190, which had to ship with `--no-verify`.

### Failure distribution

| Suite                                | `f77a862` | `b9f8bf4` (re-measured) | Landed              |
| ------------------------------------ | --------- | ----------------------- | ------------------- |
| `tests/setup_env/git_hooks.bats`     | 65        | 66                      | PR #189, 2026-07-28 |
| `tests/setup_env/git_sync.bats`      | 24        | 24                      | PR #182, 2026-07-18 |
| `tests/scripts/pre_commit_hook.bats` | 2         | **0**                   | earlier             |
| **total**                            | **91**    | **90**                  |                     |

`git_hooks.bats` 65 → 66 is explained: `4bb160b` (PR #190) touched that suite in between.

**`pre_commit_hook.bats` 2 → 0 is not explained, and it is load-bearing.** That file is
byte-identical since `f77a862` and still carries its fixture-only unset at line 12, yet its
two failures did not reproduce in a fresh clone — with git hooks installed or not, run
standalone or inside the full suite. Those two failures are the sole evidence for the
"coverage is per-subshell" half of the analysis below and for one named Testing bullet.
Until the discrepancy is resolved, treat that half as **unverified**: the environmental
difference between the original measurement and the reproduction has not been identified,
so it is unknown whether the original 2 were a genuine per-subshell leak or an artifact of
the measuring environment. Resolving it is a prerequisite for the implementation plan, not
an optional follow-up — the fix is the same either way, but the spec should not carry an
argument it cannot reproduce.

## Adjacent drift: fifteen hand-copied unsets, all missing the same variable

> **Scope note.** Two review rounds established that this section describes _drift_, not the
> defect. It causes no failure today; the fix in Decisions 1-2 does not depend on it, and
> cleaning it up changes no verdict. It stays here because it is the reason the leak went 11
> days undiagnosed and because it is the content of the follow-up hygiene spec — not because
> it is in scope. Read what follows as background.

Six BATS files create git repositories. Their `GIT_*` hygiene, counted:

| File                                  | Sources `common.bash` | `unset` copies   | Unsets in test bodies | Failing |
| ------------------------------------- | --------------------- | ---------------- | --------------------- | ------- |
| `tests/setup_env/git_hooks.bats`      | yes                   | 0                | —                     | **65**  |
| `tests/setup_env/git_sync.bats`       | yes                   | 0                | —                     | **24**  |
| `tests/scripts/pre_commit_hook.bats`  | no                    | 1 (fixture only) | **no**                | **2**   |
| `tests/scripts/pre_push.bats`         | no                    | 3                | yes                   | 0       |
| `tests/scripts/unit.bats`             | yes                   | 4                | yes (2)               | 0       |
| `tests/setup_env/update_summary.bats` | yes                   | 7                | yes (4)               | 0       |

**15 hand-copied `unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE` lines across four files. Every
one of them omits `GIT_COMMON_DIR`.**

Two independent defects. The first explains the bulk of the failures; the second is latent
across the whole suite.

**1. Coverage is per-subshell and incomplete.** The 89–90 failures in `git_hooks.bats` and
`git_sync.bats` are files with no unset anywhere — this part reproduces exactly and is not
in question. The per-subshell claim rests on the other 2: `pre_commit_hook.bats` unsets in
its fixture subshell but **not in its test bodies**, so the hook under test inherits the
leak. **Those 2 did not reproduce at `b9f8bf4`** (see the distribution table), so this
mechanism is currently asserted rather than measured, even though the code shape it
describes is plainly present in the file. The three files that do unset in their test
bodies (`pre_push.bats`, `unit.bats`, `update_summary.bats`) pass today for exactly that
reason — they are not correct, they are lucky in the right places. That last point stands
independently of the discrepancy: it is a claim about why they pass, not about a failure.

**2. All 15 copies omit `GIT_COMMON_DIR`.** The `git_env.py` story repeating: five
hand-rolled copies in ai-config had already drifted to two different variable sets, none
including `GIT_INDEX_FILE`. Here 15 copies drifted to the same wrong set, all missing the
one var that — measured during PR #190 — redirects `git rev-parse --git-path hooks` exactly
as `GIT_DIR` does. No test fails from this omission alone today, which is precisely why it
survived 15 copies.

The per-subshell shape makes this a placement question, not a var-list question. In
`tests/scripts/pre_commit_hook.bats`, the unset sits _inside_ `setup()`'s fixture-building
`bash -c` string:

```bash
setup() {
  bash -c "
    export PATH='${CLEAN_PATH}'
    unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE   # cleans ONLY this subshell
    git -C '${REPO_DIR}' init --quiet
  "
}

@test "pre-commit-hook.sh exits 0 when lint passes and ggshield is absent" {
  run bash -c "export PATH='${CLEAN_PATH}'; cd '${REPO_DIR}' && bash '${REPO_ROOT}/scripts/pre-commit-hook.sh'"
}
```

Each `@test` body is a _separate_ child of the bats process, which still carries the leak.
Adding `GIT_COMMON_DIR` to that line would **not** fix the two failing tests — the var they
inherit does not come from the fixture subshell. Fixing it in place would mean adding an
unset to every `run bash -c` in the file: a 16th, 17th and 18th copy. That is what rules
out the obvious "patch each file's variable list" approach — the copies are the defect, not
their contents.

## Decisions

| #   | Decision                                                                                                                                                         | Rationale                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| --- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | **The whole fix is one `unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE` in `scripts/pre-push`, before `make test`.** Nothing else ships in this spec. | `scripts/pre-push:32` is the only place in this repo that runs the suite under an environment git populates — verified: `.github/workflows/ci.yml:21` runs bare `make test`, `scripts/pre-commit` never runs tests, and `git-workflow.md`'s measured table records that bisect and `rebase --exec` export nothing. One line at that boundary immunises all 1058 current tests **and** every future test file, including files that never source a helper. Two earlier drafts of this spec built a per-file mechanism instead (a shared `unset` in `tests/helpers/common.bash`, 15 hand-copy deletions, a guard test, a CI step); a second review round established that none of them can fire in an environment this decision does not already cover, so they are hygiene, not the fix, and are priced as hygiene in Out of scope. |
| 2   | All four variables, not just `GIT_DIR`                                                                                                                           | `GIT_COMMON_DIR` was measured during PR #190 to redirect `--git-path hooks` identically to `GIT_DIR`. `GIT_INDEX_FILE` is exported **relative** by `pre-commit` (`git-workflow.md`), so it follows a subprocess by cwd — the nastiest of the four, and the one every existing hand-copy omitted. Matches the idiom already used four times in `lib/git_hooks.sh`. Only `GIT_DIR` is measured to cause failures today; the other three cost nothing and close the drift the 15 hand-copies demonstrate.                                                                                                                                                                                                                                                                                                                             |
| 3   | No change to `tests/helpers/common.bash`, no deletion of the 15 hand-rolled unsets, no guard test, no CI step                                                    | Each was proposed and then withdrawn. The 15 copies are real drift and the `GIT_COMMON_DIR` omission is real, but the spec concedes that omission causes no failure today — so removing them changes no verdict anywhere. The guard and the CI step existed only to detect a regression in the per-file mechanism, which is no longer being built. Keeping them would mean shipping a detector for a mechanism that is not in the change, plus a second full-suite CI run (measured: `test` 3m52s today, ~7m45s with it, on the `auto-merge` critical path) to verify a condition Decision 1 makes unreachable.                                                                                                                                                                                                                    |
| 4   | No change to anything under `lib/`                                                                                                                               | The production functions already strip correctly (`lib/git_hooks.sh` does it four times). Only fixture and test-body code was ever exposed.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |

## Design

The entire change is one line in one file.

### `scripts/pre-push`

Strip the four vars immediately before the `make test` invocation, at the one point where
they enter this repo's test suite:

```bash
# Git exports GIT_DIR into this hook's environment when the push originates
# from a worktree (git-workflow.md's measured table). Everything below runs
# `make test`, and any suite building a git fixture inherits the leak --
# including suites that never source tests/helpers/common.bash.
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE
```

Placement: after the hook's own `REPO_ROOT` / `merge-base` / `diff` resolution, so it does not
disturb the hook's git calls or its worktree-compat requirement — but before `make test`.

`make install-hooks` uses `ln -sf`, so this takes effect without a reinstall, and linked
worktrees share `.git/hooks` with the main checkout. That is worth stating because the global
standards warn that installed hooks are copies; for this repo they are symlinks, verified.

## Testing

One behaviour, one test, plus the measurement that proves the fix is sufficient.

**The test:** `tests/scripts/pre_push.bats` gains a case asserting the hook clears all four
variables before invoking `make test` — not merely that `make test` is invoked. It must fail
with the `unset` line removed.

**The measurement**, already taken in a fresh clone at `b9f8bf4`:

| Check                                                     | Before (measured)   | After (measured)       |
| --------------------------------------------------------- | ------------------- | ---------------------- |
| `GIT_DIR="$(git rev-parse --absolute-git-dir)" make test` | 90 `not ok`, exit 2 | **0 `not ok`, exit 0** |
| `make test` (clean env)                                   | 1058 pass           | 1058 pass              |
| Real worktree push, hook enabled, no `--no-verify`        | fails               | succeeds               |

The After row is the load-bearing one: it confirms no second cause hides behind the leak, so
the fix restores the gate rather than reducing noise. Residual failure list: empty. Note the
measurement applied the `unset` in `common.bash` rather than in `scripts/pre-push` — the
boundary strip is a strict superset of what was measured, since every suite that inherits from
the hook also inherits from the helper, so the result transfers.

**Two open items the implementer must settle first** — both cheap, and both about whether the
measurement above used a faithful leak:

1. **The leak shape.** `--absolute-git-dir` yields a _plain_ gitdir; the real leak is
   `GIT_DIR=<main>/.git/worktrees/<name>`, which resolves `--git-common-dir`,
   `--show-toplevel` and index location differently. Re-run the Before/After with a real
   worktree gitdir (`git worktree add /tmp/wt-probe -b probe-env`, then point `GIT_DIR` at
   `<main>/.git/worktrees/wt-probe`) and confirm the counts hold.
2. **The `pre_commit_hook.bats` 2 → 0 discrepancy.** Its two failures did not reproduce at
   `b9f8bf4` under an injected plain `GIT_DIR`, with hooks installed or not, standalone or in
   the full suite, and the file is byte-identical since `f77a862`. Item 1 is the most plausible
   explanation — run it first and check whether those two return under the worktree gitdir. If
   they do, the mystery is closed and the per-subshell argument in the body is restored; if not,
   delete that argument rather than shipping an unreproducible claim.

Run any manual leak reproduction against a scratch repo or the probe worktree, **not** against
the live checkout: `git_hooks.bats:846-900` documents by name that under a leaked
`GIT_DIR`/`GIT_COMMON_DIR`, `install_git_hooks_all_repos` writes hooks into the leaked repo.

Coverage: `scripts/pre-push` is already covered by `tests/scripts/pre_push.bats`. The 90% floor
is unaffected.

## Out of scope

- **The `--no-verify` push on PR #190** — already merged; this spec prevents recurrence rather
  than revisiting it.
- **The 15 hand-copied unsets and their missing `GIT_COMMON_DIR`.** Real drift, and the
  `git_env.py` story repeating — but it causes no failure today, so removing it changes no
  verdict. It is a hygiene change and belongs in its own spec, priced as hygiene, alongside the
  `pre_commit_hook.bats`/`pre_push.bats` sourcing question and any shared `unset` in
  `tests/helpers/common.bash`. Do not bundle it here: two review rounds established that
  bundling it is what made this spec look like a fix when most of it was cleanup.
- **A guard test and a leaked-env CI step.** Both existed to detect regressions in the per-file
  mechanism above. With that mechanism out of scope, they have nothing to guard. If the hygiene
  spec ships the shared helper `unset`, it should carry a leak-injected guard — and if it adds
  a CI pass, scope it to the four affected suites (~70s) rather than a second full `make test`
  (~3m52s, on the `auto-merge` critical path), and name the job so it lands inside
  `auto-merge`'s `needs:` list.
- **A shared `git_env`-style helper for shell**, mirroring ai-config's `git_env.py`. Nothing to
  share until the hygiene spec consolidates the copies.

## Related

- PR #190 — where this surfaced; shipped with `--no-verify` under this exact condition
- PR #189 / PR #182 — introduced the two largest affected suites
- `git-workflow.md` — the measured table of which vars git exports into which hook
- `ai-config/.claude/scripts/git_env.py` — the same drift, already solved once in Python

## Multi-Lens Review

Reviewed at commit: `d4cb265` (Step 7 self-review commit, before Step 8 dispatch)

### Goal-Fit

Finding: The guard test (Decision 4) is vacuous in every environment that actually runs
it, so the change ships with no durable detector for the defect it exists to prevent.
`[ -z "${GIT_DIR:-}" ]` is already true in a clean shell, so under local `make test`,
under the CI `test` job, and under a normal-checkout pre-push, the guard passes
identically whether or not the `unset` line exists in `common.bash`. It can only fail
under a worktree pre-push — the one environment no automated consumer runs. Applying the
reads-it test: the consumer is `make test`'s exit code, but no verdict in CI or on any
normal push can differ because the guard exists, and nothing carries its result past the
session. This is the vacuous-`grep -q` pass class the repo's own BATS pitfalls doc names.

Two secondary consequences of the same gap. First, Decision 4's stated rationale ("the
next git-fixture suite that skips `common.bash` silently reintroduces this") is not what
the guard does — a new `.bats` file that doesn't source `common.bash` leaks, and the
guard, living in a file that does source it, still passes. That vector is live:
`pre_push.bats` and `pre_commit_hook.bats` are two of six git-fixture files that don't
source it today. Second, the reason this went 11 days undetected is that nothing in the
pipeline ever runs the suite under a leaked `GIT_DIR`; the spec fixes the symptom and
leaves that blind spot unchanged.

The proportionate fix is cheaper than the guard, not more expensive: make the leak a
tested condition rather than an asserted-empty variable — either a CI step re-running a
representative subset with `GIT_DIR="$(git rev-parse --absolute-git-dir)"` exported (the
command already appears in the spec's Problem section), or a meta-test enumerating
`.bats` files containing `git init` and asserting each loads `common.bash`. Either
changes a verdict and leaves a record; the proposed guard does neither.

Everything else is well-sized and shippable as-is. Verified independently: the 15 copies
(1/3/4/7 across the four named files) and the two `common.bash` sourcing idioms both
match the spec's counts.

Assumption: That some environment which routinely runs `make test` actually exports these
variables — specifically that `GIT_COMMON_DIR` and `GIT_WORK_TREE` are ever exported at
all. `git-workflow.md`'s measured table states git exports only `GIT_DIR` from `pre-push`
(worktree case) and only a relative `GIT_INDEX_FILE` from `pre-commit`, and says
explicitly that `GIT_WORK_TREE` and `GIT_COMMON_DIR` are not exported by either hook.
Decision 2 justifies `GIT_COMMON_DIR` on a different fact — that it redirects
`--git-path hooks` when set — which is about effect, not exposure. If the vars are never
exported by any real workflow, two of the four guard assertions can never fail under any
condition. Settle it by running, from a worktree in this repo, a throwaway
`.git/hooks/pre-push` containing `env | grep '^GIT_' >&2` and pushing; then the same for
`pre-commit`; then `grep -rn 'GIT_DIR\|GIT_COMMON_DIR' .github/workflows/`.

Disposition: **Addressed.** Decision 4 was rewritten from an ambient assertion to a
leak-injected guard plus a CI step that runs the suite under a leaked `GIT_DIR`, so the
property now has a verdict in an automated consumer. Decision 5 was reversed to add the
`scripts/pre-push` boundary strip, which covers the new-suite-skips-the-helper vector the
guard cannot reach. Assumption not separately probed: `git-workflow.md`'s measured table
already records that `GIT_WORK_TREE` and `GIT_COMMON_DIR` are not exported by either hook,
and the re-measurement confirms `GIT_DIR` alone accounts for all ~90 failures — so the
four-var list is cheap insurance rather than necessity. No change implied either way.

### Ergonomics

Finding: The guard test can't fire in any environment where it will actually be run, so
day-to-day feedback is unchanged — the only thing that still surfaces a regression is the
same failed worktree push with 91 mystery failures the spec exists to eliminate. Verified:
`.github/workflows/ci.yml`'s `test` job runs bare `make test` with nothing exported, and a
developer's terminal is the same. The spec states its own acceptance criterion as "must be
verified to fail when the unset line is removed" and calls a guard that passes either way
"worthless", then specifies a guard that passes either way everywhere except the one
context nobody runs deliberately.

Two consequences on this lens. Wrong trigger: Decision 4's stated purpose is not served at
all, because the guard lives in a file that does source `common.bash`, so a new suite that
skips it leaves the guard green by construction — the next person hits the identical
11-day-invisible failure. And the real check is a manual ritual:
`GIT_DIR="$(git rev-parse --absolute-git-dir)" make test` appears only as a row in the
Testing table, not as a Makefile target, a CI step, or a line in `scripts/pre-push`. A
one-off command in a merged spec document is not a mechanism anyone re-runs six months on.

The cheap fix costs nothing in daily friction: make the guard self-polluting
(`run env GIT_DIR=/tmp/x GIT_COMMON_DIR=/tmp/x GIT_INDEX_FILE=x bash -c 'source
common.bash; ...'` asserting they are gone), and add one CI step running `make test` once
with the four vars exported. That converts both failure modes into a red check on the PR
that introduces them. As specified, feedback arrives at push time, in a worktree, as an
unattributed wall of failures.

Deliberately not raised: the `tests/helpers/env_hygiene.bats` location is fine
(`bats --recursive tests/` picks it up, and CI's `grep -r "^@test" tests/` counts it
toward the ≥840 floor); both sourcing idioms place the unset before any fixture work in
all six affected files; and losing the visible per-file `unset` for an implicit side
effect of sourcing is a readability trade the in-file comment adequately covers.

Assumption: That all 91 failures share this single cause — i.e. that unsetting the four
vars takes the polluted-env run from 91 `not ok` to 0. The spec measures the Before column
and says "the before-state is measurable today, so no prediction is required", but the
After column is asserted, not measured, and it is exactly the half that could not be
measured yet. If even a handful of the 91 fail for a second reason under a leaked
`GIT_DIR` (a fixture that legitimately resolves `--show-toplevel`, a cascade from an
earlier failure), the one-line change does not restore the gate. Settled in under a minute
without writing any of the rest of the spec: add the single `unset` line to
`tests/helpers/common.bash` in a scratch checkout and run
`GIT_DIR="$(git rev-parse --absolute-git-dir)" make test` — the failure count is the
answer, and if it isn't zero, the residual list is the real scope.

Disposition: **Addressed.** The assumption was checked exactly as prescribed and
**confirmed**: in a fresh clone at `b9f8bf4`, `GIT_DIR=<leak> make test` gives 90 `not ok`
before and **0 `not ok`, 1058 pass, exit 0** after the single `unset` line — empty residual
list, so there is no second cause. The Testing table now records both columns as measured
rather than one as asserted. The check also surfaced something the lens did not predict: the
Before figure is 90, not 91, and the per-suite split moved from 65/24/2 to 66/24/**0**. The
`git_hooks.bats` +1 is explained by `4bb160b`; the `pre_commit_hook.bats` 2 → 0 is not, and
that file is byte-identical since `f77a862`. Its two failures are the sole evidence for the
"coverage is per-subshell" argument, so that argument is now flagged unverified in the body
and resolving the discrepancy is a prerequisite for the plan. The guard and ergonomics
findings are addressed under Goal-Fit's disposition.

### Risk

Finding: The spec fixes the leak everywhere except where it enters, and its named safety
net cannot detect the regression it is specified to detect.

Decision 5 rejects the only boundary fix. The leak has exactly one entry point into this
repo's test suite: `scripts/pre-push` runs `make test` under an environment git populated.
A single `unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE` before `make test` in
`scripts/pre-push` (or in the Makefile `test` target) immunises all 1058 current tests and
every future test file, including files that never source `common.bash`. The spec's
rationale — "adding a strip there too would guard a mechanism with no remaining failure
mode" — is circular: the remaining failure mode is precisely the
new-suite-skips-`common.bash` case Decision 4 exists to catch. The chosen design converts
a one-line boundary fix into permanent per-file discipline across 26+ test files, and the
symptom of that discipline lapsing is unchanged.

The guard test is vacuous outside the environment that already fails loudly. Each `.bats`
file executes in its own process; `unset` in `env_hygiene.bats` has no effect on, and no
visibility into, a sibling suite that does not source `common.bash`. A future
`git_fixture_v2.bats` that skips it will leak exactly as `git_hooks.bats` does today, and
the guard will still pass green. The property is trivially machine-checkable — a CI step
or `make` target running `GIT_DIR="$(git rev-parse --absolute-git-dir)" make test`, the
exact command already in the Testing table — and that check would catch a new
non-sourcing suite. The spec runs it once and does not wire it in.

Explicitly not raised: the removal of the 15 inline unsets is low-risk — verified that
`common.bash` top level only computes `REPO_ROOT` via `cd`/`pwd`, not via git, so ordering
is safe, and neither `pre_commit_hook.bats` nor `pre_push.bats` calls `load_mocks`, so
their `CLEAN_PATH` mock exclusion is untouched. The blanket unset does not mask the
deliberate leak-simulation tests at `git_hooks.bats:373/387/865/893` — those set the var
per-command. And the change is not over-engineered; the defect is under-coverage at the
boundary, not excess machinery.

Assumption: That a top-level `unset` in `common.bash` is executed in the same process that
runs `setup()` and each `@test` body, on every bats version this repo runs. If bats sources
the test file in a discovery/preprocess pass separate from per-test execution, the unset
lands in the wrong process and the entire design silently does nothing — while the guard
test, which asserts about its own shell, could still pass. Genuinely uncertain because the
repo documents a version split (`shell.md`: CI is bats 1.10.0 via ubuntu apt, macOS is
1.13.0 via brew) and already has a CI-only-reproducing bash bug on record. Settle it by
probe, not by reasoning: write a throwaway `probe.bats` with a top-level `unset GIT_DIR`,
a `@test` asserting both `[ -z "${GIT_DIR:-}" ]` and `run bash -c '[ -z "$GIT_DIR" ]'`,
then run `GIT_DIR=/tmp/x bats probe.bats` locally and under
`docker run --rm --platform linux/amd64 ubuntu:24.04` with apt bats. Both must fail with
the unset removed and pass with it present, on both versions.

Disposition: **Addressed.** The Decision 5 half is accepted and the decision reversed —
`scripts/pre-push` now carries the boundary strip, and the rationale records why the earlier
"no remaining failure mode" reasoning was circular. The guard half is addressed by the
leak-injected form plus the CI step. The assumption was probed exactly as prescribed and
**refuted**: a top-level `unset` in a `.bats` file reaches the test body, `setup()`, and
`run bash -c` children on both bats 1.10.0 (ubuntu apt, `--platform linux/amd64`) and 1.14.0
(macOS brew) — 3/3 pass with the fix, 3/3 fail without, on each. No discovery-pass split
exists, so the "entire design silently does nothing" scenario is ruled out. Recorded in
Decision 1. One correction to the lens's premise: the local bats is 1.14.0, not the 1.13.0
`shell.md` documents — that file is stale, which is worth fixing separately but changes
nothing here.

Disposition:

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.

## Multi-Lens Review — Round 2

Re-run after the Round 1 dispositions were Addressed. Reviewed at commit: `dafff0c`. Fresh
subagents, told the section above is history rather than findings, and asked specifically for
defects the revision itself introduced. All three found one.

### Goal-Fit (round 2, `dafff0c`)

Finding: Reversing Decision 5 to add the `scripts/pre-push` strip made most of the rest of the
spec unnecessary, and the spec was not re-sized to match. Verified: `scripts/pre-push:32` is
the only place in this repo that runs the suite under an environment git populates —
`.github/workflows/ci.yml:21` runs bare `make test`, `scripts/pre-commit` never runs tests,
and `git-workflow.md`'s table says bisect/rebase-exec export nothing. Decision 5 alone
restores the gate for every current and future test. Reads-it test on the remainder: Decision
1's only remaining consumer is the CI step this spec itself invents (self-referential);
Decision 3 (15 deletions plus a shared source line into the two files most at risk from one)
changes no verdict anywhere and the spec concedes the `GIT_COMMON_DIR` omission causes no
failure today; Decision 4 guards Decision 1, which Decision 5 already covers. The claims
"Keep both — they fail independently" and "Neither subsumes the other" are unsupported: no
named environment has Decision 1 firing where Decision 5 does not. The proportionate spec is
Decision 5 plus its Testing bullet — everything else is hygiene and should be priced as
hygiene. Secondary: making the `pre_commit_hook.bats` discrepancy a plan prerequisite while
stating "the fix is the same either way" blocks on an investigation that cannot change design,
scope, or acceptance.

Assumption: That `GIT_DIR=… make test` returns 0 failures **inside CI's environment**, not
just a local fresh clone. The CI step is now the only thing making Decisions 1 and 4
non-decorative, and `auto-merge` depends on `test` — so if it is red for any
environment-specific reason, every PR in this repo is blocked. CI uses `actions/checkout`
(detached HEAD, possibly shallow), where `--absolute-git-dir` and fixture behaviour are not
obviously identical. Settle with the Docker recipe from `shell.md`, on a detached HEAD, with
the `unset` applied — it must exit 0.

Disposition: **Addressed — the finding is accepted in full and the spec cut to match.** The
`scripts/pre-push` strip is now the whole fix (Decision 1). The `common.bash` unset, the 15
deletions, the guard test and the CI step are all out of scope, moved to a follow-up hygiene
spec and explicitly priced as hygiene. The claims "Keep both — they fail independently" and
"Neither subsumes the other" are deleted; they were unsupported, and no environment was ever
produced where the helper fires and the hook does not. The `pre_commit_hook.bats` prerequisite
is demoted from a plan gate to one of two implementer items, tied to a specific hypothesis
(the leak shape) rather than left as an open mystery.

The assumption is **moot as stated** — with the CI step withdrawn, there is nothing whose
redness could block every PR. Its underlying question survives in a smaller form and is
recorded as implementer item 1: the measurement used a plain gitdir, and a worktree gitdir may
behave differently.

### Ergonomics (round 2, `dafff0c`)

Finding: The new CI step re-runs the **entire** 1058-test suite plus its `lint` prerequisite a
second time on every PR, in a repo whose local-hook design exists "to conserve GitHub Actions
minutes." Measured, not estimated: the full suite is 7m24s locally; in CI run 30505166422 the
`test` job took 3m52s and `bash-coverage` 5m37s, and `auto-merge` gates on both. Doubling
`test` to ~7m45s makes it the new critical path — every PR waits ~2 min longer to auto-merge,
forever, and burns ~4 extra Actions minutes, to re-verify a condition Decision 5 already makes
unreachable on the developer's actual path. The spec's own failure table says all 90 leaked-env
failures live in three files; a scoped second pass —
`GIT_DIR=… bats tests/setup_env/git_hooks.bats tests/setup_env/git_sync.bats tests/scripts/pre_commit_hook.bats tests/scripts/pre_push.bats`
— took **70s** locally for all four and detects the identical regression class, while skipping
the pointless second `lint` sweep. Round 1 correctly demanded the property get an automated
verdict; the correction reached for the biggest available hammer rather than the cheapest.
Second: the YAML snippet is a bare step naming no job. Read as a new job rather than a step
appended to `test`, it lands outside `auto-merge`'s `needs:` list and becomes an advisory red X
that never blocks a merge — the vacuous-guard failure in a new shape.

Assumption: That the leaked-env pass gets wired somewhere `auto-merge` actually waits on. The
spec is silent and both readings are plausible. Settled by naming the job before dispatch, and
confirmed post-merge by `grep -n -A2 'auto-merge:' .github/workflows/ci.yml` showing the
containing job in `needs:`.

Disposition: **Addressed by removal.** The CI step is withdrawn entirely, so neither the
doubled runtime nor the unnamed-job hazard can occur. Both measurements are carried forward
into Out of scope as constraints on the follow-up hygiene spec should it want a leaked-env
pass: scope it to the four affected suites (~70s measured) rather than a second full
`make test` (`test` 3m52s in CI run 30505166422, on the `auto-merge` critical path), and name
the job so it lands inside `auto-merge`'s `needs:` list. Recording those there rather than
discarding them is the point — the next spec should not have to re-derive them.

The assumption is moot for this spec and preserved as a requirement on the next one.

### Risk (round 2, `dafff0c`)

Finding: The one automated detector the revision adds injects a leak narrower and structurally
different from the real one, so the fix's blast-radius-bearing parts stay untested. Three
defects in that single YAML step, which after Decision 5 is the only place any real consumer
runs the suite under a leak:

1. **It injects one of four variables.** Strip `GIT_COMMON_DIR` from `common.bash` and the step
   stays green — yet Decision 2's whole case is that `GIT_COMMON_DIR` and the relative
   `GIT_INDEX_FILE` are the dangerous, universally-omitted ones. The spec's own Testing bullet
   demands asserting under a leaked `GIT_COMMON_DIR` specifically; the design does not deliver
   it.
2. **Wrong leak shape.** `git rev-parse --absolute-git-dir` yields a _plain_ gitdir. The real
   leak is `GIT_DIR=<main>/.git/worktrees/<name>` — a linked-worktree gitdir, which resolves
   `--git-common-dir`, `--show-toplevel` and index location differently. The reproduction that
   produced the After column used the plain shape in a fresh clone; the original 91-failure
   measurement came from a real worktree push. **That is the most plausible unexamined
   explanation for the `pre_commit_hook.bats` 2 → 0 discrepancy** the spec flags as an
   unresolved mystery.
3. **It aims a live leak at the working repo.** `git_hooks.bats:846-900` documents by name that
   under a leaked `GIT_DIR`/`GIT_COMMON_DIR`, `install_git_hooks_all_repos` writes hooks into
   the leaked repo. Contained on a runner, but the same command appears twice in the spec as a
   thing to run, and locally the target is the developer's real `dotfiles/.git`. A scratch repo
   or a linked worktree's gitdir gives better fidelity at zero blast radius.

This lens explicitly disagrees with round 2's Goal-Fit: it calls Decision 5 "not redundant
machinery — the cheapest part of the design." Checked and dismissed: `make install-hooks` uses
`ln -sf`, so Decision 5's edit takes effect without reinstall and linked worktrees share
`.git/hooks`; the 15-copy count, the 6-file table, both sourcing idioms and the identical
`REPO_ROOT` in `pre_push.bats`/`pre_commit_hook.bats` all verify; the blanket unset does not
disarm the leak-simulation tests at `git_hooks.bats:373/387/865/893`.

Assumption: That `GIT_DIR=<plain .git>` is a faithful proxy for `GIT_DIR=<main>/.git/worktrees/<name>`.
Every measurement in the current body — the 90 Before, the 0 After, "residual failure list:
empty" — used the plain shape, and the CI step perpetuates it as the permanent gate. If the
shapes are not equivalent, the After column proves nothing about the condition the hook
actually faces. Settle before implementing: `git worktree add /tmp/wt-probe -b probe-env`, then
in a scratch checkout at `b9f8bf4` run `make test` under
`GIT_DIR=<main>/.git/worktrees/wt-probe` with and without the `unset`, and compare the
per-suite split — specifically whether `pre_commit_hook.bats` contributes 2.

Disposition: **Addressed.** Defects 1 and 3 are moot — the CI step is withdrawn, so there is
no detector injecting one of four variables and no command in this spec aimed at the live
checkout. Defect 3's underlying warning is kept as an explicit instruction in Testing: run any
manual leak reproduction against a scratch repo or a probe worktree, citing
`git_hooks.bats:846-900` by name.

Defect 2 is the valuable one and is **promoted into the spec** as implementer item 1, together
with the hypothesis it implies: the plain-vs-worktree gitdir difference is the most plausible
explanation for the `pre_commit_hook.bats` 2 → 0 discrepancy, and item 2 now says so and tells
the implementer to run item 1 first. If the two failures return under the worktree gitdir the
mystery closes; if not, the per-subshell argument gets deleted rather than shipped
unreproducible.

This lens's disagreement with round 2's Goal-Fit — "Decision 5 is the cheapest part of the
design", against Goal-Fit's "Decision 5 makes the rest unnecessary" — is resolved in the same
direction by both: keep the boundary strip, drop the rest. The two lenses were arguing about
what to cut, not about what to keep.

Assumption **accepted as unresolved and made a blocking implementer item** rather than
dispositioned away. The After column was measured with a plain gitdir; until item 1 runs, it is
evidence about a proxy. The spec now says that in Testing rather than presenting the number as
final.

### Adversarial Spec Review (round 2)

N/A — unchanged; the revision introduced no comparison, evaluator, or ambiguous-criteria
component.
