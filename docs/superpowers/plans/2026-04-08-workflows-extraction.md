# Workflows Extraction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract the four main workflow blocks from `setup_env.sh` into `lib/workflows.sh` as named functions, making `setup_env.sh` a thin dispatcher with zero behavior change.

**Architecture:** Create `lib/workflows.sh` with four functions (`run_setup_user`, `run_setup_or_developer`, `run_developer_or_ansible`, `run_update`). Each function body is the current `if` block body moved verbatim. `setup_env.sh` sources the new module and calls the functions. Tests assert the functions exist.

**Tech Stack:** Bash, BATS

---

## File Map

| Action | File                        |
| ------ | --------------------------- |
| Create | `lib/workflows.sh`          |
| Modify | `setup_env.sh`              |
| Modify | `tests/setup_env/unit.bats` |

---

### Task 1: Create `lib/workflows.sh` with four workflow function stubs

This task creates the file and verifies it is syntactically valid. The function bodies are filled in Task 2.

**Files:**

- Create: `lib/workflows.sh`
- Modify: `tests/setup_env/unit.bats`

- [ ] **Step 1: Write the failing tests**

Add to the end of `tests/setup_env/unit.bats`:

```bash
# ── workflows ────────────────────────────────────────────────────────────────

@test "run_setup_user is defined after sourcing setup_env" {
  declare -f run_setup_user &>/dev/null
  [ "$?" -eq 0 ]
}

@test "run_setup_or_developer is defined after sourcing setup_env" {
  declare -f run_setup_or_developer &>/dev/null
  [ "$?" -eq 0 ]
}

@test "run_developer_or_ansible is defined after sourcing setup_env" {
  declare -f run_developer_or_ansible &>/dev/null
  [ "$?" -eq 0 ]
}

@test "run_update is defined after sourcing setup_env" {
  declare -f run_update &>/dev/null
  [ "$?" -eq 0 ]
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
make test-unit 2>&1 | grep -A2 "run_setup_user is defined"
```

Expected: FAIL (function not found)

- [ ] **Step 3: Create `lib/workflows.sh` with empty function stubs**

```bash
#!/usr/bin/env bash
# lib/workflows.sh — top-level workflow functions dispatched by setup_env.sh

run_setup_user() {
  :
}

run_setup_or_developer() {
  :
}

run_developer_or_ansible() {
  :
}

run_update() {
  :
}
```

- [ ] **Step 4: Add source line to `setup_env.sh`**

In `setup_env.sh`, after the existing `source` lines (after line 23, before the sourcing guard on line 26), add:

```bash
source "$(dirname "${BASH_SOURCE[0]}")/lib/workflows.sh"
```

The source block at the top of `setup_env.sh` should now read:

```bash
source "$(dirname "${BASH_SOURCE[0]}")/lib/constants.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/helpers.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/detect_env.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/macos.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/linux.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/developer.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/workflows.sh"
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
make test-unit 2>&1 | tail -20
```

Expected: the 4 new tests pass; all others still pass.

- [ ] **Step 6: Lint**

```bash
make lint
```

Expected: exit 0

- [ ] **Step 7: Commit**

```bash
git add lib/workflows.sh setup_env.sh tests/setup_env/unit.bats
git commit -m "feat: add lib/workflows.sh with empty workflow function stubs

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 2: Move workflow bodies into `lib/workflows.sh`

Move each block from `setup_env.sh` into its corresponding function. No code changes inside the blocks — pure mechanical movement.

**Files:**

- Modify: `lib/workflows.sh`
- Modify: `setup_env.sh`

- [ ] **Step 1: Move `run_setup_user` body**

In `setup_env.sh`, lines 36–114 contain the `if [[ ${SETUP} || ${SETUP_USER} ]]; then ... fi` block.

Copy the body (everything between `then` and the closing `fi`) into `run_setup_user()` in `lib/workflows.sh`:

```bash
run_setup_user() {
  # need to make sure that some base packages are installed
  if [[ ${REDHAT} || ${FEDORA} ]]; then
    if ! [ -x "$(command -v dnf)" ]; then
      printf "Installing dnf\\n"
      sudo -H yum update -y
      sudo -H yum install dnf -y
      if ! [ -x "$(command -v dnf)" ]; then
        printf "Failed to install dnf\\n"
        exit 1
      fi
      printf "Installed dnf\\n"
    fi
  fi

  if [[ -n ${MACOS} ]]; then
    printf "Installing Rosetta if necessary\\n"
    install_rosetta
  fi

  if [[ -n ${MACOS} ]] || [[ -n ${FEDORA} ]] || [[ -n ${CENTOS} ]]; then
    install_git
  fi

  mkdir -p ${HOME}/software_downloads

  if [[ ${MACOS} || ${UBUNTU} || ${FEDORA} || ${CENTOS} ]]; then
    install_zsh
  fi

  if [[ -n ${LINUX} ]]; then
    install_bats
  fi

  printf "Creating %s/bin\\n" "${HOME}"
  mkdir -p ${HOME}/bin

  printf "Creating %s\\n" "${PERSONAL_GITREPOS}"
  mkdir -p ${PERSONAL_GITREPOS}

  clone_or_update_dotfiles

  setup_dotfile_symlinks

  setup_zsh_as_default_shell

  printf "Setting up cheat.sh\\n"
  if [[ -d ${HOME}/bin ]]; then
    if [[ -n ${UBUNTU} ]]; then
      sudo -H apt update
      sudo -H apt install curl -y
    fi
    if [[ -n ${CENTOS} ]]; then
      sudo -H dnf update -y
      sudo -H dnf install curl -y
    fi
    if [[ -n ${REDHAT} ]] || [[ -n ${FEDORA} ]]; then
      sudo -H yum update
      sudo -H yum install curl -y
    fi
    curl https://cht.sh/:cht.sh > ~/bin/cht.sh
    chmod 750 ${HOME}/bin/cht.sh
  fi
  if [[ -x $(command -v cht.sh) ]]; then
    printf "cht.sh is installed\\n"
  fi

  printf "Creating %s/.zsh.d\\n" "${HOME}"
  mkdir -p ${HOME}/.zsh.d
  if [[ ! -f ${HOME}/.zsh.d/_cht ]]; then
    curl https://cheat.sh/:zsh > ${HOME}/.zsh.d/_cht
  fi

  printf "Creating %s/go-work\\n" "${HOME}"
  mkdir -p ${HOME}/go-work
  if [[ -d ${HOME}/go-work ]]; then
    printf "Created %s/go-work\\n" "${HOME}"
  fi
}
```

- [ ] **Step 2: Move `run_setup_or_developer` body**

Lines 116–1044 of `setup_env.sh` contain the `if [[ -n ${SETUP} ]] || [[ -n ${DEVELOPER} ]]; then ... fi` block.

Copy the body into `run_setup_or_developer()` in `lib/workflows.sh`. The function body starts with `setup_credential_directories` and ends with the `fi` closing the vim plugins block. This is a mechanical copy — do not modify any code inside.

- [ ] **Step 3: Move `run_developer_or_ansible` body**

Lines 1046–1250 of `setup_env.sh` contain the `if [[ -n ${DEVELOPER} ]] || [[ -n ${ANSIBLE} ]]; then ... fi` block.

Copy the body into `run_developer_or_ansible()` in `lib/workflows.sh`. The function body starts with `printf "Installing json2yaml via npm\\n"` and ends before the `# update is run more often` comment.

- [ ] **Step 4: Move `run_update` body**

Lines 1252–1337 of `setup_env.sh` contain the `if [[ -n ${UPDATE} ]]; then ... fi` block.

Copy the body into `run_update()` in `lib/workflows.sh`. The function body starts with `if [[ -n ${MACOS} ]] || [[ -n ${LINUX} ]]; then` (the `brew_update` block) and ends before `gem update`.

Wait — include `gem update` and the closing `fi`. The function ends with:

```bash
  printf "updating ruby gems\\n"
  gem update
}
```

- [ ] **Step 5: Replace workflow blocks in `setup_env.sh` with dispatch calls**

Remove lines 36–1337 (the four `if` blocks) from `setup_env.sh` and replace with:

```bash
[[ -n ${SETUP_USER:-} ]] || [[ -n ${SETUP:-} ]] && run_setup_user
[[ -n ${SETUP:-} ]] || [[ -n ${DEVELOPER:-} ]] && run_setup_or_developer
[[ -n ${DEVELOPER:-} ]] || [[ -n ${ANSIBLE:-} ]] && run_developer_or_ansible
[[ -n ${UPDATE:-} ]] && run_update
```

The final `setup_env.sh` main body (after the sourcing guard) should be:

```bash
[[ $# -eq 0 ]] && usage
process_args "$@"

detect_env

[[ -n ${SETUP_USER:-} ]] || [[ -n ${SETUP:-} ]] && run_setup_user
[[ -n ${SETUP:-} ]] || [[ -n ${DEVELOPER:-} ]] && run_setup_or_developer
[[ -n ${DEVELOPER:-} ]] || [[ -n ${ANSIBLE:-} ]] && run_developer_or_ansible
[[ -n ${UPDATE:-} ]] && run_update

/usr/bin/env zsh "${HOME}/.zshrc"
exit 0
```

- [ ] **Step 6: Run lint**

```bash
make lint
```

Expected: exit 0. Fix any syntax errors before proceeding.

- [ ] **Step 7: Run tests**

```bash
make test-unit
```

Expected: all tests pass including the 4 new workflow-function tests.

- [ ] **Step 8: Commit**

```bash
git add lib/workflows.sh setup_env.sh
git commit -m "refactor: move workflow blocks from setup_env.sh into lib/workflows.sh

setup_env.sh is now a thin dispatcher. No behavior change.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 3: Update `CLAUDE.md` and `README.md`

- [ ] **Step 1: Update `CLAUDE.md`**

In the Layout section of `CLAUDE.md`, add `lib/workflows.sh` to the `lib/` listing:

```
├── lib/
│   ├── constants.sh          # Version pins, download URLs, directory vars
│   ├── helpers.sh            # Logging, safe_link, install guards, brew helpers
│   ├── detect_env.sh         # OS/version detection + profile/capability resolution
│   ├── macos.sh              # macOS-specific install functions
│   ├── linux.sh              # Linux-specific install functions
│   ├── developer.sh          # Cross-platform dev tooling (Ruby, Python, Ansible, etc.)
│   └── workflows.sh          # Top-level workflow functions dispatched by setup_env.sh
```

- [ ] **Step 2: Run lint and tests one final time**

```bash
make test
```

Expected: exit 0

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: document lib/workflows.sh in CLAUDE.md

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```
