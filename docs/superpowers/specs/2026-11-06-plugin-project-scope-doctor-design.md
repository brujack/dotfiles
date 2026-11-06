# Doctor WARN for Claude plugins installed only at project scope

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

On `claude`, `studio` and `laptop-1` all five ids have a `user` record. All five are
`false` in the user manifest (`~/.claude/settings.json`, tracked in ai-config).
`terraform_ansible/.claude/settings.json` on workstation enables
`ansible-good-practices` and `terraform-skill`; every other of the five is `false` there
and in `dotfiles/.claude/settings.json`.

### Cause

`setup_claude_plugins` installs only ids whose manifest value is `true`
(`lib/workflows.sh:279`). That is a recorded decision, not an oversight: the 2026-09-19
provisioning spec (decision 2, ADR-0034) measured that `claude plugins install` of a
`false` id rewrites it to `true` in the tracked `settings.json`, and that a following
`claude plugins disable` restores the file byte-identical. The three clean hosts hold user
records left by the pre-2026-09-19 hardcoded install list (inferred, `installedAt` not
read). Workstation's state is what current dotfiles produces on a fresh machine.

The remedy the backlog row proposed (`claude plugins install -s user <id>`) is therefore
wrong for a `false` id: it would dirty ai-config and enable the plugin everywhere.

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
  another session's repo._ This check reads installed state, not repo settings; it is a
  WARN; every remedy is a local command on the machine that runs doctor.
- _Close to decoration: output ephemeral, no copier of `enabledPlugins` exists._ Still
  partly true: doctor output is read by the operator at run time and kept nowhere. The
  hazard is real here (five ids on workstation, measured), unlike the copier the dropped
  check guarded against. The durable channel stays the backlog row for option B.

## Decision

Option C of three: a doctor WARN now (this spec); changing the reconcile to install and
then disable `false` ids (option B) goes to the backlog as its own decision, because it
reverses ADR-0034 decision 2. The doctor check also covers project-only ids absent from
the manifest, which B cannot reach.

## Design

### Detection: `claude_plugin_prune.py --list-project-only`

The module already parses and validates `installed_plugins.json` (`_validate`: JSON
object, supported `version`, a `plugins` object) and owns the `("project", "local")`
scope set. A new mode reuses both and writes nothing:

```
<id>\t<scope>:<projectPath>[,<scope>:<projectPath>...]
```

one line per id that has no `user` record and at least one `project` or `local` record,
sorted by id; records within a line sorted. Exit 0 (no lines when none). An unusable file
exits 3 with one `refused: <reason>` line, as `prune` does. A missing file exits 0 with no
output (the shell decides absence first; see below). Records with a missing
`projectPath` print `-`.

### Doctor check: `_doctor_check_plugin_scope`

Called from `run_doctor` immediately after `_doctor_check_plugin_node_paths`. Reads the
plugins file through the existing `_OVERRIDE_CLAUDE_PLUGINS_FILE` seam and the interpreter
through `_CLAUDE_PRUNE_PYTHON`.

- Plugins file absent: no section, no counted check (no Claude Code plugins).
- Interpreter missing, or the helper refuses or exits non-zero: header plus one WARN naming
  the reason (`python3 not found`, or the `refused:` line). Never a PASS.
- No project-only id: header `Claude plugin scope:` plus one PASS.
- Otherwise one WARN per id, label `<id>`, detail
  `installed only at <scope>:<path>[, ...] — never updated by -t update — run: <remedy>`.
  The remedy depends on the id's value in `_claude_plugin_manifest`:

| Manifest value      | Remedy                                                                                                                                |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| `true`              | `claude plugins install -s user <id>`, detail also says the reconcile did not install it                                              |
| `false`             | `claude plugins install -s user <id> && claude plugins disable -s user <id>`                                                          |
| absent              | `add <id> to ai-config .claude/settings.json enabledPlugins, or (cd '<path>' && claude plugins uninstall -s <scope> <id>)` per record |
| manifest unreadable | no remedy command; detail says `user manifest unreadable — cannot choose a remedy`                                                    |

The manifest is read once per check, not per id.

WARN, not FAIL: the cost is a plugin that goes stale, not a broken session.

## Testing

- pytest (`tests/test_claude_plugin_prune.py`): `--list-project-only` on a fixture shaped
  like workstation's file (16 ids, the five project-only ones, one with two project
  paths, one with both user and project records) asserts the exact five-line output; the
  file is byte-identical afterwards and no backup directory is created; refusal on a
  non-object file exits 3; `local` scope listed; an id with a `user` record never listed.
- bats (new `tests/setup_env/plugin_scope.bats`, mirroring `plugin_node_paths.bats`):
  absent file (no output, no counters moved); PASS; one case per manifest row (true,
  false, absent, unreadable) asserting the exact remedy line; refusal; missing
  interpreter via `_CLAUDE_PRUNE_PYTHON`; `run_doctor` calls the check after the
  node-path check.

## Requirements

- **R1.** `lib/claude_plugin_prune.py --list-project-only --file <f>` prints one line `<id>\t<scope>:<projectPath>[,...]` per id with no `user` record and at least one `project` or `local` record, sorted by id, and exits 0.
- **R2.** `--list-project-only` never writes the plugins file and never creates or writes the backup directory.
- **R3.** `--list-project-only` on a file `_validate` rejects or cannot parse exits 3 with one line starting `refused: `.
- **R4.** `run_doctor` calls `_doctor_check_plugin_scope` immediately after `_doctor_check_plugin_node_paths`.
- **R5.** With the plugins file absent, `_doctor_check_plugin_scope` prints nothing and changes no doctor counter.
- **R6.** With no project-only id, the check prints the header `Claude plugin scope:` and exactly one PASS.
- **R7.** For a project-only id whose manifest value is `true`, the WARN's remedy is `claude plugins install -s user <id>`.
- **R8.** For a project-only id whose manifest value is `false`, the WARN's remedy is `claude plugins install -s user <id> && claude plugins disable -s user <id>`.
- **R9.** For a project-only id absent from the manifest, the WARN names adding the id to ai-config `.claude/settings.json` `enabledPlugins` and, per record, `(cd '<path>' && claude plugins uninstall -s <scope> <id>)`.
- **R10.** When `_claude_plugin_manifest` fails, each project-only id gets a WARN containing `user manifest unreadable` and no `claude plugins` command.
- **R11.** When the interpreter is missing or the helper exits non-zero, the check prints one WARN naming the reason and no PASS.
- **R12.** The Backlog of `docs/superpowers/README.md` gains a row for installing then disabling `false` ids in the reconcile (option B), citing this spec, and the "Some Claude plugins are installed only at project scope" row is closed or rewritten to point at this spec.
- **V1.** On workstation, before any repair, `./setup_env.sh -t doctor` prints exactly five plugin-scope WARNs, each with the R8 remedy.
- **V2.** On workstation, run one R8 remedy; `cmp` shows ai-config `.claude/settings.json` byte-identical to its pre-remedy copy and `git -C ai-config status --porcelain` is empty.
- **V3.** On `claude`, `studio` and `laptop-1`, `-t doctor` prints the plugin-scope PASS.
- **N1.** The check never runs `claude` and writes no file.
- **N2.** `setup_claude_plugins` and ADR-0034 decision 2 are unchanged.
- **N3.** No plugin-scope result is a FAIL.

## Multi-Lens Review

Reviewed at commit: `5702ffa9` (Step 7 self-review commit, before Step 8 dispatch)

### Goal-Fit

Finding: The remedy table branches on the wrong input. Whether staleness costs anything depends on whether any settings scope enables the plugin, not on the user manifest value. Measured read-only on workstation: of the five, only `ansible-good-practices` and `terraform-skill` are `true` anywhere (terraform_ansible project settings); `frontend-design`, `rust-analyzer-lsp` and `skill-creator` are `false` in user, terraform_ansible and dotfiles settings, so they are dead installs and the right remedy is `uninstall -s project` per record. Yet V1 requires the R8 remedy for all five, which would turn three dead records into user-scope plugins `-t update` refreshes forever. Simpler path not weighed: `claude plugins update` accepts `-s project|local`, so `-t update` could update project-only records in place (`cd <projectPath> && claude plugins update -s <scope> <id>`), never touching ai-config and not reversing ADR-0034. Reads-it test: consumer is the operator at doctor time; changes a decision (yes); durable output none. Premise verified at `5702ffa9` (`lib/workflows.sh:279`; update loop at 1000-1014 updates any user-installed manifest id, `true` or `false`; ids absent from the manifest are never updated even with a user record). Empty-helper check: R5, R6, V3 pass on empty output; R7-R10 and V1 would fail.
Assumption: a project-scope install serves only sessions inside its `projectPath`, so a fresh machine reproduces this only through Claude Code's project-install prompt; if a user-scope install satisfies project `enabledPlugins` without re-prompting, R8 is a one-time fix and the check is near-decoration after workstation is repaired. Settle by opening terraform_ansible on a host with no user record and observing the prompt, and by reading `installedAt` of the user records on the three clean hosts (before 2026-09-19 or not).
Disposition:

### Ergonomics

Finding: Same defect as Goal-Fit, reached independently: R8 is wrong for 3 of 5 ids (orphan installs enabled nowhere); fix is one more input, `enabledPlugins` from each record's `<projectPath>/.claude/settings.json`: install-then-disable only when some project enables the id, otherwise uninstall. Secondary: (a) with `&&`, an `install` that rewrites `settings.json` then exits non-zero skips `disable`, leaving ai-config dirty with no signal; (b) V2 proves byte-identity but not that a user record now exists; add a doctor re-run showing the WARN gone; (c) the absent row's remedy ("add … or (cd …)") is prose, not pasteable. Premise verified (`lib/workflows.sh:79-87`, `:279`; workstation `~/.claude/settings.json` resolves into ai-config). Empty-helper: R6 and V3 pass on empty output; pytest five-line fixture and V1 catch it.
Assumption: `claude plugins install -s user <id>` adds a user record when a project record for the same id exists, rather than exiting 0 as "already installed"; if false, R7/R8 do nothing and the WARN recurs. Settle on a scratch `HOME` with a copied `installed_plugins.json`, or by running V2 and re-running doctor.
Disposition:

### Risk

Finding: Low risk overall, not over-engineered; two write-path gaps. (1) `claude_plugin_prune.py`'s `main()` has no mode: `--file` and `--backup-dir` are `required=True` and any accepted argv runs `prune()`, which rewrites the file. Doctor will not pass `--backup-dir`, so the implementer must relax it, and the spec does not say how; if `--backup-dir` gains a default, any call that loses `--list-project-only` (empty array element, quoting slip, refactor) silently prunes. Needs an R: list mode excludes `--backup-dir`/`--keep`/`--dry-run`, `--backup-dir` stays mandatory otherwise (`parser.error`), and a test that `--file f` alone exits 2 with the file byte-identical. (2) R8's `&&`: if install succeeds and disable fails, the plugin is enabled in every session on that host and the shared ai-config checkout holds a dirty tracked file a peer session could commit; use `;` and append `git -C ~/git-repos/personal/ai-config diff --exit-code .claude/settings.json`. Empty-helper: R6, V3 and the bats PASS case pass on empty output; the pytest fixture is hand-built (a real schema change would not show); the bats remedy cases catch it only if they drive the real helper rather than a stubbed interpreter, which the spec does not say; after V2 repairs workstation no host produces output, so an always-empty check looks healthy from then on. Premise verified (workstation probe: 16 ids, the same five; `:279` as cited).
Assumption: same as Ergonomics: `install -s user` creates a separate user record beside an existing project record, and the following `disable -s user` restores `settings.json` byte-identical in that situation (ADR-0034 measured only ids with no existing record). Settled by V2, which changes state and so is the operator's to run.
Disposition:

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison/evaluator/ambiguous-criteria trigger.
