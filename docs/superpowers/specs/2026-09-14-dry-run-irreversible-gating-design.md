# `--dry-run` gates outbound writes

**Filename note:** this file is `…-dry-run-irreversible-gating-design.md`, from round 1 when
the scope was "irreversible operations". Round 2 narrowed that to outbound writes. The path is kept
because the round-1 commits, the All Plans index row and the Step 8 review all reference it;
the title states the current scope.

**Date:** 2026-09-14
**Status:** Design — revised after Step 8 round 2; operator dispositioned all findings
Addressed and ruled to stop review here, so the next step is `writing-plans`

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

**Gate outbound writes: the operations that write to another machine.** Three sites.

This is deliberately narrower than round 1's ten. It closes 100% of the measured harm; round
1's table closed 0% of it.

**The "narrow the promise" alternative is already half-shipped**, which round 1 got wrong.
`README.md:207` reads: "`--dry-run` — log mutating operations without executing. **Honoured by
symlinking (`lib/helpers.sh`) and the git-hooks sweep only** — `run_update` contains no
`run_cmd` call sites, so `-t update --dry-run` still performs real package upgrades,
`git push`, and `rsync --delete`. Do not rely on it to preview an update." Only `CLAUDE.md:92`
is stale. So that alternative is one line of remaining work, not a fresh decision — and this
spec does that line too, regardless.

**That fact inverts the comparison, and correcting it is not the same as re-running it.** An
earlier draft fixed the README claim and left the arithmetic built on the old cost. Re-run
properly, the choice is: **one line** (correct `CLAUDE.md:92`, ship nothing) against **three
guards plus a seam, a mock, a truthiness fix and eight cases**. The cheap option is not
merely cheaper — it is already 90% delivered.

The case for building anyway is that the two options are not substitutes. Documenting the
flag as unsafe leaves `-t update` and `-t developer` unrunnable without accepting live
`rsync --delete` to three hosts and a push per repo — which is how this session ended up
unable to answer a direct question about whether those workflows work, and had to refuse to
run them. The guards buy back a preview of exactly the two workflows that most need one. If
that is not worth three guards, the honest outcome is to ship the one-line doc fix and
backlog the rest — and this spec should be retired rather than narrowed a third time.

What it does not do: make `--dry-run` a no-op. Package upgrades, venv rebuilds, `git fetch`
and `pull --ff-only` on every personal repo, five `npm install -g` and `uv sync` all still
run. The documentation enumerates them rather than gesturing at "local work", following
`README.md:207`'s model — and `CLAUDE.md:86` ("Also writes a state-ledger entry") needs the
same edit, since under `--dry-run` it will no longer be true.

## Scope

| site                                      | operation                                   | guard    |
| ----------------------------------------- | ------------------------------------------- | -------- |
| `ledger_write_entry` (`workflows.sh:943`) | `\| "${_ledger_bin}" write` → commit + push | function |
| `_git_sync_one_repo` (`git_sync.sh:71`)   | `git -C "${_path}" push --quiet`            | line     |
| `sync_legacy_dirs` (`legacy_rsync.sh:8`)  | 3 × `rsync -ar --delete` to remote hosts    | function |

**`ledger_write_entry` is the sole chokepoint for ledger EGRESS.** All six
`_ledger_write_run_entry` call sites (`workflows.sh:227,253,297,304,310` and
`update_summary.sh:598` via `_ledger_write_dotfiles_entry`) funnel through
`update_summary.sh:521/523` into it. One guard covers all of them, including the
`_update_summary` write that fires at the end of every `run_update`.

Two precision corrections, both measured, because earlier drafts overstated this:

- **"every ledger write" is too wide; "outbound write" is what is true.** `ensure_state_ledger` runs
  `ledger.py init` (`workflows.sh:937`) and `run_update` runs `scan_skills.py --write-ledger`
  (`:415`) outside this function. Neither pushes — `cmd_init` spans `ledger.py:372-436` and
  contains no path to `_git_commit_and_push` or `_flush_spool_internal`, and
  `scan_skills.py` writes `~/.claude/plugin-verdicts.json`, a local file. So the design is
  unaffected and no fourth guard is needed, but the sentence had to narrow.
- **"Every caller invokes it as `|| true`" is false for the two direct callers.**
  `update_summary.sh:521` and `:523` are bare. The conclusion survives — both sit inside
  `_ledger_write_run_entry`, whose five callers do use `|| true`, and
  `_ledger_write_dotfiles_entry` is called `|| true` at `:598` — so returning 0 is still
  safe. The evidence was wrong, not the claim.

**`git_sync.sh:71` takes a line guard, not a function guard, and the distinction is the
rule.** `_git_sync_one_repo` has exactly two mutations: the push at `:71` and
`git pull --ff-only --quiet` at `:82`. Its purpose is _sync_, not _push_ — the pull is neither
an outbound write nor irreversible (fast-forward only, refused on a dirty tree at `:78-80`). It
does reach the remote, so it is egress; that is precisely why the guarantee is scoped to writes
rather than to egress. Guarding the
function would suppress a preview of the pull for no benefit. `sync_git_repos` (`:97`) routes
both the personal repos and `~/.local/share/state-ledger` (`:108-112`) through this same
function, so the one line guard covers both.

**`sync_legacy_dirs` takes a function guard** because the whole function is the rsync push.

### The rule

> Guard the function where its purpose **is** the outbound write. Guard the line where the
> outbound write is one branch of a function that does other useful work.

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

The first is fixed by rendering a SKIP — **for `legacy-rsync` only**.
`_update_record_start` already has the precedent: its `legacy-rsync)` arm calls
`_update_skip "legacy-rsync" "not studio"` (`update_summary.sh:152-153`). Under `DRY_RUN`
that arm calls `_update_skip "legacy-rsync" "dry run"` instead.

**`git-repos` deliberately does NOT get a SKIP, and the reason is the guard's granularity.**
That section is line-gated: `_git_repo_status` still runs `git fetch` against every repo
(`git_sync.sh:22`) and `pull --ff-only` still runs on every repo that is behind (`:82`).
Printing `[SKIP] git-repos  dry run` would deny that working trees moved, in the only durable
record of the run — replacing round 1's false `[OK]` with an equally false `[SKIP]`. A
section whose guard covers one line of several cannot be rendered as wholly skipped.
`_update_record_start` has fourteen arms and no `git-repos` arm at all, so there is nothing
to add there.

Two consequences follow and are accepted. `git-repos` renders `[OK]` with its ordinary
result, which is truthful — the fetches and pulls really happened, only the pushes were
suppressed. And a diverged repo still returns rc 2, so `_update_warn` overwrites status
unconditionally; that is pre-existing behaviour and this change does not alter it.

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
Unprefixed rather than `_OVERRIDE_*` is deliberate: `UV_BIN` and `GGSHIELD_BIN` are the
precedent for an operator escape hatch that doubles as a test seam, and this is that shape.

**The seam is load-bearing, not a convenience, and the reason is the resolution order.**
`command -v ledger` is checked _before_ the `${HOME}`-relative fallback, so redirecting `HOME`
in a test does not intercept the binary on any machine where `ledger` is on `PATH` — which is
the Linux boxes. Without `LEDGER_BIN` plus `tests/mocks/ledger`, the guard's test would hit
the real ledger. Add a row for it to `CLAUDE.md`'s Test Seams table in the same change; every
sibling seam is documented there and a Definition of Done item covers it.

### 6. `DRY_RUN` must mean what it looks like

`helpers.sh:16` is `[[ -n ${DRY_RUN:-} ]]`, so `DRY_RUN=0`, `DRY_RUN=false` and `DRY_RUN=no`
all take the dry-run branch — only unset or empty executes. `process_args` compounds it:
`[[ -n "${DRY_RUN+x}" ]] || readonly DRY_RUN=1` (`helpers.sh:818`) _preserves_ an inherited
value rather than overwriting it.

Today that costs a few printed symlink lines. After this change a stray `DRY_RUN=0` in the
environment silently suppresses every push, every `rsync --delete` and every ledger write on a
run nobody asked to be a preview — and it reports success, because `ledger_write_entry`'s two
direct callers are bare and `_ledger_write_run_entry` is invoked `|| true`. The thing that
notices is `ledger drift`, a week later, blaming the machine.

So `run_cmd` and the guards test a normalised value: unset, empty, `0`, `false` and `no` all
mean off; anything else means on. One helper, `_dry_run_active`, used by `run_cmd` and all
three guards so the four sites cannot drift apart.

**This was raised by round 1's Risk lens, marked "Addressed", and not done** — the disposition
listed the README fix and the PATH mocks and silently omitted this. It is recorded here
because a false disposition in a review record is worse than an open finding: the record is
what a later reader trusts once the code is forgotten.

## Testing

**The marker-file idiom does not transfer, and round 1 was wrong to name it.**
`git_hooks.bats:1269` works because the fixture owns a Makefile that writes the marker.
`rsync`, `git push` and `ledger write` have no test-owned recipe. Interception is by PATH
mock: `tests/mocks/rsync` and `tests/mocks/git` exist; `tests/mocks/ledger` must be added
alongside the `LEDGER_BIN` seam.

**The safety mechanism is `load_mocks` plus a source override — NOT `HOME`.** An earlier draft
said every control runs "with `HOME` redirected to `BATS_TEST_TMPDIR`", which names the wrong
thing. `HOME` feeds only the rsync _source_ (`legacy_rsync.sh:15`); the three destinations are
hardcoded `bruce@workstation:`, `bruce@laptop-1:` and `bruce@ratna:`. An empty `HOME` with a
real `rsync` reachable is **worse** than none — `rsync -ar --delete <empty>/ bruce@ratna:…`
empties the target. What actually protects the existing suite is `load_mocks` plus
`_OVERRIDE_GIT_REPOS_SRC` plus `MOCK_HOSTNAME_OUTPUT` (`legacy_rsync.bats:6,11,16`), and that
is what these cases use.

**Every absence case asserts the announcement, not only the absence.** A case that asserts
"the mock was not called" passes when the fixture never reached the guard at all. §3 mandates
a `[DRY RUN] <command>` line, so each absence case additionally asserts that line is present
— a positive claim about a derived value, which an unreached guard cannot satisfy. That is
also what gives §3 test coverage; without it the entire remedy for round 1's
"operator cannot tell what was gated" ships untested.

**A rule this repo does not yet have, introduced here rather than cited.** A test whose safety
depends on a mock being resolved must verify the mock is live before the dangerous call.
Measured: there is no such precedent — `refute_grep` asserts absence, and `load_mocks` only
prepends `tests/mocks` to `PATH` without checking anything resolves. It matters most for the
ledger, per §5's resolution order.

**`tests/setup_env/git_sync.bats` cannot simply take `load_mocks`.** That file deliberately
uses none: its `setup()` builds a real bare origin with real `git init`, `clone`, `commit` and
`push`. Adding the git mock would shadow the git the fixture is made of and collapse the file
— the PATH-mock-shadowing pitfall `shell.md` documents. Cases 3, 4 and 7 therefore intercept
by asserting on the real fixture's refs (did `origin` move?) rather than on a git mock.

Eight cases — three gated sites with a paired positive control each, plus two that pin
behaviour a future change is likely to break:

| case                                             | asserts                                                                               |
| ------------------------------------------------ | ------------------------------------------------------------------------------------- |
| `ledger_write_entry` under DRY_RUN               | `LEDGER_BIN` mock never invoked, **and** `[DRY RUN]` names the suppressed write       |
| `ledger_write_entry` control                     | mock invoked, receives the JSON on stdin                                              |
| `_git_sync_one_repo` ahead-branch under DRY_RUN  | fixture `origin` ref unmoved, **and** `[DRY RUN]` names the push                      |
| `_git_sync_one_repo` ahead-branch control        | fixture `origin` ref advances                                                         |
| `sync_legacy_dirs` under DRY_RUN                 | `MOCK_HOSTNAME_OUTPUT=studio`, rsync mock never invoked, **and** `[DRY RUN]` names it |
| `sync_legacy_dirs` control                       | `MOCK_HOSTNAME_OUTPUT=studio`, rsync mock invoked 3×                                  |
| `_git_sync_one_repo` behind-branch under DRY_RUN | `pull --ff-only` **still runs** — the pull is not gated                               |
| `_update_record_start` under DRY_RUN             | `legacy-rsync` reason is `dry run`; **no** `git-repos` SKIP is written                |

**Case 5 must force `MOCK_HOSTNAME_OUTPUT=studio` and an earlier draft named that only for the
control.** `sync_legacy_dirs` returns at `legacy_rsync.sh:9-12` when `_is_legacy_sync_host` is
false, and `hostname -s` is not `studio` on `ubuntu-latest` or on two of the three dev
machines — so without the knob the rsync mock goes uncalled because of the host gate, not the
guard, and the case passes against zero implementation. Subject and control must differ only
in `DRY_RUN`.

**Case 8 asserts the reason, and must not collide with the existing skip.**
`_update_record_start` already writes `_update_skip "legacy-rsync" "not studio"` on a
non-studio host (`update_summary.sh:152-153`), so the case sets `MOCK_HOSTNAME_OUTPUT=studio`
and asserts the reason is `dry run`. Its second half — that no `git-repos` SKIP is written —
is what pins §2's granularity decision.

The seventh is the one that fails if a future change over-widens the guard from the line to
the function, which is the likeliest regression.

`readonly DRY_RUN` does not threaten the controls. `readonly` inside a bash function is global
and sticks (`unset` returns 1; reassignment dies with `readonly variable`), but bats isolates
it per `@test` — verified with a two-case fixture where case 1 sets `readonly DRY_RUN=1` and
case 2 unsets and reassigns: 2/2 ok, no leak.

## Verification

**Two gates have now been written for this spec and both were invariant to the fix.** Round
1's counted state-ledger commits and could only fail, because the count moved via the ungated
ledger write. Round 2's counted the same thing around `sync_git_repos.sh --dry-run` and could
only pass, because `--dry-run` falls to that script's `*)` arm (`Unrecognized option`,
`return 1`), nothing runs, and `before == after`. It also fails in the other direction once
implemented, because the deliberately ungated `pull --ff-only` moves `rev-list --count HEAD`
on a repo written from three machines, where _behind_ is the normal state.

The fault in both was the oracle, not the command: `rev-list --count HEAD` is a statement
about the **local** repository, and "nothing left this machine" is a statement about the
**remote**. A push moves the remote ref; a pull cannot.

```bash
before=$(git ls-remote ~/.local/share/state-ledger-origin 2>/dev/null || \
         git -C ~/.local/share/state-ledger ls-remote origin main | awk '{print $1}')
scripts/sync_git_repos.sh --dry-run
after=$(git -C ~/.local/share/state-ledger ls-remote origin main | awk '{print $1}')
[ "${before}" = "${after}" ]
```

Expect `[DRY RUN]` lines for the three rsync targets and for any repo that is ahead, and the
`origin/main` SHA unchanged.

**This is NOT runnable today, and saying so is the correction.** Both earlier rounds claimed
"runnable today and currently fails"; both claims were false, and the second was false in the
flattering direction. `scripts/sync_git_repos.sh` does not parse `--dry-run` at all yet —
`tests/scripts/unit.bats:356` already pins that it rejects unknown flags without running
either leg — so the gate becomes meaningful only once §4 ships. Before that, the
pre-implementation evidence is the measured harm in the Problem section, not this command.

The ledger guard is covered by the suite rather than by this check, since exercising
`ledger_write_entry` end-to-end requires a real ledger write.

## Documentation

`CLAUDE.md:92` changes to state what is guaranteed — **no outbound write**: no `git push`, no
`rsync --delete`, no state-ledger **entry** write. Package upgrades, venv rebuilds and local
deletions still run, and the line says so, matching `README.md:207` rather than contradicting
it.

**This paragraph said "no egress: nothing leaves this machine" until Phase 3, and that
directive was false.** `security-review` (LOW-1) measured it: `_git_repo_status` runs
`git fetch` against every personal repo's remote and authenticates with the operator's SSH
key on every dry run, and `npm install -g` and `uv sync` reach registries — all egress. What
the guards actually deliver is no outbound **write**, which is the correct and still-strong
claim. `bug-scan` then narrowed it once more: `ensure_state_ledger` runs ungated and performs
a local `ledger.py init`, so the guarantee is "no state-ledger **entry** write" rather than
"no state-ledger write". Corrected here rather than only in the plan, because this spec is the
artifact the plan's tasks were written from, and leaving the directive intact would have it
mandate the retracted wording to the next reader. The `Disposition` blocks below are records
of what each review round judged and are deliberately **not** rewritten — they say "no egress"
because that is what was true when they were written.

## ADR

Not warranted. A defect repair restoring a documented contract; no structural pattern changes.

## Known limitations

- **`--dry-run` is not a no-op and the docs must keep saying so.** Only outbound writes are gated.
- **Registry fetches are unresolved, deliberately.** `npm install -g` (5 sites) and
  `uv_sync_venv` fetch from a registry and mutate global state. `uv sync` in particular is
  documented at `CLAUDE.md:274` as producing a state "not reproducible from the lock" — which
  meets the _second_ clause of a wider criterion ("destroys state the remote cannot
  reproduce") even though it is not an outbound write in the sense used here. Deciding that is a separate
  question with its own blast radius; it goes to the backlog with these measurements rather
  than being settled inside a defect repair.
- **Delete-recreate pairs stay ungated.** Gating them requires guarding whole functions, which
  changes what a preview reports. Backlog.
- **Nothing detects drift.** No test asserts that the set of outbound-write sites is a subset of the
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

---

## Multi-Lens Review — Round 2

Reviewed at commit: `3124144b` (the three-site egress design above)

All three lenses blocked again. The headline is that **the replacement verification gate is
wrong in both directions** — round 1's gate always failed; this one passes today and fails
after a correct implementation. That is round 1's defect class recurring inside the section
written to retire it, and it is the second acceptance gate in this spec to be invariant to
the fix it is meant to measure.

Every claim below was re-verified against the code by the session. Two lens claims were
**refuted** and are recorded as such rather than carried forward.

### Goal-Fit

Finding: **The gate cannot fail.** `rev-list --count HEAD` moves on _commit_, not on push,
and both guards the gate exercises are push-side. Worse, `sync_git_repos_main`
(`scripts/sync_git_repos.sh:34-56`) parses one `${1:-}` through a `case` whose arms are
`-h|--help`, `--git-only`, `--legacy-only`, `""` and `*)`; `--dry-run` falls to `*)` →
`Unrecognized option` → `return 1`, so nothing runs, `before == after`, and the assertion
passes. The spec's "runnable today and currently fails" is false — it passes trivially, and
`tests/scripts/unit.bats:356` already pins that rejection behaviour. Separately, two of three
absence cases are non-discriminating: `sync_legacy_dirs` returns at `legacy_rsync.sh:9-12`
when `_is_legacy_sync_host` is false, and `tests/mocks/git` has no ahead/behind knob, so
`_git_sync_one_repo` returns 0 at `:87` without reaching the push at `:71`.
Assumption: that a `--dry-run` invocation is a run the CMDB should have **no record of at
all**. Package upgrades, venv rebuilds and pulls really happen under `--dry-run`, and
state-ledger's contract is an append-only record with a spool path so writes are never
silently dropped — so the right shape may be an entry carrying `dry_run: true` rather than
suppression, which would make the largest guard in the table the wrong mechanism. Genuinely
open; operator question.
Disposition: **Addressed.** The assumption was put to the operator rather than argued by the
author, and the ruling is that **a dry run gets no CMDB entry at all** — so the guard stays
and the "no egress" headline holds. The `dry_run: true` alternative was considered and
rejected: it would keep the state-ledger push alive under `--dry-run`, which is the exact
egress the Problem section measured, in exchange for a record of a run that deliberately did
less than it reports. Recorded here so it is not reopened. The gate and absence-case defects
in this finding are fixed in the body: the verification oracle now measures the remote, and
cases 1/3/5 assert the `[DRY RUN]` line rather than an absence alone.

### Ergonomics

Finding: **§2's SKIP rendering contradicts the Scope section.** `git-repos` is _line_-gated —
`_git_repo_status` still runs `git fetch` on every repo and `pull --ff-only` still runs on
every repo that is behind — so `[SKIP] git-repos  dry run` denies that working trees moved.
Round 1 was blocked for `[OK]` over a section that did nothing; round 2 ships `[SKIP]` over a
section that did real work. Same lie, opposite sign. It is also unstable: `_update_warn`
overwrites status unconditionally, so the same dry run renders SKIP or WARN depending on the
fleet's state. The rendering has to follow the guard's granularity. Also: `_update_record_start`
has **no `git-repos` arm** at all (fourteen arms, `legacy-rsync` is the only sync one), so §2
asserts a symmetry that does not exist; case 8 goes red on CI because the existing
`_update_skip "legacy-rsync" "not studio"` collides with the proposed `"dry run"` reason and
the precedence is unspecified; and **no case asserts the `[DRY RUN]` announcement**, so §3 —
the entire remedy for round 1's "operator cannot tell what was gated" — ships untested.
Assumption: that `scan_skills.py --write-ledger` (`workflows.sh:415`) is a second ledger
writer reachable under `--dry-run`. **Checked and refuted** — its `LEDGER_PATH` is
`~/.claude/plugin-verdicts.json` and `_save_ledger` writes JSON to disk. Different artifact,
no git, no egress.
Disposition: **Addressed.** The `git-repos` SKIP is removed entirely — that section is
line-gated, its `git fetch` and `pull --ff-only` really run, and printing SKIP over them
would deny real work in the only durable record of the run. SKIP is kept for `legacy-rsync`
alone, where the whole function is gated, so the rendering now follows the guard's
granularity. The claim that `_update_record_start` has a `git-repos` arm is deleted; it has
fourteen arms and `legacy-rsync` is the only sync one. Case 8 is rewritten to assert the
`legacy-rsync` reason without colliding with the pre-existing `"not studio"` skip, and cases
1/3/5 now assert the `[DRY RUN]` announcement so §3 ships tested.

### Risk

Finding: **The gate fails after a correct implementation, for a second independent reason.**
`sync_git_repos` routes `~/.local/share/state-ledger` through `_git_sync_one_repo`
(`git_sync.sh:108-112`), and `pull --ff-only` is deliberately ungated — so a pull moves
`rev-list --count HEAD` and the gate goes red against a working design. state-ledger is
written from three machines, so _behind_ is its normal state; that repo's own reflog carries
a `pull --ff-only: fast-forward` dated one day before this spec. The oracle is measuring the
wrong side of the wire: "nothing left this machine" is a property of the **remote**, so
`git ls-remote origin main` before/after, or the `origin/main` ref, is falsifiable by a push
and immune to a pull. Two further defects: the round-1 `DRY_RUN` truthiness finding is marked
**Addressed** in this file while appearing nowhere in the body — `helpers.sh:16` is still
`[[ -n ${DRY_RUN:-} ]]`, so `DRY_RUN=0` takes the dry-run branch, and after this change a
stray export silently suppresses every push, rsync and ledger write while reporting success.
And the named test harness cannot coexist with its target: `tests/setup_env/git_sync.bats`
deliberately uses no `load_mocks`, building a real bare origin with real
`git init/clone/commit/push`, so adding mocks for cases 3–4 collapses the file.
Assumption: that `ledger_write_entry` is the sole chokepoint for ledger **egress**, when
`ensure_state_ledger` runs `ledger.py init` unconditionally on every run — including dry ones
— before the gated write. **Checked and refuted.** `cmd_init` spans `ledger.py:372-436` and
contains zero references to `_git_commit_and_push` or `_flush_spool_internal`; the four push
sites are `:486` (`cmd_write`), `:668` (`_flush_spool_internal`), `:791` (`cmd_promote`) and
`:850`, and the flush's callers are `:467`, `:831`, `:948` and `:1010` — none in `cmd_init`.
The two `check=True` git calls in that range are `pull --ff-only` and `clone`, both inbound.
No fourth egress row is needed.
Disposition: **Addressed.** The verification gate is replaced with a remote-side oracle —
`git ls-remote origin main` before and after — which a push moves and a pull cannot, and it
is now labelled honestly as **not runnable until the flag exists**, since both prior rounds
claimed "runnable today and currently fails" and both claims were false. `DRY_RUN`
truthiness is fixed in the body rather than dispositioned away a second time. The
`git_sync.bats` harness constraint is stated: that file deliberately uses no `load_mocks` and
builds a real bare origin, so cases 3/4 must intercept without shadowing the git the fixture
is made of. The refuted assumption is recorded above so no fourth guard is added.

### Session-verified corrections to the spec body

Independent of the lens findings, these were measured and are wrong as written:

- `:108` "Every caller invokes it as `|| true`" is **false** for the two direct callers —
  `update_summary.sh:521` and `:523` are bare. The conclusion survives (both sit inside
  `_ledger_write_run_entry`, whose five callers do use `|| true`), but the stated evidence
  does not.
- "sole chokepoint for every ledger **write**" overreaches. `ensure_state_ledger` runs
  `ledger.py init` (`workflows.sh:937`) and `run_update` runs `scan_skills.py --write-ledger`
  (`:415`) outside it. Neither pushes, so the design is unaffected — the sentence needs
  narrowing to _egress_, which is what it actually establishes.
- The rsync-control safety rationale names the wrong mechanism. `HOME` feeds only the rsync
  _source_ (`legacy_rsync.sh:15`); the three destinations are hardcoded
  `bruce@workstation:`/`laptop-1:`/`ratna:`. An empty `HOME` with real rsync reachable is
  **worse** than none. The existing suite's actual protection is `load_mocks` plus
  `_OVERRIDE_GIT_REPOS_SRC` plus `MOCK_HOSTNAME_OUTPUT` (`legacy_rsync.bats:6,11,16`) — and
  that hostname knob is exactly what case 5 needs and the spec never names.
- There is **no in-repo precedent** for verifying a mock is live before a dangerous call.
  `refute_grep` asserts absence, and `load_mocks` only prepends `tests/mocks` to `PATH`. A
  rule of that shape would be introduced here, not cited — which is a stronger claim and has
  to be written as one. It matters most for the ledger, whose `command -v ledger` arm
  (`workflows.sh:946`) is checked _before_ the `${HOME}`-relative fallback, so `HOME`
  redirection alone does not intercept it and `tests/mocks/ledger` is load-bearing.
- The Decision section corrects the `README.md:207` fact but never re-runs the arithmetic it
  inverts: the rejected alternative is ~90% shipped and costs one line, so the case for
  building three guards has to be argued against _that_ cost, not the stated one.
