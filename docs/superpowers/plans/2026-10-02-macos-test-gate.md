# macOS Test Gate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run the bats suite on macOS on every PR and block merge when it is red.

**Architecture:** A new `test-macos` job in `ci.yml` runs `make test` on `macos-latest` and is in `auto-merge`'s `needs:`. A small script reports failures and checks that the suite ran. The test helper stops tests inheriting the platform from the parent shell, and the one real macOS failure is fixed.

**Tech Stack:** GitHub Actions, bash, bats, GNU parallel, Homebrew.

**Spec:** `docs/superpowers/specs/2026-10-02-macos-test-gate-design.md`

## Global Constraints

- All work happens in `/home/bruce/git-repos/personal/dotfiles/.worktrees/macos-test-gate/` on branch `feat/macos-test-gate`.
- `make test` on `claude` takes about 71s (ADR-0035). Run it in the foreground with `timeout: 600000` and stdin from `/dev/null`: `make test > /tmp/t.log 2>&1 < /dev/null; echo "rc=$?"`. Never pipe it into `tail`.
- Shell standards: `~/.claude/standards/shell.md`. No `set -e` outside hooks, `[[ ]]`, `${VAR}`, `printf`, sourcing guard on testable scripts.
- Pinned versions: shellcheck `0.11.0`, uv `0.12.5`. The macOS job uses the same versions as the `test` job.
- The macOS job uses the system `make`. It does not install `make` or `gmake`.
- A commit message comes from the `caveman:caveman-commit` skill and ends with the session's attribution trailers.

## Verification (whole change)

| check                      | command                                                           | expected                                                                           |
| -------------------------- | ----------------------------------------------------------------- | ---------------------------------------------------------------------------------- |
| Linux suite                | `make test` on `claude`                                           | rc 0, `ok` count equals `^@test` count                                             |
| Hostile inheritance, Linux | `MACOS=1 make test` on `claude`                                   | rc 0                                                                               |
| macOS gate can fail        | first CI run after Task 1                                         | `test-macos` red, `not ok` set is tests 1266, 1667, 1668, 1698, 1700, 1702 by name |
| Determinism                | four re-runs of that job                                          | same `not ok` set                                                                  |
| macOS gate passes          | CI run after Task 3                                               | `test-macos` green                                                                 |
| Studio, bare environment   | the reproduction command in Task 4, full suite, on the branch tip | rc 0                                                                               |
| Studio, hostile            | same with `LINUX=1 UBUNTU=1` exported                             | rc 0                                                                               |
| Diagnosis from Linux       | `gh run view <id> --log-failed` on the red run                    | failing test names and diagnostics present                                         |

**Orchestrator steps between tasks (not delegated):**

- After Task 1: run `pr-review`, push, open the PR, and read the first `test-macos` run. A `not ok` set other than the six is reported to the operator before Task 2 starts. Re-run the job four times with `gh run rerun <id> --job <job-id>` and compare the sets.
- The PR cannot merge while `test-macos` is red, because the job is in `needs:` from Task 1.
- After Task 3: sync the branch to a throwaway clone on the Studio and run both Studio checks above.

**Deviation from the spec, stated:** the spec verifies the executed-count check with two scratch commits on CI. This plan puts the check in a script with bats tests for both cases instead, so the controls are permanent and run on every PR.

**1266 diagnosis (measured at plan time, reported to the operator as the spec requires):** `gpg --dearmor` on the first 400 bytes of `keys/microsoft.asc` exits 2 under GnuPG 2.4.8 (`claude`) and exits 0 under GnuPG 2.5.24 (Studio), writing 248 bytes in both. `_install_ubuntu_edge_source` trusts gpg's exit status, so under GnuPG 2.5 a truncated key yields a keyring it accepts. That is a production weakness that depends on the gpg version, not on macOS. Task 3 changes production behaviour: the built keyring must contain the pinned fingerprint `MS_GPG_FPR`.

---

### Task 1: `test-macos` job and suite report script

```yaml-task
id: 1
description: Add scripts/ci-suite-report.sh with tests, and a test-macos job in ci.yml that is in auto-merge needs
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: bats tests/scripts/ci_suite_report.bats
    exit_code: 0
  - cmd: 'python3 -c "import yaml,sys; d=yaml.safe_load(open(\".github/workflows/ci.yml\")); j=d[\"jobs\"]; sys.exit(0 if j[\"test-macos\"][\"runs-on\"]==\"macos-latest\" and \"test-macos\" in j[\"auto-merge\"][\"needs\"] else 1)"'
    exit_code: 0
  - cmd: 'make test > /tmp/t1.log 2>&1 < /dev/null'
    exit_code: 0
max_retries: 3
files_touched:
  - scripts/ci-suite-report.sh
  - tests/scripts/ci_suite_report.bats
  - .github/workflows/ci.yml
  - tests/setup_env/shellcheck_pin.bats
  - tests/setup_env/requirements_ci.bats
depends_on: []
```

**Interfaces:**

- Produces: `scripts/ci-suite-report.sh <log-file> <tests-dir>`. Prints every `not ok` line and the `#` diagnostic lines that follow it. Then prints `executed=<n> declared=<m>`. Exit 0 only when `n == m` and `m > 0`; otherwise exit 1 with a message naming both numbers. Exit 2 when the log file is missing or unreadable, with its own message.
  - executed: lines in the log matching `^(ok|not ok) `.
  - declared: lines matching `^@test` in `*.bats` files under `<tests-dir>`, found with `find`, not `git`.

**Steps:**

- [ ] Write `tests/scripts/ci_suite_report.bats`, one test at a time, each red before its code. Build fixtures under `BATS_TEST_TMPDIR`: a tests dir with two `.bats` files holding three `@test` lines, plus a non-bats file containing the string `test@test.com @test` to prove anchoring.
  - equal counts, all `ok`: exit 0, output has `executed=3 declared=3`.
  - log with one `not ok 2 name` followed by `# (in test file x, line 3)` and `#   detail`: both diagnostic lines are printed. Counts equal, so exit 0: this script reports, `make`'s exit status is what fails the job.
  - log with zero `ok` lines: exit 1, output names `executed=0 declared=3`.
  - empty tests dir: exit 1, output names `declared=0`.
  - log holding `bash -n OK (111 files)` and a bare `OK` line: neither is counted.
  - a skipped test line `ok 3 name # skip reason`: counted.
  - missing log file: exit 2, message names the file.
- [ ] Write `scripts/ci-suite-report.sh` to pass them. `#!/usr/bin/env bash`, functions plus the sourcing guard on the last line.
- [ ] Add the job to `.github/workflows/ci.yml` after `lint-macos`:

```yaml
test-macos:
  runs-on: macos-latest
  timeout-minutes: 30 # provisional; re-size to ~3x p90 after five green runs
  steps:
    - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7

    - name: Install bash, bats and GNU parallel
      run: brew install bash bats-core parallel

    - name: Install shellcheck (pinned)
      env:
        SC_VER: "0.11.0"
        SC_SHA256: "56affdd8de5527894dca6dc3d7e0a99a873b0f004d7aabc30ae407d3f48b0a79"
      run: |
        curl -fsSL -o /tmp/sc.tar.xz \
          "https://github.com/koalaman/shellcheck/releases/download/v${SC_VER}/shellcheck-v${SC_VER}.darwin.aarch64.tar.xz"
        echo "${SC_SHA256}  /tmp/sc.tar.xz" | shasum -a 256 -c -
        tar -xJf /tmp/sc.tar.xz -C /tmp
        sudo install -m755 "/tmp/shellcheck-v${SC_VER}/shellcheck" /usr/local/bin/shellcheck
        shellcheck --version | grep -q "version: ${SC_VER}"

    - name: Install uv (pinned)
      env:
        UV_VER: "0.12.5"
        UV_SHA256: "5bb0e5fe008a773c3dbcb97ff79cd89e1241464fe9d2f986d52ad8f1b037bd62"
      run: |
        curl -fsSL -o /tmp/uv.tar.gz \
          "https://github.com/astral-sh/uv/releases/download/${UV_VER}/uv-aarch64-apple-darwin.tar.gz"
        echo "${UV_SHA256}  /tmp/uv.tar.gz" | shasum -a 256 -c -
        tar -xzf /tmp/uv.tar.gz -C /tmp
        sudo install -m755 /tmp/uv-aarch64-apple-darwin/uv /usr/local/bin/uv
        uv --version | grep -q "uv ${UV_VER}"

    - name: Tool versions
      run: |
        bash --version | head -1
        bats --version
        make --version | head -1
        parallel --version | head -1

    - name: Run tests
      run: |
        make test > /tmp/make-test.log 2>&1 < /dev/null
        rc=$?
        bash scripts/ci-suite-report.sh /tmp/make-test.log tests
        report_rc=$?
        if [ "${rc}" -ne 0 ]; then
          printf 'make test exited %d\n' "${rc}" >&2
          tail -40 /tmp/make-test.log
          exit 1
        fi
        exit "${report_rc}"
```

GitHub runs `run:` steps under `bash -e`. The `make test` line must not abort the step before the report runs: start the block with `set +e`.

- [ ] Add `test-macos` to `auto-merge`'s `needs:` list.
- [ ] `tests/setup_env/shellcheck_pin.bats` and `tests/setup_env/requirements_ci.bats` parse `ci.yml` per job and may assert Linux asset names or `sha256sum` for every job that runs `make test`. Run them. Where one fails because of the new job, extend it to accept the darwin asset name and `shasum -a 256 -c` for a `macos-latest` job. Do not weaken what it asserts for the Linux jobs.
- [ ] Both sha256 values above were computed at plan time from the release assets; the uv value matches the upstream `.sha256` file. Re-download and re-check both before committing.
- [ ] Run the three acceptance commands. Commit.

---

### Task 2: Tests stop inheriting the platform

```yaml-task
id: 2
description: Unset inherited platform variables in tests/helpers/common.bash and make five real-tool tests set the platform from uname
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: 'env MACOS=1 bats -f "_doctor_check_cred_dirs real|_doctor_check_github_mcp" tests/setup_env/unit.bats'
    exit_code: 0
  - cmd: 'env -u MACOS -u LINUX -u UBUNTU bats -f "_doctor_check_cred_dirs real|_doctor_check_github_mcp" tests/setup_env/unit.bats'
    exit_code: 0
  - cmd: 'MACOS=1 make test > /tmp/t2-hostile.log 2>&1 < /dev/null'
    exit_code: 0
  - cmd: 'make test > /tmp/t2.log 2>&1 < /dev/null'
    exit_code: 0
max_retries: 3
files_touched:
  - tests/helpers/common.bash
  - tests/setup_env/unit.bats
depends_on: [1]
```

**Base-tree state of the gates (measured):** the first command exits 1 on the base tree with exactly five `not ok` (round-2 review, on `claude`). The second exits 0 on `claude` today and is a regression guard.

**Steps:**

- [ ] Confirm red: run the first acceptance command; expect five `not ok`.
- [ ] In `tests/setup_env/unit.bats`, the two `_doctor_check_cred_dirs real:` tests, and the three `_doctor_check_github_mcp` tests named `warns when GITHUB_PAT_EXPIRY within 30 days`, `passes when all checks pass` and `fails when GITHUB_PAT has expired`: set the platform at the top of each test body from the machine, because each runs a real `stat` or `date`:

```bash
  if [[ "$(uname -s)" == "Darwin" ]]; then export MACOS=1; else unset MACOS; fi
```

- [ ] Run the first command again: expect rc 0 from those edits alone.
- [ ] In `tests/helpers/common.bash`, at file top level after `REPO_ROOT`, unset the inherited platform so every loader starts clean:

```bash
# Tests must not inherit the platform from the parent shell: an interactive
# mac shell exports MACOS=1, an ssh command or a CI runner exports nothing,
# and the same test then takes a different branch (dotfiles spec
# 2026-10-02-macos-test-gate). A test that needs a platform sets it.
unset MACOS LINUX UBUNTU NOBLE RESOLUTE PROFILE
for _inherited_cap in "${!HAS_@}"; do
  unset "${_inherited_cap}"
done
unset _inherited_cap
```

- [ ] Run `MACOS=1 make test`. A test that goes red here was relying on an inherited variable. Fix it in the test by setting what it needs. If the file is not `tests/setup_env/unit.bats`, stop and report `blocker` naming the file: it is outside `files_touched`.
- [ ] Mutation check: remove the `unset` block, run `MACOS=1 make test`, and record whether anything goes red. If nothing does, say so in the report: the block is then defence with no failing case on Linux, and the Studio hostile run in Verification is its control.
- [ ] Run all four acceptance commands. Commit.

---

### Task 3: Edge keyring must contain the pinned fingerprint

```yaml-task
id: 3
description: Make _install_ubuntu_edge_source verify the built keyring holds MS_GPG_FPR, so a gpg that exits 0 on a truncated key still fails closed
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: 'bats -f "_install_ubuntu_edge_source" tests/setup_env/linux_ubuntu.bats'
    exit_code: 0
  - cmd: 'make test > /tmp/t3.log 2>&1 < /dev/null'
    exit_code: 0
max_retries: 3
files_touched:
  - lib/linux_ubuntu.sh
  - tests/setup_env/linux_ubuntu.bats
depends_on: [2]
```

**Context:** `lib/linux_ubuntu.sh` around line 792 runs `"${_MS_GPG_BIN:-gpg}" --dearmor < key | sudo tee keyring` and accepts the keyring when gpg exited 0 and the file is non-empty. GnuPG 2.5.24 exits 0 on a truncated key and still writes 248 bytes; GnuPG 2.4.8 exits 2. The existing test `fails closed when gpg fails but still emits bytes (truncated key)` is green on `claude` and red on a mac for that reason, so it cannot be this fix's regression guard on Linux.

**Steps:**

- [ ] Read `_ms_verify_deb` in the same file to see how `MS_GPG_FPR` is checked there, and reuse that method.
- [ ] Add a test that is red on Linux: point `_MS_GPG_BIN` at a stub script in `BATS_TEST_TMPDIR` that, for `--dearmor`, writes bytes to stdout and exits 0, and for any other invocation behaves as a gpg that finds no key matching the fingerprint. Assert: status 0, output contains `edge: could not build`, no `.list` file, no keyring file. Run it: expect red.
- [ ] In `_install_ubuntu_edge_source`, after the dearmor, require that the built keyring lists a key whose fingerprint equals `MS_GPG_FPR` (for example `gpg --show-keys --with-colons <keyring>` and an exact match on the `fpr` record). Any failure takes the existing fail-closed branch. Keep the existing warning text's leading `edge: could not build ${_edge_keyring}` so current assertions hold; extend the parenthesis to name the fingerprint check.
- [ ] Add a positive test: the real `keys/microsoft.asc` with the real gpg still produces the `.list` and the keyring. One of the existing tests may already cover this; if so, name it in the report instead of adding one.
- [ ] Mutation check: remove the fingerprint check, confirm the new test goes red and the positive test stays green.
- [ ] Run both acceptance commands. Commit.

---

### Task 4: Documentation and ADR

```yaml-task
id: 4
description: Document the test-macos job in CLAUDE.md, add ADR-0037 with its index row, and update the plan index (docs-only, no behavior change)
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: 'grep -q "test-macos" CLAUDE.md'
    exit_code: 0
  - cmd: 'test -f docs/adr/0037-macos-suite-gates-merge.md'
    exit_code: 0
  - cmd: 'grep -q "0037" docs/adr/README.md'
    exit_code: 0
  - cmd: 'grep -c "All jobs run on .ubuntu-latest." CLAUDE.md | grep -qx 0'
    exit_code: 0
  - cmd: 'make test > /tmp/t4.log 2>&1 < /dev/null'
    exit_code: 0
max_retries: 3
files_touched:
  - CLAUDE.md
  - docs/adr/0037-macos-suite-gates-merge.md
  - docs/adr/README.md
  - docs/superpowers/README.md
depends_on: [3]
```

`make test` is declared because tests in this repo read `CLAUDE.md` (`tests/test_phrase_check.py`), so this task can move the suite.

**Steps:**

- [ ] `CLAUDE.md`, section `### CI / GitHub Actions`:
  - add a `test-macos` bullet after `lint-macos`: runs on `macos-latest`, blocks auto-merge, installs bash, bats-core and GNU parallel from Homebrew (unpinned) and pinned shellcheck and uv, runs `make test` under the system GNU Make 3.81, then `scripts/ci-suite-report.sh` prints every `not ok` block and fails unless the executed test count equals the declared count. State that the `makefile_lint_scope.bats` arms needing make 4 or later skip there and run on `ubuntu-latest`, and that the GNU `ar` verifier tests skip on macOS.
  - update the `auto-merge` bullet's `needs:` list.
  - add `test-macos` 30 to the timeout bullet, marked provisional.
  - replace the line "All jobs run on `ubuntu-latest` with ..." with one that names the two macOS jobs as the exceptions.
  - add the reproduction command:

```bash
ssh studio 'cd /tmp/<clone> && env -i HOME="$(mktemp -d)" \
  PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin \
  bats tests/<file>.bats' < /dev/null
```

- in `### Testing Rules`, first bullet: add one sentence saying `tests/helpers/common.bash` now unsets inherited platform variables when sourced.
- Layout tree: add `ci-suite-report.sh` to the `scripts/` line and `test-macos` to the workflows line.
- Write no measured figures into `CLAUDE.md`.
- [ ] `docs/adr/0037-macos-suite-gates-merge.md`, Nygard format, Status Accepted, written as the other ADRs in `docs/adr/` write it. Context: the session moved to Linux on 2026-09-19 and nothing ran the suite on macOS; six tests were red on the Studio. Decision: `test-macos` gates merge; system make; unpinned Homebrew runners with a version banner; job in `needs:` from its first commit because the merge step has no `--auto`. Consequences: PR wall clock, skips on macOS, real-run defects still uncovered (backlog row). Related: ADR-0008 (its queue-time reason no longer holds: `lint-macos` queued a median of 8s, maximum 12s, over 40 runs on 2026-10-02), ADR-0035, the spec.
- [ ] `docs/adr/README.md`: add the 0037 row.
- [ ] `docs/superpowers/README.md`: on the `macos-test-gate` row, set the Plan cell to `[macos-test-gate](plans/2026-10-02-macos-test-gate.md)` and the status to `In Progress`.
- [ ] Run the acceptance commands. Commit.
