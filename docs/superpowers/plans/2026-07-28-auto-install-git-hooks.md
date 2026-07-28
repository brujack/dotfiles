# Auto-install Git Hooks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Install every personal repo's git hooks automatically during `-t setup_user` and `-t update`, so a hook edited on one box is live on all of them without a manual `make install-hooks` per checkout.

**Architecture:** A new `lib/git_hooks.sh` discovers repos under `${PERSONAL_GITREPOS}` that carry an `install-hooks` Makefile target, runs each target, and verifies the result as a post-condition on the installed hooks directory rather than on the target's exit code. Reporting digests hook file contents before and after each call so the weekly summary names what actually changed. `config/hook_repos.sh` holds a reporting-only list of repos expected to carry hooks.

**Tech Stack:** Bash, BATS, GNU Make, `shasum`/`sha256sum`.

**Spec:** [2026-07-28-auto-install-git-hooks-design.md](../specs/2026-07-28-auto-install-git-hooks-design.md) at commit `9646364`.

## Global Constraints

- No `set -euo pipefail` at top level — conditional installs require non-zero exits to continue.
- Every `lib/` file carries the sourcing guard `[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0` **as its last line, after all function definitions** — not near the top. The guard's condition is _true_ when the file is sourced, so placing it above the definitions returns before any function exists and breaks standalone sourcing entirely. Verified precedent: `lib/git_sync.sh:118` and `lib/legacy_rsync.sh:28` are each the final line of their file. (`CLAUDE.md`'s "near the top" wording is inaccurate; Task 8 corrects it.)
- Shebang `#!/usr/bin/env bash`; `[[ ]]` not `[ ]`; `${VAR}` with braces; `printf` not `echo`; `snake_case()` functions; `readonly SCREAMING_SNAKE_CASE` constants.
- Error handling in function bodies uses `|| return 1`, never `|| exit`.
- Tests never mutate real system state — PATH-based mocks from `tests/mocks/` only. `tests/mocks/make` already exists.
- Bash coverage is CI-gated at 90% and blocks auto-merge. CI also asserts a test-count floor of ≥840.
- The sweep operates on `~/git-repos/personal/` only. `~/git-repos/work/` is out of scope.
- The digest is over **file contents with symlinks resolved**, never `stat` metadata. Measured: `cp` rewrites mtime while content stays identical.
- The post-condition asserts on the **installed hooks directory**, never on `scripts/`. A hook installed by a route other than the Makefile (e.g. `ledger init`) satisfies it.
- The mandated hook set is uniform for every repo: `{pre-commit, pre-push, commit-msg}`.

## Verification Planning

**Command that proves the whole change works:**

```bash
./setup_env.sh -t update --dry-run 2>&1 | grep -A3 'git-hooks'
```

**Expected observable output:** a `git-hooks` section appears in the update summary, listing `[DRY RUN] make -s -C <dir> install-hooks` for each of the six repos that currently carry an `install-hooks` target (`ai-config`, `dotfiles`, `etch-cli`, `state-ledger`, `brucejacksonconsulting-site`, `math`), and no line for `ai-config-hook-integrity` (a live worktree), for any `*-worktrees` container, or for any repo without the target.

**Live (non-dry-run) confirmation**, run once after merge:

```bash
./setup_env.sh -t update
```

Expected: the summary's `git-hooks` line names `state-ledger` and `brucejacksonconsulting-site` as gaps or updates, because as measured 2026-07-28 `state-ledger` is missing `pre-push` + `commit-msg` and `brucejacksonconsulting-site` is missing `pre-commit`. Re-running immediately afterwards must report the same repos as **checked, not updated** — that is the idempotency proof.

**Edge cases that must be exercised:**

- A linked worktree in `${PERSONAL_GITREPOS}` is never installed into.
- A partial clone (empty `.git/` directory, `rev-parse` fails) is never invoked — this is the case that writes `/pre-commit` as root on Linux.
- A repo whose `make install-hooks` exits 1 does not stop the repos discovered after it.
- `run_setup_user` returns 0 even when the sweep failed.
- `-t update` reports `n/a` rather than `0` for the updated count under `--dry-run`.

---

### Task 1: Discovery and the expected-repos list

```yaml-task
id: 1
description: Add config/hook_repos.sh and lib/git_hooks.sh with the discovery filter chain
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
  - config/hook_repos.sh
  - lib/git_hooks.sh
  - tests/setup_env/git_hooks.bats
depends_on: []
```

**Files:**

- `config/hook_repos.sh` (new) — `readonly HOOK_EXPECTED_REPOS=(ai-config dotfiles etch-cli state-ledger brucejacksonconsulting-site math ai-devops etch-config terraform_ansible)`. Header comment must state: reporting only; this list decides what counts as a gap, never what gets installed.
- `lib/git_hooks.sh` (new) — header comment, sourcing guard, then source `config/hook_repos.sh` relative to `${BASH_SOURCE[0]}` following the `lib/detect_env.sh:23` pattern. Guard the source with `[[ -f ... ]]` and define an empty `HOOK_EXPECTED_REPOS` fallback if absent, so the file is self-contained when sourced standalone by BATS — the same technique `lib/git_sync.sh` uses for `_git_ssh_opts`.
- `tests/setup_env/git_hooks.bats` (new).

**Implement `_git_hooks_discover()`** — prints one absolute repo path per line to stdout, returns 0:

```bash
_git_hooks_discover() {
  local _dir
  for _dir in "${PERSONAL_GITREPOS}"/*/; do
    [[ -d "${_dir}.git" ]] || continue
    git -C "${_dir}" rev-parse --git-dir >/dev/null 2>&1 || continue
    [[ -f "${_dir}Makefile" ]] || continue
    grep -q '^install-hooks:' "${_dir}Makefile" || continue
    printf '%s\n' "${_dir}"
  done
}
```

Both the `-d .git` and `rev-parse` tests are required and neither subsumes the other: `-d .git` alone admits a partial clone; `rev-parse` alone succeeds inside a linked worktree and would re-admit throwaway worktrees.

**Build the fixture tree once in `setup()`** under `BATS_TEST_TMPDIR`, exporting `PERSONAL_GITREPOS` to it. Nine directories:

1. `repo-with-target/` — real `git init`, `Makefile` containing `install-hooks:`
2. `repo-no-target/` — real `git init`, `Makefile` without the target
3. `worktree-dir/` — `.git` written as a regular file containing `gitdir: /somewhere`
4. `plain-dir/` — no `.git`
5. `repo-failing/` — real `git init`, `Makefile` whose `install-hooks` recipe exits 1
6. `partial-clone/` — `mkdir -p partial-clone/.git` only, plus a `Makefile` with the target
7. `repo-partial-hooks/` — real `git init`, target installs `pre-push` only
8. `repo-listed-no-makefile/` — real `git init`, no Makefile, name present in `HOOK_EXPECTED_REPOS`
9. `repo-unlisted-no-makefile/` — real `git init`, no Makefile, name absent from `HOOK_EXPECTED_REPOS`

Use `git init -q` for real repos. Fixture 6 must be created **inside** `BATS_TEST_TMPDIR` with no ancestor git repository, or `rev-parse` walks upward and succeeds — assert in the test that `git -C partial-clone rev-parse --git-dir` fails before relying on it.

**Tests (write one, watch it fail, implement, watch it pass, commit — repeat):**

- discovers `repo-with-target`, `repo-failing`, `repo-partial-hooks`, `partial-clone`'s exclusion aside
- excludes `repo-no-target`
- excludes `worktree-dir` (the `.git`-is-a-file case)
- excludes `plain-dir`
- **excludes `partial-clone`** — passes `-d .git`, must be rejected by `rev-parse`. This is the `/pre-commit`-as-root guard and cannot be covered by fixture 4.
- excludes `repo-listed-no-makefile` and `repo-unlisted-no-makefile` from _discovery_ (they are gap candidates, handled in Task 3, not install candidates)
- empty `PERSONAL_GITREPOS` prints nothing and returns 0
- a single-qualifying-repo tree behaves the same as a multi-repo tree
- `HOOK_EXPECTED_REPOS` is populated after sourcing `lib/git_hooks.sh`

**Interfaces:**

- Consumes: `PERSONAL_GITREPOS` (from `lib/constants.sh`).
- Produces: `_git_hooks_discover()` → stdout, one trailing-slash absolute path per line, exit 0. `HOOK_EXPECTED_REPOS` array of bare repo names.

---

### Task 2: Content digest

```yaml-task
id: 2
description: Add _git_hooks_digest computing a content hash of a repo's installed hooks directory
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
depends_on: [1]
```

**Files:** `lib/git_hooks.sh`, `tests/setup_env/git_hooks.bats`.

**Implement `_git_hooks_digest REPO_DIR`** — prints a single stable digest string of the repo's installed hooks directory, returns 0. Resolve the hooks directory with `git -C "${_dir}" rev-parse --git-path hooks`; it may be relative, so resolve against `${_dir}`. Hash **file contents with symlinks followed**, sorted by filename for stability, and include the filename so an added or removed hook changes the digest. Missing hooks directory prints an empty-but-stable marker and returns 0.

Use `shasum -a 256` — present on both macOS and Ubuntu; `sha256sum` is Linux-only. Do not use `stat`, `ls -l`, mtime, inode, or size.

**Tests:**

- two calls with no change between them produce identical digests
- **mutating a hook's content changes the digest** — this is the load-bearing assertion
- adding a hook file changes the digest
- removing a hook file changes the digest
- a symlinked hook digests as its target's content, not as the link path
- **`cp`-ing an identical file over an installed hook does NOT change the digest** — this is the mtime-vs-content test, and it must use a real `cp` rather than the `make` mock. A metadata digest fails it; a content digest passes it.
- a repo with no hooks directory returns 0 and prints a stable value

**Interfaces:**

- Consumes: `_git_hooks_discover()` output shape (trailing-slash path).
- Produces: `_git_hooks_digest REPO_DIR` → single-line digest string on stdout, exit 0.

---

### Task 3: Post-condition and gap classification

```yaml-task
id: 3
description: Add _git_hooks_check_complete and _git_hooks_gap_repos for hook-presence and missing-infrastructure gaps
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
depends_on: [2]
```

**Files:** `lib/git_hooks.sh`, `tests/setup_env/git_hooks.bats`.

**Implement `_git_hooks_check_complete REPO_DIR`** — asserts each of `pre-commit`, `pre-push`, `commit-msg` exists and is executable (`[[ -x ... ]]`) in the repo's hooks directory, resolved the same way as Task 2. Prints the names of any missing hooks, space-separated, on stdout. Returns 0 when complete, 1 when any are missing.

This inspects the **installed hooks directory only**. It must never look at `scripts/`. `state-ledger` has no `scripts/pre-commit` but `ledger init` installs an executable `.git/hooks/pre-commit`, and this check must **pass** on that hook — a source-based check would emit a false gap weekly forever.

Add `readonly _GIT_HOOKS_MANDATED=(pre-commit pre-push commit-msg)` near the top of the file. The set is uniform for every repo per `repo-structure.md`; do not make it per-repo.

**Implement `_git_hooks_gap_repos()`** — prints bare names of repos in `HOOK_EXPECTED_REPOS` that exist under `${PERSONAL_GITREPOS}` as real git repos but have no `Makefile` at all. Repos absent from the list are silent. Returns 0.

**Tests:**

- complete repo → returns 0, prints nothing
- repo missing `commit-msg` only → returns 1, prints `commit-msg`
- repo missing two hooks → returns 1, prints both names
- **a hook present but not executable counts as missing** — both branches of the `-x` guard
- **a hook with no counterpart in `scripts/` still passes when installed** — the `ledger init` shape; assert explicitly that `scripts/` is not consulted
- `repo-listed-no-makefile` appears in `_git_hooks_gap_repos` output
- `repo-unlisted-no-makefile` does NOT appear
- empty `HOOK_EXPECTED_REPOS` → `_git_hooks_gap_repos` prints nothing, returns 0

**Interfaces:**

- Consumes: `HOOK_EXPECTED_REPOS`, `PERSONAL_GITREPOS`.
- Produces: `_git_hooks_check_complete REPO_DIR` → missing hook names on stdout, exit 0 complete / 1 incomplete. `_git_hooks_gap_repos()` → bare repo names on stdout, exit 0. `_GIT_HOOKS_MANDATED` array.

---

### Task 4: Sweep orchestration and summary

```yaml-task
id: 4
description: Add install_git_hooks_all_repos tying discovery, install, digest, and gap reporting together
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
depends_on: [3]
```

**Files:** `lib/git_hooks.sh`, `tests/setup_env/git_hooks.bats`.

**Implement `install_git_hooks_all_repos()`:**

For each path from `_git_hooks_discover()`: take a pre-digest, `run_cmd make -s -C "${_dir}" install-hooks`, capture the rc immediately into a local, take a post-digest, then run `_git_hooks_check_complete`. Accumulate four counters — checked, updated, failures, gaps — and two name lists (updated repos, gap descriptions).

Rules, each of which has a test below:

- **Fail-closed, not fail-fast.** A non-zero `make` rc increments failures and the loop continues to the next repo. The function returns 1 only after every discovered repo has been attempted.
- **Gaps never affect the return code.** An incomplete repo increments gaps and emits `log_warn`.
- `make` is invoked with `-s`; none of the six real recipes are `@`-prefixed and the weekly run would otherwise gain ~30–40 lines of echo.
- Under `DRY_RUN`, `run_cmd` prints instead of executing, so digests cannot differ. Skip the digest entirely and report the updated count as the literal string `n/a`, never `0` — `0` would falsely assert everything was current.
- Append `_git_hooks_gap_repos()` output to the gap list.

Summary line, printed via `log_info`:

```
6 checked, 2 updated (ai-config, etch-cli), 3 gaps (state-ledger: commit-msg; ai-devops, etch-config: no Makefile)
```

Name the gaps, do not merely count them — a bare `3 gaps` is the same unactionable line in a different costume.

**Tests:**

- clean tree → returns 0, checked count equals discovered count
- **`repo-failing` returns 1 AND every repo discovered after it still ran** — the single most important test in the file; assert on a marker file written by each fixture's recipe
- a repo with an incomplete hook set increments gaps, does NOT change the return code, and emits `log_warn`
- **unchanged repo reports checked-not-updated using a real `cp`-style recipe, not the `make` mock** — a mock that never touches the filesystem passes this assertion for the wrong reason (`tdd.md` section E, mock fidelity)
- **a symlink-install repo reports updated when its source file is mutated between the two digests.** This proves the digest is _capable_ of seeing a symlink-target change; it does not prove the sweep ever will, since in production nothing mutates the source between the two reads. Note that in the test body.
- calling the function twice produces the same counters as calling it once
- `DRY_RUN=1` → no `make` invocation recorded, discovered repo list unchanged, updated count is `n/a`
- gap repos from `_git_hooks_gap_repos` appear in the summary line

**Interfaces:**

- Consumes: `_git_hooks_discover()`, `_git_hooks_digest()`, `_git_hooks_check_complete()`, `_git_hooks_gap_repos()`, `run_cmd()`, `log_info()`, `log_warn()`.
- Produces: `install_git_hooks_all_repos()` → exit 0 when no `make` failed, 1 otherwise. Summary via `log_info`.

---

### Task 5: Wire into `run_setup_user`

```yaml-task
id: 5
description: Source lib/git_hooks.sh from setup_env.sh and call the sweep from run_setup_user, returning 0
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: bats tests/setup_env/workflows.bats
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - setup_env.sh
  - lib/workflows.sh
  - tests/setup_env/workflows.bats
depends_on: [4]
```

**Files:** `setup_env.sh`, `lib/workflows.sh`, `tests/setup_env/workflows.bats`.

Add `source "$(dirname "${BASH_SOURCE[0]}")/lib/git_hooks.sh"` to `setup_env.sh` after the `lib/legacy_rsync.sh` line (currently line 52).

In `run_setup_user()`, insert after `setup_claude_plugins` and before `_ledger_write_run_entry`:

```bash
  install_git_hooks_all_repos || log_warn "git hooks sweep reported failures — see above"
```

**Do NOT use `|| return 1`.** `setup_env.sh:82` dispatches via `_run_or_exit run_setup_user`, whose body is `[[ ${_ec} -eq 0 ]] || exit "${_ec}"` — a non-zero return here aborts the entire script before `run_setup_or_developer` and `run_developer_or_ansible` ever run, letting a broken Makefile in an unrelated repo kill a full machine bootstrap. Propagating would also skip `_ledger_write_run_entry`, on exactly the runs worth recording.

**Tests:**

- `run_setup_user` invokes `install_git_hooks_all_repos` (stub the function, assert a marker file)
- **`run_setup_user` returns 0 when the sweep returns 1** — the dispatcher-hazard test
- **`_ledger_write_run_entry` still runs when the sweep returns 1**
- the sweep is called after `setup_claude_plugins` (order assertion via an append-only marker log)
- `setup_env.sh` passes `bash -n` and `zsh -n` with the new source line

**Interfaces:**

- Consumes: `install_git_hooks_all_repos()` from Task 4.
- Produces: no new symbols. `run_setup_user`'s contract is unchanged — still returns 0 on success paths.

---

### Task 6: Wire into `run_update` and the summary section order

```yaml-task
id: 6
description: Call the sweep from run_update after the git-repos section and register the git-hooks summary section
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: bats tests/setup_env/update_summary.bats tests/setup_env/workflows.bats
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - lib/workflows.sh
  - lib/update_summary.sh
  - tests/setup_env/update_summary.bats
  - tests/setup_env/workflows.bats
depends_on: [5]
```

**Files:** `lib/workflows.sh`, `lib/update_summary.sh`, `tests/setup_env/update_summary.bats`, `tests/setup_env/workflows.bats`.

In `run_update()`, inside the `_run_all` block, insert **after** the `legacy-rsync` block that ends at `lib/workflows.sh:487`:

```bash
    _update_record_start "git-hooks"
    install_git_hooks_all_repos 2>&1 | tee "${_DOTFILES_RUN_TMPDIR}/err_git-hooks"
    _update_record_end "git-hooks" "${PIPESTATUS[0]}"
```

Placement after `git-repos` (`lib/workflows.sh:473-476`) is a hard constraint, not a preference: `sync_git_repos` is what pulls each repo's hook sources, and a sweep placed before it installs the previous cycle's hooks and reports success. `state-ledger` was 1 commit behind upstream on the Mac Studio when the spec was written, so this is live rather than hypothetical.

Add `git-hooks` to `readonly _UPDATE_SECTION_ORDER` in `lib/update_summary.sh:5-8`. **Both edits are mandatory and coupled** — `CLAUDE.md` records that a `_update_record_start/end` pair without a matching `_UPDATE_SECTION_ORDER` entry is tracked internally but never printed.

**Audit the hardcoded count assertions in `tests/setup_env/update_summary.bats` by hand** — `CLAUDE.md` warns a mechanical `sed` pass over fixture loops misses them. The two are line 404 (`*"8 OK"*`) and line 461 (`*"1 OK"*`). Both write status files for an explicit section list rather than iterating `_UPDATE_SECTION_ORDER`, so adding a section should not change either count. Run the file and confirm rather than assuming; if a count does shift, update it to the measured value.

**Tests:**

- `run_update` with `_run_all=1` invokes `install_git_hooks_all_repos`
- **the sweep runs after `sync_git_repos`** — append-only marker log, assert ordering
- the sweep is NOT invoked under a scoped flag run (`--brew-only`)
- a sweep failure records `FAIL` for the `git-hooks` section
- `git-hooks` appears in `_UPDATE_SECTION_ORDER`
- `_update_summary` prints a `git-hooks` row when a status file exists for it

**Interfaces:**

- Consumes: `install_git_hooks_all_repos()`, `_update_record_start/end`.
- Produces: a `git-hooks` section in the update summary and in the state-ledger `_failure_stage` field.

---

### Task 7: ADR

```yaml-task
id: 7
description: Write ADR-0016 recording the cross-repo hook sweep as a structural pattern (docs-only, no behavior change)
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: test -f docs/adr/0016-auto-install-git-hooks.md
    exit_code: 0
  - cmd: 'grep -q "0016" docs/adr/README.md'
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched:
  - docs/adr/0016-auto-install-git-hooks.md
  - docs/adr/README.md
depends_on: [6]
parallel_group: docs
```

**Files:** `docs/adr/0016-auto-install-git-hooks.md` (new), `docs/adr/README.md`.

Nygard format — Context → Decision → Consequences → Related. Status `Accepted`. Next free number is 0016 (0015 is the highest present).

Content must record the four decisions a future reader would otherwise re-litigate:

1. **Discovery over a hardcoded repo list**, with the `-d .git` + `rev-parse --git-dir` pair and why neither test subsumes the other.
2. **Post-condition on the installed hooks directory, not the target's exit code** — with `state-ledger` as the worked example in both directions: its `pre-push`/`commit-msg` are true gaps, and its `ledger init`-installed `pre-commit` must pass.
3. **Content digest, never metadata** — with the measurement (`cp` rewrites mtime, content hash unchanged) and the note that the digest's informativeness is inversely coupled to the symlink-normalization backlog item.
4. **Asymmetric return-code handling** — fail-closed at `run_update`, return 0 at `run_setup_user`, because `_run_or_exit` would otherwise let a hook sweep abort a machine bootstrap.

Add the row to `docs/adr/README.md`'s status table.

**Interfaces:** none — documentation only.

---

### Task 8: Documentation sync

```yaml-task
id: 8
description: Update CLAUDE.md, the spec status banner, and the plan index (docs-only, no behavior change)
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: 'grep -q "git_hooks.sh" CLAUDE.md'
    exit_code: 0
  - cmd: 'grep -q "auto-install-git-hooks" docs/superpowers/README.md'
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched:
  - CLAUDE.md
  - docs/superpowers/README.md
  - docs/superpowers/plans/2026-07-28-auto-install-git-hooks.md
depends_on: [6]
parallel_group: docs
```

**Files:** `CLAUDE.md`, `docs/superpowers/README.md`, this plan file.

`CLAUDE.md` edits:

- Add `git_hooks.sh` to the `lib/` line in the Layout tree, and `hook_repos.sh` to the `config/` line.
- Add a Key Conventions bullet mirroring the existing `_UPDATE_SECTION_ORDER` coupling warning: the `git-hooks` section requires matching entries in both `run_update` and `_UPDATE_SECTION_ORDER`, and the hook sweep's post-condition reads the installed hooks directory, never `scripts/`.
- **Correct the sourcing-guard wording.** The Code Standards section currently says lib files must include the guard "near the top". That is wrong and actively harmful — the guard's condition is true when sourced, so at the top it returns before defining anything. Change it to state the guard belongs on the **last line, after all function definitions**, citing `lib/git_sync.sh:118` and `lib/legacy_rsync.sh:28` as the precedent. Caught during Task 1 when the implementer refused the instruction and verified the correct placement empirically.
- Update the Testing section's test count and the Coverage section's bash figure to the values measured after Task 6 — read them from the actual run, do not estimate.

`docs/superpowers/README.md` — set the `auto-install-git-hooks` row's Status to `Done` and link the plan file (the row currently reads "plan not yet written").

This plan file — add `> **Status: DONE**` at the top.

**Interfaces:** none — documentation only.

---

## Self-Review

1. **Spec coverage** — discovery + both filters (T1), expected-repos list (T1, T3), content digest (T2), post-condition (T3), fail-closed-not-fail-fast (T4), `make -s` (T4), dry-run `n/a` (T4), summary naming (T4), `setup_user` returns 0 (T5), `run_update` ordering + `_UPDATE_SECTION_ORDER` (T6), ADR (T7), docs (T8). No spec requirement is unmapped.
2. **Placeholder scan** — no TBD/TODO; every function body, fixture, and assertion is spelled out.
3. **Type consistency** — `_git_hooks_discover`, `_git_hooks_digest`, `_git_hooks_check_complete`, `_git_hooks_gap_repos`, `install_git_hooks_all_repos`, `HOOK_EXPECTED_REPOS`, `_GIT_HOOKS_MANDATED` used identically across tasks.
4. **YAML blocks** — every task has one; `make validate-plan` run below.
5. **TDD `files_touched` includes the test file** — T1–T6 all list their `.bats` file. T7/T8 are `tdd: not-applicable` with justification in `description`.
6. **Token budget** — every task block is under 2KB of YAML+prose; no BDD boilerplate.
7. **ADR significance** — yes, a new structural pattern with a HOLD-shaped post-condition; T7 covers it at plan time rather than deferring to post-merge.
8. **`files_touched` matches the prose** — T1 declares 3 files and describes 3; T5 declares `setup_env.sh` + `lib/workflows.sh` + tests and edits exactly those; T6 declares 4 and edits 4. No `model: haiku` tasks, so the single-file scope guard does not apply.
