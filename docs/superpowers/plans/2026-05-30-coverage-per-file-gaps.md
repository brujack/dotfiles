# Coverage: Per-File Gaps (helpers.sh + workflows.sh) Implementation Plan

> **Status: DONE**

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Raise helpers.sh (86%→≥90%) and workflows.sh (85%→≥90%) by adding 12 BATS tests targeting specific uncovered branches.

**Architecture:** Tests only — no production code changes. 4 tests in `install_guards.bats`, 5 tests in `unit.bats`, 3 tests in `workflows.bats`. All tests use existing patterns: PATH-injected mocks, `MOCK_*` env vars, direct function calls for counter assertions, and per-test stubs in `BATS_TEST_TMPDIR`.

**Tech Stack:** BATS (bash), PATH-injected mocks, direct function calls, `_DOCTOR_*` counter assertions.

---

## File Structure

| File                                  | Change                                                                                                    |
| ------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| `tests/setup_env/install_guards.bats` | Add 4 root guard tests (brew_install_formula, brew_tap_if_missing, brew_tap_installed, brew_install_cask) |
| `tests/setup_env/unit.bats`           | Add 5 tests: 3 real `_doctor_check_cred_dirs`, 2 real `_doctor_check_versions`                            |
| `tests/setup_env/workflows.bats`      | Add 3 tests: setup_claude_mcp local.sh, run_developer_or_ansible Linux, run_update neither-OS             |

---

### Task 1: brew root guard tests in install_guards.bats

**Files:**

- Modify: `tests/setup_env/install_guards.bats`

These cover `return 1` at helpers.sh lines 141, 151, 161, 169 — the `! ensure_not_root` branches in brew_install_formula, brew_install_cask, brew_tap_installed, and brew_tap_if_missing. All use the same pattern as the existing `brew_update returns 1 when running as root` test.

- [ ] **Step 1: Add 4 tests to `tests/setup_env/install_guards.bats`**

**Insertion 1** — find the closing `}` of:

```
@test "brew_install_formula does not call brew install when formula is present" {
```

Append after that `}`, before `# ── brew_tap_if_missing ──`:

```bash
@test "brew_install_formula returns 1 when root" {
  export MOCK_ID_U=0
  run brew_install_formula git
  [ "$status" -eq 1 ]
}
```

**Insertion 2** — find the closing `}` of:

```
@test "brew_tap_if_missing does not call brew tap when tap is present" {
```

Append after that `}`, before `# ── install_bats ──`:

```bash
@test "brew_tap_if_missing returns 1 when root" {
  export MOCK_ID_U=0
  run brew_tap_if_missing hashicorp/tap
  [ "$status" -eq 1 ]
}
```

**Insertion 3** — find the closing `}` of:

```
@test "brew_tap_installed returns 1 when tap is not listed" {
```

Append after that `}`, before `# ── brew_install_cask ──`:

```bash
@test "brew_tap_installed returns 1 when root" {
  export MOCK_ID_U=0
  run brew_tap_installed hashicorp/tap
  [ "$status" -eq 1 ]
}
```

**Insertion 4** — find the closing `}` of:

```
@test "brew_install_cask does not call brew install when cask is present" {
```

Append after that `}`, before `# ── brew_update ──`:

```bash
@test "brew_install_cask returns 1 when root" {
  export MOCK_ID_U=0
  run brew_install_cask docker
  [ "$status" -eq 1 ]
}
```

- [ ] **Step 2: Run tests to verify they pass**

```bash
bats tests/setup_env/install_guards.bats
```

Expected: all tests pass including the 4 new ones.

- [ ] **Step 3: Commit**

```bash
git add tests/setup_env/install_guards.bats
git commit -m "test(helpers): cover brew_install/tap root guard return paths"
```

---

### Task 2: \_doctor_check_cred_dirs real implementation tests

**Files:**

- Modify: `tests/setup_env/unit.bats`

The existing tests at lines 923 and 955 use **inline function overrides** — they never invoke the real `_doctor_check_cred_dirs`. These new tests call the actual function, covering helpers.sh lines 388–400 (dir missing, macOS stat pass, macOS stat fail).

Setup: `export HOME="${TMPDIR_TEST}"` so dirs under `~/.aws`, `~/.tf_creds`, `~/.ssh`, `~/.tsh` point to the test tmpdir. `MACOS` is already set by `load_setup_env()` on macOS test machines, so `stat -f '%OLp'` is used.

- [ ] **Step 1: Add 3 tests to `tests/setup_env/unit.bats`**

Find the closing `}` of:

```
@test "_doctor_check_cred_dirs fails when dir is missing" {
```

Append after that `}`, before `# ── _doctor_check_versions ──`:

```bash
@test "_doctor_check_cred_dirs real: fails when all credential dirs are missing" {
  _DOCTOR_FAIL=0; _DOCTOR_FAILED=0; _DOCTOR_PASS=0; _DOCTOR_WARN=0
  export HOME="${TMPDIR_TEST}"
  # No dirs created — all four dirs are absent
  _doctor_check_cred_dirs
  [ "${_DOCTOR_FAILED}" -ge 4 ]
  [ "${_DOCTOR_PASS}" -eq 0 ]
}

@test "_doctor_check_cred_dirs real: passes when all dirs have correct 700 perms" {
  _DOCTOR_FAIL=0; _DOCTOR_FAILED=0; _DOCTOR_PASS=0; _DOCTOR_WARN=0
  export HOME="${TMPDIR_TEST}"
  mkdir -p "${TMPDIR_TEST}/.aws" "${TMPDIR_TEST}/.tf_creds" "${TMPDIR_TEST}/.ssh" "${TMPDIR_TEST}/.tsh"
  chmod 700 "${TMPDIR_TEST}/.aws" "${TMPDIR_TEST}/.tf_creds" "${TMPDIR_TEST}/.ssh" "${TMPDIR_TEST}/.tsh"
  _doctor_check_cred_dirs
  [ "${_DOCTOR_PASS}" -eq 4 ]
  [ "${_DOCTOR_FAILED}" -eq 0 ]
}

@test "_doctor_check_cred_dirs real: fails when a dir has wrong perms" {
  _DOCTOR_FAIL=0; _DOCTOR_FAILED=0; _DOCTOR_PASS=0; _DOCTOR_WARN=0
  export HOME="${TMPDIR_TEST}"
  mkdir -p "${TMPDIR_TEST}/.aws" "${TMPDIR_TEST}/.tf_creds" "${TMPDIR_TEST}/.ssh" "${TMPDIR_TEST}/.tsh"
  chmod 700 "${TMPDIR_TEST}/.aws" "${TMPDIR_TEST}/.tf_creds" "${TMPDIR_TEST}/.tsh"
  chmod 755 "${TMPDIR_TEST}/.ssh"
  _doctor_check_cred_dirs
  [ "${_DOCTOR_FAILED}" -ge 1 ]
  [ "${_DOCTOR_PASS}" -ge 3 ]
}
```

- [ ] **Step 2: Run tests to verify they pass**

```bash
bats tests/setup_env/unit.bats --filter "_doctor_check_cred_dirs"
```

Expected: all 5 tests (2 existing + 3 new) pass.

- [ ] **Step 3: Commit**

```bash
git add tests/setup_env/unit.bats
git commit -m "test(helpers): cover _doctor_check_cred_dirs real implementation paths"
```

---

### Task 3: \_doctor_check_versions real implementation tests

**Files:**

- Modify: `tests/setup_env/unit.bats`

The existing tests at lines 975 and 994 use **inline function overrides** — they never invoke the real `_doctor_check_versions`. `_doctor_check_one_version` is nested inside `_doctor_check_versions` and can only be tested by calling the outer function. Two uncovered paths:

1. Tool not installed → `log_warn "${_tool}: not installed"` (helpers.sh lines 409–411)
2. Version string unparseable → `log_warn "${_tool}: could not parse version from '${_raw}'"` (helpers.sh lines 416–418)

**Test 1** uses an empty PATH dir so `command -v go/python3/zsh` all fail. `log_warn` only calls `printf`, so no PATH lookup is needed for that path; `grep` and `head` are never reached.

**Test 2** creates a `go` stub outputting garbage in `BATS_TEST_TMPDIR`. `grep -oE "[0-9]+\.[0-9]+..."` finds no match → `_installed` is empty → `log_warn` "could not parse".

In both tests `_DOCTOR_FAILED` must stay 0 — warnings are non-fatal.

- [ ] **Step 1: Add 2 tests to `tests/setup_env/unit.bats`**

Find the closing `}` of:

```
@test "_doctor_check_versions fails when installed version differs from pinned" {
```

Append after that `}`, before `# ── _doctor_check_symlink_roots ──`:

```bash
@test "_doctor_check_versions real: warns when tools are not installed" {
  _DOCTOR_FAIL=0; _DOCTOR_FAILED=0; _DOCTOR_PASS=0; _DOCTOR_WARN=0
  local _saved_path="$PATH"
  local _empty="${BATS_TEST_TMPDIR}/empty_tools"
  mkdir -p "${_empty}"
  export PATH="${_empty}"  # no binaries here — command -v go/python3/ruby/zsh all fail
  local _rc=0
  _doctor_check_versions 2>&1 || _rc=$?
  export PATH="${_saved_path}"
  [ "${_rc}" -eq 0 ]
  [ "${_DOCTOR_FAILED}" -eq 0 ]
}

@test "_doctor_check_versions real: warns when version output cannot be parsed" {
  _DOCTOR_FAIL=0; _DOCTOR_FAILED=0; _DOCTOR_PASS=0; _DOCTOR_WARN=0
  local _tmp="${BATS_TEST_TMPDIR}/version_tools"
  mkdir -p "${_tmp}"
  printf '#!/usr/bin/env bash\nprintf "go: totally unparseable output\n"\n' > "${_tmp}/go"
  chmod +x "${_tmp}/go"
  export PATH="${_tmp}:${PATH}"
  local _rc=0
  _doctor_check_versions 2>&1 || _rc=$?
  [ "${_rc}" -eq 0 ]
  [ "${_DOCTOR_FAILED}" -eq 0 ]
}
```

- [ ] **Step 2: Run tests to verify they pass**

```bash
bats tests/setup_env/unit.bats --filter "_doctor_check_versions"
```

Expected: all 4 tests (2 existing + 2 new) pass.

- [ ] **Step 3: Commit**

```bash
git add tests/setup_env/unit.bats
git commit -m "test(helpers): cover _doctor_check_versions real tool-absent and parse-failure paths"
```

---

### Task 4: workflows.sh coverage gaps in workflows.bats

**Files:**

- Modify: `tests/setup_env/workflows.bats`

Three uncovered branches in workflows.sh:

1. **Line 13** (`source "${_local_config}" || true`): `setup_claude_mcp` sources `config/local.sh` when it exists. No existing test creates this file.
2. **Lines 175–176, 178–180** (`run_developer_or_ansible` Linux path + setup_ansible/clone_personal_repos): All existing tests have at least one callee fail before reaching setup_ansible. No test exercises the success path with LINUX=1.
3. **Lines 236–237** (`run_update` neither-macOS-nor-Linux path): `_update_skip "brew" "not macOS or Linux"` is never called; all existing tests set either MACOS or LINUX.

Setup note: `PERSONAL_GITREPOS="${BATS_TEST_TMPDIR}/git-repos/personal"` and `DOTFILES="dotfiles"` are set by `workflows.bats` `setup()`. `BREWFILE_LOC="${BATS_TEST_TMPDIR}/brew"` is also set. `_UPDATE_TMPDIR` is exported by `run_update` itself before calling `_update_skip`, so the status files are accessible after calling `run_update` directly.

- [ ] **Step 1: Add 3 tests to `tests/setup_env/workflows.bats`**

**Insertion 1** — find the closing `}` of:

```
@test "setup_claude_mcp returns 1 when envsubst fails" {
```

Append after that `}`, before `# ── run_setup_user ──`:

```bash
@test "setup_claude_mcp sources config/local.sh to read GITHUB_PAT" {
  export _OVERRIDE_AI_CONFIG_DIR="${BATS_TEST_TMPDIR}/ai-config"
  mkdir -p "${_OVERRIDE_AI_CONFIG_DIR}/.claude"
  printf '{"auth":"Bearer ${GITHUB_PAT}"}\n' \
    > "${_OVERRIDE_AI_CONFIG_DIR}/.claude/mcp.json.template"
  mkdir -p "${PERSONAL_GITREPOS}/${DOTFILES}/config"
  printf 'export GITHUB_PAT="pat-from-local-sh"\n' \
    > "${PERSONAL_GITREPOS}/${DOTFILES}/config/local.sh"
  unset GITHUB_PAT
  setup_claude_mcp
  grep -q "pat-from-local-sh" "${HOME}/.claude/mcp.json"
}
```

**Insertion 2** — find the closing `}` of:

```
@test "run_developer_or_ansible does not call setup_ansible when setup_kitchen fails" {
```

Append after that `}`, before `# ── process_args --pkgs-only ──`:

```bash
@test "run_developer_or_ansible succeeds on Linux calling setup_ansible and clone_personal_repos" {
  export LINUX=1
  unset MACOS UBUNTU
  install_ruby_tools()       { return 0; }
  install_ruby()             { return 0; }
  install_github_cli_linux() { printf "github_cli_linux\n" >> "${MOCK_CALLS_FILE}"; return 0; }
  setup_kitchen()            { return 0; }
  setup_ansible()            { printf "setup_ansible\n" >> "${MOCK_CALLS_FILE}"; return 0; }
  clone_personal_repos()     { printf "clone_repos\n" >> "${MOCK_CALLS_FILE}"; return 0; }
  run run_developer_or_ansible
  [ "$status" -eq 0 ]
  grep -q "github_cli_linux" "${MOCK_CALLS_FILE}"
  grep -q "setup_ansible" "${MOCK_CALLS_FILE}"
  grep -q "clone_repos" "${MOCK_CALLS_FILE}"
}
```

**Insertion 3** — find the closing `}` of:

```
@test "run_update skips softwareupdate on Linux" {
```

Append after that `}`, before `# ── return-code propagation: run_setup_user ──`:

```bash
@test "run_update skips brew when neither macOS nor Linux" {
  unset MACOS LINUX UBUNTU
  export UPDATE_BREW=1
  export UPDATE_LOG_PATH="${BATS_TEST_TMPDIR}/update.log"
  run_update
  grep -q "SKIP" "${_UPDATE_TMPDIR}/status_brew"
  grep -q "not macOS or Linux" "${_UPDATE_TMPDIR}/result_brew"
}
```

- [ ] **Step 2: Run tests to verify they pass**

```bash
bats tests/setup_env/workflows.bats --filter "sources config/local.sh\|succeeds on Linux\|skips brew when neither"
```

Expected: all 3 new tests pass.

- [ ] **Step 3: Run full workflows suite**

```bash
bats tests/setup_env/workflows.bats
```

Expected: all tests pass (no regressions).

- [ ] **Step 4: Commit**

```bash
git add tests/setup_env/workflows.bats
git commit -m "test(workflows): cover local.sh source, Linux path, and neither-OS skip"
```

---

### Task 5: Verify full suite and open PR

**Files:** none

- [ ] **Step 1: Run full test suite**

```bash
make test
```

Expected: all 705 tests pass (693 before + 12 new).

- [ ] **Step 2: Open PR**

```bash
gh pr create --title "test(coverage): raise helpers.sh and workflows.sh coverage to ≥90%" --body "$(cat <<'EOF'
## Summary
- Add 12 BATS tests targeting specific uncovered branches in `helpers.sh` and `workflows.sh`
- No production code changes
- helpers.sh: cover `brew_install_formula/cask` and `brew_tap_installed/if_missing` root guards; `_doctor_check_cred_dirs` real implementation (dir missing, correct 700, wrong perms); `_doctor_check_versions` real implementation (tool absent, parse failure)
- workflows.sh: cover `setup_claude_mcp` local.sh source path; `run_developer_or_ansible` Linux success path; `run_update` neither-macOS-nor-Linux brew skip

## Test Plan
- [ ] `make test` passes (705 tests)
- [ ] `make bash-coverage` confirms helpers.sh ≥90%, workflows.sh ≥90%
EOF
)"
```

- [ ] **Step 3: Monitor CI until green**

```bash
gh pr checks --watch
```

Expected: all checks pass, PR auto-merges.

- [ ] **Step 4: Post-merge cleanup** _(Do this directly on main after the PR merges — not inside the worktree)_

```bash
# On main branch (not in worktree):
# 1. Update docs/superpowers/README.md: add coverage-per-file-gaps row (Done)
# 2. Add > **Status: DONE** banner to this plan file
# 3. Update CLAUDE.md: change test count from 693 to 705
# 4. Push the docs commits immediately
git add docs/superpowers/README.md docs/superpowers/plans/2026-05-30-coverage-per-file-gaps.md CLAUDE.md
git commit -m "docs(coverage): mark coverage-per-file-gaps Done, 705 tests"
git push origin master
```
