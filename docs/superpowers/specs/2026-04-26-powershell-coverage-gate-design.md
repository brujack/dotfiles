# PowerShell Coverage Gate

**Date:** 2026-04-26
**Status:** Approved, ready for implementation plan
**Standard:** `~/.claude/standards/tdd.md` (≥90% line coverage)

## Goal

Bring `powershell/setup_windows.ps1` to ≥90% line coverage, enforce the floor locally and in CI, and record the figure in `CLAUDE.md`. This is the first of two coverage-compliance plans for the dotfiles repo; the bash/BATS plan follows once this pattern is established.

## Why this first

PowerShell is the smaller, lower-risk surface:

- One product file (`setup_windows.ps1`, 226 lines) vs. ~15 bash files spanning thousands of lines.
- Pester has built-in `-CodeCoverage` support — zero additional tooling install vs. `kcov`/`bashcov` for bash.
- 22 existing Pester tests already in place to extend.
- Closing the gap in a single plan is realistic, which sets a clean precedent for the bash plan.

It also closes an existing CI gap: today PowerShell tests run only via the local pre-push hook and are not exercised on PRs.

## Scope

**In scope:**

- Coverage measurement and gate for `powershell/setup_windows.ps1`.
- New Pester tests to reach ≥90% coverage.
- Local enforcement via `make test` (already invoked by the pre-push hook).
- New `powershell` CI job in `.github/workflows/ci.yml`, added to `auto-merge` dependencies.
- Project-level `CLAUDE.md` documentation of the figure and exclusions.

**Out of scope:**

- Bash/BATS coverage (separate follow-on plan).
- Caching of `Install-Module Pester` in CI.
- Migrating Pester output to Codecov / external coverage services.

## Components

| Component                                  | Change                                                                                                                                                   |
| ------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `powershell/run-tests.ps1`                 | Configure `CodeCoverage` on the Pester run; target `./setup_windows.ps1`; fail if measured coverage < 90%.                                               |
| `powershell/tests/setup_windows.Tests.ps1` | Add tests until measured coverage ≥ 90%, prioritising mandatory test categories from tdd.md (boundary, error path, state transition).                    |
| `.github/workflows/ci.yml`                 | New `powershell` job (ubuntu-latest); installs pwsh + Pester ≥5.0 + PSScriptAnalyzer; runs `cd powershell && make test`. Added to `auto-merge` `needs:`. |
| `CLAUDE.md` (project)                      | New "Coverage" subsection under PowerShell Testing recording the current figure, floor, scope, exclusions, re-measure command.                           |
| `.gitignore`                               | Add `powershell/coverage.xml`.                                                                                                                           |

## Pester coverage configuration

`powershell/run-tests.ps1` Pester block becomes:

```powershell
Import-Module Pester
$config = New-PesterConfiguration
$config.Run.Path = 'tests/'
$config.Run.Exit = $true
$config.Output.Verbosity = 'Detailed'
$config.CodeCoverage.Enabled = $true
$config.CodeCoverage.Path = './setup_windows.ps1'
$config.CodeCoverage.OutputFormat = 'JaCoCo'
$config.CodeCoverage.OutputPath = './coverage.xml'
$config.CodeCoverage.CoveragePercentTarget = 90
$result = Invoke-Pester -Configuration $config -PassThru

if ($null -eq $result.CodeCoverage) {
    Write-Error "Pester returned no CodeCoverage result — verify Pester >= 5.0"
    exit 1
}
if ($result.CodeCoverage.CoveragePercent -lt 90) {
    Write-Error "Coverage $($result.CodeCoverage.CoveragePercent)% is below 90% floor"
    exit 1
}
```

Notes:

- `JaCoCo` XML is the de-facto standard format and is consumable by external tools without conversion if we ever want to wire one in.
- `coverage.xml` is git-ignored.
- `-PassThru` is required: `CoveragePercentTarget` alone affects display but not exit code in Pester 5. The explicit `if` block is the actual gate.
- Null-guard the result so a future Pester regression or wrong version produces an actionable error rather than a silent pass.

## Filling the coverage gap

The plan will (in this order):

1. **Wire up coverage measurement only** — add `CodeCoverage.Enabled`, `Path`, `OutputFormat`, `OutputPath` to `run-tests.ps1`, but _not_ the `if ($result.CodeCoverage.CoveragePercent -lt 90)` gate yet. Run `make test` to capture the baseline percentage.
2. **Read JaCoCo report.** Identify uncovered lines in `setup_windows.ps1`, grouped by function.
3. **Add tests by function.** For each function with uncovered branches, add Pester tests covering happy path (if missing), error paths, boundary conditions, and state transitions per tdd.md's Mandatory Test Categories. Coverage % is a floor — these categories take priority over chasing the percentage with shallow assertions.
4. **Likely focus areas** (based on the file's structure):
   - Error branches (Chocolatey install failure, missing prereqs)
   - Optional Windows feature enable/disable paths
   - COM-object update searcher wrappers (already mockable per CLAUDE.md)
   - Package install loop boundary cases (empty list, single item, all-installed)
5. **Re-measure and iterate** until ≥90%.
6. **Enable the gate.** Flip `run-tests.ps1` to fail <90%.
7. **Record the figure** in `CLAUDE.md`.

If baseline is significantly lower than expected (<60%), the implementer escalates to the user and we may fall back to a hybrid (set gate at baseline initially, add tests until 90%, then raise gate). This is a contingency, not the default plan.

## CI job

New job in `.github/workflows/ci.yml`:

```yaml
powershell:
  runs-on: ubuntu-latest
  env:
    FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: "true"
  steps:
    - uses: actions/checkout@v5
    - name: Install PowerShell
      run: |
        sudo apt-get update
        sudo apt-get install -y wget apt-transport-https software-properties-common
        source /etc/os-release
        wget -q "https://packages.microsoft.com/config/ubuntu/${VERSION_ID}/packages-microsoft-prod.deb"
        sudo dpkg -i packages-microsoft-prod.deb
        sudo apt-get update
        sudo apt-get install -y powershell
    - name: Install Pester + PSScriptAnalyzer
      run: |
        pwsh -Command "Install-Module Pester -Force -Scope CurrentUser -MinimumVersion 5.0"
        pwsh -Command "Install-Module PSScriptAnalyzer -Force -Scope CurrentUser"
    - name: make test
      working-directory: powershell
      run: make test
```

`auto-merge` job: append `powershell` to `needs:` so a PR cannot auto-merge until the PowerShell job (which now includes the coverage gate) passes.

## CLAUDE.md changes

Add a "Coverage" subsection under the existing "PowerShell Testing" section:

```markdown
### Coverage

- **`setup_windows.ps1`: <N>%** (line coverage, measured by Pester `-CodeCoverage`)
- Floor: 90%. CI fails on any drop below the floor.
- Scope: `setup_windows.ps1` only. `run-tests.ps1` and `run-lint.ps1` are excluded as test/lint glue (per tdd.md:84).
- Re-measure: `cd powershell && make test` prints the percentage and writes `coverage.xml`.
- Update this figure whenever tests are added or removed.
```

`<N>%` is replaced with the measured figure during implementation.

## Risks and mitigations

| Risk                                                                                      | Mitigation                                                                                                                   |
| ----------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| Pester `CoveragePercent` field missing or null on older versions                          | `MinimumVersion 5.0` enforced in CI install; explicit null-guard in `run-tests.ps1` produces a clear error.                  |
| New tests must cover Windows-only cmdlets that don't exist on Linux/macOS CI runner       | Existing pattern (CLAUDE.md "Cross-platform test stubs": `function global:CmdletName { }` in `BeforeAll`) extends naturally. |
| `Install-Module Pester` adds ~30s to every CI run                                         | Accepted; caching can be added later if it becomes painful.                                                                  |
| Coverage instrumentation slows local test runs                                            | Measured ~2–3× baseline test time on a 226-line file with 22+ tests; acceptable.                                             |
| Baseline coverage much lower than expected                                                | Implementer escalates; contingency is the hybrid baseline-then-ratchet approach described in "Filling the coverage gap."     |
| Existing tests pass while coverage report shows missing branches that _should_ be covered | Treat as a tdd.md "shallow assertion" finding: replace or strengthen the test rather than adding parallel tests.             |

## Success criteria

- `cd powershell && make test` exits non-zero if coverage drops below 90%.
- A new `powershell` CI job runs on every PR and is a required dependency for `auto-merge`.
- `setup_windows.ps1` measured at ≥90% line coverage.
- The figure is recorded in `CLAUDE.md` and the documented re-measure command produces it.
- No regression in existing 22 tests; no regression in lint.

## Out of scope (explicit non-goals)

- Bash/BATS coverage tooling (`kcov`, `bashcov`) — separate plan after this lands.
- Adding coverage to `tests/setup_windows.Tests.ps1` itself.
- Coverage of `run-tests.ps1` and `run-lint.ps1` (excluded glue).
- External coverage services (Codecov, Coveralls).
- Caching of installed PowerShell modules in CI.
