# apt/dpkg Conffile Prompts Implementation Plan

spec: docs/superpowers/specs/2026-10-03-apt-conffile-noninteractive-design.md

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every apt/dpkg install a dotfiles workflow runs answers dpkg's conffile prompt without a terminal (confdef+confold), the three vendor archive-setup debs also restore a deleted conffile (confmiss), a test gate enforces both, and `-t doctor` reports kept-local conffile copies.

**Architecture:** One readonly array `APT_CONFFILE_OPTS` in `lib/constants.sh`, expanded at every configuring apt/apt-get/nala call; literal dpkg flags at the three archive-setup `dpkg` installs. `tests/scripts/dpkg_sudo_frontend.bats` gains a second verdict over its existing call tokenizer. A new `_doctor_check_conffile_dist` in `lib/helpers.sh`.

**Tech Stack:** bash, bats, awk (mawk/BWK-compatible, POSIX classes only), shellcheck.

## Global Constraints

- `APT_CONFFILE_OPTS=(-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)`, readonly.
- `--force-confmiss` only on `packages-microsoft-prod.deb`, `volian-archive-keyring_0.2.0_all.deb`, `volian-archive-nala_0.2.0_all.deb`. Nowhere else (N2).
- `remove`/`purge`/`autoremove`/`autopurge` calls unchanged (N3). `Vagrantfile` unchanged (N4). No wrapper between `sudo` and apt/apt-get/nala/dpkg (N5). Nothing written outside the repo by code under test (N1).
- Every sudo dpkg-running call keeps `DEBIAN_FRONTEND=noninteractive` directly after `sudo` and its flags (existing gate).
- Doctor check: no `sudo`, never moves/deletes/merges a file (N6); no `.dpkg-dist` reporting in `run_update`, `run_setup_or_developer` or `_UPDATE_SECTION_ORDER` (N7).
- Shell standards: `[[ ]]`, `${VAR}`, `printf`, `|| return 1`, no `set -e`; every new suppression carries a same-line reason.
- Per-task gates are scoped bats files plus `make lint`. The orchestrator runs the full `make test` after Task 4 (the suite is too long to put in every task gate).

## Verification (session level)

1. `make test` exits 0 in the worktree after Task 4, with the final pass line recorded.
2. V3 mutations, each run by the orchestrator and reverted with `git checkout -- <file>`:
   - delete `"${APT_CONFFILE_OPTS[@]}"` from `lib/linux_ubuntu.sh:46`. Expect the real-tree conffile test and the xargs argv test to go red;
   - delete `--force-confmiss` from the volian keyring line in `lib/helpers.sh`. Expect the confmiss test to go red;
   - in the detector, change the configuring-verb regex to `^NOMATCH$`. Expect the judged-count assertion to go red;
   - in `_doctor_check_conffile_dist`, change the `find` pattern to `*.nomatch`. Expect the nested and old-mtime cases to go red.
3. V1 and V2 real-tool probes on claude (Orchestrator steps below).

## Orchestrator steps

- [ ] O1. `git worktree add -b fix/apt-conffile <wt> origin/master`; dispatch every task with `<wt>` at the top of its prompt.
- [ ] O2. After Task 4: run `make test > <scratch>/mt.log 2>&1; echo rc=$?` in `<wt>`, then grep `not ok` and the summary line.
- [ ] O3. Run the V3 mutations (above), one at a time, and record red/green for each.
- [ ] O4. Run V2 on claude. Rebuild the scratchpad `dotfiles-cfprobe2` v1/v2 debs (one conffile, contents differ).
  - Copy the R5 flags from the final `lib/linux_ubuntu.sh:202`.
  - (a) Install v1, `rm` the conffile, run `dpkg -i v2` (no force) to get `iU`, then rerun with the R5 flags.
  - (b) Install v2, `rm` the conffile, run a same-version reinstall with the R5 flags.
  - Expect rc 0, `ii` and the file restored in both. Purge afterwards.
- [ ] O5. Run V1 on claude. Serve v1/v2 from a `file:` apt source whose `Packages` is built by hand with `dpkg-deb -f` plus Filename, Size and SHA256 (§2 method), and install v1.
  - Edit the conffile, then run the exact `xargs` line from `lib/linux_ubuntu.sh:46` against a one-line list naming the probe package, with stdin `</dev/null`.
  - Expect rc 0, `ii`, the edit kept and a `.dpkg-dist` written. `./setup_env.sh -t doctor` must WARN on it.
  - Then delete only the probe's `.dpkg-dist`; the next doctor run must no longer name it. Leave `/etc/default/grub.ucf-dist` for the operator; it keeps that check at WARN on claude (spec V1 amendment).
  - Remove the source and purge the package.
- [ ] O6. Invoke `finishing-a-development-branch`.

---

### Task 1: Conffile verdict in the dpkg sudo gate

```yaml-task
id: 1
description: Add the conffile verdict, array-token skip, confmiss allow-set, judged count and fixture cases to the dpkg sudo gate
role: executor
model: sonnet
tdd: required
requirements: [R8, R9, R10, R11, R12, R13]
acceptance:
  - cmd: 'bats -f "conffile detector" tests/scripts/dpkg_sudo_frontend.bats'
    exit_code: 0
  - cmd: '[ "$(bats --count -f "conffile detector" tests/scripts/dpkg_sudo_frontend.bats)" -ge 8 ]'
    exit_code: 0
  - cmd: 'bats -f "conffile options|confmiss appears" tests/scripts/dpkg_sudo_frontend.bats'
    exit_code: 1
  - cmd: 'bats -f "^(every dpkg-running|the real-tree|the detector )" tests/scripts/dpkg_sudo_frontend.bats'
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched: [tests/scripts/dpkg_sudo_frontend.bats]
depends_on: []
```

**Files:** `tests/scripts/dpkg_sudo_frontend.bats`

The real-tree tests are expected to be **red** at the end of this task. Tasks 2 and 3 make them green. That is why gate 3 expects exit 1.

- **Emitter.** Extend the awk so `judge()` also prints a conffile record per judged call: `<file>:<line>:conffile:<ok|bad>`. Print a separate `<file>:<line>:confmiss:<yes|no>:<deb-basename-or->` for every `dpkg` `-i|--install|--configure` call.
- **Configuring verbs.** apt/apt-get/nala with `install|reinstall|upgrade|full-upgrade|dist-upgrade|build-dep` are judged; any other verb is not judged.
- **Option check.** A call is `ok` if any token equals `"${APT_CONFFILE_OPTS[@]}"`, or if both `Dpkg::Options::=--force-confdef` and `Dpkg::Options::=--force-confold` appear anywhere in the call. For dpkg, `--force-confdef` and `--force-confold` must both appear anywhere in the call, not only in leading flags.
- **`classify()`.** In the apt/apt-get/nala flag-skip loop, also skip a token equal to `"${APT_CONFFILE_OPTS[@]}"`. Keep the existing frontend output format unchanged, so the existing tests still pass.
- **Real-tree tests.** Add two, named exactly as below. Reuse `_tracked_shell_files`.
  - `every configuring apt/dpkg sudo call carries the conffile options`: fails on any `conffile:bad` record. It asserts that the count of `conffile:` records is greater than 0 (R9, separate from the frontend guard).
    - On failure it prints the file and line, the apt fix (`"${APT_CONFFILE_OPTS[@]}"`, or the two literal `-o Dpkg::Options::=` options in a file that cannot source `lib/constants.sh`) and the dpkg fix (`--force-confdef --force-confold`).
    - The message names `dotfiles-apt-upgrade-hazards.md` §2.
  - `--force-confmiss appears exactly at the three archive-setup debs`: uses `_CONFMISS_DEBS=(packages-microsoft-prod.deb volian-archive-keyring_0.2.0_all.deb volian-archive-nala_0.2.0_all.deb)`.
    - Each name matches exactly one `confmiss:` record, and that record is `yes`.
    - Every `confmiss:yes` record names one of the three.
- **Fixture tests.** Every name starts with `the conffile detector`, and there are at least 8 (R13 plus one for the confmiss emitter):
  - array after verb: `ok`
  - array before verb (`sudo DEBIAN_FRONTEND=noninteractive apt "${APT_CONFFILE_OPTS[@]}" install x -y`): `ok`, and also judged by the frontend verdict
  - literal pair: `ok`
  - no options: `bad`
  - confdef only: `bad`
  - `dpkg -i ./x.deb --force-confdef --force-confold`: `ok`
  - `apt remove x -y`: no conffile record
  - a dpkg line carrying confmiss: `confmiss:yes:x.deb`
- **Comment.** Update the header comment: add the second verdict to the description, and state that the blind-spot list applies to it too.

---

### Task 2: Shared array at every apt/apt-get/nala site

```yaml-task
id: 2
description: Define APT_CONFFILE_OPTS and add it to every configuring apt/apt-get/nala sudo call, literal options in bootstrap, with argv tests
role: executor
model: sonnet
tdd: required
requirements: [R1, R2, R3, R4, R7, R14]
acceptance:
  - cmd: 'bats --jobs 8 tests/setup_env/linux_ubuntu.bats tests/setup_env/linux_shared.bats tests/setup_env/install_functions.bats tests/setup_env/install_guards.bats tests/setup_env/workflows.bats tests/setup_env/developer.bats tests/scripts/unit.bats'
    exit_code: 0
  - cmd: '[ "$(bats --count -f "conffile argv" tests/setup_env/linux_ubuntu.bats)" -ge 2 ]'
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched: [lib/constants.sh, lib/linux_ubuntu.sh, lib/linux_shared.sh, lib/helpers.sh, lib/developer.sh, lib/workflows.sh, scripts/bootstrap_linux.sh, tests/helpers/common.bash, tests/setup_env/linux_ubuntu.bats]
depends_on: [1]
```

**Files:** as listed.

- **`lib/constants.sh`.** Add `readonly -a APT_CONFFILE_OPTS=(-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)`, with a one-line reason pointing at `dotfiles-apt-upgrade-hazards.md` §2.
- **Call sites.** Add `"${APT_CONFFILE_OPTS[@]}"` after the verb at every call the Task 1 detector judges as configuring, in `lib/`. Get the list with the detector's `conffile:bad` output.
  - In the 5 xargs lines (`lib/linux_ubuntu.sh:46,47,52,53,70`) it goes after `install -y`, in the fixed part.
  - `lib/linux_shared.sh` `update_apt_packages`: replace the two literal `-o Dpkg::Options::=` options with the array. Keep the `< /dev/null` and the comment, updated to name the array.
  - `scripts/bootstrap_linux.sh:35`: literal `-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold` after `install`. Add a comment saying it runs before `lib/` is sourced.
- **`tests/helpers/common.bash`.** Add `argv_probe_stub_path <name>`: same shape as `frontend_probe_stub_path`, but it writes `argv: <name> <arg>` once per argument (`for _a in "$@"`), so separate arguments are distinguishable from one argument containing spaces.
- **`tests/setup_env/linux_ubuntu.bats`.** Add tests named `conffile argv: ...`:
  - The xargs+nala base install. Put an argv probe for `xargs` first on PATH, call the noble branch of the function holding `:46`, and assert the lines `argv: xargs -o`, `argv: xargs Dpkg::Options::=--force-confdef`, `argv: xargs Dpkg::Options::=--force-confold` appear.
  - One direct `sudo … apt install` site. Use `_install_ubuntu_albert` or the closest already-tested single apt install. The argv probe for `apt` must show the same three separate lines.
- **Do not touch** remove, purge or autoremove calls, or any dpkg call. Task 3 owns those.

---

### Task 3: confdef/confold/confmiss at the three archive-setup dpkg installs

```yaml-task
id: 3
description: Add --force-confdef --force-confold --force-confmiss with reason comments to the powershell and two volian dpkg installs, with argv tests
role: executor
model: sonnet
tdd: required
requirements: [R5, R6, R14]
acceptance:
  - cmd: bats tests/scripts/dpkg_sudo_frontend.bats
    exit_code: 0
  - cmd: 'bats --jobs 8 tests/setup_env/linux_ubuntu.bats tests/setup_env/install_functions.bats'
    exit_code: 0
  - cmd: '[ "$(bats --count -f "conffile argv" tests/setup_env/linux_ubuntu.bats tests/setup_env/install_functions.bats)" -ge 4 ]'
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched: [lib/linux_ubuntu.sh, lib/helpers.sh, tests/setup_env/linux_ubuntu.bats, tests/setup_env/install_functions.bats]
depends_on: [2]
```

**Files:** as listed.

- **The three dpkg calls.** `lib/linux_ubuntu.sh` `_install_ubuntu_powershell` `dpkg -i`, and the two `dpkg --install` calls in `lib/helpers.sh` `check_and_install_nala`.
  - Add `--force-confdef --force-confold --force-confmiss` after `dpkg -i`/`--install`.
  - Comment each call: the package carries only a vendor apt keyring/source, so restoring a deleted file is always right here, and nowhere else (spec Decision, §2b).
- **`tests/setup_env/linux_ubuntu.bats`.** Add `conffile argv: powershell dpkg -i`, reusing the setup of the existing `_install_ubuntu_powershell: dpkg -i sees DEBIAN_FRONTEND` test. With `argv_probe_stub_path dpkg`, assert separate `argv: dpkg --force-confdef`, `--force-confold` and `--force-confmiss` lines.
- **`tests/setup_env/install_functions.bats`.** Add `conffile argv: volian dpkg --install`, reusing the setup of `check_and_install_nala: volian dpkg --install sees DEBIAN_FRONTEND`. Assert the same three lines appear for each of the two debs: count `argv: dpkg --force-confmiss` lines = 2.
- After this task the whole `dpkg_sudo_frontend.bats` must be green.

---

### Task 4: `_doctor_check_conffile_dist`

```yaml-task
id: 4
description: Add a Linux-only doctor check reporting every *.dpkg-dist and *.ucf-dist under /etc, register it, and stub it in run_doctor tests
role: executor
model: sonnet
tdd: required
requirements: [R15, R16, R17, R18]
acceptance:
  - cmd: 'bats --jobs 8 tests/setup_env/doctor_conffile_dist.bats tests/setup_env/unit.bats tests/setup_env/plugin_node_paths.bats'
    exit_code: 0
  - cmd: '[ "$(bats --count tests/setup_env/doctor_conffile_dist.bats)" -ge 8 ]'
    exit_code: 0
  - cmd: 'a=$(grep -rhE "_doctor_check_pyenv_shims\(\) +\{ :; \}" tests | wc -l); b=$(grep -rhE "_doctor_check_conffile_dist\(\) +\{ :; \}" tests | wc -l); [ "$a" -gt 0 ] && [ "$a" -eq "$b" ]'
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched: [lib/helpers.sh, tests/setup_env/doctor_conffile_dist.bats, tests/setup_env/unit.bats, tests/setup_env/plugin_node_paths.bats]
depends_on: [3]
```

**Files:** as listed. The new test file follows `tests/setup_env/doctor_pyenv_shims.bats`'s setup.

`_doctor_check_conffile_dist` in `lib/helpers.sh`, placed next to `_doctor_check_gnu_coreutils`:

```bash
_doctor_check_conffile_dist() {
  [[ -n ${LINUX} ]] || return 0
  printf "\nKept conffile copies:\n"
  local _root="${_OVERRIDE_CONFFILE_DIST_ROOT:-/etc}" _f _n=0
  if [[ ! -d "${_root}" || ! -r "${_root}" ]]; then
    doctor_warn "${_root}" "not a readable directory; cannot scan for .dpkg-dist/.ucf-dist"
    return 0
  fi
  while IFS= read -r -d '' _f; do
    _n=$(( _n + 1 ))
    doctor_warn "${_f}" "package copy kept beside your file; diff it against ${_f%.*-dist}, merge, then delete it (empty diff: just delete)"
  done < <(find "${_root}" \( -name '*.dpkg-dist' -o -name '*.ucf-dist' \) -print0 2>/dev/null)
  [[ ${_n} -gt 0 ]] || doctor_pass "no .dpkg-dist or .ucf-dist under ${_root}"
}
```

- The header comment states:
  - why this check exists (confold took away the prompt; spec);
  - that unprivileged `find` misses root-only dirs (7 on claude, 0 conffiles under them);
  - that `*.dpkg-new`/`*.ucf-new` are deliberately not matched;
  - why there is no timestamp test (dpkg keeps the archive mtime).
- Register it in `run_doctor` after `_doctor_check_gnu_coreutils`.
- `tests/setup_env/doctor_conffile_dist.bats`: `export LINUX=1`, `_OVERRIDE_CONFFILE_DIST_ROOT` = fixture dir. The cases:
  - nested `.dpkg-dist` reported, with path and `diff`;
  - nested `.ucf-dist` reported;
  - `touch -d 2020-01-01` `.dpkg-dist` reported;
  - `.dpkg-new` not reported;
  - empty root: one `[PASS]`, no `[WARN]`;
  - missing root: one `[WARN]`, no `[PASS]`;
  - `LINUX` unset: empty output;
  - `_DOCTOR_FAILED -eq 0` after a WARN case.
- Add `_doctor_check_conffile_dist() { :; }` beside every `_doctor_check_pyenv_shims() { :; }` stub: 4 in `tests/setup_env/unit.bats`, 1 in `tests/setup_env/plugin_node_paths.bats` (counted at `65e65259`; re-count first).
  - Anchor on `pyenv_shims`, not `gnu_coreutils`: one `unit.bats` test omits the `gnu_coreutils` stub and relies on `RESOLUTE` being unset. This check is gated on `LINUX`, which a developer's interactive shell exports, so an unstubbed `run_doctor` test would scan the real `/etc` on claude. That is read-only but changes the WARN count, because `/etc/default/grub.ucf-dist` exists there.
- Every case in `doctor_conffile_dist.bats` sets or unsets `LINUX` explicitly; none inherits it.

---

### Task 5: Docs, ADR, backlog

```yaml-task
id: 5
description: Document the conffile policy, seam and doctor check; ADR-0040; close two backlog rows and add the R19 row (docs-only, no behavior change)
role: executor
model: sonnet
tdd: not-applicable
requirements: [R19]
acceptance:
  - cmd: grep -q 'APT_CONFFILE_OPTS' CLAUDE.md
    exit_code: 0
  - cmd: grep -q '_OVERRIDE_CONFFILE_DIST_ROOT' CLAUDE.md
    exit_code: 0
  - cmd: test -f docs/adr/0040-apt-conffile-prompts-answered-unattended.md
    exit_code: 0
  - cmd: grep -q '0040' docs/adr/README.md
    exit_code: 0
  - cmd: '! grep -q "cannot answer a dpkg conffile prompt" docs/superpowers/README.md'
    exit_code: 0
  - cmd: 'grep -qE "guards skip|install guard" docs/superpowers/README.md'
    exit_code: 0
max_retries: 2
files_touched: [CLAUDE.md, docs/adr/0040-apt-conffile-prompts-answered-unattended.md, docs/adr/README.md, docs/superpowers/README.md]
depends_on: [4]
```

**Files:** as listed. No file here is read by the suite, so the gates are greps. The orchestrator's `make test` (O2) covers the suite.

- **`CLAUDE.md`.**
  - Shell Scripts bullets: next to the `DEBIAN_FRONTEND` bullet, add one bullet: every configuring apt/apt-get/nala call carries `"${APT_CONFFILE_OPTS[@]}"`, confmiss only at the three archive-setup debs, enforced by `tests/scripts/dpkg_sudo_frontend.bats`.
  - Entry Points `doctor` line: add the kept-conffile check.
  - Test Seams: a one-line `_OVERRIDE_CONFFILE_DIST_ROOT` bullet.
- **`docs/adr/0040-…`** (Nygard: Context, Decision, Consequences, Related). Cover:
  - confold everywhere, plus the rejected alternatives (drop-in, wrapper, literals);
  - confmiss scoped to the three debs, with the measured table;
  - the guard limitation (R19);
  - the doctor check replacing a run-scoped advisory, and why (the mtime measurement).
  - Add the row to `docs/adr/README.md`.
- **`docs/superpowers/README.md`.**
  - Delete the two closed P2 rows.
  - Add a P2 bugs row from R19: packages already at `iU` from an earlier conffile failure, and the three R5 packages at `ii` with a deleted keyring/source, which the R5 callers' install guards skip. Point the row at the spec.
  - Leave this plan's All Plans row (added In Progress with the plan); the orchestrator sets Done after merge.

## Non-goal check

Reviewer verdicts (fresh subagent, `nongoal-check.md`): N2–N7 CLEAR. N1 UNCLEAR.

- **N1** — quote: "O5. … Then delete it and `/etc/default/grub.ucf-dist` … (also O4: install v1, `rm` the conffile, run `dpkg -i v2` …)". Resolution: N1 binds the delivered code; V1/V2 require the real-tool probes, which touch only the throwaway probe package and its own files. Deleting the operator's pre-existing `/etc/default/grub.ucf-dist` was removed. Spec amendment to V1 (in `## Amendments`), and O5 changed:
  - before: "Then delete it and `/etc/default/grub.ucf-dist`; the next doctor run must PASS that check."
  - after: "Then delete only the probe's `.dpkg-dist`; the next doctor run must no longer name it. Leave `/etc/default/grub.ucf-dist` for the operator; it keeps that check at WARN on claude (spec V1 amendment)."
