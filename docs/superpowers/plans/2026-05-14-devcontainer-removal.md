# .devcontainer Removal Implementation Plan

> **Status: DONE**

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove `.devcontainer/` from dotfiles by promoting real dotfiles to the repo root and deleting stale dev container scaffolding.

**Architecture:** Every dotfile is already a tracked symlink at the repo root pointing into `.devcontainer/`, and `lib/helpers.sh` already references the repo-root paths — so no code or test changes are needed. The migration is: remove the 15 repo-root symlinks, `git mv` the real files to replace them, delete the dev container scaffolding, update `.gitignore` and `CLAUDE.md`, then commit in a single PR.

**Tech Stack:** git, bash

---

## File Map

**Repo-root symlinks to remove (git rm):**
`.config`, `.gitconfig_linux`, `.gitconfig_linux_gitlab`, `.gitconfig_mac`, `.gitconfig_mac_gitlab`, `.p10k.zsh`, `.ssh/config`, `.ssh/teleport.cfg`, `.tmux.conf`, `.vimrc`, `.zprofile`, `.zshrc`, `bruce.omp.json`, `profile.ps1`, `starship.toml`

**Real files to move (git mv, preserving history):**
All files under `.devcontainer/` → repo root (see Task 2 for exact commands)

**Dev container scaffolding to delete (git rm):**
`.devcontainer/devcontainer.json`, `.devcontainer/Dockerfile`, `.devcontainer/README.md`, `.devcontainer/Makefile`, `.devcontainer/.hadolint.yaml`

**Text files to update:**

- `.gitignore` — remove `devcontainer.env` entry
- `CLAUDE.md` — update Layout tree and Symlink Strategy section

**No changes to:**

- `lib/helpers.sh` (paths already reference repo root)
- `tests/` (test fixtures use `$PERSONAL_GITREPOS/$DOTFILES/` prefix, not `.devcontainer/`)
- `lib/` any other file
- `.github/workflows/ci.yml`

---

### Task 1: Create feature branch worktree

**Files:** none

- [ ] **Step 1: Pull master and create worktree**

```bash
cd ~/git-repos/personal/dotfiles
git fetch --prune && git pull
git worktree add .worktrees/feature/remove-devcontainer -b feature/remove-devcontainer
```

- [ ] **Step 2: Verify baseline tests pass**

```bash
cd .worktrees/feature/remove-devcontainer
make test 2>&1 | tail -5
```

Expected: all 619 tests pass, exit 0.

---

### Task 2: Remove repo-root symlinks and move real files

**Files:**

- Remove (git rm): 15 repo-root symlinks
- Move (git mv): 15 real files/dirs from `.devcontainer/` to repo root

- [ ] **Step 1: Remove the 15 repo-root symlinks**

```bash
cd /Users/bruce/git-repos/personal/dotfiles/.worktrees/feature/remove-devcontainer
git rm .config \
       .gitconfig_linux \
       .gitconfig_linux_gitlab \
       .gitconfig_mac \
       .gitconfig_mac_gitlab \
       .p10k.zsh \
       .tmux.conf \
       .vimrc \
       .zprofile \
       .zshrc \
       bruce.omp.json \
       profile.ps1 \
       starship.toml \
       .ssh/config \
       .ssh/teleport.cfg
```

Expected: 15 files staged as deleted.

- [ ] **Step 2: Move individual dotfiles to repo root**

```bash
git mv .devcontainer/.zshrc .zshrc
git mv .devcontainer/.zprofile .zprofile
git mv .devcontainer/.vimrc .vimrc
git mv .devcontainer/.tmux.conf .tmux.conf
git mv .devcontainer/.p10k.zsh .p10k.zsh
git mv .devcontainer/.gitconfig_mac .gitconfig_mac
git mv .devcontainer/.gitconfig_mac_gitlab .gitconfig_mac_gitlab
git mv .devcontainer/.gitconfig_linux .gitconfig_linux
git mv .devcontainer/.gitconfig_linux_gitlab .gitconfig_linux_gitlab
git mv .devcontainer/bruce.omp.json bruce.omp.json
git mv .devcontainer/profile.ps1 profile.ps1
git mv .devcontainer/starship.toml starship.toml
```

- [ ] **Step 3: Move the .config/ directory**

```bash
git mv .devcontainer/.config .config
```

Expected: all files under `.devcontainer/.config/` (`.zshrc.d/` 7 files + `ccstatusline/settings.json`) now appear under `.config/` in the staging area.

- [ ] **Step 4: Move the .ssh/ files**

```bash
git mv .devcontainer/.ssh/config .ssh/config
git mv .devcontainer/.ssh/teleport.cfg .ssh/teleport.cfg
```

- [ ] **Step 5: Verify staging looks correct**

```bash
git status --short | head -40
```

Expected output shows `R  .devcontainer/.zshrc -> .zshrc` style renames for all 15 dotfiles, no unexpected additions.

---

### Task 3: Delete dev container scaffolding and physical cleanup

**Files:**

- Delete (git rm): 5 dev container files
- Physical cleanup: `rm -rf .devcontainer/`

- [ ] **Step 1: Delete dev container scaffolding**

```bash
git rm .devcontainer/devcontainer.json \
       .devcontainer/Dockerfile \
       .devcontainer/README.md \
       .devcontainer/Makefile \
       .devcontainer/.hadolint.yaml
```

- [ ] **Step 2: Physically remove the now-empty .devcontainer/ directory**

```bash
rm -rf .devcontainer/
```

This removes the empty directory and any gitignored files (`devcontainer.env`) left behind.

- [ ] **Step 3: Verify .devcontainer/ is gone**

```bash
ls .devcontainer/ 2>/dev/null || echo "gone"
git status --short | grep devcontainer
```

Expected: `gone` and no staged/unstaged `.devcontainer/` entries.

---

### Task 4: Update .gitignore and CLAUDE.md

**Files:**

- Modify: `.gitignore`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Remove devcontainer.env from .gitignore**

In `.gitignore`, remove line 5:

```
devcontainer.env
```

The file should no longer contain `devcontainer.env` after this edit.

- [ ] **Step 2: Update CLAUDE.md Layout tree**

In `CLAUDE.md`, replace the `.devcontainer/` block (lines 56–71):

```
├── .devcontainer/            # Central dotfiles storage + dev container config
│   ├── .zshrc                # Main zsh config (sources .zshrc.d modules)
│   ├── .zprofile             # Zsh login shell config
│   ├── .vimrc                # Vim config with 50+ plugins
│   ├── .tmux.conf            # Tmux config (Dracula theme, tpm, C-a prefix)
│   ├── .p10k.zsh             # Powerlevel10k prompt config
│   ├── .gitconfig_mac        # Git config for macOS
│   ├── .gitconfig_linux      # Git config for Linux
│   └── .config/.zshrc.d/     # Modular zsh config (7 numbered files)
│       ├── 1_init.zsh        # OS detection, initial setup
│       ├── 2_functions.zsh   # Shell functions
│       ├── 3_oh-my-zsh.zsh   # Oh-My-Zsh config
│       ├── 4_aliases.zsh     # Aliases
│       ├── 5_general.zsh     # General settings
│       ├── 6_path.zsh        # PATH configuration
│       └── 7_final.zsh       # Final setup, completions
```

With:

```
├── .zshrc                    # Main zsh config (sources .zshrc.d modules)
├── .zprofile                 # Zsh login shell config
├── .vimrc                    # Vim config with 50+ plugins
├── .tmux.conf                # Tmux config (Dracula theme, tpm, C-a prefix)
├── .p10k.zsh                 # Powerlevel10k prompt config
├── .gitconfig_mac            # Git config for macOS
├── .gitconfig_mac_gitlab     # Git config for macOS (GitLab)
├── .gitconfig_linux          # Git config for Linux
├── .gitconfig_linux_gitlab   # Git config for Linux (GitLab)
├── .config/
│   ├── .zshrc.d/             # Modular zsh config (7 numbered files)
│   │   ├── 1_init.zsh        # OS detection, initial setup
│   │   ├── 2_functions.zsh   # Shell functions
│   │   ├── 3_oh-my-zsh.zsh   # Oh-My-Zsh config
│   │   ├── 4_aliases.zsh     # Aliases
│   │   ├── 5_general.zsh     # General settings
│   │   ├── 6_path.zsh        # PATH configuration
│   │   └── 7_final.zsh       # Final setup, completions
│   └── ccstatusline/         # Claude Code status line config
├── bruce.omp.json            # Oh My Posh prompt theme
├── profile.ps1               # PowerShell profile
├── starship.toml             # Starship prompt config
```

- [ ] **Step 3: Update CLAUDE.md Symlink Strategy section**

In `CLAUDE.md`, replace lines 114 and 116:

Old line 114:

```
Dotfiles live in `.devcontainer/` (this repo) and `.claude/`/`.cursor/` (ai-config repo at `~/git-repos/personal/ai-config`). `setup_env.sh` creates symlinks from `$HOME` into the repos:
```

New line 114:

```
Dotfiles live at the repo root and in the ai-config repo (`.claude/`/`.cursor/`). `setup_env.sh` creates symlinks from `$HOME` into the repos:
```

Old line 116:

```
- **`.devcontainer/`** — each file symlinked individually into `$HOME` (e.g. `~/.zshrc → …/.devcontainer/.zshrc`)
```

New line 116:

```
- **Repo root** — each dotfile symlinked individually into `$HOME` (e.g. `~/.zshrc → dotfiles/.zshrc`)
```

---

### Task 5: Verify, commit, push PR, merge, clean up

**Files:** none new

- [ ] **Step 1: Run full test suite**

```bash
cd /Users/bruce/git-repos/personal/dotfiles/.worktrees/feature/remove-devcontainer
make test 2>&1 | tail -5
```

Expected: 619 tests pass, exit 0. If any fail, investigate before proceeding.

- [ ] **Step 2: Verify live symlinks still resolve**

```bash
ls -la ~/.zshrc ~/.vimrc ~/.tmux.conf ~/.p10k.zsh
```

Expected: each symlink still resolves — they now point to the repo-root real files rather than through the repo-root-symlink-to-devcontainer chain. The chain shortens from `~/.zshrc → dotfiles/.zshrc → dotfiles/.devcontainer/.zshrc` to `~/.zshrc → dotfiles/.zshrc` (real file).

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "chore: remove .devcontainer/ — promote dotfiles to repo root"
```

- [ ] **Step 4: Push and open PR**

```bash
git push -u origin feature/remove-devcontainer
gh pr create --title "chore: remove .devcontainer/ — promote dotfiles to repo root" \
  --body "$(cat <<'EOF'
## Summary
- Promote all dotfiles from .devcontainer/ to repo root (git mv, history preserved)
- Delete stale dev container scaffolding (devcontainer.json, Dockerfile, README, Makefile, .hadolint.yaml)
- Remove devcontainer.env from .gitignore
- Update CLAUDE.md Layout tree and Symlink Strategy section
- No changes to lib/helpers.sh or tests — paths were already repo-root

## Test plan
- [x] 619 BATS tests pass
- [x] Live symlinks verified resolving correctly
EOF
)"
```

- [ ] **Step 5: Monitor CI**

```bash
gh pr checks --watch --repo brujack/dotfiles
```

Wait for all checks to pass and PR to auto-merge.

- [ ] **Step 6: Post-merge cleanup**

```bash
cd ~/git-repos/personal/dotfiles
git fetch --prune && git pull
git worktree remove .worktrees/feature/remove-devcontainer
git worktree prune
git branch -D feature/remove-devcontainer
git push origin --delete feature/remove-devcontainer
```
