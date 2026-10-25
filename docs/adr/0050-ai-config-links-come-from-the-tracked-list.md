# ADR-0050: ai-config links come from git's tracked list

**Date:** 2026-10-25
**Status:** Accepted

## Context

`setup_dotfile_symlinks` linked every top-level entry of `ai-config/.claude/` and
`ai-config/.cursor/` into `$HOME` with a shell glob. The glob is default-allow over
whatever the checkout happens to hold, so gitignored runtime state was linked exactly
like tracked configuration and machines diverged by checkout contents. On `workstation`
this moved a real `~/.claude/dod-log` aside and linked an ai-config copy in its place,
which hid older entries from `dod_log.py`'s pre-push check. On `claude` (2026-10-25) five
`.claude` items and `.cursor/plugins` were linked although ai-config tracks none of them.

Alternatives considered:

- **Skip gitignored paths** (`git check-ignore`): still default-allow, so an untracked but
  not-yet-ignored directory is linked.
- **Refuse to link over any real `~/.claude/<name>`**: needs no list, but on a fresh machine
  where Claude Code already created a real `settings.json` or `skills/`, setup would refuse
  to link the harness.
- **Allowlist of tracked items, alone**: tracked is not the same as config.
  `ai-config/.claude/dod-log/.gitkeep` was tracked 2026-06-30 to 2026-07-29, and in that
  window the allowlist would have linked `dod-log` over the real directory again.

## Decision

1. An ai-config `.claude`/`.cursor` item is linked only if `git ls-files` reports at least
   one file at or under it (`_ai_config_tracked_items`, NUL-delimited, with `GIT_DIR`,
   `GIT_WORK_TREE`, `GIT_COMMON_DIR` and `GIT_INDEX_FILE` stripped).
2. `CLAUDE_HOME_STORES` (`lib/constants.sh`) names the items ai-config's own code writes
   through `~/.claude/<name>`; they are never linked, tracked or not. The list is
   maintained by hand.
3. An existing link into ai-config for a name this run does not link gets one WARN with a
   remedy chosen by the name (`cp -a` out of ai-config for a home store holding data,
   `rm <link>` otherwise). Nothing is removed automatically.
4. If the tracked list cannot be read, nothing is linked from that directory and
   `setup_dotfile_symlinks` returns 1. There is no fallback to the glob.

## Consequences

- A fresh machine gets only tracked ai-config configuration; runtime state stays local.
- Adding a new top-level ai-config item takes effect only once it is committed.
- A new script that writes through `~/.claude/<name>` must be added to
  `CLAUDE_HOME_STORES` by hand; nothing detects the omission (Backlog row).
- Existing stale links persist until the operator runs the printed remedy, and the WARN
  repeats on every `setup_user` until then.
- `run_setup_user` stops after the link step if ai-config's index cannot be read. That
  state is close to unreachable, because `setup_ai_config` clones or validates the same
  checkout one step earlier.
- Tests need a real git index: `load_mocks` points `_AI_CONFIG_GIT` at the real git and
  defaults `_OVERRIDE_AI_CONFIG_DIR` to a fixture built by `track_ai_config_fixture`.
- `setup_windows.ps1` still links a hand-written list and does not follow this rule
  (Backlog row).

## Related

- Spec: [`2026-10-25-link-tracked-ai-config-items-design.md`](../superpowers/specs/2026-10-25-link-tracked-ai-config-items-design.md)
- Plan: [`2026-10-25-link-tracked-ai-config-items.md`](../superpowers/plans/2026-10-25-link-tracked-ai-config-items.md)
- PR: dotfiles#374 (`78fc1c65`)
- [ADR-0034](0034-claude-plugins-from-ai-config-settings.md): plugin provisioning reads ai-config's tracked `settings.json`
