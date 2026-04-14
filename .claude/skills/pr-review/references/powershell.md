# PowerShell PR Review Reference

## Security

- No `Invoke-Expression` (iex) on untrusted or constructed strings
- No hardcoded credentials — use `SecureString` or secret management (AWS Secrets Manager, etc.)
- `[System.Net.ServicePointManager]::ServerCertificateValidationCallback` not disabled
- Downloaded scripts verified (hash check or signed) before execution
- `-ExecutionPolicy Bypass` not baked into scripts — that's a caller concern
- Sensitive strings not written to verbose/debug streams

## TDD / Tests

- `Pester` is the standard test framework — `Invoke-Pester` must pass
- `Describe` / `It` blocks for all functions with logic
- `Mock` used to isolate external calls (filesystem, registry, network)
- `Assert-MockCalled` to verify interactions where relevant

## Code Quality

- `PSScriptAnalyzer` — must pass with no errors or warnings
  ```powershell
  Invoke-ScriptAnalyzer -Path . -Recurse
  ```
- `[CmdletBinding()]` and `param()` blocks on all functions
- `Write-Verbose` / `Write-Debug` for diagnostic output — not `Write-Host` in library code
- Approved verbs used (`Get-`, `Set-`, `New-`, `Remove-`, etc.)
- `$ErrorActionPreference = 'Stop'` at script top for scripts that must fail fast
- No positional parameters in function calls within scripts — use named parameters

## Logic

- `$null` checks: `if ($null -eq $var)` not `if ($var -eq $null)` (null on left)
- `try/catch/finally` blocks around all external calls
- Pipeline objects typed or documented
- `[OutputType()]` attribute on functions that return values

## Commands to run

```powershell
Invoke-ScriptAnalyzer -Path . -Recurse
Invoke-Pester -Output Detailed
```
