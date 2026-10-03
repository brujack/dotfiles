# Master Guard Default-Deny Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the pre-push hook's direct-to-master deny list with one default-deny
predicate shared by the suite trigger and the master guard, so only inert `.md` files and
the root `LICENSE` reach `master` without a PR.

**Architecture:** `scripts/pre-push` gains `_path_is_inert <path> <sha>` (name rule plus a
first-two-bytes content check). The suite trigger runs `make test` unless every changed path
is inert; the master guard refuses any non-inert path or an unresolvable range, with a
recovery message chosen from the ref line. A new bats file pins the premise that no
`make test` step reads a tracked `.md`.

**Tech Stack:** bash, bats, git plumbing (`diff --no-renames`, `cat-file`).

**Spec:** `docs/superpowers/specs/2026-10-02-master-guard-default-deny-design.md`

## Global Constraints

- Inert = (`*.md` not under root `tests/`, or exactly `LICENSE`) AND the blob at `local_sha`
  does not start with `#!`. Everything else is not inert.
- Deleted at the tip (`git cat-file -e` fails): judged by name alone. Exists but not a
  `blob`: not inert.
- Read the first two bytes as `head -c 2 < <(git cat-file blob "${sha}:${path}")` — never a
  pipe (rc 141 under `pipefail` on blobs over the pipe buffer).
- Changed paths come from `git -c core.quotePath=false diff --no-renames --name-only "${range}"`.
- `_path_is_inert` is only ever called inside `if`, `&&` or `||` (the hook runs `set -e`).
- **Measured during planning, refines the spec:** `git push origin HEAD:master` hands the
  hook `local_ref` = `HEAD`, not the branch name, whether on a branch or detached. When
  `local_ref` is `HEAD`, resolve it with `git symbolic-ref -q --short HEAD`: `master` takes
  the local-master recipe, another branch the branch recipe, empty the detached recipe.
- Inert-set tests in `tests/scripts/pre_push.bats` push to a feature ref (`refs/heads/feat/x`);
  only guard tests push to `refs/heads/master`.
- Per-task gates are scoped (`bats <file>`, `make lint`). The orchestrator runs `make test`
  once after Task 4 and once after Task 5.
- No task pushes. The installed hook is the main checkout's copy, so pushes from this branch
  are judged by the old hook until merge.

## Verification (session level)

- `bats tests/scripts/pre_push.bats tests/scripts/docs_inert_premise.bats tests/scripts/whats-new-anthropic.bats` green.
- `make test` green on `claude`; `test-macos` green in CI.
- Mutation gates in Task 3 each turn `pre_push.bats` red.
- Edge cases: shebang `.md`/`LICENSE`, rename `x.sh` to `x.md`, `.sh` deletion, newline path,
  300 KB `.md`, unresolvable range, `HEAD:master` from a branch and from detached HEAD.

---

### Task 1: Rename the digest state file to `.platform-state.md`

```yaml-task
id: 1
description: git mv the weekly digest's .platform-state.txt to .platform-state.md and update every reader, keeping content
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: bats tests/scripts/whats-new-anthropic.bats
    exit_code: 0
  - cmd: 'test -z "$(git ls-files docs/anthropic-new-features/.platform-state.txt)"'
    exit_code: 0
  - cmd: 'cmp <(git show origin/master:docs/anthropic-new-features/.platform-state.txt) docs/anthropic-new-features/.platform-state.md'
    exit_code: 0
  - cmd: '! grep -rn "platform-state.txt" scripts tests docs/anthropic-new-features/README.md'
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched: [scripts/whats-new-anthropic.sh, tests/scripts/whats-new-anthropic.bats, docs/anthropic-new-features/README.md, docs/anthropic-new-features/.platform-state.txt, docs/anthropic-new-features/.platform-state.md]
depends_on: []
parallel_group: wave-1
```

- [ ] Change the six `.platform-state.txt` references in `tests/scripts/whats-new-anthropic.bats` (lines 264, 297, 344, 375, 400, 414) to `.platform-state.md`. Run the file; the line-264 test must fail.
- [ ] `scripts/whats-new-anthropic.sh:8`: `PLATFORM_STATE_FILE="${FEATURES_DIR}/.platform-state.md"`. Run the file; green.
- [ ] `git mv docs/anthropic-new-features/.platform-state.txt docs/anthropic-new-features/.platform-state.md` (content must carry over; without it the next digest reports the whole page as new).
- [ ] `docs/anthropic-new-features/README.md:8`: name `.platform-state.md`.
- [ ] Leave historical specs/plans that name the old file untouched.
- [ ] Commit (caveman-commit).

### Task 2: `_path_is_inert` and the suite trigger

```yaml-task
id: 2
description: Add the default-deny inert predicate to scripts/pre-push and drive the suite trigger with it
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: bats tests/scripts/pre_push.bats
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched: [scripts/pre-push, tests/scripts/pre_push.bats]
depends_on: []
```

**Predicate (add above the stdin loop, verbatim):**

```bash
# Default-deny: a path is inert only if it is a .md outside the root tests/,
# or the root LICENSE, AND its blob does not start with #! (make lint selects
# shell files by first line, whatever their name). Call only in a conditional:
# this hook runs under set -e.
_path_is_inert() {
    local _path="${1}" _sha="${2}" _head
    case "${_path}" in
        tests/*) return 1 ;;
        LICENSE | *.md) ;;
        *) return 1 ;;
    esac
    # Deleted at the tip: never lands, so judged by name alone.
    git cat-file -e "${_sha}:${_path}" 2>/dev/null || return 0
    [[ "$(git cat-file -t "${_sha}:${_path}" 2>/dev/null)" == "blob" ]] || return 1
    # Process substitution, not a pipe: head closing early is SIGPIPE (141)
    # under pipefail on any blob larger than the pipe buffer.
    _head="$(head -c 2 < <(git cat-file blob "${_sha}:${_path}"))"
    [[ "${_head}" != '#!' ]]
}
```

**Trigger:** `changed` from `git -c core.quotePath=false diff --no-renames --name-only "${range}"`. Replace the `^tests/` and `grep -qvE` arms with a loop over `changed` (`while IFS= read -r _p; ... done <<< "${changed}"`, skip empty lines): any `! _path_is_inert "${_p}" "${local_sha}"` sets `needs_test=1` and appends to a per-ref `live_paths` (Task 3 reads it). Diff failure still sets `needs_test=1`. Leave the old master guard block as is.

**Tests (red first, one at a time, all on `refs/heads/feat/x`):**

- [ ] Repoint every inert-set test that pushes to `refs/heads/master` (lines 63, 108, 117, 126, 135, 153, 162, 171, 246, 255, 264, 273, 292, 301, 310, 319, 328, 337, 346, 355, 391, 399) to `refs/heads/feat/x`. Guard tests (415 onward) stay on master.
- [ ] Invert "skips when only a .github/workflows file changed" and "skips a .github workflow using the .yaml spelling": suite runs.
- [ ] New: `docs/a.md` skipped; `foo/tests/a.md` skipped; `docs/evil.md` with `#!/usr/bin/env bash` runs; root `LICENSE` with a shebang runs; `x/LICENSE` runs; `a.md.sh` runs; 300 KB `docs/big.md` skipped; `git mv x.sh x.md` runs; deleting `docs/old.md` skipped; deleting `x.sh` runs.
- [ ] `_commit_file` uses `printf '%s\n'` with single quotes; for a shebang or 300 KB file write the file directly in the test and commit with `git -C`.
- [ ] Commit.

**Produces:** `_path_is_inert`; per ref line, `live_paths` (newline-joined non-inert paths) and `diff_rc`.

### Task 3: Default-deny master guard and recovery messages

```yaml-task
id: 3
description: Refuse non-inert paths and unresolvable ranges on master, with a recovery chosen from the ref line
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: bats tests/scripts/pre_push.bats
    exit_code: 0
  - cmd: make lint
    exit_code: 0
  - cmd: 'bash -c ''t=$(mktemp -d); mkdir -p $t/scripts $t/tests/scripts; cp tests/scripts/pre_push.bats $t/tests/scripts/; sed "s/ --no-renames//" scripts/pre-push > $t/scripts/pre-push; ! bats $t/tests/scripts/pre_push.bats >/dev/null'''
    exit_code: 0
  - cmd: 'bash -c ''t=$(mktemp -d); mkdir -p $t/scripts $t/tests/scripts; cp tests/scripts/pre_push.bats $t/tests/scripts/; sed "s/\[\[ \"\${_head}\" != .#!. \]\]/true/" scripts/pre-push > $t/scripts/pre-push; ! cmp -s scripts/pre-push $t/scripts/pre-push && ! bats $t/tests/scripts/pre_push.bats >/dev/null'''
    exit_code: 0
max_retries: 3
files_touched: [scripts/pre-push, tests/scripts/pre_push.bats]
depends_on: [2]
```

Replace the old guard block. On `remote_ref == refs/heads/master`: if `diff_rc` is non-zero, append `remote_ref` to `unresolved_refs`; else append `live_paths` to `refuse_paths` and record `refuse_local_ref="${local_ref}"`. After the loop, before the `needs_test` exit:

- `unresolved_refs` non-empty: print that the range for that ref cannot be resolved, run `git fetch` and retry; exit 1.
- `refuse_paths` non-empty: print every path, "Only .md files and the root LICENSE may go to master directly", "ci.yml runs on pull_request only, so these would reach master untested", then the recipe, then always: emergency route (`gh pr merge --admin`; do not use `--no-verify`) and "a push carrying a branch and master is refused whole; push the branch on its own". Exit 1.

Recipe from `refuse_local_ref` (resolve `HEAD` with `git symbolic-ref -q --short HEAD`, see Global Constraints):

- `master`: `git switch -c <name>`; `git push -u origin <name> && gh pr create --fill`; `git switch master && git reset --keep origin/master`; if `reset --keep` refuses, commit or set aside the uncommitted change first, nothing is lost; in a worktree run the reset in the main checkout.
- branch `<b>`: `git push -u origin <b> && gh pr create --fill`.
- empty (detached): `git switch -c <name>`, then the branch recipe.

**Tests (red first, one at a time, on `refs/heads/master`):** each of `tests/mocks/x`, `a.py`, `.zshrc`, `uv.lock`, `.github/workflows/ci.yml`, `.warp/settings.toml`, `renovate.json`, `docs/x/.state.txt`, `foo.unknown` refused and named; `docs/a.md`, `README.md`, `LICENSE`, `docs/café.md`, 300 KB `.md`, `foo/tests/a.md`, deleting `docs/old.md` allowed; shebang `.md` and `LICENSE`, `tests/a.md`, `x/LICENSE`, `a.md.sh`, a path containing a newline, deleting `x.sh` refused; `git mv x.sh x.md` refused naming `x.sh`; unknown `remote_sha` gives the fetch message and not `gh pr create`; `local_ref` `refs/heads/master` run from branch `feat` gives `reset --keep` and not `git push -u origin feat`; `local_ref` `refs/heads/feat` names `feat` and lacks `reset --keep`; `local_ref` `HEAD` on branch `feat` gives the `feat` recipe; `HEAD` detached gives `git switch -c`; every refusal contains `gh pr merge --admin` and not `--no-verify`; docs commit stacked on an unpushed code commit refused; non-inert path on a feature ref runs the suite and exits 0. Remove the old `.bash` and `.sh` guard tests only if a new row covers them.

Mutations (report each red test in the task report, beyond the two gates above): restore the old deny list; delete the `unresolved_refs` refusal; call `_path_is_inert` bare outside a conditional.

- [ ] Commit.

### Task 4: Pin the docs-inert premise

```yaml-task
id: 4
description: New bats file asserting no make test prerequisite and no test reads a tracked .md outside tests/
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: bats tests/scripts/docs_inert_premise.bats
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched: [tests/scripts/docs_inert_premise.bats]
depends_on: []
parallel_group: wave-1
```

Two checker functions in the file, each taking a root directory, so tests can run them on the
real repo and on fixtures:

1. `_check_prereqs <root>`: read `make -C <root> -pnq test 2>/dev/null` (rc 1 from `-q` is
   expected; parse stdout, never branch on rc), take the `test:` rule's prerequisites and
   recurse through each target's own prerequisites, ignoring file prerequisites that exist on
   disk. Compare the closure with a recorded `ALLOWED_TEST_PREREQS` array (measure it now; it
   starts from `lint check-lock check-requirements-ci test-python`). An extra target fails,
   naming it, saying to check whether it reads a tracked `.md`, and naming
   `check-agent-guidance` (reads `CLAUDE.md`) as the known reader.
2. `_check_readers <root>`: scan `<root>/tests` (`*.bats`, `*.py`, `helpers/*`) for a path built
   from a root variable (`REPO_ROOT`, `ROOT`, `repo_root`, `BATS_TEST_DIRNAME/../..`) ending in
   `.md` and not under `tests/`. Recorded `ALLOWED_MD_READERS` (file and reason), empty today;
   `tests/test_relocation_check.py` needs no entry (it reads `CLAUDE.md` via `git show` at a
   pinned SHA). A hit fails, naming file and line.

**Tests:** real repo passes `_check_prereqs`; fixture Makefile with `test: lint check-agent-guidance` fails naming `check-agent-guidance`; real repo passes `_check_readers`; fixture `tests/x.bats` containing `cat "${REPO_ROOT}/README.md"` fails naming the file; fixture `tests/y.py` with `REPO_ROOT / "CLAUDE.md"` fails; fixture reading `"${REPO_ROOT}/tests/fixtures/a.md"` passes. Write each control red first against a stub that always passes.

- [ ] Commit.

### Task 5: Document the rule

```yaml-task
id: 5
description: Docs-only — CLAUDE.md pre-push bullets, ADR-0038, ADR index, plan index; no behaviour change so TDD does not apply
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: 'grep -q "_path_is_inert" CLAUDE.md'
    exit_code: 0
  - cmd: 'grep -q "gh pr merge --admin" CLAUDE.md'
    exit_code: 0
  - cmd: 'test -f docs/adr/0038-master-guard-default-deny.md && grep -q "0038" docs/adr/README.md'
    exit_code: 0
  - cmd: 'grep -qE "Status.*Accepted" docs/adr/0038-master-guard-default-deny.md'
    exit_code: 0
  - cmd: '! grep -n "deliberately narrower\|known gap, recorded" CLAUDE.md'
    exit_code: 0
max_retries: 2
files_touched: [CLAUDE.md, docs/adr/0038-master-guard-default-deny.md, docs/adr/README.md, docs/superpowers/README.md]
depends_on: [1, 2, 3, 4]
```

- `CLAUDE.md` Testing section: replace the "Pre-push hook: fail-closed inert-path set" and "direct-to-master guard" bullet groups with bullets stating: one predicate; inert = `.md` outside root `tests/` or root `LICENSE`, without a `#!` first line; everything else needs a PR; unresolvable range on master refused with fetch-and-retry; recovery recipes; emergency route `gh pr merge --admin`, never `--no-verify`; a broken hook blocks every push, recover with a fix branch pushed `--no-verify` (the one sanctioned use); `tests/scripts/docs_inert_premise.bats` pins the premise. Keep the `→ \`dotfiles-testing-toolchain.md\` § ...` suffix pointers (ADR-0036 format). Keep the existing worktree-root and git-env-strip bullets.
- ADR-0038 (Nygard: Context, Decision, Consequences, Related; `**Status:** Accepted`): amends ADR-0017's inert set, supersedes the guard's narrow scope, records the emergency route and the `HEAD` local_ref finding. Copy the structure of `docs/adr/0037-macos-suite-gates-merge.md`.
- `docs/adr/README.md`: add the 0038 row.
- `docs/superpowers/README.md`: master-guard row In Progress, plan linked.
- [ ] Commit.

The ai-config knowledge sections and the ai-config backlog row (align `git-workflow.md` and
`sdlc-branch-guard`) are done by the orchestrator in Phase 3's docs step, not by this task.
