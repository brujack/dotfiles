# `--dry-run` gates egress

**Filename note:** this file is `…-dry-run-irreversible-gating-design.md`, from round 1 when
the scope was "irreversible operations". Round 2 narrowed that to egress. The path is kept
because the round-1 commits, the All Plans index row and the Step 8 review all reference it;
the title states the current scope.

**Date:** 2026-09-14
**Status:** Design — revised after Step 8 round 1, pending re-review

> **Round 2 rewrite.** Round 1 proposed gating ten sites selected by a destructive-verb
> classifier. All three lenses blocked it: the ten sites closed **none** of the harm the
> problem statement measured, and three of them made `--dry-run` worse than doing nothing.
> The scope below is re-derived from the rule instead of from the classifier. The round-1
> review is preserved verbatim at the bottom — it is the record of why this document changed,
> not a description of the design above it.

## Problem

`--dry-run` is documented in `CLAUDE.md:92` as "log mutating operations (symlinks, installs,
mkdir) without executing". It does not do that. It pushes to a GitHub remote.

Measured on the **Studio**, 2026-09-14, one run of `setup_env.sh -t setup_user --dry-run`:

```
[DRY RUN] lines emitted                 7  of 90 output lines
real git pull into ai-config            3000d538..754bdffc, 4 files, 117 insertions
real commit + push to state-ledger      e76d0d9..6311ec1  main -> main
```

Verified independently of the run's own output: commit `6311ec1` is present in state-ledger
and `git rev-list --count origin/main..HEAD` reads 0, so it reached the remote. One run, one
machine.

The full chain, traced: `run_setup_user` (`workflows.sh:227`) → `_ledger_write_run_entry`
(`update_summary.sh:389`) → `ledger_write_entry` (`workflows.sh:943`) →
`| "${_ledger_bin}" write` (`:954`) → `ledger.py:486` `_git_commit_and_push` → `git commit`
(`:334`), `git pull --rebase` (`:342`), `git push` (`:344`) — all `check=True`, all
unconditional.

**Not** evidence of harm, recorded so the problem is not inflated: the
`Created /Users/bruce/.tf_creds`-style lines. All seven such directories carry birth dates
from 2022 or 2026-01, so `mkdir -p` no-op'd and the log line prints unconditionally.

### Where it comes from

`specs/2026-04-08-doctor-dry-run-design.md:18` calls `run_cmd` "a thin wrapper used by all
mutating helpers". Its plan wired one caller, `safe_link`.

An earlier draft of this spec said "nothing widened it since". **That is false**, and the
correction matters because it cuts against the argument it was supporting: `5142258c`
(#189, 2026-07-29) widened `run_cmd` into `lib/git_hooks.sh`, and that widening **did** carry
`DRY_RUN` awareness (`git_hooks.sh:386,401,443,538`). So the mechanism has been extended
correctly once already; the gap is coverage, not a broken practice.

Static counts, 2026-09-14, over `setup_env.sh` + `lib/*.sh` + `scripts/*.sh`:

```
run_cmd call sites             5      (helpers.sh:50,54,56,59 in safe_link; git_hooks.sh:459)
DRY_RUN occurrences            6      of which 3 are non-comment: 2 reads + 1 assignment
                                      (git_hooks.sh:386, helpers.sh:16; helpers.sh:818 sets it)
```

An earlier draft reported "6 read sites", counting three comment lines. That erred toward
making the status quo look better and is corrected here.

### Why the first attempt missed it

Round 1 populated its scope table with a **destructive-verb classifier** (`rm -rf`,
`rsync --delete`, `virtualenv-delete`, `chsh`) while the decision rule is a **purpose** test.
Egress does not contain a destructive verb: it hides behind a binary invocation
(`| "${_ledger_bin}" write`), a function named `sync`, and `npm install -g`. The instrument
was structurally incapable of finding the thing the problem statement measured. Scope below
is derived by asking what leaves the machine, then checked against the verb list — not the
reverse.

## Decision

**Gate egress: the operations that leave this machine.** Three sites.

This is deliberately narrower than round 1's ten. It closes 100% of the measured harm; round
1's table closed 0% of it.

**The "narrow the promise" alternative is already half-shipped**, which round 1 got wrong.
`README.md:207` reads: "`--dry-run` — log mutating operations without executing. **Honoured by
symlinking (`lib/helpers.sh`) and the git-hooks sweep only** — `run_update` contains no
`run_cmd` call sites, so `-t update --dry-run` still performs real package upgrades,
`git push`, and `rsync --delete`. Do not rely on it to preview an update." Only `CLAUDE.md:92`
is stale. So that alternative is one line of remaining work, not a fresh decision — and this
spec does that line too, regardless.

What it does not do: make `--dry-run` a no-op. Package upgrades, venv rebuilds and local
deletions still run. The documentation says so.

## Scope

| site                                      | operation                                   | guard    |
| ----------------------------------------- | ------------------------------------------- | -------- |
| `ledger_write_entry` (`workflows.sh:943`) | `\| "${_ledger_bin}" write` → commit + push | function |
| `_git_sync_one_repo` (`git_sync.sh:71`)   | `git -C "${_path}" push --quiet`            | line     |
| `sync_legacy_dirs` (`legacy_rsync.sh:8`)  | 3 × `rsync -ar --delete` to remote hosts    | function |

**`ledger_write_entry` is the sole chokepoint for every ledger write.** All six
`_ledger_write_run_entry` call sites (`workflows.sh:227,253,297,304,310` and
`update_summary.sh:598` via `_ledger_write_dotfiles_entry`) funnel through
`update_summary.sh:521/523` into it. One guard covers all of them, including the
`_update_summary` write that fires at the end of every `run_update`. Every caller invokes it
as `|| true`, so returning 0 is safe and misleads nothing.

**`git_sync.sh:71` takes a line guard, not a function guard, and the distinction is the
rule.** `_git_sync_one_repo` has exactly two mutations: the push at `:71` and
`git pull --ff-only --quiet` at `:82`. Its purpose is _sync_, not _push_ — the pull is neither
egress nor irreversible (fast-forward only, refused on a dirty tree at `:78-80`). Guarding the
function would suppress a preview of the pull for no benefit. `sync_git_repos` (`:97`) routes
both the personal repos and `~/.local/share/state-ledger` (`:108-112`) through this same
function, so the one line guard covers both.

**`sync_legacy_dirs` takes a function guard** because the whole function is the rsync push.

### The rule

> Guard the function where its purpose **is** the egress. Guard the line where egress is one
> branch of a function that does other useful work.

Round 1 used a superficially similar rule to justify wrapping single lines inside
delete-recreate pairs. That produced three regressions and is **not** what this says: no site
in this scope has a recreate step following it.

### Out of scope, with reasons

These were in round 1's table and are removed, because none of them leaves the machine:

`setup_ansible`, `recreate_python_venv`, `recreate_ruby`, `_install_go_from_tarball`,
`setup_ai_config`, `ensure_state_ledger`, `setup_zsh_as_default_shell` (`chsh`), and
`rbenv uninstall -f` (`developer.sh:429`, which round 1's "exact" table omitted anyway).

Three of them were actively dangerous to gate, because gating the delete leaves the recreate
running against undeleted state — measured by two lenses independently:

- `_install_go_from_tarball`: gating `sudo rm -rf /usr/local/go` (`:89`) leaves
  `sudo mv .../go /usr/local/go` (`:91`), and `mv` of a directory onto an existing directory
  nests it, yielding `/usr/local/go/go`. A dry run would corrupt a live Go install that a real
  run replaces cleanly.
- `setup_ai_config`: gating `rm -rf "${_dir}"` (`:107`) leaves
  `git clone … "${_dir}" || return 1` (`:109`), which fails into a non-empty directory and
  aborts the whole preview through `run_setup_user`'s `|| return 1`.
- `setup_ansible`: gating `pyenv virtualenv-delete -f ansible` (`:530`) leaves
  `pyenv virtualenv` (`:531`) and `uv_sync_venv` (`:536`) live — and `CLAUDE.md:274` documents
  `uv sync` as pruning and downgrading to a state "not reproducible from the lock".

Also out of scope: `npm install -g` (`workflows.sh:279,282,285,288,456`) and `uv_sync_venv`.
Both fetch from a registry, so both arguably meet a wider reading of the criterion. See Known
limitations.

## Design

### 1. Guard shape

Function guards return **0**, early, after any logging. The zero is load-bearing: callers
invoke these as `fn || return 1` or `|| true`, so a non-zero guard would report a preview as a
failed run.

### 2. A guard must not be recorded as success

Round 1's guards returned 0 into machinery that writes that 0 down. Two consequences, both
measured:

- `sync_legacy_dirs` returning 0 reaches `_update_record_end "legacy-rsync" 0`
  (`workflows.sh:606`), whose `*)` arm sets `_result="updated"` and writes `OK` — printing
  `[OK] legacy-rsync  updated` for a section that synced nothing.
- `recreate_python_venv` returning 0 means `run_recreate_venv`'s `|| return 1`
  (`workflows.sh:303`) never fires, so `_ledger_write_run_entry "recreate_venv" 0` writes a
  **false CMDB record** for a rebuild that did not happen.

The second is fixed structurally by this scope: `ledger_write_entry` is itself guarded, so no
ledger record is written under `--dry-run` at all.

The first is fixed by rendering a SKIP. `_update_record_start` already has the precedent —
its `legacy-rsync)` arm calls `_update_skip "legacy-rsync" "not studio"`
(`update_summary.sh:152-153`). Under `DRY_RUN`, the `legacy-rsync` and `git-repos` arms call
`_update_skip "<section>" "dry run"`.

### 3. Every gated site announces itself

All three guards print `[DRY RUN] <what would have run>` on the same channel `run_cmd` uses,
so a transcript can be grepped for what was prevented. Round 1's function guards printed
nothing, which on the Studio meant silence where three `rsync --delete` would have been.

### 4. Standalone entry point

`scripts/sync_git_repos.sh` dispatches both `sync_git_repos` (`:60`) and `sync_legacy_dirs`
(`:63`), and both are now gated — so a `--dry-run` flag added to its own arg loop is honoured
by everything the script does. Round 1 proposed this flag while gating only one of the two,
which would have advertised a preview that still pushed.

### 5. A seam for the ledger binary

`ledger_write_entry` resolves `command -v ledger`, falling back to `${HOME}/.local/bin/ledger`
(`workflows.sh:946-948`). There is **no override**, and `tests/mocks/ledger` does not exist.
Existing tests avoid the real binary by stubbing the _caller_ (`workflows.bats:358` redefines
`_ledger_write_run_entry`) or by the machine-id early return (`update_summary.sh:394-395`).
Neither can test this guard: stubbing the caller bypasses it.

Add `LEDGER_BIN` as the first candidate, matching the `UV_BIN` pattern already documented in
`CLAUDE.md`. It grants nothing — a caller who can set it can already put a `ledger` on `PATH`.

## Testing

**The marker-file idiom does not transfer, and round 1 was wrong to name it.**
`git_hooks.bats:1269` works because the fixture owns a Makefile that writes the marker.
`rsync`, `git push` and `ledger write` have no test-owned recipe. Interception is by PATH
mock: `tests/mocks/rsync` and `tests/mocks/git` exist; `tests/mocks/ledger` must be added
alongside the `LEDGER_BIN` seam.

**Positive controls must be mocked, not live.** Each DRY_RUN case asserting "the mock was not
called" is paired with a control asserting it **was** called — otherwise the absence passes
vacuously when the fixture never ran. Round 1 mandated the pairing without saying what the
control runs against; unmocked on the Studio it would fire real `rsync -ar --delete` at three
hosts, since `hostname -s` is `studio` and `_is_legacy_sync_host` passes. Every control runs
against the PATH mock with `HOME` redirected to `BATS_TEST_TMPDIR` at `setup()` scope. Note
`tests/mocks/rm` passes through to `/bin/rm`, so an unredirected `HOME` really deletes.

Eight cases — three gated sites with a paired positive control each, plus two that pin
behaviour a future change is likely to break:

| case                                             | asserts                                                 |
| ------------------------------------------------ | ------------------------------------------------------- |
| `ledger_write_entry` under DRY_RUN               | `LEDGER_BIN` mock never invoked                         |
| `ledger_write_entry` control                     | mock invoked, receives the JSON on stdin                |
| `_git_sync_one_repo` ahead-branch under DRY_RUN  | git mock records no `push`                              |
| `_git_sync_one_repo` ahead-branch control        | git mock records `push`                                 |
| `sync_legacy_dirs` under DRY_RUN                 | rsync mock never invoked                                |
| `sync_legacy_dirs` control                       | rsync mock invoked 3×                                   |
| `_git_sync_one_repo` behind-branch under DRY_RUN | `pull --ff-only` **still runs** — the pull is not gated |
| `run_update` section rendering under DRY_RUN     | `[SKIP] legacy-rsync  dry run`, never `[OK] … updated`  |

The seventh is the one that fails if a future change over-widens the guard from the line to
the function, which is the likeliest regression.

`readonly DRY_RUN` does not threaten the controls. `readonly` inside a bash function is global
and sticks (`unset` returns 1; reassignment dies with `readonly variable`), but bats isolates
it per `@test` — verified with a two-case fixture where case 1 sets `readonly DRY_RUN=1` and
case 2 unsets and reassigns: 2/2 ok, no leak.

## Verification

Round 1's gate counted state-ledger commits under `-t update --dry-run`. It was
**unsatisfiable** — the count moved via the ungated ledger write, so it would have failed
after a perfect implementation — and running it performs a real update. Replaced.

The cheap gate, which exercises two of the three guards with no package upgrades:

```bash
before=$(git -C ~/.local/share/state-ledger rev-list --count HEAD)
scripts/sync_git_repos.sh --dry-run
after=$(git -C ~/.local/share/state-ledger rev-list --count HEAD)
[ "${before}" = "${after}" ]
```

Expect the run to print `[DRY RUN]` lines for the three rsync targets and for any repo that is
ahead, and to leave the count unchanged. This is runnable today and currently fails, because
the flag does not exist and the pushes are real.

The third guard is covered by the suite rather than by an operator check, since exercising
`ledger_write_entry` end-to-end requires a real ledger write.

## Documentation

`CLAUDE.md:92` changes to state what is guaranteed — **no egress**: nothing leaves this
machine. Package upgrades, venv rebuilds and local deletions still run, and the line says so,
matching `README.md:207` rather than contradicting it.

## ADR

Not warranted. A defect repair restoring a documented contract; no structural pattern changes.

## Known limitations

- **`--dry-run` is not a no-op and the docs must keep saying so.** Only egress is gated.
- **Registry fetches are unresolved, deliberately.** `npm install -g` (5 sites) and
  `uv_sync_venv` fetch from a registry and mutate global state. `uv sync` in particular is
  documented at `CLAUDE.md:274` as producing a state "not reproducible from the lock" — which
  meets the _second_ clause of a wider criterion ("destroys state the remote cannot
  reproduce") even though it is not egress in the sense used here. Deciding that is a separate
  question with its own blast radius; it goes to the backlog with these measurements rather
  than being settled inside a defect repair.
- **Delete-recreate pairs stay ungated.** Gating them requires guarding whole functions, which
  changes what a preview reports. Backlog.
- **Nothing detects drift.** No test asserts that the set of egress points is a subset of the
  gated set, so a new `git push` elsewhere is silently ungated — the same mechanism that
  produced this defect. `scripts/check-lib-exit-traps.sh` is an in-repo precedent for a scanner
  ratchet. Backlog, deliberately out of this change.

---

## Multi-Lens Review

Reviewed at commit: `20a83d77` (round 1 — the ten-site verb-derived design, now superseded)

All three lenses returned blocking findings and converged on the same root cause: the scope
table was populated by a **destructive-verb classifier** while the design's rule is a
**purpose** test. Every finding below was independently re-verified against the code by the
session before being recorded.

### Goal-Fit

Finding: **The ten gated sites did not include the operation the spec measured.** The push
came via `run_setup_user` → `_ledger_write_run_entry` → `ledger_write_entry` →
`ledger.py:486` `_git_commit_and_push` → `git push` (`:344`), all unconditional. A second
uncovered egress was `git_sync.sh:71` (`DRY_RUN` and `run_cmd` counts both 0 in that file),
and the session's own egress sweep found a third class, five `npm install -g` calls. The
design closed **0%** of the measured harm. Three of four line-wrap sites were
delete-recreate pairs where gating only the delete left the recreate running against
undeleted state — `/usr/local/go/go` nesting, an aborted preview, and a live `uv sync`. The
verification gate was unsatisfiable, counting commits moved by ungated writes.
Assumption: that the suite could drive `DRY_RUN` without routing through `process_args`,
since `readonly` inside a bash function is global. **Checked and refuted** — bash does behave
that way, but bats isolates it per `@test` (2/2 ok, no leak). The pairing is safe.
Disposition: **Addressed.** Scope re-derived from egress rather than from the verb
classifier; `ledger_write_entry` and `git_sync.sh:71` are now the first two gated sites. All
four line-wrap sites removed, eliminating every delete-recreate regression. Verification gate
replaced with a `sync_git_repos.sh --dry-run` check that exercises two guards without a real
update. The refuted assumption is recorded in Testing so it is not re-litigated.

### Ergonomics

Finding: **The guard's `return 0` was durable and remote, not merely returned.** A guarded
`sync_legacy_dirs` reached `_update_record_end … 0`, printing `[OK] legacy-rsync  updated`
for a section that synced nothing, with `_update_skip` already available and unused. Worse,
`run_recreate_venv` would have written a **false CMDB record** asserting a venv recreate that
never happened. Separately, an operator could not tell from the output what was gated —
function guards printed nothing.
Assumption: that the ten-site table was the complete set of irreversible operations reachable
from a `-t` workflow, when the instrument was a verb matcher and "leaves the machine" is not
a verb. **Checked and confirmed false** by the session's egress sweep.
Disposition: **Addressed.** §2 requires SKIP rendering via the existing
`_update_record_start` precedent; the false-record class is removed structurally, because
`ledger_write_entry` is itself gated so no record is written under `--dry-run`. §3 requires
every gated site to print `[DRY RUN]`, ending the silent-guard case.

### Risk

Finding: **The rejected alternative was already half-shipped.** `README.md:207` already
narrows the promise; only `CLAUDE.md:92` is stale, so "narrow the docs" was one line of
remaining work rather than a fresh decision, which invalidated the Decision section's cost
comparison. Two further factual errors: "nothing widened it since" is false — `5142258c`
(#189) widened `run_cmd` into `git_hooks.sh` **with** `DRY_RUN` awareness, so the evidence cut
against the spec's own argument — and the table called "exact" omitted `rbenv uninstall -f`
(`developer.sh:429`). Also: `DRY_RUN=0`, `false` and `no` all take the dry-run branch, so an
accidental export would silently no-op three rsync targets. And the marker-file idiom does not
transfer, while the mandated positive controls run unmocked would fire real `rsync --delete`
and `chsh`.
Assumption: that "destroys state the remote cannot reproduce" excludes package-manager state,
when `CLAUDE.md:274` argues the opposite for `uv sync`. Genuinely open.
Disposition: **Addressed**, with the assumption deferred rather than resolved. README
correction and both factual errors are fixed in the body above. Testing now specifies PATH
mocks with `HOME` redirected at `setup()` scope. The package-manager question is recorded as
the first Known limitation and goes to the backlog with its measurements — this spec is a
defect repair and settling that boundary belongs in its own change.

### Adversarial Spec Review (comparison/judge designs only)

N/A — no comparison, evaluator, or ambiguous-criteria trigger; acceptance is a concrete
command with a measurable result.
