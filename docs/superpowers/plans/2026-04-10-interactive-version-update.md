# Interactive Version Update Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an `--update` flag to `check-versions` that prompts interactively for each outdated pin and updates `lib/constants.sh` in-place, including URL constants that embed the version.

**Architecture:** `_run_cv_check` (inner helper of `run_check_versions`) detects `[OUTDATED]` results. When `UPDATE_VERSIONS` is set, it calls a new `_prompt_version_update()` helper that reads user input and calls `_update_version_pin()` to sed-update `lib/constants.sh`. A further `_update_url_pins()` helper handles URL vars (`GO_DOWNLOAD_FILENAME`, `GO_DOWNLOAD_URL`, `YQ_URL`) that embed the version string. Non-interactive behavior (no `--update`) is unchanged.

**Tech Stack:** Bash, BATS, sed (BSD-compatible with `.bak` extension), `lib/helpers.sh`, `lib/workflows.sh`, `lib/constants.sh`

---

## File Map

| File | Change |
|---|---|
| `lib/helpers.sh` | Add `--update` to `process_args()` long-option loop (line 438); add `--update` to `usage()` (line 212) |
| `lib/workflows.sh` | Add `_update_version_pin()`, `_update_url_pins()`, `_prompt_version_update()` at top of `run_check_versions` scope; add `_var` param to every `_run_cv_check` call; add prompt dispatch in `_run_cv_check` |
| `tests/setup_env/unit.bats` | Add test for `process_args --update` |
| `tests/setup_env/workflows.bats` | Add tests for `_update_version_pin`, `_update_url_pins` |

---

## Task 1: Add `--update` flag to `process_args()` and `usage()`

**Files:**
- Modify: `lib/helpers.sh:212` (usage string)
- Modify: `lib/helpers.sh:438` (process_args long-option loop)
- Test: `tests/setup_env/unit.bats`

- [ ] **Step 1: Write the failing test**

In `tests/setup_env/unit.bats`, find the block of `process_args` tests (search for `@test "process_args --brew-only sets UPDATE_BREW"`). Add immediately after:

```bash
@test "process_args --update sets UPDATE_VERSIONS" {
  process_args --update -t check-versions
  [[ -n ${UPDATE_VERSIONS:-} ]]
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bats tests/setup_env/unit.bats --filter "process_args --update"
```

Expected: FAIL — `UPDATE_VERSIONS` not set

- [ ] **Step 3: Add `--update` to `process_args()` in `lib/helpers.sh`**

In `lib/helpers.sh` at line 438 (after `--mas-install)  readonly SETUP_MAS=1 ;;`), add:

```bash
      --update)        readonly UPDATE_VERSIONS=1 ;;
```

- [ ] **Step 4: Run test to verify it passes**

```bash
bats tests/setup_env/unit.bats --filter "process_args --update"
```

Expected: PASS

- [ ] **Step 5: Update `usage()` in `lib/helpers.sh`**

Find line 212 in `lib/helpers.sh` (the `check-versions` entry in `usage()`):

```
  check-versions : Compare pinned tool versions in lib/constants.sh against latest GitHub releases
```

Replace with:

```
  check-versions : Compare pinned tool versions in lib/constants.sh against latest GitHub releases
                   --update   Prompt to update each outdated pin in constants.sh
```

Also add `--update` to the Options section after `--mas-install`:

```
  --update        : (check-versions only) Prompt to update outdated version pins in lib/constants.sh
```

- [ ] **Step 6: Run all tests**

```bash
make test
```

Expected: all tests pass

- [ ] **Step 7: Commit**

```bash
git add lib/helpers.sh tests/setup_env/unit.bats
git commit -m "feat: add --update flag to process_args for check-versions"
```

---

## Task 2: Add `_update_version_pin()` helper

**Files:**
- Modify: `lib/workflows.sh` (add helper before `run_check_versions` at line 1409)
- Test: `tests/setup_env/workflows.bats`

The helper sed-updates a version var in `lib/constants.sh`. Tests use a temp copy of constants.sh.

- [ ] **Step 1: Write the failing tests**

Add a new section to `tests/setup_env/workflows.bats` after the `run_mas_install` section:

```bash
# ── _update_version_pin ───────────────────────────────────────────────────────

setup_constants_copy() {
  # Creates a writable temp copy of lib/constants.sh for update tests
  _CONSTANTS_COPY="${BATS_TEST_TMPDIR}/constants.sh"
  cp "${REPO_ROOT}/lib/constants.sh" "${_CONSTANTS_COPY}"
  export _TEST_CONSTANTS_PATH="${_CONSTANTS_COPY}"
}

@test "_update_version_pin updates GO_VER in constants.sh" {
  setup_constants_copy
  # Temporarily override the path _update_version_pin uses
  export _OVERRIDE_CONSTANTS_PATH="${_TEST_CONSTANTS_PATH}"
  _update_version_pin "go" "GO_VER" "1.26" "1.27"
  grep -q 'GO_VER="1.27"' "${_TEST_CONSTANTS_PATH}"
}

@test "_update_version_pin does not modify other vars" {
  setup_constants_copy
  export _OVERRIDE_CONSTANTS_PATH="${_TEST_CONSTANTS_PATH}"
  _update_version_pin "go" "GO_VER" "1.26" "1.27"
  grep -q 'PYTHON_VER=' "${_TEST_CONSTANTS_PATH}"
  # Python version unchanged
  grep -q "PYTHON_VER=\"${PYTHON_VER}\"" "${_TEST_CONSTANTS_PATH}"
}

@test "_update_version_pin removes .bak file after update" {
  setup_constants_copy
  export _OVERRIDE_CONSTANTS_PATH="${_TEST_CONSTANTS_PATH}"
  _update_version_pin "go" "GO_VER" "1.26" "1.27"
  [[ ! -f "${_TEST_CONSTANTS_PATH}.bak" ]]
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bats tests/setup_env/workflows.bats --filter "_update_version_pin"
```

Expected: FAIL — `_update_version_pin: command not found`

- [ ] **Step 3: Add `_update_url_pins()` stub and `_update_version_pin()` to `lib/workflows.sh`**

Insert before `run_check_versions()` at line 1409. Add the stub first so `_update_version_pin` can call it — Task 3 will replace the stub with the real implementation:

```bash
# Stub — replaced with full implementation in Task 3
_update_url_pins() {
  : # no-op until full implementation
}

_update_version_pin() {
  local _tool="$1" _var="$2" _old="$3" _new="$4"
  local _constants="${_OVERRIDE_CONSTANTS_PATH:-$(dirname "${BASH_SOURCE[0]}")/../lib/constants.sh}"
  sed -i.bak "s|^${_var}=\"${_old}\"|${_var}=\"${_new}\"|" "${_constants}"
  rm -f "${_constants}.bak"
  _update_url_pins "${_tool}" "${_old}" "${_new}" "${_constants}"
}
```

Note: `_OVERRIDE_CONSTANTS_PATH` is only set in tests — production always resolves to `lib/constants.sh` relative to `lib/workflows.sh`.

- [ ] **Step 4: Run tests to verify they pass**

```bash
bats tests/setup_env/workflows.bats --filter "_update_version_pin"
```

Expected: 3 tests PASS

- [ ] **Step 5: Commit**

```bash
git add lib/workflows.sh tests/setup_env/workflows.bats
git commit -m "feat: add _update_version_pin helper to run_check_versions"
```

---

## Task 3: Add `_update_url_pins()` helper

**Files:**
- Modify: `lib/workflows.sh` (add before `_update_version_pin`)
- Test: `tests/setup_env/workflows.bats`

- [ ] **Step 1: Write the failing tests**

Add to `tests/setup_env/workflows.bats` after the `_update_version_pin` section:

```bash
# ── _update_url_pins ──────────────────────────────────────────────────────────

@test "_update_url_pins updates GO_DOWNLOAD_FILENAME for go" {
  setup_constants_copy
  # Patch a known old filename into the copy so replacement is predictable
  sed -i.bak 's|^GO_DOWNLOAD_FILENAME=.*|GO_DOWNLOAD_FILENAME="go1.26.1.linux-amd64.tar.gz"|' "${_TEST_CONSTANTS_PATH}"
  rm -f "${_TEST_CONSTANTS_PATH}.bak"
  _update_url_pins "go" "1.26" "1.27" "${_TEST_CONSTANTS_PATH}"
  grep -q 'go1.27' "${_TEST_CONSTANTS_PATH}"
}

@test "_update_url_pins updates GO_DOWNLOAD_URL for go" {
  setup_constants_copy
  sed -i.bak 's|^GO_DOWNLOAD_FILENAME=.*|GO_DOWNLOAD_FILENAME="go1.26.1.linux-amd64.tar.gz"|' "${_TEST_CONSTANTS_PATH}"
  sed -i.bak "s|go1.26.1.linux-amd64.tar.gz|go1.26.1.linux-amd64.tar.gz|g" "${_TEST_CONSTANTS_PATH}"
  rm -f "${_TEST_CONSTANTS_PATH}.bak"
  _update_url_pins "go" "1.26" "1.27" "${_TEST_CONSTANTS_PATH}"
  # GO_DOWNLOAD_URL should no longer contain the old filename
  ! grep -q 'go1.26.1' "${_TEST_CONSTANTS_PATH}"
}

@test "_update_url_pins updates YQ_URL for yq" {
  setup_constants_copy
  _update_url_pins "yq" "${YQ_VER}" "9.9.9" "${_TEST_CONSTANTS_PATH}"
  grep -q '/v9.9.9/' "${_TEST_CONSTANTS_PATH}"
}

@test "_update_url_pins leaves constants unchanged for vagrant" {
  setup_constants_copy
  cp "${_TEST_CONSTANTS_PATH}" "${BATS_TEST_TMPDIR}/constants_before.sh"
  _update_url_pins "vagrant" "2.4.9" "2.5.0" "${_TEST_CONSTANTS_PATH}"
  diff "${_TEST_CONSTANTS_PATH}" "${BATS_TEST_TMPDIR}/constants_before.sh"
}

@test "_update_url_pins leaves constants unchanged for shellcheck" {
  setup_constants_copy
  cp "${_TEST_CONSTANTS_PATH}" "${BATS_TEST_TMPDIR}/constants_before.sh"
  _update_url_pins "shellcheck" "${SHELLCHECK_VER}" "0.12.0" "${_TEST_CONSTANTS_PATH}"
  diff "${_TEST_CONSTANTS_PATH}" "${BATS_TEST_TMPDIR}/constants_before.sh"
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
bats tests/setup_env/workflows.bats --filter "_update_url_pins"
```

Expected: FAIL — `_update_url_pins: command not found`

- [ ] **Step 3: Replace the `_update_url_pins()` stub in `lib/workflows.sh` with the full implementation**

Find the stub `_update_url_pins() { : ; }` added in Task 2 and replace it with:

```bash
_update_url_pins() {
  local _tool="$1" _old="$2" _new="$3" _constants="$4"

  case "${_tool}" in
    go)
      local _old_filename _new_filename
      _old_filename=$(grep '^GO_DOWNLOAD_FILENAME=' "${_constants}" | cut -d'"' -f2)
      # Replace the full semver prefix (e.g. go1.26.1 → go1.27.x)
      # Pattern: go followed by digits.digits.digits up to the next dot
      _new_filename=$(printf '%s' "${_old_filename}" | \
        sed 's|^go[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.|go'"${_new}"'.|')
      if [[ "${_old_filename}" != "${_new_filename}" ]]; then
        sed -i.bak "s|^GO_DOWNLOAD_FILENAME=\"${_old_filename}\"|GO_DOWNLOAD_FILENAME=\"${_new_filename}\"|" "${_constants}"
        rm -f "${_constants}.bak"
        # GO_DOWNLOAD_URL embeds the filename — replace old filename with new throughout
        sed -i.bak "s|${_old_filename}|${_new_filename}|g" "${_constants}"
        rm -f "${_constants}.bak"
      fi
      ;;
    yq)
      # YQ_URL contains /v<version>/ — replace that segment
      sed -i.bak "s|/v${_old}/|/v${_new}/|g" "${_constants}"
      rm -f "${_constants}.bak"
      ;;
    *)
      # vagrant, python3, ruby, zsh, shellcheck — no URL vars to update
      ;;
  esac
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bats tests/setup_env/workflows.bats --filter "_update_url_pins"
```

Expected: 5 tests PASS

- [ ] **Step 5: Run all tests**

```bash
make test
```

- [ ] **Step 6: Commit**

```bash
git add lib/workflows.sh tests/setup_env/workflows.bats
git commit -m "feat: add _update_url_pins helper for in-place URL constant updates"
```

---

## Task 4: Wire interactive prompting into `run_check_versions`

**Files:**
- Modify: `lib/workflows.sh` (add `_prompt_version_update`; update `_run_cv_check` and all `_run_cv_check` calls)

No new tests needed for this task — the prompt flow is integration-level and relies on stdin, which is outside the mock harness. Existing `_update_version_pin` and `_update_url_pins` tests already cover the write path.

- [ ] **Step 1: Add `_prompt_version_update()` before `run_check_versions`**

Insert immediately before `run_check_versions()` at line 1409 (after the other helpers added in Tasks 2–3):

```bash
_prompt_version_update() {
  local _tool="$1" _var="$2" _pinned="$3" _latest="$4"
  local _reply
  printf "  Update %s from %s to %s? [y/N] " "${_tool}" "${_pinned}" "${_latest}"
  read -r _reply
  if [[ "${_reply}" =~ ^[Yy]$ ]]; then
    _update_version_pin "${_tool}" "${_var}" "${_pinned}" "${_latest}"
    printf "  Updated %s → %s\n" "${_var}" "${_latest}"
  fi
}
```

- [ ] **Step 2: Update `_run_cv_check` inside `run_check_versions`**

The current `_run_cv_check` inner function (inside `run_check_versions`) is:

```bash
  _run_cv_check() {
    local _tool="$1" _pinned="$2" _repo="$3" _cmd="$4" _regex="$5"
    local _out
    _out=$(_check_one_version "${_tool}" "${_pinned}" "${_repo}" "${_cmd}" "${_regex}" 2>&1)
    printf '%s\n' "${_out}"
    if [[ "${_out}" == *"[SKIP]"* ]];       then _skipped=$(( _skipped + 1 ))
    elif [[ "${_out}" == *"[WARN]"* ]];     then _warned=$(( _warned + 1 ))
    elif [[ "${_out}" == *"[OK]"* ]];       then _ok=$(( _ok + 1 ))
    elif [[ "${_out}" == *"[OUTDATED]"* ]]; then _outdated=$(( _outdated + 1 )); fi
  }
```

Replace it with:

```bash
  _run_cv_check() {
    local _tool="$1" _pinned="$2" _repo="$3" _cmd="$4" _regex="$5" _var="$6"
    local _out _latest
    _out=$(_check_one_version "${_tool}" "${_pinned}" "${_repo}" "${_cmd}" "${_regex}" 2>&1)
    printf '%s\n' "${_out}"
    if [[ "${_out}" == *"[SKIP]"* ]];       then _skipped=$(( _skipped + 1 ))
    elif [[ "${_out}" == *"[WARN]"* ]];     then _warned=$(( _warned + 1 ))
    elif [[ "${_out}" == *"[OK]"* ]];       then _ok=$(( _ok + 1 ))
    elif [[ "${_out}" == *"[OUTDATED]"* ]]; then
      _outdated=$(( _outdated + 1 ))
      if [[ -n ${UPDATE_VERSIONS:-} ]]; then
        _latest=$(printf '%s' "${_out}" | grep -oE 'latest=[^ ]+' | cut -d= -f2)
        _prompt_version_update "${_tool}" "${_var}" "${_pinned}" "${_latest}"
      fi
    fi
  }
```

- [ ] **Step 3: Add `_var` argument to every `_run_cv_check` call**

The current seven calls are:

```bash
  _run_cv_check "go"         "${GO_VER}"         "golang/go"           "go version"           "[0-9]+\.[0-9]+(\.[0-9]+)?"
  _run_cv_check "python3"    "${PYTHON_VER}"      "python/cpython"      "python3 --version"    "[0-9]+\.[0-9]+\.[0-9]+"
  _run_cv_check "ruby"       "${RUBY_VER}"        "ruby/ruby"           "ruby --version"       "[0-9]+\.[0-9]+\.[0-9]+"
  _run_cv_check "zsh"        "${ZSH_VER}"         "zsh-users/zsh"       "zsh --version"        "[0-9]+\.[0-9]+(\.[0-9]+)?"
  _run_cv_check "yq"         "${YQ_VER}"          "mikefarah/yq"        "yq --version"         "[0-9]+\.[0-9]+\.[0-9]+"
  _run_cv_check "shellcheck" "${SHELLCHECK_VER}"  "koalaman/shellcheck" "shellcheck --version" "[0-9]+\.[0-9]+\.[0-9]+"
  _run_cv_check "vagrant"    "${VAGRANT_VER}"     "hashicorp/vagrant"   "vagrant --version"    "[0-9]+\.[0-9]+\.[0-9]+"
```

Replace with:

```bash
  _run_cv_check "go"         "${GO_VER}"         "golang/go"           "go version"           "[0-9]+\.[0-9]+(\.[0-9]+)?" "GO_VER"
  _run_cv_check "python3"    "${PYTHON_VER}"      "python/cpython"      "python3 --version"    "[0-9]+\.[0-9]+\.[0-9]+"    "PYTHON_VER"
  _run_cv_check "ruby"       "${RUBY_VER}"        "ruby/ruby"           "ruby --version"       "[0-9]+\.[0-9]+\.[0-9]+"    "RUBY_VER"
  _run_cv_check "zsh"        "${ZSH_VER}"         "zsh-users/zsh"       "zsh --version"        "[0-9]+\.[0-9]+(\.[0-9]+)?" "ZSH_VER"
  _run_cv_check "yq"         "${YQ_VER}"          "mikefarah/yq"        "yq --version"         "[0-9]+\.[0-9]+\.[0-9]+"    "YQ_VER"
  _run_cv_check "shellcheck" "${SHELLCHECK_VER}"  "koalaman/shellcheck" "shellcheck --version" "[0-9]+\.[0-9]+\.[0-9]+"    "SHELLCHECK_VER"
  _run_cv_check "vagrant"    "${VAGRANT_VER}"     "hashicorp/vagrant"   "vagrant --version"    "[0-9]+\.[0-9]+\.[0-9]+"    "VAGRANT_VER"
```

- [ ] **Step 4: Run all tests**

```bash
make test
```

Expected: all tests pass (no regression in existing check-versions tests)

- [ ] **Step 5: Commit**

```bash
git add lib/workflows.sh
git commit -m "feat: wire --update interactive prompting into run_check_versions"
```

---

## Task 5: Update docs and superpowers index

**Files:**
- Modify: `docs/superpowers/README.md`
- Modify: `README.md`

- [ ] **Step 1: Update superpowers README**

In `docs/superpowers/README.md`, find the interactive-version-update row and update it:

```
| 2026-04-10 | [interactive-version-update](plans/2026-04-10-interactive-version-update.md) | [spec](specs/2026-04-10-interactive-version-update-design.md) | Done |
```

- [ ] **Step 2: Update top-level README.md**

Find the `check-versions` row in the entry points table and update the description to mention `--update`:

```
| `check-versions` | Compare pinned tool versions in `lib/constants.sh` against GitHub latest; `--update` prompts to apply each update in-place |
```

Also add `--update` to the Options section:

```
- `--update` — (check-versions only) interactively prompt to update each outdated pin in `lib/constants.sh`
```

- [ ] **Step 3: Run final test suite**

```bash
make test
```

Expected: all tests pass, exit 0

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/README.md README.md
git commit -m "docs: update README and superpowers index for interactive-version-update"
```
