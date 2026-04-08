# Granular Update Flags Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `--brew-only`, `--pip-only`, `--gems-only`, `--mas-only`, `--claude-only` long-option flags to `./setup_env.sh -t update` so individual subsystems can be updated without running everything. No-flag behavior unchanged (all subsystems run).

**Architecture:** `process_args()` pre-processes the new long options into `UPDATE_*` readonly vars; a new `_any_update_flag()` helper returns true if any flag is set; `run_update()` guards each subsystem block behind the flag or `_run_all`.

**Tech Stack:** bash, bats

---

## File Map

| Action | File |
|---|---|
| Modify | `lib/helpers.sh` — extend long-option loop in `process_args()`, add `_any_update_flag()`, update `usage()` |
| Modify | `lib/workflows.sh` — refactor `run_update()` |
| Modify | `tests/setup_env/unit.bats` — add flag parsing and dispatch tests |
| Modify | `CLAUDE.md` |
| Modify | `README.md` |

---

### Task 1: Add _any_update_flag() to lib/helpers.sh + tests

**Files:**
- Modify: `lib/helpers.sh`
- Modify: `tests/setup_env/unit.bats`

- [ ] **Step 1: Write failing tests**

Add to `tests/setup_env/unit.bats`:

```bash
# ── _any_update_flag ──────────────────────────────────────────────────────────

@test "_any_update_flag returns 1 when no flags set" {
  unset UPDATE_BREW UPDATE_PIP UPDATE_GEMS UPDATE_MAS UPDATE_CLAUDE
  run _any_update_flag
  [ "$status" -eq 1 ]
}

@test "_any_update_flag returns 0 when UPDATE_BREW is set" {
  export UPDATE_BREW=1
  run _any_update_flag
  [ "$status" -eq 0 ]
}

@test "_any_update_flag returns 0 when UPDATE_PIP is set" {
  export UPDATE_PIP=1
  run _any_update_flag
  [ "$status" -eq 0 ]
}

@test "_any_update_flag returns 0 when multiple flags are set" {
  export UPDATE_PIP=1
  export UPDATE_GEMS=1
  run _any_update_flag
  [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
make test-unit
```

Expected: FAIL — `_any_update_flag: command not found`

- [ ] **Step 3: Add _any_update_flag() to lib/helpers.sh**

In `lib/helpers.sh`, add after the `app_dir_exists()` function and before `check_and_install_nala()`:

```bash
_any_update_flag() {
  [[ -n ${UPDATE_BREW:-}   ]] || [[ -n ${UPDATE_PIP:-}    ]] || \
  [[ -n ${UPDATE_GEMS:-}   ]] || [[ -n ${UPDATE_MAS:-}    ]] || \
  [[ -n ${UPDATE_CLAUDE:-} ]]
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
make test-unit
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/helpers.sh tests/setup_env/unit.bats
git commit -m "feat: add _any_update_flag() helper for granular update flags"
```

---

### Task 2: Extend process_args() to parse new flags + tests

**Files:**
- Modify: `lib/helpers.sh`
- Modify: `tests/setup_env/unit.bats`

- [ ] **Step 1: Write failing tests**

Add to `tests/setup_env/unit.bats`:

```bash
# ── process_args granular update flags ───────────────────────────────────────

@test "process_args sets UPDATE_BREW for --brew-only" {
  process_args -t update --brew-only
  [ "${UPDATE_BREW}" -eq 1 ]
}

@test "process_args sets UPDATE_PIP for --pip-only" {
  process_args -t update --pip-only
  [ "${UPDATE_PIP}" -eq 1 ]
}

@test "process_args sets UPDATE_GEMS for --gems-only" {
  process_args -t update --gems-only
  [ "${UPDATE_GEMS}" -eq 1 ]
}

@test "process_args sets UPDATE_MAS for --mas-only" {
  process_args -t update --mas-only
  [ "${UPDATE_MAS}" -eq 1 ]
}

@test "process_args sets UPDATE_CLAUDE for --claude-only" {
  process_args -t update --claude-only
  [ "${UPDATE_CLAUDE}" -eq 1 ]
}

@test "process_args sets multiple UPDATE flags when multiple flags given" {
  process_args -t update --brew-only --pip-only
  [ "${UPDATE_BREW}" -eq 1 ]
  [ "${UPDATE_PIP}" -eq 1 ]
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
make test-unit
```

Expected: FAIL — `UPDATE_BREW` not set

- [ ] **Step 3: Extend the long-option loop in process_args()**

In `lib/helpers.sh`, replace the `process_args()` long-option for loop:

```bash
  local _short_args=()
  for _arg in "$@"; do
    if [[ "${_arg}" == "--dry-run" ]]; then
      readonly DRY_RUN=1
    else
      _short_args+=("${_arg}")
    fi
  done
```

With:

```bash
  local _short_args=()
  for _arg in "$@"; do
    case "${_arg}" in
      --dry-run)     readonly DRY_RUN=1 ;;
      --brew-only)   readonly UPDATE_BREW=1 ;;
      --pip-only)    readonly UPDATE_PIP=1 ;;
      --gems-only)   readonly UPDATE_GEMS=1 ;;
      --mas-only)    readonly UPDATE_MAS=1 ;;
      --claude-only) readonly UPDATE_CLAUDE=1 ;;
      *) _short_args+=("${_arg}") ;;
    esac
  done
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
make test-unit
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/helpers.sh tests/setup_env/unit.bats
git commit -m "feat: add --brew-only / --pip-only / --gems-only / --mas-only / --claude-only to process_args"
```

---

### Task 3: Refactor run_update() in lib/workflows.sh + dispatch tests

**Files:**
- Modify: `lib/workflows.sh`
- Modify: `tests/setup_env/unit.bats`

- [ ] **Step 1: Write failing tests**

Add to `tests/setup_env/unit.bats`:

```bash
# ── run_update flag dispatch ───────────────────────────────────────────────────

@test "run_update with --brew-only calls brew subsystem and skips gems" {
  load_mocks
  export MOCK_CALLS_FILE="${TMPDIR_TEST}/mock_calls"
  touch "${MOCK_CALLS_FILE}"
  export MACOS=1
  unset LINUX
  export UPDATE_BREW=1
  unset UPDATE_PIP UPDATE_GEMS UPDATE_MAS UPDATE_CLAUDE
  run_update
  grep -q "brew update" "${MOCK_CALLS_FILE}"
  ! grep -q "gem update" "${MOCK_CALLS_FILE}"
}

@test "run_update with no flags calls brew and gem subsystems" {
  load_mocks
  export MOCK_CALLS_FILE="${TMPDIR_TEST}/mock_calls"
  touch "${MOCK_CALLS_FILE}"
  export MACOS=1
  unset LINUX
  unset UPDATE_BREW UPDATE_PIP UPDATE_GEMS UPDATE_MAS UPDATE_CLAUDE
  run_update
  grep -q "brew update" "${MOCK_CALLS_FILE}"
  grep -q "gem update" "${MOCK_CALLS_FILE}"
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
make test-unit
```

Expected: FAIL — `run_update` calls all subsystems even with `UPDATE_BREW=1` (no guard yet)

- [ ] **Step 3: Refactor run_update() in lib/workflows.sh**

Replace the entire `run_update()` function body (lines 1219–1303 in the current file) with:

```bash
run_update() {
  local _run_all=0
  _any_update_flag || _run_all=1

  if [[ ${_run_all} -eq 1 ]] || [[ -n ${UPDATE_BREW:-} ]]; then
    if [[ -n ${MACOS} ]] || [[ -n ${LINUX} ]]; then
      brew_update
      printf "Updating app store apps softwareupdate\\n"
      sudo -H softwareupdate --install --all --verbose
    fi
  fi

  if [[ ${_run_all} -eq 1 ]] || [[ -n ${UPDATE_CLAUDE:-} ]]; then
    if command -v claude &>/dev/null; then
      printf "Updating Claude plugins\\n"
      claude plugins update superpowers && claude plugins update code-simplifier && claude plugins update context7
      printf "Updated Claude plugins\\n"
    fi
  fi

  if [[ ${_run_all} -eq 1 ]] || [[ -n ${UPDATE_MAS:-} ]]; then
    update_system_packages
  fi

  if [[ ${_run_all} -eq 1 ]] || [[ -n ${UPDATE_PIP:-} ]]; then
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

      "$PYTHON" - <<'PY'
import json, subprocess, sys

cmd = [sys.executable, "-m", "pip", "list", "--outdated", "--format=json"]
out = subprocess.check_output(cmd, text=True)
pkgs = [p["name"] for p in json.loads(out)]

if pkgs:
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-U", *pkgs])
PY

      "$PYTHON" -m pip check || true
      printf "Updated pip packages\n"
    fi
  fi

  if [[ ${_run_all} -eq 1 ]]; then
    update_aws_cli
    update_rust
    if [[ -d ${HOME}/.tfenv ]]; then
      printf "Updating tfenv\\n"
      cd ${HOME}/.tfenv || exit
      git pull
      cd ${PERSONAL_GITREPOS}/${DOTFILES} || exit
    fi
    if [[ -d ${HOME}/.oh-my-zsh ]]; then
      printf "Updating oh-my-zsh\\n"
      cd ${HOME}/.oh-my-zsh || exit
      git pull
      cd ${PERSONAL_GITREPOS}/${DOTFILES} || exit
    fi
    if [[ -d ${HOME}/.oh-my-zsh/custom/themes/powerlevel10k ]]; then
      printf "Updating powerlevel10k\\n"
      cd ${HOME}/.oh-my-zsh/custom/themes/powerlevel10k || exit
      git pull
      cd ${PERSONAL_GITREPOS}/${DOTFILES} || exit
    fi
    if [[ -d ${HOME}/.tmux/plugins/tpm ]]; then
      printf "Updating tpm\\n"
      cd ${HOME}/.tmux/plugins/tpm || exit
      git pull
      cd ${PERSONAL_GITREPOS}/${DOTFILES} || exit
    fi
    if [[ -f ${HOME}/bin/cht.sh ]]; then
      printf "Updating cheat.sh\\n"
      curl https://cht.sh/:cht.sh > ~/bin/cht.sh
      chmod 754 ${HOME}/bin/cht.sh
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
  fi

  if [[ ${_run_all} -eq 1 ]] || [[ -n ${UPDATE_GEMS:-} ]]; then
    printf "updating ruby gems\\n"
    gem update
  fi
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
make test-unit
```

Expected: PASS

- [ ] **Step 5: Run full test suite**

```bash
make test
```

Expected: all pass

- [ ] **Step 6: Commit**

```bash
git add lib/workflows.sh tests/setup_env/unit.bats
git commit -m "feat: guard run_update subsystems with UPDATE_* flags"
```

---

### Task 4: Update usage() and docs

**Files:**
- Modify: `lib/helpers.sh`
- Modify: `CLAUDE.md`
- Modify: `README.md`

- [ ] **Step 1: Update usage() in lib/helpers.sh**

Replace the `usage()` body in `lib/helpers.sh`:

```bash
usage() {
  cat << EOF
Usage: $0 -t <type> [--dry-run] [-w]
Types:
  setup_user : Sets up a basic user environment for the current user
  setup      : Runs a full machine and developer setup
  developer  : Runs a developer setup with packages and python virtual environment for running ansible
  ansible    : Just runs the ansible setup using a python virtual environment. Typically used after a python update
  update     : Does a system update of packages including brew packages
               Flags: --brew-only, --pip-only, --gems-only, --mas-only, --claude-only
  doctor     : Prints detected OS, profile, capabilities, and key paths (no side effects)
Options:
  --dry-run     : Log mutating operations (symlinks, installs, mkdir) without executing them
  --brew-only   : (update only) Update Homebrew formulae and casks only
  --pip-only    : (update only) Update pip packages only
  --gems-only   : (update only) Update Ruby gems only
  --mas-only    : (update only) Update Mac App Store apps only
  --claude-only : (update only) Update Claude plugins only
  -w            : Optional -- Specify w for a redhat computer, sets up terraform 0.11 instead of default 0.12
EOF
  exit 0
}
```

- [ ] **Step 2: Update README.md**

In `README.md`, in the Usage table, update the `update` row description and add after the options block:

```markdown
| `update` | Update all packages (brew, apt/dnf/yum, pip, mas, Claude plugins, etc.) |
```

Under `**Options:**`, add:

```markdown
- `--brew-only` — update Homebrew formulae and casks only (with `-t update`)
- `--pip-only` — update pip packages only (with `-t update`)
- `--gems-only` — update Ruby gems only (with `-t update`)
- `--mas-only` — update Mac App Store apps only (with `-t update`)
- `--claude-only` — update Claude plugins only (with `-t update`)

Flags are additive: `./setup_env.sh -t update --brew-only --pip-only` runs only brew and pip.
```

- [ ] **Step 3: Update CLAUDE.md**

In `CLAUDE.md`, in the Entry Points table, update the `update` row:

```markdown
| `update` | Update all packages (brew, apt/dnf/yum, pip, gems, tools). Supports `--brew-only`, `--pip-only`, `--gems-only`, `--mas-only`, `--claude-only` flags |
```

- [ ] **Step 4: Verify lint**

```bash
make lint
```

Expected: all OK

- [ ] **Step 5: Commit**

```bash
git add lib/helpers.sh CLAUDE.md README.md
git commit -m "docs: document granular update flags in usage, CLAUDE.md, README"
```
