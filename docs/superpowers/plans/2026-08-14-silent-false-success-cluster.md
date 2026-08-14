# Silent-False-Success Cluster Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make six functions stop reporting success for work that did not happen, and delete a publisher whose exit codes nothing reads.

**Architecture:** Five production files gain error propagation and install-state guards; one script plus its make target and tests are deleted. No new abstractions beyond a single `_apt_pkg_installed` helper in `lib/linux_shared.sh`. No new gates, no ADR — this is defect repair plus a deletion, and ADR-0008 is amended rather than superseded.

**Tech Stack:** bash, BATS, GNU Make, `dpkg-query`, Homebrew.

**Spec:** [`2026-08-13-silent-false-success-cluster-design.md`](../specs/2026-08-13-silent-false-success-cluster-design.md), reviewed across three lens rounds. Read it before starting — every guard in this plan has a rejected predecessor recorded there, and two of them look more correct than the version that shipped.

## Global Constraints

- **Never use a `PATH` probe as an install guard.** `quiet_which zsh` was rejected: it cannot see `zsh-doc`, which ships no binary. See spec item 2.
- **Never use `dpkg-query -W` as an install guard.** Measured on Ubuntu 24.04 / dpkg 1.22.6: it returns 0 for a removed-but-not-purged (`rc`) package. Use `${db:Status-Abbrev}` matched against `^ii`.
- **`_apt_pkg_installed` takes exactly one package.** `dpkg-query -f ... -W pkg1 pkg2 | grep -q '^ii'` passes when _either_ is installed. Two calls joined by `&&`.
- **Gate snap on `command -v snap`, never on `HAS_SNAP`.** An unmapped hostname yields zero `HAS_*` variables; nothing maps to the `server` profile.
- **`make test` takes ~9m34s.** Wave members must NOT declare it — they would background past the 120s Bash threshold and never wake. The orchestrator runs it once at wave close.
- **Test naming:** `<function>: <behaviour>`, matching `tests/setup_env/macos.bats`.
- **Every error-path test asserts two things:** the return code is 1, AND the trailing success log is absent.
- Commit each task with `caveman:caveman-commit`.

## Baseline

Each row states where its number came from, because two are this repo's published figures
and two were measured against this tree while writing the plan. Conflating those is the
boundary error `behavior.md` names, and it happened twice while producing the spec.

| quantity                               | value                   | provenance                                                                                                         |
| -------------------------------------- | ----------------------- | ------------------------------------------------------------------------------------------------------------------ |
| `make test`                            | green, **1317 `ok`** | measured, this tree, full uncontended local run                                                                    |
| `make test` runtime                    | ~9m34s                  | `CLAUDE.md`; consistent with the run above                                                                         |
| bash coverage                          | 91% (3135/3415)         | **CI's figure**, from `CLAUDE.md` — not measured here. Local reads 92%; publish CI's per that file's standing rule |
| `grep -rn push-bash-coverage <scoped>` | **38 matches**          | measured, this tree; must reach 0 (T6)                                                                             |
| `tests/setup_env/linux_shared.bats`    | 1 test, 720 bytes       | measured, this tree — `install_git_linux`/`install_zsh_linux` have **no** coverage today                           |

## Verification Planning

**Session-level proof the whole change works**, above the per-task gates:

```bash
make test          # expect green; state cases-added / 13-removed / net arithmetic
make lint          # expect exit 0
make bash-coverage # re-derive; do NOT assume direction (see below)
grep -rn 'push-bash-coverage' tests/ .github/ Makefile CLAUDE.md docs/adr/ docs/superpowers/README.md   # expect no matches
```

**Coverage moves in both directions** — new error branches add coverable lines while a deleted file leaves the `git ls-files`-derived instrumented set. If the percentage rises, confirm it rose because new branches are covered, not because a low-coverage file exited the denominator. Publish the figure with its denominator.

**Edge cases that must be exercised to be confident**, each owned by a named test below: a package in `rc` state; `zsh` present with `zsh-doc` absent; a prep step failing while the install succeeds; apt failing while snap succeeds and the reverse; `snap` absent from `PATH`; neither `MACOS` nor `LINUX` set.

**Three mutation checks are acceptance criteria, not advice** (T8). Each pins a defect that shipped in a draft of the spec and survived a review round.

---

### Task 1: macOS install guards propagate brew failures

```yaml-task
id: 1
description: install_git_macos and install_zsh_macos propagate a failing brew_install_formula instead of logging success
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: 'test "$(bats --count -f "install_git_macos: propagates a failing brew install" tests/setup_env/macos.bats)" -ge 1'
    exit_code: 0
  - cmd: 'test "$(bats --count -f "install_zsh_macos: propagates a failing brew install" tests/setup_env/macos.bats)" -ge 1'
    exit_code: 0
  - cmd: bats tests/setup_env/macos.bats
    exit_code: 0
max_retries: 3
files_touched:
  - lib/macos.sh
  - tests/setup_env/macos.bats
depends_on: []
parallel_group: wave-1
```

**Files:** `lib/macos.sh` (`install_git_macos` at :96, `install_zsh_macos` at :115), `tests/setup_env/macos.bats`.

**Change:** append `|| return 1` to the `brew_install_formula git` and `brew_install_formula zsh` calls. Keep the trailing `log_info` — with every failable call guarded, that matches `install_bats_macos` (guard at :145) and `install_make_macos` (:184) in the same file.

**Tests, written first, one at a time:**

- `install_git_macos: propagates a failing brew install` — mock `brew_install_formula` to exit 1; assert `status` is 1 AND `output` does not contain `Installed git`.
- `install_zsh_macos: propagates a failing brew install` — same shape, `Installed zsh`.
- Success branches already exist in this file; extend rather than duplicate.

**Interfaces:** Consumes nothing. Produces no new symbols.

**Wave note:** scoped gate only, no `make test` — see Global Constraints.

---

### Task 2: Linux install guards — install-state guard, tiered errors, no dist-upgrade

```yaml-task
id: 2
description: install_git_linux and install_zsh_linux gain an install-state guard, fail only on the contract step, and stop running a full-system dist-upgrade
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: 'test "$(bats --count -f "install_zsh_linux: installs when zsh-doc is absent" tests/setup_env/linux_shared.bats)" -ge 1'
    exit_code: 0
  - cmd: 'test "$(bats --count -f "install_zsh_linux: installs when zsh is in rc state" tests/setup_env/linux_shared.bats)" -ge 1'
    exit_code: 0
  - cmd: 'test "$(bats --count -f "install_zsh_linux: propagates a failing apt install" tests/setup_env/linux_shared.bats)" -ge 1'
    exit_code: 0
  - cmd: bats tests/setup_env/linux_shared.bats
    exit_code: 0
max_retries: 3
files_touched:
  - lib/linux_shared.sh
  - tests/setup_env/linux_shared.bats
  - tests/mocks/dpkg-query
depends_on: []
parallel_group: wave-1
```

**Files:** `lib/linux_shared.sh` (`install_git_linux` :4, `install_zsh_linux` :14); `tests/setup_env/linux_shared.bats` (**one** test today — write these from scratch); `tests/mocks/dpkg-query`.

**Mock extension first.** `tests/mocks/dpkg-query` ignores its arguments and keys off one global `MOCK_DPKG_QUERY_EXIT`. Extend it to dispatch on the package name (last arg) against a per-package status map — `MOCK_DPKG_STATUS_zsh=ii`, `MOCK_DPKG_STATUS_zsh_doc=rc`, absent meaning not installed. Neither discriminating test below is writable without it.

**New helper:**

```bash
_apt_pkg_installed() {
  dpkg-query -f '${db:Status-Abbrev}' -W "${1}" 2>/dev/null | grep -q '^ii'
}
```

**Guards:** `install_git_linux` uses `_apt_pkg_installed git`; `install_zsh_linux` uses `_apt_pkg_installed zsh && _apt_pkg_installed zsh-doc`.

**The git guard carries a required comment** — copy the four-line block from spec item 2 verbatim. The warning must live at the guard, not only in the spec.

**Error tiering:** `add-apt-repository` and `apt update` get `|| log_warn "..."`; `apt install` gets `|| { log_error "..."; return 1; }`. **Delete `sudo -H apt dist-upgrade -y` from both functions.**

**Tests, one at a time:** skips-when-both-installed; installs-when-`zsh-doc`-absent; installs-when-`zsh`-in-`rc`; propagates-failing-`apt install` (status 1, no `Installed zsh`); warns-but-continues-when-`apt update`-fails (status 0, warning present); does-not-run-`dist-upgrade` (absent from `MOCK_CALLS_FILE`). Mirror the first four for git.

**Interfaces:** Produces `_apt_pkg_installed <pkg>` → exit 0 iff `^ii`. Task 3 shares this file; do not rename it.

**Size note:** this block runs ~30% over the 2KB target. Deliberate — the alternatives are cutting a discriminating acceptance gate or splitting the mock extension into a task with no independently testable deliverable. Both are worse than the overage.

---

### Task 3: Split apt from snap in the update path

```yaml-task
id: 3
description: Split update_system_packages into update_apt_packages and update_snap_packages so each summary row reports its own subsystem, gated on command -v snap
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: 'test "$(bats --count -f "update_snap_packages: skipped when snap is absent from PATH" tests/setup_env/workflows.bats)" -ge 1'
    exit_code: 0
  - cmd: bats tests/setup_env/linux_shared.bats
    exit_code: 0
  - cmd: bats tests/setup_env/workflows.bats
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - lib/linux_shared.sh
  - lib/workflows.sh
  - tests/setup_env/linux_shared.bats
  - tests/setup_env/workflows.bats
depends_on: [2]
```

**Files:** `lib/linux_shared.sh` (`update_system_packages` :33), `lib/workflows.sh` (caller :448), both bats files.

**Split:** `update_apt_packages` (apt update → `check_and_install_nala` → nala full-upgrade → autoremove, each `|| { log_error; return 1; }`); `update_snap_packages` (`snap refresh`, same). `update_system_packages` becomes a wrapper running **both unconditionally** — snap must still refresh when apt fails — returning 1 if either failed. Keep the wrapper; existing tests reference it.

**Caller:** `_update_record_start "apt"` / run / `_update_record_end "apt" "${PIPESTATUS[0]}"`, then the same for snap wrapped in `if command -v snap > /dev/null 2>&1; ... else _update_skip "snap" "snap not installed on this host"; fi`. **Delete the `cp err_apt err_snap` line.**

**Tests, one at a time:** apt-fails-snap-succeeds → apt row red, snap row green; the reverse; `snap` absent → row skipped with that exact reason and `snap refresh` never invoked; `err_snap` contains snap output and **not** apt's.

**The snap-absent test strips `tests/mocks/snap` from `PATH`; it does not unset a variable.** `load_mocks` prepends `tests/mocks`, so `command -v snap` is true by default here — use the `_clean_path` idiom. A variable-based mock would also pass against the rejected `HAS_SNAP` gate, which is the whole distinction.

**Interfaces:** Consumes `_apt_pkg_installed` (Task 2, unchanged). Produces `update_apt_packages` / `update_snap_packages`, rc 0 on success.

**Not a wave member** — shares `lib/linux_shared.sh` with Task 2, so it carries the aggregate gate.

---

### Task 4: Dispatchers fail on unsupported platform

```yaml-task
id: 4
description: install_git, install_zsh and install_bats return 1 instead of 0 when neither MACOS nor LINUX is set
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: 'test "$(bats --count -f "install_bats: returns 1 when no platform matches" tests/setup_env/install_guards.bats)" -ge 1'
    exit_code: 0
  - cmd: bats tests/setup_env/install_guards.bats
    exit_code: 0
max_retries: 3
files_touched:
  - lib/helpers.sh
  - tests/setup_env/install_guards.bats
depends_on: []
parallel_group: wave-1
```

**Files:** `lib/helpers.sh` (`install_git` :246, `install_zsh` :254, `install_bats` :262), `tests/setup_env/install_guards.bats`.

**Change:** add to each dispatcher —

```bash
  else
    log_error "Unsupported platform — cannot install <pkg>"
    return 1
  fi
```

**An existing fall-through test pins rc 0.** It encodes the bug. Find it (`grep -n 'install_bats\|install_git\|install_zsh' tests/setup_env/install_guards.bats`), update its assertion to rc 1, and add the two missing siblings so all three dispatchers are covered.

**State plainly in the commit body that this is unreachable from production today** — all three call sites at `lib/workflows.sh:126,133,137` are guarded by the exact complement. It is included because Tasks 1 and 2 fix the callees beneath it, and a dispatcher returning a false zero would stop that propagation one level short.

**Interfaces:** Consumes nothing. Produces no new symbols.

**Wave note:** scoped gate only.

---

### Task 5: gnubin prefix parity test

```yaml-task
id: 5
description: Assert lib/macos.sh and 6_path.zsh carry the same two gnubin prefixes, so drift between the install guard and the PATH consumer fails the suite
role: executor
model: haiku
tdd: required
acceptance:
  - cmd: 'test "$(bats --count -f "gnubin prefixes match between lib/macos.sh and 6_path.zsh" tests/setup_env/install_guards.bats)" -ge 1'
    exit_code: 0
  - cmd: bats tests/setup_env/install_guards.bats
    exit_code: 0
max_retries: 3
files_touched:
  - tests/setup_env/install_guards.bats
depends_on: [4]
```

**Files:** `tests/setup_env/install_guards.bats` only. Add beside the existing `install_make_macos` cases.

**Exact test:**

```bash
@test "gnubin prefixes match between lib/macos.sh and 6_path.zsh" {
  local _bash_prefixes _zsh_prefixes
  _bash_prefixes="$(grep -oE '/(opt/homebrew|usr/local)/opt/make/libexec/gnubin' \
    "${REPO_ROOT}/lib/macos.sh" | sort -u)"
  _zsh_prefixes="$(grep -oE '/(opt/homebrew|usr/local)/opt/make/libexec/gnubin' \
    "${REPO_ROOT}/.config/.zshrc.d/6_path.zsh" | sort -u)"

  [ -n "${_bash_prefixes}" ]
  [ -n "${_zsh_prefixes}" ]
  [ "${_bash_prefixes}" = "${_zsh_prefixes}" ]
}
```

**Both non-empty assertions are load-bearing** — a grep matching nothing in both files makes the equality vacuously true. Do not remove them as redundant.

**Depends on Task 4** because it shares `install_guards.bats`; it is not in the wave for that reason alone.

**Interfaces:** none.

---

### Task 6: Delete the coverage publisher

```yaml-task
id: 6
description: Delete scripts/push-bash-coverage.sh, its make target, its 13 tests across two files, and its two doc references — the publisher has no live consumer
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: 'test ! -e scripts/push-bash-coverage.sh'
    exit_code: 0
  - cmd: 'grep -rn "push-bash-coverage" tests/ .github/ Makefile CLAUDE.md docs/adr/ docs/superpowers/README.md; test $? -eq 1'
    exit_code: 0
  - cmd: bats tests/scripts/unit.bats
    exit_code: 0
max_retries: 3
files_touched:
  - scripts/push-bash-coverage.sh
  - tests/scripts/push_bash_coverage.bats
  - tests/scripts/unit.bats
  - Makefile
  - CLAUDE.md
  - docs/adr/0008-bash-coverage-ps4-xtrace.md
depends_on: []
parallel_group: wave-1
```

**`tdd: not-applicable`** — a deletion writes no behaviour to test. Its correctness is proven by the grep assertion and by the suite staying green.

**Delete:** `scripts/push-bash-coverage.sh`; `tests/scripts/push_bash_coverage.bats` (11 cases); `tests/scripts/unit.bats` lines 665 and 673 (two cases invoking the script directly — these are **hard 127 failures** after deletion, not a count change); `Makefile` target at :114-118, its `.PHONY` entry at :47, its `help` line at :55; the `CLAUDE.md:332` sentence naming `make push-bash-coverage`; the ADR-0008 bullet at :31.

**Do not delete** `scripts/run-bash-coverage.sh`, `make bash-coverage`, or anything in `.github/`. CI publishes the badge on every PR and is unaffected.

**The grep assertion returns 38 matches now and must return none.** Its scope excludes `docs/superpowers/specs/` and `docs/superpowers/plans/` deliberately — five historical documents reference the script and _should_ keep doing so; they record what existed when written.

**ADR-0008 loses a bullet, not its status.** The PS4-xtrace decision stands; one delivery mechanism goes away.

**Interfaces:** none.

---

### Task 7: Close the backlog rows and index the plan

```yaml-task
id: 7
description: Update docs/superpowers/README.md — add this plan to All Plans, remove four closed backlog rows and two stale ones (docs-only, no behaviour change)
role: executor
model: haiku
tdd: not-applicable
acceptance:
  - cmd: 'grep -q "2026-08-14-silent-false-success-cluster" docs/superpowers/README.md'
    exit_code: 0
  - cmd: 'grep -c "push-bash-coverage" docs/superpowers/README.md; test $? -eq 1'
    exit_code: 0
max_retries: 3
files_touched:
  - docs/superpowers/README.md
depends_on: [1, 2, 3, 4, 5, 6]
```

**`tdd: not-applicable`** — index and prose only, no executable logic.

**Add** a row to All Plans: date `2026-08-14`, plan link, spec link, status `Done`.

**Remove these four backlog rows** (closed by this plan): `install_zsh_macos` reports a brew failure as success; `install_bats` dispatcher returns 0 when no platform matches; `push-bash-coverage.sh` misreports a missing bats as a red suite; gnubin prefix pair is duplicated across two languages.

**Remove these two stale rows** (already fixed by earlier work, verified this session): `make lint` cannot see the extensionless hooks — closed by the `git ls-files`-derived `SHELL_FILES` at `Makefile:14`; Coverage denominator heredoc bodies — closed by the exclusion at `scripts/run-bash-coverage.sh:212`.

**Add three follow-up rows** from the spec: the dead `push-bash-coverage` crontab entry (operator action, machine-local); `wsl2_workstation` possibly wrongly declared snap-less, affecting six `HAS_SNAP` sites in `lib/linux_ubuntu.sh`; `PROFILE_CAPS[server]` has no hostname mapping and an unmapped host silently receives zero capabilities.

**Interfaces:** none.

---

### Task 8: Aggregate verification and the three mutation checks

```yaml-task
id: 8
description: Run the full gate chain, execute three named mutation checks, and record the re-derived coverage figure with its denominator in CLAUDE.md
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: make test
    exit_code: 0
  - cmd: make lint
    exit_code: 0
  - cmd: make bash-coverage
    exit_code: 0
max_retries: 3
files_touched:
  - CLAUDE.md
depends_on: [1, 2, 3, 4, 5, 6, 7]
```

**`tdd: not-applicable`** — this task runs checks and records a measured figure; it writes no behaviour.

**Three mutation checks, each pinning a defect that shipped in a draft of the spec and survived a review round.** Apply the mutation, confirm the named case goes **red**, revert:

1. Replace `_apt_pkg_installed zsh && _apt_pkg_installed zsh-doc` with `quiet_which zsh` → `install_zsh_linux: installs when zsh-doc is absent` must fail.
2. Replace `_apt_pkg_installed`'s body with `dpkg-query -W "${1}" > /dev/null 2>&1` → `install_zsh_linux: installs when zsh is in rc state` must fail.
3. Revert any one `|| return 1` from Task 1 → the matching macOS propagation case must fail.

**Report the arithmetic, do not assert a direction:** cases added, 13 removed, net. Baseline was 1317 `ok`.

**Re-derive coverage rather than predicting it.** The denominator moves both ways — new error branches add coverable lines, `scripts/push-bash-coverage.sh` leaves the `git ls-files`-derived set. If the figure rises, confirm it rose because the new branches are covered and not because a low-coverage file exited the denominator. Update `CLAUDE.md`'s Bash coverage figure **with its denominator**; publish CI's number, not the local one, per that file's own standing rule.

**Interfaces:** none.
