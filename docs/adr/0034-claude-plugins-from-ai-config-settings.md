# ADR-0034: Claude plugin provisioning reads ai-config's `settings.json`

**Date:** 2026-09-19
**Status:** Accepted.

## Context

`setup_claude_plugins` installed a hardcoded `plugin@marketplace` list with no
`claude plugins marketplace add` anywhere in dotfiles (backlog #84), and its membership
test against `claude plugins list` output was an unanchored substring match, so a
superstring id could read as "already installed" (#101). Measured 2026-09-19 on `claude`
(Claude Code 2.1.278), in a fresh `HOME` holding only a copy of the real settings file,
under `env -i`:

- `claude plugins marketplace list --json` reports `No marketplaces configured`, even
  though all 7 marketplaces dotfiles installs from **are** declared in
  `extraKnownMarketplaces` in ai-config's `.claude/settings.json` — the file
  `setup_dotfile_symlinks` symlinks to `~/.claude/settings.json`.
- `claude plugins install -s user <id>` fails for every plugin on a fresh box, the
  official marketplace included: `Plugin "…" not found in marketplace "…"`. The error's
  own suggested remedy, `claude plugin marketplace update <name>`, also fails
  (`Marketplace '<name>' not found`) — only `claude plugins marketplace add <source>`
  works, and repeating it is harmless.
- `marketplace add` alone installs nothing (a fresh `HOME` with all 7 marketplaces added
  still reports 0 installed plugins), so registration and installation are both
  load-bearing steps, not one implying the other.

Four independent copies of "which marketplaces, which plugins" existed and had already
drifted: `settings.json`'s own `enabledPlugins` (15 ids, 11 `true` / 4 `false`),
`setup_claude_plugins`'s hardcoded list (14 ids), `run_update`'s claude-section update
loop (14 ids, identical to the setup list), and a fourth, independent 4-id list added
directly in `_install_ubuntu_brew_packages` (`lib/linux_ubuntu.sh`) for the one path that
runs before `claude-code` itself is installed. `code-simplifier@claude-plugins-official`
was enabled in `settings.json` and absent from the first two lists — the fourth list is
what actually installed it. Because `setup_claude_plugins` swallowed every failure with
`log_warn` and always returned 0, a provision that installed nothing reported success;
the #84 row records four installs failing this way on `claude`'s first real provision
with nothing propagating.

Two further measurements shaped the design rather than only motivating it: `claude
plugins marketplace add`/`install -s user` **rewrite** `settings.json` on every call
(re-serializing it in the CLI's own canonical form) even when the parsed content is
unchanged, so a byte-for-byte no-op cannot be assumed; and some `claude plugins`
subcommands auto-detect scope from the invoking `cwd` rather than always writing user
scope, so a call made with a repository as `cwd` can silently write that repository's
**project**-scope `.claude/settings.json` instead.

## Decision

1. **`settings.json` is the single source of truth**, for both marketplaces
   (`extraKnownMarketplaces`) and plugins (`enabledPlugins`). All three hardcoded lists in
   dotfiles (`setup_claude_plugins`, `run_update`'s claude section,
   `_install_ubuntu_brew_packages`) are deleted; each reaches the manifest reader instead.
2. **Register before installing, and only install what is declared `true`.** Every
   declared marketplace not already registered is added
   (`claude plugins marketplace add <source>`) before any plugin install is attempted. A
   plugin whose declared value is `false` is never installed. Every declared id already
   installed at user scope — `true` or `false` — is still updated by `-t update`, so a
   disabled-but-installed plugin's cache does not go stale.
3. **Membership is exact id equality**, never a substring test (closes #101): both the
   registered-marketplace check and the installed-plugin check compare against
   `claude … --json` output parsed into an id list, not against raw text.
4. **Tri-state return from `setup_claude_plugins`:** `0` everything declared is present,
   `2` partial with every failure named, `1` hard failure (the settings file is missing,
   unreadable, unparsable, not a JSON object, or `python3` cannot be resolved — states
   provisioning cannot proceed from at all). `run_setup_user` aborts only on `1` and warns
   and continues on `2`, so one failed install or one unsupported marketplace source never
   blocks `run_setup_or_developer`, the git-hooks sweep, or the ledger entry that follow it.
5. **`-t update` reconciles against the `settings.json` it just pulled.** The `ai-config`
   update section now runs immediately before the `claude` section, and only on a full run
   (`_run_all`; never `--claude-only`, which reconciles against whatever the current
   checkout already has). A plugin enabled in ai-config on one machine therefore reaches
   every other machine on its own next full update, without a matching dotfiles change.
6. **A write guard reports, it does not prevent.** `_claude_settings_git_state` records
   the settings file's git status (clean/dirty/untracked/unknown) before and after each
   provisioning call; `_claude_settings_guard_check` compares the pair and warns when the
   file changed during the run, naming a `git diff` to review. This is deliberately
   advisory — the CLI's own re-serialization on `add`/`install` is expected, and the guard
   cannot distinguish "the CLI reformatted it", "a value flipped", and "a concurrent
   session edited it"; it reports the same actionable fact (a dirty tracked file) for all
   three rather than trying to tell them apart.

## Consequences

- **A broken or unsupported entry in ai-config's `settings.json` now WARNs every
  machine's next update, not just the one whose hardcoded list happened to include it.**
  The dependency runs ai-config → dotfiles: an unrecognized marketplace source type
  (`unsupported` in the manifest), a marketplace that fails to add, or a plugin that fails
  to install are all recorded and surfaced, and the fix is a single edit to ai-config's
  file rather than a hand-sync across dotfiles.
- **The guard cannot stop a write, only surface one for review.** `settings.json` is a
  tracked file shared by every machine through the symlink `setup_dotfile_symlinks`
  installs; the CLI's own commands can rewrite it on a run that changes nothing
  semantically. A WARN left unread indefinitely means an unreviewed reformat, reorder, or
  value flip sits in ai-config's tracked file until someone reads the diff the guard
  points at.
- **Registering a new marketplace or enabling a new plugin is now a one-file edit in
  ai-config, not a hand-sync across two dotfiles files — except one regression guard.**
  The Task 8 test in `tests/setup_env/claude_plugins.bats` that pins the hardcoded-list
  deletion is a **denylist** of marketplace names known when it was written, deliberately
  not derived from `settings.json` (a derived list would make the test agree with
  whatever the manifest says and could never fail). A genuinely new marketplace therefore
  needs a matching hand edit to that test's alternation, or the guard silently stops
  covering it.
- **Whether a declared plugin actually works is still unverified.** This ADR covers what
  `settings.json` declares and whether the CLI reports it registered/installed — not
  whether its MCP server starts or its hooks fire (backlog #102, left open; dotfiles#288
  covers one such failure independently).
- **Uninstalling a plugin removed from `settings.json` is out of scope, deliberately.**
  Uninstalling is destructive and was not asked for; a plugin disabled or deleted in
  ai-config simply stops being installed or updated going forward.

## Related

- `docs/superpowers/specs/2026-09-19-claude-plugin-provisioning-design.md` — full design,
  measurements, and Multi-Lens Review
- `docs/superpowers/plans/2026-09-19-claude-plugin-provisioning.md` — the implementation
  plan
- `CLAUDE.md` — Entry Points (`setup_user`, `update`), Key Conventions (`-s user`), Test
  Seams (`_OVERRIDE_CLAUDE_SETTINGS`, `_CLAUDE_GUARD_GIT`)
- `docs/superpowers/README.md` — Backlog rows #84 and #101, closed by this change
- `lib/workflows.sh` — `_claude_plugin_manifest`, `setup_claude_plugins`,
  `provision_claude_plugins` header comments
