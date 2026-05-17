# Knowledge Directory — dotfiles

Reference material for the dotfiles repo. Not instructions, not workflows, not coding conventions — reference documents for understanding the system, domain concepts, and curated research.

## Categories

### Architecture docs (non-ADR)

Descriptions of how the system works that are too detailed or too volatile for CLAUDE.md, but don't rise to the level of an architectural _decision_ record. Examples:

- How the profile model resolves capabilities from hostname
- The update workflow section order and `_update_record_*` lifecycle
- How etch manifests are loaded and applied during setup
- The symlink strategy for `.claude/`, `.cursor/`, and dotfiles

ADRs (`docs/adr/`) record _decisions_. Architecture docs here describe _how things work_.

### Saved web research

Curated findings from the web-research skill (Exa + Firecrawl) that are worth preserving across sessions. Save here instead of re-fetching next time. Examples:

- Homebrew formula/cask API behavior
- Shell compatibility notes discovered during debugging
- Tool-specific quirks found in external docs

Use file names like `research-<topic>.md` to distinguish from architecture docs.

### Other reference material

Reference sheets for tools managed by dotfiles (shell, npm, Brewfile structure) that don't fit the above categories.

## What does not belong here

| Content type                         | Where it lives                                  |
| ------------------------------------ | ----------------------------------------------- |
| Instructions / behavioral directives | `CLAUDE.md`                                     |
| Reusable workflows                   | `~/.claude/skills/` or `.cursor/skills-cursor/` |
| Coding conventions                   | `~/.claude/standards/`                          |
| Plans and specs                      | `docs/superpowers/` or `docs/cursor/`           |
| Architectural decisions              | `docs/adr/`                                     |

## File naming

`<topic>.md` or `research-<topic>.md` — lowercase with hyphens. One topic per file.

## Index

Add a row to this table when you create a file:

| File         | Category | Contents |
| ------------ | -------- | -------- |
| _(none yet)_ | —        | —        |
