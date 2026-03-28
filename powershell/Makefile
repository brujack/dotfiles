.PHONY: test lint help

help:
	@printf "Available targets:\n"
	@printf "  make test   Run Pester tests (requires pwsh, Pester v5)\n"
	@printf "  make lint   Run PSScriptAnalyzer on setup_windows.ps1\n"
	@printf "  make help   Show this help\n"

lint:
	pwsh -NoProfile -Command 'Import-Module PSScriptAnalyzer; $$r = Invoke-ScriptAnalyzer -Path ./setup_windows.ps1 -Settings ./PSScriptAnalyzerSettings.psd1; if ($$r) { $$r | Format-Table -AutoSize; exit 1 }'

test:
	pwsh -NoProfile -Command '\
		Import-Module PSScriptAnalyzer; \
		$$r = Invoke-ScriptAnalyzer -Path ./setup_windows.ps1 -Settings ./PSScriptAnalyzerSettings.psd1; \
		if ($$r) { $$r | Format-Table -AutoSize; exit 1 }; \
		Import-Module Pester; \
		$$config = New-PesterConfiguration; \
		$$config.Run.Path = "tests/"; \
		$$config.Output.Verbosity = "Detailed"; \
		$$config.Run.Exit = $$true; \
		Invoke-Pester -Configuration $$config'
