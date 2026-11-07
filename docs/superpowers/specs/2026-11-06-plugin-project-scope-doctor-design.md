# Doctor WARN for Claude plugins installed only at project scope

**Status: Retired 2026-11-06, before implementation.** The round-2 Goal-fit lens found
the premise false: every project-only record dated from before 2026-09-19, when dotfiles
stopped writing project scope, so nothing current recreates them. The operator chose a
one-time repair over the check. Round-2 dispositions were not recorded, because the spec
was retired instead of revised. See `## Retirement` at the end of this file for the
repair and its measurements, and the Backlog rows in `docs/superpowers/README.md` for
the open follow-ups.

## Problem

`-t update` updates Claude plugins with `claude plugins update -s user`, and only for
ids that `_claude_installed_user_ids` reports (`lib/workflows.sh:1011`). The prune added
in dotfiles#427 (ADR-0055) removes a project or local record only when a user record for
the same id exists. A plugin with no user-scope record at all is therefore never updated
and never pruned, and nothing reports it.

### Measurement (2026-11-06)

Population: `~/.claude/plugins/installed_plugins.json` on four hosts, read with a
read-only Python probe (`scope` set per id). Claim population: the same four hosts.

| Host          | ids | project-only |
| ------------- | --- | ------------ |
| `claude`      | 15  | 0            |
| `studio`      | 16  | 0            |
| `laptop-1`    | 15  | 0            |
| `workstation` | 16  | 5            |

Workstation's five: `ansible-good-practices@claude-ansible-skills`,
`frontend-design@claude-plugins-official`, `rust-analyzer-lsp@claude-plugins-official`,
`skill-creator@claude-plugins-official` (records under `dotfiles` and
`terraform_ansible`), `terraform-skill@antonbabenko`. All other records are under
`terraform_ansible`.

All five are `false` in the user manifest (`~/.claude/settings.json`, which on workstation
resolves into the ai-config checkout). Project settings, read on workstation only:
`terraform_ansible/.claude/settings.json` enables `ansible-good-practices` and
`terraform-skill`; `frontend-design`, `rust-analyzer-lsp` and `skill-creator` are `false`
there and in `dotfiles/.claude/settings.json`. So two of the five are wanted in a project
and stale; three are enabled nowhere and are dead installs.

On `claude`, `studio` and `laptop-1` all five ids have a `user` record. Their `installedAt`
dates (read 2026-11-06) are 2026-09-12 on `claude`, 2026-05-17 to 2026-06-13 on `studio`,
2026-06-13 on `laptop-1`: all before the 2026-09-19 provisioning change.

### Cause

`setup_claude_plugins` installs only ids whose manifest value is `true`
(`lib/workflows.sh:279`). That is a recorded decision, not an oversight: the 2026-09-19
provisioning spec (decision 2, ADR-0034) measured that `claude plugins install` of a
`false` id rewrites it to `true` in the tracked `settings.json`, and that a following
`claude plugins disable` restores the file byte-identical. The three clean hosts' user
records predate that change (dates above), so they are leftovers of the old hardcoded
install list. Workstation's state is what current dotfiles produces on a fresh machine,
so the check stays useful after workstation is repaired.

The remedy the backlog row proposed (`claude plugins install -s user <id>`) is wrong for a
`false` id (it would dirty ai-config and enable the plugin everywhere) and wrong for a dead
install (it would promote a plugin nobody enables into one `-t update` refreshes forever).

### Gates already in the path

- `setup_claude_plugins`: skips `false` ids by design; did not fire.
- The prune: needs a user record; did not fire.
- `-t doctor`: no check reads plugin scope; did not fire.

### Prior decision: a different doctor check was dropped

`specs/2026-11-04-claude-plugin-user-scope-design.md` (dotfiles#427) proposed and dropped a
`-t doctor` check. That check read the repos' `.claude/settings.json` for `enabledPlugins`
entries redundant with the user manifest and FAILed on them. Its objections, and how this
check differs:

- _FAIL fired when the operator enabled a plugin globally, and its remedy was a PR in
  another session's repo._ This check reads installed state; it is a WARN; every remedy
  but one (an id absent from the user manifest) is a local command on the machine that
  runs doctor.
- _Close to decoration: output ephemeral, no copier of `enabledPlugins` exists._ Still
  partly true: doctor output is read by the operator at run time and kept nowhere. The
  hazard is real here (five ids on workstation, measured), and a fresh machine reproduces
  it. The durable channel is the backlog row below.

## Decision

Option C of three: a doctor WARN now (this spec). Two alternatives go to one backlog row as
rivals, because each is its own decision:

- **B:** the reconcile installs `false` ids too, then disables them. Reverses ADR-0034
  decision 2.
- **In-place update:** `-t update` runs `cd <projectPath> && claude plugins update -s
  <scope> <id>` for project-only records (`update` accepts `-s project|local`). Never
  touches ai-config, but contradicts the operator rule that external plugins live at user
  scope and keeps dead installs updated. Rejected for now (operator, 2026-11-06).

## Design

### Detection: `claude_plugin_prune.py --list-project-only`

The module already parses and validates `installed_plugins.json` (`_validate`: JSON
object, supported `version`, a `plugins` object) and owns the `("project", "local")`
scope set. A new mode reuses both and writes nothing. One line per id that has no `user`
record and at least one `project` or `local` record, sorted by id, records within a line
sorted:

```
<id>\t<enablement>\t<scope>:<projectPath>[,<scope>:<projectPath>...]
```

`<enablement>` is `enabled` when at least one record's project enables the id, `unknown`
when none does and at least one record's project settings could not be read, otherwise
`disabled`. For one record, the project enables the id when its effective value is `true`:
`<projectPath>/.claude/settings.local.json` `enabledPlugins[<id>]` when that file has the
key, else `<projectPath>/.claude/settings.json`'s. A missing file or missing key is not
enabled. A file that exists but cannot be read or parsed as a JSON object makes that record
unreadable. A record with no `projectPath`, or one whose directory is gone, is not enabled
and prints `-` for a missing path.

Exit 0 (no lines when none). An unusable plugins file exits 3 with one `refused: <reason>`
line, as `prune` does.

**Parser shape.** `--list-project-only` takes only `--file`; combining it with
`--backup-dir`, `--keep` or `--dry-run` is a `parser.error` (exit 2). Without
`--list-project-only`, `--backup-dir` stays mandatory (`parser.error`, exit 2), so an argv
that loses the mode flag can never reach `prune()`.

### Doctor check: `_doctor_check_plugin_scope`

Called from `run_doctor` immediately after `_doctor_check_plugin_node_paths`. Reads the
plugins file through the existing `_OVERRIDE_CLAUDE_PLUGINS_FILE` seam and the interpreter
through `_CLAUDE_PRUNE_PYTHON`. The user manifest is read once per check via
`_claude_plugin_manifest`.

- Plugins file absent: no section, no counted check (no Claude Code plugins).
- Interpreter missing, or the helper refuses or exits non-zero: header plus one WARN naming
  the reason (`python3 not found`, or the `refused:` line). Never a PASS.
- No project-only id: header `Claude plugin scope:` plus one PASS.
- Otherwise one WARN per id, label `<id>`, detail
  `installed only at <scope>:<path>[, ...] — never updated by -t update — <remedy>`.

`<settings-check>` below is
`git -C "$(dirname "$(readlink -f ~/.claude/settings.json)")" diff --exit-code settings.json`,
which exits non-zero if the install left the tracked file changed.

| Enablement | User manifest | Remedy text |
| --- | --- | --- |
| `disabled` | any | `run: (cd '<path>' && claude plugins uninstall -s <scope> <id>)` per record, joined with `; ` |
| `enabled` | `true` | `run: claude plugins install -s user <id>` and `setup_claude_plugins did not install it` |
| `enabled` | `false` | `run: claude plugins install -s user <id>; claude plugins disable -s user <id>; <settings-check>` |
| `enabled` | absent | `add <id> as false to ai-config .claude/settings.json enabledPlugins, then run: claude plugins install -s user <id>; claude plugins disable -s user <id>; <settings-check>` |
| `enabled` | unreadable | `user manifest unreadable — cannot choose a remedy` (no command) |
| `unknown` | any | `cannot read project settings for <path> — cannot choose a remedy` (no command) |

`;`, not `&&`, between install and disable: if install flips the tracked file and then
exits non-zero, disable still runs and the settings check still reports. Once the user
record exists, the next `-t update` prunes the project records (ADR-0055).

WARN, not FAIL: the cost is a stale or dead plugin, not a broken session.

## Testing

- pytest (`tests/test_claude_plugin_prune.py`): `--list-project-only` on a fixture shaped
  like workstation's file (16 ids, the five project-only ones, one with two project
  paths, one with both user and project records) plus fixture project directories with
  settings files reproducing workstation's enablement asserts the exact five-line output;
  `settings.local.json` overriding `settings.json` in both directions; an unreadable
  project settings file gives `unknown`; a gone `projectPath` gives `disabled`; the plugins
  file is byte-identical afterwards and no backup directory is created; refusal on a
  non-object file exits 3; `local` scope listed; an id with a `user` record never listed.
  Parser: `--file f` alone exits 2 with the file byte-identical; `--list-project-only`
  with `--backup-dir` exits 2.
- bats (new `tests/setup_env/plugin_scope.bats`, mirroring `plugin_node_paths.bats`): every
  remedy case drives the real helper on a fixture plugins file and fixture project
  directories; a stubbed interpreter is used only for the missing-interpreter and
  helper-failure cases. Cases: absent file (no output, no counters moved); PASS; one case
  per remedy-table row asserting the exact remedy text; refusal; missing interpreter via
  `_CLAUDE_PRUNE_PYTHON`; `run_doctor` calls the check after the node-path check.

## Requirements

- **R1.** `lib/claude_plugin_prune.py --list-project-only --file <f>` prints one line `<id>\t<enablement>\t<scope>:<projectPath>[,...]` per id with no `user` record and at least one `project` or `local` record, sorted by id, and exits 0.
- **R2.** `<enablement>` is `enabled` if any record's project has an effective `enabledPlugins[<id>]` of `true` (`.claude/settings.local.json` when it has the key, else `.claude/settings.json`), else `unknown` if any record's project settings file exists but cannot be read or parsed as a JSON object, else `disabled`.
- **R3.** `--list-project-only` never writes the plugins file and never creates or writes the backup directory.
- **R4.** `--list-project-only` on a plugins file `_validate` rejects or cannot parse exits 3 with one line starting `refused: `.
- **R5.** `--list-project-only` combined with `--backup-dir`, `--keep` or `--dry-run` exits 2; without `--list-project-only`, an argv lacking `--backup-dir` exits 2 and leaves the plugins file byte-identical.
- **R6.** `run_doctor` calls `_doctor_check_plugin_scope` immediately after `_doctor_check_plugin_node_paths`.
- **R7.** With the plugins file absent, `_doctor_check_plugin_scope` prints nothing and changes no doctor counter.
- **R8.** With no project-only id, the check prints the header `Claude plugin scope:` and exactly one PASS.
- **R9.** A `disabled` id's WARN gives `(cd '<path>' && claude plugins uninstall -s <scope> <id>)` for each record, joined with `; `.
- **R10.** An `enabled` id whose user manifest value is `true` gets the remedy `claude plugins install -s user <id>`.
- **R11.** An `enabled` id whose user manifest value is `false` gets the remedy `claude plugins install -s user <id>; claude plugins disable -s user <id>; git -C "$(dirname "$(readlink -f ~/.claude/settings.json)")" diff --exit-code settings.json`.
- **R12.** An `enabled` id absent from the user manifest gets the R11 command preceded by an instruction to add the id as `false` to ai-config `.claude/settings.json` `enabledPlugins`.
- **R13.** An `enabled` id when `_claude_plugin_manifest` fails, and every `unknown` id, gets a WARN containing `cannot choose a remedy` and no `claude plugins` command.
- **R14.** When the interpreter is missing or the helper exits non-zero, the check prints one WARN naming the reason and no PASS.
- **R15.** The Backlog of `docs/superpowers/README.md` gains one row naming both B (reconcile installs then disables `false` ids) and the in-place `update -s project` alternative, citing this spec, and the "Some Claude plugins are installed only at project scope" row is removed and replaced by a pointer to this spec.
- **V1.** On workstation, before any repair, `./setup_env.sh -t doctor` prints one plugin-scope WARN per project-only id: R9 remedies for `frontend-design`, `rust-analyzer-lsp` and `skill-creator`, and R11 remedies for `ansible-good-practices` and `terraform-skill` (less any id repaired by the 2026-11-06 probe).
- **V2.** On workstation, paste one R11 remedy and one R9 remedy: the R11 line's `git diff --exit-code` exits 0, `cmp` shows ai-config `.claude/settings.json` byte-identical to its pre-remedy copy, and a following `-t doctor` no longer lists either id.
- **V3.** On `claude`, `studio` and `laptop-1`, `-t doctor` prints the plugin-scope PASS.
- **N1.** The check never runs `claude` and writes no file.
- **N2.** `setup_claude_plugins` and ADR-0034 decision 2 are unchanged.
- **N3.** No plugin-scope result is a FAIL.

## Multi-Lens Review

Reviewed at commit: `5702ffa9` (Step 7 self-review commit, before Step 8 dispatch)

### Goal-Fit

Finding: The remedy table branches on the wrong input. Whether staleness costs anything depends on whether any settings scope enables the plugin, not on the user manifest value. Measured read-only on workstation: of the five, only `ansible-good-practices` and `terraform-skill` are `true` anywhere (terraform_ansible project settings); `frontend-design`, `rust-analyzer-lsp` and `skill-creator` are `false` in user, terraform_ansible and dotfiles settings, so they are dead installs and the right remedy is `uninstall -s project` per record. Yet V1 requires the R8 remedy for all five, which would turn three dead records into user-scope plugins `-t update` refreshes forever. Simpler path not weighed: `claude plugins update` accepts `-s project|local`, so `-t update` could update project-only records in place (`cd <projectPath> && claude plugins update -s <scope> <id>`), never touching ai-config and not reversing ADR-0034. Reads-it test: consumer is the operator at doctor time; changes a decision (yes); durable output none. Premise verified at `5702ffa9` (`lib/workflows.sh:279`; update loop at 1000-1014 updates any user-installed manifest id, `true` or `false`; ids absent from the manifest are never updated even with a user record). Empty-helper check: R5, R6, V3 pass on empty output; R7-R10 and V1 would fail.
Assumption: a project-scope install serves only sessions inside its `projectPath`, so a fresh machine reproduces this only through Claude Code's project-install prompt; if a user-scope install satisfies project `enabledPlugins` without re-prompting, R8 is a one-time fix and the check is near-decoration after workstation is repaired. Settle by opening terraform_ansible on a host with no user record and observing the prompt, and by reading `installedAt` of the user records on the three clean hosts (before 2026-09-19 or not).
Disposition: Addressed (operator, 2026-11-06) — remedy now branches on project enablement (dead installs get `uninstall -s project`); in-place `update -s project` recorded as a rejected rival in the B backlog row (R15); `installedAt` read on the clean hosts, all before 2026-09-19, so a fresh machine reproduces the state.

### Ergonomics

Finding: Same defect as Goal-Fit, reached independently: R8 is wrong for 3 of 5 ids (orphan installs enabled nowhere); fix is one more input, `enabledPlugins` from each record's `<projectPath>/.claude/settings.json`: install-then-disable only when some project enables the id, otherwise uninstall. Secondary: (a) with `&&`, an `install` that rewrites `settings.json` then exits non-zero skips `disable`, leaving ai-config dirty with no signal; (b) V2 proves byte-identity but not that a user record now exists; add a doctor re-run showing the WARN gone; (c) the absent row's remedy ("add … or (cd …)") is prose, not pasteable. Premise verified (`lib/workflows.sh:79-87`, `:279`; workstation `~/.claude/settings.json` resolves into ai-config). Empty-helper: R6 and V3 pass on empty output; pytest five-line fixture and V1 catch it.
Assumption: `claude plugins install -s user <id>` adds a user record when a project record for the same id exists, rather than exiting 0 as "already installed"; if false, R7/R8 do nothing and the WARN recurs. Settle on a scratch `HOME` with a copied `installed_plugins.json`, or by running V2 and re-running doctor.
Disposition: Addressed (operator, 2026-11-06) — enablement input added (R2); `;` instead of `&&` plus a settings diff check (R11); V2 re-runs doctor; absent-from-manifest remedy is a stated instruction plus a pasteable command (R12).

### Risk

Finding: Low risk overall, not over-engineered; two write-path gaps. (1) `claude_plugin_prune.py`'s `main()` has no mode: `--file` and `--backup-dir` are `required=True` and any accepted argv runs `prune()`, which rewrites the file. Doctor will not pass `--backup-dir`, so the implementer must relax it, and the spec does not say how; if `--backup-dir` gains a default, any call that loses `--list-project-only` (empty array element, quoting slip, refactor) silently prunes. Needs an R: list mode excludes `--backup-dir`/`--keep`/`--dry-run`, `--backup-dir` stays mandatory otherwise (`parser.error`), and a test that `--file f` alone exits 2 with the file byte-identical. (2) R8's `&&`: if install succeeds and disable fails, the plugin is enabled in every session on that host and the shared ai-config checkout holds a dirty tracked file a peer session could commit; use `;` and append `git -C ~/git-repos/personal/ai-config diff --exit-code .claude/settings.json`. Empty-helper: R6, V3 and the bats PASS case pass on empty output; the pytest fixture is hand-built (a real schema change would not show); the bats remedy cases catch it only if they drive the real helper rather than a stubbed interpreter, which the spec does not say; after V2 repairs workstation no host produces output, so an always-empty check looks healthy from then on. Premise verified (workstation probe: 16 ids, the same five; `:279` as cited).
Assumption: same as Ergonomics: `install -s user` creates a separate user record beside an existing project record, and the following `disable -s user` restores `settings.json` byte-identical in that situation (ADR-0034 measured only ids with no existing record). Settled by V2, which changes state and so is the operator's to run.
Disposition: Addressed (operator, 2026-11-06) — parser shape pinned (R5, `--file f` alone exits 2 byte-identical); `;` plus settings diff check (R11); bats remedy cases drive the real helper on fixtures. Install-beside-project-record assumption: probe handed to the operator after the auto-mode classifier refused the remote write.

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.

### Round 2 (reviewed at `18046a6a`, all three lenses, design substance changed)

**Goal-Fit.** Finding: false premise. The spec dates the clean hosts' user records to before 2026-09-19 and never applies the same test to workstation. Measured (lens, then re-measured by the orchestrator, read-only): all six project-only records on workstation have `installedAt` 2026-05-02 to 2026-09-07, all before 2026-09-19; `lastUpdated` 2026-10-16 to 2026-11-05, so the pre-#427 default-scope `update` kept them fresh until `-s user`. Current dotfiles writes no project scope, so the three dead installs cannot recur and the two enabled ids recur only if Claude Code itself installs at project scope when a project enables an id the user manifest has `false` (unverified). Simpler path: a one-time workstation repair, check or option B only if that recurs. Also: a missing `projectPath` yields `(cd '-' && …)`. Assumption: on a fresh machine Claude Code installs a project-enabled, user-`false` plugin at project scope; settle by starting `claude` in `terraform_ansible` on a host with no record for `terraform-skill@antonbabenko` and reading `installed_plugins.json` (state-changing, operator's). Disposition:

**Ergonomics.** Finding: the `disabled` row (R9) is unsafe or unclearable in two spec-created cases and is the only row without a tracked-file check. (1) A missing path prints `-`, and `(cd '-' && …)` in zsh jumps to `OLDPWD` (measured: `zsh -fc 'cd /etc; cd /tmp; (cd '-' && pwd)'` printed `/etc`), so the paste runs a project uninstall in an arbitrary directory. (2) A gone directory is classed `disabled`, the `cd` fails, and the WARN recurs forever; ADR-0055 §2 says the CLI cannot reach gone-directory records, and worktree sessions create them. (3) `uninstall -s project` may rewrite the project's tracked `.claude/settings.json`. Checked fine: settings-check resolves and runs rc 0 on `claude`; `; ` joining; line length acceptable. Latent today: 7 project/local records on workstation, 0 gone paths. Assumption: `uninstall -s project` leaves `<path>/.claude/settings.json` unchanged; settle in a scratch git repo (install -s project, commit, uninstall -s project, `git diff --exit-code`), state-changing. Disposition:

**Risk.** Finding: R9 writes tracked files in peer repos with no check. Claude Code 2.1.318 binary strings indicate uninstall removes the id's line from that scope's settings file; on workstation every `disabled` record is under `terraform_ansible` (another session's repo, git-workflow-020) plus one under `dotfiles`, both tracking `.claude/settings.json` with the ids as `false`. V2 compares only ai-config. Fix: `git -C '<path>' diff --exit-code .claude/settings.json` after each uninstall and coordinate with the owning session. Secondary: gone `projectPath` needs its own row; R5 sound; proportionate. Assumption: same as Ergonomics (strings suggest yes, unproven). Disposition:

## Retirement

Retired 2026-11-06 by the operator after the round-2 Multi-Lens Review, in favour of a
one-time repair on `workstation`. The `terraform_ansible` session ran the repair there,
each block approved by the operator in that session. Results:

- `claude plugins uninstall -s project` removed the project records for
  `frontend-design`, `rust-analyzer-lsp` and `skill-creator` (in `terraform_ansible` and
  `dotfiles`), and the stale `caveman@caveman` 2.7.0 project record in
  `terraform_ansible`. The first fleet count missed that caveman record because it had a
  user record beside it, and the prune keeps it (see below).
- **Measured: `uninstall -s project <id>` deletes `<id>`'s key from the project's tracked
  `.claude/settings.json`,** whether the key is `true` or `false`, and moves the
  `enabledPlugins` object to the end of the file. This was seen on `terraform_ansible`'s
  real file and reproduced on `claude` with a throwaway git project (Claude Code
  2.1.318). Each uninstall was therefore followed by
  `git checkout -- .claude/settings.json`, which left `"caveman@caveman": true` in place.
  The R9 remedy in this spec would have disabled caveman in every `terraform_ansible`
  session.
- `claude plugins install -s user` then `disable -s user` added user records for
  `ansible-good-practices` and `terraform-skill`. The ai-config manifest kept both
  `false`, **but the file was not restored byte-identical**: `skillListingBudgetFraction`
  and the `skillOverrides` block moved from the end of the file to after `model`, with no
  value changed. That contradicts the 2026-09-19 measurement behind ADR-0034 decision 2.
  The operator had it reverted with `git checkout -- .claude/settings.json`; both ids
  stayed `false`.
- After the repair, the only non-user records on `workstation` are the
  `terraform_ansible` project records of `ansible-good-practices` and `terraform-skill`.
  Their new user records are newer, so the next `-t update` prunes both.
- `CLAUDE_CONFIG_DIR` does not isolate `claude plugins install`: the `claude` probe
  wrote a project record into the real `~/.claude/plugins/installed_plugins.json` while
  `uninstall` cleaned only the redirected copy. The stray record was removed by hand,
  with a backup taken first.
