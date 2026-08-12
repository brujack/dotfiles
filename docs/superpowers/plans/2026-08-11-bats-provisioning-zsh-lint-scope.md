# bats Provisioning Parity and `zsh -n` Lint Scope Implementation Plan

> **Status: DONE**

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give macOS the same unconditional bats provisioning Linux already has, point `zsh -n` at the ten files zsh actually interprets, and make a missing `bats-core` visible to `-t update`.

**Architecture:** `install_bats` becomes a platform dispatcher mirroring the existing `install_zsh` shape (`lib/helpers.sh:254`), with a new macOS arm and the Linux body renamed. `make lint` gains a second derived file list, `ZSH_FILES`, and `zsh -n` moves off the 36 bash files onto it. Removing one Brewfile tag lets the existing drift check report the gap on cadence.

**Tech Stack:** bash 5, GNU Make 3.81, bats-core, shellcheck 0.11.0, Homebrew, apt.

**Spec:** [`2026-08-11-bats-provisioning-zsh-lint-scope-design.md`](../specs/2026-08-11-bats-provisioning-zsh-lint-scope-design.md) — reviewed across three lens rounds, final at `93a6d4f`.

## Global Constraints

- **No `command -v` guards** are added for `bats` or `zsh`. `make lint` and `make test` stay fail-closed.
- **Ten zsh files**, not eight or nine: `.zshrc`, `.zprofile`, seven `.config/.zshrc.d/*.zsh`, `bruce.zsh-theme`. The pathspec is `'*.zsh' '*.zsh-theme' '.zshrc' '.zprofile'`.
- **The `print-%` recipe must quote its argument** — `@printf '%s\n' "$($*)"`. Unquoted, an empty variable emits nothing and two empty sets compare equal. Verified on GNU Make 3.81.
- **No `run_update` step for bats.** Provisioning is Task 3's job, visibility is Task 2's. Installing on the cadence path was specified and rejected; see spec §A.
- **The call-site guard is `MACOS || LINUX`**, never narrowed to `UBUNTU`. `install_bats_linux` gains no distro check.
- Shell standards per `~/.claude/standards/shell.md`: `#!/usr/bin/env bash`, no `set -e`, `[[ ]]`, `${VAR}`, `printf`, `|| return 1` propagation, sourcing guard as the **last** line of any lib file.
- Every commit message via `caveman:caveman-commit`.

## Baseline (measured 2026-08-11, at `93a6d4f`)

| Quantity                          | Value                                                     | Command                                                                                     |
| --------------------------------- | --------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| `make lint`                       | rc 0, 36 `bash OK` + 36 `zsh OK` lines, all on bash files | `make lint`                                                                                 |
| Tracked zsh files                 | 10                                                        | `git ls-files '*.zsh' '*.zsh-theme' '.zshrc' '.zprofile' \| wc -l`                          |
| `zsh -n` over all 10              | all pass                                                  | `for f in $(git ls-files '*.zsh' '*.zsh-theme' '.zshrc' '.zprofile'); do zsh -n "$f"; done` |
| Existing `zsh -n` bats tests      | 7 (`.zshrc.d/1_init`..`7_final`)                          | `grep -c 'run zsh -n' tests/zshrc.d/unit.bats`                                              |
| Bash coverage (CI, authoritative) | 91%                                                       | `bash-coverage` CI job                                                                      |
| `make test`                       | **rc 0, 1274 ok, 0 not ok**                               | `make test`                                                                                 |
| `install_bats` references         | 9 sites, 4 files                                          | `grep -rn 'install_bats' lib/ tests/ setup_env.sh`                                          |

**These figures were measured under the configuration this plan changes, and that is stated deliberately.** The 36/36 lint line counts and the 7-test count are _before_ numbers used to size the work; they are not acceptance targets. Every acceptance gate below states its own post-change expectation.

## Session-level verification

Run after Task 8, above and beyond the per-task gates:

1. `make test` — rc 0. Expect the bats count to exceed the CI floor of 840 and to have risen from the 1274 recorded on 2026-08-10.
2. `make lint` — rc 0, output carries exactly **ten** `zsh   OK` lines and **zero** `zsh` lines naming a `.sh`, `.bash`, or hook path.
3. `make bash-coverage` — ≥ 91%. New functions in `lib/macos.sh` and `lib/helpers.sh` enter the instrumented set; untested additions would drop below the CI floor and block auto-merge.
4. **Injection checks**, in this order, each followed by `git checkout -- <path>` and a clean `git status --short`:
   - zsh-invalid construct into `bruce.zsh-theme` → `make lint` emits `zsh  FAIL bruce.zsh-theme`.
   - bash construct zsh rejects into a tracked `.sh` → `make lint` rc 0.
   - bash-**invalid** construct into a tracked `.sh` → `make lint` emits `bash FAIL <path>`. Assert the line, not the exit code: shellcheck also rejects that file, so rc alone cannot tell whether the `bash -n` loop still runs.

   **Output format, pinned from `Makefile:45-46` — note the differing internal spacing:**

   ```
   printf "bash  OK  %s\n"   printf "bash FAIL %s\n"
   printf "zsh   OK  %s\n"   printf "zsh  FAIL %s\n"
   ```

   Task 4 changes these lines' surroundings. If a `printf` string itself changes, these checks and Task 4's gates go green while proving nothing — update both in the same commit.

   Inject into `bruce.zsh-theme`, never `.config/.zshrc.d/*.zsh` — those are symlinked live into `$HOME` and a broken one breaks every new interactive shell. `bruce.zsh-theme` is symlinked but not sourced (`ZSH_THEME="bruce"` is commented at `.config/.zshrc.d/3_oh_my_zsh.zsh:7`).

5. `./setup_env.sh -t doctor` — rc 0 on this machine, confirming no symlink or tool regression.

**Before closing the PR, on `office` (or `home-1`) — not on this machine.** Two read-only
commands settling facts §E depends on entirely; see the spec's **Open field measurements**
section for what each result means. Neither blocks implementation, and neither is measured yet.

```bash
ls -l ~/.dotfiles-update.log          # recent mtime => §E reaches the machine; stale => §E is inert
brew list --formula | wc -l           # 100+ formulae with bats-core absent refutes the stated cause
brew list bats-core
```

---

## Task 1: Add `install_bats_macos`

```yaml-task
id: 1
description: Add install_bats_macos to lib/macos.sh mirroring install_zsh_macos, with bats-core via Homebrew
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: bats tests/setup_env/macos.bats
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - lib/macos.sh
  - tests/setup_env/macos.bats
depends_on: []
parallel_group: wave-1
```

**Files:** `lib/macos.sh` (add function), `tests/setup_env/macos.bats` (add tests).

Model the new function on `install_zsh_macos` at `lib/macos.sh:115`, which is the established shape in this file. Place `install_bats_macos` immediately after it.

```bash
install_bats_macos() {
  if quiet_which bats; then
    log_info "bats already installed"
    return 0
  fi

  log_info "Installing bats via Homebrew"
  if ! command -v brew &> /dev/null; then
    install_homebrew
  fi
  if command -v brew &> /dev/null; then
    brew_install_formula bats-core || return 1
  else
    log_error "Failed to install Homebrew. Cannot install bats."
    return 1
  fi
  log_info "Installed bats"
}
```

The formula is `bats-core`; the binary is `bats`. `quiet_which` is `lib/helpers.sh:66`, `brew_install_formula` is `lib/helpers.sh:141`.

**Tests** — write each one RED first, confirm it fails for the right reason, then implement. Four cases, all required:

1. bats already present → returns 0, `brew_install_formula` never invoked (assert via `MOCK_BREW_*` state, not just rc).
2. brew present, bats absent → `brew install bats-core` reached, returns 0.
3. brew absent and `install_homebrew` fails to provide it → returns **1**, and the error names bats.
4. Idempotency — calling twice after a successful first call leaves the same state and returns 0 both times.

Per `tdd.md` E2 the failing branch must be inert: export `HOME="${BATS_TEST_TMPDIR}"` at `setup()` scope alongside the PATH mocks, so a regressed test cannot reach a real Homebrew.

**Interfaces:**

- Consumes: `quiet_which`, `brew_install_formula`, `install_homebrew`, `log_info`, `log_error` — all pre-existing.
- Produces: `install_bats_macos()` → 0 on success or already-present, 1 on failure. Task 3's dispatcher calls it.

---

## Task 2: Untag `bats-core` in the Brewfile

```yaml-task
id: 2
description: Remove the HAS_DEVTOOLS tag from Brewfile bats-core so the drift check reports it, guarded by an assertion against the real Brewfile
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: bats tests/setup_env/brewfile_drift.bats
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - Brewfile
  - tests/setup_env/brewfile_drift.bats
depends_on: []
parallel_group: wave-1
```

**Files:** `Brewfile` (line 15), `tests/setup_env/brewfile_drift.bats` (add one test).

Change `brew "bats-core"                             # [HAS_DEVTOOLS]` to drop the trailing tag. Keep the surrounding alignment convention of the file.

Why: `_brewfile_parse_section` (`lib/update_summary.sh`) skips any entry whose `# [CAP]` names an unset variable, and `office`/`home-1` are `mac_mini` profile (`gui printing`, no `HAS_DEVTOOLS`). So `bats-core` can never appear under `Missing (in Brewfile, not installed)` on exactly the machines that lack it. `brew bundle` ignores the tag entirely, so installation behaviour does not change.

**The test must read the real repository `Brewfile`, not a fixture.** A fixture-driven test cannot fail when someone re-adds the tag, and the fixture-shaped assertion already exists at `tests/setup_env/brewfile_drift.bats:398` ("OK untagged entries still checked regardless of capabilities") — duplicating it guards nothing. Nothing in the suite currently reads the real Brewfile's tags at all.

RED first: write the test against the tagged file, confirm it fails, then untag.

```bash
@test "_brewfile_parse_section: real Brewfile yields bats-core without HAS_DEVTOOLS" {
  unset HAS_DEVTOOLS
  run _brewfile_parse_section brew "${REPO_ROOT}/Brewfile"
  [ "$status" -eq 0 ]
  [[ "$output" == *"bats-core"* ]]
}
```

**Interfaces:**

- Consumes: `_brewfile_parse_section` (`lib/update_summary.sh`), unchanged.
- Produces: nothing other tasks depend on.

---

## Task 3: Rename to `install_bats_linux`, add the dispatcher, widen the call site

```yaml-task
id: 3
description: Rename install_bats to install_bats_linux, add an install_bats platform dispatcher, and widen the run_setup_user call site to MACOS or LINUX
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: bats tests/setup_env/
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - lib/linux_shared.sh
  - lib/helpers.sh
  - lib/workflows.sh
  - tests/setup_env/install_guards.bats
  - tests/setup_env/workflows.bats
depends_on: [1]
parallel_group: null
```

**Files:** three lib files, three test files.

1. `lib/linux_shared.sh:23` — rename `install_bats()` to `install_bats_linux()`. **Body unchanged**; it keeps `sudo -H apt-get install -y bats` and gains no distro check.
2. `lib/helpers.sh` — new dispatcher immediately after `install_zsh()` (which ends at `:260`), same shape:

```bash
install_bats() {
  if [[ -n ${MACOS} ]]; then
    install_bats_macos
  elif [[ -n ${LINUX} ]]; then
    install_bats_linux
  fi
}
```

3. `lib/workflows.sh:135-137` — change that block's guard **in place**, from `if [[ -n ${LINUX} ]]` to `if [[ ${MACOS} || ${LINUX} ]]`. It keeps its own block.

**Do not fold `install_bats` into the `install_zsh` block at `:131`.** That block's guard is `MACOS || UBUNTU`, a different platform set; sharing one block forces one guard on both functions. This is the specific error an earlier draft of the spec made.

**Do not narrow to `UBUNTU`.** `readonly UBUNTU=1` requires `/etc/os-release` `NAME` to be exactly `"Ubuntu"` (`lib/detect_env.sh:10-11`); narrowing would skip the call silently on other Linux while hooks still install at `:206`.

**Rename is a contract change for tests, and the enumeration is already done** — 9 sites, 4 files, measured 2026-08-11. `tests/setup_env/install_functions.bats` contains none despite being the natural place to look.

| Site                          | Action                                                |
| ----------------------------- | ----------------------------------------------------- |
| `lib/linux_shared.sh:23`      | rename the definition                                 |
| `lib/workflows.sh:136`        | **keep the name** — now resolves to the dispatcher    |
| `install_guards.bats:125`     | retitle the section comment                           |
| `install_guards.bats:127,130` | → `install_bats_linux`, and `unset MACOS`             |
| `install_guards.bats:136,139` | → `install_bats_linux`, and `unset MACOS`             |
| `install_guards.bats:973`     | **keep the name** — stubs what `run_setup_user` calls |
| `workflows.bats:161`          | **keep the name**, add a macOS counterpart            |

**A blanket find-and-replace breaks this.** Three of the nine sites must stay `install_bats` because the dispatcher is exactly what they exercise.

**`tests/setup_env/install_guards.bats:127,136` export `UBUNTU=1` without unsetting `MACOS`.** Once the dispatcher branches on `MACOS` first, those tests take the macOS arm on every Mac while still passing on Linux and on `ubuntu-latest` CI — a failure invisible to CI and visible only locally, which blocks pushes from every Mac since `scripts/pre-push` runs `make test`. Add `unset MACOS` per `tdd.md`'s test-isolation rule.

**New tests** (RED first, each separately):

- Dispatcher: `MACOS` set routes to the macOS arm; `LINUX` set routes to the Linux arm; neither set is a no-op returning 0.
- `run_setup_user` on macOS calls `install_bats`, and aborts when it returns non-zero. This is the assertion whose absence let the original hole ship — the Linux path was covered and the macOS path did not exist.

**Interfaces:**

- Consumes: `install_bats_macos` from Task 1.
- Produces: `install_bats()` dispatcher, `install_bats_linux()`. No later task calls these.

---

## Task 4: Move `zsh -n` onto `ZSH_FILES`

```yaml-task
id: 4
description: Add ZSH_FILES and a print-% target to the Makefile, move zsh -n off the bash files onto it, extend the empty-list refusal, and retire the zsh-on-bash test assertion
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: bats tests/scripts/makefile_lint_scope.bats
    exit_code: 0
  - cmd: 'bash -c ''[ "$(make lint | grep -c "^zsh")" -eq 10 ]'''
    exit_code: 0
  - cmd: 'bash -c ''! make lint | grep "^zsh" | grep -qE "\.(sh|bash)$|scripts/(pre-push|commit-msg)$"'''
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - Makefile
  - tests/scripts/makefile_lint_scope.bats
  - tests/setup_env/workflows.bats
depends_on: [3]
parallel_group: null
```

**Files:** `Makefile`, new `tests/scripts/makefile_lint_scope.bats`, `tests/setup_env/workflows.bats`.

**Makefile.** Add beside `SHELL_FILES`, with the same `env -u` prefix — git exports `GIT_DIR` into the pre-push hook when the push originates from a worktree, and this is a parse-time assignment:

```make
ZSH_FILES := $(shell env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR -u GIT_INDEX_FILE \
                 git ls-files '*.zsh' '*.zsh-theme' '.zshrc' '.zprofile')
```

Add the introspection target so tests read the real variables:

```make
print-%: ; @printf '%s\n' "$($*)"
```

Keep the quoting — it stops the shell glob-expanding a value containing `*`. An earlier draft called it load-bearing because "unquoted, an empty variable emits nothing"; measured with `od -c` on GNU Make 3.81, both forms emit a single `\n`, so that reason was false. Anti-vacuity comes from the scope test's non-empty assertions.

Remove the `zsh -n` line from the `SHELL_FILES` loop at `:46` and add a second loop over `ZSH_FILES`. Extend the empty-list refusal at `:38-42` to fail when **either** list is empty, checked independently so the message names which one.

**Retire `tests/setup_env/workflows.bats:282-284`** — the `@test "setup_env.sh passes zsh -n with the git_hooks.sh source line"` block. It is the last enforcement of `zsh -n` on a bash file. The `bash -n` assertion above it at `:278` stays.

**New scope test**, `tests/scripts/makefile_lint_scope.bats`, asserting against `make print-ZSH_FILES` / `make print-SHELL_FILES`:

- `ZSH_FILES` equals `git ls-files '*.zsh' '*.zsh-theme' '.zshrc' '.zprofile'` as a set.
- **Independent completeness check:** every path from `git ls-files | grep -E '\.zsh(-theme)?$|(^|/)\.z[a-z]+$'` appears in `ZSH_FILES`. This rule does not share the pathspec's blind spot, which is the entire point — it is what found `.zprofile`.
- `SHELL_FILES` and `ZSH_FILES` are disjoint.
- Both non-empty.

Strip the mocks directory from `PATH` (per `shell.md`); a `tests/mocks/git` stub would otherwise empty both lists and make every assertion vacuously true.

**Falsifiability, measured:** against the nine-path pathspec the completeness check emits `.zprofile`; against the eight-path pathspec it emits `.zprofile` and `bruce.zsh-theme`. It fails on a wrong pathspec and passes on the right one.

**Interfaces:**

- Produces: `ZSH_FILES`, `SHELL_FILES`, and `print-%`. Tasks 5 and 6 mirror the pathspec; Task 7 edits the same Makefile.

---

## Task 5: Align the CI zsh selector

```yaml-task
id: 5
description: Point the ci.yml zsh syntax step at the tracked zsh files instead of find over .sh (CI config, no local runtime to test)
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: 'grep -q "zsh-theme" .github/workflows/ci.yml'
    exit_code: 0
  - cmd: 'bash -c ''! grep -B5 "xargs -I{} zsh -n" .github/workflows/ci.yml | grep -q "find \."'''
    exit_code: 0
  - cmd: 'bash -c ''grep -B5 "xargs -I{} zsh -n" .github/workflows/ci.yml | grep -q "git ls-files"'''
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - .github/workflows/ci.yml
depends_on: [4]
parallel_group: wave-2
```

**Files:** `.github/workflows/ci.yml`, the zsh step at `:56-61`.

`tdd: not-applicable` — this is a CI workflow definition with no local runtime; it is verified by the grep gates above plus the CI run on the PR itself. There is no unit under test.

Replace the step's `find . -name '*.sh' ...` selector with the same derivation the Makefile uses:

```yaml
- name: Syntax check all zsh files
  run: |
    git ls-files '*.zsh' '*.zsh-theme' '.zshrc' '.zprofile' \
      | xargs -I{} zsh -n {}
```

Rename the step, since it no longer checks "shell scripts". No `env -u` prefix is needed: the CI job is a fresh checkout, not a hook invocation, so no `GIT_DIR` is inherited.

**Empty-list refusal, added after review.** The step must not pass having parsed zero files.
Measured: `printf '' | xargs -I{} zsh -n {}` exits 0, and GitHub's default `run` shell is
`bash -e {0}` with **no `pipefail`**, so `git ls-files`'s own status is discarded and the
step's status is `xargs`'s alone. A missing `.git`, a future `sparse-checkout`, a pathspec
typo, or the globs ceasing to match after a rename would all pass green. `make lint` guards
this at `Makefile:51-55`; the CI step now does too. Verified: in a git repo containing no zsh
files, the guarded step exits 1 and the unguarded form exits 0.

**Gate note, added after Task 5 returned a blocker.** Two earlier versions of this task's
second gate were both vacuous, in opposite ways. The plan's original anchored the `sed` range
on `"Syntax check all shell scripts (zsh)"` — the step name the rename _deletes_ — so after a
correct implementation the range is empty and the gate passes having inspected nothing. The
dispatch prompt paraphrased it to `/Syntax check all/`, which both step names share, so `sed`
anchored on the bash step and the gate failed against a _correct_ implementation. The gate now
anchors on the `zsh -n` terminator, which exists in both the old and new file, and asserts the
selector both negatively (no `find .`) and positively (uses `git ls-files`). Verified: passes
on the changed tree, fails both ways on `HEAD`'s version.

**Leave the bash step at `:49-54` alone.** Its `find`-versus-`git ls-files` inconsistency is pre-existing and out of scope; touching it here would widen the diff without a decision behind it.

**Interfaces:**

- Consumes: the pathspec fixed in Task 4. The two must match.

---

## Task 6: Behavioral `zsh -n` coverage for the three unchecked files

```yaml-task
id: 6
description: Add zsh -n tests for .zshrc, .zprofile and bruce.zsh-theme, which no suite currently reaches (task deliverable is the test itself, no production change)
role: executor
model: haiku
tdd: not-applicable
acceptance:
  - cmd: bats tests/zshrc.d/unit.bats
    exit_code: 0
  - cmd: 'bash -c ''[ "$(grep -c "run zsh -n" tests/zshrc.d/unit.bats)" -eq 10 ]'''
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - tests/zshrc.d/unit.bats
depends_on: [4]
parallel_group: wave-2
```

**Files:** `tests/zshrc.d/unit.bats` only.

`tdd: not-applicable` — the deliverable _is_ test code; there is no production change to drive red-green from. `model: haiku` — single file, mechanical, following seven existing examples verbatim.

The file currently holds seven `zsh -n` tests at `:15-45`, covering `1_init` through `7_final`. Add three more in the same shape, taking the count to ten:

```bash
@test ".zshrc has valid zsh syntax" {
  run zsh -n "${REPO_ROOT}/.zshrc"
  [ "$status" -eq 0 ]
}
```

…and the same for `.zprofile` and `bruce.zsh-theme`. Note these three sit at the repo root, not under `${ZSHRC_D}` — use `${REPO_ROOT}`, which the existing `setup()` already establishes.

`.zprofile` is the important one: zsh sources it at **login**, it is symlinked into `$HOME` by `lib/helpers.sh:677`, and nothing has ever syntax-checked it.

**Interfaces:**

- Consumes: `REPO_ROOT` from the existing `setup()`.
- Produces: nothing other tasks depend on.

---

## Task 7: Rewrite the bats-missing error text

```yaml-task
id: 7
description: Collapse four duplicate bats-not-found strings into one variable holding the message text, leading with the one-shot install and naming setup_user second
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: 'bash -c ''[ "$(grep -c "BATS_MISSING" Makefile)" -ge 5 ]'''
    exit_code: 0
  - cmd: 'bash -c ''make BATS= -n test 2>&1 | grep -q "brew install bats-core"'''
    exit_code: 0
  - cmd: 'bash -c ''make BATS= -n test 2>&1 | grep -q "setup_env.sh -t setup_user"'''
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - Makefile
depends_on: [4]
parallel_group: null
```

**Files:** `Makefile` — the four `$(error ...)` sites at `test`, `bash-coverage`, `push-bash-coverage`, `test-unit`.

`tdd: not-applicable` — a Makefile message string with no unit under test; the three grep gates above exercise it through a real `make BATS= -n test` invocation, which is the actual failure path.

Define one variable holding **the message text only**:

```make
BATS_MISSING := bats not found. Install: brew install bats-core (macOS) or sudo apt-get install bats (Linux). Durable fix: ./setup_env.sh -t setup_user
```

and reference it as `$(error $(BATS_MISSING))` at each of the four sites.

**Do not move `$(error ...)` itself into the variable.** `$(error)` fires wherever it is expanded, so a `:=` assignment containing it aborts every `make` invocation at parse time regardless of target. A recursively-expanded `=` would technically defer it, but produces a variable whose mere expansion halts the build — a trap for the next reader with no gain over sharing the string.

The one-shot leads because an operator reads this message _while a push is blocked_, with unpushed commits and possibly a dirty tree. `run_setup_user` is a ~20-step run that does an unconditional `git pull` in the checkout and calls `setup_claude_mcp`; it is the durable fix, not the emergency one.

**Interfaces:**

- Consumes: the Makefile as left by Task 4.

---

## Task 8: Documentation sync

```yaml-task
id: 8
description: Update CLAUDE.md conventions and testing prose plus the plan index to match the shipped behaviour (docs-only, no behavior change)
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: 'bash -c ''! grep -q "zsh -n setup_env.sh" CLAUDE.md'''
    exit_code: 0
  - cmd: 'grep -q "2026-08-11-bats-provisioning-zsh-lint-scope" docs/superpowers/README.md'
    exit_code: 0
  - cmd: 'bash -c ''! grep -qE "install_bats\(\).*setup_env\.sh" CLAUDE.md'''
    exit_code: 0
  - cmd: 'bash -c ''! grep -q "bash -n + zsh -n on every tracked shell file" CLAUDE.md'''
    exit_code: 0
  - cmd: 'bash -c ''! grep -q "1260 tests as of 2026-08-09" CLAUDE.md'''
    exit_code: 0
  - cmd: 'bash -c ''! grep -q "1274 tests as of 2026-08-10" CLAUDE.md'''
    exit_code: 0
  - cmd: 'bash -c ''! grep -q "zsh -n\` on all \`.sh\` files" CLAUDE.md'''
    exit_code: 0
  - cmd: make check-agent-guidance
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - CLAUDE.md
  - docs/superpowers/README.md
depends_on: [5, 6, 7]
parallel_group: null
```

**Files:** `CLAUDE.md`, `docs/superpowers/README.md`.

`tdd: not-applicable` — prose only, no executable logic.

1. **Key Conventions:** retire "For shell syntax-only fixes in `setup_env.sh`, validate with both `bash -n setup_env.sh` and `zsh -n setup_env.sh` before commit." That line prescribes exactly the check this plan removes. Replace with the split: `bash -n` for `.sh`/`.bash`/hooks, `zsh -n` for the ten zsh files.
2. **Testing:** the `make lint` description currently reads "bash -n + zsh -n on every tracked shell file". Correct it — `bash -n` and shellcheck over `SHELL_FILES`, `zsh -n` over `ZSH_FILES`.
3. **`CLAUDE.md:202`** — the Testing section reads "Ubuntu: `sudo apt-get install -y bats` (via `install_bats()` in `setup_env.sh`)". After Task 3 that names a function which no longer exists under that name, and the macOS line above it no longer reflects that `run_setup_user` installs bats there too. Rewrite both to describe the dispatcher. _(Found by Task 3's spec reviewer, which correctly declined to fix it as outside its `files_touched`.)_
4. **`CLAUDE.md` test counts** — the CI section records "1260 tests as of 2026-08-09" and the
   Coverage section "1274 tests as of 2026-08-10". This branch adds tests in T1, T2, T3, T4 and
   T6; update both figures to the count `make test` reports at that point, and re-read the
   coverage percentage rather than carrying the old one forward. The 840 CI floor is unaffected.
5. **`CLAUDE.md:247`** — the `lint-macos` job is described as running "`bash -n` and `zsh -n`
   on all `.sh` files". After Task 5 the zsh step selects the ten tracked zsh files via
   `git ls-files`, not `.sh` via `find`. The bash step is unchanged, so describe the two
   separately. _(Found by the orchestrator enumerating CLAUDE.md before dispatch; not in the
   original T8 scope.)_
6. **Coverage figure at `CLAUDE.md:298`** — T1 and T3 add functions to `lib/macos.sh` and
   `lib/helpers.sh`, both in the instrumented set, so the percentage has moved. Run
   `make bash-coverage` and confirm it is **≥ 91%**, the CI gate that blocks auto-merge. Do
   **not** publish the local number as the headline figure: `CLAUDE.md` itself states "publish
   the CI figure; treat a local number as a preview," and macOS reads about one point above
   ubuntu-latest. Report the local figure and flag that the published one needs reconciling
   against CI's run on the PR.
7. **`docs/superpowers/README.md`:** delete the "Fail-closed widened the fleet's bats/zsh dependency" backlog row and add an All Plans row dated 2026-08-11 linking this plan and its spec, status **Done**. Add the `> **Status: DONE**` banner to the top of this plan file.

`make check-agent-guidance` is in the gate because `CLAUDE.md` feeds the generated Cursor mirror; if it fails, run `make sync-agent-guidance` rather than hand-editing the mirror.

**Interfaces:**

- Consumes: the final state of every prior task.

---

## Carry to the Phase 3 `learnings` pass

Not a task in this plan, and deliberately not done mid-cycle — recorded here so the
post-merge `docs` → `learnings` step finds it rather than relying on the session transcript.

**"A set derived by one rule cannot validate itself" now has three independent instances
across three languages, and lives in no standards file.**

| Instance             | Where                    | Cost of having no second derivation                                                                            |
| -------------------- | ------------------------ | -------------------------------------------------------------------------------------------------------------- |
| Coverage denominator | `shell.md`, dotfiles#199 | A tracer instrumented 13 of 36 tracked files and published 91% for two months                                  |
| `[lints]` regex      | Rust spec (ai-config)    | —                                                                                                              |
| `ZSH_FILES` pathspec | this spec                | Three wrong counts across two full lens rounds; a differently-derived set found `.zprofile` on first execution |

`shell.md` and `tdd.md` each state the rule for their own domain — denominators and coverage
instruments — but nothing states it generally, so it is being rediscovered per language. The
third instance is the threshold where that stops being reasonable.

The dotfiles instance is the only one where the cost was measured _across multiple review
rounds_, which is what makes it the useful citation: reviewing the rule harder demonstrably
did not work, twice, and the fix was one command.

Candidate home is a general entry in `~/.claude/standards/` rather than a per-language one.
That is a fleet-wide edit affecting every repo and session, so it wants its own decision at
`learnings` time — not a unilateral edit here.

## Self-Review

1. **Spec coverage.** §A → Tasks 1, 3. §B → Tasks 4, 5, 6. §C → Task 7. §D → Tasks 4 (test retirement), 8. §E → Task 2. No gaps.
2. **Placeholder scan.** No TBD/TODO; every task carries the literal code or the exact edit.
3. **Type consistency.** `install_bats_macos` (Task 1) → dispatcher (Task 3); `ZSH_FILES` and `print-%` (Task 4) → Tasks 5, 6, 7.
4. **YAML blocks.** Every task has one; `make validate-plan` before commit. Every `cmd:` containing `": "` or a shell negation is single-quoted.
5. **TDD `files_touched` includes test files.** Tasks 1, 2, 3, 4 all list theirs.
6. **Token budget.** Every block under 2KB, flat YAML, no BDD boilerplate.
7. **ADR-significance.** No new Phase 3 gate, HOLD-capable check, structural pattern, security guardrail, or storage choice — this changes the scope of an existing lint target and adds a provisioning arm. No ADR required.
8. **`files_touched` matches the prose.** Task 3 names six files and edits six. Task 6 is `haiku` with exactly one non-workflow, non-migration, non-lockfile path.

### Gate falsifiability

| Task | Discriminating gate                          | Fails on the base tree because                                      |
| ---- | -------------------------------------------- | ------------------------------------------------------------------- |
| 1    | `bats tests/setup_env/macos.bats`            | new tests written RED first; `install_bats_macos` does not exist    |
| 2    | real-Brewfile parse test                     | `bats-core` is tagged, so `_brewfile_parse_section` omits it        |
| 3    | dispatcher + `run_setup_user` tests          | `install_bats` is the apt body, not a dispatcher; macOS path absent |
| 4    | `make lint \| grep -c "^zsh"` = 10           | currently 36, and all 36 name bash files                            |
| 5    | `grep -q "zsh-theme" ci.yml`                 | the selector is `find . -name '*.sh'`                               |
| 6    | `grep -c "run zsh -n"` = 10                  | currently 7                                                         |
| 7    | `make BATS= -n test \| grep -q "setup_user"` | current text names only the one-shot installs                       |
| 8    | `! grep -q "zsh -n setup_env.sh" CLAUDE.md`  | that line is present today                                          |

**Gates that expect non-zero were checked for the right reason.** Every `bats <file>` path above exists; every `grep` target file exists. A gate naming an absent file exits 4 or 2 and would pass a naive "expect failure" check vacuously.

**What each gate is blind to.** Tasks 1-3's bats gates are satisfied by a test that asserts only on `rc`, which is why each task body names the specific side effects to assert (mock invocation state, not just return code). Task 4's line-count gate is satisfied by a `ZSH_FILES` that happens to hold ten wrong paths, which is why the scope test's completeness check derives its expectation by a _different rule_ than the pathspec. Task 6's count gate is satisfied by ten tests naming the same file three times, which is why the task body names the three files explicitly.

**No task in this plan is a behaviour-preserving refactor**, so no differential harness is required. Task 3's rename changes a function's name and its call graph, not its behaviour, and the existing repointed tests are the oracle for that.
