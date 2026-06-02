# ADR-0009: Powerlevel10k Removal — Starship as Sole Prompt

**Date:** 2026-05-27
**Status:** Accepted

## Context

dotfiles previously supported two shell prompts: Starship (cross-platform, fast, Nerd Font-aware)
and Powerlevel10k (zsh-only, instant-prompt, highly configurable). p10k was supported via
`setup_p10k()` in `lib/macos.sh` and `lib/linux_shared.sh`, plus the `~/.p10k.zsh` config file
tracked in the dotfiles repo.

Problems that drove removal:

- p10k is zsh-only; Starship works on bash and zsh equally, covering all dotfiles machines
- p10k requires a separate config file (`~/.p10k.zsh`) maintained alongside Starship's
  `starship.toml` — two configs doing the same job
- p10k's instant-prompt feature conflicted with dotfiles' xtrace-based bash coverage
  (ADR-0008): the prompt initialization sequence interfered with the `BASH_XTRACEFD` redirect,
  producing spurious output in coverage runs
- Maintenance burden: two prompts to update, both requiring Nerd Font support

Alternatives considered:

- Keep both prompts, gate behind a machine capability flag — adds a config axis to all prompt
  tests and documentation with no end-user benefit for a solo-dev repo
- Keep p10k for zsh-only machines and Starship for others — complicates zshrc conditionals and
  still requires maintaining two prompt configs

## Decision

Remove all p10k code: delete `setup_p10k()` from `lib/macos.sh` and `lib/linux_shared.sh`,
remove `~/.p10k.zsh` from the dotfiles repo, and remove the p10k zshrc conditional block.
Starship becomes the sole prompt for all machines.

`starship.toml` is the single source of truth for prompt customization. Any capability
previously covered by p10k (git status, language version display, directory truncation) is
handled via Starship modules.

## Consequences

- Simpler `zshrc`: one prompt conditional block removed
- `lib/` test surface reduced — `setup_p10k()` branches no longer need coverage
- Machines that had p10k binaries on disk retain them until the next `brew cleanup`, but
  dotfiles no longer installs or configures p10k
- Any future per-machine prompt customization goes through `starship.toml` overrides, not
  a second prompt tool

## Related

- [lib/macos.sh](../../lib/macos.sh)
- [lib/linux_shared.sh](../../lib/linux_shared.sh)
- [starship.toml](../../starship.toml)
- ADR-0008: Use PS4 xtrace for bash coverage measurement
