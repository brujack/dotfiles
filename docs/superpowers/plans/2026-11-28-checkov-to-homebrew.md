# Move checkov to Homebrew Implementation Plan

spec: docs/superpowers/specs/2026-11-28-checkov-to-homebrew-design.md

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove `checkov` from the shared `uv.lock` so virtualenv reaches a fixed release, and install checkov from Homebrew on devtools machines instead.

**Architecture:** One deleted `pyproject.toml` line and a cooldown-respecting relock; one `Brewfile.devtools` entry and one entry in the Linux brew formula loop; tests pin the absence and both install paths; ADR-0063 records what moves out of Dependabot's view.

**Tech Stack:** bash, bats, pinned uv 0.13.0 (`resolve_pinned_uv`), Homebrew.

## Global Constraints

- Lock and renderings use only the pinned uv: `uv="$(bash -c 'source lib/constants.sh; source lib/helpers.sh; resolve_pinned_uv')"`.
- 14-day cooldown (ADR-0057): virtualenv and packaging land at their newest release at least 14 days before the commit; no other package changes version (N1).
- `uv.lock` carries no `exclude-newer` option (R5).
- `checkov` goes in `Brewfile.devtools` only, never `Brewfile` or `Brewfile.gui` (N4).
- No new install function, update section or migration code (N3).
- No edit outside dotfiles in any task (N2); the etch-config and terraform_ansible Backlog rows are orchestrator steps.
- `make test` runs near the Bash tool's 600 s cap, so task gates are scoped; the orchestrator runs `make test </dev/null` once after Task 2 and again after Task 3.

## Verification

- `make test </dev/null` exits 0 on the branch (orchestrator, after Task 2 and Task 3).
- `python3 scripts/uv_lock_cooldown.py verify <master uv.lock> uv.lock <cutoff>` exits 0 (V1, Task 1 gate).
- Edge cases: `make check-lock` passes (no `exclude-newer`); the Linux install test fails if `checkov` is dropped from the loop; the pyproject test fails if `checkov` is re-declared.
- Post-merge V2-V6 are orchestrator steps (below).

---

### Task 1: Remove checkov from the lock

```yaml-task
id: 1
description: Delete the checkov declaration, relock under the 14-day cooldown, re-render, and replace the floor test with an absence test
role: executor
model: sonnet
tdd: required
requirements: [R1, R4, R5, R6]
acceptance:
  - cmd: 'bats -f "declares no checkov" tests/setup_env/developer.bats'
    exit_code: 0
    stdout_match: 'ok 1 pyproject.toml declares no checkov'
  - cmd: '! bats -f "checkov carries a floor" tests/setup_env/developer.bats | grep -q "^ok"'
    exit_code: 0
  - cmd: 'make check-lock </dev/null'
    exit_code: 0
  - cmd: 'make check-requirements-ci </dev/null'
    exit_code: 0
  - cmd: '! grep -q exclude-newer uv.lock'
    exit_code: 0
  - cmd: '! grep -qiE "^(name = \")?(checkov|asteval|ecdsa)(\"|==)" uv.lock requirements-ci.txt requirements-runtime-ci.txt requirements-ci-test.txt requirements-ci-mutation.txt requirements-ci-audit.txt'
    exit_code: 0
  - cmd: 'git show origin/master:uv.lock > "${TMPDIR:-/tmp}/base-uv.lock" && python3 scripts/uv_lock_cooldown.py verify "${TMPDIR:-/tmp}/base-uv.lock" uv.lock "$(date -u -d "14 days ago" +%Y-%m-%dT%H:%M:%SZ)"'
    exit_code: 0
  - cmd: 'make lint </dev/null'
    exit_code: 0
max_retries: 3
files_touched: [pyproject.toml, uv.lock, requirements-ci.txt, requirements-runtime-ci.txt, requirements-ci-test.txt, requirements-ci-mutation.txt, requirements-ci-audit.txt, tests/setup_env/developer.bats]
depends_on: []
```

- [ ] RED: in `tests/setup_env/developer.bats`, replace the test `checkov carries a floor at or above 3.3.13` with:

```bash
@test "pyproject.toml declares no checkov" {
  # checkov pins packaging<24, asteval==1.0.6 and ecdsa; declared in the shared lock it
  # held virtualenv below its fixed release (12 advisories). It installs from Homebrew
  # instead (Brewfile.devtools, ADR-0063); a re-declaration would re-block virtualenv.
  local _manifest="${BATS_TEST_DIRNAME}/../../pyproject.toml"
  [ -f "${_manifest}" ]
  grep -q '"ansible"' "${_manifest}"   # positive control: wrong path cannot pass
  if grep -qE '^\s*"checkov' "${_manifest}"; then
    printf "checkov is declared in pyproject.toml again\n" >&2
    return 1
  fi
}
```

Run `bats -f "declares no checkov" tests/setup_env/developer.bats`: must FAIL (checkov declared).

- [ ] In the boto3 test's comment (`pyproject.toml no longer declares boto3`), replace "The package itself is still INSTALLED -- checkov and cloudsplaining both require it -- so this pins the declaration only." with "checkov and cloudsplaining were its last dependents and left the lock with checkov (ADR-0063), so boto3 is no longer installed at all; this pins the declaration."
- [ ] GREEN: delete the `"checkov>=3.3.13",` line and every comment line attached to it (from `# terraform static analysis.` through `# cost. Revisit when upstream unpins.`) in `pyproject.toml`; nothing else in the file changes.
- [ ] Relock with the pinned uv (`$uv` per Global Constraints), in order:
  1. `"$uv" lock`
  2. `"$uv" lock --upgrade-package virtualenv --exclude-newer "$(date -u -d '14 days ago' +%Y-%m-%dT%H:%M:%SZ)"`
  3. `"$uv" lock` (removes the `exclude-newer` option)
  4. `make sync-requirements-ci </dev/null`
- [ ] Check N1 with a tomllib diff of `{name: version}` between `git show origin/master:uv.lock` and `uv.lock`: only removals (42 expected) plus `virtualenv` and `packaging` changed. Report the two new versions.
- [ ] Run every acceptance gate; commit (`caveman:caveman-commit`).

**Interfaces:** Produces the relocked `uv.lock`; Task 2 edits `developer.bats` after this task.

---

### Task 2: Install checkov from Homebrew on devtools machines

```yaml-task
id: 2
description: Add checkov to Brewfile.devtools with an ADR pointer comment and to the Linux brew formula loop, with tests for both
role: executor
model: sonnet
tdd: required
requirements: [R2, R3, R7]
acceptance:
  - cmd: 'bats -f "checkov installs only from Brewfile.devtools" tests/setup_env/developer.bats'
    exit_code: 0
    stdout_match: 'ok 1 checkov installs only from Brewfile.devtools'
  - cmd: 'bats -f "installs checkov via brew" tests/setup_env/linux_ubuntu.bats'
    exit_code: 0
    stdout_match: 'ok 1 _install_ubuntu_brew_packages: installs checkov via brew'
  - cmd: 'bats tests/setup_env/developer.bats tests/setup_env/linux_ubuntu.bats tests/setup_env/install_guards.bats </dev/null'
    exit_code: 0
  - cmd: 'make lint </dev/null'
    exit_code: 0
max_retries: 3
files_touched: [Brewfile.devtools, lib/linux_ubuntu.sh, tests/setup_env/developer.bats, tests/setup_env/linux_ubuntu.bats]
depends_on: [1]
```

- [ ] RED: add to `tests/setup_env/developer.bats`:

```bash
@test "checkov installs only from Brewfile.devtools" {
  local _root="${BATS_TEST_DIRNAME}/../.."
  grep -qx 'brew "ggshield"' "${_root}/Brewfile.devtools"   # positive control
  grep -qx 'brew "checkov"' "${_root}/Brewfile.devtools"
  run grep -q '"checkov"' "${_root}/Brewfile"
  [ "$status" -eq 1 ]
  run grep -q '"checkov"' "${_root}/Brewfile.gui"
  [ "$status" -eq 1 ]
}
```

Add to `tests/setup_env/linux_ubuntu.bats` after `installs uv via brew`:

```bash
@test "_install_ubuntu_brew_packages: installs checkov via brew" {
  run _install_ubuntu_brew_packages
  [ "$status" -eq 0 ]
  grep -qx "brew install checkov" "${MOCK_CALLS_FILE}"
}
```

Run both by `-f`: must FAIL.

- [ ] GREEN: in `Brewfile.devtools`, after `tap "snyk/tap"` and before `brew "ggshield"`, add
      `# vendors asteval 1.0.6 and ecdsa 0.19.2 with open advisories; see docs/adr/0063-checkov-from-homebrew.md`
      then `brew "checkov"`. In `lib/linux_ubuntu.sh` `_install_ubuntu_brew_packages`, add `checkov` to the `for _f in` list after `cargo-cyclonedx`.
- [ ] Mutation control: remove `checkov` from the loop, confirm the Linux test fails, restore.
- [ ] Run every acceptance gate; commit.

**Interfaces:** Consumes Task 1's `developer.bats`. The comment names `docs/adr/0063-checkov-from-homebrew.md`, which Task 3 creates.

---

### Task 3: ADR-0063 and Backlog

```yaml-task
id: 3
description: Write ADR-0063 and its index row and close both checkov Backlog rows (docs-only, no behaviour change, so TDD does not apply)
role: executor
model: sonnet
tdd: not-applicable
requirements: [R8, R9]
acceptance:
  - cmd: 'for g in GHSA-9w56-46f6-3qhx GHSA-89v8-rhwq-hf77 GHSA-wj6h-64fc-37mp pip-audit cooldown etch third-party; do grep -qi -- "$g" docs/adr/0063-checkov-from-homebrew.md || { echo "missing $g"; exit 1; }; done'
    exit_code: 0
  - cmd: 'grep -q "0063-checkov-from-homebrew.md" docs/adr/README.md'
    exit_code: 0
  - cmd: '! grep -nE "^\| (30 Dependabot alerts, all held by checkov|30 .virtualenv. alerts blocked by .checkov)" docs/superpowers/README.md | grep -v "~~"'
    exit_code: 0
  - cmd: 'make lint </dev/null'
    exit_code: 0
max_retries: 2
files_touched: [docs/adr/0063-checkov-from-homebrew.md, docs/adr/README.md, docs/superpowers/README.md]
depends_on: [2]
```

- [ ] Write `docs/adr/0063-checkov-from-homebrew.md` in the shape of `docs/adr/0062-ci-root-writes-scan.md` (`**Status:** Accepted`, Date 2026-11-28; Context, Decision, Consequences, Related). Content from the spec's Problem and Design 6: why Homebrew (alternatives rejected); GHSA-9w56-46f6-3qhx, GHSA-89v8-rhwq-hf77 (asteval 1.0.6) and GHSA-wj6h-64fc-37mp (ecdsa 0.19.2) still inside the formula; the whole vendored tree (about 40 packages) unmonitored by Dependabot and upgraded by `brew upgrade` with no 14-day cooldown; manual re-check `pip-audit --path <site-packages>` located via `ls "$(brew --prefix checkov)/libexec/lib"`; the third-party-policy expiry condition (from the deleted `pyproject.toml` comment); the etch-config transient; the laptop and work macs' architecture unmeasured (an Intel devtools mac builds from source). No rollout steps or dated measurements (those go in the PR body). Related: ADR-0057, spec path.
- [ ] Add the `| [0063](0063-checkov-from-homebrew.md) | Install checkov from Homebrew, outside the shared uv lock | 2026-11-28 | Accepted |` row to `docs/adr/README.md` after 0062.
- [ ] In `docs/superpowers/README.md` delete the two rows `30 Dependabot alerts, all held by checkov's pins` and `30 \`virtualenv\` alerts blocked by \`checkov\`'s \`packaging<24\` pin`.
- [ ] Run gates; commit.

---

## Orchestrator steps (not dispatched)

1. After Task 2 and after Task 3: `make test </dev/null` exits 0, with the root-path snapshot unchanged.
2. Commit the etch-config and terraform_ansible Backlog rows in their own repos (N2), each in a worktree, messaging the owning session first.
3. Before merge, with operator approval: `/home/linuxbrew/.linuxbrew/bin/brew install checkov` on `claude` and `workstation`, `/opt/homebrew/bin/brew install checkov` on the Studio; V2 (`"$(brew --prefix)/bin/checkov" --version` exits 0 on each).
4. Open the PR, then message ai-config and state-ledger with the PR number and the packaging move (V6); record the rollout in the PR body.
5. After merge: V3 on the three machines (after the operator's `-t update`), V4, V5.

## Non-goal check

Reviewer output (`nongoal.json`): N1 CLEAR, N2 CLEAR, N3 CLEAR, N4 CLEAR. No CONFLICT or UNCLEAR, so no plan revision or amendment followed.

- N1: the 42 removals are not version changes; only virtualenv and packaging are upgraded, and Task 1's tomllib diff checks it.
- N2: every dispatched task writes inside dotfiles; the etch-config and terraform_ansible rows are separate orchestrator commits.
- N3: Task 2 extends the existing `_install_ubuntu_brew_packages` loop; no new function, section or migration code.
- N4: checkov goes in `Brewfile.devtools` only, and Task 2's test asserts `Brewfile` and `Brewfile.gui` carry none.
