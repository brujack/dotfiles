# GitHub MCP Server Implementation Plan

> **Status: DONE**

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Install the GitHub MCP server on all dev machines via dotfiles, with the
PAT stored per-machine in `config/local.sh` and the token never committed to git.

**Architecture:** Rename `.claude/mcp.json` to `.claude/mcp.json.template` (tracked,
contains `${GITHUB_PAT}` placeholder). `setup_claude_mcp` in `lib/workflows.sh`
generates `~/.claude/mcp.json` via `envsubst` at setup time. `_doctor_check_github_mcp`
in `lib/helpers.sh` validates the generated file, live token, and expiry.

**Tech Stack:** Bash, BATS, `envsubst` (gettext), GitHub REST API (`api.github.com/user`)

---

## File Map

| File                             | Change                                                                                 |
| -------------------------------- | -------------------------------------------------------------------------------------- |
| `.claude/mcp.json`               | DELETE (git rm)                                                                        |
| `.claude/mcp.json.template`      | CREATE — tracked template with `${GITHUB_PAT}` placeholder                             |
| `lib/helpers.sh`                 | ADD `_DOCTOR_WARN`, `doctor_warn()`, `_doctor_check_github_mcp()`; update `run_doctor` |
| `lib/workflows.sh`               | ADD `setup_claude_mcp()`; update `run_setup_user`                                      |
| `config/local.sh.example`        | ADD `GITHUB_PAT` and `GITHUB_PAT_EXPIRY` vars                                          |
| `tests/setup_env/unit.bats`      | ADD `doctor_warn` and `_doctor_check_github_mcp` tests                                 |
| `tests/setup_env/workflows.bats` | ADD `setup_claude_mcp` tests                                                           |
| `README.md`                      | ADD GitHub MCP section                                                                 |
| `CLAUDE.md`                      | UPDATE symlink section; ADD mock var rows                                              |
| `.claude/CLAUDE.md`              | ADD `## GitHub MCP` section                                                            |
| `docs/superpowers/README.md`     | ADD plan row                                                                           |

---

### Task 1: Migrate mcp.json to mcp.json.template

**Files:**

- Delete: `.claude/mcp.json`
- Create: `.claude/mcp.json.template`

- [ ] **Step 1: Rename the file in git**

  ```bash
  git mv .claude/mcp.json .claude/mcp.json.template
  ```

- [ ] **Step 2: Add the GitHub MCP entry to the template**

  Replace the contents of `.claude/mcp.json.template` with:

  ```json
  {
    "mcpServers": {
      "sequential-thinking": {
        "command": "npx",
        "args": ["-y", "@modelcontextprotocol/server-sequential-thinking"]
      },
      "github": {
        "type": "http",
        "url": "https://api.githubcopilot.com/mcp/",
        "headers": {
          "Authorization": "Bearer ${GITHUB_PAT}"
        }
      }
    }
  }
  ```

- [ ] **Step 3: Verify template is valid JSON with placeholder intact**

  ```bash
  python3 -c "import json,sys; json.load(sys.stdin)" < .claude/mcp.json.template
  grep -q '\${GITHUB_PAT}' .claude/mcp.json.template
  ```

  Expected: no JSON parse error; exit 0 for grep.

- [ ] **Step 4: Commit**

  ```bash
  git add .claude/mcp.json.template
  git commit -m "chore: rename mcp.json to mcp.json.template for token substitution

  Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
  ```

---

### Task 2: Add doctor_warn to helpers.sh

**Files:**

- Modify: `lib/helpers.sh` (after line 26, alongside `_DOCTOR_PASS`/`_DOCTOR_FAIL`)

- [ ] **Step 1: Write the failing test**

  In `tests/setup_env/unit.bats`, add after the `doctor_pass / doctor_fail` section
  (after line ~595):

  ```bash
  # ── doctor_warn ──────────────────────────────────────────────────────────────

  @test "doctor_warn increments _DOCTOR_WARN" {
    _DOCTOR_WARN=0
    doctor_warn "some check" "a warning"
    [ "${_DOCTOR_WARN}" -eq 1 ]
  }

  @test "doctor_warn does not set _DOCTOR_FAILED" {
    _DOCTOR_FAILED=0
    _DOCTOR_WARN=0
    doctor_warn "some check" "a warning"
    [ "${_DOCTOR_FAILED}" -eq 0 ]
  }

  @test "doctor_warn prints [WARN] with label and detail" {
    _DOCTOR_WARN=0
    run doctor_warn "my label" "my detail"
    [[ "$output" == *"[WARN]"* ]]
    [[ "$output" == *"my label"* ]]
    [[ "$output" == *"my detail"* ]]
  }
  ```

- [ ] **Step 2: Run tests to verify they fail**

  ```bash
  make test 2>&1 | grep -E "not ok.*doctor_warn"
  ```

  Expected: 3 failing tests mentioning `doctor_warn`.

- [ ] **Step 3: Add `_DOCTOR_WARN` counter and `doctor_warn` function to helpers.sh**

  In `lib/helpers.sh`, find the block (lines 23–37):

  ```bash
  # ── doctor check primitives ───────────────────────────────────────────────────
  _DOCTOR_PASS=0
  _DOCTOR_FAIL=0
  _DOCTOR_FAILED=0

  doctor_pass() {
    _DOCTOR_PASS=$(( _DOCTOR_PASS + 1 ))
    printf "  ${_GREEN}[PASS]${_NC} %s\n" "$1"
  }

  doctor_fail() {
    _DOCTOR_FAIL=$(( _DOCTOR_FAIL + 1 ))
    _DOCTOR_FAILED=1
    printf "  ${_RED}[FAIL]${_NC} %s: %s\n" "$1" "${2:-}"
  }
  ```

  Replace with:

  ```bash
  # ── doctor check primitives ───────────────────────────────────────────────────
  _DOCTOR_PASS=0
  _DOCTOR_FAIL=0
  _DOCTOR_FAILED=0
  _DOCTOR_WARN=0

  doctor_pass() {
    _DOCTOR_PASS=$(( _DOCTOR_PASS + 1 ))
    printf "  ${_GREEN}[PASS]${_NC} %s\n" "$1"
  }

  doctor_fail() {
    _DOCTOR_FAIL=$(( _DOCTOR_FAIL + 1 ))
    _DOCTOR_FAILED=1
    printf "  ${_RED}[FAIL]${_NC} %s: %s\n" "$1" "${2:-}"
  }

  doctor_warn() {
    _DOCTOR_WARN=$(( _DOCTOR_WARN + 1 ))
    printf "  ${_YELLOW}[WARN]${_NC} %s: %s\n" "$1" "${2:-}"
  }
  ```

- [ ] **Step 4: Run tests to verify they pass**

  ```bash
  make test 2>&1 | grep -E "(not ok.*doctor_warn|ok.*doctor_warn)"
  ```

  Expected: 3 passing tests, 0 failing.

- [ ] **Step 5: Commit**

  ```bash
  git add lib/helpers.sh tests/setup_env/unit.bats
  git commit -m "feat: add doctor_warn helper to helpers.sh

  Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
  ```

---

### Task 3: Add \_doctor_check_github_mcp to helpers.sh

**Files:**

- Modify: `lib/helpers.sh` (add function after `_doctor_check_versions`)
- Modify: `tests/setup_env/unit.bats` (add tests)

- [ ] **Step 1: Write the failing tests**

  In `tests/setup_env/unit.bats`, add a new section after the `doctor_warn` tests:

  ```bash
  # ── _doctor_check_github_mcp ─────────────────────────────────────────────────

  @test "_doctor_check_github_mcp fails when ~/.claude/mcp.json is missing" {
    _DOCTOR_FAIL=0; _DOCTOR_FAILED=0; _DOCTOR_PASS=0; _DOCTOR_WARN=0
    unset GITHUB_PAT GITHUB_PAT_EXPIRY
    # HOME is BATS_TEST_TMPDIR — no .claude/mcp.json exists
    _doctor_check_github_mcp
    [ "${_DOCTOR_FAIL}" -eq 1 ]
    [ "${_DOCTOR_FAILED}" -eq 1 ]
  }

  @test "_doctor_check_github_mcp fails when GITHUB_PAT is unset" {
    _DOCTOR_FAIL=0; _DOCTOR_FAILED=0; _DOCTOR_PASS=0; _DOCTOR_WARN=0
    unset GITHUB_PAT GITHUB_PAT_EXPIRY
    mkdir -p "${HOME}/.claude"
    printf '{"mcpServers":{}}\n' > "${HOME}/.claude/mcp.json"
    _doctor_check_github_mcp
    [ "${_DOCTOR_FAIL}" -eq 1 ]
  }

  @test "_doctor_check_github_mcp fails when curl exits 22 (invalid token)" {
    _DOCTOR_FAIL=0; _DOCTOR_FAILED=0; _DOCTOR_PASS=0; _DOCTOR_WARN=0
    export GITHUB_PAT="fake-token"
    unset GITHUB_PAT_EXPIRY
    mkdir -p "${HOME}/.claude"
    printf '{"mcpServers":{}}\n' > "${HOME}/.claude/mcp.json"
    export MOCK_CURL_EXIT=22
    _doctor_check_github_mcp
    [ "${_DOCTOR_FAIL}" -eq 1 ]
  }

  @test "_doctor_check_github_mcp warns when curl exits 28 (timeout)" {
    _DOCTOR_FAIL=0; _DOCTOR_FAILED=0; _DOCTOR_PASS=0; _DOCTOR_WARN=0
    export GITHUB_PAT="fake-token"
    unset GITHUB_PAT_EXPIRY
    mkdir -p "${HOME}/.claude"
    printf '{"mcpServers":{}}\n' > "${HOME}/.claude/mcp.json"
    export MOCK_CURL_EXIT=28
    _doctor_check_github_mcp
    [ "${_DOCTOR_FAIL}" -eq 0 ]
    [ "${_DOCTOR_WARN}" -ge 1 ]
  }

  @test "_doctor_check_github_mcp warns when curl exits 6 (DNS failure)" {
    _DOCTOR_FAIL=0; _DOCTOR_FAILED=0; _DOCTOR_PASS=0; _DOCTOR_WARN=0
    export GITHUB_PAT="fake-token"
    unset GITHUB_PAT_EXPIRY
    mkdir -p "${HOME}/.claude"
    printf '{"mcpServers":{}}\n' > "${HOME}/.claude/mcp.json"
    export MOCK_CURL_EXIT=6
    _doctor_check_github_mcp
    [ "${_DOCTOR_FAIL}" -eq 0 ]
    [ "${_DOCTOR_WARN}" -ge 1 ]
  }

  @test "_doctor_check_github_mcp warns when GITHUB_PAT_EXPIRY within 30 days" {
    _DOCTOR_FAIL=0; _DOCTOR_FAILED=0; _DOCTOR_PASS=0; _DOCTOR_WARN=0
    export GITHUB_PAT="fake-token"
    mkdir -p "${HOME}/.claude"
    printf '{"mcpServers":{}}\n' > "${HOME}/.claude/mcp.json"
    export MOCK_CURL_EXIT=0
    # Set expiry to 5 days from now (within 30-day warning window)
    if [[ -n "${MACOS:-}" ]]; then
      export GITHUB_PAT_EXPIRY=$(date -v+5d +%Y-%m-%d)
    else
      export GITHUB_PAT_EXPIRY=$(date -d "+5 days" +%Y-%m-%d)
    fi
    _doctor_check_github_mcp
    [ "${_DOCTOR_WARN}" -ge 1 ]
  }

  @test "_doctor_check_github_mcp prints INFO when GITHUB_PAT_EXPIRY not set" {
    _DOCTOR_FAIL=0; _DOCTOR_FAILED=0; _DOCTOR_PASS=0; _DOCTOR_WARN=0
    export GITHUB_PAT="fake-token"
    unset GITHUB_PAT_EXPIRY
    mkdir -p "${HOME}/.claude"
    printf '{"mcpServers":{}}\n' > "${HOME}/.claude/mcp.json"
    export MOCK_CURL_EXIT=0
    run _doctor_check_github_mcp
    [[ "$output" == *"GITHUB_PAT_EXPIRY"* ]]
  }

  @test "_doctor_check_github_mcp passes when all checks pass" {
    _DOCTOR_FAIL=0; _DOCTOR_FAILED=0; _DOCTOR_PASS=0; _DOCTOR_WARN=0
    export GITHUB_PAT="fake-token"
    mkdir -p "${HOME}/.claude"
    printf '{"mcpServers":{}}\n' > "${HOME}/.claude/mcp.json"
    export MOCK_CURL_EXIT=0
    # Set expiry 90 days out (outside warning window)
    if [[ -n "${MACOS:-}" ]]; then
      export GITHUB_PAT_EXPIRY=$(date -v+90d +%Y-%m-%d)
    else
      export GITHUB_PAT_EXPIRY=$(date -d "+90 days" +%Y-%m-%d)
    fi
    _doctor_check_github_mcp
    [ "${_DOCTOR_FAIL}" -eq 0 ]
    [ "${_DOCTOR_FAILED}" -eq 0 ]
  }
  ```

- [ ] **Step 2: Run tests to verify they fail**

  ```bash
  make test 2>&1 | grep "not ok.*github_mcp"
  ```

  Expected: 8 failing tests.

- [ ] **Step 3: Add `_doctor_check_github_mcp` to helpers.sh**

  In `lib/helpers.sh`, after the `_doctor_check_versions` function, add:

  ```bash
  _doctor_check_github_mcp() {
    printf "\nGitHub MCP:\n"
    local _mcp_file="${HOME}/.claude/mcp.json"

    # Check generated file exists (not a broken symlink)
    if [[ -L "${_mcp_file}" ]] && [[ ! -e "${_mcp_file}" ]]; then
      doctor_fail "~/.claude/mcp.json" "broken symlink — run: setup_env.sh -t setup_user"
      return
    fi
    if [[ ! -f "${_mcp_file}" ]]; then
      doctor_fail "~/.claude/mcp.json" "missing — run: setup_env.sh -t setup_user"
      return
    fi
    doctor_pass "~/.claude/mcp.json (generated)"

    # Check PAT is set
    if [[ -z "${GITHUB_PAT:-}" ]]; then
      doctor_fail "GITHUB_PAT" "unset — add to config/local.sh: https://github.com/settings/tokens?type=beta"
      return
    fi
    doctor_pass "GITHUB_PAT (set)"

    # Check token is live
    local _curl_rc=0
    curl --max-time 5 --silent --fail \
      -H "Authorization: Bearer ${GITHUB_PAT}" \
      https://api.github.com/user > /dev/null 2>&1 || _curl_rc=$?

    if [[ ${_curl_rc} -eq 22 ]]; then
      doctor_fail "GitHub PAT" "invalid or revoked — rotate at https://github.com/settings/tokens"
    elif [[ ${_curl_rc} -eq 28 ]] || [[ ${_curl_rc} -eq 6 ]]; then
      doctor_warn "GitHub PAT" "network unreachable (offline?) — skipping live check"
    elif [[ ${_curl_rc} -ne 0 ]]; then
      doctor_warn "GitHub PAT" "curl error ${_curl_rc} — skipping live check"
    else
      doctor_pass "GitHub PAT (live)"
    fi

    # Check expiry
    if [[ -z "${GITHUB_PAT_EXPIRY:-}" ]]; then
      log_info "  [INFO] Set GITHUB_PAT_EXPIRY in config/local.sh to enable expiry checks"
      return 0
    fi

    local _expiry_epoch _today_epoch _diff_days
    if [[ -n "${MACOS:-}" ]]; then
      _expiry_epoch=$(date -j -f "%Y-%m-%d" "${GITHUB_PAT_EXPIRY}" +%s 2>/dev/null) || true
    else
      _expiry_epoch=$(date -d "${GITHUB_PAT_EXPIRY}" +%s 2>/dev/null) || true
    fi
    _today_epoch=$(date +%s)

    if [[ -z "${_expiry_epoch:-}" ]]; then
      doctor_warn "GITHUB_PAT_EXPIRY" "could not parse '${GITHUB_PAT_EXPIRY}' — use format YYYY-MM-DD"
      return 0
    fi

    _diff_days=$(( (_expiry_epoch - _today_epoch) / 86400 ))
    if [[ ${_diff_days} -le 0 ]]; then
      doctor_fail "GITHUB_PAT_EXPIRY" "PAT expired on ${GITHUB_PAT_EXPIRY} — rotate at https://github.com/settings/tokens"
    elif [[ ${_diff_days} -le 30 ]]; then
      doctor_warn "GITHUB_PAT_EXPIRY" "expires in ${_diff_days} days (${GITHUB_PAT_EXPIRY}) — rotate at https://github.com/settings/tokens"
    else
      doctor_pass "GITHUB_PAT_EXPIRY (${GITHUB_PAT_EXPIRY}, ${_diff_days} days)"
    fi
  }
  ```

- [ ] **Step 4: Run tests to verify they pass**

  ```bash
  make test 2>&1 | grep -E "(not ok|ok).*github_mcp"
  ```

  Expected: 8 passing, 0 failing.

- [ ] **Step 5: Commit**

  ```bash
  git add lib/helpers.sh tests/setup_env/unit.bats
  git commit -m "feat: add _doctor_check_github_mcp to helpers.sh

  Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
  ```

---

### Task 4: Wire \_doctor_check_github_mcp into run_doctor

**Files:**

- Modify: `lib/helpers.sh` — `run_doctor` function and summary line

- [ ] **Step 1: Write the failing test**

  In `tests/setup_env/unit.bats`, add after the existing `run_doctor` tests
  (after the `run_doctor prints HAS_GUI line` test, ~line 360):

  ```bash
  @test "run_doctor calls _doctor_check_github_mcp" {
    local _called=0
    _doctor_check_github_mcp() { _called=1; }
    # Stub all other sub-checks to avoid side effects
    _doctor_check_symlinks()      { :; }
    _doctor_check_symlink_roots() { :; }
    _doctor_check_tools()         { :; }
    _doctor_check_cred_dirs()     { :; }
    _doctor_check_versions()      { :; }
    run_doctor
    [ "${_called}" -eq 1 ]
  }

  @test "run_doctor summary includes warnings count" {
    _doctor_check_symlinks()      { :; }
    _doctor_check_symlink_roots() { :; }
    _doctor_check_tools()         { :; }
    _doctor_check_cred_dirs()     { :; }
    _doctor_check_versions()      { :; }
    _doctor_check_github_mcp()    { doctor_warn "test" "a warning"; }
    run run_doctor
    [[ "$output" == *"1 warnings"* ]]
  }
  ```

- [ ] **Step 2: Run tests to verify they fail**

  ```bash
  make test 2>&1 | grep "not ok.*run_doctor.*github\|not ok.*run_doctor.*warn"
  ```

  Expected: 2 failing tests.

- [ ] **Step 3: Update run_doctor in helpers.sh**

  In `lib/helpers.sh`, find `run_doctor`:

  ```bash
  run_doctor() {
    _DOCTOR_PASS=0
    _DOCTOR_FAIL=0
    _DOCTOR_FAILED=0
  ```

  Replace the opening block and the checks/summary with:

  ```bash
  run_doctor() {
    _DOCTOR_PASS=0
    _DOCTOR_FAIL=0
    _DOCTOR_FAILED=0
    _DOCTOR_WARN=0
  ```

  Then find the existing calls block:

  ```bash
    _doctor_check_symlinks
    _doctor_check_symlink_roots
    _doctor_check_tools
    _doctor_check_cred_dirs
    _doctor_check_versions

    printf "\n=== Summary ===\n"
    printf "%d checks passed, %d failed\n" "${_DOCTOR_PASS}" "${_DOCTOR_FAIL}"
  ```

  Replace with:

  ```bash
    _doctor_check_symlinks
    _doctor_check_symlink_roots
    _doctor_check_tools
    _doctor_check_cred_dirs
    _doctor_check_versions
    _doctor_check_github_mcp

    printf "\n=== Summary ===\n"
    printf "%d checks passed, %d failed, %d warnings\n" "${_DOCTOR_PASS}" "${_DOCTOR_FAIL}" "${_DOCTOR_WARN}"
  ```

- [ ] **Step 4: Run tests to verify they pass**

  ```bash
  make test 2>&1 | grep -E "(not ok|ok).*(run_doctor.*github|run_doctor.*warn)"
  ```

  Expected: 2 passing, 0 failing. Full suite still passing.

- [ ] **Step 5: Commit**

  ```bash
  git add lib/helpers.sh tests/setup_env/unit.bats
  git commit -m "feat: wire _doctor_check_github_mcp into run_doctor

  Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
  ```

---

### Task 5: Add setup_claude_mcp to workflows.sh

**Files:**

- Modify: `lib/workflows.sh` (add function before `run_setup_user`)
- Modify: `tests/setup_env/workflows.bats` (add tests)

- [ ] **Step 1: Write the failing tests**

  In `tests/setup_env/workflows.bats`, add a new section before the
  `run_setup_user` section:

  ```bash
  # ── setup_claude_mcp ─────────────────────────────────────────────────────────

  @test "setup_claude_mcp generates mcp.json when GITHUB_PAT is set" {
    export GITHUB_PAT="test-token-abc"
    mkdir -p "${PERSONAL_GITREPOS}/${DOTFILES}/.claude"
    printf '{"mcpServers":{"github":{"headers":{"Authorization":"Bearer ${GITHUB_PAT}"}}}}\n' \
      > "${PERSONAL_GITREPOS}/${DOTFILES}/.claude/mcp.json.template"
    setup_claude_mcp
    [[ -f "${HOME}/.claude/mcp.json" ]]
    grep -q "test-token-abc" "${HOME}/.claude/mcp.json"
    ! grep -q '\${GITHUB_PAT}' "${HOME}/.claude/mcp.json"
  }

  @test "setup_claude_mcp returns 0 when GITHUB_PAT is unset" {
    unset GITHUB_PAT
    mkdir -p "${PERSONAL_GITREPOS}/${DOTFILES}/.claude"
    printf '{"mcpServers":{"github":{"headers":{"Authorization":"Bearer ${GITHUB_PAT}"}}}}\n' \
      > "${PERSONAL_GITREPOS}/${DOTFILES}/.claude/mcp.json.template"
    local _rc=0
    setup_claude_mcp || _rc=$?
    [ "${_rc}" -eq 0 ]
  }

  @test "setup_claude_mcp does not create mcp.json when GITHUB_PAT is unset" {
    unset GITHUB_PAT
    mkdir -p "${PERSONAL_GITREPOS}/${DOTFILES}/.claude"
    printf '{"test":"${GITHUB_PAT}"}\n' \
      > "${PERSONAL_GITREPOS}/${DOTFILES}/.claude/mcp.json.template"
    setup_claude_mcp
    [[ ! -f "${HOME}/.claude/mcp.json" ]]
  }

  @test "setup_claude_mcp removes broken symlink before generating file" {
    export GITHUB_PAT="test-token"
    mkdir -p "${PERSONAL_GITREPOS}/${DOTFILES}/.claude"
    printf '{"auth":"Bearer ${GITHUB_PAT}"}\n' \
      > "${PERSONAL_GITREPOS}/${DOTFILES}/.claude/mcp.json.template"
    mkdir -p "${HOME}/.claude"
    # Create broken symlink (points to non-existent file)
    ln -s "${BATS_TEST_TMPDIR}/nonexistent_target" "${HOME}/.claude/mcp.json"
    setup_claude_mcp
    [[ -f "${HOME}/.claude/mcp.json" ]]
    [[ ! -L "${HOME}/.claude/mcp.json" ]]
  }

  @test "setup_claude_mcp returns 1 when envsubst fails" {
    export GITHUB_PAT="test-token"
    mkdir -p "${PERSONAL_GITREPOS}/${DOTFILES}/.claude"
    printf '{"auth":"Bearer ${GITHUB_PAT}"}\n' \
      > "${PERSONAL_GITREPOS}/${DOTFILES}/.claude/mcp.json.template"
    envsubst() { return 1; }
    run setup_claude_mcp
    [ "$status" -eq 1 ]
  }
  ```

- [ ] **Step 2: Run tests to verify they fail**

  ```bash
  make test 2>&1 | grep "not ok.*setup_claude_mcp"
  ```

  Expected: 5 failing tests.

- [ ] **Step 3: Add setup_claude_mcp to workflows.sh**

  In `lib/workflows.sh`, add the following function immediately before `run_setup_user`:

  ```bash
  setup_claude_mcp() {
    local _template="${PERSONAL_GITREPOS}/${DOTFILES}/.claude/mcp.json.template"
    local _output="${HOME}/.claude/mcp.json"
    local _local_config="${PERSONAL_GITREPOS}/${DOTFILES}/config/local.sh"

    # Source config/local.sh to pick up GITHUB_PAT if not already in environment
    if [[ -f "${_local_config}" ]]; then
      # shellcheck disable=SC1090
      source "${_local_config}" || true
    fi

    if [[ -z "${GITHUB_PAT:-}" ]]; then
      log_warn "GITHUB_PAT not set — GitHub MCP not configured"
      log_warn "Add GITHUB_PAT to config/local.sh and re-run: setup_env.sh -t setup_user"
      return 0
    fi

    if ! command -v envsubst &>/dev/null; then
      log_error "envsubst not found — install gettext: brew install gettext or apt-get install gettext-base"
      return 1
    fi

    # Remove broken symlink from old setup if present
    if [[ -L "${_output}" ]] && [[ ! -e "${_output}" ]]; then
      rm -f "${_output}"
    fi

    mkdir -p "$(dirname "${_output}")"
    if ! GITHUB_PAT="${GITHUB_PAT}" envsubst '${GITHUB_PAT}' < "${_template}" > "${_output}"; then
      log_error "Failed to generate ${_output} from template"
      return 1
    fi
    log_info "GitHub MCP configured (${_output})"
  }
  ```

- [ ] **Step 4: Run tests to verify they pass**

  ```bash
  make test 2>&1 | grep -E "(not ok|ok).*setup_claude_mcp"
  ```

  Expected: 5 passing, 0 failing.

- [ ] **Step 5: Commit**

  ```bash
  git add lib/workflows.sh tests/setup_env/workflows.bats
  git commit -m "feat: add setup_claude_mcp to workflows.sh

  Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
  ```

---

### Task 6: Wire setup_claude_mcp into run_setup_user

**Files:**

- Modify: `lib/workflows.sh` — `run_setup_user` function

- [ ] **Step 1: Write the failing test**

  In `tests/setup_env/workflows.bats`, add to the `run_setup_user` section:

  ```bash
  @test "run_setup_user calls setup_claude_mcp" {
    export MACOS=1
    unset LINUX UBUNTU REDHAT FEDORA CENTOS
    local _called=0
    setup_claude_mcp() { _called=1; return 0; }
    run_setup_user
    [ "${_called}" -eq 1 ]
  }

  @test "run_setup_user returns non-zero when setup_claude_mcp fails" {
    export MACOS=1
    unset LINUX UBUNTU REDHAT FEDORA CENTOS
    setup_claude_mcp() { return 1; }
    run run_setup_user
    [ "$status" -ne 0 ]
  }
  ```

- [ ] **Step 2: Run tests to verify they fail**

  ```bash
  make test 2>&1 | grep "not ok.*run_setup_user.*claude\|not ok.*run_setup_user.*mcp"
  ```

  Expected: 2 failing tests.

- [ ] **Step 3: Add setup_claude_mcp call to run_setup_user in workflows.sh**

  In `lib/workflows.sh`, find the end of `run_setup_user` (before the closing `}`
  of the function at ~line 82):

  ```bash
    printf "Creating %s/go-work\\n" "${HOME}"
    mkdir -p ${HOME}/go-work
    if [[ -d ${HOME}/go-work ]]; then
      printf "Created %s/go-work\\n" "${HOME}"
    fi
  }
  ```

  Replace with:

  ```bash
    printf "Creating %s/go-work\\n" "${HOME}"
    mkdir -p ${HOME}/go-work
    if [[ -d ${HOME}/go-work ]]; then
      printf "Created %s/go-work\\n" "${HOME}"
    fi

    setup_claude_mcp || return 1
  }
  ```

- [ ] **Step 4: Run full test suite**

  ```bash
  make test 2>&1 | tail -5
  ```

  Expected: all tests pass.

- [ ] **Step 5: Commit**

  ```bash
  git add lib/workflows.sh tests/setup_env/workflows.bats
  git commit -m "feat: call setup_claude_mcp from run_setup_user

  Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
  ```

---

### Task 7: Update config/local.sh.example

**Files:**

- Modify: `config/local.sh.example`

- [ ] **Step 1: Add GITHUB_PAT vars**

  In `config/local.sh.example`, append the following before the final blank line
  (or at the end):

  ```bash
  # GitHub PAT for Claude Code GitHub MCP server
  # Create at: https://github.com/settings/tokens?type=beta (fine-grained PAT)
  # Required permissions: metadata:read, contents:read, issues:read+write, pull-requests:read+write
  # Repository access: all repos (or specific repos if preferred)
  # export GITHUB_PAT=""
  # export GITHUB_PAT_EXPIRY=""  # ISO date e.g. 2027-04-14 — doctor warns 30 days before expiry
  ```

- [ ] **Step 2: Verify lint passes**

  ```bash
  make lint
  ```

  Expected: exit 0, no errors.

- [ ] **Step 3: Commit**

  ```bash
  git add config/local.sh.example
  git commit -m "chore: add GITHUB_PAT vars to local.sh.example

  Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
  ```

---

### Task 8: Documentation updates

**Files:**

- Modify: `README.md`
- Modify: `CLAUDE.md` (project)
- Modify: `.claude/CLAUDE.md` (global — symlinked to `~/.claude/CLAUDE.md`)
- Modify: `docs/superpowers/README.md`

- [ ] **Step 1: Update README.md**

  Find the existing section structure in `README.md`. Add a new
  `## Claude Code Integration` section (if it doesn't exist) with a subsection:

  ````markdown
  ## Claude Code Integration

  ### GitHub MCP

  Claude Code is configured with the GitHub MCP server for native GitHub operations
  (PR review, issue management, repo browsing) across all projects.

  **One-time setup per machine:**

  1. Create a fine-grained PAT at <https://github.com/settings/tokens?type=beta>
     - Resource owner: your account
     - Repository access: All repositories (or specific repos)
     - Permissions: `Metadata` (read), `Contents` (read), `Issues` (read+write),
       `Pull requests` (read+write)
     - Set expiry: maximum 1 year

  2. Add to `config/local.sh`:

     ```bash
     export GITHUB_PAT="github_pat_..."
     export GITHUB_PAT_EXPIRY="2027-04-14"   # your actual expiry date
     ```
  ````

  3. Run setup:

     ```bash
     ./setup_env.sh -t setup_user
     ```

  4. Verify:

     ```bash
     ./setup_env.sh -t doctor
     ```

  The generated `~/.claude/mcp.json` is not tracked in git — it is regenerated
  from `.claude/mcp.json.template` on each `setup_user` run.

  ```

  ```

- [ ] **Step 2: Update CLAUDE.md (project-level dotfiles)**

  In `CLAUDE.md`, find the `.claude/` symlink section under "Symlink Strategy"
  and update the bullet to note the generated file:

  Find:

  ```
  - **`.claude/`** — each item symlinked individually into `~/.claude/`, preserving any non-repo files already there
  ```

  Replace with:

  ```
  - **`.claude/`** — each item symlinked individually into `~/.claude/`, preserving any non-repo files already there.
    Exception: `mcp.json.template` is symlinked as `~/.claude/mcp.json.template` (read-only reference); the live
    `~/.claude/mcp.json` is **generated** by `setup_claude_mcp` via `envsubst` and is not a symlink.
  ```

  Also update the mock vars table to add two new rows after the `MOCK_TEE_EXIT` row:

  ```markdown
  | `MOCK_CURL_EXIT` | Exit code for `curl` (default: 0); use 22 for HTTP auth failure (FAIL), 28 for timeout (WARN), 6 for DNS failure (WARN) in `_doctor_check_github_mcp` tests |
  ```

  Note: `MOCK_CURL_EXIT` already exists in the table — update its description to
  add the new GitHub MCP context. Do not add a duplicate row.

- [ ] **Step 3: Update .claude/CLAUDE.md (global)**

  In `.claude/CLAUDE.md`, find `## GitHub Actions / CI` and insert a new section
  immediately before it:

  ```markdown
  ## GitHub MCP

  The GitHub MCP server is configured globally (user scope) via `~/.claude/mcp.json`.
  It provides native GitHub operations — PR review, issue management, repo browsing,
  diff access — across all projects without copy-pasting into chat.

  Requires `GITHUB_PAT` to be set in `~/git-repos/personal/dotfiles/config/local.sh`.
  If it isn't set, run `setup_env.sh -t setup_user` after adding the token.
  Verify with `setup_env.sh -t doctor`.

  Use it for:

  - Fetching PR diffs and changed files
  - Reading and creating issues
  - Posting structured review comments
  - Browsing repo contents

  Do not use it to push directly to main/master — normal PR workflow still applies.
  ```

- [ ] **Step 4: Update docs/superpowers/README.md**

  Add row to the All Plans table after the `pr-review-gate` row:

  ```markdown
  | 2026-04-14 | [github-mcp](plans/2026-04-14-github-mcp.md) | [spec](specs/2026-04-14-github-mcp-design.md) | In Progress |
  ```

- [ ] **Step 5: Run full test suite and lint**

  ```bash
  make test
  ```

  Expected: all tests pass, no lint errors.

- [ ] **Step 6: Commit**

  ```bash
  git add README.md CLAUDE.md .claude/CLAUDE.md docs/superpowers/README.md \
      docs/superpowers/plans/2026-04-14-github-mcp.md
  git commit -m "docs: add GitHub MCP setup docs and update plan index

  Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
  ```
