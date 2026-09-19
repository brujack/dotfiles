# Claude plugin provisioning reads settings.json and registers marketplaces

**Status:** Approved design 2026-09-19; revised after Multi-Lens Review rounds 1-4
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
2. **Disabled plugins are never installed.** Only ids whose value is `true` are
   installed. Every declared id already installed at user scope is still updated, whether
   `true` or `false` (Multi-Lens Review E4/R5).
3. **Tri-state return:** 0 all present, 2 partial with named failures, 1 hard failure.
   `run_setup_user` warns on 2; `run_update` WARNs on 2, like `git-hooks` and
   `cargo-tools` (E2). rc 1 aborts `setup_user` and FAILs the update section.
4. **`-t update` reconciles, then updates,** against the settings.json this run just
   pulled (E1). A plugin enabled in ai-config on one machine reaches the others on their
   next full update.

## Design

### `_claude_plugin_manifest` (new, `lib/workflows.sh`, next to `setup_claude_plugins`)

Reads `${_OVERRIDE_CLAUDE_SETTINGS:-${HOME}/.claude/settings.json}` with `python3` (already
used elsewhere in `lib/workflows.sh`) and prints tab-separated lines:

| line                                   | from                                                                                                                  |
| -------------------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| `marketplace<TAB><name><TAB><source>`  | each `extraKnownMarketplaces` entry; `source.source == "github"` gives `<repo>` (`owner/repo`), `"git"` gives `<url>` |
| `unsupported<TAB><name><TAB><type>`    | an entry with any other `source.source`, or a missing `repo`/`url`                                                    |
| `plugin<TAB><id><TAB><true or false>`  | each `enabledPlugins` key, with its boolean value; a non-boolean value is emitted as `false`                          |

Returns 1, printing nothing to stdout, when `python3` is absent or the file is missing,
unreadable, not valid JSON, or not a JSON object. Missing or empty
`extraKnownMarketplaces`/`enabledPlugins` keys are not errors here: they produce no lines
of that kind, and `setup_claude_plugins` decides what an empty set means.

Only these two source types exist in today's file (measured: `{'git', 'github'}`).
Mapping others is deferred until one appears; `unsupported` makes that visible rather
than silent.

### `setup_claude_plugins` (rewritten; name and callers unchanged)

1. `claude` not on PATH → `log_warn`, return 0 (unchanged).
2. Read the manifest. rc 1 → return 1.
3. Read registered marketplace names from `claude plugins marketplace list --json`
   (`[].name`) and installed plugins from `claude plugins list --json`, keeping the `id`s
   whose `scope` is `"user"`. Exact id equality replaces today's `grep -qF` substring test
   (#101). If either call fails or its output does not parse, record the failure with the
   CLI's message, skip steps 4-7 (the state they act on is unknown), and return 2. This
   is rc 2, not rc 1, because the list calls can fail for reasons outside settings: in a
   fresh `HOME` the same argv returned `Not logged in · Please run /login` minutes after
   succeeding (Multi-Lens Review round 3, cause unknown), and a box not yet logged in must
   not abort `setup_user`.
4. For each `marketplace` line whose name is not registered:
   `claude plugins marketplace add <source>`. A failure is recorded by name.
5. For each `unsupported` line: record a failure naming the marketplace and its type.
6. If no `plugin` line is `true`, record `no enabled plugins declared in <path>` (R3).
   A valid file that provisions nothing is the silent success this spec removes.
7. For each `true` `plugin` line whose id is not installed at user scope:
   `claude plugins install -s user <id>`. A failure is recorded by id. A plugin whose
   marketplace failed to add is still attempted, and its own failure is recorded.
8. Print every recorded failure to stderr. Return 2 if any, else 0.

**Invariant: this function never changes what `settings.json` means.** It adds only
marketplaces already declared there and installs only plugins already `true`. What the CLI
does to the file, measured on 2.1.278 (Multi-Lens Review round 2, ergonomics):

- `marketplace add` and `install` **rewrite** user `settings.json` every time, replacing
  the target file through the symlink (new inode, link intact, Linux and macOS) and
  serialising it in the CLI's canonical form (2-space indent, known keys reordered).
- The parsed content is unchanged. The bytes are unchanged only when the file was already
  canonical, which ai-config's copy is today.
- `update`, including of a `false` plugin, left the file untouched.

So the invariant holds by meaning and only coincidentally by bytes. The write guard below
reports any change git can see after each run.

### `_claude_settings_git_state` (new, `lib/workflows.sh`): the write guard

The harm the invariant protects against is a dirty ai-config: an unreviewed change in a
tracked file every session on the machine shares. So the guard asks git that question
directly, before and after the span in which the CLI may write (round 3, replacing the
round 2 snapshot/compare design, which kept producing defects of its own):

- Resolve the same path the manifest reads, `${_OVERRIDE_CLAUDE_SETTINGS:-${HOME}/.claude/settings.json}`,
  to its real path with `python3` (`os.path.realpath`), find the enclosing repository, and print
  `git status --porcelain -- <file>` for it, with the git environment stripped
  (`env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE`, `shell.md`).
  Print `untracked` if the file is not in a git repository, and `unknown` if git fails.
- The caller compares the two results:
  - clean before, and anything other than clean after (a status line, `untracked` or
    `unknown`) → WARN
    `<real path> changed during plugin provisioning — review: git -C <repo> diff -- <path in repo>`,
    or, for `untracked`/`unknown` after, `<path> no longer resolves into a tracked file`.
    The second form catches the symlink being replaced by a regular file, which would
    silently detach the machine from ai-config (Multi-Lens Review round 4);
  - already modified before → one info line (`was already modified; not checked`);
  - `untracked` or `unknown` before → one info line naming which.
- It never fails and never aborts. It reports what git sees, so a reformat, a flipped
  value and a concurrent session's edit are all reported the same way, as a dirty file
  with a diff to read. That is the actionable fact in each case. It cannot tell them apart
  and does not try.

git is resolved through `${_CLAUDE_GUARD_GIT:-git}`: the bats suite's `tests/mocks/git`
shadows `git` on `PATH`, so guard tests point this seam at the real binary (`shell.md`,
"A PATH mock shadows the binary your production code needs").

### Callers

- **`run_setup_user`** (`lib/workflows.sh:189`): the line
  `setup_claude_plugins || return 1` has never been able to fire, because the function
  has always returned 0. This spec activates it (R2): a missing or broken settings file or
  an absent `python3` now returns 1, which stops `setup_user` before
  `run_setup_or_developer`, the git-hooks sweep and the ledger entry.
  That is deliberate, since provisioning cannot proceed from a settings file it cannot
  read, but it is a change in behaviour. Only a missing or unparsable settings file or an
  absent `python3` returns 1; a failed list call is rc 2 (step 3). rc 2 → `log_warn`
  naming that plugin provisioning was partial, and continue. The write guard wraps the call
  and only ever warns.
- **`run_update`:**
  - **Order (E1).** The `ai-config` section (`setup_ai_config`, today at
    `lib/workflows.sh:700-703`, gated `_run_all`) moves ahead of the claude section, so a
    full update reconciles against the settings.json it just pulled.
    `--claude-only` does not pull ai-config; it reconciles against the current checkout.
    That is documented in `CLAUDE.md`, not changed.
  - **Claude section.** Record the guard state, then call `setup_claude_plugins` with its
    output tee'd into `err_claude` so the section's detail shows the reason (R4).
    - Reconcile rc 1: the update loop is skipped and the section FAILs, naming the
      reason. (Round 1's G5 rule, "run the loop even after a failed list call", is
      removed: the set it iterates comes from the call that failed, so it could not be
      implemented; round 2, all three lenses.)
    - Otherwise list installed plugins once more with `plugins list --json` (reconcile does
      not return its set) and run `claude plugins update <id>` for every declared id in
      it at user scope. This replaces the hardcoded 14-item loop. If that list fails, the
      loop is skipped and the section FAILs naming it (round 3), rather than updating
      nothing and reporting OK. An update failure FAILs the section, as today.
    - Then check the guard, before `_update_record_end`, and settle the status once:
      - if anything FAILed (reconcile rc 1, the re-list, an update), write every message,
        including the guard's warning and any reconcile rc 2 failures, to
        `fail_result_claude`, then `_update_record_end "claude" 1`. `_update_warn` is never
        called on this path, because it overwrites the status and would downgrade the FAIL
        (round 4);
      - otherwise `_update_record_end "claude" 0`, then, if there is a guard warning or a
        reconcile rc 2, one `_update_warn` whose message joins them with `; ` (E2).
    - The post-update skill scan and attestation audit that follow are unchanged.
  - **Coupling to ai-config's checkout (round 2 R2).** With the pull ahead of it, the
    section reads whatever the pull left. `setup_ai_config` runs
    `pull --rebase --autostash`; a conflict leaves markers in `settings.json`, the
    manifest fails to parse, and the section FAILs naming that, with zero updates. That is
    loud, and preferred to reconciling against a guess. `_UPDATE_SECTION_ORDER` moves
    `ai-config` ahead of `claude` so the summary matches execution order.
  - **`--dry-run`.** Neither `setup_ai_config` nor the claude section checks
    `_dry_run_active` today, and the reconcile does not either: a dry run registers
    marketplaces and installs plugins. That matches `--dry-run`'s documented contract,
    no outbound write, since both are downloads plus local writes.

### Tests (bats)

`tests/mocks/claude` gains `--json` handling: `plugins list --json` prints
`MOCK_CLAUDE_PLUGINS_LIST_JSON`, `plugins marketplace list --json` prints
`MOCK_CLAUDE_MARKETPLACE_LIST_JSON`, and `MOCK_CLAUDE_FAIL_ARGS` (a substring of the argv)
makes a matching invocation exit 1. `MOCK_CLAUDE_EDIT_SETTINGS=<verb>` makes the named
verb (`install` or `update`) append a newline to the file `_OVERRIDE_CLAUDE_SETTINGS`
names, to drive the guard. `MOCK_CLAUDE_FAIL_ON_CALL=<n>` fails only the nth invocation
whose argv is exactly `plugins list --json` (not `plugins marketplace list --json`),
counting in a file under `BATS_TEST_TMPDIR`, so the re-list can fail while reconcile's
list succeeds. Each defaults to an empty JSON list, to not failing or to not editing, and every argv is still
recorded to `MOCK_CALLS_FILE`. The existing `MOCK_CLAUDE_PLUGINS_LIST_OUTPUT` text path
stays for any caller that does not pass `--json`; the 9 tests using it are updated where
they exercise `setup_claude_plugins`.

A fixture `settings.json` is supplied through `_OVERRIDE_CLAUDE_SETTINGS`, set in
`setup()` so no test can read the operator's real file. Every positive case below uses
the same fixture, which declares at least one `github` and one `git` marketplace and both
`true` and `false` plugins.

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
- A valid file with no `true` plugin returns 2, naming it (R3).
- Guard, with the settings fixture committed in a real temporary git repo,
  `_OVERRIDE_CLAUDE_SETTINGS` naming it and `_CLAUDE_GUARD_GIT` pointed at the real git:
  - an edit during `install` produces the `changed during plugin provisioning` warning
    with the `git diff` pointer, and `setup_claude_plugins`' rc is unchanged by it;
  - an edit during `update` in `run_update` is caught too, and the section is WARN;
  - a `run_update` that FAILs and has an edit keeps `status_claude` FAIL and carries the
    guard warning in its result;
  - an already-modified file produces the `was already modified; not checked` line and no
    warning;
  - a fixture outside any repo produces the `untracked` info line;
  - a fixture that is clean before and replaced by an untracked regular file during the
    run produces the `no longer resolves into a tracked file` warning.
- A list-call failure in `setup_claude_plugins` returns 2 with the CLI's message and zero
  `add`/`install` calls.
- In `run_update`, a failing re-list (`MOCK_CLAUDE_FAIL_ON_CALL=2`) makes zero `update`
  calls and FAILs naming it.
- Missing, unparsable and non-object settings each return 1 with zero `claude` calls.
- `claude` absent returns 0.
- Everything present: zero `add` and zero `install` calls, return 0 — and the manifest
  produced at least one `true` `plugin` line, so the case cannot pass on an empty reader
  (G3).
- `run_setup_user` continues after a 2 and returns non-zero after a 1.
- `run_update` pulls ai-config before reading the manifest (E1), reconciles before any
  `update`, runs `update` once per declared id installed at user scope (including a
  `false` one and one absent from the old hardcoded list, asserted as an exact count),
  WARNs on a reconcile rc 2, FAILs on an update failure, and on a reconcile rc 1 makes
  zero `update` calls and FAILs naming the reason.
- A regression test fails if `lib/workflows.sh` again contains a literal
  `<name>@<marketplace>` id for any marketplace declared in the fixture (G4).

### Real-CLI acceptance (manual, recorded in the PR body)

In a fresh `HOME` whose `.claude/settings.json` is a **symlink** to a copy of the real
file (the production shape), with a cwd outside any repository (so no command can fall
back to project scope), and with `claude` wrapped by a `PATH` shim that appends each argv
to a log before exec'ing the real binary (G2):

1. rc 0; 7 marketplaces registered; the 11 `true` plugins installed; none of the 4
   `false` ones installed; the copy's content unchanged (`cmp`), and
   `.claude/settings.json` still a symbolic link.
2. Run it again: rc 0; the shim log shows zero `marketplace add` and zero
   `plugins install` lines for that run.
3. Add a bogus marketplace to the copy's `extraKnownMarketplaces`: rc 2, named on stderr,
   the other entries unaffected.
4. In a second fresh `HOME`, put the settings copy re-indented to 4 spaces inside a
   temporary git repository, commit it, and make `$HOME/.claude/settings.json` a symlink
   to it. Record the guard state, run
   `setup_claude_plugins`, record it again: the guard reports the file modified (the CLI
   re-serialises it on `add`/`install`), and `git diff` shows whitespace only.

Run it on Linux and on macOS. This proves the content invariant against the real CLI;
the settings guard re-checks it on every production run.

### Docs

- `CLAUDE.md`: the `setup_user` and `update` entry-point bullets (plugins come from
  ai-config's `settings.json`; `--claude-only` reconciles against the current checkout),
  and a Test Seams paragraph for `_OVERRIDE_CLAUDE_SETTINGS`.
- ADR in `docs/adr/`: ai-config's `settings.json` is the plugin source of truth for
  dotfiles provisioning. It is a contract between two repos: a change to it lands in
  ai-config and takes effect in dotfiles on the next run, and a broken or `unsupported`
  entry makes every machine's next update WARN until ai-config is fixed.
- `docs/superpowers/README.md`: remove the #84 and #101 backlog rows when this ships, and
  add one: the update ledger entry records dotfiles' `git_sha` but not ai-config's HEAD,
  although plugin provisioning now depends on it (round 2 R2).
- ai-config backlog row: its prettier hook formats `settings.json`, and prettier and the
  CLI disagree on short arrays, so the first such edit makes the file non-canonical and
  every later add or install reformats it. Candidate fixes are `.prettierignore` or a
  canonical-form check (round 2 ergonomics). Out of this spec; the guard makes it visible
  meanwhile.

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
Disposition: Addressed G2 (argv shim, symlinked settings, cwd outside any repo), G3 (shared fixture; idempotency case asserts a `true` plugin line), G4 (regression grep covers every declared marketplace), G5 (update loop runs whenever the manifest parsed). Accepted G1, reason: the CLI self-install is an unconfirmed timestamp inference, and reconcile costs two list calls when nothing is missing.

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
Disposition: Addressed E1 (ai-config pull moved ahead of the claude section; `--claude-only` documented), E2 (reconcile rc 2 WARNs), E3 (invariant reworded to content; acceptance on a symlink with a link check), E4 (every declared installed id is updated).

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
Disposition: Addressed R1 (before/after content hash, step 9), R2 (abort path stated in Callers), R3 (zero `true` plugins is rc 2), R4 (reconcile output tee'd into `err_claude`), R5 (same as E4).

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.

### Round 2

Reviewed at commit: `9a7695e0`. All three lenses re-ran against the revised body.

Goal-Fit: Worth building. The round-1 G5 rule cannot be implemented: the update set comes
from the `plugins list --json` call whose failure triggers the rule, the caller receives
only an rc, and both fallbacks fail (updating every declared id FAILs on the uninstalled
`false` ones, measured `Plugin "terraform-skill" is not installed`; updating none makes
the rule inert), while its test passes on zero calls. Assumption: no declared plugin needs
`-y` (command-source or headersHelper install) under a non-TTY stdout; holds for all 7
catalogs today.
Disposition: Addressed (G5 removed; reconcile rc 1 skips the update loop and FAILs).
Accepted the `-y` assumption, reason: it holds for every current catalog and a violation
fails loudly as rc 2 naming the plugin.

Ergonomics: The byte hash is the wrong instrument. `marketplace add` and `install` rewrite
settings.json into the CLI's canonical form every time; the file was byte-identical only
because ai-config's copy is already canonical (a 4-space copy changed on both, parsed
content equal). ai-config's prettier hook can make it non-canonical on the first short
array, after which every add or install produces a whitespace-only dirty ai-config and a
WARN the byte hash cannot tell from a flipped value. Confirmed live that `update` of a
`false` plugin leaves the file unchanged. Also found the G5 contradiction independently.
Assumption: ai-config's settings.json stays canonical under agent edits through the
prettier hook; true today.
Disposition: Addressed (guard compares parsed content and bytes separately, reports
reformat-only distinctly; ai-config prettier row backlogged).

Risk: (1) G5, as above. (2) Moving the pull earlier couples plugin updates to ai-config's
checkout (a rebase conflict leaves an unparsable manifest); `--dry-run` would now also add
and install; the ledger records no ai-config HEAD; the summary order no longer matches
execution. (3) The hash guarded reconcile but not the update loop, and its tool was
unspecified (`sha256sum` is absent from a bare macOS PATH). Assumption: `update` of a
`false` plugin across a real version bump does not flip it to `true`; measured on the
no-op path only.
Disposition: Addressed (G5 removed; coupling, dry-run and conflict behaviour stated;
`_UPDATE_SECTION_ORDER` reordered; ledger-HEAD row backlogged; guard spans the whole
claude section and uses `python3`). The version-bump assumption is covered by the guard
spanning the update loop, which reports a flip whenever it happens.

### Round 3 (scoped: risk lens on the round 2 revision)

Reviewed at commit: `c2d366f9`.

Risk: Five of eight findings were in the round 2 snapshot/compare guard: a FAIL hid its
report; a snapshot or re-read failure could abort `setup_user`, including on a first
provision before `claude` is installed; acceptance case 4 had nothing to run against;
`other keys changed` was too coarse for `hooks`/`permissions`; a concurrent edit could be
silently reverted and read as unchanged. Outside the guard: the re-list after reconcile
had no failure branch (silent zero updates), and the list calls returned
`Not logged in · Please run /login` in a fresh `HOME` minutes after succeeding, so a box
not yet logged in could abort `setup_user`. Assumption: nothing but the spanned CLI calls
writes settings.json during the span.
Disposition: Addressed. The snapshot/compare guard is replaced by a before/after
`git status` on the tracked file that only warns, which removes the snapshot state, the
compare step, the reread branch and the key classification, and reports concurrent edits
as what they are, a dirty ai-config. The re-list failure FAILs by name; a list-call
failure is rc 2, not rc 1. The concurrency assumption no longer breaks the design: the
guard reports whatever git sees.

### Round 4 (scoped: risk lens on the round 3 revision)

Reviewed at commit: `5bca25d9`.

Risk: No new mechanism defects. Specification gaps: (1) a FAIL could be downgraded to WARN,
because the guard check was unordered against `_update_record_end` and `_update_warn`
overwrites the status; (2) a leftover Callers sentence still said a failed list call
returns 1; (3) a symlink replaced by a regular file produced only an info line, silently
detaching the machine from ai-config; (4) the guard, the mock and the tests could watch
different files, and acceptance case 4 did not state the symlink. Harness details: a test
still encoded the retired rc 1; a leftover `<mode>` in the mock variable; the nth-call mock
needed persisted state and an exact argv; the guard-emits-nothing case needed companions.
Verified: git reports ` M` for same-size rewrites (new inode, and same inode with mtime
restored) under ai-config's default config; the git environment strip is load-bearing
(a leaked `GIT_DIR` reads `??` and silences the guard). Assumption: the CLI rewrites
through the symlink rather than replacing it; now checked on every run by gap (3)'s fix.
Disposition: Addressed, pending operator confirmation. All eight applied as wording and
test changes; no mechanism added. Review stops here: the remaining findings sat in
specification wording and test apparatus, and the last two rounds removed mechanism.
