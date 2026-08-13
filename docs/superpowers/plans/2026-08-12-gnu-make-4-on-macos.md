# GNU Make 4.x on macOS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the GNU Make version-skew defect class at its source, and align every mac's `make` with the version CI runs, without introducing any mechanism that can block a machine from testing or pushing.

**Architecture:** Four independent components. `MAKEFLAGS += --no-print-directory` in the repo `Makefile` removes the only measured version-variant behaviour at every call site including unwritten ones. `install_make_macos()` provisions GNU make 4.x via Homebrew during `setup_user`. A dual-prefix `gnubin` prepend in `6_path.zsh` makes `make` resolve to it. A make-version field on the `-t update` state-ledger entry makes a divergent machine queryable from anywhere rather than visible only at its own terminal.

**Tech Stack:** GNU Make, zsh, bash, BATS, Homebrew.

**Spec:** [`2026-08-12-gnu-make-4-on-macos-design.md`](../specs/2026-08-12-gnu-make-4-on-macos-design.md)

## Global Constraints

- `MAKEFLAGS` is an **exported environment variable**, not a file-local directive. Every `make` a test spawns inherits `--no-print-directory` from the environment once the directive lands.
- **Binding partition.** Every stdout-capturing `make` invocation in a test file is in exactly one set: **guarded** (carries a per-call `--no-print-directory`) or **measuring** (carries `env -u MAKEFLAGS` and nothing else). Both sets must be non-empty.
- `Makefile:81` is `test: lint test-python`. Any edit preserves `test-python`.
- The doctor helper `_doctor_check_one_version` asserts a **pin**; this work needs a **floor**. Do not reuse it. There is deliberately no `MAKE_VER` constant.
- Version comparison is numeric (`-ge` on the extracted major), never lexicographic — `[[ "4.4.1" < "3.81" ]]` is true under `[[`.
- Homebrew prefixes: `/opt/homebrew` (ARM) and `/usr/local` (Intel — ratna is `x86_64`, macOS 13.7.8, `gnubin` already present). Never `brew --prefix` inside `6_path.zsh`: that file is what puts Homebrew on `PATH`.
- `6_path.zsh`'s existing idiom is `path+=` (append), which loses to `/usr/bin`. This work requires **prepend**.
- Linux is untouched. CI (`ubuntu-latest`) is untouched.
- No mechanism may fail a run, block a push, or change an exit code.

## Verification Planning

**Command that proves the whole change works:**

```bash
make test                                             # 3.81, the fleet default
shim=$(mktemp -d); ln -s "$(command -v gmake)" "$shim/make"
PATH="$shim:$PATH" make test                          # 4.4.1, what CI runs
```

**Expected:** `rc=0` and `1294 + <new cases> ok, 0 not ok` from **both**. Measured on the base tree with the directive applied by hand: 3.81 → `rc=0, 1294 ok, 0 not ok`; 4.4.1 shim → `rc=0, 1294 ok, 0 not ok`.

**Edge cases that must be exercised:** the Intel `/usr/local` prefix with no ARM prefix present (T3 case 8); an absent/unparseable `make --version` recorded as `unknown` rather than as a version (T5 case 18); and the `MAKEFLAGS` leak remaining observable (T1 case 5) — that last one is what proves cases 1 and 2 measure the `Makefile` rather than the environment.

**Dispatch is strictly sequential — no `parallel_group` on any task.** T3/T4/T5 touch disjoint files and would qualify, but `subagent-driven-development` records that wave members must not run the repo's full suite, and dotfiles#208 hit exactly that failure twice in one session this week: two members backgrounded `make test` past the 120s auto-background threshold and ended their turn awaiting a notification that does not exist. Seven sequential tasks each running the real aggregate gate is the safer trade here.

---

### Task 1: MAKEFLAGS directive + measurement cases

```yaml-task
id: 1
description: Add MAKEFLAGS += --no-print-directory to the Makefile and the three cases that measure it
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: grep -q 'MAKEFLAGS' Makefile
    exit_code: 0
  - cmd: bats tests/scripts/makefile_lint_scope.bats
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - Makefile
  - tests/scripts/makefile_lint_scope.bats
depends_on: []
```

**Files:** `Makefile` (add `MAKEFLAGS += --no-print-directory` as line 1), `tests/scripts/makefile_lint_scope.bats` (cases 1, 2, 5).

**Cases.** Write each test first, run it red, then implement.

- **Case 1** — under `env -u MAKEFLAGS`, `print-ZSH_FILES` line count is **equal** across a `<4` make and a `≥4` make, **and >0**. Equality alone passes when both emit nothing. Resolve the `<4` arm from `/usr/bin/make` and the `≥4` arm from the first make ≥4 on `PATH`; if either arm is missing, `skip` with a reason naming which arm. A skip on `ubuntu-latest` is expected and correct — it has neither a 3.81 `make` nor a `gmake`.
- **Case 2** — under `env -u MAKEFLAGS`, a `print-` probe returns an exact derived value, not a verdict.
- **Case 5** — with `MAKEFLAGS` inherited (no `env -u`), a directive-free fixture Makefile emits directory lines under a ≥4 make. This is the falsifiability canary: it is the only case that fails if the `env -u` discipline is dropped.

Measured reference: a directive-free fixture emits 3 lines alone, 1 line spawned from an outer make carrying the directive, 3 again under `env -u MAKEFLAGS`.

**Interfaces:**

- Consumes: nothing.
- Produces: the `Makefile` directive that T2's structural cases assert, and the `env -u MAKEFLAGS` idiom every later make-measuring test copies.

---

### Task 2: Structural partition cases + flag the four unguarded parses

```yaml-task
id: 2
description: Assert the guarded/measuring partition and add per-call flags to makefile_scope.bats
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: test $(grep -c 'no-print-directory' tests/makefile_scope.bats) -ge 4
    exit_code: 0
  - cmd: bats tests/makefile_scope.bats tests/scripts/makefile_lint_scope.bats
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - tests/makefile_scope.bats
  - tests/scripts/makefile_lint_scope.bats
depends_on: [1]
```

**Files:** `tests/makefile_scope.bats` (add `--no-print-directory` to the four `make -C "${REPO_ROOT}" -n lint` invocations at lines 36, 45, 68, 79), `tests/scripts/makefile_lint_scope.bats` (cases 3, 4, 6).

**Cases.**

- **Case 3** — `MAKEFLAGS += --no-print-directory` is present in the `Makefile`.
- **Case 4** — the partition. Scan every stdout-capturing `make` invocation across `tests/**/*.bats` and assert each is in exactly one of guarded / measuring, and **both sets are non-empty**. An invocation in neither set fails. Non-emptiness is required so a scanner matching nothing cannot read as a pass.
- **Case 6** — `test` still has `test-python` as a prerequisite.

Lines 36 and 45 already wrap in `env` for `GIT_DIR`/`GIT_INDEX_FILE`; add the flag to the `make` call itself, not the `env` prefix.

**Interfaces:**

- Consumes: T1's `Makefile` directive.
- Produces: the partition invariant every later test-writing task must satisfy.

---

### Task 3: gnubin PATH prepend

```yaml-task
id: 3
description: Prepend the Homebrew gnubin dir for GNU make on macOS, testing both prefixes
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: grep -q 'gnubin' .config/.zshrc.d/6_path.zsh
    exit_code: 0
  - cmd: bats tests/zshrc.d/unit.bats
    exit_code: 0
  - cmd: zsh -n .config/.zshrc.d/6_path.zsh
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - .config/.zshrc.d/6_path.zsh
  - tests/zshrc.d/unit.bats
depends_on: [1]
```

**Files:** `.config/.zshrc.d/6_path.zsh` (inside the existing `if [[ ${MACOS} ]]` block), `tests/zshrc.d/unit.bats` (cases 7–12).

**Implementation:**

```zsh
for _gnubin in /opt/homebrew/opt/make/libexec/gnubin \
               /usr/local/opt/make/libexec/gnubin; do
  [[ -d ${_gnubin} ]] && { path=(${_gnubin} $path); break }
done
unset _gnubin
```

**Cases.** 7: with an ARM-prefix dir present it is `path[1]` — assert **position**, not membership, since a membership check passes for the inert append idiom. 8: with only `/usr/local` present it is `path[1]` (the ratna case). 9: sourcing three times yields one entry (`typeset -U path` dedupes). 10: with neither dir present, no entry added and `PATH` otherwise intact. 11: under `LINUX` no gnubin entry **and** a known Linux path is present — the positive mirror is required, because a pure absence assertion passes for a file that died on its first line. 12: `_gnubin` does not leak into the environment.

**Interfaces:**

- Consumes: nothing from T1/T2.
- Produces: `make` resolving to GNU 4.x on a provisioned mac.

---

### Task 4: install_make_macos provisioning

```yaml-task
id: 4
description: Provision GNU make via Homebrew during setup_user on macOS
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: grep -q 'install_make_macos' lib/macos.sh
    exit_code: 0
  - cmd: grep -q 'install_make_macos' lib/workflows.sh
    exit_code: 0
  - cmd: bats tests/setup_env/install_guards.bats
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - lib/macos.sh
  - lib/workflows.sh
  - tests/setup_env/install_guards.bats
depends_on: [1]
```

**Files:** `lib/macos.sh` (new `install_make_macos()`), `lib/workflows.sh` (call it from `run_setup_user`'s existing `if [[ -n ${MACOS} ]]` branch, alongside `install_git`), `tests/setup_env/install_guards.bats` (cases 13–16).

**Implementation.** Mirror `install_bats_macos()` exactly: `quiet_which` probe → `install_homebrew` if brew absent → `brew_install_formula make || return 1` → `log_error` + `return 1` if brew still absent.

**Called directly, with no `install_make()` dispatcher** — Linux needs nothing, so a dispatcher would exist only to have an empty arm, and `install_bats`'s `if`/`elif` has no `else`, so it returns 0 when neither `MACOS` nor `LINUX` is set.

**The probe is `quiet_which gmake`, not `make`.** `make` is always present on macOS at 3.81, so probing it reports success on precisely the machine needing the install.

**Cases.** 13: `gmake` present → no `brew install` call. 14: `gmake` absent, brew present → `brew_install_formula make` called once. 15: `gmake` absent, brew absent and uninstallable → returns 1 and logs an error. 16: a stubbed 3.81 `make` on `PATH` must **not** satisfy the probe — install still runs.

**Interfaces:**

- Consumes: `quiet_which`, `install_homebrew`, `brew_install_formula`, `log_info`, `log_error` from `lib/helpers.sh` / `lib/macos.sh`.
- Produces: `gmake` on disk, which T3's prepend then finds.

---

### Task 5: make-version field on the update ledger entry

```yaml-task
id: 5
description: Record the machine's make major version as a field on the -t update ledger entry
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: grep -q 'make_version' lib/update_summary.sh
    exit_code: 0
  - cmd: bats tests/setup_env/update_summary.bats
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - lib/update_summary.sh
  - tests/setup_env/update_summary.bats
depends_on: [1]
```

**Files:** `lib/update_summary.sh` (`_ledger_write_run_entry` at :377, called at :491), `tests/setup_env/update_summary.bats` (cases 17–21).

**A field on the existing entry, not a new section.** A section would require a matching entry in `_UPDATE_SECTION_ORDER` (`lib/update_summary.sh:5`), which CLAUDE.md records as a two-place coupling whose omission tracks a section internally while never printing it. A field needs neither edit.

**Floor, not pin.** Extract the major component and compare with `-ge`. Do **not** reuse `_doctor_check_one_version` (it asserts `[[ "${_installed}" == "${_pinned}"* ]]` against a constant) and do not add a `MAKE_VER` constant.

**Cases.** 17: `-t update` on macOS writes the field with value `4`. 18: unparseable or absent `make --version` records `unknown` — **not** a version and not empty, because an empty major makes `[[ "" -ge 4 ]]` false and would record identically to a real 3.81, making a broken probe indistinguishable from a correctly-detected old make. 19: Linux writes no make-version field **and** the entry is still written (positive mirror). 20: comparison is numeric, not lexicographic. 21: the field never changes the run's exit code.

**Interfaces:**

- Consumes: `_ledger_write_run_entry(RUN_TYPE, EXIT_CODE)`.
- Produces: a queryable divergence signal in the state ledger.

---

### Task 6: ADR-0018

```yaml-task
id: 6
description: Record the architectural decision and the rejected enforcement guard (docs-only, no behavior change)
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: test -f docs/adr/0018-gnu-make-4-on-macos.md
    exit_code: 0
  - cmd: 'grep -qE "\*\*Status:\*\* Accepted" docs/adr/0018-gnu-make-4-on-macos.md'
    exit_code: 0
  - cmd: grep -q '0018' docs/adr/README.md
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - docs/adr/0018-gnu-make-4-on-macos.md
  - docs/adr/README.md
depends_on: [1, 2, 3, 4, 5]
```

**Files:** new `docs/adr/0018-gnu-make-4-on-macos.md`, `docs/adr/README.md` (status-table row).

Nygard format — Context → Decision → Consequences → Related. `**Status:** Accepted`, matching the format of all 17 existing ADRs (verified against the corpus; a bare `Status: Accepted` would not match and would make this file the directory's only outlier).

**Consequences must record the rejected `require-gnu-make` guard and why**, since that is the load-bearing decision: a `MAKE_VERSION` command-line assignment bypassed it silently, its printed `gmake test` remedy produced a false green because make does not propagate itself to a bare `make` in a recipe, it blocked `git push` via `scripts/pre-push:71`, it locked out Intel machines, and it could not run in CI. Both reproductions are in the spec.

**Interfaces:** Consumes the completed implementation. Produces the decision record.

---

### Task 7: CLAUDE.md

```yaml-task
id: 7
description: Document the MAKEFLAGS directive, the test partition, and the gnubin prepend (docs-only, no behavior change)
role: executor
model: haiku
tdd: not-applicable
acceptance:
  - cmd: grep -q 'MAKEFLAGS' CLAUDE.md
    exit_code: 0
  - cmd: grep -q 'gnubin' CLAUDE.md
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - CLAUDE.md
depends_on: [1, 2, 3, 4, 5, 6]
```

**Files:** `CLAUDE.md` only.

Add to the **Testing** section: the `MAKEFLAGS += --no-print-directory` directive, that it is an exported environment variable reaching every spawned make, and the guarded/measuring partition rule with `env -u MAKEFLAGS` for measuring tests.

Add to **Key Conventions**: the dual-prefix gnubin prepend, that it must be a prepend rather than `path+=`, and that `brew --prefix` must not be used there because `6_path.zsh` is itself what puts Homebrew on `PATH`.

**Interfaces:** Consumes the completed implementation. Produces the durable convention record.

---

## Self-Review

1. **Spec coverage** — §1 → T1/T2, §2 → T4, §3 → T3, §4 → T5, all 21 cases assigned, docs → T6/T7. No gaps.
2. **Placeholders** — none; every case states its assertion and every implementation states its code or its mirror.
3. **Type consistency** — `install_make_macos`, `_ledger_write_run_entry`, `_gnubin`, `MAKEFLAGS` spelled identically across tasks and matched against the repo.
4. **YAML blocks** — present on all 7 tasks; `make validate-plan` before commit. Case 6's `grep` is single-quoted for the colon-space rule.
5. **TDD `files_touched` includes the test file** — T1–T5 each list production and test files.
6. **Token budget** — every block under 2KB.
7. **ADR significance** — yes: a fleet-wide `PATH` change plus a ledger schema field. T6 covers it at plan time rather than post-merge.
8. **`files_touched` matches the prose** — T4 names `lib/macos.sh` and `lib/workflows.sh` and lists both; T7 is the only `haiku` task and touches exactly one file.
9. **Gate falsifiability** — every discriminating gate was run against the base tree and returned **exit 1**, not 2/4/127. `bats` resolves on both target files (exit 0), so no gate names a path that does not exist.
10. **Wrong implementations that still pass** — a `grep` gate passes for a directive added as a comment, and a `bats` gate passes for a test that asserts nothing. The pairing is deliberate: `make test` under both make versions is the session-level check, and case 5 is the canary that fails if the `env -u` discipline erodes.
