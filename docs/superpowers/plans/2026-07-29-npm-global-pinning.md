# npm Global Package Pinning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `jscpd` to the npm global install chain and pin all three global packages to exact versions at both call sites.

**Architecture:** Version pins go in `lib/constants.sh` alongside the existing `<NAME>_VER` scalars (that file is literally titled "version pins"). `lib/workflows.sh` references them at its two npm call sites — the install path in `run_developer_or_ansible` and the update chain in `run_update`. No new pattern is introduced; the repo already pins ~25 tools this way.

**Tech Stack:** bash, BATS, existing `tests/mocks/npm` invocation-capture mock.

## Global Constants

- Pins, measured via `npm view` on 2026-07-29: `jscpd@5.0.14`, `firecrawl-cli@1.19.27`, `exa-mcp-server@3.2.1`.
- Constant naming follows the existing convention exactly: `JSCPD_VER`, `FIRECRAWL_CLI_VER`, `EXA_MCP_SERVER_VER` (compare `BATS_VER`, `GITLEAKS_VER`).
- `shell.md`: no `set -e` outside git hooks; `printf` not `echo`; `[[ ]]` not `[ ]`; `${VAR}` braces; `|| return 1` inside functions.
- Both existing call-site shapes are preserved. The install path installs one package per `npm` invocation with its own `printf` and `|| return 1`; the update chain installs all packages in a single piped invocation. Do not consolidate either — failure granularity in the install path and `PIPESTATUS` in the update chain both depend on the current shape.
- `SHELL_FILES := $(shell find . -name "*.sh" ...)` so both edited files are covered by `make lint` (`bash -n` + `shellcheck`) automatically.

## Non-goals (from the spec — do not re-litigate)

- This work claims **no** coverage row in ai-config's maintainability manifest and must not be justified as moving one. `duplication.implemented` stays `False` before and after.
- No `jscpd` caller is written. This installs the tool; nothing invokes it.
- `lib/workflows.sh:209` `npm install json2yaml` is missing `-g` and installs into the current working directory. **Do not fix it here** — different bug shape, own backlog row.
- Do not wire these pins into `run_check_versions`. See "Follow-on" below; it is a separate, now-measured backlog row.

## Verification Planning

**Session-level verification, above the per-task gates:**

| What                                 | Command                                                               | Expected                                                                                  |
| ------------------------------------ | --------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| Full suite green                     | `make test` (from repo root)                                          | exit 0. Runs `lint` first (`bash -n` + `shellcheck` over all `*.sh`)                      |
| Install path pins land               | `bats tests/setup_env/workflows.bats -f "install"`                    | Captured calls contain `jscpd@5.0.14`, `firecrawl-cli@1.19.27`, `exa-mcp-server@3.2.1`    |
| Update chain pins land               | `bats tests/setup_env/workflows.bats -f "npm"`                        | Same three pinned strings in the update-chain call                                        |
| No unpinned invocation survives      | the negative assertions in Tasks 2 and 3                              | A bare `firecrawl-cli` not followed by `@` fails the test                                 |
| Update-chain exit propagation intact | `bats tests/setup_env/workflows.bats -f "npm"` with `MOCK_NPM_EXIT=1` | `status_npm` records failure — proves `PIPESTATUS[0]` still reads npm's exit, not `tee`'s |

**Edge cases that must be exercised to be confident:**

1. **`PIPESTATUS[0]` must still be npm's exit code.** The update chain is `npm ... 2>&1 | tee "${_DOTFILES_RUN_TMPDIR}/err_npm"` followed by `_update_record_end "npm" "${PIPESTATUS[0]}"`. Any restructuring that breaks the pipeline silently makes the recorded status `tee`'s (always 0), so a failed global install would report OK. Task 3 asserts the failure path, not only the success path.
2. **The existing assertion cannot detect this change's own regression.** `tests/setup_env/workflows.bats:1495` is `grep -q "npm install -g firecrawl-cli"` — a substring match that passes with or without a pin. It also passes today and would pass if someone later removed the pins. Task 3 replaces it rather than adding beside it.
3. **Skip branch unchanged.** `run_update` skips npm entirely unless `_run_all` or `UPDATE_CLAUDE` is set. Adding a package must not alter that guard; the existing skip test must still pass untouched.

---

### Task 1: Add the three npm version pins to lib/constants.sh

```yaml-task
id: 1
description: Add JSCPD_VER, FIRECRAWL_CLI_VER, EXA_MCP_SERVER_VER pins (pure configuration, three scalar assignments, no behavior change — tests for the behavior live in Tasks 2 and 3 which assert the call sites)
role: executor
model: haiku
tdd: not-applicable
acceptance:
  - cmd: make lint
    exit_code: 0
  - cmd: 'bash -c ''source lib/constants.sh && [[ "${JSCPD_VER}" == "5.0.14" ]]'''
    exit_code: 0
  - cmd: 'bash -c ''source lib/constants.sh && [[ "${FIRECRAWL_CLI_VER}" == "1.19.27" ]]'''
    exit_code: 0
  - cmd: 'bash -c ''source lib/constants.sh && [[ "${EXA_MCP_SERVER_VER}" == "3.2.1" ]]'''
    exit_code: 0
max_retries: 3
files_touched:
  - lib/constants.sh
depends_on: []
```

**Files:** `lib/constants.sh`

Add to the version-pin block near the top (the run of `<NAME>_VER="x.y.z"` assignments starting at `BATS_VER`), keeping that block's alphabetical-ish grouping. Plain assignment, not `readonly` — this file is sourced repeatedly by the test suite and `readonly` re-assignment errors on a second source.

```bash
EXA_MCP_SERVER_VER="3.2.1"
FIRECRAWL_CLI_VER="1.19.27"
JSCPD_VER="5.0.14"
```

Add one comment line above the three, because the reason they are unlike every other pin in this file is not derivable from the code:

```bash
# npm global packages — pinned by exact version at both lib/workflows.sh call sites.
# Unlike the GitHub-release pins above, these are NOT covered by
# `./setup_env.sh -t check-versions`: only jscpd publishes GitHub releases matching
# its npm version. See docs/superpowers/plans/2026-07-29-npm-global-pinning.md.
```

**Interfaces:**

- Consumes: nothing.
- Produces: shell variables `JSCPD_VER`, `FIRECRAWL_CLI_VER`, `EXA_MCP_SERVER_VER`, each a bare semver string with no leading `v`. Tasks 2 and 3 interpolate them as `"<pkg>@${<NAME>_VER}"`.

---

### Task 2: Pin the install-path npm calls and add jscpd

```yaml-task
id: 2
description: Pin the two run_developer_or_ansible npm global installs and add a third for jscpd, with a BATS test asserting exact pinned invocations
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: make lint
    exit_code: 0
  - cmd: bats tests/setup_env/workflows.bats
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - lib/workflows.sh
  - tests/setup_env/workflows.bats
depends_on: [1]
```

**Files:** `lib/workflows.sh` (install path, currently lines 208-215), `tests/setup_env/workflows.bats`

**RED first.** Add this test. It must fail before the implementation, because no pinned string exists yet.

```bash
@test "run_developer_or_ansible pins every npm global package" {
  export MACOS=1
  unset LINUX UBUNTU
  run_developer_or_ansible
  grep -q "npm install -g jscpd@5.0.14" "${MOCK_CALLS_FILE}"
  grep -q "npm install -g firecrawl-cli@1.19.27" "${MOCK_CALLS_FILE}"
  grep -q "npm install -g exa-mcp-server@3.2.1" "${MOCK_CALLS_FILE}"
}

@test "run_developer_or_ansible leaves no unpinned npm global install" {
  export MACOS=1
  unset LINUX UBUNTU
  run_developer_or_ansible
  # A global package name not followed by '@' is an unpinned invocation. This is the
  # assertion the pre-existing substring test could not make: `grep -q "npm install
  # -g firecrawl-cli"` matches the pinned and unpinned forms identically.
  ! grep -qE 'npm install -g (jscpd|firecrawl-cli|exa-mcp-server)($|[^@])' \
    "${MOCK_CALLS_FILE}"
}
```

If `run_developer_or_ansible` cannot be driven to completion in the harness (it calls `install_ruby_tools`, `install_ruby`, and OS-branch installers after the npm block), scope the test to the npm block by asserting on `MOCK_CALLS_FILE` after `run` rather than requiring exit 0 — use `run run_developer_or_ansible` and assert only on the captured calls. Do not add mocks beyond those already in `tests/mocks/`.

**GREEN.** Replace the three-line npm block, preserving one invocation per package with its own `printf` and `|| return 1`:

```bash
  printf "Installing jscpd via npm\n"
  npm install -g "jscpd@${JSCPD_VER}" || return 1

  printf "Installing firecrawl-cli via npm\n"
  npm install -g "firecrawl-cli@${FIRECRAWL_CLI_VER}" || return 1

  printf "Installing exa-mcp-server via npm\n"
  npm install -g "exa-mcp-server@${EXA_MCP_SERVER_VER}" || return 1
```

Insert the jscpd block after the existing `json2yaml` line and before `firecrawl-cli`. Leave line 209 (`npm install json2yaml`, no `-g`) exactly as it is — it is a separate backlog row.

**Interfaces:**

- Consumes: `JSCPD_VER`, `FIRECRAWL_CLI_VER`, `EXA_MCP_SERVER_VER` from Task 1.
- Produces: nothing consumed by later tasks. Task 3 edits a different function in the same file.

---

### Task 3: Pin the update-chain npm call, add jscpd, and replace the weak assertion

```yaml-task
id: 3
description: Pin the run_update npm global install and add jscpd, replacing the substring assertion that passes with or without a pin, and asserting PIPESTATUS still carries npm's exit
role: executor
model: sonnet
tdd: required
acceptance:
  - cmd: make lint
    exit_code: 0
  - cmd: bats tests/setup_env/workflows.bats
    exit_code: 0
  - cmd: make test
    exit_code: 0
max_retries: 3
files_touched:
  - lib/workflows.sh
  - tests/setup_env/workflows.bats
depends_on: [2]
```

**Files:** `lib/workflows.sh` (update chain, currently line 380), `tests/setup_env/workflows.bats` (the existing test at ~1489)

**RED first.** Rewrite the existing `run_update calls npm install when UPDATE_CLAUDE is set` test in place — do not add a second test beside it, because the point is that the old assertion is unable to fail:

```bash
@test "run_update installs pinned npm globals when UPDATE_CLAUDE is set" {
  export MACOS=1
  unset LINUX UBUNTU
  export UPDATE_CLAUDE=1
  unset UPDATE_BREW UPDATE_PIP UPDATE_GEMS UPDATE_MAS UPDATE_PKGS
  run_update
  grep -q "jscpd@5.0.14" "${MOCK_CALLS_FILE}"
  grep -q "firecrawl-cli@1.19.27" "${MOCK_CALLS_FILE}"
  grep -q "exa-mcp-server@3.2.1" "${MOCK_CALLS_FILE}"
  ! grep -qE 'npm install -g .*(jscpd|firecrawl-cli|exa-mcp-server)($|[^@])' \
    "${MOCK_CALLS_FILE}"
}

@test "run_update records npm failure — PIPESTATUS carries npm's exit, not tee's" {
  export MACOS=1
  unset LINUX UBUNTU
  export UPDATE_CLAUDE=1
  unset UPDATE_BREW UPDATE_PIP UPDATE_GEMS UPDATE_MAS UPDATE_PKGS
  export MOCK_NPM_EXIT=1
  run_update
  # tee always exits 0. If the pipeline shape is broken, this records OK.
  ! grep -q "OK" "${_DOTFILES_RUN_TMPDIR}/status_npm"
}
```

The second test is the state-transition and error-path case required by `tdd.md`. It fails today only if the pipeline is broken, so write it, confirm it passes on the unmodified pipeline, then confirm it still passes after the edit — it is a regression guard, not a RED-first test.

Leave the existing `run_update skips npm when UPDATE_CLAUDE flag not set` test completely untouched. It is the false-branch half of the guard pair.

**GREEN.** Pin the single invocation, keeping the pipe and the `PIPESTATUS[0]` read exactly as they are:

```bash
    npm install -g "jscpd@${JSCPD_VER}" "firecrawl-cli@${FIRECRAWL_CLI_VER}" \
      "exa-mcp-server@${EXA_MCP_SERVER_VER}" 2>&1 \
      | tee "${_DOTFILES_RUN_TMPDIR}/err_npm"
    _update_record_end "npm" "${PIPESTATUS[0]}"
```

A line continuation before the pipe is safe; moving the `| tee` off the npm command, or wrapping the invocation in a subshell or function, is not — either makes `PIPESTATUS[0]` read something other than npm's exit.

**Interfaces:**

- Consumes: the three pins from Task 1.
- Produces: nothing. Terminal task.

---

## Follow-on — verified, not assumed

Both rows below were measured on 2026-07-29 rather than inferred, and belong in
`ai-config/docs/superpowers/README.md`'s Backlog.

**1. Wire `jscpd` — and only `jscpd` — into `run_check_versions`.** The spec that
scoped this work recorded "dotfiles has no `renovate.json`, so these pins have no
automated bump path." True about renovate, incomplete about dotfiles: `run_check_versions`
(`lib/workflows.sh:722`) compares `lib/constants.sh` pins against GitHub releases and
`--update` rewrites them interactively. It is a **curated list** of `_run_cv_check` calls,
not an iteration over the file, so adding a pin does not enrol it. Measured, per package:

| package          | `releases/latest`                                   | matches npm | wireable                |
| ---------------- | --------------------------------------------------- | ----------- | ----------------------- |
| `jscpd`          | `5.0.14`                                            | yes         | **yes**                 |
| `firecrawl-cli`  | none — `mendableai/firecrawl` publishes no releases | —           | no                      |
| `exa-mcp-server` | none                                                | —           | no, and actively unsafe |

`exa-mcp-server --version` does not print a version — it **starts the server**
(`[smithery] Starting MCP server with stdio transport`), so `_check_one_version` would
hang on it. `firecrawl-cli` is installed per `npm ls -g` yet `command -v firecrawl-cli`
fails, so its binary is named something else and the `_tool` argument cannot be the
package name. Wire jscpd only, and record in a comment why the other two are excluded, or
the next reader will "fix" the omission.

**2. `lib/workflows.sh:209` — `npm install json2yaml` with no `-g`.** Installs into
whatever the current working directory happens to be, which is why a gitignored
`dotfiles/node_modules/` tree exists. Different shape from the pinning work (local vs
global install), deliberately excluded from this plan.
