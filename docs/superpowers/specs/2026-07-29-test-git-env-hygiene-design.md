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

## The real defect: fifteen hand-copied unsets, all missing the same variable

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

| #   | Decision                                                                                                                                                                                        | Rationale                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| --- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | A single top-level `unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE` in `tests/helpers/common.bash`, executed on `source` — not inside `load_mocks()` or `load_setup_env()`           | Top-level means it runs whenever the helper is sourced, in the shell that then runs `setup()` and the `@test` body — so every fixture subshell and every `run bash -c` child inherits a clean environment without needing its own unset. A function-scoped version would only help files calling that specific function (`load_setup_env`: 16 of 26 files; `load_mocks`: 20). The repo already uses two sourcing idioms — `load '../helpers/common.bash'` at file scope and `source "${REPO_ROOT}/tests/helpers/common.bash"` inside `setup()`. Both work here; do not normalise them as part of this change. **Verified 2026-07-30**, since the whole design rests on it: a probe `.bats` with a top-level `unset` and a polluted parent env passes 3/3 (test body, `setup()`, and `run bash -c` child all see the vars gone) and fails 3/3 with the unset removed — on **both** bats 1.10.0 (CI, ubuntu apt, `--platform linux/amd64`) and 1.14.0 (macOS brew). No discovery-pass/execution-pass split exists on either version. |
| 2   | All four variables, not just `GIT_DIR`                                                                                                                                                          | `GIT_COMMON_DIR` was measured during PR #190 to redirect `--git-path hooks` identically to `GIT_DIR`. `GIT_INDEX_FILE` is exported **relative** by `pre-commit` (`git-workflow.md`), so it follows a subprocess by cwd — the nastiest of the four, and the one every existing hand-copy omitted. Matches the idiom already used four times in `lib/git_hooks.sh`.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| 3   | Delete all 15 hand-rolled unsets; make `pre_commit_hook.bats` and `pre_push.bats` source `common.bash`                                                                                          | Leaving them is what allowed the drift. Sourcing is safe for both: `common.bash`'s top level only assigns `REPO_ROOT` (to the identical value both files already compute) and defines two functions. Neither file calls `load_mocks`, so the deliberate "exclude the git mock from PATH" behaviour in both is preserved — that exclusion is their own `CLEAN_PATH` logic, untouched.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| 4   | A **leak-injected** guard: a test that exports the four vars into a child, sources `common.bash` there, and asserts they are gone — plus one CI step running the suite under a leaked `GIT_DIR` | An earlier draft specified a guard that simply asserted `[ -z "${GIT_DIR:-}" ]` during a normal run. That is vacuous: those vars are already empty in a clean shell, so it passes identically whether or not the fix exists, in every environment that actually runs it — local `make test`, the CI `test` job, and a normal-checkout pre-push. It could only fail under a worktree pre-push, which no automated consumer runs, so no verdict anywhere could differ because it existed. Injecting the leak is what makes the guard fail when the fix is removed, and the CI step is what makes it run somewhere that reports a verdict. Both were confirmed workable by the bats probe in Decision 1, which is exactly this shape.                                                                                                                                                                                                                                                                                                 |
| 5   | **Also** strip the four vars in `scripts/pre-push` before `make test`                                                                                                                           | Reversed from an earlier draft that left the hook alone on the grounds that "once the tests are robust, the hook passes". That reasoning is circular: the failure mode it dismisses is the one Decision 4 exists to catch — a future git-fixture suite that never sources `common.bash`. `scripts/pre-push` is the single point where the leak enters this repo's test suite, so one `unset` there immunises all 1058 current tests **and** every future test file, including files that skip the helper. It is a boundary fix, not a redundant one: Decision 1 protects files that opt in, Decision 5 protects the ones that forget. Keep both — they fail independently.                                                                                                                                                                                                                                                                                                                                                         |
| 6   | No change to anything under `lib/`                                                                                                                                                              | The production functions already strip correctly (`lib/git_hooks.sh` does it four times). Only fixture and test-body code was ever exposed.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |

## Design

### `tests/helpers/common.bash`

Add at top level, after the `REPO_ROOT` assignment and before the function definitions:

```bash
# Git exports repo-location vars into hook environments -- GIT_DIR when pushing
# from a worktree, and a RELATIVE GIT_INDEX_FILE from pre-commit (see
# git-workflow.md's measured table). The pre-push hook runs `make test`, so any
# suite that builds a git fixture inherits them and every `git -C <fixture>`
# call silently operates on the leaked repo instead.
#
# Unset at TOP LEVEL, deliberately, not inside load_mocks/load_setup_env: it
# then runs in the same shell that runs setup() and the @test body, so every
# fixture subshell and every `run bash -c` child inherits a clean environment
# without needing its own unset. A `bash -c` block inside setup() cannot do
# this -- it only cleans itself, while each @test body is a separate child.
#
# All four vars, matching lib/git_hooks.sh: GIT_COMMON_DIR redirects
# `rev-parse --git-path hooks` exactly as GIT_DIR does (measured, PR #190),
# and it is the var every previous hand-rolled copy in tests/ omitted.
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE
```

### Removals

Delete all 15 now-redundant inline unsets: `pre_commit_hook.bats` 1, `pre_push.bats` 3,
`unit.bats` 4, `update_summary.bats` 7.

Several are embedded mid-string in `run bash -c "unset GIT_DIR …; export PATH=…; …"`
one-liners rather than on their own lines — delete only the `unset …;` clause there and
leave the rest of the command intact.

Add `load "${BATS_TEST_DIRNAME}/../helpers/common.bash"` (path adjusted per directory
depth) to `pre_commit_hook.bats` and `pre_push.bats`, which currently do not source it.
The other four already do.

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

This overlaps Decision 1 deliberately. The helper protects files that opt in; this protects
the ones that forget. Neither subsumes the other, and both are one line.

### Guard test

New file `tests/helpers/env_hygiene.bats` (or appended to an existing `tests/scripts/`
suite — implementer's call, one location). The guard must **inject the leak itself** rather
than assert on the ambient environment:

```bash
@test "sourcing common.bash strips inherited git repo-location vars" {
  run env GIT_DIR=/tmp/leak GIT_WORK_TREE=/tmp/leak \
          GIT_COMMON_DIR=/tmp/leak GIT_INDEX_FILE=leak-index \
      bash -c "source '${BATS_TEST_DIRNAME}/../helpers/common.bash'
               printf '%s|%s|%s|%s' \
                 \"\${GIT_DIR:-}\" \"\${GIT_WORK_TREE:-}\" \
                 \"\${GIT_COMMON_DIR:-}\" \"\${GIT_INDEX_FILE:-}\""
  [ "$status" -eq 0 ]
  [ "$output" = "|||" ]
}
```

Why injected rather than ambient: `[ -z "${GIT_DIR:-}" ]` is already true in a clean shell,
so an ambient assertion passes identically with or without the fix in every environment that
runs it — verified, `.github/workflows/ci.yml`'s `test` job runs bare `make test` with
nothing exported, and a developer's terminal is the same. The injected form fails when the
`unset` line is removed, which is the whole point; the bats probe recorded in Decision 1 is
this exact shape and does fail 3/3 without the fix.

The guard alone is still not sufficient, because it lives in a file that **does** source
`common.bash` — a future suite that skips the helper leaves it green by construction. Two
things close that, and the spec requires both:

- **Decision 5's `scripts/pre-push` strip** — covers files that never source the helper.
- **A CI step** running the suite once with the leak exported:
  ```yaml
  - name: Test under leaked git env
    run: GIT_DIR="$(git rev-parse --absolute-git-dir)" make test
  ```
  This is what gives the property a verdict somewhere automated. Without it, the check
  exists only as a command in a merged spec document, which nobody re-runs.

## Testing

The before-state is measurable today, and the after-state has now been measured too rather
than predicted — in a fresh clone at `b9f8bf4` with the single `unset` line applied:

| Check                                                     | Before (measured)   | After (measured)          |
| --------------------------------------------------------- | ------------------- | ------------------------- |
| `GIT_DIR="$(git rev-parse --absolute-git-dir)" make test` | 90 `not ok`, exit 2 | **0 `not ok`, exit 0**    |
| `make test` (clean env)                                   | 1058 pass           | 1058 pass + guard test    |
| Guard test with the `unset` line removed                  | n/a                 | must FAIL (injected form) |
| Real worktree push, hook enabled, no `--no-verify`        | fails               | succeeds                  |

The After row is the one that mattered: it confirms there is no second cause hiding behind
the leak, so the one-line fix fully restores the gate rather than merely reducing the noise.
Residual failure list after the fix: empty.

Also verify per `tdd.md`:

- **Both branches of the guard** — passes with the unset present, fails with it removed.
  Confirmed workable on bats 1.10.0 and 1.14.0 (Decision 1).
- **`pre_commit_hook.bats` and `pre_push.bats` still pass** after sourcing `common.bash` —
  specifically that their `CLEAN_PATH` git-mock exclusion still works, since that is the
  behaviour most at risk from adding a shared source line.
- **Resolve the `pre_commit_hook.bats` 2 → 0 discrepancy** before implementing. The two
  tests named in the original measurement (`exits 0 when lint passes and ggshield is
absent`, `runs ggshield with pre-commit args when present and lint passes`) did not fail
  at `b9f8bf4` under an injected `GIT_DIR`, with hooks installed or not, standalone or in
  the full suite. Identify the environmental difference, then assert the intended property:
  that they pass under a leaked `GIT_COMMON_DIR` specifically, not only under a leaked
  `GIT_DIR`.
- **`scripts/pre-push` strip is exercised** — a test that the hook clears the four vars
  before invoking `make test`, not only that `make test` is invoked.

Coverage: `tests/helpers/common.bash` is test infrastructure, not measured by
`scripts/run-bash-coverage.sh`'s `INCLUDE_FILES`. The 90% floor is unaffected.
`scripts/pre-push` is already covered by `tests/scripts/pre_push.bats`.

## Out of scope

- **The `--no-verify` push on PR #190** — already merged; this spec prevents recurrence
  rather than revisiting it.
- **A shared `git_env`-style helper for shell**, mirroring ai-config's `git_env.py`. With
  the four copies deleted and one authority left, there is nothing to share yet. Worth
  reconsidering only if a second non-`common.bash` consumer appears.

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
