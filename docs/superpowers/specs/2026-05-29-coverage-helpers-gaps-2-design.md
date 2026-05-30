# Coverage: helpers.sh — Gaps 2 Design

## Goal

Raise `helpers.sh` bash coverage from 83% to ≥90% by adding 10 tests for genuinely uncovered code paths. No production code changes required.

## Background

`helpers.sh` contains core brew, doctor, and shell-setup utilities. The 83% baseline was measured 2026-05-28. The uncovered paths were identified by inspecting the source against existing tests in `install_guards.bats` and `unit.bats`.

## Uncovered Paths

| Function                   | Uncovered path                                        | How to reach                       |
| -------------------------- | ----------------------------------------------------- | ---------------------------------- |
| `brew_formula_installed`   | root guard returns 1                                  | MOCK_ID_U=0                        |
| `brew_cask_installed`      | root guard returns 1                                  | MOCK_ID_U=0                        |
| `brew_cask_installed`      | tap-qualified slash path uses `--full-name`           | cask name containing `/`           |
| `brew_update`              | `brew upgrade` (formula) fails → return 1             | MOCK_BREW_UPGRADE_EXIT=1           |
| `brew_update`              | `brew upgrade --cask --greedy` fails → warn, continue | MOCK_BREW_UPGRADE_CASK_EXIT=1      |
| `brew_update`              | `brew cleanup` fails → return 1                       | MOCK_BREW_CLEANUP_EXIT=1           |
| `_doctor_check_github_mcp` | GITHUB_PAT_EXPIRY parse failure                       | GITHUB_PAT_EXPIRY="not-a-date"     |
| `_doctor_check_github_mcp` | PAT expired (`_diff_days ≤ 0`)                        | GITHUB_PAT_EXPIRY past date        |
| `_doctor_check_tools`      | Linux/Ubuntu apt-get found                            | LINUX=1, UBUNTU=1, apt-get in PATH |
| `_doctor_check_tools`      | Linux/Ubuntu apt-get missing                          | LINUX=1, UBUNTU=1, minimal PATH    |

`setup_zsh_as_default_shell` "not executable" branch is intentionally skipped — `ZSH_PATH` is hardcoded inside the function with no override seam, making it untestable without a production code change.

## Files Changed

### `tests/mocks/brew`

Add `MOCK_BREW_UPGRADE_CASK_EXIT` support so formula and cask upgrade can fail independently:

```bash
upgrade)
  if [[ "$*" == *"--cask"* ]]; then
    exit "${MOCK_BREW_UPGRADE_CASK_EXIT:-${MOCK_BREW_UPGRADE_EXIT:-0}}"
  fi
  exit "${MOCK_BREW_UPGRADE_EXIT:-0}"
  ;;
```

Fallback chain: `MOCK_BREW_UPGRADE_CASK_EXIT` → `MOCK_BREW_UPGRADE_EXIT` → 0. This is backward-compatible: existing tests that set `MOCK_BREW_UPGRADE_EXIT=1` still fail both `upgrade` and `upgrade --cask`.

### `tests/setup_env/install_guards.bats` — 6 new tests

Append after existing `brew_formula_installed` tests:

**Test 1:** `brew_formula_installed returns 1 when root`

```bash
export MOCK_ID_U=0
run brew_formula_installed git
[ "$status" -eq 1 ]
```

Append after existing `brew_cask_installed` tests:

**Test 2:** `brew_cask_installed returns 1 when root`

```bash
export MOCK_ID_U=0
run brew_cask_installed docker
[ "$status" -eq 1 ]
```

**Test 3:** `brew_cask_installed uses full-name flag for tap-qualified casks`

```bash
export MOCK_BREW_LIST_CASK="hashicorp/tap/vault-secrets-operator"
run brew_cask_installed hashicorp/tap/vault-secrets-operator
[ "$status" -eq 0 ]
grep -q "brew list --cask --full-name" "${MOCK_CALLS_FILE}"
```

Append after existing `brew_update` tests:

**Test 4:** `brew_update returns 1 when brew upgrade fails`

```bash
export MOCK_ID_U=1000
export MOCK_BREW_UPGRADE_EXIT=1
run brew_update
[ "$status" -eq 1 ]
[[ "$output" == *"Failed to upgrade formulae"* ]]
```

**Test 5:** `brew_update warns but continues when cask upgrade fails`

```bash
export MOCK_ID_U=1000
export MOCK_BREW_UPGRADE_CASK_EXIT=1
run brew_update
[ "$status" -eq 0 ]
[[ "$output" == *"Some casks failed to upgrade"* ]]
[[ "$output" == *"Homebrew update process completed successfully"* ]]
```

**Test 6:** `brew_update returns 1 when brew cleanup fails`

```bash
export MOCK_ID_U=1000
export MOCK_BREW_CLEANUP_EXIT=1
run brew_update
[ "$status" -eq 1 ]
[[ "$output" == *"Failed to clean up"* ]]
```

### `tests/setup_env/unit.bats` — 4 new tests

Append after existing `_doctor_check_github_mcp` tests:

**Test 7:** `_doctor_check_github_mcp warns when GITHUB_PAT_EXPIRY cannot be parsed`

Setup: mcp.json present, GITHUB_PAT set, curl exits 0, GITHUB_PAT_EXPIRY set to an unparseable value. Direct call (not `run`) so `_DOCTOR_WARN` flag is visible.

```bash
_DOCTOR_FAIL=0; _DOCTOR_FAILED=0; _DOCTOR_PASS=0; _DOCTOR_WARN=0
export GITHUB_PAT="fake-token"
mkdir -p "${HOME}/.claude"
printf '{"mcpServers":{}}\n' > "${HOME}/.claude/mcp.json"
export MOCK_CURL_EXIT=0
export GITHUB_PAT_EXPIRY="not-a-date"
_doctor_check_github_mcp
[ "${_DOCTOR_WARN}" -ge 1 ]
```

**Test 8:** `_doctor_check_github_mcp fails when GITHUB_PAT has expired`

GITHUB_PAT_EXPIRY set to a past date. `_diff_days` will be negative → `doctor_fail`.

```bash
_DOCTOR_FAIL=0; _DOCTOR_FAILED=0; _DOCTOR_PASS=0; _DOCTOR_WARN=0
export GITHUB_PAT="fake-token"
mkdir -p "${HOME}/.claude"
printf '{"mcpServers":{}}\n' > "${HOME}/.claude/mcp.json"
export MOCK_CURL_EXIT=0
export GITHUB_PAT_EXPIRY="2020-01-01"
_doctor_check_github_mcp
[ "${_DOCTOR_FAILED}" -ge 1 ]
```

Append after existing `_doctor_check_tools` tests (the ones using overridden implementations):

**Test 9:** `_doctor_check_tools passes apt-get when found on Ubuntu`

```bash
_DOCTOR_FAIL=0; _DOCTOR_FAILED=0; _DOCTOR_PASS=0; _DOCTOR_WARN=0
export LINUX=1; export UBUNTU=1; unset MACOS
_doctor_check_tools
# apt-get is in tests/mocks/ — should be found
# All common tools in PATH too; assert no failure from apt-get check
# (common tools pass; apt-get passes; _DOCTOR_FAILED is 0)
[ "${_DOCTOR_FAILED}" -eq 0 ]
```

**Test 10:** `_doctor_check_tools fails when apt-get is missing on Ubuntu`

Use filtered mocks dir (all mocks except apt-get). Minimal PATH ensures apt-get is not found on any platform including Ubuntu Noble (where `/bin → /usr/bin` symlink would otherwise bypass directory stripping). Restore PATH immediately after call.

```bash
_DOCTOR_FAIL=0; _DOCTOR_FAILED=0; _DOCTOR_PASS=0; _DOCTOR_WARN=0
export LINUX=1; export UBUNTU=1; unset MACOS
local _saved_path="$PATH"
local _mocks_dir; _mocks_dir="$(cd "${BATS_TEST_DIRNAME}/../mocks" && pwd)"
local _tmp="${BATS_TEST_TMPDIR}/mocks_no_apt"
mkdir -p "${_tmp}"
for f in "${_mocks_dir}/"*; do
  [[ "$(basename "$f")" == "apt-get" ]] && continue
  ln -sf "$f" "${_tmp}/$(basename "$f")"
done
export PATH="${_tmp}"
_doctor_check_tools
export PATH="${_saved_path}"
[ "${_DOCTOR_FAILED}" -ge 1 ]
```

## Test Count

10 new tests. Expected total: 683 + 10 = 693 BATS tests. `helpers.sh` coverage: 83% → ≥90%.

## Not In Scope

- `setup_zsh_as_default_shell` "not executable" branch (no test seam)
- `_doctor_check_github_mcp` broken symlink / missing mcp.json (already covered)
- Any refactoring of helpers.sh
