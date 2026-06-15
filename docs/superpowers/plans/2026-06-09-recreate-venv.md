> **Status: DONE** — merged dotfiles#124, dotfiles#127

# recreate-venv Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `-t recreate-venv [--venv-name <name>]` to `setup_env.sh` that force-deletes and recreates a named pyenv virtualenv (default: `ansible`), running the full pip install when the name is `ansible`.

**Architecture:** New `recreate_python_venv()` in `lib/developer.sh` owns the pyenv logic; `run_recreate_venv()` in `lib/workflows.sh` reads `VENV_NAME` and dispatches; `process_args()` and `usage()` in `lib/helpers.sh` expose the new type and flag; `setup_env.sh` adds one dispatch line. Existing `-t ansible` semantics (idempotent, only recreates when symlink wrong) are unchanged.

**Tech Stack:** bash 5, pyenv, pyenv-virtualenv, BATS

---

## Files

- Modify: `lib/helpers.sh` — `usage()` and `process_args()`
- Modify: `lib/developer.sh` — add `recreate_python_venv()`
- Modify: `lib/workflows.sh` — add `run_recreate_venv()`
- Modify: `setup_env.sh` — add dispatch line for `RECREATE_VENV`
- Modify: `tests/setup_env/unit.bats` — `process_args` + `usage` + `run_recreate_venv` tests
- Modify: `tests/setup_env/install_functions.bats` — `recreate_python_venv` tests

---

### Task 1: Add `recreate-venv` to `usage()` and `process_args()`

**Files:**

- Modify: `lib/helpers.sh`
- Test: `tests/setup_env/unit.bats`

- [ ] **Step 1: Write the failing tests**

Add to `tests/setup_env/unit.bats` after the existing `process_args sets ANSIBLE` test (around line 73):

```bash
@test "process_args sets RECREATE_VENV for -t recreate-venv" {
  run bash -c "
    source '${BATS_TEST_DIRNAME}/../../setup_env.sh'
    process_args -t recreate-venv
    printf '%s' \"\${RECREATE_VENV}\"
  "
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "process_args sets VENV_NAME from --venv-name flag" {
  run bash -c "
    source '${BATS_TEST_DIRNAME}/../../setup_env.sh'
    process_args --venv-name myenv -t recreate-venv
    printf '%s' \"\${VENV_NAME}\"
  "
  [ "$status" -eq 0 ]
  [ "$output" = "myenv" ]
}

@test "process_args leaves VENV_NAME unset when --venv-name absent" {
  run bash -c "
    source '${BATS_TEST_DIRNAME}/../../setup_env.sh'
    process_args -t recreate-venv
    printf '%s' \"\${VENV_NAME:-unset}\"
  "
  [ "$status" -eq 0 ]
  [ "$output" = "unset" ]
}
```

Add to the existing `usage` test block (around line 187):

```bash
  [[ "$output" == *"recreate-venv"* ]]
  [[ "$output" == *"--venv-name"* ]]
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
make test 2>&1 | grep -A2 "recreate-venv\|venv-name\|RECREATE_VENV"
```

Expected: tests fail — `RECREATE_VENV` unset, `VENV_NAME` unset, usage missing entries.

- [ ] **Step 3: Add `recreate-venv` to `usage()`**

In `lib/helpers.sh`, in the `usage()` heredoc after the `ansible` line:

```bash
  ansible    : Just runs the ansible setup using a python virtual environment. Typically used after a python update
  recreate-venv : Force-delete and recreate a pyenv virtualenv
               Flags: --venv-name (default: ansible)
```

Also add `--venv-name` to the Options section after `--claude-only`:

```bash
  --venv-name     : (recreate-venv only) Name of the pyenv virtualenv to recreate (default: ansible)
```

- [ ] **Step 4: Add `--venv-name` to the long-options loop in `process_args()`**

In the `for _arg in "$@"` loop in `process_args()`, after the `--update` case:

```bash
      --venv-name)  ;;  # handled below as value-bearing option
```

The long-options loop in `process_args` strips unknown long opts into `_short_args`. `--venv-name` takes a value — handle it with a lookahead. Replace the loop with this pattern (the loop currently starts around line 501):

```bash
process_args() {
  local _short_args=()
  local _i=0
  local _args=("$@")
  while [[ ${_i} -lt ${#_args[@]} ]]; do
    local _arg="${_args[${_i}]}"
    case "${_arg}" in
      --dry-run)       [[ -n "${DRY_RUN+x}" ]]         || readonly DRY_RUN=1 ;;
      --brew-only)     [[ -n "${UPDATE_BREW+x}" ]]     || readonly UPDATE_BREW=1 ;;
      --pip-only)      [[ -n "${UPDATE_PIP+x}" ]]      || readonly UPDATE_PIP=1 ;;
      --gems-only)     [[ -n "${UPDATE_GEMS+x}" ]]     || readonly UPDATE_GEMS=1 ;;
      --mas-only)      [[ -n "${UPDATE_MAS+x}" ]]      || readonly UPDATE_MAS=1 ;;
      --claude-only)   [[ -n "${UPDATE_CLAUDE+x}" ]]   || readonly UPDATE_CLAUDE=1 ;;
      --pkgs-only)     [[ -n "${UPDATE_PKGS+x}" ]]     || readonly UPDATE_PKGS=1 ;;
      --brew-install)  [[ -n "${SETUP_BREW+x}" ]]      || readonly SETUP_BREW=1 ;;
      --mas-install)   [[ -n "${SETUP_MAS+x}" ]]       || readonly SETUP_MAS=1 ;;
      --update)        [[ -n "${UPDATE_VERSIONS+x}" ]] || readonly UPDATE_VERSIONS=1 ;;
      --venv-name)
        _i=$(( _i + 1 ))
        [[ -n "${VENV_NAME+x}" ]] || readonly VENV_NAME="${_args[${_i}]}"
        ;;
      *) _short_args+=("${_arg}") ;;
    esac
    _i=$(( _i + 1 ))
  done
  set -- "${_short_args[@]}"

  local arg OPTARG
  while getopts ":ht:w" arg; do
    # shellcheck disable=SC2317 # exit after usage() is intentional redundancy
    case ${arg} in
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
          recreate-venv)  readonly RECREATE_VENV=1 ;;
          *) printf "Invalid option for -t\n"; usage; exit 1 ;;
        esac
        ;;
      w) readonly WORK=1 ;;
      h | *) usage; exit 0 ;;
    esac
  done
}
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
make test 2>&1 | grep -E "recreate-venv|venv-name|RECREATE_VENV|ok|not ok" | head -20
```

Expected: the 3 new `process_args` tests and the updated `usage` test all pass.

- [ ] **Step 6: Commit**

```bash
git add lib/helpers.sh tests/setup_env/unit.bats
git commit -m "feat: add recreate-venv type and --venv-name flag to process_args"
```

---

### Task 2: Add `recreate_python_venv()` to `lib/developer.sh`

**Files:**

- Modify: `lib/developer.sh`
- Test: `tests/setup_env/install_functions.bats`

- [ ] **Step 1: Write the failing tests**

Add to `tests/setup_env/install_functions.bats`:

```bash
# ── recreate_python_venv ──────────────────────────────────────────────────────

@test "recreate_python_venv ansible: calls pyenv virtualenv-delete, create, activate, pip install" {
  export MACOS=1
  unset LINUX
  export HAS_DEVTOOLS=1
  # Point MOCK_PYENV_WHICH_STDOUT to mock python so `pyenv which python` returns
  # the mock binary — this intercepts the `"${_python}" -m pip install` call.
  export MOCK_PYENV_WHICH_STDOUT="${BATS_TEST_DIRNAME}/../mocks/python"
  export PATH="${BATS_TEST_DIRNAME}/../mocks:${PATH}"
  recreate_python_venv "ansible"
  grep -q "virtualenv-delete -f ansible" "${MOCK_CALLS_FILE}"
  grep -q "virtualenv.*ansible" "${MOCK_CALLS_FILE}"
  grep -q "activate ansible" "${MOCK_CALLS_FILE}"
  grep -q "pip install" "${MOCK_CALLS_FILE}"
}

@test "recreate_python_venv myenv: calls delete, create, activate — no pip install" {
  export MACOS=1
  unset LINUX
  export HAS_DEVTOOLS=1
  export MOCK_PYENV_WHICH_STDOUT="${BATS_TEST_DIRNAME}/../mocks/python"
  export PATH="${BATS_TEST_DIRNAME}/../mocks:${PATH}"
  recreate_python_venv "myenv"
  grep -q "virtualenv-delete -f myenv" "${MOCK_CALLS_FILE}"
  grep -q "virtualenv.*myenv" "${MOCK_CALLS_FILE}"
  grep -q "activate myenv" "${MOCK_CALLS_FILE}"
  run grep "pip install" "${MOCK_CALLS_FILE}"
  [ "$status" -ne 0 ]
}

@test "recreate_python_venv returns 1 when pyenv not found" {
  export MACOS=1
  unset LINUX
  export HAS_DEVTOOLS=1
  # Strip mocks dir so pyenv is not findable
  local _saved_path="$PATH"
  export PATH="/usr/bin:/bin"
  local _rc=0
  recreate_python_venv "ansible" || _rc=$?
  export PATH="${_saved_path}"
  [ "${_rc}" -ne 0 ]
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
make test 2>&1 | grep -A2 "recreate_python_venv"
```

Expected: fail — `recreate_python_venv` not defined.

- [ ] **Step 3: Write `recreate_python_venv()` in `lib/developer.sh`**

Add after `setup_ansible()` (after line 234). Use `pyenv which python` to capture the
python path (same pattern as `run_update`) so tests can inject via `MOCK_PYENV_WHICH_STDOUT`:

```bash
recreate_python_venv() {
  local _venv_name="${1:-ansible}"
  export PYENV_ROOT="$HOME/.pyenv"
  export PYENV_VIRTUALENV_DISABLE_PROMPT=1
  if ! quiet_which pyenv; then
    log_error "pyenv not found — cannot recreate virtualenv"
    return 1
  fi
  export PATH="$PYENV_ROOT/bin:$PATH"
  eval "$(pyenv init -)"

  printf "Deleting virtualenv '%s'\\n" "${_venv_name}"
  pyenv virtualenv-delete -f "${_venv_name}" || return 1

  printf "Creating virtualenv '%s' with Python %s\\n" "${_venv_name}" "${PYTHON_VER}"
  pyenv virtualenv "${PYTHON_VER}" "${_venv_name}" || return 1
  pyenv activate "${_venv_name}" || return 1

  if [[ "${_venv_name}" == "ansible" ]]; then
    local _python
    _python="$(pyenv which python 2>/dev/null || command -v python3)"
    printf "Installing Ansible dependencies...\\n"
    "${_python}" -m pip install ansible ansible-lint certbot certbot-dns-cloudflare checkov boto3 docker gmpy2 jmespath mpmath netaddr pylint psutil bpytop HttpPy j2cli wheel shell-gpt pyright mutmut hypothesis || return 1
  fi
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
make test 2>&1 | grep -E "recreate_python_venv|ok|not ok" | head -20
```

Expected: all 3 `recreate_python_venv` tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/developer.sh tests/setup_env/install_functions.bats
git commit -m "feat: add recreate_python_venv to developer.sh"
```

---

### Task 3: Add `run_recreate_venv()` to `lib/workflows.sh` and dispatch in `setup_env.sh`

**Files:**

- Modify: `lib/workflows.sh`
- Modify: `setup_env.sh`
- Test: `tests/setup_env/unit.bats`

- [ ] **Step 1: Write the failing tests**

Add to `tests/setup_env/unit.bats` after the existing `run_developer_or_ansible is defined` test (around line 358):

```bash
@test "run_recreate_venv is defined after sourcing setup_env" {
  declare -f run_recreate_venv &>/dev/null
  [ "$?" -eq 0 ]
}

@test "run_recreate_venv calls recreate_python_venv with ansible when VENV_NAME unset" {
  recreate_python_venv() { printf "recreate_python_venv %s\n" "$1"; }
  run run_recreate_venv
  [[ "$output" == *"recreate_python_venv ansible"* ]]
}

@test "run_recreate_venv calls recreate_python_venv with VENV_NAME when set" {
  recreate_python_venv() { printf "recreate_python_venv %s\n" "$1"; }
  VENV_NAME="myenv"
  run run_recreate_venv
  [[ "$output" == *"recreate_python_venv myenv"* ]]
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
make test 2>&1 | grep -A2 "run_recreate_venv"
```

Expected: fail — `run_recreate_venv` not defined.

- [ ] **Step 3: Add `run_recreate_venv()` to `lib/workflows.sh`**

Add after `run_developer_or_ansible()` (after line 188):

```bash
run_recreate_venv() {
  local _venv_name="${VENV_NAME:-ansible}"
  recreate_python_venv "${_venv_name}" || return 1
}
```

- [ ] **Step 4: Add dispatch line to `setup_env.sh`**

In `setup_env.sh`, after the `[[ -n ${UPDATE:-} ]]` line (line 83):

```bash
[[ -n ${RECREATE_VENV:-} ]] && _run_or_exit run_recreate_venv
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
make test 2>&1 | grep -E "run_recreate_venv|ok|not ok" | head -20
```

Expected: all 3 `run_recreate_venv` tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/workflows.sh setup_env.sh tests/setup_env/unit.bats
git commit -m "feat: add run_recreate_venv workflow and dispatch in setup_env.sh"
```

---

### Task 4: Update docs index (do this on main after PR merges — not in worktree)

**Files:**

- Modify: `docs/superpowers/README.md`

- [ ] **Step 1: Add row to the All Plans table**

Add to `docs/superpowers/README.md` All Plans table:

```
| 2026-06-09 | [recreate-venv](plans/2026-06-09-recreate-venv.md) | [spec](specs/2026-06-09-recreate-venv-design.md) | Done |
```

- [ ] **Step 2: Add Status: DONE banner to plan file**

At the top of `docs/superpowers/plans/2026-06-09-recreate-venv.md`, add:

```markdown
> **Status: DONE**
```

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/README.md docs/superpowers/plans/2026-06-09-recreate-venv.md
git commit -m "docs: mark recreate-venv plan done"
```
