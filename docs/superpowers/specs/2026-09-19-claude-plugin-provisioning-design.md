# Claude plugin provisioning reads settings.json and registers marketplaces

**Status:** Approved design 2026-09-19, pending spec review
**Closes backlog rows:** "`setup_claude_plugins` installs `plugin@marketplace` refs with no
`marketplace add` anywhere" (#84) and "`setup_claude_plugins`'s membership test is an
unanchored substring match" (#101). Leaves "Claude plugin marketplaces are a dependency
surface no gate can see" (#102) open.

## Problem, as measured

The #84 row says no marketplace registration exists anywhere. That is half right.
dotfiles never runs `claude plugins marketplace add`, but all 7 marketplaces **are**
declared in `extraKnownMarketplaces` in ai-config's `.claude/settings.json`. That file is
symlinked to `~/.claude/settings.json` by `setup_dotfile_symlinks`
(`readlink -f ~/.claude/settings.json` → `ai-config/.claude/settings.json`).

The declaration does not help a non-interactive install. Measured 2026-09-19 on `claude`
(Claude Code 2.1.278), in a fresh `HOME` holding only a copy of that `settings.json`, run
under `env -i`:

| command                                                                           | rc  | output                                                                                                                                                                       |
| --------------------------------------------------------------------------------- | --- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `claude plugins marketplace list`                                                 | 0   | `No marketplaces configured`                                                                                                                                                 |
| `claude plugins install -s user superpowers@claude-plugins-official`              | 1   | `Plugin "superpowers" not found in marketplace "claude-plugins-official". Your local copy may be out of date — try claude plugin marketplace update claude-plugins-official` |
| `claude plugins install -s user caveman@caveman`                                  | 1   | same shape                                                                                                                                                                   |
| `claude plugins marketplace update caveman`                                       | 1   | `Marketplace 'caveman' not found`                                                                                                                                            |
| `claude plugins marketplace add https://github.com/juliusbrussee/caveman.git`     | 0   | `Successfully added marketplace: caveman (declared in user settings)`                                                                                                        |
| `claude plugins install -s user caveman@caveman` (after add)                      | 0   | `Successfully installed plugin: caveman@caveman (scope: user)`                                                                                                               |
| `claude plugins marketplace add anthropics/claude-plugins-official` (second time) | 0   | `already on disk — declared in user settings`                                                                                                                                |

So on a fresh box **every** install fails, the official marketplace included, and the
error's own suggested remedy (`marketplace update`) fails too. `marketplace add <source>`
is the working path, and repeating it is harmless. The population here is one fresh
`HOME` on one Linux box and one CLI version; the Macs and other CLI versions were not
measured.

Today `setup_claude_plugins` (`lib/workflows.sh:48`) swallows every failure with
`|| log_warn` and returns 0, so a provision that installed nothing reports success.
Per the #84 row (not re-measured here), four installs failed that way on `claude`'s first
provision and nothing propagated.

### Two write hazards, both measured in the same fresh `HOME`

Both commands can write `settings.json`, and on a real machine that path is ai-config's
**tracked** file:

- **`marketplace add`** of a marketplace already declared left `settings.json`
  byte-identical (`cmp` against the original). Its state went to the per-machine
  `~/.claude/plugins/known_marketplaces.json` (`~/.claude/plugins` is a real directory,
  not a symlink into ai-config). A marketplace not already declared would be written in.
- **`install`** of a plugin whose `enabledPlugins` value is `false`
  (`terraform-skill@antonbabenko`) rewrote that value to `true`. A following
  `claude plugins disable` restored the file byte-identical.

Today's hardcoded list installs 4 plugins that `settings.json` disables
(`frontend-design`, `ansible-good-practices`, `terraform-skill`, `rust-analyzer-lsp`), so a
fresh provision that succeeded would dirty ai-config and re-enable them.

### Three copies of one list, already drifted

- `settings.json` `enabledPlugins`: 15 ids (11 `true`, 4 `false`).
- `setup_claude_plugins`' list: 14 ids.
- `run_update`'s claude-section loop (`lib/workflows.sh`): 14 ids, identical to the setup
  list.

`code-simplifier@claude-plugins-official` is enabled in settings and in neither dotfiles
list. The 7 marketplaces the setup list uses match the 7 declared, exactly.

## Decisions (operator, 2026-09-19)

1. **`settings.json` is the single source of truth** for both marketplaces
   (`extraKnownMarketplaces`) and plugins (`enabledPlugins`). Both hardcoded lists in
   dotfiles are deleted.
2. **Disabled plugins are skipped.** Only ids whose value is `true` are installed.
3. **Tri-state return:** 0 all present, 2 partial with named failures, 1 hard failure.
4. **`-t update` reconciles, then updates.** A plugin enabled in ai-config on one machine
   reaches the others on their next update, not only on a rerun of `setup_user`.

## Design

### `_claude_plugin_manifest` (new, `lib/workflows.sh`, next to `setup_claude_plugins`)

Reads `${_OVERRIDE_CLAUDE_SETTINGS:-${HOME}/.claude/settings.json}` with `python3` (already
used elsewhere in `lib/workflows.sh`) and prints tab-separated lines:

| line                                  | from                                                                                                                  |
| ------------------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| `marketplace<TAB><name><TAB><source>` | each `extraKnownMarketplaces` entry; `source.source == "github"` gives `<repo>` (`owner/repo`), `"git"` gives `<url>` |
| `unsupported<TAB><name><TAB><type>`   | an entry with any other `source.source`, or a missing `repo`/`url`                                                    |
| `plugin<TAB><id>`                     | each `enabledPlugins` key whose value is exactly `true`                                                               |

Returns 1, printing nothing to stdout, when `python3` is absent or the file is missing,
unreadable, not valid JSON, or not a JSON object. Missing or empty
`extraKnownMarketplaces`/`enabledPlugins` keys are not errors: they produce no lines of
that kind.

Only these two source types exist in today's file (measured: `{'git', 'github'}`).
Mapping others is deferred until one appears; `unsupported` makes that visible rather
than silent.

### `setup_claude_plugins` (rewritten; name and callers unchanged)

1. `claude` not on PATH → `log_warn`, return 0 (unchanged).
2. Read the manifest. rc 1 → return 1.
3. Read registered marketplace names from `claude plugins marketplace list --json`
   (`[].name`) and installed plugins from `claude plugins list --json`, keeping the `id`s
   whose `scope` is `"user"`. Either call failing, or its output not parsing, → return 1.
   Exact id equality replaces today's `grep -qF` substring test (#101).
4. For each `marketplace` line whose name is not registered:
   `claude plugins marketplace add <source>`. A failure is recorded by name.
5. For each `unsupported` line: record a failure naming the marketplace and its type.
6. For each `plugin` line whose id is not installed at user scope:
   `claude plugins install -s user <id>`. A failure is recorded by id. A plugin whose
   marketplace failed to add is still attempted, and its own failure is recorded.
7. Print every recorded failure to stderr. Return 2 if any, else 0.

**Invariant: this function never writes `settings.json`.** It adds only marketplaces
already declared there and installs only plugins already `true`, and both were measured
to leave the file byte-identical. The real-CLI acceptance check below re-proves it on
each run of that check. Unit tests cannot prove it, because the mock writes nothing.

### Callers

- **`run_setup_user`** (`lib/workflows.sh:189`, today `setup_claude_plugins || return 1`):
  capture the rc. 1 → return 1. 2 → `log_warn` naming that plugin provisioning was
  partial, and continue.
- **`run_update`'s claude section:** call `setup_claude_plugins` first. Then run
  `claude plugins update <id>` for each `plugin` line of the manifest, replacing the
  hardcoded 14-item loop. A reconcile rc 2 adds `reconcile` to the section's existing
  named-failure list; a reconcile rc 1 does too, and the update loop is skipped because
  it has no list to iterate. Any entry in that list FAILs the section, which is how an
  update failure is reported today. The post-update skill scan and attestation audit
  that follow are unchanged.

### Tests (bats)

`tests/mocks/claude` gains `--json` handling: `plugins list --json` prints
`MOCK_CLAUDE_PLUGINS_LIST_JSON`, `plugins marketplace list --json` prints
`MOCK_CLAUDE_MARKETPLACE_LIST_JSON`, and `MOCK_CLAUDE_FAIL_ARGS` (a substring of the argv)
makes a matching invocation exit 1. Each defaults to an empty JSON list or to not
failing, and every argv is still recorded to `MOCK_CALLS_FILE`. The existing
`MOCK_CLAUDE_PLUGINS_LIST_OUTPUT` text path stays for any caller that does not pass
`--json`; the 9 tests using it are updated where they exercise `setup_claude_plugins`.

A fixture `settings.json` is supplied through `_OVERRIDE_CLAUDE_SETTINGS`, set in
`setup()` so no test can read the operator's real file.

Cases:

- A declared, unregistered `github` marketplace is added as `owner/repo`, and a `git` one
  as its URL.
- A registered marketplace is not added again.
- An enabled, missing plugin is installed with `-s user`. A disabled one never appears in
  any `install` argv.
- An installed id that is a superstring of an enabled id does not count as installed
  (#101). An id installed only at `project` scope does not count either.
- One marketplace's add failing returns 2, names it on stderr, and the remaining
  marketplaces and plugins are still processed.
- An `unsupported` source returns 2 and names the marketplace and type.
- Missing, unparsable and non-object settings each return 1 with zero `claude` calls.
- `plugins list --json` failing returns 1.
- `claude` absent returns 0.
- Everything present: zero `add` and zero `install` calls, return 0 (idempotency).
- `run_setup_user` continues after a 2 and returns non-zero after a 1.
- `run_update` calls reconcile before any `update`, and runs `update` once per `true` id
  in the fixture, including an id absent from the old hardcoded list.
- A regression test fails if `lib/workflows.sh` again carries a hardcoded
  `@claude-plugins-official` plugin id, since a reintroduced list is exactly the drift
  this removes.

### Real-CLI acceptance (manual, recorded in the PR body)

In a fresh `HOME` holding a copy of the real `settings.json`, run `setup_claude_plugins`
against the real CLI:

1. rc 0; 7 marketplaces registered; the 11 `true` plugins installed; none of the 4
   `false` ones installed; `settings.json` byte-identical to the copy (`cmp`).
2. Run it again: rc 0, zero `add` and zero `install` invocations.
3. Add a bogus marketplace to the copy's `extraKnownMarketplaces`: rc 2, named on stderr,
   the other entries unaffected.

This is the check that proves the write invariant, because the unit tests run against a
mock that writes nothing.

### Docs

- `CLAUDE.md`: the `setup_user` entry-point bullet (plugins come from ai-config's
  `settings.json`), and a Test Seams paragraph for `_OVERRIDE_CLAUDE_SETTINGS`.
- ADR in `docs/adr/`: ai-config's `settings.json` is the plugin source of truth for
  dotfiles provisioning. It is a contract between two repos, so a change to it lands in
  ai-config and takes effect in dotfiles on the next run.
- `docs/superpowers/README.md`: remove the #84 and #101 backlog rows when this ships.

## Out of scope

- **#102.** The plugin list now lives in one tracked JSON file, which makes it reviewable,
  but no gate reads that file.
- **Verifying a plugin actually loads.** This provisions what `settings.json` declares.
  Whether a plugin's MCP server or hooks work is a separate concern (dotfiles#288 covers
  one such failure).
- **Removing plugins no longer in `settings.json`.** Uninstalling is destructive and was
  not asked for.

## Multi-Lens Review

Reviewed at commit: `7fa3c2b8` (Step 7 self-review commit, before Step 8 dispatch)

### Goal-Fit

Finding: Worth building, sized about right. (1) The CLI appears to install enabled
plugins by itself once their marketplace is registered: `code-simplifier` has a user-scope
row dotfiles never installed, and `warp`/`pyright` rows share one millisecond timestamp
across scopes. That is inferred from timestamps, not confirmed. If true, the load-bearing
value is marketplace registration, failure propagation and exact-id matching; reconcile in
`-t update` adds little beyond it. (2) Acceptance case 2 names no instrument: against the
real CLI there is no `MOCK_CALLS_FILE`, so "zero add/install" needs an argv-logging `PATH`
shim, and the acceptance should use a symlinked `settings.json`. (3) An empty manifest is
caught only if the positive cases share one fixture; the idempotency case should also
assert the manifest produced at least one `plugin` line. (4) The hardcoded-list regression
test greps only `@claude-plugins-official`; a reintroduced `caveman@caveman` list passes
it. (5) In `run_update`, a reconcile rc 1 caused by `plugins list --json` failing also
skips the update loop, although the manifest parsed. The lens also reported, and reverted,
an accidental project-scope write to `dotfiles/.claude/settings.json` from
`claude plugins disable` run with the repo as cwd; `git status` confirmed clean afterwards.
Assumption: `marketplace add` of an already-declared entry may re-serialise it on another
CLI version or on macOS. Measured 2026-09-19 on `studio` (CLI 2.1.278) through a symlinked
copy: content byte-identical after `add` and after `install` of a `true` plugin. Holds on
both platforms at this version.
Disposition:

### Ergonomics

Finding: (1) Section order defeats decision 4. The claude section runs at
`lib/workflows.sh:383-449`, before `setup_ai_config` at `:700-703`, which runs only under
`_run_all`. A full `-t update` reconciles against the settings.json from before this run's
pull, so a newly enabled plugin arrives on the second update. `--claude-only` never pulls
ai-config at all. (2) Reconcile rc 2 FAILs the whole update, while `git-repos`,
`git-hooks`, `legacy-rsync` and `cargo-tools` map rc 2 to WARN. One unreachable
marketplace or `unsupported` source would keep every routine update red on every machine.
(3) The invariant is false as worded: `marketplace add` and `install` replace the target
file (new inode) with identical content, which `cmp` cannot see. Reword to "never changes
its content", and run the acceptance against a symlinked `settings.json`, checking the
link survives. (4) The update loop now covers only `true` ids, so the 4 installed but
disabled plugins stop receiving updates.
Assumption: that on macOS the CLI writes through the symlink rather than replacing it.
Measured 2026-09-19 on `studio`: after `marketplace add`, `stat -f %HT` still reports
`Symbolic Link` (target inode changed, content identical). Holds.
Disposition:

### Risk

Finding: (1) The write invariant is proven once, manually, and never enforced at run time.
A plugin disabled between the manifest read and a later install (interactive toggle, peer
session, ai-config pull) is flipped back to `true` in the tracked file, and a future CLI
version that re-serialises on install would dirty ai-config on every provision silently.
Remedy: hash the resolved settings file before and after, and return rc 2 naming the
change if it moved. (2) The spec activates a dormant abort path: `run_setup_user`'s
`setup_claude_plugins || return 1` has never been able to fire; rc 1 would now skip
everything after it in `setup_user`. State that. (3) A valid file yielding zero `plugin`
lines returns rc 0, the silent success the spec exists to remove; zero plugins should be
rc 2. (4) Where reconcile's stderr goes in `run_update` is unstated; unless captured into
`err_claude`, the FAIL detail will not say why. (5) The 4 disabled plugins stop updating.
Premise re-verified with a symlinked settings.json: add and install of a `true` plugin
leave content identical; install of a `false` plugin rewrites it to `true`, link intact.
Assumption: that CLI versions the fleet auto-updates to keep not writing settings.json on
`add` of a declared marketplace or `install` of a `true` plugin. Refutable per version by
the fixture above; the before/after hash in finding (1) would check it on every run.
Disposition:

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.
