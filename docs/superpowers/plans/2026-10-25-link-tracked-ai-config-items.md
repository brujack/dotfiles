# Link only tracked ai-config items Implementation Plan

spec: docs/superpowers/specs/2026-10-25-link-tracked-ai-config-items-design.md

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `setup_dotfile_symlinks` links an ai-config `.claude`/`.cursor` item only when git tracks it and it is not a home store, and warns (never removes) for stale links.

**Architecture:** a helper `_ai_config_tracked_items` (`lib/helpers.sh`) lists tracked first-path components via `${_AI_CONFIG_GIT:-git}` with the four `GIT_*` variables stripped. `_link_ai_config_subdir` replaces each glob loop and `_warn_stale_ai_config_links` emits the name-keyed remedy. `CLAUDE_HOME_STORES` (`lib/constants.sh`) names the never-linked stores. Tests get real-git fixtures through `track_ai_config_fixture` (`tests/helpers/common.bash`), and `load_mocks` defaults `_AI_CONFIG_GIT` and `_OVERRIDE_AI_CONFIG_DIR`.

**Tech Stack:** bash 5, bats, git.

## Global Constraints

- No symlink is removed automatically by this change (N1).
- No new doctor check (N2).
- `safe_link` is not modified (N3).
- No fallback to the glob when git fails (N4).
- Every git call in the helper runs as `env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE "${_AI_CONFIG_GIT:-git}" -C <dir> ...`.
- Fixtures are rooted under `BATS_TEST_TMPDIR`, never `HOME`; fixture repos are built with `git init` + `git add`, never `git commit` (CI has no `user.name`).
- Shell style per `~/.claude/standards/shell.md`: `[[ ]]`, `${VAR}`, `printf`, functions `|| return 1`.
- Sort with `LC_ALL=C` wherever output order is asserted.

## Verification

- Session-level: `make test </dev/null` exits 0, run once by the orchestrator after Task 2 and again after Task 3. Baseline on master `3305f3f7` (measured 2026-10-25 on `claude`): rc 0, 3345 `ok`, 0 `not ok`, 146 s, under the 600 s Bash cap.
- Task gates are scoped (`make lint` plus the touched bats files), because a full `make test` per task duplicates the orchestrator run.
- Mutation controls (Task 2, reported in its receipt and the PR body): restoring the `"${_ai_config_dir}/.claude/"*` glob turns the "untracked items are not linked" test red; deleting the empty-list check in `_ai_config_tracked_items` turns the "repo tracking nothing under .claude" test red.
- V1 and V2 run after merge (spec Requirements).

---

### Task 1: tracked-item helper, git seam and fixture builder

```yaml-task
id: 1
description: Add _ai_config_tracked_items with the _AI_CONFIG_GIT seam, the track_ai_config_fixture test helper and the load_mocks git default, with unit tests
role: executor
model: sonnet
tdd: required
requirements: [R5, R6, R9]
acceptance:
  - cmd: 'make lint < /dev/null'
    exit_code: 0
  - cmd: 'bats --jobs 12 tests/setup_env/install_guards.bats < /dev/null'
    exit_code: 0
max_retries: 3
files_touched: [lib/helpers.sh, tests/helpers/common.bash, tests/setup_env/install_guards.bats]
depends_on: []
```

**Files:** `lib/helpers.sh` (new helper beside `safe_link`), `tests/helpers/common.bash`, `tests/setup_env/install_guards.bats` (new `_ai_config_tracked_items` section).

**Behaviour** (`_ai_config_tracked_items <repo_dir> <subdir>`):

- Runs `ls-files -z -- <subdir>`, reads NUL-delimited, prints each distinct first component below `<subdir>/`, `LC_ALL=C` sorted, one per line. Drops names starting with `.`.
- rc 1 with nothing printed when git exits non-zero or the list is empty; rc 0 otherwise.

**Test helper** `track_ai_config_fixture <dir>`: creates `<dir>/.claude/settings.json` and `<dir>/.cursor/rules/.gitkeep` if absent, writes `.gitkeep` into every empty directory under `.claude` and `.cursor`, then runs `git init -q` and `git add -A` in `<dir>` with `GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null` and the four `GIT_*` stripped, using `${_AI_CONFIG_GIT}`. `load_mocks` exports `_AI_CONFIG_GIT` as the absolute path of the real git, resolved with `tests/mocks` removed from `PATH`, before its `PATH` prepend.

**Tests (RED first):**

1. Fixture tracking `.claude/a`, `.claude/b/x`, `.claude/c/.gitkeep`: output is exactly `a`, `b`, `c`.
2. A tracked `.claude/.hidden` is not printed.
3. Untracked `.claude/u` is not printed.
4. Non-repo dir: rc 1, empty stdout.
5. Repo tracking only `.cursor/x`: `<dir> .claude` gives rc 1.
6. Exported `GIT_DIR` pointing at a second fixture repo: output still the first repo's names.

**Interfaces:**

- Produces: `_ai_config_tracked_items <repo_dir> <subdir>` (stdout names, rc 0/1); `track_ai_config_fixture <dir>`; exported `_AI_CONFIG_GIT`.

---

### Task 2: allowlist loops, home stores and stale-link warning

```yaml-task
id: 2
description: Replace both glob loops with the tracked allowlist, add CLAUDE_HOME_STORES, fail closed, warn on stale links, migrate existing fixtures and default _OVERRIDE_AI_CONFIG_DIR in load_mocks
role: executor
model: sonnet
tdd: required
requirements: [R1, R2, R3, R4, R7, R8, R11, R12]
acceptance:
  - cmd: 'make lint < /dev/null'
    exit_code: 0
  - cmd: 'bats --jobs 12 tests/setup_env/install_guards.bats tests/setup_env/extracted_functions.bats tests/setup_env/workflows.bats tests/setup_env/unit.bats tests/setup_env/developer.bats < /dev/null'
    exit_code: 0
max_retries: 3
files_touched: [lib/helpers.sh, lib/constants.sh, tests/helpers/common.bash, tests/setup_env/install_guards.bats, tests/setup_env/extracted_functions.bats, tests/setup_env/workflows.bats, tests/setup_env/unit.bats, tests/setup_env/developer.bats]
depends_on: [1]
```

**Files:** `lib/helpers.sh` (`setup_dotfile_symlinks`, new `_link_ai_config_subdir`, `_warn_stale_ai_config_links`), `lib/constants.sh` (`readonly -a CLAUDE_HOME_STORES=(dod-log logs plugin-verdicts.json skill-log skip-ledger.jsonl)` with a comment naming the spec's Home stores section and the `telemetry_path.STREAMS`/`dispatch-log` carve-out), test files.

**Behaviour:** follow spec §§ Home stores, The two loops, Stale-link warning exactly.

- `.claude` skips `projects`, `rules` and `CLAUDE_HOME_STORES`; `.cursor` skips `User`. An absent-on-disk tracked item is skipped.
- On helper failure: no item and no explicit link (`projects` for `.claude`, `rules` for `.cursor`) from that subdir. `log_error` names the directory and says the remaining `setup_user` steps will be skipped; the rest of the function runs; the function returns 1 at its end.
- The warning matches only `readlink` text equal to `<ai_config_dir>/<subdir>/<name>`. Remedy for a home-store dir with contents: `rm <link> && mkdir <link> && cp -a <target>/. <link>/`; for a home-store file: `rm <link> && cp -a <target> <link>`; otherwise `rm <link>`.

**Fixture migration:** `load_mocks` defaults `_OVERRIDE_AI_CONFIG_DIR` to `${BATS_TEST_TMPDIR}/ai-config-default` built with `track_ai_config_fixture`. In `extracted_functions.bats` call `track_ai_config_fixture "${FAKE_AI_CONFIG_SRC}"` at the end of `_make_fake_dotfiles`. In `install_guards.bats` call it before each `setup_dotfile_symlinks` run whose fixture should link. Update tests asserting `.cursor/plugins` is linked: it is untracked in the real repo, so make the fixture track a different item instead of weakening the assertion. Count both groups with `grep -c` before editing and report the counts.

**New tests:** spec Testing cases 1-8 and 10-12, all asserting exact `readlink` text. Case 6: the stale link still exists and exactly one warning line names it. Case 12: no `~/.claude/dod-log.bak` appears.

**Interfaces:**

- Consumes: Task 1's helper, `track_ai_config_fixture`, `_AI_CONFIG_GIT`.
- Produces: `CLAUDE_HOME_STORES`; `setup_dotfile_symlinks` rc 1 on helper failure.

---

### Task 3: CLAUDE.md, seam pointer and plan index

```yaml-task
id: 3
description: Document the tracked-only rule and stale-link warning in CLAUDE.md Symlink Strategy and add the two seam lines (docs-only, no behaviour change)
role: executor
model: sonnet
tdd: not-applicable
requirements: [R10]
acceptance:
  - cmd: 'make lint < /dev/null'
    exit_code: 0
  - cmd: 'grep -qE "git tracks" CLAUDE.md'
    exit_code: 0
  - cmd: 'grep -q "_AI_CONFIG_GIT" CLAUDE.md'
    exit_code: 0
max_retries: 2
files_touched: [CLAUDE.md, docs/superpowers/README.md]
depends_on: [2]
```

**Files:** `CLAUDE.md` § Symlink Strategy: the `.claude/` and `.cursor/` bullets say only items git tracks in ai-config are linked, `CLAUDE_HOME_STORES` names are never linked, and stale links are warned about, not removed. § Test Seams: one line each for `_AI_CONFIG_GIT` (load_mocks points it at real git; never `tests/mocks/git`) and the load_mocks `_OVERRIDE_AI_CONFIG_DIR` default (a test needing a different ai-config overrides it and calls `track_ai_config_fixture`). `docs/superpowers/README.md`: move the Backlog row "`setup_dotfile_symlinks` links whatever runtime state…" out of P2 (strike-through or delete per the file's convention for shipped rows) and set this plan's index row Status. The ai-config knowledge entries (`dotfiles-test-seams.md`, `dotfiles-conventions.md`) are V2, post-merge.

Before editing, grep `tests/` for any asserted phrase from the Symlink Strategy section (`grep -rn 'Symlink Strategy\|symlink each ai-config' tests/`) and leave asserted text intact.

**Interfaces:** none.

## Non-goal check

Fresh reviewer, 2026-10-25, against N1-N4 from `spec_contract.py`: CLEAR 4, CONFLICT 0, UNCLEAR 0.

- N1 CLEAR: the `rm <link>` remedies are warning text only; no task executes them.
- N2 CLEAR: no task adds a doctor check.
- N3 CLEAR: the new helper sits beside `safe_link`, which is never modified.
- N4 CLEAR: git failure returns rc 1 and fails closed; the glob reappears only as a temporary mutation control.
