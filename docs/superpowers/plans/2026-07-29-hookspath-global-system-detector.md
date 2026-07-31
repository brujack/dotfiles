# Global/System `core.hooksPath` Detector Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Detect a `core.hooksPath` pin at `--global` or `--system` scope — the only scope nothing in this repo reads, and the only one where a single value redirects or disables hooks in every repo on the box — and report it from both `-t update` and `-t doctor`.

**Architecture:** One detector, `_git_hooks_hookspath_offenders` in `lib/git_hooks.sh`, reads the two scopes explicitly and prints one line per pin. Two callers consume it: `install_git_hooks_all_repos` (the unattended surface) folds offenders into its existing counters and widens its return contract to signal partial success, and `_doctor_check_hooks_path` in `lib/helpers.sh` (the on-demand surface) maps offenders onto `doctor_fail`. Partial-success reporting reuses the `git-repos`/`legacy-rsync` rc=2 pattern rather than a new `_update_record_end` case arm.

**Tech Stack:** bash, BATS, git config scoped reads, `GIT_CONFIG_GLOBAL`/`GIT_CONFIG_SYSTEM` test seams.

## Global Constraints

- PR 2 of 2 from spec `docs/superpowers/specs/2026-07-29-doctor-hookspath-check-design.md`. **PR 1 (the `GIT_DIR` strip, plan `2026-07-29-hooks-sweep-gitdir-strip.md`) must be merged first** — Task 3 edits `install_git_hooks_all_repos`, the same function PR 1 touches.
- Read scopes **explicitly** (`--global`, `--system`). Never bare `git config --get core.hooksPath`: that returns the effective value after system→global→local precedence and cannot say which scope to unset.
- **No per-repo scan.** Spec Decision 1. Do not iterate `PERSONAL_GITREPOS`, do not add a worktree guard, do not add an allowlist.
- **Do not change the dotfiles `Makefile` `install-hooks` target.** Spec Decision 7: resolving via `--git-path hooks` plus `mkdir -p` creates the pinned directory, which makes `_git_hooks_dir`'s `[[ -d ]]` succeed and silences the PR #189 detection this whole design depends on.
- `git config --get` exits 1 when a key is unset. That is the clean path; never propagate it as failure.
- No `set -e` at top level. `lib/git_hooks.sh`'s sourcing guard stays the last line of the file.
- Bash coverage floor 90%, CI-blocking.

## Verification

**Session-level command:**

```bash
make test
```

Exit 0, reported test count above the current 1056 and not below it.

**Plus a real end-to-end check that no unit test covers** — the detector against a genuinely pinned global config, on this machine, without touching `~/.gitconfig`:

```bash
tmp=$(mktemp -d)
printf '[core]\n\thooksPath = /nonexistent/hooks\n' > "${tmp}/gitconfig"
GIT_CONFIG_GLOBAL="${tmp}/gitconfig" ./setup_env.sh -t doctor; echo "exit=$?"
rm -rf "${tmp}"
```

**Expected output:** a `[FAIL] global: pinned to /nonexistent/hooks — remedy: git config --global --unset core.hooksPath` line under a `Git hooksPath:` header, and a non-zero exit. Re-running without `GIT_CONFIG_GLOBAL` must show two PASS lines and leave the exit code driven only by the other checks.

**Edge cases that must be exercised:** both scopes set at once (two independent lines, neither masking the other); a pin whose path does not exist (still FAIL — Decision 3); the unset case not being mistaken for an error because `git config --get` exits 1.

---

### Task 1: `_git_hooks_hookspath_offenders` detector

```yaml-task
id: 1
description: Add _git_hooks_hookspath_offenders to lib/git_hooks.sh, printing one tab-separated scope/value line per pinned scope and returning 0 whether or not offenders exist
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: bats tests/setup_env/git_hooks.bats
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - lib/git_hooks.sh
  - tests/setup_env/git_hooks.bats
depends_on: []
```

**Files:** `lib/git_hooks.sh` (new function, placed after `_git_hooks_join` and before `install_git_hooks_all_repos`), `tests/setup_env/git_hooks.bats`.

**Contract.** Prints zero, one, or two lines of `scope<TAB>value`, where `scope` is literally `system` or `global`. Prints nothing when both are unset. Returns 0 in every case. Callers count lines; the exit code is never a verdict.

**A scope pinned to an EMPTY value is an offender and must be reported.** `git config --global core.hooksPath ""` writes `hooksPath =` — key present, value empty — and `git config --get` then exits **0 with empty stdout**, not 1. Git honors that pin: measured on git 2.55.0, a repo with an executable `.git/hooks/pre-commit` ran the hook 0 times under an empty global pin and 1 time with the pin removed. An empty pin therefore disables every hook on the machine, and skipping it would report "clean" on precisely the state this detector exists to name. Its record is `scope<TAB>` with an empty second field — a well-formed TSV line that `IFS=$'\t' read -r _scope _value` parses to scope set, value empty. Consumers render an empty value as `(empty)`.

> **Amended 2026-07-31 during Phase 2 execution.** The Task 1 code-quality review found the original implementation snippet's `[[ -z "${_value}" ]] && continue` produced a false clean on this input; the main agent reproduced it end-to-end before amending. Tasks 2 and 3 below carry matching `(empty)` rendering. A separate minor finding — that `|| continue` also swallows a scope git could not read at all (rc 128, e.g. a malformed config) — was **deliberately deferred to the backlog**, on the grounds that a corrupt gitconfig makes essentially every other git call fail loudly at the same moment. What that deferral does **not** establish: a _scope-specific_ read failure (e.g. `/etc/gitconfig` unreadable while `--global` reads fine) would still be reported as clean.

**Step 1 — write the first failing test** (unset case, the clean path — this is the one that catches treating `git config`'s exit 1 as an error):

```bash
@test "_git_hooks_hookspath_offenders prints nothing and returns 0 when neither scope is set" {
  local _g="${TESTDIR}/gitconfig-global" _s="${TESTDIR}/gitconfig-system"
  : > "${_g}"; : > "${_s}"
  GIT_CONFIG_GLOBAL="${_g}" GIT_CONFIG_SYSTEM="${_s}" run _git_hooks_hookspath_offenders
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
```

Run it: `bats tests/setup_env/git_hooks.bats -f "hookspath_offenders"`. It must fail with `command not found`, not an assertion failure.

**Step 2 — minimal implementation:**

```bash
# _git_hooks_hookspath_offenders prints one "scope<TAB>value" line per git
# scope that has core.hooksPath SET, where scope is literally "system" or
# "global". Prints nothing when neither is set. Contract: ALWAYS returns 0 --
# an empty result means "checked, clean", and callers count lines rather than
# reading the exit code as a verdict.
#
# A scope set to an EMPTY value is reported, not skipped: git treats an empty
# core.hooksPath as a real pin that disables hooks everywhere, while
# `git config --get` reports it as rc 0 with empty stdout. Skipping it would
# report "clean" on a machine with every hook silently off.
#
# Scopes are read explicitly rather than via a bare `git config --get`,
# which returns the EFFECTIVE value after system->global->local precedence
# and so cannot say which scope to unset -- the one thing the operator needs.
#
# No `env -u GIT_DIR ...` strip here, unlike every other git call in this
# file: neither read takes repo context, so an inherited GIT_DIR cannot
# redirect them. The strip is still required on the `make install-hooks`
# invocation, which does.
#
# There is deliberately NO per-repo arm. A per-clone pin that resolves has no
# route to a machine where it breaks (git never transfers .git/config; the
# two rsync destinations carry --exclude=personal since #182; the ratna push
# is archive-only), and every per-clone shape that CAN hurt is already caught
# by _git_hooks_check_complete's rc 1/2.
_git_hooks_hookspath_offenders() {
  local _scope _value
  for _scope in system global; do
    # --get exits 1 when unset. That is the normal clean path, not an error,
    # and must not leak out of this function as a failure.
    _value="$(git config "--${_scope}" --get core.hooksPath 2>/dev/null)" || continue
    printf '%s\t%s\n' "${_scope}" "${_value}"
  done
  return 0
}
```

Run the test — it passes. Commit.

**Step 3 — add the remaining cases one at a time**, running each to red before implementing (the implementation above already satisfies all of them; if a test passes immediately on first run, that is a signal the test is not exercising what it claims — check the fixture wiring before accepting it):

```bash
@test "_git_hooks_hookspath_offenders reports a global pin with its scope label" {
  local _g="${TESTDIR}/gc" _s="${TESTDIR}/sc"
  printf '[core]\n\thooksPath = /tmp/mine\n' > "${_g}"; : > "${_s}"
  GIT_CONFIG_GLOBAL="${_g}" GIT_CONFIG_SYSTEM="${_s}" run _git_hooks_hookspath_offenders
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'global\t/tmp/mine')" ]
}

@test "_git_hooks_hookspath_offenders reports a system pin with its scope label" {
  local _g="${TESTDIR}/gc" _s="${TESTDIR}/sc"
  : > "${_g}"; printf '[core]\n\thooksPath = /etc/hooks\n' > "${_s}"
  GIT_CONFIG_GLOBAL="${_g}" GIT_CONFIG_SYSTEM="${_s}" run _git_hooks_hookspath_offenders
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'system\t/etc/hooks')" ]
}

@test "_git_hooks_hookspath_offenders reports both scopes as separate lines, system first" {
  local _g="${TESTDIR}/gc" _s="${TESTDIR}/sc"
  printf '[core]\n\thooksPath = /tmp/mine\n' > "${_g}"
  printf '[core]\n\thooksPath = /etc/hooks\n' > "${_s}"
  GIT_CONFIG_GLOBAL="${_g}" GIT_CONFIG_SYSTEM="${_s}" run _git_hooks_hookspath_offenders
  [ "${#lines[@]}" -eq 2 ]
  [ "${lines[0]}" = "$(printf 'system\t/etc/hooks')" ]
  [ "${lines[1]}" = "$(printf 'global\t/tmp/mine')" ]
}

@test "_git_hooks_hookspath_offenders reports a pin whose path does not exist" {
  local _g="${TESTDIR}/gc" _s="${TESTDIR}/sc"
  printf '[core]\n\thooksPath = /nonexistent/nope\n' > "${_g}"; : > "${_s}"
  GIT_CONFIG_GLOBAL="${_g}" GIT_CONFIG_SYSTEM="${_s}" run _git_hooks_hookspath_offenders
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'global\t/nonexistent/nope')" ]
}

@test "_git_hooks_hookspath_offenders is idempotent across two calls in one shell" {
  local _g="${TESTDIR}/gc" _s="${TESTDIR}/sc"
  printf '[core]\n\thooksPath = /tmp/mine\n' > "${_g}"; : > "${_s}"
  local _first _second
  _first="$(GIT_CONFIG_GLOBAL="${_g}" GIT_CONFIG_SYSTEM="${_s}" _git_hooks_hookspath_offenders)"
  _second="$(GIT_CONFIG_GLOBAL="${_g}" GIT_CONFIG_SYSTEM="${_s}" _git_hooks_hookspath_offenders)"
  [ "${_first}" = "${_second}" ]
}
```

The two-scope test pins the order (`system` then `global`) because the loop is written `for _scope in system global` — assert the order the code produces, and if you change the loop order change the test with it.

**Step 4 — `make test`, then commit.**

**Interfaces:**

- Consumes: nothing from other tasks.
- Produces: `_git_hooks_hookspath_offenders` — no arguments, stdout `scope<TAB>value` lines with `scope ∈ {system, global}`, always exit 0. Tasks 2 and 3 both consume exactly this.

---

### Task 2: `_doctor_check_hooks_path` doctor surface

```yaml-task
id: 2
description: Add _doctor_check_hooks_path to lib/helpers.sh and wire it into run_doctor after _doctor_check_cred_dirs, mapping offenders onto doctor_fail with per-scope remedies
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: bats tests/setup_env/unit.bats
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - lib/helpers.sh
  - tests/setup_env/unit.bats
depends_on: [1]
parallel_group: wave-2
```

**Files:** `lib/helpers.sh` (new function after `_doctor_check_cred_dirs`, plus one line in `run_doctor`'s call list), `tests/setup_env/unit.bats`.

**Step 1 — write the failing clean-path test.** Follow the existing doctor-test conventions in `unit.bats` (87 `_doctor_check` references there already): reset `_DOCTOR_PASS`/`_DOCTOR_FAIL`/`_DOCTOR_FAILED` before the call and assert on the counters, not only on output text.

```bash
@test "_doctor_check_hooks_path passes both scopes when neither pins core.hooksPath" {
  local _g="${TESTDIR}/gc" _s="${TESTDIR}/sc"
  : > "${_g}"; : > "${_s}"
  _DOCTOR_PASS=0; _DOCTOR_FAIL=0; _DOCTOR_FAILED=0
  GIT_CONFIG_GLOBAL="${_g}" GIT_CONFIG_SYSTEM="${_s}" run _doctor_check_hooks_path
  [ "$status" -eq 0 ]
  [[ "$output" == *"Git hooksPath:"* ]]
  [[ "$output" == *"[PASS]"* ]]
}
```

**Step 2 — implement:**

```bash
_doctor_check_hooks_path() {
  printf "\nGit hooksPath:\n"
  local _offenders _scope _value
  _offenders="$(_git_hooks_hookspath_offenders)"

  local -a _pinned=()
  while IFS=$'\t' read -r _scope _value; do
    [[ -z "${_scope}" ]] && continue
    _pinned+=("${_scope}")
    # An empty value is a real pin that disables hooks, not an absent one --
    # render it so the FAIL line does not read "pinned to  --".
    [[ -z "${_value}" ]] && _value="(empty)"
    doctor_fail "${_scope}" \
      "pinned to ${_value} — remedy: git config --${_scope} --unset core.hooksPath"
  done <<< "${_offenders}"

  # Each scope reports independently: a pin at one must not suppress the
  # other's PASS, or an operator fixing the loud one has no signal that the
  # quiet one was ever checked.
  for _scope in system global; do
    local _found=0 _p
    for _p in "${_pinned[@]+"${_pinned[@]}"}"; do
      [[ "${_p}" == "${_scope}" ]] && _found=1
    done
    [[ ${_found} -eq 0 ]] && doctor_pass "${_scope}: unset"
  done
}
```

`"${_pinned[@]+"${_pinned[@]}"}"` is required rather than a bare `"${_pinned[@]}"`: the array is empty on the clean path and an unquoted-empty expansion errors under `set -u` if a caller ever enables it.

The `<<< "${_offenders}"` here-string yields one empty line when `_offenders` is empty, which the `[[ -z "${_scope}" ]] && continue` guard absorbs — that guard is load-bearing on the clean path, not defensive.

**Step 3 — wire into `run_doctor`.** In `lib/helpers.sh`, after `_doctor_check_cred_dirs` in the call list:

```bash
  _doctor_check_cred_dirs
  _doctor_check_hooks_path
  _doctor_check_versions
```

**Step 4 — add the remaining tests**, one at a time to red first:

```bash
@test "_doctor_check_hooks_path fails on a global pin and names the --global remedy" {
  local _g="${TESTDIR}/gc" _s="${TESTDIR}/sc"
  printf '[core]\n\thooksPath = /tmp/mine\n' > "${_g}"; : > "${_s}"
  _DOCTOR_PASS=0; _DOCTOR_FAIL=0; _DOCTOR_FAILED=0
  GIT_CONFIG_GLOBAL="${_g}" GIT_CONFIG_SYSTEM="${_s}" run _doctor_check_hooks_path
  [[ "$output" == *"[FAIL] global"* ]]
  [[ "$output" == *"git config --global --unset core.hooksPath"* ]]
  # the other scope still reports
  [[ "$output" == *"[PASS] system: unset"* ]]
}

@test "_doctor_check_hooks_path sets _DOCTOR_FAILED on a pin" {
  local _g="${TESTDIR}/gc" _s="${TESTDIR}/sc"
  printf '[core]\n\thooksPath = /tmp/mine\n' > "${_g}"; : > "${_s}"
  _DOCTOR_PASS=0; _DOCTOR_FAIL=0; _DOCTOR_FAILED=0
  GIT_CONFIG_GLOBAL="${_g}" GIT_CONFIG_SYSTEM="${_s}" _doctor_check_hooks_path > /dev/null
  [ "${_DOCTOR_FAILED}" -eq 1 ]
  [ "${_DOCTOR_FAIL}" -eq 1 ]
}

@test "_doctor_check_hooks_path reports both pins without either masking the other" {
  local _g="${TESTDIR}/gc" _s="${TESTDIR}/sc"
  printf '[core]\n\thooksPath = /tmp/mine\n' > "${_g}"
  printf '[core]\n\thooksPath = /etc/hooks\n' > "${_s}"
  _DOCTOR_PASS=0; _DOCTOR_FAIL=0; _DOCTOR_FAILED=0
  GIT_CONFIG_GLOBAL="${_g}" GIT_CONFIG_SYSTEM="${_s}" run _doctor_check_hooks_path
  [[ "$output" == *"[FAIL] global"* ]]
  [[ "$output" == *"[FAIL] system"* ]]
  [[ "$output" != *"[PASS]"* ]]
}

@test "_doctor_check_hooks_path fails on a pin whose directory does not exist" {
  local _g="${TESTDIR}/gc" _s="${TESTDIR}/sc"
  printf '[core]\n\thooksPath = /nonexistent/nope\n' > "${_g}"; : > "${_s}"
  _DOCTOR_PASS=0; _DOCTOR_FAIL=0; _DOCTOR_FAILED=0
  GIT_CONFIG_GLOBAL="${_g}" GIT_CONFIG_SYSTEM="${_s}" run _doctor_check_hooks_path
  [[ "$output" == *"[FAIL] global"* ]]
}

@test "_doctor_check_hooks_path fails on a scope pinned to an empty value and renders it (empty)" {
  local _g="${TESTDIR}/gc" _s="${TESTDIR}/sc"
  printf '[core]\n\thooksPath =\n' > "${_g}"; : > "${_s}"
  _DOCTOR_PASS=0; _DOCTOR_FAIL=0; _DOCTOR_FAILED=0
  GIT_CONFIG_GLOBAL="${_g}" GIT_CONFIG_SYSTEM="${_s}" run _doctor_check_hooks_path
  [[ "$output" == *"[FAIL] global"* ]]
  [[ "$output" == *"pinned to (empty)"* ]]
  [[ "$output" == *"[PASS] system: unset"* ]]
}

@test "run_doctor invokes the hooksPath check" {
  local _g="${TESTDIR}/gc" _s="${TESTDIR}/sc"
  : > "${_g}"; : > "${_s}"
  GIT_CONFIG_GLOBAL="${_g}" GIT_CONFIG_SYSTEM="${_s}" run run_doctor
  [[ "$output" == *"Git hooksPath:"* ]]
}
```

**Step 5 — `make test`, then commit.**

**Interfaces:**

- Consumes: `_git_hooks_hookspath_offenders` (Task 1) — stdout `scope<TAB>value`, always exit 0. `doctor_pass`/`doctor_fail` from `lib/helpers.sh:29,34`, which increment `_DOCTOR_PASS`/`_DOCTOR_FAIL` and set `_DOCTOR_FAILED=1` respectively.
- Produces: `_doctor_check_hooks_path`, no arguments, called only from `run_doctor`.

---

### Task 3: Sweep surface and partial-success reporting

```yaml-task
id: 3
description: Call the detector from install_git_hooks_all_repos, widen its return contract to 2 for partial success, and add the rc==2 warn mapping at the run_update call site following the git-repos pattern
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: bats tests/setup_env/git_hooks.bats tests/setup_env/workflows.bats
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - lib/git_hooks.sh
  - lib/workflows.sh
  - tests/setup_env/git_hooks.bats
  - tests/setup_env/workflows.bats
depends_on: [1]
parallel_group: wave-2
```

**Files:** `lib/git_hooks.sh` (`install_git_hooks_all_repos`), `lib/workflows.sh` (the `git-hooks` block at lines 499–501), `tests/setup_env/git_hooks.bats`, `tests/setup_env/workflows.bats`.

**Why rc=2 and not an `_update_record_end` case arm.** The spec says "case arm," but the structurally analogous sections do not use one. `lib/workflows.sh:481-485` shows the real pattern: `sync_git_repos` returns 2 for partial success, the call site maps 2→0 for `_update_record_end` (so the section is not marked FAIL), then calls `_update_warn` + `_update_write_detail_from_err`. `_update_record_end` itself falls through `*)` → `_result="updated"` as normal. Follow that; do not add a `git-hooks)` arm to `_update_record_end`.

**Step 1 — write the failing sweep test.** `install_git_hooks_all_repos` must report the offender and return 2 when a global pin exists and no `make` call failed:

```bash
@test "install_git_hooks_all_repos reports a global hooksPath pin and returns 2" {
  local _g="${TESTDIR}/gc" _s="${TESTDIR}/sc"
  printf '[core]\n\thooksPath = /tmp/pinned\n' > "${_g}"; : > "${_s}"
  GIT_CONFIG_GLOBAL="${_g}" GIT_CONFIG_SYSTEM="${_s}" run install_git_hooks_all_repos
  [ "$status" -eq 2 ]
  [[ "$output" == *"core.hooksPath pinned"* ]]
  [[ "$output" == *"global"* ]]
  [[ "$output" == *"/tmp/pinned"* ]]
}
```

**Step 2 — implement in `install_git_hooks_all_repos`.** Add a counter alongside the existing ones (near line 296):

```bash
  local _hookspath=0
  local -a _hookspath_lines=()
```

After the `_git_hooks_gap_repos` loop and before `_updated_str` is computed (i.e. after line 392), add:

```bash
  # A global/system pin is a cause, not a symptom: it redirects or disables
  # hooks in every repo on this box at once. Reported here rather than
  # per-repo because the per-repo shapes that can hurt are already covered
  # by _git_hooks_check_complete's rc 1/2 above, and because the remedy
  # differs -- `make install-hooks` cannot fix a pinned scope.
  local _hp_scope _hp_value
  while IFS=$'\t' read -r _hp_scope _hp_value; do
    [[ -z "${_hp_scope}" ]] && continue
    _hookspath=$((_hookspath + 1))
    # Empty value is a real pin that disables hooks -- see Task 1's Contract.
    [[ -z "${_hp_value}" ]] && _hp_value="(empty)"
    _hookspath_lines+=("${_hp_scope}: ${_hp_value}")
    log_warn "core.hooksPath pinned at ${_hp_scope} scope: ${_hp_value} (remedy: git config --${_hp_scope} --unset core.hooksPath)"
  done <<< "$(_git_hooks_hookspath_offenders)"
```

Extend the summary line, after the `_unknown` clause (line 409):

```bash
  if [[ ${_hookspath} -gt 0 ]]; then
    _summary+=", ${_hookspath} core.hooksPath pinned ($(_git_hooks_join '; ' "${_hookspath_lines[@]}"))"
  fi
```

`_git_hooks_join` takes the separator as its first argument; note that its multi-character separator behaviour is why it exists rather than `IFS='; '` with `${arr[*]}` — `${arr[*]}` joins on the _first character_ of `IFS` only, so a two-element list would render `a;b` not `a; b`. Assert the separator with a **two**-element fixture in the test below; a one-element list cannot see this class of bug.

Replace the return block (lines 419-420):

```bash
  # Contract: 0 clean, 1 a make call failed, 2 partial success -- gaps,
  # unknowns, or a pinned hooksPath, none of which a failed make explains.
  # 2 mirrors sync_git_repos/sync_legacy_dirs so run_update's existing
  # rc==2 warn mapping applies unchanged.
  [[ ${_failures} -gt 0 ]] && return 1
  if [[ ${_hookspath} -gt 0 || ${_gaps} -gt 0 || ${_unknown} -gt 0 ]]; then
    return 2
  fi
  return 0
}
```

**Step 3 — this widens the return contract, so existing tests will break.** Run `bats tests/setup_env/git_hooks.bats` and read every failure. Any test asserting `[ "$status" -eq 0 ]` on a fixture that has gaps or unknowns is now asserting the old contract and must be updated to expect 2. Do **not** weaken an assertion to `[ "$status" -ne 1 ]` to make it pass — change it to the specific expected value, or the test stops distinguishing clean from partial. Also check `tests/setup_env/workflows.bats` for sweep-invoking tests with the same shape.

**Step 4 — add the two-element separator test:**

```bash
@test "install_git_hooks_all_repos joins two hooksPath offenders with '; ' not ';'" {
  local _g="${TESTDIR}/gc" _s="${TESTDIR}/sc"
  printf '[core]\n\thooksPath = /tmp/one\n' > "${_g}"
  printf '[core]\n\thooksPath = /tmp/two\n' > "${_s}"
  GIT_CONFIG_GLOBAL="${_g}" GIT_CONFIG_SYSTEM="${_s}" run install_git_hooks_all_repos
  [ "$status" -eq 2 ]
  [[ "$output" == *"system: /tmp/two; global: /tmp/one"* ]]
}
```

**Step 4b — the empty-pin test.** An empty value is a real pin (Task 1 Contract) and must reach the summary as `(empty)`, never as a bare trailing space:

```bash
@test "install_git_hooks_all_repos renders a hooksPath pinned to an empty value as (empty)" {
  local _g="${TESTDIR}/gc" _s="${TESTDIR}/sc"
  printf '[core]\n\thooksPath =\n' > "${_g}"; : > "${_s}"
  GIT_CONFIG_GLOBAL="${_g}" GIT_CONFIG_SYSTEM="${_s}" run install_git_hooks_all_repos
  [ "$status" -eq 2 ]
  [[ "$output" == *"global: (empty)"* ]]
}
```

**Step 5 — the call site.** `lib/workflows.sh`, replace lines 499-501:

```bash
    _update_record_start "git-hooks"
    install_git_hooks_all_repos 2>&1 | tee "${_DOTFILES_RUN_TMPDIR}/err_git-hooks"
    _update_record_end "git-hooks" "${PIPESTATUS[0]}"
```

with:

```bash
    _update_record_start "git-hooks"
    install_git_hooks_all_repos 2>&1 | tee "${_DOTFILES_RUN_TMPDIR}/err_git-hooks"
    local _git_hooks_rc="${PIPESTATUS[0]}"
    _update_record_end "git-hooks" "$(( _git_hooks_rc == 2 ? 0 : _git_hooks_rc ))"
    if [[ ${_git_hooks_rc} -eq 2 ]]; then
      _update_warn "git-hooks" "gaps or a pinned core.hooksPath — see detail"
      _update_write_detail_from_err "git-hooks" "warning output"
    fi
```

This is the Decision 5 fix: without it the section renders as a bare `[OK] git-hooks updated` over its own findings, because `_update_record_end` writes `OK` unconditionally on the non-zero-exit-free path (`lib/update_summary.sh:367`).

**Step 6 — the summary regression test** in `tests/setup_env/workflows.bats`. Model it on the existing `git-repos` warn test at `tests/setup_env/workflows.bats:1336` (`run_update records git-repos as WARN (not OK) when sync_git_repos returns 2`):

```bash
@test "run_update marks git-hooks WARN, not OK, when the sweep returns 2" {
  # ... existing run_update harness setup from the git-repos WARN test ...
  install_git_hooks_all_repos() { printf 'core.hooksPath pinned at global scope\n'; return 2; }
  export -f install_git_hooks_all_repos 2>/dev/null || true
  run run_update
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_git-hooks")" = "WARN" ]
  [[ "$(cat "${_DOTFILES_RUN_TMPDIR}/result_git-hooks")" == *"core.hooksPath"* ]]
  # the regression this test exists for
  [ "$(cat "${_DOTFILES_RUN_TMPDIR}/status_git-hooks")" != "OK" ]
}
```

Copy the harness setup verbatim from `workflows.bats:1336-1351` rather than inventing one — `run_update` needs `_DOTFILES_RUN_TMPDIR`, the section mocks, and the flag vars already wired there.

**Step 7 — verify `_UPDATE_SECTION_ORDER` still contains `git-hooks`.** Per the coupling documented in `CLAUDE.md`, a section tracked but absent from that array is never printed. It is already present; confirm rather than assume:

```bash
grep -n 'git-hooks' lib/update_summary.sh
```

**Step 8 — `make test`, then commit.**

**Interfaces:**

- Consumes: `_git_hooks_hookspath_offenders` (Task 1); `_update_warn` and `_update_write_detail_from_err` (`lib/update_summary.sh:53,64`); `_git_hooks_join` (separator as `$1`).
- Produces: `install_git_hooks_all_repos` return contract widened from `{0,1}` to `{0,1,2}`, where 2 is partial success. Task 4 documents this.

---

### Task 4: Documentation

```yaml-task
id: 4
description: Document the new doctor check, the sweep's widened return contract, and the updated test count in CLAUDE.md, and mark the plan Done in the index (docs-only, no behavior change, so TDD does not apply)
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: 'grep -q "core.hooksPath" CLAUDE.md'
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - CLAUDE.md
  - docs/superpowers/README.md
depends_on: [2, 3]
```

**Files:** `CLAUDE.md`, `docs/superpowers/README.md`.

**`CLAUDE.md` — three edits:**

1. The `doctor` row of the Entry Points table currently reads "Active health checks: symlinks, tool presence, credential dir permissions, version drift." Add global/system hooksPath: `Active health checks: symlinks, tool presence, credential dir permissions, version drift, global/system core.hooksPath pins.`

2. Under Key Conventions, extend the existing `git-hooks` section-coupling bullet with the return contract:

   > `install_git_hooks_all_repos` returns 0 clean, 1 when a `make install-hooks` call failed, and 2 for partial success — gaps, unreadable hooks, or a `core.hooksPath` pinned at global/system scope. The `run_update` call site maps 2→0 for `_update_record_end` then calls `_update_warn`, the same shape `git-repos` and `legacy-rsync` use. Without that mapping the section renders `[OK] git-hooks updated` over its own findings.

3. Update the Testing section's bash test count and the CI regression-proxy figure if the added tests move it. Read the actual number from the `make test` output of Task 3 — do **not** guess. If the count crossed a threshold that `.github/workflows/ci.yml` pins (currently ≥840), leave the workflow alone; it is a floor, not an equality check.

**`docs/superpowers/README.md`:** the All Plans row for this work currently reads `| 2026-07-29 | hooksPath global/system check + sweep GIT_DIR strip | [spec](...) | Pending |`. Split it into the two plans this spec produced and set both to `Done`, linking each plan file:

```
| 2026-07-29 | [hooks-sweep-gitdir-strip](plans/2026-07-29-hooks-sweep-gitdir-strip.md) | [spec](specs/2026-07-29-doctor-hookspath-check-design.md) | Done |
| 2026-07-29 | [hookspath-global-system-detector](plans/2026-07-29-hookspath-global-system-detector.md) | [spec](specs/2026-07-29-doctor-hookspath-check-design.md) | Done |
```

Also add the `> **Status: DONE**` banner to the top of both plan files.

**Interfaces:**

- Consumes: the real test count from Task 3's `make test` run; the return contract from Task 3.
- Produces: nothing consumed by later tasks.

---

## Self-review

1. **Spec coverage:** Decision 1 → Task 1 (two scopes, no per-repo arm). Decision 2 → Task 1 (explicit scope reads). Decision 3 → Task 2 (`doctor_fail`, and the nonexistent-path test). Decision 4 → Tasks 2 and 3 (both surfaces). Decision 5 → Task 3 Steps 5-6. Decision 6 → PR 1, out of scope here. Decision 7 → Global Constraints as an explicit non-action. Fleet-evidence and Out-of-scope sections need no tasks.
2. **Placeholders:** none. The one place a value is not literal — the test count in Task 4 — explicitly says to read it from a real run rather than guess, per the magic-number rule.
3. **Type consistency:** `_git_hooks_hookspath_offenders` (no args, `scope<TAB>value`, exit 0) is named identically in Tasks 1, 2, 3. Scope labels are `system`/`global` throughout, matching the `--${_scope}` remedy interpolation.
4. **`files_touched` matches the prose** in every task, and includes the test file wherever `tdd: required`.
5. **Parallel group:** Tasks 2 and 3 share `wave-2` and both depend on Task 1. `files_touched` are disjoint — `lib/helpers.sh` + `unit.bats` versus `lib/git_hooks.sh` + `lib/workflows.sh` + `git_hooks.bats` + `workflows.bats`. Task 1 also touches `lib/git_hooks.sh` but runs strictly before both via `depends_on`.
6. **Acceptance gates are the aggregate** (`make test`, which chains `make lint` first in this repo), with scoped `bats` runs alongside for speed rather than instead.
7. **ADR check:** no new Phase 3 gate, no HOLD-capable check, no security guardrail, no storage or schema decision. This extends the existing `doctor` check pattern (established by the 2026-04-08 `doctor-enhanced` spec) and reuses the existing rc=2 partial-success convention. No ADR.
8. **Known risk, flagged not hidden:** Task 3 widens a return contract that existing tests assert. Step 3 exists specifically to force reading every resulting failure, and forbids weakening assertions to `-ne 1` to get green.
