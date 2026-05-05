---
name: project_bats_infrastructure
description: BATS testing infrastructure for math repo hook scripts (PR #44, 2026-05-05)
type: project
originSessionId: f3e36aa9-ad21-40c4-9371-fd95942b6af6
---

## What was built (PR #44, 2026-05-05)

### Infrastructure files

- `tests/helpers/common.bash` — sets `REPO_ROOT` two levels up from the file; provides `load_mocks()` which prepends `tests/mocks/` to PATH
- `tests/mocks/make` — logs `make <args>` to `$MOCK_CALLS_FILE`, exits `$MOCK_MAKE_EXIT` (default 0)
- `tests/mocks/git` — logs calls, dispatches output by subcommand: `--show-toplevel` → `$MOCK_GIT_SHOW_TOPLEVEL`, `merge-base` → `$MOCK_GIT_MERGE_BASE` (default abc123), `rev-list` → `$MOCK_GIT_REV_LIST`, `diff` → `$MOCK_GIT_DIFF_NAMES`
- `tests/mocks/ggshield` — logs calls, exits `$MOCK_GGSHIELD_EXIT` (default 0)
- `make test-hooks` runs `bats --recursive tests/`
- CI: `.github/workflows/scripts.yml` installs bats via apt and runs the test suite

### Key non-obvious patterns

**1. Testing "command not on PATH" (e.g. ggshield absent)**

**Why:** `load_mocks()` puts `tests/mocks/` on PATH, so the ggshield mock is always found. To simulate ggshield being absent, you need a PATH without that directory.

**How to apply:** Create a temp mock dir with only the needed commands (symlinks to real mocks), strip `tests/mocks/` from PATH using:

```bash
custom_path="$(printf '%s' "$PATH" | tr ':' '\n' | grep -v "${REPO_ROOT}/tests/mocks" | paste -sd: -)"
```

Then run the hook with that custom PATH via `env "PATH=${custom_path}" bash scripts/pre-commit`.

**2. Worktree-safety proof**

**Why:** The pre-push hook must use the active worktree root (from `git rev-parse --show-toplevel`), not a hardcoded repo path. Without an explicit test, a regression could silently run tests in the wrong directory.

**How to apply:** Set `$MOCK_GIT_SHOW_TOPLEVEL` to a fake path like `${BATS_TEST_TMPDIR}/fake-worktree` and assert `make` is called with that fake path prefix — confirms the hook used the worktree root rather than hardcoded main repo path.

**3. Stderr capture without `--separate-stderr`**

**Why:** The bats version installed via apt may be older than the version on the developer's machine and may not support `--separate-stderr`. Tests that need to check stderr output cannot rely on `$stderr` being populated by `run`.

**How to apply:** Use direct bash invocation with `|| rc=$?` pattern and redirect stderr to a temp file:

```bash
local rc=0 stderr_file
stderr_file="$(mktemp)"
bash scripts/pre-push < /dev/null 2>"${stderr_file}" || rc=$?
grep -q "expected string" "${stderr_file}"
rm -f "${stderr_file}"
```
