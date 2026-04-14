# Cursor Config Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sync `~/.cursor/plugins/` and `~/.cursor/skills-cursor/` across machines via dotfiles using a loop-based symlink pattern, mirroring how `~/.claude/` is handled.

**Architecture:** Add `plugins/` and `skills-cursor/` to `dotfiles/.cursor/`, add a `.gitignore` to ignore `plugins/cache/` (auto-managed, not worth tracking), and extend `setup_dotfile_symlinks()` in `lib/helpers.sh` with a loop that symlinks `dotfiles/.cursor/*` → `~/.cursor/*`, skipping `User/` (already handled by the existing CURSOR_USER_DIR block). Migrate existing machine's `~/.cursor/plugins/` and `~/.cursor/skills-cursor/` into dotfiles as a one-time step.

**Tech Stack:** bash, BATS, existing mock infrastructure (`safe_link`, `FAKE_HOME`, `FAKE_DOTFILES_SRC`)

---

## Files

| File                                       | Action | Purpose                                                             |
| ------------------------------------------ | ------ | ------------------------------------------------------------------- |
| `lib/helpers.sh`                           | Modify | Add cursor loop after `.claude/` loop in `setup_dotfile_symlinks()` |
| `tests/setup_env/extracted_functions.bats` | Modify | Add 3 tests + update `_make_fake_dotfiles()`                        |
| `dotfiles/.cursor/.gitignore`              | Create | Ignore `plugins/cache/` in dotfiles repo                            |
| `dotfiles/.cursor/plugins/`                | Create | Move from `~/.cursor/plugins/`                                      |
| `dotfiles/.cursor/skills-cursor/`          | Create | Move from `~/.cursor/skills-cursor/`                                |
| `docs/superpowers/README.md`               | Modify | Add plan entry                                                      |

---

## Task 1: Loop in setup_dotfile_symlinks (TDD)

**Files:**

- Modify: `tests/setup_env/extracted_functions.bats:25-52` (`_make_fake_dotfiles`) and after line 158 (after last cursor test)
- Modify: `lib/helpers.sh:581` (after the `.claude/` loop, before `.ssh/config` line)

- [ ] **Step 1: Write the failing tests**

In `tests/setup_env/extracted_functions.bats`, update `_make_fake_dotfiles()` to add the new dirs. Find the existing helper (lines 25–52) and add these two lines after the existing `mkdir -p "${FAKE_DOTFILES_SRC}/.cursor/User/snippets"` line:

```bash
  mkdir -p "${FAKE_DOTFILES_SRC}/.cursor/plugins"
  mkdir -p "${FAKE_DOTFILES_SRC}/.cursor/skills-cursor"
```

Then add three new tests after the last cursor test (`setup_dotfile_symlinks links Cursor User settings on Linux`, currently ending around line 158):

```bash
@test "setup_dotfile_symlinks creates ~/.cursor/plugins symlink" {
  _make_fake_dotfiles
  export MACOS=1
  unset LINUX
  run setup_dotfile_symlinks
  [ "$status" -eq 0 ]
  [[ -L "${FAKE_HOME}/.cursor/plugins" ]]
  [[ "$(readlink "${FAKE_HOME}/.cursor/plugins")" == "${FAKE_DOTFILES_SRC}/.cursor/plugins" ]]
}

@test "setup_dotfile_symlinks creates ~/.cursor/skills-cursor symlink" {
  _make_fake_dotfiles
  export MACOS=1
  unset LINUX
  run setup_dotfile_symlinks
  [ "$status" -eq 0 ]
  [[ -L "${FAKE_HOME}/.cursor/skills-cursor" ]]
  [[ "$(readlink "${FAKE_HOME}/.cursor/skills-cursor")" == "${FAKE_DOTFILES_SRC}/.cursor/skills-cursor" ]]
}

@test "setup_dotfile_symlinks does not symlink User/ under ~/.cursor" {
  _make_fake_dotfiles
  export MACOS=1
  unset LINUX
  run setup_dotfile_symlinks
  [ "$status" -eq 0 ]
  [[ ! -L "${FAKE_HOME}/.cursor/User" ]]
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
make test 2>&1 | grep "not ok"
```

Expected: 2 failures — `creates ~/.cursor/plugins symlink` and `creates ~/.cursor/skills-cursor symlink`. The `does not symlink User/` test may already pass (no loop exists yet, so nothing creates it), but verify all three behave as expected.

- [ ] **Step 3: Implement the cursor loop in lib/helpers.sh**

Find this line in `lib/helpers.sh` (around line 583):

```bash
  safe_link "${PERSONAL_GITREPOS}/${DOTFILES}/.ssh/config" "${HOME}/.ssh/config"
```

Insert the following immediately before that line:

```bash
  log_info "Creating ${HOME}/.cursor"
  mkdir -p "${HOME}/.cursor"
  for _cursor_item in "${PERSONAL_GITREPOS}/${DOTFILES}/.cursor/"*; do
    # Skip User/ — handled separately via CURSOR_USER_DIR symlinks
    [[ "$(basename ${_cursor_item})" == "User" ]] && continue
    _cursor_target="${HOME}/.cursor/$(basename ${_cursor_item})"
    safe_link "${_cursor_item}" "${_cursor_target}"
  done

```

- [ ] **Step 4: Run tests to verify they pass**

```bash
make test 2>&1 | grep "not ok"
```

Expected: no output (all passing).

- [ ] **Step 5: Commit**

```bash
git add lib/helpers.sh tests/setup_env/extracted_functions.bats
git commit -m "feat: add ~/.cursor loop symlinks in setup_dotfile_symlinks"
```

---

## Task 2: Migrate files and update docs

**Files:**

- Create: `dotfiles/.cursor/.gitignore`
- Create: `dotfiles/.cursor/plugins/` (moved from `~/.cursor/plugins/`)
- Create: `dotfiles/.cursor/skills-cursor/` (moved from `~/.cursor/skills-cursor/`)
- Modify: `docs/superpowers/README.md`

- [ ] **Step 1: Add .gitignore to dotfiles/.cursor/**

Create `dotfiles/.cursor/.gitignore` with this content:

```
# Ignore auto-managed plugin cache — large, machine-specific, regenerated by Cursor
plugins/cache/
```

- [ ] **Step 2: Move plugins/ and skills-cursor/ into dotfiles**

```bash
cp -r ~/.cursor/plugins /Users/bruce/git-repos/personal/dotfiles/.cursor/plugins
cp -r ~/.cursor/skills-cursor /Users/bruce/git-repos/personal/dotfiles/.cursor/skills-cursor
```

- [ ] **Step 3: Verify git status looks right**

```bash
cd /Users/bruce/git-repos/personal/dotfiles
git status
```

Expected: `.cursor/.gitignore` new file, `.cursor/plugins/local/` (empty dir or tracked files), `.cursor/skills-cursor/` with skill files. `plugins/cache/` should NOT appear (gitignored).

If `plugins/cache/` appears, the `.gitignore` isn't working — verify the path in `.cursor/.gitignore` is `plugins/cache/` and that the file is being picked up.

- [ ] **Step 4: Replace real dirs with symlinks on this machine**

```bash
rm -rf ~/.cursor/plugins
rm -rf ~/.cursor/skills-cursor
```

Then run `setup_dotfile_symlinks` to create the symlinks (or create manually):

```bash
ln -s /Users/bruce/git-repos/personal/dotfiles/.cursor/plugins ~/.cursor/plugins
ln -s /Users/bruce/git-repos/personal/dotfiles/.cursor/skills-cursor ~/.cursor/skills-cursor
```

Verify:

```bash
ls -la ~/.cursor/plugins ~/.cursor/skills-cursor
```

Expected: both are symlinks pointing into dotfiles.

- [ ] **Step 5: Update docs/superpowers/README.md**

Add a new row to the All Plans table:

```markdown
| 2026-04-10 | [cursor-sync](plans/2026-04-10-cursor-sync.md) | [spec](specs/2026-04-10-cursor-sync-design.md) | Done |
```

- [ ] **Step 6: Commit**

```bash
git add .cursor/ docs/superpowers/README.md
git commit -m "feat: add cursor plugins and skills-cursor to dotfiles for cross-machine sync"
```
