# Plugin node repair: atomic rewrite and setup call Implementation Plan

spec: docs/superpowers/specs/2026-10-21-plugin-node-repair-setup-design.md

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `repair_plugin_node_paths` never truncates a config, tells the operator how to fix what it cannot, and runs from `-t setup`/`-t developer` after the package step.

**Architecture:** Replace the in-place `printf >` with mktemp-beside, `cp -p`, write, `mv -f`, with explicit cleanup and a `-w` refusal. Add one unconditional call in `run_setup_or_developer` between the platform package block and `install_cargo_tools`, warning on rc 1.

**Tech Stack:** bash, bats, PATH mocks in `tests/mocks/`.

## Global Constraints

- No change to `_plugin_stale_node_paths`, `_doctor_check_plugin_node_paths` or `run_update`'s `plugin-node` section (N1).
- No snapshot or comparison of node versions gates the repair (N2).
- No EXIT or RETURN trap in `lib/helpers.sh` (N3; `scripts/check-lib-exit-traps.sh` runs in `make lint`).
- Remedy suffixes, exact: `— run: brew install <formula>` (missing `opt/` link) and `— check write permission and free space in <dir>` (failed rewrite), appended after the existing text.
- Setup warning, exact: `plugin node paths: some pins could not be repaired — see the 'cannot repair' lines above`.
- Verified apparatus (writing-plans item 10): `tests/mocks/mv` honours `MOCK_MV_FAIL_ARGS`; `tests/mocks/cp` exits on `MOCK_CP_EXIT` before the real copy; `mktemp` fails in a `chmod 555` directory; the read-only test is `plugin_node_paths.bats:151`; the ordering test pattern is `cargo_tools_update.bats:191`, whose `setup()` sets `HOME` to a temp dir and `MACOS=1`.

## Verification

- Session gate: the orchestrator runs `make test` once after Task 2 (Task 3 is docs and cannot change the suite).
- After merge (V2, operator): on `workstation`, after the next `-t developer` that upgrades linuxbrew node, `./setup_env.sh -t doctor` reports `no plugin pins a missing node binary`.

---

### Task 1: atomic rewrite with cause-specific remedies

```yaml-task
id: 1
description: Make repair_plugin_node_paths write via mktemp-beside + cp -p + mv -f, refuse non-writable configs, clean up on any failure, and append a remedy to each cannot-repair line
role: executor
model: sonnet
tdd: required
requirements: [R1, R2, R3, R4, R7]
acceptance:
  - cmd: bats --jobs 24 tests/setup_env/plugin_node_paths.bats
    exit_code: 0
  - cmd: make lint
    exit_code: 0
  - cmd: '! command grep -qE ''printf .*> "\$\{_file\}"'' lib/helpers.sh'
    exit_code: 0
max_retries: 3
files_touched: [lib/helpers.sh, tests/setup_env/plugin_node_paths.bats]
depends_on: []
```

**Files:** `lib/helpers.sh` (`repair_plugin_node_paths`, ~line 1574), `tests/setup_env/plugin_node_paths.bats` (repair tests ~121-210; helpers `_make_brew_node`, `_make_plugin`).

**Steps:**

- [ ] Write failing tests (spec Testing 1, 2, 2b, 3, 3b), each `run repair_plugin_node_paths` with status asserted:
  1. `export MOCK_MV_FAIL_ARGS="${_dir}/hooks/hooks.json"`: status 1, config byte-identical (`cmp` against a saved copy), `run ls "${_dir}/hooks"` shows no `hooks.json.*`, output has `rewrite failed`.
  2. `chmod 555 "${_dir}/hooks"` (root-skip like :151), status 1, config byte-identical; `chmod 755` before the assertions so teardown can delete it.
     2b. `export MOCK_CP_EXIT=1`: status 1, config byte-identical, no `hooks.json.*` left.
  3. seed `chmod 640` on the config: status 0, mode still 640 via `stat -c %a "$f" 2>/dev/null || stat -f %Lp "$f"`, config holds `${STABLE_NODE}` and not `${STALE_NODE}`, no `hooks.json.*` left.
     3b. missing-opt case (no `_make_brew_node`): output has `— run: brew install node`; rewrite-failed case (0444 file): output has `— check write permission and free space in`.
- [ ] Run `bats tests/setup_env/plugin_node_paths.bats -f repair_plugin_node_paths < /dev/null`; confirm new tests fail on assertions.
- [ ] Implement per spec Design → atomic rewrite: `[[ -w ]]` refusal first; `_tmp="$(mktemp "${_file}.XXXXXX")"`, `cp -p "${_file}" "${_tmp}"`, `printf '%s\n' "${_content//"${_node}"/"${_stable}"}" > "${_tmp}"`, `mv -f "${_tmp}" "${_file}"`; on any failure `[[ -n ${_tmp} ]] && rm -f "${_tmp}"`, print the failed-rewrite line with remedy, `_failed=1`, `continue`. Keep the quoted-replacement comment. Append the missing-opt remedy using the existing `_formula`. Update the function's header comment to say the write is atomic.
- [ ] Gates; commit via `caveman:caveman-commit`.

**Interfaces:** contract unchanged: rc 0/1/2 as today; stdout `repaired …`, stderr `cannot repair …` lines.

### Task 2: call the repair from run_setup_or_developer

```yaml-task
id: 2
description: Call repair_plugin_node_paths unconditionally in run_setup_or_developer after the platform package block and before install_cargo_tools, warning on rc 1 and silent on rc 2
role: executor
model: sonnet
tdd: required
requirements: [R5, R6]
acceptance:
  - cmd: bats --jobs 24 tests/setup_env/cargo_tools_update.bats tests/setup_env/plugin_node_paths.bats
    exit_code: 0
  - cmd: make lint
    exit_code: 0
  - cmd: 'awk ''/^run_setup_or_developer\(\)/{f=1} f&&/install_ubuntu_packages \|\| _pkgs_rc/{u=NR} f&&/repair_plugin_node_paths/{r=NR} f&&/install_cargo_tools \|\|/{c=NR} f&&/^}/{exit} END{exit !(u && r && c && u<r && r<c)}'' lib/workflows.sh'
    exit_code: 0
max_retries: 3
files_touched: [lib/workflows.sh, tests/setup_env/cargo_tools_update.bats]
depends_on: [1]
```

**Files:** `lib/workflows.sh` (`run_setup_or_developer`, ~line 557), `tests/setup_env/cargo_tools_update.bats` (beside the run_setup_or_developer tests at ~175-215).

**Steps:**

- [ ] Write failing tests (spec Testing 6-9), stubbing `install_macos_packages`/`install_ubuntu_packages`/`install_cargo_tools`/`install_aws_tools`/`setup_vim_plugins` as the neighbouring tests do, and `repair_plugin_node_paths` as a function: 6. order log (`:191` pattern): `install_macos_packages`, then `repair_plugin_node_paths`, then `install_cargo_tools` — assert each line present and in order. 7. repair stub `return 1`: status 0; output has the exact warning; `install_cargo_tools` still ran. 8. repair stub `return 2`: status 0; `[[ "$output" != *"plugin node paths"* ]]`; repair stub's marker present (so the call happened). 9. `unset MACOS; export UBUNTU=1 LINUX=1`: order log shows `install_ubuntu_packages` before `repair_plugin_node_paths`.
- [ ] Run them; confirm they fail on assertions.
- [ ] Implement the spec's `run_setup_or_developer` block verbatim (comment, `local _plugin_node_rc=0`, call, rc-1 warning) after the `UBUNTU` block's closing `fi`, before the `install_cargo_tools` comment.
- [ ] Gates; commit via `caveman:caveman-commit`.

**Interfaces:** consumes Task 1's contract; `run_setup_or_developer`'s exit status is unchanged by the repair.

### Task 3: docs — backlog rows and plan index

```yaml-task
id: 3
description: Docs-only (no behaviour change, TDD not applicable) - remove the two shipped backlog rows, file the circular doctor remedy row, add the plan index row
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: make lint
    exit_code: 0
  - cmd: '! command grep -q "rewrites in place, not atomically" docs/superpowers/README.md'
    exit_code: 0
  - cmd: 'command grep -q "plans/2026-10-21-plugin-node-repair-setup.md" docs/superpowers/README.md'
    exit_code: 0
max_retries: 2
files_touched: [docs/superpowers/README.md]
depends_on: [2]
```

**Steps:**

- [ ] Delete the P2 bugs rows starting `| \`repair_plugin_node_paths\` rewrites in place, not atomically`and`| \`-t setup\` and \`-t developer\` never run the plugin node-path repair`.
- [ ] Add to the **P2 — bugs and security** table (append as its last row): `| doctor's stale-pin remedy cannot clear the two unrepairable causes | \`_doctor_check_plugin_node_paths\` prints \`run: setup_env.sh -t update --brew-only\` for every stale pin, which re-runs the same \`repair_plugin_node_paths\`; when the \`opt/\` link is missing (formula not installed) or the rewrite fails (permission, disk), the re-run fails identically. The repair's own lines now carry the cause-specific remedy (\`specs/2026-10-21-plugin-node-repair-setup-design.md\`); doctor should name it too. Raised by the ergonomics lens on that spec, 2026-10-21. |`
- [ ] Add the top All Plans row: `| 2026-10-21 | [plugin node repair setup](plans/2026-10-21-plugin-node-repair-setup.md) | [Plugin node-path repair: atomic rewrite, and run it from setup/developer](specs/2026-10-21-plugin-node-repair-setup-design.md) | In Progress |`
- [ ] Gates; commit via `caveman:caveman-commit`.

## Non-goal check

Reviewer verdicts (2026-10-21, fresh subagent, `nongoal-check.md`): 0 CONFLICT, 0 UNCLEAR.

- **N1 CLEAR** — "Task 3 names `_doctor_check_plugin_node_paths` only inside a Backlog row"; Tasks 1-2 edit only `repair_plugin_node_paths` and `run_setup_or_developer`. Resolution: none needed.
- **N2 CLEAR** — "Call repair_plugin_node_paths unconditionally in run_setup_or_developer". Resolution: none needed.
- **N3 CLEAR** — cleanup is explicit: "on any failure `[[ -n ${_tmp} ]] && rm -f "${_tmp}"`". Resolution: none needed.
