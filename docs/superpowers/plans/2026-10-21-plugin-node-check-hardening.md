# Plugin node-path check hardening Implementation Plan

spec: docs/superpowers/specs/2026-10-21-plugin-node-check-hardening-design.md

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** the plugin node-path check never PASSes over a config it did not scan, doctor names a remedy that clears each stale-pin cause, and a symlinked cache root is scanned.

**Architecture:** `_plugin_stale_node_paths` greps each config on its own under `LC_ALL=C` with stdout+stderr captured and tags `unreadable`/`nontext` files; the repair and doctor handle the tags; a new `_plugin_stable_node` helper feeds doctor's cause-specific remedy; two summary warnings are reworded.

**Tech Stack:** bash, bats, PATH mocks in `tests/mocks/`.

## Global Constraints

- No change to `repair_plugin_node_paths`'s rewrite sequence (`-w`, `mktemp`, `cp -p`, `printf`, `mv -f`) or rc contract 0/1/2 (N1).
- No change to `run_setup_or_developer` or `run_update`'s `plugin-node` section beyond the two warning strings (N2).
- A tagged config is never written (N3).
- No EXIT/RETURN trap and no temp file in `lib/helpers.sh` (`scripts/check-lib-exit-traps.sh` runs in `make lint`); no `grep -a`.
- Exact strings (copy verbatim):
  - repair unreadable: `cannot repair <file>: cannot be read — run: chmod u+r <file>`
  - repair nontext: `cannot repair <file>: contains non-text data — reinstall plugin <plugin>@<marketplace>`
  - doctor unreadable: `cannot be read — run: chmod u+r <file>`; doctor nontext: `contains non-text data — reinstall plugin <plugin>@<marketplace>`
  - doctor stale-pin remedies: `run: brew install <formula>` / `run: chmod u+w <file> && setup_env.sh -t update --brew-only` / `run: setup_env.sh -t update --brew-only`, each after `pins missing <node> — `
  - update warn: `plugin config(s) could not be checked or repaired — see detail`
  - setup warn: `plugin node paths: some configs could not be checked or repaired — see the 'cannot repair' lines above`
- In every `chmod` remedy `<file>` is the absolute path; doctor's label stays cache-relative. `<plugin>@<marketplace>` come from cache-relative path components 2 and 1.
- Verified apparatus: `grep`, `find`, `tr` are not mocked in `tests/mocks/`; the macOS CI leg resolves BSD `/usr/bin/grep`; `_make_plugin <mkt>/<plugin>/<ver> <node>` (plugin_node_paths.bats:46) builds both configs; root-skip pattern at plugin_node_paths.bats:151.
- Implementation traps (spec §1): an empty `_out` must not reach the dedupe (`sort -u <<< ""` yields one empty line); keep `_out=$(…)` and `_rc=$?` off any `local` line.

## Verification

- Session gate: the orchestrator runs `make test < /dev/null` once after Task 3 (Task 4 is docs only).
- V2 (orchestrator, before and after the merge): `./setup_env.sh -t doctor` on `claude`, `workstation` (`ssh workstation`) and the Studio prints `[PASS] no plugin pins a missing node binary`, recorded beside `find <cache>/ -type f \( -path '*/hooks/hooks.json' -o -path '*/.claude-plugin/plugin.json' \) | wc -l`.
- Test 3's discriminating run is the macOS CI leg; the RED step must be observed there or on the Studio.

---

### Task 1: tag unscanned configs; repair and doctor refuse them; descend a symlinked root

```yaml-task
id: 1
description: Per-file LC_ALL=C grep with stdout+stderr captured tags unreadable/nontext configs, repair and doctor report them with the exact remedies, and find descends a symlinked cache root
role: executor
model: sonnet
tdd: required
requirements: [R1, R2, R3, R4, R7]
acceptance:
  - cmd: bats --jobs 24 tests/setup_env/plugin_node_paths.bats
    exit_code: 0
  - cmd: make lint
    exit_code: 0
  - cmd: command grep -q 'LC_ALL=C grep -oE' lib/helpers.sh
    exit_code: 0
  - cmd: command grep -qF 'find "${_cache}/"' lib/helpers.sh
    exit_code: 0
max_retries: 3
files_touched: [lib/helpers.sh, tests/setup_env/plugin_node_paths.bats]
depends_on: []
```

**Files:** `lib/helpers.sh` (`_plugin_stale_node_paths`, `repair_plugin_node_paths`, `_doctor_check_plugin_node_paths`), `tests/setup_env/plugin_node_paths.bats`.

**Steps:**

- [ ] Write failing tests (spec Testing 1, 2, 3, 4, 6):
  1. `chmod 000` hooks.json (root-skip like :151): `run _plugin_stale_node_paths` output has `<file>\tunreadable`; `run repair_plugin_node_paths` status 1, output has `cannot be read — run: chmod u+r <abs file>`, file byte-identical after `chmod 644` (`cmp` against a saved copy); `run _doctor_check_plugin_node_paths` has `[FAIL]` and the doctor text, no `no plugin pins a missing node binary`; restore mode before assertions.
  2. `_make_plugin "mkt/plg/1.0.0" "${STALE_NODE}"`, then append a NUL to hooks.json (`printf '\0' >> …`): finder has `<file>\tnontext` and not the pin for that file; repair status 1 with `reinstall plugin plg@mkt`, file byte-identical; doctor FAILs it.
  3. hooks.json written as `{"c":"\377<STALE_NODE>"}` (byte between `"` and the pin), no NUL; first `locale -a | command grep -qxiE 'en_US\.utf-?8'` else `fail`; then `LC_ALL=en_US.UTF-8 run _plugin_stale_node_paths`: no tag, pin reported.
  4. One unreadable config plus a writable sibling plugin with a stale pin: the sibling is still repaired.
  5. Cache root as a symlink to a directory holding a stale pin (`_OVERRIDE_CLAUDE_PLUGIN_CACHE` = the link): finder reports it; doctor label has no `//`.
- [ ] Run `bats tests/setup_env/plugin_node_paths.bats < /dev/null`; confirm the new tests fail on assertions (test 3 passes on GNU by design; note it).
- [ ] Implement per spec Design §1 and §3: per-file `_out="$(LC_ALL=C grep -oE '<regex>' "${_file}" 2>&1)"`, `_rc=$?` on its own line; rc ≥ 2 → `unreadable`; any line not starting with `/` → `nontext`; else dedupe non-empty lines and `[[ -x ]]` as today. Repair and doctor branch on `_node` = `unreadable`/`nontext` before the formula derivation. `find "${_cache}/"`. Update the function header comments to state the tag contract.
- [ ] Gates; commit via `caveman:caveman-commit`.

**Interfaces:** finder line format `<abs file>\t<abs node>|unreadable|nontext`; rc unchanged (0, or 2 for no cache).

### Task 2: _plugin_stable_node and doctor's cause-specific remedy

```yaml-task
id: 2
description: Extract _plugin_stable_node from repair_plugin_node_paths and make doctor pick brew install, chmod u+w then update, or update as the stale-pin remedy
role: executor
model: sonnet
tdd: required
requirements: [R5, R6]
acceptance:
  - cmd: bats --jobs 24 tests/setup_env/plugin_node_paths.bats
    exit_code: 0
  - cmd: make lint
    exit_code: 0
  - cmd: command grep -q '^_plugin_stable_node()' lib/helpers.sh
    exit_code: 0
max_retries: 3
files_touched: [lib/helpers.sh, tests/setup_env/plugin_node_paths.bats]
depends_on: [1]
```

**Steps:**

- [ ] Write failing tests (spec Testing 5): `_plugin_stable_node /x/Cellar/node@22/22.1.0/bin/node` prints `node@22\t/x/opt/node@22/bin/node`; doctor with no `_make_brew_node` → `run: brew install node`; doctor with `_make_brew_node` and hooks.json `chmod 444` (root-skip) → `run: chmod u+w <abs file> && setup_env.sh -t update --brew-only`; doctor with link present and writable → `run: setup_env.sh -t update --brew-only` (the existing :306 test must still hold).
- [ ] Run; confirm they fail on assertions.
- [ ] Implement per spec Design §2; repair's existing output and every existing repair test unchanged.
- [ ] Gates; commit.

**Interfaces:** `_plugin_stable_node <node>` → stdout `<formula>\t<stable path>`, rc 0.

### Task 3: reword the two summary warnings

```yaml-task
id: 3
description: Reword the run_update plugin-node warning and the run_setup_or_developer rc-1 warning to say configs could not be checked or repaired
role: executor
model: sonnet
tdd: required
requirements: [R8]
acceptance:
  - cmd: bats --jobs 24 tests/setup_env/update_plugin_node.bats tests/setup_env/cargo_tools_update.bats
    exit_code: 0
  - cmd: make lint
    exit_code: 0
  - cmd: command grep -c 'could not be checked or repaired' lib/workflows.sh
    exit_code: 0
    stdout_match: '^2$'
max_retries: 3
files_touched: [lib/workflows.sh, tests/setup_env/update_plugin_node.bats, tests/setup_env/cargo_tools_update.bats]
depends_on: [2]
```

**Steps:**

- [ ] Change the assertions at `tests/setup_env/update_plugin_node.bats:81` and `tests/setup_env/cargo_tools_update.bats:242` to the new exact strings (Global Constraints); run; confirm both fail.
- [ ] Change only the two strings at `lib/workflows.sh` (`_update_warn "plugin-node" …` and the `log_warn` in `run_setup_or_developer`).
- [ ] Gates; commit.

### Task 4: docs — backlog rows and plan index

```yaml-task
id: 4
description: Docs-only (no behaviour change, TDD not applicable) - remove the three shipped plugin-node backlog rows and add the plan index row
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: make lint
    exit_code: 0
  - cmd: '! command grep -qE "reads an unreadable or binary config as clean|reads a symlinked cache root as clean|stale-pin remedy cannot clear" docs/superpowers/README.md'
    exit_code: 0
  - cmd: command grep -q "plans/2026-10-21-plugin-node-check-hardening.md" docs/superpowers/README.md
    exit_code: 0
max_retries: 2
files_touched: [docs/superpowers/README.md]
depends_on: [3]
```

**Steps:**

- [ ] Delete the P2 bugs rows starting `| plugin node-path check reads an unreadable or binary config as clean`, `| plugin node-path check reads a symlinked cache root as clean` and `| doctor's stale-pin remedy cannot clear the two unrepairable causes`.
- [ ] Add as the top All Plans row: `| 2026-10-21 | [plugin node check hardening](plans/2026-10-21-plugin-node-check-hardening.md) | [Plugin node-path check: no false PASS, cause-specific doctor remedy, symlinked cache root](specs/2026-10-21-plugin-node-check-hardening-design.md) | In Progress |`
- [ ] Gates; commit.

## Non-goal check

Reviewer verdicts (2026-10-21, fresh subagent, `nongoal-check.md`): 0 CONFLICT, 0 UNCLEAR.

- **N1 CLEAR** — the tag branch runs "before the formula derivation" and Task 2 only extracts that derivation; the rewrite sequence is untouched and a tagged file returns 1, inside 0/1/2. Resolution: none needed.
- **N2 CLEAR** — "Change only the two strings at `lib/workflows.sh`", gated by `grep -c` = 2. Resolution: none needed.
- **N3 CLEAR** — repair skips a tagged file first; tests 1 and 2 `cmp` it byte-identical. Resolution: none needed.
