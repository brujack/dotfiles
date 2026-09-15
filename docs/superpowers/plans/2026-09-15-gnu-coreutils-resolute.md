# GNU coreutils Precedence on Resolute — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On Ubuntu 26.04 (`RESOLUTE`) only, install GNU coreutils from linuxbrew and prepend its `gnubin` to interactive `PATH`, so `sort -u` stops collating `py.test` and `pytest` as equal and pyenv regains its `pytest` shim.

**Architecture:** Two production edits and one observability arm. `_install_ubuntu_brew_packages` gains a `RESOLUTE`-gated `brew_install_formula coreutils` that feeds the existing `_failed` accumulator, so a failure flows through the established rc-2 partial-success contract rather than aborting a bootstrap. `.config/.zshrc.d/6_path.zsh` gains a **prepend** inside its `LINUX` block behind a `_OVERRIDE_GNUBIN_LINUX` seam. A new `_doctor_check_gnu_coreutils` arm asserts the resolved **provider** (`sort --version` contains `GNU`), not directory existence, so something reads the fix after the session that installed it.

**Tech Stack:** bash (`lib/`), zsh (`.config/.zshrc.d/`), bats, Homebrew on Linux, pyenv.

**Spec:** `docs/superpowers/specs/2026-09-13-gnu-coreutils-precedence-resolute-design.md` at `88fb2b69`. It has been through `brainstorming` Step 8 (three lenses) and Step 9 (operator dispositioned all six findings) — the Adversarial Spec Review Gate is **satisfied**; do not re-run it.

---

## Global Constraints

- **Never put `make test` in a task's `acceptance:` block.** This repo's suite runs ~768s, past the Bash tool's 600s cap, so the harness backgrounds it and a backgrounded command never wakes a subagent. Every task below carries scoped commands instead. **The orchestrator runs `make test` once, uncontended, after Task 5 — the last code-touching task.**
- All tasks are `model: sonnet`. `haiku` is undispatchable in this repo: the fixed preamble measures ~166k tokens against a 200k window, so a task can pass the plan validator's haiku scope guard and still be impossible to dispatch.
- Work happens in the worktree `/Users/bruce/git-repos/personal/dotfiles-coreutils`, branch `feat/gnu-coreutils-resolute`, base `origin/master` `c978b1ff`. Never the main checkout.
- `path=(${dir} $path)` — **prepend, never `path+=`**. Every other entry in the `LINUX` block appends, which lands behind `/usr/bin` (index 10 on `claude`) and would be inert while still reading as correct.
- Absence assertions are paired with a positive control. Three of the spec's own verdicts are satisfied equally by a dead mechanism; the file already carries the pattern at `tests/zshrc.d/unit.bats:407` (`NO_GNUBIN` plus a non-empty `${#path}`) and `:492` (`NO_GNUBIN` plus `HAS_LOCAL_BIN`).
- `_DOCTOR_FAIL` (a count, `lib/helpers.sh:42`) and `_DOCTOR_FAILED` (a 0/1 flag, `:43`) are distinct. `CLAUDE.md` records that tests confuse them. Any new doctor test asserts the one it means and says which.
- Commit messages come from `caveman:caveman-commit`. Trailers, final paragraph, `Key: value` lines only:
  `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>` and
  `Claude-Session: https://claude.ai/code/session_011vMKkiyyQXgXGYwRf64WRm`.

### Measured baselines — taken on the Mac Studio, in a worktree of the base `c978b1ff`, before any task ran

Every acceptance gate below was proven reachable at this state. Conditions stated because this plan changes none of them:

| command                                          | rc  | duration | result                                                              |
| ------------------------------------------------ | --- | -------- | ------------------------------------------------------------------- |
| `make lint`                                      | 0   | 22s      | clean                                                               |
| `bats tests/zshrc.d/unit.bats`                   | 0   | 13s      | 56 ok, 0 not ok                                                     |
| `bats tests/setup_env/linux_ubuntu.bats`         | 0   | 81s      | 103 ok, 0 not ok                                                    |
| `bats tests/setup_env/unit.bats`                 | 0   | 93s      | 201 ok, 0 not ok                                                    |
| `printf 'py.test\npytest\n' \| sort -u \| wc -l` | 0   | —        | **2** (`/usr/bin/sort`, `2.3-Apple (199)`); also 2 under `LC_ALL=C` |

**That last row is why Task 4 does not assert on the ambient `sort`.** This machine's BSD `sort` already returns 2, so an ambient assertion would pass for a reason that says nothing about the fix — a check answering about a different artifact than the one under test. Task 4 resolves `sort` _through_ the prepend and asserts the provider string.

---

## Verification Planning

**Session-level verification, above the per-task gates.**

1. **The suite, once, uncontended, after Task 5:**

   ```bash
   cd /Users/bruce/git-repos/personal/dotfiles-coreutils && make test < /dev/null
   ```

   Expected: rc 0. Baseline on `c978b1ff` is 1714 ok / 0 not ok; this plan adds roughly 12 tests, so expect ~1726 ok and 0 not ok. **A skip does not reduce that count**: measured on bats 1.14.0, a skipped test prints `ok N <name> # skip <reason>`, so `grep -c '^ok '` includes it. Task 4's collation case runs on any machine carrying a GNU coreutils gnubin — every mac, via the untagged `brew "coreutils"` in `Brewfile` — and skips on CI, which has none.

2. **The behavioural acceptance, on `claude`, after the branch merges and `setup_env.sh -t setup` has run there.** The spec's acceptance line names no actor, and that omission is load-bearing: `6_path.zsh` is sourced by **interactive zsh only**, so `ssh claude '<cmd>'` and `bash -lc` both answer about a shell that never saw the prepend. Run it as an interactive zsh:

   ```bash
   ssh claude "zsh -i -c 'pyenv rehash && test -x ~/.pyenv/shims/pytest && pyenv versions --executables | grep -cx pytest'"
   ```

   Expected: the shim exists and the count is **1**. Measured pre-fix on that box: 148 names, `pytest` = 0; with C collation forced, 149 names and `pytest` = 1.

3. **Edge cases that must be exercised to be confident**, each owned by a task below:
   - The `RESOLUTE` gate in **both** directions — installs on 26.04, absent on 24.04 (Task 2). The absent case is paired with a positive control proving the function ran at all.
   - The prepend is a prepend — `path[1]`, not membership (Task 3).
   - Repeated sourcing does not duplicate the entry (Task 3; `typeset -U path` at `6_path.zsh:1` is the mechanism, and the test pins it).
   - `_gnubin_linux` does not leak into the interactive shell (Task 3).
   - The provider, not the directory (Tasks 4 and 5). A `gnubin` directory can exist while `PATH` still resolves uutils; directory existence is what Task 3's tests already cover and is not the property that matters.

**What none of these can see, stated rather than discovered:** nothing asserts that `pyenv-versions` itself still pipes through `sort`. If upstream pyenv changes that line, every check here keeps passing and the fix becomes decorative. No cheap instrument exists for it; recorded as a known blind spot rather than papered over.

---

## Task 1: Stop the macOS gnubin tests inheriting `LINUX`

```yaml-task
id: 1
description: Fix OS-variable inheritance in the four macOS gnubin tests (test-hygiene only; the failing-first cycle for the behaviour lands in Task 3, which is where these tests become discriminating)
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: bats tests/zshrc.d/unit.bats
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched:
  - tests/zshrc.d/unit.bats
depends_on: []
```

**Files:** `tests/zshrc.d/unit.bats` — the four `@test` blocks at `:355`, `:372`, `:389`, `:407`.

Each currently does `export MACOS=1` inside its `zsh -c` and never unsets `LINUX`. `.config/.zshrc.d/1_init.zsh:3` exports `LINUX=1`, which reaches bats grandchildren, so on a Linux box those four run with **both** set. `CLAUDE.md`'s Testing Rules already forbid this: `load_setup_env()` does not set OS vars, and a test whose outcome depends on OS detection must set them itself.

In each of the four, add `unset MACOS LINUX` inside the `zsh -c` body, immediately before `export MACOS=1`. Do not touch anything else in those tests. `:389` and `:407` get the same treatment even though only `:355`, `:407` and `:492` were measured RED on the target box. `:372` is byte-identical in construct to `:355`, so it fails the same way. `:389` is different, and is fixed prophylactically rather than because it breaks: it asserts `grep -c` equals 1 against its own fixture dir and never reads `path[1]`, so a prepend of some other directory cannot move it. Fix it anyway — leaving one instance of the construct behind reinstates the defect for whoever edits it next.

**This must land before Task 3.** With Task 3's block present, `:355`, `:407` and `:492` go RED on `claude`; `scripts/pre-push` runs `make test`, so the branch would otherwise block every push from that box.

**Mutation control — required, because this task's own gate cannot discriminate.** On the Studio the suite is green before and after, since no Linux gnubin block exists yet and the `LINUX` arm only ever appends. Prove the fix is load-bearing rather than cosmetic:

```bash
# 1. RED: temporarily append Task 3's prepend into the LINUX block of a scratch
#    copy of 6_path.zsh, pointed at a directory that exists, and run the four
#    tests with LINUX=1 exported. Record the "not ok" lines.
# 2. Apply this task's fix.
# 3. Re-run the same construction. The same four must be ok.
# 4. `git checkout .config/.zshrc.d/6_path.zsh` — the block is Task 3's to add.
```

Report both outputs in the task result. A green run that never saw the block is not evidence.

**Interfaces:**

- Consumes: nothing.
- Produces: four `@test` bodies that begin `unset MACOS LINUX` before setting `MACOS=1`. Task 3 mirrors this shape in its four new Linux tests (`unset MACOS LINUX`, then `export LINUX=1`).

---

## Task 2: `RESOLUTE`-gated coreutils install

```yaml-task
id: 2
description: Install GNU coreutils from linuxbrew on RESOLUTE only, feeding failure into the existing _failed accumulator
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: bats tests/setup_env/linux_ubuntu.bats
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched:
  - lib/linux_ubuntu.sh
  - tests/setup_env/linux_ubuntu.bats
depends_on: []
```

**Files:** `lib/linux_ubuntu.sh`, `tests/setup_env/linux_ubuntu.bats`.

Add to `_install_ubuntu_brew_packages`, immediately after `brew_install_cask codex || _failed+=(codex)` (~`:591`) and before the `if [[ -n ${HAS_DEVTOOLS} ]]` block. Match the guarded-call shape already used for `shfmt` (`:583`), `snyk` (`:586`) and `codex` (`:591`):

```bash
  # Ubuntu 26.04 ships uutils coreutils. Its `sort -u` collates `py.test` and
  # `pytest` as equal under UTF-8 and drops one, so pyenv-versions:47 emits no
  # `pytest` shim and every bare-`pytest` Makefile target breaks. apt cannot make
  # GNU the provider -- build-essential pins coreutils-from-uutils by name -- so
  # the formula is the route. 24.04 and earlier already ship GNU; gate to avoid
  # installing a second copy on machines that do not need it.
  if [[ -n ${RESOLUTE} ]]; then
    brew_install_formula coreutils || _failed+=(coreutils)
  fi
```

`|| _failed+=(coreutils)` rather than `|| return 1` is deliberate and matches the file's tri-state contract documented in `CLAUDE.md`: 0 clean, 1 hard failure, 2 partial success with the failed packages named. A bare guard would kill a whole fresh-machine bootstrap over one briefly-unavailable upstream formula.

**Tests** — write the failing test first, one behaviour at a time. The suite's `setup()` already provides `MOCK_CALLS_FILE`, `load_mocks` and `refute_grep` (`tests/helpers/common.bash:27`).

1. `RESOLUTE` set → `brew install coreutils` appears in `${MOCK_CALLS_FILE}`. Set `export RESOLUTE=1; unset NOBLE` explicitly — `load_setup_env` does not set OS vars.
2. `RESOLUTE` unset (`export NOBLE=1; unset RESOLUTE`) → `refute_grep "brew install coreutils" "${MOCK_CALLS_FILE}"`. **Pair this absence with a positive control in the same test**: also `grep -q "brew install shfmt" "${MOCK_CALLS_FILE}"`, so a function that never ran cannot satisfy it. Without the control this test passes identically against a deleted function body.
3. Failure feeds the accumulator: override `brew_install_formula() { [[ "$1" == "coreutils" ]] && return 1; return 0; }` with `RESOLUTE=1`, assert `status -eq 2`, that the output contains `coreutils`, and that it contains `1 package(s) failed`. Named, not merely counted — mirror the existing test at `:297`, whose comment explains why the shared `MOCK_BREW_INSTALL_EXIT` knob is too blunt here.

Expected after this task: 106 ok, 0 not ok.

**Interfaces:**

- Consumes: `brew_install_formula <name>` (returns non-zero on failure), the `_failed` array, and `RESOLUTE` from `lib/detect_env.sh`.
- Produces: the formula `coreutils` installed at `/home/linuxbrew/.linuxbrew/opt/coreutils`, whose `libexec/gnubin` is the directory Task 3 prepends.

---

## Task 3: Prepend the Linux gnubin to `PATH`

```yaml-task
id: 3
description: Prepend the linuxbrew coreutils gnubin inside 6_path.zsh's LINUX block behind a _OVERRIDE_GNUBIN_LINUX seam, with four tests mirroring the macOS gnubin four
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: bats tests/zshrc.d/unit.bats
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched:
  - .config/.zshrc.d/6_path.zsh
  - tests/zshrc.d/unit.bats
depends_on: [1]
```

**Files:** `.config/.zshrc.d/6_path.zsh` (the `LINUX` block spans `:48-72`), `tests/zshrc.d/unit.bats`.

Add inside the `LINUX` block, immediately after the `/home/linuxbrew/.linuxbrew/sbin` append (so it reads beside the other linuxbrew entries) and before `if [[ ${UBUNTU} ]]`:

```zsh
  # GNU coreutils ahead of uutils on 26.04. uutils' `sort -u` collates `py.test`
  # and `pytest` as equal and drops one, so pyenv-versions:47 leaves no `pytest`
  # shim. PREPEND, never `path+=` -- every other entry in this block appends,
  # which lands behind /usr/bin (index 10 on claude) and would be inert while
  # still reading as correct. `typeset -U path` at :1 handles the dedup.
  _gnubin_linux="${_OVERRIDE_GNUBIN_LINUX:-/home/linuxbrew/.linuxbrew/opt/coreutils/libexec/gnubin}"
  [[ -d ${_gnubin_linux} ]] && path=(${_gnubin_linux} $path)
  unset _gnubin_linux
```

`unset` sits on its own line, outside the `&&`, so it runs whether or not the directory existed — the macOS loop at `:41-45` does the same.

The block is **not** gated on `RESOLUTE`. It is release-blind by design, and the `-d` test is the gate. Note the directory is not *only* creatable by Task 2 — a hand install, or a future non-RESOLUTE install, creates it too. The consequence is benign (brew's GNU coreutils ahead of the distro's GNU coreutils is a version change, not a semantic one), and the real argument is that `-d` verifies the artifact the code actually needs rather than deriving the gate from a release string. Say this in review if asked — the install half is release-based and the `PATH` half is not, and that asymmetry is deliberate.

**Tests** — one at a time, RED then GREEN. Mirror the macOS four, each beginning `unset MACOS LINUX` then `export LINUX=1`, with both macOS seams pointed at `/nonexistent/...` so the macOS arm cannot interfere:

1. **present** → `path[1]` equals the fixture dir. Asserting `path[1]`, not membership, is what makes this a prepend test rather than a presence test.
2. **absent** → seam at `/nonexistent/coreutils-gnubin`, print `NO_GNUBIN`. **Pair with a positive control**: also assert a known Linux entry landed (`HOME/.local/bin`, the `:492` pattern), so a `6_path.zsh` that failed to source cannot satisfy it.
3. **deduped** → source three times, `grep -c` the fixture dir in `$path` equals 1.
4. **no leak** → `${_gnubin_linux:-unset}` prints `unset`.

**Also amend the existing test at `:492`** ("adds no gnubin entry under LINUX, but still adds a known Linux path"). It asserts `NO_GNUBIN` under `LINUX=1` and matches `*gnubin*`, so it goes RED on any box where the real coreutils gnubin exists. Add `export _OVERRIDE_GNUBIN_LINUX='/nonexistent/coreutils-gnubin'` to its `zsh -c` body. Its meaning shifts from "there is no Linux gnubin" to "the seam is honoured", which is the true claim now; update its comment to say so.

Expected after this task: 60 ok, 0 not ok.

**Interfaces:**

- Consumes: `LINUX` from `1_init.zsh`; the directory Task 2 installs.
- Produces: the seam `_OVERRIDE_GNUBIN_LINUX`, default `/home/linuxbrew/.linuxbrew/opt/coreutils/libexec/gnubin`. Task 4 drives the same seam; Task 6 documents it as a Test Seams row.

---

## Task 4: A collation test that can actually fail

```yaml-task
id: 4
description: Add the one check that fails if the mechanism is dead — sort -u through the prepend must keep both py.test and pytest, asserted against the GNU provider string
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: bats tests/zshrc.d/unit.bats
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched:
  - tests/zshrc.d/unit.bats
depends_on: [3]
```

**Files:** `tests/zshrc.d/unit.bats`, appended after Task 3's four.

Every other verdict this change produces is an absence assertion — satisfied equally by a working mechanism and by one that never ran. This is the only check whose failure mode is the defect itself:

```bats
@test "6_path.zsh's Linux gnubin supplies a sort that distinguishes py.test from pytest" {
  # The defect, directly: uutils `sort -u` collates py.test and pytest as equal
  # and drops one, so pyenv-versions:47 emits no pytest shim. GNU keeps both.
  #
  # Resolve sort THROUGH the prepend, never from the ambient PATH. This machine's
  # /usr/bin/sort is BSD and already answers 2 (measured, 2.3-Apple (199)), so an
  # ambient assertion would pass for a reason that says nothing about the fix.
  # The provider assertion is what makes the 2 mean something.
  # First gnubin whose sort is executable. NEVER /usr/bin -- that is the ambient
  # shape this test exists to avoid. Skip only when no prefix carries one.
  local _gnubin=""
  for _c in /home/linuxbrew/.linuxbrew/opt/coreutils/libexec/gnubin \
            /opt/homebrew/opt/coreutils/libexec/gnubin \
            /usr/local/opt/coreutils/libexec/gnubin; do
    [[ -x "${_c}/sort" ]] && { _gnubin="${_c}"; break; }
  done
  [[ -n ${_gnubin} ]] || skip "no GNU coreutils gnubin (checked linuxbrew, /opt/homebrew, /usr/local)"
  run zsh -c "
    export PATH=/usr/bin:/bin:/usr/sbin:/sbin
    unset MACOS LINUX
    export LINUX=1
    export _OVERRIDE_GNUBIN_LINUX='${_gnubin}'
    export _OVERRIDE_GNUBIN_ARM='/nonexistent/gnubin-arm'
    export _OVERRIDE_GNUBIN_INTEL='/nonexistent/gnubin-intel'
    source '${ZSHRC_D}/6_path.zsh' 2>/dev/null
    whence -p sort
    sort --version | head -1
    printf 'py.test\npytest\n' | sort -u | wc -l | tr -d ' '
  "
  [ "$status" -eq 0 ]
  [[ "$(printf '%s\n' "$output" | head -1)" == *GNU* ]]
  [ "$(printf '%s\n' "$output" | tail -1)" -eq 2 ]
}
```

**The `skip` is honest, but not reported the way this plan first claimed.** Measured on bats 1.14.0, a skipped test prints `ok N <name> # skip <reason>` — a reader sees the skip, a `^ok` count does not. It discriminates only on `claude` after Task 2 has installed the formula — which is exactly the acceptance step in Verification Planning, not a gate. Do not replace the skip with an ambient-`sort` assertion to make it run everywhere; that converts a real check into one that agrees with BSD `sort` about nothing.

Expected after this task: 61 ok, 0 not ok, and **0 skipped on a mac** — the guard finds the Homebrew gnubin and the test runs. CI skips, having none.

**Interfaces:**

- Consumes: `_OVERRIDE_GNUBIN_LINUX` from Task 3.
- Produces: nothing downstream.

---

## Task 5: Doctor arm asserting the GNU provider

```yaml-task
id: 5
description: Add _doctor_check_gnu_coreutils asserting sort --version contains GNU, gated on RESOLUTE, wired into run_doctor and stubbed in the three end-to-end run_doctor tests
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: bats tests/setup_env/unit.bats
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched:
  - lib/helpers.sh
  - tests/setup_env/unit.bats
depends_on: [2, 3]
```

**Files:** `lib/helpers.sh`, `tests/setup_env/unit.bats`.

Spec finding F3: nothing reads this fix after the session that ships it. Install failure degrades to a WARN, the `PATH` arm has no `else`, and the acceptance line writes to no file. This arm is the reader.

Define `_doctor_check_gnu_coreutils` after `_doctor_check_github_mcp` (which ends ~`:803`), and wire it into `run_doctor` after the `_doctor_check_github_mcp` line (`:475`), before the two cadence arms:

```bash
_doctor_check_gnu_coreutils() {
  # 26.04 ships uutils, whose `sort -u` collates py.test and pytest as equal and
  # drops one, leaving pyenv with no pytest shim. Earlier Ubuntu and macOS ship
  # GNU already, so there is nothing here to check on them.
  [[ -n ${RESOLUTE} ]] || return 0
  printf "\nGNU coreutils:\n"
  # The PROVIDER, not the directory. A gnubin directory can exist while PATH
  # still resolves uutils -- directory existence is what the zshrc.d tests
  # already cover, and it is not the property that matters.
  local _ver
  _ver="$(sort --version 2>/dev/null | head -1)"
  if [[ "${_ver}" == *GNU* ]]; then
    doctor_pass "sort is GNU (${_ver})"
  else
    doctor_fail "sort" "not GNU (${_ver:-no --version output}) — pyenv will drop the pytest shim; run: setup_env.sh -t setup"
  fi
}
```

`doctor_fail` rather than `doctor_warn`, on the `_doctor_check_profile` precedent (`:485`): a real gap with a one-line remedy should name itself loudly on a machine's first run, not blend into the report. It sets `_DOCTOR_FAILED=1`, so `run_doctor` exits 1 on an unprovisioned 26.04 box — which is the correct answer to "is this machine healthy".

**Tests.** `_DOCTOR_FAIL` is a count and `_DOCTOR_FAILED` is a 0/1 flag; assert the one you mean and say which in the test name or a comment. Drive `sort` through a shim directory holding **only** a `sort` stub, prepended to `PATH` — never by stripping a `PATH` entry, which takes `git`, `make` and the rest of the toolchain with it.

1. `RESOLUTE` unset → the function returns 0 and prints nothing. **Pair with (2) as the positive control** — on its own this passes against a deleted function.
2. `RESOLUTE=1`, stub `sort` printing `sort (GNU coreutils) 9.5` → output contains `[PASS]`, `_DOCTOR_FAILED` is 0.
3. `RESOLUTE=1`, stub printing `sort (uutils coreutils) 0.2.2` → output contains `[FAIL]`, `_DOCTOR_FAILED` is 1.
4. `run_doctor` calls the new arm — mirror the existing `run_doctor calls _doctor_check_github_mcp` test at `:993`.

**Then add `_doctor_check_gnu_coreutils() { :; }` to all three existing end-to-end stub blocks** — `:993`ff, `:1020`ff and `:1412`ff. Without it, on a `RESOLUTE` box those tests run the real check: the `1 warnings` assertion at `:1020` and the exit-code assertion at `:1412` both break. This is the same reason every other arm is stubbed there.

Expected after this task: 206 ok, 0 not ok.

**Orchestrator, after this task and before Task 6:** run `make test < /dev/null` once, uncontended, from the worktree. Expect rc 0, ~1726 ok, 0 not ok; a skip prints as an `ok ... # skip` line and does not reduce that count. This is the plan's single aggregate gate.

**Interfaces:**

- Consumes: `doctor_pass` (`:46`), `doctor_fail` (`:51`), `_DOCTOR_FAILED` (`:43`), `RESOLUTE`.
- Produces: `_doctor_check_gnu_coreutils`, wired into `run_doctor`'s arm list.

---

## Task 6: ADR-0031 and docs

```yaml-task
id: 6
description: Write ADR-0031 recording the release-gated install against a release-blind PATH edit, index it, and document the new seam in CLAUDE.md (docs-only, no behaviour change)
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: 'grep -qE "Status.*Accepted" docs/adr/0031-gnu-coreutils-precedence-on-resolute.md'
    exit_code: 0
  - cmd: 'grep -qE "\[0031\]\(0031-.*\.md\)" docs/adr/README.md'
    exit_code: 0
  - cmd: 'grep -q "_OVERRIDE_GNUBIN_LINUX" CLAUDE.md'
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched:
  - docs/adr/0031-gnu-coreutils-precedence-on-resolute.md
  - docs/adr/README.md
  - CLAUDE.md
depends_on: [3, 5]
```

**Files:** a new `docs/adr/0031-gnu-coreutils-precedence-on-resolute.md`, its index row, and `CLAUDE.md`.

`repo-structure.md` names structural patterns and platform-gating decisions as ADR-significant, and the spec agrees one is warranted. Follow the Nygard shape of any existing ADR in that directory — Context, Decision, Consequences, Related — and copy the `Status` line's exact rendering from a peer file rather than from this plan's gate pattern, which is deliberately tolerant.

Record at minimum:

- **Why not apt.** `build-essential` pins coreutils-from-uutils by name, so apt cannot make GNU the provider. Homebrew is the only route that leaves the base system intact.
- **The asymmetry.** The install is release-gated (`RESOLUTE`); the `PATH` edit is release-**blind** and gated only on `-d`. Both are deliberate; a reader will otherwise "fix" the second to match the first.
- **What the install does beyond the prepend.** `coreutils.rb` sets `no_conflict` empty only on macOS; on Linux a 26-name list gets **unprefixed** symlinks into `linuxbrew/bin`, already at `PATH` index 5 ahead of `/usr/bin` at 10. So 26 binaries change provider at **install** time, independent of this change's `PATH` edit. Repo-wide impact measured: exactly one live executable call site, `lib/linux_ubuntu.sh:164`'s `sha256sum -c -` rustup signature gate, which `tests/setup_env/linux_ubuntu.bats:358-360` deliberately does not mock. `sort` is not in that list, which is why the prepend is still required.
- **The rejected alternative and its real reason.** `LC_ALL=C` was declined for **CI parity**, not by preference: `claude`'s `pre-push` gate and CI currently disagree across 104 binaries, which is `tdd.md` pitfall G.
- **The accepted cost.** The prepend lands at `PATH` index 1, ahead of four pyenv/rbenv shim directories. Measured: **0 collisions** between 164 shim names and 104 gnubin names, with a positive control (a seeded name returns through `comm`) so the zero discriminates. Nothing re-runs that check, so a future pyenv entry point sharing a coreutils name would shadow silently — record it as a known cost.

**`CLAUDE.md`:** add `_OVERRIDE_GNUBIN_LINUX` to the Test Seams section beside the existing `_OVERRIDE_GNUBIN_ARM`/`_OVERRIDE_GNUBIN_INTEL` entry, stating that the real directory exists on any provisioned `claude`, so a test that forgets the seam short-circuits the `-d` guard and silently asserts nothing. Extend the "Homebrew `make` gnubin prepend" bullet under Key Conventions to cover the Linux coreutils case and repeat the prepend-not-append rule there.

**Do not add `make check-agent-guidance` to this task's gates.** It compares against `.cursor/rules/global-claude-standards.mdc`, which is gitignored and exists only in the main checkout, so it fails in a worktree on the unchanged base — a plan defect, not an implementation one.

**Interfaces:**

- Consumes: the seam name and default from Task 3; the doctor arm name from Task 5.
- Produces: `docs/adr/0031-gnu-coreutils-precedence-on-resolute.md`, cited by the PR body.

---

## Plan index

The spec's row in `docs/superpowers/README.md` (line 141) is flipped from `Pending` to `In Progress` and pointed at this plan file in the same commit that adds it — that is Phase 1 bookkeeping, not a task. The `In Progress` → `Done` flip and the `> **Status: DONE**` banner on this file land **on master after the PR merges**, per `git-workflow.md`, and are listed below rather than scheduled as a branch task.

## Post-merge

- [ ] Flip the index row to `Done`; add `> **Status: DONE**` to the top of this plan file, naming the PR and merge SHA. On master, not in the worktree.
- [ ] Run `setup_env.sh -t setup` on `claude`, then the acceptance command from Verification Planning §2 under `zsh -i -c`.
- [ ] Record CI's `bash-coverage` figure (gate floor 91%) in the PR body. A local run is a preview and must be labelled as one.
