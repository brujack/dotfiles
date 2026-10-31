# Shared Push-Content Gate — PR2 (dotfiles) Implementation Plan

> **Status: DONE** — merged via [dotfiles#412](https://github.com/brujack/dotfiles/pull/412) (2026-10-31, `056494d8`).

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Spec:** ai-config `docs/superpowers/specs/2026-10-30-shared-push-content-gate-design.md` (cross-repo; no `spec:` line). R13 (dotfiles) and R14, with R14 as amended 2026-10-31, are copied verbatim under Global Constraints. The plan carries no `spec:` line because the spec tooling reads a spec only from the pushing repo. So `spec-alignment-review` records SKIP for this PR, with that reason (operator decision, 2026-10-31).

**Goal:** dotfiles' `scripts/pre-push` loads the shared push-content gate from ai-config's GitHub master for every master push, instead of refusing master pushes with its own `_path_is_inert` guard.

**Architecture:** The canonical wiring block from ai-config `docs/templates/pre-push-wiring` goes at the top of `scripts/pre-push`, which then starts `#!/usr/bin/env -S bash -p`. The ref loop reads `${_pcg_refs}` rather than stdin. The master-refusal half of the loop and `_print_recovery` are deleted. `_path_is_inert` stays as the `make test` trigger. The tests reach the gate through a `gh` stub (the load-failure path, on the real file) and through a hook copy whose `_pcg_fetch` serves a stub library (the load-success path). No test touches the network.

**Tech Stack:** bash ≥ 4, bats, git, `gh auth token`, `/usr/bin/curl`.

## Global Constraints

- R13 (dotfiles): "has the wiring block at the top of its tracked pre-push script, and every later stdin read reads `${_pcg_refs}` behind a non-empty check, and its first line is `#!/usr/bin/env -S bash -p`."
- R14 as amended: "dotfiles' `scripts/pre-push` no longer refuses master pushes by `_path_is_inert`, and keeps its `make test` trigger, CLAUDE.md budget check and unresolved-range refusal." (`_print_recovery` is dropped from the keep list: its only caller is the refusal R14 removes.)
- The wiring block (between `# >>> push-content-gate wiring` and `# <<< push-content-gate wiring`) is byte-identical to ai-config `origin/master:docs/templates/pre-push-wiring`.
- Do not edit `.github/workflows/ci.yml`, `Makefile`, `scripts/ci-suite-report.sh` or `tests/scripts/docs_inert_premise.bats`; the dotfiles session's `feat/test-macos-shard` branch owns them.
- No test makes a network call. Every test that runs the hook has a `gh` stub ahead of the real `gh` on `PATH`.
- Bash coverage stays at or above CI's 91% gate. Baseline at `origin/master` `25c85b21`, measured 2026-10-31 under `make bash-coverage` in an archive copy: total 91% (6325/6907), `pre-push` 93% (164/176). The same figures were measured with only the shebang flipped and the detector fixed.

## Verification Planning

Done when, after merge, a throwaway clone of dotfiles with `make install-hooks`, pushing to a local bare remote seeded as a copy of the clone, shows three results. A code file pushed to master is refused with the shared gate's `[file rule R2]` message. A docs-only commit to master is permitted. A code file pushed to a feature branch is permitted after `make test`. This is the same harness as ai-config's V1 run (`ai-config#344` body), with the clone directory named `dotfiles`. Edge cases: a push carrying two ref lines drains both; a feature-only push makes no `gh` call; `gh auth token` failing refuses a master push before the suite runs.

---

### Task 1: Shell-file detector accepts `env -S bash`

```yaml-task
id: 1
description: list-shell-files.sh lists a file whose first line is `#!/usr/bin/env -S bash -p`
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: bats tests/scripts/list_shell_files.bats
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched:
  - scripts/list-shell-files.sh
  - tests/scripts/list_shell_files.bats
depends_on: []
```

`scripts/list-shell-files.sh` is the `SHELL_FILES` source for `make lint` and `lint-macos`. Its `case` (line 27) has no pattern for `env -S bash`, so Task 2's shebang would silently drop `scripts/pre-push` from lint. Measured in an archive copy: flipping only the shebang turned `makefile_lint_scope.bats` tests 31 and 269 red.

- [ ] In `tests/scripts/list_shell_files.bats`, add `@test "includes a file with #!/usr/bin/env -S bash -p"` and `@test "includes a file with #!/usr/bin/env -S bash"`, copying the shape of `includes a file with #!/usr/bin/env bash` (line 41). Also add `@test "excludes a file with #!/usr/bin/env -S zsh"`. Run `bats tests/scripts/list_shell_files.bats` and see the two include tests fail with exit 1.
- [ ] In the `case`, add `'#!'*env\ -S\ bash|'#!'*env\ -S\ bash\ *` to the bash alternatives. Rerun: all pass.
- [ ] `make lint`, commit `fix(lint): detect env -S bash shebangs`.

### Task 2: Wire `scripts/pre-push` to the shared gate

```yaml-task
id: 2
description: scripts/pre-push gets the wiring block and bash -p shebang, reads ${_pcg_refs}, and drops its master refusal and _print_recovery
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: bats tests/scripts/pre_push.bats
    exit_code: 0
  - cmd: make test
    exit_code: 0
  - cmd: 'diff <(sed -n "/^# >>> push-content-gate wiring$/,/^# <<< push-content-gate wiring$/p" scripts/pre-push) <(git -C ../../../ai-config show origin/master:docs/templates/pre-push-wiring | sed -n "/^# >>> push-content-gate wiring$/,/^# <<< push-content-gate wiring$/p")'
    exit_code: 0
  - cmd: 'make bash-coverage 2>&1'
    exit_code: 0
    stdout_match: 'Overall bash coverage: (9[1-9]|100)%'
max_retries: 3
files_touched:
  - scripts/pre-push
  - tests/scripts/pre_push.bats
depends_on: [1]
```

**Hook (`scripts/pre-push`):**

- [ ] Line 1 becomes `#!/usr/bin/env -S bash -p`. Paste the wiring block byte for byte directly below the header comment and `set -e`, and above `_path_is_inert`. Copy it with `git -C ../../../ai-config show origin/master:docs/templates/pre-push-wiring`, taking the lines from `# >>> push-content-gate wiring` to `# <<< push-content-gate wiring`, never the template's leading comment.
- [ ] Change the loop's `done` to `done <<< "${_pcg_refs}"`, and guard the loop with `if [[ -n "${_pcg_refs}" ]]; then … fi` (R13: non-empty check).
- [ ] Delete `refuse_paths`, `refuse_local_ref`, the `elif [[ -n "${live_paths}" ]]` arm that sets them, the `if [[ -n "${refuse_paths}" ]]` block after the loop, and `_print_recovery` with its comment. Keep the master test and its `diff_rc` arm, so an unresolvable range on a master push still lands in `unresolved_refs`.

**Tests (`tests/scripts/pre_push.bats`):**

- [ ] In `setup()`, write `${MAKE_MOCK_DIR}/gh`: it appends `$*` to `${BATS_TEST_TMPDIR}/gh.calls` and exits `${MOCK_GH_EXIT:-1}`. `MAKE_MOCK_DIR` is already first on `_run_pre_push`'s `PATH` (line 107).
- [ ] Add `_run_pre_push_wired <stdin> <verdict>`. It writes `${BATS_TEST_TMPDIR}/pre-push.copy`: `scripts/pre-push` with the body between `# >>> _pcg_fetch` and `# <<< _pcg_fetch` replaced by a `_pcg_fetch` that prints a stub library. The stub library defines `push_content_gate_refs`, which writes its two arguments to `${BATS_TEST_TMPDIR}/pcg.args` and returns 0 for `permit` or prints `stub gate refused` and returns 1 for `refuse`. The helper fails the test if the copy still contains `api.github.com`, then runs the copy like `_run_pre_push` does.
- [ ] Delete every test whose subject is the master refusal or `_print_recovery`: those at lines 597 and 607; the `master guard refuses/allows …` tests at 724–1062; the recipe tests at 861–905, 971 and 1427; `_assert_refused` and `_master_push_of`. That policy is now ai-config's, tested there.
- [ ] Retarget to `refs/heads/feat/x` the tests whose subject is not ref-specific: lines 334, 626 (rename it `markdown-only push skips the suite`), 926, 936, 947 and 955, plus any other `refs/heads/master` line that `bats` turns red for that reason alone. Keep one unresolved-range test on master: a master push with an unknown `remote_sha` and `MOCK_GH_EXIT=1`.
- [ ] New tests:
  - `wiring: a feature-only push makes no gh call`: `gh.calls` is absent.
  - `wiring: a master push whose gate cannot load is refused before the suite`: status 1, output contains `cannot load the push-content gate`, `MOCK_CALLS_FILE` absent.
  - `wiring: a loaded gate's refusal stops the push before the suite`: wired, `refuse`; status 1, `stub gate refused` in output, no make.
  - `wiring: a loaded gate's permit reaches the suite trigger`: wired, `permit`, `.sh` change; make ran; `pcg.args` holds the ref text.
  - `wiring: two ref lines are both drained from _pcg_refs`: feature-only, two refs, one with a `.sh`; make ran.
  - `wiring: the hook starts with bash -p`: line 1 equals `#!/usr/bin/env -S bash -p`.
- [ ] Before committing: deleting the `done <<< "${_pcg_refs}"` redirect, or swapping the wiring's `|| exit 1` for `|| true`, must each turn at least one new test red. Report both runs.
- [ ] `make test`, `make bash-coverage`, commit `feat(pre-push): load shared push-content gate`.

### Task 3: Docs for the shared gate

```yaml-task
id: 3
description: CLAUDE.md, ADR-0038 status, ADR index and plan index describe the shared gate (docs-only, no behavior change)
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: make lint
    exit_code: 0
  - cmd: make check-claude-md-budget
    exit_code: 0
  - cmd: 'grep -q "Superseded by ai-config ADR-0091" docs/adr/0038-master-guard-default-deny.md'
    exit_code: 0
  - cmd: '! grep -nE "decides both the suite trigger and the master guard|_print_recovery" CLAUDE.md'
    exit_code: 0
max_retries: 2
files_touched:
  - CLAUDE.md
  - docs/adr/0038-master-guard-default-deny.md
  - docs/adr/README.md
  - docs/superpowers/README.md
depends_on: [2]
```

- [ ] `CLAUDE.md` line 209: `_path_is_inert` decides the suite trigger only. Master pushes are judged by ai-config's shared push-content gate, loaded from GitHub master by the wiring block (ai-config ADR-0091), and refused when it cannot load. Line 211: keep the unresolved-range refusal. Line 217: drop the master-refusal clause. Line 220: replace the master-guard emergency wording with the shared gate's (a fast PR, or the operator's own push). Keep the net size no larger: `make check-claude-md-budget` (a `make test` prerequisite) must pass.
- [ ] ADR-0038: set its status to `Superseded by ai-config ADR-0091 (2026-10-31)` with one sentence on what moved. Update its `docs/adr/README.md` row to match.
- [ ] `docs/superpowers/README.md`: add an All Plans row for this plan, marked In Progress.
- [ ] `make lint`, commit `docs: shared push-content gate replaces master guard`.

The orchestrator runs `make test` once after Task 3. Task 3's gates are `make lint` and `make check-claude-md-budget`, the only parts of `make test` its prose can move.

## Non-goal check

Run 2026-10-31 against the six effective non-goals of the ai-config spec (one reviewer-role subagent, `~/.claude/skills/writing-plans/nongoal-check.md`): N1 through N6 all CLEAR, 0 CONFLICT, 0 UNCLEAR, no plan change. The reviewer's notes: Task 2's surviving `_path_is_inert` trigger and unresolved-range refusal are not a content check (N2); feature pushes make no `gh` call (N3); the `git -C ../../../ai-config show` copy runs at authoring time only, and the stub `_pcg_fetch` exists only in a test copy (N5).
