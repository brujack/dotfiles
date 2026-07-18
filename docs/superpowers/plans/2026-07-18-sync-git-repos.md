# sync_git_repos Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `scripts/synch_git-repos.sh` (stale hostnames, blind `rsync --delete` push that would clobber multi-machine `personal/` work) with a two-mode sync: git-native fetch/pull/push for `personal/` repos + `state-ledger`, and studio-only rsync for legacy no-git-access directories + ratna backup.

**Architecture:** Two new sourcing-guarded lib files (`lib/git_sync.sh`, `lib/legacy_rsync.sh`) hold the sync logic; a thin entrypoint (`scripts/sync_git_repos.sh`) exposes both standalone with `-h`/`--git-only`/`--legacy-only`; `run_update()` in `lib/workflows.sh` wires both in automatically under the existing `_run_all` git-tools block.

**Tech Stack:** Bash 5+, git, rsync, BATS (existing repo conventions — sourcing guards, `MOCK_*` PATH-injection, `log_info`/`log_warn`, `_update_record_start`/`_update_record_end`/`_update_skip`/`_update_warn`).

## Global Constraints

- No `set -e`, no `exit` inside any function in either new lib — every failure path is `log_warn` + continue (per `docs/superpowers/specs/2026-07-18-sync-git-repos-design.md` Error handling).
- Dirty repos are never stashed, force-pushed, or force-pulled.
- Diverged repos (`ahead>0 && behind>0`) are never auto-merged or auto-rebased — warn + skip only.
- `git fetch` runs before any ahead/behind classification (`@{u}` is a stale local ref without it) — this ordering is the load-bearing fix from spec review; a regression test enforces it directly.
- Return contract for `sync_git_repos()` and `sync_legacy_dirs()`: `0` = fully synced, `2` = completed with warnings (something was skipped), no other codes expected.
- `find ... -name .git -type d` intentionally excludes git worktrees (their `.git` is a file, not a directory) — do not "fix" this to include worktrees.
- Reuse existing helpers: `log_info`/`log_warn` (`lib/helpers.sh`), `_git_ssh_opts` (`lib/workflows.sh`, wraps `GIT_SSH_COMMAND` with `BatchMode=yes -o ConnectTimeout=10`), `PERSONAL_GITREPOS`/`GITREPOS` (`lib/constants.sh`).
- `tests/setup_env/git_sync.bats` must NOT load the `tests/mocks/git` PATH stub — it is a scripted exit-code simulator used elsewhere, not real git plumbing, and would falsify every classification test.

---

## Verification (session-level)

- `make test` exits 0 — full BATS suite including the two new files, with no regression in existing counts.
- `make lint` exits 0 — shellcheck + `bash -n` + `zsh -n` clean on both new lib files and the entrypoint script.
- `./scripts/sync_git_repos.sh -h` exits 0, output mentions both "git sync" and "legacy sync" modes and lists `--git-only`/`--legacy-only`.
- `bats tests/setup_env/git_sync.bats` exits 0, including the explicit regression case: commit+push from a second clone without fetching in the first clone must classify `behind`, not `clean`.
- `bats tests/setup_env/legacy_rsync.bats` exits 0, including the exit-code-2-on-one-failed-leg case.
- `grep -q 'git-repos legacy-rsync' lib/update_summary.sh` — confirms `_UPDATE_SECTION_ORDER` updated.
- `[[ ! -f scripts/synch_git-repos.sh ]]` — old file gone.
- Manual smoke test on studio (or a machine simulating it via `MOCK_HOSTNAME_OUTPUT`): `./scripts/sync_git_repos.sh --git-only` against real `~/git-repos/personal/*` repos prints one line per repo and does not modify a repo that has uncommitted changes (`git status --porcelain` identical before/after).

---

### Task 1: `_git_repo_status` — fetch-first classification

```yaml-task
id: 1
description: Add _git_repo_status to lib/git_sync.sh classifying repos as missing/unreachable/no-upstream/dirty+ahead+behind, fetch always runs first
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: 'bats tests/setup_env/git_sync.bats'
    exit_code: 0
  - cmd: 'shellcheck lib/git_sync.sh'
    exit_code: 0
  - cmd: 'bash -n lib/git_sync.sh'
    exit_code: 0
  - cmd: 'zsh -n lib/git_sync.sh'
    exit_code: 0
max_retries: 3
files_touched:
  - lib/git_sync.sh
  - tests/setup_env/git_sync.bats
depends_on: []
parallel_group: core
```

**Files:**

`lib/git_sync.sh` (new):

```bash
#!/usr/bin/env bash
# lib/git_sync.sh — git-native repo sync (fetch/pull/push, never clobbers local work)

[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0

_git_repo_status() {
  local _path="$1"

  if [[ ! -d "${_path}" ]] || ! git -C "${_path}" rev-parse --git-dir >/dev/null 2>&1; then
    printf "missing\n"
    return 0
  fi

  if ! GIT_SSH_COMMAND="$(_git_ssh_opts)" git -C "${_path}" fetch --quiet 2>/dev/null; then
    printf "unreachable\n"
    return 0
  fi

  if ! git -C "${_path}" rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
    printf "no-upstream\n"
    return 0
  fi

  local _dirty=0
  [[ -n "$(git -C "${_path}" status --porcelain 2>/dev/null)" ]] && _dirty=1

  local _counts _ahead _behind
  _counts="$(git -C "${_path}" rev-list --left-right --count 'HEAD...@{u}' 2>/dev/null)"
  _ahead="$(printf '%s' "${_counts}" | awk '{print $1}')"
  _behind="$(printf '%s' "${_counts}" | awk '{print $2}')"

  printf "dirty=%d ahead=%d behind=%d\n" "${_dirty}" "${_ahead:-0}" "${_behind:-0}"
}
```

`tests/setup_env/git_sync.bats` (new) — real temp git repos, no `load_mocks` for `git`:

```bash
#!/usr/bin/env bats

load '../helpers/common.bash'

setup() {
  load_setup_env
  # lib/git_sync.sh isn't wired into setup_env.sh's source chain until Task 6
  # — source it explicitly so this file is self-contained regardless of
  # dispatch order.
  # shellcheck disable=SC1091
  source "${REPO_ROOT}/lib/git_sync.sh"
  export TESTDIR="${BATS_TEST_TMPDIR}"
  export ORIGIN="${TESTDIR}/origin.git"
  export CLONE="${TESTDIR}/clone"
  git init -q --bare "${ORIGIN}"
  git clone -q "${ORIGIN}" "${CLONE}"
  git -C "${CLONE}" commit -q --allow-empty -m init
  git -C "${CLONE}" push -q -u origin HEAD:master
}

@test "_git_repo_status reports missing for a nonexistent path" {
  run _git_repo_status "${TESTDIR}/does-not-exist"
  [ "$status" -eq 0 ]
  [ "$output" = "missing" ]
}

@test "_git_repo_status reports clean dirty=0 ahead=0 behind=0 on a fresh clone" {
  run _git_repo_status "${CLONE}"
  [ "$status" -eq 0 ]
  [ "$output" = "dirty=0 ahead=0 behind=0" ]
}

@test "_git_repo_status reports dirty=1 when there are uncommitted changes" {
  echo "scratch" > "${CLONE}/scratch.txt"
  run _git_repo_status "${CLONE}"
  [ "$output" = "dirty=1 ahead=0 behind=0" ]
}

@test "_git_repo_status reports ahead after a local commit" {
  git -C "${CLONE}" commit -q --allow-empty -m "local work"
  run _git_repo_status "${CLONE}"
  [ "$output" = "dirty=0 ahead=1 behind=0" ]
}

@test "_git_repo_status reports behind after a push from a second clone WITHOUT fetching first" {
  local second="${TESTDIR}/second-clone"
  git clone -q "${ORIGIN}" "${second}"
  git -C "${second}" commit -q --allow-empty -m "from second machine"
  git -C "${second}" push -q
  # ${CLONE} has NOT fetched — this is the exact regression the fetch-first
  # ordering fixes. Must report behind, not clean.
  run _git_repo_status "${CLONE}"
  [ "$output" = "dirty=0 ahead=0 behind=1" ]
}

@test "_git_repo_status reports diverged as ahead>0 and behind>0" {
  local second="${TESTDIR}/second-clone"
  git clone -q "${ORIGIN}" "${second}"
  git -C "${second}" commit -q --allow-empty -m "from second machine"
  git -C "${second}" push -q
  git -C "${CLONE}" commit -q --allow-empty -m "local unpushed work"
  run _git_repo_status "${CLONE}"
  [ "$output" = "dirty=0 ahead=1 behind=1" ]
}

@test "_git_repo_status reports unreachable when the remote is gone" {
  rm -rf "${ORIGIN}"
  run _git_repo_status "${CLONE}"
  [ "$output" = "unreachable" ]
}

@test "_git_repo_status reports no-upstream when there is no tracking branch" {
  local noup="${TESTDIR}/no-upstream-repo"
  mkdir -p "${noup}"
  git -C "${noup}" init -q
  git -C "${noup}" commit -q --allow-empty -m init
  run _git_repo_status "${noup}"
  [ "$output" = "no-upstream" ]
}
```

**Interfaces:**

- Produces: `_git_repo_status <path>` — echoes exactly one of `missing`, `unreachable`, `no-upstream`, or `dirty=<0|1> ahead=<n> behind=<n>` to stdout. Always returns 0 (classification never fails the caller). Consumed by Task 2's `_git_sync_one_repo`.
- Consumes: `_git_ssh_opts` (already defined in `lib/workflows.sh`, sourced before `lib/git_sync.sh` — see Task 6 for the `setup_env.sh` source-order change).

---

### Task 2: `_git_sync_one_repo` — decision table

```yaml-task
id: 2
description: Add _git_sync_one_repo to lib/git_sync.sh, deciding push/pull/warn from the dirty x ahead x behind compound status
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: 'bats tests/setup_env/git_sync.bats'
    exit_code: 0
  - cmd: 'shellcheck lib/git_sync.sh'
    exit_code: 0
  - cmd: 'bash -n lib/git_sync.sh'
    exit_code: 0
  - cmd: 'zsh -n lib/git_sync.sh'
    exit_code: 0
max_retries: 3
files_touched:
  - lib/git_sync.sh
  - tests/setup_env/git_sync.bats
depends_on: [1]
```

**Files:**

Append to `lib/git_sync.sh`:

```bash
_git_sync_one_repo() {
  local _path="$1"
  local _status
  _status="$(_git_repo_status "${_path}")"

  case "${_status}" in
    missing)
      return 0
      ;;
    unreachable)
      log_warn "${_path}: remote unreachable, skipping"
      return 1
      ;;
    no-upstream)
      log_warn "${_path}: no upstream configured, skipping"
      return 1
      ;;
    dirty=*)
      local _dirty _ahead _behind
      _dirty="$(printf '%s' "${_status}" | grep -oE 'dirty=[0-9]+' | cut -d= -f2)"
      _ahead="$(printf '%s' "${_status}" | grep -oE 'ahead=[0-9]+' | cut -d= -f2)"
      _behind="$(printf '%s' "${_status}" | grep -oE 'behind=[0-9]+' | cut -d= -f2)"

      if [[ ${_ahead} -gt 0 && ${_behind} -gt 0 ]]; then
        log_warn "${_path}: diverged (ahead ${_ahead}, behind ${_behind}), skipping — manual rebase/merge required"
        return 1
      fi
      if [[ ${_ahead} -gt 0 ]]; then
        if GIT_SSH_COMMAND="$(_git_ssh_opts)" git -C "${_path}" push --quiet; then
          return 0
        fi
        log_warn "${_path}: push failed"
        return 1
      fi
      if [[ ${_behind} -gt 0 ]]; then
        if [[ ${_dirty} -eq 1 ]]; then
          log_warn "${_path}: dirty tree, behind — skipping pull (unsafe)"
          return 1
        fi
        if GIT_SSH_COMMAND="$(_git_ssh_opts)" git -C "${_path}" pull --ff-only --quiet; then
          return 0
        fi
        log_warn "${_path}: pull failed"
        return 1
      fi
      return 0
      ;;
    *)
      log_warn "${_path}: unexpected status '${_status}'"
      return 1
      ;;
  esac
}
```

Add to `tests/setup_env/git_sync.bats` (one test per decision-table row, using the same `setup()` fixture from Task 1):

```bash
@test "_git_sync_one_repo no-ops on a clean repo" {
  run _git_sync_one_repo "${CLONE}"
  [ "$status" -eq 0 ]
  [ "$(git -C "${CLONE}" rev-parse HEAD)" = "$(git -C "${CLONE}" rev-parse '@{u}')" ]
}

@test "_git_sync_one_repo pushes when ahead and not dirty" {
  git -C "${CLONE}" commit -q --allow-empty -m "local work"
  run _git_sync_one_repo "${CLONE}"
  [ "$status" -eq 0 ]
  [ "$(git -C "${ORIGIN}" rev-parse master)" = "$(git -C "${CLONE}" rev-parse HEAD)" ]
}

@test "_git_sync_one_repo pushes when ahead EVEN IF dirty (push never touches working tree)" {
  git -C "${CLONE}" commit -q --allow-empty -m "local work"
  echo "scratch" > "${CLONE}/scratch.txt"
  run _git_sync_one_repo "${CLONE}"
  [ "$status" -eq 0 ]
  [ "$(git -C "${ORIGIN}" rev-parse master)" = "$(git -C "${CLONE}" rev-parse HEAD)" ]
  [ -f "${CLONE}/scratch.txt" ]
}

@test "_git_sync_one_repo pulls --ff-only when behind and clean" {
  local second="${TESTDIR}/second-clone"
  git clone -q "${ORIGIN}" "${second}"
  git -C "${second}" commit -q --allow-empty -m "from second machine"
  git -C "${second}" push -q
  run _git_sync_one_repo "${CLONE}"
  [ "$status" -eq 0 ]
  [ "$(git -C "${CLONE}" rev-parse HEAD)" = "$(git -C "${ORIGIN}" rev-parse master)" ]
}

@test "_git_sync_one_repo skips (does not pull) when behind and dirty" {
  local second="${TESTDIR}/second-clone"
  git clone -q "${ORIGIN}" "${second}"
  git -C "${second}" commit -q --allow-empty -m "from second machine"
  git -C "${second}" push -q
  echo "scratch" > "${CLONE}/scratch.txt"
  local _before
  _before="$(git -C "${CLONE}" rev-parse HEAD)"
  run _git_sync_one_repo "${CLONE}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"skipping pull"* ]]
  [ "$(git -C "${CLONE}" rev-parse HEAD)" = "${_before}" ]
}

@test "_git_sync_one_repo skips diverged repos without merging" {
  local second="${TESTDIR}/second-clone"
  git clone -q "${ORIGIN}" "${second}"
  git -C "${second}" commit -q --allow-empty -m "from second machine"
  git -C "${second}" push -q
  git -C "${CLONE}" commit -q --allow-empty -m "local unpushed work"
  local _before
  _before="$(git -C "${CLONE}" rev-parse HEAD)"
  run _git_sync_one_repo "${CLONE}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"diverged"* ]]
  [ "$(git -C "${CLONE}" rev-parse HEAD)" = "${_before}" ]
}

@test "_git_sync_one_repo returns 0 and no-ops on missing path" {
  run _git_sync_one_repo "${TESTDIR}/does-not-exist"
  [ "$status" -eq 0 ]
}

@test "_git_sync_one_repo returns 1 and warns on unreachable remote" {
  rm -rf "${ORIGIN}"
  run _git_sync_one_repo "${CLONE}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unreachable"* ]]
}
```

**Interfaces:**

- Consumes: `_git_repo_status` (Task 1), `_git_ssh_opts` (`lib/workflows.sh`), `log_warn` (`lib/helpers.sh`).
- Produces: `_git_sync_one_repo <path>` — returns 0 if the repo is clean/pushed/pulled/missing, 1 if it was skipped with a warning printed to stdout/stderr via `log_warn`. Consumed by Task 3's `sync_git_repos`.

---

### Task 3: `sync_git_repos()` — discovery, orchestration, exit contract

```yaml-task
id: 3
description: Add sync_git_repos to lib/git_sync.sh, discovering personal/ repos plus state-ledger and aggregating _git_sync_one_repo results into the 0/2 exit contract
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: 'bats tests/setup_env/git_sync.bats'
    exit_code: 0
  - cmd: 'shellcheck lib/git_sync.sh'
    exit_code: 0
  - cmd: 'bash -n lib/git_sync.sh'
    exit_code: 0
  - cmd: 'zsh -n lib/git_sync.sh'
    exit_code: 0
max_retries: 3
files_touched:
  - lib/git_sync.sh
  - tests/setup_env/git_sync.bats
depends_on: [2]
```

**Files:**

Append to `lib/git_sync.sh`:

```bash
sync_git_repos() {
  local _had_warning=0
  local _repo
  local _base="${_OVERRIDE_PERSONAL_GITREPOS:-${PERSONAL_GITREPOS}}"

  while IFS= read -r _repo; do
    [[ -z "${_repo}" ]] && continue
    log_info "git-repos: syncing ${_repo}"
    _git_sync_one_repo "${_repo}" || _had_warning=1
  done < <(find "${_base}" -maxdepth 2 -name .git -type d 2>/dev/null | sed 's#/\.git$##' | sort)

  local _ledger_dir="${_OVERRIDE_STATE_LEDGER_DIR:-${HOME}/.local/share/state-ledger}"
  if [[ -d "${_ledger_dir}" ]]; then
    log_info "git-repos: syncing ${_ledger_dir}"
    _git_sync_one_repo "${_ledger_dir}" || _had_warning=1
  fi

  [[ ${_had_warning} -eq 1 ]] && return 2
  return 0
}
```

`_OVERRIDE_PERSONAL_GITREPOS` follows the repo's existing test-seam pattern (`local _file="${_OVERRIDE_VAR:-real/path}"`, documented in `dotfiles-bats-test-infrastructure`) so tests point discovery at a temp directory instead of the real `~/git-repos/personal/`. Same pattern reused for `_OVERRIDE_STATE_LEDGER_DIR` (already used by `ensure_state_ledger` in `lib/workflows.sh`).

Add to `tests/setup_env/git_sync.bats`:

```bash
@test "sync_git_repos discovers repos via find -maxdepth 2 -name .git -type d" {
  local base="${TESTDIR}/fake-personal"
  mkdir -p "${base}/repo-a"
  git init -q --bare "${TESTDIR}/repo-a-origin.git"
  git clone -q "${TESTDIR}/repo-a-origin.git" "${base}/repo-a"
  git -C "${base}/repo-a" commit -q --allow-empty -m init
  git -C "${base}/repo-a" push -q -u origin HEAD:master
  export _OVERRIDE_PERSONAL_GITREPOS="${base}"
  export _OVERRIDE_STATE_LEDGER_DIR="${TESTDIR}/no-ledger"
  run sync_git_repos
  [ "$status" -eq 0 ]
  [[ "$output" == *"repo-a"* ]]
}

@test "sync_git_repos excludes git worktrees (gitdir-file .git, not a directory)" {
  local base="${TESTDIR}/fake-personal-wt"
  mkdir -p "${base}"
  git init -q --bare "${TESTDIR}/wt-origin.git"
  git clone -q "${TESTDIR}/wt-origin.git" "${base}/main-repo"
  git -C "${base}/main-repo" commit -q --allow-empty -m init
  git -C "${base}/main-repo" push -q -u origin HEAD:master
  git -C "${base}/main-repo" worktree add -q "${base}/main-repo-wt" -b wt-branch
  export _OVERRIDE_PERSONAL_GITREPOS="${base}"
  export _OVERRIDE_STATE_LEDGER_DIR="${TESTDIR}/no-ledger"
  run sync_git_repos
  [ "$status" -eq 0 ]
  [[ "$output" == *"main-repo"* ]]
  [[ "$output" != *"main-repo-wt"* ]]
}

@test "sync_git_repos returns 2 when a repo is skipped" {
  local base="${TESTDIR}/fake-personal-dirty"
  mkdir -p "${base}"
  git init -q --bare "${TESTDIR}/dirty-origin.git"
  git clone -q "${TESTDIR}/dirty-origin.git" "${base}/dirty-repo"
  git -C "${base}/dirty-repo" commit -q --allow-empty -m init
  git -C "${base}/dirty-repo" push -q -u origin HEAD:master
  local second="${TESTDIR}/dirty-second"
  git clone -q "${TESTDIR}/dirty-origin.git" "${second}"
  git -C "${second}" commit -q --allow-empty -m "from second machine"
  git -C "${second}" push -q
  echo scratch > "${base}/dirty-repo/scratch.txt"
  export _OVERRIDE_PERSONAL_GITREPOS="${base}"
  export _OVERRIDE_STATE_LEDGER_DIR="${TESTDIR}/no-ledger"
  run sync_git_repos
  [ "$status" -eq 2 ]
}

@test "sync_git_repos returns 0 when everything is already clean" {
  local base="${TESTDIR}/fake-personal-clean"
  mkdir -p "${base}"
  git init -q --bare "${TESTDIR}/clean-origin.git"
  git clone -q "${TESTDIR}/clean-origin.git" "${base}/clean-repo"
  git -C "${base}/clean-repo" commit -q --allow-empty -m init
  git -C "${base}/clean-repo" push -q -u origin HEAD:master
  export _OVERRIDE_PERSONAL_GITREPOS="${base}"
  export _OVERRIDE_STATE_LEDGER_DIR="${TESTDIR}/no-ledger"
  run sync_git_repos
  [ "$status" -eq 0 ]
}

@test "sync_git_repos is idempotent: running twice on a clean tree gives identical exit 0 both times" {
  local base="${TESTDIR}/fake-personal-idempotent"
  mkdir -p "${base}"
  git init -q --bare "${TESTDIR}/idem-origin.git"
  git clone -q "${TESTDIR}/idem-origin.git" "${base}/idem-repo"
  git -C "${base}/idem-repo" commit -q --allow-empty -m init
  git -C "${base}/idem-repo" push -q -u origin HEAD:master
  export _OVERRIDE_PERSONAL_GITREPOS="${base}"
  export _OVERRIDE_STATE_LEDGER_DIR="${TESTDIR}/no-ledger"
  run sync_git_repos
  [ "$status" -eq 0 ]
  run sync_git_repos
  [ "$status" -eq 0 ]
}
```

**Interfaces:**

- Consumes: `_git_sync_one_repo` (Task 2), `PERSONAL_GITREPOS` (`lib/constants.sh`), `log_info` (`lib/helpers.sh`).
- Produces: `sync_git_repos()` — no arguments, returns 0 (all synced) or 2 (one or more skipped). Consumed by `scripts/sync_git_repos.sh` (Task 5) and `run_update()` (Task 6). Honors `_OVERRIDE_PERSONAL_GITREPOS`/`_OVERRIDE_STATE_LEDGER_DIR` test seams.

---

### Task 4: `lib/legacy_rsync.sh` — `_is_legacy_sync_host` + `sync_legacy_dirs`

```yaml-task
id: 4
description: Add lib/legacy_rsync.sh with a shared studio-host predicate and studio-only rsync push to workstation/laptop-1 (exclude personal/) and full-tree ratna backup
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: 'bats tests/setup_env/legacy_rsync.bats'
    exit_code: 0
  - cmd: 'shellcheck lib/legacy_rsync.sh'
    exit_code: 0
  - cmd: 'bash -n lib/legacy_rsync.sh'
    exit_code: 0
  - cmd: 'zsh -n lib/legacy_rsync.sh'
    exit_code: 0
max_retries: 3
files_touched:
  - lib/legacy_rsync.sh
  - tests/setup_env/legacy_rsync.bats
depends_on: []
parallel_group: core
```

**Files:**

`lib/legacy_rsync.sh` (new):

```bash
#!/usr/bin/env bash
# lib/legacy_rsync.sh — one-way rsync push of legacy/no-git-access dirs, studio-only

[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0

_is_legacy_sync_host() {
  [[ "$(hostname -s)" == "studio" ]]
}

sync_legacy_dirs() {
  if ! _is_legacy_sync_host; then
    log_info "legacy-rsync: not studio, skipping"
    return 0
  fi

  local _had_failure=0
  local _src="${_OVERRIDE_GIT_REPOS_SRC:-${HOME}/git-repos}/"

  rsync -ar --delete --exclude=personal "${_src}" "bruce@workstation:~/git-repos/" \
    || { log_warn "legacy-rsync: workstation failed"; _had_failure=1; }
  rsync -ar --delete --exclude=personal "${_src}" "bruce@laptop-1:~/git-repos/" \
    || { log_warn "legacy-rsync: laptop-1 failed"; _had_failure=1; }
  rsync -ar --delete "${_src}" "bruce@ratna:~/git-repos/" \
    || { log_warn "legacy-rsync: ratna failed"; _had_failure=1; }

  [[ ${_had_failure} -eq 1 ]] && return 2
  return 0
}
```

`_OVERRIDE_GIT_REPOS_SRC` follows the same test-seam pattern as Task 3's `_OVERRIDE_PERSONAL_GITREPOS` — tests point the rsync source at a temp dir.

`tests/setup_env/legacy_rsync.bats` (new):

```bash
#!/usr/bin/env bats

load '../helpers/common.bash'

setup() {
  load_mocks
  load_setup_env
  # shellcheck disable=SC1091
  source "${REPO_ROOT}/lib/legacy_rsync.sh"
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  export _OVERRIDE_GIT_REPOS_SRC="${BATS_TEST_TMPDIR}/git-repos"
  mkdir -p "${_OVERRIDE_GIT_REPOS_SRC}"
}

@test "_is_legacy_sync_host is true on studio" {
  export MOCK_HOSTNAME_OUTPUT=studio
  run _is_legacy_sync_host
  [ "$status" -eq 0 ]
}

@test "_is_legacy_sync_host is false on any other host" {
  export MOCK_HOSTNAME_OUTPUT=workstation
  run _is_legacy_sync_host
  [ "$status" -eq 1 ]
}

@test "sync_legacy_dirs runs no rsync and returns 0 on non-studio" {
  export MOCK_HOSTNAME_OUTPUT=workstation
  run sync_legacy_dirs
  [ "$status" -eq 0 ]
  run grep -q rsync "${MOCK_CALLS_FILE}"
  [ "$status" -ne 0 ]
}

@test "sync_legacy_dirs pushes to workstation and laptop-1 with --exclude=personal, ratna without" {
  export MOCK_HOSTNAME_OUTPUT=studio
  run sync_legacy_dirs
  [ "$status" -eq 0 ]
  grep -q -- "--exclude=personal.*bruce@workstation" "${MOCK_CALLS_FILE}"
  grep -q -- "--exclude=personal.*bruce@laptop-1" "${MOCK_CALLS_FILE}"
  grep -q "bruce@ratna" "${MOCK_CALLS_FILE}"
  run grep -- "--exclude=personal.*bruce@ratna" "${MOCK_CALLS_FILE}"
  [ "$status" -ne 0 ]
}

@test "sync_legacy_dirs returns 2 when one rsync leg fails" {
  export MOCK_HOSTNAME_OUTPUT=studio
  export MOCK_RSYNC_EXIT=1
  run sync_legacy_dirs
  [ "$status" -eq 2 ]
}

@test "sync_legacy_dirs returns 0 when all three legs succeed" {
  export MOCK_HOSTNAME_OUTPUT=studio
  export MOCK_RSYNC_EXIT=0
  run sync_legacy_dirs
  [ "$status" -eq 0 ]
}
```

**Interfaces:**

- Consumes: `log_info`/`log_warn` (`lib/helpers.sh`).
- Produces: `_is_legacy_sync_host()` — no args, returns 0/1, no output. Also called directly from Task 6's `run_update` wiring. `sync_legacy_dirs()` — no args, returns 0 (synced or correctly skipped) or 2 (a leg failed). Consumed by `scripts/sync_git_repos.sh` (Task 5) and `run_update()` (Task 6). Honors `_OVERRIDE_GIT_REPOS_SRC` test seam.

---

### Task 5: `scripts/sync_git_repos.sh` entrypoint, delete old script

```yaml-task
id: 5
description: Add scripts/sync_git_repos.sh entrypoint (-h/--git-only/--legacy-only), delete scripts/synch_git-repos.sh and its stale tests
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: 'bats tests/scripts/unit.bats'
    exit_code: 0
  - cmd: 'shellcheck scripts/sync_git_repos.sh'
    exit_code: 0
  - cmd: 'bash -n scripts/sync_git_repos.sh'
    exit_code: 0
  - cmd: 'zsh -n scripts/sync_git_repos.sh'
    exit_code: 0
  - cmd: '[[ ! -f scripts/synch_git-repos.sh ]]'
    exit_code: 0
max_retries: 3
files_touched:
  - scripts/sync_git_repos.sh
  - scripts/synch_git-repos.sh
  - tests/scripts/unit.bats
depends_on: [3, 4]
parallel_group: wire
```

**Files:**

`scripts/sync_git_repos.sh` (new, executable — `chmod +x`):

```bash
#!/usr/bin/env bash
# scripts/sync_git_repos.sh — git-native sync for personal/ repos + state-ledger,
# studio-only rsync push for legacy/no-git-access dirs + ratna backup.

_sync_git_repos_usage() {
  cat <<'USAGE'
Usage: sync_git_repos.sh [--git-only|--legacy-only|-h|--help]

Two independent sync modes:

  git sync     Fetches every repo under ~/git-repos/personal/ plus
               ~/.local/share/state-ledger. Fast-forward pulls when
               behind, pushes when ahead, warns and skips dirty or
               diverged repos. Never force-pushes, never auto-merges.
               Safe to run on any machine.

  legacy sync  One-way rsync push (--delete) of legacy/no-git-access
               directories from studio to workstation and laptop-1
               (excluding personal/, which git sync already owns
               there), plus a full-tree backup push to ratna. Runs
               only on studio; no-ops elsewhere.

Options:
  --git-only     Run only the git sync.
  --legacy-only  Run only the legacy rsync sync.
  -h, --help     Show this help and exit.

Exit codes:
  0  everything synced cleanly
  2  completed, but one or more repos/targets were skipped (see warnings above)
USAGE
}

sync_git_repos_main() {
  local _mode="both"
  case "${1:-}" in
    -h|--help)
      _sync_git_repos_usage
      return 0
      ;;
    --git-only)
      _mode="git"
      ;;
    --legacy-only)
      _mode="legacy"
      ;;
  esac

  local _rc=0

  if [[ "${_mode}" == "both" || "${_mode}" == "git" ]]; then
    sync_git_repos || _rc=2
  fi
  if [[ "${_mode}" == "both" || "${_mode}" == "legacy" ]]; then
    sync_legacy_dirs || _rc=2
  fi

  return "${_rc}"
}

[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0

source "$(dirname "${BASH_SOURCE[0]}")/../lib/constants.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/helpers.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/workflows.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/git_sync.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/legacy_rsync.sh"

sync_git_repos_main "$@"
exit $?
```

`lib/workflows.sh` is sourced (for `_git_ssh_opts`) before `lib/git_sync.sh`, matching `scripts/bootstrap_mac.sh`'s precedent of sourcing individual libs directly rather than all of `setup_env.sh` (which would also run `detect_env` and the full `-t` dispatch tail — harmless but unnecessary for this entrypoint).

Delete `scripts/synch_git-repos.sh`.

In `tests/scripts/unit.bats`, remove the two `synch_git-repos.sh` tests (`prints error message when not on studio`, `calls rsync for all three hosts when on studio` — lines ~175-196, see `git grep -n "synch_git-repos" tests/scripts/unit.bats`) and add:

```bash
# ── sync_git_repos.sh ─────────────────────────────────────────────────────────

@test "sync_git_repos.sh -h prints usage mentioning both sync modes" {
  run bash "${REPO_ROOT}/scripts/sync_git_repos.sh" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"git sync"* ]]
  [[ "$output" == *"legacy sync"* ]]
}

@test "sync_git_repos.sh --help prints the same usage as -h" {
  run bash "${REPO_ROOT}/scripts/sync_git_repos.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--git-only"* ]]
  [[ "$output" == *"--legacy-only"* ]]
}

@test "sync_git_repos.sh --git-only skips the legacy rsync leg" {
  export MOCK_HOSTNAME_OUTPUT=studio
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  export HOME="${BATS_TEST_TMPDIR}"
  mkdir -p "${HOME}/git-repos/personal"
  run bash "${REPO_ROOT}/scripts/sync_git_repos.sh" --git-only
  run grep -q rsync "${MOCK_CALLS_FILE}"
  [ "$status" -ne 0 ]
}

@test "sync_git_repos.sh --legacy-only skips the git sync leg" {
  export MOCK_HOSTNAME_OUTPUT=studio
  export MOCK_CALLS_FILE="${BATS_TEST_TMPDIR}/mock_calls"
  export HOME="${BATS_TEST_TMPDIR}"
  mkdir -p "${HOME}/git-repos/personal"
  run bash "${REPO_ROOT}/scripts/sync_git_repos.sh" --legacy-only
  [ "$status" -eq 0 ]
  grep -q rsync "${MOCK_CALLS_FILE}"
}
```

These four run through the mocked `rsync`/`hostname`/`git` PATH (`load_mocks` equivalent — `tests/scripts/unit.bats` already loads mocks globally per its existing `setup()`), which is correct here since the assertions are about dispatch (which function ran), not git plumbing correctness (already covered by Task 1-3's real-repo tests).

**Interfaces:**

- Consumes: `sync_git_repos()` (Task 3), `sync_legacy_dirs()` (Task 4).
- Produces: `sync_git_repos_main <args>` and `_sync_git_repos_usage` — testable via sourcing (guarded), runnable via `bash scripts/sync_git_repos.sh`. Exit code is `sync_git_repos_main`'s return value (0 or 2).

---

### Task 6: wire into `run_update()` — exit-2-to-WARN contract, `legacy-rsync` skip case, section order

```yaml-task
id: 6
description: Source git_sync.sh/legacy_rsync.sh from setup_env.sh, call both from run_update's _run_all block with the exit-2-to-WARN translation, add legacy-rsync skip case to _update_record_start, add both sections to _UPDATE_SECTION_ORDER
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: 'bats tests/setup_env/workflows.bats'
    exit_code: 0
  - cmd: 'bats tests/setup_env/update_summary.bats'
    exit_code: 0
  - cmd: 'bats tests/setup_env/unit.bats'
    exit_code: 0
  - cmd: 'shellcheck setup_env.sh lib/workflows.sh lib/update_summary.sh'
    exit_code: 0
  - cmd: 'bash -n setup_env.sh'
    exit_code: 0
  - cmd: 'zsh -n setup_env.sh'
    exit_code: 0
  - cmd: "grep -q 'git-repos legacy-rsync' lib/update_summary.sh"
    exit_code: 0
max_retries: 3
files_touched:
  - setup_env.sh
  - lib/workflows.sh
  - lib/update_summary.sh
  - tests/setup_env/workflows.bats
  - tests/setup_env/update_summary.bats
  - tests/setup_env/unit.bats
depends_on: [3, 4]
parallel_group: wire
```

**Files:**

`setup_env.sh` — add two source lines after `lib/workflows.sh` (line 50):

```bash
source "$(dirname "${BASH_SOURCE[0]}")/lib/workflows.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/git_sync.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/legacy_rsync.sh"
```

`lib/workflows.sh` — in `run_update()`, insert immediately after the existing `ai-config` block (after line 471, `_update_record_end "ai-config" "${PIPESTATUS[0]}"`, before `update_aws_cli`):

```bash
    _update_record_start "git-repos"
    sync_git_repos 2>&1 | tee "${_DOTFILES_RUN_TMPDIR}/err_git-repos"
    local _git_repos_rc="${PIPESTATUS[0]}"
    _update_record_end "git-repos" "$(( _git_repos_rc == 2 ? 0 : _git_repos_rc ))"
    [[ ${_git_repos_rc} -eq 2 ]] && _update_warn "git-repos" "one or more repos skipped — see detail"

    _update_record_start "legacy-rsync"
    sync_legacy_dirs 2>&1 | tee "${_DOTFILES_RUN_TMPDIR}/err_legacy-rsync"
    local _legacy_rsync_rc="${PIPESTATUS[0]}"
    _update_record_end "legacy-rsync" "$(( _legacy_rsync_rc == 2 ? 0 : _legacy_rsync_rc ))"
    [[ ${_legacy_rsync_rc} -eq 2 ]] && _update_warn "legacy-rsync" "one or more rsync targets unreachable"
```

`lib/workflows.sh` `_update_record_start()` — this function lives in `lib/update_summary.sh`, not `lib/workflows.sh` (see the existing `apt`/`snap`/`mas` cases around line 95-123). Add a `legacy-rsync)` branch to its `case "${_section}" in` statement, alongside the existing `apt`/`snap` "not applicable" branches:

```bash
    legacy-rsync)
      _is_legacy_sync_host || _update_skip "legacy-rsync" "not studio"
      ;;
```

`lib/update_summary.sh` — change:

```bash
readonly _UPDATE_SECTION_ORDER=(
  brew softwareupdate apt snap mas claude terraform-skill npm pip gems
  ai-config oh-my-zsh tpm tfenv cheat.sh brew-drift
)
```

to:

```bash
readonly _UPDATE_SECTION_ORDER=(
  brew softwareupdate apt snap mas claude terraform-skill npm pip gems
  ai-config git-repos legacy-rsync oh-my-zsh tpm tfenv cheat.sh brew-drift
)
```

Add to `tests/setup_env/workflows.bats` (mocking `sync_git_repos`/`sync_legacy_dirs` as shell functions, matching this file's existing pattern for mocking `setup_ai_config`-style calls):

```bash
@test "run_update calls sync_git_repos and records git-repos section" {
  sync_git_repos() { echo "fake git sync"; return 0; }
  sync_legacy_dirs() { echo "fake legacy sync"; return 0; }
  export -f sync_git_repos sync_legacy_dirs
  export UPDATE=1
  run run_update
  [ "$status" -eq 0 ]
  [[ "$output" == *"fake git sync"* ]]
}

@test "run_update records git-repos as WARN (not OK) when sync_git_repos returns 2" {
  sync_git_repos() { echo "one repo skipped"; return 2; }
  sync_legacy_dirs() { return 0; }
  export -f sync_git_repos sync_legacy_dirs
  export UPDATE=1
  run run_update
  [ -f "${_DOTFILES_RUN_TMPDIR}/status_git-repos" ]
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_git-repos")" = "WARN" ]
}

@test "run_update records legacy-rsync as WARN (not OK) when sync_legacy_dirs returns 2" {
  sync_git_repos() { return 0; }
  sync_legacy_dirs() { echo "one target unreachable"; return 2; }
  export -f sync_git_repos sync_legacy_dirs
  export UPDATE=1
  run run_update
  [ -f "${_DOTFILES_RUN_TMPDIR}/status_legacy-rsync" ]
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_legacy-rsync")" = "WARN" ]
}

@test "run_update records git-repos as OK when sync_git_repos returns 0" {
  sync_git_repos() { return 0; }
  sync_legacy_dirs() { return 0; }
  export -f sync_git_repos sync_legacy_dirs
  export UPDATE=1
  run run_update
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_git-repos")" = "OK" ]
}
```

Note: this file's `${_DOTFILES_RUN_TMPDIR}` fixture setup and `run_update` invocation pattern already exists for the `ai-config`/`tfenv` sections — follow that exact existing pattern (same `setup()`, same way `_DOTFILES_RUN_TMPDIR` is created/exported) rather than reinventing it; inspect the file's existing `ai-config` test for the precise fixture boilerplate to copy.

Add to `tests/setup_env/update_summary.bats`:

```bash
@test "_UPDATE_SECTION_ORDER includes git-repos and legacy-rsync after ai-config" {
  local _joined
  _joined="${_UPDATE_SECTION_ORDER[*]}"
  [[ "${_joined}" == *"ai-config git-repos legacy-rsync"* ]]
}
```

Add to `tests/setup_env/unit.bats`:

```bash
@test "_update_record_start legacy-rsync case skips via _update_skip when not studio" {
  _is_legacy_sync_host() { return 1; }
  export -f _is_legacy_sync_host
  _update_record_start "legacy-rsync"
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_legacy-rsync")" = "SKIP" ]
}

@test "_update_record_start legacy-rsync case does not skip on studio" {
  _is_legacy_sync_host() { return 0; }
  export -f _is_legacy_sync_host
  _update_record_start "legacy-rsync"
  [ ! -f "${_DOTFILES_RUN_TMPDIR}/status_legacy-rsync" ]
}
```

(Match this file's existing `apt`/`snap` "not applicable" case tests for the `_DOTFILES_RUN_TMPDIR` setup boilerplate.)

**Interfaces:**

- Consumes: `sync_git_repos()` (Task 3), `sync_legacy_dirs()` (Task 4), `_is_legacy_sync_host()` (Task 4), `_update_record_start`/`_update_record_end`/`_update_skip`/`_update_warn` (pre-existing, `lib/update_summary.sh`).
- Produces: `run_update()` now includes `git-repos` and `legacy-rsync` in its summary output; `_UPDATE_SECTION_ORDER` reflects both. No new public functions.

---

### Task 7: docs — CLAUDE.md convention note, plan index status

```yaml-task
id: 7
description: Document sync_git_repos.sh in CLAUDE.md Key Conventions and mark the plan Done in docs/superpowers/README.md (docs-only, no behavior change)
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: "grep -q 'scripts/sync_git_repos.sh' CLAUDE.md"
    exit_code: 0
  - cmd: 'grep -q "sync-git-repos" docs/superpowers/README.md'
    exit_code: 0
max_retries: 2
files_touched:
  - CLAUDE.md
  - docs/superpowers/README.md
depends_on: [5, 6]
```

**Files:**

`CLAUDE.md` — add a bullet to the existing "Key Conventions" list (same section as the `_UPDATE_SECTION_ORDER coupling` bullet near the end of the file):

```markdown
- **`scripts/sync_git_repos.sh`** replaces the old rsync-only sync script. Two independent modes: git-native fetch/pull/push for `personal/` repos + `state-ledger` (safe on any of the three dev machines — never force-pushes, never auto-merges a diverged repo), and studio-only rsync push for legacy/no-git-access directories + a full-tree ratna backup. Runs automatically as part of `-t update`; `--git-only`/`--legacy-only`/`-h` for standalone use. See `docs/superpowers/specs/2026-07-18-sync-git-repos-design.md` for the full design and the dirty/ahead/behind decision table.
```

`docs/superpowers/README.md` — update the row added during brainstorming from `Pending` to `Done`, and link the plan:

```markdown
| 2026-07-18 | [sync-git-repos](plans/2026-07-18-sync-git-repos.md) | [spec](specs/2026-07-18-sync-git-repos-design.md) | Done |
```

**Interfaces:** None — docs-only, no code interfaces produced or consumed.
