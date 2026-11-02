# run_update Flag Scoping Implementation Plan

> **Status: DONE** (dotfiles#418, merged 2026-11-02)

spec: docs/superpowers/specs/2026-11-02-run-update-flag-scoping-design.md

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a flagless `run_update` coverage pin, then scope the 10 bats tests that assert one flag-gated section to that section's flag.

**Architecture:** Test-only. Task 1 adds two pins to `tests/setup_env/workflows.bats` that run a flagless `run_update` and require every `_UPDATE_SECTION_ORDER` name to appear in the summary with a result other than `flag not set`. Tasks 2 and 3 add `export UPDATE_<X>=1` lines to 4 tests in `workflows.bats` and 6 in `cargo_tools_update.bats`, and drop those flags from their `unset` lines.

**Tech Stack:** bash 5, bats 1.13, GNU make.

## Global Constraints

- Changes only in `tests/**/*.bats` and `docs/` (N1). No new `run_update` flag or selector (N2). No lint, ratchet or guard on flagless counts (N3). `tests/bats-weights.tsv` unchanged (N5).
- No assertion line in an existing `@test` body is removed or changed (N4). A scoped test's diff only adds `export UPDATE_<X>=1` lines before its `run_update` call and removes `UPDATE_<X>` from its `unset` line (R2).
- A scoped test asserting on pyenv-shims, cargo-tools or gems also sets `UPDATE_PIP` (R6). These single-flag tests keep exactly one flag: `unit.bats` "run_update --gems-only ...", `cargo_tools_update.bats` lines 44 and 54, `update_pyenv_shims.bats` line 308.
- Tests asserting on ai-config, git-repos, legacy-rsync, git-hooks, aws, rust, cheat.sh, tfenv, oh-my-zsh, tpm or zsh-autosuggestions stay flagless (R4; all inside the `_run_all`-only block at `lib/workflows.sh:1301`).
- Mutation controls run in a copy: `D=$(mktemp -d) && git archive HEAD | tar -x -C "$D"`, work only in `$D`, and `rm -rf -- "$D"` (path written out) before reporting. After each `sed`, `grep` the mutated line to prove it changed; a non-matching `sed` is a silent no-op.

## Verification

- Session level: `make test` exits 0 at the head; every `test-shard` and `test-macos-shard` leg passes (V1).
- `bats --count` per touched file is unchanged by Tasks 2 and 3, and up by exactly 2 for `workflows.bats` after Task 1 (V1).
- The pin goes red under each control (Task 1): whole gems block deleted (V4), `_run_all` arm removed from the gems gate and from the pyenv-shims gate (V5), and `_UPDATE_SECTION_ORDER` emptied. Prototyped 2026-11-02 in an archive copy of `669795ef`: both pins `ok` on the clean tree; both `not ok` with `flagless run skipped gems: [SKIP] gems  flag not set` under the gems V5 control; `not ok` with the array emptied.
- One scoped test per flag used turns red when its section is broken (V3): `UPDATE_BREW` (Task 2), `UPDATE_PKGS` (Task 2), `UPDATE_BREW`+`UPDATE_PIP` (Task 3).
- Edge cases: both platforms' variable sets; a section name containing `.` (`cheat.sh`); a summary detail line that starts with `[WARN]  git-repos:` and must not count as a row.

## Classification (plan-time re-count, 2026-11-02)

Scan: per tracked `.bats`, a test body (ending at the next `@test`) that names `run_update`, sets no `UPDATE_*=` and does not call `setup_run_update_linux`. 91 hits.

Scoped (R1, 10 tests):

| Test                                                                                           | Flag(s)                     | Absence-assert producer (R3)                                                                                                                                                                                                                                                                                                                                                          |
| ---------------------------------------------------------------------------------------------- | --------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `workflows.bats:1350` "run_update calls brew update on macOS"                                  | `UPDATE_BREW`               | —                                                                                                                                                                                                                                                                                                                                                                                     |
| `workflows.bats:1418` "run_update calls apt on Ubuntu"                                         | `UPDATE_PKGS`               | —                                                                                                                                                                                                                                                                                                                                                                                     |
| `workflows.bats:2181` "run_update skips softwareupdate on Linux"                               | `UPDATE_BREW`               | `softwareupdate` in `run_update` comes only from the brew block (`lib/workflows.sh:879`) and `_update_softwareupdate_labels` (`lib/update_summary.sh:119`, reached from `_update_record_start "softwareupdate"` in that block); `lib/macos.sh:31,236` are setup-only (`install_rosetta`, `install_macos_packages`), not reached by `run_update`. Brew block runs under `UPDATE_BREW`. |
| `workflows.bats:2248` "run_update Linux packages block skips apt with not applicable on macOS" | `UPDATE_PKGS`               | —                                                                                                                                                                                                                                                                                                                                                                                     |
| `cargo_tools_update.bats:64, 76, 102, 131, 152, 165` (six cargo-tools tests)                   | `UPDATE_BREW`, `UPDATE_PIP` | `:64`, `:131`, `:152` assert `status_cargo-tools` `!=`; the only writer is the cargo-tools block (`lib/workflows.sh:1416-1446`), run under `UPDATE_BREW`.                                                                                                                                                                                                                             |

Keep-full (81 tests), by reason:

- **R4, `_run_all`-only section (58):** `workflows.bats` 2705, 2724, 2736, 2757, 2773, 2784, 2792, 2803, 2811, 2822, 2866, 2890, 2898, 2922, 2954, 2996, 3018, 3060, 3080, 3105, 3122, 3138, 3153, 3167, 3182, 3199, 3216, 3232, 3248, 3264, 3280, 3302, 3314, 3323, 3333, 3361, 3397, 3456, 3467, 3518, 3532, 3550, 3569, 3585, 3601, 3616, 3632, 3659, 3675; `update_noop_skip.bats` 59, 66, 75, 84, 91, 101, 110; `update_claude.bats` 81, 100.
- **Already scoped by `_claude_only_env` (5, heuristic miss):** `workflows.bats` 3754, 3764, 3774, 3785, 3794.
- **Class 2, name says no flags or full run (4):** `workflows.bats` 1372, 2235; `unit.bats` 1225; `update_pyenv_shims.bats` 110.
- **Class 2, whole-run behaviour (4):** `workflows.bats` 1476, 1498 (run dir), 2830 (cwd); `unit.bats` 525 (abort before any section).
- **Not a candidate, names `run_update` without a flagless run (10):** `workflows.bats` 1339, 2122, 2693, 4271; `unit.bats` 765, 1204; `flatpak.bats` 271; `linux_shared.bats` 94, 133; `ledger_integration.bats` 158.

Line numbers are at `669795ef`; Task 1 appends at the end of `workflows.bats`, so they hold through Task 2.

---

### Task 1: Flagless coverage pin

```yaml-task
id: 1
description: Add macOS and Ubuntu flagless run_update pins that require every _UPDATE_SECTION_ORDER name in the summary with a result other than flag not set
role: executor
model: sonnet
tdd: required
requirements: [R5]
acceptance:
  - cmd: bats tests/setup_env/workflows.bats -f 'reaches every section'
    exit_code: 0
    stdout_match: 'ok 2 run_update with no flags reaches every section on Ubuntu'
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [tests/setup_env/workflows.bats]
depends_on: []
```

**Files:** append to the end of `tests/setup_env/workflows.bats`.

- [ ] Append exactly:

```bash

# ── flagless run_update coverage pin ─────────────────────────────────────────
# A run with no UPDATE_* flag must reach every section in _UPDATE_SECTION_ORDER.
# Every flag-gated block in run_update has an `else _update_skip ... "flag not set"`
# branch, so a gate that loses its `${_run_all} -eq 1 ||` arm still writes a row;
# only the "flag not set" check below catches that. The count check stops an
# empty or unsourced array from passing with nothing checked.
_assert_flagless_run_reaches_every_section() {
  local _name _rx _row _checked=0
  [ "${#_UPDATE_SECTION_ORDER[@]}" -gt 0 ]
  for _name in "${_UPDATE_SECTION_ORDER[@]}"; do
    _rx="\\[(OK|FAIL|SKIP|WARN)\\][[:space:]]+${_name//./\\.}([[:space:]]|\$)"
    _row="$(printf '%s\n' "${output}" | grep -E "${_rx}")" || {
      printf 'no summary row for %s\n' "${_name}" >&2
      return 1
    }
    [[ "${_row}" != *"flag not set"* ]] || {
      printf 'flagless run skipped %s: %s\n' "${_name}" "${_row}" >&2
      return 1
    }
    _checked=$((_checked + 1))
  done
  [ "${_checked}" -eq "${#_UPDATE_SECTION_ORDER[@]}" ]
}

@test "run_update with no flags reaches every section on macOS" {
  export MACOS=1
  unset LINUX UBUNTU
  unset UPDATE_BREW UPDATE_PIP UPDATE_GEMS UPDATE_MAS UPDATE_CLAUDE UPDATE_PKGS
  run run_update
  _assert_flagless_run_reaches_every_section
}

@test "run_update with no flags reaches every section on Ubuntu" {
  unset MACOS
  export LINUX=1 UBUNTU=1 NOBLE=1
  unset UPDATE_BREW UPDATE_PIP UPDATE_GEMS UPDATE_MAS UPDATE_CLAUDE UPDATE_PKGS
  run run_update
  _assert_flagless_run_reaches_every_section
}
```

- [ ] **Red first (V4, V5, empty array).** In an archive copy of the task's HEAD, run `bats tests/setup_env/workflows.bats -f 'reaches every section'` under each mutation, restoring `lib/workflows.sh` from `git show HEAD:lib/workflows.sh` between them. Each must print `not ok` for both pins (the empty-array control: at least the one it runs):
  1. V4: delete the whole gems block (`lib/workflows.sh`, the `if [[ ${_run_all} -eq 1 ]] || [[ -n ${UPDATE_GEMS:-} ]]` block through its `fi`, `else` included).
  2. V5 gems: `sed -i 's/if \[\[ \${_run_all} -eq 1 \]\] || \[\[ -n \${UPDATE_GEMS:-} \]\]; then/if [[ -n ${UPDATE_GEMS:-} ]]; then/' lib/workflows.sh`; `grep -c 'if \[\[ -n \${UPDATE_GEMS:-} \]\]; then' lib/workflows.sh` must print 1.
  3. V5 pyenv-shims: remove `[[ ${_run_all} -eq 1 ]] || ` from the gate at `lib/workflows.sh:1230` (`UPDATE_BREW || UPDATE_PIP`); grep the line to prove it changed.
  4. Empty array: insert `local -a _UPDATE_SECTION_ORDER=()` as the helper's first line in the copy's test file.
- [ ] Report each control's command, its grep proof and the `not ok` lines. Delete the copy.
- [ ] Gates, then commit (`caveman:caveman-commit`).

**Interfaces:** Produces `_assert_flagless_run_reaches_every_section` (reads bats `$output`); nothing later depends on it.

### Task 2: Scope four workflows.bats tests

```yaml-task
id: 2
description: Scope workflows.bats tests at lines 1350, 1418, 2181 and 2248 to UPDATE_BREW or UPDATE_PKGS, with a V3 break-the-section control per flag
role: executor
model: sonnet
tdd: required
requirements: [R1, R2, R3, R4]
acceptance:
  - cmd: bats tests/setup_env/workflows.bats -f 'brew update on macOS|calls apt on Ubuntu|skips softwareupdate on Linux|skips apt with not applicable on macOS'
    exit_code: 0
  - cmd: 'bash -c ''git diff "$(git merge-base origin/master HEAD)" -- tests/setup_env/workflows.bats | grep -E "^-[^-]" | grep -vE "^-[[:space:]]*unset( UPDATE_[A-Z]+)+[[:space:]]*$"; test $? -eq 1'''
    exit_code: 0
  - cmd: 'bash -c ''test "$(git diff "$(git merge-base origin/master HEAD)" -- tests/setup_env/workflows.bats | grep -cE "^\+[[:space:]]*export UPDATE_(BREW|PKGS)=1$")" -eq 4'''
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [tests/setup_env/workflows.bats]
depends_on: [1]
```

**Edits** (no other line in these bodies changes):

| Line | Add before `run`/`run_update` | `unset` line change                |
| ---- | ----------------------------- | ---------------------------------- |
| 1350 | `export UPDATE_BREW=1`        | drop `UPDATE_BREW`                 |
| 1418 | `export UPDATE_PKGS=1`        | none (`UPDATE_PKGS` is not listed) |
| 2181 | `export UPDATE_BREW=1`        | none (no `unset` line)             |
| 2248 | `export UPDATE_PKGS=1`        | drop `UPDATE_PKGS`                 |

- [ ] Make the edits. Run the first gate. Task 1 removes no line and adds no `export UPDATE_` line, so the two diff gates see only this task's edits.
- [ ] **V3 controls** in an archive copy: (a) break `brew update` in `brew_update` (`lib/helpers.sh:300`, e.g. rename the subcommand) and show `:1350` goes `not ok`; (b) break the apt call the `:1418` grep matches (in `update_apt_packages`, `lib/linux_shared.sh`) and show `:1418` goes `not ok`. Grep-prove each mutation, report command and `not ok` line, delete the copy. A test that stays green moves to keep-full; report it as a blocker.
- [ ] Gates, then commit.

**Interfaces:** Consumes nothing from Task 1 beyond the file being appended (line numbers above are unchanged).

### Task 3: Scope six cargo_tools_update.bats tests

```yaml-task
id: 3
description: Scope the six flagless cargo-tools tests to UPDATE_BREW plus UPDATE_PIP (R6), with a V3 break-the-section control
role: executor
model: sonnet
tdd: required
requirements: [R1, R2, R3, R6]
acceptance:
  - cmd: bats tests/setup_env/cargo_tools_update.bats
    exit_code: 0
  - cmd: 'bash -c ''git diff "$(git merge-base origin/master HEAD)" -- tests/setup_env/cargo_tools_update.bats | grep -E "^[-+][^-+]" | grep -vE "^[-+][[:space:]]*(export UPDATE_[A-Z]+=1|unset( UPDATE_[A-Z]+)+)[[:space:]]*$"; test $? -eq 1'''
    exit_code: 0
  - cmd: 'bash -c ''test "$(git diff "$(git merge-base origin/master HEAD)" -- tests/setup_env/cargo_tools_update.bats | grep -cE "^\+[[:space:]]*export UPDATE_(BREW|PIP)=1$")" -eq 12'''
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched: [tests/setup_env/cargo_tools_update.bats]
depends_on: [2]
```

**Edits:** in each of the tests at lines 64, 76, 102, 131, 152 and 165, replace
`unset UPDATE_BREW UPDATE_PIP UPDATE_GEMS UPDATE_MAS UPDATE_CLAUDE UPDATE_PKGS` with three lines:

```bash
  export UPDATE_BREW=1
  export UPDATE_PIP=1
  unset UPDATE_GEMS UPDATE_MAS UPDATE_CLAUDE UPDATE_PKGS
```

Do not touch the tests at lines 44 (`--brew-only`) and 54 (`--pip-only`): they must keep one flag (R6).

- [ ] Make the edits. Run the first gate.
- [ ] **V3 control** in an archive copy: change `_update_record_end "cargo-tools" "$(( _cargo_tools_rc == 2 ? 0 : _cargo_tools_rc ))"` (`lib/workflows.sh:1437`) to `_update_record_end "cargo-tools" 1`; grep-prove it; show `:165` ("marks cargo-tools OK") goes `not ok`. Report, delete the copy.
- [ ] Gates, then commit.

### Orchestrator, after Task 3

- [ ] `make test` once at the head.
- [ ] V2: re-run the scan; record per-file flagless counts before (91) and after (81) in the PR body, with this plan's keep-full list.
- [ ] V6: one before/after pair on `claude` of `tests/setup_env/workflows.bats tests/setup_env/cargo_tools_update.bats` at `bats --jobs 8 < /dev/null`, `/usr/bin/time -a -o`, `uptime` per run; report against ~11 s (spec amendment). Note the two new pins add about 3 s of full runs.
- [ ] Mark this plan and the spec index row Done on merge.

## Non-goal check

Reviewer (opus, 2026-11-02) against N1-N5: all CLEAR, 0 CONFLICT, 0 UNCLEAR. Near-misses it named, no resolution needed:

- N1: the plan edits `lib/workflows.sh` only inside throwaway `git archive` copies for mutation controls; the branch's changes stay in `tests/**/*.bats` and `docs/`.
- N4: Task 3 rewrites an `unset` line into `export` lines plus a narrower `unset`; that is setup, not an assertion line.
