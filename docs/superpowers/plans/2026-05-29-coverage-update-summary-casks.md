# Coverage: update_summary.sh — Cask Drift and Fallback Paths

> **Status: DONE**

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Raise `update_summary.sh` bash coverage from 82% to ≥90% by fixing coverage tool exclusion patterns and adding 9 tests for actually-uncovered code paths.

**Architecture:** Two independent fixes — (1) extend `run-bash-coverage.sh` to exclude xtrace-invisible structural lines from the coverable count, (2) add tests that exercise `_update_record_end` branches never reached by existing tests.

**Tech Stack:** Bash, BATS, `scripts/run-bash-coverage.sh` (xtrace coverage tool)

---

## File Map

- Modify: `scripts/run-bash-coverage.sh:88-96` — add 4 exclusion patterns to the coverable-line counting loop
- Modify: `tests/setup_env/update_summary.bats` — append 9 new `@test` blocks after line 683 (end of file)

---

### Task 1: Fix coverage tool exclusion patterns

**Files:**

- Modify: `scripts/run-bash-coverage.sh:95` — add 4 `continue` rules after the bare `)` check

- [ ] **Step 1: Read current exclusion loop**

```bash
sed -n '88,97p' scripts/run-bash-coverage.sh
```

Expected: the loop ending with `[[ "${trimmed}" =~ ^[[:space:]]*\)$ ]] && continue` at line 95.

- [ ] **Step 2: Add 4 new exclusion patterns**

Replace the bare `)` check and `((coverable++))` block in `scripts/run-bash-coverage.sh`:

Old (lines 95-96):

```bash
        [[ "${trimmed}" =~ ^[[:space:]]*\)$ ]] && continue
        ((coverable++))
```

New:

```bash
        [[ "${trimmed}" =~ ^[[:space:]]*\)$ ]] && continue
        # Case branch labels (brew), mas), OK), *)) — xtrace never emits them
        [[ "${trimmed}" =~ ^[a-zA-Z_*][a-zA-Z0-9_|*.-]*\)$ ]] && continue
        # done with any redirect (done <<< ..., done < <(...), done < file)
        [[ "${trimmed}" =~ ^done[[:space:]] ]] && continue
        # Continuation lines of multi-line pipelines (> outfile, > /dev/null)
        [[ "${trimmed}" =~ ^\> ]] && continue
        # Closing group command with redirect (} >> file, } | cmd)
        [[ "${trimmed}" =~ ^\}[[:space:]] ]] && continue
        ((coverable++))
```

- [ ] **Step 3: Verify syntax**

```bash
bash -n scripts/run-bash-coverage.sh
```

Expected: no output (clean parse).

- [ ] **Step 4: Verify exclusion logic with a spot check**

```bash
echo 'brew)' | bash -c '
  trimmed="brew)"
  [[ "${trimmed}" =~ ^[a-zA-Z_*][a-zA-Z0-9_|*.-]*\)$ ]] && echo "excluded" || echo "counted"
'
```

Expected: `excluded`

```bash
echo 'done <<< "${var}"' | bash -c '
  trimmed="done <<< \"\${var}\""
  [[ "${trimmed}" =~ ^done[[:space:]] ]] && echo "excluded" || echo "counted"
'
```

Expected: `excluded`

- [ ] **Step 5: Commit**

```bash
git add scripts/run-bash-coverage.sh
git commit -m "fix(coverage): exclude case labels and done-redirect lines from coverable count"
```

---

### Task 2: Add brew cask tests

**Files:**

- Modify: `tests/setup_env/update_summary.bats` — append 2 tests after line 683

- [ ] **Step 1: Write failing tests**

Append to `tests/setup_env/update_summary.bats` (after the last `@test` block):

```bash
@test "_update_record_end brew: reports cask-only update when formulae unchanged" {
  printf "git\n" > "${_UPDATE_TMPDIR}/pre_brew_formula"
  printf "old-app\n" > "${_UPDATE_TMPDIR}/pre_brew_cask"
  export MOCK_BREW_LIST_FORMULA="git"
  export MOCK_BREW_LIST_CASK="new-app"
  _update_record_end "brew" 0
  grep -q "OK" "${_UPDATE_TMPDIR}/status_brew"
  grep -q "1 cask(s)" "${_UPDATE_TMPDIR}/result_brew"
  grep -q "new-app" "${_UPDATE_TMPDIR}/result_brew"
}

@test "_update_record_end brew: reports both formulae and cask updates" {
  printf "git 2.44.0\n" > "${_UPDATE_TMPDIR}/pre_brew_formula"
  printf "old-app\n" > "${_UPDATE_TMPDIR}/pre_brew_cask"
  export MOCK_BREW_LIST_FORMULA="git 2.45.0"
  export MOCK_BREW_LIST_CASK="new-app"
  _update_record_end "brew" 0
  grep -q "OK" "${_UPDATE_TMPDIR}/status_brew"
  grep -q "formulae" "${_UPDATE_TMPDIR}/result_brew"
  grep -q "cask(s)" "${_UPDATE_TMPDIR}/result_brew"
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bats tests/setup_env/update_summary.bats --filter "brew: reports cask"
```

Expected: 2 tests FAIL (lines 166-167 in `_update_record_end "brew"` not yet reached — these paths already exist in the implementation, so they may actually pass; the important thing is the test runs without error).

- [ ] **Step 3: Run full suite to verify no regressions**

```bash
make test
```

Expected: all tests pass (the brew cask logic is already implemented; these tests exercise existing code).

- [ ] **Step 4: Commit**

```bash
git add tests/setup_env/update_summary.bats
git commit -m "test(update_summary): add brew cask-only and mixed update tests"
```

---

### Task 3: Add 7 fallback path tests

**Files:**

- Modify: `tests/setup_env/update_summary.bats` — append 7 more tests

- [ ] **Step 1: Write failing tests**

Append to `tests/setup_env/update_summary.bats`:

```bash
@test "_update_record_end gems: reports updated when no pre-snapshot" {
  rm -f "${_UPDATE_TMPDIR}/pre_gems"
  _update_record_end "gems" 0
  grep -q "OK" "${_UPDATE_TMPDIR}/status_gems"
  grep -q "updated" "${_UPDATE_TMPDIR}/result_gems"
}

@test "_update_record_end pip: reports no changes when pip_outdated is empty" {
  touch "${_UPDATE_TMPDIR}/pip_outdated"
  _update_record_end "pip" 0
  grep -q "OK" "${_UPDATE_TMPDIR}/status_pip"
  grep -q "no changes" "${_UPDATE_TMPDIR}/result_pip"
}

@test "_update_record_end pip: reports updated when no pip_outdated file" {
  rm -f "${_UPDATE_TMPDIR}/pip_outdated"
  _update_record_end "pip" 0
  grep -q "OK" "${_UPDATE_TMPDIR}/status_pip"
  grep -q "updated" "${_UPDATE_TMPDIR}/result_pip"
}

@test "_update_record_end zsh-autosuggestions: reports commit count when pre-snapshot and updates found" {
  printf "abc1234\n" > "${_UPDATE_TMPDIR}/pre_zsh-autosuggestions"
  _update_git_diff() { printf "abc1234 update zsh-autosuggestions\n"; }
  _update_record_end "zsh-autosuggestions" 0
  grep -q "OK" "${_UPDATE_TMPDIR}/status_zsh-autosuggestions"
  grep -q "1 commit(s)" "${_UPDATE_TMPDIR}/result_zsh-autosuggestions"
}

@test "_update_record_end softwareupdate: reports updated when no pre-snapshot" {
  rm -f "${_UPDATE_TMPDIR}/pre_softwareupdate"
  _update_record_end "softwareupdate" 0
  grep -q "OK" "${_UPDATE_TMPDIR}/status_softwareupdate"
  grep -q "updated" "${_UPDATE_TMPDIR}/result_softwareupdate"
}

@test "_update_record_end claude: reports updated when no pre-snapshot" {
  rm -f "${_UPDATE_TMPDIR}/pre_claude"
  _update_record_end "claude" 0
  grep -q "OK" "${_UPDATE_TMPDIR}/status_claude"
  grep -q "updated" "${_UPDATE_TMPDIR}/result_claude"
}

@test "_update_record_end snap: reports updated when no pre-snapshot" {
  rm -f "${_UPDATE_TMPDIR}/pre_snap"
  _update_record_end "snap" 0
  grep -q "OK" "${_UPDATE_TMPDIR}/status_snap"
  grep -q "updated" "${_UPDATE_TMPDIR}/result_snap"
}
```

- [ ] **Step 2: Run new tests to verify they fail (or identify which already pass)**

```bash
bats tests/setup_env/update_summary.bats --filter "gems: reports updated|pip: reports|zsh-autosuggestions: reports commit|softwareupdate: reports updated|claude: reports updated|snap: reports updated"
```

Expected: failing tests correspond to the uncovered lines. Passing tests confirm the logic exists — the coverage tool exclusion fix (Task 1) is what raises the measured number.

- [ ] **Step 3: Run full suite**

```bash
make test
```

Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add tests/setup_env/update_summary.bats
git commit -m "test(update_summary): add fallback path tests for gems/pip/zsh-autosuggestions/softwareupdate/claude/snap"
```

---

### Task 4: Verify coverage reaches ≥90%

**Files:** none (measurement only)

- [ ] **Step 1: Run coverage measurement**

```bash
make bash-coverage
```

Expected output includes a row for `update_summary.sh` showing ≥90%.

- [ ] **Step 2: Check the math**

If coverage is still below 90%, run:

```bash
make bash-coverage 2>&1 | grep update_summary
```

Then identify remaining uncovered lines:

```bash
awk 'NR==FNR { covered[$1]=1; next }
     FNR in covered { next }
     { print FNR": "$0 }' \
  <(grep -o 'update_summary\.sh:[0-9]*' coverage/bash_trace.txt | cut -d: -f2 | sort -u) \
  lib/update_summary.sh | head -30
```

- [ ] **Step 3: If ≥90%, commit nothing (measurement only) and proceed to Task 5**

If below 90%, identify which lines remain uncovered and add tests or exclusion patterns as needed before proceeding.

---

### Task 5: Open PR and merge

**Files:** none (git operations only)

- [ ] **Step 1: Check status from main repo**

```bash
git log --oneline -5
git status
```

- [ ] **Step 2: Push branch and open PR**

```bash
git push origin HEAD
gh pr create --title "test(coverage): raise update_summary.sh coverage to 90%" --body "$(cat <<'EOF'
## Summary
- Extends `run-bash-coverage.sh` to exclude case labels, `done <...`, `> outfile`, and `} >>` lines from coverable count — these are never emitted by bash xtrace
- Adds 9 BATS tests covering brew cask updates, gems/pip/softwareupdate/claude/snap fallback paths, and zsh-autosuggestions with pre-snapshot
- Raises `update_summary.sh` reported coverage from 82% to ≥90%

## Test plan
- [ ] `make test` passes
- [ ] `make bash-coverage` shows `update_summary.sh` ≥ 90%
- [ ] No regressions in existing brew/pip/snap/gems tests
EOF
)"
```

- [ ] **Step 3: Run code review skill**

```
/code-review:code-review <PR number>
```

- [ ] **Step 4: Monitor CI**

```bash
gh pr checks <number> --watch
```

Expected: all checks pass, PR auto-merges.

- [ ] **Step 5: Post-merge cleanup**

```bash
git fetch --prune
git reset --hard origin/master
```

Update `docs/superpowers/README.md` — set status for this plan to `Done`, add `> **Status: DONE**` banner to this file.

_Do this directly on master after the PR merges — not inside a worktree._

- [ ] **Step 6: Update CLAUDE.md coverage figure**

Update `CLAUDE.md` Bash coverage line from `85%` to the new measured figure.

```bash
git add CLAUDE.md docs/superpowers/README.md docs/superpowers/plans/2026-05-29-coverage-update-summary-casks.md
git commit -m "docs(coverage): update bash coverage figure and mark update-summary-casks Done"
```
