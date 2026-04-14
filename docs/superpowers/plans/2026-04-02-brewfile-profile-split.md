# Brewfile Profile Split Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace ~50 manual `if ! app_dir_exists ...; then brew_install_cask` blocks in `setup_env.sh` with three `brew bundle`-managed Brewfiles split by `HAS_*` capability, eliminating brittle app-path checks and old hostname-var profile gates.

**Architecture:** A new `install_macos_casks()` function in `lib/macos.sh` runs `brew bundle` against the main `Brewfile` (universal), `Brewfile.gui` (HAS_GUI), and `Brewfile.devtools` (HAS_DEVTOOLS). `brew bundle` tracks installation state itself — no `app_dir_exists` checks needed. The existing if/then blocks in `setup_env.sh` lines 155–370 are deleted and replaced with a single `install_macos_casks` call.

**Tech Stack:** Bash, BATS, `tests/mocks/` PATH-injection pattern, `brew bundle`

---

## Files

| File                                  | Action                                                                   |
| ------------------------------------- | ------------------------------------------------------------------------ |
| `lib/macos.sh`                        | Modify — add `install_macos_casks()` function                            |
| `setup_env.sh`                        | Modify — replace lines 137–139 + 155–370 with `install_macos_casks` call |
| `Brewfile`                            | Modify — append 25 universal casks                                       |
| `Brewfile.gui`                        | Create — 10 GUI casks                                                    |
| `Brewfile.devtools`                   | Create — 16 devtools casks                                               |
| `tests/setup_env/install_guards.bats` | Modify — add `install_macos_casks` tests                                 |

---

## Task 1: Write failing tests for `install_macos_casks`

**Files:**

- Modify: `tests/setup_env/install_guards.bats`

- [ ] **Step 1: Append the failing tests to `tests/setup_env/install_guards.bats`**

Add at the end of the file:

```bash
# ── install_macos_casks ───────────────────────────────────────────────────────

@test "install_macos_casks calls brew bundle with main Brewfile" {
  export BREWFILE_LOC="${BATS_TEST_TMPDIR}/brew"
  export PERSONAL_GITREPOS="${BATS_TEST_TMPDIR}/repos"
  export DOTFILES="dotfiles"
  unset HAS_GUI HAS_DEVTOOLS
  run install_macos_casks
  grep -q "brew bundle" "${MOCK_CALLS_FILE}"
}

@test "install_macos_casks calls brew bundle with Brewfile.gui when HAS_GUI is set" {
  export BREWFILE_LOC="${BATS_TEST_TMPDIR}/brew"
  export PERSONAL_GITREPOS="${BATS_TEST_TMPDIR}/repos"
  export DOTFILES="dotfiles"
  export HAS_GUI=1
  unset HAS_DEVTOOLS
  run install_macos_casks
  grep -q "Brewfile\.gui" "${MOCK_CALLS_FILE}"
}

@test "install_macos_casks does not call brew bundle with Brewfile.gui when HAS_GUI is unset" {
  export BREWFILE_LOC="${BATS_TEST_TMPDIR}/brew"
  export PERSONAL_GITREPOS="${BATS_TEST_TMPDIR}/repos"
  export DOTFILES="dotfiles"
  unset HAS_GUI HAS_DEVTOOLS
  run install_macos_casks
  grep -q "brew bundle" "${MOCK_CALLS_FILE}"
  ! grep -q "Brewfile\.gui" "${MOCK_CALLS_FILE}"
}

@test "install_macos_casks calls brew bundle with Brewfile.devtools when HAS_DEVTOOLS is set" {
  export BREWFILE_LOC="${BATS_TEST_TMPDIR}/brew"
  export PERSONAL_GITREPOS="${BATS_TEST_TMPDIR}/repos"
  export DOTFILES="dotfiles"
  unset HAS_GUI
  export HAS_DEVTOOLS=1
  run install_macos_casks
  grep -q "Brewfile\.devtools" "${MOCK_CALLS_FILE}"
}

@test "install_macos_casks does not call brew bundle with Brewfile.devtools when HAS_DEVTOOLS is unset" {
  export BREWFILE_LOC="${BATS_TEST_TMPDIR}/brew"
  export PERSONAL_GITREPOS="${BATS_TEST_TMPDIR}/repos"
  export DOTFILES="dotfiles"
  unset HAS_GUI HAS_DEVTOOLS
  run install_macos_casks
  grep -q "brew bundle" "${MOCK_CALLS_FILE}"
  ! grep -q "Brewfile\.devtools" "${MOCK_CALLS_FILE}"
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
make test-unit 2>&1 | grep -E "^(not ok|ok)" | grep "install_macos_casks"
```

Expected: all 5 new tests show `not ok` — `install_macos_casks: command not found`.

---

## Task 2: Add `install_macos_casks` to `lib/macos.sh`

**Files:**

- Modify: `lib/macos.sh`

- [ ] **Step 1: Append the function to `lib/macos.sh`**

Add at the end of `lib/macos.sh`:

```bash
install_macos_casks() {
  brew bundle --file "${BREWFILE_LOC}/Brewfile"
  [[ -n ${HAS_GUI} ]]      && brew bundle --file "${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile.gui"
  [[ -n ${HAS_DEVTOOLS} ]] && brew bundle --file "${PERSONAL_GITREPOS}/${DOTFILES}/Brewfile.devtools"
}
```

- [ ] **Step 2: Validate syntax**

```bash
bash -n lib/macos.sh && printf "bash  OK\n"
zsh  -n lib/macos.sh && printf "zsh   OK\n"
```

Expected: both print OK.

- [ ] **Step 3: Run the tests to confirm the 5 new tests pass**

```bash
make test-unit 2>&1 | grep -E "^(not ok|ok)" | grep "install_macos_casks"
```

Expected: all 5 tests show `ok`.

- [ ] **Step 4: Run the full test suite to confirm nothing is broken**

```bash
make test 2>&1 | grep "^not ok"
```

Expected: no new failures (only pre-existing test 29 if still present).

- [ ] **Step 5: Commit**

```bash
git add lib/macos.sh tests/setup_env/install_guards.bats
git commit -m "feat: add install_macos_casks() with HAS_* capability-based brew bundle

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 3: Update `setup_env.sh`

**Files:**

- Modify: `setup_env.sh` (lines 137–139 and 155–370)

Current lines 137–139:

```bash
      if ! brew bundle check --file "${BREWFILE_LOC}/Brewfile"; then
        brew bundle --file "${BREWFILE_LOC}/Brewfile"
      fi
```

Current lines 155–157 (start of block to delete):

```bash
      cd ${PERSONAL_GITREPOS}/${DOTFILES} || exit

      # the below casks and mas are not in a brewfile since they will "fail" if already installed
      if ! app_dir_exists "/Applications/1Password.app"; then
```

- [ ] **Step 1: Replace lines 137–139 with the `install_macos_casks` call**

Find:

```bash
      if ! brew bundle check --file "${BREWFILE_LOC}/Brewfile"; then
        brew bundle --file "${BREWFILE_LOC}/Brewfile"
      fi
```

Replace with:

```bash
      install_macos_casks
```

- [ ] **Step 2: Delete lines 155–370 (the cd + all if/then cask blocks)**

Delete from:

```bash
      cd ${PERSONAL_GITREPOS}/${DOTFILES} || exit

      # the below casks and mas are not in a brewfile since they will "fail" if already installed
      if ! app_dir_exists "/Applications/1Password.app"; then
        brew_install_cask 1password
      fi
```

All the way through:

```bash
      if ! app_dir_exists "/Applications/zoom.us.app"; then
        brew_install_cask zoom
      fi
```

The line immediately after (line 372 in the original): `printf "Cleaning Homebrew up...\\n"` must remain.

- [ ] **Step 3: Validate syntax**

```bash
bash -n setup_env.sh && printf "bash  OK\n"
zsh  -n setup_env.sh && printf "zsh   OK\n"
```

Expected: both print OK.

- [ ] **Step 4: Run the full test suite**

```bash
make test 2>&1 | grep "^not ok"
```

Expected: no new failures.

- [ ] **Step 5: Commit**

```bash
git add setup_env.sh
git commit -m "refactor: replace if/then cask blocks with install_macos_casks call

Removes ~50 app_dir_exists guard blocks and replaces them with a single
call to install_macos_casks(), which delegates to brew bundle per
HAS_* capability. brew bundle handles idempotency itself.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 4: Add universal casks to `Brewfile`

**Files:**

- Modify: `Brewfile`

- [ ] **Step 1: Append the universal casks to `Brewfile`**

Add at the end of `Brewfile` (after the last `brew "zsh-completions"` line):

```ruby
cask "1password"
cask "adobe-acrobat-reader"
cask "alfred"
cask "appcleaner"
cask "beyond-compare"
cask "daisydisk"
cask "expressvpn"
cask "firefox"
cask "flycut"
cask "github"
cask "google-chrome"
cask "istat-menus"
cask "iterm2"
cask "macdown"
cask "malwarebytes"
cask "powershell"
cask "slack"
cask "spotify"
cask "teamviewer"
cask "tidal"
cask "visual-studio-code"
cask "vlc"
cask "warp"
cask "zed"
cask "zoom"
```

- [ ] **Step 2: Run the full test suite**

```bash
make test 2>&1 | grep "^not ok"
```

Expected: no new failures.

- [ ] **Step 3: Commit**

```bash
git add Brewfile
git commit -m "feat: add 25 universal macOS casks to Brewfile

These casks install on all macOS machines. Previously guarded with
individual app_dir_exists checks; brew bundle handles idempotency.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 5: Create `Brewfile.gui`

**Files:**

- Create: `Brewfile.gui`

- [ ] **Step 1: Create `Brewfile.gui`**

```ruby
# Brewfile.gui — installed on HAS_GUI machines (all desktop Macs)
cask "adobe-creative-cloud"
cask "balenaetcher"
cask "bambu-studio"
cask "chatgpt"
cask "claude"
cask "discord"
cask "logi-options-plus"
cask "microsoft-office"
cask "obs"
cask "sonos"
```

- [ ] **Step 2: Run the full test suite**

```bash
make test 2>&1 | grep "^not ok"
```

Expected: no new failures.

- [ ] **Step 3: Commit**

```bash
git add Brewfile.gui
git commit -m "feat: add Brewfile.gui for HAS_GUI desktop Mac casks

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 6: Create `Brewfile.devtools`

**Files:**

- Create: `Brewfile.devtools`

- [ ] **Step 1: Create `Brewfile.devtools`**

```ruby
# Brewfile.devtools — installed on HAS_DEVTOOLS machines
cask "carbon-copy-cloner"
cask "cursor"
cask "dbeaver-community"
cask "docker"
cask "fork"
cask "funter"
cask "google-cloud-sdk"
cask "lens"
cask "mysqlworkbench"
cask "oracle-jdk"
cask "postman"
cask "session-manager-plugin"
cask "sourcetree"
cask "steam"
cask "vagrant"
cask "virtualbox"
```

- [ ] **Step 2: Run the full test suite**

```bash
make test 2>&1 | grep "^not ok"
```

Expected: no new failures.

- [ ] **Step 3: Commit**

```bash
git add Brewfile.devtools
git commit -m "feat: add Brewfile.devtools for HAS_DEVTOOLS machine casks

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 7: Final verification

- [ ] **Step 1: Run the complete test suite**

```bash
make test
```

Expected: exit 0 (or only pre-existing failures).

- [ ] **Step 2: Run lint**

```bash
make lint
```

Expected: `bash OK` and `zsh OK` for all files.

- [ ] **Step 3: Confirm the old if/then block is fully gone**

```bash
grep -c "app_dir_exists" setup_env.sh
```

Expected: `0` — no remaining `app_dir_exists` calls in the cask install section.

- [ ] **Step 4: Confirm Brewfile.gui and Brewfile.devtools exist**

```bash
ls -la Brewfile Brewfile.gui Brewfile.devtools
```

Expected: all three files present.

- [ ] **Step 5: Check git log**

```bash
git log --oneline -6
```

Expected: 5 commits visible for this feature (install_macos_casks function, setup_env.sh refactor, Brewfile, Brewfile.gui, Brewfile.devtools).
