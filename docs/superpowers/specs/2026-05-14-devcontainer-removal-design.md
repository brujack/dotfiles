# .devcontainer Removal Design

Remove the `.devcontainer/` directory from dotfiles by promoting the real files to the
repo root and deleting the stale dev-container scaffolding.

## Context

`.devcontainer/` was originally used for VS Code dev container configuration. It was
co-opted as the primary dotfiles storage location, with every user dotfile living inside
it. The dev container scaffolding (devcontainer.json, Dockerfile, etc.) is stale and
unused.

The current on-disk state has already been partially migrated:

- `lib/helpers.sh` already references repo-root paths (`$DOTFILES/.zshrc`, etc.) — no
  code changes needed
- Every dotfile is tracked at the repo root as a **symlink into `.devcontainer/`**
  (e.g. `dotfiles/.zshrc → .devcontainer/.zshrc`)
- The real files live in `.devcontainer/`

The migration replaces the repo-root symlinks with the real files, then deletes
`.devcontainer/`.

## What Changes

### Tracked symlinks to remove (repo root)

All of these currently point into `.devcontainer/` and are replaced by the real files:

```
.config                       → .devcontainer/.config/
.gitconfig_linux              → .devcontainer/.gitconfig_linux
.gitconfig_linux_gitlab       → .devcontainer/.gitconfig_linux_gitlab
.gitconfig_mac                → .devcontainer/.gitconfig_mac
.gitconfig_mac_gitlab         → .devcontainer/.gitconfig_mac_gitlab
.p10k.zsh                     → .devcontainer/.p10k.zsh
.ssh/config                   → .devcontainer/.ssh/config
.ssh/teleport.cfg             → .devcontainer/.ssh/teleport.cfg
.tmux.conf                    → .devcontainer/.tmux.conf
.vimrc                        → .devcontainer/.vimrc
.zprofile                     → .devcontainer/.zprofile
.zshrc                        → .devcontainer/.zshrc
bruce.omp.json                → .devcontainer/bruce.omp.json
profile.ps1                   → .devcontainer/profile.ps1
starship.toml                 → .devcontainer/starship.toml
```

### Real files to move (git mv, preserving history)

Each file moves from `.devcontainer/X` to `X` (repo root or subdirectory):

| From                                    | To                        |
| --------------------------------------- | ------------------------- |
| `.devcontainer/.zshrc`                  | `.zshrc`                  |
| `.devcontainer/.zprofile`               | `.zprofile`               |
| `.devcontainer/.vimrc`                  | `.vimrc`                  |
| `.devcontainer/.tmux.conf`              | `.tmux.conf`              |
| `.devcontainer/.p10k.zsh`               | `.p10k.zsh`               |
| `.devcontainer/.gitconfig_mac`          | `.gitconfig_mac`          |
| `.devcontainer/.gitconfig_mac_gitlab`   | `.gitconfig_mac_gitlab`   |
| `.devcontainer/.gitconfig_linux`        | `.gitconfig_linux`        |
| `.devcontainer/.gitconfig_linux_gitlab` | `.gitconfig_linux_gitlab` |
| `.devcontainer/.config/`                | `.config/`                |
| `.devcontainer/.ssh/config`             | `.ssh/config`             |
| `.devcontainer/.ssh/teleport.cfg`       | `.ssh/teleport.cfg`       |
| `.devcontainer/bruce.omp.json`          | `bruce.omp.json`          |
| `.devcontainer/profile.ps1`             | `profile.ps1`             |
| `.devcontainer/starship.toml`           | `starship.toml`           |

### Dev container scaffolding to delete

These are not symlinked to `$HOME` and serve no purpose:

- `.devcontainer/devcontainer.json`
- `.devcontainer/Dockerfile`
- `.devcontainer/README.md`
- `.devcontainer/Makefile`
- `.devcontainer/.hadolint.yaml`

After all moves and deletions, `.devcontainer/` is empty and removed.

### .gitignore

Remove `devcontainer.env` (line 5) — the AWS credentials file that was gitignored for
the dev container environment. No longer relevant.

### CLAUDE.md

Update two locations:

1. **Layout tree** — remove the `.devcontainer/` entry; add individual entries for the
   dotfiles now at repo root (`.zshrc`, `.vimrc`, `.tmux.conf`, etc.)
2. **Symlink Strategy section** — replace `.devcontainer/` reference with repo root:
   `each file symlinked individually into $HOME (e.g. ~/.zshrc → dotfiles/.zshrc)`

## What Does NOT Change

- `lib/helpers.sh` — already references `$DOTFILES/.zshrc`, `$DOTFILES/.vimrc`, etc.
  No path updates needed.
- Tests — test fixtures use `$PERSONAL_GITREPOS/$DOTFILES/` prefix, not
  `.devcontainer/`. No test changes needed.
- Live symlinks in `$HOME` — `~/.zshrc` → `dotfiles/.zshrc`. After migration,
  `dotfiles/.zshrc` is the real file rather than a symlink, so `~/.zshrc` continues
  to resolve correctly without re-running `setup_env.sh`.

## Migration Order

All changes land in a single commit — no two-step process needed since
`helpers.sh` and tests don't change.

1. `git rm` the 15 repo-root symlinks
2. `git mv` each real file from `.devcontainer/` to repo root (handles `.ssh/` by
   overwriting the now-removed symlinks)
3. `git rm` the 5 dev container scaffolding files
4. `git rm -r .devcontainer/` (now empty)
5. Update `.gitignore` — remove `devcontainer.env`
6. Update `CLAUDE.md`
7. `make test` — verify 619 tests still pass
8. Push PR via feature branch

## Out of Scope

- Changes to `.devcontainer/.config/ccstatusline/` contents
- Changes to any zshrc.d module content
- Changes to any gitconfig content
