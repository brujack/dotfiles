.PHONY: test lint help

help:
	@printf "Available targets:\n"
	@printf "  make test   Run PSScriptAnalyzer lint then Pester tests\n"
	@printf "  make lint   Run PSScriptAnalyzer on setup_windows.ps1\n"
	@printf "  make help   Show this help\n"

lint:
	pwsh -Command 'Import-Module PSScriptAnalyzer; $$r = Invoke-ScriptAnalyzer -Path ./setup_windows.ps1 -Settings ./PSScriptAnalyzerSettings.psd1; if ($$r) { $$r | Format-Table -AutoSize; exit 1 }'

test:
	pwsh -File ./run-tests.ps1
