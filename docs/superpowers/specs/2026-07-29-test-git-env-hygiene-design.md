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

Git exports `GIT_DIR` into the `pre-push` hook environment **only when pushing from a
worktree** (`git-workflow.md`'s measured table — a normal checkout exports nothing). The
hook runs `make test`. 91 tests then fail because their _fixtures_ call `git init` and
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

| Suite                                | Failures | Landed              |
| ------------------------------------ | -------- | ------------------- |
| `tests/setup_env/git_hooks.bats`     | 65       | PR #189, 2026-07-28 |
| `tests/setup_env/git_sync.bats`      | 24       | PR #182, 2026-07-18 |
| `tests/scripts/pre_commit_hook.bats` | 2        | earlier             |

## The real defect: fifteen hand-copied unsets, all missing the same variable

Six BATS files create git repositories. Their `GIT_*` hygiene, counted:

| File | Sources `common.bash` | `unset` copies | Unsets in test bodies | Failing |
| --- | --- | --- | --- | --- |
| `tests/setup_env/git_hooks.bats` | yes | 0 | — | **65** |
| `tests/setup_env/git_sync.bats` | yes | 0 | — | **24** |
| `tests/scripts/pre_commit_hook.bats` | no | 1 (fixture only) | **no** | **2** |
| `tests/scripts/pre_push.bats` | no | 3 | yes | 0 |
| `tests/scripts/unit.bats` | yes | 4 | yes (2) | 0 |
| `tests/setup_env/update_summary.bats` | yes | 7 | yes (4) | 0 |

**15 hand-copied `unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE` lines across four files. Every
one of them omits `GIT_COMMON_DIR`.**

Two independent defects. The first explains today's 91 failures; the second is latent
across the whole suite.

**1. Coverage is per-subshell and incomplete.** The 89 failures in `git_hooks.bats` and
`git_sync.bats` are files with no unset anywhere. The remaining 2 are subtler:
`pre_commit_hook.bats` unsets in its fixture subshell but **not in its test bodies**, so the
hook under test inherits the leak. The three files that do unset in their test bodies
(`pre_push.bats`, `unit.bats`, `update_summary.bats`) pass today for exactly that reason —
they are not correct, they are lucky in the right places.

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

| #   | Decision                                                                                                                                                                              | Rationale                                                                                                                                                                                                                                                                                                                                                                            |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 1   | A single top-level `unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE` in `tests/helpers/common.bash`, executed on `source` — not inside `load_mocks()` or `load_setup_env()` | Top-level means it runs whenever the helper is sourced, in the shell that then runs `setup()` and the `@test` body — so every fixture subshell and every `run bash -c` child inherits a clean environment without needing its own unset. A function-scoped version would only help files calling that specific function (`load_setup_env`: 16 of 26 files; `load_mocks`: 20). The repo already uses two sourcing idioms — `load '../helpers/common.bash'` at file scope and `source "${REPO_ROOT}/tests/helpers/common.bash"` inside `setup()`. Both work here; do not normalise them as part of this change. |
| 2   | All four variables, not just `GIT_DIR`                                                                                                                                                | `GIT_COMMON_DIR` was measured during PR #190 to redirect `--git-path hooks` identically to `GIT_DIR`. `GIT_INDEX_FILE` is exported **relative** by `pre-commit` (`git-workflow.md`), so it follows a subprocess by cwd — the nastiest of the four, and the one every existing hand-copy omitted. Matches the idiom already used four times in `lib/git_hooks.sh`.                    |
| 3   | Delete all 15 hand-rolled unsets; make `pre_commit_hook.bats` and `pre_push.bats` source `common.bash`                                                                              | Leaving them is what allowed the drift. Sourcing is safe for both: `common.bash`'s top level only assigns `REPO_ROOT` (to the identical value both files already compute) and defines two functions. Neither file calls `load_mocks`, so the deliberate "exclude the git mock from PATH" behaviour in both is preserved — that exclusion is their own `CLEAN_PATH` logic, untouched. |
| 4   | A guard test asserting all four variables are unset during a test run                                                                                                                 | Without it, the next git-fixture suite that skips `common.bash` silently reintroduces this, and the symptom is 91 unrelated failures visible only on a worktree push — which cost this session a failed push and a full bisect-by-hand to diagnose. The guard converts that into one named failure.                                                                                  |
| 5   | No change to `scripts/pre-push`                                                                                                                                                       | The hook's only action is `make test`. Once the tests are robust, the hook passes. Adding a strip there too would guard a mechanism with no remaining failure mode.                                                                                                                                                                                                                  |
| 6   | No change to anything under `lib/`                                                                                                                                                    | The production functions already strip correctly (`lib/git_hooks.sh` does it four times). Only fixture and test-body code was ever exposed.                                                                                                                                                                                                                                          |

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

### Guard test

New file `tests/helpers/env_hygiene.bats` (or appended to an existing `tests/scripts/`
suite — implementer's call, one location):

```bash
@test "test environment has no inherited git repo-location vars" {
  [ -z "${GIT_DIR:-}" ]
  [ -z "${GIT_WORK_TREE:-}" ]
  [ -z "${GIT_COMMON_DIR:-}" ]
  [ -z "${GIT_INDEX_FILE:-}" ]
}
```

This must be in a file that sources `common.bash`, and must be verified to **fail** when
the unset line is removed — a guard that passes either way is worthless, which is the
lesson from PR #190's fixture.

## Testing

The before-state is measurable today, so no prediction is required:

| Check                                                     | Before              | After                  |
| --------------------------------------------------------- | ------------------- | ---------------------- |
| `GIT_DIR="$(git rev-parse --absolute-git-dir)" make test` | 91 `not ok`, exit 2 | 0 `not ok`, exit 0     |
| `make test` (clean env)                                   | 1058 pass           | 1058 pass + guard test |
| Guard test with the `unset` line removed                  | n/a                 | must FAIL              |
| Real worktree push, hook enabled, no `--no-verify`        | fails               | succeeds               |

Also verify per `tdd.md`:

- **Both branches of the guard** — passes with the unset present, fails with it removed.
- **`pre_commit_hook.bats` and `pre_push.bats` still pass** after sourcing `common.bash` —
  specifically that their `CLEAN_PATH` git-mock exclusion still works, since that is the
  behaviour most at risk from adding a shared source line.
- **The two currently-failing `pre_commit_hook.bats` tests** (`exits 0 when lint passes and
ggshield is absent`, `runs ggshield with pre-commit args when present and lint passes`)
  pass under a leaked `GIT_COMMON_DIR` specifically, not only under a leaked `GIT_DIR`.

Coverage: `tests/helpers/common.bash` is test infrastructure, not measured by
`scripts/run-bash-coverage.sh`'s `INCLUDE_FILES`. The 90% floor is unaffected.

## Out of scope

- **`scripts/pre-push` itself** — no change needed (Decision 5).
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
