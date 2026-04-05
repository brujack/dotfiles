# mas Brewfile Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move all `mas install` calls from `setup_env.sh` into the existing Brewfile.* files using `brew bundle`'s native `mas` support.

**Architecture:** Add `mas "Name", id: 12345` entries to `Brewfile` (universal), `Brewfile.gui` (HAS_GUI), and `Brewfile.devtools` (HAS_DEVTOOLS), then delete the ~95-line manual mas block from `setup_env.sh`. No new files, functions, or capabilities needed — `install_macos_casks()` already dispatches all three bundles.

**Tech Stack:** bash, brew bundle (Homebrew), mas (Mac App Store CLI)

---

## Files

| File | Change |
|---|---|
| `Brewfile` | Add 16 universal `mas` entries |
| `Brewfile.gui` | Add 1 `mas` entry (Evernote) |
| `Brewfile.devtools` | Add 10 `mas` entries |
| `setup_env.sh` | Remove lines 160–253 (the entire mas install block) |

---

### Task 1: Add universal mas entries to Brewfile

**Files:**
- Modify: `Brewfile` (append after last `cask` line, currently line 133)

- [ ] **Step 1: Append mas entries to Brewfile**

Add the following block at the end of `Brewfile` (after `cask "zoom"`):

```
mas "Better Rename 9", id: 414209656
mas "Blackmagic Disk Speed Test", id: 425264550
mas "Brother iPrint&Scan", id: 1193539993
mas "Flycut", id: 442160987
mas "iNet Network Scanner", id: 403304796
mas "Mactracker", id: 430255202
mas "Magnet", id: 441258766
mas "Markoff", id: 1084713122
mas "Microsoft Remote Desktop", id: 715768417
mas "Remote Desktop", id: 409907375
mas "Simplenote", id: 692867256
mas "Slack", id: 803453959
mas "Speedtest", id: 1153157709
mas "Sync Folders Pro", id: 522706442
mas "The Unarchiver", id: 425424353
mas "Transmit", id: 403388562
```

- [ ] **Step 2: Verify syntax**

Run:
```bash
brew bundle check --file Brewfile --no-upgrade 2>&1 | head -5
```
Expected: either `The Brewfile's dependencies are satisfied.` or a list of missing apps (not a parse error). A parse error means the `mas` syntax is wrong.

- [ ] **Step 3: Commit**

```bash
git add Brewfile
git commit -m "feat: add universal mas app entries to Brewfile"
```

---

### Task 2: Add Evernote to Brewfile.gui

**Files:**
- Modify: `Brewfile.gui`

Evernote was previously gated by `LAPTOP || STUDIO || RECEPTION || OFFICE || HOMES` — all Mac profiles with `HAS_GUI`.

- [ ] **Step 1: Append mas entry to Brewfile.gui**

Add to the end of `Brewfile.gui`:

```
mas "Evernote", id: 406056744
```

- [ ] **Step 2: Verify syntax**

```bash
brew bundle check --file Brewfile.gui --no-upgrade 2>&1 | head -5
```
Expected: dependency check output (not a parse error).

- [ ] **Step 3: Commit**

```bash
git add Brewfile.gui
git commit -m "feat: add Evernote mas entry to Brewfile.gui"
```

---

### Task 3: Add devtools mas entries to Brewfile.devtools

**Files:**
- Modify: `Brewfile.devtools`

These were previously gated by `LAPTOP || STUDIO` (SQLPro, Valentina Studio) and `RATNA || LAPTOP || STUDIO` (iWork suite, iMovie, Pixelmator Pro, Read CHM, Telegram, Xcode). With RATNA deprecated, all map to `HAS_DEVTOOLS` (personal_laptop + mac_workstation).

- [ ] **Step 1: Append mas entries to Brewfile.devtools**

Add to the end of `Brewfile.devtools`:

```
mas "iMovie", id: 408981434
mas "Keynote", id: 409183694
mas "Numbers", id: 409203825
mas "Pages", id: 409201541
mas "Pixelmator Pro", id: 1289583905
mas "Read CHM", id: 594432954
mas "SQLPro for Postgres", id: 1025345625
mas "Telegram", id: 747648890
mas "Valentina Studio", id: 604825918
mas "Xcode", id: 497799835
```

- [ ] **Step 2: Verify syntax**

```bash
brew bundle check --file Brewfile.devtools --no-upgrade 2>&1 | head -5
```
Expected: dependency check output (not a parse error).

- [ ] **Step 3: Commit**

```bash
git add Brewfile.devtools
git commit -m "feat: add devtools mas entries to Brewfile.devtools"
```

---

### Task 4: Remove mas install block from setup_env.sh

**Files:**
- Modify: `setup_env.sh` (remove lines 160–253)

The block to remove starts at `printf "Installing common apps via mas\\n"` and ends at the closing `fi` of the `RATNA || LAPTOP || STUDIO` block (the last `fi` before `printf "Setting up macOS defaults\\n"`). The `softwareupdate` line immediately before (line 158) stays.

- [ ] **Step 1: Identify exact line range**

```bash
grep -n "Installing common apps via mas\|Setting up macOS defaults" setup_env.sh
```
Expected output (approximate):
```
160:    printf "Installing common apps via mas\\n"
255:    printf "Setting up macOS defaults\\n"
```
The block to delete is from the `printf "Installing common apps via mas"` line through the blank line just before `printf "Setting up macOS defaults"`.

- [ ] **Step 2: Delete the mas block**

Open `setup_env.sh` and delete from `printf "Installing common apps via mas\\n"` through the closing `fi` of the RATNA/LAPTOP/STUDIO block (the `fi` on the line just before `printf "Setting up macOS defaults\\n"`).

After the deletion, the `softwareupdate` line should be directly followed by the blank line and then `printf "Setting up macOS defaults\\n"`:

```bash
    printf "Updating app store apps via softwareupdate\\n"
    sudo -H softwareupdate --install --all --verbose

    printf "Setting up macOS defaults\\n"
```

- [ ] **Step 3: Validate shell syntax**

```bash
bash -n setup_env.sh && zsh -n setup_env.sh
```
Expected: no output (both commands exit 0).

- [ ] **Step 4: Commit**

```bash
git add setup_env.sh
git commit -m "refactor: remove manual mas install block from setup_env.sh"
```

---

### Task 5: Run tests and confirm clean

**Files:**
- None modified

- [ ] **Step 1: Run the full test suite**

```bash
make test
```
Expected: all tests pass, exit 0. If any test fails referencing the removed mas block or `app_dir_exists` calls for mas-installed apps, delete or update that test.

- [ ] **Step 2: If a test references the removed mas block, remove it**

Check:
```bash
grep -rn "mas install\|414209656\|1193539993\|425264550\|442160987\|403304796\|430255202\|441258766\|1084713122\|715768417\|409907375\|692867256\|803453959\|1153157709\|522706442\|425424353\|403388562\|406056744\|1025345625\|604825918\|409183694\|408981434\|409203825\|409201541\|1289583905\|594432954\|747648890\|497799835" tests/
```
Expected: no matches (the mock at `tests/mocks/mas` is fine — it's a general mock, not tied to these IDs). If any test asserts on specific `mas install <id>` calls from the old block, delete those test cases.

- [ ] **Step 3: Re-run tests after any test removals**

```bash
make test
```
Expected: exit 0.

- [ ] **Step 4: Commit if any test files were changed**

```bash
git add tests/
git commit -m "test: remove obsolete mas install block test assertions"
```
(Skip this step if no test files were changed.)
