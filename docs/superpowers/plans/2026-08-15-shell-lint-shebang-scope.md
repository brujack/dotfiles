# Shebang-Derived Shell Lint Scope Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Derive `make lint`'s `SHELL_FILES` from first-line shebang instead of a filename pathspec, widening the gate from 35 to 100 tracked files.

**Architecture:** A new `scripts/list-shell-files.sh` emits every tracked file whose first line is a bash/sh shebang; the Makefile's `SHELL_FILES :=` calls it. The existing empty-list guard becomes the fail-closed path for a broken script. Eleven bats oracle cases pin the set from both directions — a name-derived oracle proves it is not too small, and an extensionless non-shell fixture proves it is not too large.

**Tech Stack:** bash, GNU make (3.81 and 4.x), shellcheck 0.11.0, bats-core, GitHub Actions.

**Spec:** [`2026-08-15-shell-lint-shebang-scope-design.md`](../specs/2026-08-15-shell-lint-shebang-scope-design.md) at `842ee7f`.

## Global Constraints

- Branch `feat/shebang-derived-lint-scope`, worktree `/Users/bruce/git-repos/personal/.worktrees/dotfiles-shebang-scope`. **All work happens there.**
- The interpreter pattern must require `/` or `env ` before `bash`/`sh`. A bare `'#!'*sh` matches `#!/usr/bin/env zsh` and `#!/usr/bin/env fish`. Verified against 11 shebang forms.
- `env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE` on **both** git calls in the script. `scripts/pre-push` runs `make test`, and git exports `GIT_DIR` into that hook from a worktree.
- `2>/dev/null` must **precede** the input redirect in the `read`. Bash applies redirections left to right; after the redirect it is inert and an unreadable file prints `Permission denied` at every make parse.
- `read` returns 1 at EOF-without-delimiter while populating the variable — the guard is `|| [[ -n "${first}" ]] || continue`, not a bare `|| continue`.
- `make lint` is the pre-commit hook and `test: lint` makes it pre-push. Never leave the tree in a state where `make lint` is red between tasks — this is why Task 1 precedes the widening.
- No hardcoded file counts in any acceptance gate. Current figures (100 files, 64 mocks) are context, not contracts.
- Do not touch `scripts/run-bash-coverage.sh`. The coverage denominator is a stated non-goal.

## Session-Level Verification

Beyond per-task gates, the whole change is proven by:

```bash
make test                                    # exit 0, no regression vs the 1334-test floor
make print-SHELL_FILES | tr ' ' '\n' | grep -c .     # 100, up from 35
make bash-coverage                           # figure unchanged — denominator untouched
```

Plus three mutations that must turn the suite **red**, run manually at Task 8:

1. Revert `tests/mocks/gpg`'s `_` back to `line` → `make lint` red.
2. Replace the script body with the equivalent pathspec → cases 5 and 11 red, 1–4/6–10 green.
3. Revert the `read` guard to bare `|| continue` → case 5's unterminated fixture red.

Mutation 2 is the load-bearing one: it is the only check that distinguishes this design from a one-line pathspec that produces the identical 100 files.

---

### Task 9 (prerequisite, spliced in after Task 1 blocked): Isolate PATH in the gnubin tests

```yaml-task
id: 9
description: Scrub PATH inside the two gnubin zsh -c invocations so they measure what 6_path.zsh adds rather than what the outer shell inherited
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: bats tests/zshrc.d/unit.bats
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - tests/zshrc.d/unit.bats
depends_on: []
```

**Why this exists.** Task 1 returned `blocker` on `make test`. Independent re-run showed the
failure is **pre-existing on master** — `bats tests/zshrc.d/unit.bats` fails tests 23 and 24 at
`a1cb22d`, with none of Task 1's changes. So `make test → exit 0`, which this plan put in all
eight tasks, **was never reachable**. That is a plan defect, not an implementation failure:
`writing-plans` requires running a gate's measuring command against the target while writing
the plan, and I did not run `make test` on base.

**The bug** is `tdd.md` pitfall A, test isolation. Both tests set
`_OVERRIDE_GNUBIN_ARM`/`_OVERRIDE_GNUBIN_INTEL` to nonexistent paths and then assert
`NO_GNUBIN`, but the `zsh -c` inherits the outer `PATH`; `6_path.zsh` runs `typeset -U path`,
which **unions** the already-present gnubin entry rather than dropping it. The test therefore
measures the contents of `path` rather than what the file under test *added*. It passes only
on a machine whose shell has no gnubin — which is every CI runner, and not this one.

`setup()` deliberately does not call `load_mocks()` because prepending to the outer `PATH`
corrupts it for zsh subprocesses; that comment is correct and must stay. The fix belongs
inside the two `zsh -c` bodies, not in `setup()`.

Add as the first line of each of the two `zsh -c` bodies (currently near lines 275 and 300):

```sh
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
```

Verify RED first: without the line, both tests fail on this machine; with it, both pass. Do
not weaken either assertion — `NO_GNUBIN` and the `${#path} -gt 0` check both stay.

**Leave It Better applies:** this blocks `make test`, which `scripts/pre-push` runs, so it
blocks pushing. Fixed in this PR and called out in the PR body rather than deferred.

**Interfaces:** Produces — a green `bats tests/zshrc.d/unit.bats`, making every other task's
`make test` gate reachable for the first time.

---

### Task 1: Fix the five shellcheck findings in tests/mocks

```yaml-task
id: 1
description: Suppress 4 SC2086 in tests/mocks/brew with reasons and fix 1 SC2034 in tests/mocks/gpg, before the widening exposes them
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: shellcheck tests/mocks/brew tests/mocks/gpg
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - tests/mocks/brew
  - tests/mocks/gpg
depends_on: [9]
```

**Why first:** these files are not linted today, so this is a no-op for the gate — but doing it before Task 3 means `make lint` is never red between tasks. `tdd: not-applicable` — no behaviour change; the existing `tests/setup_env/brewfile_drift.bats` is the regression test and must stay green.

**`tests/mocks/gpg` line 5** — `line` is written and never read; the loop only drains stdin:

```bash
while IFS= read -r _; do
```

**`tests/mocks/brew` lines 6, 11, 13, 19** — do **NOT** quote these. Word splitting is the mechanism: it renders `MOCK_BREW_LEAVES="bat git"` as `brew leaves`' one-per-line output. Quoting collapses it to one line and breaks `brewfile_drift.bats`. Add above each:

```bash
# shellcheck disable=SC2086 # word-splitting is the point: renders a space-separated list one-per-line, as real brew does
```

**Verified before planning:** base `shellcheck` exit 1 with exactly these 5 findings; after the fix exit 0; and `MOCK_BREW_LEAVES="bat git" bash tests/mocks/brew leaves` still emits two lines.

**Interfaces:** Produces — nothing consumed by later tasks; this is a precondition for Task 3's gate being green.

---

### Task 2: Add scripts/list-shell-files.sh with its bats suite

```yaml-task
id: 2
description: Create the shebang-derivation script and a bats suite covering accepted forms, rejected interpreters, and the unterminated-line-1 edge case
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: bats tests/scripts/list_shell_files.bats
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - scripts/list-shell-files.sh
  - tests/scripts/list_shell_files.bats
depends_on: []
```

**Write the tests first.** Each builds a fixture git repo in `BATS_TEST_TMPDIR`, commits, and runs the script with cwd inside it.

Required cases:

| fixture first line                                              | expect       |
| --------------------------------------------------------------- | ------------ |
| `#!/usr/bin/env bash`                                           | included     |
| `#!/bin/bash`                                                   | included     |
| `#!/bin/bash -e`                                                | included     |
| `#!/bin/sh`                                                     | included     |
| `#!/usr/bin/env sh`                                             | included     |
| `#!/usr/bin/env zsh`                                            | **excluded** |
| `#!/bin/zsh`                                                    | **excluded** |
| `#!/usr/bin/zsh -f`                                             | **excluded** |
| `#!/usr/bin/env fish`                                           | **excluded** |
| `#!/usr/bin/env python3`                                        | **excluded** |
| `# not a shebang`                                               | **excluded** |
| `#!/usr/bin/env bash` with **no trailing newline**, single line | **included** |
| empty file                                                      | excluded     |
| untracked file with a bash shebang                              | excluded     |

Then the script — exact body in the spec's Rule section. Three details are load-bearing and each has its own test above: the `/`-or-`env ` requirement, the `read` guard, and the `2>/dev/null` placement. Add `set -o pipefail` and an explicit non-zero exit if the `git ls-files` call fails, so a partial walk is a failure rather than a short list (Task 4 case 8 asserts exit 0).

**Interfaces:** Produces — `scripts/list-shell-files.sh`, executable (mode 755), emits one path per line relative to repo root, exit 0 on success and non-zero on any internal failure. Task 3 consumes it.

---

### Task 3: Wire SHELL_FILES to the script and fix the lint recipe's output

```yaml-task
id: 3
description: Point SHELL_FILES at the script, give bash -n a deferred one-line summary, and name the remedy in the empty-list guard
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: 'bash -c ''make print-SHELL_FILES | tr " " "\n" | grep -qx tests/mocks/brew'''
    exit_code: 0
  - cmd: 'bash -c ''make print-SHELL_FILES | tr " " "\n" | grep -qx config/local.sh.example'''
    exit_code: 0
  - cmd: make lint
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - Makefile
  - tests/scripts/makefile_lint_scope.bats
depends_on: [1, 2]
```

**Three edits to `Makefile`:**

1. `SHELL_FILES := $(shell ./scripts/list-shell-files.sh)` replacing the `git ls-files` pathspec. Leave `ZSH_FILES` and `BATS_FILES` alone.
2. The `lint` recipe's `bash -n` arm currently prints one line per file — 35 today, 100 after. Accumulate and print once, mirroring the shellcheck arm's shape. It is **not** a transplant: shellcheck takes the whole list in one invocation, `bash -n` takes one file, so this is a loop with deferred output. On failure keep naming the file; `bash -n` writes its own diagnostic to stderr, so only the `OK` chatter goes.
3. Extend the empty-list guard's message to name the **remedy**, not just a third cause: `chmod +x scripts/list-shell-files.sh`. `scripts/pre-commit-hook.sh:5` runs `make lint`, so an operator hitting this is locked out of committing the fix.

The two `grep -qx` gates are the discriminators: neither path is producible by the old pathspec. Both fail on base — verified, the current `SHELL_FILES` contains neither.

**Interfaces:** Consumes — `scripts/list-shell-files.sh` from Task 2. Produces — `make print-SHELL_FILES` emits 100 space-separated paths on one line (this shape matters for Task 5).

---

### Task 4: Add the eleven oracle cases

```yaml-task
id: 4
description: Add oracle cases pinning the derived set from both directions, including the extensionless non-shell fixture that separates this design from a pathspec
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: bats tests/scripts/makefile_lint_scope.bats
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - tests/scripts/makefile_lint_scope.bats
depends_on: [3]
```

Cases, per the spec's Test oracle section:

1. Name oracle is itself **non-empty**, derived through the existing `_git_ls_clean` helper so it carries the same four-variable `env -u` strip. Without this, case 2 is vacuous — `∅ ⊆ anything`.
2. Name oracle ⊆ `SHELL_FILES`.
3. `SHELL_FILES` non-empty; `make lint` exits non-zero when it is empty.
4. `SHELL_FILES` and `ZSH_FILES` disjoint, **both asserted non-empty first**.
5. The shebang-form matrix from Task 2, plus the shebang-only-no-newline fixture.
6. Survives a leaked `GIT_DIR` pointed at a decoy repo.
7. `tests/mocks/brew` **and** `config/local.sh.example` are both members.
8. `scripts/list-shell-files.sh` **exits 0**. No count — a count needs a reference value, and every reference value is either hardcoded or derived by a predicate that can disagree with production. Round 2's floor broke on deletion, round 3's on a python-shebang mock.
9. Count identical under a `<4` and a `>=4` make. **Must skip with a stated reason** where only one is present (`ubuntu-latest` has 4.3 only) rather than pass silently.
10. The CI step's empty-list guard.
11. **A tracked non-shell file under `tests/mocks/` is absent from `SHELL_FILES`.** Fixtures must be **extensionless**: `tests/mocks/fixture-data` (no shebang) and `tests/mocks/python-helper` (`#!/usr/bin/env python3`). A `.md` fixture is worthless here — verified, `:(exclude)*.md` passes it while still shipping two non-shell files.

Case 11 is the only case pinning the property the script is bought for. Cases 1–10 all stay green under the equivalent pathspec — measured.

**Interfaces:** Consumes — `make print-SHELL_FILES` from Task 3.

---

### Task 5: Point CI's lint-macos at the derived list

```yaml-task
id: 5
description: Replace the find-based bash -n step with the derived list, add the empty-list guard, and delete the dead tests/mocks exclusion
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: 'bash -c ''f=$(make print-SHELL_FILES | tr " " "\n" | grep -c .); [ "$f" -gt 0 ]'''
    exit_code: 0
  - cmd: 'bash -c ''make print-SHELL_FILES | tr " " "\n" | xargs -I{} bash -n {}'''
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - .github/workflows/ci.yml
depends_on: [3]
```

`tdd: not-applicable` — GitHub Actions steps cannot be executed locally; the shell logic inside the step is what the gates above run, and Task 4 case 10 covers the guard.

**`tr ' ' '\n'` is required and is not cosmetic.** `print-%` emits `$(SHELL_FILES)` as one space-separated line, while the sibling zsh step is newline-oriented because `git ls-files` emits newlines. `xargs -I` implies `-L1` and does not split on blanks, so copying that step's shape fails with `xargs: command line cannot be assembled, too long` — verified.

Replace the `find` step with:

```yaml
- name: Syntax check all shell scripts (bash)
  run: |
    files=$(make print-SHELL_FILES | tr ' ' '\n' | grep -c .)
    if [ "${files}" -eq 0 ]; then
      printf 'shell file list is EMPTY - refusing to pass having checked nothing\n' >&2
      exit 1
    fi
    make print-SHELL_FILES | tr ' ' '\n' | xargs -I{} bash -n {}
```

This deletes `-not -path './tests/mocks/*'`, which has never excluded anything — `-name '*.sh'` never matched an extensionless mock. `find . -path './tests/mocks/*' -name '*.sh'` returns 0.

**Interfaces:** Consumes — `make print-SHELL_FILES` from Task 3.

---

### Task 6: Write ADR-0019

```yaml-task
id: 6
description: Record the shebang-derivation decision, its rejected alternatives, and the deferred-repos reasoning as an ADR (docs-only, no behavior change)
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: test -f docs/adr/0019-shebang-derived-lint-scope.md
    exit_code: 0
  - cmd: 'grep -qE "Status:.*Accepted" docs/adr/0019-shebang-derived-lint-scope.md'
    exit_code: 0
  - cmd: 'grep -q "0019" docs/adr/README.md'
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - docs/adr/0019-shebang-derived-lint-scope.md
  - docs/adr/README.md
depends_on: [3]
```

`tdd: not-applicable` — documentation only. Required by `repo-structure.md`: this changes the structural pattern by which every gate in the repo derives its scope, and the four deferred repos need a decision record to point at rather than a 900-line spec.

**Status gate is deliberately tolerant.** `grep -qE "Status:.*Accepted"` matches the repo's actual `**Status:** Accepted` convention — 29 of 30 existing ADRs use it. A literal `grep -q "Status: Accepted"` cannot match those bytes and would force the implementer to write the directory's only format outlier to satisfy the gate.

Nygard format, short — the spec carries the detail. Context: a pathspec cannot express "every tracked shell script"; 35 of 100 files were gated. Decision: derive by first-line shebang via `scripts/list-shell-files.sh`. Consequences: +43ms per `make` invocation, a parse-time dependency on a tracked executable, and a set correct in both directions. Rejected: inline `$(shell)` (`\#` diverges between make 3.81 and 4.x), an awk one-liner (only testable through make), and a wider pathspec (identical set today, but a directory glob cannot exclude non-shell files — measured at 20 such arrivals across five repos). Related: ADR-0017, ADR-0018, and the spec.

**Interfaces:** Consumes — the decision as implemented in Task 3.

---

### Task 7: Update CLAUDE.md

```yaml-task
id: 7
description: Sync the documented lint scope figures and the now-false tests/mocks coverage note (docs-only, no behavior change)
role: executor
model: haiku
tdd: not-applicable
acceptance:
  - cmd: 'grep -q "list-shell-files" CLAUDE.md'
    exit_code: 0
  - cmd: '! grep -q "35 tracked shell files" CLAUDE.md'
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - CLAUDE.md
depends_on: [3, 4, 5]
```

`tdd: not-applicable` — documentation only.

**Both gates are discriminators and both fail on base** — `CLAUDE.md` currently contains `35 tracked shell files` and does not contain `list-shell-files`. Verified.

**`CLAUDE.md` edits.** Three places state the old scope and must move together:

- The `make lint` bullet under Testing: "35 tracked shell files: 33 `.sh`/`.bash` plus the two extensionless hooks" → the shebang-derived set, naming `scripts/list-shell-files.sh` and the **101** figure with its date. Not 100: the script carries a bash shebang and is tracked, so it appears in its own output. The spec calls this self-consistency — the tool deciding the scope cannot exempt itself from it.
- The ShellCheck section's closing paragraph, which says scope comes from `git ls-files` "plus two named hooks".
- The paragraph beginning "**It does not cover `tests/mocks/`.**" — now false; replace with a note that the derivation covers them and that the 2 files with findings were fixed.

Do **not** touch the Coverage section — the bash coverage denominator is unchanged and its independence is a stated non-goal.

**Not in this task:** the backlog row removal in `docs/superpowers/README.md` and the plan-index status flip are docs-only on **master**, not this branch. The orchestrator handles them directly. An earlier draft of this task carried a `! grep -q "cannot see any of the 64 mocks" docs/superpowers/README.md` gate against a file the task does not touch — unsatisfiable by construction, and exactly the "check the paths a gate names" defect this skill warns about.

**Interfaces:** Consumes — the final state of Tasks 3–5.

---

### Task 8: Run the three mutations

```yaml-task
id: 8
description: Prove each new gate can fail by applying its mutation and confirming the expected cases turn red
role: reviewer
tdd: not-applicable
acceptance:
  - cmd: make test
    exit_code: 0
max_retries: 1
files_touched: []
depends_on: [4, 5, 6, 7]
```

`tdd: not-applicable` — this task runs mutations and reverts them; it ships no code. Its own gate is that the tree is clean and green **after** all three are reverted.

Apply each, record the observed result, revert:

| #   | mutation                                                                                                                                               | expected                                |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------- |
| 1   | `tests/mocks/gpg`: `_` → `line`                                                                                                                        | `make lint` red                         |
| 2   | script body → the equivalent pathspec `git ls-files '*.sh' '*.bash' 'scripts/pre-push' 'scripts/commit-msg' 'tests/mocks/*' 'config/local.sh.example'` | cases **5 and 11** red; 1–4, 6–10 green |
| 3   | `read` guard → bare `\|\| continue`                                                                                                                    | case 5's unterminated fixture red       |

**Mutation 2 is why this task exists.** It is the only check distinguishing this design from a one-line pathspec producing the identical 100 files. If case 11 does not turn red, the whole change reduces to a more expensive way of producing the same set and that is a blocker, not a nit.

Note both cases 5 and 11 are expected red under mutation 2 — a pathspec ignores shebangs entirely, so the form matrix fails too. An earlier version of this expectation said "case 11 red, 1–10 green" and was unsatisfiable under either reading.

**Interfaces:** Consumes — everything. Produces — the recorded mutation results for the PR body.
