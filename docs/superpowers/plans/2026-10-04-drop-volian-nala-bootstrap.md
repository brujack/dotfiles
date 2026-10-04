> **Status: DONE** — merged in #311 (2026-10-04).

# Drop Volian Nala Bootstrap Implementation Plan

spec: docs/superpowers/specs/2026-10-04-drop-volian-nala-bootstrap-design.md

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `check_and_install_nala` installs nala from the Ubuntu archive on every release; the unpinned root-installed volian debs, their tests and their confmiss allow-set entries are gone.

**Architecture:** Delete one `if [[ -z ${RESOLUTE} ]]` block in `lib/helpers.sh`; rework the nala tests around an argv probe; shrink the dpkg gate's confmiss allow-set to the Microsoft deb; docs.

**Tech Stack:** bash, bats.

## Global Constraints

- The nala line stays exactly `sudo -H DEBIAN_FRONTEND=noninteractive apt install "${APT_CONFFILE_OPTS[@]}" nala -y`.
- No new `apt update` (N3). `_install_ubuntu_powershell` and `packages-microsoft-prod.deb` handling unchanged (N2). No volian cleanup code (N1). The 2026-10-03 spec is not edited (N4).
- No tracked file under `lib/`, `scripts/`, `setup_env.sh`, `tests/` contains `volian` (R2).
- Shell standards: `[[ ]]`, `${VAR}`, `printf`, exact-path `git add`.

## Orchestrator steps

- [ ] O1. Run `git worktree add -b fix/drop-volian <wt> origin/master`, and put `<wt>` at the top of every dispatch.
- [ ] O2. After Task 2, run `make test < /dev/null > <scratch>/mt.log 2>&1` and record the result.
- [ ] O3. Run each V1 mutation and revert it with `git checkout -- <file>`:
  - re-add a `wget https://example.invalid/volian.deb` line inside `check_and_install_nala`: the NOBLE test goes red;
  - drop `"${APT_CONFFILE_OPTS[@]}"` from the nala line: the NOBLE test goes red;
  - delete the nala `apt install` line: the NOBLE and RESOLUTE tests go red;
  - add `--force-confmiss` to `_install_ubuntu_powershell`'s `apt install powershell` as `-o Dpkg::Options::=--force-confmiss`: the confmiss test goes red.
- [ ] O4. Run the changed bats files on the Studio from a `git bundle` clone in a bare env (V2).
- [ ] O5. Invoke `finishing-a-development-branch`. After the merge, add one sentence to ai-config's `docs/knowledge/dotfiles-apt-upgrade-hazards.md` §2b in a separate ai-config docs commit.

---

### Task 1: Delete the volian block and rework the tests

```yaml-task
id: 1
description: Remove the volian bootstrap from check_and_install_nala and update the nala tests and the dpkg gate's confmiss allow-set
role: executor
model: sonnet
tdd: required
requirements: [R1, R2, R3, R4, R5, R9]
acceptance:
  - cmd: bats tests/setup_env/install_functions.bats tests/scripts/dpkg_sudo_frontend.bats
    exit_code: 0
  - cmd: '! git grep -n -i volian -- lib scripts setup_env.sh tests'
    exit_code: 0
  - cmd: '[ "$(bats --count -f "check_and_install_nala on NOBLE" tests/setup_env/install_functions.bats)" -ge 1 ]'
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched: [lib/helpers.sh, tests/setup_env/install_functions.bats, tests/scripts/dpkg_sudo_frontend.bats]
depends_on: []
```

**Files:** as listed. The RED commit comes first: write the new NOBLE test, and watch it fail because the volian `wget` runs.

- **`lib/helpers.sh` `check_and_install_nala`:** delete the `if [[ -z ${RESOLUTE} ]]; then … fi` block, which holds both `wget`s, both `dpkg --install` calls with their comments, and `sudo -H apt update`. Leave everything else untouched.
- **`tests/setup_env/install_functions.bats`:**
  - Delete `check_and_install_nala: volian dpkg --install sees DEBIAN_FRONTEND=noninteractive` and `conffile argv: volian dpkg --install restores deleted conffiles (confmiss) on both debs`.
  - Delete `check_and_install_nala installs nala via dpkg and apt on Ubuntu when absent`; its case is the new NOBLE test.
  - Replace `check_and_install_nala on NOBLE uses volian wget path` with `check_and_install_nala on NOBLE installs nala from the Ubuntu archive`:
    - setup: `NOBLE=1`, `unset RESOLUTE`, nala absent;
    - `argv_probe_stub_path apt` first on PATH;
    - assert exactly one line equal to `argv: apt [install][-o][Dpkg::Options::=--force-confdef][-o][Dpkg::Options::=--force-confold][nala][-y]` (`grep -cxF`, count 1);
    - assert zero `wget` lines and zero `dpkg --install` lines in `MOCK_CALLS_FILE`. Use `grep -c` set equal to 0, not a negated grep, because `! grep` is a no-op under bats.
  - Rename `check_and_install_nala on RESOLUTE uses apt install, skips volian wget` to `check_and_install_nala on RESOLUTE installs nala from the Ubuntu archive`. Set `RESOLUTE=1` explicitly and keep its assertions, rewording any that mention volian into zero-`wget` counts.
  - In every other test that calls `check_and_install_nala`, set or unset `RESOLUTE` explicitly. That covers the non-Linux, non-Ubuntu, already-installed and DEBIAN_FRONTEND tests.
- **`tests/scripts/dpkg_sudo_frontend.bats`:**
  - `_CONFMISS_DEBS=(packages-microsoft-prod.deb)`;
  - rename the test `--force-confmiss appears exactly at the three archive-setup debs` to `--force-confmiss appears only at the packages-microsoft-prod.deb install`;
  - delete the `'lib/helpers.sh|sudo.*dpkg --install'` anchor line from the real-tree enumeration test, and keep the `'lib/linux_ubuntu.sh|sudo.*dpkg -i'` anchor.
- **Mutation-check the new NOBLE test** by dropping the options array from the nala line. It must go red; restore afterwards.

---

### Task 2: Docs and backlog

```yaml-task
id: 2
description: Update CLAUDE.md conffile bullet, ADR-0040 amendment note with cleanup command, and backlog rows (docs-only, no behavior change)
role: executor
model: sonnet
tdd: not-applicable
requirements: [R6, R7, R8]
acceptance:
  - cmd: '! grep -qi volian CLAUDE.md'
    exit_code: 0
  - cmd: 'grep -q "packages-microsoft-prod.deb" CLAUDE.md'
    exit_code: 0
  - cmd: 'grep -qE "Amend(ed|ment).*2026-10-04" docs/adr/0040-apt-conffile-prompts-answered-unattended.md'
    exit_code: 0
  - cmd: 'grep -q "apt purge -y volian-archive-keyring volian-archive-nala" docs/adr/0040-apt-conffile-prompts-answered-unattended.md'
    exit_code: 0
  - cmd: '! grep -q "Volian archive debs install as root" docs/superpowers/README.md'
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 2
files_touched: [CLAUDE.md, docs/adr/0040-apt-conffile-prompts-answered-unattended.md, docs/superpowers/README.md]
depends_on: [1]
```

**Files:** as listed. No file here is read by the suite, so gates are greps; the orchestrator runs `make test` (O2).

- **`CLAUDE.md`:** in the Shell Scripts conffile bullet, replace "the three archive-setup dpkg installs (`packages-microsoft-prod.deb` and the two volian debs)" with "the `packages-microsoft-prod.deb` install". Change no other text.
- **ADR-0040:** append a section `## Amendment (2026-10-04)`. It says:
  - the volian nala bootstrap was removed, and nala now comes from the Ubuntu archive on every release;
  - confmiss now sits only on `packages-microsoft-prod.deb`;
  - see `docs/superpowers/specs/2026-10-04-drop-volian-nala-bootstrap-design.md`;
  - the manual cleanup for a machine provisioned through the old path, verbatim from the spec: `sudo rm -f /etc/apt/sources.list.d/volian-archive-scar-unstable.sources /etc/apt/preferences.d/volian-archive-scar-unstable.pref && sudo apt purge -y volian-archive-keyring volian-archive-nala && sudo apt update`.

  Do not edit the original Decision text.
- **`docs/superpowers/README.md`:**
  - delete the row `Volian archive debs install as root with no integrity check`;
  - rewrite the row `Conffile repair misses machines whose install guard skips the call` so it names only the Microsoft package and `_pwsh_probe_runs`;
  - leave the All Plans row alone (added with the plan on master; orchestrator sets Done after merge).

## Non-goal check

Reviewer verdicts (fresh subagent, `nongoal-check.md`): N1, N2, N3, N4 all CLEAR. Borderline reasoning recorded by the reviewer: the ADR cleanup command is operator documentation, not code (N1, N3); the O3 confmiss mutation is reverted (N2); only ADR-0040 and the 2026-10-04 spec are edited (N4).
