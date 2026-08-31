# `run_update` cd guards, invisible section, and truncating fetches — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove three `cd`-backs that silently relocate cwd and carry an abort path for a hazard that cannot occur; make `zsh-autosuggestions` a reported section; and stop four `curl > file` sites from destroying their target and reporting OK over it.

**Architecture:** Three independent edits to `lib/workflows.sh` plus one to `lib/update_summary.sh`, each landing with its own bats coverage. Two changes to the shared `tests/mocks/curl` are prerequisites, because the mock currently cannot express either a failed fetch with `-f` or a successful fetch that writes content.

**Tech Stack:** bash 5.x, bats-core, `tests/mocks/` PATH-injection harness, `make lint` (shellcheck + `bash -n` + `zsh -n`).

**Spec:** [2026-08-31-update-run-cd-guards-design.md](../specs/2026-08-31-update-run-cd-guards-design.md) at `ebed0101`. Two full Multi-Lens Review rounds, all dispositions recorded.

## Global Constraints

- **Acceptance gates are scoped, and `make test` is the orchestrator's job — a deliberate deviation from `writing-plans`' aggregate-gate rule, for the reason that rule's own wave exception gives.** Measured this session: `make test` on the base tree runs past 1:43 and keeps going, so it crosses the Bash tool's 120s auto-background threshold. A backgrounded command never wakes a subagent, so a task declaring `make test` ends its turn awaiting a notification that does not arrive. The exception's stated mechanism is duration, not parallelism, and it applies to a sequential task of this length identically. **The orchestrator runs `make test` after each task's gate passes**; that single uncontended run is the aggregate gate, so nothing is weakened.
- **Every gate below was checked against the base tree while this plan was written.** A gate that exits non-zero for a usage reason (missing file, missing binary, `bats -f` matching nothing) is not a gate — each structural gate names a construct that exists today and asserts it is gone or changed.
- **`bats -f <filter>` exits 0 when it matches nothing.** Every bats gate therefore also asserts a minimum test count via `-c`, or names the file without a filter. Do not write a bare `bats -f` gate.
- **No `set -e` in `lib/*.sh`** (`shell.md`). Propagate with `|| return 1` / `_rc=1`.
- **`printf`, not `echo`. `[[ ]]`, not `[ ]`. `${VAR}` with braces.** Function bodies use `|| return 1`, never `|| exit`.
- **Correct line references** (`lib/workflows.sh`, current master): binary fetch `:650`, completion fetch `:658`, zsh-autosuggestions block `:660-665`, cd-backs `:622`/`:632`/`:642`/`:662`/`:664`; install path `:162` (binary), `:171-173` (completion, `! -f`-guarded).
- **`tests/mocks/curl` is shared fleet-wide.** Any change must leave every existing suite's ok/not-ok set identical with the new variables unset.
- **A `.git` existence test, never `git rev-parse`, for the plugin guard.** `rev-parse --git-dir` walks upward and `~/.oh-my-zsh` is itself a checkout; an exported `GIT_DIR` defeats `git -C` besides. See spec Group B.

## Verification Planning

**Session-level command:** `make test` on a clean tree, then a real `setup_env.sh -t update` on the Studio.

**Expected observable:** the rendered summary gains a `zsh-autosuggestions` row (OK or FAIL, not SKIP, since the plugin is a real clone here), the `cheat.sh` row still reports, and `~/bin/cht.sh` and `~/.zsh.d/_cht` are **non-empty afterwards** — both are 0 bytes today (spec M4), so a successful run repairing them is the end-to-end proof that `-o` plus `[[ -s ]]` works against the real endpoints.

**Edge cases that must be exercised:** a plugin directory that is not a git checkout; a plugin directory that is a non-clone nested inside the oh-my-zsh repo (the case that defeated the first guard); a 404 on either cheat.sh fetch; a completion-only failure; `run_update` invoked from outside the dotfiles repo.

---

### Task 1: Teach `tests/mocks/curl` to express failure and success

```yaml-task
id: 1
description: Add MOCK_CURL_HTTP_STATUS (honoured only for a short-option cluster containing f) and make -o write MOCK_CURL_STDOUT to the target instead of touching it
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: 'bash -c ''MOCK_CURL_HTTP_STATUS=404 tests/mocks/curl -fsS -o /tmp/t1a https://cht.sh/:cht.sh; [[ $? -ne 0 ]]'''
    exit_code: 0
  - cmd: 'bash -c ''MOCK_CURL_HTTP_STATUS=404 tests/mocks/curl -sS -o /tmp/t1b http://x; [[ $? -eq 0 ]]'''
    exit_code: 0
  - cmd: 'bash -c ''MOCK_CURL_HTTP_STATUS=404 tests/mocks/curl --form x -o /tmp/t1c http://x; [[ $? -eq 0 ]]'''
    exit_code: 0
  - cmd: 'bash -c ''rm -f /tmp/t1d; MOCK_CURL_STDOUT=body tests/mocks/curl -o /tmp/t1d http://x; [[ -s /tmp/t1d ]]'''
    exit_code: 0
  - cmd: 'bats -c tests/setup_env/mocks_curl.bats'
    exit_code: 0
max_retries: 3
files_touched:
  - tests/mocks/curl
  - tests/setup_env/mocks_curl.bats
depends_on: []
```

**Files:** `tests/mocks/curl` (rewrite), `tests/setup_env/mocks_curl.bats` (new).

**Why this is first:** Group C cannot be tested without it. Today the mock derives its exit solely from `MOCK_CURL_EXIT` and implements `-o` as bare `touch "${outfile}"`, so a _successful_ mocked fetch produces a zero-byte target — reproducing the production defect inside the harness with a green verdict.

**`-f` detection.** Production emits `curl -fsS`, not `curl -f`. Measured: an exact-token test does not fire; a `*-f*` substring test fires but also matches `--form`. Iterate `"$@"`, match `^-[a-zA-Z]+$` (a short-option cluster, which excludes `--long`), and test whether that token contains `f`.

**Precedence must be stated in the file, not discovered.** `MOCK_CURL_EXIT` wins when both are set — it is the existing, explicit knob and several suites depend on it. `MOCK_CURL_HTTP_STATUS` applies only when `MOCK_CURL_EXIT` is unset AND an `f`-bearing short cluster is present.

**On failure the mock must not write the target**, mirroring real curl's `-o` behaviour (spec M4: a 404 with `-o` leaves a pre-seeded file at its original 9 bytes).

**Steps:**

- [ ] Write `tests/setup_env/mocks_curl.bats` covering: `-fsS` + status 404 exits non-zero; `-sS` + status 404 exits 0; `--form` + status 404 exits 0; `-o` with `MOCK_CURL_STDOUT` writes non-empty; `-o` on a failed fetch leaves a pre-seeded target unchanged; `MOCK_CURL_EXIT=0` beats `MOCK_CURL_HTTP_STATUS=404`; both unset behaves as today (exit 0, target created).
- [ ] Run it, confirm it fails.
- [ ] Rewrite `tests/mocks/curl`. Keep the `MOCK_CALLS_FILE` log line first and the URL-pattern stdout dispatch unchanged.
- [ ] Run the new suite, confirm green.
- [ ] **Inertness proof:** run `make test` with both new variables unset and diff the `not ok` set against `/private/tmp/.../baseline-test.log`. Any delta means the shared mock moved under an existing suite — that is a blocker, not something to fix forward.
- [ ] Commit (`caveman:caveman-commit`).

**Interfaces:**

- Produces: `MOCK_CURL_HTTP_STATUS` (int, honoured only for `f`-bearing short clusters, subordinate to `MOCK_CURL_EXIT`); `-o <file>` now receives `MOCK_CURL_STDOUT` content on success and is left untouched on failure. Tasks 5 and 6 consume both.

---

### Task 2: Register the section and widen the summary name column

```yaml-task
id: 2
description: Add zsh-autosuggestions to _UPDATE_SECTION_ORDER after oh-my-zsh and widen all four render arms from %-16s to %-19s
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: 'bash -c ''source lib/update_summary.sh; [[ " ${_UPDATE_SECTION_ORDER[*]} " == *" oh-my-zsh zsh-autosuggestions "* ]]'''
    exit_code: 0
  - cmd: 'bash -c ''[[ "$(command grep -c "%-19s" lib/update_summary.sh)" -eq 4 ]]'''
    exit_code: 0
  - cmd: 'bash -c ''[[ "$(command grep -c "%-16s" lib/update_summary.sh)" -eq 0 ]]'''
    exit_code: 0
  - cmd: 'bats -c tests/setup_env/update_summary.bats'
    exit_code: 0
max_retries: 3
files_touched:
  - lib/update_summary.sh
  - tests/setup_env/update_summary.bats
depends_on: []
```

**Files:** `lib/update_summary.sh:5-8` (array), `:555`/`:559`/`:563`/`:567` (render arms), `tests/setup_env/update_summary.bats`.

**Why the column moves.** `zsh-autosuggestions` is 19 characters; the longest current name is `terraform-skill` at 15. Left at `%-16s`, every weekly summary on every machine gains one row three characters out of line — and it is the newest row, so it reads as the broken one. Nothing in the suite asserts summary padding; measured.

**Why the count assertions above are safe.** The ten existing count assertions (`update_summary.bats:407-409` and friends) seed their sections **by name**, and `_update_summary` `continue`s on any section with no `status_` file — so an unseeded array entry is invisible to the tally. The three ordering assertions (`:824`, `:830`, `:836`) are contiguous substrings all terminating at `rust`, before the insertion point. Both verified; see spec M5.

**Steps:**

- [ ] Add a test asserting `_UPDATE_SECTION_ORDER` contains `oh-my-zsh zsh-autosuggestions` contiguously.
- [ ] Add a test asserting a rendered row for a 19-character section name is not truncated and its reason column starts at a fixed offset.
- [ ] Run both, confirm they fail.
- [ ] Edit the array and all four `printf` arms.
- [ ] Run `bats tests/setup_env/update_summary.bats`, confirm green including the ten pre-existing count assertions.
- [ ] Commit.

**Interfaces:**

- Produces: a printable `zsh-autosuggestions` section name. Task 4 depends on this — a section recorded but absent from the array is tracked internally and never printed, with no error.

---

### Task 3: Delete the three dead `cd`-backs and make the subshells explicit

```yaml-task
id: 3
description: Convert the tfenv/oh-my-zsh/tpm brace groups to subshells and delete their cd-backs and rc temporaries
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: 'bash -c ''[[ "$(command grep -c "cd \"\${PERSONAL_GITREPOS}/\${DOTFILES}\" || return 1" lib/workflows.sh)" -eq 1 ]]'''
    exit_code: 0
  - cmd: 'bash -c ''[[ "$(command grep -c "{ cd \"\${HOME}" lib/workflows.sh)" -eq 0 ]]'''
    exit_code: 0
  - cmd: 'bats -c tests/setup_env/workflows.bats'
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched:
  - lib/workflows.sh
  - tests/setup_env/workflows.bats
depends_on: []
```

**Files:** `lib/workflows.sh:617-645`, `tests/setup_env/workflows.bats`.

**The `-eq 1` is measured, and the first draft of it was wrong.** The spec says "five `cd` guards", and writing `-eq 2` from that framing was the magic-number trap this skill warns about. Only **four** lines match the string `cd "${PERSONAL_GITREPOS}/${DOTFILES}" || return 1` — `:622`, `:632`, `:642`, `:664`. The fifth guard, `:662`, is `cd "${HOME}/.oh-my-zsh/custom/plugins/zsh-autosuggestions" || return 1`, a different target. So this task removes three of four and one remains for Task 4. Verified by running the gate on the base tree before writing it.

**Result shape** for each of the three blocks:

```bash
if [[ -d ${HOME}/.tfenv ]]; then
  _update_record_start "tfenv"
  printf "Updating tfenv\\n"
  ( cd "${HOME}/.tfenv" && git pull ) 2>&1 | tee "${_DOTFILES_RUN_TMPDIR}/err_tfenv"
  _update_record_end "tfenv" "${PIPESTATUS[0]}"
else
  _update_skip "tfenv" "not installed"
fi
```

The `local _tfenv_rc` / `_omz_rc` / `_tpm_rc` temporaries go with the `cd`-back — with nothing between the pipeline and `_update_record_end`, `${PIPESTATUS[0]}` reads inline, matching `aws`, `rust` and `cheat.sh`. Note `local x="${PIPESTATUS[0]}"` resets `PIPESTATUS` to `(0)` anyway (measured), so the temporaries were never a durable capture.

**Keep the `( )` with the deletion.** The isolation today is inherited from the `| tee`, not a property of the code; `( )` makes it the code's own so a future edit dropping the pipe cannot reintroduce a parent-scope `cd` with no `cd`-back after it.

**V4 — the cwd test.** Add: assert `$PWD` equal before and after a full mocked `run_update`, **invoked from a directory that is not the dotfiles repo**. From the repo root both versions end there and the case cannot discriminate. The case must **also assert `run_update` completed**, because one of the three pre-change failure paths (`cd`-back failing outright) aborts before the assertion and would otherwise read as a pass.

**Steps:**

- [ ] Write V4 in `tests/setup_env/workflows.bats`.
- [ ] Run it from a non-repo cwd, confirm it fails on the base tree — and confirm it fails on the `$PWD` assertion, not on an abort.
- [ ] Convert the three blocks; delete the three `cd`-backs and three `local _*_rc` lines.
- [ ] Run V4, confirm green. Run the full `workflows.bats`, confirm no regression.
- [ ] Commit.

**Interfaces:**

- Consumes: nothing.
- Produces: `run_update` no longer moves the parent's cwd in the tfenv/oh-my-zsh/tpm blocks. Task 4 removes the last two `cd` sites.

---

### Task 4: Wire `zsh-autosuggestions` as a reported section behind a `.git` guard

```yaml-task
id: 4
description: Subshell the zsh-autosuggestions block, guard on .git existence, record start/end, and add SKIP rows for all three absent branches
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: 'bash -c ''[[ "$(command grep -c "cd \"\${PERSONAL_GITREPOS}/\${DOTFILES}\" || return 1" lib/workflows.sh)" -eq 0 ]]'''
    exit_code: 0
  - cmd: 'bash -c ''[[ "$(command grep -c "_update_skip \"zsh-autosuggestions\"" lib/workflows.sh)" -eq 3 ]]'''
    exit_code: 0
  - cmd: 'bash -c ''command grep -q "\[\[ -e \${_zsh_autosug}/.git \]\]" lib/workflows.sh'''
    exit_code: 0
  - cmd: 'bash -c ''[[ "$(command grep -c "rev-parse --git-dir" lib/workflows.sh)" -eq 0 ]]'''
    exit_code: 0
  - cmd: 'bats -c tests/setup_env/workflows.bats'
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched:
  - lib/workflows.sh
  - tests/setup_env/workflows.bats
depends_on: [2, 3]
```

**Files:** `lib/workflows.sh:660-665` and the outer `_run_all` else at `:666-671`, `tests/setup_env/workflows.bats`.

**Result shape:** see spec Group C — sorry, Group B. Guard is `[[ -e ${_zsh_autosug}/.git ]]`, never `git rev-parse`.

**Why a filesystem test and not git plumbing** — this is the defect round-2 review found in round 1's own fix, and it is the reason for the fourth acceptance gate above. `rev-parse --git-dir` walks **upward**, and `~/.oh-my-zsh` is itself a checkout. A tarball install of the plugin nested inside it takes the _update_ arm; `git pull` then targets oh-my-zsh — which the `oh-my-zsh` section already pulled forty lines earlier in the same run, so HEAD has not moved and the row renders `[OK] zsh-autosuggestions no changes` forever. Silently wrong, where the guard existed to prevent a merely-visible wrong FAIL. `-e` also accepts the `.git`-as-file form used by submodules and linked worktrees, and touches no git plumbing so an exported `GIT_DIR` cannot reach it.

**The three SKIP reasons** (hence `-eq 3`): `"not installed"` (no directory), `"not a git checkout — reinstall to enable updates"` (directory without `.git`), `"flag not set"` (outer `_run_all` else). The middle reason names a remedy because that branch never self-heals — `5_general.zsh:44` fires on `[[ ! -d … ]]` only.

**The harness will fight three of these tests.** `load_mocks` puts `tests/mocks/` on `PATH` in `setup()`, and `tests/mocks/git:8-9` intercepts `rev-parse --git-dir` returning an env var with no stdout, while `rev-parse HEAD` prints nothing at all. For V1 and V8 use the selective-mock idiom at `workflows.bats:1936` — symlink every mock **except `git`** into a temp dir and prepend that — so real git runs for the snapshot. V3's middle case needs no such thing: the guard is a filesystem test, so fixture shape _is_ the condition.

**Steps:**

- [ ] V1: fixture plugin dir as a real `git init` repo (mocks stripped for git); assert the rendered summary contains a `zsh-autosuggestions` row **and** `[ -s "${_DOTFILES_RUN_TMPDIR}/pre_zsh-autosuggestions" ]`.
- [ ] V2: `git` mock returning 1 for `pull`; assert `status_zsh-autosuggestions` is `FAIL` and `run_update` exits non-zero.
- [ ] V3: three cases — no directory; bare `mkdir -p` directory; `_run_all=0`. Assert each SKIP reason string.
- [ ] V3b: fixture built as `git init "${HOME}/.oh-my-zsh"` plus a plain `mkdir -p` plugin dir inside it. Assert SKIP **and** that `MOCK_CALLS_FILE` contains no `git pull` for that path. This is the case that would have caught the `rev-parse` guard.
- [ ] V8: fixture git repo, advance `HEAD` by two commits between `record_start` and `record_end`; assert `result_zsh-autosuggestions` reads literally `2 commit(s)`. Must drive `_update_record_start` and must not inherit `update_summary.bats:793`'s `_update_git_diff` stub.
- [ ] Run all five, confirm they fail.
- [ ] Implement the block and the outer-else skip.
- [ ] Run them, confirm green.
- [ ] Commit.

**Interfaces:**

- Consumes: `_UPDATE_SECTION_ORDER` entry from Task 2; a `run_update` with no remaining tfenv/omz/tpm `cd`-backs from Task 3.
- Produces: `run_update` moves the parent's cwd nowhere. `V4` from Task 3 must still pass.

---

### Task 5: Rewrite the update-path cheat.sh fetches as one accumulating section

```yaml-task
id: 5
description: Fold the completion fetch into the cheat.sh section with an _rc accumulator, failure-only stderr markers, -fsS -o, and a non-empty check
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: 'bash -c ''[[ "$(command grep -c "curl https://cht.sh/:cht.sh > ~/bin/cht.sh" lib/workflows.sh)" -eq 1 ]]'''
    exit_code: 0
  - cmd: 'bash -c ''[[ "$(command grep -c "curl https://cheat.sh/:zsh > \"\${HOME}\"/.zsh.d/_cht" lib/workflows.sh)" -eq 1 ]]'''
    exit_code: 0
  - cmd: 'bash -c ''command grep -q "cheat.sh completion fetch failed" lib/workflows.sh'''
    exit_code: 0
  - cmd: 'bats -c tests/setup_env/workflows.bats'
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched:
  - lib/workflows.sh
  - tests/setup_env/workflows.bats
depends_on: [1]
```

**Files:** `lib/workflows.sh:647-659`, `tests/setup_env/workflows.bats`.

**Both count gates are `-eq 1`, not `-eq 0`, and both were corrected after running them.** The update and install paths use byte-identical fetch strings — `:162`/`:650` for the binary and `:172`/`:658` for the completion — so each grep returns **2** on the base tree and must return 1 after this task, with Task 6 taking it to 0. Writing `-eq 0` here would have made this task's gate unsatisfiable without doing Task 6's work inside it.

**Result shape:** see spec Group C. Outer condition is a **disjunction** of the two file guards, not a nesting — a machine with `~/.zsh.d/_cht` but no `~/bin/cht.sh` must still update its completion. Progress banners stay **outside** the subshell; failure markers go **inside** on stderr.

**Why both.** Banners inside consume two of the ten lines `_update_write_detail_from_err` renders as operator detail. Banners outside leave the detail anonymous — `curl -fsS` on a 404 emits `curl: (56) The requested URL returned error: 404`, naming neither URL nor file, so `[FAIL] cheat.sh` becomes unlocatable between two fetches. Failure-only markers satisfy both.

**`[[ -s … ]]` after each fetch, with `chmod` gated behind it.** `-f` keys on HTTP status, and `cht.sh` answers an unknown topic with HTTP 200 and an error body — so `-f` alone cannot distinguish a usable file from a degraded 200.

**Assert non-zero, never a specific curl exit code.** The same 404 yields 56 on macOS 8.7.1 and 22 on Linux 8.5.0 (measured, both platforms).

**Steps:**

- [ ] V5: target pre-seeded, `MOCK_CURL_HTTP_STATUS=404`; assert `status_cheat.sh` is `FAIL` and the target's content is unchanged. Record in the test's own comment that the "target intact" half discriminates `>` from `-o` and nothing more — the mock never writes the target on failure in any variant.
- [ ] V6: fail **only** the completion fetch; assert `detail_cheat.sh` contains `cheat.sh completion fetch failed` and **not** the binary marker.
- [ ] V7: successful fetch with `MOCK_CURL_STDOUT` set; assert `status_cheat.sh` is `OK` **and** `~/bin/cht.sh` is non-empty.
- [ ] Add a case for the disjunction: `~/.zsh.d/_cht` present, `~/bin/cht.sh` absent → completion still fetched.
- [ ] Run all four, confirm they fail.
- [ ] Implement the block.
- [ ] Run them, confirm green.
- [ ] Commit.

**Interfaces:**

- Consumes: `MOCK_CURL_HTTP_STATUS` and content-writing `-o` from Task 1.
- Produces: `err_cheat.sh` carries per-half failure markers on stderr; `cheat.sh` section covers both artifacts.

---

### Task 6: Fix the two install-path fetches

```yaml-task
id: 6
description: Apply -fsS -o to the install-path cht.sh and completion fetches, leaving chmod 750 as it is
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: 'bash -c ''[[ "$(command grep -c "curl https://cht.sh/:cht.sh > " lib/workflows.sh)" -eq 0 ]]'''
    exit_code: 0
  - cmd: 'bash -c ''[[ "$(command grep -c "curl https://cheat.sh/:zsh > " lib/workflows.sh)" -eq 0 ]]'''
    exit_code: 0
  - cmd: 'bash -c ''command grep -q "chmod 750 \"\${HOME}\"/bin/cht.sh" lib/workflows.sh'''
    exit_code: 0
  - cmd: 'bats -c tests/setup_env/workflows.bats'
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched:
  - lib/workflows.sh
  - tests/setup_env/workflows.bats
depends_on: [1, 5]
```

**Files:** `lib/workflows.sh:162`, `:171-173`, `tests/setup_env/workflows.bats`.

**Two different hazards, not one.** `:162` is unguarded and truncates like the update path. `:172` sits inside `if [[ ! -f ${HOME}/.zsh.d/_cht ]]` — it fetches **only when the file is absent**, so it can never truncate an existing one. Its hazard is the inverse: a 404 creates a **0-byte `_cht` that then satisfies the `! -f` guard forever**, so the install path never retries and the completion is permanently empty. `-fsS -o` fixes that too, because no file is created on failure.

**`chmod 750` at `:163` stays.** The third gate above pins it. An earlier spec revision harmonised it to the update path's `754` arguing "no argument on record for the group-execute bit differing" — group-execute is `r-x` in **both**; the delta is other-read, so that change would have made a network-downloaded `$HOME` executable world-readable with no defect behind it. Withdrawn. If the split matters it gets its own row.

**Steps:**

- [ ] Add a test: install path with `MOCK_CURL_HTTP_STATUS=404` and no pre-existing `~/.zsh.d/_cht` → assert `~/.zsh.d/_cht` does **not** exist afterwards (the never-retry fix).
- [ ] Add a test: install path binary fetch fails → `~/bin/cht.sh` unchanged if pre-seeded.
- [ ] Run both, confirm they fail.
- [ ] Apply `-fsS -o` at both sites. Do not touch `chmod 750`.
- [ ] Run them, confirm green.
- [ ] Commit.

**Interfaces:**

- Consumes: `MOCK_CURL_HTTP_STATUS` from Task 1.

---

### Task 7: Sync CLAUDE.md and the plan index

```yaml-task
id: 7
description: Record the new section, the SKIP reasons, the mock variables and the column width in CLAUDE.md, and set the plan index row to Done (docs-only, no behavior change)
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: 'bash -c ''command grep -q "zsh-autosuggestions" CLAUDE.md'''
    exit_code: 0
  - cmd: 'bash -c ''command grep -q "MOCK_CURL_HTTP_STATUS" CLAUDE.md'''
    exit_code: 0
  - cmd: 'bash -c ''command grep -q "2026-08-31-update-run-cd-guards" docs/superpowers/README.md'''
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched:
  - CLAUDE.md
  - docs/superpowers/README.md
depends_on: [1, 2, 3, 4, 5, 6]
```

**Files:** `CLAUDE.md`, `docs/superpowers/README.md`.

`tdd: not-applicable` — documentation only, no executable logic.

**CLAUDE.md needs, at minimum:** `zsh-autosuggestions` added to the `_UPDATE_SECTION_ORDER` coupling note; the three SKIP reasons; `MOCK_CURL_HTTP_STATUS` and the changed `-o` semantics in the mock-pattern section; the `%-19s` column; and a line under Test Seams recording that the plugin guard is a filesystem test **specifically because** `rev-parse --git-dir` walks upward past a nested non-clone and because `git -C` does not override an exported `GIT_DIR`.

**Steps:**

- [ ] Update CLAUDE.md.
- [ ] Set the plan index row to `Done`, link this plan file, and add the `> **Status: DONE**` banner at the top of this file.
- [ ] Commit.

---

## Self-Review

1. **Spec coverage.** Group A → T3. Group B → T2 + T4. Group C update path → T5, install path → T6. Mock changes → T1. V1/V2/V3/V3b/V8 → T4. V4 → T3. V5/V6/V7 → T5. V9 → T2's gate plus every task's `bats -c`. V10 → orchestrator's `make test`. Docs → T7. **No gaps.**
2. **Placeholder scan.** None.
3. **Type consistency.** `_zsh_autosug`, `_rc`, `MOCK_CURL_HTTP_STATUS`, `MOCK_CURL_STDOUT` used identically across T1/T4/T5/T6.
4. **YAML blocks.** Every task has one; every `cmd:` containing `": "` or embedded quotes is single-quoted per the colon-space rule. Run `make validate-plan` before committing.
5. **TDD `files_touched` includes the test file.** All six `tdd: required` tasks list both.
6. **Token budget.** Every block under 2KB.
7. **ADR significance.** No new Phase 3 gate, HOLD-capable check, storage choice or security guardrail. ADR-0027 already covers the exit contract this builds on. **No ADR task needed.**
8. **`files_touched` matches the prose.** Checked per task; T7 lists both files its body names, which is why it is `sonnet` and not `haiku`.

**Gate falsifiability — measured against the base tree, not asserted.** All eleven structural gates were run in a detached worktree at `cbe1e0bb` before dispatch. **Ten fail with exit 1** — a real failure, not a usage error (2/4/127), which is the distinction that separates a gate from a command that cannot run.

**One passes on the base tree, and it is not a defect: T6's `chmod 750` assertion is a _pin_, not a discriminator.** It asserts the mode does **not** change, guarding against the 754 harmonisation withdrawn from the spec, so it necessarily holds before the work as well as after. Do not count it as evidence that Task 6 did anything — Task 6's discriminating gates are its two `-eq 0` fetch counts, which do fail on base. A gate that proves work was *not* done is a different instrument from one that proves work *was*, and a task needs at least one of the latter.

Every structural gate names a construct that exists on the base tree today, verified by `command grep -c`: five `cd`-back lines (T3 `-eq 2`, T4 `-eq 0`), zero `%-19s` (T2 `-eq 4`), two `cht.sh` redirect fetches (T5 `-eq 1`, T6 `-eq 0`), zero `.git`-existence guards (T4). None can pass on an unmodified tree, and none exits non-zero for a usage reason.

**What wrong implementation would still pass?** For T4, a section that records but never snapshots — which is why V1 asserts `[ -s pre_zsh-autosuggestions ]` and V8 pins the literal `2 commit(s)`. For T5, a fetch that succeeds and writes nothing — which is why T1 must land first and V7 asserts non-empty content. Those are the two blind spots both review rounds identified, and each now has a case.
