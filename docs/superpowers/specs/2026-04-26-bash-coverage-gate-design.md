# Bash/BATS Coverage Gate

**Date:** 2026-04-26
**Status:** Approved, ready for implementation plan
**Standard:** `~/.claude/standards/tdd.md` (≥90% line coverage)

## Goal

Bring all bash source files (`setup_env.sh` + `lib/*.sh`) to per-file coverage floors, enforce those floors in CI, and record the figures in `CLAUDE.md`. This is the second of two coverage-compliance plans for the dotfiles repo; the PowerShell gate (PR #45) established the pattern.

## Why this second

- Larger surface: 9 files, 3,408 lines vs. one 226-line PowerShell file.
- No built-in coverage support in BATS — requires an external tool (kcov).
- Platform-specific files (`linux.sh`, `macos.sh`) warrant lower floors due to OS-locked branches.
- The PowerShell plan proved the pattern (measure → iterate → gate → document); this plan follows the same sequence.

## Scope

**In scope:**

- Coverage measurement and gate for `setup_env.sh` and all `lib/*.sh` files (9 files total).
- `scripts/run-coverage.sh` — new script that runs kcov and enforces per-file floors.
- New `make coverage` target in the root Makefile.
- New `bash-coverage` CI job in `.github/workflows/ci.yml`, added to `auto-merge` dependencies.
- New tests to close any gap between baseline and floor for each file.
- Project-level `CLAUDE.md` documentation of per-file figures and floors.

**Out of scope:**

- `tests/` files — test glue is not measured.
- `scripts/` files other than the new `run-coverage.sh`.
- `.devcontainer/` shell configs.
- Caching of kcov in CI.
- External coverage services (Codecov, Coveralls).
- Local enforcement via pre-push hook — `make test` is unchanged; kcov is CI-only.

## Components

| Component                  | Change                                                                                                                                                |
| -------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| `scripts/run-coverage.sh`  | New: runs kcov over full BATS suite; parses `coverage/kcov-merged/index.json`; checks per-file floors; prints pass/fail table; exits 1 on any failure |
| `Makefile`                 | New `coverage` target: calls `scripts/run-coverage.sh` if kcov present; prints skip message and exits 0 if absent (same pattern as shellcheck)        |
| `.github/workflows/ci.yml` | New `bash-coverage` job (ubuntu-latest); installs bats + shellcheck + zsh + kcov + jq; runs `make coverage`; added to `auto-merge needs:`             |
| `CLAUDE.md`                | New "Bash Coverage" subsection under "Testing" with per-file table, floors, re-measure command                                                        |
| `.gitignore`               | Add `coverage/`                                                                                                                                       |

## Coverage floors

| File                    | Floor | Rationale                                                                     |
| ----------------------- | ----- | ----------------------------------------------------------------------------- |
| `setup_env.sh`          | 90%   | Cross-platform entry point; already well-tested                               |
| `lib/constants.sh`      | 90%   | Declarations; trivially covered when sourced                                  |
| `lib/detect_env.sh`     | 90%   | Cross-platform env detection                                                  |
| `lib/helpers.sh`        | 90%   | Most-tested file; has dedicated test suite                                    |
| `lib/workflows.sh`      | 90%   | Has 1054-line workflow test suite                                             |
| `lib/update_summary.sh` | 90%   | Has 624-line test suite                                                       |
| `lib/developer.sh`      | 90%   | Cross-platform dev tools                                                      |
| `lib/linux.sh`          | 75%   | Platform-specific Ubuntu/RHEL/CentOS paths; many branches require OS presence |
| `lib/macos.sh`          | 75%   | macOS-only; CI runs on Ubuntu; branches require mock investment               |

## `scripts/run-coverage.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${REPO_ROOT}/coverage"

declare -A FLOORS=(
  ["setup_env.sh"]=90
  ["constants.sh"]=90
  ["detect_env.sh"]=90
  ["helpers.sh"]=90
  ["workflows.sh"]=90
  ["update_summary.sh"]=90
  ["developer.sh"]=90
  ["linux.sh"]=75
  ["macos.sh"]=75
)

INCLUDE_PATH="${REPO_ROOT}/setup_env.sh:${REPO_ROOT}/lib"

rm -rf "${OUTPUT_DIR}"
kcov --include-path="${INCLUDE_PATH}" "${OUTPUT_DIR}" bats --recursive "${REPO_ROOT}/tests/"

INDEX="${OUTPUT_DIR}/kcov-merged/index.json"
if [[ ! -f "${INDEX}" ]]; then
  printf "ERROR: kcov did not produce %s — verify kcov version\n" "${INDEX}" >&2
  exit 1
fi

failed=0
printf "\n%-30s %10s %10s %10s\n" "File" "Coverage" "Floor" "Status"
printf "%-30s %10s %10s %10s\n" "----" "--------" "-----" "------"

while IFS= read -r file_json; do
  filepath=$(printf '%s' "${file_json}" | jq -r '.file')
  percent=$(printf '%s' "${file_json}" | jq -r '.percent_covered')
  basename="${filepath##*/}"
  floor="${FLOORS[${basename}]:-90}"
  pct_int=$(printf '%.0f' "${percent}")
  if [[ "${pct_int}" -lt "${floor}" ]]; then
    status="FAIL"
    failed=1
  else
    status="PASS"
  fi
  printf "%-30s %9s%% %9s%% %10s\n" "${basename}" "${pct_int}" "${floor}" "${status}"
done < <(jq -c '.files[]' "${INDEX}")

if [[ "${failed}" -ne 0 ]]; then
  printf "\nCoverage gate FAILED — one or more files below floor\n" >&2
  exit 1
fi
printf "\nCoverage gate PASSED\n"
```

Notes:

- `--include-path` limits the report to source files only (excludes bats internals, test helpers, mock scripts).
- Basename matching handles the fact that kcov stores absolute paths in `index.json`.
- Unknown files (not in `FLOORS`) default to 90%.
- The null-guard on `index.json` produces an actionable error rather than a silent pass if kcov regresses.
- If a source file is never sourced during any test, kcov may omit it from `index.json` entirely — its floor would be silently skipped. The implementer must verify all 9 expected files appear in the baseline report and add at least one test that sources any missing file.

## Makefile addition

```makefile
KCOV := $(shell command -v kcov 2>/dev/null)

coverage:
ifeq ($(KCOV),)
	@printf "kcov not found — skipping coverage (CI enforces the gate). Install: brew install kcov\n"
else
	@bash scripts/run-coverage.sh
endif
```

`make test` is unchanged. `make coverage` is a standalone target, not called by `make test`.

## CI job

New job in `.github/workflows/ci.yml` (inserted between `powershell` and `secret-scan`):

```yaml
bash-coverage:
  runs-on: ubuntu-latest
  env:
    FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: "true"
  steps:
    - uses: actions/checkout@v5
    - name: Install dependencies
      run: sudo apt-get install -y bats shellcheck zsh kcov jq
    - name: Run coverage gate
      run: make coverage
```

`auto-merge needs:` changes from `[test, lint-macos, powershell, secret-scan]` to `[test, lint-macos, powershell, bash-coverage, secret-scan]`.

The `bash-coverage` job is self-contained (installs its own bats/shellcheck/zsh) and has no ordering dependency on the `test` job.

## Filling the coverage gap

The plan follows the same sequence as the PowerShell gate:

1. **Wire up measurement only** — add `scripts/run-coverage.sh` and `make coverage` without the `exit 1` gate. Run `make coverage` in CI to capture baseline per-file percentages.
2. **Read the report.** Identify uncovered lines per file. Group by function.
3. **Add tests by function.** For each file below its floor, add BATS tests covering happy path (if missing), error paths, boundary conditions, and state transitions per tdd.md's Mandatory Test Categories.
4. **Likely focus areas** (based on file sizes and existing test coverage):
   - `lib/linux.sh`: RHEL/CentOS/Fedora install paths not yet exercised; mock-based tests needed
   - `lib/macos.sh`: macOS-specific Homebrew and cask paths
   - `lib/developer.sh`: tool install guards and virtualenv paths
5. **Re-measure and iterate** until all files meet their floor.
6. **Enable the gate.** Flip `scripts/run-coverage.sh` to exit 1 on failure.
7. **Record figures** in `CLAUDE.md`.

If any file's baseline is above its floor already, the gate is enabled immediately for that file. If a file's baseline is significantly lower than the floor (>20 points gap), escalate to the user before writing tests — the floor may need adjustment.

## CLAUDE.md changes

New "Bash Coverage" subsection under the existing "Testing" section:

```markdown
### Bash Coverage

- Floor: 90% for cross-platform files, 75% for platform-specific files. CI fails on any drop below the floor.
- Re-measure: `make coverage` prints the per-file table and writes `coverage/`. Requires kcov (`brew install kcov` locally; installed automatically in CI).
- Update the figures below whenever tests are added or removed.

| File                    | Coverage | Floor |
| ----------------------- | -------- | ----- |
| `setup_env.sh`          | <N>%     | 90%   |
| `lib/constants.sh`      | <N>%     | 90%   |
| `lib/detect_env.sh`     | <N>%     | 90%   |
| `lib/helpers.sh`        | <N>%     | 90%   |
| `lib/workflows.sh`      | <N>%     | 90%   |
| `lib/update_summary.sh` | <N>%     | 90%   |
| `lib/developer.sh`      | <N>%     | 90%   |
| `lib/linux.sh`          | <N>%     | 75%   |
| `lib/macos.sh`          | <N>%     | 75%   |
```

`<N>%` values are filled in during implementation after baseline measurement.

## Risks and mitigations

| Risk                                                | Mitigation                                                                                                                                         |
| --------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| kcov on macOS ARM64 is unreliable                   | Gate is CI-only (ubuntu-latest); local `make coverage` skips gracefully if kcov absent                                                             |
| kcov does not trace sourced files in BATS `setup()` | kcov uses `LD_PRELOAD` on Linux to trace the full process tree including subshells; sourced files are covered. Verify during baseline measurement. |
| `index.json` format changes between kcov versions   | Null-guard + explicit error message; CI pins to whatever `apt-get install kcov` provides on ubuntu-latest                                          |
| Baseline much lower than floor for some files       | Implementer escalates; floor may be lowered for that file or a hybrid baseline-then-ratchet approach used                                          |
| New tests for `linux.sh` require heavy mocking      | Existing mock infrastructure (PATH-injected mocks, `MOCK_*` env vars) is already in place and well-documented in `CLAUDE.md`                       |
| Source file absent from kcov report = silent pass   | Verify all 9 files appear in baseline `index.json`; add a sourcing test for any that are missing before enabling the gate                          |

## Success criteria

- `make coverage` exits non-zero in CI if any file drops below its floor.
- A new `bash-coverage` CI job runs on every PR and is a required dependency for `auto-merge`.
- All 9 source files at or above their documented floor.
- Per-file figures recorded in `CLAUDE.md` with the documented re-measure command.
- No regression in existing BATS tests; `make test` still passes.

## Out of scope (explicit non-goals)

- Local enforcement via pre-push hook.
- Coverage of `scripts/run-coverage.sh` itself.
- Coverage of test files (`tests/`).
- External coverage services.
- Caching of kcov in CI.
- Bash coverage for `.devcontainer/` shell configs.
