# Update Summary Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a structured end-of-run summary to `./setup_env.sh -t update` showing per-section status and exactly what changed, with history appended to `~/.dotfiles-update.log`.

**Architecture:** New `lib/update_summary.sh` contains all summary infrastructure — snapshot capture, diffing, result tracking, formatted output. `run_update()` in `lib/workflows.sh` wraps each section with `_update_record_start`/`_update_record_end` calls. A temp directory holds per-section snapshot files; `_update_summary` reads them to build the report.

**Tech Stack:** Bash, BATS testing, `comm`/`diff` for line diffs, `git log` for git-based sections.

---

### Task 1: Scaffolding and pure diff utilities

**Files:**

- Create: `lib/update_summary.sh`
- Create: `tests/setup_env/update_summary.bats`
- Modify: `setup_env.sh:29-35` (add source line)

- [ ] **Step 1: Write failing tests for `_update_diff_lines`**

Add to `tests/setup_env/update_summary.bats`:

```bash
#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "${REPO_ROOT}/tests/helpers/common.bash"
  load_mocks
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  touch "${MOCK_CALLS_FILE}"
  load_setup_env
  export _UPDATE_TMPDIR="${BATS_TEST_TMPDIR}"
  export UPDATE_LOG_PATH="${BATS_TEST_TMPDIR}/update.log"
}

teardown() {
  :
}

# ── _update_diff_lines ────────────────────────────────────────────────────────

@test "_update_diff_lines returns changed lines between pre and post" {
  printf "git 2.44.0\nwget 1.21.3\ncurl 8.6.0\n" > "${BATS_TEST_TMPDIR}/pre"
  printf "git 2.45.0\nwget 1.21.3\ncurl 8.7.1\n" > "${BATS_TEST_TMPDIR}/post"
  run _update_diff_lines "${BATS_TEST_TMPDIR}/pre" "${BATS_TEST_TMPDIR}/post"
  [ "$status" -eq 0 ]
  [[ "$output" == *"git 2.45.0"* ]]
  [[ "$output" == *"curl 8.7.1"* ]]
  [[ "$output" != *"wget"* ]]
}

@test "_update_diff_lines returns empty when no changes" {
  printf "git 2.44.0\nwget 1.21.3\n" > "${BATS_TEST_TMPDIR}/pre"
  printf "git 2.44.0\nwget 1.21.3\n" > "${BATS_TEST_TMPDIR}/post"
  run _update_diff_lines "${BATS_TEST_TMPDIR}/pre" "${BATS_TEST_TMPDIR}/post"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "_update_diff_lines returns new lines added in post" {
  printf "git 2.44.0\n" > "${BATS_TEST_TMPDIR}/pre"
  printf "git 2.44.0\nnode 20.12.0\n" > "${BATS_TEST_TMPDIR}/post"
  run _update_diff_lines "${BATS_TEST_TMPDIR}/pre" "${BATS_TEST_TMPDIR}/post"
  [ "$status" -eq 0 ]
  [[ "$output" == *"node 20.12.0"* ]]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bats tests/setup_env/update_summary.bats`
Expected: FAIL — `_update_diff_lines: command not found`

- [ ] **Step 3: Write failing test for `_update_snapshot`**

Append to `tests/setup_env/update_summary.bats`:

```bash
# ── _update_snapshot ──────────────────────────────────────────────────────────

@test "_update_snapshot writes command stdout to pre_SECTION file" {
  _update_snapshot "testcmd" printf "hello world\n"
  [ -f "${_UPDATE_TMPDIR}/pre_testcmd" ]
  grep -q "hello world" "${_UPDATE_TMPDIR}/pre_testcmd"
}

@test "_update_snapshot overwrites existing snapshot file" {
  printf "old\n" > "${_UPDATE_TMPDIR}/pre_testcmd"
  _update_snapshot "testcmd" printf "new\n"
  grep -q "new" "${_UPDATE_TMPDIR}/pre_testcmd"
  ! grep -q "old" "${_UPDATE_TMPDIR}/pre_testcmd"
}
```

- [ ] **Step 4: Run tests to verify they fail**

Run: `bats tests/setup_env/update_summary.bats`
Expected: FAIL — `_update_snapshot: command not found`

- [ ] **Step 5: Create `lib/update_summary.sh` with `_update_diff_lines` and `_update_snapshot`**

Create `lib/update_summary.sh`:

```bash
#!/usr/bin/env bash
# lib/update_summary.sh — update run tracking and summary reporting

# Fixed section order for summary display
readonly _UPDATE_SECTION_ORDER=(
  brew softwareupdate mas claude pip gems
  oh-my-zsh p10k tpm tfenv cheat.sh
)

# _update_diff_lines PRE_FILE POST_FILE
# Outputs lines in POST_FILE that differ from PRE_FILE (new or changed).
_update_diff_lines() {
  local _pre="$1" _post="$2"
  comm -13 <(sort "${_pre}") <(sort "${_post}")
}

# _update_snapshot SECTION COMMAND...
# Runs COMMAND and writes stdout to ${_UPDATE_TMPDIR}/pre_SECTION.
_update_snapshot() {
  local _section="$1"
  shift
  "$@" > "${_UPDATE_TMPDIR}/pre_${_section}" 2>/dev/null || true
}
```

- [ ] **Step 6: Source `lib/update_summary.sh` in `setup_env.sh`**

Add after the `source "$(dirname "${BASH_SOURCE[0]}")/lib/developer.sh"` line (line 34) in `setup_env.sh`:

```bash
source "$(dirname "${BASH_SOURCE[0]}")/lib/update_summary.sh"
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `bats tests/setup_env/update_summary.bats`
Expected: All 5 tests PASS

- [ ] **Step 8: Run full test suite**

Run: `make test`
Expected: All tests pass (no regressions)

- [ ] **Step 9: Commit**

```bash
git add lib/update_summary.sh tests/setup_env/update_summary.bats setup_env.sh
git commit -m "feat: add update_summary.sh scaffolding with diff and snapshot utilities"
```

---

### Task 2: Git diff utility

**Files:**

- Modify: `lib/update_summary.sh`
- Modify: `tests/setup_env/update_summary.bats`

- [ ] **Step 1: Write failing tests for `_update_git_diff`**

Append to `tests/setup_env/update_summary.bats`:

```bash
# ── _update_git_diff ──────────────────────────────────────────────────────────

@test "_update_git_diff returns commit log between old SHA and HEAD" {
  # Create a real git repo with two commits
  local _repo="${BATS_TEST_TMPDIR}/gitrepo"
  mkdir -p "${_repo}"
  local clean_path
  clean_path="$(printf "%s" "${PATH}" | tr ':' '\n' | grep -v "tests/mocks" | tr '\n' ':' | sed 's/:$//')"
  bash -c "
    export PATH='${clean_path}'
    git -C '${_repo}' init --quiet
    git -C '${_repo}' config user.email 'test@test.com'
    git -C '${_repo}' config user.name 'Test'
    printf 'a\n' > '${_repo}/file.txt'
    git -C '${_repo}' add .
    git -C '${_repo}' commit --quiet -m 'first commit'
    printf 'b\n' > '${_repo}/file.txt'
    git -C '${_repo}' add .
    git -C '${_repo}' commit --quiet -m 'second commit'
  "
  local _old_sha
  _old_sha=$(bash -c "export PATH='${clean_path}'; git -C '${_repo}' log --format='%H' | tail -1")
  run bash -c "export PATH='${clean_path}'; source '${REPO_ROOT}/lib/update_summary.sh'; _update_git_diff '${_repo}' '${_old_sha}'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"second commit"* ]]
  [[ "$output" != *"first commit"* ]]
}

@test "_update_git_diff returns empty when no new commits" {
  local _repo="${BATS_TEST_TMPDIR}/gitrepo2"
  mkdir -p "${_repo}"
  local clean_path
  clean_path="$(printf "%s" "${PATH}" | tr ':' '\n' | grep -v "tests/mocks" | tr '\n' ':' | sed 's/:$//')"
  bash -c "
    export PATH='${clean_path}'
    git -C '${_repo}' init --quiet
    git -C '${_repo}' config user.email 'test@test.com'
    git -C '${_repo}' config user.name 'Test'
    printf 'a\n' > '${_repo}/file.txt'
    git -C '${_repo}' add .
    git -C '${_repo}' commit --quiet -m 'first commit'
  "
  local _sha
  _sha=$(bash -c "export PATH='${clean_path}'; git -C '${_repo}' rev-parse HEAD")
  run bash -c "export PATH='${clean_path}'; source '${REPO_ROOT}/lib/update_summary.sh'; _update_git_diff '${_repo}' '${_sha}'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bats tests/setup_env/update_summary.bats`
Expected: FAIL — `_update_git_diff: command not found`

- [ ] **Step 3: Implement `_update_git_diff`**

Add to `lib/update_summary.sh`:

```bash
# _update_git_diff DIR OLD_SHA
# Outputs git log from OLD_SHA to HEAD in DIR (one line per commit).
_update_git_diff() {
  local _dir="$1" _old_sha="$2"
  git -C "${_dir}" log "${_old_sha}..HEAD" --oneline 2>/dev/null
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bats tests/setup_env/update_summary.bats`
Expected: All 7 tests PASS

- [ ] **Step 5: Run full test suite**

Run: `make test`
Expected: All tests pass

- [ ] **Step 6: Commit**

```bash
git add lib/update_summary.sh tests/setup_env/update_summary.bats
git commit -m "feat: add _update_git_diff utility for git-based section diffs"
```

---

### Task 3: State tracking functions (`_update_record_start`, `_update_record_end`, `_update_skip`)

**Files:**

- Modify: `lib/update_summary.sh`
- Modify: `tests/setup_env/update_summary.bats`

- [ ] **Step 1: Write failing tests for `_update_skip`**

Append to `tests/setup_env/update_summary.bats`:

```bash
# ── _update_skip ──────────────────────────────────────────────────────────────

@test "_update_skip writes SKIP status and reason" {
  _update_skip "mas" "--brew-only flag set"
  [ -f "${_UPDATE_TMPDIR}/status_mas" ]
  grep -q "SKIP" "${_UPDATE_TMPDIR}/status_mas"
  [ -f "${_UPDATE_TMPDIR}/result_mas" ]
  grep -q "\-\-brew-only flag set" "${_UPDATE_TMPDIR}/result_mas"
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/setup_env/update_summary.bats`
Expected: FAIL — `_update_skip: command not found`

- [ ] **Step 3: Implement `_update_skip`**

Add to `lib/update_summary.sh`:

```bash
# _update_skip SECTION REASON
# Records a section as skipped with the given reason.
_update_skip() {
  local _section="$1" _reason="$2"
  printf "SKIP\n" > "${_UPDATE_TMPDIR}/status_${_section}"
  printf "%s\n" "${_reason}" > "${_UPDATE_TMPDIR}/result_${_section}"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats tests/setup_env/update_summary.bats`
Expected: PASS

- [ ] **Step 5: Write failing tests for `_update_record_start`**

Append to `tests/setup_env/update_summary.bats`:

```bash
# ── _update_record_start ──────────────────────────────────────────────────────

@test "_update_record_start creates pre-snapshot for brew section" {
  export MOCK_BREW_LIST_FORMULA="git wget"
  export MOCK_BREW_LIST_CASK="docker"
  _update_record_start "brew"
  [ -f "${_UPDATE_TMPDIR}/pre_brew_formula" ]
  [ -f "${_UPDATE_TMPDIR}/pre_brew_cask" ]
}

@test "_update_record_start creates pre-snapshot for gems section" {
  _update_record_start "gems"
  [ -f "${_UPDATE_TMPDIR}/pre_gems" ]
}

@test "_update_record_start records git SHA for oh-my-zsh section" {
  local _repo="${BATS_TEST_TMPDIR}/.oh-my-zsh"
  mkdir -p "${_repo}"
  local clean_path
  clean_path="$(printf "%s" "${PATH}" | tr ':' '\n' | grep -v "tests/mocks" | tr '\n' ':' | sed 's/:$//')"
  bash -c "
    export PATH='${clean_path}'
    git -C '${_repo}' init --quiet
    git -C '${_repo}' config user.email 'test@test.com'
    git -C '${_repo}' config user.name 'Test'
    printf 'a\n' > '${_repo}/file.txt'
    git -C '${_repo}' add .
    git -C '${_repo}' commit --quiet -m 'init'
  "
  _update_record_start "oh-my-zsh"
  [ -f "${_UPDATE_TMPDIR}/pre_oh-my-zsh" ]
}

@test "_update_record_start creates no snapshot for claude section" {
  _update_record_start "claude"
  [ ! -f "${_UPDATE_TMPDIR}/pre_claude" ]
}
```

- [ ] **Step 6: Run tests to verify they fail**

Run: `bats tests/setup_env/update_summary.bats`
Expected: FAIL — `_update_record_start: command not found`

- [ ] **Step 7: Write failing tests for `_update_record_end`**

Append to `tests/setup_env/update_summary.bats`:

```bash
# ── _update_record_end ────────────────────────────────────────────────────────

@test "_update_record_end with exit 0 writes OK status" {
  printf "" > "${_UPDATE_TMPDIR}/pre_brew_formula"
  printf "" > "${_UPDATE_TMPDIR}/pre_brew_cask"
  export MOCK_BREW_LIST_FORMULA="git"
  export MOCK_BREW_LIST_CASK=""
  _update_record_end "brew" 0
  [ -f "${_UPDATE_TMPDIR}/status_brew" ]
  grep -q "OK" "${_UPDATE_TMPDIR}/status_brew"
}

@test "_update_record_end with exit 1 writes FAIL status" {
  _update_record_end "claude" 1
  grep -q "FAIL" "${_UPDATE_TMPDIR}/status_claude"
  grep -q "exit 1" "${_UPDATE_TMPDIR}/result_claude"
}

@test "_update_record_end diffs brew formulae and reports changes" {
  printf "git 2.44.0\nwget 1.21.3\n" > "${_UPDATE_TMPDIR}/pre_brew_formula"
  printf "" > "${_UPDATE_TMPDIR}/pre_brew_cask"
  export MOCK_BREW_LIST_FORMULA="git 2.45.0\nwget 1.21.3"
  export MOCK_BREW_LIST_CASK=""
  _update_record_end "brew" 0
  grep -q "OK" "${_UPDATE_TMPDIR}/status_brew"
  grep -q "git 2.45.0" "${_UPDATE_TMPDIR}/result_brew"
}

@test "_update_record_end reports no changes when nothing changed" {
  printf "git 2.44.0\n" > "${_UPDATE_TMPDIR}/pre_brew_formula"
  printf "docker 4.28.0\n" > "${_UPDATE_TMPDIR}/pre_brew_cask"
  export MOCK_BREW_LIST_FORMULA="git 2.44.0"
  export MOCK_BREW_LIST_CASK="docker 4.28.0"
  _update_record_end "brew" 0
  grep -q "no changes" "${_UPDATE_TMPDIR}/result_brew"
}
```

- [ ] **Step 8: Implement `_update_record_start` and `_update_record_end`**

Add to `lib/update_summary.sh`:

```bash
# _update_record_start SECTION
# Takes pre-snapshot appropriate for the section type.
_update_record_start() {
  local _section="$1"
  case "${_section}" in
    brew)
      brew list --formula --versions > "${_UPDATE_TMPDIR}/pre_brew_formula" 2>/dev/null || true
      brew list --cask --versions > "${_UPDATE_TMPDIR}/pre_brew_cask" 2>/dev/null || true
      ;;
    mas)
      mas list > "${_UPDATE_TMPDIR}/pre_mas" 2>/dev/null || true
      ;;
    gems)
      gem list > "${_UPDATE_TMPDIR}/pre_gems" 2>/dev/null || true
      ;;
    pip)
      # pip snapshot is captured inside the Python block; nothing to do here
      ;;
    oh-my-zsh)
      git -C "${HOME}/.oh-my-zsh" rev-parse HEAD > "${_UPDATE_TMPDIR}/pre_oh-my-zsh" 2>/dev/null || true
      ;;
    p10k)
      git -C "${HOME}/.oh-my-zsh/custom/themes/powerlevel10k" rev-parse HEAD > "${_UPDATE_TMPDIR}/pre_p10k" 2>/dev/null || true
      ;;
    tpm)
      git -C "${HOME}/.tmux/plugins/tpm" rev-parse HEAD > "${_UPDATE_TMPDIR}/pre_tpm" 2>/dev/null || true
      ;;
    tfenv)
      git -C "${HOME}/.tfenv" rev-parse HEAD > "${_UPDATE_TMPDIR}/pre_tfenv" 2>/dev/null || true
      ;;
    zsh-autosuggestions)
      git -C "${HOME}/.oh-my-zsh/custom/plugins/zsh-autosuggestions" rev-parse HEAD > "${_UPDATE_TMPDIR}/pre_zsh-autosuggestions" 2>/dev/null || true
      ;;
    # claude, softwareupdate, cheat.sh — no pre-snapshot needed
    *) ;;
  esac
}

# _update_record_end SECTION EXIT_CODE
# Takes post-snapshot, diffs against pre, stores result and status.
_update_record_end() {
  local _section="$1" _exit="$2"
  local _result=""

  if [[ "${_exit}" -ne 0 ]]; then
    printf "FAIL\n" > "${_UPDATE_TMPDIR}/status_${_section}"
    printf "exit %d — see output above\n" "${_exit}" > "${_UPDATE_TMPDIR}/result_${_section}"
    return
  fi

  case "${_section}" in
    brew)
      local _formula_diff="" _cask_diff="" _formula_count=0 _cask_count=0
      brew list --formula --versions > "${_UPDATE_TMPDIR}/post_brew_formula" 2>/dev/null || true
      brew list --cask --versions > "${_UPDATE_TMPDIR}/post_brew_cask" 2>/dev/null || true
      if [[ -f "${_UPDATE_TMPDIR}/pre_brew_formula" ]]; then
        _formula_diff=$(_update_diff_lines "${_UPDATE_TMPDIR}/pre_brew_formula" "${_UPDATE_TMPDIR}/post_brew_formula")
        _formula_count=$(printf '%s' "${_formula_diff}" | grep -c . || true)
      fi
      if [[ -f "${_UPDATE_TMPDIR}/pre_brew_cask" ]]; then
        _cask_diff=$(_update_diff_lines "${_UPDATE_TMPDIR}/pre_brew_cask" "${_UPDATE_TMPDIR}/post_brew_cask")
        _cask_count=$(printf '%s' "${_cask_diff}" | grep -c . || true)
      fi
      if [[ ${_formula_count} -gt 0 ]] || [[ ${_cask_count} -gt 0 ]]; then
        if [[ ${_formula_count} -gt 0 ]]; then
          _result="${_formula_count} formulae ($(printf '%s' "${_formula_diff}" | paste -sd', ' -))"
        fi
        if [[ ${_cask_count} -gt 0 ]]; then
          [[ -n "${_result}" ]] && _result="${_result}\n"
          _result="${_result}${_cask_count} cask(s) ($(printf '%s' "${_cask_diff}" | paste -sd', ' -))"
        fi
      else
        _result="no changes"
      fi
      ;;
    mas)
      if [[ -f "${_UPDATE_TMPDIR}/pre_mas" ]]; then
        mas list > "${_UPDATE_TMPDIR}/post_mas" 2>/dev/null || true
        local _mas_diff
        _mas_diff=$(_update_diff_lines "${_UPDATE_TMPDIR}/pre_mas" "${_UPDATE_TMPDIR}/post_mas")
        local _mas_count
        _mas_count=$(printf '%s' "${_mas_diff}" | grep -c . || true)
        if [[ ${_mas_count} -gt 0 ]]; then
          _result="${_mas_count} app(s) updated"
        else
          _result="no changes"
        fi
      else
        _result="updated"
      fi
      ;;
    gems)
      if [[ -f "${_UPDATE_TMPDIR}/pre_gems" ]]; then
        gem list > "${_UPDATE_TMPDIR}/post_gems" 2>/dev/null || true
        local _gem_diff
        _gem_diff=$(_update_diff_lines "${_UPDATE_TMPDIR}/pre_gems" "${_UPDATE_TMPDIR}/post_gems")
        local _gem_count
        _gem_count=$(printf '%s' "${_gem_diff}" | grep -c . || true)
        if [[ ${_gem_count} -gt 0 ]]; then
          _result="${_gem_count} gem(s) ($(printf '%s' "${_gem_diff}" | paste -sd', ' -))"
        else
          _result="no changes"
        fi
      else
        _result="updated"
      fi
      ;;
    pip)
      if [[ -f "${_UPDATE_TMPDIR}/pip_outdated" ]]; then
        local _pip_count
        _pip_count=$(wc -l < "${_UPDATE_TMPDIR}/pip_outdated" | tr -d ' ')
        if [[ ${_pip_count} -gt 0 ]]; then
          _result="${_pip_count} package(s) ($(paste -sd', ' - < "${_UPDATE_TMPDIR}/pip_outdated"))"
        else
          _result="no changes"
        fi
      else
        _result="updated"
      fi
      ;;
    oh-my-zsh|p10k|tpm|tfenv|zsh-autosuggestions)
      if [[ -f "${_UPDATE_TMPDIR}/pre_${_section}" ]]; then
        local _old_sha _git_dir
        _old_sha=$(cat "${_UPDATE_TMPDIR}/pre_${_section}")
        case "${_section}" in
          oh-my-zsh) _git_dir="${HOME}/.oh-my-zsh" ;;
          p10k) _git_dir="${HOME}/.oh-my-zsh/custom/themes/powerlevel10k" ;;
          tpm) _git_dir="${HOME}/.tmux/plugins/tpm" ;;
          tfenv) _git_dir="${HOME}/.tfenv" ;;
          zsh-autosuggestions) _git_dir="${HOME}/.oh-my-zsh/custom/plugins/zsh-autosuggestions" ;;
        esac
        local _commits
        _commits=$(_update_git_diff "${_git_dir}" "${_old_sha}")
        local _commit_count
        _commit_count=$(printf '%s' "${_commits}" | grep -c . || true)
        if [[ ${_commit_count} -gt 0 ]]; then
          _result="${_commit_count} commit(s)"
        else
          _result="no changes"
        fi
      else
        _result="no changes"
      fi
      ;;
    *)
      _result="updated"
      ;;
  esac

  printf "OK\n" > "${_UPDATE_TMPDIR}/status_${_section}"
  printf "%s\n" "${_result}" > "${_UPDATE_TMPDIR}/result_${_section}"
}
```

- [ ] **Step 9: Run tests to verify they pass**

Run: `bats tests/setup_env/update_summary.bats`
Expected: All tests PASS

- [ ] **Step 10: Run full test suite**

Run: `make test`
Expected: All tests pass

- [ ] **Step 11: Commit**

```bash
git add lib/update_summary.sh tests/setup_env/update_summary.bats
git commit -m "feat: add state tracking functions (_update_record_start, _update_record_end, _update_skip)"
```

---

### Task 4: Summary output and log writing

**Files:**

- Modify: `lib/update_summary.sh`
- Modify: `tests/setup_env/update_summary.bats`

- [ ] **Step 1: Write failing tests for `_update_summary`**

Append to `tests/setup_env/update_summary.bats`:

```bash
# ── _update_summary ───────────────────────────────────────────────────────────

@test "_update_summary prints OK section with result" {
  printf "OK\n" > "${_UPDATE_TMPDIR}/status_brew"
  printf "2 formulae (git 2.45.0, wget 1.22.0)\n" > "${_UPDATE_TMPDIR}/result_brew"
  # Mark remaining sections as skipped so summary has data
  local _s
  for _s in softwareupdate mas claude pip gems oh-my-zsh p10k tpm tfenv cheat.sh; do
    printf "SKIP\n" > "${_UPDATE_TMPDIR}/status_${_s}"
    printf "not run\n" > "${_UPDATE_TMPDIR}/result_${_s}"
  done
  run _update_summary
  [ "$status" -eq 0 ]
  [[ "$output" == *"[OK]"* ]]
  [[ "$output" == *"brew"* ]]
  [[ "$output" == *"2 formulae"* ]]
}

@test "_update_summary prints FAIL section with exit code" {
  printf "FAIL\n" > "${_UPDATE_TMPDIR}/status_claude"
  printf "exit 1 — see output above\n" > "${_UPDATE_TMPDIR}/result_claude"
  local _s
  for _s in brew softwareupdate mas pip gems oh-my-zsh p10k tpm tfenv cheat.sh; do
    printf "OK\n" > "${_UPDATE_TMPDIR}/status_${_s}"
    printf "no changes\n" > "${_UPDATE_TMPDIR}/result_${_s}"
  done
  run _update_summary
  [[ "$output" == *"[FAIL]"* ]]
  [[ "$output" == *"claude"* ]]
  [[ "$output" == *"exit 1"* ]]
}

@test "_update_summary prints SKIP section with reason" {
  printf "SKIP\n" > "${_UPDATE_TMPDIR}/status_mas"
  printf "--brew-only flag set\n" > "${_UPDATE_TMPDIR}/result_mas"
  local _s
  for _s in brew softwareupdate claude pip gems oh-my-zsh p10k tpm tfenv cheat.sh; do
    printf "OK\n" > "${_UPDATE_TMPDIR}/status_${_s}"
    printf "no changes\n" > "${_UPDATE_TMPDIR}/result_${_s}"
  done
  run _update_summary
  [[ "$output" == *"[SKIP]"* ]]
  [[ "$output" == *"mas"* ]]
  [[ "$output" == *"--brew-only flag set"* ]]
}

@test "_update_summary prints totals line" {
  printf "OK\n" > "${_UPDATE_TMPDIR}/status_brew"
  printf "no changes\n" > "${_UPDATE_TMPDIR}/result_brew"
  printf "FAIL\n" > "${_UPDATE_TMPDIR}/status_claude"
  printf "exit 1\n" > "${_UPDATE_TMPDIR}/result_claude"
  printf "SKIP\n" > "${_UPDATE_TMPDIR}/status_mas"
  printf "not needed\n" > "${_UPDATE_TMPDIR}/result_mas"
  local _s
  for _s in softwareupdate pip gems oh-my-zsh p10k tpm tfenv cheat.sh; do
    printf "OK\n" > "${_UPDATE_TMPDIR}/status_${_s}"
    printf "no changes\n" > "${_UPDATE_TMPDIR}/result_${_s}"
  done
  run _update_summary
  [[ "$output" == *"9 OK"* ]]
  [[ "$output" == *"1 failed"* ]]
  [[ "$output" == *"1 skipped"* ]]
}

@test "_update_summary creates log file when missing" {
  rm -f "${UPDATE_LOG_PATH}"
  local _s
  for _s in brew softwareupdate mas claude pip gems oh-my-zsh p10k tpm tfenv cheat.sh; do
    printf "OK\n" > "${_UPDATE_TMPDIR}/status_${_s}"
    printf "no changes\n" > "${_UPDATE_TMPDIR}/result_${_s}"
  done
  _update_summary
  [ -f "${UPDATE_LOG_PATH}" ]
}

@test "_update_summary appends to existing log file" {
  printf "previous run\n" > "${UPDATE_LOG_PATH}"
  local _s
  for _s in brew softwareupdate mas claude pip gems oh-my-zsh p10k tpm tfenv cheat.sh; do
    printf "OK\n" > "${_UPDATE_TMPDIR}/status_${_s}"
    printf "no changes\n" > "${_UPDATE_TMPDIR}/result_${_s}"
  done
  _update_summary
  grep -q "previous run" "${UPDATE_LOG_PATH}"
  grep -q "Update Summary" "${UPDATE_LOG_PATH}"
}

@test "_update_summary writes separator before entry in log" {
  local _s
  for _s in brew softwareupdate mas claude pip gems oh-my-zsh p10k tpm tfenv cheat.sh; do
    printf "OK\n" > "${_UPDATE_TMPDIR}/status_${_s}"
    printf "no changes\n" > "${_UPDATE_TMPDIR}/result_${_s}"
  done
  _update_summary
  head -1 "${UPDATE_LOG_PATH}" | grep -q "─"
}

@test "_update_summary skips sections with no status file" {
  # Only create status for brew — others should be silently skipped
  printf "OK\n" > "${_UPDATE_TMPDIR}/status_brew"
  printf "no changes\n" > "${_UPDATE_TMPDIR}/result_brew"
  run _update_summary
  [ "$status" -eq 0 ]
  [[ "$output" == *"brew"* ]]
  [[ "$output" == *"1 OK"* ]]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bats tests/setup_env/update_summary.bats`
Expected: FAIL — `_update_summary: command not found`

- [ ] **Step 3: Implement `_update_summary`**

Add to `lib/update_summary.sh`:

```bash
# _update_summary
# Reads status/result files, prints formatted table, appends to log file.
_update_summary() {
  local _ok=0 _fail=0 _skip=0
  local _output=""
  local _timestamp
  _timestamp=$(date '+%Y-%m-%d %H:%M:%S')

  _output+="=== Update Summary — ${_timestamp} ===\n\n"

  local _section _status _result
  for _section in "${_UPDATE_SECTION_ORDER[@]}"; do
    if [[ ! -f "${_UPDATE_TMPDIR}/status_${_section}" ]]; then
      continue
    fi
    _status=$(cat "${_UPDATE_TMPDIR}/status_${_section}")
    _result=$(cat "${_UPDATE_TMPDIR}/result_${_section}")

    case "${_status}" in
      OK)
        _ok=$(( _ok + 1 ))
        _output+="$(printf "[OK]   %-16s %s" "${_section}" "${_result}")\n"
        ;;
      FAIL)
        _fail=$(( _fail + 1 ))
        _output+="$(printf "[FAIL] %-16s %s" "${_section}" "${_result}")\n"
        ;;
      SKIP)
        _skip=$(( _skip + 1 ))
        _output+="$(printf "[SKIP] %-16s %s" "${_section}" "${_result}")\n"
        ;;
    esac
  done

  local _total=$(( _ok + _fail + _skip ))
  _output+="\n$(printf "%d sections: %d OK, %d failed, %d skipped" "${_total}" "${_ok}" "${_fail}" "${_skip}")\n"

  # Print to terminal
  printf '%b' "${_output}"

  # Append to log file
  local _log="${UPDATE_LOG_PATH:-${HOME}/.dotfiles-update.log}"
  {
    printf "────────────────────────────────────────────────────────\n"
    printf '%b' "${_output}"
  } >> "${_log}" 2>/dev/null || log_warn "Could not write to ${_log}"

  printf "Log appended: %s\n" "${_log}"
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bats tests/setup_env/update_summary.bats`
Expected: All tests PASS

- [ ] **Step 5: Run full test suite**

Run: `make test`
Expected: All tests pass

- [ ] **Step 6: Commit**

```bash
git add lib/update_summary.sh tests/setup_env/update_summary.bats
git commit -m "feat: add _update_summary for formatted output and log writing"
```

---

### Task 5: Wire `run_update()` to call summary functions

**Files:**

- Modify: `lib/workflows.sh:154-262` (`run_update()`)
- Modify: `tests/setup_env/workflows.bats`

- [ ] **Step 1: Write failing integration tests**

Append to `tests/setup_env/workflows.bats`:

```bash
# ── run_update summary integration ────────────────────────────────────────────

@test "run_update creates _UPDATE_TMPDIR and cleans it up" {
  export MACOS=1
  unset LINUX UBUNTU REDHAT FEDORA CENTOS
  export UPDATE_BREW=1
  export UPDATE_LOG_PATH="${BATS_TEST_TMPDIR}/update.log"
  run_update
  # _UPDATE_TMPDIR should be cleaned up (no leftover /tmp/tmp.* dirs from this run)
  [ ! -d "${_UPDATE_TMPDIR:-/nonexistent}" ]
}

@test "run_update calls _update_summary at end" {
  export MACOS=1
  unset LINUX UBUNTU REDHAT FEDORA CENTOS
  export UPDATE_BREW=1
  export UPDATE_LOG_PATH="${BATS_TEST_TMPDIR}/update.log"
  run run_update
  [[ "$output" == *"Update Summary"* ]]
}

@test "run_update records brew section status" {
  export MACOS=1
  unset LINUX UBUNTU REDHAT FEDORA CENTOS
  export UPDATE_BREW=1
  export UPDATE_LOG_PATH="${BATS_TEST_TMPDIR}/update.log"
  run run_update
  [[ "$output" == *"brew"* ]]
}

@test "run_update skips mas when --brew-only flag set" {
  export MACOS=1
  unset LINUX UBUNTU REDHAT FEDORA CENTOS
  export UPDATE_BREW=1
  export UPDATE_LOG_PATH="${BATS_TEST_TMPDIR}/update.log"
  run run_update
  [[ "$output" == *"[SKIP]"*"mas"* ]] || [[ "$output" != *"mas"* ]]
}

@test "run_update appends to log file" {
  export MACOS=1
  unset LINUX UBUNTU REDHAT FEDORA CENTOS
  export UPDATE_BREW=1
  export UPDATE_LOG_PATH="${BATS_TEST_TMPDIR}/update.log"
  run_update
  [ -f "${BATS_TEST_TMPDIR}/update.log" ]
  grep -q "Update Summary" "${BATS_TEST_TMPDIR}/update.log"
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bats tests/setup_env/workflows.bats`
Expected: FAIL — output won't contain "Update Summary" because `run_update()` doesn't call summary functions yet

- [ ] **Step 3: Modify `run_update()` to wrap sections**

Replace `run_update()` in `lib/workflows.sh:154-262` with the wrapped version. The key changes:

1. Add `_UPDATE_TMPDIR=$(mktemp -d)` at the start
2. Wrap each section with `_update_record_start`/`_update_record_end`
3. Add `_update_skip` for sections that don't run
4. Call `_update_summary` at the end
5. Clean up `_UPDATE_TMPDIR` at the end

```bash
run_update() {
  local _run_all=0
  _any_update_flag || _run_all=1

  _UPDATE_TMPDIR=$(mktemp -d)

  # ── brew + softwareupdate ─────────────────────────────────────────────────
  if [[ ${_run_all} -eq 1 ]] || [[ -n ${UPDATE_BREW:-} ]]; then
    if [[ -n ${MACOS} ]] || [[ -n ${LINUX} ]]; then
      _update_record_start "brew"
      brew_update
      _update_record_end "brew" $?

      _update_record_start "softwareupdate"
      printf "Updating app store apps softwareupdate\\n"
      sudo -H softwareupdate --install --all --verbose
      _update_record_end "softwareupdate" $?
    else
      _update_skip "brew" "not macOS or Linux"
      _update_skip "softwareupdate" "not macOS or Linux"
    fi
  else
    _update_skip "brew" "flag not set"
    _update_skip "softwareupdate" "flag not set"
  fi

  # ── claude plugins ────────────────────────────────────────────────────────
  if [[ ${_run_all} -eq 1 ]] || [[ -n ${UPDATE_CLAUDE:-} ]]; then
    if command -v claude &>/dev/null; then
      _update_record_start "claude"
      printf "Updating Claude plugins\\n"
      claude plugins update superpowers && claude plugins update code-simplifier && claude plugins update context7
      _update_record_end "claude" $?
    else
      _update_skip "claude" "claude not installed"
    fi
  else
    _update_skip "claude" "flag not set"
  fi

  # ── mas + system packages ─────────────────────────────────────────────────
  if [[ ${_run_all} -eq 1 ]] || [[ -n ${UPDATE_MAS:-} ]]; then
    _update_record_start "mas"
    update_system_packages
    if [[ -n ${MACOS} ]]; then
      log_info "Updating mas packages"
      mas upgrade
    fi
    _update_record_end "mas" $?
  else
    _update_skip "mas" "flag not set"
  fi

  # ── pip ───────────────────────────────────────────────────────────────────
  if [[ ${_run_all} -eq 1 ]] || [[ -n ${UPDATE_PIP:-} ]]; then
    _update_record_start "pip"
    printf "Updating pip3 packages\n"
    if [[ -n ${HAS_DEVTOOLS} ]]; then
      export PYENV_ROOT="$HOME/.pyenv"
      export PATH="$PYENV_ROOT/bin:$PYENV_ROOT/shims:$PATH"

      if command -v pyenv >/dev/null 2>&1; then
        eval "$(pyenv init -)"
        eval "$(pyenv virtualenv-init -)" 2>/dev/null || true
      fi

      pyenv shell ansible 2>/dev/null || true
      PYTHON="$(pyenv which python 2>/dev/null || command -v python3)"

      "$PYTHON" -m pip install -U pip setuptools wheel

      "$PYTHON" - <<PY
import json, subprocess, sys

cmd = [sys.executable, "-m", "pip", "list", "--outdated", "--format=json"]
out = subprocess.check_output(cmd, text=True)
pkgs = [p["name"] for p in json.loads(out)]

# Write outdated package names for the update summary
with open("${_UPDATE_TMPDIR}/pip_outdated", "w") as f:
    f.write("\\n".join(pkgs))

if pkgs:
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-U", *pkgs])
PY

      "$PYTHON" -m pip check || true
      printf "Updated pip packages\n"
    fi
    _update_record_end "pip" $?
  else
    _update_skip "pip" "flag not set"
  fi

  # ── git-based tools + misc (run_all only) ─────────────────────────────────
  if [[ ${_run_all} -eq 1 ]]; then
    if [[ -d ${HOME}/.tfenv ]]; then
      _update_record_start "tfenv"
      printf "Updating tfenv\\n"
      cd ${HOME}/.tfenv || exit
      git pull
      cd ${PERSONAL_GITREPOS}/${DOTFILES} || exit
      _update_record_end "tfenv" $?
    else
      _update_skip "tfenv" "not installed"
    fi
    if [[ -d ${HOME}/.oh-my-zsh ]]; then
      _update_record_start "oh-my-zsh"
      printf "Updating oh-my-zsh\\n"
      cd ${HOME}/.oh-my-zsh || exit
      git pull
      cd ${PERSONAL_GITREPOS}/${DOTFILES} || exit
      _update_record_end "oh-my-zsh" $?
    else
      _update_skip "oh-my-zsh" "not installed"
    fi
    if [[ -d ${HOME}/.oh-my-zsh/custom/themes/powerlevel10k ]]; then
      _update_record_start "p10k"
      printf "Updating powerlevel10k\\n"
      cd ${HOME}/.oh-my-zsh/custom/themes/powerlevel10k || exit
      git pull
      cd ${PERSONAL_GITREPOS}/${DOTFILES} || exit
      _update_record_end "p10k" $?
    else
      _update_skip "p10k" "not installed"
    fi
    if [[ -d ${HOME}/.tmux/plugins/tpm ]]; then
      _update_record_start "tpm"
      printf "Updating tpm\\n"
      cd ${HOME}/.tmux/plugins/tpm || exit
      git pull
      cd ${PERSONAL_GITREPOS}/${DOTFILES} || exit
      _update_record_end "tpm" $?
    else
      _update_skip "tpm" "not installed"
    fi
    if [[ -f ${HOME}/bin/cht.sh ]]; then
      _update_record_start "cheat.sh"
      printf "Updating cheat.sh\\n"
      curl https://cht.sh/:cht.sh > ~/bin/cht.sh
      chmod 754 ${HOME}/bin/cht.sh
      _update_record_end "cheat.sh" $?
    else
      _update_skip "cheat.sh" "not installed"
    fi
    if [[ -f ${HOME}/.zsh.d/_cht ]]; then
      printf "Updating cheat.sh tab completion\\n"
      curl https://cheat.sh/:zsh > ${HOME}/.zsh.d/_cht
    fi
    if [[ -d ${HOME}/.oh-my-zsh/custom/plugins/zsh-autosuggestions ]]; then
      printf "Updating zsh-autosuggestions\\n"
      cd ${HOME}/.oh-my-zsh/custom/plugins/zsh-autosuggestions || exit
      git pull
      cd ${PERSONAL_GITREPOS}/${DOTFILES} || exit
    fi
  else
    _update_skip "tfenv" "flag not set"
    _update_skip "oh-my-zsh" "flag not set"
    _update_skip "p10k" "flag not set"
    _update_skip "tpm" "flag not set"
    _update_skip "cheat.sh" "flag not set"
  fi

  # ── gems ──────────────────────────────────────────────────────────────────
  if [[ ${_run_all} -eq 1 ]] || [[ -n ${UPDATE_GEMS:-} ]]; then
    _update_record_start "gems"
    printf "updating ruby gems\\n"
    gem update
    _update_record_end "gems" $?
  else
    _update_skip "gems" "flag not set"
  fi

  # ── summary ───────────────────────────────────────────────────────────────
  _update_summary

  rm -rf "${_UPDATE_TMPDIR}"
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bats tests/setup_env/workflows.bats`
Expected: All tests PASS (including new integration tests)

- [ ] **Step 5: Run full test suite**

Run: `make test`
Expected: All tests pass

- [ ] **Step 6: Commit**

```bash
git add lib/workflows.sh tests/setup_env/workflows.bats
git commit -m "feat: wire run_update() to call summary functions for all sections"
```

---

### Task 6: Documentation updates

**Files:**

- Modify: `CLAUDE.md` (add update summary docs)
- Modify: `docs/superpowers/README.md` (add plan row)

- [ ] **Step 1: Update CLAUDE.md**

Add to the "Entry Points" table in `CLAUDE.md`, after the `update` row description:

```
The `update` workflow prints a structured summary at the end showing per-section status ([OK], [FAIL], [SKIP]) and what changed. Each run is appended to `~/.dotfiles-update.log`.
```

Add to the "Test Seams" table in `CLAUDE.md`:

```
| `UPDATE_LOG_PATH` | `_update_summary` | Redirects log writes to a temp file in tests; defaults to `~/.dotfiles-update.log` |
| `_UPDATE_TMPDIR` | all summary functions | Set to `${BATS_TEST_TMPDIR}` in tests to isolate snapshot files |
```

Add to the "Layout" tree in `CLAUDE.md`, under `lib/`:

```
│   ├── update_summary.sh     # Update run tracking and summary reporting
```

- [ ] **Step 2: Update superpowers README.md**

Add row to `docs/superpowers/README.md`:

```
| 2026-04-11 | [update-summary](plans/2026-04-11-update-summary.md) | [spec](specs/2026-04-11-update-summary-design.md) | In Progress |
```

- [ ] **Step 3: Run lint to verify changes are clean**

Run: `make lint`
Expected: All OK

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md docs/superpowers/README.md
git commit -m "docs: add update-summary to CLAUDE.md and superpowers index"
```

---

## Self-Review

**Spec coverage check:**

| Spec requirement                      | Task                                  |
| ------------------------------------- | ------------------------------------- | --- | ------------------------------- |
| New `lib/update_summary.sh`           | Task 1 (create), Tasks 2-4 (populate) |
| `_update_diff_lines`                  | Task 1                                |
| `_update_snapshot`                    | Task 1                                |
| `_update_git_diff`                    | Task 2                                |
| `_update_record_start`                | Task 3                                |
| `_update_record_end`                  | Task 3                                |
| `_update_skip`                        | Task 3                                |
| `_update_summary`                     | Task 4                                |
| Wire `run_update()`                   | Task 5                                |
| Log file append                       | Task 4 (implementation), Task 4 tests |
| `UPDATE_LOG_PATH` test seam           | Task 4                                |
| `_UPDATE_TMPDIR` test seam            | Tasks 1-5                             |
| Section order                         | Task 1 (`_UPDATE_SECTION_ORDER`)      |
| Error handling (snapshot fails)       | Task 3 (`                             |     | true` on all snapshot commands) |
| Error handling (log write fails)      | Task 4 (`                             |     | log_warn`)                      |
| Integration tests in `workflows.bats` | Task 5                                |
| Docs                                  | Task 6                                |

**Placeholder scan:** No TBDs, TODOs, or "implement later" found.

**Type consistency:** `_update_record_start`, `_update_record_end`, `_update_skip`, `_update_summary`, `_update_diff_lines`, `_update_git_diff`, `_update_snapshot` — all names consistent between tasks.
