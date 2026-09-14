# `--dry-run` Egress Gating Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `setup_env.sh --dry-run` stop performing operations that leave this machine — a push to state-ledger, a push per personal repo, and three `rsync --delete` to remote hosts.

**Architecture:** Three guards plus a truthiness fix. `ledger_write_entry` and `sync_legacy_dirs` take function guards; `_git_sync_one_repo`'s push takes a **line** guard so the fast-forward pull still previews. A shared `_dry_run_active` helper replaces the `[[ -n ]]` test so `DRY_RUN=0` no longer means on.

**Tech Stack:** bash, bats, existing `tests/mocks/` PATH mocks.

**Spec:** `docs/superpowers/specs/2026-09-14-dry-run-irreversible-gating-design.md` at `a334e7aa` (two Step 8 rounds, six dispositions, operator-approved).

## Global Constraints

- **No task may declare `make test`.** Measured on the Studio 2026-09-14: `rc=0`, 1675 ok, 0 not ok, **784s** — past the 600s Bash cap, so it backgrounds and a backgrounded command never wakes a subagent. The orchestrator runs `make test` **once**, uncontended, after Task 6 (the last code-touching task). That single run is the real gate; the scoped per-task gates are regression checks, not a weakening.
- **No task declares `parallel_group`.** Sequential dispatch; at these durations parallelism buys nothing and avoids the shared-worktree hazard.
- **Phase 2 runs in the worktree** `/Users/bruce/git-repos/personal/dotfiles-dry-run-egress` on branch `fix/dry-run-egress-gating`, created from `a334e7aa`. Do not work in the main checkout.
- `_dry_run_active` is the single truthiness authority. Unset, empty, `0`, `false`, `no` mean **off**; anything else means on. `run_cmd` and all three guards call it so the four sites cannot drift.
- Every guard prints `[DRY RUN] <what would have run>` on **stdout** (verified: `lib/helpers.sh:17` emits to stdout, stderr empty).
- Every absence assertion is paired with a positive control, and additionally asserts the `[DRY RUN]` line — an absence alone passes when the guard was never reached.
- **What "the gate was proven" means differs by gate shape — read the task body, do not assume.** Measured at pre-flight:
  - **Behavioural proofs (Tasks 1–4).** The defect itself was reproduced on the base tree: `DRY_RUN=0` suppresses execution, a guarded push still moves a fixture `origin` ref, the rsync mock is invoked 3×, the ledger mock is invoked 1×. That is what guarantees the RED test fails for the right reason.
  - **Whole-file bats gates (Tasks 3–6) pass on the base tree by construction** — `git_sync.bats` 24 tests, `legacy_rsync.bats` 6, `update_summary.bats` 101, `scripts/unit.bats` 146, all exit 0. Inherent to TDD: the new test does not exist yet. The gate becomes discriminating the moment the RED test is written, and a whole-file run necessarily includes it. **Verify RED directly before implementing**; never read the green base run as evidence.
  - **Filtered gates (Tasks 1–2) must match zero tests on base**, and both do: `-f "dry_run_active"` and `-f "dry-run"` each exit 1 with `ERROR: Found no tests`. A filter matching a pre-existing passing test is vacuous — Task 2's original `-f "ledger"` was exactly that, exiting 0 on base against one pre-existing test, and was corrected at pre-flight.
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

Seam: resolve `LEDGER_BIN` first, then `command -v ledger`, then `${HOME}/.local/bin/ledger`. Needed because `command -v` is checked **before** the `${HOME}` fallback, so redirecting `HOME` cannot intercept on the Linux boxes. `tests/mocks/ledger` records argv to `MOCK_CALLS_FILE` and drains stdin.

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

**Interfaces:**

- Consumes: Task 3's push guard, Task 4's rsync guard.

---

### Task 7: Correct `CLAUDE.md` and document the seam

```yaml-task
id: 7
description: Correct CLAUDE.md:92 and :86 and add the LEDGER_BIN Test Seams row (docs-only, no behaviour change so TDD does not apply)
role: executor
model: haiku
tdd: not-applicable
acceptance:
  - cmd: 'grep -qE "no (operation that leaves|egress)" CLAUDE.md'
    exit_code: 0
  - cmd: grep -q "LEDGER_BIN" CLAUDE.md
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched:
  - CLAUDE.md
depends_on: [6]
```

**Files:** `CLAUDE.md` only.

`:92` currently promises "log mutating operations (symlinks, installs, mkdir) without executing", which is false. It becomes a statement of what is guaranteed — **no egress** — and enumerates what still runs: package upgrades, venv rebuilds, `git fetch` and `pull --ff-only` on every personal repo, five `npm install -g`, and `uv sync`. Follow `README.md:207`'s enumerate-what-still-runs model.

`:86` says `-t update` "Also writes a state-ledger entry" — now conditionally false, since no entry is written under `--dry-run`. Add that qualifier.

Add a Test Seams row for `LEDGER_BIN` beside `UV_BIN` and `GGSHIELD_BIN`, stating it is checked before `command -v ledger` and that `tests/mocks/ledger` is load-bearing rather than convenient.

---

## Verification

Per-task gates above are regression checks. The feature-level verification is:

1. **Orchestrator runs `make test` once after Task 6**, uncontended. Baseline `rc=0`, 1675 ok, 0 not ok, 784s. Expect ok to rise by the new cases and not-ok to stay 0.
2. **Operator check on the Studio, after the branch merges** — proves the whole change against the real world rather than fixtures:

```bash
before=$(git -C ~/.local/share/state-ledger ls-remote origin main | awk '{print $1}')
scripts/sync_git_repos.sh --dry-run
after=$(git -C ~/.local/share/state-ledger ls-remote origin main | awk '{print $1}')
[ "${before}" = "${after}" ]
```

`ls-remote` is the oracle because "nothing left this machine" is a property of the **remote**. Two earlier gates measured `rev-list --count HEAD`, which a _pull_ moves and a _push_ does not — one could only fail, the other could only pass.

3. **Edge cases that must be exercised:** `DRY_RUN=0` executes (Task 1); the behind-branch pull still runs under `DRY_RUN=1` (Task 3); `legacy-rsync` renders `dry run` and not `not studio` on a studio host (Task 5); the `*)` unknown-flag rejection still works (Task 6).

## Out of scope

Recorded in the spec's Known limitations with measurements, deliberately not in this plan: registry fetches (`npm install -g` ×5, `uv_sync_venv`), delete-recreate pairs, and a drift ratchet asserting the egress set is a subset of the gated set.
