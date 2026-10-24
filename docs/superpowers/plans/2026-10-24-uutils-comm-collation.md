# makefile_lint_scope.bats C collation and CI coreutils probe Implementation Plan

spec: docs/superpowers/specs/2026-10-24-uutils-comm-collation-design.md

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `tests/scripts/makefile_lint_scope.bats` collation-independent under uutils coreutils, guard it with a test that discriminates on uutils boxes, and make CI print which coreutils and locale it runs.

**Architecture:** `LC_ALL=C` on every `sort -u` and `comm -NN` invocation in the one bats file; one new bats test that forces `/usr/bin` (uutils) first and pins `LC_ALL=en_US.UTF-8`; one informational `Tool versions` step in `ci.yml`'s `test` job; backlog bookkeeping.

**Tech Stack:** bats 1.13, bash, GitHub Actions.

## Global Constraints

- No change to any file under `lib/` (N1) or `pyenv.d/` (N2).
- The `Tool versions` step does not fail the job on any version string (N3).
- No `setup()` or file-level code in `tests/scripts/makefile_lint_scope.bats` sets `LC_ALL`, `LC_COLLATE` or `LANG` (R2).
- Worktree: all work happens in `/home/bruce/git-repos/personal/dotfiles-wt-uutils` on branch `fix/uutils-comm-collation`.
- Task gates are scoped; the orchestrator runs `make test` once after Task 3, uncontended.

## Verification

- Session-level: on `claude`, `PATH="/usr/bin:${PATH}" bats tests/scripts/makefile_lint_scope.bats` shows 3 `not ok` on the base tree (predicted: tests 3, 17 and the new one) and 0 after Task 1 (V1); `make test` exits 0.
- Mutation (V2): removing `LC_ALL=C` from `_sorted_lines_from_space_list` turns the new test red, gated in Task 1.
- CI (V3): the PR's `test` job log shows the `Tool versions` output; record its lines on the `powershell` Backlog row (orchestrator step after CI).
- Edge: the new test skips cleanly on macOS (no uutils `--version`) and where `en_US.utf8` is not generated.

Baseline measured 2026-10-24 on `claude` against `origin/master` `9cb694f3`: `grep -oE '(LC_ALL=C )?(sort -u|comm -[0-9]+)' tests/scripts/makefile_lint_scope.bats` gives 14 occurrences, 0 of them prefixed.

---

### Task 1: C collation in makefile_lint_scope.bats plus uutils regression test

```yaml-task
id: 1
description: Prefix LC_ALL=C on every sort -u and comm call in makefile_lint_scope.bats and add a uutils/en_US regression test, test first
role: executor
model: sonnet
tdd: required
requirements: [R1, R2, R3, R4]
acceptance:
  - cmd: 'bash -c ''PATH="/usr/bin:${PATH}" bats tests/scripts/makefile_lint_scope.bats'''
    exit_code: 0
  - cmd: 'bash -c ''PATH="/usr/bin:${PATH}" bats --filter "under uutils sort and comm" tests/scripts/makefile_lint_scope.bats'''
    exit_code: 0
    stdout_match: '(?m)^ok 1 disjointness pipeline holds under uutils sort and comm in en_US\.UTF-8$'
  - cmd: 'bash -c ''f=tests/scripts/makefile_lint_scope.bats; test -z "$(grep -oE "(LC_ALL=C )?(sort -u|comm -[0-9]+)" "$f" | grep -v "^LC_ALL=C ")" && [ "$(grep -oE "LC_ALL=C (sort -u|comm -[0-9]+)" "$f" | wc -l)" -ge 14 ]'''
    exit_code: 0
  - cmd: 'bash -c ''f=tests/scripts/makefile_lint_scope.bats; ! grep -nE "^(export )?(LC_ALL|LC_COLLATE|LANG)=" "$f" && [ "$(awk "/^setup\\(\\) \\{/,/^}/" "$f" | grep -c "LC_ALL\|LC_COLLATE\|LANG=")" -eq 0 ]'''
    exit_code: 0
  - cmd: 'bash -c ''f=tests/scripts/makefile_lint_scope.bats; m=tests/scripts/.mutant_lint_scope.bats; trap "rm -f $m" EXIT; sed "s/| LC_ALL=C sort -u$/| sort -u/" "$f" > "$m"; cmp -s "$m" "$f" && exit 3; PATH="/usr/bin:${PATH}" bats --filter "under uutils sort and comm" "$m"'''
    exit_code: 1
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched:
  - tests/scripts/makefile_lint_scope.bats
depends_on: []
```

**IMPORTANT: All work must happen in `/home/bruce/git-repos/personal/dotfiles-wt-uutils/`. Do not cd anywhere else.**

**Files:** `tests/scripts/makefile_lint_scope.bats` only.

Context: on Ubuntu 26.04 `/usr/bin/sort` and `/usr/bin/comm` are uutils 0.10.0. Under `en_US.UTF-8` uutils `comm` rejects uutils `sort` output (`comm: file 1 is not in sorted order`, rc 1). Under `C`/`C.UTF-8` it does not. The session `PATH` puts linuxbrew GNU gnubin first, so plain `bats` is green; always run with `PATH="/usr/bin:${PATH}"` to see the defect. A failing uutils `comm` still prints the correct overlap, so the new test must assert `comm`'s exit status and stderr, not only the overlap.

- [ ] **Step 1: write the failing test.** Insert after the "oracle case 4" test (the second test containing `comm -12`), verbatim:

```bash
# uutils regression guard. Ubuntu 26.04's /usr/bin/sort and /usr/bin/comm are
# uutils, and uutils comm rejects uutils sort output collated under
# en_US.UTF-8 (C and C.UTF-8 collate bytewise and hide it). The tests above
# resolve sort and comm through the session PATH, which puts GNU gnubin first
# on claude and workstation, so they cannot see a dropped LC_ALL=C. This one
# forces /usr/bin first and pins en_US.UTF-8; the per-command LC_ALL=C
# prefixes override that pin. A failing uutils comm still prints the right
# overlap, so its exit status and stderr are asserted directly.
@test "disjointness pipeline holds under uutils sort and comm in en_US.UTF-8" {
  /usr/bin/sort --version 2>/dev/null | grep -q uutils || skip "/usr/bin/sort is not uutils"
  /usr/bin/comm --version 2>/dev/null | grep -q uutils || skip "/usr/bin/comm is not uutils"
  locale -a 2>/dev/null | grep -qiE '^en_US\.utf-?8$' || skip "en_US.UTF-8 locale not generated"

  run _make_print SHELL_FILES
  [ "${status}" -eq 0 ]
  local shell_list="${output}"
  run _make_print ZSH_FILES
  [ "${status}" -eq 0 ]
  local zsh_list="${output}"

  local dir="${BATS_TEST_TMPDIR}/uutils"
  mkdir -p "${dir}"
  local rc=0
  (
    export PATH="/usr/bin:${PATH}" LC_ALL=en_US.UTF-8
    _sorted_lines_from_space_list "${shell_list}" > "${dir}/shell"
    _sorted_lines_from_space_list "${zsh_list}" > "${dir}/zsh"
    LC_ALL=C comm -12 "${dir}/shell" "${dir}/zsh" > "${dir}/overlap" 2> "${dir}/comm.err"
  ) || rc=$?
  cat "${dir}/comm.err" >&2
  [ "${rc}" -eq 0 ]
  run -1 grep -q 'not in sorted order' "${dir}/comm.err"
  [ "$(cat "${dir}/overlap")" = "${_KNOWN_SHELL_ZSH_OVERLAP}" ]
  unexpected="$(LC_ALL=C comm -23 "${dir}/overlap" <(printf '%s\n' "${_KNOWN_SHELL_ZSH_OVERLAP}"))"
  [ -z "${unexpected}" ]
}
```

- [ ] **Step 2: run it, confirm RED for the right reason.** `PATH="/usr/bin:${PATH}" bats --filter "under uutils sort and comm" tests/scripts/makefile_lint_scope.bats` must print `not ok 1` with `not in sorted order` on stderr (not a skip, not a syntax error). Then the whole file under that `PATH`: 3 `not ok`.
- [ ] **Step 3: prefix `LC_ALL=C`** on every `sort -u` and every `comm -NN` in the file: the helper becomes `printf '%s\n' "${1}" | tr ' ' '\n' | LC_ALL=C sort -u`; `| sort -u` becomes `| LC_ALL=C sort -u`; `comm -12`/`comm -23` become `LC_ALL=C comm -12`/`LC_ALL=C comm -23`. Enumerate with `grep -noE '(LC_ALL=C )?(sort -u|comm -[0-9]+)' tests/scripts/makefile_lint_scope.bats`; touch nothing else, and do not write a bare `sort -u` or `comm -NN` into any comment.
- [ ] **Step 4: GREEN.** Run every acceptance gate above. The mutation gate must exit 1 (bats failure), not 3 (mutation did not apply).
- [ ] **Step 5: commit** via `caveman:caveman-commit`, exact path staged.

**Interfaces:** Produces the test name `disjointness pipeline holds under uutils sort and comm in en_US.UTF-8`, cited in Task 3's backlog text.

### Task 2: CI coreutils and locale probe

```yaml-task
id: 2
description: Add an informational Tool versions step to ci.yml's test job printing locale and both sort/comm resolutions
role: executor
model: sonnet
tdd: not-applicable
requirements: [R5]
acceptance:
  - cmd: 'python3 -c ''import yaml,sys; j=yaml.safe_load(open(".github/workflows/ci.yml"))["jobs"]["test"]["steps"]; n=[s.get("name") for s in j]; i=n.index("Tool versions"); assert i < n.index("Run tests"), n; r=j[i]["run"]; [sys.exit("missing "+t) for t in ("locale\n","locale -a","command -v sort comm || true","/usr/bin/sort --version | head -1","/usr/bin/comm --version | head -1") if t not in r]'''
    exit_code: 0
  - cmd: 'bash -c ''python3 -c "import yaml; print([s for s in yaml.safe_load(open(\".github/workflows/ci.yml\"))[\"jobs\"][\"test\"][\"steps\"] if s.get(\"name\")==\"Tool versions\"][0][\"run\"])" > "${BATS_TMPDIR:-/tmp}/tv.sh" && env PATH=/nonexistent:/bin LC_ALL=xx_XX.UTF-8 /bin/bash -e "${BATS_TMPDIR:-/tmp}/tv.sh"'''
    exit_code: 0
  - cmd: bats tests/scripts/ci_runner_pins.bats tests/scripts/ci_test_macos_log.bats tests/setup_env/shellcheck_pin.bats tests/setup_env/requirements_ci.bats tests/scripts/makefile_lint_scope.bats tests/scripts/auto_merge_gate.bats
    exit_code: 0
max_retries: 3
files_touched:
  - .github/workflows/ci.yml
depends_on: [1]
```

**IMPORTANT: All work must happen in `/home/bruce/git-repos/personal/dotfiles-wt-uutils/`. Do not cd anywhere else.**

TDD waiver: the step is diagnostic output with no behaviour a test could pin beyond the structural gates above.

- [ ] **Step 1:** in `.github/workflows/ci.yml`'s `test` job, insert between the `Install uv (pinned)` step and `- name: Run tests`, matching `test-macos`'s `Tool versions` step style:

```yaml
- name: Tool versions
  run: |
    locale
    locale -a
    command -v sort comm || true
    sort --version | head -1
    comm --version | head -1
    /usr/bin/sort --version | head -1
    /usr/bin/comm --version | head -1
```

- [ ] **Step 2:** run the gates. The second gate runs the body under `bash -e` with no `sort`/`comm` on `PATH` and a missing locale; it must exit 0 (N3). `/bin` on Ubuntu holds `/usr/bin` via usrmerge, so `PATH=/nonexistent:/bin` still reaches `locale` and `head`; if `command -v` there finds `sort`, that is fine, the gate's point is that nothing fails.
- [ ] **Step 3: commit** via `caveman:caveman-commit`, exact path staged.

### Task 3: backlog bookkeeping

```yaml-task
id: 3
description: Close the two uutils backlog rows, add the pyenv-hook retirement row, link the plan in the index (docs-only, no behaviour change)
role: executor
model: sonnet
tdd: not-applicable
requirements: [R6]
acceptance:
  - cmd: 'bash -c ''! grep -qF "| \`makefile_lint_scope.bats\` disjointness tests fail under uutils" docs/superpowers/README.md && ! grep -qF "| \`sort -u\` over names is lossy on Ubuntu 26.04" docs/superpowers/README.md'''
    exit_code: 0
  - cmd: 'bash -c ''awk "/^### P3 — tech-debt/,/^### P3 — docs/" docs/superpowers/README.md | grep -qF "dotfiles-register-all-executables.bash"'''
    exit_code: 0
  - cmd: 'bash -c ''grep -F "2026-10-24-uutils-comm-collation-design.md" docs/superpowers/README.md | grep -qF "plans/2026-10-24-uutils-comm-collation.md"'''
    exit_code: 0
  - cmd: make lint
    exit_code: 0
max_retries: 3
files_touched:
  - docs/superpowers/README.md
depends_on: [1, 2]
```

**IMPORTANT: All work must happen in `/home/bruce/git-repos/personal/dotfiles-wt-uutils/`. Do not cd anywhere else.**

Edit with a short Python line-based script, not the Edit tool (Edit reflows whole tables in this file).

- [ ] **Step 1:** delete the whole row starting ``| `makefile_lint_scope.bats` disjointness tests fail under uutils`` (P2 — test gaps) and the whole row starting ``| `sort -u` over names is lossy on Ubuntu 26.04`` (P2 — bugs and security).
- [ ] **Step 2:** append as the last row of the `### P3 — tech-debt` table (the line before the blank line preceding `### P3 — docs`; NOT the `Closed without shipping` table at the end):
      ``| `pyenv.d/rehash/dotfiles-register-all-executables.bash` may be retirable under uutils 0.10.0 | The hook exists for uutils 0.8.0's `sort -u` dropping one of `pytest`/`py.test`. Measured 2026-10-24: uutils 0.10.0 on `claude` and `workstation` keeps both (`printf 'pytest\npy.test\n' \| /usr/bin/sort -u \| wc -l` gives 2, `LC_COLLATE=en_US.UTF-8`). Re-measure `pyenv versions --executables` against the unhooked list under 0.10.0 and retire the hook if they match. See `docs/superpowers/specs/2026-10-24-uutils-comm-collation-design.md`. |``
- [ ] **Step 3:** in the All Plans index row whose Spec cell links `specs/2026-10-24-uutils-comm-collation-design.md`, replace the Plan cell `—` with `[uutils comm collation](plans/2026-10-24-uutils-comm-collation.md)` and the Status cell with `In Progress`.
- [ ] **Step 4:** gates, then commit via `caveman:caveman-commit`, exact path staged.

## Orchestrator steps after Task 3

1. `make test </dev/null` once in the worktree, uncontended; paste the summary line. Re-verify `git branch --show-current` before and after.
2. Phase 3 (`finishing-a-development-branch`); PR body carries the V1 before/after counts and the V2 mutation result.
3. After CI's `test` job runs: copy its `Tool versions` output (`LANG`/`LC_ALL` lines, `command -v` paths, both `sort --version` lines) onto the `powershell` Backlog row as a direct-to-master docs commit (V3).
