# Hooks Sweep `GIT_DIR` Strip Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop a leaked `GIT_DIR` from redirecting the git-hooks sweep's `make install-hooks` into another repo's hooks directory.

**Architecture:** `install_git_hooks_all_repos` already strips `GIT_DIR`/`GIT_WORK_TREE`/`GIT_COMMON_DIR`/`GIT_INDEX_FILE` on every _read_ path (`_git_hooks_discover`, `_git_hooks_dir`) but not on its one _write_ path, the `make install-hooks` invocation at `lib/git_hooks.sh:327`. One `env -u` prefix closes it for all nine mandated repos regardless of each repo's Makefile shape.

**Tech Stack:** bash, BATS, GNU make.

## Global Constraints

- PR 1 of 2 from spec `docs/superpowers/specs/2026-07-29-doctor-hookspath-check-design.md`. Ships first and independently; do not implement any part of PR 2 (the hooksPath detector) here.
- No `set -e` at top level (`shell.md`).
- `lib/git_hooks.sh` keeps its sourcing guard `[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0` as the **last** line of the file.
- The four stripped variables are exactly `GIT_DIR`, `GIT_WORK_TREE`, `GIT_COMMON_DIR`, `GIT_INDEX_FILE` — same set already used at `lib/git_hooks.sh:43` and `:74`.
- Bash coverage floor is 90% and CI blocks below it.

## Why this is exposed today

Verified in this repo:

```
$ git rev-parse --git-path hooks
.git/hooks
$ GIT_DIR=/Users/bruce/git-repos/personal/ai-config/.git git rev-parse --git-path hooks
/Users/bruce/git-repos/personal/ai-config/.git/hooks
```

`ai-config` (`$(HOOKS_DIR)` from `--git-path hooks`) and `math` (`$(git rev-parse --git-path hooks)` inline) both resolve their install target that way, so a leaked `GIT_DIR` sends the swept repo's hooks into whichever repo the leaked var names. Trigger chain: push from a worktree → git exports `GIT_DIR` into the pre-push hook environment → this repo's pre-push runs `make test` → `git_hooks.sh` is sourced and the sweep can run.

## Verification

**Session-level command:** `make test` from the repo root — exit 0, and the reported test count must not drop below the current 1056.

**Expected observable change:** a new BATS test in `tests/setup_env/git_hooks.bats` that fails before the production change and passes after. The failure mode it detects: hooks installed into the leaked repo instead of the swept repo.

**Edge case that must be exercised:** the fixture's `install-hooks` target must resolve via `$(git rev-parse --git-path hooks)`. With a literal `.git/hooks` target the test passes whether or not the strip is present, because `make -C` sets cwd and a leaked `GIT_DIR` cannot redirect a literal relative path — `tests/setup_env/git_hooks.bats:805`'s existing real-recipe fixture has exactly that shape and must NOT be reused as-is. This is the `tdd.md` section E mock-fidelity trap.

---

### Task 1: Strip repo-location vars from the sweep's `make install-hooks` invocation

```yaml-task
id: 1
description: Add env -u GIT_DIR/GIT_WORK_TREE/GIT_COMMON_DIR/GIT_INDEX_FILE to install_git_hooks_all_repos' make call, with a BATS test using a --git-path-hooks fixture that can observe the redirect
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: bats tests/setup_env/git_hooks.bats
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - lib/git_hooks.sh
  - tests/setup_env/git_hooks.bats
depends_on: []
```

**Files:**

- `tests/setup_env/git_hooks.bats` — new test + new fixture builder
- `lib/git_hooks.sh` — line 327

**Step 1 — write the failing test.**

Add a fixture builder next to the existing `_sweep_build_real_repo` helper (around line 789). It must differ from that helper in exactly one way that matters: the `install-hooks` recipe resolves its destination through `git rev-parse --git-path hooks` instead of a literal `.git/hooks`.

```bash
# _sweep_build_gitpath_repo NAME
# Builds a repo whose install-hooks resolves its destination via
# `git rev-parse --git-path hooks` -- the shape ai-config and math use, and
# the ONLY shape that can observe a leaked GIT_DIR redirecting the install.
# A literal `.git/hooks` recipe (see _sweep_build_real_repo) lands in the
# swept repo either way, because make -C sets cwd, so it cannot fail when
# the strip is absent.
_sweep_build_gitpath_repo() {
  local _name="$1"
  local _repo="${PERSONAL_GITREPOS}/${_name}"
  git init -q "${_repo}"
  mkdir -p "${_repo}/scripts"
  local _h
  for _h in pre-commit pre-push commit-msg; do
    printf '#!/usr/bin/env bash\nexit 0\n' > "${_repo}/scripts/${_h}"
    chmod +x "${_repo}/scripts/${_h}"
  done
  printf 'install-hooks:\n\t@d="$$(git rev-parse --git-path hooks)"; mkdir -p "$$d"; cp scripts/pre-commit scripts/pre-push scripts/commit-msg "$$d/"; chmod +x "$$d/pre-commit" "$$d/pre-push" "$$d/commit-msg"\n' \
    > "${_repo}/Makefile"
}
```

Note the `$$` escapes: this is a Makefile recipe written from a shell heredoc-free `printf`, so `$$d` reaches make as `$d` and make passes `$d` to the shell.

Then the test itself:

```bash
@test "install_git_hooks_all_repos strips GIT_DIR so hooks land in the swept repo, not the leaked one" {
  _sweep_build_gitpath_repo "target-repo"

  # A second real repo that a leaked GIT_DIR will point at. It is NOT
  # discoverable (no Makefile), so the sweep must never write into it.
  local _leaked="${TESTDIR}/leaked-repo"
  git init -q "${_leaked}"

  # Only target-repo is discoverable, so the sweep visits exactly one repo.
  run env GIT_DIR="${_leaked}/.git" bash -c "
    source '${BATS_TEST_DIRNAME}/../../lib/git_hooks.sh'
    PERSONAL_GITREPOS='${PERSONAL_GITREPOS}' install_git_hooks_all_repos
  "

  # The load-bearing assertion: destination is the swept repo.
  [ -x "${PERSONAL_GITREPOS}/target-repo/.git/hooks/pre-commit" ]
  # And NOT the leaked one.
  [ ! -e "${_leaked}/.git/hooks/pre-commit" ]
}
```

The `source` + explicit `PERSONAL_GITREPOS` inside `env` is needed because `env GIT_DIR=…` must wrap the whole sweep, not just one call — a BATS `run` of an already-sourced function would not carry the var into `make`'s environment the way a real leaked push does.

**Step 2 — run it and confirm it fails for the right reason.**

```bash
bats tests/setup_env/git_hooks.bats -f "strips GIT_DIR"
```

Expected failure: the first assertion fails because `target-repo/.git/hooks/pre-commit` does not exist, and the second fails because the file landed in `leaked-repo` instead. If it fails because the fixture's `make` errored, fix the fixture before touching production code — a fixture error is not the bug under test.

**Step 3 — implement.**

`lib/git_hooks.sh:327`, replace:

```bash
    run_cmd make -s -C "${_dir}" install-hooks
```

with:

```bash
    # An inherited GIT_DIR (or GIT_WORK_TREE/GIT_COMMON_DIR/GIT_INDEX_FILE)
    # overrides -C for any git call the recipe itself makes -- and ai-config
    # and math both resolve their install destination via `git rev-parse
    # --git-path hooks`, so a leak sends this repo's hooks into whichever
    # repo the leaked var names. git exports GIT_DIR into the pre-push hook
    # environment when pushing from a worktree, and this repo's pre-push
    # runs `make test`, which sources this file. Same four vars, and the
    # same reason, as the read paths above.
    run_cmd env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE \
      make -s -C "${_dir}" install-hooks
```

Leave `_rc=$?` on the following line untouched — `env`'s exit status is the exit status of `make`, so the existing failure accounting is unaffected.

**Step 4 — confirm the test passes and nothing regressed.**

```bash
bats tests/setup_env/git_hooks.bats
make test
```

`make test` runs `make lint` first (`bash -n`, `zsh -n`, shellcheck) — both must be clean. Check the reported test count has gone up by one and not down.

**Step 5 — verify the DRY_RUN path still prints correctly.**

`run_cmd` under `DRY_RUN` prints the command rather than executing it, and the printed line now begins with `env -u …`. Confirm the existing dry-run test still passes and that its assertion does not pin the exact command string:

```bash
bats tests/setup_env/git_hooks.bats -f "dry"
```

If an existing dry-run assertion matches the literal `make -s -C`, widen it to match a substring that survives the prefix (e.g. `install-hooks`) rather than deleting the assertion.

**Step 6 — commit.**

Invoke `caveman:caveman-commit` to generate the message, then commit. Subject ≤50 chars, `fix(hooks):` type.

**Interfaces:**

- Consumes: `run_cmd` (from `lib/helpers.sh`), `_git_hooks_discover`, `_git_hooks_digest`, `_git_hooks_check_complete` — all unchanged.
- Produces: nothing new. `install_git_hooks_all_repos` keeps its `{0, 1}` return contract; PR 2 is what widens it to `{0, 1, 2}`.

---

## Self-review

1. **Spec coverage:** covers exactly the spec's "Delivery — PR 1" scope (Decision 6 plus its isolation test). Decisions 1–5 and 7 belong to PR 2 or are explicit non-actions.
2. **Placeholders:** none. Fixture, test, and production diff are given verbatim.
3. **Type consistency:** `_sweep_build_gitpath_repo` is a new name and does not collide with the existing `_sweep_build_real_repo` / `_sweep_build_failing_repo`.
4. **`files_touched` matches the prose:** both files the steps modify are listed; the test file is included as `tdd: required` demands.
5. **Acceptance gate is the aggregate:** `make test`, with the scoped `bats` run alongside for speed, never instead.
6. **ADR check:** no new Phase 3 gate, no HOLD-capable check, no schema or storage decision, no new structural pattern — this restores an existing invariant (`env -u` on every git-touching path) to the one place it was missing. No ADR needed.
7. **Coverage:** one added branch-free line in an already-instrumented file; the 90% floor is not at risk.
