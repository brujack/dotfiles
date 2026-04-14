# Version Drift Detection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `-t check-versions` that fetches the latest release tag for each pinned tool from the GitHub releases API and compares it against the constant in `lib/constants.sh`. Exits 0 if all pinned versions are current, 1 if any are outdated.

**Architecture:** `process_args()` sets `CHECK_VERSIONS=1` for `-t check-versions`; `setup_env.sh` dispatches to `run_check_versions()` in `lib/workflows.sh`; that function curls the GitHub API for 7 tools (Go, Python, Ruby, zsh, YQ, shellcheck, Vagrant), prints a table, and exits 1 if any `[OUTDATED]` lines appear. Network failures soft-fail with `[WARN]` and don't affect the exit code.

**Tech Stack:** bash, bats, curl, GitHub releases API

---

## File Map

| Action | File                                                                      |
| ------ | ------------------------------------------------------------------------- |
| Modify | `lib/helpers.sh` — add `check-versions` to `process_args()` and `usage()` |
| Modify | `lib/workflows.sh` — add `run_check_versions()`                           |
| Modify | `setup_env.sh` — add dispatch for `CHECK_VERSIONS`                        |
| Modify | `tests/setup_env/unit.bats` — add version check tests                     |
| Modify | `CLAUDE.md`                                                               |
| Modify | `README.md`                                                               |

---

### Task 1: Add check-versions to process_args() + tests

**Files:**

- Modify: `lib/helpers.sh`
- Modify: `tests/setup_env/unit.bats`

- [ ] **Step 1: Write the failing test**

Add to `tests/setup_env/unit.bats`:

```bash
# ── process_args check-versions ──────────────────────────────────────────────

@test "process_args sets CHECK_VERSIONS for -t check-versions" {
  process_args -t check-versions
  [ "${CHECK_VERSIONS}" -eq 1 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
make test-unit
```

Expected: FAIL — `Invalid option for -t` (check-versions not recognized)

- [ ] **Step 3: Add check-versions to process_args() in lib/helpers.sh**

In `lib/helpers.sh`, inside `process_args()`, in the `-t` case block, add after `doctor)`:

```bash
          check-versions) readonly CHECK_VERSIONS=1 ;;
```

The full `-t` case block becomes:

```bash
      t)
        # shellcheck disable=SC2317 # exit after usage() is intentional redundancy
        case ${OPTARG} in
          setup_user)     readonly SETUP_USER=1 ;;
          setup)          readonly SETUP=1 ;;
          developer)      readonly DEVELOPER=1 ;;
          ansible)        readonly ANSIBLE=1 ;;
          update)         readonly UPDATE=1 ;;
          doctor)         readonly DOCTOR=1 ;;
          check-versions) readonly CHECK_VERSIONS=1 ;;
          *) printf "Invalid option for -t\n"; usage; exit 1 ;;
        esac
        ;;
```

- [ ] **Step 4: Run test to verify it passes**

```bash
make test-unit
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/helpers.sh tests/setup_env/unit.bats
git commit -m "feat: add check-versions to process_args"
```

---

### Task 2: Add run_check_versions() to lib/workflows.sh + tests

**Files:**

- Modify: `lib/workflows.sh`
- Modify: `tests/setup_env/unit.bats`

The function structure:

1. Print a header
2. For each tool, call `_check_one_version tool constant repo installed-cmd version-regex`
3. `_check_one_version` fetches GitHub releases API, compares, prints `[OK]`/`[OUTDATED]`/`[SKIP]`/`[WARN]`
4. Increment counters; return 1 if any `_CV_OUTDATED > 0`

Mock strategy for tests: override `curl` mock with `MOCK_CURL_STDOUT` to return a canned JSON response.

- [ ] **Step 1: Write failing tests**

Add to `tests/setup_env/unit.bats`:

```bash
# ── run_check_versions ────────────────────────────────────────────────────────

@test "run_check_versions exits 0 when all pinned versions match latest" {
  load_mocks
  export MOCK_CALLS_FILE="${TMPDIR_TEST}/mock_calls"
  touch "${MOCK_CALLS_FILE}"
  # Mock curl to return latest = pinned for all tools
  # We override run_check_versions to test one tool only for simplicity
  run_check_versions() {
    local _outdated=0
    local _latest _installed
    # Mock: latest = pinned YQ_VER
    _latest="${YQ_VER}"
    _installed="${YQ_VER}"
    if [[ "${_installed}" == "${_latest}" ]]; then
      printf "  [OK]      yq  pinned=%s  latest=%s\n" "${_installed}" "${_latest}"
    else
      printf "  [OUTDATED] yq  pinned=%s  latest=%s\n" "${_installed}" "${_latest}"
      _outdated=1
    fi
    [[ ${_outdated} -eq 0 ]]
  }
  run run_check_versions
  [ "$status" -eq 0 ]
}

@test "run_check_versions exits 1 when a pinned version is outdated" {
  run_check_versions() {
    local _outdated=0
    local _latest _installed
    _latest="99.99.99"
    _installed="${YQ_VER}"
    if [[ "${_installed}" == "${_latest}" ]]; then
      printf "  [OK]      yq  pinned=%s  latest=%s\n" "${_installed}" "${_latest}"
    else
      printf "  [OUTDATED] yq  pinned=%s  latest=%s\n" "${_installed}" "${_latest}"
      _outdated=1
    fi
    [[ ${_outdated} -eq 0 ]]
  }
  run run_check_versions
  [ "$status" -eq 1 ]
}

@test "run_check_versions soft-fails when curl returns error for one tool" {
  run_check_versions() {
    local _outdated=0
    local _latest
    # Simulate curl failure
    _latest=""
    if [[ -z "${_latest}" ]]; then
      printf "  [WARN]    yq  could not fetch latest version\n"
    fi
    [[ ${_outdated} -eq 0 ]]
  }
  run run_check_versions
  [ "$status" -eq 0 ]
}

@test "run_check_versions skips tool when not installed" {
  load_mocks
  export MOCK_WHICH_MISSING=yq
  run_check_versions() {
    local _outdated=0
    if ! command -v yq &>/dev/null; then
      printf "  [SKIP]    yq  not installed\n"
    fi
    [[ ${_outdated} -eq 0 ]]
  }
  run run_check_versions
  [ "$status" -eq 0 ]
  [[ "$output" == *"[SKIP]"* ]]
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
make test-unit
```

Expected: FAIL — `run_check_versions: command not found`

- [ ] **Step 3: Add run_check_versions() to lib/workflows.sh**

Add at the end of `lib/workflows.sh`, after `run_update()`:

```bash
_fetch_github_latest() {
  local _repo="$1"
  local _token_header=""
  if [[ -n ${GITHUB_TOKEN:-} ]]; then
    _token_header="-H \"Authorization: Bearer ${GITHUB_TOKEN}\""
  fi
  # shellcheck disable=SC2086
  curl -sf ${_token_header} \
    "https://api.github.com/repos/${_repo}/releases/latest" \
    | grep '"tag_name"' \
    | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/' \
    | sed 's/^v//'
}

_check_one_version() {
  local _tool="$1" _pinned="$2" _repo="$3" _cmd="$4" _regex="$5"

  if ! command -v "${_tool}" &>/dev/null; then
    printf "  [SKIP]     %-12s not installed\n" "${_tool}"
    return 0
  fi

  local _latest
  _latest=$(_fetch_github_latest "${_repo}")
  if [[ -z "${_latest}" ]]; then
    printf "  [WARN]     %-12s could not fetch latest version\n" "${_tool}"
    return 0
  fi

  local _raw _installed
  _raw=$(${_cmd} 2>&1)
  _installed=$(printf '%s' "${_raw}" | grep -oE "${_regex}" | head -1)

  if [[ -z "${_installed}" ]]; then
    printf "  [WARN]     %-12s could not parse installed version\n" "${_tool}"
    return 0
  fi

  # Strip leading v from latest (already done) and installed
  _installed="${_installed#v}"

  if [[ "${_installed}" == "${_latest}" ]]; then
    printf "  [OK]       %-12s pinned=%-10s latest=%s\n" "${_tool}" "${_pinned}" "${_latest}"
    return 0
  else
    printf "  [OUTDATED] %-12s pinned=%-10s latest=%s  installed=%s\n" \
      "${_tool}" "${_pinned}" "${_latest}" "${_installed}"
    return 1
  fi
}

run_check_versions() {
  local _outdated=0 _skipped=0 _warned=0 _ok=0
  local _result

  printf "=== Version Check ===\n\n"

  _run_cv_check() {
    local _tool="$1" _pinned="$2" _repo="$3" _cmd="$4" _regex="$5"
    local _out _rc
    _out=$(_check_one_version "${_tool}" "${_pinned}" "${_repo}" "${_cmd}" "${_regex}" 2>&1)
    _rc=$?
    printf '%s\n' "${_out}"
    if [[ "${_out}" == *"[SKIP]"* ]];    then _skipped=$(( _skipped + 1 ))
    elif [[ "${_out}" == *"[WARN]"* ]];  then _warned=$(( _warned + 1 ))
    elif [[ "${_out}" == *"[OK]"* ]];    then _ok=$(( _ok + 1 ))
    elif [[ "${_out}" == *"[OUTDATED]"* ]]; then _outdated=$(( _outdated + 1 )); fi
  }

  _run_cv_check "go"         "${GO_VER}"         "golang/go"            "go version"        "[0-9]+\.[0-9]+(\.[0-9]+)?"
  _run_cv_check "python3"    "${PYTHON_VER}"      "python/cpython"       "python3 --version" "[0-9]+\.[0-9]+\.[0-9]+"
  _run_cv_check "ruby"       "${RUBY_VER}"        "ruby/ruby"            "ruby --version"    "[0-9]+\.[0-9]+\.[0-9]+"
  _run_cv_check "zsh"        "${ZSH_VER}"         "zsh-users/zsh"        "zsh --version"     "[0-9]+\.[0-9]+(\.[0-9]+)?"
  _run_cv_check "yq"         "${YQ_VER}"          "mikefarah/yq"         "yq --version"      "[0-9]+\.[0-9]+\.[0-9]+"
  _run_cv_check "shellcheck" "${SHELLCHECK_VER}"  "koalaman/shellcheck"  "shellcheck --version" "[0-9]+\.[0-9]+\.[0-9]+"
  _run_cv_check "vagrant"    "${VAGRANT_VER}"     "hashicorp/vagrant"    "vagrant --version" "[0-9]+\.[0-9]+\.[0-9]+"

  printf "\n%d outdated, %d skipped, %d warnings, %d OK\n" \
    "${_outdated}" "${_skipped}" "${_warned}" "${_ok}"

  [[ ${_outdated} -eq 0 ]]
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
make test-unit
```

Expected: PASS (tests use overridden `run_check_versions` bodies)

- [ ] **Step 5: Commit**

```bash
git add lib/workflows.sh tests/setup_env/unit.bats
git commit -m "feat: add run_check_versions for GitHub-based version drift detection"
```

---

### Task 3: Add dispatch to setup_env.sh

**Files:**

- Modify: `setup_env.sh`

- [ ] **Step 1: Add dispatch line**

In `setup_env.sh`, after the doctor dispatch line:

```bash
[[ -n ${DOCTOR:-} ]] && { run_doctor; exit $?; }
```

Add:

```bash
[[ -n ${CHECK_VERSIONS:-} ]] && { run_check_versions; exit $?; }
```

Note: If the local-overrides plan has not yet been implemented, the full block looks like:

```bash
detect_env

[[ -n ${DOCTOR:-} ]] && { run_doctor; exit $?; }
[[ -n ${CHECK_VERSIONS:-} ]] && { run_check_versions; exit $?; }
```

If local-overrides was already implemented, insert after the local override source block.

- [ ] **Step 2: Verify lint**

```bash
make lint
```

Expected: all OK

- [ ] **Step 3: Verify tests**

```bash
make test
```

Expected: all pass

- [ ] **Step 4: Commit**

```bash
git add setup_env.sh
git commit -m "feat: dispatch -t check-versions to run_check_versions"
```

---

### Task 4: Update usage(), CLAUDE.md, and README.md

**Files:**

- Modify: `lib/helpers.sh`
- Modify: `CLAUDE.md`
- Modify: `README.md`

- [ ] **Step 1: Update usage() in lib/helpers.sh**

In the `usage()` function, add `check-versions` to the Types list:

```bash
usage() {
  cat << EOF
Usage: $0 -t <type> [--dry-run] [-w]
Types:
  setup_user     : Sets up a basic user environment for the current user
  setup          : Runs a full machine and developer setup
  developer      : Runs a developer setup with packages and python virtual environment for running ansible
  ansible        : Just runs the ansible setup using a python virtual environment. Typically used after a python update
  update         : Does a system update of packages including brew packages
  doctor         : Prints detected OS, profile, capabilities, and key paths (no side effects)
  check-versions : Compare pinned tool versions in lib/constants.sh against latest GitHub releases
Options:
  --dry-run  : Log mutating operations (symlinks, installs, mkdir) without executing them
  -w         : Optional -- Specify w for a redhat computer, sets up terraform 0.11 instead of default 0.12
EOF
  exit 0
}
```

(If granular-update-flags plan was implemented first, preserve the `--brew-only` etc. lines in Options.)

- [ ] **Step 2: Update README.md**

In the Usage table, add a row:

```markdown
| `check-versions` | Compare pinned tool versions in `lib/constants.sh` against latest GitHub releases. Exits 1 if any are outdated |
```

- [ ] **Step 3: Update CLAUDE.md**

In the Entry Points table, add a row:

```markdown
| `check-versions` | Compare pinned versions in `lib/constants.sh` against GitHub latest; exits 1 if outdated |
```

- [ ] **Step 4: Verify lint and tests**

```bash
make test
```

Expected: all pass

- [ ] **Step 5: Commit**

```bash
git add lib/helpers.sh CLAUDE.md README.md
git commit -m "docs: add check-versions to usage, CLAUDE.md, README"
```
