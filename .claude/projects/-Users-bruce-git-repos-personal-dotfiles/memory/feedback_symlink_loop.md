---
name: helpers.sh symlink loop bug fixed
description: The first .claude/* loop must skip projects/ to avoid creating circular symlinks when ~/.claude/projects is later set up via the per-project loop
type: feedback
---

Skip `projects/` in the first `for _claude_item in dotfiles/.claude/*` loop in `setup_dotfile_symlinks()`.

**Why:** The second loop creates per-project symlinks from `~/.claude/projects/` → `dotfiles/.claude/projects/`. If the first loop also symlinks `dotfiles/.claude/projects` → `~/.claude/projects`, those two directories become the same location, and the second loop creates self-referential (circular) symlinks.

**How to apply:** When editing the `.claude` symlinking code in `helpers.sh`, always keep the `projects/` skip guard: `[[ "$(basename ${_claude_item})" == "projects" ]] && continue`
