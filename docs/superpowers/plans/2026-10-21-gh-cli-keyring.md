# gh CLI keyring Implementation Plan

spec: docs/superpowers/specs/2026-10-21-gh-cli-keyring-design.md

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `install_github_cli_linux` never empties the live keyring, its tests never reach `/etc/apt`, and it runs first and non-fatally in `run_developer_or_ansible`.

**Architecture:** Reuse `_install_apt_keyring` and `_write_apt_source_list` (`lib/linux_ubuntu.sh`) exactly as `_install_ubuntu_docker` does, behind two new path seams. Move the step to the top of `run_developer_or_ansible`, keep its rc, warn at the end, return 0, and record exit code 2 in the ledger.

**Tech Stack:** bash, bats, PATH mocks in `tests/mocks/`.

## Global Constraints

- No change to `_install_apt_keyring` or `_write_apt_source_list` (N1).
- No change to the fail-fast behaviour of any other step in `run_developer_or_ansible` (N2).
- No change to which machines install apt `gh` or linuxbrew `gh` (N3).
- Seam defaults: `_GH_CLI_KEYRING=/etc/apt/keyrings/githubcli-archive-keyring.gpg`, `_GH_CLI_SOURCES_LIST=/etc/apt/sources.list.d/github-cli.list`.
- Key URL `https://cli.github.com/packages/githubcli-archive-keyring.gpg`, kind `binary`.
- Every `sudo` apt call keeps `DEBIAN_FRONTEND=noninteractive` on the sudo line and the quoted `"${APT_CONFFILE_OPTS[@]}"`.

## Verification

- Session gate: `make test` exits 0 in the worktree, run once by the orchestrator after Task 2 (the suite reads `lib/` and `tests/`; Task 3 cannot change its result).
- Edge cases covered by tests: failed fetch with and without an existing keyring, apt install failure, non-Ubuntu, gh partial with later steps succeeding, ordering against a later hard failure.
- After merge (V2, operator): on `claude`, `./setup_env.sh -t developer`, then `file /etc/apt/keyrings/githubcli-archive-keyring.gpg` reports an OpenPGP public key and `sudo apt update` shows no `cli.github.com` error.

---

### Task 1: no-clobber gh keyring with path seams

```yaml-task
id: 1
description: Route install_github_cli_linux through _install_apt_keyring and _write_apt_source_list behind _GH_CLI_KEYRING/_GH_CLI_SOURCES_LIST, returning 1 on any failed stage
role: executor
model: sonnet
tdd: required
requirements: [R1, R2, R3, R4, R5, R9, R10]
acceptance:
  - cmd: bats --jobs 24 tests/setup_env/workflows.bats
    exit_code: 0
  - cmd: make lint
    exit_code: 0
  - cmd: '! command grep -q "wget -qO- https://cli.github.com" lib/developer.sh'
    exit_code: 0
  - cmd: 'command grep -q "_GH_CLI_KEYRING=" tests/setup_env/workflows.bats'
    exit_code: 0
max_retries: 3
files_touched: [lib/developer.sh, tests/setup_env/workflows.bats]
depends_on: []
```

**Files:** `lib/developer.sh` (`install_github_cli_linux`, ~line 509), `tests/setup_env/workflows.bats` (`setup()` at line 6; gh tests at ~1364).

**Steps:**

- [ ] In `setup()`, after `load_setup_env`, add with a one-line why-comment (tests/mocks/sudo execs real tee/install/mv):
      `export _GH_CLI_KEYRING="${BATS_TEST_TMPDIR}/apt/keyrings/githubcli-archive-keyring.gpg"`, `export _GH_CLI_SOURCES_LIST="${BATS_TEST_TMPDIR}/apt/sources.list.d/github-cli.list"`, `mkdir -p "${BATS_TEST_TMPDIR}/apt/sources.list.d" "${BATS_TEST_TMPDIR}/apt-key-tmp"`, `export _APT_KEY_TMP_ROOT="${BATS_TEST_TMPDIR}/apt-key-tmp"`, `export MOCK_CURL_STDOUT='fake-gh-keyring-bytes'`.
      Keep the two existing gh tests' bare calls (R10).
- [ ] Write failing tests (Ubuntu: `unset MACOS; export LINUX=1 UBUNTU=1`; use `run` and assert `$status`):
  1. pre-seed `_GH_CLI_KEYRING` with `old-key`, `MOCK_CURL_EXIT=22`: status 1, file still exactly `old-key`, output has `github cli: keyring: install failed`, `MOCK_CALLS_FILE` has `apt install` … `gh`.
  2. no keyring, `MOCK_CURL_EXIT=22`: `[ ! -e "${_GH_CLI_SOURCES_LIST}" ]`.
  3. success: status 0, keyring content equals `fake-gh-keyring-bytes`, list contains `signed-by=${_GH_CLI_KEYRING}] https://cli.github.com/packages stable main`.
  4. `MOCK_APT_FAIL_SUBCMD=install`: status 1, output has `github cli: gh: install failed`.
  5. `unset UBUNTU`: status 0, no `curl`/`apt` line in `MOCK_CALLS_FILE`.
- [ ] Run `bats tests/setup_env/workflows.bats -f install_github_cli_linux`; confirm the new tests fail for the right reason (not a syntax/usage error).
- [ ] Replace the function body with the spec's code block (Design → `install_github_cli_linux`): seams, `sudo mkdir -p "$(dirname "${_keyring}")"`, `_install_apt_keyring … binary`, `_write_apt_source_list "github cli" "source list" …`, `sudo -H apt update || :`, apt install with warning, `return "${_rc}"`. Drop `chmod go+r` and the trailing `gh is installed` if-block. Keep the `UBUNTU` guard and `printf "installing github cli on Ubuntu\\n"`.
- [ ] Run the gates; commit via `caveman:caveman-commit`.

**Interfaces:** Produces `install_github_cli_linux` → 0 all stages ok or not Ubuntu; 1 any failed stage, each named in a `github cli:` warning.

### Task 2: run gh first, non-fatal, ledger records 2

```yaml-task
id: 2
description: Move install_github_cli_linux before _require_npm_pins in run_developer_or_ansible, keep its rc, warn at the end, return 0, and pass exit code 2 to _ledger_write_run_entry on a gh partial
role: executor
model: sonnet
tdd: required
requirements: [R6, R7, R8]
acceptance:
  - cmd: bats --jobs 24 tests/setup_env/workflows.bats
    exit_code: 0
  - cmd: make lint
    exit_code: 0
  - cmd: 'awk ''/^run_developer_or_ansible\(\)/{f=1} f&&/install_github_cli_linux/{g=NR} f&&/_require_npm_pins \|\|/{n=NR} f&&/^}/{exit} END{exit !(g && n && g<n)}'' lib/workflows.sh'
    exit_code: 0
max_retries: 3
files_touched: [lib/workflows.sh, tests/setup_env/workflows.bats]
depends_on: [1]
```

**Files:** `lib/workflows.sh` (`run_developer_or_ansible`, ~line 615), `tests/setup_env/workflows.bats` (existing `run_developer_or_ansible` tests ~2595-2620).

**Steps:**

- [ ] Write failing tests, stubbing `install_ruby_tools`, `install_ruby`, `setup_ansible`, `clone_personal_repos`, `install_github_cli_linux` as functions that append a name to `MOCK_CALLS_FILE` (existing pattern at ~2612), and `_ledger_write_run_entry() { printf 'ledger %s %s\n' "$1" "$2" >> "${MOCK_CALLS_FILE}"; }` (pattern at ~863): 7. `export LINUX=1`, gh stub returns 1: status 0; `setup_ansible` and `clone_repos` lines present; output has `github cli: install incomplete`; `MOCK_CALLS_FILE` has `ledger developer 2`. 8. gh stub returns 0, `install_ruby` stub returns 1: status 1; both `github_cli_linux` and `install_ruby` lines present (assert each with `grep -n`), and the gh line number is lower than the ruby line number; no `ledger` line.
      Update the existing Linux success test to also assert `ledger developer 0`. Leave the macOS/`LINUX`-unset test as is.
- [ ] Run them; confirm 7 and 8 fail for the right reason.
- [ ] Apply the spec's `run_developer_or_ansible` block: `local _gh_rc=0`, gh step right after `_dotfiles_run_tmpdir_setup || return 1`, `install_github_cli_linux || _gh_rc=2`; remove the old step after `install_ruby`; before the ledger call `[[ ${_gh_rc} -ne 0 ]] && log_warn "github cli: install incomplete (keyring, source list or gh) -- see the 'github cli:' warnings at the start of this run"` (use an `if`, so the function's last status stays from the ledger call); `_ledger_write_run_entry "developer" "${_gh_rc}" || true`. No `return "${_gh_rc}"`.
- [ ] Run the gates; commit via `caveman:caveman-commit`.

**Interfaces:** Consumes Task 1's 0/1 contract. Produces `run_developer_or_ansible` → 1 on a hard failure (no ledger entry), else 0 with ledger exit code 0 or 2.

### Task 3: docs — seam line, backlog, plan index

```yaml-task
id: 3
description: Docs-only (no behaviour change, TDD not applicable) - add the gh seam line to CLAUDE.md, remove the two shipped backlog rows, file the duplicate-gh row, add the plan index row
role: executor
model: sonnet
tdd: not-applicable
acceptance:
  - cmd: make lint
    exit_code: 0
  - cmd: 'command grep -q "_GH_CLI_KEYRING" CLAUDE.md'
    exit_code: 0
  - cmd: '! command grep -q "writes an empty keyring on a failed fetch" docs/superpowers/README.md'
    exit_code: 0
  - cmd: 'command grep -q "plans/2026-10-21-gh-cli-keyring.md" docs/superpowers/README.md'
    exit_code: 0
max_retries: 2
files_touched: [CLAUDE.md, docs/superpowers/README.md]
depends_on: [2]
```

**Steps:**

- [ ] `CLAUDE.md` Test Seams, right after the `_DOCKER_KEYRING`/`_DOCKER_SOURCES_LIST` bullet (~line 431), same two-line shape:
      `- \`_GH_CLI_KEYRING\`/\`_GH_CLI_SOURCES_LIST\` (\`lib/developer.sh:install_github_cli_linux\`)`/` - Defaults \`/etc/apt/keyrings/githubcli-archive-keyring.gpg\` and \`/etc/apt/sources.list.d/github-cli.list\`; \`tests/setup_env/workflows.bats\` sets both at setup scope so the sudo mock cannot write the real \`/etc/apt\`.`
- [ ] `docs/superpowers/README.md`: delete the P2 bugs row "`install_github_cli_linux` writes an empty keyring on a failed fetch" and the P2 test-gaps row "`install_github_cli_linux` tests reach real `/etc/apt` paths".
- [ ] Add to the **P3 — tech-debt** table (NOT the last table, which is "Closed without shipping"): `| gh installed twice on \`claude\` | linuxbrew \`gh\` (\`lib/linux_ubuntu.sh:1425\` list) shadows apt \`/usr/bin/gh\` from \`install_github_cli_linux\`; \`workstation\` has only apt's (measured 2026-10-21). Decide one source. Out of scope of \`specs/2026-10-21-gh-cli-keyring-design.md\`. |`
- [ ] Add the top All Plans row: `| 2026-10-21 | [gh cli keyring](plans/2026-10-21-gh-cli-keyring.md) | [install_github_cli_linux: no clobber, seamed paths, run first](specs/2026-10-21-gh-cli-keyring-design.md) | In Progress |`
- [ ] Run the gates; commit via `caveman:caveman-commit`.

## Non-goal check

Reviewer verdicts (2026-10-21, fresh subagent, `nongoal-check.md`): 0 CONFLICT, 0 UNCLEAR.

- **N1 CLEAR** — "Task 1 calls `_install_apt_keyring` and `_write_apt_source_list` but does not edit them. Its `files_touched` lists only `lib/developer.sh` and the test file." Resolution: none needed.
- **N2 CLEAR** — "Test 8 checks that an `install_ruby` failure still returns 1 with no ledger entry." Resolution: none needed.
- **N3 CLEAR** — "The `UBUNTU` guard stays, and the linuxbrew `gh` list is not edited." The reviewer flagged that dropping the trailing `gh is installed` block would make N3 UNCLEAR if it installed gh; it is only `printf "gh is installed Ubuntu\\n"` (`lib/developer.sh:518-520`). Resolution: none needed.
