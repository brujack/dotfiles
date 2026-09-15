# `--dry-run` Egress Gating Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `setup_env.sh --dry-run` stop performing operations that leave this machine — a push to state-ledger, a push per personal repo, and three `rsync --delete` to remote hosts.

**Architecture:** Three guards plus a truthiness fix. `ledger_write_entry` and `sync_legacy_dirs` take function guards; `_git_sync_one_repo`'s push takes a **line** guard so the fast-forward pull still previews. A shared `_dry_run_active` helper replaces the `[[ -n ]]` test so `DRY_RUN=0` no longer means on.

**Tech Stack:** bash, bats, existing `tests/mocks/` PATH mocks.

**Spec:** `docs/superpowers/specs/2026-09-14-dry-run-irreversible-gating-design.md` at `a334e7aa` (two Step 8 rounds, six dispositions, operator-approved).

## Global Constraints

- **No task may declare `make test`.** Measured on the Studio 2026-09-14: `rc=0`, 1675 ok, 0 not ok, **784s** — past the 600s Bash cap, so it backgrounds and a backgrounded command never wakes a subagent. The orchestrator runs `make test` **once**, uncontended, after **Task 8** — the last code-touching task. That single run is the real gate; the scoped per-task gates are regression checks, not a weakening. (This read "after Task 6" until Task 8 was spliced in for finding C2; Task 8 edits `lib/git_hooks.sh`, so a run at Task 6 would predate the final code change.)
- **No task declares `parallel_group`.** Sequential dispatch; at these durations parallelism buys nothing and avoids the shared-worktree hazard.
- **Phase 2 runs in the worktree** `/Users/bruce/git-repos/personal/dotfiles-dry-run-egress` on branch `fix/dry-run-egress-gating`, created from `a334e7aa`. Do not work in the main checkout.
- `_dry_run_active` is the single truthiness authority. Unset, empty, `0`, `false`, `no` mean **off**; anything else means on. **There are SIX sites, not four**, and this bullet said four until Task 1's review measured otherwise: `run_cmd`, the three guards (Tasks 2–4), `process_args`'s `--dry-run` arm (`helpers.sh:825`, fixed inside Task 1 — see C1 there), and `install_git_hooks_all_repos` (`git_hooks.sh:386`, Task 8). Every one calls the helper so they cannot drift. The two that were missed are the two that read `DRY_RUN` **directly** rather than through `run_cmd`, which is the shape to grep for if a seventh is ever added: `git grep -n 'DRY_RUN' -- lib/ scripts/ setup_env.sh .config/`.
- Every guard prints `[DRY RUN] <what would have run>` on **stdout** (verified: `lib/helpers.sh:17` emits to stdout, stderr empty).
- Every absence assertion is paired with a positive control, and additionally asserts the `[DRY RUN]` line — an absence alone passes when the guard was never reached.
- **What "the gate was proven" means differs by gate shape — read the task body, do not assume.** Measured at pre-flight:
  - **Behavioural proofs (Tasks 1–4).** The defect itself was reproduced on the base tree: `DRY_RUN=0` suppresses execution, a guarded push still moves a fixture `origin` ref, the rsync mock is invoked 3×, the ledger mock is invoked 1×. That is what guarantees the RED test fails for the right reason.
  - **Every task from 2 to 6 declares TWO bats arms, and they have opposite base-tree behaviour on purpose.** Read the pair, not either half.
    - The **discriminating arm** is `-f "dry-run"` (Task 1: `-f "dry_run_active"`). It must match **zero** tests on base, and every one does — exit 1 with `ERROR: Found no tests`, measured per file at pre-flight. This arm is what forces the task's tests to _exist_: a whole-file run exits 0 for a subagent that wrote no test at all, and this arm does not. A filter matching a pre-existing passing test is vacuous — Task 2's original `-f "ledger"` was exactly that, exiting 0 on base against one pre-existing test, and was corrected at pre-flight. **This is why every task body mandates that new test names carry the literal `dry-run`.**
    - The **regression arm** is the unfiltered whole-file run, and it **passes on the base tree by construction** — `workflows.bats` 216 tests, `git_sync.bats` 24, `legacy_rsync.bats` 6, `update_summary.bats` 101, `scripts/unit.bats` 146, all exit 0. Inherent to TDD: the new test does not exist yet. That green is also the positive control proving the filter mechanism works, so the discriminating arm's zero is a real absence rather than a broken filter. It becomes discriminating the moment the RED test is written, since a whole-file run necessarily includes it. **Verify RED directly before implementing**; never read the green base run as evidence of anything but the population.
  - **Task 1 carries a third gate, `-f "run_cmd"`, which exits 0 on base against 3 pre-existing tests. That is deliberate.** It is a regression arm in filtered clothing: Task 1's body requires `unit.bats:744`'s existing `[[ "$output" == "[DRY RUN]"* ]]` prefix assertion keep working, and those 3 tests are what pin it. It is also the **only** gate covering the second half of the deliverable — confirmed by mutation at review: reverting `run_cmd` to `[[ -n ${DRY_RUN:-} ]]` while keeping the helper leaves `-f "dry_run_active"` fully green and turns `-f "run_cmd"` red. Do not "correct" it to a zero-match filter; it would stop pinning the routing.
- If a gate passes on the unmodified tree in a way its task body does not predict, that is a plan defect — report it as a blocker rather than proceeding.

---

### Task 1: `_dry_run_active` helper and `run_cmd` truthiness

```yaml-task
id: 1
description: Add _dry_run_active so DRY_RUN=0/false/no mean off, and route run_cmd through it
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: bats tests/setup_env/unit.bats -f "dry_run_active"
    exit_code: 0
  - cmd: bats tests/setup_env/unit.bats -f "run_cmd"
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched:
  - lib/helpers.sh
  - tests/setup_env/unit.bats
depends_on: []
```

**Files:** `lib/helpers.sh` (add `_dry_run_active`, rewrite `run_cmd`'s condition), `tests/setup_env/unit.bats`.

**Base-tree proof (gate A, measured):** `DRY_RUN=0 run_cmd touch "$f"` prints `[DRY RUN] touch …` and never creates the file — `0` is treated as **on**. A test asserting `DRY_RUN=0` executes therefore fails on base with exit 1, for the right reason.

```bash
_dry_run_active() {
  case "${DRY_RUN:-}" in
    ""|0|false|no) return 1 ;;
    *)             return 0 ;;
  esac
}
```

`run_cmd` becomes `if _dry_run_active; then printf "[DRY RUN] %s\n" "$*"; else "$@"; fi`.

Tests: `DRY_RUN=1`/`true`/`yes` suppress and print the marker; `DRY_RUN=0`/`false`/`no`/empty/unset execute. Keep `tests/setup_env/unit.bats:744`'s existing prefix assertion working.

**Interfaces:**

- Produces: `_dry_run_active()` — no args, returns 0 when dry-run is active. Tasks 2, 3, 4 call it.

---

### Task 2: Guard `ledger_write_entry` and add the `LEDGER_BIN` seam

```yaml-task
id: 2
description: Function-guard ledger_write_entry and add the LEDGER_BIN seam plus its mock
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: bats tests/setup_env/workflows.bats -f "dry-run"
    exit_code: 0
  - cmd: bats tests/setup_env/workflows.bats
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched:
  - lib/workflows.sh
  - tests/mocks/ledger
  - tests/setup_env/workflows.bats
depends_on: [1]
```

**Files:** `lib/workflows.sh` (`ledger_write_entry`, ~`:943`), new `tests/mocks/ledger`, `tests/setup_env/workflows.bats`.

**Base-tree proof (gate F, measured):** with a `ledger` mock on `PATH`, `DRY_RUN=1 ledger_write_entry '{"x":1}'` invokes the mock **1** time and exits 0. A test asserting zero invocations fails on base by measuring the write, not by a missing seam.

Guard goes at the top of `ledger_write_entry`, after the payload check, before binary resolution:

```bash
if _dry_run_active; then
  printf "[DRY RUN] ledger write (entry suppressed)\n"
  return 0
fi
```

`return 0` is load-bearing: `update_summary.sh:521` and `:523` are **bare** calls (the spec's earlier "every caller uses `|| true`" was wrong); safety comes from `_ledger_write_run_entry`'s five callers using `|| true` and `:598`'s `_ledger_write_dotfiles_entry || true`.

Seam: resolve `LEDGER_BIN` first, then `command -v ledger`, then `${HOME}/.local/bin/ledger`. Needed because `command -v` is checked **before** the `${HOME}` fallback, so redirecting `HOME` cannot intercept. `tests/mocks/ledger` records argv to `MOCK_CALLS_FILE` and drains stdin.

**That justification is true of one actor and false of three, so it carries a qualifier — measured 2026-09-14 across the fleet rather than asserted:**

| actor                                      | `~/.local/bin` on `PATH` | `command -v ledger`             | could a `HOME` redirect intercept? |
| ------------------------------------------ | ------------------------ | ------------------------------- | ---------------------------------- |
| `workstation` / `claude`, interactive zsh  | yes                      | `/home/bruce/.local/bin/ledger` | **no — the seam is required**      |
| `workstation` / `claude`, `ssh host 'cmd'` | no                       | none                            | yes                                |
| Studio, harness Bash tool                  | no                       | none                            | yes                                |
| `ubuntu-latest`                            | n/a                      | none (ledger not installed)     | yes                                |

**The one row that matters is the first, because it is the actor that runs the suite on a Linux dev box** — a session's Bash tool is profile-sourced, so it inherits the interactive `PATH`. A `HOME`-only test seam would therefore pass in CI and on the Studio and fail on `workstation` and `claude`: green where it is cheap to run and red where the real binary lives. That split is the argument for `LEDGER_BIN`, not the bare ordering claim.

This qualifier exists because the unqualified sentence was checked against `ssh host 'command -v ledger'`, which returned `none` on both Linux boxes and appeared to refute it. `ssh` is the non-interactive actor and answers for a different `PATH` — `behavior.md`'s actor-boundary rule, hit while auditing this very premise. Do not re-derive this with `ssh`.

Tests: absence case asserts the mock is uncalled **and** `[DRY RUN]` appears; control (`DRY_RUN` unset) asserts the mock is called and receives the JSON on stdin.

**Both new test names MUST contain the literal string `dry-run`**, because the acceptance
gate filters on it. Measured at pre-flight: `-f "ledger"` was the original filter and it
exits **0** on the base tree — it matches one pre-existing passing test
(`run_setup_user still calls _ledger_write_run_entry when install_git_hooks_all_repos returns 1`),
so it passed against zero implementation, and it would have kept passing if the new tests were
named without that substring. `-f "dry-run"` matches **zero** tests on base (exit 1,
`ERROR: Found no tests`), so the gate cannot pass until this task's tests exist. Suggested
names: `ledger_write_entry under dry-run does not invoke the ledger binary` and
`ledger_write_entry without dry-run invokes the ledger binary with the JSON on stdin`.

**Interfaces:**

- Consumes: `_dry_run_active()` from Task 1.
- Produces: `LEDGER_BIN` seam; `tests/mocks/ledger` honouring `MOCK_CALLS_FILE`.

---

### Task 3: Line-guard the push in `_git_sync_one_repo`

```yaml-task
id: 3
description: Guard only the git push at git_sync.sh:71, leaving pull --ff-only previewing
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: bats tests/setup_env/git_sync.bats -f "dry-run"
    exit_code: 0
  - cmd: bats tests/setup_env/git_sync.bats
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched:
  - lib/git_sync.sh
  - tests/setup_env/git_sync.bats
depends_on: [1]
```

**Files:** `lib/git_sync.sh` (`:71` only), `tests/setup_env/git_sync.bats`.

**Base-tree proof (gate D, measured):** in a real bare-origin fixture, `DRY_RUN=1 _git_sync_one_repo <clone>` **moves** the origin ref. A test asserting the ref is unmoved fails on base for the right reason.

Guard the ahead branch only:

```bash
if [[ ${_ahead} -gt 0 ]]; then
  if _dry_run_active; then
    printf "[DRY RUN] git -C %s push --quiet\n" "${_path}"
    return 0
  fi
  ...
```

**Do NOT guard the function or the `behind` branch.** `pull --ff-only` at `:82` is deliberately left running so a preview shows it. `sync_git_repos` routes both the personal repos and `~/.local/share/state-ledger` (`:108-112`) through this one function, so this single line covers both.

**This file uses NO `load_mocks`** — its `setup()` builds a real bare origin with real `git init/clone/commit/push`. Adding the git mock would shadow the git the fixture is made of. Assert on the fixture's `origin` ref, never on a git mock.

Tests: ahead-branch absence (origin ref unmoved + `[DRY RUN]` names the push); ahead-branch control (ref advances); behind-branch under `DRY_RUN=1` asserting `pull --ff-only` **still ran** — that case is what fails if someone later widens this to a function guard.

**Every new test name MUST contain the literal string `dry-run`.** The unfiltered
whole-file run is a regression arm, not a gate: measured at pre-flight, `bats
tests/setup_env/git_sync.bats` exits **0** on the base tree with 24 passing tests, so on its
own it would have passed against zero implementation. The `-f "dry-run"` arm matches
**zero** tests on base (exit 1, `ERROR: Found no tests`) and is what makes the gate
discriminate; the 24-test population is the positive control proving the filter mechanism
works rather than the zero being an artifact. Keep both arms.

**Interfaces:**

- Consumes: `_dry_run_active()` from Task 1.

---

### Task 4: Function-guard `sync_legacy_dirs`

```yaml-task
id: 4
description: Function-guard sync_legacy_dirs so no rsync --delete reaches a remote host
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: bats tests/setup_env/legacy_rsync.bats -f "dry-run"
    exit_code: 0
  - cmd: bats tests/setup_env/legacy_rsync.bats
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched:
  - lib/legacy_rsync.sh
  - tests/setup_env/legacy_rsync.bats
depends_on: [1]
```

**Files:** `lib/legacy_rsync.sh` (`sync_legacy_dirs`, `:8`), `tests/setup_env/legacy_rsync.bats`.

**Base-tree proof (gate E, measured):** with `MOCK_HOSTNAME_OUTPUT=studio`, `_OVERRIDE_GIT_REPOS_SRC` set and mocks on `PATH`, `DRY_RUN=1 sync_legacy_dirs` invokes the rsync mock **3** times. A test asserting zero invocations fails on base correctly.

Guard goes **after** the `_is_legacy_sync_host` check so a non-studio host still reports its existing skip:

```bash
if _dry_run_active; then
  printf "[DRY RUN] rsync -ar --delete to workstation, laptop-1, ratna\n"
  return 0
fi
```

**`MOCK_HOSTNAME_OUTPUT=studio` is mandatory in BOTH the absence case and its control.** Without it `_is_legacy_sync_host` returns at `legacy_rsync.sh:9-12` on `ubuntu-latest` and on two of three dev machines, the rsync mock goes uncalled because of the host gate rather than the guard, and the case passes against zero implementation. Subject and control must differ only in `DRY_RUN`.

Safety: protection is `load_mocks` + `_OVERRIDE_GIT_REPOS_SRC` + `MOCK_HOSTNAME_OUTPUT` (`legacy_rsync.bats:6,11,16`) — **not** `HOME`. `HOME` feeds only the rsync _source_; the three destinations are hardcoded `bruce@workstation:`, `bruce@laptop-1:`, `bruce@ratna:`, so an empty `HOME` with real rsync reachable would empty the targets.

**Every new test name MUST contain the literal string `dry-run`.** The unfiltered
whole-file run is a regression arm, not a gate: measured at pre-flight, `bats
tests/setup_env/legacy_rsync.bats` exits **0** on the base tree with 6 passing tests, so on
its own it would have passed against zero implementation. The `-f "dry-run"` arm matches
**zero** tests on base (exit 1, `ERROR: Found no tests`) and is what makes the gate
discriminate; the 6-test population is the positive control proving the filter mechanism
works rather than the zero being an artifact. Keep both arms.

**Interfaces:**

- Consumes: `_dry_run_active()` from Task 1.

---

### Task 5: Render `[SKIP] legacy-rsync dry run` — and no `git-repos` SKIP

```yaml-task
id: 5
description: Under DRY_RUN, _update_record_start's legacy-rsync arm writes a dry-run skip
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: bats tests/setup_env/update_summary.bats -f "dry-run"
    exit_code: 0
  - cmd: bats tests/setup_env/update_summary.bats
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched:
  - lib/update_summary.sh
  - tests/setup_env/update_summary.bats
depends_on: [4]
```

**Files:** `lib/update_summary.sh` (`_update_record_start`'s `legacy-rsync)` arm, `:152-153`).

Without this, a guarded `sync_legacy_dirs` returning 0 reaches `_update_record_end … 0`, whose `*)` arm sets `_result="updated"` and prints `[OK] legacy-rsync  updated` for a section that synced nothing.

```bash
legacy-rsync)
  if _dry_run_active; then
    _update_skip "legacy-rsync" "dry run"
  else
    _is_legacy_sync_host || _update_skip "legacy-rsync" "not studio"
  fi
  ;;
```

**`git-repos` gets NO arm and no SKIP.** That section is line-gated: `_git_repo_status` still runs `git fetch` on every repo and `pull --ff-only` still runs on every repo that is behind. `[SKIP] git-repos` would deny that working trees moved — replacing round 1's false `[OK]` with an equally false `[SKIP]`. `_update_record_start` has fourteen arms and no `git-repos` arm; do not add one.

Tests: with `MOCK_HOSTNAME_OUTPUT=studio` and `DRY_RUN=1`, the `legacy-rsync` reason is `dry run` (not `not studio` — they collide otherwise); and no `status_git-repos` SKIP file is written. The second half pins the granularity decision.

**Every new test name MUST contain the literal string `dry-run`** — note the hyphen, while
the rendered SKIP _reason_ is the two-word `dry run`; the test name and the asserted output
are different strings and only the name feeds the filter. The unfiltered whole-file run is a
regression arm, not a gate: measured at pre-flight, `bats tests/setup_env/update_summary.bats`
exits **0** on the base tree with 101 passing tests, so on its own it would have passed
against zero implementation. The `-f "dry-run"` arm matches **zero** tests on base (exit 1,
`ERROR: Found no tests`) and is what makes the gate discriminate; the 101-test population is
the positive control proving the filter mechanism works rather than the zero being an
artifact. Keep both arms.

**Interfaces:**

- Consumes: `_dry_run_active()` from Task 1; the Task 4 guard.

---

### Task 6: Add `--dry-run` to `scripts/sync_git_repos.sh`

```yaml-task
id: 6
description: Parse --dry-run in sync_git_repos_main so the standalone entry point can preview
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: bats tests/scripts/unit.bats -f "dry-run"
    exit_code: 0
  - cmd: bats tests/scripts/unit.bats
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched:
  - scripts/sync_git_repos.sh
  - tests/scripts/unit.bats
depends_on: [3, 4]
```

**Files:** `scripts/sync_git_repos.sh` (`sync_git_repos_main`, `:34-56`), `tests/scripts/unit.bats`.

**Gate B was rewritten, and why matters.** The obvious gate — run the script with `--dry-run` — exits 1 on base with `Unrecognized option: --dry-run`, which is the script's deliberate rejection (already pinned by `tests/scripts/unit.bats:356`). Exit 1 _looks_ like a real measurement and measures nothing about egress. The gate asserts instead that **a bare-origin fixture's ref is unmoved** while the flag is accepted, which can only pass once Tasks 3 and 4 have landed.

`--dry-run` sets `DRY_RUN=1` and is composable with the existing `--git-only` / `--legacy-only`, so the current single-`${1:-}` `case` must become a loop. Preserve the existing `*)` rejection for genuinely unknown flags — `unit.bats:356` pins it and must keep passing.

Both legs are gated by Tasks 3 and 4, so the flag is honoured by everything the script does. Round 1 proposed this flag while gating only one leg, which would have advertised a preview that still pushed.

**Every new test name MUST contain the literal string `dry-run`.** The unfiltered whole-file
run is a regression arm, not a gate: measured at pre-flight, `bats tests/scripts/unit.bats`
exits **0** on the base tree with 146 passing tests, so on its own it would have passed
against zero implementation. The `-f "dry-run"` arm matches **zero** tests in this file on
base (exit 1, `ERROR: Found no tests`) and is what makes the gate discriminate; the 146-test
population is the positive control proving the filter mechanism works rather than the zero
being an artifact. Other files in `tests/scripts/` do carry `--dry-run` test names, which is
irrelevant — the filter is scoped to this file. Keep both arms, and note the regression arm
is the one that pins `unit.bats:356`'s existing unknown-flag rejection.

**Interfaces:**

- Consumes: Task 3's push guard, Task 4's rsync guard.

---

### Task 7: Correct `CLAUDE.md` and document the seam

```yaml-task
id: 7
description: Correct CLAUDE.md:92 and :86 and add the LEDGER_BIN Test Seams row (docs-only, no behaviour change so TDD does not apply)
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: 'grep -qE "no (operation that leaves|egress)" CLAUDE.md'
    exit_code: 0
  - cmd: grep -q "LEDGER_BIN" CLAUDE.md
    exit_code: 0
  - cmd: grep -q "DRY_RUN=0" CLAUDE.md
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched:
  - CLAUDE.md
depends_on: [6]
```

**Files:** `CLAUDE.md` only.

**This task was `model: haiku` and was escalated to `sonnet` after a dispatch failed with `Prompt is too long`.** The task is genuinely single-file and mechanical — exactly what haiku is for. Escalation is authorized re-plan move 4, applied without widening scope: the task, its gates and its one file are unchanged.

**The first diagnosis recorded here was wrong and is retracted.** It blamed the size of `CLAUDE.md` and offered "roughly 1,000 lines" as a threshold. Task 9 then failed identically on `README.md` at **515 lines / 25,676 bytes** — a 6× smaller file, same `Prompt is too long`. The target file is not the variable.

**The variable is the fixed preamble every subagent in this repo carries before it reads anything**, measured 2026-09-14:

| component                             | bytes                     |
| ------------------------------------- | ------------------------- |
| repo `CLAUDE.md`                      | 154,612                   |
| `~/.claude/standards/*.md` (14 files) | 491,947                   |
| `USER.md`                             | 19,047                    |
| **total**                             | **665,606 ≈ 166k tokens** |

Against haiku 4.5's 200k window that is ~83% consumed at dispatch, so **no `model: haiku` task in this repo is dispatchable at all**, whatever it touches. Both escalations are therefore the same fix, not two coincidences.

**The haiku scope guard cannot catch this class, and that is worth stating where the next author will see it.** `validate-plan.py`'s `_haiku_scope_errors` enforces `files_touched` of **exactly one path** plus a forbidden-pattern list (workflows, migrations, lockfiles). It has no size check, so one enormous file passes a guard whose whole purpose is keeping haiku on work it can hold. A plan can therefore be valid and undispatchable at the same time.

**Task 9 was checked, deliberately left on `haiku`, and then failed too — so the check was right in form and wrong in its criterion.** Sizing `README.md` at 515 lines and concluding haiku "holds it comfortably" was verifying one level wider than the fix, which is the correct instinct; it measured the wrong quantity. The question was never how big the target file is, but how much of the window is gone before the agent starts. Task 9 is now `sonnet` for the same reason Task 7 is.

**Do not choose `haiku` for any task in this repo until the preamble shrinks or the guard learns to check it.** `validate-plan.py`'s `_haiku_scope_errors` enforces `files_touched` of exactly one path plus a forbidden-pattern list (workflows, migrations, lockfiles) and has no notion of context budget — so it will keep certifying `model: haiku` plans that cannot be dispatched. A plan can be valid and undispatchable at once, and this one was, twice.

`:92` currently promises "log mutating operations (symlinks, installs, mkdir) without executing", which is false. It becomes a statement of what is guaranteed — **no egress** — and enumerates what still runs: package upgrades, venv rebuilds, `git fetch` and `pull --ff-only` on every personal repo, five `npm install -g`, and `uv sync`. Follow `README.md:207`'s enumerate-what-still-runs model.

`:86` says `-t update` "Also writes a state-ledger entry" — now conditionally false, since no entry is written under `--dry-run`. Add that qualifier.

Add a Test Seams row for `LEDGER_BIN` beside `UV_BIN` and `GGSHIELD_BIN`, stating it is checked before `command -v ledger` and that `tests/mocks/ledger` is load-bearing rather than convenient.

**Write the reason with its actor, not the bare ordering claim.** The row must say that on a Linux dev box the suite's actor is profile-sourced and therefore resolves a real `ledger` at `~/.local/bin/ledger` through `command -v`, so a `HOME`-only seam would pass on the Studio and in CI — where `command -v ledger` finds nothing — and fail on `workstation` and `claude`. Task 2's body carries the measured four-actor table; copy that reasoning, and do **not** write the unqualified sentence "redirecting `HOME` cannot intercept on the Linux boxes", which is true only of the interactive actor and reads as true of all of them.

**Also state the truthiness contract, which lands documented nowhere otherwise.** `CLAUDE.md:92` and `README.md:207` describe `--dry-run`'s _scope_ and never its accepted _values_, so the `0`/`false`/`no`/empty/unset rule this plan introduces would ship fleet-wide undocumented. One sentence: `DRY_RUN=0`, `false`, `no`, empty and unset all mean dry-run is **off**, any other value means on, and `--dry-run` wins over an inherited falsy value. The third acceptance gate (`grep -q "DRY_RUN=0" CLAUDE.md`) pins it — measured at pre-flight, `CLAUDE.md` contains **zero** occurrences of `DRY_RUN=0`, `LEDGER_BIN`, and the egress phrasing, so all three greps exit 1 on base and none is vacuous.

---

### Task 8: Route `install_git_hooks_all_repos` through `_dry_run_active`

```yaml-task
id: 8
description: Fix the sixth DRY_RUN reader at git_hooks.sh:386 so the sweep and run_cmd agree
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: bats tests/setup_env/git_hooks.bats -f "dry-run"
    exit_code: 0
  - cmd: bats tests/setup_env/git_hooks.bats
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched:
  - lib/git_hooks.sh
  - tests/setup_env/git_hooks.bats
depends_on: [1]
```

**Files:** `lib/git_hooks.sh` (`:386` only), `tests/setup_env/git_hooks.bats`.

**This task exists because the plan was wrong, and that is worth recording.** The spec enumerated `git_hooks.sh:386` as a `DRY_RUN` reader; no task 1–7 touched `lib/git_hooks.sh`, and the Global Constraints bullet above counted four sites when there are six. Found by Task 1's code-quality review, confirmed independently before scheduling — `git grep` shows the file appears in no other task's `files_touched`.

`:386` still reads `[[ -n "${DRY_RUN:-}" ]] && _dry=1`, so after Task 1 the two predicates **disagree** on exactly the values Task 1 changed:

```
DRY_RUN=[0]      run_cmd=EXEC   git_hooks.sh:386 -> _dry=1
DRY_RUN=[false]  run_cmd=EXEC   git_hooks.sh:386 -> _dry=1
DRY_RUN=[no]     run_cmd=EXEC   git_hooks.sh:386 -> _dry=1
```

Measured at review, end-to-end against the file's own `_sweep_build_cp_repo` fixture with `DRY_RUN=0 install_git_hooks_all_repos`: `make install-hooks` really ran in both repos (both markers present) while the summary reported `2 checked, n/a updated, 0 gaps`. On base this was **coherent** — `DRY_RUN=0` meant dry on both halves, nothing ran, and `n/a` was truthful. Task 1 introduces the incoherence; it is not pre-existing.

Two consequences, both at lines the fix must leave alone:

- `:538-540` forces `_updated_str="n/a"` whenever `_dry -eq 1`, under a comment reading _"`0` under DRY_RUN would falsely assert every repo was already current — nothing ran, so nothing is known."_ Post-Task-1 that comment is false in precisely the new case: things ran, and the summary denies it.
- `:449`'s `[[ ${_dry} -eq 0 ]] && _pre=...` skips the pre-digest, so `_updated` cannot increment even without the `n/a` override — real installs are structurally uncountable while `_dry=1`.

Fix is one line: `_dry_run_active && _dry=1`. It sits mid-function so there is no trailing-return hazard, and `lib/helpers.sh` is already a hard dependency of this file through `run_cmd`/`log_warn`, so the symbol resolves. **Do not** rewrite `:449` or `:538` — once `_dry` is correct they are correct, and widening scope here re-opens the counting question this plan deliberately left alone.

**Every new test name MUST contain the literal string `dry-run`.** Measured at pre-flight: `git_hooks.bats` holds 92 tests, **zero** of whose names contain `dry-run`, so `-f "dry-run"` exits 1 with `ERROR: Found no tests` and the gate cannot pass until this task's tests exist; the whole-file arm exits 0 at 92 ok on base, which is both the regression arm and the positive control proving the filter works. Mirror the existing `git_hooks.bats:1254` (`DRY_RUN=1`) with a `DRY_RUN=0` case asserting the markers **do** exist and the summary does **not** contain `n/a updated`.

**Interfaces:**

- Consumes: `_dry_run_active()` from Task 1.

---

### Task 9: Correct `README.md:207`, which this branch falsifies

```yaml-task
id: 9
description: Rewrite README.md's --dry-run option entry, which becomes false when this branch merges (docs-only, no behaviour change so TDD does not apply)
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: grep -q "leaves this machine" README.md
    exit_code: 0
  - cmd: '! grep -q "git-hooks sweep only" README.md'
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched:
  - README.md
depends_on: [8]
```

**Files:** `README.md` only (`:207`).

**This task exists because the plan was wrong a second time, in the same way as Task 8.** The spec discusses `README.md:207` in eight places and no task's `files_touched` contained `README.md`. Found by checking Task 7's pointers against the file rather than trusting them.

`:207` currently reads:

> `--dry-run` — log mutating operations without executing. **Honoured by symlinking (`lib/helpers.sh`) and the git-hooks sweep only** — `run_update` contains no `run_cmd` call sites, so `-t update --dry-run` still performs real package upgrades, `git push`, and `rsync --delete`. Do not rely on it to preview an update.

Every clause is accurate **today** and the emphasised one is exactly what Tasks 2–4 and 8 falsify. Left alone it becomes a confident, specific, wrong warning telling operators not to trust a flag that now works — worse than the vague promise at `CLAUDE.md:92` that Task 7 fixes, because this one names mechanisms and reads as freshly verified.

Rewrite it on `README.md:207`'s own enumerate-what-still-runs model — the model Task 7 is told to imitate, which this line is the origin of. State what is now **guaranteed** (no operation that leaves this machine: no `git push`, no `rsync --delete`, no state-ledger write) and enumerate what still runs (package upgrades, venv rebuilds, `git fetch` and `pull --ff-only` on every personal repo, five `npm install -g`, `uv sync`). Keep it one bullet; do not restructure the Options list.

**Gate discrimination, measured at pre-flight.** Presence gate: `leaves this machine` occurs **0** times in `README.md` today (as do `no egress` and `DRY_RUN=0`), so it cannot pass until the rewrite lands. Absence gate: `git-hooks sweep only` occurs exactly **1** time, so its removal is observable — and it is paired with the presence gate deliberately, because an absence alone is satisfied by several states including the line being deleted outright rather than rewritten.

**Scope discipline:** `:162` also mentions a state-ledger entry, and `:456` describes the pre-push hook. Neither is this task's business — do not touch them.

**Interfaces:**

- Consumes: the finished behaviour of Tasks 2, 3, 4 and 8. Runs last so it describes the merged state rather than an intermediate one.

---

## Verification

Per-task gates above are regression checks. The feature-level verification is:

1. **Orchestrator runs `make test` once after Task 8**, uncontended — Task 8 is the last code-touching task, not Task 6. Baseline `rc=0`, 1675 ok, 0 not ok, 784s. Expect ok to rise by the new cases and not-ok to stay 0.
2. **Operator check on the Studio, after the branch merges** — proves the whole change against the real world rather than fixtures:

```bash
before=$(git -C ~/.local/share/state-ledger ls-remote origin main | awk '{print $1}')
scripts/sync_git_repos.sh --dry-run
after=$(git -C ~/.local/share/state-ledger ls-remote origin main | awk '{print $1}')
[ "${before}" = "${after}" ]
```

`ls-remote` is the oracle because "nothing left this machine" is a property of the **remote**. Two earlier gates measured `rev-list --count HEAD`, which a _pull_ moves and a _push_ does not — one could only fail, the other could only pass.

3. **Edge cases that must be exercised:** `DRY_RUN=0` executes (Task 1); **an exported `DRY_RUN=0` plus an explicit `--dry-run` previews rather than executing** (Task 1, finding C1); the sweep summary does not report `n/a updated` over hooks it really installed (Task 8, finding C2); the behind-branch pull still runs under `DRY_RUN=1` (Task 3); `legacy-rsync` renders `dry run` and not `not studio` on a studio host (Task 5); the `*)` unknown-flag rejection still works (Task 6).

The C1 case is the one to run by hand on the Studio before merging, because it is the only edge case whose failure mode is **real egress under an explicit preview flag** rather than a wrong report. Measured on both trees at review time, which is what makes it a regression case rather than a hypothetical:

```
DRY_RUN=0 + --dry-run, base 582fac1c -> PREVIEW            (correct, by accident)
DRY_RUN=0 + --dry-run, Task 1 as first shipped -> EXECUTES FOR REAL
```

## Out of scope

Recorded in the spec's Known limitations with measurements, deliberately not in this plan: registry fetches (`npm install -g` ×5, `uv_sync_venv`), delete-recreate pairs, and a drift ratchet asserting the egress set is a subset of the gated set.
