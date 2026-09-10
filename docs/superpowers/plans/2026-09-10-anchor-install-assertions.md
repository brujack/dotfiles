# Anchor the pyenv install assertion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `tests/setup_env/linux_ubuntu.bats:127` fail when the `pyenv` brew install is deleted, and record the class-wide finding in the backlog.

**Architecture:** One assertion changes from a substring `grep -q` to a whole-line literal `grep -qxF`. A mutation script outside the repo proves the new assertion catches the deletion that the old one misses. The backlog gains one class row and loses the row this closes.

**Tech Stack:** bats 1.14.0 (macOS), GNU/BSD grep, Python 3 for the README edit.

**Spec:** `docs/superpowers/specs/2026-09-10-anchor-install-assertions-design.md` (approved through round 3, `91ec0e17`).

## Global Constraints

- All work happens in `/Users/bruce/git-repos/personal/dotfiles/.claude/worktrees/anchor-install-asserts/`. Do not `cd` anywhere else.
- No production code changes. `lib/` must be byte-identical to `origin/master` at the end.
- Run bats with stdin from `/dev/null`. Never pipe a test run into `head`/`tail` and trust the exit status.
- **Do not run `make test` inside a task.** The suite exceeded the 600s Bash cap at 1128 tests and now has 1626, so it would background and strand the task. The orchestrator runs it once after Task 2.
- **Do not use the Edit or Write tool on `docs/superpowers/README.md`.** A formatter hook rewrites the whole file (measured: 249 changed lines for a one-row edit). Use the Python script in Task 2.
- Never run `setup_env.sh` unmocked, and never run `scripts/sync_git_repos.sh`.
- Commit messages come from `caveman:caveman-commit`, with the attribution trailers from the session.

## Verification (session level)

1. `bash <scratchpad>/pyenv_mutation.sh` from the worktree root exits 0 after Task 1, and exited 1 on the unedited tree (measured before dispatch).
2. `make test` exits 0 with the test count unchanged (orchestrator, after Task 2).
3. The PR's CI `test` and `bash-coverage` jobs pass on `ubuntu-latest`.
4. `git diff --stat origin/master -- lib` is empty.

---

### Task 1: Anchor the pyenv assertion

```yaml-task
id: 1
description: Change linux_ubuntu.bats:127 to a whole-line literal match so deleting the pyenv install fails the test
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: 'bash /private/tmp/claude-501/-Users-bruce-git-repos-personal-dotfiles/4b198185-5d36-4281-966d-980cbe0713f0/scratchpad/pyenv_mutation.sh'
    exit_code: 0
  - cmd: 'grep -cF ''grep -qxF "brew install pyenv" "${MOCK_CALLS_FILE}"'' tests/setup_env/linux_ubuntu.bats'
    exit_code: 0
    stdout_match: '^1$'
  - cmd: 'git diff --numstat origin/master -- tests/setup_env/linux_ubuntu.bats'
    exit_code: 0
    stdout_match: '^1\s+1\s'
  - cmd: 'bats tests/setup_env/linux_ubuntu.bats </dev/null'
    exit_code: 0
  - cmd: 'make lint'
    exit_code: 0
max_retries: 3
files_touched:
  - tests/setup_env/linux_ubuntu.bats
depends_on: []
```

**Files:** Modify `tests/setup_env/linux_ubuntu.bats`, line 127 only.

**Steps:**

- [ ] **RED — show the defect.** From the worktree root, run the mutation script. It must print `working-tree assertion on mutant: ... ok 1` and exit **1**. An exit of 2 is an apparatus failure: stop and report it.
- [ ] **Edit.** Replace line 127
      `  grep -q "brew install pyenv" "${MOCK_CALLS_FILE}"`
      with
      `  grep -qxF "brew install pyenv" "${MOCK_CALLS_FILE}"`.
      Change nothing else in the file. Line 133 (`pyenv-virtualenv`) and line 139 (`uv`) stay as they are.
- [ ] **GREEN.** Re-run the mutation script: it must print `not ok 1` for the working-tree assertion, `ok 1` for origin/master's, and exit 0.
- [ ] Run every acceptance command above and paste each exit code.
- [ ] Commit only `tests/setup_env/linux_ubuntu.bats`.

**Interfaces:** Consumes nothing. Produces nothing later tasks use.

---

### Task 2: Backlog edits

```yaml-task
id: 2
description: Retire the closed backlog row, add the class row, reword the inherited-variables row (docs-only, no behaviour change, so tdd not-applicable)
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: 'grep -F "Unanchored mock-log greps can match a longer sibling line" docs/superpowers/README.md | grep -qF "specs/2026-09-10-anchor-install-assertions-design.md"'
    exit_code: 0
  - cmd: '! grep -qF "lets a real deletion pass" docs/superpowers/README.md'
    exit_code: 0
  - cmd: 'grep -qF ''the variables `detect_env` sets'' docs/superpowers/README.md'
    exit_code: 0
  - cmd: '! grep -qF ''exported `MACOS`/`LINUX`/`HAS_*`'' docs/superpowers/README.md'
    exit_code: 0
  - cmd: 'git diff --numstat origin/master -- docs/superpowers/README.md'
    exit_code: 0
    stdout_match: '^2\s+2\s'
max_retries: 3
files_touched:
  - docs/superpowers/README.md
depends_on: [1]
```

**Files:** Modify `docs/superpowers/README.md` (Backlog section) through the script below. Never through Edit or Write.

**Steps:**

- [ ] Save this script as `"${TMPDIR:-/tmp}/backlog_edit.py"` and run `python3 "${TMPDIR:-/tmp}/backlog_edit.py"` from the worktree root:

```python
import sys
PATH = "docs/superpowers/README.md"
RETIRE = "| `grep -q` in `tests/setup_env/linux_ubuntu.bats` lets a real deletion pass"
REWORD = "| Which tests pass only because the invoking shell exported `MACOS`/`LINUX`/`HAS_*` |"
AFTER = "| `tests/zshrc.d/unit.bats` Docker PATH tests lag their siblings |"
NEW_REWORD = ("| Which tests pass only because the invoking shell exported the variables `detect_env` sets | "
              "Unswept. `CLAUDE.md` was corrected in `bc18bb54`: `load_setup_env()` sets no OS vars, so "
              "tests inherit whatever `lib/detect_env.sh` would have set from the invoking shell. On a Mac "
              "several are empty regardless, so the sweep has to run on the workstation to discriminate. "
              "Row \"`profiles.bats` isolates absent-capability tests per-test\" covers one file's "
              "absent-capability case only. |")
CLASS = ("| Unanchored mock-log greps can match a longer sibling line | 397 `grep -q` checks against "
         "`MOCK_CALLS_FILE` in 16 files match substrings. In the 23-site install subset only `pyenv` "
         "collided, and it is fixed; an exact-match helper that prints the log on failure is the "
         "candidate class fix. Counting command and measurements: "
         "[spec](specs/2026-09-10-anchor-install-assertions-design.md). |")
lines = open(PATH, encoding="utf-8").read().split("\n")
def one(prefix):
    hits = [i for i, l in enumerate(lines) if l.startswith(prefix)]
    if len(hits) != 1:
        sys.exit(f"expected one line starting {prefix!r}, found {len(hits)}")
    return hits[0]
r, w, a = one(RETIRE), one(REWORD), one(AFTER)
lines[w] = NEW_REWORD
lines.insert(a + 1, CLASS)
del lines[r]
open(PATH, "w", encoding="utf-8").write("\n".join(lines))
print("ok")
```

- [ ] Run every acceptance command above and paste each exit code.
- [ ] Commit only `docs/superpowers/README.md`.

**Interfaces:** Consumes Task 1's commit only through ordering. Produces nothing later tasks use.
