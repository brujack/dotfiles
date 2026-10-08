# Check-Versions Curl Fix Implementation Plan

spec: docs/superpowers/specs/2026-10-07-check-versions-curl-max-time-design.md

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make homebrew-install's drift check work (install.sh history, report-only, compare URL), delete the meaningless oh-my-zsh check, and bound the homebrew and crates.io curls with `--max-time 10`.

**Architecture:** Edits to three functions in `lib/workflows.sh` (`_check_cv_homebrew_install`, `_check_one_cargo_version`, `run_check_versions`), comment/help-text edits in `lib/constants.sh` and `lib/helpers.sh`, bats cases in `tests/setup_env/workflows.bats` and `tests/setup_env/check_versions_cargo.bats`, docs in `CLAUDE.md` and `README.md`.

**Tech Stack:** bash, bats, `tests/mocks/curl` (records argv verbatim to `MOCK_CALLS_FILE`).

## Global Constraints

- Worktree: `/home/bruce/git-repos/personal/dotfiles-cv-fix`, branch `fix/cv-curl-max-time`. All work happens there.
- `--max-time 10` exactly, spelled as in `_fetch_github_latest` (`lib/workflows.sh:1273`).
- Homebrew endpoint exactly `https://api.github.com/repos/Homebrew/install/commits?path=install.sh&per_page=1`, quoted.
- No new constant, helper function, or environment-variable seam (N2).
- No change to the cheat.sh curls, to homebrew auth, or to `HOMEBREW_INSTALL_SHA`'s value (N3).
- No change to any other check's output, counter or exit code (N1).
- Tasks are sequential (shared files). Per-task gates are scoped; the orchestrator runs `make test` once after Task 3 and again after Task 4.

## Verification

- `make test` exits 0 (V2).
- V1 mutations, run by the orchestrator after Task 3: each must turn its test red, then be reverted.
  - remove `--max-time 10` from `_check_cv_homebrew_install` -> R6 test red
  - endpoint back to `commits/master` -> R6 test red
  - restore `_prompt_version_update "homebrew-install" ...` in the OUTDATED branch -> R7 test red
  - remove `--max-time 10` from `_check_one_cargo_version` -> R8 test red
  - re-add a `_check_cv_oh_my_zsh` call in `run_check_versions` -> R9 test red
- V3, orchestrator, real network, after checking `x-ratelimit-remaining` > 5: `./setup_env.sh -t check-versions` shows homebrew-install `[OK]` or `[OUTDATED]` followed by a `compare/` URL, and no `oh-my-zsh` line. Expected today: OUTDATED, `5e78e698...09c62fc5`.

---

### Task 1: homebrew-install — install.sh reference, bound, report-only

```yaml-task
id: 1
description: Point _check_cv_homebrew_install at install.sh history with --max-time 10, make it report-only with a compare URL, and fix the two comments that claim --update bumps the pin
role: executor
model: sonnet
tdd: required
requirements: [R2, R3, R5, R6, R7]
acceptance:
  - cmd: bats tests/setup_env/workflows.bats
    exit_code: 0
  - cmd: make lint
    exit_code: 0
  - cmd: 'grep -n "_prompt_version_update \"homebrew-install\"" lib/workflows.sh'
    exit_code: 1
max_retries: 3
files_touched: [lib/workflows.sh, lib/constants.sh, lib/helpers.sh, tests/setup_env/workflows.bats]
depends_on: []
```

**Steps:**

- [ ] Add these two tests to `tests/setup_env/workflows.bats` directly after `_check_cv_homebrew_install emits OUTDATED when SHA differs`:

```bash
@test "_check_cv_homebrew_install queries install.sh history with max-time 10" {
  local _ok=0 _outdated=0 _warned=0
  _check_cv_homebrew_install >/dev/null
  grep -- '--max-time 10' "${MOCK_CALLS_FILE}" \
    | grep -qF 'https://api.github.com/repos/Homebrew/install/commits?path=install.sh&per_page=1'
}

@test "_check_cv_homebrew_install is report-only under --update and prints a compare URL" {
  local _ok=0 _outdated=0 _warned=0
  # shellcheck disable=SC2034 # read by _check_cv_homebrew_install after source; shellcheck cannot see the consumer
  HOMEBREW_INSTALL_SHA="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  export UPDATE_VERSIONS=1
  # Records to a file: a variable would be lost in the $(...) subshell below.
  _prompt_version_update() { printf 'called\n' >> "${BATS_TEST_TMPDIR}/prompt_rec"; }
  curl() { printf '[{"sha":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","commit":{}}]'; }
  export -f curl
  local _out
  _out=$(_check_cv_homebrew_install 2>&1)
  [[ "${_out}" == *"[OUTDATED]"* ]]
  [[ "${_out}" == *"https://github.com/Homebrew/install/compare/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa...bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"* ]]
  [ ! -s "${BATS_TEST_TMPDIR}/prompt_rec" ]
}
```

- [ ] Run `bats tests/setup_env/workflows.bats -f homebrew`; both new tests fail.
- [ ] In `lib/workflows.sh`, `_check_cv_homebrew_install`: replace the curl line with
      `_latest=$(curl -fsSL --max-time 10 "https://api.github.com/repos/Homebrew/install/commits?path=install.sh&per_page=1" \` (keep the `2>/dev/null | grep '"sha"' | head -1 | cut -d'"' -f4)` continuation). Add above it: `# The pin guards install.sh, not the repo: most repo commits never touch it.`
- [ ] In its OUTDATED branch, delete the `if [[ -n ${UPDATE_VERSIONS:-} ]]; then _prompt_version_update ... fi` block and print after the OUTDATED line:
      `printf "             review: https://github.com/Homebrew/install/compare/%s...%s\n" "${_pinned}" "${_latest}"`
      with the comment `# Report-only: this pin's script is downloaded and run, so a bump needs the diff reviewed.`
- [ ] `lib/constants.sh`, `HOMEBREW_INSTALL_SHA` comment: replace `# update check: ./setup_env.sh -t check-versions --update` with `# drift check: ./setup_env.sh -t check-versions (report-only; bump by hand after reviewing the printed compare URL)`.
- [ ] `lib/helpers.sh` usage line for `--update`: append ` (homebrew-install is report-only)`.
- [ ] Run the acceptance commands; all pass. Commit (message via `caveman:caveman-commit`).

---

### Task 2: bound the crates.io call

```yaml-task
id: 2
description: Add --max-time 10 to _check_one_cargo_version's curl, with a test in check_versions_cargo.bats tying the flag to the _CRATES_API request
role: executor
model: sonnet
tdd: required
requirements: [R4, R8]
acceptance:
  - cmd: bats tests/setup_env/check_versions_cargo.bats
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched: [lib/workflows.sh, tests/setup_env/check_versions_cargo.bats]
depends_on: [1]
```

**Steps:**

- [ ] Append to the END of `tests/setup_env/check_versions_cargo.bats` (after every existing test; the file's header comment explains the SC2218 ordering constraint):

```bash
@test "_check_one_cargo_version bounds the crates.io request with max-time 10" {
  _check_one_cargo_version "cargo-audit" "0.21.0" >/dev/null
  grep -- '--max-time 10' "${MOCK_CALLS_FILE}" | grep -qF "${_CRATES_API}/cargo-audit"
}
```

- [ ] Run it; it fails.
- [ ] In `lib/workflows.sh`, `_check_one_cargo_version`: change `curl -sf -A "dotfiles check-versions (bjackson@pobox.com)" \` to `curl -sf --max-time 10 -A "dotfiles check-versions (bjackson@pobox.com)" \`.
- [ ] Run the acceptance commands; pass. Commit.

---

### Task 3: delete the oh-my-zsh check

```yaml-task
id: 3
description: Remove _check_cv_oh_my_zsh and its call, reword the OH_MY_ZSH_VER comment, and update tests (delete two, keep the recorder stub asserting 0 calls, warning count 17 to 16)
role: executor
model: sonnet
tdd: required
requirements: [R1, R2, R9]
acceptance:
  - cmd: bats tests/setup_env/workflows.bats tests/setup_env/check_versions_cargo.bats
    exit_code: 0
  - cmd: make lint
    exit_code: 0
  - cmd: 'grep -rn "_check_cv_oh_my_zsh" lib/'
    exit_code: 1
max_retries: 3
files_touched: [lib/workflows.sh, lib/constants.sh, tests/setup_env/workflows.bats, tests/setup_env/check_versions_cargo.bats]
depends_on: [2]
```

**Steps:**

- [ ] `tests/setup_env/workflows.bats`: in `run_check_versions reports GitHub checks not checked on a token with a line break`, change `[ "$(grep -c '^_check_cv_oh_my_zsh$' "${BATS_TEST_TMPDIR}/rec")" -eq 1 ]` to `-eq 0`. Keep the `_check_cv_oh_my_zsh` recorder stub in `_stub_cv_callees` unchanged; the `_check_cv_homebrew_install` `-eq 1` line beside it is the positive control.
- [ ] In `run_check_versions counts warned tools in summary`, change `"17 warnings"` to `"16 warnings"` and rewrite the comment's first sentence to: `7 tools via _run_cv_check emit [WARN] + _check_cv_homebrew_install also emits [WARN] when curl fails in test env, plus the 8 CARGO_TOOLS pins via the real (unstubbed) _check_one_cargo_version = 16 total. Was 17 until _check_cv_oh_my_zsh was deleted on 2026-10-07 (oh-my-zsh has no releases; the pin is a branch).` Keep the older history sentences.
- [ ] Run `bats tests/setup_env/workflows.bats -f 'line break|warned tools'`; both fail.
- [ ] Delete tests `run_check_versions checks oh-my-zsh tag` and `_check_cv_oh_my_zsh emits WARN when curl returns empty (no releases)`.
- [ ] `tests/setup_env/check_versions_cargo.bats`: delete the three `_check_cv_oh_my_zsh() { :; }` lines.
- [ ] `lib/workflows.sh`: delete the `_check_cv_oh_my_zsh` function and the `_check_cv_oh_my_zsh` line in `run_check_versions`.
- [ ] `lib/constants.sh`: replace the `OH_MY_ZSH_VER` comment's 2nd and 3rd lines with `# not version-checked: a branch has no upstream version to compare against` and `# read by lib/helpers.sh:setup_dotfile_symlinks`.
- [ ] Run the acceptance commands; pass. Commit.

---

### Task 4: docs

```yaml-task
id: 4
description: Docs-only (no behaviour change, so TDD does not apply) — CLAUDE.md and README check-versions text, remove the backlog row, link the plan in the index
role: executor
model: sonnet
tdd: not-applicable
requirements: [R10, R11]
acceptance:
  - cmd: make lint
    exit_code: 0
  - cmd: 'grep -n "_check_cv_oh_my_zsh" CLAUDE.md README.md docs/superpowers/README.md'
    exit_code: 1
  - cmd: 'grep -q "homebrew-install, which is report-only" CLAUDE.md'
    exit_code: 0
max_retries: 2
files_touched: [CLAUDE.md, README.md, docs/superpowers/README.md]
depends_on: [3]
```

**Steps:**

- [ ] `CLAUDE.md` `check-versions` bullet: change `` `--update` prompts per-tool to apply updates in-place. `` to `` `--update` prompts per-tool to apply updates in-place, except homebrew-install, which is report-only and prints a `compare/<pin>...<latest>` URL to review the installer diff. `` and change `` `_check_cv_oh_my_zsh`, `_check_cv_homebrew_install` and the crates.io checks still run `` to `` `_check_cv_homebrew_install` and the crates.io checks still run ``.
- [ ] `README.md:206`: change `` `--update` prompts to apply each update in-place `` to `` `--update` prompts to apply each update in-place (homebrew-install is report-only) ``. `README.md:219`: append ` (homebrew-install is report-only)`.
- [ ] `docs/superpowers/README.md`: delete the backlog row starting ``| `_check_cv_oh_my_zsh` / `_check_cv_homebrew_install` call api.github.com``; in All Plans, change the `check-versions-curl-max-time` row's plan cell from `—` to `[check-versions-curl-max-time](plans/2026-10-07-check-versions-curl-max-time.md)` (status stays In Progress until merge).
- [ ] Run acceptance; commit.

## Non-goal check

Reviewer: fresh subagent, `nongoal-check.md`, 2026-10-07.

- **N1** CLEAR.
- **N2** CLEAR.
- **N3** UNCLEAR. Quote: Task 1 "replace the curl line with `_latest=$(curl -fsSL --max-time 10 "https://api.github.com/repos/Homebrew/install/commits?path=install.sh&per_page=1" \`". Concern: replacing the whole line could drop auth/header flags. Resolution: no plan change needed. The current line is `_latest=$(curl -fsSL "https://api.github.com/repos/Homebrew/install/commits/master" \` (`lib/workflows.sh:1399` at `e2982ec1`): it carries no `-H`, token or `-A`, so the replacement keeps the call unauthenticated, as N3 requires.

## Execution notes

- Task 3's third gate was written `grep -n ... lib/`. grep on a directory without `-r` exits 2 ("Is a directory"), so the gate could never return its expected 1. Corrected to `grep -rn`, 2026-10-08.
- While this plan's branch was in Phase 3, PR #321 merged the same library changes to master from another session (2026-10-08 11:35Z). Its code meets R1-R5; its tests did not pin R6-R8, and README carried no report-only wording. The branch was rebuilt from master as that delta only: the R6/R7/R8 tests, an OK-path no-URL assertion, and the two README lines. Master's code was kept as merged, including its `diff:` label and 12-character SHAs in the compare URL, which GitHub resolves.
