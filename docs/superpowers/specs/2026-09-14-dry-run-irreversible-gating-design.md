# `--dry-run` gates irreversible operations

**Date:** 2026-09-14
**Status:** Design — approved by operator, pending Multi-Lens Review

## Problem

`--dry-run` is documented as "log mutating operations (symlinks, installs, mkdir) without
executing" (`CLAUDE.md:92`). It does not do that. It executes destructive operations,
including a push to a GitHub remote.

Measured on the **Studio**, 2026-09-14, one run of `setup_env.sh -t setup_user --dry-run`:

```
[DRY RUN] lines emitted                 7  of 90 output lines
real git pull into ai-config            3000d538..754bdffc, 4 files, 117 insertions
real commit + push to state-ledger      e76d0d9..6311ec1  main -> main
```

The state-ledger push was verified independently of the run's own output: commit `6311ec1`
is present in that repo and `git rev-list --count origin/main..HEAD` reads 0, so it reached
the remote. That is one run on one machine, not a fleet claim.

One correction to an earlier reading of the same log, recorded because it would otherwise
inflate the problem: the `Created /Users/bruce/.tf_creds`-style lines are **not** evidence of
mutation. All seven such directories carry birth dates from 2022 or 2026-01, none from the
run, so `mkdir -p` no-op'd and the log line prints unconditionally. The two mutations above
are the whole measured harm.

### Where it comes from

The design this flag shipped under
(`specs/2026-04-08-doctor-dry-run-design.md:18`) calls `run_cmd` "a thin wrapper used by
**all mutating helpers**". Its plan wired exactly one caller — `safe_link` — and nothing
widened it since. This is `behavior.md`'s "a fix scoped to one call site, verified at that
call site": the verification passed because it only ever exercised `safe_link`.

Static counts over `setup_env.sh` + `lib/*.sh` + `scripts/*.sh` (36 files), 2026-09-14:

```
mutating-verb lines          234
run_cmd call sites             5      (4 in lib/helpers.sh, 1 in lib/git_hooks.sh)
DRY_RUN read sites             6      (2 in lib/helpers.sh, 4 in lib/git_hooks.sh)
```

`lib/developer.sh`, `lib/macos.sh`, `lib/workflows.sh`, `lib/git_sync.sh` and
`lib/legacy_rsync.sh` read `DRY_RUN` **zero** times.

These are counts from a verb-matching classifier written for this spec, not from a parser.
It was run with a positive control (8 hits in `lib/legacy_rsync.sh`, a file known to contain
them) after an earlier version of it returned `TOTAL 0` — a broken instrument, not a clean
codebase. Treat 234 as the order of magnitude, not a precise inventory. The 9-site scope
table below was enumerated individually and is exact.

## Decision

**Gate the operations that leave the machine or destroy state the remote cannot reproduce.
Do not attempt to make `--dry-run` a total no-op.**

Rejected: widening `run_cmd` to all 234 sites. 47 of them are pipelines, in-command
redirects, or commands inside quoted `trap` strings, which `run_cmd "$@"` structurally
cannot wrap, so a total guarantee needs a second mechanism as well; and the diff would touch
every lib file and every workflow, with regression risk across `setup`, `setup_user`,
`developer` and `update`. (The 187/47 split is from the same approximate classifier.)

Also rejected: leaving behaviour alone and narrowing `CLAUDE.md:92` to match. Cheapest and
zero code risk, but it leaves no safe way to preview a run — which is the thing the flag
exists for — and `-t update` / `-t developer` stay unrunnable without accepting live
`rsync --delete` and venv deletion.

## Scope

Ten sites in eight functions — `sync_legacy_dirs` holds three of them. Enumerated
individually with enclosing function and shape;
`shape` is what `run_cmd` can accept.

| function                                          | operation                                            | shape    |
| ------------------------------------------------- | ---------------------------------------------------- | -------- |
| `sync_legacy_dirs` (`legacy_rsync.sh:17,19,27`)   | `rsync -ar --delete` to workstation, laptop-1, ratna | simple   |
| `setup_ansible` (`developer.sh:530`)              | `pyenv virtualenv-delete -f ansible`                 | simple   |
| `recreate_python_venv` (`developer.sh:554`)       | `pyenv virtualenv-delete -f`                         | guarded  |
| `recreate_ruby` (`developer.sh:419`)              | `rm -rf ~/.rubies/ruby-${RUBY_VER}`                  | simple   |
| `_install_go_from_tarball` (`linux_ubuntu.sh:89`) | `sudo rm -rf /usr/local/go`                          | simple   |
| `setup_ai_config` (`workflows.sh:107`)            | `rm -rf` the ai-config repo root                     | guarded  |
| `ensure_state_ledger` (`workflows.sh:931`)        | `rm -rf` the ledger checkout                         | guarded  |
| `setup_zsh_as_default_shell` (`helpers.sh:384`)   | `chsh`                                               | compound |

`workflows.sh:107` fires only in the `else` branch, when `_git_is_valid_repo` is false — it
deletes a corrupt checkout before re-cloning, and that checkout may hold uncommitted work.
`workflows.sh:931` deletes a tool-managed cache, included because it can hold unpushed spool
entries the remote cannot reproduce.

**Deliberately not gated**, so the omission reads as a decision: the `trap` string at
`developer.sh:76` (`rm -rf "${_ring}"`, its own gpg homedir), `~/software_downloads/*`
download dirs, the five `rm -rf "${_tmp}"` in `_install_rustup_rs`, and
`rm -rf "/tmp/python-build.*"` — all self-created scratch, recreated on the next run.

`scripts/whats-new-anthropic.sh` and `scripts/whats-new-claude-code.sh` both call `git push`
and are **out of scope because they are unreachable** from any `-t` workflow or LaunchAgent.
Measured repo-wide over tracked files: excluding `docs/`, five files reference them and all
five are tests or a mock comment; `LaunchAgents/cadence.plist.template` runs
`scripts/cadence-notify.sh` only. Verified with positive controls in the same sweep
(`cadence-notify` 8 referencing files, `run-bash-coverage` 26), because an unchecked zero is
what this spec's own problem statement is made of. Those scripts already carry their own
`--dry-run`.

## Design

### 1. The rule

> If the function's **purpose** is the destructive act, guard the function.
> If destruction is **incidental** to otherwise-useful work, wrap the line.

Stated here because the design uses two mechanisms, and without the rule a reviewer will
apply the wrong one.

**Function guards** — an early `return 0` at the top, after any logging. The zero is
load-bearing: callers invoke these as `fn || return 1`, so a non-zero dry-run guard would
report a preview as a failed run. Applies to `sync_legacy_dirs`, `recreate_python_venv`,
`recreate_ruby`.

**Line wraps** via `run_cmd`: `setup_ai_config`, `ensure_state_ledger`,
`_install_go_from_tarball`, `setup_ansible`. Each of these does substantial non-destructive
work that a preview should still perform and report — `setup_ai_config` pulls when the repo
is valid, `setup_ansible` builds the venv — so a function guard would make `--dry-run` show
_less_ than it does today.

The function-guard shape mirrors existing in-repo prior art rather than inventing one:
`scripts/whats-new-claude-code.sh:116` holds a local `_dry_run`, prints, and returns 0
before ever reaching `commit_and_push`, which itself has no dry-run awareness.

### 2. The `chsh` exception

`helpers.sh:384` is line-level by the rule, but **`run_cmd` is the wrong tool there** and
using it would reintroduce a bug the file was just fixed for.

The construct is:

```bash
if ! sudo -n chsh -s "${ZSH_PATH}" "${USER}" 2>/dev/null && ! chsh -s "${ZSH_PATH}"; then
  log_error "Could not change login shell to ${ZSH_PATH}"
  return 1
fi
log_info "Changed default shell to ${ZSH_PATH}"
```

Under `DRY_RUN`, `run_cmd` prints and returns 0, so `! 0` is false, the `&&` short-circuits,
the error body is skipped, and control falls through to `log_info "Changed default shell"` —
reporting a shell change that never happened. That is exactly the failure the comment at
`helpers.sh:382` records as having just been fixed ("the previous version checked neither
and then logged success unconditionally").

So this site gets an explicit `DRY_RUN` check immediately before the `if`, printing the
intended command and returning 0 **without** the success log.

Everything above it — resolving `ZSH_PATH`, reading the account's real login shell via
`_current_login_shell`, the already-zsh early return, the not-executable error — is
non-destructive and must still run, because it is exactly what a preview should show.

### 3. Standalone entry point

`scripts/sync_git_repos.sh` sources `lib/helpers.sh` at its own line 72, so `run_cmd` is
reachable there. But `--dry-run` is parsed only in `process_args` (`helpers.sh:811`, with the
flag's own arm at `:818`), which is called only from `setup_env.sh:60` — so the standalone
path has no `--dry-run` today and `DRY_RUN` is simply unset.

Add `--dry-run` to that script's own arg loop, beside its existing `--git-only`,
`--legacy-only` and `-h`. It is the entry point that fires `rsync --delete` at three hosts,
`CLAUDE.md` already warns never to invoke it unmocked outside the bats harness, and its
sibling `whats-new-*.sh` scripts already carry the same flag.

## Testing

Adopt the marker-file idiom already used by
`tests/setup_env/git_hooks.bats:1269` — a fixture whose recipe `touch`es a marker, with the
test asserting `[ ! -f marker ]`. That proves the command never executed, rather than
asserting on output text, which a printed `[DRY RUN]` line would satisfy either way.

**Every marker-absence case is paired with a positive control** — the same fixture run
_without_ `DRY_RUN`, asserting the marker **is** created. Without the pair, marker-absence
passes vacuously when the fixture never ran at all, and the suite would then test the
comparison and never the measurement feeding it.

Established idiom for driving the flag, from the existing suite:
`DRY_RUN=1 PERSONAL_GITREPOS="${_base}" run install_git_hooks_all_repos`. `DRY_RUN` is an
ordinary environment variable in test context — the `readonly` at `helpers.sh:818` fires only
inside `process_args` when the flag is parsed, and `tests/setup_env/unit.bats:740-742`
already does `export DRY_RUN=1` … `unset DRY_RUN`.

Cases: for each of the eight functions, a DRY_RUN case asserting the destructive command did
not run, and its positive control. Plus one case pinning the `chsh` behaviour specifically —
that under `DRY_RUN` the function returns 0 and does **not** emit
`Changed default shell`, which is the assertion that would have caught the short-circuit
bug described above.

## Verification

Runnable today and currently **failing**, which is what makes it a gate rather than a
prediction:

```bash
before=$(git -C ~/.local/share/state-ledger rev-list --count HEAD)
setup_env.sh -t update --dry-run
after=$(git -C ~/.local/share/state-ledger rev-list --count HEAD)
[ "${before}" = "${after}" ]
```

Plus: `rsync`, `pyenv virtualenv-delete` and `git push` appear in the output only on
`[DRY RUN]` lines.

This must be run on a machine where the `-t update` path is exercised. It cannot be run as
part of `make test`, because it performs a real update when the gate fails — which is the
condition it is testing for. It is an operator check, run once after implementation.

## Documentation

`CLAUDE.md:92` changes from "log mutating operations (symlinks, installs, mkdir) without
executing" to a statement of what is actually guaranteed: **no irreversible operations** —
nothing that leaves the machine and nothing that destroys state the remote cannot reproduce
— while idempotent local work (`mkdir -p`, `git pull`) still runs so the preview is useful.
The gated set is named.

## ADR

Not warranted. This is a defect repair restoring a documented contract, not an architectural
choice — the alternatives were weighed and recorded here, and no structural pattern changes.

## Known limitations

- **`--dry-run` remains a partial guarantee.** 224 mutating lines stay ungated by design.
  A future destructive line added outside the ten gated sites is not covered, which is the
  same mechanism that produced the current 5-of-234 state. The rule in §1 is the only thing
  preventing recurrence, and it is prose, not a gate.
- **Nothing detects drift.** No test asserts that the set of destructive verbs in the repo
  is a subset of the gated set, so a new `rsync --delete` or `git push` elsewhere would be
  silently ungated. A ratchet of that shape is possible — `scripts/check-lib-exit-traps.sh`
  is an existing precedent for a scanner ratchet in this repo — and is deliberately left out
  of this spec to keep it to one change. Recorded as a backlog candidate rather than
  designed here.
- The verification gate is an operator check, not a CI gate, for the reason given above.

## Multi-Lens Review

Reviewed at commit: `20a83d77` (Step 7 self-review commit, before Step 8 dispatch)

All three lenses returned blocking findings and converged on the same root cause: the scope
table was populated by a **destructive-verb classifier** while §1's rule is a **purpose**
test. Egress hides behind a binary invocation (`| "${_ledger_bin}" write`), a function named
"sync", and `npm install -g` — none of which contain a destructive verb. Every finding below
was independently re-verified against the code by the session before being recorded here.

### Goal-Fit

Finding: **The ten gated sites do not include the operation the spec measured.** The push
that produced `6311ec1` runs `run_setup_user` (`workflows.sh:227`) →
`_ledger_write_run_entry` (`update_summary.sh:389`) → `ledger_write_entry`
(`workflows.sh:943`) → `| "${_ledger_bin}" write` → `ledger.py:486` `_git_commit_and_push` →
`git commit` (`:334`), `git pull --rebase` (`:342`), `git push` (`:344`), all `check=True`
and unconditional. A second uncovered egress is `git_sync.sh:71`
(`git -C "${_path}" push --quiet`), which has `DRY_RUN` and `run_cmd` counts of 0. The
session's own egress sweep found a third class: five `npm install -g` calls
(`workflows.sh:279,282,285,288,456`). So the design closes **0%** of the measured harm.
Worse, three of the four line-wrap sites are **delete-recreate pairs** where gating only the
delete leaves the recreate running against undeleted state: `_install_go_from_tarball`
(`sudo mv` nests into `/usr/local/go/go`, corrupting a live install that today's ungated path
replaces cleanly), `setup_ai_config` (`git clone` into a still-present dir fails, and
`|| return 1` aborts the whole preview), and `setup_ansible` (ungated `pyenv virtualenv` +
`uv_sync_venv`, the one mutation `CLAUDE.md:274` documents as not reproducible from the
lock). The Verification gate is therefore unsatisfiable: it counts state-ledger commits moved
by ungated writes, so it fails after a perfect implementation of all ten sites.
Assumption: that the new suite can drive `DRY_RUN` without routing through `process_args`,
since `readonly` inside a bash function is global and would make every later positive control
run in dry-run mode and pass vacuously. **Checked and refuted** — bash does behave that way
(`unset` rc=1, reassignment dies `readonly variable`), but bats isolates it per `@test`: a
two-case fixture where case 1 sets `readonly DRY_RUN=1` and case 2 unsets and reassigns
returns 2/2 ok with no leak. The positive-control pairing is safe as designed.
Disposition:

### Ergonomics

Finding: **The guard's `return 0` is durable and remote, not merely returned.** A guarded
`sync_legacy_dirs` reaches `_update_record_end "legacy-rsync" 0`, whose `*)` arm sets
`_result="updated"` and writes `OK` — so `-t update --dry-run` prints
`[OK] legacy-rsync  updated` for a section that synced nothing. `_update_skip` already exists
as the correct primitive and the spec never mentions it. Worse, `run_recreate_venv`
(`workflows.sh:300-305`) calls `recreate_python_venv || return 1` and then
`_ledger_write_run_entry "recreate_venv" 0`: a guard returning 0 means `|| return 1` never
fires, so the design **writes a false CMDB record** asserting a venv recreate that never
happened. Same shape at `:227`, `:253`, `:297`, `:310`. Separately, the operator cannot tell
from the output what was gated — `run_cmd` sites print `[DRY RUN]`, function guards print
nothing, and the `chsh` site deliberately suppresses its log, so a guarded `sync_legacy_dirs`
on the Studio is silent where three `rsync --delete` would have been.
Assumption: that the ten-site table is the complete set of irreversible operations reachable
from a `-t` workflow, when the instrument behind it is a verb matcher and "leaves the
machine" is not a verb. **Checked and confirmed false** by the session's egress sweep, which
found the ledger write, `git_sync.sh:71`, and five `npm install -g` sites.
Disposition:

### Risk

Finding: **The rejected alternative is already half-shipped, which invalidates the Decision
section's cost comparison.** `README.md:207` already reads "Honoured by symlinking
(`lib/helpers.sh`) and the git-hooks sweep only — `run_update` contains no `run_cmd` call
sites, so `-t update --dry-run` still performs real package upgrades, `git push`, and
`rsync --delete`. Do not rely on it to preview an update." Only `CLAUDE.md:92` is stale, so
"narrow the promise" is one line of remaining work rather than a fresh decision. Two further
factual errors: the spec's "nothing widened it since" is false — `5142258c` (#189) widened
`run_cmd` into `git_hooks.sh` and that widening **did** carry `DRY_RUN` awareness (four
references), so the evidence cuts against the spec's own prose-rule argument; and the table
called "exact" omits `rbenv uninstall -f "${RUBY_VER}"` (`developer.sh:429`). Also:
`DRY_RUN=0`, `DRY_RUN=false` and `DRY_RUN=no` all take the dry-run branch (only empty/unset
executes), so after this change an accidental export silently converts `-t update` into a
no-op for three rsync targets instead of costing seven printed lines. And the borrowed
marker-file idiom does not transfer: `git_hooks.bats:1269` works because the fixture owns a
Makefile that writes the marker; `rsync`, `chsh`, `pyenv virtualenv-delete` and `rm -rf` have
no test-owned recipe, so interception must be PATH mocks — and the mandated positive controls,
run unmocked on the Studio, would fire real `rsync -ar --delete` at three hosts and a real
`chsh`.
Assumption: that the criterion "destroys state the remote cannot reproduce" excludes
package-manager state. `CLAUDE.md:274` argues the opposite for `uv sync` — pre-sync state is
not reproducible from the lock and `uv pip install -r` of the freeze "fails as
unsatisfiable" — which would put `uv_sync_venv` in the table and leave `-t update --dry-run`
unsafe regardless. Genuinely open; the operator decides whether a package-manager mutation
meets the criterion.
Disposition:

### Adversarial Spec Review (comparison/judge designs only)

N/A — spec has no comparison, evaluator, or ambiguous-criteria trigger; acceptance is a
concrete command with a measurable result.
